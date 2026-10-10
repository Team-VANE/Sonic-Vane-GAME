extends Node

const OVERLAY_SCRIPT: Script = preload("res://LS5Framework/Scripts/UI/SceneDiagnosticOverlay.gd")
const REPORT_PATH: String = "user://scene_diagnostics.log"
const DEPENDENCY_ERROR_LOG_PATH: String = "user://scene_dependency_errors.log"
const MAX_DEPENDENCY_RESOURCES: int = 8192
const DEPENDENCY_FRAME_BUDGET_USEC: int = 2000
const CHECK_INTERVAL: float = 0.5
const SETTLING_TIME: float = 3.0
const REQUIRED_BAD_CHECKS: int = 3

var _overlay: CanvasLayer = null
var _timer: Timer = null
var _scene_id: int = 0
var _level_id: int = 0
var _settle_until_msec: int = 0
var _candidate_signature: String = ""
var _bad_checks: int = 0
var _displayed_signature: String = ""
var _events: Array[Dictionary] = []
var _load_issue: Dictionary = {}
var _preview_active: bool = false
var _last_report: Dictionary = {}
var _dependency_scan_generation: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LevelPreparationManager.level_preparation_started.connect(_on_preparation_started)
	LevelPreparationManager.level_preparation_failed.connect(_on_preparation_failed)
	LevelPreparationManager.level_preparation_completed.connect(_on_preparation_completed)
	get_tree().scene_changed.connect(_on_scene_changed)
	_timer = Timer.new()
	_timer.wait_time = CHECK_INTERVAL
	_timer.timeout.connect(_check_scene)
	add_child(_timer)
	_timer.start()

func record_event(source: String, reason: String, resource_path: String = "") -> void:
	_events.append({"source": source, "reason": reason, "resource": resource_path, "time_msec": Time.get_ticks_msec()})
	if _events.size() > 24:
		_events.pop_front()

func report_loading_problem(reason: String, scene_path: String, stalled: bool = false) -> void:
	record_event("LoadingScreen", reason, scene_path)
	_load_issue = _issue(
		"LOAD_STALLED" if stalled else "LOAD_FAILED",
		"Loading stopped making progress" if stalled else "Scene loading failed",
		reason,
		"A slow disk or unresolved resource request can cause a stall; a stall alone does not prove a missing file." if stalled else "Verify the game's Data packs and inspect level_load.log for the failed resource.",
		"Observed" if stalled else "Confirmed"
	)
	_present([_load_issue], {"level_scene": scene_path, "scene": _current_scene_path()})

func _on_preparation_started(_generation: int, scene_path: String) -> void:
	_load_issue.clear()
	_reset_candidate()
	_clear_display()
	record_event("LevelPreparation", "Preparing scene", scene_path)

func _on_preparation_failed(_generation: int, scene_path: String, reason: String) -> void:
	report_loading_problem(reason, scene_path)

func _on_preparation_completed(_generation: int, _scene_path: String) -> void:
	_load_issue.clear()
	_clear_display()
	_reset_candidate()

func clear_loading_stall() -> void:
	if String(_load_issue.get("code", "")) != "LOAD_STALLED":
		return
	_load_issue.clear()
	_clear_display()

func _on_scene_changed() -> void:
	_scene_id = 0
	_level_id = 0
	_reset_candidate()
	_load_issue.clear()
	_clear_display()

func _reset_candidate() -> void:
	_settle_until_msec = Time.get_ticks_msec() + roundi(SETTLING_TIME * 1000.0)
	_candidate_signature = ""
	_bad_checks = 0

func _current_scene_path() -> String:
	var scene: Node = get_tree().current_scene
	return scene.scene_file_path if is_instance_valid(scene) else ""

func _check_scene() -> void:
	if _preview_active:
		return
	var scene: Node = get_tree().current_scene
	if not is_instance_valid(scene):
		return
	if _scene_id != scene.get_instance_id():
		_scene_id = scene.get_instance_id()
		_reset_candidate()
	var manager: Node = get_tree().get_first_node_in_group("LevelManager")
	if not is_instance_valid(manager) or not manager.has_method("get_current_level"):
		if _load_issue.is_empty():
			_clear_display()
		return
	if manager.has_method("is_level_loading") and manager.call("is_level_loading"):
		return
	var level: Node = manager.call("get_current_level")
	var level_instance_id: int = level.get_instance_id() if is_instance_valid(level) else 0
	if _level_id != level_instance_id:
		_level_id = level_instance_id
		_reset_candidate()
	if not _load_issue.is_empty():
		return
	if Time.get_ticks_msec() < _settle_until_msec:
		return
	var session: Node = get_tree().get_first_node_in_group("NetworkSession")
	var player: Node = null
	var level_path: String = String(manager.call("get_current_level_scene_path")) if manager.has_method("get_current_level_scene_path") else ""
	var context: Dictionary = {"scene": scene.scene_file_path, "level_scene": level_path}
	if is_instance_valid(session) and session.has_method("get_local_player"):
		player = session.call("get_local_player")
		if session.has_method("get_scene_diagnostic_context"):
			context.merge(session.call("get_scene_diagnostic_context"))
	else:
		player = manager.call("_get_local_player") if manager.has_method("_get_local_player") else get_tree().get_first_node_in_group("Player")
	var rig: Node = null
	if _live_node(player) and "camera_rig" in player:
		var rig_value: Variant = player.get("camera_rig")
		if _live_node(rig_value):
			rig = rig_value
	if not _live_node(rig):
		rig = get_tree().get_first_node_in_group("CameraRig")
	var active_camera: Camera3D = get_viewport().get_camera_3d()
	context["player"] = _node_path(player)
	context["rig"] = _node_path(rig)
	context["active_camera"] = _node_path(active_camera)
	context["viewport_3d_disabled"] = get_viewport().disable_3d
	var issues: Array[Dictionary] = inspect_scene(level, player, rig, active_camera, context)
	var pack_manager: Node = get_tree().get_first_node_in_group("ContentPackManager")
	if not OS.has_feature("editor") and is_instance_valid(pack_manager) and pack_manager.has_method("get_data_directory"):
		context["data_directory"] = String(pack_manager.call("get_data_directory"))
		if String(context["data_directory"]).is_empty():
			issues.push_front(_issue("DATA_MISSING", "Required Data folder is unavailable", "The content-pack manager could not resolve the game's Data directory.", "Place the matching Data folder beside the game application, then restart."))
	if issues.is_empty():
		_candidate_signature = ""
		_bad_checks = 0
		_clear_display()
		return
	var signature: String = _signature(issues, context)
	if signature != _candidate_signature:
		_candidate_signature = signature
		_bad_checks = 0
	_bad_checks += 1
	if _bad_checks >= REQUIRED_BAD_CHECKS:
		_present(issues, context)

func inspect_scene(level_value: Variant, player_value: Variant, rig_value: Variant, camera_value: Variant, context: Dictionary = {}) -> Array[Dictionary]:
	var level: Node = level_value if _live_node(level_value) else null
	var player: Node = player_value if _live_node(player_value) else null
	var rig: Node = rig_value if _live_node(rig_value) else null
	var active_camera: Camera3D = camera_value if _live_node(camera_value) and camera_value is Camera3D else null
	var issues: Array[Dictionary] = []
	if not _live_node(level):
		issues.append(_issue("LEVEL_MISSING", "Level scene is not present", "A gameplay shell is running, but its level manager has no live level instance.", "Check the selected level path and the last loading/preparation error."))
	if not _live_node(player):
		var reason: String = String(context.get("spawn_failure", "The local player node is missing or was removed from the scene tree."))
		if reason.is_empty():
			reason = "The local player node is missing or was removed from the scene tree."
		issues.append(_issue("PLAYER_MISSING", "Local player did not spawn", reason, "Check the selected character scene and character-pack dependencies. A missing player alone does not identify which file failed."))
		for scene_path: String in context.get("character_scene_paths", []):
			if not ResourceLoader.exists(scene_path):
				issues.append(_issue("CHARACTER_RESOURCE_MISSING", "Selected character scene is unavailable", scene_path, "Restore the matching characters pack and its required shared resources."))
	if bool(context.get("viewport_3d_disabled", false)):
		issues.append(_issue("VIEWPORT_3D_DISABLED", "Gameplay viewport has 3D disabled", "The main viewport is configured not to render 3D content.", "Check the viewport's disable_3d property and display setup."))
	if not _live_node(active_camera):
		issues.append(_issue("CAMERA_INACTIVE", "No active gameplay camera", "The main gameplay viewport has no current Camera3D.", "Check the camera node, its viewport and current-camera assignment."))
	if not _live_node(rig):
		issues.append(_issue("CAMERA_RIG_MISSING", "Player camera rig is missing", "No live camera rig could be resolved for the local player.", "Check NetworkSession's camera rig path and the player's camera reference."))
	else:
		var expected_value: Variant = rig.get("camera") if "camera" in rig else null
		var expected_camera: Camera3D = expected_value if _live_node(expected_value) and expected_value is Camera3D else null
		if not _live_node(expected_camera):
			issues.append(_issue("CAMERA_NODE_MISSING", "Camera rig has no camera", "The rig's Camera3D reference is absent or no longer valid.", "Check CameraYawRig / CameraPitchRig / SonicCamera and its exported reference."))
		elif _live_node(active_camera) and active_camera != expected_camera and not active_camera.is_in_group("SceneDiagnosticsCameraOverride"):
			issues.append(_issue("CAMERA_WRONG_CURRENT", "A different camera is rendering", "Current: %s. Expected: %s." % [_node_path(active_camera), _node_path(expected_camera)], "Check which camera became current. Register intentional cinematic cameras in SceneDiagnosticsCameraOverride."))
		if _live_node(player) and "target" in rig and rig.get("target") != player and not (_live_node(active_camera) and active_camera.is_in_group("SceneDiagnosticsCameraOverride")):
			issues.append(_issue("CAMERA_TARGET_MISMATCH", "Camera is not following the local player", "Rig target: %s. Local player: %s." % [_node_path(rig.get("target")), _node_path(player)], "Check local-player camera assignment after spawning or switching character."))
	if _live_node(player) and player is Node3D and (not (player as Node3D).global_position.is_finite() or not (player as Node3D).global_basis.is_finite()):
		issues.append(_issue("PLAYER_TRANSFORM_INVALID", "Player transform is invalid", "The player's world position or orientation contains a non-finite value.", "Inspect the last teleport, spawn transform and movement update."))
	if _live_node(active_camera) and (not active_camera.global_position.is_finite() or not active_camera.global_basis.is_finite()):
		issues.append(_issue("CAMERA_TRANSFORM_INVALID", "Camera transform is invalid", "The active camera's world position or orientation contains a non-finite value.", "Inspect the camera target and active constraint transforms."))
	if _live_node(active_camera) and active_camera.cull_mask == 0:
		issues.append(_issue("CAMERA_LAYERS_EMPTY", "Active camera renders no 3D layers", "The active Camera3D has an empty cull mask.", "Restore the world and player render layers on the gameplay camera."))
	return issues

func _live_node(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and node.is_inside_tree() and not node.is_queued_for_deletion()

func _node_path(node: Variant) -> String:
	return String(node.get_path()) if _live_node(node) else "<missing>"

func _issue(code: String, title: String, detail: String, suggestion: String, confidence: String = "Confirmed") -> Dictionary:
	return {"code": code, "title": title, "detail": detail, "suggestion": suggestion, "confidence": confidence}

func _signature(issues: Array, context: Dictionary) -> String:
	return JSON.stringify({"issues": issues, "level": context.get("level_scene", ""), "character": context.get("selected_character", "")})

func _present(issues: Array, context: Dictionary) -> void:
	if _preview_active:
		return
	var signature: String = _signature(issues, context)
	if signature == _displayed_signature:
		return
	_displayed_signature = signature
	_last_report = {
		"generated": Time.get_datetime_string_from_system(), "engine": Engine.get_version_info(),
		"executable": OS.get_executable_path().get_file(), "context": context.duplicate(true),
		"issues": issues.duplicate(true), "recent_events": _events.duplicate(true),
		"preparation_state": LevelPreparationManager.get_preparation_state(),
		"preparation_failure": LevelPreparationManager.get_failure_reason(),
		"failed_resources": LevelPreparationManager.get_failed_resources(),
		"runtime_cache_misses": LevelPreparationManager.get_runtime_cache_misses()
	}
	_dependency_scan_generation += 1
	_last_report["dependency_scan"] = {"state": "Scanning", "entries": []}
	var log_saved: bool = _write_report()
	_ensure_overlay()
	_overlay.call("show_report", _last_report, log_saved)
	_complete_dependency_report(_dependency_scan_generation, _last_report.duplicate(true))

func _write_report() -> bool:
	var file: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	var log_saved: bool = file != null
	var dependency_file: FileAccess = FileAccess.open(DEPENDENCY_ERROR_LOG_PATH, FileAccess.WRITE)
	if dependency_file:
		dependency_file.store_line("Sonic Vane dependency error report — " + String(_last_report.get("generated", "")))
		dependency_file.store_line("Context: " + JSON.stringify(_last_report.get("context", {})))
		for issue: Dictionary in _last_report.get("issues", []):
			dependency_file.store_line("%s: %s" % [issue.get("code", ""), issue.get("detail", "")])
		var scan: Dictionary = _last_report.get("dependency_scan", {})
		dependency_file.store_line("Dependency scan: %s; examined: %d" % [scan.get("state", "Pending"), scan.get("examined", 0)])
		for entry: Dictionary in scan.get("entries", []):
			dependency_file.store_line("\n[%s] %s\nReason: %s\nReferenced by: %s" % [entry.status, entry.path, entry.reason, ", ".join(entry.owners)])
		if scan.get("entries", []).is_empty():
			dependency_file.store_line("No missing dependencies identified. This does not prove that all resources loaded correctly.")
	_last_report["dependency_error_log_saved"] = dependency_file != null
	if file:
		file.store_line("Sonic Vane scene diagnostic report")
		file.store_line(JSON.stringify(_last_report, "\t"))
	return log_saved

func _complete_dependency_report(generation: int, report: Dictionary) -> void:
	var roots: PackedStringArray = []
	var context: Dictionary = report.get("context", {})
	for key: String in ["scene", "level_scene"]:
		var path: String = String(context.get(key, ""))
		if not path.is_empty():
			roots.append(path)
	for path: String in context.get("character_scene_paths", []):
		roots.append(path)
	var failed: Dictionary = report.get("failed_resources", {})
	for path: String in failed:
		roots.append(path)
	var scan: Dictionary = await inspect_dependencies(roots, failed, generation)
	if generation != _dependency_scan_generation or _preview_active or _displayed_signature.is_empty():
		return
	_last_report["dependency_scan"] = scan
	var log_saved: bool = _write_report()
	_overlay.call("update_dependencies", _last_report, log_saved)

func resolve_dependency_path(dependency: String) -> String:
	var sections: PackedStringArray = dependency.split("::")
	var reference: String = sections[0].strip_edges()
	if reference.begins_with("uid://"):
		var uid: int = ResourceUID.text_to_id(reference)
		if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
			var uid_path: String = ResourceUID.get_id_path(uid)
			if ResourceLoader.exists(uid_path) or FileAccess.file_exists(uid_path):
				return uid_path
		if sections.size() >= 3 and not sections[2].strip_edges().is_empty():
			return sections[2].strip_edges()
	return reference

func inspect_dependencies(roots: PackedStringArray, failed: Dictionary = {}, generation: int = -1) -> Dictionary:
	var queue: Array[Dictionary] = []
	var visited: Dictionary = {}
	var findings: Dictionary = {}
	for root: String in roots:
		queue.append({"path": resolve_dependency_path(root), "owner": "Requested asset"})
	var index: int = 0
	var frame_start: int = Time.get_ticks_usec()
	while index < queue.size() and visited.size() < MAX_DEPENDENCY_RESOURCES:
		if generation >= 0 and generation != _dependency_scan_generation:
			return {"state": "Cancelled", "entries": [], "examined": visited.size()}
		var request: Dictionary = queue[index]
		index += 1
		var path: String = String(request.path)
		if path.is_empty():
			continue
		if not visited.has(path):
			visited[path] = true
			var resource_exists: bool = not path.begins_with("uid://") and ResourceLoader.exists(path)
			var file_exists: bool = not path.begins_with("uid://") and FileAccess.file_exists(path)
			if not resource_exists and not file_exists:
				findings[path] = {"path": path, "status": "Unresolved UID" if path.begins_with("uid://") else "Missing", "reason": "Reference could not be resolved." if path.begins_with("uid://") else "Resource and source file are unavailable.", "owners": []}
			elif failed.has(path):
				findings[path] = {"path": path, "status": "Failed to load", "reason": String(failed[path]), "owners": []}
			if resource_exists:
				for dependency: String in ResourceLoader.get_dependencies(path):
					queue.append({"path": resolve_dependency_path(dependency), "owner": path})
		if findings.has(path) and not findings[path].owners.has(request.owner):
			findings[path].owners.append(request.owner)
		if Time.get_ticks_usec() - frame_start >= DEPENDENCY_FRAME_BUDGET_USEC:
			await get_tree().process_frame
			frame_start = Time.get_ticks_usec()
	var entries: Array[Dictionary] = []
	var paths: Array = findings.keys()
	paths.sort()
	for path: String in paths:
		findings[path].owners.sort()
		entries.append(findings[path])
	return {"state": "Incomplete — scan limit reached" if index < queue.size() else "Complete", "entries": entries, "examined": visited.size(), "roots": roots}

func _ensure_overlay() -> void:
	if is_instance_valid(_overlay):
		get_tree().root.move_child(_overlay, get_tree().root.get_child_count() - 1)
		return
	_overlay = OVERLAY_SCRIPT.new() as CanvasLayer
	get_tree().root.add_child(_overlay)

func open_dependency_inspection(return_dialog: Window = null) -> void:
	if is_instance_valid(_overlay) and _overlay.call("is_report_visible"):
		_overlay.call("open_inspection", return_dialog)

func _clear_display() -> void:
	if _preview_active:
		return
	_displayed_signature = ""
	_dependency_scan_generation += 1
	if is_instance_valid(_overlay):
		_overlay.call("clear_report")

func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)

func show_preview(issues: Array, context: Dictionary, dependency_scan: Dictionary = {}) -> void:
	_preview_active = true
	_dependency_scan_generation += 1
	_ensure_overlay()
	_overlay.call("show_report", {"issues": issues, "context": context, "dependency_scan": dependency_scan}, false, true)

func end_preview() -> void:
	_preview_active = false
	_clear_display()
	_reset_candidate()

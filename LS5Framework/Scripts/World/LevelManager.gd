extends Node
class_name LevelManager

const DeathPlaneScript := preload("res://LS5Framework/Objects/Gameplay/DeathPlane.gd")
const LEVEL_TRANSIENT_GROUP: StringName = &"LevelTransient"

@export var level_root_path: NodePath = NodePath("../LevelRoot")
@export var fallback_world_environment_path: NodePath = NodePath("../Lights/WorldEnvironment")
## Directory where LVL_*.tres docs live (including LVLTEST.tres).
@export var level_data_dir: String = "res://LS5Framework/Scenes/Levels"
@export var hub_level_id: StringName = &"NIKO_TEST"
@export var auto_load_hub: bool = true
## Shows a black overlay while a newly loaded level settles.
@export var level_start_fade_enabled: bool = true
## Seconds used by the black overlay fade-in at level start.
@export var level_start_fade_in_duration: float = 0.45
## Frames to keep the level hidden before starting the fade-in.
@export var level_start_fade_hold_frames: int = 3
## Shows the reusable loading transition when replacing level content.
@export var level_loading_transition_enabled: bool = true
## Scene used for level loading messages and the black transition cover.
@export var loading_transition_scene: PackedScene = preload("res://LS5Framework/Scenes/UI/LoadingScreen.tscn")

@export_group("Level Preparation")
## Maximum main-thread preparation time used before yielding to the next frame.
@export_range(250, 16000, 250, "or_greater", "suffix:µs") var preparation_frame_budget_usec: int = 2000
## Maximum cosmetic activation time used before yielding to the next frame.
@export_range(250, 16000, 250, "or_greater", "suffix:µs") var cosmetic_activation_frame_budget_usec: int = 1500

# Each entry: {"id": StringName, "scene": String}
@export var level_scenes: Array[Dictionary] = [
	{"id": &"NIKO_TEST", "scene": "res://LS5Framework/Scenes/Levels/NikoTest/niko_test.tscn"},
	{"id": &"GREEN_HILL_CANYON", "scene": "res://LS5Framework/Scenes/Levels/Green Hill Canyon/green_hill_canyon.tscn"},
	{"id": &"GREEN_HILL_OCEAN", "scene": "res://LS5Framework/Scenes/Levels/Green Hill Ocean/green_hill_ocean.tscn"},
	{"id": &"EMERALD_COAST", "scene": "res://LS5Framework/Scenes/Levels/EmeraldCoast/emerald_coast.tscn"},
	{"id": &"MINECRAFT", "scene": "res://LS5Framework/Scenes/Levels/Minecraft/mine_craft.tscn"}
]

var _current_level_id: StringName = &""
var _current_level_scene_path: String = ""
var _current_level: Node = null
var _pending_teleport: Dictionary = {}
var _level_doc_entries: Array = []
var _level_doc_dir_cached: String = ""
var _level_load_in_progress: bool = false
var _level_start_transition_in_progress: bool = false
var _level_load_gameplay_suspended: bool = false
var _suspended_level_ref: WeakRef = null
var _suspended_level_process_mode: int = Node.PROCESS_MODE_INHERIT
var _suspended_player_ref: WeakRef = null


func _ready() -> void:
	add_to_group("LevelManager")
	var pending_scene: String = ""
	if get_tree() != null and get_tree().has_meta("pending_level_scene"):
		var v = get_tree().get_meta("pending_level_scene")
		if v is String:
			pending_scene = v
		get_tree().remove_meta("pending_level_scene")
	if pending_scene.strip_edges() != "":
		call_deferred("load_level_by_scene_path", pending_scene, StringName(""), NodePath("PlayerSpawn"))
		return
	if auto_load_hub and hub_level_id != &"":
		call_deferred("_load_hub")


func _exit_tree() -> void:
	_restore_gameplay_after_level_load()


func _load_hub() -> void:
	if _current_level_id != &"":
		return
	load_level_by_id(hub_level_id)


func get_current_level_id() -> StringName:
	return _current_level_id


func get_current_level() -> Node:
	return _current_level


func is_level_loading() -> bool:
	return _level_load_in_progress


func get_current_level_scene_path() -> String:
	return _current_level_scene_path


func reload_current_level_in_place() -> void:
	if _current_level_scene_path.strip_edges() == "" or _current_level == null:
		return
	load_level_by_scene_path(
		_current_level_scene_path,
		_current_level_id,
		NodePath(""),
		true,
		true,
		true
	)


func get_path_in_current_level(node: Node) -> NodePath:
	if _current_level == null or node == null:
		return NodePath("")
	if not _current_level.is_ancestor_of(node):
		return NodePath("")
	return _current_level.get_path_to(node)


func resolve_node_in_current_level(path: NodePath) -> Node:
	if _current_level == null:
		return null
	return _current_level.get_node_or_null(path)


func request_level_change(
		level_id: StringName,
		scene_path: String,
		exit_path: NodePath,
		body: Node3D,
		keep_velocity: bool,
		match_rotation: bool,
		exit_offset: Vector3
	) -> void:
	if body != null and body.has_method("is_player_state_locked") and body.call("is_player_state_locked"):
		return

	var target_id: StringName = level_id
	var target_scene_path: String = scene_path
	if target_scene_path == "" and target_id != &"":
		target_scene_path = _get_scene_path_for_id(target_id)
	if target_id == &"" and target_scene_path != "":
		target_id = _get_id_for_scene_path(target_scene_path)
	if target_scene_path == "":
		push_warning("LevelManager: target scene path not found.")
		return

	if _current_level_scene_path == target_scene_path and _current_level != null:
		_apply_exit_teleport(body, _current_level, exit_path, keep_velocity, match_rotation, exit_offset)
		return

	_clear_body_momentum_for_level_change(body)
	_pending_teleport = {
		"body": weakref(body),
		"exit_path": exit_path,
		"keep_velocity": false,
		"match_rotation": match_rotation,
		"exit_offset": exit_offset
	}
	load_level_by_scene_path(
		target_scene_path,
		target_id,
		NodePath("PlayerSpawn"),
		true,
		false,
		true
	)


func request_level_change_from_doc(
		level_doc_name: String,
		exit_path: NodePath,
		body: Node3D,
		keep_velocity: bool,
		match_rotation: bool,
		exit_offset: Vector3
	) -> void:
	# SUMMARY: Resolve LVL_*.tres doc name to a level scene, then request change.
	var entry: Dictionary = _get_level_entry_for_doc(level_doc_name)
	if entry.is_empty():
		print("LevelManager: doc miss, refreshing cache for %s" % level_doc_name)
		_reset_level_doc_cache()
		entry = _get_level_entry_for_doc(level_doc_name)
	if entry.is_empty():
		push_warning("LevelManager: level doc not found for %s" % level_doc_name)
		return
	var scene_path: String = _get_scene_path_from_entry(entry)
	if scene_path == "":
		push_warning("LevelManager: scene path not found in doc %s" % level_doc_name)
		return
	var level_id: StringName = &""
	if entry.has("id"):
		level_id = StringName(String(entry["id"]))
	request_level_change(level_id, scene_path, exit_path, body, keep_velocity, match_rotation, exit_offset)


func load_level_by_id(level_id: StringName, spawn_path: NodePath = NodePath("PlayerSpawn")) -> void:
	var scene_path = _get_scene_path_for_id(level_id)
	if scene_path == "":
		push_warning("LevelManager: scene path not found for level_id %s" % String(level_id))
		return
	load_level_by_scene_path(scene_path, level_id, spawn_path)


func ensure_level_ready_by_id(
		level_id: StringName,
		spawn_path: NodePath = NodePath("PlayerSpawn"),
		end_race_for_scene_change: bool = true,
		show_loading_transition: bool = false
	) -> bool:
	var scene_path: String = _get_scene_path_for_id(level_id)
	if scene_path == "":
		push_warning("LevelManager: scene path not found for level_id %s" % String(level_id))
		return false
	return await ensure_level_ready_by_scene_path(
		scene_path,
		level_id,
		spawn_path,
		end_race_for_scene_change,
		show_loading_transition
	)


func ensure_level_ready_by_scene_path(
		scene_path: String,
		level_id: StringName = &"",
		spawn_path: NodePath = NodePath("PlayerSpawn"),
		end_race_for_scene_change: bool = true,
		show_loading_transition: bool = false
	) -> bool:
	var normalized_scene_path: String = scene_path.strip_edges()
	if normalized_scene_path == "":
		return false
	while _level_load_in_progress:
		if get_tree() == null:
			return false
		await get_tree().process_frame
	if _current_level_scene_path == normalized_scene_path and _current_level != null and is_instance_valid(_current_level):
		if not await _wait_for_level_start_transition():
			return false
		return LevelPreparationManager.is_level_ready(normalized_scene_path)
	await load_level_by_scene_path(
		normalized_scene_path,
		level_id,
		spawn_path,
		end_race_for_scene_change,
		false,
		show_loading_transition
	)
	var loaded_target_scene: bool = (
		_current_level_scene_path == normalized_scene_path
		and _current_level != null
		and is_instance_valid(_current_level)
	)
	if not loaded_target_scene:
		return false
	if not await _wait_for_level_start_transition():
		return false
	return LevelPreparationManager.is_level_ready(normalized_scene_path)


func _wait_for_level_start_transition() -> bool:
	while _level_start_transition_in_progress:
		if get_tree() == null:
			return false
		await get_tree().process_frame
	return true


func load_level_by_scene_path(
		scene_path: String,
		level_id: StringName = &"",
		spawn_path: NodePath = NodePath("PlayerSpawn"),
		end_race_for_scene_change: bool = true,
		force_reload: bool = false,
		show_loading_transition: bool = false
	) -> void:
	if scene_path.strip_edges() == "":
		return
	if _current_level_scene_path == scene_path and _current_level != null and not force_reload:
		_apply_spawn_teleport(spawn_path)
		return
	if _level_load_in_progress:
		return
	_level_load_in_progress = true
	var loading_transition: LoadingScreen = _find_loading_transition()
	if level_loading_transition_enabled or show_loading_transition or loading_transition != null:
		loading_transition = await _begin_loading_transition(scene_path, level_id)
	var preparation_generation: int = LevelPreparationManager.get_current_generation()
	if loading_transition != null:
		preparation_generation = loading_transition.get_preparation_generation()
	else:
		preparation_generation = LevelPreparationManager.begin_level_preparation(scene_path)
	var cache_enabled: bool = LevelPreparationManager.is_cache_enabled()
	var session_prep_start_usec: int = Time.get_ticks_usec()
	var network_time_suspended: bool = _suspend_network_time_for_level_load()
	if end_race_for_scene_change:
		_end_local_race_for_scene_change()
	_prepare_players_for_level_change()
	_clear_level_transients()
	_clear_local_gravity_state_for_level_change()
	_clear_death_sequence_for_level_change()
	_clear_local_checkpoint_state()
	_clear_screen_faders_for_scene_change()
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Preparing session for level change",
			float(Time.get_ticks_usec() - session_prep_start_usec) / 1000000.0
		)

	var pack_start_usec: int = Time.get_ticks_usec()
	var pack_manager = _get_pack_manager()
	if pack_manager != null and pack_manager.has_method("ensure_pack_for_scene"):
		pack_manager.call("ensure_pack_for_scene", scene_path)
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Ensuring level content pack",
			float(Time.get_ticks_usec() - pack_start_usec) / 1000000.0
		)

	var level_root = _get_level_root()
	if level_root == null:
		push_warning("LevelManager: level_root not found.")
		LevelPreparationManager.fail_level_preparation(preparation_generation, "Level root was not found.")
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return

	var resolve_scene_start_usec: int = Time.get_ticks_usec()
	var packed: Resource = null
	if loading_transition != null:
		packed = loading_transition.get_tracked_resource(scene_path)
		if not (packed is PackedScene):
			packed = await loading_transition.load_tracked_scene(scene_path)
	else:
		packed = load(scene_path)
		if cache_enabled and packed is PackedScene:
			LevelPreparationManager.register_required_resource(
				scene_path,
				LevelPreparationManager.SCOPE_LEVEL,
				preparation_generation
			)
			LevelPreparationManager.store_resource(
				scene_path,
				packed,
				LevelPreparationManager.SCOPE_LEVEL,
				preparation_generation
			)
	LevelPreparationManager.finish_resource_loading(preparation_generation)
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Resolving level scene resource",
			float(Time.get_ticks_usec() - resolve_scene_start_usec) / 1000000.0
		)
	if not (packed is PackedScene):
		push_warning("LevelManager: failed to load scene %s" % scene_path)
		LevelPreparationManager.fail_level_preparation(
			preparation_generation,
			"Level scene failed to load: %s" % scene_path
		)
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return

	var audio_start_usec: int = Time.get_ticks_usec()
	var audio_ready: bool = true
	if cache_enabled:
		var audio_manifest: AudioPreparationManifest = _build_audio_preparation_manifest(scene_path)
		audio_ready = await _prepare_audio_manifest(
			audio_manifest,
			loading_transition,
			preparation_generation
		)
	if cache_enabled and loading_transition != null:
		loading_transition.record_loading_phase(
			"Preparing character and level audio",
			float(Time.get_ticks_usec() - audio_start_usec) / 1000000.0
		)
	if not audio_ready:
		LevelPreparationManager.fail_level_preparation(
			preparation_generation,
			"One or more required audio resources failed to load."
		)
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return

	if _current_level != null and is_instance_valid(_current_level):
		if loading_transition != null:
			loading_transition.show_loading_phase("Unloading previous level...")
			if get_tree() != null:
				await get_tree().process_frame
		var unload_start_usec: int = Time.get_ticks_usec()
		_unload_current_level()
		if loading_transition != null:
			loading_transition.record_loading_phase(
				"Unloading previous level",
				float(Time.get_ticks_usec() - unload_start_usec) / 1000000.0
			)

	var start_fader: Node = _begin_level_start_fade()
	if loading_transition != null:
		loading_transition.show_loading_phase("Instantiating scene objects...")
		if get_tree() != null:
			await get_tree().process_frame
	var instantiate_start_usec: int = Time.get_ticks_usec()
	var inst: Node = (packed as PackedScene).instantiate()
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Instantiating scene objects",
			float(Time.get_ticks_usec() - instantiate_start_usec) / 1000000.0
		)
	var proxies: Array[Node] = LevelObjectProxySpawner.collect_proxies(inst)
	var proxy_resource_paths: Array[String] = LevelObjectProxySpawner.collect_required_resource_paths(proxies)
	if cache_enabled and not proxy_resource_paths.is_empty():
		if loading_transition != null:
			loading_transition.show_loading_phase("Loading level object proxies...")
		var proxy_load_start_usec: int = Time.get_ticks_usec()
		var proxy_resources_ready: bool = false
		if loading_transition != null:
			proxy_resources_ready = await loading_transition.load_tracked_resources(
				proxy_resource_paths,
				"Proxy"
			)
		else:
			proxy_resources_ready = await LevelPreparationManager.load_resources_threaded(
				proxy_resource_paths,
				LevelPreparationManager.SCOPE_LEVEL,
				preparation_generation
			)
		if loading_transition != null:
			loading_transition.record_loading_phase(
				"Loading level object proxy resources",
				float(Time.get_ticks_usec() - proxy_load_start_usec) / 1000000.0
			)
		if not proxy_resources_ready:
			LevelPreparationManager.fail_level_preparation(
				preparation_generation,
				"One or more level object proxy resources failed to load."
			)
			inst.free()
			if loading_transition != null:
				await _finish_loading_transition(loading_transition)
			_finish_level_start_fade(start_fader)
			_resume_network_time_after_level_load(network_time_suspended)
			_level_load_in_progress = false
			return
	if loading_transition != null:
		loading_transition.show_loading_phase("Replacing level object proxies...")
	var proxy_start_usec: int = Time.get_ticks_usec()
	var proxies_replaced: bool = LevelObjectProxySpawner.replace_proxies_in_level(inst, proxies)
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Replacing level object proxies",
			float(Time.get_ticks_usec() - proxy_start_usec) / 1000000.0
		)
	if not proxies_replaced:
		LevelPreparationManager.fail_level_preparation(
			preparation_generation,
			"One or more level object proxies could not be replaced."
		)
		inst.free()
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_finish_level_start_fade(start_fader)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return
	var weather_start_usec: int = Time.get_ticks_usec()
	var weather_ready: bool = true
	if cache_enabled:
		weather_ready = await _prepare_weather_resources(
			inst,
			loading_transition,
			preparation_generation
		)
	if cache_enabled and loading_transition != null:
		loading_transition.record_loading_phase(
			"Preparing permitted weather states",
			float(Time.get_ticks_usec() - weather_start_usec) / 1000000.0
		)
	if not weather_ready:
		LevelPreparationManager.fail_level_preparation(
			preparation_generation,
			"One or more permitted weather states failed to prepare."
		)
		inst.free()
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_finish_level_start_fade(start_fader)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return
	var preparation_context: Dictionary = {
		"generation": preparation_generation,
		"scene_path": scene_path,
		"level_id": level_id,
		"managed": true,
	}
	var preparation_nodes: Array[Node] = []
	if cache_enabled:
		preparation_nodes = _collect_level_preparation_nodes(inst)
	var object_preparation_start_usec: int = Time.get_ticks_usec()
	var objects_prepared: bool = true
	if cache_enabled:
		objects_prepared = await _run_level_preparation_phase(
			preparation_nodes,
			&"prepare_for_level",
			preparation_context,
			preparation_frame_budget_usec,
			loading_transition,
			"Prepare"
		)
	if cache_enabled and loading_transition != null:
		loading_transition.record_loading_phase(
			"Preparing repeated gameplay objects",
			float(Time.get_ticks_usec() - object_preparation_start_usec) / 1000000.0
		)
	if not objects_prepared:
		LevelPreparationManager.fail_level_preparation(
			preparation_generation,
			"One or more gameplay objects failed preparation."
		)
		inst.free()
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_finish_level_start_fade(start_fader)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return
	if loading_transition != null:
		loading_transition.show_loading_phase("Initializing scene objects...")
		if get_tree() != null:
			await get_tree().process_frame
	var ready_start_usec: int = Time.get_ticks_usec()
	var original_process_mode: int = inst.process_mode
	if cache_enabled:
		inst.process_mode = Node.PROCESS_MODE_DISABLED
	level_root.add_child(inst)
	if cache_enabled and get_tree() != null:
		if loading_transition != null:
			loading_transition.show_loading_phase("Synchronizing level collision...")
		var collision_sync_start_usec: int = Time.get_ticks_usec()
		await get_tree().physics_frame
		if get_tree() != null:
			await get_tree().process_frame
		if loading_transition != null:
			loading_transition.record_loading_phase(
				"Synchronizing level collision",
				float(Time.get_ticks_usec() - collision_sync_start_usec) / 1000000.0
			)
	var activation_start_usec: int = Time.get_ticks_usec()
	var objects_activated: bool = true
	if cache_enabled:
		objects_activated = await _run_level_preparation_phase(
			preparation_nodes,
			&"activate_for_gameplay",
			preparation_context,
			0,
			loading_transition,
			"Activate"
		)
	if cache_enabled and loading_transition != null:
		loading_transition.record_loading_phase(
			"Initializing scene objects",
			float(Time.get_ticks_usec() - ready_start_usec) / 1000000.0
		)
		loading_transition.record_loading_phase(
			"Activating prepared gameplay objects",
			float(Time.get_ticks_usec() - activation_start_usec) / 1000000.0
		)
	if not objects_activated:
		LevelPreparationManager.fail_level_preparation(
			preparation_generation,
			"One or more prepared gameplay objects failed activation."
		)
		inst.queue_free()
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_finish_level_start_fade(start_fader)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return
	var graphics_start_usec: int = Time.get_ticks_usec()
	_apply_graphics_to_level(inst)
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Applying level graphics settings",
			float(Time.get_ticks_usec() - graphics_start_usec) / 1000000.0
		)
		loading_transition.show_loading_phase("Preparing first level frame...")
	var cosmetics_start_usec: int = Time.get_ticks_usec()
	var cosmetics_ready: bool = true
	if cache_enabled:
		cosmetics_ready = await _run_level_preparation_phase(
			preparation_nodes,
			&"activate_level_cosmetics",
			preparation_context,
			cosmetic_activation_frame_budget_usec,
			loading_transition,
			"Cosmetics"
		)
	if cache_enabled and loading_transition != null:
		loading_transition.record_loading_phase(
			"Activating level cosmetics",
			float(Time.get_ticks_usec() - cosmetics_start_usec) / 1000000.0
		)
	if not cosmetics_ready:
		LevelPreparationManager.fail_level_preparation(
			preparation_generation,
			"One or more cosmetic preparation tasks failed."
		)
		inst.queue_free()
		if loading_transition != null:
			await _finish_loading_transition(loading_transition)
		_finish_level_start_fade(start_fader)
		_resume_network_time_after_level_load(network_time_suspended)
		_level_load_in_progress = false
		return
	if cache_enabled:
		inst.process_mode = original_process_mode
	_current_level = inst
	_current_level_scene_path = scene_path
	_current_level_id = level_id if level_id != &"" else _get_id_for_scene_path(scene_path)

	var spawn_start_usec: int = Time.get_ticks_usec()
	var spawn_applied: bool = false
	if not _pending_teleport.is_empty():
		_apply_pending_teleport(inst)
		spawn_applied = true
	elif spawn_path != NodePath(""):
		_apply_spawn_teleport(spawn_path)
		spawn_applied = true
	if loading_transition != null and spawn_applied:
		loading_transition.record_loading_phase(
			"Applying level spawn",
			float(Time.get_ticks_usec() - spawn_start_usec) / 1000000.0
		)

	var local_notification_start_usec: int = Time.get_ticks_usec()
	_notify_local_level_changed(_current_level_id)
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Sending local level notification",
			float(Time.get_ticks_usec() - local_notification_start_usec) / 1000000.0
		)
	if get_tree() != null:
		var first_frame_start_usec: int = Time.get_ticks_usec()
		await get_tree().process_frame
		if loading_transition != null:
			loading_transition.record_loading_phase(
				"First prepared level process frame",
				float(Time.get_ticks_usec() - first_frame_start_usec) / 1000000.0
			)
	var readiness_start_usec: int = Time.get_ticks_usec()
	var preparation_ready: bool = LevelPreparationManager.complete_level_preparation(
		preparation_generation,
		scene_path
	)
	if loading_transition != null:
		loading_transition.record_loading_phase(
			"Completing level readiness barrier",
			float(Time.get_ticks_usec() - readiness_start_usec) / 1000000.0
		)
	if preparation_ready:
		var weather_sync_start_usec: int = Time.get_ticks_usec()
		_notify_weather_systems_level_ready(inst)
		if loading_transition != null:
			loading_transition.record_loading_phase(
				"Activating synchronized weather",
				float(Time.get_ticks_usec() - weather_sync_start_usec) / 1000000.0
			)
		var network_notification_start_usec: int = Time.get_ticks_usec()
		_notify_network_session_level_ready()
		if loading_transition != null:
			loading_transition.record_loading_phase(
				"Sending network level-ready notification",
				float(Time.get_ticks_usec() - network_notification_start_usec) / 1000000.0
			)
	else:
		push_warning(
			"LevelManager: level preparation did not complete for %s: %s" % [
				scene_path,
				LevelPreparationManager.get_failure_reason()
			]
		)
	if loading_transition != null:
		await _finish_loading_transition(loading_transition)
	_finish_level_start_fade(start_fader)
	_resume_network_time_after_level_load(network_time_suspended)
	_level_load_in_progress = false


func _begin_loading_transition(scene_path: String, level_id: StringName) -> LoadingScreen:
	var transition: LoadingScreen = _find_loading_transition()
	if transition == null and level_loading_transition_enabled and loading_transition_scene != null:
		transition = loading_transition_scene.instantiate() as LoadingScreen
		if transition != null and get_tree() != null:
			get_tree().root.add_child(transition)
	if transition == null:
		return null
	transition.adopt_for_level_handoff()
	if not transition.has_loading_message():
		transition.set_level_name(_get_level_display_name(scene_path, level_id))
	if not transition.is_covering_screen():
		if not transition.screen_covered.is_connected(_suspend_gameplay_for_level_load):
			transition.screen_covered.connect(
				_suspend_gameplay_for_level_load,
				CONNECT_ONE_SHOT
			)
		await transition.play_intro()
	_suspend_gameplay_for_level_load()
	transition.begin_load_tracking(scene_path)
	return transition


func _finish_loading_transition(transition: LoadingScreen) -> void:
	if transition == null or not is_instance_valid(transition):
		_restore_gameplay_after_level_load()
		return
	transition.finish_load_tracking()
	await transition.play_outro()
	if is_instance_valid(transition):
		transition.release_after_handoff()
	_restore_gameplay_after_level_load()


func _suspend_gameplay_for_level_load() -> void:
	if _level_load_gameplay_suspended:
		return
	_level_load_gameplay_suspended = true
	_suspend_level_node_for_load(_current_level)
	var player: Node3D = _get_local_player()
	if player != null and is_instance_valid(player) and player.has_method("set_level_load_suspended"):
		_suspended_player_ref = weakref(player)
		player.call("set_level_load_suspended", true)


func _suspend_level_node_for_load(level: Node) -> void:
	if level == null or not is_instance_valid(level):
		return
	_suspended_level_ref = weakref(level)
	_suspended_level_process_mode = level.process_mode
	level.process_mode = Node.PROCESS_MODE_DISABLED


func _restore_gameplay_after_level_load() -> void:
	if not _level_load_gameplay_suspended:
		return
	var suspended_level: Node = null
	if _suspended_level_ref != null:
		suspended_level = _suspended_level_ref.get_ref() as Node
	if suspended_level != null and is_instance_valid(suspended_level):
		suspended_level.process_mode = _suspended_level_process_mode
	var suspended_player: Node = null
	if _suspended_player_ref != null:
		suspended_player = _suspended_player_ref.get_ref() as Node
	if suspended_player != null and is_instance_valid(suspended_player):
		suspended_player.call("set_level_load_suspended", false)
	var current_player: Node3D = _get_local_player()
	if current_player != null and is_instance_valid(current_player) \
			and current_player != suspended_player \
			and current_player.has_method("set_level_load_suspended"):
		current_player.call("set_level_load_suspended", false)
	_level_load_gameplay_suspended = false
	_suspended_level_ref = null
	_suspended_level_process_mode = Node.PROCESS_MODE_INHERIT
	_suspended_player_ref = null


func _find_loading_transition() -> LoadingScreen:
	if get_tree() == null:
		return null
	var transitions: Array[Node] = get_tree().get_nodes_in_group("LevelLoadingTransition")
	for candidate: Node in transitions:
		if candidate is LoadingScreen and is_instance_valid(candidate):
			return candidate as LoadingScreen
	return null


func _get_level_display_name(scene_path: String, level_id: StringName) -> String:
	var normalized_scene_path: String = scene_path.strip_edges()
	for entry_value: Variant in _get_level_catalog_entries():
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var entry_scene_path: String = _get_scene_path_from_entry(entry).strip_edges()
		var entry_id: StringName = StringName(String(entry.get("id", "")))
		if entry_scene_path == normalized_scene_path or (level_id != &"" and entry_id == level_id):
			var display_name: String = String(entry.get("name", "")).strip_edges()
			if display_name != "":
				return display_name
	if level_id != &"":
		return String(level_id).replace("_", " ").capitalize()
	var file_name: String = normalized_scene_path.get_file().get_basename()
	if file_name != "":
		return file_name.replace("_", " ").capitalize()
	return "Level"


func _apply_spawn_teleport(spawn_path: NodePath) -> void:
	var body = _get_local_player()
	if body == null:
		return
	_apply_exit_teleport(body, _current_level, spawn_path, false, true, Vector3.ZERO)


func _clear_body_momentum_for_level_change(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("clear_gravity_state"):
		body.call("clear_gravity_state", &"level_restart", true)
	if body.has_method("stop_all_momentum_and_special_movement"):
		body.call("stop_all_momentum_and_special_movement")
		return
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO


func _unload_current_level() -> void:
	_clear_screen_faders_for_scene_change()
	_clear_level_transients()
	if _current_level == null or not is_instance_valid(_current_level):
		_current_level = null
		_clear_world_environment_override()
		return
	var old_level := _current_level
	_current_level = null
	_clear_world_environment_override()
	var parent := old_level.get_parent()
	if parent != null:
		parent.remove_child(old_level)
	old_level.queue_free()
	_clear_screen_faders_for_scene_change()


func _prepare_players_for_level_change() -> void:
	if get_tree() == null:
		return
	var handled: Dictionary = {}
	for group_name: StringName in [&"Player", &"player", &"RemotePlayer"]:
		for player: Node in get_tree().get_nodes_in_group(group_name):
			if player == null or not is_instance_valid(player):
				continue
			var instance_id: int = player.get_instance_id()
			if handled.has(instance_id):
				continue
			handled[instance_id] = true
			if player.has_method("prepare_for_level_change"):
				player.call("prepare_for_level_change")
			elif player.has_method("stop_all_momentum_and_special_movement"):
				player.call("stop_all_momentum_and_special_movement")
			if player.has_method("clear_prompt"):
				player.call("clear_prompt")


func _clear_level_transients() -> void:
	if get_tree() == null:
		return
	var transients: Array[Node] = get_tree().get_nodes_in_group(LEVEL_TRANSIENT_GROUP)
	for transient: Node in transients:
		if transient == null or not is_instance_valid(transient):
			continue
		_disable_transient_lights(transient)
		var parent: Node = transient.get_parent()
		if parent != null:
			parent.remove_child(transient)
		transient.queue_free()


func _disable_transient_lights(node: Node) -> void:
	if node is Light3D:
		var light: Light3D = node as Light3D
		light.light_energy = 0.0
		light.visible = false
	for child: Node in node.get_children():
		_disable_transient_lights(child)


func _clear_screen_faders_for_scene_change() -> void:
	_level_start_transition_in_progress = false
	if get_tree() == null:
		return
	var faders: Array = get_tree().get_nodes_in_group("ScreenFader")
	for node in faders:
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("reset_now"):
			node.call("reset_now")


func _begin_level_start_fade() -> Node:
	if not level_start_fade_enabled:
		_level_start_transition_in_progress = false
		return null
	var fader: Node = _get_or_create_screen_fader()
	if fader == null:
		_level_start_transition_in_progress = false
		return null
	_level_start_transition_in_progress = true
	if fader.has_method("set_fade_color"):
		fader.call("set_fade_color", Color.BLACK)
	if fader.has_method("fade_to"):
		fader.call("fade_to", 1.0, 0.0)
	return fader


func _finish_level_start_fade(fader: Node) -> void:
	if fader == null or not is_instance_valid(fader):
		_level_start_transition_in_progress = false
		return
	call_deferred("_fade_in_after_level_start", weakref(fader))


func _fade_in_after_level_start(fader_ref: WeakRef) -> void:
	var frame_count: int = max(level_start_fade_hold_frames, 0)
	for i in range(frame_count):
		if get_tree() == null:
			_level_start_transition_in_progress = false
			return
		await get_tree().process_frame
	var fader = fader_ref.get_ref()
	if fader == null or not is_instance_valid(fader):
		_level_start_transition_in_progress = false
		return
	if fader.has_method("fade_in"):
		await fader.call("fade_in", max(level_start_fade_in_duration, 0.0))
	_level_start_transition_in_progress = false


func _get_or_create_screen_fader() -> Node:
	if get_tree() == null:
		return null
	var existing: Array = get_tree().get_nodes_in_group("ScreenFader")
	if existing != null and existing.size() > 0:
		return existing[0]
	var fader: ScreenFader = ScreenFader.new()
	fader.add_to_group("ScreenFader")
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.add_child(fader)
	elif get_tree().current_scene != null:
		get_tree().current_scene.add_child(fader)
	else:
		add_child(fader)
	return fader


func _apply_pending_teleport(level_node: Node) -> void:
	var body_ref = _pending_teleport.get("body", null)
	var body: Node3D = null
	if body_ref is WeakRef:
		body = body_ref.get_ref()
	elif body_ref is Node3D:
		body = body_ref
	if body == null or not is_instance_valid(body):
		_pending_teleport.clear()
		return
	var exit_path: NodePath = _pending_teleport.get("exit_path", NodePath(""))
	var keep_velocity: bool = bool(_pending_teleport.get("keep_velocity", false))
	var match_rotation: bool = bool(_pending_teleport.get("match_rotation", false))
	var exit_offset: Vector3 = _pending_teleport.get("exit_offset", Vector3.ZERO)
	_apply_exit_teleport(body, level_node, exit_path, keep_velocity, match_rotation, exit_offset)
	_pending_teleport.clear()


func _apply_exit_teleport(
		body: Node3D,
		level_node: Node,
		exit_path: NodePath,
		keep_velocity: bool,
		match_rotation: bool,
		exit_offset: Vector3
	) -> void:
	if body == null or level_node == null:
		return
	var exit_target: Node3D = null
	if exit_path != NodePath(""):
		var n = level_node.get_node_or_null(exit_path)
		if n is Node3D:
			exit_target = n
	if exit_target == null:
		var fallback = level_node.get_node_or_null(NodePath("PlayerSpawn"))
		if fallback is Node3D:
			exit_target = fallback
	if exit_target == null:
		return

	if body.has_method("apply_teleport_from_exit"):
		body.call("apply_teleport_from_exit", exit_target, keep_velocity, match_rotation, exit_offset)
		return
	if body.has_method("apply_teleport"):
		body.call("apply_teleport", exit_target.global_transform, keep_velocity, match_rotation, exit_offset)
		return

	var old_basis: Basis = body.global_transform.basis
	var old_velocity: Vector3 = Vector3.ZERO
	var has_velocity: bool = false
	if body is CharacterBody3D:
		old_velocity = (body as CharacterBody3D).velocity
		has_velocity = true

	var exit_xform: Transform3D = exit_target.global_transform
	var world_offset: Vector3 = exit_xform.basis * exit_offset
	var base_xform := Transform3D(exit_xform.basis, exit_xform.origin + world_offset)
	base_xform = DownwarpUtil.apply_downwarp_from_node(exit_target, base_xform, [body])
	var new_origin: Vector3 = base_xform.origin
	var new_basis: Basis = base_xform.basis if match_rotation else old_basis
	body.global_transform = Transform3D(new_basis, new_origin)

	if has_velocity:
		var cb = body as CharacterBody3D
		cb.velocity = old_velocity if keep_velocity else Vector3.ZERO


func _apply_graphics_to_level(level_node: Node) -> void:
	if level_node == null:
		return
	var world_env: WorldEnvironment = _find_first_world_environment(level_node)
	var dir_light: DirectionalLight3D = _find_first_directional_light(level_node)
	var active_world_env: WorldEnvironment = world_env
	if world_env != null:
		_apply_world_environment_override(world_env)
	else:
		var fallback_world_env := _get_fallback_world_environment()
		if fallback_world_env != null:
			_apply_world_environment_override(fallback_world_env)
			active_world_env = fallback_world_env
		else:
			_clear_world_environment_override()
	var settings = get_node_or_null("/root/SettingsManager")
	if settings == null:
		return
	if active_world_env == null and dir_light == null:
		return
	if settings.has_method("register_graphics_targets"):
		settings.call("register_graphics_targets", active_world_env, dir_light)
	elif settings.has_method("apply_graphics_to"):
		settings.call("apply_graphics_to", active_world_env, dir_light)


func _apply_world_environment_override(world_env: WorldEnvironment) -> void:
	if world_env == null:
		return
	var targets := _get_world_environment_override_targets()
	var world: Object = targets.get("world", null)
	var vp: Viewport = targets.get("viewport", null)
	if world == null and vp == null:
		return
	_set_world_or_viewport_property(world, vp, "environment", world_env.environment)
	_set_world_or_viewport_property(world, vp, "camera_attributes", world_env.camera_attributes)
	_set_world_or_viewport_property(world, vp, "compositor", world_env.compositor)


func _clear_world_environment_override() -> void:
	var targets := _get_world_environment_override_targets()
	var world: Object = targets.get("world", null)
	var vp: Viewport = targets.get("viewport", null)
	if world == null and vp == null:
		return
	_set_world_or_viewport_property(world, vp, "environment", null)
	_set_world_or_viewport_property(world, vp, "camera_attributes", null)
	_set_world_or_viewport_property(world, vp, "compositor", null)


func _get_world_environment_override_targets() -> Dictionary:
	var vp: Viewport = null
	var player := _get_local_player()
	if player != null:
		vp = player.get_viewport()
	if vp == null:
		vp = get_viewport()
	if vp == null or not vp.has_method("get_world_3d"):
		return {"world": null, "viewport": vp}
	var world = vp.call("get_world_3d")
	return {"world": world, "viewport": vp}


func _get_fallback_world_environment() -> WorldEnvironment:
	if fallback_world_environment_path == NodePath(""):
		return null
	var n = get_node_or_null(fallback_world_environment_path)
	if n == null and get_tree() != null:
		n = get_tree().get_root().get_node_or_null(fallback_world_environment_path)
	return n if n is WorldEnvironment else null


func _set_world_or_viewport_property(world: Object, vp: Viewport, property_name: String, value) -> void:
	if world != null and _object_has_property(world, property_name):
		world.set(property_name, value)
		return
	if vp != null and _object_has_property(vp, property_name):
		vp.set(property_name, value)


func _object_has_property(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	var list = obj.get_property_list()
	for item in list:
		if item is Dictionary and item.has("name") and String(item["name"]) == property_name:
			return true
	return false


func _find_first_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found = _find_first_world_environment(child)
		if found != null:
			return found
	return null


func _find_first_directional_light(node: Node) -> DirectionalLight3D:
	var visible_light: DirectionalLight3D = _find_directional_light(node, true)
	if visible_light != null:
		return visible_light
	return _find_directional_light(node, false)


func _find_directional_light(node: Node, require_visible: bool) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		var light := node as DirectionalLight3D
		if not require_visible or light.visible:
			return light
	for child in node.get_children():
		var found = _find_directional_light(child, require_visible)
		if found != null:
			return found
	return null


func _notify_local_level_changed(level_id: StringName) -> void:
	var session = _get_network_session()
	if session != null and session.has_method("set_local_level_id"):
		var send_id: StringName = level_id
		if send_id == &"" and _current_level_scene_path != "":
			send_id = StringName(_current_level_scene_path)
		session.call("set_local_level_id", send_id)


func _end_local_race_for_scene_change() -> void:
	var player = _get_local_player()
	if player != null:
		if player.has_method("force_leave_race_for_scene_change"):
			player.call("force_leave_race_for_scene_change")
			return
		if player.has_method("leave_race"):
			player.call("leave_race", false)
			return
	var session = _get_network_session()
	if session != null and session.has_method("leave_race"):
		session.call("leave_race", false)


func _clear_death_sequence_for_level_change() -> void:
	DeathPlaneScript.cancel_death_sequence()
	var player = _get_local_player()
	if player == null:
		return
	if player.has_method("set_death_state"):
		player.call("set_death_state", false)
	if player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", false)
	if player.has_method("get") and player.get("_player_state_locked") != null:
		player.set("_player_state_locked", false)


func _clear_local_gravity_state_for_level_change() -> void:
	var player = _get_local_player()
	if player != null and player.has_method("clear_gravity_state"):
		player.call("clear_gravity_state", &"level_restart", true)


func _clear_local_checkpoint_state() -> void:
	var body = _get_local_player()
	if body == null:
		return
	if body.has_method("clear_checkpoint_data"):
		body.call("clear_checkpoint_data")


func _get_level_root() -> Node:
	if level_root_path == NodePath(""):
		return null
	var n = get_node_or_null(level_root_path)
	if n == null and get_tree() != null:
		n = get_tree().get_root().get_node_or_null(level_root_path)
	return n


func _get_scene_path_for_id(level_id: StringName) -> String:
	for entry in level_scenes:
		var id_val = entry.get("id", "")
		var id_name = StringName(String(id_val))
		if id_name == level_id:
			var scene_val = entry.get("scene", "")
			if scene_val is PackedScene:
				return (scene_val as PackedScene).resource_path
			return String(scene_val)
	for entry_value: Variant in _get_level_catalog_entries():
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var entry_id: StringName = StringName(String(entry.get("id", "")))
		if entry_id == level_id:
			return _get_scene_path_from_entry(entry)
	return ""


func _get_level_entry_for_doc(doc_name: String) -> Dictionary:
	var cleaned: String = doc_name.strip_edges()
	if cleaned == "":
		return {}
	var ext: String = cleaned.get_extension().to_lower()
	if ext == "":
		cleaned += ".tres"
	elif ext == "xml":
		cleaned = cleaned.substr(0, cleaned.length() - ext.length() - 1) + ".tres"
	elif ext != "tres":
		cleaned += ".tres"
	var doc_file: String = cleaned.get_file().to_lower()
	var entries: Array = _get_level_catalog_entries()
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var source_path: String = String(entry.get("source", ""))
		if source_path.get_file().to_lower() == doc_file:
			return entry
	return {}


func _get_scene_path_from_entry(entry: Dictionary) -> String:
	if entry.has("level_scene"):
		var level_scene: String = String(entry.get("level_scene", ""))
		if level_scene.strip_edges() != "":
			return level_scene
	if entry.has("scene"):
		return String(entry.get("scene", ""))
	return ""


func _get_level_catalog_entries() -> Array:
	if level_data_dir.strip_edges() == "":
		return []
	if _level_doc_entries.is_empty() or _level_doc_dir_cached != level_data_dir:
		_level_doc_entries = LevelCatalog.load_level_entries(level_data_dir)
		_level_doc_dir_cached = level_data_dir
	return _level_doc_entries


func _reset_level_doc_cache() -> void:
	print("LevelManager: clearing LevelDoc cache")
	_level_doc_entries.clear()
	_level_doc_dir_cached = ""


func _get_id_for_scene_path(scene_path: String) -> StringName:
	for entry in level_scenes:
		var scene_val = entry.get("scene", "")
		var entry_path: String = ""
		if scene_val is PackedScene:
			entry_path = (scene_val as PackedScene).resource_path
		else:
			entry_path = String(scene_val)
		if entry_path == scene_path:
			var id_val = entry.get("id", "")
			return StringName(String(id_val))
	return &""


func _get_local_player() -> Node3D:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("Player")
	if list != null and list.size() > 0:
		var n = list[0]
		return n if n is Node3D else null
	return null


func _get_network_session() -> Node:
	if get_tree() == null:
		return null
	return get_tree().root.find_child("NetworkSession", true, false)


func _build_audio_preparation_manifest(level_scene_path: String) -> AudioPreparationManifest:
	var manifest: AudioPreparationManifest = AudioPreparationManifest.new()
	var normalized_level_path: String = level_scene_path.strip_edges()
	if normalized_level_path != "":
		manifest.level_roots.append(normalized_level_path)
	var network_session: Node = _get_network_session()
	if network_session == null or not network_session.has_method("get_required_character_scene_paths"):
		return manifest
	var scene_paths_value: Variant = network_session.call("get_required_character_scene_paths")
	if not (scene_paths_value is Array):
		return manifest
	for path_value: Variant in scene_paths_value:
		var scene_path: String = String(path_value).strip_edges()
		if scene_path != "" and not manifest.character_roots.has(scene_path):
			manifest.character_roots.append(scene_path)
	return manifest


func _prepare_audio_manifest(
		manifest: AudioPreparationManifest,
		loading_transition: LoadingScreen,
		preparation_generation: int
	) -> bool:
	if not LevelPreparationManager.is_cache_enabled():
		return true
	if loading_transition != null:
		return await loading_transition.load_audio_manifest(manifest)
	if not LevelPreparationManager.prepare_character_scope(
			manifest.get_character_signature(),
			preparation_generation
		):
		return false
	if not await LevelPreparationManager.load_resources_threaded(
			manifest.character_roots,
			LevelPreparationManager.SCOPE_CHARACTER,
			preparation_generation
		):
		return false
	var character_audio_paths: Array[String] = _flatten_manifest_paths(
		manifest.get_character_audio_by_root()
	)
	if not await LevelPreparationManager.load_resources_threaded(
			character_audio_paths,
			LevelPreparationManager.SCOPE_CHARACTER,
			preparation_generation
		):
		return false
	var level_audio_paths: Array[String] = _flatten_manifest_paths(manifest.get_level_audio_by_root())
	level_audio_paths.append_array(manifest.get_additional_audio_paths())
	return await LevelPreparationManager.load_resources_threaded(
		level_audio_paths,
		LevelPreparationManager.SCOPE_LEVEL,
		preparation_generation
	)


func _flatten_manifest_paths(paths_by_root: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for paths_value: Variant in paths_by_root.values():
		if not (paths_value is Array):
			continue
		for path_value: Variant in paths_value:
			var path: String = String(path_value).strip_edges()
			if path != "" and not result.has(path):
				result.append(path)
	return result


func _prepare_weather_resources(
		level_instance: Node,
		loading_transition: LoadingScreen,
		preparation_generation: int
	) -> bool:
	var weather_systems: Array[Node] = []
	_collect_nodes_with_method(level_instance, &"get_weather_preparation_paths", weather_systems)
	var weather_paths: Array[String] = []
	for weather_system: Node in weather_systems:
		var paths_value: Variant = weather_system.call("get_weather_preparation_paths")
		if not (paths_value is Array):
			continue
		for path_value: Variant in paths_value:
			var path: String = String(path_value).strip_edges()
			if path != "" and not weather_paths.has(path):
				weather_paths.append(path)
	var resources_loaded: bool = true
	if not weather_paths.is_empty():
		if loading_transition != null:
			loading_transition.show_loading_phase("Loading permitted weather states...")
			resources_loaded = await loading_transition.load_tracked_resources(weather_paths, "Weather")
		else:
			resources_loaded = await LevelPreparationManager.load_resources_threaded(
				weather_paths,
				LevelPreparationManager.SCOPE_LEVEL,
				preparation_generation
			)
	if not resources_loaded:
		return false
	for weather_system: Node in weather_systems:
		if weather_system.has_method("apply_prepared_weather_resources"):
			var applied_value: Variant = weather_system.call("apply_prepared_weather_resources")
			if applied_value == false:
				return false
	return true


func _collect_level_preparation_nodes(level_instance: Node) -> Array[Node]:
	var result: Array[Node] = []
	_collect_nodes_with_method(level_instance, &"prepare_for_level", result)
	_collect_nodes_with_method(level_instance, &"activate_for_gameplay", result)
	_collect_nodes_with_method(level_instance, &"activate_level_cosmetics", result)
	var unique_result: Array[Node] = []
	for node: Node in result:
		if not unique_result.has(node):
			unique_result.append(node)
	return unique_result


func _collect_nodes_with_method(node: Node, method_name: StringName, result: Array[Node]) -> void:
	if node.has_method(method_name):
		result.append(node)
	for child: Node in node.get_children():
		_collect_nodes_with_method(child, method_name, result)


func _run_level_preparation_phase(
		nodes: Array[Node],
		method_name: StringName,
		context: Dictionary,
		frame_budget_usec: int,
		loading_transition: LoadingScreen = null,
		phase_label: String = ""
	) -> bool:
	var slice_start_usec: int = Time.get_ticks_usec()
	for node: Node in nodes:
		if node == null or not is_instance_valid(node) or not node.has_method(method_name):
			continue
		var node_label: String = _get_preparation_node_label(node)
		if loading_transition != null:
			loading_transition.show_loading_phase("%s: %s" % [phase_label, node_label])
		var node_start_usec: int = Time.get_ticks_usec()
		var result_value: Variant = node.call(method_name, context)
		if loading_transition != null:
			loading_transition.record_object_preparation(
				node_label,
				phase_label,
				float(Time.get_ticks_usec() - node_start_usec) / 1000000.0
			)
		if result_value == false:
			return false
		if frame_budget_usec <= 0:
			continue
		if Time.get_ticks_usec() - slice_start_usec < maxi(frame_budget_usec, 250):
			continue
		if get_tree() == null:
			return false
		await get_tree().process_frame
		slice_start_usec = Time.get_ticks_usec()
	return true


func _get_preparation_node_label(node: Node) -> String:
	var parts: Array[String] = []
	var current: Node = node
	while current != null:
		parts.push_front(String(current.name))
		current = current.get_parent()
	return "/".join(parts)


func _suspend_network_time_for_level_load() -> bool:
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager == null or not network_manager.has_method("suspend_network_time_for_level_load"):
		return false
	return bool(network_manager.call("suspend_network_time_for_level_load"))


func _resume_network_time_after_level_load(was_suspended: bool) -> void:
	if not was_suspended:
		return
	var network_manager: Node = get_node_or_null("/root/NetworkManager")
	if network_manager != null and network_manager.has_method("resume_network_time_after_level_load"):
		network_manager.call("resume_network_time_after_level_load", true)


func _notify_network_session_level_ready() -> void:
	var session: Node = _get_network_session()
	if session != null and session.has_method("on_local_level_ready"):
		session.call("on_local_level_ready")


func _notify_weather_systems_level_ready(level_instance: Node) -> void:
	var weather_systems: Array[Node] = []
	_collect_nodes_with_method(level_instance, &"on_level_preparation_ready", weather_systems)
	for weather_system: Node in weather_systems:
		if is_instance_valid(weather_system):
			weather_system.call("on_level_preparation_ready")


func _get_pack_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("ContentPackManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("ContentPackManager", true, false)

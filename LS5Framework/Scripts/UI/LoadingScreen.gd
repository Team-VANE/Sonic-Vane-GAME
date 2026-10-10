extends CanvasLayer
class_name LoadingScreen

signal intro_finished()
signal screen_covered()

const LOADING_MESSAGE_TEMPLATES: Array[Dictionary] = [
	{"prefix": "Revving up", "suffix": ""},
	{"prefix": "Start your engines for", "suffix": ""},
	{"prefix": "", "suffix": "Comin' at ya"},
	{"prefix": "Next stop:", "suffix": ""},
	{"prefix": "Juicin' toward", "suffix": ""},
	{"prefix": "Off to", "suffix": ""},
	{"prefix": "Get ready for", "suffix": ""},
	{"prefix": "Get psyched for", "suffix": ""},
	{"prefix": "", "suffix": "Is WAY past cool"},
	{"prefix": "Gotta speed to", "suffix": "Keep it cool, kid!"}
]
const LOAD_LOG_PATH: String = "user://level_load.log"
const LOAD_ERROR_LOG_PATH: String = "user://level_load_error.log"
const MAX_VISIBLE_RESOURCES: int = 2
const MAX_STALL_LOG_DEPENDENCIES: int = 250
const MAX_STALL_LOG_COMPLETIONS: int = 25

## Duration of the black background fade before loading begins.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var background_fade_duration: float = 0.32
## Duration of the loading banner's entrance from the left.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var banner_enter_duration: float = 0.38
## Duration of the loading banner's exit to the right.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var banner_exit_duration: float = 0.32
## Horizontal clearance used when placing the banner off-screen.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var offscreen_margin: float = 56.0
## Minimum horizontal margin retained around the loading banner.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var viewport_margin: float = 28.0
## Minimum loading banner width.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px") var minimum_banner_width: float = 520.0
## Maximum loading banner width.
@export_range(0.0, 3000.0, 1.0, "or_greater", "suffix:px") var maximum_banner_width: float = 900.0
## Seconds without threaded loading progress before a diagnostic stall report is generated.
@export_range(5.0, 300.0, 1.0, "or_greater", "suffix:s") var loading_hang_timeout_seconds: float = 25.0
## Seconds without threaded loading progress before the temporary slow-loading notice appears.
@export_range(1.0, 300.0, 1.0, "or_greater", "suffix:s") var slow_loading_notice_delay_seconds: float = 10.0

@export_group("Audio")
## Fades active music when this loading screen begins its intro.
@export var fade_out_music_on_intro: bool = true
## Duration of the outgoing music fade before loading replaces current content.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var music_fade_out_duration: float = 3.0
@export_group("")

## Provides the full-screen transition layout.
@onready var root: Control = $Root
## Fades the previous screen to black before loading begins.
@onready var background: ColorRect = $Root/Background
## Frames the loading message and moves during the transition.
@onready var banner: VBoxContainer = $Root/Banner
## Displays flavour text above the level name.
@onready var prefix_label: Label = $Root/Banner/LevelFrame/FrameContent/Margin/Content/Prefix
## Displays the selected level name.
@onready var level_label: Label = $Root/Banner/LevelFrame/FrameContent/Margin/Content/LevelName
## Displays flavour text below the level name.
@onready var suffix_label: Label = $Root/Banner/LevelFrame/FrameContent/Margin/Content/Suffix
## Displays the resources currently being loaded.
@onready var resource_label: Label = $Root/Banner/ProgressInset/ProgressFrame/Margin/Content/ResourceStatus
## Displays aggregate resource loading progress.
@onready var progress_bar: ProgressBar = $Root/Banner/ProgressInset/ProgressFrame/Margin/Content/LoadProgress

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_seeded: bool = false
var _level_name: String = ""
var _intro_active: bool = false
var _cover_active: bool = false
var _outro_active: bool = false
var _awaiting_level_handoff: bool = false
var _loading_started: bool = false
var _transition_tween: Tween = null
var _tracked_resources: Dictionary = {}
var _loaded_resources: Dictionary = {}
var _load_entries: Array[Dictionary] = []
var _report_roots: Dictionary = {}
var _report_target: String = ""
var _report_start_usec: int = 0
var _report_finished: bool = false
var _preparation_generation: int = 0
var _shell_change_start_usec: int = 0
var _shell_frame_start_usec: int = 0
var _active_request_roots: Array[String] = []
var _watchdog_last_progress_usec: int = 0
var _watchdog_last_progress_value: float = 0.0
var _watchdog_reported: bool = false
var _watchdog_notice: String = ""
var _slow_loading_notice_shown: bool = false
var _resource_status_default_color: Color = Color.WHITE
## Provides recovery actions after a scene load fails.
var _failure_dialog: AcceptDialog = null


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("LevelLoadingTransition")
	add_to_group("ModalMenu")
	background.modulate.a = 0.0
	banner.modulate.a = 0.0
	progress_bar.value = 0.0
	resource_label.text = "Preparing resources..."
	_resource_status_default_color = resource_label.get_theme_color(&"font_color")
	if not root.resized.is_connected(_update_banner_layout):
		root.resized.connect(_update_banner_layout)
	_update_banner_layout()


func _process(_delta: float) -> void:
	if not _active_request_roots.is_empty():
		_update_loading_watchdog()


func set_level_name(level_name: String) -> void:
	var resolved_name: String = level_name.strip_edges()
	if resolved_name == "":
		resolved_name = "Level"
	if _level_name == resolved_name and has_loading_message():
		return
	_level_name = resolved_name
	_ensure_rng_seeded()
	var prefix: String = "Loading"
	var suffix: String = ""
	if not LOADING_MESSAGE_TEMPLATES.is_empty():
		var index: int = _rng.randi_range(0, LOADING_MESSAGE_TEMPLATES.size() - 1)
		var entry: Dictionary = LOADING_MESSAGE_TEMPLATES[index]
		prefix = String(entry.get("prefix", "")).strip_edges()
		suffix = String(entry.get("suffix", "")).strip_edges()
	set_loading_message(prefix, resolved_name, suffix)


func set_loading_message(prefix: String, level_name: String, suffix: String) -> void:
	_level_name = level_name.strip_edges()
	if _level_name == "":
		_level_name = "Level"
	if not is_node_ready():
		await ready
	prefix_label.text = prefix.strip_edges()
	level_label.text = _level_name
	suffix_label.text = suffix.strip_edges()
	prefix_label.visible = prefix_label.text != ""
	suffix_label.visible = suffix_label.text != ""


func has_loading_message() -> bool:
	return _level_name != ""


func is_covering_screen() -> bool:
	return _cover_active


func adopt_for_level_handoff() -> void:
	_awaiting_level_handoff = true


func play_intro() -> void:
	if _cover_active or _intro_active:
		return
	_intro_active = true
	if not is_node_ready():
		await ready
	await get_tree().process_frame
	var wait_for_music_fade: bool = _fade_out_active_music()
	var music_fade_timer: SceneTreeTimer = null
	if wait_for_music_fade and music_fade_out_duration > 0.0:
		music_fade_timer = get_tree().create_timer(music_fade_out_duration, true, false, true)
	_update_banner_layout()
	_kill_transition_tween()
	var target_position: Vector2 = banner.position
	banner.position = Vector2(-banner.size.x - offscreen_margin, target_position.y)
	banner.scale = Vector2(0.96, 0.96)
	banner.modulate.a = 0.0
	background.modulate.a = 0.0
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(
		background,
		"modulate:a",
		1.0,
		max(background_fade_duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_callback(_mark_screen_covered).set_delay(
		max(background_fade_duration, 0.01)
	)
	_transition_tween.tween_property(
		banner,
		"position",
		target_position,
		max(banner_enter_duration, 0.01)
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(
		banner,
		"scale",
		Vector2.ONE,
		max(banner_enter_duration, 0.01)
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_transition_tween.tween_property(
		banner,
		"modulate:a",
		1.0,
		max(banner_enter_duration * 0.72, 0.01)
	)
	await _transition_tween.finished
	_transition_tween = null
	if music_fade_timer != null and music_fade_timer.time_left > 0.0:
		await music_fade_timer.timeout
	_intro_active = false
	_mark_screen_covered()
	intro_finished.emit()


func _mark_screen_covered() -> void:
	if _cover_active:
		return
	_cover_active = true
	screen_covered.emit()


func _fade_out_active_music() -> bool:
	if not fade_out_music_on_intro or get_tree() == null:
		return false
	var fade_started: bool = false
	var controllers: Array[Node] = get_tree().get_nodes_in_group("MusicControllers")
	for node: Node in controllers:
		if not (node is MusicController) or not is_instance_valid(node):
			continue
		var controller: MusicController = node as MusicController
		var source_id: StringName = controller.get_active_music_source_id()
		if source_id == &"" or not controller.is_music_source_playing(source_id):
			continue
		controller.stop_all_music(music_fade_out_duration)
		fade_started = true
	return fade_started


func play_outro() -> void:
	if _outro_active:
		return
	if not _cover_active:
		await play_intro()
	_outro_active = true
	_kill_transition_tween()
	var target_position: Vector2 = Vector2(root.size.x + offscreen_margin, banner.position.y)
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(
		banner,
		"position",
		target_position,
		max(banner_exit_duration, 0.01)
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(
		banner,
		"scale",
		Vector2(0.96, 0.96),
		max(banner_exit_duration, 0.01)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(
		banner,
		"modulate:a",
		0.0,
		max(banner_exit_duration * 0.82, 0.01)
	)
	await _transition_tween.finished
	_transition_tween = null
	_outro_active = false


func start_loading(
		scene_ref: String,
		min_visible_time: float = 0.2,
		preload_delay: float = 0.0,
		level_scene_ref: String = "",
		audio_manifest: AudioPreparationManifest = null
	) -> void:
	if _loading_started or scene_ref.strip_edges() == "":
		return
	_loading_started = true
	_awaiting_level_handoff = level_scene_ref.strip_edges() != ""
	await play_intro()
	if preload_delay > 0.0 and get_tree() != null:
		await get_tree().create_timer(preload_delay, true, false, true).timeout
	var load_start_msec: int = Time.get_ticks_msec()
	var packed_scene: PackedScene = await _load_scenes_threaded(scene_ref, level_scene_ref, audio_manifest)
	if packed_scene == null:
		_show_load_failure("Could not load %s. Check that all game content packs are installed." % scene_ref)
		return
	var elapsed: float = float(Time.get_ticks_msec() - load_start_msec) / 1000.0
	var remaining_time: float = max(min_visible_time - elapsed, 0.0)
	if remaining_time > 0.0 and get_tree() != null:
		var minimum_wait_start_usec: int = Time.get_ticks_usec()
		await get_tree().create_timer(remaining_time, true, false, true).timeout
		record_loading_phase(
			"Minimum loading screen display wait",
			float(Time.get_ticks_usec() - minimum_wait_start_usec) / 1000000.0
		)
	if not _awaiting_level_handoff:
		finish_load_tracking()
		await play_outro()
	_change_scene(scene_ref, packed_scene)


func release_after_handoff() -> void:
	_awaiting_level_handoff = false
	finish_load_tracking()
	queue_free()


func _load_scenes_threaded(
		scene_ref: String,
		level_scene_ref: String,
		audio_manifest: AudioPreparationManifest
	) -> PackedScene:
	var refs: Array[String] = [scene_ref]
	var dependency_ref: String = level_scene_ref.strip_edges()
	var root_roles: Dictionary = {}
	if LevelPreparationManager.is_cache_enabled() and dependency_ref != "" and dependency_ref != scene_ref:
		refs.append(dependency_ref)
		root_roles[scene_ref] = "Shell"
		root_roles[dependency_ref] = "Level"
	else:
		root_roles[scene_ref] = "Scene"
	_begin_load_tracking(dependency_ref if dependency_ref != "" else scene_ref)
	await _load_resource_set(refs, root_roles)
	for resource_ref: String in refs:
		if get_tracked_resource(resource_ref) == null:
			return null
	if LevelPreparationManager.is_cache_enabled() and audio_manifest != null:
		if not await load_audio_manifest(audio_manifest):
			return null
	if not LevelPreparationManager.finish_resource_loading(_preparation_generation):
		return null
	return get_tracked_resource(scene_ref) as PackedScene


func load_tracked_scene(scene_ref: String) -> PackedScene:
	var normalized_ref: String = scene_ref.strip_edges()
	if normalized_ref == "":
		return null
	var cached_resource: Resource = get_tracked_resource(normalized_ref)
	if cached_resource is PackedScene:
		return cached_resource as PackedScene
	begin_load_tracking(normalized_ref)
	var refs: Array[String] = [normalized_ref]
	var root_roles: Dictionary = {}
	root_roles[normalized_ref] = "Level"
	await _load_resource_set(refs, root_roles)
	LevelPreparationManager.finish_resource_loading(_preparation_generation)
	return get_tracked_resource(normalized_ref) as PackedScene


func load_tracked_resources(resource_refs: Array[String], root_role: String = "Level") -> bool:
	var normalized_refs: Array[String] = []
	var root_roles: Dictionary = {}
	for resource_ref: String in resource_refs:
		var normalized_ref: String = resource_ref.strip_edges()
		if normalized_ref == "" or normalized_refs.has(normalized_ref):
			continue
		normalized_refs.append(normalized_ref)
		root_roles[normalized_ref] = root_role
	if normalized_refs.is_empty():
		return true
	await _load_resource_set(normalized_refs, root_roles)
	if not LevelPreparationManager.finish_resource_loading(_preparation_generation):
		return false
	for normalized_ref: String in normalized_refs:
		if get_tracked_resource(normalized_ref) == null:
			return false
	return true


func load_audio_manifest(manifest: AudioPreparationManifest) -> bool:
	if not LevelPreparationManager.is_cache_enabled():
		return true
	if manifest == null:
		return true
	if not LevelPreparationManager.prepare_character_scope(
			manifest.get_character_signature(),
			_preparation_generation
		):
		return false
	show_loading_phase("Preparing audio resources...")
	for character_root: String in manifest.character_roots:
		var normalized_root: String = character_root.strip_edges()
		if normalized_root == "":
			continue
		if not await _load_owned_resource_set([normalized_root], normalized_root, "Character"):
			return false
	var character_audio: Dictionary = manifest.get_character_audio_by_root()
	for root_value: Variant in character_audio.keys():
		var root_ref: String = String(root_value)
		var resource_paths: Array[String] = _to_string_array(character_audio[root_value])
		if not await _load_owned_resource_set(resource_paths, root_ref, "CharacterAudio"):
			return false
	var level_audio: Dictionary = manifest.get_level_audio_by_root()
	for root_value: Variant in level_audio.keys():
		var root_ref: String = String(root_value)
		var resource_paths: Array[String] = _to_string_array(level_audio[root_value])
		if not await _load_owned_resource_set(resource_paths, root_ref, "LevelAudio"):
			return false
	var additional_audio: Array[String] = manifest.get_additional_audio_paths()
	if not additional_audio.is_empty():
		if not await _load_owned_resource_set(additional_audio, "Additional audio", "LevelAudio"):
			return false
	return LevelPreparationManager.finish_resource_loading(_preparation_generation)


func _load_owned_resource_set(
		resource_paths: Array[String],
		owner_ref: String,
		root_role: String
	) -> bool:
	if resource_paths.is_empty():
		return true
	var root_roles: Dictionary = {}
	var root_owners: Dictionary = {}
	for resource_path: String in resource_paths:
		root_roles[resource_path] = root_role
		root_owners[resource_path] = owner_ref
	await _load_resource_set(resource_paths, root_roles, root_owners)
	for resource_path: String in resource_paths:
		if get_tracked_resource(resource_path) == null:
			return false
	return true


func _to_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (values is Array):
		return result
	for value: Variant in values:
		var path: String = String(value).strip_edges()
		if path != "" and not result.has(path):
			result.append(path)
	return result


func get_tracked_resource(resource_ref: String) -> Resource:
	var normalized_ref: String = resource_ref.strip_edges()
	var value: Variant = _loaded_resources.get(normalized_ref)
	if value is Resource:
		return value as Resource
	return LevelPreparationManager.get_resource(normalized_ref)


func get_preparation_generation() -> int:
	return _preparation_generation


func begin_load_tracking(target_ref: String) -> void:
	var normalized_ref: String = target_ref.strip_edges()
	if normalized_ref == "":
		return
	if _report_start_usec > 0 and not _report_finished:
		return
	_begin_load_tracking(normalized_ref)


func record_loading_phase(phase_name: String, duration_sec: float) -> void:
	var normalized_name: String = phase_name.strip_edges()
	if normalized_name == "":
		return
	var end_seconds: float = _get_report_elapsed_seconds()
	var resolved_duration: float = max(duration_sec, 0.0)
	_load_entries.append({
		"path": normalized_name,
		"seconds": resolved_duration,
		"start_seconds": max(end_seconds - resolved_duration, 0.0),
		"end_seconds": end_seconds,
		"kind": "phase"
	})
	if not _watchdog_reported:
		resource_label.text = normalized_name


func record_object_preparation(object_path: String, phase_name: String, duration_sec: float) -> void:
	var normalized_path: String = object_path.strip_edges()
	if normalized_path == "":
		return
	_load_entries.append({
		"path": normalized_path,
		"phase": phase_name.strip_edges(),
		"seconds": max(duration_sec, 0.0),
		"kind": "object",
	})


func show_loading_phase(phase_name: String) -> void:
	var normalized_name: String = phase_name.strip_edges()
	if normalized_name == "":
		return
	progress_bar.value = 100.0
	if not _watchdog_reported:
		resource_label.text = normalized_name


func finish_load_tracking() -> void:
	if _report_finished:
		return
	_report_finished = true
	progress_bar.value = 100.0
	resource_label.text = "Finalizing level..."
	if _report_start_usec > 0 and SettingsManager.level_load_logging_enabled:
		_write_load_log()


func _begin_load_tracking(target_ref: String) -> void:
	_tracked_resources.clear()
	_loaded_resources.clear()
	_load_entries.clear()
	_report_roots.clear()
	_report_target = target_ref.strip_edges()
	_report_start_usec = Time.get_ticks_usec()
	_report_finished = false
	_preparation_generation = LevelPreparationManager.begin_level_preparation(_report_target)
	_active_request_roots.clear()
	_watchdog_last_progress_usec = Time.get_ticks_usec()
	_watchdog_last_progress_value = 0.0
	_watchdog_reported = false
	_watchdog_notice = ""
	_slow_loading_notice_shown = false
	resource_label.add_theme_color_override(&"font_color", _resource_status_default_color)
	progress_bar.value = 0.0
	resource_label.text = "Scanning level resources..."


func _load_resource_set(
		root_refs: Array[String],
		root_roles: Dictionary = {},
		root_owners: Dictionary = {}
	) -> void:
	# Shared scene and script dependencies are resolved before the next root starts.
	if root_refs.size() > 1:
		for root_ref: String in root_refs:
			var normalized_ref: String = root_ref.strip_edges()
			if normalized_ref == "":
				continue
			await _load_resource_set([normalized_ref], root_roles, root_owners)
			if get_tracked_resource(normalized_ref) == null:
				return
		return
	var dependency_scan_start_usec: int = Time.get_ticks_usec()
	var ordered_refs: Array[String] = []
	var ordered_lookup: Dictionary = {}
	var cache_enabled: bool = LevelPreparationManager.is_cache_enabled()
	for root_ref: String in root_refs:
		var normalized_root: String = root_ref.strip_edges()
		if normalized_root == "":
			continue
		var owner_ref: String = String(root_owners.get(normalized_root, normalized_root))
		var role: String = String(root_roles.get(normalized_root, "Scene"))
		if not _report_roots.has(owner_ref) or role in ["Level", "Character", "Weather", "Proxy"]:
			_report_roots[owner_ref] = role
		if cache_enabled:
			var visited: Dictionary = {}
			_collect_dependencies(normalized_root, owner_ref, visited, ordered_lookup, ordered_refs)
		elif not ordered_lookup.has(normalized_root):
			_register_resource_owner(normalized_root, owner_ref)
			ordered_lookup[normalized_root] = true
			ordered_refs.append(normalized_root)
	if cache_enabled:
		record_loading_phase(
			"Scanning resource dependencies",
			float(Time.get_ticks_usec() - dependency_scan_start_usec) / 1000000.0
		)
	if ordered_refs.is_empty():
		return
	var requested_roots: Dictionary = {}
	for root_ref: String in root_refs:
		var normalized_root: String = root_ref.strip_edges()
		if normalized_root != "":
			requested_roots[normalized_root] = true
	_start_loading_watchdog(requested_roots)
	var request_queue_start_usec: int = Time.get_ticks_usec()
	for resource_ref: String in ordered_refs:
		var queued_usec: int = Time.get_ticks_usec()
		var existing_state: Dictionary = _tracked_resources.get(resource_ref, {})
		_tracked_resources[resource_ref] = {
			"progress": 0.0,
			"complete": false,
			"cached": ResourceLoader.has_cached(resource_ref),
			"requested": requested_roots.has(resource_ref),
			"queued_usec": queued_usec,
			"first_progress_usec": 0,
			"owners": _get_resource_owners(resource_ref)
		}
		var cache_scope: StringName = _get_resource_cache_scope(_tracked_resources[resource_ref])
		if cache_enabled:
			LevelPreparationManager.register_required_resource(
				resource_ref,
				cache_scope,
				_preparation_generation
			)
		if bool(existing_state.get("complete", false)):
			var existing_resource: Resource = get_tracked_resource(resource_ref)
			if existing_resource != null:
				if cache_enabled:
					LevelPreparationManager.store_resource(
						resource_ref,
						existing_resource,
						cache_scope,
						_preparation_generation
					)
				_tracked_resources[resource_ref] = existing_state
				continue
		if not requested_roots.has(resource_ref):
			continue
		var request_error: Error = ResourceLoader.load_threaded_request(resource_ref)
		if request_error != OK and request_error != ERR_BUSY:
			if ResourceLoader.has_cached(resource_ref):
				var cached_resource: Resource = ResourceLoader.load(resource_ref)
				if cached_resource != null:
					_loaded_resources[resource_ref] = cached_resource
					_mark_resource_complete(resource_ref, _tracked_resources[resource_ref])
				else:
					_mark_resource_failed(resource_ref, request_error)
			else:
				_mark_resource_failed(resource_ref, request_error)
	record_loading_phase(
		"Queueing threaded resource requests",
		float(Time.get_ticks_usec() - request_queue_start_usec) / 1000000.0
	)
	while _has_pending_requested_resources():
		_update_resource_statuses()
		_update_loading_watchdog()
		if not _has_pending_requested_resources():
			break
		if get_tree() == null:
			return
		await get_tree().process_frame
	_resolve_loaded_dependencies(ordered_refs)
	_active_request_roots.clear()
	_update_loading_display()


func _collect_dependencies(
		resource_ref: String,
		owner_ref: String,
		visited: Dictionary,
		ordered_lookup: Dictionary,
		ordered_refs: Array[String]
	) -> void:
	if resource_ref == "":
		return
	_register_resource_owner(resource_ref, owner_ref)
	if visited.has(resource_ref):
		return
	visited[resource_ref] = true
	for dependency_entry: String in ResourceLoader.get_dependencies(resource_ref):
		var dependency_ref: String = _resolve_dependency_path(dependency_entry)
		_collect_dependencies(dependency_ref, owner_ref, visited, ordered_lookup, ordered_refs)
	if not ordered_lookup.has(resource_ref):
		ordered_lookup[resource_ref] = true
		ordered_refs.append(resource_ref)


func _register_resource_owner(resource_ref: String, owner_ref: String) -> void:
	var owners: Array[String] = _get_resource_owners(resource_ref)
	if not owners.has(owner_ref):
		owners.append(owner_ref)
	var state: Dictionary = _tracked_resources.get(resource_ref, {})
	state["owners"] = owners
	_tracked_resources[resource_ref] = state


func _get_resource_owners(resource_ref: String) -> Array[String]:
	var owners: Array[String] = []
	var state_value: Variant = _tracked_resources.get(resource_ref)
	if state_value is Dictionary:
		for owner_value: Variant in (state_value as Dictionary).get("owners", []):
			owners.append(String(owner_value))
	return owners


func _get_resource_cache_scope(state: Dictionary) -> StringName:
	var has_character_owner: bool = false
	for owner_value: Variant in state.get("owners", []):
		var owner_ref: String = String(owner_value)
		var role: String = String(_report_roots.get(owner_ref, "Scene"))
		if role == "Level" or role == "LevelAudio" or role == "Scene" or role == "Proxy" or role == "Weather":
			return LevelPreparationManager.SCOPE_LEVEL
		if role == "Character" or role == "CharacterAudio":
			has_character_owner = true
	if has_character_owner:
		return LevelPreparationManager.SCOPE_CHARACTER
	return LevelPreparationManager.SCOPE_CORE


func _resolve_dependency_path(dependency_entry: String) -> String:
	if dependency_entry.contains("::"):
		var fallback_path: String = dependency_entry.get_slice("::", 2).strip_edges()
		if fallback_path != "":
			return fallback_path
		return dependency_entry.get_slice("::", 0).strip_edges()
	return dependency_entry.strip_edges()


func _has_pending_requested_resources() -> bool:
	for state_value: Variant in _tracked_resources.values():
		if not (state_value is Dictionary):
			continue
		var state: Dictionary = state_value as Dictionary
		if bool(state.get("requested", false)) and not bool(state.get("complete", false)):
			return true
	return false


func _update_resource_statuses() -> void:
	for resource_ref_value: Variant in _tracked_resources.keys():
		var resource_ref: String = String(resource_ref_value)
		var state: Dictionary = _tracked_resources[resource_ref]
		if bool(state.get("complete", false)) or not bool(state.get("requested", false)):
			continue
		var progress: Array = []
		var status: int = ResourceLoader.load_threaded_get_status(resource_ref, progress)
		state["status"] = status
		_tracked_resources[resource_ref] = state
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource: Resource = ResourceLoader.load_threaded_get(resource_ref)
			if resource != null:
				_loaded_resources[resource_ref] = resource
				_mark_resource_complete(resource_ref, state)
			else:
				_mark_resource_failed(resource_ref, FAILED)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_mark_resource_failed(resource_ref, FAILED)
		elif not progress.is_empty():
			state["progress"] = clamp(float(progress[0]), 0.0, 1.0)
			if float(state["progress"]) > 0.0 and int(state.get("first_progress_usec", 0)) == 0:
				state["first_progress_usec"] = Time.get_ticks_usec()
			_tracked_resources[resource_ref] = state
	_update_loading_display()


func _resolve_loaded_dependencies(resource_refs: Array[String]) -> void:
	for resource_ref: String in resource_refs:
		var state: Dictionary = _tracked_resources.get(resource_ref, {})
		if bool(state.get("complete", false)):
			continue
		if not ResourceLoader.has_cached(resource_ref):
			_mark_resource_failed(resource_ref, ERR_CANT_ACQUIRE_RESOURCE)
			continue
		var resource: Resource = ResourceLoader.load(resource_ref)
		if resource == null:
			_mark_resource_failed(resource_ref, ERR_CANT_ACQUIRE_RESOURCE)
			continue
		_loaded_resources[resource_ref] = resource
		_mark_resource_complete(resource_ref, state)


func _start_loading_watchdog(requested_roots: Dictionary) -> void:
	_active_request_roots.clear()
	for root_value: Variant in requested_roots.keys():
		_active_request_roots.append(String(root_value))
	_watchdog_last_progress_usec = Time.get_ticks_usec()
	_watchdog_last_progress_value = _get_active_root_progress()
	if not _watchdog_reported:
		_slow_loading_notice_shown = false
		resource_label.add_theme_color_override(&"font_color", _resource_status_default_color)


func _update_loading_watchdog() -> void:
	if _active_request_roots.is_empty():
		return
	var current_usec: int = Time.get_ticks_usec()
	var current_progress: float = _get_active_root_progress()
	if current_progress > _watchdog_last_progress_value + 0.0001:
		if _watchdog_reported:
			SceneDiagnostics.clear_loading_stall()
		_watchdog_last_progress_value = current_progress
		_watchdog_last_progress_usec = current_usec
		_slow_loading_notice_shown = false
		_watchdog_reported = false
		_watchdog_notice = ""
		resource_label.add_theme_color_override(&"font_color", _resource_status_default_color)
		return
	var stalled_seconds: float = float(
		current_usec - _watchdog_last_progress_usec
	) / 1000000.0
	if (
		not _slow_loading_notice_shown
		and stalled_seconds >= max(slow_loading_notice_delay_seconds, 1.0)
	):
		_slow_loading_notice_shown = true
		resource_label.add_theme_color_override(&"font_color", Color(1.0, 0.78, 0.3, 1.0))
		resource_label.text = "Loading is taking a while. Still working..."
	if _watchdog_reported or stalled_seconds < max(loading_hang_timeout_seconds, 5.0):
		return
	_watchdog_reported = true
	var log_written: bool = _write_loading_hang_log(stalled_seconds)
	if log_written:
		_watchdog_notice = "Loading is taking longer than expected. If it never finishes, restart the game and send level_load_error.log from Options > Data > Open Local Files to LS5."
	else:
		_watchdog_notice = "Loading is taking longer than expected. If it never finishes, restart the game and notify LS5."
	resource_label.add_theme_color_override(&"font_color", Color(1.0, 0.42, 0.28, 1.0))
	resource_label.text = _watchdog_notice
	SceneDiagnostics.report_loading_problem(
		"No threaded resource progress for %.1f seconds. Active requests: %s." % [stalled_seconds, ", ".join(_active_request_roots)],
		_report_target,
		true
	)


func _get_active_root_progress() -> float:
	if _active_request_roots.is_empty():
		return 0.0
	var aggregate_progress: float = 0.0
	for resource_ref: String in _active_request_roots:
		var state: Dictionary = _tracked_resources.get(resource_ref, {})
		aggregate_progress += float(state.get("progress", 0.0))
	return aggregate_progress / float(_active_request_roots.size())


func _write_loading_hang_log(stalled_seconds: float) -> bool:
	var file: FileAccess = FileAccess.open(LOAD_ERROR_LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning(
			"LoadingScreen: could not write %s: %s" % [
				LOAD_ERROR_LOG_PATH,
				error_string(FileAccess.get_open_error()),
			]
		)
		return false
	file.store_line("LS5 Engine 3 Loading Stall Report")
	file.store_line("Generated: %s" % Time.get_datetime_string_from_system())
	file.store_line("Target: %s" % _report_target)
	file.store_line("Tracked elapsed: %.3f s" % _get_report_elapsed_seconds())
	file.store_line("No progress observed: %.3f s" % stalled_seconds)
	file.store_line("Preparation generation: %d" % _preparation_generation)
	file.store_line("Preparation state: %d" % LevelPreparationManager.get_preparation_state())
	file.store_line("Preparation failure: %s" % LevelPreparationManager.get_failure_reason())
	file.store_line("Engine: %s" % JSON.stringify(Engine.get_version_info()))
	file.store_line("Operating system: %s %s" % [OS.get_name(), OS.get_version()])
	file.store_line("")
	file.store_line("Stalled threaded roots")
	file.store_line("Progress  Status       Path")
	for resource_ref: String in _active_request_roots:
		var root_state: Dictionary = _tracked_resources.get(resource_ref, {})
		file.store_line(
			"%7.2f%%  %-11s  %s" % [
				float(root_state.get("progress", 0.0)) * 100.0,
				_get_thread_status_name(int(root_state.get("status", ResourceLoader.THREAD_LOAD_IN_PROGRESS))),
				resource_ref,
			]
		)
	var unresolved_dependencies: Array[String] = []
	for resource_value: Variant in _tracked_resources.keys():
		var resource_ref: String = String(resource_value)
		var dependency_state_record: Dictionary = _tracked_resources[resource_ref]
		if bool(dependency_state_record.get("requested", false)) or bool(
			dependency_state_record.get("complete", false)
		):
			continue
		if not ResourceLoader.has_cached(resource_ref):
			unresolved_dependencies.append(resource_ref)
	unresolved_dependencies.sort()
	file.store_line("")
	file.store_line("Uncached dependency candidates: %d" % unresolved_dependencies.size())
	var dependency_limit: int = mini(unresolved_dependencies.size(), MAX_STALL_LOG_DEPENDENCIES)
	for dependency_index: int in range(dependency_limit):
		var dependency_ref: String = unresolved_dependencies[dependency_index]
		var dependency_state: Dictionary = _tracked_resources.get(dependency_ref, {})
		file.store_line(
			"%-21s  %s" % [
				_format_owner_labels(dependency_state.get("owners", [])),
				dependency_ref,
			]
		)
	if unresolved_dependencies.size() > dependency_limit:
		file.store_line("... %d additional dependencies omitted" % (unresolved_dependencies.size() - dependency_limit))
	var completed_entries: Array[Dictionary] = []
	for entry: Dictionary in _load_entries:
		if String(entry.get("kind", "")) == "resource":
			completed_entries.append(entry)
	completed_entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("seconds", 0.0)) > float(b.get("seconds", 0.0))
	)
	file.store_line("")
	file.store_line("Most recently completed resources")
	var completion_limit: int = mini(completed_entries.size(), MAX_STALL_LOG_COMPLETIONS)
	for completion_index: int in range(completion_limit):
		var entry: Dictionary = completed_entries[completion_index]
		file.store_line(
			"%8.3f s  %s" % [
				float(entry.get("seconds", 0.0)),
				String(entry.get("path", "")),
			]
		)
	file.flush()
	return true


func _get_thread_status_name(status: int) -> String:
	match status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return "invalid"
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return "in_progress"
		ResourceLoader.THREAD_LOAD_FAILED:
			return "failed"
		ResourceLoader.THREAD_LOAD_LOADED:
			return "loaded"
	return "unknown_%d" % status


func _mark_resource_complete(resource_ref: String, state: Dictionary) -> void:
	var completed_usec: int = Time.get_ticks_usec()
	var queued_usec: int = int(state.get("queued_usec", _report_start_usec))
	state["progress"] = 1.0
	state["complete"] = true
	state["completed_usec"] = completed_usec
	_tracked_resources[resource_ref] = state
	var resource_value: Variant = _loaded_resources.get(resource_ref)
	if resource_value is Resource:
		LevelPreparationManager.store_resource(
			resource_ref,
			resource_value as Resource,
			_get_resource_cache_scope(state),
			_preparation_generation
		)
	_load_entries.append({
		"path": resource_ref,
		"seconds": float(completed_usec - _report_start_usec) / 1000000.0,
		"queued_seconds": float(queued_usec - _report_start_usec) / 1000000.0,
		"request_seconds": float(completed_usec - queued_usec) / 1000000.0,
		"kind": "resource",
		"cached": bool(state.get("cached", false)),
		"thread_root": bool(state.get("requested", false)),
		"owners": state.get("owners", [])
	})


func _mark_resource_failed(resource_ref: String, error_code: int) -> void:
	var state: Dictionary = _tracked_resources.get(resource_ref, {})
	var completed_usec: int = Time.get_ticks_usec()
	var queued_usec: int = int(state.get("queued_usec", _report_start_usec))
	state["progress"] = 1.0
	state["complete"] = true
	state["completed_usec"] = completed_usec
	_tracked_resources[resource_ref] = state
	LevelPreparationManager.mark_resource_failed(
		resource_ref,
		error_string(error_code),
		_preparation_generation
	)
	_load_entries.append({
		"path": resource_ref,
		"seconds": float(completed_usec - _report_start_usec) / 1000000.0,
		"queued_seconds": float(queued_usec - _report_start_usec) / 1000000.0,
		"request_seconds": float(completed_usec - queued_usec) / 1000000.0,
		"kind": "error",
		"error": error_string(error_code),
		"thread_root": bool(state.get("requested", false)),
		"owners": state.get("owners", [])
	})


func _update_loading_display() -> void:
	var total_count: int = 0
	for state_value: Variant in _tracked_resources.values():
		if state_value is Dictionary and bool((state_value as Dictionary).get("requested", false)):
			total_count += 1
	if total_count <= 0:
		progress_bar.value = 100.0
		return
	var aggregate_progress: float = 0.0
	var active_names: Array[String] = []
	for resource_ref_value: Variant in _tracked_resources.keys():
		var resource_ref: String = String(resource_ref_value)
		var state: Dictionary = _tracked_resources[resource_ref]
		if not bool(state.get("requested", false)):
			continue
		aggregate_progress += float(state.get("progress", 0.0))
		if not bool(state.get("complete", false)) and active_names.size() < MAX_VISIBLE_RESOURCES:
			active_names.append(resource_ref.get_file())
	progress_bar.value = aggregate_progress / float(total_count) * 100.0
	if _watchdog_reported:
		resource_label.text = _watchdog_notice
	elif _slow_loading_notice_shown:
		resource_label.text = "Loading is taking a while. Still working..."
	elif active_names.is_empty():
		resource_label.text = "Resources ready"
	else:
		resource_label.text = "Loading %s" % ", ".join(active_names)


func _write_load_log() -> void:
	var file: FileAccess = FileAccess.open(LOAD_LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("LoadingScreen: could not write %s: %s" % [LOAD_LOG_PATH, error_string(FileAccess.get_open_error())])
		return
	var total_seconds: float = _get_report_elapsed_seconds()
	var resource_entries: Array[Dictionary] = []
	var phase_entries: Array[Dictionary] = []
	var object_entries: Array[Dictionary] = []
	var cached_count: int = 0
	var failed_count: int = 0
	for entry: Dictionary in _load_entries:
		var kind: String = String(entry.get("kind", "resource"))
		if kind == "phase":
			phase_entries.append(entry)
		elif kind == "object":
			object_entries.append(entry)
		else:
			resource_entries.append(entry)
			if bool(entry.get("cached", false)):
				cached_count += 1
			if kind == "error":
				failed_count += 1
	resource_entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("request_seconds", 0.0)) > float(b.get("request_seconds", 0.0))
	)
	phase_entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("start_seconds", 0.0)) < float(b.get("start_seconds", 0.0))
	)
	file.store_line("LS5 Engine 3 Level Load Report")
	file.store_line("Generated: %s" % Time.get_datetime_string_from_system())
	file.store_line("Target: %s" % _report_target)
	file.store_line("Total tracked time: %.3f s" % total_seconds)
	file.store_line("Resources tracked: %d" % _tracked_resources.size())
	file.store_line("Initially cached: %d" % cached_count)
	file.store_line("Initially uncached: %d" % max(resource_entries.size() - cached_count - failed_count, 0))
	file.store_line("Failed: %d" % failed_count)
	file.store_line(
		"Retained cache: %d core, %d character, %d level, %d lookahead" % [
			LevelPreparationManager.get_scope_resource_count(LevelPreparationManager.SCOPE_CORE),
			LevelPreparationManager.get_scope_resource_count(LevelPreparationManager.SCOPE_CHARACTER),
			LevelPreparationManager.get_scope_resource_count(LevelPreparationManager.SCOPE_LEVEL),
			LevelPreparationManager.get_scope_resource_count(LevelPreparationManager.SCOPE_LOOKAHEAD)
		]
	)
	file.store_line("")
	file.store_line("Tracked roots")
	for root_value: Variant in _report_roots.keys():
		var root_ref: String = String(root_value)
		var root_counts: Dictionary = _get_root_resource_counts(root_ref, resource_entries)
		file.store_line(
			"%-8s %4d resources  %4d cached  latest completion %8.3f s  %s" % [
				String(_report_roots[root_ref]),
				int(root_counts.get("total", 0)),
				int(root_counts.get("cached", 0)),
				float(root_counts.get("latest_seconds", 0.0)),
				root_ref
			]
		)
	file.store_line("")
	file.store_line("Resource type summary")
	file.store_line(" Count  Cached  Longest request  Latest completion  Type")
	var type_entries: Array[Dictionary] = _build_resource_type_summary(resource_entries)
	for type_entry: Dictionary in type_entries:
		file.store_line(
			"%6d  %6d  %15.3f s  %17.3f s  %s" % [
				int(type_entry.get("count", 0)),
				int(type_entry.get("cached", 0)),
				float(type_entry.get("longest_request", 0.0)),
				float(type_entry.get("latest_completion", 0.0)),
				String(type_entry.get("extension", ""))
			]
		)
	file.store_line("")
	file.store_line("Slowest resource requests")
	file.store_line("Request time is queue-to-observed-completion latency. Concurrent requests and dependencies overlap, so it is not isolated resource processing time.")
	file.store_line("Only Root=yes entries are explicit threaded requests; other entries are dependencies resolved from the completed root cache.")
	file.store_line("  Queued   Request  Complete  Cache  Root  Owners                 Path")
	for entry: Dictionary in resource_entries:
		var kind: String = String(entry.get("kind", "resource"))
		var suffix: String = ""
		if kind == "error":
			suffix = " [FAILED: %s]" % String(entry.get("error", "Unknown error"))
		var cache_label: String = "yes" if bool(entry.get("cached", false)) else "no"
		file.store_line(
			"%8.3f  %8.3f  %8.3f  %-5s  %-4s  %-21s  %s%s" % [
				float(entry.get("queued_seconds", 0.0)),
				float(entry.get("request_seconds", 0.0)),
				float(entry.get("seconds", 0.0)),
				cache_label,
				"yes" if bool(entry.get("thread_root", false)) else "no",
				_format_owner_labels(entry.get("owners", [])),
				String(entry.get("path", "")),
				suffix
			]
		)
	file.store_line("")
	file.store_line("Scene setup timeline")
	file.store_line("Phases may overlap when scene callbacks and frame waits run concurrently.")
	file.store_line("   Start       End  Duration  Phase")
	for entry: Dictionary in phase_entries:
		file.store_line(
			"%8.3f  %8.3f  %8.3f  %s" % [
				float(entry.get("start_seconds", 0.0)),
				float(entry.get("end_seconds", 0.0)),
				float(entry.get("seconds", 0.0)),
				String(entry.get("path", ""))
			]
		)
	file.store_line("")
	file.store_line("Scene setup phases by duration")
	phase_entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("seconds", 0.0)) > float(b.get("seconds", 0.0))
	)
	for entry: Dictionary in phase_entries:
		file.store_line("%8.3f s  %s" % [float(entry.get("seconds", 0.0)), String(entry.get("path", ""))])
	file.store_line("")
	file.store_line("Slowest object preparation steps")
	file.store_line("Duration (ms)  Phase       Object")
	object_entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("seconds", 0.0)) > float(b.get("seconds", 0.0))
	)
	for entry: Dictionary in object_entries:
		file.store_line(
			"%13.3f  %-10s  %s" % [
				float(entry.get("seconds", 0.0)) * 1000.0,
				String(entry.get("phase", "")),
				String(entry.get("path", "")),
			]
		)


func _get_report_elapsed_seconds() -> float:
	if _report_start_usec <= 0:
		return 0.0
	return float(Time.get_ticks_usec() - _report_start_usec) / 1000000.0


func _get_root_resource_counts(root_ref: String, resource_entries: Array[Dictionary]) -> Dictionary:
	var total: int = 0
	var cached: int = 0
	var latest_seconds: float = 0.0
	for entry: Dictionary in resource_entries:
		var owners: Array[String] = []
		var owner_values: Array = entry.get("owners", []) as Array
		for owner_value: Variant in owner_values:
			owners.append(String(owner_value))
		if not owners.has(root_ref):
			continue
		total += 1
		if bool(entry.get("cached", false)):
			cached += 1
		latest_seconds = max(latest_seconds, float(entry.get("seconds", 0.0)))
	return {"total": total, "cached": cached, "latest_seconds": latest_seconds}


func _build_resource_type_summary(resource_entries: Array[Dictionary]) -> Array[Dictionary]:
	var by_extension: Dictionary = {}
	for entry: Dictionary in resource_entries:
		var extension: String = String(entry.get("path", "")).get_extension().to_lower()
		if extension == "":
			extension = "(none)"
		var summary: Dictionary = by_extension.get(extension, {
			"extension": extension,
			"count": 0,
			"cached": 0,
			"longest_request": 0.0,
			"latest_completion": 0.0
		})
		summary["count"] = int(summary.get("count", 0)) + 1
		if bool(entry.get("cached", false)):
			summary["cached"] = int(summary.get("cached", 0)) + 1
		summary["longest_request"] = max(
			float(summary.get("longest_request", 0.0)),
			float(entry.get("request_seconds", 0.0))
		)
		summary["latest_completion"] = max(
			float(summary.get("latest_completion", 0.0)),
			float(entry.get("seconds", 0.0))
		)
		by_extension[extension] = summary
	var summaries: Array[Dictionary] = []
	for summary_value: Variant in by_extension.values():
		if summary_value is Dictionary:
			summaries.append(summary_value as Dictionary)
	summaries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("count", 0)) > int(b.get("count", 0))
	)
	return summaries


func _format_owner_labels(owner_values: Variant) -> String:
	var labels: Array[String] = []
	if owner_values is Array:
		var owners: Array = owner_values as Array
		for owner_value: Variant in owners:
			var owner_ref: String = String(owner_value)
			var role: String = String(_report_roots.get(owner_ref, "Scene"))
			if not labels.has(role):
				labels.append(role)
	return "+".join(labels) if not labels.is_empty() else "Unassigned"


func _change_scene(scene_ref: String, packed_scene: PackedScene) -> void:
	if get_tree() == null:
		return
	if packed_scene == null:
		_show_load_failure("Could not load %s." % scene_ref)
		return
	_shell_change_start_usec = Time.get_ticks_usec()
	var scene_error: Error = get_tree().change_scene_to_packed(packed_scene)
	if scene_error != OK:
		_shell_change_start_usec = 0
		_show_load_failure("Could not open %s: %s" % [scene_ref, error_string(scene_error)])


func _show_load_failure(reason: String) -> void:
	_awaiting_level_handoff = false
	SceneDiagnostics.report_loading_problem(reason, _report_target)
	LevelPreparationManager.fail_level_preparation(_preparation_generation, reason)
	_load_entries.append({
		"path": _report_target,
		"seconds": _get_report_elapsed_seconds(),
		"kind": "error",
		"error": reason,
		"owners": []
	})
	_write_load_log()
	push_error("LoadingScreen: %s" % reason)
	if _failure_dialog != null:
		return
	_failure_dialog = AcceptDialog.new()
	_failure_dialog.exclusive = true
	_failure_dialog.title = "Loading failed"
	_failure_dialog.dialog_text = reason + "\n\nDetails were saved to level_load.log."
	_failure_dialog.ok_button_text = "Return to menu"
	_failure_dialog.add_button("Open Local Files", false, "logs")
	_failure_dialog.add_button("Inspect Dependencies", false, "dependencies")
	_failure_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"dependencies":
			_failure_dialog.hide()
			SceneDiagnostics.open_dependency_inspection(_failure_dialog)
		else:
			OS.shell_open(ProjectSettings.globalize_path("user://"))
	)
	_failure_dialog.confirmed.connect(_return_after_load_failure)
	_failure_dialog.canceled.connect(_return_after_load_failure)
	add_child(_failure_dialog)
	_failure_dialog.popup_centered(Vector2i(640, 220))
	_failure_dialog.get_ok_button().grab_focus()


func _return_after_load_failure() -> void:
	# The originating menu remains the current scene until the shell loads.
	var reload_error: Error = get_tree().reload_current_scene()
	if reload_error == OK:
		queue_free()
	else:
		_failure_dialog.dialog_text = "Could not restore the menu. Please restart the game."
		_failure_dialog.popup_centered()


func _update_banner_layout() -> void:
	if not is_node_ready():
		return
	var available_width: float = max(root.size.x - viewport_margin * 2.0, 1.0)
	var lower_width: float = min(minimum_banner_width, available_width)
	var banner_width: float = clamp(root.size.x * 0.62, lower_width, min(maximum_banner_width, available_width))
	banner.offset_left = -banner_width * 0.5
	banner.offset_right = banner_width * 0.5


func _ensure_rng_seeded() -> void:
	if _rng_seeded:
		return
	_rng.randomize()
	_rng_seeded = true


func _kill_transition_tween() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null


func _on_scene_changed() -> void:
	if _shell_change_start_usec > 0:
		record_loading_phase(
			"Changing shell scene and initializing shell objects",
			float(Time.get_ticks_usec() - _shell_change_start_usec) / 1000000.0
		)
		_shell_change_start_usec = 0
		_shell_frame_start_usec = Time.get_ticks_usec()
		if get_tree() != null:
			await get_tree().process_frame
		if _shell_frame_start_usec > 0:
			record_loading_phase(
				"First shell process frame",
				float(Time.get_ticks_usec() - _shell_frame_start_usec) / 1000000.0
			)
			_shell_frame_start_usec = 0
	if _awaiting_level_handoff:
		return
	LevelPreparationManager.complete_level_preparation(
		_preparation_generation,
		_report_target
	)
	queue_free()


func _enter_tree() -> void:
	if get_tree() != null and not get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	_kill_transition_tween()
	if get_tree() != null and get_tree().scene_changed.is_connected(_on_scene_changed):
		get_tree().scene_changed.disconnect(_on_scene_changed)

extends Area3D

const DeathPlane = preload("res://LS5Framework/Objects/Gameplay/DeathPlane.gd")
const DEFAULT_RACE_ID: String = "RACE01"
const MIN_RACE_GHOST_COUNT: int = 2
const MAX_RACE_GHOST_COUNT: int = 20
const DEFAULT_RACE_GHOST_COUNT: int = 3
const RACE_GHOST_PLAYBACK_GROUP: StringName = &"RaceGhostPlayback"
const LEADING_RACE_GHOST_GROUP: StringName = &"LeadingRaceGhost"
const WORLD_TEXT_MODEL_SCRIPT: Script = preload("res://LS5Framework/Scripts/UI/YawBillboardTextModel.gd")

enum RaceType {
	CLASSIC_RACE,
	COLLECTION_RACE,
	RING_RACE,
}

signal collection_progress_changed(player: Node, collected: int, required: int)
signal collection_race_completed(player: Node)
signal ring_race_completed(player: Node)

@export var active: bool = true
@export var one_shot: bool = false

@export_group("Race Type")
## Determines the objective and goal behavior for this race.
@export_enum("Classic Race", "Collection Race", "Ring Race") var race_type: int = RaceType.CLASSIC_RACE
## Number of collection items required to finish a Collection Race.
@export_range(1, 999, 1) var collection_required_count: int = 1
## Optional linked goal used to run the Collection Race finish sequence.
@export_node_path("Area3D") var collection_finish_goal_path: NodePath = NodePath("")
## Number of rings required to finish a Ring Race.
@export_range(1, 9999, 1) var ring_required_count: int = 100
## Optional linked goal used to run the Ring Race finish sequence.
@export_node_path("Area3D") var ring_finish_goal_path: NodePath = NodePath("")

@export_group("Activation")
@export var require_group_primary: StringName = &"Player"
@export var require_group_secondary: StringName = &"player"
@export var online_requires_interact: bool = true
@export var offline_requires_interact: bool = true
## Interaction prompt template. Use {race_type} to insert the configured race type.
@export var interact_prompt_text: String = "Press INTERACT to start {race_type}!"
@export var interact_prompt_duration: float = 9999.0

@export_group("Starting Line")
@export var starting_line_path: NodePath = NodePath("StartingLine")
@export var use_child_slots: bool = true
@export var starting_line_offset: Vector3 = Vector3.ZERO
## Marker whose local -Z direction sets camera yaw and pitch after race placement.
@export_node_path("Node3D") var camera_facing_direction_path: NodePath = NodePath("CameraFacingDirection")
## Optional marker whose local -Z direction sets player facing along the starting surface. Empty uses CameraFacingDirection.
@export_node_path("Node3D") var player_facing_direction_path: NodePath = NodePath("")

@export_group("UI")
@export var level_name: String = "LEVEL"
## Race ID must be 1-8 letters or digits.
@export_placeholder("1-8 letters or digits")
var race_id: String = DEFAULT_RACE_ID:
	set(value):
		_set_race_id(value)
	get:
		return _get_race_id()
@export var countdown_start_delay: float = 2.0
@export var countdown_seconds: int = 3
## Uses a fixed two-second READY/SET countdown instead of the numbered countdown.
@export var use_ready_set_go_countdown: bool = false
@export var go_duration: float = 1.0
const _DEFAULT_RACE_UI_SCENE_PATH: String = "res://LS5Framework/Scenes/Race/RaceUI.tscn"
const _DEFAULT_RACE_MENU_SCENE_PATH: String = "res://LS5Framework/Scenes/Race/RaceStartMenu.tscn"
const _DEFAULT_RACE_GHOST_SCENE_PATH: String = "res://LS5Framework/Scenes/Race/RaceGhost.tscn"
const POST_PROCESS_EXEMPT_3D_LAYER: int = 1 << 19

static var _missing_scene_paths: Dictionary = {}

@export var race_ui_scene: PackedScene = null
@export var race_settings_menu_scene: PackedScene = null
@export var ghost_scene: PackedScene = null

@export_subgroup("Race Label")
@export var race_label_enabled: bool = true
@export var race_label_offset: Vector3 = Vector3(0.0, 3.0, 0.0)
@export var race_label_pixel_size: float = 0.015
## Maximum text field width used by the world-space race label before the title wraps.
@export_range(100.0, 4000.0, 10.0) var race_label_width: float = 2160.0
@export var race_label_color: Color = Color(1, 1, 1, 1)
@export var race_label_no_depth_test: bool = true
@export var race_label_refresh_seconds: float = 1.0
## Scales and fades the world race label by camera distance.
@export var race_label_distance_fade_enabled: bool = true
## Camera distance where the world race label reaches 0 scale and opacity.
@export var race_label_distance_fade_distance: float = 400.0
## Fraction of fade distance that keeps opacity at full strength.
@export_range(0.0, 1.0, 0.01) var race_label_full_opacity_distance_fraction: float = 0.5

@export_group("Online")
# After the first player finishes, the server starts a countdown; when it ends, remaining racers are DNF
# and results are shown. Set to 0 to show results immediately after the first finish.
@export var online_dnf_countdown_duration: float = 60.0

@export_group("Fade")
@export var fade_out_duration: float = 0.525
@export var fade_hold_duration: float = 0.075
@export var fade_in_duration: float = 0.525
@export var fade_color: Color = Color(1, 1, 1, 1)
@export var music_fade_out_time: float = 0.5

@export_group("Controls")
@export var lock_controls_during_countdown: bool = true
@export var reset_hud_timer_on_start: bool = true

@export_group("Music")
@export var go_music_stream: AudioStream
@export var go_music_fade_in: float = 0.75
@export var go_music_fade_out: float = 0.0
## If true, the race music starts on GO and ignores early-start timing.
@export var go_music_play_on_go: bool = false
## Time (in seconds) after the title card SFX starts before beginning race music.
@export var go_music_pre_start_offset: float = 0.0
# Keep early-start offsets in a consistent, safe range.
const _MUSIC_TITLECARD_OFFSET_MAX: float = 5.0

@export_group("SFX")
@export var sfx_bus: StringName = &"UI"
@export var sfx_start_queue: AudioStream = preload("res://LS5Framework/Sounds/Menu/Race_Start_Queue.WAV")
@export var sfx_titlecard: AudioStream = preload("res://LS5Framework/Sounds/Menu/titlecard.wav")
@export var sfx_countdown: AudioStream = preload("res://LS5Framework/Sounds/Menu/Countdown.wav")
@export var sfx_go: AudioStream = preload("res://LS5Framework/Sounds/Menu/Countdown_GO.wav")
## Sound played for READY when the alternate countdown is enabled.
@export var sfx_ready: AudioStream = preload("res://LS5Framework/Sounds/Menu/Race_SonicR_Ready.wav")
## Sound played for SET when the alternate countdown is enabled.
@export var sfx_set: AudioStream = preload("res://LS5Framework/Sounds/Menu/Race_SonicR_Set.wav")
## Sound played for GO when the alternate countdown is enabled.
@export var sfx_ready_set_go: AudioStream = preload("res://LS5Framework/Sounds/Menu/Race_SonicR_Go.wav")

var _sequence_running: bool = false
var _has_fired: bool = false
var _candidate_player = null
var _waiting_for_network_go: bool = false
var _active_ui = null
var _active_player = null
var _network_countdown_released: bool = false
var _active_hud = null
var _sfx_player: AudioStreamPlayer = null
var _cancel_token: int = 0
var _race_label = null
var _race_label_refresh_timer: float = 0.0
var _interact_prompt_visible: bool = false
var _settings_menu = null
var _settings_menu_player = null
var _go_music_started: bool = false
var _pending_race_ghost_enabled: bool = false
var _pending_multiple_ghosts_enabled: bool = false
var _pending_ghost_count: int = DEFAULT_RACE_GHOST_COUNT
var _pending_record_ghost_enabled: bool = false
var _pending_selected_ghost_path: String = ""
var _race_id_internal: String = DEFAULT_RACE_ID
var _ghost_actors: Array[Node] = []
var _ghost_active_path: String = ""
var _ghost_record_player = null
var _ghost_samples: Array = []
var _ghost_record_elapsed: float = 0.0
var _ghost_sample_accum: float = 0.0
var _ghost_recording_active: bool = false
var _ghost_recording_capped: bool = false
var _ghost_recording_invalidated_by_debug: bool = false
var _ghost_record_tick_rate: int = GhostDataManager.DEFAULT_TICK_RATE
var _ghost_playback_tick_rate: int = GhostDataManager.DEFAULT_PLAYBACK_TICK_RATE
var _ghost_active_finish_time: float = 0.0
var _pending_ghost_payload: Dictionary = {}
var _collection_progress: Dictionary = {}
var _collection_finish_requested: Dictionary = {}
var _ring_finish_requested: Dictionary = {}


func _ready() -> void:
	_resolve_default_scenes()
	add_to_group("RaceStart")
	# Sensible defaults so it "just works" when dropped into a scene.
	monitoring = true
	monitorable = true
	# Detect bodies from any collision layer; filtering is done by groups/meta checks.
	collision_mask = 0xFFFFFFFF
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if race_label_enabled:
		_ensure_race_label()
		_update_race_label_text()
	if Engine.is_editor_hint():
		update_configuration_warnings()


func _resolve_default_scenes() -> void:
	if race_ui_scene == null:
		race_ui_scene = _safe_load_scene(_DEFAULT_RACE_UI_SCENE_PATH)
	if race_settings_menu_scene == null:
		race_settings_menu_scene = _safe_load_scene(_DEFAULT_RACE_MENU_SCENE_PATH)
	if ghost_scene == null:
		ghost_scene = _safe_load_scene(_DEFAULT_RACE_GHOST_SCENE_PATH)


func _set_race_id(value: String) -> void:
	var sanitized := _sanitize_race_id(value)
	if _race_id_internal == sanitized:
		return
	_race_id_internal = sanitized
	if Engine.is_editor_hint():
		set_deferred("race_id", _race_id_internal)
		update_configuration_warnings()


func _get_race_id() -> String:
	return _race_id_internal


func _safe_load_scene(path: String) -> PackedScene:
	if path.strip_edges() == "":
		return null
	if not ResourceLoader.exists(path):
		if not _missing_scene_paths.has(path):
			_missing_scene_paths[path] = true
			push_warning("RaceStart: missing scene: %s" % path)
		return null
	var res = load(path)
	if res is PackedScene:
		return res
	if not _missing_scene_paths.has(path):
		_missing_scene_paths[path] = true
		push_warning("RaceStart: expected PackedScene at %s" % path)
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not GhostDataManager.is_valid_race_id(_get_race_id_value()):
		warnings.append(GhostDataManager.get_race_id_rules_text())
	return warnings


func _get_race_id_value() -> String:
	return _race_id_internal


func _get_display_level_name() -> String:
	var display_level := level_name.strip_edges()
	if display_level == "":
		display_level = "LEVEL"
	return display_level


func get_race_type_name() -> String:
	if race_type == RaceType.COLLECTION_RACE:
		return GhostDataManager.RACE_TYPE_COLLECTION
	if race_type == RaceType.RING_RACE:
		return GhostDataManager.RACE_TYPE_RING
	return GhostDataManager.RACE_TYPE_CLASSIC


func is_collection_race() -> bool:
	return race_type == RaceType.COLLECTION_RACE


func is_ring_race() -> bool:
	return race_type == RaceType.RING_RACE


func uses_back_goal_ring() -> bool:
	return is_collection_race() or is_ring_race()


func get_high_score_key() -> String:
	var level_key: String = _get_level_key()
	if race_type == RaceType.CLASSIC_RACE:
		return level_key
	return "%s::%s::%s" % [level_key, _get_race_id_value(), get_race_type_name()]


func get_collection_progress(player: Node) -> int:
	if player == null or not is_instance_valid(player):
		return 0
	return int(_collection_progress.get(player.get_instance_id(), 0))


func can_accept_collection_item(player: Node, collection_item: Node) -> bool:
	if not is_collection_race():
		return false
	if player == null or not is_instance_valid(player):
		return false
	if not _is_player_collection_active(player):
		return false
	if collection_item != null and is_instance_valid(collection_item):
		if collection_item.has_method("is_for_race_start"):
			var is_linked = collection_item.call("is_for_race_start", self)
			if is_linked is bool and not bool(is_linked):
				return false

	var player_id: int = player.get_instance_id()
	if bool(_collection_finish_requested.get(player_id, false)):
		return false
	return true


func collect_collection_item(player: Node, collection_item: Node) -> bool:
	if not can_accept_collection_item(player, collection_item):
		return false
	var player_id: int = player.get_instance_id()
	var required: int = max(collection_required_count, 1)
	var collected: int = min(int(_collection_progress.get(player_id, 0)) + 1, required)
	_collection_progress[player_id] = collected
	collection_progress_changed.emit(player, collected, required)
	if player.has_method("show_prompt"):
		player.call("show_prompt", "Collection items: %d / %d" % [collected, required], 2.0)
	if collected >= required:
		_collection_finish_requested[player_id] = true
		_set_collection_items_active_for_race(false)
		call_deferred("_finish_collection_race", player)
	return true


func _is_player_collection_active(player: Node) -> bool:
	if not player.has_method("get"):
		return false
	var active_value = player.get("race_active")
	var finished_value = player.get("race_finished")
	var is_active: bool = active_value is bool and bool(active_value)
	var is_finished: bool = finished_value is bool and bool(finished_value)
	return is_active and not is_finished


func _finish_collection_race(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not _is_player_collection_active(player):
		return
	var goal: Node = _resolve_collection_finish_goal()
	if goal == null:
		push_warning("RaceStart: Collection Race requires a linked RaceGoal.")
		_collection_finish_requested.erase(player.get_instance_id())
		_set_collection_items_active_for_race(true)
		return
	collection_race_completed.emit(player)
	if goal.has_method("finish_for_player"):
		goal.call("finish_for_player", player)


func _resolve_collection_finish_goal() -> Node:
	return _resolve_objective_finish_goal(collection_finish_goal_path)


func _resolve_ring_finish_goal() -> Node:
	return _resolve_objective_finish_goal(ring_finish_goal_path)


func _resolve_objective_finish_goal(goal_path: NodePath) -> Node:
	if goal_path != NodePath(""):
		var explicit_goal: Node = get_node_or_null(goal_path)
		if explicit_goal == null and get_tree() != null and get_tree().current_scene != null:
			explicit_goal = get_tree().current_scene.get_node_or_null(goal_path)
		if explicit_goal != null and is_instance_valid(explicit_goal):
			return explicit_goal
	if get_tree() == null:
		return null
	for goal in get_tree().get_nodes_in_group("RaceGoal"):
		if goal != null and is_instance_valid(goal) and _is_goal_for_this_race(goal):
			return goal
	return null


func _reset_collection_progress() -> void:
	_collection_progress.clear()
	_collection_finish_requested.clear()
	_ring_finish_requested.clear()


func _set_collection_items_active_for_race(is_enabled: bool) -> void:
	if get_tree() == null:
		return
	for collection_item in get_tree().get_nodes_in_group("RaceCollectionItem"):
		if collection_item == null or not is_instance_valid(collection_item):
			continue
		if not _is_collection_item_for_this_race(collection_item):
			continue
		if collection_item.has_method("set_active_for_race"):
			collection_item.call("set_active_for_race", is_enabled and is_collection_race())


func _is_collection_item_for_this_race(collection_item: Node) -> bool:
	if collection_item.has_method("is_for_race_start"):
		var matches = collection_item.call("is_for_race_start", self)
		if matches is bool:
			return bool(matches)
	return false


func _prepare_race_object_layouts() -> void:
	_clear_race_object_blacklists()
	if get_tree() == null:
		return
	var started_race_id: String = _get_race_id_value()
	for layout in get_tree().get_nodes_in_group("RaceObjectLayout"):
		if layout != null and is_instance_valid(layout) and layout.has_method("set_active_for_race_id"):
			layout.call("set_active_for_race_id", started_race_id)


func _apply_race_object_blacklists() -> void:
	if get_tree() == null:
		return
	var started_race_id: String = _get_race_id_value()
	for blacklist in get_tree().get_nodes_in_group("RaceObjectBlacklist"):
		if blacklist != null and is_instance_valid(blacklist) and blacklist.has_method("set_active_race_id"):
			blacklist.call("set_active_race_id", started_race_id)


func deactivate_race_objects() -> void:
	_clear_race_object_blacklists()
	if get_tree() == null:
		return
	for layout in get_tree().get_nodes_in_group("RaceObjectLayout"):
		if layout != null and is_instance_valid(layout) and layout.has_method("set_layout_enabled"):
			layout.call("set_layout_enabled", false)


func _clear_race_object_blacklists() -> void:
	if get_tree() == null:
		return
	for blacklist in get_tree().get_nodes_in_group("RaceObjectBlacklist"):
		if blacklist != null and is_instance_valid(blacklist) and blacklist.has_method("clear_active_race"):
			blacklist.call("clear_active_race")


func _sanitize_race_id(value: String) -> String:
	var source := ""
	if value is String:
		source = (value as String).strip_edges()
	var output := ""
	for i in range(source.length()):
		if output.length() >= 8:
			break
		var code := source.unicode_at(i)
		if _is_race_id_code_allowed(code):
			output += source.substr(i, 1)
	if output == "":
		output = DEFAULT_RACE_ID
	return output


func _is_race_id_code_allowed(code: int) -> bool:
	var is_digit := code >= 48 and code <= 57
	var is_upper := code >= 65 and code <= 90
	var is_lower := code >= 97 and code <= 122
	return is_digit or is_upper or is_lower


func _can_use_ghost_features() -> bool:
	if _is_online():
		return false
	return GhostDataManager.is_valid_race_id(_get_race_id_value())


func _get_saved_ghost_preferences() -> Dictionary:
	var out := {
		"race_ghost_enabled": false,
		"multiple_ghosts_enabled": false,
		"ghost_count": DEFAULT_RACE_GHOST_COUNT,
		"record_ghost_enabled": false,
		"recording_tick_rate": GhostDataManager.DEFAULT_TICK_RATE,
		"playback_tick_rate": GhostDataManager.DEFAULT_PLAYBACK_TICK_RATE,
		"selected_ghost_path": ""
	}
	var settings = _get_settings_manager()
	if settings == null or not settings.has_method("get"):
		return out
	var race_enabled = settings.get("race_ghost_enabled")
	if race_enabled is bool:
		out["race_ghost_enabled"] = bool(race_enabled)
	var multiple_enabled = settings.get("race_multiple_ghosts_enabled")
	if multiple_enabled is bool:
		out["multiple_ghosts_enabled"] = bool(multiple_enabled)
	var ghost_count = settings.get("race_ghost_count")
	if ghost_count is int:
		out["ghost_count"] = clampi(int(ghost_count), MIN_RACE_GHOST_COUNT, MAX_RACE_GHOST_COUNT)
	var record_enabled = settings.get("race_record_ghost_data")
	if record_enabled is bool:
		out["record_ghost_enabled"] = bool(record_enabled)
	var selected_path = settings.get("race_selected_ghost_path")
	if selected_path is String:
		out["selected_ghost_path"] = String(selected_path)
	var recording_rate = settings.get("race_ghost_recording_rate")
	if recording_rate is int:
		out["recording_tick_rate"] = GhostDataManager.normalize_recording_tick_rate(int(recording_rate))
	var playback_rate = settings.get("race_ghost_playback_rate")
	if playback_rate is int:
		out["playback_tick_rate"] = GhostDataManager.normalize_recording_tick_rate(int(playback_rate))
	return out


func _validate_saved_ghost_path(path: String) -> String:
	if path.strip_edges() == "":
		return ""
	var data := GhostDataManager.load_ghost(path)
	if data.is_empty():
		return ""
	if not GhostDataManager.is_ghost_for_context(data, _get_level_key(), _get_race_id_value(), get_race_type_name()):
		return ""
	return path


func _configure_pending_ghost_settings(race_ghost_enabled: bool, record_ghost_enabled: bool, selected_ghost_path: String, multiple_ghosts_enabled: bool = false, ghost_count: int = DEFAULT_RACE_GHOST_COUNT) -> void:
	_pending_selected_ghost_path = _validate_saved_ghost_path(selected_ghost_path)
	var ghost_preferences: Dictionary = _get_saved_ghost_preferences()
	_ghost_record_tick_rate = GhostDataManager.normalize_recording_tick_rate(int(ghost_preferences.get("recording_tick_rate", GhostDataManager.DEFAULT_TICK_RATE)))
	_ghost_playback_tick_rate = GhostDataManager.normalize_recording_tick_rate(int(ghost_preferences.get("playback_tick_rate", GhostDataManager.DEFAULT_PLAYBACK_TICK_RATE)))
	var allowed := _can_use_ghost_features()
	_pending_race_ghost_enabled = allowed and race_ghost_enabled
	_pending_multiple_ghosts_enabled = _pending_race_ghost_enabled and multiple_ghosts_enabled
	_pending_ghost_count = clampi(ghost_count, MIN_RACE_GHOST_COUNT, MAX_RACE_GHOST_COUNT)
	_pending_record_ghost_enabled = allowed and record_ghost_enabled


func _resolve_pending_ghost_paths() -> Array[String]:
	var paths: Array[String] = []
	if not _pending_race_ghost_enabled:
		return paths
	var ranked_ghosts: Array = GhostDataManager.list_ghosts_for_race(_get_display_level_name(), _get_level_key(), _get_race_id_value(), get_race_type_name())
	var selected_path: String = _validate_saved_ghost_path(_pending_selected_ghost_path)
	var next_rank_index: int = 0
	if selected_path != "":
		paths.append(selected_path)
		next_rank_index = -1
		for rank_index: int in range(ranked_ghosts.size()):
			var ranked_value = ranked_ghosts[rank_index]
			if ranked_value is Dictionary and String((ranked_value as Dictionary).get("path", "")) == selected_path:
				next_rank_index = rank_index + 1
				break
	elif not ranked_ghosts.is_empty():
		var best_value = ranked_ghosts[0]
		if best_value is Dictionary:
			var best_path: String = String((best_value as Dictionary).get("path", ""))
			if best_path != "":
				paths.append(best_path)
				next_rank_index = 1
	var maximum_count: int = _pending_ghost_count if _pending_multiple_ghosts_enabled else 1
	if not _pending_multiple_ghosts_enabled or next_rank_index < 0:
		return paths
	for rank_index: int in range(next_rank_index, ranked_ghosts.size()):
		if paths.size() >= maximum_count:
			break
		var summary_value = ranked_ghosts[rank_index]
		if not (summary_value is Dictionary):
			continue
		var summary: Dictionary = summary_value
		var path: String = String(summary.get("path", ""))
		if path != "" and not paths.has(path):
			paths.append(path)
	return paths


func _spawn_ghost_actor() -> Node:
	if ghost_scene == null:
		_resolve_default_scenes()
	if ghost_scene == null:
		return null
	var inst = ghost_scene.instantiate()
	if inst == null:
		return null
	var parent_node := _get_menu_parent()
	if parent_node != null:
		parent_node.add_child(inst)
	else:
		add_child(inst)
	inst.add_to_group(RACE_GHOST_PLAYBACK_GROUP)
	inst.add_to_group(&"LevelTransient")
	_ghost_actors.append(inst)
	return inst


func _prepare_ghost_runtime(player: Node) -> void:
	_clear_ghost_runtime()
	if not _can_use_ghost_features():
		return
	if _pending_race_ghost_enabled:
		var ghost_paths: Array[String] = _resolve_pending_ghost_paths()
		for ghost_index: int in range(ghost_paths.size()):
			var ghost_path: String = ghost_paths[ghost_index]
			var ghost_data: Dictionary = GhostDataManager.load_ghost(ghost_path)
			if not ghost_data.is_empty():
				var actor = _spawn_ghost_actor()
				if actor != null and actor.has_method("set_ghost_data"):
					actor.name = "RaceGhost_%02d" % (ghost_index + 1)
					if actor.has_method("configure_visual_from_player"):
						actor.call("configure_visual_from_player", player)
					if actor.has_method("set_playback_tick_rate"):
						actor.call("set_playback_tick_rate", _ghost_playback_tick_rate)
					if actor.has_method("set_visual_opacity"):
						var lineup_opacity: float = 0.65 if ghost_index == 0 else max(0.26, 0.42 - float((ghost_index - 1) % 5) * 0.04)
						actor.call("set_visual_opacity", lineup_opacity)
					actor.call("set_ghost_data", ghost_data)
					if _ghost_active_path == "":
						_register_leading_ghost(actor)
						_ghost_active_path = ghost_path
						_ghost_active_finish_time = float(ghost_data.get("finish_time", 0.0))
	if _pending_record_ghost_enabled and player != null and is_instance_valid(player):
		_ghost_record_player = player
		_ghost_record_elapsed = 0.0
		_ghost_sample_accum = 0.0
		_ghost_recording_active = false
		_ghost_recording_capped = false
		_ghost_recording_invalidated_by_debug = false
		_ghost_samples.clear()


func _register_leading_ghost(actor: Node) -> void:
	actor.add_to_group(LEADING_RACE_GHOST_GROUP)
	if actor.has_signal("playback_finished"):
		actor.connect("playback_finished", _on_leading_ghost_finished.bind(actor), CONNECT_ONE_SHOT)


func _on_leading_ghost_finished(actor: Node) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion() or not _ghost_actors.has(actor):
		return
	HUDMusicTrackDisplay.post_notification(get_tree(), "Ghost Finished", "The chosen ghost has reached the goal.")


func _start_ghost_runtime() -> void:
	for actor: Node in _ghost_actors:
		if is_instance_valid(actor) and actor.has_method("start_playback"):
			actor.call("start_playback")
	if _pending_record_ghost_enabled and _ghost_record_player != null and is_instance_valid(_ghost_record_player):
		if _ghost_recording_invalidated_by_debug or _is_ghost_recording_invalidated_by_debug():
			_invalidate_ghost_recording_debug()
			return
		_ghost_recording_active = true
		_ghost_recording_capped = false
		_ghost_recording_invalidated_by_debug = false
		_ghost_record_elapsed = 0.0
		_ghost_sample_accum = 0.0
		_ghost_samples.clear()
		_append_ghost_sample(_ghost_record_player, 0.0)


func _tick_ghost_recording(delta: float) -> void:
	if not _ghost_recording_active:
		return
	if get_tree().paused:
		return
	if _ghost_record_player == null or not is_instance_valid(_ghost_record_player):
		_ghost_recording_active = false
		return
	if _is_ghost_recording_invalidated_by_debug():
		_invalidate_ghost_recording_debug()
		return
	var remaining := GhostDataManager.MAX_DURATION_SECONDS - _ghost_record_elapsed
	if remaining <= 0.0:
		_ghost_recording_active = false
		_ghost_recording_capped = true
		return
	var step: float = min(max(delta, 0.0), remaining)
	_ghost_record_elapsed += step
	_ghost_sample_accum += step
	var interval: float = GhostDataManager.get_tick_interval(_ghost_record_tick_rate)
	while _ghost_sample_accum >= interval:
		_ghost_sample_accum -= interval
		_append_ghost_sample(_ghost_record_player, _ghost_record_elapsed - _ghost_sample_accum)
	if _ghost_record_elapsed >= GhostDataManager.MAX_DURATION_SECONDS:
		_ghost_recording_active = false
		_ghost_recording_capped = true


func _append_ghost_sample(player: Node, sample_time: float) -> void:
	if player == null or not is_instance_valid(player) or not (player is Node3D):
		return
	var xf: Transform3D = (player as Node3D).global_transform
	if player.has_method("get"):
		var model_root = player.get("model_root")
		if model_root != null and is_instance_valid(model_root) and (model_root is Node3D):
			xf = (model_root as Node3D).global_transform
	var pos: Vector3 = xf.origin
	var rot: Quaternion = xf.basis.get_rotation_quaternion().normalized()
	var speed: float = 0.0
	var airborne: bool = false
	var rolling: bool = false
	var grinding: bool = false
	if player.has_method("get"):
		var velocity_value = player.get("velocity")
		if velocity_value is Vector3:
			speed = (velocity_value as Vector3).length()
		var attached_value = player.get("attached")
		if attached_value is bool:
			airborne = not bool(attached_value)
		var rolling_value = player.get("rolling")
		if rolling_value is bool:
			rolling = bool(rolling_value)
		var rail_active_value = player.get("_rail_active")
		if rail_active_value is bool:
			grinding = bool(rail_active_value)
	var sample := {
		"t": clamp(sample_time, 0.0, GhostDataManager.MAX_DURATION_SECONDS),
		"position": [pos.x, pos.y, pos.z],
		"rotation": [rot.x, rot.y, rot.z, rot.w],
		"speed": speed,
		"airborne": airborne,
		"rolling": rolling,
		"grinding": grinding
	}
	if not _ghost_samples.is_empty():
		var last = _ghost_samples[_ghost_samples.size() - 1]
		if last is Dictionary and float((last as Dictionary).get("t", -1.0)) >= float(sample.get("t", 0.0)):
			_ghost_samples[_ghost_samples.size() - 1] = sample
			return
	_ghost_samples.append(sample)


func invalidate_ghost_recording_for_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player != _ghost_record_player:
		return
	_invalidate_ghost_recording_debug()


func _is_ghost_recording_invalidated_by_debug() -> bool:
	if _ghost_record_player == null or not is_instance_valid(_ghost_record_player):
		return false
	if not _ghost_record_player.has_method("get"):
		return false
	var debug_value = _ghost_record_player.get("race_debug_used")
	if debug_value is bool and bool(debug_value):
		return true
	return false


func _invalidate_ghost_recording_debug() -> void:
	_ghost_recording_active = false
	_ghost_recording_invalidated_by_debug = true
	_ghost_samples.clear()


func _clear_ghost_runtime(discard_pending: bool = true) -> void:
	_ghost_recording_active = false
	_ghost_record_player = null
	_ghost_record_elapsed = 0.0
	_ghost_sample_accum = 0.0
	_ghost_recording_capped = false
	_ghost_recording_invalidated_by_debug = false
	_ghost_samples.clear()
	_ghost_active_path = ""
	_ghost_active_finish_time = 0.0
	if discard_pending:
		_pending_ghost_payload.clear()
	var actors_to_clear: Array[Node] = []
	for actor: Node in _ghost_actors:
		if is_instance_valid(actor) and not actors_to_clear.has(actor):
			actors_to_clear.append(actor)
	if get_tree() != null:
		for actor: Node in get_tree().get_nodes_in_group(RACE_GHOST_PLAYBACK_GROUP):
			if is_instance_valid(actor) and not actors_to_clear.has(actor):
				actors_to_clear.append(actor)
	for actor: Node in actors_to_clear:
		_dispose_ghost_actor(actor)
	_ghost_actors.clear()


func _dispose_ghost_actor(actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_method("clear_playback"):
		actor.call("clear_playback")
	actor.set_process(false)
	actor.set_physics_process(false)
	var parent: Node = actor.get_parent()
	if parent != null:
		parent.remove_child(actor)
	if not actor.is_queued_for_deletion():
		actor.queue_free()


func finalize_local_ghost_run(player: Node, finish_time: float, score: int, debug_used: bool) -> String:
	var note := ""
	_pending_ghost_payload.clear()
	var is_record_player: bool = player != null and is_instance_valid(player) and player == _ghost_record_player
	if _ghost_recording_active and is_record_player:
		_append_ghost_sample(player, min(finish_time, GhostDataManager.MAX_DURATION_SECONDS))
	_ghost_recording_active = false
	if _pending_record_ghost_enabled and is_record_player:
		if debug_used or _ghost_recording_invalidated_by_debug:
			note = "Ghost not saved: debug used."
		elif finish_time > GhostDataManager.MAX_DURATION_SECONDS or _ghost_recording_capped:
			note = "Ghost not saved: race exceeded 5:00."
		elif not _ghost_samples.is_empty():
			_pending_ghost_payload = GhostDataManager.build_ghost_payload(_get_display_level_name(), _get_level_key(), _get_race_id_value(), finish_time, score, _ghost_samples, get_race_type_name(), _ghost_record_tick_rate)
			note = "Unsaved ghost ready: %d Hz, %d samples." % [_ghost_record_tick_rate, _ghost_samples.size()]
	_clear_ghost_runtime(false)
	return note


func has_pending_ghost_run() -> bool:
	return not _pending_ghost_payload.is_empty()


func get_pending_ghost_summary() -> Dictionary:
	if _pending_ghost_payload.is_empty():
		return {}
	var samples: Array = _pending_ghost_payload.get("samples", []) as Array
	return {
		"tick_rate": GhostDataManager.get_payload_tick_rate(_pending_ghost_payload),
		"sample_count": samples.size(),
		"finish_time": float(_pending_ghost_payload.get("finish_time", 0.0)),
		"formatted_time": GhostDataManager.format_time(float(_pending_ghost_payload.get("finish_time", 0.0)))
	}


func save_pending_ghost_run() -> String:
	if _pending_ghost_payload.is_empty():
		return ""
	var saved_path: String = GhostDataManager.save_ghost(_pending_ghost_payload)
	if saved_path != "":
		_pending_ghost_payload.clear()
	return saved_path


func discard_pending_ghost_run() -> void:
	_pending_ghost_payload.clear()


func get_active_ghost_time_comparison(finish_time: float) -> String:
	if _ghost_active_finish_time <= 0.0 or finish_time <= 0.0:
		return ""
	var difference: float = abs(finish_time - _ghost_active_finish_time)
	if is_equal_approx(difference, 0.0):
		return "Matched the ghost time."
	if finish_time < _ghost_active_finish_time:
		return "Beat the ghost by %s." % GhostDataManager.format_time(difference)
	return "Ghost finished %s ahead." % GhostDataManager.format_time(difference)


func _on_body_entered(body: Node) -> void:
	if not active or _sequence_running:
		return
	if one_shot and _has_fired:
		return
	if body == null:
		return
	if not (body is CharacterBody3D):
		return
	if _is_player_in_race(body):
		return
	# Buddy pawns should never start races.
	if body.has_method("has_meta") and body.call("has_meta", "is_buddy"):
		var v = body.call("get_meta", "is_buddy")
		if v is bool and bool(v):
			return

	if require_group_primary != &"" and body.is_in_group(require_group_primary):
		pass
	elif require_group_secondary != &"" and body.is_in_group(require_group_secondary):
		pass
	else:
		# Fallback for scenes that didn't add the player to groups yet.
		# Keep buddy exclusion above, so this doesn't catch the buddy pawn.
		var looks_like_player: bool = body.has_method("set_ui_input_blocked") and body.has_method("_apply_respawn_transform")
		if not looks_like_player:
			return

	# Only affect the local authority in multiplayer.
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if body.has_method("is_multiplayer_authority") and not body.is_multiplayer_authority():
			return

	var wants_interact: bool = (_is_online() and online_requires_interact) or ((not _is_online()) and offline_requires_interact)
	if wants_interact:
		var session = _get_network_session()
		if _is_online() and session != null and session.has_method("is_race_busy"):
			var busy = session.call("is_race_busy")
			if busy is bool and bool(busy):
				return
		_candidate_player = body
		if _is_player_ui_blocked(body):
			_interact_prompt_visible = false
			return
		_show_interact_prompt()
	else:
		call_deferred("_open_race_settings_menu", body)


func _on_body_exited(body: Node) -> void:
	if body == null:
		return
	if _candidate_player != null and body == _candidate_player:
		_hide_interact_prompt()
		_interact_prompt_visible = false
		_candidate_player = null
	if _settings_menu_player == body:
		_close_race_settings_menu(false)


func cancel_for_player(player: Node) -> void:
	# Cancels any in-progress countdown/setup for this RaceStart (used when leaving the race/queue).
	if player == null or not is_instance_valid(player):
		return
	var should_cancel: bool = false
	if _candidate_player == player:
		should_cancel = true
	if _active_player == player:
		should_cancel = true
	if not should_cancel:
		return

	_cancel_token += 1
	_network_countdown_released = false
	_go_music_started = false
	_release_active_player(player)
	if get_tree():
		for fader: Node in get_tree().get_nodes_in_group("ScreenFader"):
			if fader.has_method("reset_now"):
				fader.call("reset_now")
	if player.has_method("_restore_autoplay_music"):
		player.call("_restore_autoplay_music")
	_waiting_for_network_go = false
	_sequence_running = false
	_hide_interact_prompt()
	_interact_prompt_visible = false
	_candidate_player = null
	if not one_shot:
		_has_fired = false

	if _active_ui != null and is_instance_valid(_active_ui):
		_active_ui.queue_free()
	_active_ui = null
	_close_race_settings_menu(false)
	_clear_ghost_runtime()

	# Restore HUD timer if we stopped it.
	if _active_hud != null and is_instance_valid(_active_hud):
		if _active_hud.has_method("set_timer_running"):
			_active_hud.call("set_timer_running", true)
	_active_hud = null

	if player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", false)
	if player.has_method("set"):
		player.set("race_session_joined", false)
		player.set("race_in_countdown", false)
		player.set("race_active", false)
		player.set("race_finished", false)
	_set_goals_active_for_race(false)
	_set_collection_items_active_for_race(false)
	deactivate_race_objects()


func _exit_tree() -> void:
	_hide_interact_prompt()
	_candidate_player = null
	_close_race_settings_menu(false)
	_set_collection_items_active_for_race(false)
	_reset_collection_progress()
	if not _server_race_session_still_active():
		deactivate_race_objects()
	_clear_ghost_runtime()

	_active_player = null
	_go_music_started = false


func _server_race_session_still_active() -> bool:
	if not _is_online() or not multiplayer.is_server():
		return false
	var session: Node = _get_network_session()
	if session == null or not session.has_method("is_race_session_active"):
		return false
	var active_value = session.call("is_race_session_active")
	return active_value is bool and bool(active_value)


func _process(delta: float) -> void:
	_update_race_label(delta)
	_tick_ghost_recording(delta)
	_cleanup_stale_settings_menu()
	if get_tree() != null and get_tree().paused:
		return
	_check_ring_race_completion()
	var wants_interact: bool = (_is_online() and online_requires_interact) or ((not _is_online()) and offline_requires_interact)
	if not wants_interact:
		return
	var session = _get_network_session()
	if _is_online() and session != null and session.has_method("is_race_busy"):
		var busy_val = session.call("is_race_busy")
		var busy: bool = false
		if busy_val is bool:
			busy = bool(busy_val)
		if busy:
			if _interact_prompt_visible:
				_hide_interact_prompt()
			_interact_prompt_visible = false
			_candidate_player = null
			return
	var overlapping_bodies: Array = get_overlapping_bodies()
	if _candidate_player != null:
		if not is_instance_valid(_candidate_player):
			_candidate_player = null
		elif not overlapping_bodies.has(_candidate_player):
			_hide_interact_prompt()
			_interact_prompt_visible = false
			_candidate_player = null
	if _candidate_player == null:
		_candidate_player = _refresh_candidate_from_overlaps(wants_interact, overlapping_bodies)
	if _sequence_running or _settings_menu != null or _candidate_player == null:
		return
	if not is_instance_valid(_candidate_player):
		_candidate_player = null
		return
	if _is_player_in_race(_candidate_player):
		_hide_interact_prompt()
		_interact_prompt_visible = false
		_candidate_player = null
		return
	if _is_player_ui_blocked(_candidate_player):
		if _interact_prompt_visible:
			_hide_interact_prompt()
		return
	if _candidate_player.has_method("is_post_ui_action_suppressed"):
		var sup = _candidate_player.call("is_post_ui_action_suppressed")
		if sup is bool and bool(sup):
			if _interact_prompt_visible:
				_hide_interact_prompt()
			return
	if not _interact_prompt_visible:
		_show_interact_prompt()
	if Input.is_action_just_pressed("interact"):
		_hide_interact_prompt()
		call_deferred("_open_race_settings_menu", _candidate_player)


func _cleanup_stale_settings_menu() -> void:
	# In online play, UI layers can be freed externally (scene changes, session resets).
	# If that happens, ensure the player is unfrozen and the cached references are cleared.
	if _settings_menu != null and not is_instance_valid(_settings_menu):
		_settings_menu = null
		var player = _settings_menu_player
		_settings_menu_player = null
		_unfreeze_player_for_menu(player)


func _refresh_candidate_from_overlaps(wants_interact: bool, overlapping_bodies: Array) -> Node:
	if not wants_interact:
		return null
	if not active or _sequence_running:
		return null
	if one_shot and _has_fired:
		return null

	var session = _get_network_session()
	if _is_online() and session != null and session.has_method("is_race_busy"):
		var busy_val = session.call("is_race_busy")
		var busy: bool = false
		if busy_val is bool:
			busy = bool(busy_val)
		if busy:
			if _interact_prompt_visible:
				_hide_interact_prompt()
			return null

	for body_any in overlapping_bodies:
		var body: Node = body_any
		if not _is_valid_candidate_player(body):
			continue
		if _is_player_ui_blocked(body):
			continue
		return body
	return null


func _is_valid_candidate_player(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not (body is CharacterBody3D):
		return false
	if _is_player_in_race(body):
		return false
	# Buddy pawns should never start races.
	if body.has_method("has_meta") and body.call("has_meta", "is_buddy"):
		var v = body.call("get_meta", "is_buddy")
		if v is bool and bool(v):
			return false

	if require_group_primary != &"" and body.is_in_group(require_group_primary):
		pass
	elif require_group_secondary != &"" and body.is_in_group(require_group_secondary):
		pass
	else:
		# Fallback for scenes that didn't add the player to groups yet.
		# Keep buddy exclusion above, so this doesn't catch the buddy pawn.
		var looks_like_player: bool = body.has_method("set_ui_input_blocked") and body.has_method("_apply_respawn_transform")
		if not looks_like_player:
			return false

	# Only affect the local authority in multiplayer.
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if body.has_method("is_multiplayer_authority") and not body.is_multiplayer_authority():
			return false

	return true


func _update_race_label(delta: float) -> void:
	if not race_label_enabled:
		if _race_label != null:
			_race_label.queue_free()
			_race_label = null
		return

	_ensure_race_label()
	if _race_label == null:
		return
	_update_race_label_distance_visibility()

	if race_label_refresh_seconds <= 0.0:
		_update_race_label_text()
		return

	_race_label_refresh_timer -= delta
	if _race_label_refresh_timer > 0.0:
		return
	_race_label_refresh_timer = race_label_refresh_seconds
	_update_race_label_text()


func _ensure_race_label() -> void:
	if _race_label != null:
		return
	var label = get_node_or_null("RaceLabel")
	if label == null or not label.has_method("set_title_and_info"):
		var existing_label: Node = label as Node
		if existing_label != null:
			remove_child(existing_label)
			existing_label.queue_free()
		label = WORLD_TEXT_MODEL_SCRIPT.new()
		label.name = "RaceLabel"
		add_child(label)
	_race_label = label
	_apply_race_label_visuals()


func _update_race_label_text() -> void:
	if _race_label == null:
		return
	_apply_race_label_visuals()
	var display_level: String = _get_display_level_name()
	var race_id_text: String = _get_race_id_value()
	if race_id_text == "" or not GhostDataManager.is_valid_race_id(race_id_text):
		race_id_text = "INVALID"
	var level_key: String = get_high_score_key()
	var best_time: float = HighScoreManager.get_best_time(level_key)
	var best_text: String = "--:--:--"
	if best_time >= 0.0:
		best_text = _format_time_value(best_time)
	var collection_text: String = ""
	if is_collection_race():
		collection_text = "\nREQUIRED ITEMS  %d" % max(collection_required_count, 1)
	elif is_ring_race():
		collection_text = "\nREQUIRED RINGS  %d" % max(ring_required_count, 1)
	var info: String = "%s\nRACE ID  %s%s\nHIGH SCORE  %s" % [get_race_type_name(), race_id_text, collection_text, best_text]
	_race_label.set_title_and_info(display_level, info)


func _apply_race_label_visuals() -> void:
	if _race_label == null:
		return
	var panel_width: float = race_label_width * race_label_pixel_size * 0.4
	_race_label.configure(race_label_pixel_size, race_label_color, race_label_no_depth_test, POST_PROCESS_EXEMPT_3D_LAYER, panel_width)
	if _race_label.position != race_label_offset:
		_race_label.position = race_label_offset


func _update_race_label_distance_visibility() -> void:
	if _race_label == null:
		return
	if not race_label_distance_fade_enabled:
		if not _race_label.visible:
			_race_label.visible = true
		if _race_label.scale != Vector3.ONE:
			_race_label.scale = Vector3.ONE
		_race_label.set_opacity(1.0)
		return

	var fade_distance: float = max(race_label_distance_fade_distance, 0.001)
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var view_camera: Camera3D = viewport.get_camera_3d()
	if view_camera == null:
		return

	var camera_distance: float = view_camera.global_position.distance_to(_race_label.global_position)
	var distance_fraction: float = clamp(camera_distance / fade_distance, 0.0, 1.0)
	var scale_factor: float = 1.0 - distance_fraction
	var opacity_start_fraction: float = clamp(race_label_full_opacity_distance_fraction, 0.0, 1.0)
	var alpha_factor: float = 1.0
	if distance_fraction > opacity_start_fraction:
		var fade_span: float = max(1.0 - opacity_start_fraction, 0.001)
		alpha_factor = 1.0 - clamp((distance_fraction - opacity_start_fraction) / fade_span, 0.0, 1.0)

	var label_scale: Vector3 = Vector3.ONE * scale_factor
	var label_visible: bool = scale_factor > 0.001 and alpha_factor > 0.001
	if _race_label.scale != label_scale:
		_race_label.scale = label_scale
	if _race_label.visible != label_visible:
		_race_label.visible = label_visible
	_race_label.set_opacity(alpha_factor)


func _format_time_value(seconds_value: float) -> String:
	var elapsed: float = max(seconds_value, 0.0)
	var total_seconds: int = int(elapsed)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	var hundredths: int = int((elapsed - total_seconds) * 100.0) % 100
	return "%02d:%02d:%02d" % [minutes, seconds, hundredths]


func _get_level_key() -> String:
	var level_id: StringName = &""
	var scene_path: String = ""
	var level_manager = _get_level_manager()
	if level_manager != null:
		if level_manager.has_method("get_current_level_id"):
			var v = level_manager.call("get_current_level_id")
			if v is StringName:
				level_id = v
			elif v is String:
				level_id = StringName(v)
		if level_manager.has_method("get_current_level_scene_path"):
			scene_path = String(level_manager.call("get_current_level_scene_path"))
	if scene_path == "" and get_tree() != null and get_tree().current_scene != null:
		scene_path = String(get_tree().current_scene.scene_file_path)
	return HighScoreManager.get_level_key(level_id, scene_path)


func _is_online() -> bool:
	return multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _is_player_ui_blocked(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_ui_input_blocked"):
		var v = player.call("is_ui_input_blocked")
		if v is bool and bool(v):
			return true
	return false


func _show_interact_prompt() -> void:
	if _candidate_player == null or not is_instance_valid(_candidate_player):
		return
	var prompt_text: String = _get_interact_prompt_text()
	if _candidate_player.has_method("show_prompt"):
		_candidate_player.call("show_prompt", prompt_text, interact_prompt_duration)
	elif _candidate_player.has_method("show_chat_bubble"):
		_candidate_player.call("show_chat_bubble", prompt_text)
	_interact_prompt_visible = true


func _get_interact_prompt_text() -> String:
	var race_type_name: String = get_race_type_name()
	var prompt_template: String = interact_prompt_text.strip_edges()
	if prompt_template == "" or prompt_template == "Press INTERACT to start race!":
		return "Press INTERACT to start %s!" % race_type_name
	if prompt_template.contains("{race_type}"):
		return prompt_template.replace("{race_type}", race_type_name)
	if prompt_template.to_lower().contains(race_type_name.to_lower()):
		return prompt_template
	return "%s\n%s" % [prompt_template, race_type_name]


func _hide_interact_prompt() -> void:
	_interact_prompt_visible = false
	if _candidate_player == null or not is_instance_valid(_candidate_player):
		return
	if _candidate_player.has_method("clear_prompt"):
		_candidate_player.call("clear_prompt")

## Allow the player script to request the race menu directly.
## This is a fallback for online sessions where Area3D input polling can be skipped.
func try_open_race_settings_menu_from_player(player: Node) -> bool:
	_cleanup_stale_settings_menu()
	if player == null or not is_instance_valid(player):
		return false
	if not active or _sequence_running:
		return false
	if one_shot and _has_fired:
		return false
	if _settings_menu != null and is_instance_valid(_settings_menu):
		return true
	if not _is_valid_candidate_player(player):
		return false
	if _is_player_in_race(player):
		return false
	if _is_player_ui_blocked(player):
		return false
	
	# Attempt to use overlaps first for accuracy.
	var overlapping: bool = overlaps_body(player)
	
	# Fallback: check distance if overlap check fails (sometimes occurs during network frames).
	if not overlapping and player is Node3D:
		var dist_sq: float = global_position.distance_squared_to(player.global_position)
		if dist_sq < 25.0: # 5 unit radius fallback
			overlapping = true
			
	if not overlapping:
		return false

	var wants_interact: bool = (_is_online() and online_requires_interact) or ((not _is_online()) and offline_requires_interact)
	if _is_online():
		var session = _get_network_session()
		if session != null and session.has_method("is_race_busy"):
			var busy_val = session.call("is_race_busy")
			var busy: bool = false
			if busy_val is bool:
				busy = bool(busy_val)
			if busy:
				return false

	_candidate_player = player
	if wants_interact:
		_hide_interact_prompt()
		_interact_prompt_visible = false
	call_deferred("_open_race_settings_menu", player)
	return true


func _open_race_settings_menu(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	_cleanup_stale_settings_menu()
	_resolve_default_scenes()
	if _sequence_running or _settings_menu != null:
		return
	if race_settings_menu_scene == null:
		_hide_interact_prompt()
		_interact_prompt_visible = false
		_start_race_without_menu(player)
		return
	if _is_player_ui_blocked(player):
		return

	_settings_menu = race_settings_menu_scene.instantiate()
	_settings_menu.add_to_group(&"LevelTransient")
	_settings_menu_player = player

	_hide_interact_prompt()
	_interact_prompt_visible = false
	_freeze_player_for_menu(player)

	var parent_node := _get_menu_parent()
	if parent_node != null:
		parent_node.add_child(_settings_menu)
	else:
		add_child(_settings_menu)

	var settings = _get_settings_manager()
	var ghost_prefs := _get_saved_ghost_preferences()
	if settings != null and _settings_menu.has_method("set_values"):
		var dnf_val : float = settings.get("race_dnf_timer_sec")
		var join_val : float = settings.get("race_join_timer_sec")
		var combo_val: bool = settings.get("combo_system_enabled")
		var dnf_f: float = online_dnf_countdown_duration
		var join_f: float = 30.0
		var combo_f: bool = true
		if dnf_val is float:
			dnf_f = float(dnf_val)
		if join_val is float:
			join_f = float(join_val)
		if combo_val is bool:
			combo_f = bool(combo_val)
		_settings_menu.call("set_values", dnf_f, join_f, bool(ghost_prefs.get("race_ghost_enabled", false)), bool(ghost_prefs.get("record_ghost_enabled", false)), _validate_saved_ghost_path(String(ghost_prefs.get("selected_ghost_path", ""))), combo_f, int(ghost_prefs.get("recording_tick_rate", GhostDataManager.DEFAULT_TICK_RATE)), int(ghost_prefs.get("playback_tick_rate", GhostDataManager.DEFAULT_PLAYBACK_TICK_RATE)), bool(ghost_prefs.get("multiple_ghosts_enabled", false)), int(ghost_prefs.get("ghost_count", DEFAULT_RACE_GHOST_COUNT)))
	if _settings_menu != null and _settings_menu.has_method("configure_ghosts"):
		var available_ghosts: Array = []
		var best_ghost_path := ""
		var selected_ghost_path := _validate_saved_ghost_path(String(ghost_prefs.get("selected_ghost_path", "")))
		var ghosts_allowed := _can_use_ghost_features()
		if ghosts_allowed:
			available_ghosts = GhostDataManager.list_ghosts_for_race(_get_display_level_name(), _get_level_key(), _get_race_id_value(), get_race_type_name())
			best_ghost_path = GhostDataManager.get_best_ghost_path(_get_display_level_name(), _get_level_key(), _get_race_id_value(), get_race_type_name())
		_settings_menu.call("configure_ghosts", _get_display_level_name(), ghosts_allowed, _is_online(), available_ghosts, selected_ghost_path, best_ghost_path, _get_race_id_value(), GhostDataManager.get_race_id_rules_text())
	if not _is_online() and not GhostDataManager.is_valid_race_id(_get_race_id_value()) and player.has_method("show_prompt"):
		player.call("show_prompt", GhostDataManager.get_race_id_rules_text(), 4.0)

	if _settings_menu.has_signal("start_requested"):
		_settings_menu.connect("start_requested", Callable(self, "_on_race_settings_start"))
	if _settings_menu.has_signal("canceled"):
		_settings_menu.connect("canceled", Callable(self, "_on_race_settings_cancel"))


func _start_race_without_menu(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var settings = _get_settings_manager()
	var ghost_prefs := _get_saved_ghost_preferences()
	var dnf_val: float = online_dnf_countdown_duration
	var join_val: float = 30.0
	if settings != null and settings.has_method("get"):
		var dnf_raw = settings.get("race_dnf_timer_sec")
		var join_raw = settings.get("race_join_timer_sec")
		if dnf_raw is float:
			dnf_val = float(dnf_raw)
		elif dnf_raw is int:
			dnf_val = float(dnf_raw)
		if join_raw is float:
			join_val = float(join_raw)
		elif join_raw is int:
			join_val = float(join_raw)
	_configure_pending_ghost_settings(bool(ghost_prefs.get("race_ghost_enabled", false)), bool(ghost_prefs.get("record_ghost_enabled", false)), String(ghost_prefs.get("selected_ghost_path", "")), bool(ghost_prefs.get("multiple_ghosts_enabled", false)), int(ghost_prefs.get("ghost_count", DEFAULT_RACE_GHOST_COUNT)))
	_apply_race_settings(dnf_val, join_val)
	_has_fired = true
	if _is_online():
		_pending_race_ghost_enabled = false
		_pending_multiple_ghosts_enabled = false
		_pending_record_ghost_enabled = false
		_pending_selected_ghost_path = ""
		_request_online_race_start(player, join_val, dnf_val)
	else:
		start_race_for_player(player, false)


func _on_race_settings_start(dnf_seconds: float, join_seconds: float, race_ghost_enabled: bool, record_ghost_enabled: bool, selected_ghost_path: String, multiple_ghosts_enabled: bool, ghost_count: int, combo_system_enabled: bool) -> void:
	var player = _settings_menu_player
	_close_race_settings_menu(false)
	if player == null or not is_instance_valid(player):
		return
	_configure_pending_ghost_settings(race_ghost_enabled, record_ghost_enabled, selected_ghost_path, multiple_ghosts_enabled, ghost_count)
	_apply_race_settings(dnf_seconds, join_seconds, combo_system_enabled)
	_has_fired = true
	if _is_online():
		_pending_race_ghost_enabled = false
		_pending_multiple_ghosts_enabled = false
		_pending_record_ghost_enabled = false
		_pending_selected_ghost_path = ""
		_request_online_race_start(player, join_seconds, dnf_seconds)
	else:
		start_race_for_player(player, false)


func _on_race_settings_cancel() -> void:
	_close_race_settings_menu(true)


func _close_race_settings_menu(restore_prompt: bool) -> void:
	if _settings_menu != null and is_instance_valid(_settings_menu):
		_settings_menu.queue_free()
	_settings_menu = null

	var player = _settings_menu_player
	_settings_menu_player = null
	_unfreeze_player_for_menu(player)

	if restore_prompt and _candidate_player != null and not _is_player_ui_blocked(_candidate_player):
		_show_interact_prompt()


func _freeze_player_for_menu(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("stop_all_momentum_and_special_movement"):
		player.call("stop_all_momentum_and_special_movement")
	if player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unfreeze_player_for_menu(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _apply_race_settings(dnf_seconds: float, join_seconds: float, combo_system_enabled: bool = true) -> void:
	online_dnf_countdown_duration = clamp(dnf_seconds, 30.0, 300.0)
	var settings = _get_settings_manager()
	if settings != null and settings.has_method("set"):
		settings.set("race_dnf_timer_sec", dnf_seconds)
		settings.set("race_join_timer_sec", join_seconds)
		settings.set("combo_system_enabled", combo_system_enabled)

	if _active_player != null and is_instance_valid(_active_player):
		var ts = _active_player.get("_trick_system")
		if ts != null and is_instance_valid(ts):
			ts.combo_system_enabled = combo_system_enabled

	if settings != null and settings.has_method("save_now"):
		settings.call("save_now")


func _get_settings_manager() -> Node:
	var root := get_tree().root
	if root == null:
		return null
	return root.get_node_or_null("SettingsManager")


func _get_menu_parent() -> Node:
	if get_tree() != null:
		# Priority 1: Current scene root
		if get_tree().current_scene != null:
			return get_tree().current_scene
		# Priority 2: Viewport root
		return get_tree().root
	return null


func _request_online_race_start(player: Node, queue_duration: float, dnf_duration: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_clear_ghost_runtime()
	var session = _get_network_session()
	if session == null:
		return
	if session.has_method("is_race_busy"):
		var busy = session.call("is_race_busy")
		if busy is bool and bool(busy):
			return
	_has_fired = true
	var level_scene_path: String = ""
	var race_start_path: String = ""
	var level_manager = _get_level_manager()
	if level_manager != null:
		if level_manager.has_method("get_current_level_scene_path"):
			level_scene_path = String(level_manager.call("get_current_level_scene_path"))
		if level_manager.has_method("get_path_in_current_level"):
			var p = level_manager.call("get_path_in_current_level", self)
			if p is NodePath:
				race_start_path = String(p)
	if level_scene_path == "" or race_start_path == "":
		if get_tree() != null and get_tree().current_scene != null:
			level_scene_path = String(get_tree().current_scene.scene_file_path)
			race_start_path = String(get_tree().current_scene.get_path_to(self))
	if level_scene_path == "" or race_start_path == "":
		return
	if session.has_method("request_start_race"):
		session.call("request_start_race", level_scene_path, race_start_path, queue_duration, dnf_duration)


func _get_network_session() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("NetworkSession")
	if list != null and list.size() > 0:
		return list[0]
	var cs = get_tree().current_scene
	if cs == null:
		return null
	return cs.get_node_or_null("NetworkSession")


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)


func start_race_for_player_networked(player: Node, already_faded_out: bool) -> void:
	# Same as start_race_for_player, but waits for NetworkSession to trigger GO/unlock.
	if _sequence_running:
		return
	if player == null or not is_instance_valid(player):
		return
	_clear_ghost_runtime()
	_sequence_running = true
	_network_countdown_released = false
	_waiting_for_network_go = true
	_claim_active_player(player)
	var my_cancel_token: int = _cancel_token
	_go_music_started = false

	# Detach from any spline/rail constraints before starting race.
	if player.has_method("cancel_spline_spring"):
		player.call("cancel_spline_spring")
	if player.has_method("cancel_rail_grind"):
		player.call("cancel_rail_grind")

	if player.has_method("reset_gameplay_run_state"):
		player.call("reset_gameplay_run_state", true)
	else:
		if player.has_method("reset_rings"):
			player.call("reset_rings")
		if player.has_method("reset_score"):
			player.call("reset_score")

	DeathPlane.cancel_death_sequence()
	if player.has_method("set_death_state"):
		player.call("set_death_state", false)

	_prepare_race_object_layouts()
	_reset_objects_for_race_restart()
	_apply_race_object_blacklists()
	_reset_collection_progress()
	_set_collection_items_active_for_race(false)
	_reset_goals_for_race()
	_set_player_race_state(player, true, false, false)

	# Ensure the pause menu is closed when the race sequence starts.
	var pause_menus = get_tree().get_nodes_in_group("PauseMenu")
	for pm in pause_menus:
		if pm.has_method("_resume_game"):
			pm.call("_resume_game")

	var hud = _resolve_hud(player)
	_active_hud = hud
	if hud != null:
		if hud.has_method("set_timer_running"):
			hud.call("set_timer_running", false)
		if reset_hud_timer_on_start and hud.has_method("set_elapsed_time"):
			hud.call("set_elapsed_time", 0.0)

	if not already_faded_out:
		_fade_out_music()

	var ui = _spawn_ui()
	_active_ui = ui
	if ui != null:
		ui.call("show_level_name", level_name)
		ui.call("show_countdown_number", "")
		_play_sfx(sfx_titlecard)
		_queue_go_music_after_titlecard(my_cancel_token)

	var fader = _get_or_create_fader()
	var prev_fade_color: Color = Color.BLACK
	if fader != null and fader.has_method("get"):
		var c = fader.get("fade_color")
		if c is Color:
			prev_fade_color = c
	if fader != null and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", fade_color)

	if not already_faded_out and fader != null:
		_notify_camera_teleport(player, fade_out_duration + fade_hold_duration + fade_in_duration + float(_get_countdown_duration()))
		await fader.call("fade_out", fade_out_duration)
		if get_tree() != null and fade_hold_duration > 0.0:
			await get_tree().create_timer(fade_hold_duration).timeout
		if my_cancel_token != _cancel_token:
			return

	_teleport_player_to_start(player)
	_notify_camera_teleport(player, fade_in_duration + float(_get_countdown_duration()))

	if fader != null:
		await fader.call("fade_in", fade_in_duration)
		if my_cancel_token != _cancel_token:
			return
	var lineup_session: Node = _get_network_session()
	if lineup_session and lineup_session.has_method("notify_race_lineup_ready"):
		lineup_session.call("notify_race_lineup_ready")
	while not _network_countdown_released:
		await get_tree().process_frame
		if my_cancel_token != _cancel_token:
			return
	if player.has_method("play_voice_event"):
		player.call("play_voice_event", &"race_start")

	# Brief pause before countdown begins.
	if countdown_start_delay > 0.0 and get_tree() != null:
		await get_tree().create_timer(countdown_start_delay).timeout
		if my_cancel_token != _cancel_token:
			return

	var countdown_completed: bool = await _run_countdown(player, ui, my_cancel_token)
	if not countdown_completed:
		if my_cancel_token == _cancel_token:
			cancel_for_player(player)
		return

	# Inform server we are ready to start on GO.
	var session = _get_network_session()
	if session != null and session.has_method("notify_race_ready"):
		session.call("notify_race_ready")

	# Keep the UI visible until GO arrives.
	if ui != null and is_instance_valid(ui):
		ui.call("hide_countdown")

	# Restore fader color (keep white fade for other systems).
	if fader != null and is_instance_valid(fader) and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", prev_fade_color)


func trigger_network_go() -> void:
	if not _waiting_for_network_go:
		return
	_waiting_for_network_go = false

	var player = _active_player
	var hud = _active_hud
	var ui = _active_ui
	var go_token: int = _cancel_token
	_set_goals_active_for_race(true)
	_set_collection_items_active_for_race(true)

	if player != null and is_instance_valid(player):
		_set_player_race_state(player, false, true, false)
		# Keep cursor locked for gameplay.
		_lock_cursor(player)

	if hud != null and is_instance_valid(hud):
		if reset_hud_timer_on_start and hud.has_method("set_elapsed_time"):
			hud.call("set_elapsed_time", 0.0)
		if hud.has_method("set_timer_running"):
			hud.call("set_timer_running", true)

	_start_go_music_if_needed()

	if ui != null and is_instance_valid(ui):
		ui.call("hide_level_name")
		ui.call("hide_countdown")
		_play_sfx(_get_go_sound())
		await ui.call("show_go", go_duration)
		if go_token != _cancel_token:
			return
		if is_instance_valid(ui):
			ui.queue_free()
	_active_ui = null
	_sequence_running = false
	if not one_shot:
		_has_fired = false


func start_race_for_player(player: Node, already_faded_out: bool) -> void:
	if _sequence_running:
		return
	if player == null or not is_instance_valid(player):
		return
	_sequence_running = true
	_claim_active_player(player)
	var my_cancel_token: int = _cancel_token
	_go_music_started = false
	_prepare_ghost_runtime(player)

	# Ensure gameplay cursor lock during race countdown/start.
	_lock_cursor(player)

	# Detach from any spline/rail constraints before starting race.
	if player.has_method("cancel_spline_spring"):
		player.call("cancel_spline_spring")
	if player.has_method("cancel_rail_grind"):
		player.call("cancel_rail_grind")

	if player.has_method("reset_gameplay_run_state"):
		player.call("reset_gameplay_run_state", true)
	else:
		if player.has_method("reset_rings"):
			player.call("reset_rings")
		if player.has_method("reset_score"):
			player.call("reset_score")

	DeathPlane.cancel_death_sequence()
	if player.has_method("set_death_state"):
		player.call("set_death_state", false)

	_prepare_race_object_layouts()
	_reset_objects_for_race_restart()
	_apply_race_object_blacklists()
	_reset_collection_progress()
	_set_collection_items_active_for_race(false)
	_reset_goals_for_race()
	_set_player_race_state(player, true, false, false)

	# Ensure the pause menu is closed when the race sequence starts.
	var pause_menus = get_tree().get_nodes_in_group("PauseMenu")
	for pm in pause_menus:
		if pm.has_method("_resume_game"):
			pm.call("_resume_game")

	var hud = _resolve_hud(player)
	if hud != null:
		if hud.has_method("set_timer_running"):
			hud.call("set_timer_running", false)
		if reset_hud_timer_on_start and hud.has_method("set_elapsed_time"):
			hud.call("set_elapsed_time", 0.0)

	if not already_faded_out:
		_fade_out_music()

	var ui = _spawn_ui()
	if ui != null:
		ui.call("show_level_name", level_name)
		ui.call("show_countdown_number", "")
		_play_sfx(sfx_titlecard)
		_queue_go_music_after_titlecard(my_cancel_token)

	var fader = _get_or_create_fader()
	var prev_fade_color: Color = Color.BLACK
	if fader != null and fader.has_method("get"):
		var c = fader.get("fade_color")
		if c is Color:
			prev_fade_color = c
	if fader != null and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", fade_color)

	if not already_faded_out and fader != null:
		_notify_camera_teleport(player, fade_out_duration + fade_hold_duration + fade_in_duration + float(_get_countdown_duration()) + go_duration)
		await fader.call("fade_out", fade_out_duration)
		if get_tree() != null and fade_hold_duration > 0.0:
			await get_tree().create_timer(fade_hold_duration).timeout
		if my_cancel_token != _cancel_token:
			return

	_teleport_player_to_start(player)
	_notify_camera_teleport(player, fade_in_duration + float(_get_countdown_duration()) + go_duration)

	if fader != null:
		await fader.call("fade_in", fade_in_duration)
		if my_cancel_token != _cancel_token:
			return
	if player.has_method("play_voice_event"):
		player.call("play_voice_event", &"race_start")

	# Brief pause before countdown begins.
	if countdown_start_delay > 0.0 and get_tree() != null:
		await get_tree().create_timer(countdown_start_delay).timeout
		if my_cancel_token != _cancel_token:
			return

	var countdown_completed: bool = await _run_countdown(player, ui, my_cancel_token)
	if not countdown_completed:
		if my_cancel_token == _cancel_token:
			cancel_for_player(player)
		return
	_set_goals_active_for_race(true)
	_set_collection_items_active_for_race(true)
	_set_player_race_state(player, false, true, false)
	_start_ghost_runtime()
	_start_go_music_if_needed()

	if hud != null and is_instance_valid(hud):
		if reset_hud_timer_on_start and hud.has_method("set_elapsed_time"):
			hud.call("set_elapsed_time", 0.0)
		if hud.has_method("set_timer_running"):
			hud.call("set_timer_running", true)

	if ui != null and is_instance_valid(ui):
		ui.call("hide_level_name")
		ui.call("hide_countdown")
		_play_sfx(_get_go_sound())
		await ui.call("show_go", go_duration)
		ui.queue_free()

	# Restore fader color for other systems.
	if fader != null and is_instance_valid(fader) and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", prev_fade_color)

	_sequence_running = false
	if not one_shot:
		_has_fired = false


func _get_countdown_duration() -> int:
	return 2 if use_ready_set_go_countdown else max(countdown_seconds, 0)


func _get_go_sound() -> AudioStream:
	return sfx_ready_set_go if use_ready_set_go_countdown else sfx_go


func _run_countdown(player: Node, ui: Node, cancel_token: int) -> bool:
	if use_ready_set_go_countdown:
		var labels: Array[String] = ["READY!", "SET!"]
		var sounds: Array[AudioStream] = [sfx_ready, sfx_set]
		for index: int in range(labels.size()):
			if ui != null and is_instance_valid(ui):
				ui.call("show_countdown_number", labels[index])
			_play_sfx(sounds[index])
			var countdown_number: int = labels.size() - index
			if not await _wait_countdown_tick(player, countdown_number, cancel_token):
				return false
		return true

	var seconds: int = max(countdown_seconds, 0)
	for countdown_number: int in range(seconds, 0, -1):
		if ui != null and is_instance_valid(ui):
			ui.call("show_countdown_number", str(countdown_number))
		_play_sfx(sfx_countdown)
		if not await _wait_countdown_tick(player, countdown_number, cancel_token):
			return false
	return true


func _wait_countdown_tick(player: Node, countdown_number: int, cancel_token: int) -> bool:
	if get_tree() == null:
		return cancel_token == _cancel_token
	var buffer_time: float = 0.0
	if countdown_number == 1 and player != null and is_instance_valid(player):
		if player.has_method("get_spindash_countdown_release_buffer_time"):
			buffer_time = clamp(float(player.call("get_spindash_countdown_release_buffer_time")), 0.0, 1.0)
	var leading_time: float = 1.0 - buffer_time
	if leading_time > 0.0:
		await get_tree().create_timer(leading_time).timeout
		if cancel_token != _cancel_token:
			return false
	if buffer_time > 0.0:
		if player.has_method("set_spindash_countdown_release_buffer_open"):
			player.call("set_spindash_countdown_release_buffer_open", true)
		await get_tree().create_timer(buffer_time).timeout
	return cancel_token == _cancel_token


func is_active_for_player(player: Node) -> bool:
	return player != null and is_instance_valid(player) and _active_player == player


func _check_ring_race_completion() -> void:
	if not is_ring_race():
		return
	var player: Node = _active_player
	if player == null or not is_instance_valid(player) or not _is_player_collection_active(player):
		return
	var player_id: int = player.get_instance_id()
	if bool(_ring_finish_requested.get(player_id, false)):
		return
	var rings_value: Variant = player.get("rings")
	if not (rings_value is int) or int(rings_value) < max(ring_required_count, 1):
		return
	_ring_finish_requested[player_id] = true
	call_deferred("_finish_ring_race", player)


func _finish_ring_race(player: Node) -> void:
	if player == null or not is_instance_valid(player) or not _is_player_collection_active(player):
		return
	var goal: Node = _resolve_ring_finish_goal()
	if goal == null:
		push_warning("RaceStart: Ring Race requires a linked RaceGoal.")
		return
	ring_race_completed.emit(player)
	if goal.has_method("finish_for_player"):
		goal.call("finish_for_player", player)


func _claim_active_player(player: Node) -> void:
	if get_tree() != null:
		for race_start: Node in get_tree().get_nodes_in_group("RaceStart"):
			if race_start == self or not is_instance_valid(race_start):
				continue
			if race_start.has_method("_release_active_player"):
				race_start.call("_release_active_player", player)
	_active_player = player


func _release_active_player(player: Node) -> void:
	if _active_player == player:
		_active_player = null


func _lock_cursor(player: Node) -> void:
	if player == null or not is_instance_valid(player) or not player.has_method("set"):
		return
	player.set("lock_cursor_to_game", true)
	if player.has_method("_update_mouse_lock"):
		player.call("_update_mouse_lock")


func _get_music_controller():
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("MusicControllers")
	if list != null and list.size() > 0 and list[0] is MusicController:
		return list[0]
	var cs = get_tree().current_scene
	if cs != null:
		var mc = cs.get_node_or_null("MusicController")
		if mc is MusicController:
			return mc
	return null


func _fade_out_music() -> void:
	if get_tree() == null:
		return
	var controllers := get_tree().get_nodes_in_group("MusicControllers")
	if controllers != null and not controllers.is_empty():
		for node in controllers:
			if node is MusicController:
				(node as MusicController).stop_music(music_fade_out_time)
		return
	var mc = _get_music_controller()
	if mc == null:
		return
	mc.stop_music(music_fade_out_time)


func _play_go_music() -> bool:
	if go_music_stream == null:
		return false
	var mc = _get_music_controller()
	if mc == null:
		return false
	mc.play_music(go_music_stream, go_music_fade_in, go_music_fade_out, true)
	return true


func _is_player_in_race(player: Node) -> bool:
	# Prevent re-triggering the race start while a race is active.
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("get"):
		return false
	var in_countdown = player.get("race_in_countdown")
	var active = player.get("race_active")
	var finished = player.get("race_finished")
	var race_in_countdown: bool = in_countdown is bool and bool(in_countdown)
	var race_active: bool = active is bool and bool(active)
	var race_finished: bool = finished is bool and bool(finished)
	if (race_in_countdown or race_active) and not race_finished:
		return true
	return false


func _start_go_music_if_needed() -> void:
	# Avoid restarting the GO track when an earlier trigger already started it.
	if _go_music_started:
		return
	if _play_go_music():
		_go_music_started = true


func _get_titlecard_duration() -> float:
	if sfx_titlecard == null:
		return 0.0
	var length: float = sfx_titlecard.get_length()
	return max(length, 0.0)


func _queue_go_music_after_titlecard(cancel_token: int) -> void:
	# Schedule the GO music based on time after the title card SFX starts.
	if go_music_play_on_go:
		return
	if get_tree() == null:
		return
	var offset: float = clamp(go_music_pre_start_offset, 0.0, _MUSIC_TITLECARD_OFFSET_MAX)
	var titlecard_duration: float = _get_titlecard_duration()
	if offset <= 0.0 and titlecard_duration <= 0.0:
		return
	var start_delay: float = max(titlecard_duration + offset, 0.0)
	if start_delay <= 0.0:
		_start_go_music_if_needed()
		return
	_start_go_music_after_delay(start_delay, cancel_token)


func _start_go_music_after_delay(delay_seconds: float, cancel_token: int) -> void:
	if get_tree() == null:
		return
	var my_cancel_token: int = cancel_token
	await get_tree().create_timer(delay_seconds).timeout
	if my_cancel_token != _cancel_token:
		return
	if not _sequence_running:
		return
	_start_go_music_if_needed()


func _get_sfx_player() -> AudioStreamPlayer:
	if _sfx_player != null and is_instance_valid(_sfx_player):
		return _sfx_player
	var p := AudioStreamPlayer.new()
	p.bus = sfx_bus
	add_child(p)
	_sfx_player = p
	return _sfx_player


func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var p = _get_sfx_player()
	if p == null:
		return
	p.stream = stream
	p.play()


func _teleport_player_to_start(player: Node) -> void:
	var t: Transform3D = _get_start_transform_for_player(player)
	if player.has_method("_apply_respawn_transform"):
		player.call("_apply_respawn_transform", t, false)
		# Race start should consider you grounded.
		if player.has_method("set"):
			player.set("attached", true)
			player.set("_prev_attached", true)
		_set_race_checkpoint(player, t)
		_align_camera_to_start(player)
		if player.has_method("_network_publish_teleport_state"):
			player.call("_network_publish_teleport_state")
		return

	if player is Node3D:
		(player as Node3D).global_transform = t
		if player.has_method("set"):
			player.set("velocity", Vector3.ZERO)
			player.set("attached", true)
			player.set("_prev_attached", true)
		_set_race_checkpoint(player, t)
		_align_camera_to_start(player)
		if player.has_method("_network_publish_teleport_state"):
			player.call("_network_publish_teleport_state")


func _align_camera_to_start(player: Node) -> void:
	var direction_node: Node3D = _resolve_start_facing_marker(camera_facing_direction_path)
	if not (direction_node is Node3D):
		return
	var direction_transform: Transform3D = (direction_node as Node3D).global_transform
	var forward: Vector3 = -direction_transform.basis.z
	var up: Vector3 = direction_transform.basis.y
	if player.has_method("get_gravity_up"):
		up = player.call("get_gravity_up")
	else:
		up = _get_start_transform_for_player(player).basis.y
	if forward.length() < 0.001:
		return
	if up.length() < 0.001:
		up = Vector3.UP
	var rig: Node = _resolve_camera_rig_for_player(player)
	if rig == null:
		return
	if rig.has_method("align_to_facing_direction"):
		rig.call("align_to_facing_direction", forward.normalized(), up.normalized())
	elif rig.has_method("align_to_direction"):
		rig.call("align_to_direction", forward.normalized(), up.normalized())
	elif rig.has_method("set_yaw_from_forward"):
		rig.call("set_yaw_from_forward", forward.normalized(), up.normalized())
	if rig.has_method("notify_teleport"):
		rig.call("notify_teleport")


func _set_race_checkpoint(player: Node, xform: Transform3D) -> void:
	# Race start acts as a checkpoint so deaths/respawns return you to the start line.
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("activate_checkpoint_from") and not player.has_method("activate_checkpoint"):
		return
	var dir: Vector3 = (-xform.basis.z).normalized()
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	if player.has_method("activate_checkpoint_from"):
		player.call("activate_checkpoint_from", self, xform, 0.0, dir)
	else:
		player.call("activate_checkpoint", xform, 0.0, dir)


func _reset_goals_for_race() -> void:
	if get_tree() == null:
		return
	var goals = get_tree().get_nodes_in_group("RaceGoal")
	if goals == null:
		return
	for goal in goals:
		if goal != null and is_instance_valid(goal) and _is_goal_for_this_race(goal) and goal.has_method("reset_for_race_start"):
			goal.call("reset_for_race_start")


func _reset_objects_for_race_restart() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	_reset_objects_for_race_restart_recursive(get_tree().current_scene)


func _reset_objects_for_race_restart_recursive(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node != self and node.has_method("reset_for_race_restart"):
		node.call("reset_for_race_restart")
	for child in node.get_children():
		_reset_objects_for_race_restart_recursive(child)


func _set_goals_active_for_race(is_enabled: bool) -> void:
	if get_tree() == null:
		return
	var goals = get_tree().get_nodes_in_group("RaceGoal")
	if goals == null:
		return
	for goal in goals:
		if goal != null and is_instance_valid(goal) and _is_goal_for_this_race(goal) and goal.has_method("set_goal_active_for_race"):
			goal.call("set_goal_active_for_race", is_enabled)


func _is_goal_for_this_race(goal: Node) -> bool:
	if goal == null or not is_instance_valid(goal):
		return false
	if goal.has_method("is_for_race_start"):
		var matches = goal.call("is_for_race_start", self)
		if matches is bool:
			return bool(matches)
	return false


func _get_start_transform_for_player(_player: Node) -> Transform3D:
	var start_node = get_node_or_null(starting_line_path)
	if start_node == null and get_tree() != null and get_tree().current_scene != null:
		start_node = get_tree().current_scene.get_node_or_null(starting_line_path)
	if start_node is Node3D:
		var base_t: Transform3D = (start_node as Node3D).global_transform
		if use_child_slots:
			for c in (start_node as Node3D).get_children():
				if c is Node3D:
					base_t = (c as Node3D).global_transform
					break
		base_t.origin += starting_line_offset
		return _apply_start_facing(base_t)
	return _apply_start_facing(global_transform)


func _resolve_start_facing_marker(path: NodePath) -> Node3D:
	if path.is_empty():
		return null
	var marker: Node3D = get_node_or_null(path) as Node3D
	if not marker and get_tree() and get_tree().current_scene:
		marker = get_tree().current_scene.get_node_or_null(path) as Node3D
	return marker


func _apply_start_facing(start_transform: Transform3D) -> Transform3D:
	var marker: Node3D = _resolve_start_facing_marker(player_facing_direction_path)
	if not marker:
		marker = _resolve_start_facing_marker(camera_facing_direction_path)
	if not marker:
		return start_transform
	var up: Vector3 = start_transform.basis.y.normalized()
	var forward: Vector3 = (-marker.global_basis.z).slide(up)
	if up.length_squared() < 0.001 or forward.length_squared() < 0.001:
		return start_transform
	forward = forward.normalized()
	var right: Vector3 = forward.cross(up).normalized()
	start_transform.basis = Basis(right, up, -forward) * Basis.from_scale(start_transform.basis.get_scale())
	return start_transform


func _resolve_hud(player: Node) -> Node:
	if player != null and player.has_method("_get_hud_node"):
		var h = player.call("_get_hud_node")
		if h != null and is_instance_valid(h):
			return h
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("HUD")
	if list != null and list.size() > 0:
		return list[0]
	return null


func _spawn_ui() -> Node:
	if race_ui_scene == null:
		_resolve_default_scenes()
	if race_ui_scene == null:
		return null
	var ui = race_ui_scene.instantiate()
	if ui == null:
		return null
	ui.add_to_group("RaceUI")
	var vp = get_viewport()
	if vp != null:
		vp.add_child(ui)
	elif get_tree() != null and get_tree().current_scene != null:
		get_tree().current_scene.add_child(ui)
	else:
		add_child(ui)
	return ui


func _get_or_create_fader() -> Node:
	if get_tree() == null:
		return null
	var existing = get_tree().get_nodes_in_group("ScreenFader")
	if existing != null and existing.size() > 0:
		return existing[0]

	var fader = ScreenFader.new()
	fader.add_to_group("ScreenFader")
	var vp = get_viewport()
	if vp != null:
		vp.add_child(fader)
	elif get_tree().current_scene != null:
		get_tree().current_scene.add_child(fader)
	else:
		add_child(fader)
	return fader


func _notify_camera_teleport(player: Node, duration: float) -> void:
	if player == null:
		return
	var rig: Node = _resolve_camera_rig_for_player(player)
	if rig != null and rig.has_method("notify_teleport"):
		rig.call("notify_teleport", duration)


func _resolve_camera_rig_for_player(player: Node) -> Node:
	var rig: Node = null
	if player.has_method("get"):
		var rig_value: Variant = player.get("camera_rig")
		if rig_value is Node:
			rig = rig_value as Node
	if rig == null and player.has_method("get"):
		var cam = player.get("camera")
		if cam != null and cam is Node:
			rig = (cam as Node).get_parent()
	if rig == null and get_tree() != null:
		var rigs = get_tree().get_nodes_in_group("CameraRig")
		if rigs != null and rigs.size() > 0 and rigs[0] is Node:
			rig = rigs[0] as Node
	return rig


func _set_player_race_state(player: Node, in_countdown: bool, race_active: bool, race_finished: bool) -> void:
	if player == null or not player.has_method("set"):
		return
	player.set("race_in_countdown", in_countdown)
	player.set("race_active", race_active)
	player.set("race_finished", race_finished)
	if (in_countdown or not race_active) and player.has_method("set_spindash_countdown_release_buffer_open"):
		player.call("set_spindash_countdown_release_buffer_open", false)
	if in_countdown and player.has_method("clear_gravity_state"):
		player.call("clear_gravity_state", &"race_cleanup", true)
	if in_countdown and player.has_method("clear_max_speed_overrides"):
		player.call("clear_max_speed_overrides")
	if in_countdown:
		if player.has_method("reset_race_debug_usage"):
			player.call("reset_race_debug_usage")
		else:
			player.set("race_debug_used", false)


func release_network_countdown() -> void:
	if _waiting_for_network_go:
		_network_countdown_released = true

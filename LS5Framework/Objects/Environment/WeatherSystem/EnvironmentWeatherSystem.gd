@tool
extends Node3D
class_name EnvironmentWeatherSystem

enum InitialTimeMode {
	FIXED,
	RANDOM,
}

const PERSISTENT_STATE_VERSION: int = 2
const WEATHER_STATE_PREFIX: String = "weather:"
const TIME_STATE_PREFIX: String = "time:"

signal weather_transition_started(preset_id: StringName, duration_seconds: float)
signal weather_changed(preset_id: StringName)
signal weather_extension_updated(preset: DynamicWeatherPreset, duration_seconds: float)

@export_group("Environment")
## Atmospheric profile applied to the contained day-night cycle.
@export var environment_profile: DayNightProfile
## Chooses a fixed or uniformly random initial game-clock hour when no persistent time exists.
@export_enum("Fixed", "Random") var initial_time_mode: int = InitialTimeMode.FIXED
## Initial local solar time used in Fixed mode and as the persistence fallback.
@export_range(0.0, 24.0, 0.001) var initial_time_of_day_hours: float = 9.0
## Fixed random seed for repeatable random starting times. Zero selects a random seed at startup.
@export var time_random_seed: int = 0
## Advances local solar time when authoritative. Disable for a static time of day.
@export var time_progression_enabled: bool = true
## Real-time minutes required for one complete in-game day.
@export_range(0.1, 1440.0, 0.1) var day_length_minutes: float = 24.0
## Gives the daylight and nighttime clock ranges different shares of the complete cycle duration.
@export var uneven_day_night_durations_enabled: bool = true
## Game-clock hour at which the slower daylight portion begins.
@export_range(0.0, 24.0, 0.01) var daylight_start_hour: float = 6.0
## Game-clock hour at which the faster nighttime portion begins.
@export_range(0.0, 24.0, 0.01) var daylight_end_hour: float = 18.0
## Fraction of the complete real-time cycle spent within the configured daylight clock range.
@export_range(0.05, 0.95, 0.01) var daylight_duration_ratio: float = 0.7

@export_group("Weather")
## Applies startup, dynamic, persistent, and synchronized weather presets. Disable to retain scene-assigned weather resources.
@export var use_weather_presets: bool = true
## Resource paths for every combined weather preset permitted by this level.
@export var weather_preset_paths: Array[String] = []
## Preset applied at startup while weather presets are enabled. Use "random" for weighted random selection.
@export var initial_weather_id: StringName = &"random"
## Selects and transitions between eligible weather presets while authoritative and presets are enabled.
@export var dynamic_weather_enabled: bool = true
## Enables the contained rain system. Disable for levels that never use precipitation.
@export var precipitation_enabled: bool = true
## Fixed random seed for repeatable weather sequences. Zero selects a random seed at startup.
@export var weather_random_seed: int = 0

@export_group("Weather Persistence")
## Preserves dynamic weather state while changing between participating levels.
@export var persistent_weather_enabled: bool = true
## Weather state channel used to isolate unrelated worlds or campaigns.
@export var weather_persistence_namespace: StringName = &"default"
## Carries procedural cloud position into the next participating level.
@export var persist_cloud_motion: bool = true

@export_group("Time Persistence")
## Preserves the game-clock hour independently from dynamic weather.
@export var persistent_time_enabled: bool = true
## Time state channel with an optional game-hour offset, such as "default+1h30m" or "default-45m".
@export var time_persistence_reference: String = "default"

@export_group("Persistence Updates")
## Seconds between updates to the cross-level state cache.
@export_range(0.1, 10.0, 0.1) var persistence_update_interval_seconds: float = 0.5

@export_group("Weather Intelligence")
## Preferred maximum severity difference between consecutive automatic weather states.
@export_range(0.0, 1.0, 0.01) var maximum_severity_step: float = 0.42
## Strength of the probability penalty applied as severity difference increases.
@export_range(0.0, 8.0, 0.01) var severity_continuity_exponent: float = 2.0
## Number of recently selected presets remembered by the automatic scheduler.
@export_range(0, 16, 1) var recent_weather_memory: int = 3
## Selection multiplier applied to presets still present in recent history.
@export_range(0.0, 1.0, 0.01) var recent_weather_weight_multiplier: float = 0.15

@export_group("Online Synchronization")
## Uses the server as authority for time progression and dynamic weather selection.
@export var network_sync_enabled: bool = true
## Seconds between lightweight authoritative time snapshots.
@export_range(0.1, 10.0, 0.05) var network_sync_interval_seconds: float = 1.0
## Speed at which clients converge on authoritative solar time.
@export_range(0.1, 30.0, 0.1) var network_time_interpolation_speed: float = 5.0
## Time error in hours that causes an immediate correction instead of interpolation.
@export_range(0.1, 12.0, 0.1) var network_time_snap_threshold_hours: float = 2.0

@export_group("Scene References")
## Contained DayNightCycle responsible for sky, fog, lighting, clouds, sun, and moon.
@export_node_path("DayNightCycle") var day_night_cycle_path: NodePath = NodePath("DayNightCycle")
## Contained RainSystem responsible for precipitation, collision, cover response, and weather audio.
@export_node_path("RainSystem") var rain_system_path: NodePath = NodePath("RainSystem")
## Optional weather nodes receiving transition_to_weather_preset(preset, duration) calls.
@export var additional_weather_system_paths: Array[NodePath] = []

var _day_night_cycle: DayNightCycle
var _rain_system: RainSystem
var weather_presets: Array[DynamicWeatherPreset] = []
var _preset_by_id: Dictionary = {}
var _resources_prepared: bool = false
var _level_preparation_ready: bool = false
var _network_level_key: String = ""
var _started_as_network_client: bool = false
var _missing_remote_preset_ids: Dictionary = {}
var _weather_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _current_preset: DynamicWeatherPreset
var _weather_duration_remaining: float = 0.0
var _weather_transition_remaining: float = 0.0
var _recent_weather_ids: Array[StringName] = []
var _network_sync_elapsed: float = 0.0
var _full_state_request_elapsed: float = 0.0
var _network_time_target_hours: float = 0.0
var _network_cycle_enabled: bool = false
var _network_day_length_minutes: float = 24.0
var _network_uneven_day_night_durations_enabled: bool = true
var _network_daylight_start_hour: float = 6.0
var _network_daylight_end_hour: float = 18.0
var _network_daylight_duration_ratio: float = 0.7
var _network_state_received: bool = false
var _state_sequence: int = 0
var _last_received_sequence: int = -1
var _persistence_elapsed: float = 0.0
## Session clock source retained across level changes.
var _clock_session: Node
var _clock_channel: String = ""
var _clock_offset: float = 0.0
var _clock_received: bool = false
var _clock_poll_elapsed: float = 2.0
var _clock_hour: float = 0.0
var _clock_settings: Dictionary = {}


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	var cycle_node: DayNightCycle = get_node_or_null(day_night_cycle_path) as DayNightCycle
	var rain_node: RainSystem = get_node_or_null(rain_system_path) as RainSystem
	if not cycle_node:
		warnings.append("Day Night Cycle Path must reference a DayNightCycle node.")
	if uneven_day_night_durations_enabled and is_equal_approx(
		wrapf(daylight_start_hour, 0.0, 24.0),
		wrapf(daylight_end_hour, 0.0, 24.0)
	):
		warnings.append("Daylight Start Hour and Daylight End Hour must differ while uneven durations are enabled.")
	if precipitation_enabled and not rain_node:
		warnings.append("Rain System Path must reference a RainSystem node while precipitation is enabled.")
	if use_weather_presets and weather_preset_paths.is_empty():
		warnings.append("At least one weather preset path is required while Use Weather Presets is enabled.")
	if use_weather_presets:
		for preset_path: String in weather_preset_paths:
			if preset_path.strip_edges() == "" or not ResourceLoader.exists(preset_path):
				warnings.append("Weather preset path does not exist: %s" % preset_path)
	var known_ids: Dictionary = {}
	var automatic_preset_count: int = 0
	if use_weather_presets:
		for preset: DynamicWeatherPreset in weather_presets:
			if not preset:
				warnings.append("Weather Presets contains an empty element.")
				continue
			var id_text: String = String(preset.preset_id)
			if id_text.is_empty():
				warnings.append("Every weather preset requires a non-empty Preset Id.")
			elif known_ids.has(id_text):
				warnings.append("Weather preset IDs must be unique: %s" % id_text)
			else:
				known_ids[id_text] = true
			if preset.automatic_selection_enabled and preset.selection_weight > 0.0:
				automatic_preset_count += 1
	if use_weather_presets and not weather_presets.is_empty() and dynamic_weather_enabled and automatic_preset_count < 2:
		warnings.append("Dynamic weather requires at least two weighted automatic presets.")
	if use_weather_presets and not known_ids.is_empty() and initial_weather_id != &"random" and not known_ids.has(String(initial_weather_id)):
		warnings.append("Initial Weather Id does not match an assigned preset.")
	var time_reference: Dictionary = _parse_time_persistence_reference()
	if persistent_time_enabled and time_reference.get("valid") != true:
		warnings.append("Time Persistence Reference must use a channel with an optional offset such as default+1h30m.")
	return warnings


func _ready() -> void:
	add_to_group(&"environment_weather_system")
	_resolve_nodes()
	if Engine.is_editor_hint():
		return
	if use_weather_presets and weather_presets.is_empty():
		apply_prepared_weather_resources()
	var system_time_seed: int = int(Time.get_unix_time_from_system() * 1000000.0)
	var instance_seed: int = int(get_instance_id())
	if weather_random_seed == 0:
		_weather_rng.seed = system_time_seed ^ Time.get_ticks_usec() ^ instance_seed
	else:
		_weather_rng.seed = weather_random_seed
	if time_random_seed == 0:
		_time_rng.seed = system_time_seed ^ Time.get_ticks_usec() ^ instance_seed ^ 0x51F15E5D
	else:
		_time_rng.seed = time_random_seed
	_configure_contained_systems()
	_started_as_network_client = _is_network_client()
	if _started_as_network_client:
		_prepare_network_client()
	else:
		_restore_persistent_time_state()
		var persistent_weather_restored: bool = false
		if use_weather_presets:
			persistent_weather_restored = _restore_persistent_weather_state()
		if not persistent_weather_restored:
			_initialize_authoritative_state()
	if LevelPreparationManager.get_preparation_state() == LevelPreparationManager.PreparationState.IDLE:
		call_deferred("on_level_preparation_ready")


func get_weather_preparation_paths() -> Array[String]:
	var result: Array[String] = []
	if not use_weather_presets:
		return result
	for preset_path: String in weather_preset_paths:
		var normalized_path: String = preset_path.strip_edges()
		if normalized_path != "" and not result.has(normalized_path):
			result.append(normalized_path)
	return result


func apply_prepared_weather_resources() -> bool:
	_resources_prepared = false
	if not use_weather_presets:
		weather_presets.clear()
		_preset_by_id.clear()
		_resources_prepared = true
		return true
	var prepared_presets: Array[DynamicWeatherPreset] = []
	var prepared_by_id: Dictionary = {}
	for preset_path: String in get_weather_preparation_paths():
		var resource: Resource = null
		if LevelPreparationManager.is_cache_enabled():
			resource = LevelPreparationManager.get_prepared_resource(
				preset_path,
				LevelPreparationManager.SCOPE_LEVEL,
				&"EnvironmentWeatherSystem"
			)
		else:
			resource = ResourceLoader.load(preset_path)
		if not (resource is DynamicWeatherPreset):
			push_warning("EnvironmentWeatherSystem: weather preset could not be loaded: %s" % preset_path)
			return false
		var preset: DynamicWeatherPreset = resource as DynamicWeatherPreset
		if preset.preset_id == &"":
			push_warning("EnvironmentWeatherSystem: weather preset has no preset ID: %s" % preset_path)
			return false
		if prepared_by_id.has(preset.preset_id):
			push_warning("EnvironmentWeatherSystem: duplicate weather preset ID: %s" % preset.preset_id)
			return false
		prepared_presets.append(preset)
		prepared_by_id[preset.preset_id] = preset
	if prepared_presets.is_empty():
		push_warning("EnvironmentWeatherSystem: no weather presets were prepared.")
		return false
	weather_presets = prepared_presets
	_preset_by_id = prepared_by_id
	_resources_prepared = true
	_missing_remote_preset_ids.clear()
	return true


func on_level_preparation_ready() -> void:
	if Engine.is_editor_hint() or _level_preparation_ready:
		return
	if use_weather_presets and not _resources_prepared:
		push_error("EnvironmentWeatherSystem: level readiness opened before weather resources were prepared.")
		return
	_network_level_key = _resolve_network_level_key()
	_level_preparation_ready = true
	_connect_session_clock()
	if _started_as_network_client:
		_prepare_network_client()
		call_deferred("_request_full_network_state")


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _level_preparation_ready:
		return
	var client_now: bool = _is_network_client()
	if client_now != _started_as_network_client:
		_started_as_network_client = client_now
		if client_now:
			_prepare_network_client()
		elif _day_night_cycle:
			_day_night_cycle.cycle_enabled = time_progression_enabled
	if _started_as_network_client:
		_process_network_client(delta)
	else:
		_process_authoritative_weather(delta)
		_process_network_broadcast(delta)
		_update_persistent_state(delta)
	_process_session_clock(delta)


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and not _started_as_network_client:
		_store_persistent_weather_state()
		_store_persistent_time_state()


func transition_to_weather_id(preset_id: StringName, duration_seconds: float = -1.0) -> bool:
	if not use_weather_presets or _is_network_client():
		return false
	var target: DynamicWeatherPreset = _find_preset(preset_id)
	if not target:
		return false
	var duration: float = duration_seconds
	if duration < 0.0:
		duration = _random_range(target.transition_range_seconds, 0.0)
	_begin_authoritative_weather(target, duration)
	return true


func set_static_weather(preset_id: StringName, duration_seconds: float = 0.0) -> bool:
	if not use_weather_presets or _is_network_client():
		return false
	dynamic_weather_enabled = false
	var changed: bool = transition_to_weather_id(preset_id, duration_seconds)
	_broadcast_full_state()
	return changed


func set_dynamic_weather_active(active: bool) -> void:
	if _is_network_client():
		return
	dynamic_weather_enabled = active and use_weather_presets
	if active and _current_preset:
		_weather_duration_remaining = _random_range(
			_current_preset.duration_range_seconds,
			1.0
		)
	_broadcast_full_state()


func set_time_progression_active(active: bool) -> void:
	if _is_network_client():
		return
	time_progression_enabled = active
	if _day_night_cycle:
		_day_night_cycle.cycle_enabled = active
	if _uses_session_clock() and multiplayer.is_server():
		_clock_session.set_environment_clock_progression(_clock_channel, active)
	_broadcast_full_state()


func set_precipitation_active(active: bool) -> void:
	if _is_network_client():
		return
	_apply_precipitation_setting(active)
	_broadcast_full_state()


func force_next_weather() -> void:
	if not use_weather_presets or _is_network_client() or not dynamic_weather_enabled:
		return
	_select_and_begin_next_weather()


func get_current_weather_id() -> StringName:
	return _current_preset.preset_id if _current_preset else &""


func clear_persistent_weather_state() -> void:
	var state_store: Node = get_node_or_null("/root/EnvironmentWeatherState")
	if state_store and state_store.has_method("clear_state"):
		state_store.call("clear_state", _get_weather_state_namespace())


func clear_persistent_time_state() -> void:
	var state_store: Node = get_node_or_null("/root/EnvironmentWeatherState")
	if not state_store or not state_store.has_method("clear_state"):
		return
	var time_reference: Dictionary = _parse_time_persistence_reference()
	if time_reference.get("valid") == true:
		state_store.call("clear_state", _get_time_state_namespace(time_reference))


func _resolve_nodes() -> void:
	_day_night_cycle = get_node_or_null(day_night_cycle_path) as DayNightCycle
	_rain_system = get_node_or_null(rain_system_path) as RainSystem


func _configure_contained_systems() -> void:
	if _day_night_cycle:
		if environment_profile:
			_day_night_cycle.profile = environment_profile
		_day_night_cycle.day_length_minutes = day_length_minutes
		_day_night_cycle.uneven_day_night_durations_enabled = uneven_day_night_durations_enabled
		_day_night_cycle.daylight_start_hour = daylight_start_hour
		_day_night_cycle.daylight_end_hour = daylight_end_hour
		_day_night_cycle.daylight_duration_ratio = daylight_duration_ratio
		_day_night_cycle.cycle_enabled = time_progression_enabled
		_day_night_cycle.set_time(_get_initial_time_hours())
	if _rain_system:
		_rain_system.set_system_active(precipitation_enabled)
	for path: NodePath in additional_weather_system_paths:
		var weather_system: Node = get_node_or_null(path)
		if weather_system and weather_system.has_method("set_weather_system_active"):
			weather_system.call("set_weather_system_active", true)


func _initialize_authoritative_state() -> void:
	if not use_weather_presets:
		_current_preset = null
		_weather_duration_remaining = 0.0
		_weather_transition_remaining = 0.0
		return
	var initial_preset: DynamicWeatherPreset = null
	if initial_weather_id == &"random":
		initial_preset = _select_next_weather()
		if not initial_preset:
			initial_preset = _random_valid_preset()
	else:
		initial_preset = _find_preset(initial_weather_id)
	if not initial_preset:
		initial_preset = _first_valid_preset()
	if not initial_preset:
		return
	_apply_weather_preset(initial_preset, 0.0)
	_weather_transition_remaining = 0.0
	_weather_duration_remaining = _random_range(initial_preset.duration_range_seconds, 1.0)
	_remember_weather(initial_preset.preset_id)
	_store_persistent_weather_state()


func _process_authoritative_weather(delta: float) -> void:
	if _day_night_cycle:
		_day_night_cycle.cycle_enabled = time_progression_enabled
		_day_night_cycle.day_length_minutes = day_length_minutes
		_day_night_cycle.uneven_day_night_durations_enabled = uneven_day_night_durations_enabled
		_day_night_cycle.daylight_start_hour = daylight_start_hour
		_day_night_cycle.daylight_end_hour = daylight_end_hour
		_day_night_cycle.daylight_duration_ratio = daylight_duration_ratio
	if not use_weather_presets or not dynamic_weather_enabled or not _current_preset:
		return
	if _weather_transition_remaining > 0.0:
		_weather_transition_remaining = maxf(_weather_transition_remaining - delta, 0.0)
		return
	_weather_duration_remaining = maxf(_weather_duration_remaining - delta, 0.0)
	if _weather_duration_remaining <= 0.0:
		_select_and_begin_next_weather()


func _select_and_begin_next_weather() -> void:
	var target: DynamicWeatherPreset = _select_next_weather()
	if not target:
		return
	var transition_duration: float = _random_range(target.transition_range_seconds, 0.0)
	_begin_authoritative_weather(target, transition_duration)


func _begin_authoritative_weather(target: DynamicWeatherPreset, duration_seconds: float) -> void:
	_state_sequence += 1
	var safe_duration: float = maxf(duration_seconds, 0.0)
	_apply_weather_preset(target, safe_duration)
	_weather_transition_remaining = safe_duration
	_weather_duration_remaining = _random_range(target.duration_range_seconds, 1.0)
	_remember_weather(target.preset_id)
	if _level_preparation_ready and network_sync_enabled and _is_online() and multiplayer.is_server():
		rpc(
			"_rpc_apply_weather",
			_network_level_key,
			String(target.preset_id),
			safe_duration,
			_weather_duration_remaining,
			_state_sequence
		)
	_store_persistent_weather_state()


func _apply_weather_preset(target: DynamicWeatherPreset, duration_seconds: float) -> void:
	if not use_weather_presets or not target:
		return
	_current_preset = target
	weather_transition_started.emit(target.preset_id, duration_seconds)
	if _day_night_cycle and target.sky_weather:
		_day_night_cycle.transition_to_weather(target.sky_weather, duration_seconds)
	if _rain_system and precipitation_enabled and target.rain_profile:
		_rain_system.transition_to_profile(target.rain_profile, duration_seconds)
	for path: NodePath in additional_weather_system_paths:
		var weather_system: Node = get_node_or_null(path)
		if weather_system and weather_system.has_method("transition_to_weather_preset"):
			weather_system.call("transition_to_weather_preset", target, duration_seconds)
	weather_extension_updated.emit(target, duration_seconds)
	weather_changed.emit(target.preset_id)


func _select_next_weather() -> DynamicWeatherPreset:
	var eligible: Array[DynamicWeatherPreset] = []
	for candidate: DynamicWeatherPreset in weather_presets:
		if not candidate or not candidate.automatic_selection_enabled:
			continue
		if candidate.selection_weight <= 0.0:
			continue
		if _current_preset and candidate.preset_id == _current_preset.preset_id:
			continue
		eligible.append(candidate)
	if eligible.is_empty():
		return _current_preset
	var continuity_candidates: Array[DynamicWeatherPreset] = []
	if _current_preset:
		for candidate: DynamicWeatherPreset in eligible:
			if absf(candidate.severity - _current_preset.severity) <= maximum_severity_step:
				continuity_candidates.append(candidate)
	if not continuity_candidates.is_empty():
		eligible = continuity_candidates
	var weights: Array[float] = []
	var total_weight: float = 0.0
	var nighttime: bool = false
	if _day_night_cycle:
		nighttime = _day_night_cycle.get_day_phase() in [&"night", &"dusk"]
	for candidate: DynamicWeatherPreset in eligible:
		var weight: float = maxf(candidate.selection_weight, 0.0)
		weight *= candidate.nighttime_weight_multiplier if nighttime else candidate.daytime_weight_multiplier
		if _current_preset:
			var severity_difference: float = absf(candidate.severity - _current_preset.severity)
			weight *= float(pow(
				maxf(1.0 - severity_difference, 0.01),
				severity_continuity_exponent
			))
		if _recent_weather_ids.has(candidate.preset_id):
			weight *= recent_weather_weight_multiplier
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.000001:
		return eligible[_weather_rng.randi_range(0, eligible.size() - 1)]
	var selection: float = _weather_rng.randf_range(0.0, total_weight)
	for index: int in range(eligible.size()):
		selection -= weights[index]
		if selection <= 0.0:
			return eligible[index]
	return eligible.back()


func _remember_weather(preset_id: StringName) -> void:
	if recent_weather_memory <= 0:
		_recent_weather_ids.clear()
		return
	_recent_weather_ids.append(preset_id)
	while _recent_weather_ids.size() > recent_weather_memory:
		_recent_weather_ids.pop_front()


func _find_preset(preset_id: StringName) -> DynamicWeatherPreset:
	var preset_value: Variant = _preset_by_id.get(preset_id)
	if preset_value is DynamicWeatherPreset:
		return preset_value as DynamicWeatherPreset
	return null


func _first_valid_preset() -> DynamicWeatherPreset:
	for candidate: DynamicWeatherPreset in weather_presets:
		if candidate:
			return candidate
	return null


func _random_valid_preset() -> DynamicWeatherPreset:
	var candidates: Array[DynamicWeatherPreset] = []
	for candidate: DynamicWeatherPreset in weather_presets:
		if candidate:
			candidates.append(candidate)
	if candidates.is_empty():
		return null
	var selected_index: int = _weather_rng.randi_range(0, candidates.size() - 1)
	return candidates[selected_index]


func _random_range(value_range: Vector2, minimum_value: float) -> float:
	var lower_bound: float = maxf(minf(value_range.x, value_range.y), minimum_value)
	var upper_bound: float = maxf(maxf(value_range.x, value_range.y), lower_bound)
	return _weather_rng.randf_range(lower_bound, upper_bound)


func _prepare_network_client() -> void:
	_network_state_received = false
	_full_state_request_elapsed = 2.0
	if _day_night_cycle:
		_day_night_cycle.cycle_enabled = false


func _process_network_client(delta: float) -> void:
	if _day_night_cycle:
		_day_night_cycle.cycle_enabled = false
	if not _network_state_received:
		_full_state_request_elapsed += delta
		if _full_state_request_elapsed >= 2.0:
			_full_state_request_elapsed = 0.0
			_request_full_network_state()
		return
	if not _day_night_cycle or _uses_session_clock():
		return
	if _network_cycle_enabled:
		_network_time_target_hours = _day_night_cycle.calculate_advanced_time(_network_time_target_hours, delta)
	var current_time: float = _day_night_cycle.time_of_day_hours
	var time_difference: float = _shortest_time_difference(current_time, _network_time_target_hours)
	if absf(time_difference) >= network_time_snap_threshold_hours:
		_day_night_cycle.apply_synchronized_time(_network_time_target_hours)
		return
	var interpolation_weight: float = 1.0 - exp(-network_time_interpolation_speed * delta)
	_day_night_cycle.apply_synchronized_time(current_time + time_difference * interpolation_weight)


func _process_network_broadcast(delta: float) -> void:
	if not _level_preparation_ready or not network_sync_enabled or not _is_online() or not multiplayer.is_server():
		return
	_network_sync_elapsed += delta
	if _network_sync_elapsed < network_sync_interval_seconds:
		return
	_network_sync_elapsed = 0.0
	var preset_id: String = String(get_current_weather_id())
	var synchronized_time: float = _day_night_cycle.time_of_day_hours if _day_night_cycle else 0.0
	rpc(
		"_rpc_time_snapshot",
		_network_level_key,
		synchronized_time,
		time_progression_enabled,
		day_length_minutes,
		uneven_day_night_durations_enabled,
		daylight_start_hour,
		daylight_end_hour,
		daylight_duration_ratio,
		dynamic_weather_enabled and use_weather_presets,
		precipitation_enabled,
		preset_id,
		_weather_duration_remaining,
		_weather_transition_remaining,
		_state_sequence
	)


func _request_full_network_state() -> void:
	if not _level_preparation_ready or not network_sync_enabled or not _is_network_client():
		return
	rpc_id(1, "_rpc_request_full_state", _network_level_key)


func _broadcast_full_state() -> void:
	if not _level_preparation_ready or not network_sync_enabled or not _is_online() or not multiplayer.is_server():
		return
	for peer_id: int in multiplayer.get_peers():
		_send_full_state(peer_id)


func _send_full_state(peer_id: int) -> void:
	var synchronized_time: float = _day_night_cycle.time_of_day_hours if _day_night_cycle else 0.0
	rpc_id(
		peer_id,
		"_rpc_receive_full_state",
		_network_level_key,
		synchronized_time,
		time_progression_enabled,
		day_length_minutes,
		uneven_day_night_durations_enabled,
		daylight_start_hour,
		daylight_end_hour,
		daylight_duration_ratio,
		dynamic_weather_enabled and use_weather_presets,
		precipitation_enabled,
		String(get_current_weather_id()),
		_weather_duration_remaining,
		_weather_transition_remaining,
		_state_sequence
	)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_full_state(level_key: String) -> void:
	if not _level_preparation_ready or not network_sync_enabled or not _is_online() or not multiplayer.is_server():
		return
	if level_key != _network_level_key:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id > 0:
		_send_full_state(sender_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_receive_full_state(
	level_key: String,
	server_time_hours: float,
	server_cycle_enabled: bool,
	server_day_length_minutes: float,
	server_uneven_day_night_durations_enabled: bool,
	server_daylight_start_hour: float,
	server_daylight_end_hour: float,
	server_daylight_duration_ratio: float,
	server_dynamic_weather_enabled: bool,
	server_precipitation_enabled: bool,
	preset_id: String,
	weather_duration_remaining: float,
	transition_remaining: float,
	sequence: int
) -> void:
	if not _level_preparation_ready or not _is_network_client() or level_key != _network_level_key:
		return
	var weather_state_is_current: bool = sequence >= _last_received_sequence
	if weather_state_is_current and use_weather_presets and not preset_id.is_empty():
		if not _apply_remote_weather(StringName(preset_id), transition_remaining):
			_network_state_received = false
			return
	_network_state_received = true
	_network_cycle_enabled = server_cycle_enabled
	_network_day_length_minutes = maxf(server_day_length_minutes, 0.1)
	_network_uneven_day_night_durations_enabled = server_uneven_day_night_durations_enabled
	_network_daylight_start_hour = wrapf(server_daylight_start_hour, 0.0, 24.0)
	_network_daylight_end_hour = wrapf(server_daylight_end_hour, 0.0, 24.0)
	_network_daylight_duration_ratio = clampf(server_daylight_duration_ratio, 0.05, 0.95)
	_network_time_target_hours = wrapf(server_time_hours, 0.0, 24.0)
	dynamic_weather_enabled = server_dynamic_weather_enabled and use_weather_presets
	_apply_network_precipitation_setting(server_precipitation_enabled)
	if weather_state_is_current:
		_weather_duration_remaining = maxf(weather_duration_remaining, 0.0)
		_weather_transition_remaining = maxf(transition_remaining, 0.0)
		_last_received_sequence = sequence
	if _day_night_cycle:
		_day_night_cycle.day_length_minutes = _network_day_length_minutes
		_day_night_cycle.uneven_day_night_durations_enabled = _network_uneven_day_night_durations_enabled
		_day_night_cycle.daylight_start_hour = _network_daylight_start_hour
		_day_night_cycle.daylight_end_hour = _network_daylight_end_hour
		_day_night_cycle.daylight_duration_ratio = _network_daylight_duration_ratio
		if not _uses_session_clock():
			_day_night_cycle.apply_synchronized_time(_network_time_target_hours)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_weather(
	level_key: String,
	preset_id: String,
	transition_duration: float,
	weather_duration: float,
	sequence: int
) -> void:
	if (
		not _level_preparation_ready
		or not use_weather_presets
		or not _is_network_client()
		or level_key != _network_level_key
		or sequence <= _last_received_sequence
	):
		return
	if not _apply_remote_weather(StringName(preset_id), transition_duration):
		_network_state_received = false
		return
	_last_received_sequence = sequence
	_weather_transition_remaining = maxf(transition_duration, 0.0)
	_weather_duration_remaining = maxf(weather_duration, 0.0)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_time_snapshot(
	level_key: String,
	server_time_hours: float,
	server_cycle_enabled: bool,
	server_day_length_minutes: float,
	server_uneven_day_night_durations_enabled: bool,
	server_daylight_start_hour: float,
	server_daylight_end_hour: float,
	server_daylight_duration_ratio: float,
	server_dynamic_weather_enabled: bool,
	server_precipitation_enabled: bool,
	preset_id: String,
	weather_duration_remaining: float,
	transition_remaining: float,
	sequence: int
) -> void:
	if not _level_preparation_ready or not _is_network_client() or level_key != _network_level_key:
		return
	var weather_state_is_current: bool = sequence >= _last_received_sequence
	if weather_state_is_current and use_weather_presets and not preset_id.is_empty():
		if not _apply_remote_weather(StringName(preset_id), transition_remaining):
			_network_state_received = false
			return
	_network_state_received = true
	_network_cycle_enabled = server_cycle_enabled
	_network_day_length_minutes = maxf(server_day_length_minutes, 0.1)
	_network_uneven_day_night_durations_enabled = server_uneven_day_night_durations_enabled
	_network_daylight_start_hour = wrapf(server_daylight_start_hour, 0.0, 24.0)
	_network_daylight_end_hour = wrapf(server_daylight_end_hour, 0.0, 24.0)
	_network_daylight_duration_ratio = clampf(server_daylight_duration_ratio, 0.05, 0.95)
	_network_time_target_hours = wrapf(server_time_hours, 0.0, 24.0)
	dynamic_weather_enabled = server_dynamic_weather_enabled and use_weather_presets
	_apply_network_precipitation_setting(server_precipitation_enabled)
	if weather_state_is_current:
		_weather_duration_remaining = maxf(weather_duration_remaining, 0.0)
		_weather_transition_remaining = maxf(transition_remaining, 0.0)
	if _day_night_cycle:
		_day_night_cycle.day_length_minutes = _network_day_length_minutes
		_day_night_cycle.uneven_day_night_durations_enabled = _network_uneven_day_night_durations_enabled
		_day_night_cycle.daylight_start_hour = _network_daylight_start_hour
		_day_night_cycle.daylight_end_hour = _network_daylight_end_hour
		_day_night_cycle.daylight_duration_ratio = _network_daylight_duration_ratio
	if sequence > _last_received_sequence:
		_last_received_sequence = sequence


func _apply_remote_weather(preset_id: StringName, duration_seconds: float) -> bool:
	if not use_weather_presets:
		return true
	if _current_preset and _current_preset.preset_id == preset_id:
		return true
	var target: DynamicWeatherPreset = _find_preset(preset_id)
	if not target:
		if not _missing_remote_preset_ids.has(preset_id):
			_missing_remote_preset_ids[preset_id] = true
			push_error("EnvironmentWeatherSystem: server weather preset is unavailable locally: %s" % preset_id)
		return false
	_apply_weather_preset(target, maxf(duration_seconds, 0.0))
	return true


func _apply_network_precipitation_setting(active: bool) -> void:
	if precipitation_enabled == active:
		return
	_apply_precipitation_setting(active)


func _apply_precipitation_setting(active: bool) -> void:
	precipitation_enabled = active
	if _rain_system:
		_rain_system.set_system_active(active)
		if active and _current_preset and _current_preset.rain_profile:
			_rain_system.transition_to_profile(_current_preset.rain_profile, 0.0)


func _restore_persistent_weather_state() -> bool:
	if not use_weather_presets or not persistent_weather_enabled or not dynamic_weather_enabled:
		return false
	var state_store: Node = get_node_or_null("/root/EnvironmentWeatherState")
	if not state_store or not state_store.has_method("has_state"):
		return false
	var state_namespace: StringName = _get_weather_state_namespace()
	var has_state_value: Variant = state_store.call("has_state", state_namespace)
	if has_state_value != true:
		return false
	var state_value: Variant = state_store.call("get_state", state_namespace)
	if not (state_value is Dictionary):
		return false
	var state: Dictionary = state_value
	if int(state.get("version", 0)) != PERSISTENT_STATE_VERSION:
		return false
	var rng_state_value: Variant = state.get("rng_state")
	if rng_state_value != null:
		_weather_rng.state = int(rng_state_value)
	if persist_cloud_motion and _day_night_cycle:
		var cloud_offset_value: Variant = state.get("cloud_offset")
		if cloud_offset_value is Vector2:
			_day_night_cycle.set_cloud_offset(cloud_offset_value)
	var preset_id: StringName = StringName(String(state.get("preset_id", "")))
	var restored_preset: DynamicWeatherPreset = _find_preset(preset_id)
	if not restored_preset:
		return false
	_apply_weather_preset(restored_preset, 0.0)
	_weather_transition_remaining = 0.0
	_weather_duration_remaining = maxf(float(state.get("weather_duration_remaining", 1.0)), 1.0)
	_remember_weather(restored_preset.preset_id)
	return true


func _restore_persistent_time_state() -> bool:
	if not persistent_time_enabled or not _day_night_cycle:
		return false
	var time_reference: Dictionary = _parse_time_persistence_reference()
	if time_reference.get("valid") != true:
		return false
	var state_store: Node = get_node_or_null("/root/EnvironmentWeatherState")
	if not state_store or not state_store.has_method("has_state"):
		return false
	var state_namespace: StringName = _get_time_state_namespace(time_reference)
	var has_state_value: Variant = state_store.call("has_state", state_namespace)
	if has_state_value != true:
		return false
	var state_value: Variant = state_store.call("get_state", state_namespace)
	if not (state_value is Dictionary):
		return false
	var state: Dictionary = state_value
	if int(state.get("version", 0)) != PERSISTENT_STATE_VERSION:
		return false
	var canonical_hour: float = float(state.get("time_of_day_hours", initial_time_of_day_hours))
	var offset_hours: float = float(time_reference.get("offset_hours", 0.0))
	_day_night_cycle.set_time(wrapf(canonical_hour + offset_hours, 0.0, 24.0))
	return true


func _update_persistent_state(delta: float) -> void:
	if not persistent_weather_enabled and not persistent_time_enabled:
		return
	_persistence_elapsed += delta
	if _persistence_elapsed < persistence_update_interval_seconds:
		return
	_persistence_elapsed = 0.0
	_store_persistent_weather_state()
	_store_persistent_time_state()


func _store_persistent_weather_state() -> void:
	if not use_weather_presets or not persistent_weather_enabled or not dynamic_weather_enabled or not _current_preset:
		return
	var state_store: Node = get_node_or_null("/root/EnvironmentWeatherState")
	if not state_store or not state_store.has_method("set_state"):
		return
	var stored_cloud_offset: Vector2 = Vector2.ZERO
	if is_instance_valid(_day_night_cycle):
		stored_cloud_offset = _day_night_cycle.get_cloud_offset()
	var state: Dictionary = {
		"version": PERSISTENT_STATE_VERSION,
		"preset_id": String(_current_preset.preset_id),
		"weather_duration_remaining": _weather_duration_remaining,
		"cloud_offset": stored_cloud_offset,
		"rng_state": _weather_rng.state,
	}
	state_store.call("set_state", _get_weather_state_namespace(), state)


func _store_persistent_time_state() -> void:
	if not persistent_time_enabled or not is_instance_valid(_day_night_cycle):
		return
	var time_reference: Dictionary = _parse_time_persistence_reference()
	if time_reference.get("valid") != true:
		return
	var state_store: Node = get_node_or_null("/root/EnvironmentWeatherState")
	if not state_store or not state_store.has_method("set_state"):
		return
	var offset_hours: float = float(time_reference.get("offset_hours", 0.0))
	var canonical_hour: float = wrapf(_day_night_cycle.time_of_day_hours - offset_hours, 0.0, 24.0)
	var state: Dictionary = {
		"version": PERSISTENT_STATE_VERSION,
		"time_of_day_hours": canonical_hour,
	}
	state_store.call("set_state", _get_time_state_namespace(time_reference), state)


func _get_initial_time_hours() -> float:
	if initial_time_mode == InitialTimeMode.RANDOM:
		return _time_rng.randf_range(0.0, 24.0)
	return initial_time_of_day_hours


func _get_weather_state_namespace() -> StringName:
	return StringName(WEATHER_STATE_PREFIX + String(weather_persistence_namespace))


func _get_time_state_namespace(time_reference: Dictionary) -> StringName:
	var channel: String = String(time_reference.get("channel", "default"))
	return StringName(TIME_STATE_PREFIX + channel)


func _parse_time_persistence_reference() -> Dictionary:
	var reference_text: String = time_persistence_reference.strip_edges()
	if reference_text.is_empty():
		return {"valid": false, "channel": "", "offset_hours": 0.0}
	var separator_index: int = -1
	var offset_sign: float = 1.0
	for index: int in range(1, reference_text.length()):
		var character: String = reference_text.substr(index, 1)
		if character == "+" or character == "-":
			separator_index = index
			offset_sign = -1.0 if character == "-" else 1.0
			break
	var channel: String = reference_text
	var offset_hours: float = 0.0
	if separator_index >= 0:
		channel = reference_text.substr(0, separator_index).strip_edges()
		var offset_text: String = reference_text.substr(separator_index + 1).strip_edges()
		var offset_result: Dictionary = _parse_game_hour_offset(offset_text)
		if offset_result.get("valid") != true:
			return {"valid": false, "channel": channel, "offset_hours": 0.0}
		offset_hours = float(offset_result.get("hours", 0.0)) * offset_sign
	if channel.is_empty():
		return {"valid": false, "channel": "", "offset_hours": 0.0}
	return {"valid": true, "channel": channel, "offset_hours": offset_hours}


func _parse_game_hour_offset(offset_text: String) -> Dictionary:
	var remaining: String = offset_text.to_lower().replace(" ", "")
	if remaining.is_empty():
		return {"valid": false, "hours": 0.0}
	var offset_hours: float = 0.0
	var has_hour_unit: bool = false
	var hour_separator: int = remaining.find("h")
	if hour_separator >= 0:
		if remaining.find("h", hour_separator + 1) >= 0:
			return {"valid": false, "hours": 0.0}
		var hour_text: String = remaining.substr(0, hour_separator)
		if hour_text.is_empty() or not hour_text.is_valid_float():
			return {"valid": false, "hours": 0.0}
		offset_hours += float(hour_text)
		remaining = remaining.substr(hour_separator + 1)
		has_hour_unit = true
	if remaining.ends_with("m"):
		var minute_text: String = remaining.substr(0, remaining.length() - 1)
		if minute_text.is_empty() or not minute_text.is_valid_float():
			return {"valid": false, "hours": 0.0}
		offset_hours += float(minute_text) / 60.0
		remaining = ""
	elif not remaining.is_empty():
		if has_hour_unit or not remaining.is_valid_float():
			return {"valid": false, "hours": 0.0}
		offset_hours += float(remaining)
		remaining = ""
	if not remaining.is_empty():
		return {"valid": false, "hours": 0.0}
	return {"valid": true, "hours": offset_hours}


func _shortest_time_difference(from_hour: float, to_hour: float) -> float:
	return fposmod(to_hour - from_hour + 12.0, 24.0) - 12.0


func _resolve_network_level_key() -> String:
	if get_tree() == null:
		return ""
	var level_manager: Node = get_tree().root.find_child("LevelManager", true, false)
	if level_manager != null and level_manager.has_method("get_current_level_scene_path"):
		var level_scene_path: String = String(level_manager.call("get_current_level_scene_path"))
		if not level_scene_path.is_empty():
			return level_scene_path
	if level_manager != null and level_manager.has_method("get_current_level_id"):
		var level_id: StringName = StringName(String(level_manager.call("get_current_level_id")))
		if level_id != &"":
			return String(level_id)
	if get_tree().current_scene != null:
		return get_tree().current_scene.scene_file_path
	return ""


func _is_online() -> bool:
	return multiplayer and multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func _is_network_client() -> bool:
	return network_sync_enabled and _is_online() and not multiplayer.is_server()


func _uses_session_clock() -> bool:
	return network_sync_enabled and _is_online() and is_instance_valid(_clock_session)


func _connect_session_clock() -> void:
	_clock_session = get_tree().get_first_node_in_group("NetworkSession")
	if not _clock_session or not _clock_session.has_signal("environment_clock_received"):
		_clock_session = null
		return
	var reference: Dictionary = _parse_time_persistence_reference()
	_clock_channel = "time:" + String(reference.get("channel", "default")) if persistent_time_enabled else "level:" + _network_level_key
	_clock_offset = float(reference.get("offset_hours", 0.0)) if persistent_time_enabled else 0.0
	if not _clock_session.environment_clock_received.is_connected(_on_session_clock):
		_clock_session.environment_clock_received.connect(_on_session_clock)


func _process_session_clock(delta: float) -> void:
	if not is_instance_valid(_clock_session):
		_connect_session_clock()
	if not _uses_session_clock() or not _day_night_cycle:
		_clock_received = false
		return
	_day_night_cycle.cycle_enabled = false
	_clock_poll_elapsed += delta
	if _clock_poll_elapsed >= maxf(network_sync_interval_seconds, 0.1):
		_clock_poll_elapsed = 0.0
		_clock_session.request_environment_clock(_clock_channel, _day_night_cycle.time_of_day_hours - _clock_offset, {
			"enabled": time_progression_enabled, "length": day_length_minutes,
			"uneven": uneven_day_night_durations_enabled, "start": daylight_start_hour,
			"end": daylight_end_hour, "ratio": daylight_duration_ratio,
		})
	if not _clock_received:
		return
	_day_night_cycle.day_length_minutes = float(_clock_settings.get("length", day_length_minutes))
	_day_night_cycle.uneven_day_night_durations_enabled = bool(_clock_settings.get("uneven", uneven_day_night_durations_enabled))
	_day_night_cycle.daylight_start_hour = float(_clock_settings.get("start", daylight_start_hour))
	_day_night_cycle.daylight_end_hour = float(_clock_settings.get("end", daylight_end_hour))
	_day_night_cycle.daylight_duration_ratio = float(_clock_settings.get("ratio", daylight_duration_ratio))
	var advance_seconds: float = delta
	if _clock_settings.has("transition"):
		var transition: Dictionary = _clock_settings["transition"]
		var elapsed: float = float(transition["elapsed"]) + delta
		var duration: float = float(transition["duration"])
		transition["elapsed"] = elapsed
		_clock_hour = float(transition["start"]) + float(transition["delta"]) * smoothstep(0.0, 1.0, minf(elapsed / duration, 1.0))
		advance_seconds = maxf(elapsed - duration, 0.0)
		if elapsed >= duration:
			_clock_settings.erase("transition")
	if bool(_clock_settings.get("enabled", true)):
		_clock_hour = _day_night_cycle.calculate_advanced_time(_clock_hour, advance_seconds)
	_day_night_cycle.apply_synchronized_time(_clock_hour + _clock_offset)


func _on_session_clock(channel: String, hour: float, settings: Dictionary) -> void:
	if channel != _clock_channel:
		return
	_clock_received = true
	_clock_hour = hour
	_clock_settings = settings.duplicate(true)


func synchronize_time_transition(hour: float, duration: float, shortest_path: bool) -> bool:
	if not _uses_session_clock() or not _clock_received:
		return false
	_clock_session.transition_environment_clock(_clock_channel, hour - _clock_offset, duration, shortest_path)
	return true

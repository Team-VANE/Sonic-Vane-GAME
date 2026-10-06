@tool
extends Node3D
class_name DayNightCycle

signal time_changed(hour: float, normalized_time: float)
signal phase_changed(phase: StringName)
signal time_transition_finished(hour: float)
signal weather_transition_finished(weather: DayNightWeather)
signal profile_transition_finished(profile: DayNightProfile)

@export_group("Resources")
## Lighting, atmosphere, fog, and celestial appearance sampled across the day.
@export var profile: DayNightProfile
## Current cloud and weather configuration.
@export var weather: DayNightWeather

@export_group("Time")
## Current local solar time in hours.
@export_range(0.0, 24.0, 0.001) var time_of_day_hours: float = 9.0:
	set(value):
		time_of_day_hours = wrapf(value, 0.0, 24.0)
		_force_update = true
## Advances the clock during gameplay.
@export var cycle_enabled: bool = true
## Real-time minutes required for a complete in-game day.
@export_range(0.1, 1440.0, 0.1) var day_length_minutes: float = 24.0
## Gives the daylight and nighttime clock ranges different shares of the complete cycle duration.
@export var uneven_day_night_durations_enabled: bool = true
## Game-clock hour at which the slower daylight portion begins.
@export_range(0.0, 24.0, 0.01) var daylight_start_hour: float = 6.0
## Game-clock hour at which the faster nighttime portion begins.
@export_range(0.0, 24.0, 0.01) var daylight_end_hour: float = 18.0
## Fraction of the complete real-time cycle spent within the configured daylight clock range.
@export_range(0.05, 0.95, 0.01) var daylight_duration_ratio: float = 0.7
## Allows time and profile changes to preview in the editor viewport.
@export var editor_preview_enabled: bool = true

@export_group("Performance")
## Interval between sky, environment, and radiance changes; lights still rotate every frame.
@export_range(0.016, 10.0, 0.001) var environment_update_interval_seconds: float = 0.2
## Interval between visible cloud-motion updates. Zero updates every rendered frame for smooth high-speed wind.
@export_range(0.0, 1.0, 0.001) var cloud_motion_update_interval_seconds: float = 0.0

@export_group("Fixed Scene Attributes")
## Keeps scene-authored fog enablement, color, density, and sun scatter unchanged by time and weather.
@export var fixed_scene_fog: bool = false

@export_group("Time-Driven Attributes")
## Updates atmosphere colors, scattering, and ground-sky appearance from the day-night profile.
@export var time_controls_sky_appearance: bool = true
## Updates sky energy, ambient color, and ambient energy from the day-night profile.
@export var time_controls_environment_lighting: bool = true
## Rotates the sun and moon according to the game clock.
@export var time_controls_celestial_motion: bool = true
## Updates sun and moon colors, energy, visibility, and angular size from the day-night profile.
@export var time_controls_celestial_lighting: bool = true
## Updates procedural star appearance and visibility from the day-night profile.
@export var time_controls_starfield: bool = true
## Updates cloud light and shadow colors from the day-night profile.
@export var time_controls_cloud_lighting: bool = true
## Updates fog enablement, color, density, and sun scatter from the day-night profile.
@export var time_controls_fog: bool = true

@export_group("Weather-Driven Attributes")
## Updates procedural cloud shape, layers, motion, and horizon projection from weather resources.
@export var weather_controls_clouds: bool = true
## Applies overcast multipliers to ambient, sun, and moon energy.
@export var weather_controls_lighting: bool = true
## Applies weather density multipliers to fog.
@export var weather_controls_fog: bool = true
## Applies weather saturation multipliers to the scene-authored Environment saturation.
@export var weather_controls_saturation: bool = true

@export_group("Celestial Orbit")
## World-space compass rotation of the sun path around world up.
@export_range(-180.0, 180.0, 0.1) var sun_path_azimuth_degrees: float = 0.0
## Tilt of the sun path relative to the world horizon.
@export_range(-45.0, 45.0, 0.1) var sun_path_tilt_degrees: float = 0.0
## Time offset between the sun and moon orbits.
@export_range(0.0, 24.0, 0.01) var moon_orbit_offset_hours: float = 12.0
## Additional inclination of the moon path.
@export_range(-45.0, 45.0, 0.1) var moon_orbit_inclination_degrees: float = 5.0
## Lunar phase from new moon at 0, full moon at 0.5, and new moon at 1.
@export_range(0.0, 1.0, 0.001) var moon_phase: float = 0.5

@export_group("Scene References")
## WorldEnvironment controlled by this cycle.
@export_node_path("WorldEnvironment") var world_environment_path: NodePath = NodePath("WorldEnvironment")
## DirectionalLight3D used for direct sunlight and sun shadows.
@export_node_path("DirectionalLight3D") var sun_light_path: NodePath = NodePath("Sun")
## DirectionalLight3D used for moonlight.
@export_node_path("DirectionalLight3D") var moon_light_path: NodePath = NodePath("Moon")
## Registers the controlled environment, sun, and moon with the project's graphics settings manager.
@export var register_graphics_targets: bool = true

var _world_environment: WorldEnvironment
var _sun_light: DirectionalLight3D
var _moon_light: DirectionalLight3D
var _sky_material: ShaderMaterial
var _cloud_offset: Vector2 = Vector2.ZERO
var _update_elapsed: float = 0.0
var _cloud_update_elapsed: float = 0.0
var _force_update: bool = true
var _current_phase: StringName = &""

var _time_transition_active: bool = false
var _time_transition_start: float = 0.0
var _time_transition_delta: float = 0.0
var _time_transition_duration: float = 0.0
var _time_transition_elapsed: float = 0.0

var _weather_transition_active: bool = false
var _weather_transition_from: Dictionary = {}
var _weather_transition_target: DayNightWeather
var _weather_transition_duration: float = 0.0
var _weather_transition_elapsed: float = 0.0

var _profile_transition_active: bool = false
var _profile_transition_from: Dictionary = {}
var _profile_transition_target: DayNightProfile
var _profile_transition_duration: float = 0.0
var _profile_transition_elapsed: float = 0.0

var _fixed_background_energy: float = 1.0
var _fixed_ambient_color: Color = Color.WHITE
var _fixed_ambient_energy: float = 1.0
var _fixed_fog_enabled: bool = false
var _fixed_fog_color: Color = Color.WHITE
var _fixed_fog_density: float = 0.0
var _fixed_fog_sun_scatter: float = 0.0
var _fixed_saturation: float = 1.0
var _fixed_sun_color: Color = Color.WHITE
var _fixed_sun_energy: float = 0.0
var _fixed_sun_visible: bool = true
var _fixed_sun_angular_distance: float = 0.53
var _fixed_sun_transform: Transform3D = Transform3D.IDENTITY
var _fixed_moon_color: Color = Color.WHITE
var _fixed_moon_energy: float = 0.0
var _fixed_moon_visible: bool = true
var _fixed_moon_angular_distance: float = 0.52
var _fixed_moon_transform: Transform3D = Transform3D.IDENTITY
var _fixed_sky_parameters: Dictionary = {}
var _fixed_state_captured: bool = false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if uneven_day_night_durations_enabled and is_equal_approx(
		wrapf(daylight_start_hour, 0.0, 24.0),
		wrapf(daylight_end_hour, 0.0, 24.0)
	):
		warnings.append("Daylight Start Hour and Daylight End Hour must differ while uneven durations are enabled.")
	return warnings


func _ready() -> void:
	add_to_group(&"day_night_cycle")
	_resolve_nodes()
	_capture_fixed_scene_state()
	_apply_celestial_transforms()
	_apply_environment_state()
	if not Engine.is_editor_hint():
		_register_with_graphics_settings()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_elapsed += delta
		if editor_preview_enabled and (_force_update or _update_elapsed >= environment_update_interval_seconds):
			_resolve_nodes()
			_apply_celestial_transforms()
			_apply_environment_state()
		return

	var time_changed_this_frame: bool = _advance_time(delta)
	_advance_profile_transition(delta)
	_advance_weather_transition(delta)

	var weather_state: Dictionary = _get_weather_state()
	var wind_direction: Vector2 = weather_state.get("wind_direction", Vector2.ZERO)
	var has_wind_direction: bool = wind_direction.length_squared() > 0.000001
	if has_wind_direction:
		wind_direction = wind_direction.normalized()
	var wind_speed: float = float(weather_state.get("wind_speed", 0.0))
	var cloud_motion_active: bool = weather_controls_clouds and has_wind_direction and wind_speed > 0.000001
	if cloud_motion_active:
		_cloud_offset += wind_direction * wind_speed * delta
		_cloud_update_elapsed += delta

	if time_changed_this_frame:
		_apply_celestial_transforms()
	_update_elapsed += delta
	var environment_update_due: bool = _force_update or _update_elapsed >= environment_update_interval_seconds
	var cloud_update_due: bool = cloud_motion_active and (cloud_motion_update_interval_seconds <= 0.0 or _cloud_update_elapsed >= cloud_motion_update_interval_seconds)
	if environment_update_due:
		_apply_environment_state()
	elif cloud_update_due:
		_apply_cloud_motion()


func set_time(hour: float) -> void:
	if _synchronize_time_transition(hour, 0.0, true):
		return
	_time_transition_active = false
	time_of_day_hours = hour
	_apply_celestial_transforms()
	_apply_environment_state()


func offset_time(hours: float) -> void:
	set_time(time_of_day_hours + hours)


func apply_synchronized_time(hour: float) -> void:
	_time_transition_active = false
	time_of_day_hours = hour
	_apply_celestial_transforms()


func get_cloud_offset() -> Vector2:
	return _cloud_offset


func set_cloud_offset(value: Vector2) -> void:
	_cloud_offset = value
	_apply_cloud_motion()


func transition_to_time(hour: float, duration_seconds: float, shortest_path: bool = true) -> void:
	if _synchronize_time_transition(hour, duration_seconds, shortest_path):
		return
	var target_hour: float = wrapf(hour, 0.0, 24.0)
	if duration_seconds <= 0.0:
		set_time(target_hour)
		time_transition_finished.emit(time_of_day_hours)
		return
	_time_transition_start = time_of_day_hours
	_time_transition_delta = fposmod(target_hour - time_of_day_hours + 12.0, 24.0) - 12.0
	if not shortest_path and _time_transition_delta < 0.0:
		_time_transition_delta += 24.0
	_time_transition_duration = duration_seconds
	_time_transition_elapsed = 0.0
	_time_transition_active = true


func transition_to_weather(target_weather: DayNightWeather, duration_seconds: float) -> void:
	if not target_weather:
		return
	if duration_seconds <= 0.0:
		weather = target_weather
		_weather_transition_active = false
		_force_update = true
		weather_transition_finished.emit(weather)
		return
	_weather_transition_from = _get_weather_state()
	_weather_transition_target = target_weather
	_weather_transition_duration = duration_seconds
	_weather_transition_elapsed = 0.0
	_weather_transition_active = true


func transition_to_profile(target_profile: DayNightProfile, duration_seconds: float) -> void:
	if not target_profile:
		return
	if duration_seconds <= 0.0:
		profile = target_profile
		_profile_transition_active = false
		_force_update = true
		profile_transition_finished.emit(profile)
		return
	_profile_transition_from = _get_profile_state()
	_profile_transition_target = target_profile
	_profile_transition_duration = duration_seconds
	_profile_transition_elapsed = 0.0
	_profile_transition_active = true


func pause_cycle() -> void:
	cycle_enabled = false


func resume_cycle() -> void:
	cycle_enabled = true


func get_normalized_time() -> float:
	return time_of_day_hours / 24.0


func get_sun_direction() -> Vector3:
	return _get_orbit_direction(time_of_day_hours, sun_path_tilt_degrees)


func get_moon_direction() -> Vector3:
	return _get_orbit_direction(time_of_day_hours + moon_orbit_offset_hours, sun_path_tilt_degrees + moon_orbit_inclination_degrees)


func get_day_phase() -> StringName:
	var sun_height: float = get_sun_direction().y
	if sun_height > 0.12:
		return &"day"
	if sun_height > -0.16:
		return &"dawn" if time_of_day_hours < 12.0 else &"dusk"
	return &"night"


func _advance_time(delta: float) -> bool:
	if _time_transition_active:
		_time_transition_elapsed = minf(_time_transition_elapsed + delta, _time_transition_duration)
		var weight: float = smoothstep(0.0, 1.0, _time_transition_elapsed / _time_transition_duration)
		time_of_day_hours = _time_transition_start + _time_transition_delta * weight
		if _time_transition_elapsed >= _time_transition_duration:
			_time_transition_active = false
			time_transition_finished.emit(time_of_day_hours)
		return true
	if not cycle_enabled:
		return false
	time_of_day_hours = calculate_advanced_time(time_of_day_hours, delta)
	return true


func calculate_advanced_time(hour: float, real_seconds: float) -> float:
	var seconds_per_day: float = maxf(day_length_minutes * 60.0, 0.001)
	if not uneven_day_night_durations_enabled:
		return wrapf(hour + real_seconds * 24.0 / seconds_per_day, 0.0, 24.0)
	var daylight_start: float = wrapf(daylight_start_hour, 0.0, 24.0)
	var daylight_end: float = wrapf(daylight_end_hour, 0.0, 24.0)
	var daylight_hours: float = fposmod(daylight_end - daylight_start, 24.0)
	if daylight_hours <= 0.001 or daylight_hours >= 23.999:
		return wrapf(hour + real_seconds * 24.0 / seconds_per_day, 0.0, 24.0)
	var nighttime_hours: float = 24.0 - daylight_hours
	var daylight_ratio: float = clampf(daylight_duration_ratio, 0.05, 0.95)
	var daylight_rate: float = daylight_hours / maxf(seconds_per_day * daylight_ratio, 0.001)
	var nighttime_rate: float = nighttime_hours / maxf(seconds_per_day * (1.0 - daylight_ratio), 0.001)
	var remaining_seconds: float = fposmod(maxf(real_seconds, 0.0), seconds_per_day)
	var advanced_hour: float = wrapf(hour, 0.0, 24.0)
	var segment_count: int = 0
	while remaining_seconds > 0.000001 and segment_count < 3:
		var hours_since_daylight_start: float = fposmod(advanced_hour - daylight_start, 24.0)
		var is_daylight: bool = hours_since_daylight_start < daylight_hours
		var boundary_hour: float = daylight_end if is_daylight else daylight_start
		var clock_rate: float = daylight_rate if is_daylight else nighttime_rate
		var hours_to_boundary: float = fposmod(boundary_hour - advanced_hour, 24.0)
		var seconds_to_boundary: float = hours_to_boundary / clock_rate
		if remaining_seconds < seconds_to_boundary:
			advanced_hour = wrapf(advanced_hour + remaining_seconds * clock_rate, 0.0, 24.0)
			remaining_seconds = 0.0
		else:
			advanced_hour = boundary_hour
			remaining_seconds -= seconds_to_boundary
		segment_count += 1
	return advanced_hour


func _advance_weather_transition(delta: float) -> void:
	if not _weather_transition_active:
		return
	_weather_transition_elapsed = minf(_weather_transition_elapsed + delta, _weather_transition_duration)
	_force_update = true
	if _weather_transition_elapsed >= _weather_transition_duration:
		weather = _weather_transition_target
		_weather_transition_active = false
		weather_transition_finished.emit(weather)


func _advance_profile_transition(delta: float) -> void:
	if not _profile_transition_active:
		return
	_profile_transition_elapsed = minf(_profile_transition_elapsed + delta, _profile_transition_duration)
	_force_update = true
	if _profile_transition_elapsed >= _profile_transition_duration:
		profile = _profile_transition_target
		_profile_transition_active = false
		profile_transition_finished.emit(profile)


func _resolve_nodes() -> void:
	_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	_moon_light = get_node_or_null(moon_light_path) as DirectionalLight3D
	_sky_material = null
	if _world_environment and _world_environment.environment and _world_environment.environment.sky:
		_sky_material = _world_environment.environment.sky.sky_material as ShaderMaterial


func _capture_fixed_scene_state() -> void:
	if _world_environment and _world_environment.environment:
		var environment: Environment = _world_environment.environment
		_fixed_background_energy = environment.background_energy_multiplier
		_fixed_ambient_color = environment.ambient_light_color
		_fixed_ambient_energy = environment.ambient_light_energy
		_fixed_fog_enabled = environment.fog_enabled
		_fixed_fog_color = environment.fog_light_color
		_fixed_fog_density = environment.fog_density
		_fixed_fog_sun_scatter = environment.fog_sun_scatter
		_fixed_saturation = environment.adjustment_saturation
	if _sun_light:
		_fixed_sun_color = _sun_light.light_color
		_fixed_sun_energy = _sun_light.light_energy
		_fixed_sun_visible = _sun_light.visible
		_fixed_sun_angular_distance = _sun_light.light_angular_distance
		_fixed_sun_transform = _sun_light.global_transform
	if _moon_light:
		_fixed_moon_color = _moon_light.light_color
		_fixed_moon_energy = _moon_light.light_energy
		_fixed_moon_visible = _moon_light.visible
		_fixed_moon_angular_distance = _moon_light.light_angular_distance
		_fixed_moon_transform = _moon_light.global_transform
	_capture_fixed_shader_parameters()
	_fixed_state_captured = true


func _ensure_fixed_scene_state() -> void:
	if _fixed_state_captured == true:
		return
	_capture_fixed_scene_state()


func _capture_fixed_shader_parameters() -> void:
	_fixed_sky_parameters = {}
	if not _sky_material:
		return
	var parameter_names: Array[StringName] = [
		&"sun_direction", &"moon_direction", &"zenith_color", &"horizon_color", &"ground_color",
		&"ground_visibility", &"rayleigh_strength", &"mie_strength", &"mie_eccentricity", &"turbidity",
		&"sun_color", &"moon_color", &"sun_angular_radius", &"sun_disk_intensity", &"moon_angular_radius",
		&"moon_disk_intensity", &"moon_phase", &"star_visibility", &"star_intensity", &"star_scale",
		&"star_density", &"star_lower_hemisphere_visibility", &"star_cool_color", &"star_warm_color",
		&"cloud_light_color", &"cloud_shadow_color", &"cloud_coverage", &"cloud_density", &"cloud_softness",
		&"cloud_scale", &"cloud_detail", &"cloud_light_absorption", &"cloud_volume_depth", &"cloud_volume_steps",
		&"cloud_optical_density", &"cloud_core_shadow_strength", &"cloud_edge_light_strength", &"cloud_offset", &"lower_layer_height",
		&"upper_layer_amount", &"upper_layer_height", &"upper_layer_scale", &"upper_layer_wind_multiplier",
		&"distance_fade_start", &"distance_fade_end", &"distance_haze_strength", &"above_horizon_clouds_enabled",
		&"below_horizon_clouds_enabled", &"below_horizon_visibility", &"below_horizon_fade_depth",
		&"below_horizon_scale", &"below_horizon_detail", &"below_horizon_curvature", &"below_horizon_haze_strength",
	]
	for parameter_name: StringName in parameter_names:
		_fixed_sky_parameters[parameter_name] = _sky_material.get_shader_parameter(parameter_name)


func _restore_fixed_shader_parameters(parameter_names: Array) -> void:
	if not _sky_material:
		return
	for parameter_name: StringName in parameter_names:
		if _fixed_sky_parameters.has(parameter_name):
			_sky_material.set_shader_parameter(parameter_name, _fixed_sky_parameters[parameter_name])


func _apply_celestial_transforms() -> void:
	_ensure_fixed_scene_state()
	if not time_controls_celestial_motion:
		if _sun_light:
			_sun_light.global_transform = _fixed_sun_transform
		if _moon_light:
			_moon_light.global_transform = _fixed_moon_transform
		return
	var sun_direction: Vector3 = get_sun_direction()
	var moon_direction: Vector3 = get_moon_direction()
	_apply_light_direction(_sun_light, sun_direction)
	_apply_light_direction(_moon_light, moon_direction)


func _apply_light_direction(light: DirectionalLight3D, celestial_direction: Vector3) -> void:
	if not light:
		return
	var basis_up: Vector3 = Vector3.UP
	if absf(celestial_direction.dot(basis_up)) > 0.98:
		basis_up = Vector3.FORWARD
	var light_transform: Transform3D = light.global_transform
	light_transform.basis = Basis.looking_at(-celestial_direction, basis_up)
	light.global_transform = light_transform


func _get_orbit_direction(hour: float, inclination_degrees: float) -> Vector3:
	var orbit_angle: float = (wrapf(hour, 0.0, 24.0) - 6.0) / 24.0 * TAU
	var direction: Vector3 = Vector3(cos(orbit_angle), sin(orbit_angle), 0.0)
	direction = direction.rotated(Vector3.FORWARD, deg_to_rad(inclination_degrees))
	direction = direction.rotated(Vector3.UP, deg_to_rad(sun_path_azimuth_degrees))
	return direction.normalized()


func _apply_environment_state() -> void:
	_update_elapsed = 0.0
	_force_update = false
	if not _world_environment or not _world_environment.environment:
		return
	_ensure_fixed_scene_state()
	var profile_state: Dictionary = _get_profile_state()
	var weather_state: Dictionary = _get_weather_state()
	var cloud_coverage: float = float(weather_state.get("cloud_coverage", 0.0))
	var cloud_density: float = float(weather_state.get("cloud_density", 0.0))
	var overcast: float = clampf(cloud_coverage * cloud_density, 0.0, 1.0)
	var direct_multiplier: float = 1.0
	var ambient_multiplier: float = 1.0
	if weather_controls_lighting:
		direct_multiplier = lerpf(1.0, float(weather_state.get("overcast_light_multiplier", 1.0)), overcast)
		ambient_multiplier = lerpf(1.0, float(weather_state.get("overcast_ambient_multiplier", 1.0)), overcast)

	var environment: Environment = _world_environment.environment
	if time_controls_environment_lighting:
		environment.background_energy_multiplier = float(profile_state["sky_energy"])
		environment.ambient_light_color = profile_state["ambient_color"]
		environment.ambient_light_energy = float(profile_state["ambient_energy"]) * ambient_multiplier
	else:
		environment.background_energy_multiplier = _fixed_background_energy
		environment.ambient_light_color = _fixed_ambient_color
		environment.ambient_light_energy = _fixed_ambient_energy * ambient_multiplier
	if fixed_scene_fog:
		environment.fog_enabled = _fixed_fog_enabled
		environment.fog_light_color = _fixed_fog_color
		environment.fog_density = _fixed_fog_density
		environment.fog_sun_scatter = _fixed_fog_sun_scatter
	elif time_controls_fog or weather_controls_fog:
		var fog_density_multiplier: float = 1.0
		if weather_controls_fog:
			fog_density_multiplier = float(weather_state.get("fog_density_multiplier", 1.0))
		var base_fog_density: float = _fixed_fog_density
		var base_fog_enabled: bool = _fixed_fog_enabled
		if time_controls_fog:
			environment.fog_light_color = profile_state["fog_color"]
			environment.fog_sun_scatter = float(profile_state["fog_sun_scatter"])
			base_fog_density = float(profile_state["fog_density"])
			var profile_fog_value: Variant = profile_state.get("fog_enabled")
			if profile_fog_value != null:
				base_fog_enabled = profile_fog_value == true
		else:
			environment.fog_light_color = _fixed_fog_color
			environment.fog_sun_scatter = _fixed_fog_sun_scatter
		var effective_fog_density: float = base_fog_density * fog_density_multiplier
		environment.fog_enabled = base_fog_enabled and effective_fog_density > 0.0000001
		environment.fog_density = effective_fog_density
	else:
		environment.fog_enabled = _fixed_fog_enabled
		environment.fog_light_color = _fixed_fog_color
		environment.fog_density = _fixed_fog_density
		environment.fog_sun_scatter = _fixed_fog_sun_scatter
	var saturation_multiplier: float = 1.0
	if weather_controls_saturation:
		saturation_multiplier = float(weather_state.get("saturation_multiplier", 1.0))
	environment.adjustment_saturation = _fixed_saturation * saturation_multiplier

	if _sun_light:
		var sun_energy: float = _fixed_sun_energy * direct_multiplier
		if time_controls_celestial_lighting:
			sun_energy = float(profile_state["sun_energy"]) * direct_multiplier
			_sun_light.light_color = profile_state["sun_color"]
			_sun_light.light_angular_distance = float(profile_state["sun_angular_diameter_degrees"])
			_sun_light.visible = sun_energy > 0.0001
		else:
			_sun_light.light_color = _fixed_sun_color
			_sun_light.light_angular_distance = _fixed_sun_angular_distance
			_sun_light.visible = _fixed_sun_visible and sun_energy > 0.0001
		_sun_light.light_energy = sun_energy
	if _moon_light:
		var moon_energy: float = _fixed_moon_energy * direct_multiplier
		if time_controls_celestial_lighting:
			moon_energy = float(profile_state["moon_energy"]) * direct_multiplier
			_moon_light.light_color = profile_state["moon_color"]
			_moon_light.light_angular_distance = float(profile_state["moon_angular_diameter_degrees"])
			_moon_light.visible = moon_energy > 0.0001
		else:
			_moon_light.light_color = _fixed_moon_color
			_moon_light.light_angular_distance = _fixed_moon_angular_distance
			_moon_light.visible = _fixed_moon_visible and moon_energy > 0.0001
		_moon_light.light_energy = moon_energy

	_apply_shader_state(profile_state, weather_state)
	_cloud_update_elapsed = 0.0
	var normalized_time: float = get_normalized_time()
	time_changed.emit(time_of_day_hours, normalized_time)
	var next_phase: StringName = get_day_phase()
	if next_phase != _current_phase:
		_current_phase = next_phase
		phase_changed.emit(_current_phase)


func _apply_shader_state(profile_state: Dictionary, weather_state: Dictionary) -> void:
	if not _sky_material:
		return
	if time_controls_celestial_motion:
		_sky_material.set_shader_parameter("sun_direction", get_sun_direction())
		_sky_material.set_shader_parameter("moon_direction", get_moon_direction())
	else:
		_restore_fixed_shader_parameters([&"sun_direction", &"moon_direction"])
	if time_controls_sky_appearance:
		_sky_material.set_shader_parameter("zenith_color", profile_state["zenith_color"])
		_sky_material.set_shader_parameter("horizon_color", profile_state["horizon_color"])
		_sky_material.set_shader_parameter("ground_color", profile_state["ground_color"])
		_sky_material.set_shader_parameter("ground_visibility", profile_state["ground_visibility"])
		_sky_material.set_shader_parameter("rayleigh_strength", profile_state["rayleigh_strength"])
		_sky_material.set_shader_parameter("mie_strength", profile_state["mie_strength"])
		_sky_material.set_shader_parameter("mie_eccentricity", profile_state["mie_eccentricity"])
		_sky_material.set_shader_parameter("turbidity", profile_state["turbidity"])
	else:
		_restore_fixed_shader_parameters([
			&"zenith_color", &"horizon_color", &"ground_color", &"ground_visibility", &"rayleigh_strength",
			&"mie_strength", &"mie_eccentricity", &"turbidity",
		])
	if time_controls_celestial_lighting:
		_sky_material.set_shader_parameter("sun_color", profile_state["sun_color"])
		_sky_material.set_shader_parameter("moon_color", profile_state["moon_color"])
		_sky_material.set_shader_parameter("sun_angular_radius", deg_to_rad(float(profile_state["sun_angular_diameter_degrees"]) * 0.5))
		_sky_material.set_shader_parameter("sun_disk_intensity", profile_state["sun_disk_intensity"])
		_sky_material.set_shader_parameter("moon_angular_radius", deg_to_rad(float(profile_state["moon_angular_diameter_degrees"]) * 0.5))
		_sky_material.set_shader_parameter("moon_disk_intensity", profile_state["moon_disk_intensity"])
		_sky_material.set_shader_parameter("moon_phase", moon_phase)
	else:
		_restore_fixed_shader_parameters([
			&"sun_color", &"moon_color", &"sun_angular_radius", &"sun_disk_intensity", &"moon_angular_radius",
			&"moon_disk_intensity", &"moon_phase",
		])
	if time_controls_starfield:
		_sky_material.set_shader_parameter("star_visibility", profile_state["star_visibility"])
		_sky_material.set_shader_parameter("star_intensity", profile_state["star_intensity"])
		_sky_material.set_shader_parameter("star_scale", profile_state["star_scale"])
		_sky_material.set_shader_parameter("star_density", profile_state["star_density"])
		_sky_material.set_shader_parameter("star_lower_hemisphere_visibility", profile_state["star_lower_hemisphere_visibility"])
		_sky_material.set_shader_parameter("star_cool_color", profile_state["star_cool_color"])
		_sky_material.set_shader_parameter("star_warm_color", profile_state["star_warm_color"])
	else:
		_restore_fixed_shader_parameters([
			&"star_visibility", &"star_intensity", &"star_scale", &"star_density",
			&"star_lower_hemisphere_visibility", &"star_cool_color", &"star_warm_color",
		])
	if time_controls_cloud_lighting:
		_sky_material.set_shader_parameter("cloud_light_color", profile_state["cloud_light_color"])
		_sky_material.set_shader_parameter("cloud_shadow_color", profile_state["cloud_shadow_color"])
	else:
		_restore_fixed_shader_parameters([&"cloud_light_color", &"cloud_shadow_color"])
	if weather_controls_clouds:
		_sky_material.set_shader_parameter("cloud_coverage", weather_state.get("cloud_coverage", 0.0))
		_sky_material.set_shader_parameter("cloud_density", weather_state.get("cloud_density", 0.0))
		_sky_material.set_shader_parameter("cloud_softness", weather_state.get("cloud_softness", 0.12))
		_sky_material.set_shader_parameter("cloud_scale", weather_state.get("cloud_scale", 3.2))
		_sky_material.set_shader_parameter("cloud_detail", weather_state.get("cloud_detail", 0.72))
		_sky_material.set_shader_parameter("cloud_light_absorption", weather_state.get("cloud_light_absorption", 0.42))
		_sky_material.set_shader_parameter("cloud_volume_depth", weather_state.get("cloud_volume_depth", 0.0))
		_sky_material.set_shader_parameter("cloud_volume_steps", weather_state.get("cloud_volume_steps", 1))
		_sky_material.set_shader_parameter("cloud_optical_density", weather_state.get("cloud_optical_density", 1.0))
		_sky_material.set_shader_parameter("cloud_core_shadow_strength", weather_state.get("cloud_core_shadow_strength", 0.0))
		_sky_material.set_shader_parameter("cloud_edge_light_strength", weather_state.get("cloud_edge_light_strength", 1.0))
		_sky_material.set_shader_parameter("cloud_offset", _cloud_offset)
		_sky_material.set_shader_parameter("lower_layer_height", weather_state.get("lower_layer_height", 0.022))
		_sky_material.set_shader_parameter("upper_layer_amount", weather_state.get("upper_layer_amount", 0.12))
		_sky_material.set_shader_parameter("upper_layer_height", weather_state.get("upper_layer_height", 0.07))
		_sky_material.set_shader_parameter("upper_layer_scale", weather_state.get("upper_layer_scale", 0.62))
		_sky_material.set_shader_parameter("upper_layer_wind_multiplier", weather_state.get("upper_layer_wind_multiplier", 1.45))
		_sky_material.set_shader_parameter("distance_fade_start", weather_state.get("distance_fade_start", 0.82))
		_sky_material.set_shader_parameter("distance_fade_end", weather_state.get("distance_fade_end", 0.995))
		_sky_material.set_shader_parameter("distance_haze_strength", weather_state.get("distance_haze_strength", 0.78))
		_sky_material.set_shader_parameter("above_horizon_clouds_enabled", weather_state.get("above_horizon_clouds_enabled", true))
		_sky_material.set_shader_parameter("below_horizon_clouds_enabled", weather_state.get("below_horizon_clouds_enabled", true))
		_sky_material.set_shader_parameter("below_horizon_visibility", weather_state.get("below_horizon_visibility", 0.0))
		_sky_material.set_shader_parameter("below_horizon_fade_depth", weather_state.get("below_horizon_fade_depth", 0.35))
		_sky_material.set_shader_parameter("below_horizon_scale", weather_state.get("below_horizon_scale", 1.0))
		_sky_material.set_shader_parameter("below_horizon_detail", weather_state.get("below_horizon_detail", 1.0))
		_sky_material.set_shader_parameter("below_horizon_curvature", weather_state.get("below_horizon_curvature", 1.0))
		_sky_material.set_shader_parameter("below_horizon_haze_strength", weather_state.get("below_horizon_haze_strength", 0.72))
	else:
		_restore_fixed_shader_parameters([
			&"cloud_coverage", &"cloud_density", &"cloud_softness", &"cloud_scale", &"cloud_detail",
			&"cloud_light_absorption", &"cloud_volume_depth", &"cloud_volume_steps", &"cloud_optical_density",
			&"cloud_core_shadow_strength", &"cloud_edge_light_strength", &"cloud_offset", &"lower_layer_height", &"upper_layer_amount",
			&"upper_layer_height", &"upper_layer_scale", &"upper_layer_wind_multiplier", &"distance_fade_start",
			&"distance_fade_end", &"distance_haze_strength", &"above_horizon_clouds_enabled",
			&"below_horizon_clouds_enabled", &"below_horizon_visibility", &"below_horizon_fade_depth",
			&"below_horizon_scale", &"below_horizon_detail", &"below_horizon_curvature", &"below_horizon_haze_strength",
		])


func _apply_cloud_motion() -> void:
	_cloud_update_elapsed = 0.0
	if not _sky_material or not weather_controls_clouds:
		return
	_sky_material.set_shader_parameter("cloud_offset", _cloud_offset)


func _get_profile_state() -> Dictionary:
	var normalized_time: float = get_normalized_time()
	var current_state: Dictionary = _sample_profile(profile, normalized_time)
	if not _profile_transition_active or not _profile_transition_target:
		return current_state
	var target_state: Dictionary = _sample_profile(_profile_transition_target, normalized_time)
	var weight: float = smoothstep(0.0, 1.0, _profile_transition_elapsed / _profile_transition_duration)
	return _blend_profile_states(_profile_transition_from, target_state, weight)


func _sample_profile(source: DayNightProfile, normalized_time: float) -> Dictionary:
	if not source:
		return _fallback_profile_state()
	return {
		"ground_color": source.ground_color,
		"ground_visibility": source.ground_visibility,
		"zenith_color": source.sample_color(source.zenith_color, normalized_time, Color(0.12, 0.38, 0.9, 1.0)),
		"horizon_color": source.sample_color(source.horizon_color, normalized_time, Color(0.62, 0.78, 1.0, 1.0)),
		"sun_color": source.sample_color(source.sun_color, normalized_time, Color(1.0, 0.92, 0.78, 1.0)),
		"moon_color": source.sample_color(source.moon_color, normalized_time, Color(0.72, 0.82, 1.0, 1.0)),
		"ambient_color": source.sample_color(source.ambient_color, normalized_time, Color(0.42, 0.55, 0.75, 1.0)),
		"fog_color": source.sample_color(source.fog_color, normalized_time, Color(0.58, 0.7, 0.84, 1.0)),
		"cloud_light_color": source.sample_color(source.cloud_light_color, normalized_time, Color(1.0, 0.98, 0.94, 1.0)),
		"cloud_shadow_color": source.sample_color(source.cloud_shadow_color, normalized_time, Color(0.35, 0.42, 0.52, 1.0)),
		"rayleigh_strength": source.rayleigh_strength,
		"mie_strength": source.mie_strength,
		"mie_eccentricity": source.mie_eccentricity,
		"turbidity": source.turbidity,
		"fog_enabled": source.fog_enabled,
		"sun_angular_diameter_degrees": source.sun_angular_diameter_degrees,
		"sun_disk_intensity": source.sun_disk_intensity,
		"moon_angular_diameter_degrees": source.moon_angular_diameter_degrees,
		"moon_disk_intensity": source.moon_disk_intensity,
		"star_intensity": source.star_intensity,
		"star_scale": source.star_scale,
		"star_density": source.star_density,
		"star_lower_hemisphere_visibility": source.star_lower_hemisphere_visibility,
		"star_cool_color": source.star_cool_color,
		"star_warm_color": source.star_warm_color,
		"sun_energy": source.sample_value(source.sun_energy, normalized_time, 1.0) * source.sun_energy_scale,
		"moon_energy": source.sample_value(source.moon_energy, normalized_time, 0.0) * source.moon_energy_scale,
		"sky_energy": source.sample_value(source.sky_energy, normalized_time, 1.0) * source.sky_energy_scale,
		"ambient_energy": source.sample_value(source.ambient_energy, normalized_time, 1.0) * source.ambient_energy_scale,
		"star_visibility": source.sample_value(source.star_visibility, normalized_time, 0.0),
		"fog_density": source.sample_value(source.fog_density, normalized_time, 0.0002),
		"fog_sun_scatter": source.sample_value(source.fog_sun_scatter, normalized_time, 0.15),
	}


func _fallback_profile_state() -> Dictionary:
	return {
		"ground_color": Color(0.035, 0.028, 0.025, 1.0),
		"ground_visibility": 1.0,
		"zenith_color": Color(0.12, 0.38, 0.9, 1.0),
		"horizon_color": Color(0.62, 0.78, 1.0, 1.0),
		"sun_color": Color(1.0, 0.92, 0.78, 1.0),
		"moon_color": Color(0.72, 0.82, 1.0, 1.0),
		"ambient_color": Color(0.42, 0.55, 0.75, 1.0),
		"fog_color": Color(0.58, 0.7, 0.84, 1.0),
		"cloud_light_color": Color(1.0, 0.98, 0.94, 1.0),
		"cloud_shadow_color": Color(0.35, 0.42, 0.52, 1.0),
		"rayleigh_strength": 2.0,
		"mie_strength": 0.08,
		"mie_eccentricity": 0.8,
		"turbidity": 4.0,
		"fog_enabled": true,
		"sun_angular_diameter_degrees": 0.53,
		"sun_disk_intensity": 18.0,
		"moon_angular_diameter_degrees": 0.52,
		"moon_disk_intensity": 1.2,
		"star_intensity": 1.4,
		"star_scale": 720.0,
		"star_density": 0.28,
		"star_lower_hemisphere_visibility": 0.0,
		"star_cool_color": Color(0.62, 0.72, 1.0, 1.0),
		"star_warm_color": Color(1.0, 0.88, 0.68, 1.0),
		"sun_energy": 1.35,
		"moon_energy": 0.0,
		"sky_energy": 1.0,
		"ambient_energy": 1.0,
		"star_visibility": 0.0,
		"fog_density": 0.0002,
		"fog_sun_scatter": 0.15,
	}


func _blend_profile_states(from_state: Dictionary, to_state: Dictionary, weight: float) -> Dictionary:
	var result: Dictionary = {}
	var color_keys: Array[String] = [
		"ground_color", "zenith_color", "horizon_color", "sun_color", "moon_color",
		"ambient_color", "fog_color", "cloud_light_color", "cloud_shadow_color",
		"star_cool_color", "star_warm_color"
	]
	var float_keys: Array[String] = [
		"ground_visibility", "rayleigh_strength", "mie_strength", "mie_eccentricity", "turbidity",
		"sun_angular_diameter_degrees", "sun_disk_intensity", "moon_angular_diameter_degrees",
		"moon_disk_intensity", "star_intensity", "star_scale", "star_density",
		"star_lower_hemisphere_visibility", "sun_energy", "moon_energy",
		"sky_energy", "ambient_energy", "star_visibility", "fog_density", "fog_sun_scatter"
	]
	for key: String in color_keys:
		var from_color: Color = from_state.get(key, to_state[key])
		var to_color: Color = to_state[key]
		result[key] = from_color.lerp(to_color, weight)
	for key: String in float_keys:
		result[key] = lerpf(float(from_state.get(key, to_state[key])), float(to_state[key]), weight)
	var to_fog_value: Variant = to_state.get("fog_enabled")
	var to_fog_enabled: bool = true
	if to_fog_value != null:
		to_fog_enabled = to_fog_value == true
	var from_fog_value: Variant = from_state.get("fog_enabled")
	var from_fog_enabled: bool = to_fog_enabled
	if from_fog_value != null:
		from_fog_enabled = from_fog_value == true
	result["fog_enabled"] = from_fog_enabled or to_fog_enabled
	return result


func _get_weather_state() -> Dictionary:
	var current_state: Dictionary = _sample_weather(weather)
	if not _weather_transition_active or not _weather_transition_target:
		return current_state
	var target_state: Dictionary = _sample_weather(_weather_transition_target)
	var weight: float = smoothstep(0.0, 1.0, _weather_transition_elapsed / _weather_transition_duration)
	return _blend_weather_states(_weather_transition_from, target_state, weight)


func _sample_weather(source: DayNightWeather) -> Dictionary:
	if not source:
		return {
			"cloud_coverage": 0.0, "cloud_density": 0.0, "cloud_softness": 0.12,
			"cloud_scale": 3.2, "cloud_detail": 0.72, "cloud_light_absorption": 0.42,
			"cloud_volume_depth": 0.0, "cloud_volume_steps": 1, "cloud_optical_density": 1.0,
			"cloud_core_shadow_strength": 0.0, "cloud_edge_light_strength": 1.0,
			"lower_layer_height": 0.022, "upper_layer_amount": 0.12, "upper_layer_height": 0.07,
			"upper_layer_scale": 0.62, "upper_layer_wind_multiplier": 1.45,
			"distance_fade_start": 0.82, "distance_fade_end": 0.995, "distance_haze_strength": 0.78,
			"above_horizon_clouds_enabled": true, "below_horizon_clouds_enabled": true,
			"below_horizon_visibility": 0.0, "below_horizon_fade_depth": 0.35,
			"below_horizon_scale": 1.0, "below_horizon_detail": 1.0,
			"below_horizon_curvature": 1.0, "below_horizon_haze_strength": 0.72,
			"wind_direction": Vector2.ZERO, "wind_speed": 0.0, "overcast_light_multiplier": 1.0,
			"overcast_ambient_multiplier": 1.0, "fog_density_multiplier": 1.0, "saturation_multiplier": 1.0,
		}
	return {
		"cloud_coverage": source.cloud_coverage,
		"cloud_density": source.cloud_density,
		"cloud_softness": source.cloud_softness,
		"cloud_scale": source.cloud_scale,
		"cloud_detail": source.cloud_detail,
		"cloud_light_absorption": source.cloud_light_absorption,
		"cloud_volume_depth": source.cloud_volume_depth,
		"cloud_volume_steps": source.cloud_volume_steps,
		"cloud_optical_density": source.cloud_optical_density,
		"cloud_core_shadow_strength": source.cloud_core_shadow_strength,
		"cloud_edge_light_strength": source.cloud_edge_light_strength,
		"lower_layer_height": source.lower_layer_height,
		"upper_layer_amount": source.upper_layer_amount,
		"upper_layer_height": source.upper_layer_height,
		"upper_layer_scale": source.upper_layer_scale,
		"upper_layer_wind_multiplier": source.upper_layer_wind_multiplier,
		"distance_fade_start": source.distance_fade_start,
		"distance_fade_end": source.distance_fade_end,
		"distance_haze_strength": source.distance_haze_strength,
		"above_horizon_clouds_enabled": source.above_horizon_clouds_enabled,
		"below_horizon_clouds_enabled": source.below_horizon_clouds_enabled,
		"below_horizon_visibility": source.below_horizon_visibility,
		"below_horizon_fade_depth": source.below_horizon_fade_depth,
		"below_horizon_scale": source.below_horizon_scale,
		"below_horizon_detail": source.below_horizon_detail,
		"below_horizon_curvature": source.below_horizon_curvature,
		"below_horizon_haze_strength": source.below_horizon_haze_strength,
		"wind_direction": source.wind_direction,
		"wind_speed": source.wind_speed,
		"overcast_light_multiplier": source.overcast_light_multiplier,
		"overcast_ambient_multiplier": source.overcast_ambient_multiplier,
		"fog_density_multiplier": source.fog_density_multiplier,
		"saturation_multiplier": source.saturation_multiplier,
	}


func _blend_weather_states(from_state: Dictionary, to_state: Dictionary, weight: float) -> Dictionary:
	var result: Dictionary = {}
	var float_keys: Array[String] = [
		"cloud_coverage", "cloud_density", "cloud_softness", "cloud_scale", "cloud_detail",
		"cloud_light_absorption", "cloud_volume_depth", "cloud_optical_density", "cloud_core_shadow_strength",
		"cloud_edge_light_strength", "lower_layer_height", "upper_layer_amount", "upper_layer_height",
		"upper_layer_scale", "upper_layer_wind_multiplier", "distance_fade_start", "distance_fade_end",
		"distance_haze_strength", "below_horizon_visibility", "below_horizon_fade_depth",
		"below_horizon_scale", "below_horizon_detail", "below_horizon_curvature", "below_horizon_haze_strength",
		"wind_speed", "overcast_light_multiplier",
		"overcast_ambient_multiplier", "fog_density_multiplier", "saturation_multiplier"
	]
	for key: String in float_keys:
		result[key] = lerpf(float(from_state.get(key, to_state[key])), float(to_state[key]), weight)
	result["cloud_volume_steps"] = int(round(lerpf(
		float(from_state.get("cloud_volume_steps", to_state.get("cloud_volume_steps", 1))),
		float(to_state.get("cloud_volume_steps", 1)),
		weight
	)))
	var bool_keys: Array[String] = ["above_horizon_clouds_enabled", "below_horizon_clouds_enabled"]
	for key: String in bool_keys:
		var from_enabled: bool = from_state.get(key, to_state.get(key, true)) == true
		var to_enabled: bool = to_state.get(key, true) == true
		result[key] = from_enabled if weight < 0.5 else to_enabled
	var from_wind: Vector2 = from_state.get("wind_direction", to_state["wind_direction"])
	var to_wind: Vector2 = to_state["wind_direction"]
	result["wind_direction"] = from_wind.lerp(to_wind, weight)
	return result


func _register_with_graphics_settings() -> void:
	if not register_graphics_targets:
		return
	var settings_manager: Node = get_node_or_null("/root/SettingsManager")
	if settings_manager and settings_manager.has_method("register_graphics_targets"):
		settings_manager.call("register_graphics_targets", _world_environment, _sun_light)
		settings_manager.call("register_graphics_targets", null, _moon_light)


func _synchronize_time_transition(hour: float, duration: float, shortest_path: bool) -> bool:
	var controller: Node = get_parent()
	return not Engine.is_editor_hint() and controller and controller.has_method("synchronize_time_transition") and bool(controller.call("synchronize_time_transition", hour, duration, shortest_path))

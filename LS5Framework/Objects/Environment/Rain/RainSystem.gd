extends Node3D
class_name RainSystem

signal cover_exposure_changed(exposure: float)
signal cover_edge_distance_changed(distance: float)
signal profile_transition_finished(profile: RainProfile)
signal thunder_played(stream: AudioStream)

@export_group("Rain")
## Rain appearance and motion settings applied to both distance-detail layers.
@export var profile: RainProfile
## Enables rain emission while keeping the system ready for transitions.
@export var rain_enabled: bool = true
## Additional runtime multiplier for scripted intensity changes without modifying the profile resource.
@export_range(0.0, 1.0, 0.01) var intensity_multiplier: float = 1.0

@export_group("Camera Tracking")
## Camera followed by the local rain volume. Leave empty to use the viewport's active Camera3D.
@export_node_path("Camera3D") var camera_path: NodePath

@export_group("Cover Occlusion")
## Uses wind-aligned physics rays to measure how exposed the camera is to rain.
@export var cover_detection_enabled: bool = true
## Multiplies the entire visual rain volume by camera exposure. Leave disabled to preserve rain visible beyond nearby cover.
@export var cover_suppresses_visual_emission: bool = false
## Physics layers treated as rain-blocking cover by the wind-aligned probes.
@export_flags_3d_physics var cover_collision_mask: int = 1
## Allows Area3D nodes on the cover mask to block exposure probes.
@export var cover_collide_with_areas: bool = false
## Seconds between cover probe batches.
@export_range(0.02, 1.0, 0.01) var cover_check_interval_seconds: float = 0.1
## Odd number of probes per axis. Five creates a 5 by 5 grid.
@export_range(1, 5, 2) var cover_grid_size: int = 3
## Horizontal radius sampled around the camera for partial-cover detection.
@export_range(0.0, 30.0, 0.25) var cover_probe_radius: float = 4.0
## Additional far-rain radius and viewing distance used at complete shelter so rain beyond distant cover remains visible.
@export_range(0.0, 200.0, 0.5) var sheltered_far_range_extension: float = 90.0
## Height above the camera used as the lower endpoint of cover rays.
@export_range(0.0, 10.0, 0.1) var cover_probe_height: float = 1.0
## Extra wind-aligned ray length beyond the rain emission plane.
@export_range(0.0, 30.0, 0.5) var cover_ray_margin: float = 4.0
## Exposure values at or below this threshold report complete shelter.
@export_range(0.0, 0.9, 0.01) var full_cover_exposure_threshold: float = 0.12
## Speed at which measured exposure falls when moving beneath cover.
@export_range(0.1, 30.0, 0.1) var cover_fade_out_speed: float = 10.0
## Speed at which measured exposure rises after leaving cover.
@export_range(0.1, 30.0, 0.1) var cover_fade_in_speed: float = 3.5

@export_group("Particle Collision")
## Visual layers captured by the camera-following rain collision heightfield.
@export_flags_3d_render var collision_visual_mask: int = 1048575
## Enables geometry collision for detailed rain close to the camera.
@export var near_collision_enabled: bool = true
## Enables geometry collision for distant rain.
@export var far_collision_enabled: bool = true
## World-space size of the camera-following particle collision heightfield.
@export var collision_heightfield_size: Vector3 = Vector3(110.0, 70.0, 110.0)
## Heightfield resolution. Higher values preserve smaller roof and terrain details at greater cost.
@export_enum("256:0", "512:1", "1024:2", "2048:3") var collision_heightfield_resolution: int = 1
## Rebuilds particle collision every frame for moving level meshes. Leave disabled for static geometry.
@export var collision_update_always: bool = false
## Camera travel required before the heightfield recenters and rebuilds for static geometry.
@export_range(0.5, 30.0, 0.5) var collision_recenter_distance: float = 6.0

@export_group("Performance")
## Maximum detailed drop allocation. Runtime intensity uses Amount Ratio and does not restart particles.
@export_range(64, 4096, 1) var near_particle_capacity: int = 1100
## Maximum simplified distant drop allocation. Runtime intensity uses Amount Ratio and does not restart particles.
@export_range(64, 4096, 1) var far_particle_capacity: int = 1400
## Particle simulation frequency. Fast collision is more reliable at higher values.
@export_range(15, 120, 1) var particle_fixed_fps: int = 60

@export_group("Audio")
## Enables listener-centered rain ambience and cover filtering.
@export var audio_enabled: bool = true
## Rain loop filtered according to the camera's distance beneath cover.
@export var outdoor_rain_stream: AudioStream
## Dedicated audio bus containing the rain low-pass filter and routed through SFX.
@export var audio_bus: StringName = &"Rain"
## Additional volume applied after profile intensity and cover filtering.
@export_range(-40.0, 12.0, 0.1) var audio_volume_offset_db: float = 0.0
## Exponent applied to rain intensity before calculating audible volume.
@export_range(0.1, 4.0, 0.01) var audio_intensity_exponent: float = 0.65
## Maximum volume change per second for rain-loop fades.
@export_range(1.0, 120.0, 0.5) var audio_fade_speed_db_per_second: float = 36.0
## Volume treated as silent before inactive rain loops are stopped.
@export_range(-80.0, -20.0, 1.0) var audio_silence_db: float = -60.0

@export_group("Thunder")
## Enables profile-driven automatic and manually triggered thunder playback.
@export var thunder_audio_enabled: bool = true
## Loud thunder variations selected without immediate repetition.
@export var loud_thunder_streams: Array[AudioStream] = []
## Distant rumbling thunder variations selected without immediate repetition.
@export var rumbling_thunder_streams: Array[AudioStream] = []
## Additional volume applied to every thunder event.
@export_range(-40.0, 12.0, 0.1) var thunder_volume_offset_db: float = 0.0
## Minimum and maximum delay before the first automatic thunder event after activation.
@export var thunder_initial_delay_range_seconds: Vector2 = Vector2(4.0, 12.0)
## Fixed random seed for repeatable thunder timing. Zero generates a random seed during scene loading.
@export var thunder_random_seed: int = 0

@export_group("Cover Audio")
## Uses concentric wind-aligned probes to measure the nearest open-sky edge while sheltered.
@export var cover_edge_audio_enabled: bool = true
## Maximum horizontal distance searched for an open-sky cover edge.
@export_range(4.0, 200.0, 0.5) var cover_edge_probe_max_distance: float = 60.0
## Distance between concentric cover-edge probe rings.
@export_range(1.0, 20.0, 0.5) var cover_edge_probe_spacing: float = 5.0
## Number of evenly distributed directions sampled on each probe ring.
@export_range(4, 16, 1) var cover_edge_probe_directions: int = 8
## Speed at which the measured cover-edge distance changes in world units per second.
@export_range(1.0, 100.0, 0.5) var cover_edge_distance_smoothing_speed: float = 30.0
## Distance beneath cover that reaches the fully sheltered filter settings.
@export_range(1.0, 100.0, 0.5) var audio_full_filter_distance: float = 60.0
## Low-pass cutoff used in open rain or at the edge of cover.
@export_range(500.0, 20500.0, 10.0) var audio_exposed_cutoff_hz: float = 18000.0
## Low-pass cutoff used at or beyond the full-filter distance.
@export_range(200.0, 16000.0, 10.0) var audio_deep_cover_cutoff_hz: float = 1800.0
## Volume reduction applied at or beyond the full-filter distance.
@export_range(-24.0, 0.0, 0.1) var audio_deep_cover_attenuation_db: float = -4.0
## Shapes how quickly filtering increases with distance from the cover edge.
@export_range(0.1, 4.0, 0.01) var audio_cover_depth_exponent: float = 0.8

@export_group("Ambient Lighting")
## Modulates rain brightness using the active Environment ambient light.
@export var ambient_lighting_enabled: bool = true
## WorldEnvironment sampled for rain brightness. Leave empty to use the active World3D Environment.
@export_node_path("WorldEnvironment") var lighting_environment_path: NodePath
## Ambient luminance treated as full daytime rain brightness.
@export_range(0.01, 4.0, 0.01) var ambient_reference_luminance: float = 0.5
## Minimum rain brightness retained in very dark environments.
@export_range(0.0, 1.0, 0.01) var minimum_ambient_brightness: float = 0.08
## Maximum rain brightness produced by ambient lighting.
@export_range(0.0, 2.0, 0.01) var maximum_ambient_brightness: float = 1.0
## Shapes the response between night and daytime ambient light.
@export_range(0.1, 4.0, 0.01) var ambient_response_exponent: float = 0.75
## Additional multiplier applied after ambient-light adaptation.
@export_range(0.0, 2.0, 0.01) var rain_brightness_multiplier: float = 1.0
## Seconds between Environment lighting samples.
@export_range(0.02, 1.0, 0.01) var ambient_lighting_update_interval_seconds: float = 0.1
## Speed at which rain adapts to changing ambient light.
@export_range(0.1, 20.0, 0.1) var ambient_lighting_adaptation_speed: float = 3.0

@export_group("Scene References")
## Camera-following anchor containing both particle detail layers.
@export_node_path("Node3D") var emitter_anchor_path: NodePath = NodePath("EmitterAnchor")
## Detailed four-sided low-poly drop layer.
@export_node_path("GPUParticles3D") var near_particles_path: NodePath = NodePath("EmitterAnchor/NearRain")
## Simplified three-sided low-poly drop layer used at greater camera distances.
@export_node_path("GPUParticles3D") var far_particles_path: NodePath = NodePath("EmitterAnchor/FarRain")
## Camera-following heightfield that hides drops when they contact level geometry.
@export_node_path("GPUParticlesCollisionHeightField3D") var collision_heightfield_path: NodePath = NodePath("RainCollisionHeightfield")
## Listener-centered outdoor rain ambience player.
@export_node_path("AudioStreamPlayer") var outdoor_audio_player_path: NodePath = NodePath("OutdoorRainAudio")
## Listener-centered one-shot thunder player routed through the filtered Rain bus.
@export_node_path("AudioStreamPlayer") var thunder_audio_player_path: NodePath = NodePath("ThunderAudio")

var _camera: Camera3D
var _emitter_anchor: Node3D
var _near_particles: GPUParticles3D
var _far_particles: GPUParticles3D
var _collision_heightfield: GPUParticlesCollisionHeightField3D
var _near_process_material: ParticleProcessMaterial
var _far_process_material: ParticleProcessMaterial
var _near_mesh: PrimitiveMesh
var _far_mesh: PrimitiveMesh
var _near_draw_material: ShaderMaterial
var _far_draw_material: ShaderMaterial
var _outdoor_audio_player: AudioStreamPlayer
var _thunder_audio_player: AudioStreamPlayer
var _rain_low_pass_filter: AudioEffectLowPassFilter

var _current_state: Dictionary = {}
var _applied_profile: RainProfile
var _rain_direction: Vector3 = Vector3.DOWN
var _spawn_height: float = 30.0
var _cover_elapsed: float = 0.0
var _cover_target: float = 1.0
var _cover_exposure: float = 1.0
var _cover_edge_distance_target: float = 0.0
var _cover_edge_distance: float = 0.0
var _cover_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _collision_anchor_initialized: bool = false
var _ambient_lighting_elapsed: float = 0.0
var _lighting_target: float = 1.0
var _lighting_multiplier: float = 1.0
var _applied_far_cover_extension: float = -1.0
var _thunder_timer: float = -1.0
var _thunder_was_enabled: bool = false
var _last_thunder_stream: AudioStream
var _active_thunder_base_volume_db: float = -1.0
var _thunder_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _system_active: bool = true
var _global_particle_quality_multiplier: float = 1.0
var _global_weather_occlusion_enabled: bool = true

var _profile_transition_active: bool = false
var _profile_transition_from: Dictionary = {}
var _profile_transition_target: RainProfile
var _profile_transition_duration: float = 0.0
var _profile_transition_elapsed: float = 0.0


func _ready() -> void:
	add_to_group(&"rain_system")
	if thunder_random_seed == 0:
		_thunder_rng.randomize()
	else:
		_thunder_rng.seed = thunder_random_seed
	_resolve_nodes()
	_sync_global_graphics_settings()
	_configure_static_resources()
	_current_state = _sample_profile(profile)
	_apply_profile_state(_current_state)
	_update_ambient_lighting_target()
	_lighting_multiplier = _lighting_target
	_apply_lighting_multiplier()
	_update_camera()
	_update_emission()
	_update_audio(0.0)


func _process(delta: float) -> void:
	_update_camera()
	_update_ambient_lighting(delta)
	if _camera and _emitter_anchor:
		_emitter_anchor.global_transform = Transform3D(Basis.IDENTITY, _camera.global_position)
	_update_collision_anchor()
	_advance_profile_transition(delta)
	if not _profile_transition_active and profile != _applied_profile:
		_current_state = _sample_profile(profile)
		_apply_profile_state(_current_state)
	var cover_speed: float = cover_fade_in_speed if _cover_target > _cover_exposure else cover_fade_out_speed
	var previous_exposure: float = _cover_exposure
	_cover_exposure = move_toward(_cover_exposure, _cover_target, cover_speed * delta)
	if not is_equal_approx(previous_exposure, _cover_exposure):
		cover_exposure_changed.emit(_cover_exposure)
	var previous_edge_distance: float = _cover_edge_distance
	_cover_edge_distance = move_toward(
		_cover_edge_distance,
		_cover_edge_distance_target,
		cover_edge_distance_smoothing_speed * delta
	)
	if not is_equal_approx(previous_edge_distance, _cover_edge_distance):
		cover_edge_distance_changed.emit(_cover_edge_distance)
	_update_far_cover_visibility()
	_update_emission()
	_update_audio(delta)
	_update_thunder(delta)


func _physics_process(delta: float) -> void:
	if not _global_weather_occlusion_enabled:
		_cover_target = 1.0
		_cover_edge_distance_target = 0.0
		return
	_cover_elapsed += delta
	if _cover_elapsed < cover_check_interval_seconds:
		return
	_cover_elapsed = 0.0
	_update_cover_target()


func set_profile(target_profile: RainProfile) -> void:
	_profile_transition_active = false
	profile = target_profile
	_current_state = _sample_profile(profile)
	_apply_profile_state(_current_state)


func transition_to_profile(target_profile: RainProfile, duration_seconds: float) -> void:
	if not target_profile:
		return
	if duration_seconds <= 0.0:
		set_profile(target_profile)
		profile_transition_finished.emit(profile)
		return
	_profile_transition_from = _current_state.duplicate(true)
	_profile_transition_target = target_profile
	_profile_transition_duration = duration_seconds
	_profile_transition_elapsed = 0.0
	_profile_transition_active = true


func set_system_active(active: bool) -> void:
	_system_active = active
	visible = active
	set_process(active)
	set_physics_process(active)
	if active:
		_update_camera()
		_update_emission()
		_update_audio(0.0)
		return
	_set_particle_emission(_near_particles, 0.0)
	_set_particle_emission(_far_particles, 0.0)
	if _outdoor_audio_player:
		_outdoor_audio_player.stop()
	if _thunder_audio_player:
		_thunder_audio_player.stop()


func refresh_profile() -> void:
	_current_state = _sample_profile(profile)
	_apply_profile_state(_current_state)


func get_cover_exposure() -> float:
	return _cover_exposure


func get_cover_edge_distance() -> float:
	return _cover_edge_distance


func get_audio_cover_depth() -> float:
	if not _global_weather_occlusion_enabled or not cover_detection_enabled or not cover_edge_audio_enabled:
		return 0.0
	var normalized_distance: float = clampf(
		_cover_edge_distance / maxf(audio_full_filter_distance, 0.001),
		0.0,
		1.0
	)
	return float(pow(normalized_distance, audio_cover_depth_exponent))


func _resolve_nodes() -> void:
	_emitter_anchor = get_node_or_null(emitter_anchor_path) as Node3D
	_near_particles = get_node_or_null(near_particles_path) as GPUParticles3D
	_far_particles = get_node_or_null(far_particles_path) as GPUParticles3D
	_collision_heightfield = get_node_or_null(collision_heightfield_path) as GPUParticlesCollisionHeightField3D
	_outdoor_audio_player = get_node_or_null(outdoor_audio_player_path) as AudioStreamPlayer
	_thunder_audio_player = get_node_or_null(thunder_audio_player_path) as AudioStreamPlayer
	if _near_particles:
		_near_process_material = _near_particles.process_material as ParticleProcessMaterial
		_near_mesh = _near_particles.draw_pass_1 as PrimitiveMesh
		if _near_mesh:
			_near_draw_material = _near_mesh.material as ShaderMaterial
	if _far_particles:
		_far_process_material = _far_particles.process_material as ParticleProcessMaterial
		_far_mesh = _far_particles.draw_pass_1 as PrimitiveMesh
		if _far_mesh:
			_far_draw_material = _far_mesh.material as ShaderMaterial


func _sync_global_graphics_settings() -> void:
	var settings_manager: Node = get_node_or_null("/root/SettingsManager")
	if settings_manager == null:
		return
	var quality_multiplier: float = 1.0
	if settings_manager.has_method("get_particle_quality_multiplier"):
		quality_multiplier = float(settings_manager.call("get_particle_quality_multiplier"))
	var occlusion_enabled: bool = bool(settings_manager.get("weather_occlusion_enabled"))
	apply_global_graphics_settings(quality_multiplier, occlusion_enabled)


func apply_global_graphics_settings(particle_multiplier: float, occlusion_enabled: bool) -> void:
	_global_particle_quality_multiplier = clampf(particle_multiplier, 0.0, 1.0)
	_global_weather_occlusion_enabled = occlusion_enabled
	if _collision_heightfield:
		_collision_heightfield.visible = occlusion_enabled and (near_collision_enabled or far_collision_enabled)
		_collision_anchor_initialized = false
	if not occlusion_enabled:
		_cover_target = 1.0
		_cover_edge_distance_target = 0.0
	if not _current_state.is_empty():
		_apply_profile_state(_current_state)
		_update_emission()


func _configure_static_resources() -> void:
	if _near_particles:
		_near_particles.amount = maxi(near_particle_capacity, 1)
		_near_particles.fixed_fps = maxi(particle_fixed_fps, 1)
		_near_particles.interpolate = true
		_near_particles.fract_delta = true
	if _far_particles:
		_far_particles.amount = maxi(far_particle_capacity, 1)
		_far_particles.fixed_fps = maxi(particle_fixed_fps, 1)
		_far_particles.interpolate = true
		_far_particles.fract_delta = true
	if _collision_heightfield:
		_collision_heightfield.visible = _global_weather_occlusion_enabled and (near_collision_enabled or far_collision_enabled)
		_collision_heightfield.heightfield_mask = collision_visual_mask
		_collision_heightfield.size = collision_heightfield_size
		_collision_heightfield.resolution = collision_heightfield_resolution
		_collision_heightfield.update_mode = (
			GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
			if collision_update_always
			else GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
		)
		_collision_heightfield.follow_camera_enabled = false
	_configure_audio_player(_outdoor_audio_player, outdoor_rain_stream)
	_configure_audio_player(_thunder_audio_player, null)
	_resolve_rain_low_pass_filter()
	_cover_query.collision_mask = cover_collision_mask
	_cover_query.collide_with_bodies = true
	_cover_query.collide_with_areas = cover_collide_with_areas
	_cover_query.hit_from_inside = true


func _configure_audio_player(player: AudioStreamPlayer, configured_stream: AudioStream) -> void:
	if not player:
		return
	if configured_stream:
		player.stream = configured_stream
	player.bus = audio_bus
	player.volume_db = audio_silence_db


func _resolve_rain_low_pass_filter() -> void:
	_rain_low_pass_filter = null
	var bus_index: int = AudioServer.get_bus_index(audio_bus)
	if bus_index < 0:
		push_warning("RainSystem: Audio bus '%s' was not found." % audio_bus)
		return
	var effect_count: int = AudioServer.get_bus_effect_count(bus_index)
	for effect_index: int in range(effect_count):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus_index, effect_index)
		if effect is AudioEffectLowPassFilter:
			_rain_low_pass_filter = effect as AudioEffectLowPassFilter
			return
	push_warning("RainSystem: Audio bus '%s' has no low-pass filter." % audio_bus)


func _update_camera() -> void:
	if not camera_path.is_empty():
		if not is_instance_valid(_camera):
			_camera = get_node_or_null(camera_path) as Camera3D
		return
	_camera = get_viewport().get_camera_3d()


func _update_ambient_lighting(delta: float) -> void:
	_ambient_lighting_elapsed += delta
	if _ambient_lighting_elapsed >= ambient_lighting_update_interval_seconds:
		_ambient_lighting_elapsed = 0.0
		_update_ambient_lighting_target()
	var previous_multiplier: float = _lighting_multiplier
	_lighting_multiplier = move_toward(
		_lighting_multiplier,
		_lighting_target,
		ambient_lighting_adaptation_speed * delta
	)
	if not is_equal_approx(previous_multiplier, _lighting_multiplier):
		_apply_lighting_multiplier()


func _update_ambient_lighting_target() -> void:
	if not ambient_lighting_enabled:
		_lighting_target = rain_brightness_multiplier
		return
	var environment: Environment = _resolve_lighting_environment()
	if not environment:
		_lighting_target = rain_brightness_multiplier
		return
	var ambient_color: Color = environment.ambient_light_color
	var color_luminance: float = (
		ambient_color.r * 0.2126
		+ ambient_color.g * 0.7152
		+ ambient_color.b * 0.0722
	)
	var measured_luminance: float = maxf(color_luminance * environment.ambient_light_energy, 0.0)
	var normalized_luminance: float = clampf(
		measured_luminance / maxf(ambient_reference_luminance, 0.001),
		0.0,
		1.0
	)
	var response: float = float(pow(normalized_luminance, ambient_response_exponent))
	var minimum_brightness: float = minf(minimum_ambient_brightness, maximum_ambient_brightness)
	var maximum_brightness: float = maxf(minimum_ambient_brightness, maximum_ambient_brightness)
	_lighting_target = lerpf(minimum_brightness, maximum_brightness, response) * rain_brightness_multiplier


func _resolve_lighting_environment() -> Environment:
	if not lighting_environment_path.is_empty():
		var world_environment: WorldEnvironment = get_node_or_null(lighting_environment_path) as WorldEnvironment
		if world_environment and world_environment.environment:
			return world_environment.environment
	var world: World3D = get_world_3d()
	if world:
		return world.environment
	return null


func _apply_lighting_multiplier() -> void:
	if _near_draw_material:
		_near_draw_material.set_shader_parameter("lighting_multiplier", _lighting_multiplier)
	if _far_draw_material:
		_far_draw_material.set_shader_parameter("lighting_multiplier", _lighting_multiplier)


func _update_collision_anchor() -> void:
	if not _global_weather_occlusion_enabled or not _camera or not _collision_heightfield:
		return
	var camera_position: Vector3 = _camera.global_position
	var travel_distance: float = _collision_heightfield.global_position.distance_to(camera_position)
	if collision_update_always or not _collision_anchor_initialized or travel_distance >= collision_recenter_distance:
		_collision_heightfield.global_transform = Transform3D(Basis.IDENTITY, camera_position)
		_collision_anchor_initialized = true


func _advance_profile_transition(delta: float) -> void:
	if not _profile_transition_active or not _profile_transition_target:
		return
	_profile_transition_elapsed = minf(_profile_transition_elapsed + delta, _profile_transition_duration)
	var weight: float = smoothstep(0.0, 1.0, _profile_transition_elapsed / _profile_transition_duration)
	var target_state: Dictionary = _sample_profile(_profile_transition_target)
	_current_state = _blend_profile_states(_profile_transition_from, target_state, weight)
	_apply_profile_state(_current_state)
	if _profile_transition_elapsed >= _profile_transition_duration:
		profile = _profile_transition_target
		_profile_transition_active = false
		_applied_profile = profile
		profile_transition_finished.emit(profile)


func _apply_profile_state(state: Dictionary) -> void:
	_applied_profile = profile if not _profile_transition_active else null
	var fall_speed: float = maxf(float(state["fall_speed"]), 0.1)
	var wind_velocity: Vector2 = state["wind_velocity"]
	var velocity: Vector3 = Vector3(wind_velocity.x, -fall_speed, wind_velocity.y)
	var velocity_magnitude: float = maxf(velocity.length(), 0.1)
	_rain_direction = velocity / velocity_magnitude
	_spawn_height = maxf(float(state["spawn_height"]), 1.0)
	var fall_time: float = _spawn_height / fall_speed
	var lifetime: float = fall_time * (1.0 + maxf(float(state["lifetime_margin"]), 0.0))
	var source_shift: Vector3 = Vector3(-wind_velocity.x * fall_time, 0.0, -wind_velocity.y * fall_time)
	var emitter_position: Vector3 = source_shift + Vector3.UP * _spawn_height
	var speed_randomness: float = clampf(float(state["velocity_randomness"]), 0.0, 0.95)
	var minimum_speed: float = velocity_magnitude * (1.0 - speed_randomness)
	var maximum_speed: float = velocity_magnitude * (1.0 + speed_randomness)
	_configure_particle_layer(
		_near_particles,
		_near_process_material,
		emitter_position,
		float(state["near_radius"]),
		lifetime,
		minimum_speed,
		maximum_speed,
		float(state["direction_spread_degrees"]),
		float(state["near_scale_min"]),
		float(state["near_scale_max"]),
		near_collision_enabled and _global_weather_occlusion_enabled
	)
	_configure_particle_layer(
		_far_particles,
		_far_process_material,
		emitter_position,
		float(state["far_radius"]),
		lifetime,
		minimum_speed,
		maximum_speed,
		float(state["direction_spread_degrees"]),
		float(state["far_scale_min"]),
		float(state["far_scale_max"]),
		far_collision_enabled and _global_weather_occlusion_enabled
	)
	_configure_draw_material(
		_near_draw_material,
		state["tint"],
		state["near_drop_size"],
		float(state["edge_highlight_strength"]),
		float(state["emission_strength"]),
		float(state["tip_softness"]),
		0.0,
		0.01,
		float(state["near_fade_out_start"]),
		float(state["near_fade_out_end"])
	)
	_configure_draw_material(
		_far_draw_material,
		state["tint"],
		state["far_drop_size"],
		float(state["edge_highlight_strength"]),
		float(state["emission_strength"]),
		float(state["tip_softness"]),
		float(state["far_fade_in_start"]),
		float(state["far_fade_in_end"]),
		float(state["far_fade_out_start"]),
		float(state["far_fade_out_end"])
	)
	_update_far_cover_visibility(true)


func _configure_particle_layer(
	particles: GPUParticles3D,
	process_material: ParticleProcessMaterial,
	emitter_position: Vector3,
	radius: float,
	lifetime: float,
	minimum_speed: float,
	maximum_speed: float,
	spread_degrees: float,
	scale_minimum: float,
	scale_maximum: float,
	collision_enabled: bool
) -> void:
	if not particles or not process_material:
		return
	var safe_radius: float = maxf(radius, 1.0)
	particles.position = emitter_position
	particles.lifetime = maxf(lifetime, 0.1)
	var horizontal_travel: float = Vector2(emitter_position.x, emitter_position.z).length()
	var horizontal_extent: float = safe_radius + horizontal_travel + 5.0
	var vertical_extent: float = _spawn_height * (1.0 + float(_current_state.get("lifetime_margin", 0.28))) + 8.0
	particles.visibility_aabb = AABB(
		Vector3(-horizontal_extent, -vertical_extent, -horizontal_extent),
		Vector3(horizontal_extent * 2.0, vertical_extent + 12.0, horizontal_extent * 2.0)
	)
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(safe_radius, 0.1, safe_radius)
	process_material.direction = _rain_direction
	process_material.spread = clampf(spread_degrees, 0.0, 89.0)
	process_material.initial_velocity_min = maxf(minimum_speed, 0.1)
	process_material.initial_velocity_max = maxf(maximum_speed, minimum_speed)
	process_material.gravity = Vector3.ZERO
	process_material.scale_min = maxf(minf(scale_minimum, scale_maximum), 0.01)
	process_material.scale_max = maxf(maxf(scale_minimum, scale_maximum), 0.01)
	process_material.collision_mode = (
		ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
		if collision_enabled
		else ParticleProcessMaterial.COLLISION_DISABLED
	)


func _configure_draw_material(
	draw_material: ShaderMaterial,
	tint: Color,
	drop_size: Vector2,
	edge_highlight_strength: float,
	emission_strength: float,
	tip_softness: float,
	fade_in_start: float,
	fade_in_end: float,
	fade_out_start: float,
	fade_out_end: float
) -> void:
	if not draw_material:
		return
	draw_material.set_shader_parameter("rain_tint", tint)
	draw_material.set_shader_parameter("drop_diameter", maxf(drop_size.x, 0.001))
	draw_material.set_shader_parameter("drop_length", maxf(drop_size.y, 0.05))
	draw_material.set_shader_parameter("edge_highlight_strength", maxf(edge_highlight_strength, 0.0))
	draw_material.set_shader_parameter("emission_strength", maxf(emission_strength, 0.0))
	draw_material.set_shader_parameter("lighting_multiplier", _lighting_multiplier)
	draw_material.set_shader_parameter("tip_softness", clampf(tip_softness, 0.01, 0.49))
	draw_material.set_shader_parameter("fade_in_start", fade_in_start)
	draw_material.set_shader_parameter("fade_in_end", fade_in_end)
	draw_material.set_shader_parameter("fade_out_start", fade_out_start)
	draw_material.set_shader_parameter("fade_out_end", fade_out_end)


func _update_far_cover_visibility(force_update: bool = false) -> void:
	if not _far_particles or _current_state.is_empty():
		return
	var shelter: float = 1.0 - clampf(_cover_exposure, 0.0, 1.0) if _global_weather_occlusion_enabled and cover_detection_enabled else 0.0
	var range_extension: float = maxf(sheltered_far_range_extension, 0.0) * shelter
	if not force_update and is_equal_approx(range_extension, _applied_far_cover_extension):
		return
	_applied_far_cover_extension = range_extension
	var base_far_radius: float = maxf(float(_current_state.get("far_radius", 48.0)), 1.0)
	var effective_far_radius: float = base_far_radius + range_extension
	if _far_process_material:
		_far_process_material.emission_box_extents = Vector3(
			effective_far_radius,
			0.1,
			effective_far_radius
		)
	var horizontal_travel: float = Vector2(_far_particles.position.x, _far_particles.position.z).length()
	var horizontal_extent: float = effective_far_radius + horizontal_travel + 5.0
	var lifetime_margin: float = float(_current_state.get("lifetime_margin", 0.28))
	var vertical_extent: float = _spawn_height * (1.0 + lifetime_margin) + 8.0
	_far_particles.visibility_aabb = AABB(
		Vector3(-horizontal_extent, -vertical_extent, -horizontal_extent),
		Vector3(horizontal_extent * 2.0, vertical_extent + 12.0, horizontal_extent * 2.0)
	)
	if _far_draw_material:
		var base_fade_out_start: float = float(_current_state.get("far_fade_out_start", 200.0))
		var base_fade_out_end: float = float(_current_state.get("far_fade_out_end", 240.0))
		_far_draw_material.set_shader_parameter("fade_out_start", base_fade_out_start + range_extension * 0.72)
		_far_draw_material.set_shader_parameter("fade_out_end", base_fade_out_end + range_extension)
	if _global_weather_occlusion_enabled and _collision_heightfield:
		var collision_radius: float = effective_far_radius
		if not far_collision_enabled:
			collision_radius = float(_current_state.get("near_radius", 15.0))
		var required_horizontal_size: float = (collision_radius + horizontal_travel + 5.0) * 2.0
		var required_vertical_size: float = _spawn_height * 2.0 + 10.0
		_collision_heightfield.size = Vector3(
			maxf(collision_heightfield_size.x, required_horizontal_size),
			maxf(collision_heightfield_size.y, required_vertical_size),
			maxf(collision_heightfield_size.z, required_horizontal_size)
		)


func _update_cover_target() -> void:
	if not _global_weather_occlusion_enabled or not cover_detection_enabled:
		_cover_target = 1.0
		_cover_edge_distance_target = 0.0
		return
	if not _camera or not is_inside_tree():
		_cover_target = 0.0
		_cover_edge_distance_target = 0.0
		return
	var world: World3D = get_world_3d()
	if not world:
		_cover_target = 0.0
		_cover_edge_distance_target = 0.0
		return
	_cover_query.collision_mask = cover_collision_mask
	_cover_query.collide_with_areas = cover_collide_with_areas
	var grid_size: int = clampi(cover_grid_size, 1, 5)
	if grid_size % 2 == 0:
		grid_size = mini(grid_size + 1, 5)
	var center_index: int = grid_size / 2
	var blocked_count: int = 0
	var probe_count: int = grid_size * grid_size
	var center_blocked: bool = false
	var vertical_distance: float = maxf(_spawn_height - cover_probe_height, 1.0)
	var ray_length: float = vertical_distance / maxf(-_rain_direction.y, 0.05) + cover_ray_margin
	for grid_x: int in range(grid_size):
		var x_weight: float = 0.5 if grid_size == 1 else float(grid_x) / float(grid_size - 1)
		var offset_x: float = lerpf(-cover_probe_radius, cover_probe_radius, x_weight)
		for grid_z: int in range(grid_size):
			var z_weight: float = 0.5 if grid_size == 1 else float(grid_z) / float(grid_size - 1)
			var offset_z: float = lerpf(-cover_probe_radius, cover_probe_radius, z_weight)
			var horizontal_offset: Vector3 = Vector3(offset_x, 0.0, offset_z)
			if _is_cover_probe_blocked(world, horizontal_offset, ray_length):
				blocked_count += 1
				if grid_x == center_index and grid_z == center_index:
					center_blocked = true
	if center_blocked:
		_cover_target = 0.0
		_cover_edge_distance_target = _measure_nearest_cover_edge_distance(world, ray_length)
		return
	_cover_edge_distance_target = 0.0
	var exposure: float = 1.0 - float(blocked_count) / float(maxi(probe_count, 1))
	if exposure <= full_cover_exposure_threshold:
		_cover_target = 0.0
	else:
		_cover_target = inverse_lerp(full_cover_exposure_threshold, 1.0, exposure)


func _measure_nearest_cover_edge_distance(world: World3D, ray_length: float) -> float:
	if not cover_edge_audio_enabled:
		return 0.0
	var maximum_distance: float = maxf(cover_edge_probe_max_distance, 1.0)
	var spacing: float = clampf(cover_edge_probe_spacing, 0.5, maximum_distance)
	var direction_count: int = clampi(cover_edge_probe_directions, 4, 16)
	var ring_count: int = maxi(ceili(maximum_distance / spacing), 1)
	for ring_index: int in range(1, ring_count + 1):
		var distance: float = minf(float(ring_index) * spacing, maximum_distance)
		for direction_index: int in range(direction_count):
			var angle: float = TAU * float(direction_index) / float(direction_count)
			var direction: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
			var horizontal_offset: Vector3 = direction * distance
			if _is_cover_probe_blocked(world, horizontal_offset, ray_length):
				continue
			var blocked_distance: float = maxf(distance - spacing, 0.0)
			var open_distance: float = distance
			for _refinement_index: int in range(3):
				var test_distance: float = (blocked_distance + open_distance) * 0.5
				if _is_cover_probe_blocked(world, direction * test_distance, ray_length):
					blocked_distance = test_distance
				else:
					open_distance = test_distance
			return open_distance
	return maximum_distance


func _is_cover_probe_blocked(world: World3D, horizontal_offset: Vector3, ray_length: float) -> bool:
	var ray_origin: Vector3 = (
		_camera.global_position
		+ horizontal_offset
		+ Vector3.UP * cover_probe_height
	)
	_cover_query.from = ray_origin
	_cover_query.to = ray_origin - _rain_direction * ray_length
	var hit: Dictionary = world.direct_space_state.intersect_ray(_cover_query)
	return not hit.is_empty()


func _update_emission() -> void:
	var intensity: float = float(_current_state.get("intensity", 0.0))
	var exposure_multiplier: float = _cover_exposure if cover_suppresses_visual_emission else 1.0
	var emission_ratio: float = clampf(intensity * intensity_multiplier * exposure_multiplier, 0.0, 1.0)
	emission_ratio *= _global_particle_quality_multiplier
	if not rain_enabled:
		emission_ratio = 0.0
	_set_particle_emission(_near_particles, emission_ratio)
	_set_particle_emission(_far_particles, emission_ratio)


func _update_audio(delta: float) -> void:
	var intensity: float = clampf(
		float(_current_state.get("intensity", 0.0)) * intensity_multiplier,
		0.0,
		1.0
	)
	if not rain_enabled or not audio_enabled:
		intensity = 0.0
	var intensity_gain: float = float(pow(intensity, audio_intensity_exponent))
	var cover_depth: float = get_audio_cover_depth()
	var profile_volume_db: float = float(_current_state.get("audio_volume_db", -3.0))
	var pitch_scale: float = maxf(float(_current_state.get("audio_pitch_scale", 1.0)), 0.01)
	if _outdoor_audio_player:
		_outdoor_audio_player.pitch_scale = pitch_scale
	var cover_attenuation_db: float = lerpf(0.0, audio_deep_cover_attenuation_db, cover_depth)
	var target_volume_db: float = _calculate_audio_target_db(
		intensity_gain,
		profile_volume_db + audio_volume_offset_db + cover_attenuation_db
	)
	_update_rain_low_pass_filter(cover_depth)
	var should_play: bool = intensity_gain > 0.0001
	_update_audio_player(_outdoor_audio_player, target_volume_db, should_play, delta)


func _update_rain_low_pass_filter(cover_depth: float) -> void:
	if not _rain_low_pass_filter:
		return
	var exposed_cutoff: float = clampf(audio_exposed_cutoff_hz, 20.0, 20500.0)
	var sheltered_cutoff: float = clampf(audio_deep_cover_cutoff_hz, 20.0, 20500.0)
	var logarithmic_cutoff: float = exp(
		lerpf(log(exposed_cutoff), log(sheltered_cutoff), clampf(cover_depth, 0.0, 1.0))
	)
	_rain_low_pass_filter.cutoff_hz = logarithmic_cutoff


func _update_thunder(delta: float) -> void:
	_update_active_thunder_cover_mix()
	var thunder_enabled_value: Variant = _current_state.get("thunder_enabled", false)
	var profile_thunder_enabled: bool = false
	if thunder_enabled_value == true:
		profile_thunder_enabled = true
	var automatic_thunder_enabled: bool = (
		audio_enabled
		and thunder_audio_enabled
		and profile_thunder_enabled
	)
	if not automatic_thunder_enabled:
		_thunder_timer = -1.0
		_thunder_was_enabled = false
		return
	if not _thunder_was_enabled:
		_thunder_was_enabled = true
		_schedule_next_thunder(true)
	_thunder_timer -= delta
	if _thunder_timer > 0.0:
		return
	if _thunder_audio_player and _thunder_audio_player.playing:
		_thunder_timer = 1.0
		return
	_play_random_thunder()
	_schedule_next_thunder(false)


func trigger_random_thunder() -> void:
	if not audio_enabled or not thunder_audio_enabled:
		return
	_play_random_thunder()
	_schedule_next_thunder(false)


func trigger_loud_thunder() -> void:
	if not audio_enabled or not thunder_audio_enabled:
		return
	_play_thunder_from_collection(loud_thunder_streams, rumbling_thunder_streams)
	_schedule_next_thunder(false)


func trigger_rumbling_thunder() -> void:
	if not audio_enabled or not thunder_audio_enabled:
		return
	_play_thunder_from_collection(rumbling_thunder_streams, loud_thunder_streams)
	_schedule_next_thunder(false)


func _schedule_next_thunder(use_initial_delay: bool) -> void:
	var minimum_delay: float = 0.0
	var maximum_delay: float = 0.0
	if use_initial_delay:
		minimum_delay = maxf(
			minf(thunder_initial_delay_range_seconds.x, thunder_initial_delay_range_seconds.y),
			0.0
		)
		maximum_delay = maxf(
			maxf(thunder_initial_delay_range_seconds.x, thunder_initial_delay_range_seconds.y),
			minimum_delay
		)
	else:
		var profile_minimum: float = float(_current_state.get("thunder_interval_min_seconds", 12.0))
		var profile_maximum: float = float(_current_state.get("thunder_interval_max_seconds", 30.0))
		minimum_delay = maxf(minf(profile_minimum, profile_maximum), 0.1)
		maximum_delay = maxf(maxf(profile_minimum, profile_maximum), minimum_delay)
	_thunder_timer = _thunder_rng.randf_range(minimum_delay, maximum_delay)


func _play_random_thunder() -> void:
	var loud_probability: float = clampf(
		float(_current_state.get("thunder_loud_probability", 0.55)),
		0.0,
		1.0
	)
	if _thunder_rng.randf() <= loud_probability:
		_play_thunder_from_collection(loud_thunder_streams, rumbling_thunder_streams)
	else:
		_play_thunder_from_collection(rumbling_thunder_streams, loud_thunder_streams)


func _play_thunder_from_collection(
	preferred_streams: Array[AudioStream],
	fallback_streams: Array[AudioStream]
) -> void:
	if not _thunder_audio_player:
		return
	var streams: Array[AudioStream] = preferred_streams
	if streams.is_empty():
		streams = fallback_streams
	if streams.is_empty():
		return
	var stream_index: int = _thunder_rng.randi_range(0, streams.size() - 1)
	if streams.size() > 1 and streams[stream_index] == _last_thunder_stream:
		stream_index = (stream_index + _thunder_rng.randi_range(1, streams.size() - 1)) % streams.size()
	var selected_stream: AudioStream = streams[stream_index]
	if not selected_stream:
		return
	_last_thunder_stream = selected_stream
	var minimum_pitch: float = float(_current_state.get("thunder_pitch_min", 0.92))
	var maximum_pitch: float = float(_current_state.get("thunder_pitch_max", 1.06))
	var pitch_lower_bound: float = maxf(minf(minimum_pitch, maximum_pitch), 0.01)
	var pitch_upper_bound: float = maxf(maxf(minimum_pitch, maximum_pitch), pitch_lower_bound)
	_active_thunder_base_volume_db = (
		float(_current_state.get("thunder_volume_db", -1.0))
		+ thunder_volume_offset_db
	)
	_thunder_audio_player.stop()
	_thunder_audio_player.stream = selected_stream
	_thunder_audio_player.pitch_scale = _thunder_rng.randf_range(pitch_lower_bound, pitch_upper_bound)
	_update_active_thunder_cover_mix()
	_thunder_audio_player.play()
	thunder_played.emit(selected_stream)


func _update_active_thunder_cover_mix() -> void:
	if not _thunder_audio_player:
		return
	var cover_attenuation_db: float = lerpf(
		0.0,
		audio_deep_cover_attenuation_db,
		get_audio_cover_depth()
	)
	_thunder_audio_player.volume_db = _active_thunder_base_volume_db + cover_attenuation_db


func _calculate_audio_target_db(gain: float, maximum_volume_db: float) -> float:
	if gain <= 0.0001:
		return audio_silence_db
	return maxf(audio_silence_db, maximum_volume_db + linear_to_db(gain))


func _update_audio_player(
	player: AudioStreamPlayer,
	target_volume_db: float,
	should_play: bool,
	delta: float
) -> void:
	if not player or not player.stream:
		return
	if should_play and not player.playing:
		player.play()
	var volume_step: float = audio_fade_speed_db_per_second * delta
	player.volume_db = move_toward(player.volume_db, target_volume_db, volume_step)
	if not should_play and player.playing and player.volume_db <= audio_silence_db + 0.1:
		player.stop()


func _set_particle_emission(particles: GPUParticles3D, emission_ratio: float) -> void:
	if not particles:
		return
	particles.amount_ratio = emission_ratio
	particles.emitting = emission_ratio > 0.001


func _sample_profile(source: RainProfile) -> Dictionary:
	if not source:
		return {
			"intensity": 0.0,
			"tint": Color(0.72, 0.82, 0.92, 0.58),
			"edge_highlight_strength": 0.65,
			"emission_strength": 0.18,
			"tip_softness": 0.16,
			"fall_speed": 32.0,
			"wind_velocity": Vector2.ZERO,
			"velocity_randomness": 0.12,
			"direction_spread_degrees": 1.8,
			"audio_volume_db": -3.0,
			"audio_pitch_scale": 1.0,
			"thunder_enabled": false,
			"thunder_interval_min_seconds": 12.0,
			"thunder_interval_max_seconds": 30.0,
			"thunder_loud_probability": 0.55,
			"thunder_volume_db": -1.0,
			"thunder_pitch_min": 0.92,
			"thunder_pitch_max": 1.06,
			"spawn_height": 30.0,
			"near_radius": 15.0,
			"far_radius": 48.0,
			"lifetime_margin": 0.28,
			"near_drop_size": Vector2(0.02, 1.25),
			"near_scale_min": 0.65,
			"near_scale_max": 1.35,
			"near_fade_out_start": 12.0,
			"near_fade_out_end": 23.0,
			"far_drop_size": Vector2(0.027, 2.0),
			"far_scale_min": 0.75,
			"far_scale_max": 1.3,
			"far_fade_in_start": 12.0,
			"far_fade_in_end": 20.0,
			"far_fade_out_start": 200.0,
			"far_fade_out_end": 240.0,
		}
	var edge_highlight_value: Variant = source.get("edge_highlight_strength")
	var sampled_edge_highlight_strength: float = 0.65
	if edge_highlight_value != null:
		sampled_edge_highlight_strength = float(edge_highlight_value)
	var emission_value: Variant = source.get("emission_strength")
	var sampled_emission_strength: float = 0.18
	if emission_value != null:
		sampled_emission_strength = float(emission_value)
	var tip_softness_value: Variant = source.get("tip_softness")
	var sampled_tip_softness: float = 0.16
	if tip_softness_value != null:
		sampled_tip_softness = float(tip_softness_value)
	var far_drop_size_value: Variant = source.get("far_drop_size")
	var sampled_far_drop_size: Vector2 = Vector2(0.027, 2.0)
	if far_drop_size_value is Vector2:
		sampled_far_drop_size = far_drop_size_value
	var audio_volume_value: Variant = source.get("audio_volume_db")
	var sampled_audio_volume_db: float = -3.0
	if audio_volume_value != null:
		sampled_audio_volume_db = float(audio_volume_value)
	var audio_pitch_value: Variant = source.get("audio_pitch_scale")
	var sampled_audio_pitch_scale: float = 1.0
	if audio_pitch_value != null:
		sampled_audio_pitch_scale = float(audio_pitch_value)
	var thunder_enabled_value: Variant = source.get("thunder_enabled")
	var sampled_thunder_enabled: bool = false
	if thunder_enabled_value == true:
		sampled_thunder_enabled = true
	var thunder_interval_min_value: Variant = source.get("thunder_interval_min_seconds")
	var sampled_thunder_interval_min: float = 12.0
	if thunder_interval_min_value != null:
		sampled_thunder_interval_min = float(thunder_interval_min_value)
	var thunder_interval_max_value: Variant = source.get("thunder_interval_max_seconds")
	var sampled_thunder_interval_max: float = 30.0
	if thunder_interval_max_value != null:
		sampled_thunder_interval_max = float(thunder_interval_max_value)
	var thunder_loud_probability_value: Variant = source.get("thunder_loud_probability")
	var sampled_thunder_loud_probability: float = 0.55
	if thunder_loud_probability_value != null:
		sampled_thunder_loud_probability = float(thunder_loud_probability_value)
	var thunder_volume_value: Variant = source.get("thunder_volume_db")
	var sampled_thunder_volume_db: float = -1.0
	if thunder_volume_value != null:
		sampled_thunder_volume_db = float(thunder_volume_value)
	var thunder_pitch_min_value: Variant = source.get("thunder_pitch_min")
	var sampled_thunder_pitch_min: float = 0.92
	if thunder_pitch_min_value != null:
		sampled_thunder_pitch_min = float(thunder_pitch_min_value)
	var thunder_pitch_max_value: Variant = source.get("thunder_pitch_max")
	var sampled_thunder_pitch_max: float = 1.06
	if thunder_pitch_max_value != null:
		sampled_thunder_pitch_max = float(thunder_pitch_max_value)
	return {
		"intensity": source.intensity,
		"tint": source.tint,
		"edge_highlight_strength": sampled_edge_highlight_strength,
		"emission_strength": sampled_emission_strength,
		"tip_softness": sampled_tip_softness,
		"fall_speed": source.fall_speed,
		"wind_velocity": source.wind_velocity,
		"velocity_randomness": source.velocity_randomness,
		"direction_spread_degrees": source.direction_spread_degrees,
		"audio_volume_db": sampled_audio_volume_db,
		"audio_pitch_scale": sampled_audio_pitch_scale,
		"thunder_enabled": sampled_thunder_enabled,
		"thunder_interval_min_seconds": sampled_thunder_interval_min,
		"thunder_interval_max_seconds": sampled_thunder_interval_max,
		"thunder_loud_probability": sampled_thunder_loud_probability,
		"thunder_volume_db": sampled_thunder_volume_db,
		"thunder_pitch_min": sampled_thunder_pitch_min,
		"thunder_pitch_max": sampled_thunder_pitch_max,
		"spawn_height": source.spawn_height,
		"near_radius": source.near_radius,
		"far_radius": source.far_radius,
		"lifetime_margin": source.lifetime_margin,
		"near_drop_size": source.near_drop_size,
		"near_scale_min": source.near_scale_min,
		"near_scale_max": source.near_scale_max,
		"near_fade_out_start": source.near_fade_out_start,
		"near_fade_out_end": source.near_fade_out_end,
		"far_drop_size": sampled_far_drop_size,
		"far_scale_min": source.far_scale_min,
		"far_scale_max": source.far_scale_max,
		"far_fade_in_start": source.far_fade_in_start,
		"far_fade_in_end": source.far_fade_in_end,
		"far_fade_out_start": source.far_fade_out_start,
		"far_fade_out_end": source.far_fade_out_end,
	}


func _blend_profile_states(from_state: Dictionary, to_state: Dictionary, weight: float) -> Dictionary:
	var result: Dictionary = {}
	var float_keys: Array[String] = [
		"intensity", "edge_highlight_strength", "emission_strength", "tip_softness",
		"fall_speed", "velocity_randomness", "direction_spread_degrees", "audio_volume_db",
		"audio_pitch_scale", "thunder_interval_min_seconds", "thunder_interval_max_seconds",
		"thunder_loud_probability", "thunder_volume_db", "thunder_pitch_min", "thunder_pitch_max",
		"spawn_height", "near_radius", "far_radius", "lifetime_margin", "near_scale_min",
		"near_scale_max", "near_fade_out_start", "near_fade_out_end", "far_scale_min",
		"far_scale_max", "far_fade_in_start", "far_fade_in_end", "far_fade_out_start",
		"far_fade_out_end"
	]
	for key: String in float_keys:
		result[key] = lerpf(float(from_state.get(key, to_state[key])), float(to_state[key]), weight)
	result["thunder_enabled"] = (
		to_state.get("thunder_enabled", false)
		if weight >= 0.5
		else from_state.get("thunder_enabled", false)
	)
	var from_tint: Color = from_state.get("tint", to_state["tint"])
	var to_tint: Color = to_state["tint"]
	result["tint"] = from_tint.lerp(to_tint, weight)
	var from_wind: Vector2 = from_state.get("wind_velocity", to_state["wind_velocity"])
	var to_wind: Vector2 = to_state["wind_velocity"]
	result["wind_velocity"] = from_wind.lerp(to_wind, weight)
	var from_near_size: Vector2 = from_state.get("near_drop_size", to_state["near_drop_size"])
	var to_near_size: Vector2 = to_state["near_drop_size"]
	result["near_drop_size"] = from_near_size.lerp(to_near_size, weight)
	var from_far_size: Vector2 = from_state.get("far_drop_size", to_state["far_drop_size"])
	var to_far_size: Vector2 = to_state["far_drop_size"]
	result["far_drop_size"] = from_far_size.lerp(to_far_size, weight)
	return result

@tool
extends WorldObject
class_name Ring

const LIGHTSPEED_GROUP: StringName = &"LightSpeedDashRing"
const RIVAL_SEARCH_GROUP: StringName = &"RivalRingSearch"
const SIZE_BASE_POSITION_META: StringName = &"_uniform_size_base_position"
const SIZE_BASE_SCALE_META: StringName = &"_uniform_size_base_scale"
const PICKUP_AUDIO_LEFT_BUS: StringName = &"RingPanLeft"
const PICKUP_AUDIO_RIGHT_BUS: StringName = &"RingPanRight"
const TERRAIN_WARP_RAY_DISTANCE: float = 500.0
const TERRAIN_WARP_RETRY_LIMIT: int = 3

static var _pickup_audio_pan_left: bool = true

@export_group("Ring")
## Uniform scale applied to the ring mesh, pickup collision, and collection effects.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = max(value, 0.01)
		if is_node_ready():
			_apply_size_preview()

@export var respawn_enabled: bool = true
@export var respawn_delay_sec: float = 60.0
## Reusable visual and audio feedback played when the ring respawns.
@export var respawn_feedback: ObjectRespawnFeedback = preload("res://LS5Framework/Resources/Effects/ObjectRespawnFeedback.tres")

@export var allow_light_speed_dash: bool = true

@export var ring_value: int = 1

@export var pickup_particle_scene: PackedScene = preload("res://LS5Framework/Objects/Rings/Ring_Particle.tscn")
@export var pickup_particle_texture: Texture2D = preload("res://LS5Framework/Images/Ring_Particle.png")
@export var pickup_particle_lifetime: float = 0.35
@export var pickup_particle_count: int = 4
@export var pickup_particle_radial_offset: float = 0.12
@export var pickup_particle_radial_drift_distance: float = 0.12
@export var pickup_particle_start_scale_variation: float = 0.002
@export var pickup_particle_start_scale: float = 0.012
@export var pickup_particle_end_scale: float = 0.003
@export var pickup_particle_fade_out_time: float = 0.3

## Scene used for the pickup light pulse.
@export var pickup_light_scene: PackedScene = preload("res://LS5Framework/Objects/Rings/Ring_Light.tscn")
## Starting brightness of the pickup light pulse.
@export var pickup_light_start_energy: float = 1.0
## Brightness at the end of the pickup light pulse.
@export var pickup_light_end_energy: float = 0.0
## Lifetime of the pickup light pulse.
@export var pickup_light_lifetime: float = 0.2
## Fade-out time for the pickup light pulse.
@export var pickup_light_fade_out_time: float = 0.2
## Radius of the pickup light pulse.
@export var pickup_light_range: float = 2.5
## Tint applied to the pickup light pulse.
@export var pickup_light_color: Color = Color(1.0, 0.92, 0.55, 1.0)

@export var pickup_sound: AudioStream = preload("res://LS5Framework/Sounds/General/RingSpread.wav")
@export var pickup_sound_volume_db: float = 0.0
@export var pickup_sound_pitch_scale: float = 1.0

@export var rotate_speed_deg: float = 120.0

var _collected: bool = false
var _respawn_timer: float = 0.0
var _network_respawn_timers: Array[Timer] = []
var _mesh: MeshInstance3D = null
var _shape: CollisionShape3D = null
var _terrain_warp_enabled: bool = false
var _terrain_warp_height_offset: float = 0.0
var _terrain_warp_collision_mask: int = 0xFFFFFFFF
var _terrain_warp_generation: int = 0


func _ready() -> void:
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_apply_size_preview()
	if Engine.is_editor_hint():
		set_process(false)
		return
	super._ready()
	add_to_group(LIGHTSPEED_GROUP)
	add_to_group(RIVAL_SEARCH_GROUP)
	set_process(true)
	_lsd_register(true)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_terrain_warp_generation += 1
	_lsd_register(false)


func configure_terrain_warp(warp_enabled: bool, warp_height_offset: float, warp_collision_mask: int) -> void:
	_terrain_warp_enabled = warp_enabled
	_terrain_warp_height_offset = maxf(warp_height_offset, 0.0)
	_terrain_warp_collision_mask = warp_collision_mask
	_terrain_warp_generation += 1


func apply_configured_terrain_warp() -> bool:
	if not _terrain_warp_enabled:
		return true
	if _apply_terrain_warp_query():
		return true
	var generation: int = _terrain_warp_generation
	call_deferred("_retry_configured_terrain_warp", generation)
	return false


func _retry_configured_terrain_warp(generation: int) -> void:
	for _attempt: int in range(TERRAIN_WARP_RETRY_LIMIT):
		if generation != _terrain_warp_generation or not is_inside_tree() or get_tree() == null:
			return
		await get_tree().physics_frame
		if generation != _terrain_warp_generation or not is_inside_tree() or get_tree() == null:
			return
		await get_tree().process_frame
		if generation != _terrain_warp_generation or not is_inside_tree():
			return
		if _apply_terrain_warp_query():
			return


func _apply_terrain_warp_query() -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return false
	var ray_origin: Vector3 = global_position
	var ray_start: Vector3 = ray_origin + Vector3.UP * 0.1
	var ray_end: Vector3 = ray_origin + Vector3.DOWN * TERRAIN_WARP_RAY_DISTANCE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = _terrain_warp_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if not hit:
		return false
	var hit_position: Vector3 = hit.get("position", ray_origin)
	global_position = hit_position + Vector3.UP * _terrain_warp_height_offset
	return true


func _lsd_register(active: bool) -> void:
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr == null:
		return
	if active and allow_light_speed_dash:
		if mgr.has_method("register_ring"):
			mgr.register_ring(self)
		return
	if mgr.has_method("unregister_ring"):
		mgr.unregister_ring(self)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _mesh != null and rotate_speed_deg != 0.0 and not _collected:
		_mesh.rotation.y = fmod(_mesh.rotation.y + deg_to_rad(rotate_speed_deg) * delta, TAU)

	if _respawn_timer > 0.0:
		_respawn_timer = max(_respawn_timer - delta, 0.0)
		if _respawn_timer <= 0.0:
			_set_collected(false)


func _on_body_entered(body: Node3D) -> void:
	if not enabled:
		return
	_apply_to_player(body)
	emit_signal("triggered", body)
	if one_shot:
		enabled = false
		set_deferred("monitoring", false)


func _apply_to_player(player: Node3D) -> void:
	if _collected or not enabled:
		return

	var is_rival_actor: bool = false
	if player != null and player.has_meta("is_rival_actor"):
		is_rival_actor = bool(player.get_meta("is_rival_actor"))
	var is_buddy: bool = false
	if player != null and player.has_meta("is_buddy"):
		is_buddy = bool(player.get_meta("is_buddy"))

	if player == null or (not is_buddy and not is_rival_actor and not player.is_in_group("Player") and not player.is_in_group("player")):
		return

	# Award rings locally to whoever picked it up.
	if player != null and player.has_method("add_rings"):
		player.call("add_rings", ring_value)

	# Single-player: collect locally.
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		_collect_local()
		return

	# Multiplayer: request server to mark as collected (sync visibility/respawn).
	_collect_local(true)
	rpc_id(1, "_rpc_request_collect")


func _collect_local(play_particles: bool = true) -> void:
	if play_particles:
		_play_pickup_light()
		_play_pickup_sound()
	_set_collected(true, play_particles)
	if respawn_enabled:
		_respawn_timer = max(respawn_delay_sec, 0.0)


func reset_for_race_restart() -> void:
	if not _collected and _respawn_timer <= 0.0 and _network_respawn_timers.is_empty():
		return
	_respawn_timer = 0.0
	for timer in _network_respawn_timers:
		if timer != null and is_instance_valid(timer):
			timer.queue_free()
	_network_respawn_timers.clear()
	_set_collected(false, false)


func _set_collected(value: bool, play_particles: bool = false) -> void:
	var was_collected: bool = _collected
	_collected = value
	enabled = not value
	set_deferred("monitoring", not value)
	if _shape != null:
		_shape.set_deferred("disabled", value)
	if _mesh != null:
		_mesh.visible = not value
	_lsd_register(not value)
	if was_collected and not value and respawn_feedback != null:
		respawn_feedback.play(self)

	if value and play_particles:
		_play_pickup_particles()


func is_light_speed_dash_ready() -> bool:
	return not _collected and enabled and allow_light_speed_dash


func _play_pickup_particles() -> void:
	if pickup_particle_scene == null:
		return
	var parent = get_parent()
	if parent == null:
		parent = self
	var count: int = max(pickup_particle_count, 3)
	for i in range(count):
		var p: Node = pickup_particle_scene.instantiate()
		if p == null:
			continue
		var radial_dir: Vector3 = _get_pickup_particle_radial_direction(i, count)
		var uniform_size: float = max(size, 0.01)
		var radial_offset: Vector3 = radial_dir * max(pickup_particle_radial_offset, 0.0) * uniform_size
		var scale_jitter: float = randf_range(
			-pickup_particle_start_scale_variation,
			pickup_particle_start_scale_variation
		) * uniform_size
		p.set("twinkle_texture", pickup_particle_texture)
		p.set("twinkle_lifetime", max(pickup_particle_lifetime, 0.05))
		p.set("twinkle_start_scale", max(pickup_particle_start_scale * uniform_size + scale_jitter, 0.01))
		p.set("twinkle_end_scale", max(pickup_particle_end_scale * uniform_size, 0.01))
		p.set("twinkle_start_alpha", 1.0)
		p.set("twinkle_end_alpha", 0.0)
		p.set("twinkle_fade_out_time", max(pickup_particle_fade_out_time, 0.01))
		p.set("twinkle_spawn_position", global_position)
		p.set("twinkle_initial_offset", radial_offset)
		p.set("twinkle_drift_direction", radial_dir)
		p.set("twinkle_drift_distance", max(pickup_particle_radial_drift_distance, 0.0) * uniform_size)
		parent.add_child(p)
		if p is Node3D:
			var p3d: Node3D = p as Node3D
			p3d.top_level = true


func _play_pickup_light() -> void:
	if pickup_light_scene == null:
		return
	var p: Node = pickup_light_scene.instantiate()
	if p == null:
		return
	p.add_to_group(&"LevelTransient")
	p.set("light_spawn_position", global_position)
	p.set("light_start_energy", max(pickup_light_start_energy, 0.0))
	p.set("light_end_energy", max(pickup_light_end_energy, 0.0))
	p.set("light_lifetime", max(pickup_light_lifetime, 0.01))
	p.set("light_fade_out_time", max(pickup_light_fade_out_time, 0.01))
	p.set("light_range", max(pickup_light_range, 0.01) * max(size, 0.01))
	p.set("pulse_color", pickup_light_color)
	var parent = get_parent()
	if parent == null:
		parent = self
	parent.add_child(p)
	if p is Node3D:
		var p3d: Node3D = p as Node3D
		p3d.top_level = true


func _apply_size_preview() -> void:
	var uniform_size: float = max(size, 0.01)
	_apply_size_to_node(get_node_or_null("Mesh") as Node3D, uniform_size)
	_apply_size_to_node(get_node_or_null("CollisionShape3D") as Node3D, uniform_size)


func _apply_size_to_node(node: Node3D, uniform_size: float) -> void:
	if not node:
		return
	if not node.has_meta(SIZE_BASE_POSITION_META):
		node.set_meta(SIZE_BASE_POSITION_META, node.position)
	if not node.has_meta(SIZE_BASE_SCALE_META):
		node.set_meta(SIZE_BASE_SCALE_META, node.scale)
	var base_position_value: Variant = node.get_meta(SIZE_BASE_POSITION_META, node.position)
	var base_scale_value: Variant = node.get_meta(SIZE_BASE_SCALE_META, node.scale)
	if base_position_value is Vector3:
		node.position = (base_position_value as Vector3) * uniform_size
	if base_scale_value is Vector3:
		node.scale = (base_scale_value as Vector3) * uniform_size


func _get_pickup_particle_radial_direction(index: int, count: int) -> Vector3:
	var up: Vector3 = Vector3.UP
	var forward: Vector3 = -global_transform.basis.z
	forward = forward - up * forward.dot(up)
	if forward.length() < 0.001:
		forward = global_transform.basis.x - up * global_transform.basis.x.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	forward = forward.normalized()

	var right: Vector3 = up.cross(forward)
	if right.length() < 0.001:
		right = global_transform.basis.x - up * global_transform.basis.x.dot(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	right = right.normalized()

	var angle: float = TAU * float(index) / float(max(count, 1))
	var radial: Vector3 = (forward * cos(angle) + right * sin(angle)).normalized()
	if radial.length() < 0.001:
		radial = forward
	return radial

func _play_pickup_sound() -> void:
	if pickup_sound == null:
		return
	var p = AudioStreamPlayer3D.new()
	p.add_to_group(&"LevelTransient")
	p.stream = pickup_sound
	p.volume_db = pickup_sound_volume_db
	p.pitch_scale = pickup_sound_pitch_scale
	p.bus = get_next_pickup_audio_bus(&"SFX")
	p.autoplay = true

	var parent = get_parent()
	if parent == null:
		parent = self
	parent.add_child(p)
	p.top_level = true
	p.global_transform = global_transform
	p.finished.connect(func():
		p.queue_free()
	)


static func get_next_pickup_audio_bus(fallback_bus: StringName = &"SFX") -> StringName:
	var selected_bus: StringName = PICKUP_AUDIO_LEFT_BUS if _pickup_audio_pan_left else PICKUP_AUDIO_RIGHT_BUS
	_pickup_audio_pan_left = not _pickup_audio_pan_left
	if AudioServer.get_bus_index(selected_bus) < 0:
		return fallback_bus
	return selected_bus


@rpc("any_peer", "reliable")
func _rpc_request_collect() -> void:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if _collected:
		return

	rpc("_rpc_set_collected", true)
	if respawn_enabled and respawn_delay_sec > 0.0:
		var t = Timer.new()
		t.one_shot = true
		t.wait_time = respawn_delay_sec
		add_child(t)
		_network_respawn_timers.append(t)
		t.timeout.connect(func():
			_network_respawn_timers.erase(t)
			if is_inside_tree():
				rpc("_rpc_set_collected", false)
			t.queue_free()
		)
		t.start()


@rpc("authority", "reliable", "call_local")
func _rpc_set_collected(value: bool) -> void:
	_set_collected(value, false)

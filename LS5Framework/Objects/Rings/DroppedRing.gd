@tool
extends Ring
class_name DroppedRing

## Initial velocity assigned when the ring is spawned.
@export var dropped_initial_velocity: Vector3 = Vector3.ZERO
## Gravity direction used by dropped ring physics.
@export var dropped_up: Vector3 = Vector3.UP
## Gravity strength applied to dropped rings.
@export var dropped_gravity_strength: float = 65.0
## Velocity retained after each ground bounce.
@export var dropped_bounce_retention: float = 0.78
## Tangential velocity retained after each ground bounce.
@export var dropped_bounce_tangent_retention: float = 0.92
## Minimum impact speed needed to play a bounce sound.
@export var dropped_bounce_sound_min_speed: float = 8.0
## Minimum time between bounce sounds on one dropped ring.
@export var dropped_bounce_sound_cooldown: float = 0.08
## Time before the dropped ring can be picked up.
@export var dropped_pickup_delay: float = 1.0
## Lifetime before the dropped ring is removed.
@export var dropped_lifetime: float = 6.0
## Time at the end of lifetime spent flickering.
@export var dropped_flash_time: float = 1.5
## Visibility toggle interval during the flicker period.
@export var dropped_flash_interval: float = 0.08
## Radius used when resolving ground impacts.
@export var dropped_collision_radius: float = 0.55
## Collision mask used for dropped ring bounce checks.
@export_flags_3d_physics var dropped_ground_collision_mask: int = 17
## Sounds used when dropped rings bounce.
@export var dropped_bounce_sounds: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Objects/RingBounce1.wav"),
	preload("res://LS5Framework/Sounds/Objects/RingBounce2.wav"),
	preload("res://LS5Framework/Sounds/Objects/RingBounce3.wav"),
]
## Volume for dropped ring bounce sounds.
@export var dropped_bounce_volume_db: float = -5.0
## Base pitch for dropped ring bounce sounds.
@export var dropped_bounce_pitch_scale: float = 1.0

var _dropped_velocity: Vector3 = Vector3.ZERO
var _dropped_age: float = 0.0
var _dropped_pickup_timer: float = 0.0
var _dropped_flash_timer: float = 0.0
var _dropped_bounce_sound_timer: float = 0.0
var _dropped_visible: bool = true
var _last_bounce_sound_index: int = -1


func _ready() -> void:
	if Engine.is_editor_hint():
		super._ready()
		return
	add_to_group(&"LevelTransient")
	respawn_enabled = false
	allow_light_speed_dash = false
	pickup_sound = preload("res://LS5Framework/Sounds/General/ring.wav")
	super._ready()
	remove_from_group(LIGHTSPEED_GROUP)
	_lsd_register(false)
	_dropped_velocity = dropped_initial_velocity
	_dropped_pickup_timer = max(dropped_pickup_delay, 0.0)
	set_physics_process(true)


func setup_dropped_ring(initial_velocity: Vector3, up: Vector3) -> void:
	dropped_initial_velocity = initial_velocity
	_dropped_velocity = initial_velocity
	dropped_up = up.normalized()
	if dropped_up.length() < 0.001:
		dropped_up = Vector3.UP


func _process(delta: float) -> void:
	super._process(delta)
	if Engine.is_editor_hint():
		return
	_dropped_age += delta
	_dropped_pickup_timer = max(_dropped_pickup_timer - delta, 0.0)
	_dropped_bounce_sound_timer = max(_dropped_bounce_sound_timer - delta, 0.0)
	_update_expiration_visibility(delta)
	if _dropped_pickup_timer <= 0.0:
		_try_collect_overlapping_players()
	if _dropped_age >= max(dropped_lifetime, 0.05):
		queue_free()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var up: Vector3 = dropped_up.normalized()
	if up.length() < 0.001:
		up = Vector3.UP

	_dropped_velocity -= up * max(dropped_gravity_strength, 0.0) * delta
	var start_pos: Vector3 = global_position
	var target_pos: Vector3 = start_pos + _dropped_velocity * delta
	var motion: Vector3 = target_pos - start_pos
	if motion.length() < 0.001:
		global_position = target_pos
		return

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		start_pos,
		target_pos - up * max(dropped_collision_radius, 0.0) * max(size, 0.01),
		dropped_ground_collision_mask
	)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = target_pos
		return

	var hit_position: Vector3 = hit.get("position", target_pos)
	var normal: Vector3 = hit.get("normal", up)
	if normal.length() < 0.001:
		normal = up
	normal = normal.normalized()
	global_position = hit_position + normal * max(dropped_collision_radius, 0.0) * max(size, 0.01)

	var incoming_speed: float = _dropped_velocity.length()
	var normal_speed: float = _dropped_velocity.dot(normal)
	var tangent_velocity: Vector3 = _dropped_velocity - normal * normal_speed
	var bounce_speed: float = max(-normal_speed, 0.0) * clamp(dropped_bounce_retention, 0.0, 1.25)
	_dropped_velocity = tangent_velocity * clamp(dropped_bounce_tangent_retention, 0.0, 1.0) + normal * bounce_speed

	if incoming_speed >= max(dropped_bounce_sound_min_speed, 0.0):
		_play_bounce_sound()


func _apply_to_player(player: Node3D) -> void:
	if _dropped_pickup_timer > 0.0:
		return
	super._apply_to_player(player)


func _collect_local(play_particles: bool = true) -> void:
	if _collected:
		return
	_collected = true
	enabled = false
	set_deferred("monitoring", false)
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if play_particles:
		_play_pickup_light()
		_play_pickup_sound()
		_play_pickup_particles()
	queue_free()


func is_light_speed_dash_ready() -> bool:
	return false


func _update_expiration_visibility(delta: float) -> void:
	var flash_start: float = max(dropped_lifetime, 0.05) - max(dropped_flash_time, 0.0)
	if _dropped_age < flash_start:
		if not _dropped_visible:
			_dropped_visible = true
			_set_mesh_visible(true)
		return

	_dropped_flash_timer += delta
	if _dropped_flash_timer < max(dropped_flash_interval, 0.01):
		return
	_dropped_flash_timer = 0.0
	_dropped_visible = not _dropped_visible
	_set_mesh_visible(_dropped_visible)


func _set_mesh_visible(visible_state: bool) -> void:
	if _mesh != null:
		_mesh.visible = visible_state


func _try_collect_overlapping_players() -> void:
	for body in get_overlapping_bodies():
		if body is Node3D:
			_apply_to_player(body as Node3D)
			if _collected:
				return


func _play_bounce_sound() -> void:
	if _dropped_bounce_sound_timer > 0.0:
		return
	if dropped_bounce_sounds.is_empty():
		return

	var idx: int = 0
	if dropped_bounce_sounds.size() > 1 and _last_bounce_sound_index >= 0:
		idx = randi_range(0, dropped_bounce_sounds.size() - 2)
		if idx >= _last_bounce_sound_index:
			idx += 1
	else:
		idx = randi_range(0, dropped_bounce_sounds.size() - 1)
	_last_bounce_sound_index = idx

	var stream: AudioStream = dropped_bounce_sounds[idx]
	if stream == null:
		return

	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.add_to_group(&"LevelTransient")
	p.stream = stream
	p.volume_db = dropped_bounce_volume_db
	p.pitch_scale = max(dropped_bounce_pitch_scale + randf_range(-0.08, 0.08), 0.01)
	p.bus = "SFX"
	p.autoplay = true
	var parent: Node = get_parent()
	if parent == null:
		parent = self
	parent.add_child(p)
	p.top_level = true
	p.global_position = global_position
	p.finished.connect(func():
		p.queue_free()
	)
	_dropped_bounce_sound_timer = max(dropped_bounce_sound_cooldown, 0.0)

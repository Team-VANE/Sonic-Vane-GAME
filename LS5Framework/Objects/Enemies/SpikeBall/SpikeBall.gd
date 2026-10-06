@tool
extends RigidBody3D
class_name SpikeBall

enum MovementMode {
	FLOATING,
	CRASH_DOWN,
	PHYSICAL,
}

enum CrashState {
	TOP_HOLD,
	FALLING,
	GROUND_HOLD,
	RISING,
}

const DYNAMIC_PHYSICS_GROUP: StringName = &"dynamic_physics_object"
const CRASH_FALL_FAILSAFE_DURATION: float = 10.0
const SIZE_BASE_POSITION_META: StringName = &"_uniform_size_base_position"
const SIZE_BASE_SCALE_META: StringName = &"_uniform_size_base_scale"

@export_group("Behavior")
## Movement behavior used by the spike ball.
@export var movement_mode: MovementMode = MovementMode.FLOATING
## Uniform scale applied to the mesh, collisions, and landing dust.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = max(value, 0.01)
		if is_node_ready():
			_apply_size()
## Prevents contact damage while retaining solid collision.
@export var intangible: bool = false
## Damage passed to the contacted player.
@export var damage_amount: int = 1
## Radius shared by the solid collision and damage area.
@export var collision_radius: float = 1.75
## Extra radius used to detect contact at the edge of the solid collision.
@export var damage_contact_margin: float = 0.15

@export_group("Crash Down")
## Delay at the raised position before each fall.
@export var crash_top_hold_duration: float = 0.7
## Delay at ground level before rising.
@export var crash_ground_hold_duration: float = 0.7
## Initial downward speed along the spike ball's local Y axis.
@export var crash_initial_fall_speed: float = 0.0
## Downward acceleration along the spike ball's local Y axis.
@export var crash_fall_acceleration: float = 65.0
## Maximum downward speed along the spike ball's local Y axis.
@export var crash_max_fall_speed: float = 80.0
## Rising speed along the spike ball's local Y axis.
@export var crash_rise_speed: float = 20.0
## Physics layers treated as level geometry by crash detection.
@export_flags_3d_physics var crash_ground_collision_mask: int = 1

@export_group("Physical")
## Mass used by physical movement.
@export var physical_mass: float = 15.0
## Surface friction used by physical movement.
@export_range(0.0, 1.0, 0.01) var physical_friction: float = 0.35
## Surface bounce used by physical movement.
@export_range(0.0, 1.0, 0.01) var physical_bounce: float = 0.15
## Linear damping used by physical movement.
@export var physical_linear_damp: float = 0.05
## Angular damping used by physical movement.
@export var physical_angular_damp: float = 0.05
## Multiplier applied to the project gravity strength.
@export var physical_gravity_scale: float = 4.0
## Base up direction used outside gravity modifiers and planetary fields.
@export var physical_base_gravity_up: Vector3 = Vector3.UP
## Transforms the base gravity-up direction by the placement rotation once at startup.
@export var physical_base_up_is_local: bool = false
## Enables directional and planetary gravity systems in physical mode.
@export var follow_gravity_systems: bool = true

## Solid spherical collision used by players, level geometry, and physics objects.
@onready var _solid_collision: CollisionShape3D = $CollisionShape3D
## Spherical area used to detect damaging player contact.
@onready var _damage_area: Area3D = $DamageArea
## Spherical shape used by the player damage area.
@onready var _damage_collision: CollisionShape3D = $DamageArea/CollisionShape3D
## Audio player used by crash-down ground impacts.
@onready var _crash_audio: AudioStreamPlayer3D = $CrashAudio
## One-shot dust emitter used by crash-down ground impacts.
@onready var _landing_dust: GPUParticles3D = $LandingDust
## Root scaled to resize the spike ball mesh.
@onready var _visual_root: Node3D = $Visual

var _crash_state: CrashState = CrashState.TOP_HOLD
var _crash_state_timer: float = 0.0
var _crash_fall_timer: float = 0.0
var _crash_fall_speed: float = 0.0
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _raised_position: Vector3 = Vector3.ZERO
var _crash_up_axis: Vector3 = Vector3.UP
var _resolved_base_gravity_up: Vector3 = Vector3.UP
var _resolved_gravity_up: Vector3 = Vector3.UP
var _resolved_gravity_multiplier: float = 1.0
var _gravity_modifiers: Dictionary = {}
var _gravity_modifier_sequence: int = 0
var _planetary_gravity_sources: Dictionary = {}
var _base_dust_radial_velocity_min: float = 0.0
var _base_dust_radial_velocity_max: float = 0.0


func _ready() -> void:
	_spawn_transform = global_transform
	_raised_position = global_position
	_crash_up_axis = global_transform.basis.y.normalized()
	if _crash_up_axis.length() < 0.001:
		_crash_up_axis = Vector3.UP
	_resolved_base_gravity_up = physical_base_gravity_up.normalized()
	if _resolved_base_gravity_up.length() < 0.001:
		_resolved_base_gravity_up = Vector3.UP
	if physical_base_up_is_local:
		_resolved_base_gravity_up = (
			global_transform.basis * _resolved_base_gravity_up
		).normalized()
	_resolved_gravity_up = _resolved_base_gravity_up
	_configure_landing_dust()
	_apply_size()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_apply_physics_material()
	_configure_movement_mode()
	_damage_area.monitoring = not intangible
	_crash_state_timer = max(crash_top_hold_duration, 0.0)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if movement_mode == MovementMode.PHYSICAL:
		_update_gravity_state(delta)
	elif movement_mode == MovementMode.CRASH_DOWN:
		_update_crash_down(delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint():
		return
	if movement_mode != MovementMode.PHYSICAL or not follow_gravity_systems:
		return
	var gravity_strength: float = _get_project_gravity_strength()
	gravity_strength *= max(physical_gravity_scale, 0.0)
	gravity_strength *= max(_resolved_gravity_multiplier, 0.0)
	state.linear_velocity -= _resolved_gravity_up * gravity_strength * state.step


func is_gravity_pull_enabled() -> bool:
	return movement_mode == MovementMode.PHYSICAL and follow_gravity_systems


func get_gravity_up() -> Vector3:
	return _resolved_gravity_up


func get_gravity_down() -> Vector3:
	return -_resolved_gravity_up


func get_dynamic_impact_velocity() -> Vector3:
	if movement_mode == MovementMode.PHYSICAL:
		return linear_velocity
	return Vector3.ZERO


func apply_gravity_modifier(
	source: Object,
	new_gravity_up: Vector3,
	gravity_multiplier: float,
	duration: float,
	priority: int,
	blend_with_planetary: bool,
	clear_on_death: bool,
	clear_on_respawn: bool,
	clear_on_level_restart: bool,
	clear_on_race_cleanup: bool
) -> void:
	if not is_gravity_pull_enabled() or not source or new_gravity_up.length() < 0.001:
		return
	_gravity_modifier_sequence += 1
	_gravity_modifiers[source.get_instance_id()] = {
		"up": new_gravity_up.normalized(),
		"multiplier": max(gravity_multiplier, 0.0),
		"remaining": duration if duration > 0.0 else -1.0,
		"priority": priority,
		"sequence": _gravity_modifier_sequence,
		"blend_planetary": blend_with_planetary,
		"clear_on_death": clear_on_death,
		"clear_on_respawn": clear_on_respawn,
		"clear_on_level_restart": clear_on_level_restart,
		"clear_on_race_cleanup": clear_on_race_cleanup,
	}
	_update_gravity_state(0.0)


func remove_gravity_modifier(source: Object) -> void:
	if not source:
		return
	_gravity_modifiers.erase(source.get_instance_id())
	_update_gravity_state(0.0)


func register_planetary_gravity_source(source: Node) -> void:
	if not is_gravity_pull_enabled() or not source or not is_instance_valid(source):
		return
	if not source.has_method("get_planetary_gravity_vector"):
		return
	_planetary_gravity_sources[source.get_instance_id()] = weakref(source)
	_update_gravity_state(0.0)


func unregister_planetary_gravity_source(source: Node) -> void:
	if not source:
		return
	_planetary_gravity_sources.erase(source.get_instance_id())
	_update_gravity_state(0.0)


func clear_gravity_state(reason: StringName = &"all", clear_planetary: bool = true) -> void:
	var modifier_ids: Array = _gravity_modifiers.keys()
	var clear_key: StringName = _get_gravity_clear_key(reason)
	for modifier_id: Variant in modifier_ids:
		var modifier_value: Variant = _gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			_gravity_modifiers.erase(modifier_id)
			continue
		var modifier: Dictionary = modifier_value
		if clear_key == &"all" or bool(modifier.get(clear_key, false)):
			_gravity_modifiers.erase(modifier_id)
	if clear_planetary:
		_planetary_gravity_sources.clear()
	_update_gravity_state(0.0)


func reset_for_race_restart() -> void:
	clear_gravity_state(&"all", true)
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_crash_state = CrashState.TOP_HOLD
	_crash_state_timer = max(crash_top_hold_duration, 0.0)
	_crash_fall_timer = 0.0
	_crash_fall_speed = 0.0
	_crash_audio.stop()
	_landing_dust.emitting = false
	_configure_movement_mode()


func _apply_size() -> void:
	var uniform_size: float = max(size, 0.01)
	_apply_size_to_node(_visual_root, uniform_size)
	_apply_size_to_node(_landing_dust, uniform_size)
	var radius: float = max(collision_radius, 0.01) * uniform_size
	if _solid_collision.shape is SphereShape3D:
		(_solid_collision.shape as SphereShape3D).radius = radius
	if _damage_collision.shape is SphereShape3D:
		(_damage_collision.shape as SphereShape3D).radius = (
			max(collision_radius + damage_contact_margin, 0.01) * uniform_size
		)
	var dust_material: ParticleProcessMaterial = (
		_landing_dust.process_material as ParticleProcessMaterial
	)
	if dust_material:
		dust_material.radial_velocity_min = _base_dust_radial_velocity_min * uniform_size
		dust_material.radial_velocity_max = _base_dust_radial_velocity_max * uniform_size


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


func _apply_physics_material() -> void:
	mass = max(physical_mass, 0.001)
	linear_damp = max(physical_linear_damp, 0.0)
	angular_damp = max(physical_angular_damp, 0.0)
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = clamp(physical_friction, 0.0, 1.0)
	material.bounce = clamp(physical_bounce, 0.0, 1.0)
	physics_material_override = material


func _configure_movement_mode() -> void:
	gravity_scale = 0.0 if follow_gravity_systems else max(physical_gravity_scale, 0.0)
	if movement_mode == MovementMode.PHYSICAL:
		freeze = false
		sleeping = false
		continuous_cd = true
		add_to_group(DYNAMIC_PHYSICS_GROUP)
		return
	remove_from_group(DYNAMIC_PHYSICS_GROUP)
	gravity_scale = 0.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	sleeping = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _update_crash_down(delta: float) -> void:
	match _crash_state:
		CrashState.TOP_HOLD:
			_crash_state_timer = max(_crash_state_timer - delta, 0.0)
			if _crash_state_timer <= 0.0:
				_crash_state = CrashState.FALLING
				_crash_fall_timer = 0.0
				_crash_fall_speed = max(crash_initial_fall_speed, 0.0)
		CrashState.FALLING:
			_update_crash_fall(delta)
		CrashState.GROUND_HOLD:
			_crash_state_timer = max(_crash_state_timer - delta, 0.0)
			if _crash_state_timer <= 0.0:
				_crash_state = CrashState.RISING
		CrashState.RISING:
			_update_crash_rise(delta)


func _update_crash_fall(delta: float) -> void:
	_crash_fall_timer += delta
	if _crash_fall_timer >= CRASH_FALL_FAILSAFE_DURATION:
		queue_free()
		return
	_crash_fall_speed = min(
		_crash_fall_speed + max(crash_fall_acceleration, 0.0) * delta,
		max(crash_max_fall_speed, 0.0)
	)
	var motion: Vector3 = -_crash_up_axis * _crash_fall_speed * delta
	var hit: Dictionary = _trace_crash_center(global_position, global_position + motion)
	if hit.is_empty():
		global_position += motion
		return
	var hit_position_value: Variant = hit.get("position")
	if not (hit_position_value is Vector3):
		queue_free()
		return
	global_position = hit_position_value as Vector3
	_crash_state = CrashState.GROUND_HOLD
	_crash_state_timer = max(crash_ground_hold_duration, 0.0)
	if _crash_audio.stream:
		_crash_audio.play()
	_landing_dust.restart()
	_landing_dust.emitting = true


func _configure_landing_dust() -> void:
	var dust_material: ParticleProcessMaterial = (
		_landing_dust.process_material as ParticleProcessMaterial
	)
	if dust_material:
		_base_dust_radial_velocity_min = dust_material.radial_velocity_min
		_base_dust_radial_velocity_max = dust_material.radial_velocity_max
		dust_material.gravity = _crash_up_axis * 0.8


func _update_crash_rise(delta: float) -> void:
	var distance_to_top: float = (_raised_position - global_position).dot(_crash_up_axis)
	if distance_to_top <= 0.001:
		global_position = _raised_position
		_crash_state = CrashState.TOP_HOLD
		_crash_state_timer = max(crash_top_hold_duration, 0.0)
		return
	var rise_distance: float = min(max(crash_rise_speed, 0.0) * delta, distance_to_top)
	global_position += _crash_up_axis * rise_distance


func _trace_crash_center(ray_from: Vector3, ray_to: Vector3) -> Dictionary:
	var world: World3D = get_world_3d()
	if not world or ray_from.is_equal_approx(ray_to):
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collision_mask = crash_ground_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	query.exclude = [get_rid()]
	return world.direct_space_state.intersect_ray(query)


func _update_gravity_state(delta: float) -> void:
	var previous_up: Vector3 = _resolved_gravity_up
	var previous_multiplier: float = _resolved_gravity_multiplier
	var selected_modifier: Dictionary = {}
	var selected_priority: int = -2147483648
	var selected_sequence: int = -1
	var expired_ids: Array = []
	for modifier_id: Variant in _gravity_modifiers.keys():
		var modifier_value: Variant = _gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			expired_ids.append(modifier_id)
			continue
		var modifier: Dictionary = modifier_value
		var remaining: float = float(modifier.get("remaining", -1.0))
		if remaining > 0.0 and delta > 0.0:
			remaining = max(remaining - delta, 0.0)
			modifier["remaining"] = remaining
			_gravity_modifiers[modifier_id] = modifier
			if remaining <= 0.0:
				expired_ids.append(modifier_id)
				continue
		var priority: int = int(modifier.get("priority", 0))
		var sequence: int = int(modifier.get("sequence", 0))
		if priority > selected_priority or (
			priority == selected_priority and sequence > selected_sequence
		):
			selected_modifier = modifier
			selected_priority = priority
			selected_sequence = sequence
	for modifier_id: Variant in expired_ids:
		_gravity_modifiers.erase(modifier_id)

	var planetary_vector: Vector3 = _get_planetary_gravity_vector()
	var gravity_down: Vector3 = -_resolved_base_gravity_up
	var zero_gravity_up: Vector3 = _resolved_base_gravity_up
	if not selected_modifier.is_empty():
		var modifier_up_value: Variant = selected_modifier.get("up", _resolved_base_gravity_up)
		var modifier_up: Vector3 = _resolved_base_gravity_up
		if modifier_up_value is Vector3:
			modifier_up = (modifier_up_value as Vector3).normalized()
		if modifier_up.length() < 0.001:
			modifier_up = _resolved_base_gravity_up
		zero_gravity_up = modifier_up
		gravity_down = -modifier_up * max(float(selected_modifier.get("multiplier", 1.0)), 0.0)
		if bool(selected_modifier.get("blend_planetary", false)):
			gravity_down += planetary_vector
	elif planetary_vector.length() > 0.000001:
		gravity_down = planetary_vector
	if gravity_down.length() > 0.000001:
		_resolved_gravity_up = -gravity_down.normalized()
		_resolved_gravity_multiplier = gravity_down.length()
	else:
		_resolved_gravity_up = zero_gravity_up
		_resolved_gravity_multiplier = 0.0
	var gravity_direction_changed: bool = (
		previous_up.length() < 0.001
		or previous_up.normalized().dot(_resolved_gravity_up) < 0.99999
	)
	var gravity_strength_changed: bool = not is_equal_approx(
		previous_multiplier,
		_resolved_gravity_multiplier
	)
	if gravity_direction_changed or gravity_strength_changed:
		sleeping = false


func _get_planetary_gravity_vector() -> Vector3:
	var planetary_vector: Vector3 = Vector3.ZERO
	var invalid_source_ids: Array = []
	for source_id: Variant in _planetary_gravity_sources.keys():
		var source_ref_value: Variant = _planetary_gravity_sources.get(source_id)
		if not (source_ref_value is WeakRef):
			invalid_source_ids.append(source_id)
			continue
		var source: Object = (source_ref_value as WeakRef).get_ref()
		if not source or not is_instance_valid(source):
			invalid_source_ids.append(source_id)
			continue
		if not source.has_method("get_planetary_gravity_vector"):
			invalid_source_ids.append(source_id)
			continue
		var contribution_value: Variant = source.call("get_planetary_gravity_vector", self)
		if contribution_value is Vector3:
			planetary_vector += contribution_value as Vector3
	for source_id: Variant in invalid_source_ids:
		_planetary_gravity_sources.erase(source_id)
	return planetary_vector


func _get_project_gravity_strength() -> float:
	var gravity_setting: Variant = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return max(float(gravity_setting), 0.0)


func _get_gravity_clear_key(reason: StringName) -> StringName:
	match reason:
		&"death":
			return &"clear_on_death"
		&"respawn":
			return &"clear_on_respawn"
		&"level_restart":
			return &"clear_on_level_restart"
		&"race_cleanup", &"race_restart":
			return &"clear_on_race_cleanup"
		_:
			return &"all"


func _on_damage_area_body_entered(body: Node3D) -> void:
	_try_damage_body(body)


func resolve_player_collision_contact(body: Node3D, incoming_velocity: Vector3, _contact_normal: Vector3) -> bool:
	return _try_damage_body(body, incoming_velocity, true)


func _try_damage_body(body: Node3D, incoming_velocity: Vector3 = Vector3.ZERO, use_incoming_velocity: bool = false) -> bool:
	if intangible or not body or not _is_player(body):
		return false
	if body.has_method("is_hurt_invulnerable"):
		var invulnerable_value: Variant = body.call("is_hurt_invulnerable")
		if invulnerable_value is bool and bool(invulnerable_value):
			return false
	if body.has_method("apply_damage"):
		if use_incoming_velocity and body is CharacterBody3D:
			(body as CharacterBody3D).velocity = incoming_velocity
		body.call("apply_damage", max(damage_amount, 0), self)
		return true
	return false


func _is_player(body: Node) -> bool:
	return body.is_in_group(&"player") or body.is_in_group(&"Player")

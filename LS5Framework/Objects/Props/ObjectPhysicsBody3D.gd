extends RigidBody3D
class_name ObjectPhysicsBody3D

enum CarryPhysicsMode {
	RIGID_BODY,
	SIMPLIFIED,
}

enum CarryState {
	FREE,
	EASING_TO_CARRY,
	CARRIED,
}

@export_group("Object Physics")
## Enables supplemental collision sweeps independently of surface feedback.
@export var collision_safety_enabled: bool = true
## Minimum speed requiring supplemental collision sweeps.
@export var collision_safety_min_speed: float = 0.0
## Keeps imported fracture templates frozen until an emitter activates a copy.
@export var fracture_template: bool = false
## Keeps the body fixed while preserving interaction components.
@export var anchored: bool = false
## Enables physical water interaction independently of carrying.
@export var buoyancy_enabled: bool = false
## Effective water displacement in cubic world units.
@export var buoyancy_volume: float = 0.03
## Weighted local points used for water displacement and torque.
@export var buoyancy_samples: Array[PropBuoyancySample] = []
## Component receiving water forces. Empty creates a component on ready.
@export var buoyancy_component: ObjectBuoyancy3D

## Current carrier of this object.
var carry_holder: Node3D
## Player credited for this object's local impacts.
var impact_instigator: Node3D:
	get:
		return get_score_award_recipient()
	set(value):
		set_influence_owner(value)

@export_group("Influence Ownership")
## Attribution duration after release or a qualifying impulse. Zero disables expiry.
@export_range(0.0, 120.0, 0.1, "or_greater", "suffix:s") var influence_duration: float = 8.0
## Minimum applied impulse that assigns a new influence owner.
@export_range(0.0, 1000.0, 0.1, "or_greater") var influence_minimum_impulse: float = 2.0

var _influence_owner: WeakRef
var _influence_remaining: float = 0.0

@export_group("Carry")
## Allows this object to be picked up.
@export var carry_enabled: bool = true
## Disables body collisions while held; release placement still checks the full shape.
@export var carry_intangible: bool = true

var _carry_collisions_suspended: bool = false
var _carry_collision_layer: int = 0
var _carry_collision_mask: int = 0
## Group used by players when scanning for carryable objects.
@export var carry_group: StringName = &"carryable_object"
## Group used by dynamic-object interactions such as enemy impact damage.
@export var dynamic_physics_group: StringName = &"dynamic_physics_object"
## Time used to ease into the carry target.
@export var carry_ease_time: float = 0.18
## Easing exponent used while moving into the carry target.
@export var carry_ease_power: float = 2.0
## Angular velocity applied when released without throw spin data.
@export var release_angular_velocity: Vector3 = Vector3.ZERO
## Allows this object to reset when it enters a carryable respawn volume.
@export var carry_respawn_enabled: bool = true
## Optional transform used when this object respawns.
@export var carry_respawn_point: Node3D
## Linear velocity applied after respawning.
@export var carry_respawn_velocity: Vector3 = Vector3.ZERO
## Angular velocity applied after respawning.
@export var carry_respawn_angular_velocity: Vector3 = Vector3.ZERO

@export_group("Physics")
## Physics mode used while the object is not carried.
@export var carry_physics_mode: CarryPhysicsMode = CarryPhysicsMode.RIGID_BODY
## Mass used by rigid-body physics.
@export var carry_mass: float = 10.0
## Friction used by rigid-body physics.
@export var carry_friction: float = 0.21
## Bounce used by rigid-body physics.
@export var carry_bounce: float = 0.35
## Linear damping used by rigid-body physics.
@export var carry_linear_damp: float = 0.09
## Angular damping used by rigid-body physics.
@export var carry_angular_damp: float = 0.05
## Gravity scale used by rigid-body physics.
@export var carry_gravity_scale: float = 4.0
## Allows this object to follow directional and planetary gravity pull mechanics.
@export var follow_gravity_pull: bool = true:
	set(value):
		follow_gravity_pull = value
		if is_inside_tree():
			_apply_physics_attributes()
			_update_gravity_pull_state(0.0)
			_wake_for_gravity_change()
## Maximum linear speed eligible for rigid-body rest detection.
@export var carry_rest_linear_speed: float = 1.0
## Maximum angular speed eligible for rigid-body rest detection.
@export var carry_rest_angular_speed: float = 0.75
## Time stable support must be maintained before a rigid carryable sleeps.
@export var carry_rest_settle_time: float = 0.15
## Interval between shape-support checks while sleeping on unchanged static geometry. Zero checks every tick.
@export_range(0.0, 1.0, 0.01, "seconds") var carry_rest_support_refresh_time: float = 0.1
## Maximum accumulated displacement allowed during the rest settling period.
@export_range(0.0, 0.25, 0.001) var carry_rest_position_tolerance: float = 0.015
## Maximum accumulated rotation allowed during the rest settling period.
@export_range(0.0, 10.0, 0.1, "degrees") var carry_rest_rotation_tolerance_degrees: float = 1.0
## Extra fixed distance used by rigid-body support checks.
@export var carry_rest_support_extra_distance: float = 0.1
## Maximum number of shape contacts considered by rigid-body support checks.
@export_range(1, 32, 1) var carry_rest_max_support_contacts: int = 8
## Minimum alignment between a support normal and gravity up.
@export_range(-1.0, 1.0, 0.01) var carry_rest_min_support_dot: float = 0.35
## Extra support angle retained after a rigid carryable establishes stable contact.
@export_range(0.0, 45.0, 0.1, "degrees") var carry_rest_support_hysteresis_degrees: float = 8.0
## Maximum cumulative gravity direction change ignored while rigid support remains stable.
@export_range(0.0, 45.0, 0.1, "degrees") var carry_rest_gravity_up_tolerance_degrees: float = 5.0
## Maximum cumulative gravity strength ratio ignored while rigid support remains stable.
@export_range(0.0, 1.0, 0.01) var carry_rest_gravity_strength_tolerance: float = 0.05
## Enables continuous collision detection for rigid-body carry physics.
@export var carry_continuous_collision: bool = true

@export_group("Simplified Physics")
## Initial velocity used by simplified physics.
@export var simplified_initial_velocity: Vector3 = Vector3.ZERO
## Base up direction used by carryable gravity and simplified physics.
@export var simplified_up: Vector3 = Vector3.UP
## Gravity strength used by simplified physics.
@export var simplified_gravity_strength: float = 65.0
## Dynamic friction coefficient used while simplified props slide on a support.
@export_range(0.0, 1.0, 0.01) var simplified_friction: float = 0.25
## Static friction coefficient for quiet props, clamped to at least the dynamic coefficient.
@export_range(0.0, 2.0, 0.01) var simplified_static_friction: float = 0.6
## Maximum contact responses resolved during each simplified motion step.
@export_range(1, 16, 1) var simplified_max_slides: int = 4
## Minimum settling threshold for closing speed; large gravity steps raise this threshold.
@export var simplified_settle_speed: float = 2.0
## Maximum downward distance used to check the complete collision footprint.
@export var simplified_support_distance: float = 0.08
## Normal velocity retained on simplified ground contact.
@export_range(0.0, 1.25, 0.01) var simplified_bounce: float = 0.35
## Fallback collision radius for shapeless legacy props and surface-effect probes.
@export var simplified_collision_radius: float = 0.55
## Maximum distance covered by one simplified physics sweep step.
@export var simplified_max_sweep_step_distance: float = 0.45
## Extra separation applied after simplified physics impact.
@export var simplified_collision_skin: float = 0.025
## Ground mask used by shapeless legacy props; authored shapes use the body collision mask.
@export_flags_3d_physics var simplified_ground_collision_mask: int = 17
## Relative speed eligible for resting; smaller rebound speeds are cleared.
@export var simplified_sleep_speed: float = 0.5
## Keeps simplified physics carryables upright while they are not carried.
@export var simplified_keep_upright: bool = true

@export_group("Surface Effects")
## Optional camera used for carryable impact and slide effect distance checks.
@export var surface_effect_camera: Node3D
## Maximum camera distance for carryable impact and slide effects.
@export var surface_effect_camera_distance: float = 200.0
## Particle scene emitted when this object hits or slides against collision surfaces.
@export var surface_dust_scene: PackedScene
## Time before spawned surface dust is cleaned up.
@export var surface_dust_cleanup_time: float = 2.0
## Minimum normal impact speed needed to emit impact effects.
@export var surface_impact_min_speed: float = 2.0
## Minimum tangential speed needed to emit slide effects.
@export var surface_slide_min_speed: float = 2.5
## Minimum time between impact effects.
@export var surface_impact_effect_cooldown: float = 0.08
## Minimum time between slide effects.
@export var surface_slide_effect_cooldown: float = 0.12
## Contact separation time required before another impact effect can trigger.
@export var surface_impact_contact_reset_time: float = 0.1
## Sounds played when this object hits collision surfaces.
@export var surface_impact_sounds: Array[AudioStream] = []
## Sounds played when this object slides against collision surfaces.
@export var surface_slide_sounds: Array[AudioStream] = []
## AudioStreamPlayer3D used for carryable impact sounds.
@export var surface_impact_sfx_player: AudioStreamPlayer3D
## AudioStreamPlayer3D used for carryable slide sounds.
@export var surface_slide_sfx_player: AudioStreamPlayer3D
## Volume used at the minimum impact or slide speed.
@export var surface_sound_min_volume_db: float = -24.0
## Volume used at or above the maximum impact or slide speed.
@export var surface_sound_max_volume_db: float = -4.0
## Impact or slide speed that reaches maximum sound volume.
@export var surface_sound_max_speed: float = 45.0
## Pitch variation applied to carryable surface sounds.
@export var surface_sound_pitch_random: float = 0.08
## Audio bus used by carryable surface sounds.
@export var surface_sound_bus: StringName = &"SFX"
## Time a slide loop continues without fresh slide contact.
@export var surface_slide_sound_stop_delay: float = 0.16
## Enables ray probes for rigid-body carryable surface effects.
@export var surface_effect_rigid_probe_enabled: bool = true
## Enables extra probe skin for rigid-body surface effect sweeps.
@export var surface_effect_probe_skin_enabled: bool = true
## Extra distance used by rigid-body surface effect probes.
@export var surface_effect_probe_skin: float = 0.15
## Extra distance used by rigid-body surface effect probes at high speed.
@export var surface_effect_probe_max_skin: float = 1.2
## Speed that applies the maximum rigid-body surface effect probe distance.
@export var surface_effect_probe_max_speed: float = 80.0
## Minimum inward speed needed for rigid-body surface effect safety correction.
@export var surface_effect_probe_correction_min_speed: float = 0.5
## Collision mask used by rigid-body surface effect probes.
@export_flags_3d_physics var surface_effect_collision_mask: int = 17

var _carry_state: CarryState = CarryState.FREE
var _carry_target_transform: Transform3D = Transform3D.IDENTITY
var _ease_start_transform: Transform3D = Transform3D.IDENTITY
var _ease_timer: float = 0.0
var _manual_velocity: Vector3 = Vector3.ZERO
var _collision_exception_body: PhysicsBody3D = null
var _collision_exception_timer: float = 0.0
var _axis_lock_timer: float = 0.0
var _axis_lock_direction: Vector3 = Vector3.ZERO
var _axis_lock_speed: float = 0.0
var _axis_lock_sideways_influence: float = 0.0
var _speed_lock_timer: float = 0.0
var _speed_lock_direction: Vector3 = Vector3.ZERO
var _speed_lock_value: float = 0.0
var _hold_forward_timer: float = 0.0
var _hold_forward_direction: Vector3 = Vector3.ZERO
var _hold_forward_speed: float = 0.0
var _hold_up_timer: float = 0.0
var _hold_up_direction: Vector3 = Vector3.ZERO
var _hold_up_speed: float = 0.0
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _surface_impact_effect_timer: float = 0.0
var _surface_slide_effect_timer: float = 0.0
var _last_surface_impact_sound_index: int = -1
var _last_surface_slide_sound_index: int = -1
var _surface_previous_position: Vector3 = Vector3.ZERO
var _surface_previous_velocity: Vector3 = Vector3.ZERO
var _surface_slide_sound_timer: float = 0.0
var _surface_impact_contact_timer: float = 0.0
var _surface_impact_contact_normal: Vector3 = Vector3.ZERO
var _temporary_surface_slide_player: AudioStreamPlayer3D = null
var _simplified_resting: bool = false
var _rigid_resting: bool = false
var _rigid_rest_timer: float = 0.0
var _rigid_support_valid: bool = false
var _rigid_rest_linear_limit: float = 0.0
var _rigid_support_normal: Vector3 = Vector3.ZERO
var _rigid_rest_gravity_up: Vector3 = Vector3.ZERO
var _rigid_rest_gravity_multiplier: float = 0.0
var _rigid_rest_transform: Transform3D = Transform3D.IDENTITY
var _rigid_support_body: Node3D = null
var _rigid_support_transform: Transform3D = Transform3D.IDENTITY
var _rigid_support_shape: int = -1
var _rigid_support_shape_transform: Transform3D = Transform3D.IDENTITY
var _rigid_support_refresh_timer: float = 0.0
var _rigid_rest_parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
var _rigid_rest_result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
var _simplified_motion_parameters: PhysicsTestMotionParameters3D
var _simplified_motion_result: PhysicsTestMotionResult3D
var _simplified_ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _surface_ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _gravity_modifiers: Dictionary = {}
var _gravity_modifier_sequence: int = 0
var _planetary_gravity_sources: Dictionary = {}
var _resolved_gravity_up: Vector3 = Vector3.UP
var _resolved_gravity_multiplier: float = 1.0
## Optional assistance state for the most recent targeted throw.
var _throw_flight: RefCounted = null


func _ready() -> void:
	if collision_safety_enabled:
		var safety: ObjectMotionSafety3D = ObjectMotionSafety3D.new()
		safety.name = "MotionSafety"
		safety.minimum_speed = collision_safety_min_speed
		add_child(safety)
	if not buoyancy_component:
		buoyancy_component = ObjectBuoyancy3D.new()
		buoyancy_component.name = "Buoyancy"
		add_child(buoyancy_component)
	buoyancy_component.enabled = buoyancy_enabled
	buoyancy_component.displaced_volume = buoyancy_volume
	buoyancy_component.samples = buoyancy_samples if not buoyancy_samples.is_empty() else _make_buoyancy_samples()
	_spawn_transform = global_transform
	if carry_enabled:
		add_to_group(carry_group)
	add_to_group(dynamic_physics_group)
	_manual_velocity = simplified_initial_velocity
	_update_gravity_pull_state(0.0)
	_apply_physics_attributes()
	_configure_physics_mode()
	_configure_surface_contact_monitor()
	_store_surface_effect_previous_state()


func _physics_process(delta: float) -> void:
	_update_influence_ownership(delta)
	if buoyancy_component:
		buoyancy_component.enabled = buoyancy_enabled
		buoyancy_component.displaced_volume = buoyancy_volume
	_update_collision_exception_timer(delta)
	_update_surface_effect_timers(delta)
	_update_gravity_pull_state(delta)
	if carry_physics_mode == CarryPhysicsMode.RIGID_BODY and buoyancy_enabled and buoyancy_component and sleeping and not anchored and not is_carried():
		var water: Dictionary = buoyancy_component.evaluate(global_transform, linear_velocity, angular_velocity, get_prop_gravity_vector(), mass, delta)
		if buoyancy_component.submerged_fraction > 0.0 or buoyancy_component.get_meta(&"was_submerged", false):
			sleeping = false
		buoyancy_component.set_meta(&"was_submerged", buoyancy_component.submerged_fraction > 0.0)
	if _carry_state == CarryState.EASING_TO_CARRY:
		_update_carry_ease(delta)
		_stop_surface_slide_sound()
		_store_surface_effect_previous_state()
		return
	if _carry_state == CarryState.CARRIED:
		global_transform = _resolve_carry_transform(_carry_target_transform)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_stop_surface_slide_sound()
		_store_surface_effect_previous_state()
		return
	var previous_surface_position: Vector3 = _surface_previous_position
	var previous_surface_velocity: Vector3 = _surface_previous_velocity
	_update_gimmick_velocity(delta)
	if anchored or fracture_template:
		return
	if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		_update_simplified_physics(delta)
	else:
		_update_rigid_rest_state(delta)
		if not _rigid_resting:
			_process_rigid_surface_effect_probe(
				previous_surface_position,
				global_position,
				previous_surface_velocity,
				_get_object_velocity()
			)
		else:
			_stop_surface_slide_sound()
	_store_surface_effect_previous_state()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if carry_physics_mode != CarryPhysicsMode.RIGID_BODY:
		return
	if is_carried() or anchored:
		return
	if state.get_contact_count():
		stop_throw_assistance()
	elif _throw_flight:
		state.linear_velocity = _throw_flight.update_velocity(state.linear_velocity, state.step)
	if _rigid_resting and not state.sleeping:
		_clear_rigid_rest_state()
	if follow_gravity_pull and not _rigid_resting:
		var gravity_up: Vector3 = get_gravity_up()
		var gravity_strength: float = _get_resolved_gravity_strength(_get_rigid_base_gravity_strength())
		state.linear_velocity -= gravity_up * gravity_strength * state.step
	_apply_water_forces(state)
	var contact_count: int = state.get_contact_count()
	for i: int in range(contact_count):
		var normal: Vector3 = state.get_contact_local_normal(i)
		if normal.length() < 0.001:
			continue
		normal = normal.normalized()
		var contact_position: Vector3 = state.get_contact_local_position(i)
		var current_velocity: Vector3 = state.linear_velocity
		_process_surface_effect_contact(contact_position, normal, current_velocity)


func can_be_carried_by(_player: Node) -> bool:
	if not carry_enabled or anchored:
		return false
	return _carry_state == CarryState.FREE


func begin_carry(player: Node, target_transform: Transform3D, release_collision_lock: float = 0.35) -> bool:
	if not can_be_carried_by(player):
		return false
	stop_throw_assistance()
	carry_holder = player as Node3D
	impact_instigator = carry_holder
	_carry_target_transform = target_transform
	_ease_start_transform = global_transform
	_ease_timer = 0.0
	_carry_state = CarryState.EASING_TO_CARRY
	_simplified_resting = false
	_clear_rigid_rest_state()
	_stop_surface_slide_sound()
	_set_carried_physics_state()
	if carry_intangible:
		_carry_collision_layer = collision_layer
		_carry_collision_mask = collision_mask
		_carry_collisions_suspended = true
		collision_layer = 0
		collision_mask = 0
	if player is PhysicsBody3D:
		_set_collision_exception(player as PhysicsBody3D, max(release_collision_lock, 0.0))
	return true


func set_carry_target_transform(target_transform: Transform3D) -> void:
	_carry_target_transform = target_transform
	if _carry_state == CarryState.CARRIED:
		global_transform = _resolve_carry_transform(_carry_target_transform)


func put_down(release_transform: Transform3D, release_velocity: Vector3, release_collision_lock: float = 0.35) -> void:
	release_carry(release_transform, release_velocity, release_collision_lock)


func throw_from_carry(release_transform: Transform3D, release_velocity: Vector3, release_collision_lock: float = 0.35) -> void:
	release_carry(release_transform, release_velocity, release_collision_lock)


func get_throw_prediction_parameters() -> Dictionary:
	if buoyancy_component and buoyancy_component.submerged_fraction > 0.0:
		return {}
	var gravity: Vector3 = get_prop_gravity_vector()
	var damping: float = maxf(carry_linear_damp, 0.0)
	if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		gravity = -get_gravity_up() * _get_resolved_gravity_strength(maxf(simplified_gravity_strength, 0.0))
		damping = 0.0
	elif not follow_gravity_pull:
		var direction: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
		gravity = direction * _get_rigid_base_gravity_strength()
	if carry_physics_mode == CarryPhysicsMode.RIGID_BODY and linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE:
		damping += float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	var motion: Dictionary = {
		"gravity": gravity,
		"damping": damping,
		"step": maxf(Engine.time_scale, 0.001) / float(Engine.physics_ticks_per_second),
		"gravity_after_motion": carry_physics_mode == CarryPhysicsMode.RIGID_BODY and follow_gravity_pull,
	}
	if follow_gravity_pull and not get_tree().get_nodes_in_group(&"PlanetaryGravitySource").is_empty():
		motion["gravity_sampler"] = Callable(self, "sample_throw_gravity")
	return motion


func sample_throw_gravity(sample_position: Vector3) -> Vector3:
	var base_strength: float = simplified_gravity_strength if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED else _get_rigid_base_gravity_strength()
	var planetary: Vector3 = Vector3.ZERO
	for source: Node in get_tree().get_nodes_in_group(&"PlanetaryGravitySource"):
		if source.has_method("get_gravity_vector_at"):
			planetary += source.call("get_gravity_vector_at", sample_position, self) as Vector3
	var selected: Dictionary = {}
	for modifier: Dictionary in _gravity_modifiers.values():
		if selected.is_empty() or int(modifier["priority"]) > int(selected["priority"]) or (int(modifier["priority"]) == int(selected["priority"]) and int(modifier["sequence"]) > int(selected["sequence"])):
			selected = modifier
	var down: Vector3 = -_get_base_gravity_up()
	if not selected.is_empty():
		down = -(selected["up"] as Vector3).normalized() * maxf(float(selected["multiplier"]), 0.0)
		if bool(selected.get("blend_planetary", false)):
			down += planetary
	elif not planetary.is_zero_approx():
		down = planetary
	return down * maxf(base_strength, 0.0)


func start_throw_assistance(target: Node3D, solution: Dictionary, settings: Dictionary) -> void:
	if not _throw_flight:
		_throw_flight = load("res://LS5Framework/Objects/Props/ThrownObjectFlight.gd").new(self)
	_throw_flight.start(target, solution, settings)


func stop_throw_assistance() -> void:
	if _throw_flight:
		_throw_flight.stop()


func is_throw_assistance_active() -> bool:
	return _throw_flight and _throw_flight.is_active()


func get_throw_collision_mask() -> int:
	return _carry_collision_mask if _carry_collisions_suspended else collision_mask


func get_throw_clearance_radius() -> float:
	var radius: float = 0.0
	for owner_id: int in get_shape_owners():
		if is_shape_owner_disabled(owner_id):
			continue
		var local_transform: Transform3D = shape_owner_get_transform(owner_id)
		for index: int in range(shape_owner_get_shape_count(owner_id)):
			var shape: Shape3D = shape_owner_get_shape(owner_id, index)
			var shape_basis: Basis = global_basis * local_transform.basis
			if shape is SphereShape3D and shape_basis.is_conformal():
				var center_offset: float = (global_basis * local_transform.origin).length()
				radius = maxf(radius, center_offset + shape.radius * shape_basis.x.length())
				continue
			var bounds: AABB = shape.get_debug_mesh().get_aabb()
			for corner: int in range(8):
				radius = maxf(radius, (global_basis * (local_transform * bounds.get_endpoint(corner))).length())
	return radius


func release_carry(release_transform: Transform3D, release_velocity: Vector3, release_collision_lock: float = 0.35) -> void:
	stop_throw_assistance()
	if is_instance_valid(carry_holder):
		set_influence_owner(carry_holder)
	_restore_carry_collisions()
	carry_holder = null
	global_transform = release_transform
	_reset_motion_history()
	_carry_state = CarryState.FREE
	_simplified_resting = false
	_clear_rigid_rest_state()
	_collision_exception_timer = max(release_collision_lock, _collision_exception_timer)
	_apply_physics_attributes()
	_configure_physics_mode()
	if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		_manual_velocity = release_velocity
	else:
		freeze = false
		sleeping = false
		linear_velocity = release_velocity
		angular_velocity = release_angular_velocity
	_store_surface_effect_previous_state()


func apply_spring_impulse(
	origin: Vector3,
	launch_dir: Vector3,
	strength: float,
	snap_to_center: bool,
	stop_momentum: bool,
	additive_mode: int,
	min_additive_launch_speed: float,
	additive_mirrored_bounce_ratio: float,
	max_additive_launch_speed: float,
	_movement_lock_time: float = 0.0,
	_action_lock_time: float = 0.0,
	align_time: float = 0.0,
	_spring_basis: Basis = Basis.IDENTITY,
	_clear_movement_lock_on_ground: bool = true,
	_clear_action_lock_on_ground: bool = true,
	_lock_horizontal_during_align: bool = true,
	sideways_gravity_influence: float = 0.0,
	_detach_from_ground: bool = true,
	_align_model_during_spring: bool = true,
	_preserve_active_flight: bool = false,
	_preserved_flight_time_bonus: float = 0.0,
	_downward_trajectory_torque_enabled: bool = true,
	_downward_trajectory_min_angle_deg: float = 45.0,
	_downward_trajectory_align_speed_deg: float = 720.0,
	_downward_trajectory_gravity_yaw_enabled: bool = true,
	_downward_trajectory_gravity_yaw_strength: float = 1.0,
	_downward_trajectory_gravity_yaw_safe_angle_deg: float = 3.0,
	_downward_trajectory_gravity_yaw_full_angle_deg: float = 90.0,
	_downward_trajectory_torque_min_horizontal_speed: float = 2.0,
	_downward_trajectory_landing_forward_pitch_enabled: bool = true
) -> void:
	if is_carried():
		return
	_release_for_gimmick()
	var direction: Vector3 = _safe_direction(launch_dir, Vector3.UP)
	if snap_to_center:
		global_position = origin
	_apply_directional_impulse(direction, strength, stop_momentum, additive_mode, min_additive_launch_speed, additive_mirrored_bounce_ratio, max_additive_launch_speed)
	if align_time > 0.0:
		var current_velocity: Vector3 = _get_object_velocity()
		_axis_lock_timer = max(align_time, 0.0)
		_axis_lock_direction = direction
		_axis_lock_speed = max(current_velocity.dot(direction), strength)
		_axis_lock_sideways_influence = clamp(sideways_gravity_influence, 0.0, 1.0)


func apply_dash_panel_impulse(
	_origin: Vector3,
	dash_dir: Vector3,
	strength: float,
	stop_momentum: bool,
	additive_mode: int,
	min_additive_launch_speed: float,
	_movement_lock_time: float = 0.0,
	_action_lock_time: float = 0.0,
	_align_camera_yaw_roll: bool = true,
	_panel_basis: Basis = Basis.IDENTITY,
	lock_speed_enabled: bool = false,
	lock_speed_value: float = 0.0,
	lock_speed_duration: float = 0.0,
	_override_max_speed: bool = false,
	_max_speed_override: float = 0.0,
	_max_speed_override_duration: float = 0.0,
	_match_y_position: bool = false,
	_override_previous_lock_timers: bool = true
) -> void:
	if is_carried():
		return
	_release_for_gimmick()
	var direction: Vector3 = _safe_direction(dash_dir, -global_transform.basis.z)
	_apply_directional_impulse(direction, strength, stop_momentum, additive_mode, min_additive_launch_speed)
	if lock_speed_enabled and lock_speed_duration > 0.0:
		_speed_lock_timer = max(lock_speed_duration, 0.0)
		_speed_lock_direction = direction
		_speed_lock_value = max(lock_speed_value, 0.0)


func apply_ramp_impulse(
	_origin: Vector3,
	ramp_forward: Vector3,
	ramp_up: Vector3,
	forward_speed: float,
	up_speed: float,
	additive_launch: bool = false,
	additive_min_forward_speed: float = 0.0,
	_movement_lock_time: float = 0.0,
	_action_lock_time: float = 0.0,
	_align_camera_yaw_roll: bool = true,
	hold_forward_time: float = 0.0,
	hold_up_time: float = 0.0
) -> void:
	if is_carried():
		return
	_release_for_gimmick()
	var forward: Vector3 = _safe_direction(ramp_forward, -global_transform.basis.z)
	var up: Vector3 = _safe_direction(ramp_up, Vector3.UP)
	var current_velocity: Vector3 = _get_object_velocity()
	var launch_velocity: Vector3 = forward * max(forward_speed, 0.0) + up * up_speed
	if additive_launch:
		var forward_component: float = max(current_velocity.dot(forward), 0.0) + max(forward_speed, 0.0)
		forward_component = max(forward_component, max(additive_min_forward_speed, 0.0))
		var side_velocity: Vector3 = current_velocity - forward * current_velocity.dot(forward) - up * current_velocity.dot(up)
		launch_velocity = side_velocity + forward * forward_component + up * up_speed
	_set_object_velocity(launch_velocity)
	if hold_forward_time > 0.0:
		_hold_forward_timer = max(hold_forward_time, 0.0)
		_hold_forward_direction = forward
		_hold_forward_speed = max(forward_speed, 0.0)
	if hold_up_time > 0.0:
		_hold_up_timer = max(hold_up_time, 0.0)
		_hold_up_direction = up
		_hold_up_speed = up_speed


func is_carried() -> bool:
	return _carry_state == CarryState.EASING_TO_CARRY or _carry_state == CarryState.CARRIED


func is_gravity_pull_enabled() -> bool:
	return follow_gravity_pull


func get_gravity_up() -> Vector3:
	if follow_gravity_pull:
		var resolved_up: Vector3 = _resolved_gravity_up.normalized()
		if resolved_up.length() >= 0.001:
			return resolved_up
	return _get_base_gravity_up()


func get_gravity_down() -> Vector3:
	return -get_gravity_up()


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
	if not follow_gravity_pull or source == null or new_gravity_up.length() < 0.001:
		return
	_gravity_modifier_sequence += 1
	var remaining: float = duration if duration > 0.0 else -1.0
	_gravity_modifiers[source.get_instance_id()] = {
		"up": new_gravity_up.normalized(),
		"multiplier": max(gravity_multiplier, 0.0),
		"remaining": remaining,
		"priority": priority,
		"sequence": _gravity_modifier_sequence,
		"blend_planetary": blend_with_planetary,
		"clear_on_death": clear_on_death,
		"clear_on_respawn": clear_on_respawn,
		"clear_on_level_restart": clear_on_level_restart,
		"clear_on_race_cleanup": clear_on_race_cleanup,
	}
	_update_gravity_pull_state(0.0)


func remove_gravity_modifier(source: Object) -> void:
	if source == null:
		return
	_gravity_modifiers.erase(source.get_instance_id())
	_update_gravity_pull_state(0.0)


func register_planetary_gravity_source(source: Node) -> void:
	if not follow_gravity_pull or source == null or not is_instance_valid(source):
		return
	if not source.has_method("get_planetary_gravity_vector"):
		return
	var source_id: int = source.get_instance_id()
	if _planetary_gravity_sources.has(source_id):
		return
	_planetary_gravity_sources[source_id] = weakref(source)
	_update_gravity_pull_state(0.0)


func unregister_planetary_gravity_source(source: Node) -> void:
	if source == null:
		return
	_planetary_gravity_sources.erase(source.get_instance_id())
	_update_gravity_pull_state(0.0)


func clear_gravity_state(reason: StringName = &"all", clear_planetary: bool = true) -> void:
	_clear_gravity_state(reason, clear_planetary)


func get_dynamic_impact_velocity() -> Vector3:
	if is_carried():
		return Vector3.ZERO
	return _get_object_velocity()


func respawn_carryable(_source: Node = null) -> bool:
	if not carry_respawn_enabled:
		return false
	var target_transform: Transform3D = _spawn_transform
	if carry_respawn_point and is_instance_valid(carry_respawn_point):
		target_transform = carry_respawn_point.global_transform
	clear_carry_owner()
	_remove_collision_exception()
	impact_instigator = null
	_clear_gravity_state(&"respawn", true)
	_clear_gimmick_state()
	_carry_state = CarryState.FREE
	_ease_timer = 0.0
	_simplified_resting = false
	_clear_rigid_rest_state()
	_stop_surface_slide_sound()
	global_transform = target_transform
	_manual_velocity = carry_respawn_velocity
	_apply_physics_attributes()
	_configure_physics_mode()
	if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		_store_surface_effect_previous_state()
		return true
	freeze = anchored
	sleeping = anchored
	linear_velocity = carry_respawn_velocity
	angular_velocity = carry_respawn_angular_velocity
	_store_surface_effect_previous_state()
	_reset_motion_history()
	return true


func _apply_physics_attributes() -> void:
	mass = max(carry_mass, 0.001)
	linear_damp = max(carry_linear_damp, 0.0)
	angular_damp = max(carry_angular_damp, 0.0)
	gravity_scale = 0.0 if follow_gravity_pull else max(carry_gravity_scale, 0.0)
	var physics_material: PhysicsMaterial = PhysicsMaterial.new()
	physics_material.friction = max(carry_friction, 0.0)
	physics_material.bounce = max(carry_bounce, 0.0)
	physics_material_override = physics_material


func _configure_physics_mode() -> void:
	_clear_rigid_rest_state()
	if anchored or fracture_template:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
		sleeping = true
	elif carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		continuous_cd = false
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		sleeping = true
	else:
		continuous_cd = carry_continuous_collision
		freeze = false
		sleeping = false
	_configure_surface_contact_monitor()


func _update_gravity_pull_state(delta: float) -> void:
	var previous_up: Vector3 = _resolved_gravity_up
	var previous_multiplier: float = _resolved_gravity_multiplier
	var expired_modifier_ids: Array = []
	var selected_modifier: Dictionary = {}
	var selected_priority: int = -2147483648
	var selected_sequence: int = -1
	for modifier_id in _gravity_modifiers.keys():
		var modifier_value: Variant = _gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			expired_modifier_ids.append(modifier_id)
			continue
		var modifier: Dictionary = modifier_value
		var remaining: float = float(modifier.get("remaining", -1.0))
		if remaining > 0.0 and delta > 0.0:
			remaining = max(remaining - delta, 0.0)
			modifier["remaining"] = remaining
			_gravity_modifiers[modifier_id] = modifier
			if remaining <= 0.0:
				expired_modifier_ids.append(modifier_id)
				continue
		var modifier_priority: int = int(modifier.get("priority", 0))
		var modifier_sequence: int = int(modifier.get("sequence", 0))
		if modifier_priority > selected_priority or (
			modifier_priority == selected_priority and modifier_sequence > selected_sequence
		):
			selected_modifier = modifier
			selected_priority = modifier_priority
			selected_sequence = modifier_sequence
	for modifier_id in expired_modifier_ids:
		_gravity_modifiers.erase(modifier_id)

	var planetary_vector: Vector3 = Vector3.ZERO
	var invalid_planetary_ids: Array = []
	for source_id in _planetary_gravity_sources.keys():
		var source_ref: Variant = _planetary_gravity_sources.get(source_id)
		if not (source_ref is WeakRef):
			invalid_planetary_ids.append(source_id)
			continue
		var source: Object = source_ref.get_ref()
		if source == null or not is_instance_valid(source) or not source.has_method("get_planetary_gravity_vector"):
			invalid_planetary_ids.append(source_id)
			continue
		var contribution_value: Variant = source.call("get_planetary_gravity_vector", self)
		if contribution_value is Vector3:
			var contribution: Vector3 = contribution_value
			planetary_vector += contribution
	for source_id in invalid_planetary_ids:
		_planetary_gravity_sources.erase(source_id)

	var base_up: Vector3 = _get_base_gravity_up()
	var gravity_down_vector: Vector3 = -base_up
	var preferred_zero_up: Vector3 = base_up
	if not selected_modifier.is_empty():
		var modifier_up_value: Variant = selected_modifier.get("up", base_up)
		var modifier_up: Vector3 = base_up
		if modifier_up_value is Vector3:
			modifier_up = modifier_up_value
		modifier_up = modifier_up.normalized()
		if modifier_up.length() < 0.001:
			modifier_up = base_up
		preferred_zero_up = modifier_up
		var modifier_multiplier: float = max(float(selected_modifier.get("multiplier", 1.0)), 0.0)
		gravity_down_vector = -modifier_up * modifier_multiplier
		if bool(selected_modifier.get("blend_planetary", false)):
			gravity_down_vector += planetary_vector
	elif planetary_vector.length() > 0.000001:
		gravity_down_vector = planetary_vector

	if gravity_down_vector.length() > 0.000001:
		_resolved_gravity_up = -gravity_down_vector.normalized()
		_resolved_gravity_multiplier = gravity_down_vector.length()
	else:
		_resolved_gravity_up = preferred_zero_up
		_resolved_gravity_multiplier = 0.0
	var up_changed: bool = previous_up.length() < 0.001 or previous_up.normalized().dot(_resolved_gravity_up) < 0.99999
	var multiplier_changed: bool = not is_equal_approx(previous_multiplier, _resolved_gravity_multiplier)
	if _gravity_change_should_wake(previous_up, previous_multiplier, up_changed, multiplier_changed):
		_wake_for_gravity_change()


func _get_base_gravity_up() -> Vector3:
	var up: Vector3 = simplified_up
	if up.length() < 0.001:
		up = Vector3.UP
	return up.normalized()


func _get_rigid_base_gravity_strength() -> float:
	var gravity_setting: Variant = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return max(float(gravity_setting), 0.0) * max(carry_gravity_scale, 0.0)


func _get_resolved_gravity_strength(base_strength: float) -> float:
	if not follow_gravity_pull:
		return max(base_strength, 0.0)
	return max(base_strength, 0.0) * max(_resolved_gravity_multiplier, 0.0)


func _gravity_change_should_wake(
	previous_up: Vector3,
	previous_multiplier: float,
	up_changed: bool,
	multiplier_changed: bool
) -> bool:
	if carry_physics_mode != CarryPhysicsMode.RIGID_BODY or is_carried() or not _rigid_support_valid:
		return up_changed or multiplier_changed
	var comparison_up: Vector3 = _rigid_rest_gravity_up
	var comparison_multiplier: float = _rigid_rest_gravity_multiplier
	if comparison_up.length() < 0.001:
		comparison_up = previous_up
		comparison_multiplier = previous_multiplier
	if comparison_up.length() < 0.001:
		return up_changed or multiplier_changed
	var up_tolerance_radians: float = deg_to_rad(max(carry_rest_gravity_up_tolerance_degrees, 0.0))
	var minimum_up_alignment: float = cos(up_tolerance_radians)
	if comparison_up.normalized().dot(_resolved_gravity_up) < minimum_up_alignment:
		return true
	var multiplier_scale: float = max(
		max(abs(comparison_multiplier), abs(_resolved_gravity_multiplier)),
		0.001
	)
	var multiplier_change_ratio: float = abs(
		_resolved_gravity_multiplier - comparison_multiplier
	) / multiplier_scale
	if multiplier_change_ratio > max(carry_rest_gravity_strength_tolerance, 0.0):
		return true
	return false


func _wake_for_gravity_change() -> void:
	_simplified_resting = false
	_clear_rigid_rest_state()
	if carry_physics_mode == CarryPhysicsMode.RIGID_BODY and not is_carried():
		sleeping = false


func _clear_gravity_state(reason: StringName, clear_planetary: bool) -> void:
	var modifier_ids: Array = _gravity_modifiers.keys()
	for modifier_id in modifier_ids:
		var modifier_value: Variant = _gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			_gravity_modifiers.erase(modifier_id)
			continue
		var modifier: Dictionary = modifier_value
		if _gravity_modifier_clears_for_reason(modifier, reason):
			_gravity_modifiers.erase(modifier_id)
	if clear_planetary:
		_planetary_gravity_sources.clear()
	_update_gravity_pull_state(0.0)


func _gravity_modifier_clears_for_reason(modifier: Dictionary, reason: StringName) -> bool:
	match reason:
		&"death":
			return bool(modifier.get("clear_on_death", true))
		&"respawn":
			return bool(modifier.get("clear_on_respawn", true))
		&"level_restart":
			return bool(modifier.get("clear_on_level_restart", true))
		&"race_cleanup":
			return bool(modifier.get("clear_on_race_cleanup", true))
		_:
			return true


func _set_carried_physics_state() -> void:
	_clear_rigid_rest_state()
	continuous_cd = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	sleeping = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _update_carry_ease(delta: float) -> void:
	var duration: float = max(carry_ease_time, 0.0)
	var t: float = 1.0
	if duration > 0.0:
		_ease_timer += delta
		t = clamp(_ease_timer / duration, 0.0, 1.0)
	var eased_t: float = 1.0 - pow(1.0 - t, max(carry_ease_power, 0.01))
	global_transform = _resolve_carry_transform(_ease_start_transform.interpolate_with(_carry_target_transform, eased_t))
	if t >= 1.0:
		_carry_state = CarryState.CARRIED
		global_transform = _resolve_carry_transform(_carry_target_transform)


func _update_simplified_physics(delta: float) -> void:
	if _throw_flight:
		_manual_velocity = _throw_flight.update_velocity(_manual_velocity, delta)
	if not _has_simplified_collision_shapes():
		_update_simplified_ray_physics(delta)
		return
	var up: Vector3 = get_gravity_up() if follow_gravity_pull else _get_base_gravity_up()
	if simplified_keep_upright:
		_apply_simplified_upright(up)
	var gravity_strength: float = _get_resolved_gravity_strength(maxf(simplified_gravity_strength, 0.0))
	var acceleration: Vector3 = -up * gravity_strength
	if buoyancy_component and buoyancy_enabled:
		var water: Dictionary = buoyancy_component.evaluate(global_transform, _manual_velocity, Vector3.ZERO, acceleration, mass, delta)
		acceleration += (water["force"] as Vector3) / maxf(mass, 0.001)
	var support: Dictionary = _get_simplified_shape_support(up)
	if _apply_simplified_support(support, up, acceleration, delta):
		return
	var distance: float = _manual_velocity.length() * maxf(delta, 0.0)
	var step_count: int = clampi(ceili(distance / maxf(simplified_max_sweep_step_distance, 0.01)), 1, 64)
	var step_delta: float = maxf(delta, 0.0) / float(step_count)
	for index: int in range(step_count):
		_move_simplified_shape_step(step_delta, up)
		if _manual_velocity.is_zero_approx():
			break


func _has_simplified_collision_shapes() -> bool:
	for owner_id: int in get_shape_owners():
		if not is_shape_owner_disabled(owner_id) and shape_owner_get_shape_count(owner_id) > 0:
			return true
	return false


func _get_simplified_shape_support(up: Vector3) -> Dictionary:
	if not _simplified_motion_parameters:
		_simplified_motion_parameters = PhysicsTestMotionParameters3D.new()
		_simplified_motion_result = PhysicsTestMotionResult3D.new()
	var parameters: PhysicsTestMotionParameters3D = _simplified_motion_parameters
	parameters.from = global_transform
	parameters.motion = -up * maxf(simplified_support_distance, 0.001)
	parameters.margin = maxf(simplified_collision_skin, 0.001)
	parameters.recovery_as_collision = true
	parameters.max_collisions = clampi(carry_rest_max_support_contacts, 1, 32)
	parameters.exclude_bodies = []
	if is_instance_valid(_collision_exception_body):
		parameters.exclude_bodies = [_collision_exception_body.get_rid()]
	var result: PhysicsTestMotionResult3D = _simplified_motion_result
	if not PhysicsServer3D.body_test_motion(get_rid(), parameters, result):
		return {}
	var best_index: int = -1
	var best_alignment: float = maxf(carry_rest_min_support_dot, 0.0)
	for index: int in range(result.get_collision_count()):
		var normal: Vector3 = result.get_collision_normal(index).normalized()
		var alignment: float = normal.dot(up)
		if alignment > best_alignment and result.get_collision_depth(index) <= maxf(simplified_collision_skin * 2.0, 0.01):
			best_index = index
			best_alignment = alignment
	if best_index < 0:
		return {}
	return {"normal": result.get_collision_normal(best_index).normalized(), "position": result.get_collision_point(best_index), "collider": result.get_collider(best_index), "velocity": result.get_collider_velocity(best_index), "travel": result.get_travel()}


func _simplified_collider_velocity(collider: Object, point: Vector3, fallback: Vector3) -> Vector3:
	if collider is ObjectPhysicsBody3D:
		return collider.get_dynamic_impact_velocity_at(point)
	return fallback


func _simplified_support_body_can_rest(collider: Object) -> bool:
	if not is_instance_valid(collider) or not collider is Node3D or not collider.is_inside_tree() or collider.is_queued_for_deletion():
		return false
	if collider is ObjectPhysicsBody3D:
		if collider.is_carried():
			return false
		if collider.anchored:
			return true
		if collider.carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
			return collider._simplified_resting and collider.get_dynamic_impact_velocity().is_zero_approx()
	if collider is RigidBody3D:
		return collider.freeze or (collider.sleeping and collider.linear_velocity.is_zero_approx() and collider.angular_velocity.is_zero_approx())
	return _rigid_support_body_can_rest(collider as Node3D)


func _apply_simplified_support(support: Dictionary, up: Vector3, acceleration: Vector3, delta: float) -> bool:
	var was_resting: bool = _simplified_resting
	_simplified_resting = false
	if support.is_empty():
		_manual_velocity += acceleration * delta
		return false
	var normal: Vector3 = support.normal
	var point: Vector3 = support.position
	var collider: Object = support.collider
	var support_velocity: Vector3 = _simplified_collider_velocity(collider, point, support.velocity)
	var relative: Vector3 = _manual_velocity - support_velocity
	var normal_speed: float = relative.dot(normal)
	var normal_acceleration: float = acceleration.dot(normal)
	var settling_speed: float = maxf(maxf(simplified_settle_speed, 0.0), maxf(-normal_acceleration, 0.0) * maxf(delta, 0.0) * 1.5)
	if normal_speed > maxf(simplified_sleep_speed, 0.0) or normal_speed < -settling_speed or normal_acceleration > 0.001:
		_manual_velocity += acceleration * delta
		return false
	# Support gaps require physical motion before settling.
	if (support.travel as Vector3).dot(-up) > maxf(simplified_collision_skin, 0.001) + 0.002:
		_manual_velocity += acceleration * delta
		return false
	var tangent: Vector3 = relative.slide(normal)
	var tangent_acceleration: Vector3 = acceleration.slide(normal)
	var normal_force: float = maxf(-normal_acceleration, 0.0)
	var static_friction: float = maxf(simplified_static_friction, simplified_friction)
	if tangent.length() <= maxf(simplified_sleep_speed, 0.0) and tangent_acceleration.length() <= normal_force * static_friction + 0.001 and _simplified_support_body_can_rest(collider):
		if not was_resting and -normal_speed >= maxf(surface_impact_min_speed, 0.0):
			_process_surface_effect_contact(point, normal, relative)
		_manual_velocity = Vector3.ZERO
		_simplified_resting = true
		_mark_surface_contact_without_effects(normal)
		return true
	if was_resting:
		_stop_surface_slide_sound()
	tangent += tangent_acceleration * delta
	tangent = tangent.move_toward(Vector3.ZERO, maxf(simplified_friction, 0.0) * normal_force * delta)
	_manual_velocity = support_velocity + tangent
	if tangent.length() >= maxf(surface_slide_min_speed, 0.0):
		_process_surface_effect_contact(point, normal, relative)
	return false


func _move_simplified_shape_step(delta: float, up: Vector3) -> void:
	var remaining_time: float = delta
	for index: int in range(maxi(simplified_max_slides, 1)):
		var motion: Vector3 = _manual_velocity * remaining_time
		if motion.length_squared() < 0.00000001:
			break
		var collision: KinematicCollision3D = move_and_collide(motion, false, maxf(simplified_collision_skin, 0.001), false, clampi(carry_rest_max_support_contacts, 1, 32))
		if not collision:
			break
		var fraction: float = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0.0, 1.0)
		remaining_time *= 1.0 - fraction
		for contact: int in range(collision.get_collision_count()):
			var normal: Vector3 = collision.get_normal(contact).normalized()
			var point: Vector3 = collision.get_position(contact)
			var collider: Object = collision.get_collider(contact)
			var support_velocity: Vector3 = _simplified_collider_velocity(collider, point, collision.get_collider_velocity(contact))
			var relative: Vector3 = _manual_velocity - support_velocity
			var closing_speed: float = -relative.dot(normal)
			if closing_speed <= 0.001:
				continue
			record_object_impact(point, normal, relative, collider as Node3D)
			_process_surface_effect_contact(point, normal, relative)
			var bounce_speed: float = closing_speed * maxf(simplified_bounce, 0.0)
			if closing_speed <= maxf(simplified_settle_speed, 0.0) or bounce_speed < maxf(simplified_sleep_speed, 0.0):
				bounce_speed = 0.0
			var tangent: Vector3 = relative.slide(normal)
			tangent = tangent.move_toward(Vector3.ZERO, maxf(simplified_friction, 0.0) * closing_speed)
			_manual_velocity = support_velocity + tangent + normal * bounce_speed
		if remaining_time < 0.00001:
			break


func _update_simplified_ray_physics(delta: float) -> void:
	var up: Vector3 = get_gravity_up() if follow_gravity_pull else _get_base_gravity_up()
	if simplified_keep_upright:
		_apply_simplified_upright(up)
	if not buoyancy_enabled and _simplified_ray_should_remain_at_rest(up):
		_manual_velocity = Vector3.ZERO
		_stop_surface_slide_sound()
		return
	_simplified_resting = false
	var gravity_strength: float = _get_resolved_gravity_strength(max(simplified_gravity_strength, 0.0))
	_manual_velocity -= up * gravity_strength * delta
	if buoyancy_component and buoyancy_enabled:
		var water: Dictionary = buoyancy_component.evaluate(global_transform, _manual_velocity, Vector3.ZERO, -up * gravity_strength, mass, delta)
		_manual_velocity += (water["force"] as Vector3) / mass * delta
	var motion: Vector3 = _manual_velocity * delta
	if motion.length() < 0.001:
		return
	var max_step_distance: float = max(simplified_max_sweep_step_distance, 0.01)
	var step_count: int = maxi(1, ceili(motion.length() / max_step_distance))
	var step_motion: Vector3 = motion / float(step_count)
	for _step_index: int in range(step_count):
		if not _move_simplified_ray_step(step_motion, up):
			return


func _apply_simplified_upright(up: Vector3) -> void:
	var forward: Vector3 = -global_transform.basis.z
	forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = _manual_velocity
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.RIGHT
		forward -= up * forward.dot(up)
	forward = forward.normalized()
	var upright_basis: Basis = Basis().looking_at(forward, up)
	if not global_basis.is_equal_approx(upright_basis):
		global_basis = upright_basis


func _move_simplified_ray_step(motion: Vector3, up: Vector3) -> bool:
	var start_position: Vector3 = global_position
	var target_position: Vector3 = start_position + motion
	var hit: Dictionary = _cast_simplified_motion(start_position, motion, up)
	if hit.is_empty():
		global_position = target_position
		_simplified_resting = false
		return true
	var hit_position: Vector3 = hit.get("position", target_position)
	var normal: Vector3 = hit.get("normal", up)
	if normal.length() < 0.001:
		normal = up
	normal = normal.normalized()
	record_object_impact(hit_position, normal, _manual_velocity, hit.get("collider") as Node3D)
	global_position = hit_position + normal * (max(simplified_collision_radius, 0.0) + max(simplified_collision_skin, 0.0))
	var normal_speed: float = _manual_velocity.dot(normal)
	var tangent_velocity: Vector3 = _manual_velocity - normal * normal_speed
	var bounce_speed: float = max(-normal_speed, 0.0) * simplified_bounce
	if bounce_speed < simplified_sleep_speed:
		bounce_speed = 0.0
	var damped_tangent_velocity: Vector3 = tangent_velocity * (1.0 - simplified_friction)
	var should_rest: bool = bounce_speed <= 0.0 and damped_tangent_velocity.length() <= max(simplified_sleep_speed, 0.0) and _simplified_support_can_rest(normal, up) and _rigid_support_body_can_rest(hit.get("collider") as Node3D)
	if not should_rest:
		_process_surface_effect_contact(global_position, normal, _manual_velocity)
		_manual_velocity = damped_tangent_velocity + normal * bounce_speed
	else:
		var impact_speed: float = abs(_manual_velocity.dot(normal))
		var slide_speed: float = tangent_velocity.length()
		if impact_speed >= max(surface_impact_min_speed, 0.0) or slide_speed >= max(surface_slide_min_speed, 0.0):
			_process_surface_effect_contact(global_position, normal, _manual_velocity)
		_manual_velocity = Vector3.ZERO
		_simplified_resting = true
		_stop_surface_slide_sound()
	return false


func _simplified_ray_should_remain_at_rest(up: Vector3) -> bool:
	if not _simplified_resting:
		return false
	if _manual_velocity.length() > max(simplified_sleep_speed, 0.0):
		return false
	var support_distance: float = max(simplified_collision_radius, 0.0) + max(simplified_collision_skin, 0.0) + 0.05
	var support_hit: Dictionary = _cast_simplified_ray(global_position, global_position - up * support_distance)
	if support_hit.is_empty():
		return false
	if not _rigid_support_body_can_rest(support_hit.get("collider") as Node3D):
		return false
	var contact_distance: float = global_position.distance_to(support_hit.get("position", global_position) as Vector3)
	if contact_distance > max(simplified_collision_radius, 0.0) + max(simplified_collision_skin, 0.0) * 2.0 + 0.001:
		return false
	var normal: Vector3 = support_hit.get("normal", up)
	if normal.length() < 0.001:
		normal = up
	normal = normal.normalized()
	return _simplified_support_can_rest(normal, up)


func _simplified_support_can_rest(normal: Vector3, up: Vector3) -> bool:
	var friction: float = maxf(maxf(simplified_friction, simplified_static_friction), 0.0)
	return normal.dot(up) >= max(carry_rest_min_support_dot, 1.0 / sqrt(1.0 + friction * friction))


func _update_rigid_rest_state(delta: float) -> void:
	if carry_physics_mode != CarryPhysicsMode.RIGID_BODY or is_carried():
		_clear_rigid_rest_state()
		return
	var up: Vector3 = get_gravity_up() if follow_gravity_pull else _get_base_gravity_up()
	var angular_speed: float = angular_velocity.length()
	var linear_limit: float = _get_rigid_rest_linear_limit(delta)
	var normal_speed: float = linear_velocity.dot(up)
	var tangent_speed: float = (linear_velocity - up * normal_speed).length()
	var motion_is_quiet: bool = tangent_speed <= max(carry_rest_linear_speed, 0.0) and normal_speed >= -linear_limit and normal_speed <= max(carry_rest_linear_speed, 0.0) and angular_speed <= max(carry_rest_angular_speed, 0.0)
	if not motion_is_quiet:
		var was_resting: bool = _rigid_resting
		_clear_rigid_rest_state()
		if was_resting:
			sleeping = false
		return
	if _rigid_resting:
		if not sleeping or global_transform != _rigid_rest_transform or not _rigid_cached_support_is_valid():
			_clear_rigid_rest_state()
			sleeping = false
			return
		_rigid_support_refresh_timer -= max(delta, 0.0)
		if _rigid_support_refresh_timer > 0.0:
			_mark_surface_contact_without_effects(_rigid_support_normal)
			return
	var support_hit: Dictionary = _get_rigid_rest_support_hit(up)
	var supported: bool = _is_rigid_rest_support_valid(support_hit, up)
	_rigid_support_valid = supported
	_rigid_rest_linear_limit = linear_limit
	_rigid_support_normal = support_hit.get("normal", up) if supported else Vector3.ZERO
	if not supported:
		var was_resting: bool = _rigid_resting
		_clear_rigid_rest_state()
		if was_resting:
			sleeping = false
		return
	if _rigid_rest_gravity_up.length() < 0.001:
		_rigid_rest_gravity_up = up
		_rigid_rest_gravity_multiplier = _resolved_gravity_multiplier
	if _rigid_resting:
		_rigid_support_refresh_timer = max(carry_rest_support_refresh_time, 0.0)
		_mark_surface_contact_without_effects(_rigid_support_normal)
		return
	var support_body: Node3D = support_hit.get("collider") as Node3D
	var support_changed: bool = support_body != _rigid_support_body or not _rigid_cached_support_is_valid()
	var position_changed: bool = global_position.distance_to(_rigid_rest_transform.origin) > max(carry_rest_position_tolerance, 0.0)
	var rotation_changed: bool = global_basis.get_rotation_quaternion().angle_to(_rigid_rest_transform.basis.get_rotation_quaternion()) > deg_to_rad(max(carry_rest_rotation_tolerance_degrees, 0.0))
	if _rigid_rest_timer <= 0.0 or support_changed or position_changed or rotation_changed:
		_rigid_rest_timer = 0.0
		_rigid_rest_transform = global_transform
		_rigid_support_body = support_body
		_rigid_support_transform = support_body.global_transform
		_rigid_support_shape = int(support_hit.get("shape", -1))
		if support_body is StaticBody3D and _rigid_support_shape >= 0:
			var owner_id: int = (support_body as StaticBody3D).shape_find_owner(_rigid_support_shape)
			_rigid_support_shape_transform = (support_body as StaticBody3D).shape_owner_get_transform(owner_id)
	_rigid_rest_timer += max(delta, 0.0)
	if _rigid_rest_timer < max(carry_rest_settle_time, 0.0):
		return
	_rigid_resting = true
	_rigid_rest_transform = global_transform
	_rigid_support_refresh_timer = max(carry_rest_support_refresh_time, 0.0)
	var settled_support_normal: Vector3 = support_hit.get("normal", up)
	_mark_surface_contact_without_effects(settled_support_normal)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true
	_stop_surface_slide_sound()


func _get_rigid_rest_support_hit(up: Vector3) -> Dictionary:
	var support_distance: float = max(carry_rest_support_extra_distance, 0.0)
	if support_distance <= 0.001:
		return {}
	var parameters: PhysicsTestMotionParameters3D = _rigid_rest_parameters
	parameters.from = global_transform
	parameters.motion = -up * support_distance
	parameters.margin = max(simplified_collision_skin, 0.0)
	parameters.max_collisions = clampi(carry_rest_max_support_contacts, 1, 32)
	parameters.recovery_as_collision = true
	if _collision_exception_body and is_instance_valid(_collision_exception_body):
		parameters.exclude_bodies = [_collision_exception_body.get_rid()]
	else:
		parameters.exclude_bodies = []
	var result: PhysicsTestMotionResult3D = _rigid_rest_result
	if not PhysicsServer3D.body_test_motion(get_rid(), parameters, result):
		return {}
	if result.get_travel().dot(-up) > max(simplified_collision_skin, 0.0) + 0.001:
		return {}
	var best_normal: Vector3 = Vector3.ZERO
	var best_alignment: float = -INF
	var best_index: int = -1
	var collision_count: int = result.get_collision_count()
	for collision_index: int in range(collision_count):
		var collision_normal: Vector3 = result.get_collision_normal(collision_index)
		if collision_normal.length() < 0.001:
			continue
		collision_normal = collision_normal.normalized()
		var alignment: float = collision_normal.dot(up)
		if alignment > best_alignment:
			best_alignment = alignment
			best_normal = collision_normal
			best_index = collision_index
	if best_normal.length() < 0.001:
		return {}
	return {"normal": best_normal, "collider": result.get_collider(best_index), "shape": result.get_collider_shape(best_index)}


func _is_rigid_rest_support_valid(support_hit: Dictionary, up: Vector3) -> bool:
	if support_hit.is_empty():
		return false
	var support_body: Node3D = support_hit.get("collider") as Node3D
	if not _rigid_support_body_can_rest(support_body):
		return false
	var normal: Vector3 = support_hit.get("normal", up)
	if normal.length() < 0.001:
		return false
	var friction: float = max(carry_friction, 0.0)
	var friction_min_dot: float = 1.0 / sqrt(1.0 + friction * friction)
	var minimum_dot: float = max(clamp(carry_rest_min_support_dot, -1.0, 1.0), friction_min_dot)
	if _rigid_support_valid:
		var support_angle: float = acos(clamp(minimum_dot, -1.0, 1.0))
		var hysteresis_angle: float = deg_to_rad(max(carry_rest_support_hysteresis_degrees, 0.0))
		minimum_dot = cos(min(support_angle + hysteresis_angle, PI))
	return normal.normalized().dot(up) >= minimum_dot


func _rigid_support_body_can_rest(body: Node3D) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion():
		return false
	if body is CSGShape3D:
		return (body as CSGShape3D).is_root_shape() and (body as CSGShape3D).use_collision
	if not body is StaticBody3D or body is AnimatableBody3D:
		return false
	var static_body: StaticBody3D = body as StaticBody3D
	return static_body.constant_linear_velocity.is_zero_approx() and static_body.constant_angular_velocity.is_zero_approx()


func _rigid_cached_support_is_valid() -> bool:
	if not is_instance_valid(_rigid_support_body) or not _rigid_support_body_can_rest(_rigid_support_body):
		return false
	if _rigid_support_body.global_transform != _rigid_support_transform:
		return false
	if _rigid_support_body is CSGShape3D:
		return ((_rigid_support_body as CSGShape3D).collision_layer & collision_mask) != 0
	var static_body: StaticBody3D = _rigid_support_body as StaticBody3D
	if not (static_body.collision_layer & collision_mask) or _rigid_support_shape < 0 or _rigid_support_shape >= PhysicsServer3D.body_get_shape_count(static_body.get_rid()):
		return false
	var owner_id: int = static_body.shape_find_owner(_rigid_support_shape)
	return not static_body.is_shape_owner_disabled(owner_id) and static_body.shape_owner_get_transform(owner_id) == _rigid_support_shape_transform


func _get_rigid_rest_linear_limit(delta: float) -> float:
	var base_strength: float = _get_rigid_base_gravity_strength()
	var gravity_step_speed: float = _get_resolved_gravity_strength(base_strength) * max(delta, 0.0)
	return max(max(carry_rest_linear_speed, 0.0), gravity_step_speed * 1.5)


func _clear_rigid_rest_state() -> void:
	_rigid_resting = false
	_rigid_rest_timer = 0.0
	_rigid_support_valid = false
	_rigid_rest_linear_limit = 0.0
	_rigid_support_normal = Vector3.ZERO
	_rigid_rest_gravity_up = Vector3.ZERO
	_rigid_rest_gravity_multiplier = 0.0
	_rigid_support_body = null
	_rigid_support_shape = -1
	_rigid_support_refresh_timer = 0.0


func _mark_surface_contact_without_effects(contact_normal: Vector3 = Vector3.ZERO) -> void:
	_surface_impact_contact_timer = max(
		_surface_impact_contact_timer,
		max(surface_impact_contact_reset_time, 0.0)
	)
	if contact_normal.length() >= 0.001:
		_surface_impact_contact_normal = contact_normal.normalized()
	_stop_surface_slide_sound()


func _configure_surface_contact_monitor() -> void:
	var effects_enabled: bool = surface_dust_scene != null or not surface_impact_sounds.is_empty() or not surface_slide_sounds.is_empty()
	if carry_physics_mode == CarryPhysicsMode.RIGID_BODY and effects_enabled:
		contact_monitor = true
		max_contacts_reported = max(max_contacts_reported, 4)


func _update_surface_effect_timers(delta: float) -> void:
	_surface_impact_effect_timer = max(_surface_impact_effect_timer - delta, 0.0)
	_surface_slide_effect_timer = max(_surface_slide_effect_timer - delta, 0.0)
	_surface_slide_sound_timer = max(_surface_slide_sound_timer - delta, 0.0)
	_surface_impact_contact_timer = max(_surface_impact_contact_timer - delta, 0.0)
	if _surface_impact_contact_timer <= 0.0:
		_surface_impact_contact_normal = Vector3.ZERO
	if _surface_slide_sound_timer <= 0.0:
		_stop_surface_slide_sound()


func _process_surface_effect_contact(contact_position: Vector3, normal: Vector3, object_velocity: Vector3) -> void:
	var safe_normal: Vector3 = normal
	if safe_normal.length() < 0.001:
		safe_normal = Vector3.UP
	safe_normal = safe_normal.normalized()
	var normal_changed: bool = (
		_surface_impact_contact_normal.length() < 0.001
		or _surface_impact_contact_normal.dot(safe_normal) < 0.5
	)
	var is_new_contact: bool = _surface_impact_contact_timer <= 0.0 or normal_changed
	_surface_impact_contact_timer = max(surface_impact_contact_reset_time, 0.0)
	_surface_impact_contact_normal = safe_normal
	if not _surface_effects_are_near_camera():
		return
	var impact_speed: float = abs(object_velocity.dot(safe_normal))
	var slide_speed: float = (object_velocity - safe_normal * object_velocity.dot(safe_normal)).length()
	if is_new_contact and impact_speed >= max(surface_impact_min_speed, 0.0) and _surface_impact_effect_timer <= 0.0:
		_emit_surface_dust(contact_position, safe_normal)
		_play_surface_impact_sound(contact_position, impact_speed)
		_surface_impact_effect_timer = max(surface_impact_effect_cooldown, 0.0)
	if slide_speed >= max(surface_slide_min_speed, 0.0):
		_update_surface_slide_sound(contact_position, slide_speed)
		if _surface_slide_effect_timer <= 0.0:
			_emit_surface_dust(contact_position, safe_normal)
			_surface_slide_effect_timer = max(surface_slide_effect_cooldown, 0.0)


func _process_rigid_surface_effect_probe(
	previous_position: Vector3,
	current_position: Vector3,
	previous_velocity: Vector3,
	current_velocity: Vector3
) -> void:
	if not surface_effect_rigid_probe_enabled:
		return
	if (
		_rigid_support_valid
		and current_velocity.length() <= _rigid_rest_linear_limit
		and previous_velocity.length() <= _rigid_rest_linear_limit
	):
		_process_surface_effect_contact(global_position, _rigid_support_normal, current_velocity)
		return
	var probe_velocity: Vector3 = current_velocity
	if previous_velocity.length_squared() > probe_velocity.length_squared():
		probe_velocity = previous_velocity
	var up: Vector3 = get_gravity_up() if follow_gravity_pull else _get_base_gravity_up()
	var motion: Vector3 = current_position - previous_position
	var probe_skin: float = _get_surface_effect_probe_skin(probe_velocity.length())
	var contact_probe_skin: float = max(probe_skin, max(simplified_collision_skin, 0.01))
	if motion.length() > 0.001:
		var sweep_hit: Dictionary = _cast_surface_effect_motion(previous_position, motion, up, contact_probe_skin)
		if not sweep_hit.is_empty():
			var sweep_position: Vector3 = sweep_hit.get("position", current_position)
			var sweep_normal: Vector3 = sweep_hit.get("normal", up)
			_process_surface_effect_contact(sweep_position, sweep_normal, probe_velocity)
			if not collision_safety_enabled:
				_apply_rigid_surface_safety_hit(sweep_hit, up, probe_velocity)
			current_position = global_position
			current_velocity = _get_object_velocity()
	var support_distance: float = max(simplified_collision_radius, 0.0) + contact_probe_skin
	var support_hit: Dictionary = _cast_surface_effect_ray(current_position, current_position - up * support_distance)
	if support_hit.is_empty():
		return
	var support_position: Vector3 = support_hit.get("position", current_position)
	var support_normal: Vector3 = support_hit.get("normal", up)
	var support_velocity: Vector3 = current_velocity
	if probe_velocity.length_squared() > support_velocity.length_squared():
		support_velocity = probe_velocity
	_process_surface_effect_contact(support_position, support_normal, support_velocity)


func _get_surface_effect_probe_skin(speed: float) -> float:
	if not surface_effect_probe_skin_enabled:
		return 0.0
	var min_skin: float = max(surface_effect_probe_skin, 0.0)
	var max_skin: float = max(surface_effect_probe_max_skin, min_skin)
	var max_speed: float = max(surface_effect_probe_max_speed, 0.001)
	var t: float = clamp(max(speed, 0.0) / max_speed, 0.0, 1.0)
	return lerp(min_skin, max_skin, t)


func _apply_rigid_surface_safety_hit(hit: Dictionary, fallback_normal: Vector3, object_velocity: Vector3) -> void:
	var normal: Vector3 = hit.get("normal", fallback_normal)
	if normal.length() < 0.001:
		normal = fallback_normal
	if normal.length() < 0.001:
		normal = Vector3.UP
	normal = normal.normalized()
	var normal_speed: float = object_velocity.dot(normal)
	if normal_speed >= -max(surface_effect_probe_correction_min_speed, 0.0):
		return
	var hit_position: Vector3 = hit.get("position", global_position)
	var origin_offset: Vector3 = hit.get("origin_offset", Vector3.ZERO)
	var correction_distance: float = max(simplified_collision_skin, 0.0)
	if origin_offset.length() < 0.001:
		correction_distance += max(simplified_collision_radius, 0.0)
	global_position = hit_position - origin_offset + normal * correction_distance
	var tangent_velocity: Vector3 = object_velocity - normal * normal_speed
	var bounce_speed: float = max(-normal_speed, 0.0) * max(carry_bounce, 0.0)
	var adjusted_velocity: Vector3 = tangent_velocity * (1.0 - clamp(carry_friction, 0.0, 1.0)) + normal * bounce_speed
	_set_object_velocity(adjusted_velocity)


func _surface_effects_are_near_camera() -> bool:
	var max_distance: float = max(surface_effect_camera_distance, 0.0)
	if max_distance <= 0.0:
		return true
	var camera: Node3D = _get_surface_effect_camera()
	if camera == null:
		return true
	return camera.global_position.distance_squared_to(global_position) <= max_distance * max_distance


func _get_surface_effect_camera() -> Node3D:
	if surface_effect_camera and is_instance_valid(surface_effect_camera):
		return surface_effect_camera
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()


func _emit_surface_dust(contact_position: Vector3, normal: Vector3) -> void:
	if surface_dust_scene == null:
		return
	var dust: Node = surface_dust_scene.instantiate()
	if dust == null:
		return
	var parent: Node = get_parent()
	if parent == null:
		parent = self
	parent.add_child(dust)
	if dust is Node3D:
		var dust_node: Node3D = dust as Node3D
		dust_node.top_level = true
		dust_node.global_transform = _get_surface_effect_transform(contact_position, normal)
	_restart_particles_on_node(dust)
	var tree: SceneTree = get_tree()
	if tree != null:
		var timer: SceneTreeTimer = tree.create_timer(max(surface_dust_cleanup_time, 0.05))
		timer.timeout.connect(func() -> void:
			if is_instance_valid(dust):
				dust.queue_free()
		)


func _get_surface_effect_transform(contact_position: Vector3, normal: Vector3) -> Transform3D:
	var up: Vector3 = normal
	if up.length() < 0.001:
		up = Vector3.UP
	up = up.normalized()
	var forward: Vector3 = -global_transform.basis.z
	forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = global_transform.basis.x
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	return Transform3D(Basis().looking_at(forward, up), contact_position)


func _restart_particles_on_node(node: Node) -> void:
	if node is GPUParticles3D:
		var gpu_particles: GPUParticles3D = node as GPUParticles3D
		gpu_particles.restart()
		gpu_particles.emitting = true
	elif node is CPUParticles3D:
		var cpu_particles: CPUParticles3D = node as CPUParticles3D
		cpu_particles.restart()
		cpu_particles.emitting = true
	for child: Node in node.get_children():
		_restart_particles_on_node(child)


func _play_surface_impact_sound(contact_position: Vector3, strength: float) -> void:
	if surface_impact_sounds.is_empty():
		return
	var index: int = _get_random_surface_sound_index(surface_impact_sounds, true)
	var stream: AudioStream = surface_impact_sounds[index]
	if stream == null:
		return
	var player: AudioStreamPlayer3D = surface_impact_sfx_player
	var temporary_player: bool = false
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer3D.new()
		temporary_player = true
	player.stream = stream
	player.volume_db = _get_surface_sound_volume(strength, surface_impact_min_speed)
	player.pitch_scale = max(1.0 + randf_range(-surface_sound_pitch_random, surface_sound_pitch_random), 0.01)
	player.bus = String(surface_sound_bus)
	if temporary_player:
		player.autoplay = true
		var parent: Node = get_parent()
		if parent == null:
			parent = self
		parent.add_child(player)
		player.top_level = true
	player.global_position = contact_position
	player.play()
	if temporary_player:
		player.finished.connect(func() -> void:
			if is_instance_valid(player):
				player.queue_free()
		)


func _update_surface_slide_sound(contact_position: Vector3, strength: float) -> void:
	if surface_slide_sounds.is_empty():
		return
	var player: AudioStreamPlayer3D = _get_surface_slide_player()
	if player == null:
		return
	_surface_slide_sound_timer = max(surface_slide_sound_stop_delay, 0.0)
	player.global_position = contact_position
	player.volume_db = _get_surface_sound_volume(strength, surface_slide_min_speed)
	player.bus = String(surface_sound_bus)
	if player.playing and player.stream != null:
		return
	var index: int = _get_random_surface_sound_index(surface_slide_sounds, false)
	var stream: AudioStream = surface_slide_sounds[index]
	if stream == null:
		return
	player.stream = stream
	player.pitch_scale = max(1.0 + randf_range(-surface_sound_pitch_random, surface_sound_pitch_random), 0.01)
	player.play()


func _get_surface_slide_player() -> AudioStreamPlayer3D:
	if surface_slide_sfx_player and is_instance_valid(surface_slide_sfx_player):
		return surface_slide_sfx_player
	if _temporary_surface_slide_player and is_instance_valid(_temporary_surface_slide_player):
		return _temporary_surface_slide_player
	_temporary_surface_slide_player = AudioStreamPlayer3D.new()
	var parent: Node = get_parent()
	if parent == null:
		parent = self
	parent.add_child(_temporary_surface_slide_player)
	_temporary_surface_slide_player.top_level = true
	return _temporary_surface_slide_player


func _stop_surface_slide_sound() -> void:
	var player: AudioStreamPlayer3D = null
	if surface_slide_sfx_player and is_instance_valid(surface_slide_sfx_player):
		player = surface_slide_sfx_player
	elif _temporary_surface_slide_player and is_instance_valid(_temporary_surface_slide_player):
		player = _temporary_surface_slide_player
	if player == null:
		return
	if player.playing:
		player.stop()
	_surface_slide_sound_timer = 0.0


func _get_random_surface_sound_index(sounds: Array[AudioStream], is_impact: bool) -> int:
	var last_index: int = _last_surface_impact_sound_index if is_impact else _last_surface_slide_sound_index
	var index: int = 0
	if sounds.size() > 1 and last_index >= 0:
		index = randi_range(0, sounds.size() - 2)
		if index >= last_index:
			index += 1
	else:
		index = randi_range(0, sounds.size() - 1)
	if is_impact:
		_last_surface_impact_sound_index = index
	else:
		_last_surface_slide_sound_index = index
	return index


func _get_surface_sound_volume(strength: float, minimum_speed: float) -> float:
	var min_speed: float = max(minimum_speed, 0.0)
	var max_speed: float = max(surface_sound_max_speed, min_speed + 0.001)
	var t: float = clamp((strength - min_speed) / (max_speed - min_speed), 0.0, 1.0)
	return lerp(surface_sound_min_volume_db, surface_sound_max_volume_db, t)


func _cast_simplified_motion(start_position: Vector3, motion: Vector3, up: Vector3) -> Dictionary:
	var radius: float = max(simplified_collision_radius, 0.0)
	var motion_direction: Vector3 = _safe_direction(motion, -up)
	var side: Vector3 = motion_direction.cross(up)
	if side.length() < 0.001:
		side = motion_direction.cross(Vector3.RIGHT)
	if side.length() < 0.001:
		side = motion_direction.cross(Vector3.FORWARD)
	side = side.normalized()
	var forward_offset: Vector3 = motion_direction * radius
	var side_offset: Vector3 = side * radius
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		-up * radius,
		forward_offset,
		-forward_offset,
		side_offset,
		-side_offset,
	]
	var best_hit: Dictionary = {}
	var best_distance: float = INF
	for offset: Vector3 in offsets:
		var hit: Dictionary = _cast_simplified_ray(start_position + offset, start_position + offset + motion)
		if hit.is_empty():
			continue
		var hit_position: Vector3 = hit.get("position", start_position)
		var hit_distance: float = start_position.distance_to(hit_position)
		if hit_distance < best_distance:
			best_distance = hit_distance
			best_hit = hit
	return best_hit


func _cast_simplified_ray(from_position: Vector3, to_position: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = _simplified_ray_query
	query.from = from_position
	query.to = to_position
	query.collision_mask = simplified_ground_collision_mask
	var excluded_rids: Array[RID] = [get_rid()]
	if _collision_exception_body and is_instance_valid(_collision_exception_body):
		excluded_rids.append(_collision_exception_body.get_rid())
	query.exclude = excluded_rids
	return get_world_3d().direct_space_state.intersect_ray(query)


func _cast_surface_effect_motion(start_position: Vector3, motion: Vector3, up: Vector3, probe_skin: float) -> Dictionary:
	var radius: float = max(simplified_collision_radius, 0.0)
	var motion_direction: Vector3 = _safe_direction(motion, -up)
	var side: Vector3 = motion_direction.cross(up)
	if side.length() < 0.001:
		side = motion_direction.cross(Vector3.RIGHT)
	if side.length() < 0.001:
		side = motion_direction.cross(Vector3.FORWARD)
	side = side.normalized()
	var skin: float = max(probe_skin, 0.0)
	var forward_offset: Vector3 = motion_direction * radius
	var side_offset: Vector3 = side * radius
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		-up * radius,
		forward_offset,
		-forward_offset,
		side_offset,
		-side_offset,
	]
	var best_hit: Dictionary = {}
	var best_distance: float = INF
	for offset: Vector3 in offsets:
		var hit: Dictionary = _cast_surface_effect_ray(start_position + offset, start_position + offset + motion + motion_direction * skin)
		if hit.is_empty():
			continue
		hit["origin_offset"] = offset
		var hit_position: Vector3 = hit.get("position", start_position)
		var hit_distance: float = start_position.distance_to(hit_position)
		if hit_distance < best_distance:
			best_distance = hit_distance
			best_hit = hit
	return best_hit


func _cast_surface_effect_ray(from_position: Vector3, to_position: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = _surface_ray_query
	query.from = from_position
	query.to = to_position
	query.collision_mask = surface_effect_collision_mask
	var excluded_rids: Array[RID] = [get_rid()]
	if _collision_exception_body and is_instance_valid(_collision_exception_body):
		excluded_rids.append(_collision_exception_body.get_rid())
	query.exclude = excluded_rids
	return get_world_3d().direct_space_state.intersect_ray(query)


func _store_surface_effect_previous_state() -> void:
	_surface_previous_position = global_position
	_surface_previous_velocity = _get_object_velocity()


func _update_gimmick_velocity(delta: float) -> void:
	var current_velocity: Vector3 = _get_object_velocity()
	var velocity_changed: bool = false
	if _axis_lock_timer > 0.0 and _axis_lock_direction.length() > 0.001:
		_axis_lock_timer = max(_axis_lock_timer - delta, 0.0)
		var side_velocity: Vector3 = current_velocity - _axis_lock_direction * current_velocity.dot(_axis_lock_direction)
		current_velocity = _axis_lock_direction * _axis_lock_speed + side_velocity * _axis_lock_sideways_influence
		velocity_changed = true
	if _speed_lock_timer > 0.0 and _speed_lock_direction.length() > 0.001:
		_speed_lock_timer = max(_speed_lock_timer - delta, 0.0)
		var side_velocity_speed_lock: Vector3 = current_velocity - _speed_lock_direction * current_velocity.dot(_speed_lock_direction)
		current_velocity = side_velocity_speed_lock + _speed_lock_direction * _speed_lock_value
		velocity_changed = true
	if _hold_forward_timer > 0.0 and _hold_forward_direction.length() > 0.001:
		_hold_forward_timer = max(_hold_forward_timer - delta, 0.0)
		current_velocity = _replace_velocity_component(current_velocity, _hold_forward_direction, _hold_forward_speed)
		velocity_changed = true
	if _hold_up_timer > 0.0 and _hold_up_direction.length() > 0.001:
		_hold_up_timer = max(_hold_up_timer - delta, 0.0)
		current_velocity = _replace_velocity_component(current_velocity, _hold_up_direction, _hold_up_speed)
		velocity_changed = true
	if velocity_changed:
		_set_object_velocity(current_velocity)


func _apply_directional_impulse(direction: Vector3, strength: float, stop_momentum: bool, additive_mode: int, min_additive_launch_speed: float, mirrored_bounce_ratio: float = 0.0, max_launch_speed: float = 0.0) -> void:
	stop_throw_assistance()
	var launch_speed: float = max(strength, 0.0)
	var current_velocity: Vector3 = _get_object_velocity()
	var new_velocity: Vector3 = direction * launch_speed
	var inward_speed: float = min(current_velocity.dot(direction), 0.0)
	if stop_momentum:
		new_velocity = direction * launch_speed
	elif additive_mode == 1:
		new_velocity = current_velocity + direction * launch_speed
	else:
		var side_velocity: Vector3 = current_velocity - direction * current_velocity.dot(direction)
		new_velocity = side_velocity + direction * launch_speed

	var bounce_ratio: float = max(mirrored_bounce_ratio, 0.0)
	var along_speed: float = new_velocity.dot(direction)
	if not stop_momentum:
		along_speed = max(along_speed, min_additive_launch_speed)
	if inward_speed < 0.0 and bounce_ratio > 0.0:
		var mirrored_speed: float = -inward_speed
		if bounce_ratio <= 1.0:
			along_speed = lerp(along_speed, mirrored_speed, bounce_ratio)
		else:
			along_speed = mirrored_speed * bounce_ratio
	if max_launch_speed > 0.0:
		along_speed = min(along_speed, max_launch_speed)
	new_velocity += direction * (along_speed - new_velocity.dot(direction))
	_set_object_velocity(new_velocity)


func _release_for_gimmick() -> void:
	stop_throw_assistance()
	if _carry_state != CarryState.FREE:
		_carry_state = CarryState.FREE
		_apply_physics_attributes()
		_configure_physics_mode()
	_simplified_resting = false
	_clear_rigid_rest_state()
	sleeping = false


func _clear_gimmick_state() -> void:
	_axis_lock_timer = 0.0
	_axis_lock_direction = Vector3.ZERO
	_axis_lock_speed = 0.0
	_axis_lock_sideways_influence = 0.0
	_speed_lock_timer = 0.0
	_speed_lock_direction = Vector3.ZERO
	_speed_lock_value = 0.0
	_hold_forward_timer = 0.0
	_hold_forward_direction = Vector3.ZERO
	_hold_forward_speed = 0.0
	_hold_up_timer = 0.0
	_hold_up_direction = Vector3.ZERO
	_hold_up_speed = 0.0


func _get_object_velocity() -> Vector3:
	if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		return _manual_velocity
	return linear_velocity


func _set_object_velocity(value: Vector3) -> void:
	if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		_manual_velocity = value
		return
	_clear_rigid_rest_state()
	freeze = false
	sleeping = false
	linear_velocity = value


func _replace_velocity_component(current_velocity: Vector3, direction: Vector3, speed: float) -> Vector3:
	var safe_direction: Vector3 = _safe_direction(direction, Vector3.UP)
	var side_velocity: Vector3 = current_velocity - safe_direction * current_velocity.dot(safe_direction)
	return side_velocity + safe_direction * speed


func _safe_direction(value: Vector3, fallback: Vector3) -> Vector3:
	var direction: Vector3 = value
	if direction.length() < 0.001:
		direction = fallback
	if direction.length() < 0.001:
		direction = Vector3.UP
	return direction.normalized()


func _set_collision_exception(body: PhysicsBody3D, lock_time: float) -> void:
	if _collision_exception_body and is_instance_valid(_collision_exception_body) and _collision_exception_body != body:
		_remove_collision_exception()
	_collision_exception_body = body
	_collision_exception_timer = max(_collision_exception_timer, lock_time)
	add_collision_exception_with(body)
	body.add_collision_exception_with(self)


func _update_collision_exception_timer(delta: float) -> void:
	if not is_instance_valid(_collision_exception_body):
		_collision_exception_body = null
		_collision_exception_timer = 0.0
		return
	if is_carried():
		return
	_collision_exception_timer = max(_collision_exception_timer - delta, 0.0)
	if _collision_exception_timer > 0.0 or _overlaps_release_owner():
		return
	_remove_collision_exception()


func is_release_contact_ignored(source: Node3D) -> bool:
	return is_instance_valid(source) and source == _collision_exception_body


func _overlaps_release_owner() -> bool:
	if not _collision_exception_body.is_inside_tree():
		return false
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.collision_mask = _collision_exception_body.collision_layer
	query.margin = 0.02
	query.exclude = [get_rid()]
	for child: Node in get_children():
		if not child is CollisionShape3D or child.disabled or not child.shape:
			continue
		query.shape = child.shape
		query.transform = child.global_transform
		for overlap: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 256):
			if overlap.get("collider") == _collision_exception_body:
				return true
	return false


func _remove_collision_exception() -> void:
	if _collision_exception_body and is_instance_valid(_collision_exception_body):
		remove_collision_exception_with(_collision_exception_body)
		_collision_exception_body.remove_collision_exception_with(self)
	_collision_exception_body = null
	_collision_exception_timer = 0.0


func apply_kick_impulse(impulse: Vector3, instigator: Node3D = null) -> bool:
	if is_carried() or (carry_physics_mode == CarryPhysicsMode.RIGID_BODY and freeze):
		return false
	stop_throw_assistance()
	if is_instance_valid(instigator) and impulse.length() >= influence_minimum_impulse and not impulse.is_zero_approx():
		set_influence_owner(instigator)
	_simplified_resting = false
	_clear_rigid_rest_state()
	if carry_physics_mode == CarryPhysicsMode.SIMPLIFIED:
		_manual_velocity += impulse / max(carry_mass, 0.001)
	else:
		sleeping = false
		apply_central_impulse(impulse)
	return true


func set_influence_owner(instigator: Node3D) -> void:
	if not is_instance_valid(instigator) or instigator.is_queued_for_deletion():
		clear_influence_owner()
		return
	_influence_owner = weakref(instigator)
	_influence_remaining = maxf(influence_duration, 0.0)


func clear_influence_owner() -> void:
	_influence_owner = null
	_influence_remaining = 0.0


func get_score_award_recipient() -> Node3D:
	var instigator: Node3D = _influence_owner.get_ref() as Node3D if _influence_owner else null
	if not is_instance_valid(instigator) or not instigator.is_inside_tree() or instigator.is_queued_for_deletion():
		clear_influence_owner()
		return null
	if influence_duration > 0.0 and _influence_remaining <= 0.0 and not is_carried():
		clear_influence_owner()
		return null
	if instigator.has_method("_network_is_local_authority") and not instigator.call("_network_is_local_authority"):
		return null
	return instigator


func _update_influence_ownership(delta: float) -> void:
	if not _influence_owner:
		return
	get_score_award_recipient()
	if not _influence_owner or is_carried() or influence_duration <= 0.0:
		return
	_influence_remaining = maxf(_influence_remaining - maxf(delta, 0.0), 0.0)
	if _influence_remaining <= 0.0:
		clear_influence_owner()


func clear_carry_owner() -> void:
	stop_throw_assistance()
	_restore_carry_collisions()
	if is_instance_valid(carry_holder) and carry_holder.get("_carried_object") == self:
		carry_holder.set("_carried_object", null)
		var controller: Variant = carry_holder.get("_carry_module")
		if controller:
			controller._clear_pending_carry_put_down()
			controller._clear_pending_carry_throw()
	carry_holder = null
	_carry_state = CarryState.FREE


func _exit_tree() -> void:
	clear_carry_owner()
	_remove_collision_exception()


func _apply_water_forces(state: PhysicsDirectBodyState3D) -> void:
	if not buoyancy_component or not buoyancy_enabled:
		return
	var gravity: Vector3 = -get_gravity_up() * _get_resolved_gravity_strength(_get_rigid_base_gravity_strength())
	var water: Dictionary = buoyancy_component.evaluate(state.transform, state.linear_velocity, state.angular_velocity, gravity, mass, state.step)
	var force: Vector3 = water["force"]
	if buoyancy_component.submerged_fraction > 0.0:
		_clear_rigid_rest_state()
		state.sleeping = false
		state.apply_central_force(force)
		state.apply_torque(water["torque"])
		state.angular_velocity *= float(water.get("angular_retention", 1.0))


func get_prop_gravity_vector() -> Vector3:
	return -get_gravity_up() * _get_resolved_gravity_strength(_get_rigid_base_gravity_strength())


func _restore_carry_collisions() -> void:
	if not _carry_collisions_suspended:
		return
	collision_layer = _carry_collision_layer
	collision_mask = _carry_collision_mask
	_carry_collisions_suspended = false


func _resolve_carry_transform(target: Transform3D) -> Transform3D:
	return target if _carry_collisions_suspended else _safe_carry_transform(target)


func is_carry_placement_clear(target: Transform3D, margin: float, nudge: Vector3, excludes: Array[RID]) -> bool:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.collision_mask = _carry_collision_mask if _carry_collisions_suspended else collision_mask
	query.margin = margin
	query.exclude = excludes.duplicate()
	query.exclude.append(get_rid())
	for child: Node in get_children():
		if not child is CollisionShape3D or child.disabled or not child.shape:
			continue
		query.shape = child.shape
		query.transform = target * child.transform
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
		query.transform.origin += nudge
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func _safe_carry_transform(target: Transform3D) -> Transform3D:
	var parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	parameters.from = global_transform
	parameters.motion = target.origin - global_position
	parameters.margin = 0.02
	if is_instance_valid(carry_holder) and carry_holder is PhysicsBody3D:
		parameters.exclude_bodies = [carry_holder.get_rid()]
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	var safe: Transform3D = target
	if PhysicsServer3D.body_test_motion(get_rid(), parameters, result):
		safe.origin = global_position + result.get_travel()
		return Transform3D(global_basis, safe.origin)
	parameters.from = target
	parameters.motion = Vector3.ZERO
	parameters.recovery_as_collision = true
	if PhysicsServer3D.body_test_motion(get_rid(), parameters, result):
		safe.basis = global_basis
	return safe


func _make_buoyancy_samples() -> Array[PropBuoyancySample]:
	var points: Array[PropBuoyancySample] = []
	for child: Node in get_children():
		if not child is CollisionShape3D or not child.shape or child.disabled or child.is_queued_for_deletion():
			continue
		var bounds: AABB
		var shape: Shape3D = child.shape
		if shape is BoxShape3D:
			bounds = AABB(-shape.size * 0.5, shape.size)
		elif shape is SphereShape3D:
			bounds = AABB(-Vector3.ONE * shape.radius, Vector3.ONE * shape.radius * 2.0)
		elif shape is CapsuleShape3D or shape is CylinderShape3D:
			var size: Vector3 = Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0)
			bounds = AABB(-size * 0.5, size)
		elif shape is ConvexPolygonShape3D and not shape.points.is_empty():
			bounds = AABB(shape.points[0], Vector3.ZERO)
			for point: Vector3 in shape.points:
				bounds = bounds.expand(point)
		else:
			continue
		var volume: float = bounds.get_volume()
		for index: int in range(8):
			var sample: PropBuoyancySample = PropBuoyancySample.new()
			var corner: Vector3 = bounds.get_endpoint(index)
			sample.position = child.transform * bounds.get_center().lerp(corner, 0.75)
			sample.radius = maxf(bounds.size[bounds.size.min_axis_index()] * 0.25, 0.02)
			sample.weight = maxf(volume / 8.0, 0.001)
			points.append(sample)
	return points


func _reset_motion_history() -> void:
	var safety: ObjectMotionSafety3D = get_node_or_null("MotionSafety") as ObjectMotionSafety3D
	if safety:
		safety.reset_history()


func _refresh_buoyancy_samples() -> void:
	if buoyancy_component:
		buoyancy_component.samples = buoyancy_samples if not buoyancy_samples.is_empty() else _make_buoyancy_samples()


func record_object_impact(_point: Vector3, normal: Vector3, relative_velocity: Vector3, collider: Node3D) -> void:
	stop_throw_assistance()
	var recipient: Node3D = get_score_award_recipient()
	if is_carried() or not is_instance_valid(collider) or not recipient:
		return
	var receiver: Node = collider
	if not receiver.has_method("receive_object_impact"):
		receiver = receiver.get_parent()
	if receiver and receiver.has_method("receive_object_impact"):
		var source_reference: WeakRef = weakref(self)
		var recipient_reference: WeakRef = weakref(recipient)
		var receiver_reference: WeakRef = weakref(receiver)
		var deliver: Callable = func() -> void:
			var source: Node3D = source_reference.get_ref() as Node3D
			var beneficiary: Node3D = recipient_reference.get_ref() as Node3D
			var target: Node = receiver_reference.get_ref() as Node
			if is_instance_valid(source) and is_instance_valid(beneficiary) and is_instance_valid(target):
				target.call("receive_object_impact", source, relative_velocity, normal, beneficiary)
		deliver.call_deferred()


func get_dynamic_impact_velocity_at(point: Vector3) -> Vector3:
	if is_carried():
		return Vector3.ZERO
	return _get_object_velocity() + angular_velocity.cross(point - global_position)

class_name SpringAction
extends CharacterAction

@export_group("Spring")

@export_subgroup("State")
## Gravity scale applied while the spring state is active and airborne.
@export var spring_gravity_scale: float = 1.8
## Ends an unlocked spring state when speed falls below the configured threshold.
@export var spring_exit_on_low_speed: bool = true
## Speed below which an unlocked spring state ends.
@export var spring_exit_speed_threshold: float = 5.0

@export_subgroup("Visual Alignment")
## Duration used to snap the character model toward the launch direction.
@export var spring_model_snap_time: float = 0.12

@export_subgroup("Spline")
## Additional model pitch applied during spline travel.
@export var spline_model_pitch_deg: float = 90.0

var movement_lock_timer: float = 0.0
var action_lock_timer: float = 0.0
var align_timer: float = 0.0
var align_dir: Vector3 = Vector3.ZERO
var lock_sideways: bool = false
var sideways_gravity_scale: float = 0.0
var cancel_on_ground: bool = true
var align_up: Vector3 = Vector3.ZERO
var align_forward: Vector3 = Vector3.ZERO
var clear_move_on_ground: bool = false
var clear_action_on_ground: bool = false
var detached: bool = false
var align_model: bool = false
var model_snap_timer: float = 0.0
var trajectory_torque_active: bool = false
var trajectory_torque_align_speed_deg: float = 720.0


func _on_action_initialized() -> void:
	action_id = &"spring"
	input_action = &""
	continuous_update = false
	allow_when_inactive = true


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func continuous_physics_update(delta: float) -> void:
	movement_lock_timer = max(movement_lock_timer - delta, 0.0)
	action_lock_timer = max(action_lock_timer - delta, 0.0)


func advance_alignment(delta: float) -> void:
	align_timer = max(align_timer - delta, 0.0)
	model_snap_timer = max(model_snap_timer - delta, 0.0)
	if align_timer <= 0.0:
		model_snap_timer = 0.0


func is_in_spring_state() -> bool:
	return align_timer > 0.0 or movement_lock_timer > 0.0


func apply_impulse(
	spring_position: Vector3,
	spring_direction: Vector3,
	spring_strength: float,
	snap_to_center: bool,
	stop_momentum: bool,
	additive_mode: int,
	min_additive_launch_speed: float,
	additive_mirrored_bounce_ratio: float,
	max_additive_launch_speed: float,
	p_movement_lock_time: float,
	p_action_lock_time: float,
	align_time: float,
	spring_basis: Basis,
	p_clear_move_on_ground: bool,
	p_clear_action_on_ground: bool,
	lock_horizontal_during_align: bool,
	p_sideways_gravity_scale: float,
	detach_from_ground: bool,
	align_model_during_spring: bool,
	preserve_active_flight: bool = false,
	flight_time_bonus: float = 0.0,
	downward_trajectory_torque_enabled: bool = true,
	downward_trajectory_min_angle_deg: float = 45.0,
	downward_trajectory_align_speed_deg: float = 720.0,
	downward_trajectory_gravity_yaw_enabled: bool = true,
	downward_trajectory_gravity_yaw_strength: float = 1.0,
	downward_trajectory_gravity_yaw_safe_angle_deg: float = 3.0,
	downward_trajectory_gravity_yaw_full_angle_deg: float = 90.0,
	downward_trajectory_torque_min_horizontal_speed: float = 2.0,
	downward_trajectory_landing_forward_pitch_enabled: bool = true
) -> void:
	if owner_player == null:
		return

	var preserve_flight: bool = false
	if preserve_active_flight and owner_player.has_method("is_current_action_flight"):
		preserve_flight = bool(owner_player.call("is_current_action_flight"))
	var effective_align_time: float = align_time
	var effective_align_model: bool = align_model_during_spring
	var effective_lock_horizontal: bool = lock_horizontal_during_align
	if preserve_flight:
		effective_align_time = 0.0
		effective_align_model = false
		effective_lock_horizontal = false
		if flight_time_bonus > 0.0 and owner_player.has_method("add_flight_time"):
			owner_player.call("add_flight_time", flight_time_bonus)

	owner_player.cancel_spline_spring()
	owner_player.cancel_homing_attack(false)
	if owner_player.has_method("reset_trick_staleness"):
		owner_player.reset_trick_staleness()

	align_timer = 0.0
	owner_player._bounce_state = owner_player.BounceState.NONE
	owner_player._is_jumping = false
	owner_player._jump_variable = false
	owner_player._jump_hang_allowed = false
	owner_player._jump_time = 0.0
	owner_player.refresh_airborne_abilities()
	owner_player._jump_dash_requested = false
	owner_player._jump_dash_recent_timer = 0.0

	align_model = effective_align_model
	if align_model and spring_model_snap_time > 0.0:
		model_snap_timer = max(model_snap_timer, spring_model_snap_time)
	else:
		model_snap_timer = 0.0

	var dir: Vector3 = spring_direction.normalized()
	if dir.length() < 0.001:
		dir = get_owner_gravity_up()

	if detach_from_ground:
		var detach_up: Vector3 = get_owner_gravity_up()
		owner_player._record_spring_detach_state(detach_up)
		owner_player.attached = false
		owner_player._attachment_immunity = owner_player.launch_immunity_time
		owner_player._airborne_time = 0.0
	else:
		owner_player._airborne_time = 0.0

	if snap_to_center:
		owner_player.global_position = spring_position
		owner_player.surface_point = spring_position

	var v: Vector3 = owner_player.velocity

	var inward_speed: float = min(v.dot(dir), 0.0)
	if stop_momentum:
		owner_player.velocity = dir * spring_strength
	else:
		match additive_mode:
			0:
				var lateral: Vector3 = get_gravity_planar_component(v)
				var launch: Vector3 = dir * spring_strength
				owner_player.velocity = lateral + launch
			1:
				owner_player.velocity = v + dir * spring_strength
			_:
				var lateral: Vector3 = get_gravity_planar_component(v)
				var launch: Vector3 = dir * spring_strength
				owner_player.velocity = lateral + launch

	var mirrored_ratio: float = max(additive_mirrored_bounce_ratio, 0.0)
	var along_speed: float = owner_player.velocity.dot(dir)
	if not stop_momentum:
		along_speed = max(along_speed, min_additive_launch_speed)
	if inward_speed < 0.0 and mirrored_ratio > 0.0:
		var mirrored_speed: float = -inward_speed
		if mirrored_ratio <= 1.0:
			along_speed = lerp(along_speed, mirrored_speed, mirrored_ratio)
		else:
			along_speed = mirrored_speed * mirrored_ratio
	if max_additive_launch_speed > 0.0:
		along_speed = min(along_speed, max_additive_launch_speed)
	owner_player.velocity += dir * (along_speed - owner_player.velocity.dot(dir))

	if p_movement_lock_time > 0.0:
		movement_lock_timer = max(movement_lock_timer, p_movement_lock_time)

	if p_action_lock_time > 0.0:
		action_lock_timer = max(action_lock_timer, p_action_lock_time)

	if effective_align_time > 0.0:
		align_timer = max(align_timer, effective_align_time)
		align_up = spring_basis.y.normalized()
		align_forward = (-spring_basis.z).normalized()
		align_dir = dir
		lock_sideways = effective_lock_horizontal
		sideways_gravity_scale = p_sideways_gravity_scale
		cancel_on_ground = true

	clear_move_on_ground = p_clear_move_on_ground
	clear_action_on_ground = p_clear_action_on_ground

	if align_timer <= 0.0:
		align_model = false

	if not preserve_flight:
		if owner_player.has_method("reset_flight_eligibility"):
			owner_player.call("reset_flight_eligibility")
		if owner_player.has_method("end_active_flight_for_external_impulse"):
			owner_player.call("end_active_flight_for_external_impulse", {"reason": &"spring_impulse"})

	trajectory_torque_active = false
	trajectory_torque_align_speed_deg = max(downward_trajectory_align_speed_deg, 0.0)
	if owner_player.has_method("configure_spring_trajectory_torque"):
		trajectory_torque_active = bool(owner_player.call(
			"configure_spring_trajectory_torque",
			dir,
			downward_trajectory_torque_enabled and detach_from_ground and not preserve_flight,
			downward_trajectory_min_angle_deg,
			trajectory_torque_align_speed_deg,
			downward_trajectory_gravity_yaw_enabled,
			downward_trajectory_gravity_yaw_strength,
			downward_trajectory_gravity_yaw_safe_angle_deg,
			downward_trajectory_gravity_yaw_full_angle_deg,
			downward_trajectory_torque_min_horizontal_speed,
			downward_trajectory_landing_forward_pitch_enabled
		))

	detached = detach_from_ground
	if not preserve_flight:
		owner_player._trigger_anim_command(&"CMD_SPRING")

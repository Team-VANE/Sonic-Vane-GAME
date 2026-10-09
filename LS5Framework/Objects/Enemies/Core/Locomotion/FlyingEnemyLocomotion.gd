extends EnemyLocomotion
class_name FlyingEnemyLocomotion

@export_group("Flight")
## Maximum movement speed across the actor's gravity plane.
@export var horizontal_speed: float = 6.0
## Maximum movement speed along the actor's gravity-up axis.
@export var vertical_speed: float = 3.0
## Acceleration toward the desired flight velocity.
@export var acceleration: float = 18.0
## Deceleration used when no movement is requested.
@export var deceleration: float = 22.0
## Horizontal distance from the goal where movement stops.
@export var horizontal_deadzone: float = 0.1
## Vertical distance from the goal where movement stops.
@export var vertical_deadzone: float = 0.1
## Interval between collision-recovery checks during stationary flight. Zero checks every tick.
@export_range(0.0, 0.5, 0.01, "seconds") var idle_collision_refresh_time: float = 0.1

@export_group("Facing")
## Turns the actor toward the requested facing direction.
@export var facing_enabled: bool = true
## Allows facing to pitch along gravity-up toward the target.
@export var face_pitch: bool = false
## Maximum facing rotation speed in degrees per second.
@export var facing_speed_deg: float = 360.0

var _moving: bool = false
var _idle_refresh_timer: float = 0.0
var _idle_transform: Transform3D = Transform3D.IDENTITY
var _idle_up: Vector3 = Vector3.ZERO


func physics_tick(delta: float, intent: EnemyIntent) -> void:
	if actor == null:
		return
	var up: Vector3 = _get_up()
	if actor.up_direction != up:
		actor.up_direction = up
	var move_direction: Vector3 = intent.move_direction
	var planar_direction: Vector3 = move_direction - up * move_direction.dot(up)
	var vertical_amount: float = move_direction.dot(up)
	var desired_velocity: Vector3 = Vector3.ZERO
	if intent.speed_ratio > 0.0:
		if planar_direction.length() > max(horizontal_deadzone, 0.0):
			desired_velocity += planar_direction.normalized() * max(horizontal_speed, 0.0) * intent.speed_ratio
		if abs(vertical_amount) > max(vertical_deadzone, 0.0):
			desired_velocity += up * sign(vertical_amount) * max(vertical_speed, 0.0) * intent.speed_ratio
	var rate: float = acceleration if desired_velocity.length() > actor.velocity.length() else deceleration
	actor.velocity = actor.velocity.move_toward(desired_velocity, max(rate, 0.0) * delta)
	var previous_position: Vector3 = actor.global_position
	_begin_move(actor.velocity)
	_idle_refresh_timer = max(_idle_refresh_timer - delta, 0.0)
	var idle_unchanged: bool = actor.velocity.is_zero_approx() and desired_velocity.is_zero_approx() and actor.global_transform == _idle_transform and up.is_equal_approx(_idle_up)
	if not idle_unchanged or _idle_refresh_timer <= 0.0 or actor.get_slide_collision_count() > 0:
		actor.move_and_slide()
		_capture_slide_impact_contacts()
		_idle_refresh_timer = max(idle_collision_refresh_time, 0.0)
	_moving = actor.global_position.distance_squared_to(previous_position) > 0.000001
	if facing_enabled and not intent.facing_locked:
		_update_facing(intent.face_direction, up, delta)
	_idle_transform = actor.global_transform
	_idle_up = up


func reset_locomotion() -> void:
	super.reset_locomotion()
	_moving = false
	_idle_refresh_timer = 0.0


func get_state_tag() -> StringName:
	return &"move" if _moving else &"idle"


func _update_facing(requested_direction: Vector3, up: Vector3, delta: float) -> void:
	var forward: Vector3 = requested_direction
	if not face_pitch:
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	var facing_up: Vector3 = up
	if abs(forward.dot(facing_up)) > 0.995:
		facing_up = actor.global_basis.x
	var desired_basis: Basis = Basis().looking_at(forward, facing_up).orthonormalized()
	if actor.global_basis.is_equal_approx(desired_basis) or facing_speed_deg <= 0.0:
		return
	var current_basis: Basis = actor.global_basis.orthonormalized()
	var angle: float = current_basis.get_rotation_quaternion().angle_to(desired_basis.get_rotation_quaternion())
	if angle <= 0.000001:
		return
	var maximum_step: float = deg_to_rad(max(facing_speed_deg, 0.0)) * delta
	actor.global_basis = current_basis.slerp(desired_basis, min(maximum_step / angle, 1.0)).orthonormalized()


func _get_up() -> Vector3:
	if actor.has_method("get_gravity_up"):
		var up_value: Variant = actor.call("get_gravity_up")
		if up_value is Vector3:
			var up: Vector3 = (up_value as Vector3).normalized()
			if up.length() >= 0.001:
				return up
	return Vector3.UP

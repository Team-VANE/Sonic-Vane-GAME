extends Node
class_name ObjectFracturePieceSafety

var collision_mask: int = 17
var safe_radius: float = 0.25
var safe_skin: float = 0.04
var max_sweep_step_distance: float = 0.4
var bounce: float = 0.15
var friction: float = 0.25
var up_direction: Vector3 = Vector3.UP
var enabled: bool = true

var _body: RigidBody3D
var _previous_position: Vector3 = Vector3.ZERO


func setup(
	body: RigidBody3D,
	safety_collision_mask: int,
	safety_radius: float,
	safety_skin: float,
	safety_max_sweep_step_distance: float,
	safety_bounce: float,
	safety_friction: float,
	safety_up_direction: Vector3
) -> void:
	_body = body
	collision_mask = safety_collision_mask
	safe_radius = max(safety_radius, 0.0)
	safe_skin = max(safety_skin, 0.0)
	max_sweep_step_distance = max(safety_max_sweep_step_distance, 0.01)
	bounce = max(safety_bounce, 0.0)
	friction = clamp(safety_friction, 0.0, 1.0)
	up_direction = safety_up_direction
	if up_direction.length() < 0.001:
		up_direction = Vector3.UP
	up_direction = up_direction.normalized()
	_previous_position = _body.global_position


func _ready() -> void:
	if _body == null:
		var parent: Node = get_parent()
		if parent is RigidBody3D:
			_body = parent as RigidBody3D
	if _body:
		_previous_position = _body.global_position


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	if _body == null or not is_instance_valid(_body):
		return
	var current_position: Vector3 = _body.global_position
	var motion: Vector3 = current_position - _previous_position
	if motion.length() > 0.001:
		_sweep_motion(_previous_position, motion)
	else:
		_probe_support(current_position)
	_previous_position = _body.global_position


func reset_history() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	_previous_position = _body.global_position


func _sweep_motion(start_position: Vector3, motion: Vector3) -> void:
	var step_count: int = maxi(1, ceili(motion.length() / max_sweep_step_distance))
	var step_motion: Vector3 = motion / float(step_count)
	var step_start: Vector3 = start_position
	for _step_index: int in range(step_count):
		var hit: Dictionary = _cast_motion(step_start, step_motion)
		if hit.is_empty():
			step_start += step_motion
			continue
		_apply_safe_hit(hit, step_motion)
		return
	_probe_support(_body.global_position)


func _probe_support(current_position: Vector3) -> void:
	var support_distance: float = safe_radius + safe_skin
	if support_distance <= 0.0:
		return
	var hit: Dictionary = _cast_ray(current_position, current_position - up_direction * support_distance)
	if hit.is_empty():
		return
	_apply_safe_hit(hit, -up_direction * support_distance)


func _cast_motion(start_position: Vector3, motion: Vector3) -> Dictionary:
	var motion_direction: Vector3 = _safe_direction(motion, -up_direction)
	var side: Vector3 = motion_direction.cross(up_direction)
	if side.length() < 0.001:
		side = motion_direction.cross(Vector3.RIGHT)
	if side.length() < 0.001:
		side = motion_direction.cross(Vector3.FORWARD)
	side = side.normalized()
	var forward_offset: Vector3 = motion_direction * safe_radius
	var side_offset: Vector3 = side * safe_radius
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		-up_direction * safe_radius,
		forward_offset,
		-forward_offset,
		side_offset,
		-side_offset,
	]
	var best_hit: Dictionary = {}
	var best_distance: float = INF
	for offset: Vector3 in offsets:
		var from_position: Vector3 = start_position + offset
		var to_position: Vector3 = from_position + motion + motion_direction * safe_skin
		var hit: Dictionary = _cast_ray(from_position, to_position)
		if hit.is_empty():
			continue
		var hit_position: Vector3 = hit.get("position", start_position)
		var hit_distance: float = start_position.distance_to(hit_position)
		if hit_distance < best_distance:
			best_distance = hit_distance
			best_hit = hit
	return best_hit


func _cast_ray(from_position: Vector3, to_position: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_position,
		to_position,
		collision_mask
	)
	query.exclude = [_body.get_rid()]
	return _body.get_world_3d().direct_space_state.intersect_ray(query)


func _apply_safe_hit(hit: Dictionary, fallback_motion: Vector3) -> void:
	var normal: Vector3 = hit.get("normal", up_direction)
	if normal.length() < 0.001:
		normal = _safe_direction(-fallback_motion, up_direction)
	normal = normal.normalized()
	var hit_position: Vector3 = hit.get("position", _body.global_position)
	_body.global_position = hit_position + normal * (safe_radius + safe_skin)
	var velocity: Vector3 = _body.linear_velocity
	var normal_speed: float = velocity.dot(normal)
	if normal_speed >= 0.0:
		return
	var tangent_velocity: Vector3 = velocity - normal * normal_speed
	var bounce_speed: float = -normal_speed * bounce
	_body.linear_velocity = tangent_velocity * (1.0 - friction) + normal * bounce_speed


func _safe_direction(value: Vector3, fallback: Vector3) -> Vector3:
	var direction: Vector3 = value
	if direction.length() < 0.001:
		direction = fallback
	if direction.length() < 0.001:
		direction = Vector3.UP
	return direction.normalized()

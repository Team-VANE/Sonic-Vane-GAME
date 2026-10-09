extends EnemyLocomotion
class_name GroundedEnemyLocomotion

const SURFACE_METADATA = preload("res://LS5Framework/Scripts/World/SurfaceBehaviorMetadata.gd")

@export_group("Ground Movement")
## Maximum grounded movement speed.
@export var movement_speed: float = 7.0
## Acceleration toward the desired grounded velocity.
@export var acceleration: float = 28.0
## Deceleration used while no movement is requested.
@export var deceleration: float = 34.0
## Distance from the actor origin to its support contact.
@export var ground_contact_offset: float = 1.0
## Interval between idle movement/support checks on unchanged static geometry. Zero disables idle caching.
@export_range(0.0, 0.5, 0.01, "seconds") var idle_support_refresh_time: float = 0.1

@export_group("Surface Adhesion")
## Enables support following and ground snapping.
@export var adhesion_enabled: bool = true
## Maximum accepted support-normal angle from resolved gravity-up.
@export_range(0.0, 180.0, 0.5) var maximum_surface_angle_deg: float = 70.0
## Maximum accepted surface angle when attaching from the air.
@export_range(0.0, 180.0, 0.5) var airborne_attach_max_angle_deg: float = 70.0
## Maximum normal change accepted between consecutive supports.
@export_range(0.0, 180.0, 0.5) var maximum_normal_step_deg: float = 65.0
## Distance beyond the expected contact point searched for support.
@export var support_snap_distance: float = 0.35
## Time support can be absent before the actor becomes airborne.
@export var support_grace_time: float = 0.08
## Acceleration pressing an attached actor into its current support.
@export var adhesion_acceleration: float = 26.0
## Physics layers accepted as support surfaces.
@export_flags_3d_physics var support_collision_mask: int = 1
## Physics layers that remain solid but cannot become support.
@export_flags_3d_physics var non_attachable_surface_mask: int = 64

@export_group("Alignment")
## Aligns the actor body and visual up axis to the support normal.
@export var align_to_surface: bool = true
## Maximum surface-alignment rotation speed in degrees per second.
@export var alignment_speed_deg: float = 540.0
## Maximum facing rotation speed in degrees per second.
@export var facing_speed_deg: float = 480.0

@export_group("Ledges and Obstacles")
## Stops forward movement when no support is detected ahead.
@export var stop_at_ledges: bool = true
## Forward distance used by the ledge support probe.
@export var ledge_probe_distance: float = 0.85
## Enables automatic jumps over detected obstacles.
@export var auto_jump_obstacles: bool = true
## Enables automatic jumps when support is absent ahead.
@export var auto_jump_gaps: bool = false
## Forward obstacle detection distance.
@export var obstacle_probe_distance: float = 0.8
## Height of the forward obstacle ray above the actor origin.
@export var obstacle_probe_height: float = 0.35

@export_group("Jump")
## Allows this locomotion module to jump.
@export var jump_enabled: bool = true
## Launch speed applied along the current support normal.
@export var jump_speed: float = 12.0
## Delay before another automatic or requested jump can begin.
@export var jump_cooldown_sec: float = 0.4

var _support_normal: Vector3 = Vector3.UP
var _grounded: bool = false
var _support_grace_timer: float = 0.0
var _jump_cooldown: float = 0.0
var _moving: bool = false
var _support_body: Node3D = null
var _support_body_transform: Transform3D = Transform3D.IDENTITY
var _support_shape: int = -1
var _support_shape_transform: Transform3D = Transform3D.IDENTITY
var _idle_transform: Transform3D = Transform3D.IDENTITY
var _idle_gravity_up: Vector3 = Vector3.ZERO
var _idle_refresh_timer: float = 0.0
var _support_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _ledge_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _obstacle_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func setup(owner_actor: CharacterBody3D) -> void:
	super.setup(owner_actor)
	_support_normal = _get_gravity_up()
	actor.up_direction = _support_normal
	actor.floor_stop_on_slope = true
	actor.floor_snap_length = 0.0
	actor.floor_max_angle = deg_to_rad(min(max(maximum_surface_angle_deg, 0.0), 89.0))
	_probe_support(true)


func physics_tick(delta: float, intent: EnemyIntent) -> void:
	if actor == null:
		return
	_jump_cooldown = max(_jump_cooldown - delta, 0.0)
	var gravity_up: Vector3 = _get_gravity_up()
	var movement_plane_normal: Vector3 = _support_normal if _grounded else gravity_up
	if actor.up_direction != movement_plane_normal:
		actor.up_direction = movement_plane_normal
	var requested_direction: Vector3 = intent.move_direction
	var planar_direction: Vector3 = requested_direction - movement_plane_normal * requested_direction.dot(movement_plane_normal)
	if planar_direction.length() >= 0.001:
		planar_direction = planar_direction.normalized()
	var jump_requested: bool = intent.jump_requested
	if _grounded and planar_direction.length() >= 0.001:
		var ledge_ahead: bool = (stop_at_ledges or auto_jump_gaps) and not _has_support_ahead(planar_direction)
		var obstacle_ahead: bool = auto_jump_obstacles and _has_obstacle_ahead(planar_direction)
		if obstacle_ahead and auto_jump_obstacles:
			jump_requested = true
		elif ledge_ahead and auto_jump_gaps:
			jump_requested = true
		elif ledge_ahead and stop_at_ledges:
			planar_direction = Vector3.ZERO

	var lateral_velocity: Vector3 = actor.velocity - movement_plane_normal * actor.velocity.dot(movement_plane_normal)
	var desired_velocity: Vector3 = planar_direction * max(movement_speed, 0.0) * clamp(intent.speed_ratio, 0.0, 1.0)
	_idle_refresh_timer = max(_idle_refresh_timer - delta, 0.0)
	if desired_velocity.is_zero_approx() and not jump_requested and _can_reuse_idle_support(gravity_up):
		_begin_move(Vector3.ZERO)
		_moving = false
		var idle_facing: Vector3 = Vector3.ZERO if intent.facing_locked else intent.face_direction
		_update_orientation(idle_facing, gravity_up, delta)
		_idle_transform = actor.global_transform
		return
	var movement_rate: float = acceleration if desired_velocity.length() > lateral_velocity.length() else deceleration
	lateral_velocity = lateral_velocity.move_toward(desired_velocity, max(movement_rate, 0.0) * delta)
	if _grounded:
		actor.velocity = lateral_velocity - _support_normal * max(adhesion_acceleration, 0.0) * delta
		if jump_enabled and jump_requested and _jump_cooldown <= 0.0:
			actor.velocity = lateral_velocity + _support_normal * max(jump_speed, 0.0)
			_grounded = false
			_support_grace_timer = 0.0
			_jump_cooldown = max(jump_cooldown_sec, 0.0)
	else:
		actor.velocity = lateral_velocity + gravity_up * actor.velocity.dot(gravity_up)
		actor.velocity += _get_gravity_acceleration() * delta

	var previous_position: Vector3 = actor.global_position
	_begin_move(actor.velocity)
	actor.move_and_slide()
	_capture_slide_impact_contacts()
	_moving = actor.global_position.distance_squared_to(previous_position) > 0.000001
	_update_support(delta)
	var facing_direction: Vector3 = Vector3.ZERO if intent.facing_locked else intent.face_direction
	_update_orientation(facing_direction, gravity_up, delta)
	_idle_transform = actor.global_transform
	_idle_gravity_up = gravity_up
	_idle_refresh_timer = max(idle_support_refresh_time, 0.0)


func reset_locomotion() -> void:
	super.reset_locomotion()
	_grounded = false
	_support_normal = _get_gravity_up()
	_support_grace_timer = 0.0
	_jump_cooldown = 0.0
	_moving = false
	_support_body = null
	_support_shape = -1
	_idle_refresh_timer = 0.0
	_probe_support(true)


func is_grounded() -> bool:
	return _grounded


func get_state_tag() -> StringName:
	if not _grounded:
		return &"airborne"
	return &"move" if _moving and actor.velocity.length() > 0.2 else &"idle"


func _update_support(delta: float) -> void:
	var collision_support: Dictionary = _find_collision_support()
	if not collision_support.is_empty():
		if _accept_support(collision_support.get("normal", _support_normal) as Vector3):
			_remember_support(collision_support)
			_support_grace_timer = max(support_grace_time, 0.0)
			return
	if _probe_support(false):
		_support_grace_timer = max(support_grace_time, 0.0)
		return
	_support_grace_timer = max(_support_grace_timer - delta, 0.0)
	if _support_grace_timer <= 0.0:
		_grounded = false
		_support_body = null
		_support_normal = _get_gravity_up()


func _find_collision_support() -> Dictionary:
	var best: Dictionary = {}
	var best_dot: float = -2.0
	for index: int in range(actor.get_slide_collision_count()):
		var collision: KinematicCollision3D = actor.get_slide_collision(index)
		var normal: Vector3 = collision.get_normal().normalized()
		var collider: Object = collision.get_collider()
		if not _surface_is_accepted(collider, normal, not _grounded):
			continue
		var reference_normal: Vector3 = _support_normal if _grounded else _get_gravity_up()
		var alignment: float = normal.dot(reference_normal)
		if alignment > best_dot:
			best_dot = alignment
			best = {"normal": normal, "collider": collider, "shape": collision.get_collider_shape_index()}
	return best


func _probe_support(initial_probe: bool) -> bool:
	if not adhesion_enabled or actor == null or actor.get_world_3d() == null:
		return false
	var probe_up: Vector3 = _support_normal if _grounded else _get_gravity_up()
	var offset: float = max(ground_contact_offset, 0.0) * max(float(actor.get("size")), 0.01)
	var ray_start: Vector3 = actor.global_position + probe_up * max(support_snap_distance, 0.0)
	var ray_length: float = offset + max(support_snap_distance, 0.0) * 2.0
	var query: PhysicsRayQueryParameters3D = _support_query
	query.from = ray_start
	query.to = ray_start - probe_up * ray_length
	query.collision_mask = support_collision_mask
	query.exclude = [actor.get_rid()]
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.get("normal", probe_up) as Vector3
	var collider: Object = hit.get("collider") as Object
	if not _surface_is_accepted(collider, normal, not _grounded and not initial_probe):
		return false
	var target_position: Vector3 = (hit.get("position", actor.global_position) as Vector3) + normal.normalized() * offset
	var snap_distance: float = actor.global_position.distance_to(target_position)
	if initial_probe or snap_distance <= max(support_snap_distance, 0.0) * 2.0 + 0.05:
		var was_grounded: bool = _grounded
		if _accept_support(normal):
			_remember_support(hit)
			if not initial_probe and not was_grounded:
				_record_impact_contact(normal, collider)
			actor.global_position = target_position
			return true
	return false


func _remember_support(hit: Dictionary) -> void:
	_support_body = hit.get("collider") as Node3D
	_support_shape = int(hit.get("shape", -1))
	if is_instance_valid(_support_body):
		_support_body_transform = _support_body.global_transform
		if _support_body is StaticBody3D and _support_shape >= 0:
			var body: StaticBody3D = _support_body as StaticBody3D
			_support_shape_transform = body.shape_owner_get_transform(body.shape_find_owner(_support_shape))


func _can_reuse_idle_support(gravity_up: Vector3) -> bool:
	if not adhesion_enabled or not _grounded or _idle_refresh_timer <= 0.0 or not actor.velocity.is_zero_approx():
		return false
	if actor.global_transform != _idle_transform or not gravity_up.is_equal_approx(_idle_gravity_up):
		return false
	if not is_instance_valid(_support_body) or _support_body is AnimatableBody3D or not _support_body.is_inside_tree() or _support_body.is_queued_for_deletion():
		return false
	if _support_body.global_transform != _support_body_transform:
		return false
	if not _surface_is_accepted(_support_body, _support_normal, false):
		return false
	if _support_body is CSGShape3D:
		var csg: CSGShape3D = _support_body as CSGShape3D
		return csg.is_root_shape() and csg.use_collision and (csg.collision_layer & support_collision_mask) != 0
	if not _support_body is StaticBody3D:
		return false
	var body: StaticBody3D = _support_body as StaticBody3D
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx() or not (body.collision_layer & support_collision_mask):
		return false
	if _support_shape < 0 or _support_shape >= PhysicsServer3D.body_get_shape_count(body.get_rid()):
		return false
	var owner_id: int = body.shape_find_owner(_support_shape)
	return not body.is_shape_owner_disabled(owner_id) and body.shape_owner_get_transform(owner_id) == _support_shape_transform


func _accept_support(normal_value: Vector3) -> bool:
	var normal: Vector3 = normal_value.normalized()
	if normal.length() < 0.001:
		return false
	if _grounded and _support_normal.length() >= 0.001:
		var angle_deg: float = rad_to_deg(acos(clamp(_support_normal.dot(normal), -1.0, 1.0)))
		if angle_deg > max(maximum_normal_step_deg, 0.0):
			return false
		_rotate_velocity_between_normals(_support_normal, normal)
	_support_normal = normal
	_grounded = true
	return true


func _surface_is_accepted(collider: Object, normal_value: Vector3, airborne: bool) -> bool:
	if collider == null or normal_value.length() < 0.001:
		return false
	if collider is CollisionObject3D and ((collider as CollisionObject3D).collision_layer & non_attachable_surface_mask) != 0:
		return false
	var limit: float = airborne_attach_max_angle_deg if airborne else maximum_surface_angle_deg
	if collider.has_meta(SURFACE_METADATA.ATTACH_LIMIT):
		var metadata_value: Variant = collider.get_meta(SURFACE_METADATA.ATTACH_LIMIT)
		if metadata_value is int or metadata_value is float:
			limit = min(limit, float(metadata_value))
	if limit <= 0.0:
		return false
	var angle_deg: float = rad_to_deg(acos(clamp(normal_value.normalized().dot(_get_gravity_up()), -1.0, 1.0)))
	return angle_deg <= clamp(limit, 0.0, 180.0) + 0.001


func _has_support_ahead(direction: Vector3) -> bool:
	if actor.get_world_3d() == null:
		return true
	var offset: float = max(ground_contact_offset, 0.0) * max(float(actor.get("size")), 0.01)
	var origin: Vector3 = actor.global_position + direction * max(ledge_probe_distance, 0.0) + _support_normal * max(support_snap_distance, 0.05)
	var query: PhysicsRayQueryParameters3D = _ledge_query
	query.from = origin
	query.to = origin - _support_normal * (offset + max(support_snap_distance, 0.0) * 2.0)
	query.collision_mask = support_collision_mask
	query.exclude = [actor.get_rid()]
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return _surface_is_accepted(hit.get("collider") as Object, hit.get("normal", _support_normal) as Vector3, false)


func _has_obstacle_ahead(direction: Vector3) -> bool:
	if actor.get_world_3d() == null:
		return false
	var origin: Vector3 = actor.global_position + _support_normal * max(obstacle_probe_height, 0.0)
	var query: PhysicsRayQueryParameters3D = _obstacle_query
	query.from = origin
	query.to = origin + direction * max(obstacle_probe_distance, 0.0)
	query.collision_mask = support_collision_mask
	query.exclude = [actor.get_rid()]
	return not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _update_orientation(face_direction: Vector3, gravity_up: Vector3, delta: float) -> void:
	var desired_up: Vector3 = _support_normal if _grounded and align_to_surface else gravity_up
	var forward: Vector3 = face_direction - desired_up * face_direction.dot(desired_up)
	if forward.length() < 0.001:
		forward = -actor.global_basis.z
		forward -= desired_up * forward.dot(desired_up)
	if forward.length() < 0.001:
		return
	var desired_basis: Basis = Basis().looking_at(forward.normalized(), desired_up).orthonormalized()
	if actor.global_basis.is_equal_approx(desired_basis):
		return
	var current_basis: Basis = actor.global_basis.orthonormalized()
	var rotation_speed: float = min(max(alignment_speed_deg, 0.0), max(facing_speed_deg, 0.0))
	var angle: float = current_basis.get_rotation_quaternion().angle_to(desired_basis.get_rotation_quaternion())
	if angle <= 0.000001:
		return
	if rotation_speed <= 0.0:
		return
	var maximum_step: float = deg_to_rad(rotation_speed) * delta
	actor.global_basis = current_basis.slerp(desired_basis, min(maximum_step / angle, 1.0)).orthonormalized()


func _rotate_velocity_between_normals(from_normal: Vector3, to_normal: Vector3) -> void:
	var axis: Vector3 = from_normal.cross(to_normal)
	if axis.length() < 0.000001:
		return
	var angle: float = acos(clamp(from_normal.dot(to_normal), -1.0, 1.0))
	actor.velocity = actor.velocity.rotated(axis.normalized(), angle)


func _get_gravity_up() -> Vector3:
	if actor and actor.has_method("get_gravity_up"):
		var up_value: Variant = actor.call("get_gravity_up")
		if up_value is Vector3:
			var up: Vector3 = (up_value as Vector3).normalized()
			if up.length() >= 0.001:
				return up
	return Vector3.UP


func _get_gravity_acceleration() -> Vector3:
	if actor and actor.has_method("get_gravity_acceleration_vector"):
		var acceleration_value: Variant = actor.call("get_gravity_acceleration_vector")
		if acceleration_value is Vector3:
			return acceleration_value as Vector3
	return -_get_gravity_up() * 38.0

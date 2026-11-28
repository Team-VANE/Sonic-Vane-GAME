extends RefCounted

static var _motion_samples: Dictionary = {}


static func target_velocity(target: Node3D, max_speed: float = 40.0) -> Vector3:
	var ancestor: Node = target
	while ancestor:
		if ancestor.has_method("get_throw_target_velocity"):
			var supplied: Variant = ancestor.call("get_throw_target_velocity")
			if supplied is Vector3:
				return supplied.limit_length(max_speed)
		if ancestor is CharacterBody3D:
			return ancestor.velocity.limit_length(max_speed)
		if ancestor.has_method("get_dynamic_impact_velocity_at"):
			return (ancestor.call("get_dynamic_impact_velocity_at", target.global_position) as Vector3).limit_length(max_speed)
		if ancestor is RigidBody3D:
			return (ancestor.linear_velocity + ancestor.angular_velocity.cross(target.global_position - ancestor.global_position)).limit_length(max_speed)
		ancestor = ancestor.get_parent()
	var id: int = target.get_instance_id()
	var frame: int = Engine.get_physics_frames()
	var point: Vector3 = target_position(target, target.global_position)
	var velocity: Vector3 = Vector3.ZERO
	if _motion_samples.has(id):
		var sample: Dictionary = _motion_samples[id]
		var frames: int = frame - int(sample["frame"])
		if frames == 0:
			return (sample["velocity"] as Vector3).limit_length(max_speed)
		if frames > 0 and frames <= Engine.physics_ticks_per_second:
			velocity = (point - (sample["position"] as Vector3)) * float(Engine.physics_ticks_per_second) / (float(frames) * maxf(Engine.time_scale, 0.001))
	if _motion_samples.size() >= 256 and not _motion_samples.has(id):
		_motion_samples.clear()
	_motion_samples[id] = {"position": point, "frame": frame, "velocity": velocity}
	return velocity.limit_length(max_speed)

static func is_target_available(target: Node3D, prop: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
		return false
	if target == prop or prop.is_ancestor_of(target):
		return false
	if target.is_in_group(&"CarryThrowTarget"):
		return target.has_method(&"can_receive_thrown_object") and target.call(&"can_receive_thrown_object", prop)
	if not target.is_in_group(&"HomingTarget"):
		return false
	var ancestor: Node = target
	while ancestor:
		if ancestor.is_in_group(&"Rail") or ancestor.has_method("try_start_with_body_proximity") or ancestor.has_method("get_closest_point_on_path"):
			return false
		ancestor = ancestor.get_parent()
	for property: StringName in [&"enabled", &"homing_target_enabled", &"thrown_object_targeting_enabled"]:
		if target.get(property) == false:
			return false
	if target is PropTarget3D:
		return is_instance_valid(target.prop) and not target.prop.is_destroyed and not target.prop.is_carried() and target.prop.targeting_allowed
	return true


static func target_position(target: Node3D, origin: Vector3) -> Vector3:
	if target.has_method(&"get_throw_target_position"):
		return target.call(&"get_throw_target_position")
	if target.has_method("get_homing_target_position"):
		var point: Variant = target.call("get_homing_target_position", origin)
		if point is Vector3:
			return point
	return target.global_position


static func facing_score(offset: Vector3, forward: Vector3, up: Vector3, max_range: float, horizontal_angle: float, vertical_angle: float) -> float:
	var distance: float = offset.length()
	if distance < 0.05 or distance > max_range:
		return INF
	var lateral: Vector3 = offset.slide(up)
	if lateral.is_zero_approx():
		return INF
	var alignment: float = forward.dot(lateral.normalized())
	if alignment <= 0.0 or alignment < cos(deg_to_rad(horizontal_angle)):
		return INF
	if absf(atan2(offset.dot(up), lateral.length())) > deg_to_rad(vertical_angle):
		return INF
	return acos(clampf(alignment, -1.0, 1.0)) + distance / maxf(max_range, 0.01) * 0.001


static func solve(origin: Vector3, destination: Vector3, preferred_velocity: Vector3, inherited_velocity: Vector3, motion: Dictionary, min_time: float, max_time: float, max_speed: float, target_motion: Vector3 = Vector3.ZERO, minimum_impact_speed: float = 0.0) -> Array[Dictionary]:
	var solutions: Array[Dictionary] = []
	if motion.is_empty() or max_time < min_time:
		return solutions
	var step: float = float(motion["step"])
	var gravity: Vector3 = motion["gravity"]
	var gravity_after_motion: bool = bool(motion.get("gravity_after_motion", false))
	var retention: float = clampf(1.0 - float(motion["damping"]) * step, 0.0, 1.0)
	var first_frame: int = maxi(ceili(min_time / step), 1)
	var last_frame: int = maxi(floori(max_time / step), first_frame)
	var velocity_factor: float = 1.0
	var position_factor: float = 0.0
	var gravity_velocity: Vector3 = Vector3.ZERO
	var gravity_position: Vector3 = Vector3.ZERO
	var stride: int = maxi(ceili(float(last_frame - first_frame) / 20.0), 1)
	for frame: int in range(1, last_frame + 1):
		velocity_factor *= retention
		gravity_velocity *= retention
		if not gravity_after_motion:
			gravity_velocity += gravity * step
		position_factor += velocity_factor * step
		gravity_position += gravity_velocity * step
		if gravity_after_motion:
			gravity_velocity += gravity * step
		if frame < first_frame or (frame != last_frame and (frame - first_frame) % stride):
			continue
		if position_factor < 0.00001:
			continue
		var duration: float = float(frame) * step
		var intercept: Vector3 = destination + target_motion * duration
		var launch: Vector3 = (intercept - origin - gravity_position) / position_factor
		if not launch.is_finite() or (launch - inherited_velocity).length() > max_speed:
			continue
		var arrival_velocity: Vector3 = launch * velocity_factor + gravity_velocity
		if gravity_after_motion:
			arrival_velocity -= gravity * step
		if (arrival_velocity - target_motion).length() < minimum_impact_speed:
			continue
		solutions.append({"velocity": launch, "frames": frame, "time": duration, "destination": intercept, "factor": position_factor, "cost": launch.distance_squared_to(preferred_velocity)})
	solutions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["cost"]) < float(b["cost"]))
	if motion.has("gravity_sampler"):
		var refined: Array[Dictionary] = []
		for index: int in range(mini(solutions.size(), 8)):
			var solution: Dictionary = solutions[index]
			var launch: Vector3 = solution["velocity"]
			var intercept: Vector3 = solution["destination"]
			var path: PackedVector3Array = PackedVector3Array()
			for iteration: int in range(6):
				path = predict_path(origin, launch, int(solution["frames"]), motion)
				var error: Vector3 = intercept - path[path.size() - 1]
				if error.length() < 0.03:
					break
				if iteration < 5:
					launch += error / float(solution["factor"])
			var arrival_velocity: Vector3 = (path[path.size() - 1] - path[path.size() - 2]) / step
			if not launch.is_finite() or intercept.distance_to(path[path.size() - 1]) > 0.12 or (launch - inherited_velocity).length() > max_speed or (arrival_velocity - target_motion).length() < minimum_impact_speed:
				continue
			solution["velocity"] = launch
			solution["path"] = path
			solution["cost"] = launch.distance_squared_to(preferred_velocity)
			refined.append(solution)
		refined.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["cost"]) < float(b["cost"]))
		return refined
	return solutions


static func predict_path(origin: Vector3, launch: Vector3, frames: int, motion: Dictionary) -> PackedVector3Array:
	var path: PackedVector3Array = PackedVector3Array([origin])
	var position: Vector3 = origin
	var velocity: Vector3 = launch
	var step: float = float(motion["step"])
	var retention: float = clampf(1.0 - float(motion["damping"]) * step, 0.0, 1.0)
	var after_motion: bool = bool(motion.get("gravity_after_motion", false))
	var sampler: Callable = motion.get("gravity_sampler", Callable())
	for frame: int in range(frames):
		var gravity: Vector3 = sampler.call(position) if sampler.is_valid() else motion["gravity"]
		velocity *= retention
		if not after_motion:
			velocity += gravity * step
		position += velocity * step
		if after_motion:
			velocity += gravity * step
		path.append(position)
	return path


static func arc_is_clear(prop: ObjectPhysicsBody3D, carrier: PhysicsBody3D, target: Node3D, release: Transform3D, solution: Dictionary, motion: Dictionary) -> bool:
	var radius: float = prop.get_throw_clearance_radius()
	if radius <= 0.0:
		return false
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = prop.get_throw_collision_mask()
	query.collide_with_areas = false
	var exclusions: Array[RID] = [prop.get_rid(), carrier.get_rid()]
	var ancestor: Node = target
	while ancestor:
		if ancestor is PhysicsBody3D:
			exclusions.append(ancestor.get_rid())
			break
		ancestor = ancestor.get_parent()
	query.exclude = exclusions
	var space: PhysicsDirectSpaceState3D = prop.get_world_3d().direct_space_state
	var path: PackedVector3Array = solution.get("path", PackedVector3Array())
	if path.is_empty():
		path = predict_path(release.origin, solution["velocity"], int(solution["frames"]), motion)
	for frame: int in range(path.size() - 1):
		query.transform = Transform3D(Basis.IDENTITY, path[frame])
		query.motion = path[frame + 1] - path[frame]
		if not space.intersect_shape(query, 1).is_empty():
			return false
		var fractions: PackedFloat32Array = space.cast_motion(query)
		if fractions[0] < 1.0:
			return false
	return true

extends RefCounted
class_name DownwarpUtil

static func apply_downwarp_from_node(
	node: Node3D,
	xform: Transform3D,
	exclude: Array = [],
	gravity_up: Vector3 = Vector3.ZERO
) -> Transform3D:
	var info: Dictionary = apply_downwarp_from_node_with_hit(node, xform, exclude, gravity_up)
	if info.has("xform") and info["xform"] is Transform3D:
		return info["xform"]
	return xform

static func apply_downwarp_from_node_with_hit(
	node: Node3D,
	xform: Transform3D,
	exclude: Array = [],
	gravity_up: Vector3 = Vector3.ZERO,
	surface_filter: Callable = Callable(),
	body_mask: int = 0xFFFFFFFF
) -> Dictionary:
	var up: Vector3 = _resolve_gravity_up(gravity_up, exclude)
	var result: Dictionary = {}
	result["xform"] = xform
	result["hit"] = false
	result["point"] = xform.origin
	result["normal"] = up
	result["collider"] = null
	result["shape"] = -1

	if node == null or not is_instance_valid(node):
		return result
	var enabled: bool = false
	var v = node.get("downwarp_enabled")
	if v is bool:
		enabled = v
	if not enabled:
		return result
	var world: World3D = node.get_world_3d()
	if world == null:
		return result

	var distance: float = 50.0
	var offset: float = 0.05
	var mask: int = 0xFFFFFFFF

	var dv = node.get("downwarp_distance")
	if dv is float or dv is int:
		distance = float(dv)
	var ov = node.get("downwarp_offset")
	if ov is float or ov is int:
		offset = float(ov)
	var mv = node.get("downwarp_collision_mask")
	if mv is int:
		mask = int(mv)

	var from_pos: Vector3 = xform.origin + up * 0.1
	var to_pos: Vector3 = xform.origin - up * max(distance, 0.0)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	params.collision_mask = mask & body_mask
	params.hit_back_faces = false
	var exclusions: Array[RID] = []
	for item: Variant in exclude:
		if item is RID:
			exclusions.append(item)
		elif item is CollisionObject3D and is_instance_valid(item):
			exclusions.append(item.get_rid())
	params.exclude = exclusions

	var hit: Dictionary = {}
	for attempt: int in range(16):
		hit = world.direct_space_state.intersect_ray(params)
		if hit.is_empty() or not surface_filter.is_valid() or surface_filter.call(hit):
			break
		params.from = (hit["position"] as Vector3) - up * 0.001
		hit.clear()
		if (params.from - to_pos).dot(up) <= 0.0:
			break
	if hit:
		var p: Vector3 = hit.position
		var n: Vector3 = hit.normal
		xform.origin = p + up * max(offset, 0.0)
		result["xform"] = xform
		result["hit"] = true
		result["point"] = p
		result["normal"] = n
		result["collider"] = hit.get("collider")
		result["shape"] = int(hit.get("shape", -1))
	else:
		result["xform"] = xform

	return result


static func _resolve_gravity_up(requested_up: Vector3, exclude: Array) -> Vector3:
	var up: Vector3 = requested_up.normalized()
	if up.length() >= 0.001:
		return up
	for excluded in exclude:
		if excluded is Node and is_instance_valid(excluded) and excluded.has_method("get_gravity_up"):
			var gravity_up_value = excluded.call("get_gravity_up")
			if gravity_up_value is Vector3:
				up = (gravity_up_value as Vector3).normalized()
				if up.length() >= 0.001:
					return up
	return Vector3.UP

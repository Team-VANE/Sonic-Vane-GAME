extends Area3D
class_name ImportedSurfaceBehaviorArea

const DETECTION_LAYER: int = 1 << 31
const DETECTION_GROUP: StringName = &"surface_behavior_triggers"

var _registered_bodies: Dictionary = {}


func is_imported_surface_behavior_area() -> bool:
	return true


static func is_behavior_area(area: Area3D) -> bool:
	return area is ImportedSurfaceBehaviorArea or SurfaceBehaviorRegistry.is_behavior_area(area)


static func notify_entered(area: Area3D, body: Node3D) -> void:
	if area is ImportedSurfaceBehaviorArea:
		(area as ImportedSurfaceBehaviorArea)._on_body_entered(body)
	else:
		SurfaceBehaviorRegistry.notify_entered(area, body)


static func notify_exited(area: Area3D, body: Node3D) -> void:
	if area is ImportedSurfaceBehaviorArea:
		(area as ImportedSurfaceBehaviorArea)._on_body_exited(body)
	else:
		SurfaceBehaviorRegistry.notify_exited(area, body)


func _ready() -> void:
	collision_layer = DETECTION_LAYER
	add_to_group(DETECTION_GROUP)
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	call_deferred("_register_existing_overlaps")


func _register_existing_overlaps() -> void:
	if not is_inside_tree():
		return
	for body: Node3D in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.has_method("enter_surface_behavior_area"):
		return
	_registered_bodies[body.get_instance_id()] = weakref(body)
	body.call("enter_surface_behavior_area", self)


func _on_body_exited(body: Node3D) -> void:
	if body == null or not body.has_method("exit_surface_behavior_area"):
		return
	_registered_bodies.erase(body.get_instance_id())
	body.call("exit_surface_behavior_area", self)


func _exit_tree() -> void:
	for body_reference: WeakRef in _registered_bodies.values():
		var body: Node3D = body_reference.get_ref() as Node3D
		if is_instance_valid(body):
			body.call("exit_surface_behavior_area", self)
	_registered_bodies.clear()


static func collect_body_contacts(
	body: CollisionObject3D,
	start_position: Vector3,
	sweep_motion: bool
) -> Dictionary:
	var overlaps: Dictionary = {}
	var crossed: Dictionary = {}
	if body.collision_layer == 0 or not body.get_tree().get_first_node_in_group(DETECTION_GROUP):
		return {"overlaps": overlaps, "crossed": crossed}
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	for owner_id: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		var shape_transform: Transform3D = body.global_transform * body.shape_owner_get_transform(owner_id)
		for shape_id: int in range(body.shape_owner_get_shape_count(owner_id)):
			var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			query.shape = body.shape_owner_get_shape(owner_id, shape_id)
			query.transform = shape_transform
			query.collision_mask = DETECTION_LAYER
			query.collide_with_areas = true
			query.collide_with_bodies = false
			query.margin = 0.01
			_collect_query_contacts(space, query, body, overlaps)
			if not sweep_motion or start_position.is_equal_approx(body.global_position):
				continue
			query.transform.origin += start_position - body.global_position
			_collect_query_contacts(space, query, body, crossed)
			_collect_motion_contacts(space, query, body, body.global_position - start_position, crossed)

	return {"overlaps": overlaps, "crossed": crossed}


static func _collect_motion_contacts(
	space: PhysicsDirectSpaceState3D,
	query: PhysicsShapeQueryParameters3D,
	body: CollisionObject3D,
	motion: Vector3,
	contacts: Dictionary
) -> void:
	var segment_count: int = maxi(ceili(motion.length() / 64.0), 1)
	var segment_motion: Vector3 = motion / float(segment_count)
	var start_transform: Transform3D = query.transform
	var excluded: Array[RID] = []
	for segment_index: int in range(segment_count):
		var origin_transform: Transform3D = start_transform
		origin_transform.origin += segment_motion * float(segment_index)
		query.transform = origin_transform
		query.motion = Vector3.ZERO
		_collect_query_contacts(space, query, body, contacts)
		for area: Area3D in contacts.values():
			if not excluded.has(area.get_rid()):
				excluded.append(area.get_rid())
		for attempt: int in range(64):
			query.exclude = excluded
			query.transform = origin_transform
			query.motion = segment_motion
			var found_hit: bool = false
			for refinement: int in range(12):
				var fractions: PackedFloat32Array = space.cast_motion(query)
				if fractions.size() < 2 or fractions[0] >= 1.0:
					break
				var hit_motion: Vector3 = query.motion * fractions[1]
				query.transform.origin = origin_transform.origin + hit_motion
				query.motion = Vector3.ZERO
				for hit: Dictionary in space.intersect_shape(query, 64):
					var area: Area3D = hit.get("collider") as Area3D
					if area and not excluded.has(area.get_rid()):
						excluded.append(area.get_rid())
						found_hit = true
						if is_behavior_area(area) and (area.collision_mask & body.collision_layer):
							contacts[area.get_instance_id()] = area
				if found_hit:
					break
				query.transform = origin_transform
				query.motion = hit_motion
			if not found_hit:
				break


static func _collect_query_contacts(
	space: PhysicsDirectSpaceState3D,
	query: PhysicsShapeQueryParameters3D,
	body: CollisionObject3D,
	contacts: Dictionary
) -> void:
	for hit: Dictionary in space.intersect_shape(query, 64):
		var area: Area3D = hit.get("collider") as Area3D
		if is_behavior_area(area) and (area.collision_mask & body.collision_layer):
			contacts[area.get_instance_id()] = area

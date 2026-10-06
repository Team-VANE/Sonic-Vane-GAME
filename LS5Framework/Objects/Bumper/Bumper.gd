class_name Bumper
extends Area3D

enum LaunchMode {
	RADIAL,
	SURFACE_NORMAL,
	SPECIFIED_DIRECTION,
}

@export_group("Bumper")

## Enables bumper interaction.
@export var active: bool = true

## Additional collision mask for dynamic physics objects accepted by the bumper.
@export_flags_3d_physics var dynamic_object_collision_mask: int = 7

## Time before the same body can trigger this bumper again.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s")
var rehit_cooldown: float = 0.15

## Detaches supported players from the ground when launched.
@export var detach_from_ground: bool = true
## Clears prior action, movement, and spring alignment locks when bounced.
@export var override_previous_lock_timers: bool = true

@export_group("Launch")

## Selects how the outward launch direction is calculated.
@export_enum("Radial", "Surface Normal", "Specified Direction")
var launch_mode: int = LaunchMode.RADIAL

## Multiplies the total speed of the reflected incoming velocity.
@export_range(0.0, 10.0, 0.01, "or_greater")
var mirrored_bounce_ratio: float = 1.0

## Minimum total speed of the outgoing bounce.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s")
var minimum_impulse: float = 35.0

## Maximum total speed of the outgoing bounce. A value of 0.0 disables the cap.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s")
var maximum_impulse: float = 100.0

## Keeps velocity perpendicular to the selected launch direction.
@export var preserve_tangential_velocity: bool = true

## Local-space direction used by Specified Direction mode.
@export var specified_launch_direction: Vector3 = Vector3.UP

## Mesh or collision shape used by Surface Normal mode.
@export var surface_normal_source: Node3D

## Solid collision body queried for the exact Surface Normal hit location.
@export var surface_collision_body: StaticBody3D

## Authored mesh used to generate matching concave trigger and solid collision shapes.
@export var trimesh_source: MeshInstance3D

## Generates collision shapes from Trimesh Source when the bumper enters the scene.
@export var generate_trimesh_collision: bool = false

## Uses a convex hull for reliable body detection while retaining exact trimesh solid collision.
@export var trimesh_convex_trigger: bool = true

## Maximum distance from the body origin to the resolved trimesh contact.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m")
var surface_contact_distance: float = 2.5

@export_group("Audio")

## Audio player used for the bumper sound.
@export var sfx_player: AudioStreamPlayer3D

## Sound played when the bumper launches a body.
@export var bumper_sound: AudioStream

@export_group("Visual Bounce")

## Visual root scaled when the bumper is triggered.
@export var visual_root: Node3D

## Enables the trigger scale animation.
@export var visual_bounce_enabled: bool = true

## Peak uniform scale applied during the trigger animation.
@export_range(1.0, 3.0, 0.01)
var visual_bounce_peak_scale: float = 1.2

## Duration of the trigger scale animation.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:s")
var visual_bounce_duration: float = 0.16

var _body_cooldowns: Dictionary = {}
var _tracked_bodies: Dictionary = {}
var _visual_base_scale: Vector3 = Vector3.ONE
var _visual_tween: Tween


func _ready() -> void:
	if dynamic_object_collision_mask > 0:
		collision_mask = collision_mask | dynamic_object_collision_mask
	_setup_trimesh_collision()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if visual_root:
		_visual_base_scale = visual_root.scale


func _setup_trimesh_collision() -> void:
	if not generate_trimesh_collision or not trimesh_source or not trimesh_source.mesh:
		return

	var area_shape: Shape3D
	if trimesh_convex_trigger:
		area_shape = trimesh_source.mesh.create_convex_shape()
	else:
		var concave_area_shape: ConcavePolygonShape3D = trimesh_source.mesh.create_trimesh_shape()
		if concave_area_shape:
			concave_area_shape.backface_collision = false
		area_shape = concave_area_shape
	if not area_shape:
		return

	surface_normal_source = trimesh_source
	_set_descendant_colliders_non_alignable(trimesh_source)
	_disable_descendant_collision_shapes(trimesh_source)
	var area_collision: CollisionShape3D = CollisionShape3D.new()
	area_collision.name = "GeneratedTrimeshAreaCollision"
	area_collision.shape = area_shape
	add_child(area_collision)
	area_collision.global_transform = trimesh_source.global_transform

	if not surface_collision_body:
		surface_collision_body = StaticBody3D.new()
		surface_collision_body.name = "GeneratedTrimeshSolidBody"
		add_child(surface_collision_body)
	surface_collision_body.collision_layer = 1 << 6
	surface_collision_body.collision_mask = collision_mask

	var solid_shape: ConcavePolygonShape3D = trimesh_source.mesh.create_trimesh_shape()
	if not solid_shape:
		return
	solid_shape.backface_collision = false
	var solid_collision: CollisionShape3D = CollisionShape3D.new()
	solid_collision.name = "GeneratedTrimeshSolidCollision"
	solid_collision.shape = solid_shape
	surface_collision_body.add_child(solid_collision)
	solid_collision.global_transform = trimesh_source.global_transform


func _set_descendant_colliders_non_alignable(node: Node) -> void:
	for child: Node in node.get_children():
		if child is CollisionObject3D:
			var collision_object: CollisionObject3D = child as CollisionObject3D
			collision_object.collision_layer = collision_object.collision_layer | (1 << 6)
		_set_descendant_colliders_non_alignable(child)


func _disable_descendant_collision_shapes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
		_disable_descendant_collision_shapes(child)


func _physics_process(delta: float) -> void:
	var expired_ids: Array[int] = []
	for body_id: int in _body_cooldowns:
		var remaining_time: float = float(_body_cooldowns[body_id]) - delta
		_body_cooldowns[body_id] = remaining_time
		if remaining_time <= 0.0:
			expired_ids.append(body_id)

	for body_id: int in expired_ids:
		_body_cooldowns.erase(body_id)
		_try_rehit_after_cooldown(body_id)

	var invalid_body_ids: Array[int] = []
	for body_id: int in _tracked_bodies:
		var tracked_body: Node3D = _tracked_bodies[body_id] as Node3D
		if not is_instance_valid(tracked_body):
			invalid_body_ids.append(body_id)
			continue
		_try_bounce_body(tracked_body)
	for body_id: int in invalid_body_ids:
		_tracked_bodies.erase(body_id)


func _on_body_entered(body: Node3D) -> void:
	_tracked_bodies[body.get_instance_id()] = body
	_try_bounce_body(body)


func _on_body_exited(body: Node3D) -> void:
	_tracked_bodies.erase(body.get_instance_id())


func resolve_player_collision_contact(body: Node3D, incoming_velocity: Vector3, contact_normal: Vector3) -> bool:
	var direction_override: Vector3 = contact_normal if launch_mode == LaunchMode.SURFACE_NORMAL else Vector3.ZERO
	return _try_bounce_body(body, direction_override, incoming_velocity)


func _try_bounce_body(body: Node3D, launch_direction_override: Vector3 = Vector3.ZERO, incoming_velocity_override: Variant = null) -> bool:
	if not active or not body.has_method("apply_spring_impulse"):
		return false
	if body.has_method("is_carried") and bool(body.call("is_carried")):
		return false

	var body_id: int = body.get_instance_id()
	if float(_body_cooldowns.get(body_id, 0.0)) > 0.0:
		return false

	var incoming_velocity: Vector3 = _get_body_velocity(body)
	if incoming_velocity_override is Vector3:
		incoming_velocity = incoming_velocity_override
	var launch_direction: Vector3 = launch_direction_override
	if launch_direction.length_squared() <= 0.000001:
		launch_direction = _get_launch_direction(body, incoming_velocity)
	if launch_direction.length_squared() <= 0.000001:
		return false
	var launch_velocity: Vector3 = _get_bounce_velocity(incoming_velocity, launch_direction)
	if launch_velocity.length_squared() <= 0.000001:
		return false
	if override_previous_lock_timers and body.has_method("clear_object_lock_timers"):
		body.call("clear_object_lock_timers")
	body.call(
		"apply_spring_impulse",
		global_position,
		launch_velocity.normalized(),
		launch_velocity.length(),
		false,
		true,
		1,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
		global_basis,
		true,
		true,
		false,
		1.0,
		detach_from_ground,
		false
	)
	if body.has_method("register_combo_feat"):
		body.call("register_combo_feat", &"bumper_bounce", "Bumper Bounce", 125.0, 0.8)

	_body_cooldowns[body_id] = rehit_cooldown
	_play_sound()
	_play_visual_bounce()
	return true


func _try_rehit_after_cooldown(body_id: int) -> bool:
	if not _tracked_bodies.has(body_id):
		return false

	var body: Node3D = _tracked_bodies[body_id] as Node3D
	if not is_instance_valid(body):
		return false

	var incoming_velocity: Vector3 = _get_body_velocity(body)
	var surface_normal: Vector3 = _get_slide_collision_surface_normal(body, incoming_velocity)
	if surface_normal.length_squared() <= 0.000001:
		return false
	if launch_mode == LaunchMode.SURFACE_NORMAL:
		return _try_bounce_body(body, surface_normal)
	return _try_bounce_body(body)


func _get_bounce_velocity(incoming_velocity: Vector3, surface_normal: Vector3) -> Vector3:
	var normal: Vector3 = surface_normal.normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.UP

	var incoming_speed: float = incoming_velocity.length()
	var normal_speed: float = incoming_velocity.dot(normal)
	var outgoing_direction: Vector3 = normal
	if normal_speed < 0.0 and incoming_speed > 0.000001:
		var reflected_velocity: Vector3 = incoming_velocity - normal * normal_speed * 2.0
		if preserve_tangential_velocity:
			outgoing_direction = reflected_velocity.normalized()

	var outgoing_speed: float = incoming_speed * max(mirrored_bounce_ratio, 0.0)
	outgoing_speed = max(outgoing_speed, minimum_impulse)
	if maximum_impulse > 0.0:
		outgoing_speed = min(outgoing_speed, maximum_impulse)
	return outgoing_direction * outgoing_speed


func _get_body_velocity(body: Node3D) -> Vector3:
	if body.has_method("get_external_pre_collision_velocity"):
		var pre_collision_velocity: Variant = body.call("get_external_pre_collision_velocity")
		if pre_collision_velocity is Vector3:
			return pre_collision_velocity
	if body is CharacterBody3D:
		return (body as CharacterBody3D).velocity
	if body is RigidBody3D:
		return (body as RigidBody3D).linear_velocity
	return Vector3.ZERO


func _get_launch_direction(body: Node3D, incoming_velocity: Vector3) -> Vector3:
	var radial_direction: Vector3 = body.global_position - global_position
	if radial_direction.length_squared() <= 0.000001:
		radial_direction = global_basis.y
	radial_direction = radial_direction.normalized()

	match launch_mode:
		LaunchMode.SURFACE_NORMAL:
			return _get_surface_normal(body, incoming_velocity, radial_direction)
		LaunchMode.SPECIFIED_DIRECTION:
			var direction: Vector3 = global_basis * specified_launch_direction
			if direction.length_squared() > 0.000001:
				return direction.normalized()

	return radial_direction


func _get_surface_normal(body: Node3D, incoming_velocity: Vector3, fallback: Vector3) -> Vector3:
	var slide_normal: Vector3 = _get_slide_collision_surface_normal(body, incoming_velocity)
	if slide_normal.length_squared() > 0.000001:
		return slide_normal
	var collision_normal: Vector3 = _get_collision_surface_normal(body.global_position, incoming_velocity)
	if collision_normal.length_squared() > 0.000001:
		return collision_normal
	if generate_trimesh_collision and trimesh_source:
		return Vector3.ZERO
	if not surface_normal_source:
		return fallback

	var source_mesh: Mesh
	if surface_normal_source is MeshInstance3D:
		source_mesh = (surface_normal_source as MeshInstance3D).mesh
	elif surface_normal_source is CollisionShape3D:
		var collision_shape: CollisionShape3D = surface_normal_source as CollisionShape3D
		if collision_shape.shape:
			source_mesh = collision_shape.shape.get_debug_mesh()

	if not source_mesh:
		return fallback

	var source_inverse: Transform3D = surface_normal_source.global_transform.affine_inverse()
	var local_point: Vector3 = source_inverse * body.global_position
	var local_velocity: Vector3 = source_inverse.basis * incoming_velocity
	var mesh_center: Vector3 = source_mesh.get_aabb().get_center()
	var ray_direction: Vector3 = local_velocity.normalized()
	var ray_length: float = max(
		local_velocity.length() * get_physics_process_delta_time() * 2.0,
		source_mesh.get_aabb().size.length() * 2.0
	)
	var ray_origin: Vector3 = local_point - ray_direction * ray_length
	var closest_ray_distance: float = INF
	var entry_normal: Vector3 = Vector3.ZERO
	var closest_distance_squared: float = INF
	var closest_normal: Vector3 = Vector3.ZERO

	for surface_index: int in range(source_mesh.get_surface_count()):
		var arrays: Array = source_mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX]
		var triangle_count: int = int(indices.size() / 3) if not indices.is_empty() else int(vertices.size() / 3)
		for triangle_index: int in range(triangle_count):
			var vertex_offset: int = triangle_index * 3
			var index_a: int = indices[vertex_offset] if not indices.is_empty() else vertex_offset
			var index_b: int = indices[vertex_offset + 1] if not indices.is_empty() else vertex_offset + 1
			var index_c: int = indices[vertex_offset + 2] if not indices.is_empty() else vertex_offset + 2
			var point_a: Vector3 = vertices[index_a]
			var point_b: Vector3 = vertices[index_b]
			var point_c: Vector3 = vertices[index_c]
			var candidate_normal: Vector3 = (point_b - point_a).cross(point_c - point_a)
			if candidate_normal.length_squared() <= 0.000001:
				continue
			candidate_normal = candidate_normal.normalized()
			var triangle_center: Vector3 = (point_a + point_b + point_c) / 3.0
			if candidate_normal.dot(triangle_center - mesh_center) < 0.0:
				candidate_normal = -candidate_normal

			if ray_direction.length_squared() > 0.000001:
				var ray_distance: float = _ray_triangle_distance(ray_origin, ray_direction, point_a, point_b, point_c)
				if ray_distance >= 0.0 and ray_distance <= ray_length and ray_distance < closest_ray_distance:
					closest_ray_distance = ray_distance
					entry_normal = candidate_normal

			var candidate_point: Vector3 = _closest_point_on_triangle(local_point, point_a, point_b, point_c)
			var distance_squared: float = local_point.distance_squared_to(candidate_point)
			if distance_squared >= closest_distance_squared:
				continue
			closest_distance_squared = distance_squared
			closest_normal = candidate_normal

	var used_entry_normal: bool = entry_normal.length_squared() > 0.000001
	var selected_normal: Vector3 = entry_normal if used_entry_normal else closest_normal
	if selected_normal.length_squared() <= 0.000001:
		return fallback

	var normal_basis: Basis = surface_normal_source.global_basis.inverse().transposed()
	var world_normal: Vector3 = normal_basis * selected_normal
	if world_normal.length_squared() <= 0.000001:
		return fallback
	world_normal = world_normal.normalized()
	if used_entry_normal and world_normal.dot(incoming_velocity) > 0.0:
		world_normal = -world_normal
	return world_normal


func _get_slide_collision_surface_normal(body: Node3D, incoming_velocity: Vector3) -> Vector3:
	if not (body is CharacterBody3D) or not surface_collision_body:
		return Vector3.ZERO

	var character_body: CharacterBody3D = body as CharacterBody3D
	for collision_index: int in range(character_body.get_slide_collision_count()):
		var collision: KinematicCollision3D = character_body.get_slide_collision(collision_index)
		if not collision or collision.get_collider() != surface_collision_body:
			continue
		var hit_normal: Vector3 = collision.get_normal().normalized()
		if hit_normal.length_squared() <= 0.000001:
			continue
		if hit_normal.dot(incoming_velocity) > 0.0:
			hit_normal = -hit_normal
		return hit_normal

	return Vector3.ZERO


func _get_collision_surface_normal(body_position: Vector3, incoming_velocity: Vector3) -> Vector3:
	if not surface_collision_body or incoming_velocity.length_squared() <= 0.000001:
		return Vector3.ZERO

	var travel_direction: Vector3 = incoming_velocity.normalized()
	var frame_distance: float = incoming_velocity.length() * get_physics_process_delta_time()
	var sweep_distance: float = max(frame_distance * 2.0, 10.0)
	var ray_start: Vector3 = body_position - travel_direction * sweep_distance
	var ray_end: Vector3 = body_position + travel_direction * sweep_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_start,
		ray_end,
		surface_collision_body.collision_layer
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true

	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") != surface_collision_body:
		return Vector3.ZERO
	var hit_position: Vector3 = hit.get("position", body_position)
	if surface_contact_distance > 0.0 and body_position.distance_to(hit_position) > surface_contact_distance:
		return Vector3.ZERO

	var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if hit_normal.length_squared() <= 0.000001:
		return Vector3.ZERO
	hit_normal = hit_normal.normalized()
	if hit_normal.dot(incoming_velocity) > 0.0:
		hit_normal = -hit_normal
	return hit_normal


func _ray_triangle_distance(
	ray_origin: Vector3,
	ray_direction: Vector3,
	point_a: Vector3,
	point_b: Vector3,
	point_c: Vector3
) -> float:
	var edge_ab: Vector3 = point_b - point_a
	var edge_ac: Vector3 = point_c - point_a
	var determinant_axis: Vector3 = ray_direction.cross(edge_ac)
	var determinant: float = edge_ab.dot(determinant_axis)
	if abs(determinant) <= 0.000001:
		return -1.0

	var inverse_determinant: float = 1.0 / determinant
	var origin_offset: Vector3 = ray_origin - point_a
	var barycentric_b: float = origin_offset.dot(determinant_axis) * inverse_determinant
	if barycentric_b < 0.0 or barycentric_b > 1.0:
		return -1.0

	var barycentric_axis: Vector3 = origin_offset.cross(edge_ab)
	var barycentric_c: float = ray_direction.dot(barycentric_axis) * inverse_determinant
	if barycentric_c < 0.0 or barycentric_b + barycentric_c > 1.0:
		return -1.0

	var ray_distance: float = edge_ac.dot(barycentric_axis) * inverse_determinant
	return ray_distance if ray_distance >= 0.0 else -1.0


func _closest_point_on_triangle(point: Vector3, point_a: Vector3, point_b: Vector3, point_c: Vector3) -> Vector3:
	var edge_ab: Vector3 = point_b - point_a
	var edge_ac: Vector3 = point_c - point_a
	var offset_ap: Vector3 = point - point_a
	var dot_ab_ap: float = edge_ab.dot(offset_ap)
	var dot_ac_ap: float = edge_ac.dot(offset_ap)
	if dot_ab_ap <= 0.0 and dot_ac_ap <= 0.0:
		return point_a

	var offset_bp: Vector3 = point - point_b
	var dot_ab_bp: float = edge_ab.dot(offset_bp)
	var dot_ac_bp: float = edge_ac.dot(offset_bp)
	if dot_ab_bp >= 0.0 and dot_ac_bp <= dot_ab_bp:
		return point_b

	var edge_region_c: float = dot_ab_ap * dot_ac_bp - dot_ab_bp * dot_ac_ap
	if edge_region_c <= 0.0 and dot_ab_ap >= 0.0 and dot_ab_bp <= 0.0:
		var edge_ratio: float = dot_ab_ap / (dot_ab_ap - dot_ab_bp)
		return point_a + edge_ab * edge_ratio

	var offset_cp: Vector3 = point - point_c
	var dot_ab_cp: float = edge_ab.dot(offset_cp)
	var dot_ac_cp: float = edge_ac.dot(offset_cp)
	if dot_ac_cp >= 0.0 and dot_ab_cp <= dot_ac_cp:
		return point_c

	var edge_region_b: float = dot_ab_cp * dot_ac_ap - dot_ab_ap * dot_ac_cp
	if edge_region_b <= 0.0 and dot_ac_ap >= 0.0 and dot_ac_cp <= 0.0:
		var edge_ratio: float = dot_ac_ap / (dot_ac_ap - dot_ac_cp)
		return point_a + edge_ac * edge_ratio

	var edge_region_a: float = dot_ab_bp * dot_ac_cp - dot_ab_cp * dot_ac_bp
	if edge_region_a <= 0.0 and (dot_ac_bp - dot_ab_bp) >= 0.0 and (dot_ab_cp - dot_ac_cp) >= 0.0:
		var edge_bc: Vector3 = point_c - point_b
		var edge_ratio: float = (dot_ac_bp - dot_ab_bp) / ((dot_ac_bp - dot_ab_bp) + (dot_ab_cp - dot_ac_cp))
		return point_b + edge_bc * edge_ratio

	var inverse_total: float = 1.0 / (edge_region_a + edge_region_b + edge_region_c)
	var barycentric_b: float = edge_region_b * inverse_total
	var barycentric_c: float = edge_region_c * inverse_total
	return point_a + edge_ab * barycentric_b + edge_ac * barycentric_c


func _play_sound() -> void:
	if not sfx_player or not bumper_sound:
		return
	sfx_player.stream = bumper_sound
	sfx_player.play()


func _play_visual_bounce() -> void:
	if not visual_bounce_enabled or not visual_root:
		return
	if _visual_tween:
		_visual_tween.kill()
	visual_root.scale = _visual_base_scale
	if visual_bounce_duration <= 0.0:
		return
	var peak_scale: Vector3 = _visual_base_scale * visual_bounce_peak_scale
	_visual_tween = create_tween()
	_visual_tween.tween_property(visual_root, "scale", peak_scale, visual_bounce_duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_visual_tween.tween_property(visual_root, "scale", _visual_base_scale, visual_bounce_duration * 0.65).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

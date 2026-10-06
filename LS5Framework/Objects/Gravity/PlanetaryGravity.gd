extends Area3D
class_name PlanetaryGravity

enum FalloffMode {
	CONSTANT,
	LINEAR,
	INVERSE_SQUARE
}

@export_group("Activation")
## Enables this planetary gravity field.
@export var active: bool = true
## Primary group accepted by this field.
@export var require_group_primary: StringName = &"Player"
## Secondary group accepted by this field.
@export var require_group_secondary: StringName = &"player"
## Physics layers containing optional non-player gravity followers.
@export_flags_3d_physics var gravity_follower_collision_mask: int = 130

@export_group("Gravity")
## Multiplier applied to each affected body's base gravity strength.
@export var gravity_multiplier: float = 1.0
## Radius used for influence and falloff calculations.
@export var influence_radius: float = 40.0
## Controls gravity strength across the influence radius.
@export var falloff_mode: FalloffMode = FalloffMode.CONSTANT
## Minimum multiplier retained by linear falloff at the influence edge.
@export_range(0.0, 1.0) var linear_edge_multiplier: float = 0.0
## Distance where inverse-square falloff has full strength.
@export var inverse_square_reference_distance: float = 8.0

@export_group("Surface Solver")
## Uses collision normals from the gravity surface before falling back to center-point gravity.
@export var prefer_surface_raycast: bool = true
## Physics layers containing the gravity surface.
@export_flags_3d_physics var surface_raycast_mask: int = 1
## Extra distance added past the gravity center for surface raycasts.
@export var surface_raycast_extra_distance: float = 0.5

@export_group("Nodes")
## Node used as the planetary gravity center. The area origin is used when empty.
@export var gravity_center_path: NodePath = NodePath("GravityCenter")
## Collision body or mesh representing the planetary surface used by the normal solver.
@export var gravity_surface_path: NodePath = NodePath("GravitySurface")
## CollisionShape3D defining the field's area of influence.
@export var influence_shape_path: NodePath = NodePath("InfluenceShape")

var _gravity_center: Node3D = null
var _gravity_surface: Node3D = null
var _influence_shape: CollisionShape3D = null
var _tracked_bodies: Dictionary = {}


func _ready() -> void:
	collision_mask |= gravity_follower_collision_mask
	_gravity_center = get_node_or_null(gravity_center_path) as Node3D
	_gravity_surface = get_node_or_null(gravity_surface_path) as Node3D
	_influence_shape = get_node_or_null(influence_shape_path) as CollisionShape3D
	_update_influence_shape()
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if not active:
		_unregister_all_bodies()
		return
	for body in get_overlapping_bodies():
		if body is Node3D and _is_gravity_body(body):
			_register_body(body)
	var stale_ids: Array = []
	for body_id in _tracked_bodies.keys():
		var body_ref: Variant = _tracked_bodies.get(body_id)
		if not (body_ref is WeakRef):
			stale_ids.append(body_id)
			continue
		var body: Node3D = body_ref.get_ref() as Node3D
		var physics_body: PhysicsBody3D = body as PhysicsBody3D
		if body == null or not is_instance_valid(body) or physics_body == null or not overlaps_body(physics_body) or not _is_gravity_body(body):
			if body != null and is_instance_valid(body) and body.has_method("unregister_planetary_gravity_source"):
				body.call("unregister_planetary_gravity_source", self)
			stale_ids.append(body_id)
	for body_id in stale_ids:
		_tracked_bodies.erase(body_id)


func _exit_tree() -> void:
	_unregister_all_bodies()


func _on_body_entered(body: Node3D) -> void:
	if active and _is_gravity_body(body):
		_register_body(body)


func _on_body_exited(body: Node3D) -> void:
	if body == null:
		return
	_tracked_bodies.erase(body.get_instance_id())
	if body.has_method("unregister_planetary_gravity_source"):
		body.call("unregister_planetary_gravity_source", self)


func _register_body(body: Node3D) -> void:
	if not body.has_method("register_planetary_gravity_source"):
		return
	var body_id: int = body.get_instance_id()
	if _tracked_bodies.has(body_id):
		return
	_tracked_bodies[body_id] = weakref(body)
	body.call("register_planetary_gravity_source", self)


func _unregister_all_bodies() -> void:
	for body_ref in _tracked_bodies.values():
		if not (body_ref is WeakRef):
			continue
		var body: Node = body_ref.get_ref() as Node
		if body != null and is_instance_valid(body) and body.has_method("unregister_planetary_gravity_source"):
			body.call("unregister_planetary_gravity_source", self)
	_tracked_bodies.clear()


func get_planetary_gravity_vector(body: Node3D) -> Vector3:
	if not active or body == null or not is_instance_valid(body):
		return Vector3.ZERO
	var center: Vector3 = _get_gravity_center_position()
	var to_center: Vector3 = center - body.global_position
	var distance: float = to_center.length()
	if distance < 0.001:
		return Vector3.ZERO
	var radius: float = max(influence_radius, 0.001)
	if distance > radius:
		return Vector3.ZERO
	var gravity_down: Vector3 = to_center / distance
	if prefer_surface_raycast:
		var surface_down: Vector3 = _get_surface_gravity_down(body, center, gravity_down)
		if surface_down.length() >= 0.001:
			gravity_down = surface_down
	var strength_factor: float = max(gravity_multiplier, 0.0) * _get_falloff_multiplier(distance, radius)
	return gravity_down * strength_factor


func _get_surface_gravity_down(
	body: Node3D,
	center: Vector3,
	center_down: Vector3
) -> Vector3:
	if _gravity_surface == null or not is_instance_valid(_gravity_surface):
		return Vector3.ZERO
	var world: World3D = get_world_3d()
	if world == null:
		return Vector3.ZERO
	var ray_end: Vector3 = center + center_down * max(surface_raycast_extra_distance, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(body.global_position, ray_end)
	query.collision_mask = surface_raycast_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_back_faces = true
	query.hit_from_inside = true
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty() or not _is_gravity_surface_collider(hit.get("collider")):
		return Vector3.ZERO
	var normal_value = hit.get("normal")
	if not (normal_value is Vector3):
		return Vector3.ZERO
	var surface_normal: Vector3 = normal_value
	var surface_down: Vector3 = -surface_normal.normalized()
	if surface_down.length() < 0.001:
		return Vector3.ZERO
	if surface_down.dot(center_down) < 0.0:
		surface_down = -surface_down
	return surface_down


func _is_gravity_surface_collider(collider) -> bool:
	if not (collider is Node):
		return false
	var collider_node: Node = collider
	if collider_node == _gravity_surface:
		return true
	if _gravity_surface.is_ancestor_of(collider_node):
		return true
	return collider_node.is_ancestor_of(_gravity_surface)


func _get_falloff_multiplier(distance: float, radius: float) -> float:
	match falloff_mode:
		FalloffMode.LINEAR:
			var t: float = clamp(distance / radius, 0.0, 1.0)
			return lerp(1.0, clamp(linear_edge_multiplier, 0.0, 1.0), t)
		FalloffMode.INVERSE_SQUARE:
			var reference: float = max(inverse_square_reference_distance, 0.001)
			var divisor: float = max(distance, reference)
			return (reference * reference) / (divisor * divisor)
		_:
			return 1.0


func _get_gravity_center_position() -> Vector3:
	if _gravity_center != null and is_instance_valid(_gravity_center):
		return _gravity_center.global_position
	return global_position


func _update_influence_shape() -> void:
	if _influence_shape == null or _influence_shape.shape == null:
		return
	if _influence_shape.shape is SphereShape3D:
		(_influence_shape.shape as SphereShape3D).radius = max(influence_radius, 0.001)


func _is_gravity_body(body: Node) -> bool:
	if body == null or not body.has_method("register_planetary_gravity_source"):
		return false
	if require_group_primary != &"" and body.is_in_group(require_group_primary):
		return true
	if require_group_secondary != &"" and body.is_in_group(require_group_secondary):
		return true
	if require_group_primary == &"" and require_group_secondary == &"":
		return true
	if not body.has_method("is_gravity_pull_enabled"):
		return false
	var enabled_value: Variant = body.call("is_gravity_pull_enabled")
	return enabled_value is bool and bool(enabled_value)


func reset_for_race_restart() -> void:
	_unregister_all_bodies()

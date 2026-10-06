extends Node3D
class_name PhysicsShapeEmitter

## Physics Shape Emitter
## Spawns random rigid bodies (sphere, box, cylinder, capsule) with varied physics.
## Designed for Jolt compatibility by using standard RigidBody3D + Shape3D nodes.
##
## Usage:
## - Drop the scene in a level.
## - Adjust spawn settings, shape toggles, and physics ranges in the inspector.
## - The spawned bodies use collision_layer/mask settings below for player collision.

@export_group("Spawn")
@export var spawn_enabled: bool = true
@export var spawn_on_ready: bool = true
@export var spawn_interval_sec: float = 0.5
@export var spawn_count: int = 1
@export var max_alive: int = 40
@export var spawn_parent_path: NodePath = NodePath("")
@export var spawn_local_space: bool = true
@export var spawn_box_extents: Vector3 = Vector3(2.0, 1.0, 2.0)
@export var randomize_rotation: bool = true

@export_group("Lifetime")
@export var lifetime_sec: float = 0.0
@export var cleanup_on_exit: bool = true
@export var spawned_group: StringName = &"physics_shape_spawn"

@export_group("Collision")
@export var collision_layer: int = 1
# Default mask collides with level (layer 1) and player (layer 4).
@export var collision_mask: int = 5

@export_group("Shapes")
@export var allow_sphere: bool = true
@export var allow_box: bool = true
@export var allow_cylinder: bool = true
@export var allow_capsule: bool = true
@export var sphere_radius_min: float = 0.35
@export var sphere_radius_max: float = 0.85
@export var box_size_min: Vector3 = Vector3(0.4, 0.4, 0.4)
@export var box_size_max: Vector3 = Vector3(1.1, 1.1, 1.1)
@export var cylinder_radius_min: float = 0.25
@export var cylinder_radius_max: float = 0.6
@export var cylinder_height_min: float = 0.5
@export var cylinder_height_max: float = 1.2
@export var capsule_radius_min: float = 0.25
@export var capsule_radius_max: float = 0.5
@export var capsule_height_min: float = 0.6
@export var capsule_height_max: float = 1.4

@export_group("Visual")
@export var material_override: Material
@export var randomize_albedo: bool = true
@export var albedo_min: Color = Color(0.6, 0.6, 0.6, 1.0)
@export var albedo_max: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Physics Attributes")
@export var mass_min: float = 0.5
@export var mass_max: float = 6.0
@export var friction_min: float = 0.4
@export var friction_max: float = 1.1
@export var bounce_min: float = 0.0
@export var bounce_max: float = 0.6
@export var linear_damp_min: float = 0.0
@export var linear_damp_max: float = 0.2
@export var angular_damp_min: float = 0.0
@export var angular_damp_max: float = 0.3
@export var gravity_scale_min: float = 0.8
@export var gravity_scale_max: float = 1.4

@export_group("Velocity")
@export var linear_velocity_min: Vector3 = Vector3(-1.5, 0.5, -1.5)
@export var linear_velocity_max: Vector3 = Vector3(1.5, 4.0, 1.5)
@export var angular_velocity_min: Vector3 = Vector3(-3.0, -3.0, -3.0)
@export var angular_velocity_max: Vector3 = Vector3(3.0, 3.0, 3.0)
@export var velocity_local_space: bool = true
@export var angular_velocity_local_space: bool = true

enum ShapeType {
	SPHERE,
	BOX,
	CYLINDER,
	CAPSULE
}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawn_accum: float = 0.0
var _spawned: Array[RigidBody3D] = []


func _ready() -> void:
	_rng.randomize()
	set_physics_process(true)
	if spawn_on_ready and spawn_enabled:
		_spawn_batch()


func _exit_tree() -> void:
	if not cleanup_on_exit:
		return
	_cleanup_spawned()


func _physics_process(delta: float) -> void:
	if not spawn_enabled:
		return

	_prune_spawned()

	var interval: float = max(spawn_interval_sec, 0.0)
	if interval <= 0.0:
		_spawn_batch()
		return

	_spawn_accum += delta
	while _spawn_accum >= interval:
		_spawn_accum -= interval
		_spawn_batch()


func _spawn_batch() -> void:
	if spawn_count <= 0:
		return
	_prune_spawned()

	for i in range(spawn_count):
		if max_alive > 0 and _spawned.size() >= max_alive:
			return
		var body: RigidBody3D = _spawn_one()
		if body != null:
			_spawned.append(body)


func _spawn_one() -> RigidBody3D:
	var shape_type: int = _pick_shape_type()
	if shape_type < 0:
		return null

	var body := RigidBody3D.new()
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	body.mass = _rand_range(mass_min, mass_max)
	body.linear_damp = _rand_range(linear_damp_min, linear_damp_max)
	body.angular_damp = _rand_range(angular_damp_min, angular_damp_max)
	body.gravity_scale = _rand_range(gravity_scale_min, gravity_scale_max)
	body.sleeping = false

	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = _rand_range(friction_min, friction_max)
	phys_mat.bounce = _rand_range(bounce_min, bounce_max)
	body.physics_material_override = phys_mat

	var collision_shape := CollisionShape3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh: Mesh = null
	var shape: Shape3D = null

	if shape_type == ShapeType.SPHERE:
		var radius: float = _rand_range(sphere_radius_min, sphere_radius_max)
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = radius
		sphere_mesh.height = radius * 2.0
		mesh = sphere_mesh
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = radius
		shape = sphere_shape
	elif shape_type == ShapeType.BOX:
		var size: Vector3 = _rand_vec3(box_size_min, box_size_max)
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh = box_mesh
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape = box_shape
	elif shape_type == ShapeType.CYLINDER:
		var radius_c: float = _rand_range(cylinder_radius_min, cylinder_radius_max)
		var height_c: float = _rand_range(cylinder_height_min, cylinder_height_max)
		var cyl_mesh := CylinderMesh.new()
		cyl_mesh.top_radius = radius_c
		cyl_mesh.bottom_radius = radius_c
		cyl_mesh.height = height_c
		mesh = cyl_mesh
		var cyl_shape := CylinderShape3D.new()
		cyl_shape.radius = radius_c
		cyl_shape.height = height_c
		shape = cyl_shape
	elif shape_type == ShapeType.CAPSULE:
		var radius_cap: float = _rand_range(capsule_radius_min, capsule_radius_max)
		var height_cap: float = _rand_range(capsule_height_min, capsule_height_max)
		var cap_mesh := CapsuleMesh.new()
		cap_mesh.radius = radius_cap
		cap_mesh.height = height_cap
		mesh = cap_mesh
		var cap_shape := CapsuleShape3D.new()
		cap_shape.radius = radius_cap
		cap_shape.height = height_cap
		shape = cap_shape

	if mesh == null or shape == null:
		body.queue_free()
		return null

	mesh_instance.mesh = mesh
	if material_override != null:
		mesh_instance.material_override = material_override
	elif randomize_albedo:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _rand_color(albedo_min, albedo_max)
		mesh_instance.material_override = mat

	collision_shape.shape = shape
	body.add_child(mesh_instance)
	body.add_child(collision_shape)

	var parent: Node = _resolve_spawn_parent()
	if parent == null:
		body.queue_free()
		return null
	parent.add_child(body)

	var spawn_pos: Vector3 = _pick_spawn_position()
	var spawn_basis: Basis = _pick_spawn_basis()
	body.global_transform = Transform3D(spawn_basis, spawn_pos)
	body.add_to_group(spawned_group)

	_apply_initial_velocity(body)
	_setup_lifetime(body)
	_connect_cleanup(body)

	return body


func _pick_shape_type() -> int:
	var candidates: Array[int] = []
	if allow_sphere:
		candidates.append(ShapeType.SPHERE)
	if allow_box:
		candidates.append(ShapeType.BOX)
	if allow_cylinder:
		candidates.append(ShapeType.CYLINDER)
	if allow_capsule:
		candidates.append(ShapeType.CAPSULE)

	if candidates.is_empty():
		return -1

	var idx: int = _rng.randi_range(0, candidates.size() - 1)
	return candidates[idx]


func _pick_spawn_position() -> Vector3:
	var ext: Vector3 = Vector3(abs(spawn_box_extents.x), abs(spawn_box_extents.y), abs(spawn_box_extents.z))
	var offset: Vector3 = Vector3(
		_rand_range(-ext.x, ext.x),
		_rand_range(-ext.y, ext.y),
		_rand_range(-ext.z, ext.z)
	)

	if spawn_local_space:
		return global_position + (global_transform.basis * offset)
	return global_position + offset


func _pick_spawn_basis() -> Basis:
	if not randomize_rotation:
		return global_transform.basis

	var pitch: float = _rand_range(-PI, PI)
	var yaw: float = _rand_range(-PI, PI)
	var roll: float = _rand_range(-PI, PI)
	var rand_basis := Basis.from_euler(Vector3(pitch, yaw, roll))

	if spawn_local_space:
		return global_transform.basis * rand_basis
	return rand_basis


func _apply_initial_velocity(body: RigidBody3D) -> void:
	var v: Vector3 = _rand_vec3(linear_velocity_min, linear_velocity_max)
	if velocity_local_space:
		v = global_transform.basis * v
	body.linear_velocity = v

	var w: Vector3 = _rand_vec3(angular_velocity_min, angular_velocity_max)
	if angular_velocity_local_space:
		w = global_transform.basis * w
	body.angular_velocity = w


func _setup_lifetime(body: RigidBody3D) -> void:
	var life: float = max(lifetime_sec, 0.0)
	if life <= 0.0:
		return

	var t := Timer.new()
	t.one_shot = true
	t.wait_time = life
	body.add_child(t)
	t.timeout.connect(func():
		if is_instance_valid(body):
			body.queue_free()
	)
	t.start()


func _connect_cleanup(body: RigidBody3D) -> void:
	if not body.tree_exited.is_connected(_on_spawned_tree_exited):
		body.tree_exited.connect(_on_spawned_tree_exited.bind(body))


func _on_spawned_tree_exited(body: RigidBody3D) -> void:
	_spawned.erase(body)


func _prune_spawned() -> void:
	for i in range(_spawned.size() - 1, -1, -1):
		var body: RigidBody3D = _spawned[i]
		if body == null or not is_instance_valid(body):
			_spawned.remove_at(i)


func _cleanup_spawned() -> void:
	for body in _spawned:
		if body != null and is_instance_valid(body):
			body.queue_free()
	_spawned.clear()


func _resolve_spawn_parent() -> Node:
	if spawn_parent_path != NodePath(""):
		var node = get_node_or_null(spawn_parent_path)
		if node != null:
			return node

	var parent: Node = get_parent()
	if parent != null:
		return parent
	return get_tree().current_scene


func _rand_range(min_value: float, max_value: float) -> float:
	var lo: float = min(min_value, max_value)
	var hi: float = max(min_value, max_value)
	return _rng.randf_range(lo, hi)


func _rand_vec3(min_value: Vector3, max_value: Vector3) -> Vector3:
	return Vector3(
		_rand_range(min_value.x, max_value.x),
		_rand_range(min_value.y, max_value.y),
		_rand_range(min_value.z, max_value.z)
	)


func _rand_color(min_value: Color, max_value: Color) -> Color:
	return Color(
		_rand_range(min_value.r, max_value.r),
		_rand_range(min_value.g, max_value.g),
		_rand_range(min_value.b, max_value.b),
		_rand_range(min_value.a, max_value.a)
	)

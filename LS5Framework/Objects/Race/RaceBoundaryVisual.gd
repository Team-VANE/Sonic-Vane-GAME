@tool
extends MeshInstance3D

## Collision shape used to size and position the boundary visual.
@export_node_path("CollisionShape3D") var collision_shape_path: NodePath = NodePath("../CollisionShape3D")

var _collision_shape: CollisionShape3D = null
var _tracked_shape: Shape3D = null


func _ready() -> void:
	set_process(true)
	_resolve_collision_shape()


func _process(_delta: float) -> void:
	if not is_instance_valid(_collision_shape):
		_resolve_collision_shape()
	if not is_instance_valid(_collision_shape):
		return
	if _tracked_shape != _collision_shape.shape:
		_track_shape(_collision_shape.shape)
	if transform != _collision_shape.transform:
		transform = _collision_shape.transform


func _resolve_collision_shape() -> void:
	_collision_shape = get_node_or_null(collision_shape_path) as CollisionShape3D
	_track_shape(_collision_shape.shape if is_instance_valid(_collision_shape) else null)


func _track_shape(shape: Shape3D) -> void:
	if is_instance_valid(_tracked_shape) and _tracked_shape.changed.is_connected(_sync_from_collision_shape):
		_tracked_shape.changed.disconnect(_sync_from_collision_shape)
	_tracked_shape = shape
	if is_instance_valid(_tracked_shape) and not _tracked_shape.changed.is_connected(_sync_from_collision_shape):
		_tracked_shape.changed.connect(_sync_from_collision_shape)
	_sync_from_collision_shape()


func _sync_from_collision_shape() -> void:
	if not is_instance_valid(_collision_shape):
		mesh = null
		return
	var shape: Shape3D = _collision_shape.shape
	if shape is BoxShape3D:
		var box_shape: BoxShape3D = shape as BoxShape3D
		var box_mesh: BoxMesh = mesh as BoxMesh
		if box_mesh == null:
			box_mesh = BoxMesh.new()
			mesh = box_mesh
		box_mesh.size = box_shape.size
	elif shape is SphereShape3D:
		var sphere_shape: SphereShape3D = shape as SphereShape3D
		var sphere_mesh: SphereMesh = mesh as SphereMesh
		if sphere_mesh == null:
			sphere_mesh = SphereMesh.new()
			mesh = sphere_mesh
		sphere_mesh.radius = sphere_shape.radius
		sphere_mesh.height = sphere_shape.radius * 2.0
	elif shape is CapsuleShape3D:
		var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
		var capsule_mesh: CapsuleMesh = mesh as CapsuleMesh
		if capsule_mesh == null:
			capsule_mesh = CapsuleMesh.new()
			mesh = capsule_mesh
		capsule_mesh.radius = capsule_shape.radius
		capsule_mesh.height = capsule_shape.height
	elif shape is CylinderShape3D:
		var cylinder_shape: CylinderShape3D = shape as CylinderShape3D
		var cylinder_mesh: CylinderMesh = mesh as CylinderMesh
		if cylinder_mesh == null:
			cylinder_mesh = CylinderMesh.new()
			mesh = cylinder_mesh
		cylinder_mesh.top_radius = cylinder_shape.radius
		cylinder_mesh.bottom_radius = cylinder_shape.radius
		cylinder_mesh.height = cylinder_shape.height
	else:
		mesh = null
	transform = _collision_shape.transform

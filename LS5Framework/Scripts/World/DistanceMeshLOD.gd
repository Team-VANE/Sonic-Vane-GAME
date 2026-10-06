extends Node
class_name DistanceMeshLOD

## Mesh instance whose primitive mesh subdivision properties are adjusted by distance.
@export_node_path("MeshInstance3D") var target_mesh_path: NodePath
## PrimitiveMesh integer properties adjusted for each detail level.
@export var subdivision_properties: PackedStringArray = PackedStringArray(["rings", "ring_segments"])
## Subdivision values used inside the near distance.
@export var high_detail_values: PackedInt32Array = PackedInt32Array([24, 12])
## Subdivision values used between the near and far distances.
@export var medium_detail_values: PackedInt32Array = PackedInt32Array([16, 6])
## Subdivision values used beyond the far distance.
@export var low_detail_values: PackedInt32Array = PackedInt32Array([8, 3])
## Base distance where high detail changes to medium detail before the graphics multiplier is applied.
@export_range(0.0, 10000.0, 0.5, "or_greater") var near_distance: float = 30.0
## Base distance where medium detail changes to low detail before the graphics multiplier is applied.
@export_range(0.0, 10000.0, 0.5, "or_greater") var far_distance: float = 90.0
## Seconds between camera-distance checks.
@export_range(0.02, 5.0, 0.01, "or_greater") var update_interval: float = 0.2
## Fraction of each boundary used to prevent repeated detail changes near a threshold.
@export_range(0.0, 0.5, 0.01) var hysteresis: float = 0.1

const DETAIL_HIGH: int = 0
const DETAIL_MEDIUM: int = 1
const DETAIL_LOW: int = 2

var _target_mesh: MeshInstance3D = null
var _mesh: PrimitiveMesh = null
var _detail_level: int = -1
var _update_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"DistanceMeshLOD")
	_target_mesh = get_node_or_null(target_mesh_path) as MeshInstance3D
	if not _target_mesh or not (_target_mesh.mesh is PrimitiveMesh):
		set_process(false)
		return
	_mesh = (_target_mesh.mesh as PrimitiveMesh).duplicate() as PrimitiveMesh
	_target_mesh.mesh = _mesh
	_update_timer = float(get_instance_id() % 100) / 100.0 * max(update_interval, 0.02)
	_update_detail(true)
	set_process(true)


func _process(delta: float) -> void:
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = max(update_interval, 0.02)
	_update_detail(false)


func refresh() -> void:
	_update_detail(true)


func _update_detail(force: bool) -> void:
	if not _target_mesh or not _mesh:
		return
	var viewport: Viewport = get_viewport()
	if not viewport:
		return
	var camera: Camera3D = viewport.get_camera_3d()
	if not camera:
		return
	var distance: float = _target_mesh.global_position.distance_to(camera.global_position)
	var multiplier: float = _get_distance_multiplier()
	var near_boundary: float = max(near_distance, 0.0) * multiplier
	var far_boundary: float = max(far_distance, near_distance) * multiplier
	var next_level: int = _select_detail_level(distance, near_boundary, far_boundary)
	if force or next_level != _detail_level:
		_apply_detail_level(next_level)


func _select_detail_level(distance: float, near_boundary: float, far_boundary: float) -> int:
	var margin: float = clamp(hysteresis, 0.0, 0.5)
	if _detail_level == DETAIL_HIGH and distance <= near_boundary * (1.0 + margin):
		return DETAIL_HIGH
	if _detail_level == DETAIL_MEDIUM:
		if distance < near_boundary * (1.0 - margin):
			return DETAIL_HIGH
		if distance <= far_boundary * (1.0 + margin):
			return DETAIL_MEDIUM
	if _detail_level == DETAIL_LOW and distance >= far_boundary * (1.0 - margin):
		return DETAIL_LOW
	if distance <= near_boundary:
		return DETAIL_HIGH
	if distance <= far_boundary:
		return DETAIL_MEDIUM
	return DETAIL_LOW


func _apply_detail_level(level: int) -> void:
	var values: PackedInt32Array = low_detail_values
	if level == DETAIL_HIGH:
		values = high_detail_values
	elif level == DETAIL_MEDIUM:
		values = medium_detail_values
	var property_count: int = mini(subdivision_properties.size(), values.size())
	for index: int in range(property_count):
		var property_name: StringName = StringName(subdivision_properties[index])
		if _has_property(_mesh, property_name):
			_mesh.set(property_name, values[index])
	_detail_level = level


func _get_distance_multiplier() -> float:
	var settings_manager: Node = get_node_or_null("/root/SettingsManager")
	if settings_manager and settings_manager.has_method("get_lod_distance_multiplier"):
		return max(float(settings_manager.call("get_lod_distance_multiplier")), 0.01)
	return 1.0


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false

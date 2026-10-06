extends Node
class_name TextureEffects

# Optional node that owns the primary material to animate.
@export var target_node_path: NodePath
# Optional surface index for the primary mesh target.
@export var surface_index: int = -1
# Additional nodes that own materials to animate.
@export var target_paths: Array[NodePath] = []
# Optional surface indices for mesh targets.
@export var surface_indices: Array[int] = []
# Direction of the UV scroll before normalisation.
@export var scroll_direction: Vector2 = Vector2.RIGHT
# Directions for additional targets.
@export var scroll_directions: Array[Vector2] = []
# Scroll speed in UV units per second.
@export var scroll_speed: float = 0.1
# Speeds for additional targets.
@export var scroll_speeds: Array[float] = []
# Shader parameter that receives the UV offset.
@export var offset_parameter: StringName = &"uv_offset"
# Shader parameters for additional targets.
@export var offset_parameters: Array[StringName] = []
# Starts scrolling when the node is ready.
@export var autoplay: bool = true
# Per-target autoplay flags.
@export var autoplays: Array[bool] = []
# Repeats the offset in the 0..1 range.
@export var wrap_offset: bool = true
# Per-target wrap flags.
@export var wrap_offsets: Array[bool] = []

var _target_materials: Array = []
var _scroll_offsets: Array[Vector2] = []


func _ready() -> void:
	_refresh_targets()
	set_process(not _target_materials.is_empty())
	_apply_offsets()


func _process(delta: float) -> void:
	if _target_materials.is_empty():
		return

	for i in range(_target_materials.size()):
		var material = _target_materials[i]
		if not (material is ShaderMaterial or material is BaseMaterial3D):
			continue
		if not _is_target_enabled(i):
			continue

		var direction: Vector2 = _get_target_direction(i)
		var speed: float = _get_target_speed(i)
		if direction == Vector2.ZERO or speed == 0.0:
			continue

		var offset: Vector2 = _get_target_offset(i)
		offset += direction.normalized() * speed * delta
		if _get_target_wrap(i):
			offset.x = fposmod(offset.x, 1.0)
			offset.y = fposmod(offset.y, 1.0)

		_scroll_offsets[i] = offset
		_apply_offset_to_material(material, i, offset)


func reset_scroll() -> void:
	for i in range(_scroll_offsets.size()):
		_scroll_offsets[i] = Vector2.ZERO
	_apply_offsets()


func refresh_targets() -> void:
	_refresh_targets()
	_apply_offsets()


func set_scroll_enabled(enabled: bool) -> void:
	set_process(enabled)


func set_scroll_direction(direction: Vector2) -> void:
	scroll_direction = direction


func set_scroll_speed(speed: float) -> void:
	scroll_speed = max(speed, 0.0)


func _apply_offsets() -> void:
	for i in range(_target_materials.size()):
		var material = _target_materials[i]
		if material is ShaderMaterial or material is BaseMaterial3D:
			_apply_offset_to_material(material, i, _get_target_offset(i))


func _refresh_targets() -> void:
	_target_materials.clear()
	_scroll_offsets.clear()

	var paths: Array[NodePath] = _collect_target_paths()
	for i in range(paths.size()):
		var target_node: Node = get_node_or_null(paths[i])
		_target_materials.append(_resolve_shader_material(target_node, _get_surface_index(i)))
		_scroll_offsets.append(Vector2.ZERO)


func _collect_target_paths() -> Array[NodePath]:
	var paths: Array[NodePath] = []
	if target_node_path != NodePath(""):
		paths.append(target_node_path)
	for path in target_paths:
		if path != NodePath(""):
			paths.append(path)
	return paths


func _resolve_shader_material(target_node: Node, surface_index: int) -> Material:
	if target_node == null or not is_instance_valid(target_node):
		return null

	if target_node is CanvasItem:
		var canvas_item := target_node as CanvasItem
		if canvas_item.material is ShaderMaterial or canvas_item.material is BaseMaterial3D:
			return canvas_item.material

	if target_node is MeshInstance3D:
		var mesh := target_node as MeshInstance3D
		if mesh.material_override is ShaderMaterial or mesh.material_override is BaseMaterial3D:
			return mesh.material_override

		if mesh.mesh != null:
			var material_index: int = surface_index
			if material_index >= 0 and material_index < mesh.mesh.get_surface_count():
				var active_material := mesh.get_active_material(material_index)
				if active_material is ShaderMaterial or active_material is BaseMaterial3D:
					return active_material

				var surface_material := mesh.mesh.surface_get_material(material_index)
				if surface_material is ShaderMaterial or surface_material is BaseMaterial3D:
					return surface_material

			if mesh.mesh.get_surface_count() > 0:
				var first_active_material := mesh.get_active_material(0)
				if first_active_material is ShaderMaterial or first_active_material is BaseMaterial3D:
					return first_active_material

				var first_surface_material := mesh.mesh.surface_get_material(0)
				if first_surface_material is ShaderMaterial or first_surface_material is BaseMaterial3D:
					return first_surface_material

	return null


func _apply_offset_to_material(material: Material, index: int, offset: Vector2) -> void:
	if material is ShaderMaterial:
		var parameter: StringName = _get_target_parameter(index)
		(material as ShaderMaterial).set_shader_parameter(parameter, offset)
	elif material is BaseMaterial3D:
		(material as BaseMaterial3D).uv1_offset = Vector3(offset.x, offset.y, 0.0)


func _get_target_offset(index: int) -> Vector2:
	if index >= 0 and index < _scroll_offsets.size():
		return _scroll_offsets[index]
	return Vector2.ZERO


func _get_target_parameter(index: int) -> StringName:
	if index == 0:
		return offset_parameter
	if index - 1 >= 0 and index - 1 < offset_parameters.size():
		return offset_parameters[index - 1]
	return offset_parameter


func _get_target_direction(index: int) -> Vector2:
	if index == 0:
		return scroll_direction
	if index - 1 >= 0 and index - 1 < scroll_directions.size():
		return scroll_directions[index - 1]
	return scroll_direction


func _get_target_speed(index: int) -> float:
	if index == 0:
		return scroll_speed
	if index - 1 >= 0 and index - 1 < scroll_speeds.size():
		return max(scroll_speeds[index - 1], 0.0)
	return scroll_speed


func _get_target_wrap(index: int) -> bool:
	if index == 0:
		return wrap_offset
	if index - 1 >= 0 and index - 1 < wrap_offsets.size():
		return wrap_offsets[index - 1]
	return wrap_offset


func _is_target_enabled(index: int) -> bool:
	if index == 0:
		return autoplay
	if index - 1 >= 0 and index - 1 < autoplays.size():
		return autoplays[index - 1]
	return autoplay


func _get_surface_index(index: int) -> int:
	if index == 0:
		return surface_index
	if index - 1 >= 0 and index - 1 < surface_indices.size():
		return surface_indices[index - 1]
	return -1

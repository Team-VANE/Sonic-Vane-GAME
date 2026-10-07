@tool
extends Node
class_name TextureEffects

## Optional node that owns the primary material to animate.
@export var target_node_path: NodePath:
	set(value):
		target_node_path = value
		_queue_target_refresh()
## Optional surface index for the primary mesh target.
@export var surface_index: int = -1:
	set(value):
		surface_index = value
		_queue_target_refresh()
## Additional nodes that own materials to animate.
@export var target_paths: Array[NodePath] = []:
	set(value):
		target_paths = value
		_queue_target_refresh()
## Optional surface indices for mesh targets.
@export var surface_indices: Array[int] = []:
	set(value):
		surface_indices = value
		_queue_target_refresh()
## Direction of the UV scroll before normalisation.
@export var scroll_direction: Vector2 = Vector2.RIGHT
## Directions for additional targets.
@export var scroll_directions: Array[Vector2] = []
## Scroll speed in UV units per second.
@export var scroll_speed: float = 0.1
## Speeds for additional targets.
@export var scroll_speeds: Array[float] = []
## Shader parameter that receives the UV offset.
@export var offset_parameter: StringName = &"uv_offset"
## Shader parameters for additional targets.
@export var offset_parameters: Array[StringName] = []
## Starts scrolling when the node is ready.
@export var autoplay: bool = true
## Per-target autoplay flags.
@export var autoplays: Array[bool] = []
## Repeats the offset in the 0..1 range.
@export var wrap_offset: bool = true
## Per-target wrap flags.
@export var wrap_offsets: Array[bool] = []

@export_group("Editor Preview")
## Previews UV scrolling with isolated materials in the editor.
@export var editor_preview_enabled: bool = true:
	set(value):
		editor_preview_enabled = value
		_queue_target_refresh()

var _target_materials: Array[Material] = []
var _material_bindings: Array[Dictionary] = []
var _refresh_pending: bool = false
var _scroll_enabled: bool = true
var _editor_save_suspended: bool = false
var _scroll_offsets: Array[Vector2] = []


func _ready() -> void:
	_refresh_targets()
	_apply_offsets()


func _exit_tree() -> void:
	_restore_target_materials()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_editor_save_suspended = true
		_restore_target_materials()
		_update_processing()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_editor_save_suspended = false
		_queue_target_refresh()


func _queue_target_refresh() -> void:
	if not is_node_ready() or _refresh_pending:
		return
	_refresh_pending = true
	_refresh_targets_deferred.call_deferred()


func _refresh_targets_deferred() -> void:
	_refresh_pending = false
	if is_inside_tree():
		refresh_targets()


func _update_processing() -> void:
	var preview_allowed: bool = not Engine.is_editor_hint() or (editor_preview_enabled and not _editor_save_suspended)
	var has_material: bool = false
	for material: Material in _target_materials:
		if material:
			has_material = true
			break
	set_process(_scroll_enabled and preview_allowed and has_material)


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
	_scroll_enabled = enabled
	_update_processing()


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
	_restore_target_materials()
	_scroll_offsets.clear()
	if Engine.is_editor_hint() and (not editor_preview_enabled or _editor_save_suspended):
		_update_processing()
		return

	var paths: Array[NodePath] = _collect_target_paths()
	for i in range(paths.size()):
		var target_node: Node = get_node_or_null(paths[i])
		_target_materials.append(_resolve_shader_material(target_node, _get_surface_index(i)))
		_scroll_offsets.append(Vector2.ZERO)
	_update_processing()


func _collect_target_paths() -> Array[NodePath]:
	var paths: Array[NodePath] = []
	if target_node_path != NodePath(""):
		paths.append(target_node_path)
	for path in target_paths:
		if path != NodePath(""):
			paths.append(path)
	return paths


func _resolve_shader_material(target_node: Node, target_surface_index: int) -> Material:
	if not is_instance_valid(target_node):
		return null
	if target_node is CanvasItem:
		var canvas_item: CanvasItem = target_node as CanvasItem
		return _isolate_material(canvas_item, &"material", -1, canvas_item.material)
	if target_node is MeshInstance3D:
		var mesh: MeshInstance3D = target_node as MeshInstance3D
		if mesh.material_override is ShaderMaterial or mesh.material_override is BaseMaterial3D:
			return _isolate_material(mesh, &"material_override", -1, mesh.material_override)
		if mesh.mesh and mesh.mesh.get_surface_count() > 0:
			var material_index: int = target_surface_index
			if material_index < 0 or material_index >= mesh.mesh.get_surface_count():
				material_index = 0
			return _isolate_material(mesh, &"surface", material_index, mesh.get_active_material(material_index))
	return null


func _isolate_material(target_node: Node, slot: StringName, material_index: int, material: Material) -> Material:
	if not (material is ShaderMaterial or material is BaseMaterial3D):
		return null
	for binding: Dictionary in _material_bindings:
		if binding["target"].get_ref() == target_node and binding["slot"] == slot and binding["index"] == material_index:
			return binding["isolated"] as Material
	var isolated: Material = material.duplicate() as Material
	isolated.resource_local_to_scene = true
	var original: Material = material
	if slot == &"surface":
		var mesh: MeshInstance3D = target_node as MeshInstance3D
		original = mesh.get_surface_override_material(material_index)
		mesh.set_surface_override_material(material_index, isolated)
	else:
		target_node.set(slot, isolated)
	_material_bindings.append({
		"target": weakref(target_node),
		"slot": slot,
		"index": material_index,
		"original": original,
		"isolated": isolated,
	})
	return isolated


func _restore_target_materials() -> void:
	for binding: Dictionary in _material_bindings:
		var target_node: Node = binding["target"].get_ref() as Node
		if not is_instance_valid(target_node):
			continue
		var slot: StringName = binding["slot"]
		if slot == &"surface":
			var mesh: MeshInstance3D = target_node as MeshInstance3D
			var material_index: int = binding["index"]
			if mesh.mesh and material_index < mesh.mesh.get_surface_count():
				if mesh.get_surface_override_material(material_index) == binding["isolated"]:
					mesh.set_surface_override_material(material_index, binding["original"] as Material)
		elif target_node.get(slot) == binding["isolated"]:
			target_node.set(slot, binding["original"])
	_material_bindings.clear()
	_target_materials.clear()


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

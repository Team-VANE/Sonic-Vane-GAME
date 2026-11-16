@tool
extends Node

const WATER_RENDER_LAYER: int = 1 << 18
const CAPTURE_NAME: String = "_AdventureWaterRefractionCapture"
const EFFECT_SCRIPT: Script = preload("res://LS5Framework/Scripts/World/AdventureWaterRefractionEffect.gd")

## Viewport receiving the shared water compositor.
var _source: Viewport
## Active source camera with the water effect installed.
var _camera: Camera3D
var _users: Dictionary = {}
var _meshes: Dictionary = {}
var _effect: CompositorEffect
var _base_compositor: Compositor
var _installed_compositor: Compositor
var _inherited_compositor: Compositor
## Environment providing inherited compositor effects.
var _world_source: Object
var _ready_frame: bool = false


static func is_supported() -> bool:
	return RenderingServer.get_rendering_device() != null


static func acquire(source: Viewport, water: Node) -> Node:
	var reference: WeakRef = source.get_meta(CAPTURE_NAME) as WeakRef if source.has_meta(CAPTURE_NAME) else null
	var capture: Node = reference.get_ref() as Node if reference else null
	if not is_instance_valid(capture):
		var script: Script = load("res://LS5Framework/Scripts/World/AdventureWaterRefractionCapture.gd")
		capture = script.new()
		capture.name = CAPTURE_NAME
		source.set_meta(CAPTURE_NAME, weakref(capture))
		source.add_child.call_deferred(capture)
	capture.register(water)
	return capture


func _ready() -> void:
	_source = get_parent() as Viewport
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_effect = EFFECT_SCRIPT.new()
	RenderingServer.frame_pre_draw.connect(_sync)
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


func register(water: Node) -> void:
	_users[water.get_instance_id()] = weakref(water)


func unregister(water: Node) -> void:
	_users.erase(water.get_instance_id())
	if _users.is_empty():
		_suspend()


func is_capture_ready() -> bool:
	return _ready_frame and _effect and _effect.enabled and is_instance_valid(_camera) and _camera.compositor == _installed_compositor


func get_source_viewport() -> Viewport:
	return _source if is_instance_valid(_source) else get_parent() as Viewport


func _sync() -> void:
	var previous_capture: SubViewport = get_node_or_null("SceneCapture") as SubViewport
	if previous_capture:
		previous_capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
		previous_capture.queue_free()
	if not _effect:
		_effect = EFFECT_SCRIPT.new()
	if _meshes == null:
		_meshes = {}
	if not is_supported():
		return
	var camera: Camera3D = _source.get_camera_3d()
	if not is_instance_valid(camera) or not (camera.cull_mask & WATER_RENDER_LAYER):
		_suspend()
		return
	var data: Array[Dictionary] = []
	var visible_view: bool = not Engine.is_editor_hint() or not _source.get_parent() is Control or (_source.get_parent() as Control).is_visible_in_tree()
	var meshes: Dictionary = {}
	for id: int in _users.keys():
		var water: Node3D = (_users[id] as WeakRef).get_ref() as Node3D
		if not water:
			_users.erase(id)
		elif visible_view and water.is_refraction_visible_from(camera):
			var mesh: Mesh = water._visual.mesh
			var mesh_id: int = mesh.get_instance_id()
			meshes[mesh_id] = true
			if not _meshes.has(mesh_id) or _meshes[mesh_id].is_empty():
				_meshes[mesh_id] = _mesh_vertices(mesh)
			var vertices: PackedByteArray = _meshes[mesh_id]
			if not vertices.is_empty() and water._surface_parameter_cache.has("surface_image"):
				data.append({"id": id, "mesh_id": mesh_id, "vertices": vertices, "count": vertices.size() / 32, "transform": water._visual.get_global_transform_interpolated(), "bounds": water._bounds, "geometry": water.geometry, "parameters": water._surface_parameter_cache.duplicate()})
	for id: int in _meshes.keys():
		if not meshes.has(id):
			_meshes.erase(id)
	if data.is_empty():
		_suspend()
		return
	var world_changed: bool = not _base_compositor and is_instance_valid(_world_source) and _world_source.get("compositor") != _inherited_compositor
	if camera != _camera or camera.compositor != _installed_compositor or world_changed:
		_restore_camera()
		_camera = camera
		_base_compositor = camera.compositor
		var inherited: Compositor = _base_compositor if _base_compositor else _world_compositor()
		_inherited_compositor = inherited
		_installed_compositor = inherited.duplicate() as Compositor if inherited else Compositor.new()
		var effects: Array[CompositorEffect] = _installed_compositor.compositor_effects.duplicate()
		effects.append(_effect)
		_installed_compositor.compositor_effects = effects
		_camera.compositor = _installed_compositor
	_effect.set_water_data(data)
	_effect.enabled = true


func _mesh_vertices(mesh: Mesh) -> PackedByteArray:
	var vertices: PackedFloat32Array = PackedFloat32Array()
	for surface: int in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] else PackedVector3Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else positions.size()
		for index: int in range(count):
			var vertex: int = indices[index] if not indices.is_empty() else index
			var position: Vector3 = positions[vertex]
			var normal: Vector3 = normals[vertex] if not normals.is_empty() else Vector3.UP
			if normals.is_empty():
				var triangle: int = index - index % 3
				var a: Vector3 = positions[indices[triangle] if not indices.is_empty() else triangle]
				var b: Vector3 = positions[indices[triangle + 1] if not indices.is_empty() else triangle + 1]
				var c: Vector3 = positions[indices[triangle + 2] if not indices.is_empty() else triangle + 2]
				normal = (c - a).cross(b - a).normalized()
			vertices.append_array(PackedFloat32Array([position.x, position.y, position.z, 1.0, normal.x, normal.y, normal.z, 0.0]))
	return vertices.to_byte_array()


func _world_compositor() -> Compositor:
	var world: World3D = _source.find_world_3d()
	for property: Dictionary in world.get_property_list():
		if property.name == "compositor":
			_world_source = world
			return world.get("compositor") as Compositor
	for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		if node is WorldEnvironment and node.get_viewport().find_world_3d() == world:
			_world_source = node
			return node.compositor
	return null


func _suspend() -> void:
	_ready_frame = false
	if _effect:
		_effect.enabled = false
		var empty: Array[Dictionary] = []
		_effect.set_water_data(empty)
	_restore_camera()


func _restore_camera() -> void:
	if is_instance_valid(_camera) and _camera.compositor == _installed_compositor:
		_camera.compositor = _base_compositor
	_camera = null
	_installed_compositor = null
	_base_compositor = null
	_inherited_compositor = null


func _on_frame_drawn() -> void:
	_ready_frame = _effect and _effect.enabled and is_instance_valid(_camera)


func _exit_tree() -> void:
	_suspend()
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)
	if RenderingServer.frame_post_draw.is_connected(_on_frame_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)

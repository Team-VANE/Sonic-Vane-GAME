@tool
extends Node3D

@export var guide_length: float = 1.5:
	set(value):
		guide_length = value
		if Engine.is_editor_hint() and is_inside_tree():
			_ensure_mesh()
			_rebuild_guide()

@export var guide_arrow_size: float = 0.3:
	set(value):
		guide_arrow_size = value
		if Engine.is_editor_hint() and is_inside_tree():
			_ensure_mesh()
			_rebuild_guide()

@export var axis_length: float = 0.6:
	set(value):
		axis_length = value
		if Engine.is_editor_hint() and is_inside_tree():
			_ensure_mesh()
			_rebuild_guide()

var _mesh_instance: MeshInstance3D = null
var _mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		if _mesh_instance != null and is_instance_valid(_mesh_instance):
			_mesh_instance.queue_free()
		set_process(false)
		return
	_ensure_mesh()
	_rebuild_guide()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_rebuild_guide()


func _ensure_mesh() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ConstraintPointGuide"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visible = true
	_mesh_instance.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_mesh_instance)

	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_mesh_instance.material_override = _material


func _rebuild_guide() -> void:
	if _mesh == null:
		return
	var len: float = max(guide_length, 0.01)
	var arrow: float = max(guide_arrow_size, 0.0)
	var axis: float = max(axis_length, 0.0)

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Forward (cyan)
	_mesh.surface_set_color(Color(0.2, 0.85, 1.0, 1.0))
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_add_vertex(Vector3(0.0, 0.0, len))
	var tip := Vector3(0.0, 0.0, len)
	_mesh.surface_add_vertex(tip)
	_mesh.surface_add_vertex(tip + Vector3(arrow, 0.0, -arrow))
	_mesh.surface_add_vertex(tip)
	_mesh.surface_add_vertex(tip + Vector3(-arrow, 0.0, -arrow))

	# Up (green)
	_mesh.surface_set_color(Color(0.2, 1.0, 0.4, 1.0))
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_add_vertex(Vector3(0.0, axis, 0.0))

	# Right (red)
	_mesh.surface_set_color(Color(1.0, 0.35, 0.35, 1.0))
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_add_vertex(Vector3(axis, 0.0, 0.0))

	_mesh.surface_end()

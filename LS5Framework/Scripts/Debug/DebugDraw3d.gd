extends Node3D
# class_name DebugDraw3d

# Simple debug line command
class LineCommand:
	var from: Vector3
	var to: Vector3
	var color: Color

	func _init(_from: Vector3, _to: Vector3, _color: Color) -> void:
		from = _from
		to = _to
		color = _color

var _commands: Array = []

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	# Mesh instance to render all debug lines
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

	# Unshaded, always-on-top material that uses vertex colors
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.render_priority = 1
	_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_material.disable_fog = true
	_material.flags_transparent = false

	_mesh_instance.material_override = _material

	set_process(true)


func _input(event: InputEvent) -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var focus_owner: Control = viewport.gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_KP_ADD:
		var vp := get_viewport()
		if vp == null:
			return
		vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if vp.debug_draw != Viewport.DEBUG_DRAW_WIREFRAME else Viewport.DEBUG_DRAW_DISABLED


func _process(delta: float) -> void:
	# If nothing to draw, clear mesh and bail
	if _commands.is_empty():
		_mesh_instance.mesh = null
		return

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	# Build line mesh from commands
	for c in _commands:
		var cmd: LineCommand = c
		st.set_color(cmd.color)
		st.add_vertex(cmd.from)
		st.set_color(cmd.color)
		st.add_vertex(cmd.to)

	var mesh: ArrayMesh = st.commit()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _material

	# Clear for next frame
	_commands.clear()


# --------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------

func line(from: Vector3, to: Vector3, color: Color) -> void:
	var cmd: LineCommand = LineCommand.new(from, to, color)
	_commands.append(cmd)


func arrow(from: Vector3, to: Vector3, color: Color) -> void:
	var dir: Vector3 = to - from
	var length: float = dir.length()
	if length < 0.001:
		return

	var dir_n: Vector3 = dir / length

	# Base line
	line(from, to, color)

	# Arrow head
	var head_length: float = length * 0.2
	# Clamp so very short arrows still have a visible head, but long ones don't get silly
	if head_length < 0.1:
		head_length = 0.1
	elif head_length > 0.5:
		head_length = 0.5

	var tip: Vector3 = to
	var head_base: Vector3 = tip - dir_n * head_length

	# Build a small orthonormal basis around dir
	var right: Vector3 = dir_n.cross(Vector3.UP)
	if right.length() < 0.001:
		right = dir_n.cross(Vector3.FORWARD)
	right = right.normalized()

	var up: Vector3 = right.cross(dir_n).normalized()

	var spread: float = head_length * 0.5

	var head_right: Vector3 = head_base + (right - dir_n) * spread
	var head_left: Vector3 = head_base + (-right - dir_n) * spread

	line(tip, head_right, color)
	line(tip, head_left, color)

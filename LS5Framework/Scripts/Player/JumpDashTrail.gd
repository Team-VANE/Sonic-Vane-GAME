extends MeshInstance3D
class_name JumpDashTrail

@export var radius: float = 0.35
@export var sides: int = 8
@export var max_points: int = 28
@export var min_sample_distance: float = 0.15
@export var max_sample_distance: float = 12.0
@export var slow_sample_distance_scale: float = 0.25
@export var speed_fade_threshold: float = 12.0
@export var fade_out_time: float = 0.4
@export var max_opacity: float = 0.6
## Portion of the trail near the player that fades toward the head.
@export_range(0.0, 1.0, 0.01) var front_fade_fraction: float = 0.18
## Minimum opacity multiplier at the newest trail point.
@export_range(0.0, 1.0, 0.01) var front_min_opacity: float = 0.0
@export var tint: Color = Color(0.2, 0.8, 1.0, 1.0)

var _points: PackedVector3Array = PackedVector3Array()
var _emit_strength: float = 0.0
var _effective_min_distance: float = 0.15
var _last_up: Vector3 = Vector3.UP
var _mesh: ArrayMesh = ArrayMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_material.vertex_color_use_as_albedo = true
	material_override = _material
	visible = false


func set_tint(color: Color) -> void:
	tint = color


func stop_and_clear() -> void:
	_emit_strength = 0.0
	_points.clear()
	_mesh.clear_surfaces()
	visible = false


func update_trail(delta: float, head_pos: Vector3, active: bool, speed: float = 0.0) -> void:
	var min_dist := min_sample_distance
	if speed_fade_threshold > 0.001 and speed < speed_fade_threshold:
		var min_scale: float = clamp(slow_sample_distance_scale, 0.01, 1.0)
		min_dist = min_sample_distance * min_scale
	_effective_min_distance = min_dist

	var speed_ok: bool = (speed_fade_threshold <= 0.001) or (speed >= speed_fade_threshold)
	if active and speed_ok:
		_emit_strength = 1.0
	else:
		if fade_out_time <= 0.0:
			_emit_strength = 0.0
		else:
			_emit_strength = max(_emit_strength - (delta / fade_out_time), 0.0)

	if _emit_strength <= 0.0:
		if visible:
			_points.clear()
			_mesh.clear_surfaces()
			visible = false
		return

	visible = true
	_add_point(head_pos)
	_rebuild_mesh()


func _add_point(head_pos: Vector3) -> void:
	var min_dist: float = max(_effective_min_distance, 0.001)
	if _points.is_empty():
		_points.append(head_pos)
		_last_up = Vector3.UP
		return

	var last: Vector3 = _points[_points.size() - 1]
	var to_last: Vector3 = head_pos - last
	var dist: float = to_last.length()

	if dist > max_sample_distance:
		# Treat as a teleport/huge gap: restart the trail to avoid streaks.
		_points.clear()
		_points.append(head_pos)
		_last_up = Vector3.UP
		return

	if dist < min_dist:
		_points[_points.size() - 1] = head_pos
		return

	var step: float = min_dist
	var dir: Vector3 = to_last / dist
	var steps: int = max(1, int(dist / step))
	var step_size: float = dist / float(steps)
	var pos := last
	for i in range(steps):
		pos += dir * step_size
		_points.append(pos)

	_points[_points.size() - 1] = head_pos
	_trim_points()


func _trim_points() -> void:
	while _points.size() > max_points:
		_points.remove_at(0)


func _alpha_for_index(idx: int, count: int) -> float:
	if count <= 1:
		return 0.0
	var t: float = float(idx) / float(count - 1)
	var front_factor: float = 1.0
	if front_fade_fraction > 0.001:
		var distance_from_head: float = 1.0 - t
		front_factor = clamp(distance_from_head / front_fade_fraction, front_min_opacity, 1.0)
	return t * front_factor * max_opacity * _emit_strength


func _rebuild_mesh() -> void:
	_mesh.clear_surfaces()
	var count: int = _points.size()
	if count < 2 or sides < 3 or radius <= 0.0:
		return
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.resize(count * sides)
	normals.resize(count * sides)
	colors.resize(count * sides)
	indices.resize((count - 1) * sides * 6)
	var circle: PackedVector2Array = PackedVector2Array()
	circle.resize(sides)
	for j: int in range(sides):
		var angle: float = TAU * float(j) / float(sides)
		circle[j] = Vector2(cos(angle), sin(angle))
	var up_ref: Vector3 = _last_up
	for i: int in range(count):
		var point: Vector3 = _points[i]
		var tangent: Vector3 = _points[i + 1] - point if i < count - 1 else point - _points[i - 1]
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var up: Vector3 = up_ref - tangent * up_ref.dot(tangent)
		if up.length_squared() < 0.000001:
			up = Vector3.UP
		if abs(up.dot(tangent)) > 0.95:
			up = Vector3.RIGHT
		up = up.normalized()
		var right: Vector3 = tangent.cross(up).normalized()
		if right.length_squared() < 0.000001:
			right = Vector3.RIGHT
		up = right.cross(tangent).normalized()
		up_ref = up
		var color: Color = Color(tint.r, tint.g, tint.b, _alpha_for_index(i, count) * tint.a)
		for j: int in range(sides):
			var index: int = i * sides + j
			var direction: Vector3 = right * circle[j].x + up * circle[j].y
			vertices[index] = point + direction * radius
			normals[index] = direction.normalized()
			colors[index] = color
			if i == count - 1:
				continue
			var next_index: int = i * sides + (j + 1) % sides
			var base: int = index * 6
			indices[base] = index
			indices[base + 1] = index + sides
			indices[base + 2] = next_index
			indices[base + 3] = next_index
			indices[base + 4] = index + sides
			indices[base + 5] = next_index + sides
	_last_up = up_ref
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

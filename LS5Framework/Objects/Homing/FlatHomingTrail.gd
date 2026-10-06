extends MeshInstance3D
class_name FlatHomingTrail

@export_group("Shape")
## Full width of the flat trail surface.
@export_range(0.01, 20.0, 0.01) var width: float = 1.25
## Maximum number of sampled positions retained by the trail.
@export_range(2, 512, 1) var max_points: int = 192
## Distance between interpolated trail samples.
@export_range(0.01, 10.0, 0.01) var min_sample_distance: float = 0.5
## Distance treated as a teleport that restarts the trail.
@export_range(0.1, 500.0, 0.1) var max_sample_distance: float = 100.0
## Width multiplier at the oldest trail point.
@export_range(0.0, 2.0, 0.01) var tail_width_scale: float = 0.0
## Width multiplier at the newest trail point.
@export_range(0.0, 2.0, 0.01) var head_width_scale: float = 0.15

@export_group("Appearance")
## Color and base opacity applied to the trail.
@export var tint: Color = Color(0.14, 0.78, 1.0, 0.85)
## Portion of the oldest trail section that fades in from transparent.
@export_range(0.0, 1.0, 0.01) var tail_fade_fraction: float = 0.12
## Portion of the newest trail section that fades toward the head.
@export_range(0.0, 1.0, 0.01) var head_fade_fraction: float = 0.08
## Minimum opacity multiplier at the newest trail point.
@export_range(0.0, 1.0, 0.01) var head_min_opacity: float = 0.2
## Time used to fade the complete trail after emission stops.
@export_range(0.0, 5.0, 0.01) var fade_out_time: float = 0.25
## Allows the trail to render through level geometry.
@export var draw_through_geometry: bool = false
## Optional material override. The material must use mesh vertex colors to retain trail fading.
@export var trail_material: Material

var _points: PackedVector3Array = PackedVector3Array()
var _up_hints: PackedVector3Array = PackedVector3Array()
var _emitting: bool = false
var _fade_strength: float = 0.0
var _mesh: ArrayMesh = ArrayMesh.new()
var _generated_material: StandardMaterial3D = null


func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_configure_material()
	visible = false
	set_process(true)


func begin_trail(start_position: Vector3, up_hint: Vector3 = Vector3.UP) -> void:
	_points.clear()
	_up_hints.clear()
	_points.append(start_position)
	_up_hints.append(_normalized_up_hint(up_hint))
	_emitting = true
	_fade_strength = 1.0
	visible = true
	_mesh.clear_surfaces()


func add_trail_point(world_position: Vector3, up_hint: Vector3 = Vector3.UP) -> void:
	if not _emitting:
		begin_trail(world_position, up_hint)
		return
	_add_sampled_point(world_position, _normalized_up_hint(up_hint))
	_rebuild_mesh()


func finish_trail() -> void:
	_emitting = false
	if fade_out_time <= 0.0:
		clear_trail()


func clear_trail() -> void:
	_emitting = false
	_fade_strength = 0.0
	_points.clear()
	_up_hints.clear()
	_mesh.clear_surfaces()
	visible = false


func set_tint(color: Color) -> void:
	tint = color
	_rebuild_mesh()


func _process(delta: float) -> void:
	if _emitting or _fade_strength <= 0.0:
		return
	_fade_strength = max(_fade_strength - max(delta, 0.0) / max(fade_out_time, 0.001), 0.0)
	if _fade_strength <= 0.0:
		clear_trail()
		return
	_rebuild_mesh()


func _configure_material() -> void:
	if trail_material != null:
		material_override = trail_material
		return
	_generated_material = StandardMaterial3D.new()
	_generated_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_generated_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_generated_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_generated_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_generated_material.vertex_color_use_as_albedo = true
	_generated_material.albedo_color = Color.WHITE
	_generated_material.no_depth_test = draw_through_geometry
	material_override = _generated_material


func _add_sampled_point(world_position: Vector3, up_hint: Vector3) -> void:
	if _points.is_empty():
		_points.append(world_position)
		_up_hints.append(up_hint)
		return
	var last_index: int = _points.size() - 1
	var last_position: Vector3 = _points[last_index]
	var offset: Vector3 = world_position - last_position
	var distance: float = offset.length()
	if distance > max(max_sample_distance, min_sample_distance):
		begin_trail(world_position, up_hint)
		return
	if distance < max(min_sample_distance, 0.01):
		_points[last_index] = world_position
		_up_hints[last_index] = up_hint
		return
	var direction: Vector3 = offset / distance
	var step_count: int = max(1, int(ceil(distance / max(min_sample_distance, 0.01))))
	var previous_up: Vector3 = _up_hints[last_index]
	for step_index in range(1, step_count + 1):
		var weight: float = float(step_index) / float(step_count)
		_points.append(last_position + direction * distance * weight)
		_up_hints.append(_normalized_up_hint(previous_up.lerp(up_hint, weight)))
	_trim_points()


func _trim_points() -> void:
	var retained_count: int = max(max_points, 2)
	while _points.size() > retained_count:
		_points.remove_at(0)
		_up_hints.remove_at(0)


func _rebuild_mesh() -> void:
	_mesh.clear_surfaces()
	var point_count: int = _points.size()
	if point_count < 2 or width <= 0.0 or _fade_strength <= 0.0:
		return
	var left_edges: PackedVector3Array = PackedVector3Array()
	var right_edges: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var previous_width_direction: Vector3 = Vector3.ZERO
	for point_index in range(point_count):
		var tangent: Vector3 = _tangent_at(point_index)
		var width_direction: Vector3 = _width_direction_at(point_index, tangent, previous_width_direction)
		previous_width_direction = width_direction
		var path_progress: float = float(point_index) / float(point_count - 1)
		var width_scale: float = lerp(tail_width_scale, head_width_scale, path_progress)
		width_scale = max(width_scale, sin(path_progress * PI))
		var half_width: float = width * max(width_scale, 0.0) * 0.5
		left_edges.append(_points[point_index] - width_direction * half_width)
		right_edges.append(_points[point_index] + width_direction * half_width)
		var surface_normal: Vector3 = tangent.cross(width_direction).normalized()
		if surface_normal.length() < 0.001:
			surface_normal = Vector3.UP
		normals.append(surface_normal)
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment_index in range(point_count - 1):
		_add_segment(surface_tool, segment_index, point_count, left_edges, right_edges, normals)
	surface_tool.commit(_mesh)
	mesh = _mesh
	visible = true


func _add_segment(
	surface_tool: SurfaceTool,
	segment_index: int,
	point_count: int,
	left_edges: PackedVector3Array,
	right_edges: PackedVector3Array,
	normals: PackedVector3Array
) -> void:
	var next_index: int = segment_index + 1
	var progress_current: float = float(segment_index) / float(point_count - 1)
	var progress_next: float = float(next_index) / float(point_count - 1)
	var color_current: Color = _color_at(progress_current)
	var color_next: Color = _color_at(progress_next)
	_add_vertex(surface_tool, left_edges[segment_index], normals[segment_index], color_current, Vector2(0.0, progress_current))
	_add_vertex(surface_tool, left_edges[next_index], normals[next_index], color_next, Vector2(0.0, progress_next))
	_add_vertex(surface_tool, right_edges[segment_index], normals[segment_index], color_current, Vector2(1.0, progress_current))
	_add_vertex(surface_tool, right_edges[segment_index], normals[segment_index], color_current, Vector2(1.0, progress_current))
	_add_vertex(surface_tool, left_edges[next_index], normals[next_index], color_next, Vector2(0.0, progress_next))
	_add_vertex(surface_tool, right_edges[next_index], normals[next_index], color_next, Vector2(1.0, progress_next))


func _add_vertex(surface_tool: SurfaceTool, vertex: Vector3, normal: Vector3, color: Color, uv: Vector2) -> void:
	surface_tool.set_normal(normal)
	surface_tool.set_color(color)
	surface_tool.set_uv(uv)
	surface_tool.add_vertex(vertex)


func _tangent_at(point_index: int) -> Vector3:
	var point_count: int = _points.size()
	var tangent: Vector3 = Vector3.ZERO
	if point_index <= 0:
		tangent = _points[1] - _points[0]
	elif point_index >= point_count - 1:
		tangent = _points[point_count - 1] - _points[point_count - 2]
	else:
		tangent = _points[point_index + 1] - _points[point_index - 1]
	if tangent.length() < 0.001:
		return Vector3.FORWARD
	return tangent.normalized()


func _width_direction_at(point_index: int, tangent: Vector3, previous_width_direction: Vector3) -> Vector3:
	var curve_direction: Vector3 = _curve_direction_at(point_index, tangent)
	var width_direction: Vector3 = curve_direction
	if width_direction.length() < 0.001 and previous_width_direction.length() >= 0.001:
		width_direction = previous_width_direction - tangent * previous_width_direction.dot(tangent)
	if width_direction.length() < 0.001:
		var up_hint: Vector3 = _up_hints[point_index]
		width_direction = up_hint - tangent * up_hint.dot(tangent)
	if width_direction.length() < 0.001:
		var fallback_axis: Vector3 = Vector3.UP
		if abs(tangent.dot(fallback_axis)) > 0.95:
			fallback_axis = Vector3.RIGHT
		width_direction = fallback_axis - tangent * fallback_axis.dot(tangent)
	width_direction = width_direction.normalized()
	if previous_width_direction.length() >= 0.001 and width_direction.dot(previous_width_direction) < 0.0:
		width_direction = -width_direction
	return width_direction


func _curve_direction_at(point_index: int, tangent: Vector3) -> Vector3:
	if point_index <= 0 or point_index >= _points.size() - 1:
		return Vector3.ZERO
	var incoming: Vector3 = _points[point_index] - _points[point_index - 1]
	var outgoing: Vector3 = _points[point_index + 1] - _points[point_index]
	if incoming.length() < 0.001 or outgoing.length() < 0.001:
		return Vector3.ZERO
	var bend: Vector3 = outgoing.normalized() - incoming.normalized()
	bend -= tangent * bend.dot(tangent)
	return bend.normalized() if bend.length() >= 0.001 else Vector3.ZERO


func _color_at(path_progress: float) -> Color:
	var alpha_factor: float = 1.0
	if tail_fade_fraction > 0.001:
		alpha_factor *= clamp(path_progress / tail_fade_fraction, 0.0, 1.0)
	if head_fade_fraction > 0.001:
		var distance_from_head: float = 1.0 - path_progress
		alpha_factor *= clamp(distance_from_head / head_fade_fraction, head_min_opacity, 1.0)
	return Color(tint.r, tint.g, tint.b, tint.a * alpha_factor * _fade_strength)


func _normalized_up_hint(up_hint: Vector3) -> Vector3:
	if up_hint.length() < 0.001:
		return Vector3.UP
	return up_hint.normalized()

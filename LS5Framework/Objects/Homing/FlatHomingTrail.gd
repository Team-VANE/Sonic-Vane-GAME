extends MeshInstance3D
class_name FlatHomingTrail

@export_group("Shape")
## Full width of each face of the cross-shaped ribbon.
@export_range(0.01, 20.0, 0.01) var width: float = 1.25
## Maximum number of sampled positions retained by the trail.
@export_range(2, 129, 1) var max_points: int = 129
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
## Optional material override. Custom shaders can use trail_tint, trail_fade, progress_scale, and the head/tail fade uniforms.
@export var trail_material: Material

var _points: PackedVector3Array = PackedVector3Array()
var _up_hints: PackedVector3Array = PackedVector3Array()
var _emitting: bool = false
var _fade_strength: float = 0.0
const TRAIL_SHADER: Shader = preload("res://LS5Framework/Objects/Homing/CollectionRibbon.gdshader")
var _mesh: RibbonTrailMesh = RibbonTrailMesh.new()
## Independent sample bones deform the native ribbon without rebuilding its surfaces.
var _trail_skeleton: Skeleton3D
var _generated_material: ShaderMaterial



func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	_configure_ribbon()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_configure_material()
	visible = false
	set_process(false)


func begin_trail(start_position: Vector3, up_hint: Vector3 = Vector3.UP) -> void:
	_points.clear()
	_up_hints.clear()
	_points.append(start_position)
	_up_hints.append(_normalized_up_hint(up_hint))
	_emitting = true
	_fade_strength = 1.0
	visible = false
	set_process(false)


func add_trail_point(world_position: Vector3, up_hint: Vector3 = Vector3.UP) -> void:
	if not _emitting:
		begin_trail(world_position, up_hint)
		return
	_add_sampled_point(world_position, _normalized_up_hint(up_hint))
	_rebuild_mesh()


func finish_trail() -> void:
	_emitting = false
	set_process(true)
	if fade_out_time <= 0.0:
		clear_trail()


func clear_trail() -> void:
	_emitting = false
	_fade_strength = 0.0
	_points.clear()
	_up_hints.clear()
	visible = false
	set_process(false)


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
	_update_material()


func _configure_material() -> void:
	if trail_material != null:
		material_override = trail_material
		return
	_generated_material = ShaderMaterial.new()
	if draw_through_geometry:
		var shader: Shader = Shader.new()
		shader.code = TRAIL_SHADER.code.replace("cull_disabled;", "cull_disabled, depth_test_disabled;")
		_generated_material.shader = shader
	else:
		_generated_material.shader = TRAIL_SHADER
	material_override = _generated_material



func _add_sampled_point(world_position: Vector3, up_hint: Vector3) -> void:
	if _points.is_empty():
		_points.append(world_position)
		_up_hints.append(up_hint)
		return
	var last_index: int = _points.size() - 1
	if _points[last_index].distance_to(world_position) > maxf(max_sample_distance, min_sample_distance):
		begin_trail(world_position, up_hint)
		return
	var anchor_index: int = maxi(last_index - 1, 0)
	var anchor: Vector3 = _points[anchor_index]
	var anchor_up: Vector3 = _up_hints[anchor_index]
	var offset: Vector3 = world_position - anchor
	var distance: float = offset.length()
	var spacing: float = maxf(min_sample_distance, 0.01)
	if distance < spacing:
		if _points.size() == 1:
			_points.append(world_position)
			_up_hints.append(up_hint)
		else:
			_points[last_index] = world_position
			_up_hints[last_index] = up_hint
		return
	if _points.size() > 1:
		_points.remove_at(last_index)
		_up_hints.remove_at(last_index)
	var direction: Vector3 = offset / distance
	var step_count: int = floori(distance / spacing)
	for index: int in range(1, step_count + 1):
		var traveled: float = float(index) * spacing
		_points.append(anchor + direction * traveled)
		_up_hints.append(_normalized_up_hint(anchor_up.lerp(up_hint, traveled / distance)))
	_points.append(world_position)
	_up_hints.append(up_hint)
	_trim_points()



func _trim_points() -> void:
	var retained_count: int = clampi(max_points, 2, 129)
	while _points.size() > retained_count:
		_points.remove_at(0)
		_up_hints.remove_at(0)


func _configure_ribbon() -> void:
	var point_count: int = clampi(max_points, 3, 129)
	if _trail_skeleton and _trail_skeleton.get_bone_count() == point_count:
		return
	if not _trail_skeleton:
		_trail_skeleton = Skeleton3D.new()
		_trail_skeleton.name = "TrailSkeleton"
		add_child(_trail_skeleton)
		skeleton = get_path_to(_trail_skeleton)
	_mesh.shape = RibbonTrailMesh.SHAPE_CROSS
	_mesh.sections = point_count - 1
	_mesh.section_segments = 1
	_mesh.section_length = 1.0
	_trail_skeleton.clear_bones()
	var ribbon_skin: Skin = Skin.new()
	for index: int in point_count:
		_trail_skeleton.add_bone("Sample%d" % index)
		var rest: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, float(_mesh.sections) * 0.5 - float(index), 0.0))
		_trail_skeleton.set_bone_rest(index, rest)
		ribbon_skin.add_bind(index, rest.affine_inverse())
	skin = ribbon_skin


func _update_material() -> void:
	if material_override is ShaderMaterial:
		var shader_material: ShaderMaterial = material_override as ShaderMaterial
		shader_material.set_shader_parameter("trail_tint", tint)
		shader_material.set_shader_parameter("trail_fade", _fade_strength)
		shader_material.set_shader_parameter("progress_scale", float(_mesh.sections) / float(maxi(_points.size() - 1, 1)))
		shader_material.set_shader_parameter("tail_fade_fraction", tail_fade_fraction)
		shader_material.set_shader_parameter("head_fade_fraction", head_fade_fraction)
		shader_material.set_shader_parameter("head_min_opacity", head_min_opacity)
	else:
		transparency = 1.0 - clampf(_fade_strength, 0.0, 1.0)


func _rebuild_mesh() -> void:
	visible = _points.size() >= 2 and width > 0.0 and _fade_strength > 0.0
	if not visible:
		return
	_configure_ribbon()
	_trim_points()
	var point_count: int = _points.size()
	global_position = _points[0]
	var bounds: AABB = AABB(Vector3.ZERO, Vector3.ZERO)
	var previous_width_direction: Vector3 = Vector3.ZERO
	for index: int in _trail_skeleton.get_bone_count():
		var point_index: int = mini(index, point_count - 1)
		var tangent: Vector3 = _tangent_at(point_index)
		var width_direction: Vector3 = _width_direction_at(point_index, tangent, previous_width_direction)
		previous_width_direction = width_direction
		var progress: float = float(point_index) / float(point_count - 1)
		var width_scale: float = maxf(lerpf(tail_width_scale, head_width_scale, progress), sin(progress * PI))
		var span: float = maxf(width * width_scale, 0.00001)
		var normal: Vector3 = width_direction.cross(tangent).normalized()
		var basis: Basis = Basis(width_direction * span, tangent, normal * span)
		var point: Vector3 = _points[point_index] - global_position
		_trail_skeleton.set_bone_pose(index, Transform3D(basis, point))
		bounds = bounds.expand(point)
	custom_aabb = bounds.grow(maxf(width, 0.01))
	_update_material()


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
	var width_direction: Vector3 = Vector3.ZERO
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


func _normalized_up_hint(up_hint: Vector3) -> Vector3:
	if up_hint.length() < 0.001:
		return Vector3.UP
	return up_hint.normalized()

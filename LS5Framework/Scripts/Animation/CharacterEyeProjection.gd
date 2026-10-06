@tool
extends Node
class_name CharacterEyeProjection

## Eye mesh receiving the projection material.
@export var eye_mesh: MeshInstance3D
## Left pupil projector; its local axes and scale define the mapping space.
@export var left_projector: Node3D
## Right pupil projector; its local axes and scale define the mapping space.
@export var right_projector: Node3D
## Shared material template copied for each eye mesh instance.
@export var projection_material: ShaderMaterial
## Surface receiving the eye material.
@export_range(0, 255, 1) var surface_index: int = 0
## Matches projector transforms to the eye mesh's interpolated render transform.
@export var match_physics_interpolation: bool = true

var _bound_mesh: MeshInstance3D
var _bound_template: ShaderMaterial
var _bound_surface: int = -1
var _material: ShaderMaterial
var _previous_material: Material


func _ready() -> void:
	_bind_material()
	RenderingServer.frame_pre_draw.connect(_update_projection)


func _process(_delta: float) -> void:
	if eye_mesh != _bound_mesh or projection_material != _bound_template or surface_index != _bound_surface:
		_bind_material()


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_update_projection):
		RenderingServer.frame_pre_draw.disconnect(_update_projection)
	_release_material()


func _release_material() -> void:
	if is_instance_valid(_bound_mesh) and _bound_mesh.mesh and _bound_surface >= 0 and _bound_surface < _bound_mesh.mesh.get_surface_count():
		if _bound_mesh.get_surface_override_material(_bound_surface) == _material:
			_bound_mesh.set_surface_override_material(_bound_surface, _previous_material)
	if _bound_template and _bound_template.changed.is_connected(_bind_material):
		_bound_template.changed.disconnect(_bind_material)
	_material = null
	_previous_material = null
	_bound_mesh = null
	_bound_template = null
	_bound_surface = -1


func _bind_material() -> void:
	_release_material()
	_bound_mesh = eye_mesh
	_bound_template = projection_material
	_bound_surface = surface_index
	if not is_instance_valid(eye_mesh) or not eye_mesh.mesh or not projection_material:
		return
	if surface_index < 0 or surface_index >= eye_mesh.mesh.get_surface_count():
		return
	_previous_material = eye_mesh.get_surface_override_material(surface_index)
	_material = projection_material.duplicate() as ShaderMaterial
	eye_mesh.set_surface_override_material(surface_index, _material)
	projection_material.changed.connect(_bind_material)
	_update_projection()


func _update_projection() -> void:
	if not _material:
		return
	var render_correction: Transform3D = _get_render_correction()
	var enabled: Vector2 = Vector2.ZERO
	if is_instance_valid(left_projector) and left_projector.is_inside_tree():
		var left_transform: Transform3D = render_correction * left_projector.global_transform
		if absf(left_transform.basis.determinant()) > 0.000001:
			_material.set_shader_parameter(&"world_to_left", left_transform.affine_inverse())
			enabled.x = 1.0
	if is_instance_valid(right_projector) and right_projector.is_inside_tree():
		var right_transform: Transform3D = render_correction * right_projector.global_transform
		if absf(right_transform.basis.determinant()) > 0.000001:
			_material.set_shader_parameter(&"world_to_right", right_transform.affine_inverse())
			enabled.y = 1.0
	_material.set_shader_parameter(&"projector_enabled", enabled)


func _get_render_correction() -> Transform3D:
	if not match_physics_interpolation or not is_instance_valid(eye_mesh) or not eye_mesh.is_inside_tree():
		return Transform3D.IDENTITY
	var physics_transform: Transform3D = eye_mesh.global_transform
	if absf(physics_transform.basis.determinant()) <= 0.000001:
		return Transform3D.IDENTITY
	var render_transform: Transform3D = eye_mesh.get_global_transform_interpolated()
	return render_transform * physics_transform.affine_inverse()

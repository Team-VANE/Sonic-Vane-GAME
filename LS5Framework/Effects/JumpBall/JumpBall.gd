extends Node3D
class_name JumpBall

## Visual instance imported from the jump ball GLB.
@export var visual_root_path: NodePath = NodePath("Visual")
## Animation tree used for basis-to-extruded blending.
@export var animation_tree_path: NodePath = NodePath("AnimationTree")
## Material applied to jump ball mesh surfaces.
@export var jump_ball_material: ShaderMaterial
## Color used by the jump ball shader.
@export var tint: Color = Color(0.2, 0.8, 1.0, 0.72)
## Speed where the jump ball reaches full extrusion.
@export var speed_for_full_extrusion: float = 140.0
## Speed where the tail fade reaches full strength.
@export var speed_for_full_tail_fade: float = 160.0
## Blend fade speed used when appearing.
@export var fade_in_speed: float = 18.0
## Blend fade speed used when disappearing.
@export var fade_out_speed: float = 16.0
## Heading offset applied around the supplied up axis.
@export var heading_angle_offset_deg: float = 90.0
## Local mesh direction used for fading toward the extruded tip.
@export var tail_fade_axis: Vector3 = Vector3(0.0, 0.0, -1.0)
## Local axis distance where tip fade begins.
@export var tail_fade_start: float = 0.18
## Local axis distance over which tip fade reaches minimum alpha.
@export var tail_fade_length: float = 1.35

var _visual_root: Node3D = null
var _animation_tree: AnimationTree = null
var _material: ShaderMaterial = null
var _visible_amount: float = 0.0
var _last_heading: Vector3 = Vector3.FORWARD


func _ready() -> void:
	top_level = true
	_visual_root = get_node_or_null(visual_root_path) as Node3D
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	_setup_material()
	if _animation_tree != null:
		_animation_tree.active = true
		_apply_animation(0.0)
	visible = false


func set_tint(color: Color) -> void:
	tint = color
	_apply_material_params(0.0, 0.0)


func set_speed_for_full_extrusion(value: float) -> void:
	speed_for_full_extrusion = max(value, 0.001)


func set_jump_ball_active(delta: float, active: bool, world_position: Vector3, heading: Vector3, up: Vector3) -> void:
	var speed: float = heading.length()
	global_position = world_position

	if not active:
		_visible_amount = 0.0
		visible = false
		_apply_material_params(0.0, 0.0)
		return

	var target_amount: float = 1.0 if active else 0.0
	var fade_speed: float = fade_in_speed if target_amount > _visible_amount else fade_out_speed
	_visible_amount = move_toward(_visible_amount, target_amount, max(fade_speed, 0.0) * delta)
	visible = _visible_amount > 0.001

	if visible:
		_update_orientation(heading, up)

	var extrusion: float = clamp(speed / max(speed_for_full_extrusion, 0.001), 0.0, 1.0)
	var tail_fade: float = clamp(speed / max(speed_for_full_tail_fade, 0.001), 0.0, 1.0)
	_apply_animation(extrusion)
	_apply_material_params(_visible_amount, tail_fade)


func _setup_material() -> void:
	if jump_ball_material != null:
		_material = jump_ball_material
	else:
		_material = ShaderMaterial.new()
	_apply_material_to_meshes(self)
	_apply_material_params(0.0, 0.0)


func _apply_material_to_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.material_override = _material
	for child in node.get_children():
		_apply_material_to_meshes(child)


func _apply_animation(extrusion: float) -> void:
	if _animation_tree == null:
		return
	_animation_tree.set("parameters/JumpBallBlend/blend_position", clamp(extrusion, 0.0, 1.0))


func _apply_material_params(alpha: float, tail_fade: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("jump_ball_color", tint)
	_material.set_shader_parameter("jump_ball_alpha", clamp(alpha, 0.0, 1.0))
	_material.set_shader_parameter("tail_fade_strength", clamp(tail_fade, 0.0, 1.0))
	_material.set_shader_parameter("tail_fade_axis", tail_fade_axis.normalized() if tail_fade_axis.length() > 0.001 else Vector3(0.0, 0.0, -1.0))
	_material.set_shader_parameter("tail_fade_start", tail_fade_start)
	_material.set_shader_parameter("tail_fade_length", tail_fade_length)


func _update_orientation(heading: Vector3, up: Vector3) -> void:
	if heading.length() > 0.001:
		_last_heading = heading.normalized()
	if _last_heading.length() <= 0.001:
		return
	var up_dir: Vector3 = up.normalized()
	if up_dir.length() <= 0.001:
		up_dir = Vector3.UP
	var forward_dir: Vector3 = -_last_heading
	if abs(forward_dir.dot(up_dir)) > 0.98:
		up_dir = Vector3.RIGHT
	var target_basis: Basis = Basis().looking_at(forward_dir, up_dir)
	if abs(heading_angle_offset_deg) > 0.001:
		target_basis = Basis(up_dir, deg_to_rad(heading_angle_offset_deg)) * target_basis
	var current_scale: Vector3 = scale
	global_transform = Transform3D(target_basis.scaled(current_scale), global_position)

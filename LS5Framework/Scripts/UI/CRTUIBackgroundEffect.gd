extends Node
class_name CRTUIBackgroundEffect

const BACKGROUND_SHADER: Shader = preload("res://LS5Framework/Shaders/UI/UIBackgroundCRT.gdshader")
const MAX_TEXT_CLEARANCE_RECTS: int = 32

## Root containing controls that receive the background scanline material.
@export var target_root_path: NodePath = NodePath("..")
## Strength of scanlines drawn over large panel backgrounds.
@export_range(0.0, 1.0, 0.01) var panel_scanline_strength: float = 0.05
## Strength of scanlines drawn over compact framed backgrounds.
@export_range(0.0, 1.0, 0.01) var compact_scanline_strength: float = 0.05
## Strength of scanlines drawn over button backgrounds.
@export_range(0.0, 1.0, 0.01) var button_scanline_strength: float = 0.14
## Color shared by scanlines across managed backgrounds.
@export var scanline_color: Color = Color(0.3, 0.7, 1.0, 1.0)
## Highlight added between dark scanlines on large panels.
@export_range(0.0, 0.25, 0.005) var panel_scanline_lift: float = 0.025
## Highlight added between dark scanlines on compact frames.
@export_range(0.0, 0.25, 0.005) var compact_scanline_lift: float = 0.035
## Highlight added between dark scanlines on buttons.
@export_range(0.0, 0.25, 0.005) var button_scanline_lift: float = 0.045
## Vertical spacing between scanlines in screen pixels.
@export_range(1.0, 16.0, 0.25) var scanline_spacing_px: float = 6.0
## Visible width of each scanline in screen pixels.
@export_range(0.25, 8.0, 0.25) var scanline_width_px: float = 2.5
## Downward scanline travel speed in screen pixels per second. Negative values reverse direction.
@export_range(-32.0, 100.0, 0.05) var scanline_scroll_speed_px: float = 4.00
## Proportional strength used for ordinary scanline flicker.
@export_range(0.0, 2.0, 0.001) var scanline_flicker_subtle_strength: float = 0.01
## Proportional strength available to infrequent CRT-like flicker peaks.
@export_range(0.0, 2.0, 0.001) var scanline_flicker_peak_strength: float = 0.65
## Clusters flicker samples near the subtle strength. Higher values make peaks less frequent.
@export_range(1.0, 32.0, 0.25) var scanline_flicker_bias: float = 24.0
## Independent random strength updates per second.
@export_range(0.0, 90.0, 0.25) var scanline_flicker_speed: float = 75.0
## Maximum control height treated as a compact frame.
@export_range(16.0, 512.0, 1.0) var compact_frame_max_height: float = 128.0
## Enables dynamic scanline feathering around foreground text.
@export var text_clearance_enabled: bool = false
## Empty space maintained between text bounds and visible scanlines.
@export_range(0.0, 32.0, 0.5) var text_clearance_padding_px: float = 3.0
## Distance over which scanlines fade back in around text.
@export_range(0.0, 32.0, 0.5) var text_clearance_feather_px: float = 7.0
## Seconds between text-clearance layout refreshes.
@export_range(0.05, 1.0, 0.05) var text_mask_refresh_interval: float = 0.15

## Contains controls that receive the scanline material.
@onready var target_root: Node = get_node_or_null(target_root_path)

var _panel_material: ShaderMaterial = null
var _compact_material: ShaderMaterial = null
var _button_material: ShaderMaterial = null
var _managed_controls: Array[Control] = []
var _text_mask_refresh_timer: float = 0.0


func _ready() -> void:
	_panel_material = _create_material(panel_scanline_strength, panel_scanline_lift)
	_compact_material = _create_material(compact_scanline_strength, compact_scanline_lift)
	_button_material = _create_material(button_scanline_strength, button_scanline_lift)
	call_deferred("refresh")
	set_process(text_clearance_enabled)
	if get_tree() != null and not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.disconnect(_on_tree_node_added)


func _process(delta: float) -> void:
	_text_mask_refresh_timer -= delta
	if _text_mask_refresh_timer > 0.0:
		return
	_text_mask_refresh_timer = max(text_mask_refresh_interval, 0.05)
	_refresh_text_clearance_masks()


func refresh() -> void:
	if target_root == null or not is_instance_valid(target_root):
		return
	_apply_to_branch(target_root)


func set_scanline_color(color: Color) -> void:
	scanline_color = color
	for effect_material: ShaderMaterial in [_panel_material, _compact_material, _button_material]:
		if effect_material != null:
			effect_material.set_shader_parameter("scanline_color", scanline_color)
	for control: Control in _managed_controls:
		if is_instance_valid(control) and control.material is ShaderMaterial:
			(control.material as ShaderMaterial).set_shader_parameter("scanline_color", scanline_color)


func _on_tree_node_added(node: Node) -> void:
	if target_root == null or not is_instance_valid(target_root):
		return
	if node == target_root or target_root.is_ancestor_of(node):
		call_deferred("_apply_to_branch", node)


func _apply_to_branch(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		var control: Control = node as Control
		if _is_background_control(control) and control.material == null:
			var background_material: ShaderMaterial = _get_background_material(control)
			if text_clearance_enabled:
				var control_material: ShaderMaterial = background_material.duplicate() as ShaderMaterial
				control.material = control_material
				_managed_controls.append(control)
				_update_text_clearance_mask(control)
			else:
				control.material = background_material
	for child: Node in node.get_children():
		_apply_to_branch(child)


func _is_background_control(control: Control) -> bool:
	return (
		control is Button
		or control is Panel
		or control is PanelContainer
		or control is LineEdit
		or control is TextEdit
		or control is ItemList
		or control is Tree
		or control is RichTextLabel
		or control is TabBar
		or control is TabContainer
	)


func _create_material(strength: float, lift: float) -> ShaderMaterial:
	var effect_material: ShaderMaterial = ShaderMaterial.new()
	effect_material.shader = BACKGROUND_SHADER
	effect_material.set_shader_parameter("scanline_strength", strength)
	effect_material.set_shader_parameter("scanline_lift", lift)
	effect_material.set_shader_parameter("scanline_color", scanline_color)
	effect_material.set_shader_parameter("scanline_spacing_px", scanline_spacing_px)
	effect_material.set_shader_parameter("scanline_width_px", scanline_width_px)
	effect_material.set_shader_parameter("scanline_scroll_speed_px", scanline_scroll_speed_px)
	effect_material.set_shader_parameter("scanline_flicker_subtle_strength", scanline_flicker_subtle_strength)
	effect_material.set_shader_parameter("scanline_flicker_peak_strength", scanline_flicker_peak_strength)
	effect_material.set_shader_parameter("scanline_flicker_bias", scanline_flicker_bias)
	effect_material.set_shader_parameter("scanline_flicker_speed", scanline_flicker_speed)
	effect_material.set_shader_parameter("text_clearance_padding_px", text_clearance_padding_px)
	effect_material.set_shader_parameter("text_clearance_feather_px", text_clearance_feather_px)
	return effect_material


func _get_background_material(control: Control) -> ShaderMaterial:
	if control is Button:
		return _button_material
	if control is LineEdit or control is TabBar:
		return _compact_material
	if control is Panel or control is PanelContainer:
		if control.size.y <= compact_frame_max_height:
			return _compact_material
	return _panel_material


func _refresh_text_clearance_masks() -> void:
	for index: int in range(_managed_controls.size() - 1, -1, -1):
		var control: Control = _managed_controls[index]
		if not is_instance_valid(control):
			_managed_controls.remove_at(index)
			continue
		if control.is_visible_in_tree():
			_update_text_clearance_mask(control)


func _update_text_clearance_mask(background: Control) -> void:
	if background == null or not is_instance_valid(background):
		return
	var effect_material: ShaderMaterial = background.material as ShaderMaterial
	if effect_material == null:
		return
	var clearance_rects: Array[Vector4] = []
	_collect_text_clearance_rects(background, background, clearance_rects)
	var clearance_count: int = min(clearance_rects.size(), MAX_TEXT_CLEARANCE_RECTS)
	while clearance_rects.size() < MAX_TEXT_CLEARANCE_RECTS:
		clearance_rects.append(Vector4.ZERO)
	effect_material.set_shader_parameter("text_clearance_count", clearance_count)
	effect_material.set_shader_parameter("text_clearance_rects", clearance_rects)


func _collect_text_clearance_rects(
		background: Control,
		node: Node,
		clearance_rects: Array[Vector4]
	) -> void:
	if clearance_rects.size() >= MAX_TEXT_CLEARANCE_RECTS:
		return
	if node is Control:
		var text_control: Control = node as Control
		if text_control.is_visible_in_tree() and _is_text_control(text_control):
			var text_rect: Rect2 = _get_text_rect(text_control)
			var local_rect: Rect2 = _convert_rect_to_background(background, text_control, text_rect)
			var clipped_rect: Rect2 = local_rect.intersection(Rect2(Vector2.ZERO, background.size))
			if clipped_rect.size.x > 0.0 and clipped_rect.size.y > 0.0:
				clearance_rects.append(Vector4(
					clipped_rect.position.x,
					clipped_rect.position.y,
					clipped_rect.size.x,
					clipped_rect.size.y
				))
	for child: Node in node.get_children():
		_collect_text_clearance_rects(background, child, clearance_rects)


func _is_text_control(control: Control) -> bool:
	return (
		control is Label
		or control is Button
		or control is LineEdit
		or control is TextEdit
		or control is RichTextLabel
		or control is TabBar
	)


func _get_text_rect(control: Control) -> Rect2:
	if control is Label:
		var label: Label = control as Label
		return _get_single_line_text_rect(
			label,
			label.text,
			label.horizontal_alignment,
			label.vertical_alignment
		)
	if control is Button:
		var button: Button = control as Button
		return _get_single_line_text_rect(
			button,
			button.text,
			button.alignment,
			VERTICAL_ALIGNMENT_CENTER
		)
	if control is LineEdit:
		var line_edit: LineEdit = control as LineEdit
		var displayed_text: String = line_edit.text if line_edit.text != "" else line_edit.placeholder_text
		return _get_single_line_text_rect(
			line_edit,
			displayed_text,
			line_edit.alignment,
			VERTICAL_ALIGNMENT_CENTER
		)
	return Rect2(Vector2.ZERO, control.size)


func _get_single_line_text_rect(
		control: Control,
		text: String,
		horizontal_alignment: int,
		vertical_alignment: int
	) -> Rect2:
	if text == "":
		return Rect2()
	var text_font: Font = control.get_theme_font("font")
	var text_font_size: int = control.get_theme_font_size("font_size")
	var text_size: Vector2 = text_font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		text_font_size
	)
	text_size.y = text_font.get_height(text_font_size)
	var text_position: Vector2 = Vector2.ZERO
	if horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		text_position.x = (control.size.x - text_size.x) * 0.5
	elif horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		text_position.x = control.size.x - text_size.x
	if vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		text_position.y = (control.size.y - text_size.y) * 0.5
	elif vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		text_position.y = control.size.y - text_size.y
	return Rect2(text_position, text_size)


func _convert_rect_to_background(
		background: Control,
		text_control: Control,
		text_rect: Rect2
	) -> Rect2:
	var text_transform: Transform2D = text_control.get_global_transform_with_canvas()
	var background_inverse: Transform2D = background.get_global_transform_with_canvas().affine_inverse()
	var top_left: Vector2 = background_inverse * (text_transform * text_rect.position)
	var bottom_right: Vector2 = background_inverse * (
		text_transform * (text_rect.position + text_rect.size)
	)
	var rect_position: Vector2 = Vector2(
		min(top_left.x, bottom_right.x),
		min(top_left.y, bottom_right.y)
	)
	var rect_size: Vector2 = Vector2(
		abs(bottom_right.x - top_left.x),
		abs(bottom_right.y - top_left.y)
	)
	return Rect2(rect_position, rect_size)

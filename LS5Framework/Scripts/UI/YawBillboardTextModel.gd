extends Node3D

const POST_PROCESS_EXEMPT_3D_LAYER: int = 1 << 19
const TITLE_FONT: Font = preload("res://LS5Framework/Resources/Fonts/Orbitron900.tres")
const BODY_FONT: Font = preload("res://LS5Framework/Resources/Fonts/Orbitron600.tres")
const CRT_EFFECT_SCRIPT: Script = preload("res://LS5Framework/Scripts/UI/CRTUIBackgroundEffect.gd")
const PANEL_COLOR: Color = Color(0.01, 0.025, 0.065, 0.94)
const FRAME_COLOR: Color = Color(0.18, 0.52, 1.0, 0.98)
const HIGHLIGHT_COLOR: Color = Color(0.48, 0.78, 1.0, 1.0)
const PROMPT_COLOR: Color = Color(1.0, 0.86, 0.16, 1.0)
const BODY_COLOR: Color = Color(0.9, 0.95, 1.0, 1.0)
const PIXELS_PER_WORLD_UNIT: float = 100.0
const WORLD_TEXT_CANVAS_LAYER: int = 0
const INFO_PANEL_MIN_WIDTH: float = 5.0
const INFO_PANEL_DEFAULT_WIDTH: float = 12.96
const INFO_PANEL_MAX_WIDTH: float = 24.0
const TITLE_HORIZONTAL_PADDING_PIXELS: float = 48.0
const TITLE_BASE_HEIGHT_PIXELS: float = 82.0
const INFO_BASE_TOP_PIXELS: float = 108.0
const INFO_BOTTOM_PADDING_PIXELS: float = 24.0
const TITLE_ELLIPSIS: String = ". . ."

var title_text: String = ""
var info_text: String = ""
var message_text: String = ""
var _message_mode: bool = false
var _prompt_mode: bool = false
var _pixel_size: float = 0.01
var _base_tint: Color = Color.WHITE
var _opacity: float = 1.0
var _panel_size: Vector2 = Vector2(INFO_PANEL_DEFAULT_WIDTH, 3.2)
var _info_panel_max_width: float = INFO_PANEL_DEFAULT_WIDTH
var _title_uses_second_line: bool = false
var _display_title_text: String = ""
var _canvas_layer: CanvasLayer = null
var _panel: Panel = null
var _accent: ColorRect = null
var _title_label: Label = null
var _info_label: Label = null
var _panel_style: StyleBoxFlat = null
var _scanline_effect = null


func _ready() -> void:
	_ensure_model()
	_apply_content()
	set_process(true)


func _process(_delta: float) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		_set_canvas_visible(false)
		return
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null or camera.is_position_behind(global_position):
		_set_canvas_visible(false)
		return
	var direction: Vector3 = camera.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.000001:
		var yaw: float = atan2(direction.x, direction.z)
		global_rotation = Vector3(0.0, yaw, 0.0)
	_update_canvas_projection(camera, viewport)


func set_title_and_info(title: String, info: String) -> void:
	title_text = title
	info_text = info
	message_text = ""
	_message_mode = false
	_prompt_mode = false
	_update_info_panel_layout()
	_apply_content()


func set_message(message: String, is_prompt: bool = false) -> void:
	message_text = message
	_message_mode = true
	_prompt_mode = is_prompt
	_panel_size = _measure_message_panel(message)
	_apply_content()


func configure(pixel_size: float, tint: Color, _no_depth_test: bool, _render_layers: int = POST_PROCESS_EXEMPT_3D_LAYER, panel_width: float = 0.0) -> void:
	_pixel_size = max(pixel_size, 0.001)
	_base_tint = tint
	if not _message_mode and panel_width > 0.0:
		_info_panel_max_width = clamp(panel_width, INFO_PANEL_MIN_WIDTH, INFO_PANEL_MAX_WIDTH)
		_update_info_panel_layout()
	_ensure_model()
	_apply_content()


func set_opacity(value: float) -> void:
	_opacity = clamp(value, 0.0, 1.0)
	_apply_colors()


func _ensure_model() -> void:
	if _panel != null:
		return
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "WorldTextCanvas"
	_canvas_layer.layer = WORLD_TEXT_CANVAS_LAYER
	_canvas_layer.visible = false
	add_child(_canvas_layer)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = PANEL_COLOR
	_panel_style.border_width_left = 4
	_panel_style.border_width_top = 4
	_panel_style.border_width_right = 4
	_panel_style.border_width_bottom = 4
	_panel_style.corner_radius_top_left = 10
	_panel_style.corner_radius_top_right = 10
	_panel_style.corner_radius_bottom_right = 10
	_panel_style.corner_radius_bottom_left = 10
	_panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	_panel_style.shadow_size = 10

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_canvas_layer.add_child(_panel)
	_scanline_effect = CRT_EFFECT_SCRIPT.new()
	_scanline_effect.name = "ScanlineEffect"
	_scanline_effect.target_root_path = NodePath("..")
	_scanline_effect.panel_scanline_strength = 0.035
	_scanline_effect.compact_scanline_strength = 0.035
	_scanline_effect.panel_scanline_lift = 0.015
	_scanline_effect.compact_scanline_lift = 0.015
	_scanline_effect.scanline_spacing_px = 6.0
	_scanline_effect.scanline_width_px = 1.0
	_panel.add_child(_scanline_effect)

	_accent = ColorRect.new()
	_accent.name = "Accent"
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_accent)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.max_lines_visible = 2
	_title_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_title_label.add_theme_font_override("font", TITLE_FONT)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.002, 0.012, 1.0))
	_title_label.add_theme_constant_override("outline_size", 8)
	_panel.add_child(_title_label)

	_info_label = Label.new()
	_info_label.name = "Info"
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_override("font", BODY_FONT)
	_info_label.add_theme_color_override("font_outline_color", Color(0.0, 0.002, 0.012, 1.0))
	_info_label.add_theme_constant_override("outline_size", 5)
	_panel.add_child(_info_label)


func _apply_content() -> void:
	if not is_inside_tree():
		return
	_ensure_model()
	_apply_geometry()
	if _message_mode:
		_title_label.text = message_text
		_info_label.text = ""
		_info_label.visible = false
	else:
		_title_label.text = _display_title_text
		_info_label.text = info_text
		_info_label.visible = info_text != ""
	_apply_colors()


func _apply_geometry() -> void:
	if _panel == null:
		return
	var panel_pixels: Vector2 = _panel_size * PIXELS_PER_WORLD_UNIT
	var font_scale: float = _pixel_size / 0.01
	_panel.size = panel_pixels
	_panel.pivot_offset = panel_pixels * 0.5
	_accent.position = Vector2(4.0, 4.0)
	_accent.size = Vector2(panel_pixels.x - 8.0, 8.0)
	if _message_mode:
		_title_label.position = Vector2(22.0, 16.0)
		_title_label.size = panel_pixels - Vector2(44.0, 32.0)
		_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title_label.add_theme_font_size_override("font_size", maxi(12, int(28.0 * font_scale)))
	else:
		_title_label.position = Vector2(24.0, 24.0)
		var title_font_size: int = maxi(18, int(42.0 * font_scale))
		var second_line_height: float = float(title_font_size + 8) if _title_uses_second_line else 0.0
		_title_label.size = Vector2(panel_pixels.x - TITLE_HORIZONTAL_PADDING_PIXELS, TITLE_BASE_HEIGHT_PIXELS + second_line_height)
		_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title_label.add_theme_font_size_override("font_size", title_font_size)
		var info_top: float = INFO_BASE_TOP_PIXELS + second_line_height
		_info_label.position = Vector2(28.0, info_top)
		_info_label.size = Vector2(panel_pixels.x - 56.0, panel_pixels.y - info_top - INFO_BOTTOM_PADDING_PIXELS)
		_info_label.add_theme_font_size_override("font_size", maxi(12, int(25.0 * font_scale)))


func _update_info_panel_layout() -> void:
	var title_font_size: int = maxi(18, int(42.0 * (_pixel_size / 0.01)))
	var maximum_content_width: float = _info_panel_max_width * PIXELS_PER_WORLD_UNIT - TITLE_HORIZONTAL_PADDING_PIXELS
	var title_size: Vector2 = TITLE_FONT.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_font_size)
	var explicit_line_count: int = title_text.split("\n").size()
	_title_uses_second_line = explicit_line_count > 1 or title_size.x > maximum_content_width
	_display_title_text = _fit_title_to_lines(title_text, maximum_content_width, title_font_size)
	var fitted_title_width: float = min(title_size.x + TITLE_HORIZONTAL_PADDING_PIXELS, _info_panel_max_width * PIXELS_PER_WORLD_UNIT)
	var panel_width: float = clamp(fitted_title_width / PIXELS_PER_WORLD_UNIT, INFO_PANEL_MIN_WIDTH, _info_panel_max_width)
	var second_line_height: float = float(title_font_size + 8) / PIXELS_PER_WORLD_UNIT if _title_uses_second_line else 0.0
	_panel_size = Vector2(panel_width, 3.2 + second_line_height)


func _fit_title_to_lines(title: String, maximum_width: float, font_size: int) -> String:
	var normalized_title: String = " ".join(title.replace("\n", " ").split(" ", false)).strip_edges()
	if normalized_title == "":
		return ""
	if _measure_title_width(normalized_title, font_size) <= maximum_width:
		return normalized_title
	var first_length: int = _get_fitting_title_length(normalized_title, maximum_width, font_size)
	var first_break: int = _find_title_word_break(normalized_title, first_length)
	var first_line: String = normalized_title.left(first_break).strip_edges()
	var remaining: String = normalized_title.substr(first_break).strip_edges()
	if remaining == "":
		return first_line
	if _measure_title_width(remaining, font_size) <= maximum_width:
		return "%s\n%s" % [first_line, remaining]
	var suffix_width: float = _measure_title_width(" " + TITLE_ELLIPSIS, font_size)
	var second_length: int = _get_fitting_title_length(remaining, max(maximum_width - suffix_width, 0.0), font_size)
	var second_break: int = _find_title_word_break(remaining, second_length)
	var second_line: String = remaining.left(second_break).strip_edges()
	if second_line == "":
		second_line = remaining.left(second_length).strip_edges()
	return "%s\n%s %s" % [first_line, second_line, TITLE_ELLIPSIS]


func _get_fitting_title_length(text: String, maximum_width: float, font_size: int) -> int:
	var fitting_length: int = 0
	for character_index: int in range(1, text.length() + 1):
		if _measure_title_width(text.left(character_index), font_size) > maximum_width:
			break
		fitting_length = character_index
	return maxi(fitting_length, 1)


func _find_title_word_break(text: String, fitting_length: int) -> int:
	var fitting_text: String = text.left(fitting_length)
	var word_break: int = fitting_text.rfind(" ")
	if word_break > 0 and word_break >= fitting_length / 2:
		return word_break
	return fitting_length


func _measure_title_width(text: String, font_size: int) -> float:
	return TITLE_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func _apply_colors() -> void:
	if _panel == null:
		return
	var tint_alpha: float = _base_tint.a * _opacity
	var frame_color: Color = PROMPT_COLOR if _prompt_mode else FRAME_COLOR
	var accent_color: Color = PROMPT_COLOR if _prompt_mode else HIGHLIGHT_COLOR
	_panel_style.bg_color = Color(PANEL_COLOR.r * _base_tint.r, PANEL_COLOR.g * _base_tint.g, PANEL_COLOR.b * _base_tint.b, PANEL_COLOR.a * tint_alpha)
	_panel_style.border_color = Color(frame_color.r * _base_tint.r, frame_color.g * _base_tint.g, frame_color.b * _base_tint.b, frame_color.a * tint_alpha)
	_accent.color = Color(accent_color.r * _base_tint.r, accent_color.g * _base_tint.g, accent_color.b * _base_tint.b, accent_color.a * tint_alpha)
	var title_color: Color = PROMPT_COLOR if _prompt_mode else HIGHLIGHT_COLOR
	_title_label.add_theme_color_override("font_color", Color(title_color.r * _base_tint.r, title_color.g * _base_tint.g, title_color.b * _base_tint.b, tint_alpha))
	_info_label.add_theme_color_override("font_color", Color(BODY_COLOR.r * _base_tint.r, BODY_COLOR.g * _base_tint.g, BODY_COLOR.b * _base_tint.b, tint_alpha))


func _update_canvas_projection(camera: Camera3D, viewport: Viewport) -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	if viewport_size.y <= 0.0:
		_set_canvas_visible(false)
		return
	var pixels_per_world_unit: float = 1.0
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		pixels_per_world_unit = viewport_size.y / max(camera.size, 0.001)
	else:
		var camera_space_position: Vector3 = camera.global_transform.affine_inverse() * global_position
		var depth: float = max(-camera_space_position.z, 0.001)
		var vertical_fov: float = deg_to_rad(camera.fov)
		pixels_per_world_unit = viewport_size.y / max(2.0 * tan(vertical_fov * 0.5) * depth, 0.001)
	var global_scale_value: float = (global_basis.x.length() + global_basis.y.length() + global_basis.z.length()) / 3.0
	var canvas_scale: float = max((pixels_per_world_unit / PIXELS_PER_WORLD_UNIT) * global_scale_value, 0.001)
	var screen_position: Vector2 = camera.unproject_position(global_position)
	_panel.scale = Vector2.ONE * canvas_scale
	_panel.position = screen_position - _panel.size * 0.5
	_set_canvas_visible(is_visible_in_tree())


func _set_canvas_visible(value: bool) -> void:
	if _canvas_layer != null:
		_canvas_layer.visible = value


func _measure_message_panel(message: String) -> Vector2:
	var lines: PackedStringArray = message.split("\n")
	var longest_line: int = 0
	for line: String in lines:
		longest_line = max(longest_line, line.length())
	var width: float = clamp(float(longest_line) * 0.18 + 1.0, 3.0, 8.0)
	var wrapped_lines: int = max(lines.size(), ceili(float(longest_line) / 38.0))
	var height: float = clamp(0.72 + float(wrapped_lines) * 0.38, 1.1, 3.0)
	return Vector2(width, height)

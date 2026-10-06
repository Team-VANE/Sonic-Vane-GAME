extends Control
class_name HUDStatContainer

## Displays the generated stat panel and scanline background.
@onready var stat_background: ColorRect = $Background
## Displays the stat name inside the container.
@onready var stat_name_label: Label = $ContentMargin/StatText/StatName
## Aligns the current stat value to the right side of the container.
@onready var stat_value_container: HBoxContainer = $ContentMargin/StatText/StatValue
## Supplies the font and outline settings for generated value cells.
@onready var stat_value_template: Label = $ContentMargin/StatText/StatValue/ValueTemplate

## Name displayed on the left side of the stat container.
@export var stat_name: String = "Stat"
## Value displayed before the HUD provides live data.
@export var initial_value: String = "0"
## Dims leading zero placeholders until their digit positions become significant.
@export var dim_leading_zeros: bool = false
## Opacity used by leading zero placeholders.
@export_range(0.0, 1.0, 0.01) var leading_zero_opacity: float = 0.1
@export_group("Warning Flash")
## Allows the stat name to flash while its warning state is active.
@export var warning_flash_enabled: bool = false
## Seconds each warning color remains visible before alternating.
@export var warning_flash_interval: float = 0.133333
## Alternate color displayed by the stat name during a warning.
@export var warning_flash_color: Color = Color(1.0, 0.08, 0.08, 1.0)

var _normal_name_color: Color = Color.WHITE
var _warning_active: bool = false
var _warning_showing_color: bool = false
var _warning_timer: float = 0.0
var _value_cells: Array[Label] = []
var _value_text: String = ""
var _digit_cell_width: float = 0.0


func _ready() -> void:
	if stat_background.material != null:
		stat_background.material = stat_background.material.duplicate()
	stat_background.resized.connect(_update_background_size)
	_update_background_size()
	stat_name_label.text = stat_name
	_digit_cell_width = _measure_digit_cell_width()
	set_value_text(initial_value)
	_normal_name_color = stat_name_label.get_theme_color("font_color")
	set_process(false)


func _process(delta: float) -> void:
	if not _warning_active:
		return
	_warning_timer -= delta
	var interval: float = max(warning_flash_interval, 0.001)
	while _warning_timer <= 0.0:
		_warning_timer += interval
		_warning_showing_color = not _warning_showing_color
		_apply_warning_color()


func set_value_text(value: String) -> void:
	if stat_value_container == null or stat_value_template == null:
		call_deferred("set_value_text", value)
		return
	if value == _value_text:
		return
	_value_text = value
	_ensure_value_cell_count(value.length())
	var first_significant_index: int = _get_first_significant_index(value)
	for index: int in range(_value_cells.size()):
		var character: String = value.substr(index, 1)
		var value_cell: Label = _value_cells[index]
		value_cell.text = character
		value_cell.custom_minimum_size.x = _get_character_cell_width(character)
		value_cell.modulate.a = (
			clamp(leading_zero_opacity, 0.0, 1.0)
			if dim_leading_zeros and index < first_significant_index
			else 1.0
		)


func _get_first_significant_index(value: String) -> int:
	if not dim_leading_zeros or value == "":
		return 0
	for index: int in range(value.length()):
		if value.substr(index, 1) != "0":
			return index
	return max(value.length() - 1, 0)


func _measure_digit_cell_width() -> float:
	var value_font: Font = stat_value_template.get_theme_font("font")
	var value_font_size: int = stat_value_template.get_theme_font_size("font_size")
	var widest_digit: float = 0.0
	for digit: int in range(10):
		var digit_width: float = value_font.get_char_size(48 + digit, value_font_size).x
		widest_digit = max(widest_digit, digit_width)
	return ceil(widest_digit)


func _get_character_cell_width(character: String) -> float:
	if character.length() == 1:
		var codepoint: int = character.unicode_at(0)
		if codepoint >= 48 and codepoint <= 57:
			return _digit_cell_width
	var value_font: Font = stat_value_template.get_theme_font("font")
	var value_font_size: int = stat_value_template.get_theme_font_size("font_size")
	return ceil(value_font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1.0, value_font_size).x)


func _ensure_value_cell_count(required_count: int) -> void:
	while _value_cells.size() < required_count:
		var value_cell: Label = stat_value_template.duplicate() as Label
		value_cell.name = "ValueCell%d" % _value_cells.size()
		value_cell.visible = true
		stat_value_container.add_child(value_cell)
		_value_cells.append(value_cell)
	while _value_cells.size() > required_count:
		var value_cell: Label = _value_cells.pop_back()
		value_cell.queue_free()


func set_frame_color(color: Color) -> void:
	if stat_background == null:
		if not is_node_ready():
			call_deferred("set_frame_color", color)
		return
	var color_material: ShaderMaterial = stat_background.material as ShaderMaterial
	if color_material != null:
		var panel_color: Color = color.darkened(0.9)
		panel_color.a = 0.9
		color_material.set_shader_parameter("panel_color", panel_color)
		color_material.set_shader_parameter("frame_color", color)
		color_material.set_shader_parameter("frame_highlight_color", color.lightened(0.35))
		color_material.set_shader_parameter("scanline_color", color.lightened(0.2))


func _update_background_size() -> void:
	if stat_background == null:
		return
	var color_material: ShaderMaterial = stat_background.material as ShaderMaterial
	if color_material != null:
		color_material.set_shader_parameter("panel_size", stat_background.size)


func set_warning_active(active: bool) -> void:
	if not is_node_ready():
		call_deferred("set_warning_active", active)
		return
	var next_active: bool = active and warning_flash_enabled
	if next_active == _warning_active:
		return
	_warning_active = next_active
	_warning_showing_color = false
	_warning_timer = max(warning_flash_interval, 0.001)
	_apply_warning_color()
	set_process(_warning_active)


func _apply_warning_color() -> void:
	var color: Color = warning_flash_color if _warning_showing_color else _normal_name_color
	stat_name_label.add_theme_color_override("font_color", color)

@tool
extends Control

class_name LMToastNotification

var _label: Label
var _panel: PanelContainer
var _tween: Tween

const DURATION: float = 3.0
const ANIMATION_DURATION: float = 0.3

const COLOR_SURFACE = Color("#1A202C")
const COLOR_STATUS_GREEN = Color("#22c55e")
const COLOR_BODY_TEXT = Color("#e2e8f0")

func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.0
	offset_left = -220
	offset_top = 20
	size_flags_horizontal = SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(440, 40)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.0
	_panel.offset_left = -220
	_panel.offset_top = 0
	_panel.size_flags_horizontal = SIZE_SHRINK_CENTER
	_panel.custom_minimum_size = Vector2(440, 40)

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(COLOR_STATUS_GREEN.r, COLOR_STATUS_GREEN.g, COLOR_STATUS_GREEN.b, 0.95)
	style_box.set_corner_radius_all(6)
	style_box.set_content_margin_all(10)

	var style = Theme.new()
	style.set_stylebox("panel", "PanelContainer", style_box)
	_panel.theme = style

	_label = Label.new()
	_label.text = "Entity definitions exported successfully!"
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.custom_minimum_size = Vector2(440, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_panel.add_child(_label)
	add_child(_panel)

	_panel.modulate.a = 0.0
	_animate_in()

func _animate_in() -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate:a", 1.0, ANIMATION_DURATION)
	_tween.tween_callback(_schedule_out)

func _schedule_out() -> void:
	await get_tree().create_timer(DURATION).timeout
	_animate_out()

func _animate_out() -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "modulate:a", 0.0, ANIMATION_DURATION)
	_tween.tween_callback(queue_free)

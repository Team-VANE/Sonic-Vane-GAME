extends Control
class_name CenterReticleDot

# SUMMARY:
# - Draws a simple center-screen dot for the UI reticle.
# - Exposes color, radius, and vertical offset settings.

var dot_color: Color = Color(1, 1, 1, 1)
var dot_radius: float = 3.0
var offset_y: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	_update_geometry()


func set_dot_color(value: Color) -> void:
	dot_color = value
	queue_redraw()


func set_dot_radius(value: float) -> void:
	dot_radius = max(value, 0.5)
	_update_geometry()


func set_offset_y(value: float) -> void:
	offset_y = value
	_update_geometry()


func _update_geometry() -> void:
	var size: Vector2 = Vector2.ONE * dot_radius * 2.0
	custom_minimum_size = size
	pivot_offset = size * 0.5
	offset_left = -size.x * 0.5
	offset_right = size.x * 0.5
	offset_top = -size.y * 0.5 + offset_y
	offset_bottom = size.y * 0.5 + offset_y
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = custom_minimum_size * 0.5
	draw_circle(center, dot_radius, dot_color)

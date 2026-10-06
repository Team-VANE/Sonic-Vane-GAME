extends Control

var deadzone_degrees: float = 15.0
var max_deviation_degrees: float = 90.0

@export var circle_radius: float = 40.0
@export var circle_color: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var deadzone_color: Color = Color(0.2, 0.6, 1.0, 0.6)
@export var active_zone_color: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var line_color: Color = Color(0.8, 0.8, 0.8, 1.0)
@export var arrow_color: Color = Color(0.2, 0.8, 0.4, 1.0)


func _ready() -> void:
	custom_minimum_size = Vector2(circle_radius * 4.0, circle_radius * 2.5)
	queue_redraw()


func set_deadzone(value_deg: float) -> void:
	deadzone_degrees = clamp(value_deg, 0.0, 180.0)
	queue_redraw()


func set_max_deviation(value_deg: float) -> void:
	max_deviation_degrees = clamp(value_deg, deadzone_degrees, 180.0)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.55)
	var r: float = circle_radius

	# Background circle
	draw_circle(center, r, active_zone_color)

	# Deadzone wedge (symmetrical around 0)
	var deadzone_rad: float = deg_to_rad(deadzone_degrees)
	var points: PackedVector2Array = PackedVector2Array()
	points.append(center)
	var segments: int = max(int(deadzone_degrees / 2.0), 3)
	for i in range(segments + 1):
		var angle: float = -deadzone_rad * 0.5 + (deadzone_rad * float(i) / float(segments))
		points.append(center + Vector2(sin(angle), -cos(angle)) * r)
	draw_colored_polygon(points, deadzone_color)

	# Max deviation arc lines
	var max_rad: float = deg_to_rad(max_deviation_degrees)
	var left_angle: float = -max_rad * 0.5
	var right_angle: float = max_rad * 0.5
	draw_line(center, center + Vector2(sin(left_angle), -cos(left_angle)) * r, line_color, 1.5)
	draw_line(center, center + Vector2(sin(right_angle), -cos(right_angle)) * r, line_color, 1.5)

	# Deadzone boundary lines
	var dz_left: float = -deadzone_rad * 0.5
	var dz_right: float = deadzone_rad * 0.5
	draw_dashed_line(center, center + Vector2(sin(dz_left), -cos(dz_left)) * r, line_color, 1.0, 4.0)
	draw_dashed_line(center, center + Vector2(sin(dz_right), -cos(dz_right)) * r, line_color, 1.0, 4.0)

	# Forward arrow (camera facing up)
	var arrow_tip: Vector2 = center + Vector2(0.0, -r * 0.7)
	var arrow_base: Vector2 = center + Vector2(0.0, -r * 0.3)
	draw_line(arrow_base, arrow_tip, arrow_color, 2.5)
	# Arrowhead
	var head_size: float = 6.0
	draw_line(arrow_tip, arrow_tip + Vector2(-head_size * 0.6, head_size), arrow_color, 2.0)
	draw_line(arrow_tip, arrow_tip + Vector2(head_size * 0.6, head_size), arrow_color, 2.0)

	# Labels
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	draw_string(font, center + Vector2(-r - 8.0, 4.0), str(int(deadzone_degrees)) + "°", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, line_color)

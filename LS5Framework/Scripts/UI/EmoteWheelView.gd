extends Control
class_name EmoteWheelView

const OUTER_RADIUS: float = 245.0
const INNER_RADIUS: float = 88.0

## Supplies the wheel labels and navigation text.
@export var label_font: Font

var options: Array[Dictionary] = []
var highlighted: int = -1
var heading: String = ""
var controller_active: bool = false
var feedback: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not label_font:
		label_font = ThemeDB.fallback_font


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	if not feedback.is_empty():
		_draw_centred(feedback, centre + Vector2(0.0, 10.0), 24, Color(0.8, 0.94, 1.0))
		return
	_draw_centred(heading, centre + Vector2(0.0, -282.0), 25, Color.WHITE)
	var count: int = options.size()
	if not count:
		return
	var step: float = TAU / float(count)
	for index: int in count:
		var angle: float = -PI * 0.5 + float(index) * step
		var points: PackedVector2Array = PackedVector2Array()
		var start: float = angle - step * 0.5 + 0.016
		var end: float = angle + step * 0.5 - 0.016
		for segment: int in 25:
			var arc_angle: float = lerpf(start, end, float(segment) / 24.0)
			points.append(centre + Vector2.from_angle(arc_angle) * OUTER_RADIUS)
		for segment: int in 25:
			var arc_angle: float = lerpf(end, start, float(segment) / 24.0)
			points.append(centre + Vector2.from_angle(arc_angle) * INNER_RADIUS)
		var fill: Color = Color(0.04, 0.1, 0.19, 0.88)
		if index == highlighted:
			fill = Color(0.08, 0.53, 0.83, 0.96)
		draw_colored_polygon(points, fill)
		points.append(points[0])
		draw_polyline(points, Color(0.43, 0.77, 1.0, 0.8), 2.0, true)
		var label_position: Vector2 = centre + Vector2.from_angle(angle) * 166.0
		var label: String = String(options[index].get("label", ""))
		if label == "Looking For Race":
			label = "LFR"
		_draw_centred(label, label_position + Vector2(0.0, 7.0), 20, Color.WHITE)
	draw_circle(centre, INNER_RADIUS - 5.0, Color(0.02, 0.06, 0.13, 0.9))
	var selected_label: String = String(options[highlighted].get("label", "")) if highlighted >= 0 else "Choose emote"
	var words: PackedStringArray = selected_label.split(" ")
	if label_font.get_string_size(selected_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > 150.0 and words.size() > 1:
		var split: int = ceili(float(words.size()) * 0.5)
		_draw_centred(" ".join(words.slice(0, split)), centre + Vector2(0.0, -3.0), 18, Color.WHITE)
		_draw_centred(" ".join(words.slice(split)), centre + Vector2(0.0, 19.0), 18, Color.WHITE)
	else:
		_draw_centred(selected_label, centre + Vector2(0.0, 7.0), 18, Color.WHITE)
	var hint: String = "Flick right stick  ·  LB / RB pages" if controller_active else "Left click select  ·  Mouse wheel pages"
	var cancel_hint: String = "B / LB + RB / D-pad right cancel" if controller_active else "Esc / Right click / G cancel"
	_draw_centred(hint, centre + Vector2(0.0, 284.0), 17, Color(0.8, 0.88, 1.0))
	_draw_centred(cancel_hint, centre + Vector2(0.0, 309.0), 16, Color(0.8, 0.88, 1.0))


func _draw_centred(text: String, baseline: Vector2, font_size: int, color: Color) -> void:
	var width: float = label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var position: Vector2 = baseline - Vector2(width * 0.5, 0.0)
	draw_string_outline(label_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.0, 0.02, 0.05, 0.9))
	draw_string(label_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

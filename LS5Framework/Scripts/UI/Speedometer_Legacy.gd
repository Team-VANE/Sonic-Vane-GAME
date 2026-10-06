extends Control

@export var arc_color: Color = Color(0.95, 0.95, 0.95, 0.9)
@export var border_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var needle_color_default: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var needle_gain_color: Color = Color(1.0, 0.15, 0.15, 1.0)
@export var needle_lose_color: Color = Color(0.15, 0.4, 1.0, 1.0)
@export var marker_color: Color = Color(1.0, 0.85, 0.2, 1.0)
@export var tick_color: Color = Color(0.7, 0.7, 0.7, 0.6)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.45)
## Width of the curved speedometer frame.
@export var arc_width: float = 14.0
## Additional width drawn behind the curved frame to define its outer edge.
@export var arc_border_extra_width: float = 5.0
## Color used to fill the curved frame with Barrier Blast charge.
@export var barrier_blast_color: Color = Color(0.05, 0.45, 1.0, 1.0)
@export var shadow_offset: Vector2 = Vector2(3.0, 3.0)
@export var marker_length: float = 12.0
@export var marker_width: float = 3.0
@export var base_radius: float = 8.0
@export var color_lerp_speed: float = 10.0
@export var gain_threshold: float = 10.0
@export var lose_threshold: float = 10.0
@export var tick_count: int = 5
@export var needle_width_fraction: float = 0.08
@export var needle_lerp_speed: float = 8.0

@export_group("Presentation")
## Padding between the dial and the speedometer frame.
@export_range(0.0, 80.0, 1.0, "or_greater", "suffix:px") var dial_padding: float = 14.0
## Vertical space reserved below the dial for the speed readout.
@export_range(0.0, 120.0, 1.0, "or_greater", "suffix:px") var readout_reserved_height: float = 54.0
## Vertical space reserved above the dial for the Barrier Blast label.
@export_range(0.0, 120.0, 1.0, "or_greater", "suffix:px") var barrier_header_reserved_height: float = 52.0
## Time taken by the Barrier Blast label to grow into view.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var barrier_label_enter_duration: float = 0.32
## Time taken by the Barrier Blast label to shrink out of view.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var barrier_label_exit_duration: float = 0.24
## Duration of one Barrier Blast label pulse.
@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:s") var barrier_label_pulse_duration: float = 0.72
## Scale reached by the Barrier Blast label during its pulse.
@export_range(1.0, 1.5, 0.01) var barrier_label_pulse_scale: float = 1.045
## Duration of one full-gauge white emissive cycle.
@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:s") var full_gauge_emissive_duration: float = 0.8
## Strength of the white emissive overlay at the peak of its cycle.
@export_range(0.0, 1.0, 0.01) var full_gauge_emissive_strength: float = 0.9

@export_group("Landing Readout Effects")
## Maximum vertical displacement of the failed landing-roll bounce.
@export_range(0.0, 40.0, 1.0, "or_greater", "suffix:px") var landing_failure_bounce_distance: float = 22.0
## Duration of the failed landing-roll bounce and red glow pulse.
@export_range(0.1, 2.0, 0.01, "or_greater", "suffix:s") var landing_failure_effect_duration: float = 0.34
## Maximum scale reached by the successful landing-roll pulse.
@export_range(1.0, 1.5, 0.01) var landing_success_pulse_scale: float = 1.18
## Duration of the successful landing-roll growth and white glow pulse.
@export_range(0.1, 2.0, 0.01, "or_greater", "suffix:s") var landing_success_effect_duration: float = 0.46
## Color reached when a correctly timed landing roll grants no speed benefit.
@export var landing_no_benefit_color: Color = Color(0.24, 0.24, 0.27, 0.58)
## Duration of the no-benefit landing-roll fade cycle.
@export_range(0.1, 2.0, 0.01, "or_greater", "suffix:s") var landing_no_benefit_effect_duration: float = 0.5

var _current_speed: float = 0.0
var _max_speed: float = 1.0
var _top_speed: float = 0.0
var _prev_speed: float = 0.0
var _needle_color: Color = needle_color_default
var _displayed_needle_angle: float = PI
var _barrier_blast_fraction: float = 0.0
var _barrier_blast_available: bool = false
var _full_gauge_emissive_elapsed: float = 0.0
var _frame_style: StyleBoxFlat = null
var _readout_style: StyleBoxFlat = null
var _barrier_label_transition_tween: Tween = null
var _barrier_label_pulse_tween: Tween = null
var _readout_motion_tween: Tween = null
var _readout_glow_tween: Tween = null
var _readout_base_position: Vector2 = Vector2.ZERO
var _primary_color: Color = Color.WHITE
var _secondary_color: Color = Color(0.05, 0.45, 1.0, 1.0)

## Holds the fixed current-speed, separator, and maximum-speed fields.
@onready var readout_text: Control = $ReadoutFrame/Margin/ReadoutEffect/ReadoutText
## Draws the landing feedback glow behind the fixed readout fields.
@onready var readout_glow: Control = $ReadoutFrame/Margin/ReadoutEffect/ReadoutGlow
## Displays the current speed in its fixed-width field.
@onready var current_speed_label: Label = $ReadoutFrame/Margin/ReadoutEffect/ReadoutText/Current
## Displays the maximum speed in its fixed-width field.
@onready var maximum_speed_label: Label = $ReadoutFrame/Margin/ReadoutEffect/ReadoutText/Maximum
## Displays the current speed in the glow layer.
@onready var current_speed_glow_label: Label = $ReadoutFrame/Margin/ReadoutEffect/ReadoutGlow/Current
## Displays the maximum speed in the glow layer.
@onready var maximum_speed_glow_label: Label = $ReadoutFrame/Margin/ReadoutEffect/ReadoutGlow/Maximum
## Isolates readout animation from the speedometer frame layout.
@onready var readout_effect: Control = $ReadoutFrame/Margin/ReadoutEffect
## Provides contrast behind the speedometer dial.
@onready var frame: PanelContainer = $Frame
## Frames the numeric speed readout.
@onready var readout_frame: PanelContainer = $ReadoutFrame
## Announces when Barrier Blast is available.
@onready var barrier_blast_label: Label = $BarrierBlastLabel


func _ready() -> void:
	_needle_color = needle_color_default
	_displayed_needle_angle = PI
	_prepare_styles()
	_apply_hud_colors()
	_set_barrier_blast_available(false, true)
	call_deferred("_center_readout_effect_pivots")
	set_process(false)


func _process(delta: float) -> void:
	if not _barrier_blast_available:
		return
	var cycle_duration: float = max(full_gauge_emissive_duration, 0.1)
	_full_gauge_emissive_elapsed = fposmod(
		_full_gauge_emissive_elapsed + max(delta, 0.0),
		cycle_duration
	)
	queue_redraw()


func set_speed(speed: float, max_speed_value: float, top_speed_value: float, delta: float = 0.0) -> void:
	_current_speed = max(speed, 0.0)
	_max_speed = max(max_speed_value, 0.001)
	_top_speed = max(top_speed_value, 0.0)
	# DEBUG: uncomment to verify values received by the speedometer
	# print("[Speedometer] received speed=%.2f max=%.2f top=%.2f t=%.3f" % [_current_speed, _max_speed, _top_speed, clamp(_current_speed / _max_speed, 0.0, 1.0)])
	var target_t: float = clamp(_current_speed / _max_speed, 0.0, 1.0)
	var target_angle: float = lerp(PI, 3.0 * PI / 2.0, target_t)
	if delta > 0.0:
		var speed_change_per_sec: float = (_current_speed - _prev_speed) / delta
		var target_color: Color = needle_color_default
		if speed_change_per_sec > gain_threshold:
			target_color = needle_gain_color
		elif speed_change_per_sec < -lose_threshold:
			target_color = needle_lose_color
		_needle_color = _needle_color.lerp(target_color, color_lerp_speed * delta)
		_displayed_needle_angle = lerp(_displayed_needle_angle, target_angle, needle_lerp_speed * delta)
	else:
		_displayed_needle_angle = target_angle
	_prev_speed = _current_speed
	if current_speed_label != null and maximum_speed_label != null:
		var current_text: String = str(int(_current_speed))
		var maximum_text: String = str(int(_max_speed))
		current_speed_label.text = current_text
		maximum_speed_label.text = maximum_text
		if current_speed_glow_label != null and maximum_speed_glow_label != null:
			current_speed_glow_label.text = current_text
			maximum_speed_glow_label.text = maximum_text
	queue_redraw()


func play_landing_roll_effect(
	successful: bool,
	strength: float,
	benefit_granted: bool
) -> void:
	if readout_text == null or readout_glow == null:
		return
	var effect_strength: float = clamp(strength, 0.0, 1.0)
	_reset_readout_effects()
	_center_readout_effect_pivots()
	if successful and benefit_granted:
		_play_landing_roll_success(effect_strength)
	elif successful:
		_play_landing_roll_no_benefit()
	else:
		_play_landing_roll_failure(effect_strength)


func _play_landing_roll_failure(strength: float) -> void:
	var duration: float = max(landing_failure_effect_duration, 0.1)
	var amplitude: float = max(landing_failure_bounce_distance, 0.0) * lerp(0.35, 1.0, strength)
	var base_y: float = _readout_base_position.y
	_readout_motion_tween = create_tween()
	_readout_motion_tween.tween_property(readout_effect, "position:y", base_y + amplitude, duration * 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_readout_motion_tween.tween_property(readout_effect, "position:y", base_y - amplitude * 0.58, duration * 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_readout_motion_tween.tween_property(readout_effect, "position:y", base_y + amplitude * 0.46, duration * 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_readout_motion_tween.tween_property(readout_effect, "position:y", base_y - amplitude * 0.28, duration * 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_readout_motion_tween.tween_property(readout_effect, "position:y", base_y + amplitude * 0.18, duration * 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_readout_motion_tween.tween_property(readout_effect, "position:y", base_y, duration * 0.32).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_start_readout_glow(Color(1.0, 0.08, 0.04, 1.0), duration, lerp(0.55, 1.0, strength))


func _play_landing_roll_success(strength: float) -> void:
	var duration: float = max(landing_success_effect_duration, 0.1)
	var peak_scale: float = lerp(1.04, max(landing_success_pulse_scale, 1.0), strength)
	_readout_motion_tween = create_tween()
	_readout_motion_tween.tween_property(readout_effect, "scale", Vector2.ONE * peak_scale, duration * 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_readout_motion_tween.tween_property(readout_effect, "scale", Vector2.ONE, duration * 0.58).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_start_readout_glow(Color.WHITE, duration, lerp(0.5, 1.0, strength))


func _play_landing_roll_no_benefit() -> void:
	var duration: float = max(landing_no_benefit_effect_duration, 0.1)
	_readout_motion_tween = create_tween()
	_readout_motion_tween.tween_property(
		readout_text,
		"modulate",
		landing_no_benefit_color,
		duration * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_readout_motion_tween.tween_property(
		readout_text,
		"modulate",
		Color.WHITE,
		duration * 0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_readout_glow(color: Color, duration: float, peak_alpha: float) -> void:
	for child: Node in readout_glow.get_children():
		if child is Label:
			(child as Label).add_theme_color_override("font_outline_color", color)
	readout_glow.modulate.a = 0.0
	_readout_glow_tween = create_tween()
	_readout_glow_tween.tween_property(readout_glow, "modulate:a", clamp(peak_alpha, 0.0, 1.0), duration * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_readout_glow_tween.tween_property(readout_glow, "modulate:a", 0.0, duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _reset_readout_effects() -> void:
	_kill_tween(_readout_motion_tween)
	_kill_tween(_readout_glow_tween)
	_readout_motion_tween = null
	_readout_glow_tween = null
	readout_effect.position = _readout_base_position
	readout_effect.scale = Vector2.ONE
	readout_text.modulate = Color.WHITE
	readout_glow.modulate.a = 0.0


func _center_readout_effect_pivots() -> void:
	if readout_effect != null:
		if _readout_motion_tween == null:
			_readout_base_position = readout_effect.position
		readout_effect.pivot_offset = readout_effect.size * 0.5


func set_barrier_blast_fraction(fraction: float) -> void:
	_barrier_blast_fraction = clamp(fraction, 0.0, 1.0)
	_set_barrier_blast_available(_barrier_blast_fraction >= 1.0)
	queue_redraw()


func set_hud_colors(primary_color: Color, secondary_color: Color) -> void:
	_primary_color = primary_color
	_secondary_color = secondary_color
	arc_color = primary_color
	border_color = primary_color.lightened(0.35)
	barrier_blast_color = secondary_color
	_apply_hud_colors()
	queue_redraw()


func _draw() -> void:
	var safe_padding: float = max(dial_padding, 0.0)
	var safe_readout_height: float = max(readout_reserved_height, 0.0)
	var safe_header_height: float = max(barrier_header_reserved_height, 0.0)
	var center: Vector2 = Vector2(
		size.x - safe_padding,
		size.y - safe_padding - safe_readout_height
	)
	var radius: float = min(
		size.x - safe_padding * 2.0,
		size.y - safe_padding * 2.0 - safe_readout_height - safe_header_height
	)
	if radius <= 1.0:
		return

	var arc_start_angle: float = PI
	var arc_end_angle: float = 3.0 * PI / 2.0
	var segments: int = 64

	var top_t: float = clamp(_top_speed / _max_speed, 0.0, 1.0)
	var marker_angle: float = lerp(arc_start_angle, arc_end_angle, top_t)

	_draw_pass(center + shadow_offset, radius, arc_start_angle, arc_end_angle, segments, _displayed_needle_angle, marker_angle, true)
	_draw_pass(center, radius, arc_start_angle, arc_end_angle, segments, _displayed_needle_angle, marker_angle, false)


func _draw_pass(center: Vector2, radius: float, start_angle: float, end_angle: float, segments: int, needle_angle: float, marker_angle: float, is_shadow: bool) -> void:
	var arc_col: Color = shadow_color if is_shadow else arc_color
	var border_col: Color = shadow_color if is_shadow else border_color
	var needle_col: Color = shadow_color if is_shadow else _needle_color
	var mark_col: Color = shadow_color if is_shadow else marker_color
	var tick_col: Color = shadow_color if is_shadow else tick_color

	var points: PackedVector2Array = _arc_points(center, radius, start_angle, end_angle, segments)
	if points.size() >= 2:
		draw_polyline(points, border_col, arc_width + arc_border_extra_width, true)
		draw_polyline(points, arc_col, arc_width, true)
		if not is_shadow and _barrier_blast_fraction > 0.0:
			var progress_end_angle: float = lerp(start_angle, end_angle, _barrier_blast_fraction)
			var progress_segments: int = max(1, int(ceil(float(segments) * _barrier_blast_fraction)))
			var progress_points: PackedVector2Array = _arc_points(
				center,
				radius,
				start_angle,
				progress_end_angle,
				progress_segments
			)
			if _barrier_blast_available:
				var emissive_pulse: float = _get_full_gauge_emissive_pulse()
				var glow_color: Color = Color(1.0, 1.0, 1.0, emissive_pulse * 0.28)
				draw_polyline(progress_points, glow_color, arc_width + 10.0, true)
				var emissive_color: Color = barrier_blast_color.lerp(
					Color.WHITE,
					emissive_pulse * clamp(full_gauge_emissive_strength, 0.0, 1.0)
				)
				draw_polyline(progress_points, emissive_color, arc_width, true)
			else:
				draw_polyline(progress_points, barrier_blast_color, arc_width, true)

	if not is_shadow:
		_draw_ticks(center, radius, start_angle, end_angle, tick_col)

	_draw_needle(center, radius, needle_angle, needle_col, is_shadow)
	_draw_marker(center, radius, marker_angle, mark_col, is_shadow)


func _arc_points(center: Vector2, radius: float, start_angle: float, end_angle: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var angle: float = lerp(start_angle, end_angle, t)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _draw_ticks(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color) -> void:
	if tick_count <= 1:
		return
	for i in range(tick_count):
		var t: float = float(i) / float(tick_count - 1)
		var angle: float = lerp(start_angle, end_angle, t)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var inner: Vector2 = center + direction * (radius - marker_length * 0.3)
		var outer: Vector2 = center + direction * (radius + arc_width * 0.5 + 1.0)
		draw_line(inner, outer, color, 1.5, true)


func _draw_needle(center: Vector2, radius: float, angle: float, color: Color, is_shadow: bool) -> void:
	var direction: Vector2 = Vector2(cos(angle), sin(angle))
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
	var tip: Vector2 = center + direction * radius * 0.92
	var base_center: Vector2 = center - direction * radius * 0.08
	var half_width: float = radius * needle_width_fraction * 0.5
	var base_left: Vector2 = base_center + perpendicular * half_width
	var base_right: Vector2 = base_center - perpendicular * half_width
	var polygon: PackedVector2Array = PackedVector2Array([base_left, tip, base_right])
	draw_colored_polygon(polygon, color)
	if not is_shadow:
		draw_circle(center, base_radius, color)


func _draw_marker(center: Vector2, radius: float, angle: float, color: Color, is_shadow: bool) -> void:
	var direction: Vector2 = Vector2(cos(angle), sin(angle))
	var inner: Vector2 = center + direction * (radius - marker_length * 0.5)
	var outer: Vector2 = center + direction * (radius + arc_width * 0.5 + 3.0)
	draw_line(inner, outer, color, marker_width, true)


func _prepare_styles() -> void:
	_frame_style = _duplicate_panel_style(frame)
	_readout_style = _duplicate_panel_style(readout_frame)


func _duplicate_panel_style(panel: PanelContainer) -> StyleBoxFlat:
	if panel == null:
		return null
	var configured_style: StyleBox = panel.get_theme_stylebox("panel")
	if not (configured_style is StyleBoxFlat):
		return null
	var duplicated_style: StyleBoxFlat = configured_style.duplicate() as StyleBoxFlat
	panel.add_theme_stylebox_override("panel", duplicated_style)
	return duplicated_style


func _apply_hud_colors() -> void:
	var primary_foreground: Color = _primary_color.lightened(0.38)
	var barrier_foreground: Color = _secondary_color.lightened(0.28)
	if _frame_style != null:
		_frame_style.border_color = _primary_color
	if _readout_style != null:
		_readout_style.border_color = primary_foreground
	if readout_text != null:
		for child: Node in readout_text.get_children():
			if child is Label:
				(child as Label).add_theme_color_override("font_color", primary_foreground)
	if barrier_blast_label != null:
		barrier_blast_label.add_theme_color_override("font_color", barrier_foreground)


func _set_barrier_blast_available(available: bool, immediate: bool = false) -> void:
	if _barrier_blast_available == available and not immediate:
		return
	_barrier_blast_available = available
	_kill_tween(_barrier_label_transition_tween)
	_kill_tween(_barrier_label_pulse_tween)
	_barrier_label_transition_tween = null
	_barrier_label_pulse_tween = null
	if available:
		_full_gauge_emissive_elapsed = 0.0
		set_process(true)
		_show_barrier_blast_label(immediate)
		return
	_full_gauge_emissive_elapsed = 0.0
	set_process(false)
	_hide_barrier_blast_label(immediate)
	queue_redraw()


func _show_barrier_blast_label(immediate: bool) -> void:
	if barrier_blast_label == null:
		return
	barrier_blast_label.visible = true
	UIExcitementEffects.set_center_pivot(barrier_blast_label)
	if immediate or barrier_label_enter_duration <= 0.0:
		barrier_blast_label.scale = Vector2.ONE
		barrier_blast_label.modulate.a = 1.0
		_start_barrier_label_pulse()
		return
	_barrier_label_transition_tween = UIExcitementEffects.pulse_in(
		barrier_blast_label,
		barrier_label_enter_duration,
		0.2,
		1.12
	)
	if _barrier_label_transition_tween != null:
		_barrier_label_transition_tween.tween_callback(_start_barrier_label_pulse)


func _hide_barrier_blast_label(immediate: bool) -> void:
	if barrier_blast_label == null:
		return
	if immediate or not barrier_blast_label.visible or barrier_label_exit_duration <= 0.0:
		barrier_blast_label.visible = false
		barrier_blast_label.scale = Vector2.ZERO
		barrier_blast_label.modulate.a = 0.0
		return
	_barrier_label_transition_tween = create_tween()
	_barrier_label_transition_tween.set_parallel(true)
	_barrier_label_transition_tween.tween_property(
		barrier_blast_label,
		"scale",
		Vector2.ZERO,
		barrier_label_exit_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_barrier_label_transition_tween.tween_property(
		barrier_blast_label,
		"modulate:a",
		0.0,
		barrier_label_exit_duration * 0.8
	)
	_barrier_label_transition_tween.set_parallel(false)
	_barrier_label_transition_tween.tween_callback(barrier_blast_label.hide)


func _start_barrier_label_pulse() -> void:
	if not _barrier_blast_available or barrier_blast_label == null:
		return
	_kill_tween(_barrier_label_pulse_tween)
	barrier_blast_label.scale = Vector2.ONE
	var pulse_duration: float = max(barrier_label_pulse_duration, 0.1)
	_barrier_label_pulse_tween = create_tween().set_loops()
	_barrier_label_pulse_tween.tween_property(
		barrier_blast_label,
		"scale",
		Vector2.ONE * max(barrier_label_pulse_scale, 1.0),
		pulse_duration * 0.42
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_barrier_label_pulse_tween.tween_property(
		barrier_blast_label,
		"scale",
		Vector2.ONE,
		pulse_duration * 0.58
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _get_full_gauge_emissive_pulse() -> float:
	if not _barrier_blast_available:
		return 0.0
	var cycle_duration: float = max(full_gauge_emissive_duration, 0.1)
	var cycle_ratio: float = _full_gauge_emissive_elapsed / cycle_duration
	return 0.5 - cos(cycle_ratio * TAU) * 0.5


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()

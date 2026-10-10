class_name TrickUI
extends Control

enum ResultPhase {
	NONE,
	RATING,
	FINAL_SCORE
}

@onready var _active_container: Control = $ActiveContainer
@onready var _score_label: Label = $ActiveContainer/ScoreLabel
@onready var _timer_bar: Control = $ActiveContainer/TimerBar
@onready var _timer_warning_border: Panel = $ActiveContainer/TimerBar/WarningBorder
@onready var _timer_glow: ColorRect = $ActiveContainer/TimerBar/Glow
@onready var _timer_fill: ColorRect = $ActiveContainer/TimerBar/Fill
@onready var _history_labels: Array[Label] = [
	$ActiveContainer/TrickHistory/OldestLabel,
	$ActiveContainer/TrickHistory/MiddleLabel,
	$ActiveContainer/TrickHistory/NewestLabel
]
@onready var _result_container: Control = $ResultContainer
@onready var _rating_label: Label = $ResultContainer/RatingLabel
@onready var _final_score_label: Label = $ResultContainer/FinalScoreLabel

const RESULT_RATING_LINGER: float = 0.7
const RESULT_SCORE_LINGER: float = 2.2
const RESULT_FADE_DURATION: float = 0.55
const RESULT_OVERLAP_OFFSET: float = 132.0
const FAILURE_DURATION: float = 1.0
const JITTER_DURATION: float = 0.55
const JITTER_STRENGTH: float = 8.0

var _presentation_profile: PlayerCharacterVisualProfile = null
var _display_score: float = 0.0
var _target_score: float = 0.0
var _target_history: Array[String] = []
var _combo_active: bool = false
var _timer_ratio: float = 0.0
var _timer_warning_phase: float = 0.0
var _failure_timer: float = 0.0
var _empty_combo_fade_remaining: float = 0.0
var _jitter_timer: float = 0.0
var _is_hurt: bool = false
var _pause_hidden: bool = false
var _combo_system_enabled: bool = true
var _last_history_width: float = 0.0
var _active_base_position: Vector2 = Vector2.ZERO
var _result_base_position: Vector2 = Vector2.ZERO
var _result_phase: ResultPhase = ResultPhase.NONE
var _result_score: float = 0.0
var _result_score_linger: float = 0.0
var _result_fade_remaining: float = 0.0
var _result_sequence_tween: Tween = null
var _result_rotation_tween: Tween = null
var _result_move_tween: Tween = null
var _final_score_tween: Tween = null

func _ready() -> void:
	visible = false
	_active_container.visible = false
	_result_container.visible = false
	_active_container.modulate.a = 1.0
	_result_container.modulate.a = 1.0
	call_deferred("_initialize_layout")

func _initialize_layout() -> void:
	_active_base_position = _active_container.position
	_result_base_position = _result_container.position
	UIExcitementEffects.set_center_pivot(_score_label)
	UIExcitementEffects.set_center_pivot(_rating_label)
	UIExcitementEffects.set_center_pivot(_final_score_label)
	_layout_timer_fill()
	_refresh_visibility()

func _process(delta: float) -> void:
	if _pause_hidden or not SettingsManager.hud_visible:
		visible = false
		return
	_update_display_score(delta)
	_update_timer_warning(delta)
	_update_failure(delta)
	_update_empty_combo_fade(delta)
	_update_result(delta)
	_refresh_layout()
	_refresh_visibility()

func set_character_presentation_profile(profile: PlayerCharacterVisualProfile) -> void:
	_presentation_profile = profile

func update_trick_display(score: float, trick_list: String) -> void:
	var lines: Array[String] = []
	if not trick_list.is_empty():
		for line: String in trick_list.split(" + ", false):
			lines.append(line)
	update_combo_display(score, lines)

func update_combo_display(score: float, history: Array[String]) -> void:
	if _is_hurt:
		if history.is_empty() and score <= 0.0:
			return
		_cancel_failure_state()
	_target_score = maxf(score, 0.0)
	_target_history.assign(history)
	if history.is_empty() and score <= 0.0:
		_combo_active = false
		_set_history_lines()
		_refresh_visibility()
		return
	_combo_active = true
	_cancel_empty_combo_fade()
	_active_container.modulate.a = 1.0
	_set_active_text_color(Color.WHITE)
	_set_history_lines()
	_move_result_for_overlap(true)
	_refresh_visibility()

func update_combo_timer(time_remaining: float, maximum_time: float) -> void:
	if _is_hurt:
		if time_remaining <= 0.0:
			_timer_ratio = 0.0
			_layout_timer_fill()
			return
		_cancel_failure_state()
	_timer_ratio = clampf(time_remaining / maximum_time if maximum_time > 0.0 else 0.0, 0.0, 1.0)
	if time_remaining > 0.0:
		_cancel_empty_combo_fade()
		_combo_active = true
	_layout_timer_fill()
	_refresh_visibility()

func finish_combo(score: float, history: Array[String]) -> void:
	_cancel_failure_state()
	_cancel_empty_combo_fade()
	_target_history.assign(history)
	_combo_active = false
	_timer_ratio = 0.0
	_layout_timer_fill()
	if score <= 0.0:
		_cancel_result_sequence()
		_target_score = 0.0
		_display_score = 0.0
		_score_label.text = "0"
		_set_history_lines()
		_empty_combo_fade_remaining = RESULT_FADE_DURATION
	else:
		_start_result_sequence(score)
	_refresh_visibility()

func fail_combo(_score: float, history: Array[String]) -> void:
	_cancel_empty_combo_fade()
	_cancel_result_sequence()
	_target_score = 0.0
	_display_score = 0.0
	_score_label.text = "0"
	_target_history.assign(history)
	_combo_active = false
	_timer_ratio = 0.0
	_failure_timer = FAILURE_DURATION
	_jitter_timer = JITTER_DURATION
	_is_hurt = true
	_active_container.position = _active_base_position
	_active_container.modulate.a = 1.0
	_set_active_text_color(Color(1.0, 0.08, 0.08, 1.0))
	_set_history_lines()
	_layout_timer_fill()
	_refresh_visibility()

func set_pause_hidden(hidden: bool) -> void:
	_pause_hidden = hidden
	_refresh_visibility()

func set_combo_system_enabled(enabled: bool) -> void:
	_combo_system_enabled = enabled
	modulate.a = 1.0
	_refresh_visibility()

func _start_result_sequence(score: float) -> void:
	_cancel_result_sequence()
	_result_phase = ResultPhase.RATING
	_result_score = score
	_result_container.visible = true
	_result_container.modulate = Color.WHITE
	_result_score_linger = 0.0
	_result_fade_remaining = 0.0
	_final_score_label.visible = false
	_final_score_label.text = "SCORE: %d" % int(score)
	var rating: Dictionary = _get_rating(score)
	_rating_label.text = String(rating.get("text", "Nice!"))
	var score_color: Color = _get_score_color(score)
	_rating_label.add_theme_color_override("font_color", score_color)
	_final_score_label.add_theme_color_override("font_color", score_color)
	_rating_label.visible = true
	_rating_label.scale = Vector2.ZERO
	_rating_label.rotation = -TAU
	_rating_label.modulate.a = 1.0
	UIExcitementEffects.set_center_pivot(_rating_label)
	_move_result_for_overlap(false)

	_result_sequence_tween = create_tween()
	_result_sequence_tween.tween_property(
		_rating_label,
		"scale",
		Vector2.ONE * 1.14,
		0.34
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_result_sequence_tween.tween_property(
		_rating_label,
		"scale",
		Vector2.ONE,
		0.14
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_result_sequence_tween.tween_interval(RESULT_RATING_LINGER)
	_result_sequence_tween.tween_callback(_show_final_score.bind(score))

	_result_rotation_tween = create_tween()
	_result_rotation_tween.tween_property(
		_rating_label,
		"rotation",
		0.0,
		0.48
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _show_final_score(score: float) -> void:
	_result_sequence_tween = null
	_result_rotation_tween = null
	if _result_phase != ResultPhase.RATING:
		return
	_result_phase = ResultPhase.FINAL_SCORE
	_rating_label.visible = false
	_final_score_label.text = "SCORE: %d" % int(score)
	_final_score_label.add_theme_color_override("font_color", _get_score_color(score))
	_final_score_label.visible = true
	_final_score_label.modulate = Color.WHITE
	_result_score_linger = RESULT_SCORE_LINGER
	_result_fade_remaining = RESULT_FADE_DURATION
	_final_score_tween = UIExcitementEffects.pulse_in(_final_score_label, 0.38, 0.0, 1.1)

func _cancel_result_sequence() -> void:
	_kill_tween(_result_sequence_tween)
	_kill_tween(_result_rotation_tween)
	_kill_tween(_result_move_tween)
	_kill_tween(_final_score_tween)
	_result_sequence_tween = null
	_result_rotation_tween = null
	_result_move_tween = null
	_final_score_tween = null
	_result_phase = ResultPhase.NONE
	_result_score = 0.0
	_result_score_linger = 0.0
	_result_fade_remaining = 0.0
	_result_container.visible = false
	_result_container.modulate = Color.WHITE
	_rating_label.visible = false
	_final_score_label.visible = false
	_result_container.position = _result_base_position

func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()

func _move_result_for_overlap(animated: bool) -> void:
	if _result_phase == ResultPhase.NONE:
		return
	var target_position: Vector2 = _result_base_position
	if _combo_active:
		target_position.y -= RESULT_OVERLAP_OFFSET
	_kill_tween(_result_move_tween)
	_result_move_tween = null
	if not animated:
		_result_container.position = target_position
		return
	_result_move_tween = create_tween()
	_result_move_tween.tween_property(
		_result_container,
		"position",
		target_position,
		0.24
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

func _update_result(delta: float) -> void:
	if _result_phase != ResultPhase.NONE:
		var score_color: Color = _get_score_color(_result_score)
		_rating_label.add_theme_color_override("font_color", score_color)
		_final_score_label.add_theme_color_override("font_color", score_color)
	if _result_phase != ResultPhase.FINAL_SCORE:
		return
	if _result_score_linger > 0.0:
		_result_score_linger = maxf(_result_score_linger - delta, 0.0)
		return
	_result_fade_remaining = maxf(_result_fade_remaining - delta, 0.0)
	_result_container.modulate.a = clampf(
		_result_fade_remaining / RESULT_FADE_DURATION,
		0.0,
		1.0
	)
	if _result_fade_remaining <= 0.0:
		_cancel_result_sequence()

func _update_display_score(delta: float) -> void:
	_display_score = lerpf(_display_score, _target_score, clampf(delta * 12.0, 0.0, 1.0))
	if absf(_display_score - _target_score) < 0.5:
		_display_score = _target_score
	_score_label.text = str(int(roundf(_display_score)))
	if not _is_hurt:
		_score_label.add_theme_color_override("font_color", _get_score_color(_display_score))

func _update_timer_warning(delta: float) -> void:
	if _timer_warning_border == null:
		return
	if not _combo_active or _timer_ratio > 0.5 or _timer_ratio <= 0.0:
		_timer_warning_phase = 0.0
		_timer_warning_border.modulate.a = 0.0
		return
	var urgency: float = clampf(1.0 - (_timer_ratio / 0.5), 0.0, 1.0)
	var flashes_per_second: float = lerpf(1.75, 11.0, urgency * urgency)
	_timer_warning_phase = fmod(_timer_warning_phase + delta * flashes_per_second * TAU, TAU)
	var pulse: float = (sin(_timer_warning_phase) + 1.0) * 0.5
	_timer_warning_border.modulate.a = lerpf(0.28, 1.0, pulse * pulse)

func _update_failure(delta: float) -> void:
	if not _is_hurt:
		return
	_failure_timer = maxf(_failure_timer - delta, 0.0)
	_jitter_timer = maxf(_jitter_timer - delta, 0.0)
	if _jitter_timer > 0.0:
		var offset: Vector2 = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * JITTER_STRENGTH
		_active_container.position = _active_base_position + offset
	else:
		_active_container.position = _active_base_position
	_active_container.modulate.a = clampf(_failure_timer / FAILURE_DURATION, 0.0, 1.0)
	if _failure_timer <= 0.0:
		_cancel_failure_state()

func _cancel_failure_state() -> void:
	_failure_timer = 0.0
	_jitter_timer = 0.0
	_is_hurt = false
	_active_container.position = _active_base_position
	_active_container.modulate.a = 1.0
	_set_active_text_color(Color.WHITE)

func _update_empty_combo_fade(delta: float) -> void:
	if _empty_combo_fade_remaining <= 0.0:
		return
	_empty_combo_fade_remaining = maxf(_empty_combo_fade_remaining - delta, 0.0)
	_active_container.modulate.a = _empty_combo_fade_remaining / RESULT_FADE_DURATION

func _cancel_empty_combo_fade() -> void:
	_empty_combo_fade_remaining = 0.0
	_active_container.modulate.a = 1.0

func _get_rating(score: float) -> Dictionary:
	if _presentation_profile != null:
		var profile_rating: Dictionary = _presentation_profile.get_combo_rating(score)
		if not String(profile_rating.get("text", "")).is_empty():
			return profile_rating
	var fallback_thresholds: PackedFloat32Array = PackedFloat32Array([
		1.0, 400.0, 800.0, 1600.0, 2400.0, 4000.0, 8000.0, 12000.0, 25000.0, 50000.0
	])
	var fallback_texts: PackedStringArray = PackedStringArray([
		"Good!", "Great!", "Nice!", "Jammin'!", "Cool!", "Radical!", "Tight!", "Awesome!", "Extreme!", "Perfect!"
	])
	var selected_tier: int = 0
	for tier_index: int in range(fallback_thresholds.size()):
		if score < fallback_thresholds[tier_index]:
			break
		selected_tier = tier_index
	return {
		"text": fallback_texts[selected_tier],
		"tier": selected_tier,
		"tier_count": fallback_texts.size()
	}

func _get_score_color(score: float) -> Color:
	if _is_perfect_score(score):
		var hue: float = fmod(float(Time.get_ticks_msec()) / 1800.0, 1.0)
		return Color.from_hsv(hue, 0.88, 1.0, 1.0)
	if _presentation_profile != null:
		return _presentation_profile.get_combo_rating_color(score)
	var fallback_thresholds: PackedFloat32Array = PackedFloat32Array([
		1.0, 400.0, 800.0, 1600.0, 2400.0, 4000.0, 8000.0, 12000.0, 25000.0, 50000.0
	])
	var fallback_colors: PackedColorArray = PackedColorArray([
		Color(0.08, 0.66, 1.0, 1.0), Color(0.0, 0.9, 0.86, 1.0),
		Color(0.2, 1.0, 0.38, 1.0), Color(0.94, 1.0, 0.2, 1.0),
		Color(1.0, 0.78, 0.08, 1.0), Color(1.0, 0.48, 0.08, 1.0),
		Color(1.0, 0.25, 0.08, 1.0), Color(1.0, 0.12, 0.42, 1.0),
		Color(1.0, 0.08, 0.9, 1.0), Color(1.0, 0.08, 0.9, 1.0)
	])
	if score <= fallback_thresholds[0]:
		return fallback_colors[0]
	for tier_index: int in range(fallback_thresholds.size() - 1):
		var lower_score: float = fallback_thresholds[tier_index]
		var upper_score: float = fallback_thresholds[tier_index + 1]
		if score < upper_score:
			var blend: float = inverse_lerp(lower_score, upper_score, score)
			return fallback_colors[tier_index].lerp(fallback_colors[tier_index + 1], blend)
	return fallback_colors[fallback_colors.size() - 1]

func _is_perfect_score(score: float) -> bool:
	if _presentation_profile != null and not _presentation_profile.combo_rating_score_thresholds.is_empty():
		return score >= _presentation_profile.combo_rating_score_thresholds[-1]
	return score >= 50000.0

func _set_history_lines() -> void:
	var wrapped_lines: Array[String] = _wrap_history_entries(_target_history)
	for index: int in range(_history_labels.size()):
		var source_index: int = wrapped_lines.size() - _history_labels.size() + index
		_history_labels[index].text = wrapped_lines[source_index] if source_index >= 0 else ""

func _wrap_history_entries(entries: Array[String]) -> Array[String]:
	var wrapped_lines: Array[String] = []
	if entries.is_empty():
		return wrapped_lines
	var newest_label: Label = _history_labels[_history_labels.size() - 1]
	var font: Font = newest_label.get_theme_font("font")
	var font_size: int = newest_label.get_theme_font_size("font_size")
	var maximum_width: float = maxf(_active_container.size.x - 36.0, 1.0)
	var current_line: String = ""
	for entry: String in entries:
		var candidate: String = entry if current_line.is_empty() else current_line + "  •  " + entry
		if not current_line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > maximum_width:
			wrapped_lines.append(current_line)
			current_line = entry
		else:
			current_line = candidate
	if not current_line.is_empty():
		wrapped_lines.append(current_line)
	return wrapped_lines

func _refresh_layout() -> void:
	_layout_timer_fill()
	if not is_equal_approx(_last_history_width, _active_container.size.x):
		_last_history_width = _active_container.size.x
		_set_history_lines()

func _layout_timer_fill() -> void:
	if _timer_bar == null or _timer_fill == null or _timer_glow == null:
		return
	var fill_width: float = maxf(_timer_bar.size.x * _timer_ratio, 0.0)
	var fill_left: float = (_timer_bar.size.x - fill_width) * 0.5
	_timer_fill.position.x = fill_left
	_timer_fill.size.x = fill_width
	_timer_glow.position.x = fill_left - 3.0
	_timer_glow.size.x = fill_width + 6.0 if fill_width > 0.0 else 0.0

func _set_active_text_color(color: Color) -> void:
	var score_color: Color = color
	if color == Color.WHITE:
		score_color = _get_score_color(_display_score)
	_score_label.add_theme_color_override("font_color", score_color)
	var history_alphas: Array[float] = [0.18, 0.5, 1.0]
	for index: int in range(_history_labels.size()):
		var label_color: Color = color
		label_color.a *= history_alphas[index]
		_history_labels[index].add_theme_color_override("font_color", label_color)

func _refresh_visibility() -> void:
	var hud_allowed: bool = _combo_system_enabled and not _pause_hidden and SettingsManager.hud_visible
	var active_visible: bool = hud_allowed and (_combo_active or _is_hurt or _empty_combo_fade_remaining > 0.0)
	var result_visible: bool = hud_allowed and _result_phase != ResultPhase.NONE
	_active_container.visible = active_visible
	_result_container.visible = result_visible
	visible = active_visible or result_visible

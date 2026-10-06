@tool
extends Control
class_name LipSyncTimeline

signal playhead_changed(time_sec: float)
signal cue_selected(cue: LipSyncCue, expression: bool)
signal cue_modified
signal add_requested(expression: bool, time_sec: float, row: int)
signal delete_requested
signal edit_started
signal edit_cancelled
signal selection_changed
signal selection_status(message: String)

const RULER_BOTTOM: float = 30.0
const WAVE_BOTTOM: float = 165.0
const WORD_BOTTOM: float = 200.0
const VISEME_ROW_BOTTOM: float = 246.0
const ROW_HEIGHT: float = 46.0
const VISEME_BOTTOM: float = WORD_BOTTOM + ROW_HEIGHT * LipSyncCue.ROW_COUNT
const EXPRESSION_BOTTOM: float = VISEME_BOTTOM + ROW_HEIGHT * LipSyncCue.ROW_COUNT
const MIN_AUDIBLE_SPAN: float = 0.02
const WAVEFORM_SCRIPT: Script = preload("res://addons/ls5_lipsync/editor/lip_sync_waveform.gd")

var clip: LipSyncClip
var waveform: PackedFloat32Array = PackedFloat32Array():
	set(value):
		waveform = value
		_waveform_reload_pending = waveform.is_empty()
		queue_redraw()
var _waveform_message: String = ""
var _waveform_reload_pending: bool = true
var _waveform_stream: AudioStream
var playhead: float = 0.0
var pixels_per_second: float = 180.0
var snap_step: float = 0.01
var scroll_seconds: float = 0.0
var selected_cue: LipSyncCue
var selected_expression: bool = false
var selected_cues: Array[LipSyncCue] = []
var selected_words: Array[Dictionary] = []
var active_word: Dictionary = {}
var _box_anchor: Vector2 = Vector2.ZERO
var _box_cursor: Vector2 = Vector2.ZERO
var _selection_operation: int = 0
var _selection_before_cues: Array[LipSyncCue] = []
var _selection_before_words: Array[Dictionary] = []
var _selection_before_active_cue: LipSyncCue
var _selection_before_active_word: Dictionary = {}
var _drag_entries: Array[Dictionary] = []
var _drag_backup: Dictionary = {}
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_original_row: int = 0
var _drag_changed: bool = false
var _drag_moved: bool = false
var _collapse_on_click: bool = false
var _move_warning: String = ""
var _drag_mode: String = ""
var _drag_anchor: float = 0.0
var _drag_start: float = 0.0
var _drag_end: float = 0.0
var _drag_blend_start: float = 0.0
var _drag_strength_start: float = 0.0
var _drag_button: int = 0
var _word_index: int = -1


func _ready() -> void:
	set_process(true)
	custom_minimum_size = Vector2(360.0, EXPRESSION_BOTTOM + 8.0)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_window().focus_exited.connect(_cancel_drag)
	tooltip_text = "Click or box-drag to select cues and words. Shift adds; Ctrl subtracts. Drag selected bodies to move the group. Right-drag vertically for strength or horizontally for blending. The initial click's half selects blend-in or blend-out. B toggles maximum blend lock for selected cues. Escape cancels a drag or clears selection. Ctrl+wheel zooms."


func _process(_delta: float) -> void:
	if clip and clip.audio and (_waveform_reload_pending or clip.audio != _waveform_stream):
		refresh_waveform()
	if not _drag_mode.is_empty() and _drag_button > 0 and not Input.is_mouse_button_pressed(_drag_button):
		_finish_drag()


func set_clip(next_clip: LipSyncClip, peaks: PackedFloat32Array = PackedFloat32Array()) -> void:
	clip = next_clip
	_waveform_message = ""
	_waveform_stream = clip.audio if clip else null
	waveform = peaks
	if clip and clip.audio and waveform.is_empty():
		refresh_waveform()
	clear_selection()
	_drag_mode = ""
	_drag_button = 0
	_drag_entries.clear()
	_drag_backup.clear()
	_selection_before_cues.clear()
	_selection_before_words.clear()
	_selection_before_active_cue = null
	_selection_before_active_word = {}
	playhead = 0.0
	scroll_seconds = 0.0
	if clip:
		pixels_per_second = clampf((size.x - 24.0) / maxf(clip.get_timeline_length(), 0.5), 75.0, 360.0)
		normalize_audible_range()
	queue_redraw()


func refresh_waveform() -> void:
	var analysis: Dictionary = WAVEFORM_SCRIPT.analyze(clip.audio if clip else null)
	waveform = analysis["peaks"]
	_waveform_message = String(analysis.get("reason", "Waveform unavailable."))
	_waveform_stream = clip.audio if clip else null
	_waveform_reload_pending = false
	queue_redraw()


func normalize_audible_range() -> void:
	if not clip or not clip.audio:
		return
	var duration: float = maxf(0.0, clip.audio.get_length())
	var minimum_span: float = minf(MIN_AUDIBLE_SPAN, duration)
	if clip.audible_start < 0.0 or clip.audible_start >= duration or clip.audible_end <= clip.audible_start:
		clip.audible_start = 0.0
		clip.audible_end = duration
	else:
		clip.audible_start = clampf(clip.audible_start, 0.0, duration - minimum_span)
		clip.audible_end = clampf(clip.audible_end, clip.audible_start + minimum_span, duration)
	queue_redraw()


func cancel_audible_drag() -> void:
	if _drag_mode == "audible_start" or _drag_mode == "audible_end":
		_finish_drag()


func set_playhead(time_sec: float, notify: bool = true) -> void:
	playhead = clampf(time_sec, 0.0, _timeline_length())
	if notify:
		playhead_changed.emit(playhead)
	queue_redraw()


func is_scrubbing() -> bool:
	return _drag_mode == "playhead"


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	draw_rect(Rect2(Vector2.ZERO, size), Color("252b31"))
	draw_rect(Rect2(0.0, RULER_BOTTOM, size.x, WAVE_BOTTOM - RULER_BOTTOM), Color("171c20"))
	draw_rect(Rect2(0.0, WAVE_BOTTOM, size.x, WORD_BOTTOM - WAVE_BOTTOM), Color("303e48"))
	for row: int in range(LipSyncCue.ROW_COUNT):
		draw_rect(Rect2(0.0, WORD_BOTTOM + float(row) * ROW_HEIGHT, size.x, ROW_HEIGHT), Color("233946") if row % 2 == 0 else Color("294250"))
		draw_rect(Rect2(0.0, VISEME_BOTTOM + float(row) * ROW_HEIGHT, size.x, ROW_HEIGHT), Color("433443") if row % 2 == 0 else Color("503a50"))
	if not clip:
		draw_string(font, Vector2(18.0, 55.0), "Select a lip sync clip to edit.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)
		return
	var first_second: int = maxi(0, floori(scroll_seconds))
	var last_second: int = ceili(scroll_seconds + size.x / pixels_per_second)
	for second: int in range(first_second, last_second + 1):
		var x: float = _time_x(float(second))
		draw_line(Vector2(x, 0.0), Vector2(x, EXPRESSION_BOTTOM), Color(1.0, 1.0, 1.0, 0.12), 1.0)
		draw_string(font, Vector2(x + 4.0, 19.0), "%d s" % second, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size - 2, Color("c4d0d6"))
	_draw_waveform()
	_draw_words(font, font_size)
	_draw_cues(clip.viseme_cues, Color("3299d1"), false, font, font_size)
	_draw_cues(clip.expression_cues, Color("b476bf"), true, font, font_size)
	draw_string(font, Vector2(8.0, WORD_BOTTOM - 9.0), "WORDS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size - 3, Color("c4d0d6"))
	for row: int in range(LipSyncCue.ROW_COUNT):
		draw_string(font, Vector2(8.0, WORD_BOTTOM + float(row + 1) * ROW_HEIGHT - 9.0), "VIS %d" % (row + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size - 3, Color("d6ebf6"))
		draw_string(font, Vector2(8.0, VISEME_BOTTOM + float(row + 1) * ROW_HEIGHT - 9.0), "EXP %d" % (row + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size - 3, Color("f3dcf4"))
	var head_x: float = _time_x(playhead)
	draw_line(Vector2(head_x, 0.0), Vector2(head_x, EXPRESSION_BOTTOM), Color("ffdc6b"), 2.0)
	if _drag_mode == "box" and _drag_moved:
		var box: Rect2 = Rect2(_box_anchor, _box_cursor - _box_anchor).abs()
		draw_rect(box, Color(0.6, 0.8, 1.0, 0.16))
		draw_rect(box, Color("b9dfff"), false, 1.0)
	if not _move_warning.is_empty():
		draw_string(font, Vector2(12.0, 53.0), _move_warning, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, font_size, Color("ffbf75"))


func _draw_waveform() -> void:
	var duration: float = clip.audio.get_length() if clip.audio else 0.0
	var middle: float = (RULER_BOTTOM + WAVE_BOTTOM) * 0.5
	var half_height: float = (WAVE_BOTTOM - RULER_BOTTOM) * 0.45
	if waveform.is_empty() or duration <= 0.0:
		draw_string(get_theme_default_font(), Vector2(12.0, middle), _waveform_message if not _waveform_message.is_empty() else "Waveform unavailable. Use Refresh Waveform to reload audio data.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, get_theme_default_font_size(), Color("c4d0d6"))
	elif scroll_seconds >= duration:
		draw_string(get_theme_default_font(), Vector2(12.0, middle), "Voice audio is outside this view. Use Fit Timeline to return to it.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, get_theme_default_font_size(), Color("c4d0d6"))
	for pixel: int in range(0, int(size.x), 2):
		if waveform.is_empty() or duration <= 0.0:
			break
		var time_sec: float = _x_time(float(pixel))
		if time_sec < 0.0 or time_sec > duration:
			continue
		var bin_index: int = clampi(int(time_sec / duration * waveform.size()), 0, waveform.size() - 1)
		var height: float = maxf(0.5, waveform[bin_index] * half_height)
		draw_line(Vector2(pixel, middle - height), Vector2(pixel, middle + height), Color("55d985"), 2.0)
	for bound: float in [clip.audible_start, clip.audible_end]:
		if bound > 0.0:
			var x: float = _time_x(bound)
			draw_line(Vector2(x, RULER_BOTTOM), Vector2(x, WAVE_BOTTOM), Color("e9c850"), 2.0)


func _draw_words(font: Font, font_size: int) -> void:
	for span: Dictionary in clip.word_spans:
		var x1: float = _time_x(float(span.get("start", 0.0)))
		var x2: float = _time_x(float(span.get("end", 0.0)))
		var rect: Rect2 = Rect2(x1, WAVE_BOTTOM + 4.0, maxf(4.0, x2 - x1 - 2.0), WORD_BOTTOM - WAVE_BOTTOM - 8.0)
		draw_rect(rect, Color("536f84"))
		if _has_word(selected_words, span):
			draw_rect(rect, Color.WHITE if is_same(span, active_word) else Color("b9dfff"), false, 3.0 if is_same(span, active_word) else 1.5)
		draw_string(font, Vector2(x1 + 4.0, WORD_BOTTOM - 12.0), String(span.get("word", "")), HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, rect.size.x - 8.0), font_size - 1, Color.WHITE)


func _draw_cues(cues: Array[LipSyncCue], color: Color, expression: bool, font: Font, font_size: int) -> void:
	for cue: LipSyncCue in cues:
		if not cue:
			continue
		var bounds: Vector2 = _row_bounds(expression, cue.row)
		var top: float = bounds.x
		var bottom: float = bounds.y
		var x1: float = _time_x(cue.start_time)
		var x2: float = _time_x(cue.end_time)
		var rect: Rect2 = Rect2(x1, top + 5.0, maxf(3.0, x2 - x1), bottom - top - 10.0)
		var fill: Color = color.lightened(0.22) if cue == selected_cue and expression == selected_expression else color
		draw_rect(rect, fill)
		draw_rect(rect, Color.WHITE if cue == selected_cue else (Color("b9dfff") if selected_cues.has(cue) else fill.darkened(0.35)), false, 3.0 if cue == selected_cue else 1.5)
		var curve: int = clip.expression_blend_curve if expression else clip.viseme_blend_curve
		for edge: int in range(2):
			var points: PackedVector2Array = PackedVector2Array()
			var start: float = cue.start_time if edge == 0 else cue.end_time - cue.get_blend_out()
			var duration: float = cue.get_blend_in() if edge == 0 else cue.get_blend_out()
			for step: int in range(13):
				var time_sec: float = start + duration * float(step) / 12.0
				points.append(Vector2(_time_x(time_sec), lerpf(bottom - 6.0, top + 6.0, cue.get_fade_weight(time_sec, curve))))
			draw_polyline(points, fill.lightened(0.4), 1.0)
		var strength_y: float = lerpf(bottom - 6.0, top + 6.0, clampf(cue.strength, 0.0, 1.0))
		draw_line(Vector2(x1 + 1.0, strength_y), Vector2(x2 - 1.0, strength_y), Color(0.0, 0.0, 0.0, 0.65), 3.5)
		draw_line(Vector2(x1 + 1.0, strength_y), Vector2(x2 - 1.0, strength_y), Color("fff2a6"), 1.5)
		if cue.lock_max_blend:
			draw_string(font, Vector2(x2 - 16.0, top + 16.0), "B", HORIZONTAL_ALIGNMENT_LEFT, 12.0, font_size - 2, Color("fff2a6"))
		draw_string(font, Vector2(x1 + 5.0, bottom - 15.0), String(cue.pose_id).trim_prefix("EXP_").trim_prefix("VIS_"), HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, rect.size.x - 10.0), font_size - 1, Color.WHITE)


func _input(event: InputEvent) -> void:
	if _drag_mode.is_empty():
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == _drag_button and not button.pressed:
			_finish_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		var position: Vector2 = get_global_transform_with_canvas().affine_inverse() * motion.position
		_update_drag(position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_drag()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if not button.pressed:
			return
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if not _drag_mode.is_empty():
				accept_event()
				return
			var direction: float = 1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if button.ctrl_pressed:
				var anchor_time: float = _x_time(button.position.x)
				pixels_per_second = clampf(pixels_per_second * (1.15 if direction > 0.0 else 1.0 / 1.15), 45.0, 1000.0)
				scroll_seconds = maxf(0.0, anchor_time - button.position.x / pixels_per_second)
			else:
				scroll_seconds = maxf(0.0, scroll_seconds - direction * 0.25)
			scroll_seconds = clampf(scroll_seconds, 0.0, maxf(0.0, _timeline_length() - size.x / pixels_per_second + 0.25))
			queue_redraw()
			accept_event()
			return
		if button.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] or not clip or not _drag_mode.is_empty():
			return
		grab_focus()
		_drag_button = button.button_index
		_drag_origin = button.position
		_drag_anchor = _x_time(button.position.x)
		_drag_changed = false
		_drag_moved = false
		_collapse_on_click = false
		_drag_backup = _capture_drag_state()
		_move_warning = ""
		if button.button_index == MOUSE_BUTTON_LEFT and button.position.y < WAVE_BOTTOM:
			if clip.audio and button.position.y >= RULER_BOTTOM:
				normalize_audible_range()
				var start_x: float = _time_x(clip.audible_start)
				var end_x: float = _time_x(clip.audible_end)
				var near_start: bool = absf(button.position.x - start_x) <= 7.0
				var near_end: bool = absf(button.position.x - end_x) <= 7.0
				if near_start or near_end:
					_drag_mode = "audible_start" if near_start and (not near_end or button.position.x <= (start_x + end_x) * 0.5) else "audible_end"
			if _drag_mode.is_empty():
				_drag_mode = "playhead"
				set_playhead(_drag_anchor)
			accept_event()
			return
		if button.double_click and button.button_index == MOUSE_BUTTON_LEFT and not button.shift_pressed and not button.ctrl_pressed:
			var insert_row: Dictionary = _row_at_y(button.position.y)
			if not insert_row.is_empty():
				add_requested.emit(bool(insert_row["expression"]), _drag_anchor, int(insert_row["row"]))
				_drag_button = 0
				accept_event()
				return
		var picked: Dictionary = _pick_cue(button.position)
		_word_index = -1
		if button.position.y >= WAVE_BOTTOM and button.position.y < WORD_BOTTOM:
			_pick_word(button.position.x)
		if not picked.is_empty() or _word_index >= 0:
			var word: Dictionary = clip.word_spans[_word_index] if _word_index >= 0 else {}
			var cue: LipSyncCue = picked.get("cue") as LipSyncCue
			var already_selected: bool = selected_cues.has(cue) if cue else _has_word(selected_words, word)
			if button.ctrl_pressed and button.button_index == MOUSE_BUTTON_LEFT:
				if cue:
					selected_cues.erase(cue)
				else:
					_remove_word(selected_words, word)
				_reconcile_active()
				_drag_mode = ""
				_drag_button = 0
			else:
				if not already_selected and not button.shift_pressed:
					clear_selection()
				if cue:
					if not selected_cues.has(cue):
						selected_cues.append(cue)
					selected_cue = cue
					selected_expression = bool(picked["expression"])
					active_word = {}
					_drag_mode = String(picked["mode"])
					_drag_start = cue.start_time
					_drag_end = cue.end_time
					_drag_original_row = cue.row
					if button.button_index == MOUSE_BUTTON_RIGHT:
						_drag_mode = "cue_adjust"
						_drag_strength_start = cue.strength
						_drag_blend_start = cue.get_blend_in() if _drag_anchor < (_drag_start + _drag_end) * 0.5 else cue.get_blend_out()
				else:
					if not _has_word(selected_words, word):
						selected_words.append(word)
					active_word = word
					selected_cue = null
					_drag_start = float(word["start"])
					_drag_end = float(word["end"])
					if button.button_index == MOUSE_BUTTON_RIGHT:
						_drag_mode = ""
				if _drag_mode in ["move", "word_move"]:
					_drag_mode = "group"
					_capture_group()
					_collapse_on_click = already_selected and not button.shift_pressed and get_selection_count() > 1
				_notify_selection()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.position.y >= WAVE_BOTTOM:
			_drag_mode = "box"
			_box_anchor = button.position
			_box_cursor = button.position
			_selection_operation = -1 if button.ctrl_pressed else (1 if button.shift_pressed else 0)
			_selection_before_cues = selected_cues.duplicate()
			_selection_before_words = selected_words.duplicate()
			_selection_before_active_cue = selected_cue
			_selection_before_active_word = active_word
		else:
			_drag_button = 0
		accept_event()
	elif event is InputEventKey and event.pressed:
		var key: InputEventKey = event
		if not _drag_mode.is_empty():
			accept_event()
			return
		if key.keycode == KEY_DELETE and get_selection_count() > 0:
			delete_requested.emit()
			accept_event()
		elif key.keycode == KEY_ESCAPE:
			clear_selection()
			accept_event()


func _update_drag(position: Vector2) -> void:
	_drag_moved = _drag_moved or position.distance_to(_drag_origin) >= 4.0
	if _drag_mode == "cue_adjust":
		var motion: Vector2 = (position - _drag_origin).abs()
		var distance: float = maxf(motion.x, motion.y)
		if distance < 6.0:
			return
		if distance < 12.0 and maxf(motion.x, motion.y) < minf(motion.x, motion.y) * 1.25:
			return
		_drag_mode = "strength" if motion.y > motion.x else ("blend_in" if _drag_anchor < (_drag_start + _drag_end) * 0.5 else "blend_out")
	if _drag_mode == "box":
		_box_cursor = position
		if _drag_moved:
			_box_select()
	elif _drag_mode == "playhead":
		set_playhead(_x_time(position.x))
	elif _drag_mode in ["audible_start", "audible_end"]:
		_drag_audible_handle(_x_time(position.x))
	elif _drag_moved:
		if _drag_mode == "group":
			_drag_group(position)
		elif _drag_mode.begins_with("word_"):
			_drag_word(_x_time(position.x))
		elif _drag_mode in ["blend_in", "blend_out"]:
			_drag_blend(_x_time(position.x))
		elif _drag_mode == "strength":
			_drag_strength(position)
		else:
			_drag_cue(position)

func _drag_audible_handle(time_sec: float) -> void:
	if not clip or not clip.audio:
		cancel_audible_drag()
		return
	var duration: float = maxf(0.0, clip.audio.get_length())
	var minimum_span: float = minf(MIN_AUDIBLE_SPAN, duration)
	var next_time: float = _snap_time(time_sec)
	if _drag_mode == "audible_start":
		next_time = clampf(next_time, 0.0, maxf(0.0, clip.audible_end - minimum_span))
		if is_equal_approx(next_time, clip.audible_start):
			return
		_begin_edit()
		clip.audible_start = next_time
	elif _drag_mode == "audible_end":
		next_time = clampf(next_time, minf(duration, clip.audible_start + minimum_span), duration)
		if is_equal_approx(next_time, clip.audible_end):
			return
		_begin_edit()
		clip.audible_end = next_time
	clip.emit_changed()
	cue_modified.emit()
	queue_redraw()


func _drag_cue(position: Vector2) -> void:
	if not selected_cue or not clip:
		return
	var delta: float = _snap_time(_x_time(position.x) - _drag_anchor)
	var cues: Array[LipSyncCue] = clip.expression_cues if selected_expression else clip.viseme_cues
	var target_row: int = selected_cue.row
	var candidate_start: float = selected_cue.start_time
	var candidate_end: float = selected_cue.end_time
	if _drag_mode == "left":
		candidate_start = clampf(_drag_start + delta, 0.0, selected_cue.end_time - 0.02)
	elif _drag_mode == "right":
		candidate_end = maxf(selected_cue.start_time + 0.02, _drag_end + delta)
	if not _fits_in_row(cues, selected_cue, target_row, candidate_start, candidate_end):
		_move_warning = "Resize blocked: clips would overlap on the same row."
		queue_redraw()
		return
	_move_warning = ""
	if is_equal_approx(candidate_start, selected_cue.start_time) and is_equal_approx(candidate_end, selected_cue.end_time):
		return
	_begin_edit()
	selected_cue.row = target_row
	selected_cue.start_time = candidate_start
	selected_cue.end_time = candidate_end
	selected_cue.refresh_blends()
	cues.sort_custom(func(a: LipSyncCue, b: LipSyncCue) -> bool: return a.start_time < b.start_time)
	selected_cue.emit_changed()
	clip.emit_changed()
	cue_modified.emit()
	queue_redraw()


func _drag_blend(time_sec: float) -> void:
	if not selected_cue or not clip:
		return
	var delta: float = _snap_time(time_sec - _drag_anchor)
	var limit: float = (selected_cue.end_time - selected_cue.start_time) * 0.5
	var adjusted: float = 0.0
	if _drag_mode == "blend_in":
		adjusted = clampf(_drag_blend_start + delta, 0.0, limit)
		if is_equal_approx(adjusted, selected_cue.get_blend_in()):
			return
	else:
		adjusted = clampf(_drag_blend_start - delta, 0.0, limit)
		if is_equal_approx(adjusted, selected_cue.get_blend_out()):
			return
	_begin_edit()
	selected_cue.refresh_blends()
	selected_cue.lock_max_blend = false
	if _drag_mode == "blend_in":
		selected_cue.blend_in = adjusted
	else:
		selected_cue.blend_out = adjusted
	selected_cue.emit_changed()
	clip.emit_changed()
	cue_modified.emit()
	queue_redraw()


func _drag_strength(position: Vector2) -> void:
	if not selected_cue or not clip:
		return
	var value: float = clampf(_drag_strength_start + (_drag_origin.y - position.y) / (ROW_HEIGHT - 12.0), 0.0, 1.0)
	if is_equal_approx(value, selected_cue.strength):
		return
	_begin_edit()
	selected_cue.strength = value
	selected_cue.emit_changed()
	clip.emit_changed()
	cue_modified.emit()
	queue_redraw()


func toggle_selected_blend_lock() -> void:
	var enabled: bool = false
	for cue: LipSyncCue in selected_cues:
		if not cue.lock_max_blend:
			enabled = true
	set_selected_blend_lock(enabled)


func set_selected_blend_lock(enabled: bool, active_only: bool = false) -> void:
	if not clip or not _drag_mode.is_empty():
		return
	var targets: Array[LipSyncCue] = [selected_cue] if active_only and selected_cue else selected_cues
	var changed: bool = false
	for cue: LipSyncCue in targets:
		if cue.lock_max_blend != enabled:
			if not changed:
				edit_started.emit()
				changed = true
			cue.refresh_blends()
			cue.lock_max_blend = enabled
			cue.refresh_blends()
			cue.emit_changed()
	if changed:
		clip.emit_changed()
		cue_modified.emit()
		queue_redraw()


func _pick_cue(position: Vector2) -> Dictionary:
	if not clip:
		return {}
	var row_at_cursor: Dictionary = _row_at_y(position.y)
	if row_at_cursor.is_empty():
		return {}
	var expression: bool = bool(row_at_cursor["expression"])
	var row: int = int(row_at_cursor["row"])
	var cues: Array[LipSyncCue] = clip.expression_cues if expression else clip.viseme_cues
	for cue: LipSyncCue in cues:
		if not cue or cue.row != row:
			continue
		var x1: float = _time_x(cue.start_time)
		var x2: float = _time_x(cue.end_time)
		if position.x >= x1 - 4.0 and position.x <= x2 + 4.0:
			var mode: String = "move"
			if absf(position.x - x1) <= 6.0:
				mode = "left"
			elif absf(position.x - x2) <= 6.0:
				mode = "right"
			return {"cue": cue, "expression": expression, "mode": mode}
	return {}


func _row_at_y(y: float) -> Dictionary:
	if y < WORD_BOTTOM or y >= EXPRESSION_BOTTOM:
		return {}
	var expression: bool = y >= VISEME_BOTTOM
	var top: float = VISEME_BOTTOM if expression else WORD_BOTTOM
	return {"expression": expression, "row": floori((y - top) / ROW_HEIGHT)}


func _row_bounds(expression: bool, row: int) -> Vector2:
	var top: float = (VISEME_BOTTOM if expression else WORD_BOTTOM) + float(clampi(row, 0, LipSyncCue.ROW_COUNT - 1)) * ROW_HEIGHT
	return Vector2(top, top + ROW_HEIGHT)


func _fits_in_row(cues: Array[LipSyncCue], selected: LipSyncCue, row: int, start: float, end: float) -> bool:
	for cue: LipSyncCue in cues:
		if cue and cue != selected and cue.row == row and start < cue.end_time - 0.001 and end > cue.start_time + 0.001:
			return false
	return true


func _pick_word(x: float) -> void:
	_word_index = -1
	for index: int in range(clip.word_spans.size()):
		var span: Dictionary = clip.word_spans[index]
		var x1: float = _time_x(float(span.get("start", 0.0)))
		var x2: float = _time_x(float(span.get("end", 0.0)))
		if x >= x1 - 4.0 and x <= x2 + 4.0:
			_word_index = index
			_drag_mode = "word_move"
			if absf(x - x1) <= 6.0:
				_drag_mode = "word_left"
			elif absf(x - x2) <= 6.0:
				_drag_mode = "word_right"
			_drag_anchor = _x_time(x)
			_drag_start = float(span.get("start", 0.0))
			_drag_end = float(span.get("end", 0.0))
			return


func _drag_word(time_sec: float) -> void:
	if not clip or _word_index < 0:
		return
	var span: Dictionary = clip.word_spans[_word_index]
	var lower: float = float(clip.word_spans[_word_index - 1]["end"]) if _word_index > 0 else 0.0
	var upper: float = float(clip.word_spans[_word_index + 1]["start"]) if _word_index + 1 < clip.word_spans.size() else _timeline_length()
	var delta: float = _snap_time(time_sec - _drag_anchor)
	var next_start: float = float(span["start"])
	var next_end: float = float(span["end"])
	if _drag_mode == "word_left":
		next_start = clampf(_drag_start + delta, lower, next_end - 0.02)
	elif _drag_mode == "word_right":
		next_end = clampf(_drag_end + delta, next_start + 0.02, upper)
	if is_equal_approx(next_start, float(span["start"])) and is_equal_approx(next_end, float(span["end"])):
		return
	_begin_edit()
	span["start"] = next_start
	span["end"] = next_end
	clip.word_spans[_word_index] = span
	clip.emit_changed()
	cue_modified.emit()
	queue_redraw()


func get_selection_count() -> int:
	return selected_cues.size() + selected_words.size()


func clear_selection() -> void:
	selected_cues.clear()
	selected_words.clear()
	selected_cue = null
	active_word = {}
	_notify_selection()


func select_cue(cue: LipSyncCue, expression: bool) -> void:
	clear_selection()
	if cue:
		selected_cues.append(cue)
	selected_cue = cue
	selected_expression = expression
	_notify_selection()


func _has_word(words: Array[Dictionary], word: Dictionary) -> bool:
	for item: Dictionary in words:
		if is_same(item, word):
			return true
	return false


func _remove_word(words: Array[Dictionary], word: Dictionary) -> void:
	for index: int in range(words.size() - 1, -1, -1):
		if is_same(words[index], word):
			words.remove_at(index)


func _notify_selection() -> void:
	cue_selected.emit(selected_cue, selected_expression)
	selection_changed.emit()
	queue_redraw()


func _reconcile_active() -> void:
	if selected_cue and selected_cues.has(selected_cue):
		active_word = {}
	elif not active_word.is_empty() and _has_word(selected_words, active_word):
		selected_cue = null
	elif not selected_cues.is_empty():
		selected_cue = selected_cues.back()
		selected_expression = clip.expression_cues.has(selected_cue)
		active_word = {}
	else:
		selected_cue = null
		active_word = selected_words.back() if not selected_words.is_empty() else {}
	_notify_selection()


func _box_select() -> void:
	var box: Rect2 = Rect2(_box_anchor, _box_cursor - _box_anchor).abs()
	selected_cues.clear()
	selected_words.clear()
	if _selection_operation != 0:
		selected_cues.assign(_selection_before_cues)
		selected_words.assign(_selection_before_words)
	for expression: bool in [false, true]:
		var cues: Array[LipSyncCue] = clip.expression_cues if expression else clip.viseme_cues
		for cue: LipSyncCue in cues:
			if not cue:
				continue
			var bounds: Vector2 = _row_bounds(expression, cue.row)
			var rect: Rect2 = Rect2(_time_x(cue.start_time), bounds.x + 5.0, maxf(3.0, (cue.end_time - cue.start_time) * pixels_per_second), bounds.y - bounds.x - 10.0)
			if box.intersects(rect, true):
				if _selection_operation < 0:
					selected_cues.erase(cue)
				elif not selected_cues.has(cue):
					selected_cues.append(cue)
	for word: Dictionary in clip.word_spans:
		var rect: Rect2 = Rect2(_time_x(float(word["start"])), WAVE_BOTTOM + 4.0, maxf(4.0, (float(word["end"]) - float(word["start"])) * pixels_per_second - 2.0), WORD_BOTTOM - WAVE_BOTTOM - 8.0)
		if box.intersects(rect, true):
			if _selection_operation < 0:
				_remove_word(selected_words, word)
			elif not _has_word(selected_words, word):
				selected_words.append(word)
	_reconcile_active()


func _capture_group() -> void:
	_drag_entries.clear()
	for cue: LipSyncCue in selected_cues:
		_drag_entries.append({"cue": cue, "kind": "expression" if clip.expression_cues.has(cue) else "viseme", "row": cue.row, "start": cue.start_time, "end": cue.end_time})
	for word: Dictionary in selected_words:
		_drag_entries.append({"word": word, "kind": "word", "row": 0, "start": float(word["start"]), "end": float(word["end"])})


func _drag_group(position: Vector2) -> void:
	if _drag_entries.is_empty():
		return
	var delta: float = _snap_time(_drag_start + _x_time(position.x) - _drag_anchor) - _drag_start
	if absf(position.x - _drag_origin.x) < 4.0:
		delta = 0.0
	var earliest: float = INF
	var minimum_row: int = 3
	var maximum_row: int = 0
	var kind: String = String(_drag_entries[0]["kind"])
	for entry: Dictionary in _drag_entries:
		earliest = minf(earliest, float(entry["start"]))
		minimum_row = mini(minimum_row, int(entry["row"]))
		maximum_row = maxi(maximum_row, int(entry["row"]))
		if String(entry["kind"]) != kind:
			kind = "mixed"
	delta = maxf(delta, -earliest)
	var row_delta: int = 0
	var target: Dictionary = _row_at_y(position.y)
	if kind in ["viseme", "expression"] and not target.is_empty() and bool(target["expression"]) == (kind == "expression"):
		var last_row: int = LipSyncCue.ROW_COUNT - 1
		row_delta = clampi(int(target["row"]) - _drag_original_row, -minimum_row, last_row - maximum_row)
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _drag_entries:
		var candidate: Dictionary = entry.duplicate()
		candidate["start"] = float(entry["start"]) + delta
		candidate["end"] = float(entry["end"]) + delta
		candidate["row"] = int(entry["row"]) + row_delta
		candidates.append(candidate)
	if not _group_fits(candidates):
		_move_warning = "Move blocked: clips would overlap on the same track or row."
		selection_status.emit(_move_warning)
		queue_redraw()
		return
	_move_warning = ""
	var changed: bool = false
	for candidate: Dictionary in candidates:
		if candidate["kind"] == "word":
			var word: Dictionary = candidate["word"]
			changed = changed or not is_equal_approx(float(word["start"]), float(candidate["start"]))
		else:
			var cue: LipSyncCue = candidate["cue"]
			changed = changed or cue.row != int(candidate["row"]) or not is_equal_approx(cue.start_time, float(candidate["start"]))
	if not changed:
		queue_redraw()
		return
	_begin_edit()
	for candidate: Dictionary in candidates:
		if candidate["kind"] == "word":
			var word: Dictionary = candidate["word"]
			word["start"] = candidate["start"]
			word["end"] = candidate["end"]
		else:
			var cue: LipSyncCue = candidate["cue"]
			cue.start_time = float(candidate["start"])
			cue.end_time = float(candidate["end"])
			cue.row = int(candidate["row"])
			cue.emit_changed()
	_sort_tracks()
	clip.emit_changed()
	cue_modified.emit()
	selection_status.emit("Moved %d selected clip(s)." % get_selection_count())
	queue_redraw()


func _group_fits(candidates: Array[Dictionary]) -> bool:
	for index: int in range(candidates.size()):
		var candidate: Dictionary = candidates[index]
		for other_index: int in range(index):
			var other: Dictionary = candidates[other_index]
			if candidate["kind"] == other["kind"] and candidate["row"] == other["row"] and _overlaps(candidate, other):
				return false
		if candidate["kind"] == "word":
			for word: Dictionary in clip.word_spans:
				if not _has_word(selected_words, word) and _overlaps(candidate, word):
					return false
		else:
			var cues: Array[LipSyncCue] = clip.expression_cues if candidate["kind"] == "expression" else clip.viseme_cues
			for cue: LipSyncCue in cues:
				if cue and not selected_cues.has(cue) and cue.row == int(candidate["row"]) and _overlaps(candidate, {"start": cue.start_time, "end": cue.end_time}):
					return false
	return true


func _overlaps(a: Dictionary, b: Dictionary) -> bool:
	return float(a["start"]) < float(b["end"]) - 0.001 and float(a["end"]) > float(b["start"]) + 0.001


func _sort_tracks() -> void:
	clip.viseme_cues.sort_custom(func(a: LipSyncCue, b: LipSyncCue) -> bool: return a.start_time < b.start_time)
	clip.expression_cues.sort_custom(func(a: LipSyncCue, b: LipSyncCue) -> bool: return a.start_time < b.start_time)
	clip.word_spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["start"]) < float(b["start"]))


func _begin_edit() -> void:
	if not _drag_changed:
		edit_started.emit()
		_drag_changed = true


func _capture_drag_state() -> Dictionary:
	var cues: Array[Dictionary] = []
	for cue: LipSyncCue in clip.viseme_cues + clip.expression_cues:
		if cue:
			cues.append({"cue": cue, "start": cue.start_time, "end": cue.end_time, "row": cue.row, "in": cue.blend_in, "out": cue.blend_out, "strength": cue.strength, "lock": cue.lock_max_blend})
	var words: Array[Dictionary] = []
	for word: Dictionary in clip.word_spans:
		words.append({"word": word, "start": word["start"], "end": word["end"]})
	return {"cues": cues, "words": words, "audible_start": clip.audible_start, "audible_end": clip.audible_end}


func _finish_drag() -> void:
	if _drag_mode == "box" and not _drag_moved and _selection_operation == 0:
		clear_selection()
	elif _collapse_on_click and not _drag_moved:
		if selected_cue:
			select_cue(selected_cue, selected_expression)
		else:
			var word: Dictionary = active_word
			clear_selection()
			selected_words.append(word)
			active_word = word
			_notify_selection()
	_drag_mode = ""
	_drag_button = 0
	_drag_entries.clear()
	_drag_backup.clear()
	_drag_changed = false
	_move_warning = ""
	queue_redraw()


func _cancel_drag() -> void:
	if _drag_mode.is_empty():
		return
	if _drag_mode == "box":
		selected_cues = _selection_before_cues.duplicate()
		selected_words = _selection_before_words.duplicate()
		selected_cue = _selection_before_active_cue
		active_word = _selection_before_active_word
		if selected_cue:
			selected_expression = clip.expression_cues.has(selected_cue)
		_reconcile_active()
	if _drag_changed and not _drag_backup.is_empty():
		for entry: Dictionary in _drag_backup["cues"]:
			var cue: LipSyncCue = entry["cue"]
			cue.start_time = entry["start"]
			cue.end_time = entry["end"]
			cue.row = entry["row"]
			cue.blend_in = entry["in"]
			cue.blend_out = entry["out"]
			cue.strength = entry["strength"]
			cue.lock_max_blend = entry["lock"]
			cue.emit_changed()
		for entry: Dictionary in _drag_backup["words"]:
			var word: Dictionary = entry["word"]
			word["start"] = entry["start"]
			word["end"] = entry["end"]
		clip.audible_start = _drag_backup["audible_start"]
		clip.audible_end = _drag_backup["audible_end"]
		_sort_tracks()
		clip.emit_changed()
		cue_modified.emit()
		edit_cancelled.emit()
	_collapse_on_click = false
	_drag_moved = true
	_finish_drag()


func _time_x(time_sec: float) -> float:
	return (time_sec - scroll_seconds) * pixels_per_second


func _x_time(x: float) -> float:
	return maxf(0.0, scroll_seconds + x / pixels_per_second)


func _timeline_length() -> float:
	var length: float = maxf(0.1, clip.get_timeline_length()) if clip else 0.1
	if clip:
		for word: Dictionary in clip.word_spans:
			length = maxf(length, float(word["end"]))
	return length


func _snap_time(time_sec: float) -> float:
	return snappedf(time_sec, snap_step) if snap_step > 0.0 else time_sec

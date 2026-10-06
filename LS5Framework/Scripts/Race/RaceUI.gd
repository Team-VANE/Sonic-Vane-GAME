extends CanvasLayer

signal option_selected(option: StringName)
signal ghost_save_requested()

## Input action that accelerates race presentation sequences.
@export var action_skip: StringName = &"ability_slot_01"
## Allows the configured mouse button to accelerate race presentation sequences.
@export var allow_mouse_skip: bool = true
## Mouse button used to accelerate race presentation sequences.
@export var mouse_skip_button: MouseButton = MOUSE_BUTTON_LEFT

@export_group("Countdown Presentation")
## Time taken by the countdown frame to sweep in from below.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var countdown_enter_duration: float = 0.5
## Time taken by the countdown frame to sweep out above the screen.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var countdown_exit_duration: float = 0.42
## Vertical distance used by the countdown frame's entrance.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px") var countdown_enter_distance: float = 520.0
## Vertical distance used by the countdown frame's exit.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px") var countdown_exit_distance: float = 460.0
## Final glyph spacing reached while GO remains visible.
@export_range(0, 40, 1, "or_greater", "suffix:px") var go_tracking_spacing: int = 5

@export_group("Results Presentation")
## Time taken by the results panel to enter.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var results_enter_duration: float = 0.55
## Time taken to reveal the result text.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var results_reveal_duration: float = 0.8
## Speed multiplier applied to presentation tweens after skip input.
@export_range(1.0, 20.0, 0.1, "or_greater") var skip_animation_speed: float = 5.0
## Maximum remaining wait after presentation skip input.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var skip_remaining_time: float = 0.35

## Displays the race or level name during setup.
@onready var label_level: Label = get_node_or_null("Root/LevelName") as Label
## Contains the countdown and GO presentation.
@onready var panel_countdown: PanelContainer = get_node_or_null("Root/CountdownFrame") as PanelContainer
## Displays countdown numbers and GO text.
@onready var label_countdown: Label = get_node_or_null("Root/CountdownFrame/Margin/CountdownText") as Label
## Contains the race result summary.
@onready var panel_results: PanelContainer = get_node_or_null("Root/Results") as PanelContainer
## Displays race result values and placements.
@onready var label_results: RichTextLabel = get_node_or_null("Root/Results/Margin/VBox/ResultsText") as RichTextLabel
## Highlights a newly achieved record.
@onready var label_new_record: Label = get_node_or_null("Root/Results/NewRecord") as Label
## Contains post-race action buttons.
@onready var panel_options: PanelContainer = get_node_or_null("Root/Options") as PanelContainer
## Contains the optional ghost save action shown for a completed recording.
@onready var ghost_save_container: VBoxContainer = get_node_or_null("Root/Options/Margin/VBox/GhostSave") as VBoxContainer
## Describes the pending ghost recording and its save state.
@onready var label_ghost_save: Label = get_node_or_null("Root/Options/Margin/VBox/GhostSave/Status") as Label
## Commits the pending ghost recording to disk.
@onready var button_save_ghost: Button = get_node_or_null("Root/Options/Margin/VBox/GhostSave/SaveGhost") as Button
## Keeps the player at the current location after closing the results.
@onready var button_stay: Button = get_node_or_null("Root/Options/Margin/VBox/Stay") as Button
## Returns the player to the configured hub after closing the results.
@onready var button_return_hub: Button = get_node_or_null("Root/Options/Margin/VBox/ReturnHub") as Button
## Restarts the current race or returns to its start.
@onready var button_restart: Button = get_node_or_null("Root/Options/Margin/VBox/RestartRace") as Button
## Returns to the main menu after a race.
@onready var button_return_menu: Button = get_node_or_null("Root/Options/Margin/VBox/ReturnMenu") as Button

var _skip_requested: bool = false
var _countdown_frame_presented: bool = false
var _primary_color: Color = Color(0.2, 0.55, 1.0, 1.0)
var _foreground_color: Color = Color(0.65, 0.82, 1.0, 1.0)
var _countdown_style: StyleBoxFlat = null
var _results_style: StyleBoxFlat = null
var _options_style: StyleBoxFlat = null
var _go_tracking_font: FontVariation = null
var _active_tweens: Array[Tween] = []
var _countdown_frame_tween: Tween = null
var _countdown_text_tween: Tween = null


func _ready() -> void:
	layer = 50
	visible = true
	set_process_unhandled_input(true)
	_prepare_panel_styles()
	_resolve_character_colors()
	_go_tracking_font = UIExcitementEffects.create_tracking_font(label_countdown)
	_reset()


func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	if get_tree() != null and get_tree().has_meta(&"chat_input_active") and bool(get_tree().get_meta(&"chat_input_active")):
		return
	if event.is_action_pressed(action_skip):
		_request_speedup()
		return
	if allow_mouse_skip and event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == mouse_skip_button:
			_request_speedup()


func _reset() -> void:
	_skip_requested = false
	_countdown_frame_presented = false
	_kill_active_tweens()
	if label_level != null:
		label_level.visible = false
		label_level.scale = Vector2.ONE
		label_level.modulate.a = 1.0
	if panel_countdown != null:
		panel_countdown.visible = false
		panel_countdown.scale = Vector2.ONE
		panel_countdown.modulate.a = 1.0
	if label_countdown != null:
		label_countdown.visible = false
		label_countdown.scale = Vector2.ONE
		label_countdown.modulate.a = 1.0
	if panel_results != null:
		panel_results.visible = false
	if panel_options != null:
		panel_options.visible = false
	if ghost_save_container != null:
		ghost_save_container.visible = false


func show_level_name(level_name: String) -> void:
	if label_level == null:
		return
	label_level.text = level_name
	label_level.visible = true
	_track_tween(UIExcitementEffects.sweep_in(label_level, Vector2(-260.0, 0.0), 0.48, 0.78))
	HUDMusicTrackDisplay.post_notification(
		get_tree(),
		"Race Starting",
		level_name,
		null,
		3.5,
		&"race_starting"
	)


func hide_level_name() -> void:
	if label_level == null or not label_level.visible:
		return
	var tween: Tween = UIExcitementEffects.sweep_out(
		label_level,
		Vector2(260.0, -24.0),
		0.28,
		0.96
	)
	_track_tween(tween)
	if tween != null:
		tween.tween_callback(label_level.hide)


func show_countdown_number(text_value: String) -> void:
	if panel_countdown == null or label_countdown == null:
		return
	if text_value == "":
		label_countdown.text = ""
		label_countdown.visible = false
		return
	label_countdown.add_theme_font_size_override("font_size", 160)
	label_countdown.text = text_value
	label_countdown.visible = true
	if _go_tracking_font != null:
		_go_tracking_font.spacing_glyph = 0
	if not _countdown_frame_presented:
		_countdown_frame_presented = true
		panel_countdown.visible = true
		_countdown_frame_tween = UIExcitementEffects.sweep_in(
			panel_countdown,
			Vector2(0.0, countdown_enter_distance),
			countdown_enter_duration,
			0.9
		)
		_track_tween(_countdown_frame_tween)
	_pulse_countdown_text(false)


func hide_countdown() -> void:
	if label_countdown != null:
		label_countdown.visible = false


func show_go(duration: float = 1.0) -> void:
	if panel_countdown == null or label_countdown == null:
		return
	if not _countdown_frame_presented:
		_countdown_frame_presented = true
		panel_countdown.visible = true
		_countdown_frame_tween = UIExcitementEffects.sweep_in(
			panel_countdown,
			Vector2(0.0, countdown_enter_distance),
			countdown_enter_duration,
			0.9
		)
		_track_tween(_countdown_frame_tween)
	label_countdown.add_theme_font_size_override("font_size", 140)
	label_countdown.text = "GO!"
	label_countdown.visible = true
	_pulse_countdown_text(true)
	_track_tween(UIExcitementEffects.animate_tracking(
		label_countdown,
		_go_tracking_font,
		go_tracking_spacing,
		duration
	))
	if get_tree() != null and duration > 0.0:
		await get_tree().create_timer(duration).timeout
	if not is_instance_valid(panel_countdown):
		return
	_countdown_frame_tween = UIExcitementEffects.sweep_out(
		panel_countdown,
		Vector2(0.0, -countdown_exit_distance),
		countdown_exit_duration,
		0.88
	)
	_track_tween(_countdown_frame_tween)
	if _countdown_frame_tween != null:
		await _countdown_frame_tween.finished
	if panel_countdown != null:
		panel_countdown.visible = false


func show_results(
		rings_value: int,
		time_seconds: float,
		score_value: int,
		is_new_record: bool = false,
		extra_note: String = ""
	) -> void:
	_set_result_text(rings_value, time_seconds, score_value, "", is_new_record, extra_note)


func show_race_results_with_places(
		rings_value: int,
		time_seconds: float,
		score_value: int,
		places_bbcode: String,
		is_new_record: bool = false,
		extra_note: String = ""
	) -> void:
	_set_result_text(
		rings_value,
		time_seconds,
		score_value,
		places_bbcode,
		is_new_record,
		extra_note
	)


func show_options() -> void:
	if panel_options == null:
		return
	panel_options.visible = true
	panel_options.reset_size()
	call_deferred("_animate_options_in")


func _animate_options_in() -> void:
	if panel_options == null or not panel_options.visible:
		return
	_focus_post_race_options()
	_track_tween(UIExcitementEffects.sweep_in(
		panel_options,
		Vector2(0.0, 220.0),
		0.46,
		0.94
	))


func _focus_post_race_options() -> void:
	var focus_candidates: Array[Button] = [
		button_stay,
		button_return_hub,
		button_restart,
		button_return_menu,
		button_save_ghost,
	]
	for button: Button in focus_candidates:
		if not button or not is_instance_valid(button):
			continue
		if not button.is_visible_in_tree() or button.disabled or button.focus_mode == Control.FOCUS_NONE:
			continue
		button.grab_focus()
		return


func configure_post_race_options(allow_restart: bool, allow_return_menu: bool) -> void:
	if button_restart != null:
		button_restart.visible = allow_restart
	if button_return_menu != null:
		button_return_menu.visible = allow_return_menu


func configure_ghost_save(summary: Dictionary) -> void:
	if ghost_save_container == null:
		return
	var available: bool = not summary.is_empty()
	ghost_save_container.visible = available
	if not available:
		return
	var tick_rate: int = int(summary.get("tick_rate", GhostDataManager.LEGACY_TICK_RATE))
	var sample_count: int = int(summary.get("sample_count", 0))
	if label_ghost_save != null:
		label_ghost_save.text = "UNSAVED GHOST  |  %d Hz  |  %d samples\nSave it now, or choose another action to discard it." % [tick_rate, sample_count]
	if button_save_ghost != null:
		button_save_ghost.disabled = false
		button_save_ghost.text = "Save Ghost"


func set_ghost_save_result(saved_path: String) -> void:
	if saved_path.strip_edges() == "":
		if label_ghost_save != null:
			label_ghost_save.text = "Ghost could not be saved. The run is still available to retry."
		if button_save_ghost != null:
			button_save_ghost.disabled = false
			button_save_ghost.text = "Retry Save"
		return
	if label_ghost_save != null:
		label_ghost_save.text = "GHOST SAVED  |  %s" % saved_path.get_file()
	if button_save_ghost != null:
		button_save_ghost.disabled = true
		button_save_ghost.text = "Saved"


func set_restart_label(text_value: String) -> void:
	if button_restart != null:
		button_restart.text = text_value


func consume_skip() -> bool:
	var was_requested: bool = _skip_requested
	_skip_requested = false
	return was_requested


func wait_or_skip(delay: float) -> void:
	_skip_requested = false
	var remaining: float = max(delay, 0.0)
	while remaining > 0.0:
		if _skip_requested:
			_skip_requested = false
			_accelerate_active_tweens()
			remaining = min(remaining, max(skip_remaining_time, 0.0))
		var step: float = min(0.05, remaining)
		remaining -= step
		if get_tree() == null:
			break
		await get_tree().create_timer(step).timeout
	_skip_requested = false


func format_time(seconds_value: float) -> String:
	var elapsed: float = max(seconds_value, 0.0)
	var total_seconds: int = int(elapsed)
	var minutes: int = int(total_seconds / 60)
	var seconds: int = total_seconds % 60
	var hundredths: int = int((elapsed - total_seconds) * 100.0) % 100
	return "%02d:%02d:%02d" % [minutes, seconds, hundredths]


func _set_result_text(
		rings_value: int,
		time_seconds: float,
		score_value: int,
		places_bbcode: String,
		is_new_record: bool,
		extra_note: String
	) -> void:
	if panel_results != null:
		panel_results.visible = true
	if label_results != null:
		var note_text: String = ""
		if extra_note.strip_edges() != "":
			note_text = "\n%s" % extra_note
		var color_html: String = _foreground_color.to_html(false)
		label_results.text = (
			"[center][font_size=38][color=#%s][b]RACE RESULTS[/b][/color][/font_size][/center]"
			+ "\n\nRings: %d\nTime: %s\nScore: %d%s%s"
		) % [
			color_html,
			rings_value,
			format_time(time_seconds),
			score_value,
			places_bbcode,
			note_text,
		]
		label_results.scroll_to_line(0)
	if label_new_record != null:
		label_new_record.visible = is_new_record
	call_deferred("_animate_results_in", is_new_record)


func _animate_results_in(is_new_record: bool) -> void:
	if panel_results == null or not panel_results.visible:
		return
	_track_tween(UIExcitementEffects.sweep_in(
		panel_results,
		Vector2(300.0, 90.0),
		results_enter_duration,
		0.9
	))
	_track_tween(UIExcitementEffects.reveal_text(label_results, results_reveal_duration))
	if is_new_record and label_new_record != null:
		_track_tween(UIExcitementEffects.pulse_in(label_new_record, 0.55, 0.3, 1.16))


func _pulse_countdown_text(is_go: bool) -> void:
	if label_countdown == null:
		return
	if _countdown_text_tween != null and _countdown_text_tween.is_valid():
		_countdown_text_tween.kill()
	var start_scale: float = 0.5 if is_go else 0.62
	var overshoot: float = 1.14 if is_go else 1.08
	_countdown_text_tween = UIExcitementEffects.pulse_in(
		label_countdown,
		0.34,
		start_scale,
		overshoot
	)
	_track_tween(_countdown_text_tween)


func _request_speedup() -> void:
	_skip_requested = true
	_accelerate_active_tweens()


func _accelerate_active_tweens() -> void:
	_prune_active_tweens()
	UIExcitementEffects.accelerate_tweens(_active_tweens, skip_animation_speed)


func _track_tween(tween: Tween) -> void:
	if tween == null:
		return
	_active_tweens.append(tween)


func _prune_active_tweens() -> void:
	for index: int in range(_active_tweens.size() - 1, -1, -1):
		var tween: Tween = _active_tweens[index]
		if tween == null or not tween.is_valid() or not tween.is_running():
			_active_tweens.remove_at(index)


func _kill_active_tweens() -> void:
	for tween: Tween in _active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_active_tweens.clear()


func _prepare_panel_styles() -> void:
	_countdown_style = _duplicate_panel_style(panel_countdown)
	_results_style = _duplicate_panel_style(panel_results)
	_options_style = _duplicate_panel_style(panel_options)


func _duplicate_panel_style(panel: Control) -> StyleBoxFlat:
	if panel == null:
		return null
	var configured_style: StyleBox = panel.get_theme_stylebox("panel")
	if not (configured_style is StyleBoxFlat):
		return null
	var duplicated_style: StyleBoxFlat = configured_style.duplicate() as StyleBoxFlat
	panel.add_theme_stylebox_override("panel", duplicated_style)
	return duplicated_style


func _resolve_character_colors() -> void:
	if get_tree() != null:
		for node: Node in get_tree().get_nodes_in_group("HUDNotificationStack"):
			if node is HUDMusicTrackDisplay:
				_primary_color = (node as HUDMusicTrackDisplay).get_primary_color()
				break
	_foreground_color = _primary_color.lightened(0.38)
	if _countdown_style != null:
		_countdown_style.border_color = _primary_color
	if _results_style != null:
		_results_style.border_color = _primary_color
	if _options_style != null:
		_options_style.border_color = _primary_color
	if label_level != null:
		label_level.add_theme_color_override("font_color", _foreground_color)
	if label_countdown != null:
		label_countdown.add_theme_color_override("font_color", _foreground_color)
	if label_results != null:
		label_results.add_theme_color_override("default_color", _foreground_color)
	if label_ghost_save != null:
		label_ghost_save.add_theme_color_override("font_color", _foreground_color)


func _on_stay_pressed() -> void:
	_emit_option_and_close(&"stay")


func _on_return_hub_pressed() -> void:
	_emit_option_and_close(&"return_hub")


func _on_restart_race_pressed() -> void:
	_emit_option_and_close(&"restart_race")


func _on_return_menu_pressed() -> void:
	_emit_option_and_close(&"return_menu")


func _on_save_ghost_pressed() -> void:
	if button_save_ghost != null:
		button_save_ghost.disabled = true
		button_save_ghost.text = "Saving..."
	ghost_save_requested.emit()


func _emit_option_and_close(option: StringName) -> void:
	option_selected.emit(option)
	visible = false
	queue_free()

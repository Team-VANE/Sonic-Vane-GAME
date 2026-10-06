extends CanvasLayer

signal start_requested(dnf_seconds: float, join_seconds: float, race_ghost_enabled: bool, record_ghost_enabled: bool, selected_ghost_path: String, multiple_ghosts_enabled: bool, ghost_count: int, combo_system_enabled: bool)
signal canceled()

const _GHOST_DIALOG_SCENE: PackedScene = preload("res://LS5Framework/Scenes/Race/GhostSelectionDialog.tscn")
const MIN_GHOST_COUNT: int = 2
const MAX_GHOST_COUNT: int = 20
const DEFAULT_GHOST_COUNT: int = 3

@export var dnf_min_sec: float = 30.0
@export var dnf_max_sec: float = 300.0
@export var dnf_step_sec: float = 5.0
@export var join_min_sec: float = 5.0
@export var join_max_sec: float = 120.0
@export var join_step_sec: float = 5.0

@onready var slider_dnf: HSlider = get_node_or_null("Root/Panel/VBox/Options/DNF/Slider")
@onready var label_dnf_value: Label = get_node_or_null("Root/Panel/VBox/Options/DNF/Value")
@onready var slider_join: HSlider = get_node_or_null("Root/Panel/VBox/Options/Join/Slider")
@onready var label_join_value: Label = get_node_or_null("Root/Panel/VBox/Options/Join/Value")
@onready var check_race_ghost: CheckBox = get_node_or_null("Root/Panel/VBox/Options/Ghosts/RaceGhost")
## Enables the ranked multi-ghost lineup preference.
@onready var check_multiple_ghosts: CheckBox = get_node_or_null("Root/Panel/VBox/Options/Ghosts/MultipleGhosts")
## Sets the maximum number of ghosts in a multi-ghost lineup.
@onready var slider_ghost_count: HSlider = get_node_or_null("Root/Panel/VBox/Options/Ghosts/GhostCount/Slider")
## Displays the selected multi-ghost lineup size.
@onready var label_ghost_count: Label = get_node_or_null("Root/Panel/VBox/Options/Ghosts/GhostCount/Value")
## Displays the persistent recording and playback quality preferences used by this race.
@onready var label_recording_status: Label = get_node_or_null("Root/Panel/VBox/Options/Ghosts/RecordingStatus")
@onready var check_combo_system: CheckBox = get_node_or_null("Root/Panel/VBox/Options/ComboSystem")
@onready var label_ghost_selection: Label = get_node_or_null("Root/Panel/VBox/Options/Ghosts/Selection")
@onready var label_ghost_rules: Label = get_node_or_null("Root/Panel/VBox/Options/Ghosts/Rules")
@onready var button_choose_ghost: Button = get_node_or_null("Root/Panel/VBox/Options/Ghosts/ChooseGhost")
@onready var button_start: Button = get_node_or_null("Root/Panel/VBox/Buttons/StartRace")
@onready var button_cancel: Button = get_node_or_null("Root/Panel/VBox/Buttons/Cancel")

var _ghosts_allowed: bool = false
var _ghosts_locked_by_online: bool = false
var _ghost_rules_text: String = GhostDataManager.get_race_id_rules_text()
var _level_display_name: String = "Level"
var _ghost_race_id: String = ""
var _available_ghosts: Array = []
var _selected_ghost_path: String = ""
var _best_ghost_path: String = ""
var _ghost_dialog = null
var _ghost_dialog_focus_modes: Dictionary = {}
var _record_ghost_enabled: bool = false
var _recording_tick_rate: int = GhostDataManager.DEFAULT_TICK_RATE
var _playback_tick_rate: int = GhostDataManager.DEFAULT_PLAYBACK_TICK_RATE
var _race_ghost_preference: bool = false
var _multiple_ghosts_preference: bool = false
var _ghost_count_preference: int = DEFAULT_GHOST_COUNT

func _ready() -> void:
	layer = 60
	visible = true
	add_to_group("ModalMenu")
	set_process_unhandled_input(true)
	_configure_sliders()
	_sync_labels()
	_wire_signals()
	_sync_ghost_controls()
	call_deferred("_focus_default_control")

func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	if _ghost_dialog != null and is_instance_valid(_ghost_dialog):
		return
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")
	if not cancel_pressed and event is InputEventKey:
		var key := event as InputEventKey
		cancel_pressed = key.pressed and key.keycode == Key.KEY_ESCAPE
	if not cancel_pressed:
		return
	get_viewport().set_input_as_handled()
	_cancel()

func set_values(dnf_seconds: float, join_seconds: float, race_ghost_enabled: bool = false, record_ghost_enabled: bool = false, selected_ghost_path: String = "", combo_system_enabled: bool = true, recording_tick_rate: int = GhostDataManager.DEFAULT_TICK_RATE, playback_tick_rate: int = GhostDataManager.DEFAULT_PLAYBACK_TICK_RATE, multiple_ghosts_enabled: bool = false, ghost_count: int = DEFAULT_GHOST_COUNT) -> void:
	if slider_dnf != null:
		slider_dnf.set_value_no_signal(clamp(dnf_seconds, dnf_min_sec, dnf_max_sec))
	if slider_join != null:
		slider_join.set_value_no_signal(clamp(join_seconds, join_min_sec, join_max_sec))
	_race_ghost_preference = race_ghost_enabled
	_multiple_ghosts_preference = multiple_ghosts_enabled
	_ghost_count_preference = clampi(ghost_count, MIN_GHOST_COUNT, MAX_GHOST_COUNT)
	if check_race_ghost != null:
		check_race_ghost.set_pressed_no_signal(_race_ghost_preference)
	if check_multiple_ghosts != null:
		check_multiple_ghosts.set_pressed_no_signal(_multiple_ghosts_preference)
	if slider_ghost_count != null:
		slider_ghost_count.set_value_no_signal(float(_ghost_count_preference))
	_record_ghost_enabled = record_ghost_enabled
	_recording_tick_rate = GhostDataManager.normalize_recording_tick_rate(recording_tick_rate)
	_playback_tick_rate = GhostDataManager.normalize_recording_tick_rate(playback_tick_rate)
	if check_combo_system != null:
		check_combo_system.set_pressed_no_signal(combo_system_enabled)
	_selected_ghost_path = selected_ghost_path
	_sync_labels()
	_sync_ghost_controls()

func configure_ghosts(level_display_name: String, ghosts_allowed: bool, is_online: bool, ghosts: Array, selected_path: String, best_path: String, race_id: String, rules_text: String) -> void:
	_level_display_name = level_display_name
	_ghosts_allowed = ghosts_allowed
	_ghosts_locked_by_online = is_online
	_available_ghosts = ghosts.duplicate(true)
	_selected_ghost_path = selected_path
	_best_ghost_path = best_path
	_ghost_race_id = race_id
	_ghost_rules_text = rules_text
	_sync_ghost_controls()

func _configure_sliders() -> void:
	if slider_dnf != null:
		slider_dnf.min_value = dnf_min_sec
		slider_dnf.max_value = dnf_max_sec
		slider_dnf.step = dnf_step_sec
		slider_dnf.value = clamp(slider_dnf.value, dnf_min_sec, dnf_max_sec)
	if slider_join != null:
		slider_join.min_value = join_min_sec
		slider_join.max_value = join_max_sec
		slider_join.step = join_step_sec
		slider_join.value = clamp(slider_join.value, join_min_sec, join_max_sec)
	if slider_ghost_count != null:
		slider_ghost_count.min_value = float(MIN_GHOST_COUNT)
		slider_ghost_count.max_value = float(MAX_GHOST_COUNT)
		slider_ghost_count.step = 1.0
		slider_ghost_count.value = float(clampi(int(slider_ghost_count.value), MIN_GHOST_COUNT, MAX_GHOST_COUNT))

func _wire_signals() -> void:
	if slider_dnf != null and not slider_dnf.value_changed.is_connected(_on_dnf_changed):
		slider_dnf.value_changed.connect(_on_dnf_changed)
	if slider_join != null and not slider_join.value_changed.is_connected(_on_join_changed):
		slider_join.value_changed.connect(_on_join_changed)
	if check_race_ghost != null and not check_race_ghost.toggled.is_connected(_on_race_ghost_toggled):
		check_race_ghost.toggled.connect(_on_race_ghost_toggled)
	if check_multiple_ghosts != null and not check_multiple_ghosts.toggled.is_connected(_on_multiple_ghosts_toggled):
		check_multiple_ghosts.toggled.connect(_on_multiple_ghosts_toggled)
	if slider_ghost_count != null and not slider_ghost_count.value_changed.is_connected(_on_ghost_count_changed):
		slider_ghost_count.value_changed.connect(_on_ghost_count_changed)
	if check_combo_system != null and not check_combo_system.toggled.is_connected(_on_combo_system_toggled):
		check_combo_system.toggled.connect(_on_combo_system_toggled)
	if button_choose_ghost != null and not button_choose_ghost.pressed.is_connected(_on_choose_ghost_pressed):
		button_choose_ghost.pressed.connect(_on_choose_ghost_pressed)
	if button_start != null and not button_start.pressed.is_connected(_on_start_pressed):
		button_start.pressed.connect(_on_start_pressed)
	if button_cancel != null and not button_cancel.pressed.is_connected(_on_cancel_pressed):
		button_cancel.pressed.connect(_on_cancel_pressed)

func _on_dnf_changed(_value: float) -> void:
	_sync_labels()
	_persist_settings()

func _on_join_changed(_value: float) -> void:
	_sync_labels()
	_persist_settings()

func _on_race_ghost_toggled(enabled: bool) -> void:
	_race_ghost_preference = enabled
	_sync_ghost_controls()
	_persist_settings()


func _on_multiple_ghosts_toggled(enabled: bool) -> void:
	_multiple_ghosts_preference = enabled
	_sync_ghost_controls()
	_persist_settings()


func _on_ghost_count_changed(value: float) -> void:
	_ghost_count_preference = clampi(int(value), MIN_GHOST_COUNT, MAX_GHOST_COUNT)
	_sync_labels()
	_persist_settings()

func _on_combo_system_toggled(_enabled: bool) -> void:
	_persist_settings()

func _on_choose_ghost_pressed() -> void:
	if not _ghosts_allowed or _GHOST_DIALOG_SCENE == null:
		return
	if _ghost_dialog != null and is_instance_valid(_ghost_dialog):
		return
	_ghost_dialog = _GHOST_DIALOG_SCENE.instantiate()
	if _ghost_dialog == null:
		return
	var parent_node := _get_menu_parent()
	if parent_node != null:
		parent_node.add_child(_ghost_dialog)
	else:
		add_child(_ghost_dialog)
	if _ghost_dialog.has_method("configure"):
		_ghost_dialog.call("configure", _get_level_display_name(), _ghost_race_id, _available_ghosts, _selected_ghost_path)
	if _ghost_dialog.has_signal("ghost_selected"):
		_ghost_dialog.connect("ghost_selected", Callable(self, "_on_ghost_selected"))
	if _ghost_dialog.has_signal("selection_cleared"):
		_ghost_dialog.connect("selection_cleared", Callable(self, "_on_ghost_selection_cleared"))
	if _ghost_dialog.has_signal("ghost_data_changed"):
		_ghost_dialog.connect("ghost_data_changed", Callable(self, "_on_ghost_data_changed"))
	_ghost_dialog.tree_exited.connect(_on_ghost_dialog_tree_exited, CONNECT_ONE_SHOT)
	_set_race_menu_focus_enabled(false)

func _on_ghost_selected(path: String) -> void:
	_selected_ghost_path = path
	_sync_ghost_controls()
	_persist_settings()

func _on_ghost_selection_cleared() -> void:
	_selected_ghost_path = ""
	_sync_ghost_controls()
	_persist_settings()

func _on_ghost_data_changed() -> void:
	var remaining_ghosts: Array = []
	for ghost: Variant in _available_ghosts:
		if ghost is Dictionary and FileAccess.file_exists(String((ghost as Dictionary).get("path", ""))):
			remaining_ghosts.append(ghost)
	_available_ghosts = remaining_ghosts
	_best_ghost_path = String((_available_ghosts[0] as Dictionary).get("path", "")) if not _available_ghosts.is_empty() else ""
	if _selected_ghost_path != "" and not FileAccess.file_exists(_selected_ghost_path):
		_selected_ghost_path = ""
	_sync_ghost_controls()
	_persist_settings()

func _on_ghost_dialog_tree_exited() -> void:
	_ghost_dialog = null
	_set_race_menu_focus_enabled(true)
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if button_choose_ghost != null and not button_choose_ghost.disabled:
		button_choose_ghost.grab_focus()
	else:
		_focus_default_control()

func _set_race_menu_focus_enabled(enabled: bool) -> void:
	if enabled:
		for control: Control in _ghost_dialog_focus_modes:
			if is_instance_valid(control):
				control.focus_mode = int(_ghost_dialog_focus_modes[control])
		_ghost_dialog_focus_modes.clear()
		return
	var root_control: Control = get_node_or_null("Root")
	if root_control == null:
		return
	var pending: Array[Node] = [root_control]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Control:
			var control: Control = node
			if control.focus_mode != Control.FOCUS_NONE:
				_ghost_dialog_focus_modes[control] = control.focus_mode
				control.focus_mode = Control.FOCUS_NONE
		for child: Node in node.get_children():
			pending.append(child)

func _on_start_pressed() -> void:
	_close_ghost_dialog()
	_persist_settings()
	emit_signal("start_requested", _get_dnf_value(), _get_join_value(), _get_race_ghost_enabled(), _get_record_ghost_enabled(), _selected_ghost_path, _get_multiple_ghosts_enabled(), _get_ghost_count(), _get_combo_system_enabled())
	queue_free()

func _on_cancel_pressed() -> void:
	_cancel()

func _cancel() -> void:
	_close_ghost_dialog()
	emit_signal("canceled")
	queue_free()


func _focus_default_control() -> void:
	if button_start != null and button_start.is_visible_in_tree():
		button_start.grab_focus()
		return
	if slider_dnf != null and slider_dnf.is_visible_in_tree():
		slider_dnf.grab_focus()
		return
	if button_cancel != null:
		button_cancel.grab_focus()

func _get_dnf_value() -> float:
	if slider_dnf != null:
		return float(slider_dnf.value)
	return dnf_min_sec

func _get_join_value() -> float:
	if slider_join != null:
		return float(slider_join.value)
	return join_min_sec

func _get_race_ghost_enabled() -> bool:
	return _ghosts_allowed and _race_ghost_preference


func _get_multiple_ghosts_enabled() -> bool:
	return _get_race_ghost_enabled() and _multiple_ghosts_preference


func _get_ghost_count() -> int:
	return clampi(_ghost_count_preference, MIN_GHOST_COUNT, MAX_GHOST_COUNT)

func _get_record_ghost_enabled() -> bool:
	if not _ghosts_allowed:
		return false
	return _record_ghost_enabled

func _get_combo_system_enabled() -> bool:
	if check_combo_system != null:
		return check_combo_system.button_pressed
	return true

func _sync_labels() -> void:
	if label_dnf_value != null:
		label_dnf_value.text = _format_timer(_get_dnf_value())
	if label_join_value != null:
		label_join_value.text = _format_timer(_get_join_value())
	if label_ghost_count != null:
		label_ghost_count.text = str(_get_ghost_count())

func _sync_ghost_controls() -> void:
	var allowed := _ghosts_allowed
	if check_race_ghost != null:
		check_race_ghost.disabled = not allowed
		check_race_ghost.set_pressed_no_signal(_race_ghost_preference)
	var multi_controls_enabled: bool = allowed and _race_ghost_preference
	if check_multiple_ghosts != null:
		check_multiple_ghosts.disabled = not multi_controls_enabled
		check_multiple_ghosts.set_pressed_no_signal(_multiple_ghosts_preference)
	if slider_ghost_count != null:
		var ghost_count_enabled: bool = multi_controls_enabled and _multiple_ghosts_preference
		slider_ghost_count.editable = ghost_count_enabled
		slider_ghost_count.focus_mode = Control.FOCUS_ALL if ghost_count_enabled else Control.FOCUS_NONE
	if label_recording_status != null:
		if not allowed:
			label_recording_status.text = "Ghost recording: Unavailable"
		elif _record_ghost_enabled:
			label_recording_status.text = "Recording: On at %d Hz | Playback: Up to %d Hz\nSaving is optional after the race." % [_recording_tick_rate, _playback_tick_rate]
		else:
			label_recording_status.text = "Recording: Off | Playback: Up to %d Hz\nChange this persistent preference in Gameplay settings." % _playback_tick_rate
	if button_choose_ghost != null:
		button_choose_ghost.disabled = not allowed
	if label_ghost_rules != null:
		if _ghosts_locked_by_online:
			label_ghost_rules.text = "Ghost options are single-player only."
		else:
			label_ghost_rules.text = _ghost_rules_text
	if label_ghost_selection != null:
		if not allowed:
			label_ghost_selection.text = "Ghost selection: Disabled"
		elif _multiple_ghosts_preference and _race_ghost_preference:
			var primary_name: String = _selected_ghost_path.get_file() if _selected_ghost_path.strip_edges() != "" else "Best available ghost"
			label_ghost_selection.text = "Primary: %s | Slower ranked ghosts: up to %d total" % [primary_name, _get_ghost_count()]
		elif _selected_ghost_path.strip_edges() != "":
			label_ghost_selection.text = "Ghost selection: %s" % _selected_ghost_path.get_file()
		elif _best_ghost_path.strip_edges() != "":
			label_ghost_selection.text = "Ghost selection: Best available ghost"
		else:
			label_ghost_selection.text = "Ghost selection: No ghost available"

func _format_timer(seconds_value: float) -> String:
	var total := int(max(seconds_value, 0.0))
	var minutes := total / 60
	var seconds := total % 60
	if minutes > 0:
		return "%dm %02ds" % [minutes, seconds]
	return "%ds" % [seconds]

func _persist_settings() -> void:
	var settings = _get_settings_manager()
	if settings == null:
		return
	if settings.has_method("set"):
		settings.set("race_dnf_timer_sec", _get_dnf_value())
		settings.set("race_join_timer_sec", _get_join_value())
		settings.set("race_ghost_enabled", _race_ghost_preference)
		settings.set("race_multiple_ghosts_enabled", _multiple_ghosts_preference)
		settings.set("race_ghost_count", _get_ghost_count())
		settings.set("race_selected_ghost_path", _selected_ghost_path)
		settings.set("combo_system_enabled", _get_combo_system_enabled())
	if settings.has_method("save_now"):
		settings.call("save_now")

func _get_level_display_name() -> String:
	return _level_display_name


func _close_ghost_dialog() -> void:
	if _ghost_dialog != null and is_instance_valid(_ghost_dialog):
		_ghost_dialog.queue_free()
	_ghost_dialog = null


func _get_menu_parent() -> Node:
	if get_tree() != null and get_tree().current_scene != null:
		return get_tree().current_scene
	return null

func _get_settings_manager() -> Node:
	var root := get_tree().root
	if root == null:
		return null
	return root.get_node_or_null("SettingsManager")

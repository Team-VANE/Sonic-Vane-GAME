extends CanvasLayer

signal ghost_selected(path: String)
signal selection_cleared()
signal ghost_data_changed()
signal canceled()

@onready var title_label: Label = get_node_or_null("Root/Panel/VBox/Title")
@onready var info_label: Label = get_node_or_null("Root/Panel/VBox/Info")
@onready var ghost_list: ItemList = get_node_or_null("Root/Panel/VBox/MainRow/ListColumn/GhostList")
@onready var detail_label: RichTextLabel = get_node_or_null("Root/Panel/VBox/MainRow/ListColumn/Details")
@onready var button_select: Button = get_node_or_null("Root/Panel/VBox/MainRow/ActionColumn/Select")
@onready var button_use_best: Button = get_node_or_null("Root/Panel/VBox/MainRow/ActionColumn/UseBest")
@onready var button_clear: Button = get_node_or_null("Root/Panel/VBox/MainRow/ActionColumn/Clear")
@onready var button_cancel: Button = get_node_or_null("Root/Panel/VBox/MainRow/ActionColumn/Cancel")
@onready var button_delete_selected: Button = get_node_or_null("Root/Panel/VBox/MainRow/ActionColumn/DeleteSelected")
@onready var button_clear_all: Button = get_node_or_null("Root/Panel/VBox/MainRow/ActionColumn/ClearAll")
@onready var confirm_dialog: Control = get_node_or_null("Root/ConfirmDialog")
@onready var confirm_title: Label = get_node_or_null("Root/ConfirmDialog/WarningFrame/Margin/Content/Title")
@onready var confirm_body: Label = get_node_or_null("Root/ConfirmDialog/WarningFrame/Margin/Content/Body")
@onready var button_confirm_delete: Button = get_node_or_null("Root/ConfirmDialog/WarningFrame/Margin/Content/Buttons/Confirm")
@onready var button_cancel_delete: Button = get_node_or_null("Root/ConfirmDialog/WarningFrame/Margin/Content/Buttons/Cancel")
@onready var sfx_warning: AudioStreamPlayer = get_node_or_null("SfxWarning")

var _ghosts: Array = []
var _selected_path: String = ""
var _level_name: String = ""
var _level_ghost_count: int = 0
var _delete_mode: StringName = &""
var _delete_path: String = ""
var _picker_focus_modes: Dictionary = {}
var _focus_before_confirmation: Control = null


func _ready() -> void:
	layer = 80
	visible = true
	add_to_group("ModalMenu")
	set_process_unhandled_input(true)
	_wire_signals()
	_refresh_buttons()
	_update_details()
	call_deferred("_focus_default_control")


func configure(level_name: String, race_id: String, ghosts: Array, selected_path: String) -> void:
	_level_name = level_name
	_ghosts = ghosts.duplicate(true)
	_selected_path = selected_path
	_level_ghost_count = GhostDataManager.list_ghost_paths_for_level(_level_name, "").size()
	if title_label != null:
		title_label.text = "Choose Ghost"
	if info_label != null:
		info_label.text = "%s\nRace ID: %s" % [level_name, race_id]
	_populate_list()
	_select_path(selected_path)
	_refresh_buttons()
	_update_details()
	call_deferred("_focus_default_control")


func _input(event: InputEvent) -> void:
	if event == null:
		return
	if event.is_echo():
		return
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")
	if not cancel_pressed and event is InputEventKey:
		var key := event as InputEventKey
		cancel_pressed = key.pressed and key.keycode == Key.KEY_ESCAPE
	if cancel_pressed:
		get_viewport().set_input_as_handled()
		if confirm_dialog != null and confirm_dialog.visible:
			_close_confirmation()
			return
		_cancel()
		return
	if confirm_dialog != null and confirm_dialog.visible:
		return
	if ghost_list == null or ghost_list.item_count == 0 or get_viewport().gui_get_focus_owner() != ghost_list:
		return
	if event.is_action_pressed("ui_right") or (event.is_action_pressed("ui_down") and _get_selected_index() >= ghost_list.item_count - 1):
		get_viewport().set_input_as_handled()
		_focus_list_exit()


func _wire_signals() -> void:
	if ghost_list != null:
		if not ghost_list.item_selected.is_connected(_on_item_selected):
			ghost_list.item_selected.connect(_on_item_selected)
		if not ghost_list.item_activated.is_connected(_on_item_activated):
			ghost_list.item_activated.connect(_on_item_activated)
	if button_select != null and not button_select.pressed.is_connected(_on_select_pressed):
		button_select.pressed.connect(_on_select_pressed)
	if button_use_best != null and not button_use_best.pressed.is_connected(_on_use_best_pressed):
		button_use_best.pressed.connect(_on_use_best_pressed)
	if button_clear != null and not button_clear.pressed.is_connected(_on_clear_pressed):
		button_clear.pressed.connect(_on_clear_pressed)
	if button_cancel != null and not button_cancel.pressed.is_connected(_on_cancel_pressed):
		button_cancel.pressed.connect(_on_cancel_pressed)
	if button_delete_selected != null and not button_delete_selected.pressed.is_connected(_on_delete_selected_pressed):
		button_delete_selected.pressed.connect(_on_delete_selected_pressed)
	if button_clear_all != null and not button_clear_all.pressed.is_connected(_on_clear_all_pressed):
		button_clear_all.pressed.connect(_on_clear_all_pressed)
	if button_confirm_delete != null and not button_confirm_delete.pressed.is_connected(_on_confirm_delete_pressed):
		button_confirm_delete.pressed.connect(_on_confirm_delete_pressed)
	if button_cancel_delete != null and not button_cancel_delete.pressed.is_connected(_close_confirmation):
		button_cancel_delete.pressed.connect(_close_confirmation)


func _populate_list() -> void:
	if ghost_list == null:
		return
	ghost_list.clear()
	for ghost in _ghosts:
		if not (ghost is Dictionary):
			continue
		var entry: Dictionary = ghost
		var file_name := String(entry.get("file_name", "ghost"))
		var finish_time := String(entry.get("formatted_time", entry.get("finish_time", "")))
		var score := int(entry.get("score", 0))
		var tick_rate: int = int(entry.get("tick_rate", GhostDataManager.LEGACY_TICK_RATE))
		ghost_list.add_item("%s  |  %d Hz  |  %s  |  Score %d" % [finish_time, tick_rate, file_name, score])
		ghost_list.set_item_custom_fg_color(ghost_list.item_count - 1, Color(0.94, 0.97, 1.0, 1.0))
	if not _ghosts.is_empty() and _get_selected_index() < 0:
		_select_path(String((_ghosts[0] as Dictionary).get("path", "")))


func _select_path(path: String) -> void:
	_selected_path = path
	if ghost_list == null:
		return
	if path.strip_edges() == "":
		ghost_list.deselect_all()
		return
	for i in range(_ghosts.size()):
		var ghost = _ghosts[i]
		if ghost is Dictionary and String((ghost as Dictionary).get("path", "")) == path:
			ghost_list.select(i)
			ghost_list.ensure_current_is_visible()
			return
	ghost_list.deselect_all()


func _refresh_buttons() -> void:
	var has_ghosts := not _ghosts.is_empty()
	if button_select != null:
		button_select.disabled = _get_selected_index() < 0
	if button_use_best != null:
		button_use_best.disabled = not has_ghosts
	if button_clear != null:
		button_clear.disabled = _selected_path.strip_edges() == ""
	if button_delete_selected != null:
		button_delete_selected.disabled = _get_selected_index() < 0
	if button_clear_all != null:
		button_clear_all.disabled = _level_ghost_count == 0
	_update_action_focus()


func _update_action_focus() -> void:
	var available: Array[Button] = []
	for button: Button in [button_select, button_use_best, button_clear, button_delete_selected, button_clear_all, button_cancel]:
		if button != null and not button.disabled:
			available.append(button)
	for index: int in range(available.size()):
		var button: Button = available[index]
		button.focus_neighbor_top = button.get_path_to(available[(index - 1 + available.size()) % available.size()])
		button.focus_neighbor_bottom = button.get_path_to(available[(index + 1) % available.size()])


func _update_details() -> void:
	if detail_label == null:
		return
	var idx := _get_selected_index()
	if idx < 0 or idx >= _ghosts.size():
		detail_label.text = "[center]No ghost selected.[/center]"
		return
	var ghost = _ghosts[idx]
	if not (ghost is Dictionary):
		detail_label.text = "[center]No ghost selected.[/center]"
		return
	var entry: Dictionary = ghost
	var path := String(entry.get("path", ""))
	_selected_path = path
	var finish_time := String(entry.get("formatted_time", entry.get("finish_time", "")))
	var score := int(entry.get("score", 0))
	var created := String(entry.get("created_at_text", ""))
	var file_name := String(entry.get("file_name", "ghost"))
	var tick_rate: int = int(entry.get("tick_rate", GhostDataManager.LEGACY_TICK_RATE))
	var sample_count: int = int(entry.get("sample_count", 0))
	detail_label.text = "[center][b]%s[/b]\nTime: %s | Score: %d\nCapture: %d Hz | %d samples\nSaved: %s[/center]" % [file_name, finish_time, score, tick_rate, sample_count, created]


func _get_selected_index() -> int:
	if ghost_list == null:
		return -1
	var selected := ghost_list.get_selected_items()
	if selected.is_empty():
		return -1
	return int(selected[0])


func _on_item_selected(_index: int) -> void:
	_update_details()
	_refresh_buttons()


func _on_item_activated(_index: int) -> void:
	_on_select_pressed()


func _on_select_pressed() -> void:
	var idx := _get_selected_index()
	if idx < 0 or idx >= _ghosts.size():
		return
	var ghost = _ghosts[idx]
	if not (ghost is Dictionary):
		return
	var path := String((ghost as Dictionary).get("path", ""))
	if path.strip_edges() == "":
		return
	emit_signal("ghost_selected", path)
	queue_free()


func _on_use_best_pressed() -> void:
	if _ghosts.is_empty():
		return
	if ghost_list != null:
		ghost_list.select(0)
	_update_details()
	_refresh_buttons()
	_on_select_pressed()


func _on_clear_pressed() -> void:
	_selected_path = ""
	emit_signal("selection_cleared")
	queue_free()


func _on_delete_selected_pressed() -> void:
	var index: int = _get_selected_index()
	if index < 0 or index >= _ghosts.size():
		return
	var entry: Dictionary = _ghosts[index]
	var path: String = String(entry.get("path", ""))
	if path == "":
		return
	_show_confirmation(&"selected", path)


func _on_clear_all_pressed() -> void:
	if _level_ghost_count == 0:
		return
	_show_confirmation(&"level", "")


func _show_confirmation(mode: StringName, path: String) -> void:
	if confirm_dialog == null or button_cancel_delete == null:
		return
	_delete_mode = mode
	_delete_path = path
	_focus_before_confirmation = get_viewport().gui_get_focus_owner()
	if mode == &"level":
		confirm_title.text = "CLEAR LEVEL GHOST DATA?"
		confirm_body.text = "Delete all %d saved ghost files for %s, across its races? This cannot be undone." % [_level_ghost_count, _level_name]
		button_confirm_delete.text = "Clear Level"
	else:
		confirm_title.text = "DELETE THIS GHOST?"
		confirm_body.text = "Delete %s? This cannot be undone." % path.get_file()
		button_confirm_delete.text = "Delete"
	_picker_focus_modes.clear()
	for control: Control in [ghost_list, button_select, button_use_best, button_clear, button_cancel, button_delete_selected, button_clear_all]:
		if control != null:
			_picker_focus_modes[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	confirm_dialog.visible = true
	button_cancel_delete.grab_focus()
	if sfx_warning != null and sfx_warning.stream != null:
		sfx_warning.play()


func _close_confirmation() -> void:
	if confirm_dialog != null:
		confirm_dialog.visible = false
	for control: Control in _picker_focus_modes:
		if is_instance_valid(control):
			control.focus_mode = int(_picker_focus_modes[control])
	_picker_focus_modes.clear()
	_delete_mode = &""
	_delete_path = ""
	if _focus_before_confirmation != null and is_instance_valid(_focus_before_confirmation) and _focus_before_confirmation.focus_mode != Control.FOCUS_NONE and not (_focus_before_confirmation is BaseButton and (_focus_before_confirmation as BaseButton).disabled):
		_focus_before_confirmation.grab_focus()
	else:
		_focus_default_control()
	_focus_before_confirmation = null


func _on_confirm_delete_pressed() -> void:
	if confirm_dialog == null or not confirm_dialog.visible:
		return
	var mode: StringName = _delete_mode
	var path: String = _delete_path
	_close_confirmation()
	var failed_count: int = 0
	if mode == &"selected":
		var error: Error = GhostDataManager.delete_ghost(path)
		if error != OK:
			failed_count = 1
	elif mode == &"level":
		var result: Dictionary = GhostDataManager.delete_ghosts_for_level(_level_name, "")
		failed_count = (result.get("failed", []) as Array).size()
	else:
		return
	var remaining_ghosts: Array = []
	for ghost: Variant in _ghosts:
		if ghost is Dictionary and FileAccess.file_exists(String((ghost as Dictionary).get("path", ""))):
			remaining_ghosts.append(ghost)
	_ghosts = remaining_ghosts
	_level_ghost_count = GhostDataManager.list_ghost_paths_for_level(_level_name, "").size()
	if _selected_path != "" and not FileAccess.file_exists(_selected_path):
		_selected_path = ""
	_populate_list()
	_update_details()
	_refresh_buttons()
	ghost_data_changed.emit()
	if failed_count > 0 and detail_label != null:
		detail_label.text = "[center][color=#ff9099]Could not delete %d ghost file(s).[/color][/center]" % failed_count
	_focus_default_control()


func _on_cancel_pressed() -> void:
	_cancel()


func _cancel() -> void:
	emit_signal("canceled")
	queue_free()


func _focus_default_control() -> void:
	if ghost_list != null and ghost_list.item_count > 0:
		ghost_list.grab_focus()
		if _get_selected_index() < 0 and ghost_list.item_count > 0:
			ghost_list.select(0)
			_update_details()
			_refresh_buttons()
		return
	if button_clear_all != null and not button_clear_all.disabled:
		button_clear_all.grab_focus()
		return
	if button_cancel != null:
		button_cancel.grab_focus()
		return
	if button_select != null:
		button_select.grab_focus()


func _focus_list_exit() -> void:
	for button: Button in [button_select, button_use_best, button_clear, button_cancel, button_delete_selected, button_clear_all]:
		if button != null and not button.disabled:
			button.grab_focus()
			return

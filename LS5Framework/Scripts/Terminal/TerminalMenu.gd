extends CanvasLayer

signal level_selected(entry: Dictionary)
signal character_selected(entry: Dictionary)
signal buddy_selected(entry: Dictionary)
signal buddy_despawn_requested()
signal canceled()

@export var title_text: String = "Terminal"
@export var level_data_dir: String = ""
## Directory where CHAR_*.tres character docs live.
@export var character_data_dir: String = "res://LS5Framework/Characters"

@onready var panel: Panel = get_node_or_null("Root/Panel")
@onready var vbox: VBoxContainer = get_node_or_null("Root/Panel/VBox")

var _level_entries: Array = []
var _character_entries: Array = []
var _pack_wait_attempts: int = 0
var _level_list_waiting_for_packs: bool = false
var _current_screen: StringName = &"parent"


func _ready() -> void:
	layer = 60
	visible = true
	add_to_group("ModalMenu")
	set_process(true)
	set_process_unhandled_input(true)
	_ensure_content_pack_manager()
	_resolve_level_data_dir()
	_show_parent_menu()
	call_deferred("_focus_default_control")


func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")
	if not cancel_pressed and event is InputEventKey:
		var key := event as InputEventKey
		cancel_pressed = key.pressed and key.keycode == Key.KEY_ESCAPE
	if not cancel_pressed:
		return
	get_viewport().set_input_as_handled()
	if _current_screen != &"parent":
		_show_parent_menu()
	else:
		_cancel()


func _process(delta: float) -> void:
	var scroll_input: float = SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", SettingsManager.get_right_stick_deadzone(), &"gamepad")
	if absf(scroll_input) < 0.05:
		return
	var scroll_container: ScrollContainer = _get_scroll_container()
	if scroll_container == null:
		return
	var scroll_bar: VScrollBar = scroll_container.get_v_scroll_bar()
	if scroll_bar == null:
		return
	var new_scroll: float = float(scroll_container.scroll_vertical) - scroll_input * 900.0 * delta
	scroll_container.scroll_vertical = int(clamp(new_scroll, 0.0, scroll_bar.max_value))


func set_level_entries(entries: Array) -> void:
	_level_entries = entries.duplicate(true)
	if _current_screen == &"level":
		_build_level_list()


func _resolve_level_data_dir() -> void:
	if level_data_dir.strip_edges() != "":
		return
	var level_manager := _get_level_manager()
	if level_manager != null:
		var raw_dir = level_manager.get("level_data_dir")
		if raw_dir is String and String(raw_dir).strip_edges() != "":
			level_data_dir = String(raw_dir)
	if level_data_dir.strip_edges() == "":
		level_data_dir = "res://LS5Framework/Scenes/Levels"


func _show_parent_menu() -> void:
	_current_screen = &"parent"
	_clear_vbox()
	_add_title(_get_title_text())
	_add_button("Character Select", Callable(self, "_show_character_select"))
	_add_button("Buddies", Callable(self, "_show_buddy_select"))
	_add_button("Level Select", Callable(self, "_show_level_select"))
	_add_spacer()
	_add_button("Cancel", Callable(self, "_on_cancel_pressed"))
	_add_hint("Esc to cancel")
	call_deferred("_focus_default_control")


func _show_character_select() -> void:
	_current_screen = &"character"
	_clear_vbox()
	_add_title("Select a Character")
	var list: VBoxContainer = _add_scroll_list()
	_character_entries = CharacterCatalog.load_character_entries(character_data_dir)
	var selected_id: String = SettingsManager.chosen_character_id
	var buddy_marker_id: String = SettingsManager.chosen_buddy_character_id if SettingsManager.buddy_active else ""
	var added: int = MenuSelectList.populate(
		list,
		_character_entries,
		selected_id,
		Callable(self, "_on_character_entry_pressed"),
		&"MenuButtons",
		Callable(self, "_on_character_entry_right_pressed"),
		buddy_marker_id,
		"Buddy"
	)
	if added <= 0:
		_add_empty_label("No characters found")
	_add_back_buttons()
	call_deferred("_focus_default_control")


func _show_buddy_select() -> void:
	_current_screen = &"buddy"
	_clear_vbox()
	_add_title("Buddies")
	var list: VBoxContainer = _add_scroll_list()
	_character_entries = CharacterCatalog.load_character_entries(character_data_dir)
	var selected_id: String = SettingsManager.chosen_buddy_character_id if SettingsManager.buddy_active else ""
	var added: int = MenuSelectList.populate(
		list,
		_character_entries,
		selected_id,
		Callable(self, "_on_buddy_entry_pressed"),
		&"MenuButtons"
	)
	if added <= 0:
		_add_empty_label("No characters found")
	var buttons: HBoxContainer = _add_back_buttons(false)
	var despawn: Button = Button.new()
	despawn.text = "Despawn"
	despawn.pressed.connect(_on_buddy_despawn_pressed)
	buttons.add_child(despawn)
	call_deferred("_focus_default_control")


func _show_level_select() -> void:
	_current_screen = &"level"
	_clear_vbox()
	_add_title("Select a Level")
	_add_scroll_list()
	_add_back_buttons()
	call_deferred("_build_level_list_after_packs")
	call_deferred("_focus_default_control")


func _build_level_list_after_packs() -> void:
	if _current_screen != &"level":
		return
	var pack_manager: Node = _get_content_pack_manager()
	if pack_manager == null:
		_build_level_list()
		return
	if pack_manager.has_method("are_packs_loaded"):
		var loaded = pack_manager.call("are_packs_loaded")
		if loaded is bool and bool(loaded):
			_build_level_list()
			return
	if not _level_list_waiting_for_packs:
		_level_list_waiting_for_packs = true
		if pack_manager.has_signal("packs_loaded"):
			if not pack_manager.packs_loaded.is_connected(_on_packs_loaded):
				pack_manager.packs_loaded.connect(_on_packs_loaded)
			return
	_pack_wait_attempts += 1
	if _pack_wait_attempts >= 120:
		_build_level_list()
		return
	call_deferred("_build_level_list_after_packs")


func _on_packs_loaded() -> void:
	_level_list_waiting_for_packs = false
	if _current_screen == &"level":
		_build_level_list()


func _build_level_list() -> void:
	if _current_screen != &"level":
		return
	var list: VBoxContainer = _get_active_list()
	if list == null:
		return
	if _level_entries.is_empty():
		_level_entries = LevelCatalog.load_level_entries(level_data_dir)
	var added: int = MenuSelectList.populate(list, _level_entries, "", Callable(self, "_on_level_entry_pressed"))
	if added <= 0:
		_add_empty_label("No levels found")
	call_deferred("_focus_default_control")


func _on_character_entry_pressed(entry: Dictionary) -> void:
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	SettingsManager.set_chosen_character_id(character_id)
	SettingsManager.save_now()
	emit_signal("character_selected", entry)
	_show_parent_menu()


func _on_character_entry_right_pressed(entry: Dictionary) -> void:
	_toggle_buddy_entry(entry)


func _on_buddy_entry_pressed(entry: Dictionary) -> void:
	_activate_buddy_entry(entry)
	_show_buddy_select()


func _on_buddy_despawn_pressed() -> void:
	SettingsManager.set_buddy_active(false)
	SettingsManager.save_now()
	emit_signal("buddy_despawn_requested")
	_show_buddy_select()


func _toggle_buddy_entry(entry: Dictionary) -> void:
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	if SettingsManager.buddy_active and SettingsManager.chosen_buddy_character_id.nocasecmp_to(character_id) == 0:
		SettingsManager.set_buddy_active(false)
		SettingsManager.save_now()
		emit_signal("buddy_despawn_requested")
	else:
		_activate_buddy_entry(entry)
	if _current_screen == &"character":
		_show_character_select()
	elif _current_screen == &"buddy":
		_show_buddy_select()


func _activate_buddy_entry(entry: Dictionary) -> void:
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	SettingsManager.set_chosen_buddy_character_id(character_id)
	SettingsManager.set_buddy_active(true)
	SettingsManager.save_now()
	emit_signal("buddy_selected", entry)


func _on_level_entry_pressed(entry: Dictionary) -> void:
	emit_signal("level_selected", entry)


func _add_title(text: String) -> Label:
	var label := Label.new()
	label.name = "Title"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(label)
	return label


func _add_button(text: String, pressed_callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func():
		pressed_callback.call()
	)
	vbox.add_child(button)
	return button


func _add_scroll_list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _add_empty_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(label)


func _add_back_buttons(add_hint: bool = true) -> HBoxContainer:
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)

	var back: Button = Button.new()
	back.text = "Back"
	back.pressed.connect(_show_parent_menu)
	buttons.add_child(back)

	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_on_cancel_pressed)
	buttons.add_child(cancel)

	if add_hint:
		_add_hint("Esc to go back")
	return buttons


func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	vbox.add_child(spacer)


func _add_hint(text: String) -> void:
	var hint := Label.new()
	hint.text = text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)


func _clear_vbox() -> void:
	if vbox == null:
		return
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()


func _get_title_text() -> String:
	var display: String = title_text.strip_edges()
	if display == "":
		display = "Terminal"
	return display


func _get_active_list() -> VBoxContainer:
	if vbox == null:
		return null
	var scroll: ScrollContainer = vbox.get_node_or_null("Scroll")
	if scroll == null:
		return null
	var list: VBoxContainer = scroll.get_node_or_null("List")
	return list


func _on_cancel_pressed() -> void:
	_cancel()


func _cancel() -> void:
	emit_signal("canceled")
	queue_free()


func _focus_default_control() -> void:
	if vbox != null and _focus_first_focusable_control(vbox):
		return


func _focus_first_focusable_control(root: Node) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	if root is Control:
		var control: Control = root
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return true
	for child in root.get_children():
		if _focus_first_focusable_control(child):
			return true
	return false


func _get_scroll_container() -> ScrollContainer:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner.is_visible_in_tree():
		var focused_scroll: ScrollContainer = _find_scroll_container_upwards(focus_owner, self)
		if focused_scroll != null:
			return focused_scroll
	return _find_first_scroll_container(self)


func _find_scroll_container_upwards(node: Node, root: Node) -> ScrollContainer:
	var current: Node = node
	while current != null:
		if current is ScrollContainer and current.is_visible_in_tree():
			return current
		if current == root:
			break
		current = current.get_parent()
	return null


func _find_first_scroll_container(root: Node) -> ScrollContainer:
	if root == null or not is_instance_valid(root):
		return null
	if root is ScrollContainer and root.is_visible_in_tree():
		return root
	for child in root.get_children():
		var found: ScrollContainer = _find_first_scroll_container(child)
		if found != null:
			return found
	return null


func _get_content_pack_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("ContentPackManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("ContentPackManager", true, false)


func _ensure_content_pack_manager() -> void:
	if get_tree() == null:
		return
	var existing = get_tree().get_nodes_in_group("ContentPackManager")
	if existing != null and existing.size() > 0:
		return
	var mgr := ContentPackManager.new()
	mgr.name = "ContentPackManager"
	get_tree().root.call_deferred("add_child", mgr)
	mgr.call_deferred("load_all_packs")


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)

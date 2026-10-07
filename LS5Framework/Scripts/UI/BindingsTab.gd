extends VBoxContainer

signal loadout_mapping_requested

const CONTROL_CATEGORIES: Array[Dictionary] = [
	{"label": "Movement", "actions": [
		{"action": "move_forward", "label": "Move Forward"},
		{"action": "move_back", "label": "Move Back"},
		{"action": "move_left", "label": "Move Left"},
		{"action": "move_right", "label": "Move Right"},
		{"action": "walk", "label": "Walk"}
	]},
	{"label": "Abilities", "actions": [
		{"action": "ability_slot_01", "label": "Ability Slot 1"},
		{"action": "ability_slot_02", "label": "Ability Slot 2"},
		{"action": "ability_slot_03", "label": "Ability Slot 3"},
		{"action": "ability_slot_04", "label": "Ability Slot 4"},
		{"action": "ability_slot_05", "label": "Ability Slot 5"},
		{"action": "ability_slot_06", "label": "Ability Slot 6"},
		{"action": "ability_slot_07", "label": "Ability Slot 7"},
		{"action": "ability_slot_08", "label": "Ability Slot 8"},
		{"action": "ability_slot_09", "label": "Ability Slot 9"},
		{"action": "ability_slot_10", "label": "Ability Slot 10"},
		{"action": "ability_slot_11", "label": "Ability Slot 11"},
		{"action": "ability_slot_12", "label": "Ability Slot 12"},
		{"action": "ability_slot_13", "label": "Ability Slot 13"},
		{"action": "ability_slot_14", "label": "Ability Slot 14"},
		{"action": "ability_slot_15", "label": "Ability Slot 15"},
		{"action": "ability_slot_16", "label": "Ability Slot 16"},
		{"action": "lightspeeddash", "label": "Lightspeed Dash"}
	]},
	{"label": "Camera", "actions": [
		{"action": "camera_zoom_in", "label": "Camera Zoom In"},
		{"action": "camera_zoom_out", "label": "Camera Zoom Out"},
		{"action": "VomitCam", "label": "Camera Alignment / Rear View"},
		{"action": "toggle_mouse_lock", "label": "Toggle Mouse Lock"}
	]},
	{"label": "General", "actions": [
		{"action": "emote_wheel", "label": "Open / Cancel Emote Wheel"},
		{"action": "emote_page_previous", "label": "Previous Emote Page"},
		{"action": "emote_page_next", "label": "Next Emote Page"},
		{"action": "interact", "label": "Interact"},
		{"action": "hide_pause_menu", "label": "Hide Pause Menu"},
		{"action": "respawn", "label": "Respawn"},
		{"action": "respawn_checkpoint", "label": "Respawn Checkpoint"},
		{"action": "quick_restart", "label": "Quick Restart"}
	]},
	{"label": "Online", "actions": [
		{"action": "player_tracking", "label": "Show Full Player Tracking"}
	]},
	{"label": "Debug", "actions": [
		{"action": "debug_toggle", "label": "Toggle Debug HUD"},
		{"action": "debug_enter", "label": "Toggle Debug Flight"},
		{"action": "debug_fast", "label": "Fast Fly"},
		{"action": "debug_slow", "label": "Slow Fly"},
		{"action": "debug_fly_up", "label": "Fly Up"},
		{"action": "debug_fly_down", "label": "Fly Down"},
		{"action": "debug_next_anim", "label": "Next Debug Animation"},
		{"action": "debug_prev_anim", "label": "Previous Debug Animation"},
		{"action": "buddy_spawn", "label": "Spawn or Despawn Buddy"},
		{"action": "unstuck", "label": "Unstuck"},
		{"action": "spawn_online_debug_puppet", "label": "Toggle Online Test Dummy"},
		{"action": "debug_reload_player_parameters", "label": "Reload Player Parameters"},
		{"action": "debug_reload_level_in_place", "label": "Reload Level In Place"},
		{"action": "debug_rewind_time_of_day", "label": "Rewind Time of Day"},
		{"action": "debug_advance_time_of_day", "label": "Advance Time of Day"}
	]}
]

const BINDING_KIND_KEYBOARD: StringName = &"keyboard"
const BINDING_KIND_GAMEPAD: StringName = &"gamepad"
const GAMEPAD_BIND_AXIS_THRESHOLD: float = 0.5

const DISALLOWED_KEYS: Array[int] = [
	Key.KEY_ENTER,
	Key.KEY_KP_ENTER,
	Key.KEY_META
]

@onready var label_bind_help: Label = $LabelBindHelp
@onready var controls_list: VBoxContainer = $ScrollControls/ControlsList

var _action_buttons: Dictionary = {}
var _pending_action: StringName = &""
var _pending_binding_kind: StringName = &""
var _pending_button: Button = null
var _ui_interaction_locked: bool = false
var _ui_interaction_cache: Dictionary = {}
## Opens the selected character's ability loadout mapping.
var loadout_mapping_button: Button = null


func _ready() -> void:
	_build_bindings_list()
	_ensure_default_bindings()
	set_process_input(true)
	set_process_unhandled_input(false)
	if label_bind_help != null:
		label_bind_help.visible = true
		label_bind_help.text = "Press a key or mouse button for Keyboard, or a button or stick direction for Gamepad. Press DEL to clear the current keyboard binding, or ESC to cancel."


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			_refresh_all_action_buttons()
		if not is_visible_in_tree() and _pending_action != &"":
			_cancel_binding()
	if what == NOTIFICATION_EXIT_TREE:
		if _pending_action != &"":
			_cancel_binding()


func refresh_from_settings() -> void:
	if _pending_action != &"":
		_cancel_binding()
	_refresh_all_action_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if _try_bind_key_event(key_event):
			_mark_input_handled()


func _input(event: InputEvent) -> void:
	if _pending_action == &"":
		return
	if not is_visible_in_tree():
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if _try_bind_key_event(key_event):
			_mark_input_handled()
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if not mouse_event.pressed:
			return
		if _pending_binding_kind != BINDING_KIND_KEYBOARD:
			return
		if _is_mouse_wheel_button(mouse_event.button_index):
			_mark_input_handled()
			return
		var new_mouse_bindings: Array = [{"type": "mouse", "button": int(mouse_event.button_index)}]
		SettingsManager.set_action_bindings_for_kind(_pending_action, BINDING_KIND_KEYBOARD, new_mouse_bindings)
		_finish_binding()
		_mark_input_handled()
		return
	if _pending_binding_kind != BINDING_KIND_GAMEPAD:
		return
	if event is InputEventJoypadButton:
		var joy_button_event: InputEventJoypadButton = event
		if not joy_button_event.pressed:
			return
		if joy_button_event.is_action_pressed("ui_cancel") or joy_button_event.is_action_pressed("pause"):
			_cancel_binding()
			_mark_input_handled()
			return
		var joy_bindings: Array = [{"type": "joy_button", "button": int(joy_button_event.button_index)}]
		SettingsManager.set_action_bindings_for_kind(_pending_action, BINDING_KIND_GAMEPAD, joy_bindings)
		_finish_binding()
		_mark_input_handled()
		return
	if event is InputEventJoypadMotion:
		var joy_motion_event: InputEventJoypadMotion = event
		if abs(float(joy_motion_event.axis_value)) < GAMEPAD_BIND_AXIS_THRESHOLD:
			return
		var joy_motion_bindings: Array = [{"type": "joy_motion", "axis": int(joy_motion_event.axis), "axis_value": signf(float(joy_motion_event.axis_value))}]
		SettingsManager.set_action_bindings_for_kind(_pending_action, BINDING_KIND_GAMEPAD, joy_motion_bindings)
		_finish_binding()
		_mark_input_handled()
		return


func _build_bindings_list() -> void:
	if controls_list == null:
		return
	_clear_children(controls_list)
	_action_buttons.clear()
	var loadout_hint: Label = Label.new()
	loadout_hint.text = "Looking for per-ability bindings?  Check out your per-character loadout mapping."
	loadout_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loadout_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_list.add_child(loadout_hint)
	loadout_mapping_button = Button.new()
	loadout_mapping_button.text = "Open Character Loadout Mapping"
	loadout_mapping_button.add_to_group("MenuButtons")
	loadout_mapping_button.pressed.connect(func() -> void: loadout_mapping_requested.emit())
	controls_list.add_child(loadout_mapping_button)

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 12)
	var header_action: Label = Label.new()
	header_action.text = "Action"
	header_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_keyboard: Label = Label.new()
	header_keyboard.text = "Keyboard"
	header_keyboard.custom_minimum_size = Vector2(160, 0)
	var header_gamepad: Label = Label.new()
	header_gamepad.text = "Gamepad"
	header_gamepad.custom_minimum_size = Vector2(160, 0)
	header_row.add_child(header_action)
	header_row.add_child(header_keyboard)
	header_row.add_child(header_gamepad)
	controls_list.add_child(header_row)

	for category in CONTROL_CATEGORIES:
		_add_category_label(String(category.get("label", "")))
		var actions: Array = category.get("actions", [])
		for entry in actions:
			if not entry.has("action") or not entry.has("label"):
				continue
			_add_binding_row(StringName(entry["action"]), String(entry["label"]))


func _add_category_label(category_text: String) -> void:
	if category_text == "":
		return
	var label: Label = Label.new()
	label.text = category_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", 20)
	controls_list.add_child(label)


func _add_binding_row(action_name: StringName, label_text: String) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)

	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var keyboard_button: Button = Button.new()
	keyboard_button.text = _get_action_key_text(action_name, BINDING_KIND_KEYBOARD)
	keyboard_button.size_flags_horizontal = Control.SIZE_FILL
	keyboard_button.custom_minimum_size = Vector2(160, 0)
	keyboard_button.add_to_group("MenuButtons")
	keyboard_button.pressed.connect(_on_bind_button_pressed.bind(action_name, BINDING_KIND_KEYBOARD, keyboard_button))

	var gamepad_button: Button = Button.new()
	gamepad_button.text = _get_action_key_text(action_name, BINDING_KIND_GAMEPAD)
	gamepad_button.size_flags_horizontal = Control.SIZE_FILL
	gamepad_button.custom_minimum_size = Vector2(160, 0)
	gamepad_button.add_to_group("MenuButtons")
	gamepad_button.pressed.connect(_on_bind_button_pressed.bind(action_name, BINDING_KIND_GAMEPAD, gamepad_button))

	row.add_child(label)
	row.add_child(keyboard_button)
	row.add_child(gamepad_button)
	controls_list.add_child(row)

	_action_buttons[action_name] = {
		"keyboard": keyboard_button,
		"gamepad": gamepad_button
	}


func _on_bind_button_pressed(action_name: StringName, binding_kind: StringName, button: Button) -> void:
	_begin_binding(action_name, binding_kind, button)


func _begin_binding(action_name: StringName, binding_kind: StringName, button: Button) -> void:
	if _pending_action != &"":
		_cancel_binding()
	_pending_action = action_name
	_pending_binding_kind = binding_kind
	_pending_button = button
	if _pending_button != null:
		if binding_kind == BINDING_KIND_GAMEPAD:
			_pending_button.text = "Press a button or move a stick..."
		else:
			_pending_button.text = "Press a key..."
	_set_binding_active(true)
	set_process_unhandled_input(true)


func _finish_binding() -> void:
	if _pending_action == &"":
		return
	var focus_button: Button = _pending_button
	_refresh_action_button(_pending_action)
	_pending_action = &""
	_pending_binding_kind = &""
	_pending_button = null
	_set_binding_active(false)
	set_process_unhandled_input(false)
	if focus_button != null and is_instance_valid(focus_button):
		focus_button.call_deferred("grab_focus")


func _cancel_binding() -> void:
	if _pending_action == &"":
		return
	var focus_button: Button = _pending_button
	_refresh_action_button(_pending_action)
	_pending_action = &""
	_pending_binding_kind = &""
	_pending_button = null
	_set_binding_active(false)
	set_process_unhandled_input(false)
	if focus_button != null and is_instance_valid(focus_button):
		focus_button.call_deferred("grab_focus")


func _refresh_action_button(action_name: StringName) -> void:
	if not _action_buttons.has(action_name):
		return
	var button_pair: Dictionary = _action_buttons[action_name]
	var keyboard_button: Button = button_pair.get("keyboard", null)
	var gamepad_button: Button = button_pair.get("gamepad", null)
	if keyboard_button != null:
		keyboard_button.text = _get_action_key_text(action_name, BINDING_KIND_KEYBOARD)
	if gamepad_button != null:
		gamepad_button.text = _get_action_key_text(action_name, BINDING_KIND_GAMEPAD)


func _refresh_all_action_buttons() -> void:
	for action_name in _action_buttons.keys():
		_refresh_action_button(StringName(action_name))


func _get_action_key_text(action_name: StringName, binding_kind: StringName) -> String:
	var key_texts: Array[String] = []
	for binding in SettingsManager.get_action_bindings(action_name):
		if not (binding is Dictionary):
			continue
		var binding_dict: Dictionary = binding
		if not _binding_kind_matches(String(binding_dict.get("type", "")), binding_kind):
			continue
		var text: String = _get_binding_label(binding_dict)
		if text != "":
			key_texts.append(text)
	if key_texts.is_empty():
		return "Unbound"
	return ", ".join(key_texts)


func _is_disallowed_key(keycode_value: int) -> bool:
	if keycode_value == Key.KEY_ESCAPE:
		return true
	if keycode_value == Key.KEY_DELETE:
		return true
	for disallowed in DISALLOWED_KEYS:
		if keycode_value == int(disallowed):
			return true
	return false


func _is_mouse_wheel_button(button_index: int) -> bool:
	if button_index == MouseButton.MOUSE_BUTTON_WHEEL_UP:
		return true
	if button_index == MouseButton.MOUSE_BUTTON_WHEEL_DOWN:
		return true
	if button_index == MouseButton.MOUSE_BUTTON_WHEEL_LEFT:
		return true
	if button_index == MouseButton.MOUSE_BUTTON_WHEEL_RIGHT:
		return true
	return false


func _is_media_key(key_event: InputEventKey) -> bool:
	var text: String = key_event.as_text().to_lower()
	if text.find("media") != -1:
		return true
	if text.find("volume") != -1:
		return true
	if text.find("audio") != -1:
		return true
	if text.find("mute") != -1:
		return true
	if text.find("play") != -1:
		return true
	if text.find("pause") != -1:
		return true
	if text.find("stop") != -1:
		return true
	if text.find("next") != -1:
		return true
	if text.find("prev") != -1:
		return true
	if text.find("rewind") != -1:
		return true
	if text.find("forward") != -1:
		return true
	return false


func _try_bind_key_event(key_event: InputEventKey) -> bool:
	if _pending_action == &"":
		return false
	if not is_visible_in_tree():
		return false
	if not key_event.pressed or key_event.echo:
		return true
	var keycode_value: int = int(key_event.keycode)
	if keycode_value == Key.KEY_NONE:
		return true
	if _pending_binding_kind == BINDING_KIND_GAMEPAD:
		if keycode_value == Key.KEY_ESCAPE:
			_cancel_binding()
			return true
		if keycode_value == Key.KEY_DELETE:
			SettingsManager.set_action_bindings_for_kind(_pending_action, BINDING_KIND_GAMEPAD, [])
			_finish_binding()
			return true
		return true
	if keycode_value == Key.KEY_ESCAPE:
		_cancel_binding()
		return true
	if keycode_value == Key.KEY_DELETE:
		var empty_codes: Array = []
		SettingsManager.set_action_keycodes(_pending_action, empty_codes)
		_finish_binding()
		return true
	if _is_disallowed_key(keycode_value):
		return true
	if _is_media_key(key_event):
		return true
	var new_bindings: Array = [{"type": "key", "keycode": keycode_value}]
	SettingsManager.set_action_bindings_for_kind(_pending_action, BINDING_KIND_KEYBOARD, new_bindings)
	_finish_binding()
	return true


func _ensure_default_bindings() -> void:
	var action_names: Array = []
	for category in CONTROL_CATEGORIES:
		var actions: Array = category.get("actions", [])
		for entry in actions:
			if entry.has("action"):
				action_names.append(StringName(entry["action"]))
	SettingsManager.ensure_default_input_bindings(action_names)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		if child != null:
			child.queue_free()


func _set_binding_active(active: bool) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if active:
		tree.set_meta("input_binding_active", true)
		_lock_ui_interaction()
	else:
		tree.call_deferred("set_meta", "input_binding_active", false)
		_unlock_ui_interaction()


func _mark_input_handled() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()


func _lock_ui_interaction() -> void:
	if _ui_interaction_locked:
		return
	_ui_interaction_locked = true
	_ui_interaction_cache.clear()

	var controls: Array[Control] = []
	_collect_controls(self, controls)
	for control in controls:
		if control == null or not is_instance_valid(control):
			continue
		_ui_interaction_cache[control] = {
			"mouse_filter": control.mouse_filter,
			"focus_mode": control.focus_mode
		}
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE

	var vp: Viewport = get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _unlock_ui_interaction() -> void:
	if not _ui_interaction_locked:
		return
	_ui_interaction_locked = false

	for control in _ui_interaction_cache.keys():
		if control == null or not is_instance_valid(control):
			continue
		var state: Dictionary = _ui_interaction_cache[control]
		if state.has("mouse_filter"):
			control.mouse_filter = int(state["mouse_filter"])
		if state.has("focus_mode"):
			control.focus_mode = int(state["focus_mode"])
	_ui_interaction_cache.clear()


func _collect_controls(root: Node, out_controls: Array[Control]) -> void:
	if root is Control:
		out_controls.append(root)
	for child in root.get_children():
		if child == null:
			continue
		_collect_controls(child, out_controls)


func _binding_kind_matches(binding_type: String, binding_kind: StringName) -> bool:
	if binding_kind == &"":
		return true
	if binding_kind == &"keyboard":
		return binding_type == "key" or binding_type == "mouse"
	if binding_kind == &"gamepad":
		return binding_type == "joy_button" or binding_type == "joy_motion"
	return false


func _get_binding_label(binding_dict: Dictionary) -> String:
	return String(InputBindingGlyphs.describe_binding(binding_dict, InputBindingGlyphs.Style.AUTO, -1, false).get("label", ""))


func _get_key_label(keycode_value: int) -> String:
	if keycode_value == 0:
		return ""
	return OS.get_keycode_string(keycode_value)


func _get_mouse_label(button_index: int) -> String:
	match button_index:
		MouseButton.MOUSE_BUTTON_LEFT:
			return "Mouse Left"
		MouseButton.MOUSE_BUTTON_RIGHT:
			return "Mouse Right"
		MouseButton.MOUSE_BUTTON_MIDDLE:
			return "Mouse Middle"
		MouseButton.MOUSE_BUTTON_WHEEL_UP:
			return "Mouse Wheel Up"
		MouseButton.MOUSE_BUTTON_WHEEL_DOWN:
			return "Mouse Wheel Down"
		MouseButton.MOUSE_BUTTON_WHEEL_LEFT:
			return "Mouse Wheel Left"
		MouseButton.MOUSE_BUTTON_WHEEL_RIGHT:
			return "Mouse Wheel Right"
		_:
			return "Mouse Button %d" % button_index


func _get_joy_button_label(button_index: int) -> String:
	if button_index < 0:
		return ""
	if button_index == JOY_BUTTON_BACK:
		return "Back / Select"
	return "Joy Button %d" % button_index


func _get_joy_motion_label(axis: int, axis_value: int) -> String:
	if axis < 0:
		return ""
	var dir_text: String = "Positive" if axis_value >= 0 else "Negative"
	return "Joy Axis %d %s" % [axis, dir_text]

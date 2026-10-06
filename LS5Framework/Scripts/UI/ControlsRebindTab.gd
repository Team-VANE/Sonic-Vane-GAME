extends VBoxContainer

const BINDINGS_TAB_SCRIPT: Script = preload("res://LS5Framework/Scripts/UI/BindingsTab.gd")

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
@onready var chk_invert_mouse_y: CheckBox = $HBoxMouseInvertY/CheckInvertMouseY
@onready var slider_mouse_sensitivity: HSlider = $HBoxMouseSensitivity/SliderMouseSensitivity

var _action_buttons: Dictionary = {}
var _pending_action: StringName = &""
var _pending_binding_kind: StringName = &""
var _pending_button: Button = null
var _ui_interaction_locked: bool = false
var _ui_interaction_cache: Dictionary = {}
var _setting_checkboxes: Dictionary = {}
var _setting_spinboxes: Dictionary = {}
var _setting_sliders: Dictionary = {}
var _setting_option_buttons: Dictionary = {}
var _left_stick_trick_movement_row: Control = null


func _ready() -> void:
	_build_controls_list()
	_ensure_default_bindings()
	_sync_controls_settings()
	_wire_controls_settings()
	set_process_input(true)
	set_process_unhandled_input(false)
	if label_bind_help != null:
		label_bind_help.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			_sync_controls_settings()
		if not is_visible_in_tree() and _pending_action != &"":
			_cancel_binding()
	if what == NOTIFICATION_EXIT_TREE:
		if _pending_action != &"":
			_cancel_binding()


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


func _build_controls_list() -> void:
	if controls_list == null:
		return
	_clear_children(controls_list)
	_action_buttons.clear()
	_setting_checkboxes.clear()
	_setting_spinboxes.clear()
	_setting_sliders.clear()
	_setting_option_buttons.clear()
	_left_stick_trick_movement_row = null
	_add_controller_settings_rows()


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
	# SUMMARY: Attempt to bind a key while a binding prompt is active.
	# STEPS:
	# - Step 1: Validate binding state and filter repeats/releases.
	# - Step 2: Handle cancel/delete/disallowed keys.
	# - Step 3: Apply the binding and finish the prompt.
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
	var action_names: Array = _get_binding_action_names()
	SettingsManager.ensure_default_input_bindings(action_names)


func _get_binding_action_names() -> Array:
	var action_names: Array = []
	for category in BINDINGS_TAB_SCRIPT.CONTROL_CATEGORIES:
		var actions: Array = category.get("actions", [])
		for entry in actions:
			if entry.has("action"):
				action_names.append(StringName(entry["action"]))
	return action_names


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
	# SUMMARY: Temporarily disable UI focus and mouse input while binding.
	# STEPS:
	# - Step 1: Cache all Control focus/mouse settings in this tab.
	# - Step 2: Clear focus and ignore GUI input on each Control.
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
	# SUMMARY: Restore UI focus and mouse input settings after binding.
	# STEPS:
	# - Step 1: Reapply cached Control settings.
	# - Step 2: Clear the cache for the next bind session.
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
	# SUMMARY: Collect all Control nodes under a root (including root if applicable).
	if root is Control:
		out_controls.append(root)
	for child in root.get_children():
		if child == null:
			continue
		_collect_controls(child, out_controls)


func _wire_controls_settings() -> void:
	if chk_invert_mouse_y != null:
		if not chk_invert_mouse_y.toggled.is_connected(_on_CheckInvertMouseY_toggled):
			chk_invert_mouse_y.toggled.connect(_on_CheckInvertMouseY_toggled)
	if slider_mouse_sensitivity != null:
		if not slider_mouse_sensitivity.value_changed.is_connected(_on_SliderMouseSensitivity_value_changed):
			slider_mouse_sensitivity.value_changed.connect(_on_SliderMouseSensitivity_value_changed)

func _sync_controls_settings() -> void:
	if chk_invert_mouse_y != null:
		chk_invert_mouse_y.button_pressed = SettingsManager.mouse_invert_y
	if slider_mouse_sensitivity != null:
		slider_mouse_sensitivity.value = SettingsManager.mouse_look_sensitivity
	for key in _setting_checkboxes.keys():
		var checkbox: CheckBox = _setting_checkboxes[key] as CheckBox
		if checkbox == null:
			continue
		match String(key):
			"right_stick_invert_y":
				checkbox.button_pressed = SettingsManager.right_stick_invert_y
	for key in _setting_sliders.keys():
		var slider: HSlider = _setting_sliders[key] as HSlider
		if slider == null:
			continue
		match String(key):
			"right_stick_sensitivity_percent":
				slider.value = SettingsManager.right_stick_sensitivity_percent
			"trick_rotation_acceleration_percent":
				slider.value = SettingsManager.trick_rotation_acceleration_percent
	for key in _setting_option_buttons.keys():
		var option: OptionButton = _setting_option_buttons[key] as OptionButton
		if option == null:
			continue
		match String(key):
			"trick_control_stick":
				var selected_index: int = option.get_item_index(SettingsManager.trick_control_stick)
				if selected_index >= 0:
					option.selected = selected_index
			"left_stick_trick_movement":
				var selected_index: int = option.get_item_index(SettingsManager.left_stick_trick_movement)
				if selected_index >= 0:
					option.selected = selected_index
	for key in _setting_spinboxes.keys():
		var spinbox: SpinBox = _setting_spinboxes[key] as SpinBox
		if spinbox == null:
			continue
		match String(key):
			"left_stick_deadzone_percent":
				spinbox.value = SettingsManager.left_stick_deadzone_percent
			"left_stick_max_percent":
				spinbox.value = SettingsManager.left_stick_max_percent
			"right_stick_deadzone_percent":
				spinbox.value = SettingsManager.right_stick_deadzone_percent
			"right_stick_max_percent":
				spinbox.value = SettingsManager.right_stick_max_percent
			"walk_stick_zone_percent":
				spinbox.value = SettingsManager.walk_stick_zone_percent
	_update_left_stick_trick_movement_visibility()


func _on_CheckInvertMouseY_toggled(pressed: bool) -> void:
	SettingsManager.set_mouse_invert_y(pressed)
	SettingsManager.save_now()


func _on_SliderMouseSensitivity_value_changed(value: float) -> void:
	SettingsManager.set_mouse_look_sensitivity(value)
	SettingsManager.save_now()


func _add_controller_settings_rows() -> void:
	_add_section_label("Controller Tuning")
	_setting_option_buttons["trick_control_stick"] = _add_trick_control_stick_row()
	_setting_option_buttons["left_stick_trick_movement"] = _add_left_stick_trick_movement_row()
	var trick_acceleration_slider: HSlider = _add_percent_slider_setting_row("Trick Rotation Acceleration %", SettingsManager.trick_rotation_acceleration_percent, 50.0, 300.0, 5.0, Callable(self, "_on_TrickRotationAcceleration_value_changed"))
	trick_acceleration_slider.tooltip_text = "Controls how quickly controller input reaches the character's top trick rotation speed."
	_setting_sliders["trick_rotation_acceleration_percent"] = trick_acceleration_slider
	_setting_spinboxes["left_stick_deadzone_percent"] = _add_percent_setting_row("Left Stick Deadzone %", SettingsManager.left_stick_deadzone_percent, Callable(self, "_on_LeftStickDeadzone_value_changed"))
	_setting_spinboxes["left_stick_max_percent"] = _add_percent_setting_row("Left Stick Max %", SettingsManager.left_stick_max_percent, Callable(self, "_on_LeftStickMax_value_changed"))
	_setting_spinboxes["right_stick_deadzone_percent"] = _add_percent_setting_row("Right Stick Deadzone %", SettingsManager.right_stick_deadzone_percent, Callable(self, "_on_RightStickDeadzone_value_changed"))
	_setting_spinboxes["right_stick_max_percent"] = _add_percent_setting_row("Right Stick Max %", SettingsManager.right_stick_max_percent, Callable(self, "_on_RightStickMax_value_changed"))
	_setting_checkboxes["right_stick_invert_y"] = _add_toggle_setting_row("Invert Right Stick Y", SettingsManager.right_stick_invert_y, Callable(self, "_on_RightStickInvertY_toggled"))
	_setting_sliders["right_stick_sensitivity_percent"] = _add_percent_slider_setting_row("Camera Stick Sensitivity %", SettingsManager.right_stick_sensitivity_percent, 700.0, 3000.0, 25.0, Callable(self, "_on_RightStickSensitivity_value_changed"))
	_setting_spinboxes["walk_stick_zone_percent"] = _add_percent_setting_row("Walk Stick Zone %", SettingsManager.walk_stick_zone_percent, Callable(self, "_on_WalkStickZone_value_changed"))


func _add_trick_control_stick_row() -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label: Label = Label.new()
	label.text = "Trick Control Stick"
	label.tooltip_text = "Selects which controller stick rotates the character while Trick is held."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var option: OptionButton = OptionButton.new()
	option.tooltip_text = "Left Stick controls trick rotation while leaving camera controls on the Right Stick."
	option.add_item("Left Stick", SettingsManager.TRICK_CONTROL_STICK_LEFT)
	option.add_item("Right Stick", SettingsManager.TRICK_CONTROL_STICK_RIGHT)
	var selected_index: int = option.get_item_index(SettingsManager.trick_control_stick)
	if selected_index >= 0:
		option.selected = selected_index
	option.item_selected.connect(_on_TrickControlStick_item_selected)
	row.add_child(label)
	row.add_child(option)
	controls_list.add_child(row)
	return option


func _add_left_stick_trick_movement_row() -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label: Label = Label.new()
	label.text = "Left-Stick Trick Movement"
	label.tooltip_text = "Selects how movement continues while the Left Stick is controlling trick rotation."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var option: OptionButton = OptionButton.new()
	option.tooltip_text = "Preserve Entry Momentum keeps the airborne velocity from when trick rotation began. Continuous Input uses the last gravity-horizontal movement direction at the previous stick strength."
	option.add_item("Preserve Entry Momentum", SettingsManager.LEFT_STICK_TRICK_MOVEMENT_PRESERVE_MOMENTUM)
	option.add_item("Continuous Input", SettingsManager.LEFT_STICK_TRICK_MOVEMENT_LAST_INPUT)
	var selected_index: int = option.get_item_index(SettingsManager.left_stick_trick_movement)
	if selected_index >= 0:
		option.selected = selected_index
	option.item_selected.connect(_on_LeftStickTrickMovement_item_selected)
	row.add_child(label)
	row.add_child(option)
	controls_list.add_child(row)
	_left_stick_trick_movement_row = row
	_update_left_stick_trick_movement_visibility()
	return option


func _update_left_stick_trick_movement_visibility() -> void:
	if _left_stick_trick_movement_row == null:
		return
	_left_stick_trick_movement_row.visible = (
		SettingsManager.trick_control_stick == SettingsManager.TRICK_CONTROL_STICK_LEFT
	)


func _add_section_label(text: String) -> void:
	if controls_list == null:
		return
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	controls_list.add_child(label)


func _add_percent_setting_row(label_text: String, value: float, changed_callback: Callable) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spinbox: SpinBox = SpinBox.new()
	spinbox.min_value = 0.0
	spinbox.max_value = 100.0
	spinbox.step = 1.0
	spinbox.value = value
	spinbox.custom_minimum_size = Vector2(120, 0)
	if not spinbox.value_changed.is_connected(changed_callback):
		spinbox.value_changed.connect(changed_callback)
	row.add_child(label)
	row.add_child(spinbox)
	controls_list.add_child(row)
	return spinbox


func _add_toggle_setting_row(label_text: String, value: bool, changed_callback: Callable) -> CheckBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var checkbox: CheckBox = CheckBox.new()
	checkbox.button_pressed = value
	if not checkbox.toggled.is_connected(changed_callback):
		checkbox.toggled.connect(changed_callback)
	row.add_child(label)
	row.add_child(checkbox)
	controls_list.add_child(row)
	return checkbox


func _add_percent_slider_setting_row(label_text: String, value: float, min_value: float, max_value: float, step_value: float, changed_callback: Callable) -> HSlider:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider: HSlider = HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 0)
	slider.value = value
	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(70, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%.0f%%" % value
	if not slider.value_changed.is_connected(changed_callback):
		slider.value_changed.connect(changed_callback)
	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = "%.0f%%" % new_value
	)
	row.add_child(label)
	row.add_child(slider)
	row.add_child(value_label)
	controls_list.add_child(row)
	return slider


func _get_binding_label(binding: Dictionary) -> String:
	var bind_type: String = String(binding.get("type", ""))
	if bind_type == "key":
		var keycode_value: int = int(binding.get("keycode", Key.KEY_NONE))
		if keycode_value != Key.KEY_NONE:
			var key_event: InputEventKey = InputEventKey.new()
			key_event.keycode = keycode_value
			return key_event.as_text()
	elif bind_type == "mouse":
		var mouse_button: int = int(binding.get("button", 0))
		if mouse_button > 0:
			var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
			mouse_event.button_index = mouse_button
			return mouse_event.as_text()
	elif bind_type == "joy_button":
		var joy_button: int = int(binding.get("button", -1))
		if joy_button >= 0:
			return "Joypad Button %d" % joy_button
	elif bind_type == "joy_motion":
		var joy_axis: int = int(binding.get("axis", -1))
		var joy_axis_value: float = float(binding.get("axis_value", 0.0))
		if joy_axis >= 0 and joy_axis_value != 0.0:
			var axis_suffix: String = "-" if joy_axis_value < 0.0 else "+"
			return "Axis %d%s" % [joy_axis, axis_suffix]
	return ""


func _binding_kind_matches(binding_type: String, binding_kind: StringName) -> bool:
	if binding_kind == BINDING_KIND_KEYBOARD:
		return binding_type == "key" or binding_type == "mouse"
	if binding_kind == BINDING_KIND_GAMEPAD:
		return binding_type == "joy_button" or binding_type == "joy_motion"
	return false


func _on_LeftStickDeadzone_value_changed(value: float) -> void:
	SettingsManager.set_left_stick_deadzone_percent(value)
	SettingsManager.save_now()


func _on_LeftStickMax_value_changed(value: float) -> void:
	SettingsManager.set_left_stick_max_percent(value)
	SettingsManager.save_now()


func _on_RightStickDeadzone_value_changed(value: float) -> void:
	SettingsManager.set_right_stick_deadzone_percent(value)
	SettingsManager.save_now()


func _on_RightStickMax_value_changed(value: float) -> void:
	SettingsManager.set_right_stick_max_percent(value)
	SettingsManager.save_now()


func _on_RightStickInvertY_toggled(pressed: bool) -> void:
	SettingsManager.set_right_stick_invert_y(pressed)
	SettingsManager.save_now()


func _on_RightStickSensitivity_value_changed(value: float) -> void:
	SettingsManager.set_right_stick_sensitivity_percent(value)
	SettingsManager.save_now()


func _on_TrickControlStick_item_selected(index: int) -> void:
	var option: OptionButton = _setting_option_buttons.get("trick_control_stick", null) as OptionButton
	if option == null:
		return
	SettingsManager.set_trick_control_stick(option.get_item_id(index))
	SettingsManager.save_now()
	_update_left_stick_trick_movement_visibility()


func _on_LeftStickTrickMovement_item_selected(index: int) -> void:
	var option: OptionButton = _setting_option_buttons.get("left_stick_trick_movement", null) as OptionButton
	if option == null:
		return
	SettingsManager.set_left_stick_trick_movement(option.get_item_id(index))
	SettingsManager.save_now()


func _on_TrickRotationAcceleration_value_changed(value: float) -> void:
	SettingsManager.set_trick_rotation_acceleration_percent(value)
	SettingsManager.save_now()


func _on_WalkStickZone_value_changed(value: float) -> void:
	SettingsManager.set_walk_stick_zone_percent(value)
	SettingsManager.save_now()


func refresh_from_settings() -> void:
	if _pending_action != &"":
		_cancel_binding()
	_build_controls_list()
	_sync_controls_settings()

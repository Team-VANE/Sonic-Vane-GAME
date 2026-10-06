extends Control
class_name CharacterSettingsMenu

signal closed

const HOLD_TIME_MIN: float = 0.01
const HOLD_TIME_MAX: float = 2.0
const HOLD_TIME_STEP: float = 0.01
const NAVIGATION_REPEAT_DELAY: float = 0.35
const NAVIGATION_REPEAT_INTERVAL: float = 0.085
const NAVIGATION_ROW_TOLERANCE: float = 24.0
const MENU_VERTICAL_MARGIN: float = 32.0
const NAVIGATION_ACTIONS: Array[StringName] = [
	&"ui_up",
	&"ui_down",
	&"ui_left",
	&"ui_right",
]

@onready var title_label: Label = $Dimmer/Center/Panel/Margin/Content/Title
## Panel resized to preserve the menu's viewport border margins.
@onready var panel: PanelContainer = $Dimmer/Center/Panel
@onready var tabs: TabContainer = $Dimmer/Center/Panel/Margin/Content/Tabs
@onready var loadout_scroll: ScrollContainer = $Dimmer/Center/Panel/Margin/Content/Tabs/Loadout/Scroll
@onready var loadout_rows: VBoxContainer = $Dimmer/Center/Panel/Margin/Content/Tabs/Loadout/Scroll/Rows
@onready var conflict_label: Label = $Dimmer/Center/Panel/Margin/Content/Tabs/Loadout/ConflictLabel
@onready var route_scroll: ScrollContainer = $Dimmer/Center/Panel/Margin/Content/Tabs/Routes/Scroll
@onready var route_rows: VBoxContainer = $Dimmer/Center/Panel/Margin/Content/Tabs/Routes/Scroll/Rows
@onready var add_route_button: Button = $Dimmer/Center/Panel/Margin/Content/Tabs/Routes/AddRouteButton
@onready var reset_button: Button = $Dimmer/Center/Panel/Margin/Content/Footer/ResetButton
@onready var reset_routes_button: Button = $Dimmer/Center/Panel/Margin/Content/Footer/ResetRoutesButton
@onready var close_button: Button = $Dimmer/Center/Panel/Margin/Content/Footer/CloseButton

var _entry: Dictionary = {}
var _profile: CharacterSettingsProfile = null
var _held_navigation_action: StringName = &""
var _navigation_repeat_remaining: float = 0.0


func _ready() -> void:
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	focus_mode = Control.FOCUS_NONE
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_panel_height):
		viewport.size_changed.connect(_update_panel_height)
	_update_panel_height()
	_configure_tab_focus()
	_configure_scroll_focus(loadout_scroll)
	_configure_scroll_focus(route_scroll)
	reset_button.pressed.connect(_on_reset_pressed)
	reset_routes_button.pressed.connect(_on_reset_routes_pressed)
	add_route_button.pressed.connect(_on_add_route_pressed)
	close_button.pressed.connect(close_menu)
	visibility_changed.connect(_on_visibility_changed)
	tabs.tab_changed.connect(_on_tab_changed)
	call_deferred("_focus_active_tab")


func _update_panel_height() -> void:
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	panel.custom_minimum_size.y = maxf(viewport_height - MENU_VERTICAL_MARGIN * 2.0, 0.0)


func _configure_tab_focus() -> void:
	tabs.focus_mode = Control.FOCUS_NONE
	var tab_bar: TabBar = tabs.get_tab_bar()
	if tab_bar != null:
		tab_bar.focus_mode = Control.FOCUS_NONE


func open_for_character(entry: Dictionary) -> void:
	_entry = entry.duplicate(true)
	var profile_value: Variant = entry.get("settings_profile", null)
	_profile = profile_value as CharacterSettingsProfile
	var character_name: String = String(entry.get("name", "Character"))
	title_label.text = "%s Settings" % character_name
	_build_loadout_rows()
	_build_route_rows()
	tabs.current_tab = 0
	show()
	call_deferred("_focus_active_tab")


func close_menu() -> void:
	hide()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _handle_tab_input(event):
		_clear_navigation_repeat()
		get_viewport().set_input_as_handled()
		return
	if _held_navigation_action != &"" and event.is_action_released(_held_navigation_action):
		_clear_navigation_repeat()
	var navigation_action: StringName = _get_navigation_action_from_event(event)
	if navigation_action == &"" or _has_open_option_popup(loadout_rows) or _has_open_option_popup(route_rows):
		return
	if navigation_action == _held_navigation_action:
		get_viewport().set_input_as_handled()
		return
	_held_navigation_action = navigation_action
	_navigation_repeat_remaining = NAVIGATION_REPEAT_DELAY
	_navigate_focus(navigation_action)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or SettingsManager.is_mouse_input_active():
		_clear_navigation_repeat()
		return
	if _held_navigation_action == &"" or not Input.is_action_pressed(_held_navigation_action):
		_clear_navigation_repeat()
		return
	if _has_open_option_popup(loadout_rows) or _has_open_option_popup(route_rows):
		_clear_navigation_repeat()
		return
	_navigation_repeat_remaining -= delta
	while _navigation_repeat_remaining <= 0.0:
		_navigate_focus(_held_navigation_action)
		_navigation_repeat_remaining += NAVIGATION_REPEAT_INTERVAL


func _get_navigation_action_from_event(event: InputEvent) -> StringName:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return &""
	for action: StringName in NAVIGATION_ACTIONS:
		if event.is_action_pressed(action):
			return action
	return &""


func _clear_navigation_repeat() -> void:
	_held_navigation_action = &""
	_navigation_repeat_remaining = 0.0


func _navigate_focus(action: StringName) -> void:
	var groups: Array = _get_navigation_groups()
	if groups.is_empty():
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	var location: Vector2i = _find_navigation_location(groups, focus_owner)
	if location.x < 0:
		var first_group: Array = groups[0]
		if not first_group.is_empty():
			_grab_navigation_focus(first_group[0] as Control)
		return
	var target: Control = null
	if action == &"ui_left" or action == &"ui_right":
		target = _get_horizontal_navigation_target(groups, location, action)
	else:
		target = _get_vertical_navigation_target(groups, location, action)
	if target != null and target != focus_owner:
		_grab_navigation_focus(target)


func _grab_navigation_focus(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.grab_focus()
	SettingsManager.call_deferred("ensure_navigation_focus_visible", control)


func _get_navigation_groups() -> Array:
	var groups: Array = []
	var loadout_tab: Control = tabs.get_node("Loadout") as Control
	var routes_tab: Control = tabs.get_node("Routes") as Control
	if tabs.current_tab == tabs.get_tab_idx_from_control(loadout_tab):
		_append_loadout_navigation_groups(groups)
	elif tabs.current_tab == tabs.get_tab_idx_from_control(routes_tab):
		_append_routes_navigation_groups(groups)
	_append_footer_navigation_group(groups)
	return groups


func _append_loadout_navigation_groups(groups: Array) -> void:
	for child: Node in loadout_rows.get_children():
		if not (child is VBoxContainer):
			continue
		var controls: Array[Control] = []
		_collect_primary_focus_targets(child, controls)
		_append_navigation_group(groups, controls)


func _append_routes_navigation_groups(groups: Array) -> void:
	var add_route_controls: Array[Control] = [add_route_button]
	_append_navigation_group(groups, add_route_controls)
	for child: Node in route_rows.get_children():
		if not (child is VBoxContainer):
			continue
		var controls: Array[Control] = []
		_collect_primary_focus_targets(child, controls)
		_append_visual_navigation_rows(groups, controls)


func _append_footer_navigation_group(groups: Array) -> void:
	var footer_controls: Array[Control] = [reset_button, reset_routes_button, close_button]
	_append_navigation_group(groups, footer_controls)


func _append_visual_navigation_rows(groups: Array, controls: Array[Control]) -> void:
	if controls.is_empty():
		return
	controls.sort_custom(func(first: Control, second: Control) -> bool:
		return first.get_global_rect().get_center().y < second.get_global_rect().get_center().y
	)
	var current_row: Array[Control] = []
	var row_center_y: float = 0.0
	for control: Control in controls:
		var center_y: float = control.get_global_rect().get_center().y
		if current_row.is_empty() or abs(center_y - row_center_y) <= NAVIGATION_ROW_TOLERANCE:
			current_row.append(control)
			row_center_y = _get_average_control_center_y(current_row)
			continue
		current_row.sort_custom(func(first: Control, second: Control) -> bool:
			return first.get_global_rect().get_center().x < second.get_global_rect().get_center().x
		)
		_append_navigation_group(groups, current_row)
		current_row.clear()
		current_row.append(control)
		row_center_y = center_y
	if not current_row.is_empty():
		current_row.sort_custom(func(first: Control, second: Control) -> bool:
			return first.get_global_rect().get_center().x < second.get_global_rect().get_center().x
		)
		_append_navigation_group(groups, current_row)


func _get_average_control_center_y(controls: Array[Control]) -> float:
	var total: float = 0.0
	for control: Control in controls:
		total += control.get_global_rect().get_center().y
	return total / float(controls.size())


func _append_navigation_group(groups: Array, controls: Array[Control]) -> void:
	var valid_controls: Array[Control] = []
	for control: Control in controls:
		if _is_navigation_focus_target(control):
			valid_controls.append(control)
	if not valid_controls.is_empty():
		groups.append(valid_controls)


func _collect_primary_focus_targets(root: Node, controls: Array[Control]) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is Control:
		var control: Control = root as Control
		if not control.is_visible_in_tree():
			return
		if _is_navigation_focus_target(control):
			controls.append(control)
			return
	for child: Node in root.get_children():
		_collect_primary_focus_targets(child, controls)


func _is_navigation_focus_target(control: Control) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return control is BaseButton or control is LineEdit or control is Range or control is ItemList


func _find_navigation_location(groups: Array, focus_owner: Control) -> Vector2i:
	if focus_owner == null or not is_instance_valid(focus_owner):
		return Vector2i(-1, -1)
	for group_index: int in range(groups.size()):
		var group: Array = groups[group_index]
		for control_index: int in range(group.size()):
			var control: Control = group[control_index] as Control
			if focus_owner == control or control.is_ancestor_of(focus_owner):
				return Vector2i(group_index, control_index)
	return Vector2i(-1, -1)


func _get_horizontal_navigation_target(groups: Array, location: Vector2i, action: StringName) -> Control:
	var group: Array = groups[location.x]
	var direction: int = -1 if action == &"ui_left" else 1
	var target_index: int = clampi(location.y + direction, 0, group.size() - 1)
	return group[target_index] as Control


func _get_vertical_navigation_target(groups: Array, location: Vector2i, action: StringName) -> Control:
	var direction: int = -1 if action == &"ui_up" else 1
	var target_group_index: int = clampi(location.x + direction, 0, groups.size() - 1)
	var current_group: Array = groups[location.x]
	var target_group: Array = groups[target_group_index]
	var current_control: Control = current_group[location.y] as Control
	var current_center_x: float = current_control.get_global_rect().get_center().x
	var target: Control = target_group[0] as Control
	var best_distance: float = abs(target.get_global_rect().get_center().x - current_center_x)
	for candidate_value: Variant in target_group:
		var candidate: Control = candidate_value as Control
		var distance: float = abs(candidate.get_global_rect().get_center().x - current_center_x)
		if distance < best_distance:
			target = candidate
			best_distance = distance
	return target


func _has_open_option_popup(root: Node) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	if root is OptionButton:
		var popup: PopupMenu = (root as OptionButton).get_popup()
		if popup != null and popup.visible:
			return true
	for child: Node in root.get_children():
		if _has_open_option_popup(child):
			return true
	return false


func _configure_scroll_focus(scroll_container: ScrollContainer) -> void:
	if scroll_container == null:
		return
	scroll_container.focus_mode = Control.FOCUS_NONE
	scroll_container.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	scroll_container.get_h_scroll_bar().focus_mode = Control.FOCUS_NONE


func _handle_tab_input(event: InputEvent) -> bool:
	var direction: int = 0
	if event.is_action_pressed("ui_page_up"):
		direction = -1
	elif event.is_action_pressed("ui_page_down"):
		direction = 1
	elif event is InputEventJoypadButton:
		var joy_event: InputEventJoypadButton = event as InputEventJoypadButton
		if joy_event.pressed:
			if joy_event.button_index == JOY_BUTTON_LEFT_SHOULDER:
				direction = -1
			elif joy_event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				direction = 1
	if direction == 0:
		return false
	var tab_count: int = tabs.get_tab_count()
	if tab_count <= 0:
		return false
	tabs.current_tab = wrapi(tabs.current_tab + direction, 0, tab_count)
	call_deferred("_focus_active_tab")
	return true


func _on_tab_changed(_tab: int) -> void:
	if visible and not SettingsManager.is_mouse_input_active():
		call_deferred("_focus_active_tab")


func _build_loadout_rows() -> void:
	for child: Node in loadout_rows.get_children():
		loadout_rows.remove_child(child)
		child.queue_free()
	if _profile == null:
		var unavailable: Label = Label.new()
		unavailable.text = "This character does not provide a customizable settings profile."
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		loadout_rows.add_child(unavailable)
		reset_button.disabled = true
		conflict_label.text = ""
		return
	reset_button.disabled = not CharacterProfileManager.has_loadout_override(_profile)
	var effective_loadout: Array[Dictionary] = CharacterProfileManager.get_effective_loadout(_profile)
	for definition: Dictionary in _profile.ability_catalog:
		if not bool(definition.get("loadout_assignable", true)):
			continue
		_add_ability_row(definition, _find_binding(effective_loadout, StringName(definition.get("ability_id", &""))))
	_refresh_conflict_warning()


func _add_ability_row(definition: Dictionary, binding: Dictionary) -> void:
	var ability_id: StringName = StringName(definition.get("ability_id", &""))
	if ability_id == &"":
		return
	var container: VBoxContainer = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.set_meta("ability_id", ability_id)

	var name_label: Label = Label.new()
	name_label.text = String(definition.get("display_name", String(ability_id).capitalize()))
	name_label.tooltip_text = String(definition.get("description", ""))
	container.add_child(name_label)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	container.add_child(controls)

	var slot_label: Label = Label.new()
	slot_label.text = "Input Slot"
	slot_label.custom_minimum_size.x = 80.0
	controls.add_child(slot_label)

	var slot_option: OptionButton = OptionButton.new()
	slot_option.name = "Slot"
	slot_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_option.custom_minimum_size.x = 260.0
	slot_option.fit_to_longest_item = false
	slot_option.tooltip_text = "Generic physical input slot assigned to this ability."
	_populate_slot_options(slot_option, StringName(binding.get("slot", &"")))
	controls.add_child(slot_option)

	var chord_label: Label = Label.new()
	chord_label.text = "With"
	controls.add_child(chord_label)

	var chord_option: OptionButton = OptionButton.new()
	chord_option.name = "ChordSlot"
	chord_option.custom_minimum_size.x = 155.0
	chord_option.fit_to_longest_item = false
	chord_option.tooltip_text = "Optional second input slot that must be held simultaneously."
	_populate_slot_options(chord_option, _get_first_required_slot(binding), "No Chord")
	controls.add_child(chord_option)

	var gesture_label: Label = Label.new()
	gesture_label.text = "Activation"
	gesture_label.custom_minimum_size.x = 70.0
	controls.add_child(gesture_label)

	var gesture_option: OptionButton = OptionButton.new()
	gesture_option.name = "Gesture"
	gesture_option.custom_minimum_size.x = 120.0
	gesture_option.tooltip_text = "Input gesture that activates this ability."
	_populate_gesture_options(gesture_option, definition, StringName(binding.get("gesture", &"press")))
	controls.add_child(gesture_option)

	var hold_label: Label = Label.new()
	hold_label.name = "HoldLabel"
	hold_label.text = "Window"
	controls.add_child(hold_label)

	var hold_time: SpinBox = SpinBox.new()
	hold_time.name = "HoldTime"
	hold_time.min_value = HOLD_TIME_MIN
	hold_time.max_value = HOLD_TIME_MAX
	hold_time.step = HOLD_TIME_STEP
	hold_time.suffix = " s"
	hold_time.custom_minimum_size.x = 100.0
	hold_time.tooltip_text = "Tap window or hold duration in seconds."
	hold_time.value = clamp(float(binding.get("hold_time", 0.19)), HOLD_TIME_MIN, HOLD_TIME_MAX)
	controls.add_child(hold_time)

	var selected_gesture: StringName = _get_selected_metadata(gesture_option)
	_set_hold_time_visibility(hold_label, hold_time, selected_gesture)
	slot_option.item_selected.connect(func(_index: int) -> void:
		_save_row(container)
	)
	chord_option.item_selected.connect(func(_index: int) -> void:
		_save_row(container)
	)
	gesture_option.item_selected.connect(func(_index: int) -> void:
		_set_hold_time_visibility(hold_label, hold_time, _get_selected_metadata(gesture_option))
		_save_row(container)
	)
	hold_time.value_changed.connect(func(_value: float) -> void:
		_save_row(container)
	)

	loadout_rows.add_child(container)
	var separator: HSeparator = HSeparator.new()
	loadout_rows.add_child(separator)


func _build_route_rows() -> void:
	for child: Node in route_rows.get_children():
		route_rows.remove_child(child)
		child.queue_free()
	if _profile == null:
		var unavailable: Label = Label.new()
		unavailable.text = "This character does not provide customizable action routes."
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		route_rows.add_child(unavailable)
		add_route_button.disabled = true
		reset_routes_button.disabled = true
		return
	add_route_button.disabled = false
	reset_routes_button.disabled = not CharacterProfileManager.has_route_override(_profile)
	for route: Dictionary in CharacterProfileManager.get_effective_routes(_profile):
		_add_route_row(route)


func _add_route_row(route: Dictionary) -> void:
	var route_id: StringName = StringName(route.get("route_id", &""))
	if route_id == &"":
		return
	var container: VBoxContainer = VBoxContainer.new()
	container.add_theme_constant_override("separation", 6)
	container.set_meta("route_id", route_id)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	container.add_child(header)

	var enabled_toggle: CheckBox = CheckBox.new()
	enabled_toggle.name = "Enabled"
	enabled_toggle.text = String(route.get("display_name", String(route_id).capitalize()))
	enabled_toggle.button_pressed = bool(route.get("enabled", true))
	enabled_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enabled_toggle.tooltip_text = "Enables this action route."
	header.add_child(enabled_toggle)

	var remove_button: Button = Button.new()
	remove_button.name = "Remove"
	remove_button.text = "Remove"
	remove_button.tooltip_text = "Disables a packaged route or deletes a user-created route."
	header.add_child(remove_button)

	var controls: HFlowContainer = HFlowContainer.new()
	controls.name = "Controls"
	controls.add_theme_constant_override("h_separation", 12)
	controls.add_theme_constant_override("v_separation", 8)
	container.add_child(controls)

	var source_option: OptionButton = _add_route_option_field(controls, "Source", "Source action that owns the route.")
	_populate_route_action_options(source_option, StringName(route.get("source_action", &"")), false)
	var event_option: OptionButton = _add_route_option_field(controls, "Event", "Input or lifecycle event that evaluates the route.")
	_populate_definition_options(event_option, CharacterProfileManager.ROUTE_EVENTS, "event", "label", StringName(route.get("event", &"ability_triggered")))
	var input_option: OptionButton = _add_route_option_field(controls, "Input", "Ability input follows that ability's current loadout slot.")
	_populate_route_input_options(input_option, route)
	var target_option: OptionButton = _add_route_option_field(controls, "Target", "Action executed when this route succeeds.")
	_populate_route_action_options(target_option, StringName(route.get("target_action", &"")), true)
	var activation_option: OptionButton = _add_route_option_field(controls, "Activation", "How the target action receives the route.")
	_populate_definition_options(activation_option, CharacterProfileManager.ROUTE_ACTIVATIONS, "activation", "label", StringName(route.get("activation", &"execute")))
	var state_option: OptionButton = _add_route_option_field(controls, "State", "Player attachment state required for this route.")
	_populate_definition_options(state_option, CharacterProfileManager.ROUTE_STATES, "state", "label", StringName(route.get("required_state", &"any")))

	var priority_field: VBoxContainer = VBoxContainer.new()
	priority_field.name = "PriorityField"
	priority_field.custom_minimum_size.x = 110.0
	controls.add_child(priority_field)
	var priority_label: Label = Label.new()
	priority_label.text = "Priority"
	priority_field.add_child(priority_label)
	var priority: SpinBox = SpinBox.new()
	priority.name = "Priority"
	priority.min_value = -1000.0
	priority.max_value = 1000.0
	priority.step = 1.0
	priority.value = float(route.get("priority", 10))
	priority.tooltip_text = "Higher-priority routes are attempted first."
	priority_field.add_child(priority)

	var options_field: VBoxContainer = VBoxContainer.new()
	options_field.name = "OptionsField"
	options_field.custom_minimum_size.x = 220.0
	controls.add_child(options_field)
	var options_label: Label = Label.new()
	options_label.text = "Options"
	options_field.add_child(options_label)
	var consume_toggle: CheckBox = CheckBox.new()
	consume_toggle.name = "Consume"
	consume_toggle.text = "Consume Input"
	consume_toggle.button_pressed = bool(route.get("consume_input", true))
	consume_toggle.tooltip_text = "Stops normal ability dispatch after this input route succeeds."
	options_field.add_child(consume_toggle)
	var suppress_toggle: CheckBox = CheckBox.new()
	suppress_toggle.name = "SuppressUntilRelease"
	suppress_toggle.text = "Suppress Until Release"
	suppress_toggle.button_pressed = bool(route.get("suppress_input_until_release", false))
	suppress_toggle.tooltip_text = "Claims the routed input until every assigned slot has been released."
	options_field.add_child(suppress_toggle)

	_set_route_field_visibility(container)
	enabled_toggle.toggled.connect(func(_enabled: bool) -> void:
		_save_route_row(container)
	)
	remove_button.pressed.connect(func() -> void:
		_remove_route_row(container)
	)
	source_option.item_selected.connect(func(_index: int) -> void:
		_save_route_row(container)
	)
	event_option.item_selected.connect(func(_index: int) -> void:
		_set_route_field_visibility(container)
		_save_route_row(container)
	)
	input_option.item_selected.connect(func(_index: int) -> void:
		_save_route_row(container)
	)
	target_option.item_selected.connect(func(_index: int) -> void:
		_save_route_row(container)
	)
	activation_option.item_selected.connect(func(_index: int) -> void:
		_set_route_field_visibility(container)
		_save_route_row(container)
	)
	state_option.item_selected.connect(func(_index: int) -> void:
		_save_route_row(container)
	)
	priority.value_changed.connect(func(_value: float) -> void:
		_save_route_row(container)
	)
	consume_toggle.toggled.connect(func(_enabled: bool) -> void:
		_save_route_row(container)
	)
	suppress_toggle.toggled.connect(func(_enabled: bool) -> void:
		_save_route_row(container)
	)

	route_rows.add_child(container)
	var separator: HSeparator = HSeparator.new()
	route_rows.add_child(separator)


func _add_route_option_field(parent: HFlowContainer, field_name: String, tooltip: String) -> OptionButton:
	var field: VBoxContainer = VBoxContainer.new()
	field.name = field_name + "Field"
	field.custom_minimum_size.x = 170.0
	parent.add_child(field)
	var label: Label = Label.new()
	label.text = field_name
	field.add_child(label)
	var option: OptionButton = OptionButton.new()
	option.name = field_name
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.tooltip_text = tooltip
	field.add_child(option)
	return option


func _populate_definition_options(option: OptionButton, definitions: Array[Dictionary], id_key: String, label_key: String, selected_id: StringName) -> void:
	for definition: Dictionary in definitions:
		var item_id: StringName = StringName(definition.get(id_key, &""))
		option.add_item(String(definition.get(label_key, item_id)))
		var index: int = option.item_count - 1
		option.set_item_metadata(index, item_id)
		if item_id == selected_id:
			option.select(index)


func _populate_route_action_options(option: OptionButton, selected_action: StringName, allow_none: bool) -> void:
	if allow_none:
		option.add_item("None")
		option.set_item_metadata(0, &"")
	for definition: Dictionary in _get_routable_action_definitions():
		var action_id: StringName = StringName(definition.get("action_id", &""))
		option.add_item(String(definition.get("display_name", String(action_id).capitalize())))
		var index: int = option.item_count - 1
		option.set_item_metadata(index, action_id)
		if action_id == selected_action:
			option.select(index)


func _populate_route_input_options(option: OptionButton, route: Dictionary) -> void:
	var selected_ability: StringName = StringName(route.get("input_ability", &""))
	var selected_action: StringName = StringName(route.get("input_action", &""))
	option.add_item("Source Ability Input")
	option.set_item_metadata(0, {"ability": &"", "action": &""})
	for definition: Dictionary in _profile.ability_catalog:
		if not bool(definition.get("input_source", true)):
			continue
		var ability_id: StringName = StringName(definition.get("ability_id", &""))
		option.add_item(String(definition.get("display_name", String(ability_id).capitalize())))
		var index: int = option.item_count - 1
		option.set_item_metadata(index, {"ability": ability_id, "action": &""})
		if ability_id == selected_ability:
			option.select(index)
	if selected_ability == &"" and selected_action != &"":
		option.add_item("Fixed: %s" % String(selected_action))
		var fixed_index: int = option.item_count - 1
		option.set_item_metadata(fixed_index, {"ability": &"", "action": selected_action})
		option.select(fixed_index)


func _get_routable_action_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	var known: Dictionary = {}
	for ability: Dictionary in _profile.ability_catalog:
		var ability_id: StringName = StringName(ability.get("ability_id", &""))
		if ability_id == &"" or known.has(ability_id):
			continue
		known[ability_id] = true
		definitions.append({"action_id": ability_id, "display_name": String(ability.get("display_name", String(ability_id).capitalize()))})
	for route: Dictionary in CharacterProfileManager.get_effective_routes(_profile):
		for key: String in ["source_action", "target_action"]:
			var action_id: StringName = StringName(route.get(key, &""))
			if action_id == &"" or known.has(action_id):
				continue
			known[action_id] = true
			definitions.append({"action_id": action_id, "display_name": String(action_id).capitalize()})
	for action_id: StringName in [&"grounded", &"fall"]:
		if not known.has(action_id):
			definitions.append({"action_id": action_id, "display_name": String(action_id).capitalize()})
	return definitions


func _save_route_row(container: VBoxContainer) -> void:
	if _profile == null:
		return
	var route_id: StringName = StringName(container.get_meta("route_id", &""))
	var route: Dictionary = CharacterProfileManager.get_route(_profile, route_id)
	if route.is_empty():
		return
	var header: HBoxContainer = container.get_child(0) as HBoxContainer
	var controls: HFlowContainer = container.get_node("Controls") as HFlowContainer
	if header == null or controls == null:
		return
	var enabled_toggle: CheckBox = header.get_node("Enabled") as CheckBox
	var source_option: OptionButton = controls.get_node("SourceField/Source") as OptionButton
	var event_option: OptionButton = controls.get_node("EventField/Event") as OptionButton
	var input_option: OptionButton = controls.get_node("InputField/Input") as OptionButton
	var target_option: OptionButton = controls.get_node("TargetField/Target") as OptionButton
	var activation_option: OptionButton = controls.get_node("ActivationField/Activation") as OptionButton
	var state_option: OptionButton = controls.get_node("StateField/State") as OptionButton
	var priority: SpinBox = controls.get_node("PriorityField/Priority") as SpinBox
	var consume_toggle: CheckBox = controls.get_node("OptionsField/Consume") as CheckBox
	var suppress_toggle: CheckBox = controls.get_node("OptionsField/SuppressUntilRelease") as CheckBox
	route["enabled"] = enabled_toggle.button_pressed
	route["source_action"] = _get_selected_metadata(source_option)
	route["event"] = _get_selected_metadata(event_option)
	var input_metadata: Variant = input_option.get_item_metadata(input_option.selected)
	if input_metadata is Dictionary:
		route["input_ability"] = StringName((input_metadata as Dictionary).get("ability", &""))
		route["input_action"] = StringName((input_metadata as Dictionary).get("action", &""))
	route["target_action"] = _get_selected_metadata(target_option)
	route["activation"] = _get_selected_metadata(activation_option)
	route["required_state"] = _get_selected_metadata(state_option)
	route["priority"] = int(priority.value)
	route["consume_input"] = consume_toggle.button_pressed
	route["suppress_input_until_release"] = suppress_toggle.button_pressed
	CharacterProfileManager.set_route(_profile, route)
	reset_routes_button.disabled = false


func _set_route_field_visibility(container: VBoxContainer) -> void:
	var controls: HFlowContainer = container.get_node("Controls") as HFlowContainer
	if controls == null:
		return
	var event_option: OptionButton = controls.get_node("EventField/Event") as OptionButton
	var activation_option: OptionButton = controls.get_node("ActivationField/Activation") as OptionButton
	var event: StringName = _get_selected_metadata(event_option)
	var activation: StringName = _get_selected_metadata(activation_option)
	var input_field: Control = controls.get_node("InputField") as Control
	var target_field: Control = controls.get_node("TargetField") as Control
	var suppress_toggle: CheckBox = controls.get_node("OptionsField/SuppressUntilRelease") as CheckBox
	var uses_input: bool = _route_event_uses_input(event)
	input_field.visible = uses_input
	suppress_toggle.visible = uses_input
	target_field.visible = event != CharacterProfileManager.ROUTE_EVENT_POLICY and activation != CharacterProfileManager.ROUTE_ACTIVATION_NEUTRAL_AIR and activation != CharacterProfileManager.ROUTE_ACTIVATION_CLEAR_ACTIVE


func _route_event_uses_input(event: StringName) -> bool:
	return event == CharacterProfileManager.ROUTE_EVENT_ABILITY_TRIGGERED or event == CharacterProfileManager.ROUTE_EVENT_INPUT_PRESSED or event == CharacterProfileManager.ROUTE_EVENT_INPUT_HELD or event == CharacterProfileManager.ROUTE_EVENT_INPUT_RELEASED


func _remove_route_row(container: VBoxContainer) -> void:
	if _profile == null:
		return
	CharacterProfileManager.remove_route(_profile, StringName(container.get_meta("route_id", &"")))
	_build_route_rows()
	call_deferred("_focus_active_tab")


func _on_add_route_pressed() -> void:
	if _profile == null or _profile.ability_catalog.is_empty():
		return
	var source_action: StringName = StringName(_profile.ability_catalog[0].get("ability_id", &""))
	var target_action: StringName = source_action
	if _profile.ability_catalog.size() > 1:
		target_action = StringName(_profile.ability_catalog[1].get("ability_id", source_action))
	var route_id: StringName = StringName("user_route_%d" % Time.get_ticks_usec())
	CharacterProfileManager.set_route(_profile, {
		"route_id": route_id,
		"display_name": "Custom Route",
		"source_action": source_action,
		"event": CharacterProfileManager.ROUTE_EVENT_INPUT_RELEASED,
		"input_ability": source_action,
		"target_action": target_action,
		"activation": CharacterProfileManager.ROUTE_ACTIVATION_EXECUTE,
		"required_state": CharacterProfileManager.ROUTE_STATE_ANY,
		"priority": 10,
		"enabled": true,
		"consume_input": true,
	})
	_build_route_rows()


func _populate_slot_options(option: OptionButton, selected_slot: StringName, empty_label: String = "Unassigned") -> void:
	option.add_item(empty_label)
	option.set_item_metadata(0, &"")
	for slot_definition: Dictionary in CharacterProfileManager.INPUT_SLOTS:
		var slot: StringName = StringName(slot_definition.get("slot", &""))
		var slot_label: String = String(slot_definition.get("label", slot))
		var binding_summary: String = _get_input_action_binding_summary(slot)
		option.add_item("%s (%s)" % [slot_label, binding_summary])
		var index: int = option.item_count - 1
		option.set_item_metadata(index, slot)
		option.set_item_tooltip(index, "%s is currently bound to %s." % [slot_label, binding_summary])
		if slot == selected_slot:
			option.select(index)


func _get_first_required_slot(binding: Dictionary) -> StringName:
	var required_slots_value: Variant = binding.get("required_slots", [])
	if not (required_slots_value is Array) or (required_slots_value as Array).is_empty():
		return &""
	return StringName((required_slots_value as Array)[0])


func _get_input_action_binding_summary(action_name: StringName) -> String:
	if action_name == &"" or not InputMap.has_action(action_name):
		return "Unbound"
	var labels: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action_name):
		var label: String = _get_input_event_label(event)
		if label != "" and not labels.has(label):
			labels.append(label)
	if labels.is_empty():
		return "Unbound"
	return " / ".join(labels)


func _get_input_event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		var keycode_value: int = int(key_event.keycode)
		if keycode_value == Key.KEY_NONE:
			keycode_value = int(key_event.physical_keycode)
		if keycode_value != Key.KEY_NONE:
			return OS.get_keycode_string(keycode_value)
		return ""
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		match mouse_event.button_index:
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
			_:
				return "Mouse Button %d" % int(mouse_event.button_index)
	if event is InputEventJoypadButton:
		var joy_button_event: InputEventJoypadButton = event as InputEventJoypadButton
		return "Joypad Button %d" % int(joy_button_event.button_index)
	if event is InputEventJoypadMotion:
		var joy_motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion
		var direction: String = "+" if joy_motion_event.axis_value >= 0.0 else "-"
		return "Joypad Axis %d%s" % [int(joy_motion_event.axis), direction]
	return event.as_text()


func _populate_gesture_options(option: OptionButton, definition: Dictionary, selected_gesture: StringName) -> void:
	var supported_value: Variant = definition.get("supported_gestures", [])
	var supported: Array = []
	if supported_value is Array:
		supported = supported_value
	for gesture_definition: Dictionary in CharacterProfileManager.GESTURES:
		var gesture: StringName = StringName(gesture_definition.get("gesture", &""))
		if not supported.is_empty() and not supported.has(gesture):
			continue
		option.add_item(String(gesture_definition.get("label", gesture)))
		var index: int = option.item_count - 1
		option.set_item_metadata(index, gesture)
		if gesture == selected_gesture:
			option.select(index)


func _save_row(container: VBoxContainer) -> void:
	if _profile == null:
		return
	var controls: HBoxContainer = container.get_child(1) as HBoxContainer
	if controls == null:
		return
	var slot_option: OptionButton = controls.get_node("Slot") as OptionButton
	var chord_option: OptionButton = controls.get_node("ChordSlot") as OptionButton
	var gesture_option: OptionButton = controls.get_node("Gesture") as OptionButton
	var hold_time: SpinBox = controls.get_node("HoldTime") as SpinBox
	var ability_id: StringName = StringName(container.get_meta("ability_id", &""))
	var previous: Dictionary = CharacterProfileManager.get_binding(_profile, ability_id)
	var binding: Dictionary = previous.duplicate(true)
	binding["ability_id"] = ability_id
	var primary_slot: StringName = _get_selected_metadata(slot_option)
	var chord_slot: StringName = _get_selected_metadata(chord_option)
	if primary_slot == &"" or chord_slot == primary_slot:
		chord_slot = &""
		chord_option.select(0)
	binding["slot"] = primary_slot
	var required_slots: Array[StringName] = []
	if chord_slot != &"" and chord_slot != primary_slot:
		required_slots.append(chord_slot)
	binding["required_slots"] = required_slots
	binding["gesture"] = _get_selected_metadata(gesture_option)
	binding["hold_time"] = float(hold_time.value)
	CharacterProfileManager.set_binding(_profile, binding)
	reset_button.disabled = false
	_refresh_conflict_warning()


func _refresh_conflict_warning() -> void:
	if _profile == null:
		conflict_label.text = ""
		return
	var bindings_by_slot: Dictionary = {}
	var conflicts: Array[String] = []
	for binding: Dictionary in CharacterProfileManager.get_effective_loadout(_profile):
		var slot: StringName = StringName(binding.get("slot", &""))
		if slot == &"":
			continue
		var previous_bindings: Array = bindings_by_slot.get(slot, [])
		for previous_value: Variant in previous_bindings:
			if not (previous_value is Dictionary):
				continue
			var previous_binding: Dictionary = previous_value
			var shared_allowed: bool = bool(previous_binding.get("allow_shared", false)) and bool(binding.get("allow_shared", false))
			if not shared_allowed and _bindings_potentially_conflict(previous_binding, binding):
				var previous_id: StringName = StringName(previous_binding.get("ability_id", &""))
				var ability_id: StringName = StringName(binding.get("ability_id", &""))
				conflicts.append("%s and %s share %s" % [_get_ability_display_name(previous_id), _get_ability_display_name(ability_id), CharacterProfileManager.get_slot_label(slot)])
		previous_bindings.append(binding)
		bindings_by_slot[slot] = previous_bindings
	conflict_label.text = "Potential conflicts: %s" % "; ".join(conflicts) if not conflicts.is_empty() else ""


func _bindings_potentially_conflict(first: Dictionary, second: Dictionary) -> bool:
	var first_gesture: StringName = StringName(first.get("gesture", &"press"))
	var second_gesture: StringName = StringName(second.get("gesture", &"press"))
	if first_gesture == second_gesture:
		return true
	if first_gesture == CharacterProfileManager.GESTURE_PRESS or second_gesture == CharacterProfileManager.GESTURE_PRESS:
		return true
	return (first_gesture == CharacterProfileManager.GESTURE_TAP and second_gesture == CharacterProfileManager.GESTURE_RELEASE) or (first_gesture == CharacterProfileManager.GESTURE_RELEASE and second_gesture == CharacterProfileManager.GESTURE_TAP)


func _get_ability_display_name(ability_id: StringName) -> String:
	if _profile != null:
		var definition: Dictionary = _profile.get_ability_definition(ability_id)
		if not definition.is_empty():
			return String(definition.get("display_name", String(ability_id).capitalize()))
	return String(ability_id).capitalize()


func _find_binding(loadout: Array[Dictionary], ability_id: StringName) -> Dictionary:
	for binding: Dictionary in loadout:
		if StringName(binding.get("ability_id", &"")) == ability_id:
			return binding
	return {"ability_id": ability_id, "slot": &"", "gesture": &"press", "hold_time": 0.19}


func _get_selected_metadata(option: OptionButton) -> StringName:
	if option == null or option.selected < 0:
		return &""
	return StringName(option.get_item_metadata(option.selected))


func _set_hold_time_visibility(label: Label, spin_box: SpinBox, gesture: StringName) -> void:
	var uses_window: bool = gesture == CharacterProfileManager.GESTURE_TAP or gesture == CharacterProfileManager.GESTURE_HOLD
	label.visible = uses_window
	spin_box.visible = uses_window


func _on_reset_pressed() -> void:
	if _profile == null:
		return
	CharacterProfileManager.reset_loadout(_profile)
	_build_loadout_rows()
	call_deferred("_focus_active_tab")


func _on_reset_routes_pressed() -> void:
	if _profile == null:
		return
	CharacterProfileManager.reset_routes(_profile)
	_build_route_rows()
	call_deferred("_focus_active_tab")


func _on_visibility_changed() -> void:
	if visible:
		call_deferred("_focus_active_tab")
	else:
		_clear_navigation_repeat()


func _focus_active_tab() -> void:
	if not visible or tabs == null:
		return
	var loadout_tab: Control = tabs.get_node("Loadout") as Control
	var routes_tab: Control = tabs.get_node("Routes") as Control
	if tabs.current_tab == tabs.get_tab_idx_from_control(loadout_tab):
		_focus_first_loadout_control()
		return
	if tabs.current_tab == tabs.get_tab_idx_from_control(routes_tab):
		if add_route_button.visible and not add_route_button.disabled:
			add_route_button.grab_focus()
			return
		if _focus_first_control(route_rows):
			return
	close_button.grab_focus()


func _focus_first_control(root: Node) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	if root is Control:
		var control: Control = root as Control
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and (control is BaseButton or control is LineEdit or control is Range or control is ItemList):
			control.grab_focus()
			return true
	for child: Node in root.get_children():
		if _focus_first_control(child):
			return true
	return false


func _focus_first_loadout_control() -> void:
	for child: Node in loadout_rows.get_children():
		if not (child is VBoxContainer):
			continue
		var controls: HBoxContainer = child.get_child(1) as HBoxContainer
		var slot_option: OptionButton = null
		if controls != null:
			slot_option = controls.get_node_or_null("Slot") as OptionButton
		if slot_option != null:
			slot_option.grab_focus()
			return
	close_button.grab_focus()

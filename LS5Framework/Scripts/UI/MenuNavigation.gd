extends Node

signal action_cancelled(scope_root: Control)

const DIRECTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]
const THEME_FACTORY = preload("res://LS5Framework/Scripts/UI/MenuPresentation.gd")

var _hosts: Array[Dictionary] = []
var _scope: Dictionary = {}
## Current menu boundary for focus and directional input.
var _root: Control
var _scope_key: String = ""
var _memory: Dictionary = {}
var _memory_index: Dictionary = {}
var _held: StringName = &""
var _repeat_remaining: float = 0.0
var _held_seconds: float = 0.0
var _release_barrier: bool = false
var _axis: Vector2 = Vector2.ZERO
var _controller_device: int = -1
var _stick_direction: StringName = &""
## Vertical scrollbar receiving right-stick input.
var _right_stick_scrollbar: VScrollBar
var _right_stick_scroll_remainder: float = 0.0
var _keyboard_active: bool = true
var _restoring: bool = false
var _popup_was_open: bool = false
var _theme: Theme
## Provides controller text entry for editable menu fields.
var _text_entry: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = THEME_FACTORY.create_theme()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var frame: Control = preload("res://LS5Framework/Scripts/UI/MenuFocusFrame.gd").new()
	frame.navigation = self
	layer.add_child(frame)
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void:
		_clear_repeat()
		_axis = Vector2.ZERO
		_stick_direction = &""
		_release_barrier = _any_menu_input_held()
	)


func register_menu(host: Node, provider: Callable, priority: int = 10) -> void:
	_hosts.append({"host": weakref(host), "provider": provider, "priority": priority})
	if host is Control:
		(host as Control).theme = _theme
	else:
		for child: Node in host.get_children():
			if child is Control:
				(child as Control).theme = _theme
	_adapt_panels.call_deferred(host)


func _adapt_panels(host: Node) -> void:
	if not is_instance_valid(host):
		return
	for path: NodePath in [^"Overlay/OnlinePanel/Panel", ^"Root/Panel"]:
		var panel: Control = host.get_node_or_null(path) as Control
		if panel:
			var layout: Node = preload("res://LS5Framework/Scripts/UI/MenuPanelViewport.gd").new()
			layout.panel = panel
			layout.form_layout = path == ^"Overlay/OnlinePanel/Panel"
			host.add_child(layout)


func restore_focus() -> void:
	_refresh_scope()
	_restore_focus()


func forget_focus(scope_root: Control) -> void:
	var prefix: String = str(scope_root.get_instance_id()) + ":"
	for key: String in _memory.keys():
		if key.begins_with(prefix):
			_memory.erase(key)
			_memory_index.erase(key)


func _refresh_scope() -> void:
	var next: Dictionary = {}
	var best_priority: int = -1
	for index: int in range(_hosts.size() - 1, -1, -1):
		var entry: Dictionary = _hosts[index]
		var host: Node = entry["host"].get_ref()
		if not is_instance_valid(host):
			_hosts.remove_at(index)
			continue
		var candidate: Dictionary = entry["provider"].call()
		var candidate_root: Control = candidate.get("root") as Control
		if candidate_root and candidate_root.is_visible_in_tree() and int(entry["priority"]) > best_priority:
			next = candidate
			best_priority = int(entry["priority"])
	var next_root: Control = next.get("root") as Control
	var key: String = ""
	if next_root:
		key = str(next_root.get_instance_id()) + ":" + String(next.get("page", ""))
	if key != _scope_key:
		_remember_focus()
		_scope = next
		_root = next_root
		_scope_key = key
		_right_stick_scrollbar = null
		_right_stick_scroll_remainder = 0.0
		_clear_repeat()
		_release_barrier = _any_menu_input_held()
		if _root:
			_restore_focus()
	else:
		_scope = next


func _process(delta: float) -> void:
	_refresh_scope()
	if not _root or bool(_scope.get("suspended", false)):
		_clear_repeat()
		return
	var popup_open: bool = _has_popup(_root)
	if popup_open:
		_popup_was_open = true
		_clear_repeat()
		return
	if _popup_was_open:
		_popup_was_open = false
		_release_barrier = _any_menu_input_held()
		_restore_focus()
	if _release_barrier:
		if not _any_menu_input_held():
			_release_barrier = false
		return
	if _keyboard_active and not _eligible(get_viewport().gui_get_focus_owner()):
		_restore_focus()
	_scroll_with_right_stick(delta)
	if _held == &"":
		return
	if _stick_direction != _held and not Input.is_action_pressed(_held):
		_clear_repeat()
		return
	_held_seconds += delta
	_repeat_remaining -= delta
	if _repeat_remaining <= 0.0:
		_navigate(_held)
		var focus: Control = get_viewport().gui_get_focus_owner()
		_repeat_remaining = 0.045 if focus is Range and _held_seconds > 0.65 else 0.09


func _input(event: InputEvent) -> void:
	SettingsManager.track_input_device(event)
	_refresh_scope()
	if not _root or bool(_scope.get("suspended", false)):
		return
	if event is InputEventMouseMotion:
		if event.relative.length_squared() > 16.0:
			_keyboard_active = false
			_clear_repeat()
			_stick_direction = &""
		return
	if event is InputEventMouseButton:
		_keyboard_active = false
		var hovered: Control = get_viewport().gui_get_hovered_control()
		var pointer_focus: Callable = _scope.get("pointer_focus", Callable())
		if event.pressed and hovered and pointer_focus.is_valid() and not _has_popup(_root):
			pointer_focus.call(hovered)
			_refresh_scope()
		if event.pressed and not _has_popup(_root) and hovered and not (hovered == _root or _root.is_ancestor_of(hovered)):
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if hovered is Range and not (hovered is ScrollBar):
				var scroll: ScrollContainer = _parent_scroll(hovered)
				if scroll:
					scroll.scroll_vertical += -56 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 56
					get_viewport().set_input_as_handled()
		return
	if _has_popup(_root):
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if _release_barrier:
		if _is_menu_event(event):
			get_viewport().set_input_as_handled()
		return
	var cancel: Callable = _scope.get("cancel", Callable())
	var panel_switch: Callable = _scope.get("panel_switch", Callable())
	if panel_switch.is_valid() and panel_switch.call(event):
		get_viewport().set_input_as_handled()
		return
	if cancel.is_valid() and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		action_cancelled.emit(_root)
		cancel.call()
		get_viewport().set_input_as_handled()
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus and focus.has_method("menu_event") and bool(focus.call("menu_event", event)):
		get_viewport().set_input_as_handled()
		return
	if (focus is LineEdit or focus is TextEdit) and bool(focus.get_meta(&"menu_editing", false)):
		if event.is_action_pressed(&"ui_cancel"):
			focus.set_meta(&"menu_editing", false)
			if focus.get_parent() is SpinBox:
				_focus(focus.get_parent() as Control)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"ui_accept") and focus is LineEdit:
			focus.set_meta(&"menu_editing", false)
			(focus as LineEdit).text_submitted.emit((focus as LineEdit).text)
			get_viewport().set_input_as_handled()
		return
	if (focus is LineEdit or focus is TextEdit) and event is InputEventKey and event.pressed and event.unicode >= 32 and not _is_menu_event(event):
		focus.set_meta(&"menu_editing", true)
		return
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_keyboard_active = true
		if event is InputEventKey and not event.echo:
			_stick_direction = &""
			_axis = Vector2.ZERO
		elif event is InputEventJoypadButton and event.device != _controller_device:
			_controller_device = event.device
			_stick_direction = &""
			_axis = Vector2.ZERO
			_clear_repeat()
	if event is InputEventKey and event.echo:
		if _is_menu_event(event):
			get_viewport().set_input_as_handled()
		return
	var direction: StringName = &""
	if event is InputEventJoypadMotion:
		if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			return
		if event.device != _controller_device:
			if absf(event.axis_value) < 0.55:
				get_viewport().set_input_as_handled()
				return
			_controller_device = event.device
			_axis = Vector2.ZERO
			_stick_direction = &""
			_clear_repeat()
		if event.axis == JOY_AXIS_LEFT_X:
			_axis.x = event.axis_value
		else:
			_axis.y = event.axis_value
		if _axis.length() < 0.32:
			if _held == _stick_direction:
				_clear_repeat()
			_stick_direction = &""
		elif _axis.length() >= 0.55:
			_keyboard_active = true
			if absf(_axis.x) > absf(_axis.y) + 0.12:
				direction = &"ui_left" if _axis.x < 0.0 else &"ui_right"
			elif absf(_axis.y) > absf(_axis.x) + 0.12:
				direction = &"ui_up" if _axis.y < 0.0 else &"ui_down"
			else:
				direction = _stick_direction
			_stick_direction = direction
		get_viewport().set_input_as_handled()
	else:
		for action: StringName in DIRECTIONS:
			if event.is_action_pressed(action):
				direction = action
			elif event.is_action_released(action) and _held == action:
				_clear_repeat()
	if direction != &"":
		if direction != _held:
			_held = direction
			_held_seconds = 0.0
			_repeat_remaining = 0.30
			_navigate(direction)
		get_viewport().set_input_as_handled()
		return
	if _change_category(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_next") or event.is_action_pressed(&"ui_focus_prev"):
		_move_linear(-1 if event.is_action_pressed(&"ui_focus_prev") else 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept"):
		if not _eligible(focus):
			_restore_focus()
			get_viewport().set_input_as_handled()
			return
		if focus.has_method("menu_confirm"):
			focus.call("menu_confirm")
		elif focus is OptionButton:
			(focus as OptionButton).button_down.emit()
			(focus as OptionButton).show_popup()
			(focus as OptionButton).pressed.emit()
		elif focus is ColorPickerButton:
			(focus as ColorPickerButton).button_down.emit()
			(focus as ColorPickerButton).get_popup().popup_centered()
			(focus as ColorPickerButton).pressed.emit()
		elif focus is SpinBox:
			var editor: LineEdit = (focus as SpinBox).get_line_edit()
			if event is InputEventJoypadButton:
				_open_text_entry(editor)
			else:
				editor.set_meta(&"menu_editing", true)
				editor.grab_focus()
		elif focus is LineEdit or focus is TextEdit:
			if focus is LineEdit and event is InputEventJoypadButton and (focus as LineEdit).editable:
				_open_text_entry(focus as LineEdit)
			else:
				focus.set_meta(&"menu_editing", true)
		elif focus is BaseButton:
			var button: BaseButton = focus as BaseButton
			button.button_down.emit()
			if button.toggle_mode:
				button.button_pressed = not button.button_pressed
			button.pressed.emit()
		elif focus is ItemList:
			var list: ItemList = focus as ItemList
			if list.get_selected_items().size():
				list.item_activated.emit(list.get_selected_items()[0])
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"ui_accept"):
		get_viewport().set_input_as_handled()


func _navigate(action: StringName) -> void:
	if not _root:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit and focus.get_parent() is SpinBox and not bool(focus.get_meta(&"menu_editing", false)):
		focus = focus.get_parent() as Control
		_focus(focus)
	if not _eligible(focus):
		_restore_focus()
		return
	if focus.has_method("menu_navigate"):
		focus.call("menu_navigate", action)
		return
	var horizontal: bool = action in [&"ui_left", &"ui_right"]
	var direction: int = -1 if action in [&"ui_left", &"ui_up"] else 1
	if horizontal and focus is Range and not (focus is ScrollBar):
		var value_control: Range = focus as Range
		var fine: float = value_control.step if value_control.step > 0.0 else (value_control.max_value - value_control.min_value) / 100.0
		var multiplier: float = maxf(1.0, floorf((value_control.max_value - value_control.min_value) / maxf(fine, 0.001) / 30.0)) if _held_seconds > 0.65 else 1.0
		value_control.value = clampf(value_control.value + fine * multiplier * direction, value_control.min_value, value_control.max_value)
		return
	if horizontal and focus is OptionButton:
		var option: OptionButton = focus as OptionButton
		var index: int = option.selected + direction
		while index >= 0 and index < option.item_count:
			if not option.is_item_disabled(index) and not option.is_item_separator(index):
				option.select(index)
				option.item_selected.emit(index)
				return
			index += direction
		return
	if horizontal and focus is BaseButton and (focus as BaseButton).toggle_mode:
		(focus as BaseButton).button_pressed = direction > 0
		return
	if focus is ItemList and not horizontal:
		var list: ItemList = focus as ItemList
		var selected: PackedInt32Array = list.get_selected_items()
		var index: int = selected[0] if selected.size() else -1
		var next: int = index + direction
		while next >= 0 and next < list.item_count:
			if not list.is_item_disabled(next) and list.is_item_selectable(next):
				list.select(next)
				list.ensure_current_is_visible()
				list.item_selected.emit(next)
				return
			next += direction
	if focus is ItemList and horizontal:
		_move_linear(direction)
		return
	var targets: Array[Control] = _targets()
	var current: int = targets.find(focus)
	if current < 0:
		_restore_focus()
		return
	if horizontal:
		var parent: Node = focus.get_parent()
		if parent is HBoxContainer:
			var neighbor: int = current + direction
			if neighbor >= 0 and neighbor < targets.size() and targets[neighbor].get_parent() == parent:
				_focus(targets[neighbor])
		return
	var row: Node = _logical_row(focus)
	var next_index: int = current + direction
	while next_index >= 0 and next_index < targets.size() and _logical_row(targets[next_index]) == row:
		next_index += direction
	if next_index >= 0 and next_index < targets.size():
		var destination: Node = _logical_row(targets[next_index])
		if row is HBoxContainer and destination is HBoxContainer:
			var source_group: Array[Control] = []
			var destination_group: Array[Control] = []
			for candidate: Control in targets:
				if _logical_row(candidate) == row:
					source_group.append(candidate)
				elif _logical_row(candidate) == destination:
					destination_group.append(candidate)
			_focus(destination_group[clampi(source_group.find(focus), 0, destination_group.size() - 1)])
		else:
			_focus(targets[next_index])


func _move_linear(direction: int) -> void:
	var targets: Array[Control] = _targets()
	if targets.is_empty():
		return
	var index: int = targets.find(get_viewport().gui_get_focus_owner())
	_focus(targets[clampi(index + direction, 0, targets.size() - 1)])


func _logical_row(control: Control) -> Node:
	if control.get_parent() is HBoxContainer:
		var values: int = 0
		for child: Node in control.get_parent().get_children():
			if child is OptionButton or child is Range or child is LineEdit or child is ColorPickerButton:
				values += 1
		if values > 1:
			return control
		return control.get_parent()
	return control


func _change_category(event: InputEvent) -> bool:
	var tabs: TabContainer = _scope.get("tabs") as TabContainer
	if not tabs:
		return false
	var direction: int = 0
	if event.is_action_pressed(&"ui_page_up"):
		direction = -1
	elif event.is_action_pressed(&"ui_page_down"):
		direction = 1
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			direction = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			direction = 1
	if not direction or tabs.get_tab_count() < 2:
		return false
	_remember_focus()
	tabs.current_tab = wrapi(tabs.current_tab + direction, 0, tabs.get_tab_count())
	_refresh_scope()
	_restore_focus()
	return true


func _targets() -> Array[Control]:
	var result: Array[Control] = []
	_collect(_root, result)
	return result


func _collect(node: Node, result: Array[Control]) -> void:
	if node is Control:
		var control: Control = node as Control
		if not control.is_visible_in_tree() or control.is_queued_for_deletion():
			return
		if control is SpinBox and (control as SpinBox).editable and (control as SpinBox).get_line_edit().focus_mode != Control.FOCUS_NONE:
			control.focus_mode = Control.FOCUS_ALL
		if _eligible(control):
			result.append(control)
			return
	for child: Node in node.get_children():
		_collect(child, result)


func _eligible(control: Control) -> bool:
	if not is_instance_valid(control) or not _root or control.is_queued_for_deletion():
		return false
	if not (control == _root or _root.is_ancestor_of(control)) or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return false
	if control is ScrollBar or control is TabBar or control is ScrollContainer:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	if control is Slider and not (control as Slider).editable:
		return false
	if control is SpinBox and not (control as SpinBox).editable:
		return false
	if control is LineEdit and not (control as LineEdit).editable:
		return false
	return control is BaseButton or control is Range or control is LineEdit or control is TextEdit or control is ItemList or control.has_method("menu_navigate")


func _remember_focus() -> void:
	if not _root:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if _eligible(focus):
		_memory[_scope_key] = _root.get_path_to(focus)


func _restore_focus() -> void:
	if not _root or _restoring or bool(_scope.get("suspended", false)):
		return
	var target: Control
	if _memory.has(_scope_key):
		target = _root.get_node_or_null(_memory[_scope_key]) as Control
		if not _eligible(target):
			var available: Array[Control] = _targets()
			if not available.is_empty():
				target = available[clampi(int(_memory_index.get(_scope_key, 0)), 0, available.size() - 1)]
	if not _eligible(target):
		target = _scope.get("default") as Control
	if not _eligible(target):
		var targets: Array[Control] = _targets()
		if targets.is_empty():
			return
		target = targets[0]
	_focus(target)


func _focus(control: Control) -> void:
	_restoring = true
	control.grab_focus()
	_restoring = false
	_memory[_scope_key] = _root.get_path_to(control)
	_memory_index[_scope_key] = _targets().find(control)
	if control.has_method("menu_focus_entered"):
		control.call("menu_focus_entered")
	_reveal_focus(control)
	_reveal_focus_instance.call_deferred(control.get_instance_id())
	_update_description(control)


func _reveal_focus_instance(instance_id: int) -> void:
	var control: Control = instance_from_id(instance_id) as Control
	if _eligible(control) and control.get_viewport().gui_get_focus_owner() == control:
		_reveal_focus(control)


func _reveal_focus(control: Control) -> void:
	var parent: Node = control.get_parent()
	while parent and parent != _root:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(control)
		parent = parent.get_parent()


func _on_focus_changed(control: Control) -> void:
	if not _root or _restoring or bool(_scope.get("suspended", false)) or _has_popup(_root):
		return
	if _eligible(control):
		if not _keyboard_active and (control is LineEdit or control is TextEdit):
			control.set_meta(&"menu_editing", true)
		_memory[_scope_key] = _root.get_path_to(control)
		_memory_index[_scope_key] = _targets().find(control)
		_update_description(control)
	elif _keyboard_active:
		call_deferred("_restore_focus")


func _update_description(control: Control) -> void:
	var description: Label = _scope.get("description") as Label
	if description:
		description.text = control.tooltip_text if not control.tooltip_text.is_empty() else "Choose an option. Use left and right to adjust values."


func _parent_scroll(control: Control) -> ScrollContainer:
	var parent: Node = control.get_parent()
	while parent and parent != _root:
		if parent is ScrollContainer:
			return parent as ScrollContainer
		parent = parent.get_parent()
	return null


func _has_popup(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is Window and (child as Window).visible:
			return true
		if _has_popup(child):
			return true
	return false


func _clear_repeat() -> void:
	_held = &""
	_held_seconds = 0.0
	_repeat_remaining = 0.0


func _scroll_with_right_stick(delta: float) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var device: int = SettingsManager.get_preferred_joypad_device()
	if device < 0:
		return
	var amount: float = Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
	if absf(amount) < 0.25:
		_right_stick_scroll_remainder = 0.0
		return
	_scroll_menu_vertical(amount * 900.0 * delta, focus)


func _scroll_menu_vertical(pixels: float, focus: Control) -> void:
	var scrollbar: VScrollBar
	if is_instance_valid(focus) and (focus == _root or _root.is_ancestor_of(focus)):
		var node: Node = focus
		while node:
			scrollbar = _vertical_scrollbar(node)
			if scrollbar or node == _root:
				break
			node = node.get_parent()
	if not scrollbar:
		scrollbar = _find_visible_vertical_scrollbar(_root)
	if not scrollbar:
		return
	if scrollbar != _right_stick_scrollbar:
		_right_stick_scrollbar = scrollbar
		_right_stick_scroll_remainder = 0.0
	_right_stick_scroll_remainder += pixels
	var step: int = int(_right_stick_scroll_remainder)
	_right_stick_scroll_remainder -= step
	if step:
		scrollbar.value += step


func _vertical_scrollbar(node: Node) -> VScrollBar:
	var scrollbar: VScrollBar
	if node is ScrollContainer:
		scrollbar = node.get_v_scroll_bar()
	elif node is RichTextLabel and node.scroll_active:
		scrollbar = node.get_v_scroll_bar()
	if scrollbar and scrollbar.is_visible_in_tree() and scrollbar.max_value - scrollbar.page > scrollbar.min_value:
		return scrollbar
	return null


func _find_visible_vertical_scrollbar(node: Node) -> VScrollBar:
	if node is CanvasItem and not node.is_visible_in_tree():
		return null
	var scrollbar: VScrollBar = _vertical_scrollbar(node)
	if scrollbar:
		return scrollbar
	for child: Node in node.get_children():
		scrollbar = _find_visible_vertical_scrollbar(child)
		if scrollbar:
			return scrollbar
	return null


func _any_menu_input_held() -> bool:
	for action: StringName in [&"ui_accept", &"ui_cancel", &"pause", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if Input.is_action_pressed(action):
			return true
	return false


func _is_menu_event(event: InputEvent) -> bool:
	for action: StringName in [&"ui_accept", &"ui_cancel", &"pause", &"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev", &"ui_page_up", &"ui_page_down"]:
		if event.is_action(action):
			return true
	return event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_repeat()
		_axis = Vector2.ZERO
		_stick_direction = &""
		_release_barrier = true


func _open_text_entry(editor: LineEdit) -> void:
	if not is_instance_valid(_text_entry):
		_text_entry = load("res://LS5Framework/Scripts/UI/MenuTextEntry.gd").new()
		var layer: CanvasLayer = CanvasLayer.new()
		layer.layer = 110
		add_child(layer)
		layer.add_child(_text_entry)
	_text_entry.open(editor)

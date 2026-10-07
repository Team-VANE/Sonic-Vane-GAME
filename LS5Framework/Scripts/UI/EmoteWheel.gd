extends CanvasLayer

signal emote_selected(emote_id: StringName)

## Supplies ordered categories and their emote labels.
@export var pages: Array[EmoteWheelPage] = []
## Limits each displayed page; overflow options create additional pages.
@export_range(1, 12, 1) var options_per_page: int = 6
## Sets the minimum stick deflection required to highlight an option.
@export_range(0.2, 1.0, 0.01) var stick_activation_threshold: float = 0.55
## Adds angular tolerance at wedge boundaries to stabilize highlighting.
@export_range(0.0, 15.0, 0.5) var selection_hysteresis_degrees: float = 5.0
## Suppresses wheel controls after closing and after held controls are released.
@export_range(0.05, 0.5, 0.01) var input_guard_seconds: float = 0.16
## Sets the opacity fade duration when opening.
@export_range(0.01, 0.3, 0.01) var fade_in_seconds: float = 0.09
## Sets the visual growth duration, including the small overshoot.
@export_range(0.02, 0.3, 0.01) var growth_seconds: float = 0.14
## Replaces the growth bounce with an opacity fade.
@export var reduced_motion: bool = false

## Draws the wheel independently of the fixed selection geometry.
@onready var wheel: EmoteWheelView = $Wheel

var last_selected_emote: StringName = &""
var _open: bool = false
var _display_pages: Array[Dictionary] = []
var _page_index: int = 0
var _highlighted: int = -1
var _stick: Vector2 = Vector2.ZERO
var _stick_ready: bool = false
var _stick_armed: bool = false
var _stick_peak_magnitude: float = 0.0
var _stick_returning: bool = false
var _confirm_pending: bool = false
var _controller_active: bool = false
var _joy_device: int = -1
var _left_held: bool = false
var _right_held: bool = false
var _pending_page_step: int = 0
var _page_step_at: int = 0
var _guard_until: int = 0
var _blocked_actions: Dictionary = {}
var _reserved_events: Array[InputEvent] = []
var _release_pending: Array[InputEvent] = []
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _opening_scene: Node = null
var _player: Node = null
var _centre: Vector2 = Vector2.ZERO
var _layout_scale: float = 1.0
var _visual_scale: float = 1.0
var _transition: Tween


func _ready() -> void:
	process_priority = -1000
	process_physics_priority = -1000
	wheel.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()


func is_open() -> bool:
	return _open


func is_camera_input_blocked() -> bool:
	return _open or Time.get_ticks_msec() < _guard_until or not _release_pending.is_empty()


func is_action_blocked(action: StringName) -> bool:
	return _blocked_actions.has(action) and is_camera_input_blocked()


func _process(_delta: float) -> void:
	_update_release_guard()
	if not _open:
		return
	if not _can_remain_open():
		close_wheel()
		return
	if _pending_page_step and Time.get_ticks_msec() >= _page_step_at:
		_change_page(_pending_page_step)
		_pending_page_step = 0
	if _confirm_pending:
		_confirm_pending = false
		_confirm_selection()


func _input(event: InputEvent) -> void:
	if _modal_ui_active():
		if _open:
			close_wheel()
		return
	if not _open:
		if is_camera_input_blocked() and _event_is_reserved(event):
			_track_guard_event(event)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"emote_wheel", false) and _can_open():
			open_wheel(event is InputEventJoypadButton, event.device)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"emote_wheel", false) or event.is_action_pressed(&"ui_cancel", false) or event.is_action_pressed(&"UI_back", false):
		close_wheel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"pause", false) or event.is_action_pressed(&"enter_chat", false):
		close_wheel()
		return
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		if _joy_device < 0:
			_joy_device = event.device
		if event.device == _joy_device:
			if event.axis == JOY_AXIS_RIGHT_X:
				_stick.x = event.axis_value
			else:
				_stick.y = event.axis_value
			_update_stick_selection(_stick)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if event.relative.length_squared() >= 4.0:
			_controller_active = false
			_stick_armed = false
			_confirm_pending = false
			_select_mouse(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_RIGHT:
					close_wheel()
				MOUSE_BUTTON_LEFT:
					_controller_active = false
					_select_mouse(event.position)
					_confirm_selection()
				MOUSE_BUTTON_WHEEL_UP:
					_change_page(-1)
				MOUSE_BUTTON_WHEEL_DOWN:
					_change_page(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action(&"emote_page_previous") or event.is_action(&"emote_page_next"):
		if event.is_action(&"emote_page_previous"):
			_left_held = event.is_pressed()
		if event.is_action(&"emote_page_next"):
			_right_held = event.is_pressed()
		if _left_held and _right_held:
			close_wheel()
		elif event.is_pressed() and not event.is_echo():
			_controller_active = event is InputEventJoypadButton
			_pending_page_step = -1 if event.is_action(&"emote_page_previous") else 1
			_page_step_at = Time.get_ticks_msec() + 55
			_confirm_pending = false
			_stick_armed = false
			_set_highlight(-1)
		get_viewport().set_input_as_handled()
		return
	if _event_is_reserved(event):
		get_viewport().set_input_as_handled()


func open_wheel(controller: bool = false, device: int = -1) -> void:
	if _open:
		return
	_rebuild_pages()
	if _display_pages.is_empty():
		return
	_open = true
	_opening_scene = get_tree().current_scene
	_player = _get_local_player()
	_controller_active = controller
	_joy_device = device if controller else SettingsManager.get_preferred_joypad_device()
	_stick = _read_stick()
	_stick_ready = _stick.length() <= _release_threshold()
	_stick_armed = false
	_confirm_pending = false
	_pending_page_step = 0
	_stick_peak_magnitude = 0.0
	_stick_returning = false
	_left_held = Input.is_action_pressed(&"emote_page_previous")
	_right_held = Input.is_action_pressed(&"emote_page_next")
	_page_index = clampi(SettingsManager.emote_last_page, 0, _display_pages.size() - 1) if SettingsManager.remember_emote_page else 0
	_highlighted = -1
	_mouse_mode_before_open = Input.get_mouse_mode()
	_refresh_reserved_inputs()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_viewport().warp_mouse(_centre)
	_refresh_view()
	wheel.show()
	wheel.modulate.a = 0.0
	_visual_scale = 1.0 if reduced_motion else 0.8
	_layout()
	_kill_transition()
	_transition = create_tween().set_parallel(true)
	_transition.tween_property(wheel, "modulate:a", 1.0, fade_in_seconds)
	if not reduced_motion:
		_transition.tween_method(_set_visual_scale, 0.8, 1.04, growth_seconds * 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_transition.tween_method(_set_visual_scale, 1.04, 1.0, growth_seconds * 0.35).set_delay(growth_seconds * 0.65).set_trans(Tween.TRANS_SINE)


func close_wheel() -> void:
	if not _open:
		return
	if SettingsManager.remember_emote_page:
		SettingsManager.set_emote_last_page(_page_index)
	_open = false
	_confirm_pending = false
	_stick_armed = false
	_pending_page_step = 0
	_guard_until = Time.get_ticks_msec() + int(input_guard_seconds * 1000.0)
	_release_pending.clear()
	for event: InputEvent in _reserved_events:
		if _physical_event_pressed(event):
			_release_pending.append(event)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and get_tree().current_scene == _opening_scene and not get_tree().paused and not _modal_ui_active():
		Input.set_mouse_mode(_mouse_mode_before_open)
	_kill_transition()
	_transition = create_tween()
	_transition.tween_property(wheel, "modulate:a", 0.0, 0.08)
	_transition.tween_callback(wheel.hide)


func _confirm_selection() -> void:
	if not _open or _highlighted < 0 or _pending_page_step:
		return
	var options: Array = _display_pages[_page_index].options
	var option: Dictionary = options[_highlighted]
	last_selected_emote = StringName(option.id)
	close_wheel()
	if is_instance_valid(_player) and _player.has_method("play_emote_voice"):
		_player.call("play_emote_voice", last_selected_emote)
	emote_selected.emit(last_selected_emote)
	_kill_transition()
	wheel.feedback = String(option.label)
	wheel.modulate.a = 1.0
	_set_visual_scale(1.0)
	wheel.queue_redraw()
	_transition = create_tween()
	_transition.tween_interval(0.65)
	_transition.tween_property(wheel, "modulate:a", 0.0, 0.12)
	_transition.tween_callback(wheel.hide)


func _update_stick_selection(vector: Vector2) -> void:
	var magnitude: float = vector.length()
	if not _stick_ready:
		if magnitude <= _release_threshold():
			_stick_ready = true
		return
	if _pending_page_step:
		return
	if magnitude >= maxf(stick_activation_threshold, _release_threshold() + 0.1):
		_controller_active = true
		if not _stick_armed:
			_stick_peak_magnitude = 0.0
			_stick_returning = false
		if _stick_armed and magnitude < _stick_peak_magnitude - 0.12:
			_stick_returning = true
		if magnitude >= _stick_peak_magnitude - 0.04:
			_stick_returning = false
		_stick_peak_magnitude = maxf(_stick_peak_magnitude, magnitude)
		_stick_armed = true
		_confirm_pending = false
		if not _stick_returning:
			_select_direction(vector, true)
	elif magnitude <= _release_threshold() and _stick_armed:
		_stick_armed = false
		_confirm_pending = true


func _release_threshold() -> float:
	return clampf(SettingsManager.get_right_stick_deadzone(), 0.12, 0.4)


func _select_mouse(position: Vector2) -> void:
	var vector: Vector2 = (position - _centre) / _layout_scale
	if vector.length() < EmoteWheelView.INNER_RADIUS or vector.length() > EmoteWheelView.OUTER_RADIUS:
		_set_highlight(-1)
	else:
		_select_direction(vector, false)


func _select_direction(vector: Vector2, hysteresis: bool) -> void:
	var count: int = _display_pages[_page_index].options.size()
	var step: float = TAU / float(count)
	var angle: float = fposmod(vector.angle() + PI * 0.5, TAU)
	if hysteresis and _highlighted >= 0:
		var previous_angle: float = float(_highlighted) * step
		var distance: float = absf(wrapf(angle - previous_angle, -PI, PI))
		if distance <= step * 0.5 + deg_to_rad(selection_hysteresis_degrees):
			return
	_set_highlight(int(floor((angle + step * 0.5) / step)) % count)


func _set_highlight(index: int) -> void:
	_highlighted = index
	wheel.highlighted = index
	wheel.controller_active = _controller_active
	wheel.queue_redraw()


func _change_page(step: int) -> void:
	_page_index = posmod(_page_index + step, _display_pages.size())
	_pending_page_step = 0
	_highlighted = -1
	_stick_ready = _stick.length() <= _release_threshold()
	_stick_armed = false
	_confirm_pending = false
	_stick_peak_magnitude = 0.0
	_stick_returning = false
	_refresh_view()


func _rebuild_pages() -> void:
	_display_pages.clear()
	for page: EmoteWheelPage in pages:
		if not page:
			continue
		var valid_options: Array[Dictionary] = []
		for option: Dictionary in page.options:
			if not String(option.get("id", "")).is_empty() and not String(option.get("label", "")).is_empty():
				valid_options.append(option)
		var limit: int = maxi(options_per_page, 1)
		var page_count: int = ceili(float(valid_options.size()) / float(limit))
		for index: int in page_count:
			var heading: String = page.title
			if page_count > 1:
				heading += " %d/%d" % [index + 1, page_count]
			_display_pages.append({"title": heading, "options": valid_options.slice(index * limit, (index + 1) * limit)})


func _refresh_view() -> void:
	wheel.options.assign(_display_pages[_page_index].options)
	wheel.heading = "%s  ·  %d/%d" % [_display_pages[_page_index].title, _page_index + 1, _display_pages.size()]
	wheel.highlighted = _highlighted
	wheel.controller_active = _controller_active
	wheel.feedback = ""
	wheel.queue_redraw()


func _layout() -> void:
	_centre = get_viewport().get_visible_rect().size * 0.5
	_layout_scale = clampf(minf(_centre.y * 2.0 / 760.0, _centre.x * 2.0 / 760.0), 0.45, 1.8)
	wheel.pivot_offset = wheel.size * 0.5
	wheel.position = _centre - wheel.size * 0.5
	wheel.scale = Vector2.ONE * _layout_scale * _visual_scale


func _set_visual_scale(value: float) -> void:
	_visual_scale = value
	_layout()


func _kill_transition() -> void:
	if _transition and _transition.is_valid():
		_transition.kill()


func _read_stick() -> Vector2:
	if _joy_device < 0:
		return Vector2.ZERO
	return Vector2(Input.get_joy_axis(_joy_device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(_joy_device, JOY_AXIS_RIGHT_Y))


func _get_local_player() -> Node:
	for player: Node in get_tree().get_nodes_in_group(&"Player"):
		if player.has_method("_network_is_local_authority") and bool(player.call("_network_is_local_authority")):
			if not bool(player.get("_is_dead")) and not bool(player.get_meta(&"debug_online_dummy", false)):
				return player
	return null


func _can_open() -> bool:
	return _get_local_player() != null and not _other_ui_active()


func _can_remain_open() -> bool:
	return is_instance_valid(_player) and not bool(_player.get("_is_dead")) and get_tree().current_scene == _opening_scene and not _other_ui_active()


func _other_ui_active() -> bool:
	if get_tree().paused or not get_window().has_focus():
		return true
	return _modal_ui_active()


func _modal_ui_active() -> bool:
	if bool(get_tree().get_meta(&"chat_input_active", false)):
		return true
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return true
	for group: StringName in [&"ModalMenu", &"PauseMenu"]:
		for menu: Node in get_tree().get_nodes_in_group(group):
			if menu is CanvasLayer and (menu as CanvasLayer).visible:
				return true
			if menu is CanvasItem and (menu as CanvasItem).is_visible_in_tree():
				return true
	return false


func _refresh_reserved_inputs() -> void:
	_reserved_events.clear()
	_blocked_actions.clear()
	_release_pending.clear()
	for action: StringName in [&"emote_wheel", &"emote_page_previous", &"emote_page_next", &"ui_cancel", &"UI_back"]:
		_reserved_events.append_array(InputMap.action_get_events(action))
	for button: int in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		_reserved_events.append(event)
	for axis: int in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		for direction: float in [-1.0, 1.0]:
			var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
			event.axis = axis
			event.axis_value = direction
			_reserved_events.append(event)
	for action: StringName in InputMap.get_actions():
		for binding: InputEvent in InputMap.action_get_events(action):
			if _event_is_reserved(binding):
				_blocked_actions[action] = true
				break


func _event_is_reserved(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		return true
	for reserved: InputEvent in _reserved_events:
		if reserved.is_match(event, false):
			return true
	return false


func _physical_event_pressed(event: InputEvent) -> bool:
	if event is InputEventKey:
		return Input.is_physical_key_pressed(event.physical_keycode) if event.physical_keycode else Input.is_key_pressed(event.keycode)
	if event is InputEventMouseButton:
		return event.button_index <= MOUSE_BUTTON_XBUTTON2 and Input.is_mouse_button_pressed(event.button_index)
	if event is InputEventJoypadButton:
		for device: int in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(device, event.button_index):
				return true
	if event is InputEventJoypadMotion:
		for device: int in Input.get_connected_joypads():
			if Input.get_joy_axis(device, event.axis) * signf(event.axis_value) > _release_threshold():
				return true
	return false


func _track_guard_event(event: InputEvent) -> void:
	if event.is_pressed():
		_guard_until = Time.get_ticks_msec() + int(input_guard_seconds * 1000.0)
		for reserved: InputEvent in _reserved_events:
			if reserved.is_match(event, false) and not _release_pending.has(reserved):
				_release_pending.append(reserved)


func _update_release_guard() -> void:
	if _open:
		return
	for index: int in range(_release_pending.size() - 1, -1, -1):
		if not _physical_event_pressed(_release_pending[index]):
			_release_pending.remove_at(index)
			_guard_until = Time.get_ticks_msec() + int(input_guard_seconds * 1000.0)
	if not is_camera_input_blocked():
		_blocked_actions.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _open:
		close_wheel()

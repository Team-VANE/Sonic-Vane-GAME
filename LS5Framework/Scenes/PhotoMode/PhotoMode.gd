extends Control

signal exit_requested

const SWITCH_FOCUS: StringName = &"photo_switch_focus"
const RAISE: StringName = &"photo_camera_raise"
const LOWER: StringName = &"photo_camera_lower"
const ROLL_LEFT: StringName = &"photo_camera_roll_left"
const ROLL_RIGHT: StringName = &"photo_camera_roll_right"
const SCREENSHOT: StringName = &"photo_screenshot"
const SCREENSHOT_DIRECTORY: String = "user://Screenshots"
const PREFERENCES_PATH: String = "user://photo_mode.cfg"
const MENU_PRESENTATION = preload("res://LS5Framework/Scripts/UI/MenuPresentation.gd")
const PhotoPlayerPanel = preload("res://LS5Framework/Scenes/PhotoMode/PhotoPlayerPanel.gd")
const ROLL_SPEED: float = PI * 0.5
const FOV_SPEED: float = 45.0
const THUMBNAIL_SIZE: Vector2i = Vector2i(800, 600)
const PREVIEW_CANVAS_MASK: int = 1 << 19
const GREEN_SCREEN_MASK: int = 1 << 17
const FULL_FRAME: Vector4 = Vector4(0.0, 0.0, 1.0, 1.0)
enum PhotoFilter { ORIGINAL, MONOCHROME, VIVID, MUTED, SEPIATONE, CRT, GREEN_SCREEN }
const SCREENSHOT_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440),
	Vector2i(3840, 2160), Vector2i(5120, 2160), Vector2i(7680, 4320)
]

## Free camera movement speed in world units per second.
@export_range(1.0, 80.0, 1.0) var movement_speed: float = 14.0
## Maximum camera distance from the local player during online play.
@export_range(10.0, 200.0, 1.0) var online_camera_radius: float = 60.0

## Renders the photo view independently of the gameplay rig.
@onready var _camera: Camera3D = $Camera
## Draws the photo filters and crop guide behind the controls.
@onready var _preview_layer: CanvasLayer = $PreviewLayer
## Sets the filter and crop bounds for the photo preview.
@onready var _preview_material: ShaderMaterial = $PreviewLayer/Preview.material
## Contains the focusable camera settings.
@onready var _panel: PanelContainer = $Panel
## Holds the photo controls and shared exit button.
@onready var _content: VBoxContainer = $Panel/Content
## Selects the active group of photo controls.
@onready var _tabs: TabContainer = %Tabs
## Controls player gaze and skeletal photo poses.
@onready var _player_panel: PhotoPlayerPanel = %Tabs/Player
## Confirms departure before discarding the photo setup.
@onready var _exit_confirmation: PanelContainer = $Panel/ExitConfirmation
## Restores the active tab from the confirmation prompt.
@onready var _keep_editing: Button = %KeepEditing
## Returns to Pause after confirmation.
@onready var _confirm_exit: Button = %ConfirmExit
## Advances the paused simulation by one physics tick.
@onready var _frame_advance: Button = %FrameAdvance
## Enables camera-local near and far blur.
@onready var _depth_of_field: CheckButton = %DepthOfField
## Sets and displays the depth of field focus distance.
@onready var _focus_distance: HSlider = %FocusDistance
## Displays the selected focus distance.
@onready var _focus_distance_label: Label = %FocusDistanceLabel
## Sets the strength of depth of field blur.
@onready var _blur_amount: HSlider = %BlurAmount
## Displays the selected strength of depth of field blur.
@onready var _blur_amount_label: Label = %BlurAmountLabel
## Selects a camera-local color filter.
@onready var _filter: OptionButton = %Filter
## Includes the underwater camera overlay in the photo.
@onready var _water_effect: CheckButton = %WaterEffect
## Includes the radial speed streaks in the photo.
@onready var _speed_lines: CheckButton = %SpeedLines
## Includes the radial motion blur in the photo.
@onready var _radial_blur: CheckButton = %RadialBlur
## Renders manually configured speed effects independently of the gameplay rig.
@onready var _radial_effect: SpeedRadialBlurEffect = $RadialEffect
## Includes the directional sun flare in the photo.
@onready var _sun_flare: CheckButton = %SunFlare
## Sets the darkening around the edges of the saved frame.
@onready var _vignette: HSlider = %Vignette
## Lists weather presets available in the current stage.
@onready var _weather: OptionButton = %PhotoWeather
## Sets the local solar time of the shot.
@onready var _weather_hour: HSlider = %PhotoHour
## Rotates the sun's east-west path around world up.
@onready var _sun_east: HSlider = %SunEast
## Displays weather availability and notes.
@onready var _weather_status: Label = %WeatherStatus
## Updates camera-angle quill poses as the photo camera moves.
@onready var _live_quills: CheckButton = %LiveQuills
## Identifies whether the stage is frozen or live.
@onready var _world_status: Label = %WorldStatus
## Lists the camera controls before switching to the clean view.
@onready var _camera_controls: Label = %CameraControls
## Toggles the local player's visibility in the shot.
@onready var _hide_player: CheckButton = %HidePlayer
## Captures the current photo view.
@onready var _screenshot_button: Button = %TakeScreenshot
## Selects the screenshot output dimensions.
@onready var _screenshot_size: OptionButton = %ScreenshotSize
## Opens the directory used for screenshot exports.
@onready var _screenshot_folder: Button = %OpenScreenshotFolder
## Displays the saved filename or capture failure.
@onready var _capture_status: Label = %CaptureStatus
## Confirms screenshot capture while camera controls are active.
@onready var _shutter: AudioStreamPlayer = $Shutter
## Adjusts the photo camera field of view.
@onready var _fov_slider: HSlider = %FieldOfView
## Displays the current field of view in degrees.
@onready var _fov_label: Label = %FieldOfViewLabel
## Switches from menu navigation to camera movement.
@onready var _switch_button: Button = %SwitchFocus
## Restores the entry framing and lens.
@onready var _reset_button: Button = %ResetCamera
## Returns to the pause menu.
@onready var _exit_button: Button = %ExitPhotoMode

## Receives camera ownership when Photo Mode closes.
var _gameplay_camera: Camera3D
## Owns the stage's screen effects.
var _effect_rig: Node
## Stage system rendering the local photo weather preview.
var _weather_system: EnvironmentWeatherSystem
var _weather_edited: bool = false
## Directional flares configured by the active stage.
var _sun_flares: Array[CameraFlare3D] = []
## Camera-angle modifiers belonging to the local character.
var _quill_modifiers: Array[CameraAngleOverlay3D] = []
var _preferred_resolution: Vector2i = Vector2i.ZERO
## Anchors the photo camera's online movement limit.
var _online_player: Node3D
## Local player whose visibility is controlled for the shot.
var _player: Node3D
var _player_was_visible: bool = true
var _green_screen: bool = false
## Original render layers of meshes included in the player matte.
var _green_screen_layers: Dictionary[int, int] = {}
## Supplies the player silhouette independently of the lit scene.
var _green_matte: SubViewport
## Renders the player mask from the photo camera's viewpoint.
var _green_matte_camera: Camera3D
var _canvas_mask: int = 0
var _capture_pending: bool = false
var _frame_pending: bool = false
var _frame_stepping: bool = false
var _offline: bool = true
var _capture_generation: int = 0
var _window_capture_size: Vector2i = Vector2i.ZERO
var _camera_fov: float = 75.0
var _entry_transform: Transform3D = Transform3D.IDENTITY
var _angles: Vector3 = Vector3.ZERO
var _entry_fov: float = 75.0
var _camera_focused: bool = false
var _waiting_for_camera_neutral: bool = false
var _switch_held: bool = false
var _last_shift_press_ms: int = -1
var _shift_sprint: bool = false
var _hint_controller: bool = false
var _hint_style: int = -1


func _ready() -> void:
	_fov_slider.value_changed.connect(_set_fov)
	_switch_button.pressed.connect(_set_camera_focus.bind(true))
	_reset_button.pressed.connect(_reset_framing)
	_hide_player.toggled.connect(_set_player_hidden)
	_screenshot_button.pressed.connect(_take_screenshot)
	_screenshot_size.item_selected.connect(_on_screenshot_size_selected)
	get_viewport().size_changed.connect(_refresh_preview_after_resize, CONNECT_DEFERRED)
	_screenshot_folder.pressed.connect(_open_screenshot_folder)
	_depth_of_field.toggled.connect(func(_enabled: bool) -> void: _update_depth_of_field())
	_focus_distance.value_changed.connect(func(_value: float) -> void: _update_depth_of_field())
	_blur_amount.value_changed.connect(func(_value: float) -> void: _update_depth_of_field())
	for name_text: String in ["Original", "Black and White", "Vivid", "Muted", "Sepiatone", "CRT", "Green Screen"]:
		_filter.add_item(name_text)
	_filter.item_selected.connect(_set_filter)
	for toggle: CheckButton in [_water_effect, _speed_lines, _radial_blur, _live_quills, _sun_flare]:
		toggle.toggled.connect(func(_enabled: bool) -> void: _apply_photo_effects())
	for slider: HSlider in _radial_settings().values():
		slider.value_changed.connect(func(_value: float) -> void: _apply_radial_effect())
	_vignette.value_changed.connect(func(_value: float) -> void: _update_canvas_visibility())
	_weather.item_selected.connect(func(_index: int) -> void: _apply_weather_preview())
	_weather_hour.value_changed.connect(func(_value: float) -> void: _apply_weather_preview())
	_sun_east.value_changed.connect(func(_value: float) -> void: _apply_weather_preview())
	(%ResetPhotoSettings as Button).pressed.connect(_reset_photo_settings)
	_frame_advance.pressed.connect(_advance_frame)
	get_window().size_changed.connect(_refresh_screenshot_sizes)
	_exit_button.pressed.connect(_request_exit)
	_keep_editing.pressed.connect(_cancel_exit)
	_confirm_exit.pressed.connect(func() -> void: exit_requested.emit())
	SettingsManager.input_bindings_changed.connect(_on_bindings_changed)
	resized.connect(_layout_panel)
	_layout_panel()
	set_process(false)
	set_process_input(false)


func open(source: Camera3D, player: Node3D, online: bool) -> void:
	_gameplay_camera = source
	_setup_weather(online)
	_effect_rig = source
	while _effect_rig and not _effect_rig.has_method("set_photo_screen_effects"):
		_effect_rig = _effect_rig.get_parent()
	for flare: Node in get_tree().get_nodes_in_group(&"SunLensFlare"):
		if flare is CameraFlare3D and flare.get_viewport() == get_viewport():
			_sun_flares.append(flare)
			flare.begin_photo_view(_camera, PREVIEW_CANVAS_MASK)
	_player = player
	for node: Node in player.find_children("*", "SkeletonModifier3D", true, false):
		if node is CameraAngleOverlay3D:
			_quill_modifiers.append(node)
	_online_player = player if online else null
	_offline = not online
	_frame_advance.disabled = online
	_frame_advance.tooltip_text = "Frame advance is available offline." if online else "Steps the offline world by one physics tick."
	_player_was_visible = player.visible
	_canvas_mask = get_viewport().canvas_cull_mask
	_capture_status.hide()
	_entry_transform = source.get_global_transform_interpolated()
	_entry_fov = source.fov
	_camera.projection = source.projection
	_camera.size = source.size
	_camera.frustum_offset = source.frustum_offset
	_camera.keep_aspect = source.keep_aspect
	_camera.near = source.near
	_camera.far = source.far
	_camera.h_offset = source.h_offset
	_camera.v_offset = source.v_offset
	_camera.cull_mask = source.cull_mask
	_camera.environment = source.environment
	_camera.attributes = source.attributes
	_camera.compositor = source.compositor
	_fov_slider.editable = source.projection == Camera3D.PROJECTION_PERSPECTIVE
	_fov_slider.min_value = minf(15.0, _entry_fov)
	_fov_slider.max_value = maxf(120.0, _entry_fov)
	_reset_framing()
	_depth_of_field.disabled = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_depth_of_field.tooltip_text = "Requires the Forward+ or Mobile renderer." if _depth_of_field.disabled else "Blurs objects in front of and behind the focus distance."
	_exit_confirmation.hide()
	_content.show()
	_tabs.current_tab = 0
	for page: Node in _tabs.get_children():
		(page as ScrollContainer).scroll_vertical = 0
	_world_status.text = "World live" if _online_player else "World frozen"
	visible = true
	_refresh_screenshot_sizes()
	var settings: ConfigFile = ConfigFile.new()
	settings.load(PREFERENCES_PATH)
	_apply_photo_settings(settings)
	SettingsManager.set_fps_counter_suppressed(true)
	_camera.make_current()
	_player_panel.open(player, _camera)
	set_process(true)
	set_process_input(true)
	_switch_held = Input.is_action_pressed(SWITCH_FOCUS)
	MenuNavigation.forget_focus(_panel)
	_set_camera_focus(false)


func close() -> void:
	_restore_photo_state()
	if _camera.is_current():
		if is_instance_valid(_gameplay_camera) and _gameplay_camera.is_inside_tree():
			_gameplay_camera.make_current()
		else:
			_camera.clear_current(false)
	_gameplay_camera = null
	_online_player = null
	_camera.environment = null
	_camera.attributes = null
	_camera.compositor = null
	visible = false
	SettingsManager.set_fps_counter_suppressed(false)
	set_process(false)
	set_process_input(false)


func _exit_tree() -> void:
	if visible:
		_restore_photo_state(true)
		SettingsManager.set_fps_counter_suppressed(false)


func _restore_photo_state(detaching: bool = false) -> void:
	_player_panel.close(detaching)
	_save_photo_settings()
	_restore_green_screen_layers()
	if is_instance_valid(_weather_system):
		_weather_system.set_photo_weather(-1.0, 0.0, &"", _gameplay_camera)
	_weather_system = null
	_capture_generation += 1
	_capture_pending = false
	_preview_layer.hide()
	_radial_effect.hide()
	for flare: CameraFlare3D in _sun_flares:
		if is_instance_valid(flare):
			flare.end_photo_view()
	_sun_flares.clear()
	_frame_pending = false
	if _frame_stepping:
		get_tree().paused = true
		_frame_stepping = false
	get_viewport().canvas_cull_mask = _canvas_mask
	if is_instance_valid(_effect_rig):
		_effect_rig.call("set_photo_screen_effects", 1, true, true, true)
	_effect_rig = null
	for modifier: CameraAngleOverlay3D in _quill_modifiers:
		if is_instance_valid(modifier):
			modifier.set_photo_view(null, true)
	_quill_modifiers.clear()
	_set_player_hidden(false)
	_player = null


func _set_player_hidden(hidden: bool) -> void:
	if is_instance_valid(_player):
		_player.visible = _green_screen or (_player_was_visible and not hidden)


func has_photo_view() -> bool:
	return _camera.is_current() and is_instance_valid(_gameplay_camera) and _gameplay_camera.is_inside_tree()


func navigation_scope() -> Dictionary:
	if not visible or _camera_focused:
		return {}
	if _exit_confirmation.visible:
		return {"root": _exit_confirmation, "default": _keep_editing, "cancel": _cancel_exit}
	var defaults: Array[Control] = [_fov_slider if _fov_slider.editable else _switch_button, _depth_of_field, _filter,
		_weather if not _weather.disabled else _weather_hour, _screenshot_size, _player_panel.get_default_focus()]
	return {"root": _panel, "default": defaults[_tabs.current_tab], "tabs": _tabs, "page": str(_tabs.current_tab), "panel_switch": _handle_tab_key}


func _handle_tab_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var direction: int = int(event.physical_keycode == KEY_E or event.keycode == KEY_E) - int(event.physical_keycode == KEY_Q or event.keycode == KEY_Q)
	if not direction:
		return false
	_tabs.current_tab = wrapi(_tabs.current_tab + direction, 0, _tabs.get_tab_count())
	MenuNavigation.restore_focus()
	return true


func _request_exit() -> void:
	_content.hide()
	_exit_confirmation.show()
	MenuNavigation.restore_focus()


func _cancel_exit() -> void:
	_exit_confirmation.hide()
	_content.show()
	MenuNavigation.restore_focus()


func _advance_frame() -> void:
	if not _offline or _frame_pending or _capture_pending or not get_tree().paused:
		return
	_frame_pending = true
	var generation: int = _capture_generation
	await get_tree().physics_frame
	if generation != _capture_generation:
		return
	_frame_stepping = true
	get_tree().paused = false
	await get_tree().physics_frame
	if generation != _capture_generation:
		return
	get_tree().paused = true
	_frame_stepping = false
	_frame_pending = false


func _set_camera_focus(enabled: bool) -> void:
	_camera_focused = enabled
	_last_shift_press_ms = -1
	_shift_sprint = false
	_waiting_for_camera_neutral = enabled
	_panel.visible = not enabled
	_update_canvas_visibility()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE
	_update_hints()
	MenuNavigation.restore_focus()


func _input(event: InputEvent) -> void:
	SettingsManager.track_input_device(event)
	if _camera_focused and event is InputEventKey and event.keycode == KEY_SHIFT and not event.echo:
		_update_shift_boost(event.pressed, Time.get_ticks_msec())
	if _capture_pending or _frame_pending:
		get_viewport().set_input_as_handled()
		return
	if _exit_confirmation.visible:
		if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
			get_viewport().set_input_as_handled()
			_cancel_exit()
		return
	if event.is_action_pressed(SCREENSHOT, false, true):
		get_viewport().set_input_as_handled()
		_take_screenshot()
		return
	if event.is_action_released(SWITCH_FOCUS, true):
		_switch_held = false
	if event.is_action_pressed(SWITCH_FOCUS, false, true):
		if not _switch_held:
			_switch_held = true
			_set_camera_focus(not _camera_focused)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if _camera_focused:
			_set_camera_focus(false)
		else:
			_request_exit()
		return
	if not _camera_focused:
		return
	if event is InputEventMouseMotion and not _waiting_for_camera_neutral:
		var look: Vector2 = event.screen_relative * (SettingsManager.mouse_look_sensitivity * 0.0025)
		if SettingsManager.mouse_invert_y:
			look.y = -look.y
		_rotate_camera(look)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not Input.is_action_pressed(SWITCH_FOCUS):
		_switch_held = false
	if SettingsManager.is_controller_input_active() != _hint_controller or InputBindingGlyphs.resolve_style() != _hint_style:
		_update_hints()
	if _camera_focused and not _capture_pending:
		_move_camera(delta)
	if is_instance_valid(_online_player) and _online_player.is_inside_tree():
		var origin: Vector3 = _online_player.global_position
		var offset: Vector3 = _camera.global_position - origin
		_camera.global_position = origin + offset.limit_length(online_camera_radius)
	_player_panel.update_camera_gaze()
	if _green_screen:
		_sync_green_matte()
	if _live_quills.button_pressed and get_tree().paused:
		for modifier: CameraAngleOverlay3D in _quill_modifiers:
			if is_instance_valid(modifier):
				modifier.refresh_photo_view(delta)
	if is_instance_valid(_weather_system):
		_weather_system.update_photo_rain_camera(_camera)


func _setup_weather(online: bool) -> void:
	_weather_system = null
	_weather.clear()
	_weather.add_item("Stage Weather")
	_weather.set_item_metadata(0, &"")
	_weather.select(0)
	if not online:
		for node: Node in get_tree().get_nodes_in_group(&"environment_weather_system"):
			if node is EnvironmentWeatherSystem and node.get_photo_cycle() and node.get_viewport() == get_viewport():
				_weather_system = node
				break
	_weather.disabled = not is_instance_valid(_weather_system)
	_weather_hour.editable = not _weather.disabled
	_sun_east.editable = not _weather.disabled
	_weather_status.text = "Weather controls are available offline." if online else "This stage has no weather cycle."
	_weather_status.visible = _weather.disabled
	_weather_edited = false
	if _weather.disabled:
		return
	var cycle: DayNightCycle = _weather_system.get_photo_cycle()
	_weather_hour.set_value_no_signal(cycle.time_of_day_hours)
	_sun_east.set_value_no_signal(cycle.sun_path_azimuth_degrees)
	_sun_east.editable = cycle.time_controls_celestial_motion
	for preset: Dictionary in _weather_system.get_terminal_weather_state().get("presets", []):
		_weather.add_item(preset["name"])
		_weather.set_item_metadata(_weather.item_count - 1, StringName(preset["id"]))
	_weather.disabled = _weather.item_count < 2
	_update_weather_labels()


func _update_weather_labels() -> void:
	var minutes: int = posmod(roundi(_weather_hour.value * 60.0), 1440)
	(%PhotoHourLabel as Label).text = "Time of Day  %02d:%02d" % [floori(minutes / 60.0), minutes % 60]
	(%SunEastLabel as Label).text = "Sun East Rotation  %d°" % roundi(_sun_east.value)


func _apply_weather_preview() -> void:
	if not is_instance_valid(_weather_system):
		return
	_weather_edited = true
	_update_weather_labels()
	_weather_system.set_photo_weather(wrapf(_weather_hour.value, 0.0, 24.0), _sun_east.value, _weather.get_selected_metadata(), _camera if _weather.selected > 0 else _gameplay_camera)
	_set_filter(_filter.selected)


func _apply_photo_effects() -> void:
	if is_instance_valid(_effect_rig):
		_effect_rig.call("set_photo_screen_effects", PREVIEW_CANVAS_MASK, not _green_screen and _water_effect.button_pressed, false, false)
	for flare: CameraFlare3D in _sun_flares:
		if is_instance_valid(flare):
			flare.set_photo_flare_enabled(not _green_screen and _sun_flare.button_pressed)
	for modifier: CameraAngleOverlay3D in _quill_modifiers:
		if is_instance_valid(modifier):
			modifier.set_photo_view(_camera, _live_quills.button_pressed)
	_apply_radial_effect()


func _apply_radial_effect() -> void:
	var controls: Dictionary = _radial_settings()
	var lines: HSlider = controls["line_intensity"]
	var blur: HSlider = controls["radial_intensity"]
	var horizontal: HSlider = controls["radial_center_x"]
	var vertical: HSlider = controls["radial_center_y"]
	var values: Vector2 = Vector2(lines.value if _speed_lines.button_pressed else 0.0, blur.value if _radial_blur.button_pressed else 0.0)
	_radial_effect.set_manual_photo_effect(PREVIEW_CANVAS_MASK, Vector2.ZERO if _green_screen else values, Vector2(horizontal.value, vertical.value))
	for key: String in controls:
		var slider: HSlider = controls[key]
		var label: Label = slider.get_parent().get_node("Value")
		label.text = "%s  %d%%" % [slider.tooltip_text, roundi(slider.value * 100.0)]
	_update_canvas_visibility()


func _move_camera(delta: float) -> void:
	var move: Vector2 = SettingsManager.get_radial_action_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back",
		SettingsManager.get_left_stick_deadzone(), SettingsManager.get_left_stick_max())
	var look: Vector2 = SettingsManager.get_radial_action_vector(
		&"camera_left", &"camera_right", &"camera_up", &"camera_down",
		SettingsManager.get_right_stick_deadzone(), SettingsManager.get_right_stick_max(), &"gamepad")
	var lift: float = Input.get_axis(LOWER, RAISE)
	var roll: float = Input.get_axis(ROLL_LEFT, ROLL_RIGHT)
	var zoom: float = Input.get_axis(&"photo_fov_widen", &"photo_fov_narrow")
	if _waiting_for_camera_neutral:
		_waiting_for_camera_neutral = not (move.is_zero_approx() and look.is_zero_approx() and is_zero_approx(lift) and is_zero_approx(roll) and is_zero_approx(zoom))
		return
	if _fov_slider.editable and not is_zero_approx(zoom):
		_set_fov(clampf(_camera_fov - zoom * FOV_SPEED * delta, _fov_slider.min_value, _fov_slider.max_value))
		_fov_slider.set_value_no_signal(_camera_fov)
	if SettingsManager.right_stick_invert_y:
		look.y = -look.y
	_rotate_camera(look * SettingsManager.get_right_stick_sensitivity() * 0.18 * delta, -roll * ROLL_SPEED * delta)
	var basis: Basis = Basis.from_euler(Vector3(_angles.x, _angles.y, 0.0))
	var direction: Vector3 = basis.x * move.x + basis.z * move.y + Vector3.UP * lift
	var speed: float = movement_speed * _camera_speed_multiplier()
	_camera.global_position += direction.limit_length(1.0) * speed * delta


func _update_shift_boost(pressed: bool, now_ms: int) -> void:
	if pressed:
		_shift_sprint = _last_shift_press_ms >= 0 and now_ms - _last_shift_press_ms <= 350
		_last_shift_press_ms = -1 if _shift_sprint else now_ms
	else:
		_shift_sprint = false


func _camera_speed_multiplier() -> float:
	var device: int = SettingsManager.get_preferred_joypad_device()
	var both_shoulders: bool = device >= 0 and Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	if both_shoulders or (_shift_sprint and Input.is_key_pressed(KEY_SHIFT)):
		return 8.0
	if Input.is_action_pressed(&"photo_camera_fast") or Input.is_action_pressed(&"photo_camera_fast_right"):
		return 3.0
	return 1.0


func _rotate_camera(look: Vector2, roll: float = 0.0) -> void:
	if look.is_zero_approx() and is_zero_approx(roll):
		return
	var yaw_direction: float = -1.0 if cos(_angles.x) < 0.0 else 1.0
	_angles.x = wrapf(_angles.x - look.y, -PI, PI)
	_angles.y = wrapf(_angles.y - look.x * yaw_direction, -PI, PI)
	_angles.z = wrapf(_angles.z + roll, -PI, PI)
	_camera.global_basis = Basis.from_euler(_angles)


func _reset_framing() -> void:
	_camera.global_transform = _entry_transform
	_angles = _entry_transform.basis.orthonormalized().get_euler()
	_fov_slider.set_value_no_signal(_entry_fov)
	_set_fov(_entry_fov)


func _set_fov(value: float) -> void:
	_camera_fov = value
	_camera.fov = value
	_fov_label.text = "Field of View  %d°" % roundi(value)


func _update_depth_of_field() -> void:
	var distance: float = _focus_distance.value
	var blur: float = _blur_amount.value
	_focus_distance_label.text = "Focus Distance  %.1f" % distance
	_blur_amount_label.text = "Blur Strength  %d%%" % roundi(blur * 200.0)
	if _green_screen:
		return
	var enabled: bool = _depth_of_field.button_pressed and not _depth_of_field.disabled
	_focus_distance.editable = enabled
	_blur_amount.editable = enabled
	var source: CameraAttributes = _gameplay_camera.attributes
	if not enabled:
		_camera.attributes = source
		return
	var attributes: CameraAttributesPractical = source.duplicate() as CameraAttributesPractical if source is CameraAttributesPractical else CameraAttributesPractical.new()
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_near_distance = distance * 0.85
	attributes.dof_blur_far_distance = distance * 1.15
	attributes.dof_blur_amount = blur
	_camera.attributes = attributes


func _set_filter(index: int) -> void:
	var original: Environment = _gameplay_camera.environment
	var green_screen: bool = index == PhotoFilter.GREEN_SCREEN
	if _green_screen != green_screen:
		_set_green_screen(green_screen)
	if green_screen:
		_preview_material.set_shader_parameter(&"filter_mode", 0)
		_update_canvas_visibility()
		return
	var preview_filter: int = 0
	if index == PhotoFilter.SEPIATONE or index == PhotoFilter.CRT:
		preview_filter = 1 if index == PhotoFilter.SEPIATONE else 2
		index = PhotoFilter.ORIGINAL
	_preview_material.set_shader_parameter(&"filter_mode", preview_filter)
	_update_canvas_visibility()
	if index == 0:
		_camera.environment = original
		return
	var source: Environment = original if original else _gameplay_camera.get_world_3d().environment
	var filtered: Environment = source.duplicate() as Environment if source else Environment.new()
	var contrast: float = filtered.adjustment_contrast if filtered.adjustment_enabled else 1.0
	var saturation: float = filtered.adjustment_saturation if filtered.adjustment_enabled else 1.0
	if not filtered.adjustment_enabled:
		filtered.adjustment_brightness = 1.0
	filtered.adjustment_enabled = true
	filtered.adjustment_contrast = contrast * [1.0, 1.05, 1.12, 0.9][index]
	filtered.adjustment_saturation = saturation * [1.0, 0.0, 1.35, 0.6][index]
	_camera.environment = filtered


func _set_green_screen(enabled: bool) -> void:
	if enabled:
		_green_screen = true
		_camera.environment = _gameplay_camera.environment
		_camera.attributes = _gameplay_camera.attributes
		var model: Node3D = _player.get("model_root") as Node3D if "model_root" in _player else _player
		if not model:
			model = _player
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.layers & _camera.cull_mask and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				_green_screen_layers[mesh.get_instance_id()] = mesh.layers
				mesh.layers |= GREEN_SCREEN_MASK
		_green_matte = SubViewport.new()
		_green_matte.transparent_bg = true
		_green_matte.world_3d = _camera.get_world_3d()
		_green_matte.canvas_cull_mask = 0
		_green_matte.msaa_3d = get_viewport().msaa_3d
		_green_matte.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_green_matte)
		_green_matte_camera = Camera3D.new()
		_green_matte_camera.cull_mask = GREEN_SCREEN_MASK
		_green_matte_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_green_matte_camera.environment = Environment.new()
		_green_matte_camera.compositor = Compositor.new()
		_green_matte.add_child(_green_matte_camera)
		_green_matte_camera.make_current()
		_sync_green_matte()
		_preview_material.set_shader_parameter(&"player_matte", _green_matte.get_texture())
	else:
		_restore_green_screen_layers()
		_camera.cull_mask = _gameplay_camera.cull_mask
		_camera.compositor = _gameplay_camera.compositor
		_update_depth_of_field()
	_hide_player.disabled = enabled
	_set_player_hidden(_hide_player.button_pressed)
	_apply_photo_effects()


func _restore_green_screen_layers() -> void:
	if _green_screen:
		_preview_material.set_shader_parameter(&"player_matte", null)
		_green_matte.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_green_matte.queue_free()
		_green_matte = null
		_green_matte_camera = null
	for instance_id: int in _green_screen_layers:
		var mesh: MeshInstance3D = instance_from_id(instance_id) as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.layers = _green_screen_layers[instance_id]
	_green_screen_layers.clear()
	_green_screen = false
	_hide_player.disabled = false


func _sync_green_matte() -> void:
	_green_matte.size = Vector2i(get_viewport().get_texture().get_size()).max(Vector2i(2, 2))
	_green_matte_camera.global_transform = _camera.global_transform
	_green_matte_camera.projection = _camera.projection
	_green_matte_camera.fov = _camera.fov
	_green_matte_camera.size = _camera.size
	_green_matte_camera.frustum_offset = _camera.frustum_offset
	_green_matte_camera.h_offset = _camera.h_offset
	_green_matte_camera.v_offset = _camera.v_offset
	_green_matte_camera.near = _camera.near
	_green_matte_camera.far = _camera.far
	_green_matte_camera.keep_aspect = _camera.keep_aspect


func _on_bindings_changed(_action: StringName) -> void:
	if visible:
		_update_hints()


func _update_hints() -> void:
	_hint_controller = SettingsManager.is_controller_input_active()
	_hint_style = InputBindingGlyphs.resolve_style()
	var swap: String = _binding_label(SWITCH_FOCUS)
	var raise_label: String = _binding_label(RAISE)
	var lower_label: String = _binding_label(LOWER)
	var back: String = _binding_label(&"ui_cancel")
	var roll_left: String = _binding_label(ROLL_LEFT)
	var roll_right: String = _binding_label(ROLL_RIGHT)
	var capture: String = _binding_label(SCREENSHOT)
	_switch_button.text = "Camera Controls  [%s]" % swap if swap else "Camera Controls"
	_screenshot_button.text = "Take Screenshot  [%s]" % capture if capture else "Take Screenshot"
	var movement: String = "Left Stick Move   •   Right Stick Aim" if _hint_controller else "Movement Keys Move   •   Mouse Aim"
	var vertical: String = "%s / %s  Raise / Lower" % [raise_label, lower_label] if raise_label and lower_label else ""
	var roll_hint: String = "%s / %s  Roll" % [roll_left, roll_right] if roll_left and roll_right else ""
	if _fov_slider.editable:
		var narrow: String = _binding_label(&"photo_fov_narrow")
		var widen: String = _binding_label(&"photo_fov_widen")
		if narrow and widen:
			roll_hint += "\n%s / %s  Field of View" % [narrow, widen]
	var tabs_hint: String = "%s / %s  Switch Tabs" % [MENU_PRESENTATION.button_label(JOY_BUTTON_LEFT_SHOULDER), MENU_PRESENTATION.button_label(JOY_BUTTON_RIGHT_SHOULDER)] if _hint_controller else "Q / E  Switch Tabs"
	var boost_hint: String = "Hold Shift  3× Speed\nDouble-press and hold Shift  8× Speed"
	if _hint_controller:
		var left: String = _binding_label(&"photo_camera_fast")
		var right: String = _binding_label(&"photo_camera_fast_right")
		boost_hint = "Hold %s or %s  3× Speed\nHold both  8× Speed" % [left, right]
	_camera_controls.text = "\n".join(PackedStringArray([movement, vertical, roll_hint, boost_hint, "%s  Return to Menu" % back, tabs_hint]))


func _update_canvas_visibility() -> void:
	var preview_visible: bool = _update_preview()
	var effects_visible: bool = not _green_screen and (_radial_effect.visible or (is_instance_valid(_effect_rig) and _water_effect.button_pressed) or (_sun_flare.button_pressed and not _sun_flares.is_empty()))
	var mask: int = 0 if _camera_focused or _capture_pending else _canvas_mask
	get_viewport().canvas_cull_mask = mask | PREVIEW_CANVAS_MASK if preview_visible or effects_visible else mask


func _refresh_preview_after_resize() -> void:
	if visible:
		_apply_radial_effect()


func _update_preview() -> bool:
	var bounds: Vector4 = FULL_FRAME
	var output_bounds: Vector4 = FULL_FRAME
	var dimensions: Vector2i = _screenshot_size.get_selected_metadata()
	var source: Vector2i = Vector2i(get_viewport().get_texture().get_size())
	var scanline_scale: float = 1.0
	if source.x > 0 and source.y > 0:
		if dimensions == Vector2i.ZERO:
			dimensions = get_window().size
		var crop: Rect2i = _screenshot_crop(source, dimensions)
		scanline_scale = minf(1.0, float(dimensions.y) / crop.size.y)
		output_bounds = Vector4(float(crop.position.x) / source.x, float(crop.position.y) / source.y,
			float(crop.end.x) / source.x, float(crop.end.y) / source.y)
		if not _capture_pending and _screenshot_size.selected != 0:
			bounds = output_bounds
	_preview_material.set_shader_parameter(&"crop_bounds", bounds)
	_preview_material.set_shader_parameter(&"output_bounds", output_bounds)
	var vignette: float = 0.0 if _green_screen else _vignette.value
	_preview_material.set_shader_parameter(&"vignette_strength", vignette)
	_preview_material.set_shader_parameter(&"green_screen", _green_screen)
	(%VignetteLabel as Label).text = "Vignette  %d%%" % roundi(_vignette.value * 100.0)
	_preview_material.set_shader_parameter(&"scanline_scale", scanline_scale)
	var filtered: bool = _filter.selected in [PhotoFilter.SEPIATONE, PhotoFilter.CRT]
	_preview_layer.visible = _green_screen or filtered or bounds != FULL_FRAME or vignette > 0.0
	return _preview_layer.visible


func _refresh_screenshot_sizes() -> void:
	var window_size: Vector2i = get_window().size
	if window_size == _window_capture_size and _screenshot_size.item_count > 0:
		return
	_window_capture_size = window_size
	_screenshot_size.clear()
	_add_screenshot_size(Vector2i.ZERO, "Current Window (%d × %d)" % [window_size.x, window_size.y])
	_add_screenshot_size(THUMBNAIL_SIZE, "800 × 600 (Level Thumbnail)")
	for preset: Vector2i in SCREENSHOT_PRESETS:
		if preset.x <= window_size.x and preset.y <= window_size.y and preset != window_size:
			_add_screenshot_size(preset, "%d × %d" % [preset.x, preset.y])
	_select_preferred_resolution()
	_refresh_preview_after_resize.call_deferred()


func _select_preferred_resolution() -> void:
	for index: int in range(_screenshot_size.item_count):
		if _screenshot_size.get_item_metadata(index) == _preferred_resolution:
			_screenshot_size.select(index)
			return
	_screenshot_size.select(0)


func _on_screenshot_size_selected(index: int) -> void:
	_preferred_resolution = _screenshot_size.get_item_metadata(index)
	_update_canvas_visibility()


func _apply_photo_settings(settings: ConfigFile) -> void:
	_vignette.set_value_no_signal(float(settings.get_value("photo", "vignette", 0.0)))
	var controls: Dictionary = _saved_toggles()
	for key: String in controls:
		var toggle: CheckButton = controls[key]
		toggle.set_pressed_no_signal(bool(settings.get_value("photo", key, key != "hide_player" and key != "depth_of_field")))
	_focus_distance.set_value_no_signal(float(settings.get_value("photo", "focus_distance", 1.0)))
	_blur_amount.set_value_no_signal(float(settings.get_value("photo", "blur_amount", 0.12)))
	var radial_settings: Dictionary = _radial_settings()
	for key: String in radial_settings:
		var slider: HSlider = radial_settings[key]
		slider.set_value_no_signal(float(settings.get_value("photo", key, 0.0)))
	var fov: float = float(settings.get_value("photo", "fov", _entry_fov))
	_fov_slider.set_value_no_signal(clampf(fov, _fov_slider.min_value, _fov_slider.max_value))
	_set_fov(clampf(fov, _fov_slider.min_value, _fov_slider.max_value))
	var resolution: Variant = settings.get_value("photo", "resolution", Vector2i.ZERO)
	_preferred_resolution = resolution if resolution is Vector2i else Vector2i.ZERO
	_select_preferred_resolution()
	var filter_index: int = clampi(int(settings.get_value("photo", "filter", 0)), 0, _filter.item_count - 1)
	_filter.select(filter_index)
	_set_filter(filter_index)
	_set_player_hidden(_hide_player.button_pressed)
	_update_depth_of_field()
	_apply_photo_effects()
	if is_instance_valid(_weather_system) and settings.has_section("weather"):
		_weather_hour.set_value_no_signal(float(settings.get_value("weather", "hour", _weather_hour.value)))
		_sun_east.set_value_no_signal(float(settings.get_value("weather", "azimuth", _sun_east.value)))
		var preset: StringName = StringName(settings.get_value("weather", "preset", &""))
		for index: int in range(_weather.item_count):
			if _weather.get_item_metadata(index) == preset:
				_weather.select(index)
				break
		_apply_weather_preview()


func _saved_toggles() -> Dictionary:
	return {"hide_player": _hide_player, "depth_of_field": _depth_of_field, "water": _water_effect,
		"speed_lines": _speed_lines, "radial_blur": _radial_blur, "live_quills": _live_quills, "sun_flare": _sun_flare}


func _radial_settings() -> Dictionary:
	return {"line_intensity": %LineIntensity, "radial_intensity": %RadialIntensity,
		"radial_center_x": %RadialCenterX, "radial_center_y": %RadialCenterY}


func _save_photo_settings(keep_unavailable_weather: bool = true) -> void:
	var settings: ConfigFile = ConfigFile.new()
	if is_instance_valid(_weather_system) and _weather_edited:
		settings.set_value("weather", "hour", _weather_hour.value)
		settings.set_value("weather", "azimuth", _sun_east.value)
		settings.set_value("weather", "preset", _weather.get_selected_metadata())
	elif keep_unavailable_weather and not is_instance_valid(_weather_system):
		var previous: ConfigFile = ConfigFile.new()
		if previous.load(PREFERENCES_PATH) == OK and previous.has_section("weather"):
			for key: String in previous.get_section_keys("weather"):
				settings.set_value("weather", key, previous.get_value("weather", key))
	settings.set_value("photo", "vignette", _vignette.value)
	var controls: Dictionary = _saved_toggles()
	for key: String in controls:
		settings.set_value("photo", key, (controls[key] as CheckButton).button_pressed)
	var radial_settings: Dictionary = _radial_settings()
	for key: String in radial_settings:
		settings.set_value("photo", key, (radial_settings[key] as HSlider).value)
	settings.set_value("photo", "fov", _camera_fov)
	settings.set_value("photo", "focus_distance", _focus_distance.value)
	settings.set_value("photo", "blur_amount", _blur_amount.value)
	settings.set_value("photo", "filter", _filter.selected)
	settings.set_value("photo", "resolution", _preferred_resolution)
	var error: Error = settings.save(PREFERENCES_PATH)
	if error != OK:
		push_warning("Could not save Photo Mode settings (%s)." % error_string(error))


func _reset_photo_settings() -> void:
	_apply_photo_settings(ConfigFile.new())
	_player_panel.reset_player_pose()
	if is_instance_valid(_weather_system):
		_weather_system.set_photo_weather(-1.0, 0.0, &"", _gameplay_camera)
		_setup_weather(false)
		_set_filter(_filter.selected)
	_save_photo_settings(false)


func _add_screenshot_size(dimensions: Vector2i, label: String) -> void:
	_screenshot_size.add_item(label)
	_screenshot_size.set_item_metadata(_screenshot_size.item_count - 1, dimensions)


func _open_screenshot_folder() -> void:
	var folder: String = ProjectSettings.globalize_path(SCREENSHOT_DIRECTORY)
	var error: Error = DirAccess.make_dir_recursive_absolute(folder)
	if error == OK:
		error = OS.shell_open(folder)
	if error != OK:
		_report_capture("Could not open Screenshots (%s)." % error_string(error), false)


func _take_screenshot() -> void:
	if _capture_pending or _frame_pending or not visible:
		return
	_capture_pending = true
	var generation: int = _capture_generation
	var viewport: Viewport = get_viewport()
	if _green_screen:
		_sync_green_matte()
	_refresh_screenshot_sizes()
	var dimensions: Vector2i = _screenshot_size.get_selected_metadata()
	_update_canvas_visibility()
	await RenderingServer.frame_post_draw
	if generation != _capture_generation:
		return
	var image: Image = viewport.get_texture().get_image()
	_capture_pending = false
	_update_canvas_visibility()
	if not image or image.is_empty():
		_report_capture("Could not read the photo view.", false)
		return
	if dimensions == Vector2i.ZERO:
		dimensions = get_window().size
	image = _resize_screenshot(image, dimensions)
	var folder: String = ProjectSettings.globalize_path(SCREENSHOT_DIRECTORY)
	var error: Error = DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		_report_capture("Could not create Screenshots (%s)." % error_string(error), false)
		return
	var output_max: float = get_window().get_output_max_linear_value()
	var hdr: bool = output_max > 1.0
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename: String = "SonicVane_%s_%d.%s" % [stamp, Time.get_ticks_usec(), "exr" if hdr else "png"]
	error = _save_screenshot(image, folder.path_join(filename), output_max, viewport.use_hdr_2d)
	if error != OK:
		_report_capture("Screenshot failed (%s)." % error_string(error), false)
		return
	_report_capture("Saved to Screenshots\n" + filename, true)


func _resize_screenshot(image: Image, dimensions: Vector2i) -> Image:
	var source: Vector2i = image.get_size()
	if dimensions == source or dimensions.x <= 0 or dimensions.y <= 0:
		return image
	var crop: Rect2i = _screenshot_crop(source, dimensions)
	if crop.size != source:
		image = image.get_region(crop)
	if crop.size != dimensions:
		image.resize(dimensions.x, dimensions.y, Image.INTERPOLATE_LANCZOS)
	return image


func _screenshot_crop(source: Vector2i, dimensions: Vector2i) -> Rect2i:
	if dimensions.x <= 0 or dimensions.y <= 0:
		return Rect2i(Vector2i.ZERO, source)
	var crop_size: Vector2i = Vector2i(
		mini(source.x, maxi(1, roundi(float(source.y) * dimensions.x / dimensions.y))),
		mini(source.y, maxi(1, roundi(float(source.x) * dimensions.y / dimensions.x))))
	return Rect2i(Vector2i(Vector2(source - crop_size) * 0.5), crop_size)


func _save_screenshot(image: Image, path: String, output_max: float, linear: bool) -> Error:
	if output_max > 1.0:
		return image.save_exr(path, false, true, output_max)
	linear = linear or image.get_format() in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]
	image.convert(Image.FORMAT_RGB8)
	if linear:
		image.linear_to_srgb()
	return image.save_png(path)


func _report_capture(message: String, success: bool) -> void:
	_capture_status.text = message
	_capture_status.show()
	if success:
		_shutter.play()
	else:
		push_warning(message)


func _binding_label(action: StringName) -> String:
	return String(InputBindingGlyphs.get_slot_glyph(action, _hint_controller, _hint_style).get("label", ""))


func _layout_panel() -> void:
	var margin: float = minf(24.0, size.x * 0.04)
	var minimum_width: float = minf(320.0, size.x * 0.44)
	var width: float = clampf(size.x * 0.33, minimum_width, 460.0)
	_panel.offset_left = -width - margin
	_panel.offset_right = -margin
	var vertical_margin: float = minf(24.0, size.y * 0.04)
	_panel.offset_top = vertical_margin
	_panel.offset_bottom = -vertical_margin

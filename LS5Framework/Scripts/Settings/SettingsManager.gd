extends Node

signal resolution_changed(size: Vector2i, aspect_ratio: String)
signal input_bindings_changed(action: StringName)

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_CONFIG_PATH := "res://LS5Framework/Scripts/Settings/DefaultSettings.cfg"
const CONFIG_SCHEMA_VERSION: int = 1
const INPUT_ACTION_NAME_MIGRATIONS: Dictionary = {
	&"action_0": &"ability_slot_01",
	&"action_1": &"ability_slot_02",
	&"action_3": &"ability_slot_03",
	&"action_7": &"ability_slot_04",
	&"action_8": &"ability_slot_05",
	&"ability_jump": &"ability_slot_01",
	&"ability_primary": &"ability_slot_02",
	&"ability_secondary": &"ability_slot_03",
	&"ability_roll": &"ability_slot_04",
	&"ability_drift": &"ability_slot_05",
}

# -----------------------------------------
# Resolution list (you can edit this)
# -----------------------------------------
const BASE_RESOLUTIONS: Array[Dictionary] = [
	{"label": "1280 × 720", "size": Vector2i(1280, 720), "aspect": "16:9"},
	{"label": "1600 × 900", "size": Vector2i(1600, 900), "aspect": "16:9"},
	{"label": "1920 × 1080", "size": Vector2i(1920, 1080), "aspect": "16:9"},
	{"label": "2560 × 1080", "size": Vector2i(2560, 1080), "aspect": "21:9"},
	{"label": "2560 × 1440", "size": Vector2i(2560, 1440), "aspect": "16:9"},
	{"label": "3440 × 1440", "size": Vector2i(3440, 1440), "aspect": "21:9"},
]
var _resolutions: Array[Dictionary] = []

# -----------------------------------------
# Stored settings (defaults)
# -----------------------------------------
var resolution_index: int = 0
var fullscreen: bool = false
var vsync_enabled: bool = false

var ssr: bool = true
var ssao: bool = true
var ssil: bool = false
var sdfgi: bool = false
var shadows: bool = true
var glow: bool = true
var depth_of_field_enabled: bool = true

const RENDER_SCALE_MODE_DIRECT: int = 0
const RENDER_SCALE_MODE_FSR: int = 1
const RENDER_SCALE_NATIVE: float = 1.0
const RENDER_SCALE_HIGH_QUALITY: float = 0.77
const RENDER_SCALE_QUALITY: float = 0.67
const RENDER_SCALE_BALANCED: float = 0.59
const RENDER_SCALE_PERFORMANCE: float = 0.5
const RENDER_SCALE_HIGH_PERFORMANCE: float = 0.4
var render_scale_mode: int = RENDER_SCALE_MODE_DIRECT
var render_scale_ratio: float = RENDER_SCALE_NATIVE

const SHADOW_RESOLUTION_LOW: int = 0
const SHADOW_RESOLUTION_MEDIUM: int = 1
const SHADOW_RESOLUTION_HIGH: int = 2
const SHADOW_RESOLUTION_ULTRA: int = 3
const PARTICLE_QUALITY_LOW: int = 0
const PARTICLE_QUALITY_MEDIUM: int = 1
const PARTICLE_QUALITY_HIGH: int = 2
const PARTICLE_QUALITY_ULTRA: int = 3
const PARTICLE_BASE_RATIO_META: StringName = &"settings_base_amount_ratio"
const VOLUMETRIC_FOG_BASE_ENABLED_META: StringName = &"settings_base_volumetric_fog_enabled"
var volumetric_fog_enabled: bool = true
var shadow_resolution: int = SHADOW_RESOLUTION_HIGH
var particle_quality: int = PARTICLE_QUALITY_ULTRA
var weather_occlusion_enabled: bool = true

const LOD_DISTANCE_LOW: int = 0
const LOD_DISTANCE_MEDIUM: int = 1
const LOD_DISTANCE_HIGH: int = 2
const LOD_DISTANCE_JUICED: int = 3
var lod_distance_quality: int = LOD_DISTANCE_LOW

# Water shader optimization toggles (global uniforms for all water materials).
# These match global uniforms in Shaders/WaterShader_StayAtHomeDev/Shader/Water.gdshader.
var water_displacement_enabled: bool = false
var water_refraction_enabled: bool = true
var water_normal_maps_enabled: bool = true
# Depth effects include depth-based tint, foam, and absorption; refraction is skipped when this is off.
var water_depth_effects_enabled: bool = true

const WATER_GLOBAL_DISPLACEMENT: StringName = &"water_displacement_enabled"
const WATER_GLOBAL_REFRACTION: StringName = &"water_refraction_enabled"
const WATER_GLOBAL_NORMALS: StringName = &"water_normal_maps_enabled"
const WATER_GLOBAL_DEPTH_FX: StringName = &"water_depth_effects_enabled"
# Water SSR is tied to the general SSR toggle to keep reflection options consistent.
const WATER_GLOBAL_SSR: StringName = &"water_ssr_enabled"

var master_percent: float = 50.0
var music_db: float = -6.8
var sfx_db: float = 0.0
var ui_db: float = 0.0
var voice_db: float = -4.8

const MUSIC_MIN_DB: float = -40.0
const MUSIC_MAX_DB: float = 0.0
const SFX_MIN_DB: float = -40.0
const SFX_MAX_DB: float = 0.0
const UI_MIN_DB: float = -40.0
const UI_MAX_DB: float = 0.0
const VOICE_MIN_DB: float = -40.0
const VOICE_MAX_DB: float = 0.0
const MUSIC_MUTE_THRESHOLD_DB: float = MUSIC_MIN_DB
const SFX_MUTE_THRESHOLD_DB: float = SFX_MIN_DB
const UI_MUTE_THRESHOLD_DB: float = UI_MIN_DB
const VOICE_MUTE_THRESHOLD_DB: float = VOICE_MIN_DB
const MOUSE_SENS_MIN: float = 0.1
const MOUSE_SENS_MAX: float = 3.0
const CAMERA_FOV_MIN: float = 40.0
const CAMERA_FOV_MAX: float = 120.0

# Camera
var camera_far_cutoff: float = 4560.0
var camera_default_fov: float = 66.0
var camera_follow_smoothing: float = 39.0
var camera_dolly_enabled: bool = false
var camera_target_lookahead_enabled: bool = true
var camera_target_lookahead_amount: float = 100.0
var camera_auto_follow_enabled: bool = true
var camera_auto_follow_controller_only: bool = true
var camera_auto_follow_sensitivity: float = 24.0
var camera_auto_follow_interrupt_delay: float = 1.2
var camera_auto_follow_deadzone_deg: float = 20.0
var camera_auto_follow_max_deviation_deg: float = 100.0
var camera_auto_follow_vertical_enabled: bool = true
var camera_auto_follow_vertical_max_tilt: float = 31.0
var camera_auto_follow_level_pitch_deg: float = 11.0
var camera_auto_follow_speed_ramp: float = 80.0
var camera_auto_follow_slope_suppression: float = 0.0
var camera_auto_follow_slope_threshold_deg: float = 15.0
var mouse_invert_y: bool = false
var mouse_look_sensitivity: float = 1.0
var right_stick_invert_y: bool = false
const DEFAULT_STICK_DEADZONE_PERCENT: float = 15.0
const DEFAULT_STICK_MAX_PERCENT: float = 100.0
const DEFAULT_RIGHT_STICK_SENSITIVITY_PERCENT: float = 2550.0
const DEFAULT_WALK_STICK_ZONE_PERCENT: float = 35.0
const TRICK_CONTROL_STICK_LEFT: int = 0
const TRICK_CONTROL_STICK_RIGHT: int = 1
const DEFAULT_TRICK_CONTROL_STICK: int = TRICK_CONTROL_STICK_LEFT
const LEFT_STICK_TRICK_MOVEMENT_PRESERVE_MOMENTUM: int = 0
const LEFT_STICK_TRICK_MOVEMENT_LAST_INPUT: int = 1
const DEFAULT_LEFT_STICK_TRICK_MOVEMENT: int = LEFT_STICK_TRICK_MOVEMENT_PRESERVE_MOMENTUM
const DEFAULT_TRICK_ROTATION_ACCELERATION_PERCENT: float = 300.0
var left_stick_deadzone_percent: float = DEFAULT_STICK_DEADZONE_PERCENT
var left_stick_max_percent: float = DEFAULT_STICK_MAX_PERCENT
var right_stick_deadzone_percent: float = DEFAULT_STICK_DEADZONE_PERCENT
var right_stick_max_percent: float = DEFAULT_STICK_MAX_PERCENT
var right_stick_sensitivity_percent: float = DEFAULT_RIGHT_STICK_SENSITIVITY_PERCENT
var walk_stick_zone_percent: float = DEFAULT_WALK_STICK_ZONE_PERCENT
var trick_control_stick: int = DEFAULT_TRICK_CONTROL_STICK
var left_stick_trick_movement: int = DEFAULT_LEFT_STICK_TRICK_MOVEMENT
var trick_rotation_acceleration_percent: float = DEFAULT_TRICK_ROTATION_ACCELERATION_PERCENT
var preferred_joypad_device: int = -1
var _last_input_was_controller: bool = false
var _last_input_was_mouse: bool = false

# Homing / targeting
const HOMING_TARGETING_MOVEMENT: int = 0
const HOMING_TARGETING_CAMERA: int = 1
const HOMING_TARGETING_HYBRID: int = 2

var homing_targeting_mode: int = HOMING_TARGETING_HYBRID
var homing_mouse_targeting_mode: int = HOMING_TARGETING_CAMERA
var homing_targeting_separate_by_device: bool = true
var homing_camera_radius: float = 535.0
var center_reticle_enabled: bool = true
var center_reticle_scale: float = 1.9
var center_reticle_opacity: float = 0.45
var center_reticle_color: Color = Color(0.7187805, 1, 0.62890625, 1)
var reticle_vertical_offset: float = 23.0
var hud_visible: bool = true
var action_prompts_visible: bool = true
var fps_counter_visible: bool = false
var _fps_counter_label: Label = null
var _fps_counter_update_time: float = 0.0

# Lightspeed Dash targeting
const LIGHTSPEED_DASH_TARGETING_MOVEMENT: int = 0
const LIGHTSPEED_DASH_TARGETING_CAMERA: int = 1
const LIGHTSPEED_DASH_TARGETING_HYBRID: int = 2

var lightspeed_dash_targeting_mode: int = LIGHTSPEED_DASH_TARGETING_HYBRID

# Character colors
const DEFAULT_CHOSEN_CHARACTER_ID: String = "sonic_neo_adventure"
const DEFAULT_CHOSEN_BUDDY_CHARACTER_ID: String = "tails"
const DEFAULT_CHARACTER_PRIMARY_COLOR: Color = Color(0, 0.5390625, 0.20255688, 1)
const DEFAULT_CHARACTER_SECONDARY_COLOR: Color = Color(1, 0, 0.44067812, 1)
const DEFAULT_CHARACTER_TRAIL_COLOR: Color = Color(0, 0.65625, 0.1640625, 1)
var chosen_character_id: String = DEFAULT_CHOSEN_CHARACTER_ID
var chosen_buddy_character_id: String = DEFAULT_CHOSEN_BUDDY_CHARACTER_ID
var buddy_active: bool = true
var use_character_colors: bool = false
var character_primary_color: Color = DEFAULT_CHARACTER_PRIMARY_COLOR
var character_secondary_color: Color = DEFAULT_CHARACTER_SECONDARY_COLOR
var character_trail_color: Color = DEFAULT_CHARACTER_TRAIL_COLOR

# Legacy aliases.
var use_character_colors_offline: bool = false
var offline_primary_color: Color = DEFAULT_CHARACTER_PRIMARY_COLOR
var offline_secondary_color: Color = DEFAULT_CHARACTER_SECONDARY_COLOR
var offline_trail_color: Color = DEFAULT_CHARACTER_TRAIL_COLOR

# Combo System
var combo_system_enabled: bool = true
## Reopens the emote wheel on its last used category and page.
var remember_emote_page: bool = true
## Stores the last used emote page across sessions.
var emote_last_page: int = 0

# Diagnostics
var level_load_logging_enabled: bool = true

# Race
const GHOST_RECORDING_RATES: Array[int] = [15, 30, 60]
const DEFAULT_GHOST_RECORDING_RATE: int = 30
const DEFAULT_GHOST_PLAYBACK_RATE: int = 60
const MIN_RACE_GHOST_COUNT: int = 2
const MAX_RACE_GHOST_COUNT: int = 20
const DEFAULT_RACE_GHOST_COUNT: int = 3
var race_dnf_timer_sec: float = 300.0
var race_join_timer_sec: float = 120.0
var race_ghost_enabled: bool = true
var race_multiple_ghosts_enabled: bool = true
var race_ghost_count: int = MAX_RACE_GHOST_COUNT
var race_record_ghost_data: bool = true
var race_ghost_recording_rate: int = 60
var race_ghost_playback_rate: int = 15
var race_selected_ghost_path: String = ""

# Online
const DEFAULT_PLAYER_PRIMARY_COLOR: Color = Color(0.18, 0.52, 1.0, 1.0)
var online_player_name: String = "Marble"
var online_address: String = "127.0.0.1"
var online_invite_code: String = "TFo3fuQlDxk2nAKEsDKnX"
var online_connection_mode: int = 0
var online_port: int = 8910
var online_max_players: int = 16
var online_name_color: Color = Color(0, 1, 0.6953125, 1)
var online_primary_color: Color = DEFAULT_CHARACTER_PRIMARY_COLOR
var online_secondary_color: Color = DEFAULT_CHARACTER_SECONDARY_COLOR
var online_trail_color: Color = DEFAULT_CHARACTER_TRAIL_COLOR

var _graphics_targets: Array = []
var _camera_targets: Array = []
var _depth_of_field_states: Dictionary = {}
var _sdfgi_refresh_tokens: Dictionary = {}
var input_bindings: Dictionary = {}
const CONTROLLER_FOCUS_SCROLL_MARGIN: float = 48.0
const LOCKED_INPUT_ACTIONS: Array[StringName] = [
	&"pause",
	&"enter_chat",
	&"player_tracking_toggle"
]

const PLAYER_TRACKING_MODE_FULL: int = 0
const PLAYER_TRACKING_MODE_MINIMAL: int = 1
const PLAYER_TRACKING_MODE_OFF: int = 2
var player_tracking_mode: int = PLAYER_TRACKING_MODE_MINIMAL

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_refresh_resolution_entries()
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.gui_focus_changed.is_connected(_on_gui_focus_changed):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)
	_load()
	_create_fps_counter()
	if get_tree() != null and not get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.connect(_on_scene_node_added)
	_repair_text_input_actions()
	var actions: Array = InputMap.get_actions()
	ensure_default_input_bindings(actions)
	_apply_display()
	_apply_audio()
	_apply_graphics_to_registered()
	_apply_water_shader_globals()
	_apply_camera_to_registered()
	_apply_camera_to_scene()
	_apply_hud_visibility()
	_apply_fps_counter_visibility()


func _process(delta: float) -> void:
	if not fps_counter_visible or _fps_counter_label == null:
		return
	_fps_counter_update_time -= delta
	if _fps_counter_update_time > 0.0:
		return
	_fps_counter_update_time = 0.25
	_fps_counter_label.text = "%d FPS" % Engine.get_frames_per_second()


func _create_fps_counter() -> void:
	if _fps_counter_label != null:
		return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "FPSCounterLayer"
	layer.layer = 120
	add_child(layer)
	var label: Label = Label.new()
	label.name = "FPSCounter"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label.offset_left = -168.0
	label.offset_top = 24.0
	label.offset_right = -24.0
	label.offset_bottom = 60.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	layer.add_child(label)
	_fps_counter_label = label
	_fps_counter_update_time = 0.0


func _apply_fps_counter_visibility() -> void:
	if _fps_counter_label == null:
		return
	_fps_counter_label.visible = fps_counter_visible
	if fps_counter_visible:
		_fps_counter_update_time = 0.0


# =========================================
# INPUT (F1 reset resolution)
# =========================================
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var joy_device: int = int(event.device)
		if joy_device >= 0:
			preferred_joypad_device = joy_device
	if event is InputEventJoypadButton:
		if event.pressed:
			_last_input_was_controller = true
			_last_input_was_mouse = false
	elif event is InputEventJoypadMotion:
		if abs(event.axis_value) >= 0.2:
			_last_input_was_controller = true
			_last_input_was_mouse = false
	elif event is InputEventMouseMotion:
		if event.relative.length_squared() > 0.0:
			_last_input_was_controller = false
			_last_input_was_mouse = true
	elif event is InputEventMouseButton:
		if event.pressed:
			_last_input_was_controller = false
			_last_input_was_mouse = true
	elif event is InputEventKey:
		if event.pressed:
			_last_input_was_controller = false
			_last_input_was_mouse = false
	# Set "reset_resolution" action to F1 in Input Map
	if event.is_action_pressed("reset_resolution") and not _is_text_input_focused():
		_reset_resolution_to_default()


func _is_text_input_focused() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	var focus_owner: Control = viewport.gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func is_controller_input_active() -> bool:
	return _last_input_was_controller


func is_mouse_input_active() -> bool:
	return _last_input_was_mouse


func _on_gui_focus_changed(control: Control) -> void:
	if _last_input_was_mouse:
		return
	if control == null or not is_instance_valid(control):
		return
	call_deferred("ensure_navigation_focus_visible", control)


func ensure_navigation_focus_visible(control: Control) -> void:
	if _last_input_was_mouse:
		return
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	if control.get_viewport() == null or control.get_viewport().gui_get_focus_owner() != control:
		return
	var scroll_container: ScrollContainer = _find_parent_scroll_container(control)
	if scroll_container == null:
		return
	_apply_controller_focus_scroll_margin(scroll_container, control)


func _find_parent_scroll_container(control: Control) -> ScrollContainer:
	var current: Node = control.get_parent()
	while current != null:
		if current is ScrollContainer and current.is_visible_in_tree():
			return current as ScrollContainer
		current = current.get_parent()
	return null


func _apply_controller_focus_scroll_margin(scroll_container: ScrollContainer, control: Control) -> void:
	if _last_input_was_mouse:
		return
	if scroll_container == null or control == null:
		return
	if not is_instance_valid(scroll_container) or not is_instance_valid(control):
		return
	if not scroll_container.is_visible_in_tree() or not control.is_visible_in_tree():
		return
	if control.get_viewport() == null or control.get_viewport().gui_get_focus_owner() != control:
		return
	var scroll_rect: Rect2 = scroll_container.get_global_rect()
	var control_rect: Rect2 = control.get_global_rect()
	var vertical_margin: float = min(CONTROLLER_FOCUS_SCROLL_MARGIN, scroll_rect.size.y * 0.25)
	var horizontal_margin: float = min(CONTROLLER_FOCUS_SCROLL_MARGIN, scroll_rect.size.x * 0.25)
	var target_vertical: float = float(scroll_container.scroll_vertical)
	var target_horizontal: float = float(scroll_container.scroll_horizontal)
	var visible_top: float = scroll_rect.position.y + vertical_margin
	var visible_bottom: float = scroll_rect.end.y - vertical_margin
	var visible_left: float = scroll_rect.position.x + horizontal_margin
	var visible_right: float = scroll_rect.end.x - horizontal_margin
	if control_rect.position.y < visible_top:
		target_vertical -= visible_top - control_rect.position.y
	elif control_rect.end.y > visible_bottom:
		target_vertical += control_rect.end.y - visible_bottom
	if control_rect.position.x < visible_left:
		target_horizontal -= visible_left - control_rect.position.x
	elif control_rect.end.x > visible_right:
		target_horizontal += control_rect.end.x - visible_right
	var vertical_bar: VScrollBar = scroll_container.get_v_scroll_bar()
	var horizontal_bar: HScrollBar = scroll_container.get_h_scroll_bar()
	var max_vertical: float = max(vertical_bar.max_value - vertical_bar.page, 0.0)
	var max_horizontal: float = max(horizontal_bar.max_value - horizontal_bar.page, 0.0)
	scroll_container.scroll_vertical = int(round(clamp(target_vertical, 0.0, max_vertical)))
	scroll_container.scroll_horizontal = int(round(clamp(target_horizontal, 0.0, max_horizontal)))
	call_deferred("_restore_focus_after_navigation_scroll", scroll_container, control)


func _restore_focus_after_navigation_scroll(scroll_container: ScrollContainer, control: Control) -> void:
	if _last_input_was_mouse:
		return
	if scroll_container == null or control == null:
		return
	if not is_instance_valid(scroll_container) or not is_instance_valid(control):
		return
	if not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return
	var viewport: Viewport = control.get_viewport()
	if viewport == null:
		return
	var focus_owner: Control = viewport.gui_get_focus_owner()
	if focus_owner == control:
		return
	if focus_owner == null or focus_owner == scroll_container or focus_owner == scroll_container.get_v_scroll_bar() or focus_owner == scroll_container.get_h_scroll_bar():
		control.grab_focus()


func get_active_homing_targeting_mode() -> int:
	if homing_targeting_separate_by_device and not is_controller_input_active():
		return homing_mouse_targeting_mode
	return homing_targeting_mode


# =========================================
# PUBLIC: resolution helpers
# =========================================
func get_resolution_count() -> int:
	return _resolutions.size()

func get_resolution_label(index: int) -> String:
	if index < 0 or index >= _resolutions.size():
		return ""
	return "%s  (%s)" % [
		String(_resolutions[index]["label"]),
		String(_resolutions[index]["aspect"]),
	]


func get_resolution_size(index: int) -> Vector2i:
	if index < 0 or index >= _resolutions.size():
		return Vector2i.ZERO
	return Vector2i(_resolutions[index]["size"])


func get_resolution_aspect(index: int) -> String:
	if index < 0 or index >= _resolutions.size():
		return ""
	return String(_resolutions[index]["aspect"])


func get_resolution_aspect_categories() -> Array[String]:
	var categories: Array[String] = []
	for entry: Dictionary in _resolutions:
		var aspect: String = String(entry.get("aspect", ""))
		if aspect != "" and not categories.has(aspect):
			categories.append(aspect)
	return categories

func get_resolution_index() -> int:
	return clampi(resolution_index, 0, _resolutions.size() - 1)

func set_resolution_index(index: int) -> void:
	resolution_index = clampi(index, 0, _resolutions.size() - 1)
	_apply_display()

func _reset_resolution_to_default() -> void:
	resolution_index = _get_monitor_resolution_index()
	fullscreen = false
	_apply_display()
	_save()


func _refresh_resolution_entries() -> void:
	_resolutions.assign(BASE_RESOLUTIONS.duplicate(true))
	var screen_size: Vector2i = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	if screen_size.x <= 0 or screen_size.y <= 0:
		return
	for entry: Dictionary in _resolutions:
		if Vector2i(entry.get("size", Vector2i.ZERO)) == screen_size:
			return
	_resolutions.append({
		"label": "%d × %d" % [screen_size.x, screen_size.y],
		"size": screen_size,
		"aspect": _get_aspect_label(screen_size),
	})


func _get_monitor_resolution_index() -> int:
	var screen_size: Vector2i = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	for index: int in range(_resolutions.size()):
		if Vector2i(_resolutions[index].get("size", Vector2i.ZERO)) == screen_size:
			return index
	return clampi(resolution_index, 0, _resolutions.size() - 1)


func _get_aspect_label(size: Vector2i) -> String:
	if size.x <= 0 or size.y <= 0:
		return "Other"
	var divisor: int = _greatest_common_divisor(size.x, size.y)
	if divisor <= 0:
		return "Other"
	return "%d:%d" % [int(size.x / divisor), int(size.y / divisor)]


func _greatest_common_divisor(a: int, b: int) -> int:
	var left: int = absi(a)
	var right: int = absi(b)
	while right != 0:
		var remainder: int = left % right
		left = right
		right = remainder
	return left


# =========================================
# APPLY DISPLAY / AUDIO / GRAPHICS
# =========================================
func _apply_display() -> void:
	var idx: int = get_resolution_index()
	var size: Vector2i = get_resolution_size(idx)
	var root_window: Window = get_window()
	if fullscreen:
		root_window.content_scale_size = Vector2i.ZERO
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		root_window.content_scale_size = size
		root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		var was_fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_windowed_resolution(size)
		if was_fullscreen:
			call_deferred("_apply_windowed_resolution", size)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	resolution_changed.emit(size, get_resolution_aspect(idx))


func _apply_windowed_resolution(size: Vector2i) -> void:
	if fullscreen:
		return
	DisplayServer.window_set_size(size)
	_center_window_on_current_screen(size)


func _center_window_on_current_screen(window_size: Vector2i) -> void:
	var screen_index: int = DisplayServer.window_get_current_screen()
	var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_index)
	var centered_position: Vector2i = usable_rect.position + Vector2i(
		floori(float(usable_rect.size.x - window_size.x) * 0.5),
		floori(float(usable_rect.size.y - window_size.y) * 0.5)
	)
	DisplayServer.window_set_position(centered_position)

func _apply_audio() -> void:
	var bus_master: int = AudioServer.get_bus_index("Master")
	if bus_master != -1:
		AudioServer.set_bus_volume_db(bus_master, 0.0)

	var bus_music: int = AudioServer.get_bus_index("Music")
	if bus_music != -1:
		var music_percent: float = get_music_volume_percent()
		var master_mix: float = get_master_volume_percent()
		var effective_music : float = clamp((music_percent * master_mix) / 100.0, 0.0, 100.0)
		AudioServer.set_bus_mute(bus_music, effective_music <= 0.0)
		AudioServer.set_bus_volume_db(bus_music, _percent_to_db(effective_music, MUSIC_MIN_DB, MUSIC_MAX_DB))

	var bus_sfx: int = AudioServer.get_bus_index("SFX")
	if bus_sfx != -1:
		var sfx_percent: float = get_sfx_volume_percent()
		var master_mix: float = get_master_volume_percent()
		var effective_sfx : float = clamp((sfx_percent * master_mix) / 100.0, 0.0, 100.0)
		AudioServer.set_bus_mute(bus_sfx, effective_sfx <= 0.0)
		AudioServer.set_bus_volume_db(bus_sfx, _percent_to_db(effective_sfx, SFX_MIN_DB, SFX_MAX_DB))

	var bus_ui: int = AudioServer.get_bus_index("UI")
	if bus_ui != -1:
		var ui_percent: float = get_ui_volume_percent()
		var master_mix: float = get_master_volume_percent()
		var effective_ui: float = clamp((ui_percent * master_mix) / 100.0, 0.0, 100.0)
		AudioServer.set_bus_mute(bus_ui, effective_ui <= 0.0)
		AudioServer.set_bus_volume_db(bus_ui, _percent_to_db(effective_ui, UI_MIN_DB, UI_MAX_DB))

	var bus_voice: int = AudioServer.get_bus_index("Voice")
	if bus_voice != -1:
		var voice_percent: float = get_voice_volume_percent()
		var master_mix: float = get_master_volume_percent()
		var effective_voice : float = clamp((voice_percent * master_mix) / 100.0, 0.0, 100.0)
		AudioServer.set_bus_mute(bus_voice, effective_voice <= 0.0)
		AudioServer.set_bus_volume_db(bus_voice, _percent_to_db(effective_voice, VOICE_MIN_DB, VOICE_MAX_DB))

# Call this from your level scenes:
func apply_camera_to(camera_node: Camera3D) -> void:
	if camera_node == null:
		return
	camera_node.far = max(camera_far_cutoff, 1.0)
	camera_node.fov = clamp(camera_default_fov, CAMERA_FOV_MIN, CAMERA_FOV_MAX)
	_apply_depth_of_field_to_camera(camera_node)


func _apply_depth_of_field_to_camera(camera_node: Camera3D) -> void:
	var camera_attributes: CameraAttributes = camera_node.attributes
	if not camera_attributes:
		return
	var attributes_id: int = camera_attributes.get_instance_id()
	if depth_of_field_enabled:
		if not _depth_of_field_states.has(attributes_id):
			return
		var state: Dictionary = _depth_of_field_states[attributes_id]
		var attributes_ref: WeakRef = state.get("attributes", null)
		if attributes_ref and attributes_ref.get_ref() == camera_attributes:
			camera_attributes.dof_blur_far_enabled = bool(state.get("far_enabled", false))
			camera_attributes.dof_blur_near_enabled = bool(state.get("near_enabled", false))
		_depth_of_field_states.erase(attributes_id)
		return
	if _depth_of_field_states.has(attributes_id):
		var existing_state: Dictionary = _depth_of_field_states[attributes_id]
		var existing_ref: WeakRef = existing_state.get("attributes", null)
		if not existing_ref or existing_ref.get_ref() != camera_attributes:
			_depth_of_field_states.erase(attributes_id)
	if not _depth_of_field_states.has(attributes_id):
		_depth_of_field_states[attributes_id] = {
			"attributes": weakref(camera_attributes),
			"far_enabled": camera_attributes.dof_blur_far_enabled,
			"near_enabled": camera_attributes.dof_blur_near_enabled
		}
	camera_attributes.dof_blur_far_enabled = false
	camera_attributes.dof_blur_near_enabled = false

func _apply_camera_to_scene() -> void:
	# Fallback: apply to any active camera rig in the loaded scene,
	# even if no binder has registered a camera yet.
	if get_tree() == null:
		return
	for rig in get_tree().get_nodes_in_group("CameraRig"):
		if rig == null or not is_instance_valid(rig):
			continue
		if not rig.has_method("get"):
			continue
		var cam = rig.get("camera")
		if cam is Camera3D:
			apply_camera_to(cam)
		if rig.has_method("set_default_fov"):
			rig.call("set_default_fov", camera_default_fov)
		if rig.has_method("set_follow_smoothing"):
			rig.call("set_follow_smoothing", camera_follow_smoothing)
		if rig.has_method("set_dolly_follow_enabled"):
			rig.call("set_dolly_follow_enabled", camera_dolly_enabled)
		if rig.has_method("set_target_lookahead_enabled"):
			rig.call("set_target_lookahead_enabled", camera_target_lookahead_enabled)
		if rig.has_method("set_target_lookahead_amount"):
			rig.call("set_target_lookahead_amount", camera_target_lookahead_amount)
		if rig.has_method("set_auto_follow_enabled"):
			rig.call("set_auto_follow_enabled", camera_auto_follow_enabled)
		if rig.has_method("set_auto_follow_sensitivity"):
			rig.call("set_auto_follow_sensitivity", camera_auto_follow_sensitivity)
		if rig.has_method("set_auto_follow_interrupt_delay"):
			rig.call("set_auto_follow_interrupt_delay", camera_auto_follow_interrupt_delay)
		if rig.has_method("set_auto_follow_deadzone_deg"):
			rig.call("set_auto_follow_deadzone_deg", camera_auto_follow_deadzone_deg)
		if rig.has_method("set_auto_follow_max_deviation_deg"):
			rig.call("set_auto_follow_max_deviation_deg", camera_auto_follow_max_deviation_deg)
		if rig.has_method("set_auto_follow_vertical_enabled"):
			rig.call("set_auto_follow_vertical_enabled", camera_auto_follow_vertical_enabled)
		if rig.has_method("set_auto_follow_vertical_max_tilt_deg"):
			rig.call("set_auto_follow_vertical_max_tilt_deg", camera_auto_follow_vertical_max_tilt)
		if rig.has_method("set_auto_follow_level_pitch_deg"):
			rig.call("set_auto_follow_level_pitch_deg", camera_auto_follow_level_pitch_deg)
		if rig.has_method("set_auto_follow_speed_ramp"):
			rig.call("set_auto_follow_speed_ramp", camera_auto_follow_speed_ramp)
		if rig.has_method("set_auto_follow_slope_suppression"):
			rig.call("set_auto_follow_slope_suppression", camera_auto_follow_slope_suppression)
		if rig.has_method("set_auto_follow_slope_threshold_deg"):
			rig.call("set_auto_follow_slope_threshold_deg", camera_auto_follow_slope_threshold_deg)

# Call this from your level scenes:
func apply_graphics_to(world_env: WorldEnvironment, dir_light: DirectionalLight3D) -> void:
	if world_env and world_env.environment:
		var env: Environment = world_env.environment
		if not env.has_meta(VOLUMETRIC_FOG_BASE_ENABLED_META):
			env.set_meta(VOLUMETRIC_FOG_BASE_ENABLED_META, env.volumetric_fog_enabled)
		env.ssr_enabled = ssr
		env.ssao_enabled = ssao
		env.ssil_enabled = ssil
		env.sdfgi_enabled = sdfgi
		env.glow_enabled = glow
		env.volumetric_fog_enabled = volumetric_fog_enabled and bool(env.get_meta(VOLUMETRIC_FOG_BASE_ENABLED_META, false))

	if dir_light:
		dir_light.shadow_enabled = shadows


func register_graphics_targets(world_env: WorldEnvironment, dir_light: DirectionalLight3D) -> void:
	_cleanup_graphics_targets()
	var entry := {
		"world": world_env if world_env == null else weakref(world_env),
		"light": dir_light if dir_light == null else weakref(dir_light)
	}
	_graphics_targets.append(entry)
	_apply_graphics_to_entry(entry)
	_apply_graphics_to_viewport()
	_refresh_sdfgi_for_environment(world_env)

func register_camera_targets(camera_node: Camera3D) -> void:
	_cleanup_camera_targets()
	_camera_targets.clear()
	var entry := {
		"camera": camera_node if camera_node == null else weakref(camera_node)
	}
	_camera_targets.append(entry)
	_apply_camera_to_entry(entry)


func _cleanup_graphics_targets() -> void:
	var to_remove: Array = []
	for entry in _graphics_targets:
		var world_env: WorldEnvironment = _get_graphics_target(entry, "world")
		var dir_light: DirectionalLight3D = _get_graphics_target(entry, "light")
		if world_env == null and dir_light == null:
			to_remove.append(entry)

	for entry in to_remove:
		_graphics_targets.erase(entry)


func _apply_graphics_to_registered() -> void:
	_cleanup_graphics_targets()
	for entry in _graphics_targets:
		_apply_graphics_to_entry(entry)
	_apply_graphics_to_viewport()
	_apply_shadow_resolution()
	_apply_particle_quality_to_tree()
	_apply_weather_graphics_settings()

func _cleanup_camera_targets() -> void:
	var to_remove: Array = []
	for entry in _camera_targets:
		var cam: Camera3D = _get_camera_target(entry, "camera")
		if cam == null:
			to_remove.append(entry)
	for entry in to_remove:
		_camera_targets.erase(entry)


func _apply_camera_to_registered() -> void:
	_cleanup_camera_targets()
	for entry in _camera_targets:
		_apply_camera_to_entry(entry)


func _apply_camera_to_entry(entry: Dictionary) -> void:
	var cam: Camera3D = _get_camera_target(entry, "camera")
	if cam != null:
		apply_camera_to(cam)


func _get_camera_target(entry: Dictionary, key: String):
	var value = entry.get(key, null)
	if value == null:
		return null
	if value is WeakRef:
		var ref = value.get_ref()
		if ref == null:
			entry[key] = null
		return ref
	return value


func _apply_graphics_to_entry(entry: Dictionary) -> void:
	var world_env: WorldEnvironment = _get_graphics_target(entry, "world")
	var dir_light: DirectionalLight3D = _get_graphics_target(entry, "light")
	if world_env or dir_light:
		apply_graphics_to(world_env, dir_light)


func _apply_graphics_to_viewport() -> void:
	# Some systems (e.g. WorldEnvironmentTrigger) can override the active environment on the Viewport's World3D.
	# Apply to that active environment as well so options always take effect.
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale_mode == RENDER_SCALE_MODE_FSR else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(render_scale_ratio, RENDER_SCALE_HIGH_PERFORMANCE, RENDER_SCALE_NATIVE)
	if not vp.has_method("get_world_3d"):
		return
	var world = vp.call("get_world_3d")
	if world == null:
		return
	var env = world.environment
	if env == null:
		return
	env.ssr_enabled = ssr
	env.ssao_enabled = ssao
	env.ssil_enabled = ssil
	env.sdfgi_enabled = sdfgi
	env.glow_enabled = glow
	if not env.has_meta(VOLUMETRIC_FOG_BASE_ENABLED_META):
		env.set_meta(VOLUMETRIC_FOG_BASE_ENABLED_META, env.volumetric_fog_enabled)
	env.volumetric_fog_enabled = volumetric_fog_enabled and bool(env.get_meta(VOLUMETRIC_FOG_BASE_ENABLED_META, false))


func _apply_shadow_resolution() -> void:
	var resolution_size: int = get_shadow_resolution_size()
	var directional_16_bits: bool = bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", false))
	RenderingServer.directional_shadow_atlas_set_size(resolution_size, directional_16_bits)
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.positional_shadow_atlas_size = resolution_size


func get_shadow_resolution_size() -> int:
	match shadow_resolution:
		SHADOW_RESOLUTION_LOW:
			return 1024
		SHADOW_RESOLUTION_MEDIUM:
			return 2048
		SHADOW_RESOLUTION_ULTRA:
			return 8192
		_:
			return 4096


func get_particle_quality_multiplier() -> float:
	match particle_quality:
		PARTICLE_QUALITY_LOW:
			return 0.35
		PARTICLE_QUALITY_MEDIUM:
			return 0.6
		PARTICLE_QUALITY_HIGH:
			return 0.8
		_:
			return 1.0


func _on_scene_node_added(node: Node) -> void:
	if node is GPUParticles3D or node is CPUParticles3D:
		call_deferred("_apply_graphics_quality_to_node", node)
	if node.is_in_group(&"HUD"):
		call_deferred("_apply_hud_visibility_to_node", node)


func _apply_hud_visibility() -> void:
	if get_tree() == null:
		return
	for hud_node: Node in get_tree().get_nodes_in_group(&"HUD"):
		_apply_hud_visibility_to_node(hud_node)


func _apply_hud_visibility_to_node(hud_node: Node) -> void:
	if hud_node == null or not is_instance_valid(hud_node):
		return
	hud_node.set("visible", hud_visible)


func _apply_particle_quality_to_tree() -> void:
	if get_tree() == null:
		return
	_apply_graphics_quality_to_node(get_tree().root)


func _apply_graphics_quality_to_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is GPUParticles3D or node is CPUParticles3D:
		var ancestor: Node = node.get_parent()
		while ancestor != null:
			if ancestor.is_in_group(&"rain_system"):
				return
			ancestor = ancestor.get_parent()
		if not node.has_meta(PARTICLE_BASE_RATIO_META):
			node.set_meta(PARTICLE_BASE_RATIO_META, float(node.get("amount_ratio")))
		var base_ratio: float = float(node.get_meta(PARTICLE_BASE_RATIO_META, 1.0))
		node.set("amount_ratio", clampf(base_ratio * get_particle_quality_multiplier(), 0.0, 1.0))
		return
	for child: Node in node.get_children():
		_apply_graphics_quality_to_node(child)


func _apply_weather_graphics_settings() -> void:
	if get_tree() == null:
		return
	var particle_multiplier: float = get_particle_quality_multiplier()
	for rain_system: Node in get_tree().get_nodes_in_group(&"rain_system"):
		if rain_system and rain_system.has_method("apply_global_graphics_settings"):
			rain_system.call("apply_global_graphics_settings", particle_multiplier, weather_occlusion_enabled)


func _refresh_sdfgi_for_environment(world_env: WorldEnvironment) -> void:
	if not sdfgi:
		return
	if world_env == null or world_env.environment == null:
		return
	var environment_id: int = int(world_env.environment.get_instance_id())
	var refresh_token: int = int(_sdfgi_refresh_tokens.get(environment_id, 0)) + 1
	_sdfgi_refresh_tokens[environment_id] = refresh_token
	world_env.environment.sdfgi_enabled = false
	call_deferred("_finish_sdfgi_refresh", weakref(world_env), environment_id, refresh_token)


func _finish_sdfgi_refresh(world_env_ref: WeakRef, environment_id: int, refresh_token: int) -> void:
	if get_tree() != null:
		await get_tree().process_frame
	if get_tree() != null:
		await get_tree().process_frame
	if refresh_token != int(_sdfgi_refresh_tokens.get(environment_id, 0)):
		return
	if not sdfgi:
		_sdfgi_refresh_tokens.erase(environment_id)
		return
	if world_env_ref == null:
		_sdfgi_refresh_tokens.erase(environment_id)
		return
	var world_env: Variant = world_env_ref.get_ref()
	if not (world_env is WorldEnvironment):
		_sdfgi_refresh_tokens.erase(environment_id)
		return
	if world_env.environment == null:
		_sdfgi_refresh_tokens.erase(environment_id)
		return
	if int(world_env.environment.get_instance_id()) != environment_id:
		_sdfgi_refresh_tokens.erase(environment_id)
		return
	world_env.environment.sdfgi_enabled = true
	_sdfgi_refresh_tokens.erase(environment_id)
	_apply_graphics_to_viewport()


func _refresh_registered_sdfgi() -> void:
	if not sdfgi:
		return
	_cleanup_graphics_targets()
	var refreshed_environments: Dictionary = {}
	for entry: Dictionary in _graphics_targets:
		var world_env: WorldEnvironment = _get_graphics_target(entry, "world")
		if not world_env or not world_env.environment:
			continue
		var environment_id: int = int(world_env.environment.get_instance_id())
		if refreshed_environments.has(environment_id):
			continue
		refreshed_environments[environment_id] = true
		_refresh_sdfgi_for_environment(world_env)


func _apply_water_shader_globals() -> void:
	# Global shader parameters keep all water materials in sync across scenes.
	RenderingServer.global_shader_parameter_set(WATER_GLOBAL_DISPLACEMENT, water_displacement_enabled)
	RenderingServer.global_shader_parameter_set(WATER_GLOBAL_REFRACTION, water_refraction_enabled)
	RenderingServer.global_shader_parameter_set(WATER_GLOBAL_NORMALS, water_normal_maps_enabled)
	RenderingServer.global_shader_parameter_set(WATER_GLOBAL_DEPTH_FX, water_depth_effects_enabled)
	RenderingServer.global_shader_parameter_set(WATER_GLOBAL_SSR, ssr)


func _get_graphics_target(entry: Dictionary, key: String):
	var value = entry.get(key, null)
	if value == null:
		return null
	if value is WeakRef:
		var ref = value.get_ref()
		if ref == null:
			entry[key] = null
		return ref
	return value


# =========================================
# PUBLIC: setters used by the menu
# =========================================
func set_ssr_enabled(value: bool) -> void:
	ssr = value
	_apply_graphics_to_registered()
	_apply_water_shader_globals()

func set_ssao_enabled(value: bool) -> void:
	ssao = value
	_apply_graphics_to_registered()

func set_ssil_enabled(value: bool) -> void:
	ssil = value
	_apply_graphics_to_registered()

func set_sdfgi_enabled(value: bool) -> void:
	sdfgi = value
	_apply_graphics_to_registered()
	_refresh_registered_sdfgi()

func set_shadows_enabled(value: bool) -> void:
	shadows = value
	_apply_graphics_to_registered()

func set_glow_enabled(value: bool) -> void:
	glow = value
	_apply_graphics_to_registered()

func set_depth_of_field_enabled(value: bool) -> void:
	depth_of_field_enabled = value
	_apply_camera_to_registered()
	_apply_camera_to_scene()


func set_render_scale_mode(value: int) -> void:
	render_scale_mode = clampi(value, RENDER_SCALE_MODE_DIRECT, RENDER_SCALE_MODE_FSR)
	_apply_graphics_to_viewport()


func set_render_scale_ratio(value: float) -> void:
	render_scale_ratio = clampf(value, RENDER_SCALE_HIGH_PERFORMANCE, RENDER_SCALE_NATIVE)
	_apply_graphics_to_viewport()


func get_graphics_snapshot() -> Dictionary:
	return {
		"resolution_index": resolution_index,
		"fullscreen": fullscreen,
		"vsync_enabled": vsync_enabled,
		"render_scale_mode": render_scale_mode,
		"render_scale_ratio": render_scale_ratio,
		"volumetric_fog_enabled": volumetric_fog_enabled,
		"shadow_resolution": shadow_resolution,
		"particle_quality": particle_quality,
		"weather_occlusion_enabled": weather_occlusion_enabled,
		"ssr": ssr,
		"ssao": ssao,
		"ssil": ssil,
		"sdfgi": sdfgi,
		"shadows": shadows,
		"glow": glow,
		"depth_of_field_enabled": depth_of_field_enabled,
		"lod_distance_quality": lod_distance_quality,
		"water_displacement_enabled": water_displacement_enabled,
		"water_refraction_enabled": water_refraction_enabled,
		"water_normal_maps_enabled": water_normal_maps_enabled,
		"water_depth_effects_enabled": water_depth_effects_enabled,
		"camera_far_cutoff": camera_far_cutoff,
	}


func apply_graphics_snapshot(snapshot: Dictionary) -> void:
	resolution_index = clampi(int(snapshot.get("resolution_index", resolution_index)), 0, _resolutions.size() - 1)
	fullscreen = bool(snapshot.get("fullscreen", fullscreen))
	vsync_enabled = bool(snapshot.get("vsync_enabled", vsync_enabled))
	render_scale_mode = clampi(int(snapshot.get("render_scale_mode", render_scale_mode)), RENDER_SCALE_MODE_DIRECT, RENDER_SCALE_MODE_FSR)
	render_scale_ratio = clampf(float(snapshot.get("render_scale_ratio", render_scale_ratio)), RENDER_SCALE_HIGH_PERFORMANCE, RENDER_SCALE_NATIVE)
	volumetric_fog_enabled = bool(snapshot.get("volumetric_fog_enabled", volumetric_fog_enabled))
	shadow_resolution = clampi(int(snapshot.get("shadow_resolution", shadow_resolution)), SHADOW_RESOLUTION_LOW, SHADOW_RESOLUTION_ULTRA)
	particle_quality = clampi(int(snapshot.get("particle_quality", particle_quality)), PARTICLE_QUALITY_LOW, PARTICLE_QUALITY_ULTRA)
	weather_occlusion_enabled = bool(snapshot.get("weather_occlusion_enabled", weather_occlusion_enabled))
	ssr = bool(snapshot.get("ssr", ssr))
	ssao = bool(snapshot.get("ssao", ssao))
	ssil = bool(snapshot.get("ssil", ssil))
	sdfgi = bool(snapshot.get("sdfgi", sdfgi))
	shadows = bool(snapshot.get("shadows", shadows))
	glow = bool(snapshot.get("glow", glow))
	depth_of_field_enabled = bool(snapshot.get("depth_of_field_enabled", depth_of_field_enabled))
	lod_distance_quality = clampi(int(snapshot.get("lod_distance_quality", lod_distance_quality)), LOD_DISTANCE_LOW, LOD_DISTANCE_JUICED)
	water_displacement_enabled = bool(snapshot.get("water_displacement_enabled", water_displacement_enabled))
	water_refraction_enabled = bool(snapshot.get("water_refraction_enabled", water_refraction_enabled))
	water_normal_maps_enabled = bool(snapshot.get("water_normal_maps_enabled", water_normal_maps_enabled))
	water_depth_effects_enabled = bool(snapshot.get("water_depth_effects_enabled", water_depth_effects_enabled))
	camera_far_cutoff = maxf(float(snapshot.get("camera_far_cutoff", camera_far_cutoff)), 1.0)
	_apply_display()
	_apply_graphics_to_registered()
	_apply_water_shader_globals()
	_apply_camera_to_registered()
	_apply_camera_to_scene()
	_refresh_registered_sdfgi()
	if get_tree() != null:
		for lod_node: Node in get_tree().get_nodes_in_group(&"DistanceMeshLOD"):
			if lod_node and lod_node.has_method("refresh"):
				lod_node.call("refresh")

func set_lod_distance_quality(value: int) -> void:
	lod_distance_quality = clampi(value, LOD_DISTANCE_LOW, LOD_DISTANCE_JUICED)
	if get_tree() == null:
		return
	for lod_node: Node in get_tree().get_nodes_in_group(&"DistanceMeshLOD"):
		if lod_node and lod_node.has_method("refresh"):
			lod_node.call("refresh")

func get_lod_distance_multiplier() -> float:
	var index: int = clampi(lod_distance_quality, LOD_DISTANCE_LOW, LOD_DISTANCE_JUICED)
	match index:
		LOD_DISTANCE_LOW:
			return 0.5
		LOD_DISTANCE_MEDIUM:
			return 1.0
		LOD_DISTANCE_JUICED:
			return 2.5
		_:
			return 1.5

func set_water_displacement_enabled(value: bool) -> void:
	water_displacement_enabled = value
	_apply_water_shader_globals()

func set_water_refraction_enabled(value: bool) -> void:
	water_refraction_enabled = value
	_apply_water_shader_globals()

func set_water_normal_maps_enabled(value: bool) -> void:
	water_normal_maps_enabled = value
	_apply_water_shader_globals()

func set_water_depth_effects_enabled(value: bool) -> void:
	water_depth_effects_enabled = value
	_apply_water_shader_globals()

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_display()

func set_vsync_enabled(value: bool) -> void:
	vsync_enabled = value
	# hook vsync here if desired

func set_master_db(value: float) -> void:
	# Backward-compatible alias; percent input expected now.
	set_master_volume_percent(value)

func set_music_db(db: float) -> void:
	music_db = db
	_apply_audio()

func set_sfx_db(db: float) -> void:
	sfx_db = db
	_apply_audio()

func set_ui_db(db: float) -> void:
	ui_db = db
	_apply_audio()

func set_voice_db(db: float) -> void:
	voice_db = db
	_apply_audio()

func set_master_volume_percent(percent: float) -> void:
	master_percent = clamp(percent, 0.0, 100.0)
	_apply_audio()

func get_master_volume_percent() -> float:
	return clamp(master_percent, 0.0, 100.0)

func set_music_volume_percent(percent: float) -> void:
	music_db = _percent_to_db(percent, MUSIC_MIN_DB, MUSIC_MAX_DB)
	_apply_audio()

func set_sfx_volume_percent(percent: float) -> void:
	sfx_db = _percent_to_db(percent, SFX_MIN_DB, SFX_MAX_DB)
	_apply_audio()

func set_ui_volume_percent(percent: float) -> void:
	ui_db = _percent_to_db(percent, UI_MIN_DB, UI_MAX_DB)
	_apply_audio()

func set_voice_volume_percent(percent: float) -> void:
	voice_db = _percent_to_db(percent, VOICE_MIN_DB, VOICE_MAX_DB)
	_apply_audio()

func get_music_volume_percent() -> float:
	return _db_to_percent(music_db, MUSIC_MIN_DB, MUSIC_MAX_DB)

func get_sfx_volume_percent() -> float:
	return _db_to_percent(sfx_db, SFX_MIN_DB, SFX_MAX_DB)

func get_ui_volume_percent() -> float:
	return _db_to_percent(ui_db, UI_MIN_DB, UI_MAX_DB)

func get_voice_volume_percent() -> float:
	return _db_to_percent(voice_db, VOICE_MIN_DB, VOICE_MAX_DB)

func _percent_to_db(percent: float, min_db: float, max_db: float) -> float:
	var t: float = clamp(percent / 100.0, 0.0, 1.0)
	return lerp(min_db, max_db, t)

func _db_to_percent(db_value: float, min_db: float, max_db: float) -> float:
	var range_db: float = max(max_db - min_db, 0.001)
	var t: float = clamp((db_value - min_db) / range_db, 0.0, 1.0)
	return t * 100.0

func set_camera_far_cutoff(value: float) -> void:
	camera_far_cutoff = max(value, 1.0)
	_apply_camera_to_registered()
	_apply_camera_to_scene()

func set_camera_default_fov(value: float) -> void:
	camera_default_fov = clamp(value, CAMERA_FOV_MIN, CAMERA_FOV_MAX)
	_apply_camera_to_registered()
	_apply_camera_to_scene()


func set_camera_follow_smoothing(value: float) -> void:
	camera_follow_smoothing = max(value, 0.0)
	_apply_camera_to_scene()


func set_camera_dolly_enabled(value: bool) -> void:
	camera_dolly_enabled = value
	_apply_camera_to_scene()


func set_camera_target_lookahead_enabled(value: bool) -> void:
	camera_target_lookahead_enabled = value
	_apply_camera_to_scene()


func set_camera_target_lookahead_amount(value: float) -> void:
	camera_target_lookahead_amount = clamp(value, 0.0, 100.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_enabled(value: bool) -> void:
	camera_auto_follow_enabled = value
	_apply_camera_to_scene()


func set_camera_auto_follow_controller_only(value: bool) -> void:
	camera_auto_follow_controller_only = value


func set_camera_auto_follow_sensitivity(value: float) -> void:
	camera_auto_follow_sensitivity = max(value, 0.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_interrupt_delay(value: float) -> void:
	camera_auto_follow_interrupt_delay = max(value, 0.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_deadzone_deg(value: float) -> void:
	camera_auto_follow_deadzone_deg = clamp(value, 0.0, 180.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_max_deviation_deg(value: float) -> void:
	camera_auto_follow_max_deviation_deg = clamp(value, camera_auto_follow_deadzone_deg, 180.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_vertical_enabled(value: bool) -> void:
	camera_auto_follow_vertical_enabled = value
	_apply_camera_to_scene()


func set_camera_auto_follow_vertical_max_tilt(value: float) -> void:
	camera_auto_follow_vertical_max_tilt = clamp(value, 0.0, 90.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_level_pitch_deg(value: float) -> void:
	camera_auto_follow_level_pitch_deg = clamp(value, -89.0, 89.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_speed_ramp(value: float) -> void:
	camera_auto_follow_speed_ramp = max(value, 0.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_slope_suppression(value: float) -> void:
	camera_auto_follow_slope_suppression = clamp(value, 0.0, 1.0)
	_apply_camera_to_scene()


func set_camera_auto_follow_slope_threshold_deg(value: float) -> void:
	camera_auto_follow_slope_threshold_deg = clamp(value, 0.0, 90.0)
	_apply_camera_to_scene()


func set_mouse_invert_y(value: bool) -> void:
	mouse_invert_y = value


func set_mouse_look_sensitivity(value: float) -> void:
	mouse_look_sensitivity = clamp(value, MOUSE_SENS_MIN, MOUSE_SENS_MAX)


func set_right_stick_invert_y(value: bool) -> void:
	right_stick_invert_y = value


func set_left_stick_deadzone_percent(value: float) -> void:
	left_stick_deadzone_percent = clamp(value, 0.0, 100.0)


func set_left_stick_max_percent(value: float) -> void:
	left_stick_max_percent = clamp(value, left_stick_deadzone_percent, 100.0)


func set_right_stick_deadzone_percent(value: float) -> void:
	right_stick_deadzone_percent = clamp(value, 0.0, 100.0)


func set_right_stick_max_percent(value: float) -> void:
	right_stick_max_percent = clamp(value, right_stick_deadzone_percent, 100.0)


func set_right_stick_sensitivity_percent(value: float) -> void:
	right_stick_sensitivity_percent = clamp(value, 700.0, 3000.0)


func set_walk_stick_zone_percent(value: float) -> void:
	walk_stick_zone_percent = clamp(value, 0.0, 100.0)


func set_trick_control_stick(value: int) -> void:
	trick_control_stick = clampi(value, TRICK_CONTROL_STICK_LEFT, TRICK_CONTROL_STICK_RIGHT)


func set_left_stick_trick_movement(value: int) -> void:
	left_stick_trick_movement = clampi(
		value,
		LEFT_STICK_TRICK_MOVEMENT_PRESERVE_MOMENTUM,
		LEFT_STICK_TRICK_MOVEMENT_LAST_INPUT
	)


func set_trick_rotation_acceleration_percent(value: float) -> void:
	trick_rotation_acceleration_percent = clamp(value, 50.0, 300.0)


func set_homing_targeting_mode(mode: int) -> void:
	homing_targeting_mode = clamp(mode, HOMING_TARGETING_MOVEMENT, HOMING_TARGETING_HYBRID)


func set_homing_mouse_targeting_mode(mode: int) -> void:
	homing_mouse_targeting_mode = clamp(mode, HOMING_TARGETING_MOVEMENT, HOMING_TARGETING_HYBRID)


func set_homing_targeting_separate_by_device(value: bool) -> void:
	homing_targeting_separate_by_device = value


func set_homing_camera_radius(value: float) -> void:
	homing_camera_radius = max(value, 0.0)


func set_center_reticle_enabled(value: bool) -> void:
	center_reticle_enabled = value


func set_hud_visible(value: bool) -> void:
	hud_visible = value
	_apply_hud_visibility()


func set_action_prompts_visible(value: bool) -> void:
	action_prompts_visible = value


func set_fps_counter_visible(value: bool) -> void:
	fps_counter_visible = value
	_apply_fps_counter_visibility()


func set_center_reticle_scale(value: float) -> void:
	center_reticle_scale = max(value, 0.01)


func set_center_reticle_opacity(value: float) -> void:
	center_reticle_opacity = clamp(value, 0.0, 1.0)


func set_center_reticle_color(value: Color) -> void:
	center_reticle_color = value


func set_chosen_character_id(value: String) -> void:
	var normalized: String = value.strip_edges()
	if normalized.nocasecmp_to("sonic") == 0:
		normalized = DEFAULT_CHOSEN_CHARACTER_ID
	if normalized == "":
		normalized = DEFAULT_CHOSEN_CHARACTER_ID
	chosen_character_id = normalized


func set_chosen_buddy_character_id(value: String) -> void:
	var normalized: String = value.strip_edges()
	if normalized.nocasecmp_to("sonic") == 0:
		normalized = DEFAULT_CHOSEN_CHARACTER_ID
	if normalized == "":
		normalized = DEFAULT_CHOSEN_BUDDY_CHARACTER_ID
	chosen_buddy_character_id = normalized


func set_buddy_active(value: bool) -> void:
	buddy_active = value


func set_use_character_colors(value: bool) -> void:
	use_character_colors = value
	use_character_colors_offline = value


func set_use_character_colors_offline(value: bool) -> void:
	set_use_character_colors(value)


func set_character_primary_color(value: Color) -> void:
	character_primary_color = value
	offline_primary_color = value
	online_primary_color = value


func set_offline_primary_color(value: Color) -> void:
	set_character_primary_color(value)


func set_character_secondary_color(value: Color) -> void:
	character_secondary_color = value
	offline_secondary_color = value
	online_secondary_color = value


func set_offline_secondary_color(value: Color) -> void:
	set_character_secondary_color(value)


func set_character_trail_color(value: Color) -> void:
	character_trail_color = value
	offline_trail_color = value
	online_trail_color = value


func set_offline_trail_color(value: Color) -> void:
	set_character_trail_color(value)


func set_reticle_vertical_offset(value: float) -> void:
	reticle_vertical_offset = clamp(value, 0.0, 100.0)


func set_combo_system_enabled(value: bool) -> void:
	combo_system_enabled = value


func set_remember_emote_page(value: bool) -> void:
	remember_emote_page = value


func set_emote_last_page(value: int) -> void:
	var page: int = maxi(value, 0)
	if page == emote_last_page:
		return
	emote_last_page = page
	save_now()


func set_level_load_logging_enabled(value: bool) -> void:
	level_load_logging_enabled = value


func set_race_record_ghost_data(value: bool) -> void:
	race_record_ghost_data = value


func set_race_multiple_ghosts_enabled(value: bool) -> void:
	race_multiple_ghosts_enabled = value


func set_race_ghost_count(value: int) -> void:
	race_ghost_count = clampi(value, MIN_RACE_GHOST_COUNT, MAX_RACE_GHOST_COUNT)


func set_race_ghost_recording_rate(value: int) -> void:
	race_ghost_recording_rate = normalize_ghost_recording_rate(value)


func set_race_ghost_playback_rate(value: int) -> void:
	race_ghost_playback_rate = normalize_ghost_recording_rate(value)


func normalize_ghost_recording_rate(value: int) -> int:
	if GHOST_RECORDING_RATES.has(value):
		return value
	var closest_rate: int = DEFAULT_GHOST_RECORDING_RATE
	var closest_distance: int = abs(value - closest_rate)
	for rate: int in GHOST_RECORDING_RATES:
		var distance: int = abs(value - rate)
		if distance < closest_distance:
			closest_rate = rate
			closest_distance = distance
	return closest_rate


func set_lightspeed_dash_targeting_mode(mode: int) -> void:
	lightspeed_dash_targeting_mode = clamp(mode, LIGHTSPEED_DASH_TARGETING_MOVEMENT, LIGHTSPEED_DASH_TARGETING_HYBRID)


func set_player_tracking_mode(mode: int) -> void:
	player_tracking_mode = clampi(mode, PLAYER_TRACKING_MODE_FULL, PLAYER_TRACKING_MODE_OFF)


func reset_control_settings_to_defaults(action_names: Array) -> void:
	mouse_invert_y = false
	mouse_look_sensitivity = 1.0
	right_stick_invert_y = false
	left_stick_deadzone_percent = DEFAULT_STICK_DEADZONE_PERCENT
	left_stick_max_percent = DEFAULT_STICK_MAX_PERCENT
	right_stick_deadzone_percent = DEFAULT_STICK_DEADZONE_PERCENT
	right_stick_max_percent = DEFAULT_STICK_MAX_PERCENT
	right_stick_sensitivity_percent = DEFAULT_RIGHT_STICK_SENSITIVITY_PERCENT
	walk_stick_zone_percent = DEFAULT_WALK_STICK_ZONE_PERCENT
	trick_control_stick = DEFAULT_TRICK_CONTROL_STICK
	left_stick_trick_movement = DEFAULT_LEFT_STICK_TRICK_MOVEMENT
	trick_rotation_acceleration_percent = DEFAULT_TRICK_ROTATION_ACCELERATION_PERCENT
	homing_targeting_mode = HOMING_TARGETING_HYBRID
	homing_mouse_targeting_mode = HOMING_TARGETING_CAMERA
	homing_targeting_separate_by_device = true
	camera_auto_follow_controller_only = true
	reset_input_bindings_to_project_defaults(action_names)
	_save()


func reset_all_settings_to_defaults() -> Error:
	var err: Error = _replace_with_packaged_defaults()
	if err != OK:
		return err
	InputMap.load_from_project_settings()
	_load()
	_repair_text_input_actions()
	_apply_display()
	_apply_audio()
	_apply_graphics_to_registered()
	_apply_water_shader_globals()
	_apply_camera_to_registered()
	_apply_camera_to_scene()
	_apply_hud_visibility()
	_apply_fps_counter_visibility()
	return OK


# =========================================
# INPUT BINDINGS
# =========================================
func set_action_keycodes(action_name: StringName, keycodes: Array) -> void:
	var bindings: Array = []
	for keycode_value in keycodes:
		var keycode_int: int = int(keycode_value)
		if keycode_int == Key.KEY_NONE:
			continue
		bindings.append({"type": "key", "keycode": keycode_int})
	set_action_bindings(action_name, bindings)


func set_action_bindings_for_kind(action_name: StringName, binding_kind: StringName, bindings: Array) -> void:
	if action_name == &"":
		return
	if _is_input_action_locked(action_name):
		return
	var existing: Array = get_action_bindings(action_name)
	var merged: Array = []
	for binding in existing:
		if not (binding is Dictionary):
			continue
		if _binding_kind_matches(String(binding.get("type", "")), binding_kind):
			continue
		merged.append(binding)
	for binding in bindings:
		var cleaned: Dictionary = _sanitize_input_binding(binding)
		if cleaned.is_empty():
			continue
		if not _binding_kind_matches(String(cleaned.get("type", "")), binding_kind):
			continue
		merged.append(cleaned)
	input_bindings[action_name] = merged
	_apply_bindings_to_action(action_name, merged)
	_save()


func set_action_bindings(action_name: StringName, bindings: Array) -> void:
	if action_name == &"":
		return
	if _is_input_action_locked(action_name):
		return
	var cleaned: Array = []
	for binding in bindings:
		var cleaned_binding: Dictionary = _sanitize_input_binding(binding)
		if cleaned_binding.is_empty():
			continue
		cleaned.append(cleaned_binding)
	input_bindings[action_name] = cleaned
	_apply_bindings_to_action(action_name, cleaned)
	_save()


func _apply_keycodes_to_action(action_name: StringName, keycodes: Array) -> void:
	var bindings: Array = []
	for keycode_value in keycodes:
		var keycode_int: int = int(keycode_value)
		if keycode_int == Key.KEY_NONE:
			continue
		bindings.append({"type": "key", "keycode": keycode_int})
	_apply_bindings_to_action(action_name, bindings)


func _apply_bindings_to_action(action_name: StringName, bindings: Array) -> void:
	if _is_input_action_locked(action_name):
		return
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	var events: Array = InputMap.action_get_events(action_name)
	for ev in events:
		if ev is InputEventKey or ev is InputEventMouseButton or ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			InputMap.action_erase_event(action_name, ev)

	for binding in bindings:
		if not (binding is Dictionary):
			continue
		var binding_dict: Dictionary = binding
		var bind_type: String = String(binding_dict.get("type", ""))
		if bind_type == "key":
			var keycode_value: int = int(binding_dict.get("keycode", Key.KEY_NONE))
			if keycode_value == Key.KEY_NONE:
				continue
			var ev_key: InputEventKey = InputEventKey.new()
			ev_key.keycode = keycode_value
			InputMap.action_add_event(action_name, ev_key)
		elif bind_type == "mouse":
			var button_value: int = int(binding_dict.get("button", 0))
			if button_value <= 0:
				continue
			var ev_mouse: InputEventMouseButton = InputEventMouseButton.new()
			ev_mouse.button_index = button_value
			ev_mouse.pressed = true
			InputMap.action_add_event(action_name, ev_mouse)
		elif bind_type == "joy_button":
			var joy_button: int = int(binding_dict.get("button", -1))
			if joy_button < 0:
				continue
			var ev_joy_button: InputEventJoypadButton = InputEventJoypadButton.new()
			ev_joy_button.device = -1
			ev_joy_button.button_index = joy_button
			ev_joy_button.pressed = true
			InputMap.action_add_event(action_name, ev_joy_button)
		elif bind_type == "joy_motion":
			var joy_axis: int = int(binding_dict.get("axis", -1))
			var joy_axis_value: float = float(binding_dict.get("axis_value", 0.0))
			if joy_axis < 0 or joy_axis_value == 0.0:
				continue
			var ev_joy_motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
			ev_joy_motion.device = -1
			ev_joy_motion.axis = joy_axis
			ev_joy_motion.axis_value = joy_axis_value
			InputMap.action_add_event(action_name, ev_joy_motion)
	input_bindings_changed.emit(action_name)


func ensure_default_input_bindings(action_names: Array) -> void:
	if _has_any_input_bindings():
		return
	var changed: bool = false
	for action_entry in action_names:
		var action_name: StringName = StringName(action_entry)
		if _is_input_action_locked(action_name):
			continue
		var bindings: Array = _get_bindings_from_action(action_name)
		if bindings.is_empty():
			continue
		input_bindings[action_name] = bindings
		changed = true
	if changed:
		_save()


func reset_input_bindings_to_project_defaults(action_names: Array) -> void:
	# SUMMARY: Restore input bindings from the Project Settings defaults.
	# STEPS:
	# - Step 1: Reload InputMap from Project Settings.
	# - Step 2: Rebuild stored bindings for the provided action list.
	InputMap.load_from_project_settings()
	input_bindings.clear()
	for action_entry in action_names:
		var action_name: StringName = StringName(action_entry)
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		if _is_input_action_locked(action_name):
			continue
		var bindings: Array = _get_bindings_from_action(action_name)
		if bindings.is_empty():
			continue
		input_bindings[action_name] = bindings
	_save()


func get_action_bindings(action_name: StringName) -> Array:
	if input_bindings.has(action_name):
		var bindings: Variant = input_bindings[action_name]
		if bindings is Array:
			return (bindings as Array).duplicate(true)
	return []


func _has_any_input_bindings() -> bool:
	for binding_list in input_bindings.values():
		if binding_list is Array and binding_list.size() > 0:
			return true
	return false


func is_gameplay_action_pressed(action_name: StringName) -> bool:
	return not EmoteWheel.is_action_blocked(action_name) and Input.is_action_pressed(action_name)


func is_gameplay_action_just_pressed(action_name: StringName) -> bool:
	return not EmoteWheel.is_action_blocked(action_name) and Input.is_action_just_pressed(action_name)


func is_gameplay_action_just_released(action_name: StringName) -> bool:
	return not EmoteWheel.is_action_blocked(action_name) and Input.is_action_just_released(action_name)


func get_action_input_strength(action_name: StringName, min_output: float = 0.0, binding_kind: StringName = &"") -> float:
	if EmoteWheel.is_action_blocked(action_name):
		return 0.0
	if action_name == &"":
		return 0.0
	var bindings: Array = get_action_bindings(action_name)
	if bindings.is_empty() and InputMap.has_action(action_name):
		bindings = _get_bindings_from_action(action_name)
	var best_strength: float = 0.0
	for binding in bindings:
		if not (binding is Dictionary):
			continue
		var binding_dict: Dictionary = binding
		var bind_type: String = String(binding_dict.get("type", ""))
		if not _binding_kind_matches(bind_type, binding_kind):
			continue
		var strength: float = _get_binding_strength(binding_dict, min_output)
		if bind_type == "joy_motion":
			strength = max(strength, 0.0)
		best_strength = max(best_strength, strength)
	return clamp(best_strength, 0.0, 1.0)


func get_signed_action_axis(negative_action: StringName, positive_action: StringName, min_output: float = 0.0, binding_kind: StringName = &"") -> float:
	return get_action_input_strength(positive_action, min_output, binding_kind) - get_action_input_strength(negative_action, min_output, binding_kind)


func get_raw_action_input_strength(action_name: StringName, binding_kind: StringName = &"") -> float:
	if EmoteWheel.is_action_blocked(action_name):
		return 0.0
	if action_name == &"":
		return 0.0
	var bindings: Array = get_action_bindings(action_name)
	if bindings.is_empty() and InputMap.has_action(action_name):
		bindings = _get_bindings_from_action(action_name)
	var best_strength: float = 0.0
	for binding in bindings:
		if not (binding is Dictionary):
			continue
		var binding_dict: Dictionary = binding
		var bind_type: String = String(binding_dict.get("type", ""))
		if not _binding_kind_matches(bind_type, binding_kind):
			continue
		var strength: float = _get_binding_strength(binding_dict, 0.0, false)
		if bind_type == "joy_motion":
			strength = max(strength, 0.0)
		best_strength = max(best_strength, strength)
	return clamp(best_strength, 0.0, 1.0)


func get_raw_signed_action_axis(negative_action: StringName, positive_action: StringName, binding_kind: StringName = &"") -> float:
	return get_raw_action_input_strength(positive_action, binding_kind) - get_raw_action_input_strength(negative_action, binding_kind)


func get_raw_action_vector(
	negative_x_action: StringName,
	positive_x_action: StringName,
	negative_y_action: StringName,
	positive_y_action: StringName,
	binding_kind: StringName = &""
) -> Vector2:
	var raw_x: float = get_raw_signed_action_axis(negative_x_action, positive_x_action, binding_kind)
	var raw_y: float = get_raw_signed_action_axis(negative_y_action, positive_y_action, binding_kind)
	return Vector2(raw_x, raw_y)


func get_radial_action_vector(
	negative_x_action: StringName,
	positive_x_action: StringName,
	negative_y_action: StringName,
	positive_y_action: StringName,
	deadzone: float,
	max_output: float,
	binding_kind: StringName = &""
) -> Vector2:
	var raw_vector: Vector2 = get_raw_action_vector(
		negative_x_action,
		positive_x_action,
		negative_y_action,
		positive_y_action,
		binding_kind
	)
	var raw_magnitude: float = raw_vector.length()
	if raw_magnitude < 0.001:
		return Vector2.ZERO

	var deadzone_clamped: float = clamp(deadzone, 0.0, 1.0)
	var max_output_clamped: float = clamp(max_output, deadzone_clamped, 1.0)
	if raw_magnitude <= deadzone_clamped or max_output_clamped <= deadzone_clamped:
		return Vector2.ZERO

	var remapped_magnitude: float = clamp(
		(raw_magnitude - deadzone_clamped) / (max_output_clamped - deadzone_clamped),
		0.0,
		1.0
	)
	return raw_vector.normalized() * remapped_magnitude


func get_left_stick_deadzone() -> float:
	return clamp(left_stick_deadzone_percent / 100.0, 0.0, 1.0)


func get_left_stick_max() -> float:
	return clamp(left_stick_max_percent / 100.0, get_left_stick_deadzone(), 1.0)


func get_right_stick_deadzone() -> float:
	return clamp(right_stick_deadzone_percent / 100.0, 0.0, 1.0)


func get_right_stick_max() -> float:
	return clamp(right_stick_max_percent / 100.0, get_right_stick_deadzone(), 1.0)


func get_right_stick_sensitivity() -> float:
	return clamp(right_stick_sensitivity_percent / 100.0, 7.0, 30.0)


func get_trick_rotation_acceleration() -> float:
	return clamp(trick_rotation_acceleration_percent / 100.0, 0.5, 3.0)


func _binding_kind_matches(binding_type: String, binding_kind: StringName) -> bool:
	if binding_kind == &"":
		return true
	if binding_kind == &"keyboard":
		return binding_type == "key" or binding_type == "mouse"
	if binding_kind == &"gamepad":
		return binding_type == "joy_button" or binding_type == "joy_motion"
	return false


func _sanitize_input_binding(binding: Variant) -> Dictionary:
	if binding is Dictionary:
		var binding_dict: Dictionary = binding
		var bind_type: String = String(binding_dict.get("type", ""))
		if bind_type == "key":
			var keycode_value: int = int(binding_dict.get("keycode", Key.KEY_NONE))
			if keycode_value != Key.KEY_NONE:
				return {"type": "key", "keycode": keycode_value}
		elif bind_type == "mouse":
			var button_value: int = int(binding_dict.get("button", 0))
			if button_value > 0:
				return {"type": "mouse", "button": button_value}
		elif bind_type == "joy_button":
			var joy_button: int = int(binding_dict.get("button", -1))
			if joy_button >= 0:
				return {"type": "joy_button", "button": joy_button}
		elif bind_type == "joy_motion":
			var joy_axis: int = int(binding_dict.get("axis", -1))
			var joy_axis_value: float = float(binding_dict.get("axis_value", 0.0))
			if joy_axis >= 0 and joy_axis_value != 0.0:
				return {"type": "joy_motion", "axis": joy_axis, "axis_value": signf(joy_axis_value)}
	elif binding != null:
		var fallback_key: int = int(binding)
		if fallback_key != Key.KEY_NONE:
			return {"type": "key", "keycode": fallback_key}
	return {}


func _get_binding_strength(binding: Dictionary, min_output: float, apply_deadzone: bool = true) -> float:
	var bind_type: String = String(binding.get("type", ""))
	if bind_type == "key":
		var keycode_value: int = int(binding.get("keycode", Key.KEY_NONE))
		if keycode_value != Key.KEY_NONE and Input.is_key_pressed(keycode_value):
			return 1.0
	elif bind_type == "mouse":
		var mouse_button: int = int(binding.get("button", 0))
		if mouse_button > 0 and Input.is_mouse_button_pressed(mouse_button):
			return 1.0
	elif bind_type == "joy_button":
		var joy_button: int = int(binding.get("button", -1))
		if joy_button < 0:
			return 0.0
		var joy_device: int = get_preferred_joypad_device()
		if joy_device >= 0 and Input.is_joy_button_pressed(joy_device, joy_button):
			return 1.0
		for connected_device in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(int(connected_device), joy_button):
				return 1.0
	elif bind_type == "joy_motion":
		var joy_axis: int = int(binding.get("axis", -1))
		var joy_axis_value: float = float(binding.get("axis_value", 0.0))
		if joy_axis < 0 or joy_axis_value == 0.0:
			return 0.0
		var raw_value: float = _get_joy_axis_value(joy_axis)
		var signed_value: float = raw_value * signf(joy_axis_value)
		if signed_value <= 0.0:
			return 0.0
		if not apply_deadzone:
			return clamp(signed_value, 0.0, 1.0)
		var deadzone: float = _get_deadzone_for_joy_axis(joy_axis)
		var max_value: float = _get_max_for_joy_axis(joy_axis)
		if max_value <= deadzone:
			return 0.0
		if signed_value <= deadzone:
			return 0.0
		var t: float = clamp((signed_value - deadzone) / max(max_value - deadzone, 0.001), 0.0, 1.0)
		return lerp(clamp(min_output, 0.0, 1.0), 1.0, t)
	return 0.0


func _get_joy_axis_value(axis: int) -> float:
	var joy_device: int = get_preferred_joypad_device()
	if joy_device >= 0:
		return Input.get_joy_axis(joy_device, axis)
	for connected_device in Input.get_connected_joypads():
		var value: float = Input.get_joy_axis(int(connected_device), axis)
		if abs(value) > 0.0:
			return value
	return 0.0


func _get_deadzone_for_joy_axis(axis: int) -> float:
	if axis == 2 or axis == 3:
		return get_right_stick_deadzone()
	return get_left_stick_deadzone()


func _get_max_for_joy_axis(axis: int) -> float:
	if axis == 2 or axis == 3:
		return get_right_stick_max()
	return get_left_stick_max()


func get_preferred_joypad_device() -> int:
	if preferred_joypad_device >= 0:
		for connected_device in Input.get_connected_joypads():
			if int(connected_device) == preferred_joypad_device:
				return preferred_joypad_device
	if Input.get_connected_joypads().is_empty():
		return -1
	preferred_joypad_device = int(Input.get_connected_joypads()[0])
	return preferred_joypad_device


func _get_bindings_from_action(action_name: StringName) -> Array:
	var bindings: Array = []
	if not InputMap.has_action(action_name):
		return bindings
	var events: Array = InputMap.action_get_events(action_name)
	for ev in events:
		if ev is InputEventKey:
			var key_event: InputEventKey = ev
			var keycode_value: int = int(key_event.keycode)
			if keycode_value == Key.KEY_NONE and int(key_event.physical_keycode) != Key.KEY_NONE:
				keycode_value = int(key_event.physical_keycode)
			if keycode_value != Key.KEY_NONE:
				bindings.append({"type": "key", "keycode": keycode_value})
		elif ev is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = ev
			var button_value: int = int(mouse_event.button_index)
			if button_value > 0:
				bindings.append({"type": "mouse", "button": button_value})
		elif ev is InputEventJoypadButton:
			var joy_button_event: InputEventJoypadButton = ev
			var joy_button_value: int = int(joy_button_event.button_index)
			if joy_button_value >= 0:
				bindings.append({"type": "joy_button", "button": joy_button_value})
		elif ev is InputEventJoypadMotion:
			var joy_motion_event: InputEventJoypadMotion = ev
			var joy_axis_value: int = int(joy_motion_event.axis)
			var joy_axis_sign: float = signf(float(joy_motion_event.axis_value))
			if joy_axis_value >= 0 and joy_axis_sign != 0.0:
				bindings.append({"type": "joy_motion", "axis": joy_axis_value, "axis_value": joy_axis_sign})
	return bindings


func _backfill_missing_project_bindings() -> void:
	if input_bindings.is_empty():
		return
	var changed: bool = false
	for action_entry in InputMap.get_actions():
		var action_name: StringName = StringName(action_entry)
		if _is_input_action_locked(action_name):
			continue
		var existing: Array = get_action_bindings(action_name)
		var defaults: Array = _get_project_default_bindings(action_name)
		if defaults.is_empty():
			continue
		if existing.is_empty():
			input_bindings[action_name] = defaults.duplicate(true)
			_apply_bindings_to_action(action_name, defaults)
			changed = true
			continue
		var current_has_gamepad: bool = false
		for binding in existing:
			if not (binding is Dictionary):
				continue
			if _binding_kind_matches(String((binding as Dictionary).get("type", "")), &"gamepad"):
				current_has_gamepad = true
				break
		if current_has_gamepad:
			continue
		var merged: Array = existing.duplicate(true)
		for binding in defaults:
			if not (binding is Dictionary):
				continue
			var binding_dict: Dictionary = binding
			if _binding_kind_matches(String(binding_dict.get("type", "")), &"gamepad"):
				merged.append(binding_dict)
		if merged.size() != existing.size():
			input_bindings[action_name] = merged
			_apply_bindings_to_action(action_name, merged)
			changed = true
	if changed:
		_save()


func _get_project_default_bindings(action_name: StringName) -> Array:
	var project_setting_name: String = "input/%s" % String(action_name)
	if not ProjectSettings.has_setting(project_setting_name):
		return []
	var value: Variant = ProjectSettings.get_setting(project_setting_name)
	if not (value is Dictionary):
		return []
	var data: Dictionary = value
	var events: Variant = data.get("events", [])
	if not (events is Array):
		return []
	var bindings: Array = []
	for ev in events:
		if ev is InputEventKey:
			var key_event: InputEventKey = ev
			var keycode_value: int = int(key_event.keycode)
			if keycode_value == Key.KEY_NONE and int(key_event.physical_keycode) != Key.KEY_NONE:
				keycode_value = int(key_event.physical_keycode)
			if keycode_value != Key.KEY_NONE:
				bindings.append({"type": "key", "keycode": keycode_value})
		elif ev is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = ev
			var button_value: int = int(mouse_event.button_index)
			if button_value > 0:
				bindings.append({"type": "mouse", "button": button_value})
		elif ev is InputEventJoypadButton:
			var joy_button_event: InputEventJoypadButton = ev
			var joy_button_value: int = int(joy_button_event.button_index)
			if joy_button_value >= 0:
				bindings.append({"type": "joy_button", "button": joy_button_value})
		elif ev is InputEventJoypadMotion:
			var joy_motion_event: InputEventJoypadMotion = ev
			var joy_axis_value: int = int(joy_motion_event.axis)
			var joy_axis_sign: float = signf(float(joy_motion_event.axis_value))
			if joy_axis_value >= 0 and joy_axis_sign != 0.0:
				bindings.append({"type": "joy_motion", "axis": joy_axis_value, "axis_value": joy_axis_sign})
	return bindings


func _migrate_legacy_debug_toggle_binding() -> bool:
	var action_name: StringName = &"debug_toggle"
	if not input_bindings.has(action_name):
		return false
	var bindings: Array = get_action_bindings(action_name)
	var changed: bool = false
	for index: int in range(bindings.size()):
		var binding_value: Variant = bindings[index]
		if not (binding_value is Dictionary):
			continue
		var binding: Dictionary = binding_value
		if String(binding.get("type", "")) != "key":
			continue
		if int(binding.get("keycode", Key.KEY_NONE)) != Key.KEY_TAB:
			continue
		binding["keycode"] = Key.KEY_BACKSLASH
		bindings[index] = binding
		changed = true
	if changed:
		input_bindings[action_name] = bindings
		_apply_bindings_to_action(action_name, bindings)
	return changed


func _is_input_action_locked(action_name: StringName) -> bool:
	if String(action_name).begins_with("ui_"):
		return true
	for locked_action in LOCKED_INPUT_ACTIONS:
		if action_name == locked_action:
			return true
	return false


func _repair_text_input_actions() -> void:
	var text_action_keys: Dictionary = {
		&"ui_text_select_all": [Key.KEY_A],
		&"ui_text_cut": [Key.KEY_X],
		&"ui_text_copy": [Key.KEY_C],
		&"ui_text_paste": [Key.KEY_V],
		&"ui_text_undo": [Key.KEY_Z],
		&"ui_text_redo": [Key.KEY_Y],
		&"ui_unicode_start": [Key.KEY_U]
	}
	for action_name in text_action_keys.keys():
		if not InputMap.has_action(action_name):
			continue
		var blocked_keys: Array = text_action_keys[action_name]
		var events: Array = InputMap.action_get_events(action_name)
		for ev in events:
			if not (ev is InputEventKey):
				continue
			var key_event: InputEventKey = ev
			var keycode_value: int = int(key_event.keycode)
			if keycode_value == Key.KEY_NONE:
				keycode_value = int(key_event.physical_keycode)
			if not blocked_keys.has(keycode_value):
				continue
			var has_command_modifier: bool = key_event.command_or_control_autoremap or key_event.ctrl_pressed or key_event.meta_pressed
			var valid_shortcut: bool = has_command_modifier
			if action_name == &"ui_unicode_start":
				valid_shortcut = key_event.ctrl_pressed and key_event.shift_pressed
			if not valid_shortcut:
				InputMap.action_erase_event(action_name, ev)


# =========================================
# SAVE / LOAD
# =========================================
func _save() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	_write_settings_config(cfg)
	var err: Error = cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("SettingsManager: failed to save settings.cfg: %s" % error_string(err))
	return err


func _write_settings_config(cfg: ConfigFile) -> void:
	cfg.set_value("meta", "schema_version", CONFIG_SCHEMA_VERSION)

	cfg.set_value("display", "resolution_index", resolution_index)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync_enabled", vsync_enabled)
	cfg.set_value("display", "hud_visible", hud_visible)
	cfg.set_value("display", "action_prompts_visible", action_prompts_visible)
	cfg.set_value("display", "fps_counter_visible", fps_counter_visible)

	cfg.set_value("graphics", "ssr", ssr)
	cfg.set_value("graphics", "ssao", ssao)
	cfg.set_value("graphics", "ssil", ssil)
	cfg.set_value("graphics", "sdfgi", sdfgi)
	cfg.set_value("graphics", "shadows", shadows)
	cfg.set_value("graphics", "glow", glow)
	cfg.set_value("graphics", "depth_of_field_enabled", depth_of_field_enabled)
	cfg.set_value("graphics", "render_scale_mode", render_scale_mode)
	cfg.set_value("graphics", "render_scale_ratio", render_scale_ratio)
	cfg.set_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	cfg.set_value("graphics", "shadow_resolution", shadow_resolution)
	cfg.set_value("graphics", "particle_quality", particle_quality)
	cfg.set_value("graphics", "weather_occlusion_enabled", weather_occlusion_enabled)
	cfg.set_value("graphics", "lod_distance_quality", lod_distance_quality)
	cfg.set_value("graphics", "water_displacement_enabled", water_displacement_enabled)
	cfg.set_value("graphics", "water_refraction_enabled", water_refraction_enabled)
	cfg.set_value("graphics", "water_normal_maps_enabled", water_normal_maps_enabled)
	cfg.set_value("graphics", "water_depth_effects_enabled", water_depth_effects_enabled)

	cfg.set_value("audio", "master_percent", master_percent)
	cfg.set_value("audio", "music_db", music_db)
	cfg.set_value("audio", "sfx_db", sfx_db)
	cfg.set_value("audio", "ui_db", ui_db)
	cfg.set_value("audio", "voice_db", voice_db)

	cfg.set_value("camera", "far_cutoff", camera_far_cutoff)
	cfg.set_value("camera", "default_fov", camera_default_fov)
	cfg.set_value("camera", "dolly_enabled", camera_dolly_enabled)
	cfg.set_value("camera", "target_lookahead_enabled", camera_target_lookahead_enabled)
	cfg.set_value("camera", "target_lookahead_amount", camera_target_lookahead_amount)
	cfg.set_value("camera", "auto_follow_enabled", camera_auto_follow_enabled)
	cfg.set_value("camera", "auto_follow_controller_only", camera_auto_follow_controller_only)
	cfg.set_value("camera", "auto_follow_sensitivity", camera_auto_follow_sensitivity)
	cfg.set_value("camera", "auto_follow_interrupt_delay", camera_auto_follow_interrupt_delay)
	cfg.set_value("camera", "auto_follow_deadzone_deg", camera_auto_follow_deadzone_deg)
	cfg.set_value("camera", "auto_follow_max_deviation_deg", camera_auto_follow_max_deviation_deg)
	cfg.set_value("camera", "auto_follow_vertical_enabled", camera_auto_follow_vertical_enabled)
	cfg.set_value("camera", "auto_follow_vertical_max_tilt", camera_auto_follow_vertical_max_tilt)
	cfg.set_value("camera", "auto_follow_level_pitch_deg", camera_auto_follow_level_pitch_deg)
	cfg.set_value("camera", "auto_follow_speed_ramp", camera_auto_follow_speed_ramp)
	cfg.set_value("camera", "auto_follow_slope_suppression", camera_auto_follow_slope_suppression)
	cfg.set_value("camera", "auto_follow_slope_threshold_deg", camera_auto_follow_slope_threshold_deg)
	cfg.set_value("controls", "mouse_invert_y", mouse_invert_y)
	cfg.set_value("controls", "mouse_look_sensitivity", mouse_look_sensitivity)
	cfg.set_value("controls", "right_stick_invert_y", right_stick_invert_y)
	cfg.set_value("controls", "left_stick_deadzone_percent", left_stick_deadzone_percent)
	cfg.set_value("controls", "left_stick_max_percent", left_stick_max_percent)
	cfg.set_value("controls", "right_stick_deadzone_percent", right_stick_deadzone_percent)
	cfg.set_value("controls", "right_stick_max_percent", right_stick_max_percent)
	cfg.set_value("controls", "right_stick_sensitivity_percent", right_stick_sensitivity_percent)
	cfg.set_value("controls", "walk_stick_zone_percent", walk_stick_zone_percent)
	cfg.set_value("controls", "trick_control_stick", trick_control_stick)
	cfg.set_value("controls", "left_stick_trick_movement", left_stick_trick_movement)
	cfg.set_value("controls", "trick_rotation_acceleration_percent", trick_rotation_acceleration_percent)
	cfg.set_value("gameplay", "homing_targeting_mode", homing_targeting_mode)
	cfg.set_value("gameplay", "homing_mouse_targeting_mode", homing_mouse_targeting_mode)
	cfg.set_value("gameplay", "homing_targeting_separate_by_device", homing_targeting_separate_by_device)
	cfg.set_value("gameplay", "homing_camera_radius", homing_camera_radius)
	cfg.set_value("gameplay", "camera_follow_smoothing", camera_follow_smoothing)
	cfg.set_value("gameplay", "center_reticle_enabled", center_reticle_enabled)
	cfg.set_value("gameplay", "center_reticle_scale", center_reticle_scale)
	cfg.set_value("gameplay", "center_reticle_opacity", center_reticle_opacity)
	cfg.set_value("gameplay", "center_reticle_color", center_reticle_color)
	cfg.set_value("gameplay", "reticle_vertical_offset", reticle_vertical_offset)
	cfg.set_value("gameplay", "combo_system_enabled", combo_system_enabled)
	cfg.set_value("gameplay", "remember_emote_page", remember_emote_page)
	cfg.set_value("gameplay", "emote_last_page", emote_last_page)
	cfg.set_value("gameplay", "lightspeed_dash_targeting_mode", lightspeed_dash_targeting_mode)
	cfg.set_value("gameplay", "chosen_character_id", chosen_character_id)
	cfg.set_value("gameplay", "chosen_buddy_character_id", chosen_buddy_character_id)
	cfg.set_value("gameplay", "buddy_active", buddy_active)
	cfg.set_value("gameplay", "use_character_colors", use_character_colors)
	cfg.set_value("gameplay", "character_primary_color", character_primary_color)
	cfg.set_value("gameplay", "character_secondary_color", character_secondary_color)
	cfg.set_value("gameplay", "character_trail_color", character_trail_color)
	cfg.set_value("gameplay", "use_character_colors_offline", use_character_colors_offline)
	cfg.set_value("gameplay", "offline_primary_color", offline_primary_color)
	cfg.set_value("gameplay", "offline_secondary_color", offline_secondary_color)
	cfg.set_value("gameplay", "offline_trail_color", offline_trail_color)
	cfg.set_value("diagnostics", "level_load_logging_enabled", level_load_logging_enabled)
	cfg.set_value("race", "dnf_timer_sec", race_dnf_timer_sec)
	cfg.set_value("race", "join_timer_sec", race_join_timer_sec)
	cfg.set_value("race", "ghost_enabled", race_ghost_enabled)
	cfg.set_value("race", "multiple_ghosts_enabled", race_multiple_ghosts_enabled)
	cfg.set_value("race", "ghost_count", race_ghost_count)
	cfg.set_value("race", "record_ghost_data", race_record_ghost_data)
	cfg.set_value("race", "ghost_recording_rate", race_ghost_recording_rate)
	cfg.set_value("race", "ghost_playback_rate", race_ghost_playback_rate)
	cfg.set_value("race", "selected_ghost_path", race_selected_ghost_path)

	cfg.set_value("online", "player_name", online_player_name)
	cfg.set_value("online", "address", online_address)
	cfg.set_value("online", "invite_code", online_invite_code)
	cfg.set_value("online", "connection_mode", online_connection_mode)
	cfg.set_value("online", "port", online_port)
	cfg.set_value("online", "max_players", online_max_players)
	cfg.set_value("online", "name_color", online_name_color)
	cfg.set_value("online", "primary_color", online_primary_color)
	cfg.set_value("online", "secondary_color", online_secondary_color)
	cfg.set_value("online", "trail_color", online_trail_color)
	cfg.set_value("online", "player_tracking_mode", player_tracking_mode)

	for action_key in input_bindings.keys():
		if _is_input_action_locked(StringName(action_key)):
			continue
		var action_name: String = String(action_key)
		var keycodes: Array = input_bindings[action_key]
		cfg.set_value("input", action_name, keycodes)



func _is_config_value_compatible(value: Variant, default_value: Variant) -> bool:
	if default_value is bool:
		return value is bool
	if default_value is int:
		return (value is int or value is float) and is_finite(float(value))
	if default_value is float:
		return (value is int or value is float) and is_finite(float(value))
	if default_value is String:
		return value is String
	if default_value is StringName:
		return value is StringName or value is String
	if default_value is Color:
		if not (value is Color):
			return false
		var color_value: Color = value
		return is_finite(color_value.r) and is_finite(color_value.g) and is_finite(color_value.b) and is_finite(color_value.a)
	if default_value is Vector2:
		return value is Vector2
	if default_value is Vector2i:
		return value is Vector2i
	if default_value is Vector3:
		return value is Vector3
	if default_value is Vector3i:
		return value is Vector3i
	if default_value is Array:
		return value is Array
	if default_value is Dictionary:
		return value is Dictionary
	return typeof(value) == typeof(default_value)


func _sanitize_loaded_config(cfg: ConfigFile, defaults: ConfigFile) -> bool:
	var changed: bool = false
	for section: String in defaults.get_sections():
		for key: String in defaults.get_section_keys(section):
			if not cfg.has_section_key(section, key):
				cfg.set_value(section, key, defaults.get_value(section, key))
				changed = true
				continue
			var default_value: Variant = defaults.get_value(section, key)
			var loaded_value: Variant = cfg.get_value(section, key)
			if not _is_config_value_compatible(loaded_value, default_value):
				cfg.set_value(section, key, default_value)
				changed = true
	if cfg.has_section("input"):
		for key: String in cfg.get_section_keys("input"):
			var binding_value: Variant = cfg.get_value("input", key)
			if not (binding_value is Array or binding_value is int):
				cfg.erase_section_key("input", key)
				changed = true
	return changed


func _get_numeric_config_value(cfg: ConfigFile, section: String, key: String, default_value: Variant) -> Variant:
	if not cfg.has_section_key(section, key):
		return default_value
	var value: Variant = cfg.get_value(section, key)
	if (value is int or value is float) and is_finite(float(value)):
		return value
	return default_value


func _get_config_value(cfg: ConfigFile, section: String, key: String, default_value: Variant) -> Variant:
	var value: Variant = null
	if cfg.has_section_key(section, key):
		value = cfg.get_value(section, key)
		if default_value == null or _is_config_value_compatible(value, default_value):
			return value
	var legacy_key: String = key.replace("colors", "colo" + "urs").replace("color", "colo" + "ur")
	if legacy_key != key and cfg.has_section_key(section, legacy_key):
		value = cfg.get_value(section, legacy_key)
		if default_value == null or _is_config_value_compatible(value, default_value):
			return value
	return default_value


func _get_packaged_defaults() -> ConfigFile:
	var defaults: ConfigFile = ConfigFile.new()
	var err: Error = defaults.load(DEFAULT_CONFIG_PATH)
	if err != OK:
		push_warning("SettingsManager: failed to load packaged defaults: %s" % error_string(err))
		_write_settings_config(defaults)
	defaults.set_value("meta", "schema_version", CONFIG_SCHEMA_VERSION)
	defaults.set_value("display", "resolution_index", _get_monitor_resolution_index())
	return defaults


func _replace_with_packaged_defaults() -> Error:
	var defaults: ConfigFile = _get_packaged_defaults()
	var err: Error = defaults.save(CONFIG_PATH)
	if err != OK:
		push_warning("SettingsManager: failed to install default settings.cfg: %s" % error_string(err))
	return err


func _migrate_legacy_config_values(cfg: ConfigFile) -> void:
	if not cfg.has_section_key("audio", "master_percent") and cfg.has_section_key("audio", "master_db"):
		cfg.set_value("audio", "master_percent", cfg.get_value("audio", "master_db"))
	if not cfg.has_section_key("controls", "trick_rotation_acceleration_percent") and cfg.has_section_key("controls", "trick_rotation_sensitivity_percent"):
		cfg.set_value("controls", "trick_rotation_acceleration_percent", cfg.get_value("controls", "trick_rotation_sensitivity_percent"))
	for old_action: StringName in INPUT_ACTION_NAME_MIGRATIONS:
		var current_action: StringName = INPUT_ACTION_NAME_MIGRATIONS[old_action]
		if cfg.has_section_key("input", String(old_action)) and not cfg.has_section_key("input", String(current_action)):
			cfg.set_value("input", String(current_action), cfg.get_value("input", String(old_action)))
	for section: String in cfg.get_sections():
		for key: String in cfg.get_section_keys(section):
			if not key.contains("colour"):
				continue
			var current_key: String = key.replace("colours", "colors").replace("colour", "color")
			if not cfg.has_section_key(section, current_key):
				cfg.set_value(section, current_key, cfg.get_value(section, key))
	_migrate_config_key(cfg, "gameplay", "use_character_colors_offline", "gameplay", "use_character_colors")
	_migrate_config_key(cfg, "gameplay", "offline_primary_color", "gameplay", "character_primary_color")
	_migrate_config_key(cfg, "gameplay", "offline_secondary_color", "gameplay", "character_secondary_color")
	_migrate_config_key(cfg, "gameplay", "offline_trail_color", "gameplay", "character_trail_color")
	_migrate_config_key(cfg, "online", "primary_color", "gameplay", "character_primary_color")
	_migrate_config_key(cfg, "online", "secondary_color", "gameplay", "character_secondary_color")
	_migrate_config_key(cfg, "online", "trail_color", "gameplay", "character_trail_color")


func _migrate_config_key(cfg: ConfigFile, source_section: String, source_key: String, target_section: String, target_key: String) -> void:
	if cfg.has_section_key(target_section, target_key) or not cfg.has_section_key(source_section, source_key):
		return
	cfg.set_value(target_section, target_key, cfg.get_value(source_section, source_key))


func _load() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(CONFIG_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("SettingsManager: replacing invalid settings.cfg: %s" % error_string(err))
		if _replace_with_packaged_defaults() != OK:
			return
		err = cfg.load(CONFIG_PATH)
		if err != OK:
			return
	var defaults: ConfigFile = _get_packaged_defaults()
	_migrate_legacy_config_values(cfg)
	_sanitize_loaded_config(cfg, defaults)

	resolution_index = int(cfg.get_value("display", "resolution_index", resolution_index))
	resolution_index = clampi(resolution_index, 0, _resolutions.size() - 1)
	fullscreen       = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync_enabled    = bool(cfg.get_value("display", "vsync_enabled", vsync_enabled))
	hud_visible      = bool(cfg.get_value("display", "hud_visible", hud_visible))
	action_prompts_visible = bool(cfg.get_value("display", "action_prompts_visible", true))
	fps_counter_visible = bool(cfg.get_value("display", "fps_counter_visible", fps_counter_visible))

	ssr      = bool(cfg.get_value("graphics", "ssr", ssr))
	ssao     = bool(cfg.get_value("graphics", "ssao", ssao))
	ssil     = bool(cfg.get_value("graphics", "ssil", ssil))
	sdfgi    = bool(cfg.get_value("graphics", "sdfgi", sdfgi))
	shadows  = bool(cfg.get_value("graphics", "shadows", shadows))
	glow     = bool(cfg.get_value("graphics", "glow", glow))
	depth_of_field_enabled = bool(cfg.get_value("graphics", "depth_of_field_enabled", depth_of_field_enabled))
	render_scale_mode = clampi(int(cfg.get_value("graphics", "render_scale_mode", render_scale_mode)), RENDER_SCALE_MODE_DIRECT, RENDER_SCALE_MODE_FSR)
	render_scale_ratio = clampf(float(cfg.get_value("graphics", "render_scale_ratio", render_scale_ratio)), RENDER_SCALE_HIGH_PERFORMANCE, RENDER_SCALE_NATIVE)
	volumetric_fog_enabled = bool(cfg.get_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled))
	shadow_resolution = clampi(int(cfg.get_value("graphics", "shadow_resolution", shadow_resolution)), SHADOW_RESOLUTION_LOW, SHADOW_RESOLUTION_ULTRA)
	particle_quality = clampi(int(cfg.get_value("graphics", "particle_quality", particle_quality)), PARTICLE_QUALITY_LOW, PARTICLE_QUALITY_ULTRA)
	weather_occlusion_enabled = bool(cfg.get_value("graphics", "weather_occlusion_enabled", weather_occlusion_enabled))
	lod_distance_quality = clampi(int(cfg.get_value("graphics", "lod_distance_quality", lod_distance_quality)), LOD_DISTANCE_LOW, LOD_DISTANCE_JUICED)
	water_displacement_enabled = bool(cfg.get_value("graphics", "water_displacement_enabled", water_displacement_enabled))
	water_refraction_enabled = bool(cfg.get_value("graphics", "water_refraction_enabled", water_refraction_enabled))
	water_normal_maps_enabled = bool(cfg.get_value("graphics", "water_normal_maps_enabled", water_normal_maps_enabled))
	water_depth_effects_enabled = bool(cfg.get_value("graphics", "water_depth_effects_enabled", water_depth_effects_enabled))

	var legacy_master: Variant = cfg.get_value("audio", "master_percent", null)
	if legacy_master == null:
		legacy_master = _get_numeric_config_value(cfg, "audio", "master_db", master_percent)
	master_percent = clamp(float(legacy_master), 0.0, 100.0)
	music_db  = float(cfg.get_value("audio", "music_db", music_db))
	sfx_db    = float(cfg.get_value("audio", "sfx_db", sfx_db))
	ui_db     = float(cfg.get_value("audio", "ui_db", ui_db))
	voice_db  = float(cfg.get_value("audio", "voice_db", voice_db))

	camera_far_cutoff = float(cfg.get_value("camera", "far_cutoff", camera_far_cutoff))
	camera_far_cutoff = max(camera_far_cutoff, 1.0)
	camera_default_fov = clamp(float(cfg.get_value("camera", "default_fov", camera_default_fov)), CAMERA_FOV_MIN, CAMERA_FOV_MAX)
	camera_dolly_enabled = bool(cfg.get_value("camera", "dolly_enabled", camera_dolly_enabled))
	camera_target_lookahead_enabled = bool(cfg.get_value("camera", "target_lookahead_enabled", camera_target_lookahead_enabled))
	camera_target_lookahead_amount = float(cfg.get_value("camera", "target_lookahead_amount", camera_target_lookahead_amount))
	camera_auto_follow_enabled = bool(cfg.get_value("camera", "auto_follow_enabled", camera_auto_follow_enabled))
	camera_auto_follow_controller_only = bool(cfg.get_value("camera", "auto_follow_controller_only", camera_auto_follow_controller_only))
	camera_auto_follow_sensitivity = float(cfg.get_value("camera", "auto_follow_sensitivity", camera_auto_follow_sensitivity))
	camera_auto_follow_interrupt_delay = float(cfg.get_value("camera", "auto_follow_interrupt_delay", camera_auto_follow_interrupt_delay))
	camera_auto_follow_deadzone_deg = float(cfg.get_value("camera", "auto_follow_deadzone_deg", camera_auto_follow_deadzone_deg))
	camera_auto_follow_max_deviation_deg = float(cfg.get_value("camera", "auto_follow_max_deviation_deg", camera_auto_follow_max_deviation_deg))
	camera_auto_follow_vertical_enabled = bool(cfg.get_value("camera", "auto_follow_vertical_enabled", camera_auto_follow_vertical_enabled))
	camera_auto_follow_vertical_max_tilt = float(cfg.get_value("camera", "auto_follow_vertical_max_tilt", camera_auto_follow_vertical_max_tilt))
	camera_auto_follow_level_pitch_deg = float(cfg.get_value("camera", "auto_follow_level_pitch_deg", camera_auto_follow_level_pitch_deg))
	camera_auto_follow_speed_ramp = float(cfg.get_value("camera", "auto_follow_speed_ramp", camera_auto_follow_speed_ramp))
	camera_auto_follow_slope_suppression = float(cfg.get_value("camera", "auto_follow_slope_suppression", camera_auto_follow_slope_suppression))
	camera_auto_follow_slope_threshold_deg = float(cfg.get_value("camera", "auto_follow_slope_threshold_deg", camera_auto_follow_slope_threshold_deg))
	mouse_invert_y = bool(cfg.get_value("controls", "mouse_invert_y", mouse_invert_y))
	mouse_look_sensitivity = float(cfg.get_value("controls", "mouse_look_sensitivity", mouse_look_sensitivity))
	right_stick_invert_y = bool(cfg.get_value("controls", "right_stick_invert_y", right_stick_invert_y))
	left_stick_deadzone_percent = float(cfg.get_value("controls", "left_stick_deadzone_percent", left_stick_deadzone_percent))
	left_stick_max_percent = float(cfg.get_value("controls", "left_stick_max_percent", left_stick_max_percent))
	right_stick_deadzone_percent = float(cfg.get_value("controls", "right_stick_deadzone_percent", right_stick_deadzone_percent))
	right_stick_max_percent = float(cfg.get_value("controls", "right_stick_max_percent", right_stick_max_percent))
	right_stick_sensitivity_percent = float(cfg.get_value("controls", "right_stick_sensitivity_percent", right_stick_sensitivity_percent))
	walk_stick_zone_percent = float(cfg.get_value("controls", "walk_stick_zone_percent", walk_stick_zone_percent))
	trick_control_stick = int(cfg.get_value("controls", "trick_control_stick", trick_control_stick))
	left_stick_trick_movement = int(cfg.get_value("controls", "left_stick_trick_movement", left_stick_trick_movement))
	if cfg.has_section_key("controls", "trick_rotation_acceleration_percent"):
		trick_rotation_acceleration_percent = float(cfg.get_value("controls", "trick_rotation_acceleration_percent"))
	else:
		trick_rotation_acceleration_percent = float(_get_numeric_config_value(cfg, "controls", "trick_rotation_sensitivity_percent", trick_rotation_acceleration_percent))
	homing_targeting_mode = int(cfg.get_value("gameplay", "homing_targeting_mode", homing_targeting_mode))
	homing_mouse_targeting_mode = int(cfg.get_value("gameplay", "homing_mouse_targeting_mode", homing_mouse_targeting_mode))
	homing_targeting_separate_by_device = bool(cfg.get_value("gameplay", "homing_targeting_separate_by_device", homing_targeting_separate_by_device))
	homing_camera_radius = float(cfg.get_value("gameplay", "homing_camera_radius", homing_camera_radius))
	camera_follow_smoothing = float(cfg.get_value("gameplay", "camera_follow_smoothing", camera_follow_smoothing))
	center_reticle_enabled = bool(cfg.get_value("gameplay", "center_reticle_enabled", center_reticle_enabled))
	center_reticle_scale = float(cfg.get_value("gameplay", "center_reticle_scale", center_reticle_scale))
	center_reticle_opacity = float(cfg.get_value("gameplay", "center_reticle_opacity", center_reticle_opacity))
	center_reticle_color = Color(_get_config_value(cfg, "gameplay", "center_reticle_color", center_reticle_color))
	reticle_vertical_offset = float(cfg.get_value("gameplay", "reticle_vertical_offset", reticle_vertical_offset))
	combo_system_enabled = bool(cfg.get_value("gameplay", "combo_system_enabled", combo_system_enabled))
	remember_emote_page = bool(cfg.get_value("gameplay", "remember_emote_page", remember_emote_page))
	emote_last_page = maxi(int(cfg.get_value("gameplay", "emote_last_page", emote_last_page)), 0)
	lightspeed_dash_targeting_mode = int(cfg.get_value("gameplay", "lightspeed_dash_targeting_mode", lightspeed_dash_targeting_mode))
	set_chosen_character_id(String(cfg.get_value("gameplay", "chosen_character_id", chosen_character_id)))
	set_chosen_buddy_character_id(String(cfg.get_value("gameplay", "chosen_buddy_character_id", chosen_buddy_character_id)))
	set_buddy_active(bool(cfg.get_value("gameplay", "buddy_active", buddy_active)))
	level_load_logging_enabled = bool(cfg.get_value("diagnostics", "level_load_logging_enabled", level_load_logging_enabled))
	var use_character_colors_value = _get_config_value(cfg, "gameplay", "use_character_colors", null)
	if not (use_character_colors_value is bool):
		use_character_colors_value = _get_config_value(cfg, "gameplay", "use_character_colors_offline", use_character_colors)
	if not (use_character_colors_value is bool):
		use_character_colors_value = use_character_colors
	set_use_character_colors(bool(use_character_colors_value))

	var character_primary_value = _get_config_value(cfg, "gameplay", "character_primary_color", null)
	if character_primary_value == null:
		character_primary_value = _get_config_value(cfg, "gameplay", "offline_primary_color", null)
	if character_primary_value == null:
		character_primary_value = _get_config_value(cfg, "online", "primary_color", character_primary_color)
	if character_primary_value is Color:
		set_character_primary_color(character_primary_value)

	var character_secondary_value = _get_config_value(cfg, "gameplay", "character_secondary_color", null)
	if character_secondary_value == null:
		character_secondary_value = _get_config_value(cfg, "gameplay", "offline_secondary_color", null)
	if character_secondary_value == null:
		character_secondary_value = _get_config_value(cfg, "online", "secondary_color", character_secondary_color)
	if character_secondary_value is Color:
		set_character_secondary_color(character_secondary_value)

	var character_trail_value = _get_config_value(cfg, "gameplay", "character_trail_color", null)
	if character_trail_value == null:
		character_trail_value = _get_config_value(cfg, "gameplay", "offline_trail_color", null)
	if character_trail_value == null:
		character_trail_value = _get_config_value(cfg, "online", "trail_color", character_trail_color)
	if character_trail_value is Color:
		set_character_trail_color(character_trail_value)
	homing_targeting_mode = clamp(homing_targeting_mode, HOMING_TARGETING_MOVEMENT, HOMING_TARGETING_HYBRID)
	homing_mouse_targeting_mode = clamp(homing_mouse_targeting_mode, HOMING_TARGETING_MOVEMENT, HOMING_TARGETING_HYBRID)
	homing_camera_radius = max(homing_camera_radius, 0.0)
	camera_follow_smoothing = max(camera_follow_smoothing, 0.0)
	camera_dolly_enabled = bool(camera_dolly_enabled)
	camera_target_lookahead_enabled = bool(camera_target_lookahead_enabled)
	camera_target_lookahead_amount = clamp(camera_target_lookahead_amount, 0.0, 100.0)
	camera_auto_follow_enabled = bool(camera_auto_follow_enabled)
	camera_auto_follow_sensitivity = max(camera_auto_follow_sensitivity, 0.0)
	camera_auto_follow_interrupt_delay = max(camera_auto_follow_interrupt_delay, 0.0)
	camera_auto_follow_deadzone_deg = clamp(camera_auto_follow_deadzone_deg, 0.0, 180.0)
	camera_auto_follow_max_deviation_deg = clamp(camera_auto_follow_max_deviation_deg, camera_auto_follow_deadzone_deg, 180.0)
	camera_auto_follow_vertical_max_tilt = clamp(camera_auto_follow_vertical_max_tilt, 0.0, 90.0)
	camera_auto_follow_level_pitch_deg = clamp(camera_auto_follow_level_pitch_deg, -89.0, 89.0)
	camera_auto_follow_speed_ramp = max(camera_auto_follow_speed_ramp, 0.0)
	camera_auto_follow_slope_suppression = clamp(camera_auto_follow_slope_suppression, 0.0, 1.0)
	camera_auto_follow_slope_threshold_deg = clamp(camera_auto_follow_slope_threshold_deg, 0.0, 90.0)
	center_reticle_scale = max(center_reticle_scale, 0.01)
	center_reticle_opacity = clamp(center_reticle_opacity, 0.0, 1.0)
	mouse_look_sensitivity = clamp(mouse_look_sensitivity, MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	left_stick_deadzone_percent = clamp(left_stick_deadzone_percent, 0.0, 100.0)
	left_stick_max_percent = clamp(left_stick_max_percent, left_stick_deadzone_percent, 100.0)
	right_stick_deadzone_percent = clamp(right_stick_deadzone_percent, 0.0, 100.0)
	right_stick_max_percent = clamp(right_stick_max_percent, right_stick_deadzone_percent, 100.0)
	right_stick_sensitivity_percent = clamp(right_stick_sensitivity_percent, 700.0, 3000.0)
	walk_stick_zone_percent = clamp(walk_stick_zone_percent, 0.0, 100.0)
	trick_control_stick = clampi(trick_control_stick, TRICK_CONTROL_STICK_LEFT, TRICK_CONTROL_STICK_RIGHT)
	left_stick_trick_movement = clampi(
		left_stick_trick_movement,
		LEFT_STICK_TRICK_MOVEMENT_PRESERVE_MOMENTUM,
		LEFT_STICK_TRICK_MOVEMENT_LAST_INPUT
	)
	trick_rotation_acceleration_percent = clamp(trick_rotation_acceleration_percent, 50.0, 300.0)
	reticle_vertical_offset = clamp(reticle_vertical_offset, 0.0, 100.0)
	race_dnf_timer_sec = clamp(float(cfg.get_value("race", "dnf_timer_sec", race_dnf_timer_sec)), 30.0, 300.0)
	race_join_timer_sec = clamp(float(cfg.get_value("race", "join_timer_sec", race_join_timer_sec)), 5.0, 120.0)
	race_ghost_enabled = bool(cfg.get_value("race", "ghost_enabled", race_ghost_enabled))
	race_multiple_ghosts_enabled = bool(cfg.get_value("race", "multiple_ghosts_enabled", race_multiple_ghosts_enabled))
	race_ghost_count = clampi(int(cfg.get_value("race", "ghost_count", race_ghost_count)), MIN_RACE_GHOST_COUNT, MAX_RACE_GHOST_COUNT)
	race_record_ghost_data = bool(cfg.get_value("race", "record_ghost_data", race_record_ghost_data))
	race_ghost_recording_rate = normalize_ghost_recording_rate(int(cfg.get_value("race", "ghost_recording_rate", race_ghost_recording_rate)))
	race_ghost_playback_rate = normalize_ghost_recording_rate(int(cfg.get_value("race", "ghost_playback_rate", race_ghost_playback_rate)))
	race_selected_ghost_path = String(cfg.get_value("race", "selected_ghost_path", race_selected_ghost_path))

	online_player_name = String(cfg.get_value("online", "player_name", online_player_name))
	online_address = String(cfg.get_value("online", "address", online_address))
	online_invite_code = String(cfg.get_value("online", "invite_code", online_invite_code))
	online_connection_mode = clampi(int(cfg.get_value("online", "connection_mode", online_connection_mode)), 0, 1)
	online_port = clampi(int(cfg.get_value("online", "port", online_port)), 1, 65535)
	online_max_players = max(int(cfg.get_value("online", "max_players", online_max_players)), 1)
	online_name_color = Color(_get_config_value(cfg, "online", "name_color", online_name_color))
	online_primary_color = Color(_get_config_value(cfg, "online", "primary_color", online_primary_color))
	online_secondary_color = Color(_get_config_value(cfg, "online", "secondary_color", online_secondary_color))
	online_trail_color = Color(_get_config_value(cfg, "online", "trail_color", online_trail_color))
	player_tracking_mode = clampi(int(cfg.get_value("online", "player_tracking_mode", player_tracking_mode)), PLAYER_TRACKING_MODE_FULL, PLAYER_TRACKING_MODE_OFF)

	input_bindings.clear()
	if cfg.has_section("input"):
		var action_keys: Array = cfg.get_section_keys("input")
		for action_key in action_keys:
			var saved_action_name: StringName = StringName(action_key)
			var action_name: StringName = StringName(INPUT_ACTION_NAME_MIGRATIONS.get(saved_action_name, saved_action_name))
			if saved_action_name != action_name and cfg.has_section_key("input", String(action_name)):
				continue
			if _is_input_action_locked(action_name):
				continue
			var keycodes_value: Variant = cfg.get_value("input", action_key, [])
			var bindings: Array = []
			if keycodes_value is Array:
				var saved_list: Array = keycodes_value
				for entry in saved_list:
					if entry is Dictionary:
						var entry_dict: Dictionary = entry
						var bind_type: String = String(entry_dict.get("type", ""))
						if bind_type == "key":
							var raw_keycode: Variant = entry_dict.get("keycode", Key.KEY_NONE)
							if not (raw_keycode is int or raw_keycode is float):
								continue
							var keycode_value: int = int(raw_keycode)
							if keycode_value != Key.KEY_NONE:
								bindings.append({"type": "key", "keycode": keycode_value})
						elif bind_type == "mouse":
							var raw_mouse_button: Variant = entry_dict.get("button", 0)
							if not (raw_mouse_button is int or raw_mouse_button is float):
								continue
							var button_value: int = int(raw_mouse_button)
							if button_value > 0:
								bindings.append({"type": "mouse", "button": button_value})
						elif bind_type == "joy_button":
							var raw_joy_button: Variant = entry_dict.get("button", -1)
							if not (raw_joy_button is int or raw_joy_button is float):
								continue
							var joy_button_value: int = int(raw_joy_button)
							if joy_button_value >= 0:
								bindings.append({"type": "joy_button", "button": joy_button_value})
						elif bind_type == "joy_motion":
							var raw_joy_axis: Variant = entry_dict.get("axis", -1)
							var raw_joy_axis_value: Variant = entry_dict.get("axis_value", 0.0)
							if not (raw_joy_axis is int or raw_joy_axis is float):
								continue
							if not (raw_joy_axis_value is int or raw_joy_axis_value is float):
								continue
							var joy_axis_value: int = int(raw_joy_axis)
							var joy_axis_sign: float = signf(float(raw_joy_axis_value))
							if joy_axis_value >= 0 and joy_axis_sign != 0.0:
								bindings.append({"type": "joy_motion", "axis": joy_axis_value, "axis_value": joy_axis_sign})
					elif entry is int or entry is float:
						var keycode_fallback: int = int(entry)
						if keycode_fallback != Key.KEY_NONE:
							bindings.append({"type": "key", "keycode": keycode_fallback})
			elif keycodes_value is int or keycodes_value is float:
				var keycode_single: int = int(keycodes_value)
				if keycode_single != Key.KEY_NONE:
					bindings.append({"type": "key", "keycode": keycode_single})
			input_bindings[action_name] = bindings
			_apply_bindings_to_action(action_name, bindings)

	_migrate_legacy_debug_toggle_binding()
	_backfill_missing_project_bindings()
	_save()


func save_now() -> void:
	_save()


func repair_settings_file() -> Error:
	return _save()

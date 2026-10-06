extends Control
class_name HUDMusicTrackDisplay

const NOTIFICATION_ENTRY_SCENE_PATH: String = "res://LS5Framework/Scenes/HUD/HUDNotificationEntry.tscn"
const MUSIC_ICON_PATH: String = "res://LS5Framework/Images/UI/Music_Note.png"
const MAXIMUM_NOTIFICATION_STACK_SIZE: int = 3

static var _notification_entry_scene: PackedScene = null

## Maximum number of notifications visible in the top-right stack.
@export_range(1, 3, 1) var maximum_visible_notifications: int = 3
## Default time a general notification remains visible.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var default_notification_duration: float = 4.0
## Time a music notification remains visible after entering.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var music_notification_duration: float = 4.0
## Music-note texture used for track notifications.
@export var music_icon_texture: Texture2D = null

@export_group("Layout")
## Distance between the notification stack and the top edge.
@export_range(0.0, 500.0, 1.0, "or_greater", "suffix:px") var top_margin: float = 20.0
## Distance between the notification stack and the right edge.
@export_range(0.0, 500.0, 1.0, "or_greater", "suffix:px") var right_margin: float = 20.0
## Minimum width used by notification frames.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px") var minimum_panel_width: float = 340.0
## Maximum width used by notification frames before text is truncated.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px") var maximum_panel_width: float = 720.0

@export_group("Character Colors")
## Amount notification text and icons are lightened from the primary frame color.
@export_range(0.0, 1.0, 0.01) var foreground_lighten_amount: float = 0.35

## Arranges active notification entries in the top-right stack.
@onready var _notification_stack: VBoxContainer = $NotificationStack

var _music_controller: MusicController = null
var _current_stream: AudioStream = null
var _controller_scan_remaining: float = 0.0
var _primary_color: Color = Color.WHITE
var _secondary_color: Color = Color(0.7, 0.85, 1.0, 1.0)
var _entries: Array[HUDNotificationEntry] = []
var _keyed_entries: Dictionary = {}
var _shutting_down: bool = false


func _ready() -> void:
	_shutting_down = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self)
	add_to_group("HUDNotificationStack")
	if not resized.is_connected(_update_stack_layout):
		resized.connect(_update_stack_layout)
	_update_stack_layout()
	call_deferred("_refresh_music_controller", true)


func _exit_tree() -> void:
	_shutting_down = true
	_disconnect_music_controller()
	_entries.clear()
	_keyed_entries.clear()


func _process(delta: float) -> void:
	if _shutting_down:
		return
	_controller_scan_remaining = max(_controller_scan_remaining - max(delta, 0.0), 0.0)
	if _controller_scan_remaining <= 0.0:
		_controller_scan_remaining = 0.5
		_refresh_music_controller(false)


static func post_notification(
		tree: SceneTree,
		title: String,
		detail: String = "",
		icon_texture: Texture2D = null,
		duration: float = -1.0,
		key: StringName = &""
	) -> bool:
	if tree == null:
		return false
	var posted: bool = false
	for node: Node in tree.get_nodes_in_group("HUDNotificationStack"):
		if node is HUDMusicTrackDisplay:
			var display: HUDMusicTrackDisplay = node as HUDMusicTrackDisplay
			if not display.can_accept_notifications():
				continue
			var entry: HUDNotificationEntry = display.show_notification(
				title,
				detail,
				icon_texture,
				duration,
				key
			)
			posted = posted or entry != null
	return posted


static func dismiss_posted_notification(tree: SceneTree, key: StringName) -> void:
	if tree == null or key == &"":
		return
	for node: Node in tree.get_nodes_in_group("HUDNotificationStack"):
		if node is HUDMusicTrackDisplay:
			var display: HUDMusicTrackDisplay = node as HUDMusicTrackDisplay
			if display.can_accept_notifications():
				display.dismiss_notification(key)


func can_accept_notifications() -> bool:
	return (
		not _shutting_down
		and not is_queued_for_deletion()
		and is_inside_tree()
		and is_node_ready()
		and is_instance_valid(_notification_stack)
		and _notification_stack.is_inside_tree()
	)


func show_notification(
		title: String,
		detail: String = "",
		icon_texture: Texture2D = null,
		duration: float = -1.0,
		key: StringName = &"",
		bpm: float = 0.0,
		playback_position_provider: Callable = Callable(),
		wobble_icon: bool = false
	) -> HUDNotificationEntry:
	if not can_accept_notifications():
		return null
	var clean_title: String = title.strip_edges()
	if clean_title == "":
		return null
	_prune_entries()
	var hold_duration: float = duration
	if hold_duration < 0.0:
		hold_duration = default_notification_duration
	if key != &"" and _keyed_entries.has(key):
		var keyed_value: Variant = _keyed_entries.get(key)
		if keyed_value is HUDNotificationEntry:
			var keyed_entry: HUDNotificationEntry = keyed_value as HUDNotificationEntry
			if is_instance_valid(keyed_entry) and not keyed_entry.is_dismissing():
				keyed_entry.refresh(
					clean_title,
					detail.strip_edges(),
					icon_texture,
					hold_duration,
					_primary_color,
					bpm,
					playback_position_provider,
					wobble_icon
				)
				return keyed_entry
			_remove_entry_tracking(keyed_entry)
	var stack_limit: int = clampi(
		maximum_visible_notifications,
		1,
		MAXIMUM_NOTIFICATION_STACK_SIZE
	)
	while _entries.size() >= stack_limit:
		var oldest_entry: HUDNotificationEntry = _entries[0]
		_remove_entry_tracking(oldest_entry)
		oldest_entry.dismiss(true)
	var entry_scene: PackedScene = _get_notification_entry_scene()
	if entry_scene == null:
		return null
	var entry: HUDNotificationEntry = entry_scene.instantiate() as HUDNotificationEntry
	if entry == null:
		return null
	entry.minimum_panel_width = minimum_panel_width
	entry.maximum_panel_width = maximum_panel_width
	entry.foreground_lighten_amount = foreground_lighten_amount
	_notification_stack.add_child(entry)
	_entries.append(entry)
	if key != &"":
		_keyed_entries[key] = entry
	entry.dismissed.connect(_on_entry_dismissed)
	entry.configure(
		clean_title,
		detail.strip_edges(),
		icon_texture,
		hold_duration,
		key,
		_primary_color,
		bpm,
		playback_position_provider,
		wobble_icon
	)
	return entry


func dismiss_notification(key: StringName, immediate: bool = false) -> void:
	if key == &"" or not _keyed_entries.has(key):
		return
	var entry_value: Variant = _keyed_entries.get(key)
	_keyed_entries.erase(key)
	if not (entry_value is HUDNotificationEntry):
		return
	var entry: HUDNotificationEntry = entry_value as HUDNotificationEntry
	_entries.erase(entry)
	if is_instance_valid(entry):
		entry.dismiss(immediate)


func set_character_colors(primary_color: Color, secondary_color: Color) -> void:
	_primary_color = primary_color
	_secondary_color = secondary_color
	for entry: HUDNotificationEntry in _entries:
		if entry != null and is_instance_valid(entry):
			entry.set_primary_color(_primary_color)


func get_primary_color() -> Color:
	return _primary_color


func get_secondary_color() -> Color:
	return _secondary_color


func speed_up_notifications(speed_scale: float = 4.0) -> void:
	for entry: HUDNotificationEntry in _entries:
		if entry != null and is_instance_valid(entry):
			entry.speed_up(speed_scale)


func _refresh_music_controller(force_display: bool) -> void:
	if _shutting_down or get_tree() == null:
		return
	var active_controller: MusicController = MusicController.find_active_controller(get_tree())
	if active_controller != _music_controller:
		_disconnect_music_controller()
		_music_controller = active_controller
		if _music_controller != null:
			var track_callable: Callable = Callable(self, "_on_active_track_changed")
			if not _music_controller.active_track_changed.is_connected(track_callable):
				_music_controller.active_track_changed.connect(track_callable)
			force_display = true
	if _music_controller == null:
		if _current_stream != null:
			_on_active_track_changed(null, {})
		return
	var stream: AudioStream = _music_controller.get_selected_music_stream()
	if force_display or stream != _current_stream:
		if force_display and stream == _current_stream:
			_current_stream = null
		_on_active_track_changed(stream, _music_controller.get_track_information(stream))


func _disconnect_music_controller() -> void:
	if _music_controller == null or not is_instance_valid(_music_controller):
		return
	var track_callable: Callable = Callable(self, "_on_active_track_changed")
	if _music_controller.active_track_changed.is_connected(track_callable):
		_music_controller.active_track_changed.disconnect(track_callable)


func _on_active_track_changed(stream: AudioStream, track_information: Dictionary) -> void:
	if not can_accept_notifications():
		return
	if stream == _current_stream and stream != null:
		return
	_current_stream = stream
	dismiss_notification(&"music_track")
	if stream == null:
		return
	var title: String = String(track_information.get("title", "")).strip_edges()
	if title == "":
		title = _format_stream_name(stream, String(track_information.get("resource_path", "")))
	var author: String = String(track_information.get("author", "")).strip_edges()
	var bpm: float = max(float(track_information.get("bpm", 0.0)), 0.0)
	var playback_provider: Callable = Callable()
	if _music_controller != null and is_instance_valid(_music_controller):
		playback_provider = Callable(_music_controller, "get_current_playback_position")
	show_notification(
		title,
		author,
		_get_music_icon_texture(),
		music_notification_duration,
		&"music_track",
		bpm,
		playback_provider,
		bpm <= 0.0
	)


static func _get_notification_entry_scene() -> PackedScene:
	if _notification_entry_scene != null:
		return _notification_entry_scene
	if not ResourceLoader.exists(NOTIFICATION_ENTRY_SCENE_PATH):
		return null
	var resource: Resource = load(NOTIFICATION_ENTRY_SCENE_PATH)
	if resource is PackedScene:
		_notification_entry_scene = resource as PackedScene
	return _notification_entry_scene


func _get_music_icon_texture() -> Texture2D:
	if music_icon_texture != null:
		return music_icon_texture
	if not ResourceLoader.exists(MUSIC_ICON_PATH):
		return null
	var resource: Resource = load(MUSIC_ICON_PATH)
	if resource is Texture2D:
		music_icon_texture = resource as Texture2D
	return music_icon_texture


func _format_stream_name(stream: AudioStream, source_path: String) -> String:
	var display_source: String = source_path
	if display_source == "" and stream != null:
		display_source = stream.resource_path
	if display_source == "" and stream != null:
		display_source = stream.resource_name
	if display_source == "" and stream != null:
		display_source = stream.get_class()
	var display_name: String = display_source.get_file().get_basename()
	display_name = display_name.replace("_", " ").replace("-", " ")
	var words: PackedStringArray = display_name.split(" ", false)
	return " ".join(words).strip_edges()


func _on_entry_dismissed(entry: HUDNotificationEntry) -> void:
	_remove_entry_tracking(entry)


func _remove_entry_tracking(entry: HUDNotificationEntry) -> void:
	_entries.erase(entry)
	if entry == null or not is_instance_valid(entry):
		for key_value: Variant in _keyed_entries.keys():
			if _keyed_entries.get(key_value) == entry:
				_keyed_entries.erase(key_value)
		return
	var key: StringName = entry.notification_key
	if key != &"" and _keyed_entries.get(key) == entry:
		_keyed_entries.erase(key)


func _prune_entries() -> void:
	for index: int in range(_entries.size() - 1, -1, -1):
		var entry: HUDNotificationEntry = _entries[index]
		if entry == null or not is_instance_valid(entry):
			_entries.remove_at(index)
	for key_value: Variant in _keyed_entries.keys():
		var entry_value: Variant = _keyed_entries.get(key_value)
		if not (entry_value is HUDNotificationEntry) or not is_instance_valid(entry_value):
			_keyed_entries.erase(key_value)


func _update_stack_layout() -> void:
	if _notification_stack == null:
		return
	var safe_right_margin: float = max(right_margin, 0.0)
	var safe_top_margin: float = max(top_margin, 0.0)
	var available_width: float = max(size.x - safe_right_margin - 16.0, 1.0)
	var desired_stack_width: float = max(maximum_panel_width, minimum_panel_width)
	var stack_width: float = min(desired_stack_width, available_width)
	var entry_height: float = 112.0
	var stack_separation: float = float(_notification_stack.get_theme_constant("separation"))
	var visible_count: int = clampi(
		maximum_visible_notifications,
		1,
		MAXIMUM_NOTIFICATION_STACK_SIZE
	)
	var stack_height: float = entry_height * float(visible_count)
	stack_height += stack_separation * float(max(visible_count - 1, 0))
	_notification_stack.offset_left = -safe_right_margin - stack_width
	_notification_stack.offset_top = safe_top_margin
	_notification_stack.offset_right = -safe_right_margin
	_notification_stack.offset_bottom = safe_top_margin + stack_height


func _set_mouse_filter_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_mouse_filter_recursive(child)

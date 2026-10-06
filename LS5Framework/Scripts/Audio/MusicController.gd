extends Node
class_name MusicController

signal active_track_changed(stream: AudioStream, track_information: Dictionary)

const PRIORITY_BASE: int = 0
const PRIORITY_EVENT: int = 100
const PRIORITY_DROWNING: int = 200
const BASE_MUSIC_SOURCE_ID: StringName = &"__base_music__"

@export_group("Autostart")
@export var autoplay: bool = true
@export var autoplay_stream: AudioStream
@export var autoplay_fade_in: float = 0.75
@export var autoplay_fade_out: float = 0.5
## Additional volume in dB applied to the autoplay track.
@export var autoplay_volume_offset_db: float = 0.0
@export var autoplay_wait_frames: int = 2

@export_group("Track Information")
## Optional title, author, and BPM overrides associated with music streams.
@export var track_metadata: Array[MusicTrackMetadata] = []

@export_group("Playback")
@export var music_bus: StringName = &"Music"
@export var silent_db: float = -80.0

var _players: Array[AudioStreamPlayer] = []
var _active_player: AudioStreamPlayer
var _inactive_player: AudioStreamPlayer
var _player_tweens: Dictionary = {}
var _player_target_volumes: Dictionary = {}
var _autoplay_blocked: bool = false
var _autoplay_ticket: int = 0
var _base_music_stream: AudioStream = null
var _base_music_fade_in: float = 0.75
var _base_music_fade_out: float = 0.5
var _base_music_volume_offset_db: float = 0.0
var _base_music_start_position: float = 0.0
var _base_music_resume_position: float = 0.0
var _music_overrides: Dictionary = {}
var _music_override_sequence: int = 0
var _selected_music_source_id: StringName = &""
var _last_announced_stream: AudioStream = null

const _SUPPRESS_NEXT_AUTOPLAY_META: StringName = &"suppress_next_music_autoplay"


func _ready() -> void:
	_init_players()
	add_to_group("MusicControllers")

	# If another system (such as race setup) requests that the next autoplay
	# be suppressed, consume that request here and skip autoplay for this scene load.
	if _consume_autoplay_suppression_ticket():
		block_autoplay()
		return

	if autoplay and autoplay_stream:
		play_autoplay(true, -1.0, -1.0, true)

func _consume_autoplay_suppression_ticket() -> bool:
	# SUMMARY: Consume a one-shot suppression ticket stored on the SceneTree.
	# - Used to prevent level entry music from starting during race teleports.
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	if not tree.has_meta(_SUPPRESS_NEXT_AUTOPLAY_META):
		return false

	var raw_value = tree.get_meta(_SUPPRESS_NEXT_AUTOPLAY_META)
	var tickets: int = 0
	if raw_value is int:
		tickets = int(raw_value)
	elif raw_value is float:
		tickets = int(raw_value)
	elif raw_value is bool:
		if bool(raw_value):
			tickets = 1

	if tickets <= 0:
		tree.remove_meta(_SUPPRESS_NEXT_AUTOPLAY_META)
		return false

	tickets -= 1
	if tickets > 0:
		tree.set_meta(_SUPPRESS_NEXT_AUTOPLAY_META, tickets)
	else:
		tree.remove_meta(_SUPPRESS_NEXT_AUTOPLAY_META)
	return true


func _play_autoplay_when_ready(
	ticket: int,
	restart_if_same: bool,
	fade_in_time: float,
	fade_out_time: float
) -> void:
	if not autoplay or autoplay_stream == null:
		return
	if _autoplay_blocked or ticket != _autoplay_ticket:
		return
	var tree := get_tree()
	if tree == null:
		if _autoplay_blocked or ticket != _autoplay_ticket:
			return
		_play_autoplay_now(restart_if_same, fade_in_time, fade_out_time)
		return
	var frames: int = max(autoplay_wait_frames, 0)
	while frames > 0:
		await tree.process_frame
		if _autoplay_blocked or ticket != _autoplay_ticket:
			return
		frames -= 1
	while tree.paused:
		await tree.process_frame
		if _autoplay_blocked or ticket != _autoplay_ticket:
			return
	if _autoplay_blocked or ticket != _autoplay_ticket:
		return
	_play_autoplay_now(restart_if_same, fade_in_time, fade_out_time)


func _init_players() -> void:
	if not _players.is_empty():
		return

	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % (i + 1)
		player.bus = music_bus
		player.volume_db = silent_db
		add_child(player)
		_players.append(player)

	_active_player = _players[0]
	_inactive_player = _players[1]


func play_music(
	stream: AudioStream,
	fade_in_time: float = 0.75,
	fade_out_time: float = 0.5,
	restart_if_same: bool = false,
	from_position: float = 0.0,
	volume_offset_db: float = 0.0
) -> void:
	if stream == null:
		stop_music(fade_out_time)
		return
	var stream_changed: bool = _base_music_stream != stream
	if _selected_music_source_id == BASE_MUSIC_SOURCE_ID and stream_changed:
		_capture_selected_playback_position()
	_base_music_stream = stream
	_base_music_fade_in = max(fade_in_time, 0.0)
	_base_music_fade_out = max(fade_out_time, 0.0)
	_base_music_volume_offset_db = volume_offset_db
	_base_music_start_position = max(from_position, 0.0)
	if stream_changed or restart_if_same:
		_base_music_resume_position = _base_music_start_position
	_refresh_music_selection(
		fade_in_time,
		fade_out_time,
		BASE_MUSIC_SOURCE_ID if restart_if_same else &""
	)


func request_music_override(
	source_id: StringName,
	stream: AudioStream,
	priority: int = PRIORITY_EVENT,
	fade_in_time: float = 0.25,
	fade_out_time: float = 0.35,
	restart_if_same: bool = false,
	from_position: float = 0.0,
	volume_offset_db: float = 0.0
) -> bool:
	if source_id == &"" or source_id == BASE_MUSIC_SOURCE_ID or stream == null:
		return false
	_music_override_sequence += 1
	var resume_position: float = max(from_position, 0.0)
	if _music_overrides.has(source_id):
		var previous_entry: Dictionary = _music_overrides[source_id]
		if previous_entry.get("stream") == stream and not restart_if_same:
			resume_position = float(previous_entry.get("resume_position", resume_position))
	var entry: Dictionary = {
		"stream": stream,
		"priority": priority,
		"sequence": _music_override_sequence,
		"fade_in": max(fade_in_time, 0.0),
		"fade_out": max(fade_out_time, 0.0),
		"restart_if_same": restart_if_same,
		"start_position": max(from_position, 0.0),
		"resume_position": resume_position,
		"volume_offset_db": volume_offset_db,
	}
	_music_overrides[source_id] = entry
	_refresh_music_selection(
		fade_in_time,
		fade_out_time,
		source_id if restart_if_same else &""
	)
	return true


func release_music_override(
	source_id: StringName,
	fade_in_time: float = 0.25,
	fade_out_time: float = 0.35
) -> bool:
	if not _music_overrides.has(source_id):
		return false
	if _selected_music_source_id == source_id:
		_capture_selected_playback_position()
	_music_overrides.erase(source_id)
	_refresh_music_selection(fade_in_time, fade_out_time)
	return true


func clear_music_overrides(fade_in_time: float = 0.25, fade_out_time: float = 0.35) -> void:
	_capture_selected_playback_position()
	_music_overrides.clear()
	_refresh_music_selection(fade_in_time, fade_out_time)


func has_music_override(source_id: StringName) -> bool:
	return _music_overrides.has(source_id)


func get_active_music_priority() -> int:
	if _selected_music_source_id == BASE_MUSIC_SOURCE_ID:
		return PRIORITY_BASE
	if _music_overrides.has(_selected_music_source_id):
		var entry: Dictionary = _music_overrides[_selected_music_source_id]
		return int(entry.get("priority", PRIORITY_EVENT))
	return -1


func get_active_music_source_id() -> StringName:
	return _selected_music_source_id


func get_selected_music_stream() -> AudioStream:
	if _selected_music_source_id == BASE_MUSIC_SOURCE_ID:
		return _base_music_stream
	if _music_overrides.has(_selected_music_source_id):
		var entry: Dictionary = _music_overrides[_selected_music_source_id]
		return entry.get("stream") as AudioStream
	return null


func get_music_source_playback_position(source_id: StringName) -> float:
	if source_id == _selected_music_source_id \
			and _active_player != null \
			and _active_player.stream != null:
		return max(_active_player.get_playback_position(), 0.0)
	if source_id == BASE_MUSIC_SOURCE_ID:
		return max(_base_music_resume_position, 0.0)
	if _music_overrides.has(source_id):
		var entry: Dictionary = _music_overrides[source_id]
		return max(float(entry.get("resume_position", 0.0)), 0.0)
	return 0.0


func is_music_source_playing(source_id: StringName) -> bool:
	return source_id == _selected_music_source_id \
		and _active_player != null \
		and _active_player.playing


static func find_active_controller(tree: SceneTree) -> MusicController:
	if tree == null:
		return null
	var fallback: MusicController = null
	for node: Node in tree.get_nodes_in_group("MusicControllers"):
		if not (node is MusicController):
			continue
		var controller: MusicController = node as MusicController
		if fallback == null:
			fallback = controller
		if controller.get_selected_music_stream() != null:
			return controller
	return fallback


func _refresh_music_selection(
	default_fade_in: float,
	default_fade_out: float,
	restart_source_id: StringName = &""
) -> void:
	var target_source_id: StringName = _get_winning_override_source_id()
	if target_source_id == &"" and _base_music_stream != null:
		target_source_id = BASE_MUSIC_SOURCE_ID
	if target_source_id == &"":
		_selected_music_source_id = &""
		_stop_playback(default_fade_out)
		_announce_active_track(null)
		return

	var selection_changed: bool = target_source_id != _selected_music_source_id
	if selection_changed:
		_capture_selected_playback_position()
	_selected_music_source_id = target_source_id

	var target_stream: AudioStream = null
	var fade_in_time: float = max(default_fade_in, 0.0)
	var resume_position: float = 0.0
	var volume_offset_db: float = 0.0
	if target_source_id == BASE_MUSIC_SOURCE_ID:
		target_stream = _base_music_stream
		fade_in_time = max(default_fade_in, 0.0)
		resume_position = _base_music_resume_position
		volume_offset_db = _base_music_volume_offset_db
	else:
		var target_entry: Dictionary = _music_overrides[target_source_id]
		target_stream = target_entry.get("stream") as AudioStream
		fade_in_time = float(target_entry.get("fade_in", default_fade_in))
		resume_position = float(target_entry.get("resume_position", 0.0))
		volume_offset_db = float(target_entry.get("volume_offset_db", 0.0))

	var restart_selected: bool = target_source_id == restart_source_id
	_play_stream(
		target_stream,
		fade_in_time,
		max(default_fade_out, 0.0),
		restart_selected,
		resume_position,
		volume_offset_db
	)
	_announce_active_track(target_stream)


func _get_winning_override_source_id() -> StringName:
	var winning_source_id: StringName = &""
	var winning_priority: int = -2147483648
	var winning_sequence: int = -1
	for source_key in _music_overrides:
		var source_id: StringName = StringName(source_key)
		var entry: Dictionary = _music_overrides[source_key]
		var priority: int = int(entry.get("priority", PRIORITY_EVENT))
		var sequence: int = int(entry.get("sequence", 0))
		if priority > winning_priority or (priority == winning_priority and sequence > winning_sequence):
			winning_source_id = source_id
			winning_priority = priority
			winning_sequence = sequence
	return winning_source_id


func _capture_selected_playback_position() -> void:
	if _active_player == null or _active_player.stream == null or not _active_player.playing:
		return
	var playback_position: float = max(_active_player.get_playback_position(), 0.0)
	if _selected_music_source_id == BASE_MUSIC_SOURCE_ID:
		_base_music_resume_position = playback_position
	elif _music_overrides.has(_selected_music_source_id):
		var entry: Dictionary = _music_overrides[_selected_music_source_id]
		entry["resume_position"] = playback_position
		_music_overrides[_selected_music_source_id] = entry


func _play_stream(
	stream: AudioStream,
	fade_in_time: float = 0.75,
	fade_out_time: float = 0.5,
	restart_if_same: bool = false,
	from_position: float = 0.0,
	volume_offset_db: float = 0.0
) -> void:
	_init_players()
	if stream == null:
		_stop_playback(fade_out_time)
		return

	if _active_player.stream == stream:
		_player_target_volumes[_active_player] = volume_offset_db
		if restart_if_same:
			_restart_active(from_position)
		elif not _active_player.playing:
			_active_player.play(max(from_position, 0.0))
		_fade_player(_active_player, volume_offset_db, fade_in_time)
		return

	_prepare_inactive(stream, from_position, volume_offset_db)
	_cross_fade_players(fade_in_time, fade_out_time)
	_swap_players()


func play_music_override(
	stream: AudioStream,
	fade_in_time: float = 0.75,
	fade_out_time: float = 0.5,
	restart_if_same: bool = false,
	from_position: float = 0.0,
	volume_offset_db: float = 0.0
) -> void:
	block_autoplay()
	_block_other_autoplay()
	_fade_other_controllers(fade_out_time)
	play_music(stream, fade_in_time, fade_out_time, restart_if_same, from_position, volume_offset_db)


func play_autoplay(
	restart_if_same: bool = false,
	fade_in_time: float = -1.0,
	fade_out_time: float = -1.0,
	defer_until_ready: bool = false
) -> void:
	if autoplay_stream == null:
		return
	_autoplay_blocked = false
	_autoplay_ticket += 1
	var ticket = _autoplay_ticket
	if defer_until_ready:
		call_deferred("_play_autoplay_when_ready", ticket, restart_if_same, fade_in_time, fade_out_time)
		return
	_play_autoplay_now(restart_if_same, fade_in_time, fade_out_time)


func _play_autoplay_now(restart_if_same: bool, fade_in_time: float, fade_out_time: float) -> void:
	var fade_in := autoplay_fade_in if fade_in_time < 0.0 else fade_in_time
	var fade_out := autoplay_fade_out if fade_out_time < 0.0 else fade_out_time
	_fade_other_controllers(fade_out)
	play_music(autoplay_stream, fade_in, fade_out, restart_if_same, 0.0, autoplay_volume_offset_db)


func stop_music(fade_out_time: float = 0.5) -> void:
	if _selected_music_source_id == BASE_MUSIC_SOURCE_ID:
		_capture_selected_playback_position()
	_base_music_stream = null
	_base_music_resume_position = 0.0
	_refresh_music_selection(0.0, fade_out_time)


func stop_all_music(fade_out_time: float = 0.5) -> void:
	_music_overrides.clear()
	_base_music_stream = null
	_base_music_resume_position = 0.0
	_selected_music_source_id = &""
	_stop_playback(fade_out_time)
	_announce_active_track(null)


func _stop_playback(fade_out_time: float = 0.5) -> void:
	for player: AudioStreamPlayer in [_active_player, _inactive_player]:
		if player and player.stream:
			_fade_player(player, silent_db, maxf(fade_out_time, 0.0), true)


func stop_music_override(fade_out_time: float = 0.5) -> void:
	block_autoplay()
	_block_other_autoplay()
	_fade_other_controllers(fade_out_time)
	stop_all_music(fade_out_time)


func duck_music(fade_out_time: float = 0.5) -> void:
	if _active_player == null or _active_player.stream == null:
		return
	_fade_player(_active_player, silent_db, fade_out_time, false)


func restore_ducked_music(fade_in_time: float = 0.5) -> void:
	if _active_player == null or _active_player.stream == null:
		return
	if not _active_player.playing:
		_active_player.play()
	_fade_player(_active_player, _get_player_target_volume(_active_player), fade_in_time, false)


func get_current_stream() -> AudioStream:
	if _active_player == null:
		return null
	return _active_player.stream


func get_current_track_information() -> Dictionary:
	return get_track_information(get_selected_music_stream())


func get_current_playback_position() -> float:
	if _active_player == null or _active_player.stream == null or not _active_player.playing:
		return 0.0
	return max(_active_player.get_playback_position(), 0.0)


func get_track_information(stream: AudioStream) -> Dictionary:
	if stream == null:
		return {}
	var metadata_entry: MusicTrackMetadata = _find_track_metadata(stream)
	var title: String = ""
	var author: String = ""
	var bpm: float = -1.0
	if metadata_entry != null:
		title = metadata_entry.title.strip_edges()
		author = metadata_entry.author.strip_edges()
		bpm = metadata_entry.bpm_override
	if title == "":
		title = _read_stream_text_metadata(
			stream,
			[&"title", &"track_title", &"track_name", &"name"]
		)
	if author == "":
		author = _read_stream_text_metadata(
			stream,
			[&"artist", &"author", &"album_artist", &"composer"]
		)
	if bpm < 0.0:
		bpm = _read_stream_bpm(stream)
	return {
		"title": title,
		"author": author,
		"bpm": max(bpm, 0.0),
		"resource_path": _get_stream_source_path(stream),
	}


func _find_track_metadata(stream: AudioStream) -> MusicTrackMetadata:
	for metadata_entry: MusicTrackMetadata in track_metadata:
		if metadata_entry != null and metadata_entry.matches_stream(stream):
			return metadata_entry
	return null


func _read_stream_text_metadata(stream: AudioStream, keys: Array[StringName]) -> String:
	for key: StringName in keys:
		if stream.has_meta(key):
			var metadata_value: Variant = stream.get_meta(key, "")
			if metadata_value is String or metadata_value is StringName:
				var metadata_text: String = String(metadata_value).strip_edges()
				if metadata_text != "":
					return metadata_text
		var tag_value: Variant = _read_stream_tag(stream, key)
		if tag_value is String or tag_value is StringName:
			var tag_text: String = String(tag_value).strip_edges()
			if tag_text != "":
				return tag_text
		if _object_has_property(stream, key):
			var property_value: Variant = stream.get(key)
			if property_value is String or property_value is StringName:
				var property_text: String = String(property_value).strip_edges()
				if property_text != "":
					return property_text
	return ""


func _read_stream_bpm(stream: AudioStream) -> float:
	if stream.has_meta(&"bpm"):
		var metadata_bpm: Variant = stream.get_meta(&"bpm", 0.0)
		if metadata_bpm is float or metadata_bpm is int:
			var numeric_metadata_bpm: float = max(float(metadata_bpm), 0.0)
			if numeric_metadata_bpm > 0.0:
				return numeric_metadata_bpm
	var bpm_tag_keys: Array[StringName] = [&"bpm", &"tempo"]
	for tag_key: StringName in bpm_tag_keys:
		var tag_bpm: Variant = _read_stream_tag(stream, tag_key)
		if tag_bpm is float or tag_bpm is int:
			var numeric_tag_bpm: float = max(float(tag_bpm), 0.0)
			if numeric_tag_bpm > 0.0:
				return numeric_tag_bpm
		elif tag_bpm is String or tag_bpm is StringName:
			var tag_bpm_text: String = String(tag_bpm).strip_edges()
			if tag_bpm_text.is_valid_float():
				var parsed_tag_bpm: float = max(tag_bpm_text.to_float(), 0.0)
				if parsed_tag_bpm > 0.0:
					return parsed_tag_bpm
	if stream.has_method("get_bpm"):
		var stream_bpm: Variant = stream.call("get_bpm")
		if stream_bpm is float or stream_bpm is int:
			return max(float(stream_bpm), 0.0)
	return 0.0


func _read_stream_tag(stream: AudioStream, requested_key: StringName) -> Variant:
	if not _object_has_property(stream, &"tags"):
		return null
	var tag_data: Variant = stream.get(&"tags")
	if not (tag_data is Dictionary):
		return null
	var tags: Dictionary = tag_data as Dictionary
	for tag_key: Variant in tags.keys():
		if String(tag_key).nocasecmp_to(String(requested_key)) == 0:
			return tags.get(tag_key)
	return null


func _get_stream_source_path(stream: AudioStream) -> String:
	if stream.has_meta(&"source_resource_path"):
		var source_path: String = String(stream.get_meta(&"source_resource_path", ""))
		if source_path != "":
			return source_path
	return stream.resource_path


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property_data: Dictionary in object.get_property_list():
		if StringName(property_data.get("name", &"")) == property_name:
			return true
	return false


func _announce_active_track(stream: AudioStream) -> void:
	if stream == _last_announced_stream:
		return
	_last_announced_stream = stream
	active_track_changed.emit(stream, get_track_information(stream))


func is_playing_stream(stream: AudioStream) -> bool:
	return stream != null and _active_player != null and _active_player.stream == stream


func block_autoplay() -> void:
	_autoplay_blocked = true
	_autoplay_ticket += 1


func _block_other_autoplay() -> void:
	if get_tree() == null:
		return
	var controllers := get_tree().get_nodes_in_group("MusicControllers")
	for node in controllers:
		if node == self:
			continue
		if node is MusicController:
			(node as MusicController).block_autoplay()


func _prepare_inactive(stream: AudioStream, from_position: float, volume_offset_db: float) -> void:
	_inactive_player.stop()
	_inactive_player.stream = stream
	_inactive_player.volume_db = silent_db
	_player_target_volumes[_inactive_player] = volume_offset_db

	if from_position > 0.0:
		_inactive_player.play(from_position)
	else:
		_inactive_player.play()


func _cross_fade_players(fade_in_time: float, fade_out_time: float) -> void:
	_fade_player(_inactive_player, _get_player_target_volume(_inactive_player), fade_in_time)
	_fade_player(_active_player, silent_db, fade_out_time, true)


func _fade_player(
	player: AudioStreamPlayer,
	target_db: float,
	duration: float,
	stop_when_done: bool = false
) -> void:
	if player == null:
		return

	_kill_tween(player)

	if duration <= 0.0:
		player.volume_db = target_db
		if stop_when_done and target_db <= silent_db + 0.01:
			player.stop()
			player.stream = null
			_player_target_volumes.erase(player)
		return

	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, duration)
	_player_tweens[player] = tween
	tween.finished.connect(Callable(self, "_on_tween_finished").bind(player))

	if stop_when_done:
		tween.tween_callback(Callable(self, "_on_player_fade_complete").bind(player))


func _restart_active(from_position: float) -> void:
	if not _active_player.playing:
		_active_player.play(max(from_position, 0.0))
	elif from_position > 0.0:
		_active_player.play(from_position)
	else:
		_active_player.seek(0.0)


func _swap_players() -> void:
	var old_active := _active_player
	_active_player = _inactive_player
	_inactive_player = old_active


func _get_player_target_volume(player: AudioStreamPlayer) -> float:
	if _player_target_volumes.has(player):
		return float(_player_target_volumes[player])
	return 0.0


func _fade_other_controllers(fade_out_time: float) -> void:
	if get_tree() == null:
		return
	var controllers := get_tree().get_nodes_in_group("MusicControllers")
	for node in controllers:
		if node == self:
			continue
		if node is MusicController:
			(node as MusicController).stop_all_music(fade_out_time)


func _kill_tween(player: AudioStreamPlayer) -> void:
	if not _player_tweens.has(player):
		return

	var tween: Tween = _player_tweens[player]
	if tween and tween.is_running():
		tween.kill()
	_player_tweens.erase(player)


func _on_player_fade_complete(player: AudioStreamPlayer) -> void:
	player.stop()
	player.stream = null
	_player_tweens.erase(player)
	_player_target_volumes.erase(player)


func _on_tween_finished(player: AudioStreamPlayer) -> void:
	_player_tweens.erase(player)

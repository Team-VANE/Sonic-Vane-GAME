extends Node3D
class_name ActorAudioCues3D

@export_group("Audio Nodes")
## Optional authored AudioStreamPlayer3D for the movement or idle loop. Empty creates a cue player.
@export_node_path("AudioStreamPlayer3D") var idle_player_path: NodePath
## Optional authored AudioStreamPlayer3D shared by one-shot cues. Empty creates a cue player.
@export_node_path("AudioStreamPlayer3D") var cue_player_path: NodePath

@export_group("Cues")
## Loop played while the owning actor is alive and active.
@export var idle_sound: AudioStream
## Sound played when the actor detects a target.
@export var alert_sound: AudioStream
## Sound played when the actor takes non-lethal damage.
@export var damage_sound: AudioStream
## Sound played when the actor is defeated.
@export var defeat_sound: AudioStream
## Sound played when an attack starts.
@export var attack_sound: AudioStream
## Sound played when a projectile is released.
@export var projectile_sound: AudioStream

@export_group("Playback")
## Audio bus used by generated cue players.
@export var sound_bus: StringName = &"SFX"
## Volume applied to one-shot cue players.
@export var volume_db: float = 0.0
## Pitch applied to one-shot cue players.
@export var pitch_scale: float = 1.0
## Maximum audible distance for one-shot cue players.
@export var max_distance: float = 64.0

@export_group("Idle Playback")
## Audio bus used by the idle loop. An empty value uses the regular sound bus.
@export var idle_sound_bus: StringName = &""
## Volume applied to the idle loop.
@export var idle_volume_db: float = 0.0
## Maximum audible distance for the idle loop.
@export var idle_max_distance: float = 64.0
## Random pitch offset applied once when the idle player is created.
@export_range(0.0, 0.5, 0.01) var idle_pitch_variation: float = 0.0
## Plays the idle loop only while actual movement exceeds the configured threshold.
@export var idle_requires_movement: bool = false
## Minimum movement speed required by a movement-driven idle loop.
@export_range(0.0, 20.0, 0.01) var idle_movement_min_speed: float = 0.1

@export_group("Idle Voice Limiting")
## Identifier used to share an idle-loop voice budget between similar actors.
@export var idle_voice_group: StringName = &""
## Number of nearest idle loops that play at full configured volume.
@export_range(1, 32, 1) var idle_full_voice_count: int = 4
## Number of nearest idle loops allowed to play, including reduced-volume voices.
@export_range(1, 32, 1) var idle_max_voice_count: int = 6
## Additional attenuation applied to idle loops outside the full-volume budget.
@export_range(-60.0, 0.0, 0.5) var idle_reduced_volume_db: float = -12.0
## Interval between idle-loop priority updates.
@export_range(0.05, 1.0, 0.05) var idle_voice_update_interval: float = 0.2

var _idle_player: AudioStreamPlayer3D = null
var _one_shot_player: AudioStreamPlayer3D = null
var _idle_requested: bool = false
var _idle_group_name: StringName = &""
var _idle_update_time: float = 0.0


func setup() -> void:
	var resolved_idle_bus: StringName = idle_sound_bus if idle_sound_bus else sound_bus
	_idle_player = get_node_or_null(idle_player_path) as AudioStreamPlayer3D if not idle_player_path.is_empty() else null
	if _idle_player:
		var stream: AudioStream = idle_sound if idle_sound else _idle_player.stream
		_idle_player.stream = _prepare_loop(stream)
		idle_volume_db = _idle_player.volume_db
		idle_max_distance = _idle_player.max_distance
	else:
		_idle_player = _create_player(
			&"IdleCue",
			_prepare_loop(idle_sound),
			resolved_idle_bus,
			idle_volume_db,
			idle_max_distance,
			max(pitch_scale + randf_range(-idle_pitch_variation, idle_pitch_variation), 0.01)
		)
	_one_shot_player = get_node_or_null(cue_player_path) as AudioStreamPlayer3D if not cue_player_path.is_empty() else null
	if not _one_shot_player:
		_one_shot_player = _create_player(&"OneShotCue", null, sound_bus, volume_db, max_distance, pitch_scale)
	if idle_voice_group:
		_idle_group_name = StringName("actor_idle_audio_%s" % idle_voice_group)
		add_to_group(_idle_group_name)
	set_process(idle_voice_group != &"")


func _process(delta: float) -> void:
	_idle_update_time -= delta
	if _idle_update_time > 0.0:
		return
	_idle_update_time = max(idle_voice_update_interval, 0.05)
	_update_limited_idle()


func set_idle_active(value: bool, movement_speed: float = 0.0) -> void:
	value = value and (not idle_requires_movement or movement_speed > idle_movement_min_speed)
	_idle_requested = value
	if _idle_player == null or _idle_player.stream == null:
		return
	if idle_voice_group:
		_update_limited_idle()
	elif value:
		if not _idle_player.playing:
			_play_idle_randomized()
	elif _idle_player.playing:
		_idle_player.stop()


func play_cue(cue: StringName) -> void:
	var stream: AudioStream = null
	match cue:
		&"alert":
			stream = alert_sound
		&"damage":
			stream = damage_sound
		&"defeat":
			stream = defeat_sound
		&"attack":
			stream = attack_sound
		&"projectile":
			stream = projectile_sound
	if stream == null or _one_shot_player == null:
		return
	_one_shot_player.stop()
	_one_shot_player.stream = stream
	_one_shot_player.play()


func stop_one_shot() -> void:
	if _one_shot_player:
		_one_shot_player.stop()


func _create_player(
	node_name: StringName,
	stream: AudioStream,
	player_bus: StringName,
	player_volume_db: float,
	player_max_distance: float,
	player_pitch_scale: float
) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.name = String(node_name)
	player.stream = stream
	player.bus = String(player_bus)
	player.volume_db = player_volume_db
	player.pitch_scale = max(player_pitch_scale, 0.01)
	player.max_distance = max(player_max_distance, 0.0)
	add_child(player)
	return player


func _update_limited_idle() -> void:
	if _idle_player == null or _idle_player.stream == null:
		return
	if not _idle_requested:
		_idle_player.stop()
		return
	if not get_viewport().get_audio_listener_3d() and not get_viewport().get_camera_3d():
		_idle_player.stop()
		return
	var listener_position: Vector3 = SpatialAudioPolicy.get_listener_position(self)
	var distance_squared: float = global_position.distance_squared_to(listener_position)
	var audible_distance: float = _idle_player.max_distance
	if audible_distance > 0.0 and distance_squared > audible_distance * audible_distance:
		_idle_player.stop()
		return
	var closer_count: int = 0
	for node: Node in get_tree().get_nodes_in_group(_idle_group_name):
		var other: ActorAudioCues3D = node as ActorAudioCues3D
		if other == null or other == self or not other._idle_requested:
			continue
		var other_distance_squared: float = other.global_position.distance_squared_to(listener_position)
		var other_distance: float = other._idle_player.max_distance if is_instance_valid(other._idle_player) else other.idle_max_distance
		if other_distance > 0.0 and other_distance_squared > other_distance * other_distance:
			continue
		if other_distance_squared < distance_squared or (
			is_equal_approx(other_distance_squared, distance_squared)
			and other.get_instance_id() < get_instance_id()
		):
			closer_count += 1
	var full_voice_limit: int = max(idle_full_voice_count, 1)
	var maximum_voice_limit: int = max(idle_max_voice_count, full_voice_limit)
	if closer_count >= maximum_voice_limit:
		_idle_player.stop()
		return
	_idle_player.volume_db = idle_volume_db if closer_count < full_voice_limit else idle_volume_db + idle_reduced_volume_db
	if not _idle_player.playing:
		_play_idle_randomized()


func _play_idle_randomized() -> void:
	var stream_length: float = _idle_player.stream.get_length()
	var start_position: float = randf_range(0.0, stream_length) if stream_length > 0.0 else 0.0
	_idle_player.play(start_position)


func _prepare_loop(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var prepared: AudioStream = stream.duplicate() as AudioStream
	if prepared and _object_has_property(prepared, &"loop_mode"):
		prepared.set("loop_mode", 1)
	return prepared


func _object_has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false

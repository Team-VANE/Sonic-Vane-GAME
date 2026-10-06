class_name DrownedAction
extends CharacterAction

## Drowning countdown and drowned state action.
## Add as a child of the player's Abilities node.
## The countdown begins when the head collider enters water and stops when it exits.
## When the timer expires the drowned sequence plays, then the player respawns at checkpoint.

@export_group("Drowning")

@export_subgroup("Timer")
## Total seconds before drowning triggers.
@export var drowning_time: float = 30.0
## Seconds of the countdown that trigger a notify sound (e.g. [10, 5]).
@export var notify_seconds: Array[float] = [15.0, 20.0, 25.0]
## Seconds of the countdown that trigger an alert sound (e.g. [4, 3, 2, 1]).
@export var alert_seconds: Array[float] = [5.0, 4.0, 3.0, 2.0, 1.0]

@export_subgroup("Audio/Sounds")
## Played when the timer crosses a notify_seconds value.
@export var sfx_notify: AudioStream = preload("res://LS5Framework/Sounds/General/Drown_Notify.wav")
## Played when the timer crosses an alert_seconds value.
@export var sfx_alert: AudioStream = preload("res://LS5Framework/Sounds/General/Drown_Alert.wav")
## Played when the drowned sequence begins.
@export var sfx_drowned: AudioStream = preload("res://LS5Framework/Sounds/General/Drowned.wav")

@export_subgroup("Audio/Music")
## Music track to cross-fade to when the countdown begins.
@export var drowning_music: AudioStream = preload("res://LS5Framework/Sounds/Music/Drowning_Colours.mp3")
## Fade-in time for the drowning music.
@export var drowning_music_fade_in: float = 0.1
## Fade-out time for the drowning music.
@export var drowning_music_fade_out: float = 0.7
## Time remaining on the countdown at which the music transitions in.
@export var drowning_music_trigger_at_seconds: float = 13.0
## Priority used by the drowning music override.
@export var drowning_music_priority: int = MusicController.PRIORITY_DROWNING

@export_subgroup("Sequence/Physics")
## All-around deceleration applied each second while drowned.
@export var drowned_decel: float = 0.7
## Upward float force applied while drowned (small positive value).
@export var drowned_float_speed: float = 1.0
## Maximum upward speed while floating.
@export var drowned_float_max_up_speed: float = 6.0

@export_subgroup("Sequence/Respawn")
## Delay (seconds) before respawning after drowned animation starts.
@export var respawn_delay: float = 4.0
## Fade-out duration for the respawn black screen.
@export var fade_out_duration: float = 0.5
## Hold duration at peak black.
@export var fade_hold_duration: float = 0.1
## Fade-in duration after respawn.
@export var fade_in_duration: float = 0.5

# Runtime state
var _countdown_active: bool = false
var _countdown_timer: float = 0.0
var _drowned_active: bool = false
var _drowned_sequence_running: bool = false
var _music_triggered: bool = false
var _music_trigger_checked: bool = false
var _drowning_music_controller: MusicController = null
var _drowning_music_source_id: StringName = &""
var _notified_seconds: Array = []
var _alerted_seconds: Array = []


func _on_action_initialized() -> void:
	action_id = &"drowned"
	input_action = &""
	continuous_update = true
	allow_when_inactive = true


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func _exit_tree() -> void:
	_restore_music()


# ---------------------------------------------------------------------------
# Public API called from SonicPlayer
# ---------------------------------------------------------------------------

func start_countdown() -> void:
	if _is_post_race_protected():
		return
	if _drowned_active or _drowned_sequence_running:
		return
	if _countdown_active:
		return
	_countdown_active = true
	_countdown_timer = drowning_time
	_music_triggered = false
	_music_trigger_checked = false
	_clear_music_state()
	_notified_seconds.clear()
	_alerted_seconds.clear()


func stop_countdown() -> void:
	if _drowned_active or _drowned_sequence_running:
		return
	var should_restore_music: bool = _music_triggered
	_countdown_active = false
	_countdown_timer = 0.0
	_music_triggered = false
	_music_trigger_checked = false
	_notified_seconds.clear()
	_alerted_seconds.clear()
	if should_restore_music:
		_restore_music()
	else:
		_clear_music_state()


func is_countdown_active() -> bool:
	return _countdown_active


func is_drowned() -> bool:
	return _drowned_active or _drowned_sequence_running


func get_countdown_remaining() -> float:
	return _countdown_timer


# ---------------------------------------------------------------------------
# Continuous update – runs every physics frame regardless of active action
# ---------------------------------------------------------------------------

func continuous_physics_update(delta: float) -> void:
	if owner_player == null:
		return
	if not owner_player._network_is_local_authority():
		return
	if _is_post_race_protected():
		if _countdown_active:
			stop_countdown()
		return

	if _countdown_active and not _drowned_active and not _drowned_sequence_running:
		_tick_countdown(delta)

	if _drowned_active:
		_apply_drowned_physics(owner_player.get_movement_delta(delta))


# ---------------------------------------------------------------------------
# Active action physics update (runs while this is the _active_action)
# ---------------------------------------------------------------------------

func physics_update_action(_delta: float) -> void:
	pass


# ---------------------------------------------------------------------------
# Countdown ticking
# ---------------------------------------------------------------------------

func _tick_countdown(delta: float) -> void:
	_countdown_timer -= delta

	# Music trigger
	if not _music_trigger_checked and _countdown_timer <= drowning_music_trigger_at_seconds:
		_music_trigger_checked = true
		if _uses_global_drowning_presentation():
			_music_triggered = _play_drowning_music()

	# Notify / alert cues – fire once per threshold crossing
	for s in notify_seconds:
		if not _notified_seconds.has(s) and _countdown_timer <= s:
			_notified_seconds.append(s)
			_play_sfx(sfx_notify)

	for s in alert_seconds:
		if not _alerted_seconds.has(s) and _countdown_timer <= s:
			_alerted_seconds.append(s)
			_play_sfx(sfx_alert)

	if _countdown_timer <= 0.0:
		_countdown_active = false
		_begin_drowned_sequence()


# ---------------------------------------------------------------------------
# Drowned sequence entry
# ---------------------------------------------------------------------------

func _begin_drowned_sequence() -> void:
	if _is_post_race_protected():
		stop_countdown()
		return
	if _drowned_sequence_running:
		return
	_drowned_sequence_running = true
	_drowned_active = true

	if owner_player == null or not is_instance_valid(owner_player):
		_drowned_sequence_running = false
		_drowned_active = false
		return
	if owner_player.has_method("begin_death_sequence"):
		owner_player.call("begin_death_sequence", &"drowned")
	elif owner_player.has_method("set_death_state"):
		owner_player.call("set_death_state", true)

	# Detach from any surface
	if owner_player.attached:
		owner_player.attached = false
		owner_player._attachment_immunity = owner_player.launch_immunity_time
		owner_player._airborne_time = 0.0

	# Cancel active states
	if owner_player.has_method("cancel_rail_grind"):
		owner_player.call("cancel_rail_grind")
	if owner_player.has_method("cancel_spline_spring"):
		owner_player.call("cancel_spline_spring")

	# Lock all gameplay input (camera still runs via separate path)
	owner_player.call("set_ui_input_blocked", true)
	if owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.call("remove_coyote_jump_eligibility")

	# Play drowned animation command
	owner_player._trigger_anim_command(&"CMD_DROWNED")

	# Play drowned sound effect
	_play_sfx(sfx_drowned)

	# Set player state lock so teleporters/death planes/level transitions are ignored
	owner_player._player_state_locked = true

	_run_drowned_sequence_async()


func _run_drowned_sequence_async() -> void:
	if get_tree() == null:
		_respawn_from_drowning()
		_finish_drowned_sequence()
		return

	await get_tree().create_timer(respawn_delay).timeout

	if owner_player == null or not is_instance_valid(owner_player):
		_finish_drowned_sequence()
		return

	var fader = _get_or_create_fader() if _uses_global_drowning_presentation() else null

	if fader != null and fader.has_method("fade_out"):
		await fader.call("fade_out", fade_out_duration)

	if fader != null and get_tree() != null and fade_hold_duration > 0.0:
		await get_tree().create_timer(fade_hold_duration).timeout

	_respawn_from_drowning()

	if fader != null and fader.has_method("fade_in"):
		await fader.call("fade_in", fade_in_duration)

	_finish_drowned_sequence()


func _respawn_from_drowning() -> void:
	_drowned_active = false
	if owner_player == null or not is_instance_valid(owner_player):
		return
	owner_player.call("respawn_checkpoint_now")
	if owner_player.has_method("apply_death_respawn_consequences"):
		owner_player.call("apply_death_respawn_consequences", &"drowned")
	elif owner_player.has_method("reset_rings"):
		owner_player.call("reset_rings")
	if owner_player.camera_rig != null and owner_player.camera_rig.has_method("notify_teleport"):
		owner_player.camera_rig.call("notify_teleport")


func _finish_drowned_sequence() -> void:
	var should_restore_music: bool = _music_triggered
	_drowned_active = false
	_drowned_sequence_running = false
	_music_triggered = false
	_music_trigger_checked = false
	_notified_seconds.clear()
	_alerted_seconds.clear()

	if should_restore_music:
		_restore_music()
	else:
		_clear_music_state()

	if owner_player == null or not is_instance_valid(owner_player):
		return

	if owner_player.has_method("finish_death_sequence"):
		owner_player.call("finish_death_sequence")
	else:
		if owner_player.has_method("set_death_state"):
			owner_player.call("set_death_state", false)
		owner_player._player_state_locked = false
		owner_player.call("set_ui_input_blocked", false)

	# Clear the active action so idle/fall takes over cleanly
	if owner_player.has_method("clear_active_action"):
		owner_player.call("clear_active_action")


# ---------------------------------------------------------------------------
# Physics: float / decelerate while drowned
# Gravity is already suppressed in SonicPlayer._apply_movement().
# ---------------------------------------------------------------------------

func _apply_drowned_physics(delta: float) -> void:
	if owner_player == null:
		return

	var v: Vector3 = owner_player.velocity

	# All-around deceleration
	var speed: float = v.length()
	if speed > 0.001:
		var decel_amount: float = min(drowned_decel * delta, speed)
		v = v.normalized() * (speed - decel_amount)

	# Decompose
	var vertical: float = get_gravity_vertical_component(v)
	var lateral: Vector3 = get_gravity_planar_component(v)

	if owner_player._head_in_water_volume:
		# Head still submerged: float upward toward surface
		vertical = clamp(vertical + drowned_float_speed * delta, -drowned_float_max_up_speed, drowned_float_max_up_speed)
	else:
		# Head at or above surface: damp vertical to zero for bobbing
		vertical = move_toward(vertical, 0.0, drowned_float_speed * delta * 4.0)

	owner_player.velocity = compose_gravity_vector(lateral, vertical)


# ---------------------------------------------------------------------------
# Music helpers
# ---------------------------------------------------------------------------

func _uses_global_drowning_presentation() -> bool:
	return _is_client_controlled_player()


func _is_post_race_protected() -> bool:
	if owner_player == null or not is_instance_valid(owner_player):
		return false
	if not owner_player.has_method("is_post_race_protected"):
		return false
	return bool(owner_player.call("is_post_race_protected"))


func _is_client_controlled_player() -> bool:
	if owner_player == null or not is_instance_valid(owner_player):
		return false
	if not owner_player._network_is_local_authority():
		return false
	if owner_player.is_in_group("NPCActor"):
		return false
	return owner_player.is_in_group("Player") or owner_player.is_in_group("player")


func _play_drowning_music() -> bool:
	if drowning_music == null:
		return false
	if get_tree() == null:
		return false
	var music_controller: MusicController = MusicController.find_active_controller(get_tree())
	if music_controller == null:
		return false
	_drowning_music_controller = music_controller
	return music_controller.request_music_override(
		_get_drowning_music_source_id(),
		drowning_music,
		drowning_music_priority,
		drowning_music_fade_in,
		drowning_music_fade_out,
		true
	)


func _restore_music() -> void:
	if _drowning_music_controller != null and is_instance_valid(_drowning_music_controller):
		_drowning_music_controller.release_music_override(
			_get_drowning_music_source_id(),
			drowning_music_fade_out,
			drowning_music_fade_out
		)
	_clear_music_state()


func _get_drowning_music_source_id() -> StringName:
	if _drowning_music_source_id == &"":
		_drowning_music_source_id = StringName("drowning_%d" % get_instance_id())
	return _drowning_music_source_id


func _clear_music_state() -> void:
	_drowning_music_controller = null


# ---------------------------------------------------------------------------
# SFX helpers
# ---------------------------------------------------------------------------

func _get_sfx_player() -> AudioStreamPlayer3D:
	if owner_player == null:
		return null
	var path: NodePath = owner_player.get("drowning_sounds_player")
	if path == null or path == NodePath(""):
		return null
	return owner_player.get_node_or_null(path) as AudioStreamPlayer3D


func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	if not _is_client_controlled_player():
		return
	var player: AudioStreamPlayer3D = _get_sfx_player()
	if player == null or not is_instance_valid(player):
		return
	player.stream = stream
	player.play()


func _get_or_create_fader() -> Node:
	if owner_player == null or get_tree() == null:
		return null
	var existing = get_tree().get_nodes_in_group("ScreenFader")
	if existing != null and existing.size() > 0:
		return existing[0]
	var fader = ScreenFader.new()
	fader.add_to_group("ScreenFader")
	var vp = owner_player.get_viewport()
	if vp != null:
		vp.add_child(fader)
	elif get_tree().current_scene != null:
		get_tree().current_scene.add_child(fader)
	else:
		owner_player.add_child(fader)
	return fader

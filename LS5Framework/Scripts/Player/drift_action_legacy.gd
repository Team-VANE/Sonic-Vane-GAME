class_name LegacyDriftAction
extends CharacterAction

@export_group("Drift")
## Enables the legacy drift ability.
@export var drift_enabled: bool = true
## Minimum lateral speed required to start drift on normal ground.
@export var drift_min_speed: float = 50.0
## Minimum lateral speed required to keep drift active (0 = use drift_min_speed).
@export var drift_exit_min_speed: float = 45.0
## Minimum turn speed required to start drift.
@export var drift_turn_speed_start_threshold: float = 0.3
## Surface angle where drift can persist below min speed.
@export var drift_steep_surface_angle_deg: float = 45.0
## Lower input angle for the legacy neutral band.
@export var drift_input_angle_split_min_deg: float = 95.0
## Upper input angle for the legacy neutral band.
@export var drift_input_angle_split_max_deg: float = 140.0
## Start of the forward input no-boost band.
@export var drift_forward_no_boost_min_deg: float = 0.0
## End of the forward input no-boost band.
@export var drift_forward_no_boost_max_deg: float = 0.3
## Extra acceleration applied by forward drift input.
@export var drift_forward_accel_boost: float = 32.0
## If true, legacy drift ignores base ground acceleration.
@export var drift_override_base_accel: bool = false
## Top speed added by legacy drift boost.
@export var drift_top_speed_offset: float = 55.0
## Braking applied by backward drift input.
@export var drift_back_brake: float = 170.0
## Multiplier applied to legacy drift turn rate.
@export var drift_turn_rate_scale: float = 30.0
## Fixed speed reference for legacy drift turning.
@export var drift_turn_speed_reference: float = 0.0
## Speed cap used by legacy drift turn math.
@export var drift_turn_speed_cap: float = 0.0
## Optional legacy drift turn curve.
@export var drift_turn_curve: Curve
## Fallback legacy drift turn rate.
@export var drift_turn_deg_per_sec: float = 390.0
## Blend speed for legacy drift turn rate.
@export var drift_turn_slerp_speed: float = 1.15
## Optional legacy drift max turn curve.
@export var drift_turn_max_curve: Curve
## Maximum legacy drift turn rate.
@export var drift_turn_max_deg_per_sec: float = 5.0
## Blend speed for legacy input turn scaling.
@export var drift_turn_input_slerp_speed: float = 80.0
## Time to ease into legacy drift turn rate.
@export var drift_turn_entry_time: float = 0.2
## Turn scale for full forward drift input.
@export var drift_turn_forward_scale: float = 0.6
## Turn scale for full backward drift input.
@export var drift_turn_back_scale: float = 3.5
## Max turn cap multiplier for full backward drift input.
@export var drift_turn_back_max_scale: float = 7.5
## Seconds used to blend drift camera and movement controls back to normal after drift ends.
@export var drift_exit_duration: float = 0.2
## Blend speed for legacy drift exit turn rate.
@export var drift_exit_turn_slerp_speed: float = 18.0
## Turn rate threshold for ending legacy drift exit ease.
@export var drift_exit_turn_snap_threshold_deg: float = 1.0

@export_subgroup("Drift Sound")
## Loop played while drifting.
@export var drift_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/drift.ogg")
## Speed where the drift loop starts fading in.
@export var drift_sound_min_speed: float = 15.0
## Speed where the drift loop reaches full pitch scaling.
@export var drift_sound_full_speed: float = 120.0
## Pitch scale used at minimum drift speed.
@export var drift_sound_pitch_min: float = 0.92
## Pitch scale used at full drift speed.
@export var drift_sound_pitch_max: float = 1.25
## Turn rate where drift loop volume starts rising.
@export var drift_sound_turn_min_deg_per_sec: float = 15.0
## Turn rate where drift loop volume reaches maximum.
@export var drift_sound_turn_full_deg_per_sec: float = 200.0
## Drift loop volume at minimum turn intensity.
@export var drift_sound_volume_min_db: float = -25.0
## Drift loop volume at full turn intensity.
@export var drift_sound_volume_max_db: float = -2.0
## Blend speed for drift loop volume changes.
@export var drift_sound_turn_lerp_speed: float = 8.0

var is_active: bool = false
var exit_active: bool = false
var exit_pending: bool = false
var exit_locked: bool = false
var turn_deg_per_sec_current: float = 0.0
var turn_input_scale_current: float = 1.0
var back_input_current: float = 0.0
var turn_entry_timer: float = 0.0
var exit_turn_deg_per_sec_current: float = 0.0
var exit_turn_deg_per_sec_start: float = 0.0
var exit_elapsed: float = 0.0
var exit_blend: float = 0.0
var turn_speed_last: float = 0.0


func _on_action_initialized() -> void:
	action_id = &"drift"
	input_action = &"ability_slot_05"
	trigger_mode = ActionTrigger.PRESSED
	continuous_update = false
	allow_when_inactive = true


func continuous_physics_update(_delta: float) -> void:
	pass


func can_use() -> bool:
	if owner_player == null:
		return false
	if not drift_enabled:
		return false
	if not owner_player._network_is_local_authority():
		return false
	if owner_player._local_pause_enabled or owner_player._ui_input_blocked or owner_player._debug_mode:
		return false
	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._rail_active or owner_player._spline_active:
		return false
	if owner_player._homing_active:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	var roll_action = _get_roll_action()
	if roll_action != null and roll_action.is_rolling:
		return false
	var spindash_action = _get_spindash_action()
	if spindash_action != null and spindash_action.is_charging:
		return false
	if owner_player._automation_lock_drift and owner_player._automation_locks_active():
		return false
	return true


func update_drift_state(
	is_attached: bool,
	slope_angle_deg: float,
	lateral_speed: float,
	current_turn_speed_deg_per_sec: float
) -> void:
	var was_active: bool = is_active
	if not can_use():
		reset_state()
		return
	if not is_attached:
		reset_state()
		return
	if not SettingsManager.is_gameplay_action_pressed("ability_slot_05"):
		if was_active:
			begin_exit_ease(true)
		return

	var steep_surface_ok: bool = slope_angle_deg >= drift_steep_surface_angle_deg
	var min_speed: float = max(drift_min_speed, 0.0)
	var exit_min: float = drift_exit_min_speed
	if exit_min <= 0.0:
		exit_min = min_speed
	elif exit_min < 0.0:
		exit_min = 0.0
	var required_speed: float = min_speed
	if was_active:
		required_speed = exit_min
	var speed_ok: bool = lateral_speed >= required_speed or steep_surface_ok
	if not speed_ok:
		if was_active:
			begin_exit_ease(true)
		return

	var turn_speed_abs: float = abs(current_turn_speed_deg_per_sec)
	var can_start: bool = true
	if drift_turn_speed_start_threshold > 0.0:
		can_start = turn_speed_abs >= drift_turn_speed_start_threshold

	if not was_active:
		if not can_start:
			return
		is_active = true
		exit_active = false
		exit_pending = false
		turn_deg_per_sec_current = 0.0
		turn_entry_timer = max(drift_turn_entry_time, 0.0)
		return

	if exit_active and can_start and not exit_locked:
		cancel_exit()


func reset_state() -> void:
	var had_drift: bool = is_active or exit_active or exit_pending
	is_active = false
	exit_active = false
	exit_pending = false
	exit_locked = false
	turn_deg_per_sec_current = 0.0
	turn_speed_last = 0.0
	turn_input_scale_current = 1.0
	back_input_current = 0.0
	turn_entry_timer = 0.0
	exit_turn_deg_per_sec_start = 0.0
	exit_elapsed = 0.0
	exit_blend = 0.0
	_stop_sfx()
	if had_drift:
		_play_drift_end_voice()


func finish_exit() -> void:
	var had_drift: bool = is_active or exit_active or exit_pending
	is_active = false
	exit_active = false
	exit_pending = false
	exit_locked = false
	turn_deg_per_sec_current = 0.0
	turn_speed_last = 0.0
	turn_input_scale_current = 1.0
	back_input_current = 0.0
	turn_entry_timer = 0.0
	exit_turn_deg_per_sec_start = 0.0
	exit_elapsed = 0.0
	exit_blend = 0.0
	_stop_sfx()
	if had_drift:
		_play_drift_end_voice()


func cancel_exit() -> void:
	exit_active = false
	exit_pending = false
	exit_locked = false
	exit_turn_deg_per_sec_start = 0.0
	exit_elapsed = 0.0
	exit_blend = 0.0


func begin_exit_ease(lock_exit: bool = true) -> void:
	if exit_active:
		if lock_exit:
			exit_locked = true
		return
	exit_active = true
	exit_pending = true
	exit_locked = lock_exit
	exit_turn_deg_per_sec_current = abs(turn_speed_last)
	exit_turn_deg_per_sec_start = exit_turn_deg_per_sec_current
	exit_elapsed = 0.0
	exit_blend = 1.0


func apply_exit_turn_ease(desired_turn_deg_per_sec: float, delta: float) -> float:
	if not exit_active:
		return desired_turn_deg_per_sec

	var target_turn: float = max(desired_turn_deg_per_sec, 0.0)
	var duration: float = max(drift_exit_duration, 0.0)
	if duration <= 0.0:
		exit_turn_deg_per_sec_current = target_turn
		exit_active = false
		exit_elapsed = 0.0
		exit_blend = 0.0
		if exit_pending:
			finish_exit()
		return target_turn

	exit_elapsed = min(exit_elapsed + max(delta, 0.0), duration)
	var progress: float = clamp(exit_elapsed / duration, 0.0, 1.0)
	exit_blend = 1.0 - progress
	exit_turn_deg_per_sec_current = lerp(exit_turn_deg_per_sec_start, target_turn, progress)

	if progress >= 1.0:
		exit_turn_deg_per_sec_current = target_turn
		exit_active = false
		exit_elapsed = 0.0
		exit_blend = 0.0
		if exit_pending:
			finish_exit()

	return exit_turn_deg_per_sec_current


func _ease_in_out_sine(t: float) -> float:
	return -(cos(PI * t) - 1.0) / 2.0


func _stop_sfx() -> void:
	if owner_player != null and owner_player.has_method("_stop_drift_sfx"):
		owner_player._stop_drift_sfx()


func _play_drift_end_voice() -> void:
	if owner_player and owner_player.has_method("play_voice_event"):
		owner_player.call("play_voice_event", &"drift_end")


func _get_roll_action():
	for a in owner_player._actions:
		if a is RollAction:
			return a
	return null


func _get_spindash_action():
	for a in owner_player._actions:
		if a is SpindashAction:
			return a
	return null

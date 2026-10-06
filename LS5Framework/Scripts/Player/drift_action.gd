class_name DriftAction
extends CharacterAction

@export_group("Drift")

@export_subgroup("Activation")
## Enables the drift ability.
@export var drift_enabled: bool = true
## Minimum lateral speed required to start drift on normal ground.
@export var drift_min_speed: float = 50.0
## Minimum lateral speed required to keep drift active (0 = use drift_min_speed).
@export var drift_exit_min_speed: float = 45.0
## Minimum side input needed to choose a drift direction.
@export var drift_input_deadzone: float = 0.25
## Surface angle (deg vs gravity-up) where drift can persist even below min speed.
@export var drift_steep_surface_angle_deg: float = 45.0

@export_subgroup("Turning")
## Locked drift turn rate before input multipliers are applied.
@export var drift_base_turn_deg_per_sec: float = 125.0
## Turn multiplier when steering into the committed drift direction.
@export var drift_tight_turn_multiplier: float = 1.45
## Turn multiplier when steering opposite the committed drift direction.
@export var drift_counter_turn_multiplier: float = 0.65
## Blend speed for input-based drift turn changes.
@export var drift_turn_input_response: float = 14.0
## Blend speed for the effective drift turn rate.
@export var drift_turn_response: float = 9.0
## Seconds needed to fully swap from one drift direction to the other.
@export var drift_direction_switch_time: float = 0.45
## Allows previous drift turn influence to carry into a direction switch.
@export var drift_direction_switch_carry_previous_influence: bool = true
## Time in seconds to ease into drift turn rate after activation.
@export var drift_turn_entry_time: float = 0.18
## Carries compatible pre-drift course turning into drift entry and uses it to resolve neutral side input.
@export var drift_entry_turn_rate_inheritance_enabled: bool = true
## Turn rate below which entry inheritance and neutral-side inference are ignored.
@export var drift_entry_turn_rate_min_deg_per_sec: float = 20.0
## Turn rate where entry inheritance reaches its full configured scale.
@export var drift_entry_turn_rate_full_deg_per_sec: float = 120.0
## Multiplier applied to the inherited pre-drift turn rate.
@export var drift_entry_turn_rate_scale: float = 1.0
## Maximum inherited drift-entry turn rate. Set to 0 to disable the cap.
@export var drift_entry_turn_rate_max_deg_per_sec: float = 180.0

@export_subgroup("Wall Collision")
## Redirects inward speed into wall-parallel speed on fresh wall contact while drifting.
@export var drift_wall_speed_transfer_enabled: bool = true
## Fraction of inward wall-entry speed transferred into wall-parallel velocity.
@export_range(0.0, 1.0, 0.01) var drift_wall_speed_transfer: float = 0.65
## Maximum wall-parallel speed added by a single wall entry. Set to 0 to disable the cap.
@export var drift_wall_speed_transfer_limit: float = 45.0
## Minimum inward wall-entry speed required for speed transfer.
@export var drift_wall_speed_transfer_min_entry_speed: float = 5.0
## Maximum absolute wall-normal alignment with player-up accepted for drift transfer.
@export_range(0.0, 1.0, 0.01) var drift_wall_speed_transfer_max_up_dot: float = 0.65

@export_subgroup("Reward")
## Fraction of entry speed above the normal run cap inherited by the drift speed target.
@export_range(0.0, 1.0, 0.01) var drift_entry_speed_inheritance: float = 1.0
## Maximum inherited entry-speed excess. Set to 0 to disable the cap.
@export var drift_entry_speed_inheritance_limit: float = 0.0
## Drifted turn angle needed for the full speed reward.
@export var drift_reward_turn_degrees: float = 180.0
## Drifted distance needed for the full speed reward on wide arcs.
@export var drift_reward_distance: float = 160.0
## Top speed added at full drift reward.
@export var drift_reward_speed_bonus: float = 38.0
## Extra acceleration added at full drift reward.
@export var drift_reward_accel: float = 55.0

@export_subgroup("Straight-Line Slowdown")
## Enables progressive slowdown while the drift path remains nearly straight.
@export var drift_straight_slowdown_enabled: bool = true
## Highest average path turn rate receiving maximum slowdown; clamped below the unpunished rate.
@export_range(0.0, 180.0, 0.1, "suffix:°/s") var drift_straight_max_punished_turn_rate: float = 15.0
## Average path turn rate where slowdown reaches zero.
@export_range(0.1, 180.0, 0.1, "suffix:°/s") var drift_straight_unpunished_turn_rate: float = 60.0
## Straight travel allowed before slowdown begins.
@export_range(0.0, 5.0, 0.05, "suffix:s") var drift_straight_grace_time: float = 0.5
## Additional straight travel required to reach full slowdown.
@export_range(0.01, 10.0, 0.05, "suffix:s") var drift_straight_ramp_time: float = 2.0
## Proportional speed drag per second at full slowdown; drift acceleration also falls to zero.
@export_range(0.0, 5.0, 0.05) var drift_straight_drag_strength: float = 0.6
## Straight travel debt removed per second of sustained turning.
@export_range(0.0, 10.0, 0.1) var drift_straight_recovery_rate: float = 2.0
## Signed path turn-rate smoothing response; alternating turns cancel before classification.
@export_range(0.1, 30.0, 0.1) var drift_straight_turn_response: float = 8.0

@export_subgroup("Combo")
## Distance traveled while drifting before another combo entry is registered.
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m") var drift_combo_distance_units: float = 12.0
## Base score awarded for each drift interval.
@export_range(0.0, 10000.0, 1.0, "or_greater") var drift_combo_score: float = 75.0
## Combo time added for each drift interval.
@export_range(0.0, 5.0, 0.05, "suffix:s") var drift_combo_timer_add_seconds: float = 0.25

@export_subgroup("Exit")
## Seconds used to blend drift camera and movement controls back to normal after drift ends.
@export var drift_exit_duration: float = 0.28
## Keeps drift influence at full strength briefly before the exit ease starts.
@export var drift_exit_delay_enabled: bool = true
## Delay before drift exit easing begins.
@export var drift_exit_delay: float = 0.065
## Curve used to ease movement and camera influence out of drift.
@export var drift_exit_ease_curve: Curve = preload("res://LS5Framework/Curves/DriftExitEase.tres")

@export_subgroup("Animation/Playback")
## Animation speed when counter-steering out of the drift.
@export var drift_anim_outward_speed_scale: float = 0.95
## Animation speed with no inward or outward steering bias.
@export var drift_anim_neutral_speed_scale: float = 0.97
## Animation speed when steering into the drift.
@export var drift_anim_inward_speed_scale: float = 1.1
## Animation speed at minimum drift movement speed.
@export var drift_anim_movement_min_scale: float = 0.9
## Animation speed at maximum drift movement speed.
@export var drift_anim_movement_max_scale: float = 1.1
## Movement speed that reaches maximum drift animation scaling.
@export var drift_anim_movement_speed_for_max: float = 150.0

@export_subgroup("Animation/Model Influence")
## Enables model Y-axis influence while drifting.
@export var drift_visual_influence_enabled: bool = true
## X/Y/Z model angles used as the base drift pose.
@export var drift_visual_offset_angles_deg: Vector3 = Vector3(0.0, 10.0, 0.0)
## X/Y/Z model angles added at full inward drift steering.
@export var drift_visual_inner_angles_deg: Vector3 = Vector3(0.0, 22.0, 0.0)
## X/Y/Z model angles added at full outward drift steering.
@export var drift_visual_outer_angles_deg: Vector3 = Vector3(0.0, 4.0, 0.0)
## Blend speed for entering drift visual influence.
@export var drift_visual_entry_lerp_speed: float = 12.0
## Blend speed used when drift visual influence is cleared outside normal exit.
@export var drift_visual_exit_lerp_speed: float = 20.0

@export_subgroup("Debug/Guides")
## Enables in-world drift guide lines in debug view.
@export var drift_debug_guides_enabled: bool = true
## Length of the in-world drift guide arrows.
@export var drift_debug_guide_length: float = 18.0
## Number of line segments used by the in-world drift arc guide.
@export var drift_debug_arc_segments: int = 8

@export_subgroup("Audio/Loop")
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
@export var drift_sound_volume_min_db: float = -16.0
## Drift loop volume at full turn intensity.
@export var drift_sound_volume_max_db: float = 0.0
## Blend speed for drift loop volume changes.
@export var drift_sound_turn_lerp_speed: float = 8.0

var is_active: bool = false
var exit_active: bool = false
var exit_pending: bool = false
var exit_locked: bool = false
var turn_deg_per_sec_current: float = 0.0
var turn_input_scale_current: float = 1.0
var back_input_current: float = 0.0
var same_input_current: float = 0.0
var turn_entry_timer: float = 0.0
var entry_turn_deg_per_sec_start: float = 0.0
var exit_turn_deg_per_sec_current: float = 0.0
var exit_turn_deg_per_sec_start: float = 0.0
var exit_elapsed: float = 0.0
var exit_blend: float = 0.0
var turn_speed_last: float = 0.0
var drift_direction: int = 0
var drift_direction_target: int = 0
var drift_direction_value: float = 0.0
var drift_direction_value_start: float = 0.0
var drift_switch_elapsed: float = 0.0
var drift_reward_turn_degrees_current: float = 0.0
var drift_reward_distance_current: float = 0.0
var drift_reward_progress: float = 0.0
var drift_speed_bonus_current: float = 0.0
var drift_entry_speed_current: float = 0.0
var drift_combo_distance_accum: float = 0.0
var drift_straight_time: float = 0.0
var drift_straight_slowdown_factor: float = 0.0
var _straight_previous_direction: Vector3 = Vector3.ZERO
var _straight_previous_up: Vector3 = Vector3.UP
var _straight_turn_rate: float = 0.0
var _wall_transfer_last_physics_frame: int = -2
var _wall_transfer_last_normal: Vector3 = Vector3.ZERO


func _on_action_initialized() -> void:
	action_id = &"drift"
	input_action = &"ability_slot_05"
	trigger_mode = ActionTrigger.PRESSED
	continuous_update = false
	allow_when_inactive = true


func continuous_physics_update(_delta: float) -> void:
	pass


func resolve_wall_collision_velocity(
	normal: Vector3,
	world_up: Vector3,
	entry_velocity: Vector3
) -> bool:
	if not drift_wall_speed_transfer_enabled or not is_active or exit_active:
		return false
	if owner_player == null:
		return false
	var resolved_normal: Vector3 = normal.normalized()
	if resolved_normal.length_squared() < 0.001:
		return false
	var up: Vector3 = owner_player._physics_up_last.normalized()
	if up.length_squared() < 0.001:
		up = owner_player.surface_normal.normalized()
	if up.length_squared() < 0.001:
		up = world_up.normalized()
	if up.length_squared() < 0.001:
		return false
	if abs(resolved_normal.dot(up)) > clamp(drift_wall_speed_transfer_max_up_dot, 0.0, 1.0):
		return false
	var planar_entry: Vector3 = entry_velocity - up * entry_velocity.dot(up)
	var inward_speed: float = max(-planar_entry.dot(resolved_normal), 0.0)
	if inward_speed < max(drift_wall_speed_transfer_min_entry_speed, 0.0):
		return false
	var physics_frame: int = Engine.get_physics_frames()
	var continuous_contact: bool = (
		physics_frame <= _wall_transfer_last_physics_frame + 1
		and _wall_transfer_last_normal.dot(resolved_normal) > 0.95
	)
	_wall_transfer_last_physics_frame = physics_frame
	_wall_transfer_last_normal = resolved_normal
	if continuous_contact:
		return false
	var tangent: Vector3 = up.cross(resolved_normal).normalized()
	if tangent.length_squared() < 0.001:
		return false
	var parallel_speed: float = planar_entry.dot(tangent)
	var transfer_direction: float = sign(parallel_speed)
	if abs(transfer_direction) < 0.001:
		var facing: Vector3 = owner_player._model_forward - up * owner_player._model_forward.dot(up)
		var drift_side: Vector3 = facing.cross(up) * float(drift_direction)
		transfer_direction = sign(drift_side.dot(tangent))
	if abs(transfer_direction) < 0.001:
		transfer_direction = 1.0
	var transferred_speed: float = inward_speed * clamp(drift_wall_speed_transfer, 0.0, 1.0)
	var transfer_limit: float = max(drift_wall_speed_transfer_limit, 0.0)
	if transfer_limit > 0.0:
		transferred_speed = min(transferred_speed, transfer_limit)
	parallel_speed += transfer_direction * transferred_speed
	var wall_up: Vector3 = up.slide(resolved_normal).normalized()
	if wall_up.length_squared() < 0.001:
		return false
	var vertical_speed: float = owner_player.velocity.dot(up)
	owner_player.velocity = (
		tangent * parallel_speed
		+ wall_up * (vertical_speed / max(wall_up.dot(up), 0.1))
	)
	return true


func get_input_prompt(_context: Dictionary = {}) -> Dictionary:
	return {}


func can_use() -> bool:
	if owner_player == null:
		return false
	if not drift_enabled:
		return false
	if not owner_player._network_is_local_authority():
		return false
	if owner_player._local_pause_enabled or owner_player._ui_input_blocked or owner_player._debug_mode:
		return false
	if owner_player.has_method("is_surface_drift_blocked") and owner_player.is_surface_drift_blocked():
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
	current_turn_speed_deg_per_sec: float,
	input_side: int = 0,
	input_strength: float = 0.0,
	delta: float = 0.0
) -> void:
	var was_active: bool = is_active
	if not can_use():
		reset_state()
		return
	if not is_attached:
		reset_state()
		return

	var drift_pressed: bool = input_action != &"" and SettingsManager.is_gameplay_action_pressed(input_action)
	if not drift_pressed:
		if was_active:
			begin_exit_ease(true)
		return

	var side: int = _normalize_side(input_side)
	var input_ok: bool = input_strength >= max(drift_input_deadzone, 0.0)
	var steep_surface_ok: bool = slope_angle_deg >= drift_steep_surface_angle_deg
	var min_speed: float = max(drift_min_speed, 0.0)
	var exit_min: float = drift_exit_min_speed
	if exit_min < 0.0:
		exit_min = 0.0
	elif exit_min <= 0.0:
		exit_min = min_speed
	var required_speed: float = min_speed
	if was_active:
		required_speed = exit_min
	var speed_ok: bool = lateral_speed >= required_speed or steep_surface_ok
	if not speed_ok:
		if was_active:
			begin_exit_ease(true)
		return

	if not was_active:
		var resolved_side: int = side if input_ok else 0
		var turn_rate_side: int = _get_entry_turn_rate_side(current_turn_speed_deg_per_sec)
		if resolved_side == 0:
			resolved_side = turn_rate_side
		if resolved_side == 0:
			return
		_start_drift(resolved_side, current_turn_speed_deg_per_sec, lateral_speed)
		return

	if exit_active:
		if side != 0 and side != drift_direction_target:
			_switch_drift_direction(side)
		cancel_exit()
	else:
		_advance_direction_switch(delta)

	turn_speed_last = current_turn_speed_deg_per_sec


func update_drift_reward(delta: float, lateral_speed: float, current_turn_speed_deg_per_sec: float) -> void:
	if not is_active or exit_active:
		return
	var dt: float = max(delta, 0.0)
	drift_reward_turn_degrees_current += abs(current_turn_speed_deg_per_sec) * dt
	drift_reward_distance_current += max(lateral_speed, 0.0) * dt
	drift_combo_distance_accum += max(lateral_speed, 0.0) * dt
	var combo_distance_interval: float = max(drift_combo_distance_units, 0.1)
	if drift_combo_distance_accum >= combo_distance_interval:
		drift_combo_distance_accum -= combo_distance_interval
		if owner_player != null and owner_player.has_method("register_combo_feat"):
			owner_player.register_combo_feat(
				&"drift",
				"Drift",
				drift_combo_score,
				drift_combo_timer_add_seconds
			)
	var turn_target: float = max(drift_reward_turn_degrees, 0.001)
	var distance_target: float = max(drift_reward_distance, 0.001)
	var turn_t: float = clamp(drift_reward_turn_degrees_current / turn_target, 0.0, 1.0)
	var distance_t: float = clamp(drift_reward_distance_current / distance_target, 0.0, 1.0)
	drift_reward_progress = max(turn_t, distance_t)
	drift_speed_bonus_current = max(drift_reward_speed_bonus, 0.0) * drift_reward_progress


func get_target_speed(base_top_speed: float) -> float:
	var base_speed: float = max(base_top_speed, 0.0)
	var entry_excess: float = max(drift_entry_speed_current - base_speed, 0.0)
	var inherited_excess: float = entry_excess * clamp(drift_entry_speed_inheritance, 0.0, 1.0)
	var inheritance_limit: float = max(drift_entry_speed_inheritance_limit, 0.0)
	if inheritance_limit > 0.0:
		inherited_excess = min(inherited_excess, inheritance_limit)
	return base_speed + inherited_excess + max(drift_speed_bonus_current, 0.0)


func switch_to_opposite_direction() -> bool:
	if not is_active or exit_active:
		return false
	if drift_direction_target == 0:
		return false
	_switch_drift_direction(-drift_direction_target)
	return true


func update_straight_line_slowdown(lateral: Vector3, up: Vector3, delta: float) -> void:
	if not drift_straight_slowdown_enabled or not is_active:
		_reset_straight_line_slowdown()
		return
	if delta <= 0.0 or up.length_squared() < 0.000001:
		return
	var tangent_up: Vector3 = up.normalized()
	var direction: Vector3 = lateral.slide(tangent_up).normalized()
	var turn_rate: float = 0.0
	if direction and _straight_previous_direction:
		var previous_direction: Vector3 = PlayerMath.basis_from_to(_straight_previous_up, tangent_up) * _straight_previous_direction
		previous_direction = previous_direction.slide(tangent_up).normalized()
		turn_rate = rad_to_deg(previous_direction.signed_angle_to(direction, tangent_up)) / delta
	_straight_previous_direction = direction
	_straight_previous_up = tangent_up
	if exit_active:
		return
	_straight_turn_rate = lerpf(_straight_turn_rate, turn_rate, 1.0 - exp(-maxf(drift_straight_turn_response, 0.1) * delta))
	var duration: float = maxf(drift_straight_grace_time, 0.0) + maxf(drift_straight_ramp_time, 0.01)
	var unpunished_rate: float = maxf(drift_straight_unpunished_turn_rate, 0.1)
	var max_punished_rate: float = clampf(drift_straight_max_punished_turn_rate, 0.0, unpunished_rate - 0.1)
	var straight_weight: float = 1.0 - clampf((absf(_straight_turn_rate) - max_punished_rate) / (unpunished_rate - max_punished_rate), 0.0, 1.0)
	if straight_weight > 0.0:
		drift_straight_time = minf(drift_straight_time + delta * straight_weight, duration)
	else:
		drift_straight_time = maxf(drift_straight_time - maxf(drift_straight_recovery_rate, 0.0) * delta, 0.0)
	var progress: float = clampf((drift_straight_time - maxf(drift_straight_grace_time, 0.0)) / maxf(drift_straight_ramp_time, 0.01), 0.0, 1.0)
	drift_straight_slowdown_factor = smoothstep(0.0, 1.0, progress) * straight_weight


func get_straight_line_acceleration_multiplier() -> float:
	if not drift_straight_slowdown_enabled or not is_active or exit_active:
		return 1.0
	return 1.0 - drift_straight_slowdown_factor


func apply_straight_line_drag(lateral: Vector3, delta: float) -> Vector3:
	if not drift_straight_slowdown_enabled or not is_active or exit_active:
		return lateral
	return lateral * exp(-maxf(drift_straight_drag_strength, 0.0) * drift_straight_slowdown_factor * maxf(delta, 0.0))


func _reset_straight_line_slowdown() -> void:
	drift_straight_time = 0.0
	drift_straight_slowdown_factor = 0.0
	_straight_previous_direction = Vector3.ZERO
	_straight_previous_up = Vector3.UP
	_straight_turn_rate = 0.0


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
	same_input_current = 0.0
	turn_entry_timer = 0.0
	entry_turn_deg_per_sec_start = 0.0
	exit_turn_deg_per_sec_start = 0.0
	exit_elapsed = 0.0
	exit_blend = 0.0
	drift_direction = 0
	drift_direction_target = 0
	drift_direction_value = 0.0
	drift_direction_value_start = 0.0
	drift_switch_elapsed = 0.0
	drift_entry_speed_current = 0.0
	_wall_transfer_last_physics_frame = -2
	_wall_transfer_last_normal = Vector3.ZERO
	drift_combo_distance_accum = 0.0
	_reset_straight_line_slowdown()
	_reset_reward()
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
	same_input_current = 0.0
	turn_entry_timer = 0.0
	entry_turn_deg_per_sec_start = 0.0
	exit_turn_deg_per_sec_start = 0.0
	exit_elapsed = 0.0
	exit_blend = 0.0
	drift_direction = 0
	drift_direction_target = 0
	drift_direction_value = 0.0
	drift_direction_value_start = 0.0
	drift_switch_elapsed = 0.0
	drift_entry_speed_current = 0.0
	_wall_transfer_last_physics_frame = -2
	_wall_transfer_last_normal = Vector3.ZERO
	drift_combo_distance_accum = 0.0
	_reset_straight_line_slowdown()
	_reset_reward()
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
	var delay: float = _get_exit_delay()
	var total_duration: float = duration + delay
	if total_duration <= 0.0:
		exit_turn_deg_per_sec_current = target_turn
		exit_active = false
		exit_elapsed = 0.0
		exit_blend = 0.0
		if exit_pending:
			finish_exit()
		return target_turn

	exit_elapsed = min(exit_elapsed + max(delta, 0.0), total_duration)
	var progress: float = 1.0
	if duration > 0.0:
		progress = clamp((exit_elapsed - delay) / duration, 0.0, 1.0)
	var eased_progress: float = _sample_exit_ease(progress)
	exit_blend = 1.0 - eased_progress
	exit_turn_deg_per_sec_current = lerp(exit_turn_deg_per_sec_start, target_turn, eased_progress)

	if exit_elapsed >= total_duration:
		exit_turn_deg_per_sec_current = target_turn
		exit_active = false
		exit_elapsed = 0.0
		exit_blend = 0.0
		if exit_pending:
			finish_exit()

	return exit_turn_deg_per_sec_current


func _start_drift(side: int, pre_drift_turn_deg_per_sec: float, entry_speed: float) -> void:
	is_active = true
	exit_active = false
	exit_pending = false
	exit_locked = false
	entry_turn_deg_per_sec_start = _get_inherited_entry_turn_rate(pre_drift_turn_deg_per_sec, side)
	turn_deg_per_sec_current = entry_turn_deg_per_sec_start
	turn_input_scale_current = 1.0
	back_input_current = 0.0
	same_input_current = 0.0
	turn_entry_timer = max(drift_turn_entry_time, 0.0)
	drift_direction = side
	drift_direction_target = side
	drift_direction_value = float(side)
	drift_direction_value_start = float(side)
	drift_switch_elapsed = max(drift_direction_switch_time, 0.0)
	drift_entry_speed_current = max(entry_speed, 0.0)
	drift_combo_distance_accum = 0.0
	_reset_straight_line_slowdown()
	_reset_reward()


func _switch_drift_direction(side: int) -> void:
	var target_side: int = _normalize_side(side)
	if target_side == 0 or target_side == drift_direction_target:
		return
	drift_direction = target_side
	drift_direction_target = target_side
	drift_direction_value_start = drift_direction_value
	turn_input_scale_current = min(turn_input_scale_current, 1.0)
	if drift_direction_switch_carry_previous_influence:
		entry_turn_deg_per_sec_start = turn_deg_per_sec_current
	else:
		entry_turn_deg_per_sec_start = 0.0
		turn_deg_per_sec_current = 0.0
		turn_speed_last = 0.0
	drift_switch_elapsed = 0.0
	_reset_reward()


func _advance_direction_switch(delta: float) -> void:
	var target_value: float = float(drift_direction_target)
	var switch_time: float = max(drift_direction_switch_time, 0.0)
	if switch_time <= 0.0:
		drift_direction_value = target_value
		drift_direction_value_start = target_value
		drift_switch_elapsed = 0.0
		return
	if is_equal_approx(drift_direction_value, target_value):
		drift_direction_value = target_value
		drift_direction_value_start = target_value
		drift_switch_elapsed = switch_time
		return
	drift_switch_elapsed = min(drift_switch_elapsed + max(delta, 0.0), switch_time)
	var progress: float = clamp(drift_switch_elapsed / switch_time, 0.0, 1.0)
	var eased: float = _ease_in_out_sine(progress)
	drift_direction_value = lerp(drift_direction_value_start, target_value, eased)


func _normalize_side(side: int) -> int:
	if side > 0:
		return 1
	if side < 0:
		return -1
	return 0


func _get_entry_turn_rate_side(pre_drift_turn_deg_per_sec: float) -> int:
	if not drift_entry_turn_rate_inheritance_enabled:
		return 0
	var min_turn_rate: float = max(drift_entry_turn_rate_min_deg_per_sec, 0.0)
	if abs(pre_drift_turn_deg_per_sec) < min_turn_rate:
		return 0
	if pre_drift_turn_deg_per_sec > 0.0:
		return 1
	if pre_drift_turn_deg_per_sec < 0.0:
		return -1
	return 0


func _get_inherited_entry_turn_rate(pre_drift_turn_deg_per_sec: float, drift_side: int) -> float:
	var turn_rate_side: int = _get_entry_turn_rate_side(pre_drift_turn_deg_per_sec)
	var normalized_drift_side: int = _normalize_side(drift_side)
	if turn_rate_side == 0 or turn_rate_side != normalized_drift_side:
		return 0.0

	var inheritance_weight: float = _get_entry_turn_rate_inheritance_weight(pre_drift_turn_deg_per_sec)
	var inherited_turn_rate: float = (
		pre_drift_turn_deg_per_sec
		* max(drift_entry_turn_rate_scale, 0.0)
		* inheritance_weight
	)
	var max_turn_rate: float = max(drift_entry_turn_rate_max_deg_per_sec, 0.0)
	if max_turn_rate > 0.0:
		inherited_turn_rate = clamp(inherited_turn_rate, -max_turn_rate, max_turn_rate)
	return inherited_turn_rate


func _get_entry_turn_rate_inheritance_weight(pre_drift_turn_deg_per_sec: float) -> float:
	var min_turn_rate: float = max(drift_entry_turn_rate_min_deg_per_sec, 0.0)
	var full_turn_rate: float = max(drift_entry_turn_rate_full_deg_per_sec, min_turn_rate + 0.001)
	var ramp: float = clamp(
		(abs(pre_drift_turn_deg_per_sec) - min_turn_rate) / (full_turn_rate - min_turn_rate),
		0.0,
		1.0
	)
	return ramp * ramp * (3.0 - 2.0 * ramp)


func _reset_reward() -> void:
	drift_reward_turn_degrees_current = 0.0
	drift_reward_distance_current = 0.0
	drift_reward_progress = 0.0
	drift_speed_bonus_current = 0.0


func _ease_in_out_sine(t: float) -> float:
	var t_clamped: float = clamp(t, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * t_clamped)


func _get_exit_delay() -> float:
	if not drift_exit_delay_enabled:
		return 0.0
	return max(drift_exit_delay, 0.0)


func _sample_exit_ease(t: float) -> float:
	var t_clamped: float = clamp(t, 0.0, 1.0)
	if drift_exit_ease_curve != null:
		return clamp(drift_exit_ease_curve.sample_baked(t_clamped), 0.0, 1.0)
	return 1.0 - pow(1.0 - t_clamped, 3.0)


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

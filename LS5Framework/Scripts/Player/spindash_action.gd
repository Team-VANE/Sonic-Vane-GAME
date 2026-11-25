class_name SpindashAction
extends CharacterAction

enum AirSpindashMode { LEGACY, DROP_DASH }

@export_group("Spindash")

@export_subgroup("Activation")
@export var spindash_enabled: bool = true
## Legacy releases diagonally in midair. Drop-Dash carries charges into the air and holds them until landing or cancellation.
@export_enum("Legacy", "Drop-Dash") var spindash_air_mode: int = AirSpindashMode.DROP_DASH
@export var spindash_charge_time_max: float = 0.9
@export var spindash_rail_charge_time_max: float = 0.9
## Time required to reach full charge after airborne Drop-Dash activation.
@export_range(0.01, 5.0, 0.01, "suffix:s") var drop_dash_charge_time_max: float = 0.45
## Gravity multiplier after releasing the airborne Drop-Dash button. Grounded and Legacy spindash are unaffected.
@export_range(0.0, 5.0, 0.05) var drop_dash_gravity_scale: float = 1.5
## Minimum upward speed applied once when releasing an airborne Drop-Dash, along player gravity-up.
@export_range(0.0, 60.0, 0.5) var drop_dash_release_pop_speed: float = 12.0
## Maximum forward speed added on airborne release with directional input. Tapers to zero at the forward speed cap. Zero disables the boost.
@export_range(0.0, 100.0, 0.5, "or_greater") var drop_dash_air_release_forward_boost: float = 20.0
## Gravity-planar speed where the airborne forward boost reaches zero. Independent of air top speed. Zero disables the boost.
@export_range(0.0, 1000.0, 1.0, "or_greater") var drop_dash_air_release_forward_speed_cap: float = 150.0
## Animation command played after releasing the airborne Drop-Dash button.
@export var drop_dash_animation_command: StringName = &"CMD_DROP_DASH"
## One-shot sound played when the airborne Drop-Dash button is released.
@export var drop_dash_air_release_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/DropDash_Airborne_Release.ogg")
## Airborne loop played alongside the release sound, until landing or cancellation.
@export var drop_dash_air_released_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/DropDash_Airborne_Released_Loop.ogg")
## Total movement speed at which the airborne loop reaches maximum intensity.
@export_range(1.0, 300.0, 1.0, "or_greater") var drop_dash_loop_full_speed: float = 150.0
## Airborne loop playback speed at rest and at full movement intensity.
@export var drop_dash_loop_pitch_range: Vector2 = Vector2(0.85, 1.7)
## Airborne loop volume offsets in decibels at rest and at full movement intensity.
@export var drop_dash_loop_volume_range_db: Vector2 = Vector2(-6.0, 5.0)
## Airborne loop high-pass cutoff frequencies at rest and at full movement intensity.
@export var drop_dash_loop_high_pass_range_hz: Vector2 = Vector2(40.0, 1800.0)
## Response rate for speed-driven loop changes. Zero applies changes immediately.
@export_range(0.0, 30.0, 0.5) var drop_dash_loop_response: float = 10.0
## Delay before the Spindash activates when its modifier slot is not held.
@export var spindash_ground_hold_time: float = 0.19
## Time before GO during which a fully charged release is buffered until the race starts.
@export_range(0.0, 1.0, 0.01, "suffix:s") var race_countdown_release_buffer_time: float = 0.2

@export_subgroup("Movement/Launch")
@export var spindash_min_launch_speed: float = 15.0
@export var spindash_max_launch_speed: float = 115.0
## Maximum charged launch speed when Drop-Dash releases on landing. Entry-speed preservation can retain a higher entry speed.
@export_range(0.0, 300.0, 0.5, "or_greater") var drop_dash_max_launch_speed: float = 115.0
@export var spindash_rail_max_launch_speed: float = 95.0
## Preserves entry speed above the charge result for Drop-Dash, or above the maximum launch speed for ground and rail spindashes.
@export var spindash_preserve_entry_speed_above_max: bool = true

@export_subgroup("Movement/Charge")
@export var spindash_charge_decel: float = 18.0
@export var spindash_charge_decel_unheld: float = 110.0
## Surface-relative speed at or below which grounded charge movement stops completely.
@export var spindash_charge_stop_speed: float = 1.0
@export var spindash_turn_penalty_disable_time: float = 0.5
@export var spindash_jump_speed: float = 30.0

@export_subgroup("Barrier Blast Overcharge")
## Fills the Barrier Blast gauge while charging beyond maximum spindash charge.
@export var spindash_barrier_blast_overcharge_enabled: bool = true
## Maximum gauge fraction supplied by spindash overcharge.
@export_range(0.0, 1.0, 0.01) var spindash_barrier_blast_overcharge_cap: float = 0.75
## Time required to fill the overcharge contribution from empty to its cap.
@export_range(0.01, 30.0, 0.01, "suffix:s") var spindash_barrier_blast_overcharge_duration: float = 5.0

@export_subgroup("Movement/Air Release")
@export var spindash_air_release_min_horizontal_speed: float = 15.0
@export var spindash_air_release_horizontal_boost: float = 8.0
@export var spindash_air_release_downward_ratio: float = 0.6

@export_subgroup("Action Chain Routes")
@export_multiline var on_spindash_jump_tooltip: String = "Route for spindash+jump combo. Typically chains to the jump action."
@export var on_spindash_jump_action: NodePath

var is_charging: bool = false
var charge_time: float = 0.0
var charge_full_played: bool = false
var release_requested: bool = false
var release_with_jump: bool = false
var release_speed: float = 0.0
var pending_release: bool = false
var pending_release_speed: float = 0.0
var turn_free_timer: float = 0.0
var entry_speed: float = 0.0
var latched_direction: Vector3 = Vector3.ZERO
var ground_hold_timer: float = 0.0
var roll_held: bool = false
var ground_action1_press_valid: bool = false
var countdown_release_buffer_open: bool = false
var countdown_release_queued: bool = false
var drop_dash_charging: bool = false
var drop_dash_released: bool = false
var air_charge_cancelled: bool = false


func _on_action_initialized() -> void:
	action_id = &"spindash"
	input_action = &"ability_slot_03"
	trigger_mode = ActionTrigger.HOLD
	continuous_update = false
	allow_when_inactive = true


func continuous_physics_update(delta: float) -> void:
	if owner_player == null:
		return
	if not owner_player.race_in_countdown and countdown_release_buffer_open and not countdown_release_queued:
		countdown_release_buffer_open = false
	if not owner_player._network_is_local_authority():
		_cancel_charge()
		return
	if owner_player._hurt_active:
		_cancel_charge()
		pending_release = false
		pending_release_speed = 0.0
		release_requested = false
		release_with_jump = false
		release_speed = 0.0
		return
	if not spindash_enabled:
		_cancel_charge()
		pending_release = false
		return
	if owner_player._local_pause_enabled or owner_player._ui_input_blocked or owner_player._debug_mode:
		_cancel_charge()
		return
	if owner_player._spline_active:
		_cancel_charge()
		return
	if _is_drift_active():
		_cancel_charge()
		ground_hold_timer = 0.0
		ground_action1_press_valid = false
		return
	if not owner_player.is_automation_action_allowed(&"spindash"):
		_cancel_charge()
		pending_release = false
		pending_release_speed = 0.0
		release_requested = false
		release_with_jump = false
		release_speed = 0.0
		return

	if owner_player._rail_active:
		if owner_player.is_post_ui_action_suppressed():
			_cancel_charge()
			return
		_update_on_rail(delta)
		return
	if owner_player._spring_align_timer > 0.0 and owner_player._spring_detached:
		_cancel_charge()
		return

	_update_standard(delta)


func _update_standard(delta: float) -> void:
	if input_action == &"":
		_cancel_charge()
		return
	if _is_drift_active():
		_cancel_charge()
		ground_hold_timer = 0.0
		ground_action1_press_valid = false
		return

	var world_up: Vector3 = get_owner_gravity_up()

	var roll_slot: StringName = owner_player.get_ability_input_slot(&"roll", &"ability_slot_04")
	var jump_slot: StringName = owner_player.get_ability_input_slot(&"jump", &"ability_slot_01")
	var roll_btn: bool = SettingsManager.is_gameplay_action_pressed(String(roll_slot))
	var action1_held: bool = SettingsManager.is_gameplay_action_pressed(String(input_action))
	var action1_released: bool = SettingsManager.is_gameplay_action_just_released(String(input_action))
	var jump_pressed: bool = SettingsManager.is_gameplay_action_just_pressed(String(jump_slot)) and not owner_player.race_in_countdown
	var on_ground: bool = owner_player.attached
	var hold_time: float = max(spindash_ground_hold_time, 0.0)
	roll_held = roll_btn
	if not action1_held:
		air_charge_cancelled = false

	if pending_release and owner_player.attached:
		release_requested = true
		release_speed = pending_release_speed
		release_with_jump = false
		pending_release = false
		pending_release_speed = 0.0
		owner_player._play_spindash_release_sfx()

	if is_charging:
		transition_to_airborne_charge()
		if drop_dash_charging and on_ground:
			_trigger_release(false)
			return
		if drop_dash_charging and not action1_held:
			_release_drop_dash()
		var roll_action = _get_roll_action()
		if roll_action != null and not roll_action.is_rolling:
			roll_action.is_rolling = true
			roll_action._notify_roll_changed(true)

		if _process_countdown_release_buffer(action1_released):
			return
		if (
			jump_pressed
			and owner_player.attached
			and not owner_player.is_surface_jump_blocked()
		):
			_perform_spindash_jump(world_up)
			return
		if on_ground and (action1_released or not action1_held):
			_trigger_release(false)
			return
		if not on_ground and action1_released and not drop_dash_charging:
			_apply_air_release(world_up)
			return

		if action1_held or drop_dash_charging:
			_advance_charge(delta, get_max_charge_time())

		if not charge_full_played and get_charge_ratio() >= 1.0:
			charge_full_played = true
			owner_player._play_spindash_charge_full_sfx()

		owner_player._start_spindash_loop_sfx()
		return

	if not _can_start():
		ground_hold_timer = 0.0
		ground_action1_press_valid = false
		return

	if owner_player.is_ability_binding_triggered(action_id, input_action, &"hold", hold_time) and not _roll_route_locked():
		_start_charge()


func _update_on_rail(delta: float) -> void:
	if input_action == &"":
		_cancel_charge()
		return
	if not owner_player.is_automation_action_allowed(&"spindash"):
		_cancel_charge()
		pending_release = false
		pending_release_speed = 0.0
		release_requested = false
		release_with_jump = false
		release_speed = 0.0
		ground_hold_timer = 0.0
		return

	var roll_slot: StringName = owner_player.get_ability_input_slot(&"roll", &"ability_slot_04")
	var roll_btn: bool = SettingsManager.is_gameplay_action_pressed(String(roll_slot))
	var action1_held: bool = SettingsManager.is_gameplay_action_pressed(String(input_action))
	var action1_released: bool = SettingsManager.is_gameplay_action_just_released(String(input_action))
	var hold_time: float = max(spindash_ground_hold_time, 0.0)
	roll_held = roll_btn

	if pending_release:
		release_requested = true
		release_speed = pending_release_speed
		release_with_jump = false
		pending_release = false
		pending_release_speed = 0.0
		owner_player._play_spindash_release_sfx()

	if is_charging:
		if drop_dash_charging:
			_trigger_release(false)
			return
		if _process_countdown_release_buffer(action1_released):
			return
		if action1_released or not action1_held:
			_trigger_release(false)
			return

		_advance_charge(delta, spindash_rail_charge_time_max)
		if not charge_full_played and get_charge_ratio() >= 1.0:
			charge_full_played = true
			owner_player._play_spindash_charge_full_sfx()
		owner_player._start_spindash_loop_sfx()
		return

	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0 or owner_player._spring_align_timer > 0.0:
		ground_hold_timer = 0.0
		ground_action1_press_valid = false
		return
	if owner_player.is_ability_binding_triggered(action_id, input_action, &"hold", hold_time) and not _roll_route_locked():
		_start_charge()


func transition_to_airborne_charge() -> bool:
	if (
		not is_charging or drop_dash_charging or spindash_air_mode != AirSpindashMode.DROP_DASH
		or owner_player.attached or owner_player._rail_active
	):
		return false
	var charge_ratio: float = get_charge_ratio()
	drop_dash_charging = true
	charge_time = charge_ratio * maxf(drop_dash_charge_time_max, 0.0)
	return true


func _release_drop_dash() -> void:
	if not is_charging or not drop_dash_charging or drop_dash_released or owner_player.attached:
		return
	drop_dash_released = true
	owner_player._play_drop_dash_air_release_sfx()
	var up: Vector3 = get_owner_gravity_up()
	var upward_speed: float = owner_player.velocity.dot(up)
	var forward: Vector3 = get_air_release_input_direction()
	owner_player.velocity += forward * get_air_release_forward_boost()
	owner_player.velocity += up * maxf(drop_dash_release_pop_speed - upward_speed, 0.0)
	owner_player._trigger_anim_command_immediate(drop_dash_animation_command)
	var rig: Node3D = owner_player.camera_rig
	if is_instance_valid(rig) and rig.has_method("play_drop_dash_release_feedback"):
		rig.call("play_drop_dash_release_feedback", owner_player)


func get_air_release_input_direction() -> Vector3:
	var input_direction: Vector3 = owner_player._control_forward * owner_player._move_input.y + owner_player._control_right * owner_player._move_input.x
	return input_direction.slide(get_owner_gravity_up()).normalized()


func get_air_release_forward_boost() -> float:
	var input_strength: float = clampf(owner_player._move_input.length(), 0.0, 1.0)
	var up: Vector3 = get_owner_gravity_up()
	if input_strength <= 0.001 or get_air_release_input_direction().is_zero_approx():
		return 0.0
	var top_speed: float = drop_dash_air_release_forward_speed_cap
	if top_speed <= 0.0:
		return 0.0
	var current_speed: float = owner_player.velocity.slide(up).length()
	var strength: float = clampf(1.0 - current_speed / top_speed, 0.0, 1.0)
	return minf(maxf(drop_dash_air_release_forward_boost, 0.0) * strength * input_strength, maxf(top_speed - current_speed, 0.0))


func get_drop_dash_gravity_scale() -> float:
	return maxf(drop_dash_gravity_scale, 0.0) if is_charging and drop_dash_charging and drop_dash_released else 1.0


func get_charge_animation_command() -> StringName:
	return drop_dash_animation_command if drop_dash_charging and drop_dash_released else &"CMD_SPINDASH"


func get_max_charge_time() -> float:
	if drop_dash_charging:
		return drop_dash_charge_time_max
	var charge_max: float = spindash_charge_time_max
	if owner_player._rail_active:
		charge_max = spindash_rail_charge_time_max
	return charge_max


func get_charge_ratio() -> float:
	var charge_max: float = get_max_charge_time()
	if charge_max <= 0.0:
		return 1.0
	return clamp(charge_time / charge_max, 0.0, 1.0)


func blocks_external_barrier_blast_gain() -> bool:
	if not spindash_barrier_blast_overcharge_enabled or not is_charging:
		return false
	if owner_player == null or not is_instance_valid(owner_player) or not owner_player.barrier_blast_enabled:
		return false
	var gauge_cap: float = clamp(spindash_barrier_blast_overcharge_cap, 0.0, 1.0)
	if gauge_cap <= 0.0 or owner_player._barrier_blast_gauge >= gauge_cap:
		return false
	var charge_max: float = get_max_charge_time()
	return charge_time >= max(charge_max, 0.0)


func _advance_charge(delta: float, maximum_charge_time: float) -> void:
	var charge_delta: float = max(delta, 0.0)
	var charge_limit: float = max(maximum_charge_time, 0.0)
	var uncapped_charge_time: float = charge_time + charge_delta
	charge_time = min(uncapped_charge_time, charge_limit)
	var overcharge_delta: float = max(uncapped_charge_time - charge_limit, 0.0)
	_charge_barrier_blast(overcharge_delta)


func _charge_barrier_blast(delta: float) -> void:
	if not spindash_barrier_blast_overcharge_enabled or delta <= 0.0:
		return
	if owner_player == null or not owner_player.barrier_blast_enabled:
		return
	var gauge_cap: float = clamp(spindash_barrier_blast_overcharge_cap, 0.0, 1.0)
	if gauge_cap <= 0.0 or owner_player._barrier_blast_gauge >= gauge_cap:
		return
	var fill_duration: float = max(spindash_barrier_blast_overcharge_duration, 0.01)
	var fill_rate: float = gauge_cap / fill_duration
	owner_player._barrier_blast_gauge = min(
		owner_player._barrier_blast_gauge + fill_rate * delta,
		gauge_cap
	)
	owner_player._barrier_blast_deplete_grace_timer = max(
		owner_player._barrier_blast_deplete_grace_timer,
		max(owner_player.barrier_blast_deplete_grace_time, 0.0)
	)


func get_release_speed() -> float:
	var min_speed: float = max(spindash_min_launch_speed, 0.0)
	var max_speed: float = spindash_max_launch_speed
	var releasing_drop_dash: bool = drop_dash_charging and not owner_player._rail_active
	if owner_player._rail_active:
		max_speed = spindash_rail_max_launch_speed
	elif releasing_drop_dash:
		max_speed = drop_dash_max_launch_speed
	max_speed = max(max_speed, min_speed)
	var charged_speed: float = lerp(min_speed, max_speed, get_charge_ratio())
	var preservation_threshold: float = charged_speed if releasing_drop_dash else max_speed
	if spindash_preserve_entry_speed_above_max and entry_speed > preservation_threshold:
		return entry_speed
	return charged_speed


func _start_charge() -> void:
	if owner_player._active_action is SkydiveAction:
		owner_player.clear_active_action()
		owner_player.activate_neutral_air_action({"reason": &"spindash_charge", "source_action": &"skydive"})
	if owner_player.has_method("cancel_bounce_stomp_for_action"):
		owner_player.cancel_bounce_stomp_for_action()
	is_charging = true
	drop_dash_released = false
	drop_dash_charging = spindash_air_mode == AirSpindashMode.DROP_DASH and not owner_player.attached and not owner_player._rail_active
	charge_time = 0.0
	charge_full_played = false
	release_requested = false
	release_with_jump = false
	release_speed = 0.0
	pending_release = false
	pending_release_speed = 0.0
	latched_direction = Vector3.ZERO
	ground_hold_timer = 0.0
	ground_action1_press_valid = false
	countdown_release_queued = false

	var roll_action = _get_roll_action()
	if not owner_player._rail_active and not owner_player._rail_switch_active and roll_action != null and not roll_action.is_rolling:
		roll_action.is_rolling = true
		roll_action._notify_roll_changed(true)

	var lateral: Vector3 = get_gravity_planar_component(owner_player.velocity)
	entry_speed = lateral.length()

	if owner_player._rail_active:
		entry_speed = abs(owner_player._rail_speed)
		owner_player._trigger_anim_command_immediate(&"CMD_SPINDASHRAIL")
	else:
		owner_player._trigger_anim_command_immediate(&"CMD_SPINDASH")

	owner_player._start_spindash_loop_sfx()


func _cancel_charge() -> void:
	air_charge_cancelled = air_charge_cancelled or drop_dash_charging
	drop_dash_charging = false
	drop_dash_released = false
	countdown_release_buffer_open = false
	countdown_release_queued = false
	if not is_charging:
		return
	is_charging = false
	charge_time = 0.0
	charge_full_played = false
	entry_speed = 0.0
	latched_direction = Vector3.ZERO
	ground_hold_timer = 0.0
	roll_held = false
	ground_action1_press_valid = false
	owner_player._stop_spindash_loop_sfx()


func reset_state() -> void:
	drop_dash_charging = false
	drop_dash_released = false
	air_charge_cancelled = false
	is_charging = false
	charge_time = 0.0
	charge_full_played = false
	release_requested = false
	release_with_jump = false
	release_speed = 0.0
	pending_release = false
	pending_release_speed = 0.0
	turn_free_timer = 0.0
	entry_speed = 0.0
	latched_direction = Vector3.ZERO
	ground_hold_timer = 0.0
	roll_held = false
	ground_action1_press_valid = false
	countdown_release_buffer_open = false
	countdown_release_queued = false
	owner_player._stop_spindash_loop_sfx()


func set_race_countdown_release_buffer_open(enabled: bool) -> void:
	countdown_release_buffer_open = enabled
	if not enabled:
		countdown_release_queued = false


func _process_countdown_release_buffer(release_pressed: bool) -> bool:
	if countdown_release_queued:
		if owner_player.race_in_countdown:
			return true
		countdown_release_queued = false
		countdown_release_buffer_open = false
		if owner_player.race_active:
			_trigger_release(false)
			return true
	if (
		countdown_release_buffer_open
		and owner_player.race_in_countdown
		and release_pressed
		and get_charge_ratio() >= 1.0
	):
		countdown_release_queued = true
		return true
	return false


func _trigger_release(with_jump: bool) -> void:
	var speed: float = get_release_speed()
	air_charge_cancelled = air_charge_cancelled or drop_dash_charging
	drop_dash_charging = false
	drop_dash_released = false
	is_charging = false
	charge_time = 0.0
	charge_full_played = false
	owner_player._stop_spindash_loop_sfx()

	if owner_player.attached:
		release_requested = true
		release_speed = speed
		release_with_jump = with_jump
		if with_jump:
			owner_player.queue_jump()
		owner_player._play_spindash_release_sfx()
	else:
		pending_release = true
		pending_release_speed = speed
	ground_action1_press_valid = false
	if not with_jump:
		emit_profile_route_event(
			CharacterProfileManager.ROUTE_EVENT_COMPLETED,
			{"reason": &"spindash_completed", "source_action": action_id}
		)


func _perform_spindash_jump(world_up: Vector3) -> void:
	_trigger_release(true)

	if execute_manual_route(&"spindash_jump", {"reason": &"spindash_jump", "source_action": action_id}):
		return

	if on_spindash_jump_action != NodePath():
		execute_routed_action(
			on_spindash_jump_action,
			{"reason": &"spindash_jump", "source_action": action_id}
		)


func _apply_air_release(world_up: Vector3) -> void:
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = get_owner_gravity_up()
	var current_velocity: Vector3 = owner_player.velocity
	var current_horizontal: Vector3 = get_gravity_planar_component(current_velocity)
	var current_horizontal_speed: float = current_horizontal.length()
	var speed: float = get_release_speed()
	var min_horizontal: float = max(spindash_air_release_min_horizontal_speed, 0.0)
	var horizontal_boost: float = max(spindash_air_release_horizontal_boost, 0.0)
	var horizontal_target_speed: float = max(speed, current_horizontal_speed)
	if current_horizontal_speed < min_horizontal:
		horizontal_target_speed = max(horizontal_target_speed, min_horizontal + horizontal_boost)
	var forward_dir: Vector3 = owner_player._get_spindash_release_dir(up, current_horizontal)
	var horizontal_velocity: Vector3 = forward_dir * horizontal_target_speed
	var downward_ratio: float = max(spindash_air_release_downward_ratio, 0.0)
	var downward_speed: float = horizontal_target_speed * downward_ratio
	var vertical_target: float = -downward_speed
	var current_vertical: float = get_gravity_vertical_component(current_velocity)
	if current_vertical < vertical_target:
		vertical_target = current_vertical
	var target_velocity: Vector3 = compose_gravity_vector(horizontal_velocity, vertical_target)
	var current_speed: float = current_velocity.length()
	var target_speed: float = target_velocity.length()
	if target_speed > 0.001 and target_speed < current_speed:
		target_velocity = target_velocity.normalized() * current_speed
	owner_player.velocity = target_velocity
	owner_player._water_reattach_cooldown_timer = maxf(owner_player._water_reattach_cooldown_timer, 0.4)

	is_charging = false
	charge_time = 0.0
	charge_full_played = false
	release_requested = false
	release_with_jump = false
	release_speed = 0.0
	pending_release = false
	pending_release_speed = 0.0
	latched_direction = Vector3.ZERO
	ground_hold_timer = 0.0
	roll_held = false
	ground_action1_press_valid = false
	turn_free_timer = max(spindash_turn_penalty_disable_time, 0.0)
	owner_player._play_spindash_release_sfx()
	emit_profile_route_event(
		CharacterProfileManager.ROUTE_EVENT_COMPLETED,
		{"reason": &"spindash_completed", "source_action": action_id}
	)


func get_input_prompt_stage() -> InputPromptStage:
	return InputPromptStage.AFTER_PREEMPTIVE_ROUTES


func get_input_prompt(_context: Dictionary = {}) -> Dictionary:
	if not owner_player or not enabled or not input_prompt_enabled or not spindash_enabled:
		return {}
	if is_charging:
		if drop_dash_charging:
			return {}
		return {"label": input_prompt_name if input_prompt_name else "Launch Spindash", "gesture": &"release"}
	if not _can_start() or _roll_route_locked():
		return {}
	if owner_player._ability_input_router and owner_player._ability_input_router.get_gesture(action_id, &"hold") == &"hold" and owner_player._ability_input_router.is_binding_hold_modifier_pressed(action_id, input_action):
		return {"label": input_prompt_name, "gesture": &"press", "blocked_gestures": [&"tap", &"hold"]}
	return {"label": input_prompt_name}


func _can_start() -> bool:
	if air_charge_cancelled:
		return false
	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._rail_active or owner_player._spline_active:
		return false
	if owner_player._homing_active:
		return false
	if _is_drift_active():
		return false
	return true


func _is_drift_active() -> bool:
	if owner_player == null:
		return false
	return bool(owner_player.get("_drift_active")) or bool(owner_player.get("_drift_exit_active"))


func _roll_route_locked() -> bool:
	if owner_player == null:
		return false
	return float(owner_player.get("_spindash_roll_route_lockout_timer")) > 0.0


func _get_roll_action():
	for a in owner_player._actions:
		if a is RollAction:
			return a
	return null

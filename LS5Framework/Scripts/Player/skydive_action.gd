class_name SkydiveAction
extends CharacterAbility

enum SkydiveState {
	NONE,
	DIVE,
	GLIDE,
}

@export_group("Skydive")

@export_subgroup("Activation")
## Enables the skydive ability.
@export var skydive_enabled: bool = true

@export_subgroup("Movement/Dive")
## Gravity multiplier applied while holding the assigned input slot in the air.
@export var dive_gravity_multiplier: float = 2.6
## Maximum downward speed while diving.
@export var dive_max_down_speed: float = 220.0
## Dive time needed for full glide effect.
@export var dive_max_effect_time: float = 1.0
## Dive hold time required before release transitions into glide.
@export var dive_cancel_time: float = 0.4

@export_subgroup("Movement/Glide")
## Downward angle from forward used to score dive speed for glide.
@export var glide_down_forward_angle_deg: float = 62.0
## Multiplier applied to scored dive speed before lift is calculated.
@export var glide_effect_speed_multiplier: float = 1.0
## Maximum scored speed available to the glide.
@export var glide_max_effect_speed: float = 160.0
## Power applied to angle alignment when scoring the dive.
@export var glide_angle_alignment_power: float = 1.25
## Duration of the glide velocity blend.
@export var glide_duration: float = 1.2
## Air turn rate used during full lift effect.
@export var glide_lift_turn_angle_deg: float = 50.0
## Portion of scored speed converted into upward lift.
@export var glide_vertical_lift_multiplier: float = 0.3
## Portion of scored speed converted into forward speed.
@export var glide_horizontal_speed_multiplier: float = 0.58
## Maximum upward speed the glide can produce.
@export var glide_max_up_speed: float = 4.2
## Maximum falling speed after full lift is applied.
@export var glide_max_fall_speed_after_lift: float = 54.0
## Maximum horizontal speed the glide can target.
@export var glide_max_horizontal_speed: float = 168.0
## Sideways speed retained when leveling into the glide.
@export_range(0.0, 1.0, 0.01) var glide_side_speed_retention: float = 0.35
## Roll-spindash lockout applied when rolling out of skydive.
@export var roll_spindash_lockout: float = 0.6

@export_subgroup("Combo")
## Distance traveled while skydiving before another combo entry is registered.
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m") var skydive_combo_distance_units: float = 12.0
## Base score awarded for each skydive interval.
@export_range(0.0, 10000.0, 1.0, "or_greater") var skydive_combo_score: float = 75.0
## Combo time added for each skydive interval.
@export_range(0.0, 5.0, 0.05, "suffix:s") var skydive_combo_timer_add_seconds: float = 0.25

@export_subgroup("Action Chain Routes")
@export_multiline var on_roll_action_tooltip: String = "Route used when roll is held during skydive."
@export var on_roll_action: NodePath

var state: int = SkydiveState.NONE
var dive_elapsed: float = 0.0
var glide_elapsed: float = 0.0
var glide_start_velocity: Vector3 = Vector3.ZERO
var glide_target_velocity: Vector3 = Vector3.ZERO
var glide_lift_effect_strength: float = 0.0
var glide_frame_up: Vector3 = Vector3.ZERO
var skydive_combo_distance_accum: float = 0.0


func _on_action_initialized() -> void:
	action_id = &"skydive"
	input_action = &"ability_slot_02"
	trigger_mode = ActionTrigger.HOLD
	allow_when_inactive = true


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if not enabled or not skydive_enabled:
		return false
	if owner_player.has_method("is_insta_shield_input_consumed") and owner_player.is_insta_shield_input_consumed():
		return false
	if owner_player.attached:
		return false
	if owner_player.rolling and not (bool(_context.get("input_prompt", false)) and bool(_context.get("input_prompt_clear_active", false))):
		return false
	if owner_player.has_method("get_current_action_id") and owner_player.get_current_action_id() == &"propeller_flight":
		return false
	if owner_player._hurt_active:
		return false
	if owner_player._rail_active or owner_player._spline_active:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._spring_action_lock_timer > 0.0:
		return false
	if owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._spindash_charging:
		return false
	if owner_player._homing_active:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	return true


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if not activate(context):
		return false
	return true


func is_flight_action() -> bool:
	return true


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if input_name != input_action:
		return false
	if should_trigger_from_input(input_name, mode):
		return execute({"reason": &"skydive_input"})
	if mode == ActionTrigger.PRESSED and _can_reenter_from_terminal_animation():
		return execute({"reason": &"skydive_terminal_reenter"})
	return false


func on_action_enter(_context: Dictionary = {}) -> void:
	skydive_combo_distance_accum = 0.0
	_end_airborne_torque_for_skydive()
	_start_dive()


func on_action_exit(_next_action: CharacterAction) -> void:
	state = SkydiveState.NONE
	dive_elapsed = 0.0
	glide_elapsed = 0.0
	glide_start_velocity = Vector3.ZERO
	glide_target_velocity = Vector3.ZERO
	glide_lift_effect_strength = 0.0
	glide_frame_up = Vector3.ZERO
	skydive_combo_distance_accum = 0.0


func physics_update_action(delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		_clear_to_neutral_air()
		return
	if _try_route_roll():
		return
	_update_skydive_combo(delta)
	if state == SkydiveState.DIVE:
		_update_dive(delta)
		return
	if state == SkydiveState.GLIDE:
		_update_glide(delta)
		return
	_clear_to_neutral_air()


func _update_skydive_combo(delta: float) -> void:
	if state == SkydiveState.NONE:
		return
	var distance_delta: float = owner_player.velocity.length() * maxf(owner_player.get_movement_delta(delta), 0.0)
	skydive_combo_distance_accum += distance_delta
	var distance_interval: float = maxf(skydive_combo_distance_units, 0.1)
	if skydive_combo_distance_accum < distance_interval:
		return
	skydive_combo_distance_accum -= distance_interval
	if owner_player.has_method("register_combo_feat"):
		owner_player.register_combo_feat(
			&"skydive",
			"Skydive",
			skydive_combo_score,
			skydive_combo_timer_add_seconds
		)


func _start_dive() -> void:
	var anim_state_name: StringName = &"Skydive_Enter"
	var entering_from_glide: bool = state == SkydiveState.GLIDE
	if entering_from_glide:
		anim_state_name = &"Skydive_Glide_To_Dive"
	state = SkydiveState.DIVE
	dive_elapsed = 0.0
	glide_elapsed = 0.0
	glide_start_velocity = Vector3.ZERO
	glide_target_velocity = Vector3.ZERO
	glide_lift_effect_strength = 0.0
	glide_frame_up = _get_gravity_up()
	if not entering_from_glide:
		_request_skydive_command()
	_request_skydive_anim(anim_state_name)
	if owner_player != null and owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()


func _update_dive(delta: float) -> void:
	var dive_input_held: bool = input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action))
	if owner_player != null and owner_player.has_method("is_ability_binding_pressed"):
		dive_input_held = bool(owner_player.call("is_ability_binding_pressed", action_id, input_action))
	if not dive_input_held:
		if dive_elapsed < max(dive_cancel_time, 0.0):
			_cancel_to_neutral_air()
			return
		_start_glide()
		return

	dive_elapsed += max(delta, 0.0)
	var up: Vector3 = _get_gravity_up()
	var velocity: Vector3 = owner_player.velocity
	var extra_gravity_multiplier: float = max(dive_gravity_multiplier - 1.0, 0.0)
	velocity += get_owner_gravity_acceleration_vector() * extra_gravity_multiplier * owner_player.get_movement_delta(delta)
	velocity = _limit_down_speed(velocity, up, dive_max_down_speed)
	owner_player.velocity = velocity


func _start_glide() -> void:
	state = SkydiveState.GLIDE
	glide_elapsed = 0.0
	glide_start_velocity = owner_player.velocity
	glide_frame_up = _get_gravity_up()
	glide_target_velocity = _calculate_glide_target(glide_start_velocity)
	_request_skydive_anim(&"Skydive_Dive_To_Glide")


func _update_glide(delta: float) -> void:
	var dive_input_just_pressed: bool = input_action != &"" and SettingsManager.is_gameplay_action_just_pressed(String(input_action))
	if owner_player != null and owner_player.has_method("is_ability_binding_just_pressed"):
		dive_input_just_pressed = bool(owner_player.call("is_ability_binding_just_pressed", action_id, input_action))
	if dive_input_just_pressed:
		_start_dive()
		return
	_update_glide_gravity_frame()
	var duration: float = max(glide_duration, 0.001)
	glide_elapsed = min(glide_elapsed + max(delta, 0.0), duration)
	var progress: float = clamp(glide_elapsed / duration, 0.0, 1.0)
	var blend: float = _ease_in_out_sine(progress)
	_apply_glide_turn(owner_player.get_movement_delta(delta), blend)
	owner_player.velocity = glide_start_velocity.lerp(glide_target_velocity, blend)
	if glide_elapsed >= duration:
		_clear_to_neutral_air()


func _calculate_glide_target(start_velocity: Vector3) -> Vector3:
	var up: Vector3 = _get_gravity_up()
	var forward: Vector3 = _get_forward_for_glide(start_velocity, up)
	var angle_rad: float = deg_to_rad(clamp(glide_down_forward_angle_deg, 0.0, 89.0))
	var scored_direction: Vector3 = (forward * cos(angle_rad) - up * sin(angle_rad)).normalized()
	var speed: float = start_velocity.length()
	var alignment: float = 0.0
	if speed > 0.001:
		alignment = clamp(start_velocity.normalized().dot(scored_direction), 0.0, 1.0)
	alignment = pow(alignment, max(glide_angle_alignment_power, 0.001))
	var speed_toward_angle: float = max(start_velocity.dot(scored_direction), 0.0)
	var time_effect: float = clamp(dive_elapsed / max(dive_max_effect_time, 0.001), 0.0, 1.0)
	time_effect = _ease_out_quad(time_effect)
	var effect_speed: float = speed_toward_angle * alignment * time_effect * max(glide_effect_speed_multiplier, 0.0)
	effect_speed = min(effect_speed, max(glide_max_effect_speed, 0.0))
	var effect_denom: float = max(glide_max_effect_speed, 0.001)
	glide_lift_effect_strength = clamp(effect_speed / effect_denom, 0.0, 1.0)

	var vertical: float = get_gravity_vertical_component(start_velocity)
	var horizontal: Vector3 = get_gravity_planar_component(start_velocity)
	var side_velocity: Vector3 = horizontal - forward * horizontal.dot(forward)
	side_velocity *= clamp(glide_side_speed_retention, 0.0, 1.0)

	var target_vertical: float = vertical + effect_speed * max(glide_vertical_lift_multiplier, 0.0)
	target_vertical = clamp(
		target_vertical,
		-max(glide_max_fall_speed_after_lift, 0.0),
		max(glide_max_up_speed, 0.0)
	)

	var current_forward_speed: float = max(horizontal.dot(forward), 0.0)
	var target_forward_speed: float = current_forward_speed + effect_speed * max(glide_horizontal_speed_multiplier, 0.0)
	target_forward_speed = min(target_forward_speed, max(glide_max_horizontal_speed, 0.0))
	return compose_gravity_vector(forward * target_forward_speed + side_velocity, target_vertical)


func _apply_glide_turn(delta: float, lift_blend: float) -> void:
	if owner_player == null:
		return
	if delta <= 0.0:
		return
	var input_dir: Vector3 = _get_owner_move_direction()
	if input_dir.length() < 0.001:
		return
	input_dir = get_gravity_planar_component(input_dir)
	if input_dir.length() < 0.001:
		return
	input_dir = input_dir.normalized()

	var vertical: float = get_gravity_vertical_component(glide_target_velocity)
	var lateral: Vector3 = get_gravity_planar_component(glide_target_velocity)
	var lateral_speed: float = lateral.length()
	if lateral_speed < 0.001:
		return

	var base_turn_deg: float = _get_owner_air_turn_angle(lateral_speed)
	var lift_t: float = clamp(glide_lift_effect_strength * clamp(lift_blend, 0.0, 1.0), 0.0, 1.0)
	var turn_deg: float = lerp(base_turn_deg, max(glide_lift_turn_angle_deg, 0.0), lift_t)
	var max_step_rad: float = deg_to_rad(max(turn_deg, 0.0)) * delta
	if max_step_rad <= 0.0:
		return

	var lateral_dir: Vector3 = lateral / lateral_speed
	var angle_rad: float = acos(clamp(lateral_dir.dot(input_dir), -1.0, 1.0))
	if angle_rad <= 0.001:
		return
	var turn_t: float = min(1.0, max_step_rad / angle_rad)
	var turned_dir: Vector3 = lateral_dir.slerp(input_dir, turn_t).normalized()
	glide_target_velocity = compose_gravity_vector(turned_dir * lateral_speed, vertical)


func _get_owner_move_direction() -> Vector3:
	if owner_player == null:
		return Vector3.ZERO
	if owner_player.has_method("get_move_direction"):
		return owner_player.get_move_direction()
	return owner_player._move_direction


func _get_owner_air_turn_angle(lateral_speed: float) -> float:
	if owner_player == null:
		return 0.0
	if owner_player.has_method("_sample_curve_by_speed"):
		return max(float(owner_player.call("_sample_curve_by_speed", owner_player.air_turn_angle_curve, lateral_speed, 720.0)), 0.0)
	return 720.0


func _try_route_roll() -> bool:
	var roll_slot: StringName = &"ability_slot_04"
	if owner_player.has_method("get_ability_input_slot"):
		roll_slot = owner_player.get_ability_input_slot(&"roll", roll_slot)
	if owner_player.has_method("ability_binding_uses_slot") and owner_player.has_method("is_ability_binding_pressed"):
		var roll_contributes_to_dive: bool = bool(owner_player.call("ability_binding_uses_slot", action_id, roll_slot, input_action))
		if roll_contributes_to_dive and bool(owner_player.call("is_ability_binding_pressed", action_id, input_action)):
			return false
	if not SettingsManager.is_gameplay_action_pressed(String(roll_slot)):
		return false
	var roll_action: CharacterAction = _get_roll_action()
	if roll_action == null:
		return false
	if not roll_action.execute({"reason": &"skydive_roll", "source_action": action_id}):
		return false
	if owner_player.has_method("set_spindash_roll_route_lockout"):
		owner_player.set_spindash_roll_route_lockout(roll_spindash_lockout)
	return true


func _get_roll_action() -> CharacterAction:
	if on_roll_action != NodePath() and has_node(on_roll_action):
		var roll_node: Node = get_node(on_roll_action)
		if roll_node is CharacterAction:
			return roll_node
	for action in owner_player._actions:
		if action is RollAction:
			return action
	return null


func _get_gravity_up() -> Vector3:
	return get_owner_gravity_up()


func _update_glide_gravity_frame() -> void:
	var current_up: Vector3 = _get_gravity_up()
	if glide_frame_up.length() < 0.001:
		glide_frame_up = current_up
		return
	glide_start_velocity = rotate_gravity_frame_vector(glide_start_velocity, glide_frame_up, current_up)
	glide_target_velocity = rotate_gravity_frame_vector(glide_target_velocity, glide_frame_up, current_up)
	glide_frame_up = current_up


func _get_forward_for_glide(velocity: Vector3, up: Vector3) -> Vector3:
	var horizontal: Vector3 = get_gravity_planar_component(velocity)
	if horizontal.length() > 0.001:
		return horizontal.normalized()
	var model_forward: Vector3 = owner_player._model_forward
	model_forward -= up * model_forward.dot(up)
	if model_forward.length() > 0.001:
		return model_forward.normalized()
	return -owner_player.global_transform.basis.z.slide(up).normalized()


func _limit_down_speed(velocity: Vector3, up: Vector3, max_down_speed: float) -> Vector3:
	var down_limit: float = max(max_down_speed, 0.0)
	if down_limit <= 0.0:
		return velocity
	var vertical: float = get_gravity_vertical_component(velocity)
	if vertical >= -down_limit:
		return velocity
	return velocity + up * (-down_limit - vertical)


func _clear_to_neutral_air() -> void:
	state = SkydiveState.NONE
	glide_lift_effect_strength = 0.0
	if owner_player == null:
		return
	if owner_player.attached:
		_request_skydive_anim(&"Skydive_Exit")
		if owner_player.has_method("clear_active_action"):
			owner_player.clear_active_action()
		return
	_request_skydive_anim(&"Skydive_Exit")
	if owner_player.has_method("activate_neutral_air_action"):
		owner_player.activate_neutral_air_action({"reason": &"skydive_finished", "source_action": action_id})


func _cancel_to_neutral_air() -> void:
	state = SkydiveState.NONE
	glide_lift_effect_strength = 0.0
	if owner_player == null:
		return
	_request_skydive_anim(&"Skydive_Cancel")
	if owner_player.has_method("activate_neutral_air_action"):
		owner_player.activate_neutral_air_action({"reason": &"skydive_canceled", "source_action": action_id})


func _ease_in_out_sine(t: float) -> float:
	var clamped_t: float = clamp(t, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * clamped_t)


func _ease_out_quad(t: float) -> float:
	var clamped_t: float = clamp(t, 0.0, 1.0)
	return 1.0 - (1.0 - clamped_t) * (1.0 - clamped_t)


func _request_skydive_anim(state_name: StringName) -> void:
	if owner_player == null:
		return
	if owner_player.has_method("request_skydive_animation_state"):
		owner_player.request_skydive_animation_state(state_name)


func _request_skydive_command() -> void:
	if owner_player == null:
		return
	if owner_player.has_method("play_action_command_if_exists"):
		owner_player.play_action_command_if_exists(action_id)


func _end_airborne_torque_for_skydive() -> void:
	if owner_player == null:
		return
	if owner_player.has_method("_gracefully_end_airborne_torque"):
		owner_player.call("_gracefully_end_airborne_torque")


func _can_reenter_from_terminal_animation() -> bool:
	if owner_player == null:
		return false
	if owner_player.attached:
		return false
	if owner_player.get_current_action_id() == action_id:
		return false
	var canceling: bool = owner_player.has_method("_is_skydive_anim_canceling") and bool(owner_player.call("_is_skydive_anim_canceling"))
	var exiting: bool = owner_player.has_method("_is_skydive_anim_exiting") and bool(owner_player.call("_is_skydive_anim_exiting"))
	if not canceling and not exiting:
		return false
	return can_execute({"reason": &"skydive_terminal_reenter"})

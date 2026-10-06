class_name InstaShieldAction
extends CharacterAction

enum Phase {
	INACTIVE,
	PARRY,
	BLOCK,
	GRAPPLE_DEFENDER,
	GRAPPLE_ATTACKER,
	THROWN_VULNERABLE,
}

enum DefenseResult {
	NONE,
	PARRIED,
	BLOCK_BROKEN,
}

@export_group("Insta-Shield")

@export_subgroup("Activation")
## Enables the Insta-Shield ability.
@export var insta_shield_enabled: bool = true
## Duration of the opening parry window.
@export_range(0.01, 1.0, 0.01, "or_greater", "suffix:s") var parry_duration: float = 0.15
## Maximum duration of the regular block after the parry window.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:s") var block_duration: float = 1.0
## Cooldown applied after the shield ends or is broken.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var shield_cooldown: float = 1.2
## Maximum time permitted between the initial presses of both chord inputs.
@export_range(0.0, 0.5, 0.01, "or_greater", "suffix:s") var chord_press_window: float = 0.08
## Ability used as the primary half of the shield chord.
@export var primary_chord_ability: StringName = &"skydive"
## Fallback input slot used for the primary chord ability.
@export var primary_chord_fallback_slot: StringName = &"ability_slot_06"
## Ability used as the second half of the shield chord.
@export var secondary_chord_ability: StringName = &"parkour"
## Fallback input slot used for the secondary chord ability.
@export var secondary_chord_fallback_slot: StringName = &"ability_slot_07"

@export_subgroup("Movement")
## Exponential planar damping applied while parrying or blocking.
@export_range(0.0, 30.0, 0.1, "or_greater") var planar_damping_rate: float = 3.5
## Movement-input strength retained while parrying or blocking.
@export_range(0.0, 1.0, 0.01) var movement_input_strength: float = 0.35
## Downward speed retained when an airborne shield begins.
@export_range(0.0, 1.0, 0.01) var entry_fall_speed_retention: float = 0.35
## Gravity retained while descending during an airborne shield.
@export_range(0.0, 1.0, 0.01) var descending_gravity_scale: float = 0.25

@export_subgroup("Parry Grapple")
## Maximum time the defender may hold an attacker before throwing.
@export_range(0.05, 1.0, 0.01, "or_greater", "suffix:s") var grapple_duration: float = 0.25
## Earliest time at which Interact may break the grapple.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var grapple_escape_window_start: float = 0.06
## Latest time at which Interact may break the grapple.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var grapple_escape_window_end: float = 0.20
## Fraction of shared contact velocity retained during the grapple.
@export_range(0.0, 1.0, 0.01) var grapple_drift_retention: float = 0.3
## Minimum speed of a parry throw.
@export_range(0.0, 500.0, 0.5, "or_greater") var minimum_throw_speed: float = 45.0
## Maximum speed of a parry throw.
@export_range(0.0, 1000.0, 1.0, "or_greater") var maximum_throw_speed: float = 180.0
## Upward fraction added to a gravity-planar throw.
@export_range(0.0, 1.0, 0.01) var throw_upward_fraction: float = 0.16
## Separation speed used when an attacker escapes a grapple.
@export_range(0.0, 200.0, 0.5, "or_greater") var grapple_escape_rebound_speed: float = 24.0

@export_subgroup("Thrown Recovery")
## Duration for which a thrown attacker remains vulnerable.
@export_range(0.05, 2.0, 0.01, "or_greater", "suffix:s") var thrown_vulnerable_duration: float = 0.5
## Delay before the thrown attacker may perform an air recovery.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var thrown_recovery_delay: float = 0.12
## Speed retained when performing an airborne recovery.
@export_range(0.0, 1.0, 0.01) var thrown_recovery_speed_retention: float = 0.7
## Minimum upward speed applied by an airborne recovery.
@export_range(0.0, 200.0, 0.5, "or_greater") var thrown_recovery_up_speed: float = 18.0

@export_subgroup("Shield Break")
## Homing and jump-dash lockout applied to the attacker after breaking a block.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var shield_break_attacker_homing_lockout: float = 0.18
## Separation speed applied to an attacker after breaking a block.
@export_range(0.0, 100.0, 0.5, "or_greater") var shield_break_rebound_speed: float = 16.0

@export_subgroup("Rival AI")
## Chance for an AI-controlled grappled attacker to escape.
@export_range(0.0, 1.0, 0.01) var rival_grapple_escape_chance: float = 0.45
## Earliest time an AI defender commits to its throw.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var rival_throw_delay_min: float = 0.10
## Latest time an AI defender commits to its throw.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var rival_throw_delay_max: float = 0.24

@export_subgroup("Presentation")
## Animation command requested when the parry window begins.
@export var parry_animation_command: StringName = &"insta_shield_parry"
## Animation command requested when the regular block begins.
@export var block_animation_command: StringName = &"insta_shield_block"
## Animation command requested after a block is broken.
@export var block_break_animation_command: StringName = &"insta_shield_break"
## Animation command requested while holding a parried attacker.
@export var grapple_animation_command: StringName = &"insta_shield_grapple"
## Animation command requested while vulnerable after a parry throw.
@export var thrown_animation_command: StringName = &"insta_shield_thrown"
## Sound played when the Insta-Shield begins.
@export var activation_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Insta_Shield.wav")
## Sound volume for shield events.
@export var shield_sound_volume_db: float = 0.0

var phase: Phase = Phase.INACTIVE
var phase_elapsed: float = 0.0
var cooldown_remaining: float = 0.0
var airborne_use_available: bool = true
var _airborne_use_consumed: bool = false
var _shield_input_latched: bool = false
var _owns_shield_activation: bool = false
var _combat_partner: Node3D = null
var _captured_attack_velocity: Vector3 = Vector3.ZERO
var _grapple_drift_velocity: Vector3 = Vector3.ZERO
var _rival_hold_remaining: float = 0.0
var _rival_throw_commit_time: float = 0.0
var _rival_escape_attempt_time: float = -1.0


func _on_action_initialized() -> void:
	action_id = &"insta_shield"
	input_action = primary_chord_fallback_slot
	trigger_mode = ActionTrigger.JUST_PRESSED
	allow_when_inactive = true
	continuous_update = true
	shows_jump_ball = false
	can_pick_up_carryables_while_active = false
	can_execute_while_carrying = false


func get_input_prompt_stage() -> InputPromptStage:
	return InputPromptStage.PRIORITY


func can_execute(context: Dictionary = {}) -> bool:
	if owner_player == null or not insta_shield_enabled:
		return false
	if bool(context.get("forced_combat_state", false)):
		return true
	if not enabled or phase != Phase.INACTIVE or cooldown_remaining > 0.0:
		return false
	if owner_player._is_dead or owner_player._hurt_active or owner_player.race_in_countdown:
		return false
	if owner_player._ui_input_blocked or owner_player._local_pause_enabled:
		return false
	if owner_player._rail_active or owner_player._spline_active or owner_player._automation_active:
		return false
	if owner_player._spring_align_timer > 0.0 or owner_player._spring_action_lock_timer > 0.0:
		return false
	if not owner_player.attached and not airborne_use_available:
		return false
	return super.can_execute(context)


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if not activate(context):
		return false
	_begin_shield(bool(context.get("ai_controlled", false)), float(context.get("ai_hold_duration", block_duration)))
	return true


func prepare_priority_input(_delta: float) -> bool:
	if owner_player == null or _is_rival_owner():
		return false
	match phase:
		Phase.PARRY, Phase.BLOCK:
			return true
		Phase.GRAPPLE_DEFENDER:
			if _is_attack_commit_just_pressed():
				_throw_grappled_attacker()
			return true
		Phase.GRAPPLE_ATTACKER:
			if SettingsManager.is_gameplay_action_just_pressed(&"interact"):
				_try_escape_grapple()
			return true
		Phase.THROWN_VULNERABLE:
			if phase_elapsed >= max(thrown_recovery_delay, 0.0) and _is_jump_just_pressed():
				_perform_thrown_recovery()
			return true
		_:
			pass
	if not can_execute():
		return false
	if not _is_chord_just_pressed():
		return false
	return execute({"reason": &"shield_chord"})


func continuous_physics_update(delta: float) -> void:
	var step: float = max(delta, 0.0)
	cooldown_remaining = max(cooldown_remaining - step, 0.0)
	if phase == Phase.INACTIVE:
		if _shield_input_latched and not _is_chord_part_pressed():
			_shield_input_latched = false
		return
	if owner_player == null or owner_player._is_dead or owner_player._hurt_active:
		_finish_state(true)
		return
	phase_elapsed += step
	match phase:
		Phase.PARRY:
			if not _shield_hold_continues(step):
				_finish_state(true)
				return
			_apply_shield_movement(step)
			if phase != Phase.PARRY:
				return
			if phase_elapsed >= max(parry_duration, 0.01):
				phase = Phase.BLOCK
				phase_elapsed = 0.0
				_play_command(block_animation_command)
		Phase.BLOCK:
			if not _shield_hold_continues(step) or phase_elapsed >= max(block_duration, 0.0):
				_finish_state(true)
				return
			_apply_shield_movement(step)
		Phase.GRAPPLE_DEFENDER:
			_update_grapple_defender()
		Phase.GRAPPLE_ATTACKER:
			_update_grapple_attacker()
		Phase.THROWN_VULNERABLE:
			if phase_elapsed >= max(thrown_vulnerable_duration, 0.05):
				_finish_state(false)


func physics_update_action(_delta: float) -> void:
	pass


func on_action_exit(_next_action: CharacterAction) -> void:
	if phase == Phase.INACTIVE:
		return
	var starts_cooldown: bool = _owns_shield_activation
	_cleanup_partner_collision()
	phase = Phase.INACTIVE
	phase_elapsed = 0.0
	_owns_shield_activation = false
	_combat_partner = null
	_captured_attack_velocity = Vector3.ZERO
	_grapple_drift_velocity = Vector3.ZERO
	_rival_hold_remaining = 0.0
	_rival_escape_attempt_time = -1.0
	if starts_cooldown:
		cooldown_remaining = max(cooldown_remaining, max(shield_cooldown, 0.0))


func blocks_shared_movement_integration() -> bool:
	return phase == Phase.GRAPPLE_DEFENDER or phase == Phase.GRAPPLE_ATTACKER


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func get_movement_input_strength_multiplier() -> float:
	if phase == Phase.PARRY or phase == Phase.BLOCK:
		return clamp(movement_input_strength, 0.0, 1.0)
	if phase == Phase.THROWN_VULNERABLE:
		return 0.2
	if phase == Phase.GRAPPLE_DEFENDER or phase == Phase.GRAPPLE_ATTACKER:
		return 0.0
	return 1.0


func reset_traversal_history() -> void:
	airborne_use_available = true
	_airborne_use_consumed = false


func resolve_landing_momentum(_landing_normal: Vector3, _incoming_velocity: Vector3) -> bool:
	airborne_use_available = true
	_airborne_use_consumed = false
	return false


func is_defense_active() -> bool:
	return phase == Phase.PARRY or phase == Phase.BLOCK


func is_parry_active() -> bool:
	return phase == Phase.PARRY


func is_block_active() -> bool:
	return phase == Phase.BLOCK


func is_thrown_vulnerable() -> bool:
	return phase == Phase.THROWN_VULNERABLE


func is_combat_control_locked() -> bool:
	return phase == Phase.GRAPPLE_DEFENDER or phase == Phase.GRAPPLE_ATTACKER or phase == Phase.THROWN_VULNERABLE


func is_chord_input_consumed() -> bool:
	return phase != Phase.INACTIVE or _shield_input_latched


func start_for_rival(hold_duration: float) -> bool:
	return execute({
		"reason": &"rival_defense",
		"ai_controlled": true,
		"ai_hold_duration": max(hold_duration, parry_duration),
	})


func resolve_incoming_attack(attacker: Node3D, attack_velocity: Vector3) -> DefenseResult:
	if attacker == null or not is_instance_valid(attacker):
		return DefenseResult.NONE
	if phase == Phase.PARRY:
		_begin_parry_grapple(attacker, attack_velocity)
		return DefenseResult.PARRIED
	if phase == Phase.BLOCK:
		_break_block(attacker)
		return DefenseResult.BLOCK_BROKEN
	return DefenseResult.NONE


func begin_grappled_by(defender: Node3D, attack_velocity: Vector3, shared_drift: Vector3) -> bool:
	if owner_player == null or defender == null:
		return false
	_cancel_owner_offense()
	if not owner_player.activate_action(self, {"forced_combat_state": true, "reason": &"parried"}):
		return false
	phase = Phase.GRAPPLE_ATTACKER
	phase_elapsed = 0.0
	_owns_shield_activation = false
	_combat_partner = defender
	_captured_attack_velocity = attack_velocity
	_grapple_drift_velocity = shared_drift
	owner_player.velocity = shared_drift
	_add_partner_collision_exception()
	_play_command(grapple_animation_command)
	if _is_rival_owner() and randf() <= clamp(rival_grapple_escape_chance, 0.0, 1.0):
		_rival_escape_attempt_time = randf_range(
			max(grapple_escape_window_start, 0.0),
			max(grapple_escape_window_end, grapple_escape_window_start)
		)
	return true


func cancel_grapple_from_attacker(attacker: Node3D) -> void:
	if phase != Phase.GRAPPLE_DEFENDER or attacker != _combat_partner:
		return
	_apply_mutual_rebound(attacker, grapple_escape_rebound_speed)
	_finish_state(true)


func receive_parry_throw(defender: Node3D, throw_velocity: Vector3) -> void:
	if phase != Phase.GRAPPLE_ATTACKER or defender != _combat_partner:
		return
	_cleanup_partner_collision()
	phase = Phase.THROWN_VULNERABLE
	phase_elapsed = 0.0
	_combat_partner = defender
	owner_player.velocity = throw_velocity
	owner_player.attached = false
	owner_player._attachment_immunity = max(owner_player._attachment_immunity, owner_player.launch_immunity_time)
	_play_command(thrown_animation_command)


func _begin_shield(ai_controlled: bool, ai_hold_duration: float) -> void:
	_cancel_owner_offense()
	phase = Phase.PARRY
	phase_elapsed = 0.0
	_owns_shield_activation = true
	_airborne_use_consumed = not owner_player.attached
	if _airborne_use_consumed:
		airborne_use_available = false
	_shield_input_latched = not ai_controlled
	_rival_hold_remaining = max(ai_hold_duration, parry_duration) if ai_controlled else 0.0
	_apply_air_entry_float()
	_play_command(parry_animation_command)
	_play_sound(1.0)


func _begin_parry_grapple(attacker: Node3D, attack_velocity: Vector3) -> void:
	var shared_velocity: Vector3 = (owner_player.velocity + attack_velocity) * 0.5
	_grapple_drift_velocity = shared_velocity * clamp(grapple_drift_retention, 0.0, 1.0)
	phase = Phase.GRAPPLE_DEFENDER
	phase_elapsed = 0.0
	_combat_partner = attacker
	_captured_attack_velocity = attack_velocity
	owner_player.velocity = _grapple_drift_velocity
	_rival_throw_commit_time = randf_range(
		min(rival_throw_delay_min, rival_throw_delay_max),
		max(rival_throw_delay_min, rival_throw_delay_max)
	)
	_cancel_node_offense(attacker)
	var began: bool = false
	if attacker.has_method("begin_insta_shield_grapple"):
		began = bool(attacker.call("begin_insta_shield_grapple", owner_player, attack_velocity, _grapple_drift_velocity))
	if not began:
		_throw_node(attacker)
		_finish_state(true)
		return
	_add_partner_collision_exception()
	_play_command(grapple_animation_command)
	_play_sound(1.12)


func _break_block(attacker: Node3D) -> void:
	_play_command(block_break_animation_command)
	_play_sound(0.82)
	_cancel_node_offense(attacker)
	if attacker.has_method("apply_combat_homing_lockout"):
		attacker.call("apply_combat_homing_lockout", shield_break_attacker_homing_lockout)
	_apply_attacker_rebound(attacker, shield_break_rebound_speed)
	_finish_state(true)


func _update_grapple_defender() -> void:
	if _combat_partner == null or not is_instance_valid(_combat_partner):
		_finish_state(true)
		return
	owner_player.velocity = _grapple_drift_velocity
	if _is_rival_owner() and phase_elapsed >= _rival_throw_commit_time:
		_throw_grappled_attacker()
		return
	if phase_elapsed >= max(grapple_duration, 0.05):
		_throw_grappled_attacker()


func _update_grapple_attacker() -> void:
	if _combat_partner == null or not is_instance_valid(_combat_partner):
		_finish_state(false)
		return
	owner_player.velocity = _grapple_drift_velocity
	if _is_rival_owner() and _rival_escape_attempt_time >= 0.0 and phase_elapsed >= _rival_escape_attempt_time:
		_rival_escape_attempt_time = -1.0
		_try_escape_grapple()
		return
	if phase_elapsed > max(grapple_duration, 0.05) + 0.1:
		_finish_state(false)


func _try_escape_grapple() -> bool:
	if phase != Phase.GRAPPLE_ATTACKER:
		return false
	var window_start: float = max(grapple_escape_window_start, 0.0)
	var window_end: float = max(grapple_escape_window_end, window_start)
	if phase_elapsed < window_start or phase_elapsed > window_end:
		return false
	var defender: Node3D = _combat_partner
	if defender != null and is_instance_valid(defender) and defender.has_method("cancel_insta_shield_grapple"):
		defender.call("cancel_insta_shield_grapple", owner_player)
	else:
		_apply_attacker_rebound(owner_player, grapple_escape_rebound_speed)
	_finish_state(true)
	return true


func _throw_grappled_attacker() -> void:
	if phase != Phase.GRAPPLE_DEFENDER:
		return
	var attacker: Node3D = _combat_partner
	if attacker == null or not is_instance_valid(attacker):
		_finish_state(true)
		return
	var throw_velocity: Vector3 = _calculate_throw_velocity(attacker)
	if attacker.has_method("receive_insta_shield_throw"):
		attacker.call("receive_insta_shield_throw", owner_player, throw_velocity)
	elif "velocity" in attacker:
		attacker.set("velocity", throw_velocity)
	_finish_state(true)


func _throw_node(attacker: Node3D) -> void:
	var throw_velocity: Vector3 = _calculate_throw_velocity(attacker)
	if "velocity" in attacker:
		attacker.set("velocity", throw_velocity)


func _calculate_throw_velocity(attacker: Node3D) -> Vector3:
	var up: Vector3 = get_owner_gravity_up()
	var direction: Vector3 = get_gravity_planar_component(owner_player._move_direction)
	if direction.length() < 0.1 and _is_rival_owner():
		var rival_direction_value: Variant = owner_player.get("_rival_move_dir")
		if rival_direction_value is Vector3:
			direction = get_gravity_planar_component(rival_direction_value as Vector3)
	if direction.length() < 0.1:
		direction = get_gravity_planar_component(attacker.global_position - owner_player.global_position)
	if direction.length() < 0.1:
		direction = get_gravity_planar_component(_captured_attack_velocity)
	if direction.length() < 0.1:
		direction = get_gravity_planar_component(-owner_player.global_transform.basis.z)
	if direction.length() < 0.1:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var captured_speed: float = _captured_attack_velocity.length()
	var throw_speed: float = clamp(captured_speed, max(minimum_throw_speed, 0.0), max(maximum_throw_speed, minimum_throw_speed))
	var upward_speed: float = throw_speed * clamp(throw_upward_fraction, 0.0, 1.0)
	var planar_speed: float = sqrt(max(throw_speed * throw_speed - upward_speed * upward_speed, 0.0))
	return direction * planar_speed + up * upward_speed


func _perform_thrown_recovery() -> void:
	var up: Vector3 = get_owner_gravity_up()
	var vertical: float = owner_player.velocity.dot(up)
	var planar: Vector3 = owner_player.velocity - up * vertical
	planar *= clamp(thrown_recovery_speed_retention, 0.0, 1.0)
	var input_direction: Vector3 = get_gravity_planar_component(owner_player._move_direction)
	if input_direction.length() > 0.1:
		var retained_speed: float = max(planar.length(), minimum_throw_speed * 0.5)
		planar = input_direction.normalized() * retained_speed
	owner_player.velocity = planar + up * max(vertical, max(thrown_recovery_up_speed, 0.0))
	owner_player.attached = false
	_finish_state(false)


func _apply_shield_movement(delta: float) -> void:
	var up: Vector3 = get_owner_gravity_up()
	var vertical: float = owner_player.velocity.dot(up)
	var planar: Vector3 = owner_player.velocity - up * vertical
	planar *= exp(-max(planar_damping_rate, 0.0) * delta)
	if not owner_player.attached:
		if not _airborne_use_consumed:
			if not airborne_use_available:
				_finish_state(true)
				return
			_airborne_use_consumed = true
			airborne_use_available = false
		if vertical <= 0.0:
			var gravity_cancel: Vector3 = -get_owner_gravity_acceleration_vector() * (1.0 - clamp(descending_gravity_scale, 0.0, 1.0)) * delta
			owner_player.velocity = planar + up * vertical + gravity_cancel
			return
	owner_player.velocity = planar + up * vertical


func _apply_air_entry_float() -> void:
	if owner_player.attached:
		return
	var up: Vector3 = get_owner_gravity_up()
	var vertical: float = owner_player.velocity.dot(up)
	var planar: Vector3 = owner_player.velocity - up * vertical
	if vertical < 0.0:
		vertical *= clamp(entry_fall_speed_retention, 0.0, 1.0)
	owner_player.velocity = planar + up * vertical


func _apply_mutual_rebound(other: Node3D, speed: float) -> void:
	var midpoint: Vector3 = (owner_player.global_position + other.global_position) * 0.5
	if owner_player.has_method("cancel_attack_for_combat_response"):
		owner_player.call("cancel_attack_for_combat_response", &"grapple_escape")
	if other.has_method("cancel_attack_for_combat_response"):
		other.call("cancel_attack_for_combat_response", &"grapple_escape")
	if owner_player.has_method("apply_enemy_bounce"):
		owner_player.call("apply_enemy_bounce", midpoint, max(speed, 0.0), other)
	_apply_attacker_rebound(other, speed)


func _apply_attacker_rebound(attacker: Node3D, speed: float) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if attacker.has_method("apply_enemy_bounce"):
		attacker.call("apply_enemy_bounce", owner_player.global_position, max(speed, 0.0), owner_player)
		return
	if "velocity" in attacker:
		var away: Vector3 = attacker.global_position - owner_player.global_position
		if away.length() < 0.001:
			away = -owner_player.global_transform.basis.z
		attacker.set("velocity", away.normalized() * max(speed, 0.0))


func _cancel_owner_offense() -> void:
	if owner_player != null and owner_player.has_method("cancel_attack_for_combat_response"):
		owner_player.call("cancel_attack_for_combat_response", &"insta_shield")


func _cancel_node_offense(node: Node) -> void:
	if node != null and is_instance_valid(node) and node.has_method("cancel_attack_for_combat_response"):
		node.call("cancel_attack_for_combat_response", &"insta_shield_contact")


func _shield_hold_continues(delta: float) -> bool:
	if _is_rival_owner():
		_rival_hold_remaining = max(_rival_hold_remaining - delta, 0.0)
		return _rival_hold_remaining > 0.0
	return _is_chord_held()


func _is_chord_just_pressed() -> bool:
	if owner_player.has_method("is_ability_binding_simultaneously_just_pressed"):
		return bool(owner_player.call(
			"is_ability_binding_simultaneously_just_pressed",
			action_id,
			input_action,
			chord_press_window
		))
	return (
		SettingsManager.is_gameplay_action_just_pressed(String(primary_chord_fallback_slot))
		and SettingsManager.is_gameplay_action_just_pressed(String(secondary_chord_fallback_slot))
	)


func _is_chord_held() -> bool:
	if owner_player.has_method("is_ability_binding_pressed"):
		return bool(owner_player.call("is_ability_binding_pressed", action_id, input_action))
	return SettingsManager.is_gameplay_action_pressed(String(primary_chord_fallback_slot)) and SettingsManager.is_gameplay_action_pressed(String(secondary_chord_fallback_slot))


func _is_chord_part_pressed() -> bool:
	var primary_slot: StringName = primary_chord_fallback_slot
	var secondary_slot: StringName = secondary_chord_fallback_slot
	if owner_player.has_method("get_ability_input_slot"):
		primary_slot = StringName(owner_player.call("get_ability_input_slot", primary_chord_ability, primary_slot))
		secondary_slot = StringName(owner_player.call("get_ability_input_slot", secondary_chord_ability, secondary_slot))
	return SettingsManager.is_gameplay_action_pressed(String(primary_slot)) or SettingsManager.is_gameplay_action_pressed(String(secondary_slot))


func _is_attack_commit_just_pressed() -> bool:
	return (
		owner_player.is_ability_binding_just_pressed(&"jump", &"ability_slot_01")
		or owner_player.is_ability_binding_just_pressed(&"spin_kick", &"ability_slot_03")
		or owner_player.is_ability_binding_just_pressed(&"roll", &"ability_slot_04")
	)


func _is_jump_just_pressed() -> bool:
	return owner_player.is_ability_binding_just_pressed(&"jump", &"ability_slot_01")


func _is_rival_owner() -> bool:
	return owner_player != null and owner_player.has_meta(&"is_rival_actor") and bool(owner_player.get_meta(&"is_rival_actor"))


func _add_partner_collision_exception() -> void:
	if owner_player is PhysicsBody3D and _combat_partner is PhysicsBody3D:
		(owner_player as PhysicsBody3D).add_collision_exception_with(_combat_partner as PhysicsBody3D)


func _cleanup_partner_collision() -> void:
	if owner_player is PhysicsBody3D and _combat_partner is PhysicsBody3D and is_instance_valid(_combat_partner):
		(owner_player as PhysicsBody3D).remove_collision_exception_with(_combat_partner as PhysicsBody3D)


func _finish_state(start_cooldown: bool) -> void:
	if phase == Phase.INACTIVE:
		return
	var starts_cooldown: bool = start_cooldown and _owns_shield_activation
	_cleanup_partner_collision()
	phase = Phase.INACTIVE
	phase_elapsed = 0.0
	_owns_shield_activation = false
	_combat_partner = null
	_captured_attack_velocity = Vector3.ZERO
	_grapple_drift_velocity = Vector3.ZERO
	_rival_hold_remaining = 0.0
	_rival_escape_attempt_time = -1.0
	if starts_cooldown:
		cooldown_remaining = max(cooldown_remaining, max(shield_cooldown, 0.0))
	if owner_player != null and owner_player.get_current_action_id() == action_id:
		owner_player.clear_active_action()
		if not owner_player.attached:
			owner_player.activate_neutral_air_action({"reason": &"insta_shield_end", "source_action": action_id})


func _play_command(command: StringName) -> void:
	if command == &"" or owner_player == null:
		return
	if owner_player.has_method("play_action_command_if_exists"):
		owner_player.call("play_action_command_if_exists", command)


func _play_sound(pitch: float) -> void:
	if activation_sound == null or owner_player == null:
		return
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.add_to_group(&"LevelTransient")
	player.stream = activation_sound
	player.volume_db = shield_sound_volume_db
	player.pitch_scale = max(pitch, 0.01)
	player.bus = &"SFX"
	player.autoplay = true
	var parent: Node = owner_player.get_parent()
	if parent == null:
		parent = owner_player
	parent.add_child(player)
	player.top_level = true
	player.global_position = owner_player.global_position
	player.finished.connect(func() -> void:
		player.queue_free()
	)

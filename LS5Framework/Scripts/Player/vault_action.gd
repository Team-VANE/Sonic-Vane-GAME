class_name VaultAction
extends CharacterAction

@export_group("Vault")
## Minimum surface-tangential speed required to vault.
@export_range(0.01, 100.0, 0.1, "or_greater", "suffix:m/s") var minimum_speed: float = 2.0
## Forward launch speed used when the incoming speed is below this value.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m/s") var minimum_launch_speed: float = 30.0
## Forward speed multiplier for entry speeds at or above the minimum launch speed.
@export_range(1.0, 2.0, 0.01, "or_greater") var speed_multiplier: float = 1.0
## Launch speed away from the supporting surface when starting a vault.
@export_range(0.0, 50.0, 0.5, "or_greater", "suffix:m/s") var lift_speed: float = 14.0
## Time after the vault begins in which jump can trigger the boosted launch.
@export_range(0.05, 1.0, 0.01, "or_greater", "suffix:s") var jump_window: float = 0.4
## Animation command played when clearing the obstacle.
@export var vault_animation: StringName = &"CMD_VAULT"
## Animation command played when jumping out of the vault.
@export var vault_jump_animation: StringName = &"CMD_VAULT_JUMP"

var _jump_window_remaining: float = 0.0
var _boosted: bool = false


func _on_action_initialized() -> void:
	action_id = &"vault"
	input_prompt_enabled = false
	shows_jump_ball = false
	compact_collision = true
	fast_fall_horizontal_drag_mode = FastFallHorizontalDragMode.FORCE_EXEMPT


func can_execute(context: Dictionary = {}) -> bool:
	var lateral: Vector3 = context.get("lateral", Vector3.ZERO)
	return context.has("vault_position") and can_start_from_contact(lateral.length())


func can_start_from_contact(entry_speed: float) -> bool:
	return (
		entry_speed >= maxf(minimum_speed, 0.001)
		and enabled and owner_player and owner_player.attached and not owner_player._spindash_charging
		and owner_player._network_is_local_authority() and owner_player.is_automation_action_allowed(action_id)
		and _is_parkour_held()
	)


func on_action_enter(context: Dictionary = {}) -> void:
	var up: Vector3 = context["up"]
	var lateral: Vector3 = context["lateral"]
	_jump_window_remaining = jump_window
	_boosted = false
	if owner_player.rolling:
		if owner_player._roll_action:
			owner_player._roll_action._set_rolling(false, true)
			owner_player._sync_roll_state_from_action()
		else:
			owner_player.rolling = false
	owner_player.global_position = context["vault_position"]
	var entry_speed: float = lateral.length()
	var launch_speed: float = minimum_launch_speed
	if entry_speed >= minimum_launch_speed:
		launch_speed = entry_speed * maxf(speed_multiplier, 1.0)
	owner_player.velocity = lateral.normalized() * launch_speed + up * maxf(lift_speed, 0.0)
	owner_player._record_detach_state(up, get_owner_gravity_up(), false, false)
	owner_player.attached = false
	owner_player._attachment_immunity = maxf(
		owner_player.launch_immunity_time, owner_player.get_physics_process_delta_time() * 2.0
	)
	owner_player._clear_coyote_jump_window()
	owner_player._is_skidding = false
	owner_player.snap_model_to_normal(up, lateral.normalized())
	owner_player._trigger_anim_command_immediate(vault_animation)


func prepare_priority_input(_delta: float) -> bool:
	if not _is_vaulting():
		return false
	if owner_player._hurt_active or owner_player._is_dead:
		return false
	if (
		not _boosted and _jump_window_remaining > 0.0
		and not owner_player._ui_input_blocked and not owner_player._local_pause_enabled
		and not owner_player.race_in_countdown and _is_parkour_held()
		and owner_player.is_ability_binding_just_pressed(&"jump", &"ability_slot_01")
	):
		_jump_from_vault()
	return true


func physics_update_action(delta: float) -> void:
	if owner_player.attached:
		owner_player.clear_active_action()
		return
	_jump_window_remaining = maxf(_jump_window_remaining - delta, 0.0)
	if (
		owner_player._hurt_active or owner_player._is_dead
		or (not _boosted and _jump_window_remaining <= 0.0)
		or (_boosted and get_gravity_vertical_component(owner_player.velocity) <= 0.0)
	):
		if not owner_player.activate_neutral_air_action({"reason": &"vault_ended"}):
			owner_player.clear_active_action()


func preserves_air_momentum() -> bool:
	return true


func _is_vaulting() -> bool:
	return owner_player and owner_player._active_action == self and not owner_player.attached


func _is_parkour_held() -> bool:
	var parkour: ParkourAbility = owner_player._get_action_by_id(&"parkour") as ParkourAbility
	return (
		parkour and parkour.enabled and owner_player.is_automation_action_allowed(&"parkour")
		and owner_player.is_ability_binding_pressed(parkour.action_id, parkour.slot_id)
	)


func _jump_from_vault() -> void:
	var jump: JumpAbility = owner_player._jump_action
	var gravity: float = owner_player.get_effective_gravity_strength()
	if not jump or not jump.enabled or gravity <= 0.0:
		return
	var step: float = owner_player.get_movement_physics_delta()
	var height: float = jump.get_held_jump_height(gravity, step)
	if height <= 0.0:
		return
	var launch_speed: float = sqrt(4.0 * gravity * height) + gravity * step * 0.5
	owner_player.velocity = compose_gravity_vector(owner_player.velocity, launch_speed)
	_boosted = true
	owner_player.play_jump_sfx()
	owner_player._trigger_anim_command_immediate(vault_jump_animation)

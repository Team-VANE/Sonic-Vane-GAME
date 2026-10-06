class_name JumpDashAbility
extends CharacterAbility

@export_group("Jump Dash")
@export_subgroup("Activation")
## Restricts jump dash activation to airborne movement.
@export var jump_dash_air_only: bool = true
## Restricts jump dash to one use per airtime.
@export var jump_dash_once_per_air: bool = true
@export var require_homing_target: bool = false

@export_subgroup("Movement")
## Speed added in the facing direction when jump dash begins.
@export var jump_dash_add_speed: float = 50.0
## Lateral speed where the jump dash impulse reaches zero.
@export var jump_dash_impulse_stop_speed: float = 100.0
## Maximum lateral speed immediately after jump dash. Values at or below zero use the character maximum speed.
@export var jump_dash_max_lateral_speed: float = 0.0

@export_subgroup("Action Chain Routes")
@export_multiline var on_air_action_pressed_action_tooltip: String = "Route for Ability Slot 2 while the jump dash action is active. Set this to the bounce or stomp action if this chain should be allowed."
@export var on_air_action_pressed_action: NodePath


func _on_action_initialized() -> void:
	if owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()
	
	action_id = &"jump_dash"
	allow_when_inactive = true
	permits_attack_magnetism = true


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func on_action_pressed() -> void:
	execute({"reason": &"pressed"})


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if mode != ActionTrigger.JUST_PRESSED:
		return false
	if not should_trigger_from_input(input_name, mode):
		return false
	return execute({"reason": &"pressed"})


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if owner_player.attached:
		return false
	if owner_player.has_method("is_combat_homing_locked") and owner_player.is_combat_homing_locked():
		return false
	if owner_player.race_in_countdown:
		return false
	if jump_dash_once_per_air and owner_player._jump_dash_used_this_air:
		return false
	if require_homing_target and owner_player.has_method("has_homing_target_in_range"):
		var target_available: bool = owner_player.has_homing_target_for_prompt() if bool(_context.get("input_prompt", false)) else bool(owner_player.call("has_homing_target_in_range"))
		if not target_available:
			return false
	return true


func get_input_prompt(context: Dictionary = {}) -> Dictionary:
	if not owner_player or not owner_player.can_queue_jump_dash():
		return {}
	return super.get_input_prompt(context)


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if owner_player != null and owner_player.has_method("queue_jump_dash"):
		if not owner_player.queue_jump_dash():
			return false
	if not activate(context):
		return false
	play_cmd_for_action(action_id)
	return true


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		if owner_player.has_method("clear_active_action"):
			owner_player.call("clear_active_action")
		return
	if not owner_player.uses_character_ability_profile() and SettingsManager.is_gameplay_action_just_pressed("ability_slot_02"):
		if process_ability_routes(
			&"ability_slot_02",
			ActionTrigger.JUST_PRESSED,
			{"reason": &"air_action_pressed", "source_action": action_id}
		):
			return
	if not owner_player.uses_character_ability_profile() and SettingsManager.is_gameplay_action_just_pressed("ability_slot_02") and on_air_action_pressed_action != NodePath():
		if execute_routed_action(
			on_air_action_pressed_action,
			{"reason": &"air_action_pressed", "source_action": action_id}
		):
			return
	if owner_player.has_method("activate_neutral_air_action"):
		owner_player.call("activate_neutral_air_action", {"reason": &"jump_dash_complete", "source_action": action_id})

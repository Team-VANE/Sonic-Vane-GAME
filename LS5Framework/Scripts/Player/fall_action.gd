class_name FallAction
extends CharacterAction

@export_group("Fall")

@export_subgroup("Detection")
## Downward speed required before airborne motion is considered falling.
@export var fall_vertical_speed_threshold: float = 14.0
## Grace period after leaving the ground before falling can begin.
@export var fall_airborne_grace_time: float = 0.05

@export_subgroup("Routes/Jump")
@export_multiline var on_air_jump_pressed_homing_action_tooltip: String = "Primary in-air route while the fall action is active. Set this to the action to try first when jump is pressed in the air."
@export var on_air_jump_pressed_homing_action: NodePath
@export_multiline var on_air_jump_pressed_action_tooltip: String = "Fallback in-air route while the fall action is active. Used when the primary route does not execute."
@export var on_air_jump_pressed_action: NodePath

@export_subgroup("Routes/Action Chain")
@export_multiline var on_air_action_pressed_action_tooltip: String = "Route for Ability Slot 2 while the fall action is active. Set this to the bounce or stomp action if this chain should be allowed."
@export var on_air_action_pressed_action: NodePath


func _on_action_initialized() -> void:
	action_id = &"fall"
	allow_when_inactive = false
	permits_attack_magnetism = true


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if owner_player.attached:
		return false
	if owner_player.rolling:
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
	if owner_player._homing_post_attack_timer > 0.0:
		return false
	if owner_player._jump_dash_recent_timer > 0.0:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	return true


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		return

	var jump_slot: StringName = owner_player.get_ability_input_slot(&"jump", &"ability_slot_01")
	if not owner_player.uses_character_ability_profile() and SettingsManager.is_gameplay_action_just_pressed(String(jump_slot)) and not owner_player.race_in_countdown:
		if process_ability_routes(
			jump_slot,
			ActionTrigger.JUST_PRESSED,
			{"reason": &"jump_pressed_in_air", "source_action": action_id}
		):
			return
		if on_air_jump_pressed_homing_action != NodePath():
			if execute_routed_action(
				on_air_jump_pressed_homing_action,
				{"reason": &"jump_pressed_in_air", "source_action": action_id, "route": &"homing"}
			):
				return
		if on_air_jump_pressed_action != NodePath():
			execute_routed_action(
				on_air_jump_pressed_action,
				{"reason": &"jump_pressed_in_air", "source_action": action_id, "route": &"fallback"}
			)
			return

	if not owner_player.uses_character_ability_profile() and SettingsManager.is_gameplay_action_just_pressed("ability_slot_02"):
		if owner_player.rolling:
			return
		if process_ability_routes(
			&"ability_slot_02",
			ActionTrigger.JUST_PRESSED,
			{"reason": &"air_action_pressed", "source_action": action_id}
		):
			return
		if on_air_action_pressed_action != NodePath():
			execute_routed_action(
				on_air_action_pressed_action,
				{"reason": &"air_action_pressed", "source_action": action_id}
			)

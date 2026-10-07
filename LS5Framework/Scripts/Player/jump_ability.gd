class_name JumpAbility
extends CharacterAbility

@export_group("Jump")

@export_subgroup("Movement/Launch")
## Launch speed applied along the current surface normal.
@export var jump_speed: float = 33.0

@export_subgroup("Movement/Variable Height")
## Maximum surface angle from gravity-up that permits variable jump height.
@export var variable_jump_max_surface_angle_deg: float = 95.0
## Duration that holding jump can influence upward motion.
@export var jump_hold_time_max: float = 0.77
## Gravity scale while rising with jump held.
@export var jump_hold_gravity_scale: float = 0.8
## Gravity scale near the apex while jump remains held.
@export var jump_apex_gravity_scale: float = 0.3
## Vertical speed range treated as the jump apex.
@export var jump_apex_speed_threshold: float = 2.0
## Gravity scale after jump is released during ascent.
@export var jump_release_gravity_scale: float = 1.8

@export_subgroup("Movement/Coyote Jump")
## Enables jumping shortly after a valid floor detach.
@export var coyote_jump_enabled: bool = true
## Coyote jump window. Zero keeps eligibility until another state invalidates it.
@export var coyote_jump_duration: float = 2.0
## Maximum detached surface-normal angle eligible for coyote jump.
@export var coyote_jump_max_angle_deg: float = 361.0
## Gives homing attack priority when homing and coyote jump are both valid.
@export var coyote_jump_homing_priority: bool = true

@export_subgroup("Movement/Horizontal Damping")
## Minimum lateral speed where variable-height jump damping begins.
@export var jump_damp_min_speed: float = 12.0
## Horizontal damping strength applied during the variable-height jump hold window.
@export var jump_damp_strength: float = 3.0
## Horizontal damping strength by lateral speed during the variable-height jump hold window.
## X: lateral speed, Y: damping strength per second.
@export var jump_damp_curve: Curve

@export_subgroup("Routes/Jump")
@export_multiline var on_air_jump_pressed_homing_action_tooltip: String = "Primary in-air route. Set this node path to the action to try first when jump is pressed in the air."
@export var on_air_jump_pressed_homing_action: NodePath
@export_multiline var on_air_jump_pressed_action_tooltip: String = "Fallback in-air route. Used when the primary route does not execute."
@export var on_air_jump_pressed_action: NodePath
@export_subgroup("Routes/Action Chain")
@export_multiline var on_air_action_pressed_action_tooltip: String = "Route for Ability Slot 2 while the jump action is active in the air. Set this to the bounce or stomp action if this chain should be allowed."
@export var on_air_action_pressed_action: NodePath


func _on_action_initialized() -> void:
	slot_index = 0
	input_action = &"ability_slot_01"
	action_id = &"jump"
	allow_when_inactive = true
	permits_attack_magnetism = true


func on_action_pressed() -> void:
	if owner_player == null:
		return

	if owner_player.attached:
		if owner_player.has_method("queue_jump"):
			if owner_player.queue_jump() and activate({"reason": &"ground_jump"}):
				play_cmd_for_action(action_id)
		return

	if process_ability_routes(
		&"ability_slot_01",
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


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		var launch_pending: bool = (
			owner_player.has_method("is_jump_launch_pending")
			and bool(owner_player.call("is_jump_launch_pending"))
		)
		if launch_pending:
			return
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


func on_action_exit(_next_action: CharacterAction) -> void:
	if owner_player == null:
		return
	owner_player._is_jumping = false
	owner_player._jump_variable = false
	owner_player._jump_hang_allowed = false
	owner_player._jump_time = 0.0


func _wall_kick_prompt_available() -> bool:
	if not owner_player:
		return false
	var parkour: ParkourAbility = owner_player._get_action_by_id(&"parkour") as ParkourAbility
	return parkour and parkour.is_wall_kick_prompt_available()


func get_input_prompt_stage() -> int:
	return InputPromptStage.PRIORITY if _wall_kick_prompt_available() else InputPromptStage.NORMAL


func get_input_prompt(_context: Dictionary = {}) -> Dictionary:
	if not input_prompt_enabled or not enabled or not owner_player:
		return {}
	if _wall_kick_prompt_available():
		return {"label": "Wall Kick", "gesture": &"press", "display_priority": 100, "contextual": true}
	if owner_player.attached and owner_player.can_queue_jump():
		return {"label": input_prompt_name}
	if owner_player.can_consume_coyote_jump() and owner_player.can_queue_coyote_jump():
		return {"label": input_prompt_name}
	return {}


func execute(context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if owner_player.attached:
		if owner_player.has_method("queue_jump"):
			if not owner_player.queue_jump():
				return false
		if not activate(context):
			return false
		play_cmd_for_action(action_id)
		return true
	return true


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if mode != ActionTrigger.JUST_PRESSED:
		return false
	if not should_trigger_from_input(input_name, mode):
		return false
	if owner_player != null and owner_player.uses_character_ability_profile():
		if not owner_player.attached:
			return false
		return execute({"reason": &"ground_jump"})
	on_action_pressed()
	return true

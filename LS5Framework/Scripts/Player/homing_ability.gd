class_name HomingAbility
extends CharacterAbility

@export_group("Homing Attack")
@export_subgroup("Activation")
## Enables homing attack execution.
@export var homing_attack_enabled: bool = true
## Enables shared target scans for the homing attack.
@export var homing_targeting_enabled: bool = true
@export var require_homing_target: bool = true

@export_subgroup("Targeting/Range")
## Minimum homing target range.
@export var homing_min_range: float = 35.0
## Maximum homing target range after speed scaling.
@export var homing_max_range: float = 90.0
## Target range added per unit of current speed.
@export var homing_range_per_speed: float = 0.18
## Minimum facing dot required for a valid homing target.
@export var homing_min_dot: float = 0.6
## Maximum target height above the character. Values at or below zero disable the limit.
@export var homing_target_max_height: float = 14.0
## Prevents homing attacks from selecting targets behind collision geometry.
@export var homing_obstruction_check: bool = true
## Distance before the target ignored when deciding whether a ray hit is obstructing it.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:m") var homing_obstruction_margin: float = 0.15

@export_subgroup("Targeting/Hybrid Input")
## Minimum movement input strength that can offset targeting from the reticle.
@export_range(0.0, 1.0, 0.01) var homing_hybrid_input_min_strength: float = 0.2
## Input deviation retained as camera-targeting priority.
@export_range(0.0, 90.0, 1.0) var homing_hybrid_camera_priority_angle_deg: float = 15.0
## Input deviation where targeting fully follows movement input.
@export_range(1.0, 180.0, 1.0) var homing_hybrid_full_input_angle_deg: float = 60.0
## Reticle-proximity priority while hybrid targeting favors the camera.
@export_range(0.0, 2.0, 0.05) var homing_hybrid_reticle_priority: float = 0.5

@export_subgroup("Movement")
## Minimum travel speed during homing.
@export var homing_speed: float = 85.0
## Homing steering response.
@export var homing_turn_rate: float = 3.5
## Distance at which a homing target is considered hit.
@export var homing_hit_distance: float = 1.25
## Upward speed applied after a successful homing attack.
@export var homing_pop_up_speed: float = 40.0
## Fraction of impact speed retained by the homing bounce.
@export var homing_bounce_speed_fraction: float = 0.5
## Minimum upward velocity applied when bouncing from an enemy.
@export var enemy_bounce_min_speed: float = 28.0
## Caps the upward result when a homing target is reached from below.
@export var homing_below_target_bounce_cap_enabled: bool = true
## Minimum target height along the character's physics-up axis before the cap applies.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var homing_below_target_min_height: float = 0.25
## Maximum upward velocity retained after hitting a homing target from below.
@export_range(0.0, 100.0, 0.5, "or_greater") var homing_below_target_max_up_speed: float = 16.0
## Retains incoming speed when jump remains held after a successful hit.
@export var homing_retain_speed_if_jump_held: bool = true
## Duration that retained homing speed suppresses air deceleration.
@export var homing_retain_disable_air_decel_time: float = 0.25

@export_subgroup("Timing")
## Maximum homing duration before an automatic cancel.
@export var homing_fail_timeout: float = 4.0
## Recovery duration after homing completes.
@export var homing_post_attack_time: float = 0.2

@export_subgroup("Action Chain Routes")
@export_multiline var on_air_action_pressed_action_tooltip: String = "Route for Ability Slot 2 while the homing action is active. Set this to the bounce or stomp action if this chain should be allowed."
@export var on_air_action_pressed_action: NodePath


func _on_action_initialized() -> void:
	action_id = &"homing"
	allow_when_inactive = true
	uses_homing_targeting = true
	
	if owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if mode != ActionTrigger.JUST_PRESSED:
		return false
	if not should_trigger_from_input(input_name, mode):
		return false
	return execute({"reason": &"pressed"})


func can_execute(_context: Dictionary = {}) -> bool:
	if not enabled:
		return false
	if owner_player == null:
		return false
	if owner_player.attached:
		return false
	if owner_player.has_method("is_combat_homing_locked") and owner_player.is_combat_homing_locked():
		return false
	if not homing_attack_enabled:
		return false
	if require_homing_target and owner_player.has_method("has_homing_target_in_range"):
		var target_available: bool = owner_player.has_homing_target_for_prompt() if bool(_context.get("input_prompt", false)) else bool(owner_player.call("has_homing_target_in_range"))
		if not target_available:
			return false
	return true


func get_input_prompt(context: Dictionary = {}) -> Dictionary:
	if not owner_player or not owner_player.can_queue_homing_attack():
		return {}
	return super.get_input_prompt(context)


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if owner_player != null and owner_player.has_method("queue_homing_attack"):
		if not owner_player.queue_homing_attack():
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
		owner_player.call("activate_neutral_air_action", {"reason": &"homing_complete", "source_action": action_id})

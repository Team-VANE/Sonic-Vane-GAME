class_name BounceAction
extends CharacterAbility

@export_group("Bounce")

@export_subgroup("Activation")
## Enables bounce execution.
@export var bounce_enabled: bool = true
## Activates bounce when the configured dive input is released within the tap window.
@export var quick_release_activation_enabled: bool = false
## Dive input monitored for quick-release activation.
@export var quick_release_input_action: StringName = &"ability_slot_02"
## Maximum held duration that counts as a tap.
@export_range(0.0, 1.0, 0.01, "or_greater") var quick_release_max_hold_time: float = 0.08
## Routes to the follow-up action when the activation input is released during descent.
@export var route_on_activation_input_release: bool = true

@export_subgroup("Movement/Fall")
## Gravity scale while descending in the bounce state.
@export var bounce_gravity_scale: float = 2.35
## One-shot downward impulse applied when bounce begins.
@export var bounce_down_impulse: float = 40.0

@export_subgroup("Movement/Rebound")
## Minimum impact speed treated as a valid bounce.
@export var bounce_min_impact_speed: float = 10.0
## Speed added to the upward rebound.
@export var bounce_add_speed: float = 0.1
## Minimum upward rebound speed.
@export var bounce_min_up_speed: float = 0.5
## Maximum upward rebound speed.
@export var bounce_max_up_speed: float = 50.0

@export_subgroup("Movement/Landing")
## Impact speed above which bounce landing speed is reduced.
@export var bounce_land_speed_threshold: float = 35.0
## Impact speed removed above the bounce landing threshold.
@export var bounce_land_speed_subtract: float = 10.0
## Tangential speed above which bounce landing speed is reduced.
@export var bounce_land_horizontal_threshold: float = 0.0
## Tangential speed removed above the bounce horizontal threshold.
@export var bounce_land_horizontal_subtract: float = 0.0

@export_subgroup("Action Chain Routes")
@export_multiline var on_bounce_released_action_tooltip: String = "Route to execute when bounce is released during descent. Set this to the stomp action if bounce should hand off into stomp."
@export var on_bounce_released_action: NodePath

@export_subgroup("Audio")
## Audio player used when the bounce starts.
@export var bounce_audio_node: NodePath

var bounce_button_held: bool = false
var quick_release_elapsed: float = -1.0


func _on_action_initialized() -> void:
	action_id = &"bounce"
	input_action = quick_release_input_action
	trigger_mode = ActionTrigger.TAP
	allow_when_inactive = true
	continuous_update = false
	permits_attack_magnetism = true


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if not should_trigger_from_input(input_name, mode):
		return false
	return execute({"reason": &"tap"})


func allows_profile_route(route: Dictionary, _context: Dictionary = {}) -> bool:
	var event: StringName = StringName(route.get("event", &""))
	var target_action: StringName = StringName(route.get("target_action", &""))
	if event == CharacterProfileManager.ROUTE_EVENT_INPUT_RELEASED and target_action == &"stomp":
		return _is_descending_bounce()
	return true


func can_execute(_context: Dictionary = {}) -> bool:
	if not super.can_execute(_context):
		return false
	if owner_player == null:
		return false
	if owner_player.has_method("should_prioritize_spindash_over_bounce_stomp"):
		if owner_player.should_prioritize_spindash_over_bounce_stomp():
			return false
	if owner_player.attached:
		return false
	if owner_player.race_in_countdown:
		return false
	if owner_player._is_dead or owner_player._hurt_active:
		return false
	if owner_player._rail_active or owner_player._spline_active or owner_player._lightspeed_dash_active:
		return false
	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._automation_lock_actions and owner_player._automation_locks_active():
		return false
	if not bounce_enabled:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE and owner_player._bounce_state != owner_player.BounceState.REBOUND:
		return false
	return true


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if owner_player.has_method("cancel_homing_attack"):
		owner_player.cancel_homing_attack(false)
	if owner_player.has_method("_clear_action_input_requests"):
		owner_player.call("_clear_action_input_requests")
	if not activate(context):
		return false
	if owner_player.has_method("queue_bounce_attack"):
		owner_player.queue_bounce_attack()
	if bounce_audio_node != null and bounce_audio_node != NodePath():
		var node: Node = get_node_or_null(bounce_audio_node)
		if node is AudioStreamPlayer3D:
			node.play()
	return true


func on_action_enter(_context: Dictionary = {}) -> void:
	if owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()
	
	bounce_button_held = input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action))


func on_action_exit(_next_action: CharacterAction) -> void:
	bounce_button_held = false


func continuous_physics_update(delta: float) -> void:
	if not quick_release_activation_enabled or owner_player == null:
		quick_release_elapsed = -1.0
		return
	if owner_player.is_in_group("NPCActor"):
		quick_release_elapsed = -1.0
		return
	if owner_player.has_method("_network_is_local_authority"):
		if not bool(owner_player.call("_network_is_local_authority")):
			quick_release_elapsed = -1.0
			return
	if owner_player.has_method("_action_input_locked"):
		if bool(owner_player.call("_action_input_locked")):
			quick_release_elapsed = -1.0
			return
	if quick_release_input_action == &"":
		quick_release_elapsed = -1.0
		return

	if quick_release_elapsed >= 0.0:
		quick_release_elapsed += max(delta, 0.0)
	if SettingsManager.is_gameplay_action_just_pressed(String(quick_release_input_action)):
		quick_release_elapsed = 0.0 if can_execute() else -1.0
	if quick_release_elapsed < 0.0:
		return
	if SettingsManager.is_gameplay_action_just_released(String(quick_release_input_action)):
		var held_time: float = quick_release_elapsed
		quick_release_elapsed = -1.0
		if held_time <= max(quick_release_max_hold_time, 0.0):
			execute({"reason": &"quick_release"})
		return
	if quick_release_elapsed > max(quick_release_max_hold_time, 0.0):
		quick_release_elapsed = -1.0


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		if owner_player.has_method("clear_active_action"):
			owner_player.call("clear_active_action")
		bounce_button_held = false
		return
	if owner_player._bounce_state == owner_player.BounceState.NONE:
		if owner_player.has_method("activate_neutral_air_action"):
			owner_player.call("activate_neutral_air_action", {"reason": &"bounce_finished", "source_action": action_id})
		bounce_button_held = false
		return
	if owner_player._bounce_state == owner_player.BounceState.REBOUND:
		bounce_button_held = input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action))
		if get_gravity_vertical_component(owner_player.velocity) <= 0.0:
			if owner_player.has_method("finish_bounce_rebound"):
				owner_player.call("finish_bounce_rebound")
			if owner_player.has_method("activate_neutral_air_action"):
				owner_player.call("activate_neutral_air_action", {"reason": &"bounce_rebound_finished", "source_action": action_id})
		return
	if owner_player._bounce_state != owner_player.BounceState.BOUNCE:
		bounce_button_held = input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action))
		return
	if not _is_descending_bounce():
		bounce_button_held = input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action))
		return
	if not route_on_activation_input_release:
		return
	var bounce_pressed_now: bool = input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action))
	if bounce_button_held and not bounce_pressed_now:
		if process_ability_routes(
			input_action,
			ActionTrigger.JUST_RELEASED,
			{"reason": &"bounce_released", "source_action": action_id}
		):
			return
	if bounce_button_held and not bounce_pressed_now and on_bounce_released_action != NodePath():
		if execute_routed_action(
			on_bounce_released_action,
			{"reason": &"bounce_released", "source_action": action_id}
		):
			return
	bounce_button_held = bounce_pressed_now


func _is_descending_bounce() -> bool:
	if owner_player == null or owner_player._bounce_state != owner_player.BounceState.BOUNCE:
		return false
	return get_gravity_vertical_component(owner_player.velocity) < 0.0

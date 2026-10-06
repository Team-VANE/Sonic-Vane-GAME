extends Node
class_name CharacterAction

enum ActionTrigger {
	NONE,
	JUST_PRESSED,
	PRESSED,
	JUST_RELEASED,
	TAP,
	HOLD,
}

enum InputPromptStage { NORMAL, PRIORITY, BEFORE_ROUTES, AFTER_PREEMPTIVE_ROUTES }

enum CombatClass {
	NEUTRAL = 0,
	ATTACK  = 1,
}

enum FastFallHorizontalDragMode {
	ACTION_DEFAULT,
	FORCE_ENABLED,
	FORCE_EXEMPT,
}

@export_group("Action")
@export_subgroup("Activation")
@export var action_id: StringName = &""
@export var input_action: StringName = &""
@export var trigger_mode: ActionTrigger = ActionTrigger.JUST_PRESSED
@export var enabled: bool = true
@export var allow_when_inactive: bool = true
@export var continuous_update: bool = false

## Uses only the main collision sphere while this action is active.
@export var compact_collision: bool = false

@export_subgroup("Targeting")
## Enables shared homing-target scans while this action is present and enabled.
@export var uses_homing_targeting: bool = false
## Allows attack magnetism while this action is active.
@export var permits_attack_magnetism: bool = false

@export_subgroup("Presentation")
## Displays this action when its input and activation conditions are available.
@export var input_prompt_enabled: bool = true
## Optional HUD action name. Empty uses the character profile display name.
@export var input_prompt_name: String = ""
## Shows the jump ball when this action is active and the player is airborne while attacking.
@export var shows_jump_ball: bool = true

@export_subgroup("Movement/Shared Modifiers")
## Controls whether shared fast-fall horizontal drag affects this action.
## Action Default follows the action's trajectory policy; the force modes override it.
@export_enum("Action Default", "Force Enabled", "Force Exempt") var fast_fall_horizontal_drag_mode: int = FastFallHorizontalDragMode.ACTION_DEFAULT

@export_subgroup("Carry Interaction")
## Allows carryable objects to be picked up while this action is active.
@export var can_pick_up_carryables_while_active: bool = true
## Allows this action to start or continue while the player is carrying an object.
@export var can_execute_while_carrying: bool = true

@export_subgroup("Audio/Voice")
## Voice clips played when this action activates.
@export var activation_voice_clips: Array[AudioStream] = []
## Chance that activation voice clips play.
@export_range(0.0, 1.0, 0.01) var activation_voice_chance: float = 1.0

@export_subgroup("Routes")
## Routes evaluated by this action.
@export var routes: Array[Resource] = []

@export_subgroup("Combat")
## Marks whether this action participates in physical attack clashes.
@export var combat_class: CombatClass = CombatClass.NEUTRAL

var owner_player: Node = null


func init_action(pawn: Node) -> void:
	owner_player = pawn
	_on_action_initialized()


func _on_action_initialized() -> void:
	pass


func should_trigger_from_input(triggered_input: StringName, mode: ActionTrigger) -> bool:
	if not enabled:
		return false
	if input_action == &"":
		return false
	if mode != trigger_mode:
		return false
	return triggered_input == input_action


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player and owner_player.has_method("is_carrying_object"):
		if bool(owner_player.call("is_carrying_object")) and not can_execute_while_carrying:
			return false
	return enabled


func get_input_prompt(context: Dictionary = {}) -> Dictionary:
	if not input_prompt_enabled or not enabled or not can_execute(context):
		return {}
	return {"label": input_prompt_name}


func get_input_prompt_stage() -> InputPromptStage:
	return InputPromptStage.NORMAL


func execute(_context: Dictionary = {}) -> bool:
	return true


func on_action_enter(_context: Dictionary = {}) -> void:
	pass


func on_action_exit(_next_action: CharacterAction) -> void:
	pass


func physics_update_action(_delta: float) -> void:
	pass


func continuous_physics_update(_delta: float) -> void:
	pass


func receives_fast_fall_horizontal_drag() -> bool:
	if fast_fall_horizontal_drag_mode == FastFallHorizontalDragMode.FORCE_ENABLED:
		return true
	if fast_fall_horizontal_drag_mode == FastFallHorizontalDragMode.FORCE_EXEMPT:
		return false
	return receives_fast_fall_horizontal_drag_by_default()


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return true


func blocks_shared_movement_integration() -> bool:
	return false


func prepare_priority_input(_delta: float) -> bool:
	return false


func pauses_barrier_blast_depletion() -> bool:
	return false


func allows_barrier_blast_building() -> bool:
	return false


func blocks_surface_attachment() -> bool:
	return false


func reset_traversal_history() -> void:
	pass


func resolve_movement_contact(_entry_velocity: Vector3) -> void:
	pass


func resolve_wall_collision_velocity(
	_normal: Vector3,
	_world_up: Vector3,
	_entry_velocity: Vector3
) -> bool:
	return false


func resolve_landing_momentum(_landing_normal: Vector3, _incoming_velocity: Vector3) -> bool:
	return false


func is_landing_animation_override_active() -> bool:
	return false


func try_handle_animation_command(_command: StringName) -> bool:
	return false


func apply_visual_orientation() -> bool:
	return false


## Optional action-relative up for compact collision placement.
func get_compact_collision_up() -> Vector3:
	return Vector3.ZERO


func influence_movement_input(direction: Vector3, _gravity_up: Vector3) -> Vector3:
	return direction


func get_movement_input_strength_multiplier() -> float:
	return 1.0


func get_animation_speed_multiplier() -> float:
	return 1.0


func process_input_event(_input_name: StringName, _mode: ActionTrigger) -> bool:
	return false


func allows_profile_route(_route: Dictionary, _context: Dictionary = {}) -> bool:
	return true


func activate(context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if owner_player.has_method("activate_action"):
		return bool(owner_player.call("activate_action", self, context))
	return false


func get_owner_gravity_up() -> Vector3:
	if owner_player == null:
		return Vector3.UP
	if owner_player.has_method("get_gravity_up"):
		var resolved_up_value = owner_player.call("get_gravity_up")
		if resolved_up_value is Vector3:
			var resolved_up: Vector3 = resolved_up_value
			if resolved_up.length() >= 0.001:
				return resolved_up.normalized()
	var base_up_value = owner_player.get("gravity_up")
	if base_up_value is Vector3:
		var base_up: Vector3 = base_up_value
		if base_up.length() >= 0.001:
			return base_up.normalized()
	return Vector3.UP


func get_owner_gravity_down() -> Vector3:
	return -get_owner_gravity_up()


func get_owner_gravity_acceleration_vector() -> Vector3:
	if owner_player != null and owner_player.has_method("get_gravity_acceleration_vector"):
		var acceleration_value = owner_player.call("get_gravity_acceleration_vector")
		if acceleration_value is Vector3:
			var acceleration: Vector3 = acceleration_value
			return acceleration
	var strength: float = 0.0
	if owner_player != null and owner_player.has_method("get_effective_gravity_strength"):
		strength = max(float(owner_player.call("get_effective_gravity_strength")), 0.0)
	return get_owner_gravity_down() * strength


func get_gravity_vertical_component(vector: Vector3) -> float:
	if owner_player != null and owner_player.has_method("get_gravity_vertical_component"):
		return float(owner_player.call("get_gravity_vertical_component", vector))
	return vector.dot(get_owner_gravity_up())


func get_gravity_planar_component(vector: Vector3) -> Vector3:
	if owner_player != null and owner_player.has_method("get_gravity_planar_component"):
		var planar_value = owner_player.call("get_gravity_planar_component", vector)
		if planar_value is Vector3:
			var planar: Vector3 = planar_value
			return planar
	var up: Vector3 = get_owner_gravity_up()
	return vector - up * vector.dot(up)


func compose_gravity_vector(planar: Vector3, vertical: float) -> Vector3:
	if owner_player != null and owner_player.has_method("compose_gravity_vector"):
		var composed_value = owner_player.call("compose_gravity_vector", planar, vertical)
		if composed_value is Vector3:
			var composed: Vector3 = composed_value
			return composed
	return get_gravity_planar_component(planar) + get_owner_gravity_up() * vertical


func rotate_gravity_frame_vector(vector: Vector3, from_up: Vector3, to_up: Vector3) -> Vector3:
	if owner_player != null and owner_player.has_method("rotate_vector_between_gravity_frames"):
		var rotated_value = owner_player.call("rotate_vector_between_gravity_frames", vector, from_up, to_up)
		if rotated_value is Vector3:
			var rotated: Vector3 = rotated_value
			return rotated
	var source_up: Vector3 = from_up.normalized()
	var target_up: Vector3 = to_up.normalized()
	if source_up.length() < 0.001 or target_up.length() < 0.001:
		return vector
	var alignment: float = clamp(source_up.dot(target_up), -1.0, 1.0)
	if alignment >= 0.999999999999:
		return vector
	var axis: Vector3 = source_up.cross(target_up)
	if axis.length() < 0.000001:
		axis = source_up.cross(Vector3.RIGHT)
	if axis.length() < 0.000001:
		axis = source_up.cross(Vector3.FORWARD)
	if axis.length() < 0.000001:
		return vector
	return vector.rotated(axis.normalized(), acos(alignment))


func execute_routed_action(route_path: NodePath, context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if uses_authoritative_profile_routes():
		return false
	if owner_player.has_method("execute_action_from_path"):
		return bool(owner_player.call("execute_action_from_path", self, route_path, context))
	return false


func process_ability_routes(input_name: StringName, mode: ActionTrigger, context: Dictionary = {}) -> bool:
	var profile_event: StringName = _action_trigger_to_profile_route_event(mode)
	if owner_player != null and owner_player.has_method("has_character_profile_input_route"):
		if bool(owner_player.call("has_character_profile_input_route", action_id, input_name)):
			if profile_event != &"":
				return bool(owner_player.call("execute_character_profile_input_route", action_id, profile_event, input_name, context))
			return false
	if uses_authoritative_profile_routes():
		return false
	var sorted_routes: Array[AbilityRoute] = _get_sorted_routes()
	for route: AbilityRoute in sorted_routes:
		if _route_matches_input(route, input_name, mode, context):
			if execute_ability_route(route, context):
				return true
	return false


func execute_manual_route(route_id: StringName, context: Dictionary = {}) -> bool:
	if owner_player != null and owner_player.has_method("has_character_profile_route_id"):
		if bool(owner_player.call("has_character_profile_route_id", action_id, route_id)):
			return bool(owner_player.call(
				"execute_character_profile_route_event",
				action_id,
				CharacterProfileManager.ROUTE_EVENT_MANUAL,
				route_id,
				context
			))
	if uses_authoritative_profile_routes():
		return false
	var sorted_routes: Array[AbilityRoute] = _get_sorted_routes()
	for route: AbilityRoute in sorted_routes:
		if route == null:
			continue
		if route.trigger_mode != AbilityRoute.TriggerMode.MANUAL:
			continue
		if route_id != &"" and route.route_id != route_id:
			continue
		if _route_is_allowed(route, context):
			if execute_ability_route(route, context):
				return true
	return false


func emit_profile_route_event(event: StringName, context: Dictionary = {}) -> bool:
	if owner_player == null or not owner_player.has_method("execute_character_profile_route_event"):
		return false
	return bool(owner_player.call("execute_character_profile_route_event", action_id, event, &"", context))


func uses_authoritative_profile_routes() -> bool:
	return owner_player != null and owner_player.has_method("uses_authoritative_character_profile_routes") and bool(owner_player.call("uses_authoritative_character_profile_routes"))


func execute_ability_route(route: AbilityRoute, context: Dictionary = {}) -> bool:
	if route == null or owner_player == null:
		return false
	if not _route_is_allowed(route, context):
		return false
	var route_context: Dictionary = context.duplicate()
	if not route_context.has("source_action"):
		route_context["source_action"] = action_id
	if route.route_id != &"":
		route_context["route"] = route.route_id
	if route.reason != &"":
		route_context["reason"] = route.reason
	match route.activation_mode:
		AbilityRoute.ActivationMode.NEUTRAL_AIR:
			if owner_player.has_method("activate_neutral_air_action"):
				return bool(owner_player.call("activate_neutral_air_action", route_context))
			return false
		AbilityRoute.ActivationMode.CLEAR_ACTIVE:
			if owner_player.has_method("clear_active_action"):
				owner_player.call("clear_active_action")
				return true
			return false
		_:
			var target_action: CharacterAction = _get_route_target_action(route)
			if target_action == null:
				return false
			if owner_player.has_method("_can_execute_action_while_carrying"):
				if not bool(owner_player.call("_can_execute_action_while_carrying", target_action)):
					return false
			if route.activation_mode == AbilityRoute.ActivationMode.ACTIVATE:
				return target_action.activate(route_context)
			return target_action.execute(route_context)


func _get_route_target_action(route: AbilityRoute) -> CharacterAction:
	if route == null:
		return null
	if route.target_action == NodePath():
		return null
	if not has_node(route.target_action):
		return null
	var target_node: Node = get_node(route.target_action)
	if not (target_node is CharacterAction):
		return null
	return target_node


func _route_matches_input(route: AbilityRoute, input_name: StringName, mode: ActionTrigger, context: Dictionary = {}) -> bool:
	if route == null:
		return false
	if route.trigger_mode != _action_trigger_to_route_trigger(mode):
		return false
	if route.trigger_input != input_name:
		return false
	return _route_is_allowed(route, context)


func _route_is_allowed(route: AbilityRoute, context: Dictionary = {}) -> bool:
	if route == null:
		return false
	if not route.enabled:
		return false
	if owner_player == null:
		return false
	if route.block_during_race_countdown and bool(owner_player.get("race_in_countdown")):
		return false
	if not _route_state_matches(route):
		return false
	var source_action: StringName = _get_route_source_action(context)
	if _route_source_blocked(source_action, route.blocked_source_actions):
		return false
	if not _route_source_allowed(source_action, route.allowed_source_actions):
		return false
	return true


func _route_state_matches(route: AbilityRoute) -> bool:
	if route.required_state == AbilityRoute.RequiredState.ANY:
		return true
	var is_grounded: bool = bool(owner_player.get("attached"))
	if route.required_state == AbilityRoute.RequiredState.GROUNDED:
		return is_grounded
	if route.required_state == AbilityRoute.RequiredState.AIRBORNE:
		return not is_grounded
	return true


func _get_route_source_action(context: Dictionary = {}) -> StringName:
	if context.has("source_action"):
		return StringName(context.get("source_action", &""))
	return action_id


func _route_source_allowed(source_action: StringName, allowed_sources: Array[StringName]) -> bool:
	if allowed_sources.is_empty():
		return true
	for allowed_source: StringName in allowed_sources:
		if allowed_source == source_action:
			return true
	return false


func _route_source_blocked(source_action: StringName, blocked_sources: Array[StringName]) -> bool:
	for blocked_source: StringName in blocked_sources:
		if blocked_source == source_action:
			return true
	return false


func _action_trigger_to_route_trigger(mode: ActionTrigger) -> AbilityRoute.TriggerMode:
	match mode:
		ActionTrigger.JUST_PRESSED:
			return AbilityRoute.TriggerMode.JUST_PRESSED
		ActionTrigger.PRESSED:
			return AbilityRoute.TriggerMode.PRESSED
		ActionTrigger.JUST_RELEASED:
			return AbilityRoute.TriggerMode.JUST_RELEASED
		_:
			return AbilityRoute.TriggerMode.NONE


func _action_trigger_to_profile_route_event(mode: ActionTrigger) -> StringName:
	match mode:
		ActionTrigger.JUST_PRESSED:
			return CharacterProfileManager.ROUTE_EVENT_INPUT_PRESSED
		ActionTrigger.PRESSED:
			return CharacterProfileManager.ROUTE_EVENT_INPUT_HELD
		ActionTrigger.JUST_RELEASED:
			return CharacterProfileManager.ROUTE_EVENT_INPUT_RELEASED
	return &""


func _get_sorted_routes() -> Array[AbilityRoute]:
	var sorted_routes: Array[AbilityRoute] = []
	for route_resource: Resource in routes:
		if route_resource is AbilityRoute:
			var route: AbilityRoute = route_resource
			sorted_routes.append(route)
	sorted_routes.sort_custom(func(a: AbilityRoute, b: AbilityRoute) -> bool: return a.priority > b.priority)
	return sorted_routes


func play_cmd_for_action(base_action_name: StringName, send_net: bool = true) -> bool:
	if owner_player == null:
		return false
	if owner_player.has_method("play_action_command_if_exists"):
		return bool(owner_player.call("play_action_command_if_exists", base_action_name, send_net))
	return false


func play_activation_voice() -> void:
	if not owner_player:
		return
	if activation_voice_clips.is_empty():
		return
	if owner_player.has_method("play_voice_clips"):
		owner_player.call("play_voice_clips", activation_voice_clips, activation_voice_chance)

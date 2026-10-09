extends RefCounted
class_name PlayerActionPromptResolver

var _owner: Node = null


func _init(player: Node) -> void:
	_owner = player


func get_prompts() -> Array[Dictionary]:
	var prompts: Array[Dictionary] = []
	if not is_instance_valid(_owner) or not _owner.can_offer_action_prompts():
		return prompts
	var router: PlayerAbilityInputRouter = _owner._ability_input_router
	if not router:
		return prompts
	var claimed: Dictionary = {}
	var cleared_inputs: Dictionary = {}
	var source: StringName = _owner._get_character_profile_route_source_action()
	var context: Dictionary = {"source_action": source, "reason": &"input_prompt", "input_prompt": true}
	_append_direct_prompts(prompts, claimed, context, CharacterAction.InputPromptStage.PRIORITY)
	_append_direct_prompts(prompts, claimed, context, CharacterAction.InputPromptStage.BEFORE_ROUTES)
	_append_routes(prompts, claimed, cleared_inputs, context, true)
	_append_direct_prompts(prompts, claimed, context, CharacterAction.InputPromptStage.AFTER_PREEMPTIVE_ROUTES)
	_append_coyote_prompt(prompts, claimed, context)
	_append_routes(prompts, claimed, cleared_inputs, context, false)
	_append_direct_prompts(prompts, claimed, context, CharacterAction.InputPromptStage.NORMAL)
	prompts.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_priority: int = int(first.get("display_priority", 0))
		var second_priority: int = int(second.get("display_priority", 0))
		if first_priority != second_priority:
			return first_priority > second_priority
		return String(first["sort_key"]) < String(second["sort_key"])
	)
	return prompts


func _append_coyote_prompt(prompts: Array[Dictionary], claimed: Dictionary, context: Dictionary) -> void:
	var jump_slot: StringName = _owner.get_ability_input_slot(&"jump", &"ability_slot_01")
	if _owner.can_consume_coyote_jump():
		var jump_action: CharacterAction = _owner._get_action_by_id(&"jump")
		var homing_action: CharacterAction = _owner._get_action_by_id(&"homing")
		var target: CharacterAction = jump_action
		if _owner.coyote_jump_homing_priority and homing_action and not homing_action.get_input_prompt(context).is_empty():
			target = homing_action
		if target:
			_append_prompt(prompts, claimed, target, {"slot": jump_slot, "gesture": &"press"}, context)


func _append_routes(prompts: Array[Dictionary], claimed: Dictionary, cleared_inputs: Dictionary, context: Dictionary, preemptive: bool) -> void:
	var router: PlayerAbilityInputRouter = _owner._ability_input_router
	for route: Dictionary in router.get_input_prompt_routes(StringName(context["source_action"])):
		var is_preemptive: bool = StringName(route.get("event", &"")) == &"input_pressed" and bool(route.get("suppress_input_until_release", false))
		if is_preemptive != preemptive:
			continue
		if not _owner.is_character_profile_route_allowed(route, context):
			continue
		var activation: StringName = StringName(route.get("activation", &"execute"))
		var input_ability: StringName = StringName(route.get("input_ability", &""))
		if input_ability == &"" and StringName(route.get("event", &"")) == &"ability_triggered":
			input_ability = StringName(context["source_action"])
		var binding: Dictionary = router.get_binding(input_ability)
		if binding.is_empty():
			binding = {"slot": router.resolve_route_input_action(route), "gesture": &"press"}
		binding["ability_id"] = input_ability
		match StringName(route.get("event", &"")):
			&"input_pressed": binding["gesture"] = &"press"
			&"input_held": binding["gesture"] = &"hold"
			&"input_released": binding["gesture"] = &"release"
		var binding_key: String = _get_binding_key(binding)
		if activation == &"clear_active" or activation == &"neutral_air":
			if bool(route.get("consume_input", true)):
				claimed[binding_key] = true
			elif activation == &"clear_active":
				cleared_inputs[binding_key] = true
			continue
		var action: CharacterAction = _owner._get_action_by_id(StringName(route.get("target_action", &"")))
		if not action:
			continue
		var route_context: Dictionary = context.duplicate()
		route_context["route"] = StringName(route.get("route_id", &""))
		route_context["reason"] = StringName(route.get("reason", &"input_prompt"))
		route_context["activation"] = activation
		route_context["input_prompt_clear_active"] = cleared_inputs.has(binding_key)
		_append_prompt(prompts, claimed, action, binding, route_context, bool(route.get("consume_input", true)))


func _append_direct_prompts(prompts: Array[Dictionary], claimed: Dictionary, context: Dictionary, stage: int) -> void:
	var router: PlayerAbilityInputRouter = _owner._ability_input_router
	for action: CharacterAction in _owner._actions:
		if not action or not action.enabled or action.input_action == &"":
			continue
		if action.get_input_prompt_stage() != stage:
			continue
		if _owner._active_action and action != _owner._active_action and not action.allow_when_inactive:
			continue
		if stage == CharacterAction.InputPromptStage.NORMAL and _owner.uses_authoritative_character_profile_routes() and router.is_action_routed_from_input(StringName(context["source_action"]), action.input_action, action.action_id):
			continue
		var binding: Dictionary = router.get_binding(action.action_id)
		if binding.is_empty():
			binding = {"slot": action.input_action, "gesture": _get_trigger_gesture(action.trigger_mode)}
		binding["ability_id"] = action.action_id
		_append_prompt(prompts, claimed, action, binding, context)


func _append_prompt(prompts: Array[Dictionary], claimed: Dictionary, action: CharacterAction, binding: Dictionary, context: Dictionary, consume: bool = true) -> void:
	if not action.enabled or not _owner._can_execute_action_while_carrying(action):
		return
	var presentation: Dictionary = action.get_input_prompt(context)
	if presentation.is_empty():
		return
	if presentation.has("input_action"):
		binding = {"slot": presentation["input_action"], "gesture": presentation.get("gesture", &"press")}
	var slots: Array[StringName] = []
	var primary: StringName = StringName(binding.get("slot", &""))
	if primary != &"":
		slots.append(primary)
	for value: Variant in binding.get("required_slots", []):
		var slot: StringName = StringName(value)
		if slot != &"" and not slots.has(slot):
			slots.append(slot)
	if slots.is_empty():
		return
	var gesture: StringName = StringName(binding.get("gesture", &"press"))
	var ability_id: StringName = StringName(binding.get("ability_id", &""))
	if not _owner._ability_input_router.are_prompt_slots_available(slots, ability_id, gesture):
		return
	gesture = StringName(presentation.get("gesture", gesture))
	var sorted_slots: Array[StringName] = slots.duplicate()
	sorted_slots.sort()
	var parts: PackedStringArray = []
	for slot: StringName in sorted_slots:
		parts.append(String(slot))
	var key: String = "+".join(parts) + ":" + String(gesture)
	if claimed.has(key):
		return
	var name: String = String(presentation.get("label", ""))
	if name.is_empty() and _owner.character_settings_profile:
		name = String(_owner.character_settings_profile.get_ability_definition(action.action_id).get("display_name", ""))
	if name.is_empty():
		name = String(action.action_id).capitalize()
	prompts.append({"id": key + ":" + String(action.action_id), "action_id": action.action_id, "label": name, "slots": slots, "gesture": gesture, "hold_time": float(binding.get("hold_time", 0.0)), "display_priority": int(presentation.get("display_priority", 0)), "contextual": bool(presentation.get("contextual", false)), "sort_key": key})
	if consume:
		claimed[key] = true
		for blocked_gesture: Variant in presentation.get("blocked_gestures", []):
			claimed["+".join(parts) + ":" + String(blocked_gesture)] = true


func _get_trigger_gesture(trigger: int) -> StringName:
	match trigger:
		CharacterAction.ActionTrigger.TAP: return &"tap"
		CharacterAction.ActionTrigger.HOLD, CharacterAction.ActionTrigger.PRESSED: return &"hold"
		CharacterAction.ActionTrigger.JUST_RELEASED: return &"release"
	return &"press"


func _get_binding_key(binding: Dictionary) -> String:
	var slots: PackedStringArray = []
	var primary: String = String(binding.get("slot", ""))
	if primary:
		slots.append(primary)
	for value: Variant in binding.get("required_slots", []):
		var slot: String = String(value)
		if slot and not slots.has(slot):
			slots.append(slot)
	slots.sort()
	return "+".join(slots) + ":" + String(binding.get("gesture", &"press"))

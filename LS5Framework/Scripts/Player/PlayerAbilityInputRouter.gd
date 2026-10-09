extends RefCounted
class_name PlayerAbilityInputRouter

var owner_player: Node = null
var profile: CharacterSettingsProfile = null

var _bindings: Dictionary = {}
var _binding_slots: Dictionary = {}
var _binding_group_keys: Dictionary = {}
var _routes: Array[Dictionary] = []
var _sorted_routes: Array[Dictionary] = []
var _input_route_index: Dictionary = {}
var _monitored_groups: Array[Dictionary] = []
var _monitored_slots: Array[StringName] = []
var _gesture_held_times: Dictionary = {}
var _gesture_previous_held_times: Dictionary = {}
var _gesture_release_times: Dictionary = {}
var _gesture_hold_claimed: Dictionary = {}
var _gesture_suppressed: Dictionary = {}
var _gesture_active: Dictionary = {}
var _gesture_previous_active: Dictionary = {}
var _slot_held_times: Dictionary = {}
var _suppressed_slot_groups: Array[Dictionary] = []


func _init(pawn: Node, settings_profile: CharacterSettingsProfile) -> void:
	owner_player = pawn
	profile = settings_profile
	reload_profile()
	if CharacterProfileManager != null and not CharacterProfileManager.character_profile_changed.is_connected(_on_character_profile_changed):
		CharacterProfileManager.character_profile_changed.connect(_on_character_profile_changed)


func dispose() -> void:
	if CharacterProfileManager != null and CharacterProfileManager.character_profile_changed.is_connected(_on_character_profile_changed):
		CharacterProfileManager.character_profile_changed.disconnect(_on_character_profile_changed)
	owner_player = null
	profile = null
	_bindings.clear()
	_binding_slots.clear()
	_binding_group_keys.clear()
	_routes.clear()
	_sorted_routes.clear()
	_input_route_index.clear()
	_monitored_groups.clear()
	_monitored_slots.clear()
	_clear_gesture_state()


func set_profile(settings_profile: CharacterSettingsProfile) -> void:
	profile = settings_profile
	reload_profile()


func reload_profile() -> void:
	_bindings.clear()
	_binding_slots.clear()
	_binding_group_keys.clear()
	_routes.clear()
	_input_route_index.clear()
	_clear_gesture_state()
	if profile:
		for binding: Dictionary in CharacterProfileManager.get_effective_loadout(profile):
			var ability_id: StringName = StringName(binding.get("ability_id", &""))
			if ability_id != &"":
				_bindings[ability_id] = binding.duplicate(true)
				_binding_slots[ability_id] = _get_binding_slots(binding)
				_binding_group_keys[ability_id] = _get_binding_group_key(binding)
		_routes = CharacterProfileManager.get_effective_routes(profile)
	_sorted_routes = _routes.duplicate(true)
	_sorted_routes.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.get("priority", 10)) > int(second.get("priority", 10))
	)
	_cache_monitored_bindings()
	_cache_input_routes()


func _cache_input_routes() -> void:
	for route: Dictionary in _routes:
		var event: StringName = StringName(route.get("event", &""))
		if event != CharacterProfileManager.ROUTE_EVENT_ABILITY_TRIGGERED and event != CharacterProfileManager.ROUTE_EVENT_INPUT_PRESSED and event != CharacterProfileManager.ROUTE_EVENT_INPUT_HELD and event != CharacterProfileManager.ROUTE_EVENT_INPUT_RELEASED:
			continue
		var source: StringName = StringName(route.get("source_action", &""))
		var target: StringName = StringName(route.get("target_action", &""))
		if not _input_route_index.has(source):
			_input_route_index[source] = {}
		var targets: Dictionary = _input_route_index[source]
		if not targets.has(target):
			targets[target] = {}
		var inputs: Dictionary = targets[target]
		inputs[resolve_route_input_action(route)] = true


func update(delta: float) -> void:
	_update_slot_suppression()
	_update_slot_held_times(delta)
	for group: Dictionary in _monitored_groups:
		var group_key: String = group.key
		if _slots_are_emote_blocked(group.slots):
			_gesture_active[group_key] = false
			_gesture_previous_active[group_key] = false
			_gesture_held_times[group_key] = 0.0
			_gesture_previous_held_times[group_key] = 0.0
			_gesture_release_times[group_key] = 0.0
			continue
		var slots: Array[StringName] = group.slots
		var was_active: bool = bool(_gesture_active.get(group_key, false))
		var is_active: bool = _are_slots_pressed(slots)
		var previous_time: float = float(_gesture_held_times.get(group_key, 0.0))
		_gesture_previous_active[group_key] = was_active
		_gesture_active[group_key] = is_active
		_gesture_previous_held_times[group_key] = previous_time
		if was_active and not is_active:
			_gesture_release_times[group_key] = previous_time
		elif not is_active and not _are_any_slots_pressed(slots):
			_gesture_hold_claimed[group_key] = false
			_gesture_suppressed[group_key] = false
		if is_active:
			_gesture_held_times[group_key] = previous_time + max(delta, 0.0)
		else:
			_gesture_held_times[group_key] = 0.0


func _cache_monitored_bindings() -> void:
	_monitored_groups.clear()
	_monitored_slots.clear()
	var updated_groups: Dictionary = {}
	var monitored_bindings: Array[Dictionary] = []
	for slot_definition: Dictionary in CharacterProfileManager.INPUT_SLOTS:
		monitored_bindings.append({"slot": StringName(slot_definition.get("slot", &""))})
	for binding_value: Variant in _bindings.values():
		if not (binding_value is Dictionary):
			continue
		monitored_bindings.append(binding_value as Dictionary)
	for binding: Dictionary in monitored_bindings:
		var slots: Array[StringName] = _get_binding_slots(binding)
		for slot: StringName in slots:
			if not _monitored_slots.has(slot):
				_monitored_slots.append(slot)
		var group_key: String = _get_binding_group_key(binding)
		if group_key == "" or updated_groups.has(group_key):
			continue
		updated_groups[group_key] = true
		_monitored_groups.append({"key": group_key, "slots": slots})


func get_binding(ability_id: StringName) -> Dictionary:
	if _bindings.has(ability_id):
		return (_bindings[ability_id] as Dictionary).duplicate(true)
	return {}


func has_binding(ability_id: StringName) -> bool:
	return _bindings.has(ability_id)


func _get_resolved_slots(ability_id: StringName, fallback_slot: StringName) -> Array[StringName]:
	if _binding_slots.has(ability_id):
		return _binding_slots[ability_id]
	var slots: Array[StringName] = []
	if fallback_slot != &"":
		slots.append(fallback_slot)
	return slots


func _get_resolved_group_key(ability_id: StringName, fallback_slot: StringName) -> String:
	return String(_binding_group_keys.get(ability_id, fallback_slot))


func get_input_slot(ability_id: StringName, fallback: StringName = &"") -> StringName:
	var binding: Dictionary = _bindings.get(ability_id, {})
	return StringName(binding.get("slot", fallback))


func get_gesture(ability_id: StringName, fallback: StringName = &"press") -> StringName:
	var binding: Dictionary = _bindings.get(ability_id, {})
	return StringName(binding.get("gesture", fallback))


func get_hold_time(ability_id: StringName, fallback: float = 0.0) -> float:
	var binding: Dictionary = _bindings.get(ability_id, {})
	return max(float(binding.get("hold_time", fallback)), 0.0)


func is_binding_hold_modifier_pressed(ability_id: StringName, fallback_slot: StringName = &"") -> bool:
	var binding: Dictionary = _bindings.get(ability_id, {})
	if not bool(binding.get("modifier_bypasses_hold", false)):
		return false
	var primary: StringName = StringName(binding.get("slot", fallback_slot))
	var modifier: StringName = StringName(binding.get("modifier_slot", &""))
	var modifier_ability: StringName = StringName(binding.get("modifier_ability_id", &""))
	if modifier_ability != &"":
		modifier = get_input_slot(modifier_ability, modifier)
	return modifier != &"" and modifier != primary and SettingsManager.is_gameplay_action_pressed(String(modifier))


func binding_uses_slot(ability_id: StringName, slot: StringName, fallback_slot: StringName = &"") -> bool:
	if slot == &"":
		return false
	return _get_resolved_slots(ability_id, fallback_slot).has(slot)


func is_binding_pressed(ability_id: StringName, fallback: StringName = &"") -> bool:
	return _are_slots_pressed(_get_resolved_slots(ability_id, fallback))


func is_binding_just_pressed(ability_id: StringName, fallback: StringName = &"") -> bool:
	if _slots_are_emote_blocked(_get_resolved_slots(ability_id, fallback)):
		return false
	var group_key: String = _get_resolved_group_key(ability_id, fallback)
	return group_key != "" and bool(_gesture_active.get(group_key, false)) and not bool(_gesture_previous_active.get(group_key, false))


func is_binding_simultaneously_just_pressed(
	ability_id: StringName,
	fallback: StringName = &"",
	press_window: float = 0.08
) -> bool:
	if _slots_are_emote_blocked(_get_resolved_slots(ability_id, fallback)):
		return false
	var group_key: String = _get_resolved_group_key(ability_id, fallback)
	if group_key == "" or not bool(_gesture_active.get(group_key, false)) or bool(_gesture_previous_active.get(group_key, false)):
		return false
	return _were_slots_pressed_within(_get_resolved_slots(ability_id, fallback), max(press_window, 0.0))


func is_binding_just_released(ability_id: StringName, fallback: StringName = &"") -> bool:
	if _slots_are_emote_blocked(_get_resolved_slots(ability_id, fallback)):
		return false
	var group_key: String = _get_resolved_group_key(ability_id, fallback)
	return group_key != "" and not bool(_gesture_active.get(group_key, false)) and bool(_gesture_previous_active.get(group_key, false))


func is_binding_triggered(ability_id: StringName, fallback_slot: StringName = &"", fallback_gesture: StringName = &"press", fallback_hold_time: float = 0.0) -> bool:
	if _slots_are_emote_blocked(_get_resolved_slots(ability_id, fallback_slot)):
		return false
	var binding: Dictionary = _bindings.get(ability_id, {})
	var slot: StringName = StringName(binding.get("slot", fallback_slot))
	var gesture: StringName = StringName(binding.get("gesture", fallback_gesture))
	var hold_time: float = max(float(binding.get("hold_time", fallback_hold_time)), 0.0)
	if slot == &"":
		return false
	if binding.is_empty():
		binding = {"ability_id": ability_id, "slot": slot, "gesture": gesture, "hold_time": hold_time}
	var group_key: String = _get_resolved_group_key(ability_id, slot)
	if bool(_gesture_suppressed.get(group_key, false)):
		return false
	match gesture:
		CharacterProfileManager.GESTURE_TAP:
			if not is_binding_just_released(ability_id, slot):
				return false
			if bool(_gesture_hold_claimed.get(group_key, false)):
				return false
			return float(_gesture_release_times.get(group_key, 0.0)) < hold_time
		CharacterProfileManager.GESTURE_HOLD:
			if _modifier_bypasses_hold(binding, slot):
				_gesture_hold_claimed[group_key] = true
				return true
			if not _are_slots_pressed(_get_resolved_slots(ability_id, slot)):
				return false
			var previous_time: float = float(_gesture_previous_held_times.get(group_key, 0.0))
			var current_time: float = float(_gesture_held_times.get(group_key, 0.0))
			var crossed_threshold: bool = previous_time < hold_time and current_time >= hold_time
			if crossed_threshold:
				_gesture_hold_claimed[group_key] = true
			return crossed_threshold
		CharacterProfileManager.GESTURE_RELEASE:
			return is_binding_just_released(ability_id, slot)
		_:
			return is_binding_just_pressed(ability_id, slot)


func get_input_slots(ability_id: StringName, fallback_slot: StringName = &"") -> Array[StringName]:
	return _get_resolved_slots(ability_id, fallback_slot).duplicate()


func are_prompt_slots_available(slots: Array[StringName], ability_id: StringName, gesture: StringName) -> bool:
	if slots.is_empty() or _slots_are_emote_blocked(slots):
		return false
	var group_key: String = _get_binding_group_key({"slot": slots[0], "required_slots": slots.slice(1)})
	if bool(_gesture_suppressed.get(group_key, false)):
		return false
	if gesture == &"tap" and bool(_gesture_hold_claimed.get(group_key, false)):
		return false
	if gesture == &"release" and not _are_slots_pressed(slots):
		return false
	return ability_id == &"" or not EmoteWheel.is_action_blocked(get_input_slot(ability_id))


func get_input_prompt_routes(source_action: StringName) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	var preemptive: Array[Dictionary] = []
	for route: Dictionary in _sorted_routes:
		if not bool(route.get("enabled", true)) or StringName(route.get("source_action", &"")) != source_action:
			continue
		var event: StringName = StringName(route.get("event", &""))
		if event != &"ability_triggered" and event != &"input_pressed" and event != &"input_held" and event != &"input_released":
			continue
		if event == &"input_pressed" and bool(route.get("suppress_input_until_release", false)):
			preemptive.append(route.duplicate(true))
		else:
			matching.append(route.duplicate(true))
	preemptive.append_array(matching)
	return preemptive


func suppress_slots_until_release(slots: Array[StringName]) -> void:
	_suppressed_slot_groups.append({"slots": slots.duplicate(), "released": false})
	for group: Dictionary in _monitored_groups:
		for slot: StringName in slots:
			if group.slots.has(slot):
				_gesture_hold_claimed[group.key] = true


func _update_slot_suppression() -> void:
	for index: int in range(_suppressed_slot_groups.size() - 1, -1, -1):
		var group: Dictionary = _suppressed_slot_groups[index]
		if bool(group.released):
			_suppressed_slot_groups.remove_at(index)
		elif not _are_any_slots_pressed(group.slots):
			group.released = true


func suppress_binding_until_release(ability_id: StringName, fallback_slot: StringName = &"") -> void:
	var group_key: String = _get_resolved_group_key(ability_id, fallback_slot)
	if group_key == "":
		return
	_gesture_suppressed[group_key] = true
	_gesture_hold_claimed[group_key] = true


func get_triggered_input_routes(source_action: StringName, preemptive_only: bool = false) -> Array[Dictionary]:
	var triggered: Array[Dictionary] = []
	for route: Dictionary in _get_sorted_routes():
		if not bool(route.get("enabled", true)):
			continue
		if StringName(route.get("source_action", &"")) != source_action:
			continue
		var is_preemptive: bool = bool(route.get("suppress_input_until_release", false)) and StringName(route.get("event", &"")) == CharacterProfileManager.ROUTE_EVENT_INPUT_PRESSED
		if is_preemptive != preemptive_only:
			continue
		if _route_input_is_triggered(route):
			triggered.append(route.duplicate(true))
	return triggered


func get_event_routes(source_action: StringName, event: StringName, route_id: StringName = &"") -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for route: Dictionary in _get_sorted_routes():
		if not bool(route.get("enabled", true)):
			continue
		if StringName(route.get("source_action", &"")) != source_action:
			continue
		if StringName(route.get("event", &"")) != event:
			continue
		if route_id != &"" and StringName(route.get("route_id", &"")) != route_id:
			continue
		matching.append(route.duplicate(true))
	return matching


func has_route_channel(source_action: StringName, event: StringName, route_id: StringName = &"", input_action: StringName = &"") -> bool:
	for route: Dictionary in _routes:
		if StringName(route.get("source_action", &"")) != source_action:
			continue
		if StringName(route.get("event", &"")) != event:
			continue
		if route_id != &"" and StringName(route.get("route_id", &"")) != route_id:
			continue
		if input_action != &"" and resolve_route_input_action(route) != input_action:
			continue
		return true
	return false


func has_route_id(source_action: StringName, route_id: StringName) -> bool:
	if route_id == &"":
		return false
	for route: Dictionary in _routes:
		if StringName(route.get("source_action", &"")) == source_action and StringName(route.get("route_id", &"")) == route_id:
			return true
	return false


func has_input_route(source_action: StringName, input_action: StringName) -> bool:
	for route: Dictionary in _routes:
		if StringName(route.get("source_action", &"")) != source_action:
			continue
		var event: StringName = StringName(route.get("event", &""))
		if event != CharacterProfileManager.ROUTE_EVENT_ABILITY_TRIGGERED and event != CharacterProfileManager.ROUTE_EVENT_INPUT_PRESSED and event != CharacterProfileManager.ROUTE_EVENT_INPUT_HELD and event != CharacterProfileManager.ROUTE_EVENT_INPUT_RELEASED:
			continue
		if resolve_route_input_action(route) == input_action:
			return true
	return false


func is_action_routed_from_input(source_action: StringName, input_action: StringName, target_action: StringName) -> bool:
	var targets: Dictionary = _input_route_index.get(source_action, {})
	var inputs: Dictionary = targets.get(target_action, {})
	return inputs.has(input_action)


func resolve_route_input_action(route: Dictionary) -> StringName:
	var input_ability: StringName = StringName(route.get("input_ability", &""))
	if input_ability != &"":
		return get_input_slot(input_ability, StringName(route.get("input_action", &"")))
	var input_action: StringName = StringName(route.get("input_action", &""))
	if input_action != &"":
		return input_action
	var source_action: StringName = StringName(route.get("source_action", &""))
	return get_input_slot(source_action, &"")


func _route_input_is_triggered(route: Dictionary) -> bool:
	var event: StringName = StringName(route.get("event", &""))
	var input_action: StringName = resolve_route_input_action(route)
	if input_action == &"":
		return false
	var input_ability: StringName = StringName(route.get("input_ability", &""))
	match event:
		CharacterProfileManager.ROUTE_EVENT_ABILITY_TRIGGERED:
			if input_ability == &"":
				input_ability = StringName(route.get("source_action", &""))
			return input_ability != &"" and is_binding_triggered(input_ability, input_action)
		CharacterProfileManager.ROUTE_EVENT_INPUT_PRESSED:
			if input_ability != &"":
				return is_binding_just_pressed(input_ability, input_action)
			return SettingsManager.is_gameplay_action_just_pressed(String(input_action))
		CharacterProfileManager.ROUTE_EVENT_INPUT_HELD:
			if input_ability != &"":
				return is_binding_pressed(input_ability, input_action)
			return SettingsManager.is_gameplay_action_pressed(String(input_action))
		CharacterProfileManager.ROUTE_EVENT_INPUT_RELEASED:
			if input_ability != &"":
				return is_binding_just_released(input_ability, input_action)
			return SettingsManager.is_gameplay_action_just_released(String(input_action))
	return false


func _get_sorted_routes() -> Array[Dictionary]:
	return _sorted_routes


func _modifier_bypasses_hold(binding: Dictionary, slot: StringName) -> bool:
	if not bool(binding.get("modifier_bypasses_hold", false)):
		return false
	var modifier_slot: StringName = StringName(binding.get("modifier_slot", &""))
	var modifier_ability_id: StringName = StringName(binding.get("modifier_ability_id", &""))
	if modifier_ability_id != &"" and _bindings.has(modifier_ability_id):
		modifier_slot = StringName((_bindings[modifier_ability_id] as Dictionary).get("slot", modifier_slot))
	if modifier_slot == &"" or modifier_slot == slot or not SettingsManager.is_gameplay_action_pressed(String(modifier_slot)):
		return false
	var group_key: String = _get_binding_group_key(binding)
	var binding_just_pressed: bool = bool(_gesture_active.get(group_key, false)) and not bool(_gesture_previous_active.get(group_key, false))
	return binding_just_pressed or (SettingsManager.is_gameplay_action_just_pressed(String(modifier_slot)) and _are_binding_slots_pressed(binding))


func _get_binding_slots(binding: Dictionary) -> Array[StringName]:
	var slots: Array[StringName] = []
	var primary_slot: StringName = StringName(binding.get("slot", &""))
	if primary_slot != &"":
		slots.append(primary_slot)
	var required_slots_value: Variant = binding.get("required_slots", [])
	if required_slots_value is Array:
		for required_slot_value: Variant in required_slots_value:
			var required_slot: StringName = StringName(required_slot_value)
			if required_slot != &"" and not slots.has(required_slot):
				slots.append(required_slot)
	return slots


func _are_binding_slots_pressed(binding: Dictionary) -> bool:
	return _are_slots_pressed(_get_binding_slots(binding))


func _slots_are_emote_blocked(slots: Array[StringName]) -> bool:
	for group: Dictionary in _suppressed_slot_groups:
		for slot: StringName in slots:
			if group.slots.has(slot):
				return true
	for slot: StringName in slots:
		if EmoteWheel.is_action_blocked(slot):
			return true
	return false


func _are_slots_pressed(slots: Array[StringName]) -> bool:
	if slots.is_empty():
		return false
	for slot: StringName in slots:
		if not SettingsManager.is_gameplay_action_pressed(String(slot)):
			return false
	return true


func _are_any_slots_pressed(slots: Array[StringName]) -> bool:
	for slot: StringName in slots:
		if SettingsManager.is_gameplay_action_pressed(String(slot)):
			return true
	return false


func _were_slots_pressed_within(slots: Array[StringName], press_window: float) -> bool:
	if slots.size() <= 1:
		return not slots.is_empty()
	for slot: StringName in slots:
		if not _slot_held_times.has(slot):
			return false
		if float(_slot_held_times[slot]) > press_window:
			return false
	return true


func _update_slot_held_times(delta: float) -> void:
	for slot: StringName in _monitored_slots:
		if SettingsManager.is_gameplay_action_just_pressed(String(slot)):
			_slot_held_times[slot] = 0.0
		elif SettingsManager.is_gameplay_action_pressed(String(slot)):
			if _slot_held_times.has(slot):
				_slot_held_times[slot] = float(_slot_held_times[slot]) + max(delta, 0.0)
			else:
				_slot_held_times[slot] = INF
		else:
			_slot_held_times.erase(slot)


func _get_binding_group_key(binding: Dictionary) -> String:
	var slots: Array[StringName] = _get_binding_slots(binding)
	if slots.is_empty():
		return ""
	slots.sort()
	var key_parts: PackedStringArray = PackedStringArray()
	for slot: StringName in slots:
		key_parts.append(String(slot))
	return "+".join(key_parts)


func _clear_gesture_state() -> void:
	_gesture_held_times.clear()
	_gesture_previous_held_times.clear()
	_gesture_release_times.clear()
	_gesture_hold_claimed.clear()
	_gesture_suppressed.clear()
	_gesture_active.clear()
	_gesture_previous_active.clear()
	_slot_held_times.clear()
	_suppressed_slot_groups.clear()


func _on_character_profile_changed(profile_key: String) -> void:
	if profile != null and profile.get_profile_key() == profile_key:
		reload_profile()
		if is_instance_valid(owner_player) and owner_player.has_method("_apply_character_loadout_to_actions"):
			owner_player.call("_apply_character_loadout_to_actions")

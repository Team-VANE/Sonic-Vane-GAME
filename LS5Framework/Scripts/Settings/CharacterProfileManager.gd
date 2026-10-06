extends Node

signal character_profile_changed(profile_key: String)

const CONFIG_PATH: String = "user://character_profiles.cfg"
const SECTION_PREFIX: String = "profile/"

const SLOT_01: StringName = &"ability_slot_01"
const SLOT_02: StringName = &"ability_slot_02"
const SLOT_03: StringName = &"ability_slot_03"
const SLOT_04: StringName = &"ability_slot_04"
const SLOT_05: StringName = &"ability_slot_05"
const SLOT_06: StringName = &"ability_slot_06"
const SLOT_07: StringName = &"ability_slot_07"
const SLOT_08: StringName = &"ability_slot_08"
const SLOT_09: StringName = &"ability_slot_09"
const SLOT_10: StringName = &"ability_slot_10"
const SLOT_11: StringName = &"ability_slot_11"
const SLOT_12: StringName = &"ability_slot_12"
const SLOT_13: StringName = &"ability_slot_13"
const SLOT_14: StringName = &"ability_slot_14"
const SLOT_15: StringName = &"ability_slot_15"
const SLOT_16: StringName = &"ability_slot_16"

const SLOT_NAME_MIGRATIONS: Dictionary = {
	&"action_0": SLOT_01,
	&"action_1": SLOT_02,
	&"action_3": SLOT_03,
	&"action_7": SLOT_04,
	&"action_8": SLOT_05,
	&"ability_jump": SLOT_01,
	&"ability_primary": SLOT_02,
	&"ability_secondary": SLOT_03,
	&"ability_roll": SLOT_04,
	&"ability_drift": SLOT_05,
}

const GESTURE_PRESS: StringName = &"press"
const GESTURE_TAP: StringName = &"tap"
const GESTURE_HOLD: StringName = &"hold"
const GESTURE_RELEASE: StringName = &"release"

const ROUTE_EVENT_ABILITY_TRIGGERED: StringName = &"ability_triggered"
const ROUTE_EVENT_INPUT_PRESSED: StringName = &"input_pressed"
const ROUTE_EVENT_INPUT_HELD: StringName = &"input_held"
const ROUTE_EVENT_INPUT_RELEASED: StringName = &"input_released"
const ROUTE_EVENT_MANUAL: StringName = &"manual"
const ROUTE_EVENT_COMPLETED: StringName = &"completed"
const ROUTE_EVENT_POLICY: StringName = &"policy"

const ROUTE_ACTIVATION_EXECUTE: StringName = &"execute"
const ROUTE_ACTIVATION_ACTIVATE: StringName = &"activate"
const ROUTE_ACTIVATION_TOGGLE_ON: StringName = &"toggle_on"
const ROUTE_ACTIVATION_TOGGLE_OFF: StringName = &"toggle_off"
const ROUTE_ACTIVATION_NEUTRAL_AIR: StringName = &"neutral_air"
const ROUTE_ACTIVATION_CLEAR_ACTIVE: StringName = &"clear_active"

const ROUTE_STATE_ANY: StringName = &"any"
const ROUTE_STATE_GROUNDED: StringName = &"grounded"
const ROUTE_STATE_AIRBORNE: StringName = &"airborne"

const INPUT_SLOTS: Array[Dictionary] = [
	{"slot": SLOT_01, "label": "Ability Slot 1"},
	{"slot": SLOT_02, "label": "Ability Slot 2"},
	{"slot": SLOT_03, "label": "Ability Slot 3"},
	{"slot": SLOT_04, "label": "Ability Slot 4"},
	{"slot": SLOT_05, "label": "Ability Slot 5"},
	{"slot": SLOT_06, "label": "Ability Slot 6"},
	{"slot": SLOT_07, "label": "Ability Slot 7"},
	{"slot": SLOT_08, "label": "Ability Slot 8"},
	{"slot": SLOT_09, "label": "Ability Slot 9"},
	{"slot": SLOT_10, "label": "Ability Slot 10"},
	{"slot": SLOT_11, "label": "Ability Slot 11"},
	{"slot": SLOT_12, "label": "Ability Slot 12"},
	{"slot": SLOT_13, "label": "Ability Slot 13"},
	{"slot": SLOT_14, "label": "Ability Slot 14"},
	{"slot": SLOT_15, "label": "Ability Slot 15"},
	{"slot": SLOT_16, "label": "Ability Slot 16"},
]

const GESTURES: Array[Dictionary] = [
	{"gesture": GESTURE_PRESS, "label": "Press"},
	{"gesture": GESTURE_TAP, "label": "Tap"},
	{"gesture": GESTURE_HOLD, "label": "Hold"},
	{"gesture": GESTURE_RELEASE, "label": "Release"},
]

const ROUTE_EVENTS: Array[Dictionary] = [
	{"event": ROUTE_EVENT_ABILITY_TRIGGERED, "label": "Ability Triggered"},
	{"event": ROUTE_EVENT_INPUT_PRESSED, "label": "Input Pressed"},
	{"event": ROUTE_EVENT_INPUT_HELD, "label": "Input Held"},
	{"event": ROUTE_EVENT_INPUT_RELEASED, "label": "Input Released"},
	{"event": ROUTE_EVENT_MANUAL, "label": "Manual Event"},
	{"event": ROUTE_EVENT_COMPLETED, "label": "Action Completed"},
	{"event": ROUTE_EVENT_POLICY, "label": "Activation Policy"},
]

const ROUTE_ACTIVATIONS: Array[Dictionary] = [
	{"activation": ROUTE_ACTIVATION_EXECUTE, "label": "Execute"},
	{"activation": ROUTE_ACTIVATION_ACTIVATE, "label": "Activate State"},
	{"activation": ROUTE_ACTIVATION_TOGGLE_ON, "label": "Toggle On"},
	{"activation": ROUTE_ACTIVATION_TOGGLE_OFF, "label": "Toggle Off"},
	{"activation": ROUTE_ACTIVATION_NEUTRAL_AIR, "label": "Neutral Air"},
	{"activation": ROUTE_ACTIVATION_CLEAR_ACTIVE, "label": "Clear Active"},
]

const ROUTE_STATES: Array[Dictionary] = [
	{"state": ROUTE_STATE_ANY, "label": "Any State"},
	{"state": ROUTE_STATE_GROUNDED, "label": "Grounded"},
	{"state": ROUTE_STATE_AIRBORNE, "label": "Airborne"},
]

var _loadout_overrides: Dictionary = {}
var _route_overrides: Dictionary = {}
var _settings_overrides: Dictionary = {}


func _ready() -> void:
	_load_profiles()


func get_effective_loadout(profile: CharacterSettingsProfile) -> Array[Dictionary]:
	if profile == null:
		return []
	var profile_key: String = profile.get_profile_key()
	var loadout: Array[Dictionary] = _duplicate_dictionary_array(profile.default_loadout)
	if not _loadout_overrides.has(profile_key):
		return _resolve_default_chords(loadout, [])
	for override_binding: Dictionary in _duplicate_dictionary_array(_loadout_overrides[profile_key]):
		var ability_id: StringName = StringName(override_binding.get("ability_id", &""))
		var replaced: bool = false
		for index: int in range(loadout.size()):
			if StringName(loadout[index].get("ability_id", &"")) == ability_id:
				loadout[index] = override_binding
				replaced = true
				break
		if not replaced and ability_id != &"":
			loadout.append(override_binding)
	return _resolve_default_chords(loadout, _duplicate_dictionary_array(_loadout_overrides[profile_key]))


func _resolve_default_chords(loadout: Array[Dictionary], overrides: Array[Dictionary]) -> Array[Dictionary]:
	var overridden: Array[StringName] = []
	var assigned_slots: Dictionary = {}
	for binding: Dictionary in overrides:
		overridden.append(StringName(binding.get("ability_id", &"")))
	for binding: Dictionary in loadout:
		assigned_slots[StringName(binding.get("ability_id", &""))] = StringName(binding.get("slot", &""))
	for binding: Dictionary in loadout:
		if overridden.has(StringName(binding.get("ability_id", &""))):
			continue
		var dependencies: Array = binding.get("chord_abilities", [])
		if dependencies.is_empty():
			continue
		var slots: Array[StringName] = []
		for dependency: Variant in dependencies:
			var slot: StringName = assigned_slots.get(StringName(dependency), &"")
			if slot != &"" and not slots.has(slot):
				slots.append(slot)
		if not slots.is_empty():
			binding["slot"] = slots[0]
			binding["required_slots"] = slots.slice(1)
	return loadout


func get_binding(profile: CharacterSettingsProfile, ability_id: StringName) -> Dictionary:
	if profile == null or ability_id == &"":
		return {}
	for binding: Dictionary in get_effective_loadout(profile):
		if StringName(binding.get("ability_id", &"")) == ability_id:
			return binding
	return profile.get_default_binding(ability_id)


func set_binding(profile: CharacterSettingsProfile, binding: Dictionary) -> void:
	if profile == null:
		return
	var ability_id: StringName = StringName(binding.get("ability_id", &""))
	if ability_id == &"":
		return
	var profile_key: String = profile.get_profile_key()
	var loadout: Array[Dictionary] = []
	if _loadout_overrides.has(profile_key):
		loadout = _duplicate_dictionary_array(_loadout_overrides[profile_key])
	var replaced: bool = false
	for index: int in range(loadout.size()):
		if StringName(loadout[index].get("ability_id", &"")) == ability_id:
			loadout[index] = _sanitize_binding(binding)
			replaced = true
			break
	if not replaced:
		loadout.append(_sanitize_binding(binding))
	_loadout_overrides[profile_key] = loadout
	_save_profiles()
	character_profile_changed.emit(profile_key)


func reset_loadout(profile: CharacterSettingsProfile) -> void:
	if profile == null:
		return
	var profile_key: String = profile.get_profile_key()
	_loadout_overrides.erase(profile_key)
	_save_profiles()
	character_profile_changed.emit(profile_key)


func has_loadout_override(profile: CharacterSettingsProfile) -> bool:
	return profile != null and _loadout_overrides.has(profile.get_profile_key())


func get_effective_routes(profile: CharacterSettingsProfile) -> Array[Dictionary]:
	if profile == null:
		return []
	var profile_key: String = profile.get_profile_key()
	var routes: Array[Dictionary] = _duplicate_route_array(profile.default_routes)
	if not _route_overrides.has(profile_key):
		return routes
	for route_override: Dictionary in _duplicate_route_array(_route_overrides[profile_key]):
		var route_id: StringName = StringName(route_override.get("route_id", &""))
		var replaced: bool = false
		for index: int in range(routes.size()):
			if StringName(routes[index].get("route_id", &"")) == route_id:
				routes[index] = route_override
				replaced = true
				break
		if not replaced and route_id != &"":
			routes.append(route_override)
	return routes


func get_route(profile: CharacterSettingsProfile, route_id: StringName) -> Dictionary:
	if profile == null or route_id == &"":
		return {}
	for route: Dictionary in get_effective_routes(profile):
		if StringName(route.get("route_id", &"")) == route_id:
			return route
	return profile.get_default_route(route_id)


func set_route(profile: CharacterSettingsProfile, route: Dictionary) -> void:
	if profile == null:
		return
	var route_id: StringName = StringName(route.get("route_id", &""))
	if route_id == &"":
		return
	var profile_key: String = profile.get_profile_key()
	var routes: Array[Dictionary] = []
	if _route_overrides.has(profile_key):
		routes = _duplicate_route_array(_route_overrides[profile_key])
	var sanitized: Dictionary = _sanitize_route(route)
	var replaced: bool = false
	for index: int in range(routes.size()):
		if StringName(routes[index].get("route_id", &"")) == route_id:
			routes[index] = sanitized
			replaced = true
			break
	if not replaced:
		routes.append(sanitized)
	_route_overrides[profile_key] = routes
	_save_profiles()
	character_profile_changed.emit(profile_key)


func remove_route(profile: CharacterSettingsProfile, route_id: StringName) -> void:
	if profile == null or route_id == &"":
		return
	var packaged_route: Dictionary = profile.get_default_route(route_id)
	if not packaged_route.is_empty():
		packaged_route["enabled"] = false
		set_route(profile, packaged_route)
		return
	var profile_key: String = profile.get_profile_key()
	if not _route_overrides.has(profile_key):
		return
	var routes: Array[Dictionary] = _duplicate_route_array(_route_overrides[profile_key])
	for index: int in range(routes.size() - 1, -1, -1):
		if StringName(routes[index].get("route_id", &"")) == route_id:
			routes.remove_at(index)
	if routes.is_empty():
		_route_overrides.erase(profile_key)
	else:
		_route_overrides[profile_key] = routes
	_save_profiles()
	character_profile_changed.emit(profile_key)


func reset_routes(profile: CharacterSettingsProfile) -> void:
	if profile == null:
		return
	var profile_key: String = profile.get_profile_key()
	_route_overrides.erase(profile_key)
	_save_profiles()
	character_profile_changed.emit(profile_key)


func has_route_override(profile: CharacterSettingsProfile) -> bool:
	return profile != null and _route_overrides.has(profile.get_profile_key())


func get_effective_settings(profile: CharacterSettingsProfile) -> Dictionary:
	if profile == null:
		return {}
	var settings: Dictionary = profile.default_settings.duplicate(true)
	var profile_key: String = profile.get_profile_key()
	if _settings_overrides.has(profile_key):
		var overrides: Variant = _settings_overrides[profile_key]
		if overrides is Dictionary:
			settings.merge(overrides, true)
	return settings


func set_character_setting(profile: CharacterSettingsProfile, setting_id: StringName, value: Variant) -> void:
	if profile == null or setting_id == &"":
		return
	var profile_key: String = profile.get_profile_key()
	var settings: Dictionary = {}
	if _settings_overrides.has(profile_key) and _settings_overrides[profile_key] is Dictionary:
		settings = (_settings_overrides[profile_key] as Dictionary).duplicate(true)
	settings[setting_id] = value
	_settings_overrides[profile_key] = settings
	_save_profiles()
	character_profile_changed.emit(profile_key)


func get_slot_label(slot: StringName) -> String:
	for slot_definition: Dictionary in INPUT_SLOTS:
		if StringName(slot_definition.get("slot", &"")) == slot:
			return String(slot_definition.get("label", slot))
	return String(slot).capitalize()


func get_gesture_label(gesture: StringName) -> String:
	for gesture_definition: Dictionary in GESTURES:
		if StringName(gesture_definition.get("gesture", &"")) == gesture:
			return String(gesture_definition.get("label", gesture))
	return String(gesture).capitalize()


func get_route_event_label(event: StringName) -> String:
	for definition: Dictionary in ROUTE_EVENTS:
		if StringName(definition.get("event", &"")) == event:
			return String(definition.get("label", event))
	return String(event).capitalize()


func _sanitize_binding(binding: Dictionary) -> Dictionary:
	var sanitized: Dictionary = binding.duplicate(true)
	sanitized["ability_id"] = StringName(binding.get("ability_id", &""))
	var primary_slot: StringName = _normalize_slot(StringName(binding.get("slot", SLOT_01)))
	sanitized["slot"] = primary_slot
	sanitized["gesture"] = StringName(binding.get("gesture", GESTURE_PRESS))
	sanitized["hold_time"] = max(float(binding.get("hold_time", 0.0)), 0.0)
	var required_slots: Array[StringName] = []
	var required_slots_value: Variant = binding.get("required_slots", [])
	if required_slots_value is Array:
		for required_slot_value: Variant in required_slots_value:
			var required_slot: StringName = _normalize_slot(StringName(required_slot_value))
			if required_slot != &"" and required_slot != primary_slot and not required_slots.has(required_slot):
				required_slots.append(required_slot)
	sanitized["required_slots"] = required_slots
	if binding.has("modifier_slot"):
		sanitized["modifier_slot"] = _normalize_slot(StringName(binding.get("modifier_slot", &"")))
	return sanitized


func _sanitize_route(route: Dictionary) -> Dictionary:
	var sanitized: Dictionary = route.duplicate(true)
	sanitized["route_id"] = StringName(route.get("route_id", &""))
	sanitized["display_name"] = String(route.get("display_name", String(sanitized["route_id"]).capitalize()))
	sanitized["source_action"] = StringName(route.get("source_action", &""))
	sanitized["event"] = StringName(route.get("event", ROUTE_EVENT_ABILITY_TRIGGERED))
	sanitized["input_ability"] = StringName(route.get("input_ability", &""))
	sanitized["input_action"] = _normalize_slot(StringName(route.get("input_action", &"")))
	sanitized["target_action"] = StringName(route.get("target_action", &""))
	sanitized["activation"] = StringName(route.get("activation", ROUTE_ACTIVATION_EXECUTE))
	sanitized["required_state"] = StringName(route.get("required_state", ROUTE_STATE_ANY))
	sanitized["priority"] = int(route.get("priority", 10))
	sanitized["reason"] = StringName(route.get("reason", sanitized["route_id"]))
	sanitized["enabled"] = bool(route.get("enabled", true))
	sanitized["consume_input"] = bool(route.get("consume_input", true))
	sanitized["suppress_input_until_release"] = bool(route.get("suppress_input_until_release", false))
	sanitized["block_during_race_countdown"] = bool(route.get("block_during_race_countdown", true))
	sanitized["allowed_source_actions"] = _sanitize_string_name_array(route.get("allowed_source_actions", []))
	sanitized["blocked_source_actions"] = _sanitize_string_name_array(route.get("blocked_source_actions", []))
	return sanitized


func _normalize_slot(slot: StringName) -> StringName:
	return StringName(SLOT_NAME_MIGRATIONS.get(slot, slot))


func _duplicate_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry: Variant in value:
		if entry is Dictionary:
			result.append(_sanitize_binding(entry as Dictionary))
	return result


func _duplicate_route_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry: Variant in value:
		if entry is Dictionary:
			result.append(_sanitize_route(entry as Dictionary))
	return result


func _sanitize_string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not (value is Array):
		return result
	for entry: Variant in value:
		var item: StringName = StringName(entry)
		if item != &"":
			result.append(item)
	return result


func _save_profiles() -> void:
	var config: ConfigFile = ConfigFile.new()
	var profile_keys: Dictionary = {}
	for profile_key: Variant in _loadout_overrides.keys():
		profile_keys[String(profile_key)] = true
	for profile_key: Variant in _route_overrides.keys():
		profile_keys[String(profile_key)] = true
	for profile_key: Variant in _settings_overrides.keys():
		profile_keys[String(profile_key)] = true
	for profile_key_value: Variant in profile_keys.keys():
		var profile_key: String = String(profile_key_value)
		var section: String = SECTION_PREFIX + profile_key
		if _loadout_overrides.has(profile_key):
			config.set_value(section, "loadout", _loadout_overrides[profile_key])
		if _route_overrides.has(profile_key):
			config.set_value(section, "routes", _route_overrides[profile_key])
		if _settings_overrides.has(profile_key):
			config.set_value(section, "settings", _settings_overrides[profile_key])
	config.save(CONFIG_PATH)


func _load_profiles() -> void:
	_loadout_overrides.clear()
	_route_overrides.clear()
	_settings_overrides.clear()
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	for section_value: Variant in config.get_sections():
		var section: String = String(section_value)
		if not section.begins_with(SECTION_PREFIX):
			continue
		var profile_key: String = section.trim_prefix(SECTION_PREFIX)
		var loadout: Variant = config.get_value(section, "loadout", [])
		if loadout is Array:
			_loadout_overrides[profile_key] = _duplicate_dictionary_array(loadout)
		var routes: Variant = config.get_value(section, "routes", [])
		if routes is Array:
			var sanitized_routes: Array[Dictionary] = _duplicate_route_array(routes)
			if not sanitized_routes.is_empty():
				_route_overrides[profile_key] = sanitized_routes
		var settings: Variant = config.get_value(section, "settings", {})
		if settings is Dictionary:
			_settings_overrides[profile_key] = (settings as Dictionary).duplicate(true)

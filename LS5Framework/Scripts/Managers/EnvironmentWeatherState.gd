extends Node

var _states: Dictionary = {}


func has_state(state_namespace: StringName) -> bool:
	return _states.has(String(state_namespace))


func get_state(state_namespace: StringName) -> Dictionary:
	var key: String = String(state_namespace)
	if not _states.has(key):
		return {}
	var stored_state: Variant = _states[key]
	if stored_state is Dictionary:
		return stored_state.duplicate(true)
	return {}


func set_state(state_namespace: StringName, state: Dictionary) -> void:
	_states[String(state_namespace)] = state.duplicate(true)


func clear_state(state_namespace: StringName) -> void:
	_states.erase(String(state_namespace))


func clear_all_states() -> void:
	_states.clear()

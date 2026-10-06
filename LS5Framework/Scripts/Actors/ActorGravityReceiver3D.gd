extends Node
class_name ActorGravityReceiver3D

@export_group("Gravity")
## Enables gravity resolution and registration with external gravity fields.
@export var gravity_enabled: bool = true
## Default up direction used when no modifier or planetary field is active.
@export var base_gravity_up: Vector3 = Vector3.UP
## Transforms the configured base up direction by the owning actor's spawn basis.
@export var base_up_is_local: bool = false
## Acceleration applied at the resolved gravity multiplier of one.
@export var gravity_strength: float = 38.0

var _actor: Node3D = null
var _spawn_basis: Basis = Basis.IDENTITY
var _resolved_up: Vector3 = Vector3.UP
var _resolved_strength: float = 38.0
var _gravity_modifiers: Dictionary = {}
var _modifier_sequence: int = 0
var _planetary_sources: Dictionary = {}


func setup(actor: Node3D) -> void:
	_actor = actor
	_spawn_basis = actor.global_basis if actor else Basis.IDENTITY
	update_state(0.0)


func physics_tick(delta: float) -> void:
	if _gravity_modifiers.is_empty() and _planetary_sources.is_empty():
		_resolved_up = _get_base_up()
		_resolved_strength = max(gravity_strength, 0.0) if gravity_enabled else 0.0
		return
	update_state(delta)


func is_gravity_pull_enabled() -> bool:
	return gravity_enabled


func get_gravity_up() -> Vector3:
	var up: Vector3 = _resolved_up.normalized()
	if up.length() < 0.001:
		up = _get_base_up()
	return up


func get_gravity_down() -> Vector3:
	return -get_gravity_up()


func get_effective_gravity_strength() -> float:
	return max(_resolved_strength, 0.0)


func get_gravity_acceleration_vector() -> Vector3:
	return get_gravity_down() * get_effective_gravity_strength()


func get_vertical_component(vector: Vector3) -> float:
	return vector.dot(get_gravity_up())


func get_planar_component(vector: Vector3) -> Vector3:
	var up: Vector3 = get_gravity_up()
	return vector - up * vector.dot(up)


func compose_vector(planar: Vector3, vertical: float) -> Vector3:
	return get_planar_component(planar) + get_gravity_up() * vertical


func apply_gravity_modifier(
	source: Object,
	new_gravity_up: Vector3,
	gravity_multiplier: float,
	duration: float,
	priority: int,
	blend_with_planetary: bool,
	clear_on_death: bool,
	clear_on_respawn: bool,
	clear_on_level_restart: bool,
	clear_on_race_cleanup: bool
) -> void:
	if not gravity_enabled or source == null or new_gravity_up.length() < 0.001:
		return
	_modifier_sequence += 1
	var remaining: float = duration if duration > 0.0 else -1.0
	_gravity_modifiers[source.get_instance_id()] = {
		"up": new_gravity_up.normalized(),
		"multiplier": max(gravity_multiplier, 0.0),
		"remaining": remaining,
		"priority": priority,
		"sequence": _modifier_sequence,
		"blend_planetary": blend_with_planetary,
		"clear_on_death": clear_on_death,
		"clear_on_respawn": clear_on_respawn,
		"clear_on_level_restart": clear_on_level_restart,
		"clear_on_race_cleanup": clear_on_race_cleanup,
	}
	update_state(0.0)


func remove_gravity_modifier(source: Object) -> void:
	if source == null:
		return
	_gravity_modifiers.erase(source.get_instance_id())
	update_state(0.0)


func register_planetary_gravity_source(source: Node) -> void:
	if not gravity_enabled or source == null or not is_instance_valid(source):
		return
	if not source.has_method("get_planetary_gravity_vector"):
		return
	_planetary_sources[source.get_instance_id()] = weakref(source)
	update_state(0.0)


func unregister_planetary_gravity_source(source: Node) -> void:
	if source == null:
		return
	_planetary_sources.erase(source.get_instance_id())
	update_state(0.0)


func clear_gravity_state(reason: StringName = &"all", clear_planetary: bool = true) -> void:
	var modifier_ids: Array = _gravity_modifiers.keys()
	for modifier_id: Variant in modifier_ids:
		var modifier_value: Variant = _gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			_gravity_modifiers.erase(modifier_id)
			continue
		var modifier: Dictionary = modifier_value as Dictionary
		if _modifier_clears_for_reason(modifier, reason):
			_gravity_modifiers.erase(modifier_id)
	if clear_planetary:
		_planetary_sources.clear()
	update_state(0.0)


func update_state(delta: float) -> void:
	var base_up: Vector3 = _get_base_up()
	if not gravity_enabled:
		_resolved_up = base_up
		_resolved_strength = 0.0
		return

	var selected_modifier: Dictionary = {}
	var selected_priority: int = -2147483648
	var selected_sequence: int = -1
	var expired_ids: Array = []
	for modifier_id: Variant in _gravity_modifiers.keys():
		var modifier_value: Variant = _gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			expired_ids.append(modifier_id)
			continue
		var modifier: Dictionary = modifier_value as Dictionary
		var remaining: float = float(modifier.get("remaining", -1.0))
		if remaining > 0.0 and delta > 0.0:
			remaining = max(remaining - delta, 0.0)
			modifier["remaining"] = remaining
			_gravity_modifiers[modifier_id] = modifier
			if remaining <= 0.0:
				expired_ids.append(modifier_id)
				continue
		var modifier_priority: int = int(modifier.get("priority", 0))
		var modifier_sequence: int = int(modifier.get("sequence", 0))
		if modifier_priority > selected_priority or (
			modifier_priority == selected_priority and modifier_sequence > selected_sequence
		):
			selected_modifier = modifier
			selected_priority = modifier_priority
			selected_sequence = modifier_sequence
	for modifier_id: Variant in expired_ids:
		_gravity_modifiers.erase(modifier_id)

	var planetary_vector: Vector3 = Vector3.ZERO
	var invalid_source_ids: Array = []
	for source_id: Variant in _planetary_sources.keys():
		var source_ref_value: Variant = _planetary_sources.get(source_id)
		if not (source_ref_value is WeakRef):
			invalid_source_ids.append(source_id)
			continue
		var source_ref: WeakRef = source_ref_value as WeakRef
		var source: Object = source_ref.get_ref()
		if source == null or not is_instance_valid(source) or not source.has_method("get_planetary_gravity_vector"):
			invalid_source_ids.append(source_id)
			continue
		var contribution_value: Variant = source.call("get_planetary_gravity_vector", _actor)
		if contribution_value is Vector3:
			planetary_vector += contribution_value as Vector3
	for source_id: Variant in invalid_source_ids:
		_planetary_sources.erase(source_id)

	var gravity_down_vector: Vector3 = -base_up
	var preferred_zero_up: Vector3 = base_up
	if not selected_modifier.is_empty():
		var modifier_up_value: Variant = selected_modifier.get("up", base_up)
		var modifier_up: Vector3 = modifier_up_value as Vector3 if modifier_up_value is Vector3 else base_up
		modifier_up = modifier_up.normalized()
		if modifier_up.length() < 0.001:
			modifier_up = base_up
		preferred_zero_up = modifier_up
		var modifier_multiplier: float = max(float(selected_modifier.get("multiplier", 1.0)), 0.0)
		gravity_down_vector = -modifier_up * modifier_multiplier
		if bool(selected_modifier.get("blend_planetary", false)):
			gravity_down_vector += planetary_vector
	elif planetary_vector.length() > 0.000001:
		gravity_down_vector = planetary_vector

	if gravity_down_vector.length() > 0.000001:
		_resolved_up = -gravity_down_vector.normalized()
		_resolved_strength = max(gravity_strength, 0.0) * gravity_down_vector.length()
	else:
		_resolved_up = preferred_zero_up
		_resolved_strength = 0.0


func _get_base_up() -> Vector3:
	var up: Vector3 = base_gravity_up
	if base_up_is_local:
		up = _spawn_basis * up
	up = up.normalized()
	if up.length() < 0.001:
		up = Vector3.UP
	return up


func _modifier_clears_for_reason(modifier: Dictionary, reason: StringName) -> bool:
	match reason:
		&"death":
			return bool(modifier.get("clear_on_death", true))
		&"respawn":
			return bool(modifier.get("clear_on_respawn", true))
		&"level_restart":
			return bool(modifier.get("clear_on_level_restart", true))
		&"race_cleanup":
			return bool(modifier.get("clear_on_race_cleanup", true))
		_:
			return true

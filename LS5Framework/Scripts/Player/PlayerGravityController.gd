extends RefCounted
class_name PlayerGravityController

var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func set_base_up(new_up: Vector3) -> void:
	var p = _owner
	if p == null or new_up.length() <= 0.001:
		return
	p.gravity_up = new_up.normalized()
	update_state(0.0)
	if not p.attached:
		p.up_direction = p._resolved_gravity_up
		p._physics_up_last = p._resolved_gravity_up


func get_up() -> Vector3:
	var p = _owner
	var up: Vector3 = p._resolved_gravity_up.normalized()
	if up.length() < 0.001:
		up = get_base_up()
	return up


func get_down() -> Vector3:
	return -get_up()


func get_vertical_component(vector: Vector3) -> float:
	return vector.dot(get_up())


func get_planar_component(vector: Vector3) -> Vector3:
	var up: Vector3 = get_up()
	return vector - up * vector.dot(up)


func compose_vector(planar: Vector3, vertical: float) -> Vector3:
	return get_planar_component(planar) + get_up() * vertical


func rotate_between_frames(vector: Vector3, from_up: Vector3, to_up: Vector3) -> Vector3:
	var p = _owner
	var source_up: Vector3 = from_up.normalized()
	var target_up: Vector3 = to_up.normalized()
	if source_up.length() < 0.001 or target_up.length() < 0.001:
		return vector
	var alignment: float = clamp(source_up.dot(target_up), -1.0, 1.0)
	if alignment >= 0.999999999999:
		return vector
	var rotation_axis: Vector3 = source_up.cross(target_up)
	if rotation_axis.length() < 0.000001:
		rotation_axis = source_up.cross(p._model_forward)
	if rotation_axis.length() < 0.000001:
		rotation_axis = source_up.cross(Vector3.RIGHT)
	if rotation_axis.length() < 0.000001:
		rotation_axis = source_up.cross(Vector3.FORWARD)
	if rotation_axis.length() < 0.000001:
		return vector
	return vector.rotated(rotation_axis.normalized(), acos(alignment))


func get_base_up() -> Vector3:
	var p = _owner
	var up: Vector3 = p.gravity_up.normalized()
	if up.length() < 0.001:
		up = Vector3.UP
	return up


func get_base_strength() -> float:
	return max(float(_owner.gravity_strength), 0.0)


func get_effective_strength() -> float:
	return max(float(_owner._resolved_gravity_strength), 0.0)


func get_acceleration_vector() -> Vector3:
	return -get_up() * get_effective_strength()


func apply_modifier(
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
	var p = _owner
	if p == null or source == null or new_gravity_up.length() < 0.001:
		return
	p._gravity_modifier_sequence += 1
	var remaining: float = duration if duration > 0.0 else -1.0
	p._gravity_modifiers[source.get_instance_id()] = {
		"up": new_gravity_up.normalized(),
		"multiplier": max(gravity_multiplier, 0.0),
		"remaining": remaining,
		"priority": priority,
		"sequence": p._gravity_modifier_sequence,
		"blend_planetary": blend_with_planetary,
		"clear_on_death": clear_on_death,
		"clear_on_respawn": clear_on_respawn,
		"clear_on_level_restart": clear_on_level_restart,
		"clear_on_race_cleanup": clear_on_race_cleanup,
	}
	update_state(0.0)


func remove_modifier(source: Object) -> void:
	var p = _owner
	if p == null or source == null:
		return
	p._gravity_modifiers.erase(source.get_instance_id())
	update_state(0.0)


func register_planetary_source(source: Node) -> void:
	var p = _owner
	if p == null or source == null or not is_instance_valid(source):
		return
	if not source.has_method("get_planetary_gravity_vector"):
		return
	p._planetary_gravity_sources[source.get_instance_id()] = weakref(source)


func unregister_planetary_source(source: Node) -> void:
	var p = _owner
	if p == null or source == null:
		return
	p._planetary_gravity_sources.erase(source.get_instance_id())
	update_state(0.0)


func clear_state(reason: StringName, clear_planetary: bool) -> void:
	var p = _owner
	var modifier_ids: Array = p._gravity_modifiers.keys()
	for modifier_id in modifier_ids:
		var modifier_value: Variant = p._gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			p._gravity_modifiers.erase(modifier_id)
			continue
		var modifier: Dictionary = modifier_value
		if modifier_clears_for_reason(modifier, reason):
			p._gravity_modifiers.erase(modifier_id)
	if clear_planetary:
		p._planetary_gravity_sources.clear()
	update_state(0.0)


func modifier_clears_for_reason(modifier: Dictionary, reason: StringName) -> bool:
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


func update_state(delta: float) -> void:
	var p = _owner
	if p == null:
		return
	var expired_modifier_ids: Array = []
	var selected_modifier: Dictionary = {}
	var selected_priority: int = -2147483648
	var selected_sequence: int = -1
	for modifier_id in p._gravity_modifiers.keys():
		var modifier_value: Variant = p._gravity_modifiers.get(modifier_id)
		if not (modifier_value is Dictionary):
			expired_modifier_ids.append(modifier_id)
			continue
		var modifier: Dictionary = modifier_value
		var remaining: float = float(modifier.get("remaining", -1.0))
		if remaining > 0.0 and delta > 0.0:
			remaining = max(remaining - delta, 0.0)
			modifier["remaining"] = remaining
			p._gravity_modifiers[modifier_id] = modifier
			if remaining <= 0.0:
				expired_modifier_ids.append(modifier_id)
				continue
		var modifier_priority: int = int(modifier.get("priority", 0))
		var modifier_sequence: int = int(modifier.get("sequence", 0))
		if modifier_priority > selected_priority or (
			modifier_priority == selected_priority and modifier_sequence > selected_sequence
		):
			selected_modifier = modifier
			selected_priority = modifier_priority
			selected_sequence = modifier_sequence
	for modifier_id in expired_modifier_ids:
		p._gravity_modifiers.erase(modifier_id)

	var planetary_vector: Vector3 = Vector3.ZERO
	var invalid_planetary_ids: Array = []
	for source_id in p._planetary_gravity_sources.keys():
		var source_ref: Variant = p._planetary_gravity_sources.get(source_id)
		if not (source_ref is WeakRef):
			invalid_planetary_ids.append(source_id)
			continue
		var source: Object = source_ref.get_ref()
		if source == null or not is_instance_valid(source) or not source.has_method("get_planetary_gravity_vector"):
			invalid_planetary_ids.append(source_id)
			continue
		var contribution_value: Variant = source.call("get_planetary_gravity_vector", p)
		if contribution_value is Vector3:
			var contribution: Vector3 = contribution_value
			planetary_vector += contribution
	for source_id in invalid_planetary_ids:
		p._planetary_gravity_sources.erase(source_id)

	var base_up: Vector3 = get_base_up()
	var gravity_down_vector: Vector3 = -base_up
	var preferred_zero_up: Vector3 = base_up
	if not selected_modifier.is_empty():
		var modifier_up_value: Variant = selected_modifier.get("up", base_up)
		var modifier_up: Vector3 = base_up
		if modifier_up_value is Vector3:
			modifier_up = modifier_up_value
		modifier_up = modifier_up.normalized()
		if modifier_up.length() < 0.001:
			modifier_up = base_up
		preferred_zero_up = modifier_up
		var modifier_multiplier: float = max(
			float(selected_modifier.get("multiplier", 1.0)),
			0.0
		)
		gravity_down_vector = -modifier_up * modifier_multiplier
		if bool(selected_modifier.get("blend_planetary", false)):
			gravity_down_vector += planetary_vector
	elif planetary_vector.length() > 0.000001:
		gravity_down_vector = planetary_vector

	var base_strength: float = get_base_strength()
	if gravity_down_vector.length() > 0.000001:
		p._resolved_gravity_up = -gravity_down_vector.normalized()
		p._resolved_gravity_strength = base_strength * gravity_down_vector.length()
	else:
		p._resolved_gravity_up = preferred_zero_up
		p._resolved_gravity_strength = 0.0

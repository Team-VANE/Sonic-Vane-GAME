extends RefCounted
class_name CameraConstraintController

## Camera rig receiving the evaluated pose.
var rig: Node3D
## Constraint selected by priority and activation order.
var selected: CameraConstraint = null
var constraints: Array[CameraConstraint] = []
var _target: Node3D = null
var _transitions: Array[CameraTransitionTrait] = []
var _exit_traits: Array[CameraTransitionTrait] = []
var _elapsed: float = 0.0
var _from_transform: Transform3D = Transform3D.IDENTITY
var _from_pivot: Vector3 = Vector3.ZERO
var _from_fov: float = 70.0
var _orbit_basis: Basis = Basis.IDENTITY
var _filtered_position: Vector3 = Vector3.ZERO
var _filtered_basis: Basis = Basis.IDENTITY
var _filtered_fov: float = 70.0
var _first_frame: bool = true
var _position_channel: bool = false
var _orientation_channel: bool = false
var _lens_channel: bool = false
var _selected_id: int = 0
var _filtered_roll: float = 0.0
var _influencing: bool = false
var _manually_suppressed: bool = false
var _suppression_remaining: float = 0.0
var _mouse_offset: Vector2 = Vector2.ZERO
var _mouse_return_velocity: Vector2 = Vector2.ZERO
var _mouse_grace_remaining: float = 0.0
var _mouse_anchor_active: bool = false
var _mouse_intent_basis: Basis = Basis.IDENTITY
var _mouse_intent_valid: bool = false
var _mouse_free_basis: Basis = Basis.IDENTITY
var _mouse_base_influence: float = 1.0
var _mouse_anchor_basis: Basis = Basis.IDENTITY
var _offset_input_device: StringName = &"mouse"


func register(constraint: CameraConstraint) -> void:
	if not is_instance_valid(constraint) or not constraint.is_input_allowed() or constraints.has(constraint):
		return
	for entry: Variant in constraints.duplicate():
		if not is_instance_valid(entry):
			_prune_constraints()
		elif constraint.constraint_priority >= entry.constraint_priority and (entry.release_when_replaced or constraint.override_previous_constraints):
			unregister(entry as CameraConstraint, &"replaced")
	constraints.append(constraint)
	constraint.on_registered(rig)


func unregister(constraint: CameraConstraint, reason: StringName = &"released") -> void:
	if not constraints.has(constraint):
		return
	constraints.erase(constraint)
	if is_instance_valid(constraint):
		constraint.on_unregistered(reason)


func clear(except_constraint: CameraConstraint = null, suppress_transition: bool = true) -> void:
	for entry: Variant in constraints.duplicate():
		if not is_instance_valid(entry):
			_prune_constraints()
		elif entry != except_constraint:
			unregister(entry as CameraConstraint, &"cleared")
	if suppress_transition:
		selected = null
		_selected_id = 0
		_transitions.clear()
		_exit_traits.clear()
		_position_channel = false
		_orientation_channel = false
		_lens_channel = false
		_influencing = false
		_manually_suppressed = false
		_suppression_remaining = 0.0
		_reset_mouse_offset()


func advance(delta: float) -> void:
	var current_target: Node3D = rig.get("target") as Node3D
	if _target != current_target:
		if _target:
			clear()
		_target = current_target
	for entry: Variant in constraints.duplicate():
		if not is_instance_valid(entry):
			_prune_constraints()
		elif not is_instance_valid(current_target) or not entry.advance_lifetime(delta):
			unregister(entry as CameraConstraint)
	var next: CameraConstraint = null
	for entry: Variant in constraints:
		if is_instance_valid(entry) and entry.enabled and entry.is_input_allowed() and (not next or entry.constraint_priority >= next.constraint_priority):
			next = entry as CameraConstraint
	if not is_instance_valid(selected):
		selected = null
	var next_id: int = next.get_instance_id() if next else 0
	if next_id != _selected_id:
		_begin_transition(next)
	_elapsed += maxf(delta, 0.0)
	_advance_manual_suppression(delta)
	_advance_mouse_offset(delta)
	var influencing: bool = selected_has_effect()
	if not _influencing or not influencing:
		_first_frame = true
	if influencing != _influencing:
		rig.call("_sync_camera_orientation_hud", true)
	_influencing = influencing
	if influencing and selected.cancel_on_manual_look:
		var look: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_down", "camera_up")
		var mouse_delta: Vector2 = rig.get("_mouse_delta") as Vector2
		var mouse_strength: float = maxf(mouse_delta.length(), float(rig.get("_camera_mouse_strength")))
		var stick_threshold: float = float(rig.get("override_cancel_stick_threshold"))
		var mouse_threshold: float = float(rig.get("override_cancel_mouse_threshold"))
		if (stick_threshold > 0.0 and look.length() >= stick_threshold) or (mouse_threshold > 0.0 and mouse_strength >= mouse_threshold):
			unregister(selected, &"manual_look")
			advance(0.0)


func _prune_constraints() -> void:
	for index: int in range(constraints.size() - 1, -1, -1):
		if not is_instance_valid(constraints[index]):
			constraints.remove_at(index)


func is_manually_suppressed() -> bool:
	return _manually_suppressed and is_instance_valid(selected)


func _reset_mouse_offset() -> void:
	_mouse_offset = Vector2.ZERO
	_mouse_return_velocity = Vector2.ZERO
	_mouse_grace_remaining = 0.0
	_mouse_anchor_active = false
	_mouse_intent_valid = false


func uses_mouse_offset() -> bool:
	return _can_offset() and selected.mouse_offset_enabled


func uses_controller_offset() -> bool:
	return _can_offset() and selected.controller_offset_enabled


func _can_offset() -> bool:
	if not is_instance_valid(selected) or not selected.suppress_on_manual_look or selected.cancel_on_manual_look or _manually_suppressed:
		return false
	var target: Node3D = rig.get("target") as Node3D
	return is_instance_valid(target) and _weights_have_effect(selected.get_influence_weights(target.global_position))


func get_mouse_influence() -> float:
	if not (uses_mouse_offset() or uses_controller_offset()):
		return 0.0 if _manually_suppressed else 1.0
	var outer: float = maxf(deg_to_rad(selected.mouse_offset_break_deg), 0.001)
	var inner: float = clampf(deg_to_rad(selected.mouse_offset_falloff_start_deg), 0.0, outer - 0.0001)
	var weight: float = clampf((_mouse_offset.length() - inner) / (outer - inner), 0.0, 1.0)
	return 1.0 - weight * weight * (3.0 - 2.0 * weight)


func _offset_basis(basis: Basis) -> Basis:
	var result: Basis = basis.rotated(basis.y, _mouse_offset.x)
	return result.rotated(result.x, -_mouse_offset.y).orthonormalized()


func handle_mouse_motion(relative: Vector2) -> bool:
	if not uses_mouse_offset():
		return false
	var sensitivity: float = maxf(SettingsManager.mouse_look_sensitivity, 0.01)
	var vertical_sign: float = -1.0 if SettingsManager.mouse_invert_y else 1.0
	return _handle_offset_motion(Vector2(-relative.x * float(rig.get("yaw_sensitivity")), relative.y * float(rig.get("pitch_sensitivity")) * vertical_sign) * sensitivity, &"mouse")


func handle_controller_look(look: Vector2, delta: float) -> bool:
	if not uses_controller_offset() or look.length_squared() <= 0.000001 or delta <= 0.0:
		return false
	var vertical_sign: float = 1.0 if SettingsManager.right_stick_invert_y or bool(rig.get("invert_y_input")) else -1.0
	var rate: float = 40.0 * SettingsManager.get_right_stick_sensitivity() * delta
	return _handle_offset_motion(Vector2(-look.x * float(rig.get("yaw_sensitivity")), look.y * float(rig.get("pitch_sensitivity")) * vertical_sign) * rate, &"controller")


func _handle_offset_motion(angular: Vector2, device: StringName) -> bool:
	if angular.length_squared() < 0.000000000001 or bool(rig.get("manual_input_locked")) or bool(rig.call("_is_camera_input_blocked_by_ui")):
		return false
	if not _mouse_anchor_active:
		var camera: Camera3D = rig.get("camera") as Camera3D
		var anchor: Basis = _mouse_intent_basis if _mouse_intent_valid else camera.global_basis.orthonormalized()
		_mouse_anchor_basis = anchor
		_mouse_anchor_active = true
	_offset_input_device = device
	_mouse_offset += angular
	_mouse_return_velocity = Vector2.ZERO
	_mouse_grace_remaining = maxf(selected.mouse_offset_grace_duration, 0.0)
	_sync_mouse_free_heading()
	var threshold: float = maxf(deg_to_rad(selected.mouse_offset_break_deg), 0.001)
	if _mouse_offset.length() >= threshold:
		var camera: Camera3D = rig.get("camera") as Camera3D
		camera.global_basis = _mouse_free_basis
		_suppress_manual(true)
		return true
	return true


func _sync_mouse_free_heading() -> void:
	var desired: Basis = _offset_basis(_mouse_anchor_basis)
	rig.call("_sync_camera_angles_from_forward", -desired.z, rig.call("_get_camera_up"))
	_mouse_free_basis = rig.call("_get_free_input_basis") as Basis


func refresh_mouse_orientation() -> void:
	if not (uses_mouse_offset() or uses_controller_offset()) or not _mouse_anchor_active or not _mouse_intent_valid:
		return
	var camera: Camera3D = rig.get("camera") as Camera3D
	var desired: Basis = _mouse_free_basis.slerp(_offset_basis(_mouse_intent_basis), _mouse_base_influence * get_mouse_influence()).orthonormalized()
	if _orientation_channel:
		desired = _from_transform.basis.slerp(desired, _channel_weight(1)).orthonormalized()
	camera.global_basis = desired
	rig.call("_set_control_angles_from_forward", -desired.z, rig.call("_get_camera_up"))


func _advance_mouse_offset(delta: float) -> void:
	if _manually_suppressed or not _mouse_anchor_active or not is_instance_valid(selected):
		return
	if bool(rig.get("manual_input_locked")) or bool(rig.call("_is_camera_input_blocked_by_ui")):
		return
	if not selected.suppress_on_manual_look or (not selected.mouse_offset_enabled if _offset_input_device == &"mouse" else not selected.controller_offset_enabled):
		_reset_mouse_offset()
		return
	var pending: Vector2 = rig.get("_mouse_delta") as Vector2
	var controller_look: Vector2 = rig.call("_get_gamepad_look_input") as Vector2
	if pending.length_squared() > 0.000001 or float(rig.get("_camera_mouse_strength")) > 0.001 or (uses_controller_offset() and controller_look.length_squared() > 0.000001):
		_mouse_grace_remaining = maxf(selected.mouse_offset_grace_duration, 0.0)
		return
	var step: float = maxf(delta, 0.0)
	var grace: float = _mouse_grace_remaining
	_mouse_grace_remaining = maxf(grace - step, 0.0)
	step = maxf(step - grace, 0.0)
	if step <= 0.0:
		return
	var omega: float = 2.0 / maxf(selected.mouse_offset_return_time, 0.05)
	var change: Vector2 = (_mouse_return_velocity + _mouse_offset * omega) * step
	var decay: float = exp(-omega * step)
	_mouse_return_velocity = (_mouse_return_velocity - change * omega) * decay
	_mouse_offset = (_mouse_offset + change) * decay
	_sync_mouse_free_heading()
	if _mouse_offset.length_squared() < 0.00000001 and _mouse_return_velocity.length_squared() < 0.00000001:
		_mouse_offset = Vector2.ZERO
		_mouse_return_velocity = Vector2.ZERO
		_mouse_anchor_active = false


func get_mouse_debug_state() -> Dictionary:
	var enabled: bool = is_instance_valid(selected) and selected.suppress_on_manual_look and (selected.mouse_offset_enabled or selected.controller_offset_enabled) and not selected.cancel_on_manual_look
	return {
		"visible": enabled,
		"name": String(selected.name) if is_instance_valid(selected) else "",
		"offset": _mouse_offset,
		"input_device": _offset_input_device,
		"falloff_start": deg_to_rad(selected.mouse_offset_falloff_start_deg) if enabled else 0.0,
		"threshold": deg_to_rad(selected.mouse_offset_break_deg) if enabled else 1.0,
		"influence": get_mouse_influence(),
		"grace": _mouse_grace_remaining,
		"suppressed": _manually_suppressed,
		"suppression_remaining": _suppression_remaining,
		"returning": not _manually_suppressed and is_transitioning(),
	}


func handle_manual_look(look_strength: float, mouse_strength: float) -> void:
	if not is_instance_valid(selected) or bool(rig.get("manual_input_locked")) or bool(rig.call("_is_camera_input_blocked_by_ui")):
		return
	if selected.cancel_on_manual_look:
		var stick_threshold: float = float(rig.get("override_cancel_stick_threshold"))
		var mouse_threshold: float = float(rig.get("override_cancel_mouse_threshold"))
		if (stick_threshold > 0.0 and look_strength >= stick_threshold) or (mouse_threshold > 0.0 and mouse_strength >= mouse_threshold):
			unregister(selected, &"manual_look")
			advance(0.0)
		return
	if not selected.suppress_on_manual_look or (look_strength <= 0.001 and mouse_strength <= 0.001):
		return
	_suppress_manual()


func _suppress_manual(force_release: bool = false) -> void:
	if not _manually_suppressed:
		if not force_release and not selected_has_effect():
			return
		rig.call("_restore_rear_view_transform")
		var camera: Camera3D = rig.get("camera") as Camera3D
		_from_transform = camera.global_transform
		_from_transform.basis = _from_transform.basis.orthonormalized()
		_from_pivot = rig.global_position
		_from_fov = camera.fov
		rig.call("_sync_camera_angles_from_forward", -_from_transform.basis.z, rig.call("_get_camera_up"))
		rig.set("_control_yaw", rig.get("_yaw"))
		rig.set("_control_pitch", rig.get("_pitch"))
		rig.call("_reset_auto_follow_state")
		_manually_suppressed = true
		_position_channel = true
		_orientation_channel = false
		_lens_channel = true
		_set_suppression_transition(false)
		rig.call("_sync_camera_orientation_hud", true)
	_suppression_remaining = maxf(selected.manual_suppression_duration, 0.0)


func _set_suppression_transition(include_orientation: bool) -> void:
	var transition: CameraTransitionTrait = CameraTransitionTrait.new()
	transition.mode = CameraTransitionTrait.Mode.TIMED
	transition.duration = maxf(selected.manual_suppression_blend_duration, 0.01)
	transition.orientation = include_orientation
	_transitions.assign([transition])
	_elapsed = 0.0
	_first_frame = true


func _has_resume_input() -> bool:
	var keyboard: Vector2 = Vector2(
		SettingsManager.get_signed_action_axis(&"move_left", &"move_right", 0.0, &"keyboard"),
		SettingsManager.get_signed_action_axis(&"move_back", &"move_forward", 0.0, &"keyboard")
	)
	var gamepad: Vector2 = SettingsManager.get_radial_action_vector(&"move_left", &"move_right", &"move_back", &"move_forward", SettingsManager.get_left_stick_deadzone(), SettingsManager.get_left_stick_max(), &"gamepad")
	if keyboard.length_squared() > 0.000001 or gamepad.length_squared() > 0.000001:
		return true
	if SettingsManager.is_gameplay_action_pressed(&"interact"):
		return true
	for slot: int in range(1, 17):
		var action: StringName = StringName("ability_slot_%02d" % slot)
		if InputMap.has_action(action) and SettingsManager.is_gameplay_action_pressed(action):
			return true
	return false


func _advance_manual_suppression(delta: float) -> void:
	if not is_instance_valid(selected) or bool(rig.get("manual_input_locked")) or bool(rig.call("_is_camera_input_blocked_by_ui")):
		return
	var look_strength: float = float(rig.call("_get_immediate_manual_look_strength"))
	var mouse_delta: Vector2 = rig.get("_mouse_delta") as Vector2
	var mouse_strength: float = maxf(mouse_delta.length(), float(rig.get("_camera_mouse_strength")))
	if uses_mouse_offset():
		mouse_strength = 0.0
	if look_strength > 0.001 or mouse_strength > 0.001:
		handle_manual_look(look_strength, mouse_strength)
		return
	if not _manually_suppressed:
		return
	_suppression_remaining = maxf(_suppression_remaining - maxf(delta, 0.0), 0.0)
	if not selected.suppress_on_manual_look or (_suppression_remaining <= 0.000001 and _has_resume_input()):
		_begin_transition(selected)
		_set_suppression_transition(true)


func _begin_transition(next: CameraConstraint) -> void:
	var camera: Camera3D = rig.get("camera") as Camera3D
	if not camera:
		selected = next
		return
	_from_transform = camera.global_transform
	_from_transform.basis = _from_transform.basis.orthonormalized()
	_from_pivot = rig.global_position
	_from_fov = camera.fov
	_filtered_position = camera.global_position
	_filtered_basis = _from_transform.basis
	_filtered_roll = 0.0
	_filtered_fov = camera.fov
	_orbit_basis = _from_transform.basis
	var previous_position: bool = _position_channel
	var previous_orientation: bool = _orientation_channel
	var previous_lens: bool = _lens_channel
	if selected and not _manually_suppressed and (selected.retain_heading_on_release or (not selected.has_influence_trait() and not selected.position_traits.is_empty())):
		rig.call("_sync_camera_angles_from_forward", -_from_transform.basis.z, rig.call("_get_camera_up"))
		rig.set("_control_yaw", rig.get("_yaw"))
		rig.set("_control_pitch", rig.get("_pitch"))
		rig.call("_reset_auto_follow_state")
	if _manually_suppressed:
		_exit_traits.clear()
	_manually_suppressed = false
	_suppression_remaining = 0.0
	_reset_mouse_offset()
	selected = next
	_selected_id = next.get_instance_id() if next else 0
	_transitions.clear()
	_position_channel = false
	_orientation_channel = false
	_lens_channel = false
	if selected:
		_position_channel = not selected.position_traits.is_empty()
		_orientation_channel = not selected.orientation_traits.is_empty()
		for component: CameraOrientationTrait in selected.orientation_traits:
			if component and component.orbit_rig:
				_position_channel = true
		for component: CameraLensTrait in selected.lens_traits:
			if component:
				if component.mode == CameraLensTrait.Mode.ORBIT_DISTANCE:
					_position_channel = true
				else:
					_lens_channel = true
		_exit_traits.clear()
		for component: CameraTransitionTrait in selected.transition_traits:
			if component:
				if component.phase == CameraTransitionTrait.Phase.ENTRY:
					_transitions.append(component)
				else:
					_exit_traits.append(component)
	else:
		_transitions.assign(_exit_traits)
		_exit_traits.clear()
	_position_channel = _position_channel or previous_position
	_orientation_channel = _orientation_channel or previous_orientation
	_lens_channel = _lens_channel or previous_lens
	_elapsed = 0.0
	_first_frame = true
	rig.call("_sync_camera_orientation_hud", true)


func is_transitioning() -> bool:
	for component: CameraTransitionTrait in _transitions:
		if component.get_weight(_elapsed) < 1.0:
			return true
	return false


func refresh_configuration(constraint: CameraConstraint) -> void:
	if constraint != selected:
		return
	if _manually_suppressed:
		return
	var transitioning: bool = is_transitioning()
	_exit_traits.clear()
	if transitioning:
		_transitions.clear()
	for component: CameraTransitionTrait in selected.transition_traits:
		if not component:
			continue
		if component.phase == CameraTransitionTrait.Phase.EXIT:
			_exit_traits.append(component)
		elif transitioning:
			_transitions.append(component)
	_position_channel = not selected.position_traits.is_empty()
	_orientation_channel = not selected.orientation_traits.is_empty()
	_lens_channel = false
	for component: CameraOrientationTrait in selected.orientation_traits:
		if component and component.orbit_rig:
			_position_channel = true
	for component: CameraLensTrait in selected.lens_traits:
		if component:
			if component.mode == CameraLensTrait.Mode.ORBIT_DISTANCE:
				_position_channel = true
			else:
				_lens_channel = true


func owns_orientation() -> bool:
	if _manually_suppressed:
		return false
	return (is_instance_valid(selected) and not selected.orientation_traits.is_empty() and get_influence_weights().y > 0.000001) or (is_transitioning() and _orientation_channel)


func suppresses_free_orientation() -> bool:
	if is_instance_valid(selected) and selected.has_influence_trait(1):
		return false
	return owns_orientation()


func get_influence_weights() -> Vector3:
	if not is_instance_valid(selected):
		return Vector3.ONE
	var target: Node3D = rig.get("target") as Node3D
	var weights: Vector3 = selected.get_influence_weights(target.global_position) if is_instance_valid(target) else Vector3.ZERO
	return weights * get_mouse_influence()


func selected_has_effect() -> bool:
	if not is_instance_valid(selected) or _manually_suppressed:
		return false
	if not selected.has_influence_trait():
		return true
	return _weights_have_effect(get_influence_weights())


func _weights_have_effect(weights: Vector3) -> bool:
	var channels: int = 0
	if not selected.position_traits.is_empty():
		channels |= 1
	if not selected.orientation_traits.is_empty():
		channels |= 2
	for component: CameraOrientationTrait in selected.orientation_traits:
		if component and component.orbit_rig:
			channels |= 1
	for component: CameraLensTrait in selected.lens_traits:
		if component:
			channels |= 1 if component.mode == CameraLensTrait.Mode.ORBIT_DISTANCE else 4
	if not channels:
		for channel: int in 3:
			if selected.has_influence_trait(channel):
				channels |= 1 << channel
	for channel: int in 3:
		if channels & (1 << channel) and weights[channel] > 0.000001:
			return true
	return false


func is_presenting() -> bool:
	return selected_has_effect() or is_transitioning()


func _channel_weight(channel: int) -> float:
	for component: CameraTransitionTrait in _transitions:
		if (channel == 0 and component.position) or (channel == 1 and component.orientation) or (channel == 2 and component.lens):
			return component.get_weight(_elapsed)
	return 1.0


func _look_basis(direction: Vector3, up: Vector3, fallback: Basis) -> Basis:
	if direction.length_squared() < 0.000001:
		return fallback
	var forward: Vector3 = direction.normalized()
	var axis: Vector3 = up.normalized()
	if axis.length_squared() < 0.000001:
		axis = Vector3.UP
	if absf(forward.dot(axis)) > 0.999:
		axis = fallback.x.cross(forward).normalized()
		if axis.length_squared() < 0.000001:
			axis = Vector3.RIGHT if absf(forward.dot(Vector3.RIGHT)) < 0.999 else Vector3.FORWARD
	return Basis.looking_at(forward, axis).orthonormalized()


func _aim_basis(component: CameraOrientationTrait, origin: Vector3, fallback: Basis) -> Basis:
	if component.mode == CameraOrientationTrait.Mode.FIXED_ROTATION:
		return Basis.from_euler(component.rotation_degrees * (PI / 180.0))
	if component.mode == CameraOrientationTrait.Mode.MARKER_ROTATION:
		var basis: Basis = component.get_transform(selected).basis.orthonormalized()
		return Basis(-basis.x, basis.y, -basis.z) if component.marker_uses_guide_basis else basis
	var aim_node: Node3D = rig.get("target") as Node3D if component.mode == CameraOrientationTrait.Mode.FACE_PLAYER else component.get_source(selected)
	if not is_instance_valid(aim_node):
		return fallback
	var offset_up: Vector3 = rig.call("_get_target_player_up") as Vector3 if component.offset_uses_player_up else rig.call("_get_target_gravity_up") as Vector3
	var point: Vector3 = aim_node.global_position + Vector3(component.target_offset.x, 0.0, component.target_offset.z) + offset_up * component.target_offset.y
	return _look_basis(point - origin, component.get_up(selected, rig), fallback)


func _merge_position(current: Vector3, desired: Vector3, component: CameraPositionTrait) -> Vector3:
	if not component.limit_axes or component.axis_mask == 7:
		return desired
	if not component.axis_mask:
		return current
	var reference: Basis = component.get_axis_basis(selected)
	var difference: Vector3 = reference.inverse() * (desired - current)
	for axis: int in 3:
		if not component.axis_mask & (1 << axis):
			difference[axis] = 0.0
	return current + reference * difference


func _merge_orientation(current: Basis, desired: Basis, component: CameraOrientationTrait) -> Basis:
	if not component.limit_axes or component.axis_mask == 7:
		return desired
	if not component.axis_mask:
		return current
	var reference: Basis = component.get_axis_basis(selected)
	var angles: Vector3 = (reference.inverse() * current).get_euler()
	var desired_angles: Vector3 = (reference.inverse() * desired).get_euler()
	for axis: int in 3:
		if component.axis_mask & (1 << axis):
			angles[axis] = desired_angles[axis]
	return (reference * Basis.from_euler(angles)).orthonormalized()


func _position_anchor(component: CameraPositionTrait) -> Vector3:
	var xform: Transform3D = component.get_transform(selected)
	var anchor: Vector3 = xform.origin
	var target: Node3D = rig.get("target") as Node3D
	if component.mode in [CameraPositionTrait.Mode.PLAYER_CAMERA, CameraPositionTrait.Mode.PLAYER_PIVOT]:
		anchor = target.global_position
	elif component.mode == CameraPositionTrait.Mode.PATH_CAMERA:
		var path: Path3D = component.get_source(selected) as Path3D
		if path and path.curve and path.curve.point_count > 1:
			anchor = path.to_global(path.curve.get_closest_point(path.to_local(target.global_position)))
	return anchor + component.get_offset(rig, xform.basis)


func _tracked_aim(component: CameraOrientationTrait, origin: Vector3, current: Basis, delta: float) -> Basis:
	if component.limit_axes and not component.axis_mask:
		return current
	var desired: Basis = _merge_orientation(current, _aim_basis(component, origin, current), component)
	desired = current.slerp(desired, component.strength).orthonormalized()
	if not _first_frame and component.tracking_response > 0.0:
		desired = _filtered_basis.slerp(desired, 1.0 - exp(-component.tracking_response * maxf(delta, 0.0))).orthonormalized()
	return _merge_orientation(current, desired, component)


func apply(delta: float, free_transform: Transform3D, free_pivot: Vector3, free_distance: float, free_fov: float) -> void:
	var camera: Camera3D = rig.get("camera") as Camera3D
	var pivot: Vector3 = free_pivot
	var position: Vector3 = free_transform.origin
	var basis: Basis = free_transform.basis.orthonormalized()
	var fov: float = free_fov
	var orbit_distance: float = free_distance
	var orbit_distance_assigned: bool = false
	var aim: CameraOrientationTrait = null
	var has_orbit_aim: bool = false
	var fov_trait: CameraLensTrait = null
	var collision_enabled: bool = bool(rig.get("camera_collision_enabled"))
	var rear_view: bool = bool(rig.get("_rear_view_active"))
	var proximity_blend: bool = is_instance_valid(selected) and not _manually_suppressed and (selected.has_influence_trait() or _mouse_anchor_active)
	if selected and not _manually_suppressed:
		if _mouse_anchor_active:
			basis = _mouse_anchor_basis
		if selected_has_effect() and selected.collision_mode != CameraConstraint.CollisionMode.INHERIT:
			collision_enabled = selected.collision_mode == CameraConstraint.CollisionMode.ENABLED
		for component: CameraLensTrait in selected.lens_traits:
			if not component:
				continue
			if component.mode == CameraLensTrait.Mode.ORBIT_DISTANCE:
				if not orbit_distance_assigned:
					orbit_distance = maxf(component.distance, 0.0)
					orbit_distance_assigned = true
			elif not fov_trait:
				fov_trait = component
		var anchors: Array[Vector3] = []
		anchors.resize(selected.position_traits.size())
		for index: int in range(selected.position_traits.size() - 1, -1, -1):
			var component: CameraPositionTrait = selected.position_traits[index]
			if component:
				anchors[index] = _position_anchor(component)
				pivot = _merge_position(pivot, anchors[index], component)
		for component: CameraOrientationTrait in selected.orientation_traits:
			if not component or (component.limit_axes and not component.axis_mask):
				continue
			if component.mode not in [CameraOrientationTrait.Mode.ROLL, CameraOrientationTrait.Mode.MARKER_ROLL]:
				if not aim:
					aim = component
				has_orbit_aim = has_orbit_aim or component.orbit_rig
		var orbit_basis: Basis = _orbit_basis if aim and not aim.orbit_rig and not selected.position_traits.is_empty() else basis
		for index: int in range(selected.orientation_traits.size() - 1, -1, -1):
			var component: CameraOrientationTrait = selected.orientation_traits[index]
			if component and component.orbit_rig and component.mode not in [CameraOrientationTrait.Mode.ROLL, CameraOrientationTrait.Mode.MARKER_ROLL]:
				orbit_basis = _tracked_aim(component, pivot, orbit_basis, delta)
		position = free_pivot + orbit_basis.z * orbit_distance if has_orbit_aim else free_transform.origin
		if orbit_distance_assigned and not has_orbit_aim:
			position = free_pivot + free_transform.basis.orthonormalized().z * orbit_distance
		for index: int in range(selected.position_traits.size() - 1, -1, -1):
			var component: CameraPositionTrait = selected.position_traits[index]
			if not component:
				continue
			var desired: Vector3 = anchors[index]
			if component.mode in [CameraPositionTrait.Mode.FIXED_PIVOT, CameraPositionTrait.Mode.PLAYER_PIVOT, CameraPositionTrait.Mode.NODE_PIVOT]:
				desired += orbit_basis.z * orbit_distance
			if component.tracking_response > 0.0 and not _first_frame:
				desired = _filtered_position.lerp(desired, 1.0 - exp(-component.tracking_response * maxf(delta, 0.0)))
			position = _merge_position(position, desired, component)
		if not rear_view and not proximity_blend:
			position = rig.call("_resolve_camera_collision", position, collision_enabled, delta) as Vector3
		_filtered_position = position
		for index: int in range(selected.orientation_traits.size() - 1, -1, -1):
			var component: CameraOrientationTrait = selected.orientation_traits[index]
			if component and component.mode not in [CameraOrientationTrait.Mode.ROLL, CameraOrientationTrait.Mode.MARKER_ROLL]:
				basis = _tracked_aim(component, pivot if component.orbit_rig else position, basis, delta)
		_filtered_basis = basis
		var aim_basis: Basis = basis
		var highest_roll_angle: float = _filtered_roll
		for index: int in range(selected.orientation_traits.size() - 1, -1, -1):
			var roll: CameraOrientationTrait = selected.orientation_traits[index]
			if not roll or roll.mode not in [CameraOrientationTrait.Mode.ROLL, CameraOrientationTrait.Mode.MARKER_ROLL] or (roll.limit_axes and not roll.axis_mask):
				continue
			var roll_angle: float = deg_to_rad(roll.roll_degrees)
			if roll.mode == CameraOrientationTrait.Mode.MARKER_ROLL:
				var marker_basis: Basis = roll.get_transform(selected).basis.orthonormalized()
				if roll.marker_uses_guide_basis:
					marker_basis = Basis(-marker_basis.x, marker_basis.y, -marker_basis.z)
				roll_angle = float(rig.call("_compute_roll_from_basis", marker_basis, rig.call("_get_camera_up")))
			if not _first_frame and roll.tracking_response > 0.0:
				roll_angle = lerp_angle(_filtered_roll, roll_angle, 1.0 - exp(-roll.tracking_response * maxf(delta, 0.0)))
			highest_roll_angle = roll_angle
			basis = _merge_orientation(basis, aim_basis.rotated(-aim_basis.z, roll_angle), roll)
			for aim_index: int in range(index - 1, -1, -1):
				var preceding: CameraOrientationTrait = selected.orientation_traits[aim_index]
				if preceding and preceding.limit_axes and preceding.mode not in [CameraOrientationTrait.Mode.ROLL, CameraOrientationTrait.Mode.MARKER_ROLL]:
					basis = _merge_orientation(basis, aim_basis, preceding)
		_filtered_roll = highest_roll_angle
		if fov_trait:
			fov = fov_trait.fov
			var source: Node3D = fov_trait.get_source(selected)
			if fov_trait.mode == CameraLensTrait.Mode.SOURCE_FOV and source is Camera3D:
				fov = (source as Camera3D).fov
			elif fov_trait.mode == CameraLensTrait.Mode.DISTANCE_FOV:
				var reference: Vector3 = position
				if fov_trait.distance_source == CameraLensTrait.DistanceSource.MARKER_TO_PLAYER:
					reference = source.global_position if source else selected.get_locked_transform().origin
				var target_distance: float = reference.distance_to((rig.get("target") as Node3D).global_position)
				var weight: float = clampf((target_distance - fov_trait.near_distance) / maxf(fov_trait.far_distance - fov_trait.near_distance, 0.001), 0.0, 1.0)
				weight = weight * weight * (3.0 - 2.0 * weight)
				fov = lerpf(fov_trait.near_fov, fov_trait.far_fov, weight)
			if fov_trait.tracking_response > 0.0 and not _first_frame:
				fov = lerpf(_filtered_fov, fov, 1.0 - exp(-fov_trait.tracking_response * maxf(delta, 0.0)))
			_filtered_fov = fov
		_mouse_intent_basis = basis
		_mouse_intent_valid = true
		var target: Node3D = rig.get("target") as Node3D
		_mouse_base_influence = selected.get_influence_weights(target.global_position).y if is_instance_valid(target) else 0.0
		if (uses_mouse_offset() or uses_controller_offset()) and _mouse_anchor_active:
			basis = _offset_basis(basis)
		if proximity_blend:
			var influence: Vector3 = get_influence_weights()
			position = free_transform.origin.lerp(position, influence.x)
			pivot = free_pivot.lerp(pivot, influence.x)
			basis = free_transform.basis.orthonormalized().slerp(basis, influence.y).orthonormalized()
			fov = lerpf(free_fov, fov, influence.z)
	if _position_channel:
		var position_weight: float = _channel_weight(0)
		position = _from_transform.origin.lerp(position, position_weight)
		pivot = _from_pivot.lerp(pivot, position_weight)
	if _orientation_channel:
		basis = _from_transform.basis.slerp(basis, _channel_weight(1)).orthonormalized()
	if _lens_channel:
		fov = lerpf(_from_fov, fov, _channel_weight(2))
	if (proximity_blend or is_transitioning()) and not rear_view:
		position = rig.call("_resolve_camera_collision", position, collision_enabled, delta if proximity_blend else 0.0) as Vector3
	rig.global_position = pivot
	if has_orbit_aim:
		var yaw: Node3D = rig.get("yaw_node") as Node3D
		var pitch: Node3D = rig.get("pitch_node") as Node3D
		var local_basis: Basis = (rig.get("_camera_base_local_transform") as Transform3D).basis
		yaw.global_basis = (basis * local_basis.inverse()).orthonormalized()
		pitch.rotation = Vector3.ZERO
	camera.global_transform = Transform3D(basis, position)
	camera.fov = clampf(fov, 1.0, 179.0)
	if owns_orientation():
		rig.call("_set_control_angles_from_forward", -basis.z, rig.call("_get_camera_up"))
	_first_frame = false
	if not is_transitioning():
		_transitions.clear()
		_position_channel = selected and not _manually_suppressed and not selected.position_traits.is_empty()
		_orientation_channel = selected and not _manually_suppressed and not selected.orientation_traits.is_empty()
		_lens_channel = false
		if selected and not _manually_suppressed:
			for component: CameraOrientationTrait in selected.orientation_traits:
				if component and component.orbit_rig:
					_position_channel = true
			for component: CameraLensTrait in selected.lens_traits:
				if component:
					if component.mode == CameraLensTrait.Mode.ORBIT_DISTANCE:
						_position_channel = true
					else:
						_lens_channel = true

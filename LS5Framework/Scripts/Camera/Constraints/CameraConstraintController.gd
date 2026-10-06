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
	if selected and selected.cancel_on_manual_look:
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
	if selected and (selected.retain_heading_on_release or not selected.position_traits.is_empty()):
		rig.call("_sync_camera_angles_from_forward", -_from_transform.basis.z, rig.call("_get_camera_up"))
		rig.set("_control_yaw", rig.get("_yaw"))
		rig.set("_control_pitch", rig.get("_pitch"))
		rig.call("_reset_auto_follow_state")
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


func owns_orientation() -> bool:
	return (is_instance_valid(selected) and not selected.orientation_traits.is_empty()) or (is_transitioning() and _orientation_channel)


func is_presenting() -> bool:
	return is_instance_valid(selected) or is_transitioning()


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


func apply(delta: float, free_transform: Transform3D, free_pivot: Vector3, free_distance: float, free_fov: float) -> void:
	var camera: Camera3D = rig.get("camera") as Camera3D
	var pivot: Vector3 = free_pivot
	var position: Vector3 = free_transform.origin
	var basis: Basis = free_transform.basis.orthonormalized()
	var fov: float = free_fov
	var orbit_distance: float = free_distance
	var orbit_distance_assigned: bool = false
	var fixed_camera: bool = false
	var position_response: float = 0.0
	var aim: CameraOrientationTrait = null
	var roll: CameraOrientationTrait = null
	var fov_trait: CameraLensTrait = null
	var collision_enabled: bool = bool(rig.get("camera_collision_enabled"))
	var rear_view: bool = bool(rig.get("_rear_view_active"))
	if selected:
		if selected.collision_mode != CameraConstraint.CollisionMode.INHERIT:
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
		for component: CameraPositionTrait in selected.position_traits:
			if not component:
				continue
			var xform: Transform3D = component.get_transform(selected)
			var anchor: Vector3 = xform.origin
			if component.mode in [CameraPositionTrait.Mode.PLAYER_CAMERA, CameraPositionTrait.Mode.PLAYER_PIVOT]:
				anchor = (rig.get("target") as Node3D).global_position
			elif component.mode == CameraPositionTrait.Mode.PATH_CAMERA:
				var path: Path3D = component.get_source(selected) as Path3D
				if path and path.curve and path.curve.point_count > 1:
					anchor = path.to_global(path.curve.get_closest_point(path.to_local((rig.get("target") as Node3D).global_position)))
			anchor += component.get_offset(rig, xform.basis)
			fixed_camera = component.mode in [CameraPositionTrait.Mode.FIXED_CAMERA, CameraPositionTrait.Mode.PLAYER_CAMERA, CameraPositionTrait.Mode.NODE_CAMERA, CameraPositionTrait.Mode.PATH_CAMERA]
			if fixed_camera:
				position = anchor
				pivot = anchor
			else:
				pivot = anchor
			position_response = component.tracking_response
			break
		for component: CameraOrientationTrait in selected.orientation_traits:
			if not component:
				continue
			if component.mode in [CameraOrientationTrait.Mode.ROLL, CameraOrientationTrait.Mode.MARKER_ROLL]:
				if not roll:
					roll = component
			elif not aim:
				aim = component
		if not fixed_camera:
			var orbit_basis: Basis = _orbit_basis if aim and not aim.orbit_rig and not selected.position_traits.is_empty() else basis
			if aim and aim.orbit_rig:
				orbit_basis = orbit_basis.slerp(_aim_basis(aim, pivot, orbit_basis), aim.strength).orthonormalized()
				if not _first_frame and aim.tracking_response > 0.0:
					orbit_basis = _filtered_basis.slerp(orbit_basis, 1.0 - exp(-aim.tracking_response * maxf(delta, 0.0)))
			position = pivot + orbit_basis.z * orbit_distance
			basis = orbit_basis
		if position_response > 0.0 and not _first_frame:
			position = _filtered_position.lerp(position, 1.0 - exp(-position_response * maxf(delta, 0.0)))
		if not rear_view:
			position = rig.call("_resolve_camera_collision", position, collision_enabled, delta) as Vector3
		_filtered_position = position
		if aim:
			if not aim.orbit_rig:
				var desired_basis: Basis = _aim_basis(aim, position, basis)
				basis = basis.slerp(desired_basis, aim.strength).orthonormalized()
			if not aim.orbit_rig and not _first_frame and aim.tracking_response > 0.0:
				basis = _filtered_basis.slerp(basis, 1.0 - exp(-aim.tracking_response * maxf(delta, 0.0))).orthonormalized()
		_filtered_basis = basis
		if roll:
			var roll_angle: float = deg_to_rad(roll.roll_degrees)
			if roll.mode == CameraOrientationTrait.Mode.MARKER_ROLL:
				var marker_basis: Basis = roll.get_transform(selected).basis.orthonormalized()
				if roll.marker_uses_guide_basis:
					marker_basis = Basis(-marker_basis.x, marker_basis.y, -marker_basis.z)
				roll_angle = float(rig.call("_compute_roll_from_basis", marker_basis, rig.call("_get_camera_up")))
			if not _first_frame and roll.tracking_response > 0.0:
				roll_angle = lerp_angle(_filtered_roll, roll_angle, 1.0 - exp(-roll.tracking_response * maxf(delta, 0.0)))
			_filtered_roll = roll_angle
			basis = basis.rotated(-basis.z, roll_angle)
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
	if _position_channel:
		var position_weight: float = _channel_weight(0)
		position = _from_transform.origin.lerp(position, position_weight)
		pivot = _from_pivot.lerp(pivot, position_weight)
	if _orientation_channel:
		basis = _from_transform.basis.slerp(basis, _channel_weight(1)).orthonormalized()
	if _lens_channel:
		fov = lerpf(_from_fov, fov, _channel_weight(2))
	if is_transitioning() and not rear_view:
		position = rig.call("_resolve_camera_collision", position, collision_enabled, 0.0) as Vector3
	rig.global_position = pivot
	if aim and aim.orbit_rig:
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
		_position_channel = selected and not selected.position_traits.is_empty()
		_orientation_channel = selected and not selected.orientation_traits.is_empty()
		_lens_channel = false
		if selected:
			for component: CameraOrientationTrait in selected.orientation_traits:
				if component and component.orbit_rig:
					_position_channel = true
			for component: CameraLensTrait in selected.lens_traits:
				if component:
					if component.mode == CameraLensTrait.Mode.ORBIT_DISTANCE:
						_position_channel = true
					else:
						_lens_channel = true

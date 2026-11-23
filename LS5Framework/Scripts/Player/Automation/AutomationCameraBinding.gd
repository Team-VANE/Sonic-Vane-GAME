extends Node3D
class_name AutomationCameraBinding

var config: AutomationCameraTrait:
	set(value):
		if config == value:
			return
		if config and config.changed.is_connected(_invalidate):
			config.changed.disconnect(_invalidate)
		config = value
		if config:
			config.changed.connect(_invalidate)
		_dirty = true
var _dirty: bool = true
## Camera rig assigned to the active local body.
var _camera_rig: Node = null
## Dynamic camera constraint sharing the volume camera evaluator.
var _camera_constraint: CameraConstraint = null
var _camera_registered: bool = false
var _camera_transform: Transform3D = Transform3D.IDENTITY
var _camera_lead_distance_current: float = 0.0
var _camera_lead_direction: float = 0.0



func update(body: Node3D, value: AutomationSample, delta: float, path_frame: Transform3D = Transform3D.IDENTITY) -> void:
	var network: MultiplayerAPI = body.multiplayer
	if not config or not config.camera_enabled or (network and network.has_multiplayer_peer() and not body.is_multiplayer_authority()):
		release()
		return
	var rig: Node = null
	for candidate: Node in get_tree().get_nodes_in_group("CameraRig"):
		if candidate.get("target") == body:
			rig = candidate
			break
	if not is_instance_valid(_camera_rig) or _camera_rig != rig:
		release()
		_camera_rig = rig
	_update_camera_transform(body, value.position, value.tangent, value.normal, path_frame, body.get("velocity"), delta)
	if _dirty and is_instance_valid(_camera_constraint):
		_build_camera_constraint()
	if not _camera_registered and rig and rig.has_method("register_camera_constraint"):
		_build_camera_constraint()
		rig.call("register_camera_constraint", _camera_constraint)
		_camera_registered = true


func release() -> void:
	if _camera_registered and is_instance_valid(_camera_rig) and _camera_rig.has_method("unregister_camera_constraint"):
		_camera_rig.call("unregister_camera_constraint", _camera_constraint)
	_camera_registered = false
	_camera_rig = null
	_camera_lead_distance_current = 0.0
	_camera_lead_direction = 0.0


func _exit_tree() -> void:
	release()


func _get_body_gravity_up(body: Node3D) -> Vector3:
	if body.has_method("get_gravity_up"):
		var gravity_value: Variant = body.call("get_gravity_up")
		if gravity_value is Vector3 and (gravity_value as Vector3).length() > 0.001:
			return (gravity_value as Vector3).normalized()
	return Vector3.UP


func _get_body_player_up(body: Node3D) -> Vector3:
	if body.has_method("get_up_vector"):
		var player_up_value: Variant = body.call("get_up_vector")
		if player_up_value is Vector3 and (player_up_value as Vector3).length() > 0.001:
			return (player_up_value as Vector3).normalized()
	return _get_body_gravity_up(body)


func _invalidate() -> void:
	_dirty = true


func _build_camera_constraint() -> void:
	_dirty = false
	if not is_instance_valid(_camera_constraint):
		_camera_constraint = CameraConstraint.new()
		add_child(_camera_constraint)
	_camera_constraint.constraint_priority = config.constraint_priority
	_camera_constraint.override_previous_constraints = config.override_previous_camera_constraints
	_camera_constraint.disable_camera_controls = config.disable_camera_controls
	_camera_constraint.suppress_speed_effects = true
	_camera_constraint.up_mode = CameraConstraint.UpMode.PLAYER if config.target_use_player_up else CameraConstraint.UpMode.GRAVITY
	if not config.override_use_player_up:
		_camera_constraint.up_mode = CameraConstraint.UpMode.INHERIT
	_camera_constraint.collision_mode = CameraConstraint.CollisionMode.INHERIT
	if config.override_camera_collision:
		_camera_constraint.collision_mode = CameraConstraint.CollisionMode.ENABLED if config.camera_collision_enabled_override else CameraConstraint.CollisionMode.DISABLED
	var placement: CameraPositionTrait = CameraPositionTrait.new()
	placement.mode = CameraPositionTrait.Mode.FIXED_PIVOT
	placement.source_path = NodePath("")
	placement.tracking_response = config.position_smoothing
	_camera_constraint.position_traits.assign([placement])
	var aim: CameraOrientationTrait = CameraOrientationTrait.new()
	aim.mode = CameraOrientationTrait.Mode.FACE_PLAYER if config.face_player else CameraOrientationTrait.Mode.MARKER_ROTATION
	aim.target_path = NodePath("")
	aim.target_offset = config.aim_target_offset
	aim.offset_uses_player_up = config.aim_offset_uses_player_up
	aim.up_source = CameraOrientationTrait.UpSource.PLAYER if config.aim_up_uses_player_up else CameraOrientationTrait.UpSource.GRAVITY
	aim.tracking_response = config.aim_smooth if config.face_player else config.rotation_smoothing
	aim.strength = config.aim_strength
	aim.orbit_rig = not config.face_player
	_camera_constraint.orientation_traits.assign([aim])
	if config.allow_roll and absf(config.roll_deg) > 0.001:
		var roll: CameraOrientationTrait = CameraOrientationTrait.new()
		roll.mode = CameraOrientationTrait.Mode.ROLL
		roll.roll_degrees = config.roll_deg
		_camera_constraint.orientation_traits.append(roll)
	_camera_constraint.lens_traits.clear()
	if config.distance_override_enabled:
		var orbit: CameraLensTrait = CameraLensTrait.new()
		orbit.mode = CameraLensTrait.Mode.ORBIT_DISTANCE
		orbit.distance = config.distance_override
		_camera_constraint.lens_traits.append(orbit)
	if config.fov_override_enabled:
		var lens: CameraLensTrait = CameraLensTrait.new()
		lens.mode = CameraLensTrait.Mode.DISTANCE_FOV if config.fov_distance_based_enabled else CameraLensTrait.Mode.FIXED_FOV
		lens.fov = config.fov_override
		lens.near_fov = config.fov_distance_near_fov
		lens.far_fov = config.fov_distance_far_fov
		lens.near_distance = config.fov_distance_near
		lens.far_distance = config.fov_distance_far
		lens.tracking_response = config.fov_smoothing if config.fov_smoothing_independent or config.entry_smoothing_enabled else 0.0
		lens.distance_source = CameraLensTrait.DistanceSource.MARKER_TO_PLAYER
		lens.source_path = NodePath("")
		_camera_constraint.lens_traits.append(lens)
	var entry: CameraTransitionTrait = CameraTransitionTrait.new()
	entry.mode = CameraTransitionTrait.Mode.TIMED if config.entry_smoothing_enabled else CameraTransitionTrait.Mode.INSTANT
	entry.duration = config.entry_smoothing_duration
	var exit: CameraTransitionTrait = CameraTransitionTrait.new()
	exit.phase = CameraTransitionTrait.Phase.EXIT
	exit.mode = CameraTransitionTrait.Mode.TIMED if config.exit_smoothing_enabled else CameraTransitionTrait.Mode.INSTANT
	exit.duration = config.exit_smoothing_duration
	_camera_constraint.transition_traits.assign([entry, exit])
	_camera_constraint.set_locked_transform(_camera_transform)
	if _camera_registered:
		_camera_constraint.refresh_live_configuration(false)


func _get_camera_up(body: Node3D, path_frame: Transform3D, view_axis: Vector3) -> Vector3:
	var camera_up: Vector3 = _get_body_gravity_up(body)
	if config.allow_roll:
		match config.camera_up_mode:
			AutomationCameraTrait.CameraUpMode.GRAVITY:
				camera_up = _get_body_gravity_up(body)
			AutomationCameraTrait.CameraUpMode.PLAYER:
				camera_up = _get_body_player_up(body)
			AutomationCameraTrait.CameraUpMode.PATH_FRAME:
				camera_up = path_frame.basis.y
	camera_up -= view_axis * camera_up.dot(view_axis)
	if camera_up.length() < 0.001:
		camera_up = path_frame.basis.y
		camera_up -= view_axis * camera_up.dot(view_axis)
	if camera_up.length() < 0.001:
		camera_up = (Vector3.UP if absf(view_axis.y) < 0.9 else Vector3.RIGHT).slide(view_axis)
	return camera_up.normalized()


func _update_camera_lead(signed_path_speed: float, delta: float) -> float:
	var direction_threshold: float = max(config.camera_lead_direction_speed, 0.0)
	var has_travel_direction: bool = abs(signed_path_speed) > direction_threshold
	if has_travel_direction:
		_camera_lead_direction = sign(signed_path_speed)

	var recentering: bool = (
		not has_travel_direction
		and config.camera_idle_lead_mode == AutomationCameraTrait.CameraIdleLeadMode.RECENTER
	)
	var target_lead: float = 0.0
	if not recentering and abs(_camera_lead_direction) > 0.001:
		target_lead = config.camera_path_lead_distance * _camera_lead_direction
		if has_travel_direction:
			target_lead += signed_path_speed * config.camera_velocity_lead_time
	if config.camera_max_lead_distance > 0.0:
		target_lead = clamp(
			target_lead,
			-config.camera_max_lead_distance,
			config.camera_max_lead_distance
		)

	var response_speed: float = (
		config.camera_lead_recenter_smoothing if recentering else config.camera_lead_smoothing
	)
	var followed_lead: float = target_lead
	if response_speed > 0.0:
		var follow_weight: float = 1.0 - exp(-response_speed * max(delta, 0.0))
		followed_lead = lerp(_camera_lead_distance_current, target_lead, follow_weight)
	if config.camera_lead_max_adjustment_speed > 0.0:
		followed_lead = move_toward(
			_camera_lead_distance_current,
			followed_lead,
			config.camera_lead_max_adjustment_speed * max(delta, 0.0)
		)
	_camera_lead_distance_current = followed_lead
	return _camera_lead_distance_current


func _update_camera_transform(
	body: Node3D,
	path_point: Vector3,
	tangent: Vector3,
	plane_normal: Vector3,
	path_frame: Transform3D,
	body_velocity: Vector3,
	delta: float
) -> void:
	var side_sign: float = 1.0 if config.camera_side == AutomationCameraTrait.CameraSide.RIGHT_OF_PATH else -1.0
	var view_axis: Vector3 = -plane_normal * side_sign
	var camera_up: Vector3 = _get_camera_up(body, path_frame, view_axis)
	var screen_right: Vector3 = camera_up.cross(view_axis)
	if screen_right.length() < 0.001:
		screen_right = tangent
	screen_right = screen_right.normalized()
	var camera_basis: Basis = Basis(screen_right, camera_up, view_axis).orthonormalized()

	var signed_path_speed: float = body_velocity.dot(tangent)
	var lead_distance: float = _update_camera_lead(signed_path_speed, delta)

	var target_position: Vector3 = body.global_position
	if config.camera_center_on_plane:
		var depth_error: float = (body.global_position - path_point).dot(plane_normal)
		target_position -= plane_normal * depth_error
	target_position += camera_up * config.camera_vertical_offset
	target_position += tangent * lead_distance

	_camera_transform = Transform3D(camera_basis, target_position)
	if is_instance_valid(_camera_constraint):
		_camera_constraint.set_locked_transform(_camera_transform)


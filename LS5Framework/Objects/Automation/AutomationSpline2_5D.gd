extends "res://LS5Framework/Objects/Automation/AutomationSpline.gd"

enum PlaneFrameMode {
	PATH_FRAME,
	GRAVITY_RIBBON,
	PLAYER_RIBBON,
	FIXED_PATH_AXIS,
}

enum TransitionEase {
	LINEAR,
	SMOOTHSTEP,
	SMOOTHERSTEP,
}

enum PlaneInputMode {
	PATH_HORIZONTAL,
	PATH_VERTICAL,
	CAMERA_RELATIVE,
}

enum SurfaceTraversalMode {
	PROJECT_PATH_ON_SURFACE,
	RIBBON_SURFACE_TANGENT,
}

enum CameraSide {
	RIGHT_OF_PATH,
	LEFT_OF_PATH,
}

enum CameraUpMode {
	GRAVITY,
	PLAYER,
	PATH_FRAME,
}

enum CameraIdleLeadMode {
	RECENTER,
	HOLD_LAST_DIRECTION,
}

@export_category("2.5D Spline")

@export_group("Endpoint Activation")
## Lets either dedicated endpoint area activate or release the section for bidirectional traversal.
@export var bidirectional_endpoint_areas: bool = true

@export_group("Transitions")
## Path distance used to blend from free 3D movement into strict 2.5D movement at the start.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var entry_blend_distance: float = 12.0
## Path distance used to blend from strict 2.5D movement back to free 3D movement at the end.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var exit_blend_distance: float = 12.0
## Easing function applied to entry and exit adherence.
@export var transition_ease: TransitionEase = TransitionEase.SMOOTHERSTEP
## Applies the plane constraint while airborne so jumps remain inside the 2.5D ribbon.
@export var constrain_airborne: bool = true
## Applies the plane constraint during homing, jump dash, and other normal external movement states.
@export var constrain_special_moves: bool = true

@export_group("Path Sampling")
## Uses cubic interpolation when sampling path positions and authored frames.
@export var cubic_path_sampling: bool = true
## Expands the local tracking window by the player's distance traveled since the previous sample.
@export var speed_adaptive_tracking_window: bool = true
## Multiplier applied to frame travel when expanding the local tracking window.
@export_range(1.0, 10.0, 0.1, "or_greater") var tracking_window_travel_multiplier: float = 2.0
## Maximum speed-adaptive tracking window. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var max_adaptive_tracking_window: float = 100.0

@export_group("Plane Frame")
## Selects how the forbidden sideways axis is generated along the path.
@export var plane_frame_mode: PlaneFrameMode = PlaneFrameMode.PATH_FRAME
## Reverses the generated sideways axis without changing path direction.
@export var reverse_plane_normal: bool = false
## Uses the previous valid path frame when a vertical or degenerate segment cannot produce one.
@export var preserve_frame_through_degenerate_segments: bool = true

@export_group("Terrain Traversal Adjustment")
## Adapts movement orientation to attached terrain without changing spline progress.
@export var surface_frame_enabled: bool = true
## Selects whether terrain tangent follows a path projection or the surface direction inside the ribbon.
@export var surface_traversal_mode: SurfaceTraversalMode = SurfaceTraversalMode.RIBBON_SURFACE_TANGENT
## Keeps the authored sideways axis stable while terrain changes movement up and forward.
@export var surface_frame_preserve_ribbon_normal: bool = true
## Blend from the authored curve frame to the attached surface frame.
@export_range(0.0, 1.0, 0.01) var surface_frame_influence: float = 1.0
## Uses grounded travel direction to refine the surface tangent when moving fast enough.
@export var surface_frame_uses_velocity: bool = false
## Minimum grounded speed required before travel direction refines the surface frame.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var surface_frame_min_speed: float = 2.0
## Grounded tangent alignment strength used while terrain traversal adjustment is active.
@export_range(0.0, 200.0, 0.1, "or_greater") var terrain_tangent_alignment_strength: float = 6.0

@export_group("Adaptive Centerline")
## Captures the player's depth relative to the curve when the spline first activates.
@export var capture_entry_depth_offset: bool = true
## Fades captured entry depth to the authored centerline as endpoint adherence increases.
@export var captured_depth_transition_enabled: bool = true
## Lets unmarked attached terrain continuously move the centerline. Disable for strict authored depth.
@export var follow_unanchored_surface_depth: bool = false
## Lets the constrained plane follow bounded depth changes caused by attached surface geometry.
@export var adaptive_centerline_enabled: bool = true
## Limits adaptive centerline movement to grounded or otherwise attached motion.
@export var adaptive_centerline_grounded_only: bool = true
## Response speed used when the centerline follows detected surface depth. Zero follows immediately.
@export_range(0.0, 200.0, 0.1, "or_greater") var adaptive_centerline_strength: float = 20.0
## Maximum centerline movement speed. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var adaptive_centerline_max_speed: float = 12.0
## Maximum absolute depth offset the adaptive centerline may keep from the authored curve. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var adaptive_centerline_max_offset: float = 4.0
## Minimum depth difference required before the centerline follows the surface.
@export_range(0.0, 1.0, 0.001, "or_greater", "suffix:m") var adaptive_centerline_deadzone: float = 0.02

@export_group("Terrain Piece Anchors")
## Uses metadata-marked attached collision pieces as stable centerline depth targets.
@export var terrain_piece_anchors_enabled: bool = false
## Metadata key placed on a collision node or one of its parents. True uses node origin; Vector3 uses a local anchor; a number supplies a direct plane offset.
@export var terrain_piece_anchor_metadata: StringName = &"automation_25d_centerline_anchor"
## Maximum number of collider parents searched for terrain-piece anchor metadata.
@export_range(0, 32, 1) var terrain_piece_anchor_parent_search: int = 8

@export_group("Depth Offset Splines")
## Allows active 2.5D depth-profile splines to supply deterministic centerline offsets.
@export var depth_offset_splines_enabled: bool = true

@export_group("Overlapping Path Tracking")
## Extra spatial distance allowed before tracking switches from the current arc-length neighborhood to another branch.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var branch_switch_distance_tolerance: float = 2.0
## Distance from the current arc-length neighborhood that permits global closest-point recovery. Zero disables forced recovery.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var tracking_recovery_distance: float = 20.0

@export_group("Position Constraint")
## Snaps final sideways position error to zero at full adherence.
@export var strict_position_lock: bool = true
## Reapplies strict position and velocity locks after collision movement at full adherence.
@export var post_slide_constraint_pass_enabled: bool = true
## Response speed used to pull position toward the ribbon during transitions. Zero follows transition weight directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var position_lock_strength: float = 12.0
## Maximum sideways correction speed during transitions. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var max_position_correction_speed: float = 80.0
## Sideways error below this distance is ignored outside the strict core.
@export_range(0.0, 1.0, 0.001, "or_greater", "suffix:m") var position_lock_deadzone: float = 0.005

@export_group("Velocity Constraint")
## Removes all sideways velocity at full adherence.
@export var strict_velocity_lock: bool = true
## Prevents passive steering-angle speed loss while the 2.5D spline is active.
@export var disable_turning_slowdown: bool = true
## Response speed used to remove sideways velocity during transitions. Zero follows transition weight directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var velocity_lock_strength: float = 18.0
## Restores a fraction of speed lost when sideways velocity is removed. Zero avoids converting turn arcs into forward speed.
@export_range(0.0, 1.0, 0.01) var sideways_removal_speed_preservation: float = 0.0
## Lets the inherited guided turn-rate limit apply while constrained.
@export var use_guided_turn_rate_limit: bool = false

@export_group("Path Input")
## Chooses how stick input maps to signed forward and backward path movement.
@export var plane_input_mode: PlaneInputMode = PlaneInputMode.PATH_HORIZONTAL
## Reverses signed path input without changing the curve or camera side.
@export var reverse_plane_input: bool = false
## Signed path input below this amount is ignored.
@export_range(0.0, 1.0, 0.01) var plane_input_deadzone: float = 0.05
## Allows drift to activate while the player is constrained to the ribbon.
@export var allow_drift: bool = false
## Makes along-path assistance follow signed input in either direction.
@export var bidirectional_along_assist: bool = true
## Uses the along-assist target speed as a soft player speed cap.
@export var along_assist_limits_player_speed: bool = false

@export_group("Spline Camera")
## Registers this spline as a dynamic camera constraint for the local player.
@export var camera_enabled: bool = true
## Higher values win when this camera overlaps other camera constraints.
@export var constraint_priority: int = 10
## Clears previously registered camera constraints when this spline camera activates.
@export var override_previous_camera_constraints: bool = false
## Chooses which side of the movement ribbon the camera occupies.
@export var camera_side: CameraSide = CameraSide.RIGHT_OF_PATH
## Chooses the camera's vertical frame independently from the movement ribbon.
@export var camera_up_mode: CameraUpMode = CameraUpMode.GRAVITY
## Prevents manual orbit and zoom while the spline camera is influencing.
@export var disable_camera_controls: bool = true
## Aims the final camera directly at the player instead of using the generated path frame.
@export var face_player: bool = false
## Fraction of the final face-player rotation applied by the camera rig.
@export_range(0.0, 1.0, 0.01) var aim_strength: float = 1.0
## Response speed for face-player aiming.
@export_range(0.0, 200.0, 0.1, "or_greater") var aim_smooth: float = 14.0
## World-space aim offset from the player's origin.
@export var aim_target_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
## Applies the vertical aim offset along player up instead of gravity up.
@export var aim_offset_uses_player_up: bool = false
## Uses player up as the face-player look-at up axis.
@export var aim_up_uses_player_up: bool = false
## Allows the camera frame to roll with its selected up axis.
@export var allow_roll: bool = false
## Additional roll around the camera viewing axis.
@export_range(-180.0, 180.0, 0.1, "suffix:deg") var roll_deg: float = 0.0
## Overrides the camera rig's player-up setting while this spline is active.
@export var override_use_player_up: bool = true
## Player-up setting used by the camera rig during the override.
@export var target_use_player_up: bool = false

@export_group("Camera Framing")
## Overrides the normal player-controlled camera distance.
@export var distance_override_enabled: bool = true
## Distance from the movement ribbon while the override is active.
@export_range(0.01, 10000.0, 0.1, "or_greater", "suffix:m") var distance_override: float = 18.0
## Vertical tracking offset along the selected camera up axis.
@export_range(-1000.0, 1000.0, 0.1, "suffix:m") var camera_vertical_offset: float = 2.0
## Fixed tracking lead along the path in the current travel direction.
@export_range(-1000.0, 1000.0, 0.1, "suffix:m") var camera_path_lead_distance: float = 2.0
## Additional tracking lead calculated from signed path speed.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var camera_velocity_lead_time: float = 0.15
## Maximum absolute fixed and velocity lead. Zero removes the limit.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var camera_max_lead_distance: float = 12.0
## Minimum absolute path speed required before travel selects a lead direction.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var camera_lead_direction_speed: float = 1.0
## Chooses whether fixed lead recenters or retains its last direction below the direction speed.
@export var camera_idle_lead_mode: CameraIdleLeadMode = CameraIdleLeadMode.RECENTER
## Response speed used when lead approaches a moving target. Zero applies immediately.
@export_range(0.0, 200.0, 0.1, "or_greater") var camera_lead_smoothing: float = 4.0
## Response speed used when lead recenters at low speed. Zero applies immediately.
@export_range(0.0, 200.0, 0.1, "or_greater") var camera_lead_recenter_smoothing: float = 3.0
## Maximum camera-lead adjustment speed. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var camera_lead_max_adjustment_speed: float = 16.0
## Removes the player's remaining depth error from the camera tracking point.
@export var camera_center_on_plane: bool = true

@export_group("Camera Lens")
## Overrides field of view while the spline camera is active.
@export var fov_override_enabled: bool = false
## Field of view used by the spline camera.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var fov_override: float = 55.0
## Adjusts field of view by player distance from the tracking point.
@export var fov_distance_based_enabled: bool = false
## Field of view at or inside the near distance.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var fov_distance_near_fov: float = 55.0
## Field of view at or beyond the far distance.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var fov_distance_far_fov: float = 45.0
## Distance where the near field of view is fully applied.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var fov_distance_near: float = 0.0
## Distance where the far field of view is fully applied.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var fov_distance_far: float = 30.0

@export_group("Camera Transitions")
## Adds a timed entry transition when the spline first becomes active.
@export var entry_smoothing_enabled: bool = false
## Duration of the camera entry transition.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var entry_smoothing_duration: float = 0.25
## Adds a timed transition when the spline camera releases.
@export var exit_smoothing_enabled: bool = true
## Duration of camera release smoothing.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var exit_smoothing_duration: float = 0.35
## Response speed for camera tracking-point movement. Zero follows directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var position_smoothing: float = 14.0
## Response speed for generated path-frame rotation. Zero follows directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var rotation_smoothing: float = 10.0
## Response speed for field-of-view changes. Zero applies directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var fov_smoothing: float = 8.0
## Applies FOV smoothing even when timed entry smoothing is disabled.
@export var fov_smoothing_independent: bool = true
## Overrides camera collision while this spline camera is active.
@export var override_camera_collision: bool = false
## Camera collision state used while the override is active.
@export var camera_collision_enabled_override: bool = true

## Camera rig assigned to the active local body.
var _camera_rig: Node = null
## Body supplying the active spline camera pose.
var _camera_body: Node3D = null
## Dynamic camera constraint sharing the volume camera evaluator.
var _camera_constraint: CameraConstraint = null
var _camera_registered: bool = false
var _camera_transform: Transform3D = Transform3D.IDENTITY
var _camera_lead_distance_current: float = 0.0
var _camera_lead_direction: float = 0.0


func _validate_property(property: Dictionary) -> void:
	var property_name: StringName = StringName(property.get("name", ""))
	var hidden_properties: Array[StringName] = [
		&"grounded_only",
		&"align_player_rotation",
		&"continuous_force",
		&"nudge_toward_strength_base",
		&"nudge_toward_strength_per_speed",
		&"nudge_radius",
		&"tangent_snap_strength",
	]
	if property_name in hidden_properties:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR


func _ready() -> void:
	super._ready()
	_configure_bidirectional_endpoint_areas()


func _configure_bidirectional_endpoint_areas() -> void:
	if not bidirectional_endpoint_areas or not use_entrance_exit_areas:
		return
	if not _activation_configured or _enter_area == null or _exit_area == null:
		return
	var entry_handler: Callable = _on_body_entered
	var exit_handler: Callable = _on_exit_area_entered
	var endpoint_handler: Callable = _on_endpoint_area_entered
	if _enter_area.body_entered.is_connected(entry_handler):
		_enter_area.body_entered.disconnect(entry_handler)
	if _exit_area.body_entered.is_connected(exit_handler):
		_exit_area.body_entered.disconnect(exit_handler)
	if not _enter_area.body_entered.is_connected(endpoint_handler):
		_enter_area.body_entered.connect(endpoint_handler)
	if not _exit_area.body_entered.is_connected(endpoint_handler):
		_exit_area.body_entered.connect(endpoint_handler)


func _on_endpoint_area_entered(body: Node3D) -> void:
	if _bodies.has(body):
		_deactivate_body(body)
		return
	_on_body_entered(body)


func _exit_tree() -> void:
	_unregister_camera()


func _on_body_entered(body: Node3D) -> void:
	super._on_body_entered(body)
	if _bodies.has(body):
		_try_register_camera(body)


func _deactivate_body(body: Node3D) -> void:
	var was_camera_body: bool = body == _camera_body
	super._deactivate_body(body)
	_release_depth_profiles_for_body(body)
	if was_camera_body:
		_unregister_camera()
		_register_first_available_camera_body()


func _clear_bodies() -> void:
	for body: Node3D in _bodies:
		_release_depth_profiles_for_body(body)
	super._clear_bodies()
	_unregister_camera()


func _release_depth_profiles_for_body(body: Node3D) -> void:
	if body == null or not is_instance_valid(body) or get_tree() == null:
		return
	var profiles: Array[Node] = get_tree().get_nodes_in_group(&"automation_25d_depth_profiles")
	for profile: Node in profiles:
		if profile != null and profile.has_method("release_body_for_automation"):
			profile.call("release_body_for_automation", body, self)


func _physics_process(delta: float) -> void:
	if not enabled:
		_clear_bodies()
		return
	if not _activation_configured or _path == null or _path.curve == null:
		return
	if not camera_enabled:
		_unregister_camera()

	if _camera_body != null and not is_instance_valid(_camera_body):
		_unregister_camera()
	_remove_invalid_bodies()
	if _camera_body == null:
		_register_first_available_camera_body()

	var curve: Curve3D = _path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.001:
		return

	for index: int in range(_bodies.size() - 1, -1, -1):
		var body: Node3D = _bodies[index]
		if _is_beyond_failsafe(body, curve):
			_deactivate_body(body)

	for body: Node3D in _bodies:
		if not _body_has_local_authority(body):
			continue
		_apply_two_point_five_d_state(body, curve, length, delta)


func refresh_25d_constraint_after_slide(body: Node3D) -> void:
	if (
		not enabled
		or not _activation_configured
		or body == null
		or not is_instance_valid(body)
		or not _bodies.has(body)
		or _path == null
		or _path.curve == null
	):
		return
	var curve: Curve3D = _path.curve
	var length: float = max(curve.get_baked_length(), 0.0)
	if length <= 0.001:
		return
	_apply_two_point_five_d_state(body, curve, length, 0.0, false)


func _apply_two_point_five_d_state(
	body: Node3D,
	curve: Curve3D,
	length: float,
	delta: float,
	update_camera: bool = true
) -> void:
	var body_id: int = body.get_instance_id()
	var body_local: Vector3 = _path.to_local(body.global_position)
	var progress_state: Dictionary = _get_progress_state(body_id, body_local)
	var preferred_offset: float = float(progress_state.get("offset", -1.0))
	var previous_normal: Vector3 = progress_state.get("plane_normal", Vector3.ZERO) as Vector3
	var previous_tangent: Vector3 = progress_state.get("tangent", Vector3.ZERO) as Vector3
	var previous_local: Vector3 = progress_state.get("local_position", body_local) as Vector3
	var tracking_window: float = max(preferred_offset_window, 0.0)
	if speed_adaptive_tracking_window:
		var traveled_distance: float = previous_local.distance_to(body_local)
		tracking_window = max(
			tracking_window,
			traveled_distance * max(tracking_window_travel_multiplier, 1.0)
		)
		if max_adaptive_tracking_window > 0.0:
			tracking_window = min(tracking_window, max_adaptive_tracking_window)
	var closest_data: Dictionary = _get_closest_3d(
		curve,
		body_local,
		preferred_offset,
		tracking_window
	)
	var offset: float = clamp(float(closest_data.get("offset", 0.0)), 0.0, length)
	var closest_local: Vector3 = closest_data.get("point", body_local) as Vector3
	if cubic_path_sampling:
		closest_local = curve.sample_baked(offset, true)
	var path_point: Vector3 = _path.to_global(closest_local)
	var tangent: Vector3 = _get_tangent_world(curve, offset, length)
	if tangent.length() < 0.001:
		return

	var path_frame: Transform3D = _get_path_frame_world(curve, offset, tangent)
	var plane_normal: Vector3 = _get_plane_normal(body, tangent, path_frame)
	if plane_normal.length() < 0.001 and preserve_frame_through_degenerate_segments:
		plane_normal = previous_normal
	if plane_normal.length() < 0.001:
		return
	plane_normal = plane_normal.normalized()
	if reverse_plane_normal:
		plane_normal = -plane_normal
	if previous_normal.length() > 0.001 and plane_normal.dot(previous_normal) < 0.0:
		plane_normal = -plane_normal
	var surface_frame: Dictionary = _get_surface_cooperative_frame(
		body,
		tangent,
		plane_normal,
		progress_state
	)
	tangent = surface_frame.get("tangent", tangent) as Vector3
	plane_normal = surface_frame.get("normal", plane_normal) as Vector3
	if tangent.length() < 0.001 and preserve_frame_through_degenerate_segments:
		tangent = previous_tangent
	if plane_normal.length() < 0.001:
		return
	plane_normal = plane_normal.normalized()
	if previous_normal.length() > 0.001 and plane_normal.dot(previous_normal) < 0.0:
		plane_normal = -plane_normal
	var terrain_adjusted: bool = bool(surface_frame.get("adjusted", false))

	var plane_up: Vector3 = surface_frame.get(
		"up",
		plane_normal.cross(tangent)
	) as Vector3
	if plane_up.length() < 0.001:
		plane_up = path_frame.basis.y
	if plane_up.length() < 0.001:
		plane_up = _get_body_gravity_up(body)
	plane_up = plane_up.normalized()
	if (
		not terrain_adjusted
		and path_frame.basis.y.length() > 0.001
		and plane_up.dot(path_frame.basis.y) < 0.0
	):
		plane_up = -plane_up

	var influence: float = _get_adherence_weight(curve, offset, length)
	var plane_offset_state: Dictionary = _get_adaptive_plane_offset_state(
		body,
		path_point,
		plane_normal,
		progress_state,
		influence,
		delta
	)
	var plane_offset: float = float(plane_offset_state.get("offset", 0.0))
	var constrained_path_point: Vector3 = path_point + plane_normal * plane_offset
	var constraint_influence: float = max(
		influence,
		clamp(float(plane_offset_state.get("minimum_constraint_adherence", 0.0)), 0.0, 1.0)
	)
	var strict_position_lock_effective: bool = strict_position_lock
	var position_lock_strength_effective: float = position_lock_strength
	var max_position_correction_speed_effective: float = max_position_correction_speed
	var position_lock_deadzone_effective: float = position_lock_deadzone
	if bool(plane_offset_state.get("override_position_constraint", false)):
		strict_position_lock_effective = bool(
			plane_offset_state.get("strict_position_lock", strict_position_lock)
		)
		position_lock_strength_effective = max(
			float(plane_offset_state.get("position_lock_strength", position_lock_strength)),
			0.0
		)
		max_position_correction_speed_effective = max(
			float(
				plane_offset_state.get(
					"max_position_correction_speed",
					max_position_correction_speed
				)
			),
			0.0
		)
		position_lock_deadzone_effective = max(
			float(plane_offset_state.get("position_lock_deadzone", position_lock_deadzone)),
			0.0
		)
	_body_offsets[body_id] = {
		"offset": offset,
		"furthest_offset": offset,
		"local_position": body_local,
		"plane_normal": plane_normal,
		"tangent": tangent,
		"plane_offset": plane_offset,
		"plane_offset_initialized": true,
		"captured_depth_offset": float(plane_offset_state.get("captured_depth_offset", 0.0)),
		"depth_source_active": bool(plane_offset_state.get("depth_source_active", false)),
		"depth_release_active": bool(plane_offset_state.get("depth_release_active", false)),
		"terrain_orientation_sign": float(surface_frame.get("orientation_sign", 0.0)),
	}

	var lock_movement_effective: bool = lock_movement or lock_controls
	var lock_actions_effective: bool = lock_actions or lock_controls
	var lock_drift_effective: bool = lock_drift or lock_controls or not allow_drift
	var state: Dictionary = {
		"tangent_dir": tangent,
		"toward_dir": Vector3.ZERO,
		"toward_strength": 0.0,
		"max_turn_deg_per_sec": max_turn_deg_per_sec if use_guided_turn_rate_limit else 0.0,
		"continuous_force": false,
		"align_rotation": false,
		"grounded_only": not constrain_airborne,
		"force_surface_adhesion": force_surface_adhesion and constraint_influence > 0.001,
		"tangent_snap_strength": terrain_tangent_alignment_strength * constraint_influence if terrain_adjusted else 0.0,
		"along_assist_enabled": along_assist_enabled,
		"along_assist_target_speed": along_assist_target_speed,
		"along_assist_accel": along_assist_accel,
		"along_assist_limits_player_speed": along_assist_limits_player_speed,
		"bidirectional_assist": bidirectional_along_assist,
		"lock_movement": lock_movement_effective,
		"lock_actions": lock_actions_effective,
		"lock_drift": lock_drift_effective,
		"priority": priority,
		"ignore_water_physics_multipliers": ignore_water_physics_multipliers,
		"override_max_speed": override_player_max_speed,
		"max_speed_override": player_max_speed_override,
		"mode": 1,
		"constraint_source": self,
		"influence": constraint_influence,
		"path_point": constrained_path_point,
		"plane_normal": plane_normal,
		"plane_up": plane_up,
		"input_mode": int(plane_input_mode),
		"reverse_input": reverse_plane_input,
		"input_deadzone": plane_input_deadzone,
		"strict_position_lock": strict_position_lock_effective,
		"post_slide_constraint_pass_enabled": post_slide_constraint_pass_enabled,
		"position_lock_strength": position_lock_strength_effective,
		"max_position_correction_speed": max_position_correction_speed_effective,
		"position_lock_deadzone": position_lock_deadzone_effective,
		"strict_velocity_lock": strict_velocity_lock,
		"disable_turning_slowdown": disable_turning_slowdown,
		"velocity_lock_strength": velocity_lock_strength,
		"sideways_speed_preservation": sideways_removal_speed_preservation,
		"constrain_special_moves": constrain_special_moves,
	}

	if body.has_method("set_automation_spline_state"):
		body.call("set_automation_spline_state", state)
	elif body.has_method("set_automation_spline"):
		body.call(
			"set_automation_spline",
			tangent,
			Vector3.ZERO,
			0.0,
			float(state["max_turn_deg_per_sec"]),
			lock_controls,
			false,
			false,
			bool(state["grounded_only"]),
			force_surface_adhesion,
			0.0,
			along_assist_enabled,
			along_assist_target_speed,
			along_assist_accel,
			lock_movement_effective,
			lock_actions_effective,
			lock_drift_effective,
			priority,
			ignore_water_physics_multipliers,
			override_player_max_speed,
			player_max_speed_override
		)

	if update_camera and body == _camera_body:
		var velocity_value: Variant = body.get("velocity")
		var body_velocity: Vector3 = velocity_value as Vector3 if velocity_value is Vector3 else Vector3.ZERO
		_update_camera_transform(
			body,
			constrained_path_point,
			tangent,
			plane_normal,
			path_frame,
			body_velocity,
			delta
		)


func _get_progress_state(body_id: int, local_position: Vector3) -> Dictionary:
	if not _body_offsets.has(body_id):
		return {
			"offset": -1.0,
			"furthest_offset": -1.0,
			"local_position": local_position,
			"plane_normal": Vector3.ZERO,
			"tangent": Vector3.ZERO,
			"plane_offset": 0.0,
			"plane_offset_initialized": false,
			"captured_depth_offset": 0.0,
			"depth_source_active": false,
			"depth_release_active": false,
			"terrain_orientation_sign": 0.0,
		}
	var stored_progress: Variant = _body_offsets[body_id]
	if stored_progress is Dictionary:
		return stored_progress as Dictionary
	var legacy_offset: float = float(stored_progress)
	return {
		"offset": legacy_offset,
		"furthest_offset": legacy_offset,
		"local_position": local_position,
		"plane_normal": Vector3.ZERO,
		"tangent": Vector3.ZERO,
		"plane_offset": 0.0,
		"plane_offset_initialized": false,
		"captured_depth_offset": 0.0,
		"depth_source_active": false,
		"depth_release_active": false,
		"terrain_orientation_sign": 0.0,
	}


func _get_tangent_world(curve: Curve3D, offset: float, length: float) -> Vector3:
	var sample_distance: float = max(tangent_lookahead, max(curve.bake_interval, 0.05))
	var behind_offset: float = max(offset - sample_distance, 0.0)
	var ahead_offset: float = min(offset + sample_distance, length)
	var behind_world: Vector3 = _path.to_global(
		curve.sample_baked(behind_offset, cubic_path_sampling)
	)
	var ahead_world: Vector3 = _path.to_global(
		curve.sample_baked(ahead_offset, cubic_path_sampling)
	)
	var tangent: Vector3 = ahead_world - behind_world
	if tangent.length() < 0.001 and curve.closed:
		behind_offset = wrapf(offset - sample_distance, 0.0, length)
		ahead_offset = wrapf(offset + sample_distance, 0.0, length)
		behind_world = _path.to_global(curve.sample_baked(behind_offset, cubic_path_sampling))
		ahead_world = _path.to_global(curve.sample_baked(ahead_offset, cubic_path_sampling))
		tangent = ahead_world - behind_world
	return tangent.normalized() if tangent.length() > 0.001 else Vector3.ZERO


func _get_path_frame_world(curve: Curve3D, offset: float, tangent: Vector3) -> Transform3D:
	var local_frame: Transform3D = Transform3D(
		Basis.IDENTITY,
		curve.sample_baked(offset, cubic_path_sampling)
	)
	if curve.up_vector_enabled:
		local_frame = curve.sample_baked_with_rotation(offset, cubic_path_sampling)
	var world_frame: Transform3D = _path.global_transform * local_frame
	if not curve.up_vector_enabled:
		var up: Vector3 = _path.global_transform.basis.y.normalized()
		if up.length() < 0.001 or abs(up.dot(tangent)) > 0.999:
			up = Vector3.UP
		if abs(up.dot(tangent)) > 0.999:
			up = Vector3.FORWARD
		var side: Vector3 = tangent.cross(up).normalized()
		up = side.cross(tangent).normalized()
		world_frame.basis = Basis(side, up, -tangent).orthonormalized()
	return world_frame


func _get_plane_normal(body: Node3D, tangent: Vector3, path_frame: Transform3D) -> Vector3:
	var normal: Vector3 = Vector3.ZERO
	match plane_frame_mode:
		PlaneFrameMode.PATH_FRAME:
			normal = path_frame.basis.x
		PlaneFrameMode.GRAVITY_RIBBON:
			normal = tangent.cross(_get_body_gravity_up(body))
		PlaneFrameMode.PLAYER_RIBBON:
			normal = tangent.cross(_get_body_player_up(body))
		PlaneFrameMode.FIXED_PATH_AXIS:
			normal = _path.global_transform.basis.x
	normal -= tangent * normal.dot(tangent)
	if normal.length() < 0.001:
		normal = path_frame.basis.x
		normal -= tangent * normal.dot(tangent)
	return normal.normalized() if normal.length() > 0.001 else Vector3.ZERO


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


func _body_is_attached(body: Node3D) -> bool:
	if body.has_method("is_attached_for_movement"):
		var attached_value: Variant = body.call("is_attached_for_movement")
		if attached_value is bool:
			return bool(attached_value)
	var attached_property: Variant = body.get("attached")
	return attached_property is bool and bool(attached_property)


func _get_body_surface_normal(body: Node3D) -> Vector3:
	var surface_value: Variant = body.get("surface_normal")
	if surface_value is Vector3 and (surface_value as Vector3).length() > 0.001:
		return (surface_value as Vector3).normalized()
	return Vector3.ZERO


func _get_body_velocity(body: Node3D) -> Vector3:
	var velocity_value: Variant = body.get("velocity")
	return velocity_value as Vector3 if velocity_value is Vector3 else Vector3.ZERO


func _get_surface_cooperative_frame(
	body: Node3D,
	curve_tangent: Vector3,
	curve_normal: Vector3,
	progress_state: Dictionary
) -> Dictionary:
	var orientation_sign: float = float(progress_state.get("terrain_orientation_sign", 0.0))
	var fallback_frame: Dictionary = {
		"tangent": curve_tangent,
		"normal": curve_normal,
		"up": curve_normal.cross(curve_tangent),
		"adjusted": false,
		"orientation_sign": orientation_sign,
	}
	if not surface_frame_enabled or not _body_is_attached(body):
		return fallback_frame
	var surface_normal: Vector3 = _get_body_surface_normal(body)
	if surface_frame_preserve_ribbon_normal:
		surface_normal -= curve_normal * surface_normal.dot(curve_normal)
	if surface_normal.length() < 0.001:
		return fallback_frame
	surface_normal = surface_normal.normalized()

	var surface_tangent: Vector3 = Vector3.ZERO
	match surface_traversal_mode:
		SurfaceTraversalMode.PROJECT_PATH_ON_SURFACE:
			surface_tangent = curve_tangent - surface_normal * curve_tangent.dot(surface_normal)
		SurfaceTraversalMode.RIBBON_SURFACE_TANGENT:
			surface_tangent = surface_normal.cross(curve_normal)
			if abs(orientation_sign) < 0.5:
				var reference_up: Vector3 = _get_body_gravity_up(body)
				reference_up -= curve_normal * reference_up.dot(curve_normal)
				var reference_tangent: Vector3 = reference_up.cross(curve_normal)
				if (
					reference_tangent.length() > 0.001
					and abs(reference_tangent.normalized().dot(curve_tangent)) > 0.001
				):
					orientation_sign = (
						1.0 if reference_tangent.dot(curve_tangent) >= 0.0 else -1.0
					)
				else:
					orientation_sign = 1.0
			surface_tangent *= orientation_sign
	if surface_tangent.length() < 0.001:
		return fallback_frame
	surface_tangent = surface_tangent.normalized()

	if surface_frame_uses_velocity:
		var body_velocity: Vector3 = _get_body_velocity(body)
		var surface_velocity: Vector3 = body_velocity
		surface_velocity -= surface_normal * surface_velocity.dot(surface_normal)
		if surface_frame_preserve_ribbon_normal:
			surface_velocity -= curve_normal * surface_velocity.dot(curve_normal)
		if surface_velocity.length() >= surface_frame_min_speed:
			surface_velocity = surface_velocity.normalized()
			if surface_velocity.dot(surface_tangent) < 0.0:
				surface_velocity = -surface_velocity
			surface_tangent = surface_velocity

	var frame_weight: float = clamp(surface_frame_influence, 0.0, 1.0)
	var turn_angle: float = curve_tangent.signed_angle_to(surface_tangent, curve_normal)
	var tangent: Vector3 = curve_tangent.rotated(curve_normal, turn_angle * frame_weight)
	if tangent.length() < 0.001:
		tangent = surface_tangent
	tangent = tangent.normalized()

	var normal: Vector3 = curve_normal
	if not surface_frame_preserve_ribbon_normal:
		var surface_plane_normal: Vector3 = tangent.cross(surface_normal)
		if surface_plane_normal.length() > 0.001:
			surface_plane_normal = surface_plane_normal.normalized()
			if surface_plane_normal.dot(curve_normal) < 0.0:
				surface_plane_normal = -surface_plane_normal
			normal = curve_normal.slerp(surface_plane_normal, frame_weight)
	normal -= tangent * normal.dot(tangent)
	if normal.length() < 0.001:
		normal = curve_normal
	normal = normal.normalized()
	var terrain_up: Vector3 = normal.cross(tangent)
	if terrain_up.length() < 0.001:
		terrain_up = surface_normal
	else:
		terrain_up = terrain_up.normalized()
	return {
		"tangent": tangent,
		"normal": normal,
		"up": terrain_up,
		"adjusted": true,
		"orientation_sign": orientation_sign,
	}


func _get_terrain_piece_anchor_offset(
	body: Node3D,
	path_point: Vector3,
	plane_normal: Vector3,
	current_offset: float
) -> Dictionary:
	if (
		not terrain_piece_anchors_enabled
		or terrain_piece_anchor_metadata == &""
		or not _body_is_attached(body)
		or not body.has_method("get_slide_collision_count")
		or not body.has_method("get_slide_collision")
	):
		return {}

	var collision_count_value: Variant = body.call("get_slide_collision_count")
	if not collision_count_value is int:
		return {}
	var collision_count: int = int(collision_count_value)
	var best_offset: float = 0.0
	var best_distance: float = INF
	var found: bool = false
	for collision_index: int in range(collision_count):
		var collision_value: Variant = body.call("get_slide_collision", collision_index)
		if not collision_value is KinematicCollision3D:
			continue
		var collision: KinematicCollision3D = collision_value as KinematicCollision3D
		var collider_node: Node = collision.get_collider() as Node
		var search_node: Node = collider_node
		for _parent_index: int in range(terrain_piece_anchor_parent_search + 1):
			if search_node == null:
				break
			if search_node.has_meta(terrain_piece_anchor_metadata):
				var anchor_value: Variant = search_node.get_meta(terrain_piece_anchor_metadata)
				var candidate_offset: float = 0.0
				var valid_anchor: bool = false
				if anchor_value is bool and bool(anchor_value) and search_node is Node3D:
					var anchor_node: Node3D = search_node as Node3D
					candidate_offset = (anchor_node.global_position - path_point).dot(plane_normal)
					valid_anchor = true
				elif anchor_value is Vector3 and search_node is Node3D:
					var local_anchor_node: Node3D = search_node as Node3D
					var anchor_position: Vector3 = local_anchor_node.to_global(anchor_value as Vector3)
					candidate_offset = (anchor_position - path_point).dot(plane_normal)
					valid_anchor = true
				elif anchor_value is float or anchor_value is int:
					candidate_offset = float(anchor_value)
					valid_anchor = true
				if valid_anchor:
					var candidate_distance: float = abs(candidate_offset - current_offset)
					if candidate_distance < best_distance:
						best_offset = candidate_offset
						best_distance = candidate_distance
						found = true
				break
			search_node = search_node.get_parent()
	if not found:
		return {}
	return {"found": true, "offset": best_offset}


func _get_depth_offset_profile_target(
	body: Node3D,
	path_point: Vector3,
	plane_normal: Vector3
) -> Dictionary:
	if not depth_offset_splines_enabled or get_tree() == null:
		return {}
	var best_state: Dictionary = {}
	var best_priority: int = -2147483648
	var best_distance: float = INF
	var profiles: Array[Node] = get_tree().get_nodes_in_group(&"automation_25d_depth_profiles")
	for profile: Node in profiles:
		if profile == null or not is_instance_valid(profile):
			continue
		if not profile.has_method("get_depth_offset_target"):
			continue
		var state_value: Variant = profile.call(
			"get_depth_offset_target",
			body,
			self,
			path_point,
			plane_normal
		)
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value as Dictionary
		if not bool(state.get("found", false)):
			continue
		var state_priority: int = int(state.get("priority", 0))
		var state_distance: float = float(state.get("profile_distance", INF))
		if (
			state_priority > best_priority
			or (state_priority == best_priority and state_distance < best_distance)
		):
			best_state = state
			best_priority = state_priority
			best_distance = state_distance
	return best_state


func _get_adaptive_plane_offset_state(
	body: Node3D,
	path_point: Vector3,
	plane_normal: Vector3,
	progress_state: Dictionary,
	influence: float,
	delta: float
) -> Dictionary:
	var body_offset: float = (body.global_position - path_point).dot(plane_normal)
	var initialized: bool = bool(progress_state.get("plane_offset_initialized", false))
	var current_offset: float = float(progress_state.get("plane_offset", 0.0))
	var captured_depth_offset: float = float(
		progress_state.get("captured_depth_offset", current_offset)
	)
	if not initialized:
		captured_depth_offset = body_offset if capture_entry_depth_offset else 0.0
		if adaptive_centerline_max_offset > 0.0:
			captured_depth_offset = clamp(
				captured_depth_offset,
				-adaptive_centerline_max_offset,
				adaptive_centerline_max_offset
			)
		current_offset = captured_depth_offset

	var target_offset: float = body_offset
	var depth_source_active: bool = false
	var depth_profile: Dictionary = _get_depth_offset_profile_target(
		body,
		path_point,
		plane_normal
	)
	var depth_profile_found: bool = bool(depth_profile.get("found", false))
	var centerline_max_offset_limit: float = adaptive_centerline_max_offset
	if (
		depth_profile_found
		and bool(depth_profile.get("override_centerline_offset_limit", false))
	):
		centerline_max_offset_limit = max(
			float(depth_profile.get("centerline_max_offset", 0.0)),
			0.0
		)
	if depth_profile_found:
		target_offset = float(depth_profile.get("offset", body_offset))
		depth_source_active = true
	else:
		var terrain_anchor: Dictionary = _get_terrain_piece_anchor_offset(
			body,
			path_point,
			plane_normal,
			current_offset
		)
		if bool(terrain_anchor.get("found", false)):
			target_offset = float(terrain_anchor.get("offset", body_offset))
			depth_source_active = true
		elif not follow_unanchored_surface_depth:
			target_offset = captured_depth_offset
			if captured_depth_transition_enabled:
				target_offset = lerp(
					captured_depth_offset,
					0.0,
					clamp(influence, 0.0, 1.0)
				)

	if centerline_max_offset_limit > 0.0:
		target_offset = clamp(
			target_offset,
			-centerline_max_offset_limit,
			centerline_max_offset_limit
		)

	var previous_source_active: bool = bool(progress_state.get("depth_source_active", false))
	var depth_release_active: bool = bool(progress_state.get("depth_release_active", false))
	if depth_source_active:
		depth_release_active = false
	elif previous_source_active:
		depth_release_active = true

	var direct_transition_rebase: bool = (
		not depth_source_active
		and not depth_release_active
		and not follow_unanchored_surface_depth
	)
	var response_strength: float = adaptive_centerline_strength
	var response_max_speed: float = adaptive_centerline_max_speed
	var response_deadzone: float = adaptive_centerline_deadzone
	var response_mode: int = int(depth_profile.get("centerline_response_mode", 0))
	if depth_profile_found and response_mode == 1:
		response_strength = max(float(depth_profile.get("centerline_strength", response_strength)), 0.0)
		response_max_speed = max(float(depth_profile.get("centerline_max_speed", response_max_speed)), 0.0)

	var may_adapt: bool = adaptive_centerline_enabled
	var profile_allows_airborne: bool = bool(depth_profile.get("allow_airborne", false))
	if (
		adaptive_centerline_grounded_only
		and not _body_is_attached(body)
		and not (depth_profile_found and profile_allows_airborne)
	):
		may_adapt = false
	if direct_transition_rebase:
		current_offset = target_offset
	elif depth_profile_found and response_mode == 2 and may_adapt:
		current_offset = target_offset
	else:
		if may_adapt and abs(target_offset - current_offset) > response_deadzone:
			var follow_weight: float = 1.0
			if response_strength > 0.0:
				follow_weight = 1.0 - exp(-response_strength * max(delta, 0.0))
			var followed_offset: float = lerp(current_offset, target_offset, follow_weight)
			if response_max_speed > 0.0:
				followed_offset = move_toward(
					current_offset,
					followed_offset,
					response_max_speed * max(delta, 0.0)
				)
			current_offset = followed_offset
		if depth_release_active and abs(target_offset - current_offset) <= response_deadzone:
			current_offset = target_offset
			depth_release_active = false

	if centerline_max_offset_limit > 0.0 and not depth_release_active:
		current_offset = clamp(
			current_offset,
			-centerline_max_offset_limit,
			centerline_max_offset_limit
		)
	return {
		"offset": current_offset,
		"captured_depth_offset": captured_depth_offset,
		"depth_source_active": depth_source_active,
		"depth_release_active": depth_release_active,
		"minimum_constraint_adherence": float(
			depth_profile.get("minimum_constraint_adherence", 0.0)
		) if depth_profile_found else 0.0,
		"override_position_constraint": bool(
			depth_profile.get("override_position_constraint", false)
		) if depth_profile_found else false,
		"strict_position_lock": bool(
			depth_profile.get("strict_position_lock", strict_position_lock)
		),
		"position_lock_strength": float(
			depth_profile.get("position_lock_strength", position_lock_strength)
		),
		"max_position_correction_speed": float(
			depth_profile.get(
				"max_position_correction_speed",
				max_position_correction_speed
			)
		),
		"position_lock_deadzone": float(
			depth_profile.get("position_lock_deadzone", position_lock_deadzone)
		),
	}


func _get_adherence_weight(curve: Curve3D, offset: float, length: float) -> float:
	if curve.closed:
		return 1.0
	var entry_weight: float = 1.0
	var exit_weight: float = 1.0
	if entry_blend_distance > 0.001:
		entry_weight = _ease_transition(offset / entry_blend_distance)
	if exit_blend_distance > 0.001:
		exit_weight = _ease_transition((length - offset) / exit_blend_distance)
	return clamp(min(entry_weight, exit_weight), 0.0, 1.0)


func _ease_transition(value: float) -> float:
	var weight: float = clamp(value, 0.0, 1.0)
	match transition_ease:
		TransitionEase.SMOOTHSTEP:
			return weight * weight * (3.0 - 2.0 * weight)
		TransitionEase.SMOOTHERSTEP:
			return weight * weight * weight * (weight * (weight * 6.0 - 15.0) + 10.0)
	return weight


func _get_closest_3d(
	curve: Curve3D,
	local_position: Vector3,
	preferred_offset: float,
	tracking_window: float = -1.0
) -> Dictionary:
	var points: PackedVector3Array = curve.get_baked_points()
	var count: int = points.size()
	if count == 0:
		return {"offset": 0.0, "point": local_position, "dist_sq": 0.0}
	if count == 1:
		return {
			"offset": 0.0,
			"point": points[0],
			"dist_sq": points[0].distance_squared_to(local_position),
		}

	var length: float = max(curve.get_baked_length(), 0.0)
	var prefer: bool = preferred_offset >= 0.0 and length > 0.0
	var preferred: float = clamp(preferred_offset, 0.0, length) if prefer else 0.0
	var window: float = (
		max(tracking_window, 0.0)
		if tracking_window >= 0.0
		else max(preferred_offset_window, 0.0)
	)
	var use_window: bool = prefer and window > 0.0
	var best_distance_squared: float = INF
	var best_preferred_delta: float = INF
	var best_offset: float = 0.0
	var best_point: Vector3 = points[0]
	var window_distance_squared: float = INF
	var window_preferred_delta: float = INF
	var window_offset: float = 0.0
	var window_point: Vector3 = points[0]
	var window_found: bool = false
	var distance_accumulated: float = 0.0

	for index: int in range(count - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var segment: Vector3 = finish - start
		var segment_length: float = segment.length()
		if segment_length < 0.0001:
			continue
		var segment_weight: float = clamp(
			(local_position - start).dot(segment) / segment.length_squared(),
			0.0,
			1.0
		)
		var candidate: Vector3 = start + segment * segment_weight
		var candidate_offset: float = distance_accumulated + segment_length * segment_weight
		var distance_squared: float = candidate.distance_squared_to(local_position)
		var preferred_delta: float = 0.0
		if prefer:
			preferred_delta = abs(candidate_offset - preferred)
			if curve.closed:
				preferred_delta = min(preferred_delta, max(length - preferred_delta, 0.0))

		if (
			distance_squared < best_distance_squared - 0.0001
			or (
				abs(distance_squared - best_distance_squared) <= 0.0001
				and prefer
				and preferred_delta < best_preferred_delta
			)
		):
			best_distance_squared = distance_squared
			best_preferred_delta = preferred_delta
			best_offset = candidate_offset
			best_point = candidate

		if use_window and preferred_delta <= window:
			if (
				distance_squared < window_distance_squared - 0.0001
				or (
					abs(distance_squared - window_distance_squared) <= 0.0001
					and preferred_delta < window_preferred_delta
				)
			):
				window_distance_squared = distance_squared
				window_preferred_delta = preferred_delta
				window_offset = candidate_offset
				window_point = candidate
				window_found = true
		distance_accumulated += segment_length

	if use_window and window_found:
		var window_distance: float = sqrt(max(window_distance_squared, 0.0))
		var best_distance: float = sqrt(max(best_distance_squared, 0.0))
		var branch_switch_distance: float = best_distance + branch_switch_distance_tolerance
		var recovery_distance: float = max(tracking_recovery_distance, 0.0)
		if (
			window_distance <= branch_switch_distance
			or (recovery_distance > 0.0 and window_distance <= recovery_distance)
		):
			return {
				"offset": window_offset,
				"point": window_point,
				"dist_sq": window_distance_squared,
			}
	return {"offset": best_offset, "point": best_point, "dist_sq": best_distance_squared}


func _build_camera_constraint() -> void:
	if not is_instance_valid(_camera_constraint):
		_camera_constraint = CameraConstraint.new()
		add_child(_camera_constraint)
	_camera_constraint.constraint_priority = constraint_priority
	_camera_constraint.override_previous_constraints = override_previous_camera_constraints
	_camera_constraint.disable_camera_controls = disable_camera_controls
	_camera_constraint.suppress_speed_effects = true
	_camera_constraint.up_mode = CameraConstraint.UpMode.PLAYER if target_use_player_up else CameraConstraint.UpMode.GRAVITY
	if not override_use_player_up:
		_camera_constraint.up_mode = CameraConstraint.UpMode.INHERIT
	_camera_constraint.collision_mode = CameraConstraint.CollisionMode.INHERIT
	if override_camera_collision:
		_camera_constraint.collision_mode = CameraConstraint.CollisionMode.ENABLED if camera_collision_enabled_override else CameraConstraint.CollisionMode.DISABLED
	var placement: CameraPositionTrait = CameraPositionTrait.new()
	placement.mode = CameraPositionTrait.Mode.FIXED_PIVOT
	placement.source_path = NodePath("")
	placement.tracking_response = position_smoothing
	_camera_constraint.position_traits.assign([placement])
	var aim: CameraOrientationTrait = CameraOrientationTrait.new()
	aim.mode = CameraOrientationTrait.Mode.FACE_PLAYER if face_player else CameraOrientationTrait.Mode.MARKER_ROTATION
	aim.target_path = NodePath("")
	aim.target_offset = aim_target_offset
	aim.offset_uses_player_up = aim_offset_uses_player_up
	aim.up_source = CameraOrientationTrait.UpSource.PLAYER if aim_up_uses_player_up else CameraOrientationTrait.UpSource.GRAVITY
	aim.tracking_response = aim_smooth if face_player else rotation_smoothing
	aim.strength = aim_strength
	aim.orbit_rig = not face_player
	_camera_constraint.orientation_traits.assign([aim])
	if allow_roll and absf(roll_deg) > 0.001:
		var roll: CameraOrientationTrait = CameraOrientationTrait.new()
		roll.mode = CameraOrientationTrait.Mode.ROLL
		roll.roll_degrees = roll_deg
		_camera_constraint.orientation_traits.append(roll)
	_camera_constraint.lens_traits.clear()
	if distance_override_enabled:
		var orbit: CameraLensTrait = CameraLensTrait.new()
		orbit.mode = CameraLensTrait.Mode.ORBIT_DISTANCE
		orbit.distance = distance_override
		_camera_constraint.lens_traits.append(orbit)
	if fov_override_enabled:
		var lens: CameraLensTrait = CameraLensTrait.new()
		lens.mode = CameraLensTrait.Mode.DISTANCE_FOV if fov_distance_based_enabled else CameraLensTrait.Mode.FIXED_FOV
		lens.fov = fov_override
		lens.near_fov = fov_distance_near_fov
		lens.far_fov = fov_distance_far_fov
		lens.near_distance = fov_distance_near
		lens.far_distance = fov_distance_far
		lens.tracking_response = fov_smoothing if fov_smoothing_independent or entry_smoothing_enabled else 0.0
		lens.distance_source = CameraLensTrait.DistanceSource.MARKER_TO_PLAYER
		lens.source_path = NodePath("")
		_camera_constraint.lens_traits.append(lens)
	var entry: CameraTransitionTrait = CameraTransitionTrait.new()
	entry.mode = CameraTransitionTrait.Mode.TIMED if entry_smoothing_enabled else CameraTransitionTrait.Mode.INSTANT
	entry.duration = entry_smoothing_duration
	var exit: CameraTransitionTrait = CameraTransitionTrait.new()
	exit.phase = CameraTransitionTrait.Phase.EXIT
	exit.mode = CameraTransitionTrait.Mode.TIMED if exit_smoothing_enabled else CameraTransitionTrait.Mode.INSTANT
	exit.duration = exit_smoothing_duration
	_camera_constraint.transition_traits.assign([entry, exit])
	_camera_constraint.set_locked_transform(_camera_transform)


func _try_register_camera(body: Node3D) -> void:
	if not camera_enabled or _camera_registered or not _body_has_local_authority(body):
		return
	_get_camera_rig(body)
	if _camera_rig == null or not _camera_rig.has_method("register_camera_constraint"):
		return
	_camera_body = body
	_build_camera_constraint()
	_camera_rig.call("register_camera_constraint", _camera_constraint)
	_camera_registered = true
	_camera_lead_distance_current = 0.0
	_camera_lead_direction = 0.0


func _register_first_available_camera_body() -> void:
	if _camera_registered:
		return
	for body: Node3D in _bodies:
		if body != null and is_instance_valid(body) and _body_has_local_authority(body):
			_try_register_camera(body)
			if _camera_registered:
				return


func _unregister_camera() -> void:
	if _camera_registered:
		_get_camera_rig()
		if _camera_rig != null and _camera_rig.has_method("unregister_camera_constraint"):
			_camera_rig.call("unregister_camera_constraint", _camera_constraint)
	_camera_registered = false
	_camera_body = null
	_camera_lead_distance_current = 0.0
	_camera_lead_direction = 0.0


func _get_camera_rig(body: Node3D = null) -> void:
	var camera_body: Node3D = body if body else _camera_body
	if is_instance_valid(_camera_rig) and _camera_rig.get("target") == camera_body:
		return
	_camera_rig = null
	if get_tree() == null:
		return
	var rigs: Array[Node] = get_tree().get_nodes_in_group("CameraRig")
	for candidate: Node in rigs:
		if candidate.get("target") == camera_body:
			_camera_rig = candidate
			return


func _body_has_local_authority(body: Node3D) -> bool:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return true
	if body.has_method("is_multiplayer_authority"):
		return body.is_multiplayer_authority()
	return true


func is_body_active_for_25d(body: Node3D) -> bool:
	return body != null and is_instance_valid(body) and _bodies.has(body)


func _get_camera_up(body: Node3D, path_frame: Transform3D, view_axis: Vector3) -> Vector3:
	var camera_up: Vector3 = _get_body_gravity_up(body)
	if allow_roll:
		match camera_up_mode:
			CameraUpMode.GRAVITY:
				camera_up = _get_body_gravity_up(body)
			CameraUpMode.PLAYER:
				camera_up = _get_body_player_up(body)
			CameraUpMode.PATH_FRAME:
				camera_up = path_frame.basis.y
	camera_up -= view_axis * camera_up.dot(view_axis)
	if camera_up.length() < 0.001:
		camera_up = path_frame.basis.y
		camera_up -= view_axis * camera_up.dot(view_axis)
	if camera_up.length() < 0.001:
		camera_up = Vector3.UP
	return camera_up.normalized()


func _update_camera_lead(signed_path_speed: float, delta: float) -> float:
	var direction_threshold: float = max(camera_lead_direction_speed, 0.0)
	var has_travel_direction: bool = abs(signed_path_speed) > direction_threshold
	if has_travel_direction:
		_camera_lead_direction = sign(signed_path_speed)

	var recentering: bool = (
		not has_travel_direction
		and camera_idle_lead_mode == CameraIdleLeadMode.RECENTER
	)
	var target_lead: float = 0.0
	if not recentering and abs(_camera_lead_direction) > 0.001:
		target_lead = camera_path_lead_distance * _camera_lead_direction
		if has_travel_direction:
			target_lead += signed_path_speed * camera_velocity_lead_time
	if camera_max_lead_distance > 0.0:
		target_lead = clamp(
			target_lead,
			-camera_max_lead_distance,
			camera_max_lead_distance
		)

	var response_speed: float = (
		camera_lead_recenter_smoothing if recentering else camera_lead_smoothing
	)
	var followed_lead: float = target_lead
	if response_speed > 0.0:
		var follow_weight: float = 1.0 - exp(-response_speed * max(delta, 0.0))
		followed_lead = lerp(_camera_lead_distance_current, target_lead, follow_weight)
	if camera_lead_max_adjustment_speed > 0.0:
		followed_lead = move_toward(
			_camera_lead_distance_current,
			followed_lead,
			camera_lead_max_adjustment_speed * max(delta, 0.0)
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
	var side_sign: float = 1.0 if camera_side == CameraSide.RIGHT_OF_PATH else -1.0
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
	if camera_center_on_plane:
		var depth_error: float = (body.global_position - path_point).dot(plane_normal)
		target_position -= plane_normal * depth_error
	target_position += camera_up * camera_vertical_offset
	target_position += tangent * lead_distance

	_camera_transform = Transform3D(camera_basis, target_position)
	if is_instance_valid(_camera_constraint):
		_camera_constraint.set_locked_transform(_camera_transform)

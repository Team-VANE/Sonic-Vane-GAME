extends Node3D

enum ActivationMode {
	ALWAYS_WHILE_TARGET_ACTIVE,
	VOLUME,
	ENTRY_EXIT_AREAS,
}

enum CenterlineResponseMode {
	INHERIT,
	OVERRIDE,
	IMMEDIATE,
}

@export_category("2.5D Depth Profile")

@export_group("Setup")
## Enables this depth profile.
@export var enabled: bool = true
## 2.5D automation spline controlled by this profile. An empty path uses the parent node.
@export var automation_spline_path: NodePath = NodePath("")
## Bodies must belong to this group. An empty name accepts every compatible body.
@export var require_group: StringName = &"player"
## Higher values win when multiple active depth profiles target the same spline.
@export var priority: int = 0

@export_group("Activation")
## Selects how bodies activate and release this depth profile.
@export var activation_mode: ActivationMode = ActivationMode.VOLUME
## Area used for automatic enter and exit activation in Volume mode.
@export var area_path: NodePath = NodePath("Area3D")
## Area used to activate the profile in Entry/Exit Areas mode.
@export var entrance_area_path: NodePath = NodePath("Entrance")
## Area used to release the profile in Entry/Exit Areas mode.
@export var exit_area_path: NodePath = NodePath("Exit")
## Lets either endpoint activate or release the profile for bidirectional traversal.
@export var bidirectional_endpoint_areas: bool = true
## Releases the profile when the player exceeds this distance from its curve. Zero disables the failsafe.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var failsafe_exit_distance: float = 0.0

@export_group("Depth Curve")
## Path whose closest tracked point supplies the target depth relative to the main 2.5D ribbon.
@export var spline_path: NodePath = NodePath("Path3D")
## Additional signed depth applied to the sampled profile.
@export_range(-10000.0, 10000.0, 0.1, "suffix:m") var depth_bias: float = 0.0
## Reverses the sampled depth around the main spline centerline.
@export var reverse_depth: bool = false
## Allows the profile target to continue updating while the body is airborne.
@export var follow_while_airborne: bool = false
## Uses cubic interpolation after closest-point tracking selects a profile offset.
@export var cubic_profile_sampling: bool = true

@export_group("Adherence")
## Selects whether this profile inherits, overrides, or bypasses adaptive centerline smoothing.
@export var centerline_response_mode: CenterlineResponseMode = CenterlineResponseMode.INHERIT
## Centerline response speed used in Override mode. Zero follows the profile immediately.
@export_range(0.0, 1000.0, 0.1, "or_greater") var centerline_strength: float = 40.0
## Maximum centerline movement speed used in Override mode. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var centerline_max_speed: float = 40.0
## Uses this profile's centerline offset limit instead of the main 2.5D spline limit.
@export var override_centerline_offset_limit: bool = false
## Maximum absolute profile offset when its limit override is enabled. Zero removes the limit.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var centerline_max_offset: float = 0.0
## Minimum main-section adherence applied while this profile is active.
@export_range(0.0, 1.0, 0.01) var minimum_constraint_adherence: float = 0.0
## Uses this profile's position constraint settings instead of the main 2.5D spline settings.
@export var override_position_constraint: bool = false
## Snaps final sideways error to the active profile plane at full adherence.
@export var strict_position_lock: bool = true
## Position response speed used when Override Position Constraint is enabled.
@export_range(0.0, 1000.0, 0.1, "or_greater") var position_lock_strength: float = 40.0
## Maximum position correction speed used when Override Position Constraint is enabled. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m/s") var max_position_correction_speed: float = 0.0
## Position error ignored outside the strict core when Override Position Constraint is enabled.
@export_range(0.0, 1.0, 0.001, "or_greater", "suffix:m") var position_lock_deadzone: float = 0.005

@export_group("Progress Tracking")
## Arc-length neighborhood used to remain on the current profile branch. Zero disables local tracking.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var preferred_offset_window: float = 12.0
## Expands the profile tracking window by body travel since the previous sample.
@export var speed_adaptive_tracking_window: bool = true
## Multiplier applied to body travel when expanding the profile tracking window.
@export_range(1.0, 10.0, 0.1, "or_greater") var tracking_window_travel_multiplier: float = 2.0
## Maximum speed-adaptive profile tracking window. Zero removes the limit.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var max_adaptive_tracking_window: float = 100.0
## Extra spatial distance allowed before tracking switches from the current neighborhood to another branch.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var branch_switch_distance_tolerance: float = 2.0
## Distance from the current neighborhood that permits global closest-point recovery. Zero disables recovery.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var tracking_recovery_distance: float = 20.0

var _target_spline: Node = null
var _path: Path3D = null
var _area: Area3D = null
var _entrance_area: Area3D = null
var _exit_area: Area3D = null
var _activation_configured: bool = false
var _active_bodies: Array[Node3D] = []
var _body_progress: Dictionary = {}


func _ready() -> void:
	add_to_group(&"automation_25d_depth_profiles")
	_target_spline = _resolve_target_spline()
	_path = get_node_or_null(spline_path) as Path3D
	if _target_spline == null:
		push_warning("%s: A target 2.5D automation spline is required." % name)
	if _path == null:
		push_warning("%s: A depth profile Path3D is required." % name)
	_configure_activation()


func _resolve_target_spline() -> Node:
	if automation_spline_path != NodePath(""):
		return get_node_or_null(automation_spline_path)
	return get_parent()


func _resolve_area(path: NodePath) -> Area3D:
	if path == NodePath(""):
		return null
	return get_node_or_null(path) as Area3D


func _configure_area(area: Area3D) -> void:
	if area != null:
		area.monitoring = true


func _configure_activation() -> void:
	match activation_mode:
		ActivationMode.ALWAYS_WHILE_TARGET_ACTIVE:
			_activation_configured = true
		ActivationMode.VOLUME:
			_area = _resolve_area(area_path)
			_activation_configured = _area != null
			if not _activation_configured:
				push_warning("%s: Volume activation requires an Area3D." % name)
				return
			_configure_area(_area)
			if not _area.body_entered.is_connected(_on_body_entered):
				_area.body_entered.connect(_on_body_entered)
			if not _area.body_exited.is_connected(_on_body_exited):
				_area.body_exited.connect(_on_body_exited)
		ActivationMode.ENTRY_EXIT_AREAS:
			_entrance_area = _resolve_area(entrance_area_path)
			_exit_area = _resolve_area(exit_area_path)
			_activation_configured = (
				_entrance_area != null
				and _exit_area != null
				and _entrance_area != _exit_area
			)
			if not _activation_configured:
				push_warning("%s: Entry/Exit Areas mode requires distinct entrance and exit Area3D nodes." % name)
				return
			_configure_area(_entrance_area)
			_configure_area(_exit_area)
			if bidirectional_endpoint_areas:
				if not _entrance_area.body_entered.is_connected(_on_endpoint_area_entered):
					_entrance_area.body_entered.connect(_on_endpoint_area_entered)
				if not _exit_area.body_entered.is_connected(_on_endpoint_area_entered):
					_exit_area.body_entered.connect(_on_endpoint_area_entered)
			else:
				if not _entrance_area.body_entered.is_connected(_on_body_entered):
					_entrance_area.body_entered.connect(_on_body_entered)
				if not _exit_area.body_entered.is_connected(_on_exit_area_entered):
					_exit_area.body_entered.connect(_on_exit_area_entered)


func _is_valid_body(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return require_group == &"" or body.is_in_group(require_group)


func _activate_body(body: Node3D) -> void:
	if not enabled or not _is_valid_body(body):
		return
	if not _active_bodies.has(body):
		_active_bodies.append(body)


func _deactivate_body(body: Node3D) -> void:
	_active_bodies.erase(body)
	if body != null and is_instance_valid(body):
		_body_progress.erase(body.get_instance_id())


func _on_body_entered(body: Node3D) -> void:
	_activate_body(body)


func _on_body_exited(body: Node3D) -> void:
	_deactivate_body(body)


func _on_exit_area_entered(body: Node3D) -> void:
	if _active_bodies.has(body):
		_deactivate_body(body)


func _on_endpoint_area_entered(body: Node3D) -> void:
	if _active_bodies.has(body):
		_deactivate_body(body)
	else:
		_activate_body(body)


func release_body_for_automation(body: Node3D, automation_spline: Node) -> void:
	if automation_spline == _target_spline:
		_deactivate_body(body)


func _is_target_active_for_body(body: Node3D, automation_spline: Node) -> bool:
	if automation_spline != _target_spline:
		return false
	if automation_spline.has_method("is_body_active_for_25d"):
		return bool(automation_spline.call("is_body_active_for_25d", body))
	return true


func _physics_process(_delta: float) -> void:
	if not enabled:
		_active_bodies.clear()
		_body_progress.clear()
		return
	for index: int in range(_active_bodies.size() - 1, -1, -1):
		var body: Node3D = _active_bodies[index]
		if body == null or not is_instance_valid(body):
			_active_bodies.remove_at(index)


func _get_closest_profile_state(
	curve: Curve3D,
	local_position: Vector3,
	preferred_offset: float,
	tracking_window: float
) -> Dictionary:
	var points: PackedVector3Array = curve.get_baked_points()
	var point_count: int = points.size()
	if point_count == 0:
		return {}
	if point_count == 1:
		return {
			"offset": 0.0,
			"point": points[0],
			"distance_squared": points[0].distance_squared_to(local_position),
		}

	var curve_length: float = max(curve.get_baked_length(), 0.0)
	var window: float = max(tracking_window, 0.0)
	var use_preferred: bool = preferred_offset >= 0.0 and window > 0.0
	var preferred: float = clamp(preferred_offset, 0.0, curve_length) if use_preferred else 0.0
	var best_distance_squared: float = INF
	var best_offset: float = 0.0
	var best_point: Vector3 = points[0]
	var local_distance_squared: float = INF
	var local_offset: float = 0.0
	var local_point: Vector3 = points[0]
	var local_found: bool = false
	var distance_accumulated: float = 0.0

	for index: int in range(point_count - 1):
		var start: Vector3 = points[index]
		var finish: Vector3 = points[index + 1]
		var segment: Vector3 = finish - start
		var segment_length_squared: float = segment.length_squared()
		var segment_length: float = sqrt(segment_length_squared)
		var segment_weight: float = 0.0
		if segment_length_squared > 0.000001:
			segment_weight = clamp((local_position - start).dot(segment) / segment_length_squared, 0.0, 1.0)
		var candidate: Vector3 = start + segment * segment_weight
		var candidate_distance_squared: float = candidate.distance_squared_to(local_position)
		var candidate_offset: float = distance_accumulated + segment_length * segment_weight
		if candidate_distance_squared < best_distance_squared:
			best_distance_squared = candidate_distance_squared
			best_offset = candidate_offset
			best_point = candidate
		if use_preferred and abs(candidate_offset - preferred) <= window:
			if candidate_distance_squared < local_distance_squared:
				local_distance_squared = candidate_distance_squared
				local_offset = candidate_offset
				local_point = candidate
				local_found = true
		distance_accumulated += segment_length

	if use_preferred and local_found:
		var local_distance: float = sqrt(max(local_distance_squared, 0.0))
		var best_distance: float = sqrt(max(best_distance_squared, 0.0))
		var switch_distance: float = best_distance + max(branch_switch_distance_tolerance, 0.0)
		var recovery_distance: float = max(tracking_recovery_distance, 0.0)
		if (
			local_distance <= switch_distance
			or (recovery_distance > 0.0 and local_distance <= recovery_distance)
		):
			return {
				"offset": local_offset,
				"point": local_point,
				"distance_squared": local_distance_squared,
			}
	return {
		"offset": best_offset,
		"point": best_point,
		"distance_squared": best_distance_squared,
	}


func get_depth_offset_target(
	body: Node3D,
	automation_spline: Node,
	main_path_point: Vector3,
	main_plane_normal: Vector3
) -> Dictionary:
	if (
		not enabled
		or not _activation_configured
		or _path == null
		or _path.curve == null
		or not _is_valid_body(body)
		or not _is_target_active_for_body(body, automation_spline)
	):
		return {}
	if activation_mode == ActivationMode.ALWAYS_WHILE_TARGET_ACTIVE:
		_activate_body(body)
	elif not _active_bodies.has(body):
		return {}

	var body_id: int = body.get_instance_id()
	var body_local: Vector3 = _path.to_local(body.global_position)
	var preferred_offset: float = -1.0
	var previous_local: Vector3 = body_local
	var stored_progress: Variant = _body_progress.get(body_id, -1.0)
	if stored_progress is Dictionary:
		var progress_state: Dictionary = stored_progress as Dictionary
		preferred_offset = float(progress_state.get("offset", -1.0))
		previous_local = progress_state.get("local_position", body_local) as Vector3
	else:
		preferred_offset = float(stored_progress)
	var tracking_window: float = max(preferred_offset_window, 0.0)
	if speed_adaptive_tracking_window:
		var traveled_distance: float = previous_local.distance_to(body_local)
		tracking_window = max(
			tracking_window,
			traveled_distance * max(tracking_window_travel_multiplier, 1.0)
		)
		if max_adaptive_tracking_window > 0.0:
			tracking_window = min(tracking_window, max_adaptive_tracking_window)
	var closest_state: Dictionary = _get_closest_profile_state(
		_path.curve,
		body_local,
		preferred_offset,
		tracking_window
	)
	if closest_state.is_empty():
		return {}
	var closest_offset: float = float(closest_state.get("offset", 0.0))
	var closest_local: Vector3 = closest_state.get("point", body_local) as Vector3
	if cubic_profile_sampling:
		closest_local = _path.curve.sample_baked(closest_offset, true)
	var closest_world: Vector3 = _path.to_global(closest_local)
	var profile_distance: float = body.global_position.distance_to(closest_world)
	if failsafe_exit_distance > 0.0 and profile_distance > failsafe_exit_distance:
		_deactivate_body(body)
		return {}

	_body_progress[body_id] = {
		"offset": closest_offset,
		"local_position": body_local,
	}
	var target_offset: float = (closest_world - main_path_point).dot(main_plane_normal)
	if reverse_depth:
		target_offset = -target_offset
	target_offset += depth_bias
	return {
		"found": true,
		"offset": target_offset,
		"priority": priority,
		"allow_airborne": follow_while_airborne,
		"profile_distance": profile_distance,
		"centerline_response_mode": int(centerline_response_mode),
		"centerline_strength": centerline_strength,
		"centerline_max_speed": centerline_max_speed,
		"override_centerline_offset_limit": override_centerline_offset_limit,
		"centerline_max_offset": centerline_max_offset,
		"minimum_constraint_adherence": minimum_constraint_adherence,
		"override_position_constraint": override_position_constraint,
		"strict_position_lock": strict_position_lock,
		"position_lock_strength": position_lock_strength,
		"max_position_correction_speed": max_position_correction_speed,
		"position_lock_deadzone": position_lock_deadzone,
	}

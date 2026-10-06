extends Node3D

@export_category("Automation Spline")

@export_group("Setup")
## Enables activation and movement influence.
@export var enabled: bool = true
## Bodies must belong to this group. An empty name accepts every compatible body.
@export var require_group: StringName = &"player"
## Higher values win when automation spline volumes overlap.
@export var priority: int = 0

@export_group("Activation")
## Area used for enter and exit detection when separate trigger areas are disabled.
@export var area_path: NodePath = NodePath("Area3D")
## Uses dedicated entrance and exit areas instead of the main activation area.
@export var use_entrance_exit_areas: bool = false
## Area entered to activate the spline. Defaults to a child named Entrance.
@export var entrance_area_path: NodePath = NodePath("")
## Area entered to deactivate the spline. Defaults to a child named Exit.
@export var exit_area_path: NodePath = NodePath("")
## Maximum distance from the path before separate-trigger activation is released. Zero disables the failsafe.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var failsafe_exit_distance: float = 0.0

@export_group("Path Tracking")
## Path that supplies the automation curve.
@export var spline_path: NodePath = NodePath("Path3D")
## Distance sampled ahead of the closest point when calculating the route tangent.
@export_range(0.01, 100.0, 0.01, "or_greater", "suffix:m") var tangent_lookahead: float = 0.5
## Arc-length window used to keep tracking on the current branch where path segments overlap. Zero disables it.
@export_range(0.0, 200.0, 0.1, "or_greater", "suffix:m") var preferred_offset_window: float = 6.0

@export_group("Player Alignment")
## Limits automation influence and control locks to grounded movement.
@export var grounded_only: bool = true
## Rotates player movement intent toward the route tangent.
@export var align_player_rotation: bool = true
## Keeps the player adhered across surface-launch detaches and sharp contact transitions while active.
@export var force_surface_adhesion: bool = false
## Maximum guided steering rate. Zero leaves the player's turn curve unrestricted.
@export_range(0.0, 3600.0, 1.0, "or_greater", "suffix:deg/s") var max_turn_deg_per_sec: float = 240.0

@export_group("Control Locks")
## Legacy option: when true, locks movement, actions, and drift together.
@export var lock_controls: bool = false
## Ignores movement input while the automation spline is active.
@export var lock_movement: bool = false
## Ignores jump, spindash, and ability action input while active.
@export var lock_actions: bool = false
## Ignores drift input while the automation spline is active.
@export var lock_drift: bool = false

@export_group("Guided Centering")
## Continuously applies path-centering acceleration.
@export var continuous_force: bool = true
## Base path-centering acceleration.
@export var nudge_toward_strength_base: float = 3.0
## Additional path-centering acceleration per unit of player speed.
@export var nudge_toward_strength_per_speed: float = 0.035
## Maximum distance where centering applies. Zero gives it unlimited range.
@export_range(0.0, 200.0) var nudge_radius: float = 0.0
## Per-second strength for removing velocity perpendicular to the route tangent. Zero disables it.
@export_range(0.0, 200.0) var tangent_snap_strength: float = 0.0

@export_group("Along-Path Assist")
## Accelerates the player along the path toward the target speed.
@export var along_assist_enabled: bool = true
## Target speed for along-path acceleration and the legacy automation soft speed cap.
@export var along_assist_target_speed: float = 35.0
## Acceleration used to approach the target speed.
@export var along_assist_accel: float = 18.0

@export_group("Physics Overrides")
## Ignores water slowdown and vertical water limits while on this spline.
@export var ignore_water_physics_multipliers: bool = false
## If true, overrides the player's maximum speed while this spline is influencing them.
@export var override_player_max_speed: bool = false
## Maximum player speed used while override_player_max_speed is enabled.
@export_range(0.0, 1000.0) var player_max_speed_override: float = 320.0

var _area: Area3D = null
var _path: Path3D = null
var _enter_area: Area3D = null
var _exit_area: Area3D = null
var _activation_configured: bool = false
var _bodies: Array[Node3D] = []
var _body_offsets: Dictionary = {}


func _ready() -> void:
	_path = get_node_or_null(spline_path) as Path3D
	_area = _resolve_area(area_path)

	if use_entrance_exit_areas:
		_enter_area = _resolve_area(entrance_area_path, NodePath("Entrance"))
		_exit_area = _resolve_area(exit_area_path, NodePath("Exit"))
		_activation_configured = _enter_area != null and _exit_area != null and _enter_area != _exit_area
		if not _activation_configured:
			push_warning("%s: Separate entrance and exit Area3D nodes are required and must be distinct." % name)
			return
		_configure_trigger_area(_enter_area)
		_configure_trigger_area(_exit_area)
		if not _enter_area.body_entered.is_connected(_on_body_entered):
			_enter_area.body_entered.connect(_on_body_entered)
		if not _exit_area.body_entered.is_connected(_on_exit_area_entered):
			_exit_area.body_entered.connect(_on_exit_area_entered)
		return

	_activation_configured = _area != null
	if not _activation_configured:
		push_warning("%s: Activation Area3D was not found." % name)
		return
	_configure_trigger_area(_area)
	if not _area.body_entered.is_connected(_on_body_entered):
		_area.body_entered.connect(_on_body_entered)
	if not _area.body_exited.is_connected(_on_body_exited):
		_area.body_exited.connect(_on_body_exited)


func _resolve_area(path: NodePath, fallback_path: NodePath = NodePath("")) -> Area3D:
	var node: Node = null
	if path != NodePath(""):
		node = get_node_or_null(path)
	if node == null and fallback_path != NodePath(""):
		node = get_node_or_null(fallback_path)
	while node != null:
		if node is Area3D:
			return node as Area3D
		node = node.get_parent()
	return null


func _configure_trigger_area(area: Area3D) -> void:
	if area == null:
		return
	if use_entrance_exit_areas and _area != null and (area.collision_mask == 0 or area.collision_mask == 1):
		area.collision_mask = _area.collision_mask
	area.monitoring = true


func _on_body_entered(body: Node3D) -> void:
	if not enabled:
		return
	if not _is_valid_body(body):
		return
	if not _bodies.has(body):
		_bodies.append(body)


func _on_body_exited(body: Node3D) -> void:
	if body != null and is_instance_valid(body) and _bodies.has(body):
		_deactivate_body(body)


func _on_exit_area_entered(body: Node3D) -> void:
	if body != null and is_instance_valid(body) and _bodies.has(body):
		_deactivate_body(body)


func _is_valid_body(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return require_group == &"" or body.is_in_group(require_group)


func _deactivate_body(body: Node3D) -> void:
	_bodies.erase(body)
	_body_offsets.erase(body.get_instance_id())


func _clear_bodies() -> void:
	_bodies.clear()
	_body_offsets.clear()


func _remove_invalid_bodies() -> void:
	var active_ids: Dictionary = {}
	for index: int in range(_bodies.size() - 1, -1, -1):
		var body: Node3D = _bodies[index]
		if body == null or not is_instance_valid(body):
			_bodies.remove_at(index)
			continue
		active_ids[body.get_instance_id()] = true
	for body_id: Variant in _body_offsets.keys():
		if not active_ids.has(body_id):
			_body_offsets.erase(body_id)


func _is_beyond_failsafe(body: Node3D, curve: Curve3D) -> bool:
	if not use_entrance_exit_areas or failsafe_exit_distance <= 0.0:
		return false
	var body_local: Vector3 = _path.to_local(body.global_position)
	var closest_local: Vector3 = curve.get_closest_point(body_local)
	var closest_world: Vector3 = _path.to_global(closest_local)
	return body.global_position.distance_to(closest_world) > failsafe_exit_distance


func _physics_process(_delta: float) -> void:
	if not enabled:
		_clear_bodies()
		return
	if not _activation_configured or _path == null or _path.curve == null:
		return

	_remove_invalid_bodies()
	var curve: Curve3D = _path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.001:
		return

	for index: int in range(_bodies.size() - 1, -1, -1):
		var body: Node3D = _bodies[index]
		if _is_beyond_failsafe(body, curve):
			_deactivate_body(body)

	for body: Node3D in _bodies:
		if multiplayer != null and multiplayer.has_multiplayer_peer():
			if body.has_method("is_multiplayer_authority") and not body.is_multiplayer_authority():
				continue

		var body_pos: Vector3 = body.global_position
		var local: Vector3 = _path.to_local(body_pos)
		var up_world: Vector3 = Vector3.UP
		if body.has_method("get_up_vector"):
			var uv: Variant = body.call("get_up_vector")
			if uv is Vector3 and (uv as Vector3).length() > 0.001:
				up_world = (uv as Vector3).normalized()
		var up_local: Vector3 = (_path.global_transform.basis.inverse() * up_world).normalized()
		if up_local.length() < 0.001:
			up_local = Vector3.UP

		var offset: float = 0.0
		var closest_local: Vector3 = local
		var dist_sq: float = 0.0
		var preferred_offset: float = -1.0
		var furthest_offset: float = -1.0
		var previous_local: Vector3 = local
		var body_id: int = body.get_instance_id()
		if _body_offsets.has(body_id):
			var stored_progress: Variant = _body_offsets[body_id]
			if stored_progress is Dictionary:
				var progress_state: Dictionary = stored_progress as Dictionary
				preferred_offset = float(progress_state.get("offset", -1.0))
				furthest_offset = float(progress_state.get("furthest_offset", preferred_offset))
				previous_local = progress_state.get("local_position", local) as Vector3
			else:
				preferred_offset = float(stored_progress)
				furthest_offset = preferred_offset
		var max_allowed_offset: float = -1.0
		if not curve.closed and furthest_offset >= 0.0:
			var traveled_distance: float = previous_local.distance_to(local)
			var progress_margin: float = max(traveled_distance * 2.0, max(tangent_lookahead, curve.bake_interval))
			max_allowed_offset = min(furthest_offset + progress_margin, length)
		var closest_data: Dictionary = _get_closest_on_plane(curve, local, up_local, preferred_offset, max_allowed_offset)
		if closest_data.has("offset"):
			offset = float(closest_data["offset"])
		if closest_data.has("point"):
			closest_local = closest_data["point"] as Vector3
		if closest_data.has("dist_sq"):
			dist_sq = float(closest_data["dist_sq"])

		offset = clamp(offset, 0.0, length)
		if furthest_offset < 0.0:
			furthest_offset = offset
		else:
			furthest_offset = max(furthest_offset, offset)
		_body_offsets[body_id] = {
			"offset": offset,
			"furthest_offset": furthest_offset,
			"local_position": local,
		}
		var closest_world: Vector3 = _path.to_global(closest_local)

		var ahead: float = min(offset + max(tangent_lookahead, 0.05), length)
		var ahead_world: Vector3 = _path.to_global(curve.sample_baked(ahead))
		var tangent: Vector3 = ahead_world - closest_world
		if tangent.length() < 0.001:
			continue
		tangent = tangent.normalized()

		var toward: Vector3 = closest_world - body_pos
		if toward.length() > 0.001:
			toward = toward.normalized()

		var speed: float = 0.0
		if body.has_method("get"):
			var v: Variant = body.get("velocity")
			if v is Vector3:
				speed = (v as Vector3).length()

		var toward_strength: float = nudge_toward_strength_base + speed * nudge_toward_strength_per_speed
		toward_strength = max(toward_strength, 0.0)
		if nudge_radius > 0.0:
			var dist: float = sqrt(max(dist_sq, 0.0))
			if dist >= nudge_radius:
				toward = Vector3.ZERO
				toward_strength = 0.0
			elif nudge_radius > 0.001:
				var radius_scale: float = 1.0 - (dist / nudge_radius)
				toward_strength *= radius_scale

		var lock_movement_effective: bool = lock_movement or lock_controls
		var lock_actions_effective: bool = lock_actions or lock_controls
		var lock_drift_effective: bool = lock_drift or lock_controls

		if body.has_method("set_automation_spline"):
			body.call(
				"set_automation_spline",
				tangent,
				toward,
				toward_strength,
				max_turn_deg_per_sec,
				lock_controls,
				continuous_force,
				align_player_rotation,
				grounded_only,
				force_surface_adhesion,
				tangent_snap_strength,
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


func _get_closest_on_plane(
	curve: Curve3D,
	local_pos: Vector3,
	up_local: Vector3,
	preferred_offset: float,
	max_allowed_offset: float = -1.0
) -> Dictionary:
	var points: PackedVector3Array = curve.get_baked_points()
	var count: int = points.size()
	if count == 0:
		return {"offset": 0.0, "point": local_pos, "dist_sq": 0.0}
	if count == 1:
		var delta_single: Vector3 = points[0] - local_pos
		delta_single -= up_local * delta_single.dot(up_local)
		return {"offset": 0.0, "point": points[0], "dist_sq": delta_single.length_squared()}

	var length: float = max(curve.get_baked_length(), 0.0)
	var best_dist_sq: float = 1.0e30
	var best_pref_delta: float = 1.0e30
	var best_offset: float = 0.0
	var best_point: Vector3 = points[0]
	var best_window_dist_sq: float = 1.0e30
	var best_window_pref_delta: float = 1.0e30
	var best_window_offset: float = 0.0
	var best_window_point: Vector3 = points[0]
	var best_window_found: bool = false
	var dist_accum: float = 0.0
	var prefer: bool = preferred_offset >= 0.0 and length > 0.0
	var use_window: bool = preferred_offset >= 0.0 and preferred_offset_window > 0.0
	var prefer_offset: float = preferred_offset
	var dist_eps: float = 0.0001
	var is_closed: bool = curve.closed
	var window: float = max(preferred_offset_window, 0.0)

	if prefer:
		prefer_offset = clamp(preferred_offset, 0.0, length)

	for i: int in range(count - 1):
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var seg: Vector3 = p1 - p0
		var seg_len: float = seg.length()
		if seg_len < 0.0001:
			continue
		var seg_flat: Vector3 = seg - up_local * seg.dot(up_local)
		var seg_flat_len_sq: float = seg_flat.length_squared()
		var t: float = 0.0
		if seg_flat_len_sq > 0.000001:
			var to_point: Vector3 = local_pos - p0
			var to_point_flat: Vector3 = to_point - up_local * to_point.dot(up_local)
			t = clamp(to_point_flat.dot(seg_flat) / seg_flat_len_sq, 0.0, 1.0)
		if max_allowed_offset >= 0.0:
			if dist_accum > max_allowed_offset:
				break
			t = min(t, clamp((max_allowed_offset - dist_accum) / seg_len, 0.0, 1.0))
		var candidate: Vector3 = p0 + seg * t
		var delta: Vector3 = candidate - local_pos
		delta -= up_local * delta.dot(up_local)
		var dist_sq: float = delta.length_squared()
		var offset_candidate: float = dist_accum + seg_len * t
		var pref_delta: float = 0.0
		if prefer:
			pref_delta = abs(offset_candidate - prefer_offset)
			if is_closed:
				pref_delta = min(pref_delta, max(length - pref_delta, 0.0))

		if dist_sq < best_dist_sq - dist_eps:
			best_dist_sq = dist_sq
			best_pref_delta = pref_delta
			best_offset = offset_candidate
			best_point = candidate
		elif abs(dist_sq - best_dist_sq) <= dist_eps and prefer and pref_delta < best_pref_delta:
			best_pref_delta = pref_delta
			best_offset = offset_candidate
			best_point = candidate

		if use_window:
			if pref_delta <= window:
				if dist_sq < best_window_dist_sq - dist_eps:
					best_window_dist_sq = dist_sq
					best_window_pref_delta = pref_delta
					best_window_offset = offset_candidate
					best_window_point = candidate
					best_window_found = true
				elif abs(dist_sq - best_window_dist_sq) <= dist_eps and prefer and pref_delta < best_window_pref_delta:
					best_window_pref_delta = pref_delta
					best_window_offset = offset_candidate
					best_window_point = candidate
					best_window_found = true
		dist_accum += seg_len

	if use_window and best_window_found and best_window_dist_sq <= best_dist_sq + 0.0625:
		return {"offset": best_window_offset, "point": best_window_point, "dist_sq": best_window_dist_sq}
	return {"offset": best_offset, "point": best_point, "dist_sq": best_dist_sq}

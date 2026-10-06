@tool
extends Node3D

@export_group("Rail")
@export var active: bool = true
@export var require_group: StringName = "player"
## Spline used for grinding and rail-up sampling.
@export var path: Path3D
@export var allow_jump_exit: bool = true
@export var align_model: bool = true
@export var align_to_path_tilt: bool = true
@export var allow_reverse: bool = true
@export var allow_input_reverse: bool = false
@export_range(0.0, 2.0) var end_detach_distance: float = 0.05
@export_enum("AutoFromVelocity", "Forward", "Backward")
var entry_direction_mode: int = 0
@export_range(0.0, 200.0) var min_speed: float = 0.0
@export var lock_speed_enabled: bool = false
@export_range(0.0, 400.0) var lock_speed_value: float = 40.0
@export_range(0.0, 4.0) var gravity_scale: float = 1.0
@export_range(0.0, 4.0) var player_height_offset: float = 0.9
@export_range(0.0, 60.0) var reverse_speed_threshold: float = 6.0
@export_range(0.0, 60.0) var reverse_boost_speed: float = 6.0
@export var movement_lock_time: float = 0.0
@export var action_lock_time: float = 0.0
## Replaces prior action, movement, and spring alignment locks when grinding starts.
@export var override_previous_lock_timers: bool = true
@export_subgroup("Path Interval")
## Applies this interval to the rail spline bake and path mesh.
@export var override_path_interval: bool = true:
	set(value):
		override_path_interval = value
		_sync_path_interval()
## Shared interval for the spline bake and path mesh.
@export_range(0.05, 20.0, 0.05) var path_interval: float = 3.5:
	set(value):
		path_interval = value
		_sync_path_interval()
## Uses this rail's rehit cooldown instead of the player's cooldown.
@export var override_rehit_cooldown: bool = false
## Cooldown before this rail can be attached again when override is enabled.
@export_range(0.0, 5.0, 0.01) var rehit_cooldown: float = 0.25
@export_subgroup("Endpoint Snap")
## Prevents proximity snapping beyond open rail endpoints.
@export var prevent_endpoint_attachment_past_ends: bool = true
@export_subgroup("Entry Momentum")
@export_range(0.0, 200.0) var entry_head_on_speed_min: float = 6.0
@export_range(0.0, 1.0) var entry_head_on_tangent_ratio_max: float = 0.2

@export_group("Surface Handoff")
## Attempts a surface handoff at open endpoints and on contact during grinding.
@export var surface_handoff_enabled: bool = true
## Extra search distance below normal ground clearance at endpoints and collision exits.
@export_range(0.0, 100.0, 0.05, "or_greater", "suffix:m") var surface_handoff_search_length: float = 2.0
## Maximum angle between rail-up and the receiving surface normal.
@export_range(0.0, 89.0, 1.0, "suffix:deg") var surface_handoff_max_angle_deg: float = 25.0

@export_group("Editor Up Vectors")
## Displays rail-up arrows along the spline in the editor only.
@export var show_up_vectors: bool = true
## Distance between editor up-vector arrows along the spline.
@export_range(0.25, 100.0, 0.25, "or_greater", "suffix:m") var up_vector_spacing: float = 5.0
## Length of each editor up-vector arrow.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m") var up_vector_length: float = 2.0

@export_group("Homing Attack")
## Enables homing attack targeting for this rail.
@export var homing_target_enabled: bool = true
## Extra speed used when entering the rail from a homing attack.
@export_range(0.0, 200.0) var homing_entry_min_speed: float = 60.0

@export_group("Visuals")
@export var update_visual: bool = true
@export var rail_mesh: Mesh
@export var rail_material: Material

## Transient editor mesh for spline up-vector arrows.
var _up_vector_preview: MeshInstance3D
var _up_vector_signature: Array = []
var _up_vector_curve: Curve3D
var _up_vectors_dirty: bool = true

var _body_cooldowns: Dictionary = {}
var _path_visual: Node3D
var _collision_node: Node3D
var _path_targeting_world_points: PackedVector3Array = PackedVector3Array()
var _path_targeting_offsets: PackedFloat32Array = PackedFloat32Array()
var _path_world_aabb: AABB = AABB()
var _path_targeting_cache_valid: bool = false


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	set_physics_process(false)
	if Engine.is_editor_hint():
		_clear_editor_runtime_metadata()
		return
	if not is_in_group("Rail"):
		add_to_group("Rail")
	if path == null:
		path = get_node_or_null("Path3D")

	_path_visual = get_node_or_null("PathMesh")
	if _path_visual == null:
		_path_visual = get_node_or_null("RailMesh")
	if _path_visual == null:
		_path_visual = get_node_or_null("CSGPolygon3D")
	if _path_visual:
		_collision_node = _path_visual
		_collision_node.set_meta("rail_node", self)

	_sync_path_interval()

	if update_visual:
		_update_path_visual()

	if Engine.is_editor_hint():
		return

	_set_homing_target_registered(homing_target_enabled)
	_set_rail_spatial_registered(true)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_set_homing_target_registered(false)
	_set_rail_spatial_registered(false)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _body_cooldowns.is_empty():
		return

	var to_remove: Array = []
	for id in _body_cooldowns.keys():
		_body_cooldowns[id] -= delta
		if _body_cooldowns[id] <= 0.0:
			to_remove.append(id)

	for id in to_remove:
		_body_cooldowns.erase(id)
	if _body_cooldowns.is_empty():
		set_physics_process(false)


func try_start_with_body(body, override_velocity = null, override_origin = null) -> void:
	if not active:
		return

	if require_group != "" and not body.is_in_group(require_group):
		return

	if not body.has_method("start_rail_grind"):
		return
	if body.has_method("can_start_rail_grind") and not bool(body.call("can_start_rail_grind")):
		return

	if path == null or path.curve == null:
		push_warning("%s: Rail has no Path3D or curve." % name)
		return

	var id: int = body.get_instance_id()
	var remaining = _body_cooldowns.get(id, 0.0)
	if remaining > 0.0:
		return

	var session_params := _build_session_params(body, override_velocity, override_origin)
	if session_params.is_empty():
		return

	body.start_rail_grind(session_params)
	_body_cooldowns[id] = _get_rehit_cooldown(body)
	set_physics_process(true)


func try_start_with_body_proximity(
	body,
	snap_radius: float,
	override_velocity = null,
	override_origin = null,
	precomputed_candidate: Dictionary = {}
) -> bool:
	if snap_radius <= 0.0:
		return false
	if not active:
		return false
	if body == null or not is_instance_valid(body):
		return false
	if not (body is Node3D):
		return false
	if require_group != "" and not body.is_in_group(require_group):
		return false
	if not body.has_method("start_rail_grind"):
		return false
	if body.has_method("can_start_rail_grind") and not bool(body.call("can_start_rail_grind")):
		return false
	if path == null or path.curve == null:
		return false

	var id: int = body.get_instance_id()
	var remaining: float = float(_body_cooldowns.get(id, 0.0))
	if remaining > 0.0:
		return false

	var query_pos: Vector3 = (body as Node3D).global_position
	if override_origin is Vector3:
		query_pos = override_origin
	var candidate: Dictionary = precomputed_candidate
	if candidate.is_empty():
		candidate = get_path_snap_candidate(query_pos, query_pos)
	if candidate.is_empty():
		return false
	if not candidate.has("point") or not (candidate["point"] is Vector3):
		return false
	if not candidate.has("distance_squared"):
		return false
	var closest_point: Vector3 = candidate["point"]
	var distance_squared: float = float(candidate["distance_squared"])
	if distance_squared > snap_radius * snap_radius:
		return false

	var session_params: Dictionary = _build_session_params(body, override_velocity, closest_point)
	if session_params.is_empty():
		return false

	body.start_rail_grind(session_params)
	_body_cooldowns[id] = _get_rehit_cooldown(body)
	set_physics_process(true)
	return true


func _set_homing_target_registered(registered: bool) -> void:
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if registered:
		if not is_in_group("HomingTarget"):
			add_to_group("HomingTarget")
		if mgr and mgr.has_method("register"):
			mgr.register(self)
		return
	if is_in_group("HomingTarget"):
		remove_from_group("HomingTarget")
	if mgr and mgr.has_method("unregister"):
		mgr.unregister(self)


func _set_rail_spatial_registered(registered: bool) -> void:
	var manager: Node = get_node_or_null("/root/HomingTargetManager")
	if manager == null:
		return
	if registered and manager.has_method("register_rail"):
		manager.call("register_rail", self)
	elif not registered and manager.has_method("unregister_rail"):
		manager.call("unregister_rail", self)


func get_homing_manager_positions(sample_spacing: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if path == null or path.curve == null:
		positions.append(global_position)
		return positions

	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.01:
		positions.append(global_position)
		return positions

	var baked_points: PackedVector3Array = curve.get_baked_points()
	if baked_points.size() >= 2:
		for point_index in range(baked_points.size()):
			var local_point: Vector3 = baked_points[point_index]
			positions.append(path.to_global(local_point))
	else:
		var spacing: float = max(min(sample_spacing * 0.25, 8.0), 1.0)
		var steps: int = max(int(ceil(length / spacing)), 1)
		for step_index in range(steps + 1):
			var t: float = float(step_index) / float(steps)
			var offset: float = length * t
			positions.append(path.to_global(curve.sample_baked(offset)))
	return positions


func get_homing_target_position(origin: Vector3) -> Vector3:
	if path == null or path.curve == null:
		return global_position

	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.01:
		return global_position

	var offset: float = _find_closest_offset_on_path(origin, curve, length)
	return path.to_global(curve.sample_baked(offset))


func get_closest_point_on_path(origin: Vector3) -> Vector3:
	if path == null or path.curve == null:
		return global_position

	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.01:
		return global_position

	var offset: float = _find_closest_offset_on_path(origin, curve, length)
	return path.to_global(curve.sample_baked(offset))


func get_path_world_aabb() -> AABB:
	if path == null or path.curve == null:
		return AABB(global_position, Vector3.ZERO)
	_ensure_path_targeting_cache()
	if _path_targeting_world_points.is_empty():
		return AABB(path.global_position, Vector3.ZERO)
	return _path_world_aabb


func is_path_snap_query_near(segment_from: Vector3, segment_to: Vector3, snap_radius: float) -> bool:
	var segment_min: Vector3 = segment_from.min(segment_to)
	var segment_max: Vector3 = segment_from.max(segment_to)
	var query_bounds: AABB = AABB(segment_min, segment_max - segment_min).grow(max(snap_radius, 0.0))
	return get_path_world_aabb().intersects(query_bounds)


func get_path_snap_candidate(segment_from: Vector3, segment_to: Vector3) -> Dictionary:
	var candidate: Dictionary = {}
	if path == null or path.curve == null:
		return candidate

	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.01:
		return candidate

	_ensure_path_targeting_cache()
	if _path_targeting_world_points.size() < 2:
		return candidate
	var baked_points: PackedVector3Array = curve.get_baked_points()

	var best_offset: float = 0.0
	var best_point: Vector3 = Vector3.ZERO
	var best_query: Vector3 = segment_to
	var best_dist_sq: float = INF

	for point_index: int in range(_path_targeting_world_points.size() - 1):
		var local_a: Vector3 = baked_points[point_index]
		var local_b: Vector3 = baked_points[point_index + 1]
		var rail_segment_length: float = local_a.distance_to(local_b)
		if rail_segment_length <= 0.0001:
			continue
		var rail_a: Vector3 = _path_targeting_world_points[point_index]
		var rail_b: Vector3 = _path_targeting_world_points[point_index + 1]
		var gap: Vector3 = (rail_a.min(rail_b) - segment_from.max(segment_to)).max(
			segment_from.min(segment_to) - rail_a.max(rail_b)
		).max(Vector3.ZERO)
		if gap.length_squared() >= best_dist_sq:
			continue
		var closest: Dictionary = _get_closest_points_between_segments(rail_a, rail_b, segment_from, segment_to)
		if closest.is_empty():
			continue
		var rail_point: Vector3 = closest["rail_point"]
		var query_point: Vector3 = closest["query_point"]
		var rail_t: float = float(closest["rail_t"])
		var dist_sq: float = query_point.distance_squared_to(rail_point)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_offset = _path_targeting_offsets[point_index] + rail_segment_length * rail_t
			best_point = rail_point
			best_query = query_point

	if curve.closed:
		var local_last: Vector3 = baked_points[baked_points.size() - 1]
		var local_first: Vector3 = baked_points[0]
		var closing_length: float = local_last.distance_to(local_first)
		if closing_length > 0.0001:
			var closing_a: Vector3 = _path_targeting_world_points[_path_targeting_world_points.size() - 1]
			var closing_b: Vector3 = _path_targeting_world_points[0]
			var closing_closest: Dictionary = _get_closest_points_between_segments(closing_a, closing_b, segment_from, segment_to)
			if not closing_closest.is_empty():
				var closing_rail_point: Vector3 = closing_closest["rail_point"]
				var closing_query_point: Vector3 = closing_closest["query_point"]
				var closing_rail_t: float = float(closing_closest["rail_t"])
				var closing_dist_sq: float = closing_query_point.distance_squared_to(closing_rail_point)
				if closing_dist_sq < best_dist_sq:
					best_dist_sq = closing_dist_sq
					best_offset = min(_path_targeting_offsets[_path_targeting_offsets.size() - 1] + closing_length * closing_rail_t, length)
					best_point = closing_rail_point
					best_query = closing_query_point

	if best_dist_sq == INF:
		return {}

	if _is_path_snap_query_past_endpoint(segment_to, best_offset, length):
		return {}

	candidate["point"] = best_point
	candidate["query_point"] = best_query
	candidate["offset"] = best_offset
	candidate["distance_squared"] = best_dist_sq
	return candidate


func get_homing_target_position_for_aim(aim_origin: Vector3, aim_dir: Vector3) -> Vector3:
	if path == null or path.curve == null:
		return global_position

	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.01:
		return global_position

	var offset: float = _find_closest_offset_on_path_line(aim_origin, aim_dir, curve, length)
	return path.to_global(curve.sample_baked(offset))


func on_homing_hit(player: Node, _jump_held: bool) -> bool:
	if not homing_target_enabled:
		return false
	if not active:
		return false
	if player == null or not is_instance_valid(player):
		return false
	if not (player is Node3D):
		return false
	if require_group != "" and not player.is_in_group(require_group):
		return false
	if not player.has_method("start_rail_grind"):
		return false
	if player.has_method("can_start_rail_grind") and not bool(player.call("can_start_rail_grind")):
		return false
	if path == null or path.curve == null:
		return false

	var entry_point: Vector3 = get_homing_target_position((player as Node3D).global_position)
	if player.has_method("get_homing_attack_target_position"):
		var locked_entry_point: Variant = player.call("get_homing_attack_target_position")
		if locked_entry_point is Vector3:
			entry_point = locked_entry_point
	var entry_velocity: Vector3 = Vector3.ZERO
	if player.has_method("get_rail_entry_velocity"):
		entry_velocity = player.call("get_rail_entry_velocity")
	elif player is CharacterBody3D:
		entry_velocity = (player as CharacterBody3D).velocity
	if entry_velocity.length() < homing_entry_min_speed:
		var to_entry: Vector3 = entry_point - (player as Node3D).global_position
		if to_entry.length() > 0.001:
			entry_velocity = to_entry.normalized() * homing_entry_min_speed

	var entry_forward: Vector3 = Vector3.ZERO
	if player.has_method("get_rail_entry_forward"):
		entry_forward = player.call("get_rail_entry_forward")

	var params: Dictionary = build_session_params_for_entry(entry_point, entry_velocity, entry_forward)
	if params.is_empty():
		return false

	player.start_rail_grind(params)
	_body_cooldowns[player.get_instance_id()] = _get_rehit_cooldown(player)
	set_physics_process(true)
	return true


func refresh_cooldown(body: Node) -> void:
	if body == null:
		return
	var id: int = body.get_instance_id()
	_body_cooldowns[id] = _get_rehit_cooldown(body)
	set_physics_process(true)


func _get_rehit_cooldown(body: Node) -> float:
	if override_rehit_cooldown:
		return max(rehit_cooldown, 0.0)
	if body != null and body.has_method("get_rail_rehit_cooldown"):
		return max(float(body.call("get_rail_rehit_cooldown")), 0.0)
	return max(rehit_cooldown, 0.0)


func _build_session_params(body: Node3D, override_velocity = null, override_origin = null) -> Dictionary:
	var curve := path.curve
	if curve == null:
		return {}

	var curve_length := curve.get_baked_length()
	if curve_length <= 0.01:
		return {}

	var query_pos: Vector3 = body.global_transform.origin
	if override_origin is Vector3:
		query_pos = override_origin
	var start_offset: float = _find_closest_offset_on_path(query_pos, curve, curve_length)

	var tangent: Vector3 = _sample_tangent(start_offset, 0.05)
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD
	else:
		tangent = tangent.normalized()

	var projected_speed: float = 0.0
	var entry_velocity: Vector3 = Vector3.ZERO
	
	if override_velocity is Vector3:
		entry_velocity = override_velocity
	elif body != null and body.has_method("get_rail_entry_velocity"):
		entry_velocity = body.call("get_rail_entry_velocity")
	elif body is CharacterBody3D:
		entry_velocity = body.velocity
	
	projected_speed = entry_velocity.dot(tangent)
	
	# Radial landing speed preservation:
	# If we are entering at a shallow enough angle, preserve the full magnitude of velocity
	# to avoid speed loss from position correction or steep entry vectors.
	var entry_speed: float = entry_velocity.length()
	if entry_speed > 0.001:
		var dot_abs: float = abs(projected_speed)
		var ratio: float = dot_abs / entry_speed
		# threshold of ~45 degrees (cos(45) approx 0.707)
		if ratio > 0.707:
			projected_speed = entry_speed * (1.0 if projected_speed >= 0.0 else -1.0)

	var entry_forward := Vector3.ZERO
	if body != null and body.has_method("get_rail_entry_forward"):
		entry_forward = body.call("get_rail_entry_forward")
	
	var tangent_ratio: float = 0.0
	if entry_speed > 0.001:
		tangent_ratio = abs(projected_speed) / entry_speed
	
	var head_on: bool = entry_speed >= entry_head_on_speed_min and tangent_ratio <= entry_head_on_tangent_ratio_max
	var session_min_speed := min_speed
	var session_lock_speed_enabled := lock_speed_enabled
	var session_lock_speed_value := lock_speed_value
	var forward_dot := 0.0
	var forward_valid := false
	if entry_forward.length() > 0.001:
		forward_dot = tangent.dot(entry_forward.normalized())
		forward_valid = true
	if head_on:
		projected_speed = 0.0
		session_min_speed = 0.0
		session_lock_speed_enabled = false
		session_lock_speed_value = 0.0

	var sign := _determine_direction(projected_speed, forward_dot, forward_valid)
	projected_speed = abs(projected_speed) * sign

	if session_lock_speed_enabled:
		projected_speed = session_lock_speed_value * sign
	elif session_min_speed > 0.0:
		var mag = max(abs(projected_speed), session_min_speed)
		projected_speed = mag * (1.0 if projected_speed >= 0.0 else -1.0)

	return {
		"rail_node": self,
		"path": path,
		"start_offset": start_offset,
		"start_travel_sign": sign,
		"initial_speed": projected_speed,
		"align_model": align_model,
		"align_to_path_tilt": align_to_path_tilt,
		"allow_jump_exit": allow_jump_exit,
		"allow_reverse": allow_reverse,
		"allow_input_reverse": allow_input_reverse,
		"end_detach_distance": end_detach_distance,
		"surface_handoff_enabled": surface_handoff_enabled,
		"surface_handoff_search_length": surface_handoff_search_length,
		"surface_handoff_max_angle_deg": surface_handoff_max_angle_deg,
		"min_speed": session_min_speed,
		"lock_speed_enabled": session_lock_speed_enabled,
		"lock_speed_value": session_lock_speed_value,
		"gravity_scale": gravity_scale,
		"player_height_offset": player_height_offset,
		"reverse_speed_threshold": reverse_speed_threshold,
		"reverse_boost_speed": reverse_boost_speed,
		"movement_lock_time": movement_lock_time,
		"action_lock_time": action_lock_time,
		"override_previous_lock_timers": override_previous_lock_timers
	}


func _determine_direction(projected_speed: float, fallback_dot: float, fallback_valid: bool) -> float:
	match entry_direction_mode:
		0:
			if abs(projected_speed) > 0.1:
				return 1.0 if projected_speed >= 0.0 else -1.0
			if fallback_valid and abs(fallback_dot) > 0.05:
				return 1.0 if fallback_dot >= 0.0 else -1.0
			return 1.0
		1:
			return 1.0
		2:
			return -1.0
	return 1.0


func build_session_params_for_entry(
	entry_point: Vector3,
	entry_velocity: Vector3,
	entry_forward: Vector3 = Vector3.ZERO
) -> Dictionary:
	if path == null:
		return {}
	var curve := path.curve
	if curve == null:
		return {}

	var curve_length: float = curve.get_baked_length()
	if curve_length <= 0.01:
		return {}

	var start_offset: float = _find_closest_offset_on_path(entry_point, curve, curve_length)

	var tangent: Vector3 = _sample_tangent(start_offset, 0.05)
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD
	else:
		tangent = tangent.normalized()

	var projected_speed: float = entry_velocity.dot(tangent)
	var entry_speed: float = entry_velocity.length()

	# Radial landing speed preservation:
	# If we are entering at a shallow enough angle, preserve the full magnitude of velocity
	# to avoid speed loss from position correction or steep entry vectors.
	if entry_speed > 0.001:
		var dot_abs: float = abs(projected_speed)
		var ratio: float = dot_abs / entry_speed
		# threshold of ~45 degrees (cos(45) approx 0.707)
		if ratio > 0.707:
			projected_speed = entry_speed * (1.0 if projected_speed >= 0.0 else -1.0)

	var tangent_ratio: float = 0.0
	if entry_speed > 0.001:
		tangent_ratio = abs(projected_speed) / entry_speed

	var forward_dot: float = 0.0
	var forward_valid: bool = false
	if entry_forward.length() > 0.001:
		forward_dot = tangent.dot(entry_forward.normalized())
		forward_valid = true

	var head_on: bool = entry_speed >= entry_head_on_speed_min and tangent_ratio <= entry_head_on_tangent_ratio_max
	var session_min_speed: float = min_speed
	var session_lock_speed_enabled: bool = lock_speed_enabled
	var session_lock_speed_value: float = lock_speed_value
	if head_on:
		projected_speed = 0.0
		session_min_speed = 0.0
		session_lock_speed_enabled = false
		session_lock_speed_value = 0.0

	var sign: float = _determine_direction(projected_speed, forward_dot, forward_valid)
	projected_speed = abs(projected_speed) * sign

	if session_lock_speed_enabled:
		projected_speed = session_lock_speed_value * sign
	elif session_min_speed > 0.0:
		var mag: float = max(abs(projected_speed), session_min_speed)
		projected_speed = mag * (1.0 if projected_speed >= 0.0 else -1.0)

	return {
		"rail_node": self,
		"path": path,
		"start_offset": start_offset,
		"start_travel_sign": sign,
		"initial_speed": projected_speed,
		"align_model": align_model,
		"align_to_path_tilt": align_to_path_tilt,
		"allow_jump_exit": allow_jump_exit,
		"allow_reverse": allow_reverse,
		"allow_input_reverse": allow_input_reverse,
		"end_detach_distance": end_detach_distance,
		"surface_handoff_enabled": surface_handoff_enabled,
		"surface_handoff_search_length": surface_handoff_search_length,
		"surface_handoff_max_angle_deg": surface_handoff_max_angle_deg,
		"min_speed": session_min_speed,
		"lock_speed_enabled": session_lock_speed_enabled,
		"lock_speed_value": session_lock_speed_value,
		"gravity_scale": gravity_scale,
		"player_height_offset": player_height_offset,
		"reverse_speed_threshold": reverse_speed_threshold,
		"reverse_boost_speed": reverse_boost_speed,
		"movement_lock_time": movement_lock_time,
		"action_lock_time": action_lock_time,
		"override_previous_lock_timers": override_previous_lock_timers
	}


func _sample_tangent(offset: float, lookahead: float) -> Vector3:
	if path == null:
		return Vector3.FORWARD
	var curve: Curve3D = path.curve
	if curve == null:
		return Vector3.FORWARD

	var length: float = curve.get_baked_length()
	var ahead: float = clamp(offset + lookahead, 0.0, length)
	var behind: float = clamp(offset - lookahead, 0.0, length)
	
	# Use extra sampling range at endpoints for a stable tangent.
	if ahead - behind < 0.001:
		if ahead < length:
			ahead = min(ahead + 0.05, length)
		if behind > 0.0:
			behind = max(behind - 0.05, 0.0)

	var here: Vector3 = path.to_global(curve.sample_baked(behind))
	var there: Vector3 = path.to_global(curve.sample_baked(ahead))
	var tangent: Vector3 = there - here
	
	if tangent.length() < 0.001:
		return -path.global_transform.basis.z
	
	return tangent.normalized()


func _get_closest_points_between_segments(rail_a: Vector3, rail_b: Vector3, query_a: Vector3, query_b: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var rail_dir: Vector3 = rail_b - rail_a
	var query_dir: Vector3 = query_b - query_a
	var rail_len_sq: float = rail_dir.length_squared()
	var query_len_sq: float = query_dir.length_squared()

	if rail_len_sq <= 0.0001 and query_len_sq <= 0.0001:
		result["rail_point"] = rail_a
		result["query_point"] = query_a
		result["rail_t"] = 0.0
		return result

	if rail_len_sq <= 0.0001:
		var query_t_for_point: float = 0.0
		if query_len_sq > 0.0001:
			query_t_for_point = clamp((rail_a - query_a).dot(query_dir) / query_len_sq, 0.0, 1.0)
		result["rail_point"] = rail_a
		result["query_point"] = query_a + query_dir * query_t_for_point
		result["rail_t"] = 0.0
		return result

	if query_len_sq <= 0.0001:
		var rail_t_for_point: float = clamp((query_a - rail_a).dot(rail_dir) / rail_len_sq, 0.0, 1.0)
		result["rail_point"] = rail_a + rail_dir * rail_t_for_point
		result["query_point"] = query_a
		result["rail_t"] = rail_t_for_point
		return result

	var rail_query_dot: float = rail_dir.dot(query_dir)
	var rail_to_query: Vector3 = rail_a - query_a
	var rail_dot_delta: float = rail_dir.dot(rail_to_query)
	var query_dot_delta: float = query_dir.dot(rail_to_query)
	var denom: float = rail_len_sq * query_len_sq - rail_query_dot * rail_query_dot
	var rail_t: float = 0.0
	var query_t: float = 0.0

	if denom > 0.0001:
		rail_t = clamp((rail_query_dot * query_dot_delta - query_len_sq * rail_dot_delta) / denom, 0.0, 1.0)

	query_t = (rail_query_dot * rail_t + query_dot_delta) / query_len_sq
	if query_t < 0.0:
		query_t = 0.0
		rail_t = clamp(-rail_dot_delta / rail_len_sq, 0.0, 1.0)
	elif query_t > 1.0:
		query_t = 1.0
		rail_t = clamp((rail_query_dot - rail_dot_delta) / rail_len_sq, 0.0, 1.0)

	result["rail_point"] = rail_a + rail_dir * rail_t
	result["query_point"] = query_a + query_dir * query_t
	result["rail_t"] = rail_t
	return result


func _is_path_snap_query_past_endpoint(query_point: Vector3, offset: float, length: float) -> bool:
	if not prevent_endpoint_attachment_past_ends:
		return false
	if path == null:
		return false
	var curve: Curve3D = path.curve
	if curve == null:
		return false
	if curve.closed:
		return false
	if length <= 0.01:
		return false

	var tolerance: float = max(end_detach_distance, 0.01)
	if offset <= tolerance:
		var start_point: Vector3 = path.to_global(curve.sample_baked(0.0))
		var start_tangent: Vector3 = _sample_tangent(0.0, 0.1)
		if start_tangent.length() > 0.001:
			var start_delta: Vector3 = query_point - start_point
			if start_delta.dot(start_tangent.normalized()) < -tolerance:
				return true

	if offset >= length - tolerance:
		var end_point: Vector3 = path.to_global(curve.sample_baked(length))
		var end_tangent: Vector3 = _sample_tangent(length, 0.1)
		if end_tangent.length() > 0.001:
			var end_delta: Vector3 = query_point - end_point
			if end_delta.dot(end_tangent.normalized()) > tolerance:
				return true

	return false


func _find_closest_offset_on_path(world_point: Vector3, curve: Curve3D, total_length: float) -> float:
	if path == null or total_length <= 0.0:
		return 0.0

	var local_point = path.to_local(world_point)
	var closest_local = curve.get_closest_point(local_point)

	var steps = int(clamp(total_length / 0.5, 32.0, 2048.0))
	if steps <= 0:
		steps = 1
	var step: float = total_length / float(steps)
	var best_offset: float = 0.0
	var best_dist: float = INF
	var current_offset: float = 0.0

	for i in range(steps + 1):
		var clamped_offset: float = clamp(current_offset, 0.0, total_length)
		var sample = curve.sample_baked(clamped_offset)
		var dist = sample.distance_squared_to(closest_local)
		if dist < best_dist:
			best_dist = dist
			best_offset = clamped_offset
		current_offset += step

	var prev_offset: float = max(best_offset - step, 0.0)
	var next_offset: float = min(best_offset + step, total_length)
	var prev_point = curve.sample_baked(prev_offset)
	var next_point = curve.sample_baked(next_offset)
	var segment = next_point - prev_point
	var seg_len_sq = segment.length_squared()
	if seg_len_sq > 0.0001:
		var rel = closest_local - prev_point
		var t = clamp(rel.dot(segment) / seg_len_sq, 0.0, 1.0)
		best_offset = lerp(prev_offset, next_offset, t)

	return clamp(best_offset, 0.0, total_length)


func _find_closest_offset_on_path_line(aim_origin: Vector3, aim_dir: Vector3, curve: Curve3D, total_length: float) -> float:
	if path == null or total_length <= 0.0:
		return 0.0

	var line_dir: Vector3 = aim_dir.normalized()
	if line_dir.length() < 0.001:
		return _find_closest_offset_on_path(aim_origin, curve, total_length)

	var steps: int = int(clamp(total_length / 0.5, 32.0, 2048.0))
	if steps <= 0:
		steps = 1
	var step: float = total_length / float(steps)
	var best_offset: float = 0.0
	var best_dist: float = INF
	var current_offset: float = 0.0

	for i in range(steps + 1):
		var clamped_offset: float = clamp(current_offset, 0.0, total_length)
		var sample_world: Vector3 = path.to_global(curve.sample_baked(clamped_offset))
		var to_sample: Vector3 = sample_world - aim_origin
		var projection: float = max(to_sample.dot(line_dir), 0.0)
		var closest_on_line: Vector3 = aim_origin + line_dir * projection
		var dist: float = sample_world.distance_squared_to(closest_on_line)
		if dist < best_dist:
			best_dist = dist
			best_offset = clamped_offset
		current_offset += step

	var prev_offset: float = max(best_offset - step, 0.0)
	var next_offset: float = min(best_offset + step, total_length)
	var refine_steps: int = 12
	for refine_index in range(refine_steps + 1):
		var refine_t: float = float(refine_index) / float(refine_steps)
		var refine_offset: float = lerp(prev_offset, next_offset, refine_t)
		var refine_sample_world: Vector3 = path.to_global(curve.sample_baked(refine_offset))
		var refine_to_sample: Vector3 = refine_sample_world - aim_origin
		var refine_projection: float = max(refine_to_sample.dot(line_dir), 0.0)
		var refine_closest_on_line: Vector3 = aim_origin + line_dir * refine_projection
		var refine_dist: float = refine_sample_world.distance_squared_to(refine_closest_on_line)
		if refine_dist < best_dist:
			best_dist = refine_dist
			best_offset = refine_offset

	return clamp(best_offset, 0.0, total_length)


func _update_path_visual() -> void:
	if _path_visual == null or path == null or not is_instance_valid(path):
		return

	var relative_path := _path_visual.get_path_to(path)

	if _path_visual is MeshInstance3D:
		var mesh_instance := _path_visual as MeshInstance3D
		if rail_mesh:
			mesh_instance.mesh = rail_mesh
		if rail_material:
			mesh_instance.material_override = rail_material
	elif _path_visual is CSGPolygon3D:
		var csg := _path_visual as CSGPolygon3D
		csg.path_node = relative_path
	else:
		if _path_visual.has_method("set"):
			_path_visual.set("path", relative_path)

	_sync_path_interval()


func _sync_path_interval() -> void:
	if Engine.is_editor_hint():
		return
	if not override_path_interval:
		return

	var interval: float = max(path_interval, 0.05)
	if path == null and is_inside_tree():
		path = get_node_or_null("Path3D")
	if path != null and path.curve != null:
		path.curve.bake_interval = interval
	_rebuild_path_targeting_cache()

	if _path_visual == null and is_inside_tree():
		_path_visual = get_node_or_null("PathMesh")
		if _path_visual == null:
			_path_visual = get_node_or_null("RailMesh")
		if _path_visual == null:
			_path_visual = get_node_or_null("CSGPolygon3D")

	if _path_visual != null:
		_sync_interval_on_node(_path_visual, interval)

	for child in get_children():
		if child is Node:
			_sync_interval_on_tree(child, interval)

	if is_inside_tree() and not Engine.is_editor_hint():
		var mgr = get_node_or_null("/root/HomingTargetManager")
		if mgr and mgr.has_method("update_target"):
			mgr.update_target(self)
		if mgr and mgr.has_method("update_rail"):
			mgr.update_rail(self)


func _ensure_path_targeting_cache() -> void:
	if not _path_targeting_cache_valid:
		_rebuild_path_targeting_cache()


func _rebuild_path_targeting_cache() -> void:
	_path_targeting_world_points.clear()
	_path_targeting_offsets.clear()
	_path_targeting_cache_valid = true
	if path == null or path.curve == null:
		_path_world_aabb = AABB(global_position, Vector3.ZERO)
		return
	var baked_points: PackedVector3Array = path.curve.get_baked_points()
	if baked_points.is_empty():
		_path_world_aabb = AABB(path.global_position, Vector3.ZERO)
		return
	var cumulative_offset: float = 0.0
	for point_index: int in range(baked_points.size()):
		if point_index > 0:
			cumulative_offset += baked_points[point_index - 1].distance_to(baked_points[point_index])
		var world_point: Vector3 = path.to_global(baked_points[point_index])
		_path_targeting_world_points.append(world_point)
		_path_targeting_offsets.append(cumulative_offset)
		if point_index == 0:
			_path_world_aabb = AABB(world_point, Vector3.ZERO)
		else:
			_path_world_aabb = _path_world_aabb.expand(world_point)


func _sync_interval_on_tree(node: Node, interval: float) -> void:
	_sync_interval_on_node(node, interval)
	for child in node.get_children():
		if child is Node:
			_sync_interval_on_tree(child, interval)


func _sync_interval_on_node(node: Node, interval: float) -> void:
	if _has_object_property(node, "path_interval_type"):
		node.set("path_interval_type", 0)
	if _has_object_property(node, "path_interval"):
		node.set("path_interval", interval)


func _has_object_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func sample_path_up(rail_path: Path3D, distance: float) -> Vector3:
	var curve: Curve3D = rail_path.curve
	var length: float = curve.get_baked_length()
	var offset: float = clamp(distance, 0.0, length)
	var tangent: Vector3 = rail_path.global_basis * (
		curve.sample_baked(min(offset + 0.1, length)) - curve.sample_baked(max(offset - 0.1, 0.0)))
	tangent = tangent.normalized()
	var up: Vector3 = rail_path.global_basis.y
	if curve.up_vector_enabled:
		up = rail_path.global_basis * curve.sample_baked_up_vector(offset, true)
	up = up.slide(tangent)
	if up.length_squared() < 0.000001:
		up = rail_path.global_basis.x.slide(tangent)
	if up.length_squared() < 0.000001:
		up = Vector3.FORWARD.slide(tangent)
	up = up.normalized()
	if not curve.up_vector_enabled:
		var tilts: PackedFloat32Array = curve.get_baked_tilts()
		if not tilts.is_empty():
			var index: int = clampi(int(round(offset / max(curve.bake_interval, 0.001))), 0, tilts.size() - 1)
			up = up.rotated(tangent, tilts[index])
	return up


func _mark_up_vectors_dirty() -> void:
	_up_vectors_dirty = true


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_clear_editor_runtime_metadata()
	if not is_instance_valid(path):
		path = get_node_or_null("Path3D")
	var curve: Curve3D = path.curve if is_instance_valid(path) else null
	if curve != _up_vector_curve:
		if _up_vector_curve and _up_vector_curve.changed.is_connected(_mark_up_vectors_dirty):
			_up_vector_curve.changed.disconnect(_mark_up_vectors_dirty)
		_up_vector_curve = curve
		if curve:
			curve.changed.connect(_mark_up_vectors_dirty)
		_up_vectors_dirty = true
	var signature: Array = [show_up_vectors, up_vector_spacing, up_vector_length,
		path.global_transform if is_instance_valid(path) else Transform3D.IDENTITY, global_transform]
	if signature != _up_vector_signature:
		_up_vector_signature = signature
		_up_vectors_dirty = true
	if not _up_vectors_dirty:
		return
	_up_vectors_dirty = false
	if not show_up_vectors or not curve or curve.get_baked_length() <= 0.001:
		if is_instance_valid(_up_vector_preview):
			_up_vector_preview.visible = false
		return
	if not is_instance_valid(_up_vector_preview):
		_up_vector_preview = MeshInstance3D.new()
		_up_vector_preview.name = "RailUpVectors"
		_up_vector_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_up_vector_preview, false, Node.INTERNAL_MODE_BACK)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.2, 1.0, 0.35)
		material.no_depth_test = true
		_up_vector_preview.material_override = material
	_up_vector_preview.visible = true
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var length: float = curve.get_baked_length()
	var steps: int = clampi(int(ceil(length / max(up_vector_spacing, 0.25))), 1, 2048)
	for index: int in range(steps + 1):
		var offset: float = length * float(index) / float(steps)
		var origin: Vector3 = path.to_global(curve.sample_baked(offset))
		var up: Vector3 = sample_path_up(path, offset)
		var tip: Vector3 = origin + up * up_vector_length
		var side: Vector3 = up.cross(Vector3.FORWARD).normalized()
		if side.length_squared() < 0.001:
			side = up.cross(Vector3.RIGHT).normalized()
		var head_base: Vector3 = tip - up * up_vector_length * 0.25
		for vertex: Vector3 in [origin, tip, tip, head_base + side * up_vector_length * 0.12,
				tip, head_base - side * up_vector_length * 0.12]:
			mesh.surface_add_vertex(to_local(vertex))
	mesh.surface_end()
	_up_vector_preview.mesh = mesh


func _clear_editor_runtime_metadata() -> void:
	for child: Node in get_children():
		if child.has_meta("rail_node") and child.get_meta("rail_node") == self:
			child.remove_meta("rail_node")


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear_editor_runtime_metadata()

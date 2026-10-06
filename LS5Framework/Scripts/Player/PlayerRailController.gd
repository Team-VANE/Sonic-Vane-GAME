extends RefCounted
class_name PlayerRailController

# Rail discovery, switching, grinding, and detachment physics.
const RAIL_SCRIPT = preload("res://LS5Framework/Objects/Rail/Rail.gd")

var _owner: Node = null
var _switch_start_basis: Basis = Basis.IDENTITY
var _switch_duration: float = 0.0
var _surface_handoff_enabled: bool = true
var _surface_handoff_search_length: float = 2.0
var _surface_handoff_max_angle_deg: float = 25.0
const TARGET_SCAN_INTERVAL_SECONDS: float = 0.05
var _path_snap_scan_remaining: float = 0.0
var _path_snap_previous_position: Vector3 = Vector3.ZERO
var _path_snap_previous_position_valid: bool = false


func _init(owner: Node) -> void:
	_owner = owner


func _try_rail_path_snap_attach(v_before: Vector3 = Vector3.ZERO, p_before: Vector3 = Vector3.ZERO) -> void:
	var p = _owner
	var query_pos: Vector3 = p.global_position
	if not p.rail_path_snap_enabled:
		_path_snap_previous_position_valid = false
		return
	var snap_speed: float = max(p.velocity.length(), v_before.length())
	var snap_radius: float = _get_rail_path_snap_radius(snap_speed)
	if snap_radius <= 0.0:
		return
	if p._rail_active or p._spline_active:
		_path_snap_previous_position_valid = false
		_path_snap_scan_remaining = 0.0
		return
	if p._lightspeed_dash_active:
		_path_snap_previous_position = query_pos
		_path_snap_previous_position_valid = true
		return
	if p._spring_align_timer > 0.0:
		_path_snap_previous_position = query_pos
		_path_snap_previous_position_valid = true
		return
	if not can_start_rail_grind():
		_path_snap_previous_position = query_pos
		_path_snap_previous_position_valid = true
		_path_snap_scan_remaining = 0.0
		return

	_path_snap_scan_remaining = max(_path_snap_scan_remaining - max(p._movement_real_delta, 0.0), 0.0)
	if _path_snap_scan_remaining > 0.0:
		return
	_path_snap_scan_remaining = TARGET_SCAN_INTERVAL_SECONDS

	var segment_from: Vector3 = p_before
	if _path_snap_previous_position_valid:
		segment_from = _path_snap_previous_position
	var maximum_sweep: float = max(snap_radius * 4.0, snap_speed * TARGET_SCAN_INTERVAL_SECONDS * 3.0)
	if segment_from.distance_squared_to(query_pos) > maximum_sweep * maximum_sweep:
		segment_from = p_before
	_path_snap_previous_position = query_pos
	_path_snap_previous_position_valid = true

	var query_center: Vector3 = (segment_from + query_pos) * 0.5
	var query_range: float = snap_radius + segment_from.distance_to(query_pos) * 0.5
	var rails: Array = []
	var manager: Node = p.get_node_or_null("/root/HomingTargetManager")
	if manager and manager.has_method("get_rails_in_range"):
		rails = manager.call("get_rails_in_range", query_center, query_range)
	else:
		rails = p.get_tree().get_nodes_in_group("Rail")
	if rails.is_empty():
		return

	var best_rail: Node = null
	var best_query_point: Vector3 = query_pos
	var best_dist_sq: float = snap_radius * snap_radius
	var best_candidate: Dictionary = {}

	for rail in rails:
		if rail == null or not is_instance_valid(rail):
			continue
		if not rail.has_method("get_closest_point_on_path"):
			continue
		if p._object_has_property(rail, "active") and not bool(rail.get("active")):
			continue
		if rail.has_method("is_path_snap_query_near") and not bool(
			rail.call("is_path_snap_query_near", segment_from, query_pos, snap_radius)
		):
			continue

		var closest_point: Vector3 = Vector3.ZERO
		var candidate_query_point: Vector3 = query_pos
		var dist_sq: float = INF
		var candidate: Dictionary = {}
		if rail.has_method("get_path_snap_candidate"):
			var candidate_variant: Variant = rail.call("get_path_snap_candidate", segment_from, query_pos)
			if candidate_variant is Dictionary:
				candidate = candidate_variant
				if candidate.has("point") and candidate["point"] is Vector3:
					closest_point = candidate["point"]
				if candidate.has("query_point") and candidate["query_point"] is Vector3:
					candidate_query_point = candidate["query_point"]
				if candidate.has("distance_squared"):
					dist_sq = float(candidate["distance_squared"])
		else:
			var closest_variant: Variant = rail.call("get_closest_point_on_path", query_pos)
			if not (closest_variant is Vector3):
				continue
			closest_point = closest_variant
			dist_sq = query_pos.distance_squared_to(closest_point)
			candidate = {
				"point": closest_point,
				"query_point": query_pos,
				"distance_squared": dist_sq,
			}

		if dist_sq == INF:
			continue
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best_rail = rail
			best_query_point = candidate_query_point
			best_candidate = candidate

	if best_rail == null:
		return
	var best_point: Vector3 = best_candidate.get("point", Vector3.ZERO)
	if _is_rail_path_snap_obstructed(best_query_point, best_point):
		return
	if not best_rail.has_method("try_start_with_body_proximity"):
		return

	var entry_velocity: Vector3 = p.velocity
	if v_before.length() > 0.001:
		entry_velocity = v_before

	var started: Variant = best_rail.call(
		"try_start_with_body_proximity",
		p,
		snap_radius,
		entry_velocity,
		best_query_point,
		best_candidate
	)
	if started is bool and bool(started):
		p._rail_switch_active = false


func _get_rail_path_snap_radius(speed: float = -1.0) -> float:
	var p = _owner
	var min_radius: float = max(p.rail_path_snap_radius_min, 0.0)
	var max_radius: float = max(p.rail_path_snap_radius_max, min_radius)
	var speed_for_max: float = max(p.rail_path_snap_speed_for_max_radius, 0.0)
	var speed_value: float = speed
	if speed_value < 0.0:
		speed_value = p.velocity.length()
	if speed_for_max <= 0.001:
		return max_radius
	var t: float = clamp(speed_value / speed_for_max, 0.0, 1.0)
	return lerp(min_radius, max_radius, t)


func _is_rail_path_snap_obstructed(query_point: Vector3, rail_point: Vector3) -> bool:
	var p = _owner
	if not p.rail_path_snap_obstruction_check:
		return false
	var to_rail: Vector3 = rail_point - query_point
	var rail_distance: float = to_rail.length()
	if rail_distance <= 0.001:
		return false
	var world: World3D = p.get_world_3d()
	if world == null:
		return false

	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(query_point, rail_point)
	params.exclude = [p]
	params.collision_mask = p.collision_mask
	var hit: Dictionary = world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return false
	if not hit.has("position"):
		return false
	var hit_position: Vector3 = hit["position"]
	var hit_distance: float = query_point.distance_to(hit_position)
	return hit_distance < max(rail_distance - p.rail_path_snap_obstruction_margin, 0.0)


func get_rail_entry_velocity() -> Vector3:
	var p = _owner
	if p._pending_landing_has_velocity:
		return p._pending_landing_velocity
	if not p.attached:
		return p._last_air_velocity
	return p.velocity


func get_rail_entry_forward() -> Vector3:
	var p = _owner
	var f: Vector3 = p._model_forward
	if f.length() < 0.001:
		f = -p.global_transform.basis.z
	return f


func get_rail_rehit_cooldown() -> float:
	var p = _owner
	return max(p.rail_rehit_cooldown, 0.0)


func get_rail_session_snapshot() -> Dictionary:
	var p = _owner
	if not p._rail_active or p._rail_path == null:
		return {}

	return {
		"rail_node": p._rail_node,
		"surface_handoff_enabled": _surface_handoff_enabled,
		"surface_handoff_search_length": _surface_handoff_search_length,
		"surface_handoff_max_angle_deg": _surface_handoff_max_angle_deg,
		"path": p._rail_path,
		"distance": p._rail_distance,
		"speed": p._rail_speed,
		"travel_sign": p._rail_travel_sign,
		"align_model": p._rail_align_model,
		"align_to_path_tilt": p._rail_align_to_path_tilt,
		"allow_jump_exit": p._rail_allow_jump_exit,
		"allow_reverse": p._rail_allow_reverse,
		"allow_input_reverse": p._rail_input_reverse_enabled,
		"end_detach_distance": p._rail_end_detach_distance,
		"min_speed": p._rail_min_speed,
		"lock_speed_enabled": p._rail_locked_speed,
		"lock_speed_value": p._rail_lock_speed_value,
		"gravity_scale": p._rail_gravity_scale,
		"player_height_offset": p._rail_attach_height,
		"reverse_speed_threshold": p._rail_reverse_speed_threshold,
		"reverse_boost_speed": p._rail_reverse_boost_speed
	}


func get_rail_switch_snapshot() -> Dictionary:
	var p = _owner
	if not p._rail_switch_active:
		return {}

	var rail_node = p._rail_switch_target
	var path = p._rail_switch_target_path
	if path == null and rail_node != null and p._object_has_property(rail_node, "path"):
		path = rail_node.get("path")
	if path == null or path.curve == null:
		return {}

	var curve = path.curve
	var total_length: float = curve.get_baked_length()
	if total_length <= 0.01:
		return {}

	var offset: float = clamp(p._rail_switch_target_offset, 0.0, total_length)
	var tangent: Vector3 = p._rail_switch_target_tangent
	if tangent.length() < 0.001:
		tangent = _rail_sample_path_tangent(path, curve, offset, p.rail_switch_tangent_lookahead)
	if tangent.length() < 0.001:
		tangent = -path.global_transform.basis.z
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()

	var inherit_dir: Vector3 = p._rail_switch_inherited_dir
	if inherit_dir.length() < 0.001:
		inherit_dir = p._model_forward
	if inherit_dir.length() < 0.001:
		inherit_dir = -p.global_transform.basis.z
	inherit_dir = inherit_dir.normalized()

	var travel_sign: float = 1.0
	if tangent.dot(inherit_dir) < 0.0:
		travel_sign = -1.0

	var state: Dictionary = {
		"path": path,
		"distance": offset,
		"speed": p._rail_switch_inherited_speed,
		"travel_sign": travel_sign
	}

	if rail_node != null:
		for key in [
			"align_model",
			"align_to_path_tilt",
			"allow_jump_exit",
			"allow_reverse",
			"allow_input_reverse",
			"end_detach_distance",
			"min_speed",
			"lock_speed_enabled",
			"lock_speed_value",
			"gravity_scale",
			"player_height_offset",
			"reverse_speed_threshold",
			"reverse_boost_speed"
		]:
			if p._object_has_property(rail_node, key):
				state[key] = rail_node.get(key)

	return state


func is_on_rail_path(path: Path3D) -> bool:
	var p = _owner
	return p._rail_active and p._rail_path == path


func apply_rail_boost(
	boost_speed: float,
	boost_mode: int,
	travel_sign: float,
	source_path: Path3D = null,
	additive_min_speed: float = 0.0
) -> bool:
	var p = _owner
	if not p._rail_active:
		return false
	if source_path != null and p._rail_path != source_path:
		return false

	var sign: float = travel_sign
	if abs(sign) < 0.001:
		sign = 1.0
	if not p._rail_allow_reverse and sign < 0.0:
		sign = 1.0

	var signed_speed: float
	if boost_mode == 1:
		signed_speed = p._rail_speed + boost_speed * sign
		if additive_min_speed > 0.0:
			if sign >= 0.0 and signed_speed < additive_min_speed:
				signed_speed = additive_min_speed
			elif sign < 0.0 and signed_speed > -additive_min_speed:
				signed_speed = -additive_min_speed
	else:
		signed_speed = boost_speed * sign

	if not p._rail_allow_reverse and signed_speed < 0.0:
		signed_speed = 0.0

	p._rail_speed = signed_speed
	if abs(p._rail_speed) > 0.0001:
		p._rail_travel_sign = -1.0 if p._rail_speed < 0.0 else 1.0
		p._rail_last_motion_dir = p._rail_last_tangent * p._rail_travel_sign
	elif abs(sign) > 0.001:
		p._rail_travel_sign = 1.0 if sign >= 0.0 else -1.0
		p._rail_last_motion_dir = p._rail_last_tangent * p._rail_travel_sign

	return true


func _update_rail_tricks(delta: float) -> void:
	var p = _owner
	if not p._rail_active or p._trick_system == null:
		p._rail_trick_distance_accum = 0.0
		return
	
	var dist_delta: float = abs(p._rail_speed) * delta
	p._rail_trick_distance_accum += dist_delta
	var distance_interval: float = maxf(p.rail_trick_distance_units, 0.1)
	
	if p._rail_trick_distance_accum >= distance_interval:
		p._rail_trick_distance_accum -= distance_interval
		var trick_type: int = get_rail_trick_type(p._rail_crouching)
		p._on_trick_detected(trick_type, p.rail_combo_timer_add_seconds)


func get_rail_trick_type(crouching: bool) -> int:
	var p = _owner
	var fast_crouch: bool = crouching and absf(p._rail_speed) >= maxf(p.rail_crouch_fast_trick_speed_threshold, 0.0)
	if p._rail_travel_sign > 0.0:
		if fast_crouch:
			return TrickSystem.TrickType.RAIL_FORWARD_CROUCH_FAST
		return TrickSystem.TrickType.RAIL_FORWARD_CROUCH if crouching else TrickSystem.TrickType.RAIL_FORWARD
	if fast_crouch:
		return TrickSystem.TrickType.RAIL_BACKWARD_CROUCH_FAST
	return TrickSystem.TrickType.RAIL_BACKWARD_CROUCH if crouching else TrickSystem.TrickType.RAIL_BACKWARD


func is_rail_crouch_input_pressed() -> bool:
	var p = _owner
	if not p.rail_crouch_enabled or not p.roll_enabled or p._local_pause_enabled or p._ui_input_blocked or p._debug_mode:
		return false
	var roll_slot: StringName = p.get_ability_input_slot(&"roll", &"ability_slot_04")
	return SettingsManager.is_gameplay_action_pressed(String(roll_slot))


func cancel_rail_grind(reset_velocity: bool = false) -> void:
	var p = _owner
	var was_rail_active: bool = p._rail_active
	if p._rail_grind_action != null:
		p._rail_grind_action.cancel_grind(reset_velocity)
	if was_rail_active:
		p._play_rail_detach_sfx()
	p._rail_active = false
	p._rail_path = null
	p._rail_distance = 0.0
	p._rail_total_length = 0.0
	p._rail_speed = 0.0
	p._rail_travel_sign = 1.0
	p._rail_last_tangent = Vector3.FORWARD
	p._rail_last_motion_dir = Vector3.FORWARD
	p._rail_model_basis_valid = false
	p._stop_rail_grind_sfx()
	if reset_velocity:
		p.velocity = Vector3.ZERO


func _get_rail_tangent_world(curve: Curve3D, distance: float, total_length: float) -> Vector3:
	var p = _owner
	if curve == null or p._rail_path == null:
		return Vector3.FORWARD
	var step: float = 0.08
	var before: float = clamp(distance - step, 0.0, total_length)
	var after: float = clamp(distance + step, 0.0, total_length)
	if abs(after - before) < 0.0001:
		after = min(before + step, total_length)
		before = max(before - step, 0.0)
	var p0_local: Vector3 = curve.sample_baked(before)
	var p1_local: Vector3 = curve.sample_baked(after)
	var p0_world: Vector3 = p._rail_path.to_global(p0_local)
	var p1_world: Vector3 = p._rail_path.to_global(p1_local)
	return p1_world - p0_world


func _get_rail_tilt(curve: Curve3D, distance: float) -> float:
	var p = _owner
	if curve == null:
		return 0.0
	if curve.has_method("sample_baked_tilt"):
		var v = curve.call("sample_baked_tilt", distance)
		if v is float:
			return float(v)
	if curve.has_method("interpolate_baked_tilt"):
		var v2 = curve.call("interpolate_baked_tilt", distance)
		if v2 is float:
			return float(v2)
	if curve.has_method("get_baked_tilts"):
		var tilts = curve.call("get_baked_tilts")
		if tilts is PackedFloat32Array and tilts.size() > 0:
			var interval: float = 0.0
			if curve.has_method("get_bake_interval"):
				var bi = curve.call("get_bake_interval")
				if bi is float:
					interval = float(bi)
			if interval <= 0.0:
				var bi2 = curve.get("bake_interval")
				if bi2 is float:
					interval = float(bi2)
			if interval <= 0.0:
				interval = 1.0
			var idx: int = int(round(distance / interval))
			idx = clamp(idx, 0, tilts.size() - 1)
			return float(tilts[idx])
	return 0.0


func _get_rail_up_vector(curve: Curve3D, rail_dir: Vector3, distance: float) -> Vector3:
	var p = _owner
	var up: Vector3 = Vector3.ZERO
	var candidates : Array = []
	if p._rail_path != null:
		candidates.append(p._rail_path.global_transform.basis.y)
		candidates.append(p._rail_path.global_transform.basis.x)
		candidates.append(-p._rail_path.global_transform.basis.z)
	candidates.append(p._get_gravity_up())
	candidates.append(Vector3.RIGHT)
	candidates.append(Vector3.FORWARD)

	for candidate in candidates:
		if not (candidate is Vector3):
			continue
		var c_vec: Vector3 = candidate
		if c_vec.length() < 0.001:
			continue
		var projected: Vector3 = c_vec - rail_dir * c_vec.dot(rail_dir)
		if projected.length() > 0.001:
			up = projected.normalized()
			break

	if up.length() < 0.001:
		up = p._get_gravity_up()

	var tilt: float = _get_rail_tilt(curve, distance)
	if abs(tilt) > 0.0001:
		up = (Basis(rail_dir, tilt) * up).normalized()
	return up


func _get_rail_input_direction(world_up: Vector3) -> Vector3:
	var p = _owner
	if p._move_input.length() < 0.001:
		return Vector3.ZERO
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var forward: Vector3 = p._get_camera_forward_world_up(up)
	if forward.length() < 0.001:
		forward = -Vector3.FORWARD
	forward = forward.normalized()

	var right: Vector3 = forward.cross(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()

	var dir: Vector3 = forward * p._move_input.y + right * p._move_input.x
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized()


func _get_rail_spindash_input_direction(world_up: Vector3) -> Vector3:
	var p = _owner
	var x: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var z: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var input: Vector2 = Vector2(x, z)
	if input.length() < 0.001:
		return Vector3.ZERO
	if input.length() > 1.0:
		input = input.normalized()

	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var forward: Vector3 = p._get_camera_forward_world_up(up)
	if forward.length() < 0.001:
		forward = -Vector3.FORWARD
	forward = forward.normalized()

	var right: Vector3 = forward.cross(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()

	var dir: Vector3 = forward * input.y + right * input.x
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized()


func _get_rail_spindash_release_sign(rail_dir: Vector3, world_up: Vector3) -> float:
	var p = _owner
	var desired_sign: float = 0.0
	var input_dir: Vector3 = _get_rail_spindash_input_direction(world_up)
	if input_dir.length() > 0.001:
		var dot: float = rail_dir.dot(input_dir)
		if dot >= p.rail_reverse_input_dot_threshold:
			desired_sign = 1.0
		elif dot <= -p.rail_reverse_input_dot_threshold:
			desired_sign = -1.0
		if desired_sign < 0.0 and not p._rail_allow_reverse:
			desired_sign = 0.0

	if abs(desired_sign) < 0.001:
		var movement_dir: Vector3 = p._rail_last_motion_dir
		if movement_dir.length() < 0.001:
			var base_sign: float = -1.0 if p._rail_speed < 0.0 else 1.0
			movement_dir = rail_dir * base_sign
		desired_sign = 1.0 if rail_dir.dot(movement_dir) >= 0.0 else -1.0

	if not p._rail_allow_reverse and desired_sign < 0.0:
		desired_sign = 1.0

	return desired_sign


func _get_rail_switch_right(world_up: Vector3) -> Vector3:
	var p = _owner
	var up: Vector3 = p.visual_up.normalized()
	if up.length() < 0.001:
		up = world_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var rail_dir: Vector3 = p._rail_last_tangent
	if rail_dir.length() < 0.001:
		rail_dir = p._rail_last_motion_dir
	if rail_dir.length() < 0.001:
		rail_dir = p._model_forward
	if rail_dir.length() < 0.001:
		rail_dir = -p.global_transform.basis.z
	rail_dir = rail_dir.normalized()

	var right: Vector3 = rail_dir.cross(up)
	if right.length() < 0.001:
		var camera_forward: Vector3 = p._get_camera_forward_world_up(up)
		right = camera_forward.cross(up)
	if right.length() < 0.001:
		right = p.global_transform.basis.x
	if right.length() < 0.001:
		return Vector3.ZERO
	return right.normalized()


func _get_rail_switch_side_input(world_up: Vector3) -> float:
	var p = _owner
	var input_strength: float = clamp(p._move_input.length(), 0.0, 1.0)
	if input_strength < 0.001:
		return 0.0

	var input_up: Vector3 = p.visual_up.normalized()
	if input_up.length() < 0.001:
		input_up = world_up.normalized()
	if input_up.length() < 0.001:
		input_up = p._get_gravity_up()
	var input_dir: Vector3 = _get_rail_input_direction(input_up)
	var rail_right: Vector3 = _get_rail_switch_right(world_up)
	if input_dir.length() < 0.001 or rail_right.length() < 0.001:
		return 0.0

	var side_strength: float = input_dir.dot(rail_right) * input_strength
	if abs(side_strength) < p.rail_switch_side_input_min:
		return 0.0
	return 1.0 if side_strength > 0.0 else -1.0


func _rail_sample_path_tangent(path: Path3D, curve: Curve3D, offset: float, lookahead: float) -> Vector3:
	var p = _owner
	if path == null or curve == null:
		return Vector3.FORWARD
	var total_len: float = curve.get_baked_length()
	if total_len <= 0.01:
		return Vector3.FORWARD
	var ahead : float = clamp(offset + lookahead, 0.0, total_len)
	var here_local: Vector3 = curve.sample_baked(offset)
	var there_local: Vector3 = curve.sample_baked(ahead)
	var here: Vector3 = path.to_global(here_local)
	var there: Vector3 = path.to_global(there_local)
	return there - here


func _rail_find_closest_offset(path: Path3D, curve: Curve3D, world_point: Vector3) -> float:
	var p = _owner
	if path == null or curve == null:
		return 0.0

	var total_length: float = curve.get_baked_length()
	if total_length <= 0.01:
		return 0.0

	var local_point: Vector3 = path.to_local(world_point)
	var closest_local: Vector3 = curve.get_closest_point(local_point)

	var steps: int = int(clamp(total_length / 0.5, 32.0, 2048.0))
	if steps <= 0:
		steps = 1
	var step: float = total_length / float(steps)
	var best_offset: float = 0.0
	var best_dist: float = INF
	var current_offset: float = 0.0

	for i in range(steps + 1):
		var clamped_offset: float = clamp(current_offset, 0.0, total_length)
		var sample: Vector3 = curve.sample_baked(clamped_offset)
		var dist: float = sample.distance_squared_to(closest_local)
		if dist < best_dist:
			best_dist = dist
			best_offset = clamped_offset
		current_offset += step

	var prev_offset: float = max(best_offset - step, 0.0)
	var next_offset: float = min(best_offset + step, total_length)
	var prev_point: Vector3 = curve.sample_baked(prev_offset)
	var next_point: Vector3 = curve.sample_baked(next_offset)
	var segment: Vector3 = next_point - prev_point
	var seg_len_sq: float = segment.length_squared()
	if seg_len_sq > 0.0001:
		var rel: Vector3 = closest_local - prev_point
		var t: float = clamp(rel.dot(segment) / seg_len_sq, 0.0, 1.0)
		best_offset = lerp(prev_offset, next_offset, t)

	return best_offset


func _find_rail_switch_candidate(desired_side: float, world_up: Vector3) -> Dictionary:
	var p = _owner
	var result: Dictionary = {}
	if p.DEBUG_SKIP_RAIL_SHAPE:
		return result
	if abs(desired_side) < 0.001:
		return result

	var rails: Array = p.get_tree().get_nodes_in_group("Rail")
	if rails.is_empty():
		return result

	var travel_dir: Vector3 = p._rail_last_motion_dir
	if travel_dir.length() < 0.001:
		travel_dir = p._model_forward
	if travel_dir.length() < 0.001:
		travel_dir = -p.global_transform.basis.z
	travel_dir = travel_dir.normalized()

	var right: Vector3 = _get_rail_switch_right(world_up)
	if right.length() < 0.001:
		return result

	var switch_duration: float = max(p.rail_switch_max_duration, 0.0)
	var predicted_forward_speed: float = max(
		abs(p._rail_speed) * p.rail_switch_forward_speed_scale,
		p.rail_switch_forward_speed_min
	)
	if predicted_forward_speed <= 0.01:
		predicted_forward_speed = max(abs(p._rail_speed), 0.01)
	var predicted_position: Vector3 = p.global_position + travel_dir * predicted_forward_speed * switch_duration

	var best_current_side_distance: float = INF
	var best_lateral_dist_sq: float = INF
	var best_landing_dist_sq: float = INF
	var best_alignment: float = -INF
	var best_side: float = -INF

	var switch_query_radius: float = max(p.rail_switch_query_radius, 0.0)
	var max_switch_dist_sq: float = switch_query_radius * switch_query_radius
	for rail_entry in rails:
		if rail_entry == null or not is_instance_valid(rail_entry):
			continue
		var rail_node: Node = rail_entry as Node
		if rail_node == null:
			continue
		if not rail_node.has_method("try_start_with_body"):
			continue
		if p._object_has_property(rail_node, "active") and not bool(rail_node.get("active")):
			continue

		if not p._object_has_property(rail_node, "path"):
			continue
		var rail_path_variant: Variant = rail_node.get("path")
		if not (rail_path_variant is Path3D):
			continue
		var rail_path: Path3D = rail_path_variant
		if rail_path == null or rail_path.curve == null:
			continue
		if p._rail_path != null and rail_path == p._rail_path:
			continue

		var curve: Curve3D = rail_path.curve
		var total_length: float = curve.get_baked_length()
		if total_length <= 0.01:
			continue

		var offset: float = _rail_find_closest_offset(rail_path, curve, predicted_position)
		if p.rail_switch_min_end_distance > 0.0:
			if offset <= p.rail_switch_min_end_distance or offset >= total_length - p.rail_switch_min_end_distance:
				continue

		var point: Vector3 = _get_switch_landing_transform(rail_node, rail_path, offset).origin
		var to_point: Vector3 = point - predicted_position
		var forward_separation: float = to_point.dot(travel_dir)
		var lateral_delta: Vector3 = to_point - travel_dir * forward_separation

		var side_reference_offset: float = _rail_find_closest_offset(rail_path, curve, p.global_position)
		var side_reference_point: Vector3 = _get_switch_landing_transform(rail_node, rail_path, side_reference_offset).origin
		var side_reference_delta: Vector3 = side_reference_point - p.global_position
		var side_reference_forward: float = side_reference_delta.dot(travel_dir)
		var side_reference_lateral: Vector3 = side_reference_delta - travel_dir * side_reference_forward
		var side_reference_distance: float = side_reference_lateral.length()
		if side_reference_distance < 0.001:
			continue
		var side_offset: float = side_reference_delta.dot(right)
		if abs(side_offset) < 0.001:
			continue
		var side_dot: float = side_offset / side_reference_distance
		if sign(side_dot) != desired_side or abs(side_dot) < p.rail_switch_side_dot_min:
			continue

		var tangent: Vector3 = _rail_sample_path_tangent(rail_path, curve, offset, p.rail_switch_tangent_lookahead)
		if tangent.length() < 0.001:
			continue
		tangent = tangent.normalized()

		var forward_alignment: float = abs(travel_dir.dot(tangent))
		if forward_alignment < p.rail_switch_forward_dot_min:
			continue

		var landing_dist_sq: float = to_point.length_squared()
		if landing_dist_sq > max_switch_dist_sq:
			continue
		var current_side_distance: float = abs(side_offset)
		var lateral_dist_sq: float = lateral_delta.length_squared()
		var side_score : float = abs(side_dot)
		var pick: bool = false
		if current_side_distance < best_current_side_distance - 0.001:
			pick = true
		elif abs(current_side_distance - best_current_side_distance) <= 0.001:
			if lateral_dist_sq < best_lateral_dist_sq - 0.001:
				pick = true
			elif abs(lateral_dist_sq - best_lateral_dist_sq) <= 0.001:
				if landing_dist_sq < best_landing_dist_sq - 0.001:
					pick = true
				elif abs(landing_dist_sq - best_landing_dist_sq) <= 0.001:
					if forward_alignment > best_alignment + 0.001 or (abs(forward_alignment - best_alignment) <= 0.001 and side_score > best_side + 0.001):
						pick = true
		if pick:
			best_current_side_distance = current_side_distance
			best_lateral_dist_sq = lateral_dist_sq
			best_landing_dist_sq = landing_dist_sq
			best_alignment = forward_alignment
			best_side = side_score
			result = {
				"rail": rail_node,
				"path": rail_path,
				"offset": offset,
				"point": point,
				"tangent": tangent,
				"side_dot": side_dot
			}

	return result


func _update_rail_switch_candidate(world_up: Vector3) -> void:
	var p = _owner
	p._rail_switch_candidate = null
	p._rail_switch_candidate_point = Vector3.ZERO
	p._rail_switch_candidate_tangent = Vector3.ZERO
	p._rail_switch_candidate_side = 0.0

	var side: float = _get_rail_switch_side_input(world_up)
	if side == 0.0:
		return

	var candidate: Dictionary = _find_rail_switch_candidate(side, world_up)
	if candidate.is_empty():
		return

	p._rail_switch_candidate = candidate.get("rail")
	p._rail_switch_candidate_point = candidate.get("point", Vector3.ZERO)
	p._rail_switch_candidate_tangent = candidate.get("tangent", Vector3.ZERO)
	p._rail_switch_candidate_side = side


func _start_rail_switch(candidate: Dictionary, world_up: Vector3) -> void:
	var p = _owner
	var rail_node: Node3D = candidate.get("rail")
	if rail_node == null:
		return

	p._rail_switch_inherited_speed = abs(p._rail_speed)
	p._rail_switch_inherited_dir = p._rail_last_motion_dir
	if p._rail_switch_inherited_dir.length() < 0.001:
		p._rail_switch_inherited_dir = p._model_forward
	if p._rail_switch_inherited_dir.length() < 0.001:
		p._rail_switch_inherited_dir = -p.global_transform.basis.z
	p._rail_switch_inherited_dir = p._rail_switch_inherited_dir.normalized()

	var rail_right: Vector3 = _get_rail_switch_right(world_up)
	var target_point: Vector3 = candidate.get("point", Vector3.ZERO)
	var to_target: Vector3 = target_point - p.global_position
	var candidate_side: float = float(candidate.get("side_dot", 0.0))
	if abs(candidate_side) >= 0.001:
		p._rail_switch_animation_side = sign(candidate_side)
	else:
		p._rail_switch_animation_side = sign(to_target.dot(rail_right))
	p._rail_switch_animation_started = false

	_switch_start_basis = p._rail_model_basis.orthonormalized() if p._rail_model_basis_valid else Basis.looking_at(p._model_forward, p.visual_up)
	if is_instance_valid(p.model_root):
		_switch_start_basis = p.model_root.global_basis.orthonormalized()
	_switch_duration = max(p.rail_switch_max_duration, 0.0)
	p._rail_switch_active = true
	p._rail_switch_timer = max(p.rail_switch_max_duration, 0.0)
	p._rail_switch_target = rail_node
	p._rail_switch_target_path = candidate.get("path")
	p._rail_switch_target_offset = float(candidate.get("offset", 0.0))
	p._rail_switch_target_point = candidate.get("point", Vector3.ZERO)
	p._rail_switch_target_tangent = candidate.get("tangent", Vector3.ZERO)

	_end_rail(false, world_up)
	p.visual_up = _switch_start_basis.y
	p.up_direction = p.visual_up
	p._rail_align_model = rail_node.get("align_model") != false
	p._rail_model_basis = _switch_start_basis
	p._rail_model_basis_valid = true
	p._jump_requested = false
	p._jump_dash_requested = false
	p._jump_variable = false
	p._jump_hang_allowed = false
	p._jump_time = 0.0
	p._update_jump_ball(0.0)

	var v: Vector3 = p._rail_switch_inherited_dir * p._rail_switch_inherited_speed
	p.velocity = v
	p._last_air_velocity = v


func _try_start_rail_switch(world_up: Vector3) -> bool:
	var p = _owner
	if not p.rail_switch_enabled:
		return false
	if p._rail_switch_active:
		return false

	var side: float = _get_rail_switch_side_input(world_up)
	if side == 0.0:
		return false

	var candidate: Dictionary = _find_rail_switch_candidate(side, world_up)
	if candidate.is_empty():
		return false

	_start_rail_switch(candidate, world_up)
	return true


func _cancel_rail_switch() -> void:
	var p = _owner
	p._rail_switch_active = false
	p._rail_switch_animation_started = false
	if p._rail_switch_inherited_speed <= 0.0:
		return

	var dir: Vector3 = p._rail_switch_inherited_dir
	if dir.length() < 0.001:
		dir = p._model_forward
	if dir.length() < 0.001:
		dir = -p.global_transform.basis.z
	if dir.length() < 0.001:
		return

	p.velocity = dir.normalized() * p._rail_switch_inherited_speed
	p._last_air_velocity = p.velocity


func _update_rail_switch(delta: float) -> void:
	var p = _owner
	if not p._rail_switch_active:
		return
	if p._rail_active or p.attached:
		_cancel_rail_switch()
		return

	var switch_time_before_step: float = p._rail_switch_timer
	if switch_time_before_step <= delta + 0.000001:
		p._rail_switch_timer = 0.0
	else:
		p._rail_switch_timer = switch_time_before_step - delta

	if p._rail_switch_target == null or not is_instance_valid(p._rail_switch_target):
		_cancel_rail_switch()
		return

	var rail_path: Path3D = p._rail_switch_target_path
	if rail_path == null:
		rail_path = p._rail_switch_target.path
	if rail_path == null or rail_path.curve == null:
		_cancel_rail_switch()
		return

	var curve: Curve3D = rail_path.curve
	var total_length: float = curve.get_baked_length()
	if total_length <= 0.01:
		_cancel_rail_switch()
		return

	var inherit_dir: Vector3 = p._rail_switch_inherited_dir
	if inherit_dir.length() < 0.001:
		inherit_dir = p._model_forward
	if inherit_dir.length() < 0.001:
		inherit_dir = -p.global_transform.basis.z
	inherit_dir = inherit_dir.normalized()

	var forward_speed: float = max(p._rail_switch_inherited_speed * p.rail_switch_forward_speed_scale, p.rail_switch_forward_speed_min)
	if forward_speed <= 0.01:
		forward_speed = max(p._rail_switch_inherited_speed, 0.01)
	var predicted_position: Vector3 = p.global_position + inherit_dir * forward_speed * switch_time_before_step

	var offset: float = _rail_find_closest_offset(rail_path, curve, predicted_position)
	if p.rail_switch_min_end_distance > 0.0:
		if offset <= p.rail_switch_min_end_distance or offset >= total_length - p.rail_switch_min_end_distance:
			_cancel_rail_switch()
			return

	var landing_transform: Transform3D = _get_switch_landing_transform(p._rail_switch_target, rail_path, offset)
	var point: Vector3 = landing_transform.origin
	p._rail_switch_target_point = point
	p._rail_switch_target_offset = offset

	var tangent: Vector3 = _rail_sample_path_tangent(rail_path, curve, offset, p.rail_switch_tangent_lookahead)
	if tangent.length() < 0.001:
		tangent = p._rail_switch_target_tangent
	if tangent.length() < 0.001:
		tangent = -rail_path.global_transform.basis.z
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()

	var travel_sign: float = 1.0
	if tangent.dot(inherit_dir) < 0.0:
		travel_sign = -1.0
	var tangent_dir: Vector3 = tangent * travel_sign

	var to_target: Vector3 = point - p.global_position
	var lateral_to_target: Vector3 = to_target - tangent_dir * to_target.dot(tangent_dir)
	var lateral_dist: float = lateral_to_target.length()
	var lateral_vel: float = 0.0
	var lateral_dir: Vector3 = Vector3.ZERO
	var lateral_step: float = 0.0

	if lateral_dist > 0.001:
		lateral_dir = lateral_to_target / lateral_dist
		var step_ratio: float = 1.0
		if switch_time_before_step > delta + 0.000001:
			step_ratio = clamp(delta / switch_time_before_step, 0.0, 1.0)
		lateral_step = lateral_dist * step_ratio
		lateral_vel = lateral_step / max(delta, 0.001)

	var step: Vector3 = tangent_dir * (forward_speed * delta) + lateral_dir * lateral_step
	p.global_position += step
	p.velocity = tangent_dir * forward_speed + lateral_dir * lateral_vel
	p._last_air_velocity = p.velocity

	var progress: float = 1.0 - p._rail_switch_timer / max(_switch_duration, 0.000001)
	progress = clamp(progress, 0.0, 1.0)
	var eased_progress: float = progress * progress * (3.0 - 2.0 * progress)
	p._rail_model_basis = _switch_start_basis.slerp(landing_transform.basis, eased_progress).orthonormalized()
	p._rail_model_basis_valid = true
	p.visual_up = p._rail_model_basis.y
	p.up_direction = p.visual_up
	p._model_forward = -p._rail_model_basis.z

	if p._rail_switch_timer > 0.0:
		return

	offset = _rail_find_closest_offset(rail_path, curve, p.global_position)
	point = rail_path.to_global(curve.sample_baked(offset))
	landing_transform = _get_switch_landing_transform(p._rail_switch_target, rail_path, offset)
	p._rail_switch_target_offset = offset
	p._rail_switch_target_point = landing_transform.origin
	var landing_tangent: Vector3 = _rail_sample_path_tangent(rail_path, curve, offset, p.rail_switch_tangent_lookahead)
	if landing_tangent.length() > 0.001:
		tangent = landing_tangent.normalized()
		p._rail_switch_target_tangent = tangent
		travel_sign = -1.0 if tangent.dot(inherit_dir) < 0.0 else 1.0
		tangent_dir = tangent * travel_sign

	var inherit_speed: float = max(p._rail_switch_inherited_speed, 0.0)
	var entry_velocity: Vector3 = tangent_dir * inherit_speed
	var entry_forward: Vector3 = inherit_dir

	if p._rail_switch_target.has_method("build_session_params_for_entry"):
		var params: Dictionary = p._rail_switch_target.call(
			"build_session_params_for_entry",
			point,
			entry_velocity,
			entry_forward
		)
		if not params.is_empty():
			start_rail_grind(params)

	if p._rail_active:
		p.global_position = landing_transform.origin
		p._rail_model_basis = landing_transform.basis
		p._rail_model_basis_valid = true
		p.visual_up = landing_transform.basis.y
		p.up_direction = p.visual_up
		p._model_forward = -landing_transform.basis.z
		p._rail_switch_active = false
		p._rail_switch_animation_started = false
		return

	_cancel_rail_switch()


func start_rail_grind(params: Dictionary) -> void:
	var p = _owner
	if not can_start_rail_grind():
		p.can_grind_rails = false
		return
	p.can_grind_rails = true
	if p._rail_active:
		_end_rail(false, p._get_gravity_up())

	if p._homing_active:
		p.cancel_homing_attack(false)

	# Keep barrier blast gauge while on rails; rails don't consume it but can build it.

	var path: Path3D = params.get("path")
	if path == null or path.curve == null:
		return

	var curve: Curve3D = path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.01:
		return

	p._rail_path = path
	p._rail_node = params.get("rail_node")
	_surface_handoff_enabled = bool(params.get("surface_handoff_enabled", true))
	_surface_handoff_search_length = max(float(params.get("surface_handoff_search_length", 2.0)), 0.0)
	_surface_handoff_max_angle_deg = clamp(float(params.get("surface_handoff_max_angle_deg", 25.0)), 0.0, 89.0)
	p._rail_total_length = length
	p._rail_distance = clamp(params.get("start_offset", 0.0), 0.0, p._rail_total_length)
	p._rail_speed = params.get("initial_speed", 0.0)
	if abs(p._rail_speed) < 0.01:
		p._rail_speed = params.get("min_speed", 0.0)

	if abs(p._rail_speed) < 0.01:
		var fallback : float = max(params.get("lock_speed_value", 0.0), params.get("min_speed", 0.0))
		if fallback <= 0.0:
			fallback = 5.0
		p._rail_speed = fallback

	p._rail_align_model = params.get("align_model", true)
	p._rail_align_to_path_tilt = params.get("align_to_path_tilt", p.rail_align_to_path_tilt)
	p._rail_allow_jump_exit = params.get("allow_jump_exit", true)
	p._rail_allow_reverse = params.get("allow_reverse", true)
	p._rail_input_reverse_enabled = params.get("allow_input_reverse", p.rail_allow_input_reverse)
	p._rail_end_detach_distance = max(float(params.get("end_detach_distance", p.rail_end_detach_distance)), 0.0)
	p._rail_min_speed = params.get("min_speed", 0.0)
	p._rail_locked_speed = params.get("lock_speed_enabled", false)
	p._rail_lock_speed_value = params.get("lock_speed_value", 0.0)
	if p._rail_locked_speed and p._rail_lock_speed_value <= 0.0:
		p._rail_locked_speed = false
	p._rail_gravity_scale = params.get("gravity_scale", 1.0)
	p._rail_reverse_speed_threshold = max(float(params.get("reverse_speed_threshold", p.rail_reverse_speed_threshold)), 0.0)
	p._rail_reverse_boost_speed = max(float(params.get("reverse_boost_speed", p.rail_reverse_boost_speed)), 0.0)
	p._rail_attach_height = params.get("player_height_offset", p.rail_default_attach_height)
	if p._rail_attach_height <= 0.0:
		p._rail_attach_height = p.rail_default_attach_height
	p._rail_last_tangent = Vector3.FORWARD

	if not p._rail_allow_reverse and p._rail_speed < 0.0:
		p._rail_speed = abs(p._rail_speed)

	var start_travel_sign: float = float(params.get("start_travel_sign", 0.0))
	if abs(start_travel_sign) > 0.001:
		p._rail_travel_sign = -1.0 if start_travel_sign < 0.0 else 1.0
	else:
		p._rail_travel_sign = -1.0 if p._rail_speed < 0.0 else 1.0
	if not p._rail_allow_reverse and p._rail_travel_sign < 0.0:
		p._rail_travel_sign = 1.0
	var start_tangent: Vector3 = _get_rail_tangent_world(curve, p._rail_distance, p._rail_total_length)
	if start_tangent.length() > 0.001:
		p._rail_last_tangent = start_tangent.normalized()
	p._rail_last_motion_dir = p._rail_last_tangent * p._rail_travel_sign
	var dir_den : float = max(p.rail_anim_dir_speed_for_full, 0.001)
	p._rail_anim_dir_smoothed = clamp(p._rail_speed / dir_den, -1.0, 1.0)
	p._rail_anim_speed_smoothed = 0.0

	p._rail_active = true
	p.attached = true
	p._prev_attached = true
	p.remove_coyote_jump_eligibility()
	_clear_attack_state_for_rail_landing()
	p.refresh_traversal_actions()
	p.refresh_tornado_kick_availability()
	p._jump_dash_used_this_air = false
	p.reset_flight_eligibility()
	p._jump_dash_requested = false
	p._spline_active = false
	p._spring_align_timer = 0.0
	p._bounce_state = p.BounceState.NONE
	p._is_jumping = false
	p._is_falling = false
	p._update_jump_ball(0.0)

	if params.get("override_previous_lock_timers", false):
		p.clear_object_lock_timers()
	p._spring_movement_lock_timer = max(p._spring_movement_lock_timer, params.get("movement_lock_time", 0.0))
	p._spring_action_lock_timer = max(p._spring_action_lock_timer, params.get("action_lock_time", 0.0))
	p._play_rail_land_sfx()


func can_start_rail_grind() -> bool:
	var p = _owner
	if p._is_dead:
		return false
	if p._rail_grind_action == null:
		return false
	return p._rail_grind_action.can_grind()


func _clear_attack_state_for_rail_landing() -> void:
	var p = _owner
	if p._active_action != null and is_instance_valid(p._active_action):
		p.clear_active_action()
	p._attack_sources = 0
	p._jumped_from_ground = false
	p._jump_dash_recent_timer = 0.0
	p._homing_post_attack_timer = 0.0
	p._enemy_attack_chain_active = false
	p._bounce_state = p.BounceState.NONE
	p.rolling = false
	p._reset_spindash_state()
	p._set_attack_source(p.AttackSource.MANUAL, false)


func _update_rail_motion(delta: float, world_up: Vector3) -> void:
	var p = _owner
	if not p._rail_active or p._rail_path == null or p._rail_path.curve == null:
		if p._rail_active:
			_end_rail(false, world_up)
		return

	if p._debug_visible:
		_update_rail_switch_candidate(world_up)

	var curve: Curve3D = p._rail_path.curve

	if p._rail_allow_jump_exit and p._spring_movement_lock_timer <= 0.0:
		var jump_slot: StringName = p.get_ability_input_slot(&"jump", &"ability_slot_01")
		if SettingsManager.is_gameplay_action_just_pressed(String(jump_slot)):
			if _try_start_rail_switch(world_up):
				return
			_end_rail(true, world_up)
			return

	# Ignore movement input while rail grinding unless explicitly enabled.
	if not p._rail_input_reverse_enabled:
		p._move_input = Vector2.ZERO

	p._rail_crouching = is_rail_crouch_input_pressed()

	var spindash_on_rail: bool = p._spindash_charging and p.spindash_enabled
	var signed_speed: float = p._rail_speed
	var prev_travel_sign: float = p._rail_travel_sign
	var travel_sign: float = p._rail_travel_sign
	if abs(signed_speed) > 0.0001:
		travel_sign = -1.0 if signed_speed < 0.0 else 1.0

	var rail_dir: Vector3 = _get_rail_tangent_world(curve, p._rail_distance, p._rail_total_length)
	if rail_dir.length() < 0.001:
		rail_dir = p._rail_last_tangent
	if rail_dir.length() < 0.001:
		rail_dir = -p._rail_path.global_transform.basis.z
	if rail_dir.length() < 0.001:
		rail_dir = Vector3.FORWARD
	rail_dir = rail_dir.normalized()

	if p._rail_allow_reverse and p._rail_input_reverse_enabled and p._rail_reverse_speed_threshold > 0.0 and abs(signed_speed) <= p._rail_reverse_speed_threshold:
		var input_dir: Vector3 = _get_rail_input_direction(world_up)
		if input_dir.length() > 0.001:
			var input_dot: float = rail_dir.dot(input_dir)
			if input_dot >= p.rail_reverse_input_dot_threshold:
				travel_sign = 1.0
			elif input_dot <= -p.rail_reverse_input_dot_threshold:
				travel_sign = -1.0

			if travel_sign != 0.0 and abs(signed_speed) < p._rail_reverse_boost_speed:
				signed_speed = p._rail_reverse_boost_speed * travel_sign
			elif abs(signed_speed) > 0.0001:
				signed_speed = abs(signed_speed) * travel_sign

	if not p._rail_allow_reverse and travel_sign < 0.0:
		travel_sign = 1.0

	p._rail_travel_sign = travel_sign

	if p._rail_locked_speed and p._rail_lock_speed_value > 0.0 and not spindash_on_rail and not p._spindash_release_requested:
		signed_speed = p._rail_lock_speed_value * travel_sign
	else:
		if spindash_on_rail:
			var gravity_up_dir: Vector3 = world_up.normalized()
			if gravity_up_dir.length() < 0.001:
				gravity_up_dir = p._get_gravity_up()
			var accel: float = -p.get_effective_gravity_strength() * p._rail_gravity_scale * rail_dir.dot(gravity_up_dir)
			signed_speed += accel * delta

			var speed_mag : float = abs(signed_speed)
			var charge_decel : float = max(p.spindash_charge_decel, 0.0)
			speed_mag = max(speed_mag - charge_decel * delta, 0.0)
			if speed_mag <= 0.0:
				signed_speed = 0.0
			else:
				var sign: float = travel_sign
				if abs(sign) < 0.001:
					sign = -1.0 if signed_speed < 0.0 else 1.0
				if abs(sign) < 0.001:
					sign = 1.0
				signed_speed = speed_mag * sign
		else:
			var gravity_up_dir: Vector3 = world_up.normalized()
			if gravity_up_dir.length() < 0.001:
				gravity_up_dir = p._get_gravity_up()
			var accel: float = -p.get_effective_gravity_strength() * p._rail_gravity_scale * rail_dir.dot(gravity_up_dir)
			signed_speed += accel * delta

			if p._rail_crouching:
				var motion_sign: float = travel_sign
				if signed_speed < -0.0001:
					motion_sign = -1.0
				elif signed_speed > 0.0001:
					motion_sign = 1.0
				var motion_dir: Vector3 = rail_dir * motion_sign
				var slope_dot: float = motion_dir.dot(gravity_up_dir)
				var speed_mag : float = abs(signed_speed)
				if slope_dot > 0.0001:
					speed_mag = max(speed_mag - p.rail_crouch_uphill_decel * slope_dot * delta, 0.0)
				elif slope_dot < -0.0001:
					speed_mag += p.rail_crouch_downhill_accel * (-slope_dot) * delta
				var sign: float = motion_sign
				if abs(signed_speed) <= 0.0001:
					sign = travel_sign if abs(travel_sign) > 0.001 else 1.0
				signed_speed = speed_mag * sign

			if p._rail_allow_reverse and p._rail_input_reverse_enabled and prev_travel_sign != travel_sign:
				if p._rail_reverse_boost_speed > 0.0 and abs(signed_speed) < p._rail_reverse_boost_speed:
					signed_speed = p._rail_reverse_boost_speed * travel_sign

			var apply_min_speed: bool = p._rail_min_speed > 0.0
			if p._rail_crouching and p._rail_allow_reverse and p._rail_input_reverse_enabled:
				apply_min_speed = false
			if apply_min_speed:
				var dir: float = travel_sign
				if signed_speed < -0.0001:
					dir = -1.0
				elif signed_speed > 0.0001:
					dir = 1.0
				signed_speed = max(abs(signed_speed), p._rail_min_speed) * dir
			elif not p._rail_allow_reverse and signed_speed < 0.0:
				signed_speed = 0.0

	if p._spindash_release_requested:
		var release_sign: float = _get_rail_spindash_release_sign(rail_dir, world_up)
		var target_speed: float = max(p._spindash_release_speed, 0.0)
		var maximum_launch_speed: float = max(p.spindash_rail_max_launch_speed, p.spindash_min_launch_speed)
		if p.spindash_preserve_entry_speed_above_max and p._spindash_entry_speed > maximum_launch_speed:
			target_speed = max(target_speed, p._spindash_entry_speed)
		signed_speed = target_speed * release_sign
		travel_sign = release_sign
		p._spindash_turn_free_timer = max(p.spindash_turn_penalty_disable_time, 0.0)
		p._spindash_release_requested = false
		p._spindash_release_with_jump = false
		p._spindash_release_speed = 0.0
		p._trigger_anim_command(&"CMD_RAIL")

	p._rail_speed = signed_speed
	if abs(p._rail_speed) > 0.0001:
		p._rail_travel_sign = -1.0 if p._rail_speed < 0.0 else 1.0

	var end_buffer : float = clamp(p._rail_end_detach_distance, 0.0, p._rail_total_length * 0.5)
	if end_buffer > 0.0:
		if prev_travel_sign > 0.0 and p._rail_distance >= p._rail_total_length - end_buffer:
			var exit_distance: float = p._rail_total_length
			var exit_tangent: Vector3 = _get_rail_tangent_world(curve, exit_distance, p._rail_total_length)
			if exit_tangent.length() < 0.001:
				exit_tangent = p._rail_last_tangent
			if exit_tangent.length() < 0.001 and p._rail_path != null:
				exit_tangent = -p._rail_path.global_transform.basis.z
			if exit_tangent.length() < 0.001:
				exit_tangent = Vector3.FORWARD
			exit_tangent = exit_tangent.normalized()
			p._rail_last_tangent = exit_tangent
			p._rail_last_motion_dir = exit_tangent
			p._rail_distance = exit_distance
			_finish_rail_endpoint(world_up)
			return
		if prev_travel_sign < 0.0 and p._rail_distance <= end_buffer:
			var exit_distance: float = 0.0
			var exit_tangent: Vector3 = _get_rail_tangent_world(curve, exit_distance, p._rail_total_length)
			if exit_tangent.length() < 0.001:
				exit_tangent = p._rail_last_tangent
			if exit_tangent.length() < 0.001 and p._rail_path != null:
				exit_tangent = -p._rail_path.global_transform.basis.z
			if exit_tangent.length() < 0.001:
				exit_tangent = Vector3.FORWARD
			exit_tangent = exit_tangent.normalized()
			p._rail_last_tangent = exit_tangent
			p._rail_last_motion_dir = exit_tangent * -1.0
			p._rail_distance = exit_distance
			_finish_rail_endpoint(world_up)
			return

	var next_distance: float = p._rail_distance + p._rail_speed * delta
	if next_distance < 0.0 or next_distance > p._rail_total_length:
		p._rail_distance = clamp(next_distance, 0.0, p._rail_total_length)
		var exit_sign: float = p._rail_travel_sign
		if abs(exit_sign) < 0.001:
			exit_sign = prev_travel_sign
			if abs(exit_sign) < 0.001:
				exit_sign = -1.0 if p._rail_speed < 0.0 else 1.0
		var exit_tangent: Vector3 = _get_rail_tangent_world(curve, p._rail_distance, p._rail_total_length)
		if exit_tangent.length() < 0.001:
			exit_tangent = p._rail_last_tangent
		if exit_tangent.length() < 0.001 and p._rail_path != null:
			exit_tangent = -p._rail_path.global_transform.basis.z
		if exit_tangent.length() < 0.001:
			exit_tangent = Vector3.FORWARD
		exit_tangent = exit_tangent.normalized()
		p._rail_last_tangent = exit_tangent
		p._rail_last_motion_dir = exit_tangent * exit_sign
		_finish_rail_endpoint(world_up)
		return

	p._rail_distance = next_distance

	var rail_point: Vector3 = p._rail_path.to_global(curve.sample_baked(p._rail_distance))
	var path_dir: Vector3 = _get_rail_tangent_world(curve, p._rail_distance, p._rail_total_length).normalized()
	if path_dir.length_squared() < 0.001:
		path_dir = p._rail_last_tangent.normalized()
	var up_vec: Vector3 = _sample_rail_up(p._rail_distance, path_dir, world_up)
	var motion_dir: Vector3 = path_dir * p._rail_travel_sign
	p._rail_last_tangent = path_dir
	p._rail_last_motion_dir = motion_dir
	var next_position: Vector3 = rail_point + up_vec * p._rail_attach_height
	if _try_rail_collision_handoff(next_position, up_vec, world_up):
		return
	p.visual_up = up_vec
	p.up_direction = p.visual_up

	var attach_offset: Vector3 = p.visual_up * p._rail_attach_height
	p.global_position = rail_point + attach_offset
	p.velocity = motion_dir * abs(p._rail_speed)
	p.attached = true

	if p._rail_align_model:
		# Keep visual forward aligned to the rail path, not travel direction.
		var face_dir: Vector3 = path_dir
		if spindash_on_rail:
			var desired_sign: float = _get_rail_spindash_release_sign(path_dir, world_up)
			face_dir = path_dir * desired_sign
		var f : Vector3 = face_dir - p.visual_up * face_dir.dot(p.visual_up)
		if f.length() > 0.001:
			p._model_forward = f.normalized()
		var right: Vector3 = p._model_forward.cross(p.visual_up)
		if right.length() < 0.001:
			right = Vector3.RIGHT - p.visual_up * Vector3.RIGHT.dot(p.visual_up)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		var forward: Vector3 = p.visual_up.cross(right).normalized()
		p._rail_model_basis = Basis(right, p.visual_up, -forward).orthonormalized()
		p._rail_model_basis_valid = true
	else:
		p._rail_model_basis_valid = false
	p._refresh_carried_object_target_after_external_motion()


func _end_rail(jumped: bool, world_up: Vector3) -> void:
	var p = _owner
	if not p._rail_active:
		return

	if p._rail_node != null and p._rail_node.has_method("refresh_cooldown"):
		p._rail_node.refresh_cooldown(p)
	p._rail_node = null

	p._stop_rail_grind_sfx()
	p._play_rail_detach_sfx()
	p._rail_active = false
	p._rail_anim_speed_smoothed = 0.0
	p._rail_crouching = false

	var exit_dir: Vector3 = p._rail_last_motion_dir.normalized()
	if exit_dir.length() < 0.001:
		exit_dir = -Vector3.FORWARD

	p.velocity = exit_dir * abs(p._rail_speed)
	p.attached = false
	if exit_dir.length() > 0.001:
		p._model_forward = exit_dir.normalized()

	if jumped:
		p.remove_coyote_jump_eligibility()
		var jump_dir: Vector3 = p.visual_up.normalized()
		if jump_dir.length() < 0.001:
			jump_dir = world_up.normalized()
		p.velocity += jump_dir * p.rail_jump_vertical_speed
		p._activate_jump_action_for_launch(&"rail_jump")
		p._is_jumping = true
		p._jump_variable = true
		p._jump_time = 0.0
		p._jump_hang_allowed = true
		p._just_jumped = true
		p._jump_dash_used_this_air = false
		p._tornado_kick_used_this_air = false
		p._jumped_from_ground = true
		p._falling_without_jump = false
		p.play_jump_sfx()
		p._trigger_anim_command(&"CMD_JUMP")
	else:
		p._is_jumping = false
		p._jump_variable = false
		p._jump_time = 0.0
		p._jump_dash_used_this_air = false
		p._tornado_kick_used_this_air = false
		p._jumped_from_ground = false
		p._falling_without_jump = true
		if not p._rail_switch_active:
			p.refresh_coyote_jump_window_custom(p.coyote_jump_duration)

	p.visual_up = world_up

	if p._trick_detector != null:
		p._trick_detector.reset()


func get_rail_surface_up() -> Vector3:
	var p = _owner
	if not p._rail_active or not is_instance_valid(p._rail_path):
		return p._get_gravity_up()
	return _sample_rail_up(p._rail_distance, p._rail_last_tangent, p._get_gravity_up())


func _sample_rail_up(distance: float, tangent: Vector3, world_up: Vector3) -> Vector3:
	var p = _owner
	var up: Vector3 = world_up
	if p._rail_align_to_path_tilt:
		up = RAIL_SCRIPT.sample_path_up(p._rail_path, distance)
	up = up.slide(tangent)
	if up.length_squared() < 0.000001:
		up = world_up.slide(tangent)
	if up.length_squared() < 0.000001:
		up = Vector3.RIGHT.slide(tangent)
	return up.normalized()


func _finish_rail_endpoint(world_up: Vector3) -> void:
	var p = _owner
	var tangent: Vector3 = _get_rail_tangent_world(p._rail_path.curve, p._rail_distance, p._rail_total_length).normalized()
	if tangent.length_squared() > 0.000001:
		p._rail_last_tangent = tangent
		p._rail_last_motion_dir = tangent * (-1.0 if p._rail_speed < 0.0 else 1.0)
	var up: Vector3 = _sample_rail_up(p._rail_distance, p._rail_last_tangent, world_up)
	var endpoint: Vector3 = p._rail_path.to_global(p._rail_path.curve.sample_baked(p._rail_distance))
	var origin: Vector3 = endpoint + up * p._rail_attach_height
	var hit: Dictionary = _find_handoff_surface(origin, up, _surface_handoff_search_length, world_up)
	p.global_position = origin
	_end_rail(false, world_up)
	if not hit.is_empty():
		_apply_surface_handoff(hit, up, world_up)


func _find_handoff_surface(origin: Vector3, rail_up: Vector3, extra_length: float, world_up: Vector3) -> Dictionary:
	var p = _owner
	if not _surface_handoff_enabled:
		return {}
	var length: float = max(p.collision_ground_distance, 0.0) + max(extra_length, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin - rail_up * length)
	query.collision_mask = p.collision_mask
	query.exclude = [p.get_rid()]
	for attempt: int in range(16):
		var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider: Object = hit.get("collider")
		if collider and collider.has_meta("rail_node"):
			var excluded: Array[RID] = query.exclude
			excluded.append(hit.rid)
			query.exclude = excluded
			continue
		var normal: Vector3 = hit.normal
		if normal.dot(rail_up) < cos(deg_to_rad(_surface_handoff_max_angle_deg)):
			return {}
		if p._is_surface_alignment_rejected(collider, normal, world_up, int(hit.get("shape", -1))):
			return {}
		if p._is_water_collider(collider):
			return {}
		return hit
	return {}


func _try_rail_collision_handoff(next_position: Vector3, rail_up: Vector3, world_up: Vector3) -> bool:
	var p = _owner
	if not _surface_handoff_enabled:
		return false
	var collision: KinematicCollision3D = KinematicCollision3D.new()
	var motion: Vector3 = next_position - p.global_position
	var hit: Dictionary = {}
	if p.test_move(p.global_transform, motion, collision):
		var collider: Object = collision.get_collider()
		if not (collider and collider.has_meta("rail_node")) and collision.get_normal().dot(rail_up) >= cos(deg_to_rad(_surface_handoff_max_angle_deg)):
			var contact_origin: Vector3 = p.global_position + collision.get_travel()
			hit = _find_handoff_surface(contact_origin, rail_up, _surface_handoff_search_length, world_up)
			if not hit.is_empty():
				p.global_position = contact_origin
	if hit.is_empty():
		hit = _find_handoff_surface(next_position, rail_up, 0.05, world_up)
		if hit.is_empty():
			return false
		p.global_position = next_position
	_end_rail(false, world_up)
	_apply_surface_handoff(hit, rail_up, world_up)
	return true


func _apply_surface_handoff(hit: Dictionary, rail_up: Vector3, world_up: Vector3) -> void:
	var p = _owner
	var normal: Vector3 = (hit.normal as Vector3).normalized()
	var speed: float = p.velocity.length()
	var direction: Vector3 = PlayerMath.basis_from_to(rail_up, normal) * p.velocity
	direction = direction.slide(normal)
	if direction.length_squared() > 0.000001:
		p.velocity = direction.normalized() * speed
		p._model_forward = direction.normalized()
	else:
		p.velocity = Vector3.ZERO
	p.attached = true
	p._prev_attached = true
	p.surface_normal = normal
	p._prev_surface_normal = normal
	p._smoothed_surface_normal = normal
	p.surface_point = hit.position
	p.visual_up = normal
	p.up_direction = normal
	p._attachment_immunity = 0.0
	p._airborne_time = 0.0
	p._is_falling = false
	p._falling_without_jump = false
	p._pending_landing_has_velocity = false
	p._ground_snap_attached_this_frame = true
	p._radial_attach_this_frame = true
	p._follow_hit = true
	p._follow_normal = normal
	p._follow_point = hit.position
	p._follow_collider_last = hit.collider
	p._follow_collider_shape_last = int(hit.get("shape", -1))
	p._record_attach_state(normal, world_up)
	p._lock_to_surface()
	p._refresh_carried_object_target_after_external_motion()


func _get_switch_landing_transform(rail: Node, rail_path: Path3D, offset: float) -> Transform3D:
	var p = _owner
	var curve: Curve3D = rail_path.curve
	var length: float = curve.get_baked_length()
	var before: float = clamp(offset - 0.08, 0.0, length)
	var after: float = clamp(offset + 0.08, 0.0, length)
	var tangent: Vector3 = (rail_path.to_global(curve.sample_baked(after)) - rail_path.to_global(curve.sample_baked(before))).normalized()
	if tangent.length_squared() < 0.000001:
		tangent = -rail_path.global_basis.z.normalized()
	var up: Vector3 = p._get_gravity_up()
	if rail.get("align_to_path_tilt") != false:
		up = RAIL_SCRIPT.sample_path_up(rail_path, offset)
	up = up.slide(tangent)
	if up.length_squared() < 0.000001:
		up = Vector3.RIGHT.slide(tangent)
	if up.length_squared() < 0.000001:
		up = Vector3.FORWARD.slide(tangent)
	up = up.normalized()
	var height_value: Variant = rail.get("player_height_offset")
	var height: float = float(height_value) if height_value != null else p.rail_default_attach_height
	if height <= 0.0:
		height = p.rail_default_attach_height
	var point: Vector3 = rail_path.to_global(rail_path.curve.sample_baked(offset)) + up * height
	return Transform3D(Basis.looking_at(tangent, up), point)

class_name PlayerMovementCorrection
extends RefCounted

var _owner = null
var _smoothed_correction: Vector3 = Vector3.ZERO
var _ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _wall_bounds: BoxShape3D = BoxShape3D.new()
var _wall_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()


func _init(owner) -> void:
	_owner = owner
	_ray_query.exclude = [owner.get_rid()]
	_wall_query.shape = _wall_bounds
	_wall_query.exclude = [owner.get_rid()]


func update_velocity(
	lateral: Vector3,
	input_direction: Vector3,
	input_strength: float,
	physics_up: Vector3,
	is_attached: bool,
	is_drifting: bool,
	is_rolling: bool,
	automation_active: bool,
	spring_active: bool,
	delta: float
) -> Vector3:
	var p = _owner
	_clear_debug()
	if p == null or not p.movement_correction_enabled:
		_reset_correction(delta)
		return lateral
	if not is_attached and not p.movement_correction_airborne_enabled:
		_reset_correction(delta)
		return lateral
	if p.movement_correction_block_during_automation and automation_active:
		_reset_correction(delta)
		return lateral
	if spring_active or p._rail_active or p._spline_active or p._homing_active:
		_reset_correction(delta)
		return lateral
	if p._bounce_state != p.BounceState.NONE or p._hurt_active or p._is_dead:
		_reset_correction(delta)
		return lateral

	var speed: float = lateral.length()
	var minimum_speed: float = max(p.movement_correction_min_speed, 0.0)
	if speed < minimum_speed or speed <= 0.001:
		_reset_correction(delta)
		return lateral
	var world: World3D = p.get_world_3d()
	if world == null:
		_reset_correction(delta)
		return lateral

	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()
	var forward: Vector3 = lateral - up * lateral.dot(up)
	if forward.length() < 0.001:
		_reset_correction(delta)
		return lateral
	forward = forward.normalized()
	var side_axis: Vector3 = forward.cross(up).normalized()
	if side_axis.length() < 0.001:
		_reset_correction(delta)
		return lateral

	var radius: float = _get_player_radius()
	var minimum_lookahead: float = radius * max(p.movement_correction_min_lookahead_radii, 0.1)
	var maximum_lookahead: float = radius * max(
		p.movement_correction_max_lookahead_radii,
		p.movement_correction_min_lookahead_radii
	)
	var lookahead: float = clamp(
		speed * max(p.movement_correction_lookahead_time, 0.0),
		minimum_lookahead,
		maximum_lookahead
	)
	var side_distance: float = radius * max(p.movement_correction_side_probe_radii, 0.1)
	var probe_origin: Vector3 = p.global_position + up * radius * max(p.movement_correction_probe_height_radii, 0.0)
	p._movement_correction_debug_origin = probe_origin

	var correction: Vector3 = Vector3.ZERO
	var terrain_mask: int = p.movement_correction_terrain_collision_mask
	if terrain_mask == 0:
		if p.ground_ray != null:
			terrain_mask = p.ground_ray.collision_mask | p.non_alignable_surface_mask
		else:
			terrain_mask = p.collision_mask
		terrain_mask &= ~p.movement_correction_surface_collision_mask
	var terrain_enabled: bool = (
		p.movement_correction_terrain_enabled
		and p.movement_correction_terrain_strength > 0.0
		and terrain_mask != 0
	)
	var surfaces_enabled: bool = (
		p.movement_correction_surfaces_enabled
		and p.movement_correction_surface_strength > 0.0
		and p.movement_correction_surface_collision_mask != 0
	)
	var wall_mask: int = terrain_mask if terrain_enabled else 0
	if surfaces_enabled:
		wall_mask |= p.movement_correction_surface_collision_mask
	var has_wall_candidates: bool = wall_mask != 0
	if (
		has_wall_candidates
		and p.movement_correction_empty_space_check_enabled
		and not (p._debug_visible and p.movement_correction_debug_guides_enabled)
	):
		has_wall_candidates = _has_wall_candidates(
			world.direct_space_state, probe_origin, forward, side_axis, up,
			lookahead, side_distance, wall_mask, terrain_enabled, surfaces_enabled
		)
	if has_wall_candidates and terrain_enabled:
		correction += _sample_wall_mask(
			world.direct_space_state,
			probe_origin,
			forward,
			side_axis,
			up,
			lookahead,
			side_distance,
			terrain_mask,
			max(p.movement_correction_terrain_strength, 0.0),
			&"terrain",
			speed
		)
	if has_wall_candidates and surfaces_enabled:
		correction += _sample_wall_mask(
			world.direct_space_state,
			probe_origin,
			forward,
			side_axis,
			up,
			lookahead,
			side_distance,
			p.movement_correction_surface_collision_mask,
			max(p.movement_correction_surface_strength, 0.0),
			&"surface",
			speed
		)
	if p.movement_correction_ledges_enabled and p.movement_correction_ledge_strength > 0.0 and is_attached and terrain_mask != 0:
		correction += _sample_ledge_correction(
			world.direct_space_state,
			probe_origin,
			forward,
			side_axis,
			up,
			lookahead,
			side_distance,
			radius,
			terrain_mask
		) * max(p.movement_correction_ledge_strength, 0.0)

	var max_strength: float = max(p.movement_correction_max_combined_strength, 0.0)
	if max_strength > 0.0 and correction.length() > max_strength:
		correction = correction.normalized() * max_strength
	var response_t: float = clamp(max(p.movement_correction_response, 0.0) * max(delta, 0.0), 0.0, 1.0)
	_smoothed_correction = _smoothed_correction.lerp(correction, response_t)
	_smoothed_correction -= up * _smoothed_correction.dot(up)
	if _smoothed_correction.length() <= 0.001:
		return lateral

	var correction_direction: Vector3 = _smoothed_correction.normalized()
	var input_multiplier: float = _get_input_multiplier(
		input_direction,
		input_strength,
		correction_direction,
		up
	)
	var state_multiplier: float = 1.0
	if is_attached and not is_drifting and not is_rolling:
		state_multiplier *= max(p.movement_correction_neutral_grounded_multiplier, 0.0)
	if is_drifting:
		state_multiplier *= max(p.movement_correction_drift_multiplier, 0.0)
	if is_rolling:
		state_multiplier *= max(p.movement_correction_roll_multiplier, 0.0)
	var speed_t: float = _inverse_lerp_clamped(
		minimum_speed,
		max(p.movement_correction_full_strength_speed, minimum_speed + 0.001),
		speed
	)
	var acceleration: float = lerp(
		max(p.movement_correction_low_speed_accel, 0.0),
		max(p.movement_correction_high_speed_accel, 0.0),
		speed_t
	)
	var push_strength: float = _smoothed_correction.length() * input_multiplier * state_multiplier
	var pushed: Vector3 = lateral + correction_direction * acceleration * push_strength * max(delta, 0.0)
	pushed -= up * pushed.dot(up)
	if pushed.length() < 0.001:
		return lateral

	var desired_direction: Vector3 = pushed.normalized()
	var current_direction: Vector3 = lateral.normalized()
	var angle: float = acos(clamp(current_direction.dot(desired_direction), -1.0, 1.0))
	var max_turn: float = deg_to_rad(max(p.movement_correction_max_turn_deg_per_sec, 0.0)) * max(delta, 0.0)
	if max_turn > 0.0 and angle > max_turn:
		desired_direction = current_direction.slerp(desired_direction, max_turn / angle).normalized()
	p._movement_correction_debug_push = correction_direction * push_strength
	return desired_direction * speed


func _has_wall_candidates(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	forward: Vector3,
	side_axis: Vector3,
	up: Vector3,
	lookahead: float,
	side_distance: float,
	mask: int,
	terrain_enabled: bool,
	surfaces_enabled: bool
) -> bool:
	var bounds_size: Vector3 = Vector3(side_distance * 2.0 + 0.02, 0.02, lookahead + 0.02)
	if _wall_bounds.size != bounds_size:
		_wall_bounds.size = bounds_size
	_wall_query.transform = Transform3D(Basis(side_axis, up, -forward), origin + forward * lookahead * 0.5)
	_wall_query.collision_mask = mask
	_wall_query.collide_with_bodies = terrain_enabled
	_wall_query.collide_with_areas = surfaces_enabled
	return not space.intersect_shape(_wall_query, 1).is_empty()


func _sample_wall_mask(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	forward: Vector3,
	side_axis: Vector3,
	up: Vector3,
	lookahead: float,
	side_distance: float,
	mask: int,
	base_strength: float,
	kind: StringName,
	speed: float
) -> Vector3:
	var p = _owner
	var result: Vector3 = Vector3.ZERO
	var sample_count: int = max(p.movement_correction_wall_sample_count, 1)
	for side: int in [-1, 1]:
		var best: Vector3 = Vector3.ZERO
		var best_strength: float = 0.0
		for sample_index: int in range(sample_count):
			var forward_ratio: float = float(sample_index) / float(max(sample_count - 1, 1))
			var sample_origin: Vector3 = origin + forward * lookahead * forward_ratio
			var sample_end: Vector3 = sample_origin + side_axis * side_distance * float(side)
			var hit: Dictionary = _cast_ray(space, sample_origin, sample_end, mask, kind == &"surface")
			_store_debug_ray(sample_origin, sample_end, not hit.is_empty(), kind)
			if hit.is_empty():
				continue
			var full_normal: Vector3 = hit.get("normal", Vector3.ZERO)
			if full_normal.length() < 0.001:
				continue
			if abs(full_normal.normalized().dot(up)) > clamp(p.movement_correction_wall_max_up_dot, 0.0, 1.0):
				continue
			var normal: Vector3 = full_normal - up * full_normal.dot(up)
			if normal.length() < 0.001:
				continue
			normal = normal.normalized()
			var side_alignment: float = -normal.dot(side_axis * float(side))
			if side_alignment <= 0.05:
				continue
			var hit_position: Vector3 = hit.get("position", sample_end)
			var proximity: float = 1.0 - clamp(sample_origin.distance_to(hit_position) / max(side_distance, 0.001), 0.0, 1.0)
			var distance_strength: float = _get_distance_strength(proximity)
			var prediction_weight: float = lerp(1.0, 0.6, forward_ratio)
			var surface_multiplier: float = _get_surface_strength(hit.get("collider"), speed, kind)
			var strength: float = distance_strength * side_alignment * prediction_weight * base_strength * surface_multiplier
			if strength > best_strength:
				best_strength = strength
				best = normal * strength
		result += best
	return result


func _get_distance_strength(proximity: float) -> float:
	var p = _owner
	var distance_t: float = clamp(proximity, 0.0, 1.0)
	var near_multiplier: float = max(p.movement_correction_near_surface_multiplier, 0.0)
	var power: float = max(p.movement_correction_near_surface_power, 0.001)
	var near_weight: float = pow(distance_t, power)
	return distance_t * lerp(1.0, near_multiplier, near_weight)


func _sample_ledge_correction(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	forward: Vector3,
	side_axis: Vector3,
	up: Vector3,
	lookahead: float,
	side_distance: float,
	radius: float,
	terrain_mask: int
) -> Vector3:
	var p = _owner
	var support: Dictionary = {}
	var forward_distance: float = lookahead * clamp(p.movement_correction_ledge_lookahead_ratio, 0.0, 1.0)
	var cast_depth: float = max(p.collision_ground_distance, radius)
	cast_depth += radius * max(p.movement_correction_ledge_probe_depth_radii, 0.0)
	for side: int in [-1, 1]:
		var probe_center: Vector3 = origin + forward * forward_distance + side_axis * side_distance * float(side)
		var ray_start: Vector3 = probe_center + up * radius * 0.25
		var ray_end: Vector3 = probe_center - up * cast_depth
		var hit: Dictionary = _cast_ray(space, ray_start, ray_end, terrain_mask)
		var supported: bool = false
		if not hit.is_empty():
			var normal: Vector3 = hit.get("normal", Vector3.ZERO)
			supported = normal.length() > 0.001 and normal.normalized().dot(up) >= p.movement_correction_ledge_min_support_dot
		support[side] = supported
		_store_debug_ray(ray_start, ray_end, supported, &"ledge")
	var left_supported: bool = bool(support.get(-1, false))
	var right_supported: bool = bool(support.get(1, false))
	if left_supported == right_supported:
		return Vector3.ZERO
	return -side_axis if left_supported else side_axis


func _cast_ray(
	space: PhysicsDirectSpaceState3D,
	from_position: Vector3,
	to_position: Vector3,
	mask: int,
	areas_only: bool = false
) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = _ray_query
	query.from = from_position
	query.to = to_position
	query.collision_mask = mask
	query.collide_with_areas = areas_only
	query.collide_with_bodies = not areas_only
	query.hit_back_faces = true
	return space.intersect_ray(query)


func _get_input_multiplier(
	input_direction: Vector3,
	input_strength: float,
	correction_direction: Vector3,
	up: Vector3
) -> float:
	var p = _owner
	var planar_input: Vector3 = input_direction - up * input_direction.dot(up)
	var strength: float = clamp(input_strength, 0.0, 1.0)
	if planar_input.length() < 0.001 or strength <= 0.001:
		return 1.0
	var alignment: float = planar_input.normalized().dot(correction_direction) * strength
	if alignment >= 0.0:
		return lerp(1.0, max(p.movement_correction_input_away_multiplier, 0.0), alignment)
	return lerp(1.0, clamp(p.movement_correction_input_toward_multiplier, 0.0, 1.0), -alignment)


func _get_surface_strength(collider: Object, speed: float, kind: StringName) -> float:
	if kind != &"surface" or collider == null:
		return 1.0
	if collider.has_method("get_movement_correction_strength"):
		return max(float(collider.call("get_movement_correction_strength", speed)), 0.0)
	return 1.0


func _get_player_radius() -> float:
	var p = _owner
	if p._surface_preview_world_radius > 0.0:
		return max(p._surface_preview_world_radius, 0.05)
	return max(p.collision_ground_distance, 0.05)


func _reset_correction(delta: float) -> void:
	if _owner == null:
		_smoothed_correction = Vector3.ZERO
		return
	var response_t: float = clamp(max(_owner.movement_correction_response, 0.0) * max(delta, 0.0), 0.0, 1.0)
	_smoothed_correction = _smoothed_correction.lerp(Vector3.ZERO, response_t)
	_owner._movement_correction_debug_push = Vector3.ZERO


func _clear_debug() -> void:
	if _owner != null:
		_owner._movement_correction_debug_rays.clear()
		_owner._movement_correction_debug_push = Vector3.ZERO


func _store_debug_ray(from_position: Vector3, to_position: Vector3, hit: bool, kind: StringName) -> void:
	if not _owner.movement_correction_debug_guides_enabled or not _owner._debug_visible:
		return
	_owner._movement_correction_debug_rays.append({
		"from": from_position,
		"to": to_position,
		"hit": hit,
		"kind": kind,
	})


func _inverse_lerp_clamped(from_value: float, to_value: float, value: float) -> float:
	if is_equal_approx(from_value, to_value):
		return 1.0
	return clamp((value - from_value) / (to_value - from_value), 0.0, 1.0)

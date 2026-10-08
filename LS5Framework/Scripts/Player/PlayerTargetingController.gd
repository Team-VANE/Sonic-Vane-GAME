extends RefCounted
class_name PlayerTargetingController

const CharacterActionType = preload("res://LS5Framework/Scripts/Player/character_action.gd")

# Homing, attack magnetism, and lightspeed-dash target resolution.
var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func has_homing_target_in_range() -> bool:
	var p = _owner
	if not p._can_scan_homing_targets():
		return false
	if p.attached:
		return false
	var speed_now: float = p.velocity.length()
	var max_range: float = p.homing_min_range + speed_now * p.homing_range_per_speed
	max_range = clamp(max_range, p.homing_min_range, p.homing_max_range)
	var status: Dictionary = get_homing_target_request_status(p.global_position, max_range, false)
	return bool(status.get("ready", false)) and status.get("target") is Node3D


func get_homing_target_request_status(origin: Vector3, max_range: float, wait_for_next_scan: bool = true) -> Dictionary:
	var p = _owner
	var now_ms: int = Time.get_ticks_msec()
	var mode: int = SettingsManager.get_active_homing_targeting_mode()
	if _is_homing_target_scan_due(now_ms, mode):
		var updated_target: Node3D = _run_scheduled_homing_target_scan(origin, max_range, now_ms, mode)
		if wait_for_next_scan:
			clear_homing_target_request_buffer()
		return {"ready": true, "target": updated_target}
	var cached_target: Node3D = _get_valid_cached_homing_target(origin, max_range, mode)
	if cached_target != null:
		if wait_for_next_scan:
			clear_homing_target_request_buffer()
		return {"ready": true, "target": cached_target}
	if wait_for_next_scan:
		if not p._homing_target_request_buffer_active:
			p._homing_target_request_buffer_active = true
			p._homing_target_request_scan_time_ms = p._homing_reticle_cached_time_ms
		elif p._homing_target_scan_initialized and p._homing_reticle_cached_time_ms != p._homing_target_request_scan_time_ms:
			clear_homing_target_request_buffer()
			return {"ready": true, "target": null}
		return {"ready": false, "target": null}
	return {"ready": true, "target": null}


func clear_homing_target_request_buffer() -> void:
	var p = _owner
	p._homing_target_request_buffer_active = false
	p._homing_target_request_scan_time_ms = 0


func _is_homing_target_scan_due(now_ms: int, _mode: int) -> bool:
	var p = _owner
	if not p._homing_target_scan_initialized:
		return true
	return now_ms - p._homing_reticle_cached_time_ms >= p.HOMING_RETICLE_CACHE_MS


func _run_scheduled_homing_target_scan(origin: Vector3, max_range: float, now_ms: int, mode: int) -> Node3D:
	var p = _owner
	var target: Node3D = _select_homing_target(origin, max_range)
	p._homing_reticle_cached_target = target
	p._homing_reticle_cached_time_ms = now_ms
	p._homing_target_scan_initialized = true
	p._homing_reticle_cached_mode = mode
	return target


func _get_valid_cached_homing_target(origin: Vector3, max_range: float, mode: int) -> Node3D:
	var p = _owner
	if not p._homing_target_scan_initialized or mode != p._homing_reticle_cached_mode:
		return null
	var target: Node3D = p._homing_reticle_cached_target
	if target == null or not is_instance_valid(target):
		return null
	if not target.is_in_group("HomingTarget"):
		return null
	if p._object_has_property(target, "enabled") and not bool(target.get("enabled")):
		return null
	if p._object_has_property(target, "active") and not bool(target.get("active")):
		return null
	var target_position: Vector3 = _get_homing_candidate_position(target, origin)
	if _get_homing_target_max_distance(target) > 0.0:
		target_position = _refresh_homing_candidate_position(target, origin)
		if not _is_homing_target_within_max_distance(target, target_position.distance_squared_to(origin)):
			return null
	if target_position.distance_squared_to(origin) > max_range * max_range:
		return null
	return target


func _get_homing_target_max_distance(target: Node3D) -> float:
	if not _owner._object_has_property(target, "homing_target_max_distance"):
		return 0.0
	return maxf(float(target.get("homing_target_max_distance")), 0.0)


func _is_homing_target_within_max_distance(target: Node3D, distance_squared: float) -> bool:
	var max_distance: float = _get_homing_target_max_distance(target)
	return max_distance <= 0.0 or distance_squared <= max_distance * max_distance


func _get_homing_target_position(target: Node3D, origin: Vector3) -> Vector3:
	var p = _owner
	if target != null and is_instance_valid(target) and target.has_method("get_homing_target_position"):
		var position: Variant = target.call("get_homing_target_position", origin)
		if position is Vector3:
			return position
	if target != null and is_instance_valid(target):
		return target.global_position
	return origin


func _get_homing_target_position_for_aim(target: Node3D, origin: Vector3, aim_origin: Vector3, aim_dir: Vector3) -> Vector3:
	var p = _owner
	if target != null and is_instance_valid(target) and target.has_method("get_homing_target_position_for_aim"):
		var position: Variant = target.call("get_homing_target_position_for_aim", aim_origin, aim_dir)
		if position is Vector3:
			return position
	return _get_homing_target_position(target, origin)


func _is_rail_like_homing_target(target: Node) -> bool:
	var p = _owner
	return target != null and (
		target.has_method("try_start_with_body_proximity")
		or target.has_method("get_closest_point_on_path")
	)


func _set_homing_candidate_position(target: Node3D, position: Vector3) -> void:
	var p = _owner
	if target == null or not is_instance_valid(target):
		return
	p._homing_target_candidate_positions[target.get_instance_id()] = position


func _get_homing_candidate_position(target: Node3D, origin: Vector3) -> Vector3:
	var p = _owner
	if target != null and is_instance_valid(target):
		var id: int = target.get_instance_id()
		if p._homing_target_candidate_positions.has(id):
			var position: Variant = p._homing_target_candidate_positions[id]
			if position is Vector3:
				return position
	return _get_homing_target_position(target, origin)


func _smoothstep_homing(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _get_homing_camera_context() -> Dictionary:
	var p = _owner
	var cam: Camera3D = p.camera
	if not cam:
		var viewport: Viewport = p.get_viewport()
		if viewport:
			cam = viewport.get_camera_3d()
	if not cam:
		return {}

	var camera_viewport: Viewport = cam.get_viewport()
	if not camera_viewport:
		return {}
	var viewport_size: Vector2 = camera_viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return {}

	var center: Vector2 = viewport_size * 0.5
	var offset_t: float = clamp(SettingsManager.reticle_vertical_offset, 0.0, 100.0) / 100.0
	center.y -= 0.5 * viewport_size.y * offset_t
	var aim_origin: Vector3 = cam.project_ray_origin(center)
	var aim_dir: Vector3 = cam.project_ray_normal(center)
	if aim_dir.length() < 0.001:
		aim_dir = -cam.global_transform.basis.z
	if aim_dir.length() < 0.001:
		aim_dir = Vector3.FORWARD

	return {
		"camera": cam,
		"viewport_size": viewport_size,
		"center": center,
		"aim_origin": aim_origin,
		"camera_aim_dir": aim_dir.normalized()
	}


func _get_homing_hybrid_context(origin: Vector3) -> Dictionary:
	var p = _owner
	var context: Dictionary = _get_homing_camera_context()
	if context.is_empty():
		var fallback_dir: Vector3 = _get_homing_target_direction()
		if fallback_dir.length() < 0.001:
			fallback_dir = -Vector3.FORWARD
		return {
			"camera": null,
			"viewport_size": Vector2.ZERO,
			"center": Vector2.ZERO,
			"aim_origin": origin,
			"camera_aim_dir": fallback_dir.normalized(),
			"aim_dir": fallback_dir.normalized(),
			"camera_weight": 0.0
		}

	var camera_aim_dir: Vector3 = context.get("camera_aim_dir", Vector3.FORWARD)
	var camera_aim_origin: Vector3 = context.get("aim_origin", origin)
	var up: Vector3 = p._get_gravity_up().normalized()
	if up.length() < 0.001:
		up = Vector3.UP
	var camera_flat: Vector3 = camera_aim_dir - up * camera_aim_dir.dot(up)
	if camera_flat.length() < 0.001:
		camera_flat = p._get_camera_forward_world_up(up)
	if camera_flat.length() < 0.001:
		camera_flat = -Vector3.FORWARD
	camera_flat = camera_flat.normalized()

	var input_strength: float = clamp(p._move_input.length(), 0.0, 1.0)
	var camera_right: Vector3 = camera_flat.cross(up)
	if camera_right.length() >= 0.001:
		camera_right = camera_right.normalized()
	var input_flat: Vector3 = camera_flat * p._move_input.y + camera_right * p._move_input.x
	if input_flat.length() < 0.001:
		input_flat = p._move_direction - up * p._move_direction.dot(up)
	var input_threshold: float = clamp(p.homing_hybrid_input_min_strength, 0.0, 1.0)
	if input_strength <= input_threshold or input_flat.length() < 0.001:
		context["aim_dir"] = camera_aim_dir
		context["camera_weight"] = 1.0
		return context
	input_flat = input_flat.normalized()

	var signed_deviation: float = camera_flat.signed_angle_to(input_flat, up)
	var deviation: float = abs(signed_deviation)
	var camera_priority_angle: float = deg_to_rad(clamp(p.homing_hybrid_camera_priority_angle_deg, 0.0, 180.0))
	var full_input_angle: float = deg_to_rad(clamp(p.homing_hybrid_full_input_angle_deg, 0.0, 180.0))
	full_input_angle = max(full_input_angle, camera_priority_angle + 0.001)
	var angle_weight: float = _smoothstep_homing((deviation - camera_priority_angle) / (full_input_angle - camera_priority_angle))
	var strength_weight: float = 1.0
	if input_threshold < 0.999:
		strength_weight = _smoothstep_homing((input_strength - input_threshold) / (1.0 - input_threshold))
	var input_weight: float = angle_weight * strength_weight

	var aim_dir: Vector3 = camera_aim_dir.rotated(up, signed_deviation * input_weight).normalized()
	context["aim_origin"] = camera_aim_origin.lerp(origin, input_weight)
	context["aim_dir"] = aim_dir
	context["camera_weight"] = 1.0 - input_weight
	return context


func _get_homing_selection_aim_direction(mode: int, origin: Vector3) -> Vector3:
	if mode == SettingsManager.HOMING_TARGETING_HYBRID:
		var hybrid_context: Dictionary = _get_homing_hybrid_context(origin)
		var hybrid_aim_direction: Vector3 = hybrid_context.get("aim_dir", Vector3.ZERO)
		return hybrid_aim_direction
	if mode == SettingsManager.HOMING_TARGETING_CAMERA:
		var camera_context: Dictionary = _get_homing_camera_context()
		var camera_aim_direction: Vector3 = camera_context.get("camera_aim_dir", Vector3.ZERO)
		return camera_aim_direction
	return _get_homing_target_direction()


func _refresh_homing_candidate_position(target: Node3D, origin: Vector3) -> Vector3:
	var p = _owner
	if target == null or not is_instance_valid(target):
		return origin

	var mode: int = SettingsManager.get_active_homing_targeting_mode()
	var position: Vector3 = target.global_position
	if mode == SettingsManager.HOMING_TARGETING_CAMERA:
		var cam: Camera3D = p.camera
		if cam == null:
			var vp: Viewport = p.get_viewport()
			if vp != null:
				cam = vp.get_camera_3d()
		if cam != null:
			var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size
			if vp_size.x > 0.0 and vp_size.y > 0.0:
				var center: Vector2 = vp_size * 0.5
				var offset_t: float = clamp(SettingsManager.reticle_vertical_offset, 0.0, 100.0) / 100.0
				center.y += -0.5 * vp_size.y * offset_t
				var aim_origin: Vector3 = cam.project_ray_origin(center)
				var aim_dir: Vector3 = cam.project_ray_normal(center)
				if aim_dir.length() < 0.001:
					aim_dir = -cam.global_transform.basis.z
				position = _get_homing_target_position_for_aim(target, origin, aim_origin, aim_dir)
			else:
				position = _get_homing_target_position(target, origin)
		else:
			position = _get_homing_target_position(target, origin)
	elif mode == SettingsManager.HOMING_TARGETING_HYBRID:
		var hybrid_context: Dictionary = _get_homing_hybrid_context(origin)
		var hybrid_origin: Vector3 = hybrid_context.get("aim_origin", origin)
		var hybrid_dir: Vector3 = hybrid_context.get("aim_dir", _get_homing_target_direction())
		if hybrid_dir.length() < 0.001:
			hybrid_dir = -Vector3.FORWARD
		position = _get_homing_target_position_for_aim(target, origin, hybrid_origin, hybrid_dir)
	else:
		var dash_dir: Vector3 = _get_homing_target_direction()
		if dash_dir.length() < 0.001:
			dash_dir = -Vector3.FORWARD
		position = _get_homing_target_position_for_aim(target, origin, origin, dash_dir)

	_set_homing_candidate_position(target, position)
	return position


func get_homing_attack_target_position() -> Vector3:
	var p = _owner
	if p._homing_target_position_valid:
		return p._homing_target_position
	if p._homing_target != null and is_instance_valid(p._homing_target) and p._homing_target is Node3D:
		return _get_homing_target_position(p._homing_target as Node3D, p.global_position)
	return p.global_position


func get_homing_reticle_target_position(target: Node3D) -> Vector3:
	var p = _owner
	return _get_homing_candidate_position(target, p.global_position)


func _apply_attack_magnetism(delta: float, physics_up: Vector3, current_velocity: Vector3) -> Vector3:
	var p = _owner
	p._attack_magnetism_target = null
	p._attack_magnetism_target_position = Vector3.ZERO
	p._attack_magnetism_strength_current = 0.0
	if delta > 0.0:
		_tick_attack_magnetism_bounce_compensation(delta)
	if not _can_apply_attack_magnetism():
		p._attack_magnetism_scan_result.clear()
		p._attack_magnetism_scan_timer = 0.0
		return current_velocity
	if delta <= 0.0:
		return current_velocity

	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var heading: Vector3 = _get_attack_magnetism_heading(current_velocity)
	if heading.length() < 0.001:
		return current_velocity

	var result: Dictionary = _get_attack_magnetism_scan_result(delta, heading.normalized(), up, current_velocity)
	if result.is_empty():
		return current_velocity

	var target: Node3D = result.get("target", null) as Node3D
	if target == null:
		return current_velocity

	var target_position: Vector3 = result.get("position", target.global_position)
	var to_target: Vector3 = target_position - p.global_position
	var dist: float = to_target.length()
	if dist <= 0.001:
		return current_velocity

	var target_dir: Vector3 = to_target / dist
	var min_speed: float = _get_attack_magnetism_setting(target, "attack_magnetism_min_speed", p.attack_magnetism_min_speed)
	var target_speed: float = max(current_velocity.length(), max(min_speed, 0.0))
	if target_speed <= 0.001:
		return current_velocity

	var strength: float = float(result.get("strength", 0.0))
	if strength <= 0.0:
		return current_velocity

	p._attack_magnetism_target = target
	p._attack_magnetism_target_position = target_position
	p._attack_magnetism_strength_current = strength

	var desired_velocity: Vector3 = target_dir * target_speed
	var adjusted_velocity: Vector3 = current_velocity.move_toward(desired_velocity, strength * delta)
	var previous_descent: float = max(-current_velocity.dot(up), 0.0)
	var adjusted_descent: float = max(-adjusted_velocity.dot(up), 0.0)
	var lost_descent: float = max(previous_descent - adjusted_descent, 0.0)
	if lost_descent > 0.0:
		_store_attack_magnetism_bounce_compensation(lost_descent)
	return adjusted_velocity


func _tick_attack_magnetism_bounce_compensation(delta: float) -> void:
	var p = _owner
	if p._attack_magnetism_bounce_compensation_timer <= 0.0:
		p._attack_magnetism_bounce_descent_compensation = 0.0
		return
	p._attack_magnetism_bounce_compensation_timer = max(p._attack_magnetism_bounce_compensation_timer - p.get_gameplay_timer_delta(delta), 0.0)
	if p._attack_magnetism_bounce_compensation_timer <= 0.0:
		p._attack_magnetism_bounce_descent_compensation = 0.0


func _store_attack_magnetism_bounce_compensation(lost_descent: float) -> void:
	var p = _owner
	var gain: float = max(p.attack_magnetism_bounce_lost_descent_gain, 0.0)
	if gain <= 0.0:
		return
	p._attack_magnetism_bounce_descent_compensation += max(lost_descent, 0.0) * gain
	p._attack_magnetism_bounce_compensation_timer = max(p.attack_magnetism_bounce_compensation_time, 0.0)


func _consume_attack_magnetism_bounce_compensation() -> float:
	var p = _owner
	var compensation: float = p._attack_magnetism_bounce_descent_compensation
	p._attack_magnetism_bounce_descent_compensation = 0.0
	p._attack_magnetism_bounce_compensation_timer = 0.0
	return max(compensation, 0.0)


func _get_attack_magnetism_scan_result(delta: float, heading: Vector3, up: Vector3, current_velocity: Vector3) -> Dictionary:
	var p = _owner
	var interval: float = 0.0
	if p.attack_magnetism_target_update_rate_hz > 0.0:
		interval = 1.0 / p.attack_magnetism_target_update_rate_hz
	p._attack_magnetism_scan_timer -= p.get_gameplay_timer_delta(delta)

	if p._attack_magnetism_scan_timer > 0.0 and _is_attack_magnetism_scan_result_valid():
		return p._attack_magnetism_scan_result

	p._attack_magnetism_scan_timer = interval
	p._attack_magnetism_scan_result = _select_attack_magnetism_target(p.global_position, heading, up, current_velocity)
	return p._attack_magnetism_scan_result


func _is_attack_magnetism_scan_result_valid() -> bool:
	var p = _owner
	if p._attack_magnetism_scan_result.is_empty():
		return false
	var target: Node3D = p._attack_magnetism_scan_result.get("target", null) as Node3D
	if target == null or not is_instance_valid(target):
		return false
	return _is_attack_magnetism_target_available(target)


func _can_apply_attack_magnetism() -> bool:
	var p = _owner
	if not p.attack_magnetism_enabled:
		return false
	if p.attack_magnetism_player_controlled_only and not _is_player_controlled_targeting_owner():
		return false
	if p.attached:
		return false
	if p._is_dead or p._hurt_active:
		return false
	if p._homing_active or p._lightspeed_dash_active:
		return false
	if p._rail_active or p._rail_switch_active or p._spline_active:
		return false
	if p._spring_align_timer > 0.0 or p._spring_movement_lock_timer > 0.0 or p._spring_action_lock_timer > 0.0:
		return false
	if p._ramp_hold_forward_timer > 0.0 or p._ramp_hold_up_timer > 0.0:
		return false
	if p._automation_lock_movement and p._automation_locks_active():
		return false
	if not _current_action_permits_attack_magnetism():
		return false
	return _is_attack_magnetism_attack_state_active()


func _is_player_controlled_targeting_owner() -> bool:
	var p = _owner
	if p.has_meta("is_buddy") and bool(p.get_meta("is_buddy")):
		return false
	if p.has_meta("is_rival_actor") and bool(p.get_meta("is_rival_actor")):
		return false
	return p._network_is_local_authority()


func _current_action_permits_attack_magnetism() -> bool:
	var p = _owner
	if p._active_action == null or not is_instance_valid(p._active_action):
		return false
	if not (p._active_action is CharacterActionType):
		return false
	var permits: Variant = p._active_action.get("permits_attack_magnetism")
	return permits is bool and bool(permits)


func _is_attack_magnetism_attack_state_active() -> bool:
	var p = _owner
	if p.is_attack_active():
		return true
	if p._jumped_from_ground:
		return true
	if p.rolling:
		return true
	if p._jump_dash_recent_timer > 0.0:
		return true
	if p._bounce_state != p.BounceState.NONE:
		return true
	if p._enemy_attack_chain_active and not p.attached:
		return true
	if p._active_action != null and is_instance_valid(p._active_action):
		if p._active_action.has_method("get") and "combat_class" in p._active_action:
			return int(p._active_action.get("combat_class")) != p.CombatClass.NEUTRAL
	return false


func _is_homing_target_obstructed(origin: Vector3, target_position: Vector3, target: Node3D) -> bool:
	var p = _owner
	if not p.homing_obstruction_check:
		return false
	var target_distance: float = origin.distance_to(target_position)
	if target_distance <= 0.001:
		return false
	var world: World3D = p.get_world_3d()
	if world == null:
		return false

	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target_position)
	params.exclude = [p.get_rid()]
	params.collision_mask = p.collision_mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit: Dictionary = world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return false

	var collider: Node = hit.get("collider") as Node
	if collider != null and (
		collider == target
		or collider.is_ancestor_of(target)
		or target.is_ancestor_of(collider)
	):
		return false
	var hit_position: Variant = hit.get("position")
	if not (hit_position is Vector3):
		return true
	var obstruction_position: Vector3 = hit_position as Vector3
	var obstruction_margin: float = max(p.homing_obstruction_margin, 0.0)
	return origin.distance_to(obstruction_position) < max(target_distance - obstruction_margin, 0.0)


func _get_attack_magnetism_heading(current_velocity: Vector3) -> Vector3:
	var p = _owner
	if current_velocity.length() > 0.001:
		return current_velocity.normalized()
	if p._move_direction.length() > 0.001:
		return p._move_direction.normalized()
	if p._model_forward.length() > 0.001:
		return p._model_forward.normalized()
	return -p.global_transform.basis.z


func _select_attack_magnetism_target(origin: Vector3, heading: Vector3, up: Vector3, current_velocity: Vector3) -> Dictionary:
	var p = _owner
	var player_range: float = _get_attack_magnetism_player_range(current_velocity)
	var query_range: float = max(player_range, p.attack_magnetism_max_range)
	var candidates: Array = _get_attack_magnetism_candidates(origin, query_range)
	if candidates.is_empty():
		return {}

	var best: Node3D = null
	var best_position: Vector3 = Vector3.ZERO
	var best_score: float = -999999.0
	var best_strength: float = 0.0

	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not (candidate is Node3D):
			continue
		var target: Node3D = candidate as Node3D
		if not _is_attack_magnetism_target_available(target):
			continue

		var target_range: float = _get_attack_magnetism_setting(target, "attack_magnetism_range", player_range)
		target_range = max(target_range, 0.0)
		if target_range <= 0.0:
			continue
		var target_position: Vector3 = _get_attack_magnetism_target_position(target)
		var to_target: Vector3 = target_position - origin
		var dist: float = to_target.length()
		if dist <= 0.001 or dist > target_range:
			continue

		var target_dir: Vector3 = to_target / dist
		var angle_deg: float = _get_attack_magnetism_setting(target, "attack_magnetism_detection_angle_deg", p.attack_magnetism_detection_angle_deg)
		angle_deg = clamp(angle_deg, 0.0, 180.0)
		var min_dot: float = cos(deg_to_rad(angle_deg))
		var heading_dot: float = clamp(target_dir.dot(heading), -1.0, 1.0)
		if heading_dot < min_dot:
			continue

		var input_factor: float = _get_attack_magnetism_input_factor(target_dir, up)
		if input_factor <= 0.0:
			continue

		var heading_factor: float = 1.0
		if min_dot < 0.999:
			heading_factor = clamp((heading_dot - min_dot) / (1.0 - min_dot), 0.0, 1.0)
		var descent_factor: float = _get_attack_magnetism_descent_factor(current_velocity, up)
		var distance_factor: float = lerp(1.0, 0.65, clamp(dist / target_range, 0.0, 1.0))
		var base_strength: float = _get_attack_magnetism_setting(target, "attack_magnetism_strength", p.attack_magnetism_strength)
		var strength_multiplier: float = 1.0
		if p._object_has_property(target, "attack_magnetism_strength_multiplier"):
			strength_multiplier = max(float(target.get("attack_magnetism_strength_multiplier")), 0.0)
		var strength: float = max(base_strength, 0.0) * strength_multiplier * heading_factor * input_factor * descent_factor * distance_factor
		if strength <= 0.0:
			continue

		var input_score: float = min(input_factor, 2.0)
		var score: float = heading_factor * 10000.0 + input_score * 100.0 - (dist / target_range) * 10.0
		if score > best_score:
			best_score = score
			best = target
			best_position = target_position
			best_strength = strength

	if best == null:
		return {}
	return {
		"target": best,
		"position": best_position,
		"strength": best_strength,
	}


func _get_attack_magnetism_player_range(current_velocity: Vector3) -> float:
	var p = _owner
	var min_range: float = max(p.attack_magnetism_range, 0.0)
	var max_range: float = max(p.attack_magnetism_max_range, min_range)
	var speed_range: float = min_range + current_velocity.length() * max(p.attack_magnetism_range_per_speed, 0.0)
	return clamp(speed_range, min_range, max_range)


func _get_attack_magnetism_candidates(origin: Vector3, max_range: float) -> Array:
	var p = _owner
	var candidates: Array = []
	var seen: Dictionary = {}
	var mgr = p.get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("get_attack_magnetism_targets_in_range"):
		for target in mgr.get_attack_magnetism_targets_in_range(origin, max_range):
			_add_attack_magnetism_candidate(candidates, seen, target)
		return candidates
	var tree: SceneTree = p.get_tree()
	if tree == null:
		return candidates
	for target in tree.get_nodes_in_group("AttackMagnetismTarget"):
		_add_attack_magnetism_candidate(candidates, seen, target)
	return candidates


func _add_attack_magnetism_candidate(candidates: Array, seen: Dictionary, target: Node) -> void:
	var p = _owner
	if target == null or not is_instance_valid(target):
		return
	if not (target is Node3D):
		return
	var id: int = target.get_instance_id()
	if seen.has(id):
		return
	seen[id] = true
	candidates.append(target)


func _is_attack_magnetism_target_available(target: Node3D) -> bool:
	var p = _owner
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_in_group("AttackMagnetismTarget"):
		return false
	if p._object_has_property(target, "enabled") and not bool(target.get("enabled")):
		return false
	if p._object_has_property(target, "active") and not bool(target.get("active")):
		return false
	if p._object_has_property(target, "attack_magnetism_enabled"):
		return bool(target.get("attack_magnetism_enabled"))
	return true


func _get_attack_magnetism_target_position(target: Node3D) -> Vector3:
	var p = _owner
	if target != null and is_instance_valid(target) and target.has_method("get_attack_magnetism_position"):
		var position: Variant = target.call("get_attack_magnetism_position", p)
		if position is Vector3:
			return position
	return _get_homing_target_position(target, p.global_position)


func _get_attack_magnetism_setting(target: Node3D, property_name: String, fallback_value: float) -> float:
	var p = _owner
	if target != null and is_instance_valid(target):
		var override_settings: bool = false
		if p._object_has_property(target, "attack_magnetism_override_player_settings"):
			override_settings = bool(target.get("attack_magnetism_override_player_settings"))
		if override_settings and p._object_has_property(target, property_name):
			return float(target.get(property_name))
	return fallback_value


func _get_attack_magnetism_input_factor(target_dir: Vector3, up: Vector3) -> float:
	var p = _owner
	if p._move_direction.length() < 0.001:
		return 1.0
	var input_dir: Vector3 = p._move_direction - up * p._move_direction.dot(up)
	if input_dir.length() < 0.001:
		return 1.0
	input_dir = input_dir.normalized()

	var target_flat: Vector3 = target_dir - up * target_dir.dot(up)
	if target_flat.length() < 0.001:
		return 1.0
	target_flat = target_flat.normalized()

	var input_dot: float = clamp(input_dir.dot(target_flat), -1.0, 1.0)
	if input_dot <= p.attack_magnetism_input_away_dot:
		return 0.0
	if input_dot >= 0.0:
		return 1.0 + input_dot * max(p.attack_magnetism_input_toward_bonus, 0.0)
	var input_range: float = max(0.0 - p.attack_magnetism_input_away_dot, 0.001)
	return lerp(0.25, 1.0, clamp((input_dot - p.attack_magnetism_input_away_dot) / input_range, 0.0, 1.0))


func _get_attack_magnetism_descent_factor(current_velocity: Vector3, up: Vector3) -> float:
	var p = _owner
	var descent_speed: float = max(-current_velocity.dot(up), 0.0)
	var no_descent_strength: float = clamp(p.attack_magnetism_no_descent_strength, 0.0, 1.0)
	var fast_descent_strength: float = clamp(p.attack_magnetism_fast_descent_strength, 0.0, 1.0)
	var peak_speed: float = max(p.attack_magnetism_peak_descent_speed, 0.001)
	if descent_speed <= peak_speed:
		return lerp(no_descent_strength, 1.0, clamp(descent_speed / peak_speed, 0.0, 1.0))
	var max_descent_speed: float = max(p.attack_magnetism_max_descent_speed, peak_speed + 0.001)
	var fast_t: float = clamp((descent_speed - peak_speed) / (max_descent_speed - peak_speed), 0.0, 1.0)
	return lerp(1.0, fast_descent_strength, fast_t)


func _perform_jump_dash(physics_up: Vector3, is_attached: bool, lateral: Vector3) -> Vector3:
	var p = _owner
	# Respect "air only" flag
	if p.jump_dash_air_only and is_attached:
		return lateral

	# One dash per airtime, if enabled
	if p.jump_dash_once_per_air and p._jump_dash_used_this_air:
		return lateral

	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	# Base facing direction: model forward
	var forward: Vector3 = p._model_forward
	if forward.length() < 0.001:
		# Fallback to lateral movement direction, then a sane default
		if lateral.length() > 0.001:
			forward = lateral.normalized()
		else:
			forward = -Vector3.FORWARD

	# Project forward onto plane perpendicular to up (purely horizontal/along surface)
	var dash_dir: Vector3 = forward - up * forward.dot(up)
	if dash_dir.length() < 0.001:
		dash_dir = forward
	dash_dir = dash_dir.normalized()

	# --- Jump dash impulse scales down as lateral speed approaches the cutoff. ---
	var impulse_stop_speed: float = max(p.jump_dash_impulse_stop_speed, 0.0)
	var lateral_speed_pre: float = lateral.length()
	var impulse_scale: float = 0.0
	if impulse_stop_speed > 0.0:
		var remaining: float = impulse_stop_speed - lateral_speed_pre
		if remaining > 0.0:
			impulse_scale = clamp(remaining / impulse_stop_speed, 0.0, 1.0)

	if impulse_scale > 0.0:
		var dash_vec: Vector3 = dash_dir * (p.jump_dash_add_speed * impulse_scale)
		lateral += dash_vec

	# Clamp lateral speed to dash limit / global max
	var max_dash_speed: float = p.jump_dash_max_lateral_speed
	if max_dash_speed <= 0.0:
		max_dash_speed = p.max_speed

	var lateral_speed: float = lateral.length()
	if lateral_speed > max_dash_speed and lateral_speed > 0.0:
		lateral = lateral.normalized() * max_dash_speed

	# Always mark the dash as used, even if no impulse was applied due to the cutoff.
	p.play_jumpdash_sfx()
	p._jump_dash_used_this_air = true
	p._jump_dash_recent_timer = p.jump_dash_recent_time
	p._trigger_anim_command(&"JUMPDASH")
	return lateral


func _get_homing_target_direction() -> Vector3:
	var p = _owner
	# SUMMARY: Blend movement direction with horizontal facing for homing targeting.
	# STEPS:
	# - Step 1: Use current velocity (full 3D) as the movement direction.
	# - Step 2: Use model forward projected onto gravity-up as the facing direction.
	# - Step 3: Return the normalized average of both.
	var move_dir: Vector3 = p.velocity
	if move_dir.length() > 0.001:
		move_dir = move_dir.normalized()
	else:
		move_dir = p._model_forward
		if move_dir.length() > 0.001:
			move_dir = move_dir.normalized()
		else:
			move_dir = -Vector3.FORWARD

	var gravity_up_dir: Vector3 = p._get_gravity_up()

	var face_flat: Vector3 = p._model_forward - gravity_up_dir * p._model_forward.dot(gravity_up_dir)
	if face_flat.length() > 0.001:
		face_flat = face_flat.normalized()
	else:
		face_flat = move_dir - gravity_up_dir * move_dir.dot(gravity_up_dir)
		if face_flat.length() > 0.001:
			face_flat = face_flat.normalized()
		else:
			face_flat = move_dir

	var hybrid: Vector3 = move_dir + face_flat
	if hybrid.length() < 0.001:
		return move_dir
	return hybrid.normalized()


func _select_homing_target(origin: Vector3, max_range: float) -> Node3D:
	var p = _owner
	# Resolves the target with the active input-device targeting mode.
	p._homing_target_candidate_positions.clear()
	if not p._can_scan_homing_targets():
		return null
	var mode: int = SettingsManager.get_active_homing_targeting_mode()
	var target: Node3D = null
	if mode == SettingsManager.HOMING_TARGETING_CAMERA:
		target = _find_best_homing_target_camera(origin, max_range)
	elif mode == SettingsManager.HOMING_TARGETING_HYBRID:
		target = _find_best_homing_target_hybrid(origin, max_range)
	else:
		var dash_dir: Vector3 = _get_homing_target_direction()
		if dash_dir.length() < 0.001:
			dash_dir = -Vector3.FORWARD
		target = _find_best_homing_target(origin, dash_dir, max_range)

	return target


func _find_best_homing_target_camera(origin: Vector3, max_range: float) -> Node3D:
	var p = _owner
	# SUMMARY: Pick the closest target inside a camera-centered radius.
	# STEPS:
	# - Step 1: Resolve camera + viewport and validate radius.
	# - Step 2: Filter targets by range/height and screen-space radius.
	# - Step 3: Score by center priority with slight distance bias.
	if not p._can_scan_homing_targets():
		return null
	if max_range <= 0.0:
		return null

	var cam: Camera3D = p.camera
	if cam == null:
		var vp: Viewport = p.get_viewport()
		if vp != null:
			cam = vp.get_camera_3d()
	if cam == null:
		return null

	var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return null

	var radius: float = max(SettingsManager.homing_camera_radius, 0.0)
	if radius <= 0.0:
		return null

	var center: Vector2 = vp_size * 0.5
	var offset_t: float = clamp(SettingsManager.reticle_vertical_offset, 0.0, 100.0) / 100.0
	center.y += -0.5 * vp_size.y * offset_t
	var aim_origin: Vector3 = cam.project_ray_origin(center)
	var aim_dir: Vector3 = cam.project_ray_normal(center)
	if aim_dir.length() < 0.001:
		aim_dir = -cam.global_transform.basis.z
	if aim_dir.length() < 0.001:
		aim_dir = Vector3.FORWARD
	aim_dir = aim_dir.normalized()
	var center_radius: float = radius * 0.4
	var up: Vector3 = p._get_gravity_up()

	var best: Node3D = null
	var best_score: float = -999999.0
	var best_in_center: bool = false

	var max_range2: float = max_range * max_range
	var nodes: Array = []
	var mgr = p.get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("get_targets_in_range"):
		nodes = mgr.get_targets_in_range(origin, max_range)
	else:
		nodes = p.get_tree().get_nodes_in_group("HomingTarget")
	for n in nodes:
		if n == null:
			continue
		if not (n is Node3D):
			continue

		# Optional script flag.
		if p._object_has_property(n, "enabled") and not bool(n.get("enabled")):
			continue
		if p._object_has_property(n, "active") and not bool(n.get("active")):
			continue

		var target_position: Vector3 = _get_homing_target_position_for_aim(n as Node3D, origin, aim_origin, aim_dir)
		var to: Vector3 = target_position - origin
		var dist2: float = to.length_squared()
		if dist2 <= 0.000001 or dist2 > max_range2:
			continue
		if not _is_homing_target_within_max_distance(n as Node3D, dist2):
			continue
		if _is_homing_target_obstructed(origin, target_position, n as Node3D):
			continue
		if p.homing_target_max_height > 0.0:
			var height_delta: float = to.dot(up)
			if height_delta > p.homing_target_max_height:
				continue

		if cam.is_position_behind(target_position):
			continue
		var screen_pos: Vector2 = cam.unproject_position(target_position)
		var screen_dist: float = screen_pos.distance_to(center)
		if screen_dist > radius:
			continue

		# Compute exact distance only for surviving candidates.
		var dist: float = sqrt(dist2)
		var center_score: float = 1.0 - (screen_dist / radius)
		var range_score: float = 1.0 - (dist / max_range)
		var score: float = center_score * 100.0 + range_score * 5.0

		var in_center: bool = screen_dist <= center_radius
		if in_center:
			if not best_in_center or score > best_score:
				best_score = score
				best = n as Node3D
				best_in_center = true
				_set_homing_candidate_position(best, target_position)
		else:
			if best_in_center:
				continue
			if score > best_score:
				best_score = score
				best = n as Node3D
				_set_homing_candidate_position(best, target_position)

	return best


func _find_best_homing_target_hybrid(origin: Vector3, max_range: float) -> Node3D:
	var p = _owner
	if not p._can_scan_homing_targets():
		return null
	if max_range <= 0.0:
		return null

	var context: Dictionary = _get_homing_hybrid_context(origin)
	var aim_origin: Vector3 = context.get("aim_origin", origin)
	var aim_dir: Vector3 = context.get("aim_dir", Vector3.ZERO)
	if aim_dir.length() < 0.001:
		return null
	aim_dir = aim_dir.normalized()
	var camera_weight: float = clamp(float(context.get("camera_weight", 0.0)), 0.0, 1.0)
	var camera_aim_dir: Vector3 = context.get("camera_aim_dir", aim_dir)
	var cam: Camera3D = context.get("camera", null) as Camera3D
	var center: Vector2 = context.get("center", Vector2.ZERO)
	var radius: float = max(SettingsManager.homing_camera_radius, 0.0)
	var reticle_priority: float = max(p.homing_hybrid_reticle_priority, 0.0)
	var up: Vector3 = p._get_gravity_up()
	var min_dot: float = clamp(p.homing_min_dot, -1.0, 1.0)
	var max_range_squared: float = max_range * max_range

	var best: Node3D = null
	var best_score: float = -999999.0
	var nodes: Array = []
	var mgr = p.get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("get_targets_in_range"):
		nodes = mgr.get_targets_in_range(origin, max_range)
	else:
		nodes = p.get_tree().get_nodes_in_group("HomingTarget")

	for n in nodes:
		if n == null or not (n is Node3D):
			continue
		if p._object_has_property(n, "enabled") and not bool(n.get("enabled")):
			continue
		if p._object_has_property(n, "active") and not bool(n.get("active")):
			continue

		var target: Node3D = n as Node3D
		var target_position: Vector3 = _get_homing_target_position_for_aim(target, origin, aim_origin, aim_dir)
		var to_target: Vector3 = target_position - origin
		var distance_squared: float = to_target.length_squared()
		if distance_squared <= 0.000001 or distance_squared > max_range_squared:
			continue
		if not _is_homing_target_within_max_distance(target, distance_squared):
			continue
		if _is_homing_target_obstructed(origin, target_position, target):
			continue
		if p.homing_target_max_height > 0.0:
			var height_delta: float = to_target.dot(up)
			if height_delta > p.homing_target_max_height:
				continue

		var distance: float = sqrt(distance_squared)
		var target_dir: Vector3 = to_target / distance
		var intent_dot: float = target_dir.dot(aim_dir)
		if intent_dot < min_dot:
			continue

		var centeredness: float = 0.0
		if cam and radius > 0.0 and not cam.is_position_behind(target_position):
			var screen_position: Vector2 = cam.unproject_position(target_position)
			var screen_distance: float = screen_position.distance_to(center)
			centeredness = 1.0 - clamp(screen_distance / radius, 0.0, 1.0)
		var camera_alignment: float = max(target_dir.dot(camera_aim_dir), 0.0)
		var range_score: float = 1.0 - distance / max_range
		var score: float = intent_dot * 1000.0
		score += centeredness * reticle_priority * camera_weight * 1000.0
		score += camera_alignment * camera_weight * 150.0
		score += range_score * 40.0
		if score > best_score:
			best_score = score
			best = target
			_set_homing_candidate_position(target, target_position)

	return best


func _find_best_homing_target(origin: Vector3, dash_dir: Vector3, max_range: float) -> Node3D:
	var p = _owner
	if not p._can_scan_homing_targets():
		return null
	if max_range <= 0.0:
		return null

	var best = null
	var best_score: float = -999999.0
	var up: Vector3 = p._get_gravity_up()

	var max_range2: float = max_range * max_range
	var min_dot2: float = p.homing_min_dot * p.homing_min_dot

	var nodes: Array = []
	var mgr = p.get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("get_targets_in_range"):
		nodes = mgr.get_targets_in_range(origin, max_range)
	else:
		nodes = p.get_tree().get_nodes_in_group("HomingTarget")
	for n in nodes:
		if n == null:
			continue
		if not (n is Node3D):
			continue

		# Optional script flag.
		if p._object_has_property(n, "enabled") and not bool(n.get("enabled")):
			continue
		if p._object_has_property(n, "active") and not bool(n.get("active")):
			continue

		var target_position: Vector3 = _get_homing_target_position_for_aim(n as Node3D, origin, origin, dash_dir)
		var to: Vector3 = target_position - origin
		var dist2: float = to.length_squared()
		if dist2 <= 0.000001 or dist2 > max_range2:
			continue
		if not _is_homing_target_within_max_distance(n as Node3D, dist2):
			continue
		if _is_homing_target_obstructed(origin, target_position, n as Node3D):
			continue
		if p.homing_target_max_height > 0.0:
			var height_delta: float = to.dot(up)
			if height_delta > p.homing_target_max_height:
				continue

		# Use projection to avoid normalizing every candidate.
		var projection: float = to.dot(dash_dir)
		if projection <= 0.0:
			continue
		if projection * projection < min_dot2 * dist2:
			continue

		# Compute exact values for scoring only for remaining candidates.
		var dist: float = sqrt(dist2)
		var dir: Vector3 = to / dist
		var dotv: float = dir.dot(dash_dir)

		# Prefer high dot and closer distance.
		var score: float = dotv * 1000.0 - dist
		if score > best_score:
			best_score = score
			best = n
			_set_homing_candidate_position(n as Node3D, target_position)

	return best


func _get_homing_reticle_target() -> Node3D:
	var p = _owner
	# Return the cached reticle target when fresh to avoid scanning large groups each frame.
	if not p._can_scan_homing_targets():
		return null
	if p.attached:
		return null
	var speed_now: float = p.velocity.length()
	var max_range: float = p.homing_min_range + speed_now * p.homing_range_per_speed
	max_range = clamp(max_range, p.homing_min_range, p.homing_max_range)

	var status: Dictionary = get_homing_target_request_status(p.global_position, max_range, false)
	return status.get("target") as Node3D


func _try_handle_homing_hit(target: Node, jump_held: bool) -> bool:
	var p = _owner
	var n: Node = target
	while n != null:
		if n.has_method("on_homing_hit"):
			var handled = n.call("on_homing_hit", p, jump_held)
			if handled is bool and bool(handled):
				return true
		n = n.get_parent()
	return false


func limit_homing_bounce_from_below(result_velocity: Vector3, target_position: Vector3, up: Vector3) -> Vector3:
	var p = _owner
	if not p.homing_below_target_bounce_cap_enabled:
		return result_velocity
	var normalized_up: Vector3 = up.normalized()
	if normalized_up.length() < 0.001:
		normalized_up = p._get_gravity_up()
	var target_height: float = (target_position - p.global_position).dot(normalized_up)
	if target_height <= max(p.homing_below_target_min_height, 0.0):
		return result_velocity
	var upward_speed: float = result_velocity.dot(normalized_up)
	var upward_cap: float = max(p.homing_below_target_max_up_speed, 0.0)
	if upward_speed <= upward_cap:
		return result_velocity
	return result_velocity - normalized_up * (upward_speed - upward_cap)


func _end_homing(up: Vector3, jump_held: bool) -> void:
	var p = _owner
	p._homing_active = false
	var retained: Vector3 = Vector3.ZERO
	if p.homing_retain_speed_if_jump_held and jump_held:
		retained = p._homing_saved_velocity
	p.velocity = retained + up.normalized() * p.homing_pop_up_speed
	p.attached = false
	p.refresh_airborne_abilities()


func _update_homing(delta: float, up_for_physics: Vector3, is_attached: bool) -> void:
	var p = _owner
	if not p._homing_active:
		return
	p._homing_elapsed += p.get_gameplay_timer_delta(delta)
	if p.homing_fail_timeout > 0.0 and p._homing_elapsed >= p.homing_fail_timeout:
		cancel_homing_attack(false)
		return
	if is_attached:
		p._homing_active = false
		p._homing_target = null
		p._homing_target_position = Vector3.ZERO
		p._homing_target_position_valid = false
		p._homing_elapsed = 0.0
		return

	if p._homing_target == null or not is_instance_valid(p._homing_target):
		p._homing_active = false
		p._homing_target = null
		p._homing_target_position = Vector3.ZERO
		p._homing_target_position_valid = false
		p._homing_elapsed = 0.0
		return

	var up: Vector3 = up_for_physics.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var origin: Vector3 = p.global_position
	var target_position: Vector3 = get_homing_attack_target_position()
	var to: Vector3 = target_position - origin
	var dist: float = to.length()
	var hit_distance: float = p.homing_hit_distance
	var homing_target_is_rail: bool = p._homing_target is Node and _is_rail_like_homing_target(p._homing_target)
	if homing_target_is_rail:
		if p._is_rail_path_snap_obstructed(origin, target_position):
			cancel_homing_attack(false)
			return
		hit_distance = max(hit_distance, p._get_rail_path_snap_radius())

	if dist <= hit_distance:
		var current_velocity: Vector3 = p.velocity
		var current_lateral: Vector3 = p.velocity - up * p.velocity.dot(up)
		var jump_held: bool = p._is_jump_held()

		var homing_dir: Vector3 = to / max(dist, 0.001)
		var homing_spd: float = max(p.homing_speed, p._homing_saved_speed_mag)
		var is_pass_through: bool = p._object_has_property(p._homing_target, "pass_through") and p._homing_target.get("pass_through")

		if _try_handle_homing_hit(p._homing_target, jump_held):
			if is_pass_through:
				p.velocity = homing_dir * homing_spd
				p.refresh_airborne_abilities()
			p._homing_active = false
			p._homing_target = null
			p._homing_target_position = Vector3.ZERO
			p._homing_target_position_valid = false
			p._homing_elapsed = 0.0
			p._homing_post_attack_timer = max(p.homing_post_attack_time, 0.0)
			return
		var pop_speed: float = p.homing_pop_up_speed
		if p._object_has_property(p._homing_target, "pop_up_speed_override"):
			var ov = p._homing_target.get("pop_up_speed_override")
			if ov is float and float(ov) > 0.0:
				pop_speed = float(ov)

		p._homing_active = false
		var retained: Vector3 = Vector3.ZERO
		if p.homing_retain_speed_if_jump_held and jump_held:
			if current_velocity.dot(up) < 0.0:
				retained = current_lateral
			elif current_velocity.length() > 0.001:
				retained = current_velocity
			elif current_lateral.length() > 0.001:
				retained = current_lateral
			else:
				retained = p._homing_saved_lateral
			p._homing_retain_timer = max(p.homing_retain_disable_air_decel_time, 0.0)
		var bounce_velocity: Vector3 = retained + up * pop_speed
		p.velocity = limit_homing_bounce_from_below(bounce_velocity, target_position, up)
		p.attached = false
		p.refresh_airborne_abilities()
		p._homing_post_attack_timer = max(p.homing_post_attack_time, 0.0)
		p._homing_target = null
		p._homing_target_position = Vector3.ZERO
		p._homing_target_position_valid = false
		p._homing_elapsed = 0.0
		return

	var desired_dir: Vector3 = to / dist
	var spd: float = max(p.homing_speed, p._homing_saved_speed_mag)
	var current_dir: Vector3 = p.velocity.normalized()
	if current_dir.length() < 0.001:
		p.velocity = desired_dir * spd
	else:
		var angle: float = current_dir.angle_to(desired_dir)
		var max_turn: float = p.homing_turn_rate * delta
		if angle > max_turn and angle > 0.001:
			var t: float = max_turn / angle
			p.velocity = current_dir.slerp(desired_dir, t) * spd
		else:
			p.velocity = desired_dir * spd


func cancel_homing_attack(restore_saved_velocity: bool = false) -> void:
	var p = _owner
	_stop_lightspeed_dash_if_active(false)
	# Optionally restore the pre-homing velocity so downstream effects (springs, etc.)
	# don't inherit the "toward target" homing velocity.
	if restore_saved_velocity and (p._homing_active or p._homing_target != null):
		if p._homing_saved_velocity.length() > 0.001:
			p.velocity = p._homing_saved_velocity

	p._homing_active = false
	p._homing_target = null
	p._homing_target_position = Vector3.ZERO
	p._homing_target_position_valid = false
	p._homing_saved_velocity = Vector3.ZERO
	p._homing_saved_lateral = Vector3.ZERO
	p._homing_saved_speed_mag = 0.0
	p._homing_retain_timer = 0.0
	p._homing_elapsed = 0.0


func reset_for_level_change() -> void:
	var p = _owner
	_stop_lightspeed_dash_if_active(false)
	p._homing_active = false
	p._homing_target = null
	p._homing_target_position = Vector3.ZERO
	p._homing_target_position_valid = false
	p._homing_target_candidate_positions.clear()
	p._homing_reticle_cached_target = null
	p._homing_reticle_cached_time_ms = 0
	p._homing_target_scan_initialized = false
	clear_homing_target_request_buffer()
	p._homing_reticle_cached_mode = -1
	p._attack_magnetism_target = null
	p._attack_magnetism_target_position = Vector3.ZERO
	p._attack_magnetism_strength_current = 0.0
	p._attack_magnetism_scan_timer = 0.0
	p._attack_magnetism_scan_result.clear()


func _try_start_lightspeed_dash() -> bool:
	var p = _owner
	if not p.can_start_lightspeed_dash():
		return false
	var forward_bias: Vector3 = _get_lightspeed_forward_bias()
	var target: Node3D = _find_best_lightspeed_ring(p.global_position, p.lightspeed_dash_start_radius, forward_bias, 0)
	if target == null:
		return false
	_stop_lightspeed_dash_if_active(false)
	p._lightspeed_dash_active = true
	p._lightspeed_dash_target = target
	p._lightspeed_dash_prev_ring = null
	p._lightspeed_dash_timer = 0.0
	var base_velocity: Vector3 = p.velocity
	if base_velocity.length() <= 0.01:
		base_velocity = forward_bias
	if base_velocity.length() <= 0.01:
		base_velocity = p._model_forward
	if base_velocity.length() <= 0.01:
		base_velocity = -p.global_transform.basis.z
	var base_dir: Vector3 = base_velocity.normalized() if base_velocity.length() > 0.001 else p._get_camera_forward_world_up(p.gravity_up)
	if base_dir.length() <= 0.001:
		base_dir = Vector3.FORWARD
	var start_speed: float = max(p.lightspeed_dash_min_speed, max(base_velocity.length(), 0.0))
	if p.lightspeed_dash_start_additive_speed_enabled and p._lightspeed_dash_start_bonus_cooldown_timer <= 0.0:
		start_speed += max(p.lightspeed_dash_start_additive_speed, 0.0)
		p._lightspeed_dash_start_bonus_cooldown_timer = max(p.lightspeed_dash_start_bonus_cooldown, 0.0)
	if p.lightspeed_dash_start_speed_cap > 0.0:
		start_speed = min(start_speed, p.lightspeed_dash_start_speed_cap)
	p._lightspeed_dash_speed = max(start_speed, p.lightspeed_dash_min_speed)
	if p._lightspeed_dash_speed <= 0.0:
		p._lightspeed_dash_speed = p.lightspeed_dash_min_speed
	p._lightspeed_dash_release_velocity = base_dir.normalized() * p._lightspeed_dash_speed
	var initial_dir: Vector3 = (p._lightspeed_dash_target.global_position - p.global_position)
	if initial_dir.length() > 0.001:
		p._lightspeed_dash_last_dir = initial_dir.normalized()
	else:
		p._lightspeed_dash_last_dir = base_dir.normalized()
	p._bounce_state = p.BounceState.NONE
	# Cancel homing attack manually without stopping lightspeed dash
	p._homing_active = false
	p._homing_target = null
	p._homing_target_position = Vector3.ZERO
	p._homing_target_position_valid = false
	p._homing_saved_velocity = Vector3.ZERO
	p._homing_saved_lateral = Vector3.ZERO
	p._homing_saved_speed_mag = 0.0
	p._homing_retain_timer = 0.0
	p._homing_elapsed = 0.0
	p.cancel_spline_spring()
	p.cancel_rail_grind()
	p._reset_spindash_state()
	p.rolling = false
	p._spindash_charging = false
	p._jump_dash_requested = false
	clear_homing_target_request_buffer()
	p._tornado_kick_used_this_air = false
	p._jump_dash_used_this_air = true
	p.attached = false
	p._is_jumping = false
	p._is_falling = false
	p._trigger_anim_command(&"CMD_LIGHTSPEEDDASH")
	# Lock input immediately to prevent normal movement on this frame
	p._spring_movement_lock_timer = 0.1
	p._spring_action_lock_timer = 0.1
	return true


func _get_lightspeed_forward_bias() -> Vector3:
	var p = _owner
	var dir: Vector3 = p.velocity
	if dir.length() > 0.001:
		return dir.normalized()
	if p._model_forward.length() > 0.001:
		return p._model_forward.normalized()
	var world_up: Vector3 = p._get_gravity_up()
	var cam_dir: Vector3 = p._get_camera_forward_world_up(world_up)
	if cam_dir.length() > 0.001:
		return cam_dir.normalized()
	return Vector3.FORWARD


func _is_ring_available_for_lightspeed(ring: Variant) -> bool:
	var p = _owner
	if ring == null or not is_instance_valid(ring):
		return false
	if not (ring is Node):
		return false
	var ring_node: Node = ring as Node
	if ring_node.has_method("is_light_speed_dash_ready"):
		if not bool(ring_node.call("is_light_speed_dash_ready")):
			return false
	if p._object_has_property(ring_node, "enabled") and not bool(ring_node.get("enabled")):
		return false
	if p._object_has_property(ring_node, "allow_light_speed_dash") and not bool(ring_node.get("allow_light_speed_dash")):
		return false
	return true


func _find_best_lightspeed_ring(origin: Vector3, max_radius: float, forward_bias: Vector3, exclude_instance_id: int) -> Node3D:
	var p = _owner
	# Apply speed-based radius bonus first so the manager query uses the correct range.
	var speed: float = p.velocity.length()
	var speed_bonus_radius: float = speed * p.lightspeed_dash_speed_bonus_per_speed
	var effective_radius: float = max_radius + speed_bonus_radius

	var nodes: Array = []
	var mgr = p.get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("get_rings_in_range"):
		nodes = mgr.get_rings_in_range(origin, effective_radius)
	elif p.get_tree() != null:
		nodes = p.get_tree().get_nodes_in_group(p.LIGHTSPEED_RING_GROUP)
	if nodes.is_empty():
		return null
	
	var forward_norm: Vector3 = forward_bias.normalized() if forward_bias.length() > 0.001 else Vector3.ZERO
	var up: Vector3 = p._get_gravity_up()
	
	# Get camera direction and screen cursor position for targeting methods
	var camera_forward: Vector3 = p._get_camera_forward_world_up(p.gravity_up)
	var screen_cursor_pos: Vector2 = Vector2.ZERO
	var cam: Camera3D = p.camera
	if cam == null:
		var vp: Viewport = p.get_viewport()
		if vp != null:
			cam = vp.get_camera_3d()
	if cam != null:
		screen_cursor_pos = cam.get_viewport().get_mouse_position()
	
	var best: Node3D = null
	var best_score: float = -999999.0
	
	for entry in nodes:
		var ring: Node3D = entry as Node3D
		if ring == null or not is_instance_valid(ring):
			continue
		if exclude_instance_id != 0 and ring.get_instance_id() == exclude_instance_id:
			continue
		if not _is_ring_available_for_lightspeed(ring):
			continue
		var to: Vector3 = ring.global_position - origin
		var dist: float = to.length()
		if dist <= 0.001:
			continue
		if effective_radius > 0.0 and dist > effective_radius:
			continue
		if p.lightspeed_dash_max_height_delta > 0.0:
			var height_delta: float = abs(to.dot(up))
			if height_delta > p.lightspeed_dash_max_height_delta:
				continue

		# Skip rings obstructed by collision geometry (with raycast caching)
		var ring_rid: RID = (ring as CollisionObject3D).get_rid() if ring is CollisionObject3D else RID()
		var is_obstructed: bool = false
		
		# Check cache first
		var current_time_ms: int = Time.get_ticks_msec()
		if ring_rid.is_valid() and ring_rid in p._lightspeed_raycast_cache:
			var cache_entry: Dictionary = p._lightspeed_raycast_cache[ring_rid]
			if current_time_ms - cache_entry.time_ms < p.LIGHTSPEED_RAYCAST_CACHE_MS:
				is_obstructed = cache_entry.obstructed
			else:
				p._lightspeed_raycast_cache.erase(ring_rid)
		
		# If not cached, perform raycast
		if not (ring_rid.is_valid() and ring_rid in p._lightspeed_raycast_cache):
			var world: World3D = p.get_world_3d()
			if world != null:
				var ray_from: Vector3 = origin
				var ray_to: Vector3 = ring.global_position
				var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
				var exclude_list: Array[RID] = []
				exclude_list.append(p.get_rid())
				if ring is CollisionObject3D:
					exclude_list.append(ring_rid)
				ray_params.exclude = exclude_list
				ray_params.collision_mask = p.collision_mask
				var ray_result: Dictionary = world.direct_space_state.intersect_ray(ray_params)
				if ray_result:
					var hit_pos: Vector3 = ray_result.position
					var dist_to_hit: float = ray_from.distance_to(hit_pos)
					is_obstructed = dist_to_hit < dist - 0.1
				
				# Cache the result
				if ring_rid.is_valid():
					p._lightspeed_raycast_cache[ring_rid] = {"time_ms": current_time_ms, "obstructed": is_obstructed}
		
		if is_obstructed:
			continue

		var dir: Vector3 = to / dist

		# Calculate score based on targeting method
		var score: float = 0.0
		
		# For all methods, give extra weight to rings in movement direction
		var movement_bonus: float = 0.0
		if forward_norm.length() > 0.001:
			var movement_dot: float = dir.dot(forward_norm)
			if movement_dot >= p.lightspeed_dash_min_forward_dot:
				movement_bonus = movement_dot * 2000.0 # Strong bonus for movement direction
		
		var targeting_mode: int = SettingsManager.lightspeed_dash_targeting_mode
		match targeting_mode:
			SettingsManager.LIGHTSPEED_DASH_TARGETING_MOVEMENT:
				# Prefer rings in input direction
				if forward_norm.length() > 0.001:
					var dotv: float = dir.dot(forward_norm)
					if dotv < p.lightspeed_dash_min_forward_dot:
						continue
					score = dotv * 1000.0 - dist
				else:
					score = -dist
			
			SettingsManager.LIGHTSPEED_DASH_TARGETING_CAMERA:
				# Prefer rings under screen cursor
				var camera_dot: float = dir.dot(camera_forward)
				if camera_dot < p.lightspeed_dash_min_forward_dot:
					continue
				var cursor_bonus: float = 0.0
				if cam != null:
					var screen_pos: Vector2 = cam.unproject_position(ring.global_position)
					var cursor_dist: float = screen_pos.distance_to(screen_cursor_pos)
					# Bonus for being close to cursor (in screen space)
					var viewport_size: Vector2 = cam.get_viewport().get_visible_rect().size
					var normalized_cursor_dist: float = cursor_dist / viewport_size.length()
					cursor_bonus = (1.0 - clamp(normalized_cursor_dist, 0.0, 1.0)) * 500.0
				score = camera_dot * 1000.0 + cursor_bonus - dist
			
			SettingsManager.LIGHTSPEED_DASH_TARGETING_HYBRID:
				# Combine camera and input
				var camera_dot: float = dir.dot(camera_forward)
				var input_dot: float = 0.0
				if forward_norm.length() > 0.001:
					input_dot = dir.dot(forward_norm)
				
				# Determine if input is within camera facing direction
				var hybrid_angle_rad: float = deg_to_rad(p.lightspeed_dash_hybrid_angle_deg)
				var camera_input_angle: float = camera_forward.angle_to(forward_norm) if forward_norm.length() > 0.001 else 0.0
				
				var use_camera: bool = camera_input_angle <= hybrid_angle_rad and camera_dot >= p.lightspeed_dash_min_forward_dot
				var use_input: bool = forward_norm.length() > 0.001 and input_dot >= p.lightspeed_dash_min_forward_dot
				
				var cursor_bonus: float = 0.0
				if cam != null:
					var screen_pos: Vector2 = cam.unproject_position(ring.global_position)
					var cursor_dist: float = screen_pos.distance_to(screen_cursor_pos)
					var viewport_size: Vector2 = cam.get_viewport().get_visible_rect().size
					var normalized_cursor_dist: float = cursor_dist / viewport_size.length()
					cursor_bonus = (1.0 - clamp(normalized_cursor_dist, 0.0, 1.0)) * 500.0
				
				if use_camera and use_input:
					# Ring is in both directions, use weighted combination
					score = (camera_dot * 0.6 + input_dot * 0.4) * 1000.0 + cursor_bonus - dist
				elif use_camera:
					# Ring is in camera direction but not input
					score = camera_dot * 1000.0 + cursor_bonus - dist
				elif use_input:
					# Ring is in input direction but not camera
					score = input_dot * 1000.0 - dist
				else:
					# Ring is in neither direction
					continue
		
		# Add movement direction bonus to all methods
		score += movement_bonus

		if score > best_score:
			best_score = score
			best = ring
	
	return best


func _advance_lightspeed_dash_target() -> bool:
	var p = _owner
	var exclude_instance_id: int = 0
	if p._lightspeed_dash_target != null and is_instance_valid(p._lightspeed_dash_target):
		p._lightspeed_dash_prev_ring = p._lightspeed_dash_target
	var origin: Vector3 = p.global_position
	if p._lightspeed_dash_prev_ring != null and is_instance_valid(p._lightspeed_dash_prev_ring):
		origin = p._lightspeed_dash_prev_ring.global_position
		exclude_instance_id = p._lightspeed_dash_prev_ring.get_instance_id()
	else:
		p._lightspeed_dash_prev_ring = null
	var bias: Vector3 = p._lightspeed_dash_last_dir
	if bias.length() < 0.001:
		bias = p._lightspeed_dash_release_velocity
	var next_ring: Node3D = _find_best_lightspeed_ring(origin, p.lightspeed_dash_chain_radius, bias, exclude_instance_id)
	p._lightspeed_dash_target = next_ring
	return next_ring != null


func _update_lightspeed_dash(_delta: float, _physics_up: Vector3) -> void:
	var p = _owner
	if not p._lightspeed_dash_active:
		return

	# Ability Slot 2 cancellation.
	if SettingsManager.is_gameplay_action_just_pressed("ability_slot_02"):
			_end_lightspeed_dash(true, false)
			return

	# Ensure we have a valid target
	if p._lightspeed_dash_target == null or not _is_ring_available_for_lightspeed(p._lightspeed_dash_target):
			if not _advance_lightspeed_dash_target():
				_end_lightspeed_dash(true, false)
				return

	var target_pos: Vector3 = p._lightspeed_dash_target.global_position
	var to_target: Vector3 = target_pos - p.global_position
	var dist: float = to_target.length()
	var dir: Vector3
	if dist > 0.001:
		dir = to_target / dist
	else:
		dir = p._lightspeed_dash_last_dir
	if dir.length() < 0.001:
		dir = -p.global_transform.basis.z
	if dir.length() < 0.001:
		dir = Vector3.FORWARD

	# Set velocity for move_and_slide to handle position and collision
	p.velocity = dir * p._lightspeed_dash_speed
	p._lightspeed_dash_last_dir = dir
	p._lightspeed_dash_release_velocity = p.velocity

	# Keep state flags consistent
	p.attached = false
	p._is_jumping = false
	p._is_falling = false
	p._jump_dash_used_this_air = true
	p._tornado_kick_used_this_air = false


func _post_move_lightspeed_dash(_delta: float) -> void:
	var p = _owner
	if not p._lightspeed_dash_active:
		return

	# After move_and_slide, check if we reached the current ring
	if p._lightspeed_dash_target != null and is_instance_valid(p._lightspeed_dash_target):
		var distance_to_target: float = p.global_position.distance_to(p._lightspeed_dash_target.global_position)
		var collect_dist: float = max(p.lightspeed_dash_collect_distance, 0.05)
		if distance_to_target <= collect_dist:
			# Snap to ring position and try to advance
			p.global_position = p._lightspeed_dash_target.global_position
			if not _advance_lightspeed_dash_target():
				_end_lightspeed_dash(true, true)
				return

	# If target is no longer valid, try to advance
	if p._lightspeed_dash_target == null or not _is_ring_available_for_lightspeed(p._lightspeed_dash_target):
		if not _advance_lightspeed_dash_target():
			_end_lightspeed_dash(true, true)


func _end_lightspeed_dash(apply_release_velocity: bool, try_attach: bool = false) -> void:
	var p = _owner
	if not p._lightspeed_dash_active:
		return
	p._lightspeed_dash_active = false
	p._lightspeed_dash_target = null
	p._lightspeed_dash_prev_ring = null
	p._lightspeed_raycast_cache.clear()  # Clear raycast cache when dash ends
	if apply_release_velocity and p._lightspeed_dash_release_velocity.length() > 0.001:
		p.velocity = p._lightspeed_dash_release_velocity
	p._lightspeed_dash_release_velocity = Vector3.ZERO
	p._lightspeed_dash_last_dir = Vector3.ZERO
	p._lightspeed_dash_speed = 0.0
	p._lightspeed_dash_timer = 0.0
	if p._current_action_id == &"lightspeed_dash":
		p.clear_active_action()
	if try_attach and p.lightspeed_dash_auto_attach_on_end and not p.attached:
		_attempt_lightspeed_dash_ground_attach()
	if not p.attached:
		p.activate_neutral_air_action({"reason": &"lightspeed_dash_end"})


func _attempt_lightspeed_dash_ground_attach() -> void:
	var p = _owner
	var hit: Dictionary = _find_lightspeed_dash_attach_hit()
	if hit.is_empty():
		print("[LSD-ATTACH] no surface within ", p.lightspeed_dash_auto_attach_max_distance)
		return

	var hit_position: Vector3 = hit["position"] if hit.has("position") and hit["position"] is Vector3 else p.global_position
	var hit_normal: Vector3 = hit["normal"] if hit.has("normal") and hit["normal"] is Vector3 else p._get_gravity_up()
	if p._is_low_speed_detach_reattach_blocked(hit_normal, p.gravity_up):
		return
	var surface_kind: String = hit["kind"] if hit.has("kind") and hit["kind"] is String else "surface"
	print("[LSD-ATTACH] hit ", surface_kind, " at ", hit_position, " normal=", hit_normal)
	p.global_position = hit_position + hit_normal * max(p.collision_ground_distance, 0.05)
	p._apply_grounded_from_downwarp(hit_position, hit_normal)
	p._lock_to_surface()


func _find_lightspeed_dash_attach_hit() -> Dictionary:
	var p = _owner
	var result: Dictionary = {}
	if p.DEBUG_SKIP_AIR_RAYS:
		return result
	var world: World3D = p.get_world_3d()
	if world == null:
		return result

	var up: Vector3 = p._get_gravity_up()

	var max_distance: float = max(p.lightspeed_dash_auto_attach_max_distance, p.ground_ray_length)
	max_distance = max(max_distance, 0.1)
	var origin: Vector3 = p.global_position + up * 0.1

	var forward: Vector3 = _get_lightspeed_forward_bias()
	forward = forward - up * forward.dot(up)
	if forward.length() < 0.001:
		forward = -p.global_transform.basis.z
		forward = forward - up * forward.dot(up)
	if forward.length() < 0.001:
		forward = p.global_transform.basis.x - up * p.global_transform.basis.x.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	if forward.length() > 0.001:
		forward = forward.normalized()

	var right: Vector3 = up.cross(forward)
	if right.length() < 0.001:
		right = p.global_transform.basis.x - up * p.global_transform.basis.x.dot(up)
	if right.length() < 0.001:
		right = p.global_transform.basis.z - up * p.global_transform.basis.z.dot(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	if right.length() > 0.001:
		right = right.normalized()

	var directions: Array = []
	directions.append(-up)
	if forward.length() > 0.001:
		directions.append(forward)
		directions.append(-forward)
		directions.append((forward - up).normalized())
		directions.append((-forward - up).normalized())
		directions.append((forward + up).normalized())
		directions.append((-forward + up).normalized())
	if right.length() > 0.001:
		directions.append(right)
		directions.append(-right)
		directions.append((right - up).normalized())
		directions.append((-right - up).normalized())
		directions.append((right + up).normalized())
		directions.append((-right + up).normalized())
	if forward.length() > 0.001 and right.length() > 0.001:
		directions.append((forward + right).normalized())
		directions.append((forward - right).normalized())
		directions.append((-forward + right).normalized())
		directions.append((-forward - right).normalized())
	directions.append(up)

	var mask: int = p.collision_mask
	if p.ground_ray != null:
		mask = p.ground_ray.collision_mask

	var best_floor_hit: bool = false
	var best_floor_distance: float = INF
	var best_floor_point: Vector3 = Vector3.ZERO
	var best_floor_normal: Vector3 = p._get_gravity_up()
	var best_any_hit: bool = false
	var best_any_distance: float = INF
	var best_any_point: Vector3 = Vector3.ZERO
	var best_any_normal: Vector3 = p._get_gravity_up()

	for direction in directions:
		var dir: Vector3 = direction
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * max_distance)
		params.collision_mask = mask
		params.collide_with_areas = false
		params.collide_with_bodies = true
		params.exclude = [p]

		var hit: Dictionary = world.direct_space_state.intersect_ray(params)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit["position"] if hit.has("position") and hit["position"] is Vector3 else Vector3.ZERO
		var hit_normal: Vector3 = hit["normal"] if hit.has("normal") and hit["normal"] is Vector3 else Vector3.ZERO
		if hit_normal.length() < 0.001:
			continue
		if p._is_surface_alignment_rejected(
			hit.get("collider"),
			hit_normal,
			up,
			int(hit.get("shape", -1))
		):
			continue

		var hit_distance: float = origin.distance_to(hit_position)
		if hit_distance > max_distance + 0.001:
			continue

		var dot_up: float = clamp(hit_normal.normalized().dot(up), -1.0, 1.0)
		var angle_deg: float = rad_to_deg(acos(dot_up))
		var is_floor_like: bool = dot_up > 0.0 and angle_deg <= p.floor_like_max_angle_deg

		if is_floor_like:
			if not best_floor_hit or hit_distance < best_floor_distance:
				best_floor_hit = true
				best_floor_distance = hit_distance
				best_floor_point = hit_position
				best_floor_normal = hit_normal.normalized()
		elif p.lightspeed_dash_auto_attach_allow_wall_fallback:
			if not best_any_hit or hit_distance < best_any_distance:
				best_any_hit = true
				best_any_distance = hit_distance
				best_any_point = hit_position
				best_any_normal = hit_normal.normalized()

	if best_floor_hit:
		result["position"] = best_floor_point
		result["normal"] = best_floor_normal
		result["kind"] = "preferred"
		return result

	if best_any_hit:
		result["position"] = best_any_point
		result["normal"] = best_any_normal
		result["kind"] = "fallback"

	return result


func _stop_lightspeed_dash_if_active(apply_release_velocity: bool = false) -> void:
	var p = _owner
	if p._lightspeed_dash_active:
		_end_lightspeed_dash(apply_release_velocity, false)
		return
	p._lightspeed_dash_target = null
	p._lightspeed_dash_prev_ring = null
	p._lightspeed_raycast_cache.clear()
	p._lightspeed_dash_speed = 0.0
	p._lightspeed_dash_release_velocity = Vector3.ZERO
	p._lightspeed_dash_last_dir = Vector3.ZERO
	p._lightspeed_dash_timer = 0.0

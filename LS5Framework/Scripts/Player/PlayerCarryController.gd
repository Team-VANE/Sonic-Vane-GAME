extends RefCounted
class_name PlayerCarryController

const CharacterActionType = preload("res://LS5Framework/Scripts/Player/character_action.gd")

# Carryable discovery, ownership, placement, throwing, and animation integration.
var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func is_carrying_object() -> bool:
	var p = _owner
	return _has_carried_object()


func _has_carried_object() -> bool:
	var p = _owner
	return p._carried_object and is_instance_valid(p._carried_object)


func _process_carry_action_inputs() -> bool:
	var p = _owner
	if not p.carry_objects_enabled:
		return false
	if p._carry_throw_pending_release:
		return false
	if p._action_input_locked():
		return false
	if p.carry_throw_input_action != &"" and _has_carried_object():
		if SettingsManager.is_gameplay_action_just_pressed(String(p.carry_throw_input_action)):
			_throw_carried_object()
			return true
	if p.carry_put_down_input_action != &"" and p.carry_put_down_input_action != &"interact" and _has_carried_object():
		if SettingsManager.is_gameplay_action_just_pressed(String(p.carry_put_down_input_action)):
			_put_down_carried_object()
			return true
	if p.carry_pickup_input_action != &"" and p.carry_pickup_input_action != &"interact" and not _has_carried_object():
		if SettingsManager.is_gameplay_action_just_pressed(String(p.carry_pickup_input_action)):
			return _try_pick_up_carryable()
	return false


func _try_handle_carry_interact() -> bool:
	var p = _owner
	if not p.carry_objects_enabled:
		return false
	if p._carry_throw_pending_release:
		return false
	if p.carry_pickup_input_action != &"interact" and p.carry_put_down_input_action != &"interact":
		return false
	if p._action_input_locked():
		return false
	if _has_carried_object():
		if p.carry_put_down_input_action != &"interact":
			return false
		if _should_throw_carried_object_from_interact():
			_throw_carried_object()
		else:
			_put_down_carried_object()
		return true
	if p.carry_pickup_input_action != &"interact":
		return false
	return _try_pick_up_carryable()


func _try_pick_up_carryable() -> bool:
	var p = _owner
	if not _can_pick_up_carryable_now():
		return false
	var carryable: Node3D = _find_best_carryable_object()
	if not carryable:
		return false
	var target_transform: Transform3D = _get_carry_target_transform()
	if not carryable.has_method("begin_carry"):
		return false
	var handled: Variant = carryable.call("begin_carry", p, target_transform, p.carry_release_player_collision_lock)
	if handled is bool and not bool(handled):
		return false
	p._carried_object = carryable
	_clear_active_action_if_carry_blocked()
	_request_carry_pickup_animation()
	if p.has_method("register_combo_feat"):
		p.register_combo_feat(&"object_pickup", "Object Pickup", 75.0, 0.5)
	return true


func _put_down_carried_object() -> void:
	var p = _owner
	if not _has_carried_object():
		p._carried_object = null
		return
	var carryable: Node3D = p._carried_object
	p._carry_put_down_release_transform = _get_safe_carry_put_down_transform(carryable)
	p._carry_put_down_release_velocity = p.velocity * max(p.carry_release_inherit_velocity_scale, 0.0)
	p._carry_put_down_pending_release = true
	p._carry_put_down_anim_started = false
	p._carry_put_down_release_wait_frames = 2
	_force_carry_overlay_blend_visible()
	if _play_carry_overlay_state(p.carry_put_down_overlay_state):
		return
	if p.carry_put_down_anim_command != &"":
		p._trigger_anim_command(p.carry_put_down_anim_command)
		return
	release_carried_object_from_put_down_animation()


func release_carried_object_from_put_down_animation() -> void:
	var p = _owner
	if not _has_carried_object():
		_clear_pending_carry_put_down()
		return
	var carryable: Node3D = p._carried_object
	if not p._carry_put_down_pending_release:
		p._carry_put_down_release_transform = _get_safe_carry_put_down_transform(carryable)
		p._carry_put_down_release_velocity = p.velocity * max(p.carry_release_inherit_velocity_scale, 0.0)
		p._carry_put_down_pending_release = true
	var release_velocity: Vector3 = p.velocity * max(p.carry_release_inherit_velocity_scale, 0.0)
	var release_data: Dictionary = _prepare_carry_release(carryable, false, release_velocity)
	if release_data.is_empty():
		_clear_pending_carry_put_down()
		return
	p._carry_put_down_release_transform = release_data.get("transform", p._carry_put_down_release_transform)
	p._carry_put_down_release_velocity = release_data.get("velocity", release_velocity)
	if carryable.has_method("put_down"):
		carryable.call("put_down", p._carry_put_down_release_transform, p._carry_put_down_release_velocity, p.carry_release_player_collision_lock)
	elif carryable.has_method("release_carry"):
		carryable.call("release_carry", p._carry_put_down_release_transform, p._carry_put_down_release_velocity, p.carry_release_player_collision_lock)
	if p.has_method("register_combo_feat"):
		p.register_combo_feat(&"object_placed", "Object Placed", 100.0, 0.6)
	p._carried_object = null
	_clear_pending_carry_put_down()


func _clear_pending_carry_put_down() -> void:
	var p = _owner
	p._carry_pickup_pending_overlay = false
	p._carry_pickup_overlay_started = false
	p._carry_put_down_pending_release = false
	p._carry_put_down_anim_started = false
	p._carry_put_down_release_wait_frames = 0
	p._carry_put_down_release_transform = Transform3D.IDENTITY
	p._carry_put_down_release_velocity = Vector3.ZERO


func _throw_carried_object() -> void:
	var p = _owner
	if not _has_carried_object():
		p._carried_object = null
		return
	p._carry_throw_release_transform = Transform3D.IDENTITY
	p._carry_throw_release_velocity = Vector3.ZERO
	p._carry_throw_pending_release = true
	p._carry_throw_anim_started = false
	p._carry_throw_release_wait_frames = 2
	if p.carry_throw_anim_command != &"":
		p._trigger_anim_command(p.carry_throw_anim_command)
		return
	release_carried_object_from_throw_animation()


func release_carried_object_from_throw_animation() -> void:
	var p = _owner
	if not p._carry_throw_pending_release:
		return
	if not _has_carried_object():
		_clear_pending_carry_throw()
		return
	var carryable: Node3D = p._carried_object
	var release_velocity: Vector3 = _get_carry_throw_release_velocity()
	var release_data: Dictionary = _prepare_carry_release(carryable, true, release_velocity)
	if release_data.is_empty():
		_clear_pending_carry_throw()
		return
	var release_transform: Transform3D = release_data.get("transform", _get_carry_fallback_target_transform())
	release_velocity = release_data.get("velocity", release_velocity)
	var side_fallback: bool = bool(release_data.get("side_fallback", false))
	if side_fallback and carryable.has_method("put_down"):
		carryable.call("put_down", release_transform, release_velocity, p.carry_release_player_collision_lock)
	elif carryable.has_method("throw_from_carry"):
		carryable.call("throw_from_carry", release_transform, release_velocity, p.carry_release_player_collision_lock)
	elif carryable.has_method("release_carry"):
		carryable.call("release_carry", release_transform, release_velocity, p.carry_release_player_collision_lock)
	if not side_fallback:
		p.play_voice_event(&"carry_throw")
		if p.has_method("register_combo_feat"):
			p.register_combo_feat(&"object_throw", "Object Throw", 175.0, 0.8)
	p._carried_object = null
	_clear_pending_carry_throw()


func _get_carry_throw_release_velocity() -> Vector3:
	var p = _owner
	var up: Vector3 = _get_carry_up()
	var forward: Vector3 = _get_carry_forward(up)
	var inherited_velocity: Vector3 = p.velocity * max(p.carry_release_inherit_velocity_scale, 0.0)
	return inherited_velocity + forward * max(p.carry_throw_forward_speed, 0.0) + up * p.carry_throw_up_speed


func _prepare_carry_release(carryable: Node3D, is_throw: bool, release_velocity: Vector3) -> Dictionary:
	var p = _owner
	var normal_transform: Transform3D = _get_standard_carry_release_transform(is_throw, p.global_position)
	if not is_throw:
		normal_transform = _get_safe_carry_put_down_transform(carryable)
	var normal_release: Dictionary = {
		"transform": normal_transform,
		"velocity": release_velocity,
		"side_fallback": false,
	}
	if not p.carry_release_wall_avoidance_enabled:
		return normal_release
	if p.carry_release_wall_avoidance_mask <= 0:
		return normal_release
	var world: World3D = p.get_world_3d()
	if world == null:
		return normal_release
	var up: Vector3 = _get_carry_up()
	var forward: Vector3 = _get_carry_forward(up)
	var standard_transform: Transform3D = _get_standard_carry_release_transform(is_throw, p.global_position)
	var ray_origin: Vector3 = p.global_position + up * (carryable.global_position - p.global_position).dot(up)
	var forward_distance: float = max((standard_transform.origin - p.global_position).dot(forward), 0.0)
	var clearance_radius: float = max(p.carry_put_down_clearance_radius, 0.01)
	var wall_margin: float = max(p.carry_release_wall_clearance_margin, 0.0)
	var clearance_distance: float = max(
		max(p.carry_release_wall_clearance_distance, 0.0),
		forward_distance + clearance_radius
	) + wall_margin
	var wall_hit: Dictionary = _cast_carry_release_wall_ray(carryable, ray_origin, forward, clearance_distance, world)
	if wall_hit.is_empty():
		if _is_carry_release_transform_clear(normal_transform, carryable, up, world):
			return normal_release
		return _get_carry_side_fallback_release(carryable, up, forward, world)
	var hit_position: Vector3 = wall_hit.get("position", ray_origin)
	var hit_distance: float = clamp((hit_position - ray_origin).dot(forward), 0.0, clearance_distance)
	var pushback_distance: float = max(clearance_distance - hit_distance, 0.0)
	var pushback_motion: Vector3 = -forward * pushback_distance
	if pushback_motion.length() > 0.001 and not p.test_move(p.global_transform, pushback_motion):
		var predicted_player_position: Vector3 = p.global_position + pushback_motion
		var predicted_transform: Transform3D = _get_standard_carry_release_transform(is_throw, predicted_player_position)
		if _is_carry_release_transform_clear(predicted_transform, carryable, up, world):
			p.global_position = predicted_player_position
			_update_carried_object_target()
			return {
				"transform": predicted_transform,
				"velocity": release_velocity,
				"side_fallback": false,
			}
	return _get_carry_side_fallback_release(carryable, up, forward, world)


func _get_standard_carry_release_transform(is_throw: bool, player_position: Vector3) -> Transform3D:
	var p = _owner
	var up: Vector3 = _get_carry_up()
	var forward: Vector3 = _get_carry_forward(up)
	if is_throw:
		var right: Vector3 = forward.cross(up)
		if right.length() < 0.001:
			right = p.global_transform.basis.x
		right = right.normalized()
		var offset: Vector3 = p.carry_fallback_offset
		var throw_position: Vector3 = player_position + right * offset.x + up * offset.y - forward * offset.z
		return Transform3D(Basis().looking_at(forward, up), throw_position)
	var put_down_position: Vector3 = player_position + forward * max(p.carry_put_down_forward_distance, 0.0) + up * p.carry_put_down_up_offset
	return Transform3D(Basis().looking_at(forward, up), put_down_position)


func _cast_carry_release_wall_ray(
	carryable: Node3D,
	from_position: Vector3,
	forward: Vector3,
	distance: float,
	world: World3D
) -> Dictionary:
	var p = _owner
	if distance <= 0.001:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_position,
		from_position + forward * distance
	)
	query.collision_mask = p.carry_release_wall_avoidance_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	query.exclude = [p, carryable]
	return world.direct_space_state.intersect_ray(query)


func _get_carry_side_fallback_release(
	carryable: Node3D,
	up: Vector3,
	forward: Vector3,
	world: World3D
) -> Dictionary:
	var side_transform: Variant = _find_safe_carry_side_transform(carryable, up, forward, world)
	if not (side_transform is Transform3D):
		return {}
	return {
		"transform": side_transform,
		"velocity": Vector3.ZERO,
		"side_fallback": true,
	}


func _find_safe_carry_side_transform(carryable: Node3D, up: Vector3, forward: Vector3, world: World3D) -> Variant:
	var p = _owner
	var right: Vector3 = forward.cross(up)
	if right.length() < 0.001:
		right = p.global_transform.basis.x
	right = right.normalized()
	var basis: Basis = Basis().looking_at(forward, up)
	var base_side_distance: float = max(p.carry_release_side_placement_distance, 0.0)
	var side_extra: float = max(p.carry_release_side_search_extra, 0.0)
	var side_steps: int = maxi(p.carry_release_side_search_steps, 0)
	var up_steps: int = maxi(p.carry_put_down_safe_up_steps, 0)
	var up_distance: float = max(p.carry_put_down_safe_up_distance, 0.0)
	var base_up_offset: float = max(p.carry_put_down_up_offset, p.carry_put_down_clearance_radius)
	var side_signs: Array[float] = [1.0, -1.0]
	for side_step: int in range(side_steps + 1):
		var side_distance: float = base_side_distance
		if side_steps > 0:
			side_distance += side_extra * float(side_step) / float(side_steps)
		for side_sign: float in side_signs:
			for up_step: int in range(up_steps + 1):
				var up_offset: float = base_up_offset
				if up_steps > 0:
					up_offset += up_distance * float(up_step) / float(up_steps)
				var candidate_position: Vector3 = p.global_position + right * side_distance * side_sign + up * up_offset
				var candidate_transform: Transform3D = Transform3D(basis, candidate_position)
				if _is_carry_put_down_transform_safe(candidate_transform, carryable, up, world):
					return candidate_transform
	return null


func _is_carry_release_transform_clear(
	candidate_transform: Transform3D,
	carryable: Node3D,
	up: Vector3,
	world: World3D
) -> bool:
	var p = _owner
	if not _is_carry_put_down_body_motion_safe(candidate_transform, carryable, up):
		return false
	var clearance_radius: float = max(p.carry_put_down_clearance_radius, 0.01)
	var clearance_up: float = max(p.carry_put_down_clearance_up_offset, 0.0)
	var clearance_offsets: Array[Vector3] = [
		Vector3.ZERO,
		up * clearance_up,
		-up * clearance_radius,
	]
	for clearance_offset: Vector3 in clearance_offsets:
		if _carry_put_down_clearance_overlaps(candidate_transform.origin + clearance_offset, clearance_radius, carryable, world):
			return false
	return true


func _update_carried_object_target() -> void:
	var p = _owner
	if not _has_carried_object():
		p._carried_object = null
		return
	if p._carried_object.has_method("is_carried"):
		var carried_state: Variant = p._carried_object.call("is_carried")
		if carried_state is bool and not bool(carried_state):
			p._carried_object = null
			return
	if p._carried_object.has_method("set_carry_target_transform"):
		p._carried_object.call("set_carry_target_transform", _get_carry_target_transform())


func _refresh_carried_object_target_after_external_motion() -> void:
	var p = _owner
	if not _has_carried_object():
		return
	_update_carried_object_target()


func _can_pick_up_carryable_now() -> bool:
	var p = _owner
	if not p.carry_objects_enabled:
		return false
	if _has_carried_object():
		return false
	if p._local_pause_enabled or p._ui_input_blocked or p._debug_mode:
		return false
	if p.get_tree() != null and p.get_tree().paused:
		return false
	if p.race_in_countdown and not p.race_active:
		return false
	if p._is_dead or p._hurt_active:
		return false
	if not p._active_action or not is_instance_valid(p._active_action):
		return true
	if not (p._active_action is CharacterActionType):
		return true
	var allows_pickup: Variant = p._active_action.get("can_pick_up_carryables_while_active")
	return not (allows_pickup is bool) or bool(allows_pickup)


func _can_execute_action_while_carrying(action: Node) -> bool:
	var p = _owner
	if not _has_carried_object():
		return true
	if not action or not is_instance_valid(action):
		return true
	if not (action is CharacterActionType):
		return true
	var allows_carry: Variant = action.get("can_execute_while_carrying")
	return not (allows_carry is bool) or bool(allows_carry)


func _clear_active_action_if_carry_blocked() -> void:
	var p = _owner
	if not p._active_action or not is_instance_valid(p._active_action):
		return
	if _can_execute_action_while_carrying(p._active_action):
		return
	p.clear_active_action()


func _find_best_carryable_object() -> Node3D:
	var p = _owner
	if p.get_tree() == null:
		return null
	var up: Vector3 = _get_carry_up()
	var forward: Vector3 = _get_carry_forward(up)
	var pickup_radius: float = _get_carry_pickup_radius(up)
	var best_object: Node3D = null
	var best_score: float = INF
	var carryables: Array = p.get_tree().get_nodes_in_group(p.carry_object_group)
	for carryable_variant in carryables:
		if not (carryable_variant is Node3D):
			continue
		var carryable: Node3D = carryable_variant as Node3D
		if not is_instance_valid(carryable):
			continue
		if carryable == p._carried_object:
			continue
		if carryable.has_method("can_be_carried_by"):
			var allowed: Variant = carryable.call("can_be_carried_by", p)
			if allowed is bool and not bool(allowed):
				continue
		var to_object: Vector3 = carryable.global_position - p.global_position
		var distance: float = to_object.length()
		if distance > pickup_radius:
			continue
		var lateral: Vector3 = to_object - up * to_object.dot(up)
		var forward_dot: float = 1.0
		if lateral.length() > 0.001:
			forward_dot = forward.dot(lateral.normalized())
		if forward_dot < p.carry_pickup_min_forward_dot:
			continue
		if not _can_reach_carryable_without_obstruction(carryable, up):
			continue
		var score: float = distance - forward_dot
		if score < best_score:
			best_score = score
			best_object = carryable
	return best_object


func _can_reach_carryable_without_obstruction(carryable: Node3D, up: Vector3) -> bool:
	var p = _owner
	if not p.carry_pickup_requires_clear_path:
		return true
	if p.carry_pickup_obstruction_mask <= 0:
		return true
	var world: World3D = p.get_world_3d()
	if world == null:
		return true
	var ray_up: Vector3 = up
	if ray_up.length() < 0.001:
		ray_up = p._get_gravity_up()
	ray_up = ray_up.normalized()
	var from_position: Vector3 = p.global_position + ray_up * max(p.carry_pickup_obstruction_start_up_offset, 0.0)
	var to_position: Vector3 = carryable.global_position + ray_up * max(p.carry_pickup_obstruction_target_up_offset, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_position, to_position)
	query.collision_mask = p.carry_pickup_obstruction_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [p, carryable]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _get_carry_pickup_radius(up: Vector3) -> float:
	var p = _owner
	var base_radius: float = max(p.carry_pickup_radius, 0.0)
	var lateral_velocity: Vector3 = p.velocity - up * p.velocity.dot(up)
	var speed_extra: float = lateral_velocity.length() * max(p.carry_pickup_speed_radius_scale, 0.0)
	speed_extra = min(speed_extra, max(p.carry_pickup_speed_radius_max, 0.0))
	return base_radius + speed_extra


func _should_throw_carried_object_from_interact() -> bool:
	var p = _owner
	if p._move_input.length() >= p.carry_interact_throw_input_threshold:
		return true
	var up: Vector3 = _get_carry_up()
	var lateral_velocity: Vector3 = p.velocity - up * p.velocity.dot(up)
	return lateral_velocity.length() >= max(p.carry_interact_throw_speed_threshold, 0.0)


func _get_carry_target_transform() -> Transform3D:
	var p = _owner
	var carry_bone_transform: Variant = _get_carry_bone_transform()
	if carry_bone_transform is Transform3D:
		return carry_bone_transform
	if p.carry_anchor and is_instance_valid(p.carry_anchor):
		return _get_unscaled_carry_transform(p.carry_anchor.global_transform)
	return _get_carry_fallback_target_transform()


func _get_carry_fallback_target_transform() -> Transform3D:
	var p = _owner
	return _get_standard_carry_release_transform(true, p.global_position)


func _get_unscaled_carry_transform(source_transform: Transform3D) -> Transform3D:
	var p = _owner
	return Transform3D(source_transform.basis.orthonormalized(), source_transform.origin)


func _get_carry_bone_transform() -> Variant:
	var p = _owner
	if p.carry_bone_name == &"":
		return null
	var skeleton: Skeleton3D = _get_carry_skeleton()
	if not skeleton:
		return null
	var bone_index: int = skeleton.find_bone(String(p.carry_bone_name))
	if bone_index < 0:
		return null
	var anchor_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	var target_transform: Transform3D = anchor_transform * p.carry_bone_offset
	if p.carry_orientation_bone_name == &"":
		return _get_unscaled_carry_transform(target_transform)
	var orientation_bone_index: int = skeleton.find_bone(String(p.carry_orientation_bone_name))
	if orientation_bone_index < 0:
		return _get_unscaled_carry_transform(target_transform)
	var orientation_transform: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(orientation_bone_index)
	target_transform.basis = orientation_transform.basis.orthonormalized() * p.carry_bone_offset.basis.orthonormalized()
	return _get_unscaled_carry_transform(target_transform)


func _get_carry_skeleton() -> Skeleton3D:
	var p = _owner
	if p.carry_skeleton and is_instance_valid(p.carry_skeleton):
		return p.carry_skeleton
	if p.model_root and is_instance_valid(p.model_root):
		return p._find_first_skeleton(p.model_root)
	return null


func _get_carry_put_down_transform() -> Transform3D:
	var p = _owner
	return _get_standard_carry_release_transform(false, p.global_position)


func _get_safe_carry_put_down_transform(carryable: Node3D) -> Transform3D:
	var p = _owner
	var desired_transform: Transform3D = _get_carry_put_down_transform()
	if not p.carry_put_down_validate_placement:
		return desired_transform
	if p.carry_put_down_placement_mask <= 0:
		return desired_transform
	var world: World3D = p.get_world_3d()
	if world == null:
		return desired_transform
	var up: Vector3 = _get_carry_up()
	var forward: Vector3 = _get_carry_forward(up)
	var right: Vector3 = forward.cross(up)
	if right.length() < 0.001:
		right = p.global_transform.basis.x
	right = right.normalized()
	var candidate_positions: Array[Vector3] = _get_carry_put_down_candidate_positions(desired_transform.origin, forward, right, up)
	var best_transform: Transform3D = _get_unscaled_carry_transform(carryable.global_transform)
	var best_score: float = INF
	for candidate_position: Vector3 in candidate_positions:
		var candidate_transform: Transform3D = Transform3D(desired_transform.basis, candidate_position)
		if not _is_carry_put_down_transform_safe(candidate_transform, carryable, up, world):
			continue
		var forward_distance: float = max((candidate_position - p.global_position).dot(forward), 0.0)
		var side_distance: float = abs((candidate_position - desired_transform.origin).dot(right))
		var up_distance: float = abs((candidate_position - desired_transform.origin).dot(up))
		var score: float = desired_transform.origin.distance_to(candidate_position) + side_distance * 0.35 + up_distance * 0.2 + forward_distance * 0.05
		if score < best_score:
			best_score = score
			best_transform = Transform3D(desired_transform.basis, candidate_position)
	return best_transform


func _get_carry_put_down_candidate_positions(origin: Vector3, forward: Vector3, right: Vector3, up: Vector3) -> Array[Vector3]:
	var p = _owner
	var candidates: Array[Vector3] = [origin]
	var forward_steps: int = maxi(p.carry_put_down_safe_forward_steps, 0)
	var side_steps: int = maxi(p.carry_put_down_safe_side_steps, 0)
	var up_steps: int = maxi(p.carry_put_down_safe_up_steps, 0)
	var forward_extra: float = max(p.carry_put_down_safe_forward_extra, 0.0)
	var side_distance: float = max(p.carry_put_down_safe_side_distance, 0.0)
	var up_distance: float = max(p.carry_put_down_safe_up_distance, 0.0)
	for forward_step: int in range(forward_steps + 1):
		var forward_offset: float = 0.0
		if forward_steps > 0:
			forward_offset = forward_extra * float(forward_step) / float(forward_steps)
		for up_step: int in range(up_steps + 1):
			var up_offset: float = 0.0
			if up_steps > 0:
				up_offset = up_distance * float(up_step) / float(up_steps)
			for side_step: int in range(-side_steps, side_steps + 1):
				var side_offset: float = 0.0
				if side_steps > 0:
					side_offset = side_distance * float(side_step) / float(side_steps)
				var candidate_position: Vector3 = origin + forward * forward_offset + right * side_offset + up * up_offset
				if candidate_position.distance_squared_to(origin) <= 0.0001:
					continue
				candidates.append(candidate_position)
	return candidates


func _is_carry_put_down_transform_safe(candidate_transform: Transform3D, carryable: Node3D, up: Vector3, world: World3D) -> bool:
	var p = _owner
	if not _is_carry_put_down_body_motion_safe(candidate_transform, carryable, up):
		return false
	var candidate_position: Vector3 = candidate_transform.origin
	var clearance_radius: float = max(p.carry_put_down_clearance_radius, 0.01)
	var clearance_up: float = max(p.carry_put_down_clearance_up_offset, 0.0)
	var clearance_offsets: Array[Vector3] = [
		Vector3.ZERO,
		up * clearance_up,
		-up * clearance_radius,
	]
	for clearance_offset: Vector3 in clearance_offsets:
		if _carry_put_down_clearance_overlaps(candidate_position + clearance_offset, clearance_radius, carryable, world):
			return false
	var from_position: Vector3 = p.global_position + up * max(p.carry_put_down_obstruction_start_up_offset, 0.0)
	var to_position: Vector3 = candidate_position + up * clearance_up
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_position, to_position)
	ray_query.collision_mask = p.carry_put_down_placement_mask
	ray_query.collide_with_areas = false
	ray_query.collide_with_bodies = true
	ray_query.exclude = _get_carry_put_down_query_excludes(carryable)
	var hit: Dictionary = world.direct_space_state.intersect_ray(ray_query)
	return hit.is_empty()


func _is_carry_put_down_body_motion_safe(candidate_transform: Transform3D, carryable: Node3D, up: Vector3) -> bool:
	var p = _owner
	if not (carryable is PhysicsBody3D):
		return true
	var body: PhysicsBody3D = carryable as PhysicsBody3D
	var test_parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	test_parameters.from = candidate_transform
	test_parameters.motion = Vector3.ZERO
	test_parameters.margin = max(p.carry_put_down_body_test_margin, 0.0)
	test_parameters.recovery_as_collision = true
	test_parameters.exclude_bodies = [p.get_rid()]
	if PhysicsServer3D.body_test_motion(body.get_rid(), test_parameters):
		return false
	var nudge_parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	nudge_parameters.from = candidate_transform
	nudge_parameters.motion = -up * max(p.carry_put_down_body_test_margin, 0.01)
	nudge_parameters.margin = max(p.carry_put_down_body_test_margin, 0.0)
	nudge_parameters.recovery_as_collision = true
	nudge_parameters.exclude_bodies = [p.get_rid()]
	return not PhysicsServer3D.body_test_motion(body.get_rid(), nudge_parameters)


func _carry_put_down_clearance_overlaps(position: Vector3, radius: float, carryable: Node3D, world: World3D) -> bool:
	var p = _owner
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = radius
	var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = shape
	shape_query.transform = Transform3D(Basis.IDENTITY, position)
	shape_query.collision_mask = p.carry_put_down_placement_mask
	shape_query.collide_with_areas = false
	shape_query.collide_with_bodies = true
	shape_query.exclude = _get_carry_put_down_query_excludes(carryable)
	var overlaps: Array[Dictionary] = world.direct_space_state.intersect_shape(shape_query, 1)
	return not overlaps.is_empty()


func _get_carry_put_down_query_excludes(carryable: Node3D) -> Array[RID]:
	var p = _owner
	var excludes: Array[RID] = [p.get_rid()]
	if carryable is CollisionObject3D:
		excludes.append((carryable as CollisionObject3D).get_rid())
	return excludes


func _get_carry_up() -> Vector3:
	var p = _owner
	var up: Vector3 = p.visual_up
	if up.length() < 0.001:
		up = p._get_gravity_up()
	return up.normalized()


func _get_carry_forward(up: Vector3) -> Vector3:
	var p = _owner
	var forward: Vector3 = -p.global_transform.basis.z
	if p.model_root and is_instance_valid(p.model_root):
		forward = -p.model_root.global_transform.basis.z
	forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = p._move_direction
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = p._control_forward
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = -p.global_transform.basis.z
	return forward.normalized()


func _update_carry_animation(delta: float) -> void:
	var p = _owner
	if p.carry_hold_blend_parameter == "":
		return
	_update_carry_overlay_state()
	var target_blend: float = 0.0
	if _has_carried_object() and not p._carry_throw_pending_release:
		target_blend = 1.0
	var blend_speed: float = max(p.carry_hold_blend_speed, 0.0)
	if blend_speed <= 0.0 or delta <= 0.0:
		p._carry_hold_blend_value = target_blend
	else:
		p._carry_hold_blend_value = move_toward(p._carry_hold_blend_value, target_blend, blend_speed * delta)
	p._safe_set_anim_param(p.carry_hold_blend_parameter, p._carry_hold_blend_value)


func _force_carry_overlay_blend_visible() -> void:
	var p = _owner
	p._carry_hold_blend_value = 1.0
	if p.carry_hold_blend_parameter != "":
		p._safe_set_anim_param(p.carry_hold_blend_parameter, p._carry_hold_blend_value)


func _request_carry_pickup_animation() -> void:
	var p = _owner
	p._carry_pickup_pending_overlay = p.carry_pickup_overlay_state != &""
	p._carry_pickup_overlay_started = false
	_force_carry_overlay_blend_visible()
	if _play_carry_overlay_state(p.carry_pickup_overlay_state):
		p._carry_pickup_overlay_started = true
		return
	if p.carry_pickup_request_parameter != "":
		_request_anim_oneshot(p.carry_pickup_request_parameter)
	if p.carry_pickup_anim_command != &"":
		p._trigger_anim_command(p.carry_pickup_anim_command)


func _initialize_carry_overlay_animation() -> void:
	var p = _owner
	p._carry_hold_blend_value = 0.0
	if p.anim_tree != null and p.carry_hold_blend_parameter != "" and p._anim_param_exists(p.carry_hold_blend_parameter):
		p.anim_tree.set(p.carry_hold_blend_parameter, 0.0)
	if p._carry_overlay_state != null and p.carry_hold_overlay_state != &"":
		if p._carry_overlay_state.has_method("start"):
			p._carry_overlay_state.start(p.carry_hold_overlay_state)
		else:
			p._carry_overlay_state.travel(p.carry_hold_overlay_state)


func _update_carry_overlay_state() -> void:
	var p = _owner
	if p._carry_overlay_state == null:
		return
	if not _has_carried_object() or p._carry_throw_pending_release:
		return
	if p._carry_put_down_pending_release:
		var put_down_node: StringName = p._carry_overlay_state.get_current_node()
		if put_down_node != p.carry_put_down_overlay_state:
			_play_carry_overlay_state(p.carry_put_down_overlay_state)
		return
	var current_node: StringName = p._carry_overlay_state.get_current_node()
	if p._carry_pickup_pending_overlay:
		if current_node != p.carry_pickup_overlay_state:
			if _play_carry_overlay_state(p.carry_pickup_overlay_state):
				p._carry_pickup_overlay_started = true
			return
		p._carry_pickup_overlay_started = true
		if _is_anim_playback_finished(p._carry_overlay_state, p.carry_command_exit_time_margin):
			p._carry_pickup_pending_overlay = false
			p._carry_pickup_overlay_started = false
			_play_carry_overlay_state(p.carry_hold_overlay_state)
		return
	if current_node == p.carry_pickup_overlay_state:
		if _is_anim_playback_finished(p._carry_overlay_state, p.carry_command_exit_time_margin):
			_play_carry_overlay_state(p.carry_hold_overlay_state)
		return
	if current_node != p.carry_hold_overlay_state:
		_play_carry_overlay_state(p.carry_hold_overlay_state)


func _play_carry_overlay_state(state_name: StringName) -> bool:
	var p = _owner
	if state_name == &"":
		return false
	if p._carry_overlay_state == null:
		return false
	if p._carry_overlay_state.has_method("start"):
		p._carry_overlay_state.start(state_name)
	else:
		p._carry_overlay_state.travel(state_name)
	return true


func _configure_carry_overlay_filter() -> void:
	var p = _owner
	if p.anim_tree == null:
		return
	if p.carry_hold_blend_parameter == "":
		return
	var root = p.anim_tree.tree_root
	if not (root is AnimationNodeBlendTree):
		return
	var blend_tree: AnimationNodeBlendTree = root
	var overlay_node_name: StringName = _get_blend_tree_node_name_from_parameter(p.carry_hold_blend_parameter)
	if overlay_node_name == &"":
		return
	if not blend_tree.has_node(overlay_node_name):
		return
	var overlay_node: AnimationNode = blend_tree.get_node(overlay_node_name)
	if overlay_node == null:
		return
	overlay_node.set("filter_enabled", true)
	for bone_name: StringName in p.carry_overlay_filter_bones:
		if bone_name == &"":
			continue
		var filter_path: NodePath = NodePath("%s:%s" % [String(p.carry_overlay_skeleton_filter_path), String(bone_name)])
		overlay_node.set_filter_path(filter_path, true)


func _get_blend_tree_node_name_from_parameter(parameter_path: String) -> StringName:
	var p = _owner
	var node_path: String = parameter_path
	var parameters_prefix: String = "parameters/"
	if node_path.begins_with(parameters_prefix):
		node_path = node_path.substr(parameters_prefix.length())
	var slash_index: int = node_path.find("/")
	if slash_index >= 0:
		node_path = node_path.substr(0, slash_index)
	return StringName(node_path)


func is_carry_animation_locked() -> bool:
	var p = _owner
	if p._carry_put_down_pending_release:
		return true
	if p._carry_throw_pending_release:
		return true
	if p.anim_state == null:
		return false
	var current_node: StringName = p.anim_state.get_current_node()
	if p.carry_throw_anim_command != &"" and current_node == p.carry_throw_anim_command:
		return true
	if p.carry_pickup_anim_command != &"" and current_node == p.carry_pickup_anim_command:
		return true
	if p.carry_put_down_anim_command != &"" and current_node == p.carry_put_down_anim_command:
		return true
	return false


func _request_anim_oneshot(parameter_path: String) -> void:
	var p = _owner
	if parameter_path == "":
		return
	if p.anim_tree == null:
		return
	var path: String = parameter_path
	if not path.begins_with("parameters/"):
		path = "parameters/" + path
	if p._anim_param_exists(path):
		p.anim_tree.set(path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _update_pending_carry_put_down_release() -> void:
	var p = _owner
	if not p._carry_put_down_pending_release:
		return
	if p.carry_put_down_overlay_state != &"" and p._carry_overlay_state != null:
		var overlay_node: StringName = p._carry_overlay_state.get_current_node()
		if overlay_node == p.carry_put_down_overlay_state:
			p._carry_put_down_anim_started = true
			p._carry_put_down_release_wait_frames = 0
			if _is_anim_playback_finished(p._carry_overlay_state, p.carry_command_exit_time_margin):
				release_carried_object_from_put_down_animation()
			return
		if not p._carry_put_down_anim_started:
			if p._carry_put_down_release_wait_frames > 0:
				p._carry_put_down_release_wait_frames -= 1
				return
			release_carried_object_from_put_down_animation()
			return
		release_carried_object_from_put_down_animation()
		return
	if p.carry_put_down_anim_command == &"":
		release_carried_object_from_put_down_animation()
		return
	if p.anim_state == null:
		release_carried_object_from_put_down_animation()
		return
	var current_node: StringName = p.anim_state.get_current_node()
	if current_node == p.carry_put_down_anim_command:
		p._carry_put_down_anim_started = true
		p._carry_put_down_release_wait_frames = 0
		return
	if not p._carry_put_down_anim_started and _is_anim_traveling_to(p.carry_put_down_anim_command):
		p._carry_put_down_release_wait_frames = 0
		return
	if p._carry_put_down_release_wait_frames > 0:
		p._carry_put_down_release_wait_frames -= 1
		return
	if p._carry_put_down_anim_started:
		release_carried_object_from_put_down_animation()
		return
	release_carried_object_from_put_down_animation()


func _update_pending_carry_throw_release() -> void:
	var p = _owner
	if not p._carry_throw_pending_release:
		return
	if p.carry_throw_anim_command == &"":
		release_carried_object_from_throw_animation()
		return
	if p.anim_state == null:
		release_carried_object_from_throw_animation()
		return
	var current_node: StringName = p.anim_state.get_current_node()
	if current_node == p.carry_throw_anim_command:
		p._carry_throw_anim_started = true
		p._carry_throw_release_wait_frames = 0
		return
	if not p._carry_throw_anim_started and _is_anim_traveling_to(p.carry_throw_anim_command):
		p._carry_throw_release_wait_frames = 0
		return
	if p._carry_throw_release_wait_frames > 0:
		p._carry_throw_release_wait_frames -= 1
		return
	if p._carry_throw_anim_started:
		release_carried_object_from_throw_animation()
		return
	release_carried_object_from_throw_animation()


func _update_carry_command_animation_exit() -> void:
	var p = _owner
	if p.anim_state == null:
		return
	var current_node: StringName = p.anim_state.get_current_node()
	var should_return: bool = false
	if p.carry_throw_anim_command != &"" and current_node == p.carry_throw_anim_command:
		if _is_current_anim_state_finished(p.carry_command_exit_time_margin):
			if p._carry_throw_pending_release:
				release_carried_object_from_throw_animation()
			should_return = true
	elif p.carry_pickup_anim_command != &"" and current_node == p.carry_pickup_anim_command:
		should_return = _is_current_anim_state_finished(p.carry_command_exit_time_margin)
	elif p.carry_put_down_anim_command != &"" and current_node == p.carry_put_down_anim_command:
		if _is_current_anim_state_finished(p.carry_command_exit_time_margin):
			if p._carry_put_down_pending_release:
				release_carried_object_from_put_down_animation()
			should_return = true
	if should_return:
		var return_crossfade: float = 0.0
		if p.carry_throw_anim_command != &"" and current_node == p.carry_throw_anim_command:
			return_crossfade = p.carry_throw_return_crossfade
		_travel_to_carry_animation_return_state(return_crossfade)


func _is_current_anim_state_finished(exit_margin: float) -> bool:
	var p = _owner
	if p.anim_state == null:
		return false
	return _is_anim_playback_finished(p.anim_state, exit_margin)


func _is_anim_playback_finished(playback: AnimationNodeStateMachinePlayback, exit_margin: float) -> bool:
	var p = _owner
	if playback == null:
		return false
	var length: float = playback.get_current_length()
	if length <= 0.001:
		return false
	var play_position: float = playback.get_current_play_position()
	return play_position >= length - max(exit_margin, 0.0)


func _travel_to_carry_animation_return_state(crossfade: float = 0.0) -> void:
	var p = _owner
	if p.anim_state == null:
		return
	var return_state: StringName = p._get_respawn_animation_start_node()
	if return_state == &"":
		return
	if p.anim_state.get_current_node() == return_state:
		return
	_travel_anim_state_with_crossfade(return_state, crossfade)


func _travel_anim_state_with_crossfade(target_state: StringName, crossfade: float) -> void:
	var p = _owner
	if p.anim_state == null:
		return
	if crossfade <= 0.0:
		p.anim_state.travel(target_state)
		return
	var sm: AnimationNodeStateMachine = p._get_main_animation_state_machine()
	if sm == null:
		p.anim_state.travel(target_state)
		return
	var current_state: StringName = p.anim_state.get_current_node()
	var found_transition: bool = false
	for i in sm.get_transition_count():
		if sm.get_transition_to(i) != target_state:
			continue
		if current_state != &"" and sm.get_transition_from(i) != current_state:
			continue
		var transition: AnimationNodeStateMachineTransition = sm.get_transition(i)
		if transition:
			transition.xfade_time = max(crossfade, 0.0)
			found_transition = true
	if not found_transition and current_state != &"" and current_state != target_state:
		var new_transition: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
		new_transition.xfade_time = max(crossfade, 0.0)
		new_transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		new_transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		sm.add_transition(current_state, target_state, new_transition)
	p.anim_state.travel(target_state)


func _clear_pending_carry_throw() -> void:
	var p = _owner
	p._carry_pickup_pending_overlay = false
	p._carry_pickup_overlay_started = false
	p._carry_throw_pending_release = false
	p._carry_throw_anim_started = false
	p._carry_throw_release_wait_frames = 0
	p._carry_throw_release_transform = Transform3D.IDENTITY
	p._carry_throw_release_velocity = Vector3.ZERO


func _is_anim_traveling_to(state_name: StringName) -> bool:
	var p = _owner
	if p.anim_state == null:
		return false
	var travel_path = p.anim_state.get_travel_path()
	for path_node in travel_path:
		if StringName(path_node) == state_name:
			return true
	return false

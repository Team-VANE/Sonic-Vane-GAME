extends RefCounted
class_name PlayerSurfaceController

const SURFACE_METADATA = preload("res://LS5Framework/Scripts/World/SurfaceBehaviorMetadata.gd")

# Surface contact classification, attachment, ground following, and detachment.
var _owner: Node = null
var _collision_follow_valid: bool = false
var _collision_follow_normal: Vector3 = Vector3.ZERO
var _collision_follow_point: Vector3 = Vector3.ZERO
var _collision_follow_collider: Node3D = null
var _collision_follow_shape_index: int = -1
var _preview_ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func _init(owner: Node) -> void:
	_owner = owner
	_preview_ray_query.exclude = [(owner as CollisionObject3D).get_rid()]
	_preview_ray_query.collide_with_areas = false
	_preview_ray_query.hit_back_faces = false


func _process_collisions_for_attachment(v_before: Vector3, p_before: Vector3, delta: float) -> void:
	var p = _owner
	_clear_collision_follow_candidate()
	if p._movement_object_contact_handled:
		return
	var world_up: Vector3 = p._get_gravity_up()
	var collision_count: int = p.get_slide_collision_count()
	p._wall_input_contact_normals.clear()
	
	var in_spring_state: bool = p._is_spring_radial_landing_active()

	# For collision-based follow while already attached.
	var best_follow_normal: Vector3 = Vector3.ZERO
	var best_follow_point: Vector3 = Vector3.ZERO
	var best_follow_score: float = -1.0
	var best_follow_collider: Node3D = null
	var best_follow_shape_index: int = -1

	# var detach_to_floor: bool = false

	# Classify the current surface once against gravity-up.
	var curr_n: Vector3 = p.surface_normal.normalized()
	if curr_n.length() < 0.001:
		curr_n = world_up
	var curr_dot_up: float = clamp(curr_n.dot(world_up), -1.0, 1.0)
	var curr_angle_deg: float = rad_to_deg(acos(curr_dot_up))
	var curr_is_floor_like: bool = curr_angle_deg <= p.floor_like_max_angle_deg

	var sphere_contact: Dictionary = p._movement_sphere_contact
	var contact_count: int = collision_count + (0 if sphere_contact.is_empty() else 1)
	for i: int in range(contact_count):
		var slide_index: int = i - (0 if sphere_contact.is_empty() else 1)
		var col: KinematicCollision3D = p.get_slide_collision(slide_index) if slide_index >= 0 else null
		var collider: Object = col.get_collider() if col else instance_from_id(int(sphere_contact.collider_id))
		var collider_shape_index: int = col.get_collider_shape_index() if col else int(sphere_contact.shape)
		var hit_normal: Vector3 = col.get_normal() if col else sphere_contact.normal
		var hit_point: Vector3 = col.get_position() if col else sphere_contact.point
		var hit_velocity: Vector3 = col.get_collider_velocity() if col else sphere_contact.linear_velocity
		if collider and collider.has_meta("rail_node"):
			var rail_node = collider.get_meta("rail_node")
			if p._rail_switch_active and rail_node != p._rail_switch_target:
				continue
			if rail_node and rail_node.has_method("try_start_with_body"):
				rail_node.try_start_with_body(p, v_before, p_before)
				if p._rail_active:
					p._rail_switch_active = false
					return
				# If it's a rail but we didn't start grinding (e.g. cooldown), 
				# do not allow this collision to be treated as walkable ground.
				continue
		var preserves_player_momentum: bool = _surface_preserves_player_momentum(
			collider,
			collider_shape_index
		)
		var action_resolved_wall_velocity: bool = false
		if not preserves_player_momentum:
			p._record_wall_input_contact(hit_normal, p._physics_up_last, world_up)
			action_resolved_wall_velocity = p.resolve_current_action_wall_collision_velocity(
				hit_normal,
				world_up,
				v_before
			)
		if not preserves_player_momentum and not action_resolved_wall_velocity:
			_apply_wall_slide_and_friction(hit_normal, p._physics_up_last, world_up, delta, v_before)

		if p._is_surface_alignment_rejected(
			collider,
			hit_normal,
			world_up,
			collider_shape_index
		):
			if preserves_player_momentum:
				_preserve_boundary_slide_momentum(v_before, hit_normal, world_up)
			elif not p.attached:
				_preserve_rejected_collision_slide(v_before, hit_normal, world_up)
				p._dbg_radial_result = (
					"alignment_layer_block"
					if p._is_surface_alignment_blocked(collider)
					else "surface_attach_limit"
				)
			continue

		if p.attached:
			var n: Vector3 = hit_normal.normalized()
			if n.length() < 0.001:
				continue

			# ------------------------------------------------------------------
			# LOCAL-UP STEP ANGLE:
			# Ignore normals that are too different from the surface we're on.
			# This protects against sharp convex edges / backfaces, but still
			# allows smooth curves (loops, ramps) even if they become "wall-like"
			# relative to gravity-up.
			# ------------------------------------------------------------------
			var curr_up_local: Vector3 = p.surface_normal.normalized()
			if curr_up_local.length() < 0.001:
				curr_up_local = world_up

			var cos_step: float = clamp(curr_up_local.dot(n), -1.0, 1.0)
			var step_angle_deg: float = rad_to_deg(acos(cos_step))
			if (
				step_angle_deg > p.adhesion_max_step_angle_from_current_deg
				and not p._surface_launch_adhesion_active()
			):
				continue

						# Gravity-up classification for the nonfloor-to-floor rule.
				var dot_up: float = clamp(n.dot(world_up), -1.0, 1.0)
				var angle_deg: float = rad_to_deg(acos(dot_up))
				var new_is_floor_like: bool = angle_deg <= p.floor_like_max_angle_deg

				# --- Special case: non-floor surface + FLOOR contact + low speed ---
				if not curr_is_floor_like and new_is_floor_like:
					var speed_now: float = p.velocity.length()

					# If we've basically come to rest while touching the true floor,
					# give the floor priority instead of launching/detaching.
					if speed_now <= p.nonfloor_floor_detach_speed:
						# Hard-switch to the floor as our new surface.
						p.attached = true
						p.surface_normal = n
						p.surface_point = hit_point
						p._prev_surface_normal = n
						_set_collision_follow_candidate(
							n,
							hit_point,
							collider,
							collider_shape_index
						)

						# Kill any upward world-space velocity so we don't "pop" off.
						var v_tmp: Vector3 = p.velocity
						var up_comp: float = v_tmp.dot(world_up)
						if up_comp > 0.0:
							v_tmp -= world_up * up_comp
						p.velocity = v_tmp

						# From here on, treat this as floor-like for the rest of this step.
						curr_is_floor_like = true
						curr_n = n

					# In all cases, skip adhesion-follow for this contact.
					continue


			# From here on, let adhesion rules (LOCAL-UP based) decide if we can stay.
			if not _can_stay_attached(
				n,
				world_up,
				collider,
				collider_shape_index
			):
				continue

			var follow_score: float = cos_step
			if p._surface_launch_adhesion_active():
				var reference_speed: float = max(v_before.length(), 0.001)
				var impact_ratio: float = max(-v_before.dot(n), 0.0) / reference_speed
				follow_score = impact_ratio * 2.0 + cos_step * 0.25

			if follow_score > best_follow_score:
				best_follow_score = follow_score
				best_follow_normal = n
				best_follow_point = hit_point
				best_follow_collider = collider as Node3D if collider is Node3D else null
				best_follow_shape_index = collider_shape_index

			continue

		# --------------- Airborne → possible attach or bounce ---------------
		if p.current_action_blocks_surface_attachment():
			continue
		if p._attachment_immunity > 0.0 and not in_spring_state:
			# Normal behavior: during regular airtime, respect the immunity.
			continue

		# While in spring alignment, we *allow* attachment even if
		# attachment_immunity is still counting down.

		# Check for water surface landing (classic water running).
		var is_water: bool = p._is_water_collider(collider)
		var can_land_water: bool = p._can_land_on_water_surface(v_before, hit_normal)
		if _is_low_speed_detach_reattach_blocked(hit_normal, world_up):
			can_land_water = false
		if is_water and can_land_water:
			# Land on water surface (classic water running).
			p.attached = true
			p.surface_normal = hit_normal.normalized()
			p.surface_point = hit_point
			p._finish_spring_landing_state()
			p._start_water_surface_running(p.surface_normal)
			p._airborne_time = 0.0
			p._radial_attach_this_frame = true
			p._dbg_radial_result = "water_landing"
			p._loop_forward_dir = Vector3.ZERO

			p._pending_landing_velocity = p._apply_water_surface_landing_speed_penalty(
				v_before,
				p.surface_normal
			)
			p._pending_landing_has_velocity = true

			p._bounce_state = p.BounceState.NONE
			p.reset_flight_timer_to_max()
			break
		elif is_water and p.debug_mode_enabled:
			var metrics: Dictionary = PlayerMath.compute_radial_landing_metrics(v_before, hit_normal)
			print("[WATER DEBUG] Collision hit water but can't land: vel=%.1f, tan=%.1f, ang=%.1f, cooldown=%.2f" % [v_before.length(), metrics.tangent_speed, metrics.angle, p._water_reattach_cooldown_timer])
		if is_water:
			continue

		var collider_velocity: Vector3 = p.world_to_movement_velocity(hit_velocity)
		var can_attach_from_collision: bool = _can_attach_from_collision(
			v_before,
			hit_normal,
			world_up,
			hit_point,
			collider,
			collider_velocity
		)
		if not can_attach_from_collision:
			_preserve_rejected_collision_slide(v_before, hit_normal, world_up)

		if can_attach_from_collision:
			# If we are in bounce mode, perform a bounce instead of attaching.
			if p._bounce_state == p.BounceState.BOUNCE and p.bounce_enabled:
				p._do_bounce_landing(v_before, hit_normal)

				# Keep surface info for orientation if needed
				p.surface_normal = hit_normal.normalized()
				p.surface_point = hit_point

				# Do NOT set _pending_landing_velocity – this is not a normal landing.
				p._pending_landing_has_velocity = false

				# Stay airborne, so step 4 (landing momentum) does not run.
				return
			
			# Normal attach (including stomp / none)
			var was_stomp: bool = (p._bounce_state == p.BounceState.STOMP)
			
			# Normal attach (including stomp or no bounce)
			p.attached = true
			p.surface_normal = hit_normal.normalized()
			p.surface_point = hit_point
			p._finish_spring_landing_state()
			p._airborne_time = 0.0
			p._radial_attach_this_frame = p._dbg_radial_result == "accepted"
			p._dbg_radial_result = "attached" if p._radial_attach_this_frame else "floor_landing"
			p._loop_forward_dir = Vector3.ZERO
			p.reset_flight_timer_to_max()

			var landing_velocity: Vector3 = v_before
			if was_stomp:
				landing_velocity = p._apply_velocity_speed_subtraction(
					landing_velocity,
					hit_normal,
					p.stomp_land_speed_threshold,
					p.stomp_land_speed_subtract
				)
				landing_velocity = p._apply_horizontal_velocity_penalty(
					landing_velocity,
					hit_normal,
					p.stomp_land_horizontal_threshold,
					p.stomp_land_horizontal_subtract
				)

			p._pending_landing_velocity = landing_velocity
			p._pending_landing_has_velocity = true
			_set_collision_follow_candidate(
				hit_normal,
				hit_point,
				collider,
				collider_shape_index
			)
			
				# <<< SFX for stomp landing if we were stomping >>>
			if was_stomp:
				p._play_sfx(p.sfx_stomp_land)
				p._stomp_landing_flag = true

			# Once we attach, clear bounce/stomp state
			p._bounce_state = p.BounceState.NONE

			break

	# --------------- Apply follow / special detach ---------------
	if p.attached:
		if best_follow_score > -1.0:
			p._prev_surface_normal = p.surface_normal
			if p._surface_launch_adhesion_active():
				_rotate_velocity_with_surface(p._prev_surface_normal, best_follow_normal)
			p.surface_normal = best_follow_normal
			p.surface_point = best_follow_point
			_set_collision_follow_candidate(
				best_follow_normal,
				best_follow_point,
				best_follow_collider,
				best_follow_shape_index
			)

			var prev_n2: Vector3 = p._prev_surface_normal.normalized()
			var curr_n2: Vector3 = p.surface_normal.normalized()
			var dot_nd: float = clamp(prev_n2.dot(curr_n2), -1.0, 1.0)
			p._normal_delta_angle_deg = rad_to_deg(acos(dot_nd))
		#elif detach_to_floor:
			# We've run out of slope and gently bumped a floor.
			#_start_detach(surface_normal, world_up)


func _clear_collision_follow_candidate() -> void:
	_collision_follow_valid = false
	_collision_follow_normal = Vector3.ZERO
	_collision_follow_point = Vector3.ZERO
	_collision_follow_collider = null
	_collision_follow_shape_index = -1


func _set_collision_follow_candidate(
	normal: Vector3,
	point: Vector3,
	collider: Object,
	shape_index: int
) -> void:
	if normal.length() < 0.001 or not (collider is Node3D):
		return
	var collider_node: Node3D = collider as Node3D
	if not is_instance_valid(collider_node):
		return
	_collision_follow_valid = true
	_collision_follow_normal = normal.normalized()
	_collision_follow_point = point
	_collision_follow_collider = collider_node
	_collision_follow_shape_index = shape_index


func _apply_collision_follow_candidate() -> bool:
	var p = _owner
	if (
		not _collision_follow_valid
		or _collision_follow_collider == null
		or not is_instance_valid(_collision_follow_collider)
		or _collision_follow_normal.length() < 0.001
	):
		return false
	p._follow_hit = true
	p._follow_normal = _collision_follow_normal
	p._follow_point = _collision_follow_point
	p._follow_collider_last = _collision_follow_collider
	p._follow_collider_shape_last = _collision_follow_shape_index
	return true


func _collision_follow_is_excluded_by_ray(ray: RayCast3D) -> bool:
	if (
		not _collision_follow_valid
		or ray == null
		or not (_collision_follow_collider is CollisionObject3D)
	):
		return false
	var collision_object: CollisionObject3D = _collision_follow_collider as CollisionObject3D
	return (collision_object.collision_layer & ray.collision_mask) == 0


func _collision_follow_has_surface_metadata() -> bool:
	if not _collision_follow_valid or _collision_follow_collider == null:
		return false
	var p = _owner
	for metadata_key: StringName in SURFACE_METADATA.get_all_keys():
		if p._get_surface_metadata_value(
			_collision_follow_collider,
			metadata_key,
			_collision_follow_shape_index
		) != null:
			return true
	return false


func _try_ground_snap_attach(world_up: Vector3, v_before: Vector3 = Vector3.ZERO, p_before: Vector3 = Vector3.ZERO) -> void:
	var p = _owner
	if p.current_action_blocks_surface_attachment():
		return
	if not p.ground_snap_fix_enabled:
		return
	if p.attached:
		return
	if p.ground_ray == null:
		return
	if not p.ground_ray.is_colliding():
		return
	if p.ground_snap_max_distance <= 0.0:
		return
	if p._rail_active or p._spline_active or p._homing_active:
		return
	if p._spring_align_timer > 0.0:
		return
	if p._bounce_state != p.BounceState.NONE:
		return
	if p._lightspeed_dash_active:
		return
	if not p.ground_snap_ignore_attachment_immunity and p._attachment_immunity > 0.0:
		return

	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	# Only snap if we're close and not moving upward (prevents breaking launches).
	var vertical: float = p.velocity.dot(up)
	if vertical > 1.0:
		return

	var hit_collider = p.ground_ray.get_collider()
	var hit_shape_index: int = p.ground_ray.get_collider_shape()
	if hit_collider and hit_collider.has_meta("rail_node"):
		var rail_node = hit_collider.get_meta("rail_node")
		if rail_node and rail_node.has_method("try_start_with_body"):
			var v_query: Vector3 = p.velocity
			var p_query: Vector3 = p.global_position
			if v_before.length() > 0.001:
				v_query = v_before
			if p_before.length() > 0.001:
				p_query = p_before

			rail_node.try_start_with_body(p, v_query, p_query)
			if p._rail_active:
				return
			# If it's a rail but we didn't start grinding, do not snap to it as ground.
			return

	var hit_point: Vector3 = p.ground_ray.get_collision_point()
	var hit_normal: Vector3 = p.ground_ray.get_collision_normal().normalized()
	if hit_normal.length() < 0.001:
		return
	if p._is_surface_alignment_rejected(
		hit_collider,
		hit_normal,
		world_up,
		hit_shape_index
	):
		return
	if _is_low_speed_detach_reattach_blocked(hit_normal, world_up):
		return

	# Check for water surface landing via ground ray (classic water running).
	var hit_collider_for_water = p.ground_ray.get_collider()
	var is_water: bool = p._is_water_collider(hit_collider_for_water)
	if p.debug_mode_enabled and hit_collider_for_water != null:
		print("[WATER DEBUG] Ground ray hit: %s (is_water=%s)" % [hit_collider_for_water.name, is_water])
	var can_land: bool = p._can_land_on_water_surface(p.velocity, hit_normal)
	if is_water and can_land:
		p.velocity = p._apply_water_surface_landing_speed_penalty(p.velocity, hit_normal)
		p.attached = true
		p.surface_normal = hit_normal
		p._prev_surface_normal = hit_normal
		p._start_water_surface_running(hit_normal)
		p._finish_spring_landing_state()
		p._attachment_immunity = 0.0
		p._airborne_time = 0.0
		p._record_attach_state(p.surface_normal, world_up)
		p._ground_snap_attached_this_frame = true
		return
	elif is_water and p.debug_mode_enabled:
		var metrics: Dictionary = PlayerMath.compute_radial_landing_metrics(p.velocity, hit_normal)
		print("[WATER DEBUG] Ground ray hit water but can't land: vel=%.1f, tan=%.1f, ang=%.1f, cooldown=%.2f" % [p.velocity.length(), metrics.tangent_speed, metrics.angle, p._water_reattach_cooldown_timer])
	if is_water:
		var floor_hit: Dictionary = _get_ground_ray_hit_ignoring_water_surface()
		if floor_hit.is_empty():
			return
		hit_point = floor_hit.position
		hit_normal = (floor_hit.normal as Vector3).normalized()
		if hit_normal.length() < 0.001:
			return
		hit_collider = floor_hit.get("collider")
		hit_shape_index = int(floor_hit.get("shape", -1))
		if p._is_surface_alignment_rejected(
			hit_collider,
			hit_normal,
			world_up,
			hit_shape_index
		):
			return

	# Floor-like constraint.
	var dot_up: float = clamp(hit_normal.dot(up), -1.0, 1.0)
	var ang_deg: float = rad_to_deg(acos(dot_up))
	var snap_floor_angle: float = max(p.floor_like_max_angle_deg, 0.0)
	if p.surface_preview_enabled:
		snap_floor_angle = min(snap_floor_angle, max(p.surface_preview_floor_max_angle_deg, 0.0))
	if dot_up <= 0.0 or ang_deg > snap_floor_angle:
		return

	var dist: float = p.global_position.distance_to(hit_point)
	if dist > p.ground_snap_max_distance:
		return

	p.attached = true
	p.surface_normal = hit_normal
	p._prev_surface_normal = hit_normal
	p._finish_spring_landing_state()
	p._attachment_immunity = 0.0
	p._airborne_time = 0.0
	p._record_attach_state(p.surface_normal, world_up)
	p._ground_snap_attached_this_frame = true
	var snap_landing_velocity: Vector3 = v_before if v_before.length() > 0.001 else p.velocity
	if p._should_land_stationary(hit_normal, snap_landing_velocity):
		p.velocity = Vector3.ZERO


func _reconcile_grounded_state_after_move(world_up: Vector3) -> void:
	var p = _owner
	if not p.grounded_state_reconcile_enabled:
		return
	if p.attached:
		return
	if p._rail_active or p._rail_switch_active or p._spline_active:
		return
	if p._spring_align_timer > 0.0:
		return
	if p._lightspeed_dash_active or p._homing_active:
		return
	if p._bounce_state != p.BounceState.NONE:
		return
	if p._jumped_from_ground or p._jump_dash_recent_timer > 0.0:
		return
	if p._attachment_immunity > 0.0:
		return
	if p._active_action != null and p._active_action != p._fall_action:
		return

	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var vertical: float = p.velocity.dot(up)
	if vertical > p.grounded_state_reconcile_max_up_speed:
		return

	var best_normal: Vector3 = Vector3.ZERO
	var best_point: Vector3 = Vector3.ZERO
	var best_dot: float = -1.0
	var max_angle: float = max(p.grounded_state_reconcile_max_angle_deg, 0.0)
	if p.surface_preview_enabled:
		max_angle = min(max_angle, max(p.surface_preview_floor_max_angle_deg, 0.0))
	var min_dot: float = cos(deg_to_rad(max_angle))

	var collision_count: int = p.get_slide_collision_count()
	for i: int in range(collision_count):
		var col: KinematicCollision3D = p.get_slide_collision(i)
		if col == null:
			continue
		var collider = col.get_collider()
		if p._is_water_collider(collider):
			continue
		if collider != null and collider.has_meta("rail_node"):
			continue
		var n: Vector3 = col.get_normal().normalized()
		if n.length() < 0.001:
			continue
		if p._is_surface_alignment_rejected(
			collider,
			n,
			up,
			col.get_collider_shape_index()
		):
			continue
		var dot_up: float = n.dot(up)
		if dot_up < min_dot:
			continue
		if dot_up > best_dot:
			best_dot = dot_up
			best_normal = n
			best_point = col.get_position()

	if best_normal.length() < 0.001:
		return
	if _is_low_speed_detach_reattach_blocked(best_normal, up):
		return

	p.attached = true
	p.surface_normal = best_normal
	p.surface_point = best_point
	p._prev_surface_normal = best_normal
	p._finish_spring_landing_state()
	p._attachment_immunity = 0.0
	p._airborne_time = 0.0
	p._is_falling = false
	p._falling_without_jump = false
	p._jumped_from_ground = false
	p._loop_forward_dir = Vector3.ZERO
	p._ground_snap_attached_this_frame = true
	p._record_attach_state(p.surface_normal, up)
	if p._should_land_stationary(best_normal, p._pre_slide_velocity):
		p.velocity = Vector3.ZERO
	p._clear_coyote_jump_window()
	p._reset_fall_air_decel_ramp()
	p._reset_air_top_speed_ramp()
	p._clear_air_landing_align()
	if p._active_action == p._fall_action:
		p.clear_active_action()


func _get_ground_ray_hit_ignoring_water_surface() -> Dictionary:
	var p = _owner
	if p.ground_ray == null:
		return {}
	var world: World3D = p.get_world_3d()
	if world == null:
		return {}
	var ray_from: Vector3 = p.ground_ray.global_position
	var ray_to: Vector3 = p.ground_ray.to_global(p.ground_ray.target_position)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	params.exclude = [p]
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = p.ground_ray.collision_mask & ~p.WATER_SURFACE_RAY_LAYER
	return world.direct_space_state.intersect_ray(params)


func _can_attach_from_collision(
	v_before: Vector3,
	normal: Vector3,
	world_up: Vector3,
	hit_point: Vector3 = Vector3.ZERO,
	collider: Object = null,
	collider_velocity: Vector3 = Vector3.ZERO
) -> bool:
	var p = _owner
	if not p.surface_preview_enabled:
		return _can_attach_from_collision_legacy(v_before, normal, world_up)

	p._dbg_radial_result = "not_radial"
	var n: Vector3 = normal.normalized()
	var up: Vector3 = world_up.normalized()
	if n.length() < 0.001 or up.length() < 0.001:
		return false
	if _is_low_speed_detach_reattach_blocked(n, up):
		return false
	if _is_unconditional_floor_normal(n, up):
		p._dbg_radial_result = "floor_landing"
		return true

	var relative_velocity: Vector3 = v_before - collider_velocity
	var speed: float = relative_velocity.length()
	if speed < 0.0001:
		return false

	var in_spring_state: bool = p._is_spring_radial_landing_active()
	if not p.adhesion_enabled and not in_spring_state:
		return false
	if speed < p.radial_landing_min_speed:
		p._dbg_radial_result = "low_total_speed"
		return false

	var metrics: Dictionary = PlayerMath.compute_radial_landing_metrics(relative_velocity, n)
	var radial_angle: float = float(metrics.get("angle", 0.0))
	var into_speed: float = float(metrics.get("into_speed", 0.0))
	var tangential_speed: float = float(metrics.get("tangent_speed", 0.0))
	p._dbg_radial_angle = radial_angle
	p._dbg_radial_into_speed = into_speed
	p._dbg_radial_tangent_speed = tangential_speed
	p._dbg_radial_hit_timer = 0.25
	p._dbg_radial_result = "candidate"

	if into_speed <= 0.0:
		p._dbg_radial_result = "not_into_surface"
		return false

	var approach_angle_deg: float = 90.0 - radial_angle
	var min_approach_angle_deg: float = clamp(p.radial_landing_min_angle_deg, 0.0, 90.0)
	if approach_angle_deg < min_approach_angle_deg:
		p._dbg_radial_result = "head_on"
		return false
	if tangential_speed < p.radial_landing_min_speed:
		p._dbg_radial_result = "low_tangent_speed"
		return false

	var tangent: Vector3 = relative_velocity.slide(n)
	if tangent.length() < 0.001:
		p._dbg_radial_result = "no_surface_tangent"
		return false
	tangent = tangent.normalized()

	var preview: Dictionary = _preview_surface_path(
		hit_point,
		n,
		tangent,
		tangential_speed,
		collider
	)
	_store_surface_preview_debug(preview)
	if not bool(preview.get("accepted", false)):
		p._dbg_radial_result = String(preview.get("reason", "curve_rejected"))
		return false

	p._surface_support_curvature = float(preview.get("curvature", 0.0))
	p._surface_support_reaction_accel = float(preview.get("reaction_accel", 0.0))
	p._surface_support_timer = max(
		p._surface_support_timer,
		_get_surface_support_grace_time(tangential_speed)
	)
	p._dbg_radial_result = "accepted"
	return true


func _is_unconditional_floor_normal(normal: Vector3, world_up: Vector3) -> bool:
	var p = _owner
	var n: Vector3 = normal.normalized()
	var up: Vector3 = world_up.normalized()
	if n.length() < 0.001 or up.length() < 0.001:
		return false
	var max_angle_deg: float = clamp(p.surface_preview_floor_max_angle_deg, 0.0, 89.0)
	return n.dot(up) >= cos(deg_to_rad(max_angle_deg))


func _preview_surface_path(
	hit_point: Vector3,
	initial_normal: Vector3,
	initial_tangent: Vector3,
	tangential_speed: float,
	preferred_collider: Object
) -> Dictionary:
	var p = _owner
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var centers: Array[Vector3] = []
	var radius: float = _get_surface_preview_world_radius()
	var n: Vector3 = initial_normal.normalized()
	var tangent: Vector3 = initial_tangent.slide(n).normalized()
	var contact_point: Vector3 = hit_point
	var capture_debug_path: bool = p._debug_visible
	if preferred_collider == null and contact_point == Vector3.ZERO:
		contact_point = p.global_position - n * radius

	var initial_center: Vector3 = contact_point + n * radius
	if capture_debug_path:
		points.append(contact_point)
		normals.append(n)
		centers.append(initial_center)

	var min_lookahead: float = radius * max(p.surface_preview_min_lookahead_radii, 0.1)
	var max_lookahead: float = radius * max(
		p.surface_preview_max_lookahead_radii,
		p.surface_preview_min_lookahead_radii
	)
	var speed_lookahead: float = tangential_speed * max(p.surface_preview_time_horizon, 0.0)
	var lookahead: float = clamp(speed_lookahead, min_lookahead, max_lookahead)
	var target_spacing: float = max(radius * p.surface_preview_sample_spacing_radii, radius * 0.1)
	var min_samples: int = max(p.surface_preview_min_samples, 1)
	var max_samples: int = max(p.surface_preview_max_samples, min_samples)
	var sample_count: int = clampi(int(ceil(lookahead / target_spacing)), min_samples, max_samples)
	var spacing: float = lookahead / float(sample_count)

	var successful_samples: int = 0
	var path_distance: float = 0.0
	var concave_turn_deg: float = 0.0
	var reverse_turn_deg: float = 0.0
	var max_step_deg: float = 0.0
	var min_curve_radius: float = INF
	var curve_start_distance: float = INF
	var failure_reason: String = ""
	var collider_transitions: int = 0

	var current_point: Vector3 = contact_point
	var current_normal: Vector3 = n
	var current_center: Vector3 = initial_center
	var current_collider: Object = preferred_collider

	for _sample_index: int in range(sample_count):
		if (
			not capture_debug_path
			and curve_start_distance == INF
			and path_distance > radius * max(p.surface_preview_max_curve_start_radii, 0.0)
		):
			failure_reason = "curve_starts_too_late"
			break
		var predicted_center: Vector3 = current_center + tangent * spacing
		var hit: Dictionary = _find_surface_preview_hit(
			predicted_center,
			current_point,
			current_normal,
			tangent,
			spacing,
			radius,
			current_collider
		)
		if hit.is_empty():
			failure_reason = "curve_support_gap"
			break

		var next_point_value: Variant = hit.get("position", Vector3.ZERO)
		var next_point: Vector3 = next_point_value if next_point_value is Vector3 else Vector3.ZERO
		var next_normal_value: Variant = hit.get("normal", Vector3.ZERO)
		var next_normal: Vector3 = next_normal_value if next_normal_value is Vector3 else Vector3.ZERO
		next_normal = next_normal.normalized()
		if next_normal.length() < 0.001:
			failure_reason = "curve_invalid_normal"
			break
		var next_collider: Object = hit.get("collider")

		var next_center: Vector3 = next_point + next_normal * radius
		var center_step: float = current_center.distance_to(next_center)
		if center_step > spacing * max(p.surface_preview_max_gap_scale, 1.0):
			failure_reason = "curve_centerline_gap"
			break

		var normal_dot: float = clamp(current_normal.dot(next_normal), -1.0, 1.0)
		var normal_step_rad: float = acos(normal_dot)
		var normal_step_deg: float = rad_to_deg(normal_step_rad)
		max_step_deg = max(max_step_deg, normal_step_deg)
		if normal_step_deg > max(p.surface_preview_max_normal_step_deg, 0.0):
			failure_reason = "curve_sharp_corner"
			if capture_debug_path:
				points.append(next_point)
				normals.append(next_normal)
				centers.append(next_center)
			break

		var signed_component: float = -(next_normal - current_normal).dot(tangent)
		if signed_component > 0.0001:
			concave_turn_deg += normal_step_deg
			if curve_start_distance == INF:
				curve_start_distance = path_distance
			if normal_step_rad > 0.0001 and center_step > 0.0001:
				min_curve_radius = min(min_curve_radius, center_step / normal_step_rad)
		elif signed_component < -0.0001:
			reverse_turn_deg += normal_step_deg

		path_distance += center_step
		successful_samples += 1
		if capture_debug_path:
			points.append(next_point)
			normals.append(next_normal)
			centers.append(next_center)
		if current_collider != null and next_collider != null and current_collider != next_collider:
			collider_transitions += 1
		if next_collider != null:
			current_collider = next_collider

		var rotated_tangent: Vector3 = PlayerMath.basis_from_to(current_normal, next_normal) * tangent
		rotated_tangent = rotated_tangent.slide(next_normal)
		if rotated_tangent.length() < 0.001:
			rotated_tangent = (next_center - current_center).slide(next_normal)
		if rotated_tangent.length() < 0.001:
			failure_reason = "curve_invalid_tangent"
			break
		rotated_tangent = rotated_tangent.normalized()
		if rotated_tangent.dot(tangent) < 0.0:
			rotated_tangent = -rotated_tangent

		tangent = rotated_tangent
		current_point = next_point
		current_normal = next_normal
		current_center = next_center

	var coverage: float = float(successful_samples) / float(max(sample_count, 1))
	var curvature: float = 0.0
	if path_distance > 0.0001:
		curvature = deg_to_rad(concave_turn_deg - reverse_turn_deg) / path_distance
	var gravity_accel: Vector3 = p.get_gravity_acceleration_vector()
	var reaction_accel: float = tangential_speed * tangential_speed * curvature - gravity_accel.dot(n)
	var minimum_coverage: float = clamp(p.surface_preview_min_coverage, 0.0, 1.0)
	if coverage >= minimum_coverage and failure_reason in ["curve_support_gap", "curve_centerline_gap"]:
		failure_reason = ""
	var accepted: bool = failure_reason == ""

	if coverage < minimum_coverage:
		accepted = false
		if failure_reason == "":
			failure_reason = "curve_low_coverage"
	elif concave_turn_deg < max(p.surface_preview_min_concave_turn_deg, 0.0):
		accepted = false
		failure_reason = "curve_too_flat"
	elif reverse_turn_deg > max(p.surface_preview_max_reverse_turn_deg, 0.0):
		accepted = false
		failure_reason = "curve_wrong_direction"
	elif curve_start_distance == INF or curve_start_distance > radius * max(p.surface_preview_max_curve_start_radii, 0.0):
		accepted = false
		failure_reason = "curve_starts_too_late"
	elif min_curve_radius == INF or min_curve_radius < radius * max(p.surface_preview_min_curve_radius_scale, 0.0):
		accepted = false
		failure_reason = "curve_radius_too_tight"
	elif reaction_accel < p.surface_preview_min_reaction_accel:
		accepted = false
		failure_reason = "curve_insufficient_force"
	elif failure_reason != "":
		accepted = false

	if accepted:
		failure_reason = "curve_accepted"

	return {
		"accepted": accepted,
		"reason": failure_reason,
		"points": points,
		"normals": normals,
		"centers": centers,
		"radius": radius,
		"lookahead": lookahead,
		"coverage": coverage,
		"concave_turn_deg": concave_turn_deg,
		"reverse_turn_deg": reverse_turn_deg,
		"max_step_deg": max_step_deg,
		"min_curve_radius": 0.0 if min_curve_radius == INF else min_curve_radius,
		"curvature": curvature,
		"reaction_accel": reaction_accel,
		"initial_tangent": initial_tangent,
		"collider_transitions": collider_transitions
	}


func _find_surface_preview_hit(
	predicted_center: Vector3,
	previous_point: Vector3,
	normal: Vector3,
	tangent: Vector3,
	spacing: float,
	radius: float,
	preferred_collider: Object
) -> Dictionary:
	var p = _owner
	var world: World3D = p.get_world_3d()
	if world == null:
		return {}

	var inward: Vector3 = -normal.normalized()
	var binormal: Vector3 = tangent.cross(normal).normalized()
	var spread: float = clamp(p.surface_preview_probe_fan_spread, 0.0, 1.0)
	var directions: Array[Vector3] = [inward]
	if spread > 0.0:
		directions.append((inward + tangent * spread).normalized())
		directions.append((inward - tangent * spread).normalized())
		if binormal.length() > 0.001:
			directions.append((inward + binormal * spread).normalized())
			directions.append((inward - binormal * spread).normalized())

	var best_hit: Dictionary = {}
	var best_score: float = INF
	var ray_length: float = radius * max(p.surface_preview_probe_depth_radii, 1.05)
	var params: PhysicsRayQueryParameters3D = _preview_ray_query
	params.collision_mask = p.collision_mask
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var world_up: Vector3 = p._get_gravity_up()
	var origin_offsets: Array[Vector3] = [Vector3.ZERO]
	var seam_offset: float = radius * max(p.surface_preview_seam_probe_offset_radii, 0.0)
	var primary_normal_limit: float = deg_to_rad(
		max(p.surface_preview_max_normal_step_deg, 0.0)
	)
	if seam_offset > 0.0:
		origin_offsets.append(tangent * seam_offset)
		origin_offsets.append(-tangent * seam_offset)
		if binormal.length() > 0.001:
			origin_offsets.append(binormal * seam_offset)
			origin_offsets.append(-binormal * seam_offset)

	for origin_offset: Vector3 in origin_offsets:
		var ray_origin: Vector3 = predicted_center + origin_offset
		var ray_directions: Array[Vector3] = [inward]
		var center_origin: bool = origin_offset.length_squared() < 0.000001
		if center_origin:
			ray_directions = directions
		for direction: Vector3 in ray_directions:
			params.from = ray_origin
			params.to = ray_origin + direction * ray_length

			var hit: Dictionary = space.intersect_ray(params)
			if hit.is_empty():
				continue
			var candidate_collider: Object = hit.get("collider")
			if candidate_collider is Node and p._is_water_collider(candidate_collider as Node):
				continue
			if candidate_collider != null and candidate_collider.has_meta("rail_node"):
				continue
			var point_value: Variant = hit.get("position", Vector3.ZERO)
			var point: Vector3 = point_value if point_value is Vector3 else Vector3.ZERO
			var candidate_normal_value: Variant = hit.get("normal", Vector3.ZERO)
			var candidate_normal: Vector3 = candidate_normal_value if candidate_normal_value is Vector3 else Vector3.ZERO
			candidate_normal = candidate_normal.normalized()
			if candidate_normal.length() < 0.001:
				continue
			if p._is_surface_alignment_rejected(
				candidate_collider,
				candidate_normal,
				world_up,
				int(hit.get("shape", -1))
			):
				continue

			var offset: Vector3 = point - previous_point
			var forward_progress: float = offset.dot(tangent)
			if forward_progress < spacing * 0.05 or forward_progress > spacing * 3.0:
				continue

			var distance_error: float = abs(predicted_center.distance_to(point) - radius)
			var normal_angle: float = acos(clamp(normal.dot(candidate_normal), -1.0, 1.0))
			var lateral_error: float = abs(offset.dot(binormal)) if binormal.length() > 0.001 else 0.0
			var score: float = (
				distance_error
				+ normal_angle * radius * 0.25
				+ lateral_error * 0.5
				+ origin_offset.length() * 0.1
			)
			if preferred_collider != null and candidate_collider == preferred_collider:
				score -= radius * 0.02
			var primary_probe: bool = center_origin and direction.dot(inward) >= 0.9999
			var primary_collider_valid: bool = (
				preferred_collider == null
				or candidate_collider == preferred_collider
			)
			if (
				primary_probe
				and primary_collider_valid
				and distance_error <= radius * 0.35
				and normal_angle <= primary_normal_limit
				and lateral_error <= radius * 0.35
			):
				return hit
			if score < best_score:
				best_score = score
				best_hit = hit

	return best_hit


func _get_surface_preview_world_radius() -> float:
	var p = _owner
	var player_scale: Vector3 = p.global_transform.basis.get_scale().abs()
	var player_max_scale: float = max(player_scale.x, max(player_scale.y, player_scale.z))
	if p.surface_preview_radius_override > 0.0:
		p._surface_preview_world_radius = max(p.surface_preview_radius_override * player_max_scale, 0.05)
		return p._surface_preview_world_radius
	var main_radius: float = p.get_main_collision_world_radius()
	if main_radius > 0.0:
		p._surface_preview_world_radius = main_radius
		return main_radius

	for child: Node in p.get_children():
		if not (child is CollisionShape3D):
			continue
		var collision_shape: CollisionShape3D = child as CollisionShape3D
		if collision_shape.disabled or collision_shape.shape == null:
			continue
		var shape_scale: Vector3 = collision_shape.global_transform.basis.get_scale().abs()
		var max_shape_scale: float = max(shape_scale.x, max(shape_scale.y, shape_scale.z))
		var shape_radius: float = 0.0
		if collision_shape.shape is SphereShape3D:
			shape_radius = (collision_shape.shape as SphereShape3D).radius * max_shape_scale
		elif collision_shape.shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
			shape_radius = max(capsule.radius, capsule.height * 0.5) * max_shape_scale
		elif collision_shape.shape is CylinderShape3D:
			var cylinder: CylinderShape3D = collision_shape.shape as CylinderShape3D
			shape_radius = max(cylinder.radius, cylinder.height * 0.5) * max_shape_scale
		elif collision_shape.shape is BoxShape3D:
			shape_radius = (collision_shape.shape as BoxShape3D).size.length() * 0.5 * max_shape_scale
		if shape_radius > 0.0:
			p._surface_preview_world_radius = max(shape_radius, 0.05)
			return p._surface_preview_world_radius

	p._surface_preview_world_radius = max(p.collision_ground_distance * player_max_scale, 0.05)
	return p._surface_preview_world_radius


func _get_surface_support_grace_time(tangential_speed: float) -> float:
	var p = _owner
	var radius: float = p._surface_preview_world_radius
	if radius <= 0.0:
		radius = _get_surface_preview_world_radius()
	var speed_floor: float = max(p.radial_landing_min_speed, 0.1)
	var speed: float = max(tangential_speed, speed_floor)
	var time_grace: float = max(p.surface_preview_retention_grace_time, 0.0)
	var grace_radii: float = max(p.surface_preview_retention_grace_radii, 0.0)
	if grace_radii <= 0.0:
		return time_grace
	var distance_grace: float = radius * grace_radii / speed
	if time_grace <= 0.0:
		return distance_grace
	return min(time_grace, distance_grace)


func _store_surface_preview_debug(preview: Dictionary) -> void:
	var p = _owner
	p._dbg_surface_preview_points.clear()
	p._dbg_surface_preview_normals.clear()
	p._dbg_surface_preview_centers.clear()
	var point_values: Variant = preview.get("points", [])
	if point_values is Array:
		for point_value: Variant in point_values:
			if point_value is Vector3:
				p._dbg_surface_preview_points.append(point_value)
	var normal_values: Variant = preview.get("normals", [])
	if normal_values is Array:
		for normal_value: Variant in normal_values:
			if normal_value is Vector3:
				p._dbg_surface_preview_normals.append(normal_value)
	var center_values: Variant = preview.get("centers", [])
	if center_values is Array:
		for center_value: Variant in center_values:
			if center_value is Vector3:
				p._dbg_surface_preview_centers.append(center_value)
	p._dbg_surface_preview_accepted = bool(preview.get("accepted", false))
	p._dbg_surface_preview_radius = float(preview.get("radius", 0.0))
	p._dbg_surface_preview_lookahead = float(preview.get("lookahead", 0.0))
	p._dbg_surface_preview_coverage = float(preview.get("coverage", 0.0))
	p._dbg_surface_preview_total_turn_deg = float(preview.get("concave_turn_deg", 0.0))
	p._dbg_surface_preview_reverse_turn_deg = float(preview.get("reverse_turn_deg", 0.0))
	p._dbg_surface_preview_max_step_deg = float(preview.get("max_step_deg", 0.0))
	p._dbg_surface_preview_min_radius = float(preview.get("min_curve_radius", 0.0))
	p._dbg_surface_preview_curvature = float(preview.get("curvature", 0.0))
	p._dbg_surface_preview_reaction_accel = float(preview.get("reaction_accel", 0.0))
	p._dbg_surface_preview_collider_transitions = int(preview.get("collider_transitions", 0))
	var tangent_value: Variant = preview.get("initial_tangent", Vector3.ZERO)
	if tangent_value is Vector3:
		p._dbg_surface_preview_tangent = tangent_value
	else:
		p._dbg_surface_preview_tangent = Vector3.ZERO
	p._dbg_surface_preview_timer = max(p.surface_preview_debug_duration, 0.0)


func _can_attach_from_collision_legacy(v_before: Vector3, normal: Vector3, world_up: Vector3) -> bool:
	var p = _owner
	p._dbg_radial_result = "not_radial"
	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return false
	if _is_low_speed_detach_reattach_blocked(n, world_up):
		return false

	var v: Vector3 = v_before
	var speed: float = v.length()
	if speed < 0.0001:
		return false

	var in_spring_state: bool = p._is_spring_radial_landing_active()

	# Angle vs gravity-up for broad classification.
	var dot_up: float = clamp(n.dot(world_up), -1.0, 1.0)
	var surf_angle_deg: float = rad_to_deg(acos(dot_up))
	# 0°   = floor
	# 90°  = wall
	# 180° = ceiling

	# ------------------------------------------------------------------
	# VERTICAL FORBID BAND
	#   Normally: don't attach to a narrow band near 90° (pure walls).
	#   BUT: while in spring state, we *allow* this so springs can grab
	#   vertical/near-vertical and ceiling-like surfaces.
	# ------------------------------------------------------------------
	if not in_spring_state:
		if abs(surf_angle_deg - 90.0) <= p.adhesion_vertical_forbid_half_width_deg:
			return false

	# --------------------------------
	# Ceiling landing special-case (disabled)
	# --------------------------------
	# Spring state bypasses ceiling blocking so radial landing can proceed.
	#if surf_angle_deg >= 135.0 and not in_spring_state:
		# "Normal" (non-spring) ceiling rules; optional upward speed requirement:
	#	if not adhesion_enabled:
	#		return false

	#	var world_up_speed := v.dot(world_up)
	#	if world_up_speed <= 0.0:
	#		return false

	#	return true

	# --------------------------------
	# Low-speed “static” floor landing
	# --------------------------------
	if speed < 0.05:
		var min_floor_dot_static: float = cos(deg_to_rad(p.landing_floor_max_angle_deg))
		return dot_up >= min_floor_dot_static

	# --------------------------------
	# Floor and slope landing use gravity-up.
	# --------------------------------
	var min_floor_dot: float = cos(deg_to_rad(p.landing_floor_max_angle_deg))
	var down_speed: float = v.dot(-world_up)

	if dot_up >= min_floor_dot and down_speed > 0.0:
		# Normal floor / gentle slope landing.
		return true

	# From here on, only radial landing on non-floor surfaces is allowed.
	if not p.adhesion_enabled and not in_spring_state:
		return false
	# While in spring, *force* adhesion enabled for the purposes of
	# radial grabs so springs can grab walls / ceilings:
	# (we don't early-return if adhesion_enabled is false.)

	# --------------------------------
	# Radial landing on non-floor surfaces
	# --------------------------------
	if speed < p.radial_landing_min_speed:
		return false

	var metrics: Dictionary = PlayerMath.compute_radial_landing_metrics(v, n)
	var radial_angle: float = metrics.angle
	var into_speed: float = metrics.into_speed
	var tangential_speed: float = metrics.tangent_speed
	p._dbg_radial_result = "candidate"

	# Debug – just for HUD, not for gating.
	p._dbg_radial_angle = radial_angle
	p._dbg_radial_into_speed = into_speed
	p._dbg_radial_tangent_speed = tangential_speed
	p._dbg_radial_hit_timer = 0.25

	# 1) Must actually be moving into the surface.
	if into_speed <= 0.0:
		p._dbg_radial_result = "not_into_surface"
		return false

	var approach_angle_deg: float = 90.0 - radial_angle
	var min_approach_angle_deg: float = clamp(p.radial_landing_min_angle_deg, 0.0, 90.0)
	if approach_angle_deg < min_approach_angle_deg:
		p._dbg_radial_result = "head_on"
		return false

	# 2) Need enough tangential speed.
	if tangential_speed < p.radial_landing_min_speed:
		p._dbg_radial_result = "low_tangent_speed"
		return false

	# Floor → wall exception (base rule).
	# Spring state bypasses this check.
	if not in_spring_state:
		if not _passes_floor_wall_exception(n, world_up):
			p._dbg_radial_result = "floor_to_wall_block"
			return false

	p._dbg_radial_result = "accepted"
	return true


func _preserve_rejected_collision_slide(
	incoming_velocity: Vector3,
	normal: Vector3,
	world_up: Vector3
) -> void:
	var p = _owner
	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return
	if incoming_velocity.dot(n) >= 0.0:
		return
	if _get_surface_angle_deg(n, world_up) <= p.floor_like_max_angle_deg:
		return

	var incoming_tangent: Vector3 = incoming_velocity.slide(n)
	var incoming_tangent_speed: float = incoming_tangent.length()
	if incoming_tangent_speed < 0.01:
		return

	var current_tangent: Vector3 = p.velocity.slide(n)
	var dead_stop_threshold: float = max(incoming_tangent_speed * 0.1, 0.1)
	if current_tangent.length() > dead_stop_threshold:
		return

	var outward_speed: float = max(p.velocity.dot(n), 0.0)
	p.velocity = incoming_tangent + n * outward_speed
	p._dbg_radial_result = "rejected_slide"


func _surface_preserves_player_momentum(collider: Object, shape_index: int) -> bool:
	var p = _owner
	var metadata_value: Variant = p._get_surface_metadata_value(
		collider,
		SURFACE_METADATA.PRESERVE_PLAYER_MOMENTUM,
		shape_index
	)
	return metadata_value is bool and bool(metadata_value)


func _preserve_boundary_slide_momentum(
	incoming_velocity: Vector3,
	normal: Vector3,
	world_up: Vector3
) -> void:
	var p = _owner
	if p._enemy_bounce_cooldown_timer > 0.0:
		return
	var n: Vector3 = normal.normalized()
	if n.length() < 0.001 or incoming_velocity.dot(n) >= 0.0:
		return
	var incoming_speed: float = incoming_velocity.length()
	if incoming_speed < 0.01:
		return
	var tangent: Vector3 = incoming_velocity.slide(n)
	if tangent.length() < 0.001:
		tangent = p.velocity.slide(n)
	if tangent.length() < 0.001:
		tangent = (-p.global_basis.z).slide(n)
	if tangent.length() < 0.001:
		var up: Vector3 = world_up.normalized()
		if up.length() < 0.001:
			up = p._get_gravity_up()
		tangent = up.cross(n)
	if tangent.length() < 0.001:
		tangent = Vector3.RIGHT.slide(n)
	if tangent.length() < 0.001:
		return
	var current_outward_speed: float = max(p.velocity.dot(n), 0.0)
	var tangent_speed: float = sqrt(max(incoming_speed * incoming_speed - current_outward_speed * current_outward_speed, 0.0))
	p.velocity = tangent.normalized() * tangent_speed + n * current_outward_speed
	p._dbg_radial_result = "momentum_boundary_slide"


func _get_surface_angle_deg(normal: Vector3, world_up: Vector3) -> float:
	var p = _owner
	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return 0.0
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()
	return rad_to_deg(acos(clamp(n.dot(up), -1.0, 1.0)))


func _start_low_speed_detach_reattach_block(surface_angle_deg: float) -> void:
	var p = _owner
	var block_time: float = max(p.low_speed_detach_reattach_block_time, 0.0)
	if block_time <= 0.0:
		return
	p._low_speed_detach_block_angle_deg = clamp(surface_angle_deg, 0.0, 180.0)
	p._low_speed_detach_reattach_block_timer = max(p._low_speed_detach_reattach_block_timer, block_time)


func _is_low_speed_detach_reattach_blocked(normal: Vector3, world_up: Vector3) -> bool:
	var p = _owner
	if p._low_speed_detach_reattach_block_timer <= 0.0:
		return false
	var candidate_angle: float = _get_surface_angle_deg(normal, world_up)
	var tolerance: float = clamp(p.low_speed_detach_reattach_block_angle_tolerance_deg, 0.0, 180.0)
	return abs(candidate_angle - p._low_speed_detach_block_angle_deg) <= tolerance


func _passes_floor_wall_exception(new_normal: Vector3, world_up: Vector3) -> bool:
	var p = _owner
	var n_new: Vector3 = new_normal.normalized()
	if n_new.length() < 0.001:
		return true

	# Springs may ignore this rule and grab anything.
	if p._is_spring_radial_landing_active():
		return true

	var dot_up: float = clamp(n_new.dot(world_up), -1.0, 1.0)
	var new_angle_deg: float = rad_to_deg(acos(dot_up))

	if new_angle_deg < p.wall_block_floor_like_angle_deg:
		return true

	var came_from_floor_like: bool = (
		p._detached_from_floor_like
		or p._last_detach_angle_deg <= p.wall_block_floor_like_angle_deg
	)
	if not came_from_floor_like:
		return p._airborne_time <= p.nonfloor_to_wall_grace_time

	var forbidden_wall_min: float = clamp(
		max(p.wall_like_min_angle_deg, p.floor_to_steep_forbid_min_angle_deg),
		0.0,
		90.0
	)
	var forbidden_wall_max: float = clamp(
		p.wall_like_max_angle_deg,
		forbidden_wall_min,
		90.0
	)
	return new_angle_deg < forbidden_wall_min or new_angle_deg > forbidden_wall_max


func _is_plain_rigid_body(node) -> bool:
	var p = _owner
	return (
		node != null
		and is_instance_valid(node)
		and node is RigidBody3D
		and not (node as RigidBody3D).has_method("get_platform_velocity")
	)


func _ground_follow_probe(delta: float) -> void:
	var p = _owner
	if p._follow_collider_last != null and is_instance_valid(p._follow_collider_last):
		p._follow_collider_prev = p._follow_collider_last
		p._follow_collider_shape_prev = p._follow_collider_shape_last
	else:
		p._follow_collider_prev = null
		p._follow_collider_shape_prev = -1
	p._follow_hit = false
	p._follow_ray_origin = Vector3.ZERO
	p._follow_ray_target = Vector3.ZERO
	p._follow_collider_last = null
	p._follow_collider_shape_last = -1

	if not p.attached:
		_clear_collision_follow_candidate()
		return
	if p.ground_ray == null:
		if _collision_follow_has_surface_metadata():
			_apply_collision_follow_candidate()
		_clear_collision_follow_candidate()
		return

	var world_up: Vector3 = p._get_gravity_up()
	var origin_center: Vector3 = p.global_transform.origin

	var up_for_ray: Vector3 = p.surface_normal.normalized()
	if up_for_ray.length() < 0.001:
		up_for_ray = world_up

	# NEW:
	# Start the ray at the character center (not raised upward),
	# and cast FULL ground_ray_length downward along surface normal.
	var origin_follow: Vector3 = origin_center
	var target_follow: Vector3 = origin_center - up_for_ray * p.ground_ray_length

	p.ground_ray.global_position = origin_follow
	p.ground_ray.target_position = p.ground_ray.to_local(target_follow)
	p.ground_ray.force_raycast_update()

	p._follow_ray_origin = origin_follow
	p._follow_ray_target = target_follow
	var ray_follow_rejected: bool = false
	var collision_follow_has_metadata: bool = _collision_follow_has_surface_metadata()
	if (
		collision_follow_has_metadata
		and _collision_follow_is_excluded_by_ray(p.ground_ray)
	):
		_apply_collision_follow_candidate()
		_clear_collision_follow_candidate()
		return

	if p.ground_ray.is_colliding():
		p._follow_hit = true
		p._follow_point = p.ground_ray.get_collision_point()
		p._follow_normal = p.ground_ray.get_collision_normal()
		var hit_collider = p.ground_ray.get_collider()
		var hit_shape_index: int = p.ground_ray.get_collider_shape()
		if p._is_water_collider(hit_collider) and not p._running_on_water_surface and not p._can_start_water_surface_running(p._follow_normal):
			var floor_hit: Dictionary = _get_ground_ray_hit_ignoring_water_surface()
			if not floor_hit.is_empty():
				p._follow_point = floor_hit.position
				p._follow_normal = floor_hit.normal
				hit_collider = floor_hit.collider
				hit_shape_index = int(floor_hit.get("shape", -1))
		p._process_surface_contact_behavior(hit_collider, hit_shape_index)
		if p._is_dead:
			p._follow_hit = false
			_clear_collision_follow_candidate()
			return
		if p._is_surface_alignment_rejected(
			hit_collider,
			p._follow_normal,
			world_up,
			hit_shape_index
		):
			p._follow_hit = false
			p._follow_point = Vector3.ZERO
			p._follow_normal = Vector3.ZERO
			p._follow_collider_last = null
			ray_follow_rejected = true
		if hit_collider is Node3D:
			if not ray_follow_rejected:
				p._follow_collider_last = hit_collider
				p._follow_collider_shape_last = hit_shape_index

	if not p._follow_hit:
		var used_collision_follow: bool = (
			collision_follow_has_metadata
			and _apply_collision_follow_candidate()
		)
		if not used_collision_follow and not ray_follow_rejected:
			var used_forced_follow: bool = _try_forced_surface_follow(delta)
			if not used_forced_follow:
				_try_surface_follow_seam_bridge(delta)
	_clear_collision_follow_candidate()


func _try_forced_surface_follow(delta: float) -> bool:
	var p = _owner
	if not p._surface_launch_adhesion_active() or not p.attached:
		return false
	var world: World3D = p.get_world_3d()
	if world == null:
		return false

	var normal: Vector3 = p.surface_normal.normalized()
	if normal.length() < 0.001:
		return false
	var tangent: Vector3 = p.velocity.slide(normal)
	if tangent.length() < 0.001:
		tangent = p._automation_tangent_dir.slide(normal)
	if tangent.length() < 0.001:
		return false
	tangent = tangent.normalized()

	var radius: float = p._surface_preview_world_radius
	if radius <= 0.0:
		radius = _get_surface_preview_world_radius()
	var travel_distance: float = p.velocity.length() * max(delta, 0.0)
	var ray_length: float = max(p.ground_ray_length, radius * 2.5 + travel_distance)
	var center: Vector3 = p.global_position
	var inward: Vector3 = -normal
	var binormal: Vector3 = tangent.cross(normal).normalized()
	var best_hit: Dictionary = {}
	var best_score: float = INF
	var exclusions: Array[RID] = [p.get_rid()]
	var fan_steps: int = 8
	var fan_axes: Array[Vector3] = [tangent]
	if binormal.length() > 0.001:
		fan_axes.append(binormal)

	for fan_axis: Vector3 in fan_axes:
		for step: int in range(-fan_steps, fan_steps + 1):
			var angle: float = deg_to_rad(90.0 * float(step) / float(fan_steps))
			var direction: Vector3 = (inward * cos(angle) + fan_axis * sin(angle)).normalized()
			var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				center,
				center + direction * ray_length
			)
			params.collision_mask = p.collision_mask
			params.collide_with_areas = false
			params.collide_with_bodies = true
			params.exclude = exclusions
			params.hit_back_faces = false
			params.hit_from_inside = false
			var hit: Dictionary = world.direct_space_state.intersect_ray(params)
			if hit.is_empty():
				continue
			var collider: Object = hit.get("collider")
			if collider is Node and p._is_water_collider(collider as Node):
				continue
			if collider != null and collider.has_meta("rail_node"):
				continue
			var hit_normal_value: Variant = hit.get("normal", Vector3.ZERO)
			var hit_normal: Vector3 = hit_normal_value if hit_normal_value is Vector3 else Vector3.ZERO
			hit_normal = hit_normal.normalized()
			if hit_normal.length() < 0.001:
				continue
			var shape_index: int = int(hit.get("shape", -1))
			if p._is_surface_alignment_rejected(collider, hit_normal, p._get_gravity_up(), shape_index):
				continue
			if not _can_stay_attached(hit_normal, p._get_gravity_up(), collider, shape_index):
				continue
			var hit_point_value: Variant = hit.get("position", Vector3.ZERO)
			var hit_point: Vector3 = hit_point_value if hit_point_value is Vector3 else Vector3.ZERO
			var recovered_center: Vector3 = hit_point + hit_normal * p.collision_ground_distance
			var center_error: float = recovered_center.distance_to(center)
			var turn_angle: float = acos(clamp(normal.dot(hit_normal), -1.0, 1.0))
			var score: float = center_error + turn_angle * radius * 0.05
			if collider == p._follow_collider_prev:
				score -= radius * 0.05
			if score < best_score:
				best_score = score
				best_hit = hit

	if best_hit.is_empty():
		return false
	var best_point_value: Variant = best_hit.get("position", Vector3.ZERO)
	var best_normal_value: Variant = best_hit.get("normal", Vector3.ZERO)
	p._follow_point = best_point_value if best_point_value is Vector3 else Vector3.ZERO
	p._follow_normal = best_normal_value if best_normal_value is Vector3 else Vector3.ZERO
	p._follow_normal = p._follow_normal.normalized()
	var best_collider: Object = best_hit.get("collider")
	var best_shape_index: int = int(best_hit.get("shape", -1))
	p._process_surface_contact_behavior(best_collider, best_shape_index)
	if p._is_dead:
		return false
	if best_collider is Node3D:
		p._follow_collider_last = best_collider as Node3D
		p._follow_collider_shape_last = best_shape_index
	p._follow_hit = p._follow_normal.length() > 0.001
	return p._follow_hit


func _try_surface_follow_seam_bridge(delta: float) -> bool:
	var p = _owner
	if not p.surface_preview_enabled or not p.surface_preview_retention_enabled:
		return false

	var radius: float = p._surface_preview_world_radius
	if radius <= 0.0:
		radius = _get_surface_preview_world_radius()
	var normal: Vector3 = p.surface_normal.normalized()
	if normal.length() < 0.001:
		return false
	var world_up: Vector3 = p._get_gravity_up()
	var tangent_velocity: Vector3 = p.velocity.slide(normal)
	var tangent_speed: float = tangent_velocity.length()
	if tangent_speed < 0.001:
		return false
	var tangent: Vector3 = tangent_velocity / tangent_speed

	var max_probe_distance: float = radius * max(p.surface_preview_seam_follow_distance_radii, 0.0)
	if max_probe_distance <= 0.0:
		return false
	var travel_distance: float = tangent_speed * max(delta, 0.0)
	max_probe_distance = min(max_probe_distance, max(travel_distance, radius * 0.1))
	var probe_count: int = max(p.surface_preview_seam_follow_probe_count, 1)
	var center_tolerance: float = radius * max(p.surface_preview_seam_center_tolerance_radii, 0.0)
	var previous_collider: Object = p._follow_collider_prev

	for probe_index: int in range(1, probe_count + 1):
		var probe_distance: float = max_probe_distance * float(probe_index) / float(probe_count)
		var predicted_center: Vector3 = p.global_position + tangent * probe_distance
		var hit: Dictionary = _find_surface_preview_hit(
			predicted_center,
			p.surface_point,
			normal,
			tangent,
			probe_distance,
			radius,
			previous_collider
		)
		if hit.is_empty():
			continue

		var point_value: Variant = hit.get("position", Vector3.ZERO)
		var point: Vector3 = point_value if point_value is Vector3 else Vector3.ZERO
		var next_normal_value: Variant = hit.get("normal", Vector3.ZERO)
		var next_normal: Vector3 = next_normal_value if next_normal_value is Vector3 else Vector3.ZERO
		next_normal = next_normal.normalized()
		if next_normal.length() < 0.001:
			continue
		var normal_angle_deg: float = rad_to_deg(acos(clamp(normal.dot(next_normal), -1.0, 1.0)))
		if normal_angle_deg > max(p.surface_preview_max_normal_step_deg, 0.0):
			continue
		var recovered_center: Vector3 = point + next_normal * radius
		if recovered_center.distance_to(predicted_center) > center_tolerance:
			continue
		var candidate_collider: Object = hit.get("collider")
		var candidate_shape_index: int = int(hit.get("shape", -1))
		if not _can_stay_attached(
			next_normal,
			world_up,
			candidate_collider,
			candidate_shape_index
		):
			continue

		p._follow_hit = true
		p._follow_point = point
		p._follow_normal = next_normal
		if candidate_collider is Node3D:
			p._follow_collider_last = candidate_collider as Node3D
			p._follow_collider_shape_last = candidate_shape_index
		p._dbg_surface_seam_from = p.surface_point
		p._dbg_surface_seam_to = point
		p._dbg_surface_seam_normal = next_normal
		p._dbg_surface_seam_timer = max(p.surface_preview_debug_duration, 0.0)
		return true

	return false


func _smooth_surface_normal(prev: Vector3, raw: Vector3, delta: float) -> Vector3:
	var p = _owner
	var raw_normal: Vector3 = raw.normalized()
	if raw_normal.length() < 0.001:
		return prev

	if prev.length() < 0.001:
		return raw_normal

	var previous_normal: Vector3 = prev.normalized()
	var dot_pr: float = clamp(previous_normal.dot(raw_normal), -1.0, 1.0)
	var angle_rad: float = acos(dot_pr)

	if angle_rad < 0.0001:
		return raw_normal

	var max_step_rad: float = deg_to_rad(p.normal_smooth_max_angle_deg_per_sec) * delta
	var t: float = min(1.0, max_step_rad / angle_rad)

	return previous_normal.slerp(raw_normal, t).normalized()


func _update_attachment_state_after_move(delta: float) -> void:
	var p = _owner
	var world_up: Vector3 = p._get_gravity_up()
	p._prev_attached = p.attached
	p._prev_surface_normal = p.surface_normal
	p._collision_support_normal = p.surface_normal if p.attached else Vector3.ZERO

	if not p.attached:
		return

	if p._follow_hit:
		var prev_n: Vector3 = p._prev_surface_normal.normalized()
		if prev_n.length() < 0.001:
			prev_n = world_up

		var raw_n: Vector3 = p._follow_normal.normalized()
		if raw_n.length() < 0.001:
			raw_n = world_up

		# Corner angle between last frame's normal and this frame's follow normal.
		var corner_dot: float = clamp(prev_n.dot(raw_n), -1.0, 1.0)
		var corner_angle_deg: float = rad_to_deg(acos(corner_dot))

		# Outer corner detection: ignore follow hits that form outer corners relative to player's local alignment.
		if p.outer_corner_detection_enabled and not p._surface_launch_adhesion_active():
			var v_dir: Vector3 = p.velocity.normalized()
			if v_dir.length() > 0.001:
				var vel_dot_n: float = clamp(v_dir.dot(raw_n), -1.0, 1.0)
				var vel_angle_deg: float = rad_to_deg(acos(vel_dot_n))
				if vel_angle_deg >= p.outer_corner_min_angle_deg:
					p._follow_hit = false
					p._follow_point = Vector3.ZERO
					p._follow_normal = Vector3.ZERO

		if not p._follow_hit:
			if not p._surface_launch_adhesion_active() and not p._radial_attach_this_frame:
				_start_detach(p.surface_normal, world_up)
			if p.attached:
				p._record_attach_state(p.surface_normal, world_up)
			return

		_update_surface_support_observation(
			prev_n,
			raw_n,
			p.surface_point,
			p._follow_point
		)
		var can_attach: bool = _can_stay_attached(
			raw_n,
			world_up,
			p._follow_collider_last,
			p._follow_collider_shape_last
		)
		var follow_is_water: bool = p._is_water_collider(p._follow_collider_last)

		if not can_attach:
			if p._radial_attach_this_frame:
				p._pending_low_speed_detach_block = false
				p._record_attach_state(p.surface_normal, world_up)
				return

			var speed: float = p.velocity.length()
			var can_forgive_corner: bool = (
				corner_angle_deg > 0.1
				and corner_angle_deg <= p.corner_max_angle_deg
				and speed >= p.corner_min_speed
			)
			if p.surface_preview_enabled and p.surface_preview_retention_enabled:
				can_forgive_corner = can_forgive_corner and p._surface_support_timer > 0.0
			if can_forgive_corner:
				# Treat this as a continuous corner on a loop / slope.
				var t_smooth: float = p.corner_smoothing_strength
				var blended_n: Vector3 = (prev_n * (1.0 - t_smooth) + raw_n * t_smooth).normalized()

				p.surface_normal = blended_n
				p.surface_point = p._follow_point
				p._collision_support_normal = raw_n

				# Update debug delta angle
				var dot_nd: float = clamp(prev_n.dot(blended_n), -1.0, 1.0)
				p._normal_delta_angle_deg = rad_to_deg(acos(dot_nd))
				p._record_attach_state(p.surface_normal, world_up)
				return
			else:
				# Too sharp a corner or too slow → detach normally.
				_start_detach(p.surface_normal, world_up)
				return

		if follow_is_water:
			if not p._running_on_water_surface:
				if p._can_start_water_surface_running(raw_n):
					p._start_water_surface_running(raw_n)
				else:
					p._drop_from_water_surface(raw_n)
					return
		elif p._running_on_water_surface:
			p._running_on_water_surface = false

		# Normal "happy path": allowed to stay attached.
		# Smooth a bit so small normal noise doesn’t jitter.
		var max_delta_deg: float = p.adhesion_max_step_angle_from_current_deg
		var max_delta_rad: float = deg_to_rad(max_delta_deg)

		var dot_n: float = clamp(prev_n.dot(raw_n), -1.0, 1.0)
		var angle_rad: float = acos(dot_n)

		var final_n: Vector3 = raw_n
		if (
			angle_rad > max_delta_rad
			and angle_rad > 0.0001
			and not p._surface_launch_adhesion_active()
		):
			var t_clamp: float = max_delta_rad / angle_rad
			final_n = prev_n.slerp(raw_n, t_clamp).normalized()
		
		# Before we store it, rotate velocity onto this new surface.
		# Skip for plain RigidBody3D: their rotation changes the contact normal
		# each frame, and preserving speed across those changes causes accumulation.
		if not _is_plain_rigid_body(p._follow_collider_last):
			if p._surface_launch_adhesion_active():
				_rotate_velocity_with_surface(prev_n, final_n)
			else:
				p._reproject_velocity_onto_new_surface(prev_n, final_n)

		p.surface_normal = final_n
		p.surface_point = p._follow_point
		p._collision_support_normal = raw_n

		var dot_nd2: float = clamp(prev_n.dot(final_n), -1.0, 1.0)
		p._normal_delta_angle_deg = rad_to_deg(acos(dot_nd2))
	else:
		if p._surface_launch_adhesion_active():
			# Forced adhesion keeps attachment when the follow ray misses.
			pass
		elif p._radial_attach_this_frame:
			pass
		else:
			_start_detach(p.surface_normal, world_up)

	if p.attached:
		p._record_attach_state(p.surface_normal, world_up)


func _rotate_velocity_with_surface(previous_normal: Vector3, next_normal: Vector3) -> void:
	var p = _owner
	var speed: float = p.velocity.length()
	var previous_up: Vector3 = previous_normal.normalized()
	var next_up: Vector3 = next_normal.normalized()
	if speed < 0.001 or previous_up.length() < 0.001 or next_up.length() < 0.001:
		return
	var rotated_velocity: Vector3 = PlayerMath.basis_from_to(previous_up, next_up) * p.velocity
	rotated_velocity = rotated_velocity.slide(next_up)
	if rotated_velocity.length() < 0.001:
		return
	p.velocity = rotated_velocity.normalized() * speed


func _update_surface_support_observation(
	previous_normal: Vector3,
	current_normal: Vector3,
	previous_point: Vector3,
	current_point: Vector3
) -> void:
	var p = _owner
	if not p.surface_preview_enabled or not p.surface_preview_retention_enabled:
		return

	var prev_n: Vector3 = previous_normal.normalized()
	var curr_n: Vector3 = current_normal.normalized()
	if prev_n.length() < 0.001 or curr_n.length() < 0.001:
		return

	var radius: float = p._surface_preview_world_radius
	if radius <= 0.0:
		radius = _get_surface_preview_world_radius()
	var tangent_speed: float = p.velocity.slide(curr_n).length()
	var gravity_accel: Vector3 = p.get_gravity_acceleration_vector()
	p._surface_support_curvature = 0.0
	p._surface_support_reaction_accel = -gravity_accel.dot(curr_n)
	var previous_center: Vector3 = previous_point + prev_n * radius
	var current_center: Vector3 = current_point + curr_n * radius
	var center_delta: Vector3 = current_center - previous_center
	var center_distance: float = center_delta.length()
	if center_distance < 0.0001:
		_refresh_surface_support_grace(tangent_speed)
		return

	var travel_tangent: Vector3 = center_delta.slide(curr_n)
	if travel_tangent.length() < 0.001:
		travel_tangent = p.velocity.slide(curr_n)
	if travel_tangent.length() < 0.001:
		_refresh_surface_support_grace(tangent_speed)
		return
	travel_tangent = travel_tangent.normalized()

	var normal_angle_rad: float = acos(clamp(prev_n.dot(curr_n), -1.0, 1.0))
	var signed_component: float = -(curr_n - prev_n).dot(travel_tangent)
	var signed_curvature: float = 0.0
	if signed_component > 0.0001:
		signed_curvature = normal_angle_rad / center_distance
	elif signed_component < -0.0001:
		signed_curvature = -normal_angle_rad / center_distance

	var reaction_accel: float = tangent_speed * tangent_speed * signed_curvature - gravity_accel.dot(curr_n)
	p._surface_support_curvature = signed_curvature
	p._surface_support_reaction_accel = reaction_accel
	_refresh_surface_support_grace(tangent_speed)


func _refresh_surface_support_grace(tangential_speed: float) -> void:
	var p = _owner
	p._surface_support_timer = max(
		p._surface_support_timer,
		_get_surface_support_grace_time(tangential_speed)
	)


func _can_stay_attached(
	smoothed_normal: Vector3,
	world_up: Vector3,
	collider: Object = null,
	collider_shape_index: int = -1
) -> bool:
	var p = _owner
	p._pending_low_speed_detach_block = false
	if smoothed_normal.length() < 0.001:
		return false
	if p._is_surface_alignment_rejected(
		collider,
		smoothed_normal,
		world_up,
		collider_shape_index
	):
		return false
	if p._surface_prevents_detach(collider, collider_shape_index):
		return true
	if p._automation_force_surface_adhesion:
		# Automation spline override: keep adhesion even on steep/ceiling and outward-loop geometry.
		return true

	var n: Vector3 = smoothed_normal.normalized()
	var v: Vector3 = p.velocity
	var speed: float = v.length()

	var in_spring_state: bool = p._is_spring_radial_landing_active()
	if in_spring_state and p._spring_detached:
		return false

	# Angle vs gravity-up:
	#   0°   = floor
	#   90°  = wall / loop side
	#   180° = ceiling
	var dot_up: float = clamp(n.dot(world_up), -1.0, 1.0)
	var surf_angle_deg: float = rad_to_deg(acos(dot_up))

	p._dbg_surface_angle_deg = surf_angle_deg
	p._dbg_surface_is_floor_like = surf_angle_deg <= p.adhesion_floor_max_angle_deg

	# Hard limit – beyond this we never attach.
	if surf_angle_deg > clamp(p.adhesion_max_angle_deg, 0.0, 180.0) + 0.001:
		return false
	var adhesion_speed_start_angle: float = clamp(p.adhesion_detach_angle_start_deg, 0.0, 90.0)

	# Stationary floor-like surfaces can remain attached without a speed gate.
	if speed < 0.01 and surf_angle_deg < adhesion_speed_start_angle:
		p._dbg_current_adhesion_speed = 0.0
		p._dbg_required_adhesion_speed = 0.0
		return true

	# --- DECOMPOSE VELOCITY RELATIVE TO SURFACE ---
	var v_norm: float = v.dot(n)                     # (+ out from surface)
	var v_tangent: Vector3 = v - n * v_norm          # along the surface
	var v_tan_speed: float = v_tangent.length()

	# Don't cling if we are clearly leaving the surface *along its normal*.
	if v_norm > p.adhesion_max_outward_speed:
		return false

	# ------------------------------------------------------------
	# Floor-like surfaces stay attached without speed requirements.
	# ------------------------------------------------------------
	if surf_angle_deg < adhesion_speed_start_angle:
		p._dbg_current_adhesion_speed = v_tan_speed
		p._dbg_required_adhesion_speed = 0.0
		return true

	# ------------------------------------------------------------
	# ------------------------------------------------------------
	# ------------------------------------------------------------
	# REGION 2: Wall / side of loop 60°..detach_start -> speed required
	# ------------------------------------------------------------

	# Small dead-zone so we actually get a stable 90° value instead of
	var required_tan_speed: float = 0.0

	# Required adhesion speed rises through vertical and toward the max adhesion angle.
	if surf_angle_deg <= 90.0:
		# From 60° → 90°, ramp 0 → adhesion_speed_at_90
		var denom_low: float = max(90.0 - adhesion_speed_start_angle, 0.001)
		var t_low: float = 1.0 if adhesion_speed_start_angle >= 90.0 else clamp((surf_angle_deg - adhesion_speed_start_angle) / denom_low, 0.0, 1.0)
		required_tan_speed = lerp(0.0, p.adhesion_speed_at_90, t_low)
	else:
		# From 90° → detach_start, ramp adhesion_speed_at_90 → adhesion_speed_at_180
		var upper_start: float = 90.0
		var upper_end: float = max(p.adhesion_max_angle_deg, upper_start + 0.001)
		var denom_high: float = max(upper_end - upper_start, 0.001)
		var t_high: float = clamp((surf_angle_deg - upper_start) / denom_high, 0.0, 1.0)
		required_tan_speed = lerp(p.adhesion_speed_at_90, p.adhesion_speed_at_180, t_high)

	# --- Optional tangent-fraction rule: separate from required speed ---
	#
	# This no longer affects _dbg_required_adhesion_speed (so it won't
	# look like the requirement grows with SPD). It is just an extra
	# condition: "if almost all of your velocity is radial, let go".
	if p.adhesion_min_tangent_fraction > 0.0 and speed > 0.01:
		var tang_frac : float = v_tan_speed / max(speed, 0.001)
		var frac_eps: float = 0.02  # 2% slack
		if tang_frac + frac_eps < p.adhesion_min_tangent_fraction:
			# Optional: expose separate debug values for this.
			# _dbg_tangent_fraction = tang_frac
			# _dbg_tangent_fraction_required = adhesion_min_tangent_fraction
			return false

	p._dbg_current_adhesion_speed = v_tan_speed
	p._dbg_required_adhesion_speed = required_tan_speed

	if v_tan_speed < required_tan_speed:
		p._pending_low_speed_detach_block = true
		p._pending_low_speed_detach_block_angle_deg = surf_angle_deg
		return false

	return true


func _start_detach(detach_normal: Vector3, world_up: Vector3) -> void:
	var p = _owner
	if not p.attached:
		return

	var curr_up: Vector3 = _get_filtered_detach_normal(p.surface_normal, world_up)
	var det_n: Vector3 = _get_filtered_detach_normal(detach_normal, world_up)

	if curr_up.length() < 0.001:
		curr_up = world_up
	if det_n.length() < 0.001:
		det_n = curr_up

	var dot_local : float = clamp(curr_up.dot(det_n), -1.0, 1.0)
	var step_angle_deg: float = rad_to_deg(acos(dot_local))
	p._dbg_last_detach_step_angle = step_angle_deg

	if step_angle_deg > p.adhesion_max_step_angle_from_current_deg:
		det_n = curr_up

	if p._pending_low_speed_detach_block:
		_start_low_speed_detach_reattach_block(p._pending_low_speed_detach_block_angle_deg)
		p._pending_low_speed_detach_block = false

	p._record_detach_state(det_n, world_up, true, false)
	p._start_coyote_jump_window()
	
	p.attached = false
	p._surface_support_timer = 0.0
	p._surface_support_curvature = 0.0
	p._surface_support_reaction_accel = 0.0
	p._attachment_immunity = p.launch_immunity_time
	p._loop_forward_dir = Vector3.ZERO  # reset loop forward when we leave surface
	# Skip launch redirect for plain RigidBody3D surfaces. _follow_collider_prev
	# holds the last known collider since _follow_collider_last is cleared by the
	# probe before detach decisions are made.
	var detach_collider: Node = null
	if p._follow_collider_last != null and is_instance_valid(p._follow_collider_last):
		detach_collider = p._follow_collider_last
	elif p._follow_collider_prev != null and is_instance_valid(p._follow_collider_prev):
		detach_collider = p._follow_collider_prev
	if not _is_plain_rigid_body(detach_collider):
		_apply_launch_from_surface(det_n, world_up)


func _get_filtered_detach_normal(detach_normal: Vector3, world_up: Vector3) -> Vector3:
	var p = _owner
	var n: Vector3 = detach_normal.normalized()
	if n.length() < 0.001:
		return world_up
	if not p.detach_stable_normal_filter_enabled:
		p._dbg_last_detach_used_filtered = false
		return n
	if not p._stable_attach_normal_valid:
		p._dbg_last_detach_used_filtered = false
		return n

	var stable_n: Vector3 = p._stable_attach_normal.normalized()
	if stable_n.length() < 0.001:
		p._dbg_last_detach_used_filtered = false
		return n

	var step_angle_deg: float = rad_to_deg(acos(clamp(stable_n.dot(n), -1.0, 1.0)))
	var filter_angle: float = max(
		min(p.detach_stable_normal_filter_angle_deg, p.detach_ignore_last_moment_angle_deg),
		0.0
	)
	if step_angle_deg <= filter_angle:
		p._dbg_last_detach_used_filtered = false
		return n

	p._dbg_last_detach_used_filtered = true
	p._dbg_last_detach_step_angle = step_angle_deg
	return stable_n


func _apply_wall_slide_and_friction(
	normal: Vector3,
	physics_up: Vector3,
	world_up: Vector3,
	delta: float,
	reference_velocity: Vector3 = Vector3.ZERO
) -> void:
	var p = _owner
	# Disable wall friction while in spring alignment – let the launch play out cleanly.
	if p._spring_align_timer > 0.0:
		return

	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return

	# Surface angle relative to player-up.
	var player_up: Vector3 = physics_up.normalized()
	if player_up.length() < 0.001:
		player_up = world_up.normalized()
	if player_up.length() < 0.001:
		player_up = p._get_gravity_up()

	var dot_up_player: float = clamp(n.dot(player_up), -1.0, 1.0)
	var angle_vs_player_deg: float = rad_to_deg(acos(dot_up_player))

	var min_wall_angle: float = max(p.walkable_from_up_max_angle_deg, 0.0)
	var max_wall_angle: float = max(p.wall_from_up_max_angle_deg, min_wall_angle + 0.1)
	max_wall_angle = min(max_wall_angle, 180.0)

	if angle_vs_player_deg <= min_wall_angle:
		return
	if angle_vs_player_deg >= max_wall_angle:
		return

	var v: Vector3 = p.velocity
	var speed: float = v.length()
	var reference_v: Vector3 = reference_velocity
	if reference_v.length() < 0.01:
		reference_v = v
	if speed < 0.01 and reference_v.length() < 0.01:
		return

	var current_into: float = v.dot(n)
	var reference_into: float = reference_v.dot(n)
	if reference_into >= 0.0 and current_into >= 0.0:
		return

	var angle_velocity: Vector3 = reference_v
	if reference_into >= 0.0 and current_into < 0.0:
		angle_velocity = v
	if angle_velocity.length() < 0.01:
		return

	# 0° = straight into wall, 90° = pure side scrape
	var approach_dir: Vector3 = (-angle_velocity).normalized()
	var cos_ang: float = clamp(approach_dir.dot(n), -1.0, 1.0)
	var angle_deg: float = rad_to_deg(acos(cos_ang))

	var outward_normal: Vector3 = Vector3.ZERO
	if current_into > 0.0:
		outward_normal = n * current_into

	var tangential: Vector3 = v.slide(n)
	var wall_up: Vector3 = world_up.slide(n)
	if wall_up.length() < 0.001:
		wall_up = player_up.slide(n)
	if wall_up.length() < 0.001:
		p.velocity = outward_normal + tangential
		return
	wall_up = wall_up.normalized()

	var parallel_forgive_angle: float = clamp(p.wall_parallel_forgive_angle_deg, 0.0, 90.0)
	var parallel_start_angle: float = 90.0 - parallel_forgive_angle
	if angle_deg >= parallel_start_angle:
		p.velocity = outward_normal + tangential
		return

	var tangential_vert: Vector3 = wall_up * tangential.dot(wall_up)
	var tangential_side: Vector3 = tangential - tangential_vert

	var new_side: Vector3 = tangential_side

	var stop_angle: float = p.wall_stop_max_angle_deg
	var graze_angle: float = p.wall_graze_min_angle_deg
	if graze_angle <= stop_angle:
		graze_angle = stop_angle + 0.1

	if angle_deg <= stop_angle:
		# Head-on contact.
		var max_drop: float = p.wall_friction * delta
		new_side = new_side.move_toward(Vector3.ZERO, max_drop)
	elif angle_deg < graze_angle:
		# Blended contact.
		var t: float = (angle_deg - stop_angle) / (graze_angle - stop_angle)
		var fric: float = lerp(p.wall_friction, p.wall_friction * p.wall_graze_friction_scale, t)
		new_side = new_side.move_toward(Vector3.ZERO, fric * delta)
	else:
		# Graze contact.
		var fric_graze: float = p.wall_friction * p.wall_graze_friction_scale
		new_side = new_side.move_toward(Vector3.ZERO, fric_graze * delta)

	# Final velocity has no into-wall normal component.
	p.velocity = outward_normal + tangential_vert + new_side


func _apply_launch_from_surface(detach_normal: Vector3, world_up: Vector3) -> void:
	var p = _owner
	var v_current: Vector3 = p.velocity
	var speed_current: float = v_current.length()
	if p._dbg_dynbody:
		print("[DYN] LAUNCH_FROM_SURFACE spd=%.3f vel=%v det_n=%v" % [speed_current, v_current, detach_normal])
	if speed_current <= 0.01:
		return

	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var surf_up: Vector3 = detach_normal.normalized()
	if surf_up.length() < 0.001:
		surf_up = up

	# 0° = floor, 90° = wall, 180° = ceiling
	var surf_angle_deg: float = rad_to_deg(acos(clamp(surf_up.dot(up), -1.0, 1.0)))

	# Gravity-relative vertical component (positive = moving upward).
	var world_vert_before: float = v_current.dot(up)

	# ---------------------------------------------------------
	# NO-LAUNCH DETACH (IMPORTANT NEW RULE):
	# If we're too close to fully inverted, never do the upward arc.
	# This prevents the "ceiling pop" when detaching near 180°.
	# ---------------------------------------------------------
	var too_inverted: bool = surf_angle_deg >= p.launch_ceiling_cutoff_angle_deg

	# Also require a meaningful upward velocity; tiny +epsilon shouldn't trigger a launch.
	var not_really_going_up: bool = world_vert_before <= p.launch_min_world_vertical_speed

	if surf_angle_deg <= p.launch_min_world_angle_deg or too_inverted or not_really_going_up:
		# Keep tangential component, remove into-surface, preserve speed
		var normal_comp: Vector3 = surf_up * v_current.dot(surf_up)
		var tangent: Vector3 = v_current - normal_comp

		if tangent.length() > 0.001:
			p.velocity = tangent.normalized() * speed_current
		else:
			p.velocity = v_current
		return

	# ---------------------------------------------------------
	# TRUE RAMP/LOOP LAUNCH (steep but not near-ceiling)
	# ---------------------------------------------------------
	var forward_dir: Vector3 = p._model_forward
	if forward_dir.length() < 0.001:
		forward_dir = v_current
	forward_dir = forward_dir.normalized()

	# Project forward onto the surface plane
	var forward_on_surface: Vector3 = forward_dir - surf_up * forward_dir.dot(surf_up)
	var f_len: float = forward_on_surface.length()
	if f_len < 0.001:
		var tangent2: Vector3 = v_current - surf_up * v_current.dot(surf_up)
		if tangent2.length() < 0.001:
			tangent2 = Vector3.FORWARD
		forward_on_surface = tangent2.normalized()
	else:
		forward_on_surface /= f_len

	# Scale launch angle by how inverted we are (from launch_min → cutoff)
	var t : float = clamp(
		(surf_angle_deg - p.launch_min_world_angle_deg) / max(p.launch_ceiling_cutoff_angle_deg - p.launch_min_world_angle_deg, 0.001),
		0.0,
		1.0
	)

	var max_launch_angle_rad: float = deg_to_rad(60.0)
	var launch_angle: float = max_launch_angle_rad * t

	var launch_dir: Vector3 = (
		forward_on_surface * cos(launch_angle)
		+ up * sin(launch_angle)
	).normalized()

	var tangent_release: Vector3 = v_current - surf_up * v_current.dot(surf_up)
	if tangent_release.length() > 0.001:
		tangent_release = tangent_release.normalized()
	else:
		tangent_release = v_current.normalized()

	var fade_start: float = clamp(p.launch_ceiling_fade_start_angle_deg, p.launch_min_world_angle_deg, p.launch_ceiling_cutoff_angle_deg)
	var fade_range: float = max(p.launch_ceiling_cutoff_angle_deg - fade_start, 0.001)
	var ceiling_fade_t: float = clamp((surf_angle_deg - fade_start) / fade_range, 0.0, 1.0)
	var launch_weight: float = 1.0 - ceiling_fade_t
	var final_launch_dir: Vector3 = tangent_release.slerp(launch_dir, launch_weight)
	if final_launch_dir.length() < 0.001:
		final_launch_dir = tangent_release
	final_launch_dir = final_launch_dir.normalized()

	var launched_velocity: Vector3 = final_launch_dir * speed_current
	var max_added_vertical: float = max(p.launch_max_added_world_vertical_speed, 0.0)
	var launched_vertical: float = launched_velocity.dot(up)
	var max_vertical: float = world_vert_before + max_added_vertical
	if launched_vertical > max_vertical:
		launched_velocity -= up * (launched_vertical - max_vertical)
		if launched_velocity.length() > speed_current and launched_velocity.length() > 0.001:
			launched_velocity = launched_velocity.normalized() * speed_current

	p.velocity = launched_velocity

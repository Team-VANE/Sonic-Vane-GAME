extends RefCounted
class_name PlayerRespawnController

# Checkpoint activation, respawning, and unstuck recovery.
var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func _respawn() -> void:
	var p = _owner
	p._is_dead = false
	p._on_player_hurt()
	p.clear_gravity_state(&"respawn")
	# Default respawn: PlayerSpawn (preferred), otherwise initial spawn.
	var target_transform: Transform3D = p._initial_transform
	var resolved_respawn: Node3D = _resolve_respawn_point()
	var downwarp_hit: bool = false
	var downwarp_point: Vector3 = Vector3.ZERO
	var downwarp_normal: Vector3 = p._get_gravity_up()
	if resolved_respawn != null:
		target_transform = resolved_respawn.global_transform
		var downwarp_info: Dictionary = DownwarpUtil.apply_downwarp_from_node_with_hit(
			resolved_respawn,
			target_transform,
			[p]
		)
		if p._is_surface_alignment_rejected(
			downwarp_info.get("collider"),
			downwarp_info.get("normal", downwarp_normal),
			p._get_gravity_up(),
			int(downwarp_info.get("shape", -1))
		):
			downwarp_info.clear()
		if downwarp_info.has("xform") and downwarp_info["xform"] is Transform3D:
			target_transform = downwarp_info["xform"]
		if downwarp_info.has("hit"):
			downwarp_hit = bool(downwarp_info["hit"])
		if downwarp_info.has("point") and downwarp_info["point"] is Vector3:
			downwarp_point = downwarp_info["point"]
		if downwarp_info.has("normal") and downwarp_info["normal"] is Vector3:
			downwarp_normal = downwarp_info["normal"]
	_apply_respawn_transform(target_transform, false, downwarp_hit, downwarp_point, downwarp_normal)


func _respawn_to_checkpoint() -> void:
	var p = _owner
	p._is_dead = false
	p._on_player_hurt()
	p.clear_gravity_state(&"respawn")
	# Checkpoint respawn: last checkpoint, otherwise fallback to default respawn.
	var using_checkpoint: bool = p.checkpoint_enabled and p._checkpoint_active
	if using_checkpoint:
		_apply_respawn_transform(p._checkpoint_transform, true)
	else:
		_respawn()


func _apply_respawn_transform(
	target_transform: Transform3D,
	use_checkpoint_velocity: bool,
	force_grounded: bool = false,
	grounded_point: Vector3 = Vector3.ZERO,
	grounded_normal: Vector3 = Vector3.ZERO
) -> void:
	var p = _owner
	p.clear_air_trick_bank()
	p.cancel_homing_attack(false)
	p.cancel_vault_bar()
	p.clear_max_speed_overrides()
	p.refresh_traversal_actions()
	p.cancel_rail_grind()
	p.cancel_spline_spring()
	p._active_surface_behavior_areas.clear()
	p._surface_contact_behaviors.clear()
	p._follow_collider_last = null
	p._follow_collider_prev = null
	p._follow_collider_shape_last = -1
	p._follow_collider_shape_prev = -1
	p.global_transform = target_transform

	p._clear_enemy_hurt_boundary_exceptions()
	p.velocity = Vector3.ZERO
	var has_checkpoint_vel: bool = false
	if use_checkpoint_velocity and p._checkpoint_respawn_speed > 0.0 and p._checkpoint_respawn_dir.length() > 0.001:
		var d: Vector3 = p._checkpoint_respawn_dir.normalized()
		p.velocity = d * p._checkpoint_respawn_speed
		has_checkpoint_vel = true

	# Reset floor/adhesion state to avoid snapping back to stale surface normals.
	p._airborne_time = 0.0
	var respawn_up: Vector3 = p._get_gravity_up()
	p._physics_up_last = respawn_up
	p.up_direction = respawn_up
	p.surface_normal = respawn_up
	p.surface_point = p.global_position
	p._is_falling = false
	p._is_jumping = false
	p._jumped_from_ground = false
	p._falling_without_jump = false
	p._reset_directional_influence_lock()
	p._reset_stable_attach_normal()
	p._homing_post_attack_timer = 0.0
	p._combat_homing_lockout_timer = 0.0
	p._attack_sources = 0

	# Checkpoint respawns treat the player as attached only if they have a saved velocity/direction.
	p.attached = has_checkpoint_vel
	p._prev_attached = has_checkpoint_vel
	if p.attached:
		p._record_attach_state(p.surface_normal, respawn_up)

	p._reset_spindash_state()
	p._cancel_barrier_blast()
	p.rolling = false
	p._reset_enemy_targeting_spawn_grace()
	p._unlock_local_camera_constraints()
	_notify_camera_teleport()
	p._sync_buddy_after_leader_teleport()

	if force_grounded:
		p._apply_grounded_from_downwarp(grounded_point, grounded_normal)
	if p._hurt_action != null and p._hurt_action.has_method("clear_death_grounded_respawn_hold"):
		p._hurt_action.call("clear_death_grounded_respawn_hold")
	_restart_animation_state_machine_for_respawn()


func _restart_animation_state_machine_for_respawn() -> void:
	var p = _owner
	p._pending_anim_command = &""
	p._pending_anim_crossfade = -1.0
	var start_node: StringName = _get_respawn_animation_start_node()
	if p.anim_state != null and p.anim_state.has_method("start"):
		p.anim_state.start(start_node)
	elif p.anim_state != null:
		p.anim_state.travel(start_node)
	var ground_start_node: StringName = _get_respawn_ground_animation_start_node()
	if p.ground_state != null and p.ground_state.has_method("start"):
		p.ground_state.start(ground_start_node)
	elif p.ground_state != null:
		p.ground_state.travel(ground_start_node)


func _get_respawn_animation_start_node() -> StringName:
	var p = _owner
	if p.attached:
		return &"GROUND_MACHINE"
	var sm: AnimationNodeStateMachine = _get_main_animation_state_machine()
	if sm != null:
		if sm.has_node(&"FallBlend"):
			return &"FallBlend"
		if sm.has_node(&"FALL"):
			return &"FALL"
		if sm.has_node(&"GAME_Fall"):
			return &"GAME_Fall"
	return &"FallBlend"


func _get_main_animation_state_machine() -> AnimationNodeStateMachine:
	var p = _owner
	if p.anim_tree == null:
		return null
	var root = p.anim_tree.tree_root
	if root is AnimationNodeStateMachine:
		return root
	if root is AnimationNodeBlendTree:
		var bt: AnimationNodeBlendTree = root
		var sm_node_name: String = PlayerAnimation.SM_BASE.replace("parameters/", "")
		if bt.has_node(sm_node_name):
			return bt.get_node(sm_node_name) as AnimationNodeStateMachine
	return null


func _get_respawn_ground_animation_start_node() -> StringName:
	var p = _owner
	var sm: AnimationNodeStateMachine = _get_ground_animation_state_machine()
	if sm != null:
		if sm.has_node(&"IDLE"):
			return &"IDLE"
		if sm.has_node(&"IDLE_ANIMATION"):
			return &"IDLE_ANIMATION"
		if sm.has_node(&"GAME_Idle"):
			return &"GAME_Idle"
	return &"IDLE"


func _get_ground_animation_state_machine() -> AnimationNodeStateMachine:
	var p = _owner
	var sm: AnimationNodeStateMachine = _get_main_animation_state_machine()
	if sm == null or not sm.has_node(&"GROUND_MACHINE"):
		return null
	return sm.get_node(&"GROUND_MACHINE") as AnimationNodeStateMachine


func _resolve_respawn_point() -> Node3D:
	var p = _owner
	var level_manager = _get_level_manager()
	if level_manager != null:
		if level_manager.has_method("resolve_node_in_current_level"):
			var n = level_manager.call("resolve_node_in_current_level", NodePath("PlayerSpawn"))
			if n is Node3D:
				p.respawn_point = n
				return n
		if level_manager.has_method("get_current_level"):
			var level = level_manager.call("get_current_level")
			if level is Node:
				var n2 = level.get_node_or_null("PlayerSpawn")
				if n2 is Node3D:
					p.respawn_point = n2
					return n2

	if p.get_tree() != null:
		var cs = p.get_tree().current_scene
		if cs != null:
			var n3 = cs.get_node_or_null("PlayerSpawn")
			if n3 is Node3D:
				p.respawn_point = n3
				return n3
	if p.respawn_point != null and is_instance_valid(p.respawn_point):
		return p.respawn_point
	return null


func _get_level_manager() -> Node:
	var p = _owner
	if p.get_tree() == null:
		return null
	var list = p.get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return p.get_tree().root.find_child("LevelManager", true, false)


func activate_checkpoint(respawn_transform: Transform3D, respawn_speed: float, respawn_dir: Vector3) -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if not p.checkpoint_enabled:
		return
	p._checkpoint_active = true
	p._checkpoint_transform = respawn_transform
	p._checkpoint_respawn_speed = max(respawn_speed, 0.0)
	p._checkpoint_respawn_dir = respawn_dir


func activate_checkpoint_from(source: Node, respawn_transform: Transform3D, respawn_speed: float, respawn_dir: Vector3) -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if not p.checkpoint_enabled:
		return
	if source != null and is_instance_valid(source):
		var sid: int = int(source.get_instance_id())
		if sid != 0 and sid == p._checkpoint_last_source_id:
			return
		p._checkpoint_last_source_id = sid
	activate_checkpoint(respawn_transform, respawn_speed, respawn_dir)


func can_activate_checkpoint_source(source: Node) -> bool:
	var p = _owner
	if not p.checkpoint_enabled:
		return false
	if source == null or not is_instance_valid(source):
		return true
	var sid: int = int(source.get_instance_id())
	if sid != 0 and sid == p._checkpoint_last_source_id:
		return false
	return true


func respawn_now() -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if not p._is_dead and p.race_in_countdown:
		return
	if p.race_active:
		_respawn_to_checkpoint()
		return
	_respawn()


func respawn_checkpoint_now() -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if not p._is_dead and p.race_in_countdown:
		return
	_respawn_to_checkpoint()


func clear_checkpoint_data() -> void:
	var p = _owner
	p._checkpoint_active = false
	p._checkpoint_transform = Transform3D.IDENTITY
	p._checkpoint_respawn_speed = 0.0
	p._checkpoint_respawn_dir = Vector3.ZERO
	p._checkpoint_last_source_id = 0


func reset_race_debug_usage() -> void:
	var p = _owner
	p.race_debug_used = p._debug_mode
	p._race_debug_confirm_pending = false
	p._race_debug_confirm_timer = 0.0
	p._race_debug_confirmed = p._debug_mode


func unstuck_now() -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if p.is_ui_input_blocked():
		return
	p._is_dead = false
	_perform_unstuck_nudge()
	stop_all_momentum_and_special_movement()
	if p.has_method("cancel_spline_spring"):
		p.call("cancel_spline_spring")
	if p.has_method("cancel_rail_grind"):
		p.call("cancel_rail_grind")
	if p.has_method("cancel_homing_attack"):
		p.call("cancel_homing_attack", false)
	p._bounce_state = p.BounceState.NONE
	p._jump_dash_recent_timer = 0.0
	p._jump_dash_requested = false
	p._jump_dashing = false
	p._jump_dash_used_this_air = false
	p._spindash_pending_release = false
	p._spindash_pending_release_speed = 0.0
	p._spindash_release_requested = false
	p._spindash_release_with_jump = false
	p._spindash_release_speed = 0.0
	p._spindash_entry_speed = 0.0
	p._spindash_turn_free_timer = 0.0
	p._dash_speed_lock_timer = 0.0
	p._dash_speed_lock_speed = 0.0
	p._automation_active = false
	p._automation_timer = 0.0
	p._automation_lock_movement = false
	p._automation_lock_actions = false
	p._automation_lock_drift = false
	p._automation_tangent_dir = Vector3.ZERO
	p._automation_toward_dir = Vector3.ZERO
	p._automation_toward_strength = 0.0
	p._automation_max_turn_deg_per_sec = 0.0
	p._automation_along_target_speed = 0.0
	p._automation_along_accel = 0.0
	p._automation_continuous_force = true
	p._automation_align_rotation = true
	p._automation_grounded_only = true
	p._automation_force_surface_adhesion = false
	p._automation_tangent_snap_strength = 0.0
	p._automation_along_assist_enabled = true
	p._automation_along_speed_limits_player = true
	p._automation_bidirectional_assist = false
	p._automation_mode = p.AutomationSplineMode.GUIDED
	p._automation_constraint_source = null
	p._automation_influence = 0.0
	p._automation_path_point = Vector3.ZERO
	p._automation_plane_normal = Vector3.ZERO
	p._automation_plane_up = Vector3.UP
	p._automation_input_mode = p.AutomationPlaneInputMode.PATH_HORIZONTAL
	p._automation_reverse_input = false
	p._automation_input_deadzone = 0.05
	p._automation_strict_position_lock = true
	p._automation_post_slide_constraint_pass_enabled = false
	p._automation_position_lock_strength = 12.0
	p._automation_max_position_correction_speed = 80.0
	p._automation_position_lock_deadzone = 0.005
	p._automation_strict_velocity_lock = true
	p._automation_disable_turning_slowdown = false
	p._automation_velocity_lock_strength = 18.0
	p._automation_sideways_speed_preservation = 0.0
	p._automation_constrain_special_moves = true
	p._automation_priority_current = -9999
	p._automation_priority_frame = -1
	p.attached = false
	p._prev_attached = false
	p._reset_standing_clearance_state()
	p._move_input = Vector2.ZERO
	p._move_direction = Vector3.ZERO
	p._spring_movement_lock_timer = 0.0
	p._spring_action_lock_timer = 0.0
	p._spring_align_timer = 0.0
	p._spring_detached = false
	p._spring_trajectory_torque_active = false
	p._spring_trajectory_landing_forward_pitch_active = false
	p._spring_lock_sideways = false
	p._spring_sideways_gravity_scale = 0.0
	p._spring_clear_move_on_ground = false
	p._spring_clear_action_on_ground = false
	p._apply_grounded_after_debug_exit()


func _get_unstuck_nudge_dir() -> Vector3:
	var p = _owner
	var x: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var z: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var input: Vector2 = Vector2(x, z)
	if input.length() > 1.0:
		input = input.normalized()
	if input.length() < 0.001:
		return Vector3.ZERO

	var forward: Vector3 = p._control_forward
	var right: Vector3 = p._control_right
	var dir: Vector3 = forward * input.y + right * input.x
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized()


func _perform_unstuck_nudge() -> void:
	var p = _owner
	var nudge_dir: Vector3 = _get_unstuck_nudge_dir()
	if nudge_dir.length() < 0.001:
		nudge_dir = p._control_forward
		if nudge_dir.length() < 0.001:
			nudge_dir = -p.global_transform.basis.z
	if nudge_dir.length() < 0.001:
		return

	var nudge_dist: float = max(p.unstuck_nudge_distance, 0.0)
	if nudge_dist < 0.001:
		return
	var nudge: Vector3 = nudge_dir.normalized() * nudge_dist

	var safe_nudge: Vector3 = Vector3.ZERO
	var step_count: int = clampi(p.unstuck_nudge_steps, 1, 8)
	var scale: float = 1.0
	for _i in range(step_count):
		var candidate: Vector3 = nudge * scale
		if candidate.length() < 0.001:
			break
		if not p.test_move(p.global_transform, candidate):
			safe_nudge = candidate
			break
		scale *= 0.5

	var previous_layer: int = p.collision_layer
	var previous_mask: int = p.collision_mask
	p.collision_layer = 0
	p.collision_mask = 0
	if safe_nudge.length() > 0.001:
		p.global_position += safe_nudge
	elif nudge.length() > 0.001:
		var fallback_scale: float = clamp(p.unstuck_force_nudge_scale, 0.0, 1.0)
		p.global_position += nudge * fallback_scale
	p.collision_layer = previous_layer
	p.collision_mask = previous_mask


	p.clear_max_speed_overrides()


func stop_all_momentum_and_special_movement() -> void:
	var p = _owner
	p.clear_air_trick_bank()
	# Used by cutscenes (goal, race start, etc.) to ensure no leftover impulses/states.
	p._stop_lightspeed_dash_if_active(false)
	p.velocity = Vector3.ZERO
	p._reset_directional_influence_lock()
	p._reset_stable_attach_normal()

	# Clear impulses / locks that can keep overriding velocity after teleport.
	p._dash_speed_lock_timer = 0.0
	p._ramp_hold_forward_timer = 0.0
	p._ramp_hold_up_timer = 0.0
	p._ramp_hold_forward_speed = 0.0
	p._ramp_hold_up_speed = 0.0
	p._ramp_hold_forward_dir = Vector3.ZERO
	p._ramp_hold_up_dir = Vector3.ZERO

	# Cancel special movement states.
	if p._homing_active or p._homing_target != null:
		p.cancel_homing_attack(false)
	p._reset_spindash_state()
	p._spline_active = false
	p._spline_path = null
	p._spline_distance = 0.0
	p._spline_speed = 0.0
	p._spline_total_length = 0.0
	p.cancel_rail_grind(false)
	p._rail_crouching = false
	p._rail_model_basis_valid = false

	p._spring_align_timer = 0.0
	p._spring_detached = false
	p._spring_trajectory_torque_active = false
	p._spring_trajectory_landing_forward_pitch_active = false
	p._spring_movement_lock_timer = 0.0
	p._spring_action_lock_timer = 0.0

	# Reset basic airborne flags so grounded actions can resume once controls are unlocked.
	p._is_jumping = false
	p._jump_variable = false
	p._jump_time = 0.0
	p._jump_hang_allowed = false
	p._just_jumped = false
	p._is_falling = false
	p._jumped_from_ground = false
	p._falling_without_jump = false
	p._homing_post_attack_timer = 0.0
	p._lightspeed_dash_start_bonus_cooldown_timer = 0.0
	p._enemy_bounce_cooldown_timer = 0.0
	p._clear_enemy_hurt_boundary_exceptions()
	p._attack_sources = 0
	p._jump_dash_requested = false
	p._jump_dashing = false
	p._jump_dash_used_this_air = false


func _notify_camera_teleport() -> void:
	var p = _owner
	if p._is_buddy_actor() or not p._network_is_local_authority():
		return
	var rig = p.camera_rig
	if rig == null and p.camera != null:
		rig = p.camera.get_parent()
	if rig == null and p.get_tree() != null:
		var rigs = p.get_tree().get_nodes_in_group("CameraRig")
		if rigs != null and rigs.size() > 0:
			rig = rigs[0]
	if rig != null and rig.has_method("notify_teleport"):
		rig.call("notify_teleport")

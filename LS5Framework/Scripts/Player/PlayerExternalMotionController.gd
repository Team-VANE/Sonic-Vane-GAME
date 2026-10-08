extends RefCounted
class_name PlayerExternalMotionController

# Teleport, automation, spring, dash-panel, ramp, and spline motion.
var _owner: Node = null
var _spline_transport_up: Vector3 = Vector3.UP
var _spline_transport_right: Vector3 = Vector3.RIGHT
var _spline_transport_valid: bool = false


func _init(owner: Node) -> void:
	_owner = owner


func apply_teleport(exit_transform: Transform3D, keep_vel: bool, match_rot: bool, exit_local_offset: Vector3) -> void:
	var p = _owner
	p.cancel_homing_attack(false)
	cancel_spline_spring()
	cancel_vault_bar()
	p.cancel_rail_grind()
	var world_offset: Vector3 = exit_transform.basis * exit_local_offset
	var new_origin: Vector3 = exit_transform.origin + world_offset
	var old_basis: Basis = p.global_transform.basis

	# Move (and optionally rotate)
	if match_rot:
		var new_basis: Basis = exit_transform.basis.orthonormalized()
		p.global_transform = Transform3D(new_basis, new_origin)
		if keep_vel:
			var old_basis_ortho: Basis = old_basis.orthonormalized()
			p.velocity = new_basis * old_basis_ortho.inverse() * p.velocity
		var exit_up: Vector3 = new_basis.y
		var exit_forward: Vector3 = -new_basis.z
		if exit_up.length() < 0.001:
			exit_up = p._get_gravity_up()
		p.visual_up = exit_up.normalized()
		p._physics_up_last = p.visual_up
		if exit_forward.length() > 0.001:
			var f: Vector3 = exit_forward - p.visual_up * exit_forward.dot(p.visual_up)
			if f.length() > 0.001:
				p._model_forward = f.normalized()
		p.snap_model_to_normal(p.visual_up, p._model_forward)
		if p.camera_rig != null and p.camera_rig.has_method("set_yaw_from_forward"):
			p.camera_rig.call("set_yaw_from_forward", exit_forward, p._get_gravity_up())
	else:
		p.global_transform = Transform3D(p.global_transform.basis, new_origin)

	# Momentum option
	if not keep_vel:
		p.velocity = Vector3.ZERO

	# Reset “surface/adhesion” type state similarly to spring detachment :contentReference[oaicite:7]{index=7}
	if p.attached:
		p._record_detach_state(p.surface_normal, p._get_gravity_up(), false)
	p.attached = false
	p._reset_stable_attach_normal()
	p._attachment_immunity = p.launch_immunity_time
	p._airborne_time = 0.0
	p._platform_on_floor_last = false
	p._platform_collider_last = null
	p._reset_spindash_state()
	print("[TP-APPLY] vel=%v last_air=%v jump_req=%s plat_on=%s" % [p.velocity, p._last_air_velocity, p._jump_requested, p._platform_on_floor_last])
	p._dbg_tp_trace = 8
	p._notify_camera_teleport()
	p._sync_buddy_after_leader_teleport()
	if p.has_method("_network_publish_teleport_state"):
		p.call("_network_publish_teleport_state")


func _apply_grounded_from_downwarp(grounded_point: Vector3, grounded_normal: Vector3) -> void:
	var p = _owner
	# SUMMARY: Force grounded state after a downwarp reposition.
	# STEPS:
	# - Step 1: Normalize the ground normal and apply it as physics up.
	# - Step 2: Set surface data and grounded flags.
	var n: Vector3 = grounded_normal.normalized()
	if n.length() < 0.001:
		n = p._get_gravity_up()

	p._physics_up_last = n
	p.up_direction = n
	p.surface_normal = n
	p.surface_point = grounded_point

	p.attached = true
	p._prev_attached = true
	p._airborne_time = 0.0
	p._is_falling = false
	p._is_jumping = false
	p._attachment_immunity = 0.0
	p._record_attach_state(n, p._get_gravity_up())


func apply_teleport_from_exit(exit_node: Node3D, keep_vel: bool, match_rot: bool, exit_local_offset: Vector3) -> void:
	var p = _owner
	if exit_node == null or not is_instance_valid(exit_node):
		return
	var exit_xform: Transform3D = exit_node.global_transform
	var world_offset: Vector3 = exit_xform.basis * exit_local_offset
	var base_xform: Transform3D = Transform3D(exit_xform.basis, exit_xform.origin + world_offset)
	var downwarp_info: Dictionary = DownwarpUtil.apply_downwarp_from_node_with_hit(exit_node, base_xform, [p])
	var downwarp_hit: bool = false
	var downwarp_point: Vector3 = Vector3.ZERO
	var downwarp_normal: Vector3 = p._get_gravity_up()
	if p._is_surface_alignment_rejected(
		downwarp_info.get("collider"),
		downwarp_info.get("normal", downwarp_normal),
		p._get_gravity_up(),
		int(downwarp_info.get("shape", -1))
	):
		downwarp_info.clear()
	if downwarp_info.has("xform") and downwarp_info["xform"] is Transform3D:
		base_xform = downwarp_info["xform"]
	if downwarp_info.has("hit"):
		downwarp_hit = bool(downwarp_info["hit"])
	if downwarp_info.has("point") and downwarp_info["point"] is Vector3:
		downwarp_point = downwarp_info["point"]
	if downwarp_info.has("normal") and downwarp_info["normal"] is Vector3:
		downwarp_normal = downwarp_info["normal"]

	apply_teleport(base_xform, keep_vel, match_rot, Vector3.ZERO)
	if downwarp_hit:
		_apply_grounded_from_downwarp(downwarp_point, downwarp_normal)
		if p.has_method("_network_publish_teleport_state"):
			p.call("_network_publish_teleport_state")


func cancel_spline_spring() -> void:
	var p = _owner
	var previous_path: Variant = p._spline_path
	p._spline_active = false
	p._spline_path = null
	p._spline_distance = 0.0
	p._spline_speed = 0.0
	p._spline_total_length = 0.0
	p._spline_world_offset = Vector3.ZERO
	_spline_transport_up = Vector3.UP
	_spline_transport_right = Vector3.RIGHT
	_spline_transport_valid = false
	if is_instance_valid(previous_path) and previous_path is Path3D:
		var valid_path: Path3D = previous_path as Path3D
		if valid_path.has_meta(&"runtime_trajectory_arc") and not valid_path.is_queued_for_deletion():
			valid_path.queue_free()


func begin_vault_bar(
	source: Node,
	grip_position: Vector3,
	model_basis: Basis,
	animation_name: StringName
) -> bool:
	var p = _owner
	if not source or not is_instance_valid(source):
		return false
	if p._vault_bar_active:
		if p._vault_bar_source == source:
			return true
		cancel_vault_bar()

	p.cancel_rail_grind(false)
	cancel_spline_spring()
	p.cancel_homing_attack(false)
	p._stop_lightspeed_dash_if_active(false)
	p._force_neutral_air_action({"reason": &"vault_bar"})
	p._reset_drift_state()
	p._reset_spindash_state()
	p._bounce_state = p.BounceState.NONE
	p.rolling = false
	p._attack_sources = 0
	p._enemy_attack_chain_active = false
	p._is_jumping = false
	p._jumped_from_ground = false
	p._falling_without_jump = false
	p._jump_variable = false
	p._jump_hang_allowed = false
	p._jump_time = 0.0
	p.refresh_airborne_abilities()
	p._jump_dash_requested = false
	p._jump_dash_recent_timer = 0.0
	p._spring_align_timer = 0.0
	p._spring_align_model = false
	p._spring_lock_sideways = false
	p._spring_detached = false
	p._air_torque_segment_allowed = false
	p._air_torque_angular_velocity = Vector3.ZERO
	p._air_trick_animation_gesture_latched = false
	p._air_trick_animation_last_command = &""
	p._external_airborne_torque_active = false
	p._external_airborne_trick_command = &""

	if p.attached:
		p._record_detach_state(p.surface_normal, p._get_gravity_up(), false)
	p.attached = false
	p._attachment_immunity = p.launch_immunity_time
	p._airborne_time = 0.0
	p.velocity = Vector3.ZERO
	p._is_falling = false
	p.global_position = grip_position

	p._vault_bar_active = true
	p._vault_bar_source = source
	set_vault_bar_pose(source, grip_position, model_basis)
	_play_vault_bar_animation(animation_name)
	p._update_jump_ball(0.0)
	if p.model_root:
		p.model_root.visible = true
	p._refresh_carried_object_target_after_external_motion()
	return true


func set_vault_bar_pose(source: Node, grip_position: Vector3, model_basis: Basis) -> bool:
	var p = _owner
	if not p._vault_bar_active or p._vault_bar_source != source:
		return false
	if not p.model_root or not is_instance_valid(p.model_root):
		return false

	var basis: Basis = model_basis.orthonormalized()
	p.global_position = grip_position
	var model_transform: Transform3D = p.model_root.global_transform
	model_transform.basis = basis
	p.model_root.global_transform = model_transform
	p.visual_up = basis.y.normalized()
	p._physics_up_last = p.visual_up
	p._air_torque_visual_forward = (-basis.z).normalized()
	p._model_forward = p._air_torque_visual_forward
	p.velocity = Vector3.ZERO
	p._refresh_carried_object_target_after_external_motion()
	return true


func update_vault_bar(delta: float) -> void:
	var p = _owner
	if not p._vault_bar_active:
		return
	var source: Node = p._vault_bar_source
	if not source or not is_instance_valid(source) or not source.is_inside_tree():
		cancel_vault_bar()
		return
	if not source.has_method("update_vault_bar_player"):
		cancel_vault_bar()
		return
	source.call("update_vault_bar_player", p, delta)


func launch_from_vault_bar(
	source: Node,
	launch_velocity: Vector3,
	angular_velocity: Vector3,
	movement_lock_time: float,
	action_lock_time: float,
	align_time: float,
	launch_basis: Basis,
	spline_path: Path3D = null,
	spline_speed: float = 0.0,
	spline_world_offset: Vector3 = Vector3.ZERO,
	pitch_trick_command: StringName = &""
) -> bool:
	var p = _owner
	if not p._vault_bar_active or p._vault_bar_source != source:
		return false

	_restore_vault_bar_animation()
	p._vault_bar_active = false
	p._vault_bar_source = null
	p.cancel_homing_attack(false)
	p.attached = false
	p._attachment_immunity = p.launch_immunity_time
	p._airborne_time = 0.0
	p._is_falling = false
	p._spring_detached = true
	p._spring_align_model = false
	p._spring_model_snap_timer = 0.0
	p._spring_clear_move_on_ground = true
	p._spring_clear_action_on_ground = true
	p.reset_trick_staleness()
	p.refresh_airborne_abilities()
	p.reset_flight_eligibility()
	p.end_active_flight_for_external_impulse({"reason": &"vault_bar_launch"})

	if spline_path and spline_path.curve and spline_speed > 0.0:
		start_spline_spring(
			spline_path,
			spline_speed,
			false,
			true,
			false,
			action_lock_time,
			spline_world_offset,
			&""
		)
	else:
		cancel_spline_spring()
		p.velocity = launch_velocity

	if movement_lock_time > 0.0:
		p._spring_movement_lock_timer = max(p._spring_movement_lock_timer, movement_lock_time)
	if action_lock_time > 0.0:
		p._spring_action_lock_timer = max(p._spring_action_lock_timer, action_lock_time)

	if align_time > 0.0 and not p._spline_active:
		var launch_direction: Vector3 = launch_velocity.normalized()
		if launch_direction.length() < 0.001:
			launch_direction = (-launch_basis.z).normalized()
		p._spring_align_timer = max(p._spring_align_timer, align_time)
		p._spring_align_up = launch_basis.y.normalized()
		p._spring_align_forward = (-launch_basis.z).normalized()
		p._spring_align_dir = launch_direction
		p._spring_lock_sideways = true
		p._spring_sideways_gravity_scale = 0.0
		p._spring_cancel_on_ground = true
	else:
		p._spring_align_timer = 0.0
		p._spring_lock_sideways = false

	_seed_vault_bar_torque(angular_velocity, pitch_trick_command)
	p._pending_anim_command = &""
	if p.anim_state:
		p.anim_state.travel(&"FallBlend")
	_trigger_vault_bar_trick_animation()
	p._refresh_carried_object_target_after_external_motion()
	return true


func cancel_vault_bar(source: Node = null) -> void:
	var p = _owner
	if not p._vault_bar_active:
		return
	if source and p._vault_bar_source != source:
		return

	var previous_source: Node = p._vault_bar_source
	_restore_vault_bar_animation()
	p._vault_bar_active = false
	p._vault_bar_source = null
	p._external_airborne_torque_active = false
	p._external_airborne_trick_command = &""
	p._air_torque_segment_allowed = false
	p.velocity = Vector3.ZERO
	if p.anim_state:
		p.anim_state.travel(&"FallBlend")
	if previous_source and is_instance_valid(previous_source):
		if previous_source.has_method("on_vault_bar_player_cancelled"):
			previous_source.call("on_vault_bar_player_cancelled", p)


func _play_vault_bar_animation(animation_name: StringName) -> bool:
	var p = _owner
	if animation_name == &"" or not p.anim_tree:
		return false
	var animation_player: AnimationPlayer = p.anim_tree.get_node_or_null(p.anim_tree.anim_player) as AnimationPlayer
	if not animation_player:
		return false
	var resolved_name: StringName = _resolve_vault_bar_animation_name(animation_player, animation_name)
	if resolved_name == &"":
		return false

	p._vault_bar_animation_player = animation_player
	p._vault_bar_animation_tree_was_active = p.anim_tree.active
	p._vault_bar_animation_override_active = true
	p.anim_tree.active = false
	animation_player.play(resolved_name)
	return true


func _resolve_vault_bar_animation_name(
	animation_player: AnimationPlayer,
	requested_name: StringName
) -> StringName:
	if animation_player.has_animation(requested_name):
		return requested_name
	var requested: String = String(requested_name)
	for available_name in animation_player.get_animation_list():
		var available: String = String(available_name)
		if available.ends_with("/" + requested) or available.ends_with("/SONIC_" + requested):
			return StringName(available)
	return &""


func _restore_vault_bar_animation() -> void:
	var p = _owner
	if p._vault_bar_animation_override_active:
		if p._vault_bar_animation_player and is_instance_valid(p._vault_bar_animation_player):
			p._vault_bar_animation_player.stop()
		if p.anim_tree:
			p.anim_tree.active = p._vault_bar_animation_tree_was_active
	p._vault_bar_animation_player = null
	p._vault_bar_animation_override_active = false


func _seed_vault_bar_torque(angular_velocity: Vector3, pitch_trick_command: StringName) -> void:
	var p = _owner
	p._spring_trajectory_torque_active = false
	p._spring_trajectory_landing_forward_pitch_active = false
	p._clear_air_torque_samples()
	p._clear_air_landing_align()
	p._air_torque_airborne_time = 0.0
	p._air_torque_rotation_accum = Vector3.ZERO
	p._trick_retrigger_timer = 0.0
	p._air_torque_segment_allowed = p.airborne_torque_enabled and angular_velocity.length() > 0.001
	p._external_airborne_torque_active = p._air_torque_segment_allowed
	p._external_airborne_trick_command = pitch_trick_command if p._air_torque_segment_allowed else &""
	p._manual_airborne_torque_active = false
	p._manual_airborne_torque_suppress_decay = false
	p._manual_airborne_torque_fast_decay = false
	var torque_gain: float = max(p.airborne_torque_gain, 0.001)
	p._air_torque_angular_velocity = angular_velocity / torque_gain if p._air_torque_segment_allowed else Vector3.ZERO
	if p.model_root and is_instance_valid(p.model_root):
		var basis: Basis = p.model_root.global_transform.basis.orthonormalized()
		p.visual_up = basis.y.normalized()
		p._air_torque_visual_forward = (-basis.z).normalized()
		p._air_torque_yaw_forward = p._air_torque_visual_forward


func _trigger_vault_bar_trick_animation() -> void:
	var p = _owner
	if not p._network_is_local_authority() or not p.anim_state:
		return
	var tricks_allowed: bool = p.trick_animations_enabled
	if p._external_airborne_torque_active and p.manual_airborne_torque_tricks_enabled:
		tricks_allowed = true
	if not tricks_allowed or not p._air_torque_segment_allowed:
		return
	var command: StringName = p._external_airborne_trick_command
	if command == &"":
		return
	p._trigger_anim_command(command, true, p.trick_anim_crossfade)
	p._air_trick_animation_gesture_latched = true
	p._air_trick_animation_last_command = command
	p._trick_retrigger_timer = max(p.trick_retrigger_delay, 0.0)


func set_timed_max_speed_override(speed: float, duration: float) -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if p.race_in_countdown:
		clear_timed_max_speed_override()
		return
	var duration_used: float = max(duration, 0.0)
	var speed_used: float = max(speed, 0.0)
	if duration_used <= 0.0:
		clear_timed_max_speed_override()
		return
	p._timed_max_speed_override = speed_used
	p._timed_max_speed_override_timer = duration_used


func clear_timed_max_speed_override() -> void:
	var p = _owner
	p._timed_max_speed_override_timer = 0.0
	p._timed_max_speed_override = 0.0


func clear_max_speed_overrides() -> void:
	var p = _owner
	clear_timed_max_speed_override()
	p._automation_max_speed_override_enabled = false
	p._automation_max_speed_override = 0.0
	p._functional_max_speed = max(p.max_speed, 0.0)


func set_automation_spline(
	tangent_dir: Vector3,
	toward_dir: Vector3,
	toward_strength: float,
	max_turn_deg_per_sec: float,
	lock_controls: bool,
	continuous_force: bool,
	align_rotation: bool,
	grounded_only: bool,
	force_surface_adhesion: bool,
	tangent_snap_strength: float,
	along_assist_enabled: bool,
	along_assist_target_speed: float,
	along_assist_accel: float,
	lock_movement: bool = false,
	lock_actions: bool = false,
	lock_drift: bool = false,
	priority: int = 0,
	ignore_water_physics_multipliers: bool = false,
	override_max_speed: bool = false,
	max_speed_override: float = 0.0
) -> void:
	set_automation_spline_state({
		"tangent_dir": tangent_dir,
		"toward_dir": toward_dir,
		"toward_strength": toward_strength,
		"max_turn_deg_per_sec": max_turn_deg_per_sec,
		"lock_movement": lock_movement or lock_controls,
		"lock_actions": lock_actions or lock_controls,
		"lock_drift": lock_drift or lock_controls,
		"continuous_force": continuous_force,
		"align_rotation": align_rotation,
		"grounded_only": grounded_only,
		"force_surface_adhesion": force_surface_adhesion,
		"tangent_snap_strength": tangent_snap_strength,
		"along_assist_enabled": along_assist_enabled,
		"along_assist_target_speed": along_assist_target_speed,
		"along_assist_accel": along_assist_accel,
		"along_assist_limits_player_speed": true,
		"bidirectional_assist": false,
		"priority": priority,
		"ignore_water_physics_multipliers": ignore_water_physics_multipliers,
		"override_max_speed": override_max_speed,
		"max_speed_override": max_speed_override,
		"mode": 0,
	})


func set_automation_spline_state(state: Dictionary) -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	var priority: int = int(state.get("priority", 0))
	var frame_id: int = Engine.get_physics_frames()
	if frame_id != p._automation_priority_frame:
		p._automation_priority_frame = frame_id
		p._automation_priority_current = -9999
	if priority < p._automation_priority_current:
		return
	p._automation_active = true
	p._automation_tangent_dir = state.get("tangent_dir", Vector3.ZERO) as Vector3
	p._automation_toward_dir = state.get("toward_dir", Vector3.ZERO) as Vector3
	p._automation_toward_strength = max(float(state.get("toward_strength", 0.0)), 0.0)
	p._automation_max_turn_deg_per_sec = max(float(state.get("max_turn_deg_per_sec", 0.0)), 0.0)
	p._automation_lock_movement = bool(state.get("lock_movement", false))
	p._automation_lock_actions = bool(state.get("lock_actions", false))
	p._automation_lock_drift = bool(state.get("lock_drift", false))
	p._automation_priority_current = priority
	p._automation_continuous_force = bool(state.get("continuous_force", true))
	p._automation_align_rotation = bool(state.get("align_rotation", true))
	p._automation_grounded_only = bool(state.get("grounded_only", true))
	p._automation_force_surface_adhesion = bool(state.get("force_surface_adhesion", false))
	p._automation_tangent_snap_strength = max(float(state.get("tangent_snap_strength", 0.0)), 0.0)
	p._automation_along_assist_enabled = bool(state.get("along_assist_enabled", true))
	p._automation_along_target_speed = max(float(state.get("along_assist_target_speed", 0.0)), 0.0)
	p._automation_along_accel = max(float(state.get("along_assist_accel", 0.0)), 0.0)
	p._automation_along_speed_limits_player = bool(state.get("along_assist_limits_player_speed", true))
	p._automation_bidirectional_assist = bool(state.get("bidirectional_assist", false))
	p._automation_ignore_water_physics = bool(state.get("ignore_water_physics_multipliers", false))
	p._automation_max_speed_override_enabled = bool(state.get("override_max_speed", false)) and not p.race_in_countdown
	p._automation_max_speed_override = max(float(state.get("max_speed_override", 0.0)), 0.0)
	p._automation_mode = int(state.get("mode", p.AutomationSplineMode.GUIDED))
	var constraint_source_value: Variant = state.get("constraint_source", null)
	p._automation_constraint_source = (
		constraint_source_value as Node
		if constraint_source_value is Node
		else null
	)
	p._automation_influence = clamp(float(state.get("influence", 0.0)), 0.0, 1.0)
	p._automation_path_point = state.get("path_point", Vector3.ZERO) as Vector3
	p._automation_plane_normal = state.get("plane_normal", Vector3.ZERO) as Vector3
	p._automation_plane_up = state.get("plane_up", Vector3.UP) as Vector3
	p._automation_input_mode = int(state.get("input_mode", p.AutomationPlaneInputMode.PATH_HORIZONTAL))
	p._automation_reverse_input = bool(state.get("reverse_input", false))
	p._automation_input_deadzone = clamp(float(state.get("input_deadzone", 0.05)), 0.0, 1.0)
	p._automation_strict_position_lock = bool(state.get("strict_position_lock", true))
	p._automation_post_slide_constraint_pass_enabled = bool(
		state.get("post_slide_constraint_pass_enabled", false)
	)
	p._automation_position_lock_strength = max(float(state.get("position_lock_strength", 12.0)), 0.0)
	p._automation_max_position_correction_speed = max(float(state.get("max_position_correction_speed", 80.0)), 0.0)
	p._automation_position_lock_deadzone = max(float(state.get("position_lock_deadzone", 0.005)), 0.0)
	p._automation_strict_velocity_lock = bool(state.get("strict_velocity_lock", true))
	p._automation_disable_turning_slowdown = bool(
		state.get("disable_turning_slowdown", false)
	)
	p._automation_velocity_lock_strength = max(float(state.get("velocity_lock_strength", 18.0)), 0.0)
	p._automation_sideways_speed_preservation = clamp(float(state.get("sideways_speed_preservation", 0.0)), 0.0, 1.0)
	p._automation_constrain_special_moves = bool(state.get("constrain_special_moves", true))
	p._automation_timer = 0.1


func _automation_locks_active() -> bool:
	var p = _owner
	# Locks follow the same grounded-only gating as automation movement influence.
	if not p._automation_active:
		return false
	if p._automation_timer <= 0.0:
		return false
	if p._automation_grounded_only and not p.attached:
		return false
	return true


func apply_spring_impulse(
	spring_position: Vector3,
	spring_direction: Vector3,
	spring_strength: float,
	snap_to_center: bool,
	stop_momentum: bool,
	additive_mode: int,
	min_additive_launch_speed: float,
	additive_mirrored_bounce_ratio: float,
	max_additive_launch_speed: float,
	movement_lock_time: float,
	action_lock_time: float,
	align_time: float,
	spring_basis: Basis,
	clear_move_on_ground: bool,
	clear_action_on_ground: bool,
	lock_horizontal_during_align: bool,
	sideways_gravity_scale: float,
	detach_from_ground: bool,
	align_model_during_spring: bool,
	preserve_active_flight: bool = false,
	flight_time_bonus: float = 0.0,
	downward_trajectory_torque_enabled: bool = true,
	downward_trajectory_min_angle_deg: float = 45.0,
	downward_trajectory_align_speed_deg: float = 720.0,
	downward_trajectory_gravity_yaw_enabled: bool = true,
	downward_trajectory_gravity_yaw_strength: float = 1.0,
	downward_trajectory_gravity_yaw_safe_angle_deg: float = 3.0,
	downward_trajectory_gravity_yaw_full_angle_deg: float = 90.0,
	downward_trajectory_torque_min_horizontal_speed: float = 2.0,
	downward_trajectory_landing_forward_pitch_enabled: bool = true
	) -> void:
	var p = _owner
	cancel_vault_bar()
	if p._dbg_tp_trace > 0:
		print("[TP] SPRING_IMPULSE called: dir=%v strength=%s vel=%v" % [spring_direction, spring_strength, p.velocity])
	if p._spring_action != null:
		p._sync_spring_state_to_action()
		p._spring_action.apply_impulse(
			spring_position,
			spring_direction,
			spring_strength,
			snap_to_center,
			stop_momentum,
			additive_mode,
			min_additive_launch_speed,
			additive_mirrored_bounce_ratio,
			max_additive_launch_speed,
			movement_lock_time,
			action_lock_time,
			align_time,
			spring_basis,
			clear_move_on_ground,
			clear_action_on_ground,
			lock_horizontal_during_align,
			sideways_gravity_scale,
			detach_from_ground,
			align_model_during_spring,
			preserve_active_flight,
			flight_time_bonus,
			downward_trajectory_torque_enabled,
			downward_trajectory_min_angle_deg,
			downward_trajectory_align_speed_deg,
			downward_trajectory_gravity_yaw_enabled,
			downward_trajectory_gravity_yaw_strength,
			downward_trajectory_gravity_yaw_safe_angle_deg,
			downward_trajectory_gravity_yaw_full_angle_deg,
			downward_trajectory_torque_min_horizontal_speed,
			downward_trajectory_landing_forward_pitch_enabled
		)
		p._sync_spring_state_from_action()
		return
	var preserve_flight: bool = preserve_active_flight and p.is_current_action_flight()
	var effective_align_time: float = align_time
	var effective_align_model: bool = align_model_during_spring
	var effective_lock_horizontal: bool = lock_horizontal_during_align
	if preserve_flight:
		effective_align_time = 0.0
		effective_align_model = false
		effective_lock_horizontal = false
		p.add_flight_time(flight_time_bonus)
	cancel_spline_spring()
	p.cancel_homing_attack(false)
	
	p._spring_align_timer = 0.0
	p.reset_trick_staleness()
	p._bounce_state = p.BounceState.NONE
	p._is_jumping = false
	p._jump_variable = false
	p._jump_hang_allowed = false
	p._jump_time = 0.0
	p.refresh_airborne_abilities()
	p._jump_dash_requested = false
	p._jump_dash_recent_timer = 0.0
	
	p._spring_align_model = effective_align_model
	if p._spring_align_model and p.spring_model_snap_time > 0.0:
		p._spring_model_snap_timer = max(p._spring_model_snap_timer, p.spring_model_snap_time)
	else:
		p._spring_model_snap_timer = 0.0
	var dir: Vector3 = spring_direction.normalized()
	if dir.length() < 0.001:
		dir = p._get_gravity_up()

	p._spring_detached = detach_from_ground

	# --- Detach only if the spring wants it ---
	if detach_from_ground:
		p._record_spring_detach_state(p._get_gravity_up())
		p.attached = false
		p._attachment_immunity = p.launch_immunity_time
		p._airborne_time = 0.0
	else:
		# NO detachment — stay grounded & preserve surface_normal
		# But still apply impulse
		p._airborne_time = 0.0

	# Optionally snap player to spring center.
	if snap_to_center:
		p.global_position = spring_position
		p.surface_point = spring_position

	var v: Vector3 = p.velocity
	var impulse_up: Vector3 = p._get_gravity_up()

	var inward_speed: float = min(v.dot(dir), 0.0)
	if stop_momentum:
		p.velocity = dir * spring_strength
	else:
		# --- ADDITIVE MODES ---
		match additive_mode:
			0: # IgnorePriorVertical
				var vert: float = v.dot(impulse_up)
				var lateral: Vector3 = v - impulse_up * vert
				var launch: Vector3 = dir * spring_strength
				p.velocity = lateral + launch
			1: # FullyAdditiveWithMinLaunch
				p.velocity = v + dir * spring_strength
			_:
				var vert: float = v.dot(impulse_up)
				var lateral: Vector3 = v - impulse_up * vert
				var launch: Vector3 = dir * spring_strength
				p.velocity = lateral + launch

	var mirrored_ratio: float = max(additive_mirrored_bounce_ratio, 0.0)
	var along_speed: float = p.velocity.dot(dir)
	if not stop_momentum:
		along_speed = max(along_speed, min_additive_launch_speed)
	if inward_speed < 0.0 and mirrored_ratio > 0.0:
		var mirrored_speed: float = -inward_speed
		if mirrored_ratio <= 1.0:
			along_speed = lerp(along_speed, mirrored_speed, mirrored_ratio)
		else:
			along_speed = mirrored_speed * mirrored_ratio
	if max_additive_launch_speed > 0.0:
		along_speed = min(along_speed, max_additive_launch_speed)
	p.velocity += dir * (along_speed - p.velocity.dot(dir))
	# --- Apply locks / alignment timers ---
	if movement_lock_time > 0.0:
		p._spring_movement_lock_timer = max(p._spring_movement_lock_timer, movement_lock_time)

	if action_lock_time > 0.0:
		p._spring_action_lock_timer = max(p._spring_action_lock_timer, action_lock_time)

	if effective_align_time > 0.0:
		p._spring_align_timer = max(p._spring_align_timer, effective_align_time)
		p._spring_align_up = spring_basis.y.normalized()
		p._spring_align_forward = (-spring_basis.z).normalized()
		p._spring_align_dir = dir
		p._spring_lock_sideways = effective_lock_horizontal
		p._spring_sideways_gravity_scale = sideways_gravity_scale
		p._spring_cancel_on_ground = true

	# Remember whether to clear locks on next landing.
	p._spring_clear_move_on_ground = clear_move_on_ground
	p._spring_clear_action_on_ground = clear_action_on_ground
	
	if p._spring_align_timer <= 0.0:
		p._spring_align_model = false

	if not preserve_flight:
		p.reset_flight_eligibility()
		p.end_active_flight_for_external_impulse({"reason": &"spring_impulse"})


	configure_spring_trajectory_torque(
		dir,
		downward_trajectory_torque_enabled and detach_from_ground and not preserve_flight,
		downward_trajectory_min_angle_deg,
		downward_trajectory_align_speed_deg,
		downward_trajectory_gravity_yaw_enabled,
		downward_trajectory_gravity_yaw_strength,
		downward_trajectory_gravity_yaw_safe_angle_deg,
		downward_trajectory_gravity_yaw_full_angle_deg,
		downward_trajectory_torque_min_horizontal_speed,
		downward_trajectory_landing_forward_pitch_enabled
	)
	if not preserve_flight:
		p._trigger_anim_command(&"CMD_SPRING")


func configure_spring_trajectory_torque(
	launch_direction: Vector3,
	enabled: bool,
	minimum_downward_angle_deg: float,
	align_speed_deg: float,
	gravity_yaw_enabled: bool = true,
	gravity_yaw_strength: float = 1.0,
	gravity_yaw_safe_angle_deg: float = 3.0,
	gravity_yaw_full_angle_deg: float = 90.0,
	minimum_horizontal_speed: float = 2.0,
	landing_forward_pitch_enabled: bool = true
) -> bool:
	var p = _owner
	stop_airborne_trajectory_torque()
	if not enabled:
		return false

	var up: Vector3 = p._get_gravity_up()
	var direction: Vector3 = launch_direction.normalized()
	if direction.length() < 0.001:
		return false

	var launch_angle_deg: float = rad_to_deg(acos(clamp(direction.dot(up), -1.0, 1.0)))
	var threshold_deg: float = clamp(minimum_downward_angle_deg, 0.0, 180.0)
	if launch_angle_deg < threshold_deg:
		return false

	return start_airborne_trajectory_torque(
		direction,
		align_speed_deg,
		gravity_yaw_enabled,
		gravity_yaw_strength,
		gravity_yaw_safe_angle_deg,
		gravity_yaw_full_angle_deg,
		minimum_horizontal_speed,
		landing_forward_pitch_enabled
	)


func start_airborne_trajectory_torque(
	trajectory_direction: Vector3,
	align_speed_deg: float,
	gravity_yaw_enabled: bool = true,
	gravity_yaw_strength: float = 1.0,
	gravity_yaw_safe_angle_deg: float = 3.0,
	gravity_yaw_full_angle_deg: float = 90.0,
	minimum_horizontal_speed: float = 2.0,
	landing_forward_pitch_enabled: bool = true
) -> bool:
	var p = _owner
	stop_airborne_trajectory_torque()
	if p.attached or not p.airborne_torque_enabled:
		return false

	var direction: Vector3 = trajectory_direction.normalized()
	if direction.length() < 0.001:
		return false

	p._air_torque_trajectory_up = direction
	p._spring_trajectory_torque_align_speed_deg = max(align_speed_deg, 0.0)
	p._spring_trajectory_gravity_yaw_enabled = gravity_yaw_enabled
	p._spring_trajectory_gravity_yaw_strength = max(gravity_yaw_strength, 0.0)
	p._spring_trajectory_gravity_yaw_safe_angle_deg = clamp(gravity_yaw_safe_angle_deg, 0.0, 179.9)
	p._spring_trajectory_gravity_yaw_full_angle_deg = clamp(
		max(gravity_yaw_full_angle_deg, p._spring_trajectory_gravity_yaw_safe_angle_deg + 0.001),
		p._spring_trajectory_gravity_yaw_safe_angle_deg + 0.001,
		180.0
	)
	p._spring_trajectory_torque_min_horizontal_speed = max(minimum_horizontal_speed, 0.0)
	p._spring_trajectory_landing_forward_pitch_active = landing_forward_pitch_enabled
	p._spring_trajectory_torque_active = true
	p._air_torque_segment_allowed = true
	p._air_torque_airborne_time = 0.0
	p._air_torque_angular_velocity = Vector3.ZERO
	p._air_torque_rotation_accum = Vector3.ZERO
	p._manual_airborne_torque_active = false
	p._manual_airborne_torque_suppress_decay = false
	p._manual_airborne_torque_fast_decay = false
	p._air_trick_animation_gesture_latched = false
	p._air_trick_animation_last_command = &""
	p._external_airborne_torque_active = false
	p._set_manual_camera_lock(false)
	p._clear_air_torque_samples()
	p._clear_air_landing_align()
	return true


func stop_airborne_trajectory_torque(preserve_landing_forward_pitch: bool = false) -> void:
	var p = _owner
	p._spring_trajectory_torque_active = false
	if not preserve_landing_forward_pitch:
		p._spring_trajectory_landing_forward_pitch_active = false


func is_airborne_trajectory_torque_active() -> bool:
	var p = _owner
	return (
		p._spring_trajectory_torque_active
		and p._air_torque_segment_allowed
		and p.airborne_torque_enabled
		and not p.attached
	)


func get_airborne_trajectory_up() -> Vector3:
	var p = _owner
	if p.velocity.length() > 0.001:
		p._air_torque_trajectory_up = p.velocity.normalized()
	return p._air_torque_trajectory_up


func _cancel_spring_trajectory_torque(clear_spring_alignment: bool) -> void:
	var p = _owner
	if not p._spring_trajectory_torque_active:
		if clear_spring_alignment:
			p._spring_trajectory_landing_forward_pitch_active = false
		return
	stop_airborne_trajectory_torque(not clear_spring_alignment)
	if clear_spring_alignment:
		p._spring_align_timer = 0.0
		p._spring_align_up = Vector3.ZERO
		p._spring_align_forward = Vector3.ZERO
		p._spring_align_dir = Vector3.ZERO
		p._spring_lock_sideways = false
		p._spring_align_model = false
		p._spring_model_snap_timer = 0.0


func apply_dash_panel_impulse(
	panel_origin: Vector3,
	panel_dir: Vector3,
	strength: float,
	stop_momentum: bool,
	additive_mode: int,
	min_additive_launch_speed: float,
	movement_lock_time: float,
	action_lock_time: float,
	align_camera: bool,
	panel_basis: Basis,
	lock_speed_enabled: bool,
	lock_speed_value: float,
	lock_speed_duration: float,
	override_max_speed: bool = false,
	max_speed_override: float = 0.0,
	max_speed_override_duration: float = 0.0,
	match_y_position: bool = false,
	override_previous_lock_timers: bool = true
) -> void:
	var p = _owner
	var was_attached: bool = p.attached
	var previous_position: Vector3 = p.global_position
	var previous_surface_point: Vector3 = p.surface_point
	cancel_vault_bar()
	p._bounce_state = p.BounceState.NONE
	cancel_spline_spring()
	p.cancel_rail_grind(false)
	if override_previous_lock_timers:
		p.clear_object_lock_timers()

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
	p._automation_ignore_water_physics = false
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
	p._automation_expired_this_frame = false
	p._automation_priority_current = -9999
	p._automation_priority_frame = -1

	var active_action: Node = p._active_action
	var wall_run_result_value: Variant = {}
	if active_action != null and active_action.has_method("apply_dash_panel_parkour"):
		wall_run_result_value = active_action.call(
			"apply_dash_panel_parkour",
			panel_dir,
			strength,
			stop_momentum,
			additive_mode,
			min_additive_launch_speed,
			lock_speed_enabled,
			lock_speed_value,
			lock_speed_duration
		)
	else:
		var parkour_action: Node = p._get_action_by_id(&"parkour")
		if parkour_action != null and parkour_action.has_method("try_begin_from_dash_panel"):
			wall_run_result_value = parkour_action.call(
				"try_begin_from_dash_panel",
				panel_basis.y,
				panel_dir,
				strength,
				stop_momentum,
				additive_mode,
				min_additive_launch_speed,
				lock_speed_enabled,
				lock_speed_value,
				lock_speed_duration
			)
	if wall_run_result_value is Dictionary:
		var wall_run_result: Dictionary = wall_run_result_value
		if not wall_run_result.is_empty():
			p._dash_speed_lock_timer = 0.0
			if movement_lock_time > 0.0:
				p._spring_movement_lock_timer = max(p._spring_movement_lock_timer, movement_lock_time)
				p._spring_clear_move_on_ground = false
			if action_lock_time > 0.0:
				p._spring_action_lock_timer = max(p._spring_action_lock_timer, action_lock_time)
				p._spring_clear_action_on_ground = false
			if align_camera and p.camera_rig != null and p.camera_rig.has_method("align_to_direction"):
				if not (p.camera_rig.has_method("is_constraint_active") and p.camera_rig.is_constraint_active()):
					var wall_up: Vector3 = wall_run_result.get("up", Vector3.UP)
					var camera_direction: Vector3 = wall_run_result.get("direction", Vector3.ZERO)
					camera_direction = camera_direction.slide(wall_up).normalized()
					if camera_direction.length_squared() > 0.001:
						p.camera_rig.align_to_direction(camera_direction, wall_up)
			if override_max_speed:
				set_timed_max_speed_override(max_speed_override, max_speed_override_duration)
			p.reset_flight_timer_to_max()
			p._sync_spring_state_to_action()
			return

	var up: Vector3 = p.surface_normal.normalized() if was_attached else Vector3.ZERO
	if up.length() < 0.001:
		up = panel_basis.y.normalized()
	if up.length() < 0.001:
		up = p.up_direction.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	p.surface_normal = up
	p._prev_surface_normal = up
	p._smoothed_surface_normal = up
	p.up_direction = up
	p._attachment_immunity = 0.0

	var grounded_panel_position: Vector3 = panel_origin + up * p.collision_ground_distance
	var target_position: Vector3 = previous_position
	target_position.x = grounded_panel_position.x
	target_position.z = grounded_panel_position.z
	if match_y_position:
		target_position.y = grounded_panel_position.y
	var position_delta: Vector3 = target_position - previous_position
	var snap_result: Dictionary = _move_dash_panel_player(
		p,
		position_delta,
		up,
		was_attached and not match_y_position
	)
	var actual_position_delta: Vector3 = p.global_position - previous_position
	var contact_normal_value: Variant = snap_result.get("normal", Vector3.ZERO)
	var contact_normal: Vector3 = contact_normal_value if contact_normal_value is Vector3 else Vector3.ZERO
	contact_normal = contact_normal.normalized()
	if contact_normal.length() > 0.001:
		up = contact_normal
		p.surface_normal = up
		p._prev_surface_normal = up
		p._smoothed_surface_normal = up
		p.up_direction = up
	var contact_point_value: Variant = snap_result.get("point", Vector3.ZERO)
	if contact_normal.length() > 0.001 and contact_point_value is Vector3:
		p.surface_point = contact_point_value as Vector3
	elif was_attached and not match_y_position:
		p.surface_point = previous_surface_point + actual_position_delta
	else:
		p.surface_point = p.global_position - up * p.collision_ground_distance
	p._record_attach_state(p.surface_normal, p._get_gravity_up())

	var v: Vector3 = p.velocity
	var vertical: float = v.dot(up)
	var lateral: Vector3 = v - up * vertical

	var dash_dir: Vector3 = panel_dir - up * panel_dir.dot(up)
	if dash_dir.length() < 0.001:
		if lateral.length() > 0.001:
			dash_dir = lateral.normalized()
		else:
			dash_dir = (-Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up))
	if dash_dir.length() < 0.001:
		dash_dir = Vector3.FORWARD
	dash_dir = dash_dir.normalized()

	if stop_momentum:
		vertical = 0.0
		lateral = dash_dir * strength
	else:
		match additive_mode:
			0: # IgnorePriorVertical
				vertical = 0.0
				lateral += dash_dir * strength
			1: # FullyAdditiveWithMinLaunch
				var new_v: Vector3 = v + dash_dir * strength

				var new_vert: float = new_v.dot(up)
				new_v -= up * new_vert

				var along: float = new_v.dot(dash_dir)
				if along < min_additive_launch_speed:
					new_v += dash_dir * (min_additive_launch_speed - along)

				vertical = 0.0
				lateral = new_v

	p.velocity = lateral
	p.attached = true
	p._prev_attached = true
	p._is_jumping = false
	p._is_falling = false

	if movement_lock_time > 0.0:
		p._spring_movement_lock_timer = max(p._spring_movement_lock_timer, movement_lock_time)
		p._spring_clear_move_on_ground = false

	if action_lock_time > 0.0:
		p._spring_action_lock_timer = max(p._spring_action_lock_timer, action_lock_time)
		p._spring_clear_action_on_ground = false

	# Camera align
	if align_camera and p.camera_rig != null and p.camera_rig.has_method("align_to_direction"):
		if not (p.camera_rig.has_method("is_constraint_active") and p.camera_rig.is_constraint_active()):
			p.camera_rig.align_to_direction(dash_dir, up)

	if lock_speed_enabled and lock_speed_duration > 0.0 and lock_speed_value > 0.0:
		p._dash_speed_lock_timer = lock_speed_duration
		p._dash_speed_lock_speed = lock_speed_value
	if override_max_speed:
		set_timed_max_speed_override(max_speed_override, max_speed_override_duration)
	p.reset_flight_timer_to_max()
	p.end_active_flight_for_external_impulse({"reason": &"dash_panel_impulse"})
	p._sync_spring_state_to_action()


func _move_dash_panel_player(
	p,
	requested_motion: Vector3,
	surface_normal: Vector3,
	follow_surface_height: bool
) -> Dictionary:
	var result: Dictionary = {}
	var motion: Vector3 = requested_motion
	var support_normal: Vector3 = surface_normal.normalized()
	if follow_surface_height and support_normal.length() > 0.001:
		if abs(support_normal.y) > 0.2:
			motion.y = -(
				support_normal.x * motion.x
				+ support_normal.z * motion.z
			) / support_normal.y
		else:
			motion = motion.slide(support_normal)
	if motion.length() < 0.0001:
		return result

	var collision: KinematicCollision3D = p.move_and_collide(motion)
	var slide_iterations: int = 0
	while collision != null and slide_iterations < 2:
		var collision_normal: Vector3 = collision.get_normal().normalized()
		if (
			collision_normal.length() > 0.001
			and support_normal.length() > 0.001
			and collision_normal.dot(support_normal) > 0.25
		):
			result["normal"] = collision_normal
			result["point"] = collision.get_position()
			support_normal = collision_normal
		var remaining_motion: Vector3 = collision.get_remainder().slide(collision_normal)
		if remaining_motion.length() < 0.0001:
			break
		collision = p.move_and_collide(remaining_motion)
		slide_iterations += 1
	return result


func apply_ramp_impulse(
	ramp_origin: Vector3,
	ramp_forward: Vector3,
	ramp_up: Vector3,
	forward_speed: float,
	up_speed: float,
	additive_launch: bool,
	additive_min_forward_speed: float,
	movement_lock_time: float,
	action_lock_time: float,
	align_camera: bool,
	hold_forward_time: float,
	hold_up_time: float
) -> void:
	var p = _owner
	cancel_vault_bar()
	cancel_spline_spring()
	p.cancel_homing_attack(false)
	p._bounce_state = p.BounceState.NONE

	# Always detach.
	if p.attached:
		p._record_detach_state(p.surface_normal, p._get_gravity_up())
	p.attached = false
	p._attachment_immunity = p.launch_immunity_time
	p._airborne_time = 0.0
	p._is_skidding = false

	# This ramp does not use spring alignment/splines.
	p._spring_align_timer = 0.0
	p._spring_align_model = false
	p._spring_lock_sideways = false

	var up: Vector3 = ramp_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var fwd: Vector3 = ramp_forward - up * ramp_forward.dot(up)
	if fwd.length() < 0.001:
		fwd = -Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up)
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var forward_speed_used: float = max(forward_speed, 0.0)
	var up_speed_used: float = up_speed

	# Choose between absolute launch and additive launch.
	if additive_launch:
		# Only keep existing speed along the ramp's forward direction.
		var forward_along: float = p.velocity.dot(fwd)
		if forward_along < 0.0:
			forward_along = 0.0
		var final_forward_speed: float = forward_along + forward_speed_used
		var min_forward: float = max(additive_min_forward_speed, 0.0)
		if min_forward > 0.0 and final_forward_speed < min_forward:
			final_forward_speed = min_forward
		p.velocity = fwd * final_forward_speed + up * up_speed_used
	else:
		# Absolute impulse (not additive).
		p.velocity = fwd * forward_speed_used + up * up_speed_used

	# Encourage immediate facing toward the ramp direction.
	p._model_forward = fwd

	# Reuse spring timers for locking behavior.
	if movement_lock_time > 0.0:
		p._spring_movement_lock_timer = max(p._spring_movement_lock_timer, movement_lock_time)
		p._spring_clear_move_on_ground = true
	if action_lock_time > 0.0:
		p._spring_action_lock_timer = max(p._spring_action_lock_timer, action_lock_time)
		p._spring_clear_action_on_ground = true

	# Camera align
	if align_camera and p.camera_rig != null and p.camera_rig.has_method("align_to_direction"):
		if not (p.camera_rig.has_method("is_constraint_active") and p.camera_rig.is_constraint_active()):
			p.camera_rig.align_to_direction(fwd, up)

	# Optional continuous impulse holds.
	p._ramp_hold_forward_timer = max(hold_forward_time, 0.0)
	p._ramp_hold_up_timer = max(hold_up_time, 0.0)
	p._ramp_hold_forward_speed = max(p.velocity.dot(fwd), 0.0)
	p._ramp_hold_up_speed = up_speed_used
	p._ramp_hold_forward_dir = fwd
	p._ramp_hold_up_dir = up
	p.refresh_airborne_abilities()
	p.reset_flight_eligibility()
	if not p._spindash_charging:
		p._force_neutral_air_action({"reason": &"ramp_impulse"})
		p._skydive_anim_phase = p.SKYDIVE_ANIM_NONE
		p._skydive_anim_exit_timer = 0.0
		if p.anim_state != null:
			p.anim_state.travel(&"FallBlend")


func start_spline_spring(
	spline_path: Path3D,
	speed: float,
	align_model: bool,
	detach_from_ground: bool,
	allow_input_cancel: bool,
	action_lock_time: float = 0.0,
	world_offset: Vector3 = Vector3.ZERO,
	animation_command: StringName = &"CMD_SPRING",
	movement_lock_time: float = 0.0,
	clear_movement_lock_on_ground: bool = true,
	clear_action_lock_on_ground: bool = true
) -> void:
	var p = _owner
	cancel_spline_spring()
	p.cancel_homing_attack(false)
	if spline_path == null or spline_path.curve == null:
		return

	var curve: Curve3D = spline_path.curve
	var length: float = curve.get_baked_length()
	if length <= 0.001:
		return

	p._spline_path = spline_path
	p._spline_total_length = length
	p._spline_speed = speed
	p._spline_align_model = align_model
	p._spline_detach_from_ground = detach_from_ground
	p._spline_allow_input_cancel = allow_input_cancel
	p._spline_world_offset = world_offset
	p._spline_active = true
	p._update_jump_ball(0.0)
	p._is_jumping = false
	p._jump_variable = false
	p._jump_hang_allowed = false
	p._jump_time = 0.0
	# Treat spline springs like normal springs for jump-dash/anim resets.
	p.refresh_airborne_abilities()
	p._jump_dash_requested = false
	p._jump_dash_recent_timer = 0.0

	# Start at beginning of the path (offset 0). 
	# Closest-point start not implemented (uses path origin).
	p._spline_distance = 0.0
	# Snap model orientation immediately to the spline direction.
	if p._spline_align_model and p.model_root:
		var local_pos: Vector3 = curve.sample_baked(p._spline_distance)
		var ahead_dist: float = min(p._spline_distance + 0.1, p._spline_total_length)
		var local_pos_ahead: Vector3 = curve.sample_baked(ahead_dist)
		var world_pos: Vector3 = p._spline_path.to_global(local_pos) + p._spline_world_offset
		var world_pos_ahead: Vector3 = p._spline_path.to_global(local_pos_ahead) + p._spline_world_offset
		var tangent: Vector3 = (world_pos_ahead - world_pos).normalized()
		if tangent.length() < 0.001:
			tangent = Vector3.FORWARD

		var travel_dir: Vector3 = tangent * p._spline_speed
		if travel_dir.length() < 0.001:
			travel_dir = tangent
		var model_forward: Vector3 = travel_dir.normalized()
		var current_basis: Basis = p.model_root.global_transform.basis.orthonormalized()
		var transport_basis: Basis = _build_spline_transport_basis(
			model_forward,
			current_basis.y,
			current_basis.x
		)
		_store_spline_transport_basis(transport_basis)
		var basis: Basis = _apply_spline_model_pitch(transport_basis)
		p.model_root.global_transform = Transform3D(basis, p.model_root.global_transform.origin)
		p._model_forward = model_forward

	# Optional: detach from ground so adhesion doesn't fight the spline
	if detach_from_ground and p.attached:
		var world_up: Vector3 = p._get_gravity_up()
		p._record_detach_state(p.surface_normal, world_up, false)
		p.attached = false
		p._attachment_immunity = p.launch_immunity_time
		p._airborne_time = 0.0

	# Clear spring / skid state so nothing competes
	p._spring_align_timer = 0.0
	p._bounce_state = p.BounceState.NONE
	p._is_skidding = false

	if action_lock_time > 0.0:
		p._spring_action_lock_timer = max(p._spring_action_lock_timer, action_lock_time)
		p._spring_clear_action_on_ground = clear_action_lock_on_ground
	if movement_lock_time > 0.0:
		p._spring_movement_lock_timer = max(p._spring_movement_lock_timer, movement_lock_time)
		p._spring_clear_move_on_ground = clear_movement_lock_on_ground
	p.reset_flight_eligibility()
	p.end_active_flight_for_external_impulse({"reason": &"spline_spring"})

	if animation_command != &"":
		p._trigger_anim_command(animation_command)


func _update_spline_spring(delta: float) -> void:
	var p = _owner
	var path_value: Variant = p._spline_path
	if not p._spline_active or not is_instance_valid(path_value) or not (path_value is Path3D):
		cancel_spline_spring()
		return
	var spline_path: Path3D = path_value as Path3D
	if spline_path.curve == null:
		cancel_spline_spring()
		return

	var curve: Curve3D = spline_path.curve

	# Optional: allow cancelling with input
	if p._spline_allow_input_cancel and p._move_input.length() > 0.2:
		cancel_spline_spring()
		return

	# Advance along the spline
	p._spline_distance += p._spline_speed * delta

	# End of spline.
	if p._spline_distance >= p._spline_total_length:
		var runtime_arc: bool = spline_path.has_meta(&"runtime_trajectory_arc")
		if not runtime_arc:
			p._spline_active = false
			return
		var end_distance: float = p._spline_total_length
		var before_distance: float = max(end_distance - 0.1, 0.0)
		var end_local: Vector3 = curve.sample_baked(end_distance)
		var before_local: Vector3 = curve.sample_baked(before_distance)
		var end_world: Vector3 = spline_path.to_global(end_local) + p._spline_world_offset
		var before_world: Vector3 = spline_path.to_global(before_local) + p._spline_world_offset
		var exit_tangent: Vector3 = (end_world - before_world).normalized()
		if exit_tangent.length() < 0.001:
			exit_tangent = p.velocity.normalized()
		if exit_tangent.length() < 0.001:
			exit_tangent = Vector3.FORWARD
			if p.model_root:
				exit_tangent = -p.model_root.global_transform.basis.z
		var exit_speed: float = p._spline_speed
		p.global_position = end_world
		p.velocity = exit_tangent.normalized() * exit_speed
		cancel_spline_spring()
		p._refresh_carried_object_target_after_external_motion()
		return

	# Sample *local* positions on the curve
	var local_pos: Vector3 = curve.sample_baked(p._spline_distance)
	var behind_dist: float = max(p._spline_distance - 0.05, 0.0)
	var ahead_dist: float = min(p._spline_distance + 0.05, p._spline_total_length)
	var local_pos_behind: Vector3 = curve.sample_baked(behind_dist)
	var local_pos_ahead: Vector3 = curve.sample_baked(ahead_dist)

	# Convert to world space using the Path3D transform
	var world_pos: Vector3 = spline_path.to_global(local_pos) + p._spline_world_offset
	var world_pos_behind: Vector3 = spline_path.to_global(local_pos_behind) + p._spline_world_offset
	var world_pos_ahead: Vector3 = spline_path.to_global(local_pos_ahead) + p._spline_world_offset

	var tangent: Vector3 = (world_pos_ahead - world_pos_behind).normalized()
	if tangent.length() < 0.001:
		tangent = p._model_forward.normalized()
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD

	# Velocity in world space for collisions
	p.velocity = tangent * p._spline_speed

	# Place the player in world space
	p.global_position = world_pos

	# Optional: align model forward to travel direction so the head faces the trajectory.
	if p._spline_align_model and p.model_root:
		var travel_dir: Vector3 = p.velocity
		if travel_dir.length() < 0.001:
			travel_dir = tangent
		var model_forward: Vector3 = travel_dir.normalized()
		var current_basis: Basis = p.model_root.global_transform.basis.orthonormalized()
		var up_hint: Vector3 = _spline_transport_up if _spline_transport_valid else current_basis.y
		var right_hint: Vector3 = _spline_transport_right if _spline_transport_valid else current_basis.x
		var transport_basis: Basis = _build_spline_transport_basis(model_forward, up_hint, right_hint)
		_store_spline_transport_basis(transport_basis)
		var basis: Basis = _apply_spline_model_pitch(transport_basis)
		p.model_root.global_transform = Transform3D(basis, p.model_root.global_transform.origin)
		p._model_forward = model_forward
	p._refresh_carried_object_target_after_external_motion()


func _build_spline_model_basis(forward_dir: Vector3, up_hint: Vector3) -> Basis:
	var transport_basis: Basis = _build_spline_transport_basis(forward_dir, up_hint, Vector3.ZERO)
	return _apply_spline_model_pitch(transport_basis)


func _build_spline_transport_basis(
	forward_dir: Vector3,
	up_hint: Vector3,
	right_hint: Vector3
) -> Basis:
	var p = _owner
	var forward: Vector3 = forward_dir.normalized()
	if forward.length() < 0.001:
		forward = Vector3.FORWARD

	var up_ref: Vector3 = up_hint
	if up_ref.length() < 0.001:
		up_ref = p._get_gravity_up()
	up_ref = up_ref - forward * up_ref.dot(forward)
	if up_ref.length() < 0.001:
		var projected_right: Vector3 = right_hint - forward * right_hint.dot(forward)
		if projected_right.length() > 0.001:
			up_ref = projected_right.normalized().cross(forward)
		else:
			var gravity_up_ref: Vector3 = p._get_gravity_up()
			up_ref = gravity_up_ref - forward * forward.dot(gravity_up_ref)
			if up_ref.length() < 0.001:
				up_ref = Vector3.RIGHT - forward * forward.dot(Vector3.RIGHT)
	if up_ref.length() > 0.001:
		up_ref = up_ref.normalized()
	else:
		up_ref = p._get_gravity_up()

	var right: Vector3 = forward.cross(up_ref)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up_vec: Vector3 = right.cross(forward).normalized()

	var basis: Basis = Basis(right, up_vec, -forward).orthonormalized()
	return basis


func _apply_spline_model_pitch(transport_basis: Basis) -> Basis:
	var p = _owner
	var basis: Basis = transport_basis
	var pitch_rad: float = deg_to_rad(p.spline_model_pitch_deg)
	if abs(pitch_rad) > 0.0001:
		basis = basis.rotated(basis.x, -pitch_rad).orthonormalized()
	return basis


func _store_spline_transport_basis(transport_basis: Basis) -> void:
	_spline_transport_up = transport_basis.y.normalized()
	_spline_transport_right = transport_basis.x.normalized()
	_spline_transport_valid = true

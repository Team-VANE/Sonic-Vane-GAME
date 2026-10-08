# --------------------------------------------------------------------
# LICENSE/ATTRIBUTION
# This code is free and open to modify. You may use pieces of this code
# in your own projects. You may alter and use any of my custom assets
# as well, such as the "LS5E2HD" character model.
#
# Creator: Linksonic5
#
# Disclosure: Generative AI was used on math-heavy functions to help overcome
# the disability known as dyscalculia, a lack of ability to perceive
# and comprehend math concepts on a fundamental level.
# If you disagree with this practice, I would understand, and even agree with your dislike of AI.  However
# without its use, this game engine could not exist, and game development as a solo developer
# would remain inaccessible to me.
# VISUAL, AUDITORY, AND OTHER NON-CODE ASSETS IN THIS PROJECT WILL NEVER USE GENERATIVE AI.
#
# Date of creation: November 2025
# --------------------------------------------------------------------

extends "res://LS5Framework/Scripts/Player/PlayerControllerState.gd"
class_name PlayerController

const INVINCIBILITY_VISUAL_SCENE: PackedScene = preload(
	"res://LS5Framework/Scenes/Effects/InvincibilityVisual.tscn"
)

var _landing_prompt_sphere: SphereShape3D = SphereShape3D.new()

signal air_trick_boost_applied(score: float, speed_bonus: float, direction: Vector3, reason: StringName)

func clear_air_trick_bank() -> void:
	if _trick_system != null:
		_trick_system.clear_air_trick_bank()

func cash_out_air_trick_boost(direction: Vector3, reason: StringName) -> float:
	if _trick_system == null:
		return 0.0
	var score: float = _trick_system.air_trick_score
	var bonus: float = _trick_system.get_air_trick_speed_bonus()
	clear_air_trick_bank()
	if _is_dead or _hurt_active or _level_load_suspended or _is_buddy_actor():
		return 0.0
	if bonus <= 0.0 or direction.length_squared() < 0.000001:
		return 0.0
	var boost_direction: Vector3 = direction.normalized()
	var retained_speed: float = maxf(velocity.dot(boost_direction), 0.0)
	bonus = minf(bonus, retained_speed * clampf(_trick_system.air_trick_boost_retained_speed_limit, 0.0, 1.0))
	if bonus <= 0.0:
		return 0.0
	velocity += boost_direction * bonus
	air_trick_boost_applied.emit(score, bonus, boost_direction, reason)
	return bonus

func _cash_out_ground_air_trick_boost(normal: Vector3) -> float:
	var ground_normal: Vector3 = normal.normalized()
	if ground_normal.length_squared() < 0.000001:
		clear_air_trick_bank()
		return 0.0
	var direction: Vector3 = velocity.slide(ground_normal)
	var bonus: float = cash_out_air_trick_boost(direction, &"landing")
	if bonus > 0.0:
		_landing_animation_moving = true
	return bonus

func _resolve_air_trick_landing_boost(was_attached: bool) -> void:
	if attached and not was_attached and not _rail_active and not _spline_active:
		_cash_out_ground_air_trick_boost(surface_normal)

func _ensure_modules() -> void:
	if _audio_module == null:
		_audio_module = PlayerAudio.new(self)
	if _item_effects_module == null:
		_item_effects_module = PlayerItemEffects.new(self)
	if _anim_module == null:
		_anim_module = PlayerAnimation.new(self)
	if _model_module == null:
		_model_module = PlayerModel.new(self)
	if _ui_module == null:
		_ui_module = PlayerUI.new(self)
	if _network_module == null:
		_network_module = PlayerNetworkReplication.new(self)
	if _water_module == null:
		_water_module = PlayerWaterController.new(self)
	if _gravity_module == null:
		_gravity_module = PlayerGravityController.new(self)
	if _action_compatibility == null:
		_action_compatibility = PlayerActionCompatibility.new(self)
	if _targeting_module == null:
		_targeting_module = PlayerTargetingController.new(self)
	if _buddy_module == null:
		_buddy_module = PlayerBuddyController.new(self)
	if _effects_module == null:
		_effects_module = PlayerEffectsController.new(self)
	if _respawn_module == null:
		_respawn_module = PlayerRespawnController.new(self)
	if _rail_module == null:
		_rail_module = PlayerRailController.new(self)
	if _external_motion_module == null:
		_external_motion_module = PlayerExternalMotionController.new(self)
	if _debug_module == null:
		_debug_module = PlayerDebugController.new(self)
	if _carry_module == null:
		_carry_module = PlayerCarryController.new(self)
	if _combat_module == null:
		_combat_module = PlayerCombatController.new(self)
	if _surface_module == null:
		_surface_module = PlayerSurfaceController.new(self)
	if _movement_correction_module == null:
		_movement_correction_module = PlayerMovementCorrection.new(self)
	if _ability_input_router == null:
		_ability_input_router = PlayerAbilityInputRouter.new(self, character_settings_profile)

func _on_buddy_tree_exited(exited_buddy: Node = null) -> void:
	_ensure_modules()
	_buddy_module._on_buddy_tree_exited(exited_buddy)

func _clear_buddy_runtime_state() -> void:
	_ensure_modules()
	_buddy_module._clear_buddy_runtime_state()

func _on_trick_detected(trick_type: int, timer_add_seconds: float = -1.0) -> void:
	if _is_dead or _hurt_active or _level_load_suspended or _is_buddy_actor():
		return
	if is_parkour_active():
		return
	if is_current_action_flight():
		return
	var trick_name: String = _trick_system.get_trick_name(trick_type) if _trick_system != null else str(trick_type)
	push_warning("TRICK SIGNAL RECEIVED: %s" % trick_name)
	if _trick_system != null:
		_trick_system.register_trick(
			trick_type,
			Engine.get_process_frames() / 60.0,
			timer_add_seconds
		)
		if _trick_ui != null:
			_on_combo_updated(_trick_system.combo_multiplier, _trick_system.total_score)

func _on_combo_updated(_multiplier: float, score: float) -> void:
	if _is_buddy_actor():
		_disable_buddy_combo_system()
		return
	if _trick_ui != null and _trick_system != null:
		_trick_ui.set_combo_system_enabled(_trick_system.combo_system_enabled)
		if not _trick_system.combo_system_enabled:
			return
		var combo_entries: Array[String] = _trick_system.get_combo_list_entries()
		push_warning("Updating Trick UI: score=%f" % score)
		_trick_ui.update_combo_display(score, combo_entries)

func _on_combo_timer_updated(time_remaining: float, maximum_time: float) -> void:
	if _is_buddy_actor():
		_disable_buddy_combo_system()
		return
	if _trick_ui != null:
		_trick_ui.update_combo_timer(time_remaining, maximum_time)

func _complete_combo(final_score: float, combo_entries: Array[String]) -> void:
	if _trick_system == null or _is_buddy_actor():
		return
	if final_score > 0.0:
		play_landing_combo_voice(final_score)
		_update_score(int(final_score))
	if _trick_ui != null:
		_trick_ui.finish_combo(final_score, combo_entries)

func _complete_combo_result(completed_combo: Dictionary) -> float:
	if completed_combo.is_empty() or _is_buddy_actor():
		return 0.0
	var combo_entries: Array[String] = []
	var entries_value: Variant = completed_combo.get("entries", [])
	if entries_value is Array:
		for entry: Variant in entries_value:
			combo_entries.append(str(entry))
	var final_score: float = float(completed_combo.get("score", 0.0))
	_complete_combo(final_score, combo_entries)
	return final_score

func finish_active_combo() -> float:
	if _trick_system == null or _is_buddy_actor():
		return 0.0
	return _complete_combo_result(_trick_system.finish_combo())

func _on_combo_failed(final_score: float) -> void:
	if _is_buddy_actor() or _trick_system == null or _trick_ui == null:
		return
	_trick_ui.fail_combo(final_score, _trick_system.get_combo_list_entries())

func register_combo_feat(feat_id: StringName, display_name: String, base_score: float, timer_add_seconds: float = -1.0) -> void:
	if _is_dead or _trick_system == null or _is_buddy_actor():
		return
	var previous_entry_count: int = _trick_system.current_air_tricks.size()
	var resolved_display_name: String = display_name
	if character_visual_profile != null:
		resolved_display_name = character_visual_profile.get_feat_display_name(feat_id, display_name)
	_trick_system.register_feat(feat_id, resolved_display_name, base_score, timer_add_seconds)
	if _trick_system.current_air_tricks.size() <= previous_entry_count:
		return
	_on_combo_updated(_trick_system.combo_multiplier, _trick_system.total_score)
	_on_combo_timer_updated(
		_trick_system.combo_time_remaining,
		_trick_system.combo_timer_max_seconds
	)

func _on_trick_sequence_updated(trick_list: Array) -> void:
	pass

func _on_trick_performed(trick_type: int, _count: int) -> void:
	play_trick_voice(trick_type)

func _get_valid_buddy_instance() -> Node:
	_ensure_modules()
	return _buddy_module._get_valid_buddy_instance()

func _is_jump_held() -> bool:
	if not _network_is_local_authority():
		return false
	if _ui_input_blocked:
		return false
	if race_in_countdown:
		return false
	var jump_slot: StringName = get_ability_input_slot(&"jump", &"ability_slot_01")
	return SettingsManager.is_gameplay_action_pressed(String(jump_slot))


func _begin_jump_hold_state(variable_jump: bool) -> void:
	_jump_variable = variable_jump
	_is_jumping = variable_jump
	_jump_time = 0.0
	_jump_hang_allowed = variable_jump


func is_jump_launch_pending() -> bool:
	return _jump_requested


func _activate_jump_action_for_launch(reason: StringName) -> bool:
	if _jump_action == null or not is_instance_valid(_jump_action):
		return false
	if _active_action == _jump_action:
		return true
	return activate_action(_jump_action, {"reason": reason})


func _notify_buddy_leader_roll_changed(is_rolling: bool) -> void:
	_ensure_modules()
	_buddy_module._notify_buddy_leader_roll_changed(is_rolling)

func _notify_buddy_barrier_blast_sync() -> void:
	_ensure_modules()
	_buddy_module._notify_buddy_barrier_blast_sync()

func _notify_buddy_dynamic_mimic_ranges() -> void:
	_ensure_modules()
	_buddy_module._notify_buddy_dynamic_mimic_ranges()

func _notify_buddy_leader_jump_pressed() -> void:
	_ensure_modules()
	_buddy_module._notify_buddy_leader_jump_pressed()

func _notify_buddy_leader_jump_released() -> void:
	_ensure_modules()
	_buddy_module._notify_buddy_leader_jump_released()

func is_barrier_blast_active() -> bool:
	_ensure_modules()
	return _effects_module.is_barrier_blast_active()

func is_spindash_overcharge_blocking_external_barrier_blast_gain() -> bool:
	if _spindash_action == null or not is_instance_valid(_spindash_action):
		return false
	return _spindash_action.blocks_external_barrier_blast_gain()

func _get_hud_node() -> Node:
	_ensure_modules()
	if _ui_module != null:
		return _ui_module._get_hud_node()
	return null


func notify_landing_roll_speedometer_effect(
	result: StringName,
	strength: float
) -> void:
	if _is_buddy_actor() or not _network_is_local_authority():
		return
	var rig: Node = _resolve_camera_rig()
	if rig != null and rig.has_method("play_landing_feedback"):
		rig.call("play_landing_feedback", result, clamp(strength, 0.0, 1.0))
	var h: Node = _get_hud_node()
	if h != null and h.has_method("play_landing_roll_speedometer_effect"):
		h.call(
			"play_landing_roll_speedometer_effect",
			result,
			clamp(strength, 0.0, 1.0)
		)

func _set_special_gauge_ui(fraction: float) -> void:
	if _ui_module != null:
		_ui_module._set_special_gauge_ui(fraction)


func _set_ability_meter_ui(ability_name: String, current: float, max_value: float, available: bool) -> void:
	if _ui_module != null:
		_ui_module._set_ability_meter_ui(ability_name, current, max_value, available)


func _set_coyote_available_ui(_available: bool) -> void:
	if _ui_module == null:
		return
	var available: bool = _can_consume_coyote_jump()
	if not available and not _rail_active and not _rail_switch_active and not _spline_active:
		for action in _actions:
			if action is ParkourAbility and action.is_wall_kick_coyote_available():
				available = true
				break
	_ui_module._set_coyote_available_ui(available)

func _cancel_barrier_blast() -> void:
	_ensure_modules()
	_effects_module._cancel_barrier_blast()

func _update_barrier_blast(delta: float, world_up: Vector3, is_attached_for_movement: bool) -> void:
	_ensure_modules()
	_effects_module._update_barrier_blast(delta, world_up, is_attached_for_movement)

func _update_barrier_blast_sfx(speed: float, is_building: bool, reached_full: bool, delta: float = 0.0) -> void:
	_ensure_modules()
	_effects_module._update_barrier_blast_sfx(speed, is_building, reached_full, delta)

func _stop_barrier_blast_wind_sfx() -> void:
	_ensure_modules()
	_effects_module._stop_barrier_blast_wind_sfx()

func _update_puppet_barrier_blast_fx(delta: float) -> void:
	_ensure_modules()
	_effects_module._update_puppet_barrier_blast_fx(delta)

func _update_speed_wind_sfx() -> void:
	_ensure_modules()
	_effects_module._update_speed_wind_sfx()

func _ensure_sonic_boom_fx() -> void:
	_ensure_modules()
	_effects_module._ensure_sonic_boom_fx()

func _apply_sonic_boom_materials() -> void:
	_ensure_modules()
	_effects_module._apply_sonic_boom_materials()

func _update_sonic_boom_fx(delta: float) -> void:
	_ensure_modules()
	_effects_module._update_sonic_boom_fx(delta)

func _update_jump_dash_trail(delta: float) -> void:
	_ensure_modules()
	_effects_module._update_jump_dash_trail(delta)

func _update_jump_ball(delta: float) -> void:
	_ensure_modules()
	_effects_module._update_jump_ball(delta)

func _current_action_allows_jump_ball() -> bool:
	_ensure_modules()
	return _effects_module._current_action_allows_jump_ball()

func _set_sonic_boom_visibility(alpha: float, progress: float) -> void:
	_ensure_modules()
	_effects_module._set_sonic_boom_visibility(alpha, progress)

func _duplicate_sonic_boom_material(source: ShaderMaterial, shader: Shader) -> ShaderMaterial:
	_ensure_modules()
	return _effects_module._duplicate_sonic_boom_material(source, shader)

func _update_sonic_boom_orientation(delta: float) -> void:
	_ensure_modules()
	_effects_module._update_sonic_boom_orientation(delta)

func _network_is_active() -> bool:
	_ensure_modules()
	return _network_module.is_active()

func _network_is_local_authority() -> bool:
	_ensure_modules()
	return _network_module.is_local_authority()

func _network_configure_for_role() -> void:
	_ensure_modules()
	_network_module.configure_for_role()

func _network_puppet_tick(delta: float) -> void:
	_ensure_modules()
	_network_module.puppet_tick(delta)

func _network_send_state(delta: float) -> void:
	_ensure_modules()
	_network_module.capture_state(_movement_real_delta if _movement_tick_active else delta)


func _network_initialize_spawn_state(spawn_transform: Transform3D) -> void:
	_ensure_modules()
	_network_module.initialize_spawn_state(spawn_transform)


func _network_prepare_remote_scene_state(spawn_transform: Transform3D) -> void:
	_ensure_modules()
	_network_module.prepare_remote_scene_state(spawn_transform)


func _network_publish_teleport_state(target_peer_id: int = 0) -> void:
	_ensure_modules()
	_network_module.publish_teleport_state(target_peer_id)


func _network_request_authoritative_teleport() -> void:
	_ensure_modules()
	_network_module.request_authoritative_teleport()


func _network_get_state_sequence() -> int:
	_ensure_modules()
	return _network_module.get_state_sequence()


@rpc("any_peer", "reliable", "call_remote")
func _net_request_authoritative_teleport() -> void:
	_ensure_modules()
	_network_module.receive_authoritative_teleport_request()


@rpc("any_peer", "reliable", "call_remote")
func _net_authoritative_teleport(
		transform_value: Transform3D,
		velocity_value: Vector3,
		attached_value: bool,
		flags_value: int,
		main_state_value: int,
		visual_up_value: Vector3,
		model_basis_value: Basis,
		move_direction_value: Vector3,
		barrier_blast_gauge_value: float,
		action_id_value: StringName,
		state_sequence: int,
		animation_states: Dictionary,
		animation_values: Array,
		presentation_state: PackedFloat32Array
	) -> void:
	_ensure_modules()
	_network_module.receive_authoritative_teleport(
		transform_value,
		velocity_value,
		attached_value,
		flags_value,
		main_state_value,
		visual_up_value,
		model_basis_value,
		move_direction_value,
		barrier_blast_gauge_value,
		action_id_value,
		state_sequence,
		animation_states,
		animation_values,
		presentation_state
	)


func _network_set_visibility_filter(filter: Callable) -> void:
	_ensure_modules()
	_network_module.set_visibility_filter(filter)


func _network_refresh_visibility() -> void:
	_ensure_modules()
	_network_module.refresh_visibility()


func _network_set_level_presence(present: bool) -> void:
	_ensure_modules()
	_network_module.set_level_presence(present)

@rpc("any_peer", "reliable")
func _net_anim_command(command: StringName) -> void:
	_ensure_modules()
	_network_module.receive_animation_command(command)

func apply_debug_puppet_state(
	transform_value: Transform3D,
	velocity_value: Vector3,
	attached_value: bool,
	flags_value: int,
	main_state_value: int,
	visual_up_value: Vector3,
	model_basis_value: Basis,
	move_direction_value: Vector3,
	barrier_blast_gauge_value: float = 0.0,
	action_id_value: StringName = &""
) -> void:
	_ensure_modules()
	_network_module.apply_debug_puppet_state(
		transform_value,
		velocity_value,
		attached_value,
		flags_value,
		main_state_value,
		visual_up_value,
		model_basis_value,
		move_direction_value,
		barrier_blast_gauge_value,
		action_id_value
	)

@rpc("any_peer", "unreliable")
func _net_play_action_sfx(tag: String, index: int) -> void:
	_ensure_modules()
	_network_module.receive_action_sfx(tag, index)

@rpc("any_peer", "unreliable")
func _net_play_footstep_sfx(
	surface: int,
	index: int,
	volume_linear: float,
	foot: String,
	emit_dust: bool,
	water_index: int,
	water_volume: float
) -> void:
	_ensure_modules()
	_network_module.receive_footstep_sfx(
		surface,
		index,
		volume_linear,
		StringName(foot),
		emit_dust,
		water_index,
		water_volume
	)

# ===========================================================
# LIFECYCLE
# ===========================================================
func _ready() -> void:
	_reset_enemy_targeting_spawn_grace()
	_update_gravity_state(0.0)
	var initial_gravity_up: Vector3 = _get_gravity_up()
	up_direction = initial_gravity_up
	surface_normal = initial_gravity_up
	_prev_surface_normal = initial_gravity_up
	_smoothed_surface_normal = initial_gravity_up
	_last_attach_normal = initial_gravity_up
	_stable_attach_normal = initial_gravity_up
	_physics_up_last = initial_gravity_up
	_input_up_last = initial_gravity_up
	visual_up = initial_gravity_up
	_net_target_visual_up = initial_gravity_up
	_air_torque_prev_surface_normal = initial_gravity_up
	_air_torque_trajectory_up = initial_gravity_up
	_air_landing_align_normal = initial_gravity_up
	_water_surface_normal = initial_gravity_up
	_follow_normal = initial_gravity_up
	_functional_max_speed = max(max_speed, 0.0)
	randomize()
	_ensure_invincibility_visual()
	_cache_hurt_flash_renderers()
	var alignment_exclusion_mask: int = non_alignable_surface_mask | attack_pass_through_surface_mask
	collision_mask = collision_mask | alignment_exclusion_mask
	# Let the custom adhesion system handle what is 'walkable'.
	floor_max_angle = deg_to_rad(40.0)
	floor_block_on_wall = false
	floor_stop_on_slope = true
	# Disable built-in platform leave velocity. Godot's get_platform_velocity()
	# includes angular surface velocity (omega x r) from rotating RigidBody3D
	# contacts, which causes velocity spikes on spinning physics objects.
	# The custom platform carry system handles leave velocity for intentional platforms.
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING

	# Optionally make walls more “slidey” instead of sticky
	wall_min_slide_angle = 0.0
	floor_snap_length = 0.0

	# If unset, tie full-volume speed to run_top_speed
	if footstep_full_volume_speed <= 0.0:
		footstep_full_volume_speed = run_top_speed

	if ground_ray != null:
		ground_ray.exclude_parent = true
		ground_ray.collide_with_areas = false
		ground_ray.collision_mask = (
			ground_ray.collision_mask | WATER_SURFACE_RAY_LAYER
		) & ~alignment_exclusion_mask
		ground_ray.add_exception(self)

	_initial_transform = global_transform
	_net_target_transform = global_transform
	_net_target_velocity = velocity
	_net_target_attached = attached
	_net_target_state_flags = state_flags
	_net_target_main_state = main_state
	_net_target_visual_up = visual_up
	_net_target_move_direction = _move_direction
	_net_target_barrier_blast_gauge = clamp(_barrier_blast_gauge, 0.0, 1.0)
	_net_target_action_id = _current_action_id
	if model_root != null:
		_net_target_model_basis = model_root.global_transform.basis

	if not _net_saved_collision:
		_net_initial_collision_layer = collision_layer
		_net_initial_collision_mask = collision_mask
		_net_saved_collision = true

	_network_configure_for_role()
	_ensure_modules()
	_apply_character_visual_profile()
	_cache_default_character_effect_colors()
	_set_jump_ball_tint(_default_jump_ball_tint)

	if _network_is_local_authority() and not bool(get_meta(&"debug_online_dummy", false)):
		_ensure_debug_input_actions()
		_update_mouse_lock()
		_create_debug_hud()
		_init_actions()
		_set_special_gauge_ui(_barrier_blast_gauge)
		_update_ability_meter_ui()
		var h = _get_hud_node()
		if h != null and h.has_method("set_rings"):
			h.call("set_rings", rings)

	_ensure_name_tag()

	if anim_tree:
		# Route AnimationTree advance-expression evaluation to this player.
		# Many state-machine transitions call player methods/properties
		# (has_state, attached, _get_lateral_speed_for_anim, anim_state, etc.).
		# Without this, those expressions evaluate on the AnimationTree node,
		# causing transition stalls (for example trick -> FallBlend, and
		# To_Any_Grounded_State -> LAND/LAND_MOVING).
		anim_tree.advance_expression_base_node = anim_tree.get_path_to(self)
		anim_state = anim_tree.get(PlayerAnimation.SM_BASE + "/playback")
		ground_state = anim_tree.get(PlayerAnimation.SM_GROUND + "/playback")
		_carry_overlay_state = anim_tree.get(carry_overlay_playback_parameter) as AnimationNodeStateMachinePlayback
		_configure_carry_overlay_filter()
		_initialize_carry_overlay_animation()
		anim_tree.active = true
		#_dump_animtree_params()
		if anim_state == null:
			push_error("AnimationTree playback not found - check path '%s/playback'" % PlayerAnimation.SM_BASE)

		
		#_debug_anim_tree_params()

	_ensure_modules()
	_setup_water_detection()
	if buddy_enable and SettingsManager.buddy_active:
		call_deferred("spawn_selected_buddy")

func _setup_water_detection() -> void:
	_ensure_modules()
	_water_module.setup_detection()

func _on_water_area_entered(area: Area3D) -> void:
	_register_water_volume_entry(area)

func _on_water_area_exited(area: Area3D) -> void:
	_register_water_volume_exit(area)

func _register_water_volume_entry(collider: Node3D) -> void:
	_ensure_modules()
	_water_module.register_volume_entry(collider)

func _register_water_volume_exit(collider: Node3D) -> void:
	_ensure_modules()
	_water_module.register_volume_exit(collider)

func _on_head_water_body_entered(body: Node3D) -> void:
	_ensure_modules()
	_water_module.register_head_entry(body)

func _on_head_water_body_exited(body: Node3D) -> void:
	_ensure_modules()
	_water_module.register_head_exit(body)

func _on_head_water_area_entered(area: Area3D) -> void:
	_ensure_modules()
	_water_module.register_head_entry(area)

func _on_head_water_area_exited(area: Area3D) -> void:
	_ensure_modules()
	_water_module.register_head_exit(area)

func _notify_head_entered_water() -> void:
	_ensure_modules()
	_water_module.notify_head_entered_water()

func _notify_head_exited_water() -> void:
	_ensure_modules()
	_water_module.notify_head_exited_water()

func _connect_trick_signals() -> void:
	if _is_buddy_actor():
		_disable_buddy_combo_system()
		return
	if _trick_detector != null and _trick_system != null:
		var trick_detected_callable: Callable = Callable(self, "_on_trick_detected")
		if not _trick_detector.trick_detected.is_connected(trick_detected_callable):
			_trick_detector.trick_detected.connect(trick_detected_callable)
	if _trick_system != null and _trick_ui != null:
		var combo_updated_callable: Callable = Callable(self, "_on_combo_updated")
		if not _trick_system.combo_updated.is_connected(combo_updated_callable):
			_trick_system.combo_updated.connect(combo_updated_callable)
		var trick_sequence_callable: Callable = Callable(self, "_on_trick_sequence_updated")
		if not _trick_system.trick_sequence_updated.is_connected(trick_sequence_callable):
			_trick_system.trick_sequence_updated.connect(trick_sequence_callable)
		push_warning("Trick signals connected: detector=%s system=%s ui=%s" % [_trick_detector != null, _trick_system != null, _trick_ui != null])
	if _trick_system != null:
		var trick_performed_callable: Callable = Callable(self, "_on_trick_performed")
		if not _trick_system.trick_performed.is_connected(trick_performed_callable):
			_trick_system.trick_performed.connect(trick_performed_callable)
		var combo_failed_callable: Callable = Callable(self, "_on_combo_failed")
		if not _trick_system.combo_failed.is_connected(combo_failed_callable):
			_trick_system.combo_failed.connect(combo_failed_callable)
		if _trick_ui != null:
			var combo_timer_callable: Callable = Callable(self, "_on_combo_timer_updated")
			if not _trick_system.combo_timer_updated.is_connected(combo_timer_callable):
				_trick_system.combo_timer_updated.connect(combo_timer_callable)


func _create_debug_hud() -> void:
	_ensure_modules()
	_debug_module._create_debug_hud()

func _update_mouse_lock() -> void:
	_ensure_modules()
	_debug_module._update_mouse_lock()

func _handle_debug_enter_press() -> void:
	_ensure_modules()
	_debug_module._handle_debug_enter_press()

## Sends an explicit interaction request to nearby RaceStart nodes.
## This is a fallback for online sessions where the area node may miss input polling.
func _try_interact_with_race_start() -> bool:
	if _local_pause_enabled:
		return false
	if _ui_input_blocked:
		return false
	if _debug_mode:
		return false
	if get_tree() == null:
		return false
	var starts = get_tree().get_nodes_in_group("RaceStart")
	for start in starts:
		if start == null or not is_instance_valid(start):
			continue
		if not start.has_method("try_open_race_settings_menu_from_player"):
			continue
		var handled = start.call("try_open_race_settings_menu_from_player", self)
		if handled is bool and bool(handled):
			return true
	return false


## Sends an explicit interaction request to nearby Terminal nodes.
## This is a fallback for online sessions where the area node may miss input polling.
func _try_interact_with_terminal() -> bool:
	if _local_pause_enabled:
		return false
	if _ui_input_blocked:
		return false
	if _debug_mode:
		return false
	if get_tree() == null:
		return false
	var terminals = get_tree().get_nodes_in_group("Terminal")
	for terminal in terminals:
		if terminal == null or not is_instance_valid(terminal):
			continue
		if not terminal.has_method("try_open_terminal_menu_from_player"):
			continue
		var handled = terminal.call("try_open_terminal_menu_from_player", self)
		if handled is bool and bool(handled):
			return true
	return false


func is_carrying_object() -> bool:
	_ensure_modules()
	return _carry_module.is_carrying_object()


func get_jump_animation_mode() -> int:
	if is_carrying_object():
		return carry_jump_animation_mode
	return jump_animation_mode


func uses_fall_blend_for_jump_animation() -> bool:
	if get_jump_animation_mode() != JumpAnimationMode.FALL_BLEND:
		return false
	return _anim_param_exists("parameters/StateMachine/conditions/UseFallBlendForJump")


func _has_carried_object() -> bool:
	_ensure_modules()
	return _carry_module._has_carried_object()

func _process_carry_action_inputs() -> bool:
	_ensure_modules()
	return _carry_module._process_carry_action_inputs()

func _try_handle_carry_interact() -> bool:
	_ensure_modules()
	return _carry_module._try_handle_carry_interact()

func _try_pick_up_carryable() -> bool:
	_ensure_modules()
	return _carry_module._try_pick_up_carryable()

func _put_down_carried_object() -> void:
	_ensure_modules()
	_carry_module._put_down_carried_object()

func release_carried_object_from_put_down_animation() -> void:
	_ensure_modules()
	_carry_module.release_carried_object_from_put_down_animation()

func _clear_pending_carry_put_down() -> void:
	_ensure_modules()
	_carry_module._clear_pending_carry_put_down()

func _throw_carried_object() -> void:
	_ensure_modules()
	_carry_module._throw_carried_object()

func release_carried_object_from_throw_animation() -> void:
	_ensure_modules()
	_carry_module.release_carried_object_from_throw_animation()

func _get_carry_throw_release_velocity() -> Vector3:
	_ensure_modules()
	return _carry_module._get_carry_throw_release_velocity()

func _update_carried_object_target() -> void:
	_ensure_modules()
	_carry_module._update_carried_object_target()

func _refresh_carried_object_target_after_external_motion() -> void:
	_ensure_modules()
	_carry_module._refresh_carried_object_target_after_external_motion()

func _can_pick_up_carryable_now() -> bool:
	_ensure_modules()
	return _carry_module._can_pick_up_carryable_now()

func _can_execute_action_while_carrying(action: Node) -> bool:
	_ensure_modules()
	return _carry_module._can_execute_action_while_carrying(action)

func _clear_active_action_if_carry_blocked() -> void:
	_ensure_modules()
	_carry_module._clear_active_action_if_carry_blocked()

func _find_best_carryable_object() -> Node3D:
	_ensure_modules()
	return _carry_module._find_best_carryable_object()

func _can_reach_carryable_without_obstruction(carryable: Node3D, up: Vector3) -> bool:
	_ensure_modules()
	return _carry_module._can_reach_carryable_without_obstruction(carryable, up)

func _get_carry_pickup_radius(up: Vector3) -> float:
	_ensure_modules()
	return _carry_module._get_carry_pickup_radius(up)

func _should_throw_carried_object_from_interact() -> bool:
	_ensure_modules()
	return _carry_module._should_throw_carried_object_from_interact()

func _get_carry_target_transform() -> Transform3D:
	_ensure_modules()
	return _carry_module._get_carry_target_transform()

func _get_carry_fallback_target_transform() -> Transform3D:
	_ensure_modules()
	return _carry_module._get_carry_fallback_target_transform()

func _get_unscaled_carry_transform(source_transform: Transform3D) -> Transform3D:
	_ensure_modules()
	return _carry_module._get_unscaled_carry_transform(source_transform)

func _get_carry_bone_transform() -> Variant:
	_ensure_modules()
	return _carry_module._get_carry_bone_transform()

func _get_carry_skeleton() -> Skeleton3D:
	_ensure_modules()
	return _carry_module._get_carry_skeleton()

func _find_first_skeleton(root: Node) -> Skeleton3D:
	for child: Node in root.get_children():
		if child is Skeleton3D:
			return child as Skeleton3D
		var skeleton: Skeleton3D = _find_first_skeleton(child)
		if skeleton:
			return skeleton
	return null


func _get_carry_put_down_transform() -> Transform3D:
	_ensure_modules()
	return _carry_module._get_carry_put_down_transform()

func _get_safe_carry_put_down_transform(carryable: Node3D) -> Transform3D:
	_ensure_modules()
	return _carry_module._get_safe_carry_put_down_transform(carryable)

func _get_carry_put_down_candidate_positions(origin: Vector3, forward: Vector3, right: Vector3, up: Vector3) -> Array[Vector3]:
	_ensure_modules()
	return _carry_module._get_carry_put_down_candidate_positions(origin, forward, right, up)

func _is_carry_put_down_transform_safe(candidate_transform: Transform3D, carryable: Node3D, up: Vector3, world: World3D) -> bool:
	_ensure_modules()
	return _carry_module._is_carry_put_down_transform_safe(candidate_transform, carryable, up, world)

func _is_carry_put_down_body_motion_safe(candidate_transform: Transform3D, carryable: Node3D, up: Vector3) -> bool:
	_ensure_modules()
	return _carry_module._is_carry_put_down_body_motion_safe(candidate_transform, carryable, up)

func _carry_put_down_clearance_overlaps(position: Vector3, radius: float, carryable: Node3D, world: World3D) -> bool:
	_ensure_modules()
	return _carry_module._carry_put_down_clearance_overlaps(position, radius, carryable, world)

func _get_carry_put_down_query_excludes(carryable: Node3D) -> Array[RID]:
	_ensure_modules()
	return _carry_module._get_carry_put_down_query_excludes(carryable)

func _get_carry_up() -> Vector3:
	_ensure_modules()
	return _carry_module._get_carry_up()

func _get_carry_forward(up: Vector3) -> Vector3:
	_ensure_modules()
	return _carry_module._get_carry_forward(up)


func _reset_enemy_targeting_spawn_grace() -> void:
	_enemy_targeting_spawn_input_received = false
	var duration_msec: int = int(round(max(enemy_targeting_spawn_grace_sec, 0.0) * 1000.0))
	_enemy_targeting_spawn_grace_deadline_msec = Time.get_ticks_msec() + duration_msec


func _release_enemy_targeting_spawn_grace() -> void:
	_enemy_targeting_spawn_input_received = true


func is_enemy_targeting_suppressed() -> bool:
	if _enemy_targeting_spawn_input_received:
		return false
	return Time.get_ticks_msec() < _enemy_targeting_spawn_grace_deadline_msec


func _is_enemy_targeting_grace_release_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"move_left"):
		return true
	if event.is_action_pressed(&"move_right"):
		return true
	if event.is_action_pressed(&"move_forward"):
		return true
	if event.is_action_pressed(&"move_back"):
		return true
	if event.is_action_pressed(&"interact"):
		return true
	for slot_index: int in range(1, 17):
		var action_name: StringName = StringName("ability_slot_%02d" % slot_index)
		if event.is_action_pressed(action_name):
			return true
	return false


func _has_enemy_targeting_grace_release_action() -> bool:
	if SettingsManager.is_gameplay_action_just_pressed(&"interact"):
		return true
	for slot_index: int in range(1, 17):
		var action_name: StringName = StringName("ability_slot_%02d" % slot_index)
		if SettingsManager.is_gameplay_action_just_pressed(action_name):
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if not _network_is_local_authority():
		return
	if _ui_input_blocked:
		return
	if _post_ui_unblock_action_suppress_timer > 0.0:
		return
	if _local_pause_enabled:
		return
	if get_tree() != null and get_tree().paused:
		return
	if _is_enemy_targeting_grace_release_event(event):
		_release_enemy_targeting_spawn_grace()
	# --- DEBUG HUD TOGGLE ---
	# Option A: F12 (no echo, so it only fires once per key press)
	#if event is InputEventKey and not event.echo and event.keycode == Key.KEY_F12:
	#	_debug_visible = !_debug_visible
	#	if _debug_label:
	#		_debug_label.visible = _debug_visible
	#	return

	# Option B: custom input action "debug_toggle" (set in Input Map)
	if event.is_action_pressed("debug_toggle"):
		_debug_visible = !_debug_visible
		if _debug_hud:
			_debug_hud.visible = _debug_visible
		if _debug_label:
			_debug_label.visible = _debug_visible
		return
	if event.is_action_pressed("spawn_online_debug_puppet") and _debug_inputs_allowed():
		_toggle_online_debug_puppet()
		return

	if _debug_inputs_allowed():
		if event.is_action_pressed("debug_reload_level_in_place"):
			_debug_module.reload_level_in_place()
			return
		if event.is_action_pressed("debug_reload_player_parameters"):
			_reload_player_scene_parameters()
			return
		if event.is_action_pressed("debug_gravity_upside_down"):
			set_gravity_up(Vector3.DOWN)
			return
		if event.is_action_pressed("debug_gravity_normal"):
			set_gravity_up(Vector3.UP)
			return

	# --- DEBUG MODE TOGGLE / ANIM CYCLE ---
	if debug_mode_enabled and _debug_inputs_allowed():
		if event.is_action_pressed("debug_enter"):
			_handle_debug_enter_press()
			return
	if _debug_inputs_allowed() and (_debug_mode or (_debug_online_puppet != null and is_instance_valid(_debug_online_puppet))):
		if event.is_action_pressed("debug_next_anim"):
			_debug_cycle_animation(1)
			return
		if event.is_action_pressed("debug_prev_anim"):
			_debug_cycle_animation(-1)
			return

	# --- BUDDY SPAWN / DESPAWN ---
	if buddy_enable and _debug_inputs_allowed():
		if event.is_action_pressed("buddy_spawn"):
			_toggle_buddy()
			return

	# --- ONLINE / UI DEBUG ---
	if _debug_visible:
		var session_active: bool = false
		var session_id: int = 0
		if multiplayer != null and multiplayer.has_multiplayer_peer():
			session_active = true
			session_id = multiplayer.get_unique_id()
		
		_debug_label.text += "\n[ONLINE / UI]\n"
		_debug_label.text += "Session Active: %s (ID: %d)\n" % [session_active, session_id]
		_debug_label.text += "Local Auth: %s\n" % [_network_is_local_authority()]
		_debug_label.text += "UI Blocked: %s\n" % [_ui_input_blocked]
		_debug_label.text += "Camera Rig: %s\n" % [camera_rig != null]
		if camera_rig != null and camera_rig.has_method("is_constraint_active"):
			_debug_label.text += "Cam Constraint: %s\n" % [camera_rig.is_constraint_active()]

	# --- RACE INTERACT ---
	if event.is_action_pressed("interact"):
		_gracefully_end_airborne_torque()
		if _has_carried_object() and _try_handle_carry_interact():
			return
		if _try_interact_with_race_start():
			return
		if _try_interact_with_terminal():
			return
		_try_handle_carry_interact()
		return

	# --- OTHER HOTKEYS ---
	if event.is_action_pressed("toggle_mouse_lock"):
		lock_cursor_to_game = !lock_cursor_to_game
		_update_mouse_lock()
	elif event.is_action_pressed("unstuck"):
		unstuck_now()
	elif event.is_action_pressed("respawn") and not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		respawn_now()
	elif event.is_action_pressed("respawn_checkpoint") and not (event is InputEventJoypadButton or event is InputEventJoypadMotion) and _debug_inputs_allowed():
		respawn_checkpoint_now()

	if event is InputEventMouseMotion:
		_manual_airborne_mouse_delta += event.relative



func _respawn() -> void:
	_ensure_modules()
	_respawn_module._respawn()

func _respawn_to_checkpoint() -> void:
	_ensure_modules()
	_respawn_module._respawn_to_checkpoint()

func _apply_respawn_transform(
	target_transform: Transform3D,
	use_checkpoint_velocity: bool,
	force_grounded: bool = false,
	grounded_point: Vector3 = Vector3.ZERO,
	grounded_normal: Vector3 = Vector3.ZERO
) -> void:
	_ensure_modules()
	_respawn_module._apply_respawn_transform(target_transform, use_checkpoint_velocity, force_grounded, grounded_point, grounded_normal)
	_network_module.publish_teleport_state()

func _restart_animation_state_machine_for_respawn() -> void:
	_ensure_modules()
	_respawn_module._restart_animation_state_machine_for_respawn()

func _get_respawn_animation_start_node() -> StringName:
	_ensure_modules()
	return _respawn_module._get_respawn_animation_start_node()

func _get_main_animation_state_machine() -> AnimationNodeStateMachine:
	_ensure_modules()
	return _respawn_module._get_main_animation_state_machine()

func _get_respawn_ground_animation_start_node() -> StringName:
	_ensure_modules()
	return _respawn_module._get_respawn_ground_animation_start_node()

func _get_ground_animation_state_machine() -> AnimationNodeStateMachine:
	_ensure_modules()
	return _respawn_module._get_ground_animation_state_machine()

func _resolve_respawn_point() -> Node3D:
	_ensure_modules()
	return _respawn_module._resolve_respawn_point()

func _get_level_manager() -> Node:
	_ensure_modules()
	return _respawn_module._get_level_manager()

func activate_checkpoint(respawn_transform: Transform3D, respawn_speed: float, respawn_dir: Vector3) -> void:
	_ensure_modules()
	_respawn_module.activate_checkpoint(respawn_transform, respawn_speed, respawn_dir)

func activate_checkpoint_from(source: Node, respawn_transform: Transform3D, respawn_speed: float, respawn_dir: Vector3) -> void:
	_ensure_modules()
	_respawn_module.activate_checkpoint_from(source, respawn_transform, respawn_speed, respawn_dir)

func can_activate_checkpoint_source(source: Node) -> bool:
	_ensure_modules()
	return _respawn_module.can_activate_checkpoint_source(source)

func respawn_now() -> void:
	_ensure_modules()
	_respawn_module.respawn_now()

func respawn_checkpoint_now() -> void:
	_ensure_modules()
	_respawn_module.respawn_checkpoint_now()

func clear_checkpoint_data() -> void:
	_ensure_modules()
	_respawn_module.clear_checkpoint_data()

func reset_race_debug_usage() -> void:
	_ensure_modules()
	_respawn_module.reset_race_debug_usage()

func unstuck_now() -> void:
	_ensure_modules()
	_respawn_module.unstuck_now()

func _get_unstuck_nudge_dir() -> Vector3:
	_ensure_modules()
	return _respawn_module._get_unstuck_nudge_dir()

func _perform_unstuck_nudge() -> void:
	_ensure_modules()
	_respawn_module._perform_unstuck_nudge()

func stop_all_momentum_and_special_movement() -> void:
	_ensure_modules()
	_respawn_module.stop_all_momentum_and_special_movement()


func prepare_for_level_change() -> void:
	_ensure_modules()
	_respawn_module.stop_all_momentum_and_special_movement()
	_water_module.reset_for_level_change()
	_targeting_module.reset_for_level_change()
	_effects_module.reset_for_level_change()
	_ui_module.clear_prompt()
	_clear_action_input_requests()
	clear_active_action()

func reset_water_state_for_teleport() -> void:
	_ensure_modules()
	_water_module.reset_for_teleport()


func _notify_camera_teleport() -> void:
	_ensure_modules()
	_respawn_module._notify_camera_teleport()

func _update_drift_camera_rig(
	heading_dir: Vector3,
	active: bool,
	turn_speed_deg_per_sec: float,
	influence: float = 1.0
) -> void:
	if _is_buddy_actor() or not _network_is_local_authority():
		return
	var rig = camera_rig
	if rig == null and camera != null:
		rig = camera.get_parent()
	if rig == null or not rig.has_method("set_drift_camera_state"):
		if get_tree() != null:
			var rigs = get_tree().get_nodes_in_group("CameraRig")
			if rigs != null and rigs.size() > 0:
				rig = rigs[0]
	if rig != null and rig.has_method("set_drift_camera_state"):
		rig.call("set_drift_camera_state", active, heading_dir, turn_speed_deg_per_sec, influence)


func _ensure_debug_input_actions() -> void:
	_ensure_modules()
	_debug_module._ensure_debug_input_actions()

func _add_input_action_key(action_name: StringName, keycode_value: int) -> void:
	_ensure_modules()
	_debug_module._add_input_action_key(action_name, keycode_value)

func _toggle_online_debug_puppet() -> void:
	_ensure_modules()
	_debug_module._toggle_online_debug_puppet()

func _spawn_online_debug_puppet() -> void:
	_ensure_modules()
	_debug_module._spawn_online_debug_puppet()

func _sync_online_debug_puppet(delta: float) -> void:
	_ensure_modules()
	_debug_module._sync_online_debug_puppet(_movement_real_delta if _movement_tick_active else delta)

func _debug_inputs_allowed() -> bool:
	_ensure_modules()
	return _debug_module._debug_inputs_allowed()


func _reload_player_scene_parameters() -> void:
	_ensure_modules()
	_debug_module.reload_player_scene_parameters()


func _reload_action_configuration_from_scene() -> void:
	_ensure_modules()
	if _active_action != null and is_instance_valid(_active_action):
		clear_active_action()
	if _ability_input_router != null:
		_ability_input_router.set_profile(character_settings_profile)
	_init_actions()


func _reload_visual_configuration_from_scene() -> void:
	_ensure_modules()
	_clear_character_tint_overrides()
	_apply_character_visual_profile()
	if SettingsManager.use_character_colors:
		set_character_colors(
			SettingsManager.character_primary_color,
			SettingsManager.character_secondary_color,
			SettingsManager.character_trail_color
		)
	else:
		clear_character_colors()


func _set_debug_mode(enabled: bool) -> void:
	_ensure_modules()
	_debug_module._set_debug_mode(enabled)

func _debug_refresh_animation_list() -> void:
	_ensure_modules()
	_debug_module._debug_refresh_animation_list()

func _invalidate_race_ghost_recording() -> void:
	_ensure_modules()
	_debug_module._invalidate_race_ghost_recording()

func _report_race_debug_used_to_network_session() -> void:
	_ensure_modules()
	_debug_module._report_race_debug_used_to_network_session()

func _debug_cycle_animation(step: int) -> void:
	_ensure_modules()
	_debug_module._debug_cycle_animation(step)

func _find_animation_player() -> AnimationPlayer:
	_ensure_modules()
	return _debug_module._find_animation_player()

func _toggle_buddy() -> void:
	_ensure_modules()
	_buddy_module._toggle_buddy()

func spawn_selected_buddy() -> bool:
	_ensure_modules()
	return _buddy_module.spawn_selected_buddy()

func set_buddy_character(character_id: String) -> bool:
	_ensure_modules()
	return _buddy_module.set_buddy_character(character_id)

func despawn_buddy() -> void:
	_ensure_modules()
	_buddy_module.despawn_buddy()

func _instantiate_buddy_character(character_id: String) -> Node:
	_ensure_modules()
	return _buddy_module._instantiate_buddy_character(character_id)

func _collect_scene_root_properties(source: Object) -> Dictionary:
	_ensure_modules()
	return _buddy_module._collect_scene_root_properties(source)

func _restore_scene_root_properties(target: Object, values: Dictionary) -> void:
	_ensure_modules()
	_buddy_module._restore_scene_root_properties(target, values)

func _should_skip_ai_overlay_property(property_name: StringName) -> bool:
	_ensure_modules()
	return _buddy_module._should_skip_ai_overlay_property(property_name)

func _copy_buddy_template_properties_to(target: Node) -> void:
	_ensure_modules()
	_buddy_module._copy_buddy_template_properties_to(target)

func _should_copy_buddy_template_property(property_name: StringName) -> bool:
	_ensure_modules()
	return _buddy_module._should_copy_buddy_template_property(property_name)

func _spawn_buddy_instance(inst: Node, character_id: String) -> void:
	_ensure_modules()
	_buddy_module._spawn_buddy_instance(inst, character_id)

func _debug_fly_tick(delta: float) -> void:
	_ensure_modules()
	_debug_module._debug_fly_tick(delta)

func set_display_name(value: String) -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module.set_display_name(value)

func set_display_color(value: Color) -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module.set_display_color(value)

func set_character_colors(primary_color: Color, secondary_color: Color, trail_color: Color = Color(0.2, 0.8, 1.0, 1.0)) -> void:
	_cache_default_character_effect_colors()
	_character_primary_color = primary_color
	_character_secondary_color = secondary_color
	_character_trail_color = trail_color
	character_tint_enabled = character_visual_profile.tint_enabled if character_visual_profile else true
	var boom_h: float = trail_color.h
	var boom_s: float = minf(trail_color.s, 0.8)
	var boom_v: float = 4.0
	sonic_boom_color = Color.from_hsv(boom_h, boom_s, boom_v, trail_color.a)
	if jump_dash_trail != null and jump_dash_trail.has_method("set_tint"):
		jump_dash_trail.call("set_tint", trail_color)
	_set_jump_ball_tint(trail_color)
	_apply_character_tint()


func clear_character_colors() -> void:
	_cache_default_character_effect_colors()
	character_tint_enabled = false
	if character_visual_profile:
		_character_primary_color = character_visual_profile.default_primary_color
		_character_secondary_color = character_visual_profile.default_secondary_color
	else:
		_character_primary_color = Color(0.18, 0.52, 1.0, 1.0)
		_character_secondary_color = Color(1.0, 1.0, 1.0, 1.0)
	_character_trail_color = _default_jump_dash_trail_tint
	sonic_boom_color = _default_sonic_boom_color
	if jump_dash_trail != null and jump_dash_trail.has_method("set_tint"):
		jump_dash_trail.call("set_tint", _default_jump_dash_trail_tint)
	_set_jump_ball_tint(_default_jump_ball_tint)
	_apply_character_tint()


func _cache_default_character_effect_colors() -> void:
	if _has_default_character_effect_colors:
		return
	_default_sonic_boom_color = sonic_boom_color
	if jump_dash_trail != null:
		var trail_tint: Variant = jump_dash_trail.get("tint")
		if trail_tint is Color:
			_default_jump_dash_trail_tint = trail_tint
	_default_jump_ball_tint = jump_ball_default_color
	if jump_ball != null:
		var ball_tint: Variant = jump_ball.get("tint")
		if ball_tint is Color:
			_default_jump_ball_tint = ball_tint
	_has_default_character_effect_colors = true


func _set_jump_ball_tint(color: Color) -> void:
	var tint_color: Color = color
	tint_color.a = jump_ball_default_color.a
	if jump_ball != null and jump_ball.has_method("set_tint"):
		jump_ball.call("set_tint", tint_color)


func _apply_character_visual_profile() -> void:
	if _trick_system != null:
		_trick_system.set_character_presentation_profile(character_visual_profile)
	if _trick_ui != null:
		_trick_ui.set_character_presentation_profile(character_visual_profile)
	if not character_visual_profile:
		return
	_character_primary_color = character_visual_profile.default_primary_color
	_character_secondary_color = character_visual_profile.default_secondary_color
	character_tint_enabled = character_visual_profile.tint_enabled
	character_hue_fallback_color = character_visual_profile.hue_fallback_color
	character_hue_overlay_strength = character_visual_profile.hue_overlay_strength
	character_hue_saturation_threshold = character_visual_profile.hue_saturation_threshold
	character_hue_saturation_softness = character_visual_profile.hue_saturation_softness
	character_hue_saturation_exponent = character_visual_profile.hue_saturation_exponent
	jump_ball_default_color = character_visual_profile.jump_ball_default_color


func _get_character_hue_target() -> float:
	var target: Color = _character_primary_color
	if not (target is Color):
		target = character_hue_fallback_color
	var hue_color: Color = target
	if target.s < 0.01:
		hue_color = character_hue_fallback_color
	return fposmod(hue_color.h, 1.0)

func _update_score(amount: int) -> void:
	if amount <= 0:
		return
	score += amount
	var h = _get_hud_node()
	if h != null and h.has_method("set_score"):
		h.call("set_score", score)


func add_score(amount: int) -> void:
	if not _network_is_local_authority():
		return
	_update_score(amount)


func add_rings(amount: int) -> void:
	if not _network_is_local_authority():
		return
	var a: int = int(amount)
	if a <= 0:
		return
	rings += a
	_update_rings_hud()


func add_item_resource(resource_id: StringName, amount: float) -> float:
	var current_amount: float = float(item_resources.get(resource_id, 0.0))
	if not _network_is_local_authority() or resource_id == &"" or is_zero_approx(amount):
		return current_amount
	var updated_amount: float = current_amount + amount
	item_resources[resource_id] = updated_amount
	item_resource_changed.emit(resource_id, current_amount, updated_amount)
	return updated_amount


func get_item_resource_amount(resource_id: StringName) -> float:
	return float(item_resources.get(resource_id, 0.0))


func play_item_collection_sound(item_id: StringName) -> bool:
	_ensure_modules()
	if _audio_module == null:
		return false
	return _audio_module.play_item_collection_sound(item_id)


func notify_item_collected(item_id: StringName, amount: float = 1.0) -> void:
	if not _network_is_local_authority() or item_id == &"":
		return
	item_collected.emit(item_id, amount)
	play_item_collection_sound(item_id)
	_ensure_modules()
	var effect_duration: float = _item_effects_module.get_effect_remaining(item_id)
	var h: Node = _get_hud_node()
	if h != null and h.has_method("show_item_notification"):
		h.call("show_item_notification", item_id, amount, effect_duration)


func apply_speed_shoes(duration_override: float = -1.0) -> bool:
	_ensure_modules()
	return _item_effects_module.apply_speed_shoes(duration_override)


func apply_invincibility(duration_override: float = -1.0) -> bool:
	_ensure_modules()
	return _item_effects_module.apply_invincibility(duration_override)


func is_invincibility_active() -> bool:
	_ensure_modules()
	return _item_effects_module.is_invincibility_active()


func _refresh_invincibility_visual(active: bool) -> void:
	var visual: InvincibilityVisual = _ensure_invincibility_visual()
	if visual != null:
		visual.set_effect_active(active)


func _ensure_invincibility_visual() -> InvincibilityVisual:
	var visual: InvincibilityVisual = get_node_or_null("InvincibilityVisual") as InvincibilityVisual
	if visual != null:
		return visual
	visual = INVINCIBILITY_VISUAL_SCENE.instantiate() as InvincibilityVisual
	if visual == null:
		return null
	add_child(visual)
	visual.set_effect_active(false)
	return visual


func is_speed_shoes_active() -> bool:
	_ensure_modules()
	return _item_effects_module.is_speed_shoes_active()


func get_speed_shoes_remaining() -> float:
	_ensure_modules()
	return _item_effects_module.get_speed_shoes_remaining()


func get_active_top_speed_multiplier() -> float:
	_ensure_modules()
	return _item_effects_module.get_active_top_speed_multiplier()


func _get_active_acceleration_curve(fallback_curve: Curve) -> Curve:
	_ensure_modules()
	return _item_effects_module.get_active_acceleration_curve(fallback_curve)


func _tick_speed_shoes(delta: float) -> void:
	_ensure_modules()
	_item_effects_module.tick(delta)


func _release_speed_shoes_music() -> void:
	if _item_effects_module != null:
		_item_effects_module.release_speed_shoes_music()


func remove_rings(amount: int) -> int:
	if not _network_is_local_authority():
		return 0
	var a: int = int(amount)
	if a <= 0 or rings <= 0:
		return 0
	var removed: int = min(a, rings)
	rings -= removed
	_update_rings_hud()
	return removed


func reset_rings() -> void:
	if not _network_is_local_authority():
		return
	rings = 0
	_update_rings_hud()


func reset_gameplay_run_state(reset_timer: bool = true) -> void:
	if not _network_is_local_authority():
		return
	_ensure_modules()
	_item_effects_module.clear_all_effects()
	reset_rings()
	reset_score()
	var h: Node = _get_hud_node()
	if h == null:
		return
	if reset_timer and h.has_method("set_elapsed_time"):
		h.call("set_elapsed_time", 0.0)
	if h.has_method("clear_item_notifications"):
		h.call("clear_item_notifications")


func reset_for_race_restart() -> void:
	reset_gameplay_run_state(true)


func _update_rings_hud() -> void:
	var h = _get_hud_node()
	if h != null and h.has_method("set_rings"):
		h.call("set_rings", rings)


func set_local_pause_enabled(value: bool) -> void:
	_local_pause_enabled = value
	if value:
		_move_input = Vector2.ZERO
		_move_direction = Vector3.ZERO


func set_level_load_suspended(value: bool) -> void:
	if _level_load_suspended == value:
		return
	_level_load_suspended = value
	if value:
		clear_air_trick_bank()
		_level_load_saved_collision_layer = collision_layer
		_level_load_saved_collision_mask = collision_mask
		_level_load_saved_process_enabled = is_processing()
		_level_load_saved_physics_process_enabled = is_physics_processing()
		_level_load_saved_input_enabled = is_processing_input()
		_level_load_saved_unhandled_input_enabled = is_processing_unhandled_input()
		_level_load_saved_unhandled_key_input_enabled = is_processing_unhandled_key_input()
		_move_input = Vector2.ZERO
		_move_direction = Vector3.ZERO
		_clear_action_input_requests()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		_stop_level_load_audio()
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process_unhandled_key_input(false)
		return
	collision_layer = _level_load_saved_collision_layer
	collision_mask = _level_load_saved_collision_mask
	set_process(_level_load_saved_process_enabled)
	set_physics_process(_level_load_saved_physics_process_enabled)
	set_process_input(_level_load_saved_input_enabled)
	set_process_unhandled_input(_level_load_saved_unhandled_input_enabled)
	set_process_unhandled_key_input(_level_load_saved_unhandled_key_input_enabled)


func _stop_level_load_audio() -> void:
	for audio_node: Node in find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	for audio_node: Node in find_children("*", "AudioStreamPlayer3D", true, false):
		(audio_node as AudioStreamPlayer3D).stop()


func set_ui_input_blocked(value: bool) -> void:
	_ui_input_legacy_blocked = value
	_refresh_ui_input_blocked()


func set_chat_input_blocked(value: bool) -> void:
	_chat_input_blocked = value
	_refresh_ui_input_blocked()


func _refresh_ui_input_blocked() -> void:
	var was_blocked: bool = _ui_input_blocked
	_ui_input_blocked = _ui_input_legacy_blocked or _chat_input_blocked or _is_chat_input_active()
	if _ui_input_blocked:
		_move_input = Vector2.ZERO
		_move_direction = Vector3.ZERO
		_clear_action_input_requests()
	elif was_blocked:
		_post_ui_unblock_action_suppress_timer = 0.08

func restore_input_after_pause() -> void:
	# Clear any residual UI-unblock suppression and ensure camera input unlocked after pause/resume.
	_post_ui_unblock_action_suppress_timer = 0.0
	_ui_input_legacy_blocked = false
	_refresh_ui_input_blocked()
	_set_manual_camera_lock(false)


func is_ui_input_blocked() -> bool:
	return _ui_input_blocked or _chat_input_blocked or _is_chat_input_active()


func _is_chat_input_active() -> bool:
	var tree: SceneTree = get_tree()
	return tree != null and tree.has_meta(&"chat_input_active") and bool(tree.get_meta(&"chat_input_active"))


func is_player_state_locked() -> bool:
	return _player_state_locked


func is_post_ui_action_suppressed() -> bool:
	return _post_ui_unblock_action_suppress_timer > 0.0


func _ensure_name_tag() -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module._ensure_name_tag()


func show_chat_bubble(message: String) -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module.show_chat_bubble(message)


func show_prompt(message: String, duration: float) -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module.show_prompt(message, duration)


func clear_prompt() -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module.clear_prompt()


func teleport_near_node(target: Node3D, offset: Vector3 = Vector3(0.0, 1.0, 0.0)) -> void:
	if not _network_is_local_authority():
		return
	if target == null or not is_instance_valid(target):
		return
	var t: Transform3D = global_transform
	t.origin = target.global_position + offset
	_apply_respawn_transform(t, false)
	stop_all_momentum_and_special_movement()


func leave_race(from_respawn: bool) -> void:
	if not _network_is_local_authority():
		return
	var was_racing: bool = race_session_joined or race_active or race_in_countdown or race_finished
	race_session_joined = false
	race_active = false
	race_in_countdown = false
	race_finished = false
	clear_gravity_state(&"race_cleanup", true)
	_cancel_local_race_start_countdown()
	var session: Node = get_tree().get_first_node_in_group("NetworkSession") if get_tree() else null
	if session and session.has_method("leave_race"):
		session.call("leave_race", from_respawn)
	if was_racing:
		_restore_autoplay_music()
	_cleanup_race_ui_local()
	_unlock_local_camera_constraints()
	set_ui_input_blocked(false)
	lock_cursor_to_game = true
	_update_mouse_lock()
	if hud and hud.has_method("set_timer_running"):
		hud.call("set_timer_running", true)


func force_leave_race_for_scene_change() -> void:
	# Clears any race/queue state before scene transitions.
	if not _network_is_local_authority():
		return
	reset_gameplay_run_state(true)
	clear_gravity_state(&"level_restart", true)
	if _network_is_active():
		var session = null
		if get_tree() != null and get_tree().current_scene != null:
			session = get_tree().current_scene.get_node_or_null("NetworkSession")
		if session != null and session.has_method("leave_race"):
			session.call("leave_race", false)
	race_session_joined = false
	race_active = false
	race_in_countdown = false
	race_finished = false
	_cancel_local_race_start_countdown()
	_restore_autoplay_music()
	set_ui_input_blocked(false)
	_cleanup_race_ui_local()
	_unlock_local_camera_constraints()


func _cleanup_race_ui_local() -> void:
	if get_tree() == null:
		return
	for n in get_tree().get_nodes_in_group("RaceUI") + get_tree().get_nodes_in_group("RaceFinishBanner") + get_tree().get_nodes_in_group("RaceDNFBanner"):
		if n != null and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("RaceQueueBanner"):
		if n != null and is_instance_valid(n):
			n.queue_free()


func _restore_autoplay_music() -> void:
	if get_tree() == null:
		return
	var controllers: Array[Node] = get_tree().get_nodes_in_group("MusicControllers")
	var autoplay_controller: MusicController = null
	var fallback: MusicController = null
	for node in controllers:
		if node is MusicController:
			var mc: MusicController = node
			if fallback == null:
				fallback = mc
			if mc.autoplay_stream != null and mc.autoplay:
				autoplay_controller = mc
				break
	if autoplay_controller == null:
		autoplay_controller = fallback
	var fade_out: float = 0.5
	if autoplay_controller != null and autoplay_controller.has_method("get"):
		var v = autoplay_controller.get("autoplay_fade_out")
		if v is float:
			fade_out = float(v)
	for node in controllers:
		if node is MusicController:
			(node as MusicController).stop_music(fade_out)
	if autoplay_controller == null:
		return
	if autoplay_controller.has_method("play_autoplay"):
		autoplay_controller.play_autoplay(true, -1.0, fade_out)
	elif autoplay_controller.autoplay_stream != null:
		autoplay_controller.play_music(autoplay_controller.autoplay_stream, autoplay_controller.autoplay_fade_in, fade_out, true)
	for n in get_tree().get_nodes_in_group("RaceFinishBanner"):
		if n != null and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("RaceDNFBanner"):
		if n != null and is_instance_valid(n):
			n.queue_free()


func _resolve_camera_rig() -> Node:
	if _is_buddy_actor():
		return null
	var rig: Node = null
	if camera_rig != null and is_instance_valid(camera_rig):
		rig = camera_rig
	elif camera != null and is_instance_valid(camera):
		rig = camera.get_parent()
	if (rig == null or not is_instance_valid(rig)) and get_tree() != null:
		var rigs = get_tree().get_nodes_in_group("CameraRig")
		if rigs != null and rigs.size() > 0:
			rig = rigs[0]
	return rig


func _set_manual_camera_lock(active: bool) -> void:
	if _is_buddy_actor() or not _network_is_local_authority():
		return
	var rig = _resolve_camera_rig()
	if rig == null:
		return
	var controller_trick_input: bool = active and SettingsManager.is_controller_input_active()
	var right_stick_tricks: bool = (
		controller_trick_input
		and SettingsManager.trick_control_stick == SettingsManager.TRICK_CONTROL_STICK_RIGHT
	)
	var lock_manual_input: bool = active and (not controller_trick_input or right_stick_tricks)
	if rig.has_method("set_manual_input_lock"):
		rig.call("set_manual_input_lock", lock_manual_input, right_stick_tricks)
	elif "manual_input_locked" in rig:
		rig.manual_input_locked = lock_manual_input
	
func _unlock_local_camera_constraints() -> void:
	if _is_buddy_actor() or not _network_is_local_authority():
		return
	var rig = _resolve_camera_rig()
	if rig != null:
		if rig.has_method("reset_camera_effects"):
			rig.call("reset_camera_effects", true)
		elif rig.has_method("clear_camera_constraints"):
			rig.call("clear_camera_constraints", null, true)


func _cancel_local_race_start_countdown() -> void:
	# If we're in a race start countdown (queue setup), cancel it locally so controls restore immediately.
	if get_tree() == null:
		return
	for goal: Node in get_tree().get_nodes_in_group("RaceGoal"):
		if goal and goal.has_method("cancel_for_player"):
			goal.call("cancel_for_player", self)
	var starts = get_tree().get_nodes_in_group("RaceStart")
	for s in starts:
		if s != null and is_instance_valid(s) and s.has_method("cancel_for_player"):
			s.call("cancel_for_player", self)

func _tick_ui(delta: float) -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module._tick_ui(delta)
	_set_coyote_available_ui(false)


func refresh_pause_preview_ui() -> void:
	_ensure_modules()
	if _ui_module != null:
		_ui_module._update_center_reticle()


func set_combo_ui_pause_hidden(hidden: bool) -> void:
	if _trick_ui != null:
		_trick_ui.set_pause_hidden(hidden)


func get_up_vector() -> Vector3:
	return visual_up


func is_rail_camera_alignment_active() -> bool:
	return _rail_active or _rail_switch_active


func get_camera_up_vector() -> Vector3:
	if is_rail_camera_alignment_active():
		return visual_up.normalized() if visual_up.length_squared() >= 0.001 else _get_gravity_up()
	if attached and surface_normal.length_squared() >= 0.001:
		if standing_collision_shape:
			return get_collision_support_up()
		return surface_normal.normalized()
	return _get_gravity_up()


func get_collision_support_up() -> Vector3:
	if attached:
		if _has_moving_collision_support():
			return (_collision_support_body.global_basis.inverse().transposed() * _collision_support_local_normal).normalized()
		if _collision_support_normal.length_squared() > 0.001:
			return _collision_support_normal.normalized()
		if surface_normal.length_squared() > 0.001:
			return surface_normal.normalized()
	return _get_gravity_up()


func _has_moving_collision_support() -> bool:
	return (
		attached
		and is_instance_valid(_collision_support_body)
		and _collision_support_body.is_inside_tree()
		and _collision_support_body == _follow_collider_last
		and _collision_support_shape == _follow_collider_shape_last
		and _collision_support_local_normal.length_squared() > 0.001
		and (
			_collision_support_body is RigidBody3D
			or _collision_support_body is AnimatableBody3D
			or _collision_support_body.has_method("get_platform_velocity")
		)
	)


func _capture_collision_support() -> void:
	_collision_support_body = null
	_collision_support_shape = -1
	if not attached or not _follow_hit or not is_instance_valid(_follow_collider_last):
		return
	if not (_follow_collider_last is PhysicsBody3D):
		return
	_collision_support_body = _follow_collider_last as PhysicsBody3D
	_collision_support_shape = _follow_collider_shape_last
	_collision_support_local_normal = _collision_support_body.global_basis.transposed() * _collision_support_normal
	_collision_support_local_point = _collision_support_body.to_local(_follow_point)


func _get_collision_support_velocity() -> Vector3:
	if not _has_moving_collision_support():
		return Vector3.ZERO
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(_collision_support_body.get_rid())
	if state:
		var point: Vector3 = _collision_support_body.to_global(_collision_support_local_point)
		return state.get_velocity_at_local_position(point - state.transform.origin)
	return Vector3.ZERO


func _refresh_moving_collision_support() -> void:
	if not _has_moving_collision_support() or not _ensure_main_sphere_configured():
		return
	var up: Vector3 = get_collision_support_up()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		get_main_collision_world_center(),
		get_main_collision_world_center() - up * maxf(ground_ray_length, get_main_collision_world_radius() + safe_margin)
	)
	query.collision_mask = collision_mask
	query.exclude = _make_shape_query(main_collision_shape.shape, global_transform).exclude
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != _collision_support_body or int(hit.shape) != _collision_support_shape:
		_collision_support_body = null
		return
	var normal: Vector3 = hit.normal
	_collision_support_normal = normal
	_collision_support_local_normal = _collision_support_body.global_basis.transposed() * normal
	_collision_support_local_point = _collision_support_body.to_local(hit.position)


func _reset_standing_clearance_state() -> void:
	_standing_clearance_latched = false
	_standing_clearance_clear_time = 0.0
	_standing_clearance_sample_frame = -1
	_collision_support_body = null
	_collision_support_shape = -1


func _record_standing_clearance(clear: bool) -> bool:
	if not clear:
		_standing_clearance_latched = true
		_standing_clearance_clear_time = 0.0
	return clear and (not _standing_clearance_latched or standing_clearance_release_time <= 0.0)


func _advance_standing_clearance_release(delta: float) -> void:
	if not standing_collision_shape or not standing_collision_shape.shape:
		return
	if not attached:
		_reset_standing_clearance_state()
		return
	var frame: int = Engine.get_physics_frames()
	if frame == _standing_clearance_sample_frame:
		return
	_standing_clearance_sample_frame = frame
	_refresh_moving_collision_support()
	if not _has_standing_clearance():
		_record_standing_clearance(false)
	elif _standing_clearance_latched:
		if not _can_expand_collision():
			_standing_clearance_clear_time = 0.0
			return
		_standing_clearance_clear_time += maxf(delta, 0.0)
		if _standing_clearance_clear_time + 0.000001 >= standing_clearance_release_time:
			_standing_clearance_latched = false
			_standing_clearance_clear_time = 0.0


func get_player_velocity() -> Vector3:
	return velocity


## Grounded camera motion aligned to collision support, excluding static-surface position corrections.
func get_camera_tracking_velocity() -> Variant:
	if (
		attached
		and not is_rail_camera_alignment_active()
		and is_instance_valid(_follow_collider_last)
		and _follow_collider_last is StaticBody3D
		and not (_follow_collider_last is AnimatableBody3D)
	):
		var surface_body: StaticBody3D = _follow_collider_last as StaticBody3D
		if (
			not surface_body.has_method("get_platform_velocity")
			and surface_body.constant_linear_velocity.is_zero_approx()
			and surface_body.constant_angular_velocity.is_zero_approx()
		):
			var movement_up: Vector3 = surface_normal.normalized()
			var movement_velocity: Vector3 = get_world_movement_velocity()
			if movement_up.length_squared() < 0.001:
				return movement_velocity
			var support_rotation: Basis = PlayerMath.basis_from_to(movement_up, get_collision_support_up())
			return support_rotation * movement_velocity.slide(movement_up)
	return null


func get_camera_auto_follow_velocity() -> Vector3:
	if _spring_align_timer <= 0.0 or _spring_align_dir.length() < 0.001:
		return velocity
	var launch_direction: Vector3 = _spring_align_dir.normalized()
	var launch_speed: float = velocity.length()
	return launch_direction * launch_speed


func is_camera_auto_follow_direction_locked() -> bool:
	return _spring_align_timer > 0.0 and _spring_align_dir.length() >= 0.001


func get_camera_action_adjustment_state() -> Dictionary:
	if _active_action == null or not is_instance_valid(_active_action):
		return {}
	if not _active_action.has_method("get_camera_adjustment_state"):
		return {}
	var state_value: Variant = _active_action.call("get_camera_adjustment_state")
	if state_value is Dictionary:
		return state_value
	return {}


func request_parkour_wall_kick_camera_assist(
	launch_velocity: Vector3,
	outward_speed: float,
	kick_strength: float
) -> void:
	if _is_buddy_actor() or not _network_is_local_authority():
		return
	var rig: Node = _resolve_camera_rig()
	if rig != null and rig.has_method("request_parkour_wall_kick_assist"):
		rig.call(
			"request_parkour_wall_kick_assist",
			launch_velocity,
			outward_speed,
			kick_strength
		)


func get_move_direction() -> Vector3:
	return _move_direction

func is_wall_input_projection_active() -> bool:
	return _wall_input_projection_active

func is_wall_input_push_active() -> bool:
	return _wall_input_push_active

func get_wall_input_push_normal() -> Vector3:
	return _wall_input_push_normal

func get_wall_input_push_angle_deg() -> float:
	return _wall_input_push_angle_deg

func get_player_relative_horizontal_speed() -> float:
	return _horizontal_speed

func get_player_relative_vertical_speed() -> float:
	return _vertical_speed

func get_model_relative_horizontal_momentum() -> float:
	return _model_horizontal_momentum

func get_model_relative_vertical_momentum() -> float:
	return _model_vertical_momentum

func _process(delta: float) -> void:
	_tick_ui(delta)
	if _level_load_suspended:
		return
	_debug_module.update_day_night_scrub(delta)

	if _trick_system != null and _is_buddy_actor():
		_disable_buddy_combo_system()
	elif _trick_system != null:
		# Sync combo system enabled state from settings if not in a race (which can override it)
		var in_race: bool = (race_in_countdown or race_active) and not race_finished
		if not in_race:
			_trick_system.combo_system_enabled = SettingsManager.combo_system_enabled
		if _trick_ui != null:
			_trick_ui.set_combo_system_enabled(_trick_system.combo_system_enabled)
		var completed_combo: Dictionary = _trick_system.update_combo_timer(
			delta,
			velocity.length(),
			rolling or _current_action_id == &"roll"
		)
		if _trick_ui != null:
			_trick_ui.update_combo_timer(
				_trick_system.combo_time_remaining,
				_trick_system.combo_timer_max_seconds
			)
		if not completed_combo.is_empty():
			_complete_combo_result(completed_combo)
		

	if _race_debug_confirm_timer > 0.0:
		_race_debug_confirm_timer = max(_race_debug_confirm_timer - delta, 0.0)
		if _race_debug_confirm_timer <= 0.0:
			_race_debug_confirm_pending = false

	if _debug_visible:
		_debug_draw_control_anchor()


func _exit_tree() -> void:
	_release_speed_shoes_music()
	clear_gravity_state(&"all")
	if _ability_input_router != null:
		_ability_input_router.dispose()
		_ability_input_router = null
	if _ui_module != null:
		_ui_module._clear_speed_lines()
	if _debug_online_puppet != null and is_instance_valid(_debug_online_puppet):
		_debug_online_puppet.queue_free()
		_debug_online_puppet = null
	_set_manual_camera_lock(false)


func _apply_character_tint() -> void:
	_ensure_modules()
	if _model_module != null:
		_model_module._apply_character_tint()


func _clear_character_tint_overrides() -> void:
	_ensure_modules()
	if _model_module != null:
		_model_module._clear_character_tint_overrides()


func _collect_mesh_instances(node: Node, out: Array) -> void:
	_ensure_modules()
	if _model_module != null:
		_model_module._collect_mesh_instances(node, out)

	
## Returns the movement clock rate captured for the current physics tick.
func get_movement_time_scale() -> float:
	return _movement_tick_scale if _movement_tick_active else effective_movement_time_scale


## Returns whether a slowdown debuff overrides animation movement-clock exclusions.
func is_movement_time_scale_debuff_active() -> bool:
	if _movement_tick_active:
		return _movement_tick_debuff_active
	var water_slowdown: bool = water_physics_enabled and water_logic_speed_enabled and _water_logic_speed_current < 1.0 and not (_automation_active and _automation_ignore_water_physics)
	return (is_finite(movement_time_scale_debuff_multiplier) and movement_time_scale_debuff_multiplier < 1.0) or water_slowdown


## Converts world velocity into movement-clock units.
func world_to_movement_velocity(world_velocity: Vector3) -> Vector3:
	return world_velocity / get_movement_time_scale()


## Returns player velocity in world units per second.
func get_world_movement_velocity() -> Vector3:
	return velocity * get_movement_time_scale()


## Returns elapsed movement time for physics helpers outside the main update pipeline.
func get_movement_physics_delta() -> float:
	return get_physics_process_delta_time() * get_movement_time_scale()


## Converts real elapsed time into movement-clock time without changing gameplay timers.
func get_movement_delta(real_delta: float) -> float:
	return real_delta * get_movement_time_scale()


## Returns the real timer step during a movement tick, otherwise the supplied step.
func get_gameplay_timer_delta(fallback_delta: float) -> float:
	return _movement_real_delta if _movement_tick_active else fallback_delta


func _physics_process(delta: float) -> void:
	_movement_real_delta = delta
	_ensure_modules()
	if not _level_load_suspended and not _local_pause_enabled:
		_water_module.refresh_submersion_state()
		_water_module.update_logic_speed(delta)
	_movement_tick_scale = effective_movement_time_scale
	_movement_tick_debuff_active = is_movement_time_scale_debuff_active()
	_movement_tick_active = true
	_movement_physics_process(delta)
	_movement_tick_active = false


# Collision movement uses world velocity; gameplay retains movement-clock units.
func _move_with_movement_time_scale() -> void:
	_update_standing_collision()
	_movement_sphere_contact.clear()
	_movement_object_contact_handled = false
	var movement_start: Transform3D = global_transform
	_collision_attached_last_move = attached
	velocity *= _movement_tick_scale
	move_and_slide()
	velocity /= _movement_tick_scale
	_recover_missed_sphere_contact(movement_start)
	_process_object_collision_contacts()
	_refresh_surface_behavior_areas(movement_start.origin, true)


func _process_object_collision_contacts() -> void:
	for collision_index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(collision_index)
		if not collision:
			continue
		for contact_index: int in range(collision.get_collision_count()):
			if _resolve_object_collision_contact(
				collision.get_collider(contact_index),
				collision.get_normal(contact_index)
			):
				_movement_object_contact_handled = true
				return
	if not _movement_sphere_contact.is_empty():
		_movement_object_contact_handled = _resolve_object_collision_contact(
			instance_from_id(int(_movement_sphere_contact.collider_id)),
			_movement_sphere_contact.normal
		)


func _resolve_object_collision_contact(collider: Object, contact_normal: Vector3) -> bool:
	var contact_owner: Node = collider as Node
	while is_instance_valid(contact_owner):
		if contact_owner.has_method("resolve_player_collision_contact"):
			return contact_owner.call(
				"resolve_player_collision_contact", self, _pre_slide_velocity, contact_normal
			)
		contact_owner = contact_owner.get_parent()
	return false


func _recover_missed_sphere_contact(movement_start: Transform3D) -> void:
	if not _ensure_main_sphere_configured():
		return
	var motion: Vector3 = global_position - movement_start.origin
	var motion_length: float = motion.length()
	if motion_length < 0.001:
		return
	var sphere_start: Transform3D = movement_start * _main_sphere_last_transform
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsShapeQueryParameters3D = _make_shape_query(main_collision_shape.shape, sphere_start)
	var center_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		sphere_start.origin, sphere_start.origin + motion
	)
	center_ray.collision_mask = query.collision_mask
	center_ray.exclude = query.exclude
	center_ray.collide_with_areas = false
	center_ray.hit_back_faces = false
	var crossing: Dictionary = space.intersect_ray(center_ray)
	if get_slide_collision_count() and crossing.is_empty():
		var sphere_end: Transform3D = sphere_start
		sphere_end.origin += motion
		if _shape_has_clearance(main_collision_shape.shape, sphere_end):
			return
		if attached and _collision_attached_last_move and _has_shallow_ground_contacts(sphere_end):
			return
	query.motion = motion
	var fractions: PackedFloat32Array = space.cast_motion(query)
	var safe_fraction: float = 1.0
	var contact: Dictionary = {}
	if fractions.size() >= 2 and fractions[0] < 1.0:
		safe_fraction = fractions[0]
		query.motion = Vector3.ZERO
		query.transform.origin += motion * minf(fractions[1] + 0.001 / motion_length, 1.0)
		query.margin = 0.001
		contact = space.get_rest_info(query)
	if contact.is_empty() and not crossing.is_empty():
		var normal: Vector3 = crossing.normal
		var inward_motion: float = -motion.dot(normal)
		if inward_motion > 0.001:
			var radius: float = (main_collision_shape.shape as SphereShape3D).radius * sphere_start.basis.x.length()
			var support_distance: float = (sphere_start.origin - (crossing.position as Vector3)).dot(normal)
			safe_fraction = clampf((support_distance - radius - 0.001) / inward_motion, 0.0, 1.0)
			contact = {
				"normal": normal, "point": crossing.position, "rid": crossing.rid,
				"collider_id": crossing.collider_id, "shape": crossing.shape,
				"linear_velocity": Vector3.ZERO
			}
	if contact.is_empty() or safe_fraction >= 1.0:
		return
	global_position = movement_start.origin + motion * safe_fraction
	var contact_normal: Vector3 = contact.normal
	if velocity.dot(contact_normal) < 0.0:
		velocity = velocity.slide(contact_normal)
	_movement_sphere_contact = contact


func _has_shallow_ground_contacts(sphere_transform: Transform3D) -> bool:
	var query: PhysicsShapeQueryParameters3D = _make_shape_query(main_collision_shape.shape, sphere_transform)
	var contacts: Array[Vector3] = get_world_3d().direct_space_state.collide_shape(query, 32)
	if contacts.is_empty():
		return false
	var maximum_depth: float = maxf(safe_margin, 0.001)
	var support_up: Vector3 = get_collision_support_up()
	# Native ground contacts within the recovery margin remain subject to surface locking.
	for index: int in range(0, contacts.size() - 1, 2):
		if contacts[index].distance_squared_to(contacts[index + 1]) > maximum_depth * maximum_depth:
			return false
		var contact_up: Vector3 = (sphere_transform.origin - contacts[index + 1]).normalized()
		if contact_up.dot(support_up) < 0.95:
			return false
	return true


func request_compact_collision(duration: float) -> void:
	_compact_collision_timer = maxf(_compact_collision_timer, duration)
	if standing_collision_shape:
		_set_standing_collision_enabled(false)
		_set_main_sphere_compact(true)


func is_standing_clearance_blocked() -> bool:
	if standing_collision_shape == null or standing_collision_shape.shape == null or not attached:
		return false
	return not _has_standing_clearance()


func try_uncurl_with_wall_recovery() -> bool:
	if standing_collision_shape == null or standing_collision_shape.shape == null or not attached:
		return true
	if not _can_expand_collision():
		return false
	_set_standing_collision_enabled(false)
	_set_main_sphere_compact(true)
	var standing_clear: bool = _has_standing_clearance()
	if standing_clear:
		if not _record_standing_clearance(true):
			return false
		if _set_main_sphere_compact(false):
			return true
	else:
		_record_standing_clearance(false)
	if not _ensure_main_sphere_configured() or uncurl_wall_push_max_distance <= 0.0:
		return false
	var support_up: Vector3 = get_collision_support_up()
	if support_up.length_squared() < 0.001:
		return false
	var correction: Vector3 = Vector3.ZERO
	for attempt: int in 6:
		var push: Vector3 = _get_uncurl_wall_push(correction, support_up)
		if push.length_squared() < 0.000001:
			break
		var remaining: float = uncurl_wall_push_max_distance - correction.length()
		if remaining <= 0.0:
			break
		push = push.limit_length(remaining)
		if not _can_move_compact_sphere(correction, push):
			break
		correction += push
		if _has_standing_clearance_at(correction, true) and _can_move_compact_sphere(Vector3.ZERO, correction):
			global_position += correction
			return _record_standing_clearance(true) and _set_main_sphere_compact(false)
	return false


func _has_standing_clearance() -> bool:
	return _has_standing_clearance_at(Vector3.ZERO)


func _has_standing_clearance_at(offset: Vector3, check_main_sphere: bool = false) -> bool:
	var standing_transform: Transform3D = global_transform * _get_standing_collision_transform()
	standing_transform.origin += offset
	if not _shape_has_clearance(standing_collision_shape.shape, standing_transform, true, true):
		return false
	if not check_main_sphere or not _ensure_main_sphere_configured():
		return true
	var sphere_transform: Transform3D = global_transform * _main_sphere_base_transform
	sphere_transform.origin += offset
	return _shape_has_clearance(
		main_collision_shape.shape,
		sphere_transform,
		true
	)


func _shape_has_clearance(shape: Shape3D, shape_transform: Transform3D, allow_support_overlap: bool = false, allow_support_foot: bool = false) -> bool:
	var query: PhysicsShapeQueryParameters3D = _make_shape_query(shape, shape_transform)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space.intersect_shape(query, 1).is_empty():
		return true
	if not attached:
		return false
	if allow_support_overlap and _has_moving_collision_support():
		if moving_support_contact_tolerance > 0.0 or (allow_support_foot and standing_support_foot_fraction > 0.0):
			return _shape_has_moving_support_clearance(query, shape_transform, allow_support_foot)
	var contacts: Array[Vector3] = space.collide_shape(query, 16)
	if contacts.is_empty():
		return false
	var support_up: Vector3 = get_collision_support_up()
	# Support tangency tolerates submillimeter contact error.
	for index: int in range(0, contacts.size() - 1, 2):
		if contacts[index].distance_squared_to(contacts[index + 1]) > 0.000001:
			return false
		var contact_up: Vector3 = (shape_transform.origin - contacts[index + 1]).normalized()
		if contact_up.dot(support_up) < 0.99:
			return false
	return true


func _shape_has_moving_support_clearance(query: PhysicsShapeQueryParameters3D, shape_transform: Transform3D, allow_support_foot: bool) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var hits: Array[Dictionary] = space.intersect_shape(query, 64)
	if hits.size() >= 64:
		return false
	var support_rid: RID = _collision_support_body.get_rid()
	var other_exclusions: Array[RID] = query.exclude.duplicate()
	other_exclusions.append(support_rid)
	var support_exclusions: Array[RID] = query.exclude.duplicate()
	var has_support_contact: bool = false
	for hit: Dictionary in hits:
		var rid: RID = hit.rid
		if rid == support_rid:
			has_support_contact = true
		elif not support_exclusions.has(rid):
			support_exclusions.append(rid)
	query.exclude = other_exclusions
	if not space.intersect_shape(query, 1).is_empty():
		var other_contacts: Array[Vector3] = space.collide_shape(query, 32)
		if not _contacts_are_support_tangencies(other_contacts, shape_transform, 0.001, false):
			return false
	if not has_support_contact:
		return true
	query.exclude = support_exclusions
	var support_contacts: Array[Vector3] = space.collide_shape(query, 64)
	if support_contacts.size() >= 128:
		return false
	var maximum_depth: float = minf(moving_support_contact_tolerance, maxf(safe_margin, 0.001))
	return _contacts_are_support_tangencies(support_contacts, shape_transform, maximum_depth, true, allow_support_foot)


func _contacts_are_support_tangencies(
	contacts: Array[Vector3],
	shape_transform: Transform3D,
	maximum_depth: float,
	check_support_point: bool,
	allow_support_foot: bool = false
) -> bool:
	if contacts.is_empty():
		return false
	var support_up: Vector3 = get_collision_support_up()
	var support_point: Vector3 = _collision_support_body.to_global(_collision_support_local_point)
	for index: int in range(0, contacts.size() - 1, 2):
		var push: Vector3 = contacts[index + 1] - contacts[index]
		if allow_support_foot and _is_standing_support_foot_contact(contacts[index], contacts[index + 1], shape_transform):
			continue
		if push.length_squared() > maximum_depth * maximum_depth:
			return false
		var contact_up: Vector3 = (shape_transform.origin - contacts[index + 1]).normalized()
		if check_support_point:
			if (contacts[index + 1] - support_point).dot(support_up) > maximum_depth:
				return false
			if push.length_squared() > 0.000001:
				contact_up = push.normalized()
		if contact_up.dot(support_up) < (0.95 if check_support_point else 0.99):
			return false
	return true


func _is_standing_support_foot_contact(shape_point: Vector3, support_point: Vector3, standing_transform: Transform3D) -> bool:
	if standing_support_foot_fraction <= 0.0 or not _ensure_main_sphere_configured():
		return false
	var up: Vector3 = get_collision_support_up()
	var full_sphere: Transform3D = global_transform * _main_sphere_base_transform
	var offset: Vector3 = standing_transform.origin - (global_transform * _get_standing_collision_transform()).origin
	var radius: float = (main_collision_shape.shape as SphereShape3D).radius * full_sphere.basis.x.length()
	var boundary: Vector3 = full_sphere.origin + offset - up * radius * (1.0 - standing_support_foot_fraction)
	if (shape_point - boundary).dot(up) > 0.001 or (support_point - boundary).dot(up) > 0.001:
		return false
	var separation: Vector3 = support_point - shape_point
	var normal: Vector3 = separation.normalized() if separation.length_squared() > 0.000001 else (standing_transform.origin - support_point).normalized()
	return normal.dot(up) >= 0.707


func _make_shape_query(shape: Shape3D, shape_transform: Transform3D) -> PhysicsShapeQueryParameters3D:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = shape_transform
	query.collision_mask = collision_mask
	var exclusions: Array[RID] = [get_rid()]
	for body: PhysicsBody3D in get_collision_exceptions():
		exclusions.append(body.get_rid())
	query.exclude = exclusions
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.0
	return query


func _get_uncurl_wall_push(offset: Vector3, support_up: Vector3) -> Vector3:
	var largest_push: Vector3 = Vector3.ZERO
	var standing_transform: Transform3D = global_transform * _get_standing_collision_transform()
	standing_transform.origin += offset
	var standing_query: PhysicsShapeQueryParameters3D = _make_shape_query(
		standing_collision_shape.shape, standing_transform
	)
	largest_push = _get_largest_lateral_contact_push(standing_query, support_up, largest_push)
	if _main_sphere_compact:
		var sphere_transform: Transform3D = global_transform * _main_sphere_base_transform
		sphere_transform.origin += offset
		var sphere_query: PhysicsShapeQueryParameters3D = _make_shape_query(
			main_collision_shape.shape, sphere_transform
		)
		largest_push = _get_largest_lateral_contact_push(sphere_query, support_up, largest_push)
	if largest_push.length_squared() < 0.000001:
		return Vector3.ZERO
	return largest_push + largest_push.normalized() * 0.02


func _get_largest_lateral_contact_push(
	query: PhysicsShapeQueryParameters3D,
	support_up: Vector3,
	current_push: Vector3
) -> Vector3:
	var contacts: Array[Vector3] = get_world_3d().direct_space_state.collide_shape(query, 16)
	var largest_push: Vector3 = current_push
	for index: int in range(0, contacts.size() - 1, 2):
		var push: Vector3 = (contacts[index + 1] - contacts[index]).slide(support_up)
		if push.length_squared() > largest_push.length_squared():
			largest_push = push
	return largest_push


func _can_move_compact_sphere(offset: Vector3, motion: Vector3) -> bool:
	var compact_transform: Transform3D = global_transform * _main_sphere_last_transform
	compact_transform.origin += offset
	if not _shape_motion_has_clearance(main_collision_shape.shape, compact_transform, motion, true):
		return false
	compact_transform.origin += motion
	return _shape_has_clearance(main_collision_shape.shape, compact_transform, true)


func _shape_motion_has_clearance(shape: Shape3D, shape_transform: Transform3D, motion: Vector3, allow_support_overlap: bool = false) -> bool:
	if not _shape_has_clearance(shape, shape_transform, allow_support_overlap):
		return false
	var query: PhysicsShapeQueryParameters3D = _make_shape_query(shape, shape_transform)
	query.motion = motion
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.is_empty() or fractions[0] < 1.0:
		return false
	# Center traversal includes contacts omitted by initial-overlap sweeps.
	var center_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		shape_transform.origin, shape_transform.origin + motion
	)
	center_ray.collision_mask = query.collision_mask
	center_ray.exclude = query.exclude
	center_ray.collide_with_areas = false
	center_ray.hit_from_inside = true
	return space.intersect_ray(center_ray).is_empty()


func _can_expand_collision() -> bool:
	if not attached or not _collision_attached_last_move:
		return false
	var support_up: Vector3 = get_collision_support_up()
	if support_up.length_squared() < 0.001:
		return false
	var relative_velocity: Vector3 = velocity
	if _has_moving_collision_support():
		# Built-in platform motion is applied outside the gameplay velocity.
		relative_velocity += world_to_movement_velocity(get_platform_velocity() - _get_collision_support_velocity())
	var inward_motion: float = -relative_velocity.dot(support_up) * get_movement_physics_delta()
	return inward_motion <= maxf(safe_margin, 0.001)


func _can_transition_main_sphere(target_transform: Transform3D) -> bool:
	var current_world: Transform3D = global_transform * _main_sphere_last_transform
	var target_world: Transform3D = global_transform * target_transform
	if not _shape_has_clearance(main_collision_shape.shape, target_world, true):
		return false
	var full_world: Transform3D = global_transform * _main_sphere_base_transform
	var shape_radius: float = (main_collision_shape.shape as SphereShape3D).radius
	var full_radius: float = shape_radius * full_world.basis.x.length()
	var current_radius: float = shape_radius * current_world.basis.x.length()
	var target_radius: float = shape_radius * target_world.basis.x.length()
	# Sphere transitions remain inside the cleared full sphere.
	if (
		current_world.origin.distance_to(full_world.origin) + current_radius <= full_radius + 0.00001
		and target_world.origin.distance_to(full_world.origin) + target_radius <= full_radius + 0.00001
		and _shape_has_clearance(main_collision_shape.shape, full_world, true)
	):
		return true
	var motion: Vector3 = target_world.origin - current_world.origin
	if motion.length_squared() < 0.000001:
		return true
	var sweep_transform: Transform3D = current_world
	if target_world.basis.x.length_squared() < current_world.basis.x.length_squared():
		sweep_transform.basis = target_world.basis
	return _shape_motion_has_clearance(main_collision_shape.shape, sweep_transform, motion)


func _ensure_main_sphere_configured() -> bool:
	if main_collision_shape == null or not (main_collision_shape.shape is SphereShape3D):
		return false
	if _main_sphere_initialized:
		return true
	_main_sphere_base_transform = main_collision_shape.transform
	_main_sphere_last_transform = _main_sphere_base_transform
	_main_sphere_base_radius = (main_collision_shape.shape as SphereShape3D).radius * _main_sphere_base_transform.basis.x.length()
	_main_sphere_initialized = _main_sphere_base_radius > 0.1
	return _main_sphere_initialized


func get_main_collision_world_radius() -> float:
	if not _ensure_main_sphere_configured():
		return 0.0
	var shape_world: Transform3D = global_transform * _main_sphere_last_transform
	return (main_collision_shape.shape as SphereShape3D).radius * shape_world.basis.x.length()


## Actual main sphere center after collision-transform clearance checks.
func get_main_collision_world_center() -> Vector3:
	if not _ensure_main_sphere_configured():
		return global_position
	return global_transform * _main_sphere_last_transform.origin


## Model displacement preserving the full sphere's contact spacing.
func get_main_collision_visual_contact_offset(contact_normal: Vector3) -> Vector3:
	if not _ensure_main_sphere_configured() or contact_normal.length_squared() < 0.001:
		return Vector3.ZERO
	var normal: Vector3 = contact_normal.normalized()
	var base_world: Transform3D = global_transform * _main_sphere_base_transform
	var current_world: Transform3D = global_transform * _main_sphere_last_transform
	var radius: float = (main_collision_shape.shape as SphereShape3D).radius
	var radius_difference: float = radius * (base_world.basis.x.length() - current_world.basis.x.length())
	var center_difference: float = (current_world.origin - base_world.origin).dot(normal)
	return normal * maxf(radius_difference + center_difference, 0.0)


func _get_main_sphere_transform(compact: bool) -> Transform3D:
	var reduction: float = clampf(compact_sphere_radius_reduction, 0.0, _main_sphere_base_radius - 0.1)
	var target_transform: Transform3D = _main_sphere_base_transform
	if compact and reduction > 0.0:
		var up: Vector3 = get_collision_support_up()
		var action_up: Vector3 = Vector3.ZERO
		if _active_action is CharacterAction:
			action_up = (_active_action as CharacterAction).get_compact_collision_up()
		if action_up.length_squared() > 0.001:
			up = action_up
		elif not attached and _air_landing_align_active and _air_landing_align_normal.length_squared() > 0.001:
			up = _air_landing_align_normal
		if up.length_squared() < 0.001:
			up = Vector3.UP
		var local_up: Vector3 = global_transform.basis.inverse() * up.normalized()
		target_transform.origin -= local_up * reduction
		target_transform.basis = _main_sphere_base_transform.basis.scaled(
			Vector3.ONE * ((_main_sphere_base_radius - reduction) / _main_sphere_base_radius)
		)
	return target_transform


func _set_main_sphere_compact(compact: bool) -> bool:
	if not _ensure_main_sphere_configured():
		return true
	var target_transform: Transform3D = _get_main_sphere_transform(compact)
	if _main_sphere_last_transform.is_equal_approx(target_transform):
		return true
	if not _can_transition_main_sphere(target_transform):
		return false
	for owner_id: int in get_shape_owners():
		if shape_owner_get_owner(owner_id) != main_collision_shape:
			continue
		var shape_index: int = shape_owner_get_shape_index(owner_id, 0)
		PhysicsServer3D.body_set_shape_transform(get_rid(), shape_index, target_transform)
		_main_sphere_last_transform = target_transform
		_main_sphere_compact = compact and compact_sphere_radius_reduction > 0.0
		main_collision_shape.set_deferred("transform", target_transform)
		return true
	return false


func _set_standing_collision_enabled(enabled: bool) -> void:
	if standing_collision_shape == null:
		return
	_ensure_standing_shape_configured()
	if _standing_collision_enabled == enabled:
		return
	for owner_id: int in get_shape_owners():
		if shape_owner_get_owner(owner_id) != standing_collision_shape:
			continue
		var shape_index: int = shape_owner_get_shape_index(owner_id, 0)
		PhysicsServer3D.body_set_shape_disabled(get_rid(), shape_index, not enabled)
		_standing_collision_enabled = enabled
		standing_collision_shape.set_deferred("disabled", not enabled)
		return


func _ensure_standing_shape_configured() -> void:
	if _standing_collision_initialized:
		return
	_standing_collision_enabled = not standing_collision_shape.disabled
	_standing_shape_base_transform = standing_collision_shape.transform
	_standing_shape_last_transform = _standing_shape_base_transform
	_standing_collision_initialized = true


func _get_standing_collision_transform() -> Transform3D:
	_ensure_standing_shape_configured()
	var up: Vector3 = get_collision_support_up()
	if up.length_squared() < 0.001:
		return _standing_shape_base_transform
	var local_up: Vector3 = (global_transform.basis.inverse() * up.normalized()).normalized()
	var rotation: Basis = Basis(Quaternion(Vector3.UP, local_up))
	return Transform3D(
		rotation * _standing_shape_base_transform.basis,
		rotation * _standing_shape_base_transform.origin
	)


func _set_standing_collision_transform(target_transform: Transform3D) -> void:
	if _standing_shape_last_transform.is_equal_approx(target_transform):
		return
	for owner_id: int in get_shape_owners():
		if shape_owner_get_owner(owner_id) != standing_collision_shape:
			continue
		var shape_index: int = shape_owner_get_shape_index(owner_id, 0)
		PhysicsServer3D.body_set_shape_transform(get_rid(), shape_index, target_transform)
		_standing_shape_last_transform = target_transform
		standing_collision_shape.set_deferred("transform", target_transform)
		return


func _update_standing_collision() -> void:
	if standing_collision_shape == null or standing_collision_shape.shape == null:
		return
	var compact: bool = not attached or rolling or _spindash_charging or _jump_requested
	compact = compact or _compact_collision_timer > 0.0
	if _active_action is CharacterAction:
		compact = compact or (_active_action as CharacterAction).compact_collision
	var standing_transform: Transform3D = _get_standing_collision_transform()
	if compact:
		_set_standing_collision_enabled(false)
		_set_standing_collision_transform(standing_transform)
		_set_main_sphere_compact(true)
	elif not _can_expand_collision() and (_main_sphere_compact or not _standing_collision_enabled):
		_set_standing_collision_enabled(false)
		_set_standing_collision_transform(standing_transform)
	elif _record_standing_clearance(_has_standing_clearance()):
		if _main_sphere_compact:
			_set_standing_collision_enabled(false)
		_set_standing_collision_transform(standing_transform)
		if _set_main_sphere_compact(false):
			_set_standing_collision_enabled(true)
		else:
			_set_standing_collision_enabled(false)
	else:
		_set_standing_collision_enabled(false)
		_set_standing_collision_transform(standing_transform)
		_set_main_sphere_compact(true)
		var neutral_action: bool = (
			_active_action == null
			or _active_action == _grounded_action
			or _active_action == _fall_action
			or _active_action == _jump_action
		)
		if _roll_action != null and neutral_action and _roll_action.force_start_from_surface():
			_sync_roll_state_from_action()


func _movement_physics_process(delta: float) -> void:
	var motion_delta: float = get_movement_delta(delta)
	_compact_collision_timer = maxf(_compact_collision_timer - _movement_real_delta, 0.0)
	if _network_is_active() and not is_multiplayer_authority():
		_network_puppet_tick(_movement_real_delta)
		return

	if _level_load_suspended:
		_reset_drift_state()
		_stop_skid_sfx()
		_stop_engine_sfx()
		_stop_roll_sfx()
		velocity = Vector3.ZERO
		_network_send_state(delta)
		_sync_online_debug_puppet(delta)
		return

	if _local_pause_enabled and not _network_is_active():
		_reset_drift_state()
		_stop_skid_sfx()
		_stop_engine_sfx()
		_stop_roll_sfx()
		velocity = Vector3.ZERO
		_update_main_state_and_flags(delta)
		_update_animation(delta)
		_update_jump_ball(delta)
		_update_jump_dash_trail(delta)
		_network_send_state(delta)
		_sync_online_debug_puppet(delta)
		return

	_update_gravity_state(delta)

	if _debug_mode:
		_reset_drift_state()
		_read_input()
		_debug_fly_tick(delta)
		_update_jump_ball(delta)
		_update_jump_dash_trail(delta)
		_network_send_state(delta)
		_sync_online_debug_puppet(delta)
		return

	_refresh_surface_behavior_areas(global_position)
	var was_attached: bool = attached
	_refresh_moving_collision_support()
	if not attached:
		_reset_standing_clearance_state()
	var detach_fallback_normal: Vector3 = surface_normal
	if _dbg_tp_trace > 0:
		print("[TP-F%d] start: vel=%v att=%s was=%s jump=%s" % [9 - _dbg_tp_trace, velocity, attached, was_attached, _jump_requested])

	_pending_landing_has_velocity = false
	_pending_landing_airborne_time = max(_airborne_time, 0.0)
	_ground_snap_attached_this_frame = false

	# Reset per-frame radial attach flag
	_radial_attach_this_frame = false

	_jump_dash_recent_timer = max(_jump_dash_recent_timer - delta, 0.0)
	_homing_post_attack_timer = max(_homing_post_attack_timer - delta, 0.0)
	_combat_homing_lockout_timer = max(_combat_homing_lockout_timer - delta, 0.0)
	_lightspeed_dash_start_bonus_cooldown_timer = max(_lightspeed_dash_start_bonus_cooldown_timer - delta, 0.0)
	_post_ui_unblock_action_suppress_timer = max(_post_ui_unblock_action_suppress_timer - _movement_real_delta, 0.0)
	_landing_timer = max(_landing_timer - delta, 0.0)
	_spindash_turn_free_timer = max(_spindash_turn_free_timer - delta, 0.0)
	_spindash_roll_route_lockout_timer = max(_spindash_roll_route_lockout_timer - delta, 0.0)
	_enemy_bounce_cooldown_timer = max(_enemy_bounce_cooldown_timer - delta, 0.0)
	_tick_enemy_hurt_boundary_exceptions(delta)
	if attached:
		_enemy_attack_chain_active = false
		_set_attack_source(AttackSource.AIR_UNCURL, false)
	if _hurt_action != null:
		_sync_hurt_state_to_action()
		_hurt_action.continuous_physics_update(delta)
		_sync_hurt_state_from_action()
	else:
		_damage_hit_invuln_timer = max(_damage_hit_invuln_timer - delta, 0.0)
		if _hurt_active:
			_hurt_state_timer += delta
			if attached:
				_hurt_active = false
				_hurt_state_timer = 0.0
		else:
			_hurt_state_timer = 0.0
	_trick_retrigger_timer = max(_trick_retrigger_timer - delta, 0.0)

	# Spring lock timers
	if _spring_action != null:
		_sync_spring_state_to_action()
		_spring_action.continuous_physics_update(delta)
		_sync_spring_state_from_action()
	else:
		_spring_movement_lock_timer = max(_spring_movement_lock_timer - delta, 0.0)
		_spring_action_lock_timer   = max(_spring_action_lock_timer - delta, 0.0)
	# Dash panel timer
	_dash_speed_lock_timer = max(_dash_speed_lock_timer - delta, 0.0)
	_timed_max_speed_override_timer = max(_timed_max_speed_override_timer - delta, 0.0)
	_tick_speed_shoes(delta)
	_ramp_hold_forward_timer = max(_ramp_hold_forward_timer - delta, 0.0)
	_ramp_hold_up_timer = max(_ramp_hold_up_timer - delta, 0.0)

	# Debug timers – keep values visible for a short time
	_dbg_radial_hit_timer = max(_dbg_radial_hit_timer - delta, 0.0)
	_dbg_detach_timer     = max(_dbg_detach_timer - delta, 0.0)
	_dbg_surface_preview_timer = max(_dbg_surface_preview_timer - delta, 0.0)
	_dbg_surface_seam_timer = max(_dbg_surface_seam_timer - delta, 0.0)
	_surface_support_timer = max(_surface_support_timer - delta, 0.0)

	if _attachment_immunity > 0.0:
		_attachment_immunity = max(_attachment_immunity - delta, 0.0)
	if _low_speed_detach_reattach_block_timer > 0.0:
		_low_speed_detach_reattach_block_timer = max(_low_speed_detach_reattach_block_timer - delta, 0.0)

	_update_water_physics_state(delta)

	if _lightspeed_dash_active:
		attached = false
		# Lock input movement during dash to prevent normal movement
		_spring_movement_lock_timer = delta * 2.0
		_spring_action_lock_timer = delta * 2.0

	# ------------------------------------------------------------------
	# WORLD/GRAVITY UP (single source of truth for airborne gravity frame)
	# ------------------------------------------------------------------
	var world_up: Vector3 = _get_gravity_up()

	# ==========================================================
	# [VAULT BAR] Override: scripted pivot rotation
	# ==========================================================
	if _vault_bar_active:
		if _is_dead:
			cancel_vault_bar()
		else:
			_update_vault_bar(delta)

		if _vault_bar_active:
			_reset_movement_release_deceleration()
			attached = false
			_is_falling = false
			velocity = Vector3.ZERO
			up_direction = world_up
			_physics_up_last = world_up
			_update_control_anchor(world_up)
			_update_hurt_invuln_visual(delta)
			_debug_draw()
			_update_main_state_and_flags(delta)
			_update_attack_sources()
			_update_jump_ball(delta)
			_update_jump_dash_trail(delta)
			_update_carried_object_target()
			_network_send_state(delta)
			_sync_online_debug_puppet(delta)
			_jump_requested = false
			_coyote_jump_requested = false
			_prev_attached = false
			_air_torque_prev_attached = false
			_clear_air_landing_align()
			return

	_read_input()
	if _ability_input_router != null:
		_ability_input_router.update(delta)
	var priority_input_consumed: bool = _prepare_priority_action_input(delta)
	_preemptive_profile_input_consumed = priority_input_consumed
	if not priority_input_consumed:
		_update_roll_state()
		_preemptive_profile_input_consumed = _process_preemptive_character_profile_input_routes()
		_update_spindash_state(delta)
		_process_action_inputs()
	_update_action_runtime(delta)
	if _buddy_jump_mimic_active:
		var jump_slot: StringName = get_ability_input_slot(&"jump", &"ability_slot_01")
		if SettingsManager.is_gameplay_action_just_released(String(jump_slot)) or not SettingsManager.is_gameplay_action_pressed(String(jump_slot)):
			_notify_buddy_leader_jump_released()

	if attached:
		if _bounce_state != BounceState.NONE:
			_bounce_state = BounceState.NONE
	_update_attack_sources()

	# ==========================================================
	# [RAIL] Override: dedicated grind handling
	# ==========================================================
	if _is_dead and _rail_active:
		cancel_rail_grind(false)
	if _rail_active:
		_reset_movement_release_deceleration()
		if not _prev_rail_active:
			if _trick_system != null:
				_trick_system.reset_air_trick_staleness()
		_prev_rail_active = true
		_reset_drift_state()
		up_direction = world_up
		_update_rail_motion(motion_delta, world_up)

		if _rail_active:
			attached = true
			_is_falling = false

			_update_barrier_blast(delta, world_up, true)
			_update_speed_wind_sfx()
			_update_skid_sfx(delta, _get_lateral_speed_for_anim())
			_update_rail_grind_sfx(delta)
			_update_sonic_boom_fx(delta)
			_notify_buddy_barrier_blast_sync()
			_notify_buddy_dynamic_mimic_ranges()

			_update_control_anchor(world_up)
			_update_visual_up(motion_delta)
			_update_model_orientation(motion_delta)
			_update_hurt_invuln_visual(delta)
			_debug_draw()
			_update_main_state_and_flags(delta)
			_update_animation(delta)
			_update_skid_sfx(delta, _get_lateral_speed_for_anim())
			_update_engine_sfx(delta, _get_lateral_speed_for_anim())
			_update_roll_sfx(delta, _get_lateral_speed_for_anim())
			_update_jump_ball(delta)
			_update_jump_dash_trail(delta)
			_update_carried_object_target()
			_network_send_state(delta)
			_sync_online_debug_puppet(delta)

			_jump_requested = false
			_coyote_jump_requested = false
			_prev_attached = attached
			_air_torque_prev_attached = false
			_clear_air_landing_align()

			return

	# ==========================================================
	# [RAIL SWITCH] Scripted transfer to target rail
	# ==========================================================
	if _rail_switch_active:
		_reset_movement_release_deceleration()
		_prev_rail_switch_active = true
		_reset_drift_state()
		up_direction = world_up
		_update_rail_switch(motion_delta)

		if _rail_switch_active or _rail_active:
			attached = false
			_is_falling = false

			_update_control_anchor(world_up)
			_update_visual_up(motion_delta)
			_update_model_orientation(motion_delta)
			_update_hurt_invuln_visual(delta)
			_debug_draw()
			_update_main_state_and_flags(delta)
			_update_animation(delta)
			_update_skid_sfx(delta, _get_lateral_speed_for_anim())
			_update_engine_sfx(delta, _get_lateral_speed_for_anim())
			_update_roll_sfx(delta, _get_lateral_speed_for_anim())
			_update_jump_ball(delta)
			_update_jump_dash_trail(delta)
			_update_carried_object_target()
			_network_send_state(delta)
			_sync_online_debug_puppet(delta)

			_jump_requested = false
			_coyote_jump_requested = false
			_prev_attached = attached
			_air_torque_prev_attached = false
			_clear_air_landing_align()
			return

	# ==========================================================
	# [SPLINE] Override: if in spline spring, handle that first
	# ==========================================================
	if _spline_active:
		_reset_movement_release_deceleration()
		_prev_spline_active = true
		_reset_drift_state()
		# On spline: keep a stable gravity-up frame.
		up_direction = world_up

		_update_spline_spring(motion_delta)

		if _spline_active:
			_pre_slide_velocity = velocity
			_move_with_movement_time_scale()
			_process_slide_collision_surface_behaviors()

			_update_fall_flag(delta)
			_apply_airborne_collision_state()
			_update_control_anchor(world_up)
			_update_visual_up(motion_delta)
			_update_model_orientation(motion_delta)
			_update_hurt_invuln_visual(delta)
			_debug_draw()
			_update_main_state_and_flags(delta)
			_update_air_trick_animation()
			_update_animation(delta)
			_update_skid_sfx(delta, _get_lateral_speed_for_anim())
			_update_engine_sfx(delta, _get_lateral_speed_for_anim())
			_update_roll_sfx(delta, _get_lateral_speed_for_anim())
			_update_jump_ball(delta)
			_update_jump_dash_trail(delta)
			_update_carried_object_target()
			_network_send_state(delta)
			_sync_online_debug_puppet(delta)

			_jump_requested = false
			_coyote_jump_requested = false
			_prev_attached = attached
			_air_torque_prev_attached = false
			_clear_air_landing_align()

			return

	# ----------------------------------------------------------
	var is_attached_for_movement: bool = attached and (_spring_align_timer <= 0.0)

	# ----------------------------------------------------------
	# 2) Physics up (gravity + velocity decomposition + move_and_slide up_direction)
	#    IMPORTANT: never use _get_input_up() here.
	# ----------------------------------------------------------
	var phys_up: Vector3 = world_up
	if is_attached_for_movement and surface_normal.length() > 0.001:
		phys_up = surface_normal.normalized()

	# Even if attached, spring-align forces the gravity-up frame of reference.
	if _spring_align_timer > 0.0:
		phys_up = world_up

	# CharacterBody3D floor logic should use the same phys_up
	up_direction = phys_up

	# Keep this updated EVERY frame (prevents old steep normals lingering)
	_physics_up_last = phys_up

	# ----------------------------------------------------------
	# 3) Control up (stick space + control anchor + debug inputs)
	# ----------------------------------------------------------
	var control_up: Vector3 = phys_up
	if not is_attached_for_movement:
		control_up = world_up

	# 🔹DEBUG: manual upward kick on V (and similar)
	_debug_inputs(control_up)

	# Update stick info in this frame's control space
	_update_stick(control_up)

	# ----------------------------------------------------------
	# 4) Movement integration + slide
	# ----------------------------------------------------------
	var was_on_platform: bool = _platform_on_floor_last and _platform_collider_last != null and is_instance_valid(_platform_collider_last) and _platform_collider_last.is_inside_tree()
	var platform_velocity_for_leave: Vector3 = Vector3.ZERO

	if was_on_platform and delta > 0.0:
		# Plain RigidBody3D objects (no get_platform_velocity) are not treated as carry
		# platforms. Using their linear_velocity for carry creates a feedback loop:
		# player contact impulse → sphere velocity → carry moves player → more contact.
		# Only RigidBody3Ds that explicitly implement get_platform_velocity are carried.
		var is_plain_rigid_body: bool = (
			is_instance_valid(_platform_collider_last)
			and _platform_collider_last is RigidBody3D
			and not _platform_collider_last.has_method("get_platform_velocity")
		)

		if not is_plain_rigid_body:
			var delta_horizontal: Vector3
			if _platform_collider_last is RigidBody3D:
				var rb_vel: Vector3 = (_platform_collider_last as RigidBody3D).linear_velocity
				delta_horizontal = (rb_vel - world_up * rb_vel.dot(world_up)) * _movement_real_delta
			else:
				var current_origin: Vector3 = _platform_collider_last.global_position
				var delta_origin: Vector3 = current_origin - _platform_prev_origin
				delta_horizontal = delta_origin - world_up * delta_origin.dot(world_up)

			var max_carry_disp: float = max_platform_carry_speed * _movement_real_delta
			if delta_horizontal.length() > max_carry_disp and max_carry_disp > 0.0:
				delta_horizontal = delta_horizontal.normalized() * max_carry_disp

			if manual_platform_position_carry_enabled:
				global_position = global_position + delta_horizontal
			platform_velocity_for_leave = delta_horizontal / delta

	var v_before: Vector3 = velocity
	var p_before: Vector3 = global_position

	var _dbg_on_rigid: bool = _dbg_dynbody and _follow_collider_last != null and is_instance_valid(_follow_collider_last) and _follow_collider_last is RigidBody3D
	if _dbg_on_rigid:
		print("[DYN] PRE_MOVE  spd=%.3f vel=%v sn=%v" % [velocity.length(), velocity, surface_normal])

	var _dash_was_active: bool = _lightspeed_dash_active
	_apply_movement(motion_delta, phys_up, is_attached_for_movement)
	_apply_automation_25d_world_constraint(motion_delta)
	_apply_post_movement_max_speed_override(phys_up, is_attached_for_movement)
	v_before = velocity
	if _dbg_tp_trace > 0:
		print("[TP-F%d] post_movement: vel=%v spd=%.2f" % [9 - _dbg_tp_trace, velocity, velocity.length()])
	if _dbg_on_rigid:
		print("[DYN] POST_MOVE spd=%.3f vel=%v" % [velocity.length(), velocity])

	_pre_slide_velocity = velocity
	var floor_stop_on_slope_before: bool = floor_stop_on_slope
	if _spindash_charging and is_attached_for_movement:
		floor_stop_on_slope = true
	_move_with_movement_time_scale()
	_process_slide_collision_surface_behaviors()
	floor_stop_on_slope = floor_stop_on_slope_before
	if _spindash_charging and is_attached_for_movement:
		var post_slide_normal_speed: float = velocity.dot(phys_up)
		var post_slide_lateral: Vector3 = velocity - phys_up * post_slide_normal_speed
		if post_slide_lateral.length() <= max(spindash_charge_stop_speed, 0.0):
			velocity = Vector3.ZERO
	if _lightspeed_dash_active:
		_post_move_lightspeed_dash(delta)
	_refresh_automation_25d_constraint_after_slide()
	_apply_automation_25d_world_constraint(0.0, true)
	if _dbg_tp_trace > 0:
		print("[TP-F%d] post_slide: vel=%v spd=%.2f" % [9 - _dbg_tp_trace, velocity, velocity.length()])
	if _dbg_on_rigid:
		print("[DYN] POST_SLIDE spd=%.3f vel=%v plat_vel=%v" % [velocity.length(), velocity, get_platform_velocity()])

	_update_platform_carry_state()

	if not _lightspeed_dash_active:
		_try_rail_path_snap_attach(v_before, p_before)

	# If we stepped/jumped off a platform this frame, carry its horizontal momentum.
	if was_on_platform and not _platform_on_floor_last and platform_velocity_for_leave.length() > 0.0001:
		if _dbg_tp_trace > 0:
			print("[TP-F%d] PLATFORM_CARRY: carry=%v new_vel=%v" % [9 - _dbg_tp_trace, platform_velocity_for_leave, velocity + platform_velocity_for_leave])
		velocity = velocity + platform_velocity_for_leave

	# Keep the anchor basis consistent with gravity-up control space in air.
	_update_control_anchor(control_up)

	# Non-directional spring state can exit when motion stalls.
	if _spring_align_timer > 0.0 and spring_exit_on_low_speed and not _spring_lock_sideways:
		if velocity.length() <= spring_exit_speed_threshold:
			_spring_align_timer = 0.0
			_spring_align_up = Vector3.ZERO
			_spring_align_forward = Vector3.ZERO
			_spring_lock_sideways = false

			# Ensure the next frame is firmly gravity-up.
			_physics_up_last = world_up
			up_direction = world_up

	# ----------------------------------------------------------
	# 5) Collision-based landing / attachment.
	# ----------------------------------------------------------
	if not _movement_object_contact_handled:
		for action in _actions:
			if action != null and is_instance_valid(action):
				action.resolve_movement_contact(v_before)
	if not _lightspeed_dash_active and not _movement_object_contact_handled:
		if not _rail_active:
			_process_collisions_for_attachment(v_before, p_before, delta)
			_try_ground_snap_attach(world_up, v_before, p_before)
	_apply_pending_enemy_hurt_boundary_launch(world_up)

	# ----------------------------------------------------------
	# 6) Landing momentum (AIR -> GROUND) and landing bookkeeping.
	# ----------------------------------------------------------
	if attached and not was_attached and not _ground_snap_attached_this_frame and not _rail_active:
		var landing_vel: Vector3 = _last_air_velocity
		if _pending_landing_has_velocity:
			landing_vel = _pending_landing_velocity
		if _dbg_tp_trace > 0:
			print("[TP-F%d] LANDING_MOMENTUM: last_air=%v pend_has=%s pend_vel=%v landing_vel=%v" % [9 - _dbg_tp_trace, _last_air_velocity, _pending_landing_has_velocity, _pending_landing_velocity, landing_vel])
		if _platform_on_floor_last and _platform_velocity_last.length() > 0.001:
			var plat_horiz: Vector3 = _platform_velocity_last - world_up * _platform_velocity_last.dot(world_up)
			landing_vel = landing_vel - plat_horiz
		var ground_hit_normal: Vector3 = surface_normal.normalized()
		_last_ground_hit_speed = maxf(-landing_vel.dot(ground_hit_normal), 0.0)
		_last_ground_hit_strength = clampf(
			inverse_lerp(ground_hit_min_speed, maxf(ground_hit_full_speed, ground_hit_min_speed + 0.001), _last_ground_hit_speed),
			0.0,
			1.0
		)
		var stops_on_landing: bool = _should_land_stationary(surface_normal, landing_vel)
		_landing_animation_pending = true
		_apply_landing_momentum(surface_normal, landing_vel)
		_landing_animation_moving = not stops_on_landing and (_move_input.length_squared() > 0.000001 or velocity.slide(ground_hit_normal).length() >= 0.5)
		for action in _actions:
			if action != null and is_instance_valid(action):
				if action.resolve_landing_momentum(surface_normal, landing_vel):
					break

		_is_jumping = false
		_jump_variable = false
		_jump_time = 0.0
		_jump_hang_allowed = false
		_just_jumped = true
		refresh_airborne_abilities(surface_normal.normalized().dot(world_up) > 0.7)
		_jumped_from_ground = false
		_falling_without_jump = false

			# Additional landing state resets.

		if _spring_cancel_on_ground:
			_spring_align_timer = 0.0
			_spring_align_up = Vector3.ZERO
			_spring_align_forward = Vector3.ZERO
			_spring_lock_sideways = false

		_clear_spring_locks_on_landing()

		_spring_lock_sideways = false
		_finalize_trick_landing()
		_reset_trick_state()


		# record impact for landing / hard-landing conditions
		var up_for_impact: Vector3 = _physics_up_last.normalized()
		if up_for_impact.length() < 0.001:
			up_for_impact = world_up

		var v_air: Vector3 = _last_air_velocity
		var impact_speed: float = (-v_air).dot(up_for_impact)
		_last_landing_impact_speed = max(impact_speed, 0.0)
		_landing_timer = landing_linger_time
		if _barrier_blast_gauge >= 1.0:
			_barrier_blast_deplete_grace_timer = max(
				_barrier_blast_deplete_grace_timer,
				max(barrier_blast_full_land_grace_time, 0.0)
			)
			# Mirror the drain grace with an exit-speed grace so landing on ramps
			# cannot momentarily drop below full and re-trigger the sonic boom.
			_barrier_blast_full_land_exit_grace_timer = max(
				_barrier_blast_full_land_exit_grace_timer,
				max(barrier_blast_full_land_grace_time, 0.0)
			)

	# 7) Ground follow + update attachment after ray probe.
	_ground_follow_probe(delta)
	_update_attachment_state_after_move(delta)
	_reconcile_grounded_state_after_move(world_up)
	_resolve_air_trick_landing_boost(was_attached)
	if was_attached and not attached:
		_ensure_directional_influence_lock_for_detach(detach_fallback_normal, world_up)
	_update_manual_airborne_torque(motion_delta)
	_update_air_torque_ground_tracking(delta)
	_update_trick_detection(delta)

	if not _rail_active:
		_prev_rail_active = false
	if not _rail_switch_active:
		_prev_rail_switch_active = false
	if not _spline_active:
		_prev_spline_active = false

	if _automation_expired_this_frame:
		_automation_active = false
		# Clear automation adhesion override when the timer window expires.
		_automation_max_speed_override_enabled = false
		_automation_max_speed_override = 0.0
		_automation_force_surface_adhesion = false
		_automation_lock_movement = false
		_automation_lock_actions = false
		_automation_lock_drift = false
		_automation_mode = AutomationSplineMode.GUIDED
		_automation_constraint_source = null
		_automation_influence = 0.0
		_automation_path_point = Vector3.ZERO
		_automation_plane_normal = Vector3.ZERO
		_automation_plane_up = Vector3.UP
		_automation_input_mode = AutomationPlaneInputMode.PATH_HORIZONTAL
		_automation_reverse_input = false
		_automation_input_deadzone = 0.05
		_automation_strict_position_lock = true
		_automation_post_slide_constraint_pass_enabled = false
		_automation_position_lock_strength = 12.0
		_automation_max_position_correction_speed = 80.0
		_automation_position_lock_deadzone = 0.005
		_automation_strict_velocity_lock = true
		_automation_disable_turning_slowdown = false
		_automation_velocity_lock_strength = 18.0
		_automation_sideways_speed_preservation = 0.0
		_automation_constrain_special_moves = true
		_automation_bidirectional_assist = false
		_automation_along_speed_limits_player = true
		_automation_priority_current = -9999

	# Barrier Blast gauge/state update (uses final attachment + velocity).
	var barrier_attached_for_movement: bool = attached and (_spring_align_timer <= 0.0)
	if not _rail_active:
		_update_barrier_blast(delta, world_up, barrier_attached_for_movement)
	_update_speed_wind_sfx()
	_update_skid_sfx(delta, _get_lateral_speed_for_anim())
	_update_engine_sfx(delta, _get_lateral_speed_for_anim())
	_update_roll_sfx(delta, _get_lateral_speed_for_anim())
	_update_sonic_boom_fx(delta)
	_notify_buddy_barrier_blast_sync()
	_notify_buddy_dynamic_mimic_ranges()

	_prev_rail_active = _rail_active
	_prev_rail_switch_active = _rail_switch_active
	_prev_spline_active = _spline_active

	if _debug_visible:
		var speed_before_movement: float = v_before.length()
		var speed_after_movement: float = velocity.length()
		var v_after_slide: Vector3 = velocity
		var speed_after_slide: float = v_after_slide.length()

#		print("spd_before=%0.2f\nspd_after_move=%0.2f\nspd_after_slide=%0.2f\nattached=%s" % [
#			speed_before_movement,
#			speed_after_movement,
#			speed_after_slide,
#			str(attached)
#		])

	# 8) Lock to surface if attached.
	_capture_collision_support()
	_lock_to_surface()
	_advance_standing_clearance_release(delta)
	if _roll_action and _roll_action.resolve_collision_uncurl_after_movement():
		_sync_roll_state_from_action()
	_update_standing_collision()

	# 9) Update falling flag based on final attachment + velocity.
	_update_fall_flag(delta)
	_apply_airborne_collision_state()
	_update_air_landing_prediction(delta, world_up)
	_cancel_air_tumble_for_action(world_up)

	# 10) Visuals + debug.
	_update_visual_up(motion_delta)
	_update_model_orientation(motion_delta)
	_update_hurt_invuln_visual(delta)
	_debug_draw()

	# 11) High-level state snapshot (for anim, gameplay, etc.)
	_update_main_state_and_flags(delta)
	_update_attack_sources()
	_update_air_trick_animation()

	_update_animation(delta)
	_update_jump_ball(delta)
	_update_jump_dash_trail(delta)
	_update_carried_object_target()
	_network_send_state(delta)
	_sync_online_debug_puppet(delta)
	if _dbg_tp_trace > 0:
		print("[TP-F%d] end: vel=%v" % [9 - _dbg_tp_trace, velocity])
		_dbg_tp_trace -= 1
	_jump_requested = false
	_coyote_jump_requested = false
	_prev_attached = attached
	if _spring_align_timer > 0.0 or _spline_active or _rail_active:
		_air_torque_prev_attached = false
	else:
		_air_torque_prev_attached = attached

	# Auto-unstuck detection: check if player is stuck (airborne with high velocity but no position change).
	if unstuck_auto_detect_enabled and not attached:
		if _spring_align_timer <= 0.0 and not _spline_active and not _rail_active:
			var current_speed: float = velocity.length()
			var position_change: float = (global_position - _unstuck_prev_position).length()
			if current_speed >= unstuck_auto_min_speed and position_change <= unstuck_auto_max_position_change:
				_unstuck_detection_timer += delta
				if _unstuck_detection_timer >= unstuck_auto_detection_time:
					unstuck_now()
					_unstuck_detection_timer = 0.0
			else:
				_unstuck_detection_timer = 0.0
		else:
			_unstuck_detection_timer = 0.0
	else:
		_unstuck_detection_timer = 0.0
	_unstuck_prev_position = global_position
	_advance_spring_alignment(delta)


# ===========================================================
# INPUT / CAMERA
# ===========================================================
func _read_input() -> void:
	if not _network_is_local_authority():
		_move_input = Vector2.ZERO
		_walk_input_held = false
		return
	if _local_pause_enabled:
		_move_input = Vector2.ZERO
		_walk_input_held = false
		return
	if get_tree() != null and get_tree().paused:
		_move_input = Vector2.ZERO
		_walk_input_held = false
		return
	if _ui_input_blocked:
		_move_input = Vector2.ZERO
		_walk_input_held = false
		return
	if _spring_movement_lock_timer > 0.0:
		_move_input = Vector2.ZERO
		_walk_input_held = false
		return
	if _automation_lock_movement and _automation_locks_active():
		_move_input = Vector2.ZERO
		_walk_input_held = false
		return

	if race_in_countdown:
		_move_input = Vector2.ZERO
		_walk_input_held = false
		return

	var keyboard_x: float = SettingsManager.get_signed_action_axis(&"move_left", &"move_right", 0.0, &"keyboard")
	var keyboard_z: float = SettingsManager.get_signed_action_axis(&"move_back", &"move_forward", 0.0, &"keyboard")
	var keyboard_input: Vector2 = Vector2(keyboard_x, keyboard_z)
	var gamepad_raw_input: Vector2 = SettingsManager.get_raw_action_vector(
		&"move_left",
		&"move_right",
		&"move_back",
		&"move_forward",
		&"gamepad"
	)
	var gamepad_input: Vector2 = SettingsManager.get_radial_action_vector(
		&"move_left",
		&"move_right",
		&"move_back",
		&"move_forward",
		SettingsManager.get_left_stick_deadzone(),
		SettingsManager.get_left_stick_max(),
		&"gamepad"
	)
	var keyboard_strength: float = keyboard_input.length()
	var gamepad_strength: float = gamepad_input.length()
	_move_input = keyboard_input
	if gamepad_strength > keyboard_strength:
		_move_input = gamepad_input
	if _move_input.length() > 1.0:
		_move_input = _move_input.normalized()
	if _move_input.length() < 0.001:
		_move_input = Vector2.ZERO
	if _move_input != Vector2.ZERO:
		_release_enemy_targeting_spawn_grace()
	if _hurt_active:
		_move_input *= clamp(hurt_input_influence, 0.0, 1.0)
	var walk_keyboard: bool = SettingsManager.is_gameplay_action_pressed("walk")
	var using_gamepad: bool = gamepad_strength > keyboard_strength
	var walk_stick_strength: float = clamp(gamepad_raw_input.length(), 0.0, 1.0)
	var walk_zone: float = clamp(SettingsManager.walk_stick_zone_percent / 100.0, 0.0, 1.0)
	if using_gamepad and walk_zone > 0.0 and walk_stick_strength <= walk_zone:
		_walk_input_held = true
	else:
		_walk_input_held = walk_keyboard
	if _uses_left_stick_trick_controls() and _should_start_manual_airborne_torque():
		if not _left_stick_trick_momentum_active:
			_begin_left_stick_trick_momentum()
		_move_input = Vector2.ZERO
		_walk_input_held = false


func _update_roll_state() -> void:
	if _roll_action != null:
		if not _can_execute_action_while_carrying(_roll_action):
			if _roll_action.has_method("_end_roll_if_active"):
				_roll_action.call("_end_roll_if_active")
			_sync_roll_state_from_action()
			return
		var was_rolling: bool = rolling
		_roll_action.continuous_physics_update(0.0)
		_sync_roll_state_from_action()
		if rolling != was_rolling:
			_notify_buddy_leader_roll_changed(rolling)
		return
	if not _network_is_local_authority():
		rolling = false
		return
	if _hurt_active:
		rolling = false
		return
	if is_surface_roll_blocked():
		if rolling:
			rolling = false
			_notify_buddy_leader_roll_changed(false)
		return
	if _local_pause_enabled or _ui_input_blocked or _debug_mode:
		rolling = false
		return
	if _spindash_charging:
		if not rolling:
			rolling = true
			_notify_buddy_leader_roll_changed(true)
		return
	if not roll_enabled:
		rolling = false
		return

	var was_rolling: bool = rolling
	var want_roll: bool = SettingsManager.is_gameplay_action_pressed("ability_slot_04") or is_surface_roll_forced()

	if rolling:
		if not want_roll or not _can_continue_roll():
			rolling = false
	else:
		if want_roll and _can_start_roll():
			rolling = true

	if rolling != was_rolling:
		_notify_buddy_leader_roll_changed(rolling)


func _can_start_roll() -> bool:
	if _roll_action != null:
		return _roll_action._can_start_roll()
	if is_surface_roll_blocked():
		return false
	# Block during any action locks / special movement states.
	if _spring_action_lock_timer > 0.0 or _spring_movement_lock_timer > 0.0:
		return false
	if _spring_align_timer > 0.0:
		return false
	if _rail_active or _spline_active:
		return false
	if _homing_active:
		return false
	if _bounce_state != BounceState.NONE:
		return false
	return true


func _can_continue_roll() -> bool:
	if _roll_action != null:
		return _roll_action._can_continue_roll()
	# Same gating as start; if any conflicting state begins, roll drops immediately.
	return _can_start_roll()


# ===========================================================
# DRIFT
# ===========================================================
func _reset_drift_state() -> void:
	if _drift_action != null:
		_drift_action.reset_state()
		_sync_drift_state_from_action()
		_clear_drift_visual_influence()
		return
	_drift_active = false
	_drift_exit_active = false
	_drift_exit_pending = false
	_drift_exit_locked = false
	_drift_turn_deg_per_sec_current = 0.0
	_drift_turn_input_scale_current = 1.0
	_drift_back_input_current = 0.0
	_drift_same_input_current = 0.0
	_drift_turn_entry_timer = 0.0
	_drift_entry_turn_deg_per_sec_start = 0.0
	_drift_exit_turn_deg_per_sec_start = 0.0
	_drift_exit_elapsed = 0.0
	_drift_exit_blend = 0.0
	_drift_direction = 0
	_drift_direction_target = 0
	_drift_direction_value = 0.0
	_drift_direction_value_start = 0.0
	_drift_switch_elapsed = 0.0
	_drift_entry_speed_current = 0.0
	_clear_drift_visual_influence()
	_reset_drift_reward_state()
	_stop_drift_sfx()


func _finish_drift_exit() -> void:
	if _drift_action != null:
		_drift_action.finish_exit()
		_sync_drift_state_from_action()
		_clear_drift_visual_influence()
		return
	_drift_active = false
	_drift_exit_active = false
	_drift_exit_pending = false
	_drift_exit_locked = false
	_drift_turn_deg_per_sec_current = 0.0
	_drift_turn_input_scale_current = 1.0
	_drift_back_input_current = 0.0
	_drift_same_input_current = 0.0
	_drift_turn_entry_timer = 0.0
	_drift_entry_turn_deg_per_sec_start = 0.0
	_drift_exit_turn_deg_per_sec_start = 0.0
	_drift_exit_elapsed = 0.0
	_drift_exit_blend = 0.0
	_drift_direction = 0
	_drift_direction_target = 0
	_drift_direction_value = 0.0
	_drift_direction_value_start = 0.0
	_drift_switch_elapsed = 0.0
	_drift_entry_speed_current = 0.0
	_clear_drift_visual_influence()
	_reset_drift_reward_state()
	_stop_drift_sfx()


func _cancel_drift_exit() -> void:
	if _drift_action != null:
		_drift_action.cancel_exit()
		_sync_drift_state_from_action()
		return
	_drift_exit_active = false
	_drift_exit_pending = false
	_drift_exit_locked = false
	_drift_exit_turn_deg_per_sec_start = 0.0
	_drift_exit_elapsed = 0.0
	_drift_exit_blend = 0.0


func _reset_drift_reward_state() -> void:
	_drift_reward_turn_degrees_current = 0.0
	_drift_reward_distance_current = 0.0
	_drift_reward_progress = 0.0
	_drift_speed_bonus_current = 0.0


func _can_use_drift() -> bool:
	if _drift_action != null:
		_sync_drift_state_to_action()
		return _drift_action.can_use()
	if not drift_enabled:
		return false
	if not _network_is_local_authority():
		return false
	if _local_pause_enabled or _ui_input_blocked or _debug_mode:
		return false
	if is_surface_drift_blocked():
		return false
	if _spring_action_lock_timer > 0.0 or _spring_movement_lock_timer > 0.0:
		return false
	if _spring_align_timer > 0.0:
		return false
	if _rail_active or _spline_active:
		return false
	if _homing_active:
		return false
	if _bounce_state != BounceState.NONE:
		return false
	if rolling:
		return false
	if _spindash_charging:
		return false
	if _automation_lock_drift and _automation_locks_active():
		return false
	return true


func _begin_drift_exit_ease(lock_exit: bool = true) -> void:
	if _drift_action != null:
		_sync_drift_state_to_action()
		_drift_action.begin_exit_ease(lock_exit)
		_sync_drift_state_from_action()
		return
	if _drift_exit_active:
		if lock_exit:
			_drift_exit_locked = true
		return
	_drift_exit_active = true
	_drift_exit_pending = true
	_drift_exit_locked = lock_exit
	_drift_exit_turn_deg_per_sec_current = abs(_drift_turn_speed_last)
	_drift_exit_turn_deg_per_sec_start = _drift_exit_turn_deg_per_sec_current
	_drift_exit_elapsed = 0.0
	_drift_exit_blend = 1.0


func _apply_drift_exit_turn_ease(desired_turn_deg_per_sec: float, delta: float) -> float:
	if _drift_action != null:
		_sync_drift_state_to_action()
		var eased_turn: float = _drift_action.apply_exit_turn_ease(desired_turn_deg_per_sec, delta)
		_sync_drift_state_from_action()
		return eased_turn
	if not _drift_exit_active:
		return desired_turn_deg_per_sec

	var target_turn: float = max(desired_turn_deg_per_sec, 0.0)
	var duration: float = max(drift_exit_duration, 0.0)
	var delay: float = _get_drift_exit_delay()
	var total_duration: float = duration + delay
	if total_duration <= 0.0:
		_drift_exit_turn_deg_per_sec_current = target_turn
		_drift_exit_active = false
		_drift_exit_elapsed = 0.0
		_drift_exit_blend = 0.0
		if _drift_exit_pending:
			_finish_drift_exit()
		return target_turn

	_drift_exit_elapsed = min(_drift_exit_elapsed + max(delta, 0.0), total_duration)
	var progress: float = 1.0
	if duration > 0.0:
		progress = clamp((_drift_exit_elapsed - delay) / duration, 0.0, 1.0)
	var eased_progress: float = _sample_drift_exit_ease(progress)
	_drift_exit_blend = 1.0 - eased_progress
	_drift_exit_turn_deg_per_sec_current = lerp(_drift_exit_turn_deg_per_sec_start, target_turn, eased_progress)

	if _drift_exit_elapsed >= total_duration:
		_drift_exit_turn_deg_per_sec_current = target_turn
		_drift_exit_active = false
		_drift_exit_elapsed = 0.0
		_drift_exit_blend = 0.0
		if _drift_exit_pending:
			_finish_drift_exit()

	return _drift_exit_turn_deg_per_sec_current


func _get_drift_exit_delay() -> float:
	if not drift_exit_delay_enabled:
		return 0.0
	return max(drift_exit_delay, 0.0)


func _sample_drift_exit_ease(t: float) -> float:
	var t_clamped: float = clamp(t, 0.0, 1.0)
	if drift_exit_ease_curve != null:
		return clamp(drift_exit_ease_curve.sample_baked(t_clamped), 0.0, 1.0)
	return 1.0 - pow(1.0 - t_clamped, 3.0)


func _is_drift_anim_active() -> bool:
	return _drift_active and not _rail_active and not _spline_active and attached


func _get_drift_anim_direction() -> int:
	if not _is_drift_anim_active():
		return 0
	return _drift_direction


func _get_drift_anim_steer_amount() -> float:
	return clamp(_drift_same_input_current - _drift_back_input_current, -1.0, 1.0)


func _clear_drift_visual_influence() -> void:
	_drift_visual_blend = 0.0
	_drift_visual_steer = 0.0


func _update_drift_visual_influence(delta: float) -> void:
	if not drift_visual_influence_enabled:
		_clear_drift_visual_influence()
		return

	var allowed: bool = (
		_drift_active
		and attached
		and not _rail_active
		and not _spline_active
		and not _homing_active
		and _bounce_state == BounceState.NONE
		and _spring_align_timer <= 0.0
		and not _is_dead
	)
	if not allowed:
		_clear_drift_visual_influence()
		return

	var target_blend: float = 1.0
	if _drift_exit_active:
		target_blend = clamp(_drift_exit_blend, 0.0, 1.0)

	var blend_speed: float = drift_visual_entry_lerp_speed
	if _drift_exit_active:
		blend_speed = max(drift_visual_exit_lerp_speed, 0.0)
	else:
		blend_speed = max(blend_speed, 0.0)

	if blend_speed <= 0.0 or delta <= 0.0:
		_drift_visual_blend = target_blend
	else:
		_drift_visual_blend = _slerp_scalar(_drift_visual_blend, target_blend, blend_speed, delta)
		if _drift_exit_active:
			_drift_visual_blend = min(_drift_visual_blend, target_blend)

	var steer_amount: float = _get_drift_anim_steer_amount()
	var steer_target: float = clamp(float(_drift_direction) * steer_amount, -1.0, 1.0)
	if _drift_direction == 0:
		steer_target = 0.0
	_drift_visual_steer = _slerp_scalar(_drift_visual_steer, steer_target, max(drift_turn_input_response, 0.0), delta)


func _get_drift_visual_angles_deg() -> Vector3:
	var steer: float = clamp(_drift_visual_steer, -1.0, 1.0)
	var blend: float = clamp(_drift_visual_blend, 0.0, 1.0)
	if blend <= 0.001:
		return Vector3.ZERO

	var side: float = sign(steer)
	if _drift_direction != 0:
		side = sign(float(_drift_direction))
	if abs(side) <= 0.001:
		return Vector3.ZERO

	var relative_steer: float = clamp(steer * side, -1.0, 1.0)
	var inner_t: float = max(relative_steer, 0.0)
	var outer_t: float = max(-relative_steer, 0.0)
	var angles: Vector3 = drift_visual_offset_angles_deg
	angles += drift_visual_inner_angles_deg * inner_t
	angles += drift_visual_outer_angles_deg * outer_t
	return angles * side * blend


func _update_drift_state(
	is_attached: bool,
	slope_angle_deg: float,
	lateral_speed: float,
	current_turn_speed_deg_per_sec: float,
	input_side: int,
	input_strength: float,
	delta: float
) -> void:
	if _drift_action != null:
		_sync_drift_state_to_action()
		_drift_action.update_drift_state(
			is_attached,
			slope_angle_deg,
			lateral_speed,
			current_turn_speed_deg_per_sec,
			input_side,
			input_strength,
			delta
		)
		_sync_drift_state_from_action()
		return
	var was_active: bool = _drift_active
	if not _can_use_drift():
		_reset_drift_state()
		return
	if not is_attached:
		_reset_drift_state()
		return
	if not SettingsManager.is_gameplay_action_pressed("ability_slot_05"):
		if was_active:
			_begin_drift_exit_ease(true)
		return

	var steep_surface_ok: bool = slope_angle_deg >= drift_steep_surface_angle_deg
	var min_speed: float = max(drift_min_speed, 0.0)
	var exit_min_speed: float = drift_exit_min_speed
	if exit_min_speed < 0.0:
		exit_min_speed = 0.0
	elif exit_min_speed <= 0.0:
		exit_min_speed = min_speed
	var required_speed: float = min_speed
	if was_active:
		required_speed = exit_min_speed
	var speed_ok: bool = lateral_speed >= required_speed or steep_surface_ok
	if not speed_ok:
		if was_active:
			_begin_drift_exit_ease(true)
		return

	var side: int = _normalize_drift_side(input_side)
	var input_ok: bool = input_strength >= max(drift_input_deadzone, 0.0)

	if not was_active:
		var resolved_side: int = side if input_ok else 0
		var turn_rate_side: int = _get_drift_entry_turn_rate_side(current_turn_speed_deg_per_sec)
		if resolved_side == 0:
			resolved_side = turn_rate_side
		if resolved_side == 0:
			return
		_start_drift_fallback(resolved_side, current_turn_speed_deg_per_sec, lateral_speed)
		return

	if _drift_exit_active:
		if side != 0 and side != _drift_direction_target:
			_switch_drift_direction_fallback(side)
		_cancel_drift_exit()
	else:
		_advance_drift_direction_switch(delta)

	_drift_turn_speed_last = current_turn_speed_deg_per_sec


func _start_drift_fallback(side: int, pre_drift_turn_deg_per_sec: float, entry_speed: float) -> void:
	_drift_active = true
	_drift_exit_active = false
	_drift_exit_pending = false
	_drift_exit_locked = false
	_drift_entry_turn_deg_per_sec_start = _get_inherited_drift_entry_turn_rate(
		pre_drift_turn_deg_per_sec,
		side
	)
	_drift_turn_deg_per_sec_current = _drift_entry_turn_deg_per_sec_start
	_drift_turn_input_scale_current = 1.0
	_drift_back_input_current = 0.0
	_drift_same_input_current = 0.0
	_drift_turn_entry_timer = max(drift_turn_entry_time, 0.0)
	_drift_direction = side
	_drift_direction_target = side
	_drift_direction_value = float(side)
	_drift_direction_value_start = float(side)
	_drift_switch_elapsed = max(drift_direction_switch_time, 0.0)
	_drift_entry_speed_current = max(entry_speed, 0.0)
	_reset_drift_reward_state()


func _switch_drift_direction_fallback(side: int) -> void:
	var target_side: int = _normalize_drift_side(side)
	if target_side == 0 or target_side == _drift_direction_target:
		return
	_drift_direction = target_side
	_drift_direction_target = target_side
	_drift_direction_value_start = _drift_direction_value
	_drift_turn_input_scale_current = min(_drift_turn_input_scale_current, 1.0)
	if drift_direction_switch_carry_previous_influence:
		_drift_entry_turn_deg_per_sec_start = _drift_turn_deg_per_sec_current
	else:
		_drift_entry_turn_deg_per_sec_start = 0.0
		_drift_turn_deg_per_sec_current = 0.0
		_drift_turn_speed_last = 0.0
	_drift_switch_elapsed = 0.0
	_reset_drift_reward_state()


func _advance_drift_direction_switch(delta: float) -> void:
	var target_value: float = float(_drift_direction_target)
	var switch_time: float = max(drift_direction_switch_time, 0.0)
	if switch_time <= 0.0:
		_drift_direction_value = target_value
		_drift_direction_value_start = target_value
		_drift_switch_elapsed = 0.0
		return
	if is_equal_approx(_drift_direction_value, target_value):
		_drift_direction_value = target_value
		_drift_direction_value_start = target_value
		_drift_switch_elapsed = switch_time
		return
	_drift_switch_elapsed = min(_drift_switch_elapsed + max(delta, 0.0), switch_time)
	var progress: float = clamp(_drift_switch_elapsed / switch_time, 0.0, 1.0)
	var eased: float = _ease_in_out_sine(progress)
	_drift_direction_value = lerp(_drift_direction_value_start, target_value, eased)


func _normalize_drift_side(side: int) -> int:
	if side > 0:
		return 1
	if side < 0:
		return -1
	return 0


func _get_drift_entry_turn_rate_side(pre_drift_turn_deg_per_sec: float) -> int:
	if not drift_entry_turn_rate_inheritance_enabled:
		return 0
	var min_turn_rate: float = max(drift_entry_turn_rate_min_deg_per_sec, 0.0)
	if abs(pre_drift_turn_deg_per_sec) < min_turn_rate:
		return 0
	if pre_drift_turn_deg_per_sec > 0.0:
		return 1
	if pre_drift_turn_deg_per_sec < 0.0:
		return -1
	return 0


func _get_inherited_drift_entry_turn_rate(pre_drift_turn_deg_per_sec: float, drift_side: int) -> float:
	var turn_rate_side: int = _get_drift_entry_turn_rate_side(pre_drift_turn_deg_per_sec)
	var normalized_drift_side: int = _normalize_drift_side(drift_side)
	if turn_rate_side == 0 or turn_rate_side != normalized_drift_side:
		return 0.0

	var inheritance_weight: float = _get_drift_entry_turn_rate_inheritance_weight(pre_drift_turn_deg_per_sec)
	var inherited_turn_rate: float = (
		pre_drift_turn_deg_per_sec
		* max(drift_entry_turn_rate_scale, 0.0)
		* inheritance_weight
	)
	var max_turn_rate: float = max(drift_entry_turn_rate_max_deg_per_sec, 0.0)
	if max_turn_rate > 0.0:
		inherited_turn_rate = clamp(inherited_turn_rate, -max_turn_rate, max_turn_rate)
	return inherited_turn_rate


func _get_drift_entry_turn_rate_inheritance_weight(pre_drift_turn_deg_per_sec: float) -> float:
	var min_turn_rate: float = max(drift_entry_turn_rate_min_deg_per_sec, 0.0)
	var full_turn_rate: float = max(drift_entry_turn_rate_full_deg_per_sec, min_turn_rate + 0.001)
	var ramp: float = clamp(
		(abs(pre_drift_turn_deg_per_sec) - min_turn_rate) / (full_turn_rate - min_turn_rate),
		0.0,
		1.0
	)
	return ramp * ramp * (3.0 - 2.0 * ramp)


func _switch_drift_direction_from_action1() -> bool:
	if not _drift_active or _drift_exit_active:
		return false
	if _drift_action != null:
		_sync_drift_state_to_action()
		var switched: bool = _drift_action.switch_to_opposite_direction()
		_sync_drift_state_from_action()
		return switched
	if _drift_direction_target == 0:
		return false
	_switch_drift_direction_fallback(-_drift_direction_target)
	return true


func _update_drift_reward(delta: float, lateral_speed: float, current_turn_speed_deg_per_sec: float) -> void:
	if _drift_action != null:
		_sync_drift_state_to_action()
		_drift_action.update_drift_reward(delta, lateral_speed, current_turn_speed_deg_per_sec)
		_sync_drift_state_from_action()
		return
	if not _drift_active or _drift_exit_active:
		return
	var dt: float = max(delta, 0.0)
	_drift_reward_turn_degrees_current += abs(current_turn_speed_deg_per_sec) * dt
	_drift_reward_distance_current += max(lateral_speed, 0.0) * dt
	var turn_target: float = max(drift_reward_turn_degrees, 0.001)
	var distance_target: float = max(drift_reward_distance, 0.001)
	var turn_t: float = clamp(_drift_reward_turn_degrees_current / turn_target, 0.0, 1.0)
	var distance_t: float = clamp(_drift_reward_distance_current / distance_target, 0.0, 1.0)
	_drift_reward_progress = max(turn_t, distance_t)
	_drift_speed_bonus_current = max(drift_reward_speed_bonus, 0.0) * _drift_reward_progress


func _get_drift_target_speed(base_top_speed: float) -> float:
	if _drift_action != null and is_instance_valid(_drift_action):
		return _drift_action.get_target_speed(base_top_speed)
	var base_speed: float = max(base_top_speed, 0.0)
	var entry_excess: float = max(_drift_entry_speed_current - base_speed, 0.0)
	var inherited_excess: float = entry_excess * clamp(drift_entry_speed_inheritance, 0.0, 1.0)
	var inheritance_limit: float = max(drift_entry_speed_inheritance_limit, 0.0)
	if inheritance_limit > 0.0:
		inherited_excess = min(inherited_excess, inheritance_limit)
	return base_speed + inherited_excess + max(_drift_speed_bonus_current, 0.0)


func _apply_drift_turn(
	delta: float,
	physics_up: Vector3,
	lateral: Vector3,
	_move_dir: Vector3,
	turn_input_scale: float,
	_back_input_t: float
) -> Vector3:
	if not _drift_active or _drift_exit_active:
		return lateral

	var speed_before: float = lateral.length()
	if speed_before <= 0.01:
		return lateral

	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var direction_value: float = clamp(_drift_direction_value, -1.0, 1.0)
	if abs(direction_value) <= 0.001:
		return lateral

	var cur_dir: Vector3 = lateral / speed_before
	var turn_deg_per_sec: float = max(drift_base_turn_deg_per_sec, 0.0)
	var input_scale: float = max(turn_input_scale, 0.0)
	turn_deg_per_sec *= input_scale
	turn_deg_per_sec *= direction_value
	if _drift_turn_entry_timer > 0.0 and drift_turn_entry_time > 0.0:
		var entry_t: float = 1.0 - clamp(_drift_turn_entry_timer / drift_turn_entry_time, 0.0, 1.0)
		var entry_ease: float = _ease_in_out_sine(entry_t)
		turn_deg_per_sec = lerp(_drift_entry_turn_deg_per_sec_start, turn_deg_per_sec, entry_ease)
	_drift_turn_deg_per_sec_current = _limit_drift_previous_turn_influence(
		_drift_turn_deg_per_sec_current,
		direction_value,
		input_scale
	)

	_drift_turn_deg_per_sec_current = _slerp_scalar(
		_drift_turn_deg_per_sec_current,
		turn_deg_per_sec,
		drift_turn_response,
		delta
	)

	var step_rad: float = deg_to_rad(_drift_turn_deg_per_sec_current) * delta
	if abs(step_rad) <= 0.0:
		return lateral

	var new_dir: Vector3 = cur_dir.rotated(up, step_rad).normalized()
	return new_dir * speed_before


func _limit_drift_previous_turn_influence(
	current_turn_deg_per_sec: float,
	direction_value: float,
	input_scale: float
) -> float:
	var previous_side: float = sign(_drift_direction_value_start)
	var target_side: float = sign(float(_drift_direction_target))
	if abs(previous_side) <= 0.001 or abs(target_side) <= 0.001:
		return current_turn_deg_per_sec
	if previous_side == target_side:
		return current_turn_deg_per_sec
	if sign(current_turn_deg_per_sec) != previous_side:
		return current_turn_deg_per_sec

	var previous_amount: float = 0.0
	if sign(direction_value) == previous_side:
		previous_amount = clamp(abs(direction_value), 0.0, 1.0)
	var max_previous_turn: float = max(drift_base_turn_deg_per_sec, 0.0) * max(input_scale, 0.0) * previous_amount
	return clamp(current_turn_deg_per_sec, -max_previous_turn, max_previous_turn)


# ===========================================================
# SPINDASH
# ===========================================================
func _get_spindash_charge_ratio() -> float:
	var charge_max: float = spindash_charge_time_max
	if _rail_active:
		charge_max = spindash_rail_charge_time_max
	if charge_max <= 0.0:
		return 1.0
	return clamp(_spindash_charge_time / charge_max, 0.0, 1.0)


func _get_spindash_release_speed() -> float:
	var min_speed: float = max(spindash_min_launch_speed, 0.0)
	var max_speed: float = spindash_max_launch_speed
	if _rail_active:
		max_speed = spindash_rail_max_launch_speed
	max_speed = max(max_speed, min_speed)
	var charged_speed: float = lerp(min_speed, max_speed, _get_spindash_charge_ratio())
	if spindash_preserve_entry_speed_above_max and _spindash_entry_speed > max_speed:
		return _spindash_entry_speed
	return charged_speed


func set_spindash_roll_route_lockout(duration: float) -> void:
	_spindash_roll_route_lockout_timer = max(_spindash_roll_route_lockout_timer, max(duration, 0.0))


func get_spindash_countdown_release_buffer_time() -> float:
	if _spindash_action == null or not is_instance_valid(_spindash_action):
		return 0.0
	return max(_spindash_action.race_countdown_release_buffer_time, 0.0)


func set_spindash_countdown_release_buffer_open(enabled: bool) -> void:
	if _spindash_action == null or not is_instance_valid(_spindash_action):
		return
	_spindash_action.set_race_countdown_release_buffer_open(enabled)


func _start_spindash_charge() -> void:
	_spindash_charging = true
	_spindash_charge_time = 0.0
	_spindash_charge_full_played = false
	_spindash_release_requested = false
	_spindash_release_with_jump = false
	_spindash_release_speed = 0.0
	_spindash_pending_release = false
	_spindash_pending_release_speed = 0.0
	_spindash_latched_direction = Vector3.ZERO
	_spindash_ground_hold_timer = 0.0
	_spindash_ground_action1_press_valid = false
	if not rolling:
		rolling = true
		_notify_buddy_leader_roll_changed(true)
	var up: Vector3 = _physics_up_last.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var lateral: Vector3 = velocity - up * velocity.dot(up)
	_spindash_entry_speed = lateral.length()
	if _rail_active:
		_spindash_entry_speed = abs(_rail_speed)
		_trigger_anim_command_immediate(&"CMD_SPINDASHRAIL")
	else:
		_trigger_anim_command_immediate(&"CMD_SPINDASH")
	_start_spindash_loop_sfx()


func _cancel_spindash_charge() -> void:
	if _spindash_action != null:
		_sync_spindash_state_to_action()
		_spindash_action._cancel_charge()
		_sync_spindash_state_from_action()
		return
	if not _spindash_charging:
		return
	_spindash_charging = false
	_spindash_charge_time = 0.0
	_spindash_charge_full_played = false
	_spindash_entry_speed = 0.0
	_spindash_latched_direction = Vector3.ZERO
	_spindash_ground_hold_timer = 0.0
	_spindash_roll_held = false
	_spindash_ground_action1_press_valid = false
	_stop_spindash_loop_sfx()


func _reset_spindash_state() -> void:
	if _spindash_action != null:
		_spindash_action.reset_state()
		_sync_spindash_state_from_action()
		return
	_spindash_charging = false
	_spindash_charge_time = 0.0
	_spindash_charge_full_played = false
	_spindash_release_requested = false
	_spindash_release_with_jump = false
	_spindash_release_speed = 0.0
	_spindash_pending_release = false
	_spindash_pending_release_speed = 0.0
	_spindash_turn_free_timer = 0.0
	_spindash_entry_speed = 0.0
	_spindash_latched_direction = Vector3.ZERO
	_spindash_ground_hold_timer = 0.0
	_spindash_roll_held = false
	_spindash_ground_action1_press_valid = false
	_stop_spindash_loop_sfx()


func _trigger_spindash_release(with_jump: bool) -> void:
	var release_speed: float = _get_spindash_release_speed()
	_spindash_charging = false
	_spindash_charge_time = 0.0
	_spindash_charge_full_played = false
	_stop_spindash_loop_sfx()

	if attached:
		_spindash_release_requested = true
		_spindash_release_speed = release_speed
		_spindash_release_with_jump = with_jump
		if with_jump:
			queue_jump()
		_play_spindash_release_sfx()
	else:
		_spindash_pending_release = true
		_spindash_pending_release_speed = release_speed
	_spindash_ground_action1_press_valid = false


func _update_spindash_state(delta: float) -> void:
	if _spindash_action != null:
		if not _can_execute_action_while_carrying(_spindash_action):
			if _spindash_action.has_method("reset_state"):
				_spindash_action.call("reset_state")
			_sync_spindash_state_from_action()
			return
		_sync_spindash_state_to_action()
		_spindash_action.continuous_physics_update(delta)
		_sync_spindash_state_from_action()
		return
	if not _network_is_local_authority():
		_cancel_spindash_charge()
		return
	if _hurt_active:
		_cancel_spindash_charge()
		_spindash_pending_release = false
		_spindash_pending_release_speed = 0.0
		_spindash_release_requested = false
		_spindash_release_with_jump = false
		_spindash_release_speed = 0.0
		return
	if not spindash_enabled:
		_cancel_spindash_charge()
		_spindash_pending_release = false
		return
	if _local_pause_enabled or _ui_input_blocked or _debug_mode:
		_cancel_spindash_charge()
		return
	if _spline_active:
		_cancel_spindash_charge()
		return
	if _drift_active or _drift_exit_active:
		_cancel_spindash_charge()
		_spindash_ground_hold_timer = 0.0
		_spindash_ground_action1_press_valid = false
		return
	if _automation_lock_actions and _automation_locks_active():
		_cancel_spindash_charge()
		_spindash_pending_release = false
		_spindash_pending_release_speed = 0.0
		_spindash_release_requested = false
		_spindash_release_with_jump = false
		_spindash_release_speed = 0.0
		return
	if _rail_active:
		_update_spindash_state_on_rail(delta)
		return
	if _spring_align_timer > 0.0 and _spring_detached:
		_cancel_spindash_charge()
		return

	var world_up: Vector3 = _get_gravity_up()

	var roll_held: bool = SettingsManager.is_gameplay_action_pressed("ability_slot_04")
	var action1_held: bool = SettingsManager.is_gameplay_action_pressed("ability_slot_02")
	var action1_pressed: bool = SettingsManager.is_gameplay_action_just_pressed("ability_slot_02")
	var action1_released: bool = SettingsManager.is_gameplay_action_just_released("ability_slot_02")
	var jump_pressed: bool = SettingsManager.is_gameplay_action_just_pressed("ability_slot_01") and not race_in_countdown
	var on_ground: bool = attached
	var ground_hold_time: float = max(spindash_ground_hold_time, 0.0)
	_spindash_roll_held = roll_held
	if action1_pressed:
		_spindash_ground_action1_press_valid = on_ground

	if _spindash_pending_release and attached:
		_spindash_release_requested = true
		_spindash_release_speed = _spindash_pending_release_speed
		_spindash_release_with_jump = false
		_spindash_pending_release = false
		_spindash_pending_release_speed = 0.0
		_play_spindash_release_sfx()

	if _spindash_charging:
		if not rolling:
			rolling = true
			_notify_buddy_leader_roll_changed(true)
		if jump_pressed and attached and not is_surface_jump_blocked():
			_perform_spindash_jump(world_up)
			return
		if attached and (action1_released or not action1_held):
			_trigger_spindash_release(false)
			return
		if not attached and action1_released:
			_apply_spindash_air_release(world_up)
			return

		if action1_held:
			_spindash_charge_time = min(_spindash_charge_time + delta, max(spindash_charge_time_max, 0.0))

		if not _spindash_charge_full_played and _get_spindash_charge_ratio() >= 1.0:
			_spindash_charge_full_played = true
			_play_spindash_charge_full_sfx()

		_start_spindash_loop_sfx()
		return

	if not _can_start_roll():
		_spindash_ground_hold_timer = 0.0
		_spindash_ground_action1_press_valid = false
		return

	if not action1_held:
		_spindash_ground_hold_timer = 0.0
		_spindash_ground_action1_press_valid = false
		return

	if on_ground:
		if roll_held and _spindash_roll_route_lockout_timer <= 0.0:
			_start_spindash_charge()
		elif _spindash_ground_action1_press_valid:
			_spindash_ground_hold_timer += delta
			if _spindash_ground_hold_timer >= ground_hold_time:
				_start_spindash_charge()
		else:
			_spindash_ground_hold_timer = 0.0
	else:
		_spindash_ground_hold_timer = 0.0
		_spindash_ground_action1_press_valid = false
		if rolling and roll_held and _spindash_roll_route_lockout_timer <= 0.0:
			_start_spindash_charge()



func _update_spindash_state_on_rail(delta: float) -> void:
	if _automation_lock_actions and _automation_locks_active():
		_cancel_spindash_charge()
		_spindash_pending_release = false
		_spindash_pending_release_speed = 0.0
		_spindash_release_requested = false
		_spindash_release_with_jump = false
		_spindash_release_speed = 0.0
		_spindash_ground_hold_timer = 0.0
		return
	var roll_held: bool = SettingsManager.is_gameplay_action_pressed("ability_slot_04")
	var action1_held: bool = SettingsManager.is_gameplay_action_pressed("ability_slot_02")
	var action1_pressed: bool = SettingsManager.is_gameplay_action_just_pressed("ability_slot_02")
	var action1_released: bool = SettingsManager.is_gameplay_action_just_released("ability_slot_02")
	var ground_hold_time: float = max(spindash_ground_hold_time, 0.0)
	_spindash_roll_held = roll_held
	if action1_pressed:
		_spindash_ground_action1_press_valid = true

	if _spindash_pending_release:
		_spindash_release_requested = true
		_spindash_release_speed = _spindash_pending_release_speed
		_spindash_release_with_jump = false
		_spindash_pending_release = false
		_spindash_pending_release_speed = 0.0
		_play_spindash_release_sfx()

	if _spindash_charging:
		if not rolling:
			rolling = true
			_notify_buddy_leader_roll_changed(true)
		if action1_released or not action1_held:
			_trigger_spindash_release(false)
			return

		_spindash_charge_time = min(_spindash_charge_time + delta, max(spindash_charge_time_max, 0.0))
		if not _spindash_charge_full_played and _get_spindash_charge_ratio() >= 1.0:
			_spindash_charge_full_played = true
			_play_spindash_charge_full_sfx()
		_start_spindash_loop_sfx()
		return

	if _spring_action_lock_timer > 0.0 or _spring_movement_lock_timer > 0.0 or _spring_align_timer > 0.0:
		_spindash_ground_hold_timer = 0.0
		_spindash_ground_action1_press_valid = false
		return
	if not action1_held:
		_spindash_ground_hold_timer = 0.0
		_spindash_ground_action1_press_valid = false
		return

	if roll_held and _spindash_roll_route_lockout_timer <= 0.0:
		_start_spindash_charge()
	elif _spindash_ground_action1_press_valid:
		_spindash_ground_hold_timer += delta
		if _spindash_ground_hold_timer >= ground_hold_time:
			_start_spindash_charge()
	else:
		_spindash_ground_hold_timer = 0.0


func _get_spindash_release_dir(physics_up: Vector3, lateral: Vector3) -> Vector3:
	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var desired: Vector3 = _spindash_latched_direction
	if desired.length() < 0.001:
		desired = _move_direction
	if desired.length() < 0.001:
		if lateral.length() > 0.001:
			desired = lateral.normalized()
		else:
			desired = _model_forward

	desired -= up * desired.dot(up)
	if desired.length() < 0.001:
		desired = -Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up)
	if desired.length() < 0.001:
		desired = Vector3.FORWARD

	return desired.normalized()


func _update_spindash_direction_latch(physics_up: Vector3) -> void:
	if not _spindash_charging or _move_input.length() < 0.001:
		return

	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var input_direction: Vector3 = _move_direction - up * _move_direction.dot(up)
	if input_direction.length() > 0.001:
		_spindash_latched_direction = input_direction.normalized()


func _apply_spindash_release(physics_up: Vector3, lateral: Vector3) -> Vector3:
	var charge_speed: float = max(_spindash_release_speed, 0.0)
	if water_physics_enabled and _running_on_water_surface:
		charge_speed *= clamp(water_surface_spindash_release_effectiveness, 0.0, 1.0)
	var desired_dir: Vector3 = _get_spindash_release_dir(physics_up, lateral)
	var current_along_release: float = lateral.dot(desired_dir)
	var cross_release_velocity: Vector3 = lateral - desired_dir * current_along_release
	var released_along_speed: float
	if current_along_release < 0.0:
		released_along_speed = current_along_release + charge_speed
	else:
		released_along_speed = max(current_along_release, charge_speed)

	return cross_release_velocity + desired_dir * released_along_speed


func _apply_spindash_air_release(world_up: Vector3) -> void:
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var current_velocity: Vector3 = velocity
	var current_horizontal: Vector3 = current_velocity - up * current_velocity.dot(up)
	var current_horizontal_speed: float = current_horizontal.length()
	var release_speed: float = _get_spindash_release_speed()
	
	# Calculate charge_ratio from speed since the timer is reset on release.
	var min_speed: float = max(spindash_min_launch_speed, 0.0)
	var max_speed: float = max(spindash_max_launch_speed, min_speed)
	var charge_ratio: float = 0.0
	if max_speed > min_speed:
		charge_ratio = clamp((release_speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)
	elif max_speed > 0.0:
		charge_ratio = 1.0
	
	var min_horizontal: float = max(spindash_air_release_min_horizontal_speed, 0.0)
	var horizontal_boost: float = max(spindash_air_release_horizontal_boost, 0.0)
	
	# Intelligent speed preservation
	var base_speed: float = current_horizontal_speed
	if spindash_preserve_entry_speed_above_max and _spindash_entry_speed > max_speed:
		base_speed = max(base_speed, _spindash_entry_speed)
	var horizontal_target_speed: float = max(release_speed, base_speed)
	
	if current_horizontal_speed < min_horizontal:
		horizontal_target_speed = max(horizontal_target_speed, min_horizontal + horizontal_boost)
	
	var desired_dir: Vector3 = _get_spindash_release_dir(up, current_horizontal)
	
	# Partially charged spindashes act as a "lesser influence" on direction.
	# Fully charged = complete redirect (snap to desired direction).
	var final_dir: Vector3
	if charge_ratio >= 0.99: # Use a small epsilon for float precision
		final_dir = desired_dir
	else:
		var current_dir: Vector3 = current_horizontal.normalized() if current_horizontal_speed > 0.001 else desired_dir
		final_dir = current_dir.slerp(desired_dir, charge_ratio)
	
	var horizontal_velocity: Vector3 = final_dir * horizontal_target_speed
	var downward_ratio: float = max(spindash_air_release_downward_ratio, 0.0)
	var downward_speed: float = horizontal_target_speed * downward_ratio
	var vertical_target: float = -downward_speed
	var current_vertical: float = current_velocity.dot(up)
	if current_vertical < vertical_target:
		vertical_target = current_vertical
	var target_velocity: Vector3 = horizontal_velocity + up * vertical_target
	var current_speed: float = current_velocity.length()
	var target_speed: float = target_velocity.length()
	if target_speed > 0.001 and target_speed < current_speed:
		target_velocity = target_velocity.normalized() * current_speed
	velocity = target_velocity
	_spindash_charging = false
	_spindash_charge_time = 0.0
	_spindash_charge_full_played = false
	_spindash_release_requested = false
	_spindash_release_with_jump = false
	_spindash_release_speed = 0.0
	_spindash_pending_release = false
	_spindash_pending_release_speed = 0.0
	_spindash_latched_direction = Vector3.ZERO
	_spindash_ground_hold_timer = 0.0
	_spindash_roll_held = false
	_spindash_ground_action1_press_valid = false
	_spindash_turn_free_timer = max(spindash_turn_penalty_disable_time, 0.0)
	_play_spindash_release_sfx()


func _perform_spindash_jump(world_up: Vector3) -> void:
	var up: Vector3 = _physics_up_last.normalized()
	if up.length() < 0.001:
		up = world_up
	if up.length() < 0.001:
		up = _get_gravity_up()

	var v: Vector3 = velocity
	var vertical: float = v.dot(up)
	var jump_speed_used: float = max(spindash_jump_speed, 0.0)
	v += up * (jump_speed_used - vertical)
	velocity = v

	var surf_n: Vector3 = surface_normal.normalized()
	if surf_n.length() < 0.001:
		surf_n = world_up

	_record_detach_state(surf_n, world_up)
	attached = false
	_attachment_immunity = launch_immunity_time
	_airborne_time = 0.0
	_is_skidding = false
	_jumped_from_ground = true
	_falling_without_jump = false

	_jump_variable = false
	_is_jumping = true
	_jump_time = 0.0
	_jump_hang_allowed = false
	_just_jumped = true

	play_jump_sfx()
	_trigger_anim_command(&"CMD_JUMP")


func _compute_move_direction() -> void:
	if _move_input.length() < 0.001:
		_move_direction = Vector3.ZERO
		return

	var forward: Vector3 = _control_forward
	var right: Vector3 = _control_right

	var dir: Vector3 = forward * _move_input.y + right * _move_input.x
	if dir.length() < 0.001:
		_move_direction = Vector3.ZERO
	else:
		_move_direction = dir.normalized()


func _apply_automation_25d_input_mapping(physics_up: Vector3) -> float:
	var raw_strength: float = clamp(_move_input.length(), 0.0, 1.0)
	var original_direction: Vector3 = _move_direction
	var mapping_weight: float = clamp(_automation_influence, 0.0, 1.0)
	if raw_strength <= 0.001:
		_move_direction = Vector3.ZERO
		return 0.0

	var path_direction: Vector3 = _automation_tangent_dir
	path_direction -= physics_up * path_direction.dot(physics_up)
	if path_direction.length() < 0.001:
		path_direction = _automation_tangent_dir
	if path_direction.length() < 0.001:
		_move_direction = Vector3.ZERO
		return 0.0
	path_direction = path_direction.normalized()

	var signed_input: float = 0.0
	match _automation_input_mode:
		AutomationPlaneInputMode.PATH_HORIZONTAL:
			signed_input = _move_input.x
		AutomationPlaneInputMode.PATH_VERTICAL:
			signed_input = _move_input.y
		AutomationPlaneInputMode.CAMERA_RELATIVE:
			signed_input = _move_direction.dot(path_direction) * raw_strength
	if _automation_reverse_input:
		signed_input = -signed_input
	if abs(signed_input) <= _automation_input_deadzone:
		if mapping_weight >= 0.999:
			_move_direction = Vector3.ZERO
			return 0.0
		_move_direction = original_direction
		return raw_strength * (1.0 - mapping_weight)

	var mapped_direction: Vector3 = path_direction * sign(signed_input)
	if mapping_weight >= 0.999 or original_direction.length() < 0.001:
		_move_direction = mapped_direction
	else:
		_move_direction = original_direction.normalized().slerp(mapped_direction, mapping_weight)
		if _move_direction.length() > 0.001:
			_move_direction = _move_direction.normalized()
		else:
			_move_direction = mapped_direction
	return lerp(raw_strength, clamp(abs(signed_input), 0.0, 1.0), mapping_weight)


func _get_automation_constraint_response(
	influence: float,
	strength: float,
	strict_at_full_weight: bool,
	delta: float
) -> float:
	var weight: float = clamp(influence, 0.0, 1.0)
	if strict_at_full_weight and weight >= 0.999:
		return 1.0
	if strength <= 0.0:
		return weight
	return clamp(weight * (1.0 - exp(-strength * max(delta, 0.0))), 0.0, 1.0)


func _apply_automation_25d_world_constraint(
	delta: float,
	strict_post_slide_only: bool = false
) -> void:
	if _is_dead:
		return
	if not _automation_active or _automation_timer <= 0.0:
		return
	if _automation_mode != AutomationSplineMode.TWO_POINT_FIVE_D:
		return
	if _automation_grounded_only and not attached:
		return
	if (
		not _automation_constrain_special_moves
		and (
			_homing_active
			or _lightspeed_dash_active
			or _spring_align_timer > 0.0
		)
	):
		return

	var plane_normal: Vector3 = _automation_plane_normal.normalized()
	if plane_normal.length() < 0.001:
		return
	var influence: float = clamp(_automation_influence, 0.0, 1.0)
	if influence <= 0.0:
		return
	if (
		strict_post_slide_only
		and (
			not _automation_post_slide_constraint_pass_enabled
			or influence < 0.999
		)
	):
		return

	var position_error: float = (global_position - _automation_path_point).dot(plane_normal)
	if (
		(not strict_post_slide_only or _automation_strict_position_lock)
		and (
			abs(position_error) > _automation_position_lock_deadzone
			or (_automation_strict_position_lock and influence >= 0.999)
		)
	):
		var position_correction: Vector3 = -plane_normal * position_error
		if _automation_max_position_correction_speed > 0.0 and influence < 0.999:
			var max_correction: float = _automation_max_position_correction_speed * max(delta, 0.0)
			if position_correction.length() > max_correction:
				position_correction = position_correction.normalized() * max_correction
		var position_response: float = _get_automation_constraint_response(
			influence,
			_automation_position_lock_strength,
			_automation_strict_position_lock,
			delta
		)
		global_position += position_correction * position_response

	if not strict_post_slide_only or _automation_strict_velocity_lock:
		var sideways_speed: float = velocity.dot(plane_normal)
		var constrained_velocity: Vector3 = velocity - plane_normal * sideways_speed
		var preservation: float = clamp(_automation_sideways_speed_preservation, 0.0, 1.0)
		if preservation > 0.0:
			var original_speed: float = velocity.length()
			var constrained_speed: float = constrained_velocity.length()
			if original_speed > constrained_speed and constrained_speed > 0.001:
				var restored_speed: float = lerp(constrained_speed, original_speed, preservation)
				constrained_velocity = constrained_velocity / constrained_speed * restored_speed
		var velocity_response: float = _get_automation_constraint_response(
			influence,
			_automation_velocity_lock_strength,
			_automation_strict_velocity_lock,
			delta
		)
		velocity = velocity.lerp(constrained_velocity, velocity_response)


func _refresh_automation_25d_constraint_after_slide() -> void:
	if (
		not _automation_active
		or _automation_timer <= 0.0
		or _automation_mode != AutomationSplineMode.TWO_POINT_FIVE_D
		or not _automation_post_slide_constraint_pass_enabled
		or _automation_influence < 0.999
		or _automation_constraint_source == null
		or not is_instance_valid(_automation_constraint_source)
		or not _automation_constraint_source.has_method("refresh_25d_constraint_after_slide")
	):
		return
	_automation_constraint_source.call("refresh_25d_constraint_after_slide", self)


func _get_max_speed_override_state(automation_active: bool) -> Dictionary:
	var override_active: bool = false
	var override_target: float = max(max_speed, 0.0)
	if automation_active and _automation_max_speed_override_enabled:
		override_active = true
		override_target = _automation_max_speed_override
	if _timed_max_speed_override_timer > 0.0:
		override_active = true
		override_target = _timed_max_speed_override
	return {
		"active": override_active,
		"target": max(override_target, 0.0),
	}


func _apply_post_movement_max_speed_override(
	physics_up: Vector3,
	is_attached_for_movement: bool
) -> void:
	var automation_active: bool = _automation_active and _automation_timer > 0.0
	if automation_active and _automation_grounded_only and not is_attached_for_movement:
		automation_active = false
	var override_state: Dictionary = _get_max_speed_override_state(automation_active)
	if not bool(override_state.get("active", false)):
		return

	var speed_limit: float = float(override_state.get("target", 0.0))
	var water_limit_multiplier: float = 1.0
	var submerged_movement: bool = (
		water_physics_enabled
		and not water_logic_speed_enabled
		and _in_water_volume
		and not _running_on_water_surface
	)
	if automation_active and _automation_ignore_water_physics:
		submerged_movement = false
	if submerged_movement:
		water_limit_multiplier = water_top_speed_multiplier
	speed_limit *= water_limit_multiplier
	_functional_max_speed = float(override_state.get("target", 0.0))

	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var vertical_speed: float = velocity.dot(up)
	var lateral_velocity: Vector3 = velocity - up * vertical_speed
	var lateral_speed: float = lateral_velocity.length()
	if lateral_speed <= speed_limit or lateral_speed <= 0.0:
		return
	lateral_velocity = lateral_velocity / lateral_speed * speed_limit
	velocity = lateral_velocity + up * vertical_speed


func _reset_locomotion_intent_smoothing() -> void:
	_locomotion_intent_direction = Vector3.ZERO
	_locomotion_intent_last_physics_frame = -1


func _reset_movement_release_deceleration(clear_reserve: bool = true) -> void:
	if clear_reserve:
		_movement_release_decel_reserve = 0.0
	_movement_release_decel_base_delay_remaining = 0.0
	_movement_release_decel_ramp_elapsed = 0.0
	_movement_release_decel_scale_current = 1.0
	_movement_release_decel_input_active_last = false
	_movement_release_decel_ramp_active = false


func _update_movement_release_deceleration(
	delta: float,
	current_lateral: Vector3,
	movement_input_active: bool,
	bypass: bool
) -> float:
	if not movement_release_decel_enabled or bypass:
		_reset_movement_release_deceleration()
		return 1.0

	var dt: float = max(delta, 0.0)
	var base_delay: float = max(movement_release_decel_base_delay, 0.0)
	var max_delay: float = max(movement_release_decel_max_delay, base_delay)
	var max_reserve: float = max(max_delay - base_delay, 0.0)
	_movement_release_decel_reserve = min(_movement_release_decel_reserve, max_reserve)

	if movement_input_active:
		var input_strength: float = clamp(_stick_length, 0.0, 1.0)
		var full_speed: float = max(movement_release_decel_full_speed, 0.001)
		var speed_weight: float = clamp(current_lateral.length() / full_speed, 0.0, 1.0)
		var tilt_angle_deg: float = abs(rad_to_deg(_stick_turn))
		var full_tilt_angle: float = max(movement_release_decel_full_tilt_angle_deg, 0.001)
		var tilt_weight: float = clamp(tilt_angle_deg / full_tilt_angle, 0.0, 1.0)

		var intent_weight: float = (speed_weight + input_strength + tilt_weight) / 3.0
		var accumulation_rate: float = max(movement_release_decel_accumulation_rate, 0.0)
		_movement_release_decel_reserve = min(
			_movement_release_decel_reserve + intent_weight * accumulation_rate * dt,
			max_reserve
		)
		_movement_release_decel_base_delay_remaining = 0.0
		_movement_release_decel_ramp_elapsed = 0.0
		_movement_release_decel_scale_current = 0.0
		_movement_release_decel_input_active_last = true
		_movement_release_decel_ramp_active = false
		return 0.0

	if _movement_release_decel_input_active_last:
		_movement_release_decel_base_delay_remaining = base_delay
		_movement_release_decel_ramp_elapsed = 0.0
		_movement_release_decel_ramp_active = true
	_movement_release_decel_input_active_last = false
	if not _movement_release_decel_ramp_active:
		_movement_release_decel_scale_current = 1.0
		return 1.0

	var remaining_dt: float = dt
	if _movement_release_decel_base_delay_remaining > 0.0:
		var base_delay_step: float = min(_movement_release_decel_base_delay_remaining, remaining_dt)
		_movement_release_decel_base_delay_remaining -= base_delay_step
		remaining_dt -= base_delay_step

	if _movement_release_decel_base_delay_remaining <= 0.0 and _movement_release_decel_reserve > 0.0:
		var reserve_step: float = min(_movement_release_decel_reserve, remaining_dt)
		_movement_release_decel_reserve -= reserve_step
		remaining_dt -= reserve_step

	if _movement_release_decel_base_delay_remaining > 0.0 or _movement_release_decel_reserve > 0.0:
		_movement_release_decel_scale_current = 0.0
		return 0.0

	var ramp_time: float = max(movement_release_decel_ramp_time, 0.0)
	if ramp_time <= 0.0:
		_movement_release_decel_scale_current = 1.0
		_movement_release_decel_ramp_active = false
		return 1.0
	_movement_release_decel_ramp_elapsed = min(_movement_release_decel_ramp_elapsed + remaining_dt, ramp_time)
	var ramp_t: float = clamp(_movement_release_decel_ramp_elapsed / ramp_time, 0.0, 1.0)
	_movement_release_decel_scale_current = ramp_t * ramp_t * (3.0 - 2.0 * ramp_t)
	if ramp_t >= 1.0:
		_movement_release_decel_ramp_active = false
	return _movement_release_decel_scale_current


func _get_locomotion_intent_direction(
	raw_direction: Vector3,
	current_lateral: Vector3,
	physics_up: Vector3,
	is_attached: bool,
	delta: float,
	bypass_smoothing: bool
) -> Vector3:
	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var raw_planar: Vector3 = raw_direction - up * raw_direction.dot(up)
	if raw_planar.length() < 0.001:
		_reset_locomotion_intent_smoothing()
		return Vector3.ZERO
	raw_planar = raw_planar.normalized()

	var physics_frame: int = Engine.get_physics_frames()
	var frame_is_contiguous: bool = (
		_locomotion_intent_last_physics_frame >= 0
		and physics_frame <= _locomotion_intent_last_physics_frame + 1
	)
	_locomotion_intent_last_physics_frame = physics_frame

	var lateral_planar: Vector3 = current_lateral - up * current_lateral.dot(up)
	var lateral_speed: float = lateral_planar.length()
	var smoothing_available: bool = input_intent_smoothing_enabled
	if not is_attached and not input_intent_smoothing_airborne_enabled:
		smoothing_available = false
	if bypass_smoothing or not smoothing_available:
		_locomotion_intent_direction = raw_planar
		return raw_planar

	var min_speed: float = max(input_intent_smoothing_min_speed, 0.0)
	var full_speed: float = max(input_intent_smoothing_full_speed, min_speed + 0.001)
	var speed_weight: float = clamp((lateral_speed - min_speed) / (full_speed - min_speed), 0.0, 1.0)
	speed_weight = speed_weight * speed_weight * (3.0 - 2.0 * speed_weight)
	if speed_weight <= 0.001 or lateral_speed < 0.001:
		_locomotion_intent_direction = raw_planar
		return raw_planar

	var travel_direction: Vector3 = lateral_planar / lateral_speed
	var deviation_dot: float = clamp(travel_direction.dot(raw_planar), -1.0, 1.0)
	var deviation_deg: float = rad_to_deg(acos(deviation_dot))
	var full_angle: float = clamp(input_intent_smoothing_full_angle_deg, 0.0, 180.0)
	var bypass_angle: float = clamp(input_intent_smoothing_bypass_angle_deg, 0.0, 180.0)
	if bypass_angle < full_angle:
		bypass_angle = full_angle
	if deviation_deg >= bypass_angle:
		_locomotion_intent_direction = raw_planar
		return raw_planar

	var angle_falloff: float = 0.0
	var falloff_angle_range: float = bypass_angle - full_angle
	if falloff_angle_range > 0.001:
		angle_falloff = clamp((deviation_deg - full_angle) / falloff_angle_range, 0.0, 1.0)
		angle_falloff = angle_falloff * angle_falloff * (3.0 - 2.0 * angle_falloff)
	var smoothing_weight: float = speed_weight * (1.0 - angle_falloff)
	if smoothing_weight <= 0.001:
		_locomotion_intent_direction = raw_planar
		return raw_planar

	var previous_direction: Vector3 = _locomotion_intent_direction
	previous_direction -= up * previous_direction.dot(up)
	if not frame_is_contiguous or previous_direction.length() < 0.001:
		previous_direction = travel_direction
	else:
		previous_direction = previous_direction.normalized()
		var input_change_dot: float = clamp(previous_direction.dot(raw_planar), -1.0, 1.0)
		var input_change_deg: float = rad_to_deg(acos(input_change_dot))
		if input_change_deg >= bypass_angle:
			_locomotion_intent_direction = raw_planar
			return raw_planar

	var max_lag_deg: float = max(input_intent_smoothing_max_lag_deg, 0.0)
	if max_lag_deg <= 0.001:
		_locomotion_intent_direction = raw_planar
		return raw_planar
	var previous_lag_dot: float = clamp(raw_planar.dot(previous_direction), -1.0, 1.0)
	var previous_lag_deg: float = rad_to_deg(acos(previous_lag_dot))
	if previous_lag_deg > max_lag_deg:
		var previous_lag_ratio: float = max_lag_deg / max(previous_lag_deg, 0.001)
		previous_direction = raw_planar.slerp(previous_direction, previous_lag_ratio).normalized()

	var response: float = max(input_intent_smoothing_response, 0.0)
	var filtered_blend: float = 1.0
	if response > 0.0:
		var effective_response: float = response / max(smoothing_weight, 0.001)
		filtered_blend = clamp(1.0 - exp(-effective_response * max(delta, 0.0)), 0.0, 1.0)
	var filtered_direction: Vector3 = previous_direction.slerp(raw_planar, filtered_blend)
	if filtered_direction.length() < 0.001:
		filtered_direction = raw_planar
	else:
		filtered_direction = filtered_direction.normalized()

	var lag_dot: float = clamp(raw_planar.dot(filtered_direction), -1.0, 1.0)
	var lag_deg: float = rad_to_deg(acos(lag_dot))
	if lag_deg > max_lag_deg:
		var lag_ratio: float = max_lag_deg / max(lag_deg, 0.001)
		filtered_direction = raw_planar.slerp(filtered_direction, lag_ratio).normalized()

	_locomotion_intent_direction = filtered_direction
	return filtered_direction

func _record_wall_input_contact(normal: Vector3, physics_up: Vector3, world_up: Vector3) -> void:
	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return

	var player_up: Vector3 = physics_up.normalized()
	if player_up.length() < 0.001:
		player_up = world_up.normalized()
	if player_up.length() < 0.001:
		player_up = _get_gravity_up()

	var angle_vs_player_deg: float = rad_to_deg(acos(clamp(n.dot(player_up), -1.0, 1.0)))
	var min_wall_angle: float = max(walkable_from_up_max_angle_deg, 0.0)
	var max_wall_angle: float = max(wall_from_up_max_angle_deg, min_wall_angle + 0.1)
	max_wall_angle = min(max_wall_angle, 180.0)

	if angle_vs_player_deg <= min_wall_angle:
		return
	if angle_vs_player_deg >= max_wall_angle:
		return

	_wall_input_contact_normals.append(n)


func _apply_wall_input_projection(physics_up: Vector3, is_attached: bool, delta: float) -> void:
	_wall_input_projection_active = false
	_wall_input_push_active = false
	_wall_input_push_normal = Vector3.ZERO
	_wall_input_push_angle_deg = 0.0
	_wall_input_debug_raw_dir = Vector3.ZERO
	_wall_input_debug_projected_dir = Vector3.ZERO
	_wall_input_debug_normal = Vector3.ZERO

	if not _wall_input_contact_normals.is_empty():
		_wall_input_linger_normals = _wall_input_contact_normals.duplicate()
		_wall_input_linger_timer = max(wall_input_projection_linger_time, 0.0)
	elif _wall_input_linger_timer > 0.0:
		_wall_input_linger_timer = max(_wall_input_linger_timer - delta, 0.0)
		if _wall_input_linger_timer <= 0.0:
			_wall_input_linger_normals.clear()

	if not wall_input_projection_enabled:
		return
	if not is_attached and not wall_input_projection_airborne_enabled:
		return
	if _move_direction.length() < 0.001:
		return

	var projection_normals: Array[Vector3] = _wall_input_contact_normals
	if projection_normals.is_empty():
		projection_normals = _wall_input_linger_normals
	if projection_normals.is_empty():
		return

	var input_dir: Vector3 = _move_direction.normalized()
	var best_normal: Vector3 = Vector3.ZERO
	var best_into: float = 0.0
	var best_angle_deg: float = 0.0

	for normal: Vector3 in projection_normals:
		var n: Vector3 = normal.normalized()
		if n.length() < 0.001:
			continue
		var into_amount: float = -input_dir.dot(n)
		if into_amount <= 0.0:
			continue
		var angle_deg: float = rad_to_deg(acos(clamp((-input_dir).dot(n), -1.0, 1.0)))
		if into_amount > best_into:
			best_into = into_amount
			best_normal = n
			best_angle_deg = angle_deg

	if best_normal.length() < 0.001:
		return

	var head_on_angle: float = clamp(wall_input_direct_push_angle_deg, 0.0, 90.0)
	var parallel_angle: float = clamp(wall_input_parallel_angle_deg, 0.0, 90.0)
	var parallel_start_angle: float = 90.0 - parallel_angle
	if parallel_start_angle <= head_on_angle:
		parallel_start_angle = head_on_angle + 0.1

	var direct_dir: Vector3 = -best_normal
	var wall_dir: Vector3 = input_dir.slide(best_normal)
	if wall_dir.length() < 0.001:
		wall_dir = direct_dir
	else:
		wall_dir = wall_dir.normalized()

	var projected_dir: Vector3 = input_dir
	if best_angle_deg <= head_on_angle:
		projected_dir = direct_dir
		_wall_input_push_active = true
	elif best_angle_deg >= parallel_start_angle:
		projected_dir = wall_dir
		_wall_input_projection_active = true
	else:
		var blend_t: float = (best_angle_deg - head_on_angle) / (parallel_start_angle - head_on_angle)
		projected_dir = (direct_dir * (1.0 - blend_t) + wall_dir * blend_t)
		_wall_input_projection_active = true

	if projected_dir.length() < 0.001:
		return

	_wall_input_debug_raw_dir = input_dir
	_wall_input_debug_projected_dir = projected_dir.normalized()
	_wall_input_debug_normal = best_normal
	_move_direction = projected_dir.normalized()
	_wall_input_push_normal = best_normal
	_wall_input_push_angle_deg = best_angle_deg

func _sample_curve_by_speed(curve: Curve, speed: float, fallback_value: float) -> float:
	return PlayerMath.sample_curve_by_speed(curve, speed, fallback_value)


func _smoothstep_unit(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _apply_steered_locomotion_velocity(
	current_lateral: Vector3,
	steering_direction: Vector3,
	raw_intent_direction: Vector3,
	turn_deg_per_sec: float,
	sharp_turn_rate_multiplier: float,
	turn_speed_preservation: float,
	pullback_start_angle_deg: float,
	pullback_turn_rate_multiplier: float,
	pullback_brake_multiplier: float,
	drive_accel: float,
	brake_decel: float,
	brake_control_multiplier: float,
	passive_decel: float,
	target_speed: float,
	input_strength: float,
	delta: float
) -> Vector3:
	var speed: float = current_lateral.length()
	var steer_dir: Vector3 = steering_direction.normalized()
	if steer_dir.length() < 0.001:
		return current_lateral

	var strength: float = clamp(input_strength, 0.0, 1.0)
	var dt: float = max(delta, 0.0)
	if speed < 0.01:
		var gained_speed: float = min(max(target_speed, 0.0), max(drive_accel, 0.0) * strength * dt)
		return steer_dir * gained_speed

	var current_dir: Vector3 = current_lateral / speed
	var raw_dir: Vector3 = raw_intent_direction.normalized()
	if raw_dir.length() < 0.001:
		raw_dir = steer_dir
	var intent_dot: float = clamp(current_dir.dot(raw_dir), -1.0, 1.0)
	var intent_angle_deg: float = rad_to_deg(acos(intent_dot))
	var pullback_start: float = clamp(pullback_start_angle_deg, 0.0, 180.0)
	var pullback_t: float = 0.0
	if pullback_start < 180.0:
		pullback_t = _smoothstep_unit(
			(intent_angle_deg - pullback_start) / max(180.0 - pullback_start, 0.001)
		)

	var steer_dot: float = clamp(current_dir.dot(steer_dir), -1.0, 1.0)
	var steer_angle_rad: float = acos(steer_dot)
	var steer_angle_deg: float = rad_to_deg(steer_angle_rad)
	var sharp_turn_t: float = _smoothstep_unit((steer_angle_deg - 30.0) / 60.0)
	var rate_multiplier: float = lerp(1.0, max(sharp_turn_rate_multiplier, 1.0), sharp_turn_t)
	rate_multiplier *= lerp(1.0, clamp(pullback_turn_rate_multiplier, 0.0, 1.0), pullback_t)
	var analog_turn_scale: float = lerp(0.35, 1.0, strength)
	var max_turn_step: float = deg_to_rad(max(turn_deg_per_sec, 0.0) * rate_multiplier * analog_turn_scale) * dt
	var turned_dir: Vector3 = current_dir
	if steer_angle_rad > 0.001 and max_turn_step > 0.0:
		var turn_weight: float = min(1.0, max_turn_step / steer_angle_rad)
		turned_dir = current_dir.slerp(steer_dir, turn_weight).normalized()
	elif steer_angle_rad <= 0.001:
		turned_dir = steer_dir

	var drive_alignment: float = max(intent_dot, 0.0)
	var new_speed: float = speed
	if new_speed < target_speed and drive_alignment > 0.0:
		var drive_step: float = max(drive_accel, 0.0) * strength * drive_alignment * dt
		new_speed = min(new_speed + drive_step, target_speed)

	var preservation: float = clamp(turn_speed_preservation, 0.0, 1.0)
	var turn_loss_rate: float = max(passive_decel, 0.0) * sharp_turn_t * (1.0 - preservation)
	var opposing_t: float = _smoothstep_unit(max(-intent_dot, 0.0))
	var controlled_brake_scale: float = clamp(brake_control_multiplier, 0.0, 1.0)
	var pullback_brake_scale: float = lerp(
		controlled_brake_scale,
		max(pullback_brake_multiplier, 1.0),
		pullback_t
	)
	var brake_rate: float = max(brake_decel, 0.0) * opposing_t * pullback_brake_scale
	new_speed = max(new_speed - (turn_loss_rate + brake_rate) * dt, 0.0)
	return turned_dir * new_speed


func _get_slope_downhill_accel(speed: float) -> float:
	if (
		not (rolling and roll_enabled)
		and _barrier_blast_active
		and barrier_blast_slope_downhill_accel_curve != null
	):
		return _sample_curve_by_speed(
			barrier_blast_slope_downhill_accel_curve,
			speed,
			slope_downhill_accel
		)
	return _sample_curve_by_speed(slope_downhill_accel_curve, speed, slope_downhill_accel)


func _get_slope_uphill_decel(speed: float) -> float:
	if (
		not (rolling and roll_enabled)
		and _barrier_blast_active
		and barrier_blast_slope_uphill_decel_curve != null
	):
		return _sample_curve_by_speed(
			barrier_blast_slope_uphill_decel_curve,
			speed,
			slope_uphill_decel
		)
	return _sample_curve_by_speed(slope_uphill_decel_curve, speed, slope_uphill_decel)


func _apply_surface_resistance(
	current_lateral: Vector3,
	constant_resistance: float,
	linear_drag: float,
	quadratic_drag: float,
	delta: float
) -> Vector3:
	var speed: float = current_lateral.length()
	if speed <= 0.0:
		return Vector3.ZERO
	var resistance: float = max(constant_resistance, 0.0)
	resistance += max(linear_drag, 0.0) * speed
	resistance += max(quadratic_drag, 0.0) * speed * speed
	return current_lateral.move_toward(Vector3.ZERO, resistance * max(delta, 0.0))


func _reset_slope_reversal_guard(clear_debt: bool = true) -> void:
	if clear_debt:
		_slope_reversal_debt = 0.0
	_slope_reversal_uphill_peak_speed = 0.0
	_slope_reversal_previous_uphill_speed = 0.0
	_slope_reversal_air_time = 0.0


func _limit_uphill_motor_velocity(
	entry_lateral: Vector3,
	motor_lateral: Vector3,
	downhill_direction: Vector3,
	slope_angle_deg: float,
	slope_acceleration: Vector3,
	delta: float
) -> Vector3:
	if delta <= 0.0 or downhill_direction.length_squared() < 0.000001:
		return motor_lateral
	var downhill_axis: Vector3 = downhill_direction.normalized()
	var uphill_motor_delta: float = (motor_lateral - entry_lateral).dot(-downhill_axis)
	if uphill_motor_delta <= 0.0:
		return motor_lateral
	var start_angle: float = maxf(slope_uphill_control_ratio_min_angle_deg, 0.0)
	var full_angle: float = maxf(slope_uphill_control_ratio_full_angle_deg, start_angle + 0.001)
	var angle_fraction: float = clampf((slope_angle_deg - start_angle) / (full_angle - start_angle), 0.0, 1.0)
	var full_speed: float = maxf(slope_uphill_control_limit_full_speed, 0.0)
	var release_speed: float = maxf(slope_uphill_control_limit_release_speed, full_speed + 0.001)
	var speed_fraction: float = clampf((entry_lateral.length() - full_speed) / (release_speed - full_speed), 0.0, 1.0)
	var angle_weight: float = _smoothstep_unit(angle_fraction)
	var speed_weight: float = 1.0 - _smoothstep_unit(speed_fraction)
	if angle_weight <= 0.0 or speed_weight <= 0.0:
		return motor_lateral
	var downhill_delta: float = maxf(slope_acceleration.dot(downhill_axis), 0.0) * delta
	var control_ratio: float = clampf(_sample_curve_by_speed(slope_uphill_control_ratio_curve, angle_fraction, 0.5), 0.0, 1.0)
	var allowed_motor_delta: float = downhill_delta * control_ratio
	if uphill_motor_delta <= allowed_motor_delta:
		return motor_lateral
	var acceleration_ratio: float = clampf(uphill_motor_delta / maxf(downhill_delta, 0.000001), 1.0, 4.0)
	var adaptive_response: float = lerpf(1.0, acceleration_ratio, clampf(slope_uphill_control_accel_adaptation, 0.0, 1.0))
	angle_weight = 1.0 - pow(1.0 - angle_weight, adaptive_response)
	var excess_motor_delta: float = uphill_motor_delta - allowed_motor_delta
	return motor_lateral + downhill_axis * excess_motor_delta * angle_weight * speed_weight


func _update_slope_reversal_guard(
	delta: float,
	is_attached: bool,
	has_slope: bool,
	slope_angle_deg: float,
	lateral: Vector3,
	control_direction: Vector3,
	downhill_direction: Vector3,
	bypass_arming: bool
) -> void:
	if not slope_reversal_guard_enabled:
		_reset_slope_reversal_guard()
		return
	var dt: float = max(delta, 0.0)
	if not is_attached:
		_slope_reversal_air_time += dt
		_slope_reversal_uphill_peak_speed = 0.0
		_slope_reversal_previous_uphill_speed = 0.0
		if _slope_reversal_air_time >= max(slope_reversal_guard_air_reset_time, 0.0):
			_slope_reversal_debt = 0.0
		return
	_slope_reversal_air_time = 0.0
	if (
		not has_slope
		or downhill_direction.length() < 0.001
		or slope_angle_deg < max(slope_reversal_guard_min_angle_deg, 0.0)
	):
		_reset_slope_reversal_guard()
		return

	var downhill_axis: Vector3 = downhill_direction.normalized()
	var uphill_speed: float = -lateral.dot(downhill_axis)
	var downhill_speed: float = max(-uphill_speed, 0.0)
	if _slope_reversal_debt > 0.0 and downhill_speed > 0.0:
		var recovery_distance: float = max(slope_reversal_guard_recovery_distance, 0.001)
		_slope_reversal_debt = max(
			_slope_reversal_debt - downhill_speed * dt / recovery_distance,
			0.0
		)

	if bypass_arming:
		_slope_reversal_previous_uphill_speed = uphill_speed
		return

	var uphill_intent: float = 0.0
	var downhill_intent: float = 0.0
	if control_direction.length() > 0.001:
		var control_axis: Vector3 = control_direction.normalized()
		uphill_intent = max(-control_axis.dot(downhill_axis), 0.0)
		downhill_intent = max(control_axis.dot(downhill_axis), 0.0)
	if _slope_reversal_debt <= 0.001 and uphill_intent > 0.0:
		_slope_reversal_uphill_peak_speed = max(
			_slope_reversal_uphill_peak_speed,
			max(uphill_speed, 0.0)
		)

	var arm_speed: float = max(slope_reversal_guard_arm_uphill_speed, 0.0)
	var crossed_into_downhill: bool = (
		_slope_reversal_previous_uphill_speed > 0.1
		and uphill_speed < -0.1
	)
	var deliberate_reversal: bool = downhill_intent >= clamp(
		slope_reversal_guard_turn_alignment,
		0.0,
		1.0
	)
	if (
		_slope_reversal_uphill_peak_speed >= arm_speed
		and (crossed_into_downhill or deliberate_reversal)
	):
		var full_debt_speed: float = max(
			slope_uphill_start_traction_speed,
			max(arm_speed, 0.001)
		)
		var armed_debt: float = clamp(
			_slope_reversal_uphill_peak_speed / full_debt_speed,
			0.0,
			1.0
		)
		_slope_reversal_debt = max(_slope_reversal_debt, armed_debt)
		_slope_reversal_uphill_peak_speed = 0.0
	_slope_reversal_previous_uphill_speed = uphill_speed


func _ease_in_out_sine(t: float) -> float:
	var t_clamped: float = clamp(t, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * t_clamped)


func _slerp_scalar(current: float, target: float, slerp_speed: float, delta: float) -> float:
	if slerp_speed <= 0.0:
		return target
	var t_raw: float = clamp(slerp_speed * delta, 0.0, 1.0)
	var t_ease: float = _ease_in_out_sine(t_raw)
	return lerp(current, target, t_ease)


func _get_drift_input_side(lateral: Vector3, input_dir: Vector3, up_dir: Vector3) -> int:
	var up: Vector3 = up_dir.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var input_planar: Vector3 = input_dir - up * input_dir.dot(up)
	if input_planar.length() < 0.001:
		return 0
	input_planar = input_planar.normalized()

	var reference_dir: Vector3 = lateral - up * lateral.dot(up)
	if reference_dir.length() < 0.001:
		reference_dir = _model_forward - up * _model_forward.dot(up)
	if reference_dir.length() < 0.001:
		return 0
	reference_dir = reference_dir.normalized()

	var side_amount: float = reference_dir.cross(input_planar).dot(up)
	if abs(side_amount) < max(drift_input_deadzone, 0.0):
		return 0
	if side_amount > 0.0:
		return 1
	return -1


func _is_surface_alignment_blocked(collider: Object) -> bool:
	var alignment_exclusion_mask: int = non_alignable_surface_mask | attack_pass_through_surface_mask
	if collider == null or alignment_exclusion_mask == 0:
		return false

	var collider_layer: int = 0
	if collider is CollisionObject3D:
		collider_layer = (collider as CollisionObject3D).collision_layer
	elif _object_has_property(collider, "collision_layer"):
		collider_layer = int(collider.get("collision_layer"))
	else:
		return false

	return (collider_layer & alignment_exclusion_mask) != 0


func _is_surface_alignment_rejected(
	collider: Object,
	normal: Vector3,
	gravity_up: Vector3,
	collider_shape_index: int = -1
) -> bool:
	if _is_surface_alignment_blocked(collider):
		return true

	var attach_limit_deg: float = _get_surface_attach_max_angle_deg(
		collider,
		collider_shape_index
	)
	if attach_limit_deg < 0.0:
		return false
	if attach_limit_deg <= 0.001:
		return true

	var surface_normal: Vector3 = normal.normalized()
	var resolved_up: Vector3 = gravity_up.normalized()
	if surface_normal.length() < 0.001 or resolved_up.length() < 0.001:
		return false

	var surface_angle_deg: float = rad_to_deg(
		acos(clamp(surface_normal.dot(resolved_up), -1.0, 1.0))
	)
	return surface_angle_deg > attach_limit_deg + 0.001


func _get_surface_attach_max_angle_deg(
	collider: Object,
	collider_shape_index: int = -1
) -> float:
	var value: Variant = _get_surface_metadata_value(
		collider,
		SURFACE_ATTACH_MAX_ANGLE_META,
		collider_shape_index
	)
	var limit: float = clampf(float(value), 0.0, 180.0) if value is int or value is float else -1.0
	for area_reference: WeakRef in _active_surface_behavior_areas.values():
		var area: Object = area_reference.get_ref()
		if not is_instance_valid(area):
			continue
		var area_limit: Variant = _get_surface_metadata_value(area, SURFACE_ATTACH_MAX_ANGLE_META)
		if area_limit is int or area_limit is float:
			var angle: float = clampf(float(area_limit), 0.0, 180.0)
			limit = angle if limit < 0.0 else minf(limit, angle)
	return limit


func _get_surface_metadata_value(
	collider: Object,
	metadata_key: StringName,
	collider_shape_index: int = -1
) -> Variant:
	return SURFACE_METADATA.get_value(collider, metadata_key, collider_shape_index)


func _surface_metadata_bool(
	collider: Object,
	metadata_key: StringName,
	collider_shape_index: int = -1
) -> bool:
	var value: Variant = _get_surface_metadata_value(
		collider,
		metadata_key,
		collider_shape_index
	)
	return value != null and bool(value)


func _active_surface_area_has_behavior(metadata_key: StringName) -> bool:
	for area_id: Variant in _active_surface_behavior_areas.keys():
		var area_reference: WeakRef = _active_surface_behavior_areas[area_id]
		var area: Object = area_reference.get_ref() if area_reference != null else null
		if area == null or not is_instance_valid(area):
			_active_surface_behavior_areas.erase(area_id)
			continue
		if _surface_metadata_bool(area, metadata_key):
			return true
	return false


func _current_surface_has_behavior(metadata_key: StringName) -> bool:
	if bool(_surface_contact_behaviors.get(metadata_key, false)):
		return true
	if (
		_follow_collider_last != null
		and is_instance_valid(_follow_collider_last)
		and _surface_metadata_bool(
			_follow_collider_last,
			metadata_key,
			_follow_collider_shape_last
		)
	):
		return true
	return _active_surface_area_has_behavior(metadata_key)


func _recent_surface_has_behavior(metadata_key: StringName) -> bool:
	if _current_surface_has_behavior(metadata_key):
		return true
	if (
		_follow_collider_prev != null
		and is_instance_valid(_follow_collider_prev)
		and _surface_metadata_bool(
			_follow_collider_prev,
			metadata_key,
			_follow_collider_shape_prev
		)
	):
		return true
	return false


func is_surface_jump_blocked() -> bool:
	return _current_surface_has_behavior(SURFACE_NO_JUMP_META)


func is_surface_coyote_jump_blocked() -> bool:
	return (
		_recent_surface_has_behavior(SURFACE_NO_JUMP_META)
		or _recent_surface_has_behavior(SURFACE_NO_COYOTE_JUMP_META)
	)


func is_surface_roll_forced() -> bool:
	return _current_surface_has_behavior(SURFACE_FORCE_ROLL_META)


func is_surface_cling_forced() -> bool:
	return _current_surface_has_behavior(SURFACE_METADATA.FORCE_CLING)


func is_surface_roll_blocked() -> bool:
	return not is_surface_roll_forced() and _current_surface_has_behavior(SURFACE_NO_ROLL_META)


func is_surface_drift_blocked() -> bool:
	return _current_surface_has_behavior(SURFACE_NO_DRIFT_META)


func _surface_ignores_slope_gravity() -> bool:
	return _current_surface_has_behavior(SURFACE_NO_SLOPE_GRAVITY_META)


func _surface_prevents_detach(
	collider: Object = null,
	collider_shape_index: int = -1
) -> bool:
	if collider != null and _surface_metadata_bool(
		collider,
		SURFACE_NO_DETACH_META,
		collider_shape_index
	):
		return true
	return _active_surface_area_has_behavior(SURFACE_NO_DETACH_META)


func _surface_launch_adhesion_active() -> bool:
	if _automation_force_surface_adhesion:
		return true
	if _follow_collider_last != null and is_instance_valid(_follow_collider_last):
		return (
			_surface_metadata_bool(
				_follow_collider_last,
				SURFACE_STICKY_META,
				_follow_collider_shape_last
			)
			or _active_surface_area_has_behavior(SURFACE_STICKY_META)
		)
	return _recent_surface_has_behavior(SURFACE_STICKY_META)


func enter_surface_behavior_area(area: Area3D) -> void:
	if area == null or not is_instance_valid(area):
		return
	if not _network_is_local_authority():
		return
	if _active_surface_behavior_areas.has(area.get_instance_id()):
		return
	_active_surface_behavior_areas[area.get_instance_id()] = weakref(area)
	_process_surface_contact_behavior(area)


func exit_surface_behavior_area(area: Area3D) -> void:
	if area == null:
		return
	_active_surface_behavior_areas.erase(area.get_instance_id())


func _process_surface_contact_behavior(
	collider: Object,
	collider_shape_index: int = -1
) -> void:
	if collider == null or not _network_is_local_authority():
		return
	var source: Node = collider as Node if collider is Node else null
	if _surface_metadata_bool(collider, SURFACE_DEATH_META, collider_shape_index):
		apply_death_plane_damage(source)
		return

	var damage_value: Variant = _get_surface_metadata_value(
		collider,
		SURFACE_DAMAGE_AMOUNT_META,
		collider_shape_index
	)
	if damage_value is int or damage_value is float:
		var damage_amount: int = max(int(damage_value), 0)
		if damage_amount > 0:
			apply_damage(damage_amount, source)

	var blocks_jump: bool = _surface_metadata_bool(
		collider,
		SURFACE_NO_JUMP_META,
		collider_shape_index
	)
	var blocks_coyote_jump: bool = blocks_jump or _surface_metadata_bool(
		collider,
		SURFACE_NO_COYOTE_JUMP_META,
		collider_shape_index
	)
	if blocks_jump:
		_jump_requested = false
	if blocks_coyote_jump:
		_coyote_jump_requested = false
		_clear_coyote_jump_window()
	if _surface_metadata_bool(collider, SURFACE_FORCE_ROLL_META, collider_shape_index):
		_force_surface_roll()
	if not is_surface_roll_forced() and _surface_metadata_bool(collider, SURFACE_NO_ROLL_META, collider_shape_index):
		_end_surface_roll()
	if _surface_metadata_bool(collider, SURFACE_NO_DRIFT_META, collider_shape_index):
		_reset_drift_state()


func _refresh_surface_behavior_areas(start_position: Vector3, sweep_motion: bool = false) -> void:
	if not _network_is_local_authority():
		return
	var contacts: Dictionary = ImportedSurfaceBehaviorArea.collect_body_contacts(self, start_position, sweep_motion)
	var overlaps: Dictionary = contacts["overlaps"]
	var crossed: Dictionary = contacts["crossed"]
	for area: Area3D in crossed.values():
		ImportedSurfaceBehaviorArea.notify_entered(area, self)
	for area: Area3D in overlaps.values():
		ImportedSurfaceBehaviorArea.notify_entered(area, self)
	for area_id: Variant in _active_surface_behavior_areas.keys():
		var area_reference: WeakRef = _active_surface_behavior_areas[area_id]
		var area: Area3D = area_reference.get_ref() as Area3D
		if not is_instance_valid(area):
			_active_surface_behavior_areas.erase(area_id)
		elif ImportedSurfaceBehaviorArea.is_behavior_area(area) and not overlaps.has(area_id):
			ImportedSurfaceBehaviorArea.notify_exited(area, self)


func _record_surface_contact_behaviors(collider: Object, shape_index: int) -> void:
	for metadata_key: StringName in SURFACE_METADATA.get_all_keys():
		if _surface_metadata_bool(collider, metadata_key, shape_index):
			_surface_contact_behaviors[metadata_key] = true


func _process_slide_collision_surface_behaviors() -> void:
	_surface_contact_behaviors.clear()
	var contacts: Array[Dictionary] = []
	if not _movement_sphere_contact.is_empty():
		contacts.append({
			"collider": instance_from_id(int(_movement_sphere_contact.collider_id)),
			"shape": int(_movement_sphere_contact.shape),
		})
	for collision_index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(collision_index)
		if collision:
			contacts.append({"collider": collision.get_collider(), "shape": collision.get_collider_shape_index()})
	for contact: Dictionary in contacts:
		_record_surface_contact_behaviors(contact["collider"], int(contact["shape"]))
	for contact: Dictionary in contacts:
		_process_surface_contact_behavior(contact["collider"], int(contact["shape"]))
		if _is_dead:
			return
	if is_surface_roll_forced():
		_force_surface_roll()
	elif is_surface_roll_blocked():
		_end_surface_roll()
	if is_surface_drift_blocked():
		_reset_drift_state()


func _force_surface_roll() -> void:
	if _roll_action != null and is_instance_valid(_roll_action):
		if _roll_action.has_method("force_start_from_surface"):
			_roll_action.call("force_start_from_surface")
			_sync_roll_state_from_action()
		return
	if not rolling and roll_enabled and _can_start_roll():
		rolling = true
		_notify_buddy_leader_roll_changed(true)


func _end_surface_roll() -> void:
	if _roll_action != null and is_instance_valid(_roll_action):
		if _roll_action.has_method("_end_roll_if_active"):
			_roll_action.call("_end_roll_if_active")
		_sync_roll_state_from_action()
		return
	if rolling:
		rolling = false
		_notify_buddy_leader_roll_changed(false)


# ===========================================================
# COLLISION-BASED ATTACHMENT
# ===========================================================
func _process_collisions_for_attachment(v_before: Vector3, p_before: Vector3, delta: float) -> void:
	_ensure_modules()
	_surface_module._process_collisions_for_attachment(v_before, p_before, delta)

func _try_ground_snap_attach(world_up: Vector3, v_before: Vector3 = Vector3.ZERO, p_before: Vector3 = Vector3.ZERO) -> void:
	_ensure_modules()
	_surface_module._try_ground_snap_attach(world_up, v_before, p_before)

func _reconcile_grounded_state_after_move(world_up: Vector3) -> void:
	_ensure_modules()
	_surface_module._reconcile_grounded_state_after_move(world_up)

func _try_rail_path_snap_attach(v_before: Vector3 = Vector3.ZERO, p_before: Vector3 = Vector3.ZERO) -> void:
	_ensure_modules()
	_rail_module._try_rail_path_snap_attach(v_before, p_before)

func _get_rail_path_snap_radius(speed: float = -1.0) -> float:
	_ensure_modules()
	return _rail_module._get_rail_path_snap_radius(speed)

func _is_rail_path_snap_obstructed(query_point: Vector3, rail_point: Vector3) -> bool:
	_ensure_modules()
	return _rail_module._is_rail_path_snap_obstructed(query_point, rail_point)

func _get_ground_ray_hit_ignoring_water_surface() -> Dictionary:
	_ensure_modules()
	return _surface_module._get_ground_ray_hit_ignoring_water_surface()

func _can_attach_from_collision(
	v_before: Vector3,
	normal: Vector3,
	world_up: Vector3,
	hit_point: Vector3 = Vector3.ZERO,
	collider: Object = null,
	collider_velocity: Vector3 = Vector3.ZERO
) -> bool:
	_ensure_modules()
	return _surface_module._can_attach_from_collision(
		v_before,
		normal,
		world_up,
		hit_point,
		collider,
		collider_velocity
	)

func _preserve_rejected_collision_slide(
	incoming_velocity: Vector3,
	normal: Vector3,
	world_up: Vector3
) -> void:
	_ensure_modules()
	_surface_module._preserve_rejected_collision_slide(incoming_velocity, normal, world_up)

func _get_surface_angle_deg(normal: Vector3, world_up: Vector3) -> float:
	_ensure_modules()
	return _surface_module._get_surface_angle_deg(normal, world_up)

func _start_low_speed_detach_reattach_block(surface_angle_deg: float) -> void:
	_ensure_modules()
	_surface_module._start_low_speed_detach_reattach_block(surface_angle_deg)

func _is_low_speed_detach_reattach_blocked(normal: Vector3, world_up: Vector3) -> bool:
	_ensure_modules()
	return _surface_module._is_low_speed_detach_reattach_blocked(normal, world_up)

func _passes_floor_wall_exception(new_normal: Vector3, world_up: Vector3) -> bool:
	_ensure_modules()
	return _surface_module._passes_floor_wall_exception(new_normal, world_up)

# ===========================================================
# GROUND FOLLOW WHILE ATTACHED
# ===========================================================
func _is_plain_rigid_body(node) -> bool:
	_ensure_modules()
	return _surface_module._is_plain_rigid_body(node)

func _ground_follow_probe(delta: float) -> void:
	_ensure_modules()
	_surface_module._ground_follow_probe(delta)

func _smooth_surface_normal(prev: Vector3, raw: Vector3, delta: float) -> Vector3:
	_ensure_modules()
	return _surface_module._smooth_surface_normal(prev, raw, delta)

func _update_attachment_state_after_move(delta: float) -> void:
	_ensure_modules()
	_surface_module._update_attachment_state_after_move(delta)

# --------------------------------------------------
# Can we stay attached to 'detach_normal' this frame?
# --------------------------------------------------
func _can_stay_attached(
	smoothed_normal: Vector3,
	world_up: Vector3,
	collider: Object = null,
	collider_shape_index: int = -1
) -> bool:
	_ensure_modules()
	return _surface_module._can_stay_attached(
		smoothed_normal,
		world_up,
		collider,
		collider_shape_index
	)

func _start_detach(detach_normal: Vector3, world_up: Vector3) -> void:
	_ensure_modules()
	_surface_module._start_detach(detach_normal, world_up)

func _get_filtered_detach_normal(detach_normal: Vector3, world_up: Vector3) -> Vector3:
	_ensure_modules()
	return _surface_module._get_filtered_detach_normal(detach_normal, world_up)

func _apply_wall_slide_and_friction(
	normal: Vector3,
	physics_up: Vector3,
	world_up: Vector3,
	delta: float,
	reference_velocity: Vector3 = Vector3.ZERO
) -> void:
	_ensure_modules()
	_surface_module._apply_wall_slide_and_friction(normal, physics_up, world_up, delta, reference_velocity)

# ===========================================================
# RAMP / LOOP LAUNCH
# ===========================================================
func _apply_launch_from_surface(detach_normal: Vector3, world_up: Vector3) -> void:
	_ensure_modules()
	_surface_module._apply_launch_from_surface(detach_normal, world_up)

# ===========================================================
# MOVEMENT / SLOPE PHYSICS
# ===========================================================
func _apply_movement(delta: float, up_for_physics: Vector3, is_attached: bool) -> void:
	var timer_delta: float = get_gameplay_timer_delta(delta)
	var physics_up: Vector3 = up_for_physics.normalized()
	if physics_up.length() < 0.001:
		physics_up = _get_gravity_up()

	if _is_dead and is_attached:
		velocity = Vector3.ZERO
		_move_input = Vector2.ZERO
		_move_direction = Vector3.ZERO
		_last_air_velocity = Vector3.ZERO
		_reset_movement_release_deceleration()
		return
	if _current_action_blocks_shared_movement_integration():
		if not is_attached:
			_last_air_velocity = velocity
		_reset_movement_release_deceleration()
		return

	var world_up: Vector3 = _get_gravity_up()

	var run_top_speed_used: float = run_top_speed
	var ground_accel_curve_used: Curve = ground_accel_curve
	var ground_turn_angle_curve_used: Curve = ground_turn_angle_curve

	var barrier_speed_boost: bool = _barrier_blast_active or (rolling and _barrier_blast_gauge >= 1.0)
	if barrier_speed_boost:
		if barrier_blast_run_top_speed > 0.0:
			run_top_speed_used = barrier_blast_run_top_speed
		if barrier_blast_ground_accel_curve != null:
			ground_accel_curve_used = barrier_blast_ground_accel_curve
		if barrier_blast_ground_turn_angle_curve != null:
			ground_turn_angle_curve_used = barrier_blast_ground_turn_angle_curve

	# Water physics multipliers (applied on top of current values).
	var water_accel_mult: float = 1.0
	var water_decel_mult: float = 1.0
	var water_top_speed_mult: float = 1.0
	var in_water_movement_physics: bool = water_physics_enabled and not water_logic_speed_enabled and _in_water_volume and not _running_on_water_surface
	var in_submerged_vertical_physics: bool = water_physics_enabled and not water_logic_speed_enabled and _fully_submerged and not _running_on_water_surface
	if _automation_active and _automation_ignore_water_physics:
		in_water_movement_physics = false
		in_submerged_vertical_physics = false
	if in_water_movement_physics:
		water_accel_mult = water_accel_multiplier
		water_decel_mult = water_decel_multiplier
		water_top_speed_mult = water_top_speed_multiplier

	# Walk input overrides ground speed/accel while attached.
	if is_attached and _walk_input_held:
		run_top_speed_used = max(walk_top_speed, 0.0)
		if walk_ground_accel_curve != null:
			ground_accel_curve_used = walk_ground_accel_curve
		if walk_turn_angle_curve != null:
			ground_turn_angle_curve_used = walk_turn_angle_curve
	ground_accel_curve_used = _get_active_acceleration_curve(ground_accel_curve_used)

	if is_attached:
		_last_grounded_top_speed = max(run_top_speed_used, 0.0)

	# Spring state flag
	var in_spring_state: bool = _spring_align_timer > 0.0
	var in_race_countdown: bool = race_in_countdown and not race_active and not race_finished

	# Spring detach uses gravity-up as the physics frame.
	if in_spring_state and _spring_detached:
		physics_up = world_up
		_bounce_state = BounceState.NONE

	var v: Vector3 = velocity
	var vertical: float = v.dot(physics_up)
	var lateral: Vector3 = v - physics_up * vertical

	_homing_retain_timer = max(_homing_retain_timer - timer_delta, 0.0)
	_automation_timer = max(_automation_timer - timer_delta, 0.0)
	_automation_expired_this_frame = false
	if _automation_timer <= 0.0:
		_automation_expired_this_frame = true
	var ground_decel_effective: float = max(_sample_curve_by_speed(
		ground_decel_curve,
		lateral.length(),
		decel
	), 0.0)
	var gravity_horizontal_velocity: Vector3 = v - world_up * v.dot(world_up)
	var air_decel_base: float = max(_sample_curve_by_speed(
		air_decel_curve,
		gravity_horizontal_velocity.length(),
		air_decel
	), 0.0)
	# Effective air decel (ramps in after walking off a surface).
	var air_decel_effective: float = _get_fall_off_air_decel(delta, air_decel_base)
	if _hurt_active:
		air_decel_effective *= clamp(hurt_air_decel_multiplier, 0.0, 1.0)
	# Effective air top speed (delay + slerp after detaching).
	var air_top_speed_effective: float = _get_effective_air_top_speed(delta, is_attached)
	var item_top_speed_multiplier: float = get_active_top_speed_multiplier()
	run_top_speed_used *= item_top_speed_multiplier
	air_top_speed_effective *= item_top_speed_multiplier

	# --------------------------------------------------
	# LIGHTSPEED DASH OVERRIDE
	# --------------------------------------------------
	if _lightspeed_dash_active:
		# Clear input movement to prevent any normal movement during dash
		_move_input = Vector2.ZERO
		_walk_input_held = false
		_reset_drift_state()
		_update_lightspeed_dash(delta, physics_up)
		_last_air_velocity = velocity
		return

	# --------------------------------------------------
	# HOMING OVERRIDE / START (triggered via jump-dash)
	# --------------------------------------------------
	if _homing_active:
		_reset_drift_state()
		_update_homing(delta, physics_up, is_attached)
		_last_air_velocity = velocity
		return

	if _jump_dash_requested and _automation_lock_actions and _automation_locks_active():
		_jump_dash_requested = false
		_clear_homing_target_request_buffer()

	var homing_request_status: Dictionary = {}
	if _jump_dash_requested and not is_attached and _can_consume_coyote_jump():
		var should_redirect_jump_dash_to_coyote: bool = not coyote_jump_homing_priority or not _can_scan_homing_targets()
		if coyote_jump_homing_priority and _can_scan_homing_targets():
			var coyote_speed: float = velocity.length()
			var coyote_range: float = homing_min_range + coyote_speed * homing_range_per_speed
			coyote_range = clamp(coyote_range, homing_min_range, homing_max_range)
			homing_request_status = _get_homing_target_request_status(global_position, coyote_range, true)
			if bool(homing_request_status.get("ready", false)):
				should_redirect_jump_dash_to_coyote = not (homing_request_status.get("target") is Node3D)
		if should_redirect_jump_dash_to_coyote:
			_jump_dash_requested = false
			_coyote_jump_requested = true
			_jump_requested = true

	if _jump_dash_requested:
		var waiting_for_target_scan: bool = false
		# Try homing first when airborne.
		if _can_scan_homing_targets() and not is_attached:
			var up: Vector3 = physics_up.normalized()
			if up.length() < 0.001:
				up = _get_gravity_up()

			var spd_now: float = velocity.length()
			var max_range: float = homing_min_range + spd_now * homing_range_per_speed
			max_range = clamp(max_range, homing_min_range, homing_max_range)

			if homing_request_status.is_empty():
				homing_request_status = _get_homing_target_request_status(global_position, max_range, true)
			if not bool(homing_request_status.get("ready", false)):
				waiting_for_target_scan = true
			var t: Node3D = homing_request_status.get("target") as Node3D
			if not waiting_for_target_scan and t != null:
				_homing_active = true
				_homing_target = t
				_homing_target_position = _get_homing_candidate_position(t, global_position)
				_homing_target_position_valid = _is_rail_like_homing_target(t)
				_homing_elapsed = 0.0
				_homing_saved_velocity = velocity
				_homing_saved_speed_mag = velocity.length()
				_homing_saved_lateral = velocity - up * velocity.dot(up)
				var to_target: Vector3 = _homing_target_position - global_position
				var target_dist: float = to_target.length()
				if target_dist > 0.001:
					velocity = (to_target / target_dist) * max(homing_speed, velocity.length())
				_jump_dash_used_this_air = true
				_jump_dash_recent_timer = jump_dash_recent_time
				play_jumpdash_sfx()
				_jump_dash_requested = false
				_jump_requested = false
				_coyote_jump_requested = false
				_clear_coyote_jump_window()
				_reset_drift_state()
				_update_homing(delta, physics_up, false)
				_last_air_velocity = velocity
				return

		# Fallback to normal jump dash impulse.
		if not waiting_for_target_scan:
			lateral = _perform_jump_dash(physics_up, is_attached, lateral)
			_jump_dash_requested = false
	
# ===========================
# DEBUG: Add local forward speed boost
# ===========================
	if SettingsManager.is_gameplay_action_just_pressed("debug_boost_forward"):
		var up: Vector3 = physics_up.normalized()
		var forward: Vector3 = _model_forward - up * _model_forward.dot(up)   # project to local plane
		if forward.length() < 0.001:
			forward = Vector3.FORWARD    # fallback

		forward = forward.normalized()
		lateral += forward * debug_forward_boost_amount


	# --------------------------------------------------
	# SPRING OVERRIDE: no local steering / slopes / skid
	# --------------------------------------------------
	if in_spring_state and _spring_detached:
		_reset_drift_state()
		# Apply gravity along gravity-down while in spring.
		var gravity_scale: float = spring_gravity_scale
		if _drowned_action == null or not _drowned_action.is_drowned():
			vertical -= get_effective_gravity_strength() * gravity_scale * delta

		# Apply water vertical speed limits (multipliers on base speeds)
		if in_submerged_vertical_physics:
			vertical = _apply_water_vertical_speed_slowdown(vertical, delta)
		else:
			if vertical < -max_fall_speed:
				vertical = -max_fall_speed

		var v_final: Vector3 = lateral + physics_up * vertical

		# Lock velocity along spring direction if requested
		if _spring_align_dir.length() > 0.001 and _spring_lock_sideways:
			var dir: Vector3 = _spring_align_dir.normalized()
			var along_speed: float = v_final.dot(dir)
			var v_along: Vector3 = dir * along_speed
			var v_side: Vector3 = v_final - v_along

			if _spring_sideways_gravity_scale <= 0.0:
				v_final = v_along
			else:
				v_final = v_along + v_side * _spring_sideways_gravity_scale

		velocity = v_final
		_last_air_velocity = v_final
		return

	# --------------------------------------------------
	# Slope information (only when attached)
	# --------------------------------------------------
	var slope_angle_deg: float = 0.0
	var has_slope: bool = false
	var downhill_dir: Vector3 = Vector3.ZERO
	var slope_gravity: Vector3 = Vector3.ZERO
	var slope_speed_factor: float = 0.0

	if is_attached and surface_normal.length() > 0.001:
		var surf_n: Vector3 = surface_normal.normalized()

		# Angle vs gravity-up.
		# 0°   = floor
		# 90°  = vertical wall
		# 180° = ceiling
		var cos_up: float = clamp(surf_n.dot(world_up), -1.0, 1.0)
		slope_angle_deg = rad_to_deg(acos(cos_up))

		# Downhill direction follows resolved gravity projected onto the contact plane.
		var g: Vector3 = -world_up * get_effective_gravity_strength()
		var g_tangent: Vector3 = g - surf_n * g.dot(surf_n)
		var g_len: float = g_tangent.length()
		if g_len > 0.001:
			downhill_dir = g_tangent / g_len
			var near_flat_fade: float = 1.0
			var full_response_angle: float = max(slope_flat_angle_threshold_deg, 0.0)
			if full_response_angle > 0.001:
				near_flat_fade = _smoothstep_unit(slope_angle_deg / full_response_angle)
			slope_gravity = g_tangent * near_flat_fade
			has_slope = slope_gravity.length() > 0.001
			var effective_gravity: float = max(get_effective_gravity_strength(), 0.0)
			if effective_gravity > 0.001:
				slope_speed_factor = clamp(g_len / effective_gravity, 0.0, 1.0)

	# --------------------------------------------------
	# Loop surface classification WITH HYSTERESIS (Godot 4.5 safe)
	# --------------------------------------------------
	var is_loop_surface: bool = false

	if attached and surface_normal.length() > 0.001:
		var n: Vector3 = surface_normal.normalized()
		var dot_w: float = clamp(n.dot(world_up), -1.0, 1.0)
		var surf_angle: float = rad_to_deg(acos(dot_w))

		# Enter loop mode at steep angle
		var enter_deg: float = loop_input_steep_angle_deg        # e.g. 90
		# Exit loop mode at a noticeably lower angle (prevents jitter at 90°)
		var exit_deg: float = max(loop_input_steep_angle_deg - 15.0, 0.0)

		if _loop_sticky:
			# Stay in loop mode until angle gets comfortably below exit threshold
			_loop_sticky = surf_angle >= exit_deg
		else:
			# Enter loop mode when angle exceeds the steep threshold
			_loop_sticky = surf_angle >= enter_deg

		is_loop_surface = _loop_sticky
	else:
		_loop_sticky = false

	# --------------------------------------------------
	# Update loop forward direction from lateral motion
	# --------------------------------------------------
	if is_attached and is_loop_surface:
		var lat_speed: float = lateral.length()
		if lat_speed > 0.1:
			_loop_forward_dir = (lateral / lat_speed)

	_update_control_basis(physics_up, is_attached, is_loop_surface, lateral)
	_compute_move_direction()
	for action in _actions:
		if action != null and is_instance_valid(action):
			_move_direction = action.influence_movement_input(_move_direction, world_up)
	_apply_wall_input_projection(physics_up, is_attached, timer_delta)
	var auto_active: bool = _automation_active and _automation_timer > 0.0
	if auto_active and _automation_grounded_only and not is_attached:
		auto_active = false
	var max_speed_override_state: Dictionary = _get_max_speed_override_state(auto_active)
	var max_speed_override_active: bool = bool(max_speed_override_state.get("active", false))
	var max_speed_limit_for_motion: float = max(max_speed, 0.0)
	if max_speed_override_active:
		max_speed_limit_for_motion = float(max_speed_override_state.get("target", 0.0))
	var automation_25d_active: bool = (
		auto_active
		and _automation_mode == AutomationSplineMode.TWO_POINT_FIVE_D
	)
	var movement_input_strength: float = clamp(_move_input.length(), 0.0, 1.0)
	for action in _actions:
		if action != null and is_instance_valid(action):
			movement_input_strength *= clamp(action.get_movement_input_strength_multiplier(), 0.0, 1.0)
	if automation_25d_active:
		movement_input_strength = _apply_automation_25d_input_mapping(physics_up)
	var continuous_trick_input_active: bool = (
		_left_stick_trick_momentum_active
		and _uses_left_stick_trick_controls()
		and SettingsManager.left_stick_trick_movement
		== SettingsManager.LEFT_STICK_TRICK_MOVEMENT_LAST_INPUT
	)
	if continuous_trick_input_active:
		var gravity_up_for_continuous_input: Vector3 = _get_gravity_up()
		var retained_move_direction: Vector3 = _left_stick_trick_last_input_direction.slide(
			gravity_up_for_continuous_input
		)
		if retained_move_direction.length_squared() >= 0.001:
			_move_direction = retained_move_direction.normalized()
			movement_input_strength = clampf(
				_left_stick_trick_last_input_strength,
				0.0,
				1.0
			)
	if (
		_uses_left_stick_trick_controls()
		and not _left_stick_trick_momentum_active
		and _move_direction.length_squared() >= 0.001
	):
		var gravity_up_for_trick_input: Vector3 = _get_gravity_up()
		var continuous_input_direction: Vector3 = velocity.slide(gravity_up_for_trick_input)
		if continuous_input_direction.length_squared() < 0.001:
			continuous_input_direction = _move_direction.slide(gravity_up_for_trick_input)
		if continuous_input_direction.length_squared() >= 0.001:
			_left_stick_trick_last_input_direction = continuous_input_direction.normalized()
			_left_stick_trick_last_input_strength = movement_input_strength
	_update_spindash_direction_latch(physics_up)

	# --------------------------------------------------
	# DRIFT STATE (ground-only, slope uses gravity-up angle)
	# --------------------------------------------------
	var lateral_speed_for_drift: float = lateral.length()
	var drift_input_side_for_state: int = _get_drift_input_side(lateral, _move_direction, physics_up)
	var drift_input_strength_for_state: float = movement_input_strength
	_update_drift_state(
		is_attached,
		slope_angle_deg,
		lateral_speed_for_drift,
		_drift_turn_speed_last,
		drift_input_side_for_state,
		drift_input_strength_for_state,
		timer_delta
	)

	#var has_input: bool = _move_direction != Vector3.ZERO
	if is_instance_valid(_drift_action):
		_drift_action.update_straight_line_slowdown(lateral, physics_up, timer_delta)
	
	# Use raw input to decide if the player is *trying* to move
	var has_input: bool = movement_input_strength > 0.001
	var is_rolling: bool = rolling and roll_enabled
	var is_spindash_charging: bool = _spindash_charging and spindash_enabled
	var spindash_release_now: bool = _spindash_release_requested and is_attached

	# --------------------------------------------------
	# AUTOMATION SPLINE: optional movement lock + rotation align
	# --------------------------------------------------
	if auto_active and _automation_tangent_dir.length() > 0.001:
		var auto_dir: Vector3 = _automation_tangent_dir
		auto_dir -= physics_up * auto_dir.dot(physics_up)
		if auto_dir.length() > 0.001:
			auto_dir = auto_dir.normalized()
			if _automation_lock_movement:
				has_input = false
				movement_input_strength = 0.0
			if _automation_align_rotation and not automation_25d_active:
				_move_direction = auto_dir

	if not is_attached and not in_spring_state and not auto_active:
		_ensure_directional_influence_lock_for_recent_detach(world_up)
	_update_directional_influence_lock(timer_delta, is_attached, in_spring_state, auto_active)

	# Rolling has no acceleration and should not engage skid logic.
	if is_rolling:
		has_input = false
	if is_spindash_charging:
		has_input = false
	if spindash_release_now:
		has_input = false
	if _drift_active and is_attached and not in_spring_state:
		has_input = true

	# --------------------------------------------------
	# SPRING OVERRIDE FOR LATERAL (no steering while in spring)
	# --------------------------------------------------
	if in_spring_state:
		has_input = false
	else:
		# --------------------------------------------------
		# SKID STATE UPDATE (ground-only, uses enter/exit speeds)
		# --------------------------------------------------
		if _wall_input_projection_active or _wall_input_push_active:
			_is_skidding = false
		elif _drift_active:
			# Drift owns course correction; don't allow skid to fight it.
			_is_skidding = false
		elif not is_attached or not has_input:
			_is_skidding = false
		else:
			var skid_allowed: bool = slope_angle_deg <= skid_max_ground_angle_deg

			if skid_allowed:
				var lateral_speed: float = lateral.length()
				if lateral_speed >= skid_enter_min_speed or _is_skidding:
					var vel_dir: Vector3 = lateral.normalized()

					var move_dir: Vector3 = _move_direction
					if move_dir.length() > 0.0001:
						move_dir -= physics_up * move_dir.dot(physics_up)
						if move_dir.length() > 0.0001:
							move_dir = move_dir.normalized()
						else:
							move_dir = vel_dir
					else:
						move_dir = vel_dir

					var dot_dir: float = clamp(vel_dir.dot(move_dir), -1.0, 1.0)
					var angle_deg: float = rad_to_deg(acos(dot_dir))

					if not _is_skidding:
						if lateral_speed >= skid_enter_min_speed and angle_deg >= skid_enter_angle_deg:
							_is_skidding = true
					else:
						if angle_deg <= skid_exit_angle_deg or lateral_speed <= skid_exit_min_speed:
							_is_skidding = false
				else:
					_is_skidding = false
			else:
				_is_skidding = false
	
	# --------------------------------------------------
	# Input-based lateral movement
	# --------------------------------------------------
	var movement_input_active: bool = movement_input_strength > 0.001
	var slope_control_direction: Vector3 = Vector3.ZERO
	if movement_input_active:
		slope_control_direction = _move_direction - physics_up * _move_direction.dot(physics_up)
		if slope_control_direction.length() > 0.001:
			slope_control_direction = slope_control_direction.normalized()
		else:
			slope_control_direction = Vector3.ZERO
	var sticky_surface_active: bool = (
		is_attached
		and (
			_current_surface_has_behavior(SURFACE_STICKY_META)
			or _current_surface_has_behavior(SURFACE_NO_DETACH_META)
		)
	)
	var sticky_brake_input_active: bool = (
		sticky_surface_active
		and movement_input_active
		and lateral.length() > 0.001
		and slope_control_direction.length() > 0.001
		and slope_control_direction.dot(lateral.normalized()) < 0.0
	)
	var sticky_idle_deceleration_active: bool = (
		sticky_surface_active
		and (not movement_input_active or is_spindash_charging)
		and not auto_active
		and not in_spring_state
		and not _hurt_active
		and not _drift_active
		and not _drift_exit_active
	)
	var sticky_deceleration_active: bool = (
		sticky_idle_deceleration_active
		or (
			sticky_brake_input_active
			and not auto_active
			and not in_spring_state
			and not _hurt_active
			and not _drift_active
			and not _drift_exit_active
		)
	)
	var slope_reversal_guard_bypass: bool = (
		is_rolling
		or auto_active
		or in_spring_state
		or _hurt_active
		or is_spindash_charging
		or _drift_active
		or _drift_exit_active
		or _wall_input_projection_active
		or _wall_input_push_active
	)
	_update_slope_reversal_guard(
		delta,
		is_attached,
		has_slope,
		slope_angle_deg,
		lateral,
		slope_control_direction,
		downhill_dir,
		slope_reversal_guard_bypass
	)
	var slope_control_uphill_alignment: float = 0.0
	if slope_control_direction.length() > 0.001 and downhill_dir.length() > 0.001:
		slope_control_uphill_alignment = max(
			-slope_control_direction.dot(downhill_dir.normalized()),
			0.0
		)
	var slope_reversal_guard_control_weight: float = 0.0
	if not slope_reversal_guard_bypass and slope_control_uphill_alignment > 0.0:
		var momentum_preserve_speed: float = max(
			slope_reversal_guard_momentum_preserve_speed,
			0.001
		)
		var low_speed_weight: float = 1.0 - _smoothstep_unit(
			lateral.length() / momentum_preserve_speed
		)
		slope_reversal_guard_control_weight = (
			clamp(_slope_reversal_debt, 0.0, 1.0)
			* slope_control_uphill_alignment
			* low_speed_weight
		)
	var grounded_motor_accel_used: float = 0.0
	var passive_slope_context: bool = (
		is_attached
		and has_slope
		and not movement_input_active
		and not is_rolling
		and not auto_active
		and not in_spring_state
		and not _hurt_active
		and not is_spindash_charging
		and not _drift_active
		and not _drift_exit_active
	)
	if sticky_surface_active:
		_slope_passive_sliding = false
	elif not passive_slope_context:
		_slope_passive_sliding = false
	else:
		var slide_release_angle: float = max(slope_slide_start_angle_deg, 0.0)
		var slide_recover_angle: float = max(
			slide_release_angle - max(slope_static_hold_hysteresis_deg, 0.0),
			0.0
		)
		if _slope_passive_sliding:
			if slope_angle_deg <= slide_recover_angle:
				_slope_passive_sliding = false
		elif slope_angle_deg > slide_release_angle:
			_slope_passive_sliding = true
	var slope_static_hold: bool = (
		passive_slope_context
		and not _slope_passive_sliding
		and max(slope_idle_hold_speed, 0.0) > 0.0
		and lateral.length() <= max(slope_idle_hold_speed, 0.0)
	)
	var movement_release_decel_bypass: bool = (
		is_rolling
		or is_spindash_charging
		or spindash_release_now
		or _is_skidding
		or _drift_active
		or _drift_exit_active
		or auto_active
		or in_spring_state
		or _hurt_active
		or _slope_passive_sliding
	)
	var movement_release_decel_scale: float = _update_movement_release_deceleration(
		timer_delta,
		lateral,
		movement_input_active,
		movement_release_decel_bypass
	)
	var lateral_before_ground_motor: Vector3 = lateral
	if has_input:
		var input_dir_full: Vector3 = _move_direction.normalized()
		var move_dir: Vector3 = input_dir_full - physics_up * input_dir_full.dot(physics_up)
		var move_dir_len: float = move_dir.length()
		if move_dir_len > 0.0001:
			move_dir /= move_dir_len
		else:
			if lateral.length() > 0.0001:
				move_dir = lateral.normalized()
			else:
				move_dir = Vector3.ZERO

		var lateral_speed: float = lateral.length()
		var drift_controls_active: bool = _drift_active and not _drift_exit_active and is_attached
		var bypass_intent_smoothing: bool = (
			_drift_active
			or _drift_exit_active
			or _is_skidding
			or auto_active
			or _wall_input_projection_active
			or _wall_input_push_active
			or _loop_control_active
		)
		var steering_move_dir: Vector3 = _get_locomotion_intent_direction(
			move_dir,
			lateral,
			physics_up,
			is_attached,
			delta,
			bypass_intent_smoothing
		)

		if is_attached:
			if _is_skidding:
				# Skid: strong decel, but allow a *small* turn radius.
				if lateral_speed > 0.01:
					var vel_dir_skid: Vector3 = lateral / lateral_speed

					# Desired steering direction from input, projected onto ground plane
					var steer_dir: Vector3 = _move_direction
					if steer_dir.length() > 0.0001:
						steer_dir -= physics_up * steer_dir.dot(physics_up)
						if steer_dir.length() > 0.0001:
							steer_dir = steer_dir.normalized()
						else:
							steer_dir = vel_dir_skid
					else:
						steer_dir = vel_dir_skid

					# Limit how much we can turn per frame while skidding
					var max_skid_turn_rad: float = deg_to_rad(skid_turn_deg_per_sec) * delta
					var dot_turn: float = clamp(vel_dir_skid.dot(steer_dir), -1.0, 1.0)
					var angle_turn: float = acos(dot_turn)

					var final_dir: Vector3 = vel_dir_skid
					if angle_turn > 0.001 and max_skid_turn_rad > 0.0:
						var t_turn: float = min(1.0, max_skid_turn_rad / angle_turn)
						final_dir = vel_dir_skid.slerp(steer_dir, t_turn).normalized()

					# Strong speed loss while skidding
					var drop: float = skid_decel * delta
					var new_speed_skid: float = max(lateral_speed - drop, 0.0)
					lateral = final_dir * new_speed_skid
			else:
				var used_accel: float = _sample_curve_by_speed(
					ground_accel_curve_used,
					lateral_speed,
					35.0
				)
				used_accel = max(used_accel, 0.0)
				if used_accel > 0.0:
					used_accel *= get_combo_acceleration_multiplier()
				var drift_turn_scale_target: float = 1.0
				var used_accel_final: float = used_accel
				if drift_controls_active:
					var drift_input_side: int = _get_drift_input_side(lateral, move_dir, physics_up)
					var drift_input_strength: float = movement_input_strength
					var same_side_t: float = 0.0
					var counter_side_t: float = 0.0
					if drift_input_side != 0 and drift_input_side == _drift_direction:
						same_side_t = drift_input_strength
					elif drift_input_side != 0 and drift_input_side == -_drift_direction:
						counter_side_t = drift_input_strength
					var control_same_side_t: float = 0.0
					var control_counter_side_t: float = 0.0
					if drift_input_side != 0:
						var direction_for_controls: float = clamp(_drift_direction_value, -1.0, 1.0)
						var relative_input: float = float(drift_input_side) * direction_for_controls
						control_same_side_t = max(relative_input, 0.0) * drift_input_strength
						control_counter_side_t = max(-relative_input, 0.0) * drift_input_strength

					var tight_scale: float = max(drift_tight_turn_multiplier, 0.0)
					var counter_scale: float = max(drift_counter_turn_multiplier, 0.0)
					if control_same_side_t > 0.0:
						drift_turn_scale_target = lerp(1.0, tight_scale, control_same_side_t)
					elif control_counter_side_t > 0.0:
						drift_turn_scale_target = lerp(1.0, counter_scale, control_counter_side_t)

					_drift_turn_input_scale_current = _slerp_scalar(
						_drift_turn_input_scale_current,
						drift_turn_scale_target,
						drift_turn_input_response,
						delta
					)
					_drift_back_input_current = _slerp_scalar(
						_drift_back_input_current,
						counter_side_t,
						drift_turn_input_response,
						delta
					)
					_drift_same_input_current = _slerp_scalar(
						_drift_same_input_current,
						same_side_t,
						drift_turn_input_response,
						delta
					)

					var reward_accel: float = max(drift_reward_accel, 0.0)
					used_accel_final = used_accel + reward_accel * clamp(_drift_reward_progress, 0.0, 1.0)
					if is_instance_valid(_drift_action):
						used_accel_final *= _drift_action.get_straight_line_acceleration_multiplier()
				else:
					_drift_turn_input_scale_current = 1.0
					_drift_back_input_current = 0.0
					_drift_same_input_current = 0.0

				used_accel_final *= water_accel_mult
				if not drift_controls_active:
					grounded_motor_accel_used = (
						used_accel_final
						* movement_input_strength
					)
				var turn_deg_per_sec: float = 0.0
				if not drift_controls_active:
					turn_deg_per_sec = _sample_curve_by_speed(
						ground_turn_angle_curve_used,
						lateral_speed,
						540.0
					)
					turn_deg_per_sec = max(turn_deg_per_sec, 0.0)
					# Automation spline can override the turn curve while active.
					if auto_active and _automation_max_turn_deg_per_sec > 0.0:
						turn_deg_per_sec = min(turn_deg_per_sec, _automation_max_turn_deg_per_sec)
					if _drift_exit_active:
						turn_deg_per_sec = _apply_drift_exit_turn_ease(turn_deg_per_sec, timer_delta)
				var target_speed: float = run_top_speed_used
				if drift_controls_active:
					target_speed = _get_drift_target_speed(target_speed)
				if auto_active and _automation_along_speed_limits_player and _automation_along_target_speed > 0.0:
					target_speed = _automation_along_target_speed
				if water_physics_enabled and _running_on_water_surface and not (auto_active and _automation_along_speed_limits_player and _automation_along_target_speed > 0.0):
					target_speed = lateral_speed

				if drift_controls_active:
					# Drift avoids normal steering; speed adjusts along current motion.
					if lateral_speed < 0.01:
						var gained: float = min(target_speed, used_accel_final * delta)
						var drift_forward: Vector3 = move_dir
						if drift_forward.length() < 0.001:
							drift_forward = _model_forward - physics_up * _model_forward.dot(physics_up)
						if drift_forward.length() > 0.001:
							drift_forward = drift_forward.normalized()
						lateral = drift_forward * gained
					else:
						var new_speed: float = lateral_speed
						if lateral_speed < target_speed:
							var max_speed_step: float = used_accel_final * movement_input_strength * delta
							new_speed = min(lateral_speed + max_speed_step, target_speed)
						var vel_dir: Vector3 = lateral / lateral_speed
						lateral = vel_dir * new_speed
				else:
					var drift_exit_anchor_lateral: Vector3 = lateral
					var drift_exit_anchor_valid: bool = _drift_exit_active and lateral.length() > 0.001
					var wall_projection_velocity_override: bool = (_wall_input_projection_active or _wall_input_push_active) and _wall_input_debug_normal.length() > 0.001
					if wall_projection_velocity_override:
						var wall_accel_step: float = max(used_accel_final, 0.0) * delta
						var wall_decel_step: float = ground_decel_effective * water_decel_mult * delta
						if _wall_input_push_active and not _wall_input_projection_active:
							lateral = lateral.move_toward(Vector3.ZERO, wall_decel_step)
						else:
							var wall_dir: Vector3 = _wall_input_debug_projected_dir.slide(_wall_input_debug_normal)
							wall_dir -= physics_up * wall_dir.dot(physics_up)
							if wall_dir.length() < 0.001:
								lateral = lateral.move_toward(Vector3.ZERO, wall_decel_step)
							else:
								wall_dir = wall_dir.normalized()
								var current_wall_speed: float = lateral.dot(wall_dir)
								var target_wall_speed: float = target_speed
								var wall_speed_step: float = wall_accel_step if target_wall_speed > current_wall_speed else wall_decel_step
								var new_wall_speed: float = move_toward(current_wall_speed, target_wall_speed, wall_speed_step)
								var off_wall_axis: Vector3 = lateral - wall_dir * current_wall_speed
								off_wall_axis = off_wall_axis.move_toward(Vector3.ZERO, wall_decel_step)
								lateral = wall_dir * new_wall_speed + off_wall_axis
					elif lateral_speed < 0.01:
						var gained: float = min(target_speed, used_accel_final * movement_input_strength * delta)
						lateral = steering_move_dir * gained
					else:
						var vel_dir: Vector3 = lateral / lateral_speed
						var steer_target_dir: Vector3 = steering_move_dir
						if _drift_exit_active:
							var normal_control_t: float = 1.0 - clamp(_drift_exit_blend, 0.0, 1.0)
							if normal_control_t <= 0.001:
								steer_target_dir = vel_dir
							elif normal_control_t < 0.999:
								steer_target_dir = vel_dir.slerp(steering_move_dir, normal_control_t)
								if steer_target_dir.length() > 0.001:
									steer_target_dir = steer_target_dir.normalized()
								else:
									steer_target_dir = vel_dir
						var wall_projection_turn_override: bool = _wall_input_projection_active or _wall_input_push_active
						if wall_projection_turn_override:
							var wall_speed: float = lateral_speed
							if wall_speed < target_speed:
								wall_speed = min(
									wall_speed + used_accel_final * movement_input_strength * delta,
									target_speed
								)
							lateral = steer_target_dir * wall_speed
						else:
							var turn_preservation: float = ground_turn_speed_preservation
							if barrier_speed_boost:
								turn_preservation = max(turn_preservation, barrier_blast_turn_speed_preservation)
							turn_preservation *= lerp(
								1.0,
								clamp(slope_reversal_guard_turn_preservation, 0.0, 1.0),
								clamp(slope_reversal_guard_control_weight, 0.0, 1.0)
							)
							var turn_loss_decel: float = ground_decel_effective
							if (
								_spindash_turn_free_timer > 0.0
								or _loop_control_active
								or (auto_active and _automation_disable_turning_slowdown)
							):
								turn_loss_decel = 0.0
							lateral = _apply_steered_locomotion_velocity(
								lateral,
								steer_target_dir,
								move_dir,
								turn_deg_per_sec,
								ground_turn_sharp_rate_multiplier,
								turn_preservation,
								180.0,
								1.0,
								1.0,
								used_accel_final,
								ground_brake_decel,
								1.0,
								turn_loss_decel,
								target_speed,
								movement_input_strength,
								delta
							)

					if drift_exit_anchor_valid:
						var normal_control_t_exit: float = 1.0 - clamp(_drift_exit_blend, 0.0, 1.0)
						if normal_control_t_exit <= 0.001:
							lateral = drift_exit_anchor_lateral
						elif normal_control_t_exit < 0.999:
							var anchor_speed: float = drift_exit_anchor_lateral.length()
							var normal_speed: float = lateral.length()
							if anchor_speed > 0.001 and normal_speed > 0.001:
								var anchor_dir: Vector3 = drift_exit_anchor_lateral / anchor_speed
								var normal_dir: Vector3 = lateral / normal_speed
								var blended_dir: Vector3 = anchor_dir.slerp(normal_dir, normal_control_t_exit)
								if blended_dir.length() > 0.001:
									blended_dir = blended_dir.normalized()
									lateral = blended_dir * lerp(anchor_speed, normal_speed, normal_control_t_exit)
								else:
									lateral = drift_exit_anchor_lateral.lerp(lateral, normal_control_t_exit)
							else:
								lateral = drift_exit_anchor_lateral.lerp(lateral, normal_control_t_exit)

		else:
			var air_accel_curve_used: Curve = _get_active_acceleration_curve(air_accel_curve)
			var sampled_accel_air: float = _sample_curve_by_speed(
				air_accel_curve_used,
				lateral_speed,
				20.0
			)
			var used_accel_air: float = sampled_accel_air
			if is_air_acceleration_overridden():
				used_accel_air = get_air_acceleration_override(lateral_speed, used_accel_air)
			used_accel_air = max(used_accel_air, 0.0)
			if sampled_accel_air > 0.0:
				used_accel_air *= get_combo_acceleration_multiplier()

			used_accel_air *= water_accel_mult
			used_accel_air *= _directional_influence_lock_accel_multiplier

			var air_turn_deg_per_sec: float = _sample_curve_by_speed(
				air_turn_angle_curve,
				lateral_speed,
				720.0
			)
			air_turn_deg_per_sec = max(air_turn_deg_per_sec, 0.0)
			air_turn_deg_per_sec *= _directional_influence_lock_turn_multiplier
			# Automation spline can override the turn curve while active.
			if auto_active and _automation_max_turn_deg_per_sec > 0.0:
				air_turn_deg_per_sec = min(air_turn_deg_per_sec, _automation_max_turn_deg_per_sec)

			var target_speed_air: float = air_top_speed_effective
			if auto_active and _automation_along_speed_limits_player and _automation_along_target_speed > 0.0:
				target_speed_air = _automation_along_target_speed

			var wall_projection_air_velocity_override: bool = (_wall_input_projection_active or _wall_input_push_active) and _wall_input_debug_normal.length() > 0.001
			if wall_projection_air_velocity_override:
				var wall_air_speed_step: float = max(used_accel_air, air_decel_effective * water_decel_mult) * delta
				if _wall_input_push_active and not _wall_input_projection_active:
					lateral = lateral.move_toward(Vector3.ZERO, wall_air_speed_step)
				else:
					var wall_air_dir: Vector3 = _wall_input_debug_projected_dir.slide(_wall_input_debug_normal)
					wall_air_dir -= physics_up * wall_air_dir.dot(physics_up)
					if wall_air_dir.length() < 0.001:
						lateral = lateral.move_toward(Vector3.ZERO, wall_air_speed_step)
					else:
						wall_air_dir = wall_air_dir.normalized()
						var current_wall_air_speed: float = lateral.dot(wall_air_dir)
						var target_wall_air_speed: float = target_speed_air
						var new_wall_air_speed: float = move_toward(current_wall_air_speed, target_wall_air_speed, wall_air_speed_step)
						var off_wall_air_axis: Vector3 = lateral - wall_air_dir * current_wall_air_speed
						off_wall_air_axis = off_wall_air_axis.move_toward(Vector3.ZERO, wall_air_speed_step)
						lateral = wall_air_dir * new_wall_air_speed + off_wall_air_axis
			elif lateral_speed < 0.01:
				var gained_air: float = min(target_speed_air, used_accel_air * movement_input_strength * delta)
				lateral = steering_move_dir * gained_air
			else:
				var air_turn_loss_decel: float = air_decel_effective * water_decel_mult
				if (
					_spindash_turn_free_timer > 0.0
					or (auto_active and _automation_disable_turning_slowdown)
				):
					air_turn_loss_decel = 0.0
				lateral = _apply_steered_locomotion_velocity(
					lateral,
					steering_move_dir,
					move_dir,
					air_turn_deg_per_sec,
					air_turn_sharp_rate_multiplier,
					air_turn_speed_preservation,
					air_pullback_start_angle_deg,
					air_pullback_turn_rate_multiplier,
					air_pullback_brake_multiplier,
					used_accel_air,
					air_brake_decel,
					_directional_influence_lock_accel_multiplier,
					air_turn_loss_decel,
					target_speed_air,
					movement_input_strength,
					delta
				)

		# --------------------------------------------------
		# Drift turn (ground-only course correction)
		# --------------------------------------------------
		if drift_controls_active:
			if _drift_turn_entry_timer > 0.0:
				_drift_turn_entry_timer = max(_drift_turn_entry_timer - timer_delta, 0.0)
			lateral = _apply_drift_turn(
				delta,
				physics_up,
				lateral,
				move_dir,
				_drift_turn_input_scale_current,
				_drift_back_input_current
			)

	else:
		_reset_locomotion_intent_smoothing()
		if is_attached:
			if is_rolling:
				var ordinary_roll_resistance_allowed: bool = (
					sticky_surface_active
					or roll_slope_surface_resistance_enabled
					or (not has_slope and not is_loop_surface)
				)
				if is_spindash_charging:
					ordinary_roll_resistance_allowed = true
				if ordinary_roll_resistance_allowed:
					var charge_decel: float = roll_decel
					if is_spindash_charging:
						if _spindash_roll_held:
							charge_decel = spindash_charge_decel
						else:
							charge_decel = spindash_charge_decel_unheld
					lateral = _apply_surface_resistance(
						lateral,
						charge_decel,
						roll_linear_drag,
						roll_quadratic_drag,
						delta
					)
			else:
				# If an automation spline has locked controls, don't apply "no-input" deceleration.
				# Automation should be responsible for guiding speed/direction in that case.
				if auto_active and _automation_lock_movement:
					pass
				elif _slope_passive_sliding:
					pass
				else:
					var used_decel: float = ground_decel_effective * water_decel_mult * movement_release_decel_scale
					if _hurt_active:
						used_decel *= clamp(hurt_ground_decel_multiplier, 0.0, 1.0)
					var max_drop: float = used_decel * delta

					# Optional safety: don't allow more than, say, 60% of speed to vanish in one frame
					var max_fraction: float = 0.6
					max_drop = min(max_drop, lateral.length() * max_fraction)

					lateral = lateral.move_toward(Vector3.ZERO, max_drop)

		else:
			if is_rolling:
				if _homing_retain_timer <= 0.0:
					lateral = lateral.move_toward(Vector3.ZERO, max(roll_air_decel, 0.0) * water_decel_mult * delta)
			else:
				if not (auto_active and _automation_lock_movement) and not in_spring_state and _homing_retain_timer <= 0.0:
					var passive_air_decel: float = air_decel_effective * water_decel_mult * movement_release_decel_scale
					lateral = lateral.move_toward(Vector3.ZERO, passive_air_decel * delta)

		if _drift_exit_active:
			_apply_drift_exit_turn_ease(0.0, delta)

	if (
		sticky_idle_deceleration_active
		and lateral.length() <= max(slope_idle_hold_speed, 0.01)
	):
		lateral = Vector3.ZERO

	# Rolling: allow limited steering without acceleration.
	if is_rolling and _move_direction.length() > 0.001 and lateral.length() > 0.01 and roll_turn_deg_per_sec > 0.0:
		var up_roll: Vector3 = physics_up.normalized()
		if up_roll.length() < 0.001:
			up_roll = _get_gravity_up()
		var desired_roll: Vector3 = _move_direction
		desired_roll -= up_roll * desired_roll.dot(up_roll)
		if desired_roll.length() > 0.001:
			desired_roll = desired_roll.normalized()
			var speed_roll: float = lateral.length()
			var cur_dir: Vector3 = lateral / speed_roll
			var dotv: float = clamp(cur_dir.dot(desired_roll), -1.0, 1.0)
			var ang: float = acos(dotv)
			if ang > 0.0001:
				var max_turn: float = deg_to_rad(roll_turn_deg_per_sec) * delta
				var t_turn: float = min(1.0, max_turn / ang) if max_turn > 0.0 else 1.0
				var new_dir: Vector3 = cur_dir.slerp(desired_roll, t_turn).normalized()
				lateral = new_dir * speed_roll

	# --------------------------------------------------
	# MOVEMENT CORRECTION: predictive terrain, ledge, and guide-surface push
	# --------------------------------------------------
	if _movement_correction_module != null:
		lateral = _movement_correction_module.update_velocity(
			lateral,
			_move_direction,
			movement_input_strength,
			physics_up,
			is_attached,
			_drift_active and not _drift_exit_active,
			is_rolling,
			auto_active,
			in_spring_state,
			delta
		)

	# --------------------------------------------------
	# AUTOMATION SPLINE: steer lateral toward route tangent (vicinity-based)
	# --------------------------------------------------
	if auto_active and not in_spring_state and not _rail_active and not _spline_active:
		# 1) Nudge toward the spline (sideways pull)
		if _automation_continuous_force and _automation_toward_dir.length() > 0.001 and _automation_toward_strength > 0.0:
			var toward_dir: Vector3 = _automation_toward_dir
			toward_dir -= physics_up * toward_dir.dot(physics_up)
			if toward_dir.length() > 0.001:
				toward_dir = toward_dir.normalized()
				var lat_speed: float = lateral.length()
				var speed_scale: float = 1.0 + lat_speed * 0.02
				lateral += toward_dir * (_automation_toward_strength * speed_scale) * delta

		# 2) Assist along the route until reaching desired speed (separate from nudge)
		if _automation_along_assist_enabled and _automation_tangent_dir.length() > 0.001 and _automation_along_accel > 0.0 and _automation_along_target_speed > 0.0:
			var tan_dir: Vector3 = _automation_tangent_dir
			tan_dir -= physics_up * tan_dir.dot(physics_up)
			if tan_dir.length() > 0.001:
				tan_dir = tan_dir.normalized()
				var assist_sign: float = 1.0
				var assist_has_intent: bool = true
				var assist_input_strength: float = 1.0
				if _automation_bidirectional_assist:
					assist_sign = sign(_move_direction.dot(tan_dir))
					assist_has_intent = movement_input_strength > 0.001 and abs(assist_sign) > 0.001
					assist_input_strength = movement_input_strength
				if assist_has_intent:
					var assist_dir: Vector3 = tan_dir * assist_sign
					var along_speed: float = lateral.dot(assist_dir)
					if along_speed < _automation_along_target_speed:
						lateral += assist_dir * _automation_along_accel * assist_input_strength * delta

		# 3) Optional: limit turning rate toward tangent (helps “guided” feel)
		if _automation_tangent_dir.length() > 0.001 and _automation_max_turn_deg_per_sec > 0.0:
			var auto_dir2: Vector3 = _automation_tangent_dir
			auto_dir2 -= physics_up * auto_dir2.dot(physics_up)
			if auto_dir2.length() > 0.001:
				auto_dir2 = auto_dir2.normalized()
				var lat_speed2: float = lateral.length()
				var max_turn: float = deg_to_rad(_automation_max_turn_deg_per_sec) * delta
				if max_turn > 0.0 and lat_speed2 > 0.01:
					var cur_dir2: Vector3 = lateral / lat_speed2
					var dotv2: float = clamp(cur_dir2.dot(auto_dir2), -1.0, 1.0)
					var ang2: float = acos(dotv2)
					if ang2 > 0.0001:
						var axis2: Vector3 = cur_dir2.cross(auto_dir2)
						if axis2.length() > 0.0001:
							axis2 = axis2.normalized()
							var turn2: float = min(ang2, max_turn)
							cur_dir2 = cur_dir2.rotated(axis2, turn2)
							lateral = cur_dir2.normalized() * lat_speed2
		# 4) Optional: snap sideways drift back toward the tangent (strong alignment).
		if _automation_tangent_snap_strength > 0.0 and _automation_tangent_dir.length() > 0.001:
			var snap_dir: Vector3 = _automation_tangent_dir
			snap_dir -= physics_up * snap_dir.dot(physics_up)
			if snap_dir.length() > 0.001:
				snap_dir = snap_dir.normalized()
				var along_speed: float = lateral.dot(snap_dir)
				var target_lateral: Vector3 = snap_dir * along_speed
				var snap_t: float = clamp(_automation_tangent_snap_strength * delta, 0.0, 1.0)
				lateral = lateral.lerp(target_lateral, snap_t)

	if _spindash_release_requested and is_attached:
		lateral = _apply_spindash_release(physics_up, lateral)
		_spindash_turn_free_timer = max(spindash_turn_penalty_disable_time, 0.0)
		_spindash_release_requested = false
		_spindash_release_with_jump = false
		_spindash_release_speed = 0.0
		_spindash_latched_direction = Vector3.ZERO

	# --------------------------------------------------
	# Slope influence on lateral velocity (ONLY when attached)
	# --------------------------------------------------
	if (
		is_attached
		and has_slope
		and downhill_dir.length() > 0.0
		and not _surface_ignores_slope_gravity()
		and not sticky_deceleration_active
	):
		var downhill_component: float = lateral.dot(downhill_dir)
		var slope_sample_speed: float = lateral.length()
		if slope_static_hold:
			lateral = Vector3.ZERO
		var slope_down_mult: float = 1.0
		var slope_up_mult: float = 1.0
		if is_rolling:
			slope_down_mult = max(_sample_curve_by_speed(
				roll_downhill_accel_multiplier_curve,
				slope_sample_speed,
				roll_downhill_accel_multiplier
			), 0.0)
			slope_up_mult = max(_sample_curve_by_speed(
				roll_uphill_decel_multiplier_curve,
				slope_sample_speed,
				roll_uphill_decel_multiplier
			), 0.0)

		var on_rigid_floor: bool = (
			(_platform_on_floor_last
				and _platform_collider_last != null
				and is_instance_valid(_platform_collider_last)
				and _platform_collider_last is RigidBody3D)
			or (_follow_collider_last != null
				and is_instance_valid(_follow_collider_last)
				and _follow_collider_last is RigidBody3D)
		)
		var rigid_downhill_scale: float = slope_rigid_body_downhill_factor if on_rigid_floor else 1.0
		if _dbg_dynbody:
			var fc_name: String = _follow_collider_last.name if (_follow_collider_last != null and is_instance_valid(_follow_collider_last)) else "null"
			print("[DYN] SLOPE on_rigid=%s scale=%.2f follow=%s slope_ang=%.1f\u00b0" % [on_rigid_floor, rigid_downhill_scale, fc_name, slope_angle_deg])

		# Continuous tangential gravity with blended uphill and downhill response.
		if not slope_static_hold:
			var baseline_gravity: float = max(gravity_strength, 0.0)
			if baseline_gravity <= 0.001:
				baseline_gravity = max(get_effective_gravity_strength(), 0.001)
			var downhill_response: float = (
				max(_get_slope_downhill_accel(slope_sample_speed), 0.0)
				* slope_down_mult
				/ baseline_gravity
			)
			var uphill_response: float = (
				max(_get_slope_uphill_decel(slope_sample_speed), 0.0)
				* slope_up_mult
				/ baseline_gravity
			)
			var uphill_blend_speed: float = max(slope_uphill_response_blend_speed, 0.001)
			var uphill_response_weight: float = _smoothstep_unit(
				-downhill_component / uphill_blend_speed
			)
			var response_scale: float = lerp(
				downhill_response,
				uphill_response,
				uphill_response_weight
			)
			var slope_angle_power_curve: Curve = slope_gravity_angle_curve
			if is_rolling:
				slope_angle_power_curve = roll_slope_gravity_angle_curve
			elif _barrier_blast_active:
				slope_angle_power_curve = barrier_blast_slope_gravity_angle_curve
			var angle_response: float = max(_sample_curve_by_speed(
				slope_angle_power_curve,
				slope_angle_deg,
				1.0
			), 0.0)
			var rigid_response: float = lerp(
				rigid_downhill_scale,
				1.0,
				uphill_response_weight
			)
			var slope_acceleration: Vector3 = (
				slope_gravity
				* response_scale
				* angle_response
				* rigid_response
			)
			if slope_reversal_guard_control_weight > 0.0:
				var reversal_pull_scale: float = 1.0 + (
					max(slope_reversal_guard_pull_multiplier, 0.0)
					* clamp(slope_reversal_guard_control_weight, 0.0, 1.0)
				)
				slope_acceleration *= reversal_pull_scale

			var start_traction_speed: float = max(slope_uphill_start_traction_speed, 0.0)
			var walkable_uphill_start: bool = (
				start_traction_speed > 0.0
				and grounded_motor_accel_used > 0.0
				and slope_control_uphill_alignment > 0.0
				and slope_angle_deg <= max(slope_slide_start_angle_deg, 0.0)
				and not slope_reversal_guard_bypass
			)
			if walkable_uphill_start:
				var current_uphill_speed: float = max(-downhill_component, 0.0)
				var start_speed_weight: float = 1.0 - _smoothstep_unit(
					current_uphill_speed / start_traction_speed
				)
				var traction_debt_availability: float = 1.0 - _smoothstep_unit(
					clamp(_slope_reversal_debt, 0.0, 1.0) / 0.25
				)
				var traction_weight: float = (
					start_speed_weight
					* traction_debt_availability
					* slope_control_uphill_alignment
				)
				var downhill_acceleration: float = max(
					slope_acceleration.dot(downhill_dir),
					0.0
				)
				if traction_weight > 0.0 and downhill_acceleration > 0.0:
					var motor_uphill_acceleration: float = (
						grounded_motor_accel_used
						* slope_control_uphill_alignment
					)
					var retained_accel_ratio: float = clamp(
						slope_uphill_start_accel_ratio,
						0.0,
						1.0
					)
					var allowed_downhill_acceleration: float = max(
						motor_uphill_acceleration * (1.0 - retained_accel_ratio),
						0.0
					)
					var limited_downhill_acceleration: float = lerp(
						downhill_acceleration,
						min(downhill_acceleration, allowed_downhill_acceleration),
						clamp(traction_weight, 0.0, 1.0)
					)
					slope_acceleration *= (
						limited_downhill_acceleration
						/ downhill_acceleration
					)
			if (
				grounded_motor_accel_used > 0.0
				and slope_control_uphill_alignment > 0.0
				and not is_rolling
				and not auto_active
				and not in_spring_state
				and not _hurt_active
				and not is_spindash_charging
				and not _drift_active
				and not _drift_exit_active
			):
				lateral = _limit_uphill_motor_velocity(
					lateral_before_ground_motor,
					lateral,
					downhill_dir,
					slope_angle_deg,
					slope_acceleration,
					delta
				)
			lateral += slope_acceleration * delta
			if _slope_passive_sliding:
				lateral = _apply_surface_resistance(
					lateral,
					slope_slide_resistance,
					slope_slide_linear_drag,
					slope_slide_quadratic_drag,
					delta
				)

	if is_attached and is_spindash_charging:
		var charge_stop_speed: float = max(spindash_charge_stop_speed, 0.0)
		if lateral.length() <= charge_stop_speed:
			lateral = Vector3.ZERO

	# --------------------------------------------------
	# Vertical / gravity behavior
	# --------------------------------------------------
	if is_attached:
		if vertical > 0.0:
			# Remove only the into-surface part but keep total speed as much as possible
			var v_attached: Vector3 = lateral + physics_up * vertical
			v_attached -= physics_up * max(vertical, 0.0)  # remove upward along surface normal

			vertical = v_attached.dot(physics_up)
			lateral  = v_attached - physics_up * vertical

	else:
		var gravity_scale: float = 1.0
		var jump_held: bool = _is_jump_held()

		var in_bounce: bool = (_bounce_state == BounceState.BOUNCE)
		var in_stomp: bool = (_bounce_state == BounceState.STOMP)

		if in_bounce or in_stomp:
			# Bounce / stomp override: no variable jump, just strong downward accel.
			_is_jumping = false
			_jump_hang_allowed = false
			_jump_time = 0.0

			if in_bounce:
				gravity_scale = bounce_gravity_scale
			else:
				gravity_scale = stomp_gravity_scale

		else:
			# Normal air behavior (variable-height jump, apex, etc.)
			var jump_action_active: bool = _current_action_id == &"jump"
			if not jump_action_active and (_is_jumping or _jump_variable or _jump_hang_allowed):
				_is_jumping = false
				_jump_variable = false
				_jump_hang_allowed = false
				_jump_time = 0.0
			elif _is_jumping and _jump_variable:
				_jump_time += delta

				if vertical > 0.0:
					if not jump_held or _jump_time >= jump_hold_time_max:
						_jump_hang_allowed = false

					var jump_hang_active: bool = (
						jump_action_active
						and _jump_hang_allowed
						and jump_held
					)
					if jump_hang_active:
						if abs(vertical) <= jump_apex_speed_threshold:
							gravity_scale = jump_apex_gravity_scale
						else:
							gravity_scale = jump_hold_gravity_scale
					else:
						gravity_scale = jump_release_gravity_scale

					if jump_hang_active:
						var horz_vel: Vector3 = lateral
						var horz_speed: float = horz_vel.length()

						if horz_speed >= jump_damp_min_speed and horz_speed > 0.001:
							var damp_strength: float = _sample_curve_by_speed(
								jump_damp_curve,
								horz_speed,
								jump_damp_strength
							)

							var damp_amount: float = damp_strength * delta
							var new_speed: float = max(horz_speed - damp_amount, 0.0)

							if new_speed < horz_speed:
								var horz_dir: Vector3 = horz_vel / horz_speed
								lateral = horz_dir * new_speed
				else:
					_is_jumping = false
					_jump_hang_allowed = false

		if in_spring_state:
			gravity_scale *= spring_gravity_scale

		if _drowned_action == null or not _drowned_action.is_drowned():
			vertical -= get_effective_gravity_strength() * gravity_scale * delta

		# Apply water vertical speed limits (multipliers on base speeds)
		if in_submerged_vertical_physics:
			vertical = _apply_water_vertical_speed_slowdown(vertical, delta)
		else:
			if vertical < -max_fall_speed:
				vertical = -max_fall_speed


	# --------------------------------------------------
	# Hurt-state air jump breakout (SA2-style timing)
	# --------------------------------------------------
	if not is_attached and _hurt_active and _jump_requested and _hurt_state_timer >= max(hurt_air_jump_unlock_time, 0.0):
		vertical = max(vertical, jump_speed)
		_hurt_active = false
		_hurt_state_timer = 0.0
		_jump_requested = false
		_activate_jump_action_for_launch(&"hurt_air_jump")
		_begin_jump_hold_state(true)
		refresh_airborne_abilities()
		_jumped_from_ground = false
		_falling_without_jump = false
		play_jump_sfx()
		_trigger_anim_command(&"CMD_JUMP")

	# --------------------------------------------------
	# Jump from attached state
	# --------------------------------------------------
	if is_attached and _jump_requested and is_surface_jump_blocked():
		_jump_requested = false
		_coyote_jump_requested = false
	if is_attached and _jump_requested:
		if auto_active and _automation_lock_actions:
			_jump_requested = false
			_coyote_jump_requested = false
		else:
			var surf_n: Vector3 = surface_normal.normalized()
			if surf_n.length() < 0.001:
				surf_n = world_up

			var dot_up: float = clamp(surf_n.dot(world_up), -1.0, 1.0)
			var surf_ang_deg: float = rad_to_deg(acos(dot_up))

			var is_floorish_for_jump: bool = (surf_ang_deg <= variable_jump_max_surface_angle_deg and dot_up > 0.0)

			var jump_dir: Vector3 = physics_up
			if jump_dir.length() < 0.001:
				jump_dir = world_up
			jump_dir = jump_dir.normalized()

			if _dbg_tp_trace > 0:
				print("[TP-F%d] JUMP_FROM_GROUND: vel=%v -> vertical=%s" % [9 - _dbg_tp_trace, velocity, jump_speed])
			vertical = jump_speed

			play_jump_sfx()

			# Record detach surface for follow/exception rules.
			_record_detach_state(surf_n, world_up)

			attached = false
			_attachment_immunity = launch_immunity_time
			_airborne_time = 0.0
			_clear_coyote_jump_window()
			_is_skidding = false
			_jumped_from_ground = true
			_falling_without_jump = false

			_activate_jump_action_for_launch(&"ground_jump")
			_begin_jump_hold_state(is_floorish_for_jump)
			_trigger_anim_command(&"CMD_JUMP")
			_coyote_jump_requested = false

	# --------------------------------------------------
	# Coyote jump (simple ledge detach only)
	# --------------------------------------------------
	if not is_attached and (_coyote_jump_requested or (_jump_requested and _can_consume_coyote_jump())):
		var should_coyote: bool = true
		if coyote_jump_homing_priority and _can_scan_homing_targets():
			if has_homing_target_in_range():
				should_coyote = false
				_jump_requested = false
				_coyote_jump_requested = false
				_jump_dash_requested = true

		if should_coyote:
			vertical = max(vertical, jump_speed)
			_jump_requested = false
			_coyote_jump_requested = false
			_clear_coyote_jump_window()
			_activate_jump_action_for_launch(&"coyote_jump")
			_airborne_time = 0.0
			_jumped_from_ground = true
			_falling_without_jump = false
			_begin_jump_hold_state(true)
			play_jump_sfx()
			_trigger_anim_command(&"CMD_JUMP")

	# Jump dash impulse is handled earlier (homing has priority).

	# --------------------------------------------------
	# Dash panel speed lock (magnitude-only, player-relative)
	# --------------------------------------------------
	var lateral_speed_soft: float = lateral.length()

	if is_attached and _dash_speed_lock_timer > 0.0:
		# Keep current direction; only enforce speed magnitude.
		if lateral_speed_soft > 0.001:
			var dir: Vector3 = lateral / lateral_speed_soft
			lateral = dir * _dash_speed_lock_speed
		else:
			# If we're somehow almost stopped, push along input direction if any.
			if _move_direction.length() > 0.001:
				var move_dir_full: Vector3 = _move_direction
				var move_dir: Vector3 = move_dir_full - physics_up * move_dir_full.dot(physics_up)
				if move_dir.length() > 0.001:
					move_dir = move_dir.normalized()
					lateral = move_dir * _dash_speed_lock_speed
			# else: leave lateral as is (no input, no direction)

		# Recompute for later clamps
		lateral_speed_soft = lateral.length()

	# --------------------------------------------------
	# Soft cap toward ground/air top speed (configurable strength)
	# --------------------------------------------------
#	var lateral_speed_soft: float = lateral.length()
	var soft_cap_attached: bool = is_attached and attached
	var soft_top_speed: float = run_top_speed_used * water_top_speed_mult
	if not soft_cap_attached:
		soft_top_speed = air_top_speed_effective * water_top_speed_mult
	if water_physics_enabled and _running_on_water_surface:
		soft_top_speed = 0.0

	var downhill_soft_cap_bypass_active: bool = false
	if soft_cap_attached:
		# --- Let slopes & steep surfaces raise the effective top speed ---
		# slope_speed_factor: 0..1 based on surface angle vs gravity-up (up to 90°)
		# downhill_dir: world-gravity projected onto surface (already computed above)
		if downhill_dir.length() > 0.001 and lateral_speed_soft > 0.001:
			var move_dir: Vector3 = lateral / lateral_speed_soft
			var downhill_dot: float = move_dir.dot(downhill_dir)  # +1 = straight downhill, -1 = straight uphill

			if downhill_dot > 0.0:
				# Only when actually moving downhill.
				var downhill_align: float = clamp(downhill_dot, 0.0, 1.0)
				var t_slope: float = clamp(slope_speed_factor * downhill_align, 0.0, 1.0)
				downhill_soft_cap_bypass_active = (
					slope_downhill_soft_cap_bypass
					and has_slope
					and not _running_on_water_surface
					and downhill_align >= clamp(slope_downhill_soft_cap_min_alignment, 0.0, 1.0)
				)

				# Blend cap from run_top_speed → max speed as slope gets steeper
				# and movement lines up with downhill.
				if not _running_on_water_surface:
					soft_top_speed = lerp(run_top_speed_used, max_speed_limit_for_motion, t_slope)

		# --- On true loop / ceiling segments, allow full max_speed ---
		# (is_loop_surface is computed earlier in this function)
		if is_loop_surface and not _running_on_water_surface:
			soft_top_speed = max_speed_limit_for_motion
	if auto_active and _automation_along_speed_limits_player and _automation_along_target_speed > 0.0:
		soft_top_speed = _automation_along_target_speed
		downhill_soft_cap_bypass_active = false
	var drift_speed_target_active: bool = _drift_active and soft_cap_attached and not _running_on_water_surface
	if drift_speed_target_active:
		soft_top_speed = max(soft_top_speed, _get_drift_target_speed(run_top_speed_used))
	var drift_speed_target_blocks_slowdown: bool = drift_speed_target_active
	var airborne_roll_soft_cap: bool = (
		is_rolling
		and not soft_cap_attached
		and roll_air_top_speed_slowdown_enabled
	)
	var rolling_soft_cap_allowed: bool = (
		not is_rolling
		or airborne_roll_soft_cap
		or in_water_movement_physics
		or _running_on_water_surface
	)

	# Apply soft cap outside states that preserve earned or temporary speed.
	if _homing_retain_timer <= 0.0 \
			and not in_spring_state \
			and (movement_input_active or auto_active) \
			and rolling_soft_cap_allowed \
			and not downhill_soft_cap_bypass_active \
			and not drift_speed_target_blocks_slowdown \
			and not is_speed_shoes_active() \
			and (soft_top_speed > 0.0 or _running_on_water_surface) \
			and lateral_speed_soft > soft_top_speed \
			and lateral_speed_soft > 0.001:

		var over: float = lateral_speed_soft - soft_top_speed

		# Base bleed comes from ground or air decel.
		var base_bleed: float = ground_decel_effective
		if not soft_cap_attached:
			base_bleed = air_decel_effective
		if not movement_input_active and not movement_release_decel_bypass:
			base_bleed *= movement_release_decel_scale

		var slowdown_strength: float = top_speed_slowdown_strength
		var slowdown_strength_curve: Curve = top_speed_slowdown_strength_curve
		if not soft_cap_attached:
			slowdown_strength = air_top_speed_slowdown_strength
			slowdown_strength_curve = air_top_speed_slowdown_strength_curve
		if in_water_movement_physics:
			slowdown_strength = water_top_speed_slowdown_strength
		if _running_on_water_surface:
			slowdown_strength = max(water_surface_slowdown_strength, 0.0)
			if _drift_active:
				slowdown_strength *= max(water_surface_drift_slowdown_multiplier, 0.0)
		elif slowdown_strength_curve:
			var slowdown_curve_multiplier: float = _sample_curve_by_speed(
				slowdown_strength_curve,
				lateral_speed_soft,
				1.0
			)
			slowdown_strength *= max(slowdown_curve_multiplier, 0.0)
		if airborne_roll_soft_cap:
			slowdown_strength *= max(roll_top_speed_slowdown_scale, 0.0)
		if barrier_speed_boost:
			slowdown_strength *= maxf(barrier_blast_top_speed_slowdown_multiplier, 0.0)

		var bleed_rate: float = base_bleed * slowdown_strength
		if bleed_rate > 0.0:
			var drop: float = min(over, bleed_rate * delta)
			var new_speed: float = lateral_speed_soft - drop
			lateral = lateral.normalized() * new_speed


	# --------------------------------------------------
	# Clamp lateral speed to max_speed
	# --------------------------------------------------
	var max_speed_override_target: float = float(
		max_speed_override_state.get("target", max_speed_limit_for_motion)
	)
	if max_speed_override_active:
		_functional_max_speed = max(max_speed_override_target, 0.0)
	else:
		var recovery_weight: float = 1.0 - exp(-max(max_speed_override_recovery_lerp_speed, 0.0) * delta)
		_functional_max_speed = lerp(_functional_max_speed, max(max_speed, 0.0), recovery_weight) if recovery_weight > 0.0 else max(max_speed, 0.0)
	var max_speed_effective: float = _functional_max_speed * water_top_speed_mult
	if not is_attached:
		lateral = _apply_left_stick_trick_momentum(lateral, max_speed_effective, water_accel_mult, delta)
	var lateral_speed_final: float = lateral.length()
	if lateral_speed_final > max_speed_effective and lateral_speed_final > 0.0:
		lateral = lateral.normalized() * max_speed_effective
		lateral_speed_final = max_speed_effective
	if (
		not is_attached
		and not in_spring_state
		and not auto_active
		and _homing_retain_timer <= 0.0
	):
		lateral = _apply_fast_fall_horizontal_drag(lateral, vertical, delta)
		lateral_speed_final = lateral.length()

	# --------------------------------------------------
	# Drift turn speed sampling (used on next frame)
	# --------------------------------------------------
	var current_turn_speed_deg_per_sec: float = 0.0
	if is_attached and is_instance_valid(_drift_action):
		lateral = _drift_action.apply_straight_line_drag(lateral, delta)
		lateral_speed_final = lateral.length()
	var up_for_turn: Vector3 = physics_up.normalized()
	if up_for_turn.length() < 0.001:
		up_for_turn = _get_gravity_up()
	var lateral_dir: Vector3 = Vector3.ZERO
	if lateral_speed_final > 0.001:
		lateral_dir = lateral / lateral_speed_final
	var yaw_lateral_dir: Vector3 = lateral_dir - up_for_turn * lateral_dir.dot(up_for_turn)
	if yaw_lateral_dir.length() > 0.001:
		yaw_lateral_dir = yaw_lateral_dir.normalized()
	var previous_yaw_lateral_dir: Vector3 = _drift_prev_lateral_dir
	previous_yaw_lateral_dir -= up_for_turn * previous_yaw_lateral_dir.dot(up_for_turn)
	if previous_yaw_lateral_dir.length() > 0.001:
		previous_yaw_lateral_dir = previous_yaw_lateral_dir.normalized()
	if previous_yaw_lateral_dir.length() > 0.001 and yaw_lateral_dir.length() > 0.001 and delta > 0.0:
		var signed_angle_rad: float = previous_yaw_lateral_dir.signed_angle_to(yaw_lateral_dir, up_for_turn)
		if abs(signed_angle_rad) > 0.00001:
			current_turn_speed_deg_per_sec = rad_to_deg(signed_angle_rad) / delta

	_drift_turn_speed_last = current_turn_speed_deg_per_sec
	if abs(_drift_turn_speed_last) > 0.0001:
		_drift_turn_speed_memory_timer = max(airborne_torque_yaw_turn_rate_memory_time, 0.0)
	else:
		_drift_turn_speed_memory_timer = max(_drift_turn_speed_memory_timer - timer_delta, 0.0)

	var airborne_yaw_turn_speed: float = 0.0
	var input_strength_for_yaw: float = movement_input_strength
	if input_strength_for_yaw >= airborne_torque_yaw_input_min_strength \
			and yaw_lateral_dir.length() > 0.001 \
			and abs(current_turn_speed_deg_per_sec) > 0.0001:
		var input_yaw_dir: Vector3 = _move_direction - up_for_turn * _move_direction.dot(up_for_turn)
		if input_yaw_dir.length() > 0.001:
			input_yaw_dir = input_yaw_dir.normalized()
			var input_side_amount: float = yaw_lateral_dir.cross(input_yaw_dir).dot(up_for_turn)
			var input_angle_deg: float = rad_to_deg(asin(clamp(input_side_amount, -1.0, 1.0)))
			var min_input_angle: float = max(airborne_torque_yaw_input_min_angle_deg, 0.0)
			if abs(input_angle_deg) >= min_input_angle and sign(input_angle_deg) == sign(current_turn_speed_deg_per_sec):
				airborne_yaw_turn_speed = current_turn_speed_deg_per_sec

	_airborne_torque_yaw_turn_speed_last = airborne_yaw_turn_speed
	if abs(_airborne_torque_yaw_turn_speed_last) > 0.0001:
		_airborne_torque_yaw_turn_speed_memory_timer = max(airborne_torque_yaw_turn_rate_memory_time, 0.0)
	else:
		_airborne_torque_yaw_turn_speed_memory_timer = max(_airborne_torque_yaw_turn_speed_memory_timer - timer_delta, 0.0)

	if yaw_lateral_dir.length() > 0.001:
		_drift_prev_lateral_dir = yaw_lateral_dir
	else:
		_drift_prev_lateral_dir = Vector3.ZERO

	_update_drift_reward(timer_delta, lateral_speed_final, current_turn_speed_deg_per_sec)

	var drift_camera_influence: float = 0.0
	if _drift_active and is_attached:
		drift_camera_influence = 1.0
		if _drift_exit_active:
			drift_camera_influence = clamp(_drift_exit_blend, 0.0, 1.0)
	var drift_camera_active: bool = drift_camera_influence > 0.0
	var drift_heading_dir: Vector3 = lateral_dir
	if drift_heading_dir.length() < 0.001:
		drift_heading_dir = _model_forward
	_update_drift_camera_rig(
		drift_heading_dir,
		drift_camera_active,
		current_turn_speed_deg_per_sec,
		drift_camera_influence
	)
	_update_drift_sfx(timer_delta, lateral_speed_final, current_turn_speed_deg_per_sec)

	# --- RECOMBINE VELOCITY FROM LATERAL + VERTICAL ---
	var v_final: Vector3 = lateral + physics_up * vertical
	v_final = _apply_attack_magnetism(delta, physics_up, v_final)
	v_final = _adjust_final_movement_velocity(v_final, physics_up)

	# --------------------------------------------------
	# Spring alignment: lock sideways while timer active
	# --------------------------------------------------
	if in_spring_state \
		and _spring_align_dir.length() > 0.001 \
		and _spring_lock_sideways:

		var dir: Vector3 = _spring_align_dir.normalized()
		# Decompose final velocity into "along spring" + "sideways"
		var along_speed: float = v_final.dot(dir)
		var v_along: Vector3 = dir * along_speed
		var v_side: Vector3 = v_final - v_along

		# Optionally keep a bit of sideways from gravity, etc.
		if _spring_sideways_gravity_scale <= 0.0:
			v_final = v_along
		else:
			v_final = v_along + v_side * _spring_sideways_gravity_scale

	# --------------------------------------------------
	# Ramp impulse holds: override forward/up components while active.
	# Applied after caps so ramps can enforce absolute components.
	# --------------------------------------------------
	if _ramp_hold_forward_timer > 0.0 or _ramp_hold_up_timer > 0.0:
		var rup: Vector3 = _ramp_hold_up_dir
		if rup.length() < 0.001:
			rup = _get_gravity_up()
		else:
			rup = rup.normalized()

		var rfwd: Vector3 = _ramp_hold_forward_dir
		rfwd -= rup * rfwd.dot(rup)
		if rfwd.length() < 0.001:
			rfwd = -Vector3.FORWARD - rup * (-Vector3.FORWARD).dot(rup)
		if rfwd.length() < 0.001:
			rfwd = Vector3.FORWARD
		rfwd = rfwd.normalized()

		var cur_up: float = v_final.dot(rup)
		var cur_fwd: float = v_final.dot(rfwd)
		var rest: Vector3 = v_final - rup * cur_up - rfwd * cur_fwd

		if _ramp_hold_forward_timer > 0.0:
			cur_fwd = _ramp_hold_forward_speed
		if _ramp_hold_up_timer > 0.0:
			cur_up = _ramp_hold_up_speed

		v_final = rest + rfwd * cur_fwd + rup * cur_up

	if in_race_countdown:
		v_final = Vector3.ZERO

	velocity = v_final
	if water_physics_enabled and _running_on_water_surface and attached:
		_check_water_surface_min_speed()

	if not is_attached:
		_last_air_velocity = v_final


func _adjust_final_movement_velocity(movement_velocity: Vector3, _physics_up: Vector3) -> Vector3:
	return movement_velocity


func _apply_fast_fall_horizontal_drag(
	lateral_velocity: Vector3,
	vertical_speed: float,
	delta: float
) -> Vector3:
	if not fast_fall_horizontal_drag_enabled or delta <= 0.0:
		return lateral_velocity
	if lateral_velocity.length_squared() <= 0.000001:
		return lateral_velocity
	if not _current_action_receives_fast_fall_horizontal_drag():
		return lateral_velocity

	var downward_speed: float = max(-vertical_speed, 0.0)
	var start_speed: float = max(fast_fall_horizontal_drag_start_speed, 0.0)
	if downward_speed <= start_speed:
		return lateral_velocity

	var full_speed: float = max(fast_fall_horizontal_drag_full_speed, start_speed + 0.001)
	var drag_weight: float = clamp(
		(downward_speed - start_speed) / (full_speed - start_speed),
		0.0,
		1.0
	)
	var drag_decel: float = max(fast_fall_horizontal_drag_max_decel, 0.0) * drag_weight
	return lateral_velocity.move_toward(Vector3.ZERO, drag_decel * delta)


func _update_control_basis(
	physics_up: Vector3,
	is_attached_for_movement: bool,
	is_loop_surface: bool,
	lateral: Vector3
) -> void:
	var character_up: Vector3 = physics_up.normalized()
	if character_up.length() < 0.001:
		character_up = _get_gravity_up()

	var use_player_up_cam: bool = false
	if camera_rig != null and camera_rig.has_method("get_use_player_up_effective"):
		var result = camera_rig.call("get_use_player_up_effective")
		if result is bool:
			use_player_up_cam = bool(result)

	var cam_fwd_char: Vector3
	var cam_right_char: Vector3

	if use_player_up_cam and camera_rig != null and camera_rig.has_method("get_yaw_forward"):
		# Camera follows player up; yaw forward is already in the correct frame.
		cam_fwd_char = camera_rig.get_yaw_forward()
		cam_fwd_char -= character_up * cam_fwd_char.dot(character_up)
		if cam_fwd_char.length() < 0.001:
			cam_fwd_char = _control_forward
		cam_fwd_char = cam_fwd_char.normalized()

		cam_right_char = cam_fwd_char.cross(character_up)
		if cam_right_char.length() < 0.001:
			cam_right_char = Vector3.RIGHT - character_up * Vector3.RIGHT.dot(character_up)
		if cam_right_char.length() < 0.001:
			cam_right_char = Vector3.RIGHT
		cam_right_char = cam_right_char.normalized()
	else:
		var world_up: Vector3 = _get_gravity_up()

		# 1) Camera forward/right in the gravity-up frame.
		var cam_fwd_world: Vector3 = _get_camera_forward_world_up(world_up)
		if cam_fwd_world.length() < 0.001:
			cam_fwd_world = -Vector3.FORWARD
		cam_fwd_world = cam_fwd_world.normalized()

		var cam_right_world: Vector3 = cam_fwd_world.cross(world_up)
		if cam_right_world.length() < 0.001:
			cam_right_world = Vector3.RIGHT - world_up * Vector3.RIGHT.dot(world_up)
			if cam_right_world.length() < 0.001:
				cam_right_world = Vector3.RIGHT
		cam_right_world = cam_right_world.normalized()

		# 2) Rotate the gravity-up frame into the character-up frame.
		var rot_world_to_char: Basis = PlayerMath.basis_from_to(world_up, character_up)

		cam_fwd_char = rot_world_to_char * cam_fwd_world
		cam_right_char = rot_world_to_char * cam_right_world

		# 3) Project onto tangent plane of character_up
		cam_fwd_char -= character_up * cam_fwd_char.dot(character_up)
		if cam_fwd_char.length() < 0.001:
			cam_fwd_char = _control_forward
		cam_fwd_char = cam_fwd_char.normalized()

		cam_right_char -= character_up * cam_right_char.dot(character_up)
		if cam_right_char.length() < 0.001:
			cam_right_char = cam_fwd_char.cross(character_up)
			if cam_right_char.length() < 0.001:
				cam_right_char = Vector3.RIGHT - character_up * Vector3.RIGHT.dot(character_up)
		if cam_right_char.length() < 0.001:
			cam_right_char = Vector3.RIGHT
		cam_right_char = cam_right_char.normalized()

	_control_forward = cam_fwd_char
	_control_right = cam_right_char

	# behavioral flag only (for turn penalty, etc.)
	_loop_control_active = is_attached_for_movement and is_loop_surface
	
func _update_stick(physics_up: Vector3) -> void:
	# Magnitude of stick (0..1)
	_stick_length = _move_input.length()

	if _move_direction == Vector3.ZERO:
		_stick_turn = 0.0
		return

	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var look: Vector3 = _control_forward
	var move: Vector3 = _move_direction

	# Project both onto tangent plane
	look -= up * look.dot(up)
	move -= up * move.dot(up)

	if look.length() < 0.001 or move.length() < 0.001:
		_stick_turn = 0.0
		return

	look = look.normalized()
	move = move.normalized()

	# Signed angle: +left / -right around up
	_stick_turn = look.signed_angle_to(move, up)


# ===========================================================
# Apply landing momentum (speed retention, all surfaces)
# ===========================================================
func _apply_landing_momentum(landing_normal: Vector3, incoming_velocity: Vector3) -> void:
	var n: Vector3 = landing_normal.normalized()
	if n.length() < 0.001:
		velocity = Vector3.ZERO
		return

	var v: Vector3 = incoming_velocity
	var speed: float = v.length()
	if speed <= 0.01:
		velocity = Vector3.ZERO
		return

	var world_up: Vector3 = _get_gravity_up()

	# Angle vs gravity-up: 0° = floor, 90° = wall, 180° = ceiling.
	var dot_up : float = clamp(n.dot(world_up), -1.0, 1.0)
	var surf_angle_deg: float = rad_to_deg(acos(dot_up))

	# Broad classification
	var is_floor_like: bool = surf_angle_deg <= landing_floor_max_angle_deg

	# Decompose into normal + tangential components
	var v_normal: Vector3 = n * v.dot(n)
	var v_tangent: Vector3 = v - v_normal
	var tangent_speed: float = v_tangent.length()
	if _should_land_stationary(n, v):
		velocity = Vector3.ZERO
		return

	# ---------------------------------------------
	# 1) Floor-like surfaces: allow full stops
	# ---------------------------------------------
	if is_floor_like:
		# Keep some portion of tangential speed on floors (set to 0 for hard stops).
		var keep_frac: float = landing_tangent_retention_scale * landing_global_scale * landing_floor_retention_scale
		keep_frac = clamp(keep_frac, 0.0, 1.0)

		velocity = v_tangent.normalized() * (tangent_speed * keep_frac)
		return

	# ---------------------------------------------
	# 2) Non-floor surfaces (ramps / loops / walls)
	#     → NEVER hard-stop just from angle math
	# ---------------------------------------------
	if tangent_speed < 0.001:
		# If we somehow hit almost perfectly head-on on a steep surface,
		# treat it as a pure "redirect": take full speed along surface.
		# This prevents the "dead stop on a loop tri" problem.
		v_tangent = v - n * v.dot(n)
		tangent_speed = v_tangent.length()
		if tangent_speed < 0.001:
			# Extremely degenerate case, keep original velocity.
			velocity = v
			return

	# Optional: convert some *normal* (into-surface) speed into along-surface
		# for bowls / loop bottoms. Uses configured tilt range params.
	var tilt: float = 90.0 - surf_angle_deg
	tilt = clamp(abs(tilt), landing_convert_min_tilt_deg, landing_convert_max_tilt_deg)
	var tilt_t: float = 0.0
	if landing_convert_max_tilt_deg > landing_convert_min_tilt_deg:
		tilt_t = (tilt - landing_convert_min_tilt_deg) / (landing_convert_max_tilt_deg - landing_convert_min_tilt_deg)
		tilt_t = clamp(tilt_t, 0.0, 1.0)

	var convert_amount: float = v_normal.length() * landing_vertical_to_tangent_scale * tilt_t
	if convert_amount > 0.0 and landing_vertical_to_tangent_scale > 0.0:
		var tangent_dir: Vector3 = v_tangent.normalized()
		v_tangent = tangent_dir * (tangent_speed + convert_amount)
		tangent_speed = v_tangent.length()

	# Base keep factor for steep surfaces
	var keep_frac_nonfloor: float = landing_tangent_retention_scale * landing_global_scale
	keep_frac_nonfloor = clamp(keep_frac_nonfloor, 0.0, 1.0)

	# Optional: scale keep factor with tilt so steeper surfaces keep more speed
	var min_tilt: float = landing_min_tilt_deg
	var max_tilt: float = landing_full_tilt_deg
	var tilt_for_keep : float = clamp(surf_angle_deg, min_tilt, max_tilt)
	var keep_t: float = 0.0
	if max_tilt > min_tilt:
		keep_t = (tilt_for_keep - min_tilt) / (max_tilt - min_tilt)
		keep_t = clamp(keep_t, 0.0, 1.0)

	var keep_frac : float = lerp(landing_floor_retention_scale, 1.0, keep_t) * keep_frac_nonfloor
	keep_frac = clamp(keep_frac, 0.0, 1.0)

	var final_speed: float = tangent_speed * keep_frac
	if final_speed < landing_stop_speed_threshold * 0.25:
		# On steep stuff, never fully stop – keep at least a trickle.
		final_speed = max(final_speed, landing_stop_speed_threshold * 0.25)

	velocity = v_tangent.normalized() * final_speed


func _should_land_stationary(landing_normal: Vector3, incoming_velocity: Vector3) -> bool:
	if rolling:
		return false
	if _move_input != Vector2.ZERO:
		return false
	var speed_threshold: float = max(landing_stop_speed_threshold, 0.0)
	if speed_threshold <= 0.0:
		return false
	var n: Vector3 = landing_normal.normalized()
	var gravity_up_direction: Vector3 = _get_gravity_up()
	if n.length() < 0.001 or gravity_up_direction.length() < 0.001:
		return false
	var surface_angle_deg: float = rad_to_deg(acos(clamp(n.dot(gravity_up_direction), -1.0, 1.0)))
	if surface_angle_deg > max(stationary_landing_max_angle_deg, 0.0):
		return false
	var incoming_tangent_speed: float = incoming_velocity.slide(n).length()
	return incoming_tangent_speed < speed_threshold

# ===========================================================
# GENERAL HELPERS
# ===========================================================

func set_gravity_up(new_up: Vector3) -> void:
	_ensure_modules()
	_gravity_module.set_base_up(new_up)

func get_gravity_up() -> Vector3:
	_ensure_modules()
	return _gravity_module.get_up()

func get_gravity_down() -> Vector3:
	_ensure_modules()
	return _gravity_module.get_down()

func get_gravity_vertical_component(vector: Vector3) -> float:
	_ensure_modules()
	return _gravity_module.get_vertical_component(vector)

func get_gravity_planar_component(vector: Vector3) -> Vector3:
	_ensure_modules()
	return _gravity_module.get_planar_component(vector)

func compose_gravity_vector(planar: Vector3, vertical: float) -> Vector3:
	_ensure_modules()
	return _gravity_module.compose_vector(planar, vertical)

func rotate_vector_between_gravity_frames(
	vector: Vector3,
	from_up: Vector3,
	to_up: Vector3
) -> Vector3:
	_ensure_modules()
	return _gravity_module.rotate_between_frames(vector, from_up, to_up)

func _get_gravity_up() -> Vector3:
	_ensure_modules()
	return _gravity_module.get_up()

func get_base_gravity_up() -> Vector3:
	_ensure_modules()
	return _gravity_module.get_base_up()

func _get_base_gravity_up() -> Vector3:
	_ensure_modules()
	return _gravity_module.get_base_up()

func get_base_gravity_strength() -> float:
	_ensure_modules()
	return _gravity_module.get_base_strength()

func get_effective_gravity_strength() -> float:
	_ensure_modules()
	return _gravity_module.get_effective_strength()

func get_gravity_acceleration_vector() -> Vector3:
	_ensure_modules()
	return _gravity_module.get_acceleration_vector()

func apply_gravity_modifier(
	source: Object,
	new_gravity_up: Vector3,
	gravity_multiplier: float = 1.0,
	duration: float = -1.0,
	priority: int = 0,
	blend_with_planetary: bool = false,
	clear_on_death: bool = true,
	clear_on_respawn: bool = true,
	clear_on_level_restart: bool = true,
	clear_on_race_cleanup: bool = true
) -> void:
	_ensure_modules()
	_gravity_module.apply_modifier(
		source,
		new_gravity_up,
		gravity_multiplier,
		duration,
		priority,
		blend_with_planetary,
		clear_on_death,
		clear_on_respawn,
		clear_on_level_restart,
		clear_on_race_cleanup
	)

func remove_gravity_modifier(source: Object) -> void:
	_ensure_modules()
	_gravity_module.remove_modifier(source)

func register_planetary_gravity_source(source: Node) -> void:
	_ensure_modules()
	_gravity_module.register_planetary_source(source)

func unregister_planetary_gravity_source(source: Node) -> void:
	_ensure_modules()
	_gravity_module.unregister_planetary_source(source)

func clear_gravity_state(reason: StringName = &"all", clear_planetary: bool = true) -> void:
	_ensure_modules()
	_gravity_module.clear_state(reason, clear_planetary)

func _gravity_modifier_clears_for_reason(modifier: Dictionary, reason: StringName) -> bool:
	_ensure_modules()
	return _gravity_module.modifier_clears_for_reason(modifier, reason)

func _update_gravity_state(delta: float) -> void:
	_ensure_modules()
	_gravity_module.update_state(delta)

func apply_teleport(exit_transform: Transform3D, keep_vel: bool, match_rot: bool, exit_local_offset: Vector3) -> void:
	_ensure_modules()
	_external_motion_module.apply_teleport(exit_transform, keep_vel, match_rot, exit_local_offset)

func _apply_grounded_from_downwarp(grounded_point: Vector3, grounded_normal: Vector3) -> void:
	_ensure_modules()
	_external_motion_module._apply_grounded_from_downwarp(grounded_point, grounded_normal)

func _apply_grounded_after_debug_exit() -> void:
	# SUMMARY: Set grounded state if a surface is directly below after debug fly.
	# STEPS:
	# - Step 1: Raycast downward along gravity-up to find ground.
	# - Step 2: Apply grounded state from the hit result.
	var world: World3D = get_world_3d()
	if world == null:
		return

	var up: Vector3 = _get_gravity_up()

	var cast_len: float = max(ground_ray_length, collision_ground_distance)
	cast_len = max(cast_len, 0.1)

	var from_pos: Vector3 = global_position + up * 0.1
	var to_pos: Vector3 = global_position - up * cast_len
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	params.exclude = [self]

	var mask: int = collision_mask
	if ground_ray != null:
		mask = ground_ray.collision_mask
	params.collision_mask = mask

	var hit: Dictionary = world.direct_space_state.intersect_ray(params)
	if hit and not _is_surface_alignment_rejected(
		hit.get("collider"),
		hit.get("normal", Vector3.ZERO),
		up,
		int(hit.get("shape", -1))
	):
		var hit_point: Vector3 = hit.position
		var hit_normal: Vector3 = hit.normal
		_apply_grounded_from_downwarp(hit_point, hit_normal)


func apply_teleport_from_exit(exit_node: Node3D, keep_vel: bool, match_rot: bool, exit_local_offset: Vector3) -> void:
	_ensure_modules()
	_external_motion_module.apply_teleport_from_exit(exit_node, keep_vel, match_rot, exit_local_offset)

func _sync_buddy_after_leader_teleport() -> void:
	_ensure_modules()
	_buddy_module._sync_buddy_after_leader_teleport()

func _reproject_velocity_onto_new_surface(prev_n: Vector3, new_n: Vector3) -> void:
	var v: Vector3 = velocity
	var speed: float = v.length()
	if speed <= 0.01:
		return

	var n0: Vector3 = prev_n.normalized()
	var n1: Vector3 = new_n.normalized()
	if n0.length() < 0.001 or n1.length() < 0.001:
		return

	# Project current velocity onto the new surface
	var v_tangent_new: Vector3 = v - n1 * v.dot(n1)

	# If that somehow degenerates, fall back to previous-surface tangent
	if v_tangent_new.length() < 0.001:
		var v_tangent_prev: Vector3 = v - n0 * v.dot(n0)
		if v_tangent_prev.length() > 0.001:
			v_tangent_new = v_tangent_prev

	if v_tangent_new.length() < 0.001:
		# Nothing sensible to do; keep original velocity
		return

	# Keep the original speed, just rotate the direction into the new tangent plane
	var v_reproj: Vector3 = v_tangent_new.normalized() * speed
	if _dbg_dynbody and (_follow_collider_last != null and is_instance_valid(_follow_collider_last) and _follow_collider_last is RigidBody3D):
		var angle_change: float = rad_to_deg(acos(clamp(n0.dot(n1), -1.0, 1.0)))
		print("[DYN] REPROJ n_delta=%.2f° spd_before=%.3f spd_after=%.3f dir_before=%v dir_after=%v" % [angle_change, speed, v_reproj.length(), v.normalized(), v_reproj.normalized()])
	velocity = v_reproj


func _reset_fall_air_decel_ramp() -> void:
	# SUMMARY: Reset the fall-off air decel ramp to full strength.
	# STEPS:
	# - Step 1: Clear the delay timer.
	# - Step 2: Restore the scale to full decel.
	_fall_air_decel_delay_timer = 0.0
	_fall_air_decel_scale_current = 1.0


func _start_fall_air_decel_ramp() -> void:
	# SUMMARY: Start the fall-off air decel ramp at zero with a delay.
	# STEPS:
	# - Step 1: Load the delay timer.
	# - Step 2: Force the decel scale to 0.0 until the delay ends.
	_fall_air_decel_delay_timer = max(fall_air_decel_delay, 0.0)
	_fall_air_decel_scale_current = 0.0


func _get_fall_off_air_decel(delta: float, base_air_decel: float) -> float:
	# SUMMARY: Get the effective air decel when falling off without jumping.
	# STEPS:
	# - Step 1: If not in fall-off state, reset the ramp and return full air_decel.
	# - Step 2: While delay is active, keep decel at 0.
	# - Step 3: Slerp toward full decel after the delay.
	if not _falling_without_jump:
		_reset_fall_air_decel_ramp()
		return base_air_decel

	if _fall_air_decel_delay_timer > 0.0:
		_fall_air_decel_delay_timer = max(_fall_air_decel_delay_timer - get_gameplay_timer_delta(delta), 0.0)
		_fall_air_decel_scale_current = 0.0
		return 0.0

	_fall_air_decel_scale_current = _slerp_scalar(
		_fall_air_decel_scale_current,
		1.0,
		fall_air_decel_slerp_speed,
		delta
	)
	return base_air_decel * _fall_air_decel_scale_current


func _reset_air_top_speed_ramp() -> void:
	# SUMMARY: Reset the air top speed ramp to default.
	_air_top_speed_detach_timer = 0.0
	_air_top_speed_detach_active = false
	_air_top_speed_current = air_top_speed


func _start_air_top_speed_ramp(from_speed: float) -> void:
	# SUMMARY: Start the air top speed ramp from a grounded speed.
	_air_top_speed_detach_timer = max(air_top_speed_detach_delay, 0.0)
	_air_top_speed_detach_active = true
	_air_top_speed_current = max(from_speed, 0.0)


func _get_effective_air_top_speed(delta: float, is_attached: bool) -> float:
	# SUMMARY: Compute air top speed with a detach delay + slerp.
	var target_air_top_speed: float = air_top_speed
	if is_attached:
		_reset_air_top_speed_ramp()
		return target_air_top_speed
	if not _air_top_speed_detach_active:
		return target_air_top_speed
	if _air_top_speed_detach_timer > 0.0:
		_air_top_speed_detach_timer = max(_air_top_speed_detach_timer - get_gameplay_timer_delta(delta), 0.0)
		return _air_top_speed_current
	_air_top_speed_current = _slerp_scalar(
		_air_top_speed_current,
		target_air_top_speed,
		air_top_speed_detach_slerp_speed,
		delta
	)
	return _air_top_speed_current


func _reset_directional_influence_lock() -> void:
	_directional_influence_lock_strength = 0.0
	_directional_influence_lock_speed_t = 0.0
	_directional_influence_lock_accel_strength = 0.0
	_directional_influence_lock_turn_strength = 0.0
	_directional_influence_lock_air_turn_penalty_strength = 0.0
	_directional_influence_lock_accel_delay_timer = 0.0
	_directional_influence_lock_turn_delay_timer = 0.0
	_directional_influence_lock_air_turn_penalty_delay_timer = 0.0
	_directional_influence_lock_accel_multiplier = 1.0
	_directional_influence_lock_turn_multiplier = 1.0
	_directional_influence_lock_air_turn_penalty_multiplier = 1.0


func _start_directional_influence_lock(detach_speed: float, detach_angle_deg: float) -> void:
	if not launch_momentum_control_enabled:
		_reset_directional_influence_lock()
		return
	var full_speed: float = max(launch_momentum_full_speed, 0.001)
	var min_speed: float = full_speed * 0.35
	var speed_t: float = clamp((detach_speed - min_speed) / (full_speed - min_speed), 0.0, 1.0)
	if speed_t <= 0.0:
		_reset_directional_influence_lock()
		return

	var angle_t: float = _smoothstep_unit((clamp(detach_angle_deg, 0.0, 90.0) - 10.0) / 80.0)
	if angle_t <= 0.0:
		_reset_directional_influence_lock()
		return

	_directional_influence_lock_strength = max(_directional_influence_lock_strength, speed_t * angle_t)
	_directional_influence_lock_speed_t = max(_directional_influence_lock_speed_t, speed_t)
	_directional_influence_lock_accel_strength = _directional_influence_lock_strength
	_directional_influence_lock_turn_strength = _directional_influence_lock_strength
	_directional_influence_lock_air_turn_penalty_strength = 0.0
	_directional_influence_lock_accel_delay_timer = 0.0
	_directional_influence_lock_turn_delay_timer = 0.0
	_directional_influence_lock_air_turn_penalty_delay_timer = 0.0
	_update_directional_influence_lock_multipliers()


func _ensure_directional_influence_lock_for_detach(detach_normal: Vector3, world_up: Vector3) -> void:
	if _directional_influence_lock_strength > 0.0:
		return
	var n: Vector3 = _get_filtered_detach_normal(detach_normal, world_up)
	if n.length() < 0.001:
		n = world_up
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	n = n.normalized()
	var dot_up: float = clamp(n.dot(up), -1.0, 1.0)
	var angle_deg: float = rad_to_deg(acos(dot_up))
	_dbg_last_detach_normal = n
	_dbg_last_detach_world_angle = angle_deg
	_start_directional_influence_lock(velocity.length(), angle_deg)


func _ensure_directional_influence_lock_for_recent_detach(world_up: Vector3) -> void:
	if _directional_influence_lock_strength > 0.0:
		return
	if _airborne_time > max(nonfloor_to_wall_grace_time, 0.08):
		return
	if _rail_active or _spline_active or _lightspeed_dash_active or _homing_active:
		return
	_ensure_directional_influence_lock_for_detach(_last_attach_normal, world_up)


func _update_directional_influence_lock(
	delta: float,
	is_attached: bool,
	in_spring_state: bool,
	auto_active: bool
) -> void:
	if not launch_momentum_control_enabled \
			or is_attached \
			or in_spring_state \
			or auto_active \
			or _rail_active \
			or _spline_active \
			or _lightspeed_dash_active \
			or _homing_active:
		_reset_directional_influence_lock()
		return
	if _directional_influence_lock_strength <= 0.0:
		_reset_directional_influence_lock()
		return
	var recovery_time: float = max(launch_momentum_recovery_time, 0.001)
	var recovery_step: float = max(delta, 0.0) / recovery_time
	_directional_influence_lock_strength = move_toward(_directional_influence_lock_strength, 0.0, recovery_step)
	_directional_influence_lock_accel_strength = _directional_influence_lock_strength
	_directional_influence_lock_turn_strength = _directional_influence_lock_strength
	_directional_influence_lock_air_turn_penalty_strength = 0.0
	_update_directional_influence_lock_multipliers()


func _update_directional_influence_lock_multipliers() -> void:
	var accel_strength: float = clamp(_directional_influence_lock_accel_strength, 0.0, 1.0)
	var turn_strength: float = clamp(_directional_influence_lock_turn_strength, 0.0, 1.0)
	var min_control: float = clamp(launch_momentum_min_control, 0.0, 1.0)
	_directional_influence_lock_accel_multiplier = lerp(1.0, min_control, accel_strength)
	_directional_influence_lock_turn_multiplier = lerp(1.0, min_control, turn_strength)
	_directional_influence_lock_air_turn_penalty_multiplier = 1.0


func _update_fall_flag(delta: float) -> void:
	# This is the ONLY place that should set _is_falling.

	var world_up: Vector3 = _get_gravity_up()
	var up: Vector3 = _physics_up_last.normalized()
	if up.length() < 0.001:
		up = world_up

	# --------------------------------------------------
	# 1) Any grounded / floor-supported condition
	#    → NOT falling, reset airborne timer.
	# --------------------------------------------------

	# a) Our custom attachment flag.
	if attached:
		_is_falling = false
		_airborne_time = 0.0
		_clear_coyote_jump_window()
		_jumped_from_ground = false
		_falling_without_jump = false
		_reset_fall_air_decel_ramp()
		_reset_air_top_speed_ramp()
		return

	# b) CharacterBody3D's own floor test as a safety net.
	if is_on_floor():
		if not _coyote_jump_available:
			_is_falling = false
			_airborne_time = 0.0
			_clear_coyote_jump_window()
			_jumped_from_ground = false
			_falling_without_jump = false
			_reset_fall_air_decel_ramp()
			_reset_air_top_speed_ramp()
			return

	# c) Extra safety: if we're NOT attached but we are
	#    sliding along a floor-like contact normal, treat it
	#    as supported for the purposes of the falling flag.
	var collision_count: int = get_slide_collision_count()
	if collision_count > 0:
		for i in collision_count:
			var col: KinematicCollision3D = get_slide_collision(i)
			var n: Vector3 = col.get_normal().normalized()
			if n.length() < 0.001:
				continue

			var dot_up : float = clamp(n.dot(world_up), -1.0, 1.0)
			var angle_deg: float = rad_to_deg(acos(dot_up))
				# Same idea as landing_floor_max_angle_deg.
			if angle_deg <= landing_floor_max_angle_deg:
				# We're clearly riding a floor-ish surface.
				if not _coyote_jump_available:
					_is_falling = false
					_airborne_time = 0.0
					_clear_coyote_jump_window()
					_jumped_from_ground = false
					_falling_without_jump = false
					_reset_fall_air_decel_ramp()
					_reset_air_top_speed_ramp()
					return

	# --------------------------------------------------
	# 2) Truly airborne: use vertical speed to decide.
	# --------------------------------------------------
	_airborne_time += delta

	var vertical: float = velocity.dot(up)

	if _prev_attached and not attached and not _jumped_from_ground:
		_falling_without_jump = true
		_start_fall_air_decel_ramp()

	if _prev_attached and not attached:
		_start_air_top_speed_ramp(_last_grounded_top_speed)

	_update_coyote_jump_window(delta)

	if not _falling_without_jump:
		_reset_fall_air_decel_ramp()
		_is_falling = false
		return

	# Grace window: don't instantly flag as falling the
	# moment we leave the ground.
	if _airborne_time < fall_airborne_grace_time:
		# During grace we can optionally clear the flag if
		# we're not meaningfully going downward.
		if vertical >= -fall_vertical_speed_threshold * 0.5:
			_is_falling = false
		return

	# Main classification:
	#  - vertical < -threshold  → falling
	#  - roughly flat/upwards   → not falling
	if vertical < -fall_vertical_speed_threshold:
		_is_falling = true
	elif vertical > -fall_vertical_speed_threshold * 0.25:
		# Small downward drift near zero cancels the flag
		# so we don't stay "falling" while scraping along.
		_is_falling = false
	# else: keep previous _is_falling value (e.g. short apex)


func _apply_airborne_collision_state() -> void:
	# Reverted experimental airborne collision toggling — no-op to restore normal behavior.
	return

func _clear_coyote_jump_window() -> void:
	_coyote_jump_available = false
	_coyote_jump_timer = 0.0
	_set_coyote_available_ui(false)


func remove_coyote_jump_eligibility() -> void:
	_coyote_jump_requested = false
	_clear_coyote_jump_window()


func refresh_coyote_jump_window_custom(duration: float) -> void:
	if not coyote_jump_enabled:
		return
	_coyote_jump_available = true
	_coyote_jump_timer = max(duration, 0.0)
	_set_coyote_available_ui(true)


func can_use_tornado_kick() -> bool:
	return not _tornado_kick_used_this_air


func mark_tornado_kick_used() -> void:
	_tornado_kick_used_this_air = true


func refresh_tornado_kick_availability() -> void:
	_tornado_kick_used_this_air = false
	var uppercut: CharacterAction = _get_action_by_id(&"uppercut_kick")
	if uppercut:
		uppercut.refresh_airborne_availability()


func _is_simple_coyote_detach_state() -> bool:
	if _last_detach_angle_deg > coyote_jump_max_angle_deg:
		return false
	return true


func _start_coyote_jump_window() -> void:
	if is_surface_coyote_jump_blocked():
		_clear_coyote_jump_window()
		return
	if not coyote_jump_enabled:
		_clear_coyote_jump_window()
		return
	if not _is_simple_coyote_detach_state():
		if not _coyote_jump_available:
			_clear_coyote_jump_window()
		return
	_coyote_jump_available = true
	_coyote_jump_timer = max(coyote_jump_duration, 0.0)
	_set_coyote_available_ui(true)


func _update_coyote_jump_window(delta: float) -> void:
	if not _coyote_jump_available:
		return
	if attached:
		_clear_coyote_jump_window()
		return
	if coyote_jump_duration <= 0.0:
		return
	_coyote_jump_timer = max(_coyote_jump_timer - delta, 0.0)
	if _coyote_jump_timer <= 0.0:
		_coyote_jump_available = false
		_set_coyote_available_ui(false)


func _can_consume_coyote_jump() -> bool:
	if not coyote_jump_enabled:
		return false
	if is_surface_coyote_jump_blocked():
		return false
	if _ui_input_blocked:
		return false
	if attached:
		return false
	if _rail_active or _rail_switch_active or _spline_active:
		return false
	if not _coyote_jump_available:
		return false
	if coyote_jump_duration <= 0.0:
		return true
	return _coyote_jump_timer > 0.0


func can_consume_coyote_jump() -> bool:
	return _can_consume_coyote_jump()


func _update_platform_carry_state() -> void:
	_platform_on_floor_last = false
	_platform_velocity_last = Vector3.ZERO
	_platform_collider_last = null

	var up: Vector3 = _physics_up_last.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var world_up: Vector3 = _get_gravity_up()

	var surf_n: Vector3 = surface_normal.normalized()
	if surf_n.length() < 0.001:
		surf_n = world_up
	var dot_up: float = clamp(surf_n.dot(world_up), -1.0, 1.0)
	var surf_angle_deg: float = rad_to_deg(acos(dot_up))
	var floor_like_attached: bool = attached and surf_angle_deg <= adhesion_floor_max_angle_deg

	var collider: Object = null
	if is_on_floor() or floor_like_attached:
		var col: KinematicCollision3D = _get_best_floor_slide_collision(up)
		if col != null:
			collider = col.get_collider()

	if collider == null and floor_like_attached and _follow_collider_last != null and is_instance_valid(_follow_collider_last):
		collider = _follow_collider_last

	if collider == null:
		return
	if not (collider is Node3D):
		return

	_platform_on_floor_last = true
	_platform_collider_last = collider as Node3D
	_platform_prev_origin = _platform_collider_last.global_position
	if collider.has_method("get_platform_velocity"):
		var v = collider.call("get_platform_velocity")
		if v is Vector3:
			_platform_velocity_last = world_to_movement_velocity(v)


func _get_best_floor_slide_collision(up: Vector3) -> KinematicCollision3D:
	var count: int = get_slide_collision_count()
	if count <= 0:
		return null

	var best: KinematicCollision3D = null
	var best_dot: float = -1.0

	for i in count:
		var col: KinematicCollision3D = get_slide_collision(i)
		if col == null:
			continue
		var n: Vector3 = col.get_normal()
		if n.length() < 0.001:
			continue
		var d: float = n.normalized().dot(up)
		if d > best_dot:
			best_dot = d
			best = col

	# Require a reasonably "floor-ish" contact.
	if best_dot < 0.5:
		return null
	return best

func has_state(flag: int) -> bool:
	return (state_flags & flag) != 0

func get_rail_entry_velocity() -> Vector3:
	_ensure_modules()
	return _rail_module.get_rail_entry_velocity()

func get_rail_entry_forward() -> Vector3:
	_ensure_modules()
	return _rail_module.get_rail_entry_forward()

func get_rail_rehit_cooldown() -> float:
	_ensure_modules()
	return _rail_module.get_rail_rehit_cooldown()

func get_rail_session_snapshot() -> Dictionary:
	_ensure_modules()
	return _rail_module.get_rail_session_snapshot()

func get_rail_switch_snapshot() -> Dictionary:
	_ensure_modules()
	return _rail_module.get_rail_switch_snapshot()

func is_on_rail_path(path: Path3D) -> bool:
	_ensure_modules()
	return _rail_module.is_on_rail_path(path)

func apply_rail_boost(
	boost_speed: float,
	boost_mode: int,
	travel_sign: float,
	source_path: Path3D = null,
	additive_min_speed: float = 0.0
) -> bool:
	_ensure_modules()
	return _rail_module.apply_rail_boost(boost_speed, boost_mode, travel_sign, source_path, additive_min_speed)

func _update_main_state_and_flags(delta: float) -> void:
	# ------------------------------
	# MAIN STATE (coarse locomotion)
	# ------------------------------
	var new_main_state: int

	if _rail_active:
		new_main_state = MainState.RAIL
	elif _spline_active:
		new_main_state = MainState.SPLINE
	elif _spring_align_timer > 0.0 and _spring_detached:
		new_main_state = MainState.SPRING
	elif attached:
		new_main_state = MainState.GROUNDED
	else:
		new_main_state = MainState.AIRBORNE

	if new_main_state != main_state:
		main_state = new_main_state
		main_state_time = 0.0
	else:
		main_state_time += delta

	# ------------------------------
	# SUB-STATE FLAGS (tags)
	# ------------------------------
	var flags: int = 0

	# Grounded vs airborne
	if attached:
		flags |= STATE_GROUNDED

	# Moving vs idle (use anim lateral speed helper if available)
	var lateral_speed: float = velocity.length()
	if _move_direction != Vector3.ZERO and lateral_speed > 0.5:
		flags |= STATE_MOVING

	# Skidding
	if _is_skidding:
		flags |= STATE_SKIDDING

	# Jumping & falling
	if _jumped_from_ground:
		flags |= STATE_JUMPING
		if _current_action_id == &"jump" and uses_fall_blend_for_jump_animation():
			flags |= STATE_JUMP_FALL_BLEND
	if _is_falling:
		flags |= STATE_FALLING

	# Loop / steep surface
	if _loop_control_active:
		flags |= STATE_LOOPING

	# Jump dash (recent)
	if _jump_dash_recent_timer > 0.0:
		flags |= STATE_JUMP_DASH

	# Spring / spline tags
	if main_state == MainState.SPRING:
		flags |= STATE_SPRING
	if main_state == MainState.SPLINE:
		flags |= STATE_SPLINE
	if main_state == MainState.RAIL:
		flags |= STATE_RAIL
		if _rail_travel_sign < 0.0:
			flags |= STATE_RAIL_BACKWARD
		else:
			flags |= STATE_RAIL_FORWARD
		if _rail_active and _spindash_charging:
			flags |= STATE_SPINDASHRAIL
	if _barrier_blast_active:
		flags |= STATE_BARRIER_BLAST
	if rolling:
		flags |= STATE_ROLL
	if _spindash_charging:
		flags |= STATE_SPINDASH
	if _drift_active:
		flags |= STATE_DRIFT
	if _current_action_id == &"skydive":
		flags |= STATE_SKYDIVE

	# Hard landing (for a few frames after impact)
	if _landing_timer > 0.0 and _last_landing_impact_speed >= _hard_landing_speed_threshold:
		flags |= STATE_LANDING_HARD

	state_flags = flags

func _update_control_anchor(physics_up: Vector3) -> void:
	if control_anchor == null:
		return

	# Use the same "up" as the movement logic.
	var up: Vector3 = physics_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	# Use the current control forward as our anchor forward.
	var f: Vector3 = _control_forward
	if f.length() < 0.001:
		f = -Vector3.FORWARD

	# Make sure forward is tangent to the current up.
	f = f - up * f.dot(up)
	if f.length() < 0.001:
		# Fallback if something degenerates
		f = -Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up)
	if f.length() < 0.001:
		f = -Vector3.FORWARD
	f = f.normalized()

	# Right = forward × up
	var r: Vector3 = f.cross(up)
	if r.length() < 0.001:
		r = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	if r.length() < 0.001:
		r = Vector3.RIGHT
	r = r.normalized()

	# Build basis: X = right, Y = up, Z = -forward (same convention as model_root)
	var basis: Basis = Basis(r, up, -f)

	# Place the anchor at the player’s origin so gizmos are intuitive.
	control_anchor.global_transform = Transform3D(basis, global_transform.origin)

# Some useful math helpers

func get_look():
	return -global_transform.basis.z

func get_up():
	return global_transform.basis.y

func get_right():
	return global_transform.basis.x

func to_speed(vector: Vector3) -> Vector3:
	var speed: Vector3 = global_transform.basis.inverse() * vector
	return Vector3(-speed.z, speed.y, speed.x) / 60

func from_speed(speed: Vector3) -> Vector3:
	var vector: Vector3 = global_transform.basis * Vector3(speed.z, speed.y, -speed.x)
	return vector * 60
	
# ===========================================================
# LOCK TO SURFACE
# ===========================================================
func _lock_to_surface() -> void:
	if not attached:
		return

	var n: Vector3 = surface_normal.normalized()
	if standing_collision_shape:
		n = get_collision_support_up()
		_set_standing_collision_enabled(false)
	if n.length() < 0.001:
		return

	var t: Transform3D = global_transform
	var current_center: Vector3 = t.origin

	var to_center: Vector3 = current_center - surface_point
	var current_dist: float = to_center.dot(n)

	var delta_dist: float = collision_ground_distance - current_dist
	var correction: Vector3 = n * delta_dist
	if _automation_force_surface_adhesion and correction.length() > 0.0001:
		move_and_collide(correction)
	else:
		t.origin = current_center + correction
		global_transform = t
	_recover_ground_support_penetration()


func _recover_ground_support_penetration() -> void:
	if not standing_collision_shape or not _ensure_main_sphere_configured():
		return
	var support_up: Vector3 = get_collision_support_up()
	var correction: Vector3 = Vector3.ZERO
	var maximum_correction: float = maxf(safe_margin, 0.001)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsShapeQueryParameters3D = _make_shape_query(
		main_collision_shape.shape, global_transform * _main_sphere_base_transform
	)
	# Adjacent curve faces can overlap a sphere tangent to the follow plane.
	for attempt: int in 4:
		var contacts: Array[Vector3] = space.collide_shape(query, 16)
		var support_distance: float = 0.0
		for index: int in range(0, contacts.size() - 1, 2):
			var separation: Vector3 = contacts[index + 1] - contacts[index]
			var depth: float = separation.length()
			if depth < 0.0001:
				continue
			var alignment: float = (separation / depth).dot(support_up)
			if alignment < 0.707:
				continue
			support_distance = maxf(support_distance, depth / alignment + 0.001)
		if support_distance <= 0.0:
			break
		correction += support_up * support_distance
		if correction.length() > maximum_correction:
			return
		query.transform.origin += support_up * support_distance
	if correction.length_squared() < 0.000001:
		return
	var sphere_transforms: Array[Transform3D] = [_main_sphere_last_transform]
	var aligned_transform: Transform3D = _get_main_sphere_transform(_main_sphere_compact)
	if not aligned_transform.is_equal_approx(_main_sphere_last_transform):
		sphere_transforms.append(aligned_transform)
	for sphere_transform: Transform3D in sphere_transforms:
		var sphere_start: Transform3D = global_transform * sphere_transform
		var sphere_end: Transform3D = sphere_start
		sphere_end.origin += correction
		if not _shape_has_clearance(main_collision_shape.shape, sphere_end):
			return
		query.transform = sphere_start
		query.motion = correction
		var fractions: PackedFloat32Array = space.cast_motion(query)
		if fractions.is_empty() or fractions[0] < 1.0:
			return
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			sphere_start.origin, sphere_end.origin
		)
		ray.collision_mask = query.collision_mask
		ray.exclude = query.exclude
		ray.collide_with_areas = false
		ray.hit_from_inside = true
		if not space.intersect_ray(ray).is_empty():
			return
	global_position += correction


# VISUAL ORIENTATION
# ===========================================================
func _update_visual_up(delta: float) -> void:
	_ensure_modules()
	if _model_module != null:
		_model_module._update_visual_up(delta)

func _update_rail_tricks(delta: float) -> void:
	_ensure_modules()
	_rail_module._update_rail_tricks(delta)

func _update_model_orientation(delta: float) -> void:
	_ensure_modules()
	if _spline_active and _spline_align_model:
		return
	if _rail_active:
		_update_rail_tricks(delta)
	if _lightspeed_dash_active and lightspeed_dash_face_target:
		_update_lightspeed_dash_model_orientation()
		return
	if _model_module != null:
		_model_module._update_model_orientation(delta)


func _update_lightspeed_dash_model_orientation() -> void:
	if model_root == null or not is_instance_valid(model_root):
		return
	var dir: Vector3 = _lightspeed_dash_last_dir
	if dir.length() < 0.001:
		dir = velocity.normalized()
	if dir.length() < 0.001:
		return
	var up: Vector3 = visual_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var basis: Basis = _build_spline_model_basis(dir, up)
	model_root.global_transform = Transform3D(basis, model_root.global_transform.origin)
	_model_forward = -basis.z


func snap_model_to_normal(normal: Vector3, forward_hint: Vector3 = Vector3.FORWARD) -> void:
	_ensure_modules()
	if _model_module != null:
		_model_module.snap_model_to_normal(normal, forward_hint)

func _is_spring_radial_landing_active() -> bool:
	if not _spring_detached:
		return false
	if _spring_align_timer > 0.0 or _spring_movement_lock_timer > 0.0:
		return true
	return _airborne_time <= nonfloor_to_wall_grace_time


func _record_spring_detach_state(world_up: Vector3 = Vector3.ZERO) -> void:
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var detach_normal: Vector3 = Vector3.ZERO
	if attached and surface_normal.length() > 0.001:
		detach_normal = surface_normal
	elif _last_detach_normal.length() > 0.001:
		detach_normal = _last_detach_normal
	elif _last_attach_normal.length() > 0.001:
		detach_normal = _last_attach_normal
	else:
		detach_normal = up

	_record_detach_state(detach_normal, up, false, false)


func _clear_spring_locks_on_landing() -> void:
	if _spring_clear_move_on_ground:
		_spring_movement_lock_timer = 0.0
	if _spring_clear_action_on_ground:
		_spring_action_lock_timer = 0.0
	_spring_clear_move_on_ground = false
	_spring_clear_action_on_ground = false
	if is_instance_valid(_spring_action):
		_sync_spring_state_to_action()


func _finish_spring_landing_state() -> void:
	_spring_align_timer = 0.0
	_spring_align_up = Vector3.ZERO
	_spring_align_forward = Vector3.ZERO
	_spring_align_dir = Vector3.ZERO
	_spring_lock_sideways = false
	_spring_sideways_gravity_scale = 0.0
	_spring_align_model = false
	_spring_model_snap_timer = 0.0
	_spring_detached = false
	_spring_trajectory_torque_active = false
	_spring_trajectory_landing_forward_pitch_active = false


func _advance_spring_alignment(delta: float) -> void:
	if _spring_action != null:
		_sync_spring_state_to_action()
		_spring_action.advance_alignment(delta)
		_sync_spring_state_from_action()
		return
	_spring_align_timer = max(_spring_align_timer - delta, 0.0)
	_spring_model_snap_timer = max(_spring_model_snap_timer - delta, 0.0)
	if _spring_align_timer <= 0.0:
		_spring_model_snap_timer = 0.0


func _record_detach_state(
	detach_normal: Vector3,
	world_up: Vector3,
	allow_air_torque: bool = true,
	filter_normal: bool = true
) -> void:
	var n: Vector3 = detach_normal.normalized()
	if n.length() < 0.001:
		n = world_up
	if filter_normal and allow_air_torque:
		n = _get_filtered_detach_normal(n, world_up)

	var dot_up: float = clamp(n.dot(world_up), -1.0, 1.0)
	var angle_deg: float = rad_to_deg(acos(dot_up))

	_last_detach_normal = n
	_last_detach_angle_deg = angle_deg
	_dbg_last_detach_normal = n
	if allow_air_torque:
		_start_directional_influence_lock(velocity.length(), angle_deg)
	else:
		_reset_directional_influence_lock()

	# True if we left something that was basically “floor-like”.
	_detached_from_floor_like = angle_deg <= floor_like_max_angle_deg
	_dbg_last_detach_world_angle = angle_deg
	_dbg_last_detach_from_floor_like = _detached_from_floor_like
	_dbg_last_detach_coyote_eligible = angle_deg <= coyote_jump_max_angle_deg
	_dbg_detach_timer = 0.25
	_reset_stable_attach_normal()

	# Reset airborne timer – this is the moment of detach.
	_airborne_time = 0.0
	var flat_detach_limit: float = max(airborne_torque_flat_detach_max_angle_deg, 0.0)
	var allow_detach_torque: bool = allow_air_torque
	if flat_detach_limit > 0.0 and angle_deg <= flat_detach_limit:
		allow_detach_torque = false
	_start_air_torque_from_detach(allow_detach_torque)
	
	var yaw_forward: Vector3 = _compute_air_torque_yaw_forward(n, world_up)
	if yaw_forward.length() > 0.001:
		_air_torque_yaw_forward = yaw_forward

	var forward_on_up: Vector3 = _model_forward - n * _model_forward.dot(n)
	if forward_on_up.length() < 0.001:
		var v_tangent: Vector3 = velocity - n * velocity.dot(n)
		if v_tangent.length() > 0.001:
			forward_on_up = v_tangent
		else:
			var fallback: Vector3 = -global_transform.basis.z
			forward_on_up = fallback - n * fallback.dot(n)
	if forward_on_up.length() > 0.001:
		_air_torque_visual_forward = forward_on_up.normalized()

	var f: Vector3 = velocity - world_up * velocity.dot(world_up)
	if f.length() > 0.01:
		_detach_forward_hint = f.normalized()


func _record_attach_state(attach_normal: Vector3, world_up: Vector3) -> void:
	var n: Vector3 = attach_normal.normalized()
	if n.length() < 0.001:
		n = world_up

	var dot_up: float = clamp(n.dot(world_up), -1.0, 1.0)
	var angle_deg: float = rad_to_deg(acos(dot_up))

	_last_attach_normal = n
	_last_attach_angle_deg = angle_deg
	_update_stable_attach_normal(n, angle_deg)


func _update_stable_attach_normal(attach_normal: Vector3, attach_angle_deg: float) -> void:
	var n: Vector3 = attach_normal.normalized()
	if n.length() < 0.001:
		return
	if not _stable_attach_normal_valid:
		_stable_attach_normal = n
		_stable_attach_angle_deg = attach_angle_deg
		_stable_attach_normal_valid = true
		return

	var stable_n: Vector3 = _stable_attach_normal.normalized()
	if stable_n.length() < 0.001:
		_stable_attach_normal = n
		_stable_attach_angle_deg = attach_angle_deg
		_stable_attach_normal_valid = true
		return

	var step_angle_deg: float = rad_to_deg(acos(clamp(stable_n.dot(n), -1.0, 1.0)))
	var filter_angle: float = max(
		min(detach_stable_normal_filter_angle_deg, detach_ignore_last_moment_angle_deg),
		0.0
	)
	if step_angle_deg <= filter_angle:
		_stable_attach_normal = n
		_stable_attach_angle_deg = attach_angle_deg


func _reset_stable_attach_normal() -> void:
	_stable_attach_normal = _get_gravity_up()
	_stable_attach_angle_deg = 0.0
	_stable_attach_normal_valid = false


func _reset_air_torque_airborne_state(reset_segment: bool) -> void:
	# SUMMARY: Clear airborne torque integration state (visual-only).
	# NOTE: reset_segment true also re-enables torque for the next detach.
	_air_torque_airborne_time = 0.0
	_air_torque_angular_velocity = Vector3.ZERO
	_air_torque_rotation_accum = Vector3.ZERO
	_manual_airborne_torque_active = false
	_manual_airborne_torque_suppress_decay = false
	_manual_airborne_torque_fast_decay = false
	_air_trick_animation_gesture_latched = false
	_air_trick_animation_last_command = &""
	_manual_airborne_trick_input_active = false
	_manual_airborne_trick_input_command = &""
	_left_stick_trick_momentum_active = false
	_external_airborne_torque_active = false
	_set_manual_camera_lock(false)
	var up: Vector3 = visual_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var forward_on_up: Vector3 = _model_forward - up * _model_forward.dot(up)
	if forward_on_up.length() > 0.001:
		_air_torque_visual_forward = forward_on_up.normalized()
	if reset_segment:
		_air_torque_segment_allowed = true
		_spring_trajectory_torque_active = false
		_spring_trajectory_landing_forward_pitch_active = false


func _clear_air_landing_align() -> void:
	# SUMMARY: Clear predicted landing alignment state to avoid cross-state bleed.
	_air_landing_align_active = false
	_air_landing_align_normal = _get_gravity_up()
	_air_landing_align_distance = 0.0
	_air_landing_align_time_to_impact = 0.0
	_air_landing_align_ramp = 0.0
	_air_landing_align_speed_scale = 1.0
	_air_landing_align_pitch_direction = 0.0
	_air_landing_align_pitch_preference_resolved = false
	_air_landing_align_directional_pitch_complete = false
	_air_landing_align_miss_grace_timer = 0.0


func _advance_air_landing_align_miss_grace(delta: float) -> void:
	if _air_landing_align_active:
		_air_landing_align_miss_grace_timer = max(
			_air_landing_align_miss_grace_timer - max(delta, 0.0),
			0.0
		)
		if _air_landing_align_miss_grace_timer > 0.0:
			return
	_clear_air_landing_align()


func _is_air_action_tumble_cancel_active() -> bool:
	# SUMMARY: Return whether an airborne action should immediately cancel tumble.
	if _is_jumping:
		return true
	if _jump_dash_recent_timer > 0.0:
		return true
	if _spindash_charging:
		return true
	if _homing_active or _homing_post_attack_timer > 0.0:
		return true
	if _bounce_state != BounceState.NONE:
		return true
	if is_action_id_active(&"skydive"):
		return true
	if is_action_id_active(&"spin_kick") or is_action_id_active(&"uppercut_kick"):
		return true
	if rolling or is_action_id_active(&"roll"):
		return true
	if is_current_action_flight():
		return true
	if _lightspeed_dash_active:
		return true
	return false


func _cancel_air_tumble_for_action(world_up: Vector3) -> void:
	# SUMMARY: End airborne tumbling immediately for action-driven air states.
	# NOTES:
	# - Keeps the effect visual-only; movement/ability state is untouched.
	# - Prevents torque or landing-align state from bleeding into air actions.
	if not airborne_torque_cancel_on_air_actions:
		return
	if not airborne_torque_enabled:
		return
	if attached:
		return
	if not _is_air_action_tumble_cancel_active():
		return
	if _manual_airborne_torque_active:
		if is_action_id_active(&"spin_kick") or is_action_id_active(&"uppercut_kick") or is_action_id_active(&"skydive") or rolling or is_action_id_active(&"roll"):
			_gracefully_end_airborne_torque()
		elif is_current_action_flight():
			pass
		else:
			return

	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	_cancel_spring_trajectory_torque(true)
	_air_torque_airborne_time = 0.0
	_air_torque_angular_velocity = Vector3.ZERO
	_air_torque_rotation_accum = Vector3.ZERO
	_air_torque_segment_allowed = false
	_air_trick_animation_gesture_latched = false
	_air_trick_animation_last_command = &""
	_clear_air_torque_samples()
	_clear_air_landing_align()
	visual_up = up


func _is_surface_landable(normal: Vector3, world_up: Vector3) -> bool:
	# SUMMARY: Classify whether a surface normal is landable relative to gravity-up.
	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return false
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var dot_up: float = clamp(n.dot(up), -1.0, 1.0)
	var angle_deg: float = rad_to_deg(acos(dot_up))
	var max_angle: float = max(airborne_landing_align_max_angle_deg, 0.0)
	if max_angle <= 0.0:
		return false
	if angle_deg <= max_angle:
		return true
	return false


func _intersect_landing_heading(origin: Vector3, ray_end: Vector3) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.exclude = [self]
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)


## Predicted collision along the gravity-adjusted movement path within the input buffer duration.
func get_landing_prompt_prediction(duration: float) -> Dictionary:
	if attached or duration <= 0.0 or not is_inside_tree() or DEBUG_SKIP_AIR_RAYS:
		return {}
	var up: Vector3 = _get_gravity_up()
	if velocity.dot(up) >= 0.0:
		return {}
	var gravity_scale: float = 1.0
	if _bounce_state == BounceState.BOUNCE:
		gravity_scale = bounce_gravity_scale
	elif _bounce_state == BounceState.STOMP:
		gravity_scale = stomp_gravity_scale
	if _spring_align_timer > 0.0:
		gravity_scale *= spring_gravity_scale
	var acceleration: Vector3 = -up * get_effective_gravity_strength() * gravity_scale
	var origin: Vector3 = get_main_collision_world_center()
	var radius: float = get_main_collision_world_radius()
	var step_count: int = clampi(int(ceil(duration / 0.075)), 1, 12)
	var step_time: float = duration / float(step_count)
	var incoming: Vector3 = velocity
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for step: int in range(step_count):
		var next_velocity: Vector3 = incoming + acceleration * step_time
		var vertical_speed: float = next_velocity.dot(up)
		if vertical_speed < -max_fall_speed:
			next_velocity += up * (-max_fall_speed - vertical_speed)
		var motion: Vector3 = (incoming + next_velocity) * 0.5 * step_time
		var hit: Dictionary = _sweep_landing_prompt_segment(space, origin, motion, radius)
		if not hit.is_empty():
			var normal: Vector3 = hit.get("normal", Vector3.ZERO)
			if _is_surface_alignment_rejected(hit.get("collider"), normal, up, int(hit.get("shape", -1))):
				return {}
			var fraction: float = float(hit["fraction"])
			hit["incoming_velocity"] = incoming.lerp(next_velocity, fraction)
			hit["time_to_impact"] = (float(step) + fraction) * step_time
			return hit
		origin += motion
		incoming = next_velocity
	return {}


func _sweep_landing_prompt_segment(space: PhysicsDirectSpaceState3D, origin: Vector3, motion: Vector3, radius: float) -> Dictionary:
	if radius <= 0.001:
		var hit: Dictionary = _intersect_landing_heading(origin, origin + motion)
		if not hit.is_empty():
			hit["fraction"] = clampf(origin.distance_to(hit["position"]) / maxf(motion.length(), 0.001), 0.0, 1.0)
		return hit
	_landing_prompt_sphere.radius = radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _landing_prompt_sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = motion
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.margin = 0.001
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return {}
	query.transform.origin += motion * fractions[1] + motion.normalized() * 0.01
	query.motion = Vector3.ZERO
	var hit: Dictionary = space.get_rest_info(query)
	if not hit.is_empty():
		hit["collider"] = instance_from_id(int(hit["collider_id"]))
		hit["position"] = hit["point"]
		hit["fraction"] = float(fractions[0])
	return hit


func _update_air_landing_prediction(delta: float, world_up: Vector3) -> void:
	var lightspeed: LightspeedDashAbility = _get_action_by_id(&"lightspeed_dash") as LightspeedDashAbility
	if lightspeed:
		lightspeed.update_input_prompt_availability()
	var parkour: ParkourAbility = _get_action_by_id(&"parkour") as ParkourAbility
	if parkour:
		parkour.update_wall_prompt_prediction(delta)
		parkour.update_landing_roll_prompt_prediction()
	# SUMMARY: Predict an upcoming landable surface and cache its normal for visual alignment.
	# NOTES:
	# - Uses gravity-up for landable classification.
	# - Only affects visuals; movement/attachment logic remains unchanged.
	if not airborne_landing_align_enabled:
		_clear_air_landing_align()
		return
	if attached:
		_clear_air_landing_align()
		return
	if _manual_airborne_torque_active:
		_clear_air_landing_align()
		return
	if (_spring_align_timer > 0.0 and not _spring_trajectory_torque_active) or _spline_active or _rail_active or _rail_switch_active:
		_clear_air_landing_align()
		return
	# Debug guard: optionally skip expensive airborne raycasts
	if DEBUG_SKIP_AIR_RAYS:
		_clear_air_landing_align()
		return
	var align_delay: float = max(airborne_landing_align_delay, 0.0)
	if _airborne_time < align_delay:
		_clear_air_landing_align()
		return

	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var vertical_speed: float = velocity.dot(up)
	if vertical_speed >= 0.0:
		_clear_air_landing_align()
		return

	var speed: float = velocity.length()
	var predict_time: float = max(airborne_landing_align_predict_time, 0.0)
	var min_dist_base: float = max(airborne_landing_align_min_distance, 0.0)
	var max_dist_base: float = max(airborne_landing_align_max_distance, min_dist_base)

	var min_dist: float = min_dist_base
	var max_dist: float = max_dist_base
	var speed_ref: float = max(airborne_landing_align_speed_ref, 0.0)
	if speed_ref > 0.0:
		var speed_t: float = clamp(speed / speed_ref, 0.0, 1.0)
		var min_scale: float = max(airborne_landing_align_speed_min_scale, 0.0)
		var max_scale: float = max(airborne_landing_align_speed_max_scale, min_scale)
		var dist_scale: float = lerp(min_scale, max_scale, speed_t)
		min_dist = min_dist_base * dist_scale
		max_dist = max_dist_base * dist_scale
		if max_dist < min_dist:
			max_dist = min_dist
	var predict_dist: float = min_dist
	if predict_time > 0.0:
		predict_dist = clamp(speed * predict_time, min_dist, max_dist)
	else:
		predict_dist = min_dist

	var bias: float = max(airborne_landing_align_gravity_bias, 0.0)
	var predict_dir: Vector3 = velocity - up * bias * max(speed, 1.0)
	if predict_dir.length() < 0.001:
		predict_dir = -up
	else:
		predict_dir = predict_dir.normalized()

	var origin: Vector3 = global_position
	var down_extra: float = max(airborne_landing_align_downcast_extra, 0.0)
	var ray_end: Vector3 = origin + predict_dir * predict_dist - up * down_extra

	var hit: Dictionary = _intersect_landing_heading(origin, ray_end)
	if hit.is_empty():
		_advance_air_landing_align_miss_grace(delta)
		return
	var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if _is_surface_alignment_rejected(
		hit.get("collider"),
		hit_normal,
		up,
		int(hit.get("shape", -1))
	):
		_clear_air_landing_align()
		return
	if not _is_surface_landable(hit_normal, up):
		_advance_air_landing_align_miss_grace(delta)
		return

	var hit_position: Vector3 = hit.get("position", origin)
	var distance_to_hit: float = origin.distance_to(hit_position)
	var time_to_hit: float = 0.0
	if speed > 0.001:
		time_to_hit = distance_to_hit / speed

	var ramp: float = 1.0
	if predict_time > 0.0:
		ramp = 1.0 - clamp(time_to_hit / predict_time, 0.0, 1.0)
	var min_ramp: float = clamp(airborne_landing_align_min_ramp, 0.0, 1.0)
	ramp = max(min_ramp, ramp)

	var dist_denom: float = max(predict_dist, 0.001)
	var dist_frac: float = clamp(distance_to_hit / dist_denom, 0.0, 1.0)
	var closeness: float = 1.0 - dist_frac
	var close_mult: float = max(airborne_landing_align_close_speed_mult, 0.0)
	var close_power: float = max(airborne_landing_align_close_speed_power, 0.001)
	var close_t: float = pow(closeness, close_power)
	var speed_scale: float = 1.0 + (close_mult - 1.0) * close_t

	var landing_alignment_started: bool = not _air_landing_align_active
	var landing_normal: Vector3 = hit_normal.normalized()
	if not landing_alignment_started:
		var previous_normal: Vector3 = _air_landing_align_normal.normalized()
		var normal_smoothing_speed: float = max(airborne_landing_align_normal_smoothing_speed, 0.0)
		if previous_normal.length() > 0.001 and normal_smoothing_speed > 0.0:
			var normal_blend: float = 1.0 - exp(-normal_smoothing_speed * max(delta, 0.0))
			landing_normal = previous_normal.slerp(landing_normal, normal_blend).normalized()
	if landing_alignment_started:
		var frame_up: Vector3 = visual_up.normalized()
		if frame_up.length() < 0.001:
			frame_up = up
		var entering_forward: Vector3 = _model_forward
		if model_root != null and is_instance_valid(model_root):
			entering_forward = -model_root.global_transform.basis.z
		entering_forward -= frame_up * entering_forward.dot(frame_up)
		if entering_forward.length() > 0.001:
			_air_torque_visual_forward = entering_forward.normalized()
	_air_landing_align_active = true
	_air_landing_align_normal = landing_normal
	_air_landing_align_distance = distance_to_hit
	_air_landing_align_time_to_impact = time_to_hit
	_air_landing_align_ramp = ramp
	_air_landing_align_speed_scale = speed_scale
	_air_landing_align_miss_grace_timer = max(airborne_landing_align_miss_grace_time, 0.0)
	_cancel_spring_trajectory_torque(false)


func _clear_air_torque_samples() -> void:
	# SUMMARY: Clear the ground-rotation sample window for airborne torque.
	_air_torque_samples.clear()
	_air_torque_sample_durations.clear()
	_air_torque_sample_total_time = 0.0
	_air_torque_avg_angular_velocity = Vector3.ZERO
	_airborne_torque_yaw_turn_speed_last = 0.0
	_airborne_torque_yaw_turn_speed_memory_timer = 0.0


func _compute_air_torque_average() -> Vector3:
	# SUMMARY: Compute the time-weighted average angular velocity.
	var total: float = _air_torque_sample_total_time
	if total <= 0.0001:
		return Vector3.ZERO

	var accum: Vector3 = Vector3.ZERO
	for i in range(_air_torque_samples.size()):
		var w: float = float(_air_torque_sample_durations[i])
		accum += _air_torque_samples[i] * w

	return accum / total


func _compute_air_torque_yaw_forward(detach_normal: Vector3, world_up: Vector3) -> Vector3:
	# SUMMARY: Convert the last surface-facing direction into a gravity-up yaw reference.
	# NOTES:
	# - Uses world_up as the yaw axis; if projection degenerates, keep the last valid yaw.
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var forward_world: Vector3 = _model_forward
	if forward_world.length() < 0.001:
		forward_world = -global_transform.basis.z

	var yaw_forward: Vector3 = forward_world - up * forward_world.dot(up)
	if yaw_forward.length() < 0.001:
		yaw_forward = _air_torque_yaw_forward

	if yaw_forward.length() < 0.001:
		var hint: Vector3 = _detach_forward_hint - up * _detach_forward_hint.dot(up)
		if hint.length() > 0.001:
			yaw_forward = hint

	if yaw_forward.length() < 0.001:
		var fallback: Vector3 = Vector3.FORWARD
		if abs(fallback.dot(up)) > 0.99:
			fallback = Vector3.RIGHT
		yaw_forward = fallback - up * fallback.dot(up)

	if yaw_forward.length() < 0.001:
		return Vector3.ZERO

	return yaw_forward.normalized()


func _push_air_torque_sample(omega: Vector3, delta: float) -> void:
	# SUMMARY: Add a ground-rotation sample and keep a sliding time window.
	var dt: float = max(delta, 0.0)
	if dt <= 0.0:
		return

	var window: float = max(airborne_torque_sample_window, 0.0)
	if window <= 0.0:
		_air_torque_samples.clear()
		_air_torque_sample_durations.clear()
		_air_torque_sample_total_time = dt
		_air_torque_avg_angular_velocity = omega
		_air_torque_samples.append(omega)
		_air_torque_sample_durations.append(dt)
		return

	_air_torque_samples.append(omega)
	_air_torque_sample_durations.append(dt)
	_air_torque_sample_total_time += dt

	while _air_torque_sample_total_time > window and _air_torque_sample_durations.size() > 0:
		var first_dt: float = float(_air_torque_sample_durations[0])
		var excess: float = _air_torque_sample_total_time - window
		if excess < first_dt:
			_air_torque_sample_durations[0] = first_dt - excess
			_air_torque_sample_total_time = window
			break

		_air_torque_sample_total_time -= first_dt
		_air_torque_sample_durations.remove_at(0)
		_air_torque_samples.remove_at(0)

	_air_torque_avg_angular_velocity = _compute_air_torque_average()
	_dbg_air_torque_avg_omega = _air_torque_avg_angular_velocity


func _start_air_torque_from_detach(allow_air_torque: bool) -> void:
	# SUMMARY: Seed the airborne torque from the last tracked surface rotation.
	_external_airborne_torque_active = false
	_air_trick_animation_gesture_latched = false
	_air_trick_animation_last_command = &""
	_air_torque_airborne_time = 0.0
	_air_torque_segment_allowed = allow_air_torque and airborne_torque_enabled
	if not _air_torque_segment_allowed:
		_air_torque_angular_velocity = Vector3.ZERO
		_clear_air_torque_samples()
		return

	var avg_omega: Vector3 = _air_torque_avg_angular_velocity
	if _air_torque_sample_total_time <= 0.001:
		avg_omega = _air_torque_ground_angular_velocity

	var min_avg_deg: float = max(airborne_torque_min_avg_speed_deg, 0.0)
	if min_avg_deg > 0.0:
		var avg_speed_deg: float = rad_to_deg(avg_omega.length())
		if avg_speed_deg < min_avg_deg:
			_air_torque_angular_velocity = Vector3.ZERO
			_air_torque_segment_allowed = false
			_clear_air_torque_samples()
			return

	_air_torque_angular_velocity = avg_omega
	_dbg_air_torque_seed_omega = avg_omega
	if _air_torque_angular_velocity.length() < 0.0001:
		_air_torque_angular_velocity = Vector3.ZERO
	_clear_air_torque_samples()


func _get_turn_rate_yaw_angular_velocity(world_up: Vector3) -> Vector3:
	# SUMMARY: Convert the signed turning-rate sample into yaw angular velocity.
	# NOTES:
	# - Uses gravity-up as the yaw axis so captured yaw stays stable.
	# - Intended for the attached sampling path before detach.
	if not airborne_torque_enabled:
		return Vector3.ZERO
	if not airborne_torque_yaw_from_turn_rate_enabled:
		return Vector3.ZERO
	if _airborne_torque_yaw_turn_speed_memory_timer <= 0.0:
		return Vector3.ZERO

	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var yaw_speed_deg: float = _airborne_torque_yaw_turn_speed_last * airborne_torque_yaw_turn_rate_scale
	if abs(yaw_speed_deg) <= 0.0001:
		return Vector3.ZERO

	var max_speed_deg: float = max(airborne_torque_yaw_turn_rate_max_speed_deg, 0.0)
	if max_speed_deg > 0.0:
		yaw_speed_deg = clamp(yaw_speed_deg, -max_speed_deg, max_speed_deg)

	var yaw_speed_rad: float = deg_to_rad(yaw_speed_deg)
	return up * yaw_speed_rad


func _update_air_torque_ground_tracking(delta: float) -> void:
	# SUMMARY: Track surface-normal angular velocity for airborne torque.
	# NOTES:
	# - Uses world-space normals (not local-up) to match gravity orientation.
	# - Skips forced-alignment states (springs/splines/rails).
	if delta <= 0.0:
		return
	if not attached:
		return

	var fallback_up: Vector3 = _get_gravity_up()

	var curr: Vector3 = surface_normal.normalized()
	if curr.length() < 0.001:
		curr = fallback_up

	if not airborne_torque_enabled:
		_air_torque_ground_angular_velocity = Vector3.ZERO
		_air_torque_prev_surface_normal = curr
		_clear_air_torque_samples()
		return

	if _spring_align_timer > 0.0 or _spline_active or _rail_active:
		_air_torque_ground_angular_velocity = Vector3.ZERO
		_air_torque_prev_surface_normal = curr
		_clear_air_torque_samples()
		return

	# Keep a stable gravity-up yaw reference for airborne visual facing.
	var yaw_forward: Vector3 = _model_forward - fallback_up * _model_forward.dot(fallback_up)
	if yaw_forward.length() > 0.001:
		_air_torque_yaw_forward = yaw_forward.normalized()

	if not _air_torque_prev_attached:
		_air_torque_prev_surface_normal = curr
		_air_torque_ground_angular_velocity = Vector3.ZERO
		_clear_air_torque_samples()
		return

	var prev: Vector3 = _air_torque_prev_surface_normal
	if prev.length() < 0.001:
		_air_torque_prev_surface_normal = curr
		_air_torque_ground_angular_velocity = Vector3.ZERO
		_clear_air_torque_samples()
		return

	var yaw_turn_omega: Vector3 = _get_turn_rate_yaw_angular_velocity(fallback_up)
	var surface_omega: Vector3 = Vector3.ZERO

	var dot_pc: float = clamp(prev.dot(curr), -1.0, 1.0)
	var angle_rad: float = acos(dot_pc)
	var angle_deg: float = rad_to_deg(angle_rad)
	_dbg_air_torque_normal_angle_deg = angle_deg
	var min_angle_deg: float = max(airborne_torque_capture_min_angle_deg, 0.0)
	if angle_deg < min_angle_deg:
		_air_torque_ground_angular_velocity = yaw_turn_omega
		_dbg_air_torque_surface_omega = surface_omega
		_dbg_air_torque_yaw_omega = yaw_turn_omega
		_dbg_air_torque_combined_omega = _air_torque_ground_angular_velocity
		_dbg_air_torque_axis = Vector3.ZERO
		_dbg_air_torque_move_dir = Vector3.ZERO
		_air_torque_prev_surface_normal = curr
		_push_air_torque_sample(_air_torque_ground_angular_velocity, delta)
		return

	var axis: Vector3 = prev.cross(curr)
	var axis_len: float = axis.length()
	if axis_len < 0.0001:
		_air_torque_ground_angular_velocity = yaw_turn_omega
		_dbg_air_torque_surface_omega = surface_omega
		_dbg_air_torque_yaw_omega = yaw_turn_omega
		_dbg_air_torque_combined_omega = _air_torque_ground_angular_velocity
		_dbg_air_torque_axis = Vector3.ZERO
		_dbg_air_torque_move_dir = Vector3.ZERO
		_air_torque_prev_surface_normal = curr
		_push_air_torque_sample(_air_torque_ground_angular_velocity, delta)
		return

	axis /= axis_len

	var v_tangent: Vector3 = velocity - curr * velocity.dot(curr)
	if v_tangent.length() > 0.001:
		var move_dir: Vector3 = v_tangent.normalized()
		_dbg_air_torque_move_dir = move_dir
		var pitch_axis: Vector3 = curr.cross(move_dir)
		if pitch_axis.length() > 0.001:
			pitch_axis = pitch_axis.normalized()
			var axis_dot_pitch: float = axis.dot(pitch_axis)
			var pitch_sign: float = sign(axis_dot_pitch)
			if pitch_sign == 0.0:
				pitch_sign = 1.0
			axis = pitch_axis * pitch_sign

	_dbg_air_torque_axis = axis
	var speed_rad: float = angle_rad / delta
	var max_speed_deg: float = max(airborne_torque_max_speed_deg, 0.0)
	if max_speed_deg > 0.0:
		var max_speed_rad: float = deg_to_rad(max_speed_deg)
		if speed_rad > max_speed_rad:
			speed_rad = max_speed_rad

	surface_omega = axis * speed_rad
	_air_torque_ground_angular_velocity = surface_omega + yaw_turn_omega
	_dbg_air_torque_surface_omega = surface_omega
	_dbg_air_torque_yaw_omega = yaw_turn_omega
	_dbg_air_torque_combined_omega = _air_torque_ground_angular_velocity
	_air_torque_prev_surface_normal = curr
	_push_air_torque_sample(_air_torque_ground_angular_velocity, delta)


func _update_manual_airborne_torque(delta: float) -> void:
	_manual_airborne_trick_input_active = false
	_manual_airborne_trick_input_command = &""
	if delta <= 0.0:
		_manual_airborne_mouse_delta = Vector2.ZERO
		return

	var wants_input: bool = _should_start_manual_airborne_torque()
	
	if wants_input:
		if _spring_trajectory_torque_active or _spring_trajectory_landing_forward_pitch_active:
			_cancel_spring_trajectory_torque(true)
		if not _manual_airborne_torque_active:
			_manual_airborne_torque_active = true
			if not _left_stick_trick_momentum_active:
				_begin_left_stick_trick_momentum()
		_manual_airborne_torque_fast_decay = false
		_set_manual_camera_lock(true)
		
		if _bounce_state == BounceState.NONE:
			_apply_manual_airborne_torque(delta)
		else:
			_air_torque_angular_velocity = Vector3.ZERO
			
		_manual_airborne_torque_suppress_decay = true
	else:
		_manual_airborne_torque_suppress_decay = false
		_left_stick_trick_momentum_active = false
		_set_manual_camera_lock(false)
		
		if _manual_airborne_torque_active:
			# Manual torque mode is active but input is no longer desired (key released, or hard stop like landing).
			var speed: float = _air_torque_angular_velocity.length()
			
			# Hard stop conditions: land, pause, UI block, or feature disabled.
			var hard_stop: bool = attached or _local_pause_enabled or _ui_input_blocked or not manual_airborne_torque_enabled
			
			# Soft stop condition: rotation speed below threshold.
			var soft_stop: bool = speed < manual_airborne_torque_exit_threshold
			
			if hard_stop or soft_stop:
				_manual_airborne_torque_active = false
			
	_manual_airborne_mouse_delta = Vector2.ZERO


func _uses_left_stick_trick_controls() -> bool:
	return (
		SettingsManager.is_controller_input_active()
		and SettingsManager.trick_control_stick == SettingsManager.TRICK_CONTROL_STICK_LEFT
	)


func _begin_left_stick_trick_momentum() -> void:
	_left_stick_trick_momentum_active = _uses_left_stick_trick_controls()
	_left_stick_trick_entry_horizontal_speed = 0.0
	_left_stick_trick_entry_horizontal_direction = Vector3.ZERO
	if not _left_stick_trick_momentum_active:
		return
	var up: Vector3 = _get_gravity_up()
	var horizontal_velocity: Vector3 = velocity - up * velocity.dot(up)
	_left_stick_trick_entry_horizontal_speed = horizontal_velocity.length()
	if _left_stick_trick_entry_horizontal_speed > 0.001:
		_left_stick_trick_entry_horizontal_direction = horizontal_velocity / _left_stick_trick_entry_horizontal_speed


func _apply_left_stick_trick_momentum(lateral: Vector3, maximum_speed: float, water_acceleration_multiplier: float, delta: float) -> Vector3:
	if not _left_stick_trick_momentum_active:
		return lateral
	if not _uses_left_stick_trick_controls():
		return lateral
	var use_last_input: bool = (
		SettingsManager.left_stick_trick_movement
		== SettingsManager.LEFT_STICK_TRICK_MOVEMENT_LAST_INPUT
	)
	if use_last_input:
		return lateral
	var target_speed: float = min(_left_stick_trick_entry_horizontal_speed, max(maximum_speed, 0.0))
	var current_speed: float = lateral.length()
	var direction: Vector3 = _left_stick_trick_entry_horizontal_direction
	if current_speed > 0.001:
		direction = lateral / current_speed
	if direction.length_squared() < 0.001 or target_speed <= 0.001:
		return lateral
	if current_speed >= target_speed:
		return lateral
	var acceleration_curve: Curve = _get_active_acceleration_curve(air_accel_curve)
	var sampled_recovery_acceleration: float = _sample_curve_by_speed(acceleration_curve, current_speed, 20.0)
	var recovery_acceleration: float = sampled_recovery_acceleration
	if is_air_acceleration_overridden():
		recovery_acceleration = get_air_acceleration_override(current_speed, recovery_acceleration)
	recovery_acceleration = maxf(recovery_acceleration, 0.0)
	if sampled_recovery_acceleration > 0.0:
		recovery_acceleration *= get_combo_acceleration_multiplier()
	recovery_acceleration *= max(water_acceleration_multiplier, 0.0)
	recovery_acceleration *= _directional_influence_lock_accel_multiplier
	recovery_acceleration *= max(manual_airborne_torque_left_stick_momentum_recovery_multiplier, 0.0)
	var recovery_step: float = recovery_acceleration * max(delta, 0.0)
	var recovered_speed: float = move_toward(current_speed, target_speed, recovery_step)
	return direction.normalized() * recovered_speed


func _should_start_manual_airborne_torque() -> bool:
	if not manual_airborne_torque_enabled:
		return false
	if is_parkour_active():
		return false
	if attached:
		return false
	if rolling or _current_action_id == &"roll":
		return false
	if _local_pause_enabled or _ui_input_blocked:
		return false
	if _debug_mode:
		return false
	if (_spring_align_timer > 0.0 and not _spring_trajectory_torque_active) or _spline_active or _rail_active:
		return false
	if is_current_action_flight():
		return false
	if _automation_lock_actions and _automation_locks_active():
		return false
	if _automation_lock_drift and _automation_locks_active():
		return false
	return SettingsManager.is_gameplay_action_pressed("ability_slot_05")


func _gracefully_end_airborne_torque() -> void:
	_cancel_spring_trajectory_torque(true)
	if _manual_airborne_torque_active or _air_torque_segment_allowed or _air_torque_angular_velocity.length() > 0.001:
		_air_torque_segment_allowed = false
		_air_torque_angular_velocity = Vector3.ZERO
		_air_torque_rotation_accum = Vector3.ZERO
		_manual_airborne_torque_active = false
		_manual_airborne_torque_suppress_decay = false
		_manual_airborne_torque_fast_decay = false
		_left_stick_trick_momentum_active = false
		_external_airborne_torque_active = false
		_air_trick_animation_gesture_latched = false
		_air_trick_animation_last_command = &""
		_manual_airborne_trick_input_active = false
		_manual_airborne_trick_input_command = &""
		_set_manual_camera_lock(false)
		_clear_air_torque_samples()
		_clear_air_landing_align()


func cancel_airborne_torque_for_action(world_up: Vector3 = Vector3.ZERO) -> void:
	_cancel_spring_trajectory_torque(true)
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	_air_torque_airborne_time = 0.0
	_air_torque_angular_velocity = Vector3.ZERO
	_air_torque_rotation_accum = Vector3.ZERO
	_air_torque_segment_allowed = false
	_manual_airborne_torque_active = false
	_manual_airborne_torque_suppress_decay = false
	_manual_airborne_torque_fast_decay = false
	_left_stick_trick_momentum_active = false
	_external_airborne_torque_active = false
	_air_trick_animation_gesture_latched = false
	_air_trick_animation_last_command = &""
	_manual_airborne_trick_input_active = false
	_manual_airborne_trick_input_command = &""
	_set_manual_camera_lock(false)
	_clear_air_torque_samples()
	_clear_air_landing_align()
	visual_up = up


func _apply_manual_airborne_torque(delta: float) -> void:
	var mouse_delta: Vector2 = _manual_airborne_mouse_delta
	var stick_input: Vector2 = Vector2.ZERO
	if SettingsManager.is_controller_input_active():
		if _uses_left_stick_trick_controls():
			stick_input = SettingsManager.get_radial_action_vector(
				&"move_left",
				&"move_right",
				&"move_back",
				&"move_forward",
				SettingsManager.get_left_stick_deadzone(),
				SettingsManager.get_left_stick_max(),
				&"gamepad"
			)
		else:
			stick_input = SettingsManager.get_radial_action_vector(
				&"camera_left",
				&"camera_right",
				&"camera_down",
				&"camera_up",
				SettingsManager.get_right_stick_deadzone(),
				SettingsManager.get_right_stick_max(),
				&"gamepad"
			)
			if SettingsManager.right_stick_invert_y:
				stick_input.y = -stick_input.y
	stick_input.y = -stick_input.y
	if mouse_delta.length() < 0.0001 and stick_input.length() < 0.0001:
		return
	var mouse_sens: float = max(SettingsManager.mouse_look_sensitivity, 0.01)
	var yaw_scale: float = manual_airborne_torque_mouse_yaw_scale * mouse_sens
	var pitch_scale: float = manual_airborne_torque_mouse_pitch_scale * mouse_sens
	var roll_scale: float = manual_airborne_torque_mouse_roll_scale * mouse_sens
	var mouse_y_sign: float = (-1.0) if SettingsManager.mouse_invert_y else 1.0
	var mouse_diagonal_strength: float = min(abs(mouse_delta.x), abs(mouse_delta.y))
	var yaw_impulse: float = mouse_delta.x * yaw_scale
	var pitch_impulse: float = mouse_delta.y * pitch_scale * mouse_y_sign
	var roll_impulse: float = mouse_diagonal_strength * sign(mouse_delta.x) * roll_scale

	var stick_acceleration: float = max(manual_airborne_torque_stick_angular_acceleration, 0.0)
	stick_acceleration *= max(SettingsManager.get_trick_rotation_acceleration(), 0.01)
	var stick_step: float = stick_acceleration * max(delta, 0.0)
	var stick_scale_reference: float = 0.008
	var stick_yaw_scale: float = manual_airborne_torque_mouse_yaw_scale / stick_scale_reference
	var stick_pitch_scale: float = manual_airborne_torque_mouse_pitch_scale / stick_scale_reference
	var stick_roll_scale: float = manual_airborne_torque_mouse_roll_scale / stick_scale_reference
	var stick_diagonal_strength: float = min(abs(stick_input.x), abs(stick_input.y))
	yaw_impulse += stick_input.x * stick_yaw_scale * stick_step
	pitch_impulse += stick_input.y * stick_pitch_scale * stick_step
	roll_impulse += stick_diagonal_strength * sign(stick_input.x) * stick_roll_scale * stick_step
	
	var yaw_axis: Vector3
	var forward_ref: Vector3
	
	if manual_airborne_torque_player_relative:
		# Relative to player's current visual orientation.
		yaw_axis = visual_up.normalized()
		forward_ref = _air_torque_visual_forward
		if forward_ref.length() < 0.001:
			forward_ref = _model_forward
	else:
		# Relative to gravity-up and horizontal forward.
		var world_up: Vector3 = _get_gravity_up()
		yaw_axis = world_up
		forward_ref = _model_forward
	
	var pitch_axis: Vector3 = _compute_manual_pitch_axis(yaw_axis, forward_ref)
	# Positive roll around -forward (Z) rotates X to -Y (Bank Right).
	var roll_axis: Vector3 = -forward_ref.normalized()
	
	var manual_impulse: Vector3 = yaw_axis * yaw_impulse + pitch_axis * pitch_impulse + roll_axis * roll_impulse
	if manual_impulse.length() > 0.0001:
		_manual_airborne_trick_input_active = true
		_manual_airborne_trick_input_command = _get_trick_cmd_from_angular_velocity(
			manual_impulse,
			0.0
		)
	
	_air_torque_segment_allowed = true
	_air_torque_angular_velocity += manual_impulse
	
	var max_speed: float = max(manual_airborne_torque_max_speed, 0.0)
	if max_speed > 0.0 and _air_torque_angular_velocity.length() > max_speed:
		_air_torque_angular_velocity = _air_torque_angular_velocity.normalized() * max_speed


func _compute_manual_pitch_axis(up_axis: Vector3, forward_ref: Vector3) -> Vector3:
	var flat_forward: Vector3 = forward_ref - up_axis * forward_ref.dot(up_axis)
	if flat_forward.length() < 0.001:
		var fallback: Vector3 = -global_transform.basis.z
		flat_forward = fallback - up_axis * fallback.dot(up_axis)
	if flat_forward.length() < 0.001:
		flat_forward = Vector3.FORWARD - up_axis * Vector3.FORWARD.dot(up_axis)
	
	if flat_forward.length() < 0.0001:
		return global_transform.basis.x
		
	# Up x Forward = Right axis for pitching up.
	var axis: Vector3 = up_axis.cross(flat_forward.normalized())
	return axis.normalized()


func _get_input_up() -> Vector3:
	var world_up: Vector3 = _get_gravity_up()

	# 1) If attached, use current surface normal.
	if attached and surface_normal.length() > 0.001:
		return surface_normal.normalized()

	# 2) Recently detached from a steep / non-floor surface:
	#    reuse last detach normal for a short window (attachment_immunity).
	if _attachment_immunity > 0.0 and _last_detach_normal.length() > 0.001:
		var n: Vector3 = _last_detach_normal.normalized()
		var dot_up : float = clamp(n.dot(world_up), -1.0, 1.0)
		var angle_deg: float = rad_to_deg(acos(dot_up))
		# Treat anything steeper than the "floor-like" threshold as steep.
		if angle_deg >= floor_like_max_angle_deg:
			return n

	# 3) Default: gravity-up.
	return world_up


func _get_camera_forward_world_up(world_up: Vector3) -> Vector3:
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	# a) Preferred: CameraRig yaw forward projected onto the requested up plane
	if camera_rig != null and camera_rig.has_method("get_yaw_forward"):
		var yaw_fwd: Vector3 = camera_rig.get_yaw_forward()
		yaw_fwd -= up * yaw_fwd.dot(up)
		if yaw_fwd.length() > 0.001:
			return yaw_fwd.normalized()

	# b) Fallback: actual camera forward projected onto the requested up plane
	if camera != null:
		var raw_forward: Vector3 = -camera.global_transform.basis.z
		raw_forward -= up * raw_forward.dot(up)
		if raw_forward.length() > 0.001:
			return raw_forward.normalized()

	var fallback: Vector3 = _model_forward
	fallback -= up * fallback.dot(up)
	if fallback.length() < 0.001:
		fallback = -global_transform.basis.z
		fallback -= up * fallback.dot(up)
	if fallback.length() < 0.001:
		fallback = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	if fallback.length() < 0.001:
		fallback = -Vector3.FORWARD
	return fallback.normalized()


# ===========================================================
# ACTION CODE
# ===========================================================

func _init_abilities() -> void:
	_init_actions()

func _init_actions() -> void:
	_ensure_modules()
	if _ability_input_router != null:
		_ability_input_router.reload_profile()
	_actions.clear()
	_active_action = null
	_current_action_id = &""
	_fall_action = null
	_jump_action = null
	_jump_dash_action = null
	_homing_action = null
	_insta_shield_action = null
	_lightspeed_dash_action = null
	_bounce_action = null
	_stomp_action = null
	_roll_action = null
	_spindash_action = null
	_drift_action = null
	_spring_action = null
	_hurt_action = null
	_rail_grind_action = null
	_grounded_action = null
	_drowned_action = null
	_homing_targeting_ability_count = 0
	can_grind_rails = false

	var root: Node = self
	if has_node("Abilities"):
		root = get_node("Abilities")

	_collect_actions_recursive(root)
	_apply_character_loadout_to_actions()
	_cache_special_action_references()
	_apply_action_node_settings()
	_sync_drift_state_from_action()
	_sync_spring_state_from_action()
	_sync_hurt_state_from_action()
	_sync_spindash_state_from_action()
	_sync_roll_state_from_action()
	_connect_trick_signals()

func _collect_actions_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is CharacterActionType:
			var action: CharacterActionType = child
			action.init_action(self)
			_actions.append(action)
			if _action_uses_homing_targeting(action):
				_homing_targeting_ability_count += 1
		_collect_actions_recursive(child)


func _apply_character_loadout_to_actions() -> void:
	if _ability_input_router == null:
		return
	for action in _actions:
		if action == null or not (action is CharacterActionType):
			continue
		var binding: Dictionary = _ability_input_router.get_binding(action.action_id)
		if not binding.is_empty():
			action.input_action = StringName(binding.get("slot", &""))
			var gesture: StringName = StringName(binding.get("gesture", &"press"))
			if gesture == CharacterProfileManager.GESTURE_TAP:
				action.trigger_mode = CharacterActionType.ActionTrigger.TAP
			elif gesture == CharacterProfileManager.GESTURE_HOLD:
				action.trigger_mode = CharacterActionType.ActionTrigger.HOLD
			elif gesture == CharacterProfileManager.GESTURE_RELEASE:
				action.trigger_mode = CharacterActionType.ActionTrigger.JUST_RELEASED
			else:
				action.trigger_mode = CharacterActionType.ActionTrigger.JUST_PRESSED


func get_ability_input_slot(ability_id: StringName, fallback: StringName = &"") -> StringName:
	_ensure_modules()
	if _ability_input_router == null:
		return fallback
	return _ability_input_router.get_input_slot(ability_id, fallback)


func uses_character_ability_profile() -> bool:
	return character_settings_profile != null


func uses_authoritative_character_profile_routes() -> bool:
	return character_settings_profile != null and character_settings_profile.routes_authoritative


func is_ability_binding_pressed(ability_id: StringName, fallback: StringName = &"") -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.is_binding_pressed(ability_id, fallback)


func is_ability_binding_just_pressed(ability_id: StringName, fallback: StringName = &"") -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.is_binding_just_pressed(ability_id, fallback)


func is_ability_binding_simultaneously_just_pressed(
	ability_id: StringName,
	fallback: StringName = &"",
	press_window: float = 0.08
) -> bool:
	_ensure_modules()
	return (
		_ability_input_router != null
		and _ability_input_router.is_binding_simultaneously_just_pressed(ability_id, fallback, press_window)
	)


func is_ability_binding_just_released(ability_id: StringName, fallback: StringName = &"") -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.is_binding_just_released(ability_id, fallback)


func is_ability_binding_triggered(ability_id: StringName, fallback_slot: StringName = &"", fallback_gesture: StringName = &"press", fallback_hold_time: float = 0.0) -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.is_binding_triggered(ability_id, fallback_slot, fallback_gesture, fallback_hold_time)


func ability_binding_uses_slot(ability_id: StringName, slot: StringName, fallback_slot: StringName = &"") -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.binding_uses_slot(ability_id, slot, fallback_slot)


func has_character_profile_route_channel(source_action: StringName, event: StringName, route_id: StringName = &"", input_action: StringName = &"") -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.has_route_channel(source_action, event, route_id, input_action)


func has_character_profile_route_id(source_action: StringName, route_id: StringName) -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.has_route_id(source_action, route_id)


func has_character_profile_input_route(source_action: StringName, input_action: StringName) -> bool:
	_ensure_modules()
	return _ability_input_router != null and _ability_input_router.has_input_route(source_action, input_action)


func execute_character_profile_input_route(source_action: StringName, event: StringName, input_action: StringName, context: Dictionary = {}) -> bool:
	_ensure_modules()
	if _ability_input_router == null:
		return false
	for route: Dictionary in _ability_input_router.get_event_routes(source_action, event):
		if _ability_input_router.resolve_route_input_action(route) != input_action:
			continue
		if _execute_character_profile_route(route, context):
			return true
	return false


func execute_character_profile_route_event(source_action: StringName, event: StringName, route_id: StringName = &"", context: Dictionary = {}) -> bool:
	_ensure_modules()
	if _ability_input_router == null:
		return false
	for route: Dictionary in _ability_input_router.get_event_routes(source_action, event, route_id):
		if _execute_character_profile_route(route, context):
			return true
	return false


func is_character_profile_action_allowed(action_id: StringName, source_action: StringName) -> bool:
	_ensure_modules()
	if _ability_input_router == null:
		return true
	var policy_routes: Array[Dictionary] = _ability_input_router.get_event_routes(action_id, CharacterProfileManager.ROUTE_EVENT_POLICY)
	if policy_routes.is_empty():
		return true
	var has_allow_list: bool = false
	var allow_match: bool = false
	for route: Dictionary in policy_routes:
		var blocked: Array = route.get("blocked_source_actions", [])
		if blocked.has(source_action):
			return false
		var allowed: Array = route.get("allowed_source_actions", [])
		if allowed.is_empty():
			allow_match = true
			continue
		has_allow_list = true
		if allowed.has(source_action):
			allow_match = true
	return allow_match if has_allow_list else true


func _process_preemptive_character_profile_input_routes() -> bool:
	if not _network_is_local_authority():
		return false
	if _local_pause_enabled or _ui_input_blocked or _post_ui_unblock_action_suppress_timer > 0.0:
		return false
	if get_tree() != null and get_tree().paused:
		return false
	if _hurt_active:
		return false
	return _process_character_profile_input_routes(true)


func _process_character_profile_input_routes(preemptive_only: bool = false) -> bool:
	if _ability_input_router == null:
		return false
	var source_action: StringName = _get_character_profile_route_source_action()
	for route: Dictionary in _ability_input_router.get_triggered_input_routes(source_action, preemptive_only):
		var context: Dictionary = {
			"reason": StringName(route.get("reason", route.get("route_id", &"profile_route"))),
			"source_action": source_action,
		}
		if not _execute_character_profile_route(route, context):
			continue
		if bool(route.get("suppress_input_until_release", false)):
			var input_ability: StringName = StringName(route.get("input_ability", &""))
			var input_action: StringName = _ability_input_router.resolve_route_input_action(route)
			_ability_input_router.suppress_binding_until_release(input_ability, input_action)
		if bool(route.get("consume_input", true)):
			return true
	return false


func _get_character_profile_route_source_action() -> StringName:
	if _current_action_id != &"":
		return _current_action_id
	return &"grounded" if attached else &"fall"


func is_character_profile_route_allowed(route: Dictionary, context: Dictionary = {}) -> bool:
	if not bool(route.get("enabled", true)):
		return false
	if bool(route.get("block_during_race_countdown", true)) and race_in_countdown:
		return false
	var required_state: StringName = StringName(route.get("required_state", CharacterProfileManager.ROUTE_STATE_ANY))
	if required_state == CharacterProfileManager.ROUTE_STATE_GROUNDED and not attached:
		return false
	if required_state == CharacterProfileManager.ROUTE_STATE_AIRBORNE and attached:
		return false
	var source_action: StringName = StringName(context.get("source_action", route.get("source_action", &"")))
	if _active_action != null and is_instance_valid(_active_action) and StringName(_active_action.action_id) == source_action:
		if not bool(_active_action.allows_profile_route(route, context)):
			return false
	var blocked: Array = route.get("blocked_source_actions", [])
	if blocked.has(source_action):
		return false
	var allowed: Array = route.get("allowed_source_actions", [])
	if not allowed.is_empty() and not allowed.has(source_action):
		return false
	return true


func _execute_character_profile_route(route: Dictionary, context: Dictionary = {}) -> bool:
	if not is_character_profile_route_allowed(route, context):
		return false
	var source_action: StringName = StringName(context.get("source_action", route.get("source_action", &"")))
	var route_context: Dictionary = context.duplicate(true)
	route_context["source_action"] = source_action
	route_context["route"] = StringName(route.get("route_id", &""))
	if not route_context.has("reason"):
		route_context["reason"] = StringName(route.get("reason", route_context["route"]))
	var activation: StringName = StringName(route.get("activation", CharacterProfileManager.ROUTE_ACTIVATION_EXECUTE))
	if activation == CharacterProfileManager.ROUTE_ACTIVATION_NEUTRAL_AIR:
		return activate_neutral_air_action(route_context)
	if activation == CharacterProfileManager.ROUTE_ACTIVATION_CLEAR_ACTIVE:
		clear_active_action()
		return true
	var target_action_id: StringName = StringName(route.get("target_action", &""))
	var target_action = _get_action_by_id(target_action_id)
	if target_action == null or not _can_execute_action_while_carrying(target_action):
		return false
	if activation == CharacterProfileManager.ROUTE_ACTIVATION_TOGGLE_ON:
		if target_action.has_method("set_routed_toggle_active"):
			return bool(target_action.call("set_routed_toggle_active", true, route_context))
		return false
	if activation == CharacterProfileManager.ROUTE_ACTIVATION_TOGGLE_OFF:
		if target_action.has_method("set_routed_toggle_active"):
			return bool(target_action.call("set_routed_toggle_active", false, route_context))
		return false
	if activation == CharacterProfileManager.ROUTE_ACTIVATION_ACTIVATE:
		return target_action.activate(route_context)
	return target_action.execute(route_context)


func _get_action_by_id(action_id: StringName):
	if action_id == &"":
		return null
	for action in _actions:
		if action != null and is_instance_valid(action) and StringName(action.action_id) == action_id:
			return action
	return null


func _action_uses_homing_targeting(action: Node) -> bool:
	if action == null or not is_instance_valid(action):
		return false
	if not (action is CharacterActionType):
		return false
	if not bool(action.get("enabled")):
		return false
	var uses_targeting: Variant = action.get("uses_homing_targeting")
	return uses_targeting is bool and bool(uses_targeting)


func has_homing_targeting_ability() -> bool:
	return _homing_targeting_ability_count > 0


func _can_scan_homing_targets() -> bool:
	if not _is_player_controlled_targeting_owner():
		return false
	return homing_targeting_enabled and has_homing_targeting_ability()

func _cache_special_action_references() -> void:
	for action in _actions:
		if action is FallAction:
			_fall_action = action
		elif action is JumpAbility:
			_jump_action = action
		elif action is JumpDashAbility:
			_jump_dash_action = action
		elif action is HomingAbility:
			_homing_action = action
		elif action is InstaShieldAction:
			_insta_shield_action = action
		elif action is LightspeedDashAbility:
			_lightspeed_dash_action = action
		elif action is BounceAction:
			_bounce_action = action
		elif action is StompAction:
			_stomp_action = action
		elif action is RollAction:
			_roll_action = action
		elif action is SpindashAction:
			_spindash_action = action
		elif action is DriftAction:
			_drift_action = action
		elif action is SpringAction:
			_spring_action = action
		elif action is HurtAction:
			_hurt_action = action
		elif action is RailGrindAction:
			_rail_grind_action = action
		elif action is GroundedAction:
			_grounded_action = action
		elif action is DrownedActionType:
			_drowned_action = action
	can_grind_rails = _rail_grind_action != null and _rail_grind_action.enabled

	if has_node("TrickSystem"):
		_trick_system = get_node("TrickSystem") as TrickSystem
	elif has_node("Abilities/TrickSystem"):
		_trick_system = get_node("Abilities/TrickSystem") as TrickSystem
	if has_node("Abilities/TrickState"):
		_trick_detector = get_node("Abilities/TrickState") as TrickDetector
	elif has_node("Abilities/TrickDetector"):
		_trick_detector = get_node("Abilities/TrickDetector") as TrickDetector
	var trick_ui_node: Node = null
	if has_node("TrickUI"):
		trick_ui_node = get_node("TrickUI")
	elif has_node("TrickUI_Layer/TrickUI"):
		trick_ui_node = get_node("TrickUI_Layer/TrickUI")
	if trick_ui_node != null:
		_trick_ui = trick_ui_node as TrickUI
		push_warning("TrickUI found: %s" % _trick_ui.name)
	else:
		push_warning("TrickUI NOT found!")

	_sync_trick_system_parameters()


func _sync_trick_system_parameters() -> void:
	if _trick_system == null:
		push_warning("_sync_trick_system_parameters: TrickSystem node missing")
		return

	_trick_system.set_character_presentation_profile(character_visual_profile)
	_trick_system.update_trick_definitions()
	_trick_system.update_audio_streams()
	if _trick_ui != null:
		_trick_ui.set_character_presentation_profile(character_visual_profile)
	if _is_buddy_actor():
		_disable_buddy_combo_system()

func _is_buddy_actor() -> bool:
	return bool(get_meta(&"is_buddy", false))

func _disable_buddy_combo_system() -> void:
	if _trick_system != null:
		if not _trick_system.current_air_tricks.is_empty():
			_trick_system.cancel_combo()
		_trick_system.combo_system_enabled = false
	if _trick_ui != null:
		_trick_ui.set_combo_system_enabled(false)
		_trick_ui.process_mode = Node.PROCESS_MODE_DISABLED

func _apply_action_node_settings() -> void:
	_ensure_modules()
	_action_compatibility._apply_action_node_settings()

func _sync_roll_state_from_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_roll_state_from_action()

func _sync_spindash_state_from_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_spindash_state_from_action()

func _sync_spindash_state_to_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_spindash_state_to_action()

func _sync_drift_state_from_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_drift_state_from_action()

func _sync_drift_state_to_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_drift_state_to_action()

func _sync_spring_state_from_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_spring_state_from_action()

func _sync_spring_state_to_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_spring_state_to_action()

func _sync_hurt_state_from_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_hurt_state_from_action()

func _sync_hurt_state_to_action() -> void:
	_ensure_modules()
	_action_compatibility._sync_hurt_state_to_action()

func _process_action_inputs() -> void:
	var jump_slot: StringName = get_ability_input_slot(&"jump", &"ability_slot_01")
	var skydive_slot: StringName = get_ability_input_slot(&"skydive", &"ability_slot_02")
	if not _network_is_local_authority():
		return
	if _local_pause_enabled:
		return
	if get_tree() != null and get_tree().paused:
		return
	if _ui_input_blocked:
		return
	if _post_ui_unblock_action_suppress_timer > 0.0:
		return
	if _has_enemy_targeting_grace_release_action():
		_release_enemy_targeting_spawn_grace()
	if _hurt_active:
		if SettingsManager.is_gameplay_action_just_pressed(String(jump_slot)) and not race_in_countdown:
			queue_jump()
		return
	if _process_carry_action_inputs():
		return
	if _homing_active and is_ability_binding_just_pressed(&"skydive", skydive_slot):
		cancel_homing_attack(false)

	if _rail_active:
		return
	if _automation_lock_actions and _automation_locks_active():
		return

	if _spring_action_lock_timer > 0.0:
		return
	if _spring_movement_lock_timer > 0.0:
		_spring_movement_lock_timer = 0.0
		return
	if SettingsManager.is_gameplay_action_just_pressed("ability_slot_02") and _switch_drift_direction_from_action1():
		return

	if SettingsManager.is_gameplay_action_just_pressed(String(jump_slot)) and _can_consume_coyote_jump():
		if coyote_jump_homing_priority and _can_scan_homing_targets() and has_homing_target_in_range():
			_jump_dash_requested = true
			return
		queue_coyote_jump()
		return

	if _preemptive_profile_input_consumed or _process_character_profile_input_routes():
		return

	for action in _actions:
		if action == null:
			continue
		if not (action is CharacterActionType):
			continue
		var a = action
		if not a.enabled:
			continue
		if not _can_execute_action_while_carrying(a):
			continue
		if _active_action != null and a != _active_action and not a.allow_when_inactive:
			continue
		if a.input_action == &"":
			continue
		if uses_authoritative_character_profile_routes():
			var route_source_action: StringName = _get_character_profile_route_source_action()
			if _ability_input_router != null and _ability_input_router.is_action_routed_from_input(route_source_action, a.input_action, a.action_id):
				continue
		var consumed: bool = false
		if _ability_input_router != null and _ability_input_router.has_binding(a.action_id):
			if _ability_input_router.is_binding_triggered(a.action_id, a.input_action):
				consumed = a.process_input_event(a.input_action, a.trigger_mode)
		elif SettingsManager.is_gameplay_action_just_pressed(String(a.input_action)):
			consumed = a.process_input_event(a.input_action, CharacterActionType.ActionTrigger.JUST_PRESSED)
		elif SettingsManager.is_gameplay_action_pressed(String(a.input_action)):
			consumed = a.process_input_event(a.input_action, CharacterActionType.ActionTrigger.PRESSED)
		elif SettingsManager.is_gameplay_action_just_released(String(a.input_action)):
			consumed = a.process_input_event(a.input_action, CharacterActionType.ActionTrigger.JUST_RELEASED)
		if consumed:
			break

func _prepare_priority_action_input(delta: float) -> bool:
	for action in _actions:
		if action != null and is_instance_valid(action) and action.prepare_priority_input(delta):
			return true
	return false


func current_action_blocks_surface_attachment() -> bool:
	return _active_action != null and is_instance_valid(_active_action) and _active_action.blocks_surface_attachment()


func has_action_landing_animation_override() -> bool:
	for action in _actions:
		if action != null and is_instance_valid(action) and action.is_landing_animation_override_active():
			return true
	return false


func resolve_current_action_wall_collision_velocity(
	normal: Vector3,
	world_up: Vector3,
	entry_velocity: Vector3
) -> bool:
	if _drift_action != null and is_instance_valid(_drift_action):
		if _drift_action.resolve_wall_collision_velocity(normal, world_up, entry_velocity):
			return true
	if _active_action == null or not is_instance_valid(_active_action):
		return false
	if _active_action == _drift_action:
		return false
	if not _active_action.has_method("resolve_wall_collision_velocity"):
		return false
	return bool(_active_action.call("resolve_wall_collision_velocity", normal, world_up, entry_velocity))


func _update_action_runtime(delta: float) -> void:
	for action in _actions:
		if action != null and is_instance_valid(action) and action.continuous_update and _can_execute_action_while_carrying(action):
			action.continuous_physics_update(delta)
	_update_ability_meter_ui()
	if _ui_input_blocked:
		_clear_action_input_requests()
		return
	if _active_action == null and not attached and not _lightspeed_dash_active:
		activate_neutral_air_action({"reason": &"airborne_neutral"})
	if _active_action == null:
		return
	if not is_instance_valid(_active_action):
		clear_active_action()
		return
	if not _can_execute_action_while_carrying(_active_action):
		clear_active_action()
		return
	_active_action.physics_update_action(delta)
	if attached and _active_action != null and _active_action == _fall_action:
		clear_active_action()


func activate_action(action, context: Dictionary = {}) -> bool:
	if action == null or not is_instance_valid(action):
		return false
	if action.owner_player != self:
		return false
	if not _can_execute_action_while_carrying(action):
		return false
	if not action.can_execute(context):
		return false
	if _active_action != null and is_instance_valid(_active_action) and _active_action != action:
		_active_action.on_action_exit(action)
	_active_action = action
	_current_action_id = action.action_id
	action.on_action_enter(context)
	if action.has_method("play_activation_voice"):
		action.call("play_activation_voice")
	return true


func clear_active_action() -> void:
	if _active_action != null and is_instance_valid(_active_action):
		_active_action.on_action_exit(null)
	_active_action = null
	_current_action_id = &""


func activate_neutral_air_action(context: Dictionary = {}) -> bool:
	if attached:
		return false
	if _fall_action == null or not is_instance_valid(_fall_action):
		return false
	if _active_action == _fall_action:
		return true
	return activate_action(_fall_action, context)


func force_neutral_action(context: Dictionary = {}) -> bool:
	cancel_homing_attack(false)
	_jump_dash_recent_timer = 0.0
	_homing_post_attack_timer = 0.0
	if attached:
		clear_active_action()
		return true
	return activate_neutral_air_action(context)


func reset_flight_eligibility() -> void:
	for action in _actions:
		if action != null and is_instance_valid(action) and action.has_method("reset_flight_eligibility"):
			action.call("reset_flight_eligibility")


func refresh_traversal_actions() -> void:
	for action in _actions:
		if action != null and is_instance_valid(action):
			action.reset_traversal_history()


func notify_wall_kick(normal: Vector3) -> void:
	for action in _actions:
		if action and is_instance_valid(action):
			action.notify_wall_kick(normal)


func refresh_airborne_abilities(refresh_wall_lift: bool = true) -> void:
	_jump_dash_used_this_air = false
	refresh_tornado_kick_availability()
	if not refresh_wall_lift:
		return
	for action in _actions:
		if action and is_instance_valid(action):
			action.refresh_airborne_abilities()


func reset_flight_timer_to_max() -> void:
	for action in _actions:
		if action != null and is_instance_valid(action) and action.has_method("reset_flight_timer_to_max"):
			action.call("reset_flight_timer_to_max")


func add_flight_time(amount: float) -> void:
	for action in _actions:
		if action != null and is_instance_valid(action) and action.has_method("add_flight_time"):
			action.call("add_flight_time", amount)


func add_ability_gauge(ability_id: StringName, amount: float) -> bool:
	if not _network_is_local_authority() or amount <= 0.0:
		return false
	for action in _actions:
		if action == null or not is_instance_valid(action) or not action.has_method("add_ability_meter"):
			continue
		if ability_id != &"" and not _ability_gauge_id_matches(action, ability_id):
			continue
		var add_result: Variant = action.call("add_ability_meter", amount)
		if add_result is bool and not bool(add_result):
			continue
		_update_ability_meter_ui()
		return true
	return false


func _ability_gauge_id_matches(action: Node, ability_id: StringName) -> bool:
	if _object_has_property(action, "action_id") and StringName(action.get("action_id")) == ability_id:
		return true
	if action.has_method("get_ability_meter_name"):
		return StringName(action.call("get_ability_meter_name")) == ability_id
	return false


func _update_ability_meter_ui() -> void:
	for action in _actions:
		if action == null or not is_instance_valid(action):
			continue
		if not action.has_method("has_ability_meter"):
			continue
		if not bool(action.call("has_ability_meter")):
			continue
		var ability_name: String = "Ability"
		var current: float = 0.0
		var max_value: float = 0.0
		if action.has_method("get_ability_meter_name"):
			ability_name = String(action.call("get_ability_meter_name"))
		if action.has_method("get_ability_meter_current"):
			current = float(action.call("get_ability_meter_current"))
		if action.has_method("get_ability_meter_max"):
			max_value = float(action.call("get_ability_meter_max"))
		_set_ability_meter_ui(ability_name, current, max_value, true)
		return
	_set_ability_meter_ui("", 0.0, 1.0, false)


func is_current_action_flight() -> bool:
	if _active_action == null or not is_instance_valid(_active_action):
		return false
	if not _active_action.has_method("is_flight_action"):
		return false
	return bool(_active_action.call("is_flight_action"))


func _current_action_receives_fast_fall_horizontal_drag() -> bool:
	if _active_action == null or not is_instance_valid(_active_action):
		return true
	if not (_active_action is CharacterActionType):
		return true
	var action: CharacterActionType = _active_action
	return action.receives_fast_fall_horizontal_drag()


func _current_action_blocks_shared_movement_integration() -> bool:
	if _active_action == null or not is_instance_valid(_active_action):
		return false
	if not (_active_action is CharacterActionType):
		return false
	var action: CharacterActionType = _active_action
	return action.blocks_shared_movement_integration()


func is_air_acceleration_overridden() -> bool:
	if _active_action == null or not is_instance_valid(_active_action):
		return false
	if not _active_action.has_method("overrides_air_acceleration"):
		return false
	return bool(_active_action.call("overrides_air_acceleration"))


func get_air_acceleration_override(lateral_speed: float, fallback_value: float) -> float:
	if _active_action == null or not is_instance_valid(_active_action):
		return fallback_value
	if not _active_action.has_method("get_air_acceleration_override"):
		return fallback_value
	return float(_active_action.call("get_air_acceleration_override", lateral_speed))


func end_active_flight_for_external_impulse(context: Dictionary = {}) -> bool:
	if not is_current_action_flight():
		return false
	if attached:
		clear_active_action()
		return true
	return _force_neutral_air_action(context)


func _force_neutral_air_action(context: Dictionary = {}) -> bool:
	if attached:
		clear_active_action()
		return true
	if _fall_action == null or not is_instance_valid(_fall_action):
		clear_active_action()
		return false
	if _active_action == _fall_action:
		return true
	if _active_action != null and is_instance_valid(_active_action):
		_active_action.on_action_exit(_fall_action)
	_active_action = _fall_action
	_current_action_id = _fall_action.action_id
	_fall_action.on_action_enter(context)
	if _fall_action.has_method("play_activation_voice"):
		_fall_action.call("play_activation_voice")
	return true


func execute_action_from_path(requester, route_path: NodePath, context: Dictionary = {}) -> bool:
	if requester == null or requester.owner_player != self:
		return false
	if route_path == NodePath():
		return false
	if not requester.has_node(route_path):
		return false
	var target_node: Node = requester.get_node(route_path)
	if not (target_node is CharacterActionType):
		return false
	var target_action = target_node
	if not _can_execute_action_while_carrying(target_action):
		return false
	if not target_action.execute(context):
		return false
	return true


func get_current_action_id() -> StringName:
	return _current_action_id


func is_action_id_active(action_id: StringName) -> bool:
	return _current_action_id == action_id


func is_parkour_active() -> bool:
	return is_action_id_active(&"parkour")


func is_action_exhausted(action_id: StringName) -> bool:
	if not is_action_id_active(action_id):
		return false
	if _active_action == null or not is_instance_valid(_active_action):
		return false
	if not _active_action.has_method("is_exhausted"):
		return false
	return bool(_active_action.call("is_exhausted"))


func is_propeller_flight_active() -> bool:
	return is_action_id_active(&"propeller_flight")


func is_propeller_flight_exhausted() -> bool:
	return is_action_exhausted(&"propeller_flight")


func has_homing_target_in_range() -> bool:
	_ensure_modules()
	return _targeting_module.has_homing_target_in_range()

func _get_homing_target_position(target: Node3D, origin: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module._get_homing_target_position(target, origin)

func _get_homing_target_position_for_aim(target: Node3D, origin: Vector3, aim_origin: Vector3, aim_dir: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module._get_homing_target_position_for_aim(target, origin, aim_origin, aim_dir)

func _is_rail_like_homing_target(target: Node) -> bool:
	_ensure_modules()
	return _targeting_module._is_rail_like_homing_target(target)

func _set_homing_candidate_position(target: Node3D, position: Vector3) -> void:
	_ensure_modules()
	_targeting_module._set_homing_candidate_position(target, position)

func _get_homing_candidate_position(target: Node3D, origin: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module._get_homing_candidate_position(target, origin)

func _refresh_homing_candidate_position(target: Node3D, origin: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module._refresh_homing_candidate_position(target, origin)

func get_homing_attack_target_position() -> Vector3:
	_ensure_modules()
	return _targeting_module.get_homing_attack_target_position()

func get_homing_reticle_target_position(target: Node3D) -> Vector3:
	_ensure_modules()
	return _targeting_module.get_homing_reticle_target_position(target)

func limit_homing_bounce_from_below(result_velocity: Vector3, target_position: Vector3, up: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module.limit_homing_bounce_from_below(result_velocity, target_position, up)

func _apply_attack_magnetism(delta: float, physics_up: Vector3, current_velocity: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module._apply_attack_magnetism(delta, physics_up, current_velocity)

func _tick_attack_magnetism_bounce_compensation(delta: float) -> void:
	_ensure_modules()
	_targeting_module._tick_attack_magnetism_bounce_compensation(delta)

func _store_attack_magnetism_bounce_compensation(lost_descent: float) -> void:
	_ensure_modules()
	_targeting_module._store_attack_magnetism_bounce_compensation(lost_descent)

func _consume_attack_magnetism_bounce_compensation() -> float:
	_ensure_modules()
	return _targeting_module._consume_attack_magnetism_bounce_compensation()

func _get_attack_magnetism_scan_result(delta: float, heading: Vector3, up: Vector3, current_velocity: Vector3) -> Dictionary:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_scan_result(delta, heading, up, current_velocity)

func _is_attack_magnetism_scan_result_valid() -> bool:
	_ensure_modules()
	return _targeting_module._is_attack_magnetism_scan_result_valid()

func _can_apply_attack_magnetism() -> bool:
	_ensure_modules()
	return _targeting_module._can_apply_attack_magnetism()

func _is_player_controlled_targeting_owner() -> bool:
	_ensure_modules()
	return _targeting_module._is_player_controlled_targeting_owner()

func _current_action_permits_attack_magnetism() -> bool:
	_ensure_modules()
	return _targeting_module._current_action_permits_attack_magnetism()

func _is_attack_magnetism_attack_state_active() -> bool:
	_ensure_modules()
	return _targeting_module._is_attack_magnetism_attack_state_active()

func _get_attack_magnetism_heading(current_velocity: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_heading(current_velocity)

func _select_attack_magnetism_target(origin: Vector3, heading: Vector3, up: Vector3, current_velocity: Vector3) -> Dictionary:
	_ensure_modules()
	return _targeting_module._select_attack_magnetism_target(origin, heading, up, current_velocity)

func _get_attack_magnetism_player_range(current_velocity: Vector3) -> float:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_player_range(current_velocity)

func _get_attack_magnetism_candidates(origin: Vector3, max_range: float) -> Array:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_candidates(origin, max_range)

func _add_attack_magnetism_candidate(candidates: Array, seen: Dictionary, target: Node) -> void:
	_ensure_modules()
	_targeting_module._add_attack_magnetism_candidate(candidates, seen, target)

func _is_attack_magnetism_target_available(target: Node3D) -> bool:
	_ensure_modules()
	return _targeting_module._is_attack_magnetism_target_available(target)

func _get_attack_magnetism_target_position(target: Node3D) -> Vector3:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_target_position(target)

func _get_attack_magnetism_setting(target: Node3D, property_name: String, fallback_value: float) -> float:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_setting(target, property_name, fallback_value)

func _get_attack_magnetism_input_factor(target_dir: Vector3, up: Vector3) -> float:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_input_factor(target_dir, up)

func _get_attack_magnetism_descent_factor(current_velocity: Vector3, up: Vector3) -> float:
	_ensure_modules()
	return _targeting_module._get_attack_magnetism_descent_factor(current_velocity, up)

func _perform_jump_dash(physics_up: Vector3, is_attached: bool, lateral: Vector3) -> Vector3:
	_ensure_modules()
	return _targeting_module._perform_jump_dash(physics_up, is_attached, lateral)

func _get_homing_target_direction() -> Vector3:
	_ensure_modules()
	return _targeting_module._get_homing_target_direction()

func _select_homing_target(origin: Vector3, max_range: float) -> Node3D:
	_ensure_modules()
	return _targeting_module._select_homing_target(origin, max_range)


func _get_homing_target_request_status(
	origin: Vector3,
	max_range: float,
	wait_for_next_scan: bool = true
) -> Dictionary:
	_ensure_modules()
	return _targeting_module.get_homing_target_request_status(origin, max_range, wait_for_next_scan)


func _clear_homing_target_request_buffer() -> void:
	_ensure_modules()
	_targeting_module.clear_homing_target_request_buffer()

func _find_best_homing_target_camera(origin: Vector3, max_range: float) -> Node3D:
	_ensure_modules()
	return _targeting_module._find_best_homing_target_camera(origin, max_range)

func _find_best_homing_target(origin: Vector3, dash_dir: Vector3, max_range: float) -> Node3D:
	_ensure_modules()
	return _targeting_module._find_best_homing_target(origin, dash_dir, max_range)

func _get_homing_reticle_target() -> Node3D:
	_ensure_modules()
	return _targeting_module._get_homing_reticle_target()

func _try_handle_homing_hit(target: Node, jump_held: bool) -> bool:
	_ensure_modules()
	return _targeting_module._try_handle_homing_hit(target, jump_held)

func _end_homing(up: Vector3, jump_held: bool) -> void:
	_ensure_modules()
	_targeting_module._end_homing(up, jump_held)

func _update_homing(delta: float, up_for_physics: Vector3, is_attached: bool) -> void:
	_ensure_modules()
	_targeting_module._update_homing(delta, up_for_physics, is_attached)

func cancel_homing_attack(restore_saved_velocity: bool = false) -> void:
	_ensure_modules()
	_targeting_module.cancel_homing_attack(restore_saved_velocity)

func _try_start_lightspeed_dash() -> bool:
	_ensure_modules()
	return _targeting_module._try_start_lightspeed_dash()

func _get_lightspeed_forward_bias() -> Vector3:
	_ensure_modules()
	return _targeting_module._get_lightspeed_forward_bias()

func _is_ring_available_for_lightspeed(ring: Variant) -> bool:
	_ensure_modules()
	return _targeting_module._is_ring_available_for_lightspeed(ring)

func _find_best_lightspeed_ring(origin: Vector3, max_radius: float, forward_bias: Vector3, exclude_instance_id: int) -> Node3D:
	_ensure_modules()
	return _targeting_module._find_best_lightspeed_ring(origin, max_radius, forward_bias, exclude_instance_id)

func _advance_lightspeed_dash_target() -> bool:
	_ensure_modules()
	return _targeting_module._advance_lightspeed_dash_target()

func _update_lightspeed_dash(_delta: float, _physics_up: Vector3) -> void:
	_ensure_modules()
	_targeting_module._update_lightspeed_dash(_delta, _physics_up)

func _post_move_lightspeed_dash(_delta: float) -> void:
	_ensure_modules()
	_targeting_module._post_move_lightspeed_dash(_delta)

func _end_lightspeed_dash(apply_release_velocity: bool, try_attach: bool = false) -> void:
	_ensure_modules()
	_targeting_module._end_lightspeed_dash(apply_release_velocity, try_attach)

func _attempt_lightspeed_dash_ground_attach() -> void:
	_ensure_modules()
	_targeting_module._attempt_lightspeed_dash_ground_attach()

func _find_lightspeed_dash_attach_hit() -> Dictionary:
	_ensure_modules()
	return _targeting_module._find_lightspeed_dash_attach_hit()

func _stop_lightspeed_dash_if_active(apply_release_velocity: bool = false) -> void:
	_ensure_modules()
	_targeting_module._stop_lightspeed_dash_if_active(apply_release_velocity)

func cancel_spline_spring() -> void:
	_ensure_modules()
	_external_motion_module.cancel_spline_spring()


func clear_object_lock_timers() -> void:
	if _active_action is SpringAction:
		clear_active_action()
	if _pending_anim_command == &"CMD_SPRING":
		_pending_anim_command = &""
		_pending_anim_crossfade = -1.0
	cancel_spline_spring()
	_spring_movement_lock_timer = 0.0
	_spring_action_lock_timer = 0.0
	_spring_clear_move_on_ground = false
	_spring_clear_action_on_ground = false
	_finish_spring_landing_state()
	if is_instance_valid(_spring_action):
		_sync_spring_state_to_action()


func begin_vault_bar(
	source: Node,
	grip_position: Vector3,
	model_basis: Basis,
	animation_name: StringName
) -> bool:
	_ensure_modules()
	var started: bool = _external_motion_module.begin_vault_bar(source, grip_position, model_basis, animation_name)
	if started:
		register_combo_feat(&"vault_bar", "Vault Bar", 250.0, 1.0)
	return started


func set_vault_bar_pose(source: Node, grip_position: Vector3, model_basis: Basis) -> bool:
	_ensure_modules()
	return _external_motion_module.set_vault_bar_pose(source, grip_position, model_basis)


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
	_ensure_modules()
	return _external_motion_module.launch_from_vault_bar(
		source,
		launch_velocity,
		angular_velocity,
		movement_lock_time,
		action_lock_time,
		align_time,
		launch_basis,
		spline_path,
		spline_speed,
		spline_world_offset,
		pitch_trick_command
	)


func cancel_vault_bar(source: Node = null) -> void:
	_ensure_modules()
	_external_motion_module.cancel_vault_bar(source)


func _update_vault_bar(delta: float) -> void:
	_ensure_modules()
	_external_motion_module.update_vault_bar(delta)

func cancel_rail_grind(reset_velocity: bool = false) -> void:
	_ensure_modules()
	_rail_module.cancel_rail_grind(reset_velocity)

# SUMMARY: Cache automation spline influence for the next physics frame.
# NOTE: force_surface_adhesion preserves contact across steep and sharp geometry.
# NOTE: lock_controls is legacy; lock_movement/actions/drift provide separate locks.
# NOTE: priority selects the active automation when multiple splines overlap.
func set_timed_max_speed_override(speed: float, duration: float) -> void:
	_ensure_modules()
	_external_motion_module.set_timed_max_speed_override(speed, duration)

func clear_timed_max_speed_override() -> void:
	_ensure_modules()
	_external_motion_module.clear_timed_max_speed_override()

func clear_max_speed_overrides() -> void:
	_ensure_modules()
	_external_motion_module.clear_max_speed_overrides()

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
	_ensure_modules()
	_external_motion_module.set_automation_spline(tangent_dir, toward_dir, toward_strength, max_turn_deg_per_sec, lock_controls, continuous_force, align_rotation, grounded_only, force_surface_adhesion, tangent_snap_strength, along_assist_enabled, along_assist_target_speed, along_assist_accel, lock_movement, lock_actions, lock_drift, priority, ignore_water_physics_multipliers, override_max_speed, max_speed_override)

func set_automation_spline_state(state: Dictionary) -> void:
	_ensure_modules()
	_external_motion_module.set_automation_spline_state(state)

func _automation_locks_active() -> bool:
	_ensure_modules()
	return _external_motion_module._automation_locks_active()

func _object_has_property(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	var cache_key: String = _get_property_cache_key(obj)
	if cache_key == "":
		return false
	if not _property_name_cache.has(cache_key):
		var names: Dictionary = {}
		for item in obj.get_property_list():
			if item is Dictionary and item.has("name"):
				names[String(item["name"])] = true
		_property_name_cache[cache_key] = names
	var cached_names: Dictionary = _property_name_cache[cache_key]
	return cached_names.has(property_name)


func _get_property_cache_key(obj: Object) -> String:
	if obj == null:
		return ""
	var script: Variant = obj.get_script()
	if script is Script:
		var script_resource: Script = script
		if script_resource.resource_path != "":
			return "script:%s" % script_resource.resource_path
		return "script_id:%d" % script_resource.get_instance_id()
	return "class:%s" % obj.get_class()

func _do_bounce_landing(v_before: Vector3, landing_normal: Vector3) -> void:
	var n: Vector3 = landing_normal.normalized()
	if n.length() < 0.001:
		return

	var v: Vector3 = v_before

	# Decompose into normal + tangential components relative to the landing surface
	var v_normal: Vector3 = n * v.dot(n)
	var v_tangent: Vector3 = v - v_normal

	v_tangent = _apply_horizontal_speed_penalty(
		v_tangent,
		bounce_land_horizontal_threshold,
		bounce_land_horizontal_subtract
	)

	# Speed into the surface (positive when moving into it)
	var into_speed: float = -v_normal.dot(n)
	if into_speed < 0.0:
		into_speed = 0.0

	# Enforce a minimum impact speed so tiny drops still bounce decently
	if into_speed < bounce_min_impact_speed:
		into_speed = bounce_min_impact_speed

	into_speed = _apply_landing_speed_subtraction(
		into_speed,
		bounce_land_speed_threshold,
		bounce_land_speed_subtract
	)

	# Bounce magnitude = impact speed + additive
	var bounce_speed: float = into_speed + bounce_add_speed
	bounce_speed = clamp(bounce_speed, bounce_min_up_speed, bounce_max_up_speed)

	# Final velocity: keep tangential unchanged, flip normal upwards along the surface
	velocity = v_tangent + n * bounce_speed

	_on_trick_detected(TrickSystem.TrickType.BOUNCE_POGO)

	# We are airborne after the bounce.
	attached = false
	refresh_traversal_actions()
	refresh_airborne_abilities()
	_airborne_time = 0.0

	# Kill "falling" flag so other logic knows we've just pushed off
	_is_falling = false

	# This is not a normal jump
	_is_jumping = false
	_jump_hang_allowed = false
	_jump_time = 0.0

	# SFX for bounce landing
	_play_sfx(sfx_bounce_land)

	_bounce_rebound_attack_active = true
	_bounce_state = BounceState.REBOUND
	var rebound_action: CharacterAction = _get_action_by_id(&"bounce_rebound")
	if rebound_action != null:
		rebound_action.execute({"reason": &"bounce_landing", "source_action": &"bounce"})
	reset_flight_eligibility()
	end_active_flight_for_external_impulse({"reason": &"bounce_landing"})


func finish_bounce_rebound() -> bool:
	if _bounce_state != BounceState.REBOUND:
		return false
	_bounce_state = BounceState.NONE
	_bounce_rebound_attack_active = false
	return true

func _apply_landing_speed_subtraction(
	into_speed: float,
	threshold: float,
	subtract: float
) -> float:
	if subtract <= 0.0:
		return into_speed
	if threshold < 0.0:
		threshold = 0.0
	if into_speed <= threshold:
		return into_speed
	return max(into_speed - subtract, threshold)


func _apply_velocity_speed_subtraction(
	velocity_in: Vector3,
	normal: Vector3,
	threshold: float,
	subtract: float
) -> Vector3:
	if subtract <= 0.0:
		return velocity_in

	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return velocity_in

	var v_normal: Vector3 = n * velocity_in.dot(n)
	var into_speed: float = -v_normal.dot(n)
	if into_speed <= threshold:
		return velocity_in

	var new_speed : float = max(into_speed - subtract, threshold)
	var v_tangent: Vector3 = velocity_in - v_normal
	var new_v_normal : Vector3 = -n * new_speed
	return v_tangent + new_v_normal


func _apply_horizontal_speed_penalty(
	tangent_velocity: Vector3,
	threshold: float,
	subtract: float
) -> Vector3:
	if subtract <= 0.0:
		return tangent_velocity

	var speed: float = tangent_velocity.length()
	if speed <= threshold or speed <= 0.0001:
		return tangent_velocity

	var new_speed : float = max(speed - subtract, threshold)
	return tangent_velocity.normalized() * new_speed


func _apply_horizontal_velocity_penalty(
	velocity_in: Vector3,
	normal: Vector3,
	threshold: float,
	subtract: float
) -> Vector3:
	if subtract <= 0.0:
		return velocity_in

	var n: Vector3 = normal.normalized()
	if n.length() < 0.001:
		return velocity_in

	var v_normal: Vector3 = n * velocity_in.dot(n)
	var v_tangent: Vector3 = velocity_in - v_normal
	var new_v_tangent: Vector3 = _apply_horizontal_speed_penalty(v_tangent, threshold, subtract)
	return new_v_tangent + v_normal

# ===========================================================
# ABILITY QUEUE
# ===========================================================
func can_queue_jump() -> bool:
	if _action_input_locked():
		return false
	if attached and is_surface_jump_blocked():
		return false
	if _automation_lock_actions and _automation_locks_active():
		return false
	if race_in_countdown:
		return false
	return true


func queue_jump() -> bool:
	if not can_queue_jump():
		return false
	_jump_requested = true
	_notify_buddy_leader_jump_pressed()
	return true


func can_queue_coyote_jump() -> bool:
	if _action_input_locked():
		return false
	if is_surface_coyote_jump_blocked():
		return false
	if _automation_lock_actions and _automation_locks_active():
		return false
	if race_in_countdown:
		return false
	return true


func queue_coyote_jump() -> bool:
	if not can_queue_coyote_jump():
		return false
	_coyote_jump_requested = true
	_jump_requested = true
	_notify_buddy_leader_jump_pressed()
	return true
	
func can_queue_jump_dash() -> bool:
	if _action_input_locked():
		return false
	if is_combat_homing_locked():
		return false
	if _automation_lock_actions and _automation_locks_active():
		return false
	if race_in_countdown:
		return false
	if jump_dash_air_only and attached:
		return false
	if jump_dash_once_per_air and _jump_dash_used_this_air:
		return false
	return true


func queue_jump_dash() -> bool:
	if not can_queue_jump_dash():
		return false
	if not attached and _can_consume_coyote_jump():
		if coyote_jump_homing_priority and _can_scan_homing_targets():
			var speed_now: float = velocity.length()
			var max_range: float = homing_min_range + speed_now * homing_range_per_speed
			max_range = clamp(max_range, homing_min_range, homing_max_range)
			var status: Dictionary = _get_homing_target_request_status(global_position, max_range, true)
			if not bool(status.get("ready", false)) or status.get("target") is Node3D:
				_jump_dash_requested = true
				return true
		return queue_coyote_jump()
	_jump_dash_requested = true
	return true


func can_queue_homing_attack() -> bool:
	if _action_input_locked():
		return false
	if is_combat_homing_locked():
		return false
	if _automation_lock_actions and _automation_locks_active():
		return false
	if race_in_countdown or attached:
		return false
	return true


func queue_homing_attack() -> bool:
	if not can_queue_homing_attack():
		return false
	_jump_dash_requested = true
	return true


func can_offer_action_prompts() -> bool:
	if not _network_is_local_authority() or _is_buddy_actor() or _action_input_locked():
		return false
	if _is_dead or _hurt_active or race_in_countdown or _post_ui_unblock_action_suppress_timer > 0.0:
		return false
	if _rail_active or _spline_active or _vault_bar_active or _lightspeed_dash_active or is_carrying_object():
		return false
	if _spring_action_lock_timer > 0.0 or _spring_movement_lock_timer > 0.0 or _spring_align_timer > 0.0:
		return false
	return not (_automation_lock_actions and _automation_locks_active())


func has_homing_target_for_prompt() -> bool:
	if not _targeting_module or not _can_scan_homing_targets() or attached:
		return false
	if Time.get_ticks_msec() - _homing_reticle_cached_time_ms > HOMING_RETICLE_CACHE_MS:
		return false
	var max_range: float = clampf(homing_min_range + velocity.length() * homing_range_per_speed, homing_min_range, homing_max_range)
	return _targeting_module._get_valid_cached_homing_target(global_position, max_range, SettingsManager.get_active_homing_targeting_mode()) != null


func _action_input_locked() -> bool:
	if _local_pause_enabled or _ui_input_blocked or _debug_mode:
		return true
	if get_tree() != null and get_tree().paused:
		return true
	return false


func _clear_action_input_requests() -> void:
	_jump_requested = false
	_coyote_jump_requested = false
	_jump_dash_requested = false
	_clear_homing_target_request_buffer()


func can_start_lightspeed_dash() -> bool:
	if not lightspeed_dash_enabled:
		return false
	if _lightspeed_dash_active:
		return false
	if _automation_lock_actions and _automation_locks_active():
		return false
	if _local_pause_enabled or _ui_input_blocked or _debug_mode:
		return false
	if race_in_countdown and not race_active:
		return false
	if _is_dead or _hurt_active:
		return false
	if _rail_active or _rail_switch_active or _spline_active:
		return false
	if _spring_align_timer > 0.0 or _spring_movement_lock_timer > 0.0 or _spring_action_lock_timer > 0.0:
		return false
	var forward_bias: Vector3 = _get_lightspeed_forward_bias()
	var target: Node3D = _find_best_lightspeed_ring(global_position, lightspeed_dash_start_radius, forward_bias, 0)
	return target != null


func queue_lightspeed_dash(_context: Dictionary = {}) -> bool:
	if not lightspeed_dash_enabled:
		return false
	return _try_start_lightspeed_dash()


func is_lightspeed_dash_active() -> bool:
	return _lightspeed_dash_active


func should_prioritize_spindash_over_bounce_stomp() -> bool:
	if _spindash_action != null and _spindash_action.is_charging:
		return true
	if _spindash_charging:
		return true
	if uses_character_ability_profile():
		return false
	return _can_claim_midair_spindash_from_current_input()


func _can_claim_midair_spindash_from_current_input() -> bool:
	if attached:
		return false
	if not spindash_enabled:
		return false
	if not SettingsManager.is_gameplay_action_pressed("ability_slot_02"):
		return false
	if not SettingsManager.is_gameplay_action_pressed("ability_slot_04"):
		return false
	if _spindash_roll_route_lockout_timer > 0.0:
		return false
	if _hurt_active:
		return false
	if _local_pause_enabled or _ui_input_blocked or _debug_mode:
		return false
	if _spline_active or _rail_active:
		return false
	if _automation_lock_actions and _automation_locks_active():
		return false
	if _spring_action_lock_timer > 0.0 or _spring_movement_lock_timer > 0.0:
		return false
	if _spring_align_timer > 0.0:
		return false
	if _homing_active:
		return false
	if _bounce_state != BounceState.NONE:
		return false
	var roll_ready: bool = false
	if _roll_action != null:
		roll_ready = _roll_action.is_rolling or _roll_action._can_start_roll()
	else:
		roll_ready = rolling or _can_start_roll()
	return roll_ready

func queue_bounce_attack() -> void:
	if not bounce_enabled:
		return
	if should_prioritize_spindash_over_bounce_stomp():
		return

	# Only start bounce in the air
	if attached:
		return

	if _bounce_state != BounceState.NONE and _bounce_state != BounceState.REBOUND:
		return

	_bounce_rebound_attack_active = false
	_bounce_state = BounceState.BOUNCE

	var world_up: Vector3 = _get_gravity_up()
	_trigger_anim_command(&"CMD_BOUNCE")
	_cancel_air_tumble_for_action(world_up)

	# Use gravity-up for bounce and stomp vertical, not the last surface up.

	var v: Vector3 = velocity
	var vertical: float = v.dot(world_up)

	# One-shot downward impulse:
	# - If rising: invert + additive.
	# - If already falling: push further down.
	var new_vertical: float
	if vertical > 0.0:
		# Rising → force a fixed downward impulse
		new_vertical = -bounce_down_impulse
	else:
		# Falling → additive push downward
		new_vertical = vertical - bounce_down_impulse

	v += world_up * (new_vertical - vertical)
	velocity = v
	
	# SFX for bounce start
	_play_sfx(sfx_bounce_start)
	
	# Kill normal jump logic while in bounce
	_is_jumping = false
	_jump_hang_allowed = false
	_jump_time = 0.0


func cancel_bounce_stomp_for_action() -> bool:
	if _bounce_state == BounceState.NONE:
		return false
	_bounce_state = BounceState.NONE
	_bounce_rebound_attack_active = false
	if _current_action_id == &"bounce" or _current_action_id == &"stomp":
		clear_active_action()
	return true


func queue_stomp_attack() -> void:
	if should_prioritize_spindash_over_bounce_stomp():
		return
	if attached:
		return
	if _bounce_state == BounceState.STOMP:
		return
	_bounce_state = BounceState.STOMP

	var world_up: Vector3 = _get_gravity_up()
	_trigger_anim_command(&"CMD_BOUNCE")
	_cancel_air_tumble_for_action(world_up)

	var v: Vector3 = velocity
	var vertical: float = v.dot(world_up)
	var new_vertical: float
	if vertical > 0.0:
		new_vertical = -stomp_down_impulse
	else:
		new_vertical = vertical - stomp_down_impulse
	v += world_up * (new_vertical - vertical)
	velocity = v
	_play_sfx(sfx_stomp_start)
	_is_jumping = false
	_jump_hang_allowed = false
	_jump_time = 0.0


# ===========================================================
# COMBAT
# ===========================================================
func is_attack_active() -> bool:
	_ensure_modules()
	return _combat_module.is_attack_active()

func is_hurt_active() -> bool:
	_ensure_modules()
	return _combat_module.is_hurt_active()

func is_hurt_invulnerable() -> bool:
	_ensure_modules()
	return _combat_module.is_hurt_invulnerable()


func is_death_sequence_active() -> bool:
	_ensure_modules()
	return _combat_module.is_death_sequence_active()


func is_post_race_protected() -> bool:
	return race_finished


func begin_death_sequence(death_type: StringName = &"generic") -> void:
	_ensure_modules()
	_combat_module.begin_death_sequence(death_type)


func apply_death_respawn_consequences(death_type: StringName = &"generic") -> void:
	_ensure_modules()
	_combat_module.apply_death_respawn_consequences(death_type)


func finish_death_sequence() -> void:
	_ensure_modules()
	_combat_module.finish_death_sequence()


func is_airborne() -> bool:
	_ensure_modules()
	return _combat_module.is_airborne()

func get_combat_class() -> CombatClass:
	_ensure_modules()
	return _combat_module.get_combat_class()

static func resolve_combat(attacker: CombatClass, defender: CombatClass) -> CombatOutcome:
	if attacker == CombatClass.NEUTRAL:
		return CombatOutcome.LOSE
	if defender == CombatClass.NEUTRAL:
		return CombatOutcome.WIN
	return CombatOutcome.DRAW


func cancel_attack_for_combat_response(reason: StringName = &"combat_response") -> void:
	_ensure_modules()
	_combat_module.cancel_attack_for_combat_response(reason)


func is_insta_shield_defense_active() -> bool:
	return _insta_shield_action != null and is_instance_valid(_insta_shield_action) and _insta_shield_action.is_defense_active()


func is_insta_shield_parry_active() -> bool:
	return _insta_shield_action != null and is_instance_valid(_insta_shield_action) and _insta_shield_action.is_parry_active()


func is_insta_shield_block_active() -> bool:
	return _insta_shield_action != null and is_instance_valid(_insta_shield_action) and _insta_shield_action.is_block_active()


func is_insta_shield_thrown_vulnerable() -> bool:
	return _insta_shield_action != null and is_instance_valid(_insta_shield_action) and _insta_shield_action.is_thrown_vulnerable()


func is_insta_shield_combat_control_locked() -> bool:
	return _insta_shield_action != null and is_instance_valid(_insta_shield_action) and _insta_shield_action.is_combat_control_locked()


func is_insta_shield_input_consumed() -> bool:
	return _insta_shield_action != null and is_instance_valid(_insta_shield_action) and _insta_shield_action.is_chord_input_consumed()


func resolve_incoming_combat_attack(attacker: Node3D, attack_velocity: Vector3) -> int:
	if _insta_shield_action == null or not is_instance_valid(_insta_shield_action):
		return InstaShieldAction.DefenseResult.NONE
	return int(_insta_shield_action.resolve_incoming_attack(attacker, attack_velocity))


func try_activate_insta_shield_for_ai(hold_duration: float = 1.0) -> bool:
	if _insta_shield_action == null or not is_instance_valid(_insta_shield_action):
		return false
	return _insta_shield_action.start_for_rival(hold_duration)


func begin_insta_shield_grapple(defender: Node3D, attack_velocity: Vector3, shared_drift: Vector3) -> bool:
	if _insta_shield_action == null or not is_instance_valid(_insta_shield_action):
		return false
	return _insta_shield_action.begin_grappled_by(defender, attack_velocity, shared_drift)


func cancel_insta_shield_grapple(attacker: Node3D) -> void:
	if _insta_shield_action != null and is_instance_valid(_insta_shield_action):
		_insta_shield_action.cancel_grapple_from_attacker(attacker)


func receive_insta_shield_throw(defender: Node3D, throw_velocity: Vector3) -> void:
	if _insta_shield_action != null and is_instance_valid(_insta_shield_action):
		_insta_shield_action.receive_parry_throw(defender, throw_velocity)


func apply_combat_homing_lockout(duration: float) -> void:
	_combat_homing_lockout_timer = max(_combat_homing_lockout_timer, max(duration, 0.0))
	cancel_homing_attack(false)
	_jump_dash_requested = false
	_clear_homing_target_request_buffer()


func is_combat_homing_locked() -> bool:
	return _combat_homing_lockout_timer > 0.0


func _set_hurt_flash_visible(value: bool) -> void:
	_ensure_modules()
	_combat_module._set_hurt_flash_visible(value)

func _cache_hurt_flash_renderers() -> void:
	_ensure_modules()
	_combat_module._cache_hurt_flash_renderers()

func _collect_hurt_flash_renderers(node: Node) -> void:
	_ensure_modules()
	_combat_module._collect_hurt_flash_renderers(node)

func _update_hurt_invuln_visual(delta: float) -> void:
	_ensure_modules()
	_combat_module._update_hurt_invuln_visual(delta)

func set_attack_active(active: bool) -> void:
	_ensure_modules()
	_combat_module.set_attack_active(active)

func note_airborne_roll_uncurl_attack() -> void:
	_ensure_modules()
	_combat_module.note_airborne_roll_uncurl_attack()

func _set_attack_source(flag: int, active: bool) -> void:
	_ensure_modules()
	_combat_module._set_attack_source(flag, active)

func _set_attack_pass_through_collision_enabled(is_enabled: bool) -> void:
	if attack_pass_through_surface_mask == 0:
		return
	if is_enabled:
		collision_mask = collision_mask | attack_pass_through_surface_mask
	else:
		collision_mask = collision_mask & ~attack_pass_through_surface_mask


func _begin_enemy_hurt_boundary_pass_through(source: Node) -> void:
	_enemy_hurt_boundary_launch_capture_armed = false
	if source == null or enemy_hurt_boundary_pass_through_sec <= 0.0:
		return
	var boundary_body: PhysicsBody3D = _find_enemy_momentum_boundary_body(source)
	if boundary_body == null or boundary_body == self:
		return
	var body_id: int = boundary_body.get_instance_id()
	if not _enemy_hurt_boundary_exceptions.has(body_id):
		add_collision_exception_with(boundary_body)
	_enemy_hurt_boundary_exceptions[body_id] = {
		"body": weakref(boundary_body),
		"remaining": max(enemy_hurt_boundary_pass_through_sec, 0.0),
	}
	_enemy_hurt_boundary_launch_capture_armed = true


func _capture_enemy_hurt_boundary_launch_velocity() -> void:
	if not _enemy_hurt_boundary_launch_capture_armed:
		return
	_enemy_hurt_boundary_launch_capture_armed = false
	_enemy_hurt_boundary_launch_velocity = velocity
	_enemy_hurt_boundary_launch_restore_pending = true


func _apply_pending_enemy_hurt_boundary_launch(world_up: Vector3) -> void:
	if not _enemy_hurt_boundary_launch_restore_pending:
		return
	_enemy_hurt_boundary_launch_restore_pending = false
	var up: Vector3 = world_up.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()
	var saved_vertical: float = _enemy_hurt_boundary_launch_velocity.dot(up)
	var current_vertical: float = velocity.dot(up)
	if current_vertical < saved_vertical:
		var current_lateral: Vector3 = velocity - up * current_vertical
		var saved_lateral: Vector3 = _enemy_hurt_boundary_launch_velocity - up * saved_vertical
		velocity = saved_lateral if saved_lateral.length() > current_lateral.length() else current_lateral
		velocity += up * saved_vertical
	attached = false
	_ground_snap_attached_this_frame = false
	_pending_landing_has_velocity = false
	_follow_hit = false
	_attachment_immunity = max(_attachment_immunity, launch_immunity_time)
	_airborne_time = 0.0


func _find_enemy_momentum_boundary_body(source: Node) -> PhysicsBody3D:
	var candidate: Node = source
	while candidate != null:
		if candidate is PhysicsBody3D:
			var preserves_momentum: Variant = candidate.get_meta(
				SURFACE_METADATA.PRESERVE_PLAYER_MOMENTUM,
				false
			)
			if preserves_momentum is bool and bool(preserves_momentum):
				return candidate as PhysicsBody3D
		candidate = candidate.get_parent()
	return null


func _tick_enemy_hurt_boundary_exceptions(delta: float) -> void:
	for body_id: Variant in _enemy_hurt_boundary_exceptions.keys():
		var entry: Dictionary = _enemy_hurt_boundary_exceptions.get(body_id, {}) as Dictionary
		var body_reference: WeakRef = entry.get("body") as WeakRef
		var boundary_body: PhysicsBody3D = body_reference.get_ref() as PhysicsBody3D if body_reference != null else null
		var remaining: float = max(float(entry.get("remaining", 0.0)) - delta, 0.0)
		if remaining <= 0.0:
			if boundary_body != null and is_instance_valid(boundary_body):
				remove_collision_exception_with(boundary_body)
			_enemy_hurt_boundary_exceptions.erase(body_id)
			continue
		entry["remaining"] = remaining
		_enemy_hurt_boundary_exceptions[body_id] = entry


func _clear_enemy_hurt_boundary_exceptions() -> void:
	for entry_value: Variant in _enemy_hurt_boundary_exceptions.values():
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value as Dictionary
		var body_reference: WeakRef = entry.get("body") as WeakRef
		var boundary_body: PhysicsBody3D = body_reference.get_ref() as PhysicsBody3D if body_reference != null else null
		if boundary_body != null and is_instance_valid(boundary_body):
			remove_collision_exception_with(boundary_body)
	_enemy_hurt_boundary_exceptions.clear()
	_enemy_hurt_boundary_launch_capture_armed = false
	_enemy_hurt_boundary_launch_restore_pending = false
	_enemy_hurt_boundary_launch_velocity = Vector3.ZERO

func _update_attack_sources() -> void:
	_ensure_modules()
	_combat_module._update_attack_sources()

func apply_enemy_bounce(origin: Vector3, speed: float, source: Node = null) -> void:
	_ensure_modules()
	_combat_module.apply_enemy_bounce(origin, speed, source)

func apply_enemy_attack_bounce(end_bounce_stomp: bool = false, source: Node = null) -> void:
	_ensure_modules()
	_combat_module.apply_enemy_attack_bounce(end_bounce_stomp, source)

func _homing_contact_matches_source(source: Node) -> bool:
	_ensure_modules()
	return _combat_module._homing_contact_matches_source(source)

func _interrupt_skydive_for_enemy_bounce(reason: StringName) -> void:
	_ensure_modules()
	_combat_module._interrupt_skydive_for_enemy_bounce(reason)

func _get_homing_contact_up() -> Vector3:
	_ensure_modules()
	return _combat_module._get_homing_contact_up()

func _get_homing_contact_direction(source: Node, fallback_velocity: Vector3, fallback_origin: Vector3) -> Vector3:
	_ensure_modules()
	return _combat_module._get_homing_contact_direction(source, fallback_velocity, fallback_origin)

func _get_homing_contact_pass_through(source: Node) -> bool:
	_ensure_modules()
	return _combat_module._get_homing_contact_pass_through(source)

func _get_homing_contact_pop_speed(source: Node) -> float:
	_ensure_modules()
	return _combat_module._get_homing_contact_pop_speed(source)

func _complete_homing_from_enemy_contact(source: Node, contact_velocity: Vector3, contact_lateral: Vector3, up: Vector3, fallback_origin: Vector3) -> void:
	_ensure_modules()
	_combat_module._complete_homing_from_enemy_contact(source, contact_velocity, contact_lateral, up, fallback_origin)

func apply_damage(_amount: int = 1, _source: Node = null) -> void:
	_ensure_modules()
	_combat_module.apply_damage(_amount, _source)

func apply_death_plane_damage(_source: Node = null) -> void:
	_ensure_modules()
	_combat_module.apply_death_plane_damage(_source)

# ===========================================================
# ANIMATION
# ===========================================================

func _reset_trick_state() -> void:
	# SUMMARY: Clear transient trick timers to avoid cross-state bleed.
	_trick_retrigger_timer = 0.0
	_air_trick_animation_gesture_latched = false
	_air_trick_animation_last_command = &""
	_manual_airborne_trick_input_active = false
	_manual_airborne_trick_input_command = &""
	if _trick_detector != null:
		_trick_detector.reset()
	if _trick_system != null:
		_trick_system.start_airborne_segment()

func _update_trick_detection(delta: float) -> void:
	if _trick_detector == null:
		return
	if is_parkour_active():
		_trick_detector.reset()
		return
	
	if _rail_active:
		_update_rail_tricks(delta)
		return

	if attached:
		return
	if rolling or _current_action_id == &"roll":
		return
	if _spring_align_timer > 0.0 or _spline_active or _rail_active:
		return
	if is_current_action_flight():
		return

	if model_root == null:
		push_warning("_update_trick_detection: model_root missing")
		return

	var current_time: float = Engine.get_process_frames() / 60.0
	var model_basis: Basis = model_root.global_transform.basis
	var torque_yaw_delta: float = 0.0
	if airborne_torque_enabled and _air_torque_segment_allowed:
		var torque_velocity_local: Vector3 = model_basis.inverse() * _air_torque_angular_velocity
		torque_yaw_delta = torque_velocity_local.y * maxf(airborne_torque_gain, 0.0) * maxf(delta, 0.0)
	_trick_detector.update_trick_detection(model_basis, current_time, torque_yaw_delta)

func _finalize_trick_landing() -> void:
	if _trick_system == null:
		push_warning("_finalize_trick_landing: trick system missing")
		return

	if not _trick_system.combo_system_enabled:
		_trick_system.end_airborne_segment()
		_stomp_landing_flag = false
		return

	_stomp_landing_flag = false

func get_combo_barrier_blast_gain_multiplier() -> float:
	var score_ratio: float = _get_active_combo_score_ratio(combo_barrier_blast_score_target)
	return lerpf(1.0, maxf(combo_barrier_blast_max_gain_multiplier, 1.0), score_ratio)

func get_combo_acceleration_multiplier() -> float:
	var score_ratio: float = _get_active_combo_score_ratio(combo_movement_bonus_score_target)
	return lerpf(1.0, maxf(combo_acceleration_max_multiplier, 1.0), score_ratio)

func get_combo_landing_roll_effectiveness_multiplier() -> float:
	var score_ratio: float = _get_active_combo_score_ratio(combo_movement_bonus_score_target)
	return lerpf(
		1.0,
		maxf(combo_landing_roll_max_effectiveness_multiplier, 1.0),
		score_ratio
	)


func get_ground_hit_speed() -> float:
	return _last_ground_hit_speed


func get_ground_hit_strength() -> float:
	return _last_ground_hit_strength


func is_ground_hit_hard() -> bool:
	return _landing_timer > 0.0 and _last_ground_hit_strength >= ground_hit_hard_threshold

func _get_active_combo_score_ratio(score_target: float) -> float:
	if _is_buddy_actor() or _trick_system == null or not _trick_system.combo_system_enabled:
		return 0.0
	if _trick_system.current_air_tricks.is_empty():
		return 0.0
	return clampf(_trick_system.total_score / maxf(score_target, 1.0), 0.0, 1.0)

func _on_player_hurt() -> void:
	_ensure_modules()
	_combat_module._on_player_hurt()

func set_death_state(dead: bool) -> void:
	_ensure_modules()
	_combat_module.set_death_state(dead)

func reset_trick_staleness() -> void:
	if _trick_system != null:
		_trick_system.reset_air_trick_staleness()

func reset_score() -> void:
	score = 0
	var h: Node = _get_hud_node()
	if h != null and h.has_method("set_score"):
		h.call("set_score", score)

func _is_anim_in_trick_state() -> bool:
	# SUMMARY: True when the AnimationTree is in a trick state or command state.
	if anim_state == null:
		return false
	
	# If we are currently transitioning, anim_state.get_current_node() might return 
	# the 'from' node. Check if we have a travel path to a trick.
	var path = anim_state.get_travel_path()
	if not path.is_empty():
		for p in path:
			if str(p).begins_with("Trick_"):
				return true

	var current: StringName = anim_state.get_current_node()
	if current == &"TRICKS":
		return true
	if str(current).begins_with("Trick_"):
		return true
	return false


func _get_trick_cmd_from_angular_velocity(
	omega_world: Vector3,
	minimum_speed_deg: float = -1.0
) -> StringName:
	# SUMMARY: Choose the trick command based on dominant torque axis.
	# NOTES:
	# - omega_world is in world space; convert to model space for pitch/yaw/roll.
	# - The model forward axis is -basis.z, consistent with _model_forward.
	# - Sign mapping uses right-hand rotation about local axes.
	var basis: Basis = global_transform.basis
	if model_root != null:
		basis = model_root.global_transform.basis
	basis = basis.orthonormalized()

	var right: Vector3 = basis.x
	if right.length() < 0.001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var up: Vector3 = basis.y
	if up.length() < 0.001:
		up = _get_gravity_up()
	else:
		up = up.normalized()

	var forward: Vector3 = -basis.z
	if forward.length() < 0.001:
		forward = _model_forward
	if forward.length() < 0.001:
		forward = -Vector3.FORWARD
	forward = forward.normalized()

	var pitch_rate: float = omega_world.dot(right)
	var yaw_rate: float = omega_world.dot(up)
	var roll_rate: float = omega_world.dot(forward)

	var abs_p: float = abs(pitch_rate)
	var abs_y: float = abs(yaw_rate)
	var abs_r: float = abs(roll_rate)

	var best_rate: float = pitch_rate
	var best_axis: int = 0 # 0=Pitch, 1=Yaw, 2=Roll

	# Diagonal detection for animation: if Pitch and Yaw are similar, use Roll animation.
	var is_diagonal_torque: bool = false
	var avg_rate: float = 0.0
	if abs_p > 0.1 and abs_y > 0.1:
		var diff: float = abs(abs_p - abs_y)
		avg_rate = (abs_p + abs_y) * 0.5
		if diff < avg_rate: # More same than different
			is_diagonal_torque = true

	if is_diagonal_torque:
		best_axis = 2
		# Use the sign of yaw_rate to determine roll direction for diagonal torque
		best_rate = avg_rate if yaw_rate > 0 else -avg_rate
	else:
		if abs_y > abs(best_rate):
			best_rate = yaw_rate
			best_axis = 1
		if abs_r > abs(best_rate):
			best_rate = roll_rate
			best_axis = 2

	var min_deg: float = trick_torque_min_speed_deg
	if minimum_speed_deg >= 0.0:
		min_deg = minimum_speed_deg
	min_deg = maxf(min_deg, 0.0)
	if min_deg > 0.0:
		var min_rad: float = deg_to_rad(min_deg)
		if abs(best_rate) < min_rad:
			return &""
	else:
		if abs(best_rate) <= 0.0001:
			return &""

	var cmd: StringName = &""
	if best_axis == 0:
		# Pitch: positive = pitch back, negative = pitch forward.
		if best_rate < 0.0:
		#	cmd = &"CMD_TRICK_PITCH_FORWARD"
			cmd = &"Trick_Pitch_Forward"
		else:
		#	cmd = &"CMD_TRICK_PITCH_BACK"
			cmd = &"Trick_Pitch_Back"
	elif best_axis == 1:
		# Yaw: positive = yaw left, negative = yaw right (forward is -Z).
		if best_rate < 0.0:
		#	cmd = &"CMD_TRICK_YAW_RIGHT"
			cmd = &"Trick_Yaw_Right"
		else:
		#	cmd = &"CMD_TRICK_YAW_LEFT"
			cmd = &"Trick_Yaw_Left"
	else:
		# Roll: positive = roll right, negative = roll left (forward is -Z).
		if best_rate < 0.0:
		#	cmd = &"CMD_TRICK_ROLL_LEFT"
			cmd = &"Trick_Roll_Left"
		else:
		#	cmd = &"CMD_TRICK_ROLL_RIGHT"
			cmd = &"Trick_Roll_Right"

	return cmd


func _update_air_trick_animation() -> void:
	# SUMMARY: Trigger trick animations from airborne torque when rotation is fast enough.
	# NOTES:
	# - Only runs on local authority to avoid double-net triggers.
	# - Blocks while in other forced alignment states (rails/splines/springs).
	if not _network_is_local_authority():
		return
	if anim_state == null:
		return
	if _pending_anim_command != &"":
		return
	if attached:
		return
	if rolling or _current_action_id == &"roll":
		return
	if is_parkour_active():
		return
	if (
		(_spring_align_timer > 0.0 and not _external_airborne_torque_active)
		or (_spline_active and not _external_airborne_torque_active)
		or _rail_active
		or _rail_switch_active
		or _bounce_state != BounceState.NONE
	):
		return
	if is_current_action_flight():
		return
	if _homing_active:
		return
	
	var tricks_allowed: bool = trick_animations_enabled
	if (_manual_airborne_torque_active or _external_airborne_torque_active) and manual_airborne_torque_tricks_enabled:
		tricks_allowed = true
		
	if not tricks_allowed:
		return
	if not airborne_torque_enabled:
		return
	if not _air_torque_segment_allowed:
		return
	var omega_world: Vector3 = _air_torque_angular_velocity
	var manual_input_command: StringName = _manual_airborne_trick_input_command
	if _manual_airborne_trick_input_active and manual_input_command != &"":
		var direction_changed: bool = (
			_air_trick_animation_last_command != &""
			and manual_input_command != _air_trick_animation_last_command
		)
		var trick_animation_active: bool = _is_anim_in_trick_state()
		if _air_trick_animation_last_command == &"":
			if _get_trick_cmd_from_angular_velocity(omega_world) == &"":
				return
		elif not direction_changed:
			if trick_animation_active:
				return
			if _trick_retrigger_timer > 0.0:
				return
		_trigger_anim_command(manual_input_command, true, trick_anim_crossfade)
		_air_trick_animation_last_command = manual_input_command
		_air_trick_animation_gesture_latched = true
		_trick_retrigger_timer = maxf(trick_retrigger_delay, 0.0)
		return

	if omega_world.length() < 0.0001:
		_air_trick_animation_gesture_latched = false
		_air_trick_animation_last_command = &""
		return

	if _air_trick_animation_gesture_latched:
		var trigger_speed_deg: float = maxf(trick_torque_min_speed_deg, 0.0)
		var rearm_speed_deg: float = maxf(trick_torque_animation_rearm_speed_deg, 0.0)
		if trigger_speed_deg > 0.0:
			rearm_speed_deg = minf(rearm_speed_deg, trigger_speed_deg * 0.9)
		var rearm_speed_rad: float = maxf(deg_to_rad(rearm_speed_deg), 0.0001)
		if omega_world.length() > rearm_speed_rad:
			return
		_air_trick_animation_gesture_latched = false
		_air_trick_animation_last_command = &""
	if _trick_retrigger_timer > 0.0:
		return

	var cmd: StringName = &""
	if _external_airborne_torque_active:
		cmd = _external_airborne_trick_command
	if cmd == &"":
		cmd = _get_trick_cmd_from_angular_velocity(omega_world)
	if cmd == &"":
		return

	# Allow interruption of an existing trick if the new command is different.
	# If it's the same trick, we skip to avoid jittering the animation loop.
	var current_trick: StringName = anim_state.get_current_node()
	if current_trick == &"TRICKS" and anim_tree != null:
		var trick_playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/StateMachine/TRICKS/playback") as AnimationNodeStateMachinePlayback
		if trick_playback != null:
			current_trick = trick_playback.get_current_node()
	if _is_anim_in_trick_state() and current_trick == cmd:
		_air_trick_animation_gesture_latched = true
		_air_trick_animation_last_command = cmd
		return

	_trigger_anim_command(cmd, true, trick_anim_crossfade)
	_air_trick_animation_gesture_latched = true
	_air_trick_animation_last_command = cmd

	var delay: float = max(trick_retrigger_delay, 0.0)
	if delay > 0.0:
		_trick_retrigger_timer = delay

func _get_lateral_speed_for_anim() -> float:
	# Single canonical definition of "movement speed" for animation.
	# Uses the last physics-up to strip vertical component and return
	# ground/loop lateral speed in units/sec.
	var up: Vector3 = _physics_up_last.normalized()
	if up.length() < 0.001:
		up = _get_gravity_up()

	var v: Vector3 = velocity
	var vertical: float = v.dot(up)
	var lateral: Vector3 = v - up * vertical
	return lateral.length()


func should_play_moving_landing_animation() -> bool:
	if _landing_animation_pending:
		return _landing_animation_moving
	return _move_input.length_squared() > 0.000001 or _get_lateral_speed_for_anim() >= 0.5

func _update_animation(delta: float) -> void:
	_ensure_modules()
	if _anim_module != null:
		_anim_module._update_animation(delta)
	_apply_anim_command()
	_update_carry_animation(delta)
	_update_pending_carry_put_down_release()
	_update_pending_carry_throw_release()
	_update_carry_command_animation_exit()

func _trigger_anim_command(cmd: StringName, send_net: bool = true, crossfade: float = -1.0, force: bool = false) -> void:
	var allow: bool = true
	if not force and cmd != &"CMD_SPRING" and _pending_anim_command == &"CMD_SPRING":
		allow = false
	if not force and has_action_landing_animation_override():
		var command_target: Dictionary = _resolve_animation_command_target(cmd, _get_main_animation_state_machine())
		var target_machine: StringName = command_target.get("machine", &"") as StringName
		if cmd == &"CMD_SKYDIVE" or target_machine == &"TRICKS" or target_machine == &"SKYDIVE_MACHINE":
			allow = false
	if not allow:
		return
	_pending_anim_command = cmd
	_pending_anim_crossfade = crossfade
	if send_net and _network_is_active() and network_replication_enabled and is_multiplayer_authority():
		rpc("_net_anim_command", cmd)


func _trigger_anim_command_immediate(cmd: StringName, send_net: bool = true) -> void:
	_trigger_anim_command(cmd, send_net, -1.0, true)
	_apply_anim_command(true)


func play_action_command_if_exists(action_name: StringName, send_net: bool = true) -> bool:
	if action_name == &"":
		return false
	var cmd: StringName = StringName("CMD_%s" % String(action_name).to_upper())
	if anim_tree == null:
		return false
	var sm: AnimationNodeStateMachine = null
	var root: AnimationNode = anim_tree.tree_root
	if root is AnimationNodeStateMachine:
		sm = root as AnimationNodeStateMachine
	elif root is AnimationNodeBlendTree:
		var bt: AnimationNodeBlendTree = root as AnimationNodeBlendTree
		var sm_node_name: String = PlayerAnimation.SM_BASE.replace("parameters/", "")
		if bt.has_node(sm_node_name):
			sm = bt.get_node(sm_node_name) as AnimationNodeStateMachine
	if sm != null and not _resolve_animation_command_target(cmd, sm).is_empty():
		_trigger_anim_command(cmd, send_net)
		return true
	if action_name == &"homing" and sm != null and sm.has_node(&"JUMPDASH"):
		_trigger_anim_command(&"JUMPDASH", send_net)
		return true
	if not _missing_anim_command_logged.has(cmd):
		_missing_anim_command_logged[cmd] = true
		push_warning("Missing AnimationTree state '%s'" % String(cmd))
	return false


func _resolve_animation_command_target(cmd: StringName, sm: AnimationNodeStateMachine) -> Dictionary:
	if sm == null:
		return {}
	if sm.has_node(cmd):
		return {"machine": &"", "state": cmd}
	var aliases: Dictionary = {
		&"CMD_BOUNCE": &"BOUNCE",
		&"CMD_RAIL": &"RAIL",
		&"CMD_SKYDIVE": &"SKYDIVE_MACHINE",
		&"CMD_SPINDASH": &"SPINDASH",
		&"CMD_SPINDASHRAIL": &"SPINDASHRAIL",
		&"CMD_SPIN_KICK": &"SPINKICK",
		&"CMD_TORNADO_KICK": &"TORNADOKICK",
		&"CMD_LEDGE_GRAB": &"LEDGE_GRAB",
		&"CMD_TRICK_PITCH_FORWARD": &"Trick_Pitch_Forward",
		&"CMD_TRICK_PITCH_BACK": &"Trick_Pitch_Back",
		&"CMD_TRICK_YAW_LEFT": &"Trick_Yaw_Left",
		&"CMD_TRICK_YAW_RIGHT": &"Trick_Yaw_Right",
		&"CMD_TRICK_ROLL_LEFT": &"Trick_Roll_Left",
		&"CMD_TRICK_ROLL_RIGHT": &"Trick_Roll_Right",
	}
	var state: StringName = aliases.get(cmd, cmd) as StringName
	if sm.has_node(state):
		return {"machine": &"", "state": state}
	for machine_name: StringName in sm.get_node_list():
		var machine: AnimationNodeStateMachine = sm.get_node(machine_name) as AnimationNodeStateMachine
		if machine != null and machine.has_node(state):
			return {"machine": machine_name, "state": state}
	return {}


func _get_animation_group_current_node(group_name: String) -> StringName:
	if anim_tree == null:
		return &""
	var playback_path: String = "%s/%s/playback" % [PlayerAnimation.SM_BASE, group_name]
	var playback: AnimationNodeStateMachinePlayback = anim_tree.get(playback_path) as AnimationNodeStateMachinePlayback
	if playback == null:
		return &""
	return playback.get_current_node()


func _is_animation_group_current_finished(group_name: String, empty_is_finished: bool = true) -> bool:
	if anim_tree == null:
		return true
	var playback_path: String = "%s/%s/playback" % [PlayerAnimation.SM_BASE, group_name]
	var playback: AnimationNodeStateMachinePlayback = anim_tree.get(playback_path) as AnimationNodeStateMachinePlayback
	if playback == null:
		return empty_is_finished
	var length: float = playback.get_current_length()
	if length <= 0.001:
		return empty_is_finished
	return playback.get_current_play_position() >= length - 0.02


func request_skydive_animation_state(state_name: StringName) -> void:
	if state_name == &"Skydive_Enter" or state_name == &"Skydive_Dive" or state_name == &"Skydive_Glide_To_Dive":
		_skydive_anim_phase = SKYDIVE_ANIM_DIVE
		_skydive_anim_exit_timer = 0.0
	elif state_name == &"Skydive_Dive_To_Glide" or state_name == &"Skydive_Glide":
		_skydive_anim_phase = SKYDIVE_ANIM_GLIDE
		_skydive_anim_exit_timer = 0.0
	elif state_name == &"Skydive_Cancel":
		_skydive_anim_phase = SKYDIVE_ANIM_CANCEL
		_skydive_anim_exit_timer = 2.0
	elif state_name == &"Skydive_Exit":
		_skydive_anim_phase = SKYDIVE_ANIM_EXIT
		_skydive_anim_exit_timer = 2.0


func _is_skydive_anim_active() -> bool:
	return _current_action_id == &"skydive" or not _is_skydive_anim_finished()


func _is_skydive_anim_diving() -> bool:
	return _current_action_id == &"skydive" and _skydive_anim_phase == SKYDIVE_ANIM_DIVE


func _is_skydive_anim_gliding() -> bool:
	return _current_action_id == &"skydive" and _skydive_anim_phase == SKYDIVE_ANIM_GLIDE


func _is_skydive_anim_canceling() -> bool:
	return _skydive_anim_phase == SKYDIVE_ANIM_CANCEL and not _is_skydive_terminal_complete(&"Skydive_Cancel")


func _is_skydive_anim_exiting() -> bool:
	return _skydive_anim_phase == SKYDIVE_ANIM_EXIT and not _is_skydive_terminal_complete(&"Skydive_Exit")


func _is_skydive_anim_cancel_complete() -> bool:
	return _skydive_anim_phase == SKYDIVE_ANIM_CANCEL and _is_skydive_terminal_complete(&"Skydive_Cancel")


func _is_skydive_anim_exit_complete() -> bool:
	return _skydive_anim_phase == SKYDIVE_ANIM_EXIT and _is_skydive_terminal_complete(&"Skydive_Exit")


func _is_skydive_anim_finished() -> bool:
	if _skydive_anim_phase == SKYDIVE_ANIM_NONE:
		return true
	if _skydive_anim_phase == SKYDIVE_ANIM_CANCEL:
		return _is_skydive_terminal_complete(&"Skydive_Cancel")
	if _skydive_anim_phase == SKYDIVE_ANIM_EXIT:
		return _is_skydive_terminal_complete(&"Skydive_Exit")
	return false


func _is_skydive_terminal_complete(state_name: StringName) -> bool:
	if _current_action_id == &"skydive":
		return false
	if anim_tree == null:
		return _skydive_anim_exit_timer <= 0.0
	var skydive_state: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/StateMachine/SKYDIVE_MACHINE/playback") as AnimationNodeStateMachinePlayback
	if skydive_state == null:
		return _skydive_anim_exit_timer <= 0.0
	var current_node: StringName = skydive_state.get_current_node()
	if current_node == &"End":
		return true
	if current_node != state_name:
		return false
	var length: float = skydive_state.get_current_length()
	if length <= 0.001:
		return _skydive_anim_exit_timer <= 0.0
	return skydive_state.get_current_play_position() >= length - 0.02


func _apply_anim_command(force_direct: bool = false) -> void:
	if _pending_anim_command == &"":
		return
	if anim_state == null:
		return
	
	var cmd: StringName = _pending_anim_command
	var xfade: float = _pending_anim_crossfade
	for action in _actions:
		if action != null and is_instance_valid(action) and action.try_handle_animation_command(cmd):
			_pending_anim_command = &""
			_pending_anim_crossfade = -1.0
			return
	var sm: AnimationNodeStateMachine = _get_main_animation_state_machine()
	var command_target: Dictionary = _resolve_animation_command_target(cmd, sm)
	if not command_target.is_empty():
		var requested_command: StringName = cmd
		var machine_name: StringName = command_target["machine"]
		cmd = command_target["state"]
		if machine_name != &"":
			var force_restart: bool = has_action_landing_animation_override()
			if force_restart or anim_state.get_current_node() != machine_name:
				anim_state.start(machine_name, true)
			var playback_path: String = "%s/%s/playback" % [PlayerAnimation.SM_BASE, machine_name]
			var nested_playback: AnimationNodeStateMachinePlayback = anim_tree.get(playback_path) as AnimationNodeStateMachinePlayback
			if nested_playback != null:
				var current_nested: StringName = nested_playback.get_current_node()
				var can_crossfade_trick: bool = (
					machine_name == &"TRICKS"
					and anim_state.get_current_node() == &"TRICKS"
					and String(current_nested).begins_with("Trick_")
					and current_nested != cmd
				)
				if can_crossfade_trick:
					var trick_machine: AnimationNodeStateMachine = sm.get_node(machine_name) as AnimationNodeStateMachine
					var trick_fade: float = maxf(xfade if xfade >= 0.0 else trick_anim_crossfade, 0.0)
					var trick_transition: AnimationNodeStateMachineTransition = null
					for transition_index: int in trick_machine.get_transition_count():
						if trick_machine.get_transition_from(transition_index) == current_nested and trick_machine.get_transition_to(transition_index) == cmd:
							trick_transition = trick_machine.get_transition(transition_index)
							break
					if trick_transition == null:
						trick_transition = AnimationNodeStateMachineTransition.new()
						trick_transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
						trick_transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
						trick_machine.add_transition(current_nested, cmd, trick_transition)
					trick_transition.xfade_time = trick_fade
					nested_playback.travel(cmd)
				else:
					nested_playback.start(cmd, true)
			_pending_anim_command = &""
			_pending_anim_crossfade = -1.0
			return
		if cmd != requested_command:
			anim_state.start(cmd)
			_pending_anim_command = &""
			_pending_anim_crossfade = -1.0
			return
	if force_direct and sm != null and sm.has_node(cmd):
		anim_state.start(cmd, true)
		_pending_anim_command = &""
		_pending_anim_crossfade = -1.0
		return
	
	if (cmd == &"CMD_SPRING" or cmd == &"CMD_HOMING" or cmd == &"JUMPDASH" or cmd == &"ROLL") and anim_state.has_method("start"):
		anim_state.start(cmd)
	else:
		if xfade >= 0.0:
			# In Godot 4 State Machines, crossfade time is a property of the Transition resource.
			# We must find the actual StateMachine resource to modify its transitions.
			if sm != null:
				var from = anim_state.get_current_node()
				var found_transition: bool = false
				
				# Update existing transitions leading to the target command.
				for i in sm.get_transition_count():
					if sm.get_transition_to(i) == cmd:
						if from == &"" or sm.get_transition_from(i) == from:
							var trans = sm.get_transition(i)
							if trans:
								trans.xfade_time = xfade
								found_transition = true
				
				# If no transition exists, travel() will snap immediately.
				# We can try to add a temporary one from the current state if it's missing.
				if not found_transition and from != &"" and from != cmd:
					var new_trans = AnimationNodeStateMachineTransition.new()
					new_trans.xfade_time = xfade
					new_trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
					new_trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
					sm.add_transition(from, cmd, new_trans)
		
		anim_state.travel(cmd)
	
	_pending_anim_command = &""
	_pending_anim_crossfade = -1.0
	

func _update_carry_animation(delta: float) -> void:
	_ensure_modules()
	_carry_module._update_carry_animation(delta)

func _force_carry_overlay_blend_visible() -> void:
	_ensure_modules()
	_carry_module._force_carry_overlay_blend_visible()

func _request_carry_pickup_animation() -> void:
	_ensure_modules()
	_carry_module._request_carry_pickup_animation()

func _initialize_carry_overlay_animation() -> void:
	_ensure_modules()
	_carry_module._initialize_carry_overlay_animation()

func _update_carry_overlay_state() -> void:
	_ensure_modules()
	_carry_module._update_carry_overlay_state()

func _play_carry_overlay_state(state_name: StringName) -> bool:
	_ensure_modules()
	return _carry_module._play_carry_overlay_state(state_name)

func _configure_carry_overlay_filter() -> void:
	_ensure_modules()
	_carry_module._configure_carry_overlay_filter()

func _get_blend_tree_node_name_from_parameter(parameter_path: String) -> StringName:
	_ensure_modules()
	return _carry_module._get_blend_tree_node_name_from_parameter(parameter_path)

func is_carry_animation_locked() -> bool:
	_ensure_modules()
	return _carry_module.is_carry_animation_locked()

func _request_anim_oneshot(parameter_path: String) -> void:
	_ensure_modules()
	_carry_module._request_anim_oneshot(parameter_path)

func _update_pending_carry_put_down_release() -> void:
	_ensure_modules()
	_carry_module._update_pending_carry_put_down_release()

func _update_pending_carry_throw_release() -> void:
	_ensure_modules()
	_carry_module._update_pending_carry_throw_release()

func _update_carry_command_animation_exit() -> void:
	_ensure_modules()
	_carry_module._update_carry_command_animation_exit()

func _is_current_anim_state_finished(exit_margin: float) -> bool:
	_ensure_modules()
	return _carry_module._is_current_anim_state_finished(exit_margin)

func _is_anim_playback_finished(playback: AnimationNodeStateMachinePlayback, exit_margin: float) -> bool:
	_ensure_modules()
	return _carry_module._is_anim_playback_finished(playback, exit_margin)

func _travel_to_carry_animation_return_state(crossfade: float = 0.0) -> void:
	_ensure_modules()
	_carry_module._travel_to_carry_animation_return_state(crossfade)

func _travel_anim_state_with_crossfade(target_state: StringName, crossfade: float) -> void:
	_ensure_modules()
	_carry_module._travel_anim_state_with_crossfade(target_state, crossfade)

func _clear_pending_carry_throw() -> void:
	_ensure_modules()
	_carry_module._clear_pending_carry_throw()

func _is_anim_traveling_to(state_name: StringName) -> bool:
	_ensure_modules()
	return _carry_module._is_anim_traveling_to(state_name)

func _safe_set_anim_param(path: String, value) -> void:
	_ensure_modules()
	if _anim_module != null:
		_anim_module._safe_set_anim_param(path, value)


func _update_locomotion_anim(delta: float) -> void:
	_ensure_modules()
	if _anim_module != null:
		_anim_module._update_locomotion_anim(delta)

func _get_turn_amount_for_anim() -> float:
	_ensure_modules()
	if _anim_module != null:
		return _anim_module._get_turn_amount_for_anim()
	return 0.0

func _set_anim_bool_param(rel_path: String, value: bool) -> void:
	_ensure_modules()
	if _anim_module != null:
		_anim_module._set_anim_bool_param(rel_path, value)

func set_next_foot_right() -> void:
	_ensure_modules()
	if _anim_module != null:
		_anim_module.set_next_foot_right()

func set_next_foot_left() -> void:
	_ensure_modules()
	if _anim_module != null:
		_anim_module.set_next_foot_left()

# Called from the walk animation via Call Method track
func request_walk_stop() -> void:
	_ensure_modules()
	if _anim_module != null:
		_anim_module.request_walk_stop()

# ===========================================================
# DEBUG
# ===========================================================
func _debug_inputs(physics_up: Vector3) -> void:
	_ensure_modules()
	_debug_module._debug_inputs(physics_up)

func _debug_draw() -> void:
	_ensure_modules()
	_debug_module._debug_draw()

func _debug_draw_drift_guides(origin: Vector3, up: Vector3) -> void:
	_ensure_modules()
	_debug_module._debug_draw_drift_guides(origin, up)

func _debug_draw_wall_input_projection(origin: Vector3, up: Vector3) -> void:
	_ensure_modules()
	_debug_module._debug_draw_wall_input_projection(origin, up)

func _format_debug_columns(raw_text: String) -> String:
	_ensure_modules()
	return _debug_module._format_debug_columns(raw_text)

func _debug_draw_control_anchor() -> void:
	_ensure_modules()
	_debug_module._debug_draw_control_anchor()

func _debug_anim_tree_params() -> void:
	_ensure_modules()
	_debug_module._debug_anim_tree_params()

func _anim_param_exists(prop_path: String) -> bool:
	_ensure_modules()
	if _anim_module != null:
		return _anim_module._anim_param_exists(prop_path)
	return false

func _dump_animtree_params() -> void:
	_ensure_modules()
	_debug_module._dump_animtree_params()

# ===========================================================
# AUDIO
# ===========================================================

func _play_random_sfx_from_list(
	player: AudioStreamPlayer3D,
	sounds: Array[AudioStream],
	last_index: int,
	avoid_repeat: bool = true
) -> int:
	_ensure_modules()
	if _audio_module != null:
		return _audio_module._play_random_sfx_from_list(player, sounds, last_index, avoid_repeat)
	return last_index


func get_dialogue_player() -> AudioStreamPlayer3D:
	if dialogue_player and is_instance_valid(dialogue_player):
		return dialogue_player
	var found: Node = find_child("Dialogue_Player", true, false)
	if found is AudioStreamPlayer3D:
		dialogue_player = found as AudioStreamPlayer3D
	return dialogue_player


func play_voice_clips(
	clips: Array[AudioStream],
	chance: float = 1.0,
	priority: int = PlayerAudio.VOICE_PRIORITY_ACTION,
	queue_if_blocked: bool = false,
	allow_non_authority: bool = false
) -> void:
	_ensure_modules()
	if _audio_module:
		_audio_module.play_voice_clips(clips, chance, priority, queue_if_blocked, allow_non_authority)


func play_emote_voice(emote_id: StringName) -> bool:
	_ensure_modules()
	return _audio_module.play_emote_voice(emote_id)


func play_voice_event(event_id: StringName, allow_non_authority: bool = false) -> void:
	match event_id:
		&"wait":
			play_voice_clips(voice_wait_clips, voice_wait_chance, PlayerAudio.VOICE_PRIORITY_IDLE, false, allow_non_authority)
		&"hurt":
			play_voice_clips(voice_hurt_clips, voice_hurt_chance, PlayerAudio.VOICE_PRIORITY_HURT, false, allow_non_authority)
		&"death":
			play_voice_clips(voice_death_clips, voice_death_chance, PlayerAudio.VOICE_PRIORITY_HURT, false, allow_non_authority)
		&"pit":
			play_voice_clips(voice_pit_clips, voice_pit_chance, PlayerAudio.VOICE_PRIORITY_HURT, false, allow_non_authority)
		&"exhausted_flight":
			play_voice_clips(voice_exhausted_flight_clips, voice_exhausted_flight_chance, PlayerAudio.VOICE_PRIORITY_ACTION, false, allow_non_authority)
		&"drift_end":
			play_voice_clips(voice_drift_end_clips, voice_drift_end_chance, PlayerAudio.VOICE_PRIORITY_ACTION, false, allow_non_authority)
		&"carry_throw":
			play_voice_clips(voice_carry_throw_clips, voice_carry_throw_chance, PlayerAudio.VOICE_PRIORITY_ACTION, false, allow_non_authority)
		&"race_start":
			play_voice_clips(voice_race_start_clips, voice_race_start_chance, PlayerAudio.VOICE_PRIORITY_ACTION, false, allow_non_authority)
		&"finish_line":
			play_voice_clips(voice_finish_line_clips, voice_finish_line_chance, PlayerAudio.VOICE_PRIORITY_ACTION, false, allow_non_authority)
		&"race_end":
			play_voice_clips(voice_race_end_clips, voice_race_end_chance, PlayerAudio.VOICE_PRIORITY_DIALOGUE, false, allow_non_authority)


func play_wait_voice() -> void:
	play_voice_event(&"wait")


func play_landing_combo_voice(final_score: float) -> void:
	if final_score <= 0.0:
		return
	var clips: Array[AudioStream] = _get_landing_combo_voice_clips(final_score)
	play_voice_clips(clips, voice_landing_combo_chance, PlayerAudio.VOICE_PRIORITY_DIALOGUE)


func _get_landing_combo_voice_clips(final_score: float) -> Array[AudioStream]:
	var profile: PlayerCharacterVisualProfile = character_visual_profile
	var rating: Dictionary = {}
	if profile:
		rating = profile.get_combo_rating(final_score)
	if String(rating.get("text", "")).is_empty():
		rating = PlayerCharacterVisualProfile.new().get_combo_rating(final_score)
	var tier: int = clampi(int(rating.get("tier", 0)), 0, 9)
	match tier:
		0: return voice_landing_good_clips
		1: return voice_landing_great_clips
		2: return voice_landing_nice_clips
		3: return voice_landing_jammin_clips
		4: return voice_landing_cool_clips
		5: return voice_landing_radical_clips
		6: return voice_landing_tight_clips
		7: return voice_landing_awesome_clips
		8: return voice_landing_extreme_clips
		_: return voice_landing_perfect_clips


func play_trick_voice(trick_type: int) -> void:
	match trick_type:
		TrickSystem.TrickType.BACKFLIP:
			play_voice_clips(voice_trick_backflip_clips, voice_trick_backflip_chance)
		TrickSystem.TrickType.FRONTFLIP:
			play_voice_clips(voice_trick_frontflip_clips, voice_trick_frontflip_chance)
		TrickSystem.TrickType.LEFT_SPIN:
			play_voice_clips(voice_trick_left_spin_clips, voice_trick_left_spin_chance)
		TrickSystem.TrickType.RIGHT_SPIN:
			play_voice_clips(voice_trick_right_spin_clips, voice_trick_right_spin_chance)
		TrickSystem.TrickType.FRONTFLIP_LEFT_SPIN:
			play_voice_clips(voice_trick_frontflip_left_spin_clips, voice_trick_frontflip_left_spin_chance)
		TrickSystem.TrickType.BACKFLIP_LEFT_SPIN:
			play_voice_clips(voice_trick_backflip_left_spin_clips, voice_trick_backflip_left_spin_chance)
		TrickSystem.TrickType.BACKFLIP_RIGHT_SPIN:
			play_voice_clips(voice_trick_backflip_right_spin_clips, voice_trick_backflip_right_spin_chance)
		TrickSystem.TrickType.FRONTFLIP_RIGHT_SPIN:
			play_voice_clips(voice_trick_frontflip_right_spin_clips, voice_trick_frontflip_right_spin_chance)
		TrickSystem.TrickType.RAIL_FORWARD:
			play_voice_clips(voice_trick_rail_forward_clips, voice_trick_rail_forward_chance)
		TrickSystem.TrickType.RAIL_BACKWARD:
			play_voice_clips(voice_trick_rail_backward_clips, voice_trick_rail_backward_chance)
		TrickSystem.TrickType.RAIL_FORWARD_CROUCH, TrickSystem.TrickType.RAIL_FORWARD_CROUCH_FAST:
			play_voice_clips(voice_trick_rail_forward_crouch_clips, voice_trick_rail_forward_crouch_chance)
		TrickSystem.TrickType.RAIL_BACKWARD_CROUCH, TrickSystem.TrickType.RAIL_BACKWARD_CROUCH_FAST:
			play_voice_clips(voice_trick_rail_backward_crouch_clips, voice_trick_rail_backward_crouch_chance)
		TrickSystem.TrickType.BOUNCE_POGO:
			play_voice_clips(voice_trick_bounce_pogo_clips, voice_trick_bounce_pogo_chance)
		TrickSystem.TrickType.STOMP_DAREHOG:
			play_voice_clips(voice_trick_stomp_darehog_clips, voice_trick_stomp_darehog_chance)


# --- Speed-based volume for FOOTSTEPS ONLY ---
func _get_footstep_volume_linear() -> float:
	_ensure_modules()
	if _audio_module != null:
		return _audio_module._get_footstep_volume_linear()
	return 0.0


func play_footstep(foot: StringName = &"", emit_dust: bool = false) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.play_footstep(foot, emit_dust)


func _emit_footstep_dust(foot: StringName = &"") -> void:
	if footstep_dust_scene == null:
		return
	var emitter: Node3D = _get_footstep_dust_emitter(foot)
	if emitter == null:
		return
	var dust: Node = footstep_dust_scene.instantiate()
	if dust == null:
		return
	var parent: Node = get_parent()
	if parent == null:
		parent = self
	parent.add_child(dust)
	if dust is Node3D:
		var dust_node: Node3D = dust as Node3D
		dust_node.top_level = true
		dust_node.global_transform = emitter.global_transform


func _get_footstep_dust_emitter(foot: StringName = &"") -> Node3D:
	var foot_key: String = String(foot).to_lower()
	if foot_key == "left" or foot_key == "l":
		return left_foot_dust_emitter
	if foot_key == "right" or foot_key == "r":
		return right_foot_dust_emitter
	if left_foot_dust_emitter != null:
		return left_foot_dust_emitter
	return right_foot_dust_emitter


func play_landing_sound() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.play_landing_sound()


# --- Jump & jumpdash SFX (fixed volume, NOT speed-scaled) ---

func play_jump_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.play_jump_sfx()


func play_jumpdash_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.play_jumpdash_sfx()

func _start_spindash_loop_sfx(send_net: bool = true) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module._start_spindash_loop_sfx(send_net)

func _stop_spindash_loop_sfx(send_net: bool = true) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module._stop_spindash_loop_sfx(send_net)

func _play_spindash_charge_full_sfx(send_net: bool = true) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module._play_spindash_charge_full_sfx(send_net)

func _play_spindash_release_sfx(send_net: bool = true) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module._play_spindash_release_sfx(send_net)

func _play_sfx(player: AudioStreamPlayer3D) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module._play_sfx(player)

func _play_rail_land_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.play_rail_land_sfx()


func _play_rail_detach_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.play_rail_detach_sfx()


func _update_rail_grind_sfx(delta: float) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.update_rail_grind_audio(abs(_rail_speed), delta)

func _stop_rail_grind_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.stop_rail_grind_audio()

func _update_drift_sfx(delta: float, lateral_speed: float, turn_speed_deg_per_sec: float) -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.update_drift_audio(_drift_active, lateral_speed, turn_speed_deg_per_sec, delta, drift_loop_sound)

func _stop_drift_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.stop_drift_audio()

func _update_engine_sfx(delta: float, tangential_speed: float) -> void:
	_ensure_modules()
	var engine_active: bool = attached \
		and not _is_dead \
		and _current_action_id == &"" \
		and not rolling \
		and not _drift_active \
		and not _is_skidding \
		and not _rail_active \
		and not _rail_switch_active \
		and not _spline_active \
		and _bounce_state == BounceState.NONE
	if _audio_module != null:
		_audio_module.update_engine_audio(engine_active, tangential_speed, delta)

func _stop_engine_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.stop_engine_audio()

func _update_roll_sfx(delta: float, tangential_speed: float) -> void:
	_ensure_modules()
	if _audio_module == null:
		return
	var roll_active: bool = rolling and roll_enabled
	var loop_active: bool = roll_active and attached and not _spindash_charging
	_audio_module.update_roll_audio(roll_active, loop_active, tangential_speed, delta)

func _stop_roll_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.stop_roll_audio()

func _update_skid_sfx(delta: float, lateral_speed: float) -> void:
	_ensure_modules()
	var skid_active: bool = _is_skidding or (state_flags & STATE_SKIDDING) != 0
	if _audio_module != null:
		_audio_module.update_skid_audio(skid_active, lateral_speed, delta)
	_update_skid_dust(skid_active, lateral_speed, delta)

func _stop_skid_sfx() -> void:
	_ensure_modules()
	if _audio_module != null:
		_audio_module.stop_skid_audio()
	_reset_skid_dust()

func _update_skid_dust(skid_active: bool, lateral_speed: float, delta: float) -> void:
	if not skid_active or lateral_speed < max(skid_dust_min_speed, 0.0):
		_reset_skid_dust()
		return
	var interval: float = max(skid_dust_interval, 0.001)
	_skid_dust_timer = max(_skid_dust_timer - delta, 0.0)
	while _skid_dust_timer <= 0.0:
		var foot: StringName = &"left" if _skid_dust_emit_left else &"right"
		_emit_footstep_dust(foot)
		_skid_dust_emit_left = not _skid_dust_emit_left
		_skid_dust_timer += interval

func _reset_skid_dust() -> void:
	_skid_dust_timer = 0.0
	_skid_dust_emit_left = true


# ===========================================================
# EXTERNAL IMPULSES / OBJECT INTERACTION (SPRINGS, ETC)
# ===========================================================
func get_external_pre_collision_velocity() -> Vector3:
	return _pre_slide_velocity


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
	_ensure_modules()
	_external_motion_module.apply_spring_impulse(spring_position, spring_direction, spring_strength, snap_to_center, stop_momentum, additive_mode, min_additive_launch_speed, additive_mirrored_bounce_ratio, max_additive_launch_speed, movement_lock_time, action_lock_time, align_time, spring_basis, clear_move_on_ground, clear_action_on_ground, lock_horizontal_during_align, sideways_gravity_scale, detach_from_ground, align_model_during_spring, preserve_active_flight, flight_time_bonus, downward_trajectory_torque_enabled, downward_trajectory_min_angle_deg, downward_trajectory_align_speed_deg, downward_trajectory_gravity_yaw_enabled, downward_trajectory_gravity_yaw_strength, downward_trajectory_gravity_yaw_safe_angle_deg, downward_trajectory_gravity_yaw_full_angle_deg, downward_trajectory_torque_min_horizontal_speed, downward_trajectory_landing_forward_pitch_enabled)

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
	_ensure_modules()
	return _external_motion_module.configure_spring_trajectory_torque(launch_direction, enabled, minimum_downward_angle_deg, align_speed_deg, gravity_yaw_enabled, gravity_yaw_strength, gravity_yaw_safe_angle_deg, gravity_yaw_full_angle_deg, minimum_horizontal_speed, landing_forward_pitch_enabled)

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
	_ensure_modules()
	return _external_motion_module.start_airborne_trajectory_torque(trajectory_direction, align_speed_deg, gravity_yaw_enabled, gravity_yaw_strength, gravity_yaw_safe_angle_deg, gravity_yaw_full_angle_deg, minimum_horizontal_speed, landing_forward_pitch_enabled)

func stop_airborne_trajectory_torque() -> void:
	_ensure_modules()
	_external_motion_module.stop_airborne_trajectory_torque()

func is_airborne_trajectory_torque_active() -> bool:
	_ensure_modules()
	return _external_motion_module.is_airborne_trajectory_torque_active()

func get_airborne_trajectory_up() -> Vector3:
	_ensure_modules()
	return _external_motion_module.get_airborne_trajectory_up()

func _cancel_spring_trajectory_torque(clear_spring_alignment: bool) -> void:
	_ensure_modules()
	_external_motion_module._cancel_spring_trajectory_torque(clear_spring_alignment)

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
	_ensure_modules()
	_external_motion_module.apply_dash_panel_impulse(panel_origin, panel_dir, strength, stop_momentum, additive_mode, min_additive_launch_speed, movement_lock_time, action_lock_time, align_camera, panel_basis, lock_speed_enabled, lock_speed_value, lock_speed_duration, override_max_speed, max_speed_override, max_speed_override_duration, match_y_position, override_previous_lock_timers)

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
	_ensure_modules()
	_external_motion_module.apply_ramp_impulse(ramp_origin, ramp_forward, ramp_up, forward_speed, up_speed, additive_launch, additive_min_forward_speed, movement_lock_time, action_lock_time, align_camera, hold_forward_time, hold_up_time)

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
	_ensure_modules()
	_external_motion_module.start_spline_spring(
		spline_path,
		speed,
		align_model,
		detach_from_ground,
		allow_input_cancel,
		action_lock_time,
		world_offset,
		animation_command,
		movement_lock_time,
		clear_movement_lock_on_ground,
		clear_action_lock_on_ground
	)

func _update_spline_spring(delta: float) -> void:
	_ensure_modules()
	_external_motion_module._update_spline_spring(delta)

func _build_spline_model_basis(forward_dir: Vector3, up_hint: Vector3) -> Basis:
	_ensure_modules()
	return _external_motion_module._build_spline_model_basis(forward_dir, up_hint)

func _get_rail_tangent_world(curve: Curve3D, distance: float, total_length: float) -> Vector3:
	_ensure_modules()
	return _rail_module._get_rail_tangent_world(curve, distance, total_length)

func _get_rail_tilt(curve: Curve3D, distance: float) -> float:
	_ensure_modules()
	return _rail_module._get_rail_tilt(curve, distance)

func _get_rail_up_vector(curve: Curve3D, rail_dir: Vector3, distance: float) -> Vector3:
	_ensure_modules()
	return _rail_module._get_rail_up_vector(curve, rail_dir, distance)

func _get_rail_input_direction(world_up: Vector3) -> Vector3:
	_ensure_modules()
	return _rail_module._get_rail_input_direction(world_up)

func _get_rail_spindash_input_direction(world_up: Vector3) -> Vector3:
	_ensure_modules()
	return _rail_module._get_rail_spindash_input_direction(world_up)

func _get_rail_spindash_release_sign(rail_dir: Vector3, world_up: Vector3) -> float:
	_ensure_modules()
	return _rail_module._get_rail_spindash_release_sign(rail_dir, world_up)

func _get_rail_switch_side_input(world_up: Vector3 = Vector3.ZERO) -> float:
	_ensure_modules()
	return _rail_module._get_rail_switch_side_input(world_up)

func _rail_sample_path_tangent(path: Path3D, curve: Curve3D, offset: float, lookahead: float) -> Vector3:
	_ensure_modules()
	return _rail_module._rail_sample_path_tangent(path, curve, offset, lookahead)

func _rail_find_closest_offset(path: Path3D, curve: Curve3D, world_point: Vector3) -> float:
	_ensure_modules()
	return _rail_module._rail_find_closest_offset(path, curve, world_point)

func _find_rail_switch_candidate(desired_side: float, world_up: Vector3) -> Dictionary:
	_ensure_modules()
	return _rail_module._find_rail_switch_candidate(desired_side, world_up)

func _update_rail_switch_candidate(world_up: Vector3) -> void:
	_ensure_modules()
	_rail_module._update_rail_switch_candidate(world_up)

func _start_rail_switch(candidate: Dictionary, world_up: Vector3) -> void:
	_ensure_modules()
	_rail_module._start_rail_switch(candidate, world_up)

func _try_start_rail_switch(world_up: Vector3) -> bool:
	_ensure_modules()
	return _rail_module._try_start_rail_switch(world_up)

func _cancel_rail_switch() -> void:
	_ensure_modules()
	_rail_module._cancel_rail_switch()

func _update_rail_switch(delta: float) -> void:
	_ensure_modules()
	_rail_module._update_rail_switch(delta)

func start_rail_grind(params: Dictionary) -> void:
	_ensure_modules()
	var was_rail_active: bool = _rail_active
	_rail_module.start_rail_grind(params)
	if not was_rail_active and _rail_active:
		var rail_trick_type: int = _rail_module.get_rail_trick_type(_rail_module.is_rail_crouch_input_pressed())
		var rail_display_name: String = _trick_system.get_trick_name(rail_trick_type) if _trick_system != null else "Rail Grind"
		register_combo_feat(&"rail_grind", rail_display_name, 150.0, rail_combo_timer_add_seconds)

func can_start_rail_grind() -> bool:
	_ensure_modules()
	return _rail_module.can_start_rail_grind()

func get_rail_surface_up() -> Vector3:
	_ensure_modules()
	return _rail_module.get_rail_surface_up()

func _clear_attack_state_for_rail_landing() -> void:
	_ensure_modules()
	_rail_module._clear_attack_state_for_rail_landing()

func _update_rail_motion(delta: float, world_up: Vector3) -> void:
	_ensure_modules()
	_rail_module._update_rail_motion(delta, world_up)

func _end_rail(jumped: bool, world_up: Vector3) -> void:
	_ensure_modules()
	_rail_module._end_rail(jumped, world_up)

# ===========================================================
# WATER PHYSICS
# ===========================================================

func _on_water_body_entered(body: Node3D) -> void:
	_register_water_volume_entry(body)

func _on_water_body_exited(body: Node3D) -> void:
	_register_water_volume_exit(body)

func _is_water_collider(collider: Node) -> bool:
	_ensure_modules()
	return _water_module.is_water_collider(collider)

func _can_land_on_water_surface(velocity_before: Vector3, normal: Vector3) -> bool:
	_ensure_modules()
	return _water_module.can_land_on_surface(velocity_before, normal)


func _apply_water_surface_landing_speed_penalty(
	velocity_before: Vector3,
	normal: Vector3
) -> Vector3:
	_ensure_modules()
	return _water_module.apply_surface_landing_speed_penalty(velocity_before, normal)

func _apply_water_vertical_speed_slowdown(vertical: float, delta: float) -> float:
	_ensure_modules()
	return _water_module.apply_vertical_speed_slowdown(vertical, delta)

func _update_water_physics_state(delta: float) -> void:
	_ensure_modules()
	_water_module.update_physics_state(delta)

func _get_water_surface_run_normal() -> Vector3:
	_ensure_modules()
	return _water_module.get_surface_run_normal()

func _check_water_surface_min_speed() -> void:
	_ensure_modules()
	_water_module.check_surface_min_speed()

func _can_start_water_surface_running(normal: Vector3) -> bool:
	_ensure_modules()
	return _water_module.can_start_surface_running(normal)

func _start_water_surface_running(normal: Vector3) -> void:
	_ensure_modules()
	_water_module.start_surface_running(normal)

func _drop_from_water_surface(normal: Vector3) -> void:
	_ensure_modules()
	_water_module.drop_from_surface(normal)

func _get_water_surface_normal(area: Area3D) -> Vector3:
	_ensure_modules()
	return _water_module.get_surface_normal(area)

func _get_splash_tier(velocity_value: Vector3, surface_normal: Vector3) -> int:
	_ensure_modules()
	return _water_module.get_splash_tier(velocity_value, surface_normal)

func _play_water_entry_splash() -> void:
	_ensure_modules()
	_water_module.play_entry_splash()

func _play_water_exit_splash() -> void:
	_ensure_modules()
	_water_module.play_exit_splash()

func _play_water_sfx_from_array(sounds: Array[AudioStream], last_index: int) -> int:
	_ensure_modules()
	return _water_module.play_sfx_from_array(sounds, last_index)


func is_active_ring_race() -> bool:
	if not race_active or race_finished:
		return false
	for race: Node in get_tree().get_nodes_in_group("RaceStart"):
		if race.has_method("is_ring_race") and race.call("is_ring_race") and race.get("_active_player") == self:
			return true
	return false


@rpc("authority", "reliable", "call_remote")
func _net_play_voice_clip(stream_path: String, priority: int) -> void:
	_ensure_modules()
	if not _network_module.is_level_present():
		return
	if not stream_path.begins_with("res://") or not ResourceLoader.exists(stream_path):
		return
	var stream: AudioStream = load(stream_path) as AudioStream
	if not stream:
		return
	_audio_module.play_replicated_voice(stream, priority)


func claim_kick_contact(target: Node) -> bool:
	var contacts: KickContactController = get_node_or_null("KickContacts") as KickContactController
	return contacts.claim_target(target) if contacts else true

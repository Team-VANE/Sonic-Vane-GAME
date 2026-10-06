extends RefCounted
class_name PlayerActionCompatibility

# Preserves legacy controller fields while action nodes remain authoritative.
var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func _apply_action_node_settings() -> void:
	var p = _owner
	if p._grounded_action != null:
		p.run_top_speed = p._grounded_action.run_top_speed
		p.walk_top_speed = p._grounded_action.walk_top_speed
		p.decel = p._grounded_action.decel
		p.ground_decel_curve = p._grounded_action.ground_decel_curve
		p.ground_accel_curve = p._grounded_action.ground_accel_curve
		p.walk_ground_accel_curve = p._grounded_action.walk_ground_accel_curve
		p.ground_turn_angle_curve = p._grounded_action.ground_turn_angle_curve
		p.walk_turn_angle_curve = p._grounded_action.walk_turn_angle_curve
		p.ground_turn_sharp_rate_multiplier = p._grounded_action.ground_turn_sharp_rate_multiplier
		p.ground_turn_speed_preservation = p._grounded_action.ground_turn_speed_preservation
		p.ground_brake_decel = p._grounded_action.ground_brake_decel
		p.ground_turn_free_angle_deg = p._grounded_action.ground_turn_free_angle_deg
		p.ground_turn_max_penalty_angle_deg = p._grounded_action.ground_turn_max_penalty_angle_deg
		p.ground_turn_max_penalty_angle_curve = p._grounded_action.ground_turn_max_penalty_angle_curve
		p.ground_turn_free_angle_curve = p._grounded_action.ground_turn_free_angle_curve
		p.ground_turn_min_speed_factor = p._grounded_action.ground_turn_min_speed_factor
		p.slope_downhill_accel = p._grounded_action.slope_downhill_accel
		p.slope_downhill_accel_curve = p._grounded_action.slope_downhill_accel_curve
		p.slope_uphill_decel = p._grounded_action.slope_uphill_decel
		p.slope_uphill_decel_curve = p._grounded_action.slope_uphill_decel_curve
		p.slope_uphill_response_blend_speed = p._grounded_action.slope_uphill_response_blend_speed
		p.slope_gravity_angle_curve = p._grounded_action.slope_gravity_angle_curve
		p.slope_uphill_start_traction_speed = p._grounded_action.slope_uphill_start_traction_speed
		p.slope_uphill_start_accel_ratio = p._grounded_action.slope_uphill_start_accel_ratio
		p.slope_reversal_guard_enabled = p._grounded_action.slope_reversal_guard_enabled
		p.slope_reversal_guard_min_angle_deg = p._grounded_action.slope_reversal_guard_min_angle_deg
		p.slope_reversal_guard_arm_uphill_speed = p._grounded_action.slope_reversal_guard_arm_uphill_speed
		p.slope_reversal_guard_recovery_distance = p._grounded_action.slope_reversal_guard_recovery_distance
		p.slope_reversal_guard_pull_multiplier = p._grounded_action.slope_reversal_guard_pull_multiplier
		p.slope_reversal_guard_momentum_preserve_speed = p._grounded_action.slope_reversal_guard_momentum_preserve_speed
		p.slope_reversal_guard_turn_preservation = p._grounded_action.slope_reversal_guard_turn_preservation
		p.slope_reversal_guard_turn_alignment = p._grounded_action.slope_reversal_guard_turn_alignment
		p.slope_reversal_guard_air_reset_time = p._grounded_action.slope_reversal_guard_air_reset_time
		p.slope_idle_hold_speed = p._grounded_action.slope_idle_hold_speed
		p.slope_static_hold_hysteresis_deg = p._grounded_action.slope_static_hold_hysteresis_deg
		p.slope_slide_resistance = p._grounded_action.slope_slide_resistance
		p.slope_slide_linear_drag = p._grounded_action.slope_slide_linear_drag
		p.slope_slide_quadratic_drag = p._grounded_action.slope_slide_quadratic_drag
		p.slope_downhill_soft_cap_bypass = p._grounded_action.slope_downhill_soft_cap_bypass
		p.slope_downhill_soft_cap_min_alignment = p._grounded_action.slope_downhill_soft_cap_min_alignment
		p.slope_uphill_control_ratio_min_angle_deg = p._grounded_action.slope_uphill_control_ratio_min_angle_deg
		p.slope_uphill_control_ratio_full_angle_deg = p._grounded_action.slope_uphill_control_ratio_full_angle_deg
		p.slope_uphill_control_ratio_curve = p._grounded_action.slope_uphill_control_ratio_curve
		p.slope_uphill_control_accel_adaptation = p._grounded_action.slope_uphill_control_accel_adaptation
		p.slope_uphill_control_limit_full_speed = p._grounded_action.slope_uphill_control_limit_full_speed
		p.slope_uphill_control_limit_release_speed = p._grounded_action.slope_uphill_control_limit_release_speed
		p.slope_slide_start_angle_deg = p._grounded_action.slope_slide_start_angle_deg
		p.slope_slide_accel = p._grounded_action.slope_slide_accel
		p.slope_max_effect_angle_deg = p._grounded_action.slope_max_effect_angle_deg
		p.skid_enter_min_speed = p._grounded_action.skid_enter_min_speed
		p.skid_enter_angle_deg = p._grounded_action.skid_enter_angle_deg
		p.skid_exit_angle_deg = p._grounded_action.skid_exit_angle_deg
		p.skid_exit_min_speed = p._grounded_action.skid_exit_min_speed
		p.skid_decel = p._grounded_action.skid_decel
		p.skid_turn_deg_per_sec = p._grounded_action.skid_turn_deg_per_sec
		p.skid_max_ground_angle_deg = p._grounded_action.skid_max_ground_angle_deg
		p.engine_loop_sound = p._grounded_action.engine_loop_sound
		p.engine_sound_volume_min_speed = p._grounded_action.engine_sound_volume_min_speed
		p.engine_sound_volume_full_speed = p._grounded_action.engine_sound_volume_full_speed
		p.engine_sound_volume_min_db = p._grounded_action.engine_sound_volume_min_db
		p.engine_sound_volume_max_db = p._grounded_action.engine_sound_volume_max_db
		p.engine_sound_pitch_min_speed = p._grounded_action.engine_sound_pitch_min_speed
		p.engine_sound_pitch_full_speed = p._grounded_action.engine_sound_pitch_full_speed
		p.engine_sound_pitch_min = p._grounded_action.engine_sound_pitch_min
		p.engine_sound_pitch_max = p._grounded_action.engine_sound_pitch_max
		p.engine_sound_lerp_speed = p._grounded_action.engine_sound_lerp_speed
		p.engine_sound_fade_in_speed_db = p._grounded_action.engine_sound_fade_in_speed_db
		p.engine_sound_fade_out_speed_db = p._grounded_action.engine_sound_fade_out_speed_db
		p.engine_sound_stop_volume_db = p._grounded_action.engine_sound_stop_volume_db
	if p._roll_action != null:
		p.roll_enabled = p._roll_action.roll_enabled
		p.roll_decel = p._roll_action.roll_decel
		p.roll_linear_drag = p._roll_action.roll_linear_drag
		p.roll_quadratic_drag = p._roll_action.roll_quadratic_drag
		p.roll_air_decel = p._roll_action.roll_air_decel
		p.roll_turn_deg_per_sec = p._roll_action.roll_turn_deg_per_sec
		p.roll_slope_surface_resistance_enabled = p._roll_action.roll_slope_surface_resistance_enabled
		p.roll_air_top_speed_slowdown_enabled = p._roll_action.roll_air_top_speed_slowdown_enabled
		p.roll_top_speed_slowdown_scale = p._roll_action.roll_top_speed_slowdown_scale
		p.roll_downhill_accel_multiplier = p._roll_action.roll_downhill_accel_multiplier
		p.roll_downhill_accel_multiplier_curve = p._roll_action.roll_downhill_accel_multiplier_curve
		p.roll_uphill_decel_multiplier = p._roll_action.roll_uphill_decel_multiplier
		p.roll_uphill_decel_multiplier_curve = p._roll_action.roll_uphill_decel_multiplier_curve
		p.roll_slope_gravity_angle_curve = p._roll_action.roll_slope_gravity_angle_curve
		p.roll_anim_min_scale = p._roll_action.roll_anim_min_scale
		p.roll_anim_max_scale = p._roll_action.roll_anim_max_scale
		p.roll_anim_speed_for_max = p._roll_action.roll_anim_speed_for_max
		p.roll_start_sound = p._roll_action.roll_start_sound
		p.roll_start_volume_db = p._roll_action.roll_start_volume_db
		p.roll_start_pitch_scale = p._roll_action.roll_start_pitch_scale
		p.roll_end_sound = p._roll_action.roll_end_sound
		p.roll_end_volume_db = p._roll_action.roll_end_volume_db
		p.roll_end_pitch_scale = p._roll_action.roll_end_pitch_scale
		p.roll_loop_sound = p._roll_action.roll_loop_sound
		p.roll_loop_volume_min_speed = p._roll_action.roll_loop_volume_min_speed
		p.roll_loop_volume_full_speed = p._roll_action.roll_loop_volume_full_speed
		p.roll_loop_volume_min_db = p._roll_action.roll_loop_volume_min_db
		p.roll_loop_volume_max_db = p._roll_action.roll_loop_volume_max_db
		p.roll_loop_pitch_min_speed = p._roll_action.roll_loop_pitch_min_speed
		p.roll_loop_pitch_full_speed = p._roll_action.roll_loop_pitch_full_speed
		p.roll_loop_pitch_min = p._roll_action.roll_loop_pitch_min
		p.roll_loop_pitch_max = p._roll_action.roll_loop_pitch_max
		p.roll_loop_lerp_speed = p._roll_action.roll_loop_lerp_speed
		p.roll_loop_fade_in_speed_db = p._roll_action.roll_loop_fade_in_speed_db
		p.roll_loop_fade_out_speed_db = p._roll_action.roll_loop_fade_out_speed_db
		p.roll_loop_stop_volume_db = p._roll_action.roll_loop_stop_volume_db
	else:
		p.roll_enabled = false
	if p._spindash_action != null:
		p.spindash_enabled = p._spindash_action.spindash_enabled
		p.spindash_charge_time_max = p._spindash_action.spindash_charge_time_max
		p.spindash_rail_charge_time_max = p._spindash_action.spindash_rail_charge_time_max
		p.spindash_ground_hold_time = p._spindash_action.spindash_ground_hold_time
		p.spindash_min_launch_speed = p._spindash_action.spindash_min_launch_speed
		p.spindash_max_launch_speed = p._spindash_action.spindash_max_launch_speed
		p.spindash_rail_max_launch_speed = p._spindash_action.spindash_rail_max_launch_speed
		p.spindash_preserve_entry_speed_above_max = p._spindash_action.spindash_preserve_entry_speed_above_max
		p.spindash_charge_decel = p._spindash_action.spindash_charge_decel
		p.spindash_charge_decel_unheld = p._spindash_action.spindash_charge_decel_unheld
		p.spindash_charge_stop_speed = p._spindash_action.spindash_charge_stop_speed
		p.spindash_turn_penalty_disable_time = p._spindash_action.spindash_turn_penalty_disable_time
		p.spindash_jump_speed = p._spindash_action.spindash_jump_speed
		p.spindash_air_release_min_horizontal_speed = p._spindash_action.spindash_air_release_min_horizontal_speed
		p.spindash_air_release_horizontal_boost = p._spindash_action.spindash_air_release_horizontal_boost
		p.spindash_air_release_downward_ratio = p._spindash_action.spindash_air_release_downward_ratio
	else:
		p.spindash_enabled = false
	if p._drift_action != null:
		p.drift_enabled = p._drift_action.drift_enabled
		p.drift_min_speed = p._drift_action.drift_min_speed
		p.drift_exit_min_speed = p._drift_action.drift_exit_min_speed
		p.drift_input_deadzone = p._drift_action.drift_input_deadzone
		p.drift_steep_surface_angle_deg = p._drift_action.drift_steep_surface_angle_deg
		p.drift_base_turn_deg_per_sec = p._drift_action.drift_base_turn_deg_per_sec
		p.drift_tight_turn_multiplier = p._drift_action.drift_tight_turn_multiplier
		p.drift_counter_turn_multiplier = p._drift_action.drift_counter_turn_multiplier
		p.drift_turn_input_response = p._drift_action.drift_turn_input_response
		p.drift_turn_response = p._drift_action.drift_turn_response
		p.drift_direction_switch_time = p._drift_action.drift_direction_switch_time
		p.drift_direction_switch_carry_previous_influence = p._drift_action.drift_direction_switch_carry_previous_influence
		p.drift_turn_entry_time = p._drift_action.drift_turn_entry_time
		p.drift_entry_turn_rate_inheritance_enabled = p._drift_action.drift_entry_turn_rate_inheritance_enabled
		p.drift_entry_turn_rate_min_deg_per_sec = p._drift_action.drift_entry_turn_rate_min_deg_per_sec
		p.drift_entry_turn_rate_full_deg_per_sec = p._drift_action.drift_entry_turn_rate_full_deg_per_sec
		p.drift_entry_turn_rate_scale = p._drift_action.drift_entry_turn_rate_scale
		p.drift_entry_turn_rate_max_deg_per_sec = p._drift_action.drift_entry_turn_rate_max_deg_per_sec
		p.drift_entry_speed_inheritance = p._drift_action.drift_entry_speed_inheritance
		p.drift_entry_speed_inheritance_limit = p._drift_action.drift_entry_speed_inheritance_limit
		p.drift_reward_turn_degrees = p._drift_action.drift_reward_turn_degrees
		p.drift_reward_distance = p._drift_action.drift_reward_distance
		p.drift_reward_speed_bonus = p._drift_action.drift_reward_speed_bonus
		p.drift_reward_accel = p._drift_action.drift_reward_accel
		p.drift_exit_duration = p._drift_action.drift_exit_duration
		p.drift_exit_delay_enabled = p._drift_action.drift_exit_delay_enabled
		p.drift_exit_delay = p._drift_action.drift_exit_delay
		p.drift_exit_ease_curve = p._drift_action.drift_exit_ease_curve
		p.drift_anim_outward_speed_scale = p._drift_action.drift_anim_outward_speed_scale
		p.drift_anim_neutral_speed_scale = p._drift_action.drift_anim_neutral_speed_scale
		p.drift_anim_inward_speed_scale = p._drift_action.drift_anim_inward_speed_scale
		p.drift_anim_movement_min_scale = p._drift_action.drift_anim_movement_min_scale
		p.drift_anim_movement_max_scale = p._drift_action.drift_anim_movement_max_scale
		p.drift_anim_movement_speed_for_max = p._drift_action.drift_anim_movement_speed_for_max
		p.drift_visual_influence_enabled = p._drift_action.drift_visual_influence_enabled
		p.drift_visual_offset_angles_deg = p._drift_action.drift_visual_offset_angles_deg
		p.drift_visual_inner_angles_deg = p._drift_action.drift_visual_inner_angles_deg
		p.drift_visual_outer_angles_deg = p._drift_action.drift_visual_outer_angles_deg
		p.drift_visual_entry_lerp_speed = p._drift_action.drift_visual_entry_lerp_speed
		p.drift_visual_exit_lerp_speed = p._drift_action.drift_visual_exit_lerp_speed
		p.drift_debug_guides_enabled = p._drift_action.drift_debug_guides_enabled
		p.drift_debug_guide_length = p._drift_action.drift_debug_guide_length
		p.drift_debug_arc_segments = p._drift_action.drift_debug_arc_segments
		p.drift_loop_sound = p._drift_action.drift_loop_sound
		p.drift_sound_min_speed = p._drift_action.drift_sound_min_speed
		p.drift_sound_full_speed = p._drift_action.drift_sound_full_speed
		p.drift_sound_pitch_min = p._drift_action.drift_sound_pitch_min
		p.drift_sound_pitch_max = p._drift_action.drift_sound_pitch_max
		p.drift_sound_turn_min_deg_per_sec = p._drift_action.drift_sound_turn_min_deg_per_sec
		p.drift_sound_turn_full_deg_per_sec = p._drift_action.drift_sound_turn_full_deg_per_sec
		p.drift_sound_volume_min_db = p._drift_action.drift_sound_volume_min_db
		p.drift_sound_volume_max_db = p._drift_action.drift_sound_volume_max_db
		p.drift_sound_turn_lerp_speed = p._drift_action.drift_sound_turn_lerp_speed
	else:
		p.drift_enabled = false
	if p._fall_action != null:
		p.fall_vertical_speed_threshold = p._fall_action.fall_vertical_speed_threshold
		p.fall_airborne_grace_time = p._fall_action.fall_airborne_grace_time
	if p._jump_action != null:
		p.jump_speed = p._jump_action.jump_speed
		p.variable_jump_max_surface_angle_deg = p._jump_action.variable_jump_max_surface_angle_deg
		p.jump_hold_time_max = p._jump_action.jump_hold_time_max
		p.jump_hold_gravity_scale = p._jump_action.jump_hold_gravity_scale
		p.jump_apex_gravity_scale = p._jump_action.jump_apex_gravity_scale
		p.jump_apex_speed_threshold = p._jump_action.jump_apex_speed_threshold
		p.jump_release_gravity_scale = p._jump_action.jump_release_gravity_scale
		p.coyote_jump_enabled = p._jump_action.coyote_jump_enabled
		p.coyote_jump_duration = p._jump_action.coyote_jump_duration
		p.coyote_jump_max_angle_deg = p._jump_action.coyote_jump_max_angle_deg
		p.coyote_jump_homing_priority = p._jump_action.coyote_jump_homing_priority
		p.jump_damp_min_speed = p._jump_action.jump_damp_min_speed
		p.jump_damp_strength = p._jump_action.jump_damp_strength
		p.jump_damp_curve = p._jump_action.jump_damp_curve
	if p._jump_dash_action != null:
		p.jump_dash_air_only = p._jump_dash_action.jump_dash_air_only
		p.jump_dash_once_per_air = p._jump_dash_action.jump_dash_once_per_air
		p.jump_dash_add_speed = p._jump_dash_action.jump_dash_add_speed
		p.jump_dash_impulse_stop_speed = p._jump_dash_action.jump_dash_impulse_stop_speed
		p.jump_dash_max_lateral_speed = p._jump_dash_action.jump_dash_max_lateral_speed
	if p._homing_action != null:
		p.homing_targeting_enabled = p._homing_action.homing_targeting_enabled
		p.homing_attack_enabled = p._homing_action.homing_attack_enabled
		p.homing_min_range = p._homing_action.homing_min_range
		p.homing_max_range = p._homing_action.homing_max_range
		p.homing_range_per_speed = p._homing_action.homing_range_per_speed
		p.homing_min_dot = p._homing_action.homing_min_dot
		p.homing_hybrid_input_min_strength = p._homing_action.homing_hybrid_input_min_strength
		p.homing_hybrid_camera_priority_angle_deg = p._homing_action.homing_hybrid_camera_priority_angle_deg
		p.homing_hybrid_full_input_angle_deg = p._homing_action.homing_hybrid_full_input_angle_deg
		p.homing_hybrid_reticle_priority = p._homing_action.homing_hybrid_reticle_priority
		p.homing_speed = p._homing_action.homing_speed
		p.homing_turn_rate = p._homing_action.homing_turn_rate
		p.homing_hit_distance = p._homing_action.homing_hit_distance
		p.homing_pop_up_speed = p._homing_action.homing_pop_up_speed
		p.homing_bounce_speed_fraction = p._homing_action.homing_bounce_speed_fraction
		p.enemy_bounce_min_speed = p._homing_action.enemy_bounce_min_speed
		p.homing_below_target_bounce_cap_enabled = p._homing_action.homing_below_target_bounce_cap_enabled
		p.homing_below_target_min_height = p._homing_action.homing_below_target_min_height
		p.homing_below_target_max_up_speed = p._homing_action.homing_below_target_max_up_speed
		p.homing_target_max_height = p._homing_action.homing_target_max_height
		p.homing_obstruction_check = p._homing_action.homing_obstruction_check
		p.homing_obstruction_margin = p._homing_action.homing_obstruction_margin
		p.homing_retain_speed_if_jump_held = p._homing_action.homing_retain_speed_if_jump_held
		p.homing_retain_disable_air_decel_time = p._homing_action.homing_retain_disable_air_decel_time
		p.homing_fail_timeout = p._homing_action.homing_fail_timeout
		p.homing_post_attack_time = p._homing_action.homing_post_attack_time
	if p._lightspeed_dash_action != null:
		p.lightspeed_dash_enabled = p._lightspeed_dash_action.lightspeed_dash_enabled
		p.lightspeed_dash_start_radius = p._lightspeed_dash_action.lightspeed_dash_start_radius
		p.lightspeed_dash_chain_radius = p._lightspeed_dash_action.lightspeed_dash_chain_radius
		p.lightspeed_dash_collect_distance = p._lightspeed_dash_action.lightspeed_dash_collect_distance
		p.lightspeed_dash_min_forward_dot = p._lightspeed_dash_action.lightspeed_dash_min_forward_dot
		p.lightspeed_dash_max_height_delta = p._lightspeed_dash_action.lightspeed_dash_max_height_delta
		p.lightspeed_dash_min_speed = p._lightspeed_dash_action.lightspeed_dash_min_speed
		p.lightspeed_dash_max_iterations_per_frame = p._lightspeed_dash_action.lightspeed_dash_max_iterations_per_frame
		p.lightspeed_dash_max_duration = p._lightspeed_dash_action.lightspeed_dash_max_duration
		p.lightspeed_dash_speed_bonus_per_speed = p._lightspeed_dash_action.lightspeed_dash_speed_bonus_per_speed
		p.lightspeed_dash_camera_radius_bonus = p._lightspeed_dash_action.lightspeed_dash_camera_radius_bonus
		p.lightspeed_dash_hybrid_angle_deg = p._lightspeed_dash_action.lightspeed_dash_hybrid_angle_deg
		p.lightspeed_dash_turn_rate = p._lightspeed_dash_action.lightspeed_dash_turn_rate
		p.lightspeed_dash_start_additive_speed_enabled = p._lightspeed_dash_action.lightspeed_dash_start_additive_speed_enabled
		p.lightspeed_dash_start_additive_speed = p._lightspeed_dash_action.lightspeed_dash_start_additive_speed
		p.lightspeed_dash_start_bonus_cooldown = p._lightspeed_dash_action.lightspeed_dash_start_bonus_cooldown
		p.lightspeed_dash_start_speed_cap = p._lightspeed_dash_action.lightspeed_dash_start_speed_cap
		p.lightspeed_dash_auto_attach_on_end = p._lightspeed_dash_action.lightspeed_dash_auto_attach_on_end
		p.lightspeed_dash_auto_attach_max_distance = p._lightspeed_dash_action.lightspeed_dash_auto_attach_max_distance
		p.lightspeed_dash_auto_attach_allow_wall_fallback = p._lightspeed_dash_action.lightspeed_dash_auto_attach_allow_wall_fallback
		p.lightspeed_dash_face_target = p._lightspeed_dash_action.lightspeed_dash_face_target
	if p._bounce_action != null:
		p.bounce_enabled = p._bounce_action.bounce_enabled
		p.bounce_gravity_scale = p._bounce_action.bounce_gravity_scale
		p.bounce_down_impulse = p._bounce_action.bounce_down_impulse
		p.bounce_min_impact_speed = p._bounce_action.bounce_min_impact_speed
		p.bounce_add_speed = p._bounce_action.bounce_add_speed
		p.bounce_min_up_speed = p._bounce_action.bounce_min_up_speed
		p.bounce_max_up_speed = p._bounce_action.bounce_max_up_speed
		p.bounce_land_speed_threshold = p._bounce_action.bounce_land_speed_threshold
		p.bounce_land_speed_subtract = p._bounce_action.bounce_land_speed_subtract
		p.bounce_land_horizontal_threshold = p._bounce_action.bounce_land_horizontal_threshold
		p.bounce_land_horizontal_subtract = p._bounce_action.bounce_land_horizontal_subtract
	if p._stomp_action != null:
		p.stomp_gravity_scale = p._stomp_action.stomp_gravity_scale
		p.stomp_down_impulse = p._stomp_action.stomp_down_impulse
		p.stomp_land_speed_threshold = p._stomp_action.stomp_land_speed_threshold
		p.stomp_land_speed_subtract = p._stomp_action.stomp_land_speed_subtract
		p.stomp_land_horizontal_threshold = p._stomp_action.stomp_land_horizontal_threshold
		p.stomp_land_horizontal_subtract = p._stomp_action.stomp_land_horizontal_subtract
	if p._spring_action != null:
		p.spring_gravity_scale = p._spring_action.spring_gravity_scale
		p.spring_exit_on_low_speed = p._spring_action.spring_exit_on_low_speed
		p.spring_exit_speed_threshold = p._spring_action.spring_exit_speed_threshold
		p.spring_model_snap_time = p._spring_action.spring_model_snap_time
		p.spline_model_pitch_deg = p._spring_action.spline_model_pitch_deg
	if p._hurt_action != null:
		p.damage_hit_invuln_time = p._hurt_action.damage_hit_invuln_time
		p.damage_trip_speed_threshold = p._hurt_action.damage_trip_speed_threshold
		p.damage_trip_speed_multiplier = p._hurt_action.damage_trip_speed_multiplier
		p.damage_pushback_speed = p._hurt_action.damage_pushback_speed
		p.damage_launch_upward_speed = p._hurt_action.damage_launch_upward_speed
		p.hurt_input_influence = p._hurt_action.hurt_input_influence
		p.hurt_air_decel_multiplier = p._hurt_action.hurt_air_decel_multiplier
		p.hurt_ground_decel_multiplier = p._hurt_action.hurt_ground_decel_multiplier
		p.hurt_air_jump_unlock_time = p._hurt_action.hurt_air_jump_unlock_time
		p.hurt_invuln_flash_interval = p._hurt_action.hurt_invuln_flash_interval
	if p._rail_grind_action != null:
		p.rail_jump_vertical_speed = p._rail_grind_action.rail_jump_vertical_speed
		p.rail_default_attach_height = p._rail_grind_action.rail_default_attach_height
		p.rail_align_to_path_tilt = p._rail_grind_action.rail_align_to_path_tilt
		p.rail_allow_input_reverse = p._rail_grind_action.rail_allow_input_reverse
		p.rail_reverse_speed_threshold = p._rail_grind_action.rail_reverse_speed_threshold
		p.rail_reverse_boost_speed = p._rail_grind_action.rail_reverse_boost_speed
		p.rail_reverse_input_dot_threshold = p._rail_grind_action.rail_reverse_input_dot_threshold
		p.rail_end_detach_distance = p._rail_grind_action.rail_end_detach_distance
		p.rail_rehit_cooldown = p._rail_grind_action.rail_rehit_cooldown
		p.rail_crouch_enabled = p._rail_grind_action.rail_crouch_enabled
		p.rail_crouch_uphill_decel = p._rail_grind_action.rail_crouch_uphill_decel
		p.rail_crouch_downhill_accel = p._rail_grind_action.rail_crouch_downhill_accel
		p.rail_path_snap_enabled = p._rail_grind_action.rail_path_snap_enabled
		p.rail_path_snap_radius_min = p._rail_grind_action.rail_path_snap_radius_min
		p.rail_path_snap_radius_max = p._rail_grind_action.rail_path_snap_radius_max
		p.rail_path_snap_speed_for_max_radius = p._rail_grind_action.rail_path_snap_speed_for_max_radius
		p.rail_path_snap_obstruction_check = p._rail_grind_action.rail_path_snap_obstruction_check
		p.rail_path_snap_obstruction_margin = p._rail_grind_action.rail_path_snap_obstruction_margin
		p.rail_anim_min_scale = p._rail_grind_action.rail_anim_min_scale
		p.rail_anim_max_scale = p._rail_grind_action.rail_anim_max_scale
		p.rail_anim_speed_for_max = p._rail_grind_action.rail_anim_speed_for_max
		p.rail_anim_blend_smooth_speed = p._rail_grind_action.rail_anim_blend_smooth_speed
		p.rail_anim_dir_smooth_speed = p._rail_grind_action.rail_anim_dir_smooth_speed
		p.rail_anim_dir_speed_for_full = p._rail_grind_action.rail_anim_dir_speed_for_full
		p.rail_switch_enabled = p._rail_grind_action.rail_switch_enabled
		p.rail_switch_query_radius = p._rail_grind_action.rail_switch_query_radius
		p.rail_switch_side_input_min = p._rail_grind_action.rail_switch_side_input_min
		p.rail_switch_side_dot_min = p._rail_grind_action.rail_switch_side_dot_min
		p.rail_switch_forward_dot_min = p._rail_grind_action.rail_switch_forward_dot_min
		p.rail_switch_tangent_lookahead = p._rail_grind_action.rail_switch_tangent_lookahead
		p.rail_switch_lateral_speed = p._rail_grind_action.rail_switch_lateral_speed
		p.rail_switch_vertical_speed = p._rail_grind_action.rail_switch_vertical_speed
		p.rail_switch_forward_speed_scale = p._rail_grind_action.rail_switch_forward_speed_scale
		p.rail_switch_forward_speed_min = p._rail_grind_action.rail_switch_forward_speed_min
		p.rail_switch_snap_distance = p._rail_grind_action.rail_switch_snap_distance
		p.rail_switch_max_duration = p._rail_grind_action.rail_switch_max_duration
		p.rail_switch_min_end_distance = p._rail_grind_action.rail_switch_min_end_distance
		p.rail_grind_min_speed = p._rail_grind_action.rail_grind_min_speed
		p.rail_grind_full_speed = p._rail_grind_action.rail_grind_full_speed
		p.rail_grind_volume_min_db = p._rail_grind_action.rail_grind_volume_min_db
		p.rail_grind_volume_max_db = p._rail_grind_action.rail_grind_volume_max_db
		p.rail_grind_pitch_min = p._rail_grind_action.rail_grind_pitch_min
		p.rail_grind_pitch_max = p._rail_grind_action.rail_grind_pitch_max
		p.rail_grind_fade_speed_db = p._rail_grind_action.rail_grind_fade_speed_db
		p.rail_grind_stop_volume_db = p._rail_grind_action.rail_grind_stop_volume_db
		p.can_grind_rails = p._rail_grind_action.can_grind()
	else:
		p.can_grind_rails = false


func _sync_roll_state_from_action() -> void:
	var p = _owner
	if p._roll_action == null:
		p.rolling = false
		return
	p.rolling = p._roll_action.is_rolling


func _sync_spindash_state_from_action() -> void:
	var p = _owner
	if p._spindash_action == null:
		return
	p._spindash_charging = p._spindash_action.is_charging
	p._spindash_charge_time = p._spindash_action.charge_time
	p._spindash_charge_full_played = p._spindash_action.charge_full_played
	p._spindash_release_requested = p._spindash_action.release_requested
	p._spindash_release_with_jump = p._spindash_action.release_with_jump
	p._spindash_release_speed = p._spindash_action.release_speed
	p._spindash_pending_release = p._spindash_action.pending_release
	p._spindash_pending_release_speed = p._spindash_action.pending_release_speed
	p._spindash_turn_free_timer = max(p._spindash_turn_free_timer, p._spindash_action.turn_free_timer)
	p._spindash_action.turn_free_timer = p._spindash_turn_free_timer
	p._spindash_entry_speed = p._spindash_action.entry_speed
	p._spindash_latched_direction = p._spindash_action.latched_direction
	p._spindash_ground_hold_timer = p._spindash_action.ground_hold_timer
	p._spindash_roll_held = p._spindash_action.roll_held


func _sync_spindash_state_to_action() -> void:
	var p = _owner
	if p._spindash_action == null:
		return
	p._spindash_action.is_charging = p._spindash_charging
	p._spindash_action.charge_time = p._spindash_charge_time
	p._spindash_action.charge_full_played = p._spindash_charge_full_played
	p._spindash_action.release_requested = p._spindash_release_requested
	p._spindash_action.release_with_jump = p._spindash_release_with_jump
	p._spindash_action.release_speed = p._spindash_release_speed
	p._spindash_action.pending_release = p._spindash_pending_release
	p._spindash_action.pending_release_speed = p._spindash_pending_release_speed
	p._spindash_action.turn_free_timer = p._spindash_turn_free_timer
	p._spindash_action.entry_speed = p._spindash_entry_speed
	p._spindash_action.latched_direction = p._spindash_latched_direction
	p._spindash_action.ground_hold_timer = p._spindash_ground_hold_timer
	p._spindash_action.roll_held = p._spindash_roll_held


func _sync_drift_state_from_action() -> void:
	var p = _owner
	if p._drift_action == null:
		return
	p._drift_active = p._drift_action.is_active
	p._drift_exit_active = p._drift_action.exit_active
	p._drift_exit_pending = p._drift_action.exit_pending
	p._drift_exit_locked = p._drift_action.exit_locked
	p._drift_turn_deg_per_sec_current = p._drift_action.turn_deg_per_sec_current
	p._drift_turn_input_scale_current = p._drift_action.turn_input_scale_current
	p._drift_back_input_current = p._drift_action.back_input_current
	p._drift_same_input_current = p._drift_action.same_input_current
	p._drift_turn_entry_timer = p._drift_action.turn_entry_timer
	p._drift_entry_turn_deg_per_sec_start = p._drift_action.entry_turn_deg_per_sec_start
	p._drift_exit_turn_deg_per_sec_current = p._drift_action.exit_turn_deg_per_sec_current
	p._drift_exit_turn_deg_per_sec_start = p._drift_action.exit_turn_deg_per_sec_start
	p._drift_exit_elapsed = p._drift_action.exit_elapsed
	p._drift_exit_blend = p._drift_action.exit_blend
	p._drift_turn_speed_last = p._drift_action.turn_speed_last
	p._drift_direction = p._drift_action.drift_direction
	p._drift_direction_target = p._drift_action.drift_direction_target
	p._drift_direction_value = p._drift_action.drift_direction_value
	p._drift_direction_value_start = p._drift_action.drift_direction_value_start
	p._drift_switch_elapsed = p._drift_action.drift_switch_elapsed
	p._drift_reward_turn_degrees_current = p._drift_action.drift_reward_turn_degrees_current
	p._drift_reward_distance_current = p._drift_action.drift_reward_distance_current
	p._drift_reward_progress = p._drift_action.drift_reward_progress
	p._drift_speed_bonus_current = p._drift_action.drift_speed_bonus_current
	p._drift_entry_speed_current = p._drift_action.drift_entry_speed_current
	if abs(p._drift_turn_speed_last) <= 0.0001:
		p._drift_turn_speed_memory_timer = 0.0


func _sync_drift_state_to_action() -> void:
	var p = _owner
	if p._drift_action == null:
		return
	p._drift_action.is_active = p._drift_active
	p._drift_action.exit_active = p._drift_exit_active
	p._drift_action.exit_pending = p._drift_exit_pending
	p._drift_action.exit_locked = p._drift_exit_locked
	p._drift_action.turn_deg_per_sec_current = p._drift_turn_deg_per_sec_current
	p._drift_action.turn_input_scale_current = p._drift_turn_input_scale_current
	p._drift_action.back_input_current = p._drift_back_input_current
	p._drift_action.same_input_current = p._drift_same_input_current
	p._drift_action.turn_entry_timer = p._drift_turn_entry_timer
	p._drift_action.entry_turn_deg_per_sec_start = p._drift_entry_turn_deg_per_sec_start
	p._drift_action.exit_turn_deg_per_sec_current = p._drift_exit_turn_deg_per_sec_current
	p._drift_action.exit_turn_deg_per_sec_start = p._drift_exit_turn_deg_per_sec_start
	p._drift_action.exit_elapsed = p._drift_exit_elapsed
	p._drift_action.exit_blend = p._drift_exit_blend
	p._drift_action.turn_speed_last = p._drift_turn_speed_last
	p._drift_action.drift_direction = p._drift_direction
	p._drift_action.drift_direction_target = p._drift_direction_target
	p._drift_action.drift_direction_value = p._drift_direction_value
	p._drift_action.drift_direction_value_start = p._drift_direction_value_start
	p._drift_action.drift_switch_elapsed = p._drift_switch_elapsed
	p._drift_action.drift_reward_turn_degrees_current = p._drift_reward_turn_degrees_current
	p._drift_action.drift_reward_distance_current = p._drift_reward_distance_current
	p._drift_action.drift_reward_progress = p._drift_reward_progress
	p._drift_action.drift_speed_bonus_current = p._drift_speed_bonus_current
	p._drift_action.drift_entry_speed_current = p._drift_entry_speed_current


func _sync_spring_state_from_action() -> void:
	var p = _owner
	if p._spring_action == null:
		return
	p._spring_movement_lock_timer = p._spring_action.movement_lock_timer
	p._spring_action_lock_timer = p._spring_action.action_lock_timer
	p._spring_align_timer = p._spring_action.align_timer
	p._spring_align_dir = p._spring_action.align_dir
	p._spring_lock_sideways = p._spring_action.lock_sideways
	p._spring_sideways_gravity_scale = p._spring_action.sideways_gravity_scale
	p._spring_cancel_on_ground = p._spring_action.cancel_on_ground
	p._spring_align_up = p._spring_action.align_up
	p._spring_align_forward = p._spring_action.align_forward
	p._spring_clear_move_on_ground = p._spring_action.clear_move_on_ground
	p._spring_clear_action_on_ground = p._spring_action.clear_action_on_ground
	p._spring_detached = p._spring_action.detached
	p._spring_align_model = p._spring_action.align_model
	p._spring_model_snap_timer = p._spring_action.model_snap_timer
	p._spring_trajectory_torque_active = p._spring_action.trajectory_torque_active
	p._spring_trajectory_torque_align_speed_deg = p._spring_action.trajectory_torque_align_speed_deg


func _sync_spring_state_to_action() -> void:
	var p = _owner
	if p._spring_action == null:
		return
	p._spring_action.movement_lock_timer = p._spring_movement_lock_timer
	p._spring_action.action_lock_timer = p._spring_action_lock_timer
	p._spring_action.align_timer = p._spring_align_timer
	p._spring_action.align_dir = p._spring_align_dir
	p._spring_action.lock_sideways = p._spring_lock_sideways
	p._spring_action.sideways_gravity_scale = p._spring_sideways_gravity_scale
	p._spring_action.cancel_on_ground = p._spring_cancel_on_ground
	p._spring_action.align_up = p._spring_align_up
	p._spring_action.align_forward = p._spring_align_forward
	p._spring_action.clear_move_on_ground = p._spring_clear_move_on_ground
	p._spring_action.clear_action_on_ground = p._spring_clear_action_on_ground
	p._spring_action.detached = p._spring_detached
	p._spring_action.align_model = p._spring_align_model
	p._spring_action.model_snap_timer = p._spring_model_snap_timer
	p._spring_action.trajectory_torque_active = p._spring_trajectory_torque_active
	p._spring_action.trajectory_torque_align_speed_deg = p._spring_trajectory_torque_align_speed_deg


func _sync_hurt_state_from_action() -> void:
	var p = _owner
	if p._hurt_action == null:
		return
	p._hurt_active = p._hurt_action.is_active
	p._hurt_state_timer = p._hurt_action.state_timer
	p._hurt_flash_accum = p._hurt_action.flash_accum
	p._hurt_flash_visible = p._hurt_action.flash_visible
	p._damage_hit_invuln_timer = p._hurt_action.invuln_timer


func _sync_hurt_state_to_action() -> void:
	var p = _owner
	if p._hurt_action == null:
		return
	p._hurt_action.is_active = p._hurt_active
	p._hurt_action.state_timer = p._hurt_state_timer
	p._hurt_action.flash_accum = p._hurt_flash_accum
	p._hurt_action.flash_visible = p._hurt_flash_visible
	p._hurt_action.invuln_timer = p._damage_hit_invuln_timer

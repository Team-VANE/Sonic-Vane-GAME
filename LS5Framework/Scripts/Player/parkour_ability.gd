class_name ParkourAbility
extends CharacterAbility

enum WallMode { RUN, CLING }
enum WallRunAnimationSpeedSource { COMBINED, HORIZONTAL, VERTICAL }
enum WallLiftPhase { NONE, SETTLING, HOLD, RELEASE }

@export_group("Parkour")
@export_subgroup("Contact")
## Air actions from which a wall catch may begin.
@export var allowed_source_actions: Array[StringName] = [
	&"fall",
	&"jump",
	&"jump_dash",
	&"bounce",
	&"bounce_rebound",
	&"stomp",
	&"skydive",
	&"spin_kick",
	&"uppercut_kick",
]
## Air actions that may catch a wall but always enter the cling mode.
@export var cling_only_source_actions: Array[StringName] = []
## Maximum wall distance from the character origin, including the collision radius.
@export var contact_reach: float = 1.15
## Vertical offset of the upper and lower contact probes.
@export var probe_vertical_span: float = 0.5
## Number of evenly spaced gravity-relative directions used by radial wall probes.
@export_range(8, 48, 1) var radial_probe_count: int = 24
## Radius of the central sweep used when narrow contact rays miss a wall.
@export var contact_probe_radius: float = 0.15
## Maximum wall tilt away from gravity-relative vertical.
@export_range(0.0, 40.0, 1.0) var maximum_wall_tilt_degrees: float = 18.0
## Maximum convex change in wall normal permitted during a wall run. Larger outward turns detach.
@export_range(0.0, 90.0, 1.0) var maximum_outward_curve_degrees: float = 45.0
## Maximum concave change in wall normal permitted during a wall run.
@export_range(0.0, 90.0, 1.0) var maximum_inward_curve_degrees: float = 75.0
## Contact-loss window in which a wall kick remains available.
@export var contact_grace_time: float = 0.05
## Time after leaving a wall during which Jump may still perform the remembered wall kick.
@export var wall_kick_coyote_time: float = 0.15
## Jump buffer duration while approaching a nearby wall with Parkour held.
@export var jump_buffer_time: float = 0.1
## Additional wall reach used only to buffer an approaching jump input.
@export var jump_buffer_reach: float = 3.0
## Maximum outward velocity allowed when catching a wall.
@export var maximum_outward_catch_speed: float = 2.0
## Inward contact velocity while a wall is detected.
@export var contact_pressure_speed: float = 3.0
## Collision layers used by wall probes. Zero uses the character collision mask.
@export_flags_3d_physics var collision_mask_override: int = 0

@export_subgroup("Contextual Prompts")
## Displays the eligible wall-run or wall-cling action near a suitable wall.
@export var wall_proximity_prompt_enabled: bool = true
## Maximum wall distance for contextual prompts. Does not alter wall-catch reach.
@export_range(0.1, 10.0, 0.05, "suffix:m") var wall_prompt_reach: float = 2.65
## Minimum interval between supplemental wall proximity probes.
@export_range(0.05, 1.0, 0.01, "suffix:s") var wall_prompt_probe_interval: float = 0.1
## Contextual label when the wall-run entry decision is eligible.
@export var wall_run_prompt_name: String = "Wall Run"
## Contextual label when the wall-cling entry decision is eligible.
@export var wall_cling_prompt_name: String = "Wall Cling"

@export_subgroup("Wall Run")
## Center speed of the input-biased wall-run entry decision band.
@export var run_entry_speed: float = 35.0
## Speed range below and above the center where movement input may change the entry mode.
@export var run_entry_input_bias_speed_range: float = 17.0
## Movement-input strength below which entry receives the full cling bias.
@export_range(0.0, 1.0, 0.01) var run_entry_input_deadzone: float = 0.15
## Parallel share of wall-relative input where the wall-run bias begins.
@export_range(0.0, 1.0, 0.01) var run_entry_parallel_bias_start: float = 0.45
## Parallel share of wall-relative input where the wall-run bias reaches full strength.
@export_range(0.0, 1.0, 0.01) var run_entry_parallel_bias_full: float = 0.75
## Parallel speed below which an existing run transitions into a cling.
@export var run_exit_speed: float = 12.0
## Time below the exit threshold before a run becomes a cling.
@export var run_exit_delay: float = 0.12
## Minimum time a dash-panel launch retains wall-run mode at low parallel speed.
@export var wall_run_dash_panel_mode_hold_time: float = 0.35
## Optional entry speed top-up. Zero disables it; faster momentum is preserved.
@export var run_entry_speed_target: float = 0.0
## Fractional wall-parallel speed boost granted on fresh wall-run entry.
@export_range(0.0, 1.0, 0.01) var entry_forward_boost: float = 0.12
## Maximum additional wall-parallel speed granted on fresh wall-run entry.
@export var entry_forward_boost_limit: float = 5.0
## Fractional upward entry velocity boost.
@export_range(0.0, 1.0, 0.01) var entry_upward_boost: float = 0.2
## Maximum additional upward speed granted on entry.
@export var entry_upward_boost_limit: float = 3.0
## Fraction of downward entry speed removed on a fresh catch.
@export_range(0.0, 1.0, 0.01) var entry_downward_damping: float = 0.25
## Gravity multiplier while wall-run lift settles vertical entry speed.
@export_range(0.0, 1.0, 0.01) var run_initial_gravity_scale: float = 0.2
## Wall-run lift hold time at the run entry threshold.
@export var run_assistance_min_time: float = 0.5
## Maximum wall-run lift hold time.
@export var run_assistance_max_time: float = 1.5
## Wall-parallel entry speed providing the maximum lift hold time.
@export var run_assistance_max_speed: float = 70.0
@export_subgroup("Wall Run Lift")
## Enables settling, sustained height, and eased gravity return during wall runs.
@export var wall_lift_enabled: bool = true
## Maximum time allowed to settle into a horizontal wall run.
@export_range(0.0, 2.0, 0.01) var wall_lift_settle_max_time: float = 1.75
## Maximum settle time for a fast upward wall-run entry.
@export_range(0.0, 5.0, 0.01) var wall_lift_upward_settle_max_time: float = 0.3
## Downward speed removed per second while settling into a horizontal run.
@export_range(0.0, 300.0, 1.0) var wall_lift_downward_funnel_acceleration: float = 120.0
## Upward speed removed per second while settling into a horizontal run.
@export_range(0.0, 300.0, 1.0) var wall_lift_upward_funnel_acceleration: float = 85.0
## Fraction of vertical entry speed counted toward the lift hold duration.
@export_range(0.0, 1.0, 0.01) var wall_lift_vertical_entry_speed_weight: float = 0.4
## Maximum vertical-speed contribution as a fraction of wall-parallel entry speed.
@export_range(0.0, 1.0, 0.01) var wall_lift_vertical_entry_parallel_limit: float = 0.5
## Upward entry speed component redirected into wall-parallel speed when lift begins.
@export_range(0.0, 1.0, 0.01) var wall_lift_upward_entry_parallel_carry: float = 0.8
## Downward entry speed component redirected into wall-parallel speed when lift begins.
@export_range(0.0, 1.0, 0.01) var wall_lift_downward_entry_parallel_carry: float = 0.8
## Maximum wall-parallel speed gained from vertical entry when lift begins.
@export_range(0.0, 100.0, 0.1) var wall_lift_entry_parallel_gain_limit: float = 20.0
## Gravity-relative vertical speed accepted as a settled horizontal run.
@export_range(0.0, 10.0, 0.05) var wall_lift_settled_speed: float = 1.0
## Vertical speed correction per second during the lift hold.
@export_range(0.0, 100.0, 1.0) var wall_lift_hold_correction: float = 20.0
## Time used to ease from lift support into full gravity.
@export_range(0.01, 2.0, 0.01) var wall_lift_release_time: float = 0.3
## Minimum lift strength on a previously used same-facing wall until traversal refresh.
@export_range(0.0, 1.0, 0.01) var wall_lift_same_surface_minimum_strength: float = 0.25
## Inward wall-normal turn needed to replenish lift during a continuous fast run.
@export_range(90.0, 180.0, 1.0) var wall_lift_inward_refresh_angle: float = 120.0
## Minimum forward travel required for a continuous inward-turn lift refresh.
@export_range(0.0, 20.0, 0.1) var wall_lift_inward_refresh_distance: float = 3.0
## Minimum wall-parallel speed required for an inward-turn lift refresh.
@export_range(0.0, 200.0, 1.0) var wall_lift_inward_refresh_speed: float = 30.0
@export_subgroup("Wall Run")
## Physics-frame prediction multiplier used to probe the wall ahead of a wall run.
@export var run_curve_lookahead_time_scale: float = 1.5
## Maximum forward distance used to find the next face of a curved wall.
@export var run_curve_lookahead_max_distance: float = 3.0
## Fraction of inward horizontal entry speed redirected into a fresh wall run.
@export_range(0.0, 1.0, 0.01) var entry_angle_speed_conversion: float = 0.15
## Maximum wall-parallel speed granted by angled-entry conversion.
@export var entry_angle_speed_conversion_limit: float = 5.0

@export_subgroup("Wall Cling")
## Half-life of horizontal wall-parallel velocity settling toward stick input.
@export var cling_horizontal_half_life: float = 0.12
## Maximum horizontal wall-parallel speed requested by full stick input.
@export var cling_control_speed: float = 3.0
## Half-life of upward velocity while clinging. Lower values stop upward sliding sooner.
@export var cling_upward_velocity_half_life: float = 0.85
## Initial downward gravity multiplier during a cling.
@export var cling_initial_gravity_scale: float = 0.2
## Minimum gravity multiplier while rising in a cling entered from regular surface attachment.
@export var grounded_cling_upward_gravity_scale: float = 1.45
## Delay before cling gravity starts increasing.
@export var cling_slide_delay: float = 0.5
## Time taken to reach the final cling gravity strength after the delay.
@export var cling_slide_ramp_time: float = 1.0
## Final gravity multiplier during a sustained cling.
@export var cling_final_gravity_scale: float = 1.0

@export_subgroup("Landing Roll")
## Time before landing during which a Parkour press may trigger a landing roll.
@export var landing_roll_input_window: float = 0.9
## Time after landing during which a Parkour press may trigger a landing roll from captured impact momentum.
@export var landing_roll_post_landing_window: float = 0.2
## Maximum gravity-relative floor angle accepted by a landing roll.
@export_range(0.0, 90.0, 1.0) var landing_roll_max_surface_angle_degrees: float = 60.0
## Minimum into-floor impact speed required for a landing roll.
@export var landing_roll_min_impact_speed: float = 35.0
## Minimum into-floor impact speed for a landing roll after a passive ledge drop.
@export var landing_roll_passive_drop_min_impact_speed: float = 1.0
## Minimum incoming tangential speed required for a landing roll.
@export var landing_roll_min_tangential_speed: float = 8.0
## Fraction of incoming tangential speed added back by a successful landing roll.
@export_range(0.0, 1.0, 0.01) var landing_roll_tangential_recovery: float = 0.6
## Maximum additional tangential speed recovered by a landing roll.
@export var landing_roll_recovery_limit: float = 23.0
## Fraction of incoming tangential speed added back during Barrier Blast.
@export_range(0.0, 1.0, 0.01) var landing_roll_barrier_blast_tangential_recovery: float = 0.5
## Maximum additional tangential speed recovered during Barrier Blast.
@export var landing_roll_barrier_blast_recovery_limit: float = 28.0
## Cooldown after receiving landing-roll speed recovery before it can be granted again.
@export var landing_roll_speed_benefit_cooldown: float = 0.7
## Minimum uninterrupted airborne time after a jump or other action required for landing-roll speed recovery.
@export var landing_roll_speed_benefit_min_airborne_time: float = 0.7
## Time spent using only the main collision sphere after a successful landing roll.
@export var landing_roll_compact_collision_duration: float = 0.7
## Minimum radial approach angle required for rough-landing feedback.
@export_range(0.0, 90.0, 0.1, "suffix:Â°") var rough_landing_min_approach_angle: float = 35.0
## Minimum ground collision strength required for rough-landing feedback.
@export_range(0.0, 1.0, 0.01) var rough_landing_min_ground_hit_strength: float = 0.2
## Animation command used for a successful landing roll.
@export var landing_roll_animation_command: StringName = &"CMD_LANDING_ROLL"
## One-shot AnimationTree request path used to keep the landing roll visible over state transitions.
@export var landing_roll_override_parameter: String = "LandingRollOverride/request"

@export_subgroup("Wall Carve Combo")
## Distance traveled during a wall run before another Wall Carve is registered.
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m") var wall_carve_distance_units: float = 12.0
## Base score awarded for each Wall Carve interval.
@export_range(0.0, 10000.0, 1.0, "or_greater") var wall_carve_score: float = 40.0
## Combo time added for each Wall Carve interval.
@export_range(0.0, 5.0, 0.05) var wall_carve_timer_add_seconds: float = 1.25

@export_subgroup("Wall Kick/Wall Run")
## Outward launch speed for a wall-run kick before surface and chain penalties.
@export var wall_run_kick_outward_speed: float = 85.0
## Upward launch target for a wall-run kick before vertical speed carry.
@export var wall_run_kick_upward_speed: float = 38.0
## Entry speed where wall-run kick mirroring begins.
@export var wall_run_kick_entry_mirror_min_speed: float = 30.0
## Entry speed that reaches the maximum wall-run kick mirror multipliers.
@export var wall_run_kick_entry_mirror_max_speed: float = 175.0
## Maximum outward wall-run kick multiplier produced by entry speed.
@export_range(1.0, 10.0, 0.01) var wall_run_kick_entry_outward_multiplier: float = 1.25
## Maximum upward wall-run kick multiplier produced by entry speed.
@export_range(1.0, 10.0, 0.01) var wall_run_kick_entry_upward_multiplier: float = 1.0
## Fraction of captured vertical entry speed added to the wall-run kick's upward target.
@export_range(0.0, 1.0, 0.01) var wall_run_kick_vertical_entry_boost: float = 0.06
## Maximum upward speed added from wall-run vertical entry speed.
@export var wall_run_kick_vertical_entry_boost_limit: float = 8.0
## Fraction of current upward wall-run speed retained when it exceeds the kick's upward target.
@export_range(0.0, 3.0, 0.01) var wall_run_kick_upward_speed_carry: float = 0.8
## Fraction of current downward wall-run speed subtracted from the kick's upward speed.
@export_range(0.0, 3.0, 0.01) var wall_run_kick_downward_speed_carry: float = 0.2
## Minimum outward speed for a wall-run kick when strength is depleted.
@export var wall_run_kick_minimum_outward_speed: float = 1.0
## Optional wall-parallel speed top-up for a wall-run kick. Zero disables it.
@export var wall_run_kick_parallel_speed_target: float = 0.0
## Maximum stick-directed steering angle for a wall-run kick.
@export_range(0.0, 30.0, 1.0) var wall_run_kick_steering_degrees: float = 10.0
## Movement-input lock duration after a wall-run kick.
@export var wall_run_kick_movement_input_lock_time: float = 0.35
## Input-influence duration after the weakest wall-run kick.
@export var wall_run_kick_input_influence_min_time: float = 0.12
## Input-influence duration after a full-strength wall-run kick.
@export var wall_run_kick_input_influence_max_time: float = 0.32
## Inward input retained at the start of wall-run kick influence.
@export_range(0.0, 1.0, 0.01) var wall_run_kick_input_initial_inward_ratio: float = 0.0
## Outward-speed sustain duration after a wall-run kick.
@export var wall_run_kick_outward_sustain_time: float = 0.07
## Upward-speed sustain duration after a wall-run kick.
@export var wall_run_kick_upward_sustain_time: float = 0.08
## Minimum time before the wall-run kick surface can be caught again.
@export var wall_run_kick_recatch_delay: float = 0.16
## Separation required before the wall-run kick surface can be caught again.
@export var wall_run_kick_recatch_distance: float = 0.7

@export_subgroup("Wall Kick/Wall Cling")
## Outward launch speed for a wall-cling kick before surface and chain penalties.
@export var wall_cling_kick_outward_speed: float = 60.0
## Upward launch target for a wall-cling kick. Faster upward momentum is preserved.
@export var wall_cling_kick_upward_speed: float = 40.0
## Entry speed where wall-cling kick mirroring begins.
@export var wall_cling_kick_entry_mirror_min_speed: float = 30.0
## Entry speed that reaches the maximum wall-cling kick mirror multipliers.
@export var wall_cling_kick_entry_mirror_max_speed: float = 175.0
## Maximum outward wall-cling kick multiplier produced by entry speed.
@export_range(1.0, 10.0, 0.01) var wall_cling_kick_entry_outward_multiplier: float = 1.8
## Maximum upward wall-cling kick multiplier produced by entry speed.
@export_range(1.0, 10.0, 0.01) var wall_cling_kick_entry_upward_multiplier: float = 1.3
## Fraction of captured vertical entry speed added to the wall-cling kick's upward target.
@export_range(0.0, 1.0, 0.01) var wall_cling_kick_vertical_entry_boost: float = 0.35
## Maximum upward speed added from wall-cling vertical entry speed.
@export var wall_cling_kick_vertical_entry_boost_limit: float = 12.0
## Outward kick speed gained per unit of current upward cling slide speed.
@export_range(0.0, 3.0, 0.01) var wall_cling_kick_upward_slide_outward_multiplier: float = 0.02
## Outward kick speed gained per unit of current downward cling slide speed.
@export_range(0.0, 3.0, 0.01) var wall_cling_kick_downward_slide_outward_multiplier: float = 0.02
## Minimum outward speed for a wall-cling kick when strength is depleted.
@export var wall_cling_kick_minimum_outward_speed: float = 6.0
## Optional wall-parallel speed top-up for a wall-cling kick. Zero disables it.
@export var wall_cling_kick_parallel_speed_target: float = 0.0
## Maximum stick-directed steering angle for a wall-cling kick.
@export_range(0.0, 30.0, 1.0) var wall_cling_kick_steering_degrees: float = 7.0
## Movement-input lock duration after a wall-cling kick.
@export var wall_cling_kick_movement_input_lock_time: float = 0.45
## Input-influence duration after the weakest wall-cling kick.
@export var wall_cling_kick_input_influence_min_time: float = 0.18
## Input-influence duration after a full-strength wall-cling kick.
@export var wall_cling_kick_input_influence_max_time: float = 0.5
## Inward input retained at the start of wall-cling kick influence.
@export_range(0.0, 1.0, 0.01) var wall_cling_kick_input_initial_inward_ratio: float = 0.0
## Outward-speed sustain duration after a wall-cling kick.
@export var wall_cling_kick_outward_sustain_time: float = 0.22
## Upward-speed sustain duration after a wall-cling kick.
@export var wall_cling_kick_upward_sustain_time: float = 0.08
## Minimum time before the wall-cling kick surface can be caught again.
@export var wall_cling_kick_recatch_delay: float = 0.16
## Separation required before the wall-cling kick surface can be caught again.
@export var wall_cling_kick_recatch_distance: float = 0.7

@export_subgroup("Surface History")
## Granted strength when returning to the most recently kicked wall orientation.
@export_range(0.0, 1.0, 0.01) var same_wall_minimum_strength: float = 0.05
## Time over which the most recent kick's similarity penalty fades away.
@export var kicked_surface_memory_time: float = 3.5
## Travel distance from the kick over which its similarity penalty fades away.
@export var kicked_surface_memory_distance: float = 600.0
## Time without a catch before the same contact may grant fresh entry assistance.
@export var catch_memory_time: float = 2.0
## Maximum distance between catches considered part of the same entry.
@export var catch_memory_distance: float = 8.0

@export_subgroup("Tic-Tac Degradation")
## Enables additional kick strength degradation during an airborne chain.
@export var tic_tac_degradation_enabled: bool = false
## Number of kicks allowed before additional chain degradation begins.
@export var tic_tac_full_strength_uses: int = 8
## Linear strength reduction per kick after the full-strength allowance.
@export_range(0.0, 1.0, 0.01) var tic_tac_strength_loss_per_use: float = 0.15
## Minimum chain strength multiplier after repeated kicks.
@export_range(0.0, 1.0, 0.01) var tic_tac_minimum_strength: float = 0.25

@export_subgroup("Presentation")
## Fallback animation command used when the matching side-specific wall-run command is empty.
@export var wall_run_animation_command: StringName = &""
## Animation command used while the wall is on the character's left side along the run direction.
@export var wall_run_left_animation_command: StringName = &"CMD_WALLRUN_LEFT"
## Animation command used while the wall is on the character's right side along the run direction.
@export var wall_run_right_animation_command: StringName = &"CMD_WALLRUN_RIGHT"
## Optional animation command for a wall cling.
@export var wall_cling_animation_command: StringName = &"CMD_WALLCLING"
## Animation command used for a wall kick.
@export var wall_kick_animation_command: StringName = &"CMD_JUMP"
## Animation command used when kicking from a wall run with the wall on the character's left.
@export var wall_kick_run_left_animation_command: StringName = &"CMD_WALLKICK_RUN_LEFT"
## Animation command used when kicking from a wall run with the wall on the character's right.
@export var wall_kick_run_right_animation_command: StringName = &"CMD_WALLKICK_RUN_RIGHT"
## Animation command used when kicking from a wall cling.
@export var wall_kick_cling_animation_command: StringName = &"CMD_WALLKICK_CLING"
## Animation command used when leaving a wall without kicking.
@export var wall_detach_animation_command: StringName = &"CMD_WALL_DETACH"
## Animation state entered after a wall kick or detachment animation finishes.
@export var wall_exit_fall_animation_command: StringName = &"FallBlend"
## Placeholder wall-kick animation duration before transitioning to the fall blendspace.
@export var wall_kick_animation_duration: float = 0.3
## Placeholder detachment animation duration before transitioning to the fall blendspace.
@export var wall_detach_animation_duration: float = 0.12
## Aligns the character model along the wall during runs and into it during clings.
@export var align_visual_to_wall: bool = true
## Preserves wall-animation contact alignment when the main collision sphere shrinks or moves.
@export var compensate_compact_collision_alignment: bool = true
## Time taken to remove wall-contact model compensation after a wall kick or detachment.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:s") var wall_collision_alignment_release_time: float = 0.12
## Momentum component used to drive wall-run animation playback speed.
@export var wall_run_animation_speed_source: WallRunAnimationSpeedSource = WallRunAnimationSpeedSource.COMBINED
## Horizontal wall-parallel speed that produces the maximum animation multiplier.
@export var wall_run_animation_horizontal_speed_for_max: float = 100.0
## Absolute vertical speed that produces the maximum animation multiplier.
@export var wall_run_animation_vertical_speed_for_max: float = 100.0
## Animation playback multiplier at zero wall-run momentum.
@export var wall_run_animation_min_speed_scale: float = 0.5
## Animation playback multiplier at or above the configured reference momentum.
@export var wall_run_animation_max_speed_scale: float = 3.35
## Half-life used to smooth wall-run animation playback-speed changes.
@export var wall_run_animation_speed_half_life: float = 0.08

@export_subgroup("Audio")
## Sound played when entering a wall cling.
@export var wall_cling_enter_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Parkour_WallCling_Enter.wav")
## Sound looped while a wall cling is actively sliding downward.
@export var wall_cling_slide_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Parkour_WallCling_Slide.wav")
## Sound played when kicking away from a wall cling.
@export var wall_cling_jump_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Parkour_WallCling_Jump.wav")
## Sound played when kicking away from a wall run.
@export var wall_run_jump_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Parkour_WallRun_Jump.wav")
## Sound played when a timed landing roll succeeds.
@export var landing_roll_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Landing_Roll.wav")
## Volume applied to all parkour sounds.
@export var parkour_sound_volume_db: float = 0.0
## Additional slide volume at the beginning of downward movement.
@export var wall_cling_slide_min_volume_db: float = -12.0
## Additional slide volume at or above the reference downward speed.
@export var wall_cling_slide_max_volume_db: float = 0.0
## Downward speed that reaches the maximum wall-cling slide volume.
@export var wall_cling_slide_speed_for_max_volume: float = 60.0

var _in_contact: bool = false
var _surface_force_cling: bool = false
var _mode: WallMode = WallMode.CLING
var _normal: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _cling_elapsed: float = 0.0
var _missing_time: float = 0.0
var _slow_time: float = 0.0
var _assistance_duration: float = 0.0
var _entry_strength: float = 1.0
var _wall_lift_phase: WallLiftPhase = WallLiftPhase.NONE
var _wall_lift_settle_elapsed: float = 0.0
var _wall_lift_settle_limit: float = 0.75
var _wall_lift_hold_remaining: float = 0.0
var _wall_lift_release_elapsed: float = 0.0
var _wall_lift_strength: float = 1.0
var _wall_lift_applied_gravity_scale: float = 1.0
var _wall_lift_effective_entry_speed: float = 0.0
var _wall_lift_entry_vertical_speed: float = 0.0
var _wall_lift_entry_parallel_gain: float = 0.0
var _wall_lift_last_grant_normal: Vector3 = Vector3.ZERO
var _wall_lift_previous_normal: Vector3 = Vector3.ZERO
var _wall_lift_previous_position: Vector3 = Vector3.ZERO
var _wall_lift_inward_turn: float = 0.0
var _wall_lift_inward_distance: float = 0.0
var _wall_lift_last_refresh_reason: StringName = &""
var _jump_buffer: float = 0.0
var _last_kick_normal: Vector3 = Vector3.ZERO
var _last_kick_position: Vector3 = Vector3.ZERO
var _last_kick_age: float = 1000.0
var _kick_separated: bool = true
var _kick_count: int = 0
var _kick_input_outward: Vector3 = Vector3.ZERO
var _kick_input_influence_elapsed: float = 0.0
var _kick_input_influence_duration: float = 0.0
var _kick_input_lock_duration: float = 0.0
var _kick_input_initial_inward_ratio: float = 0.0
var _kick_impulse_elapsed: float = 0.0
var _kick_outward_sustain_speed: float = 0.0
var _kick_upward_sustain_speed: float = 0.0
var _kick_outward_sustain_duration: float = 0.0
var _kick_upward_sustain_duration: float = 0.0
var _last_kick_recatch_delay: float = 0.0
var _last_kick_recatch_distance: float = 0.0
var _catch_history: Array[Dictionary] = []
var _contact_confirmed: bool = false
var _probe_shape: SphereShape3D = SphereShape3D.new()
var _wall_run_animation_side: int = 0
var _wall_run_animation_speed_scale: float = 1.0
var _run_parallel_speed: float = 0.0
var _wall_entry_speed: float = 0.0
var _wall_entry_vertical_speed: float = 0.0
var _cling_started_from_floor_attach: bool = false
var _wall_carve_distance_accum: float = 0.0
var _run_collision_speed_sampled: bool = false
var _dash_panel_run_lock_remaining: float = 0.0
var _dash_panel_run_lock_parallel: float = 0.0
var _dash_panel_run_lock_vertical: float = 0.0
var _dash_panel_run_mode_hold_remaining: float = 0.0
var _dash_panel_impulse_applied_this_frame: bool = false
var _dash_panel_impulse_vertical_speed: float = 0.0
var _wall_exit_animation_elapsed: float = 0.0
var _wall_exit_animation_duration: float = 0.0
var _wall_exit_animation_pending: bool = false
var _wall_exit_animation_command: StringName = &""
## Model root receiving wall-contact collision alignment compensation.
var _wall_collision_visual_root: Node3D = null
var _wall_collision_visual_offset: Vector3 = Vector3.ZERO
var _wall_exit_visual_offset: Vector3 = Vector3.ZERO
var _wall_exit_visual_elapsed: float = 0.0
var _wall_cling_slide_player: AudioStreamPlayer3D = null
var _landing_roll_input_buffer: float = 0.0
var _landing_roll_prompt_prediction: Dictionary = {}
var _wall_prompt_hit: Dictionary = {}
var _wall_prompt_contact_hit: Dictionary = {}
var _wall_prompt_contact_frame: int = -1
var _wall_prompt_probe_remaining: float = 0.0
var _wall_prompt_up: Vector3 = Vector3.UP
var _landing_roll_memory_remaining: float = 0.0
var _landing_roll_memory_normal: Vector3 = Vector3.ZERO
var _landing_roll_memory_velocity: Vector3 = Vector3.ZERO
var _landing_roll_memory_airborne_time: float = 0.0
var _landing_roll_memory_requires_airborne_time: bool = false
var _landing_roll_requires_airborne_time: bool = false
var _landing_roll_last_action_id: StringName = &""
var _landing_roll_animation_grace_until_msec: int = 0
var _rough_landing_feat_pending: bool = false
var _landing_roll_speed_benefit_cooldown_remaining: float = 0.0
var _debug_landing_roll_performed: bool = false
var _debug_landing_roll_speed_benefit: bool = false
var _debug_landing_roll_rejection_reason: StringName = &""
var _debug_landing_roll_recovered_speed: float = 0.0
var _debug_landing_roll_airborne_time: float = 0.0
var _debug_landing_roll_airborne_time_required: bool = false
var _debug_landing_roll_tangential_speed: float = 0.0
var _debug_landing_roll_effectiveness_multiplier: float = 1.0
var _debug_landing_roll_recovery_strength: float = 0.0
var _debug_landing_roll_recovery_limit: float = 0.0
var _wall_kick_coyote_remaining: float = 0.0
var _wall_kick_coyote_normal: Vector3 = Vector3.ZERO
var _wall_kick_coyote_mode: WallMode = WallMode.CLING
var _wall_kick_coyote_parallel_speed: float = 0.0
var _wall_kick_coyote_animation_side: int = 0
var _wall_kick_coyote_entry_speed: float = 0.0
var _wall_kick_coyote_entry_vertical_speed: float = 0.0
var _wall_kick_coyote_vertical_speed: float = 0.0


func _on_action_initialized() -> void:
	action_id = &"parkour"
	slot_id = &"ability_slot_07"
	input_action = slot_id
	trigger_mode = ActionTrigger.PRESSED
	can_pick_up_carryables_while_active = false
	can_execute_while_carrying = false
	shows_jump_ball = false


func blocks_shared_movement_integration() -> bool:
	return _in_contact


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func pauses_barrier_blast_depletion() -> bool:
	return _in_contact


func allows_barrier_blast_building() -> bool:
	return _in_contact and _mode == WallMode.RUN


func blocks_surface_attachment() -> bool:
	return _in_contact


func is_landing_animation_override_active() -> bool:
	if not owner_player or landing_roll_animation_command == &"":
		return false
	if owner_player._pending_anim_command == landing_roll_animation_command:
		return true
	if Time.get_ticks_msec() < _landing_roll_animation_grace_until_msec:
		return true
	if owner_player.anim_tree != null:
		var override_path: String = _landing_roll_override_path()
		if override_path != "" and owner_player.anim_tree.get(override_path.get_base_dir() + "/active"):
			return true
	if owner_player.anim_state == null:
		return false
	var current_state: StringName = owner_player.anim_state.get_current_node()
	if current_state == landing_roll_animation_command:
		return true
	if current_state != &"PARKOUR" or owner_player.anim_tree == null:
		return false
	var playback: AnimationNodeStateMachinePlayback = owner_player.anim_tree.get("parameters/StateMachine/PARKOUR/playback") as AnimationNodeStateMachinePlayback
	return playback != null and playback.get_current_node() == landing_roll_animation_command


func try_handle_animation_command(command: StringName) -> bool:
	if command != landing_roll_animation_command or owner_player == null or owner_player.anim_tree == null or landing_roll_override_parameter == "":
		return false
	var override_path: String = _landing_roll_override_path()
	if not owner_player._anim_param_exists(override_path):
		return false
	if int(owner_player.anim_tree.get(override_path)) == AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE or bool(owner_player.anim_tree.get(override_path.get_base_dir() + "/active")):
		return true
	_landing_roll_animation_grace_until_msec = Time.get_ticks_msec() + 250
	if owner_player.attached and owner_player.anim_state != null:
		owner_player.anim_state.start(&"GROUND_MACHINE", true)
	owner_player.anim_tree.set(override_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func _landing_roll_override_path() -> String:
	if landing_roll_override_parameter == "":
		return ""
	if landing_roll_override_parameter.begins_with("parameters/"):
		return landing_roll_override_parameter
	return "parameters/" + landing_roll_override_parameter


func allows_ledge_handoff() -> bool:
	return _in_contact and _mode == WallMode.CLING


func get_parkour_debug_snapshot() -> Dictionary:
	return {
		"available": true,
		"wall_lift_phase": WallLiftPhase.keys()[_wall_lift_phase],
		"wall_lift_hold_remaining": _wall_lift_hold_remaining,
		"wall_lift_hold_duration": _assistance_duration,
		"wall_lift_strength": _wall_lift_strength,
		"wall_lift_gravity_scale": _wall_lift_applied_gravity_scale,
		"wall_lift_effective_entry_speed": _wall_lift_effective_entry_speed,
		"wall_lift_entry_parallel_gain": _wall_lift_entry_parallel_gain,
		"wall_lift_settle_elapsed": _wall_lift_settle_elapsed,
		"wall_lift_settle_limit": _wall_lift_settle_limit,
		"wall_lift_inward_turn": _wall_lift_inward_turn,
		"wall_lift_last_refresh_reason": _wall_lift_last_refresh_reason,
		"landing_roll_performed": _debug_landing_roll_performed,
		"landing_roll_speed_benefit": _debug_landing_roll_speed_benefit,
		"landing_roll_rejection_reason": _debug_landing_roll_rejection_reason,
		"landing_roll_recovered_speed": _debug_landing_roll_recovered_speed,
		"landing_roll_airborne_time": _debug_landing_roll_airborne_time,
		"landing_roll_airborne_time_required": _debug_landing_roll_airborne_time_required,
		"landing_roll_tangential_speed": _debug_landing_roll_tangential_speed,
		"landing_roll_recovery_strength": _debug_landing_roll_recovery_strength,
		"landing_roll_barrier_blast_recovery_strength": landing_roll_barrier_blast_tangential_recovery,
		"landing_roll_effectiveness_multiplier": _debug_landing_roll_effectiveness_multiplier,
		"landing_roll_recovery_limit": _debug_landing_roll_recovery_limit,
		"landing_roll_barrier_blast_recovery_limit": landing_roll_barrier_blast_recovery_limit,
		"landing_roll_min_airborne_time": landing_roll_speed_benefit_min_airborne_time,
		"landing_roll_speed_benefit_cooldown": _landing_roll_speed_benefit_cooldown_remaining,
		"landing_roll_speed_benefit_cooldown_duration": landing_roll_speed_benefit_cooldown,
	}


func get_input_prompt(_context: Dictionary = {}) -> Dictionary:
	if not input_prompt_enabled or not enabled or not owner_player:
		return {}
	if not owner_player.can_offer_action_prompts() or owner_player.is_insta_shield_input_consumed():
		return {}
	if _in_contact:
		if _mode == WallMode.RUN and _can_catch(false, true):
			return {"label": "Wall Cling", "input_action": &"interact", "gesture": &"press", "contextual": false}
		return {}
	var wall_prompt: Dictionary = _get_wall_proximity_prompt()
	if not wall_prompt.is_empty():
		return wall_prompt
	if owner_player.attached:
		if _landing_roll_memory_remaining <= 0.0:
			return {}
		if _landing_roll_invalid_reason(_landing_roll_memory_normal, _landing_roll_memory_velocity, _landing_roll_memory_requires_airborne_time) != &"":
			return {}
	else:
		if _landing_roll_input_buffer > 0.0:
			return {}
		var prediction: Dictionary = _landing_roll_prompt_prediction
		if prediction.is_empty():
			return {}
		if _landing_roll_invalid_reason(prediction["normal"], prediction["incoming_velocity"], _has_landing_roll_airborne_action()) != &"":
			return {}
	return {"label": input_prompt_name if input_prompt_name else "Landing Roll", "gesture": &"press", "display_priority": 100, "contextual": true}


func get_input_prompt_stage() -> int:
	return InputPromptStage.PRIORITY


func update_landing_roll_prompt_prediction() -> void:
	_landing_roll_prompt_prediction = {}
	if not input_prompt_enabled or not enabled or not owner_player or _in_contact or _landing_roll_input_buffer > 0.0:
		return
	if not owner_player.can_offer_action_prompts():
		return
	if not SettingsManager.action_prompts_visible or not SettingsManager.hud_visible:
		return
	_landing_roll_prompt_prediction = owner_player.get_landing_prompt_prediction(landing_roll_input_window)


func _wall_prompt_state_available() -> bool:
	if not wall_proximity_prompt_enabled or not input_prompt_enabled or _in_contact or not owner_player or not owner_player.is_inside_tree():
		return false
	if not SettingsManager.action_prompts_visible or not SettingsManager.hud_visible:
		return false
	if owner_player._local_pause_enabled or owner_player.get_tree().paused or not owner_player.can_offer_action_prompts():
		return false
	if not _can_catch(owner_player.attached, true):
		return false
	if owner_player.attached:
		return absf(owner_player.surface_normal.normalized().dot(get_owner_gravity_up())) <= sin(deg_to_rad(maximum_wall_tilt_degrees))
	return not _touching_floor()


func _get_wall_proximity_prompt() -> Dictionary:
	if not _wall_prompt_state_available() or _wall_prompt_hit.is_empty():
		return {}
	var up: Vector3 = get_owner_gravity_up()
	if not _wall_prompt_up.is_equal_approx(up):
		return {}
	var hit: Dictionary = _wall_prompt_hit.duplicate()
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var position: Vector3 = hit.get("position", owner_player.global_position)
	if owner_player.global_position.distance_squared_to(position) > maxf(wall_prompt_reach, contact_reach) ** 2:
		return {}
	if hit.has("collider") and not is_instance_valid(hit["collider"]):
		return {}
	if not _wall_hit_is_eligible(hit, -normal, up, false):
		return {}
	normal = hit["normal"]
	var source: StringName = owner_player.get_current_action_id()
	var force_cling: bool = _wall_hit_forces_cling(hit) or cling_only_source_actions.has(source)
	if not _can_catch(owner_player.attached, _wall_hit_forces_cling(hit)):
		return {}
	var tangent: Vector3 = up.cross(normal).normalized()
	var mode: WallMode = _choose_entry_wall_mode(force_cling, up, tangent, owner_player.velocity.dot(tangent), normal)
	return {"label": wall_run_prompt_name if mode == WallMode.RUN else wall_cling_prompt_name, "gesture": &"hold", "display_priority": 100, "contextual": true}


func update_wall_prompt_prediction(delta: float) -> void:
	_wall_prompt_probe_remaining = maxf(_wall_prompt_probe_remaining - maxf(delta, 0.0), 0.0)
	if not _wall_prompt_state_available():
		_wall_prompt_hit = {}
		_wall_prompt_probe_remaining = 0.0
		return
	var up: Vector3 = get_owner_gravity_up()
	if not _wall_prompt_up.is_equal_approx(up):
		_wall_prompt_hit = {}
		_wall_prompt_probe_remaining = 0.0
	_wall_prompt_up = up
	if owner_player.attached:
		_wall_prompt_hit = {"normal": owner_player.surface_normal, "position": owner_player.surface_point}
		return
	if _wall_prompt_contact_frame == Engine.get_physics_frames() and not _wall_prompt_contact_hit.is_empty():
		_wall_prompt_hit = _wall_prompt_contact_hit.duplicate()
		_wall_prompt_probe_remaining = maxf(wall_prompt_probe_interval, 0.05)
		return
	if _wall_prompt_probe_remaining > 0.0:
		return
	_wall_prompt_probe_remaining = maxf(wall_prompt_probe_interval, 0.05)
	_wall_prompt_hit = _probe_wall_prompt(up)


func _probe_wall_prompt(up: Vector3) -> Dictionary:
	var reference: Vector3 = up.cross(Vector3.RIGHT)
	if reference.length_squared() < 0.001:
		reference = up.cross(Vector3.FORWARD)
	reference = reference.normalized()
	var reach: float = maxf(wall_prompt_reach, contact_reach)
	var mask: int = collision_mask_override if collision_mask_override else owner_player.collision_mask
	var space: PhysicsDirectSpaceState3D = owner_player.get_world_3d().direct_space_state
	var best: Dictionary = {}
	var best_distance: float = INF
	for index: int in range(8):
		var direction: Vector3 = reference.rotated(up, TAU * float(index) / 8.0)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(owner_player.global_position, owner_player.global_position + direction * reach, mask, [owner_player.get_rid()])
		query.hit_back_faces = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or not _wall_hit_is_eligible(hit, direction, up, false):
			continue
		if not _can_catch(false, _wall_hit_forces_cling(hit)):
			continue
		var position: Vector3 = hit["position"]
		var distance: float = owner_player.global_position.distance_squared_to(position)
		if distance < best_distance:
			best = hit
			best_distance = distance
	return best


func _record_wall_prompt_contact(hit: Dictionary) -> void:
	if not wall_proximity_prompt_enabled or not input_prompt_enabled or _in_contact or not SettingsManager.action_prompts_visible or not SettingsManager.hud_visible:
		return
	var position: Vector3 = hit["position"]
	var previous_position: Vector3 = _wall_prompt_contact_hit.get("position", Vector3.INF)
	if owner_player.global_position.distance_squared_to(position) < owner_player.global_position.distance_squared_to(previous_position):
		_wall_prompt_contact_hit = hit.duplicate()


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	return activate(context)


func can_execute(context: Dictionary = {}) -> bool:
	var grounded_wall_transition: bool = bool(context.get("grounded_wall_transition", false))
	return (
		super.can_execute(context)
		and _can_catch(grounded_wall_transition, bool(context.get("force_cling", false)))
		and context.has("wall_normal")
	)


func process_input_event(_input_name: StringName, _trigger: ActionTrigger) -> bool:
	return false


func force_wall_cling() -> bool:
	if not _in_contact or _mode != WallMode.RUN or not _can_catch(false, true):
		return false
	_enter_wall_cling(get_owner_gravity_up())
	return true


func _enter_wall_cling(up: Vector3) -> void:
	_mode = WallMode.CLING
	_wall_lift_phase = WallLiftPhase.NONE
	_dash_panel_run_lock_remaining = 0.0
	_dash_panel_run_mode_hold_remaining = 0.0
	_cling_started_from_floor_attach = false
	_wall_carve_distance_accum = 0.0
	_run_parallel_speed = 0.0
	_wall_entry_speed = owner_player.velocity.length()
	_wall_entry_vertical_speed = owner_player.velocity.dot(up)
	_cling_elapsed = max(_cling_elapsed, _elapsed)
	_play_mode_animation()
	_play_parkour_sound(wall_cling_enter_sound)


func _can_catch(allow_attached_wall: bool = false, force_cling: bool = false) -> bool:
	if not owner_player or not enabled or not owner_player._network_is_local_authority():
		return false
	if owner_player.has_method("is_insta_shield_input_consumed") and owner_player.is_insta_shield_input_consumed():
		return false
	if (owner_player.attached and not allow_attached_wall) or owner_player._is_dead or owner_player._hurt_active:
		return false
	if _ledge_action_blocks_parkour():
		return false
	if owner_player._ui_input_blocked or owner_player._local_pause_enabled or owner_player.race_in_countdown:
		return false
	if owner_player._post_ui_unblock_action_suppress_timer > 0.0:
		return false
	if owner_player._rail_active or owner_player._spline_active or owner_player._automation_active:
		return false
	if owner_player._homing_active or owner_player._lightspeed_dash_active or owner_player._fully_submerged:
		return false
	if owner_player._spring_align_timer > 0.0 or owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0:
		return false
	if (owner_player.rolling and not force_cling) or owner_player._spindash_charging or owner_player.is_carrying_object():
		return false
	if allow_attached_wall or force_cling:
		return true
	var source_action: StringName = owner_player.get_current_action_id()
	var valid_cling_only_source: bool = (
		cling_only_source_actions.has(source_action)
		and owner_player._bounce_state != owner_player.BounceState.NONE
		and owner_player._bounce_state != owner_player.BounceState.STOMP
	)
	var valid_bounce_source: bool = (
		allowed_source_actions.has(source_action)
		and (
			source_action == &"bounce"
			or source_action == &"bounce_rebound"
			or source_action == &"stomp"
			or owner_player._bounce_state == owner_player.BounceState.REBOUND
		)
	)
	if (
		owner_player._bounce_state != owner_player.BounceState.NONE
		and not valid_cling_only_source
		and not valid_bounce_source
	):
		return false
	return _in_contact or allowed_source_actions.has(source_action) or valid_cling_only_source


func prepare_priority_input(delta: float) -> bool:
	if not owner_player:
		return false
	if owner_player.attached:
		_landing_roll_requires_airborne_time = false
	else:
		_landing_roll_requires_airborne_time = _has_landing_roll_airborne_action()
	_landing_roll_last_action_id = owner_player.get_current_action_id()
	_update_wall_exit_animation(delta)
	_update_history(delta)
	_wall_kick_coyote_remaining = max(_wall_kick_coyote_remaining - max(delta, 0.0), 0.0)
	if owner_player.attached or _in_contact or owner_player._is_dead or owner_player._hurt_active:
		_clear_wall_kick_coyote()
	_landing_roll_input_buffer = max(_landing_roll_input_buffer - max(delta, 0.0), 0.0)
	var landing_roll_memory_was_active: bool = _landing_roll_memory_remaining > 0.0
	_landing_roll_memory_remaining = max(_landing_roll_memory_remaining - max(delta, 0.0), 0.0)
	if landing_roll_memory_was_active and _landing_roll_memory_remaining <= 0.0:
		if _rough_landing_feat_pending:
			_register_landing_feedback_feat(&"hard_landing")
		_clear_landing_roll_memory()
	_landing_roll_speed_benefit_cooldown_remaining = max(
		_landing_roll_speed_benefit_cooldown_remaining - max(delta, 0.0),
		0.0
	)
	if not owner_player.attached:
		_clear_landing_roll_memory()
	_kick_input_influence_elapsed += max(delta, 0.0)
	_kick_impulse_elapsed += max(delta, 0.0)
	_update_kick_impulse_sustain()
	_jump_buffer = max(_jump_buffer - delta, 0.0)
	var jump_pressed: bool = owner_player.is_ability_binding_just_pressed(&"jump", &"ability_slot_01")
	if jump_pressed and _try_coyote_wall_kick():
		return true
	var parkour_just_pressed: bool = owner_player.is_ability_binding_just_pressed(action_id, slot_id)
	if (
		owner_player.attached
		and not _in_contact
		and enabled
		and _landing_roll_memory_remaining > 0.0
		and owner_player._network_is_local_authority()
		and not owner_player._is_dead
		and not owner_player._hurt_active
		and not owner_player._ui_input_blocked
		and not owner_player._local_pause_enabled
		and not owner_player.race_in_countdown
		and parkour_just_pressed
	):
		if _apply_landing_roll(
			_landing_roll_memory_normal,
			_landing_roll_memory_velocity,
			_landing_roll_memory_airborne_time,
			_landing_roll_memory_requires_airborne_time
		):
			_clear_landing_roll_memory()
			return true
		_notify_landing_roll_speedometer_effect(&"rejected", 1.0)
		_register_landing_feedback_feat(&"rejected")
		_clear_landing_roll_memory()
	if (
		not owner_player.attached
		and not _in_contact
		and owner_player._network_is_local_authority()
		and not owner_player._is_dead
		and not owner_player._hurt_active
		and not owner_player._ui_input_blocked
		and not owner_player._local_pause_enabled
		and not owner_player.race_in_countdown
		and parkour_just_pressed
	):
		_landing_roll_input_buffer = max(landing_roll_input_window, delta)
	elif owner_player.attached:
		_landing_roll_input_buffer = 0.0
	if _try_begin_grounded_wall_parkour():
		return true
	if not _can_catch(false, true):
		_jump_buffer = 0.0
		if _in_contact:
			_leave_wall(false, false)
		return false
	var parkour_held: bool = owner_player.is_ability_binding_pressed(action_id, slot_id)
	var hit: Dictionary = _find_wall(max(contact_reach, 0.0), false, delta, not parkour_held)
	var force_cling: bool = _wall_hit_forces_cling(hit) or (_in_contact and _surface_force_cling)
	if not _can_catch(false, force_cling):
		_jump_buffer = 0.0
		if _in_contact:
			_leave_wall(false, false)
		return false
	if not force_cling and not owner_player.is_ability_binding_pressed(action_id, slot_id):
		_jump_buffer = 0.0
		if _in_contact:
			_leave_wall()
		return false
	if _touching_floor():
		_jump_buffer = 0.0
		if _in_contact:
			_enter_grounded_from_floor_contact()
		return false
	if not hit.is_empty():
		_surface_force_cling = _wall_hit_forces_cling(hit)
		if not _surface_force_cling and not owner_player.is_ability_binding_pressed(action_id, slot_id):
			if _in_contact:
				_leave_wall()
			return false
	_contact_confirmed = not hit.is_empty()
	if _contact_confirmed:
		if not _in_contact:
			execute({"wall_normal": hit["normal"], "source_action": owner_player.get_current_action_id(), "force_cling": _wall_hit_forces_cling(hit)})
		else:
			_normal = hit["normal"]
		_missing_time = 0.0
	elif _in_contact:
		_missing_time += delta
		if _missing_time > max(contact_grace_time, 0.0):
			_leave_wall()
	if jump_pressed and (_in_contact or not _find_wall(contact_reach + max(jump_buffer_reach, 0.0), true).is_empty()):
		_jump_buffer = max(jump_buffer_time, delta)
	if _in_contact and _jump_buffer > 0.0:
		_kick()
		return true
	return _in_contact or _jump_buffer > 0.0


func _try_begin_grounded_wall_parkour() -> bool:
	if not owner_player.attached:
		return false
	if not owner_player.is_surface_cling_forced() and not owner_player.is_ability_binding_just_pressed(action_id, slot_id):
		return false
	if not _can_catch(true, owner_player.is_surface_cling_forced()):
		return false
	var up: Vector3 = get_owner_gravity_up()
	var wall_normal: Vector3 = owner_player.surface_normal.normalized()
	if wall_normal.length_squared() < 0.001:
		return false
	if abs(wall_normal.dot(up)) > sin(deg_to_rad(maximum_wall_tilt_degrees)):
		return false
	var hit: Dictionary = {
		"normal": wall_normal,
		"position": owner_player.surface_point,
	}
	if not _wall_hit_is_eligible(hit, -wall_normal, up, false):
		return false
	if not execute({
		"wall_normal": hit["normal"],
		"source_action": owner_player.get_current_action_id(),
		"grounded_wall_transition": true,
		"force_cling": owner_player.is_surface_cling_forced(),
	}):
		return false
	_contact_confirmed = true
	return true


func _touching_floor() -> bool:
	var up: Vector3 = get_owner_gravity_up()
	for index: int in range(owner_player.get_slide_collision_count()):
		var collision: KinematicCollision3D = owner_player.get_slide_collision(index)
		if collision.get_normal().dot(up) > 0.7:
			return true
	return false


func resolve_movement_contact(entry_velocity: Vector3) -> void:
	if not owner_player or not owner_player._network_is_local_authority():
		return
	if _in_contact and _touching_floor():
		_enter_grounded_from_floor_contact()
		return
	if _in_contact or not _can_catch(false, true) or _touching_floor():
		return
	var hit: Dictionary = _find_wall(max(contact_reach, 0.0), false, 0.0, not owner_player.is_ability_binding_pressed(action_id, slot_id))
	if not _can_catch(false, _wall_hit_forces_cling(hit)):
		return
	if hit.is_empty():
		return
	var previous_velocity: Vector3 = owner_player.velocity
	owner_player.velocity = entry_velocity
	if not execute({"wall_normal": hit["normal"], "source_action": owner_player.get_current_action_id(), "force_cling": _wall_hit_forces_cling(hit)}):
		owner_player.velocity = previous_velocity
		return
	_contact_confirmed = true
	if _jump_buffer > 0.0:
		_kick()


func resolve_landing_momentum(landing_normal: Vector3, incoming_velocity: Vector3) -> bool:
	var input_was_buffered: bool = _landing_roll_input_buffer > 0.0
	var landing_airborne_time: float = max(owner_player._pending_landing_airborne_time, 0.0) if owner_player else 0.0
	var requires_airborne_time: bool = _landing_roll_requires_airborne_time or (owner_player != null and owner_player._jumped_from_ground)
	_landing_roll_input_buffer = 0.0
	_clear_landing_roll_memory()
	if not owner_player or not enabled:
		return false
	var ground_hit_strength: float = owner_player.get_ground_hit_strength()
	var rough_landing_intensity: float = _get_rough_landing_intensity(landing_normal, incoming_velocity, ground_hit_strength)
	var rough_landing: bool = rough_landing_intensity >= 0.0
	var invalid_reason: StringName = _landing_roll_invalid_reason(landing_normal, incoming_velocity, requires_airborne_time)
	if invalid_reason != &"":
		if input_was_buffered:
			_debug_landing_roll_performed = false
			_debug_landing_roll_speed_benefit = false
			_debug_landing_roll_rejection_reason = invalid_reason
			_debug_landing_roll_recovered_speed = 0.0
			_debug_landing_roll_airborne_time = landing_airborne_time
			_debug_landing_roll_airborne_time_required = requires_airborne_time
			_debug_landing_roll_tangential_speed = incoming_velocity.slide(landing_normal.normalized()).length()
			_notify_landing_roll_speedometer_effect(&"rejected", 1.0)
			_register_landing_feedback_feat(&"rejected")
		elif rough_landing:
			_notify_landing_roll_speedometer_effect(&"hard_landing", rough_landing_intensity)
			_register_landing_feedback_feat(&"hard_landing")
		return false
	if not input_was_buffered:
		_landing_roll_memory_remaining = max(landing_roll_post_landing_window, 0.0)
		_landing_roll_memory_normal = landing_normal.normalized()
		_landing_roll_memory_velocity = incoming_velocity
		_landing_roll_memory_airborne_time = landing_airborne_time
		_landing_roll_memory_requires_airborne_time = requires_airborne_time
		_rough_landing_feat_pending = rough_landing
		if rough_landing:
			_notify_landing_roll_speedometer_effect(&"hard_landing", rough_landing_intensity)
			if _landing_roll_memory_remaining <= 0.0:
				_register_landing_feedback_feat(&"hard_landing")
		return false
	return _apply_landing_roll(landing_normal, incoming_velocity, landing_airborne_time, requires_airborne_time)


func _has_landing_roll_airborne_action() -> bool:
	if not owner_player:
		return false
	if _landing_roll_requires_airborne_time or owner_player._jumped_from_ground:
		return true
	var current_action: StringName = owner_player.get_current_action_id()
	return (
		current_action != _landing_roll_last_action_id
		and current_action != &""
		and current_action != &"fall"
		and current_action != &"grounded"
	)


func _get_rough_landing_intensity(landing_normal: Vector3, incoming_velocity: Vector3, ground_hit_strength: float) -> float:
	var metrics: Dictionary = PlayerMath.compute_radial_landing_metrics(incoming_velocity, landing_normal)
	var approach_angle: float = float(metrics.get("angle", 0.0))
	var into_speed: float = float(metrics.get("into_speed", 0.0))
	var min_angle: float = clampf(rough_landing_min_approach_angle, 0.0, 90.0)
	var min_hit_strength: float = clampf(rough_landing_min_ground_hit_strength, 0.0, 1.0)
	if into_speed <= 0.0 or approach_angle < min_angle or ground_hit_strength < min_hit_strength or ground_hit_strength <= 0.0:
		return -1.0
	var radial_strength: float = clampf((approach_angle - min_angle) / maxf(90.0 - min_angle, 0.001), 0.0, 1.0)
	var collision_strength: float = clampf((ground_hit_strength - min_hit_strength) / maxf(1.0 - min_hit_strength, 0.001), 0.0, 1.0)
	return collision_strength * 0.7 + radial_strength * 0.3


func _landing_roll_invalid_reason(landing_normal: Vector3, incoming_velocity: Vector3, requires_airborne_time: bool) -> StringName:
	var normal: Vector3 = landing_normal.normalized()
	var up: Vector3 = get_owner_gravity_up()
	if normal.length_squared() < 0.001:
		return &"surface_normal"
	var surface_angle: float = rad_to_deg(acos(clamp(normal.dot(up), -1.0, 1.0)))
	if surface_angle > max(landing_roll_max_surface_angle_degrees, 0.0):
		return &"surface_angle"
	var impact_speed: float = max(-incoming_velocity.dot(normal), 0.0)
	var minimum_impact_speed: float = landing_roll_min_impact_speed if requires_airborne_time else landing_roll_passive_drop_min_impact_speed
	if impact_speed < max(minimum_impact_speed, 0.0):
		return &"impact_speed"
	var incoming_tangent: Vector3 = incoming_velocity.slide(normal)
	var incoming_tangent_speed: float = incoming_tangent.length()
	if incoming_tangent_speed < max(landing_roll_min_tangential_speed, 0.0):
		return &"tangential_speed"
	return &""


func _apply_landing_roll(
	landing_normal: Vector3,
	incoming_velocity: Vector3,
	airborne_time: float,
	requires_airborne_time: bool
) -> bool:
	var invalid_reason: StringName = _landing_roll_invalid_reason(landing_normal, incoming_velocity, requires_airborne_time)
	if invalid_reason != &"":
		_debug_landing_roll_rejection_reason = invalid_reason
		return false
	_debug_landing_roll_performed = true
	_debug_landing_roll_speed_benefit = false
	_debug_landing_roll_rejection_reason = &""
	_debug_landing_roll_recovered_speed = 0.0
	_debug_landing_roll_airborne_time = max(airborne_time, 0.0)
	_debug_landing_roll_airborne_time_required = requires_airborne_time
	var normal: Vector3 = landing_normal.normalized()
	var incoming_tangent: Vector3 = incoming_velocity.slide(normal)
	var incoming_tangent_speed: float = incoming_tangent.length()
	_debug_landing_roll_tangential_speed = incoming_tangent_speed
	var current_outward_speed: float = max(owner_player.velocity.dot(normal), 0.0)
	var current_tangent_speed: float = owner_player.velocity.slide(normal).length()
	var effectiveness_multiplier: float = 1.0
	if owner_player.has_method("get_combo_landing_roll_effectiveness_multiplier"):
		effectiveness_multiplier = maxf(
			float(owner_player.call("get_combo_landing_roll_effectiveness_multiplier")),
			1.0
		)
	_debug_landing_roll_effectiveness_multiplier = effectiveness_multiplier
	var barrier_blast_active: bool = (
		owner_player.has_method("is_barrier_blast_active")
		and bool(owner_player.call("is_barrier_blast_active"))
	)
	var recovery_strength: float = landing_roll_tangential_recovery
	var recovery_limit: float = landing_roll_recovery_limit
	if barrier_blast_active:
		recovery_strength = landing_roll_barrier_blast_tangential_recovery
		recovery_limit = landing_roll_barrier_blast_recovery_limit
	_debug_landing_roll_recovery_strength = recovery_strength
	_debug_landing_roll_recovery_limit = recovery_limit
	var recovery: float = min(
		incoming_tangent_speed * clamp(recovery_strength, 0.0, 1.0),
		max(recovery_limit, 0.0)
	)
	recovery *= effectiveness_multiplier
	var speed_benefit_available: bool = (
		_landing_roll_speed_benefit_cooldown_remaining <= 0.0
		and (not requires_airborne_time or airborne_time >= max(landing_roll_speed_benefit_min_airborne_time, 0.0))
	)
	if not speed_benefit_available:
		_debug_landing_roll_rejection_reason = &"cooldown" if _landing_roll_speed_benefit_cooldown_remaining > 0.0 else &"airborne_time"
	var ground_direction: Vector3 = owner_player.velocity.slide(normal)
	if ground_direction.length_squared() < 0.001:
		ground_direction = incoming_tangent
	if ground_direction.length_squared() < 0.001:
		ground_direction = owner_player._move_direction.slide(normal)
	if ground_direction.length_squared() >= 0.001:
		ground_direction = ground_direction.normalized()
		owner_player.snap_model_to_normal(normal, ground_direction)
	if speed_benefit_available:
		var recovered_speed: float = min(
			current_tangent_speed + recovery,
			incoming_velocity.length()
		)
		if recovered_speed > current_tangent_speed + 0.001 and ground_direction.length_squared() >= 0.001:
			owner_player.velocity = ground_direction * recovered_speed + normal * current_outward_speed
			_landing_roll_speed_benefit_cooldown_remaining = max(landing_roll_speed_benefit_cooldown, 0.0)
			_debug_landing_roll_speed_benefit = true
			_debug_landing_roll_recovered_speed = recovered_speed - current_tangent_speed
		else:
			_debug_landing_roll_rejection_reason = &"no_speed_gain"
	var effectiveness_strength: float = clamp(
		(effectiveness_multiplier - 1.0) / max(effectiveness_multiplier, 1.0),
		0.0,
		1.0
	)
	var success_strength: float = clamp(
		0.25 + owner_player.get_ground_hit_strength() * 0.55 + effectiveness_strength * 0.2,
		0.0,
		1.0
	)
	var feedback_result: StringName = &"accepted" if _debug_landing_roll_speed_benefit else &"rejected"
	_notify_landing_roll_speedometer_effect(feedback_result, success_strength)
	if feedback_result == &"rejected":
		_register_landing_feedback_feat(feedback_result)
	if landing_roll_animation_command != &"":
		owner_player._trigger_anim_command_immediate(landing_roll_animation_command)
	if owner_player.has_method("request_compact_collision"):
		owner_player.request_compact_collision(landing_roll_compact_collision_duration)
	_play_parkour_sound(landing_roll_sound)
	if _debug_landing_roll_speed_benefit and owner_player.has_method("register_combo_feat"):
		owner_player.register_combo_feat(&"landing_roll", "Landing Roll", 250.0, 1.0)
	return true


func _clear_landing_roll_memory() -> void:
	_landing_roll_memory_remaining = 0.0
	_landing_roll_memory_normal = Vector3.ZERO
	_landing_roll_memory_velocity = Vector3.ZERO
	_landing_roll_memory_airborne_time = 0.0
	_landing_roll_memory_requires_airborne_time = false
	_rough_landing_feat_pending = false


func _register_landing_feedback_feat(result: StringName) -> void:
	if owner_player == null or not owner_player.has_method("register_combo_feat"):
		return
	match result:
		&"rejected":
			owner_player.register_combo_feat(&"rejected_landing_roll", "Rejected Landing Roll", 0.0, 0.0)
		&"hard_landing":
			owner_player.register_combo_feat(&"rough_landing", "Rough Landing", 0.0, 0.0)


func _notify_landing_roll_speedometer_effect(
	result: StringName,
	strength: float
) -> void:
	if owner_player != null and owner_player.has_method("notify_landing_roll_speedometer_effect"):
		owner_player.notify_landing_roll_speedometer_effect(
			result,
			clamp(strength, 0.0, 1.0)
		)


func _wall_hit_forces_cling(hit: Dictionary) -> bool:
	return not hit.is_empty() and (
		owner_player._active_surface_area_has_behavior(SurfaceBehaviorMetadata.FORCE_CLING)
		or owner_player._surface_metadata_bool(hit.get("collider"), SurfaceBehaviorMetadata.FORCE_CLING, int(hit.get("shape", -1)))
	)


func is_wall_kick_prompt_available() -> bool:
	return _in_contact and _contact_confirmed


func _find_wall(reach: float, approaching_only: bool = false, prediction_time: float = 0.0, forced_only: bool = false) -> Dictionary:
	if _wall_prompt_contact_frame != Engine.get_physics_frames():
		_wall_prompt_contact_frame = Engine.get_physics_frames()
		_wall_prompt_contact_hit = {}
	var up: Vector3 = get_owner_gravity_up()
	var reference: Vector3 = up.cross(Vector3.RIGHT)
	if reference.length_squared() < 0.001:
		reference = up.cross(Vector3.FORWARD)
	reference = reference.normalized()
	var mask: int = collision_mask_override if collision_mask_override else owner_player.collision_mask
	var space: PhysicsDirectSpaceState3D = owner_player.get_world_3d().direct_space_state
	if _in_contact and _mode == WallMode.RUN and not approaching_only and not forced_only:
		var ahead_hit: Dictionary = _find_wall_run_ahead(space, up, reach, mask, prediction_time)
		if not ahead_hit.is_empty():
			return ahead_hit
	var best: Dictionary = {}
	var best_score: float = INF
	for collision_index: int in range(owner_player.get_slide_collision_count()):
		var collision: KinematicCollision3D = owner_player.get_slide_collision(collision_index)
		if collision == null:
			continue
		var collision_normal: Vector3 = collision.get_normal().normalized()
		var collision_hit: Dictionary = {
			"normal": collision_normal,
			"position": collision.get_position(),
			"collider": collision.get_collider(),
			"shape": collision.get_collider_shape_index(),
		}
		if _wall_hit_is_eligible(collision_hit, -collision_normal, up, approaching_only):
			_record_wall_prompt_contact(collision_hit)
			if forced_only and not _wall_hit_forces_cling(collision_hit):
				continue
			var collision_score: float = owner_player.global_position.distance_to(collision.get_position()) - 0.25
			if collision_score < best_score:
				best = collision_hit
				best_score = collision_score
	var direction_count: int = max(radial_probe_count, 8)
	for direction_index: int in range(direction_count):
		var direction: Vector3 = reference.rotated(up, TAU * float(direction_index) / float(direction_count))
		for height_index: int in range(-1, 2):
			var origin: Vector3 = owner_player.global_position + up * float(height_index) * max(probe_vertical_span, 0.0)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, mask, [owner_player.get_rid()])
			query.hit_back_faces = true
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty() and height_index == 0 and contact_probe_radius > 0.0:
				hit = _sweep_wall(space, origin, direction, reach, mask)
			if hit.is_empty():
				continue
			if not _wall_hit_is_eligible(hit, direction, up, approaching_only):
				continue
			_record_wall_prompt_contact(hit)
			if forced_only and not _wall_hit_forces_cling(hit):
				continue
			var position: Vector3 = hit["position"]
			var score: float = origin.distance_to(position)
			if _in_contact:
				score += (1.0 - (hit["normal"] as Vector3).dot(_normal)) * 2.0
			if score < best_score:
				best_score = score
				best = hit
	return best


func _find_wall_run_ahead(
	space: PhysicsDirectSpaceState3D,
	up: Vector3,
	reach: float,
	mask: int,
	prediction_time: float
) -> Dictionary:
	var tangent: Vector3 = up.cross(_normal).normalized()
	var run_direction: Vector3 = tangent * sign(_run_parallel_speed)
	if run_direction.length_squared() < 0.001:
		return {}
	var lookahead: float = clamp(
		abs(_run_parallel_speed) * max(prediction_time, 0.0) * max(run_curve_lookahead_time_scale, 0.0),
		0.0,
		max(run_curve_lookahead_max_distance, 0.0)
	)
	if lookahead <= 0.001:
		return {}
	var probe_direction: Vector3 = -_normal
	var probe_length: float = max(reach, 0.0) + lookahead
	var best: Dictionary = {}
	var best_distance: float = INF
	for height_index: int in range(-1, 2):
		var origin: Vector3 = (
			owner_player.global_position
			+ run_direction * lookahead
			+ up * float(height_index) * max(probe_vertical_span, 0.0)
		)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin,
			origin + probe_direction * probe_length,
			mask,
			[owner_player.get_rid()]
		)
		query.hit_back_faces = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() and height_index == 0 and contact_probe_radius > 0.0:
			hit = _sweep_wall(space, origin, probe_direction, probe_length, mask)
		if hit.is_empty() or not _wall_hit_is_eligible(hit, probe_direction, up, false):
			continue
		var hit_position: Vector3 = hit["position"]
		var distance: float = origin.distance_to(hit_position)
		if distance < best_distance:
			best = hit
			best_distance = distance
	return best


func _wall_hit_is_eligible(hit: Dictionary, probe_direction: Vector3, up: Vector3, approaching_only: bool) -> bool:
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if normal.length() < 0.001:
		return false
	normal = normal.normalized()
	if normal.dot(probe_direction) > 0.0:
		normal = -normal
	hit["normal"] = normal
	if abs(normal.dot(up)) > sin(deg_to_rad(maximum_wall_tilt_degrees)):
		return false
	var continuing_wall_run: bool = _in_contact and _mode == WallMode.RUN
	if not continuing_wall_run and owner_player.velocity.dot(normal) > maximum_outward_catch_speed:
		return false
	if approaching_only and owner_player.velocity.dot(normal) >= -0.1:
		return false
	if _in_contact:
		var normal_angle: float = rad_to_deg(acos(clamp(normal.dot(_normal), -1.0, 1.0)))
		if normal_angle > _get_continuous_wall_angle_limit(normal, up):
			return false
	if _last_kick_normal.dot(normal) > 0.95 and (_last_kick_age < _last_kick_recatch_delay or not _kick_separated):
		return false
	return true


func _sweep_wall(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, reach: float, mask: int) -> Dictionary:
	_probe_shape.radius = max(contact_probe_radius, 0.001)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _probe_shape
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = direction * max(reach - _probe_shape.radius, 0.0)
	query.collision_mask = mask
	query.exclude = [owner_player.get_rid()]
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return {}
	query.transform.origin += query.motion * fractions[1] + direction * 0.01
	query.motion = Vector3.ZERO
	var hit: Dictionary = space.get_rest_info(query)
	if not hit.is_empty():
		hit["position"] = hit["point"]
	return hit


func on_action_enter(context: Dictionary = {}) -> void:
	_clear_wall_collision_visual_offset()
	_wall_exit_visual_offset = Vector3.ZERO
	_wall_exit_animation_pending = false
	_landing_roll_input_buffer = 0.0
	_clear_wall_kick_coyote()
	owner_player._reset_drift_state()
	_normal = context["wall_normal"]
	var source_action: StringName = StringName(context.get("source_action", &""))
	var force_cling: bool = bool(context.get("force_cling", false)) or cling_only_source_actions.has(source_action)
	_surface_force_cling = bool(context.get("force_cling", false))
	if _surface_force_cling:
		owner_player._end_surface_roll()
	if owner_player._bounce_state != owner_player.BounceState.NONE or owner_player._bounce_rebound_attack_active:
		owner_player._bounce_state = owner_player.BounceState.NONE
		owner_player._bounce_rebound_attack_active = false
	_in_contact = true
	_elapsed = 0.0
	_cling_elapsed = 0.0
	_slow_time = 0.0
	_missing_time = 0.0
	_entry_strength = _surface_strength()
	var repeated: bool = false
	for entry: Dictionary in _catch_history:
		var old_normal: Vector3 = entry["normal"]
		var old_position: Vector3 = entry["position"]
		if old_normal.dot(_normal) > 0.95 and old_position.distance_to(owner_player.global_position) < catch_memory_distance:
			repeated = true
			_elapsed = max(_elapsed, float(entry["elapsed"]))
			_cling_elapsed = max(_cling_elapsed, float(entry["cling_elapsed"]))
	var up: Vector3 = get_owner_gravity_up()
	var tangent: Vector3 = up.cross(_normal).normalized()
	var horizontal_entry: Vector3 = owner_player.velocity.slide(up)
	var inward_entry_speed: float = max(-horizontal_entry.dot(_normal), 0.0)
	var parallel: float = owner_player.velocity.dot(tangent)
	var vertical: float = owner_player.velocity.dot(up)
	_mode = _choose_entry_wall_mode(force_cling, up, tangent, parallel, _normal)
	_cling_started_from_floor_attach = (
		_mode == WallMode.CLING
		and bool(context.get("grounded_wall_transition", false))
	)
	_wall_carve_distance_accum = 0.0
	if not repeated and owner_player.has_method("register_combo_feat"):
		if _mode == WallMode.RUN:
			owner_player.register_combo_feat(
				&"wall_carve",
				"Wall Carve",
				wall_carve_score,
				wall_carve_timer_add_seconds
			)
		else:
			owner_player.register_combo_feat(&"wall_cling", "Wall Cling", 125.0, 0.6)
	_wall_entry_speed = 0.0 if _cling_started_from_floor_attach else owner_player.velocity.length()
	_wall_entry_vertical_speed = 0.0 if _cling_started_from_floor_attach else vertical
	_wall_run_animation_side = 0
	_wall_run_animation_speed_scale = _get_wall_run_animation_speed_target(parallel, vertical)
	_assistance_duration = _get_wall_lift_hold_duration(
		parallel,
		vertical if wall_lift_enabled and _mode == WallMode.RUN else 0.0
	)
	if not repeated:
		if _mode == WallMode.RUN and vertical > 0.0:
			vertical += min(vertical * entry_upward_boost, entry_upward_boost_limit) * _entry_strength
		elif vertical <= 0.0:
			vertical *= 1.0 - entry_downward_damping * _entry_strength
		if _mode == WallMode.RUN:
			parallel += sign(parallel) * min(
				inward_entry_speed * clamp(entry_angle_speed_conversion, 0.0, 1.0),
				max(entry_angle_speed_conversion_limit, 0.0)
			) * _entry_strength
			parallel += sign(parallel) * min(
				abs(parallel) * max(entry_forward_boost, 0.0),
				max(entry_forward_boost_limit, 0.0)
			) * _entry_strength
			parallel = _top_up_parallel(parallel, run_entry_speed_target, _entry_strength)
	else:
		if not wall_lift_enabled or _mode != WallMode.RUN:
			_assistance_duration = 0.0
	_run_parallel_speed = parallel if _mode == WallMode.RUN else 0.0
	_dash_panel_run_lock_remaining = 0.0
	_dash_panel_run_mode_hold_remaining = 0.0
	_dash_panel_impulse_applied_this_frame = false
	owner_player.velocity = tangent * parallel + up * vertical
	_wall_lift_previous_normal = _normal
	_wall_lift_previous_position = owner_player.global_position
	_wall_lift_inward_turn = 0.0
	_wall_lift_inward_distance = 0.0
	_wall_lift_strength = _get_wall_lift_surface_strength(_normal)
	_wall_lift_entry_vertical_speed = _wall_entry_vertical_speed
	_wall_lift_entry_parallel_gain = 0.0
	_wall_lift_settle_limit = _get_wall_lift_settle_limit(vertical)
	_wall_lift_applied_gravity_scale = 1.0
	if wall_lift_enabled and _mode == WallMode.RUN and _assistance_duration > 0.0 and _wall_lift_strength > 0.001:
		_assistance_duration *= _wall_lift_strength
		_wall_lift_phase = WallLiftPhase.SETTLING
		_wall_lift_last_refresh_reason = &"entry"
		_wall_lift_last_grant_normal = _normal
	else:
		_wall_lift_phase = WallLiftPhase.NONE
	_wall_lift_settle_elapsed = 0.0
	_wall_lift_hold_remaining = 0.0
	_wall_lift_release_elapsed = 0.0
	owner_player.attached = false
	owner_player._attachment_immunity = max(owner_player._attachment_immunity, 0.1)
	owner_player.remove_coyote_jump_eligibility()
	owner_player.refresh_airborne_abilities(false)
	owner_player._jump_dash_recent_timer = 0.0
	owner_player._jumped_from_ground = false
	owner_player._falling_without_jump = true
	owner_player._begin_jump_hold_state(false)
	owner_player._gracefully_end_airborne_torque()
	if not bool(context.get("defer_air_trick_boost", false)):
		_cash_out_wall_run_air_trick_boost()
	_play_mode_animation()
	if _mode == WallMode.CLING:
		_play_parkour_sound(wall_cling_enter_sound)


func _cash_out_wall_run_air_trick_boost() -> void:
	if _mode != WallMode.RUN:
		return
	var tangent: Vector3 = get_owner_gravity_up().cross(_normal).normalized()
	owner_player.cash_out_air_trick_boost(tangent * sign(_run_parallel_speed), &"wall_run")
	_run_parallel_speed = owner_player.velocity.dot(tangent)


func physics_update_action(delta: float) -> void:
	if not _in_contact:
		return
	var motion_delta: float = owner_player.get_movement_delta(delta)
	_elapsed += delta
	_run_collision_speed_sampled = false
	_dash_panel_impulse_applied_this_frame = false
	owner_player.attached = false
	owner_player._attachment_immunity = max(owner_player._attachment_immunity, delta + 0.05)
	var up: Vector3 = get_owner_gravity_up()
	var tangent: Vector3 = up.cross(_normal).normalized()
	var parallel: float = owner_player.velocity.dot(tangent)
	var observed_horizontal_speed: float = abs(parallel)
	var vertical: float = owner_player.velocity.dot(up)
	if _mode == WallMode.RUN:
		_dash_panel_run_mode_hold_remaining = max(_dash_panel_run_mode_hold_remaining - delta, 0.0)
		if _dash_panel_run_lock_remaining > 0.0:
			_dash_panel_run_lock_remaining = max(_dash_panel_run_lock_remaining - delta, 0.0)
			if abs(parallel) < abs(_dash_panel_run_lock_parallel) or sign(parallel) != sign(_dash_panel_run_lock_parallel):
				parallel = _dash_panel_run_lock_parallel
			if _dash_panel_run_lock_vertical > 0.0:
				vertical = max(vertical, _dash_panel_run_lock_vertical)
			elif _dash_panel_run_lock_vertical < 0.0:
				vertical = min(vertical, _dash_panel_run_lock_vertical)
			_run_parallel_speed = parallel
			observed_horizontal_speed = abs(parallel)
		if sign(parallel) == sign(_run_parallel_speed) and abs(parallel) > abs(_run_parallel_speed):
			_run_parallel_speed = parallel
		parallel = _run_parallel_speed
		var animation_side: int = _get_wall_run_animation_side(parallel)
		if animation_side != _wall_run_animation_side:
			_play_mode_animation()
		var animation_speed_target: float = _get_wall_run_animation_speed_target(parallel, vertical)
		var animation_speed_blend: float = 1.0 - pow(0.5, delta / max(wall_run_animation_speed_half_life, 0.001))
		_wall_run_animation_speed_scale = lerp(
			_wall_run_animation_speed_scale,
			animation_speed_target,
			animation_speed_blend
		)
		_slow_time = _slow_time + delta if _dash_panel_run_mode_hold_remaining <= 0.0 and observed_horizontal_speed < max(run_exit_speed, 0.0) else 0.0
		if _surface_force_cling or _slow_time >= max(run_exit_delay, 0.001):
			_enter_wall_cling(up)
	if _mode == WallMode.RUN:
		_update_wall_carve(delta, abs(parallel))
		_track_wall_lift_curve(abs(parallel))
	else:
		_wall_carve_distance_accum = 0.0
	var gravity_scale: float = 1.0
	if _mode == WallMode.RUN:
		if wall_lift_enabled:
			vertical = _update_wall_lift(delta, vertical, abs(parallel))
			parallel = _run_parallel_speed
		else:
			var progress: float = clamp(_elapsed / max(_assistance_duration, 0.001), 0.0, 1.0)
			gravity_scale = lerp(1.0 - (1.0 - run_initial_gravity_scale) * _entry_strength, 1.0, smoothstep(0.0, 1.0, progress))
	else:
		_cling_elapsed += delta
		if vertical > 0.0 and not _cling_started_from_floor_attach:
			var upward_blend: float = 1.0 - pow(0.5, motion_delta / max(cling_upward_velocity_half_life, 0.001))
			vertical = lerp(vertical, 0.0, upward_blend)
		var slide_progress: float = clamp((_cling_elapsed - cling_slide_delay) / max(cling_slide_ramp_time, 0.001), 0.0, 1.0)
		gravity_scale = lerp(cling_initial_gravity_scale, cling_final_gravity_scale, slide_progress)
		gravity_scale = lerp(1.0, gravity_scale, _entry_strength)
		if _cling_started_from_floor_attach and vertical > 0.0:
			gravity_scale = max(gravity_scale, grounded_cling_upward_gravity_scale)
		var input_direction: Vector3 = _get_wall_input(up)
		var target: float = input_direction.dot(tangent) * cling_control_speed
		var blend: float = 1.0 - pow(0.5, motion_delta / max(cling_horizontal_half_life, 0.001))
		parallel = lerp(parallel, target, blend)
	if _mode != WallMode.RUN or not wall_lift_enabled:
		if not _contact_confirmed:
			gravity_scale = 1.0
		vertical -= max(owner_player.get_effective_gravity_strength(), 0.0) * max(gravity_scale, 0.0) * motion_delta
	vertical = max(vertical, -max(float(owner_player.max_fall_speed), 0.0))
	_set_wall_cling_slide_sound_active(
		_mode == WallMode.CLING
		and _contact_confirmed
		and _cling_elapsed >= cling_slide_delay
		and vertical < -0.1,
		max(-vertical, 0.0)
	)
	var wall_up: Vector3 = up.slide(_normal).normalized()
	owner_player.velocity = tangent * parallel + wall_up * (vertical / max(wall_up.dot(up), 0.1))
	if _contact_confirmed:
		var pressure_normal: Vector3 = _normal.slide(up).normalized()
		if pressure_normal.length_squared() > 0.001:
			owner_player.velocity -= pressure_normal * max(contact_pressure_speed, 0.0)


func _update_wall_lift(delta: float, vertical: float, parallel_speed: float) -> float:
	var motion_delta: float = owner_player.get_movement_delta(delta)
	var gravity: float = max(owner_player.get_effective_gravity_strength(), 0.0)
	if not _contact_confirmed:
		_wall_lift_applied_gravity_scale = 1.0
		return vertical - gravity * motion_delta
	if parallel_speed < max(run_exit_speed, 0.0):
		_begin_wall_lift_release()
	match _wall_lift_phase:
		WallLiftPhase.SETTLING:
			_wall_lift_settle_elapsed += delta
			var funnel_acceleration: float = wall_lift_downward_funnel_acceleration if vertical < 0.0 else wall_lift_upward_funnel_acceleration
			vertical = move_toward(vertical, 0.0, max(funnel_acceleration, 0.0) * _wall_lift_strength * motion_delta)
			_wall_lift_applied_gravity_scale = lerp(1.0, clamp(run_initial_gravity_scale, 0.0, 1.0), _wall_lift_strength)
			vertical -= gravity * _wall_lift_applied_gravity_scale * motion_delta
			if abs(vertical) <= max(wall_lift_settled_speed, 0.0):
				vertical = 0.0
				_wall_lift_phase = WallLiftPhase.HOLD
				_wall_lift_hold_remaining = _assistance_duration
				_apply_wall_lift_entry_carry()
				_wall_lift_last_grant_normal = _normal
			elif _wall_lift_settle_elapsed >= _wall_lift_settle_limit:
				_begin_wall_lift_release()
			return vertical
		WallLiftPhase.HOLD:
			vertical = move_toward(vertical, 0.0, max(wall_lift_hold_correction, 0.0) * _wall_lift_strength * motion_delta)
			_wall_lift_applied_gravity_scale = 1.0 - _wall_lift_strength
			vertical -= gravity * _wall_lift_applied_gravity_scale * motion_delta
			_wall_lift_hold_remaining = max(_wall_lift_hold_remaining - delta, 0.0)
			if _wall_lift_hold_remaining <= 0.0:
				_begin_wall_lift_release()
			return vertical
		WallLiftPhase.RELEASE:
			_wall_lift_release_elapsed += delta
			var release_time: float = max(wall_lift_release_time * _wall_lift_strength, 0.001)
			var release_progress: float = clamp(_wall_lift_release_elapsed / release_time, 0.0, 1.0)
			_wall_lift_applied_gravity_scale = lerp(1.0 - _wall_lift_strength, 1.0, smoothstep(0.0, 1.0, release_progress))
			vertical -= gravity * _wall_lift_applied_gravity_scale * motion_delta
			if release_progress >= 1.0:
				_wall_lift_phase = WallLiftPhase.NONE
			return vertical
	_wall_lift_applied_gravity_scale = 1.0
	return vertical - gravity * motion_delta


func _begin_wall_lift_release() -> void:
	if _wall_lift_phase == WallLiftPhase.SETTLING or _wall_lift_phase == WallLiftPhase.HOLD:
		_wall_lift_phase = WallLiftPhase.RELEASE
		_wall_lift_release_elapsed = 0.0
		_wall_lift_hold_remaining = 0.0


func _apply_wall_lift_entry_carry() -> void:
	var parallel_speed: float = abs(_run_parallel_speed)
	if parallel_speed <= 0.001:
		return
	var carry_fraction: float = wall_lift_upward_entry_parallel_carry if _wall_lift_entry_vertical_speed > 0.0 else wall_lift_downward_entry_parallel_carry
	var redirected_speed: float = abs(_wall_lift_entry_vertical_speed) * clamp(carry_fraction, 0.0, 1.0)
	var carried_speed: float = sqrt(parallel_speed * parallel_speed + redirected_speed * redirected_speed) - parallel_speed
	_wall_lift_entry_parallel_gain = min(carried_speed, max(wall_lift_entry_parallel_gain_limit, 0.0)) * _wall_lift_strength
	_run_parallel_speed += sign(_run_parallel_speed) * _wall_lift_entry_parallel_gain
	_wall_lift_entry_vertical_speed = 0.0


func _get_wall_lift_hold_duration(parallel_speed: float, vertical_entry_speed: float) -> float:
	var horizontal_speed: float = abs(parallel_speed)
	var vertical_contribution: float = min(
		abs(vertical_entry_speed) * clamp(wall_lift_vertical_entry_speed_weight, 0.0, 1.0),
		horizontal_speed * clamp(wall_lift_vertical_entry_parallel_limit, 0.0, 1.0)
	)
	_wall_lift_effective_entry_speed = horizontal_speed + vertical_contribution
	var speed_fraction: float = clamp(
		(_wall_lift_effective_entry_speed - run_entry_speed) / max(run_assistance_max_speed - run_entry_speed, 0.001),
		0.0,
		1.0
	)
	return lerp(run_assistance_min_time, run_assistance_max_time, speed_fraction)


func _get_wall_lift_settle_limit(vertical_entry_speed: float) -> float:
	var base_time: float = max(wall_lift_settle_max_time, 0.0)
	if vertical_entry_speed <= 0.0:
		return base_time
	var gravity: float = max(owner_player.get_effective_gravity_strength(), 0.0)
	var settling_rate: float = (
		max(wall_lift_upward_funnel_acceleration, 0.0) * _wall_lift_strength
		+ gravity * lerp(1.0, clamp(run_initial_gravity_scale, 0.0, 1.0), _wall_lift_strength)
	)
	var expected_time: float = max(vertical_entry_speed - max(wall_lift_settled_speed, 0.0), 0.0) / max(settling_rate, 0.001)
	return min(max(base_time, expected_time + 0.1), max(wall_lift_upward_settle_max_time, base_time))


func _get_wall_lift_surface_strength(normal: Vector3) -> float:
	if not _wall_lift_last_grant_normal:
		return 1.0
	var angle: float = rad_to_deg(acos(clamp(normal.dot(_wall_lift_last_grant_normal), -1.0, 1.0)))
	var angular_penalty: float = 1.0 - clamp(angle / 90.0, 0.0, 1.0)
	return 1.0 - angular_penalty * (1.0 - clamp(wall_lift_same_surface_minimum_strength, 0.0, 1.0))


func _track_wall_lift_curve(parallel_speed: float) -> void:
	var position: Vector3 = owner_player.global_position
	var previous_normal: Vector3 = _wall_lift_previous_normal
	_wall_lift_previous_normal = _normal
	var previous_position: Vector3 = _wall_lift_previous_position
	_wall_lift_previous_position = position
	if not wall_lift_enabled or not _contact_confirmed or not _wall_lift_last_grant_normal:
		return
	if parallel_speed < max(wall_lift_inward_refresh_speed, 0.0):
		return
	var up: Vector3 = get_owner_gravity_up()
	var tangent: Vector3 = up.cross(_normal).normalized()
	var run_direction: Vector3 = tangent * sign(_run_parallel_speed)
	if run_direction.length_squared() < 0.001:
		return
	var forward_distance: float = (position - previous_position).dot(run_direction)
	if forward_distance < 0.03:
		return
	_wall_lift_inward_distance += forward_distance
	var normal_angle: float = rad_to_deg(acos(clamp(previous_normal.dot(_normal), -1.0, 1.0)))
	if normal_angle >= 0.5:
		var normal_change: Vector3 = _normal - previous_normal
		var inward_turn: bool = normal_change.dot(run_direction) < -0.001
		_wall_lift_inward_turn = clamp(
			_wall_lift_inward_turn + normal_angle * (1.0 if inward_turn else -1.0),
			0.0,
			180.0
		)
	if _wall_lift_inward_turn < max(wall_lift_inward_refresh_angle, 90.0):
		return
	if _wall_lift_inward_distance < max(wall_lift_inward_refresh_distance, 0.0):
		return
	_assistance_duration = _get_wall_lift_hold_duration(parallel_speed, 0.0)
	_wall_lift_strength = 1.0
	_wall_lift_entry_vertical_speed = 0.0
	_wall_lift_entry_parallel_gain = 0.0
	_wall_lift_settle_limit = _get_wall_lift_settle_limit(owner_player.velocity.dot(up))
	_wall_lift_phase = WallLiftPhase.SETTLING
	_wall_lift_settle_elapsed = 0.0
	_wall_lift_hold_remaining = 0.0
	_wall_lift_release_elapsed = 0.0
	_wall_lift_last_grant_normal = _normal
	_wall_lift_inward_turn = 0.0
	_wall_lift_inward_distance = 0.0
	_wall_lift_last_refresh_reason = &"inward_turn"


func try_begin_from_dash_panel(
	panel_normal: Vector3,
	panel_direction: Vector3,
	strength: float,
	stop_momentum: bool,
	additive_mode: int,
	min_additive_launch_speed: float,
	lock_speed_enabled: bool,
	lock_speed_value: float,
	lock_speed_duration: float
) -> Dictionary:
	if _in_contact or not owner_player.is_ability_binding_pressed(action_id, slot_id):
		return {}
	if not _can_catch(owner_player.attached):
		return {}
	var up: Vector3 = get_owner_gravity_up()
	var face_normal: Vector3 = panel_normal.normalized()
	if face_normal.length_squared() < 0.001 or abs(face_normal.dot(up)) > sin(deg_to_rad(maximum_wall_tilt_degrees)):
		return {}
	var hit: Dictionary = _find_wall(max(contact_reach, 0.0))
	if hit.is_empty():
		return {}
	var wall_normal: Vector3 = hit["normal"]
	if wall_normal.dot(face_normal) < cos(deg_to_rad(45.0)):
		return {}
	var tangent: Vector3 = up.cross(wall_normal).normalized()
	var wall_up: Vector3 = up.slide(wall_normal).normalized()
	var wall_direction: Vector3 = panel_direction.slide(wall_normal).normalized()
	if tangent.length_squared() < 0.001 or wall_up.length_squared() < 0.001 or wall_direction.length_squared() < 0.001:
		return {}
	var previous_velocity: Vector3 = owner_player.velocity
	var parallel: float = previous_velocity.dot(tangent)
	var vertical: float = previous_velocity.dot(up)
	var desired_parallel: float = wall_direction.dot(tangent) * max(strength, 0.0)
	var desired_vertical: float = wall_direction.dot(up) * max(strength, 0.0)
	if stop_momentum:
		parallel = desired_parallel
		vertical = desired_vertical
	elif additive_mode == 0:
		parallel += desired_parallel
		vertical = desired_vertical
	else:
		var wall_velocity: Vector3 = previous_velocity.slide(wall_normal) + wall_direction * max(strength, 0.0)
		var along: float = wall_velocity.dot(wall_direction)
		if along < min_additive_launch_speed:
			wall_velocity += wall_direction * (min_additive_launch_speed - along)
		parallel = wall_velocity.dot(tangent)
		vertical = wall_velocity.dot(up)
	owner_player.velocity = tangent * parallel + wall_up * (vertical / max(wall_up.dot(up), 0.1))
	if not execute({
		"wall_normal": wall_normal,
		"source_action": owner_player.get_current_action_id(),
		"grounded_wall_transition": owner_player.attached,
		"defer_air_trick_boost": true,
	}):
		owner_player.velocity = previous_velocity
		return {}
	_contact_confirmed = true
	owner_player.velocity = previous_velocity
	if _mode == WallMode.RUN:
		_run_parallel_speed = previous_velocity.dot(tangent)
	return apply_dash_panel_parkour(
		panel_direction,
		strength,
		stop_momentum,
		additive_mode,
		min_additive_launch_speed,
		lock_speed_enabled,
		lock_speed_value,
		lock_speed_duration
	)


func apply_dash_panel_parkour(
	panel_direction: Vector3,
	strength: float,
	stop_momentum: bool,
	additive_mode: int,
	min_additive_launch_speed: float,
	lock_speed_enabled: bool,
	lock_speed_value: float,
	lock_speed_duration: float
) -> Dictionary:
	if not _in_contact:
		return {}
	var up: Vector3 = get_owner_gravity_up()
	var tangent: Vector3 = up.cross(_normal).normalized()
	var wall_up: Vector3 = up.slide(_normal).normalized()
	var pressure_normal: Vector3 = _normal.slide(up).normalized()
	if tangent.length_squared() < 0.001 or wall_up.length_squared() < 0.001 or pressure_normal.length_squared() < 0.001:
		return {}
	var wall_direction: Vector3 = panel_direction.slide(_normal).normalized()
	var current_parallel: float = _run_parallel_speed
	var observed_parallel: float = owner_player.velocity.dot(tangent)
	if abs(current_parallel) < 0.001 or (sign(observed_parallel) == sign(current_parallel) and abs(observed_parallel) > abs(current_parallel)):
		current_parallel = observed_parallel
	var current_vertical: float = owner_player.velocity.dot(up)
	if wall_direction.length_squared() < 0.001:
		wall_direction = tangent * (sign(current_parallel) if abs(current_parallel) > 0.001 else 1.0)
	var desired_parallel: float = wall_direction.dot(tangent) * max(strength, 0.0)
	var desired_vertical: float = wall_direction.dot(up) * max(strength, 0.0)
	var parallel: float = current_parallel
	var vertical: float = current_vertical
	if stop_momentum:
		parallel = desired_parallel
		vertical = desired_vertical
	elif additive_mode == 0:
		parallel += desired_parallel
		vertical = desired_vertical
	else:
		var wall_velocity: Vector3 = tangent * current_parallel + wall_up * (current_vertical / max(wall_up.dot(up), 0.1))
		wall_velocity += wall_direction * max(strength, 0.0)
		var along: float = wall_velocity.dot(wall_direction)
		if along < min_additive_launch_speed:
			wall_velocity += wall_direction * (min_additive_launch_speed - along)
		parallel = wall_velocity.dot(tangent)
		vertical = wall_velocity.dot(up)
	_dash_panel_run_lock_remaining = 0.0
	var speed_lock_active: bool = _mode == WallMode.RUN and lock_speed_enabled and lock_speed_duration > 0.0 and lock_speed_value > 0.0
	if speed_lock_active:
		_dash_panel_run_lock_parallel = wall_direction.dot(tangent) * lock_speed_value
		_dash_panel_run_lock_vertical = wall_direction.dot(up) * lock_speed_value
		_dash_panel_run_lock_remaining = lock_speed_duration
		if abs(parallel) < abs(_dash_panel_run_lock_parallel) or sign(parallel) != sign(_dash_panel_run_lock_parallel):
			parallel = _dash_panel_run_lock_parallel
		if _dash_panel_run_lock_vertical > 0.0:
			vertical = max(vertical, _dash_panel_run_lock_vertical)
		elif _dash_panel_run_lock_vertical < 0.0:
			vertical = min(vertical, _dash_panel_run_lock_vertical)
	if _mode == WallMode.RUN:
		_dash_panel_run_mode_hold_remaining = max(
			wall_run_dash_panel_mode_hold_time,
			lock_speed_duration if speed_lock_active else 0.0
		)
		_run_parallel_speed = parallel
	_slow_time = 0.0
	_missing_time = 0.0
	_contact_confirmed = true
	_run_collision_speed_sampled = true
	_dash_panel_impulse_applied_this_frame = true
	_dash_panel_impulse_vertical_speed = vertical
	if _mode == WallMode.RUN and abs(vertical) > max(wall_lift_settled_speed * 2.0, 5.0):
		_begin_wall_lift_release()
	owner_player.velocity = (
		tangent * parallel
		+ wall_up * (vertical / max(wall_up.dot(up), 0.1))
		- pressure_normal * max(contact_pressure_speed, 0.0)
	)
	_cash_out_wall_run_air_trick_boost()
	return {"direction": wall_direction, "up": up}


func resolve_wall_collision_velocity(
	normal: Vector3,
	_world_up: Vector3,
	entry_velocity: Vector3
) -> bool:
	if not _in_contact or _mode != WallMode.RUN:
		return false
	var up: Vector3 = get_owner_gravity_up()
	var current_tangent: Vector3 = up.cross(_normal).normalized()
	var resolved_normal: Vector3 = normal.normalized()
	if current_tangent.length_squared() < 0.001 or resolved_normal.length_squared() < 0.001:
		return false
	if resolved_normal.dot(_normal) < 0.0:
		resolved_normal = -resolved_normal
	if abs(resolved_normal.dot(up)) > sin(deg_to_rad(maximum_wall_tilt_degrees)):
		return false
	var normal_angle: float = rad_to_deg(acos(clamp(resolved_normal.dot(_normal), -1.0, 1.0)))
	if normal_angle > _get_continuous_wall_angle_limit(resolved_normal, up):
		return false
	var tangent: Vector3 = up.cross(resolved_normal).normalized()
	if tangent.length_squared() < 0.001:
		return false
	var vertical: float = _dash_panel_impulse_vertical_speed if _dash_panel_impulse_applied_this_frame else entry_velocity.dot(up)
	var wall_up: Vector3 = up.slide(resolved_normal).normalized()
	if wall_up.length_squared() < 0.001:
		return false
	if not _run_collision_speed_sampled:
		_run_parallel_speed = entry_velocity.dot(current_tangent)
		_run_collision_speed_sampled = true
	_normal = resolved_normal
	var pressure_normal: Vector3 = resolved_normal.slide(up).normalized()
	if pressure_normal.length_squared() < 0.001:
		return false
	owner_player.velocity = (
		tangent * _run_parallel_speed
		+ wall_up * (vertical / max(wall_up.dot(up), 0.1))
		- pressure_normal * max(contact_pressure_speed, 0.0)
	)
	return true


func apply_visual_orientation() -> bool:
	if not _in_contact or not align_visual_to_wall:
		_clear_wall_collision_visual_offset()
		return false
	var up: Vector3 = get_owner_gravity_up()
	var wall_up: Vector3 = up.slide(_normal).normalized()
	if wall_up.length_squared() < 0.001:
		wall_up = up
	var tangent: Vector3 = up.cross(_normal).normalized()
	var facing: Vector3 = -_normal
	if _mode == WallMode.RUN:
		var run_speed: float = _run_parallel_speed
		if abs(run_speed) <= 0.1:
			run_speed = owner_player.velocity.dot(tangent)
		if abs(run_speed) > 0.1:
			facing = tangent * sign(run_speed)
	owner_player.snap_model_to_normal(wall_up, facing)
	var visual_offset: Vector3 = Vector3.ZERO
	if compensate_compact_collision_alignment:
		visual_offset = _get_wall_collision_visual_offset()
	_set_wall_collision_visual_offset(visual_offset)
	return true


func get_compact_collision_up() -> Vector3:
	if not _in_contact:
		return Vector3.ZERO
	return get_owner_gravity_up().slide(_normal).normalized()


func _get_wall_collision_visual_offset() -> Vector3:
	var correction: Vector3 = owner_player.get_main_collision_visual_contact_offset(_normal)
	if correction.is_zero_approx():
		return Vector3.ZERO
	var center: Vector3 = owner_player.get_main_collision_world_center()
	var radius: float = owner_player.get_main_collision_world_radius()
	var reach: float = maxf(contact_reach, radius + correction.length() + owner_player.safe_margin)
	var mask: int = collision_mask_override if collision_mask_override else owner_player.collision_mask
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		center, center - _normal * reach, mask, [owner_player.get_rid()]
	)
	query.hit_back_faces = true
	var hit: Dictionary = owner_player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _normal * clampf(_get_applied_wall_collision_visual_offset().dot(_normal), 0.0, correction.length())
	var gap: float = maxf((center - (hit.position as Vector3)).dot(_normal) - radius - owner_player.safe_margin, 0.0)
	return _normal * maxf(correction.length() - gap, 0.0)


func _get_applied_wall_collision_visual_offset() -> Vector3:
	if not is_instance_valid(_wall_collision_visual_root):
		return Vector3.ZERO
	var parent: Node3D = _wall_collision_visual_root.get_parent_node_3d()
	return parent.global_basis * _wall_collision_visual_offset if parent else _wall_collision_visual_offset


func _set_wall_collision_visual_offset(world_offset: Vector3) -> void:
	if not is_instance_valid(owner_player) or not is_instance_valid(owner_player.model_root):
		_clear_wall_collision_visual_offset()
		return
	var root: Node3D = owner_player.model_root
	if _wall_collision_visual_root != root:
		_clear_wall_collision_visual_offset()
		_wall_collision_visual_root = root
	var parent: Node3D = root.get_parent_node_3d()
	var local_offset: Vector3 = parent.global_basis.inverse() * world_offset if parent else world_offset
	root.position += local_offset - _wall_collision_visual_offset
	_wall_collision_visual_offset = local_offset


func _clear_wall_collision_visual_offset() -> void:
	if is_instance_valid(_wall_collision_visual_root):
		_wall_collision_visual_root.position -= _wall_collision_visual_offset
	_wall_collision_visual_root = null
	_wall_collision_visual_offset = Vector3.ZERO


func _release_wall_collision_visual_offset(delta: float) -> void:
	if _wall_exit_visual_offset.is_zero_approx():
		return
	var action: StringName = owner_player.get_current_action_id()
	if (
		owner_player.attached or owner_player._is_dead or owner_player._hurt_active
		or not compensate_compact_collision_alignment or not align_visual_to_wall
		or not enabled or (action != &"fall" and action != &"jump")
	):
		_wall_exit_visual_offset = Vector3.ZERO
		_clear_wall_collision_visual_offset()
		return
	_wall_exit_visual_elapsed += maxf(delta, 0.0)
	var duration: float = maxf(wall_collision_alignment_release_time, 0.0)
	var progress: float = clampf(_wall_exit_visual_elapsed / duration, 0.0, 1.0) if duration else 1.0
	_set_wall_collision_visual_offset(_wall_exit_visual_offset * (1.0 - smoothstep(0.0, 1.0, progress)))
	if progress >= 1.0:
		_wall_exit_visual_offset = Vector3.ZERO
		_clear_wall_collision_visual_offset()


func _exit_tree() -> void:
	_clear_wall_collision_visual_offset()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_player) or owner_player._local_pause_enabled:
		return
	_release_wall_collision_visual_offset(delta * owner_player.get_movement_time_scale())


func get_camera_adjustment_state() -> Dictionary:
	if not _in_contact or _mode != WallMode.RUN or not _contact_confirmed:
		return {}
	var up: Vector3 = get_owner_gravity_up()
	var open_direction: Vector3 = _normal.slide(up).normalized()
	if open_direction.length_squared() < 0.001:
		return {}
	return {
		"type": &"parkour_wall_run",
		"open_direction": open_direction,
		"speed": abs(_run_parallel_speed),
	}


func influence_movement_input(direction: Vector3, gravity_up: Vector3) -> Vector3:
	if _kick_input_influence_duration <= 0.0:
		return direction
	var input_lock_time: float = max(_kick_input_lock_duration, 0.0)
	if _kick_input_influence_elapsed < input_lock_time:
		return Vector3.ZERO
	if (
		_kick_input_influence_elapsed >= input_lock_time + _kick_input_influence_duration
	):
		return direction
	var up: Vector3 = gravity_up.normalized()
	var outward: Vector3 = _kick_input_outward.slide(up).normalized()
	if outward.length() < 0.001:
		return direction
	var planar: Vector3 = direction.slide(up)
	var inward_amount: float = min(planar.dot(outward), 0.0)
	if inward_amount >= 0.0:
		return direction
	var corrected: Vector3 = planar - outward * inward_amount
	if corrected.length() < 0.001:
		corrected = outward * planar.length()
	var recovery_elapsed: float = _kick_input_influence_elapsed - input_lock_time
	var progress: float = clamp(recovery_elapsed / max(_kick_input_influence_duration, 0.001), 0.0, 1.0)
	var initial_direction: Vector3 = corrected.lerp(planar, _kick_input_initial_inward_ratio)
	var influenced: Vector3 = initial_direction.lerp(planar, smoothstep(0.0, 1.0, progress))
	return influenced + up * direction.dot(up)


func get_movement_input_strength_multiplier() -> float:
	if _kick_input_influence_duration <= 0.0:
		return 1.0
	if _kick_input_influence_elapsed < max(_kick_input_lock_duration, 0.0):
		return 0.0
	return 1.0


func get_animation_speed_multiplier() -> float:
	if not _in_contact or _mode != WallMode.RUN:
		return 1.0
	return max(_wall_run_animation_speed_scale, 0.0)


func _update_kick_impulse_sustain() -> void:
	if _kick_input_outward.length() < 0.001:
		return
	var up: Vector3 = get_owner_gravity_up()
	var outward: Vector3 = _kick_input_outward.slide(up).normalized()
	var outward_speed: float = owner_player.velocity.dot(outward)
	var vertical_speed: float = owner_player.velocity.dot(up)
	if _kick_impulse_elapsed < max(_kick_outward_sustain_duration, 0.0):
		owner_player.velocity += outward * max(_kick_outward_sustain_speed - outward_speed, 0.0)
	if _kick_impulse_elapsed < max(_kick_upward_sustain_duration, 0.0):
		owner_player.velocity += up * max(_kick_upward_sustain_speed - vertical_speed, 0.0)


func _surface_strength() -> float:
	if not _last_kick_normal:
		return 1.0
	var angle: float = rad_to_deg(acos(clamp(_normal.dot(_last_kick_normal), -1.0, 1.0)))
	var angular_penalty: float = 1.0 - clamp(angle / 90.0, 0.0, 1.0)
	var time_weight: float = 1.0 - clamp(_last_kick_age / max(kicked_surface_memory_time, 0.001), 0.0, 1.0)
	var distance: float = owner_player.global_position.distance_to(_last_kick_position)
	var distance_weight: float = 1.0 - clamp(distance / max(kicked_surface_memory_distance, 0.001), 0.0, 1.0)
	return 1.0 - angular_penalty * min(time_weight, distance_weight) * (1.0 - same_wall_minimum_strength)


func _kick(vertical_speed_override: float = NAN) -> void:
	var up: Vector3 = get_owner_gravity_up()
	var outward: Vector3 = _normal.slide(up).normalized()
	var tangent: Vector3 = up.cross(outward).normalized()
	var from_wall_run: bool = _mode == WallMode.RUN
	var kick_outward_speed: float = wall_run_kick_outward_speed if from_wall_run else wall_cling_kick_outward_speed
	var kick_upward_speed: float = wall_run_kick_upward_speed if from_wall_run else wall_cling_kick_upward_speed
	var minimum_outward_speed: float = wall_run_kick_minimum_outward_speed if from_wall_run else wall_cling_kick_minimum_outward_speed
	var parallel_speed_target: float = wall_run_kick_parallel_speed_target if from_wall_run else wall_cling_kick_parallel_speed_target
	var steering_degrees: float = wall_run_kick_steering_degrees if from_wall_run else wall_cling_kick_steering_degrees
	var influence_min_time: float = wall_run_kick_input_influence_min_time if from_wall_run else wall_cling_kick_input_influence_min_time
	var influence_max_time: float = wall_run_kick_input_influence_max_time if from_wall_run else wall_cling_kick_input_influence_max_time
	var mirror_min_speed: float = wall_run_kick_entry_mirror_min_speed if from_wall_run else wall_cling_kick_entry_mirror_min_speed
	var mirror_max_speed: float = wall_run_kick_entry_mirror_max_speed if from_wall_run else wall_cling_kick_entry_mirror_max_speed
	var maximum_outward_multiplier: float = wall_run_kick_entry_outward_multiplier if from_wall_run else wall_cling_kick_entry_outward_multiplier
	var maximum_upward_multiplier: float = wall_run_kick_entry_upward_multiplier if from_wall_run else wall_cling_kick_entry_upward_multiplier
	var vertical_entry_boost: float = wall_run_kick_vertical_entry_boost if from_wall_run else wall_cling_kick_vertical_entry_boost
	var vertical_entry_boost_limit: float = wall_run_kick_vertical_entry_boost_limit if from_wall_run else wall_cling_kick_vertical_entry_boost_limit
	var mirror_range: float = max(mirror_max_speed - mirror_min_speed, 0.001)
	var mirror_strength: float = clamp((_wall_entry_speed - mirror_min_speed) / mirror_range, 0.0, 1.0)
	kick_outward_speed *= lerp(1.0, max(maximum_outward_multiplier, 1.0), mirror_strength)
	kick_upward_speed *= lerp(1.0, max(maximum_upward_multiplier, 1.0), mirror_strength)
	var vertical_entry_bonus: float = min(
		abs(_wall_entry_vertical_speed) * max(vertical_entry_boost, 0.0),
		max(vertical_entry_boost_limit, 0.0)
	)
	var strength: float = _surface_strength()
	if tic_tac_degradation_enabled:
		var excess_uses: int = max(_kick_count - max(tic_tac_full_strength_uses, 0) + 1, 0)
		strength *= max(tic_tac_minimum_strength, 1.0 - float(excess_uses) * tic_tac_strength_loss_per_use)
	var parallel: float = _top_up_parallel(owner_player.velocity.dot(tangent), parallel_speed_target, strength)
	var current_vertical_speed: float = owner_player.velocity.dot(up) if is_nan(vertical_speed_override) else vertical_speed_override
	var vertical: float = max(owner_player.velocity.dot(up), kick_upward_speed * strength)
	if from_wall_run:
		if current_vertical_speed >= 0.0:
			vertical = max(current_vertical_speed * max(wall_run_kick_upward_speed_carry, 0.0), kick_upward_speed * strength)
		else:
			vertical = max(kick_upward_speed * strength + current_vertical_speed * max(wall_run_kick_downward_speed_carry, 0.0), 0.0)
	vertical += vertical_entry_bonus * strength
	var steering: float = clamp(_get_wall_input(up).dot(tangent), -1.0, 1.0)
	var kick_direction: Vector3 = outward.rotated(up, deg_to_rad(steering_degrees) * steering)
	var outward_speed: float = max(minimum_outward_speed / max(kick_direction.dot(outward), 0.1), kick_outward_speed * strength)
	if not from_wall_run:
		var slide_outward_bonus: float = max(current_vertical_speed, 0.0) * wall_cling_kick_upward_slide_outward_multiplier
		slide_outward_bonus += max(-current_vertical_speed, 0.0) * wall_cling_kick_downward_slide_outward_multiplier
		outward_speed += slide_outward_bonus * strength
	owner_player.velocity = tangent * parallel + kick_direction * outward_speed + up * vertical
	if owner_player.has_method("request_parkour_wall_kick_camera_assist"):
		owner_player.request_parkour_wall_kick_camera_assist(
			owner_player.velocity,
			outward_speed,
			strength
		)
	var influence_speed_t: float = clamp(
		(outward_speed - minimum_outward_speed) / max(kick_outward_speed - minimum_outward_speed, 0.001),
		0.0,
		1.0
	)
	_kick_input_outward = outward
	_kick_input_influence_elapsed = 0.0
	_kick_input_influence_duration = lerp(influence_min_time, influence_max_time, influence_speed_t)
	_kick_input_lock_duration = wall_run_kick_movement_input_lock_time if from_wall_run else wall_cling_kick_movement_input_lock_time
	_kick_input_initial_inward_ratio = wall_run_kick_input_initial_inward_ratio if from_wall_run else wall_cling_kick_input_initial_inward_ratio
	_kick_impulse_elapsed = 0.0
	_kick_outward_sustain_speed = owner_player.velocity.dot(outward)
	_kick_upward_sustain_speed = owner_player.velocity.dot(up)
	_kick_outward_sustain_duration = wall_run_kick_outward_sustain_time if from_wall_run else wall_cling_kick_outward_sustain_time
	_kick_upward_sustain_duration = wall_run_kick_upward_sustain_time if from_wall_run else wall_cling_kick_upward_sustain_time
	_last_kick_recatch_delay = wall_run_kick_recatch_delay if from_wall_run else wall_cling_kick_recatch_delay
	_last_kick_recatch_distance = wall_run_kick_recatch_distance if from_wall_run else wall_cling_kick_recatch_distance
	_last_kick_normal = _normal
	_last_kick_position = owner_player.global_position
	_last_kick_age = 0.0
	_kick_separated = false
	_kick_count += 1
	var kick_animation_command: StringName = _get_wall_kick_animation_command()
	var kick_sound: AudioStream = wall_run_jump_sound if _mode == WallMode.RUN else wall_cling_jump_sound
	_play_parkour_sound(kick_sound)
	_jump_buffer = 0.0
	owner_player._jump_requested = false
	owner_player._coyote_jump_requested = false
	owner_player._jump_dash_requested = false
	_leave_wall(false, false)
	owner_player._activate_jump_action_for_launch(&"wall_kick")
	owner_player.notify_wall_kick(_normal)
	owner_player.refresh_airborne_abilities(false)
	owner_player._jump_dash_recent_timer = 0.0
	owner_player._jumped_from_ground = true
	owner_player._falling_without_jump = false
	owner_player._begin_jump_hold_state(false)
	owner_player._attachment_immunity = max(owner_player._attachment_immunity, _last_kick_recatch_delay)
	if owner_player.has_method("register_combo_feat"):
		if from_wall_run:
			owner_player.register_combo_feat(&"wall_run_kick", "Wall Run Kick", 275.0, 1.0)
		else:
			owner_player.register_combo_feat(&"wall_kick", "Wall Kick", 225.0, 0.8)
	_start_wall_exit_animation(kick_animation_command, wall_kick_animation_duration)


func _top_up_parallel(speed: float, target: float, strength: float) -> float:
	if abs(speed) < 0.001 or target <= abs(speed):
		return speed
	return sign(speed) * lerp(abs(speed), target, strength)


func _choose_entry_wall_mode(
	force_cling: bool,
	up: Vector3,
	tangent: Vector3,
	parallel_speed: float,
	wall_normal: Vector3
) -> WallMode:
	if force_cling:
		return WallMode.CLING
	var speed: float = abs(parallel_speed)
	var bias_range: float = max(run_entry_input_bias_speed_range, 0.0)
	var forced_cling_speed: float = max(run_entry_speed - bias_range, 0.0)
	var forced_run_speed: float = max(run_entry_speed + bias_range, forced_cling_speed + 0.001)
	if speed <= forced_cling_speed:
		return WallMode.CLING
	if speed >= forced_run_speed:
		return WallMode.RUN
	var input_direction: Vector3 = _get_wall_input(up)
	if input_direction.length() < clamp(run_entry_input_deadzone, 0.0, 1.0):
		return WallMode.CLING
	input_direction = input_direction.normalized()
	var parallel_amount: float = abs(input_direction.dot(tangent))
	var normal_amount: float = abs(input_direction.dot(wall_normal))
	var wall_relative_total: float = parallel_amount + normal_amount
	if wall_relative_total <= 0.001:
		return WallMode.CLING
	var parallel_share: float = parallel_amount / wall_relative_total
	var bias_start: float = clamp(run_entry_parallel_bias_start, 0.0, 0.999)
	var bias_full: float = clamp(run_entry_parallel_bias_full, bias_start + 0.001, 1.0)
	var wall_run_bias: float = smoothstep(bias_start, bias_full, parallel_share)
	var decision_speed: float = lerp(forced_run_speed, forced_cling_speed, wall_run_bias)
	return WallMode.RUN if speed >= decision_speed else WallMode.CLING


func _get_continuous_wall_angle_limit(normal: Vector3, up: Vector3) -> float:
	if _mode != WallMode.RUN:
		return max(maximum_outward_curve_degrees, maximum_inward_curve_degrees)
	var tangent: Vector3 = up.cross(_normal).normalized()
	var run_direction: Vector3 = tangent * sign(_run_parallel_speed)
	if run_direction.length_squared() < 0.001:
		run_direction = owner_player.velocity.slide(up).normalized()
	var normal_change_along_run: float = (normal - _normal).dot(run_direction)
	if normal_change_along_run > 0.001:
		return maximum_outward_curve_degrees
	return maximum_inward_curve_degrees


func _get_wall_kick_animation_command() -> StringName:
	var command: StringName = wall_kick_cling_animation_command
	if _mode == WallMode.RUN:
		var side: int = _wall_run_animation_side
		if not side:
			side = _get_wall_run_animation_side(_run_parallel_speed)
		command = wall_kick_run_left_animation_command if side < 0 else wall_kick_run_right_animation_command
	if command == &"":
		command = wall_kick_animation_command
	return command


func _start_wall_exit_animation(command: StringName, duration: float) -> void:
	_wall_exit_animation_elapsed = 0.0
	_wall_exit_animation_duration = max(duration, 0.0)
	_wall_exit_animation_pending = wall_exit_fall_animation_command != &""
	_wall_exit_animation_command = command
	if command != &"":
		owner_player._trigger_anim_command(command)
	if _wall_exit_animation_duration <= 0.0:
		_update_wall_exit_animation(0.0)


func _update_wall_exit_animation(delta: float) -> void:
	if not _wall_exit_animation_pending:
		return
	if owner_player.attached or _in_contact:
		_wall_exit_animation_pending = false
		return
	if _ledge_action_blocks_parkour():
		_wall_exit_animation_pending = false
		return
	var action: StringName = owner_player.get_current_action_id()
	if action != &"fall" and action != &"jump":
		_wall_exit_animation_pending = false
		return
	_wall_exit_animation_elapsed += max(delta, 0.0)
	var animation_finished: bool = _wall_exit_animation_elapsed >= _wall_exit_animation_duration
	if owner_player.anim_state != null and owner_player.anim_state.get_current_node() == _wall_exit_animation_command:
		var animation_length: float = owner_player.anim_state.get_current_length()
		if animation_length > 0.001:
			animation_finished = owner_player.anim_state.get_current_play_position() >= animation_length - 0.02
	if not animation_finished:
		return
	_wall_exit_animation_pending = false
	owner_player._trigger_anim_command(wall_exit_fall_animation_command)


func _ledge_action_blocks_parkour() -> bool:
	var ledge_action: Node = owner_player._get_action_by_id(&"ledge_mantle")
	return (
		ledge_action != null
		and is_instance_valid(ledge_action)
		and ledge_action.has_method("blocks_parkour_interaction")
		and bool(ledge_action.call("blocks_parkour_interaction"))
	)


func _enter_grounded_from_floor_contact() -> void:
	var up: Vector3 = get_owner_gravity_up()
	var best_normal: Vector3 = Vector3.ZERO
	var best_point: Vector3 = owner_player.global_position
	var best_alignment: float = 0.7
	for index: int in range(owner_player.get_slide_collision_count()):
		var collision: KinematicCollision3D = owner_player.get_slide_collision(index)
		if collision == null:
			continue
		var normal: Vector3 = collision.get_normal().normalized()
		var alignment: float = normal.dot(up)
		if alignment <= best_alignment:
			continue
		best_alignment = alignment
		best_normal = normal
		best_point = collision.get_position()
	if best_normal.length_squared() < 0.001:
		_leave_wall(false, false)
		return
	owner_player.velocity = owner_player.velocity.slide(best_normal)
	owner_player.attached = true
	owner_player.surface_normal = best_normal
	owner_player.surface_point = best_point
	owner_player._prev_surface_normal = best_normal
	owner_player._attachment_immunity = 0.0
	owner_player._airborne_time = 0.0
	owner_player._is_falling = false
	owner_player._falling_without_jump = false
	owner_player._jumped_from_ground = false
	owner_player._loop_forward_dir = Vector3.ZERO
	owner_player._ground_snap_attached_this_frame = true
	owner_player._record_attach_state(best_normal, up)
	owner_player._clear_coyote_jump_window()
	owner_player._reset_fall_air_decel_ramp()
	owner_player._reset_air_top_speed_ramp()
	owner_player._clear_air_landing_align()
	owner_player._finish_spring_landing_state()
	owner_player.clear_active_action()


func _get_wall_input(up: Vector3) -> Vector3:
	var direction: Vector3 = owner_player._control_forward * owner_player._move_input.y + owner_player._control_right * owner_player._move_input.x
	return direction.slide(up).limit_length(1.0)


func _update_wall_carve(delta: float, wall_speed: float) -> void:
	_wall_carve_distance_accum += maxf(wall_speed, 0.0) * maxf(owner_player.get_movement_delta(delta), 0.0)
	var distance_interval: float = maxf(wall_carve_distance_units, 0.1)
	if _wall_carve_distance_accum < distance_interval:
		return
	_wall_carve_distance_accum -= distance_interval
	if owner_player.has_method("register_combo_feat"):
		owner_player.register_combo_feat(
			&"wall_carve",
			"Wall Carve",
			wall_carve_score,
			wall_carve_timer_add_seconds
		)


func _leave_wall(play_detach_animation: bool = true, allow_coyote_kick: bool = true) -> void:
	if allow_coyote_kick:
		_arm_wall_kick_coyote()
	if not owner_player.activate_neutral_air_action({"reason": &"parkour_exit"}):
		owner_player.clear_active_action()
	if play_detach_animation:
		_start_wall_exit_animation(wall_detach_animation_command, wall_detach_animation_duration)


func _arm_wall_kick_coyote() -> void:
	if not _in_contact or wall_kick_coyote_time <= 0.0:
		_clear_wall_kick_coyote()
		return
	_wall_kick_coyote_remaining = wall_kick_coyote_time
	_wall_kick_coyote_normal = _normal
	_wall_kick_coyote_mode = _mode
	_wall_kick_coyote_parallel_speed = _run_parallel_speed
	_wall_kick_coyote_animation_side = _wall_run_animation_side
	_wall_kick_coyote_entry_speed = _wall_entry_speed
	_wall_kick_coyote_entry_vertical_speed = _wall_entry_vertical_speed
	_wall_kick_coyote_vertical_speed = owner_player.velocity.dot(get_owner_gravity_up())


func _try_coyote_wall_kick() -> bool:
	if owner_player.attached or _in_contact or _wall_kick_coyote_remaining <= 0.0:
		return false
	if _wall_kick_coyote_normal.length_squared() < 0.001:
		_clear_wall_kick_coyote()
		return false
	_normal = _wall_kick_coyote_normal
	_mode = _wall_kick_coyote_mode
	_run_parallel_speed = _wall_kick_coyote_parallel_speed
	_wall_run_animation_side = _wall_kick_coyote_animation_side
	_wall_entry_speed = _wall_kick_coyote_entry_speed
	_wall_entry_vertical_speed = _wall_kick_coyote_entry_vertical_speed
	var vertical_speed: float = _wall_kick_coyote_vertical_speed
	_clear_wall_kick_coyote()
	_kick(vertical_speed)
	return true


func is_wall_kick_coyote_available() -> bool:
	return owner_player != null and not owner_player.attached and not owner_player._rail_active \
		and not owner_player._rail_switch_active \
		and not owner_player._spline_active and not owner_player._is_dead and not owner_player._hurt_active \
		and not owner_player._ui_input_blocked and not _in_contact \
		and _wall_kick_coyote_remaining > 0.0 and _wall_kick_coyote_normal.length_squared() >= 0.001


func _clear_wall_kick_coyote() -> void:
	_wall_kick_coyote_remaining = 0.0
	_wall_kick_coyote_normal = Vector3.ZERO
	_wall_kick_coyote_parallel_speed = 0.0
	_wall_kick_coyote_animation_side = 0
	_wall_kick_coyote_entry_speed = 0.0
	_wall_kick_coyote_entry_vertical_speed = 0.0
	_wall_kick_coyote_vertical_speed = 0.0


func on_action_exit(_next_action: CharacterAction) -> void:
	_surface_force_cling = false
	_wall_exit_visual_offset = Vector3.ZERO
	_wall_exit_visual_elapsed = 0.0
	if (
		_next_action and (_next_action.action_id == &"fall" or _next_action.action_id == &"jump")
		and not owner_player.attached and not owner_player._is_dead and not owner_player._hurt_active
		and wall_collision_alignment_release_time > 0.0
		and is_instance_valid(_wall_collision_visual_root)
	):
		_wall_exit_visual_offset = _get_applied_wall_collision_visual_offset()
		if _wall_exit_visual_offset.is_zero_approx():
			_clear_wall_collision_visual_offset()
	else:
		_clear_wall_collision_visual_offset()
	if _in_contact:
		_catch_history.append({"normal": _normal, "position": owner_player.global_position, "age": 0.0, "elapsed": _elapsed, "cling_elapsed": _cling_elapsed})
		if _catch_history.size() > 8:
			_catch_history.pop_front()
	_in_contact = false
	_contact_confirmed = false
	_wall_run_animation_side = 0
	_wall_run_animation_speed_scale = 1.0
	_run_parallel_speed = 0.0
	_wall_lift_phase = WallLiftPhase.NONE
	_wall_lift_hold_remaining = 0.0
	_dash_panel_run_lock_remaining = 0.0
	_dash_panel_run_mode_hold_remaining = 0.0
	_dash_panel_impulse_applied_this_frame = false
	_cling_started_from_floor_attach = false
	_wall_carve_distance_accum = 0.0
	_run_collision_speed_sampled = false
	_set_wall_cling_slide_sound_active(false, 0.0)


func _update_history(delta: float) -> void:
	var grounded_attachment: bool = (
		owner_player.attached
		and owner_player.surface_normal.normalized().dot(get_owner_gravity_up()) > 0.7
	)
	if grounded_attachment or owner_player._is_dead:
		reset_traversal_history()
	_last_kick_age += delta
	if not _kick_separated:
		var separation: float = (owner_player.global_position - _last_kick_position).dot(_last_kick_normal)
		_kick_separated = separation >= _last_kick_recatch_distance or _last_kick_age >= kicked_surface_memory_time
	for index: int in range(_catch_history.size() - 1, -1, -1):
		_catch_history[index]["age"] = float(_catch_history[index]["age"]) + delta
		if float(_catch_history[index]["age"]) > catch_memory_time:
			_catch_history.remove_at(index)


func refresh_airborne_abilities() -> void:
	_wall_lift_last_grant_normal = Vector3.ZERO
	_wall_lift_strength = 1.0
	_wall_lift_inward_turn = 0.0
	_wall_lift_inward_distance = 0.0
	_wall_lift_last_refresh_reason = &"airborne_refresh"


func reset_traversal_history() -> void:
	_wall_prompt_hit = {}
	_wall_prompt_contact_hit = {}
	_wall_prompt_contact_frame = -1
	_wall_prompt_probe_remaining = 0.0
	_wall_exit_visual_offset = Vector3.ZERO
	_clear_wall_collision_visual_offset()
	_last_kick_normal = Vector3.ZERO
	_wall_lift_last_grant_normal = Vector3.ZERO
	_wall_lift_phase = WallLiftPhase.NONE
	_wall_lift_strength = 1.0
	_wall_lift_applied_gravity_scale = 1.0
	_wall_lift_hold_remaining = 0.0
	_wall_lift_inward_turn = 0.0
	_wall_lift_inward_distance = 0.0
	_wall_lift_entry_vertical_speed = 0.0
	_wall_lift_entry_parallel_gain = 0.0
	_wall_lift_effective_entry_speed = 0.0
	_wall_lift_last_refresh_reason = &""
	_last_kick_age = 1000.0
	_kick_count = 0
	_kick_separated = true
	_kick_input_outward = Vector3.ZERO
	_kick_input_influence_elapsed = 0.0
	_kick_input_influence_duration = 0.0
	_kick_input_lock_duration = 0.0
	_kick_input_initial_inward_ratio = 0.0
	_kick_impulse_elapsed = 0.0
	_kick_outward_sustain_speed = 0.0
	_kick_upward_sustain_speed = 0.0
	_kick_outward_sustain_duration = 0.0
	_kick_upward_sustain_duration = 0.0
	_wall_entry_speed = 0.0
	_wall_entry_vertical_speed = 0.0
	_last_kick_recatch_delay = 0.0
	_last_kick_recatch_distance = 0.0
	_wall_exit_animation_elapsed = 0.0
	_wall_exit_animation_duration = 0.0
	_wall_exit_animation_pending = false
	_wall_exit_animation_command = &""
	_jump_buffer = 0.0
	_clear_wall_kick_coyote()
	_catch_history.clear()


func _play_mode_animation() -> void:
	var command: StringName = wall_cling_animation_command
	if _mode == WallMode.RUN:
		var up: Vector3 = get_owner_gravity_up()
		var tangent: Vector3 = up.cross(_normal).normalized()
		var parallel: float = owner_player.velocity.dot(tangent)
		_wall_run_animation_side = _get_wall_run_animation_side(parallel)
		if _wall_run_animation_side < 0:
			command = wall_run_left_animation_command
		elif _wall_run_animation_side > 0:
			command = wall_run_right_animation_command
		if command == &"":
			command = wall_run_animation_command
	if command != &"":
		owner_player._trigger_anim_command(command)


func _play_parkour_sound(sound: AudioStream) -> void:
	if sound == null or not is_instance_valid(owner_player):
		return
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.stream = sound
	player.volume_db = parkour_sound_volume_db
	player.bus = &"SFX"
	player.autoplay = true
	player.add_to_group(&"LevelTransient")
	owner_player.add_child(player)
	player.finished.connect(player.queue_free)


func _set_wall_cling_slide_sound_active(active: bool, downward_speed: float) -> void:
	if not active:
		if is_instance_valid(_wall_cling_slide_player):
			_wall_cling_slide_player.stop()
		return
	if wall_cling_slide_sound == null or not is_instance_valid(owner_player):
		return
	if not is_instance_valid(_wall_cling_slide_player):
		_wall_cling_slide_player = AudioStreamPlayer3D.new()
		_wall_cling_slide_player.name = &"ParkourWallClingSlideSFX"
		_wall_cling_slide_player.bus = &"SFX"
		owner_player.add_child(_wall_cling_slide_player)
	if _wall_cling_slide_player.stream != wall_cling_slide_sound:
		_wall_cling_slide_player.stream = wall_cling_slide_sound
	var speed_ratio: float = clamp(
		downward_speed / max(wall_cling_slide_speed_for_max_volume, 0.001),
		0.0,
		1.0
	)
	_wall_cling_slide_player.volume_db = parkour_sound_volume_db + lerp(
		wall_cling_slide_min_volume_db,
		wall_cling_slide_max_volume_db,
		speed_ratio
	)
	if not _wall_cling_slide_player.playing:
		_wall_cling_slide_player.play()


func _get_wall_run_animation_side(parallel_speed: float) -> int:
	if parallel_speed > 0.001:
		return -1
	if parallel_speed < -0.001:
		return 1
	return _wall_run_animation_side


func _get_wall_run_animation_speed_target(horizontal_speed: float, vertical_speed: float) -> float:
	var horizontal_ratio: float = clamp(
		abs(horizontal_speed) / max(wall_run_animation_horizontal_speed_for_max, 0.001),
		0.0,
		1.0
	)
	var vertical_ratio: float = clamp(
		abs(vertical_speed) / max(wall_run_animation_vertical_speed_for_max, 0.001),
		0.0,
		1.0
	)
	var momentum_ratio: float = max(horizontal_ratio, vertical_ratio)
	if wall_run_animation_speed_source == WallRunAnimationSpeedSource.HORIZONTAL:
		momentum_ratio = horizontal_ratio
	elif wall_run_animation_speed_source == WallRunAnimationSpeedSource.VERTICAL:
		momentum_ratio = vertical_ratio
	return lerp(
		max(wall_run_animation_min_speed_scale, 0.0),
		max(wall_run_animation_max_speed_scale, 0.0),
		momentum_ratio
	)

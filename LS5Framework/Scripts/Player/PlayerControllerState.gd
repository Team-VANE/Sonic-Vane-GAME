extends CharacterBody3D
class_name PlayerControllerState

@export_group("Movement Time")
## Default movement clock rate. Preserves movement tuning and scales traversal time.
## AnimationTree resources named with `_movement-time-scale=false` exclude animation playback unless a slowdown debuff is active.
@export_range(0.01, 10.0, 0.01) var movement_time_scale: float = 1.0
## Runtime movement clock multiplier for gameplay effects. Reset to 1.0 when an effect ends.
var movement_time_scale_multiplier: float = 1.0
## Slowdown multiplier for debuffs. Values below 1.0 override animation movement-clock exclusions.
var movement_time_scale_debuff_multiplier: float = 1.0
## Product of the default, gameplay, debuff, and underwater rates, limited to 0.01–10.0.
var effective_movement_time_scale: float:
	get:
		var water_scale: float = _water_logic_speed_current
		if not water_physics_enabled or not water_logic_speed_enabled or (_automation_active and _automation_ignore_water_physics):
			water_scale = 1.0
		var combined_scale: float = movement_time_scale * movement_time_scale_multiplier * movement_time_scale_debuff_multiplier * water_scale
		if not is_finite(combined_scale):
			return 1.0
		return clampf(combined_scale, 0.01, 10.0)

var _movement_tick_scale: float = 1.0
var _movement_real_delta: float = 0.0
var _movement_tick_active: bool = false
var _movement_tick_debuff_active: bool = false


# Serialized player configuration and shared runtime state.
# Character scenes inherit these properties through the main controller.

signal item_resource_changed(resource_id: StringName, previous_amount: float, current_amount: float)
signal item_collected(item_id: StringName, amount: float)
signal speed_shoes_changed(active: bool, remaining_time: float)
signal invincibility_changed(active: bool, remaining_time: float)


const CharacterActionType = preload("res://LS5Framework/Scripts/Player/character_action.gd")
const DrownedActionType = preload("res://LS5Framework/Scripts/Player/drowned_action.gd")
const LIGHTSPEED_RING_GROUP: StringName = &"LightSpeedDashRing"
const WATER_SURFACE_RAY_LAYER: int = 32
const SURFACE_METADATA = preload("res://LS5Framework/Scripts/World/SurfaceBehaviorMetadata.gd")
const SURFACE_ATTACH_MAX_ANGLE_META: StringName = SURFACE_METADATA.ATTACH_LIMIT
const SURFACE_DAMAGE_AMOUNT_META: StringName = SURFACE_METADATA.DAMAGE_AMOUNT
const SURFACE_DEATH_META: StringName = SURFACE_METADATA.DEATH
const SURFACE_NO_SLOPE_GRAVITY_META: StringName = SURFACE_METADATA.NO_SLOPE_GRAVITY
const SURFACE_NO_DETACH_META: StringName = SURFACE_METADATA.NO_DETACH
const SURFACE_STICKY_META: StringName = SURFACE_METADATA.STICKY
const SURFACE_FORCE_ROLL_META: StringName = SURFACE_METADATA.FORCE_ROLL
const SURFACE_NO_JUMP_META: StringName = SURFACE_METADATA.NO_JUMP
const SURFACE_NO_COYOTE_JUMP_META: StringName = SURFACE_METADATA.NO_COYOTE_JUMP
const SURFACE_NO_ROLL_META: StringName = SURFACE_METADATA.NO_ROLL
const SURFACE_NO_DRIFT_META: StringName = SURFACE_METADATA.NO_DRIFT

enum JumpAnimationMode {
	STANDARD,
	FALL_BLEND,
}

# PlayerController owns the execution pipeline and delegates bounded systems to modules.
# This base retains the serialized scene schema and runtime state shared by those systems.

# -----------------------------------------------------------
# NODE REFERENCES
# -----------------------------------------------------------
@export_group("Setup")
@export_subgroup("Node References")

## Camera node controlling view direction.
@export var camera: Camera3D

## Camera rig (source of yaw). Optional; falls back to camera parent if not set.
@export var camera_rig: Node3D

## Model root node used for visual orientation.
@export var model_root: Node3D

## Ground RayCast3D used for surface-follow while attached.
@export var ground_ray: RayCast3D

## Main movement sphere resized during compact collision states.
@export var main_collision_shape: CollisionShape3D

## Radius removed from the main sphere during compact collision states, in player units.
@export_range(0.0, 1.9, 0.01, "or_greater") var compact_sphere_radius_reduction: float = 0.0

## Upper body collision used only when standing clearance is available.
@export var standing_collision_shape: CollisionShape3D

## Maximum sideways distance used to make room for an uncurling collision shape.
@export_range(0.0, 2.0, 0.01, "or_greater") var uncurl_wall_push_max_distance: float = 0.6

## Continuous clearance required before releasing obstruction-forced rolling. Zero disables the delay.
@export_range(0.0, 0.5, 0.01, "or_greater") var standing_clearance_release_time: float = 0.1

## Maximum shallow overlap accepted beneath the current moving support, limited by the recovery margin.
@export_range(0.0, 0.1, 0.001, "or_greater") var moving_support_contact_tolerance: float = 0.02

## Lower sphere region excluded from standing obstruction checks against the confirmed support. Measured in full sphere radii above its bottom; zero disables the exemption.
@export_range(0.0, 1.0, 0.05) var standing_support_foot_fraction: float = 1.0

var _compact_collision_timer: float = 0.0
var _standing_clearance_latched: bool = false
var _standing_clearance_clear_time: float = 0.0
var _standing_clearance_sample_frame: int = -1
## Body and shape supplying confirmed collision support.
var _collision_support_body: PhysicsBody3D
var _collision_support_shape: int = -1
var _collision_support_local_normal: Vector3 = Vector3.ZERO
var _collision_support_local_point: Vector3 = Vector3.ZERO
var _standing_collision_initialized: bool = false
var _standing_collision_enabled: bool = false
var _standing_shape_base_transform: Transform3D = Transform3D.IDENTITY
var _standing_shape_last_transform: Transform3D = Transform3D.IDENTITY
var _main_sphere_initialized: bool = false
var _main_sphere_compact: bool = false
var _main_sphere_base_transform: Transform3D = Transform3D.IDENTITY
var _main_sphere_last_transform: Transform3D = Transform3D.IDENTITY
var _main_sphere_base_radius: float = 0.0
var _collision_attached_last_move: bool = false
var _movement_sphere_contact: Dictionary = {}
var _movement_object_contact_handled: bool = false
var _collision_support_normal: Vector3 = Vector3.ZERO

## Optional HUD instance used for player-facing UI updates.
@export var hud: Node

## Optional respawn transform.
@export var respawn_point: Node3D

## Jump ball effect shown around airborne attacking players.
@export var jump_ball: Node3D

@export var anim_tree: AnimationTree
var anim_state: AnimationNodeStateMachinePlayback
var ground_state: AnimationNodeStateMachinePlayback
var _carry_overlay_state: AnimationNodeStateMachinePlayback

## Skeleton containing the carry bone. If empty, the first Skeleton3D under model_root is used.
@export var carry_skeleton: Skeleton3D
## Bone used as the target transform for carried objects.
@export var carry_bone_name: StringName = &"hand_r"
## Optional bone whose axes orient carried objects while carry_bone_name continues to anchor their position.
@export var carry_orientation_bone_name: StringName = &""
## Local adjustment applied to the carried object. Position uses the carry bone axes; rotation uses the orientation bone axes when set.
@export var carry_bone_offset: Transform3D = Transform3D.IDENTITY
## Node used as the target transform for carried objects when no carry bone is set.
@export var carry_anchor: Node3D

@export var control_anchor: Node3D
@export var jump_dash_trail: Node3D

@export_subgroup("Character Profile")
## Packaged defaults used to resolve this character's user-customizable settings and loadout.
@export var character_settings_profile: CharacterSettingsProfile

# -----------------------------------------------------------
# MODULES (COMPOSITION)
# -----------------------------------------------------------
# Bridge: helper objects operate on this player's state; they do not own nodes.
var _audio_module = null
var _item_effects_module = null
var _anim_module = null
var _model_module = null
var _ui_module = null
var _network_module = null
var _water_module = null
var _gravity_module = null
var _action_compatibility = null
var _targeting_module = null
var _buddy_module = null
var _effects_module = null
var _respawn_module = null
var _rail_module = null
var _external_motion_module = null
var _debug_module = null
var _carry_module = null
var _combat_module = null
var _surface_module = null
var _movement_correction_module = null
var _ability_input_router: PlayerAbilityInputRouter = null
var _preemptive_profile_input_consumed: bool = false

@export_group("Buddy AI")
@export_subgroup("General")
## Directory where CHAR_*.tres character docs live for buddy character selection.
@export var buddy_character_data_dir: String = "res://LS5Framework/Characters"
## Local offset used when spawning the buddy near this player.
@export var buddy_spawn_offset: Vector3 = Vector3(5, 3, 5)
## Enables local buddy spawning for this player.
@export var buddy_enable: bool = true

@export_subgroup("Movement/Ranges")
@export var buddy_mimic_jump_range: float = 18.0
@export var buddy_mimic_roll_range: float = 18.0
@export var buddy_obstacle_jump_range: float = 20.0
@export var buddy_spawn_teleport_distance: float = 275.0
@export var buddy_spawn_teleport_height: float = 2.2

@export_subgroup("Movement/Mimic Scaling")
@export var buddy_mimic_jump_range_max: float = 80.0
@export var buddy_mimic_roll_range_max: float = 80.0
@export var buddy_mimic_scale_speed_for_max: float = 200.0
@export var buddy_mimic_scale_exponent: float = 1.0

@export_subgroup("Movement/Spacing")
@export var buddy_crowd_slow_enabled: bool = true
@export var buddy_crowd_slow_start_distance: float = 2.0
@export var buddy_crowd_slow_full_distance: float = 1.0
@export var buddy_crowd_slow_multiplier_min: float = 0.65
@export var buddy_crowd_slow_leader_speed_threshold: float = 1.5

@export_subgroup("Movement/Catch Up")
@export var buddy_catchup_start_distance: float = 2.0
@export var buddy_catchup_full_distance: float = 45.0
@export var buddy_catchup_multiplier_max: float = 40.0
@export var buddy_catchup_exponent: float = 4.0

@export_subgroup("Synchronization/Spawn")
@export var buddy_spawn_sync_enabled: bool = true
@export var buddy_spawn_sync_copy_rotation: bool = true
@export var buddy_spawn_sync_copy_velocity: bool = true

@export_group("Respawn")
@export_subgroup("Checkpoint")
@export var checkpoint_enabled: bool = true
@export_subgroup("Enemy Targeting Grace")
## Time after spawning or respawning before enemies may target this player.
@export_range(0.0, 10.0, 0.05) var enemy_targeting_spawn_grace_sec: float = 1.0

var _buddy_instance = null
var _buddy_jump_mimic_active: bool = false
var _buddy_last_sent_bb_gauge: float = -1.0
var _buddy_last_sent_bb_active: bool = false
var _buddy_last_sent_mimic_jump_range: float = -1.0
var _buddy_last_sent_mimic_roll_range: float = -1.0
var _ground_snap_attached_this_frame: bool = false

# Last activated checkpoint (overwrites previous).
var _checkpoint_active: bool = false
var _checkpoint_transform: Transform3D = Transform3D.IDENTITY
var _checkpoint_respawn_speed: float = 0.0
var _checkpoint_respawn_dir: Vector3 = Vector3.ZERO
var _checkpoint_last_source_id: int = 0
var _enemy_targeting_spawn_grace_deadline_msec: int = 0
var _enemy_targeting_spawn_input_received: bool = false

@export_group("Movement")
@export_subgroup("Grounding/Snap Recovery")
@export var ground_snap_fix_enabled: bool = true
## Re-attaches when floor support exists but the custom grounded state was missed.
@export var grounded_state_reconcile_enabled: bool = true
## Maximum floor angle accepted by grounded-state reconciliation.
@export var grounded_state_reconcile_max_angle_deg: float = 85.0
## Maximum upward speed allowed when reconciling grounded state.
@export var grounded_state_reconcile_max_up_speed: float = 1.0
@export var ground_snap_max_distance: float = 0.25
@export var ground_snap_ignore_attachment_immunity: bool = true

# -----------------------------------------------------------
# MOVEMENT PARAMETERS
# -----------------------------------------------------------
@export_subgroup("Core")

## Global up direction opposite gravity. This can be changed by volumes or gameplay systems.
@export var gravity_up: Vector3 = Vector3.UP

@export_subgroup("Grounding/Landing")

## Global scale on how much of the tangential component is kept.
## 1.0 = keep exactly the tangential speed, 0.5 = keep half, etc.
@export var landing_tangent_retention_scale: float = 1.0

## Maximum floor angle considered valid landing (deg).
@export var landing_floor_max_angle_deg: float = 85.0

## How strongly floor-ish surfaces keep tangential speed (old behavior)
@export var landing_momentum_scale: float = 1.0

## Below this tilt angle, we don't convert vertical speed into along-slope speed.
@export var landing_convert_min_tilt_deg: float = 10.0

## At / above this tilt angle, we convert (almost) all vertical speed into tangential.
## Think deep bowls, steep ramps, loop bottoms, etc.
@export var landing_convert_max_tilt_deg: float = 70.0

## Scale for how much vertical speed is added into tangential on steep slopes.
@export var landing_vertical_to_tangent_scale: float = 1.0

## Maximum incoming tangential speed that can be stopped on a neutral-input landing.
@export var landing_stop_speed_threshold: float = 16.0

## Maximum angle from gravity-up where a neutral-input low-speed landing stops the player.
@export_range(0.0, 89.0, 0.5) var stationary_landing_max_angle_deg: float = 30.0

## Below this slope angle (deg) we do not convert downward speed into ground speed.
@export var landing_min_slope_deg: float = 30.0

## At or above this slope angle (deg) we convert as much as possible.
@export var landing_max_slope_deg: float = 90.0

## Angle where we start to keep any speed at all (in degrees).
@export var landing_min_tilt_deg: float = 0.0

## Angle where we keep *full* incoming speed (e.g. steep loop / ceiling).
@export var landing_full_tilt_deg: float = 90.0

## Global scale on retained speed (1.0 = keep exactly what we decide, <1.0 = softer).
@export var landing_global_scale: float = 1.0

## How much of your speed you keep on a perfectly flat floor (0 = stop dead).
@export var landing_floor_retention_scale: float = 1.0
## Impact speed where the reusable ground-hit strength begins rising above zero.
@export_range(0.0, 300.0, 0.1, "or_greater") var ground_hit_min_speed: float = 30.0
## Impact speed where the reusable ground-hit strength reaches one.
@export_range(0.0, 300.0, 0.1, "or_greater") var ground_hit_full_speed: float = 120.0
## Ground-hit strength required to select the hard-landing animation state.
@export_range(0.0, 1.0, 0.01) var ground_hit_hard_threshold: float = 0.65


@export_subgroup("Speed/Acceleration")

## Speed reached by running on flat.
@export_storage var run_top_speed: float = 110.0

## Speed reached by running on flat while walk input is held.
@export_storage var walk_top_speed: float = 22.0

## Speed reached by running on flat while airborne (soft cap).
@export var air_top_speed: float = 110.0

## Absolute maximum lateral speed (slopes, launches, etc.).
@export var max_speed: float = 320.0
## Lerp speed used to restore the functional maximum speed after an override ends.
## Set to 0 to restore the configured maximum speed immediately.
@export_range(0.0, 100.0) var max_speed_override_recovery_lerp_speed: float = 8.0

@export_group("Movement Correction")

@export_subgroup("Activation")
## Enables predictive movement correction during ordinary player-controlled movement.
@export var movement_correction_enabled: bool = true
## Allows correction while the player is airborne.
@export var movement_correction_airborne_enabled: bool = false
## Prevents movement correction from competing with automation guidance.
@export var movement_correction_block_during_automation: bool = true
## Minimum lateral speed required for movement correction.
@export var movement_correction_min_speed: float = 20.0
## Lateral speed where correction reaches its full configured strength.
@export var movement_correction_full_strength_speed: float = 140.0

@export_subgroup("Prediction")
## Seconds of travel used to extend correction probes with speed.
@export var movement_correction_lookahead_time: float = 0.16
## Minimum forward probe distance in player collision radii.
@export var movement_correction_min_lookahead_radii: float = 2.0
## Maximum forward probe distance in player collision radii.
@export var movement_correction_max_lookahead_radii: float = 10.0
## Side probe distance in player collision radii.
@export var movement_correction_side_probe_radii: float = 2.25
## Height of wall probes above the attached surface in player collision radii.
@export var movement_correction_probe_height_radii: float = 0.35
## Number of wall samples distributed along the predicted path.
@export_range(1, 8, 1) var movement_correction_wall_sample_count: int = 3
## Skips wall rays when a bounds query finds no bodies or correction areas along the probe paths.
@export var movement_correction_empty_space_check_enabled: bool = true
## Maximum absolute wall-normal alignment with player-up accepted as a wall.
@export_range(0.0, 1.0, 0.01) var movement_correction_wall_max_up_dot: float = 0.65

@export_subgroup("Distance Response")
## Maximum correction multiplier reached immediately beside a detected surface.
@export var movement_correction_near_surface_multiplier: float = 3.0
## Controls how tightly the added correction strength is concentrated near a surface.
@export var movement_correction_near_surface_power: float = 2.0

@export_subgroup("Terrain Walls")
## Enables correction away from ordinary terrain walls.
@export var movement_correction_terrain_enabled: bool = true
## Physics layers used for terrain wall and ledge probes.
## Zero uses ground-ray layers plus non-alignable collision.
@export_flags_3d_physics var movement_correction_terrain_collision_mask: int = 0
## Strength multiplier for ordinary terrain wall correction.
@export var movement_correction_terrain_strength: float = 1.0

@export_subgroup("Correction Surfaces")
## Enables non-blocking movement-correction collision surfaces.
@export var movement_correction_surfaces_enabled: bool = true
## Physics layers containing non-blocking movement-correction surfaces.
@export_flags_3d_physics var movement_correction_surface_collision_mask: int = 1 << 8
## Strength multiplier for movement-correction surfaces.
@export var movement_correction_surface_strength: float = 1.0

@export_subgroup("Ledges")
## Enables correction toward supported terrain when only one side approaches a ledge.
@export var movement_correction_ledges_enabled: bool = false
## Strength multiplier for asymmetric ledge correction.
@export var movement_correction_ledge_strength: float = 0.35
## Extra support-probe depth in player collision radii.
@export var movement_correction_ledge_probe_depth_radii: float = 1.0
## Forward distance used by ledge probes as a fraction of current lookahead.
@export_range(0.0, 1.0, 0.01) var movement_correction_ledge_lookahead_ratio: float = 0.65
## Minimum support-normal alignment with player-up accepted as ground.
@export_range(-1.0, 1.0, 0.01) var movement_correction_ledge_min_support_dot: float = 0.35

@export_subgroup("Push")
## Correction acceleration at the minimum activation speed.
@export var movement_correction_low_speed_accel: float = 35.0
## Correction acceleration at full-strength speed.
@export var movement_correction_high_speed_accel: float = 150.0
## Maximum heading change contributed by correction each second.
@export var movement_correction_max_turn_deg_per_sec: float = 90.0
## Response speed used to smooth correction direction and strength.
@export var movement_correction_response: float = 12.0
## Correction multiplier while grounded without rolling or drifting.
@export var movement_correction_neutral_grounded_multiplier: float = 1.0
## Correction multiplier while drifting.
@export var movement_correction_drift_multiplier: float = 1.25
## Correction multiplier while rolling.
@export var movement_correction_roll_multiplier: float = 0.85
## Correction multiplier when movement input points toward danger.
@export_range(0.0, 1.0, 0.01) var movement_correction_input_toward_multiplier: float = 0.25
## Correction multiplier when movement input points away from danger.
@export var movement_correction_input_away_multiplier: float = 1.35
## Maximum combined terrain, correction-surface, and ledge influence.
@export var movement_correction_max_combined_strength: float = 1.5

@export_subgroup("Debug")
## Draws movement-correction probes and the resulting push in the player debug view.
@export var movement_correction_debug_guides_enabled: bool = true

@export_group("Movement")
@export_subgroup("Speed/Acceleration")
## Ground soft-cap slowdown strength above run top speed.
@export var top_speed_slowdown_strength: float = 0.215

## Airborne soft-cap slowdown strength above air top speed.
@export var air_top_speed_slowdown_strength: float = 0.215

## Optional multiplier curve for top speed slowdown strength by lateral speed.
## X: lateral speed, Y: strength multiplier.
@export var top_speed_slowdown_strength_curve: Curve

## Optional multiplier curve for airborne top speed slowdown by lateral speed.
## X: lateral speed, Y: strength multiplier.
@export var air_top_speed_slowdown_strength_curve: Curve

## Ground acceleration curve.
## X: lateral speed, Y: acceleration (units/sec^2).
@export_storage var ground_accel_curve: Curve

## Ground acceleration curve while walk input is held.
## If unset, defaults to ground_accel_curve.
@export_storage var walk_ground_accel_curve: Curve

## Air acceleration curve.
## X: lateral speed, Y: acceleration (units/sec^2).
@export var air_accel_curve: Curve

## Ground deceleration when no input (still lateral-only).
@export_storage var decel: float = 35.0

## Ground deceleration by lateral speed.
## X: lateral speed, Y: deceleration (units/sec^2). Overrides decel when assigned.
@export_storage var ground_decel_curve: Curve

## Air deceleration used when no curve is assigned.
@export var air_decel: float = 32.0

## Air deceleration by gravity-up horizontal speed.
## X: gravity-up horizontal speed, Y: deceleration (units/sec^2). Overrides air_decel when assigned.
@export var air_decel_curve: Curve

@export_subgroup("Speed/Release Deceleration")
## Enables a short input-intent grace period and gradual passive deceleration after movement input is released.
@export var movement_release_decel_enabled: bool = true
## Fixed grace time applied whenever ordinary movement input is released.
@export var movement_release_decel_base_delay: float = 0.04
## Maximum total release delay, including the fixed grace time and accumulated intent reserve.
@export var movement_release_decel_max_delay: float = 0.18
## Time needed to blend from zero to full passive deceleration after the delay.
@export var movement_release_decel_ramp_time: float = 0.16
## Intent-reserve seconds gained per second at full combined speed, input-length, and stick-tilt influence.
@export var movement_release_decel_accumulation_rate: float = 1.0
## Lateral speed where the speed contribution to release intent reaches full strength.
@export var movement_release_decel_full_speed: float = 100.0
## Control-forward-relative input angle where the stick-tilt contribution reaches full strength.
@export_range(0.0, 180.0, 1.0) var movement_release_decel_full_tilt_angle_deg: float = 45.0

@export_subgroup("Airborne/Top Speed Detach Ramp")
## Delay (seconds) after detaching before air top speed begins to ramp.
@export var air_top_speed_detach_delay: float = 1.0
## Slerp speed (per second) for ramping from last grounded top speed to air_top_speed.
@export var air_top_speed_detach_slerp_speed: float = 6.0

@export_subgroup("Airborne/Deceleration Falloff")
## Delay (seconds) after walking off an attached surface before air decel ramps in.
## Set to 0.0 to start ramping immediately.
@export var fall_air_decel_delay: float = 0.75
## Slerp speed (per second) for ramping from 0 to full air_decel after the delay.
## Set to 0.0 to snap to full air decel.
@export var fall_air_decel_slerp_speed: float = 6.0

@export_subgroup("Airborne/Fast Fall Horizontal Drag")
## Enables additional gravity-planar deceleration at high downward speeds.
@export var fast_fall_horizontal_drag_enabled: bool = true
## Downward speed where additional horizontal drag begins.
@export var fast_fall_horizontal_drag_start_speed: float = 115.0
## Downward speed where additional horizontal drag reaches full strength.
@export var fast_fall_horizontal_drag_full_speed: float = 230.0
## Gravity-planar deceleration applied at or above the full-effect downward speed.
@export var fast_fall_horizontal_drag_max_decel: float = 60.0

@export_subgroup("Airborne/Launch Momentum")
## Preserves the direction of fast slope launches without removing airborne course correction.
@export var launch_momentum_control_enabled: bool = true
## Detach speed where launch-direction preservation reaches full strength.
@export var launch_momentum_full_speed: float = 180.0
## Air control retained during the fastest and steepest launches.
@export_range(0.0, 1.0, 0.05) var launch_momentum_min_control: float = 0.4
## Seconds needed to restore full air control after a maximum-strength launch.
@export var launch_momentum_recovery_time: float = 0.8

@export_storage var directional_influence_lock_enabled: bool = true
@export_storage var directional_influence_lock_min_speed: float = 5.0
@export_storage var directional_influence_lock_full_speed: float = 180.0
@export_storage var directional_influence_lock_min_angle_deg: float = 10.0
@export_storage var directional_influence_lock_full_angle_deg: float = 160.0
@export_storage var directional_influence_lock_min_accel_multiplier: float = 0.001
@export_storage var directional_influence_lock_accel_recovery_delay: float = 0.2
@export_storage var directional_influence_lock_min_turn_multiplier: float = 0.001
@export_storage var directional_influence_lock_turn_recovery_delay: float = 0.2
@export_storage var directional_influence_lock_min_air_turn_penalty_multiplier: float = 0.0
@export_storage var directional_influence_lock_air_turn_penalty_recovery_delay: float = 0.17
@export_storage var directional_influence_lock_recovery_speed: float = 1.0
@export_storage var directional_influence_lock_full_speed_recovery_time_multiplier: float = 5.6


@export_subgroup("Airborne/Jump and Gravity")

## Gravity strength applied when airborne.
@export var gravity_strength: float = 65.0

## Maximum downward velocity.
@export var max_fall_speed: float = 230.0

## Jump speed along the surface normal when attached.
@export_storage var jump_speed: float = 33.0

## Maximum surface angle (vs gravity-up, in degrees) that allows
## variable-height jump & hang-time. Above this (walls/loops/ceilings),
## jump behaves with fixed height.
@export_storage var variable_jump_max_surface_angle_deg: float = 95.0

## How long (seconds) holding the jump button can influence the jump.
@export_storage var jump_hold_time_max: float = 0.77

## Gravity scale while rising AND holding jump (softer gravity = higher jump).
@export_storage var jump_hold_gravity_scale: float = 0.8

## Extra-soft gravity scale near the apex while holding jump, for “hang time”.
@export_storage var jump_apex_gravity_scale: float = 0.3

## Vertical speed (units/sec, along current up) within which we consider
## we are “near the apex”.
@export_storage var jump_apex_speed_threshold: float = 2.0

## Gravity scale after release while still moving upward
## (he falls sooner but not with a hard velocity cut).
@export_storage var jump_release_gravity_scale: float = 1.8

## If true, allows jump shortly after walking off a ledge without jumping.
@export_storage var coyote_jump_enabled: bool = true
## Coyote jump window in seconds. 0.0 = infinite while still in a valid simple-detach state.
@export_storage var coyote_jump_duration: float = 2.0
## Maximum surface-normal angle (deg) from gravity-up to qualify as a coyote-eligible floor detach.
@export_storage var coyote_jump_max_angle_deg: float = 361.0
## If true, homing attack takes priority over coyote jump when both are available.
@export_storage var coyote_jump_homing_priority: bool = true

## Minimum horizontal (lateral) speed at which damping activates while holding jump.
@export_storage var jump_damp_min_speed: float = 12.0

#@export var jump_damp_max_speed: float = 300.0

## How strongly horizontal speed is damped each second while holding jump.
## (SA1 used a very gentle value. Start with 4–8 range.)
@export_storage var jump_damp_strength: float = 3.0

## Curve controlling how strongly horizontal speed is damped
## while holding the jump button.
## X = lateral speed.
## Y = damping strength (units/sec).
@export_storage var jump_damp_curve: Curve

#@export_group("Turning")

@export_group("Visuals and Animation")
@export_subgroup("Locomotion")
## Character-specific visual and presentation settings.
@export var character_visual_profile: PlayerCharacterVisualProfile
@export var model_turn_speed: float = 37.0
## Airborne model turn speeds (per-axis, used when not attached). 0.0 = snap on that axis.
## Yaw = around local up, Pitch = around local right, Roll = around local forward.
@export var model_turn_speed_air_yaw: float = 20.0
@export var model_turn_speed_air_pitch: float = 20.0
@export var model_turn_speed_air_roll: float = 20.0
## Minimum lateral speed before model forward updates from velocity.
@export var model_turn_min_speed: float = 1.0

## Maximum speed represented by the rail animation blendspace.
@export var anim_speed_blend_max: float = 300.0
## Compensates speed-based animation values for the final movement clock rate. Disabled uses actual world speed. Playback clock scaling remains independent.
@export var anim_speed_logic_compensation_enabled: bool = true
@export var anim_movespeed_min_scale: float = 0.76   # min run cycle speed
@export var anim_movespeed_max_scale: float = 2.07   # max run cycle speed
## Optional animation speed scale by movement speed in units per second. Overrides the min and max scales when assigned.
@export var anim_movespeed_scale_curve: Curve

@export_subgroup("Airborne/Model Turn Ramps")

## Delay before airborne yaw turn speed begins ramping in.
@export var model_turn_speed_air_yaw_delay: float = 0.0

## Ramp speed (1/sec) for airborne yaw turn speed after the delay.
## 0.0 = full strength immediately once the delay expires.
@export var model_turn_speed_air_yaw_ramp_speed: float = 2.0

## Delay before airborne pitch turn speed begins ramping in.
@export var model_turn_speed_air_pitch_delay: float = 0.0

## Ramp speed (1/sec) for airborne pitch turn speed after the delay.
## 0.0 = full strength immediately once the delay expires.
@export var model_turn_speed_air_pitch_ramp_speed: float = 2.0

## Delay before airborne roll turn speed begins ramping in.
@export var model_turn_speed_air_roll_delay: float = 0.0

## Ramp speed (1/sec) for airborne roll turn speed after the delay.
## 0.0 = full strength immediately once the delay expires.
@export var model_turn_speed_air_roll_ramp_speed: float = 2.0

@export var anim_turn_max_angle_deg: float = 300.0   # turn rate (deg/sec) that counts as "full lean"
@export var anim_turn_full_speed: float = 0.0        # speed where turn lean is fully applied
@export var anim_turn_min_speed: float = 0.0         # below this, no turn anim
@export var anim_turn_smooth_factor: float = 5.0     # smoothing strength for turn param

## Animation state used for ordinary jumps.
@export_enum("Standard", "Fall Blend") var jump_animation_mode: int = JumpAnimationMode.STANDARD

## Smoothing speed (1/sec) for the FallBlend blendspace.
## 0.0 = snap to the raw values.
@export var anim_fall_blend_smooth_speed: float = 25.0

## Minimum coordinates accepted by the FallBlend blendspace.
## Match this to the blendspace minimum to prevent off-grid smoothing latency.
@export var anim_fall_blend_min_position: Vector2 = Vector2(0.0, -100.0)

## Maximum coordinates accepted by the FallBlend blendspace.
## Match this to the blendspace maximum to prevent off-grid smoothing latency.
@export var anim_fall_blend_max_position: Vector2 = Vector2(200.0, 100.0)

@export_subgroup("Airborne/Visual Up Blending")

## Delay before visual_up begins blending back toward gravity-up while airborne.
@export var airborne_up_blend_delay: float = 0.8

## Blend speed for visual_up toward gravity-up transition.
@export var airborne_up_blend_speed: float = 180.0

## Ramp speed (1/sec) for the airborne up-blend strength after the delay.
## 0.0 = full strength immediately once the delay expires.
@export var airborne_up_blend_ramp_speed: float = 0.2

@export_subgroup("Airborne/Facing Realignment")

## Delay before movement-facing yaw resumes while airborne.
@export var airborne_facing_resume_delay: float = 0.5

## Ramp speed (1/sec) for the airborne facing yaw after the delay.
## 0.0 = full strength immediately once the delay expires.
@export var airborne_facing_resume_ramp_speed: float = 900.0

@export_subgroup("Airborne/Landing Alignment")

## If true, predict landable surfaces while airborne and visually align toward them.
@export var airborne_landing_align_enabled: bool = true

## Delay (sec) after becoming airborne before landing alignment prediction starts.
@export var airborne_landing_align_delay: float = 0.15

## Time horizon (sec) used to predict an upcoming landing along the travel direction.
@export var airborne_landing_align_predict_time: float = 0.6

## Minimum prediction ray length (units).
@export var airborne_landing_align_min_distance: float = 1.0

## Maximum prediction ray length (units).
@export var airborne_landing_align_max_distance: float = 55.0

## Speed reference (units/sec) used to scale landing prediction distance by speed.
## 0.0 disables speed-based distance scaling.
@export var airborne_landing_align_speed_ref: float = 90.0

## Minimum distance scale applied at very low speed.
@export var airborne_landing_align_speed_min_scale: float = 0.95

## Maximum distance scale applied at or above the speed reference.
@export var airborne_landing_align_speed_max_scale: float = 1.9

## Additional downward extension (units) added to the prediction ray.
@export var airborne_landing_align_downcast_extra: float = 7.5

## How strongly gravity biases the prediction direction downward.
@export var airborne_landing_align_gravity_bias: float = 0.75

## Maximum surface angle (deg vs gravity-up) that counts as landable for alignment.
@export var airborne_landing_align_max_angle_deg: float = 88.0

## Maximum visual align speed (deg/sec) toward the predicted landing normal.
@export var airborne_landing_align_speed_deg: float = 540.0

## Preserves significant local pitch rotation direction while aligning to predicted terrain.
@export var airborne_landing_align_directional_pitch_enabled: bool = true

## Minimum local pitch angular speed required to preserve its forward or backward direction.
@export_range(0.0, 2160.0, 1.0, "or_greater", "suffix:deg/s")
var airborne_landing_align_pitch_preference_min_speed_deg: float = 55.0

## Smoothing speed applied to changing predicted terrain normals. A value of 0.0 snaps immediately.
@export_range(0.0, 60.0, 0.1, "or_greater")
var airborne_landing_align_normal_smoothing_speed: float = 12.0

## Time that the last predicted normal remains active through brief ray misses on uneven terrain.
@export_range(0.0, 0.5, 0.01, "or_greater", "suffix:s")
var airborne_landing_align_miss_grace_time: float = 0.08

## Alignment angle treated as complete before selecting another directional pitch route.
@export_range(0.0, 15.0, 0.1, "suffix:deg")
var airborne_landing_align_completion_angle_deg: float = 2.0

## Turns visual facing toward movement projected across the predicted terrain while aligning.
@export var airborne_landing_align_movement_yaw_enabled: bool = true

## Maximum movement-facing yaw speed during predicted terrain alignment.
@export_range(0.0, 1080.0, 1.0, "or_greater", "suffix:deg/s")
var airborne_landing_align_movement_yaw_speed_deg: float = 240.0

## Minimum movement speed across the predicted terrain before landing yaw begins.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m/s")
var airborne_landing_align_movement_yaw_min_speed: float = 3.0

## Terrain-planar movement speed where landing yaw reaches its full configured speed.
@export_range(0.1, 200.0, 0.1, "or_greater", "suffix:m/s")
var airborne_landing_align_movement_yaw_full_speed: float = 30.0

## Minimum ramp factor applied even at the edge of the prediction horizon.
@export var airborne_landing_align_min_ramp: float = 0.15

## Extra align speed multiplier applied as the predicted landing gets closer.
@export var airborne_landing_align_close_speed_mult: float = 2.0

## Power used for the close-distance speed ramp (higher = more late/steep ramp).
@export var airborne_landing_align_close_speed_power: float = 2.0

@export_subgroup("Airborne/Torque")

## Enables captured, manual, and trajectory-driven airborne visual torque.
@export var airborne_torque_enabled: bool = true

## Gain applied to airborne torque rotation (1.0 = as captured).
@export var airborne_torque_gain: float = 1.185

## Minimum surface-normal angle (deg) needed to capture torque from the surface.
@export var airborne_torque_capture_min_angle_deg: float = 4.65

## Minimum averaged rotation speed (deg/sec) required to apply airborne torque.
@export var airborne_torque_min_avg_speed_deg: float = 20.0

## Max captured angular speed (deg/sec). 0.0 = uncapped.
@export var airborne_torque_max_speed_deg: float = 540.0

## Damping speed (1/sec) applied to airborne torque angular velocity.
@export var airborne_torque_decay_speed: float = 0.38

## Time window (sec) used to average ground rotation for airborne torque.
@export var airborne_torque_sample_window: float = 0.4

## If true, capture yaw tumble from the signed turning-rate sample while attached.
## The sampled yaw is stored before detach and then carried into airborne torque.
@export var airborne_torque_yaw_from_turn_rate_enabled: bool = true

## Multiplier applied to the signed turning-rate sample when converting it to
## captured yaw angular velocity. 1.0 = use the sampled turn rate as-is.
@export var airborne_torque_yaw_turn_rate_scale: float = 1.05

## Maximum yaw tumble speed (deg/sec) captured from turning rate before detach.
## 0.0 = uncapped.
@export var airborne_torque_yaw_turn_rate_max_speed_deg: float = 720.0
## Time after the last detected yaw turn that yaw torque can be captured.
@export var airborne_torque_yaw_turn_rate_memory_time: float = 0.08

## Minimum input-vs-travel angle needed to capture yaw torque from turning.
@export var airborne_torque_yaw_input_min_angle_deg: float = 8.0

## Minimum movement input strength needed to capture yaw torque from turning.
@export_range(0.0, 1.0, 0.01) var airborne_torque_yaw_input_min_strength: float = 0.2

## If detaching from a surface within this angle (deg) of gravity-up, do not
## start torque-n-tumble at all.
@export var airborne_torque_flat_detach_max_angle_deg: float = 9.0

## If true, activating airborne actions such as jump dash, homing, or
## bounce/stomp immediately cancels tumbling and snaps visual_up to gravity-up.
@export var airborne_torque_cancel_on_air_actions: bool = true

@export_subgroup("Airborne/Torque Manual Input")
## Enables the Ability Slot 5 mid-air manual torque mode.
@export var manual_airborne_torque_enabled: bool = true
## Base radians per pixel applied to yaw input (before mouse sensitivity).
@export var manual_airborne_torque_mouse_yaw_scale: float = -0.008
## Base radians per pixel applied to pitch input (before mouse sensitivity).
@export var manual_airborne_torque_mouse_pitch_scale: float = -0.008
## Base radians per pixel applied to diagonal roll input (before mouse sensitivity).
@export var manual_airborne_torque_mouse_roll_scale: float = -0.008
## Angular acceleration in radians per second squared at full controller stick input.
@export var manual_airborne_torque_stick_angular_acceleration: float = 45.0
## Maximum angular velocity (radians/sec) for manual torque.
@export var manual_airborne_torque_max_speed: float = 15.0
## If true, manual torque is applied relative to the player's current visual orientation.
## Otherwise, it is applied relative to gravity-up and the player's horizontal forward.
@export var manual_airborne_torque_player_relative: bool = true
## If true, manual airborne torque can trigger trick animations.
@export var manual_airborne_torque_tricks_enabled: bool = true
## Angular velocity threshold (radians/sec) used to exit manual torque mode after releasing Ability Slot 5.
@export var manual_airborne_torque_exit_threshold: float = 5.0
## Fast decay speed (1/sec) applied when interact is used to end torque.
@export var manual_airborne_torque_fast_decay_speed: float = 8.0
## Multiplier applied to regular air acceleration while recovering left-stick trick momentum.
@export var manual_airborne_torque_left_stick_momentum_recovery_multiplier: float = 1.0

@export_subgroup("Airborne/Trick Animations")

## If true, airborne tumble can trigger trick animations.
@export var trick_animations_enabled: bool = false

## Minimum angular speed (deg/sec) on the dominant torque axis to trigger a trick.
## 0.0 disables the threshold check (any non-zero torque can trigger).
@export var trick_torque_min_speed_deg: float = 150.0
## Angular speed below which a completed torque-animation gesture may rearm.
@export var trick_torque_animation_rearm_speed_deg: float = 75.0

## Extra gravity while in spring state (align timer > 0, airborne).
## 1.0 = same as normal, >1 = stronger pull downward.
@export_storage var spring_gravity_scale: float = 1.8

## Whether very low speeds should automatically end non-direction-locked spring state.
@export_storage var spring_exit_on_low_speed: bool = true

## If spring_exit_on_low_speed is true, non-direction-locked spring state ends below this speed.
@export_storage var spring_exit_speed_threshold: float = 5.0
## Time (seconds) to snap model alignment to the spring direction.
## This ignores model turn speed briefly for immediate visual alignment.
@export_storage var spring_model_snap_time: float = 0.12
## Additional pitch (deg) applied during spline travel.
## Positive values pitch the model forward (head toward travel direction).
@export_storage var spline_model_pitch_deg: float = 90.0

@export_storage var rail_jump_vertical_speed: float = 35.0
@export_storage var rail_default_attach_height: float = 0.9
@export_storage var rail_align_to_path_tilt: bool = true
@export_storage var rail_allow_input_reverse: bool = false
@export_storage var rail_reverse_speed_threshold: float = 10.0
@export_storage var rail_reverse_boost_speed: float = 10.0
@export_storage var rail_reverse_input_dot_threshold: float = 0.35
@export_storage var rail_end_detach_distance: float = 0.02
## Cooldown before the same rail can be attached again.
@export_storage var rail_rehit_cooldown: float = 0.3
@export_storage var rail_crouch_enabled: bool = true
@export_storage var rail_crouch_uphill_decel: float = 18.0
@export_storage var rail_crouch_downhill_accel: float = 24.0

## Enables rail snapping from proximity to the rail path.
@export_storage var rail_path_snap_enabled: bool = true
## Rail snap distance at zero speed.
@export_storage var rail_path_snap_radius_min: float = 1.5
## Rail snap distance at or above max snap speed.
@export_storage var rail_path_snap_radius_max: float = 4.0
## Speed where rail snap distance reaches max radius.
@export_storage var rail_path_snap_speed_for_max_radius: float = 90.0
## Blocks rail snapping when collision is between the player and rail path.
@export_storage var rail_path_snap_obstruction_check: bool = true
## Extra clearance allowed before an obstruction blocks rail snapping.
@export_storage var rail_path_snap_obstruction_margin: float = 0.15

@export_storage var rail_anim_min_scale: float = 0.8
@export_storage var rail_anim_max_scale: float = 3.0
@export_storage var rail_anim_speed_for_max: float = 120.0
@export_storage var rail_anim_blend_smooth_speed: float = 75.0
@export_storage var rail_anim_dir_smooth_speed: float = 6.0
@export_storage var rail_anim_dir_speed_for_full: float = 8.0

@export_storage var rail_switch_enabled: bool = true
@export_storage var rail_switch_query_radius: float = 30.0
## Minimum camera-relative movement strength perpendicular to the rail required to select a switch side.
@export_storage var rail_switch_side_input_min: float = 0.35
@export_storage var rail_switch_side_dot_min: float = 0.25
@export_storage var rail_switch_forward_dot_min: float = 0.2
@export_storage var rail_switch_tangent_lookahead: float = 0.05
@export_storage var rail_switch_lateral_speed: float = 45.0
@export_storage var rail_switch_vertical_speed: float = 50.0
@export_storage var rail_switch_forward_speed_scale: float = 1.0
@export_storage var rail_switch_forward_speed_min: float = 0.0
@export_storage var rail_switch_snap_distance: float = 0.1
## Fixed duration of every rail-to-rail transfer.
@export_storage var rail_switch_max_duration: float = 0.75
@export_storage var rail_switch_min_end_distance: float = 0.05

## How fast you must be moving downward (along up) before we consider it "falling".
@export_storage var fall_vertical_speed_threshold: float = 14.0

## Small grace so we don't instantly call it a fall the moment we leave ground.
@export_storage var fall_airborne_grace_time: float = 0.05

@export_storage var damage_hit_invuln_time: float = 2.0
@export_storage var damage_launch_upward_speed: float = 32.0
@export_storage var damage_pushback_speed: float = 30.0
@export_storage var damage_trip_speed_threshold: float = 40.0
@export_storage var damage_trip_speed_multiplier: float = 0.55
@export_storage var hurt_input_influence: float = 0.2
@export_storage var hurt_air_decel_multiplier: float = 0.6
@export_storage var hurt_ground_decel_multiplier: float = 0.1
@export_storage var hurt_air_jump_unlock_time: float = 0.7
## Seconds between visibility toggles during hurt invulnerability.
@export_storage var hurt_invuln_flash_interval: float = 0.02

@export_group("Barrier Blast")
@export_subgroup("Activation")
@export var barrier_blast_enabled: bool = true

@export_subgroup("Gauge/Filling")
## Minimum speed (any direction) where the gauge starts filling.
@export var barrier_blast_fill_min_speed: float = 67.0

## Maximum speed (any direction) where the gauge fills at the fastest rate.
@export var barrier_blast_fill_max_speed: float = 160.0

## Gauge fill rate (fraction/sec) at min speed.
@export var barrier_blast_fill_rate_min: float = 0.065

## Gauge fill rate (fraction/sec) at max speed.
@export var barrier_blast_fill_rate_max: float = 0.23

@export_subgroup("Gauge/Drain")
## Gauge drain rate (fraction/sec) while under min speed threshold.
@export var barrier_blast_drain_rate_under_min_speed: float = 0.22

## Prevent gauge depletion while charging a spindash.
@export var barrier_blast_pause_deplete_while_spindash: bool = true

## Grace window (sec) before drain starts after dropping below min speed.
@export var barrier_blast_deplete_grace_time: float = 0.5

## Grace window (sec) before drain starts after landing while gauge is full.
@export var barrier_blast_full_land_grace_time: float = 0.5

@export_subgroup("Movement")
## Barrier Blast ends when speed drops to/below this.
@export var barrier_blast_exit_speed: float = 67.0

## Run top speed while Barrier Blast is active.
@export var barrier_blast_run_top_speed: float = 128.0

## Ground acceleration curve while Barrier Blast is active (optional).
@export var barrier_blast_ground_accel_curve: Curve

## Downhill slope response acceleration by lateral speed while Barrier Blast is active.
## X: lateral speed, Y: acceleration.
@export var barrier_blast_slope_downhill_accel_curve: Curve

## Uphill slope response acceleration by lateral speed while Barrier Blast is active.
## X: lateral speed, Y: deceleration.
@export var barrier_blast_slope_uphill_decel_curve: Curve

## Final Barrier Blast slope response power by surface angle.
## X: surface angle in degrees, Y: power multiplier.
@export var barrier_blast_slope_gravity_angle_curve: Curve

## Ground turning curve while Barrier Blast is active (optional).
@export var barrier_blast_ground_turn_angle_curve: Curve

@export_storage var barrier_blast_ground_turn_free_angle_deg: float = 17.0
@export_storage var barrier_blast_ground_turn_free_angle_curve: Curve

## Minimum ground-turn speed preservation while Barrier Blast is active.
@export_range(0.0, 1.0, 0.05) var barrier_blast_turn_speed_preservation: float = 0.9
## Multiplier for ground, airborne, and water top-speed slowdown while Barrier Blast is active. One retains normal slowdown strength; zero disables this slowdown.
@export_range(0.0, 2.0, 0.05, "or_greater") var barrier_blast_top_speed_slowdown_multiplier: float = 1.0


@export_storage var roll_enabled: bool = true

## Deceleration while rolling on ground (very low).
@export_storage var roll_decel: float = 3.0

@export_storage var roll_linear_drag: float = 0.0
@export_storage var roll_quadratic_drag: float = 0.0005

## Deceleration while rolling in air (very low).
@export_storage var roll_air_decel: float = 2.5

## Max turn rate while rolling (deg/sec). Set to 0 to disable steering.
@export_storage var roll_turn_deg_per_sec: float = 140.0

## Applies ordinary roll surface resistance while rolling on slopes and loop surfaces.
@export_storage var roll_slope_surface_resistance_enabled: bool = false

## Multiplier applied to downhill speed gain while rolling (higher = faster downhill).
@export_storage var roll_downhill_accel_multiplier: float = 1.9

## Optional rolling downhill acceleration multiplier by lateral speed.
## X: lateral speed, Y: multiplier.
@export_storage var roll_downhill_accel_multiplier_curve: Curve

## Multiplier applied to uphill slowdown while rolling (higher = stronger slowdown uphill).
@export_storage var roll_uphill_decel_multiplier: float = 1.8

## Optional rolling uphill deceleration multiplier by lateral speed.
## X: lateral speed, Y: multiplier.
@export_storage var roll_uphill_decel_multiplier_curve: Curve

## Final rolling slope response power by surface angle.
## X: surface angle in degrees, Y: power multiplier.
@export_storage var roll_slope_gravity_angle_curve: Curve

@export_storage var roll_air_top_speed_slowdown_enabled: bool = false

## Airborne soft-cap bleed scale while rolling.
@export_storage var roll_top_speed_slowdown_scale: float = 0.2

## Animation speed while rolling (scaled by total speed).
@export_storage var roll_anim_min_scale: float = 0.0
@export_storage var roll_anim_max_scale: float = 1.4
@export_storage var roll_anim_speed_for_max: float = 90.0

@export_storage var roll_start_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Roll_Start.wav")
@export_storage var roll_start_volume_db: float = -15.0
@export_storage var roll_start_pitch_scale: float = 1.0
@export_storage var roll_end_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Roll_End.wav")
@export_storage var roll_end_volume_db: float = -15.0
@export_storage var roll_end_pitch_scale: float = 1.0
@export_storage var roll_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Roll_Loop.ogg")
@export_storage var roll_loop_volume_min_speed: float = 5.0
@export_storage var roll_loop_volume_full_speed: float = 90.0
@export_storage var roll_loop_volume_min_db: float = -50.0
@export_storage var roll_loop_volume_max_db: float = -21.0
@export_storage var roll_loop_pitch_min_speed: float = 5.0
@export_storage var roll_loop_pitch_full_speed: float = 90.0
@export_storage var roll_loop_pitch_min: float = 0.45
@export_storage var roll_loop_pitch_max: float = 1.0
@export_storage var roll_loop_lerp_speed: float = 500.0
@export_storage var roll_loop_fade_in_speed_db: float = 500.0
@export_storage var roll_loop_fade_out_speed_db: float = 500.0
@export_storage var roll_loop_stop_volume_db: float = -80.0


## Enables the drift system (ground-only course correction).
@export_storage var drift_enabled: bool = true
## Minimum lateral speed required to start drift on normal ground.
@export_storage var drift_min_speed: float = 50.0
## Minimum lateral speed required to keep drift active (0 = use drift_min_speed).
@export_storage var drift_exit_min_speed: float = 45.0
## Minimum side input needed to choose a drift direction.
@export_storage var drift_input_deadzone: float = 0.25
## Surface angle (deg vs gravity-up) where drift can persist even below min speed.
@export_storage var drift_steep_surface_angle_deg: float = 45.0
## Locked drift turn rate before input multipliers are applied.
@export_storage var drift_base_turn_deg_per_sec: float = 125.0
## Turn multiplier when steering into the committed drift direction.
@export_storage var drift_tight_turn_multiplier: float = 1.45
## Turn multiplier when steering opposite the committed drift direction.
@export_storage var drift_counter_turn_multiplier: float = 0.45
## Blend speed for input-based drift turn changes.
@export_storage var drift_turn_input_response: float = 14.0
## Blend speed for the effective drift turn rate.
@export_storage var drift_turn_response: float = 7.0
## Seconds needed to fully swap from one drift direction to the other.
@export_storage var drift_direction_switch_time: float = 0.45
## Allows previous drift turn influence to carry into a direction switch.
@export_storage var drift_direction_switch_carry_previous_influence: bool = true
## Time in seconds to ease into drift turn rate after activation.
@export_storage var drift_turn_entry_time: float = 0.18
## Carries compatible pre-drift course turning into drift entry and uses it to resolve neutral side input.
@export_storage var drift_entry_turn_rate_inheritance_enabled: bool = true
## Turn rate below which entry inheritance and neutral-side inference are ignored.
@export_storage var drift_entry_turn_rate_min_deg_per_sec: float = 20.0
## Turn rate where entry inheritance reaches its full configured scale.
@export_storage var drift_entry_turn_rate_full_deg_per_sec: float = 120.0
## Multiplier applied to the inherited pre-drift turn rate.
@export_storage var drift_entry_turn_rate_scale: float = 1.0
## Maximum inherited drift-entry turn rate. Set to 0 to disable the cap.
@export_storage var drift_entry_turn_rate_max_deg_per_sec: float = 180.0
## Fraction of entry speed above the normal run cap inherited by the drift speed target.
@export_storage var drift_entry_speed_inheritance: float = 1.0
## Maximum inherited entry-speed excess. Set to 0 to disable the cap.
@export_storage var drift_entry_speed_inheritance_limit: float = 0.0
## Drifted turn angle needed for the full speed reward.
@export_storage var drift_reward_turn_degrees: float = 180.0
## Drifted distance needed for the full speed reward on wide arcs.
@export_storage var drift_reward_distance: float = 160.0
## Top speed added at full drift reward.
@export_storage var drift_reward_speed_bonus: float = 38.0
## Extra acceleration added at full drift reward.
@export_storage var drift_reward_accel: float = 55.0
## Seconds used to blend drift camera and movement controls back to normal after drift ends.
@export_storage var drift_exit_duration: float = 0.22
## Keeps drift influence at full strength briefly before the exit ease starts.
@export_storage var drift_exit_delay_enabled: bool = true
## Delay before drift exit easing begins.
@export_storage var drift_exit_delay: float = 0.035
## Curve used to ease movement and camera influence out of drift.
@export_storage var drift_exit_ease_curve: Curve = preload("res://LS5Framework/Curves/DriftExitEase.tres")
## Animation speed when counter-steering out of the drift.
@export_storage var drift_anim_outward_speed_scale: float = 0.78
## Animation speed with no inward or outward steering bias.
@export_storage var drift_anim_neutral_speed_scale: float = 1.0
## Animation speed when steering into the drift.
@export_storage var drift_anim_inward_speed_scale: float = 1.24
## Animation speed at minimum drift movement speed.
@export_storage var drift_anim_movement_min_scale: float = 0.95
## Animation speed at maximum drift movement speed.
@export_storage var drift_anim_movement_max_scale: float = 1.32
## Movement speed that reaches maximum drift animation scaling.
@export_storage var drift_anim_movement_speed_for_max: float = 150.0
## Enables model Y-axis influence while drifting.
@export_storage var drift_visual_influence_enabled: bool = true
## X/Y/Z model angles used as the base drift pose.
@export_storage var drift_visual_offset_angles_deg: Vector3 = Vector3(0.0, 10.0, 0.0)
## X/Y/Z model angles added at full inward drift steering.
@export_storage var drift_visual_inner_angles_deg: Vector3 = Vector3(0.0, 22.0, 0.0)
## X/Y/Z model angles added at full outward drift steering.
@export_storage var drift_visual_outer_angles_deg: Vector3 = Vector3(0.0, 4.0, 0.0)
## Blend speed for entering drift visual influence.
@export_storage var drift_visual_entry_lerp_speed: float = 12.0
## Blend speed used when drift visual influence is cleared outside normal exit.
@export_storage var drift_visual_exit_lerp_speed: float = 20.0
## Enables in-world drift guide lines in debug view.
@export_storage var drift_debug_guides_enabled: bool = true
## Length of the in-world drift guide arrows.
@export_storage var drift_debug_guide_length: float = 18.0
## Number of line segments used by the in-world drift arc guide.
@export_storage var drift_debug_arc_segments: int = 8


@export_group("Debug")
@export_subgroup("Display")
## Shows the previous low-level diagnostics beneath the categorized debug view.
@export var debug_show_extended_details: bool = false

@export_subgroup("Free Movement")
@export var debug_mode_enabled: bool = true
@export var debug_move_speed: float = 70.0
@export var debug_vertical_speed: float = 25.0
@export var debug_fast_multiplier: float = 12.0
@export var debug_slow_multiplier: float = 0.25

@export_subgroup("Unstuck")
@export var unstuck_nudge_distance: float = 1.0
@export var unstuck_nudge_steps: int = 4
@export_range(0.0, 1.0) var unstuck_force_nudge_scale: float = 0.25
@export var unstuck_auto_detect_enabled: bool = true
@export var unstuck_auto_min_speed: float = 5.0
@export var unstuck_auto_max_position_change: float = 0.1
@export var unstuck_auto_detection_time: float = 0.5


## Ground turn angle per second as a curve.
## X: lateral speed, Y: degrees per second.
@export_storage var ground_turn_angle_curve: Curve
## Ground turn angle per second while walk input is held.
## X: lateral speed, Y: degrees per second.
@export_storage var walk_turn_angle_curve: Curve
@export_storage var ground_turn_sharp_rate_multiplier: float = 1.35
@export_storage var ground_turn_speed_preservation: float = 0.65
@export_storage var ground_brake_decel: float = 70.0
## Angle at which turning does not slow you down.
@export_storage var ground_turn_free_angle_deg: float = 11.0
## Angle at which turning against free angle has the most effect.  Can be greater than 180.
@export_storage var ground_turn_max_penalty_angle_deg: float = 360.0
## Angle at which turning against free angle has the most effect.  Can be greater than 180.  Curve option.
@export_storage var ground_turn_max_penalty_angle_curve: Curve
## Angle at which turning does not slow you down, curve option.
@export_storage var ground_turn_free_angle_curve: Curve
@export_storage var ground_turn_min_speed_factor: float = 0.965


@export_group("Targeting and Interactions")

## Whether the jump dash can only be used while airborne.
@export_storage var jump_dash_air_only: bool = true

## Whether the dash can only be used once per airtime (classic SA-ish).
@export_storage var jump_dash_once_per_air: bool = true

## How much speed to add in the facing direction (units/sec).
@export_storage var jump_dash_add_speed: float = 50.0

## Jump dash adds no impulse once lateral speed reaches this value.
## Impulse scales down as lateral speed approaches this value.
@export_storage var jump_dash_impulse_stop_speed: float = 100.0

## Max lateral speed allowed immediately after a dash.
## If <= 0, falls back to max_speed.
@export_storage var jump_dash_max_lateral_speed: float = 0.0

## Enables shared homing-target scans when an ability opts into them.
@export_storage var homing_targeting_enabled: bool = true
@export_storage var homing_attack_enabled: bool = true
@export_storage var homing_min_range: float = 35.0
@export_storage var homing_max_range: float = 90.0
@export_storage var homing_range_per_speed: float = 0.18
@export_storage var homing_min_dot: float = 0.6
## Minimum movement input strength that can offset hybrid targeting from the reticle.
@export_storage var homing_hybrid_input_min_strength: float = 0.2
## Input deviation retained as camera-targeting priority in hybrid mode.
@export_storage var homing_hybrid_camera_priority_angle_deg: float = 15.0
## Input deviation where hybrid targeting fully follows the movement direction.
@export_storage var homing_hybrid_full_input_angle_deg: float = 60.0
## Strength of the reticle-proximity bonus while hybrid targeting favors the camera.
@export_storage var homing_hybrid_reticle_priority: float = 0.5
## Minimum travel speed during homing; above this, homing uses your current momentum speed.
@export_storage var homing_speed: float = 85.0
@export_storage var homing_turn_rate: float = 3.5
@export_storage var homing_hit_distance: float = 1.25
@export_storage var homing_pop_up_speed: float = 40.0
@export_storage var homing_bounce_speed_fraction: float = 0.5
## Minimum velocity applied when bouncing from enemies.
@export_storage var enemy_bounce_min_speed: float = 28.0
## Caps the upward result when a homing target is reached from below.
@export_storage var homing_below_target_bounce_cap_enabled: bool = true
## Minimum target height along the character's physics-up axis before the cap applies.
@export_storage var homing_below_target_min_height: float = 0.25
## Maximum upward velocity retained after hitting a homing target from below.
@export_storage var homing_below_target_max_up_speed: float = 16.0
## Max allowed height above the player for homing targets (<= 0 disables).
@export_storage var homing_target_max_height: float = 14.0
## Prevents homing attacks from selecting targets behind collision geometry.
@export_storage var homing_obstruction_check: bool = true
## Distance before the target ignored when deciding whether a ray hit is obstructing it.
@export_storage var homing_obstruction_margin: float = 0.15
@export_storage var homing_retain_speed_if_jump_held: bool = true
@export_storage var homing_retain_disable_air_decel_time: float = 0.25
## Max time to stay in homing without hitting anything (auto-cancel).
@export_storage var homing_fail_timeout: float = 4.0
@export_storage var homing_post_attack_time: float = 0.2

@export_subgroup("Attack Magnetism")
## Enables gentle target assist while an attacking action permits it.
@export var attack_magnetism_enabled: bool = true
## Restricts attack magnetism scans to player-controlled pawns.
@export var attack_magnetism_player_controlled_only: bool = true
## Maximum target selection refresh rate.
@export var attack_magnetism_target_update_rate_hz: float = 20.0
## Minimum target range for player attack magnetism.
@export var attack_magnetism_range: float = 30.0
## Maximum target range for player attack magnetism after speed scaling.
@export var attack_magnetism_max_range: float = 100.0
## Range added per unit of current player speed in any direction.
@export var attack_magnetism_range_per_speed: float = 0.35
## Maximum heading angle for attack magnetism target selection.
@export var attack_magnetism_detection_angle_deg: float = 50.0
## Direction-adjustment acceleration applied by attack magnetism.
@export var attack_magnetism_strength: float = 55.0
## Minimum speed kept while attack magnetism turns the current velocity.
@export var attack_magnetism_min_speed: float = 0.0
## Input dot at or below this value blocks attack magnetism.
@export var attack_magnetism_input_away_dot: float = -0.15
## Extra strength when input points toward the target.
@export var attack_magnetism_input_toward_bonus: float = 0.65
## Strength multiplier used with no descent.
@export_range(0.0, 1.0, 0.01) var attack_magnetism_no_descent_strength: float = 0.18
## Descent speed where attack magnetism reaches full strength.
@export var attack_magnetism_peak_descent_speed: float = 36.0
## Descent speed where high-fall weakening reaches its minimum.
@export var attack_magnetism_max_descent_speed: float = 300.0
## Strength multiplier used at or beyond max descent speed.
@export_range(0.0, 1.0, 0.01) var attack_magnetism_fast_descent_strength: float = 0.78
## Enemy bounce velocity gained from descent speed reduced by attack magnetism.
@export var attack_magnetism_bounce_lost_descent_gain: float = 1.0
## Time lost descent compensation remains available for enemy bounce.
@export var attack_magnetism_bounce_compensation_time: float = 0.25

@export_storage var lightspeed_dash_enabled: bool = true
@export_storage var lightspeed_dash_start_radius: float = 18.0
@export_storage var lightspeed_dash_chain_radius: float = 15.0
@export_storage var lightspeed_dash_collect_distance: float = 1.15
@export_storage var lightspeed_dash_min_forward_dot: float = 0.0
@export_storage var lightspeed_dash_max_height_delta: float = 50.0
@export_storage var lightspeed_dash_min_speed: float = 85.0
@export_storage var lightspeed_dash_max_iterations_per_frame: int = 3
@export_storage var lightspeed_dash_max_duration: float = 99.0

@export_storage var lightspeed_dash_speed_bonus_per_speed: float = 0.1
@export_storage var lightspeed_dash_camera_radius_bonus: float = 5.0
@export_storage var lightspeed_dash_hybrid_angle_deg: float = 45.0
@export_storage var lightspeed_dash_turn_rate: float = 20.0
## If true, a flat speed bonus is added when lightspeed dash starts.
@export_storage var lightspeed_dash_start_additive_speed_enabled: bool = true
## Flat speed bonus added to the dash start velocity before clamping.
@export_storage var lightspeed_dash_start_additive_speed: float = 14.0
## Cooldown before the flat entry speed bonus can be granted again.
@export_storage var lightspeed_dash_start_bonus_cooldown: float = 1.0
## Maximum total speed allowed after the dash start bonus is applied.
@export_storage var lightspeed_dash_start_speed_cap: float = 220.0
@export_storage var lightspeed_dash_auto_attach_on_end: bool = true
@export_storage var lightspeed_dash_auto_attach_max_distance: float = 8.5
## If true, a natural lightspeed dash end can fall back to nearby non-floor surfaces when no floor-like hit is found.
@export_storage var lightspeed_dash_auto_attach_allow_wall_fallback: bool = true
@export_storage var lightspeed_dash_face_target: bool = true

@export_subgroup("Carry Objects")
## Enables pickup, carry, put down, and throw interactions for carryable objects.
@export var carry_objects_enabled: bool = true
## Animation state used for jumps while an object is carried.
@export_enum("Standard", "Fall Blend") var carry_jump_animation_mode: int = JumpAnimationMode.FALL_BLEND
## Group scanned when searching for nearby carryable objects.
@export var carry_object_group: StringName = &"carryable_object"
## Input action used to pick up nearby carryable objects.
@export var carry_pickup_input_action: StringName = &"interact"
## Input action used to put down a carried object.
@export var carry_put_down_input_action: StringName = &"interact"
## Optional input action used to throw a carried object. Empty disables the separate throw input.
@export var carry_throw_input_action: StringName = &""
## Local fallback offset used when no carry anchor is assigned. Negative Z is forward.
@export var carry_fallback_offset: Vector3 = Vector3(0.0, 1.35, -1.55)
## Maximum distance for picking up carryable objects.
@export var carry_pickup_radius: float = 5.0
## Extra pickup radius gained per unit of lateral speed.
@export var carry_pickup_speed_radius_scale: float = 0.025
## Maximum extra pickup radius gained from speed.
@export var carry_pickup_speed_radius_max: float = 3.0
## Minimum forward alignment for pickup selection.
@export_range(-1.0, 1.0, 0.01) var carry_pickup_min_forward_dot: float = -0.2
## If true, level geometry must not block the pickup ray to a carryable object.
@export var carry_pickup_requires_clear_path: bool = true
## Collision mask used when checking carryable pickup obstruction.
@export_flags_3d_physics var carry_pickup_obstruction_mask: int = 1
## Upward offset from the player position used as the pickup obstruction ray start.
@export var carry_pickup_obstruction_start_up_offset: float = 0.75
## Upward offset from the carryable position used as the pickup obstruction ray end.
@export var carry_pickup_obstruction_target_up_offset: float = 0.35
## Distance in front of the player used when putting an object down.
@export var carry_put_down_forward_distance: float = 2.0
## Upward offset used when putting an object down.
@export var carry_put_down_up_offset: float = 0.25
## If true, put-down placement searches for a nearby unobstructed position.
@export var carry_put_down_validate_placement: bool = true
## Collision mask used when checking put-down placement.
@export_flags_3d_physics var carry_put_down_placement_mask: int = 1
## Margin used when testing the carried object's actual physics body for put-down placement.
@export var carry_put_down_body_test_margin: float = 0.08
## Radius used when checking put-down placement clearance.
@export var carry_put_down_clearance_radius: float = 0.65
## Extra upward clearance used when checking put-down placement.
@export var carry_put_down_clearance_up_offset: float = 0.35
## Extra forward distance searched when the intended put-down point is blocked.
@export var carry_put_down_safe_forward_extra: float = 2.0
## Side distance searched when the intended put-down point is blocked.
@export var carry_put_down_safe_side_distance: float = 1.2
## Upward distance searched when the intended put-down point is blocked.
@export var carry_put_down_safe_up_distance: float = 1.0
## Number of forward search steps used for safer put-down placement.
@export var carry_put_down_safe_forward_steps: int = 3
## Number of side search steps used for safer put-down placement.
@export var carry_put_down_safe_side_steps: int = 2
## Number of upward search steps used for safer put-down placement.
@export var carry_put_down_safe_up_steps: int = 2
## Upward offset from the player position used by put-down obstruction rays.
@export var carry_put_down_obstruction_start_up_offset: float = 0.75
## Enables release-time wall clearance checks for put-downs and throws.
@export var carry_release_wall_avoidance_enabled: bool = true
## Collision mask used by release-time forward wall rays.
@export_flags_3d_physics var carry_release_wall_avoidance_mask: int = 1
## Minimum forward clearance maintained between the player and release obstructions.
@export var carry_release_wall_clearance_distance: float = 2.35
## Extra separation maintained when moving the player away from a release obstruction.
@export var carry_release_wall_clearance_margin: float = 0.1
## Initial distance from the player used by the gentle side-placement fallback.
@export var carry_release_side_placement_distance: float = 1.75
## Additional side distance searched when the nearest fallback position is obstructed.
@export var carry_release_side_search_extra: float = 2.0
## Number of additional distances checked on each side for fallback placement.
@export var carry_release_side_search_steps: int = 4
## Forward speed applied when throwing a carried object.
@export var carry_throw_forward_speed: float = 20.0
## Upward speed applied when throwing a carried object.
@export var carry_throw_up_speed: float = 14.0
## Portion of player velocity inherited by released carryable objects.
@export var carry_release_inherit_velocity_scale: float = 1.0
## Time released carryable objects ignore the carrier collision.
@export var carry_release_player_collision_lock: float = 0.35
## Movement input needed for interact to throw instead of putting down.
@export_range(0.0, 1.0, 0.01) var carry_interact_throw_input_threshold: float = 0.35
## Player speed needed for interact to throw instead of putting down.
@export var carry_interact_throw_speed_threshold: float = 12.0
## AnimationTree parameter used to blend the carry hold overlay.
@export var carry_hold_blend_parameter: String = "parameters/CarryOverlay/blend_amount"
## Speed used to blend the carry hold overlay in and out.
@export var carry_hold_blend_speed: float = 18.0
## AnimationTree playback parameter for the carry overlay state machine.
@export var carry_overlay_playback_parameter: String = "parameters/CarryAnimation/playback"
## Skeleton track path used by the carry overlay filter.
@export var carry_overlay_skeleton_filter_path: NodePath = ^"Armature/Skeleton3D"
## Bones affected by the carry overlay filter.
@export var carry_overlay_filter_bones: Array[StringName] = [
	&"clavicle_r",
	&"upperarm_r",
	&"lowerarm_r",
	&"hand_r",
	&"index_01_r",
	&"index_02_r",
	&"index_03_r",
	&"index_04_leaf_r",
	&"thumb_01_r",
	&"thumb_02_r",
	&"thumb_03_r",
	&"middle_01_r",
	&"middle_02_r",
	&"middle_03_r",
	&"middle_04_leaf_r",
	&"ring_01_r",
	&"ring_02_r",
	&"ring_03_r",
	&"ring_04_leaf_r",
	&"pinky_01_r",
	&"pinky_02_r",
	&"pinky_03_r",
	&"pinky_04_leaf_r",
]
## Carry overlay state played when picking up an object.
@export var carry_pickup_overlay_state: StringName = &"Carry_Pickup"
## Carry overlay state played while holding an object.
@export var carry_hold_overlay_state: StringName = &"Carry_Hold"
## Carry overlay state played when putting down an object.
@export var carry_put_down_overlay_state: StringName = &"Carry_PutDown"
## Optional AnimationTree OneShot request parameter used when picking up a carryable object.
@export var carry_pickup_request_parameter: String = "parameters/CarryPickup/request"
## Animation command sent when a carryable object is picked up.
@export var carry_pickup_anim_command: StringName = &""
## Animation command sent when a carried object is put down.
@export var carry_put_down_anim_command: StringName = &"CMD_PUTDOWN"
## Animation command sent when a carried object is thrown.
@export var carry_throw_anim_command: StringName = &"CMD_THROW"
## Crossfade used when returning from the carry throw animation.
@export var carry_throw_return_crossfade: float = 0.08
## Time from the end of a carry command animation that allows returning to locomotion.
@export var carry_command_exit_time_margin: float = 0.02


@export_storage var bounce_enabled: bool = true

## Gravity scale while in BOUNCE (button held, before landing).
@export_storage var bounce_gravity_scale: float = 2.35

## Gravity scale while in STOMP (button released).
@export_storage var stomp_gravity_scale: float = 2.5

## One-shot downward impulse when bounce is first triggered.
@export_storage var bounce_down_impulse: float = 40.0

## One-shot downward impulse when stomp is first entered.
@export_storage var stomp_down_impulse: float = 41.0

## If stomp impact speed exceeds this, subtract stomp_land_speed_subtract before applying landing momentum.
@export_storage var stomp_land_speed_threshold: float = 35.0

## Amount of stomp impact speed removed when above the threshold.
@export_storage var stomp_land_speed_subtract: float = 10.0

## If stomp tangential speed exceeds this, subtract stomp_land_horizontal_subtract.
@export_storage var stomp_land_horizontal_threshold: float = 0.0

## Amount of tangential speed removed when landing a stomp.
@export_storage var stomp_land_horizontal_subtract: float = 0.0

## Minimum impact speed we consider a proper bounce.
@export_storage var bounce_min_impact_speed: float = 10.0

## Extra speed added to the bounce upwards.
@export_storage var bounce_add_speed: float = 0.1

## Minimum upward speed of a bounce.
@export_storage var bounce_min_up_speed: float = 0.5

## Maximum upward speed of a bounce.
@export_storage var bounce_max_up_speed: float = 50.0

## If bounce impact speed exceeds this, subtract bounce_land_speed_subtract before launching.
@export_storage var bounce_land_speed_threshold: float = 35.0

## Amount of bounce impact speed removed when above the threshold.
@export_storage var bounce_land_speed_subtract: float = 10.0

## If bounce tangential speed exceeds this, subtract bounce_land_horizontal_subtract.
@export_storage var bounce_land_horizontal_threshold: float = 0.0

## Amount of tangential speed removed from a bounce landing.
@export_storage var bounce_land_horizontal_subtract: float = 0.0

@export_storage var spindash_enabled: bool = true
@export_storage var spindash_charge_time_max: float = 0.9
@export_storage var spindash_rail_charge_time_max: float = 0.9
@export_storage var spindash_ground_hold_time: float = 0.19
@export_storage var spindash_min_launch_speed: float = 15.0
@export_storage var spindash_max_launch_speed: float = 115.0
@export_storage var spindash_rail_max_launch_speed: float = 95.0
@export_storage var spindash_preserve_entry_speed_above_max: bool = true
## Decel while charging and holding the roll button.
@export_storage var spindash_charge_decel: float = 13.0
## Decel while charging without holding the roll button (faster stop).
@export_storage var spindash_charge_decel_unheld: float = 110.0
## Surface-relative speed at or below which grounded charge movement stops completely.
@export_storage var spindash_charge_stop_speed: float = 1.0
@export_storage var spindash_turn_penalty_disable_time: float = 0.5
@export_storage var spindash_jump_speed: float = 30.0
## Minimum horizontal speed (relative to gravity-up) when releasing a spindash in mid-air.
@export_storage var spindash_air_release_min_horizontal_speed: float = 15.0
## Extra horizontal boost applied when releasing below the minimum horizontal speed.
@export_storage var spindash_air_release_horizontal_boost: float = 8.0
## Downward speed ratio relative to horizontal speed when releasing a spindash in mid-air.
@export_storage var spindash_air_release_downward_ratio: float = 0.6



@export_group("Airborne Movement")
@export_subgroup("Turning")

## Air turn angle per second as a curve.
## X: lateral speed, Y: degrees per second.
@export var air_turn_angle_curve: Curve
## Maximum turn-rate multiplier reached when input asks for a sharp course change.
@export_range(1.0, 3.0, 0.05) var air_turn_sharp_rate_multiplier: float = 1.2
## Fraction of ordinary turn deceleration ignored during sharp airborne turns.
@export_range(0.0, 1.0, 0.05) var air_turn_speed_preservation: float = 0.9
## Deceleration applied when airborne input opposes the current course.
@export var air_brake_decel: float = 28.0
## Input angle where airborne steering begins transitioning into a direct pullback.
## Sideways and near-sideways input below this angle keeps the normal wide arc.
@export_range(90.0, 175.0, 1.0) var air_pullback_start_angle_deg: float = 125.0
## Fraction of normal turn rate retained during a direct 180-degree airborne pullback.
@export_range(0.0, 1.0, 0.05) var air_pullback_turn_rate_multiplier: float = 0.0
## Maximum air-brake multiplier reached during a direct 180-degree pullback.
@export_range(1.0, 4.0, 0.05) var air_pullback_brake_multiplier: float = 2.0

@export_storage var air_turn_free_angle_deg: float = 0.0
@export_storage var air_turn_max_penalty_angle_deg: float = 360.0
@export_storage var air_turn_max_penalty_angle_curve: Curve
@export_storage var air_turn_free_angle_curve: Curve
@export_storage var air_turn_min_speed_factor: float = 0.86

## Enables locomotion-only smoothing for small high-speed steering corrections.
@export_storage var input_intent_smoothing_enabled: bool = false
## Enables input intent smoothing while airborne.
@export_storage var input_intent_smoothing_airborne_enabled: bool = true
## Lateral speed where input intent smoothing begins to apply.
@export_storage var input_intent_smoothing_min_speed: float = 45.0
## Lateral speed where input intent smoothing reaches full strength.
@export_storage var input_intent_smoothing_full_speed: float = 100.0
## Course deviation that receives the full smoothing strength.
@export_storage var input_intent_smoothing_full_angle_deg: float = 15.0
## Course deviation that bypasses input intent smoothing.
@export_storage var input_intent_smoothing_bypass_angle_deg: float = 70.0
## Response rate used to move the filtered intent toward the current input.
@export_storage var input_intent_smoothing_response: float = 14.0
## Maximum angular distance the filtered intent can lag behind the current input.
@export_storage var input_intent_smoothing_max_lag_deg: float = 10.0

## Minimum lateral speed before skidding can start.
@export_storage var skid_enter_min_speed: float = 20.0

## Speed below which skidding will auto-exit (even if angle is still opposite).
@export_storage var skid_exit_min_speed: float = 0.0

## Angle (deg) between movement direction and input direction at which
## skidding starts (close to 180°).
@export_storage var skid_enter_angle_deg: float = 160.0

## Angle (deg) below which skidding cancels again
@export_storage var skid_exit_angle_deg: float = 150.0

## Extra deceleration applied while skidding (on top of usual stuff).
@export_storage var skid_decel: float = 130.0

## Maximum slope angle (deg, vs gravity-up) on which skidding is allowed.
## This keeps skids restricted to "ground-like" surfaces, not walls/loops.
@export_storage var skid_max_ground_angle_deg: float = 80.0

## How fast you can turn while skidding.
@export_storage var skid_turn_deg_per_sec: float = 5.0


# -----------------------------------------------------------
# COLLISION GEOMETRY LOCKING
# -----------------------------------------------------------
@export_group("Collision and Grounding")
@export_subgroup("Collision Geometry")

## Distance from the character center to the contact point along the surface normal.
## For a 2-unit tall capsule centered on the character, this is usually about 1.0.
@export var collision_ground_distance: float = 1.0


# -----------------------------------------------------------
# GROUND FOLLOW (RAYCAST WHILE ATTACHED)
# -----------------------------------------------------------
@export_subgroup("Ground Follow")

## Ray length used when attached (follows surface normal, used for loops and walls).
@export var ground_ray_length: float = 1.65


# -----------------------------------------------------------
# ADHESION / LOOP PHYSICS
# -----------------------------------------------------------
@export_group("Surface Physics")
@export_subgroup("Adhesion/General")

# ...
@export var adhesion_enabled: bool = true
@export var launch_immunity_time: float = 0.0

## When attached to a non-floor surface, if we bump into a floor-like
## surface and our speed is below this, we detach and fall.
@export var nonfloor_floor_detach_speed: float = 0.5

## Max angle where we still treat a surface like "floor-ish"
@export var adhesion_floor_max_angle_deg: float = 60.0

## Gravity-up speed at which we refuse to stick to steep slopes.
@export var adhesion_max_upward_speed_world: float = 14.0

## Minimum speed to cling to steep loop / ceiling surfaces
@export var adhesion_min_loop_speed: float = 18.0

## Fraction of velocity that must be tangential to surface to cling
@export_range(0.0, 1.0)
var adhesion_min_tangent_fraction: float = 0.35

## Max outward speed (moving away from surface along its normal)
@export var adhesion_max_outward_speed: float = 20.0

@export_subgroup("Adhesion/Loop Launch")
## Minimum gravity-up angle (deg) for ramp/loop launch to kick in.
## Below this, detach just keeps tangential velocity (no extra pop).
@export var launch_min_world_angle_deg: float = 120.0
## Surface angle where loop launch starts fading back to tangent-only release.
@export var launch_ceiling_fade_start_angle_deg: float = 145.0
@export var launch_ceiling_cutoff_angle_deg: float = 170.0
@export var launch_min_world_vertical_speed: float = 1.0
## Maximum gravity-up speed a loop launch can add. Set <= 0 to disable added vertical speed.
@export var launch_max_added_world_vertical_speed: float = 35.0

@export_subgroup("Adhesion/Loop Control")
## Above this gravity-up angle, we treat the surface as loop-like and
## drive forward/back along the current tangential velocity instead
## of using camera yaw. (Helps diagonal loops behave.)
@export var loop_input_steep_angle_deg: float = 360.0

## Above this gravity-up angle (deg) we start blending from camera-based
## forward to loop-tangent based forward for input.
@export var loop_input_blend_start_deg: float = 360.0

## At / above this angle (deg) input forward is fully aligned to loop tangent.
@export var loop_input_blend_full_deg: float = 360.0

## Max angle between consecutive surface normals we will "forgive"
## for the purposes of staying attached on loops / slopes.
@export var corner_max_angle_deg: float = 30.0

## Minimum speed required for corner forgiveness to kick in.
@export var corner_min_speed: float = 12.0

## How strongly we move toward the new normal on a forgiven corner (0..1).
@export_range(0.0, 1.0)
var corner_smoothing_strength: float = 0.5

## If true, prevents follow ray from detecting outer corner surfaces based on player local alignment.
@export var outer_corner_detection_enabled: bool = false
## Minimum angle (deg) between velocity and new surface normal to detect as outer corner.
@export var outer_corner_min_angle_deg: float = 60.0

@export_subgroup("Adhesion/Detach Fallback")
## If the normal used to detach differs from the current surface normal
## by more than this angle (deg) while on a floor-like surface, ignore
## that last-moment normal and use the current ground normal instead.
@export var detach_ignore_last_moment_angle_deg: float = 80.0
## Rejects sudden detach normals that differ sharply from the last stable attached normal.
@export var detach_stable_normal_filter_enabled: bool = true
## Minimum angle change needed before a detach normal is treated as a possible one-frame spike.
@export var detach_stable_normal_filter_angle_deg: float = 55.0

@export_subgroup("Adhesion/Angle Ranges")

## Minimum angle (deg) where the surface begins to count as non-flat for adhesion.
@export var adhesion_min_angle_deg: float = 5.0

## Angle (deg) past which adhesion requires sufficient speed instead of automatic sticking.
@export var adhesion_detach_angle_start_deg: float = 86.0

## Maximum angle (deg). Beyond this value, adhesion is not allowed.
@export var adhesion_max_angle_deg: float = 180.0

## Maximum angle (deg) between the current surface normal and a new
## contact's normal for collision-based "follow" attachment.
## Larger changes require a proper radial landing from air.
@export var adhesion_max_step_angle_from_current_deg: float = 30.0

## Band around 90° (vertical) where adhesion is NEVER allowed.
## e.g. 1.5 = anything in [88.5°, 91.5°] is treated as non-attachable.
@export var adhesion_vertical_forbid_half_width_deg: float = 2.0

@export_subgroup("Adhesion/Surface Smoothing")
## Max angle (deg) the ground normal is allowed to rotate per second.
## Lower = smoother but “stiffer”; higher = more responsive but noisier.
@export var normal_smooth_max_angle_deg_per_sec: float = 0.0

var _smoothed_surface_normal: Vector3 = Vector3.UP


@export_subgroup("Adhesion/Speed Requirements")

## Required lateral speed to remain attached at exactly vertical (90°).
@export var adhesion_speed_at_90: float = 17.0

## Required lateral speed to remain attached at fully inverted (180°).
@export var adhesion_speed_at_180: float = 26.0

## Time after a speed-based detach where similar surface angles cannot re-attach.
@export var low_speed_detach_reattach_block_time: float = 0.25

## Angle tolerance around the detached surface angle blocked from re-attachment.
@export var low_speed_detach_reattach_block_angle_tolerance_deg: float = 10.0


@export_subgroup("Adhesion/Airborne Visual Up")

## Delay before visual_up begins blending back toward gravity-up while airborne.
#@export var airborne_up_blend_delay: float = 0.0

## Blend speed for visual_up toward gravity-up transition.
#@export var airborne_up_blend_speed: float = 60.0

@export_subgroup("Wall/Slide and Friction")

## Angle (deg) from the player's current up-direction that is still considered
## walkable. Anything steeper behaves like a wall for friction/grazing.
@export var walkable_from_up_max_angle_deg: float = 50.0

## Angle (deg) between approach direction and wall normal at which
## the contact is treated as a strong head-on hit.
@export var wall_stop_max_angle_deg: float = 20.0

## Angle (deg) where graze friction begins.
@export var wall_graze_min_angle_deg: float = 30.0

## Angle (deg) from wall-parallel movement that applies no wall friction.
@export var wall_parallel_forgive_angle_deg: float = 40.0

## Maximum surface angle (deg) from player-up that can use wall friction.
@export var wall_from_up_max_angle_deg: float = 130.0

## Enables wall contact input projection.
@export var wall_input_projection_enabled: bool = true

## Enables wall contact input projection while airborne.
@export var wall_input_projection_airborne_enabled: bool = false

## Time (sec) that wall input projection remains after contact separates.
@export var wall_input_projection_linger_time: float = 0.09

## Angle (deg) from wall-parallel movement where input fully follows the wall.
@export var wall_input_parallel_angle_deg: float = 40.0

## Angle (deg) from head-on wall movement where input pushes directly into the wall.
@export var wall_input_direct_push_angle_deg: float = 20.0

## Base wall friction strength (units/sec^2).
@export var wall_friction: float = 0.1

## Fraction of friction used when grazing along a wall.
@export var wall_graze_friction_scale: float = 0.3

#@export_group("Animation")
#@export var hard_landing_speed_threshold: float = 28.0
@export var landing_linger_time: float = 0.15
@export var jump_dash_recent_time: float = 0.25

# -----------------------------------------------------------
# RADIAL LANDING (ANGLE / SPEED RULES)
# -----------------------------------------------------------
@export_group("Surface Transitions")
@export_subgroup("Radial Landing")


@export_subgroup("Alignment Exclusions")
## Legacy physics layers that block movement without becoming player-aligned surfaces.
## Surface attachment metadata is preferred for new level geometry.
@export_flags_3d_physics var non_alignable_surface_mask: int = 1 << 6
## Physics layers ignored by player movement while an attack is active.
@export_flags_3d_physics var attack_pass_through_surface_mask: int = 1 << 7
## Time the damaging enemy boundary is ignored so the upward hurt launch can clear it.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:s") var enemy_hurt_boundary_pass_through_sec: float = 0.2

@export_subgroup("Radial Landing/Wall and Ceiling Grab")

## Minimum hit angle (deg) between approach direction and surface normal for attachment.
## Lower angles are treated as head-on impacts.
@export var radial_landing_min_angle_deg: float = 35.0

## Minimum tangential speed required to attach via radial landing on walls/ceilings.
@export var radial_landing_min_speed: float = 7.0

@export_subgroup("Radial Landing/Surface Preview")
## Enables geometry-aware validation for airborne attachment to non-floor surfaces.
@export var surface_preview_enabled: bool = true
## Maximum gravity-up angle accepted as an unconditional floor landing.
@export_range(0.0, 89.0, 0.5) var surface_preview_floor_max_angle_deg: float = 60.0
## Local-space radius override used for preview scaling. Values at or below zero use the active collision shape.
@export var surface_preview_radius_override: float = 0.0
## Travel time represented by the speed-scaled preview distance.
@export var surface_preview_time_horizon: float = 0.12
## Minimum preview distance measured in collision radii.
@export var surface_preview_min_lookahead_radii: float = 24.0
## Maximum preview distance measured in collision radii.
@export var surface_preview_max_lookahead_radii: float = 48.0
## Preferred spacing between preview samples. The sample budget may increase this spacing for long previews.
@export var surface_preview_sample_spacing_radii: float = 0.65
## Minimum number of geometry samples used by a preview.
@export var surface_preview_min_samples: int = 6
## Maximum geometry-query budget per preview. Preview distance is controlled independently by lookahead.
@export var surface_preview_max_samples: int = 18
## Ray depth from the predicted player center measured in collision radii.
@export var surface_preview_probe_depth_radii: float = 2.25
## Tangential and lateral spread used by fallback probe rays.
@export_range(0.0, 1.0, 0.05) var surface_preview_probe_fan_spread: float = 0.35
## Offset applied to preview ray origins to avoid exact collider boundaries, measured in collision radii.
@export var surface_preview_seam_probe_offset_radii: float = 0.08
## Maximum forward distance used to recover attached contact across collider seams, measured in collision radii.
@export var surface_preview_seam_follow_distance_radii: float = 0.5
## Number of progressively farther probes used to recover attached contact across collider seams.
@export_range(1, 8, 1) var surface_preview_seam_follow_probe_count: int = 3
## Maximum predicted-center error accepted by seam recovery, measured in collision radii.
@export var surface_preview_seam_center_tolerance_radii: float = 0.75
## Maximum normal change accepted between consecutive preview samples.
@export_range(0.0, 180.0, 0.5) var surface_preview_max_normal_step_deg: float = 35.0
## Minimum accumulated concave normal rotation required for radial attachment.
@export_range(0.0, 180.0, 0.5) var surface_preview_min_concave_turn_deg: float = 4.0
## Maximum accumulated convex or reverse rotation allowed in a valid preview.
@export_range(0.0, 180.0, 0.5) var surface_preview_max_reverse_turn_deg: float = 5.0
## Maximum distance before concave rotation begins, measured in collision radii.
@export var surface_preview_max_curve_start_radii: float = 1.5
## Minimum accepted curve radius measured against the player collision radius.
@export var surface_preview_min_curve_radius_scale: float = 1.1
## Minimum fraction of requested samples that must find continuous support.
@export_range(0.0, 1.0, 0.05) var surface_preview_min_coverage: float = 0.8
## Maximum centerline gap between consecutive samples relative to requested spacing.
@export var surface_preview_max_gap_scale: float = 2.25
## Minimum estimated surface reaction acceleration required for airborne radial attachment.
@export var surface_preview_min_reaction_accel: float = 0.5
## Enables bounded contact continuity across collider seams while already attached.
@export var surface_preview_retention_enabled: bool = true
## Maximum contact support grace time across collision facets and short sampling gaps.
@export var surface_preview_retention_grace_time: float = 0.06
## Maximum contact support grace distance measured in collision radii.
@export var surface_preview_retention_grace_radii: float = 4.0
## Duration of the last preview visualization after a candidate collision.
@export var surface_preview_debug_duration: float = 0.5

@export var landing_momentum_floor_scale: float = 1.0
@export var landing_momentum_nonfloor_scale: float = 1.0
@export var debug_landing_momentum: bool = false

@export_subgroup("Radial Landing/Floor to Wall Exceptions")

## Angle (deg) from gravity-up considered "floor-like" for detach surface.
@export var floor_like_max_angle_deg: float = 30.0
## Angle (deg) above which we treat a surface as "ceiling-like"
## for the purpose of blocking floor→ceiling grabs.
@export var ceiling_like_min_angle_deg: float = 165.0


## Range of angles (deg) around 90° considered "wall-like".
@export var wall_like_min_angle_deg: float = 60.0
@export var wall_like_max_angle_deg: float = 120.0

## Time window (sec) after leaving a non-floor surface during which
## wall attachment is still allowed. After this, wall behaves like a bonk.
@export var nonfloor_to_wall_grace_time: float = 2.0

## Angle (deg) up to which a previous surface is still considered
## "floor-like" FOR THE PURPOSE of blocking floor→wall radial grabs.
## Anything <= this is treated as floor-ish and cannot stick to walls
## immediately after detach.
@export var wall_block_floor_like_angle_deg: float = 30.0


@export var floor_to_steep_forbid_min_angle_deg: float = 75.0


# -----------------------------------------------------------
# SLOPE PHYSICS
# -----------------------------------------------------------
@export_group("Slope and Platform Physics")
@export_subgroup("Slope/General")

## Angle where the near-flat slope response fade reaches full strength.
@export var slope_flat_angle_threshold_deg: float = 5.0

## Legacy maximum slope-effect angle retained for scene compatibility.
@export_storage var slope_max_effect_angle_deg: float = 30.0


@export_subgroup("Slope/Downhill and Uphill")

## Downhill response acceleration at full effect under baseline gravity.
@export_storage var slope_downhill_accel: float = 85.0

## Optional downhill acceleration by lateral speed.
## X: lateral speed, Y: acceleration.
@export_storage var slope_downhill_accel_curve: Curve

## Uphill response acceleration at full effect under baseline gravity.
@export_storage var slope_uphill_decel: float = 39.0

## Optional uphill deceleration by lateral speed.
## X: lateral speed, Y: deceleration.
@export_storage var slope_uphill_decel_curve: Curve

@export_storage var slope_uphill_response_blend_speed: float = 4.0
@export_storage var slope_gravity_angle_curve: Curve

@export_storage var slope_uphill_start_traction_speed: float = 3.0
@export_storage var slope_uphill_start_accel_ratio: float = 0.25
@export_storage var slope_reversal_guard_enabled: bool = true
@export_storage var slope_reversal_guard_min_angle_deg: float = 45.0
@export_storage var slope_reversal_guard_arm_uphill_speed: float = 12
@export_storage var slope_reversal_guard_recovery_distance: float = 120
@export_storage var slope_reversal_guard_pull_multiplier: float = 2.5
@export_storage var slope_reversal_guard_momentum_preserve_speed: float = 160
@export_storage var slope_reversal_guard_turn_preservation: float = 0.0
@export_storage var slope_reversal_guard_turn_alignment: float = 0.4
@export_storage var slope_reversal_guard_air_reset_time: float = 1.25
@export_storage var slope_idle_hold_speed: float = 2.0
@export_storage var slope_static_hold_hysteresis_deg: float = 3.0
@export_storage var slope_slide_resistance: float = 6.0
@export_storage var slope_slide_linear_drag: float = 0.0
@export_storage var slope_slide_quadratic_drag: float = 0.0015
@export_storage var slope_downhill_soft_cap_bypass: bool = true
@export_storage var slope_downhill_soft_cap_min_alignment: float = 0.05

@export_subgroup("Slope/Uphill Control")

## Surface angle where uphill control starts being limited against slope decel.
@export_storage var slope_uphill_control_ratio_min_angle_deg: float = 70.0

## Surface angle where uphill control reaches the curve's full ratio.
@export_storage var slope_uphill_control_ratio_full_angle_deg: float = 85.0

## Ratio of downhill slope acceleration available to uphill motor control.
## X: angle range fraction (0..1), Y: retained ratio.
@export_storage var slope_uphill_control_ratio_curve: Curve
## Strength of excess-acceleration adaptation during the steep-slope angle transition.
@export_storage var slope_uphill_control_accel_adaptation: float = 1.0
## Surface-tangential speed below which the steep-slope control limit has full effect.
@export_storage var slope_uphill_control_limit_full_speed: float = 20.0
## Surface-tangential speed at which earned momentum fully releases the control limit.
@export_storage var slope_uphill_control_limit_release_speed: float = 65.0

@export_subgroup("Platforms/Moving")

## Maximum horizontal speed (m/s) that a moving floor can carry or impart to the player.
## Acts as a safety cap against runaway velocity from jittery or fast-moving physics bodies.
@export var max_platform_carry_speed: float = 120.0
## Applies platform displacement before move_and_slide.
@export var manual_platform_position_carry_enabled: bool = false

## Scale applied to downhill tangential gravity on a RigidBody3D floor.
## Uphill gravity response remains active. A value of 0.0 prevents rotating contact normals
## from injecting downhill speed on curved physics objects.
@export_range(0.0, 1.0) var slope_rigid_body_downhill_factor: float = 0.0


@export_subgroup("Slope/Sliding")

## Angle from gravity-up where passive static traction releases.
@export_storage var slope_slide_start_angle_deg: float = 40.0

## Legacy slide acceleration retained for scene compatibility.
@export_storage var slope_slide_accel: float = 50.0

## Legacy low-speed slide threshold retained for scene compatibility.
@export var slope_slide_min_speed: float = 2.5

@export_group("Items and Power-Ups")

@export_subgroup("Speed Shoes")
## Duration applied when a Speed Shoes reward does not provide an override.
@export_range(0.0, 300.0, 0.1, "or_greater", "suffix:s") var speed_shoes_duration: float = 13.0
## Ground and air acceleration sampled by lateral speed while Speed Shoes are active.
## If unset, the current movement acceleration curve remains in use.
@export var speed_shoes_acceleration_curve: Curve
## Multiplier applied to normal ground and air top speeds while Speed Shoes are active.
@export_range(0.0, 10.0, 0.01, "or_greater") var speed_shoes_top_speed_multiplier: float = 1.25
## Music started immediately at full volume when Speed Shoes are obtained.
@export var speed_shoes_music: AudioStream = preload("res://LS5Framework/Sounds/Music/Events/Event_SpeedShoes.ogg")
## Music priority used by the Speed Shoes event.
@export var speed_shoes_music_priority: int = MusicController.PRIORITY_EVENT
## Time before the end of the Speed Shoes track when the return crossfade begins.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var speed_shoes_music_end_lead_time: float = 1.0
## Crossfade duration used when returning to the underlying music.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var speed_shoes_music_return_crossfade: float = 3.0

@export_subgroup("Invincibility")
## Duration applied when an Invincibility reward does not provide an override.
@export_range(0.0, 300.0, 0.1, "or_greater", "suffix:s") var invincibility_duration: float = 18.5
## Music started when Invincibility is obtained.
@export var invincibility_music: AudioStream = preload("res://LS5Framework/Sounds/Music/Events/Event_Invincible.ogg")
## Priority used by the Invincibility event music.
@export var invincibility_music_priority: int = MusicController.PRIORITY_EVENT
## Time the event music continues after invincibility ends before the return crossfade begins.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var invincibility_music_end_delay: float = 1.0
## Crossfade duration used when returning to the underlying music.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var invincibility_music_return_crossfade: float = 3.0

@export_group("Audio")

@export_subgroup("Item Collection")
## Item-to-sound associations used by all item grant sources.
@export var item_audio_associations: Array[Resource] = [
	preload("res://LS5Framework/Resources/Items/RingAudioAssociation.tres"),
	preload("res://LS5Framework/Resources/Items/SpeedShoesAudioAssociation.tres"),
]
## Audio bus used by item collection sounds.
@export var item_collection_sound_bus: StringName = &"SFX"
## Maximum audible distance for item collection sounds.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var item_collection_sound_max_distance: float = 65.0

@export_subgroup("Footsteps")
@export var footstep_player: AudioStreamPlayer3D          # Assign the SFX player node in the inspector
@export var footstep_sounds_default: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Footstep_Hard_1.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Footstep_Hard_2.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Footstep_Hard_3.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Footstep_Hard_4.wav"),
]
@export var footstep_sounds_gravel: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_01.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_02.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_03.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_04.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_05.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_06.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_07.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_08.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_09.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_10.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_11.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Gravel/Step_Gravel_12.wav"),
]
@export var footstep_sounds_sand: Array[AudioStream] = []
@export var footstep_sounds_tile: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Tile/Pl_Footstep_Hard_StoneMarble_Run_00_L.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Tile/Pl_Footstep_Hard_StoneMarble_Run_00_R.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Tile/Pl_Footstep_Hard_StoneMarble_Run_01_L.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Tile/Pl_Footstep_Hard_StoneMarble_Run_01_R.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Tile/Pl_Footstep_Hard_StoneMarble_Run_02_L.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Tile/Pl_Footstep_Hard_StoneMarble_Run_02_R.wav"),
]
@export var footstep_sounds_dirt: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_01.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_02.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_03.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_04.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_05.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_06.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_07.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Dirt/Step_Dirt_08.wav"),
]
@export var footstep_sounds_wood: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_01.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_02.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_03.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_04.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_05.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_06.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_07.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_08.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_09.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Wood/Step_Wood_10.wav"),
]
@export var footstep_sounds_grass: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_01.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_02.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_03.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_04.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_05.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_06.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_07.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_08.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_09.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Grass/Step_Grass_10.wav"),
]
@export var footstep_sounds_stone: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_01.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_02.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_03.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_04.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_05.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_06.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_07.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Stone/Step_Stone_08.wav"),
]
@export var footstep_sounds_water: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_01.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_02.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_03.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_04.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_05.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_06.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_07.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_08.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_09.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_10.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_11.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Water/Step_Water_12.wav"),
]
@export var footstep_sounds_metal: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_01.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_02.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_03.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_04.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_05.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_06.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_07.wav"),
	preload("res://LS5Framework/Sounds/Footstep/Metal/Step_MetalSolid_08.wav"),
]

@export_subgroup("Footsteps/Footstep Volume By Speed")
@export_range(0.0, 1.0) var footstep_min_volume: float = 0.12
@export_range(0.0, 1.0) var footstep_max_volume: float = 0.4
@export var footstep_full_volume_speed: float = 300.0           # speed that counts as "top speed"

@export_subgroup("Footsteps/Dust")
## Scene spawned when a footstep emits dust.
@export var footstep_dust_scene: PackedScene = preload("res://LS5Framework/Particles/FootstepDustBurst.tscn")
## Location used when the left foot emits dust.
@export var left_foot_dust_emitter: Node3D
## Location used when the right foot emits dust.
@export var right_foot_dust_emitter: Node3D

@export_subgroup("Movement/Skidding")
## Looping skid sound player.
@export var sfx_skid_loop: AudioStreamPlayer3D
## Skid loop used when no specific surface sound is available.
@export var skid_sound_default: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Default_Asphalt.wav")
## Skid loop used on gravel surfaces.
@export var skid_sound_gravel: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Gravel.wav")
## Skid loop used on sand surfaces.
@export var skid_sound_sand: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Sand.wav")
## Skid loop used on tile surfaces.
@export var skid_sound_tile: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Tile.wav")
## Skid loop used on dirt surfaces.
@export var skid_sound_dirt: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Dirt.wav")
## Skid loop used on wood surfaces.
@export var skid_sound_wood: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Wood.wav")
## Skid loop used on grass surfaces.
@export var skid_sound_grass: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Grass.wav")
## Skid loop used on stone surfaces.
@export var skid_sound_stone: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Stone.wav")
## Skid loop used on water surfaces or while submerged.
@export var skid_sound_water: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Water.wav")
## Skid loop used on metal surfaces.
@export var skid_sound_metal: AudioStream = preload("res://LS5Framework/Sounds/Skidding/Skidding_Metal.wav")
## Speed where skid volume and pitch scaling begin.
@export var skid_sound_min_speed: float = 20.0
## Speed where skid volume and pitch scaling reach the maximum value.
@export var skid_sound_full_speed: float = 90.0
## Minimum skid loop volume.
@export var skid_sound_volume_min_db: float = -17.0
## Maximum skid loop volume.
@export var skid_sound_volume_max_db: float = 50.0
## Skid loop pitch at low speed.
@export var skid_sound_pitch_slow: float = 1.25
## Skid loop pitch at high speed.
@export var skid_sound_pitch_fast: float = 0.92
## Decibels per second used when skidding starts.
@export var skid_sound_fade_in_speed_db: float = 400.0
## Decibels per second used when skidding stops.
@export var skid_sound_fade_out_speed_db: float = 100.0
## Volume where the skid loop stops after fade out.
@export var skid_sound_stop_volume_db: float = -60.0
## If true, default skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_default: bool = true
## If true, gravel skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_gravel: bool = true
## If true, sand skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_sand: bool = true
## If true, tile skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_tile: bool = false
## If true, dirt skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_dirt: bool = true
## If true, wood skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_wood: bool = true
## If true, grass skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_grass: bool = true
## If true, stone skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_stone: bool = true
## If true, water skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_water: bool = true
## If true, metal skid pitch is lower at slow speed and higher at high speed.
@export var skid_pitch_reverse_metal: bool = false
## Time between skid dust bursts.
@export var skid_dust_interval: float = 0.035
## Minimum lateral speed required to emit skid dust.
@export var skid_dust_min_speed: float = 10.0

@export_subgroup("Abilities/General")
@export var sfx_player: AudioStreamPlayer3D          # Assign the SFX player node in the inspector
## Audio player used for character voice clips.
@export var dialogue_player: AudioStreamPlayer3D
## Maximum audible distance for replicated player voices.
@export_range(1.0, 1000.0, 0.1, "or_greater", "suffix:m") var remote_voice_max_distance: float = 80.0
## Distance at which replicated player voices begin attenuating.
@export_range(0.1, 1000.0, 0.1, "or_greater", "suffix:m") var remote_voice_unit_size: float = 12.0
@export var jump_sounds: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Abilities/SA_Jump_1.wav"),
	preload("res://LS5Framework/Sounds/Abilities/SA_Jump_2.wav"),
	preload("res://LS5Framework/Sounds/Abilities/SA_Jump_3.wav"),
	preload("res://LS5Framework/Sounds/Abilities/SA_Jump_4.wav"),
]
@export var jumpdash_sounds: Array[AudioStream] = [
	preload("res://LS5Framework/Sounds/Abilities/JumpDash_1.wav"),
	preload("res://LS5Framework/Sounds/Abilities/JumpDash_2.wav"),
	preload("res://LS5Framework/Sounds/Abilities/JumpDash_3.wav"),
	preload("res://LS5Framework/Sounds/Abilities/JumpDash_4.wav"),
]

@export_subgroup("Abilities/Bounce and Stomp")
@export var sfx_bounce_start: AudioStreamPlayer3D
@export var sfx_bounce_land: AudioStreamPlayer3D
@export var sfx_stomp_start: AudioStreamPlayer3D
@export var sfx_stomp_land: AudioStreamPlayer3D

@export_subgroup("Abilities/Spindash")
@export var sfx_spindash_charge_loop: AudioStreamPlayer3D
@export var sfx_spindash_charge_full: AudioStreamPlayer3D
@export var sfx_spindash_release: AudioStreamPlayer3D

@export_subgroup("Abilities/Barrier Blast")
@export var sfx_barrier_blast_wind: AudioStreamPlayer3D
@export var sfx_barrier_blast_boom: AudioStreamPlayer3D
@export var barrier_blast_wind_volume_min_db: float = -120.0
@export var barrier_blast_wind_volume_max_db: float = 12.0
@export var barrier_blast_wind_pitch_min: float = 0.01
@export var barrier_blast_wind_pitch_max: float = 11.0
@export_range(0.0, 1.0) var barrier_blast_wind_speed_weight: float = 0.0
## Time for the buildup loop to fade in after crossing its speed threshold.
@export_range(0.01, 2.0, 0.01, "suffix:s") var barrier_blast_wind_fade_in_time: float = 0.22
## Time for the buildup loop to fade out after dropping below its speed threshold.
@export_range(0.01, 2.0, 0.01, "suffix:s") var barrier_blast_wind_fade_out_time: float = 0.20
## Volume used while the buildup loop is fading from silence.
@export_range(-120.0, -20.0, 1.0, "suffix:dB") var barrier_blast_wind_silent_db: float = -80.0
## Reverb bus used for the low-buildup wet layer.
@export var barrier_blast_wind_reverb_bus: StringName = &"BarrierBlastWet"
## Reverb send amount at the bottom of the buildup range.
@export_range(0.0, 1.0, 0.01) var barrier_blast_wind_wet_amount_low: float = 0.55
## Reverb send amount at full buildup intensity.
@export_range(0.0, 1.0, 0.01) var barrier_blast_wind_wet_amount_high: float = 0.05
## Shapes how quickly the wet quality recedes as buildup intensity increases.
@export_range(0.1, 4.0, 0.05) var barrier_blast_wind_wet_curve: float = 0.75

@export_subgroup("Movement/Wind")
@export var sfx_speed_wind: AudioStreamPlayer3D
@export var speed_wind_min_speed: float = 50.0
@export var speed_wind_full_speed: float = 160.0
@export var speed_wind_volume_min_db: float = -30.0
@export var speed_wind_volume_max_db: float = -1.0
@export var speed_wind_pitch_min: float = 0.9
@export var speed_wind_pitch_max: float = 1.9

@export_subgroup("Abilities/Rail Grinding")
## One-shot player used when leaving a rail.
@export var sfx_rail_detach: AudioStreamPlayer3D
@export var sfx_rail_land: AudioStreamPlayer3D
@export var sfx_rail_grind_loop: AudioStreamPlayer3D
@export_storage var rail_grind_min_speed: float = 3.0
@export_storage var rail_grind_full_speed: float = 65.0
@export_storage var rail_grind_volume_min_db: float = -10.0
@export_storage var rail_grind_volume_max_db: float = 5.0
@export_storage var rail_grind_pitch_min: float = 0.8
@export_storage var rail_grind_pitch_max: float = 1.1
@export_storage var rail_grind_fade_speed_db: float = 60.0
@export_storage var rail_grind_stop_volume_db: float = -60.0

@export_subgroup("Abilities/Drift")
## Looping drift sound player (uses drift.ogg by default).
@export var sfx_drift_loop: AudioStreamPlayer3D
## Loop played while drifting.
@export_storage var drift_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/drift.ogg")
## Speed at which drift pitch starts to drop (slow speed = higher pitch).
@export_storage var drift_sound_min_speed: float = 15.0
## Speed at which drift pitch reaches its minimum.
@export_storage var drift_sound_full_speed: float = 120.0
## Lowest pitch used at high speed.
@export_storage var drift_sound_pitch_min: float = 0.92
## Highest pitch used at low speed.
@export_storage var drift_sound_pitch_max: float = 1.25
## Turn speed (deg/sec) where drift volume starts to rise.
@export_storage var drift_sound_turn_min_deg_per_sec: float = 15.0
## Turn speed (deg/sec) where drift volume reaches max.
@export_storage var drift_sound_turn_full_deg_per_sec: float = 180.0
## Minimum drift loop volume (dB) while drifting.
@export_storage var drift_sound_volume_min_db: float = -25.0
## Maximum drift loop volume (dB) at full turn speed.
@export_storage var drift_sound_volume_max_db: float = -2.0
## Lerp speed (per second) for smoothing turn-based volume changes.
@export_storage var drift_sound_turn_lerp_speed: float = 8.0

@export_subgroup("Movement/Engine Loop")
## Player used for the high-speed grounded engine loop.
@export var sfx_engine_loop: AudioStreamPlayer3D
## Loop played during high-speed default grounded movement.
@export_storage var engine_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Footstep/Engine_Loop.wav")
## Tangential speed where the engine loop starts fading in at minimum volume.
@export_storage var engine_sound_volume_min_speed: float = 50.0
## Tangential speed where the engine loop reaches maximum volume.
@export_storage var engine_sound_volume_full_speed: float = 130.0
## Engine loop volume at the volume minimum speed.
@export_storage var engine_sound_volume_min_db: float = -43.0
## Engine loop volume at full speed.
@export_storage var engine_sound_volume_max_db: float = -26.0
## Tangential speed where engine pitch begins increasing.
@export_storage var engine_sound_pitch_min_speed: float = 50.0
## Tangential speed where engine pitch reaches its maximum value.
@export_storage var engine_sound_pitch_full_speed: float = 200.0
## Engine loop pitch at the pitch minimum speed.
@export_storage var engine_sound_pitch_min: float = 1.3
## Engine loop pitch at full speed.
@export_storage var engine_sound_pitch_max: float = 1.8
## Blend speed for tangential-speed-driven volume and pitch changes.
@export_storage var engine_sound_lerp_speed: float = 300.0
## Fade-in rate in decibels per second.
@export_storage var engine_sound_fade_in_speed_db: float = 90.0
## Fade-out rate in decibels per second.
@export_storage var engine_sound_fade_out_speed_db: float = 40.0
## Volume where the faded-out engine loop stops playing.
@export_storage var engine_sound_stop_volume_db: float = -60.0

@export_subgroup("Movement/Roll")
## Player used for mutually interrupting roll start and end sounds.
@export var sfx_roll_transition: AudioStreamPlayer3D
## Player used for the speed-driven roll loop.
@export var sfx_roll_loop: AudioStreamPlayer3D

# Volumes (these are NOT speed-scaled)
@export_range(0.0, 2.0) var jump_volume: float = 0.4
@export_range(0.0, 2.0) var jumpdash_volume: float = 0.4

@export_subgroup("Voice/Events")
## Voice clips played by Wait animation call tracks.
@export var voice_wait_clips: Array[AudioStream] = []
## Chance for a Wait animation voice clip to play.
@export_range(0.0, 1.0, 0.01) var voice_wait_chance: float = 1.0
## Voice clips played on regular hurt.
@export var voice_hurt_clips: Array[AudioStream] = []
## Chance for regular hurt voice.
@export_range(0.0, 1.0, 0.01) var voice_hurt_chance: float = 1.0
## Voice clips played on non-pit death.
@export var voice_death_clips: Array[AudioStream] = []
## Chance for non-pit death voice.
@export_range(0.0, 1.0, 0.01) var voice_death_chance: float = 1.0
## Voice clips played on pit death.
@export var voice_pit_clips: Array[AudioStream] = []
## Chance for pit death voice.
@export_range(0.0, 1.0, 0.01) var voice_pit_chance: float = 1.0
## Voice clips played when exhausted flight is attempted.
@export var voice_exhausted_flight_clips: Array[AudioStream] = []
## Chance for exhausted flight voice.
@export_range(0.0, 1.0, 0.01) var voice_exhausted_flight_chance: float = 1.0
## Voice clips played after drift ends.
@export var voice_drift_end_clips: Array[AudioStream] = []
## Chance for drift end voice.
@export_range(0.0, 1.0, 0.01) var voice_drift_end_chance: float = 1.0
## Voice clips played when throwing a carried object.
@export var voice_carry_throw_clips: Array[AudioStream] = []
## Chance for carried object throw voice.
@export_range(0.0, 1.0, 0.01) var voice_carry_throw_chance: float = 1.0

@export_subgroup("Voice/Race")
## Voice clips played after the player is positioned at a race start.
@export var voice_race_start_clips: Array[AudioStream] = []
## Chance for race start voice.
@export_range(0.0, 1.0, 0.01) var voice_race_start_chance: float = 1.0
## Voice clips played when the player crosses a race finish line.
@export var voice_finish_line_clips: Array[AudioStream] = []
## Chance for finish line voice.
@export_range(0.0, 1.0, 0.01) var voice_finish_line_chance: float = 1.0
## Voice clips played by the winner during an online race results lineup.
@export var voice_race_end_clips: Array[AudioStream] = []
## Chance for online race end voice.
@export_range(0.0, 1.0, 0.01) var voice_race_end_chance: float = 1.0

@export_subgroup("Voice/Landing Combos")
## Chance for a rating voice when a combo completes or expires successfully.
@export_range(0.0, 1.0, 0.01) var voice_landing_combo_chance: float = 1.0
## Voice clips for rating tier 1 (Good). Thresholds follow the character visual profile.
@export var voice_landing_good_clips: Array[AudioStream] = []
## Voice clips for rating tier 2 (Great).
@export var voice_landing_great_clips: Array[AudioStream] = []
## Voice clips for rating tier 3 (Nice).
@export var voice_landing_nice_clips: Array[AudioStream] = []
## Voice clips for rating tier 4 (Jammin').
@export var voice_landing_jammin_clips: Array[AudioStream] = []
## Voice clips for rating tier 5 (Cool).
@export var voice_landing_cool_clips: Array[AudioStream] = []
## Voice clips for rating tier 6 (Radical).
@export var voice_landing_radical_clips: Array[AudioStream] = []
## Voice clips for rating tier 7 (Tight).
@export var voice_landing_tight_clips: Array[AudioStream] = []
## Voice clips for rating tier 8 (Awesome).
@export var voice_landing_awesome_clips: Array[AudioStream] = []
## Voice clips for rating tier 9 (Extreme).
@export var voice_landing_extreme_clips: Array[AudioStream] = []
## Voice clips for rating tier 10 (Perfect), also used for additional rating tiers.
@export var voice_landing_perfect_clips: Array[AudioStream] = []

@export_subgroup("Voice/Tricks")
## Voice clips played on backflip tricks.
@export var voice_trick_backflip_clips: Array[AudioStream] = []
## Chance for backflip trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_backflip_chance: float = 1.0
## Voice clips played on frontflip tricks.
@export var voice_trick_frontflip_clips: Array[AudioStream] = []
## Chance for frontflip trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_frontflip_chance: float = 1.0
## Voice clips played on left spin tricks.
@export var voice_trick_left_spin_clips: Array[AudioStream] = []
## Chance for left spin trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_left_spin_chance: float = 1.0
## Voice clips played on right spin tricks.
@export var voice_trick_right_spin_clips: Array[AudioStream] = []
## Chance for right spin trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_right_spin_chance: float = 1.0
## Voice clips played on frontflip-left-spin tricks.
@export var voice_trick_frontflip_left_spin_clips: Array[AudioStream] = []
## Chance for frontflip-left-spin trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_frontflip_left_spin_chance: float = 1.0
## Voice clips played on backflip-left-spin tricks.
@export var voice_trick_backflip_left_spin_clips: Array[AudioStream] = []
## Chance for backflip-left-spin trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_backflip_left_spin_chance: float = 1.0
## Voice clips played on backflip-right-spin tricks.
@export var voice_trick_backflip_right_spin_clips: Array[AudioStream] = []
## Chance for backflip-right-spin trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_backflip_right_spin_chance: float = 1.0
## Voice clips played on frontflip-right-spin tricks.
@export var voice_trick_frontflip_right_spin_clips: Array[AudioStream] = []
## Chance for frontflip-right-spin trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_frontflip_right_spin_chance: float = 1.0
## Voice clips played on forward rail tricks.
@export var voice_trick_rail_forward_clips: Array[AudioStream] = []
## Chance for forward rail trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_rail_forward_chance: float = 1.0
## Voice clips played on backward rail tricks.
@export var voice_trick_rail_backward_clips: Array[AudioStream] = []
## Chance for backward rail trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_rail_backward_chance: float = 1.0
## Voice clips played on forward crouch rail tricks.
@export var voice_trick_rail_forward_crouch_clips: Array[AudioStream] = []
## Chance for forward crouch rail trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_rail_forward_crouch_chance: float = 1.0
## Voice clips played on backward crouch rail tricks.
@export var voice_trick_rail_backward_crouch_clips: Array[AudioStream] = []
## Chance for backward crouch rail trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_rail_backward_crouch_chance: float = 1.0
## Voice clips played on bounce pogo tricks.
@export var voice_trick_bounce_pogo_clips: Array[AudioStream] = []
## Chance for bounce pogo trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_bounce_pogo_chance: float = 1.0
## Voice clips played on stomp darehog tricks.
@export var voice_trick_stomp_darehog_clips: Array[AudioStream] = []
## Chance for stomp darehog trick voice.
@export_range(0.0, 1.0, 0.01) var voice_trick_stomp_darehog_chance: float = 1.0


# -----------------------------------------------------------
# WATER PHYSICS
# -----------------------------------------------------------
@export_group("Environment")
@export_subgroup("Water/Movement")

## Enables the water physics system.
@export var water_physics_enabled: bool = true

## Uses an underwater movement clock instead of the submerged acceleration, speed, and vertical limits.
@export var water_logic_speed_enabled: bool = false
## Underwater movement clock multiplier, applied after gameplay and debuff multipliers.
@export_range(0.01, 1.0, 0.01) var water_logic_speed_multiplier: float = 0.5
## Real seconds used to smoothstep into the underwater movement clock. Exiting restores the non-water clock immediately.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var water_logic_speed_lerp_time: float = 0.35
## Preserves world velocity on grounded water exit by converting it to the remaining non-water movement clock. Water-surface running is excluded.
@export var water_logic_speed_preserve_grounded_exit_speed: bool = true
## Preserves world velocity on airborne water exit by converting it to the remaining non-water movement clock.
@export var water_logic_speed_preserve_airborne_exit_speed: bool = false

var _water_logic_speed_current: float = 1.0
var _water_logic_speed_start: float = 1.0
var _water_logic_speed_target: float = 1.0
var _water_logic_speed_elapsed: float = 0.0

## Multiplier applied to acceleration when submerged in water.
@export var water_accel_multiplier: float = 0.2

## Multiplier applied to deceleration when submerged (>1 = stronger decel).
@export var water_decel_multiplier: float = 1.12

## Multiplier applied to top speed when submerged.
@export var water_top_speed_multiplier: float = 0.45

## Horizontal top speed slowdown strength when submerged.
@export var water_top_speed_slowdown_strength: float = 0.3

## Multiplier applied to max upward vertical velocity when submerged.
@export var water_max_up_speed_mult: float = 0.8

## Multiplier applied to max downward (fall) vertical velocity when submerged.
@export var water_max_down_speed_mult: float = 0.25

## Rate used to pull vertical speed back toward submerged up/down limits.
@export var water_vertical_speed_slowdown_rate: float = 90.0

## Minimum speed required to run on water surface (classic water running).
@export var water_surface_min_speed: float = 75.0

## Slowdown strength specifically for water surface running.
@export var water_surface_slowdown_strength: float = 3.0

## Multiplier applied to water surface slowdown while drifting.
@export var water_surface_drift_slowdown_multiplier: float = 0.85

## Multiplier applied to spindash release speed while running on water.
@export_range(0.0, 1.0, 0.01) var water_surface_spindash_release_effectiveness: float = 0.2

## Flat tangential speed removed when landing on a water surface from the air.
@export_range(0.0, 100.0, 0.1, "or_greater") var water_surface_landing_speed_penalty: float = 10.0

## Distance moved below the water surface when water running fails.
@export var water_surface_sink_depth: float = 0.35

## Downward speed applied when water running fails.
@export var water_surface_sink_down_speed: float = 8.0

## Time after leaving water before the player can re-attach to water surface.
@export var water_reattach_cooldown: float = 0.3

## Maximum angle (deg) from water surface normal to qualify for surface landing.
## Lower angles are more head-on and will splash into the water.
@export var water_surface_landing_max_angle_deg: float = 45.0

## Minimum tangential speed required to land on water surface (radial landing style).
@export var water_surface_landing_min_tangential_speed: float = 98.0

@export_subgroup("Water/Detection")
## Node path to the head water detector Area3D (for neck-deep submersion check).
@export var head_water_detector: NodePath = ^"HeadWaterDetector"

@export_subgroup("Water/Audio Nodes")
## Audio player for water footstep sounds (plays on top of regular footsteps).
@export var footstep_player_water: NodePath

## Audio player for water splash sounds (entry/exit).
@export var water_sounds_player: NodePath

## Audio player for drowning countdown and drowned sounds.
@export var drowning_sounds_player: NodePath

@export_subgroup("Water/Audio Splashes")
## Splash sounds for shallow/glancing water entry and exit (low incidence angle).
@export var sfx_water_enter_soft: Array[AudioStream]

## Splash sounds for medium-angle water entry and exit.
@export var sfx_water_enter_medium: Array[AudioStream]

## Splash sounds for steep/direct water entry and exit (high incidence angle).
@export var sfx_water_enter_hard: Array[AudioStream]

## Splash sounds for shallow/glancing water exit.
@export var sfx_water_exit_soft: Array[AudioStream]

## Splash sounds for medium-angle water exit.
@export var sfx_water_exit_medium: Array[AudioStream]

## Splash sounds for steep/direct water exit.
@export var sfx_water_exit_hard: Array[AudioStream]

## Minimum incidence angle (deg) against water surface to play any splash at all.
@export var water_splash_min_angle_deg: float = 1.0

## Incidence angle (deg) threshold between soft and medium splash.
@export var water_splash_soft_angle_deg: float = 35.0

## Incidence angle (deg) threshold between medium and hard splash.
@export var water_splash_hard_angle_deg: float = 70.0

@export_subgroup("Water/Audio Footsteps")
## Time for water footstep sounds to fade out after leaving water (seconds).
@export var water_footstep_fade_time: float = 0.3

## Maximum water footstep timer value (caps the buildup).
@export var water_footstep_max_time: float = 4.5

## Minimum water footstep timer value when entering water volume.
@export var water_footstep_min_time: float = 2.5


# -----------------------------------------------------------
# INPUT / CAMERA / DEBUG
# -----------------------------------------------------------
@export_group("Input and Camera")
@export_subgroup("Debug Impulses")
@export var debug_add_up_speed: float = 35.0
@export var debug_add_up_use_physics_up: bool = true

@export var debug_forward_boost_amount: float = 100.0

@export_subgroup("Mouse Lock")

## Whether mouse is captured during gameplay.
@export var lock_cursor_to_game: bool = true

@export_group("Networking")
@export_subgroup("Replication")
## Enables netfox state replication for this character.
@export var network_replication_enabled: bool = true
## Number of network ticks between complete state snapshots.
@export_range(1, 240, 1) var network_full_state_interval_ticks: int = 30
## Number of ticks between unreliable diff-state acknowledgements.
@export_range(0, 60, 1) var network_diff_ack_interval_ticks: int = 3
## Smooths remote presentation between synchronized network ticks.
@export var network_interpolate_remote_state: bool = true
## Authoritative updates applied directly before interpolation begins for a newly connected remote player.
@export_range(1, 30, 1) var network_initial_snap_updates: int = 3

@export_group("Presentation")
@export_subgroup("UI")
@export var name_tag_enabled: bool = true
@export var name_tag_height: float = 2.4
@export var chat_bubble_enabled: bool = true
@export var chat_bubble_duration: float = 15.0
@export var chat_bubble_height_offset: float = 0.55

@export_subgroup("UI/Homing Reticle")
@export var homing_reticle_enabled: bool = true
@export var homing_reticle_texture: Texture2D
@export var homing_reticle_pixel_size: float = 0.01
@export var homing_reticle_height_offset: float = 0.0
@export var homing_reticle_scale_base: float = 0.1
@export var homing_reticle_scale_per_unit: float = 0.01
@export var homing_reticle_scale_max: float = 3.0
@export var homing_reticle_sound_enabled: bool = true
@export var homing_reticle_sound: AudioStream
@export var homing_reticle_sound_bus: StringName = &"UI"
@export var homing_reticle_sound_volume_db: float = -4.0

@export_subgroup("Effects/Speed Lines")
@export var speed_lines_enabled: bool = true
@export var speed_lines_follow_speed_scale: float = 0.7
## Maximum influence of the player's current trajectory on lingering speed lines.
@export_range(0.0, 1.0, 0.01) var speed_lines_trajectory_follow_influence: float = 0.75
## Response speed used when lingering speed lines curve toward the player's current trajectory.
@export var speed_lines_trajectory_follow_smooth: float = 48.0
@export var speed_lines_spawn_rate_min: float = 15.0
@export var speed_lines_spawn_rate_max: float = 99.0
@export var speed_lines_lifetime: float = 0.3
@export var speed_lines_lifetime_variance: float = 0.09
## Fractional random variation applied independently to each line's length.
@export_range(0.0, 1.0, 0.01) var speed_lines_length_variance: float = 0.35
@export var speed_lines_length: float = 0.9
@export var speed_lines_length_scale_max: float = 3.0
## Fractional random variation applied independently to each line's width.
@export_range(0.0, 1.0, 0.01) var speed_lines_width_variance: float = 0.45
@export var speed_lines_width: float = 0.013
## Fractional random variation applied to each line's radial spawn distance.
@export_range(0.0, 1.0, 0.01) var speed_lines_spawn_radius_variance: float = 0.25
@export var speed_lines_spawn_radius: float = 0.9
@export var speed_lines_spawn_radius_vertical: float = 1.2
## Fractional random variation applied to each line's offset along the travel direction.
@export_range(0.0, 1.0, 0.01) var speed_lines_spawn_back_offset_variance: float = 0.3
@export var speed_lines_spawn_back_offset: float = 0.4
@export var speed_lines_grow_time: float = 0.08
@export_range(0.0, 1.0) var speed_lines_grow_start_scale: float = 0.04
## Time used to fade a newly spawned line from transparent to its target opacity.
@export var speed_lines_fade_in_time: float = 0.035
## Fractional random variation applied independently to each line's opacity.
@export_range(0.0, 1.0, 0.01) var speed_lines_alpha_variance: float = 0.18
@export var speed_lines_alpha_min: float = 0.05
@export var speed_lines_alpha_max: float = 0.7
@export var speed_lines_color: Color = Color(1, 1, 1, 1)
## Fraction of the line surface faded at both longitudinal ends.
@export_range(0.01, 0.49, 0.01) var speed_lines_surface_end_fade: float = 0.24
## Curve exponent applied to the longitudinal surface fade.
@export_range(0.1, 4.0, 0.05) var speed_lines_surface_fade_power: float = 0.85

@export_subgroup("Effects/Barrier Foot Trails")
## Enables dual-foot emissive path ribbons while Barrier Blast is active.
@export var barrier_foot_trails_enabled: bool = false
## Optional Skeleton3D path used to resolve the foot trail bones. Empty searches under ModelRoot.
@export_node_path("Skeleton3D") var barrier_foot_trail_skeleton_path: NodePath = NodePath("")
## Optional left-foot marker node path relative to the player. This overrides the left bone source.
@export_node_path("Node3D") var barrier_foot_trail_left_marker_path: NodePath = NodePath("")
## Optional right-foot marker node path relative to the player. This overrides the right bone source.
@export_node_path("Node3D") var barrier_foot_trail_right_marker_path: NodePath = NodePath("")
## Skeleton bone used as the left-foot trail origin when no marker node is assigned.
@export var barrier_foot_trail_left_bone_name: StringName = &"FootAfterImage_Root_END.L"
## Skeleton bone used as the right-foot trail origin when no marker node is assigned.
@export var barrier_foot_trail_right_bone_name: StringName = &"FootAfterImage_Root_END.R"
## Trail surface width in world units.
@export var barrier_foot_trail_width: float = 0.11
## Time each sampled foot position remains in the ribbon.
@export var barrier_foot_trail_lifetime: float = 0.28
## Time between animated foot-position samples.
@export var barrier_foot_trail_sample_interval: float = 0.016
## Minimum world-space movement required before another foot sample is added.
@export var barrier_foot_trail_min_sample_distance: float = 0.015
## Maximum retained samples for each foot ribbon.
@export_range(2, 64, 1) var barrier_foot_trail_max_points: int = 32
## Fraction of player speed inherited by lingering trail samples.
@export_range(0.0, 1.5, 0.01) var barrier_foot_trail_follow_speed_scale: float = 0.84
## Maximum influence of the player's current trajectory on lingering trail samples.
@export_range(0.0, 1.0, 0.01) var barrier_foot_trail_trajectory_follow_influence: float = 0.78
## Response speed used when lingering trail samples curve toward the player's current trajectory.
@export var barrier_foot_trail_trajectory_follow_smooth: float = 18.0
## Player-local axis used to face the right-foot surface outward. The left foot uses the opposite axis.
@export var barrier_foot_trail_outward_axis: Vector3 = Vector3.RIGHT
## Player palette color used by the emissive trail.
@export_enum("Primary", "Secondary", "Trail") var barrier_foot_trail_color_source: int = 2
## Fallback emissive tint and maximum opacity. The selected player color replaces its RGB channels.
@export var barrier_foot_trail_color: Color = Color(1.0, 0.08, 0.025, 0.9)
## Emission multiplier applied to the trail surface.
@export_range(0.0, 16.0, 0.1) var barrier_foot_trail_emission_energy: float = 4.0
## Time used to fade the trail effect in when Barrier Blast activates.
@export var barrier_foot_trail_fade_in_time: float = 0.06
## Time used to fade the trail effect out when Barrier Blast ends.
@export var barrier_foot_trail_fade_out_time: float = 0.12
## Fade curve applied from the newest samples toward the oldest tail samples.
@export_range(0.1, 8.0, 0.05) var barrier_foot_trail_tail_fade_power: float = 1.6
## Fraction of the newest trail length softened near each foot.
@export_range(0.0, 0.5, 0.01) var barrier_foot_trail_head_fade_fraction: float = 0.08
## Fraction of each ribbon edge softened across its width.
@export_range(0.0, 0.5, 0.01) var barrier_foot_trail_edge_softness: float = 0.16

@export_subgroup("Effects/Speed Boom")
@export var sonic_boom_enabled: bool = true
@export var sonic_boom_duration: float = 2.585
@export var sonic_boom_progress_delay: float = 1.48
@export var sonic_boom_fade_in_speed: float = 6.0
@export var sonic_boom_fade_out_speed: float = 3.765
@export_range(0.0, 5.0) var sonic_boom_max_alpha: float = 1.6
@export var sonic_boom_color: Color = Color(0.28651586, 1.2117599, 4.681993, 0.549)
@export var sonic_boom_override_material_params: bool = false
@export var sonic_boom_shader: Shader
@export_subgroup("Effects/Jump Ball")
@export var jump_ball_speed_for_full_extrusion: float = 140.0 ## Speed where the jump ball reaches full extrusion.

# -----------------------------------------------------------
# INTERNAL STATE
# -----------------------------------------------------------

# Networking (peer-replicated puppets)
var _net_saved_collision: bool = false
var _net_initial_collision_layer: int = 0
var _net_initial_collision_mask: int = 0

var _net_has_state: bool = false
var _net_state_sequence: int = 0
var _net_target_transform: Transform3D = Transform3D.IDENTITY
var _net_target_velocity: Vector3 = Vector3.ZERO
var _net_target_attached: bool = false
var _net_target_state_flags: int = 0
var _net_target_main_state: int = 0
var _net_target_visual_up: Vector3 = Vector3.UP
var _net_target_model_basis: Basis = Basis.IDENTITY
var _net_target_move_direction: Vector3 = Vector3.ZERO
var _net_target_barrier_blast_gauge: float = 0.0
var _net_target_action_id: StringName = &""
var _net_animation_states: Dictionary = {}
var _net_animation_values: Array = []
var _net_presentation_state: PackedFloat32Array = PackedFloat32Array()
var _debug_online_puppet: Node = null

var _character_primary_color: Color = Color(0.18, 0.52, 1.0, 1.0)
var _character_secondary_color: Color = Color(1, 1, 1, 1)
var _character_trail_color: Color = Color(0.2, 0.8, 1.0, 1.0)
var character_tint_enabled: bool = true
var character_hue_fallback_color: Color = Color(0.18, 0.52, 1.0, 1.0)
var character_hue_overlay_strength: float = 1.0
var character_hue_saturation_threshold: float = 0.2
var character_hue_saturation_softness: float = 0.25
var character_hue_saturation_exponent: float = 1.0
var jump_ball_default_color: Color = Color(0.2, 0.8, 1.0, 0.72)
var _character_tint_shader = null
var _character_tint_transparent_shader = null
var _default_sonic_boom_color: Color = Color(0.28651586, 1.2117599, 4.681993, 0.549)
var _default_jump_dash_trail_tint: Color = Color(0.2, 0.8, 1.0, 1.0)
var _default_jump_ball_tint: Color = Color(0.2, 0.8, 1.0, 0.72)
var _has_default_character_effect_colors: bool = false

var _sonic_boom_fx_node: Node3D = null
var _sonic_boom_materials: Array = []
var _sonic_boom_timer: float = 0.0
var _sonic_boom_visible: float = 0.0
var _sonic_boom_was_full: bool = false
var _sonic_boom_dir: Vector3 = Vector3.FORWARD
var _sonic_boom_active: bool = false

# Score / rings
var rings: int = 0
var score: int = 0
var item_resources: Dictionary = {}

# Race state (for AnimationTree transitions / UI / scripting)
var race_in_countdown: bool = false
var race_active: bool = false
var race_finished: bool = false
var race_session_joined: bool = false
var race_debug_used: bool = false
var _race_debug_confirm_pending: bool = false
var _race_debug_confirm_timer: float = 0.0
var _race_debug_confirmed: bool = false

var _local_pause_enabled: bool = false
var _level_load_suspended: bool = false
var _level_load_saved_collision_layer: int = 0
var _level_load_saved_collision_mask: int = 0
var _level_load_saved_process_enabled: bool = true
var _level_load_saved_physics_process_enabled: bool = true
var _level_load_saved_input_enabled: bool = true
var _level_load_saved_unhandled_input_enabled: bool = true
var _level_load_saved_unhandled_key_input_enabled: bool = true
var _ui_input_blocked: bool = false
var _ui_input_legacy_blocked: bool = false
var _chat_input_blocked: bool = false
var _post_ui_unblock_action_suppress_timer: float = 0.0
## Locked during states that must not allow teleporters, death planes, or level transitions (e.g. drowned, death).
var _player_state_locked: bool = false

# Gameplay state
var _is_skidding: bool = false
var _prev_skidding: bool = false
var _skid_dust_timer: float = 0.0
var _skid_dust_emit_left: bool = true
var _drift_active: bool = false
var _drift_turn_deg_per_sec_current: float = 0.0
var _drift_turn_speed_last: float = 0.0
var _drift_turn_speed_memory_timer: float = 0.0
var _airborne_torque_yaw_turn_speed_last: float = 0.0
var _airborne_torque_yaw_turn_speed_memory_timer: float = 0.0
var _drift_prev_lateral_dir: Vector3 = Vector3.ZERO
var _drift_exit_active: bool = false
var _drift_exit_pending: bool = false
var _drift_exit_locked: bool = false
var _drift_exit_turn_deg_per_sec_current: float = 0.0
var _drift_exit_turn_deg_per_sec_start: float = 0.0
var _drift_exit_elapsed: float = 0.0
var _drift_exit_blend: float = 0.0
var _drift_turn_input_scale_current: float = 1.0
var _drift_back_input_current: float = 0.0
var _drift_same_input_current: float = 0.0
var _drift_turn_entry_timer: float = 0.0
var _drift_entry_turn_deg_per_sec_start: float = 0.0
var _drift_direction: int = 0
var _drift_direction_target: int = 0
var _drift_direction_value: float = 0.0
var _drift_direction_value_start: float = 0.0
var _drift_switch_elapsed: float = 0.0
var _drift_reward_turn_degrees_current: float = 0.0
var _drift_reward_distance_current: float = 0.0
var _drift_reward_progress: float = 0.0
var _drift_speed_bonus_current: float = 0.0
var _drift_entry_speed_current: float = 0.0
var _drift_visual_blend: float = 0.0
var _drift_visual_steer: float = 0.0

var _just_jumped: bool = false              # true only on the frame a jump is triggered

var _jump_dash_recent_timer: float = 0.0    # counts down after a jump dash;
											# > 0 means "recent_jump_dash == true"
var _landing_timer: float = 0.0             # short timer after touching ground,
											# lets us treat a landing as “fresh” for a bit
var _last_landing_impact_speed: float = 0.0 # how hard we hit the ground (downward speed
											# at the moment we landed)
var _last_ground_hit_speed: float = 0.0
var _last_ground_hit_strength: float = 0.0
var _loop_forward_dir: Vector3 = Vector3.ZERO

var _hard_landing_speed_threshold: float = 0


# Jump state
var _is_jumping: bool = false
var _jump_variable: bool = false
var _jump_time: float = 0.0
var _jump_hang_allowed: bool = false
var _jump_requested: bool = false       # set by JumpAbility via queue_jump()
var _coyote_jump_requested: bool = false

var _is_falling: bool = false
var _jumped_from_ground: bool = false
var _falling_without_jump: bool = false
# Fall-off air decel ramp (only when leaving ground without jumping).
var _fall_air_decel_delay_timer: float = 0.0
var _fall_air_decel_scale_current: float = 1.0
# Air top speed ramp after detaching from a surface.
var _air_top_speed_detach_timer: float = 0.0
var _air_top_speed_detach_active: bool = false
var _air_top_speed_current: float = 0.0
var _last_grounded_top_speed: float = 0.0
var _speed_shoes_timer: float = 0.0
var _speed_shoes_music_tail_timer: float = 0.0
var _speed_shoes_music_controller: MusicController = null
var _speed_shoes_music_source_id: StringName = &""
var _speed_shoes_prepared_music_stream: AudioStream = null
var _invincibility_timer: float = 0.0
var _invincibility_music_timer: float = 0.0
var _invincibility_music_controller: MusicController = null
var _invincibility_music_source_id: StringName = &""
var _invincibility_prepared_music_stream: AudioStream = null
var _invincibility_attack_timer: float = 0.0
var _directional_influence_lock_strength: float = 0.0
var _directional_influence_lock_speed_t: float = 0.0
var _directional_influence_lock_accel_strength: float = 0.0
var _directional_influence_lock_turn_strength: float = 0.0
var _directional_influence_lock_air_turn_penalty_strength: float = 0.0
var _directional_influence_lock_accel_delay_timer: float = 0.0
var _directional_influence_lock_turn_delay_timer: float = 0.0
var _directional_influence_lock_air_turn_penalty_delay_timer: float = 0.0
var _directional_influence_lock_accel_multiplier: float = 1.0
var _directional_influence_lock_turn_multiplier: float = 1.0
var _directional_influence_lock_air_turn_penalty_multiplier: float = 1.0

# Jump dash state
var _jump_dash_requested: bool = false
var _jump_dash_used_this_air: bool = false
var _jump_dashing: bool = false
var _tornado_kick_used_this_air: bool = false

# Homing attack
var _homing_active: bool = false
var _homing_target = null
var _homing_saved_velocity: Vector3 = Vector3.ZERO
var _homing_saved_lateral: Vector3 = Vector3.ZERO
var _homing_saved_speed_mag: float = 0.0
var _homing_retain_timer: float = 0.0
var _homing_elapsed: float = 0.0
var _homing_post_attack_timer: float = 0.0
var _homing_target_position: Vector3 = Vector3.ZERO
var _homing_target_position_valid: bool = false
var _homing_target_candidate_positions: Dictionary = {}
# Homing reticle caching to reduce per-frame target searches
var _homing_reticle_cached_target: Node3D = null
var _homing_reticle_cached_time_ms: int = 0
var _homing_target_scan_initialized: bool = false
var _homing_target_request_buffer_active: bool = false
var _homing_target_request_scan_time_ms: int = 0
var _homing_reticle_cached_mode: int = -1
const HOMING_RETICLE_CACHE_MS: int = 50
var _attack_magnetism_target: Node3D = null
var _attack_magnetism_target_position: Vector3 = Vector3.ZERO
var _attack_magnetism_strength_current: float = 0.0
var _attack_magnetism_scan_timer: float = 0.0
var _attack_magnetism_scan_result: Dictionary = {}
var _attack_magnetism_bounce_descent_compensation: float = 0.0
var _attack_magnetism_bounce_compensation_timer: float = 0.0
var _property_name_cache: Dictionary = {}

# Raycast cache for lightspeed ring obstruction checks
var _lightspeed_raycast_cache: Dictionary = {}  # key: ring.get_rid(), value: {time_ms: int, obstructed: bool}
const LIGHTSPEED_RAYCAST_CACHE_MS: int = 50

# Collision disable while airborne (experimental)
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0
var _collision_disabled_airborne: bool = false

# Debug toggles
const DEBUG_SKIP_AIR_RAYS: bool = false
const DEBUG_SKIP_RAIL_SHAPE: bool = false
const DEBUG_SHOW_FPS: bool = true

var _lightspeed_dash_active: bool = false
var _lightspeed_dash_target: Node3D = null
var _lightspeed_dash_prev_ring: Node3D = null
var _lightspeed_dash_speed: float = 0.0
var _lightspeed_dash_release_velocity: Vector3 = Vector3.ZERO
var _lightspeed_dash_last_dir: Vector3 = Vector3.ZERO
var _lightspeed_dash_timer: float = 0.0
var _lightspeed_dash_start_bonus_cooldown_timer: float = 0.0

var _enemy_bounce_cooldown_timer: float = 0.0
var _enemy_hurt_boundary_exceptions: Dictionary = {}
var _enemy_hurt_boundary_launch_capture_armed: bool = false
var _enemy_hurt_boundary_launch_restore_pending: bool = false
var _enemy_hurt_boundary_launch_velocity: Vector3 = Vector3.ZERO
var _enemy_attack_chain_active: bool = false
var _damage_hit_invuln_timer: float = 0.0
var _combat_homing_lockout_timer: float = 0.0
var _hurt_active: bool = false
var _hurt_state_timer: float = 0.0
var _hurt_flash_accum: float = 0.0
var _hurt_flash_visible: bool = true
var _hurt_flash_renderers: Array[GeometryInstance3D] = []

# Automation spline influence (set by AutomationSpline objects)
enum AutomationSplineMode {
	GUIDED,
	TWO_POINT_FIVE_D,
}

enum AutomationPlaneInputMode {
	PATH_HORIZONTAL,
	PATH_VERTICAL,
	CAMERA_RELATIVE,
}

var _automation_active: bool = false
var _automation_tangent_dir: Vector3 = Vector3.ZERO
var _automation_toward_dir: Vector3 = Vector3.ZERO
var _automation_toward_strength: float = 0.0
var _automation_max_turn_deg_per_sec: float = 0.0
var _automation_lock_movement: bool = false
var _automation_lock_actions: bool = false
var _automation_lock_drift: bool = false
var _automation_continuous_force: bool = true
var _automation_align_rotation: bool = true
var _automation_grounded_only: bool = true
var _automation_force_surface_adhesion: bool = false # Preserves surface contact while automation is influencing.
var _automation_tangent_snap_strength: float = 0.0
var _automation_along_assist_enabled: bool = true
var _automation_along_target_speed: float = 0.0
var _automation_along_accel: float = 0.0
var _automation_along_speed_limits_player: bool = true
var _automation_bidirectional_assist: bool = false
var _automation_timer: float = 0.0
var _automation_expired_this_frame: bool = false
var _automation_priority_current: int = -9999
var _automation_priority_frame: int = -1
var _automation_ignore_water_physics: bool = false
var _automation_max_speed_override_enabled: bool = false
var _automation_max_speed_override: float = 0.0
var _automation_mode: int = AutomationSplineMode.GUIDED
var _automation_constraint_source: Node = null
var _automation_influence: float = 0.0
var _automation_path_point: Vector3 = Vector3.ZERO
var _automation_plane_normal: Vector3 = Vector3.ZERO
var _automation_plane_up: Vector3 = Vector3.UP
var _automation_input_mode: int = AutomationPlaneInputMode.PATH_HORIZONTAL
var _automation_reverse_input: bool = false
var _automation_input_deadzone: float = 0.05
var _automation_strict_position_lock: bool = true
var _automation_post_slide_constraint_pass_enabled: bool = false
var _automation_position_lock_strength: float = 12.0
var _automation_max_position_correction_speed: float = 80.0
var _automation_position_lock_deadzone: float = 0.005
var _automation_strict_velocity_lock: bool = true
var _automation_disable_turning_slowdown: bool = false
var _automation_velocity_lock_strength: float = 18.0
var _automation_sideways_speed_preservation: float = 0.0
var _automation_constrain_special_moves: bool = true

# Bounce / Stomp state
enum BounceState {
	NONE,
	BOUNCE,
	REBOUND,
	STOMP,
}

var _bounce_state: int = BounceState.NONE
var _bounce_rebound_attack_active: bool = false
var _stomp_landing_flag: bool = false

# Spindash state
var _spindash_charging: bool = false
var _spindash_charge_time: float = 0.0
var _spindash_charge_full_played: bool = false
var _spindash_release_requested: bool = false
var _spindash_release_with_jump: bool = false
var _spindash_release_speed: float = 0.0
var _spindash_pending_release: bool = false
var _spindash_pending_release_speed: float = 0.0
var _spindash_turn_free_timer: float = 0.0
var _spindash_entry_speed: float = 0.0
var _spindash_latched_direction: Vector3 = Vector3.ZERO
var _spindash_ground_hold_timer: float = 0.0
var _spindash_roll_held: bool = false
var _spindash_ground_action1_press_valid: bool = false
var _spindash_roll_route_lockout_timer: float = 0.0


# Input state
var _move_input: Vector2 = Vector2.ZERO
var _walk_input_held: bool = false
var _move_direction: Vector3 = Vector3.ZERO
var _locomotion_intent_direction: Vector3 = Vector3.ZERO
var _locomotion_intent_last_physics_frame: int = -1
var _movement_release_decel_reserve: float = 0.0
var _movement_release_decel_base_delay_remaining: float = 0.0
var _movement_release_decel_ramp_elapsed: float = 0.0
var _movement_release_decel_scale_current: float = 1.0
var _movement_release_decel_input_active_last: bool = false
var _movement_release_decel_ramp_active: bool = false
var _wall_input_contact_normals: Array[Vector3] = []
var _wall_input_linger_normals: Array[Vector3] = []
var _wall_input_linger_timer: float = 0.0
var _wall_input_projection_active: bool = false
var _wall_input_push_active: bool = false
var _wall_input_push_normal: Vector3 = Vector3.ZERO
var _wall_input_push_angle_deg: float = 0.0
var _wall_input_debug_raw_dir: Vector3 = Vector3.ZERO
var _wall_input_debug_projected_dir: Vector3 = Vector3.ZERO
var _wall_input_debug_normal: Vector3 = Vector3.ZERO

# ===========================================================
# INPUT SPACE HELPERS
# ===========================================================
var _input_up_last: Vector3 = Vector3.UP  # smoothed up for input/control space

var _stick_length: float = 0.0    # magnitude of analog input
var _stick_turn: float = 0.0      # signed angle between look & move (radians)

# Control-space basis for mapping 2D input to 3D movement.
var _control_forward: Vector3 = -Vector3.FORWARD
var _control_right: Vector3 = Vector3.RIGHT

# Loop control
var _loop_control_active: bool = false

# Last airborne velocity for landing conversion.
var _last_air_velocity: Vector3 = Vector3.ZERO

# Velocity submitted to the most recent collision sweep.
var _pre_slide_velocity: Vector3 = Vector3.ZERO

# Moving-platform carry support.
var _platform_on_floor_last: bool = false
var _platform_velocity_last: Vector3 = Vector3.ZERO
var _platform_collider_last: Node3D
var _platform_prev_origin: Vector3 = Vector3.ZERO
var _dbg_tp_trace: int = 0
## Set true in Inspector to print per-frame velocity at every step when on a RigidBody3D.
@export var _dbg_dynbody: bool = false

# Player-relative speeds (relative to current physics-up). These are updated every frame
# and are suitable for AnimationTree blend wiring.
var _horizontal_speed: float
var _vertical_speed: float

# Model-root-relative momentum (relative to model_root orientation). Updated every frame.
# Useful for state machines/blend spaces when the character is rotated sideways (springs/loops),
# so "up" can still mean model-up rather than gravity-up.
var _model_horizontal_momentum: float
var _model_vertical_momentum: float

# Attachment state
var attached: bool = false
var _prev_attached: bool = false

var _loop_sticky: bool = false

var surface_normal: Vector3 = Vector3.UP
var surface_point: Vector3 = Vector3.ZERO
var _prev_surface_normal: Vector3 = Vector3.UP
var _slope_passive_sliding: bool = false
var _slope_reversal_debt: float = 0.0
var _slope_reversal_uphill_peak_speed: float = 0.0
var _slope_reversal_previous_uphill_speed: float = 0.0
var _slope_reversal_air_time: float = 0.0
var _last_detach_normal: Vector3

# Detach classification (used for floor -> wall exception)
var _detached_from_floor_like: bool = true
var _last_detach_angle_deg: float = 0.0
var _last_attach_normal: Vector3 = Vector3.UP
var _last_attach_angle_deg: float = 0.0
var _stable_attach_normal: Vector3 = Vector3.UP
var _stable_attach_angle_deg: float = 0.0
var _stable_attach_normal_valid: bool = false

var _physics_up_last: Vector3 = Vector3.UP

# Per-player gravity resolution.
var _resolved_gravity_up: Vector3 = Vector3.UP
var _resolved_gravity_strength: float = 65.0
var _gravity_modifiers: Dictionary = {}
var _planetary_gravity_sources: Dictionary = {}
var _gravity_modifier_sequence: int = 0

# Visual orientation
var visual_up: Vector3 = Vector3.UP
var _model_forward: Vector3 = -Vector3.FORWARD

# Airborne torque (visual-only, world-space)
var _air_torque_prev_surface_normal: Vector3 = Vector3.UP
var _air_torque_ground_angular_velocity: Vector3 = Vector3.ZERO
var _air_torque_angular_velocity: Vector3 = Vector3.ZERO
var _air_torque_yaw_forward: Vector3 = -Vector3.FORWARD
var _air_torque_visual_forward: Vector3 = -Vector3.FORWARD  # Cached visual forward, rotated with airborne torque.
var _air_torque_rotation_accum: Vector3 = Vector3.ZERO  # Local-space rotation accumulation (radians) for trick rewards.
var _air_torque_airborne_time: float = 0.0
var _air_torque_segment_allowed: bool = true
var _air_torque_prev_attached: bool = false
var _air_torque_sample_total_time: float = 0.0
var _air_torque_avg_angular_velocity: Vector3 = Vector3.ZERO
var _air_torque_samples: Array = []
var _air_torque_sample_durations: Array = []
var _dbg_air_torque_surface_omega: Vector3 = Vector3.ZERO
var _dbg_air_torque_yaw_omega: Vector3 = Vector3.ZERO
var _dbg_air_torque_combined_omega: Vector3 = Vector3.ZERO
var _dbg_air_torque_avg_omega: Vector3 = Vector3.ZERO
var _dbg_air_torque_seed_omega: Vector3 = Vector3.ZERO
var _dbg_air_torque_axis: Vector3 = Vector3.ZERO
var _dbg_air_torque_move_dir: Vector3 = Vector3.ZERO
var _dbg_air_torque_normal_angle_deg: float = 0.0
var _manual_airborne_torque_active: bool = false
var _manual_airborne_torque_suppress_decay: bool = false
var _manual_airborne_torque_fast_decay: bool = false
var _left_stick_trick_momentum_active: bool = false
var _left_stick_trick_entry_horizontal_speed: float = 0.0
var _left_stick_trick_entry_horizontal_direction: Vector3 = Vector3.ZERO
var _left_stick_trick_last_input_direction: Vector3 = Vector3.ZERO
var _left_stick_trick_last_input_strength: float = 0.0
var _external_airborne_torque_active: bool = false
var _external_airborne_trick_command: StringName = &""
var _manual_airborne_mouse_delta: Vector2 = Vector2.ZERO
var _spring_trajectory_torque_active: bool = false
var _spring_trajectory_torque_align_speed_deg: float = 720.0
var _spring_trajectory_gravity_yaw_enabled: bool = true
var _spring_trajectory_gravity_yaw_strength: float = 1.0
var _spring_trajectory_gravity_yaw_safe_angle_deg: float = 3.0
var _spring_trajectory_gravity_yaw_full_angle_deg: float = 90.0
var _spring_trajectory_torque_min_horizontal_speed: float = 2.0
var _spring_trajectory_landing_forward_pitch_active: bool = false
var _air_torque_trajectory_up: Vector3 = Vector3.UP

# Airborne landing alignment (visual-only)
var _air_landing_align_active: bool = false
var _air_landing_align_normal: Vector3 = Vector3.UP
var _air_landing_align_distance: float = 0.0
var _air_landing_align_time_to_impact: float = 0.0
var _air_landing_align_ramp: float = 0.0
var _air_landing_align_speed_scale: float = 1.0
var _air_landing_align_pitch_direction: float = 0.0
var _air_landing_align_pitch_preference_resolved: bool = false
var _air_landing_align_directional_pitch_complete: bool = false
var _air_landing_align_miss_grace_timer: float = 0.0

# Timers
var _attachment_immunity: float = 0.0
var _low_speed_detach_reattach_block_timer: float = 0.0
var _low_speed_detach_block_angle_deg: float = 0.0
var _pending_low_speed_detach_block: bool = false
var _pending_low_speed_detach_block_angle_deg: float = 0.0
var _airborne_time: float = 0.0
var _trick_retrigger_timer: float = 0.0
var _air_trick_animation_gesture_latched: bool = false
var _air_trick_animation_last_command: StringName = &""
var _manual_airborne_trick_input_active: bool = false
var _manual_airborne_trick_input_command: StringName = &""
var _coyote_jump_available: bool = false
var _coyote_jump_timer: float = 0.0

# Water physics state
var _in_water_volume: bool = false
var _water_volume_count: int = 0
var _running_on_water_surface: bool = false
var _water_surface_normal: Vector3 = Vector3.UP
var _water_reattach_cooldown_timer: float = 0.0
var _water_last_collider: Node3D = null

# Head water detector (for neck-deep submersion)
var _head_water_detector_node: Area3D = null
var _head_in_water_volume: bool = false
var _head_water_volume_count: int = 0

# Submersion state (true only when fully submerged - head under water)
var _fully_submerged: bool = false

# Water footstep timer (counts up in water, down when dry)
var _water_footstep_timer: float = 0.0
var _was_airborne_before_water_entry: bool = false
var _was_in_water_volume: bool = false
var _last_splash_index: int = -1
var _water_last_entry_area: Area3D = null

# Ground follow ray debug
var _follow_hit: bool = false
var _follow_normal: Vector3 = Vector3.UP
var _follow_point: Vector3 = Vector3.ZERO
var _follow_ray_origin: Vector3 = Vector3.ZERO
var _follow_ray_target: Vector3 = Vector3.ZERO
var _follow_collider_last: Node3D
var _follow_collider_prev: Node3D
var _follow_collider_shape_last: int = -1
var _follow_collider_shape_prev: int = -1
var _active_surface_behavior_areas: Dictionary = {}

# Debug HUD
var _debug_hud: Control = null
var _debug_label: Label
var _debug_visible: bool = false
var _normal_delta_angle_deg: float = 0.0
var _debug_mode: bool = false
var _debug_saved_collision_layer: int = 0
var _debug_saved_collision_mask: int = 0
var _movement_correction_debug_rays: Array[Dictionary] = []
var _movement_correction_debug_push: Vector3 = Vector3.ZERO
var _movement_correction_debug_origin: Vector3 = Vector3.ZERO
var _debug_saved_anim_tree_active: bool = true
var _pending_anim_command: StringName = &""
var _pending_anim_crossfade: float = -1.0
var _carry_hold_blend_value: float = 0.0
var _carry_pickup_pending_overlay: bool = false
var _carry_pickup_overlay_started: bool = false
var _carry_put_down_pending_release: bool = false
var _carry_put_down_anim_started: bool = false
var _carry_put_down_release_wait_frames: int = 0
var _carry_put_down_release_transform: Transform3D = Transform3D.IDENTITY
var _carry_put_down_release_velocity: Vector3 = Vector3.ZERO
var _carry_throw_pending_release: bool = false
var _carry_throw_anim_started: bool = false
var _carry_throw_release_wait_frames: int = 0
var _carry_throw_release_transform: Transform3D = Transform3D.IDENTITY
var _carry_throw_release_velocity: Vector3 = Vector3.ZERO
var _skydive_anim_phase: int = 0
var _skydive_anim_exit_timer: float = 0.0
var _missing_anim_command_logged: Dictionary = {}
var _debug_anim_player: AnimationPlayer
var _debug_anim_names: PackedStringArray = PackedStringArray()
var _debug_anim_index: int = 0
var _debug_surface_probe_timer: float = 0.0

# Rolling ability state (used by movement and AnimationTree state machine expressions).
var rolling: bool = false

var _radial_attach_this_frame: bool = false
var _debug_radial_angle: float = 0.0
var _debug_radial_ns: float = 0.0
var _debug_radial_ts: float = 0.0

# ===========================================================
# DEBUG
# ===========================================================
var _dbg_surface_angle_deg: float = 0.0
var _dbg_surface_is_floor_like: bool = false

var _dbg_last_detach_world_angle: float = 0.0
var _dbg_last_detach_step_angle: float = 0.0
var _dbg_last_detach_used_filtered: bool = false
var _dbg_last_detach_from_floor_like: bool = false
var _dbg_last_detach_coyote_eligible: bool = false

var _dbg_radial_angle: float = 0.0
var _dbg_radial_into_speed: float = 0.0
var _dbg_radial_tangent_speed: float = 0.0
var _dbg_radial_result: String = "none"

var _dbg_surface_preview_timer: float = 0.0
var _dbg_surface_preview_points: Array[Vector3] = []
var _dbg_surface_preview_normals: Array[Vector3] = []
var _dbg_surface_preview_centers: Array[Vector3] = []
var _dbg_surface_preview_accepted: bool = false
var _dbg_surface_preview_radius: float = 0.0
var _dbg_surface_preview_lookahead: float = 0.0
var _dbg_surface_preview_coverage: float = 0.0
var _dbg_surface_preview_total_turn_deg: float = 0.0
var _dbg_surface_preview_reverse_turn_deg: float = 0.0
var _dbg_surface_preview_max_step_deg: float = 0.0
var _dbg_surface_preview_min_radius: float = 0.0
var _dbg_surface_preview_curvature: float = 0.0
var _dbg_surface_preview_reaction_accel: float = 0.0
var _dbg_surface_preview_tangent: Vector3 = Vector3.ZERO
var _dbg_surface_preview_collider_transitions: int = 0
var _dbg_surface_seam_timer: float = 0.0
var _dbg_surface_seam_from: Vector3 = Vector3.ZERO
var _dbg_surface_seam_to: Vector3 = Vector3.ZERO
var _dbg_surface_seam_normal: Vector3 = Vector3.ZERO

var _surface_preview_world_radius: float = 0.0
var _surface_support_timer: float = 0.0
var _surface_support_curvature: float = 0.0
var _surface_support_reaction_accel: float = 0.0

var _pending_landing_velocity: Vector3 = Vector3.ZERO
var _pending_landing_has_velocity: bool = false
var _pending_landing_airborne_time: float = 0.0
var _landing_animation_moving: bool = false
var _landing_animation_pending: bool = false

# timers so the HUD text doesn't flash
var _dbg_radial_hit_timer: float = 0.0
var _dbg_detach_timer: float = 0.0

var _dbg_last_detach_normal: Vector3 = Vector3.ZERO
var _dbg_current_adhesion_speed: float = 0.0
var _dbg_required_adhesion_speed: float = 0.0

# ===========================================================
# OBJECTS
# ===========================================================

# --- Spring lock / alignment state -------------------------------------------
var _spring_movement_lock_timer: float = 0.0
var _spring_action_lock_timer: float = 0.0
var _spring_align_dir: Vector3 = Vector3.ZERO   # launch direction
var _spring_lock_sideways: bool = false         # if true, freeze sideways motion
var _spring_sideways_gravity_scale: float = 0.0 # 0 = no sideways from gravity, 1 = normal
var _spring_cancel_on_ground: bool = true       # stop align when we land
var _spring_align_timer: float = 0.0
var _spring_align_up: Vector3 = Vector3.ZERO
var _spring_align_forward: Vector3 = Vector3.ZERO

# --- Auto-unstuck detection --------------------------------------------------
var _unstuck_prev_position: Vector3 = Vector3.ZERO
var _unstuck_detection_timer: float = 0.0
var _spring_clear_move_on_ground: bool = false
var _spring_clear_action_on_ground: bool = false
var _spring_detached: bool = false
var _spring_align_model : bool = false
var _spring_model_snap_timer: float = 0.0

# --- Dash Panels -------------------------------------------------------------
var _dash_speed_lock_timer: float = 0.0
var _dash_speed_lock_speed: float = 0.0
var _timed_max_speed_override_timer: float = 0.0
var _timed_max_speed_override: float = 0.0
var _functional_max_speed: float = 0.0

# Ramp impulse holds (for Jump Panel ramps). When > 0, continually override components.
var _ramp_hold_forward_timer: float = 0.0
var _ramp_hold_up_timer: float = 0.0
var _ramp_hold_forward_speed: float = 0.0
var _ramp_hold_up_speed: float = 0.0
var _ramp_hold_forward_dir: Vector3 = Vector3.ZERO
var _ramp_hold_up_dir: Vector3 = Vector3.ZERO

# Respawn
var _initial_transform: Transform3D

# Ability system

# ===========================================================
# BARRIER BLAST
# ===========================================================
var _barrier_blast_gauge: float = 0.0
var _barrier_blast_active: bool = false
var _barrier_blast_was_full: bool = false
var _barrier_blast_deplete_grace_timer: float = 0.0
var _barrier_blast_full_land_exit_grace_timer: float = 0.0

# ===========================================================
# NETWORKING
# ===========================================================

var _actions: Array = []
var _active_action = null
var _current_action_id: StringName = &""
var _carried_object: Node3D = null
var _fall_action: FallAction = null
var _jump_action: JumpAbility = null
var _jump_dash_action: JumpDashAbility = null
var _homing_action: HomingAbility = null
var _insta_shield_action: InstaShieldAction = null
var _lightspeed_dash_action: LightspeedDashAbility = null
var _bounce_action: BounceAction = null
var _stomp_action: StompAction = null
var _homing_targeting_ability_count: int = 0
var _roll_action: RollAction = null
var _spindash_action: SpindashAction = null
var _drift_action: DriftAction = null
var _spring_action: SpringAction = null
var _hurt_action: HurtAction = null
var _rail_grind_action: RailGrindAction = null
var _rail_node: Node = null
var _grounded_action: GroundedAction = null
var _drowned_action: DrownedActionType = null
var can_grind_rails: bool = false

# Trick system
var _trick_system: TrickSystem = null
var _trick_detector: TrickDetector = null
var _trick_ui: TrickUI = null

@export_group("Tricks")
@export_subgroup("Controller Integration")

## Amount of Barrier Blast gauge added per full 360-degree rotation on any axis.
@export var trick_rotation_gauge_bonus: float = 0.004

## Cooldown (sec) before another airborne trick can trigger.
@export var trick_retrigger_delay: float = 0.25

## Crossfade time (sec) when triggering trick animations.
@export var trick_anim_crossfade: float = 0.25

## Distance traveled on a rail before another grind entry is registered.
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m") var rail_trick_distance_units: float = 12.0
## Rail speed required for fast crouch trick names.
@export_range(0.0, 500.0, 1.0, "or_greater") var rail_crouch_fast_trick_speed_threshold: float = 125.0
## Combo time added for each rail grind entry.
@export_range(0.0, 5.0, 0.05, "suffix:s") var rail_combo_timer_add_seconds: float = 1.25
## Combo score required to reach the maximum Barrier Blast gain multiplier.
@export var combo_barrier_blast_score_target: float = 18500.0
## Maximum multiplier applied to Barrier Blast gauge gains during a combo.
@export_range(1.0, 5.0, 0.05, "or_greater") var combo_barrier_blast_max_gain_multiplier: float = 1.5
## Combo score required to reach the maximum movement bonuses.
@export var combo_movement_bonus_score_target: float = 18500.0
## Maximum multiplier applied to positive acceleration curve samples during a combo.
@export_range(1.0, 5.0, 0.05, "or_greater") var combo_acceleration_max_multiplier: float = 1.25
## Maximum multiplier applied to landing-roll momentum recovery during a combo.
@export_range(1.0, 5.0, 0.05, "or_greater") var combo_landing_roll_max_effectiveness_multiplier: float = 1.5
@export_storage var trick_name_backflip: String = "Backflip"
@export_storage var trick_name_frontflip: String = "Frontflip"
@export_storage var trick_name_left_spin: String = "Method"
@export_storage var trick_name_right_spin: String = "Indy"
@export_storage var trick_name_frontflip_left_spin: String = "Corkscrew"
@export_storage var trick_name_backflip_left_spin: String = "Misty Flip"
@export_storage var trick_name_backflip_right_spin: String = "Barani"
@export_storage var trick_name_frontflip_right_spin: String = "McTwist"
@export_storage var trick_name_rail_forward: String = "FS 50/50"
@export_storage var trick_name_rail_backward: String = "BS 50/50"
@export_storage var trick_name_rail_forward_crouch: String = "FS Low Raven"
@export_storage var trick_name_rail_backward_crouch: String = "BS Low Raven"
@export_storage var trick_sound: AudioStream = null
@export_storage var perfect_landing_sound: AudioStream = null

var _anim_turn_param: float = 0.0    # -1..1, left/right turn for anims
var _anim_speed_param: float = 0.0   # 0..1, normalized locomotion speed
var _was_spring_last_frame: bool = false
var _pending_walk_stop: bool = false  # Used by AnimationTree advance expressions.
var _last_walk_foot_left: bool = true # Used by AnimationTree advance expressions.


# ===========================================================
# SPLINE SPRING STATE
# ===========================================================
var _spline_active: bool = false
var _spline_path: Path3D = null
var _spline_distance: float = 0.0
var _spline_speed: float = 0.0
var _spline_total_length: float = 0.0
var _spline_align_model: bool = true
var _spline_detach_from_ground: bool = true
var _spline_allow_input_cancel: bool = false
var _spline_world_offset: Vector3 = Vector3.ZERO

# ===========================================================
# VAULT BAR STATE
# ===========================================================
var _vault_bar_active: bool = false
var _vault_bar_source: Node = null
var _vault_bar_animation_player: AnimationPlayer = null
var _vault_bar_animation_tree_was_active: bool = true
var _vault_bar_animation_override_active: bool = false

# ===========================================================
# RAIL GRIND STATE
# ===========================================================
var _rail_active: bool = false
var _rail_path: Path3D = null
var _rail_distance: float = 0.0
var _rail_total_length: float = 0.0
var _rail_speed: float = 0.0
var _rail_align_model: bool = true
var _rail_allow_jump_exit: bool = true
var _rail_allow_reverse: bool = true
var _rail_min_speed: float = 0.0
var _rail_locked_speed: bool = false
var _rail_lock_speed_value: float = 0.0
var _rail_gravity_scale: float = 1.0
var _rail_attach_height: float = 0.9
var _rail_last_tangent: Vector3 = Vector3.FORWARD
var _rail_last_motion_dir: Vector3 = Vector3.FORWARD
var _rail_align_to_path_tilt: bool = true
var _rail_input_reverse_enabled: bool = false
var _rail_model_basis: Basis = Basis.IDENTITY
var _rail_model_basis_valid: bool = false
var _rail_reverse_speed_threshold: float = 0.0
var _rail_reverse_boost_speed: float = 0.0
var _rail_travel_sign: float = 1.0
var _rail_end_detach_distance: float = 0.0
var _rail_anim_dir_smoothed: float = 0.0
var _rail_anim_speed_smoothed: float = 0.0
var _rail_crouching: bool = false
var _rail_trick_distance_accum: float = 0.0
var _rail_switch_active: bool = false
var _prev_rail_active: bool = false
var _prev_rail_switch_active: bool = false
var _prev_spline_active: bool = false
var _rail_switch_timer: float = 0.0
var _rail_switch_target: Node3D = null
var _rail_switch_target_path: Path3D = null
var _rail_switch_target_offset: float = 0.0
var _rail_switch_target_point: Vector3 = Vector3.ZERO
var _rail_switch_target_tangent: Vector3 = Vector3.ZERO
var _rail_switch_candidate: Node3D = null
var _rail_switch_candidate_point: Vector3 = Vector3.ZERO
var _rail_switch_candidate_tangent: Vector3 = Vector3.ZERO
var _rail_switch_candidate_side: float = 0.0
var _rail_switch_animation_side: float = 0.0
var _rail_switch_animation_started: bool = false
var _rail_switch_inherited_speed: float = 0.0
var _rail_switch_inherited_dir: Vector3 = Vector3.FORWARD

# ===========================================================
# HIGH-LEVEL PLAYER STATE
# ===========================================================

enum MainState {
	GROUNDED,
	AIRBORNE,
	SPRING,
	SPLINE,
	RAIL,
}

var main_state: int = MainState.AIRBORNE
var main_state_time: float = 0.0  # time spent in current main state

# Bit flags for sub-states / tags.
const STATE_GROUNDED: int = 1 << 0
const STATE_MOVING: int = 1 << 1
const STATE_SKIDDING: int = 1 << 2
const STATE_JUMPING: int = 1 << 3
const STATE_FALLING: int = 1 << 4
const STATE_LOOPING: int = 1 << 5
const STATE_JUMP_DASH: int = 1 << 6
const STATE_SPRING: int = 1 << 7
const STATE_SPLINE: int = 1 << 8
const STATE_LANDING_HARD: int = 1 << 9
const STATE_RAIL: int = 1 << 10
const STATE_BARRIER_BLAST: int = 1 << 11
const STATE_ROLL: int = 1 << 12
const STATE_SPINDASH: int = 1 << 13
const STATE_RAIL_FORWARD: int = 1 << 14
const STATE_RAIL_BACKWARD: int = 1 << 15
const STATE_SPINDASHRAIL: int = 1 << 16
const STATE_DRIFT: int = 1 << 17
const STATE_LIGHTSPEED_DASH: int = 1 << 18
const STATE_SKYDIVE: int = 1 << 19
const STATE_JUMP_FALL_BLEND: int = 1 << 20
const ENEMY_BOUNCE_COOLDOWN_SEC: float = 0.12
const SKYDIVE_ANIM_NONE: int = 0
const SKYDIVE_ANIM_DIVE: int = 1
const SKYDIVE_ANIM_GLIDE: int = 2
const SKYDIVE_ANIM_CANCEL: int = 3
const SKYDIVE_ANIM_EXIT: int = 4

enum AttackSource {
	JUMP = 1 << 0,
	ROLL = 1 << 1,
	SPINDASH = 1 << 2,
	JUMP_DASH = 1 << 3,
	BOUNCE = 1 << 4,
	HOMING = 1 << 5,
	LIGHTSPEED = 1 << 6,
	MANUAL = 1 << 7,
	ENEMY_CHAIN = 1 << 8,
	SPIN_KICK = 1 << 9,
	AIR_UNCURL = 1 << 10,
}

enum CombatClass {
	NEUTRAL = 0,
	ATTACK  = 1,
}

enum CombatOutcome {
	WIN  =  1,
	DRAW =  0,
	LOSE = -1,
}

var state_flags: int = 0  # current frame tags
var _attack_sources: int = 0
var _is_dead: bool = false
var _active_death_type: StringName = &""

## Rotation speed used when aligning the visual model with its target up direction.
@export var visual_up_lerp_speed_deg: float = 720.0

var _detach_forward_hint: Vector3 = Vector3.FORWARD

# Usage examples:

# if player.has_state(PlayerController.STATE_SKIDDING):
	# do skid-specific VFX

# if player.main_state == PlayerController.MainState.SPRING:
	# camera rail behavior, etc.

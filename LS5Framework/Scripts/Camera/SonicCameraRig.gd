extends Node3D

## Player tracked by the camera rig.
@export var target: Node3D

## Node carrying orbit yaw and the camera up frame.
@export var yaw_node: Node3D
## Node carrying orbit pitch beneath the yaw rig.
@export var pitch_node: Node3D
## Camera receiving the final evaluated pose and lens.
@export var camera: Camera3D

@export_group("Update Timing")
## Updates camera input and presentation at the rendered frame rate while collision queries remain on physics ticks.
@export var render_rate_camera_updates: bool = false:
	set(value):
		render_rate_camera_updates = value
		if is_inside_tree():
			_apply_update_timing()

## Displays constraint look feedback outside the player's debug view. Debug view always enables it.
@export var constraint_mouse_debug_enabled: bool = false
var _constraint_mouse_debug: Control = null

@export_group("Post Process Exempt 3D")
## Enables a secondary 3D pass for floating text that should not be affected by camera post processing.
@export var post_process_exempt_3d_enabled: bool = true
## Hides the post-process-exempt 3D layer from the main camera after the secondary pass is enabled.
@export var post_process_exempt_3d_hide_from_main_view: bool = false
## Canvas layer used to composite the post-process-exempt 3D pass over the main view.
@export var post_process_exempt_3d_canvas_layer: int = 79

const POST_PROCESS_EXEMPT_3D_LAYER_INDEX: int = 20
const AUTO_FOLLOW_LOCKED_MOTION_FLOOR: float = 0.65
const ASPECT_RATIO_16_9: float = 16.0 / 9.0
const ASPECT_RATIO_21_9: float = 21.0 / 9.0
const CAMERA_ALIGNMENT_ACTION: StringName = &"VomitCam"

@export_group("Alignment Input")
## Hold duration before camera alignment temporarily switches to rear view.
@export_range(0.01, 0.5, 0.01) var rear_view_hold_seconds: float = 0.2
## Maximum press duration that toggles camera alignment on release, including brief rear-view holds.
@export_range(0.01, 1.0, 0.01, "suffix:s") var alignment_tap_release_seconds: float = 0.3

@export_group("Auto Target")
@export var auto_target_local_player: bool = true
@export var auto_target_group: StringName = &"Player"
@export var auto_target_retry_interval: float = 0.25

var _auto_target_timer: float = 0.0

@export var distance: float = 8.0
@export var vertical_offset: float = 1.5        # base / mid offset

@export var min_vertical_offset: float = 0.5    # lowest when fully zoomed in
@export var max_vertical_offset: float = 1.8    # highest when fully zoomed out

@export var yaw_sensitivity: float = 0.005
@export var pitch_sensitivity: float = 0.005
@export var min_pitch_deg: float = -30.0
@export var max_pitch_deg: float = 60.0

@export var smooth_follow: bool = false
@export var follow_smooth: float = 10.0

@export_group("Aspect Ratio Framing")
## Enables an upward camera target offset as the viewport narrows from 21:9 to 16:9.
@export var aspect_ratio_height_offset_enabled: bool = true
## Upward camera target offset applied at 16:9 and narrower aspect ratios.
@export var aspect_ratio_height_offset_16_9: float = 0.45

@export_group("Dolly Follow")
## Enables velocity-matched spring tracking for the free camera pivot.
@export var dolly_follow_enabled: bool = true
## Uses terrain alignment and physics velocity for grounded dolly tracking and lookahead.
@export var dolly_surface_tracking_enabled: bool = true
## Damping ratio for the dolly spring. 1.0 is critically damped.
@export_range(0.1, 2.0, 0.05) var dolly_damping_ratio: float = 1.0
## Smoothing rate applied to measured target velocity.
@export var dolly_velocity_smoothing: float = 12.0
## Maximum distance the dolly may trail the target along its travel heading.
@export var dolly_max_lag_distance: float = 1.5
## Maximum distance the dolly may lead the target while lookahead is inactive.
@export var dolly_max_lead_distance: float = 0.75
## Maximum sideways displacement from the target's travel heading.
@export var dolly_max_lateral_distance: float = 0.65
## Maximum displacement along the effective camera-up axis.
@export var dolly_max_vertical_distance: float = 0.75
## Normalized leash usage where the spring begins increasing its response.
@export_range(0.0, 1.0, 0.01) var dolly_catchup_start: float = 0.65
## Maximum spring response multiplier near the edge of the leash.
@export var dolly_catchup_multiplier: float = 2.5
## Enables a bounded velocity-based shift of the dolly tracking anchor.
@export var target_lookahead_enabled: bool = true
## Prediction time used to calculate the target lookahead offset.
@export var target_lookahead_time: float = 0.075
## Maximum world-space distance of the target lookahead offset.
@export var target_lookahead_max_distance: float = 1.5
## Fraction of vertical target velocity included in lookahead.
@export_range(0.0, 1.0, 0.05) var target_lookahead_vertical_scale: float = 0.35
## Fraction of lateral target velocity included while the lookahead heading turns.
@export_range(0.0, 1.0, 0.05) var target_lookahead_lateral_strength: float = 0.2
## Heading deviation ignored by target lookahead.
@export_range(0.0, 45.0, 0.5) var target_lookahead_heading_deadzone_deg: float = 4.0
## Heading deviation where target lookahead reaches full turning influence.
@export_range(0.0, 90.0, 0.5) var target_lookahead_heading_full_response_deg: float = 20.0
## Time a heading change must persist before normal lookahead steering fully engages.
@export_range(0.0, 0.5, 0.01) var target_lookahead_heading_persistence: float = 0.1
## Smoothing rate applied to the persistent target lookahead heading.
@export var target_lookahead_heading_smoothing: float = 9.0
## Maximum rotation rate of the target lookahead heading.
@export var target_lookahead_heading_max_turn_rate_deg: float = 120.0
## Smoothing rate used when lateral lookahead gains influence.
@export var target_lookahead_lateral_engage_smoothing: float = 8.0
## Smoothing rate used when lateral lookahead releases influence.
@export var target_lookahead_lateral_release_smoothing: float = 16.0
## Speed where target lookahead begins to engage.
@export var target_lookahead_min_speed: float = 5.0
## Speed where target lookahead reaches full strength.
@export var target_lookahead_full_speed: float = 60.0
## Smoothing rate applied when the lookahead offset changes.
@export var target_lookahead_smoothing: float = 10.0
## Smoothing rate used when lookahead retracts during braking or reversal.
@export var target_lookahead_release_smoothing: float = 24.0
## Global multiplier applied to the target lookahead offset.
@export_range(0.0, 1.0, 0.01) var target_lookahead_strength: float = 1.0

@export_group("Auto Follow")
## Enables automatic yaw alignment toward sustained player travel.
@export var auto_follow_enabled: bool = false
## Maximum automatic yaw and pitch response speed.
@export var auto_follow_sensitivity: float = 12.0
## Time after manual camera input before automatic follow can resume.
@export var auto_follow_interrupt_delay: float = 2.0
## Low-speed heading deviation ignored by automatic yaw follow. This zone collapses across the speed ramp.
@export var auto_follow_deadzone_deg: float = 15.0
## Heading deviation where automatic yaw follow reaches full angular influence.
@export var auto_follow_max_deviation_deg: float = 90.0
## Minimum angular influence used for micro-corrections after the deadzone collapses at high speed.
@export_range(0.0, 1.0, 0.01) var auto_follow_high_speed_micro_strength: float = 0.15
## Total movement speed below which automatic follow remains inactive.
@export var auto_follow_min_speed: float = 12.0
## Total movement speed where automatic follow reaches full motion influence. 0 disables the ramp above the minimum speed.
@export var auto_follow_speed_ramp: float = 80.0
## Lateral departure speed where automatic yaw follow reaches its fastest response. 0 keeps the fastest response at all speeds.
@export var auto_follow_departure_speed_ramp: float = 55.0
## Planar share of total velocity where yaw-heading confidence reaches full strength.
@export_range(0.0, 1.0, 0.01) var auto_follow_planar_confidence: float = 0.35
## Travel-heading smoothing at the low end of the speed ramp.
@export var auto_follow_heading_smoothing_min: float = 4.0
## Travel-heading smoothing at full speed.
@export var auto_follow_heading_smoothing_max: float = 14.0
## Blend speed when automatic yaw follow gains control.
@export var auto_follow_engage_smoothing: float = 7.0
## Blend speed when automatic yaw follow releases control.
@export var auto_follow_release_smoothing: float = 12.0
## Maximum automatic yaw rotation rate in degrees per second. 0 disables the limit.
@export var auto_follow_max_turn_rate_deg: float = 240.0
## Half-angle around directly backward travel where reversal intent begins accumulating.
@export_range(0.0, 90.0, 0.5) var auto_follow_backward_intent_cone_deg: float = 30.0
## Backward travel duration required near the minimum auto-follow speed.
@export var auto_follow_backward_slow_hold_duration: float = 0.65
## Backward travel duration required at full auto-follow speed.
@export var auto_follow_backward_fast_hold_duration: float = 0.16
## Camera-to-motion angle where an active backward turn returns to normal follow.
@export_range(0.0, 180.0, 0.5) var auto_follow_backward_release_deg: float = 75.0
## Maximum automatic yaw rotation rate during a backward-facing turn.
@export var auto_follow_backward_max_turn_rate_deg: float = 135.0
## Response multiplier applied during a backward-facing turn.
@export_range(0.1, 1.0, 0.05) var auto_follow_backward_response_scale: float = 0.65
## Enables gravity-relative pitch adjustment from the same movement sample used by yaw follow.
@export var auto_follow_vertical_enabled: bool = false
## Maximum pitch offset produced by vertical travel.
@export var auto_follow_vertical_max_tilt_deg: float = 15.0
## Persistent pitch target approached according to automatic follow's current movement influence.
@export var auto_follow_level_pitch_deg: float = 0.0
## Fraction of auto-follow strength to remove when moving directly uphill on steep surfaces (0..1). 0 disables.
@export var auto_follow_slope_suppression: float = 0.0
## Surface tilt (degrees from gravity-up) above which slope suppression can engage.
@export var auto_follow_slope_threshold_deg: float = 15.0

@export_group("Parkour Camera")
## Enables lateral wall-run framing and wall-kick direction assistance.
@export var parkour_camera_enabled: bool = true
## Maximum screen-horizontal target offset toward the open side of a wall run.
@export var parkour_wall_run_pan_distance: float = 1.25
## Wall-run speed where lateral panning begins.
@export var parkour_wall_run_pan_min_speed: float = 20.0
## Wall-run speed where lateral panning reaches its maximum distance.
@export var parkour_wall_run_pan_full_speed: float = 100.0
## Fraction of the configured pan retained at the beginning of a wall run.
@export_range(0.0, 1.0, 0.01) var parkour_wall_run_pan_min_strength: float = 0.55
## Blend speed while wall-run panning engages.
@export var parkour_wall_run_pan_engage_smoothing: float = 7.0
## Blend speed while wall-run panning releases.
@export var parkour_wall_run_pan_release_smoothing: float = 11.0
## Enables controller-only yaw assistance toward wall-kick launch direction.
@export var parkour_wall_kick_assist_enabled: bool = true
## Maximum yaw correction applied by a wall kick.
@export_range(0.0, 45.0, 0.5) var parkour_wall_kick_assist_max_yaw_deg: float = 18.0
## Duration available for a wall-kick yaw correction.
@export var parkour_wall_kick_assist_duration: float = 0.4
## Response speed of the wall-kick yaw correction.
@export var parkour_wall_kick_assist_smoothing: float = 8.0
## Outward kick speed where yaw assistance begins.
@export var parkour_wall_kick_assist_min_speed: float = 6.0
## Outward kick speed where yaw assistance reaches full strength.
@export var parkour_wall_kick_assist_full_speed: float = 60.0
## View-angle deviation where backward-facing yaw assistance begins fading out.
@export_range(90.0, 179.0, 1.0) var parkour_wall_kick_assist_backward_fade_deg: float = 120.0
## Minimum wall-kick assistance retained for a directly backward launch.
@export_range(0.0, 1.0, 0.05) var parkour_wall_kick_assist_backward_min_strength: float = 0.65
## Duration a wall kick may bypass the backward intent delay.
@export var parkour_wall_kick_backward_bypass_duration: float = 0.55
## Right-stick strength that immediately cancels wall-kick yaw assistance.
@export_range(0.0, 1.0, 0.01) var parkour_wall_kick_assist_cancel_stick_strength: float = 0.55

@export_group("Override Cancel")
## Manual look strength that releases cancelable camera constraints.
@export_range(0.0, 1.0) var override_cancel_stick_threshold: float = 0.85
## Mouse displacement that releases cancelable camera constraints.
@export var override_cancel_mouse_threshold: float = 12.0

@export_group("Drift Camera")
## Enables the drift-specific dolly and target lookahead profile.
@export var drift_camera_enabled: bool = true
## Applies a dolly response override while drifting.
@export var drift_follow_enabled: bool = true
## Dolly response used while drifting (0 = no smoothing).
@export var drift_follow_smooth: float = 12.0
## Blend speed for activating the drift camera profile (per second, 0 = instant).
@export var drift_camera_blend_speed: float = 6.0
## Target velocity smoothing used while drifting.
@export var drift_velocity_smoothing: float = 18.0
## Maximum heading bias applied to drift lookahead from turn speed.
@export var drift_turn_yaw_offset_max_deg: float = 12.0
## Lookahead heading bias per degree per second of drift turn speed.
@export var drift_turn_yaw_offset_per_turn_speed: float = 0.06
## Smoothing speed for the turn-based lookahead heading bias.
@export var drift_turn_yaw_offset_slerp_speed: float = 8.0
## Lateral velocity share retained by target lookahead while drifting.
@export_range(0.0, 1.0, 0.01) var drift_lookahead_lateral_strength: float = 0.55
## Heading change ignored by drift lookahead.
@export_range(0.0, 45.0, 0.1) var drift_lookahead_heading_deadzone_deg: float = 1.5
## Heading change where drift lookahead reaches full response.
@export_range(0.0, 90.0, 0.5) var drift_lookahead_heading_full_response_deg: float = 12.0
## Duration a drift heading change must persist before full lookahead adjustment.
@export var drift_lookahead_heading_persistence: float = 0.03
## Heading smoothing used by drift lookahead.
@export var drift_lookahead_heading_smoothing: float = 14.0
## Maximum drift lookahead heading rotation rate in degrees per second.
@export var drift_lookahead_heading_max_turn_rate_deg: float = 220.0
## Multiplier applied to target lookahead time while drifting.
@export var drift_lookahead_time_multiplier: float = 1.15
## Multiplier applied to the lateral dolly leash while drifting.
@export_range(0.1, 2.0, 0.05) var drift_lateral_leash_multiplier: float = 0.8

@export_group("Zoom Options")
@export var min_distance: float = 3.0
@export var max_distance: float = 15.0
@export var zoom_speed: float = 2.0          # How fast zoom reacts
@export var zoom_smooth: float = 10.0        # 0 = instant, 5–15 = smooth
@export var camera_collision_enabled: bool = true
@export_flags(
	"World",
	"Characters",
	"Player",
	"PlayerHitbox",
	"KinematicsHeavy",
	"Triggers",
	"HUD",
	"Reserved8",
	"Reserved9",
	"Reserved10",
	"Reserved11",
	"Reserved12",
	"Reserved13",
	"Reserved14",
	"Reserved15",
	"Reserved16"
) var camera_collision_mask: int = 1
@export var camera_collision_margin: float = 0.2
@export var camera_min_collision_distance: float = 0.5

## Stabilizes obstruction recovery. Disable to restore instant collision distance changes.
@export var camera_collision_stabilization_enabled: bool = true
## Time that additional clearance must persist before camera distance recovers.
@export_range(0.0, 0.5, 0.01, "or_greater") var camera_collision_clear_delay: float = 0.08
## Exponential distance recovery rate. Zero restores distance instantly after the clear delay.
@export_range(0.0, 30.0, 0.5, "or_greater") var camera_collision_recovery_speed: float = 8.0
## Additional safe distance required to recover while obstructed. Retraction remains immediate.
@export_range(0.0, 0.5, 0.01, "or_greater") var camera_collision_distance_tolerance: float = 0.08

var _camera_collision_initialized: bool = false
var _camera_collision_recovering: bool = false
var _camera_collision_distance: float = 0.0
var _camera_collision_clear_timer: float = 0.0
var _camera_collision_target_ref: Node3D
var _camera_collision_rear_view: bool = false

## Manually lock player camera input (e.g. for manual airborne torque).
var manual_input_locked: bool = false
var _manual_input_lock_allows_auto_follow: bool = false

var _distance_target: float                  # internal zoom target
# ---------------------

@export_group("Speed FOV")
## Enable speed-based FOV boost when the player is moving fast.
@export var speed_fov_enabled: bool = true
## Maximum FOV boost offset when fully active (added to the default settings FOV).
@export var speed_fov_max_offset: float = 15.0
## Speed where the FOV boost starts (lateral, relative to camera up).
@export var speed_fov_min_speed: float = 25.0
## Speed where the FOV boost reaches max (lateral, relative to camera up).
@export var speed_fov_max_speed: float = 120.0
## Smoothing speed for FOV blending (per second, 0 = instant).
@export var speed_fov_smooth: float = 6.0

@export_group("Landing Feedback")
## Duration of landing roll FOV and hard-landing shake feedback.
@export_range(0.05, 2.0, 0.01, "suffix:s") var landing_feedback_duration: float = 0.58
## FOV increase when a landing roll is accepted.
@export_range(0.0, 40.0, 0.1, "suffix:°") var landing_roll_accepted_fov: float = 18.0
## FOV decrease for a rough landing without a roll.
@export_range(0.0, 40.0, 0.1, "suffix:°") var landing_hard_fov: float = 12.0
## FOV decrease when a parkour landing roll grants no speed benefit or is rejected.
@export_range(0.0, 40.0, 0.1, "suffix:°") var landing_roll_rejected_fov: float = 10.0
## Minimum vertical camera displacement for a qualifying rough landing.
@export_range(0.0, 20.0, 0.001, "suffix:m") var landing_hard_shake_min: float = 0.01
## Maximum vertical camera displacement for a full-strength hard landing.
@export_range(0.0, 20.0, 0.001, "suffix:m") var landing_hard_shake: float = 1.175

@export_group("Speed Distance")
## Enable speed-based distance reduction to compensate for higher FOV.
@export var speed_distance_enabled: bool = false
## Maximum distance reduction when fully active (positive values zoom in).
@export var speed_distance_max_offset: float = 0.6
## Smoothing speed for distance blending (per second, 0 = instant).
@export var speed_distance_smooth: float = 6.0

@export_group("Speed Vertical Offset")
## Enable speed-based vertical offset to compensate for higher FOV.
@export var speed_vertical_offset_enabled: bool = true
## Maximum vertical offset when fully active (positive raises the camera target).
@export var speed_vertical_offset_max_offset: float = 0.15
## Smoothing speed for vertical offset blending (per second, 0 = instant).
@export var speed_vertical_offset_smooth: float = 6.0

@export_group("Speed Radial Blur")
## Enables an aspect-correct radial blur at the screen edges while the speed FOV effect is active.
@export var speed_radial_blur_enabled: bool = true
## Fullscreen radial blur scene instantiated by the camera rig.
@export var speed_radial_blur_effect_scene: PackedScene
## Maximum inward screen-space blur radius at full speed.
@export_range(0.0, 0.2, 0.001) var speed_radial_blur_max_radius: float = 0.06
## Aspect-correct radius where the transparent center begins blending into the blur mask.
@export_range(0.0, 1.5, 0.01) var speed_radial_blur_vignette_inner_radius: float = 0.24
## Aspect-correct radius where the blur mask reaches full strength.
@export_range(0.0, 1.5, 0.01) var speed_radial_blur_vignette_outer_radius: float = 0.58
## Maximum opacity of the blurred edge layer.
@export_range(0.0, 1.0, 0.01) var speed_radial_blur_max_opacity: float = 0.9
## Amount of organic intensity and vignette-radius pulsing.
@export_range(0.0, 1.0, 0.01) var speed_radial_blur_pulse_amount: float = 0.12
## Primary vignette pulse frequency in cycles per second.
@export_range(0.0, 10.0, 0.05) var speed_radial_blur_pulse_frequency: float = 1.6
## Subtle radial color separation applied near the outer edge.
@export_range(0.0, 0.02, 0.00005) var speed_radial_blur_chromatic_separation: float = 0.00025
## Number of evenly distributed speed-line spawn lanes assigned to each screen side.
@export_range(2, 16, 1) var speed_radial_blur_line_lanes_per_side: int = 10
## Maximum visibility of the neutral-colored edge speed lines.
@export_range(0.0, 1.0, 0.01) var speed_radial_blur_line_opacity: float = 0.14
## Number of new randomized speed-line formations generated per second in each lane.
@export_range(0.1, 20.0, 0.1) var speed_radial_blur_line_spawn_rate: float = 8.0
## Portion of each spawn interval that a speed line remains visible.
@export_range(0.05, 0.95, 0.01) var speed_radial_blur_line_lifetime_fraction: float = 0.75
## Width of each speed line relative to its evenly allocated edge lane.
@export_range(0.005, 0.25, 0.001) var speed_radial_blur_line_width: float = 0.012
## Radial distance each speed line reaches inward from the outer frame.
@export_range(0.05, 0.9, 0.01) var speed_radial_blur_line_length: float = 0.5
## Blend speed used when the radial blur enters or exits.
@export var speed_radial_blur_smooth: float = 6.0

@export_group("Underwater Effect")
## Enable the underwater camera effect when the camera lens is inside a water volume.
@export var underwater_effect_enabled: bool = true
## Packed scene for the UnderwaterEffect CanvasLayer (UnderwaterEffect.tscn).
@export var underwater_effect_scene: PackedScene
## Node path to the Area3D water detector child on SonicCamera.
@export var camera_water_detector: NodePath = ^"CameraYawRig/CameraPitchRig/SonicCamera/CameraWaterDetector"

@export_group("Camera Water Audio")
## Enable camera water entry, exit, and underwater loop sounds.
@export var camera_water_audio_enabled: bool = true
## Played when the camera lens enters water.
@export var camera_water_entry_stream: AudioStream
## Played when the camera lens exits water.
@export var camera_water_exit_stream: AudioStream
## Loop played while the camera lens is underwater.
@export var camera_water_loop_stream: AudioStream
## Audio player for camera water entry and exit sounds.
@export var camera_water_one_shot_player: NodePath = ^"CameraYawRig/CameraPitchRig/SonicCamera/CameraWaterOneShotPlayer"
## Audio player for the camera underwater loop.
@export var camera_water_loop_player: NodePath = ^"CameraYawRig/CameraPitchRig/SonicCamera/CameraWaterLoopPlayer"
## Target volume for the underwater loop while active.
@export var camera_water_loop_volume_db: float = 0.0
## Muted volume for the underwater loop while inactive.
@export var camera_water_loop_silent_db: float = -80.0
## Underwater loop fade-in speed in decibels per second.
@export var camera_water_loop_fade_in_speed: float = 40.0
## Underwater loop fade-out speed in decibels per second.
@export var camera_water_loop_fade_out_speed: float = 55.0

@export_group("Barrier Blast Multipliers")
## Multiplier for speed-based FOV boost while in Barrier Blast.
@export var barrier_blast_fov_multiplier: float = 1.35
## Multiplier for speed-based distance reduction while in Barrier Blast.
@export var barrier_blast_distance_multiplier: float = 1.35
## Multiplier for speed-based vertical offset while in Barrier Blast.
@export var barrier_blast_vertical_offset_multiplier: float = 1.35
## Multiplier for radial blur intensity while in Barrier Blast.
@export var barrier_blast_radial_blur_multiplier: float = 1.55

@export_group("Up Vector")
@export var use_player_up: bool = false
@export_range(0.0, 1.0) var player_up_influence: float = 1.0
## Slerp speed for blending camera up toward player up (0 = instant).
@export var player_up_slerp_speed: float = 8.0
## Preserves camera heading by rolling through inverted player-up attach and detach transitions.
@export var preserve_heading_through_inverted_transitions: bool = true
## Blend speed used while an inverted attach or detach transition is active.
@export var inverted_transition_slerp_speed: float = 20.0
## Minimum surface-normal angle from gravity-up that uses the inverted attachment transition.
@export_range(90.0, 180.0, 0.5) var inverted_attachment_min_surface_angle_deg: float = 155.0
## Time after attachment that an inverted contact can start the transition.
@export_range(0.0, 1.0, 0.01) var inverted_attachment_detection_grace_time: float = 0.25
## Minimum surface-relative speed required before an inverted attachment transition starts.
@export_range(0.0, 100.0, 0.1) var inverted_attachment_min_movement_speed: float = 5.0
## Influence of grounded travel direction on the destination yaw heading after attaching.
@export_range(0.0, 1.0, 0.05) var inverted_attachment_movement_heading_influence: float = 1.0
## Minimum surface-normal angle from gravity-up that uses the inverted detachment transition.
@export_range(90.0, 180.0, 0.5) var inverted_detachment_min_surface_angle_deg: float = 155.0
## Influence of movement direction on the destination yaw heading after detaching.
@export_range(0.0, 1.0, 0.05) var inverted_detachment_movement_heading_influence: float = 1.0

@export var invert_y_mouse: bool = false
@export var invert_y_input: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _control_yaw: float = 0.0
var _control_pitch: float = 0.0
var _mouse_delta: Vector2 = Vector2.ZERO
var _camera_look_strength: float = 0.0
var _camera_mouse_strength: float = 0.0
var _render_look_strength_pending: float = 0.0
var _render_mouse_strength_pending: float = 0.0
var _render_input_orientation_dirty: bool = false
var _auto_follow_interrupt_timer: float = 0.0
var _auto_follow_preview_active: bool = false
var _auto_follow_preview_velocity: Vector3 = Vector3.ZERO
var _auto_follow_heading: Vector3 = Vector3.ZERO
var _auto_follow_heading_up: Vector3 = Vector3.UP
var _auto_follow_motion_weight: float = 0.0
var _auto_follow_pitch_offset: float = 0.0
var _auto_follow_backward_hold_timer: float = 0.0
var _auto_follow_backward_turn_active: bool = false
var _auto_follow_backward_turn_sign: float = 1.0
var _auto_follow_backward_bypass_timer: float = 0.0
var _drift_camera_active_target: bool = false
var _drift_camera_blend: float = 0.0
var _drift_camera_blend_target: float = 0.0
var _drift_heading_dir: Vector3 = Vector3.ZERO
var _drift_turn_speed_target: float = 0.0
var _drift_turn_yaw_offset_current: float = 0.0

# Camera constraints (volumes)
var _constraint_driver: CameraConstraintController = CameraConstraintController.new()
var _influence_free_pivot: Vector3 = Vector3.ZERO
var _influence_free_pivot_valid: bool = false
var _default_fov: float = 70.0
var _speed_fov_current: float = 0.0
var _landing_feedback_remaining: float = 0.0
var _landing_feedback_elapsed: float = 0.0
var _landing_fov_peak: float = 0.0
var _landing_fov_applied: float = 0.0
var _landing_shake_peak: float = 0.0
var _speed_fov_weight: float = 0.0
var _speed_distance_current: float = 0.0
var _speed_vertical_offset_current: float = 0.0
var _parkour_wall_run_pan_current: Vector3 = Vector3.ZERO
var _parkour_wall_kick_assist_active: bool = false
var _parkour_wall_kick_assist_elapsed: float = 0.0
var _parkour_wall_kick_assist_runtime_duration: float = 0.0
var _parkour_wall_kick_assist_target_yaw: float = 0.0
var _camera_base_local_transform: Transform3D = Transform3D.IDENTITY
var _has_camera_base_local_transform: bool = false
var _distance_lock_active: bool = false
var _distance_lock_saved_distance: float = 0.0
var _distance_lock_saved_distance_target: float = 0.0
var _distance_lock_saved_collision_enabled: bool = true
var _teleport_snap_timer: float = 0.0
var _teleport_snap_duration: float = 0.12
var _teleport_revision: int = 0
var _dolly_initialized: bool = false
var _dolly_position: Vector3 = Vector3.ZERO
var _dolly_surface_up: Vector3 = Vector3.ZERO
var _dolly_was_surface_tracking: bool = false
var _dolly_surface_relative_velocity: Vector3 = Vector3.ZERO
var _dolly_velocity: Vector3 = Vector3.ZERO
var _dolly_target_velocity: Vector3 = Vector3.ZERO
var _dolly_last_target_position: Vector3 = Vector3.ZERO
var _target_lookahead_current: Vector3 = Vector3.ZERO
var _dolly_target_ref: Node3D = null
var _dolly_leash_ratio: float = 0.0
var _dolly_source_velocity: Vector3 = Vector3.ZERO
var _target_lookahead_heading: Vector3 = Vector3.ZERO
var _target_lookahead_heading_up: Vector3 = Vector3.UP
var _target_lookahead_heading_change_timer: float = 0.0
var _target_lookahead_lateral_weight: float = 0.0

var _settings_follow_smooth: float = 0.0
var _settings_smooth_follow: bool = false
var _roll_offset: float = 0.0
var _player_up_toggle_enabled: bool = false
var _alignment_press_active: bool = false
var _alignment_press_time: float = 0.0
var _rear_view_active: bool = false
var _rear_view_transform_applied: bool = false
var _rear_view_base_local_transform: Transform3D = Transform3D.IDENTITY
var _rear_view_control_forward: Vector3 = Vector3.ZERO
## Cached HUD used to present camera orientation changes.
var _camera_orientation_hud: Node = null
var _camera_orientation_hud_id: int = 0
var _camera_orientation_hud_mode: bool = false
var _camera_up_current: Vector3 = Vector3.UP
var _camera_up_target: Vector3 = Vector3.UP
var _base_forward_ref: Vector3 = -Vector3.FORWARD
var _inverted_up_transition_active: bool = false
var _camera_up_was_grounded: bool = false
var _player_up_was_effective: bool = false
var _last_grounded_surface_up: Vector3 = Vector3.UP
var _inverted_up_transition_heading: Vector3 = Vector3.ZERO
var _inverted_up_transition_target_up: Vector3 = Vector3.UP
var _inverted_up_transition_is_attachment: bool = false
var _inverted_up_transition_frames: int = 0
var _inverted_up_transition_control_yaw_origin: float = 0.0
var _inverted_attachment_transition_up: Vector3 = Vector3.ZERO
var _inverted_attachment_detection_timer: float = 0.0
var _inverted_attachment_transition_consumed: bool = false

# Underwater effect state
var _camera_water_volume_count: int = 0
var _camera_in_water: bool = false
var _underwater_effect: Node = null
var _speed_radial_blur_effect: Node = null
var _camera_water_detector_node: Area3D = null
var _camera_water_one_shot_player: AudioStreamPlayer = null
var _camera_water_loop_player: AudioStreamPlayer = null
var _camera_water_loop_target_db: float = -80.0
var _post_process_exempt_layer_node: CanvasLayer = null
var _post_process_exempt_viewport: SubViewport = null
var _post_process_exempt_camera: Camera3D = null
var _post_process_exempt_texture_rect: TextureRect = null
var _post_process_exempt_layer_bit_active: int = 0
var _physics_interpolation_mode_before_render_updates: int = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var _yaw_interpolation_mode_before_render_updates: int = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var _pitch_interpolation_mode_before_render_updates: int = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var _camera_interpolation_mode_before_render_updates: int = Node.PHYSICS_INTERPOLATION_MODE_INHERIT


func _ready() -> void:
	_constraint_driver.rig = self
	var debug_layer: CanvasLayer = CanvasLayer.new()
	debug_layer.layer = 90
	add_child(debug_layer)
	_constraint_mouse_debug = preload("res://LS5Framework/Scripts/Camera/Constraints/CameraMouseOffsetDebug.gd").new()
	_constraint_mouse_debug.set("rig", self)
	debug_layer.add_child(_constraint_mouse_debug)
	_player_up_toggle_enabled = use_player_up
	if not is_in_group("CameraRig"):
		add_to_group("CameraRig")

	if yaw_node == null:
		yaw_node = get_node_or_null("CameraYawRig")
	if pitch_node == null and yaw_node != null:
		pitch_node = yaw_node.get_node_or_null("CameraPitchRig")
	if camera == null and pitch_node != null:
		camera = pitch_node.get_node_or_null("SonicCamera")
	_physics_interpolation_mode_before_render_updates = physics_interpolation_mode
	if yaw_node != null:
		_yaw_interpolation_mode_before_render_updates = yaw_node.physics_interpolation_mode
	if pitch_node != null:
		_pitch_interpolation_mode_before_render_updates = pitch_node.physics_interpolation_mode
	if camera != null:
		_camera_interpolation_mode_before_render_updates = camera.physics_interpolation_mode
	_apply_update_timing()
	if camera != null:
		_default_fov = camera.fov
		_camera_base_local_transform = camera.transform
		_has_camera_base_local_transform = true
		_default_fov = SettingsManager.camera_default_fov
		camera.fov = _default_fov
	_speed_fov_current = _default_fov
	_speed_fov_weight = 0.0
	_speed_distance_current = 0.0
	_speed_vertical_offset_current = 0.0
	_camera_up_target = _compute_camera_up_target()
	_camera_up_current = _camera_up_target
	_base_forward_ref = -Vector3.FORWARD
	_auto_follow_heading_up = _camera_up_current
	_camera_up_was_grounded = _is_target_grounded()
	_player_up_was_effective = _get_use_player_up_effective()
	var initial_surface_up: Vector3 = _get_target_surface_up()
	if _camera_up_was_grounded and initial_surface_up.length() >= 0.001:
		_last_grounded_surface_up = initial_surface_up

	if target == null:
		push_warning("CameraRig: target not set.")

	_ensure_post_process_exempt_3d_pass()
	call_deferred("_sync_camera_orientation_hud", false)

	# Initialize yaw from the current gravity-relative direction.
	if target != null:
		var to_cam: Vector3 = (global_position - target.global_position)
		var initial_up: Vector3 = _get_target_gravity_up()
		to_cam -= initial_up * to_cam.dot(initial_up)
		if to_cam.length() > 0.001:
			to_cam = to_cam.normalized()
			_yaw = _get_yaw_from_forward(to_cam, initial_up, _yaw)

	# Reasonable default pitch
	_pitch = deg_to_rad(15.0)
	_control_yaw = _yaw
	_control_pitch = _pitch

	# Zoom
	_distance_target = distance
	set_follow_smoothing(SettingsManager.camera_follow_smoothing)
	set_dolly_follow_enabled(SettingsManager.camera_dolly_enabled)
	set_target_lookahead_enabled(SettingsManager.camera_target_lookahead_enabled)
	set_target_lookahead_amount(SettingsManager.camera_target_lookahead_amount)
	set_auto_follow_enabled(SettingsManager.camera_auto_follow_enabled)
	set_auto_follow_sensitivity(SettingsManager.camera_auto_follow_sensitivity)
	set_auto_follow_interrupt_delay(SettingsManager.camera_auto_follow_interrupt_delay)
	set_auto_follow_deadzone_deg(SettingsManager.camera_auto_follow_deadzone_deg)
	set_auto_follow_max_deviation_deg(SettingsManager.camera_auto_follow_max_deviation_deg)
	set_auto_follow_vertical_enabled(SettingsManager.camera_auto_follow_vertical_enabled)
	set_auto_follow_vertical_max_tilt_deg(SettingsManager.camera_auto_follow_vertical_max_tilt)
	set_auto_follow_level_pitch_deg(SettingsManager.camera_auto_follow_level_pitch_deg)
	set_auto_follow_speed_ramp(SettingsManager.camera_auto_follow_speed_ramp)
	set_auto_follow_slope_suppression(SettingsManager.camera_auto_follow_slope_suppression)
	set_auto_follow_slope_threshold_deg(SettingsManager.camera_auto_follow_slope_threshold_deg)
	_setup_camera_water_audio()
	_setup_speed_radial_blur_effect()
	_setup_underwater_effect()


func _setup_underwater_effect() -> void:
	if camera_water_detector != NodePath(""):
		_camera_water_detector_node = get_node_or_null(camera_water_detector) as Area3D
	if _camera_water_detector_node != null:
		if not _camera_water_detector_node.area_entered.is_connected(_on_camera_water_area_entered):
			_camera_water_detector_node.area_entered.connect(_on_camera_water_area_entered)
		if not _camera_water_detector_node.area_exited.is_connected(_on_camera_water_area_exited):
			_camera_water_detector_node.area_exited.connect(_on_camera_water_area_exited)
	if not underwater_effect_enabled:
		return
	if underwater_effect_scene != null:
		_underwater_effect = underwater_effect_scene.instantiate()
		add_child(_underwater_effect)


func _setup_speed_radial_blur_effect() -> void:
	if not speed_radial_blur_enabled or speed_radial_blur_effect_scene == null:
		return
	_speed_radial_blur_effect = speed_radial_blur_effect_scene.instantiate()
	add_child(_speed_radial_blur_effect)
	if _speed_radial_blur_effect.has_method("configure"):
		_speed_radial_blur_effect.call(
			"configure",
			speed_radial_blur_max_radius,
			speed_radial_blur_vignette_inner_radius,
			speed_radial_blur_vignette_outer_radius,
			speed_radial_blur_max_opacity,
			speed_radial_blur_pulse_amount,
			speed_radial_blur_pulse_frequency,
			speed_radial_blur_chromatic_separation,
			speed_radial_blur_line_lanes_per_side,
			speed_radial_blur_line_opacity,
			speed_radial_blur_line_spawn_rate,
			speed_radial_blur_line_lifetime_fraction,
			speed_radial_blur_line_width,
			speed_radial_blur_line_length,
			speed_radial_blur_smooth
		)


func _setup_camera_water_audio() -> void:
	if camera_water_one_shot_player != NodePath(""):
		_camera_water_one_shot_player = get_node_or_null(camera_water_one_shot_player) as AudioStreamPlayer
	if camera_water_loop_player != NodePath(""):
		_camera_water_loop_player = get_node_or_null(camera_water_loop_player) as AudioStreamPlayer
	_camera_water_loop_target_db = camera_water_loop_silent_db
	if _camera_water_loop_player != null:
		_camera_water_loop_player.stream = camera_water_loop_stream
		_camera_water_loop_player.volume_db = camera_water_loop_silent_db
		_camera_water_loop_player.set("parameters/looping", true)


func _on_camera_water_area_entered(area: Area3D) -> void:
	if not area.is_in_group("water"):
		return
	var was_in_water: bool = _camera_water_volume_count > 0
	_camera_water_volume_count += 1
	_camera_in_water = true
	if not was_in_water:
		_play_camera_water_one_shot(camera_water_entry_stream)
		_set_camera_water_loop_active(true)
	if _underwater_effect != null:
		if _underwater_effect.has_method("set_underwater"):
			_underwater_effect.call("set_underwater", true)
		var volume: Node = area.get_parent()
		if volume != null and volume.get("override_tint") and _underwater_effect.has_method("set_tint_override"):
			_underwater_effect.call("set_tint_override", volume.get("tint_color_override"))


func _on_camera_water_area_exited(area: Area3D) -> void:
	if not area.is_in_group("water"):
		return
	_camera_water_volume_count = max(_camera_water_volume_count - 1, 0)
	if _camera_water_volume_count <= 0:
		_camera_in_water = false
		_play_camera_water_one_shot(camera_water_exit_stream)
		_set_camera_water_loop_active(false)
		if _underwater_effect != null:
			if _underwater_effect.has_method("set_underwater"):
				_underwater_effect.call("set_underwater", false)
			if _underwater_effect.has_method("clear_tint_override"):
				_underwater_effect.call("clear_tint_override")


func _play_camera_water_one_shot(stream: AudioStream) -> void:
	if not camera_water_audio_enabled:
		return
	if stream == null:
		return
	if _camera_water_one_shot_player == null or not is_instance_valid(_camera_water_one_shot_player):
		return
	_camera_water_one_shot_player.stream = stream
	_camera_water_one_shot_player.play()


func _set_camera_water_loop_active(active: bool) -> void:
	if not camera_water_audio_enabled:
		return
	if _camera_water_loop_player == null or not is_instance_valid(_camera_water_loop_player):
		return
	if camera_water_loop_stream == null:
		return
	if _camera_water_loop_player.stream != camera_water_loop_stream:
		_camera_water_loop_player.stream = camera_water_loop_stream
	_camera_water_loop_target_db = camera_water_loop_volume_db if active else camera_water_loop_silent_db
	if active and not _camera_water_loop_player.playing:
		_camera_water_loop_player.volume_db = camera_water_loop_silent_db
		_camera_water_loop_player.play()


func _update_camera_water_audio(delta: float) -> void:
	if _camera_water_loop_player == null or not is_instance_valid(_camera_water_loop_player):
		return
	var current_db: float = _camera_water_loop_player.volume_db
	var speed: float = camera_water_loop_fade_in_speed if _camera_water_loop_target_db > current_db else camera_water_loop_fade_out_speed
	speed = max(speed, 0.0)
	if speed <= 0.0:
		_camera_water_loop_player.volume_db = _camera_water_loop_target_db
	else:
		_camera_water_loop_player.volume_db = move_toward(current_db, _camera_water_loop_target_db, speed * delta)
	if _camera_water_loop_player.volume_db <= camera_water_loop_silent_db + 0.01 and _camera_water_loop_target_db <= camera_water_loop_silent_db:
		if _camera_water_loop_player.playing:
			_camera_water_loop_player.stop()


func _unhandled_input(event: InputEvent) -> void:
	if EmoteWheel.is_camera_input_blocked():
		return
	if get_tree() != null and get_tree().paused:
		return
	if manual_input_locked:
		return
	if target != null and is_instance_valid(target):
		if target.has_method("is_ui_input_blocked"):
			var v = target.call("is_ui_input_blocked")
			if v is bool and bool(v):
				return
		if target.has_method("is_post_ui_action_suppressed"):
			var s = target.call("is_post_ui_action_suppressed")
			if s is bool and bool(s):
				return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion and not _constraint_driver.uses_mouse_offset():
		_constraint_driver.handle_manual_look(0.0, event.relative.length())
	if _camera_controls_disabled() and not (event is InputEventMouseMotion and _constraint_driver.uses_mouse_offset()):
		return

	if event is InputEventMouseMotion:
		_mouse_delta += event.relative

	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance_target -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance_target += zoom_speed

	_distance_target = clamp(_distance_target, min_distance, max_distance)


func _process(delta: float) -> void:
	if render_rate_camera_updates:
		_update_camera_input(delta)
		_apply_render_input_orientation()
		_update_post_process_exempt_3d_pass()


func _physics_process(delta: float) -> void:
	if render_rate_camera_updates:
		_camera_look_strength = _render_look_strength_pending
		_camera_mouse_strength = _render_mouse_strength_pending
		_render_look_strength_pending = 0.0
		_render_mouse_strength_pending = 0.0
	_update_camera(delta, not render_rate_camera_updates)
	_render_input_orientation_dirty = false


func _update_camera(delta: float, update_input: bool = true) -> void:
	_restore_rear_view_transform()
	if (target == null or not is_instance_valid(target)) and auto_target_local_player:
		_auto_target_timer = max(_auto_target_timer - delta, 0.0)
		if _auto_target_timer <= 0.0:
			_auto_target_timer = max(auto_target_retry_interval, 0.05)
			_try_auto_target()

	_update_camera_water_audio(delta)

	if target == null or camera == null or yaw_node == null or pitch_node == null:
		_set_speed_radial_blur_intensity(0.0)
		return

	_auto_follow_interrupt_timer = max(_auto_follow_interrupt_timer - delta, 0.0)

	_constraint_driver.advance(delta)
	_update_drift_camera(delta)
	_update_camera_up(delta)

	if update_input:
		_update_camera_input(delta)
	_update_transform(delta)
	_apply_rear_view_transform(delta)
	_update_post_process_exempt_3d_pass()
	_teleport_snap_timer = max(_teleport_snap_timer - delta, 0.0)

	if update_input:
		_mouse_delta = Vector2.ZERO


func _update_camera_input(delta: float) -> void:
	_camera_look_strength = 0.0
	_camera_mouse_strength = 0.0
	if target == null or not is_instance_valid(target) or _is_camera_input_blocked_by_ui():
		_alignment_press_active = false
		_rear_view_active = false
		_mouse_delta = Vector2.ZERO
		return
	if is_instance_valid(_constraint_driver.selected):
		_constraint_driver.handle_manual_look(_get_immediate_manual_look_strength(), 0.0 if _constraint_driver.uses_mouse_offset() else _mouse_delta.length())
	var offset_consumed: bool = _constraint_driver.handle_mouse_motion(_mouse_delta)
	var offset_strength: float = _mouse_delta.length() if offset_consumed else 0.0
	if offset_consumed:
		_mouse_delta = Vector2.ZERO
	var gamepad_look: Vector2 = _get_gamepad_look_input()
	var controller_consumed: bool = _constraint_driver.handle_controller_look(gamepad_look, delta)
	_update_alignment_input()
	_process_zoom(delta)
	if not _camera_controls_disabled():
		_update_angles(delta, controller_consumed)
	if controller_consumed:
		_camera_look_strength = maxf(_camera_look_strength, gamepad_look.length())
	_camera_mouse_strength = maxf(_camera_mouse_strength, offset_strength)
	if render_rate_camera_updates:
		_render_look_strength_pending = max(_render_look_strength_pending, _camera_look_strength)
		_render_mouse_strength_pending = max(_render_mouse_strength_pending, _camera_mouse_strength)
		if _camera_look_strength > 0.001 or _camera_mouse_strength > 0.001:
			_render_input_orientation_dirty = true
	_mouse_delta = Vector2.ZERO


func _get_manual_look_strength() -> float:
	var keyboard: Vector2 = Vector2(
		SettingsManager.get_signed_action_axis(&"camera_left", &"camera_right", 0.0, &"keyboard"),
		SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", 0.0, &"keyboard")
	)
	var gamepad: Vector2 = Vector2(
		SettingsManager.get_signed_action_axis(&"camera_left", &"camera_right", SettingsManager.get_right_stick_deadzone(), &"gamepad"),
		SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", SettingsManager.get_right_stick_deadzone(), &"gamepad")
	)
	return maxf(keyboard.length(), gamepad.length())


func _get_gamepad_look_input() -> Vector2:
	return Vector2(
		SettingsManager.get_signed_action_axis(&"camera_left", &"camera_right", SettingsManager.get_right_stick_deadzone(), &"gamepad"),
		SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", SettingsManager.get_right_stick_deadzone(), &"gamepad")
	)


func _get_immediate_manual_look_strength() -> float:
	if not _constraint_driver.uses_controller_offset():
		return _get_manual_look_strength()
	return Vector2(
		SettingsManager.get_signed_action_axis(&"camera_left", &"camera_right", 0.0, &"keyboard"),
		SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", 0.0, &"keyboard")
	).length()


func _update_alignment_input() -> void:
	var now: float = float(Time.get_ticks_msec()) * 0.001
	if not _alignment_press_active and Input.is_action_just_pressed(CAMERA_ALIGNMENT_ACTION) and Input.is_action_pressed(CAMERA_ALIGNMENT_ACTION):
		_alignment_press_active = true
		_alignment_press_time = now
		_rear_view_active = false
	if not _alignment_press_active:
		return
	var held_seconds: float = now - _alignment_press_time
	if Input.is_action_pressed(CAMERA_ALIGNMENT_ACTION) and held_seconds > rear_view_hold_seconds:
		_rear_view_active = true
	if Input.is_action_just_released(CAMERA_ALIGNMENT_ACTION) or not Input.is_action_pressed(CAMERA_ALIGNMENT_ACTION):
		if held_seconds <= alignment_tap_release_seconds:
			toggle_player_up()
		_alignment_press_active = false
		_rear_view_active = false


func _restore_rear_view_transform() -> void:
	if not _rear_view_transform_applied:
		return
	if camera != null and is_instance_valid(camera):
		camera.transform = _rear_view_base_local_transform
	_rear_view_transform_applied = false
	_rear_view_control_forward = Vector3.ZERO


func _apply_rear_view_transform(delta: float) -> void:
	if not _rear_view_active or camera == null or not is_instance_valid(camera):
		return
	_rear_view_control_forward = get_yaw_forward()
	_rear_view_base_local_transform = camera.transform
	var up: Vector3 = _get_camera_up().normalized()
	if up.length_squared() < 0.000001:
		up = Vector3.UP
	var rear_rotation: Basis = Basis(up, PI)
	var desired_position: Vector3 = global_position + rear_rotation * (camera.global_position - global_position)
	var collision_enabled: bool = camera_collision_enabled
	var constraint: CameraConstraint = _constraint_driver.selected if is_instance_valid(_constraint_driver.selected) else null
	if constraint and _constraint_driver.selected_has_effect() and constraint.collision_mode != CameraConstraint.CollisionMode.INHERIT:
		collision_enabled = constraint.collision_mode == CameraConstraint.CollisionMode.ENABLED
	camera.global_position = _resolve_camera_collision(desired_position, collision_enabled, delta)
	camera.global_basis = _normalize_basis(rear_rotation * camera.global_basis)
	_rear_view_transform_applied = true


func _is_camera_input_blocked_by_ui() -> bool:
	if EmoteWheel.is_camera_input_blocked():
		return true
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_ui_input_blocked"):
		var ui_blocked: Variant = target.call("is_ui_input_blocked")
		if ui_blocked is bool and bool(ui_blocked):
			return true
	if target.has_method("is_post_ui_action_suppressed"):
		var action_suppressed: Variant = target.call("is_post_ui_action_suppressed")
		if action_suppressed is bool and bool(action_suppressed):
			return true
	return false


func _apply_render_input_orientation() -> void:
	if not _render_input_orientation_dirty:
		return
	if camera == null or target == null or yaw_node == null or pitch_node == null:
		return
	if _constraint_driver.is_presenting():
		_constraint_driver.refresh_mouse_orientation()
		return
	camera.global_basis = _get_free_input_basis()
	if _rear_view_transform_applied:
		camera.global_basis = _normalize_basis(Basis(_get_camera_up(), PI) * camera.global_basis)


func _get_free_input_basis() -> Basis:
	var up: Vector3 = _get_camera_up()
	var base_forward: Vector3 = _get_base_forward_ref(up)
	var flat_forward: Vector3 = base_forward.rotated(up, _yaw).normalized()
	var right: Vector3 = up.cross(flat_forward).normalized()
	var forward: Vector3 = up.cross(right).normalized()
	var yaw_basis: Basis = Basis(right, up, -forward)
	if abs(_roll_offset) > 0.0001:
		yaw_basis = yaw_basis.rotated(forward, _roll_offset)
	var pitch_basis: Basis = Basis(Vector3.RIGHT, _pitch)
	var local_camera_basis: Basis = _camera_base_local_transform.basis if _has_camera_base_local_transform else Basis.IDENTITY
	return _normalize_basis(yaw_basis * pitch_basis * local_camera_basis)


func _apply_update_timing() -> void:
	physics_interpolation_mode = _physics_interpolation_mode_before_render_updates
	if yaw_node != null:
		yaw_node.physics_interpolation_mode = _yaw_interpolation_mode_before_render_updates
	if pitch_node != null:
		pitch_node.physics_interpolation_mode = _pitch_interpolation_mode_before_render_updates
	if camera != null:
		camera.physics_interpolation_mode = (
			Node.PHYSICS_INTERPOLATION_MODE_OFF
			if render_rate_camera_updates
			else _camera_interpolation_mode_before_render_updates
		)


func _try_auto_target() -> void:
	if get_tree() == null:
		return
	var nodes = get_tree().get_nodes_in_group(auto_target_group)
	if nodes == null or nodes.size() == 0:
		return

	# Prefer the local authority when in multiplayer.
	var online = multiplayer != null and multiplayer.has_multiplayer_peer()

	var chosen = null
	for n in nodes:
		if n == null:
			continue
		if not (n is Node3D):
			continue
		if online:
			if n.is_multiplayer_authority():
				chosen = n
				break
		else:
			chosen = n
			break

	if chosen != null:
		if target != chosen:
			_reset_auto_follow_state()
			_dolly_initialized = false
		target = chosen


func register_camera_constraint(constraint: Node) -> void:
	if constraint is CameraConstraint:
		_constraint_driver.register(constraint as CameraConstraint)


func unregister_camera_constraint(constraint: Node, reason: StringName = &"released") -> void:
	if constraint is CameraConstraint:
		_constraint_driver.unregister(constraint as CameraConstraint, reason)


func clear_camera_constraints(except_constraint: Node = null, suppress_exit_smoothing: bool = true) -> void:
	_constraint_driver.clear(except_constraint as CameraConstraint, suppress_exit_smoothing)
	_sync_camera_orientation_hud(not suppress_exit_smoothing)


func reset_camera_effects(reset_fov: bool = true) -> void:
	clear_camera_constraints(null, true)
	_restore_camera_local_basis()
	end_distance_lock()
	_roll_offset = 0.0
	_speed_fov_weight = 0.0
	_speed_fov_current = _default_fov
	_landing_feedback_remaining = 0.0
	_landing_feedback_elapsed = 0.0
	_landing_fov_peak = 0.0
	_landing_fov_applied = 0.0
	_landing_shake_peak = 0.0
	_speed_distance_current = 0.0
	_speed_vertical_offset_current = 0.0
	_parkour_wall_run_pan_current = Vector3.ZERO
	_parkour_wall_kick_assist_active = false
	_parkour_wall_kick_assist_elapsed = 0.0
	_parkour_wall_kick_assist_runtime_duration = 0.0
	_parkour_wall_kick_assist_target_yaw = _yaw
	_dolly_initialized = false
	_camera_collision_initialized = false
	if reset_fov and camera:
		camera.fov = _default_fov


func begin_distance_lock(lock_distance: float, disable_collision: bool) -> void:
	if _distance_lock_active:
		return
	_distance_lock_active = true
	_distance_lock_saved_distance = distance
	_distance_lock_saved_distance_target = _distance_target
	_distance_lock_saved_collision_enabled = camera_collision_enabled

	var d: float = float(lock_distance)
	if d <= 0.001:
		d = distance
	distance = d
	_distance_target = d
	if disable_collision:
		camera_collision_enabled = false


func end_distance_lock() -> void:
	if not _distance_lock_active:
		return
	distance = _distance_lock_saved_distance
	_distance_target = _distance_lock_saved_distance_target
	camera_collision_enabled = _distance_lock_saved_collision_enabled
	_distance_lock_active = false


func notify_teleport(duration: float = -1.0) -> void:
	# Temporarily disables camera smoothing by forcing a snap-to-target in _update_transform.
	# Call this whenever the target is teleported/respawned.
	var d: float = duration
	_teleport_revision += 1
	if d < 0.0:
		d = _teleport_snap_duration
	_teleport_snap_timer = max(d, 0.0)
	_reset_auto_follow_state()
	_dolly_initialized = false
	_camera_collision_initialized = false


func get_teleport_revision() -> int:
	return _teleport_revision


func _update_drift_camera(delta: float) -> void:
	if not drift_camera_enabled:
		_drift_camera_active_target = false
		_drift_camera_blend = 0.0
		_drift_camera_blend_target = 0.0
		_drift_heading_dir = Vector3.ZERO
		_drift_turn_speed_target = 0.0
		_drift_turn_yaw_offset_current = 0.0
		return

	var target_blend: float = 0.0
	if _drift_camera_active_target:
		target_blend = clamp(_drift_camera_blend_target, 0.0, 1.0)

	if target_blend < 1.0:
		_drift_camera_blend = target_blend
	elif drift_camera_blend_speed <= 0.0:
		_drift_camera_blend = target_blend
	else:
		var t_raw_blend: float = clamp(drift_camera_blend_speed * delta, 0.0, 1.0)
		var t_ease: float = _ease_in_out_sine(t_raw_blend)
		_drift_camera_blend = lerp(_drift_camera_blend, target_blend, t_ease)

	var max_offset_deg: float = max(drift_turn_yaw_offset_max_deg, 0.0)
	var offset_per_speed: float = drift_turn_yaw_offset_per_turn_speed
	var target_offset_deg: float = 0.0
	if _drift_camera_active_target:
		target_offset_deg = clamp(
			_drift_turn_speed_target * offset_per_speed,
			-max_offset_deg,
			max_offset_deg
		)
	target_offset_deg *= _drift_camera_blend

	var target_offset_rad: float = deg_to_rad(target_offset_deg)
	if drift_turn_yaw_offset_slerp_speed <= 0.0:
		_drift_turn_yaw_offset_current = target_offset_rad
	else:
		var t_raw_offset: float = clamp(drift_turn_yaw_offset_slerp_speed * delta, 0.0, 1.0)
		var t_ease_offset: float = _ease_in_out_sine(t_raw_offset)
		_drift_turn_yaw_offset_current = lerp(_drift_turn_yaw_offset_current, target_offset_rad, t_ease_offset)

func _get_use_player_up_effective() -> bool:
	return _get_player_up_requested() and _is_target_grounded()


func _get_player_up_requested() -> bool:
	var constraint: CameraConstraint = _constraint_driver.selected if is_instance_valid(_constraint_driver.selected) else null
	if is_instance_valid(constraint) and _constraint_driver.selected_has_effect() and not constraint.alignment_override_dismissed and constraint.up_mode != CameraConstraint.UpMode.INHERIT:
		return constraint.up_mode == CameraConstraint.UpMode.PLAYER
	return _player_up_toggle_enabled


func get_use_player_up_effective() -> bool:
	return _get_use_player_up_effective()


func _sync_camera_orientation_hud(animate: bool) -> void:
	var hud_node: Node = _get_camera_orientation_hud()
	if hud_node == null or not hud_node.has_method("set_camera_orientation_mode"):
		return
	var mode: bool = _get_player_up_requested()
	var first_sync: bool = _camera_orientation_hud_id != hud_node.get_instance_id()
	if not first_sync and mode == _camera_orientation_hud_mode:
		return
	_camera_orientation_hud_id = hud_node.get_instance_id()
	_camera_orientation_hud_mode = mode
	hud_node.call("set_camera_orientation_mode", mode, animate and not first_sync)


func _get_camera_orientation_hud() -> Node:
	if _camera_orientation_hud != null and is_instance_valid(_camera_orientation_hud):
		return _camera_orientation_hud
	if get_tree() == null:
		return null
	_camera_orientation_hud = get_tree().get_first_node_in_group("HUD")
	return _camera_orientation_hud


func _is_target_grounded() -> bool:
	if not target or not is_instance_valid(target):
		return false
	if target.has_method("is_grounded"):
		var grounded_value = target.call("is_grounded")
		if grounded_value is bool:
			return bool(grounded_value)
	if target.has_method("is_airborne"):
		var airborne_value = target.call("is_airborne")
		if airborne_value is bool:
			return not bool(airborne_value)
	if target.has_method("is_attached_for_movement"):
		var attached_value = target.call("is_attached_for_movement")
		if attached_value is bool:
			return bool(attached_value)
	var attached_prop = target.get("attached") if target.has_method("get") else null
	if attached_prop is bool:
		return bool(attached_prop)
	return false


func _slerp_unit_vector_safe(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var from_norm: Vector3 = from.normalized()
	var to_norm: Vector3 = to.normalized()
	if from_norm.length() < 0.001:
		return to_norm if to_norm.length() >= 0.001 else _get_target_gravity_up()
	if to_norm.length() < 0.001:
		return from_norm

	var t: float = clamp(weight, 0.0, 1.0)
	var dot_value: float = clamp(from_norm.dot(to_norm), -1.0, 1.0)
	if dot_value > 0.9999:
		var linear_result: Vector3 = from_norm.lerp(to_norm, t)
		return linear_result.normalized() if linear_result.length() >= 0.001 else to_norm

	var axis: Vector3 = from_norm.cross(to_norm)
	if dot_value < -0.9999:
		axis = from_norm.cross(Vector3.RIGHT)
		if axis.length() < 0.001:
			axis = from_norm.cross(Vector3.FORWARD)

	var axis_len: float = axis.length()
	if axis_len < 0.001:
		return to_norm

	axis /= axis_len
	var angle: float = acos(dot_value) * t
	return (Basis(axis, angle) * from_norm).normalized()


func _get_target_player_up() -> Vector3:
	if not target or not is_instance_valid(target):
		return Vector3.ZERO
	var player_up_value: Variant = Vector3.ZERO
	if target.has_method("get_camera_up_vector"):
		player_up_value = target.call("get_camera_up_vector")
	elif target.has_method("get_up_vector"):
		player_up_value = target.call("get_up_vector")
	else:
		return Vector3.ZERO
	if not (player_up_value is Vector3):
		return Vector3.ZERO
	var player_up: Vector3 = (player_up_value as Vector3).normalized()
	return player_up if player_up.length() >= 0.001 else Vector3.ZERO


func _get_target_gravity_up() -> Vector3:
	if target and is_instance_valid(target) and target.has_method("get_gravity_up"):
		var gravity_up_value = target.call("get_gravity_up")
		if gravity_up_value is Vector3:
			var gravity_up: Vector3 = (gravity_up_value as Vector3).normalized()
			if gravity_up.length() >= 0.001:
				return gravity_up
	return Vector3.UP


func _get_target_surface_up() -> Vector3:
	if not target or not is_instance_valid(target):
		return Vector3.ZERO
	if target.has_method("is_rail_camera_alignment_active") and bool(target.call("is_rail_camera_alignment_active")):
		return _get_target_player_up()
	if _is_target_grounded() and target.has_method("get_collision_support_up"):
		var collision_up: Vector3 = target.call("get_collision_support_up")
		if collision_up.length_squared() >= 0.001:
			return collision_up.normalized()
	var surface_up: Vector3 = Vector3.ZERO
	var gravity_up: Vector3 = _get_target_gravity_up()
	var surface_normal_value = target.get("surface_normal")
	if surface_normal_value is Vector3:
		surface_up = (surface_normal_value as Vector3).normalized()
	var stable_normal_valid_value = target.get("_stable_attach_normal_valid")
	if stable_normal_valid_value is bool and bool(stable_normal_valid_value):
		var stable_normal_value = target.get("_stable_attach_normal")
		if stable_normal_value is Vector3:
			var stable_surface_up: Vector3 = (stable_normal_value as Vector3).normalized()
			if (
				stable_surface_up.length() >= 0.001
				and (
					surface_up.length() < 0.001
					or stable_surface_up.dot(gravity_up) < surface_up.dot(gravity_up)
				)
			):
				surface_up = stable_surface_up
	if surface_up.length() >= 0.001:
		return surface_up
	return _get_target_player_up()


func _get_camera_flat_heading(up: Vector3) -> Vector3:
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var heading: Vector3 = _base_forward_ref.rotated(up_norm, _yaw)
	heading -= up_norm * heading.dot(up_norm)
	if heading.length() < 0.001 and yaw_node and is_instance_valid(yaw_node):
		heading = yaw_node.global_transform.basis.z
		heading -= up_norm * heading.dot(up_norm)
	if heading.length() < 0.001:
		heading = up_norm.cross(Vector3.RIGHT)
	if heading.length() < 0.001:
		heading = up_norm.cross(Vector3.FORWARD)
	return heading.normalized()


func _build_camera_up_basis(up: Vector3, heading: Vector3) -> Basis:
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var heading_norm: Vector3 = heading - up_norm * heading.dot(up_norm)
	if heading_norm.length() < 0.001:
		heading_norm = up_norm.cross(Vector3.RIGHT)
	if heading_norm.length() < 0.001:
		heading_norm = up_norm.cross(Vector3.FORWARD)
	heading_norm = heading_norm.normalized()
	var right: Vector3 = up_norm.cross(heading_norm).normalized()
	heading_norm = right.cross(up_norm).normalized()
	return Basis(right, up_norm, heading_norm).orthonormalized()


func _transport_camera_heading_for_up_change(from_up: Vector3, to_up: Vector3) -> void:
	var from_up_norm: Vector3 = from_up.normalized()
	var to_up_norm: Vector3 = to_up.normalized()
	if from_up_norm.length() < 0.001 or to_up_norm.length() < 0.001:
		return
	var up_dot: float = clamp(from_up_norm.dot(to_up_norm), -1.0, 1.0)
	if up_dot > 0.999999:
		return
	var rotation_axis: Vector3 = from_up_norm.cross(to_up_norm)
	if rotation_axis.length() < 0.001:
		return
	rotation_axis = rotation_axis.normalized()
	var transported_reference: Vector3 = Basis(rotation_axis, acos(up_dot)) * _base_forward_ref
	transported_reference -= to_up_norm * transported_reference.dot(to_up_norm)
	if transported_reference.length() >= 0.001:
		_base_forward_ref = transported_reference.normalized()

func _get_target_velocity_heading(up: Vector3, minimum_speed: float) -> Vector3:
	if not target or not is_instance_valid(target):
		return Vector3.ZERO
	var movement: Vector3 = Vector3.ZERO
	if target.has_method("get_player_velocity"):
		var method_velocity_value = target.call("get_player_velocity")
		if method_velocity_value is Vector3:
			movement = method_velocity_value as Vector3
	if movement.length() < 0.001:
		var property_velocity_value = target.get("velocity")
		if property_velocity_value is Vector3:
			movement = property_velocity_value as Vector3
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var movement_heading: Vector3 = movement - up_norm * movement.dot(up_norm)
	var required_speed: float = max(minimum_speed, 0.001)
	return movement_heading.normalized() if movement_heading.length() >= required_speed else Vector3.ZERO

func _get_target_movement_heading(up: Vector3) -> Vector3:
	if not target or not is_instance_valid(target):
		return Vector3.ZERO
	var movement: Vector3 = Vector3.ZERO
	if target.has_method("get_player_velocity"):
		var method_velocity_value = target.call("get_player_velocity")
		if method_velocity_value is Vector3:
			movement = method_velocity_value as Vector3
	if movement.length() < 0.001:
		var property_velocity_value = target.get("velocity")
		if property_velocity_value is Vector3:
			movement = property_velocity_value as Vector3
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var movement_heading: Vector3 = movement - up_norm * movement.dot(up_norm)
	if movement_heading.length() < 0.001 and target.has_method("get_move_direction"):
		var move_direction_value = target.call("get_move_direction")
		if move_direction_value is Vector3:
			movement_heading = move_direction_value as Vector3
			movement_heading -= up_norm * movement_heading.dot(up_norm)
	return movement_heading.normalized() if movement_heading.length() >= 0.001 else Vector3.ZERO


func _capture_inverted_transition_heading(target_up: Vector3, use_movement_heading: bool, movement_heading_override: Vector3 = Vector3.ZERO) -> void:
	var target_up_norm: Vector3 = target_up.normalized()
	if target_up_norm.length() < 0.001:
		target_up_norm = _get_target_gravity_up()
	var camera_heading: Vector3 = _get_camera_flat_heading(_camera_up_current)
	var destination_heading: Vector3 = camera_heading - target_up_norm * camera_heading.dot(target_up_norm)
	if destination_heading.length() < 0.001:
		destination_heading = _base_forward_ref - target_up_norm * _base_forward_ref.dot(target_up_norm)
	if destination_heading.length() < 0.001:
		destination_heading = target_up_norm.cross(Vector3.RIGHT)
	if destination_heading.length() < 0.001:
		destination_heading = target_up_norm.cross(Vector3.FORWARD)
	destination_heading = destination_heading.normalized()

	var movement_heading: Vector3 = movement_heading_override
	if use_movement_heading and movement_heading.length() < 0.001:
		movement_heading = _get_target_movement_heading(target_up_norm)
	var movement_influence: float = clamp(
		inverted_detachment_movement_heading_influence,
		0.0,
		1.0
	)
	if _inverted_up_transition_is_attachment:
		movement_influence = clamp(
			inverted_attachment_movement_heading_influence,
			0.0,
			1.0
		)
	if movement_heading.length() >= 0.001 and movement_influence > 0.0:
		if destination_heading.dot(movement_heading) < -0.9999:
			if movement_influence >= 0.5:
				destination_heading = movement_heading
			else:
				destination_heading = -movement_heading
		else:
			destination_heading = destination_heading.slerp(movement_heading, movement_influence).normalized()
	_inverted_up_transition_heading = destination_heading
	_inverted_up_transition_target_up = target_up_norm


func _transport_inverted_transition_heading_to_up(target_up: Vector3) -> void:
	var from_up: Vector3 = _inverted_up_transition_target_up.normalized()
	var to_up: Vector3 = target_up.normalized()
	if from_up.length() < 0.001 or to_up.length() < 0.001:
		_inverted_up_transition_target_up = to_up
		return
	var up_dot: float = clamp(from_up.dot(to_up), -1.0, 1.0)
	var rotation_axis: Vector3 = from_up.cross(to_up)
	if up_dot < 0.999999 and rotation_axis.length() >= 0.001:
		rotation_axis = rotation_axis.normalized()
		_inverted_up_transition_heading = (
			Basis(rotation_axis, acos(up_dot)) * _inverted_up_transition_heading
		).normalized()
		var projected_heading: Vector3 = (
			_inverted_up_transition_heading
			- to_up * _inverted_up_transition_heading.dot(to_up)
		)
		if projected_heading.length() >= 0.001:
			_inverted_up_transition_heading = projected_heading.normalized()
	_inverted_up_transition_target_up = to_up


func _get_inverted_transition_destination_heading(target_up: Vector3) -> Vector3:
	var target_up_norm: Vector3 = target_up.normalized()
	if target_up_norm.length() < 0.001:
		return Vector3.ZERO
	var destination_heading: Vector3 = (
		_inverted_up_transition_heading
		- target_up_norm * _inverted_up_transition_heading.dot(target_up_norm)
	)
	if destination_heading.length() < 0.001:
		return Vector3.ZERO
	destination_heading = destination_heading.normalized()
	var control_yaw_offset: float = wrapf(
		_yaw - _inverted_up_transition_control_yaw_origin,
		-PI,
		PI
	)
	return destination_heading.rotated(target_up_norm, control_yaw_offset).normalized()

func _is_inverted_transition_orientation_settled(target_up: Vector3) -> bool:
	var target_up_norm: Vector3 = target_up.normalized()
	if target_up_norm.length() < 0.001:
		return true
	if _camera_up_current.normalized().dot(target_up_norm) <= 0.9999:
		return false
	var target_heading: Vector3 = _get_inverted_transition_destination_heading(target_up_norm)
	if target_heading.length() < 0.001:
		return true
	var current_heading: Vector3 = _get_camera_flat_heading(_camera_up_current)
	return current_heading.dot(target_heading) > 0.999

func _update_heading_preserving_camera_up(target_up: Vector3, weight: float) -> bool:
	var current_up: Vector3 = _camera_up_current.normalized()
	var target_up_norm: Vector3 = target_up.normalized()
	if current_up.length() < 0.001 or target_up_norm.length() < 0.001:
		return false
	var current_heading: Vector3 = _get_camera_flat_heading(current_up)
	var target_heading: Vector3 = _get_inverted_transition_destination_heading(target_up_norm)
	if target_heading.length() < 0.001:
		target_heading = current_heading - target_up_norm * current_heading.dot(target_up_norm)
	if target_heading.length() < 0.001:
		return false
	target_heading = target_heading.normalized()
	var current_basis: Basis = _build_camera_up_basis(current_up, current_heading)
	var target_basis: Basis = _build_camera_up_basis(target_up_norm, target_heading)
	var blended_basis: Basis = current_basis.slerp(target_basis, clamp(weight, 0.0, 1.0)).orthonormalized()
	var blended_up: Vector3 = blended_basis.y.normalized()
	var blended_heading: Vector3 = blended_basis.z.normalized()
	_camera_up_current = blended_up
	_base_forward_ref = blended_heading.rotated(blended_up, -_yaw).normalized()
	return true

func _compute_camera_up_target() -> Vector3:
	# Build the target up from gravity, optionally blending toward the player's surface up.
	var gravity_up: Vector3 = _get_target_gravity_up()
	var up: Vector3 = gravity_up
	if _get_use_player_up_effective():
		var player_up: Vector3 = _get_target_player_up()
		if player_up.length() > 0.001:
			var influence: float = clamp(player_up_influence, 0.0, 1.0)
			up = gravity_up.lerp(player_up, influence)
			if up.length() > 0.001:
				up = up.normalized()
	return up


func _update_camera_up(delta: float) -> void:
	var gravity_up: Vector3 = _get_target_gravity_up()
	var target_grounded: bool = _is_target_grounded()
	var player_up_effective: bool = _get_use_player_up_effective()
	var attachment_changed: bool = target_grounded != _camera_up_was_grounded
	if attachment_changed:
		if target_grounded:
			_inverted_attachment_detection_timer = max(inverted_attachment_detection_grace_time, 0.0)
			_inverted_attachment_transition_consumed = false
		else:
			_inverted_attachment_detection_timer = 0.0
			_inverted_attachment_transition_consumed = false
	elif target_grounded:
		_inverted_attachment_detection_timer = max(
			_inverted_attachment_detection_timer - max(delta, 0.0),
			0.0
		)
	else:
		_inverted_attachment_detection_timer = 0.0

	var target_surface_up: Vector3 = _get_target_surface_up()
	var transition_surface_up: Vector3 = _last_grounded_surface_up
	if target_grounded and target_surface_up.length() >= 0.001:
		_last_grounded_surface_up = target_surface_up
		transition_surface_up = target_surface_up
	var surface_up_norm: Vector3 = transition_surface_up.normalized()
	var surface_angle_deg: float = 0.0
	if surface_up_norm.length() >= 0.001:
		surface_angle_deg = rad_to_deg(
			acos(clamp(surface_up_norm.dot(gravity_up), -1.0, 1.0))
		)
	var attachment_angle_threshold: float = clamp(
		inverted_attachment_min_surface_angle_deg,
		90.0,
		180.0
	)
	var detachment_angle_threshold: float = clamp(
		inverted_detachment_min_surface_angle_deg,
		90.0,
		180.0
	)
	var attachment_detection_open: bool = (
		target_grounded
		and not _inverted_attachment_transition_consumed
		and (
			attachment_changed
			or _inverted_attachment_detection_timer > 0.0
		)
	)
	var attachment_surface_qualifies: bool = (
		attachment_detection_open
		and player_up_effective
		and surface_up_norm.length() >= 0.001
		and surface_angle_deg + 0.001 >= attachment_angle_threshold
	)
	var attachment_movement_heading: Vector3 = Vector3.ZERO
	if attachment_surface_qualifies:
		attachment_movement_heading = _get_target_velocity_heading(
			surface_up_norm,
			inverted_attachment_min_movement_speed
		)
	var should_start_attachment_transition: bool = (
		attachment_surface_qualifies
		and attachment_movement_heading.length() >= 0.001
	)
	var attachment_capture_pending: bool = (
		attachment_surface_qualifies
		and not should_start_attachment_transition
	)
	var should_start_detachment_transition: bool = (
		attachment_changed
		and not target_grounded
		and _player_up_was_effective
		and surface_angle_deg + 0.001 >= detachment_angle_threshold
	)
	var should_start_inverted_transition: bool = (
		should_start_attachment_transition
		or should_start_detachment_transition
	)

	_camera_up_target = _compute_camera_up_target()
	var target_up: Vector3 = _camera_up_target
	if target_up.length() < 0.001:
		target_up = gravity_up
	var current_up: Vector3 = _camera_up_current
	if current_up.length() < 0.001:
		_camera_up_current = target_up
		_inverted_up_transition_active = false
		_inverted_up_transition_heading = Vector3.ZERO
		_inverted_attachment_transition_up = Vector3.ZERO
		_inverted_up_transition_frames = 0
		_camera_up_was_grounded = target_grounded
		_player_up_was_effective = player_up_effective
		return
	var current_up_norm: Vector3 = current_up.normalized()
	var target_up_norm: Vector3 = target_up.normalized()

	if not preserve_heading_through_inverted_transitions:
		_inverted_up_transition_active = false
		_inverted_up_transition_heading = Vector3.ZERO
		_inverted_attachment_transition_up = Vector3.ZERO
		_inverted_up_transition_frames = 0
	elif should_start_inverted_transition:
		_inverted_up_transition_active = true
		_inverted_up_transition_is_attachment = should_start_attachment_transition
		_inverted_up_transition_frames = 0
		_inverted_up_transition_control_yaw_origin = _yaw
		if should_start_attachment_transition:
			_inverted_attachment_transition_consumed = true
			_inverted_attachment_transition_up = surface_up_norm
			_capture_inverted_transition_heading(
				_inverted_attachment_transition_up,
				true,
				attachment_movement_heading
			)
		else:
			_inverted_attachment_transition_up = Vector3.ZERO
			_capture_inverted_transition_heading(target_up_norm, true)
	elif attachment_changed:
		_inverted_up_transition_active = false
		_inverted_up_transition_heading = Vector3.ZERO
		_inverted_attachment_transition_up = Vector3.ZERO
		_inverted_up_transition_frames = 0

	if (
		_inverted_up_transition_active
		and _inverted_up_transition_is_attachment
		and _inverted_attachment_transition_up.length() >= 0.001
	):
		target_up_norm = _inverted_attachment_transition_up.normalized()
	elif attachment_capture_pending and preserve_heading_through_inverted_transitions:
		target_up_norm = current_up_norm

	var slerp_speed: float = max(player_up_slerp_speed, 0.0)
	if _inverted_up_transition_active:
		slerp_speed = max(inverted_transition_slerp_speed, 0.0)
	var blend_weight: float = 1.0
	if slerp_speed > 0.0:
		blend_weight = clamp(1.0 - exp(-slerp_speed * delta), 0.0, 1.0)
	var heading_preserved: bool = false
	if _inverted_up_transition_active:
		_transport_inverted_transition_heading_to_up(target_up_norm)
		heading_preserved = _update_heading_preserving_camera_up(target_up_norm, blend_weight)
		_inverted_up_transition_frames += 1
	if not heading_preserved:
		_camera_up_current = _slerp_unit_vector_safe(current_up_norm, target_up_norm, blend_weight)
		_transport_camera_heading_for_up_change(current_up_norm, _camera_up_current)
	if (
		_inverted_up_transition_active
		and _is_inverted_transition_orientation_settled(target_up_norm)
	):
		_inverted_up_transition_active = false
		_inverted_up_transition_heading = Vector3.ZERO
		_inverted_attachment_transition_up = Vector3.ZERO
		_inverted_up_transition_frames = 0

	_camera_up_was_grounded = target_grounded
	_player_up_was_effective = player_up_effective


func _get_camera_up() -> Vector3:
	var up: Vector3 = _camera_up_current
	if up.length() < 0.001:
		return _get_target_gravity_up()
	return up


func _is_target_barrier_blast_active() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_barrier_blast_active"):
		return target.call("is_barrier_blast_active")
	return false


func _get_yaw_from_forward(forward: Vector3, up: Vector3, fallback: float) -> float:
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var flat_forward: Vector3 = forward - up_norm * forward.dot(up_norm)
	if flat_forward.length() < 0.001:
		return fallback
	flat_forward = flat_forward.normalized()
	var base_forward: Vector3 = _get_base_forward_ref(up_norm)
	var base_right: Vector3 = up_norm.cross(base_forward)
	if base_right.length() < 0.001:
		return fallback
	base_right = base_right.normalized()
	return atan2(flat_forward.dot(base_right), flat_forward.dot(base_forward))


func _get_base_forward_ref(up: Vector3) -> Vector3:
	# Keep a stable yaw reference by projecting the previous forward reference onto the new up plane.
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var projected: Vector3 = _base_forward_ref - up_norm * _base_forward_ref.dot(up_norm)
	if projected.length() < 0.001:
		# If the reference is nearly parallel to up, pick a fallback closest to the old reference.
		var candidates: Array = [
			Vector3.FORWARD,
			-Vector3.FORWARD,
			Vector3.RIGHT,
			-Vector3.RIGHT,
			Vector3.UP,
			-Vector3.UP
		]
		var best_dir: Vector3 = Vector3.FORWARD
		var best_dot: float = -1.0
		for axis in candidates:
			var proj: Vector3 = axis - up_norm * axis.dot(up_norm)
			if proj.length() < 0.001:
				continue
			proj = proj.normalized()
			var dot_val: float = proj.dot(_base_forward_ref)
			if dot_val > best_dot:
				best_dot = dot_val
				best_dir = proj
		projected = best_dir
	else:
		projected = projected.normalized()
	_base_forward_ref = projected
	return _base_forward_ref


func _get_speed_fov_facing_weight(up: Vector3) -> float:
	# SUMMARY: Weight the speed FOV boost by how much the camera looks along player movement.
	# STEPS:
	# - Step 1: Fetch camera forward in full 3D.
	# - Step 2: Fetch player movement direction in full 3D.
	# - Step 3: Return the positive alignment in [0..1].
	var cam_forward_world: Vector3 = Vector3.ZERO
	if camera != null:
		cam_forward_world = -camera.global_transform.basis.z
	else:
		var base_forward: Vector3 = _get_base_forward_ref(up)
		if base_forward.length() > 0.001:
			cam_forward_world = base_forward.rotated(up, _yaw)
	if cam_forward_world.length() < 0.001:
		return 1.0
	cam_forward_world = cam_forward_world.normalized()

	var move_dir: Vector3 = Vector3.ZERO
	if target != null:
		var vel_val = target.get("velocity")
		if vel_val is Vector3:
			var vel: Vector3 = vel_val
			if vel.length() > 0.01:
				move_dir = vel.normalized()

	if move_dir.length() < 0.001:
		return 1.0

	var dot_full: float = clamp(cam_forward_world.dot(move_dir), -1.0, 1.0)
	var facing_weight: float = max(dot_full, 0.0)
	return facing_weight


func _reset_auto_follow_state() -> void:
	_clear_auto_follow_pitch_offset()
	_auto_follow_heading = Vector3.ZERO
	_auto_follow_heading_up = _camera_up_current
	_auto_follow_motion_weight = 0.0
	_auto_follow_backward_hold_timer = 0.0
	_auto_follow_backward_turn_active = false
	_auto_follow_backward_turn_sign = 1.0
	_auto_follow_backward_bypass_timer = 0.0


func _clear_auto_follow_pitch_offset() -> void:
	if abs(_auto_follow_pitch_offset) <= 0.0001:
		_auto_follow_pitch_offset = 0.0
		return
	var min_pitch: float = deg_to_rad(min_pitch_deg)
	var max_pitch: float = deg_to_rad(max_pitch_deg)
	_pitch = clamp(_pitch - _auto_follow_pitch_offset, min_pitch, max_pitch)
	_auto_follow_pitch_offset = 0.0


func _smoothstep_auto_follow(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _get_auto_follow_velocity(include_preview: bool = true) -> Vector3:
	if include_preview and _auto_follow_preview_active:
		return _auto_follow_preview_velocity
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if target.has_method("get_camera_auto_follow_velocity"):
		var camera_velocity_value = target.call("get_camera_auto_follow_velocity")
		if camera_velocity_value is Vector3:
			return camera_velocity_value as Vector3
	if target.has_method("get_player_velocity"):
		var method_velocity_value = target.call("get_player_velocity")
		if method_velocity_value is Vector3:
			return method_velocity_value as Vector3
	var property_velocity_value = target.get("velocity")
	if property_velocity_value is Vector3:
		return property_velocity_value as Vector3
	return Vector3.ZERO


func _reset_dolly_tracking(source_position: Vector3, source_velocity: Vector3) -> void:
	_camera_collision_initialized = false
	_dolly_initialized = true
	_dolly_position = source_position
	_dolly_velocity = source_velocity
	_dolly_target_velocity = source_velocity
	_dolly_last_target_position = source_position
	_target_lookahead_current = Vector3.ZERO
	_dolly_target_ref = target
	_dolly_leash_ratio = 0.0
	_dolly_source_velocity = source_velocity
	_target_lookahead_heading = Vector3.ZERO
	_target_lookahead_heading_up = _get_camera_up()
	_target_lookahead_heading_change_timer = 0.0
	_target_lookahead_lateral_weight = 0.0
	_dolly_surface_up = _get_dolly_tracking_up()
	_dolly_was_surface_tracking = dolly_surface_tracking_enabled and _is_target_grounded()
	_dolly_surface_relative_velocity = Vector3.ZERO


func _get_dolly_tracking_up() -> Vector3:
	if dolly_surface_tracking_enabled and _is_target_grounded():
		var surface_up: Vector3 = _get_target_surface_up()
		if surface_up.length_squared() > 0.001:
			return surface_up.normalized()
	return _get_camera_up()


func _transport_dolly_surface_tracking(up: Vector3) -> void:
	var surface_tracking: bool = dolly_surface_tracking_enabled and _is_target_grounded()
	var up_norm: Vector3 = up.normalized()
	if surface_tracking and _dolly_was_surface_tracking and _dolly_surface_up.length_squared() > 0.001:
		var rotation: Basis = Basis(Quaternion(_dolly_surface_up, up_norm))
		_dolly_target_velocity = rotation * _dolly_target_velocity
		_dolly_velocity = rotation * _dolly_velocity
		_dolly_surface_relative_velocity = rotation * _dolly_surface_relative_velocity
		_target_lookahead_current = rotation * _target_lookahead_current
		_dolly_position = target.global_position + rotation * (_dolly_position - _dolly_last_target_position)
	elif surface_tracking:
		_dolly_surface_relative_velocity = Vector3.ZERO
	_dolly_surface_up = up_norm
	_dolly_was_surface_tracking = surface_tracking


func _transport_target_lookahead_heading(up: Vector3) -> void:
	var up_norm: Vector3 = up.normalized()
	if up_norm.length_squared() < 0.001:
		up_norm = _get_target_gravity_up()
	var previous_up: Vector3 = _target_lookahead_heading_up.normalized()
	if previous_up.length_squared() < 0.001:
		previous_up = up_norm
	if _target_lookahead_heading.length_squared() >= 0.001:
		var up_dot: float = clamp(previous_up.dot(up_norm), -1.0, 1.0)
		if up_dot < 0.999999:
			var rotation_axis: Vector3 = previous_up.cross(up_norm)
			if rotation_axis.length_squared() >= 0.001:
				_target_lookahead_heading = Basis(rotation_axis.normalized(), acos(up_dot)) * _target_lookahead_heading
			elif up_dot < -0.999999:
				_target_lookahead_heading = Vector3.ZERO
		_target_lookahead_heading = _target_lookahead_heading.slide(up_norm)
		if _target_lookahead_heading.length_squared() >= 0.001:
			_target_lookahead_heading = _target_lookahead_heading.normalized()
		else:
			_target_lookahead_heading = Vector3.ZERO
	_target_lookahead_heading_up = up_norm


func _update_target_lookahead_heading(delta: float, up: Vector3, raw_heading: Vector3) -> float:
	_transport_target_lookahead_heading(up)
	if raw_heading.length_squared() < 0.001:
		_target_lookahead_heading_change_timer = 0.0
		return 0.0
	var up_norm: Vector3 = _target_lookahead_heading_up
	var desired_heading: Vector3 = raw_heading.slide(up_norm)
	if desired_heading.length_squared() < 0.001:
		return 0.0
	desired_heading = desired_heading.normalized()
	if _target_lookahead_heading.length_squared() < 0.001:
		_target_lookahead_heading = desired_heading
		return 0.0

	var signed_error: float = _target_lookahead_heading.signed_angle_to(desired_heading, up_norm)
	var deviation: float = abs(signed_error)
	var drift_blend: float = clamp(_drift_camera_blend, 0.0, 1.0)
	var deadzone_degrees: float = clamp(lerp(
		target_lookahead_heading_deadzone_deg,
		drift_lookahead_heading_deadzone_deg,
		drift_blend
	), 0.0, 45.0)
	var full_response_degrees: float = max(
		clamp(lerp(
			target_lookahead_heading_full_response_deg,
			drift_lookahead_heading_full_response_deg,
			drift_blend
		), 0.0, 90.0),
		deadzone_degrees + 0.01
	)
	var deadzone: float = deg_to_rad(deadzone_degrees)
	var full_response: float = deg_to_rad(full_response_degrees)
	full_response = max(full_response, deadzone + 0.0001)
	if deviation <= deadzone:
		_target_lookahead_heading_change_timer = 0.0
		return 0.0

	_target_lookahead_heading_change_timer += max(delta, 0.0)
	var persistence_duration: float = max(lerp(
		target_lookahead_heading_persistence,
		drift_lookahead_heading_persistence,
		drift_blend
	), 0.0)
	var persistence_weight: float = 1.0
	if persistence_duration > 0.0:
		persistence_weight = smoothstep(
			0.0,
			persistence_duration,
			_target_lookahead_heading_change_timer
		)
	var deviation_weight: float = smoothstep(deadzone, full_response, deviation)
	var sharp_response_angle: float = min(max(full_response * 2.5, full_response + 0.0001), PI)
	var sharp_weight: float = smoothstep(full_response, sharp_response_angle, deviation)
	var turn_weight: float = deviation_weight * lerp(persistence_weight, 1.0, sharp_weight)
	if turn_weight <= 0.0001 or delta <= 0.0:
		return turn_weight

	var smoothing: float = max(lerp(
		target_lookahead_heading_smoothing,
		drift_lookahead_heading_smoothing,
		drift_blend
	), 0.0)
	var rotation_step: float = signed_error
	if smoothing > 0.0:
		var heading_blend: float = clamp(1.0 - exp(-smoothing * delta), 0.0, 1.0)
		rotation_step *= heading_blend * turn_weight
	else:
		rotation_step *= turn_weight
	var maximum_turn_rate: float = deg_to_rad(max(lerp(
		target_lookahead_heading_max_turn_rate_deg,
		drift_lookahead_heading_max_turn_rate_deg,
		drift_blend
	), 0.0))
	if maximum_turn_rate > 0.0:
		rotation_step = clamp(rotation_step, -maximum_turn_rate * delta, maximum_turn_rate * delta)
	_target_lookahead_heading = _target_lookahead_heading.rotated(up_norm, rotation_step).normalized()
	return turn_weight


func _update_target_lookahead(delta: float, up: Vector3) -> Vector3:
	var desired_offset: Vector3 = Vector3.ZERO
	var up_norm: Vector3 = up.normalized()
	if up_norm.length_squared() < 0.001:
		up_norm = _get_target_gravity_up()
	var vertical_velocity: Vector3 = up_norm * _dolly_target_velocity.dot(up_norm)
	var planar_velocity: Vector3 = _dolly_target_velocity - vertical_velocity
	var raw_heading: Vector3 = planar_velocity.normalized() if planar_velocity.length_squared() >= 0.001 else Vector3.ZERO
	var drift_blend: float = clamp(_drift_camera_blend, 0.0, 1.0)
	var drift_heading: Vector3 = _drift_heading_dir.slide(up_norm)
	if drift_blend > 0.001 and drift_heading.length_squared() >= 0.001:
		drift_heading = drift_heading.normalized().rotated(up_norm, _drift_turn_yaw_offset_current)
		if raw_heading.length_squared() >= 0.001:
			raw_heading = raw_heading.slerp(drift_heading, drift_blend).normalized()
		else:
			raw_heading = drift_heading
	var turn_weight: float = _update_target_lookahead_heading(delta, up_norm, raw_heading)
	var lateral_strength: float = lerp(
		target_lookahead_lateral_strength,
		drift_lookahead_lateral_strength,
		drift_blend
	)
	var desired_lateral_weight: float = clamp(lateral_strength, 0.0, 1.0) * turn_weight
	var lateral_smoothing: float = max(target_lookahead_lateral_engage_smoothing, 0.0)
	if desired_lateral_weight < _target_lookahead_lateral_weight:
		lateral_smoothing = max(target_lookahead_lateral_release_smoothing, 0.0)
	if lateral_smoothing <= 0.0 or delta <= 0.0:
		_target_lookahead_lateral_weight = desired_lateral_weight
	else:
		var lateral_blend: float = clamp(1.0 - exp(-lateral_smoothing * delta), 0.0, 1.0)
		_target_lookahead_lateral_weight = lerp(
			_target_lookahead_lateral_weight,
			desired_lateral_weight,
			lateral_blend
		)

	if target_lookahead_enabled and target_lookahead_strength > 0.001:
		var lookahead_heading: Vector3 = _target_lookahead_heading
		if lookahead_heading.length_squared() < 0.001:
			lookahead_heading = raw_heading
		var longitudinal_speed: float = max(planar_velocity.dot(lookahead_heading), 0.0)
		var lateral_velocity: Vector3 = planar_velocity - lookahead_heading * planar_velocity.dot(lookahead_heading)
		var lookahead_velocity: Vector3 = (
			lookahead_heading * longitudinal_speed
			+ lateral_velocity * _target_lookahead_lateral_weight
			+ vertical_velocity * clamp(target_lookahead_vertical_scale, 0.0, 1.0)
		)
		var speed: float = lookahead_velocity.length()
		var minimum_speed: float = max(target_lookahead_min_speed, 0.0)
		var full_speed: float = max(target_lookahead_full_speed, minimum_speed + 0.001)
		var speed_weight: float = smoothstep(minimum_speed, full_speed, speed)
		var lookahead_time_multiplier: float = lerp(
			1.0,
			max(drift_lookahead_time_multiplier, 0.0),
			drift_blend
		)
		desired_offset = lookahead_velocity * max(target_lookahead_time, 0.0) * lookahead_time_multiplier
		desired_offset = desired_offset.limit_length(max(target_lookahead_max_distance, 0.0))
		desired_offset *= speed_weight * clamp(target_lookahead_strength, 0.0, 1.0)

	var smoothing: float = max(target_lookahead_smoothing, 0.0)
	if desired_offset.length_squared() < _target_lookahead_current.length_squared():
		smoothing = max(target_lookahead_release_smoothing, smoothing)
	if smoothing <= 0.0 or delta <= 0.0:
		_target_lookahead_current = desired_offset
	else:
		var blend: float = clamp(1.0 - exp(-smoothing * delta), 0.0, 1.0)
		_target_lookahead_current = _target_lookahead_current.lerp(desired_offset, blend)
	return _target_lookahead_current


func _get_dolly_response(error_ratio: float) -> float:
	var response: float = max(follow_smooth, 0.0)
	if drift_follow_enabled and _drift_camera_blend > 0.001:
		var drift_response: float = max(drift_follow_smooth, 0.0)
		if response <= 0.0:
			response = drift_response
		else:
			response = lerp(response, drift_response, _drift_camera_blend)
	var catchup_start: float = clamp(dolly_catchup_start, 0.0, 1.0)
	var catchup_weight: float = 0.0
	if catchup_start < 0.9999:
		catchup_weight = smoothstep(catchup_start, 1.0, clamp(error_ratio, 0.0, 1.0))
	elif error_ratio >= 1.0:
		catchup_weight = 1.0
	return response * lerp(1.0, max(dolly_catchup_multiplier, 1.0), catchup_weight)


func _apply_dolly_leash(
	source_position: Vector3,
	source_velocity: Vector3,
	up: Vector3
) -> void:
	var up_norm: Vector3 = up.normalized()
	if up_norm.length_squared() < 0.001:
		up_norm = _get_target_gravity_up()
	var heading: Vector3 = source_velocity.slide(up_norm)
	if heading.length_squared() < 0.001:
		heading = _get_camera_flat_heading(up_norm)
	if heading.length_squared() < 0.001:
		heading = up_norm.cross(Vector3.RIGHT)
	if heading.length_squared() < 0.001:
		heading = up_norm.cross(Vector3.FORWARD)
	heading = heading.normalized()
	var lateral: Vector3 = up_norm.cross(heading).normalized()
	var offset: Vector3 = _dolly_position - source_position
	var along_amount: float = offset.dot(heading)
	var lateral_amount: float = offset.dot(lateral)
	var vertical_amount: float = offset.dot(up_norm)
	var lag_limit: float = max(dolly_max_lag_distance, 0.001)
	var lookahead_minimum_speed: float = max(target_lookahead_min_speed, 0.0)
	var lookahead_full_speed: float = max(target_lookahead_full_speed, lookahead_minimum_speed + 0.001)
	var lookahead_motion_weight: float = smoothstep(
		lookahead_minimum_speed,
		lookahead_full_speed,
		source_velocity.length()
	)
	var lookahead_lead: float = max(_target_lookahead_current.dot(heading), 0.0) * lookahead_motion_weight
	var lead_limit: float = max(max(dolly_max_lead_distance, lookahead_lead + 0.1), 0.001)
	var lateral_leash_multiplier: float = lerp(
		1.0,
		max(drift_lateral_leash_multiplier, 0.1),
		clamp(_drift_camera_blend, 0.0, 1.0)
	)
	var lateral_limit: float = max(dolly_max_lateral_distance * lateral_leash_multiplier, 0.001)
	var vertical_limit: float = max(dolly_max_vertical_distance, 0.001)
	var clamped_along: float = clamp(along_amount, -lag_limit, lead_limit)
	var clamped_lateral: float = clamp(lateral_amount, -lateral_limit, lateral_limit)
	var clamped_vertical: float = clamp(vertical_amount, -vertical_limit, vertical_limit)
	if (
		abs(clamped_along - along_amount) > 0.0001
		or abs(clamped_lateral - lateral_amount) > 0.0001
		or abs(clamped_vertical - vertical_amount) > 0.0001
	):
		_dolly_position = (
			source_position
			+ heading * clamped_along
			+ lateral * clamped_lateral
			+ up_norm * clamped_vertical
		)
		var relative_velocity: Vector3 = _dolly_velocity - source_velocity
		var along_velocity: float = relative_velocity.dot(heading)
		var lateral_velocity: float = relative_velocity.dot(lateral)
		var vertical_velocity: float = relative_velocity.dot(up_norm)
		if (clamped_along <= -lag_limit + 0.0001 and along_velocity < 0.0) or (clamped_along >= lead_limit - 0.0001 and along_velocity > 0.0):
			_dolly_velocity -= heading * along_velocity
		if abs(clamped_lateral) >= lateral_limit - 0.0001 and sign(lateral_velocity) == sign(clamped_lateral):
			_dolly_velocity -= lateral * lateral_velocity
		if abs(clamped_vertical) >= vertical_limit - 0.0001 and sign(vertical_velocity) == sign(clamped_vertical):
			_dolly_velocity -= up_norm * vertical_velocity


func _update_dolly_follow(delta: float, up: Vector3) -> Vector3:
	var source_position: Vector3 = target.global_position
	var reported_velocity: Vector3 = _get_auto_follow_velocity(false)
	if not _dolly_initialized or _dolly_target_ref != target:
		_reset_dolly_tracking(source_position, reported_velocity)

	var dt: float = max(delta, 0.0)
	var displacement: Vector3 = source_position - _dolly_last_target_position
	var measured_velocity: Vector3 = reported_velocity
	if dt > 0.00001 and displacement.length_squared() > 0.000001:
		measured_velocity = displacement / dt
	var expected_distance: float = max(reported_velocity.length(), _dolly_target_velocity.length()) * dt
	var discontinuity_limit: float = max(
		8.0,
		expected_distance * 3.0 + max(dolly_max_lag_distance, dolly_max_lead_distance) * 2.0
	)
	if displacement.length() > discontinuity_limit:
		_reset_dolly_tracking(source_position, reported_velocity)
		measured_velocity = reported_velocity
	_transport_dolly_surface_tracking(up)
	if dolly_surface_tracking_enabled and _is_target_grounded() and target.has_method("get_camera_tracking_velocity"):
		var tracking_velocity_value: Variant = target.call("get_camera_tracking_velocity")
		if tracking_velocity_value is Vector3:
			measured_velocity = tracking_velocity_value as Vector3
	_dolly_last_target_position = source_position
	_dolly_source_velocity = measured_velocity

	var velocity_smoothing: float = max(lerp(
		dolly_velocity_smoothing,
		drift_velocity_smoothing,
		clamp(_drift_camera_blend, 0.0, 1.0)
	), 0.0)
	if velocity_smoothing <= 0.0 or dt <= 0.0:
		_dolly_target_velocity = measured_velocity
	else:
		var velocity_blend: float = clamp(1.0 - exp(-velocity_smoothing * dt), 0.0, 1.0)
		_dolly_target_velocity = _dolly_target_velocity.lerp(measured_velocity, velocity_blend)

	if _teleport_snap_timer > 0.0:
		_reset_dolly_tracking(source_position, reported_velocity)
		return source_position

	var previous_lookahead: Vector3 = _target_lookahead_current
	var lookahead: Vector3 = _update_target_lookahead(dt, up)
	var tracking_position: Vector3 = source_position + lookahead
	var tracking_velocity: Vector3 = _dolly_target_velocity
	if dt > 0.00001:
		tracking_velocity += (lookahead - previous_lookahead) / dt

	if not dolly_follow_enabled or not smooth_follow or follow_smooth <= 0.0:
		_dolly_position = tracking_position
		_dolly_velocity = tracking_velocity
		_apply_dolly_leash(source_position, _dolly_source_velocity, up)
		_dolly_surface_relative_velocity = _dolly_velocity - _dolly_source_velocity
		_dolly_leash_ratio = 0.0
		return _dolly_position

	var response: float = _get_dolly_response(_dolly_leash_ratio)
	if response <= 0.0 or dt <= 0.0:
		_dolly_position = tracking_position
		_dolly_velocity = tracking_velocity
		_dolly_surface_relative_velocity = _dolly_velocity - _dolly_source_velocity
		return _dolly_position

	var damping: float = max(dolly_damping_ratio, 0.1)
	var stiffness: float = response * response
	var damping_coefficient: float = 2.0 * damping * response
	var denominator: float = 1.0 + dt * damping_coefficient + dt * dt * stiffness
	var surface_tracking: bool = dolly_surface_tracking_enabled and _is_target_grounded()
	var spring_velocity: Vector3 = _dolly_velocity
	var spring_target_velocity: Vector3 = tracking_velocity
	if surface_tracking:
		spring_velocity = _dolly_surface_relative_velocity
		spring_target_velocity = (lookahead - previous_lookahead) / dt
	var integrated_velocity: Vector3 = (
		spring_velocity
		+ dt * stiffness * (tracking_position - _dolly_position)
		+ dt * damping_coefficient * spring_target_velocity
	) / denominator
	_dolly_velocity = integrated_velocity + _dolly_source_velocity if surface_tracking else integrated_velocity
	_dolly_position += integrated_velocity * dt
	_apply_dolly_leash(source_position, _dolly_source_velocity, up)
	_dolly_surface_relative_velocity = _dolly_velocity - _dolly_source_velocity
	var catchup_distance: float = max(
		min(dolly_max_lag_distance, min(dolly_max_lateral_distance, dolly_max_vertical_distance)),
		0.001
	)
	_dolly_leash_ratio = (tracking_position - _dolly_position).length() / catchup_distance
	return _dolly_position


func _is_auto_follow_direction_locked() -> bool:
	if _auto_follow_preview_active or target == null or not is_instance_valid(target):
		return false
	if not target.has_method("is_camera_auto_follow_direction_locked"):
		return false
	var locked_value = target.call("is_camera_auto_follow_direction_locked")
	return locked_value is bool and bool(locked_value)


func _transport_auto_follow_heading(up: Vector3) -> void:
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var previous_up: Vector3 = _auto_follow_heading_up.normalized()
	if previous_up.length() < 0.001:
		previous_up = up_norm

	if _auto_follow_heading.length() >= 0.001:
		var up_dot: float = clamp(previous_up.dot(up_norm), -1.0, 1.0)
		if up_dot < 0.999999:
			var rotation_axis: Vector3 = previous_up.cross(up_norm)
			if rotation_axis.length() >= 0.001:
				rotation_axis = rotation_axis.normalized()
				_auto_follow_heading = Basis(rotation_axis, acos(up_dot)) * _auto_follow_heading
			elif up_dot < -0.999999:
				_auto_follow_heading = Vector3.ZERO

		_auto_follow_heading -= up_norm * _auto_follow_heading.dot(up_norm)
		if _auto_follow_heading.length() >= 0.001:
			_auto_follow_heading = _auto_follow_heading.normalized()
		else:
			_auto_follow_heading = Vector3.ZERO
	_auto_follow_heading_up = up_norm


func _update_auto_follow_heading(raw_heading: Vector3, up: Vector3, speed_weight: float, delta: float) -> Vector3:
	_transport_auto_follow_heading(up)
	if raw_heading.length() < 0.001:
		return _auto_follow_heading
	var up_norm: Vector3 = _auto_follow_heading_up
	var desired_heading: Vector3 = raw_heading - up_norm * raw_heading.dot(up_norm)
	if desired_heading.length() < 0.001:
		return _auto_follow_heading
	desired_heading = desired_heading.normalized()
	if _auto_follow_heading.length() < 0.001:
		_auto_follow_heading = desired_heading
		return _auto_follow_heading

	var smoothing_min: float = max(auto_follow_heading_smoothing_min, 0.0)
	var smoothing_max: float = max(auto_follow_heading_smoothing_max, smoothing_min)
	var smoothing: float = lerp(smoothing_min, smoothing_max, clamp(speed_weight, 0.0, 1.0))
	if smoothing <= 0.0:
		_auto_follow_heading = desired_heading
		return _auto_follow_heading

	var base_forward: Vector3 = _get_base_forward_ref(up_norm)
	var current_yaw: float = _get_yaw_from_forward(_auto_follow_heading, up_norm, _yaw)
	var desired_yaw: float = _get_yaw_from_forward(desired_heading, up_norm, current_yaw)
	var blend_weight: float = clamp(1.0 - exp(-smoothing * delta), 0.0, 1.0)
	var heading_error: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	if _auto_follow_backward_turn_active:
		var turn_sign: float = _auto_follow_backward_turn_sign
		if is_zero_approx(turn_sign):
			turn_sign = 1.0
		if abs(heading_error) >= PI - 0.001:
			heading_error = PI * turn_sign
		elif sign(heading_error) != turn_sign and abs(heading_error) > PI * 0.5:
			heading_error = turn_sign * (TAU - abs(heading_error))
	var filtered_yaw: float = current_yaw + heading_error * blend_weight
	_auto_follow_heading = base_forward.rotated(up_norm, filtered_yaw).normalized()
	return _auto_follow_heading


func _update_auto_follow_motion_weight(target_weight: float, delta: float) -> void:
	var clamped_target: float = clamp(target_weight, 0.0, 1.0)
	var smoothing: float = auto_follow_engage_smoothing
	if clamped_target < _auto_follow_motion_weight:
		smoothing = auto_follow_release_smoothing
	smoothing = max(smoothing, 0.0)
	if smoothing <= 0.0:
		_auto_follow_motion_weight = clamped_target
		return
	var blend_weight: float = clamp(1.0 - exp(-smoothing * delta), 0.0, 1.0)
	_auto_follow_motion_weight = lerp(_auto_follow_motion_weight, clamped_target, blend_weight)


func _get_auto_follow_slope_factor(move_direction: Vector3) -> float:
	var suppression: float = clamp(auto_follow_slope_suppression, 0.0, 1.0)
	if suppression <= 0.0 or not target or not is_instance_valid(target):
		return 1.0
	if not target.has_method("get_up_vector"):
		return 1.0

	var player_up_value = target.call("get_up_vector")
	if not (player_up_value is Vector3):
		return 1.0
	var player_up: Vector3 = (player_up_value as Vector3).normalized()
	if player_up.length() < 0.001:
		return 1.0
	var gravity_up: Vector3 = _get_target_gravity_up()
	var tilt: float = acos(clamp(player_up.dot(gravity_up), -1.0, 1.0))
	var slope_threshold: float = deg_to_rad(clamp(auto_follow_slope_threshold_deg, 0.0, 90.0))
	if tilt <= slope_threshold:
		return 1.0

	var slope_up: Vector3 = gravity_up - player_up * gravity_up.dot(player_up)
	if slope_up.length() < 0.001:
		return 1.0
	slope_up = slope_up.normalized()
	var slope_alignment: float = max(move_direction.dot(slope_up), 0.0)
	return 1.0 - slope_alignment * slope_alignment * suppression


func _update_auto_follow_pitch(
	delta: float,
	up: Vector3,
	velocity: Vector3,
	has_control: bool,
	motion_weight: float
) -> void:
	var min_pitch: float = deg_to_rad(min_pitch_deg)
	var max_pitch: float = deg_to_rad(max_pitch_deg)
	var max_tilt: float = deg_to_rad(clamp(auto_follow_vertical_max_tilt_deg, 0.0, 90.0))
	var base_pitch: float = _pitch - _auto_follow_pitch_offset
	var desired_movement_tilt: float = 0.0
	var total_speed: float = velocity.length()
	if auto_follow_vertical_enabled and has_control and total_speed > 0.001:
		var up_norm: Vector3 = up.normalized()
		if up_norm.length() < 0.001:
			up_norm = _get_target_gravity_up()
		var follow_strength: float = clamp(motion_weight, 0.0, 1.0)
		var level_pitch: float = clamp(deg_to_rad(auto_follow_level_pitch_deg), min_pitch, max_pitch)
		var vertical_ratio: float = clamp(velocity.dot(up_norm) / total_speed, -1.0, 1.0)
		var level_response: float = max(auto_follow_sensitivity, 0.0) * follow_strength
		if level_response > 0.0:
			var level_blend: float = clamp(1.0 - exp(-level_response * delta), 0.0, 1.0)
			base_pitch = clamp(lerp(base_pitch, level_pitch, level_blend), min_pitch, max_pitch)
		desired_movement_tilt = -max_tilt * vertical_ratio * follow_strength

	var response: float = max(auto_follow_sensitivity, 0.0)
	if abs(desired_movement_tilt) < abs(_auto_follow_pitch_offset):
		response = max(response, auto_follow_release_smoothing)
	if response <= 0.0:
		_pitch = clamp(base_pitch + _auto_follow_pitch_offset, min_pitch, max_pitch)
		return
	response *= lerp(0.35, 1.0, clamp(motion_weight, 0.0, 1.0))
	var blend_weight: float = clamp(1.0 - exp(-response * delta), 0.0, 1.0)
	var next_offset: float = lerp(_auto_follow_pitch_offset, desired_movement_tilt, blend_weight)
	_pitch = clamp(base_pitch + next_offset, min_pitch, max_pitch)
	_auto_follow_pitch_offset = _pitch - base_pitch


func _update_auto_follow(delta: float, up: Vector3, constraint_active: bool) -> void:
	var dt: float = max(delta, 0.0)
	_auto_follow_backward_bypass_timer = max(_auto_follow_backward_bypass_timer - dt, 0.0)
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var has_motion_source: bool = _auto_follow_preview_active or (target and is_instance_valid(target))
	var raw_velocity: Vector3 = _get_auto_follow_velocity() if has_motion_source else Vector3.ZERO
	var wall_kick_bypass_available: bool = (
		_auto_follow_backward_bypass_timer > 0.0
		and _camera_look_strength < parkour_wall_kick_assist_cancel_stick_strength
		and _camera_mouse_strength < override_cancel_mouse_threshold
	)
	var controls_available: bool = (
		has_motion_source
		and not constraint_active
		and (not _camera_follow_disabled() or _manual_input_lock_allows_auto_follow)
		and (_auto_follow_interrupt_timer <= 0.0 or wall_kick_bypass_available)
		and not _inverted_up_transition_active
	)
	var controller_gate_open: bool = (
		not SettingsManager.camera_auto_follow_controller_only
		or SettingsManager.is_controller_input_active()
		or _auto_follow_preview_active
	)
	var auto_follow_available: bool = controls_available and controller_gate_open

	var planar_velocity: Vector3 = raw_velocity - up_norm * raw_velocity.dot(up_norm)
	var planar_speed: float = planar_velocity.length()
	var total_speed: float = raw_velocity.length()
	var minimum_speed: float = max(auto_follow_min_speed, 0.0)
	var shared_speed_weight: float = 0.0
	if total_speed > minimum_speed:
		if auto_follow_speed_ramp <= 0.0:
			shared_speed_weight = 1.0
		else:
			var full_speed: float = max(auto_follow_speed_ramp, minimum_speed + 0.001)
			shared_speed_weight = _smoothstep_auto_follow((total_speed - minimum_speed) / (full_speed - minimum_speed))
	var direction_locked: bool = _is_auto_follow_direction_locked()
	if direction_locked and total_speed > minimum_speed:
		shared_speed_weight = max(shared_speed_weight, AUTO_FOLLOW_LOCKED_MOTION_FLOOR)

	_update_auto_follow_pitch(
		dt,
		up_norm,
		raw_velocity,
		auto_follow_enabled and auto_follow_available,
		shared_speed_weight
	)

	var planar_confidence_weight: float = 0.0
	if total_speed > 0.001:
		var planar_ratio: float = clamp(planar_speed / total_speed, 0.0, 1.0)
		var full_confidence: float = clamp(auto_follow_planar_confidence, 0.0, 1.0)
		planar_confidence_weight = 1.0 if full_confidence <= 0.001 else _smoothstep_auto_follow(planar_ratio / full_confidence)
	var yaw_motion_weight: float = shared_speed_weight * planar_confidence_weight

	var raw_heading: Vector3 = Vector3.ZERO
	if planar_speed > 0.001:
		raw_heading = planar_velocity / planar_speed
	var camera_heading: Vector3 = _get_camera_flat_heading(up_norm)
	var raw_heading_deviation: float = 0.0
	if raw_heading.length_squared() >= 0.001 and camera_heading.length_squared() >= 0.001:
		raw_heading_deviation = abs(camera_heading.signed_angle_to(raw_heading, up_norm))
	var backward_intent_half_angle: float = clamp(auto_follow_backward_intent_cone_deg, 0.0, 90.0)
	var backward_entry_angle: float = PI - deg_to_rad(backward_intent_half_angle)
	var backward_release_angle: float = deg_to_rad(clamp(auto_follow_backward_release_deg, 0.0, 180.0))
	var backward_entry_active: bool = (
		backward_intent_half_angle > 0.0
		and raw_heading.length_squared() >= 0.001
		and raw_heading_deviation >= backward_entry_angle
	)
	if not auto_follow_enabled or not auto_follow_available or yaw_motion_weight <= 0.0:
		_auto_follow_backward_hold_timer = 0.0
		_auto_follow_backward_turn_active = false
	elif _auto_follow_backward_turn_active:
		if raw_heading_deviation <= backward_release_angle:
			_auto_follow_backward_turn_active = false
			_auto_follow_backward_hold_timer = 0.0
	elif backward_entry_active:
		var slow_hold: float = max(auto_follow_backward_slow_hold_duration, 0.0)
		var fast_hold: float = max(auto_follow_backward_fast_hold_duration, 0.0)
		var backward_hold_duration: float = lerp(slow_hold, fast_hold, shared_speed_weight)
		_auto_follow_backward_hold_timer += dt
		if (
			direction_locked
			or _auto_follow_backward_bypass_timer > 0.0
			or _auto_follow_backward_hold_timer >= backward_hold_duration
		):
			_auto_follow_backward_turn_active = true
			var signed_reversal: float = camera_heading.signed_angle_to(raw_heading, up_norm)
			if abs(signed_reversal) < PI - 0.001:
				_auto_follow_backward_turn_sign = sign(signed_reversal)
			if is_zero_approx(_auto_follow_backward_turn_sign):
				_auto_follow_backward_turn_sign = 1.0
			_auto_follow_heading = camera_heading
	else:
		_auto_follow_backward_hold_timer = 0.0
	if backward_entry_active and not _auto_follow_backward_turn_active:
		_transport_auto_follow_heading(up_norm)
		_update_auto_follow_motion_weight(0.0, dt)
		return
	var filtered_heading: Vector3 = _update_auto_follow_heading(raw_heading, up_norm, yaw_motion_weight, dt)
	var target_motion_weight: float = 0.0
	if auto_follow_enabled and auto_follow_available and filtered_heading.length() >= 0.001:
		var slope_factor: float = _get_auto_follow_slope_factor(filtered_heading)
		target_motion_weight = yaw_motion_weight * slope_factor
	_update_auto_follow_motion_weight(target_motion_weight, dt)
	if not auto_follow_enabled or not auto_follow_available or yaw_motion_weight <= 0.0:
		return
	if _auto_follow_motion_weight <= 0.0001 or filtered_heading.length() < 0.001:
		return

	var desired_yaw: float = _get_yaw_from_forward(filtered_heading, up_norm, _yaw)
	var yaw_error: float = wrapf(desired_yaw - _yaw, -PI, PI)
	if _auto_follow_backward_turn_active and abs(yaw_error) >= PI - 0.001:
		yaw_error = PI * _auto_follow_backward_turn_sign
	var deviation: float = abs(yaw_error)
	var deadzone_deg: float = clamp(auto_follow_deadzone_deg, 0.0, 180.0)
	var configured_deadzone: float = deg_to_rad(deadzone_deg)
	var effective_deadzone: float = configured_deadzone * (1.0 - clamp(yaw_motion_weight, 0.0, 1.0))
	if deviation <= effective_deadzone:
		return
	var max_deviation: float = deg_to_rad(clamp(auto_follow_max_deviation_deg, deadzone_deg, 180.0))
	var angle_weight: float = 1.0
	if max_deviation > effective_deadzone + 0.0001:
		angle_weight = _smoothstep_auto_follow(
			(deviation - effective_deadzone) / (max_deviation - effective_deadzone)
		)
	var micro_strength: float = clamp(auto_follow_high_speed_micro_strength, 0.0, 1.0)
	var micro_follow_floor: float = micro_strength * clamp(yaw_motion_weight, 0.0, 1.0)
	angle_weight = max(angle_weight, micro_follow_floor)

	var camera_right: Vector3 = up_norm.cross(camera_heading)
	var departure_speed: float = abs(planar_velocity.dot(camera_right.normalized())) if camera_right.length() >= 0.001 else 0.0
	var departure_weight: float = 1.0
	if auto_follow_departure_speed_ramp > 0.0:
		departure_weight = _smoothstep_auto_follow(departure_speed / auto_follow_departure_speed_ramp)
	var departure_response: float = lerp(0.35, 1.0, departure_weight)
	var follow_rate: float = max(auto_follow_sensitivity, 0.0) * _auto_follow_motion_weight * angle_weight * departure_response
	if _auto_follow_backward_turn_active:
		follow_rate *= clamp(auto_follow_backward_response_scale, 0.1, 1.0)
	if follow_rate <= 0.0:
		return

	var response_weight: float = clamp(1.0 - exp(-follow_rate * dt), 0.0, 1.0)
	var yaw_step: float = yaw_error * response_weight
	var max_turn_rate: float = deg_to_rad(max(auto_follow_max_turn_rate_deg, 0.0))
	if _auto_follow_backward_turn_active:
		var backward_turn_rate: float = deg_to_rad(max(auto_follow_backward_max_turn_rate_deg, 0.0))
		if max_turn_rate <= 0.0:
			max_turn_rate = backward_turn_rate
		elif backward_turn_rate > 0.0:
			max_turn_rate = min(max_turn_rate, backward_turn_rate)
	if max_turn_rate > 0.0:
		yaw_step = clamp(yaw_step, -max_turn_rate * dt, max_turn_rate * dt)
	_yaw = wrapf(_yaw + yaw_step, -PI, PI)


func request_parkour_wall_kick_assist(
	launch_velocity: Vector3,
	outward_speed: float,
	kick_strength: float
) -> void:
	if not parkour_camera_enabled or not parkour_wall_kick_assist_enabled:
		return
	if not SettingsManager.is_controller_input_active():
		return
	var up: Vector3 = _get_target_gravity_up()
	var launch_heading: Vector3 = launch_velocity.slide(up)
	if launch_heading.length_squared() < 0.001:
		return
	launch_heading = launch_heading.normalized()
	var minimum_speed: float = max(parkour_wall_kick_assist_min_speed, 0.0)
	var full_speed: float = max(parkour_wall_kick_assist_full_speed, minimum_speed + 0.001)
	var speed_weight: float = smoothstep(
		minimum_speed,
		full_speed,
		max(outward_speed, 0.0)
	)
	if speed_weight <= 0.001:
		return
	var desired_yaw: float = _get_yaw_from_forward(launch_heading, up, _yaw)
	var yaw_error: float = wrapf(desired_yaw - _yaw, -PI, PI)
	var yaw_error_degrees: float = abs(rad_to_deg(yaw_error))
	if yaw_error_degrees <= 0.1:
		return
	var angle_weight: float = lerp(
		0.45,
		1.0,
		smoothstep(0.0, 90.0, min(yaw_error_degrees, 90.0))
	)
	var backward_fade_start: float = clamp(
		parkour_wall_kick_assist_backward_fade_deg,
		90.0,
		179.0
	)
	var backward_weight: float = lerp(
		1.0,
		clamp(parkour_wall_kick_assist_backward_min_strength, 0.0, 1.0),
		smoothstep(backward_fade_start, 179.0, yaw_error_degrees)
	)
	var strength_weight: float = lerp(0.35, 1.0, clamp(kick_strength, 0.0, 1.0))
	var context_weight: float = speed_weight * angle_weight * backward_weight * strength_weight
	_auto_follow_backward_bypass_timer = max(
		_auto_follow_backward_bypass_timer,
		max(parkour_wall_kick_backward_bypass_duration, 0.0) * speed_weight
	)
	var wall_kick_turn_sign: float = sign(yaw_error)
	if not is_zero_approx(wall_kick_turn_sign):
		_auto_follow_backward_turn_sign = wall_kick_turn_sign
	var maximum_correction: float = deg_to_rad(
		max(parkour_wall_kick_assist_max_yaw_deg, 0.0) * context_weight
	)
	if maximum_correction <= 0.0001:
		return
	_parkour_wall_kick_assist_target_yaw = wrapf(
		_yaw + clamp(yaw_error, -maximum_correction, maximum_correction),
		-PI,
		PI
	)
	_parkour_wall_kick_assist_elapsed = 0.0
	_parkour_wall_kick_assist_runtime_duration = max(
		parkour_wall_kick_assist_duration * lerp(0.65, 1.0, context_weight),
		0.0
	)
	_parkour_wall_kick_assist_active = _parkour_wall_kick_assist_runtime_duration > 0.0


func _update_parkour_camera(delta: float, up: Vector3, constraint_active: bool) -> void:
	var dt: float = max(delta, 0.0)
	_update_parkour_wall_kick_assist(dt, constraint_active)
	var target_pan: Vector3 = Vector3.ZERO
	if parkour_camera_enabled and not constraint_active:
		var adjustment_state: Dictionary = _get_target_camera_action_adjustment_state()
		if adjustment_state.get("type", &"") == &"parkour_wall_run":
			var open_direction: Vector3 = adjustment_state.get("open_direction", Vector3.ZERO)
			open_direction = open_direction.slide(up)
			if open_direction.length_squared() >= 0.001:
				open_direction = open_direction.normalized()
				var camera_heading: Vector3 = _get_camera_flat_heading(up)
				var camera_right: Vector3 = up.cross(camera_heading).normalized()
				var lateral_amount: float = clamp(open_direction.dot(camera_right), -1.0, 1.0)
				var wall_run_speed: float = max(float(adjustment_state.get("speed", 0.0)), 0.0)
				var minimum_speed: float = max(parkour_wall_run_pan_min_speed, 0.0)
				var full_speed: float = max(parkour_wall_run_pan_full_speed, minimum_speed + 0.001)
				var speed_weight: float = lerp(
					clamp(parkour_wall_run_pan_min_strength, 0.0, 1.0),
					1.0,
					smoothstep(minimum_speed, full_speed, wall_run_speed)
				)
				target_pan = (
					camera_right
					* lateral_amount
					* max(parkour_wall_run_pan_distance, 0.0)
					* speed_weight
				)
	var smoothing: float = parkour_wall_run_pan_engage_smoothing
	if target_pan.length_squared() < _parkour_wall_run_pan_current.length_squared():
		smoothing = parkour_wall_run_pan_release_smoothing
	smoothing = max(smoothing, 0.0)
	if smoothing <= 0.0:
		_parkour_wall_run_pan_current = target_pan
	else:
		var blend: float = clamp(1.0 - exp(-smoothing * dt), 0.0, 1.0)
		_parkour_wall_run_pan_current = _parkour_wall_run_pan_current.lerp(target_pan, blend)


func _update_parkour_wall_kick_assist(delta: float, constraint_active: bool) -> void:
	if not _parkour_wall_kick_assist_active:
		return
	if (
		not parkour_camera_enabled
		or not parkour_wall_kick_assist_enabled
		or not SettingsManager.is_controller_input_active()
		or constraint_active
		or _camera_follow_disabled()
	):
		_parkour_wall_kick_assist_active = false
		return
	var cancel_strength: float = clamp(parkour_wall_kick_assist_cancel_stick_strength, 0.0, 1.0)
	if cancel_strength <= 0.0 or _camera_look_strength >= cancel_strength:
		_parkour_wall_kick_assist_active = false
		return
	var manual_weight: float = 1.0 - clamp(
		_camera_look_strength / max(cancel_strength, 0.001),
		0.0,
		1.0
	)
	_parkour_wall_kick_assist_elapsed += delta
	var duration: float = max(_parkour_wall_kick_assist_runtime_duration, 0.001)
	var remaining_weight: float = 1.0 - smoothstep(
		0.0,
		duration,
		_parkour_wall_kick_assist_elapsed
	)
	var response: float = max(parkour_wall_kick_assist_smoothing, 0.0)
	var blend: float = clamp(1.0 - exp(-response * delta), 0.0, 1.0)
	_yaw = lerp_angle(
		_yaw,
		_parkour_wall_kick_assist_target_yaw,
		blend * manual_weight * remaining_weight
	)
	if _parkour_wall_kick_assist_elapsed >= duration:
		_parkour_wall_kick_assist_active = false


func _get_target_camera_action_adjustment_state() -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {}
	if not target.has_method("get_camera_action_adjustment_state"):
		return {}
	var state_value: Variant = target.call("get_camera_action_adjustment_state")
	if state_value is Dictionary:
		return state_value
	return {}


func _update_speed_fov(delta: float, constraint_active: bool) -> float:
	# SUMMARY: Smoothly blend from the settings FOV to a boosted FOV based on speed.
	# STEPS:
	# - Step 1: Early-out if disabled.
	# - Step 2: Build a target FOV based on speed and facing alignment.
	# - Step 3: Lerp the current FOV toward the target.
	if not speed_fov_enabled:
		_speed_fov_current = _default_fov
		_speed_fov_weight = 0.0
		return _speed_fov_current

	var up: Vector3 = _get_camera_up().normalized()
	if up.length() < 0.001:
		up = _get_target_gravity_up()

	var speed: float = 0.0
	if target != null:
		var vel_val = target.get("velocity")
		if vel_val is Vector3:
			var vel: Vector3 = vel_val
			var vertical: float = vel.dot(up)
			var lateral: Vector3 = vel - up * vertical
			speed = lateral.length()

	var min_speed: float = max(speed_fov_min_speed, 0.0)
	var max_speed: float = max(speed_fov_max_speed, min_speed + 0.001)
	var t_speed: float = 0.0
	if max_speed > min_speed and speed > min_speed:
		t_speed = clamp((speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)

	var facing_weight: float = _get_speed_fov_facing_weight(up)
	var t_final: float = t_speed * facing_weight
	_speed_fov_weight = t_final

	var fov_offset: float = max(speed_fov_max_offset, 0.0)
	if _is_target_barrier_blast_active():
		fov_offset *= barrier_blast_fov_multiplier
	var target_fov: float = _default_fov + (fov_offset * t_final)

	if speed_fov_smooth <= 0.0 or delta <= 0.0:
		_speed_fov_current = target_fov
		return _speed_fov_current

	var t_smooth: float = 1.0 - exp(-speed_fov_smooth * delta)
	_speed_fov_current = lerp(_speed_fov_current, target_fov, t_smooth)
	return _speed_fov_current


func play_landing_feedback(result: StringName, strength: float) -> void:
	_landing_feedback_remaining = max(landing_feedback_duration, 0.05)
	_landing_feedback_elapsed = 0.0
	match result:
		&"accepted":
			_landing_fov_peak = landing_roll_accepted_fov
		&"rejected":
			_landing_fov_peak = -landing_roll_rejected_fov
		&"hard_landing":
			_landing_fov_peak = -landing_hard_fov
		_:
			_landing_fov_peak = 0.0
	_landing_shake_peak = 0.0
	if result == &"hard_landing":
		var minimum_shake: float = maxf(landing_hard_shake_min, 0.0)
		var maximum_shake: float = maxf(landing_hard_shake, minimum_shake)
		_landing_shake_peak = lerpf(minimum_shake, maximum_shake, clampf(strength, 0.0, 1.0))


func _step_landing_feedback(delta: float) -> Vector2:
	if _landing_feedback_remaining <= 0.0:
		return Vector2.ZERO
	var weight: float = _landing_feedback_remaining / max(landing_feedback_duration, 0.05)
	_landing_feedback_elapsed += max(delta, 0.0)
	_landing_feedback_remaining = max(_landing_feedback_remaining - max(delta, 0.0), 0.0)
	var fade: float = weight * weight
	return Vector2(
		_landing_fov_peak * fade,
		sin(_landing_feedback_elapsed * 72.0) * _landing_shake_peak * fade
	)


func _update_speed_distance(delta: float, constraint_active: bool) -> float:
	# SUMMARY: Smoothly reduce camera distance based on the current speed FOV weight.
	# STEPS:
	# - Step 1: Early-out if disabled, locked, or during constraints.
	# - Step 2: Build a target distance offset using the speed FOV weight.
	# - Step 3: Lerp the current offset toward the target.
	if not speed_distance_enabled or constraint_active or _distance_lock_active:
		_speed_distance_current = 0.0
		return _speed_distance_current

	var weight: float = clamp(_speed_fov_weight, 0.0, 1.0)
	var max_offset: float = max(speed_distance_max_offset, 0.0)
	if _is_target_barrier_blast_active():
		max_offset *= barrier_blast_distance_multiplier
	var target_offset: float = -max_offset * weight

	if speed_distance_smooth <= 0.0 or delta <= 0.0:
		_speed_distance_current = target_offset
		return _speed_distance_current

	var t_smooth: float = 1.0 - exp(-speed_distance_smooth * delta)
	_speed_distance_current = lerp(_speed_distance_current, target_offset, t_smooth)
	return _speed_distance_current


func _update_speed_vertical_offset(delta: float, constraint_active: bool) -> float:
	# SUMMARY: Smoothly offset the camera target vertically based on the current speed FOV weight.
	# STEPS:
	# - Step 1: Early-out if disabled, locked, or during constraints.
	# - Step 2: Build a target offset using the speed FOV weight.
	# - Step 3: Lerp the current offset toward the target.
	if not speed_vertical_offset_enabled or constraint_active or _distance_lock_active:
		_speed_vertical_offset_current = 0.0
		return _speed_vertical_offset_current

	var weight: float = clamp(_speed_fov_weight, 0.0, 1.0)
	var max_offset: float = speed_vertical_offset_max_offset
	if _is_target_barrier_blast_active():
		max_offset *= barrier_blast_vertical_offset_multiplier
	var target_offset: float = max_offset * weight

	if speed_vertical_offset_smooth <= 0.0 or delta <= 0.0:
		_speed_vertical_offset_current = target_offset
		return _speed_vertical_offset_current

	var t_smooth: float = 1.0 - exp(-speed_vertical_offset_smooth * delta)
	_speed_vertical_offset_current = lerp(_speed_vertical_offset_current, target_offset, t_smooth)
	return _speed_vertical_offset_current


func _update_speed_radial_blur(constraint_active: bool) -> void:
	var intensity: float = 0.0
	if speed_radial_blur_enabled and not constraint_active:
		intensity = clamp(_speed_fov_weight, 0.0, 1.0)
		if _is_target_barrier_blast_active():
			intensity *= max(barrier_blast_radial_blur_multiplier, 0.0)
	_set_speed_radial_blur_intensity(intensity)


func _set_speed_radial_blur_intensity(intensity: float) -> void:
	if _speed_radial_blur_effect == null or not is_instance_valid(_speed_radial_blur_effect):
		return
	if _speed_radial_blur_effect.has_method("set_intensity"):
		_speed_radial_blur_effect.call("set_intensity", intensity)


func _sync_camera_angles_from_forward(forward: Vector3, up: Vector3) -> void:
	var u := up.normalized()
	if u.length() < 0.001:
		u = _get_target_gravity_up()
	var f := forward.normalized()
	if f.length() < 0.001:
		return
	var flat := f - u * f.dot(u)
	if flat.length() < 0.001:
		return
	flat = flat.normalized()
	_clear_auto_follow_pitch_offset()
	_yaw = _get_yaw_from_forward(flat, u, _yaw)
	var pitch: float = -asin(clamp(f.dot(u), -1.0, 1.0))
	var min_pitch := deg_to_rad(min_pitch_deg)
	var max_pitch := deg_to_rad(max_pitch_deg)
	_pitch = clamp(pitch, min_pitch, max_pitch)


func _compute_roll_from_basis(basis: Basis, up: Vector3) -> float:
	var b := _normalize_basis(basis)
	var u := up.normalized()
	if u.length() < 0.001:
		u = _get_target_gravity_up()
	var forward := -b.z
	if forward.length() < 0.001:
		return 0.0
	forward = forward.normalized()
	if abs(forward.dot(u)) > 0.995:
		return 0.0
	var up_ref := (forward.cross(u)).cross(forward)
	if up_ref.length() < 0.001:
		return 0.0
	up_ref = up_ref.normalized()
	var up_actual := b.y.normalized()
	if up_ref.dot(up_actual) < 0.0:
		up_actual = -up_actual
	var sin_val: float = forward.dot(up_ref.cross(up_actual))
	var cos_val: float = up_ref.dot(up_actual)
	return atan2(sin_val, cos_val)


func _normalize_basis(basis: Basis) -> Basis:
	var b := basis.orthonormalized()
	if b.determinant() < 0.0:
		b.x = -b.x
	return b


func _get_camera_basis_from_guide_basis(basis: Basis) -> Basis:
	var guide_basis: Basis = _normalize_basis(basis)
	return _normalize_basis(Basis(-guide_basis.x, guide_basis.y, -guide_basis.z))


func _ease_in_out_sine(t: float) -> float:
	var t_clamped: float = clamp(t, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * t_clamped)

func _camera_controls_disabled() -> bool:
	return manual_input_locked or (_constraint_driver.selected_has_effect() and _constraint_driver.selected.disable_camera_controls)


func _camera_follow_disabled() -> bool:
	if manual_input_locked:
		return true
	var constraint: CameraConstraint = _constraint_driver.selected
	return _camera_controls_disabled() and not (is_instance_valid(constraint) and constraint.has_influence_trait(1))


func set_manual_input_lock(active: bool, allow_auto_follow: bool = false) -> void:
	manual_input_locked = active
	_manual_input_lock_allows_auto_follow = active and allow_auto_follow
	if _manual_input_lock_allows_auto_follow:
		_auto_follow_interrupt_timer = 0.0


func _process_zoom(delta: float) -> void:
	if _camera_controls_disabled():
		return
	# Gamepad / keyboard zoom input
	if Input.is_action_pressed("camera_zoom_in"):
		_distance_target -= zoom_speed * delta * 10.0
	if Input.is_action_pressed("camera_zoom_out"):
		_distance_target += zoom_speed * delta * 10.0

	_distance_target = clamp(_distance_target, min_distance, max_distance)

	# Smoothly move current distance toward target
	if zoom_smooth <= 0.01:
		distance = _distance_target
	else:
		var t := 1.0 - exp(-zoom_smooth * delta)
		distance = lerp(distance, _distance_target, t)


func _update_angles(delta: float, skip_gamepad: bool = false) -> void:
	# Mouse
	var mouse_invert: bool = invert_y_mouse
	var mouse_sens: float = 1.0
	mouse_invert = SettingsManager.mouse_invert_y
	mouse_sens = max(SettingsManager.mouse_look_sensitivity, 0.01)
	var mouse_y_sign: float = (-1.0) if mouse_invert else 1.0
	var yaw_sens_scaled: float = yaw_sensitivity
	var pitch_sens_scaled: float = pitch_sensitivity
	_yaw -= _mouse_delta.x * yaw_sens_scaled * mouse_sens
	_pitch += _mouse_delta.y * pitch_sens_scaled * mouse_sens * mouse_y_sign

	# Gamepad / keyboard look
	var keyboard_look_h: float = SettingsManager.get_signed_action_axis(&"camera_left", &"camera_right", 0.0, &"keyboard")
	var keyboard_look_v: float = SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", 0.0, &"keyboard")
	var gamepad_look_h: float = SettingsManager.get_signed_action_axis(&"camera_left", &"camera_right", SettingsManager.get_right_stick_deadzone(), &"gamepad")
	var gamepad_look_v: float = SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", SettingsManager.get_right_stick_deadzone(), &"gamepad")
	var keyboard_look: Vector2 = Vector2(keyboard_look_h, keyboard_look_v)
	var gamepad_look: Vector2 = Vector2.ZERO if skip_gamepad else Vector2(gamepad_look_h, gamepad_look_v)
	var keyboard_look_strength: float = keyboard_look.length()
	var gamepad_look_strength: float = gamepad_look.length()
	var look_input: Vector2 = keyboard_look
	if gamepad_look_strength > keyboard_look_strength:
		look_input = gamepad_look
	var look_h: float = look_input.x
	var look_v: float = look_input.y
	var stick_invert_y: bool = SettingsManager.right_stick_invert_y or invert_y_input
	var input_y_sign: float = 1.0 if stick_invert_y else -1.0
	var stick_turn_multiplier: float = 1.0
	if look_input == gamepad_look:
		stick_turn_multiplier = 4.0 * SettingsManager.get_right_stick_sensitivity()
	if _mouse_delta.length() > 0.001 or look_input.length() > 0.001:
		_auto_follow_interrupt_timer = max(auto_follow_interrupt_delay, 0.0)

	_yaw -= look_h * yaw_sens_scaled * 10.0 * delta * stick_turn_multiplier
	_pitch += look_v * pitch_sens_scaled * 10.0 * delta * stick_turn_multiplier * input_y_sign
	_camera_look_strength = look_input.length()
	_camera_mouse_strength = _mouse_delta.length()

	# Clamp pitch
	var min_pitch := deg_to_rad(min_pitch_deg)
	var max_pitch := deg_to_rad(max_pitch_deg)
	_pitch = clamp(_pitch, min_pitch, max_pitch)


func _get_aspect_ratio_height_offset() -> float:
	if not aspect_ratio_height_offset_enabled:
		return 0.0
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return 0.0
	var aspect_ratio: float = viewport_size.x / viewport_size.y
	var clamped_aspect_ratio: float = clampf(aspect_ratio, ASPECT_RATIO_16_9, ASPECT_RATIO_21_9)
	var narrowness: float = inverse_lerp(ASPECT_RATIO_21_9, ASPECT_RATIO_16_9, clamped_aspect_ratio)
	return aspect_ratio_height_offset_16_9 * narrowness


func _update_transform(delta: float) -> void:
	_restore_camera_local_basis()
	var constraint: CameraConstraint = _constraint_driver.selected
	var presenting: bool = _constraint_driver.is_presenting()
	var proximity_blend: bool = is_instance_valid(constraint) and _constraint_driver.selected_has_effect() and constraint.has_influence_trait()
	var suppress_speed: bool = _constraint_driver.selected_has_effect() and constraint.suppress_speed_effects
	var orientation_owned: bool = _constraint_driver.owns_orientation()
	var suppress_free_orientation: bool = _constraint_driver.suppresses_free_orientation()
	var up: Vector3 = _get_camera_up()
	var speed_fov_value: float = _update_speed_fov(delta, suppress_speed)
	if suppress_speed:
		speed_fov_value = _default_fov
	var landing_feedback: Vector2 = _step_landing_feedback(delta)
	var speed_distance_offset: float = _update_speed_distance(delta, suppress_speed)
	var speed_vertical_offset: float = _update_speed_vertical_offset(delta, suppress_speed)
	_update_speed_radial_blur(suppress_speed)
	var min_distance_effective: float = min_distance
	if speed_distance_offset < 0.0:
		min_distance_effective = maxf(min_distance + speed_distance_offset, 0.01)
	var effective_distance: float = clampf(distance + speed_distance_offset, min_distance_effective, max_distance)
	_update_auto_follow(delta, up, suppress_free_orientation)
	_update_parkour_camera(delta, up, suppress_free_orientation)
	var zoom_t: float = 0.0
	if max_distance > min_distance:
		zoom_t = clampf((effective_distance - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	var current_vertical_offset: float = lerpf(min_vertical_offset, max_vertical_offset, zoom_t)
	current_vertical_offset += speed_vertical_offset + _get_aspect_ratio_height_offset()
	var dolly_position: Vector3 = _update_dolly_follow(delta, _get_dolly_tracking_up())
	var desired_target_pos: Vector3 = dolly_position + up * current_vertical_offset
	if not suppress_free_orientation:
		desired_target_pos += _parkour_wall_run_pan_current
	var rig_pos: Vector3 = global_position
	if proximity_blend and _influence_free_pivot_valid:
		rig_pos = _influence_free_pivot
	if (presenting and not proximity_blend) or _teleport_snap_timer > 0.0 or dolly_follow_enabled:
		rig_pos = desired_target_pos
	elif smooth_follow:
		var follow_speed: float = _get_dolly_response(0.0)
		rig_pos = rig_pos.lerp(desired_target_pos, 1.0 - exp(-follow_speed * delta)) if follow_speed > 0.0 else desired_target_pos
	else:
		rig_pos = desired_target_pos
	_influence_free_pivot = rig_pos
	_influence_free_pivot_valid = proximity_blend
	global_position = rig_pos
	var base_forward: Vector3 = _get_base_forward_ref(up)
	var flat_forward: Vector3 = base_forward.rotated(up, _yaw).normalized()
	var right: Vector3 = up.cross(flat_forward).normalized()
	var forward: Vector3 = up.cross(right).normalized()
	var yaw_basis: Basis = Basis(right, up, -forward)
	if absf(_roll_offset) > 0.0001:
		yaw_basis = yaw_basis.rotated(forward, _roll_offset)
	yaw_node.global_transform = Transform3D(yaw_basis, rig_pos)
	pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)
	var desired_camera_global: Vector3 = pitch_node.to_global(Vector3(0.0, 0.0, -effective_distance))
	desired_camera_global += camera.global_basis.y * landing_feedback.y
	if presenting or (camera_collision_stabilization_enabled and _rear_view_active and not is_constraint_active()):
		camera.global_position = desired_camera_global
	else:
		camera.global_position = _resolve_camera_collision(desired_camera_global, camera_collision_enabled, delta)
	camera.fov = speed_fov_value + landing_feedback.x
	_landing_fov_applied = landing_feedback.x
	if presenting:
		_constraint_driver.apply(delta, camera.global_transform, rig_pos, effective_distance, camera.fov)
	if not orientation_owned:
		_control_yaw = _yaw
		_control_pitch = _pitch


func get_yaw() -> float:
	return _control_yaw


func get_player_up_toggle() -> bool:
	return _player_up_toggle_enabled


func set_player_up_toggle(value: bool, animate: bool = false) -> void:
	_player_up_toggle_enabled = value
	if is_instance_valid(_constraint_driver.selected):
		_constraint_driver.selected.alignment_override_dismissed = true
	_sync_camera_orientation_hud(animate)


func toggle_player_up() -> void:
	set_player_up_toggle(not _get_player_up_requested(), true)


func get_yaw_forward() -> Vector3:
	if _rear_view_transform_applied and _rear_view_control_forward.length_squared() > 0.000001:
		return _rear_view_control_forward
	if camera != null and _constraint_driver.owns_orientation():
		var up: Vector3 = _get_camera_up()
		var forward: Vector3 = -camera.global_basis.z
		forward = forward.slide(up)
		if forward.length_squared() < 0.000001:
			forward = up.cross(camera.global_basis.x).slide(up)
		if forward.length_squared() > 0.000001:
			return forward.normalized()
	if yaw_node != null and is_instance_valid(yaw_node):
		var fwd: Vector3 = yaw_node.global_transform.basis.z
		if fwd.length() > 0.001:
			return fwd.normalized()
	var up: Vector3 = _get_camera_up()
	var base_forward: Vector3 = _get_base_forward_ref(up)
	if base_forward.length() < 0.001:
		return -Vector3.FORWARD
	return base_forward.rotated(up, _yaw).normalized()


func set_auto_follow_enabled(value: bool) -> void:
	auto_follow_enabled = value
	if not auto_follow_enabled:
		_clear_auto_follow_pitch_offset()
		_auto_follow_motion_weight = 0.0


func set_auto_follow_sensitivity(value: float) -> void:
	auto_follow_sensitivity = max(value, 0.0)


func set_auto_follow_interrupt_delay(value: float) -> void:
	auto_follow_interrupt_delay = max(value, 0.0)


func set_auto_follow_deadzone_deg(value: float) -> void:
	auto_follow_deadzone_deg = clamp(value, 0.0, 180.0)


func set_auto_follow_max_deviation_deg(value: float) -> void:
	auto_follow_max_deviation_deg = clamp(value, auto_follow_deadzone_deg, 180.0)


func set_auto_follow_vertical_enabled(value: bool) -> void:
	auto_follow_vertical_enabled = value
	if not auto_follow_vertical_enabled:
		_clear_auto_follow_pitch_offset()


func set_auto_follow_vertical_max_tilt_deg(value: float) -> void:
	auto_follow_vertical_max_tilt_deg = clamp(value, 0.0, 90.0)


func set_auto_follow_level_pitch_deg(value: float) -> void:
	auto_follow_level_pitch_deg = clamp(value, -89.0, 89.0)


func set_auto_follow_speed_ramp(value: float) -> void:
	auto_follow_speed_ramp = max(value, 0.0)


func set_auto_follow_slope_suppression(value: float) -> void:
	auto_follow_slope_suppression = clamp(value, 0.0, 1.0)


func set_auto_follow_slope_threshold_deg(value: float) -> void:
	auto_follow_slope_threshold_deg = clamp(value, 0.0, 90.0)


func set_auto_follow_preview(active: bool, velocity: Vector3 = Vector3.ZERO) -> void:
	if _auto_follow_preview_active != active:
		_reset_auto_follow_state()
	_auto_follow_preview_active = active
	_auto_follow_preview_velocity = velocity


func set_follow_smoothing(value: float) -> void:
	var smoothing: float = max(value, 0.0)
	_settings_follow_smooth = smoothing
	_settings_smooth_follow = smoothing > 0.001
	if smoothing <= 0.001:
		smooth_follow = false
		follow_smooth = 0.0
	else:
		smooth_follow = true
		follow_smooth = smoothing


func set_dolly_follow_enabled(value: bool) -> void:
	dolly_follow_enabled = value


func set_target_lookahead_enabled(value: bool) -> void:
	target_lookahead_enabled = value


func set_target_lookahead_amount(value: float) -> void:
	target_lookahead_strength = clamp(value / 100.0, 0.0, 1.0)


func _get_post_process_exempt_3d_layer_bit() -> int:
	return 1 << (POST_PROCESS_EXEMPT_3D_LAYER_INDEX - 1)


func _ensure_post_process_exempt_3d_pass() -> void:
	if not post_process_exempt_3d_enabled:
		return
	if camera == null or get_tree() == null:
		return

	var layer_bit: int = _get_post_process_exempt_3d_layer_bit()
	_post_process_exempt_layer_bit_active = layer_bit
	if not post_process_exempt_3d_hide_from_main_view:
		camera.cull_mask = camera.cull_mask | layer_bit
		if _post_process_exempt_layer_node != null and is_instance_valid(_post_process_exempt_layer_node):
			_post_process_exempt_layer_node.visible = false
		return
	else:
		camera.cull_mask = camera.cull_mask & ~layer_bit

	var scene: Node = get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	if scene == null:
		return

	if _post_process_exempt_layer_node == null or not is_instance_valid(_post_process_exempt_layer_node):
		var layer: CanvasLayer = scene.get_node_or_null("PostProcessExempt3D") as CanvasLayer
		if layer == null:
			layer = CanvasLayer.new()
			layer.name = "PostProcessExempt3D"
			scene.add_child(layer)
		layer.layer = post_process_exempt_3d_canvas_layer
		layer.visible = true
		_post_process_exempt_layer_node = layer
	else:
		_post_process_exempt_layer_node.visible = true

	if _post_process_exempt_viewport == null or not is_instance_valid(_post_process_exempt_viewport):
		var viewport: SubViewport = SubViewport.new()
		viewport.name = "PostProcessExemptViewport"
		viewport.own_world_3d = false
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		viewport.disable_3d = false
		var source_viewport: Viewport = get_viewport()
		if source_viewport != null:
			viewport.world_3d = source_viewport.world_3d
		_post_process_exempt_layer_node.add_child(viewport)
		_post_process_exempt_viewport = viewport

	if _post_process_exempt_camera == null or not is_instance_valid(_post_process_exempt_camera):
		var overlay_camera: Camera3D = Camera3D.new()
		overlay_camera.name = "PostProcessExemptCamera"
		overlay_camera.cull_mask = layer_bit
		overlay_camera.current = true
		_post_process_exempt_viewport.add_child(overlay_camera)
		overlay_camera.make_current()
		_post_process_exempt_camera = overlay_camera

	if _post_process_exempt_texture_rect == null or not is_instance_valid(_post_process_exempt_texture_rect):
		var rect: TextureRect = TextureRect.new()
		rect.name = "PostProcessExemptTexture"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.texture = _post_process_exempt_viewport.get_texture()
		_post_process_exempt_layer_node.add_child(rect)
		_post_process_exempt_texture_rect = rect


func _update_post_process_exempt_3d_pass() -> void:
	if not post_process_exempt_3d_enabled:
		if camera != null and _post_process_exempt_layer_bit_active != 0:
			camera.cull_mask = camera.cull_mask | _post_process_exempt_layer_bit_active
			_post_process_exempt_layer_bit_active = 0
		if _post_process_exempt_layer_node != null and is_instance_valid(_post_process_exempt_layer_node):
			_post_process_exempt_layer_node.visible = false
		return
	if camera == null:
		return
	if not post_process_exempt_3d_hide_from_main_view:
		var main_layer_bit: int = _get_post_process_exempt_3d_layer_bit()
		camera.cull_mask = camera.cull_mask | main_layer_bit
		_post_process_exempt_layer_bit_active = main_layer_bit
		if _post_process_exempt_layer_node != null and is_instance_valid(_post_process_exempt_layer_node):
			_post_process_exempt_layer_node.visible = false
		return
	_ensure_post_process_exempt_3d_pass()
	if _post_process_exempt_viewport == null or _post_process_exempt_camera == null:
		return

	var source_viewport: Viewport = get_viewport()
	if source_viewport != null:
		var viewport_size_f: Vector2 = source_viewport.get_visible_rect().size
		var viewport_size: Vector2i = Vector2i(int(viewport_size_f.x), int(viewport_size_f.y))
		if viewport_size.x > 0 and viewport_size.y > 0:
			_post_process_exempt_viewport.size = viewport_size
			if _post_process_exempt_texture_rect != null:
				_post_process_exempt_texture_rect.size = Vector2(float(viewport_size.x), float(viewport_size.y))
		_post_process_exempt_viewport.world_3d = source_viewport.world_3d

	var layer_bit: int = _get_post_process_exempt_3d_layer_bit()
	if post_process_exempt_3d_hide_from_main_view:
		camera.cull_mask = camera.cull_mask & ~layer_bit
	else:
		camera.cull_mask = camera.cull_mask | layer_bit
	_post_process_exempt_camera.cull_mask = layer_bit
	_post_process_exempt_camera.global_transform = camera.global_transform
	_post_process_exempt_camera.projection = camera.projection
	_post_process_exempt_camera.fov = camera.fov
	_post_process_exempt_camera.size = camera.size
	_post_process_exempt_camera.near = camera.near
	_post_process_exempt_camera.far = camera.far
	_post_process_exempt_camera.keep_aspect = camera.keep_aspect
	_post_process_exempt_camera.attributes = null


func set_drift_camera_state(
	active: bool,
	heading_dir: Vector3,
	turn_speed_deg_per_sec: float,
	influence: float = 1.0
) -> void:
	if not drift_camera_enabled:
		_drift_camera_active_target = false
		_drift_camera_blend_target = 0.0
		_drift_heading_dir = Vector3.ZERO
		_drift_turn_speed_target = 0.0
		return
	_drift_camera_active_target = active
	_drift_camera_blend_target = clamp(influence, 0.0, 1.0)
	_drift_heading_dir = heading_dir
	_drift_turn_speed_target = turn_speed_deg_per_sec


func set_default_fov(value: float, apply_now: bool = true) -> void:
	_default_fov = value
	_speed_fov_current = _default_fov
	if apply_now and camera and not _constraint_driver.is_presenting():
		camera.fov = _default_fov
		_landing_fov_applied = 0.0


func get_default_fov() -> float:
	return _default_fov


func set_yaw_from_forward(forward: Vector3, up: Vector3 = Vector3.ZERO) -> void:
	if _constraint_driver.owns_orientation():
		return
	var u := up.normalized()
	if u.length() < 0.001:
		u = _get_target_gravity_up()
	var f := forward - u * forward.dot(u)
	if f.length() < 0.001:
		return
	f = f.normalized()
	_reset_base_forward_ref(u)
	_yaw = _get_yaw_from_forward(f, u, _yaw)
	_control_yaw = _yaw
	_reset_auto_follow_state()


func align_to_direction(direction: Vector3, up: Vector3 = Vector3.ZERO) -> void:
	set_yaw_from_forward(direction, up)


## Aligns yaw and pitch to an authored facing direction without changing yaw-only launch alignment.
func align_to_facing_direction(direction: Vector3, up: Vector3 = Vector3.ZERO) -> void:
	if _constraint_driver.owns_orientation() or direction.length_squared() < 0.001:
		return
	var resolved_up: Vector3 = up.normalized()
	if resolved_up.length_squared() < 0.001:
		resolved_up = _get_camera_up()
	set_yaw_from_forward(direction, resolved_up)
	_pitch = clampf(-asin(clampf(direction.normalized().dot(resolved_up), -1.0, 1.0)), deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_control_pitch = _pitch


func _reset_base_forward_ref(up: Vector3) -> void:
	# Reset _base_forward_ref to world +Z projected onto the given up plane.
	# atan2(f.x, f.z) yields 0 when facing +Z, so the reference must be +Z (Vector3.BACK in Godot).
	var up_norm: Vector3 = up.normalized()
	if up_norm.length() < 0.001:
		up_norm = _get_target_gravity_up()
	var ref: Vector3 = Vector3.BACK - up_norm * Vector3.BACK.dot(up_norm)
	if ref.length() < 0.001:
		ref = Vector3.RIGHT - up_norm * Vector3.RIGHT.dot(up_norm)
	if ref.length() < 0.001:
		ref = Vector3.BACK
	_base_forward_ref = ref.normalized()


func is_constraint_active() -> bool:
	return not _constraint_driver.is_manually_suppressed() and (is_instance_valid(_constraint_driver.selected) or not _constraint_driver.constraints.is_empty())


func _get_angles_from_forward(forward: Vector3, up: Vector3, fallback: Vector2) -> Vector2:
	var u := up.normalized()
	if u.length() < 0.001:
		u = _get_target_gravity_up()
	var f := forward.normalized()
	if f.length() < 0.001:
		return fallback
	var flat := f - u * f.dot(u)
	if flat.length() < 0.001:
		return fallback
	flat = flat.normalized()
	var yaw: float = _get_yaw_from_forward(flat, u, fallback.x)
	var pitch: float = -asin(clamp(f.dot(u), -1.0, 1.0))
	var min_pitch := deg_to_rad(min_pitch_deg)
	var max_pitch := deg_to_rad(max_pitch_deg)
	pitch = clamp(pitch, min_pitch, max_pitch)
	return Vector2(yaw, pitch)


## Updates control angles in the current heading frame without resetting free-camera orientation.
func _set_control_angles_from_forward(forward: Vector3, up: Vector3) -> void:
	var u: Vector3 = up.normalized()
	if u.length() < 0.001:
		u = _get_target_gravity_up()
	var f: Vector3 = forward.normalized()
	if f.length() < 0.001:
		return
	var flat: Vector3 = f - u * f.dot(u)
	if flat.length() < 0.001:
		return
	flat = flat.normalized()
	_control_yaw = _get_yaw_from_forward(flat, u, _control_yaw)
	var pitch: float = -asin(clamp(f.dot(u), -1.0, 1.0))
	var min_pitch: float = deg_to_rad(min_pitch_deg)
	var max_pitch: float = deg_to_rad(max_pitch_deg)
	_control_pitch = clamp(pitch, min_pitch, max_pitch)


func _restore_camera_local_basis() -> void:
	if camera == null or not _has_camera_base_local_transform:
		return
	var origin: Vector3 = camera.transform.origin
	camera.transform = Transform3D(_camera_base_local_transform.basis, origin)


func _resolve_camera_collision(desired_position: Vector3, collision_enabled: bool, delta: float = 0.0) -> Vector3:
	if not collision_enabled or not get_world_3d() or not target:
		_camera_collision_initialized = false
		return desired_position
	var origin: Vector3 = target.global_position
	var segment: Vector3 = desired_position - origin
	var segment_length: float = segment.length()
	if segment_length < 0.001:
		_camera_collision_initialized = false
		return desired_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, desired_position)
	query.collision_mask = camera_collision_mask
	query.hit_back_faces = true
	query.hit_from_inside = true
	if target is CollisionObject3D:
		query.exclude = [target.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var available_distance: float = segment_length
	var blocked_position: Vector3 = desired_position
	if hit:
		available_distance = minf(maxf(origin.distance_to(hit.position) - camera_collision_margin, 0.0), segment_length)
		blocked_position = origin + segment / segment_length * available_distance
	if not camera_collision_stabilization_enabled:
		_camera_collision_initialized = false
		return blocked_position
	# Zero-time calls query clearance without advancing recovery.
	if delta <= 0.0:
		return blocked_position
	var rear_view: bool = _rear_view_active
	if (
		not _camera_collision_initialized
		or not _camera_collision_recovering
		or _camera_collision_target_ref != target
		or _camera_collision_rear_view != rear_view
		or _teleport_snap_timer > 0.0
	):
		_camera_collision_initialized = true
		_camera_collision_target_ref = target
		_camera_collision_rear_view = rear_view
		_camera_collision_distance = available_distance
		_camera_collision_clear_timer = maxf(camera_collision_clear_delay, 0.0) if hit else 0.0
		_camera_collision_recovering = not hit.is_empty()
	elif available_distance < _camera_collision_distance:
		_camera_collision_distance = available_distance
		_camera_collision_clear_timer = maxf(camera_collision_clear_delay, 0.0) if hit else 0.0
		_camera_collision_recovering = not hit.is_empty()
	elif hit and available_distance <= _camera_collision_distance + maxf(camera_collision_distance_tolerance, 0.0):
		_camera_collision_clear_timer = maxf(camera_collision_clear_delay, 0.0)
	else:
		var recovery_delta: float = maxf(delta - _camera_collision_clear_timer, 0.0)
		_camera_collision_clear_timer = maxf(_camera_collision_clear_timer - delta, 0.0)
		if recovery_delta > 0.0:
			var blend: float = 1.0
			if camera_collision_recovery_speed > 0.0:
				blend = 1.0 - exp(-camera_collision_recovery_speed * recovery_delta)
			_camera_collision_distance = lerpf(_camera_collision_distance, available_distance, blend)
			if available_distance - _camera_collision_distance < 0.001:
				_camera_collision_distance = available_distance
				_camera_collision_recovering = not hit.is_empty()
	if not hit and not _camera_collision_recovering:
		return desired_position
	return origin + segment / segment_length * minf(_camera_collision_distance, available_distance)

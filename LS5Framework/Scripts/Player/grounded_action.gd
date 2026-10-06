class_name GroundedAction
extends CharacterAction

@export_group("Grounded Movement")

@export_subgroup("Speed")
@export var run_top_speed: float = 110.0
## Top speed used while walk input is held.
@export var walk_top_speed: float = 22.0
## Ground deceleration used when no curve is assigned.
@export var decel: float = 25.0
## Optional ground deceleration by lateral speed.
## X: lateral speed, Y: deceleration (units/sec^2). Overrides decel when assigned.
@export var ground_decel_curve: Curve
## Ground acceleration by lateral speed.
@export var ground_accel_curve: Curve
## Ground acceleration by lateral speed while walk input is held.
@export var walk_ground_accel_curve: Curve

@export_subgroup("Turning")
## Ground turn rate by lateral speed.
@export var ground_turn_angle_curve: Curve
## Ground turn rate by lateral speed while walk input is held.
@export var walk_turn_angle_curve: Curve
## Maximum turn-rate multiplier reached when input asks for a sharp course change.
@export_range(1.0, 3.0, 0.05) var ground_turn_sharp_rate_multiplier: float = 1.35
## Fraction of ordinary turn deceleration ignored during sharp turns.
## Deliberate reverse input still brakes normally.
@export_range(0.0, 1.0, 0.05) var ground_turn_speed_preservation: float = 0.65
## Deceleration applied when movement input opposes the current course.
@export var ground_brake_decel: float = 70.0

@export_storage var ground_turn_free_angle_deg: float = 11.0
@export_storage var ground_turn_max_penalty_angle_deg: float = 360.0
@export_storage var ground_turn_max_penalty_angle_curve: Curve
@export_storage var ground_turn_free_angle_curve: Curve
@export_storage var ground_turn_min_speed_factor: float = 0.965

@export_subgroup("Slope/Acceleration")
## Downhill response acceleration at full slope effect under the character's baseline gravity.
@export var slope_downhill_accel: float = 90.0
## Optional downhill acceleration by lateral speed.
## X: lateral speed, Y: acceleration.
@export var slope_downhill_accel_curve: Curve
## Uphill response acceleration at full slope effect under the character's baseline gravity.
@export var slope_uphill_decel: float = 45.0
## Optional uphill response acceleration by lateral speed.
## X: lateral speed, Y: deceleration.
@export var slope_uphill_decel_curve: Curve
## Uphill speed range used to blend continuously from downhill response to uphill response.
@export var slope_uphill_response_blend_speed: float = 4.0
## Final grounded slope response power by surface angle.
## X: surface angle in degrees, Y: power multiplier.
@export var slope_gravity_angle_curve: Curve
## Uphill speed below which walkable-slope traction prevents immediate backward sliding.
@export var slope_uphill_start_traction_speed: float = 5
## Fraction of uphill motor acceleration retained during low-speed starting traction.
@export_range(0.0, 1.0, 0.01) var slope_uphill_start_accel_ratio: float = 0.25

@export_subgroup("Slope/Uphill Reversal Guard")
## Restricts low-speed uphill restarts until enough downhill travel has been earned.
@export var slope_reversal_guard_enabled: bool = true
## Minimum surface angle where the uphill reversal guard can arm.
@export var slope_reversal_guard_min_angle_deg: float = 45.0
## Uphill speed required to arm a run-up before a reversal.
@export var slope_reversal_guard_arm_uphill_speed: float = 12
## Downhill distance required to fully recover from an armed reversal.
@export var slope_reversal_guard_recovery_distance: float = 120
## Additional tangential-gravity multiplier at full reversal debt.
@export var slope_reversal_guard_pull_multiplier: float = 2.5
## Uphill speed where reversal restrictions fade out to preserve earned momentum.
@export var slope_reversal_guard_momentum_preserve_speed: float = 160
## Multiplier applied to sharp-turn speed preservation at full reversal debt.
@export_range(0.0, 1.0, 0.01) var slope_reversal_guard_turn_preservation: float = 0.0
## Input alignment with downhill required to arm a deliberate reversal.
@export_range(0.0, 1.0, 0.01) var slope_reversal_guard_turn_alignment: float = 0.4
## Airborne time before reversal debt is cleared.
@export var slope_reversal_guard_air_reset_time: float = 1.25

@export_subgroup("Slope/Uphill Control Limit")
## Surface angle where low-speed uphill control starts being limited.
@export var slope_uphill_control_ratio_min_angle_deg: float = 70.0
## Surface angle where the uphill control ratio reaches its full effect.
@export var slope_uphill_control_ratio_full_angle_deg: float = 85.0
## Uphill motor acceleration retained relative to downhill slope acceleration by angle fraction.
## X: 0 at the minimum angle and 1 at the full angle. Y: retained ratio.
@export var slope_uphill_control_ratio_curve: Curve
## Strength of excess-acceleration adaptation during the angle transition. Zero uses the base angle blend; one increases its response by up to four times as uphill motor acceleration exceeds slope pull.
@export_range(0.0, 1.0, 0.01) var slope_uphill_control_accel_adaptation: float = 1.0
## Surface-tangential speed at or below which the steep-slope control limit has full effect.
@export var slope_uphill_control_limit_full_speed: float = 20.0
## Surface-tangential speed at or above which earned momentum releases the control limit.
@export var slope_uphill_control_limit_release_speed: float = 65.0

@export_subgroup("Slope/Walkable Limit and Sliding")
## Non-rolling ground speed below which static slope traction can hold the player at rest.
## Set to 0.0 to disable stationary slope holding.
@export var slope_idle_hold_speed: float = 2.0
## Surface angle above which passive static traction releases.
@export var slope_slide_start_angle_deg: float = 40.0
## Angle below the release threshold required to regain passive static traction.
@export var slope_static_hold_hysteresis_deg: float = 3.0
## Constant resistance applied while passively sliding without input.
@export var slope_slide_resistance: float = 6.0
## Speed-proportional resistance applied while passively sliding without input.
@export var slope_slide_linear_drag: float = 0.0
## Squared-speed resistance applied while passively sliding without input.
@export var slope_slide_quadratic_drag: float = 0.0015
## Prevents the normal grounded soft cap from removing speed earned from downhill gravity.
@export var slope_downhill_soft_cap_bypass: bool = true
## Minimum downhill velocity alignment that activates the downhill soft-cap bypass.
@export_range(0.0, 1.0, 0.01) var slope_downhill_soft_cap_min_alignment: float = 0.05
@export_storage var slope_slide_accel: float = 50.0
@export_storage var slope_max_effect_angle_deg: float = 90.0

@export_subgroup("Skidding")
@export var skid_enter_min_speed: float = 20.0
@export var skid_enter_angle_deg: float = 160.0
@export var skid_exit_angle_deg: float = 150.0
@export var skid_exit_min_speed: float = 0.0
@export var skid_decel: float = 130.0
@export var skid_turn_deg_per_sec: float = 5.0
@export var skid_max_ground_angle_deg: float = 80.0

@export_subgroup("Audio/Engine Loop")
## Loop played during high-speed default grounded movement.
@export var engine_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Footstep/Engine_Loop.wav")
## Tangential speed where the engine loop starts fading in at minimum volume.
@export var engine_sound_volume_min_speed: float = 50.0
## Tangential speed where the engine loop reaches maximum volume.
@export var engine_sound_volume_full_speed: float = 130.0
## Engine loop volume at the volume minimum speed.
@export var engine_sound_volume_min_db: float = -43.0
## Engine loop volume at full speed.
@export var engine_sound_volume_max_db: float = -26.0
## Tangential speed where engine pitch begins increasing.
@export var engine_sound_pitch_min_speed: float = 50.0
## Tangential speed where engine pitch reaches its maximum value.
@export var engine_sound_pitch_full_speed: float = 200.0
## Engine loop pitch at the pitch minimum speed.
@export var engine_sound_pitch_min: float = 1.3
## Engine loop pitch at full speed.
@export var engine_sound_pitch_max: float = 1.8
## Blend speed for tangential-speed-driven volume and pitch changes.
@export var engine_sound_lerp_speed: float = 300.0
## Fade-in rate in decibels per second.
@export var engine_sound_fade_in_speed_db: float = 90.0
## Fade-out rate in decibels per second.
@export var engine_sound_fade_out_speed_db: float = 40.0
## Volume where the faded-out engine loop stops playing.
@export var engine_sound_stop_volume_db: float = -60.0


func _on_action_initialized() -> void:
	action_id = &"grounded"
	input_action = &""
	continuous_update = false
	allow_when_inactive = true

class_name AdditivePhysicsSet
extends Resource

@export_group("Set")
## Stable key used by AnimationTree resource-name arguments.
@export var set_id: StringName = &"secondary_motion"
## Enables this additive physics set.
@export var enabled: bool = true
## AnimationNodeAdd2 name in the AnimationTree root blend tree.
@export var additive_node_name: StringName
## AnimationNodeAnimation name connected to the additive input.
@export var animation_node_name: StringName
## AnimationNodeTimeScale name controlling additive animation playback speed.
@export var animation_time_scale_node_name: StringName
## AnimationPlayer library name assigned to the additive animation node.
@export var animation_name: StringName

@export_group("Bone Filter")
## Skeleton bone roots affected by this set.
@export var bone_roots: Array[StringName] = []
## Includes every descendant of each configured bone root.
@export var include_child_bones: bool = true

@export_group("Airborne Envelope")
## Air speed where this set begins contributing.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m/s") var airborne_activation_speed: float = 45.0
## Air speed that produces full target strength.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m/s") var airborne_full_speed: float = 140.0
## Multiplier applied to the airborne target strength.
@export_range(0.0, 4.0, 0.01, "or_greater") var airborne_strength_multiplier: float = 1.0
## Playback scale used when airborne speed reaches the activation threshold.
@export_range(0.0, 10.0, 0.01, "or_greater") var airborne_animation_speed_at_activation: float = 0.75
## Playback scale used when airborne speed reaches the full-strength threshold.
@export_range(0.0, 10.0, 0.01, "or_greater") var airborne_animation_speed_at_full: float = 1.25

@export_group("Grounded Envelope")
## Ground speed where this set begins contributing.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m/s") var grounded_activation_speed: float = 80.0
## Ground speed that produces full target strength.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m/s") var grounded_full_speed: float = 180.0
## Multiplier applied to the grounded target strength.
@export_range(0.0, 4.0, 0.01, "or_greater") var grounded_strength_multiplier: float = 0.25
## Playback scale used when grounded speed reaches the activation threshold.
@export_range(0.0, 10.0, 0.01, "or_greater") var grounded_animation_speed_at_activation: float = 0.6
## Playback scale used when grounded speed reaches the full-strength threshold.
@export_range(0.0, 10.0, 0.01, "or_greater") var grounded_animation_speed_at_full: float = 1.0

@export_group("Response")
## Optional curve remapping normalized speed to target strength.
@export var strength_curve: Curve
## Maximum additive blend amount produced by this set.
@export_range(0.0, 4.0, 0.01, "or_greater") var maximum_strength: float = 1.0
## Time required to raise the additive blend amount by 1.0.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var rise_time: float = 0.55
## Time retained at the last strength after becoming inactive.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var inactivity_hold_time: float = 0.3
## Time required to lower the additive blend amount by 1.0.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var decay_time: float = 1.5
## Time required to lower the suppressed blend amount by 1.0.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var suppression_fade_time: float = 0.1

@export_group("Playback Response")
## Playback scale approached after the set becomes inactive.
@export_range(0.0, 10.0, 0.01, "or_greater") var inactive_animation_speed: float = 0.0
## Time required to raise playback scale by 1.0.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var animation_speed_rise_time: float = 0.25
## Time retained at the last playback scale after becoming inactive.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var animation_speed_inactivity_hold_time: float = 0.3
## Time required to lower playback scale by 1.0 after speed decreases or becomes inactive.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var animation_speed_falloff_time: float = 1.0

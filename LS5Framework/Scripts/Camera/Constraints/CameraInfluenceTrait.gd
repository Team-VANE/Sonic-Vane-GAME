@tool
extends Resource
class_name CameraInfluenceTrait

enum Falloff { LINEAR, SMOOTHSTEP }

## Influence center relative to the constraint. Empty uses the constraint origin, independently of camera placement.
@export var reference_path: NodePath = NodePath("")
## World-space radius within which the affected channels have full influence.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var full_influence_distance: float = 0.0
## World-space radius at which influence reaches zero. Must exceed Full Influence Distance.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var zero_influence_distance: float = 100.0
## Curve applied between the full and zero influence radii.
@export var falloff: Falloff = Falloff.SMOOTHSTEP
## Exponent applied after falloff. Values above one concentrate influence near the center.
@export_range(0.01, 10.0, 0.01, "or_greater") var power: float = 1.0
## Weights camera position, orbit pivot, and orbit distance.
@export var position: bool = true
## Weights camera orientation and roll.
@export var orientation: bool = true
## Weights field of view.
@export var lens: bool = true


func affects_channel(channel: int) -> bool:
	return (channel == 0 and position) or (channel == 1 and orientation) or (channel == 2 and lens)


func get_weight(owner_node: Node3D, player_position: Vector3) -> float:
	var reference: Node3D = owner_node.call("resolve_trait_node", reference_path) as Node3D
	if not is_instance_valid(reference):
		return 0.0
	var distance: float = reference.global_position.distance_to(player_position)
	var inner_radius: float = maxf(full_influence_distance, 0.0)
	var outer_radius: float = maxf(zero_influence_distance, 0.0)
	if outer_radius <= inner_radius:
		return 0.0
	var weight: float = clampf((outer_radius - distance) / (outer_radius - inner_radius), 0.0, 1.0)
	if falloff == Falloff.SMOOTHSTEP:
		weight = weight * weight * (3.0 - 2.0 * weight)
	return pow(weight, maxf(power, 0.01))

@tool
extends Resource
class_name CameraInfluenceTrait

enum Falloff { LINEAR, SMOOTHSTEP }
enum AxisSpace { WORLD, REFERENCE_LOCAL }

## Influence center relative to the constraint. Empty uses the constraint origin, independently of camera placement.
@export_node_path("Node3D") var reference_path: NodePath = NodePath("")
## Axes included in the influence distance. Ignored axes do not affect blending. X/Z excludes height; one axis creates a slab. None disables influence.
@export_flags("X", "Y", "Z") var effective_axes: int = 7
## Frame used by Effective Axes. Reference Local follows the influence reference's orientation without applying its scale.
@export var axis_space: AxisSpace = AxisSpace.WORLD
## Distance along Effective Axes within which the affected channels have full influence, in world units.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var full_influence_distance: float = 0.0
## Distance along Effective Axes at which influence reaches zero, in world units. Must exceed Full Influence Distance.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var zero_influence_distance: float = 100.0
## Curve applied between the full and zero influence distances.
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
	var axes: int = effective_axes & 7
	if not axes:
		return 0.0
	var reference: Node3D = owner_node.call("resolve_trait_node", reference_path) as Node3D
	if not is_instance_valid(reference):
		return 0.0
	var difference: Vector3 = player_position - reference.global_position
	if axes != 7:
		if axis_space == AxisSpace.REFERENCE_LOCAL:
			difference = reference.global_basis.orthonormalized().inverse() * difference
		for axis: int in 3:
			if not axes & (1 << axis):
				difference[axis] = 0.0
	var distance: float = difference.length()
	var inner_radius: float = maxf(full_influence_distance, 0.0)
	var outer_radius: float = maxf(zero_influence_distance, 0.0)
	if outer_radius <= inner_radius:
		return 0.0
	var weight: float = clampf((outer_radius - distance) / (outer_radius - inner_radius), 0.0, 1.0)
	if falloff == Falloff.SMOOTHSTEP:
		weight = weight * weight * (3.0 - 2.0 * weight)
	return pow(weight, maxf(power, 0.01))

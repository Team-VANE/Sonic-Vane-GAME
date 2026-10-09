@tool
extends Resource
class_name CameraOrientationTrait

enum Mode {
	## Aims at the player plus Target Offset.
	FACE_PLAYER,
	## Aims at the source node plus Target Offset.
	FACE_TARGET,
	## Follows the source marker's full world rotation.
	MARKER_ROTATION,
	## Uses the specified world-space Rotation Degrees.
	FIXED_ROTATION,
	## Adds Roll Degrees around the current viewing axis without replacing aim.
	ROLL,
	## Derives roll from the source marker relative to camera up, without replacing aim.
	MARKER_ROLL,
}
enum UpSource { CAMERA, WORLD, GRAVITY, PLAYER, MARKER }

## Aim, rotation, or roll behavior. Earlier traits override later traits on their selected axes. Unrestricted aim traits preserve the separate additive roll channel; axis-limited aim traits override lower-priority roll on their selected axes.
## [br][b]Face Player:[/b] Aims at the player plus Target Offset.
## [br][b]Face Target:[/b] Aims at the source node plus Target Offset.
## [br][b]Marker Rotation:[/b] Follows the source marker's full world rotation.
## [br][b]Fixed Rotation:[/b] Uses the specified world-space Rotation Degrees.
## [br][b]Roll:[/b] Adds Roll Degrees around the viewing axis without replacing aim.
## [br][b]Marker Roll:[/b] Derives roll from the source marker relative to camera up without replacing aim.
@export var mode: Mode = Mode.FACE_PLAYER:
	set(value):
		mode = value
		notify_property_list_changed()
## Aim target or orientation marker relative to the constraint.
@export var target_path: NodePath = NodePath("ConstraintPoint")
## Offset from the aim target; X and Z use world space.
@export var target_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
## Applies the vertical target offset along player up instead of gravity up.
@export var offset_uses_player_up: bool = false
## Up frame used for aiming.
@export var up_source: UpSource = UpSource.GRAVITY
## Rotates the orbit around its pivot before placing the camera.
@export var orbit_rig: bool = false
## Treats marker +Z as forward. Disable for Camera3D sources using -Z.
@export var marker_uses_guide_basis: bool = true
## Rotation used by Fixed Rotation, in degrees.
@export var rotation_degrees: Vector3 = Vector3.ZERO
## Roll around the viewing axis, in degrees.
@export_range(-180.0, 180.0, 0.1, "suffix:deg") var roll_degrees: float = 0.0
## Aim tracking response per second. Zero follows directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var tracking_response: float = 14.0
## Fraction of the desired aim rotation applied.
@export_range(0.0, 1.0, 0.01) var strength: float = 1.0

@export_group("Axis Limits")
## Restricts this trait's rotation to selected axes in the Axis Reference frame.
@export var limit_axes: bool = false:
	set(value):
		limit_axes = value
		notify_property_list_changed()
## Rotation components affected in the reference frame: X pitch, Y yaw, Z roll. Unselected components retain lower-priority traits or normal camera orientation.
@export_flags("X", "Y", "Z") var axis_mask: int = 7
## Node defining the rotation frame relative to the constraint. Empty uses world axes. Translation and scale do not affect the frame.
@export_node_path("Node3D") var axis_reference_path: NodePath = NodePath("")

## Runtime target or rotation marker for scripted cameras.
var target_node: Node3D = null
## Runtime up frame for scripted cameras. Zero uses Up Source.
var up_override: Vector3 = Vector3.ZERO

func _validate_property(property: Dictionary) -> void:
	var property_name: String = property["name"]
	var aim_mode: bool = mode in [Mode.FACE_PLAYER, Mode.FACE_TARGET]
	var marker_mode: bool = mode in [Mode.MARKER_ROTATION, Mode.MARKER_ROLL]
	var hidden: bool = false
	match property_name:
		"axis_mask", "axis_reference_path":
			hidden = not limit_axes
		"target_path":
			hidden = not marker_mode and mode != Mode.FACE_TARGET
		"target_offset", "offset_uses_player_up", "up_source":
			hidden = not aim_mode
		"marker_uses_guide_basis":
			hidden = not marker_mode
		"rotation_degrees":
			hidden = mode != Mode.FIXED_ROTATION
		"roll_degrees":
			hidden = mode != Mode.ROLL
		"orbit_rig", "strength":
			hidden = mode in [Mode.ROLL, Mode.MARKER_ROLL]
	if hidden:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR

func get_axis_basis(owner_node: Node3D) -> Basis:
	if axis_reference_path.is_empty():
		return Basis.IDENTITY
	var reference: Node3D = owner_node.call("resolve_trait_node", axis_reference_path) as Node3D
	return reference.global_basis.orthonormalized() if reference else Basis.IDENTITY

func get_source(owner_node: Node3D) -> Node3D:
	if is_instance_valid(target_node):
		return target_node
	return owner_node.call("resolve_trait_node", target_path) as Node3D

func get_transform(owner_node: Node3D) -> Transform3D:
	if target_path.is_empty() and not is_instance_valid(target_node):
		return owner_node.call("get_locked_transform") as Transform3D
	var source: Node3D = get_source(owner_node)
	return source.global_transform if source else owner_node.call("get_locked_transform") as Transform3D

func get_up(owner_node: Node3D, rig: Node3D) -> Vector3:
	if up_override.length_squared() > 0.000001:
		return up_override.normalized()
	match up_source:
		UpSource.WORLD:
			return Vector3.UP
		UpSource.GRAVITY:
			return rig.call("_get_target_gravity_up") as Vector3
		UpSource.PLAYER:
			return rig.call("_get_target_player_up") as Vector3
		UpSource.MARKER:
			return get_transform(owner_node).basis.y.normalized()
	return rig.call("_get_camera_up") as Vector3


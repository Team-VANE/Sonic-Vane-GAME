@tool
extends Resource
class_name CameraPositionTrait

enum Mode {
	## Places the camera at the source position plus Offset, without orbit distance.
	FIXED_CAMERA,
	## Places the orbit pivot at the source position plus Offset. The camera remains an orbit distance behind the pivot.
	FIXED_PIVOT,
	## Places the camera at the player's position plus Offset, without orbit distance.
	PLAYER_CAMERA,
	## Moves the orbit pivot with the player, then applies Offset and orbit distance.
	PLAYER_PIVOT,
	## Follows a source node's position plus Offset as the camera position. Currently equivalent to Fixed Camera.
	NODE_CAMERA,
	## Follows a source node's position plus Offset as the orbit pivot. Currently equivalent to Fixed Pivot.
	NODE_PIVOT,
	## Places the camera at the point on the source Path3D closest to the player, plus Offset.
	PATH_CAMERA,
}
enum OffsetSpace { WORLD, GRAVITY_UP, PLAYER_UP, SOURCE_LOCAL }

## Camera placement or orbit-pivot source. Camera modes set the camera position directly; pivot modes place the camera an orbit distance behind the pivot. Orientation and FOV use separate traits.
## [br][b]Fixed Camera:[/b] Source position plus Offset, without orbit distance.
## [br][b]Fixed Pivot:[/b] Source position plus Offset as the orbit center.
## [br][b]Player Camera:[/b] Player position plus Offset, without orbit distance.
## [br][b]Player Pivot:[/b] Player position plus Offset as the orbit center.
## [br][b]Node Camera:[/b] Follows a source node as the camera position. Currently equivalent to Fixed Camera.
## [br][b]Node Pivot:[/b] Follows a source node as the orbit center. Currently equivalent to Fixed Pivot.
## [br][b]Path Camera:[/b] Closest point on the source Path3D to the player, plus Offset.
@export var mode: Mode = Mode.FIXED_CAMERA:
	set(value):
		mode = value
		notify_property_list_changed()
## Position marker or Path3D relative to the constraint. Empty or unresolved paths use its locked transform or current origin. Assigned markers are sampled continuously, including in Fixed modes. Player modes use the player's position instead.
@export var source_path: NodePath = NodePath("ConstraintPoint")
## Offset from the selected position source.
@export var offset: Vector3 = Vector3.ZERO
## World, source-local, or world X/Z with the selected vertical up axis.
@export var offset_space: OffsetSpace = OffsetSpace.WORLD
## Position tracking response per second. Zero follows directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var tracking_response: float = 0.0

@export_group("Axis Limits")
## Restricts this trait to selected position axes. Earlier traits override later traits on their selected axes.
@export var limit_axes: bool = false:
	set(value):
		limit_axes = value
		notify_property_list_changed()
## Position axes affected in the Axis Reference frame. Unselected axes retain lower-priority traits or normal camera placement.
@export_flags("X", "Y", "Z") var axis_mask: int = 7
## Node defining the position axes relative to the constraint. Empty uses world axes. Translation and scale do not affect axis direction.
@export_node_path("Node3D") var axis_reference_path: NodePath = NodePath("")

## Runtime position source for scripted cameras.
var source_node: Node3D = null

func _validate_property(property: Dictionary) -> void:
	if property["name"] == "source_path" and mode in [Mode.PLAYER_CAMERA, Mode.PLAYER_PIVOT]:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR
	if not limit_axes and property["name"] in ["axis_mask", "axis_reference_path"]:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR

func get_axis_basis(owner_node: Node3D) -> Basis:
	if axis_reference_path.is_empty():
		return Basis.IDENTITY
	var reference: Node3D = owner_node.call("resolve_trait_node", axis_reference_path) as Node3D
	return reference.global_basis.orthonormalized() if reference else Basis.IDENTITY

func get_source(owner_node: Node3D) -> Node3D:
	if is_instance_valid(source_node):
		return source_node
	return owner_node.call("resolve_trait_node", source_path) as Node3D

func get_transform(owner_node: Node3D) -> Transform3D:
	if source_path.is_empty() and not is_instance_valid(source_node):
		return owner_node.call("get_locked_transform") as Transform3D
	var source: Node3D = get_source(owner_node)
	if source:
		return source.global_transform
	return owner_node.call("get_locked_transform") as Transform3D

func get_offset(rig: Node3D, source_basis: Basis) -> Vector3:
	match offset_space:
		OffsetSpace.GRAVITY_UP:
			return Vector3(offset.x, 0.0, offset.z) + (rig.call("_get_target_gravity_up") as Vector3) * offset.y
		OffsetSpace.PLAYER_UP:
			return Vector3(offset.x, 0.0, offset.z) + (rig.call("_get_target_player_up") as Vector3) * offset.y
		OffsetSpace.SOURCE_LOCAL:
			return source_basis.orthonormalized() * offset
	return offset


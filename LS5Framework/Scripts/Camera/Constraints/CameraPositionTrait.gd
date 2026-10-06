@tool
extends Resource
class_name CameraPositionTrait

enum Mode { FIXED_CAMERA, FIXED_PIVOT, PLAYER_CAMERA, PLAYER_PIVOT, NODE_CAMERA, NODE_PIVOT, PATH_CAMERA }
enum OffsetSpace { WORLD, GRAVITY_UP, PLAYER_UP, SOURCE_LOCAL }

## Camera placement or orbit-pivot source.
@export var mode: Mode = Mode.FIXED_CAMERA:
	set(value):
		mode = value
		notify_property_list_changed()
## Position marker or Path3D relative to the constraint. Empty uses its locked transform or origin.
@export var source_path: NodePath = NodePath("ConstraintPoint")
## Offset from the selected position source.
@export var offset: Vector3 = Vector3.ZERO
## World, source-local, or world X/Z with the selected vertical up axis.
@export var offset_space: OffsetSpace = OffsetSpace.WORLD
## Position tracking response per second. Zero follows directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var tracking_response: float = 0.0

## Runtime position source for scripted cameras.
var source_node: Node3D = null

func _validate_property(property: Dictionary) -> void:
	if property["name"] == "source_path" and mode in [Mode.PLAYER_CAMERA, Mode.PLAYER_PIVOT]:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR

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


@tool
extends Resource
class_name CameraLensTrait

enum Mode {
	## Applies the specified FOV.
	FIXED_FOV,
	## Blends Near FOV to Far FOV over the configured distance range.
	DISTANCE_FOV,
	## Sets the distance behind the orbit pivot. Direct camera-position modes ignore this distance.
	ORBIT_DISTANCE,
	## Copies FOV from a source Camera3D. Uses the specified FOV if the source is not a Camera3D.
	SOURCE_FOV,
}
enum DistanceSource { CAMERA_TO_PLAYER, MARKER_TO_PLAYER }

## Field of view or orbit-distance behavior. One FOV trait and one orbit-distance trait can be combined.
## [br][b]Fixed FOV:[/b] Applies the specified FOV.
## [br][b]Distance FOV:[/b] Blends Near FOV to Far FOV over the configured distance range.
## [br][b]Orbit Distance:[/b] Sets the distance behind the orbit pivot. Direct camera-position modes ignore this distance.
## [br][b]Source FOV:[/b] Copies FOV from a source Camera3D; other sources use the specified FOV as fallback.
@export var mode: Mode = Mode.FIXED_FOV:
	set(value):
		mode = value
		notify_property_list_changed()
## Field of view in degrees.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var fov: float = 70.0
## Orbit distance in meters.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var distance: float = 10.0
## Field of view at or inside Near Distance.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var near_fov: float = 70.0
## Field of view at or beyond Far Distance.
@export_range(1.0, 179.0, 0.1, "suffix:deg") var far_fov: float = 55.0
## Distance where Near FOV is fully applied.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var near_distance: float = 0.0
## Distance where Far FOV is fully applied.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var far_distance: float = 30.0
## Distance reference used by Distance FOV.
@export var distance_source: DistanceSource = DistanceSource.CAMERA_TO_PLAYER:
	set(value):
		distance_source = value
		notify_property_list_changed()
## Camera3D or distance-reference marker relative to the constraint.
@export var source_path: NodePath = NodePath("ConstraintPoint")
## Lens tracking response per second. Zero applies directly.
@export_range(0.0, 200.0, 0.1, "or_greater") var tracking_response: float = 0.0

## Runtime lens source for scripted cameras.
var source_node: Node3D = null

func _validate_property(property: Dictionary) -> void:
	var property_name: String = property["name"]
	var hidden: bool = false
	match property_name:
		"fov":
			hidden = mode not in [Mode.FIXED_FOV, Mode.SOURCE_FOV]
		"distance":
			hidden = mode != Mode.ORBIT_DISTANCE
		"near_fov", "far_fov", "near_distance", "far_distance", "distance_source":
			hidden = mode != Mode.DISTANCE_FOV
		"source_path":
			hidden = mode != Mode.SOURCE_FOV and not (mode == Mode.DISTANCE_FOV and distance_source == DistanceSource.MARKER_TO_PLAYER)
		"tracking_response":
			hidden = mode == Mode.ORBIT_DISTANCE
	if hidden:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR

func get_source(owner_node: Node3D) -> Node3D:
	if is_instance_valid(source_node):
		return source_node
	return owner_node.call("resolve_trait_node", source_path) as Node3D


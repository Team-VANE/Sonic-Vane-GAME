@tool
extends Resource
class_name CameraActivationTrait

enum Event { OCCUPANCY, ENTER, EXIT, REARM, DURATION, DISTANCE_EXIT }

## Activation or release rule for the camera target. Enter requires an outside-to-inside crossing after spawn or teleport; Occupancy also activates when spawning inside.
@export var event: Event = Event.OCCUPANCY:
	set(value):
		event = value
		notify_property_list_changed()
## Area relative to the constraint. An empty path uses the constraint's own Area3D.
@export var area_path: NodePath = NodePath("")
## Lifetime after activation, in seconds. Zero releases after entry completes.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var duration: float = 0.35
## Distance from the constraint origin that releases a latched camera.
@export_range(0.01, 10000.0, 0.1, "or_greater", "suffix:m") var exit_distance: float = 100.0
## Distance-exit reference relative to the constraint. Empty uses the constraint origin.
@export var reference_path: NodePath = NodePath("")

func _validate_property(property: Dictionary) -> void:
	var property_name: String = property["name"]
	if (property_name == "area_path" and event >= Event.DURATION) or (property_name == "duration" and event != Event.DURATION) or (property_name in ["exit_distance", "reference_path"] and event != Event.DISTANCE_EXIT):
		property["usage"] = PROPERTY_USAGE_NO_EDITOR


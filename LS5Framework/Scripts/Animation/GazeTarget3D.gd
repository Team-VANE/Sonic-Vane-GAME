@tool
extends Marker3D
class_name GazeTarget3D

const GAZE_TARGET_GROUP: StringName = &"gaze_targets"

@export_group("Gaze Target")
## Enables this target for automatic gaze selection.
@export var gaze_enabled: bool = true
## Selection priority. Higher-priority targets are preferred regardless of distance.
@export var gaze_priority: int = 0
## Maximum distance from a viewer. A value of 0 allows any distance.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var gaze_max_distance: float = 60.0
## Local offset used as the point the character looks toward.
@export var gaze_offset: Vector3 = Vector3.ZERO


func _enter_tree() -> void:
	if not is_in_group(GAZE_TARGET_GROUP):
		add_to_group(GAZE_TARGET_GROUP)


func get_gaze_position() -> Vector3:
	return global_position + global_basis * gaze_offset


func can_be_gazed_at(viewer: Node3D) -> bool:
	if not gaze_enabled or viewer == null or not is_instance_valid(viewer):
		return false
	if gaze_max_distance <= 0.0:
		return true
	return viewer.global_position.distance_squared_to(get_gaze_position()) <= gaze_max_distance * gaze_max_distance

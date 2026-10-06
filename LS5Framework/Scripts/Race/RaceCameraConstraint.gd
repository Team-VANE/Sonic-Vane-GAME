extends CameraConstraint
class_name RaceCameraConstraint

var position_trait: CameraPositionTrait = CameraPositionTrait.new()
var aim_trait: CameraOrientationTrait = CameraOrientationTrait.new()

func _init() -> void:
	constraint_priority = 9000
	disable_camera_controls = true
	suppress_speed_effects = true
	position_trait.mode = CameraPositionTrait.Mode.FIXED_PIVOT
	position_trait.source_path = NodePath("")
	aim_trait.mode = CameraOrientationTrait.Mode.MARKER_ROTATION
	aim_trait.target_path = NodePath("")
	aim_trait.orbit_rig = true
	aim_trait.tracking_response = 0.0
	position_traits.append(position_trait)
	orientation_traits.append(aim_trait)

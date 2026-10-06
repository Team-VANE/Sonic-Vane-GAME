extends CameraConstraint
class_name DeathCameraConstraint

var position_trait: CameraPositionTrait = CameraPositionTrait.new()
var aim_trait: CameraOrientationTrait = CameraOrientationTrait.new()
var lens_trait: CameraLensTrait = CameraLensTrait.new()

func _init() -> void:
	constraint_priority = 9999
	disable_camera_controls = true
	suppress_speed_effects = true
	position_trait.mode = CameraPositionTrait.Mode.FIXED_PIVOT
	position_trait.source_path = NodePath("")
	aim_trait.mode = CameraOrientationTrait.Mode.FACE_PLAYER
	lens_trait.mode = CameraLensTrait.Mode.DISTANCE_FOV
	lens_trait.near_fov = 55.0
	lens_trait.far_fov = 5.0
	lens_trait.far_distance = 130.0
	lens_trait.tracking_response = 8.0
	position_traits.append(position_trait)
	orientation_traits.append(aim_trait)
	lens_traits.append(lens_trait)

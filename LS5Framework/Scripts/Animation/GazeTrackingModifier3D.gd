extends SkeletonModifier3D
class_name GazeTrackingModifier3D

@export_group("Head Tracking")
## Bone receiving the procedural head rotation.
@export var head_bone_name: StringName = &"spine_06"
## Forward direction of the face in the head bone's animated local space.
@export var head_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
## Local axis used as the head's upward direction.
@export var head_up_axis: Vector3 = Vector3.UP
## Portion of horizontal target deviation applied to the head before clamping.
@export_range(0.0, 1.0, 0.01) var head_yaw_share: float = 0.72
## Portion of vertical target deviation applied to the head before clamping.
@export_range(0.0, 1.0, 0.01) var head_pitch_share: float = 0.72
## Maximum horizontal head rotation relative to the animated orientation.
@export_range(0.0, 180.0, 0.1, "radians_as_degrees") var head_yaw_limit: float = deg_to_rad(58.0)
## Maximum upward head rotation relative to the animated orientation.
@export_range(0.0, 180.0, 0.1, "radians_as_degrees") var head_pitch_up_limit: float = deg_to_rad(32.0)
## Maximum downward head rotation relative to the animated orientation.
@export_range(0.0, 180.0, 0.1, "radians_as_degrees") var head_pitch_down_limit: float = deg_to_rad(26.0)
## Response speed used to ease the head toward its constrained gaze rotation. A value of 0 applies it immediately.
@export_range(0.0, 100.0, 0.1) var head_rotation_lerp_speed: float = 9.0
## Lateral deadzone used to choose a stable turn side when the target is behind the animated head.
@export_range(0.0, 1.0, 0.001) var rear_yaw_side_deadzone: float = 0.025

@export_group("Facial Gaze")
## AnimationPlayer containing the directional facial pose animations.
@export var facial_animation_player: AnimationPlayer
## Neutral facial pose used as the additive reference for brow and cheek bones.
@export var forward_animation: StringName = &"EYES_Forward"
## Facial pose used for targets above the face.
@export var up_animation: StringName = &"EYES_Up"
## Facial pose used for targets below the face.
@export var down_animation: StringName = &"EYES_Down"
## Facial pose used for targets to the face's left.
@export var left_animation: StringName = &"EYES_Left"
## Facial pose used for targets to the face's right.
@export var right_animation: StringName = &"EYES_Right"
## Horizontal residual angle that produces full eye-pose displacement.
@export_range(0.1, 90.0, 0.1, "radians_as_degrees") var eye_yaw_limit: float = deg_to_rad(24.0)
## Vertical residual angle that produces full eye-pose displacement.
@export_range(0.1, 90.0, 0.1, "radians_as_degrees") var eye_pitch_limit: float = deg_to_rad(16.0)
## Target deviation where directional facial poses begin blending in.
@export_range(0.0, 180.0, 0.1, "radians_as_degrees") var eye_blend_start_angle: float = deg_to_rad(12.0)
## Target deviation where directional facial poses reach their calculated weight.
@export_range(0.1, 180.0, 0.1, "radians_as_degrees") var eye_blend_full_angle: float = deg_to_rad(42.0)
## Bone-name prefixes sampled as absolute transforms from the facial poses.
@export var absolute_eye_bone_prefixes: PackedStringArray = PackedStringArray(["ROT-eye", "CTRL-eyeShine", "MCH-EyeShine", "DEF_eye_", "DEF-eyeShine", "CTRL-Eye"])
## Bone-name prefixes applied additively relative to the forward facial pose.
@export var additive_face_bone_prefixes: PackedStringArray = PackedStringArray(["DEF-brow", "DEF-browMuzzle", "TWK-Cheek", "DEF-cheek"])

var target_global_position: Vector3 = Vector3.ZERO
var tracking_active: bool = false
var _head_bone: int = -1
var _head_parent_bone: int = -1
var _absolute_eye_bones: PackedInt32Array = PackedInt32Array()
var _additive_face_bones: PackedInt32Array = PackedInt32Array()
var _pose_cache: Dictionary = {}
var _cached_player_id: int = 0
var _smoothed_head_yaw: float = 0.0
var _smoothed_head_pitch: float = 0.0
var _head_smoothing_valid: bool = false
var _rear_yaw_sign: float = 0.0


func _ready() -> void:
	_cache_bones()


func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not tracking_active:
		_head_smoothing_valid = false
		_rear_yaw_sign = 0.0
		return
	if skeleton == null or _head_bone < 0:
		return
	if facial_animation_player != null and facial_animation_player.get_instance_id() != _cached_player_id:
		_pose_cache.clear()
		_cached_player_id = facial_animation_player.get_instance_id()

	var head_pose: Transform3D = skeleton.get_bone_global_pose(_head_bone)
	var target_skeleton_position: Vector3 = skeleton.global_transform.affine_inverse() * target_global_position
	var target_direction: Vector3 = target_skeleton_position - head_pose.origin
	if target_direction.length_squared() <= 0.000001:
		return
	var head_basis: Basis = head_pose.basis.orthonormalized()
	var forward: Vector3 = (head_basis * head_forward_axis.normalized()).normalized()
	var up: Vector3 = (head_basis * head_up_axis.normalized()).normalized()
	var right: Vector3 = up.cross(forward).normalized()
	if right.length_squared() <= 0.000001:
		return
	up = forward.cross(right).normalized()
	var direction: Vector3 = target_direction.normalized()
	var forward_amount: float = direction.dot(forward)
	var raw_desired_yaw: float = atan2(direction.dot(right), forward_amount)
	var desired_yaw: float = _resolve_desired_yaw(skeleton, direction, forward_amount, raw_desired_yaw)
	var desired_pitch: float = atan2(direction.dot(up), sqrt(max(1.0 - direction.dot(up) * direction.dot(up), 0.0)))
	var target_yaw: float = clamp(desired_yaw * head_yaw_share, -head_yaw_limit, head_yaw_limit)
	var target_pitch: float = clamp(desired_pitch * head_pitch_share, -head_pitch_down_limit, head_pitch_up_limit)
	if not _head_smoothing_valid:
		_smoothed_head_yaw = 0.0
		_smoothed_head_pitch = 0.0
		_head_smoothing_valid = true
	if head_rotation_lerp_speed <= 0.0:
		_smoothed_head_yaw = target_yaw
		_smoothed_head_pitch = target_pitch
	else:
		var head_blend: float = 1.0 - exp(-head_rotation_lerp_speed * max(delta, 0.0))
		_smoothed_head_yaw = lerpf(_smoothed_head_yaw, target_yaw, head_blend)
		_smoothed_head_pitch = lerpf(_smoothed_head_pitch, target_pitch, head_blend)
	var applied_yaw: float = _smoothed_head_yaw
	var applied_pitch: float = _smoothed_head_pitch
	_apply_head_rotation(skeleton, applied_yaw, applied_pitch)

	var deviation: float = max(abs(desired_yaw), abs(desired_pitch))
	var eye_blend_range: float = max(eye_blend_full_angle - eye_blend_start_angle, 0.0001)
	var eye_weight: float = smoothstep(0.0, 1.0, clamp((deviation - eye_blend_start_angle) / eye_blend_range, 0.0, 1.0))
	var residual_yaw: float = desired_yaw - applied_yaw
	var residual_pitch: float = desired_pitch - applied_pitch
	var gaze_blend: Vector2 = Vector2(
		clamp(residual_yaw / max(eye_yaw_limit, 0.0001), -1.0, 1.0),
		clamp(residual_pitch / max(eye_pitch_limit, 0.0001), -1.0, 1.0)
	) * eye_weight
	_apply_facial_pose(skeleton, gaze_blend)


func _apply_head_rotation(skeleton: Skeleton3D, yaw: float, pitch: float) -> void:
	var base_rotation: Quaternion = skeleton.get_bone_pose_rotation(_head_bone)
	var local_yaw: Quaternion = Quaternion(head_up_axis.normalized(), yaw)
	var local_right: Vector3 = head_up_axis.normalized().cross(head_forward_axis.normalized()).normalized()
	if local_right.length_squared() <= 0.000001:
		return
	var local_pitch: Quaternion = Quaternion(local_right, -pitch)
	skeleton.set_bone_pose_rotation(_head_bone, (base_rotation * local_yaw * local_pitch).normalized())


func _resolve_desired_yaw(skeleton: Skeleton3D, direction: Vector3, head_forward_amount: float, raw_desired_yaw: float) -> float:
	if head_forward_amount >= 0.0 or _head_parent_bone < 0:
		_rear_yaw_sign = 0.0
		return raw_desired_yaw
	var parent_basis: Basis = skeleton.get_bone_global_pose(_head_parent_bone).basis.orthonormalized()
	var reference_basis: Basis = (parent_basis * skeleton.get_bone_rest(_head_bone).basis).orthonormalized()
	var parent_forward: Vector3 = (reference_basis * head_forward_axis.normalized()).normalized()
	var parent_up: Vector3 = (reference_basis * head_up_axis.normalized()).normalized()
	var parent_right: Vector3 = parent_up.cross(parent_forward).normalized()
	if parent_right.length_squared() <= 0.0001:
		return raw_desired_yaw
	var parent_side_amount: float = direction.dot(parent_right)
	if abs(parent_side_amount) > rear_yaw_side_deadzone:
		_rear_yaw_sign = signf(parent_side_amount)
	elif is_zero_approx(_rear_yaw_sign):
		_rear_yaw_sign = signf(raw_desired_yaw)
	return abs(raw_desired_yaw) * _rear_yaw_sign


func _apply_facial_pose(skeleton: Skeleton3D, gaze_blend: Vector2) -> void:
	if facial_animation_player == null:
		return
	var forward_pose: Dictionary = _get_animation_pose(forward_animation)
	if forward_pose.is_empty():
		return
	var horizontal_name: StringName = left_animation if gaze_blend.x >= 0.0 else right_animation
	var vertical_name: StringName = up_animation if gaze_blend.y >= 0.0 else down_animation
	var horizontal_pose: Dictionary = _get_animation_pose(horizontal_name)
	var vertical_pose: Dictionary = _get_animation_pose(vertical_name)
	var horizontal_weight: float = abs(gaze_blend.x)
	var vertical_weight: float = abs(gaze_blend.y)

	for bone_index: int in _absolute_eye_bones:
		var bone_name: StringName = skeleton.get_bone_name(bone_index)
		if not forward_pose.has(bone_name):
			continue
		var blended_pose: Transform3D = _blend_directional_pose(
			forward_pose[bone_name],
			horizontal_pose.get(bone_name, forward_pose[bone_name]),
			vertical_pose.get(bone_name, forward_pose[bone_name]),
			horizontal_weight,
			vertical_weight
		)
		skeleton.set_bone_pose_position(bone_index, blended_pose.origin)
		skeleton.set_bone_pose_rotation(bone_index, blended_pose.basis.get_rotation_quaternion().normalized())
		skeleton.set_bone_pose_scale(bone_index, blended_pose.basis.get_scale())

	for bone_index: int in _additive_face_bones:
		var bone_name: StringName = skeleton.get_bone_name(bone_index)
		if not forward_pose.has(bone_name):
			continue
		var neutral: Transform3D = forward_pose[bone_name]
		var directional: Transform3D = _blend_directional_pose(
			neutral,
			horizontal_pose.get(bone_name, neutral),
			vertical_pose.get(bone_name, neutral),
			horizontal_weight,
			vertical_weight
		)
		var base_position: Vector3 = skeleton.get_bone_pose_position(bone_index)
		var base_rotation: Quaternion = skeleton.get_bone_pose_rotation(bone_index)
		var base_scale: Vector3 = skeleton.get_bone_pose_scale(bone_index)
		var neutral_rotation: Quaternion = neutral.basis.get_rotation_quaternion().normalized()
		var directional_rotation: Quaternion = directional.basis.get_rotation_quaternion().normalized()
		var rotation_delta: Quaternion = neutral_rotation.inverse() * directional_rotation
		var neutral_scale: Vector3 = neutral.basis.get_scale()
		var directional_scale: Vector3 = directional.basis.get_scale()
		var scale_delta: Vector3 = Vector3(
			directional_scale.x / max(abs(neutral_scale.x), 0.0001),
			directional_scale.y / max(abs(neutral_scale.y), 0.0001),
			directional_scale.z / max(abs(neutral_scale.z), 0.0001)
		)
		skeleton.set_bone_pose_position(bone_index, base_position + directional.origin - neutral.origin)
		skeleton.set_bone_pose_rotation(bone_index, (base_rotation * rotation_delta).normalized())
		skeleton.set_bone_pose_scale(bone_index, base_scale * scale_delta)


func _blend_directional_pose(neutral: Transform3D, horizontal: Transform3D, vertical: Transform3D, horizontal_weight: float, vertical_weight: float) -> Transform3D:
	var total_directional_weight: float = horizontal_weight + vertical_weight
	if total_directional_weight <= 0.0001:
		return neutral
	var neutral_weight: float = max(1.0 - total_directional_weight, 0.0)
	var total_weight: float = neutral_weight + total_directional_weight
	var horizontal_normalized: float = horizontal_weight / total_weight
	var vertical_normalized: float = vertical_weight / total_weight
	var neutral_normalized: float = neutral_weight / total_weight
	var position: Vector3 = neutral.origin * neutral_normalized + horizontal.origin * horizontal_normalized + vertical.origin * vertical_normalized
	var scale: Vector3 = neutral.basis.get_scale() * neutral_normalized + horizontal.basis.get_scale() * horizontal_normalized + vertical.basis.get_scale() * vertical_normalized
	var neutral_rotation: Quaternion = neutral.basis.get_rotation_quaternion().normalized()
	var horizontal_rotation: Quaternion = horizontal.basis.get_rotation_quaternion().normalized()
	var vertical_rotation: Quaternion = vertical.basis.get_rotation_quaternion().normalized()
	var directional_mix: float = vertical_weight / max(total_directional_weight, 0.0001)
	var directional_rotation: Quaternion = horizontal_rotation.slerp(vertical_rotation, directional_mix).normalized()
	var directional_amount: float = clamp(total_directional_weight, 0.0, 1.0)
	var rotation: Quaternion = neutral_rotation.slerp(directional_rotation, directional_amount).normalized()
	return Transform3D(Basis(rotation).scaled(scale), position)


func _get_animation_pose(animation_name: StringName) -> Dictionary:
	if _pose_cache.has(animation_name):
		return _pose_cache[animation_name]
	var animation: Animation = _resolve_animation(animation_name)
	if animation == null:
		_pose_cache[animation_name] = {}
		return {}
	var required_bones: Dictionary = {}
	for bone_index: int in _absolute_eye_bones:
		required_bones[get_skeleton().get_bone_name(bone_index)] = true
	for bone_index: int in _additive_face_bones:
		required_bones[get_skeleton().get_bone_name(bone_index)] = true
	var components: Dictionary = {}
	for track_index: int in range(animation.get_track_count()):
		var track_path: NodePath = animation.track_get_path(track_index)
		if track_path.get_subname_count() <= 0:
			continue
		var bone_name: StringName = StringName(track_path.get_subname(track_path.get_subname_count() - 1))
		if not required_bones.has(bone_name):
			continue
		if not components.has(bone_name):
			components[bone_name] = {
				"position": get_skeleton().get_bone_rest(get_skeleton().find_bone(bone_name)).origin,
				"rotation": get_skeleton().get_bone_rest(get_skeleton().find_bone(bone_name)).basis.get_rotation_quaternion(),
				"scale": get_skeleton().get_bone_rest(get_skeleton().find_bone(bone_name)).basis.get_scale(),
			}
		var track_type: int = animation.track_get_type(track_index)
		if track_type == Animation.TYPE_POSITION_3D:
			components[bone_name]["position"] = animation.position_track_interpolate(track_index, 0.0)
		elif track_type == Animation.TYPE_ROTATION_3D:
			components[bone_name]["rotation"] = animation.rotation_track_interpolate(track_index, 0.0)
		elif track_type == Animation.TYPE_SCALE_3D:
			components[bone_name]["scale"] = animation.scale_track_interpolate(track_index, 0.0)
	var pose: Dictionary = {}
	for bone_name: StringName in components:
		var component: Dictionary = components[bone_name]
		pose[bone_name] = Transform3D(Basis(component["rotation"]).scaled(component["scale"]), component["position"])
	_pose_cache[animation_name] = pose
	return pose


func _resolve_animation(animation_name: StringName) -> Animation:
	if facial_animation_player == null:
		return null
	var animation: Animation = facial_animation_player.get_animation(animation_name)
	if animation != null:
		return animation
	for available_name: StringName in facial_animation_player.get_animation_list():
		if String(available_name).get_file() == String(animation_name):
			return facial_animation_player.get_animation(available_name)
	return null


func _cache_bones() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	_head_bone = skeleton.find_bone(head_bone_name)
	_head_parent_bone = skeleton.get_bone_parent(_head_bone) if _head_bone >= 0 else -1
	_absolute_eye_bones.clear()
	_additive_face_bones.clear()
	for bone_index: int in range(skeleton.get_bone_count()):
		var bone_name: String = String(skeleton.get_bone_name(bone_index))
		if _matches_prefix(bone_name, absolute_eye_bone_prefixes):
			_absolute_eye_bones.append(bone_index)
		elif _matches_prefix(bone_name, additive_face_bone_prefixes):
			_additive_face_bones.append(bone_index)


func _matches_prefix(bone_name: String, prefixes: PackedStringArray) -> bool:
	for prefix: String in prefixes:
		if bone_name.begins_with(prefix):
			return true
	return false


func has_valid_head_bone() -> bool:
	return _head_bone >= 0 and get_skeleton() != null


func get_debug_head_global_position() -> Vector3:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or _head_bone < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(_head_bone).origin


func get_debug_head_forward_global() -> Vector3:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or _head_bone < 0:
		return Vector3.ZERO
	var head_basis: Basis = skeleton.get_bone_global_pose(_head_bone).basis.orthonormalized()
	return (skeleton.global_basis * (head_basis * head_forward_axis.normalized())).normalized()


func get_debug_absolute_eye_bone_count() -> int:
	return _absolute_eye_bones.size()


func get_debug_additive_face_bone_count() -> int:
	return _additive_face_bones.size()


func get_debug_directional_pose_counts() -> PackedInt32Array:
	return PackedInt32Array([
		_get_animation_pose(forward_animation).size(),
		_get_animation_pose(up_animation).size(),
		_get_animation_pose(down_animation).size(),
		_get_animation_pose(left_animation).size(),
		_get_animation_pose(right_animation).size(),
	])

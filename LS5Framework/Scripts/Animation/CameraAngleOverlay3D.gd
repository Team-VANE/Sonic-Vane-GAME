class_name CameraAngleOverlay3D
extends SkeletonModifier3D

const PresentationRoutes = preload("res://LS5Framework/Scripts/Animation/AnimationTreePresentationRoutes.gd")

@export_group("Node References")
## AnimationTree whose active resource names control overlay permission.
@export_node_path("AnimationTree") var animation_tree_path: NodePath
## AnimationPlayer supplying the directional poses and neutral reference.
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
## Viewing camera. The skeleton viewport's current camera is used when empty.
@export_node_path("Camera3D") var camera_path: NodePath

@export_group("Head Reference")
## Animated bone defining the viewing origin and orientation.
@export var head_bone_name: StringName
## Face-forward direction in the head bone's local space.
@export var head_forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
## Upward direction in the head bone's local space.
@export var head_up_axis: Vector3 = Vector3.UP

@export_group("Overlay Poses")
## Pose applied when the camera is on the head's left side.
@export var left_animation: StringName
## Pose applied when the camera is on the head's right side.
@export var right_animation: StringName
## Neutral pose subtracted from both overlays. Missing tracks use the bone rest pose.
@export var reference_animation: StringName = &"RESET"
## Time sampled from both directional animations.
@export_range(0.0, 60.0, 0.001, "or_greater", "suffix:s") var pose_time: float = 0.0
## Bone roots receiving pose deltas. Empty roots leave the overlay inactive.
@export var bone_roots: Array[StringName] = []
## Includes descendants of the configured bone roots.
@export var include_child_bones: bool = true
## Exchanges the poses assigned to the two viewing sides.
@export var swap_sides: bool = false
## Maximum pose displacement before the modifier's influence is applied.
@export_range(0.0, 1.0, 0.01) var strength: float = 1.0

@export_group("Viewing Angles")
## Horizontal angle where the overlay starts fading toward a side view.
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var yaw_fade_start: float = deg_to_rad(40.0)
## Horizontal angle where the overlay is fully suppressed.
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var yaw_fade_end: float = deg_to_rad(85.0)
## Vertical angle where the overlay starts fading above or below the head.
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var pitch_fade_start: float = deg_to_rad(20.0)
## Vertical angle where the overlay is fully suppressed.
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var pitch_fade_end: float = deg_to_rad(60.0)
## Angle past the head's center line required to change sides. The previous side is held inside this band.
@export_range(0.0, 30.0, 0.1, "radians_as_degrees") var crossover_deadzone: float = deg_to_rad(4.0)
## Response speed for pose changes and activation fades. Zero applies changes immediately.
@export_range(0.0, 100.0, 0.1) var blend_speed: float = 12.0

@export_group("Animation Permission")
## Resource-name prefix for permission arguments, such as `_camera-overlay-enabled=true`. Child state arguments override their parent states.
@export var animation_resource_marker: String = "_camera-overlay"
## Permission used when the active animation route has no overlay argument.
@export var enabled_by_default: bool = false

var _animation_tree: AnimationTree
var _animation_player: AnimationPlayer
var _camera: Camera3D
var _head_bone: int = -1
var _side: int = 0
var _weights: Vector2 = Vector2.ZERO
var _left_deltas: Dictionary = {}
var _right_deltas: Dictionary = {}
var _overlay_bones: Array[int] = []
var _routes: Array[Dictionary] = []
var _cached_root: AnimationRootNode
var _routes_dirty: bool = true
var _poses_dirty: bool = true
## Camera used by the photo session.
var _photo_camera: Camera3D
var _photo_live: bool = true
var _photo_delta: float = 0.0


func set_photo_view(camera: Camera3D, live: bool) -> void:
	_photo_camera = camera
	_photo_live = live
	_photo_delta = 0.0


func refresh_photo_view(delta: float) -> void:
	if active and _photo_live and is_instance_valid(_photo_camera) and get_skeleton():
		_photo_delta = delta
		get_skeleton().advance(0.0)


func _ready() -> void:
	refresh_configuration()


func _exit_tree() -> void:
	_disconnect_resources()


func refresh_configuration() -> void:
	_disconnect_resources()
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree if animation_tree_path else null
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer if animation_player_path else null
	_camera = get_node_or_null(camera_path) as Camera3D if camera_path else null
	var skeleton: Skeleton3D = get_skeleton()
	_head_bone = skeleton.find_bone(head_bone_name) if skeleton else -1
	_side = 0
	_weights = Vector2.ZERO
	_routes_dirty = true
	_poses_dirty = true
	if _animation_player:
		_animation_player.animation_libraries_updated.connect(_invalidate_poses)
	_sync_tree_root()


func _disconnect_resources() -> void:
	if is_instance_valid(_cached_root) and _cached_root.changed.is_connected(_invalidate_routes):
		_cached_root.changed.disconnect(_invalidate_routes)
	if is_instance_valid(_animation_player) and _animation_player.animation_libraries_updated.is_connected(_invalidate_poses):
		_animation_player.animation_libraries_updated.disconnect(_invalidate_poses)
	_cached_root = null


func _invalidate_routes() -> void:
	_routes_dirty = true


func _invalidate_poses() -> void:
	_poses_dirty = true


func _sync_tree_root() -> void:
	var tree_root: AnimationRootNode = _animation_tree.tree_root if is_instance_valid(_animation_tree) else null
	if tree_root == _cached_root:
		return
	if is_instance_valid(_cached_root) and _cached_root.changed.is_connected(_invalidate_routes):
		_cached_root.changed.disconnect(_invalidate_routes)
	_cached_root = tree_root
	if _cached_root:
		_cached_root.changed.connect(_invalidate_routes)
	_routes_dirty = true


func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton or _head_bone < 0 or not is_instance_valid(_animation_player):
		return
	_sync_tree_root()
	if _routes_dirty:
		_routes.clear()
		if _cached_root and animation_resource_marker:
			_collect_routes(_cached_root, "parameters", [])
		_routes_dirty = false
	if _poses_dirty:
		_cache_pose_deltas(skeleton)
		_poses_dirty = false
	if is_instance_valid(_photo_camera) and not _photo_live:
		if not _weights.is_zero_approx():
			_apply_pose_deltas(skeleton)
		return
	var target: Vector2 = Vector2.ZERO
	var camera: Camera3D = _camera if is_instance_valid(_camera) else skeleton.get_viewport().get_camera_3d()
	if is_instance_valid(_photo_camera):
		camera = _photo_camera
		delta = maxf(delta, _photo_delta)
		_photo_delta = 0.0
	if camera and is_instance_valid(_animation_tree) and _animation_tree.active and _is_overlay_allowed():
		var head: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(_head_bone)
		var direction: Vector3 = camera.global_position - head.origin
		if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			direction = camera.global_basis.z
		if direction.length_squared() > 0.000001:
			var local_direction: Vector3 = head.basis.orthonormalized().inverse() * direction.normalized()
			target = _get_view_weights(local_direction) * strength
	var blend: float = 1.0 if blend_speed <= 0.0 else 1.0 - exp(-blend_speed * maxf(delta, 0.0))
	_weights = _weights.lerp(target, blend)
	if _weights.length_squared() < 0.00000001:
		_weights = Vector2.ZERO
		return
	_apply_pose_deltas(skeleton)


func _get_view_weights(direction: Vector3) -> Vector2:
	var forward: Vector3 = head_forward_axis.normalized()
	var right: Vector3 = forward.cross(head_up_axis).normalized()
	if not forward or not right:
		return Vector2.ZERO
	var up: Vector3 = right.cross(forward).normalized()
	var front: float = direction.dot(forward)
	if front <= 0.0:
		return Vector2.ZERO
	var yaw: float = atan2(direction.dot(right), front)
	var pitch: float = asin(clampf(direction.dot(up), -1.0, 1.0))
	var amount: float = _angle_falloff(absf(yaw), yaw_fade_start, yaw_fade_end)
	amount *= _angle_falloff(absf(pitch), pitch_fade_start, pitch_fade_end)
	if amount <= 0.0:
		return Vector2.ZERO
	if _side == 0 or absf(yaw) > crossover_deadzone:
		_side = -1 if yaw <= 0.0 else 1
	var pose_side: int = -_side if swap_sides else _side
	return Vector2(amount, 0.0) if pose_side < 0 else Vector2(0.0, amount)


func _angle_falloff(angle: float, fade_start: float, fade_end: float) -> float:
	var end: float = clampf(fade_end, 0.0, PI * 0.5)
	var start: float = clampf(fade_start, 0.0, end)
	if end - start <= 0.00001:
		return 1.0 if angle < end else 0.0
	return 1.0 - smoothstep(start, end, angle)


func _cache_pose_deltas(skeleton: Skeleton3D) -> void:
	var selected: Dictionary = {}
	for bone_name: StringName in bone_roots:
		var bone: int = skeleton.find_bone(bone_name)
		if bone < 0:
			push_warning("Camera overlay bone '%s' was not found." % bone_name)
			continue
		selected[bone] = true
		if include_child_bones:
			_collect_bones(skeleton, bone, selected)
	var reference: Animation = _resolve_animation(reference_animation)
	_left_deltas = _sample_deltas(skeleton, _resolve_animation(left_animation), reference, selected)
	_right_deltas = _sample_deltas(skeleton, _resolve_animation(right_animation), reference, selected)
	_overlay_bones.clear()
	for bone: int in selected:
		if _left_deltas.has(bone) or _right_deltas.has(bone):
			_overlay_bones.append(bone)


func _collect_bones(skeleton: Skeleton3D, bone: int, selected: Dictionary) -> void:
	for child: int in skeleton.get_bone_children(bone):
		selected[child] = true
		_collect_bones(skeleton, child, selected)


func _resolve_animation(animation_name: StringName) -> Animation:
	if not animation_name:
		return null
	if _animation_player.has_animation(animation_name):
		return _animation_player.get_animation(animation_name)
	for available: StringName in _animation_player.get_animation_list():
		if String(available).get_file() == String(animation_name):
			return _animation_player.get_animation(available)
	push_warning("Camera overlay animation '%s' was not found." % animation_name)
	return null


func _sample_deltas(skeleton: Skeleton3D, animation: Animation, reference: Animation, selected: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not animation:
		return result
	var root: Node = _animation_player.get_node(_animation_player.root_node)
	for track: int in animation.get_track_count():
		var path: NodePath = animation.track_get_path(track)
		if not animation.track_is_enabled(track) or not animation.track_get_key_count(track) or path.get_subname_count() != 1:
			continue
		if root.get_node_or_null(NodePath(path.get_concatenated_names())) != skeleton:
			continue
		var bone: int = skeleton.find_bone(path.get_subname(0))
		if not selected.has(bone):
			continue
		var type: int = animation.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var neutral_track: int = reference.find_track(path, type) if reference else -1
		if neutral_track >= 0 and not reference.track_get_key_count(neutral_track):
			neutral_track = -1
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		if not result.has(bone):
			result[bone] = {"position": Vector3.ZERO, "rotation": Quaternion.IDENTITY, "scale": Vector3.ONE}
		if type == Animation.TYPE_POSITION_3D:
			var neutral: Vector3 = reference.position_track_interpolate(neutral_track, 0.0) if neutral_track >= 0 else rest.origin
			var position: Vector3 = animation.position_track_interpolate(track, minf(pose_time, animation.length))
			result[bone]["position"] = position - neutral
		elif type == Animation.TYPE_ROTATION_3D:
			var neutral: Quaternion = reference.rotation_track_interpolate(neutral_track, 0.0) if neutral_track >= 0 else rest.basis.get_rotation_quaternion()
			var rotation: Quaternion = animation.rotation_track_interpolate(track, minf(pose_time, animation.length))
			result[bone]["rotation"] = (neutral.inverse() * rotation).normalized()
		elif type == Animation.TYPE_SCALE_3D:
			var neutral: Vector3 = reference.scale_track_interpolate(neutral_track, 0.0) if neutral_track >= 0 else rest.basis.get_scale()
			var scale: Vector3 = animation.scale_track_interpolate(track, minf(pose_time, animation.length))
			result[bone]["scale"] = Vector3(scale.x / neutral.x if absf(neutral.x) > 0.00001 else 1.0, scale.y / neutral.y if absf(neutral.y) > 0.00001 else 1.0, scale.z / neutral.z if absf(neutral.z) > 0.00001 else 1.0)
	for bone: int in result.keys():
		var pose: Dictionary = result[bone]
		var rotation: Quaternion = pose["rotation"]
		if (pose["position"] as Vector3).is_zero_approx() and _is_identity_rotation(rotation) and (pose["scale"] as Vector3).is_equal_approx(Vector3.ONE):
			result.erase(bone)
	return result


func _is_identity_rotation(rotation: Quaternion) -> bool:
	return Vector3(rotation.x, rotation.y, rotation.z).is_zero_approx()


func _apply_pose_deltas(skeleton: Skeleton3D) -> void:
	var total: float = _weights.x + _weights.y
	var side_blend: float = _weights.y / total
	var identity: Dictionary = {"position": Vector3.ZERO, "rotation": Quaternion.IDENTITY, "scale": Vector3.ONE}
	for bone: int in _overlay_bones:
		var left: Dictionary = _left_deltas.get(bone, identity)
		var right: Dictionary = _right_deltas.get(bone, identity)
		var position: Vector3 = (left["position"] as Vector3).lerp(right["position"], side_blend) * total
		var rotation: Quaternion = (left["rotation"] as Quaternion).slerp(right["rotation"], side_blend)
		rotation = Quaternion.IDENTITY.slerp(rotation, total)
		var scale: Vector3 = Vector3.ONE.lerp((left["scale"] as Vector3).lerp(right["scale"], side_blend), total)
		if not position.is_zero_approx():
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone) + position)
		if not _is_identity_rotation(rotation):
			skeleton.set_bone_pose_rotation(bone, (skeleton.get_bone_pose_rotation(bone) * rotation).normalized())
		if not scale.is_equal_approx(Vector3.ONE):
			skeleton.set_bone_pose_scale(bone, skeleton.get_bone_pose_scale(bone) * scale)


func _collect_routes(node: AnimationNode, path: String, conditions: Array) -> void:
	var argument_key: String = animation_resource_marker.to_lower() + "-enabled"
	for argument: String in node.resource_name.split(";", false):
		var assignment: PackedStringArray = argument.strip_edges().to_lower().split("=", true, 1)
		if assignment.size() == 2 and assignment[0].strip_edges() == argument_key:
			var value: String = assignment[1].strip_edges()
			if value in ["true", "1", "yes", "on", "false", "0", "no", "off"]:
				_routes.append({"conditions": conditions.duplicate(), "enabled": value in ["true", "1", "yes", "on"]})
	if node is AnimationNodeStateMachine:
		for state: StringName in node.get_node_list():
			var child_conditions: Array = conditions.duplicate()
			child_conditions.append({"path": path + "/playback", "state": state})
			_collect_routes(node.get_node(state), path + "/" + String(state), child_conditions)
	elif node is AnimationNodeBlendTree:
		for child: StringName in node.get_node_list():
			_collect_routes(node.get_node(child), path + "/" + String(child), PresentationRoutes.child_conditions(node, path, child, conditions))
	elif node is AnimationNodeBlendSpace1D or node is AnimationNodeBlendSpace2D:
		for point: int in node.get_blend_point_count():
			_collect_routes(node.get_blend_point_node(point), path, conditions)


func _is_overlay_allowed() -> bool:
	var allowed: bool = enabled_by_default
	for route: Dictionary in _routes:
		var matched: bool = true
		for condition: Dictionary in route["conditions"]:
			if condition.has("selector_path"):
				if not PresentationRoutes.selector_matches(_animation_tree, condition):
					matched = false
					break
				continue
			var playback: AnimationNodeStateMachinePlayback = _animation_tree.get(condition["path"]) as AnimationNodeStateMachinePlayback
			if not playback or playback.get_current_node() != condition["state"]:
				matched = false
				break
		if matched:
			allowed = route["enabled"]
	return allowed

@tool
extends Resource
class_name LipSyncProfile

## Scene instantiated by the character preview.
@export var preview_scene: PackedScene
## Bone centered by the character preview camera.
@export var preview_focus_bone: StringName = &"head"
## Preview camera offset from the focus bone.
@export var preview_focus_offset: Vector3 = Vector3(0.0, 0.1, 0.35)
## Preview camera distance from the focus point.
@export var preview_distance: float = 2.2
## Default absolute mouth pose used when no viseme cue is active.
@export var silent_viseme_id: StringName = &"VIS_SILENT"
## Character-specific mouth poses and their animation mappings.
@export var visemes: Array[LipSyncPose] = []
## Character-specific additive expressions and their animation mappings.
@export var expressions: Array[LipSyncPose] = []
## Bones receiving absolute mouth, teeth, and tongue poses.
@export var viseme_bones: PackedStringArray = PackedStringArray()
## Bones receiving additive mouth, teeth, tongue, quill, and brow poses.
@export var expression_bones: PackedStringArray = PackedStringArray()
## Resource paths for voice clips associated with this character profile.
@export_file("*.tres") var clip_paths: PackedStringArray = PackedStringArray()

var _clip_by_stream_path: Dictionary = {}
var _missing_stream_paths: Dictionary = {}


func find_pose(pose_id: StringName, expression: bool = false) -> LipSyncPose:
	var poses: Array[LipSyncPose] = expressions if expression else visemes
	for pose: LipSyncPose in poses:
		if pose and pose.id == pose_id:
			return pose
	return null


func find_clip(stream: AudioStream) -> LipSyncClip:
	if not stream:
		return null
	if _clip_by_stream_path.has(stream.resource_path):
		return _clip_by_stream_path[stream.resource_path]
	if _missing_stream_paths.has(stream.resource_path):
		return null
	for path: String in clip_paths:
		var clip: LipSyncClip = load(path) as LipSyncClip
		if clip and clip.audio:
			_clip_by_stream_path[clip.audio.resource_path] = clip
	var match_clip: LipSyncClip = _clip_by_stream_path.get(stream.resource_path) as LipSyncClip
	if not match_clip:
		_missing_stream_paths[stream.resource_path] = true
	return match_clip


func invalidate_clip_cache() -> void:
	_clip_by_stream_path.clear()
	_missing_stream_paths.clear()


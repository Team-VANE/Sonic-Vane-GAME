@tool
extends SkeletonModifier3D
class_name LipSyncDriver

## Character-specific pose list, bone masks, and clip assignments.
@export var profile: LipSyncProfile
## AudioStreamPlayer3D used for this character's voice lines.
@export_node_path("AudioStreamPlayer3D") var voice_player_path: NodePath

var _voice_player: AudioStreamPlayer3D
var _clip: LipSyncClip
var _playback_time: float = 0.0
var _stop_tick_ms: int = -1
var _preview_active: bool = false
var _influence_active: bool = false
var _pose_cache: Dictionary = {}
var _overlay_history: Dictionary = {}
var _smoothing_history: Dictionary = {}
var _smoothing_frame: int = -1
var _smoothing_response: float = 0.0
var _preview_evaluating: bool = false


func _ready() -> void:
	if not voice_player_path.is_empty():
		_voice_player = get_node_or_null(voice_player_path) as AudioStreamPlayer3D
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _preview_active or not profile or not _voice_player:
		return
	var was_active: bool = _influence_active
	var elapsed_time: float = 0.0
	if _voice_player.playing:
		var next_clip: LipSyncClip = profile.find_clip(_voice_player.stream)
		if next_clip != _clip:
			_clip = next_clip
			_pose_cache.clear()
			_smoothing_history.clear()
		_stop_tick_ms = -1
		elapsed_time = _voice_player.get_playback_position()
	elif _clip:
		if _stop_tick_ms < 0:
			_stop_tick_ms = Time.get_ticks_msec()
		elapsed_time = _clip.audio.get_length() + float(Time.get_ticks_msec() - _stop_tick_ms) / 1000.0
		if elapsed_time > _clip.get_influence_duration():
			_clip = null
			_pose_cache.clear()
	_influence_active = _clip != null and elapsed_time <= _clip.get_influence_duration()
	if _influence_active:
		_playback_time = _scale_playback_time(_clip, elapsed_time)
	if _influence_active or was_active or not _smoothing_history.is_empty():
		_process_modification_with_delta(delta)


func set_preview(clip: LipSyncClip, time_sec: float, continuous: bool = false) -> void:
	var next_time: float = _scale_playback_time(clip, maxf(0.0, time_sec)) if clip else 0.0
	var delta: float = next_time - _playback_time
	if not continuous or clip != _clip or delta < 0.0 or delta > 0.25:
		_smoothing_history.clear()
		delta = 0.0
	_preview_active = true
	_clip = clip
	_influence_active = clip != null and time_sec <= clip.get_influence_duration()
	_playback_time = next_time
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton:
		_preview_evaluating = true
		_process_modification_with_delta(delta)
		_preview_evaluating = false


func clear_preview() -> void:
	_preview_active = false
	_clip = null
	_influence_active = false
	_pose_cache.clear()
	_smoothing_history.clear()
	_preview_evaluating = true
	_process_modification_with_delta(0.0)
	_preview_evaluating = false


func _scale_playback_time(clip: LipSyncClip, elapsed_time: float) -> float:
	var duration: float = maxf(clip.get_influence_duration(), 0.001)
	return elapsed_time * clip.get_timeline_length() / duration


func _process_modification_with_delta(delta: float) -> void:
	if Engine.is_editor_hint() and not _preview_evaluating:
		return
	if _preview_active and not _preview_evaluating:
		return
	if not _influence_active and _overlay_history.is_empty() and _smoothing_history.is_empty():
		return
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton or not profile:
		return
	if not _preview_active and _smoothing_frame != Engine.get_process_frames():
		_smoothing_frame = Engine.get_process_frames()
	elif not _preview_active:
		delta = 0.0
	if _clip:
		_smoothing_response = _clip.smoothing_time
	var neutral_pose: LipSyncPose = profile.find_pose(profile.silent_viseme_id)
	var viseme_samples: Array[Dictionary] = []
	var expression_samples: Array[Dictionary] = []
	if _clip and _influence_active:
		viseme_samples = _active_poses(_clip.viseme_cues, _playback_time, false)
		expression_samples = _active_poses(_clip.expression_cues, _playback_time, true)
	var absolute: bool = _clip != null and _influence_active and _clip.application_mode == 1
	var overlay_active: bool = absolute or not viseme_samples.is_empty() or not expression_samples.is_empty() or not _smoothing_history.is_empty()
	var affected_bones: PackedStringArray = profile.viseme_bones.duplicate()
	for bone_name: String in profile.expression_bones:
		if not affected_bones.has(bone_name):
			affected_bones.append(bone_name)
	for bone_name: String in affected_bones:
		var bone_index: int = skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		if not overlay_active and not _overlay_history.has(bone_index):
			continue
		var current: Dictionary = _read_bone_pose(skeleton, bone_index)
		var base: Dictionary = _resolve_base_pose(bone_index, current)
		if not overlay_active:
			_write_bone_pose(skeleton, bone_index, base)
			_overlay_history.erase(bone_index)
			continue
		var neutral: Dictionary = _sample_pose(neutral_pose, bone_name)
		var output: Dictionary = base.duplicate()
		if absolute:
			output.merge(neutral, true)
		if profile.viseme_bones.has(bone_name):
			var viseme_values: Dictionary = _blend_samples(neutral, viseme_samples, bone_name)
			viseme_values = _smooth_layer("viseme:" + bone_name, neutral, viseme_values, delta)
			if absolute:
				output.merge(viseme_values, true)
			else:
				output = _add_pose_delta(output, neutral, viseme_values)
		if profile.expression_bones.has(bone_name):
			var expression_values: Dictionary = _compound_expressions(neutral, expression_samples, bone_name)
			expression_values = _smooth_layer("expression:" + bone_name, neutral, expression_values, delta)
			output = _add_pose_delta(output, neutral, expression_values)
		_write_bone_pose(skeleton, bone_index, output)
		_overlay_history[bone_index] = {"base": base, "output": output}


func _active_poses(cues: Array[LipSyncCue], time_sec: float, expression: bool) -> Array[Dictionary]:
	var per_row: Array[Dictionary] = []
	for row: int in range(LipSyncCue.ROW_COUNT):
		per_row.append({})
	for cue: LipSyncCue in cues:
		if not cue or time_sec < cue.start_time or time_sec > cue.end_time:
			continue
		var pose: LipSyncPose = profile.find_pose(cue.pose_id, expression)
		if not pose:
			continue
		var fade_weight: float = cue.get_fade_weight(time_sec, _clip.expression_blend_curve if expression else _clip.viseme_blend_curve)
		var weight: float = clampf(fade_weight * cue.strength, 0.0, 1.0)
		if weight <= 0.0:
			continue
		var row_index: int = cue.row
		if row_index < 0 or row_index >= per_row.size():
			continue
		if per_row[row_index].is_empty() or weight > float(per_row[row_index]["weight"]):
			per_row[row_index] = {"pose": pose, "weight": weight, "fade": fade_weight, "mix": cue.expression_mix}
	var samples: Array[Dictionary] = []
	for sample: Dictionary in per_row:
		if not sample.is_empty():
			samples.append(sample)
	return samples


func _blend_samples(neutral: Dictionary, samples: Array[Dictionary], bone_name: String) -> Dictionary:
	if samples.is_empty():
		return neutral
	var total_weight: float = 0.0
	var total_fade: float = 0.0
	var contributing: Array[Dictionary] = []
	for sample: Dictionary in samples:
		var pose_values: Dictionary = _sample_pose(sample["pose"], bone_name)
		if pose_values.is_empty():
			continue
		var sample_weight: float = float(sample["weight"])
		total_weight += sample_weight
		total_fade += float(sample["fade"])
		contributing.append({"values": pose_values, "weight": sample_weight})
	if contributing.is_empty():
		return neutral
	var result: Dictionary = {}
	var accumulated: float = 0.0
	for sample: Dictionary in contributing:
		var values: Dictionary = neutral.duplicate()
		values.merge(sample["values"], true)
		var weight: float = float(sample["weight"])
		result = values if accumulated <= 0.0 else _mix_values(result, values, weight / (accumulated + weight))
		accumulated += weight
	var influence: float = total_weight / maxf(1.0, total_fade)
	return _mix_values(neutral, result, clampf(influence, 0.0, 1.0))


func _compound_expressions(neutral: Dictionary, samples: Array[Dictionary], bone_name: String) -> Dictionary:
	var result: Dictionary = neutral.duplicate()
	var crossfade_total: float = 0.0
	for sample: Dictionary in samples:
		if int(sample["mix"]) == 1 and not _sample_pose(sample["pose"], bone_name).is_empty():
			crossfade_total += float(sample["fade"])
	for sample: Dictionary in samples:
		var values: Dictionary = neutral.duplicate()
		values.merge(_sample_pose(sample["pose"], bone_name), true)
		var weight: float = float(sample["weight"])
		if int(sample["mix"]) == 1:
			weight /= maxf(1.0, crossfade_total)
		result = _add_pose_delta(result, neutral, _mix_values(neutral, values, weight))
	if result.has("scale") and neutral.has("scale"):
		var scale: Vector3 = result["scale"]
		var reference: Vector3 = neutral["scale"]
		for axis: int in range(3):
			if reference[axis] > 0.0001:
				scale[axis] = clampf(scale[axis], reference[axis] * 0.25, reference[axis] * 4.0)
		result["scale"] = scale
	for component: String in result:
		if not result[component].is_finite():
			return neutral
	return result


func _smooth_layer(key: String, neutral: Dictionary, target: Dictionary, delta: float) -> Dictionary:
	var response: float = _smoothing_response
	if response <= 0.0:
		_smoothing_history.erase(key)
		return target
	var previous: Dictionary = _smoothing_history.get(key, neutral)
	var result: Dictionary = _mix_values(previous, target, 1.0 - exp(-maxf(delta, 0.0) / response)) if delta > 0.0 else previous
	if _preview_active and delta <= 0.0:
		result = target
	var resting: bool = true
	for component: String in result:
		if neutral.has(component) and not result[component].is_equal_approx(neutral[component]):
			resting = false
	if resting:
		_smoothing_history.erase(key)
	else:
		_smoothing_history[key] = result
	return result


func _sample_pose(pose: LipSyncPose, bone_name: String) -> Dictionary:
	if not pose or not pose.animation:
		return {}
	var cache_key: String = "%d:%s" % [pose.get_instance_id(), bone_name]
	if _pose_cache.has(cache_key):
		return _pose_cache[cache_key]
	var values: Dictionary = {}
	var animation: Animation = pose.animation
	for track: int in range(animation.get_track_count()):
		var path: NodePath = animation.track_get_path(track)
		if String(path.get_concatenated_subnames()) != bone_name:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				values["position"] = animation.position_track_interpolate(track, 0.0)
			Animation.TYPE_ROTATION_3D:
				values["rotation"] = animation.rotation_track_interpolate(track, 0.0)
			Animation.TYPE_SCALE_3D:
				values["scale"] = animation.scale_track_interpolate(track, 0.0)
	_pose_cache[cache_key] = values
	return values


func _mix_values(from_values: Dictionary, to_values: Dictionary, weight: float) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["position", "rotation", "scale"]:
		if from_values.has(key) and to_values.has(key):
			result[key] = from_values[key].lerp(to_values[key], weight) if key != "rotation" else from_values[key].slerp(to_values[key], weight)
		elif from_values.has(key):
			result[key] = from_values[key]
		elif to_values.has(key):
			result[key] = to_values[key]
	return result


func _read_bone_pose(skeleton: Skeleton3D, bone_index: int) -> Dictionary:
	return {
		"position": skeleton.get_bone_pose_position(bone_index),
		"rotation": skeleton.get_bone_pose_rotation(bone_index),
		"scale": skeleton.get_bone_pose_scale(bone_index),
	}


func _resolve_base_pose(bone_index: int, current: Dictionary) -> Dictionary:
	var previous: Dictionary = _overlay_history.get(bone_index, {})
	if previous.is_empty():
		return current
	var base: Dictionary = current.duplicate()
	var previous_output: Dictionary = previous["output"]
	var previous_base: Dictionary = previous["base"]
	for key: String in ["position", "rotation", "scale"]:
		if current[key].is_equal_approx(previous_output[key]):
			base[key] = previous_base[key]
	return base


func _add_pose_delta(base: Dictionary, neutral: Dictionary, pose: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate()
	if neutral.has("position") and pose.has("position"):
		var neutral_position: Vector3 = neutral["position"]
		var pose_position: Vector3 = pose["position"]
		result["position"] = (result["position"] as Vector3) + pose_position - neutral_position
	if neutral.has("rotation") and pose.has("rotation"):
		var neutral_rotation: Quaternion = neutral["rotation"]
		var pose_rotation: Quaternion = pose["rotation"]
		var delta_rotation: Quaternion = neutral_rotation.inverse() * pose_rotation
		result["rotation"] = ((result["rotation"] as Quaternion) * delta_rotation).normalized()
	if neutral.has("scale") and pose.has("scale"):
		var neutral_scale: Vector3 = neutral["scale"]
		var pose_scale: Vector3 = pose["scale"]
		var ratio: Vector3 = Vector3(
			pose_scale.x / neutral_scale.x if absf(neutral_scale.x) > 0.0001 else 1.0,
			pose_scale.y / neutral_scale.y if absf(neutral_scale.y) > 0.0001 else 1.0,
			pose_scale.z / neutral_scale.z if absf(neutral_scale.z) > 0.0001 else 1.0
		)
		result["scale"] = (result["scale"] as Vector3) * ratio
	return result


func _write_bone_pose(skeleton: Skeleton3D, bone_index: int, values: Dictionary) -> void:
	skeleton.set_bone_pose_position(bone_index, values["position"])
	skeleton.set_bone_pose_rotation(bone_index, values["rotation"])
	skeleton.set_bone_pose_scale(bone_index, values["scale"])

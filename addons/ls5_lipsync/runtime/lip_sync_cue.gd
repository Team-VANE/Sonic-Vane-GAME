@tool
extends Resource
class_name LipSyncCue

const ROW_COUNT: int = 4

## Pose identifier resolved through the character profile.
@export var pose_id: StringName = &""
## Cue start time in seconds from the beginning of the audio clip.
@export var start_time: float = 0.0
## Cue end time in seconds from the beginning of the audio clip.
@export var end_time: float = 0.1
## Timeline row. Visemes and expressions use rows 0–3.
@export_range(0, 3, 1) var row: int = 0
## Seconds used to blend into this cue.
@export var blend_in: float = 0.04
## Seconds used to blend out of this cue.
@export var blend_out: float = 0.04
## Keep both blends at half the cue duration when its length changes.
@export var lock_max_blend: bool = false
## Viseme or expression influence from zero to full strength.
@export_range(0.0, 1.0, 0.01) var strength: float = 1.0
## Fade curve override. Default uses the clip's viseme or expression curve.
@export_enum("Default:-1", "Linear:0", "Smoothstep:1", "Sine:2") var blend_curve: int = -1
## Expression overlap behavior. Compound adds offsets; Crossfade shares influence with other crossfade cues.
@export_enum("Compound", "Crossfade") var expression_mix: int = 0


func get_blend_in() -> float:
	return _maximum_blend() if lock_max_blend else clampf(blend_in, 0.0, _maximum_blend())


func get_blend_out() -> float:
	return _maximum_blend() if lock_max_blend else clampf(blend_out, 0.0, _maximum_blend())


func refresh_blends() -> void:
	blend_in = get_blend_in()
	blend_out = get_blend_out()


func get_fade_weight(time_sec: float, default_curve: int = 1) -> float:
	if time_sec < start_time or time_sec > end_time:
		return 0.0
	var weight: float = 1.0
	var fade_in: float = get_blend_in()
	var fade_out: float = get_blend_out()
	if fade_in > 0.0:
		weight = minf(weight, (time_sec - start_time) / fade_in)
	if fade_out > 0.0:
		weight = minf(weight, (end_time - time_sec) / fade_out)
	weight = clampf(weight, 0.0, 1.0)
	var curve: int = default_curve if blend_curve < 0 else blend_curve
	if curve == 1:
		return weight * weight * (3.0 - 2.0 * weight)
	if curve == 2:
		return 0.5 - 0.5 * cos(PI * weight)
	return weight


func _maximum_blend() -> float:
	return maxf(0.0, end_time - start_time) * 0.5


@tool
extends Resource
class_name LipSyncClip

## Character profile used to resolve cue pose identifiers.
@export var profile: LipSyncProfile
## Voice clip synchronized by this resource.
@export var audio: AudioStream
## Spoken text used to generate an editable first draft.
@export_multiline var transcript: String = ""
## Detected or manually adjusted first audible time in seconds.
@export var audible_start: float = 0.0
## Detected or manually adjusted last audible time in seconds.
@export var audible_end: float = 0.0
## Gap in seconds between consecutive transcript-generated visemes.
@export_range(0.0, 1.0, 0.01) var generation_padding: float = 0.0
## Default blend-in duration in seconds for new cues.
@export_range(0.0, 2.0, 0.01) var new_blend_in: float = 0.04
## Default blend-out duration in seconds for new cues.
@export_range(0.0, 2.0, 0.01) var new_blend_out: float = 0.04
## Default blend-in duration for new expression cues.
@export_range(0.0, 2.0, 0.01) var new_expression_blend_in: float = 0.15
## Default blend-out duration for new expression cues.
@export_range(0.0, 2.0, 0.01) var new_expression_blend_out: float = 0.15
## Fade curve for visemes without a cue override.
@export_enum("Linear", "Smoothstep", "Sine") var viseme_blend_curve: int = 1
## Fade curve for expressions without a cue override.
@export_enum("Linear", "Smoothstep", "Sine") var expression_blend_curve: int = 1
## Response time in seconds for facial smoothing. Zero disables smoothing.
@export_range(0.0, 0.25, 0.005) var smoothing_time: float = 0.0
## Facial pose application against gameplay animation.
@export_enum("Additive Overlay", "Absolute Override") var application_mode: int = 0
## Runtime duration in seconds. Zero uses the authored timeline length.
@export_range(0.0, 120.0, 0.01) var influence_duration_override: float = 0.0
## Timed absolute viseme poses across four rows.
@export var viseme_cues: Array[LipSyncCue] = []
## Timed additive expressions across four rows.
@export var expression_cues: Array[LipSyncCue] = []
## Optional word spans used as timing guidance in the editor.
@export var word_spans: Array[Dictionary] = []


func get_timeline_length() -> float:
	var length: float = audio.get_length() if audio else 0.0
	for cue: LipSyncCue in expression_cues:
		if cue:
			length = maxf(length, cue.end_time)
	for cue: LipSyncCue in viseme_cues:
		if cue:
			length = maxf(length, cue.end_time)
	return length


func get_influence_duration() -> float:
	return influence_duration_override if influence_duration_override > 0.0 else get_timeline_length()


extends Resource
class_name CharacterUIVoiceProfile

@export_group("Voice Classes")
## Lines used when the character is confirmed or a general menu action is accepted.
@export var confirm_clips: Array[AudioStream] = []
## Lines used by Character Select and when this character is chosen.
@export var character_clips: Array[AudioStream] = []
## Lines used when Level Select opens.
@export var level_clips: Array[AudioStream] = []
## Lines used when the settings menu opens.
@export var settings_clips: Array[AudioStream] = []
## Lines used when the online menu opens.
@export var online_clips: Array[AudioStream] = []
## Lines used when a level begins loading.
@export var loading_clips: Array[AudioStream] = []
## Lines used when the exit confirmation opens.
@export var confirm_exit_clips: Array[AudioStream] = []

@export_group("Playback")
## Minimum delay before another line from the same voice class can play.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var same_class_cooldown: float = 3.0


func get_clips(voice_class: StringName) -> Array[AudioStream]:
	match voice_class:
		&"confirm":
			return confirm_clips
		&"character":
			return character_clips
		&"level":
			return level_clips
		&"settings":
			return settings_clips
		&"online":
			return online_clips
		&"loading":
			return loading_clips
		&"confirm_exit":
			return confirm_exit_clips
	return []

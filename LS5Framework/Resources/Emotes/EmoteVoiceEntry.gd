extends Resource
class_name EmoteVoiceEntry

## Matches the stable option identifier used by the emote wheel.
@export var emote_id: StringName = &""
## Supplies character-specific variants. Empty or null clips produce no voice.
@export var clips: Array[AudioStream] = []
## Overrides the same-emote cooldown; negative values use the profile default.
@export_range(-1.0, 30.0, 0.1, "or_greater", "suffix:s") var cooldown_override_seconds: float = -1.0

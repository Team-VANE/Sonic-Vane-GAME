extends Resource
class_name EmoteVoiceProfile

## Defines voice variants for this character's supported emote identifiers.
@export var entries: Array[EmoteVoiceEntry] = []
@export_group("Playback")
## Allows emotes to interrupt active emote or incidental voices. Higher-priority dialogue and hurt remain protected.
@export var allow_voice_interruption: bool = true
@export_group("Cooldowns")
## Enables global and same-emote cooldowns for this character's emote voices.
@export var cooldowns_enabled: bool = false
## Minimum delay between successfully played emote voices.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var global_cooldown_seconds: float = 1.0
## Minimum delay before the same emote voice can play again.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var same_emote_cooldown_seconds: float = 3.0


func get_entry(emote_id: StringName) -> EmoteVoiceEntry:
	if emote_id == &"":
		return null
	for entry: EmoteVoiceEntry in entries:
		if entry and entry.emote_id == emote_id:
			return entry
	return null

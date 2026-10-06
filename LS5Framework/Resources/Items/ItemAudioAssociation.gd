extends Resource
class_name ItemAudioAssociation

## Item identifier used when resolving collection audio.
@export var item_id: StringName = &""
## Sound played when the associated item is obtained.
@export var collection_sound: AudioStream
## Volume applied to this item's collection sound.
@export var volume_db: float = 0.0
## Pitch scale applied to this item's collection sound.
@export_range(0.01, 4.0, 0.01, "or_greater") var pitch_scale: float = 1.0

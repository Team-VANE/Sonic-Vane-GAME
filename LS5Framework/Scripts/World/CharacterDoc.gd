extends Resource
class_name CharacterDoc

@export_group("Identity")
## Display name shown in Character Select.
@export var character_name: String = ""

## Stable ID used by settings and runtime character selection.
@export var character_id: String = ""

## Sort order for Character Select.
@export var order: int = 0

@export_group("Scenes")
## Player scene used when this character is selected.
@export var scene: String = ""

@export_group("Character Settings")
## Packaged defaults and loadout metadata used by the per-character settings menu.
@export var settings_profile: CharacterSettingsProfile

@export_group("UI Voice")
## Character-specific voice lines used by menus while this character is selected.
@export var ui_voice_profile: CharacterUIVoiceProfile

@export_group("Attributes")
## Optional key/value metadata parsed by gameplay systems.
@export var attributes: Dictionary = {}

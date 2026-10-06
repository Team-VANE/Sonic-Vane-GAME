extends Resource
class_name CharacterSettingsProfile

## Namespace used to keep profiles from separate character packs distinct.
@export var package_id: StringName = &"ls5framework"
## Stable character identifier used for user profile persistence.
@export var character_id: StringName = &""
## Revision of the packaged defaults.
@export var profile_version: int = 1

@export_group("Presentation")
## Hides this character from character and buddy selection menus without disabling runtime lookup.
@export var hidden_from_character_select: bool = false
## Section label used by character and buddy selection menus. Empty values use Main.
@export var selection_category: String = "Main"
## Supplies character-specific emote voices and cooldowns. An empty profile produces no voice.
@export var emote_voice_profile: EmoteVoiceProfile

@export_group("Loadout")
## Abilities displayed in the per-character loadout menu.
@export var ability_catalog: Array[Dictionary] = []
## Packaged ability assignments used when no user override exists.
@export var default_loadout: Array[Dictionary] = []

@export_group("Action Routing")
## Packaged action transitions evaluated through stable action identifiers.
@export var default_routes: Array[Dictionary] = []
## Uses profile routes instead of scene-local AbilityRoute resources and NodePath fallbacks.
@export var routes_authoritative: bool = false

@export_group("Character Settings")
## Packaged defaults for character-specific settings added by profile extensions.
@export var default_settings: Dictionary = {}


func get_profile_key() -> String:
	var normalized_package: String = String(package_id).strip_edges().to_lower()
	var normalized_character: String = String(character_id).strip_edges().to_lower()
	if normalized_package == "":
		normalized_package = "local"
	return "%s:%s" % [normalized_package, normalized_character]


func get_ability_definition(ability_id: StringName) -> Dictionary:
	for definition: Dictionary in ability_catalog:
		if StringName(definition.get("ability_id", &"")) == ability_id:
			return definition.duplicate(true)
	return {}


func get_default_binding(ability_id: StringName) -> Dictionary:
	for binding: Dictionary in default_loadout:
		if StringName(binding.get("ability_id", &"")) == ability_id:
			return binding.duplicate(true)
	return {}


func get_default_route(route_id: StringName) -> Dictionary:
	for route: Dictionary in default_routes:
		if StringName(route.get("route_id", &"")) == route_id:
			return route.duplicate(true)
	return {}

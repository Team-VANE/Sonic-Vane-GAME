extends Resource
class_name CharacterSettingsProfile

const CutsceneProfile = preload("res://LS5Framework/Scripts/World/CutsceneActorProfile.gd")

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
## Supplies reusable animation, action, and dialogue cues for this character in cutscenes.
@export var cutscene_profile: CutsceneProfile

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

@export_group("Attributes")
## Ordered parameter IDs exposed by the Attributes menu. Uses pawn.property, ability.action_id.property, or visual.property.
@export var attribute_ids: Array[StringName] = []
## Optional presentation and validation overrides keyed by attribute ID: label, description, category, min, max, step, suffix, and default.
@export var attribute_definitions: Dictionary = {}
## Maps retired attribute IDs to their current IDs when reading saved settings.
@export var attribute_aliases: Dictionary = {}

func normalize_attribute_settings(values: Dictionary) -> Dictionary:
	var normalized: Dictionary = values.duplicate(true)
	for previous: Variant in attribute_aliases:
		var current: StringName = StringName(attribute_aliases[previous])
		if normalized.has(previous) and not normalized.has(current):
			normalized[current] = normalized[previous]
		normalized.erase(previous)
	return normalized


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

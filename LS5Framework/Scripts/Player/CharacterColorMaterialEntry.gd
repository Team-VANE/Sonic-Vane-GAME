class_name CharacterColorMaterialEntry
extends Resource

enum ColorSlot {
	PRIMARY,
	SECONDARY,
	TERTIARY,
}

## Material surface affected by this character colour entry.
@export var material: Material
## Optional base texture used to identify or supply the material's colour texture.
@export var texture: Texture2D
## Character colour applied through this entry's mask.
@export_enum("Primary", "Secondary", "Tertiary") var color_slot: int = ColorSlot.PRIMARY
## Greyscale texture controlling where the selected character colour is applied. Empty affects the full material.
@export var mask: Texture2D


func matches(candidate_material: Material, candidate_texture: Texture2D) -> bool:
	if material == null or candidate_material != material:
		return false
	return texture == null or candidate_texture == texture


func get_color(primary: Color, secondary: Color, tertiary: Color) -> Color:
	match color_slot:
		ColorSlot.SECONDARY:
			return secondary
		ColorSlot.TERTIARY:
			return tertiary
		_:
			return primary

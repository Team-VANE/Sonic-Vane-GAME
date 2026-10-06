extends Resource
class_name ItemIconAssociation

## Item identifier used when resolving an item icon.
@export var item_id: StringName = &""
## Foreground texture composited over the item icon background.
@export var icon_texture: Texture2D
## Keeps the icon in the timed power-up queue after its collection presentation.
@export var is_power_up: bool = false

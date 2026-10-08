@tool
extends SurfaceBehaviorTrait
class_name SurfaceHazardTrait

## Overrides inherited contact damage. Zero clears inherited damage.
@export var override_damage: bool = false:
	set(value):
		override_damage = value
		emit_changed()
		notify_property_list_changed()
## Damage passed to the player handler. Volumes apply damage once on entry.
@export_range(0, 1000, 1) var damage_amount: int = 1:
	set(value):
		damage_amount = clampi(value, 0, 1000)
		emit_changed()
## Pit-death behavior. Takes precedence over contact damage.
@export var death: Policy = Policy.INHERIT:
	set(value):
		death = value
		emit_changed()


func get_surface_metadata() -> Dictionary:
	var metadata: Dictionary = {}
	if override_damage:
		metadata[SurfaceBehaviorMetadata.DAMAGE_AMOUNT] = damage_amount
	_set_policy(metadata, SurfaceBehaviorMetadata.DEATH, death)
	return metadata


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "damage_amount" and not override_damage:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR

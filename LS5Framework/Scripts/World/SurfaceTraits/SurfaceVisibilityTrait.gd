@tool
extends SurfaceBehaviorTrait
class_name SurfaceVisibilityTrait

## Mesh visibility within the target subtree. Collision remains enabled.
@export var visibility: Policy = Policy.INHERIT:
	set(value):
		visibility = value
		emit_changed()


func get_surface_metadata() -> Dictionary:
	var metadata: Dictionary = {}
	_set_policy(metadata, SurfaceBehaviorMetadata.INVISIBLE, visibility, true)
	return metadata

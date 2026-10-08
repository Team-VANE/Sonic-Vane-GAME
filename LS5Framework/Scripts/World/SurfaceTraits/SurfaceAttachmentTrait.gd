@tool
extends SurfaceBehaviorTrait
class_name SurfaceAttachmentTrait

enum AlignmentMode { INHERIT, LIMIT, DISABLED }

## Automatic wall cling. Requires a nearby solid wall and a Parkour ability.
@export var force_cling: Policy = Policy.INHERIT:
	set(value):
		force_cling = value
		emit_changed()
## Surface alignment policy measured from gravity-up.
@export var alignment: AlignmentMode = AlignmentMode.INHERIT:
	set(value):
		alignment = value
		emit_changed()
		notify_property_list_changed()
## Maximum surface alignment angle from gravity-up when alignment is limited.
@export_range(0.0, 180.0, 0.1, "suffix:°") var maximum_angle: float = 90.0:
	set(value):
		maximum_angle = clampf(value, 0.0, 180.0)
		emit_changed()
## Adhesion that prevents geometry-driven surface launches.
@export var sticky: Policy = Policy.INHERIT:
	set(value):
		sticky = value
		emit_changed()
## Blocks ordinary adhesion detachment. Intentional jumps remain available.
@export var prevent_detach: Policy = Policy.INHERIT:
	set(value):
		prevent_detach = value
		emit_changed()
## Preserves player momentum during supported surface movement.
@export var preserve_momentum: Policy = Policy.INHERIT:
	set(value):
		preserve_momentum = value
		emit_changed()


func get_surface_metadata() -> Dictionary:
	var metadata: Dictionary = {}
	_set_policy(metadata, SurfaceBehaviorMetadata.FORCE_CLING, force_cling)
	_set_policy(metadata, SurfaceBehaviorMetadata.STICKY, sticky)
	_set_policy(metadata, SurfaceBehaviorMetadata.NO_DETACH, prevent_detach)
	_set_policy(metadata, SurfaceBehaviorMetadata.PRESERVE_PLAYER_MOMENTUM, preserve_momentum)
	if alignment != AlignmentMode.INHERIT:
		metadata[SurfaceBehaviorMetadata.ATTACH_LIMIT] = maximum_angle if alignment == AlignmentMode.LIMIT else 0.0
		if float(metadata[SurfaceBehaviorMetadata.ATTACH_LIMIT]) <= 0.0:
			metadata[SurfaceBehaviorMetadata.NO_DETACH] = false
	return metadata


func _validate_property(property: Dictionary) -> void:
	if property["name"] == "maximum_angle" and alignment != AlignmentMode.LIMIT:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR

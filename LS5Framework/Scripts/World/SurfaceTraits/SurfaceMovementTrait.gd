@tool
extends SurfaceBehaviorTrait
class_name SurfaceMovementTrait

enum RollMode { INHERIT, FORCE, BLOCK, ALLOW }
enum JumpMode { INHERIT, BLOCK, BLOCK_COYOTE, ALLOW }

## Rolling policy. Forced rolling takes precedence over restrictions from overlapping sources.
@export var rolling: RollMode = RollMode.INHERIT:
	set(value):
		rolling = value
		emit_changed()
## Ground and coyote jump policy.
@export var jumping: JumpMode = JumpMode.INHERIT:
	set(value):
		jumping = value
		emit_changed()
## Drifting availability while contacting the surface or occupying the volume.
@export var drifting: Policy = Policy.INHERIT:
	set(value):
		drifting = value
		emit_changed()
## Tangential slope gravity while the behavior is active.
@export var slope_gravity: Policy = Policy.INHERIT:
	set(value):
		slope_gravity = value
		emit_changed()


func get_surface_metadata() -> Dictionary:
	var metadata: Dictionary = {}
	if rolling != RollMode.INHERIT:
		metadata[SurfaceBehaviorMetadata.FORCE_ROLL] = rolling == RollMode.FORCE
		metadata[SurfaceBehaviorMetadata.NO_ROLL] = rolling == RollMode.BLOCK
	if jumping != JumpMode.INHERIT:
		metadata[SurfaceBehaviorMetadata.NO_JUMP] = jumping == JumpMode.BLOCK
		metadata[SurfaceBehaviorMetadata.NO_COYOTE_JUMP] = jumping in [JumpMode.BLOCK, JumpMode.BLOCK_COYOTE]
	_set_policy(metadata, SurfaceBehaviorMetadata.NO_DRIFT, drifting, true)
	_set_policy(metadata, SurfaceBehaviorMetadata.NO_SLOPE_GRAVITY, slope_gravity, true)
	return metadata

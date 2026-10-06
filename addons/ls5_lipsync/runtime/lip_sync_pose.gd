@tool
extends Resource
class_name LipSyncPose

## Stable pose identifier used by clip timing resources.
@export var id: StringName = &""
## Animation containing the character's facial pose.
@export var animation: Animation
## Text patterns used for transcript draft generation.
@export var spelling_patterns: PackedStringArray = PackedStringArray()


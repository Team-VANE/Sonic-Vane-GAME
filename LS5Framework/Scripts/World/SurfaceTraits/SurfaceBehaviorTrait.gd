@tool
extends Resource
class_name SurfaceBehaviorTrait

enum Policy { INHERIT, ENABLED, DISABLED }


func get_surface_metadata() -> Dictionary:
	return {}


func _set_policy(metadata: Dictionary, key: StringName, policy: Policy, inverted: bool = false) -> void:
	if policy != Policy.INHERIT:
		metadata[key] = (policy == Policy.ENABLED) != inverted

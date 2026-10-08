extends RefCounted
class_name SurfaceBehaviorMetadata

const ATTACH_LIMIT: StringName = &"surface_attach_max_angle_deg"
const DAMAGE_AMOUNT: StringName = &"surface_damage_amount"
const DEATH: StringName = &"surface_death"
const INTANGIBLE: StringName = &"surface_intangible"
const NO_SLOPE_GRAVITY: StringName = &"surface_no_slope_gravity"
const NO_DETACH: StringName = &"surface_no_detach"
const STICKY: StringName = &"surface_sticky"
const FORCE_CLING: StringName = &"surface_force_cling"
const INVISIBLE: StringName = &"surface_invisible"
const FORCE_ROLL: StringName = &"surface_force_roll"
const NO_JUMP: StringName = &"surface_no_jump"
const NO_COYOTE_JUMP: StringName = &"surface_no_coyote_jump"
const NO_ROLL: StringName = &"surface_no_roll"
const NO_DRIFT: StringName = &"surface_no_drift"
const PRESERVE_PLAYER_MOMENTUM: StringName = &"surface_preserve_player_momentum"


static func get_value(collider: Object, key: StringName, shape_index: int = -1) -> Variant:
	if not is_instance_valid(collider):
		return null
	var shape_owner: Object = null
	var shape: Shape3D = null
	if collider is CollisionObject3D and shape_index >= 0:
		var collision_object: CollisionObject3D = collider as CollisionObject3D
		for owner_id: int in collision_object.get_shape_owners():
			for shape_id: int in range(collision_object.shape_owner_get_shape_count(owner_id)):
				if collision_object.shape_owner_get_shape_index(owner_id, shape_id) == shape_index:
					shape_owner = collision_object.shape_owner_get_owner(owner_id)
					shape = collision_object.shape_owner_get_shape(owner_id, shape_id)
					break
			if shape_owner:
				break
	var override: Dictionary = SurfaceBehaviorRegistry.get_override(shape_owner, key)
	if not override.is_empty():
		return override["value"]
	var source: Object = collider
	while is_instance_valid(source):
		override = SurfaceBehaviorRegistry.get_override(source, key)
		if not override.is_empty():
			return override["value"]
		source = (source as Node).get_parent() if source is Node else null
	if is_instance_valid(shape_owner) and shape_owner.has_meta(key):
		return shape_owner.get_meta(key)
	if shape and shape.has_meta(key):
		return shape.get_meta(key)
	source = collider
	while is_instance_valid(source):
		if source.has_meta(key):
			return source.get_meta(key)
		source = (source as Node).get_parent() if source is Node else null
	return null


static func get_all_keys() -> Array[StringName]:
	return [
		ATTACH_LIMIT,
		DAMAGE_AMOUNT,
		DEATH,
		INTANGIBLE,
		NO_SLOPE_GRAVITY,
		NO_DETACH,
		STICKY,
		FORCE_ROLL,
		FORCE_CLING,
		INVISIBLE,
		NO_JUMP,
		NO_COYOTE_JUMP,
		NO_ROLL,
		NO_DRIFT,
		PRESERVE_PLAYER_MOMENTUM,
	]

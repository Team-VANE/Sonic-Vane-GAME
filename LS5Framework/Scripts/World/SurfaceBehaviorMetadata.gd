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

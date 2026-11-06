extends Node
class_name EnemyLocomotion

## Brakes drift perpendicular to the requested movement heading, in units per second squared. Zero uses the default movement response.
@export_range(0.0, 200.0, 0.1, "or_greater") var sideways_deceleration: float = 0.0

var actor: CharacterBody3D = null
var capture_impact_contacts: bool = true
var _pre_move_velocity: Vector3 = Vector3.ZERO
var _impact_contacts: Array[Dictionary] = []


func setup(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor


func physics_tick(_delta: float, _intent: EnemyIntent) -> void:
	pass


func _approach_movement_velocity(current: Vector3, target: Vector3, up: Vector3, acceleration: float, deceleration: float, delta: float) -> Vector3:
	var sideways: Vector3 = Vector3.ZERO
	if sideways_deceleration > 0.0:
		var side_axis: Vector3 = up.cross(target)
		if side_axis.length_squared() > 0.000001:
			side_axis = side_axis.normalized()
			sideways = side_axis * current.dot(side_axis)
			current -= sideways
			sideways = sideways.move_toward(Vector3.ZERO, sideways_deceleration * delta)
	var rate: float = acceleration if target.length_squared() > current.length_squared() else deceleration
	return current.move_toward(target, maxf(rate, 0.0) * delta) + sideways


func reset_locomotion() -> void:
	if actor:
		actor.velocity = Vector3.ZERO
	_pre_move_velocity = Vector3.ZERO
	_impact_contacts.clear()


func get_pre_move_velocity() -> Vector3:
	return _pre_move_velocity


func get_impact_contacts() -> Array[Dictionary]:
	return _impact_contacts


func _begin_move(pre_move_velocity: Vector3) -> void:
	_pre_move_velocity = pre_move_velocity
	_impact_contacts.clear()


func _capture_slide_impact_contacts() -> void:
	if actor == null or not capture_impact_contacts:
		return
	for collision_index: int in range(actor.get_slide_collision_count()):
		var collision: KinematicCollision3D = actor.get_slide_collision(collision_index)
		_record_impact_contact(collision.get_normal(), collision.get_collider())


func _record_impact_contact(normal_value: Vector3, collider: Object) -> void:
	if not capture_impact_contacts:
		return
	var normal: Vector3 = normal_value.normalized()
	if normal.length() < 0.001:
		return
	_impact_contacts.append({
		"normal": normal,
		"collider": collider,
	})


func is_grounded() -> bool:
	return false


func get_state_tag() -> StringName:
	return &"idle"

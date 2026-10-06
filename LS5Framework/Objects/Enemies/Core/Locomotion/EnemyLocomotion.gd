extends Node
class_name EnemyLocomotion

var actor: CharacterBody3D = null
var capture_impact_contacts: bool = true
var _pre_move_velocity: Vector3 = Vector3.ZERO
var _impact_contacts: Array[Dictionary] = []


func setup(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor


func physics_tick(_delta: float, _intent: EnemyIntent) -> void:
	pass


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

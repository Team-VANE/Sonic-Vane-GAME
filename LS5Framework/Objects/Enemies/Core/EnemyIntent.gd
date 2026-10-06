extends RefCounted
class_name EnemyIntent

var move_direction: Vector3 = Vector3.ZERO
var face_direction: Vector3 = Vector3.ZERO
var speed_ratio: float = 0.0
var jump_requested: bool = false
var attack_requested: bool = false
var movement_locked: bool = false
var facing_locked: bool = false


func clear() -> void:
	move_direction = Vector3.ZERO
	face_direction = Vector3.ZERO
	speed_ratio = 0.0
	jump_requested = false
	attack_requested = false
	movement_locked = false
	facing_locked = false


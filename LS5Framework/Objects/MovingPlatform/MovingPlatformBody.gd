extends AnimatableBody3D

var _prev_pos: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	process_priority = -90
	process_physics_priority = -90
	sync_to_physics = false
	_prev_pos = global_position
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var p: Vector3 = global_position
	_velocity = (p - _prev_pos) / delta
	_prev_pos = p


func get_platform_velocity() -> Vector3:
	return _velocity

extends Node
class_name ActorRespawnComponent3D

@export_group("Respawn")
## Respawns the owning actor after defeat.
@export var respawn_enabled: bool = false
## Delay between defeat and respawn.
@export var respawn_delay_sec: float = 3.0

var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _timer: float = 0.0
var _waiting: bool = false


func capture_spawn(transform_value: Transform3D) -> void:
	_spawn_transform = transform_value


func request_respawn() -> void:
	if not respawn_enabled:
		_waiting = false
		return
	_timer = max(respawn_delay_sec, 0.0)
	_waiting = true


func physics_tick(delta: float) -> bool:
	if not _waiting:
		return false
	_timer = max(_timer - delta, 0.0)
	if _timer > 0.0:
		return false
	_waiting = false
	return true


func cancel() -> void:
	_timer = 0.0
	_waiting = false


func get_spawn_transform() -> Transform3D:
	return _spawn_transform


func is_waiting() -> bool:
	return _waiting


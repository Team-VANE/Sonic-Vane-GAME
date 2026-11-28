extends CarryableObject

## Visual scale while held in the player's hands.
@export_range(0.1, 1.0, 0.01) var held_visual_scale: float = 0.5:
	set(value):
		held_visual_scale = clampf(value, 0.1, 1.0)
		_sync_visual_scale()

## Mesh scaled independently of the ball's physics body.
@onready var _ball_visual: Node3D = $Visual


func begin_carry(player: Node, target_transform: Transform3D, release_collision_lock: float = 0.35) -> bool:
	if not super.begin_carry(player, target_transform, release_collision_lock):
		return false
	_sync_visual_scale()
	return true


func release_carry(release_transform: Transform3D, release_velocity: Vector3, release_collision_lock: float = 0.35) -> void:
	super.release_carry(release_transform, release_velocity, release_collision_lock)
	_sync_visual_scale()


func clear_carry_owner() -> void:
	super.clear_carry_owner()
	_sync_visual_scale()


func _sync_visual_scale() -> void:
	if is_instance_valid(_ball_visual):
		_ball_visual.scale = Vector3.ONE * (held_visual_scale if is_carried() else 1.0)

@tool
extends MeshInstance3D

## Collision volume represented by the editor preview.
@export var collision_shape: CollisionShape3D
## Displays the trigger volume during gameplay.
@export var show_in_game: bool = false


func _ready() -> void:
	visible = Engine.is_editor_hint() or show_in_game
	set_process(Engine.is_editor_hint())
	_update_volume()


func _process(_delta: float) -> void:
	_update_volume()


func _update_volume() -> void:
	if not is_instance_valid(collision_shape) or not (collision_shape.shape is BoxShape3D) or not (mesh is BoxMesh):
		return
	(mesh as BoxMesh).size = (collision_shape.shape as BoxShape3D).size
	transform = collision_shape.transform

extends Node3D
class_name TeleporterExit

@export_group("Teleporter Exit")
@export var teleporter_id: StringName = &""
@export var exit_group: StringName = &"TeleporterExit"

@export_group("Downwarp")
@export var downwarp_enabled: bool = false
@export var downwarp_distance: float = 50.0
@export var downwarp_offset: float = 0.05
@export var downwarp_collision_mask: int = 0xFFFFFFFF


func _ready() -> void:
	if exit_group != &"" and not is_in_group(exit_group):
		add_to_group(exit_group)

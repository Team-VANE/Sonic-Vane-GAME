extends Area3D
class_name CarryableRespawnPlane

## Enables this carryable respawn volume.
@export var active: bool = true
## Disables this volume after respawning one carryable.
@export var one_shot: bool = false
## Collision mask used to detect carryable objects.
@export_flags_3d_physics var carryable_collision_mask: int = 2


func _ready() -> void:
	collision_mask = carryable_collision_mask
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if active and body.has_method("respawn_carryable"):
		_respawn_body.call_deferred(body)


func _respawn_body(body: Node3D) -> void:
	if not active or not is_instance_valid(body):
		return
	var did_respawn: bool = body.call("respawn_carryable", self) == true
	if one_shot and did_respawn:
		active = false
		set_deferred("monitoring", false)

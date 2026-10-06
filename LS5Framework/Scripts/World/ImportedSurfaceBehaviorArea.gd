extends Area3D
class_name ImportedSurfaceBehaviorArea


func _ready() -> void:
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	call_deferred("_register_existing_overlaps")


func _register_existing_overlaps() -> void:
	if not is_inside_tree():
		return
	for body: Node3D in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.has_method("enter_surface_behavior_area"):
		return
	body.call("enter_surface_behavior_area", self)


func _on_body_exited(body: Node3D) -> void:
	if body == null or not body.has_method("exit_surface_behavior_area"):
		return
	body.call("exit_surface_behavior_area", self)

extends Area3D

var body_entry_count: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(_body: Node3D) -> void:
	body_entry_count += 1

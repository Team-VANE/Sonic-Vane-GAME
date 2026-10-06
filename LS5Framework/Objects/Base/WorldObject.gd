@tool
extends Area3D
class_name WorldObject

@export var one_shot: bool = false
@export var enabled: bool = true
@export var require_group: StringName = "player"

signal triggered(player)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not enabled:
		return

	if require_group != "" and not body.is_in_group(require_group):
		return

	# Let subclasses handle the effect
	_apply_to_player(body)

	emit_signal("triggered", body)

	if one_shot:
		enabled = false
		monitoring = false
		# optionally queue_free() if you want them to disappear
		# queue_free()


func _apply_to_player(player: Node3D) -> void:
	# To be overridden by subclasses like Spring, DashPanel, etc.
	pass

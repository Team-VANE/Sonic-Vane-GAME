extends WorldObject


func _apply_to_player(player: Node3D) -> void:
	if multiplayer.has_multiplayer_peer() and not player.is_multiplayer_authority():
		return
	if player.has_method("apply_damage"):
		player.call("apply_damage", 1, self)

class_name BounceReboundAction
extends CharacterAction


func _on_action_initialized() -> void:
	action_id = &"bounce_rebound"
	input_action = &""
	allow_when_inactive = true
	permits_attack_magnetism = true


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null or not enabled:
		return false
	if owner_player.attached:
		return false
	return owner_player._bounce_state == owner_player.BounceState.REBOUND


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	return activate(context)


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		if owner_player.has_method("clear_active_action"):
			owner_player.call("clear_active_action")
		return
	if owner_player._bounce_state != owner_player.BounceState.REBOUND:
		_finish_to_neutral_air()
		return
	if get_gravity_vertical_component(owner_player.velocity) > 0.0:
		return
	if owner_player.has_method("finish_bounce_rebound"):
		owner_player.call("finish_bounce_rebound")
	_finish_to_neutral_air()


func _finish_to_neutral_air() -> void:
	if owner_player != null and owner_player.has_method("activate_neutral_air_action"):
		owner_player.call("activate_neutral_air_action", {"reason": &"bounce_rebound_finished", "source_action": action_id})

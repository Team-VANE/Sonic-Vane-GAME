class_name BounceStompAbility
extends CharacterAbility

var bounce_button_held: bool = false


func _on_action_initialized() -> void:
	action_id = &"bounce_stomp"
	allow_when_inactive = false
	permits_attack_magnetism = true


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if owner_player.attached:
		return false
	if not owner_player.bounce_enabled:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	return true


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if owner_player.has_method("queue_bounce_attack"):
		owner_player.queue_bounce_attack()
	activate(context)
	return true


func on_action_enter(_context: Dictionary = {}) -> void:
	bounce_button_held = SettingsManager.is_gameplay_action_pressed("ability_slot_02")


func on_action_exit(_next_action: CharacterAction) -> void:
	bounce_button_held = false


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		if owner_player.has_method("clear_active_action"):
			owner_player.call("clear_active_action")
		bounce_button_held = false
		return
	if owner_player._bounce_state == owner_player.BounceState.NONE:
		if owner_player.has_method("activate_neutral_air_action"):
			owner_player.call("activate_neutral_air_action", {"reason": &"bounce_finished", "source_action": action_id})
		bounce_button_held = false
		return
	var bounce_pressed_now: bool = SettingsManager.is_gameplay_action_pressed("ability_slot_02")
	if owner_player._bounce_state != owner_player.BounceState.BOUNCE:
		bounce_button_held = bounce_pressed_now
		return
	if bounce_button_held and not bounce_pressed_now:
		owner_player._bounce_state = owner_player.BounceState.STOMP
		var world_up: Vector3 = get_owner_gravity_up()
		var v: Vector3 = owner_player.velocity
		var vertical: float = get_gravity_vertical_component(v)
		var new_vertical: float
		if vertical > 0.0:
			new_vertical = -owner_player.stomp_down_impulse
		else:
			new_vertical = vertical - owner_player.stomp_down_impulse
		v += world_up * (new_vertical - vertical)
		owner_player.velocity = v
		if owner_player.has_method("_play_sfx"):
			owner_player.call("_play_sfx", owner_player.sfx_stomp_start)
	bounce_button_held = bounce_pressed_now

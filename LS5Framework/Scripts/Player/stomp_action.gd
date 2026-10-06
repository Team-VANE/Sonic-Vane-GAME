class_name StompAction
extends CharacterAbility

@export_group("Stomp")

@export_subgroup("Movement/Fall")
## Gravity scale while descending in the stomp state.
@export var stomp_gravity_scale: float = 2.5
## One-shot downward impulse applied when stomp begins.
@export var stomp_down_impulse: float = 41.0

@export_subgroup("Movement/Landing")
## Impact speed above which stomp landing speed is reduced.
@export var stomp_land_speed_threshold: float = 35.0
## Impact speed removed above the stomp landing threshold.
@export var stomp_land_speed_subtract: float = 10.0
## Tangential speed above which stomp landing speed is reduced.
@export var stomp_land_horizontal_threshold: float = 0.0
## Tangential speed removed above the stomp horizontal threshold.
@export var stomp_land_horizontal_subtract: float = 0.0

@export_subgroup("Audio")
## Audio player used when the stomp starts.
@export var stomp_audio_node: NodePath

func _on_action_initialized() -> void:
	action_id = &"stomp"
	allow_when_inactive = true
	permits_attack_magnetism = true


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func on_action_enter(_context: Dictionary = {}) -> void:
	if owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()
	
	if owner_player == null:
		return


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	var source_action: StringName = StringName(_context.get("source_action", &""))
	if source_action == &"" and owner_player.has_method("get_current_action_id"):
		source_action = owner_player.get_current_action_id()
	if owner_player.has_method("is_character_profile_action_allowed"):
		if not bool(owner_player.call("is_character_profile_action_allowed", action_id, source_action)):
			return false
	if owner_player.has_method("should_prioritize_spindash_over_bounce_stomp"):
		if owner_player.should_prioritize_spindash_over_bounce_stomp():
			return false
	if owner_player.attached:
		return false
	if owner_player._bounce_state == owner_player.BounceState.STOMP:
		return false
	return true


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if not activate(context):
		return false
	if owner_player.has_method("queue_stomp_attack"):
		owner_player.queue_stomp_attack()
	if stomp_audio_node != null and stomp_audio_node != NodePath():
		var node: Node = owner_player.get_node(stomp_audio_node)
		if node is AudioStreamPlayer3D:
			node.play()
	return true


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	if owner_player.attached:
		if owner_player.has_method("clear_active_action"):
			owner_player.call("clear_active_action")
		return
	if owner_player._bounce_state == owner_player.BounceState.NONE:
		if owner_player.has_method("activate_neutral_air_action"):
			owner_player.call("activate_neutral_air_action", {"reason": &"stomp_finished", "source_action": action_id})
		return
	if owner_player._bounce_state != owner_player.BounceState.STOMP:
		if owner_player.has_method("activate_neutral_air_action"):
			owner_player.call("activate_neutral_air_action", {"reason": &"stomp_interrupted", "source_action": action_id})

extends Node
class_name RaceVictoryPresentation

## Camera or marker animated with the character's victory presentation.
@export var camera_anchor_path: NodePath = NodePath("")
## Treats the anchor as a +Z-forward guide instead of a Camera3D transform.
@export var camera_anchor_uses_guide_basis: bool = false
## AnimationTree action name used for the victory presentation.
@export var animation_action: StringName = &"VICTORY"
## Sends the victory animation command to multiplayer peers.
@export var send_animation_over_network: bool = true
## Optional AnimationPlayer used when the presentation is not in the player's AnimationTree.
@export var animation_player_path: NodePath = NodePath("")
## Optional animation played by animation_player_path.
@export var animation_name: StringName = &""

var _animation_player: AnimationPlayer = null


func begin_victory_presentation() -> void:
	var player: Node = _resolve_player()
	if animation_player_path != NodePath(""):
		_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player != null and animation_name != &"" and _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name)
		return
	if player != null and player.has_method("play_action_command_if_exists"):
		player.call("play_action_command_if_exists", animation_action, send_animation_over_network)


func _resolve_player() -> Node:
	var candidate: Node = get_parent()
	while candidate != null:
		if candidate.has_method("play_action_command_if_exists"):
			return candidate
		candidate = candidate.get_parent()
	return null


func end_victory_presentation() -> void:
	if _animation_player != null and is_instance_valid(_animation_player) and _animation_player.is_playing():
		_animation_player.stop()
	_animation_player = null


func get_victory_camera_anchor() -> Node3D:
	if camera_anchor_path == NodePath(""):
		return null
	return get_node_or_null(camera_anchor_path) as Node3D


func victory_camera_uses_guide_basis() -> bool:
	return camera_anchor_uses_guide_basis

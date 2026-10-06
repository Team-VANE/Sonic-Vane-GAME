extends Node

const WAIT_02: AudioStream = preload("res://LS5Framework/Characters/Sonic Neo Adventure/Voice/RaceStart_01.wav")

## Dialogue player used for the temporary Wait_02 lip sync test.
@export_node_path("AudioStreamPlayer3D") var dialogue_player_path: NodePath

@onready var _dialogue_player: AudioStreamPlayer3D = get_node_or_null(dialogue_player_path) as AudioStreamPlayer3D


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_KP_1:
		return
	if not _dialogue_player:
		return
	_dialogue_player.stop()
	_dialogue_player.stream = WAIT_02
	_dialogue_player.play()

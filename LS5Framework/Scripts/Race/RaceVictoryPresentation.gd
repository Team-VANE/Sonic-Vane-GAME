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

## Uses the character AnimationTree intro, boundary-aligned loop exit, and ToIdle sequence.
@export var sequenced_victory: bool = false

## Prompt offset from bottom centre in 1080p reference pixels. Y moves upwards when negative.
@export var waiting_prompt_offset: Vector2 = Vector2(0.0, -90.0)

## Grace period before treating a victory that has not started as missing.
@export_range(0.5, 10.0, 0.1) var startup_grace: float = 3.0
## Delay before treating playback that left the victory states as interrupted.
@export_range(0.5, 10.0, 0.1) var interruption_grace: float = 1.5
## Maximum time without animation progress before recovery begins.
@export_range(1.0, 20.0, 0.1) var stall_timeout: float = 5.0

signal victory_interrupted
signal victory_finished
var _active: bool = false
var _exit_requested: bool = false
var _seen_victory: bool = false
var _seen_exit: bool = false
var _missing_time: float = 0.0
var _stalled_time: float = 0.0
var _last_position: float = -1.0
var _last_state: StringName = &""
var _animation_player: AnimationPlayer = null
var _waiting_input: bool = false
var _jump_released: bool = false
var _input_start_frame: int = -1
var _victory_speed: float = 1.0
var _prompt_slot: StringName = &""
## Screen layer owning the victory waiting prompt.
var _prompt_layer: CanvasLayer
## Contextual jump glyph displayed while waiting for a loop boundary.
var _waiting_prompt: HUDContextualPrompts
const WAITING_PROMPT: PackedScene = preload("res://LS5Framework/Scenes/HUD/HUDContextualPrompts.tscn")
const EXIT_PARAMETER: String = "parameters/StateMachine/Actions/Ground/conditions/VictoryExitRequested"


func _ready() -> void:
	set_process(false)


func begin_victory_presentation() -> void:
	var player: Node = _resolve_player()
	if sequenced_victory and player:
		if player.has_method("prepare_for_goal_sequence"):
			player.prepare_for_goal_sequence()
			player._update_animation(0.0)
		var command: StringName = StringName("CMD_%s" % String(animation_action).to_upper())
		if player.get_animation_director().get_action_backend().resolve(command) == &"":
			victory_interrupted.emit()
			return
		_victory_speed = 1.0
		player.get_animation_director().get_action_backend().victory_playback_scale = 1.0
		_active = true
		set_process(true)
		_seen_victory = false
		_seen_exit = false
		_missing_time = 0.0
		_stalled_time = 0.0
		_last_position = -1.0
		_last_state = &""
		_exit_requested = false
		player.anim_tree.set(EXIT_PARAMETER, false)
		player._trigger_anim_command_immediate(command, send_animation_over_network)
		return
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


func request_victory_exit(skip_wait: bool = false) -> void:
	if skip_wait or not sequenced_victory:
		end_victory_presentation()
		return
	if _active:
		if not _exit_requested:
			_jump_released = false
			_input_start_frame = Engine.get_process_frames()
		_exit_requested = true
		var player: Node = _resolve_player()
		if player and player.anim_tree:
			player.anim_tree.set(EXIT_PARAMETER, true)
		else:
			end_victory_presentation()

func is_victory_active() -> bool:
	return _active

func _process(delta: float) -> void:
	if not _active:
		return
	var player: Node = _resolve_player()
	if not player or not player.anim_tree:
		end_victory_presentation()
		victory_interrupted.emit()
		return
	var playback: AnimationNodeStateMachinePlayback = player.anim_tree.get("parameters/StateMachine/Actions/Ground/playback")
	var state: StringName = playback.get_current_node()
	var playing: bool = player.anim_tree.active and player.anim_state.get_current_node() == &"Actions" and StringName(player.anim_tree.get("parameters/StateMachine/Actions/Select/current_state")) == &"Ground" and state in [&"VictoryIntro", &"VictoryLoop", &"VictoryExit"]
	if playing:
		_seen_victory = true
	if playing and state == &"VictoryExit":
		_seen_exit = true
	var completed: bool = _exit_requested and _seen_victory and ((_seen_exit and player.anim_state.get_current_node() == &"Motion") or (state == &"VictoryExit" and playback.get_current_length() > 0.001 and playback.get_current_play_position() >= playback.get_current_length() - 0.001))
	if completed:
		end_victory_presentation()
		return
	_missing_time = 0.0 if playing else _missing_time + maxf(delta, 0.0)
	if playing:
		var position: float = playback.get_current_play_position()
		_stalled_time = _stalled_time + maxf(delta, 0.0) if state == _last_state and is_equal_approx(position, _last_position) else 0.0
		_last_state = state
		_last_position = position
	if _missing_time >= (interruption_grace if _seen_victory else startup_grace) or _stalled_time >= stall_timeout:
		end_victory_presentation()
		victory_interrupted.emit()
		return
	_waiting_input = _exit_requested and player.anim_state.get_current_node() == &"Actions" and playback.get_current_node() in [&"VictoryIntro", &"VictoryLoop"]
	if _waiting_input:
		_ensure_waiting_prompt(player)
		_position_waiting_prompt()
		var slot: StringName = player.get_ability_input_slot(&"jump", &"ability_slot_01")
		if Engine.get_process_frames() > _input_start_frame:
			if not SettingsManager.is_gameplay_action_pressed(String(slot)):
				_jump_released = true
			elif _jump_released and SettingsManager.is_gameplay_action_just_pressed(String(slot)):
				accelerate_victory()
	elif is_instance_valid(_waiting_prompt):
		_waiting_prompt.hide()

func end_victory_presentation() -> void:
	_waiting_input = false
	_jump_released = false
	_victory_speed = 1.0
	if is_instance_valid(_waiting_prompt):
		_waiting_prompt.hide()
	set_process(false)
	if _active:
		_active = false
		_exit_requested = false
		var player: Node = _resolve_player()
		if player and player.anim_tree:
			player.anim_tree.set(EXIT_PARAMETER, false)
			player.get_animation_director().get_action_backend().victory_playback_scale = 1.0
			player.get_animation_director().get_action_backend().resume_motion(&"victory_end")
		victory_finished.emit()
	if _animation_player != null and is_instance_valid(_animation_player) and _animation_player.is_playing():
		_animation_player.stop()
	_animation_player = null


func get_victory_camera_anchor() -> Node3D:
	if camera_anchor_path == NodePath(""):
		return null
	return get_node_or_null(camera_anchor_path) as Node3D


func victory_camera_uses_guide_basis() -> bool:
	return camera_anchor_uses_guide_basis

func can_offer_action_prompts() -> bool:
	return _waiting_input

func accelerate_victory() -> void:
	if not _waiting_input or not _jump_released:
		return
	_jump_released = false
	_victory_speed = minf(_victory_speed + 0.25, 3.5)
	var player: Node = _resolve_player()
	if player:
		player.get_animation_director().get_action_backend().victory_playback_scale = _victory_speed

func _ensure_waiting_prompt(player: Node) -> void:
	var slot: StringName = player.get_ability_input_slot(&"jump", &"ability_slot_01")
	if is_instance_valid(_waiting_prompt) and _prompt_slot == slot:
		return
	if not is_instance_valid(_waiting_prompt):
		_prompt_layer = CanvasLayer.new()
		_prompt_layer.layer = 110
		add_child(_prompt_layer)
		_waiting_prompt = WAITING_PROMPT.instantiate() as HUDContextualPrompts
		_waiting_prompt.maximum_rows = 1
		_prompt_layer.add_child(_waiting_prompt)
		_waiting_prompt.rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_slot = slot
	var prompts: Array[Dictionary] = [{"id": "victory_speed", "label": "Speed up", "gesture": "press", "contextual": true, "slots": [slot]}]
	_waiting_prompt.set_prompts(prompts, self)

func _position_waiting_prompt() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var ui_scale: float = minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	_waiting_prompt.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_waiting_prompt.size = _waiting_prompt.card_size
	_waiting_prompt.scale = Vector2.ONE * ui_scale
	_waiting_prompt.position = Vector2(viewport_size.x * 0.5, viewport_size.y) + (waiting_prompt_offset - Vector2(_waiting_prompt.card_size.x * 0.5, _waiting_prompt.card_size.y)) * ui_scale

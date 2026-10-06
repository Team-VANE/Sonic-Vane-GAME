extends WorldObject

@export_group("Music")
@export var controller: MusicController
@export var auto_find_controller: bool = true

@export var music_stream: AudioStream
@export var fade_in_time: float = 0.75
@export var fade_out_time: float = 0.5
@export var restart_if_same: bool = false
@export var start_position: float = 0.0

## If true, this trigger stops whatever track is playing instead of starting a new one.
@export var stop_music_instead: bool = false

## If true, this trigger only activates while a race is active or in countdown.
@export var race_only: bool = false

## If true, the trigger requests MusicController.stop_music when the same body exits.
@export var stop_on_exit: bool = false

var _last_controller: MusicController
var _tracked_body_ids: Dictionary = {}


func _ready() -> void:
	super()
	_connect_exit_signal()


func _apply_to_player(player: Node3D) -> void:
	if race_only and not _is_player_in_race(player):
		return
	var music_controller := _get_controller()
	if music_controller == null:
		push_warning("%s: No MusicController available; assign one or enable auto_find_controller." % name)
		return

	if stop_music_instead or music_stream == null:
		music_controller.stop_music_override(fade_out_time)
	else:
		music_controller.play_music_override(
			music_stream,
			fade_in_time,
			fade_out_time,
			restart_if_same,
			start_position
		)

	if stop_on_exit:
		_tracked_body_ids[player.get_instance_id()] = true


func _get_controller() -> MusicController:
	if controller and is_instance_valid(controller):
		_last_controller = controller
		return controller

	if auto_find_controller:
		var controllers := get_tree().get_nodes_in_group("MusicControllers")
		if not controllers.is_empty():
			var first := controllers[0]
			if first is MusicController:
				_last_controller = first
				return first

	return _last_controller if is_instance_valid(_last_controller) else null


func _on_body_exited(body: Node3D) -> void:
	if not stop_on_exit:
		return
	if require_group != "" and not body.is_in_group(require_group):
		return

	var id := body.get_instance_id()
	if not _tracked_body_ids.has(id):
		return
	_tracked_body_ids.erase(id)

	var music_controller := _get_controller()
	if music_controller:
		music_controller.stop_music(fade_out_time)


func _connect_exit_signal() -> void:
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _is_player_in_race(player: Node) -> bool:
	if player == null:
		return false
	if not player.has_method("get"):
		return false
	var in_countdown = player.get("race_in_countdown")
	var active = player.get("race_active")
	var finished = player.get("race_finished")
	var race_in_countdown = in_countdown is bool and bool(in_countdown)
	var race_active = active is bool and bool(active)
	var race_finished = finished is bool and bool(finished)
	return (race_in_countdown or race_active) and not race_finished

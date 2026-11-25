extends Node

const DURATION_USEC: int = 60_000
const TIME_SCALE: float = 0.15

var _player: Node
var _ends_at_usec: int = 0
var _previous_time_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)


func play(player: Node) -> void:
	if not _is_offline(player):
		return
	if _ends_at_usec == 0:
		_previous_time_scale = Engine.time_scale
		Engine.time_scale = _previous_time_scale * TIME_SCALE
	_player = player
	_ends_at_usec = Time.get_ticks_usec() + DURATION_USEC
	set_process(true)


func _process(_delta: float) -> void:
	if Time.get_ticks_usec() >= _ends_at_usec or not _is_offline(_player):
		_stop()


func _exit_tree() -> void:
	_stop()


func _on_connection_state_changed(state: int) -> void:
	if state != NetworkManager.SessionState.IDLE:
		_stop()


func _is_offline(player: Node) -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if NetworkManager.get_session_state() != NetworkManager.SessionState.IDLE:
		return false
	var root_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	var player_peer: MultiplayerPeer = player.multiplayer.multiplayer_peer
	return (not root_peer or root_peer is OfflineMultiplayerPeer) \
		and (not player_peer or player_peer is OfflineMultiplayerPeer)


func _stop() -> void:
	if _ends_at_usec == 0:
		return
	Engine.time_scale = _previous_time_scale
	_ends_at_usec = 0
	_player = null
	set_process(false)

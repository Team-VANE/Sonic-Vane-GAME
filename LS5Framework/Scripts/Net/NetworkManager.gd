extends Node

signal session_started(is_server: bool)
signal session_ended()
signal status_changed(message: String)
signal connection_state_changed(state: int)
signal invite_code_changed(invite_code: String)

enum TransportMode {
	INTERNET,
	DIRECT,
}

enum SessionState {
	IDLE,
	CONNECTING,
	HOSTING,
	JOINED,
}

const CONNECTION_LOG_DIR: String = "user://network_logs"

## Default UDP port for direct-IP sessions.
@export var default_port: int = 8910
## Maximum number of players accepted when no session override is provided.
@export var max_clients: int = 16

@export_group("Noray")
## Noray orchestration server used for internet sessions.
@export var noray_host: String = "tomfol.io"
## TCP command port exposed by the Noray server.
@export var noray_port: int = 8890
## UDP registrar port exposed by the Noray server.
@export var noray_registrar_port: int = 8809
## Maximum time allowed for Noray registration and UDP handshakes.
@export var noray_handshake_timeout: float = 8.0
## Delay between Noray handshake packets.
@export var noray_handshake_interval: float = 0.1
## Maximum time allowed for a client connection attempt.
@export var connection_timeout: float = 30.0

@export_group("ENet")
## Round-trip multiplier used when determining reliable packet timeouts.
@export_range(1, 128, 1) var peer_timeout_factor: int = 32
## Earliest reliable packet timeout during initial scene loading.
@export_range(1000, 300000, 1000) var peer_startup_timeout_minimum_ms: int = 30000
## Maximum initial loading time without a reliable acknowledgement.
@export_range(1000, 300000, 1000) var peer_startup_timeout_maximum_ms: int = 120000
## Earliest reliable packet timeout after peer registration.
@export_range(1000, 300000, 1000) var peer_active_timeout_minimum_ms: int = 5000
## Maximum active-session time without a reliable acknowledgement.
@export_range(1000, 300000, 1000) var peer_active_timeout_maximum_ms: int = 30000

var game_scene_path: String = ""
var last_connect_error: int = OK
var last_failure_log_path: String = ""
var player_name: String = "Player"
var player_color: Color = Color(1, 1, 1, 1)
var player_primary_color: Color = Color(1, 1, 1, 1)
var player_secondary_color: Color = Color(1, 1, 1, 1)
var player_trail_color: Color = Color(0.2, 0.8, 1.0, 1.0)

var _state: SessionState = SessionState.IDLE
var _transport_mode: TransportMode = TransportMode.DIRECT
var _invite_code: String = ""
var _target_invite_code: String = ""
var _pending_oid: String = ""
var _pending_pid: String = ""
var _operation_id: int = 0
var _client_endpoint_active: bool = false
var _using_relay: bool = false
var _noray_signals_wired: bool = false
var _closing_transport: bool = false
var _network_time_load_suspension_depth: int = 0
var _connection_stage: String = ""
var _connection_trace: Array[String] = []
var _connection_started_ms: int = 0
var _connection_timeout_generation: int = 0
var _last_endpoint: String = ""
var _endpoint_generation: int = 0
var _client_handshake_udp: PacketPeerUDP = null


func _ready() -> void:
	_wire_multiplayer_signals()
	call_deferred("_wire_noray_signals")


func is_in_session() -> bool:
	return multiplayer != null and multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_server() -> bool:
	return is_in_session() and multiplayer.is_server()


func is_connecting() -> bool:
	return _state == SessionState.CONNECTING


func get_session_state() -> SessionState:
	return _state


func get_transport_mode() -> TransportMode:
	return _transport_mode


func get_invite_code() -> String:
	return _invite_code


func is_internet_host() -> bool:
	return _state == SessionState.HOSTING and _transport_mode == TransportMode.INTERNET


func get_connection_summary() -> String:
	match _state:
		SessionState.CONNECTING:
			return "Connecting through Noray..." if _transport_mode == TransportMode.INTERNET else "Connecting directly..."
		SessionState.HOSTING:
			if _transport_mode == TransportMode.INTERNET:
				return "Internet host • Invite code %s" % _invite_code
			return "Direct-IP host • UDP %d" % default_port
		SessionState.JOINED:
			if _transport_mode == TransportMode.INTERNET:
				return "Internet client • %s" % ("Relay" if _using_relay else "NAT punch-through")
			return "Direct-IP client"
	return "Offline"


func get_diagnostics_summary() -> String:
	if not is_in_session():
		return ""
	var parts: Array[String] = []
	parts.append("Netfox %d Hz" % NetworkTime.tickrate)
	if not is_server():
		var rtt_ms: int = roundi(NetworkTimeSynchronizer.rtt * 1000.0)
		if rtt_ms > 0:
			parts.append("Ping %d ms" % rtt_ms)
	if NetworkPerformance.is_enabled():
		var payload_percent: int = clampi(
			roundi(NetworkPerformance.get_sent_state_props_ratio() * 100.0),
			0,
			100
		)
		if payload_percent > 0:
			parts.append("State payload %d%%" % payload_percent)
	return " • ".join(parts)


func host(game_scene: String, port: int = -1, max_players: int = -1) -> void:
	var operation: int = _begin_operation(TransportMode.DIRECT, game_scene)
	_set_connection_stage("Creating direct host")
	if port <= 0:
		port = default_port
	var session_limit: int = _resolve_session_limit(max_players)
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	last_connect_error = peer.create_server(port, session_limit)
	if last_connect_error != OK:
		_fail_operation(operation, "Host failed: %s" % error_string(last_connect_error))
		return

	default_port = port
	_set_multiplayer_peer(peer)
	_set_state(SessionState.HOSTING)
	status_changed.emit("Hosting direct-IP session on UDP port %d." % port)
	session_started.emit(true)
	_change_to_game_scene()


func host_internet(game_scene: String, max_players: int = -1) -> void:
	var operation: int = _begin_operation(TransportMode.INTERNET, game_scene)
	var session_limit: int = _resolve_session_limit(max_players)
	_set_connection_stage("Connecting to Noray")
	status_changed.emit("Connecting to the Noray service...")
	var preparation_error: Error = await _prepare_noray(operation)
	if not _is_operation_current(operation):
		return
	last_connect_error = preparation_error
	if last_connect_error != OK:
		_fail_operation(operation, "Internet host setup failed: %s" % error_string(last_connect_error))
		return

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	_set_connection_stage("Binding internet host UDP port")
	last_connect_error = peer.create_server(Noray.local_port, session_limit)
	if last_connect_error != OK:
		_fail_operation(operation, "Internet host failed: %s" % error_string(last_connect_error))
		return

	_invite_code = _pending_oid
	invite_code_changed.emit(_invite_code)
	_set_multiplayer_peer(peer)
	_set_state(SessionState.HOSTING)
	status_changed.emit("Internet session ready. Invite code: %s" % _invite_code)
	session_started.emit(true)
	_change_to_game_scene()


func join(address: String, port: int = -1) -> void:
	var operation: int = _begin_operation(TransportMode.DIRECT)
	_set_connection_stage("Creating direct client")
	if port <= 0:
		port = default_port
	var normalized_address: String = address.strip_edges()
	if normalized_address.is_empty():
		normalized_address = "127.0.0.1"

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	last_connect_error = peer.create_client(normalized_address, port)
	if last_connect_error != OK:
		_fail_operation(operation, "Join failed: %s" % error_string(last_connect_error))
		return

	default_port = port
	_set_multiplayer_peer(peer)
	status_changed.emit("Connecting directly to %s:%d..." % [normalized_address, port])
	_last_endpoint = "%s:%d" % [normalized_address, port]
	_start_connection_timeout(operation, "Direct ENet connection")


func join_with_code(invite_code: String) -> void:
	var normalized_code: String = invite_code.strip_edges()
	if normalized_code.is_empty():
		last_connect_error = ERR_INVALID_PARAMETER
		status_changed.emit("Enter the host's invite code.")
		return

	var operation: int = _begin_operation(TransportMode.INTERNET)
	_target_invite_code = normalized_code
	_set_connection_stage("Connecting to Noray")
	status_changed.emit("Connecting to the Noray service...")
	var preparation_error: Error = await _prepare_noray(operation)
	if not _is_operation_current(operation):
		return
	last_connect_error = preparation_error
	if last_connect_error != OK:
		_fail_operation(operation, "Internet join setup failed: %s" % error_string(last_connect_error))
		return

	status_changed.emit("Requesting a direct route to %s..." % normalized_code)
	_set_connection_stage("Requesting NAT route")
	last_connect_error = Noray.connect_nat(normalized_code)
	if last_connect_error != OK:
		_fail_operation(operation, "Could not request host route: %s" % error_string(last_connect_error))
		return
	_start_connection_timeout(operation, "Noray NAT route response")


func leave() -> void:
	var had_activity: bool = _state != SessionState.IDLE or is_in_session()
	_operation_id += 1
	_connection_timeout_generation += 1
	_close_transport()
	game_scene_path = ""
	_target_invite_code = ""
	_invite_code = ""
	_pending_oid = ""
	_pending_pid = ""
	_client_endpoint_active = false
	_using_relay = false
	_set_state(SessionState.IDLE)
	invite_code_changed.emit("")
	if had_activity:
		session_ended.emit()


func change_scene_keep_session(scene_ref: String) -> void:
	if scene_ref.strip_edges().is_empty():
		return
	game_scene_path = scene_ref
	if is_server():
		rpc("_rpc_set_game_scene", scene_ref)
	_change_scene(scene_ref)


func suspend_network_time_for_level_load() -> bool:
	if not is_in_session() or is_server():
		return false
	if not NetworkTime.is_initial_sync_done():
		return false
	_network_time_load_suspension_depth += 1
	if _network_time_load_suspension_depth == 1:
		NetworkTime.stop()
	return true


func resume_network_time_after_level_load(was_suspended: bool) -> void:
	if not was_suspended:
		return
	_network_time_load_suspension_depth = maxi(_network_time_load_suspension_depth - 1, 0)
	if _network_time_load_suspension_depth > 0:
		return
	if is_in_session() and not is_server():
		NetworkTime.start()


func _begin_operation(mode: TransportMode, game_scene: String = "") -> int:
	leave()
	_operation_id += 1
	_connection_timeout_generation += 1
	_transport_mode = mode
	game_scene_path = game_scene
	last_connect_error = OK
	last_failure_log_path = ""
	_connection_stage = ""
	_connection_trace.clear()
	_connection_started_ms = Time.get_ticks_msec()
	_last_endpoint = ""
	_set_state(SessionState.CONNECTING)
	return _operation_id


func _prepare_noray(operation: int) -> Error:
	_wire_noray_signals()
	if not _noray_signals_wired:
		return ERR_UNAVAILABLE
	_pending_oid = ""
	_pending_pid = ""
	var err: Error = await Noray.connect_to_host(noray_host, noray_port, connection_timeout)
	if not _is_operation_current(operation):
		if _state == SessionState.IDLE and Noray.is_connected_to_host():
			Noray.disconnect_from_host()
		return ERR_CANT_CONNECT
	if err != OK:
		return err

	_set_connection_stage("Waiting for Noray IDs")
	err = Noray.register_host()
	if err != OK:
		return err
	err = await _wait_for_noray_ids(operation)
	if not _is_operation_current(operation):
		if _state == SessionState.IDLE and Noray.is_connected_to_host():
			Noray.disconnect_from_host()
		return ERR_CANT_CONNECT
	if err != OK:
		return err

	status_changed.emit("Registering this connection with Noray...")
	_set_connection_stage("Registering local UDP port with Noray")
	err = await Noray.register_remote(
		noray_registrar_port,
		noray_handshake_timeout,
		noray_handshake_interval
	)
	if not _is_operation_current(operation):
		if _state == SessionState.IDLE and Noray.is_connected_to_host():
			Noray.disconnect_from_host()
		return ERR_CANT_CONNECT
	return err


func _wait_for_noray_ids(operation: int) -> Error:
	var deadline_ms: int = Time.get_ticks_msec() + roundi(noray_handshake_timeout * 1000.0)
	while _pending_oid.is_empty() or _pending_pid.is_empty():
		if not _is_operation_current(operation):
			return ERR_CANT_CONNECT
		if Time.get_ticks_msec() >= deadline_ms:
			return ERR_TIMEOUT
		await get_tree().process_frame
	return OK


func _wire_noray_signals() -> void:
	if _noray_signals_wired:
		return
	var noray: Node = get_node_or_null("/root/Noray")
	if noray == null:
		return
	if not Noray.on_oid.is_connected(_on_noray_oid):
		Noray.on_oid.connect(_on_noray_oid)
	if not Noray.on_pid.is_connected(_on_noray_pid):
		Noray.on_pid.connect(_on_noray_pid)
	if not Noray.on_connect_nat.is_connected(_on_noray_connect_nat):
		Noray.on_connect_nat.connect(_on_noray_connect_nat)
	if not Noray.on_connect_relay.is_connected(_on_noray_connect_relay):
		Noray.on_connect_relay.connect(_on_noray_connect_relay)
	if not Noray.on_disconnect_from_host.is_connected(_on_noray_disconnected):
		Noray.on_disconnect_from_host.connect(_on_noray_disconnected)
	_noray_signals_wired = true


func _wire_multiplayer_signals() -> void:
	if multiplayer == null:
		return
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_noray_oid(oid: String) -> void:
	_pending_oid = oid


func _on_noray_pid(pid: String) -> void:
	_pending_pid = pid


func _on_noray_connect_nat(address: String, port: int) -> void:
	_handle_noray_endpoint(address, port, false)


func _on_noray_connect_relay(address: String, port: int) -> void:
	_handle_noray_endpoint(address, port, true)


func _handle_noray_endpoint(address: String, port: int, is_relay: bool) -> void:
	if address.strip_edges().is_empty() or port <= 0 or port > 65535:
		return
	if _transport_mode != TransportMode.INTERNET:
		return
	if is_server():
		_handle_host_handshake(address, port)
		return
	if _state != SessionState.CONNECTING or _client_endpoint_active or (is_relay != _using_relay):
		return

	_client_endpoint_active = true
	_endpoint_generation += 1
	var endpoint_generation: int = _endpoint_generation
	_using_relay = is_relay
	var operation: int = _operation_id
	_last_endpoint = "%s:%d" % [address, port]
	_set_connection_stage("Testing %s UDP route" % ("relay" if is_relay else "NAT"))
	_start_connection_timeout(operation, "Relay UDP handshake" if is_relay else "NAT UDP handshake")
	status_changed.emit("Testing %s route..." % ("relay" if is_relay else "direct"))

	var udp: PacketPeerUDP = PacketPeerUDP.new()
	_client_handshake_udp = udp
	var err: Error = udp.bind(Noray.local_port)
	if err == OK:
		err = udp.set_dest_address(address, port)
	if err == OK:
		err = await PacketHandshake.over_packet_peer(
			udp,
			noray_handshake_timeout,
			noray_handshake_interval
		)
	udp.close()
	if _client_handshake_udp == udp:
		_client_handshake_udp = null

	if not _is_operation_current(operation) or endpoint_generation != _endpoint_generation:
		return
	_client_endpoint_active = false
	if err != OK and err != ERR_BUSY:
		last_connect_error = err
		_record_connection_event("%s UDP handshake failed: %s" % ["Relay" if is_relay else "NAT", error_string(err)])
		if not is_relay:
			_request_relay(operation, "Direct route unavailable. Requesting relay...")
		else:
			_fail_operation(operation, "Relay handshake failed: %s" % error_string(err))
		return
	if err == ERR_BUSY:
		_record_connection_event("UDP handshake received a response without final acknowledgement")

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	_set_connection_stage("Creating %s ENet client" % ("relay" if is_relay else "NAT"))
	err = peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	if err != OK:
		last_connect_error = err
		_record_connection_event("%s ENet client creation failed: %s" % ["Relay" if is_relay else "NAT", error_string(err)])
		if not is_relay:
			_request_relay(operation, "Direct connection failed. Requesting relay...")
		else:
			_fail_operation(operation, "Relay connection failed: %s" % error_string(err))
		return

	_set_multiplayer_peer(peer)
	_start_connection_timeout(operation, "Relay ENet connection" if is_relay else "NAT ENet connection")
	status_changed.emit("Connecting through %s..." % ("relay" if is_relay else "NAT punch-through"))


func _handle_host_handshake(address: String, port: int) -> void:
	var peer: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return
	await PacketHandshake.over_enet_peer(
		peer,
		address,
		port,
		noray_handshake_timeout,
		noray_handshake_interval
	)


func _request_relay(operation: int, message: String) -> void:
	if not _is_operation_current(operation):
		return
	_record_connection_event(message)
	_close_client_handshake()
	_closing_transport = true
	_close_multiplayer_peer()
	_closing_transport = false
	_client_endpoint_active = false
	_using_relay = true
	_set_connection_stage("Requesting relay route")
	status_changed.emit(message)
	last_connect_error = Noray.connect_relay(_target_invite_code)
	if last_connect_error != OK:
		_fail_operation(operation, "Could not request relay: %s" % error_string(last_connect_error))
		return
	_start_connection_timeout(operation, "Noray relay route response")


func _start_connection_timeout(operation: int, stage: String) -> void:
	_connection_timeout_generation += 1
	var generation: int = _connection_timeout_generation
	_set_connection_stage(stage)
	await get_tree().create_timer(connection_timeout).timeout
	if not _is_operation_current(operation) or generation != _connection_timeout_generation:
		return
	last_connect_error = ERR_TIMEOUT
	_record_connection_event("%s timed out" % stage)
	if _transport_mode == TransportMode.INTERNET and not _using_relay:
		_request_relay(operation, "%s timed out. Requesting relay..." % stage)
		return
	_fail_operation(operation, "%s timed out." % stage)


func _on_connected_to_server() -> void:
	if _state != SessionState.CONNECTING:
		return
	_connection_timeout_generation += 1
	_set_connection_stage("Connected")
	_configure_enet_peer_timeout(1, true)
	_set_state(SessionState.JOINED)
	status_changed.emit("Connected through relay." if _using_relay else "Connected.")
	session_started.emit(false)


func _on_connection_failed() -> void:
	if _closing_transport:
		return
	if _state != SessionState.CONNECTING:
		return
	if _using_relay and not (multiplayer.multiplayer_peer is ENetMultiplayerPeer):
		return
	var operation: int = _operation_id
	last_connect_error = ERR_CONNECTION_ERROR
	if _transport_mode == TransportMode.INTERNET and not _using_relay:
		_request_relay(operation, "NAT connection failed. Requesting relay...")
		return
	_fail_operation(operation, "Relay ENet connection failed." if _using_relay else "Direct ENet connection failed.")


func _on_server_disconnected() -> void:
	if _closing_transport:
		return
	if _state == SessionState.IDLE:
		return
	_operation_id += 1
	_connection_timeout_generation += 1
	_close_transport()
	game_scene_path = ""
	_invite_code = ""
	_target_invite_code = ""
	invite_code_changed.emit("")
	_set_state(SessionState.IDLE)
	status_changed.emit("The host ended the session.")
	session_ended.emit()


func _on_peer_connected(peer_id: int) -> void:
	if not is_server():
		return
	_configure_enet_peer_timeout(peer_id, true)
	if not game_scene_path.is_empty():
		rpc_id(peer_id, "_rpc_set_game_scene", game_scene_path)
	status_changed.emit("%d player(s) connected." % (multiplayer.get_peers().size() + 1))


func _on_peer_disconnected(_peer_id: int) -> void:
	if is_server():
		status_changed.emit("%d player(s) connected." % (multiplayer.get_peers().size() + 1))


func _on_noray_disconnected() -> void:
	if _closing_transport:
		return
	if _transport_mode != TransportMode.INTERNET or _state == SessionState.IDLE:
		return
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		if _state == SessionState.CONNECTING:
			_record_connection_event("Noray control connection closed while ENet was still connecting")
			status_changed.emit("Noray unavailable; waiting for the current game route...")
		else:
			status_changed.emit("Noray unavailable; the active game connection is unchanged.")
		return
	last_connect_error = ERR_CONNECTION_ERROR
	_fail_operation(_operation_id, "Disconnected from the Noray service.")


func confirm_peer_ready(peer_id: int) -> void:
	_configure_enet_peer_timeout(peer_id, false)


func confirm_local_peer_ready() -> void:
	if not is_server():
		_configure_enet_peer_timeout(1, false)


func _configure_enet_peer_timeout(peer_id: int, startup_grace: bool) -> void:
	if multiplayer == null:
		return
	var transport: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport == null:
		return
	var packet_peer: ENetPacketPeer = transport.get_peer(peer_id)
	if packet_peer == null:
		return
	var minimum_ms: int = peer_startup_timeout_minimum_ms if startup_grace else peer_active_timeout_minimum_ms
	var maximum_ms: int = peer_startup_timeout_maximum_ms if startup_grace else peer_active_timeout_maximum_ms
	minimum_ms = maxi(minimum_ms, 1000)
	maximum_ms = maxi(maximum_ms, minimum_ms)
	packet_peer.set_timeout(maxi(peer_timeout_factor, 1), minimum_ms, maximum_ms)


func _set_multiplayer_peer(peer: MultiplayerPeer) -> void:
	NetworkTime.stop()
	_network_time_load_suspension_depth = 0
	multiplayer.multiplayer_peer = peer


func _close_multiplayer_peer() -> void:
	NetworkTime.stop()
	_network_time_load_suspension_depth = 0
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func _close_transport() -> void:
	_closing_transport = true
	_close_client_handshake()
	_close_multiplayer_peer()
	if _noray_signals_wired:
		Noray.disconnect_from_host()
	_closing_transport = false


func _close_client_handshake() -> void:
	_endpoint_generation += 1
	if _client_handshake_udp:
		_client_handshake_udp.close()
	_client_handshake_udp = null


func _resolve_session_limit(requested_limit: int) -> int:
	if requested_limit > 0:
		return clampi(requested_limit, 1, 4095)
	return clampi(max_clients, 1, 4095)


func _set_state(value: SessionState) -> void:
	if _state == value:
		return
	_state = value
	connection_state_changed.emit(_state)


func _is_operation_current(operation: int) -> bool:
	return operation == _operation_id and _state == SessionState.CONNECTING


func _set_connection_stage(stage: String) -> void:
	_connection_stage = stage
	_record_connection_event(stage)


func _record_connection_event(message: String) -> void:
	var elapsed_ms: int = maxi(Time.get_ticks_msec() - _connection_started_ms, 0)
	_connection_trace.append("+%.2f s  %s" % [float(elapsed_ms) / 1000.0, message])


func _write_connection_failure_log(message: String) -> String:
	var absolute_dir: String = ProjectSettings.globalize_path(CONNECTION_LOG_DIR)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK:
		push_error("Could not create network log directory: %s" % error_string(directory_error))
		return ""
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var file_path: String = CONNECTION_LOG_DIR.path_join("connection_failure_%s_%d.log" % [timestamp, Time.get_ticks_msec()])
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("Could not write network connection log: %s" % error_string(FileAccess.get_open_error()))
		return ""
	var peer_status: String = "none"
	if multiplayer and multiplayer.multiplayer_peer:
		peer_status = str(multiplayer.multiplayer_peer.get_connection_status())
	var noray_connected: bool = get_node_or_null("/root/Noray") != null and Noray.is_connected_to_host()
	file.store_line("Sonic Vane connection failure")
	file.store_line("Time: %s" % Time.get_datetime_string_from_system())
	file.store_line("Operation: %s / %s" % ["Internet" if _transport_mode == TransportMode.INTERNET else "Direct IP", "Host" if not game_scene_path.is_empty() else "Join"])
	file.store_line("Stage: %s" % _connection_stage)
	file.store_line("Reason: %s" % message)
	file.store_line("Godot error: %s (%d)" % [error_string(last_connect_error), last_connect_error])
	file.store_line("Elapsed: %.2f s" % (float(Time.get_ticks_msec() - _connection_started_ms) / 1000.0))
	file.store_line("Route: %s" % ("Relay" if _using_relay else "Direct or NAT"))
	file.store_line("Endpoint: %s" % (_last_endpoint if not _last_endpoint.is_empty() else "not received"))
	file.store_line("Local UDP port: %d" % (Noray.local_port if noray_connected else -1))
	file.store_line("Noray TCP connected: %s" % noray_connected)
	file.store_line("Multiplayer peer status: %s" % peer_status)
	file.store_line("Noray server: %s:%d TCP, %d UDP" % [noray_host, noray_port, noray_registrar_port])
	file.store_line("Stage timeout: %.1f s; UDP handshake timeout: %.1f s" % [connection_timeout, noray_handshake_timeout])
	file.store_line("Diagnostic: %s" % _connection_failure_hint())
	file.store_line("Timeline:")
	for event: String in _connection_trace:
		file.store_line("  %s" % event)
	file.flush()
	file.close()
	return ProjectSettings.globalize_path(file_path)


func _connection_failure_hint() -> String:
	if _connection_stage.contains("Noray") and _connection_stage.contains("UDP"):
		return "Noray UDP registration did not complete. Check outbound UDP access to the registrar and local firewall rules."
	if _connection_stage.contains("Noray"):
		return "The Noray control connection did not complete. Check DNS, TCP reachability, and service availability."
	if _connection_stage.contains("relay") or _connection_stage.contains("Relay"):
		return "The relay route did not complete. Check UDP access to the relay and host availability; the stage above distinguishes route, handshake, and ENet failures."
	if _connection_stage.contains("NAT"):
		return "The direct NAT route did not complete. A relay fallback should follow unless Noray became unavailable."
	return "Check the stage, error code, and endpoint above on both peers."


func _fail_operation(operation: int, message: String) -> void:
	if not _is_operation_current(operation):
		return
	if last_connect_error == OK:
		last_connect_error = FAILED
	_record_connection_event("Failed: %s" % message)
	last_failure_log_path = _write_connection_failure_log(message)
	_connection_timeout_generation += 1
	_close_transport()
	game_scene_path = ""
	_invite_code = ""
	_target_invite_code = ""
	_client_endpoint_active = false
	_set_state(SessionState.IDLE)
	invite_code_changed.emit("")
	status_changed.emit("%s\nDiagnostic log: %s" % [message, last_failure_log_path] if not last_failure_log_path.is_empty() else message)
	session_ended.emit()


func _change_to_game_scene() -> void:
	if not game_scene_path.is_empty():
		_change_scene(game_scene_path)


@rpc("authority", "reliable")
func _rpc_set_game_scene(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	game_scene_path = scene_path
	if get_tree() != null:
		var current: Node = get_tree().current_scene
		if current != null and current.scene_file_path == scene_path:
			return
	_change_scene(scene_path)


func _change_scene(scene_ref: String) -> void:
	var packed: Resource = load(scene_ref)
	if packed is PackedScene:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(scene_ref)

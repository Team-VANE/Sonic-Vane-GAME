extends Node
## A noray client for Godot.
##
## See: https://github.com/foxssake/noray

var _peer: StreamPeerTCP = StreamPeerTCP.new()
var _protocol: NorayProtocolHandler = NorayProtocolHandler.new()
var _address: String = ""
var _oid: String = ""
var _pid: String = ""
var _local_port: int = -1

static var _logger: NetfoxLogger = NetfoxLogger._for_noray("Noray")

## Open ID.
##
## [i]read-only[/i], this is set after registering as host.
var oid: String:
	get: return _oid
	set(v): push_error("Trying to set read-only variable oid")

## Private ID.
##
## [i]read-only[/i], this is set after registering as host.
var pid: String:
	get: return _pid
	set(v): push_error("Trying to set read-only variable pid")

## Registered local port.
##
## This is the port that servers should listen on and the port that clients 
## should bind to ( i.e. use as local port ), since this port has been 
## registered with noray as part of this machine's external address, and this
## is the port over which any handshake happens.
##
## [i]read-only[/i], this is set after registering remote.
var local_port: int:
	get: return _local_port
	set(v): push_error("Trying to set read-only variable local_port")

## Emitted for any command received from noray.
signal on_command(command: String, data: String)

## Emitted when connected to noray.
signal on_connect_to_host()

## Emitted when disconnected from noray.
signal on_disconnect_from_host()

## Emitted when an OpenID is received from noray.
signal on_oid(oid: String)

## Emitted when a PrivateID is received from noray.
signal on_pid(pid: String)

## Emitted when a connect over NAT command is received from noray.
signal on_connect_nat(address: String, port: int)

## Emitted when a connect over relay command is received from noray.
signal on_connect_relay(address: String, port: int)

func _enter_tree():
	_protocol.on_command.connect(func (cmd, data): on_command.emit(cmd, data))
	on_command.connect(_handle_commands)

var _connection_generation: int = 0
var _registration_peer: PacketPeerUDP = null


## Connect to noray at host.
func connect_to_host(address: String, port: int = 8890, timeout: float = 30.0) -> Error:
	disconnect_from_host()
	var generation: int = _connection_generation

	_logger.info("Trying to connect to noray at %s:%s", [address, port])
	
	address = IP.resolve_hostname(address, IP.TYPE_IPV4)
	_logger.debug("Resolved noray host to %s", [address])
	if address.is_empty():
		return ERR_CANT_RESOLVE
	
	var err = _peer.connect_to_host(address, port)
	if err != Error.OK:
		return err
		
	_peer.set_no_delay(true)
	_protocol.reset()
	
	var deadline_ms: int = Time.get_ticks_msec() + roundi(maxf(timeout, 1.0) * 1000.0)
	while _peer.get_status() < 2 and Time.get_ticks_msec() < deadline_ms:
		if generation != _connection_generation:
			return ERR_CONNECTION_ERROR
		_peer.poll()
		await get_tree().process_frame
	if generation != _connection_generation:
		return ERR_CONNECTION_ERROR
	if _peer.get_status() < 2:
		_peer.disconnect_from_host()
		return ERR_TIMEOUT
	
	if _peer.get_status() == _peer.STATUS_CONNECTED:
		_address = address
		_logger.info("Connected to noray at %s:%s", [address, port])
		on_connect_to_host.emit()
		return OK
	else:
		_logger.error("Connection failed to noray at %s:%s, connection status %s", [address, port, _peer.get_status()])
		disconnect_from_host()
		return ERR_CONNECTION_ERROR

## Check if connected to any host.
func is_connected_to_host() -> bool:
	return _peer.get_status() == _peer.STATUS_CONNECTED

## Disconnect from noray.
##
## Does nothing if already disconnected.
func disconnect_from_host():
	var was_connected: bool = is_connected_to_host()
	_connection_generation += 1
	if _registration_peer:
		_registration_peer.close()
	_registration_peer = null
	_peer.disconnect_from_host()
	_protocol.reset()
	_oid = ""
	_pid = ""
	_local_port = -1
	if was_connected:
		on_disconnect_from_host.emit()

## Register as host.
func register_host() -> Error:
	return _put_command("register-host")

## Register remote address.
func register_remote(registrar_port: int = 8809, timeout: float = 8, interval: float = 0.1) -> Error:
	if not is_connected_to_host():
		return ERR_CONNECTION_ERROR
		
	if not pid:
		return ERR_UNAUTHORIZED

	var result: Error = ERR_TIMEOUT
	var udp: PacketPeerUDP = PacketPeerUDP.new()
	if _registration_peer:
		_registration_peer.close()
	_registration_peer = udp
	var generation: int = _connection_generation
	var socket_error: Error = udp.bind(0)
	if socket_error == OK:
		socket_error = udp.set_dest_address(_address, registrar_port)
	if socket_error != OK:
		udp.close()
		_registration_peer = null
		return socket_error
	interval = maxf(interval, 0.01)
	
	_logger.debug("Bound UDP to port %s", [udp.get_local_port()])
	
	var packet = pid.to_utf8_buffer()
	
	while timeout > 0:
		if generation != _connection_generation or _registration_peer != udp or not is_connected_to_host():
			udp.close()
			if _registration_peer == udp:
				_registration_peer = null
			return ERR_CONNECTION_ERROR
		socket_error = udp.put_packet(packet)
		if socket_error != OK:
			result = socket_error
			break
		
		while udp.get_available_packet_count() > 0:
			var recv = udp.get_packet().get_string_from_utf8()
			if recv == "OK":
				_local_port = udp.get_local_port()
				_logger.info("Registered local port %s to remote", [_local_port])
				result = OK
				timeout = 0 # Break outer loop
				break
			else:
				_logger.error("Failed to register local port!")
				result = FAILED
				timeout = 0 # Break outer loop
				break
		# Sleep
		await get_tree().create_timer(interval).timeout
		timeout -= interval
	
	udp.close()
	if generation != _connection_generation or _registration_peer != udp or not is_connected_to_host():
		result = ERR_CONNECTION_ERROR
	if _registration_peer == udp:
		_registration_peer = null
	return result

## Connect to a given host by OID over NAT.
func connect_nat(host_oid: String) -> Error:
	return _put_command("connect", host_oid)

## Connect to a given host by OID over relay.
func connect_relay(host_oid: String) -> Error:
	return _put_command("connect-relay", host_oid)

func _process(_delta):
	if not is_connected_to_host():
		return

	_peer.poll()
	if not is_connected_to_host():
		disconnect_from_host()
		on_disconnect_from_host.emit()
		return
	var available = _peer.get_available_bytes()
	if available <= 0:
		return
	
	_protocol.ingest(_peer.get_utf8_string(available))

func _put_command(command: String, data = null) -> Error:
	if not is_connected_to_host():
		return ERR_CONNECTION_ERROR
		
	if data != null:
		_peer.put_data(("%s %s\n" % [command, data]).to_utf8_buffer())
	else:
		_peer.put_data((command + "\n").to_utf8_buffer())

	return OK

func _handle_commands(command: String, data: String):
	if command == "set-oid":
		_oid = data
		on_oid.emit(oid)
		_logger.debug("Saved OID: %s", [oid])
	elif command == "set-pid":
		_pid = data
		on_pid.emit(pid)
		_logger.debug("Saved PID: %s", [pid])
	elif command == "connect":
		var parts = data.split(":")
		if parts.size() != 2 or not parts[1].is_valid_int():
			return
		var host: String = parts[0].strip_edges()
		var port: int = parts[1].to_int()
		if host.is_empty() or port <= 0 or port > 65535:
			return
		_logger.debug("Received connect command to %s:%s", [host, port])
		on_connect_nat.emit(host, port)
	elif command == "connect-relay":
		if not data.is_valid_int():
			return
		var host: String = _address
		var port: int = data.to_int()
		if port <= 0 or port > 65535:
			return
		_logger.debug("Received connect relay command to %s:%s", [host, port])
		on_connect_relay.emit(host, port)
	else:
		_logger.trace("Received command %s %s", [command, data])

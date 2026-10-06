extends Node

signal peer_name_changed(peer_id: int, name: String)
signal race_queue_updated()
signal environment_clock_received(channel: String, hour: float, settings: Dictionary)

var _environment_clocks: Dictionary = {}

## Directory where CHAR_*.tres character docs live.
@export var character_data_dir: String = "res://LS5Framework/Characters"
## Camera rig assigned to the local player.
@export var camera_rig_path: NodePath = NodePath("CameraRig")
## HUD assigned to the local player.
@export var hud_path: NodePath = NodePath("HUD")
@export var players_root_name: String = "Players"
## Fallback player spawn when no level spawn is available.
@export var spawn_point_path: NodePath = NodePath("PlayerSpawn")
## Build identifier compared during online join announcements.
@export var network_build_id: String = ""

var _players_root = null
var _peer_names: Dictionary = {}
var _peer_colors: Dictionary = {}
var _peer_primary_colors: Dictionary = {}
var _peer_secondary_colors: Dictionary = {}
var _peer_trail_colors: Dictionary = {}
var _peer_character_colors_enabled: Dictionary = {}
var _peer_character_ids: Dictionary = {}
var _peer_levels: Dictionary = {}
var _peer_build_mismatch: Dictionary = {}
var _character_scene_cache: Dictionary = {}
var _character_replacement_tokens: Dictionary = {}
var _character_entries_by_id: Dictionary = {}
var _default_character_entry: Dictionary = {}
var _character_catalog_loaded: bool = false
var _chat_ui = null
var _camera_rig = null
var _camera = null
var _local_id: int = 1
var _local_level_id: StringName = &""
var _local_level_ready: bool = false
var _debug_dummy_player: Node = null
var _race_banner = null
var _race_finish_banner = null
var _race_dnf_banner = null
var _race_sfx_player: AudioStreamPlayer = null
var _race_results_choice_pending: bool = false
var _race_results_token: int = 0
var _race_results_local_pending: bool = false
var _race_results_payload: Dictionary = {}
var _race_results_ready: Dictionary = {}
var _race_results_timeout: float = 0.0
var _race_results_releasing: bool = false
var _race_results_ui: Node = null
var _race_results_goal: Node = null
var _race_results_fader: Node = null

const NETWORK_SESSION_GROUP: StringName = &"NetworkSession"
const DEFAULT_CHARACTER_ID: String = "sonic_neo_adventure"
const CHAT_MESSAGE_MAX_LENGTH: int = 240
const CHARACTER_ID_MAX_LENGTH: int = 64
const DEBUG_DUMMY_PEER_ID: int = 2147483000
const DEBUG_DUMMY_NAME: String = "Debug Dummy"
const DEBUG_DUMMY_COLOR: Color = Color(1.0, 0.72, 0.2, 1.0)
var _race_results_choice: StringName = &""
var _hud_restore_attempts: int = 0
var _hud_restore_pending: bool = false

@export_group("Race SFX")
@export var race_sfx_bus: StringName = &"UI"
@export var sfx_race_queue_start: AudioStream = preload("res://LS5Framework/Sounds/Menu/Race_Start_Queue.WAV")

@export_group("Online SFX")
## Bus used for online join and leave sounds.
@export var online_sfx_bus: StringName = &"UI"
## Sound played when a player joins the online session.
@export var sfx_player_joined: AudioStream = preload("res://LS5Framework/Sounds/Menu/menuselect.wav")
## Sound played when a player leaves the online session.
@export var sfx_player_left: AudioStream = preload("res://LS5Framework/Sounds/Menu/menucancel.wav")

@export_group("Results Music")
@export var results_music_stream: AudioStream
@export var results_music_fade_in: float = 0.75
@export var results_music_fade_out: float = 0.5
@export var results_music_restart_if_same: bool = false

const _SUPPRESS_NEXT_AUTOPLAY_META: StringName = &"suppress_next_music_autoplay"

# Race queue (online)
var _race_queue_active: bool = false
var _race_queue_started_by: int = 0
var _race_queue_start_scene: String = ""
var _race_queue_start_path: String = ""
var _race_queue_remaining: float = 0.0
var _race_queue_duration: float = 30.0
var _race_queue_end_duration_override: float = -1.0
var _race_queue_joiners: Dictionary = {}
var _race_join_request_generation: int = -1
var _race_queue_ready: Dictionary = {}
var _race_queue_loaded: Dictionary = {}
var _race_lineup_started: bool = false
var _race_lineup_ready: Dictionary = {}
var _race_countdown_started: bool = false
var _race_setup_generation: int = 0
var _race_queue_broadcast_accum: float = 0.0
var _race_queue_broadcast_interval: float = 0.25
var _race_setup_waiting_for_ready: bool = false
var _race_ready_timeout: float = 0.0
var _race_local_setup_token: int = 0
@export_group("Race Setup")
## Maximum time to wait for every joined player to load and finish race placement before cancelling setup.
@export var race_ready_timeout_default: float = 45.0

# Active race session (after GO)
var _race_session_active: bool = false
var _race_session_participants: Array = []
var _race_session_active_participants: Array = []
var _race_session_goal_path: String = ""
var _race_session_start_scene: String = ""
var _race_session_start_path: String = ""
var _race_session_finish_order: Array = []
var _race_session_finish_time: Dictionary = {}
var _race_session_finish_rings: Dictionary = {}
var _race_session_finish_score: Dictionary = {}
var _race_session_debug_used: Dictionary = {}
var _race_session_dnf: Dictionary = {}
var _race_session_end_active: bool = false
var _race_session_end_remaining: float = 0.0
@export_group("Race Session")
@export var race_session_end_duration_default: float = 60.0
var _race_session_end_duration: float = 60.0
var _race_session_end_broadcast_accum: float = 0.0
var _race_session_end_broadcast_interval: float = 0.25


func _ready() -> void:
	add_to_group("NetworkSession")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	_chat_ui = get_parent().get_node_or_null("ChatUI")
	_players_root = get_parent().get_node_or_null(players_root_name)
	if _players_root == null:
		# Fallback: search for a node with this name if not found via path.
		_players_root = get_parent().find_child(players_root_name, true, false)
	if _players_root == null:
		_players_root = Node3D.new()
		_players_root.name = players_root_name
		get_parent().add_child(_players_root)

	var online = _is_online()
	var local_id = 1
	if online:
		local_id = multiplayer.get_unique_id()
	_local_id = local_id
	_peer_character_ids[local_id] = _get_selected_character_id()

	# Attempt to resolve camera components.
	_camera_rig = get_parent().get_node_or_null(camera_rig_path)
	if _camera_rig == null:
		var rig_nodes = get_tree().get_nodes_in_group("CameraRig")
		if rig_nodes.size() > 0:
			_camera_rig = rig_nodes[0]
	if _camera_rig == null:
		_camera_rig = get_parent().find_child("CameraRig", true, false)

	if _camera_rig != null:
		_camera = _camera_rig.get_node_or_null("CameraYawRig/CameraPitchRig/SonicCamera")
		if _camera == null:
			_camera = _camera_rig.find_child("SonicCamera", true, false)

	if online:
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		var network_manager = get_node_or_null("/root/NetworkManager")
		if network_manager != null and network_manager.has_signal("session_ended"):
			if not network_manager.session_ended.is_connected(_on_network_session_ended):
				network_manager.session_ended.connect(_on_network_session_ended)

	_spawn_player(local_id, true)
	_queue_peer_character_replacement(local_id)

	if online:
		for peer_id in multiplayer.get_peers():
			if peer_id != local_id:
				_spawn_player(peer_id, false)

	_assign_camera_to_local_player(local_id)
	call_deferred("_assign_camera_to_local_player", local_id)

	# Apply offline colors immediately for the local player when running standalone/offline.
	if not online:
		call_deferred("refresh_local_character_colors")

	if online:
		_register_local_character(local_id)
		_register_local_name(local_id)
		var ready_network_manager: Node = get_node_or_null("/root/NetworkManager")
		if ready_network_manager != null and ready_network_manager.has_method("confirm_local_peer_ready"):
			ready_network_manager.call("confirm_local_peer_ready")
		if not multiplayer.is_server():
			rpc_id(1, "_rpc_request_all_peer_info")
			rpc_id(1, "_rpc_request_race_sync")

func _process(delta: float) -> void:
	if not _is_online():
		return
	if not multiplayer.is_server():
		return

	# Race queue (pre-race)
	if _race_queue_active:
		_race_queue_remaining = max(_race_queue_remaining - max(delta, 0.0), 0.0)
		_race_queue_broadcast_accum += max(delta, 0.0)
		if _race_queue_broadcast_accum >= _race_queue_broadcast_interval:
			_race_queue_broadcast_accum = 0.0
			_broadcast_race_queue_state()

		# If everyone is in, start immediately.
		if _all_peers_joined_race():
			_race_queue_remaining = 0.0

		if _race_queue_remaining <= 0.001:
			_server_begin_race_setup()

		# Setup never advances until every connected participant reports ready.
		if _race_setup_waiting_for_ready:
			_race_ready_timeout = max(_race_ready_timeout - max(delta, 0.0), 0.0)
			if _race_ready_timeout <= 0.001:
				_server_cancel_race_queue()

	# Active race (post-GO)
	if not _race_results_payload.is_empty():
		_race_results_timeout = maxf(_race_results_timeout - delta, 0.0)
		if _race_results_timeout <= 0.0:
			_server_release_race_results()
		return
	if _race_session_active and _race_session_end_active:
		_race_session_end_remaining = max(_race_session_end_remaining - max(delta, 0.0), 0.0)
		_race_session_end_broadcast_accum += max(delta, 0.0)
		if _race_session_end_broadcast_accum >= _race_session_end_broadcast_interval:
			_race_session_end_broadcast_accum = 0.0
			_broadcast_race_end_countdown(true, _race_session_end_remaining)
		if _race_session_end_remaining <= 0.001:
			_server_finalize_race_results()


func is_player_tracking_visible() -> bool:
	return get_player_tracking_mode() != 2


func get_player_tracking_mode() -> int:
	var settings: Node = get_node_or_null("/root/SettingsManager")
	if settings == null:
		return 1
	return clampi(int(settings.get("player_tracking_mode")), 0, 2)


func _is_online() -> bool:
	return multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func get_player_node(peer_id: int) -> Node:
	if _players_root == null:
		return null
	return _players_root.get_node_or_null("Player_%d" % peer_id)


func get_local_peer_id() -> int:
	return _local_id


func get_debug_dummy_peer_id() -> int:
	return DEBUG_DUMMY_PEER_ID


func has_debug_dummy_player() -> bool:
	return _debug_dummy_player != null and is_instance_valid(_debug_dummy_player) and _debug_dummy_player.is_inside_tree()


func register_debug_dummy_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _debug_dummy_player != null and is_instance_valid(_debug_dummy_player) and _debug_dummy_player != player:
		_debug_dummy_player.queue_free()
	_debug_dummy_player = player
	if player.has_method("set_display_name"):
		player.call("set_display_name", DEBUG_DUMMY_NAME)
	if player.has_method("set_display_color"):
		player.call("set_display_color", DEBUG_DUMMY_COLOR)
	var exit_callback: Callable = _on_debug_dummy_tree_exited.bind(player)
	if not player.tree_exited.is_connected(exit_callback):
		player.tree_exited.connect(exit_callback)


func unregister_debug_dummy_player(player: Node = null) -> void:
	if player != null and _debug_dummy_player != player:
		return
	_debug_dummy_player = null


func _on_debug_dummy_tree_exited(player: Node) -> void:
	if _debug_dummy_player == player:
		_debug_dummy_player = null


func apply_selected_character_to_local_player() -> void:
	if _is_peer_racing(_local_id):
		return
	if _players_root == null:
		return
	var character_id: String = _get_selected_character_id()
	if character_id == "":
		return
	if _is_online() and multiplayer.is_server():
		_server_set_peer_character(_local_id, character_id)
		return
	_peer_character_ids[_local_id] = character_id
	_queue_peer_character_replacement(_local_id)
	if not _is_online():
		return
	rpc_id(1, "_rpc_request_set_character", character_id)


func _replace_peer_character(peer_id: int) -> void:
	if _players_root == null:
		return
	var is_local: bool = peer_id == _local_id
	var packed: PackedScene = _get_player_scene_for_spawn(peer_id, is_local)
	if packed == null:
		return
	var old_player: Node = get_player_node(peer_id)
	var old_transform: Transform3D = Transform3D.IDENTITY
	var old_velocity: Vector3 = Vector3.ZERO
	var had_old_player: bool = false
	var was_ui_input_blocked: bool = false
	var was_level_load_suspended: bool = false
	if old_player is Node3D:
		had_old_player = true
		old_transform = (old_player as Node3D).global_transform
	if old_player is CharacterBody3D:
		old_velocity = (old_player as CharacterBody3D).velocity
	if is_local and old_player != null and old_player.has_method("is_ui_input_blocked"):
		was_ui_input_blocked = bool(old_player.call("is_ui_input_blocked"))
	if is_local and old_player != null:
		var suspended_value: Variant = old_player.get("_level_load_suspended")
		was_level_load_suspended = suspended_value is bool and bool(suspended_value)
	if old_player != null and String(old_player.scene_file_path) == String(packed.resource_path):
		_apply_peer_info_to_player(peer_id)
		_apply_peer_level_to_player(peer_id)
		return
	if old_player != null and is_instance_valid(old_player):
		if is_local and old_player.has_method("despawn_buddy"):
			old_player.call("despawn_buddy")
		_clear_player_target_references(old_player)
		_players_root.remove_child(old_player)
		old_player.queue_free()
	_spawn_player(peer_id, is_local)
	var new_player: Node = get_player_node(peer_id)
	if had_old_player and new_player is Node3D:
		(new_player as Node3D).global_transform = old_transform
	if new_player is CharacterBody3D:
		(new_player as CharacterBody3D).velocity = old_velocity
	if had_old_player and new_player != null:
		if is_local and new_player.has_method("_network_initialize_spawn_state"):
			new_player.call("_network_initialize_spawn_state", old_transform)
			if new_player.has_method("_network_publish_teleport_state"):
				new_player.call("_network_publish_teleport_state")
		elif not is_local and new_player.has_method("_network_prepare_remote_scene_state"):
			new_player.call("_network_prepare_remote_scene_state", old_transform)
	if is_local:
		if was_ui_input_blocked and new_player != null and new_player.has_method("set_ui_input_blocked"):
			new_player.call("set_ui_input_blocked", true)
		if was_level_load_suspended and new_player != null and new_player.has_method("set_level_load_suspended"):
			new_player.call("set_level_load_suspended", true)
		_assign_camera_to_local_player(_local_id)
		call_deferred("_assign_camera_to_local_player", _local_id)
		call_deferred("refresh_local_character_colors")


func _queue_peer_character_replacement(peer_id: int) -> void:
	var token: int = int(_character_replacement_tokens.get(peer_id, 0)) + 1
	_character_replacement_tokens[peer_id] = token
	_prepare_peer_character_replacement(peer_id, token)


func _prepare_peer_character_replacement(peer_id: int, token: int) -> void:
	var character_id: String = String(_peer_character_ids.get(peer_id, "")).strip_edges()
	if character_id == "" and peer_id == _local_id:
		character_id = _get_selected_character_id()
	if character_id == "":
		return
	var packed: PackedScene = _load_character_scene(character_id)
	if packed == null:
		var entry: Dictionary = _get_character_entry(character_id)
		var scene_path: String = String(entry.get("scene", "")).strip_edges()
		if scene_path == "":
			return
		var request_error: Error = ResourceLoader.load_threaded_request(scene_path)
		if request_error != OK and request_error != ERR_BUSY:
			push_warning(
				"NetworkSession: character scene request failed for %s: %s" % [
					scene_path,
					error_string(request_error)
				]
			)
			return
		while true:
			var status: int = ResourceLoader.load_threaded_get_status(scene_path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var loaded_scene: Resource = ResourceLoader.load_threaded_get(scene_path)
				if loaded_scene is PackedScene:
					packed = loaded_scene as PackedScene
					_character_scene_cache[character_id.to_lower()] = packed
					LevelPreparationManager.store_resource(
						scene_path,
						packed,
						LevelPreparationManager.SCOPE_CHARACTER
					)
				break
			if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("NetworkSession: character scene failed to load: %s" % scene_path)
				return
			if get_tree() == null:
				return
			await get_tree().process_frame
	if packed == null or int(_character_replacement_tokens.get(peer_id, 0)) != token:
		return
	if String(_peer_character_ids.get(peer_id, "")).nocasecmp_to(character_id) != 0:
		return
	_replace_peer_character(peer_id)


func _clear_player_target_references(player: Node) -> void:
	if player == null or get_tree() == null:
		return
	for rival in get_tree().get_nodes_in_group("RivalActor"):
		if rival != null and is_instance_valid(rival) and rival.has_method("clear_rival_target_reference"):
			rival.call("clear_rival_target_reference", player)


func get_local_player() -> Node:
	return get_player_node(_local_id)


func get_peer_info_list() -> Array:
	var out: Array = []
	for id in _peer_names.keys():
		var pid: int = int(id)
		var d: Dictionary = {}
		d["peer_id"] = pid
		d["name"] = String(_peer_names[id])
		var c = Color(1, 1, 1, 1)
		if _peer_colors.has(pid):
			c = _peer_colors[pid]
		d["color"] = c
		out.append(d)
	if has_debug_dummy_player():
		out.append({
			"peer_id": DEBUG_DUMMY_PEER_ID,
			"name": DEBUG_DUMMY_NAME,
			"color": DEBUG_DUMMY_COLOR,
		})
	out.sort_custom(func(a, b): return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0)))
	return out


func set_local_level_id(level_id: StringName) -> void:
	_local_level_ready = false
	var normalized: StringName = level_id if level_id != null else &""
	_local_level_id = normalized
	_peer_levels[_local_id] = normalized
	_apply_peer_level_to_player(_local_id)
	_refresh_player_level_visibility()
	_refresh_network_visibility()
	if not _is_online():
		return
	if multiplayer.is_server():
		rpc("_rpc_set_peer_level", _local_id, String(normalized))
	else:
		rpc_id(1, "_rpc_request_set_level", String(normalized))


func on_local_level_ready() -> void:
	_local_level_ready = true
	if _players_root == null:
		return
	var spawn: Node3D = _get_player_spawn_node()
	if spawn == null:
		return
	for player: Node in _players_root.get_children():
		if not (player is Node3D):
			continue
		var peer_id: int = _parse_peer_id_from_node(player.name)
		if peer_id < 0:
			continue
		var peer_level: StringName = _peer_levels.get(peer_id, &"")
		if (
			peer_id != _local_id
			and peer_level != &""
			and _local_level_id != &""
			and peer_level != _local_level_id
		):
			continue
		var initial_transform: Transform3D = (player as Node3D).global_transform
		if peer_id != _local_id:
			initial_transform = DownwarpUtil.apply_downwarp_from_node(
				spawn,
				spawn.global_transform,
				[player]
			)
			(player as Node3D).global_transform = initial_transform
			if player is CharacterBody3D:
				(player as CharacterBody3D).velocity = Vector3.ZERO
			if player.has_method("_network_prepare_remote_scene_state"):
				player.call("_network_prepare_remote_scene_state", initial_transform)
			elif player.has_method("_network_initialize_spawn_state"):
				player.call("_network_initialize_spawn_state", initial_transform)
			call_deferred("_request_initial_player_state", peer_id)
		elif player.has_method("_network_initialize_spawn_state"):
			player.call("_network_initialize_spawn_state", initial_transform)
			if player.has_method("_network_publish_teleport_state"):
				player.call("_network_publish_teleport_state")


func get_race_queue_state() -> Dictionary:
	var st: Dictionary = {}
	st["active"] = _race_queue_active
	st["remaining"] = _race_queue_remaining
	st["starter_id"] = _race_queue_started_by
	st["start_scene"] = _race_queue_start_scene
	st["start_path"] = _race_queue_start_path
	st["joined"] = _race_queue_joiners.has(_local_id) or _race_join_request_generation == _race_setup_generation
	st["busy"] = is_race_busy()
	st["joinable"] = _race_queue_active and not _race_setup_waiting_for_ready and not _race_session_active
	return st


func is_race_busy() -> bool:
	return _race_queue_active or _race_setup_waiting_for_ready or _race_session_active or _race_results_local_pending


func is_race_session_active() -> bool:
	return _race_session_active


func request_start_race(level_scene_path: String, race_start_path: String, queue_duration: float = 30.0, dnf_duration: float = -1.0) -> void:
	if not _is_online():
		return
	if is_race_busy():
		return
	_end_local_race_before_queue()
	if multiplayer.is_server():
		_server_start_race_queue(_local_id, level_scene_path, race_start_path, queue_duration, dnf_duration)
	else:
		rpc_id(1, "_rpc_request_start_race", level_scene_path, race_start_path, queue_duration, dnf_duration)


func request_join_race() -> void:
	if not _is_online():
		return
	if _race_queue_joiners.has(_local_id):
		return
	if _race_join_request_generation == _race_setup_generation:
		return
	if not _race_queue_active:
		return
	if _race_session_active or _race_setup_waiting_for_ready:
		return
	_end_local_race_before_queue()
	if multiplayer.is_server():
		_server_join_race(_local_id)
	else:
		_race_join_request_generation = _race_setup_generation
		race_queue_updated.emit()
		rpc_id(1, "_rpc_request_join_race", _race_setup_generation)


func leave_queue() -> void:
	_race_join_request_generation = -1
	if not _is_online():
		return
	if not _race_queue_active:
		return
	if multiplayer.is_server():
		_server_leave_queue(_local_id)
	else:
		rpc_id(1, "_rpc_leave_queue", _race_setup_generation)


@rpc("any_peer", "reliable")
func _rpc_leave_queue(generation: int) -> void:
	if generation != _race_setup_generation:
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_leave_queue(sender)


func _server_leave_queue(peer_id: int) -> void:
	if not _race_queue_active:
		return
	if peer_id == _race_queue_started_by:
		_server_cancel_race_queue()
		return

	_server_remove_peer_from_race_queue(peer_id)


func notify_race_ready() -> void:
	if not _is_online() or not _race_queue_active:
		return
	if multiplayer.is_server():
		_server_mark_ready(_local_id)
	else:
		rpc_id(1, "_rpc_race_ready", _race_setup_generation)


@rpc("any_peer", "reliable")
func _rpc_request_start_race(level_scene_path: String, race_start_path: String, queue_duration: float, dnf_duration: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_start_race_queue(sender, level_scene_path, race_start_path, queue_duration, dnf_duration)


@rpc("any_peer", "reliable")
func _rpc_request_join_race(generation: int) -> void:
	if generation != _race_setup_generation:
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_join_race(sender)


func _end_local_race_before_queue() -> void:
	var p = get_player_node(_local_id)
	if p == null or not p.has_method("get"):
		return
	var in_race := false
	var v = p.get("race_in_countdown")
	if v is bool and bool(v):
		in_race = true
	var v2 = p.get("race_active")
	if v2 is bool and bool(v2):
		in_race = true
	var v3 = p.get("race_session_joined")
	if v3 is bool and bool(v3):
		in_race = true
	var v4 = p.get("race_finished")
	if v4 is bool and bool(v4):
		in_race = true
	if not in_race:
		return
	if p.has_method("force_leave_race_for_scene_change"):
		p.call("force_leave_race_for_scene_change")
		return
	if p.has_method("leave_race"):
		p.call("leave_race", false)
	if p.has_method("set"):
		p.set("race_session_joined", false)
		p.set("race_in_countdown", false)
		p.set("race_active", false)
		p.set("race_finished", false)
	if p.has_method("_cleanup_race_ui_local"):
		p.call("_cleanup_race_ui_local")
	if p.has_method("_unlock_local_camera_constraints"):
		p.call("_unlock_local_camera_constraints")


@rpc("any_peer", "reliable")
func _rpc_race_ready(generation: int) -> void:
	if generation != _race_setup_generation:
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_mark_ready(sender)


func _server_start_race_queue(starter_id: int, level_scene_path: String, race_start_path: String, queue_duration: float, dnf_duration: float) -> void:
	if is_race_busy():
		return
	if not _server_is_peer_connected(starter_id) or not is_finite(queue_duration) or not is_finite(dnf_duration):
		return
	if not level_scene_path.begins_with("res://LS5Framework/") or not level_scene_path.ends_with(".tscn") or level_scene_path.contains(".."):
		return
	if race_start_path.begins_with("/") or race_start_path.contains(".."):
		return
	if _race_queue_active:
		return
	if _race_session_active:
		return
	if race_start_path.strip_edges() == "" or level_scene_path.strip_edges() == "":
		return
	_race_setup_generation += 1
	_race_queue_active = true
	_race_queue_started_by = starter_id
	_race_queue_start_scene = level_scene_path
	_race_queue_start_path = race_start_path
	_race_queue_duration = clampf(queue_duration, 0.0, 300.0)
	_race_queue_remaining = _race_queue_duration
	if dnf_duration >= 0.0:
		_race_queue_end_duration_override = max(dnf_duration, 0.0)
	else:
		_race_queue_end_duration_override = -1.0
	_race_queue_joiners.clear()
	_race_queue_ready.clear()
	_race_queue_loaded.clear()
	_race_lineup_started = false
	_race_lineup_ready.clear()
	_race_countdown_started = false
	_race_queue_joiners[starter_id] = true
	rpc("_rpc_play_race_queue_start_sfx")
	_broadcast_race_queue_state()


func _server_join_race(peer_id: int) -> void:
	if not _race_queue_active or _race_setup_waiting_for_ready or not _server_is_peer_connected(peer_id):
		return
	_race_queue_joiners[peer_id] = true
	_broadcast_race_queue_state()


func _server_mark_ready(peer_id: int) -> void:
	if not _race_queue_active or not _race_setup_waiting_for_ready or not _race_countdown_started:
		return
	if not _race_queue_joiners.has(peer_id):
		return
	_race_queue_ready[peer_id] = true
	if _all_joiners_ready():
		_broadcast_race_go()


func _all_peers_joined_race() -> bool:
	var total: int = 1
	if multiplayer != null:
		total += multiplayer.get_peers().size()
	var joined: int = _race_queue_joiners.keys().size()
	return _race_queue_active and joined >= total


func _all_joiners_ready() -> bool:
	for id in _race_queue_joiners.keys():
		var pid: int = int(id)
		if not _race_queue_ready.has(pid):
			return false
	return _race_queue_active and _race_queue_joiners.keys().size() > 0


func _broadcast_race_queue_state() -> void:
	var joiners: Array = []
	for id in _race_queue_joiners.keys():
		joiners.append(int(id))
	# `call_local` on the RPC handles the server too; avoid double-updating.
	rpc(
		"_rpc_race_queue_state",
		_race_queue_active,
		_race_queue_started_by,
		_race_queue_start_scene,
		_race_queue_start_path,
		_race_queue_remaining,
		joiners,
		_race_setup_waiting_for_ready,
		_race_setup_generation
	)


@rpc("authority", "reliable", "call_local")
func _rpc_race_queue_state(
		active: bool,
		starter_id: int,
		race_start_scene: String,
		race_start_path: String,
		remaining: float,
		joiners: Array,
		setup_waiting_for_ready: bool = false,
		generation: int = 0
	) -> void:
	if generation < _race_setup_generation:
		return
	_race_setup_generation = generation
	_race_queue_active = active
	_race_setup_waiting_for_ready = setup_waiting_for_ready
	_race_queue_started_by = starter_id
	_race_queue_start_scene = race_start_scene
	_race_queue_start_path = race_start_path
	_race_queue_remaining = max(remaining, 0.0)
	var was_joined: bool = _race_queue_joiners.has(_local_id)
	_race_queue_joiners.clear()
	for j in joiners:
		_race_queue_joiners[int(j)] = true
	if not active or setup_waiting_for_ready or generation != _race_join_request_generation or _race_queue_joiners.has(_local_id):
		_race_join_request_generation = -1
	if was_joined and not _race_queue_joiners.has(_local_id) and not _race_session_active:
		_rpc_race_setup_cancelled(race_start_scene, race_start_path)
	_update_race_banner()
	emit_signal("race_queue_updated")


func _server_begin_race_setup() -> void:
	if not _race_queue_active:
		return
	if _race_setup_waiting_for_ready:
		return
	# Freeze the queue state now; begin setup for all joiners.
	var start_scene: String = _race_queue_start_scene
	var start_path: String = _race_queue_start_path
	var joiners: Array = []
	for id in _race_queue_joiners.keys():
		joiners.append(int(id))
	_race_queue_ready.clear()
	_race_queue_loaded.clear()
	_race_lineup_started = false
	_race_lineup_ready.clear()
	_race_countdown_started = false
	_race_setup_waiting_for_ready = true
	_race_ready_timeout = max(race_ready_timeout_default, 0.0)
	# Keep queue active during setup so clients can still query state; remaining is 0.
	_race_queue_remaining = 0.0
	_broadcast_race_queue_state()

	for id in joiners:
		var pid: int = int(id)
		if pid == _local_id:
			continue
		rpc_id(pid, "_rpc_race_begin_setup", start_scene, start_path, _race_setup_generation)
	# Server-local start
	if _race_queue_joiners.has(_local_id):
		_rpc_race_begin_setup(start_scene, start_path, _race_setup_generation)


@rpc("authority", "reliable", "call_local")
func _rpc_race_begin_setup(race_start_scene: String, race_start_path: String, generation: int) -> void:
	if generation != _race_setup_generation or not _race_queue_joiners.has(_local_id):
		return
	if race_start_scene.strip_edges() == "" or race_start_path.strip_edges() == "":
		return
	_race_setup_generation = generation
	_race_lineup_started = false
	_race_local_setup_token += 1
	_prepare_local_race_setup_async(race_start_scene, race_start_path, _race_local_setup_token)


func _prepare_local_race_setup_async(
		race_start_scene: String,
		race_start_path: String,
		setup_token: int
	) -> void:
	var level_manager: Node = _get_level_manager()
	if level_manager == null or not level_manager.has_method("ensure_level_ready_by_scene_path"):
		_notify_race_setup_failed()
		return
	var current_level_scene: String = ""
	if level_manager.has_method("get_current_level_scene_path"):
		current_level_scene = String(level_manager.call("get_current_level_scene_path"))
	var suppressed_autoplay: bool = current_level_scene != race_start_scene
	if suppressed_autoplay:
		_request_suppress_next_music_autoplay()
	var level_ready_value: Variant = await level_manager.call(
		"ensure_level_ready_by_scene_path",
		race_start_scene,
		StringName(""),
		NodePath(""),
		false,
		false
	)
	if setup_token != _race_local_setup_token:
		if suppressed_autoplay and not _is_peer_racing(_local_id):
			var tree: SceneTree = get_tree()
			if tree and tree.has_meta(_SUPPRESS_NEXT_AUTOPLAY_META):
				tree.remove_meta(_SUPPRESS_NEXT_AUTOPLAY_META)
			_restore_autoplay_music()
		return
	if not bool(level_ready_value):
		_notify_race_setup_failed()
		return
	var rs: Node = _resolve_race_start_node(race_start_scene, race_start_path)
	if rs == null or not is_instance_valid(rs):
		_notify_race_setup_failed()
		return
	var local_player: Node = get_player_node(_local_id)
	if local_player == null or not is_instance_valid(local_player):
		_notify_race_setup_failed()
		return
	while _is_online() and setup_token == _race_local_setup_token and _race_queue_active and _race_queue_joiners.has(_local_id):
		var all_present: bool = _local_level_ready
		for peer_id: int in _race_queue_joiners:
			var participant: Node = get_player_node(peer_id)
			if not participant or not participant.is_node_ready() or _peer_levels.get(peer_id, &"") != _local_level_id:
				all_present = false
		if all_present:
			break
		await get_tree().process_frame
	if not _is_online() or setup_token != _race_local_setup_token or not _race_queue_active or not _race_queue_joiners.has(_local_id):
		return
	if multiplayer.is_server():
		_server_mark_race_loaded(_local_id, _race_setup_generation)
	else:
		rpc_id(1, "_rpc_race_loaded", _race_setup_generation)


@rpc("any_peer", "reliable")
func _rpc_race_loaded(generation: int) -> void:
	if multiplayer.is_server():
		_server_mark_race_loaded(multiplayer.get_remote_sender_id(), generation)


func _server_mark_race_loaded(peer_id: int, generation: int) -> void:
	if generation != _race_setup_generation or not _race_setup_waiting_for_ready or not _race_queue_joiners.has(peer_id):
		return
	_race_queue_loaded[peer_id] = true
	_server_try_begin_lineup()


func _server_try_begin_lineup() -> void:
	if not _race_setup_waiting_for_ready or _race_lineup_started or _race_queue_joiners.is_empty():
		return
	for peer_id: int in _race_queue_joiners:
		if not _race_queue_loaded.has(peer_id):
			return
	_race_lineup_started = true
	_race_ready_timeout = maxf(race_ready_timeout_default, 0.0)
	for peer_id: int in _race_queue_joiners.keys():
		if peer_id != _local_id:
			rpc_id(peer_id, "_rpc_race_begin_lineup", _race_setup_generation)
	if _race_queue_joiners.has(_local_id):
		_rpc_race_begin_lineup(_race_setup_generation)


@rpc("authority", "reliable", "call_remote")
func _rpc_race_begin_lineup(generation: int) -> void:
	if generation != _race_setup_generation or not _race_setup_waiting_for_ready:
		return
	var rs: Node = _resolve_race_start_node(_race_queue_start_scene, _race_queue_start_path)
	var local_player: Node = get_player_node(_local_id)
	if not rs or not local_player or not rs.has_method("start_race_for_player_networked"):
		_notify_race_setup_failed()
		return
	_race_lineup_started = true
	_update_race_banner()
	local_player.set("race_session_joined", true)
	rs.call("start_race_for_player_networked", local_player, false)


func _notify_race_setup_failed() -> void:
	if not _is_online():
		return
	if multiplayer.is_server():
		_server_cancel_race_queue()
	else:
		rpc_id(1, "_rpc_race_setup_failed", _race_setup_generation)


@rpc("any_peer", "reliable")
func _rpc_race_setup_failed(generation: int) -> void:
	if generation != _race_setup_generation or not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _race_queue_joiners.has(sender):
		_server_cancel_race_queue()


func _broadcast_race_go() -> void:
	if not _race_queue_active:
		return
	if not _race_setup_waiting_for_ready or not _all_joiners_ready():
		return
	# Start the race session using the current joiners.
	_race_session_active = true
	_race_session_participants = []
	_race_session_active_participants = []
	for id in _race_queue_joiners.keys():
		var pid: int = int(id)
		_race_session_participants.append(pid)
		_race_session_active_participants.append(pid)
	_race_results_payload.clear()
	_race_session_goal_path = ""
	_race_session_start_scene = _race_queue_start_scene
	_race_session_start_path = _race_queue_start_path
	_race_session_finish_order = []
	_race_session_finish_time.clear()
	_race_session_finish_rings.clear()
	_race_session_finish_score.clear()
	_race_session_debug_used.clear()
	_race_session_dnf.clear()
	_race_session_end_active = false
	_race_session_end_remaining = 0.0
	_race_session_end_duration = max(race_session_end_duration_default, 0.0)
	_server_apply_race_end_duration_from_start_path(_race_queue_start_scene, _race_queue_start_path)

	rpc("_rpc_race_session_state", true, _race_session_participants, _race_session_start_scene, _race_session_start_path, _race_setup_generation)
	for participant_id: int in _race_session_participants:
		if participant_id == _local_id:
			_rpc_race_go(_race_queue_start_scene, _race_queue_start_path, _race_setup_generation)
		else:
			rpc_id(participant_id, "_rpc_race_go", _race_queue_start_scene, _race_queue_start_path, _race_setup_generation)
	# End the queue after GO is issued (and notify all clients).
	_race_queue_active = false
	_race_queue_started_by = 0
	_race_queue_start_scene = ""
	_race_queue_start_path = ""
	_race_queue_remaining = 0.0
	_race_queue_end_duration_override = -1.0
	_race_queue_joiners.clear()
	_race_queue_ready.clear()
	_race_queue_loaded.clear()
	_race_lineup_started = false
	_race_lineup_ready.clear()
	_race_countdown_started = false
	_race_setup_waiting_for_ready = false
	_race_ready_timeout = 0.0
	rpc("_rpc_race_queue_state", false, 0, "", "", 0.0, [], false, _race_setup_generation)

func _server_apply_race_end_duration_from_start_path(race_start_scene: String, race_start_path: String) -> void:
	if _race_queue_end_duration_override >= 0.0:
		_race_session_end_duration = max(_race_queue_end_duration_override, 0.0)
		return
	if race_start_scene.strip_edges() == "" or race_start_path.strip_edges() == "":
		return
	var rs = _resolve_race_start_node(race_start_scene, race_start_path)
	if rs == null or not is_instance_valid(rs):
		return
	if not rs.has_method("get"):
		return
	var v = rs.get("online_dnf_countdown_duration")
	if v is float:
		_race_session_end_duration = max(float(v), 0.0)


func _resolve_race_start_node(race_start_scene: String, race_start_path: String) -> Node:
	var scene_path: String = race_start_scene.strip_edges()
	var node_path: NodePath = NodePath(race_start_path)
	if scene_path == "" or race_start_path.strip_edges() == "":
		return null

	var level_manager = _get_level_manager()
	if level_manager != null:
		var current_scene: String = ""
		if level_manager.has_method("get_current_level_scene_path"):
			current_scene = String(level_manager.call("get_current_level_scene_path"))
		if current_scene != scene_path:
			return null
		if level_manager.has_method("resolve_node_in_current_level"):
			var n = level_manager.call("resolve_node_in_current_level", node_path)
			if n != null:
				return n
		if level_manager.has_method("get_current_level"):
			var level = level_manager.call("get_current_level")
			if level != null and is_instance_valid(level):
				return level.get_node_or_null(node_path)

	if get_tree() != null and get_tree().current_scene != null:
		var current_scene_root: Node = get_tree().current_scene
		if String(current_scene_root.scene_file_path) == scene_path:
			return current_scene_root.get_node_or_null(node_path)
	return null


func leave_race(from_respawn: bool) -> void:
	_race_join_request_generation = -1
	cancel_local_race_presentation()
	if not _is_online():
		return
	if multiplayer.is_server():
		_server_leave_race(_local_id, from_respawn)
	else:
		rpc_id(1, "_rpc_leave_race", from_respawn, _race_setup_generation)


@rpc("any_peer", "reliable")
func _rpc_leave_race(from_respawn: bool, generation: int) -> void:
	if generation != _race_setup_generation:
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_leave_race(sender, from_respawn)


func _server_leave_race(peer_id: int, _from_respawn: bool) -> void:
	_server_remove_peer_from_race_queue(peer_id)
	if _race_session_active and _race_session_active_participants.has(peer_id):
		var was_active: bool = _race_session_active_participants.has(peer_id)
		_race_session_dnf[peer_id] = true
		_race_session_active_participants.erase(peer_id)
		_race_results_ready.erase(peer_id)
		if was_active:
			_broadcast_race_leave_announcement(peer_id)
		if not _server_has_connected_race_participant():
			_server_clear_race_session()
			return
		if not _race_results_payload.is_empty():
			_server_try_release_race_results()
		elif not _server_has_unfinished_active_racer():
			_server_finalize_race_results()


func _server_remove_peer_from_race_queue(peer_id: int) -> void:
	if not _race_queue_active or not _race_queue_joiners.has(peer_id):
		return
	_race_queue_joiners.erase(peer_id)
	if peer_id == _race_queue_started_by and not _race_queue_joiners.is_empty():
		_race_queue_started_by = int(_race_queue_joiners.keys()[0])
	_race_queue_ready.erase(peer_id)
	_race_queue_loaded.erase(peer_id)
	_race_lineup_ready.erase(peer_id)
	if _race_queue_joiners.is_empty():
		_server_cancel_race_queue()
		return
	_broadcast_race_queue_state()
	_server_try_begin_lineup()
	_server_try_begin_countdown()
	if _race_setup_waiting_for_ready and _all_joiners_ready():
		_broadcast_race_go()


func _server_cancel_race_queue() -> void:
	var cancelled_scene: String = _race_queue_start_scene
	var cancelled_path: String = _race_queue_start_path
	var cancelled_joiners: Array = _race_queue_joiners.keys()
	var setup_was_active: bool = _race_setup_waiting_for_ready
	_race_queue_active = false
	_race_queue_started_by = 0
	_race_queue_start_scene = ""
	_race_queue_start_path = ""
	_race_queue_remaining = 0.0
	_race_queue_end_duration_override = -1.0
	_race_queue_joiners.clear()
	_race_queue_ready.clear()
	_race_queue_loaded.clear()
	_race_lineup_started = false
	_race_lineup_ready.clear()
	_race_countdown_started = false
	_race_setup_waiting_for_ready = false
	_race_ready_timeout = 0.0
	if setup_was_active:
		for pid: int in cancelled_joiners:
			if pid == _local_id:
				_rpc_race_setup_cancelled(cancelled_scene, cancelled_path)
			elif _server_is_peer_connected(pid):
				rpc_id(pid, "_rpc_race_setup_cancelled", cancelled_scene, cancelled_path)
		_broadcast_server_notice("Race start cancelled before every participant was ready.", &"")
	rpc("_rpc_race_queue_state", false, 0, "", "", 0.0, [], false, _race_setup_generation)


@rpc("authority", "reliable", "call_local")
func _rpc_race_setup_cancelled(race_start_scene: String, race_start_path: String) -> void:
	_race_local_setup_token += 1
	var local_player: Node = get_local_player()
	var race_start: Node = _resolve_race_start_node(race_start_scene, race_start_path)
	if race_start and race_start.has_method("cancel_for_player"):
		race_start.call("cancel_for_player", local_player)
	if local_player and local_player.has_method("leave_race"):
		local_player.call("leave_race", false)


func _server_has_connected_race_participant() -> bool:
	for pid_any in _race_session_active_participants:
		var pid: int = int(pid_any)
		if _server_is_peer_connected(pid):
			return true
	return false


func _server_has_unfinished_active_racer() -> bool:
	for pid_any in _race_session_active_participants:
		var pid: int = int(pid_any)
		if _race_session_finish_time.has(pid):
			continue
		if _race_session_dnf.has(pid):
			continue
		if _server_is_peer_connected(pid):
			return true
	return false


func _server_is_peer_connected(peer_id: int) -> bool:
	if peer_id == _local_id:
		return true
	if multiplayer == null:
		return false
	if not multiplayer.get_peers().has(peer_id):
		return false
	var transport: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport:
		var peer: ENetPacketPeer = transport.get_peer(peer_id)
		return peer and peer.get_state() == ENetPacketPeer.STATE_CONNECTED
	return true


func report_race_finish(goal_path: String, time_seconds: float, rings_value: int, score_value: int, debug_used: bool) -> void:
	if not _is_online():
		return
	if multiplayer.is_server():
		_server_report_finish(_local_id, goal_path, time_seconds, rings_value, score_value, debug_used)
	else:
		rpc_id(1, "_rpc_report_race_finish", goal_path, time_seconds, rings_value, score_value, debug_used, _race_setup_generation)


func report_race_debug_used() -> void:
	if not _is_online():
		return
	if multiplayer.is_server():
		_server_report_race_debug_used(_local_id)
	else:
		rpc_id(1, "_rpc_report_race_debug_used", _race_setup_generation)


@rpc("any_peer", "reliable")
func _rpc_report_race_debug_used(generation: int) -> void:
	if generation != _race_setup_generation:
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_report_race_debug_used(sender)


func _server_report_race_debug_used(peer_id: int) -> void:
	if not _race_session_active:
		return
	if not _race_session_participants.has(peer_id):
		return
	_race_session_debug_used[peer_id] = true


@rpc("any_peer", "reliable")
func _rpc_report_race_finish(goal_path: String, time_seconds: float, rings_value: int, score_value: int, debug_used: bool, generation: int) -> void:
	if generation != _race_setup_generation:
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_report_finish(sender, goal_path, time_seconds, rings_value, score_value, debug_used)


func _server_report_finish(peer_id: int, goal_path: String, time_seconds: float, rings_value: int, score_value: int, debug_used: bool) -> void:
	if not _race_results_payload.is_empty():
		return
	if not _race_session_active or not is_finite(time_seconds) or time_seconds < 0.0:
		return
	if not _race_session_active_participants.has(peer_id):
		return
	if _race_session_finish_time.has(peer_id) or _race_session_dnf.has(peer_id):
		return

	if goal_path.begins_with("/") or goal_path.contains("..") or goal_path.strip_edges().is_empty():
		return
	if _race_session_goal_path and _race_session_goal_path != goal_path:
		return
	if _race_session_goal_path == "" and goal_path.strip_edges() != "":
		_race_session_goal_path = goal_path

	_race_session_finish_time[peer_id] = max(time_seconds, 0.0)
	_race_session_finish_rings[peer_id] = max(rings_value, 0)
	_race_session_finish_score[peer_id] = score_value
	_race_session_debug_used[peer_id] = _is_debug_disqualified(peer_id, _race_session_debug_used) or bool(debug_used)
	_race_session_finish_order.append(peer_id)
	var place_num: int = _race_session_finish_order.size()
	if peer_id == _local_id:
		_rpc_race_finish_place(place_num)
	else:
		rpc_id(peer_id, "_rpc_race_finish_place", place_num)
	_broadcast_finish_announcement(peer_id, place_num)
	# Play a global SFX whenever someone places at the goal.
	rpc("_rpc_play_race_queue_start_sfx")

	# Start the 1-minute results timer when the first player finishes.
	if not _race_session_end_active:
		_race_session_end_active = true
		_race_session_end_remaining = _race_session_end_duration
		_race_session_end_broadcast_accum = 0.0
		_broadcast_race_end_countdown(true, _race_session_end_remaining)

	if _server_race_all_done():
		_server_finalize_race_results()


func _broadcast_finish_announcement(finished_peer_id: int, place_num: int) -> void:
	for pid: int in _race_session_active_participants.duplicate():
		if not _server_is_peer_connected(pid):
			continue
		if pid == _local_id:
			_rpc_race_finish_announce(finished_peer_id, place_num)
		else:
			rpc_id(pid, "_rpc_race_finish_announce", finished_peer_id, place_num)


func _broadcast_race_leave_announcement(left_peer_id: int) -> void:
	for pid: int in _race_session_active_participants.duplicate():
		if not _server_is_peer_connected(pid):
			continue
		if pid == _local_id:
			_rpc_race_leave_announce(left_peer_id)
		else:
			rpc_id(pid, "_rpc_race_leave_announce", left_peer_id)


@rpc("authority", "reliable", "call_local")
func _rpc_race_finish_announce(finished_peer_id: int, place_num: int) -> void:
	var name: String = "Player_%d" % finished_peer_id
	if _peer_names.has(finished_peer_id):
		name = String(_peer_names[finished_peer_id])
	var suffix: String = "%dth" % place_num
	if place_num == 1:
		suffix = "1st"
	elif place_num == 2:
		suffix = "2nd"
	elif place_num == 3:
		suffix = "3rd"
	_show_finish_banner("%s finished %s!" % [name, suffix])


@rpc("authority", "reliable", "call_local")
func _rpc_race_leave_announce(left_peer_id: int) -> void:
	var name: String = "Player_%d" % left_peer_id
	if _peer_names.has(left_peer_id):
		name = String(_peer_names[left_peer_id])
	_show_finish_banner("%s left the race." % name)


func _show_finish_banner(text_value: String) -> void:
	if HUDMusicTrackDisplay.post_notification(
		get_tree(),
		"Finish Line",
		text_value,
		null,
		3.0
	):
		return
	var banner = _get_or_create_finish_banner()
	if banner != null and is_instance_valid(banner) and banner.has_method("show_message"):
		banner.call("show_message", text_value)

func _on_race_ui_option_selected(option: StringName) -> void:
	_race_results_choice = option
	_race_results_choice_pending = false


func _get_music_controllers() -> Array:
	if get_tree() == null:
		return []
	return get_tree().get_nodes_in_group("MusicControllers")

func _request_suppress_next_music_autoplay() -> void:
	# SUMMARY: Ask the next MusicController autoplay to skip once.
	# - Implemented as a SceneTree meta ticket consumed by MusicController._ready.
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var tickets: int = 0
	if tree.has_meta(_SUPPRESS_NEXT_AUTOPLAY_META):
		var raw_value = tree.get_meta(_SUPPRESS_NEXT_AUTOPLAY_META)
		if raw_value is int:
			tickets = int(raw_value)
		elif raw_value is float:
			tickets = int(raw_value)
		elif raw_value is bool:
			if bool(raw_value):
				tickets = 1

	tickets = max(tickets, 0) + 1
	tree.set_meta(_SUPPRESS_NEXT_AUTOPLAY_META, tickets)


func _get_primary_music_controller() -> MusicController:
	var controllers := _get_music_controllers()
	var fallback: MusicController = null
	for node in controllers:
		if node is MusicController:
			var mc: MusicController = node
			if fallback == null:
				fallback = mc
			if mc.autoplay and mc.autoplay_stream != null:
				return mc
	return fallback


func _stop_all_music(fade_out_time: float) -> void:
	var controllers := _get_music_controllers()
	for node in controllers:
		if node is MusicController:
			(node as MusicController).stop_all_music(fade_out_time)


func _play_results_music() -> void:
	if results_music_stream == null:
		if is_instance_valid(_race_results_goal) and _race_results_goal.has_method("_play_results_music"):
			_race_results_goal.call("_play_results_music")
		return
	var mc = _get_primary_music_controller()
	if mc == null:
		return
	_stop_all_music(results_music_fade_out)
	mc.play_music(
		results_music_stream,
		results_music_fade_in,
		results_music_fade_out,
		results_music_restart_if_same
	)


func _restore_autoplay_music() -> void:
	var mc = _get_primary_music_controller()
	if mc == null:
		return
	var fade_out: float = results_music_fade_out
	_stop_all_music(fade_out)
	if mc.has_method("play_autoplay"):
		mc.play_autoplay(true, -1.0, fade_out)
	elif mc.autoplay_stream != null:
		mc.play_music(mc.autoplay_stream, mc.autoplay_fade_in, fade_out, true)


func _get_or_create_finish_banner() -> Node:
	if _race_finish_banner != null and is_instance_valid(_race_finish_banner):
		return _race_finish_banner
	var packed = load("res://LS5Framework/Scenes/Race/RaceFinishBanner.tscn")
	if not (packed is PackedScene):
		return null
	_race_finish_banner = (packed as PackedScene).instantiate()
	_race_finish_banner.add_to_group("RaceFinishBanner")
	var vp = get_viewport()
	if vp != null:
		vp.add_child(_race_finish_banner)
	else:
		add_child(_race_finish_banner)
	return _race_finish_banner


@rpc("authority", "reliable", "call_local")
func _rpc_play_race_queue_start_sfx() -> void:
	_play_race_sfx(sfx_race_queue_start)


func _play_race_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var p = _get_or_create_race_sfx_player()
	if p == null:
		return
	p.stream = stream
	p.play()


func _get_or_create_race_sfx_player() -> AudioStreamPlayer:
	if _race_sfx_player != null and is_instance_valid(_race_sfx_player):
		return _race_sfx_player
	var p := AudioStreamPlayer.new()
	p.bus = race_sfx_bus
	add_child(p)
	_race_sfx_player = p
	return _race_sfx_player


@rpc("authority", "reliable", "call_local")
func _rpc_race_finish_place(place_num: int) -> void:
	var p = get_player_node(_local_id)
	if p == null or not is_instance_valid(p):
		return
	var suffix: String = "%dth" % place_num
	if place_num == 1:
		suffix = "1st"
	elif place_num == 2:
		suffix = "2nd"
	elif place_num == 3:
		suffix = "3rd"
	if p.has_method("show_prompt"):
		p.call("show_prompt", "Finished!  %s place" % suffix, 6.0)
	elif p.has_method("show_chat_bubble"):
		p.call("show_chat_bubble", "Finished!  %s place" % suffix)


func _server_race_all_done() -> bool:
	if not _race_session_active:
		return false
	for id in _race_session_participants:
		var pid: int = int(id)
		if _race_session_finish_time.has(pid):
			continue
		if _race_session_dnf.has(pid):
			continue
		return false
	return true


func _server_finalize_race_results() -> void:
	if not _race_session_active or not _race_results_payload.is_empty():
		return
	if not _server_has_connected_race_participant():
		_server_clear_race_session()
		return
	_race_session_end_active = false
	_broadcast_race_end_countdown(false, 0.0)
	var order: Array = _race_session_finish_order.duplicate()
	var dnfs: Array = []
	for pid: int in _race_session_participants:
		if not _race_session_finish_time.has(pid):
			dnfs.append(pid)
	_race_results_payload = {
		"order": order, "dnfs": dnfs,
		"times": _race_session_finish_time.duplicate(),
		"rings": _race_session_finish_rings.duplicate(),
		"scores": _race_session_finish_score.duplicate(),
		"debug": _race_session_debug_used.duplicate(),
		"goal": _race_session_goal_path,
		"targets": _race_session_active_participants.duplicate(),
		"start_scene": _race_session_start_scene, "start_path": _race_session_start_path,
	}
	_race_results_ready.clear()
	_race_results_timeout = maxf(race_ready_timeout_default, 1.0)
	for pid: int in _race_session_active_participants.duplicate():
		if not _server_is_peer_connected(pid):
			continue
		if pid == _local_id:
			_rpc_race_prepare_results(_race_results_payload, _race_setup_generation)
		else:
			rpc_id(pid, "_rpc_race_prepare_results", _race_results_payload, _race_setup_generation)


func _is_peer_racing(peer_id: int) -> bool:
	if peer_id == _local_id:
		var player: Node = get_local_player()
		return _race_queue_joiners.has(peer_id) or _race_join_request_generation == _race_setup_generation or _race_results_local_pending or (is_instance_valid(player) and (bool(player.get("race_session_joined")) or bool(player.get("race_active")) or bool(player.get("race_in_countdown"))))
	return _race_queue_joiners.has(peer_id) or _race_session_active_participants.has(peer_id)


@rpc("authority", "reliable", "call_local")
func _rpc_race_session_state(active: bool, participants: Array, start_scene: String, start_path: String, generation: int) -> void:
	if generation < _race_setup_generation:
		return
	_race_setup_generation = generation
	_race_session_active = active
	_race_session_participants = participants.duplicate()
	if not multiplayer.is_server():
		_race_session_active_participants = participants.duplicate()
	if active:
		_race_session_start_scene = start_scene
		_race_session_start_path = start_path
	emit_signal("race_queue_updated")


@rpc("authority", "reliable", "call_remote")
func _rpc_race_prepare_results(payload: Dictionary, generation: int) -> void:
	var player: Node = get_local_player()
	if generation != _race_setup_generation or _race_results_local_pending or not player or not bool(player.get("race_session_joined")):
		return
	_race_results_token += 1
	var token: int = _race_results_token
	_race_results_local_pending = true
	_race_session_start_scene = String(payload.get("start_scene", ""))
	_race_session_start_path = String(payload.get("start_path", ""))
	player.call("set_ui_input_blocked", true)
	player.call("stop_all_momentum_and_special_movement")
	player.set("race_active", false)
	player.set("race_finished", true)
	var hud: Node = player.get("hud")
	if hud and hud.has_method("set_timer_running"):
		hud.call("set_timer_running", false)
	var goal: Node = null
	if not String(payload.get("goal", "")).is_empty() and get_tree().current_scene:
		goal = get_tree().current_scene.get_node_or_null(NodePath(String(payload["goal"])))
	if goal and not goal.has_method("apply_online_lineup_pose"):
		goal = null
	_race_results_goal = goal
	_race_results_fader = RaceTransitionHelper._get_or_create_fader(self)
	var fade_out_time: float = float(goal.get("fade_out_duration")) if goal else 1.0
	var fade_hold_time: float = float(goal.get("fade_hold_duration")) if goal else 0.075
	var color: Color = goal.get("fade_color") if goal else Color.WHITE
	if goal and goal.has_method("_register_finish_fade_camera_constraint"):
		goal.call("_register_finish_fade_camera_constraint", player)
		goal.call("_notify_camera_teleport", player, fade_out_time + fade_hold_time)
	_stop_all_music(results_music_fade_out)
	if _race_results_fader:
		_race_results_fader.call("set_fade_color", color)
		await _race_results_fader.call("fade_out", fade_out_time)
	if token != _race_results_token or not is_instance_valid(player):
		return
	if fade_hold_time > 0.0:
		await get_tree().create_timer(fade_hold_time).timeout
	if token != _race_results_token or not is_instance_valid(player):
		return
	if is_instance_valid(goal) and goal.has_method("apply_online_lineup_pose"):
		goal.call("apply_online_lineup_pose", player, payload["order"], payload["dnfs"], payload["targets"], _local_id)
	else:
		player.call("_network_publish_teleport_state")
	if multiplayer.is_server():
		_server_mark_results_ready(_local_id, generation)
	else:
		rpc_id(1, "_rpc_race_results_ready", generation)


@rpc("any_peer", "reliable")
func _rpc_race_results_ready(generation: int) -> void:
	if multiplayer.is_server():
		_server_mark_results_ready(multiplayer.get_remote_sender_id(), generation)


func _server_mark_results_ready(peer_id: int, generation: int) -> void:
	if generation != _race_setup_generation or _race_results_payload.is_empty() or not _race_session_active_participants.has(peer_id):
		return
	_race_results_ready[peer_id] = true
	_server_try_release_race_results()


func _server_try_release_race_results() -> void:
	for pid: int in _race_session_active_participants:
		if _server_is_peer_connected(pid) and not _race_results_ready.has(pid):
			return
	_server_release_race_results()


func _server_release_race_results() -> void:
	if _race_results_payload.is_empty() or _race_results_releasing:
		return
	_race_results_releasing = true
	var payload: Dictionary = _race_results_payload.duplicate(true)
	var targets: Array[int] = []
	for pid: int in _race_session_active_participants:
		if _server_is_peer_connected(pid):
			targets.append(pid)
	payload["targets"] = targets
	for pid: int in _race_session_active_participants.duplicate():
		if not _server_is_peer_connected(pid):
			continue
		if not _race_results_ready.has(pid):
			if pid == _local_id:
				_rpc_race_results_aborted(_race_setup_generation)
			else:
				rpc_id(pid, "_rpc_race_results_aborted", _race_setup_generation)
			continue
		if pid == _local_id:
			_rpc_race_present_results(payload, _race_setup_generation)
		else:
			rpc_id(pid, "_rpc_race_present_results", payload, _race_setup_generation)
	_server_clear_race_session()


@rpc("authority", "reliable", "call_remote")
func _rpc_race_results_aborted(generation: int) -> void:
	if generation != _race_setup_generation:
		return
	var player: Node = get_local_player()
	if player and player.has_method("leave_race"):
		player.call("leave_race", false)


@rpc("authority", "reliable", "call_remote")
func _rpc_race_present_results(payload: Dictionary, generation: int) -> void:
	if generation != _race_setup_generation or not _race_results_local_pending:
		return
	var token: int = _race_results_token
	var goal: Node = _race_results_goal
	if is_instance_valid(goal):
		goal.call("_unregister_finish_fade_camera_constraint")
		goal.call("apply_online_lineup_pose", get_local_player(), payload["order"], payload["dnfs"], payload["targets"], _local_id)
		var using_animated_camera: bool = bool(goal.call("_begin_victory_presentation", get_local_player()))
		goal.call("_register_goal_camera_constraint", get_local_player())
		if using_animated_camera:
			await get_tree().process_frame
			if token != _race_results_token or not _is_online():
				return
	if is_instance_valid(_race_results_fader):
		var fade_in_time: float = float(goal.get("fade_in_duration")) if is_instance_valid(goal) else 0.525
		if is_instance_valid(goal):
			goal.call("_notify_camera_teleport", get_local_player(), fade_in_time + 0.25)
		await _race_results_fader.call("fade_in", fade_in_time)
	if token != _race_results_token or not _is_online():
		return
	_race_session_start_scene = String(payload["start_scene"])
	_race_session_start_path = String(payload["start_path"])
	_rpc_show_race_results(payload["order"], payload["dnfs"], payload["times"], payload["rings"], payload["scores"], payload["goal"], payload["debug"])


func cancel_local_race_presentation() -> void:
	_race_results_token += 1
	_race_results_choice_pending = false
	_race_results_local_pending = false
	_race_local_setup_token += 1
	if is_instance_valid(_race_results_goal):
		_race_results_goal.call("_unregister_finish_fade_camera_constraint")
		_race_results_goal.call("_unregister_goal_camera_constraint", get_local_player())
	_race_results_goal = null
	if is_instance_valid(_race_results_fader):
		_race_results_fader.call("reset_now")
	_race_results_fader = null
	if is_instance_valid(_race_results_ui):
		_race_results_ui.queue_free()
	_race_results_ui = null
	_queue_hud_visibility_restore()
	if is_instance_valid(_chat_ui):
		_chat_ui.visible = true
	_update_race_dnf_banner(false, 0.0)


func _server_clear_race_session() -> void:
	_race_results_releasing = false
	_race_results_payload.clear()
	_race_results_ready.clear()
	_race_results_timeout = 0.0
	var race_start: Node = null
	if _race_session_start_scene.strip_edges() != "" and _race_session_start_path.strip_edges() != "":
		race_start = _resolve_race_start_node(_race_session_start_scene, _race_session_start_path)
	_deactivate_race_objects_for_start(race_start)
	_broadcast_race_end_countdown(false, 0.0)
	_race_session_active = false
	_race_session_participants = []
	_race_session_active_participants = []
	_race_session_goal_path = ""
	_race_session_start_scene = ""
	_race_session_start_path = ""
	_race_session_finish_order = []
	_race_session_finish_time.clear()
	_race_session_finish_rings.clear()
	_race_session_finish_score.clear()
	_race_session_debug_used.clear()
	_race_session_dnf.clear()
	_race_session_end_active = false
	_race_session_end_remaining = 0.0
	_race_session_end_broadcast_accum = 0.0
	if _is_online():
		rpc("_rpc_race_session_state", false, [], "", "", _race_setup_generation)


func _broadcast_race_end_countdown(active: bool, remaining: float) -> void:
	for pid: int in _race_session_active_participants.duplicate():
		if not _server_is_peer_connected(pid):
			continue
		if pid == _local_id:
			_rpc_race_end_countdown(active, remaining)
		else:
			rpc_id(pid, "_rpc_race_end_countdown", active, remaining)


@rpc("authority", "reliable", "call_local")
func _rpc_race_end_countdown(active: bool, remaining: float) -> void:
	var player: Node = get_local_player()
	if active and (not player or not bool(player.get("race_session_joined"))):
		return
	_update_race_dnf_banner(active, remaining)


func _update_race_dnf_banner(active: bool, remaining: float) -> void:
	var banner = _get_or_create_dnf_banner()
	if banner == null or not is_instance_valid(banner):
		return
	if banner.has_method("set_remaining"):
		banner.call("set_remaining", active, remaining)


func _get_or_create_dnf_banner() -> Node:
	if _race_dnf_banner != null and is_instance_valid(_race_dnf_banner):
		return _race_dnf_banner
	var packed = load("res://LS5Framework/Scenes/Race/RaceDNFCountdownBanner.tscn")
	if not (packed is PackedScene):
		return null
	_race_dnf_banner = (packed as PackedScene).instantiate()
	_race_dnf_banner.add_to_group("RaceDNFBanner")
	var vp = get_viewport()
	if vp != null:
		vp.add_child(_race_dnf_banner)
	else:
		add_child(_race_dnf_banner)
	return _race_dnf_banner


func _play_online_race_end_voice(order: Array, dnfs: Array) -> void:
	if order.is_empty() or order.size() + dnfs.size() < 2:
		return
	var winner_id: int = int(order[0])
	var winner: Node = get_player_node(winner_id)
	if winner == null or not is_instance_valid(winner):
		return
	if winner.has_method("play_voice_event"):
		winner.call("play_voice_event", &"race_end", true)


@rpc("authority", "reliable", "call_local")
func _rpc_show_race_results(order: Array, dnfs: Array, times: Dictionary, rings: Dictionary, scores: Dictionary, _goal_path: String, debug_flags: Dictionary) -> void:
	var results_token: int = _race_results_token
	var results_start_scene: String = _race_session_start_scene
	var results_start_path: String = _race_session_start_path
	var race_start_for_objects: Node = null
	if _race_session_start_scene.strip_edges() != "" and _race_session_start_path.strip_edges() != "":
		race_start_for_objects = _resolve_race_start_node(_race_session_start_scene, _race_session_start_path)
	var local_rings: int = 0
	var local_score: int = 0
	var local_time: float = 0.0
	if rings.has(_local_id):
		local_rings = int(rings[_local_id])
	if scores.has(_local_id):
		local_score = int(scores[_local_id])
	if times.has(_local_id):
		local_time = float(times[_local_id])
	var debug_used_local: bool = false
	if debug_flags != null and debug_flags.has(_local_id):
		var dv = debug_flags[_local_id]
		if dv is bool:
			debug_used_local = bool(dv)

	var p = get_player_node(_local_id)
	_play_online_race_end_voice(order, dnfs)
	var hud_prev_visible: bool = true
	var chat_prev_visible: bool = true
	var hud_node = null
	var chat_node = null
	if get_parent() != null:
		hud_node = get_parent().get_node_or_null(hud_path)
		chat_node = get_parent().get_node_or_null("ChatUI")
	if hud_node == null and get_tree() != null and get_tree().current_scene != null:
		hud_node = get_tree().current_scene.get_node_or_null("HUD")
		chat_node = get_tree().current_scene.get_node_or_null("ChatUI")
	if hud_node != null and is_instance_valid(hud_node):
		var v = hud_node.visible
		if v is bool:
			hud_prev_visible = bool(v)
	if chat_node != null and is_instance_valid(chat_node):
		var v2 = chat_node.visible
		if v2 is bool:
			chat_prev_visible = bool(v2)

	var ui_packed = load("res://LS5Framework/Scenes/Race/RaceUI.tscn")
	if not (ui_packed is PackedScene):
		_race_results_local_pending = false
		# Failsafe: never leave the player stuck if UI fails to load.
		_unlock_local_camera_constraints()
		if p != null and is_instance_valid(p):
			if p.has_method("set_ui_input_blocked"):
				p.call("set_ui_input_blocked", false)
			if p.has_method("set"):
				p.set("race_session_joined", false)
				p.set("race_in_countdown", false)
				p.set("race_active", false)
				p.set("race_finished", false)
				p.set("lock_cursor_to_game", true)
			if p.has_method("_update_mouse_lock"):
				p.call("_update_mouse_lock")
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_deactivate_race_objects_for_start(race_start_for_objects)
		return
	var ui = (ui_packed as PackedScene).instantiate()
	if ui == null:
		_race_results_local_pending = false
		_unlock_local_camera_constraints()
		if p != null and is_instance_valid(p):
			if p.has_method("set_ui_input_blocked"):
				p.call("set_ui_input_blocked", false)
			if p.has_method("set"):
				p.set("race_session_joined", false)
				p.set("race_in_countdown", false)
				p.set("race_active", false)
				p.set("race_finished", false)
				p.set("lock_cursor_to_game", true)
			if p.has_method("_update_mouse_lock"):
				p.call("_update_mouse_lock")
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_deactivate_race_objects_for_start(race_start_for_objects)
		return
	_race_results_ui = ui
	ui.add_to_group("RaceUI")
	var vp = get_viewport()
	if vp != null:
		vp.add_child(ui)
	else:
		add_child(ui)

	# Ensure the results UI can receive clicks (hide other overlays that may intercept input).
	if hud_node != null and is_instance_valid(hud_node):
		hud_node.visible = false
	if chat_node != null and is_instance_valid(chat_node):
		chat_node.visible = false
	# Hide the DNF countdown banner once results are showing.
	_update_race_dnf_banner(false, 0.0)
	_play_results_music()

	# Always unlock the cursor while the results UI is on screen, to avoid confusion.
	if p != null and is_instance_valid(p):
		if p.has_method("set"):
			p.set("lock_cursor_to_game", false)
		if p.has_method("_update_mouse_lock"):
			p.call("_update_mouse_lock")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var bb: String = _format_places_bbcode(order, dnfs, times, debug_flags)
	var is_new_record: bool = false
	if not debug_used_local and local_time > 0.0:
		var level_key := _get_level_key_for_scores()
		is_new_record = HighScoreManager.save_time_if_better(level_key, local_time)
	if ui.has_method("show_race_results_with_places"):
		ui.call("show_race_results_with_places", local_rings, local_time, local_score, bb, is_new_record)
	elif ui.has_method("show_results"):
		ui.call("show_results", local_rings, local_time, local_score, is_new_record)

	# Auto-close results after 5 seconds, or allow skipping via Ability Slot 1 / left click.
	if ui.has_method("wait_or_skip"):
		await ui.call("wait_or_skip", 5.0)
	if results_token != _race_results_token or not is_instance_valid(ui):
		return

	# Online post-race options (return-to-start enabled; menu disabled); keep controls locked until selection.
	if ui.has_method("configure_post_race_options"):
		ui.call("configure_post_race_options", true, false)
	if ui.has_method("set_restart_label"):
		ui.call("set_restart_label", "Return to start")
	if ui.has_method("show_options"):
		ui.call("show_options")

	var chosen: StringName = &"stay"
	var got_choice: bool = false
	_race_results_choice = &""
	_race_results_choice_pending = true
	if ui.has_signal("option_selected"):
		ui.option_selected.connect(Callable(self, "_on_race_ui_option_selected"))

	# Failsafe: don't hang forever waiting on a click; allow skip input to default to "stay".
	var max_wait: float = 30.0
	var remaining: float = max_wait
	while remaining > 0.0 and _race_results_choice_pending and results_token == _race_results_token:
		if ui == null or not is_instance_valid(ui):
			break
		if ui.has_method("consume_skip"):
			var did_skip: bool = bool(ui.call("consume_skip"))
			if did_skip:
				chosen = &"stay"
				_race_results_choice_pending = false
				break
		if get_tree() == null:
			break
		var step: float = min(0.1, remaining)
		remaining -= step
		await get_tree().create_timer(step).timeout
	if results_token != _race_results_token:
		return
	if not _race_results_choice_pending and _race_results_choice != &"":
		chosen = _race_results_choice
	got_choice = not _race_results_choice_pending

	_race_results_local_pending = false
	if is_instance_valid(_race_results_goal):
		_race_results_goal.call("_unregister_goal_camera_constraint", p)
	_race_results_goal = null
	_unlock_local_camera_constraints()

	if chosen == &"return_hub":
		_restore_autoplay_music()
		if p != null and is_instance_valid(p):
			if p.has_method("set_ui_input_blocked"):
				p.call("set_ui_input_blocked", false)
			if p.has_method("set"):
				p.set("race_session_joined", false)
				p.set("race_in_countdown", false)
				p.set("race_active", false)
				p.set("race_finished", false)
				p.set("lock_cursor_to_game", true)
			if p.has_method("_update_mouse_lock"):
				p.call("_update_mouse_lock")
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if ui != null and is_instance_valid(ui) and ui.has_signal("option_selected"):
			if ui.option_selected.is_connected(Callable(self, "_on_race_ui_option_selected")):
				ui.option_selected.disconnect(Callable(self, "_on_race_ui_option_selected"))
		if ui != null and is_instance_valid(ui):
			ui.queue_free()
		if hud_node != null and is_instance_valid(hud_node):
			hud_node.visible = hud_prev_visible
		if chat_node != null and is_instance_valid(chat_node):
			chat_node.visible = chat_prev_visible
		_queue_hud_visibility_restore()
		_deactivate_race_objects_for_start(race_start_for_objects)
		_return_to_hub()
		return

	var return_to_start: bool = (chosen == &"restart_race")

	# Always restore control + cursor lock for gameplay.
	_restore_autoplay_music()
	if p != null and is_instance_valid(p):
		if p.has_method("clear_gravity_state"):
			p.call("clear_gravity_state", &"race_cleanup", true)
		if p.has_method("set_ui_input_blocked"):
			p.call("set_ui_input_blocked", false)
		if p.has_method("set"):
			p.set("race_session_joined", false)
			p.set("race_in_countdown", false)
			p.set("race_active", false)
			p.set("race_finished", false)
			p.set("lock_cursor_to_game", true)
		if p.has_method("_update_mouse_lock"):
			p.call("_update_mouse_lock")
		if p.has_method("clear_checkpoint_data"):
			p.call("clear_checkpoint_data")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if ui != null and is_instance_valid(ui) and ui.has_signal("option_selected"):
		if ui.option_selected.is_connected(Callable(self, "_on_race_ui_option_selected")):
			ui.option_selected.disconnect(Callable(self, "_on_race_ui_option_selected"))
	if ui != null and is_instance_valid(ui):
		ui.queue_free()
	if hud_node != null and is_instance_valid(hud_node):
		hud_node.visible = hud_prev_visible
	if chat_node != null and is_instance_valid(chat_node):
		chat_node.visible = chat_prev_visible
	_queue_hud_visibility_restore()

	if return_to_start:
		_reset_objects_for_race_restart()
		_return_to_race_start(p, results_start_scene, results_start_path)
	_deactivate_race_objects_for_start(race_start_for_objects)


func _deactivate_race_objects_for_start(race_start: Node) -> void:
	if race_start == null or not is_instance_valid(race_start):
		return
	if race_start.has_method("deactivate_race_objects"):
		race_start.call("deactivate_race_objects")


func _unlock_local_camera_constraints() -> void:
	if _camera_rig == null:
		_camera_rig = get_parent().get_node_or_null(camera_rig_path)
	if _camera_rig != null and is_instance_valid(_camera_rig):
		if _camera_rig.has_method("clear_camera_constraints"):
			_camera_rig.call("clear_camera_constraints", null, true)
		if _camera_rig.has_method("notify_teleport"):
			_camera_rig.call("notify_teleport", 0.2)


func _queue_hud_visibility_restore() -> void:
	if _hud_restore_pending:
		return
	_hud_restore_attempts = 0
	_hud_restore_pending = true
	call_deferred("_restore_hud_visibility_after_scene_change")


func _restore_hud_visibility_after_scene_change() -> void:
	_hud_restore_pending = false
	var hud_node = null
	if get_parent() != null:
		hud_node = get_parent().get_node_or_null(hud_path)
	if hud_node == null and get_tree() != null and get_tree().current_scene != null:
		hud_node = get_tree().current_scene.get_node_or_null("HUD")
	if hud_node != null and is_instance_valid(hud_node):
		hud_node.visible = true
		return
	if _hud_restore_attempts < 10:
		_hud_restore_attempts += 1
		_hud_restore_pending = true
		call_deferred("_restore_hud_visibility_after_scene_change")


func _return_to_race_start(player: Node, start_scene: String = "", start_path: String = "") -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("clear_gravity_state"):
		player.call("clear_gravity_state", &"race_cleanup", true)
	if start_scene.strip_edges() == "" or start_path.strip_edges() == "":
		return
	var rs = _resolve_race_start_node(start_scene, start_path)
	if rs == null or not is_instance_valid(rs):
		return
	if rs.has_method("_teleport_player_to_start"):
		rs.call("_teleport_player_to_start", player)
		return
	if rs.has_method("_get_start_transform_for_player"):
		var t = rs.call("_get_start_transform_for_player", player)
		if t is Transform3D:
			if player.has_method("_apply_respawn_transform"):
				player.call("_apply_respawn_transform", t, false)
			elif player is Node3D:
				(player as Node3D).global_transform = t


func _reset_objects_for_race_restart() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	_reset_objects_for_race_restart_recursive(get_tree().current_scene)


func _reset_objects_for_race_restart_recursive(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("reset_for_race_restart"):
		node.call("reset_for_race_restart")
	for child in node.get_children():
		_reset_objects_for_race_restart_recursive(child)


func _get_player_spawn_node() -> Node3D:
	var level_manager = _get_level_manager()
	if level_manager != null:
		if level_manager.has_method("resolve_node_in_current_level"):
			var level_spawn = level_manager.call("resolve_node_in_current_level", NodePath("PlayerSpawn"))
			if level_spawn is Node3D:
				return level_spawn as Node3D
		if level_manager.has_method("get_current_level"):
			var level = level_manager.call("get_current_level")
			if level != null and is_instance_valid(level):
				var level_spawn_node = level.get_node_or_null("PlayerSpawn")
				if level_spawn_node is Node3D:
					return level_spawn_node as Node3D
	var spawn = get_node_or_null(spawn_point_path)
	if spawn == null and get_parent() != null:
		spawn = get_parent().get_node_or_null(spawn_point_path)
	if spawn == null and get_parent() != null:
		spawn = get_parent().get_node_or_null("PlayerSpawn")
	if spawn is Node3D:
		return spawn as Node3D
	if get_tree() != null and get_tree().current_scene != null:
		var deep = get_tree().current_scene.find_child("PlayerSpawn", true, false)
		if deep is Node3D:
			return deep as Node3D
	return null


func _return_to_player_spawn(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("clear_gravity_state"):
		player.call("clear_gravity_state", &"race_cleanup", true)
	var spawn: Node3D = _get_player_spawn_node()
	if spawn == null:
		return
	var xform: Transform3D = spawn.global_transform
	xform = DownwarpUtil.apply_downwarp_from_node(spawn, xform, [player])
	if player.has_method("_apply_respawn_transform"):
		player.call("_apply_respawn_transform", xform, false)
	elif player is Node3D:
		(player as Node3D).global_transform = xform
	if player.has_method("set"):
		player.set("attached", true)
		player.set("_prev_attached", true)
	if player.has_method("stop_all_momentum_and_special_movement"):
		player.call("stop_all_momentum_and_special_movement")


func _return_to_hub() -> void:
	var level_manager = _get_level_manager()
	if level_manager != null:
		var hub_id: StringName = &""
		if level_manager.has_method("get"):
			var v = level_manager.get("hub_level_id")
			if v is StringName:
				hub_id = v
			elif v is String:
				hub_id = StringName(v)
		if hub_id != &"" and level_manager.has_method("load_level_by_id"):
			level_manager.call("load_level_by_id", hub_id, NodePath("PlayerSpawn"))
			return
		if level_manager.has_method("load_level_by_scene_path"):
			level_manager.call("load_level_by_scene_path", "res://LS5Framework/Scenes/Levels/NikoTest/niko_test.tscn", StringName(""), NodePath("PlayerSpawn"))
			return

	if get_tree() == null:
		return
	get_tree().set_meta("pending_level_scene", "res://LS5Framework/Scenes/Levels/NikoTest/niko_test.tscn")
	if _is_online():
		var net = get_node_or_null("/root/NetworkManager")
		if net != null and net.has_method("change_scene_keep_session"):
			net.call("change_scene_keep_session", "res://LS5Framework/Scenes/Main.tscn")
			return
	var packed = load("res://LS5Framework/Scenes/Main.tscn")
	if packed is PackedScene:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file("res://LS5Framework/Scenes/Main.tscn")


func _get_level_key_for_scores() -> String:
	if _race_session_start_scene.strip_edges() != "" and _race_session_start_path.strip_edges() != "":
		var race_start: Node = _resolve_race_start_node(_race_session_start_scene, _race_session_start_path)
		if race_start != null and is_instance_valid(race_start) and race_start.has_method("get_high_score_key"):
			return String(race_start.call("get_high_score_key"))
	var level_id: StringName = &""
	var scene_path: String = ""
	var level_manager = _get_level_manager()
	if level_manager != null:
		if level_manager.has_method("get_current_level_id"):
			var v = level_manager.call("get_current_level_id")
			if v is StringName:
				level_id = v
			elif v is String:
				level_id = StringName(v)
		if level_manager.has_method("get_current_level_scene_path"):
			scene_path = String(level_manager.call("get_current_level_scene_path"))
	if scene_path == "" and get_tree() != null and get_tree().current_scene != null:
		scene_path = String(get_tree().current_scene.scene_file_path)
	return HighScoreManager.get_level_key(level_id, scene_path)


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)


func _format_places_bbcode(order: Array, dnfs: Array, times: Dictionary, debug_flags: Dictionary) -> String:
	var gold: String = "#D4AF37"
	var silver: String = "#C0C0C0"
	var bronze: String = "#CD7F32"
	var dark: String = "#555555"
	var disqualified: Array = []
	var disqualified_lookup: Dictionary = {}

	var out: String = "\n\n[center][b]PLACES[/b][/center]\n"
	var place: int = 0
	for i in range(order.size()):
		var pid: int = int(order[i])
		if _is_debug_disqualified(pid, debug_flags):
			if not disqualified_lookup.has(pid):
				disqualified.append(pid)
				disqualified_lookup[pid] = true
			continue
		place += 1
		var pfx: String = "%dth" % place
		if place == 1:
			pfx = "1st"
		elif place == 2:
			pfx = "2nd"
		elif place == 3:
			pfx = "3rd"

		var medal: String = dark
		var fs: int = 26
		if place == 1:
			medal = gold
			fs = 48
		elif place == 2:
			medal = silver
			fs = 40
		elif place == 3:
			medal = bronze
			fs = 34

		var name: String = "Player_%d" % pid
		if _peer_names.has(pid):
			name = String(_peer_names[pid])
		var time_text: String = ""
		if times != null and times.has(pid):
			var tv = times[pid]
			if tv is float or tv is int:
				time_text = _format_time_value(float(tv))
		if time_text != "":
			name += "  " + time_text
		var name_color: Color = Color(1, 1, 1, 1)
		if _peer_colors.has(pid):
			name_color = _peer_colors[pid]
		var nc: String = name_color.to_html(false)
		out += "[center][font_size=%d][color=%s][b]%s[/b][/color]  [color=#%s]%s[/color][/font_size][/center]\n" % [fs, medal, pfx, nc, name]

	for pid_any in dnfs:
		var pid: int = int(pid_any)
		if _is_debug_disqualified(pid, debug_flags):
			if not disqualified_lookup.has(pid):
				disqualified.append(pid)
				disqualified_lookup[pid] = true
			continue
		var name: String = "Player_%d" % pid
		if _peer_names.has(pid):
			name = String(_peer_names[pid])
		var name_color: Color = Color(1, 1, 1, 1)
		if _peer_colors.has(pid):
			name_color = _peer_colors[pid]
		var nc: String = name_color.to_html(false)
		out += "[center][font_size=22][color=%s]DNF  [color=#%s]%s[/color][/color][/font_size][/center]\n" % [dark, nc, name]

	if debug_flags != null:
		for pid_any in debug_flags.keys():
			var pid: int = int(pid_any)
			if _is_debug_disqualified(pid, debug_flags) and not disqualified_lookup.has(pid):
				disqualified.append(pid)
				disqualified_lookup[pid] = true

	for pid_any in disqualified:
		var pid: int = int(pid_any)
		var name: String = "Player_%d" % pid
		if _peer_names.has(pid):
			name = String(_peer_names[pid])
		var name_color: Color = Color(1, 1, 1, 1)
		if _peer_colors.has(pid):
			name_color = _peer_colors[pid]
		var nc: String = name_color.to_html(false)
		out += "[center][font_size=22][color=#AA3333]DISQUALIFIED  [color=#%s]%s[/color][/color][/font_size][/center]\n" % [nc, name]
	return out


func _is_debug_disqualified(peer_id: int, debug_flags: Dictionary) -> bool:
	if debug_flags == null or not debug_flags.has(peer_id):
		return false
	var debug_value = debug_flags[peer_id]
	if debug_value is bool and bool(debug_value):
		return true
	return false


func _format_time_value(seconds_value: float) -> String:
	var elapsed: float = max(seconds_value, 0.0)
	var total_seconds: int = int(elapsed)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	var hundredths: int = int((elapsed - total_seconds) * 100.0) % 100
	return "%02d:%02d:%02d" % [minutes, seconds, hundredths]


@rpc("authority", "reliable", "call_local")
func _rpc_race_go(race_start_scene: String, race_start_path: String, generation: int) -> void:
	if generation != _race_setup_generation or not _race_session_participants.has(_local_id):
		return
	if race_start_scene.strip_edges() == "" or race_start_path.strip_edges() == "":
		return
	_race_session_start_scene = race_start_scene
	_race_session_start_path = race_start_path
	var rs = _resolve_race_start_node(race_start_scene, race_start_path)
	if rs != null and is_instance_valid(rs) and rs.has_method("trigger_network_go"):
		rs.call("trigger_network_go")


func _update_race_banner() -> void:
	if not _race_queue_active or (_race_setup_waiting_for_ready and _race_lineup_started):
		if _race_banner != null and is_instance_valid(_race_banner):
			_race_banner.queue_free()
		_race_banner = null
		return
	if _race_banner == null or not is_instance_valid(_race_banner):
		var packed = load("res://LS5Framework/Scenes/Race/RaceQueueBanner.tscn")
		if packed is PackedScene:
			_race_banner = packed.instantiate()
			_race_banner.add_to_group("RaceQueueBanner")
			var vp = get_viewport()
			if vp != null:
				vp.add_child(_race_banner)
			else:
				add_child(_race_banner)
	if _race_banner != null and is_instance_valid(_race_banner) and _race_banner.has_method("set_state"):
		_race_banner.call("set_state", _race_queue_active, _race_queue_remaining, _race_setup_waiting_for_ready)


func _spawn_player(peer_id: int, is_local: bool) -> void:
	if _players_root == null:
		return

	var node_name = "Player_%d" % peer_id
	if _players_root.get_node_or_null(node_name) != null:
		return

	var packed: PackedScene = _get_player_scene_for_spawn(peer_id, is_local)
	if packed == null:
		push_warning("NetworkSession: selected character scene is not prepared.")
		return

	var inst = packed.instantiate()
	inst.name = node_name

	var spawn: Node3D = _get_player_spawn_node()
	var has_spawn_transform: bool = spawn != null
	var spawn_xform: Transform3D = Transform3D.IDENTITY
	if has_spawn_transform:
		spawn_xform = DownwarpUtil.apply_downwarp_from_node(spawn, spawn.global_transform)
		inst.global_transform = spawn_xform

	if _is_online():
		inst.set_multiplayer_authority(peer_id)

	# IMPORTANT: configure exported references BEFORE adding to the tree,
	# so the player `_ready()` sees valid camera/hud refs.
	if is_local:
		if not inst.is_in_group("Player"):
			inst.add_to_group("Player")
		if not inst.is_in_group("player"):
			inst.add_to_group("player")

		var hud = get_parent().get_node_or_null(hud_path)
		if hud != null:
			inst.set("hud", hud)

		if _camera_rig != null:
			inst.set("camera_rig", _camera_rig)
		elif inst.get("camera_rig") == null:
			push_warning("NetworkSession: Local camera_rig not found and not set on player.")

		if _camera != null:
			inst.set("camera", _camera)
		elif inst.get("camera") == null:
			push_warning("NetworkSession: Local camera not found and not set on player.")
	else:
		if inst.is_in_group("Player"):
			inst.remove_from_group("Player")
		if inst.is_in_group("player"):
			inst.remove_from_group("player")
		inst.add_to_group("RemotePlayer")
		inst.set("camera", null)
		inst.set("camera_rig", null)
		inst.set("hud", null)
		inst.set("lock_cursor_to_game", false)

	_players_root.add_child(inst)

	if _is_online() and inst.has_method("_network_set_visibility_filter"):
		var visibility_filter: Callable = Callable(
			self,
			"_should_replicate_player_to_peer"
		).bind(peer_id)
		inst.call("_network_set_visibility_filter", visibility_filter)
	if inst.has_method("_network_configure_for_role"):
		inst.call("_network_configure_for_role")
	if has_spawn_transform:
		inst.global_transform = spawn_xform
		if inst.has_method("_network_initialize_spawn_state"):
			inst.call("_network_initialize_spawn_state", spawn_xform)
	if not is_local:
		call_deferred("_request_initial_player_state", peer_id)

	if _peer_names.has(peer_id) and inst.has_method("set_display_name"):
		inst.call("set_display_name", String(_peer_names[peer_id]))
	if _peer_colors.has(peer_id) and inst.has_method("set_display_color"):
		inst.call("set_display_color", _peer_colors[peer_id])
	if _peer_primary_colors.has(peer_id) and _peer_secondary_colors.has(peer_id) and inst.has_method("set_character_colors"):
		var use_character_colors: bool = bool(_peer_character_colors_enabled.get(peer_id, true))
		if use_character_colors:
			var tcol = Color(0.2, 0.8, 1.0, 1.0)
			if _peer_trail_colors.has(peer_id):
				tcol = _peer_trail_colors[peer_id]
			inst.call("set_character_colors", _peer_primary_colors[peer_id], _peer_secondary_colors[peer_id], tcol)
		elif inst.has_method("clear_character_colors"):
			inst.call("clear_character_colors")
	_apply_peer_level_to_player(peer_id)
	_refresh_player_level_visibility()
	if is_local and not _local_level_ready and inst.has_method("set_level_load_suspended"):
		inst.call("set_level_load_suspended", true)


func _request_initial_player_state(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == _local_id or get_tree() == null:
		return
	await get_tree().process_frame
	var player: Node = get_player_node(peer_id)
	if player == null or not is_instance_valid(player):
		return
	var initial_sequence: int = 0
	if player.has_method("_network_get_state_sequence"):
		initial_sequence = int(player.call("_network_get_state_sequence"))
	for _attempt: int in range(3):
		if player.has_method("_network_request_authoritative_teleport"):
			player.call("_network_request_authoritative_teleport")
		for _frame_index: int in range(10):
			await get_tree().process_frame
			if player == null or not is_instance_valid(player):
				return
			if player.has_method("_network_get_state_sequence"):
				var current_sequence: int = int(player.call("_network_get_state_sequence"))
				if current_sequence > 0 and current_sequence != initial_sequence:
					return


func _get_player_scene_for_spawn(peer_id: int, is_local: bool) -> PackedScene:
	var character_id: String = String(_peer_character_ids.get(peer_id, ""))
	if character_id == "" and is_local:
		character_id = _get_selected_character_id()
	if character_id != "":
		var selected: PackedScene = _load_character_scene(character_id)
		if selected != null:
			return selected
	return null


func _load_selected_character_scene() -> PackedScene:
	return _load_character_scene(_get_selected_character_id())


func get_required_character_scene_paths() -> Array[String]:
	var scene_paths: Array[String] = []
	var character_ids: Array[String] = []
	var selected_id: String = _get_selected_character_id()
	if selected_id != "":
		character_ids.append(selected_id)
	for id_value: Variant in _peer_character_ids.values():
		var character_id: String = String(id_value).strip_edges()
		if character_id != "" and not character_ids.has(character_id):
			character_ids.append(character_id)
	for character_id: String in character_ids:
		var entry: Dictionary = _get_character_entry(character_id)
		var scene_path: String = String(entry.get("scene", "")).strip_edges()
		if scene_path != "" and not scene_paths.has(scene_path):
			scene_paths.append(scene_path)
	return scene_paths


func _get_selected_character_id() -> String:
	var settings = get_node_or_null("/root/SettingsManager")
	var selected_id: String = DEFAULT_CHARACTER_ID
	if settings != null:
		var raw_id = settings.get("chosen_character_id")
		if raw_id is String:
			selected_id = String(raw_id)
	var entry: Dictionary = _get_character_entry(selected_id)
	if entry.is_empty():
		entry = _get_default_character_entry()
	if entry.is_empty():
		return ""
	return String(entry.get("id", "")).strip_edges()


func _get_character_entry(character_id: String) -> Dictionary:
	_ensure_character_catalog()
	var cache_key: String = character_id.strip_edges().to_lower()
	if cache_key == "" or not _character_entries_by_id.has(cache_key):
		return {}
	return _character_entries_by_id[cache_key]


func _get_default_character_entry() -> Dictionary:
	_ensure_character_catalog()
	return _default_character_entry


func _ensure_character_catalog() -> void:
	if _character_catalog_loaded:
		return
	_character_catalog_loaded = true
	var entries: Array = CharacterCatalog.load_character_entries(character_data_dir)
	for raw_entry: Variant in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var character_id: String = String(entry.get("id", "")).strip_edges()
		if character_id == "":
			continue
		_character_entries_by_id[character_id.to_lower()] = entry
	_default_character_entry = _get_character_entry(DEFAULT_CHARACTER_ID)
	if _default_character_entry.is_empty():
		_default_character_entry = CharacterCatalog.get_default_entry(character_data_dir)


func _load_character_scene(character_id: String) -> PackedScene:
	var normalized_id: String = character_id.strip_edges()
	if normalized_id == "":
		return null
	var cache_key: String = normalized_id.to_lower()
	if _character_scene_cache.has(cache_key):
		var cached: Variant = _character_scene_cache[cache_key]
		if cached is PackedScene:
			return cached
	var entry: Dictionary = _get_character_entry(normalized_id)
	if entry.is_empty():
		return null
	var scene_path: String = String(entry.get("scene", "")).strip_edges()
	if scene_path == "":
		return null
	var loaded_scene: Variant = LevelPreparationManager.get_prepared_resource(
		scene_path,
		LevelPreparationManager.SCOPE_CHARACTER,
		&"NetworkCharacterSpawn"
	)
	if not (loaded_scene is PackedScene):
		loaded_scene = ResourceLoader.load(scene_path)
	if not (loaded_scene is PackedScene):
		return null
	var packed: PackedScene = loaded_scene
	_character_scene_cache[cache_key] = packed
	return packed


func _assign_camera_to_local_player(local_id: int) -> void:
	if _camera_rig == null or _players_root == null:
		return
	var local_player = _players_root.get_node_or_null("Player_%d" % local_id)
	if local_player == null:
		return
	_camera_rig.set("target", local_player)


func _on_peer_connected(peer_id: int) -> void:
	var local_id = multiplayer.get_unique_id()
	_spawn_player(peer_id, peer_id == local_id)
	if multiplayer.is_server():
		# Ensure the peer appears in rosters immediately, even if their registration arrives later.
		if not _peer_names.has(peer_id):
			_peer_names[peer_id] = "Player_%d" % peer_id
			_peer_colors[peer_id] = Color(1, 1, 1, 1)
			_peer_primary_colors[peer_id] = Color(1, 1, 1, 1)
			_peer_secondary_colors[peer_id] = Color(1, 1, 1, 1)
			_peer_trail_colors[peer_id] = Color(0.2, 0.8, 1.0, 1.0)
			_peer_character_colors_enabled[peer_id] = false
			_apply_peer_info_to_player(peer_id)
			rpc("_rpc_set_peer_info", peer_id, String(_peer_names[peer_id]), _peer_colors[peer_id], _peer_primary_colors[peer_id], _peer_secondary_colors[peer_id], _peer_trail_colors[peer_id], false)
		_send_all_peer_info_to_peer(peer_id)
		_send_all_peer_levels_to_peer(peer_id)
		_send_all_peer_characters_to_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var peer_name: String = _get_peer_display_name(peer_id)
	var version_mismatch: bool = bool(_peer_build_mismatch.get(peer_id, false))
	if multiplayer.is_server():
		_server_leave_race(peer_id, false)
	if _players_root != null:
		var node_name = "Player_%d" % peer_id
		var player = _players_root.get_node_or_null(node_name)
		if player != null and is_instance_valid(player):
			player.queue_free()
	_peer_names.erase(peer_id)
	_peer_colors.erase(peer_id)
	_peer_primary_colors.erase(peer_id)
	_peer_secondary_colors.erase(peer_id)
	_peer_trail_colors.erase(peer_id)
	_peer_character_colors_enabled.erase(peer_id)
	_peer_character_ids.erase(peer_id)
	_character_replacement_tokens.erase(peer_id)
	_peer_levels.erase(peer_id)
	_peer_build_mismatch.erase(peer_id)
	_refresh_network_visibility()
	if multiplayer.is_server():
		_broadcast_server_notice(_format_join_leave_message(peer_name, false, version_mismatch), &"leave")


func _on_network_session_ended() -> void:
	_race_join_request_generation = -1
	cancel_local_race_presentation()
	_race_queue_active = false
	_race_setup_waiting_for_ready = false
	_race_queue_joiners.clear()
	_race_queue_ready.clear()
	_race_queue_loaded.clear()
	_race_lineup_ready.clear()
	_race_session_active = false
	_race_session_participants.clear()
	_race_session_active_participants.clear()
	_race_results_payload.clear()
	_race_results_ready.clear()
	_race_results_releasing = false
	_character_replacement_tokens.clear()
	for roster: Dictionary in [_peer_names, _peer_colors, _peer_primary_colors, _peer_secondary_colors, _peer_trail_colors, _peer_character_colors_enabled, _peer_character_ids, _peer_levels, _peer_build_mismatch]:
		for peer_id: int in roster.keys():
			if peer_id != _local_id:
				roster.erase(peer_id)
	_update_race_banner()
	race_queue_updated.emit()
	if _players_root == null:
		return
	for player: Node in _players_root.get_children():
		var peer_id: int = _parse_peer_id_from_node(player.name)
		if peer_id >= 0 and peer_id != _local_id:
			player.queue_free()
	var local_player: Node = get_local_player()
	if local_player != null:
		if local_player.has_method("leave_race"):
			local_player.call("leave_race", false)
		if local_player.has_method("_network_configure_for_role"):
			local_player.call("_network_configure_for_role")


func _register_local_name(local_id: int) -> void:
	var name = "Player_%d" % local_id
	var net = get_node_or_null("/root/NetworkManager")
	var color = Color(1, 1, 1, 1)
	var primary = Color(1, 1, 1, 1)
	var secondary = Color(1, 1, 1, 1)
	var trail = Color(0.2, 0.8, 1.0, 1.0)
	var settings = get_node_or_null("/root/SettingsManager")
	var settings_name: String = ""
	var settings_color = null
	var settings_primary = null
	var settings_secondary = null
	var settings_trail = null
	var use_custom: bool = true
	if settings != null:
		settings_name = String(settings.get("online_player_name")).strip_edges()
		settings_color = settings.get("online_name_color")
		settings_primary = settings.get("online_primary_color")
		settings_secondary = settings.get("online_secondary_color")
		settings_trail = settings.get("online_trail_color")
		if "use_character_colors" in settings:
			use_custom = bool(settings.get("use_character_colors"))
		elif "use_character_colors_offline" in settings:
			use_custom = bool(settings.get("use_character_colors_offline"))

	var net_name: String = ""
	var net_color = null
	var net_primary = null
	var net_secondary = null
	var net_trail = null
	if net != null:
		net_name = String(net.get("player_name")).strip_edges()
		net_color = net.get("player_color")
		net_primary = net.get("player_primary_color")
		net_secondary = net.get("player_secondary_color")
		net_trail = net.get("player_trail_color")

	# Prefer explicit/saved settings over the NetworkManager default "Player".
	var chosen_name: String = net_name
	if chosen_name == "" or chosen_name == "Player":
		if settings_name != "" and settings_name != "Player":
			chosen_name = settings_name
	if chosen_name != "":
		name = chosen_name

	var chosen_color = net_color
	if chosen_color == null:
		chosen_color = settings_color
	if chosen_color is Color:
		color = chosen_color

	var chosen_primary = net_primary
	if chosen_primary == null:
		chosen_primary = settings_primary
	if chosen_primary is Color:
		primary = chosen_primary

	var chosen_secondary = net_secondary
	if chosen_secondary == null:
		chosen_secondary = settings_secondary
	if chosen_secondary is Color:
		secondary = chosen_secondary

	var chosen_trail = net_trail
	if chosen_trail == null:
		chosen_trail = settings_trail
	if chosen_trail is Color:
		trail = chosen_trail

	if multiplayer.is_server():
		_peer_names[local_id] = name
		_peer_colors[local_id] = color
		_peer_primary_colors[local_id] = primary
		_peer_secondary_colors[local_id] = secondary
		_peer_trail_colors[local_id] = trail
		_peer_character_colors_enabled[local_id] = use_custom
		_peer_build_mismatch[local_id] = false
		_apply_peer_info_to_player(local_id)
		rpc("_rpc_set_peer_info", local_id, name, color, primary, secondary, trail, use_custom)
	else:
		# Populate local info immediately so the roster isn't empty while we wait on the server.
		_peer_names[local_id] = name
		_peer_colors[local_id] = color
		_peer_primary_colors[local_id] = primary
		_peer_secondary_colors[local_id] = secondary
		_peer_trail_colors[local_id] = trail
		_peer_character_colors_enabled[local_id] = use_custom
		_apply_peer_info_to_player(local_id)
		rpc_id(1, "_rpc_register_peer_info", name, color, primary, secondary, trail, _get_network_build_id(), use_custom)


func _register_local_character(local_id: int) -> void:
	var character_id: String = _get_selected_character_id()
	if character_id == "":
		return
	_peer_character_ids[local_id] = character_id
	if multiplayer.is_server():
		_server_set_peer_character(local_id, character_id)
	else:
		rpc_id(1, "_rpc_request_set_character", character_id)

func _send_all_peer_info_to_peer(peer_id: int) -> void:
	for id in _peer_names.keys():
		var pid = int(id)
		var nm = String(_peer_names[id])
		var col = Color(1, 1, 1, 1)
		if _peer_colors.has(pid):
			col = _peer_colors[pid]
		var pri = Color(1, 1, 1, 1)
		var sec = Color(1, 1, 1, 1)
		if _peer_primary_colors.has(pid):
			pri = _peer_primary_colors[pid]
		if _peer_secondary_colors.has(pid):
			sec = _peer_secondary_colors[pid]
		var trl = Color(0.2, 0.8, 1.0, 1.0)
		if _peer_trail_colors.has(pid):
			trl = _peer_trail_colors[pid]
		var colors_enabled: bool = bool(_peer_character_colors_enabled.get(pid, true))
		rpc_id(peer_id, "_rpc_set_peer_info", pid, nm, col, pri, sec, trl, colors_enabled)


func _send_all_peer_levels_to_peer(peer_id: int) -> void:
	for id in _peer_levels.keys():
		var pid = int(id)
		var level_id: StringName = _peer_levels[id]
		rpc_id(peer_id, "_rpc_set_peer_level", pid, String(level_id))


func _send_all_peer_characters_to_peer(peer_id: int) -> void:
	for id: Variant in _peer_character_ids.keys():
		var pid: int = int(id)
		var character_id: String = String(_peer_character_ids[id])
		if character_id != "":
			rpc_id(peer_id, "_rpc_set_peer_character", pid, character_id)


func _server_set_peer_character(peer_id: int, character_id: String) -> void:
	if _is_peer_racing(peer_id):
		_resync_peer_character(peer_id)
		return
	var normalized_id: String = character_id.strip_edges()
	if normalized_id == "" or normalized_id.length() > CHARACTER_ID_MAX_LENGTH:
		_resync_peer_character(peer_id)
		return
	var entry: Dictionary = _get_character_entry(normalized_id)
	if entry.is_empty():
		_resync_peer_character(peer_id)
		return
	var canonical_id: String = String(entry.get("id", "")).strip_edges()
	if canonical_id == "":
		_resync_peer_character(peer_id)
		return
	var current_id: String = String(_peer_character_ids.get(peer_id, ""))
	if current_id.nocasecmp_to(canonical_id) == 0:
		return
	_peer_character_ids[peer_id] = canonical_id
	rpc("_rpc_set_peer_character", peer_id, canonical_id)


func _resync_peer_character(peer_id: int) -> void:
	var current_id: String = String(_peer_character_ids.get(peer_id, ""))
	if current_id == "":
		var fallback_entry: Dictionary = _get_default_character_entry()
		current_id = String(fallback_entry.get("id", "")).strip_edges()
		if current_id == "":
			return
		_peer_character_ids[peer_id] = current_id
		rpc("_rpc_set_peer_character", peer_id, current_id)
		return
	if peer_id == _local_id:
		return
	rpc_id(peer_id, "_rpc_set_peer_character", peer_id, current_id)


@rpc("any_peer", "reliable")
func _rpc_request_set_character(character_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_server_set_peer_character(sender, character_id)


@rpc("authority", "reliable", "call_local")
func _rpc_set_peer_character(peer_id: int, character_id: String) -> void:
	var normalized_id: String = character_id.strip_edges()
	if normalized_id == "" or normalized_id.length() > CHARACTER_ID_MAX_LENGTH:
		return
	if String(_peer_character_ids.get(peer_id, "")).nocasecmp_to(normalized_id) == 0:
		var current_player: Node = get_player_node(peer_id)
		var current_entry: Dictionary = _get_character_entry(normalized_id)
		var expected_scene_path: String = String(current_entry.get("scene", "")).strip_edges()
		if current_player != null and expected_scene_path != "" and String(current_player.scene_file_path) == expected_scene_path:
			return
	_peer_character_ids[peer_id] = normalized_id
	_queue_peer_character_replacement(peer_id)


func _server_set_peer_level(peer_id: int, level_id: String) -> void:
	var normalized: StringName = StringName(level_id)
	_peer_levels[peer_id] = normalized
	_apply_peer_level_to_player(peer_id)
	_refresh_player_level_visibility()
	_refresh_network_visibility()
	rpc("_rpc_set_peer_level", peer_id, level_id)


@rpc("any_peer", "reliable")
func _rpc_request_set_level(level_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	_server_set_peer_level(sender, level_id)


@rpc("authority", "reliable", "call_local")
func _rpc_set_peer_level(peer_id: int, level_id: String) -> void:
	var normalized: StringName = StringName(level_id)
	_peer_levels[peer_id] = normalized
	_apply_peer_level_to_player(peer_id)
	_refresh_player_level_visibility()
	_refresh_network_visibility()


@rpc("any_peer", "reliable")
func _rpc_register_peer_info(name: String, color: Color, primary_color: Color = Color(1, 1, 1, 1), secondary_color: Color = Color(1, 1, 1, 1), trail_color: Color = Color(0.2, 0.8, 1.0, 1.0), build_id: String = "", use_character_colors: bool = true) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var safe = name.strip_edges()
	if safe == "":
		safe = "Player_%d" % sender
	var was_known: bool = _peer_build_mismatch.has(sender)
	_peer_names[sender] = safe
	_peer_colors[sender] = color
	_peer_primary_colors[sender] = primary_color
	_peer_secondary_colors[sender] = secondary_color
	_peer_trail_colors[sender] = trail_color
	_peer_character_colors_enabled[sender] = use_character_colors
	var mismatch: bool = _is_peer_build_mismatch(build_id)
	_peer_build_mismatch[sender] = mismatch
	_apply_peer_info_to_player(sender)
	var ready_network_manager: Node = get_node_or_null("/root/NetworkManager")
	if ready_network_manager != null and ready_network_manager.has_method("confirm_peer_ready"):
		ready_network_manager.call("confirm_peer_ready", sender)
	rpc("_rpc_set_peer_info", sender, safe, color, primary_color, secondary_color, trail_color, use_character_colors)
	# Re-send all peer info now that the client is definitely in the gameplay scene (NetworkSession exists).
	_send_all_peer_info_to_peer(sender)
	_send_all_peer_levels_to_peer(sender)
	_send_all_peer_characters_to_peer(sender)
	if not was_known:
		_broadcast_server_notice(_format_join_leave_message(safe, true, mismatch), &"join")


@rpc("authority", "reliable", "call_local")
func _rpc_set_peer_info(peer_id: int, name: String, color: Color, primary_color: Color = Color(1, 1, 1, 1), secondary_color: Color = Color(1, 1, 1, 1), trail_color: Color = Color(0.2, 0.8, 1.0, 1.0), use_character_colors: bool = true) -> void:
	_peer_names[peer_id] = name
	_peer_colors[peer_id] = color
	_peer_primary_colors[peer_id] = primary_color
	_peer_secondary_colors[peer_id] = secondary_color
	_peer_trail_colors[peer_id] = trail_color
	_peer_character_colors_enabled[peer_id] = use_character_colors
	emit_signal("peer_name_changed", peer_id, name)
	_apply_peer_info_to_player(peer_id)

func _apply_peer_info_to_player(peer_id: int) -> void:
	if _players_root == null:
		return
	var node_name = "Player_%d" % peer_id
	var p = _players_root.get_node_or_null(node_name)
	if p == null:
		return
	if p.has_method("set_display_name") and _peer_names.has(peer_id):
		p.call("set_display_name", String(_peer_names[peer_id]))
	if p.has_method("set_display_color") and _peer_colors.has(peer_id):
		p.call("set_display_color", _peer_colors[peer_id])
	var use_character_colors: bool = bool(_peer_character_colors_enabled.get(peer_id, true))
	if use_character_colors and p.has_method("set_character_colors") and _peer_primary_colors.has(peer_id) and _peer_secondary_colors.has(peer_id):
		var tcol = Color(0.2, 0.8, 1.0, 1.0)
		if _peer_trail_colors.has(peer_id):
			tcol = _peer_trail_colors[peer_id]
		p.call("set_character_colors", _peer_primary_colors[peer_id], _peer_secondary_colors[peer_id], tcol)
	elif not use_character_colors and p.has_method("clear_character_colors"):
		p.call("clear_character_colors")


## Applies the shared character-color settings to the local player and synchronizes the live online peer state.
## Safe to call at any time.
func refresh_local_character_colors() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null:
		return

	var use_custom: bool = false
	if "use_character_colors" in sm:
		use_custom = bool(sm.get("use_character_colors"))
	elif "use_character_colors_offline" in sm:
		use_custom = bool(sm.get("use_character_colors_offline"))

	var pri: Color = Color(0.18, 0.52, 1.0, 1.0)
	var sec: Color = Color(1, 1, 1, 1)
	var trl: Color = Color(0.2, 0.8, 1.0, 1.0)
	if use_custom:
		if "character_primary_color" in sm:
			pri = Color(sm.get("character_primary_color"))
		elif "offline_primary_color" in sm:
			pri = Color(sm.get("offline_primary_color"))
		elif "online_primary_color" in sm:
			pri = Color(sm.get("online_primary_color"))
		if "character_secondary_color" in sm:
			sec = Color(sm.get("character_secondary_color"))
		elif "offline_secondary_color" in sm:
			sec = Color(sm.get("offline_secondary_color"))
		elif "online_secondary_color" in sm:
			sec = Color(sm.get("online_secondary_color"))
		if "character_trail_color" in sm:
			trl = Color(sm.get("character_trail_color"))
		elif "offline_trail_color" in sm:
			trl = Color(sm.get("offline_trail_color"))
		elif "online_trail_color" in sm:
			trl = Color(sm.get("online_trail_color"))

	var lp = get_local_player()
	if lp != null:
		if use_custom and lp.has_method("set_character_colors"):
			lp.call("set_character_colors", pri, sec, trl)
		elif not use_custom and lp.has_method("clear_character_colors"):
			lp.call("clear_character_colors")

	if not _is_online():
		return

	var net = get_node_or_null("/root/NetworkManager")
	var name: String = "Player_%d" % _local_id
	var color: Color = Color(1, 1, 1, 1)
	if net != null:
		var net_name = String(net.get("player_name")).strip_edges()
		if net_name != "":
			name = net_name
		var net_color = net.get("player_color")
		if net_color is Color:
			color = net_color
	if "online_player_name" in sm:
		var settings_name = String(sm.get("online_player_name")).strip_edges()
		if settings_name != "":
			name = settings_name
	if "online_name_color" in sm:
		var settings_color = sm.get("online_name_color")
		if settings_color is Color:
			color = settings_color

	_peer_names[_local_id] = name
	_peer_colors[_local_id] = color
	_peer_primary_colors[_local_id] = pri
	_peer_secondary_colors[_local_id] = sec
	_peer_trail_colors[_local_id] = trl
	_peer_character_colors_enabled[_local_id] = use_custom
	_apply_peer_info_to_player(_local_id)

	if multiplayer.is_server():
		rpc("_rpc_set_peer_info", _local_id, name, color, pri, sec, trl, use_custom)
	else:
		rpc_id(1, "_rpc_register_peer_info", name, color, pri, sec, trl, _get_network_build_id(), use_custom)


## Backwards-compatible helper for older menu call sites.
func refresh_local_colors_if_offline() -> void:
	refresh_local_character_colors()


func _apply_peer_level_to_player(peer_id: int) -> void:
	if _players_root == null:
		return
	var node_name = "Player_%d" % peer_id
	var p = _players_root.get_node_or_null(node_name)
	if p == null:
		return
	var level_id: StringName = &""
	if _peer_levels.has(peer_id):
		level_id = _peer_levels[peer_id]
	if p.has_method("set_meta"):
		p.set_meta("online_level_id", level_id)
	_apply_player_visibility_for_level(p, peer_id, level_id)


func _apply_player_visibility_for_level(player: Node, peer_id: int, level_id: StringName) -> void:
	if player == null or not is_instance_valid(player):
		return
	var visible_now: bool = true
	if peer_id != _local_id:
		visible_now = _local_level_id != &"" and level_id != &"" and level_id == _local_level_id
	if player.has_method("_network_set_level_presence"):
		player.call("_network_set_level_presence", visible_now)
	if player is Node3D:
		(player as Node3D).visible = visible_now
	elif player.has_method("set"):
		player.set("visible", visible_now)


func _refresh_player_level_visibility() -> void:
	if _players_root == null:
		return
	for child in _players_root.get_children():
		if child == null:
			continue
		var peer_id: int = _parse_peer_id_from_node(child.name)
		if peer_id < 0:
			continue
		if peer_id == DEBUG_DUMMY_PEER_ID:
			if child is Node3D:
				(child as Node3D).visible = true
			continue
		var level_id: StringName = &""
		if _peer_levels.has(peer_id):
			level_id = _peer_levels[peer_id]
		_apply_player_visibility_for_level(child, peer_id, level_id)


func _should_replicate_player_to_peer(receiver_peer_id: int, player_peer_id: int) -> bool:
	if receiver_peer_id == player_peer_id:
		return false
	var player_level: StringName = _peer_levels.get(player_peer_id, &"")
	var receiver_level: StringName = _peer_levels.get(receiver_peer_id, &"")
	if player_level == &"" or receiver_level == &"":
		return true
	return player_level == receiver_level


func _refresh_network_visibility() -> void:
	if _players_root == null:
		return
	for player: Node in _players_root.get_children():
		if player != null and player.has_method("_network_refresh_visibility"):
			player.call("_network_refresh_visibility")


func _parse_peer_id_from_node(node_name: String) -> int:
	if not node_name.begins_with("Player_"):
		return -1
	var suffix: String = node_name.substr(7)
	if not suffix.is_valid_int():
		return -1
	return int(suffix)


@rpc("any_peer", "reliable")
func _rpc_request_all_peer_info() -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	_send_all_peer_info_to_peer(sender)
	_send_all_peer_levels_to_peer(sender)
	_send_all_peer_characters_to_peer(sender)

@rpc("any_peer", "reliable")
func _rpc_request_race_sync() -> void:
	# Clients can miss queue/banners if they connected while still loading the gameplay scene.
	# This lets them request the current race state once their NetworkSession exists.
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()

	# Queue state (pre-race)
	var joiners: Array = []
	for id in _race_queue_joiners.keys():
		joiners.append(int(id))
	rpc_id(
		sender,
		"_rpc_race_queue_state",
		_race_queue_active,
		_race_queue_started_by,
		_race_queue_start_scene,
		_race_queue_start_path,
		_race_queue_remaining,
		joiners,
		_race_setup_waiting_for_ready,
		_race_setup_generation
	)

	rpc_id(sender, "_rpc_race_session_state", _race_session_active, _race_session_participants, _race_session_start_scene, _race_session_start_path, _race_setup_generation)
	if _race_session_active_participants.has(sender):
		rpc_id(sender, "_rpc_race_end_countdown", _race_session_end_active, _race_session_end_remaining)


# Backwards-compat wrappers (older clients)
@rpc("any_peer", "reliable")
func _rpc_register_name(name: String) -> void:
	_rpc_register_peer_info(name, Color(1, 1, 1, 1))

@rpc("authority", "reliable", "call_local")
func _rpc_set_peer_name(peer_id: int, name: String) -> void:
	var col = Color(1, 1, 1, 1)
	if _peer_colors.has(peer_id):
		col = _peer_colors[peer_id]
	var pri = Color(1, 1, 1, 1)
	var sec = Color(1, 1, 1, 1)
	if _peer_primary_colors.has(peer_id):
		pri = _peer_primary_colors[peer_id]
	if _peer_secondary_colors.has(peer_id):
		sec = _peer_secondary_colors[peer_id]
	var trl: Color = Color(0.2, 0.8, 1.0, 1.0)
	if _peer_trail_colors.has(peer_id):
		trl = _peer_trail_colors[peer_id]
	var colors_enabled: bool = bool(_peer_character_colors_enabled.get(peer_id, true))
	_rpc_set_peer_info(peer_id, name, col, pri, sec, trl, colors_enabled)


@rpc("any_peer", "reliable")
func _rpc_request_all_names() -> void:
	_rpc_request_all_peer_info()


func send_chat_message(message: String) -> void:
	if not _is_online():
		return
	var msg: String = message.strip_edges().left(CHAT_MESSAGE_MAX_LENGTH)
	if msg == "":
		return
	# If we're the server/host (peer id 1), sending to ourselves via rpc_id can be unreliable.
	# Broadcast directly instead.
	if multiplayer.is_server():
		var peer_id: int = multiplayer.get_unique_id()
		var peer_name: String = ""
		if _peer_names.has(peer_id):
			peer_name = String(_peer_names[peer_id])
		rpc("_rpc_chat_broadcast", peer_id, peer_name, msg)
	else:
		rpc_id(1, "_rpc_chat_send", msg)


@rpc("any_peer", "reliable")
func _rpc_chat_send(message: String) -> void:
	if not multiplayer.is_server():
		return
	var sanitized_message: String = message.strip_edges().left(CHAT_MESSAGE_MAX_LENGTH)
	if sanitized_message == "":
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var name: String = ""
	if _peer_names.has(sender):
		name = String(_peer_names[sender])
	rpc("_rpc_chat_broadcast", sender, name, sanitized_message)


@rpc("authority", "reliable", "call_local")
func _rpc_chat_broadcast(peer_id: int, name: String, message: String) -> void:
	if _chat_ui == null:
		_chat_ui = get_parent().get_node_or_null("ChatUI")
	if _chat_ui != null and _chat_ui.has_method("add_message"):
		_chat_ui.call("add_message", name, message)
	_apply_chat_to_player(peer_id, message)


@rpc("authority", "reliable", "call_local")
func _rpc_server_notice(message: String, sound_tag: StringName) -> void:
	if _chat_ui == null:
		_chat_ui = get_parent().get_node_or_null("ChatUI")
	if _chat_ui != null and _chat_ui.has_method("add_system_message"):
		_chat_ui.call("add_system_message", message)
	var notification_title: String = "Server Notice"
	if sound_tag == &"join":
		notification_title = "Player Joined"
	elif sound_tag == &"leave":
		notification_title = "Player Left"
	HUDMusicTrackDisplay.post_notification(
		get_tree(),
		notification_title,
		message,
		null,
		4.0
	)
	_play_online_notice_sfx(sound_tag)


func _broadcast_server_notice(message: String, sound_tag: StringName) -> void:
	if not _is_online() or not multiplayer.is_server():
		return
	_rpc_server_notice(message, sound_tag)
	for peer_id: int in multiplayer.get_peers():
		if _server_is_peer_connected(peer_id):
			rpc_id(peer_id, "_rpc_server_notice", message, sound_tag)


func _format_join_leave_message(peer_name: String, joined: bool, version_mismatch: bool) -> String:
	var safe_name: String = peer_name.strip_edges()
	if safe_name == "":
		safe_name = "Player"
	var action_text: String = "joined" if joined else "left"
	var message: String = "%s has %s the server." % [safe_name, action_text]
	if version_mismatch:
		message += " [VERSION MISMATCH]"
	return message


func _get_peer_display_name(peer_id: int) -> String:
	if _peer_names.has(peer_id):
		return String(_peer_names[peer_id])
	return "Player_%d" % peer_id


func _get_network_build_id() -> String:
	var id: String = network_build_id.strip_edges()
	if id != "":
		return id
	if ProjectSettings.has_setting("application/config/version"):
		id = String(ProjectSettings.get_setting("application/config/version")).strip_edges()
	if id == "":
		id = "dev"
	return id


func _is_peer_build_mismatch(peer_build_id: String) -> bool:
	var local_build_id: String = _get_network_build_id()
	var remote_build_id: String = peer_build_id.strip_edges()
	if remote_build_id == "":
		return true
	return remote_build_id != local_build_id


func _play_online_notice_sfx(sound_tag: StringName) -> void:
	var stream: AudioStream = null
	if sound_tag == &"join":
		stream = sfx_player_joined
	elif sound_tag == &"leave":
		stream = sfx_player_left
	if stream == null:
		return
	var player: AudioStreamPlayer = _get_or_create_online_sfx_player()
	if player == null:
		return
	player.stream = stream
	player.play()


func _get_or_create_online_sfx_player() -> AudioStreamPlayer:
	var player: AudioStreamPlayer = get_node_or_null("OnlineNoticeSFX") as AudioStreamPlayer
	if player != null:
		player.bus = online_sfx_bus
		return player
	player = AudioStreamPlayer.new()
	player.name = "OnlineNoticeSFX"
	player.bus = online_sfx_bus
	add_child(player)
	return player


func _apply_chat_to_player(peer_id: int, message: String) -> void:
	if _players_root == null:
		return
	var p = _players_root.get_node_or_null("Player_%d" % peer_id)
	if p != null and p.has_method("show_chat_bubble"):
		p.call("show_chat_bubble", message)


func request_environment_clock(channel: String, initial_hour: float, settings: Dictionary) -> void:
	if not _is_online():
		return
	if multiplayer.is_server():
		_server_send_environment_clock(_local_id, channel, initial_hour, settings)
	else:
		rpc_id(1, "_rpc_request_environment_clock", channel, initial_hour, settings)


@rpc("any_peer", "reliable")
func _rpc_request_environment_clock(channel: String, initial_hour: float, settings: Dictionary) -> void:
	if multiplayer.is_server():
		_server_send_environment_clock(multiplayer.get_remote_sender_id(), channel, initial_hour, settings)


func _server_send_environment_clock(peer_id: int, channel: String, initial_hour: float, settings: Dictionary) -> void:
	if channel.is_empty() or channel.length() > 512 or not is_finite(initial_hour):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _environment_clocks.has(channel):
		_environment_clocks[channel] = {"hour": wrapf(initial_hour, 0.0, 24.0), "stamp": now, "settings": settings.duplicate()}
	var state: Dictionary = _environment_clocks[channel]
	var config: Dictionary = state["settings"]
	var cycle: DayNightCycle = DayNightCycle.new()
	cycle.day_length_minutes = clampf(float(config.get("length", 24.0)), 0.1, 1440.0)
	cycle.uneven_day_night_durations_enabled = bool(config.get("uneven", true))
	cycle.daylight_start_hour = float(config.get("start", 6.0))
	cycle.daylight_end_hour = float(config.get("end", 18.0))
	cycle.daylight_duration_ratio = clampf(float(config.get("ratio", 0.7)), 0.05, 0.95)
	var hour: float = float(state["hour"])
	var advance_seconds: float = maxf(now - float(state["stamp"]), 0.0)
	var response_config: Dictionary = config.duplicate(true)
	if state.has("transition"):
		var transition: Dictionary = state["transition"]
		var elapsed: float = maxf(now - float(transition["stamp"]), 0.0)
		var duration: float = float(transition["duration"])
		hour = float(transition["start"]) + float(transition["delta"]) * smoothstep(0.0, 1.0, minf(elapsed / duration, 1.0))
		advance_seconds = maxf(elapsed - duration, 0.0)
		if elapsed < duration:
			response_config["transition"] = transition.duplicate()
			response_config["transition"]["elapsed"] = elapsed
		else:
			state.erase("transition")
	if bool(config.get("enabled", true)):
		hour = cycle.calculate_advanced_time(hour, advance_seconds)
	cycle.free()
	state["hour"] = hour
	state["stamp"] = now
	if peer_id == _local_id:
		_rpc_environment_clock(channel, hour, response_config)
	else:
		rpc_id(peer_id, "_rpc_environment_clock", channel, hour, response_config)


@rpc("authority", "reliable", "call_remote")
func _rpc_environment_clock(channel: String, hour: float, settings: Dictionary) -> void:
	environment_clock_received.emit(channel, hour, settings)


func notify_race_lineup_ready() -> void:
	if not _is_online() or not _race_setup_waiting_for_ready:
		return
	if multiplayer.is_server():
		_server_mark_lineup_ready(_local_id, _race_setup_generation)
	else:
		rpc_id(1, "_rpc_race_lineup_ready", _race_setup_generation)


@rpc("any_peer", "reliable")
func _rpc_race_lineup_ready(generation: int) -> void:
	if multiplayer.is_server():
		_server_mark_lineup_ready(multiplayer.get_remote_sender_id(), generation)


func _server_mark_lineup_ready(peer_id: int, generation: int) -> void:
	if generation != _race_setup_generation or not _race_lineup_started or not _race_queue_joiners.has(peer_id):
		return
	_race_lineup_ready[peer_id] = true
	_server_try_begin_countdown()


func _server_try_begin_countdown() -> void:
	if not _race_setup_waiting_for_ready or not _race_lineup_started or _race_countdown_started or _race_queue_joiners.is_empty():
		return
	for peer_id: int in _race_queue_joiners:
		if not _race_lineup_ready.has(peer_id):
			return
	_race_countdown_started = true
	_race_ready_timeout = maxf(race_ready_timeout_default, 0.0)
	for peer_id: int in _race_queue_joiners.keys():
		if peer_id != _local_id:
			rpc_id(peer_id, "_rpc_race_begin_countdown", _race_setup_generation)
	if _race_queue_joiners.has(_local_id):
		_rpc_race_begin_countdown(_race_setup_generation)


@rpc("authority", "reliable", "call_remote")
func _rpc_race_begin_countdown(generation: int) -> void:
	if generation != _race_setup_generation or not _race_setup_waiting_for_ready:
		return
	var race: Node = _resolve_race_start_node(_race_queue_start_scene, _race_queue_start_path)
	if race and race.has_method("release_network_countdown"):
		race.call("release_network_countdown")


func set_environment_clock_progression(channel: String, active: bool) -> void:
	if not multiplayer.is_server() or not _environment_clocks.has(channel):
		return
	var state: Dictionary = _environment_clocks[channel]
	_server_send_environment_clock(_local_id, channel, float(state["hour"]), state["settings"])
	state["settings"]["enabled"] = active


func transition_environment_clock(channel: String, hour: float, duration: float, shortest_path: bool) -> void:
	if multiplayer.is_server():
		_server_transition_environment_clock(channel, hour, duration, shortest_path)
	else:
		rpc_id(1, "_rpc_transition_environment_clock", channel, hour, duration, shortest_path)


@rpc("any_peer", "reliable")
func _rpc_transition_environment_clock(channel: String, hour: float, duration: float, shortest_path: bool) -> void:
	if multiplayer.is_server():
		_server_transition_environment_clock(channel, hour, duration, shortest_path)


func _server_transition_environment_clock(channel: String, hour: float, duration: float, shortest_path: bool) -> void:
	if not _environment_clocks.has(channel) or not is_finite(hour) or not is_finite(duration):
		return
	var state: Dictionary = _environment_clocks[channel]
	_server_send_environment_clock(_local_id, channel, float(state["hour"]), state["settings"])
	var start: float = float(state["hour"])
	var difference: float = fposmod(hour - start + 12.0, 24.0) - 12.0
	if not shortest_path and difference < 0.0:
		difference += 24.0
	if duration > 0.0:
		state["transition"] = {"start": start, "delta": difference, "duration": minf(duration, 600.0), "stamp": Time.get_ticks_msec() / 1000.0}
	else:
		state.erase("transition")
		state["hour"] = wrapf(hour, 0.0, 24.0)
	for peer_id: int in multiplayer.get_peers():
		_server_send_environment_clock(peer_id, channel, float(state["hour"]), state["settings"])
	_server_send_environment_clock(_local_id, channel, float(state["hour"]), state["settings"])

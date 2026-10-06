extends Node3D
class_name Terminal

@export_group("Terminal")
@export var active: bool = true
@export var one_shot: bool = false
@export var require_group_primary: StringName = &"Player"
@export var require_group_secondary: StringName = &"player"
@export var online_requires_interact: bool = true
@export var offline_requires_interact: bool = true
@export var interact_prompt_text: String = "Press INTERACT to use terminal"
@export var interact_prompt_duration: float = 9999.0

@export_group("Level")
@export var target_exit_path: NodePath = NodePath("PlayerSpawn")
@export var keep_velocity: bool = false
@export var match_exit_rotation: bool = true
@export var exit_local_offset: Vector3 = Vector3.ZERO
@export var level_data_dir: String = ""

@export_group("Menu")
const _DEFAULT_MENU_SCENE_PATH: String = "res://LS5Framework/Scenes/Terminal/TerminalMenu.tscn"
@export var terminal_menu_scene: PackedScene = null
@export var menu_title: String = "Terminal"

@export_group("Audio")
@export var idle_sound: AudioStream = preload("res://LS5Framework/Sounds/General/Movement_Wind_Loop.ogg")
@export var interact_sound: AudioStream = preload("res://LS5Framework/Sounds/Menu/menuselect.wav")

@export_group("Nodes")
@export var entrance_area_path: NodePath = NodePath("InteractArea")
@export var idle_audio_path: NodePath = NodePath("IdleAudio")
@export var interact_audio_path: NodePath = NodePath("InteractAudio")

var _entrance_area: Area3D
var _idle_audio: AudioStreamPlayer3D
var _interact_audio: AudioStreamPlayer3D

var _candidate_player: Node = null
var _interact_prompt_visible: bool = false
var _menu_instance: Node = null
var _menu_player: Node = null


func _ready() -> void:
	add_to_group("Terminal")
	_resolve_nodes()
	_resolve_default_menu_scene()
	_set_idle_audio()
	if _entrance_area == null:
		push_warning("%s: InteractArea not found." % name)
		return
	_entrance_area.monitoring = true
	_entrance_area.monitorable = true
	set_process(true)


func _exit_tree() -> void:
	_hide_interact_prompt()
	_candidate_player = null
	_close_menu(false)


func _process(_delta: float) -> void:
	_cleanup_stale_menu()
	if get_tree() != null and get_tree().paused:
		if _interact_prompt_visible:
			_hide_interact_prompt()
		return
	if not active:
		if _interact_prompt_visible:
			_hide_interact_prompt()
		if _idle_audio != null and _idle_audio.playing:
			_idle_audio.stop()
		return
	if _menu_instance != null:
		if _interact_prompt_visible:
			_hide_interact_prompt()
		return
	if _idle_audio != null and idle_sound != null and not _idle_audio.playing:
		_idle_audio.play()
	var wants_interact: bool = (_is_online() and online_requires_interact) or ((not _is_online()) and offline_requires_interact)
	if not wants_interact:
		return
	if _entrance_area == null:
		return
	var overlaps: Array = _entrance_area.get_overlapping_bodies()
	if _candidate_player != null:
		if not is_instance_valid(_candidate_player) or not overlaps.has(_candidate_player):
			_hide_interact_prompt()
			_candidate_player = null
	if _candidate_player == null:
		_candidate_player = _refresh_candidate_from_overlaps(overlaps)
	if _candidate_player == null:
		return
	if _is_player_ui_blocked(_candidate_player):
		if _interact_prompt_visible:
			_hide_interact_prompt()
		return
	if _candidate_player.has_method("is_post_ui_action_suppressed"):
		var sup = _candidate_player.call("is_post_ui_action_suppressed")
		if sup is bool and bool(sup):
			if _interact_prompt_visible:
				_hide_interact_prompt()
			return
	if not _interact_prompt_visible:
		_show_interact_prompt()
	if Input.is_action_just_pressed("interact"):
		_open_terminal_menu(_candidate_player)


func try_open_terminal_menu_from_player(player: Node) -> bool:
	_cleanup_stale_menu()
	if player == null or not is_instance_valid(player):
		return false
	if not active:
		return false
	if _menu_instance != null:
		return true
	if not _is_valid_candidate_player(player):
		return false
	if _is_player_ui_blocked(player):
		return false
	
	# Attempt to use overlaps first for accuracy.
	var overlapping: bool = false
	if _entrance_area != null:
		overlapping = _entrance_area.overlaps_body(player)
	
	# Fallback: check distance if overlap check fails (sometimes occurs during network frames).
	if not overlapping and player is Node3D:
		var dist_sq: float = global_position.distance_squared_to(player.global_position)
		if dist_sq < 25.0: # 5 unit radius fallback
			overlapping = true
			
	if not overlapping:
		return false
		
	_candidate_player = player
	_hide_interact_prompt()
	_open_terminal_menu(player)
	return true


func _resolve_nodes() -> void:
	if entrance_area_path != NodePath(""):
		_entrance_area = get_node_or_null(entrance_area_path) as Area3D
	if idle_audio_path != NodePath(""):
		_idle_audio = get_node_or_null(idle_audio_path) as AudioStreamPlayer3D
	if interact_audio_path != NodePath(""):
		_interact_audio = get_node_or_null(interact_audio_path) as AudioStreamPlayer3D


func _resolve_default_menu_scene() -> void:
	if terminal_menu_scene != null:
		return
	if _DEFAULT_MENU_SCENE_PATH.strip_edges() == "":
		return
	if not ResourceLoader.exists(_DEFAULT_MENU_SCENE_PATH):
		push_warning("Terminal: missing menu scene %s" % _DEFAULT_MENU_SCENE_PATH)
		return
	var res = load(_DEFAULT_MENU_SCENE_PATH)
	if res is PackedScene:
		terminal_menu_scene = res


func _set_idle_audio() -> void:
	if _idle_audio == null:
		return
	if idle_sound != null and _idle_audio.stream != idle_sound:
		_idle_audio.stream = idle_sound
	if _idle_audio.stream != null and not _idle_audio.playing:
		_idle_audio.play()


func _play_interact_sound() -> void:
	if _interact_audio == null:
		return
	if interact_sound != null and _interact_audio.stream != interact_sound:
		_interact_audio.stream = interact_sound
	if _interact_audio.stream != null:
		_interact_audio.play()


func _refresh_candidate_from_overlaps(overlaps: Array) -> Node:
	for body_any in overlaps:
		var body: Node = body_any
		if not _is_valid_candidate_player(body):
			continue
		if _is_player_ui_blocked(body):
			continue
		return body
	return null


func _is_valid_candidate_player(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not (body is CharacterBody3D):
		return false
	if body.has_method("has_meta") and body.call("has_meta", "is_buddy"):
		var v = body.call("get_meta", "is_buddy")
		if v is bool and bool(v):
			return false
	if require_group_primary != &"" and body.is_in_group(require_group_primary):
		pass
	elif require_group_secondary != &"" and body.is_in_group(require_group_secondary):
		pass
	else:
		var looks_like_player: bool = body.has_method("set_ui_input_blocked") and body.has_method("_apply_respawn_transform")
		if not looks_like_player:
			return false
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if body.has_method("is_multiplayer_authority") and not body.is_multiplayer_authority():
			return false
	return true


func _is_player_ui_blocked(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_ui_input_blocked"):
		var v = player.call("is_ui_input_blocked")
		if v is bool and bool(v):
			return true
	return false


func _show_interact_prompt() -> void:
	if _candidate_player == null or not is_instance_valid(_candidate_player):
		return
	if _candidate_player.has_method("show_prompt"):
		_candidate_player.call("show_prompt", interact_prompt_text, interact_prompt_duration)
	elif _candidate_player.has_method("show_chat_bubble"):
		_candidate_player.call("show_chat_bubble", interact_prompt_text)
	_interact_prompt_visible = true


func _hide_interact_prompt() -> void:
	_interact_prompt_visible = false
	if _candidate_player == null or not is_instance_valid(_candidate_player):
		return
	if _candidate_player.has_method("clear_prompt"):
		_candidate_player.call("clear_prompt")


func _open_terminal_menu(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _menu_instance != null:
		return
	_resolve_default_menu_scene()
	if terminal_menu_scene == null:
		return
	if _is_player_ui_blocked(player):
		return
	_menu_instance = terminal_menu_scene.instantiate()
	_menu_instance.add_to_group(&"LevelTransient")
	_menu_player = player
	_play_interact_sound()
	_hide_interact_prompt()
	_freeze_player_for_menu(player)
	if _menu_instance.has_method("set"):
		_menu_instance.set("title_text", menu_title)
		if level_data_dir.strip_edges() != "":
			_menu_instance.set("level_data_dir", level_data_dir)
	var parent_node := _get_menu_parent()
	if parent_node != null:
		parent_node.add_child(_menu_instance)
	else:
		add_child(_menu_instance)
	if _menu_instance.has_signal("level_selected"):
		_menu_instance.connect("level_selected", Callable(self, "_on_level_selected"))
	if _menu_instance.has_signal("character_selected"):
		_menu_instance.connect("character_selected", Callable(self, "_on_character_selected"))
	if _menu_instance.has_signal("buddy_selected"):
		_menu_instance.connect("buddy_selected", Callable(self, "_on_buddy_selected"))
	if _menu_instance.has_signal("buddy_despawn_requested"):
		_menu_instance.connect("buddy_despawn_requested", Callable(self, "_on_buddy_despawn_requested"))
	if _menu_instance.has_signal("canceled"):
		_menu_instance.connect("canceled", Callable(self, "_on_menu_canceled"))


func _on_level_selected(entry: Dictionary) -> void:
	var active_player: Node = _get_active_menu_player()
	var player_override: Node3D = active_player as Node3D
	_play_interact_sound()
	_close_menu(false)
	_request_level_change(entry, player_override)


func _on_character_selected(entry: Dictionary) -> void:
	_play_interact_sound()
	var session := _get_network_session()
	if session != null and session.has_method("apply_selected_character_to_local_player"):
		session.call("apply_selected_character_to_local_player")
	var player: Node = _get_active_menu_player()
	if player != null:
		_menu_player = player
		_candidate_player = player
		_freeze_player_for_menu(player)


func _on_buddy_selected(entry: Dictionary) -> void:
	_play_interact_sound()
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	var player: Node = _get_active_menu_player()
	if player != null and player.has_method("set_buddy_character"):
		player.call("set_buddy_character", character_id)
	_menu_player = player
	_candidate_player = player


func _on_buddy_despawn_requested() -> void:
	_play_interact_sound()
	var player: Node = _get_active_menu_player()
	if player != null and player.has_method("despawn_buddy"):
		player.call("despawn_buddy")
	_menu_player = player
	_candidate_player = player


func _on_menu_canceled() -> void:
	_play_interact_sound()
	_close_menu(true)


func _close_menu(restore_prompt: bool) -> void:
	if _menu_instance != null and is_instance_valid(_menu_instance):
		_menu_instance.queue_free()
	_menu_instance = null
	var player: Node = _get_active_menu_player()
	_menu_player = null
	_candidate_player = player
	_unfreeze_player_for_menu(player)
	if restore_prompt and player != null and not _is_player_ui_blocked(player):
		_show_interact_prompt()


func _cleanup_stale_menu() -> void:
	if _menu_instance != null and not is_instance_valid(_menu_instance):
		_menu_instance = null
		var player: Node = _get_active_menu_player()
		_menu_player = null
		_candidate_player = player
		_unfreeze_player_for_menu(player)


func _freeze_player_for_menu(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("stop_all_momentum_and_special_movement"):
		player.call("stop_all_momentum_and_special_movement")
	if player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _unfreeze_player_for_menu(player_value: Variant) -> void:
	if is_instance_valid(player_value) and player_value is Node:
		var player: Node = player_value as Node
		if player.has_method("set_ui_input_blocked"):
			player.call("set_ui_input_blocked", false)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _get_active_menu_player() -> Node:
	var local_player: Node = _get_local_player()
	if local_player != null and is_instance_valid(local_player):
		return local_player
	if is_instance_valid(_menu_player):
		return _menu_player
	return null


func _request_level_change(entry: Dictionary, player_override: Node3D = null) -> void:
	if entry.is_empty():
		return
	var player: Node3D = player_override
	if player == null:
		if _menu_player is Node3D:
			player = _menu_player as Node3D
		elif _candidate_player is Node3D:
			player = _candidate_player as Node3D
	if player == null or not is_instance_valid(player):
		return
	var level_manager = _get_level_manager()
	if level_manager == null:
		return
	if entry.has("source") and level_manager.has_method("request_level_change_from_doc"):
		level_manager.call(
			"request_level_change_from_doc",
			String(entry.get("source", "")),
			target_exit_path,
			player,
			keep_velocity,
			match_exit_rotation,
			exit_local_offset
		)
	else:
		var level_id: StringName = &""
		if entry.has("id"):
			level_id = StringName(String(entry.get("id", "")))
		var scene_path: String = ""
		if entry.has("level_scene"):
			scene_path = String(entry.get("level_scene", ""))
		if scene_path.strip_edges() == "" and entry.has("scene"):
			scene_path = String(entry.get("scene", ""))
		level_manager.call(
			"request_level_change",
			level_id,
			scene_path,
			target_exit_path,
			player,
			keep_velocity,
			match_exit_rotation,
			exit_local_offset
		)
	if one_shot:
		active = false
		if _entrance_area != null:
			_entrance_area.monitoring = false


func _get_menu_parent() -> Node:
	if get_tree() != null:
		# Priority 1: Current scene root
		if get_tree().current_scene != null:
			return get_tree().current_scene
		# Priority 2: Viewport root
		return get_tree().root
	return null


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)


func _get_network_session() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("NetworkSession")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("NetworkSession", true, false)


func _get_local_player() -> Node:
	if get_tree() == null:
		return null
	var session: Node = _get_network_session()
	if session != null and session.has_method("get_local_player"):
		var session_player: Variant = session.call("get_local_player")
		if is_instance_valid(session_player) and session_player is Node:
			return session_player as Node
	var list = get_tree().get_nodes_in_group("Player")
	if list != null:
		for player_value: Variant in list:
			if player_value is Node and _is_valid_candidate_player(player_value as Node):
				return player_value as Node
	return null


func _is_online() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer()

extends Area3D

const RaceTransitionHelperScript = preload("res://LS5Framework/Scripts/Race/RaceTransitionHelper.gd")

enum GoalCameraMode {
	STATIC_GOAL_CAMERA,
	PLAYER_VICTORY_CAMERA,
	LEGACY_PIVOT,
}

@export var active: bool = true
@export var one_shot: bool = false

@export_group("Activation")
@export var require_group_primary: StringName = &"Player"
@export var require_group_secondary: StringName = &"player"

@export_group("Goal Pose")
@export var goal_pose_path: NodePath = NodePath("GoalPose")

@export_group("Downwarp")
@export var downwarp_enabled: bool = true
@export var downwarp_distance: float = 50.0
@export var downwarp_offset: float = 0.05
@export var downwarp_collision_mask: int = 0xFFFFFFFF

@export_group("Online Lineup")
@export var lineup_front_offset: float = 1.5
@export var lineup_side_offset: float = 1.4
@export var lineup_back_step: float = 1.5

@export_group("Goal Camera")
## Selects the level camera, the character's animated victory camera, or legacy pivot behavior.
@export_enum("Static Goal Camera", "Player Victory Camera", "Legacy Pivot") var goal_camera_mode: int = GoalCameraMode.STATIC_GOAL_CAMERA
## Level-authored camera pose used by the static and fallback modes.
@export var goal_camera_point_path: NodePath = NodePath("GoalCamera")
## World-space offset applied to the level-authored goal camera.
@export var camera_position_offset: Vector3 = Vector3.ZERO
## Includes the model root offset when aiming the static goal camera.
@export var face_player_model_root: bool = true
## Aims the static goal camera at the player instead of using its authored rotation.
@export var face_player: bool = true
## Aim offset from the player's origin.
@export var face_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
## Overrides FOV during the goal presentation.
@export var fov_override_enabled: bool = false
## FOV used when the goal-camera override is enabled.
@export var fov_override: float = 70.0

@export_group("Timing")
@export var results_delay: float = 5.0
@export var options_delay: float = 5.0

@export_group("UI")
@export var race_ui_scene: PackedScene = preload("res://LS5Framework/Scenes/Race/RaceUI.tscn")

@export_group("Visuals")
@export var visual_enabled: bool = true
@export var visual_scene: PackedScene
@export var visual_root_path: NodePath = NodePath("GoalRing2")
@export var animation_player_path: NodePath = NodePath("")
@export var anim_idle: StringName = &""
@export var anim_touched: StringName = &""

@export_group("Audio")
## Looping sound played while the goal ring is active and visible.
@export var idle_sound: AudioStream = preload("res://LS5Framework/Sounds/Objects/GoalRing_Idle.wav")
## One-shot sound played when the player completes the race.
@export var win_sound: AudioStream = preload("res://LS5Framework/Sounds/Objects/GoalRing_Win.wav")
## One-shot sound played when the goal ring returns the player to the race start.
@export var back_sound: AudioStream = preload("res://LS5Framework/Sounds/Objects/GoalRing_Back.wav")
## Audio bus used by the goal ring sounds.
@export var sound_bus: StringName = &"SFX"
## Volume applied to the goal ring sounds.
@export_range(-80.0, 6.0, 0.1, "suffix:dB") var sound_volume_db: float = -6.0
## Distance where goal ring sounds begin attenuating from their configured volume.
@export_range(0.1, 1000.0, 0.1, "or_greater", "suffix:m") var sound_unit_size: float = 40.0
## Maximum audible distance for the goal ring sounds.
@export_range(0.0, 2000.0, 0.1, "or_greater", "suffix:m") var sound_max_distance: float = 300.0
## Low-pass cutoff applied as goal ring sounds attenuate over distance.
@export_range(20.0, 20500.0, 1.0, "suffix:Hz") var sound_attenuation_filter_cutoff_hz: float = 12000.0
## Strength of the distance low-pass effect.
@export_range(-80.0, 0.0, 0.1, "suffix:dB") var sound_attenuation_filter_db: float = -6.0

@export_group("Fade")
@export var fade_out_duration: float = 1.0
@export var fade_hold_duration: float = 0.075
@export var fade_in_duration: float = 0.525
@export var fade_color: Color = Color(1, 1, 1, 1)
@export var music_fade_out_time: float = 0.5

@export_group("Results Music")
@export var results_music_stream: AudioStream
@export var results_music_fade_in: float = 0.75
@export var results_music_fade_out: float = 0.5
@export var results_music_restart_if_same: bool = false

@export_group("Navigation")
@export var main_menu_scene: PackedScene = preload("res://LS5Framework/Scenes/MainMenu/MainMenu.tscn")
@export var race_start_path: NodePath = NodePath("")

var _sequence_running: bool = false
var _sequence_token: int = 0
var _sequence_player: Node = null
var _triggered: bool = false
var _touched_this_race: bool = false
var _configured_active: bool = true
var _return_to_start_running: bool = false

var _goal_constraint = null
var _goal_camera_rig: Node = null
var _finish_fade_camera_constraint: RaceCameraConstraint = null
var _finish_fade_camera_rig: Node = null
var _active_victory_presentation: Node = null
var _visual_root: Node = null
var _anim_player: AnimationPlayer = null
var _idle_audio: AudioStreamPlayer3D = null
var _win_audio: AudioStreamPlayer3D = null
var _back_audio: AudioStreamPlayer3D = null


func _ready() -> void:
	add_to_group("RaceGoal")
	_configured_active = active
	# Sensible defaults so it "just works" when dropped into a scene.
	monitoring = true
	monitorable = true
	collision_mask = 0xFFFFFFFF
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	_resolve_visuals()
	_setup_audio()
	call_deferred("_sync_goal_active_state")
	call_deferred("_play_goal_anim", anim_idle)


func _exit_tree() -> void:
	_unregister_finish_fade_camera_constraint()
	_unregister_goal_camera_constraint(null)


func _sync_goal_active_state() -> void:
	_sync_goal_label_for_race()
	if _resolve_race_start() != null:
		_apply_goal_active_state(false)
		return
	_apply_goal_active_state(_configured_active)


func set_goal_active_for_race(is_enabled: bool) -> void:
	_sync_goal_label_for_race()
	if is_enabled:
		_apply_goal_active_state(_configured_active)
		return
	if _resolve_race_start() != null:
		_apply_goal_active_state(false)
		return
	_apply_goal_active_state(_configured_active)


func _apply_goal_active_state(is_enabled: bool) -> void:
	active = is_enabled
	_sync_goal_visual_state()


func _sync_goal_visual_state() -> void:
	var should_show: bool = visual_enabled and active
	if _visual_root != null and is_instance_valid(_visual_root):
		_set_visual_visible(_visual_root, should_show)
		_set_goal_effects_active_recursive(_visual_root, should_show)
	_sync_idle_sound()


func is_for_race_start(race_start: Node) -> bool:
	if race_start == null or not is_instance_valid(race_start):
		return false
	var linked_start = _resolve_race_start()
	if linked_start == null or not is_instance_valid(linked_start):
		return false
	return linked_start == race_start


func _resolve_visuals() -> void:
	if visual_scene != null:
		var inst = visual_scene.instantiate()
		if inst != null:
			add_child(inst)
			_visual_root = inst
	elif visual_root_path != NodePath(""):
		_visual_root = get_node_or_null(visual_root_path)

	_sync_goal_visual_state()

	if animation_player_path != NodePath(""):
		_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _anim_player == null and _visual_root != null:
		var found = _visual_root.find_child("AnimationPlayer", true, false)
		if found is AnimationPlayer:
			_anim_player = found as AnimationPlayer
	if _anim_player == null:
		var found_self = find_child("AnimationPlayer", true, false)
		if found_self is AnimationPlayer:
			_anim_player = found_self as AnimationPlayer


func _set_visual_visible(node: Node, is_visible: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = is_visible
	elif node is CanvasItem:
		(node as CanvasItem).visible = is_visible


func _sync_goal_label_for_race() -> void:
	var race_start: Node = _resolve_race_start()
	var use_back_label: bool = false
	if race_start != null and is_instance_valid(race_start) and race_start.has_method("uses_back_goal_ring"):
		var back_label_value = race_start.call("uses_back_goal_ring")
		use_back_label = back_label_value is bool and bool(back_label_value)
	_apply_goal_label_mode_recursive(_visual_root, use_back_label)


func _apply_goal_label_mode_recursive(node: Node, use_back_label: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("set_back_label_enabled"):
		node.call("set_back_label_enabled", use_back_label)
	for child: Node in node.get_children():
		_apply_goal_label_mode_recursive(child, use_back_label)


func _set_goal_effects_active_recursive(node: Node, effects_active: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("set_goal_effects_active"):
		node.call("set_goal_effects_active", effects_active)
	for child: Node in node.get_children():
		_set_goal_effects_active_recursive(child, effects_active)


func _play_goal_anim(anim: StringName) -> void:
	if anim == &"":
		return
	if _anim_player == null or not is_instance_valid(_anim_player):
		return
	if _anim_player.has_animation(anim):
		_anim_player.play(anim)


func _setup_audio() -> void:
	_idle_audio = _create_audio_player("IdleAudio", idle_sound)
	_win_audio = _create_audio_player("WinAudio", win_sound)
	_back_audio = _create_audio_player("BackAudio", back_sound)
	if _back_audio != null and not _back_audio.finished.is_connected(_on_back_sound_finished):
		_back_audio.finished.connect(_on_back_sound_finished)


func _create_audio_player(node_name: StringName, stream: AudioStream) -> AudioStreamPlayer3D:
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = stream
	player.bus = sound_bus
	player.volume_db = sound_volume_db
	player.unit_size = max(sound_unit_size, 0.1)
	player.max_distance = max(sound_max_distance, 0.0)
	player.attenuation_filter_cutoff_hz = clamp(sound_attenuation_filter_cutoff_hz, 20.0, 20500.0)
	player.attenuation_filter_db = clamp(sound_attenuation_filter_db, -80.0, 0.0)
	add_child(player)
	return player


func _sync_idle_sound() -> void:
	if _idle_audio == null or not is_instance_valid(_idle_audio):
		return
	var should_play: bool = active and visual_enabled and not _touched_this_race
	if should_play:
		if not _idle_audio.playing and (_back_audio == null or not _back_audio.playing):
			_idle_audio.play()
		return
	_idle_audio.stop()


func _play_win_sound() -> void:
	if _idle_audio != null:
		_idle_audio.stop()
	if _back_audio != null:
		_back_audio.stop()
	if _win_audio != null and _win_audio.stream != null:
		_win_audio.play()


func _play_back_sound() -> void:
	if _idle_audio != null:
		_idle_audio.stop()
	if _back_audio != null and _back_audio.stream != null:
		_back_audio.play()
		return
	_sync_idle_sound()


func _on_back_sound_finished() -> void:
	_sync_idle_sound()


func _on_body_entered(body: Node) -> void:
	if not active or _sequence_running:
		return
	if _touched_this_race:
		return
	if one_shot and _triggered:
		return
	if body == null:
		return
	if not (body is CharacterBody3D):
		return
	# Buddy pawns should never finish races.
	if body.has_method("has_meta") and body.call("has_meta", "is_buddy"):
		var v = body.call("get_meta", "is_buddy")
		if v is bool and bool(v):
			return

	if require_group_primary != &"" and body.is_in_group(require_group_primary):
		pass
	elif require_group_secondary != &"" and body.is_in_group(require_group_secondary):
		pass
	else:
		var looks_like_player: bool = body.has_method("set_ui_input_blocked") and body.has_method("_apply_respawn_transform")
		if not looks_like_player:
			return

	if not _is_player_in_race(body):
		return

	# Only affect the local authority in multiplayer.
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if body.has_method("is_multiplayer_authority") and not body.is_multiplayer_authority():
			return

	var race_start: Node = _resolve_race_start()
	if _goal_returns_to_start(race_start):
		if not _return_to_start_running:
			call_deferred("_return_player_to_race_start", body, race_start)
		return

	finish_for_player(body)


func finish_for_player(player: Node) -> void:
	if not active or _sequence_running or _touched_this_race:
		return
	if player == null or not is_instance_valid(player):
		return
	if not _is_player_in_race(player):
		return
	if player.has_method("finish_active_combo"):
		player.call("finish_active_combo")
	if player.has_method("set"):
		player.set("race_finished", true)
	if player.has_method("play_voice_event"):
		player.call("play_voice_event", &"finish_line")
	_touched_this_race = true
	_play_goal_anim(anim_touched)
	_set_goal_effects_active_recursive(_visual_root, false)
	_play_win_sound()
	_triggered = true
	if not _is_online():
		_register_finish_fade_camera_constraint(player)
	call_deferred("_run_goal_sequence", player)


func _goal_returns_to_start(race_start: Node) -> bool:
	if race_start == null or not is_instance_valid(race_start):
		return false
	if race_start.has_method("uses_back_goal_ring"):
		var back_ring_value = race_start.call("uses_back_goal_ring")
		return back_ring_value is bool and bool(back_ring_value)
	if not race_start.has_method("is_collection_race"):
		return false
	var collection_value = race_start.call("is_collection_race")
	return collection_value is bool and bool(collection_value)


func _return_player_to_race_start(player: Node, race_start: Node) -> void:
	if _return_to_start_running:
		return
	if player == null or not is_instance_valid(player):
		return
	if race_start == null or not is_instance_valid(race_start):
		return
	if not race_start.has_method("_get_start_transform_for_player"):
		return
	_return_to_start_running = true
	_play_back_sound()
	var transform_value = race_start.call("_get_start_transform_for_player", player)
	if transform_value is Transform3D:
		await RaceTransitionHelperScript.fade_teleport_player(
			self,
			player,
			transform_value,
			fade_out_duration,
			fade_hold_duration,
			fade_in_duration,
			Color.WHITE,
			func() -> bool: return is_instance_valid(player) and _is_player_in_race(player)
		)
	_return_to_start_running = false


func _run_goal_sequence(player: Node) -> void:
	if _sequence_running:
		_unregister_finish_fade_camera_constraint()
		return
	if player == null or not is_instance_valid(player):
		_unregister_finish_fade_camera_constraint()
		return
	if _is_online() and not _is_player_in_race(player):
		_unregister_finish_fade_camera_constraint()
		return
	if _is_online():
		call_deferred("_run_goal_sequence_online", player)
		return
	_sequence_running = true
	_sequence_token += 1
	var sequence_token: int = _sequence_token
	_sequence_player = player

	var prev_ui_blocked: bool = false
	if player.has_method("get"):
		var v = player.get("_ui_input_blocked")
		if v is bool:
			prev_ui_blocked = bool(v)
	if player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", true)

	# Finish line should free cursor for UI interaction (and for skipping delays).
	_unlock_cursor(player)

	_set_player_race_state(player, false, false, true)
	HUDMusicTrackDisplay.post_notification(
		get_tree(),
		"Finish Line",
		"Race complete!",
		null,
		3.0
	)

	var hud = _resolve_hud(player)
	var final_time: float = 0.0
	if hud != null and is_instance_valid(hud):
		if hud.has_method("set_timer_running"):
			hud.call("set_timer_running", false)
		if hud.has_method("get"):
			var et = hud.get("elapsed_time")
			if et is float:
				final_time = float(et)

	var rings_value: int = 0
	var score_value: int = 0
	if player.has_method("get"):
		var rv = player.get("rings")
		if rv is int:
			rings_value = int(rv)
		var sv = player.get("score")
		if sv is int:
			score_value = int(sv)
	var debug_used: bool = false
	if player.has_method("get"):
		var dv = player.get("race_debug_used")
		if dv is bool:
			debug_used = bool(dv)
	var ghost_note := ""
	var race_start = _resolve_race_start()
	if race_start != null and is_instance_valid(race_start) and race_start.has_method("get_active_ghost_time_comparison"):
		var comparison_value = race_start.call("get_active_ghost_time_comparison", final_time)
		if comparison_value is String:
			ghost_note = String(comparison_value)
	if race_start != null and is_instance_valid(race_start) and race_start.has_method("finalize_local_ghost_run"):
		var ghost_note_value = race_start.call("finalize_local_ghost_run", player, final_time, score_value, debug_used)
		if ghost_note_value is String:
			var recording_note: String = String(ghost_note_value)
			if recording_note.strip_edges() != "":
				ghost_note += ("\n" if ghost_note.strip_edges() != "" else "") + recording_note

	var is_new_record: bool = false
	if not debug_used and final_time > 0.0:
		var level_key := _get_level_key()
		if race_start != null and is_instance_valid(race_start) and race_start.has_method("get_high_score_key"):
			level_key = String(race_start.call("get_high_score_key"))
		is_new_record = HighScoreManager.save_time_if_better(level_key, final_time)

	var ui = _spawn_ui()
	if ui != null and is_instance_valid(ui) and race_start != null and is_instance_valid(race_start):
		if ui.has_method("configure_ghost_save") and race_start.has_method("get_pending_ghost_summary"):
			ui.call("configure_ghost_save", race_start.call("get_pending_ghost_summary"))
		if ui.has_signal("ghost_save_requested"):
			ui.connect("ghost_save_requested", Callable(self, "_on_ghost_save_requested").bind(race_start, ui))

	var fader = _get_or_create_fader()
	var prev_fade_color: Color = Color.BLACK
	if fader != null and fader.has_method("get"):
		var c = fader.get("fade_color")
		if c is Color:
			prev_fade_color = c
	if fader != null and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", fade_color)

	_notify_camera_teleport(player, fade_out_duration + fade_hold_duration + fade_in_duration)
	if fader != null:
		_fade_out_music()
		await fader.call("fade_out", fade_out_duration)
		if not _goal_sequence_is_current(player, sequence_token):
			return
		_unregister_finish_fade_camera_constraint()
		if get_tree() != null and fade_hold_duration > 0.0:
			await get_tree().create_timer(fade_hold_duration).timeout
			if not _goal_sequence_is_current(player, sequence_token):
				return
	else:
		_unregister_finish_fade_camera_constraint()

	_teleport_player_to_goal_pose(player)
	var using_animated_victory_camera: bool = _begin_victory_presentation(player)
	_register_goal_camera_constraint(player)
	if using_animated_victory_camera and get_tree() != null:
		await get_tree().process_frame
		if not _goal_sequence_is_current(player, sequence_token):
			return
	_notify_camera_teleport(player, fade_in_duration + 0.25)

	if fader != null:
		await fader.call("fade_in", fade_in_duration)
		if not _goal_sequence_is_current(player, sequence_token):
			return

	_play_results_music()

	# Wait before showing results (skippable with Ability Slot 1 via RaceUI).
	if ui != null and is_instance_valid(ui) and ui.has_method("wait_or_skip"):
		await ui.call("wait_or_skip", results_delay)
		if not _goal_sequence_is_current(player, sequence_token):
			return
	if ui != null and is_instance_valid(ui) and ui.has_method("show_results"):
		ui.call("show_results", rings_value, final_time, score_value, is_new_record, ghost_note)
	if ui != null and is_instance_valid(ui) and ui.has_method("set_restart_label"):
		ui.call("set_restart_label", "Return to start")

	# Wait before showing options (also skippable).
	if ui != null and is_instance_valid(ui) and ui.has_method("wait_or_skip"):
		await ui.call("wait_or_skip", options_delay)
		if not _goal_sequence_is_current(player, sequence_token):
			return
	if ui != null and is_instance_valid(ui) and ui.has_method("show_options"):
		ui.call("show_options")

	var selected: StringName = &"stay"
	if ui != null and is_instance_valid(ui):
		selected = await ui.option_selected
		if not _goal_sequence_is_current(player, sequence_token):
			return
	if race_start != null and is_instance_valid(race_start) and race_start.has_method("discard_pending_ghost_run"):
		race_start.call("discard_pending_ghost_run")

	# Always do a fade-out/fade-in for stay/return/restart.
	if fader != null and is_instance_valid(fader):
		_notify_camera_teleport(player, fade_out_duration + fade_hold_duration + fade_in_duration)
		await fader.call("fade_out", fade_out_duration)
		if not _goal_sequence_is_current(player, sequence_token):
			return
		if get_tree() != null and fade_hold_duration > 0.0:
			await get_tree().create_timer(fade_hold_duration).timeout
			if not _goal_sequence_is_current(player, sequence_token):
				return

	if selected == &"restart_race":
		_reset_objects_for_race_restart()
		_return_to_race_start(player, race_start)
		selected = &"stay"

	_handle_goal_option_no_restart(player, selected)

	if selected == &"return_menu":
		# Fade-out already done; switch scenes now.
		_unregister_goal_camera_constraint(player)
		_unlock_cursor(player)
		if ui != null and is_instance_valid(ui):
			ui.queue_free()
		var tree := get_tree()
		if tree != null and main_menu_scene != null:
			tree.change_scene_to_packed(main_menu_scene)
			# Fade in so we don't leave the user on a white screen.
			if fader != null and is_instance_valid(fader):
				await tree.process_frame
				if fader != null and is_instance_valid(fader):
					await fader.call("fade_in", fade_in_duration)
					if fader.has_method("set_fade_color"):
						fader.call("set_fade_color", prev_fade_color)
		_sequence_running = false
		_sequence_player = null
		return

	# For gameplay options, re-lock cursor before returning control to the player.
	# (Return to menu intentionally stays unlocked.)
	if selected == &"stay" or selected == &"return_hub":
		_lock_cursor(player)

	if fader != null and is_instance_valid(fader):
		_notify_camera_teleport(player, fade_in_duration + 0.25)
		await fader.call("fade_in", fade_in_duration)
		if not _goal_sequence_is_current(player, sequence_token):
			return

	if player != null and is_instance_valid(player) and player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", prev_ui_blocked)

	_unregister_goal_camera_constraint(player)
	if ui != null and is_instance_valid(ui):
		ui.queue_free()

	# Restore fader color for other systems.
	if fader != null and is_instance_valid(fader) and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", prev_fade_color)

	_sequence_running = false
	_sequence_player = null


func _goal_sequence_is_current(player: Node, token: int) -> bool:
	return token == _sequence_token and is_inside_tree() and is_instance_valid(player) and player.is_inside_tree()


func cancel_for_player(player: Node) -> void:
	if _sequence_player != player:
		return
	_sequence_token += 1
	_sequence_running = false
	_sequence_player = null
	_unregister_finish_fade_camera_constraint()
	_unregister_goal_camera_constraint(player)
	if get_tree():
		for fader: Node in get_tree().get_nodes_in_group("ScreenFader"):
			if fader.has_method("reset_now"):
				fader.call("reset_now")


func _on_ghost_save_requested(race_start: Node, ui: Node) -> void:
	if race_start == null or not is_instance_valid(race_start) or not race_start.has_method("save_pending_ghost_run"):
		if ui != null and is_instance_valid(ui) and ui.has_method("set_ghost_save_result"):
			ui.call("set_ghost_save_result", "")
		return
	var saved_path: String = String(race_start.call("save_pending_ghost_run"))
	if ui != null and is_instance_valid(ui) and ui.has_method("set_ghost_save_result"):
		ui.call("set_ghost_save_result", saved_path)


func _is_online() -> bool:
	return multiplayer and multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _is_player_in_race(player: Node) -> bool:
	if player == null or not player.has_method("get"):
		return false
	var v = player.get("race_in_countdown")
	if v is bool and bool(v):
		return true
	var v2 = player.get("race_active")
	if v2 is bool and bool(v2):
		return true
	var v3 = player.get("race_session_joined")
	if v3 is bool and bool(v3):
		return true
	return false


func _run_goal_sequence_online(player: Node) -> void:
	# Online: report finish to server and wait for server-driven results.
	if not is_instance_valid(player) or not _is_online() or not _is_player_in_race(player):
		_unregister_finish_fade_camera_constraint()
		return
	_sequence_running = true

	var hud = _resolve_hud(player)
	var final_time: float = 0.0
	if hud != null and is_instance_valid(hud):
		if hud.has_method("set_timer_running"):
			hud.call("set_timer_running", false)
		if hud.has_method("get"):
			var et = hud.get("elapsed_time")
			if et is float:
				final_time = float(et)

	var rings_value: int = 0
	var score_value: int = 0
	if player.has_method("get"):
		var rv = player.get("rings")
		if rv is int:
			rings_value = int(rv)
		var sv = player.get("score")
		if sv is int:
			score_value = int(sv)

	# Tell the server we finished (server handles place + results countdown).
	var session = null
	var debug_used: bool = false
	if player.has_method("get"):
		var dv = player.get("race_debug_used")
		if dv is bool:
			debug_used = bool(dv)
	if get_tree() != null and get_tree().current_scene != null:
		session = get_tree().current_scene.get_node_or_null("NetworkSession")
	if session != null and session.has_method("report_race_finish"):
		var path_str: String = ""
		if get_tree() != null and get_tree().current_scene != null:
			path_str = String(get_tree().current_scene.get_path_to(self))
		session.call("report_race_finish", path_str, final_time, rings_value, score_value, debug_used)

	if player.has_method("set"):
		player.set("race_finished", true)
	if player.has_method("show_prompt"):
		player.call("show_prompt", "Finished!  Waiting for race results...", 6.0)

	_sequence_running = false


func _handle_goal_option_no_restart(player: Node, option: StringName) -> void:
	if option == &"return_hub":
		_unregister_goal_camera_constraint(player)
		_end_singleplayer_race(player)
		var hud = _resolve_hud(player)
		if hud != null and is_instance_valid(hud) and hud.has_method("set_timer_running"):
			hud.call("set_timer_running", true)
		if player != null and is_instance_valid(player):
			if player.has_method("set_ui_input_blocked"):
				player.call("set_ui_input_blocked", false)
			if player.has_method("set"):
				player.set("lock_cursor_to_game", true)
			if player.has_method("_update_mouse_lock"):
				player.call("_update_mouse_lock")
		_return_to_hub()
		return

	# stay
	_unregister_goal_camera_constraint(player)
	_end_singleplayer_race(player)


func _teleport_player_to_goal_pose(player: Node) -> void:
	var pose_node = get_node_or_null(goal_pose_path)
	if pose_node == null and get_tree() != null and get_tree().current_scene != null:
		pose_node = get_tree().current_scene.get_node_or_null(goal_pose_path)
	var t: Transform3D = global_transform
	if pose_node is Node3D:
		t = (pose_node as Node3D).global_transform
	if downwarp_enabled:
		t = _apply_downwarp(t, player)

	if player.has_method("reset_water_state_for_teleport"):
		player.call("reset_water_state_for_teleport")
	if player.has_method("_apply_respawn_transform"):
		player.call("_apply_respawn_transform", t, false)
		if player.has_method("set"):
			player.set("attached", true)
			player.set("_prev_attached", true)
		if player.has_method("stop_all_momentum_and_special_movement"):
			player.call("stop_all_momentum_and_special_movement")
		_apply_goal_pose_visual_alignment(player, t)
		return

	if player is Node3D:
		(player as Node3D).global_transform = t
		if player.has_method("set"):
			player.set("velocity", Vector3.ZERO)
			player.set("attached", true)
			player.set("_prev_attached", true)
		if player.has_method("stop_all_momentum_and_special_movement"):
			player.call("stop_all_momentum_and_special_movement")
	_apply_goal_pose_visual_alignment(player, t)


func _apply_goal_pose_visual_alignment(player: Node, pose_xform: Transform3D) -> void:
	# SUMMARY: Snap the model to the goal pose facing direction for results.
	# STEPS:
	# - Step 1: Extract up/forward from the pose transform.
	# - Step 2: Use snap_model_to_normal to apply an immediate visual alignment.
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("snap_model_to_normal"):
		return

	var up: Vector3 = pose_xform.basis.y
	if up.length() < 0.001:
		up = Vector3.UP
	var forward: Vector3 = -pose_xform.basis.z
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	player.call("snap_model_to_normal", up, forward)


func _apply_downwarp(xform: Transform3D, player: Node) -> Transform3D:
	if get_world_3d() == null:
		return xform
	var from_pos: Vector3 = xform.origin + Vector3.UP * 0.1
	var to_pos: Vector3 = xform.origin + Vector3.DOWN * max(downwarp_distance, 0.0)

	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	params.collision_mask = downwarp_collision_mask
	if player != null and is_instance_valid(player):
		params.exclude = [player]

	var result = get_world_3d().direct_space_state.intersect_ray(params)
	if result:
		var p = result.position
		xform.origin = p + Vector3.UP * max(downwarp_offset, 0.0)
	return xform


func _register_goal_camera_constraint(player: Node) -> void:
	if _goal_constraint != null and is_instance_valid(_goal_constraint):
		return
	var rig: Node = _resolve_camera_rig(player)
	if rig == null or not rig.has_method("register_camera_constraint"):
		return

	var camera_source: Node3D = _resolve_goal_camera_source()
	var xform: Transform3D = camera_source.global_transform if camera_source != null else global_transform
	var c := RaceCameraConstraint.new()
	c.constraint_priority = 9500
	c.disable_camera_controls = true
	if fov_override_enabled:
		var lens: CameraLensTrait = CameraLensTrait.new()
		lens.fov = fov_override
		c.lens_traits.append(lens)
	if goal_camera_mode == GoalCameraMode.LEGACY_PIVOT:
		xform.origin += camera_position_offset
		c.set_locked_transform(xform)
		if face_player:
			c.aim_trait.mode = CameraOrientationTrait.Mode.FACE_PLAYER
			c.aim_trait.orbit_rig = false
			c.aim_trait.tracking_response = 14.0
		c.aim_trait.target_offset = _compute_aim_offset(player)
	else:
		c.set_locked_transform(xform)
		c.position_trait.mode = CameraPositionTrait.Mode.FIXED_CAMERA
		c.position_trait.source_node = camera_source
		c.collision_mode = CameraConstraint.CollisionMode.DISABLED
		c.aim_trait.target_node = camera_source
		c.aim_trait.orbit_rig = false
		var uses_static_camera_source: bool = goal_camera_mode == GoalCameraMode.STATIC_GOAL_CAMERA or _active_victory_presentation == null
		c.position_trait.offset = camera_position_offset if uses_static_camera_source else Vector3.ZERO
		if not fov_override_enabled and camera_source is Camera3D:
			var lens: CameraLensTrait = CameraLensTrait.new()
			lens.mode = CameraLensTrait.Mode.SOURCE_FOV
			lens.source_node = camera_source
			c.lens_traits.append(lens)
		if goal_camera_mode == GoalCameraMode.PLAYER_VICTORY_CAMERA and _active_victory_presentation != null:
			c.aim_trait.marker_uses_guide_basis = _victory_camera_uses_guide_basis()
		elif face_player and player is Node3D:
			c.aim_trait.mode = CameraOrientationTrait.Mode.FACE_TARGET
			c.aim_trait.target_node = player as Node3D
			c.aim_trait.target_offset = _compute_aim_offset(player)
			c.aim_trait.up_override = _get_goal_camera_aim_up()
		else:
			c.aim_trait.marker_uses_guide_basis = true

	_goal_constraint = c
	_goal_camera_rig = rig
	add_child(c)
	rig.call("register_camera_constraint", c)


func _resolve_goal_camera_source() -> Node3D:
	if goal_camera_mode == GoalCameraMode.PLAYER_VICTORY_CAMERA and _active_victory_presentation != null:
		if _active_victory_presentation.has_method("get_victory_camera_anchor"):
			var anchor_value: Variant = _active_victory_presentation.call("get_victory_camera_anchor")
			if anchor_value is Node3D and is_instance_valid(anchor_value):
				return anchor_value as Node3D
	var goal_camera_node: Node = get_node_or_null(goal_camera_point_path)
	if goal_camera_node == null and get_tree() != null and get_tree().current_scene != null:
		goal_camera_node = get_tree().current_scene.get_node_or_null(goal_camera_point_path)
	return goal_camera_node as Node3D


func _get_goal_camera_aim_up() -> Vector3:
	var pose_transform: Transform3D = get_goal_pose_transform()
	var aim_up: Vector3 = pose_transform.basis.y.normalized()
	if aim_up.length() < 0.001:
		aim_up = Vector3.UP
	return aim_up


func _begin_victory_presentation(player: Node) -> bool:
	_end_victory_presentation()
	if goal_camera_mode != GoalCameraMode.PLAYER_VICTORY_CAMERA:
		return false
	_active_victory_presentation = _find_victory_presentation(player)
	if _active_victory_presentation == null:
		return false
	_active_victory_presentation.call("begin_victory_presentation")
	var anchor_value: Variant = _active_victory_presentation.call("get_victory_camera_anchor")
	if anchor_value is Node3D and is_instance_valid(anchor_value):
		return true
	_end_victory_presentation()
	return false


func _find_victory_presentation(player: Node) -> Node:
	if player == null or not is_instance_valid(player):
		return null
	if player.has_method("begin_victory_presentation") and player.has_method("get_victory_camera_anchor"):
		return player
	for descendant: Node in player.find_children("*", "", true, false):
		if descendant.has_method("begin_victory_presentation") and descendant.has_method("get_victory_camera_anchor"):
			return descendant
	return null


func _victory_camera_uses_guide_basis() -> bool:
	if _active_victory_presentation == null or not is_instance_valid(_active_victory_presentation):
		return false
	if not _active_victory_presentation.has_method("victory_camera_uses_guide_basis"):
		return false
	return bool(_active_victory_presentation.call("victory_camera_uses_guide_basis"))


func _end_victory_presentation() -> void:
	if _active_victory_presentation != null and is_instance_valid(_active_victory_presentation):
		if _active_victory_presentation.has_method("end_victory_presentation"):
			_active_victory_presentation.call("end_victory_presentation")
	_active_victory_presentation = null


func _register_finish_fade_camera_constraint(player: Node) -> void:
	_unregister_finish_fade_camera_constraint()
	var rig: Node = _resolve_camera_rig(player)
	if rig == null or not rig.has_method("register_camera_constraint"):
		return
	var camera_value: Variant = rig.get("camera")
	var pitch_value: Variant = rig.get("pitch_node")
	if not (camera_value is Camera3D) or not (pitch_value is Node3D):
		return
	var camera: Camera3D = camera_value as Camera3D
	var pitch: Node3D = pitch_value as Node3D
	if not is_instance_valid(camera) or not is_instance_valid(pitch):
		return
	var camera_distance: float = pitch.global_position.distance_to(camera.global_position)
	var minimum_distance: float = camera_distance
	var maximum_distance: float = camera_distance
	var minimum_distance_value: Variant = rig.get("min_distance")
	var maximum_distance_value: Variant = rig.get("max_distance")
	if minimum_distance_value is float:
		minimum_distance = float(minimum_distance_value)
	if maximum_distance_value is float:
		maximum_distance = float(maximum_distance_value)
	var locked_distance: float = clamp(camera_distance, minimum_distance, maximum_distance)
	var locked_origin: Vector3 = camera.global_position + pitch.global_basis.z * locked_distance
	var locked_transform: Transform3D = Transform3D(pitch.global_basis, locked_origin)
	var constraint := RaceCameraConstraint.new()
	constraint.set_locked_transform(locked_transform)
	constraint.constraint_priority = 10000
	constraint.disable_camera_controls = true
	var orbit: CameraLensTrait = CameraLensTrait.new()
	orbit.mode = CameraLensTrait.Mode.ORBIT_DISTANCE
	orbit.distance = locked_distance
	var lens: CameraLensTrait = CameraLensTrait.new()
	lens.fov = camera.fov
	constraint.lens_traits.assign([orbit, lens])
	constraint.collision_mode = CameraConstraint.CollisionMode.DISABLED
	_finish_fade_camera_constraint = constraint
	_finish_fade_camera_rig = rig
	rig.call("register_camera_constraint", constraint)


func _unregister_finish_fade_camera_constraint() -> void:
	if _finish_fade_camera_constraint == null:
		_finish_fade_camera_rig = null
		return
	if is_instance_valid(_finish_fade_camera_rig) and _finish_fade_camera_rig.has_method("unregister_camera_constraint"):
		_finish_fade_camera_rig.call("unregister_camera_constraint", _finish_fade_camera_constraint)
	if is_instance_valid(_finish_fade_camera_constraint):
		_finish_fade_camera_constraint.free()
	_finish_fade_camera_constraint = null
	_finish_fade_camera_rig = null


func _unregister_goal_camera_constraint(player: Node = null) -> void:
	if _goal_constraint == null or not is_instance_valid(_goal_constraint):
		_goal_constraint = null
		_goal_camera_rig = null
		_end_victory_presentation()
		return
	var rig: Node = _goal_camera_rig
	if rig == null or not is_instance_valid(rig):
		rig = _resolve_camera_rig(player)
	if rig != null and rig.has_method("unregister_camera_constraint"):
		rig.call("unregister_camera_constraint", _goal_constraint)
	_goal_constraint.queue_free()
	_goal_constraint = null
	_goal_camera_rig = null
	_end_victory_presentation()


func _get_goal_camera_transform() -> Transform3D:
	var n = get_node_or_null(goal_camera_point_path)
	if n == null and get_tree() != null and get_tree().current_scene != null:
		n = get_tree().current_scene.get_node_or_null(goal_camera_point_path)
	if n is Node3D:
		return (n as Node3D).global_transform
	return global_transform


func get_goal_pose_transform() -> Transform3D:
	var pose_node = get_node_or_null(goal_pose_path)
	if pose_node == null and get_tree() != null and get_tree().current_scene != null:
		pose_node = get_tree().current_scene.get_node_or_null(goal_pose_path)
	if pose_node is Node3D:
		var t: Transform3D = (pose_node as Node3D).global_transform
		if downwarp_enabled:
			t = _apply_downwarp(t, null)
		return t
	return global_transform


func apply_online_lineup_pose(player: Node, order: Array, dnfs: Array, targets: Array, peer_id: int) -> void:
	var lineup: Array[int] = []
	for id: int in order + dnfs:
		if targets.has(id) and not lineup.has(id):
			lineup.append(id)
	var index: int = lineup.find(peer_id)
	if index < 0 or not is_instance_valid(player):
		return
	var pose: Transform3D = get_goal_pose_transform()
	var right: Vector3 = pose.basis.x.normalized()
	var forward: Vector3 = -pose.basis.z.normalized()
	pose.origin += forward * lineup_front_offset
	if index == 1:
		pose.origin += -forward * lineup_back_step - right * lineup_side_offset
	elif index == 2:
		pose.origin += -forward * lineup_back_step + right * lineup_side_offset
	elif index > 2:
		var row: int = (index - 3) / 3 + 2
		var column: int = (index - 3) % 3 - 1
		pose.origin += -forward * lineup_back_step * float(row) + right * lineup_side_offset * float(column)
	if downwarp_enabled:
		pose = _apply_downwarp(pose, player)
	player.call("clear_gravity_state", &"race_cleanup", true)
	player.call("reset_water_state_for_teleport")
	player.call("_apply_respawn_transform", pose, false)
	player.call("stop_all_momentum_and_special_movement")
	player.set("attached", true)
	player.set("_prev_attached", true)
	_apply_goal_pose_visual_alignment(player, pose)
	player.call("_network_publish_teleport_state")


func _compute_aim_offset(player: Node) -> Vector3:
	var offset: Vector3 = face_offset
	if not face_player_model_root or player == null or not is_instance_valid(player):
		return offset
	if not player.has_method("get"):
		return offset
	var mr = player.get("model_root")
	if mr is Node3D:
		if player is Node3D:
			offset += (mr as Node3D).global_position - (player as Node3D).global_position
	return offset


func _resolve_camera_rig(player: Node) -> Node:
	if player != null and player.has_method("get"):
		var r = player.get("camera_rig")
		if r != null:
			return r
	if get_tree() == null:
		return null
	var rigs = get_tree().get_nodes_in_group("CameraRig")
	if rigs != null and rigs.size() > 0:
		return rigs[0]
	return null


func _resolve_hud(player: Node) -> Node:
	if player != null and player.has_method("_get_hud_node"):
		var h = player.call("_get_hud_node")
		if h != null and is_instance_valid(h):
			return h
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("HUD")
	if list != null and list.size() > 0:
		return list[0]
	return null


func _spawn_ui() -> Node:
	if race_ui_scene == null:
		return null
	var ui = race_ui_scene.instantiate()
	if ui == null:
		return null
	ui.add_to_group("RaceUI")
	var vp = get_viewport()
	if vp != null:
		vp.add_child(ui)
	elif get_tree() != null and get_tree().current_scene != null:
		get_tree().current_scene.add_child(ui)
	else:
		add_child(ui)
	return ui


func _get_or_create_fader() -> Node:
	if get_tree() == null:
		return null
	var existing = get_tree().get_nodes_in_group("ScreenFader")
	if existing != null and existing.size() > 0:
		return existing[0]

	var fader = ScreenFader.new()
	fader.add_to_group("ScreenFader")
	var vp = get_viewport()
	if vp != null:
		vp.add_child(fader)
	elif get_tree().current_scene != null:
		get_tree().current_scene.add_child(fader)
	else:
		add_child(fader)
	return fader


func _notify_camera_teleport(player: Node, duration: float) -> void:
	var rig = _resolve_camera_rig(player)
	if rig != null and rig.has_method("notify_teleport"):
		rig.call("notify_teleport", duration)


func _get_music_controller():
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("MusicControllers")
	if list != null and list.size() > 0 and list[0] is MusicController:
		return list[0]
	var cs = get_tree().current_scene
	if cs != null:
		var mc = cs.get_node_or_null("MusicController")
		if mc is MusicController:
			return mc
	return null


func _fade_out_music() -> void:
	var mc = _get_music_controller()
	if mc == null:
		return
	mc.stop_music(music_fade_out_time)


func _get_music_controllers() -> Array:
	if get_tree() == null:
		return []
	return get_tree().get_nodes_in_group("MusicControllers")


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


func _get_player_spawn_node() -> Node3D:
	if get_tree() == null:
		return null
	var level_manager = _get_level_manager()
	if level_manager != null:
		if level_manager.has_method("resolve_node_in_current_level"):
			var n = level_manager.call("resolve_node_in_current_level", NodePath("PlayerSpawn"))
			if n is Node3D:
				return n as Node3D
		if level_manager.has_method("get_current_level"):
			var level = level_manager.call("get_current_level")
			if level != null and is_instance_valid(level):
				var level_spawn = level.get_node_or_null("PlayerSpawn")
				if level_spawn is Node3D:
					return level_spawn as Node3D
	var scene = get_tree().current_scene
	if scene != null:
		var n = scene.get_node_or_null("PlayerSpawn")
		if n is Node3D:
			return n as Node3D
		var deep = scene.find_child("PlayerSpawn", true, false)
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


func _return_to_race_start(player: Node, race_start: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	if race_start == null or not is_instance_valid(race_start):
		_return_to_player_spawn(player)
		return
	if race_start.has_method("_teleport_player_to_start"):
		race_start.call("_teleport_player_to_start", player)
		return
	if race_start.has_method("_get_start_transform_for_player"):
		var transform_value: Variant = race_start.call("_get_start_transform_for_player", player)
		if transform_value is Transform3D:
			if player.has_method("_apply_respawn_transform"):
				player.call("_apply_respawn_transform", transform_value, false)
			elif player is Node3D:
				(player as Node3D).global_transform = transform_value


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


func _get_autoplay_controller() -> MusicController:
	if get_tree() == null:
		return null
	var controllers := get_tree().get_nodes_in_group("MusicControllers")
	var fallback: MusicController = null
	for node in controllers:
		if node is MusicController:
			var controller: MusicController = node
			if fallback == null:
				fallback = controller
			if controller.autoplay and controller.autoplay_stream != null:
				return controller
	return fallback


func _restore_autoplay_music() -> void:
	var mc = _get_autoplay_controller()
	if mc == null:
		return
	if mc.has_method("play_autoplay"):
		mc.play_autoplay(true)
	elif mc.autoplay_stream != null:
		var fade_in: float = mc.autoplay_fade_in
		var fade_out: float = music_fade_out_time
		if mc.has_method("get"):
			var v = mc.get("autoplay_fade_out")
			if v is float:
				fade_out = float(v)
		mc.play_music(mc.autoplay_stream, fade_in, fade_out, true)


func _end_singleplayer_race(player: Node) -> void:
	if player != null and is_instance_valid(player) and player.has_method("clear_gravity_state"):
		player.call("clear_gravity_state", &"race_cleanup", true)
	if player != null and is_instance_valid(player) and player.has_method("set"):
		player.set("race_session_joined", false)
		player.set("race_in_countdown", false)
		player.set("race_active", false)
		player.set("race_finished", false)
	if player != null and is_instance_valid(player) and player.has_method("clear_checkpoint_data"):
		player.call("clear_checkpoint_data")

	var race_start = _resolve_race_start()
	if race_start != null and is_instance_valid(race_start):
		if race_start.has_method("deactivate_race_objects"):
			race_start.call("deactivate_race_objects")
		if race_start.has_method("_clear_ghost_runtime"):
			race_start.call("_clear_ghost_runtime")

	_restore_autoplay_music()


func _resolve_race_start() -> Node:
	if race_start_path != NodePath("") and race_start_path != null:
		var n = get_node_or_null(race_start_path)
		if n == null and get_tree() != null and get_tree().current_scene != null:
			n = get_tree().current_scene.get_node_or_null(race_start_path)
		if n != null:
			return n
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("RaceStart")
	for race_start: Node in list:
		if race_start == null or not is_instance_valid(race_start):
			continue
		var active_player: Variant = race_start.get("_active_player")
		if active_player is Node and is_instance_valid(active_player):
			return race_start
	if list != null and list.size() > 0:
		return list[0]
	return null


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)


func _get_level_key() -> String:
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
	var packed = load("res://LS5Framework/Scenes/Main.tscn")
	if packed is PackedScene:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file("res://LS5Framework/Scenes/Main.tscn")


func _unlock_cursor(player: Node) -> void:
	if player != null and is_instance_valid(player) and player.has_method("set"):
		player.set("lock_cursor_to_game", false)
	if player != null and is_instance_valid(player) and player.has_method("_update_mouse_lock"):
		player.call("_update_mouse_lock")


func _lock_cursor(player: Node) -> void:
	if player != null and is_instance_valid(player) and player.has_method("set"):
		player.set("lock_cursor_to_game", true)
	if player != null and is_instance_valid(player) and player.has_method("_update_mouse_lock"):
		player.call("_update_mouse_lock")


func _set_player_race_state(player: Node, in_countdown: bool, race_active: bool, race_finished: bool) -> void:
	if player == null or not player.has_method("set"):
		return
	player.set("race_in_countdown", in_countdown)
	player.set("race_active", race_active)
	player.set("race_finished", race_finished)


func reset_for_race_start() -> void:
	_sequence_token += 1
	_sequence_player = null
	_unregister_finish_fade_camera_constraint()
	_unregister_goal_camera_constraint(null)
	_sequence_running = false
	_return_to_start_running = false
	_triggered = false
	_touched_this_race = false
	if _idle_audio != null:
		_idle_audio.stop()
	if _win_audio != null:
		_win_audio.stop()
	if _back_audio != null:
		_back_audio.stop()
	set_goal_active_for_race(false)
	call_deferred("_play_goal_anim", anim_idle)

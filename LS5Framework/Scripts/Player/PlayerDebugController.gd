extends RefCounted
class_name PlayerDebugController

const DEBUG_TIME_SCRUB_HOURS_PER_SECOND: float = 6.0
const DEBUG_DUMMY_VOICE_GAP: float = 0.35
const DEBUG_DUMMY_VOICE_MAX_DURATION: float = 8.0
const LIP_SYNC_DRIVER_PATH: String = "res://addons/ls5_lipsync/runtime/lip_sync_driver.gd"
const PARAMETER_RELOAD_CHILD_ROOTS: Array[StringName] = [&"Abilities", &"TrickSystem"]
const DEBUG_HUD_SCENE: PackedScene = preload("res://LS5Framework/Scenes/Debug/PlayerDebugHUD.tscn")

# Debug input, free flight, runtime diagnostics, and debug rendering.
var _owner: Node = null
var _dummy_animation_player: AnimationPlayer = null
var _dummy_animation_names: PackedStringArray = PackedStringArray()
var _dummy_animation_index: int = 0
var _dummy_voice_player: AudioStreamPlayer3D = null
var _dummy_voice_clips: Array[AudioStream] = []
var _dummy_voice_index: int = 0
var _dummy_voice_elapsed: float = 0.0
var _dummy_voice_gap_elapsed: float = 0.0


func _init(owner: Node) -> void:
	_owner = owner


func _create_debug_hud() -> void:
	var p = _owner
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 90
	p.add_child(canvas)
	var hud_instance: Node = DEBUG_HUD_SCENE.instantiate()
	if hud_instance is Control:
		p._debug_hud = hud_instance as Control
		canvas.add_child(p._debug_hud)
		if p._debug_hud.has_method("get_legacy_label"):
			p._debug_label = p._debug_hud.call("get_legacy_label") as Label
		p._debug_hud.visible = p._debug_visible
		return
	p._debug_label = Label.new()
	canvas.add_child(p._debug_label)
	p._debug_label.offset_left = 10.0
	p._debug_label.offset_top = 10.0
	p._debug_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	p._debug_label.add_theme_color_override(&"font_color", Color.WHITE)
	p._debug_label.visible = p._debug_visible


func _update_mouse_lock() -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if p.lock_cursor_to_game:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _handle_debug_enter_press() -> void:
	var p = _owner
	var in_race: bool = (p.race_in_countdown or p.race_active) and not p.race_finished
	if not in_race:
		_set_debug_mode(not p._debug_mode)
		return

	if p._race_debug_confirmed:
		_set_debug_mode(not p._debug_mode)
		return

	if p._debug_mode:
		p._race_debug_confirmed = true
		_set_debug_mode(not p._debug_mode)
		return

	if p._race_debug_confirm_pending and p._race_debug_confirm_timer > 0.0:
		p._race_debug_confirm_pending = false
		p._race_debug_confirm_timer = 0.0
		p._race_debug_confirmed = true
		_set_debug_mode(true)
		return

	p._race_debug_confirm_pending = true
	p._race_debug_confirm_timer = 3.0
	p.show_prompt("Press again to activate debug (high score will not be saved)", 3.0)


func _ensure_debug_input_actions() -> void:
	# Don't require manual project.godot edits; add defaults if missing.
	_add_input_action_key("debug_enter", Key.KEY_F1)
	_add_input_action_key("debug_fast", Key.KEY_SHIFT)
	_add_input_action_key("debug_slow", Key.KEY_CTRL)
	_add_input_action("debug_fly_up")
	_add_input_action("debug_fly_down")
	_add_input_action("debug_reload_player_parameters")
	_add_input_action_key("debug_reload_level_in_place", Key.KEY_SEMICOLON)
	_add_input_action_key("debug_rewind_time_of_day", Key.KEY_COMMA)
	_add_input_action_key("debug_advance_time_of_day", Key.KEY_PERIOD)
	_add_input_action_key("debug_next_anim", Key.KEY_PAGEDOWN)
	_add_input_action_key("debug_prev_anim", Key.KEY_PAGEUP)
	_add_input_action_key("buddy_spawn", Key.KEY_F3)
	_add_input_action_key("respawn_checkpoint", Key.KEY_F2)
	_add_input_action_key("unstuck", Key.KEY_F4)
	_add_input_action_key("spawn_online_debug_puppet", Key.KEY_F6)
	_add_input_action_key("debug_gravity_upside_down", Key.KEY_KP_8)
	_add_input_action_key("debug_gravity_normal", Key.KEY_KP_5)


func _add_input_action(action_name: StringName) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)


func _add_input_action_key(action_name: StringName, keycode_value: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = keycode_value
	InputMap.action_add_event(action_name, ev)


func update_day_night_scrub(delta: float) -> bool:
	var p: Node = _owner
	if not p._network_is_local_authority():
		return false
	if p.has_meta("is_buddy") and bool(p.get_meta("is_buddy")):
		return false
	if p.has_meta("is_rival_actor") and bool(p.get_meta("is_rival_actor")):
		return false
	if p._ui_input_blocked or p._local_pause_enabled:
		return false
	var tree: SceneTree = p.get_tree()
	if not tree:
		return false
	if tree.paused or not _debug_inputs_allowed():
		return false
	var direction: float = Input.get_axis(&"debug_rewind_time_of_day", &"debug_advance_time_of_day")
	if is_zero_approx(direction):
		return false
	var hour_offset: float = direction * DEBUG_TIME_SCRUB_HOURS_PER_SECOND * max(delta, 0.0)
	var cycles: Array[Node] = tree.get_nodes_in_group(&"day_night_cycle")
	var time_changed: bool = false
	for cycle: Node in cycles:
		if cycle.has_method("offset_time"):
			cycle.call("offset_time", hour_offset)
			time_changed = true
	return time_changed


func reload_level_in_place() -> void:
	var p: Node = _owner
	var tree: SceneTree = p.get_tree()
	if not tree:
		return
	var managers: Array[Node] = tree.get_nodes_in_group(&"LevelManager")
	if managers.is_empty():
		push_warning("Level reload failed: no LevelManager was found.")
		return
	var level_manager: Node = managers[0]
	if level_manager.has_method("reload_current_level_in_place"):
		level_manager.call("reload_current_level_in_place")


func _toggle_online_debug_puppet() -> void:
	var p = _owner
	if p._debug_online_puppet != null and is_instance_valid(p._debug_online_puppet):
		var existing_session: Node = _get_network_session(p)
		if existing_session != null and existing_session.has_method("unregister_debug_dummy_player"):
			existing_session.call("unregister_debug_dummy_player", p._debug_online_puppet)
		p._debug_online_puppet.queue_free()
		p._debug_online_puppet = null
		_reset_debug_puppet_cycle()
		return

	_spawn_online_debug_puppet()


func _spawn_online_debug_puppet() -> void:
	var p = _owner
	var packed: PackedScene = null
	var session: Node = _get_network_session(p)
	if p.scene_file_path:
		var player_scene: Resource = load(p.scene_file_path)
		if player_scene is PackedScene:
			packed = player_scene
	if packed == null:
		push_warning("SonicPlayer: no player scene available for debug puppet.")
		return

	var inst = packed.instantiate()
	if inst == null:
		return

	var debug_peer_id: int = 0
	if session != null and session.has_method("get_debug_dummy_peer_id"):
		debug_peer_id = int(session.call("get_debug_dummy_peer_id"))
	inst.name = "Player_%d" % debug_peer_id if debug_peer_id > 0 else "Player_DebugPuppet"
	inst.set_meta(&"debug_online_dummy", true)
	if inst is Node3D:
		(inst as Node3D).global_transform = _get_debug_puppet_transform(p)

	if inst.is_in_group("Player"):
		inst.remove_from_group("Player")
	if inst.is_in_group("player"):
		inst.remove_from_group("player")
	inst.add_to_group("RemotePlayer")

	if p._object_has_property(inst, "camera"):
		inst.set("camera", null)
	if p._object_has_property(inst, "camera_rig"):
		inst.set("camera_rig", null)
	if p._object_has_property(inst, "hud"):
		inst.set("hud", null)
	if p._object_has_property(inst, "lock_cursor_to_game"):
		inst.set("lock_cursor_to_game", false)
	if p._object_has_property(inst, "network_replication_enabled"):
		inst.set("network_replication_enabled", false)
	if p._object_has_property(inst, "collision_layer"):
		inst.set("collision_layer", 0)
	if p._object_has_property(inst, "collision_mask"):
		inst.set("collision_mask", 0)

	inst.set_physics_process(false)
	inst.set_process(false)
	inst.set_process_unhandled_input(false)

	var parent_node: Node = p.get_parent()
	if parent_node == null and p.get_tree() != null:
		parent_node = p.get_tree().current_scene
	if parent_node == null:
		inst.queue_free()
		return

	parent_node.add_child(inst)
	inst.process_mode = Node.PROCESS_MODE_DISABLED
	if p._object_has_property(inst, "network_replication_enabled"):
		inst.set("network_replication_enabled", true)
	if p._object_has_property(inst, "collision_layer"):
		inst.set("collision_layer", 0)
	if p._object_has_property(inst, "collision_mask"):
		inst.set("collision_mask", 0)
	inst.set_physics_process(false)
	inst.set_process(false)
	inst.set_process_input(false)
	inst.set_process_unhandled_input(false)
	if session != null and session.has_method("register_debug_dummy_player"):
		session.call("register_debug_dummy_player", inst)

	p._debug_online_puppet = inst
	_setup_debug_puppet_cycle(inst)


func _sync_online_debug_puppet(delta: float) -> void:
	var p = _owner
	if p._debug_online_puppet == null or not is_instance_valid(p._debug_online_puppet):
		_reset_debug_puppet_cycle()
		return
	var elapsed: float = maxf(delta, 0.0)
	if _dummy_voice_player == null or not is_instance_valid(_dummy_voice_player) or _dummy_voice_clips.is_empty():
		return
	_dummy_voice_elapsed += elapsed
	if _dummy_voice_player.playing and _dummy_voice_elapsed < DEBUG_DUMMY_VOICE_MAX_DURATION:
		_dummy_voice_gap_elapsed = 0.0
		return
	if _dummy_voice_player.playing:
		_dummy_voice_player.stop()
	_dummy_voice_gap_elapsed += elapsed
	if _dummy_voice_gap_elapsed >= DEBUG_DUMMY_VOICE_GAP:
		_play_next_debug_puppet_voice(p._debug_online_puppet)


func _setup_debug_puppet_cycle(puppet: Node) -> void:
	_reset_debug_puppet_cycle()
	var model: Node = puppet.get("model_root") as Node
	if model == null:
		model = puppet
	_dummy_animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var animation_tree: AnimationTree = puppet.get("anim_tree") as AnimationTree
	if animation_tree != null:
		animation_tree.active = false
	if _dummy_animation_player != null:
		_dummy_animation_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_dummy_animation_names = _dummy_animation_player.get_animation_list()
		_dummy_animation_names.sort()
		if not _dummy_animation_names.is_empty():
			_dummy_animation_player.play(_dummy_animation_names[0])
	if puppet.has_method("get_dialogue_player"):
		_dummy_voice_player = puppet.call("get_dialogue_player") as AudioStreamPlayer3D
	if _dummy_voice_player != null:
		_dummy_voice_player.process_mode = Node.PROCESS_MODE_ALWAYS
	for node: Node in model.find_children("*", "SkeletonModifier3D", true, false):
		if _is_lip_sync_driver(node):
			node.process_mode = Node.PROCESS_MODE_ALWAYS
			var skeleton: Skeleton3D = node.get_parent() as Skeleton3D
			if skeleton:
				skeleton.process_mode = Node.PROCESS_MODE_ALWAYS
	_dummy_voice_clips = _collect_debug_puppet_voice_clips(puppet)
	_play_next_debug_puppet_voice(puppet)


func _collect_debug_puppet_voice_clips(puppet: Node) -> Array[AudioStream]:
	var clips: Array[AudioStream] = []
	var seen: Dictionary = {}
	var nodes: Array[Node] = [puppet]
	nodes.append_array(puppet.find_children("*", "", true, false))
	for node: Node in nodes:
		if not _is_lip_sync_driver(node):
			continue
		var profile: Resource = node.get("profile") as Resource
		if not profile:
			continue
		var paths: PackedStringArray = profile.get("clip_paths")
		for path: String in paths:
			var lip_sync_clip: Resource = load(path)
			if not lip_sync_clip:
				continue
			var voice: AudioStream = lip_sync_clip.get("audio") as AudioStream
			if not voice:
				continue
			var voice_path: String = voice.resource_path
			if seen.has(voice_path):
				continue
			seen[voice_path] = true
			clips.append(voice)
	for node: Node in nodes:
		for property: Dictionary in node.get_property_list():
			var property_name: String = String(property.get("name", ""))
			if not property_name.ends_with("_clips") or not (property_name.begins_with("voice_") or property_name == "activation_voice_clips"):
				continue
			var value: Variant = node.get(property_name)
			if not (value is Array):
				continue
			for entry: Variant in value:
				if not (entry is AudioStream):
					continue
				var clip: AudioStream = entry as AudioStream
				var clip_key: String = clip.resource_path if clip.resource_path else str(clip.get_instance_id())
				if seen.has(clip_key):
					continue
				seen[clip_key] = true
				clips.append(clip)
	return clips


func _is_lip_sync_driver(node: Node) -> bool:
	var script: Script = node.get_script() as Script
	return script != null and script.resource_path == LIP_SYNC_DRIVER_PATH


func _play_next_debug_puppet_voice(puppet: Node) -> void:
	if _dummy_voice_player == null or not is_instance_valid(_dummy_voice_player) or _dummy_voice_clips.is_empty():
		return
	var clip: AudioStream = _dummy_voice_clips[_dummy_voice_index]
	_dummy_voice_index = (_dummy_voice_index + 1) % _dummy_voice_clips.size()
	_dummy_voice_elapsed = 0.0
	_dummy_voice_gap_elapsed = 0.0
	puppet.call("_ensure_modules")
	var audio: PlayerAudio = puppet.get("_audio_module") as PlayerAudio
	if audio != null:
		audio.play_replicated_voice(clip, PlayerAudio.VOICE_PRIORITY_ACTION)


func _reset_debug_puppet_cycle() -> void:
	_dummy_animation_player = null
	_dummy_animation_names = PackedStringArray()
	_dummy_animation_index = 0
	_dummy_voice_player = null
	_dummy_voice_clips.clear()
	_dummy_voice_index = 0
	_dummy_voice_elapsed = 0.0
	_dummy_voice_gap_elapsed = 0.0


func _get_network_session(player: Node) -> Node:
	if player == null or player.get_tree() == null:
		return null
	var sessions: Array[Node] = player.get_tree().get_nodes_in_group(&"NetworkSession")
	if not sessions.is_empty():
		return sessions[0]
	var current_scene: Node = player.get_tree().current_scene
	if current_scene != null:
		return current_scene.find_child("NetworkSession", true, false)
	return null


func _get_debug_puppet_transform(player: Node3D) -> Transform3D:
	var target_transform: Transform3D = player.global_transform
	var player_up: Vector3 = Vector3.UP
	if player.has_method("get_up_vector"):
		var up_value: Variant = player.call("get_up_vector")
		if up_value is Vector3 and not (up_value as Vector3).is_zero_approx():
			player_up = (up_value as Vector3).normalized()
	var side: Vector3 = target_transform.basis.x.slide(player_up)
	if side.is_zero_approx():
		side = player_up.cross(target_transform.basis.z)
	if side.is_zero_approx():
		side = Vector3.RIGHT
	target_transform.origin += side.normalized() * 4.0 + player_up * 0.25
	return target_transform


func _debug_inputs_allowed() -> bool:
	var p = _owner
	# Block debug toggles while UI (chat/pause menus) should own inputs.
	if p._ui_input_blocked:
		return false
	var vp = p.get_viewport()
	if vp == null:
		return true
	var focus = vp.gui_get_focus_owner()
	if focus == null:
		return true
	return not (focus is LineEdit or focus is TextEdit)


func _set_debug_mode(enabled: bool) -> void:
	var p = _owner
	if not p.debug_mode_enabled:
		return
	if p._debug_mode == enabled:
		return

	if enabled and (p.race_in_countdown or p.race_active) and not p.race_finished:
		p.race_debug_used = true
		_invalidate_race_ghost_recording()
		_report_race_debug_used_to_network_session()

	p._debug_mode = enabled

	if p._debug_mode:
		# Save + disable collisions so we can freely fly around.
		p._debug_saved_collision_layer = p.collision_layer
		p._debug_saved_collision_mask = p.collision_mask
		p.collision_layer = 0
		p.collision_mask = 0

		# Disable AnimationTree so AnimationPlayer cycling is visible/authoritative.
		if p.anim_tree != null:
			p._debug_saved_anim_tree_active = p.anim_tree.active
			p.anim_tree.active = false

		# Clear movement/ability state.
		p.velocity = Vector3.ZERO
		p.attached = false
		p.clear_max_speed_overrides()
		p._move_input = Vector2.ZERO
		p._move_direction = Vector3.ZERO
		p._cancel_barrier_blast()
		p.rolling = false
		if p.has_method("cancel_homing_attack"):
			p.call("cancel_homing_attack", false)
		if p.has_method("cancel_spline_spring"):
			p.call("cancel_spline_spring")
		if p.has_method("cancel_rail_grind"):
			p.call("cancel_rail_grind")
		# Reset spring/action/movement locks and related automation state.
		p._spring_movement_lock_timer = 0.0
		p._spring_action_lock_timer = 0.0
		p._spring_align_timer = 0.0
		p._spring_detached = false
		p._spring_trajectory_torque_active = false
		p._spring_trajectory_landing_forward_pitch_active = false
		p._spring_lock_sideways = false
		p._spring_sideways_gravity_scale = 0.0
		p._spring_clear_move_on_ground = false
		p._spring_clear_action_on_ground = false
		p._dash_speed_lock_timer = 0.0
		p._dash_speed_lock_speed = 0.0
		p._automation_active = false
		p._automation_timer = 0.0
		p._automation_lock_movement = false
		p._automation_lock_actions = false
		p._automation_lock_drift = false
		p._automation_tangent_dir = Vector3.ZERO
		p._automation_toward_dir = Vector3.ZERO
		p._automation_toward_strength = 0.0
		p._automation_max_turn_deg_per_sec = 0.0
		p._automation_along_target_speed = 0.0
		p._automation_along_accel = 0.0
		p._automation_continuous_force = true
		p._automation_align_rotation = true
		p._automation_grounded_only = true
		p._automation_force_surface_adhesion = false
		p._automation_tangent_snap_strength = 0.0
		p._automation_along_assist_enabled = true
		p._automation_along_speed_limits_player = true
		p._automation_bidirectional_assist = false
		p._automation_mode = p.AutomationSplineMode.GUIDED
		p._automation_constraint_source = null
		p._automation_influence = 0.0
		p._automation_path_point = Vector3.ZERO
		p._automation_plane_normal = Vector3.ZERO
		p._automation_plane_up = Vector3.UP
		p._automation_input_mode = p.AutomationPlaneInputMode.PATH_HORIZONTAL
		p._automation_reverse_input = false
		p._automation_input_deadzone = 0.05
		p._automation_strict_position_lock = true
		p._automation_post_slide_constraint_pass_enabled = false
		p._automation_position_lock_strength = 12.0
		p._automation_max_position_correction_speed = 80.0
		p._automation_position_lock_deadzone = 0.005
		p._automation_strict_velocity_lock = true
		p._automation_disable_turning_slowdown = false
		p._automation_velocity_lock_strength = 18.0
		p._automation_sideways_speed_preservation = 0.0
		p._automation_constrain_special_moves = true
		p._automation_priority_current = -9999
		p._automation_priority_frame = -1

		_debug_refresh_animation_list()
	else:
		# Restore collisions and animation control.
		p.collision_layer = p._debug_saved_collision_layer
		p.collision_mask = p._debug_saved_collision_mask
		if p.anim_tree != null:
			p.anim_tree.active = p._debug_saved_anim_tree_active
		p._apply_grounded_after_debug_exit()


func _debug_refresh_animation_list() -> void:
	var p = _owner
	p._debug_anim_player = _find_animation_player()
	p._debug_anim_names = PackedStringArray()
	p._debug_anim_index = 0
	if p._debug_anim_player == null:
		return
	var list: PackedStringArray = p._debug_anim_player.get_animation_list()
	p._debug_anim_names = list


func _invalidate_race_ghost_recording() -> void:
	var p = _owner
	var tree: SceneTree = p.get_tree()
	if tree == null:
		return
	var race_starts = tree.get_nodes_in_group("RaceStart")
	for race_start in race_starts:
		if race_start != null and is_instance_valid(race_start) and race_start.has_method("invalidate_ghost_recording_for_player"):
			race_start.call("invalidate_ghost_recording_for_player", p)


func _report_race_debug_used_to_network_session() -> void:
	var p = _owner
	var tree: SceneTree = p.get_tree()
	if tree == null:
		return
	var sessions = tree.get_nodes_in_group("NetworkSession")
	for session in sessions:
		if session != null and is_instance_valid(session) and session.has_method("report_race_debug_used"):
			session.call("report_race_debug_used")
			return


func _debug_cycle_animation(step: int) -> void:
	var p = _owner
	if not p._debug_mode:
		if p._debug_online_puppet == null or not is_instance_valid(p._debug_online_puppet):
			return
		if _dummy_animation_player == null or not is_instance_valid(_dummy_animation_player) or _dummy_animation_names.is_empty():
			return
		if step == 0:
			return
		_dummy_animation_index = posmod(_dummy_animation_index + step, _dummy_animation_names.size())
		var dummy_name: StringName = _dummy_animation_names[_dummy_animation_index]
		if _dummy_animation_player.has_animation(dummy_name):
			_dummy_animation_player.play(dummy_name)
		return
	if p._debug_anim_player == null:
		_debug_refresh_animation_list()
	if p._debug_anim_player == null or p._debug_anim_names.is_empty():
		return
	var s: int = int(step)
	if s == 0:
		return
	p._debug_anim_index = (p._debug_anim_index + s) % p._debug_anim_names.size()
	if p._debug_anim_index < 0:
		p._debug_anim_index += p._debug_anim_names.size()
	var name: StringName = p._debug_anim_names[p._debug_anim_index]
	if p._debug_anim_player.has_animation(name):
		p._debug_anim_player.play(name)


func _find_animation_player() -> AnimationPlayer:
	var p = _owner
	if p.model_root != null:
		var n = p.model_root.find_child("AnimationPlayer", true, false)
		if n is AnimationPlayer:
			return n as AnimationPlayer
	var n2 = p.find_child("AnimationPlayer", true, false)
	return n2 as AnimationPlayer if n2 is AnimationPlayer else null


func _debug_fly_tick(delta: float) -> void:
	var p = _owner
	var up: Vector3 = p._get_gravity_up()

	var cam_basis: Basis = p.global_transform.basis
	if p.camera != null:
		cam_basis = p.camera.global_transform.basis
	elif p.camera_rig is Node3D:
		cam_basis = (p.camera_rig as Node3D).global_transform.basis

	var use_camera_direction: bool = false
	if p.camera_rig != null and p.camera_rig.has_method("get_player_up_toggle"):
		use_camera_direction = bool(p.camera_rig.call("get_player_up_toggle"))

	var forward: Vector3 = -cam_basis.z
	if not use_camera_direction:
		forward -= up * forward.dot(up)
	if forward.length() > 0.001:
		forward = forward.normalized()
	else:
		forward = -Vector3.FORWARD

	var right: Vector3 = cam_basis.x
	if not use_camera_direction:
		right -= up * right.dot(up)
	if right.length() > 0.001:
		right = right.normalized()
	else:
		right = Vector3.RIGHT

	var horiz: Vector3 = right * p._move_input.x + forward * p._move_input.y
	if horiz.length() > 1.0:
		horiz = horiz.normalized()

	var vert: float = 0.0
	if SettingsManager.is_gameplay_action_pressed("debug_fly_up"):
		vert += 1.0
	if SettingsManager.is_gameplay_action_pressed("debug_fly_down"):
		vert -= 1.0

	var speed_scale: float = 1.0
	if SettingsManager.is_gameplay_action_pressed("debug_fast"):
		speed_scale *= max(p.debug_fast_multiplier, 0.0)
	if SettingsManager.is_gameplay_action_pressed("debug_slow"):
		speed_scale *= max(p.debug_slow_multiplier, 0.0)
	if p._walk_input_held:
		speed_scale *= 0.2

	var move: Vector3 = horiz * (p.debug_move_speed * speed_scale) + up * (vert * p.debug_vertical_speed * speed_scale)
	p.global_position += move * max(delta, 0.0)

	p.velocity = Vector3.ZERO
	p.attached = false


func reload_player_scene_parameters() -> void:
	var p = _owner
	var scene_path: String = String(p.scene_file_path).strip_edges()
	if scene_path == "":
		push_warning("Player parameter reload failed: the player has no scene path.")
		return
	var scene_resource: Resource = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	if not (scene_resource is PackedScene):
		push_warning("Player parameter reload failed: %s is not a PackedScene." % scene_path)
		return
	var scene_instance: Node = (scene_resource as PackedScene).instantiate()
	if scene_instance == null:
		push_warning("Player parameter reload failed: %s could not be instantiated." % scene_path)
		return
	_copy_exported_scene_parameters(scene_instance, p, scene_instance, p)
	scene_instance.free()
	_reset_surface_preview_reload_state()
	if p.has_method("_reload_action_configuration_from_scene"):
		p.call("_reload_action_configuration_from_scene")
	if p.has_method("_reload_visual_configuration_from_scene"):
		p.call("_reload_visual_configuration_from_scene")
	if p.has_method("show_prompt"):
		p.call("show_prompt", "Player parameters reloaded", 2.0)


func _reset_surface_preview_reload_state() -> void:
	var p = _owner
	p._surface_preview_world_radius = 0.0
	p._surface_support_timer = 0.0
	p._surface_support_curvature = 0.0
	p._surface_support_reaction_accel = 0.0
	p._dbg_surface_preview_timer = 0.0
	p._dbg_surface_seam_timer = 0.0
	p._dbg_surface_preview_points.clear()
	p._dbg_surface_preview_normals.clear()
	p._dbg_surface_preview_centers.clear()


func _copy_exported_scene_parameters(source_node: Node, target_node: Node, source_root: Node, target_root: Node) -> void:
	if source_node.get_script() == target_node.get_script():
		_copy_exported_node_parameters(source_node, target_node)
	for source_child_node in source_node.get_children():
		var source_child: Node = source_child_node as Node
		if source_child == null:
			continue
		if source_node == source_root and not PARAMETER_RELOAD_CHILD_ROOTS.has(source_child.name):
			continue
		var child_path: NodePath = source_root.get_path_to(source_child)
		var target_child: Node = target_root.get_node_or_null(child_path)
		if target_child != null:
			_copy_exported_scene_parameters(source_child, target_child, source_root, target_root)


func _copy_exported_node_parameters(source_node: Node, target_node: Node) -> void:
	var p = _owner
	for property in source_node.get_property_list():
		var property_name: StringName = StringName(property.get("name", ""))
		if property_name == &"" or property_name == &"script":
			continue
		var usage: int = int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if not p._object_has_property(target_node, property_name):
			continue
		var source_value: Variant = source_node.get(property_name)
		var target_value: Variant = target_node.get(property_name)
		if source_value is Node or target_value is Node:
			continue
		target_node.set(property_name, source_value)


func _debug_inputs(physics_up: Vector3) -> void:
	var p = _owner
	if SettingsManager.is_gameplay_action_just_pressed("debug_add_up"):
		var up: Vector3 = physics_up.normalized()
		if up.length() < 0.001 or not p.debug_add_up_use_physics_up:
			up = p._get_gravity_up()

		var delta_v: Vector3 = up * p.debug_add_up_speed
		p.velocity += delta_v

		print("DEBUG: +up velocity ", delta_v, " | new velocity = ", p.velocity)


func _debug_draw() -> void:
	var p = _owner
	if is_instance_valid(p._debug_label) and (not p._debug_visible or not p.debug_show_extended_details):
		p._debug_label.text = ""
	var up: Vector3 = p.visual_up.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var origin: Vector3 = p.global_transform.origin + up * 0.5

	#DebugDraw3d.arrow(origin, origin + surface_normal, Color(1.0, 0.0, 0.0, 1.0))
	#DebugDraw3d.arrow(origin, origin + _prev_surface_normal, Color(1.0, 0.5, 0.0, 1.0))
	#DebugDraw3d.arrow(origin, origin + visual_up, Color(0.0, 1.0, 0.0, 1.0))
	#DebugDraw3d.arrow(origin, origin + velocity * 0.1, Color(0.0, 0.5, 1.0, 1.0))

	if p._debug_visible and p._rail_active and p._rail_switch_candidate != null:
		var candidate_color: Color = Color(1.0, 0.8, 0.0, 1.0)
		DebugDraw3d.line(origin, p._rail_switch_candidate_point, candidate_color)
		if p._rail_switch_candidate_tangent.length() > 0.001:
			var cand_dir: Vector3 = p._rail_switch_candidate_tangent.normalized()
			DebugDraw3d.arrow(p._rail_switch_candidate_point, p._rail_switch_candidate_point + cand_dir, candidate_color)

	if p._debug_visible:
		_debug_draw_drift_guides(origin, up)
		_debug_draw_movement_correction()
		_debug_draw_wall_input_projection(origin, up)
		_debug_draw_surface_preview()
		_debug_draw_surface_seam_bridge()
		_debug_draw_ledge_mantle_probes(up)
	_update_debug_hud(up)

	if not p.control_anchor:
		return

	var f: Vector3 = -p.control_anchor.global_transform.basis.z
	var u: Vector3 = p.control_anchor.global_transform.basis.y

	var forward_angle: float = rad_to_deg(atan2(f.x, f.z))
	var up_pitch: float = rad_to_deg(acos(clamp(p._get_gravity_up().dot(u), -1.0, 1.0)))

	var msg: String = "ForwardYaw = %.2f°\nUpTilt = %.2f°" % [forward_angle, up_pitch]

	if p.camera != null:
		var cam_forward: Vector3 = -p.camera.global_transform.basis.z
		#DebugDraw3d.arrow(origin, origin + cam_forward, Color(1.0, 1.0, 0.0, 1.0))

	if p.model_root != null:
		var model_basis: Basis = p.model_root.global_transform.basis
		var model_forward: Vector3 = -model_basis.z
		var model_origin: Vector3 = p.model_root.global_transform.origin + up * 0.5
		#DebugDraw3d.arrow(model_origin, model_origin + model_forward, Color(1.0, 0.0, 1.0, 1.0))

	#if _follow_ray_origin != _follow_ray_target:
		#DebugDraw3d.line(_follow_ray_origin, _follow_ray_target, Color(0.0, 1.0, 1.0, 1.0))

	if p._debug_label != null and p._debug_visible and p.debug_show_extended_details:
		var state_str: String = "ATTACHED"
		if not p.attached:
			state_str = "AIRBORNE"
		elif p._is_skidding:
			state_str = "SKID"

		var spd: float = p.velocity.length()

		# Show “YES” only while the timer > 0
		var radial_str: String = "YES" if p._dbg_radial_hit_timer > 0.0 else "no"

		# Detach info only while timer > 0
		var detach_str: String = "RECENT" if p._dbg_detach_timer > 0.0 else "none"
		var filtered_str: String = "YES" if p._dbg_last_detach_used_filtered else "no"
		var from_floor_str: String = "YES" if p._dbg_last_detach_from_floor_like else "no"
		var coyote_eligible_str: String = "YES" if p._dbg_last_detach_coyote_eligible else "no"
		var surf_kind_str: String = "FLOOR" if p._dbg_surface_is_floor_like else "NON-FLOOR"

		var legacy_text: String = ""
		legacy_text += "STATE: %s\n" % state_str
		var ability_str: String = "none"
		if p._current_action_id != &"":
			ability_str = String(p._current_action_id)
		var attacking_str: String = "YES" if p.is_attack_active() else "no"
		legacy_text += "ABILITY: %s  ATTACKING: %s\n" % [ability_str, attacking_str]
		legacy_text += "SPD:   %.1f\n" % spd
		legacy_text += "NΔ:    %.1f°\n" % p._normal_delta_angle_deg
		legacy_text += "\n"

		legacy_text += "SURF ANGLE: %.1f°  (%s)\n" % [
			p._dbg_surface_angle_deg,
			surf_kind_str
		]
		
		legacy_text += "\n"

		legacy_text += "--- RADIAL ---\n"
		legacy_text += "Hit:   %s\n" % radial_str
		legacy_text += "Result: %s\n" % p._dbg_radial_result
		legacy_text += "Impact: %.1f°\n" % p._dbg_radial_angle
		legacy_text += "Approach: %.1f°\n" % (90.0 - p._dbg_radial_angle)
		legacy_text += "Into:  %.1f\n" % p._dbg_radial_into_speed
		legacy_text += "Tang:  %.1f\n" % p._dbg_radial_tangent_speed
		if p._dbg_surface_preview_timer > 0.0:
			var preview_state: String = "PASS" if p._dbg_surface_preview_accepted else "FAIL"
			legacy_text += "Preview: %s  cov=%.0f%%\n" % [
				preview_state,
				p._dbg_surface_preview_coverage * 100.0
			]
			legacy_text += "Radius: %.2f  look=%.2f\n" % [
				p._dbg_surface_preview_radius,
				p._dbg_surface_preview_lookahead
			]
			legacy_text += "Turn: +%.1f / -%.1f  step=%.1f\n" % [
				p._dbg_surface_preview_total_turn_deg,
				p._dbg_surface_preview_reverse_turn_deg,
				p._dbg_surface_preview_max_step_deg
			]
			legacy_text += "CurveR: %.2f  k=%.4f  force=%.2f\n" % [
				p._dbg_surface_preview_min_radius,
				p._dbg_surface_preview_curvature,
				p._dbg_surface_preview_reaction_accel
			]
			legacy_text += "Collider seams: %d\n" % p._dbg_surface_preview_collider_transitions
		if p._dbg_surface_seam_timer > 0.0:
			legacy_text += "Seam recovery: ACTIVE\n"
		legacy_text += "\n"
		
		legacy_text += "Adhesion: tan=%.1f  req=%.1f\n" % [
			p._dbg_current_adhesion_speed,
			p._dbg_required_adhesion_speed
		]
		legacy_text += "Contact: k=%.4f  force=%.2f  grace=%.3f\n" % [
			p._surface_support_curvature,
			p._surface_support_reaction_accel,
			p._surface_support_timer
		]

		legacy_text += "\n"

		legacy_text += "--- DETACH ---\n"
		legacy_text += "Recent:   %s\n" % detach_str
		legacy_text += "FromFloor:%s\n" % from_floor_str
		legacy_text += "Coyote:   %s\n" % coyote_eligible_str
		legacy_text += "WorldAng: %.1f°\n" % p._dbg_last_detach_world_angle
		legacy_text += "StepAng:  %.1f°\n" % p._dbg_last_detach_step_angle
		legacy_text += "Filtered: %s\n" % filtered_str

		legacy_text += "\n"
		legacy_text += "--- DETACH CTRL ---\n"
		var lock_str: String = "YES" if p._directional_influence_lock_strength > 0.0 else "no"
		legacy_text += "Active: %s  SpdT: %.2f\n" % [
			lock_str,
			p._directional_influence_lock_speed_t
		]
		legacy_text += "Str: A %.2f  T %.2f  P %.2f\n" % [
			p._directional_influence_lock_accel_strength,
			p._directional_influence_lock_turn_strength,
			p._directional_influence_lock_air_turn_penalty_strength
		]
		legacy_text += "Mul: A %.2f  T %.2f  P %.2f\n" % [
			p._directional_influence_lock_accel_multiplier,
			p._directional_influence_lock_turn_multiplier,
			p._directional_influence_lock_air_turn_penalty_multiplier
		]
		legacy_text += "Delay: A %.2f  T %.2f  P %.2f\n" % [
			p._directional_influence_lock_accel_delay_timer,
			p._directional_influence_lock_turn_delay_timer,
			p._directional_influence_lock_air_turn_penalty_delay_timer
		]

		legacy_text += "\n"

		legacy_text += "--- VISUAL ROT ---\n"
		var vis_up: Vector3 = p.visual_up.normalized()
		if vis_up.length() < 0.001:
			vis_up = p._get_gravity_up()
		legacy_text += "VisUp:   (%.2f, %.2f, %.2f)\n" % [vis_up.x, vis_up.y, vis_up.z]

		var model_fwd: Vector3 = p._model_forward
		legacy_text += "ModelF:  (%.2f, %.2f, %.2f)\n" % [model_fwd.x, model_fwd.y, model_fwd.z]

		var yaw_ref: Vector3 = p._air_torque_yaw_forward
		legacy_text += "YawRef:  (%.2f, %.2f, %.2f)\n" % [yaw_ref.x, yaw_ref.y, yaw_ref.z]

		var yaw_vis: Vector3 = p._air_torque_visual_forward
		legacy_text += "YawVis:  (%.2f, %.2f, %.2f)\n" % [yaw_vis.x, yaw_vis.y, yaw_vis.z]

		var land_align_str: String = "no"
		if p._air_landing_align_active:
			land_align_str = "YES"
		legacy_text += "LandAlign: %s  ramp=%.2f  t=%.2f\n" % [
			land_align_str,
			p._air_landing_align_ramp,
			p._air_landing_align_time_to_impact
		]
		if p._air_landing_align_active:
			var land_n: Vector3 = p._air_landing_align_normal
			legacy_text += "LandN:  (%.2f, %.2f, %.2f)\n" % [
				land_n.x,
				land_n.y,
				land_n.z
			]

		legacy_text += "\n"
		legacy_text += "--- AIR TORQUE ---\n"
		legacy_text += "NΔ: %.2f°  Mem: %.3f\n" % [
			p._dbg_air_torque_normal_angle_deg,
			p._airborne_torque_yaw_turn_speed_memory_timer
		]
		legacy_text += "Axis: (%.2f, %.2f, %.2f)\n" % [
			p._dbg_air_torque_axis.x,
			p._dbg_air_torque_axis.y,
			p._dbg_air_torque_axis.z
		]
		legacy_text += "Move: (%.2f, %.2f, %.2f)\n" % [
			p._dbg_air_torque_move_dir.x,
			p._dbg_air_torque_move_dir.y,
			p._dbg_air_torque_move_dir.z
		]
		legacy_text += "SurfΩ: %.1f  YawΩ: %.1f  AvgΩ: %.1f\n" % [
			rad_to_deg(p._dbg_air_torque_surface_omega.length()),
			rad_to_deg(p._dbg_air_torque_yaw_omega.length()),
			rad_to_deg(p._dbg_air_torque_avg_omega.length())
		]
		legacy_text += "SeedΩ: %.1f  LiveΩ: %.1f\n" % [
			rad_to_deg(p._dbg_air_torque_seed_omega.length()),
			rad_to_deg(p._air_torque_angular_velocity.length())
		]

		if p.model_root != null:
			var model_basis: Basis = p.model_root.global_transform.basis
			var model_up: Vector3 = model_basis.y
			var model_euler: Vector3 = model_basis.get_euler()
			var model_pitch_deg: float = rad_to_deg(model_euler.x)
			var model_yaw_deg: float = rad_to_deg(model_euler.y)
			var model_roll_deg: float = rad_to_deg(model_euler.z)
			legacy_text += "ModelUp: (%.2f, %.2f, %.2f)\n" % [
				model_up.x,
				model_up.y,
				model_up.z
			]
			legacy_text += "Euler(P/Y/R): %.1f / %.1f / %.1f\n" % [
				model_pitch_deg,
				model_yaw_deg,
				model_roll_deg
			]
		
		legacy_text += "Attached: " + str(p.attached)

		legacy_text += "\n--- WATER ---\n"
		var water_state_str: String = "none"
		if p._running_on_water_surface:
			water_state_str = "SURFACE"
		elif p._fully_submerged:
			water_state_str = "SUBMERGED"
		elif p._in_water_volume:
			water_state_str = "PARTIAL"
		legacy_text += "State:  %s (body:%s head:%s)\n" % [water_state_str, p._in_water_volume, p._head_in_water_volume]
		legacy_text += "FullSub: %s  Cooldown: %.2f\n" % [p._fully_submerged, p._water_reattach_cooldown_timer]
		legacy_text += "FootstepTimer: %.2f / %.2f\n" % [p._water_footstep_timer, p.water_footstep_max_time]
		legacy_text += "Enabled: %s\n" % p.water_physics_enabled

		legacy_text += "\n--- FOOTSTEP ---\n"
		if p._audio_module != null:
			p._debug_surface_probe_timer = max(p._debug_surface_probe_timer - p.get_process_delta_time(), 0.0)
			if p._debug_surface_probe_timer <= 0.0:
				p._audio_module.debug_update_surface_probe(p.ground_ray)
				p._debug_surface_probe_timer = 0.2
			legacy_text += "Surface: %s\n" % p._audio_module._dbg_last_surface_type
			legacy_text += "Name:    %s\n" % (p._audio_module._dbg_last_surface_name if p._audio_module._dbg_last_surface_name != "" else "(none)")
			legacy_text += "Checked: %s\n" % (p._audio_module._dbg_last_surface_candidates if p._audio_module._dbg_last_surface_candidates != "" else "(none)")
		else:
			legacy_text += "Audio module missing\n"

		if p.anim_state != null:
			legacy_text += "\nANIM STATE: %s\n" % str(p.anim_state.get_current_node())
			legacy_text += "ANIM POS:   %.3f / %.3f\n" % [
				p.anim_state.get_current_play_position(),
				p.anim_state.get_current_length()
			]
			if p.anim_tree != null:
				legacy_text += "ANIM SCALE:%s\n" % str(p.anim_tree.get("parameters/MoveTimeScale/scale"))
				if p._rail_active and p._anim_param_exists("parameters/StateMachine/RAIL/blend_position"):
					legacy_text += "RAIL BLEND:%s\n" % str(
						p.anim_tree.get("parameters/StateMachine/RAIL/blend_position")
					)
		p._debug_label.text = _format_debug_columns(legacy_text + _build_online_debug_text())


func _build_online_debug_text() -> String:
	var p: Node = _owner
	var session_active: bool = p.multiplayer != null and p.multiplayer.has_multiplayer_peer()
	var session_id: int = p.multiplayer.get_unique_id() if session_active else 0
	var lines: PackedStringArray = PackedStringArray([
		"", "[ONLINE / UI]",
		"Session Active: %s (ID: %d)" % [session_active, session_id],
		"Local Auth: %s" % p._network_is_local_authority(),
		"UI Blocked: %s" % p._ui_input_blocked,
		"Camera Rig: %s" % (p.camera_rig != null),
	])
	if is_instance_valid(p.camera_rig) and p.camera_rig.has_method("is_constraint_active"):
		lines.append("Cam Constraint: %s" % p.camera_rig.is_constraint_active())
	return "\n".join(lines) + "\n"


func _update_debug_hud(gravity_up: Vector3) -> void:
	var p = _owner
	if p._debug_hud == null or not is_instance_valid(p._debug_hud):
		return
	if not p._debug_hud.has_method("update_sections"):
		return
	if not p._debug_visible:
		p._debug_hud.visible = false
		return
	var ledge_snapshot: Dictionary = _get_ledge_mantle_debug_snapshot()
	var parkour_snapshot: Dictionary = _get_parkour_debug_snapshot()
	var status: StringName = _get_debug_hud_status(ledge_snapshot)
	var data: Dictionary = {
		"visible": p._debug_visible,
		"status": status,
		"overview": _build_overview_debug_text(gravity_up),
		"movement": _build_movement_debug_text(gravity_up, parkour_snapshot),
		"surface": _build_surface_debug_text(),
		"ledge": _build_ledge_debug_text(ledge_snapshot),
		"show_extended": p.debug_show_extended_details,
	}
	p._debug_hud.call("update_sections", data)


func _get_ledge_mantle_debug_snapshot() -> Dictionary:
	var p = _owner
	for action_value in p._actions:
		var action: Node = action_value as Node
		if action == null or not is_instance_valid(action):
			continue
		if not action.has_method("get_ledge_mantle_debug_snapshot"):
			continue
		var snapshot_value: Variant = action.call("get_ledge_mantle_debug_snapshot")
		if snapshot_value is Dictionary:
			return snapshot_value
	return {}


func _get_parkour_debug_snapshot() -> Dictionary:
	var p = _owner
	for action_value in p._actions:
		var action: Node = action_value as Node
		if action == null or not is_instance_valid(action):
			continue
		if not action.has_method("get_parkour_debug_snapshot"):
			continue
		var snapshot_value: Variant = action.call("get_parkour_debug_snapshot")
		if snapshot_value is Dictionary:
			return snapshot_value
	return {}


func _get_debug_hud_status(ledge_snapshot: Dictionary) -> StringName:
	if bool(ledge_snapshot.get("active", false)):
		return &"ACTIVE"
	if bool(ledge_snapshot.get("attempting", false)):
		return &"PROBING"
	var input_strength: float = float(ledge_snapshot.get("input_strength", 0.0))
	var minimum_input_strength: float = float(ledge_snapshot.get("minimum_input_strength", 0.0))
	var blocking_threshold: float = max(minimum_input_strength, 0.01)
	var rejection: StringName = StringName(ledge_snapshot.get("rejection", &""))
	if input_strength >= blocking_threshold and rejection != &"":
		return &"BLOCKED"
	return &"IDLE"


func _build_overview_debug_text(gravity_up: Vector3) -> String:
	var p = _owner
	var state: String = "ATTACHED" if p.attached else "AIRBORNE"
	if p._is_skidding:
		state = "SKID"
	var action: String = String(p._current_action_id) if p._current_action_id != &"" else "none"
	var vertical_speed: float = p.velocity.dot(gravity_up)
	var planar_velocity: Vector3 = p.velocity - gravity_up * vertical_speed
	return "\n".join(PackedStringArray([
		"State       %s" % state,
		"Action      %s" % action,
		"Attacking   %s" % _debug_yes_no(p.is_attack_active()),
		"Speed       %7.2f" % p.velocity.length(),
		"Planar      %7.2f" % planar_velocity.length(),
		"Vertical    %+7.2f" % vertical_speed,
	]))


func _build_movement_debug_text(gravity_up: Vector3, parkour_snapshot: Dictionary) -> String:
	var p = _owner
	var roll_bonus: String = "none"
	if bool(parkour_snapshot.get("landing_roll_performed", false)):
		roll_bonus = _debug_yes_no(bool(parkour_snapshot.get("landing_roll_speed_benefit", false)))
	return "\n".join(PackedStringArray([
		"Input       (%+.2f, %+.2f)  %.2f" % [p._move_input.x, p._move_input.y, p._move_input.length()],
		"Velocity    (%+.1f, %+.1f, %+.1f)" % [p.velocity.x, p.velocity.y, p.velocity.z],
		"Move dir    (%+.2f, %+.2f, %+.2f)" % [p._move_direction.x, p._move_direction.y, p._move_direction.z],
		"Gravity up  (%+.2f, %+.2f, %+.2f)" % [gravity_up.x, gravity_up.y, gravity_up.z],
		"Wall push   %s" % _debug_yes_no(p._wall_input_push_active),
		"Projection  %s" % _debug_yes_no(p._wall_input_projection_active),
		"Wall lift   %s  %.2f / %.2f" % [
			String(parkour_snapshot.get("wall_lift_phase", "NONE")),
			float(parkour_snapshot.get("wall_lift_hold_remaining", 0.0)),
			float(parkour_snapshot.get("wall_lift_hold_duration", 0.0)),
		],
		"Lift power  %.2f  gravity x%.2f  entry %.1f  settle %.2f / %.2f" % [
			float(parkour_snapshot.get("wall_lift_strength", 1.0)),
			float(parkour_snapshot.get("wall_lift_gravity_scale", 1.0)),
			float(parkour_snapshot.get("wall_lift_effective_entry_speed", 0.0)),
			float(parkour_snapshot.get("wall_lift_settle_elapsed", 0.0)),
			float(parkour_snapshot.get("wall_lift_settle_limit", 0.0)),
		],
		"Lift turn   %.1f°  %s" % [
			float(parkour_snapshot.get("wall_lift_inward_turn", 0.0)),
			String(parkour_snapshot.get("wall_lift_last_refresh_reason", &"")),
		],
		"Lift carry  +%.2f" % float(parkour_snapshot.get("wall_lift_entry_parallel_gain", 0.0)),
		"Roll bonus  %s  +%.2f" % [
			roll_bonus,
			float(parkour_snapshot.get("landing_roll_recovered_speed", 0.0)),
		],
		"Roll result %s" % String(parkour_snapshot.get("landing_roll_rejection_reason", &"")),
		"Roll strength %.2f x%.2f  cap %.1f" % [
			float(parkour_snapshot.get("landing_roll_recovery_strength", 0.0)),
			float(parkour_snapshot.get("landing_roll_effectiveness_multiplier", 1.0)),
			float(parkour_snapshot.get("landing_roll_recovery_limit", 0.0)),
		],
		"Roll tangent %.2f" % float(parkour_snapshot.get("landing_roll_tangential_speed", 0.0)),
		"Roll air     %.2f / %.2f  required %s" % [
			float(parkour_snapshot.get("landing_roll_airborne_time", 0.0)),
			float(parkour_snapshot.get("landing_roll_min_airborne_time", 0.0)),
			_debug_yes_no(bool(parkour_snapshot.get("landing_roll_airborne_time_required", false))),
		],
		"Roll cooldown %.2f / %.2f" % [
			float(parkour_snapshot.get("landing_roll_speed_benefit_cooldown", 0.0)),
			float(parkour_snapshot.get("landing_roll_speed_benefit_cooldown_duration", 0.0)),
		],
	]))


func _build_surface_debug_text() -> String:
	var p = _owner
	var surface_kind: String = "FLOOR" if p._dbg_surface_is_floor_like else "NON-FLOOR"
	var water_state: String = "none"
	if p._running_on_water_surface:
		water_state = "surface"
	elif p._fully_submerged:
		water_state = "submerged"
	elif p._in_water_volume:
		water_state = "partial"
	return "\n".join(PackedStringArray([
		"Attached    %s" % _debug_yes_no(p.attached),
		"Angle       %6.2f°  %s" % [p._dbg_surface_angle_deg, surface_kind],
		"Normal Δ    %6.2f°" % p._normal_delta_angle_deg,
		"Adhesion    %6.2f / %6.2f" % [p._dbg_current_adhesion_speed, p._dbg_required_adhesion_speed],
		"Support     k %.4f  force %.2f" % [p._surface_support_curvature, p._surface_support_reaction_accel],
		"Water       %s" % water_state,
	]))


func _build_ledge_debug_text(snapshot: Dictionary) -> String:
	if snapshot.is_empty() or not bool(snapshot.get("available", false)):
		return "Ability not assigned"
	var rejection: String = String(snapshot.get("rejection", &""))
	if rejection == "":
		rejection = "none"
	var wall_state: String = "FOUND" if bool(snapshot.get("wall_detected", false)) else "none"
	var top_state: String = "FOUND" if bool(snapshot.get("upper_surface_detected", false)) else "none"
	return "\n".join(PackedStringArray([
		"Enabled     %s   Active %s" % [
			_debug_yes_no(bool(snapshot.get("enabled", false))),
			_debug_yes_no(bool(snapshot.get("active", false))),
		],
		"Attempting  %s   Last %s" % [
			_debug_yes_no(bool(snapshot.get("attempting", false))),
			rejection,
		],
		"Input       %.2f   Into wall %.2f" % [
			float(snapshot.get("input_strength", 0.0)),
			float(snapshot.get("input_toward_wall", 0.0)),
		],
		"Wall        %s   angle %.1f°" % [wall_state, float(snapshot.get("wall_angle_deg", 0.0))],
		"Upper       %s   h %.2f  angle %.1f°" % [
			top_state,
			float(snapshot.get("upper_surface_height", 0.0)),
			float(snapshot.get("upper_surface_angle_deg", 0.0)),
		],
		"Top probes  %d   hits %d  %s" % [
			int(snapshot.get("top_probe_rays", 0)),
			int(snapshot.get("top_probe_hits", 0)),
			String(snapshot.get("top_probe_result", &"not_tested")),
		],
		"Clearance   catch %s  mantle %s" % [
			_debug_yes_no(bool(snapshot.get("catch_position_clear", false))),
			_debug_yes_no(bool(snapshot.get("mantle_space_clear", false))),
		],
		"Vertical    %+.2f   fall limit %.1f" % [
			float(snapshot.get("vertical_speed", 0.0)),
			float(snapshot.get("fall_speed_limit", 0.0)),
		],
		"Hold        %.2f / %.2f   cooldown %.2f" % [
			float(snapshot.get("hold_elapsed", 0.0)),
			float(snapshot.get("hold_duration", 0.0)),
			float(snapshot.get("regrab_cooldown", 0.0)),
		],
	]))


func _debug_yes_no(value: bool) -> String:
	return "YES" if value else "no"


func _debug_draw_ledge_mantle_probes(gravity_up: Vector3) -> void:
	var p = _owner
	for action_value in p._actions:
		var action: Node = action_value as Node
		if action == null or not is_instance_valid(action):
			continue
		if not action.has_method("debug_draw_ledge_mantle_probes"):
			continue
		action.call("debug_draw_ledge_mantle_probes", gravity_up)
		return


func _debug_draw_surface_preview() -> void:
	var p = _owner
	if p._dbg_surface_preview_timer <= 0.0:
		return
	if p._dbg_surface_preview_points.is_empty():
		return

	var result_color: Color = Color(0.15, 1.0, 0.25, 1.0) if p._dbg_surface_preview_accepted else Color(1.0, 0.15, 0.1, 1.0)
	var center_color: Color = Color(0.1, 0.85, 1.0, 1.0)
	var probe_color: Color = Color(1.0, 0.75, 0.15, 1.0)
	var normal_color: Color = Color(0.75, 0.25, 1.0, 1.0)
	var point_count: int = p._dbg_surface_preview_points.size()
	var center_count: int = p._dbg_surface_preview_centers.size()
	var normal_count: int = p._dbg_surface_preview_normals.size()
	var sample_count: int = min(point_count, min(center_count, normal_count))
	var normal_length: float = max(p._dbg_surface_preview_radius * 0.65, 0.25)

	for index: int in range(sample_count):
		var contact_point: Vector3 = p._dbg_surface_preview_points[index]
		var center_point: Vector3 = p._dbg_surface_preview_centers[index]
		var normal: Vector3 = p._dbg_surface_preview_normals[index].normalized()
		DebugDraw3d.line(center_point, contact_point, probe_color)
		DebugDraw3d.arrow(contact_point, contact_point + normal * normal_length, normal_color)
		if index > 0:
			DebugDraw3d.line(p._dbg_surface_preview_points[index - 1], contact_point, result_color)
			DebugDraw3d.line(p._dbg_surface_preview_centers[index - 1], center_point, center_color)

	var start_point: Vector3 = p._dbg_surface_preview_points[0]
	var cross_size: float = max(p._dbg_surface_preview_radius * 0.15, 0.08)
	DebugDraw3d.line(start_point - Vector3.RIGHT * cross_size, start_point + Vector3.RIGHT * cross_size, result_color)
	DebugDraw3d.line(start_point - Vector3.UP * cross_size, start_point + Vector3.UP * cross_size, result_color)
	DebugDraw3d.line(start_point - Vector3.FORWARD * cross_size, start_point + Vector3.FORWARD * cross_size, result_color)
	if p._dbg_surface_preview_tangent.length() > 0.001:
		DebugDraw3d.arrow(
			start_point,
			start_point + p._dbg_surface_preview_tangent.normalized() * normal_length * 1.5,
			Color(0.2, 0.45, 1.0, 1.0)
		)


func _debug_draw_surface_seam_bridge() -> void:
	var p = _owner
	if p._dbg_surface_seam_timer <= 0.0:
		return
	var seam_color: Color = Color(1.0, 0.45, 0.05, 1.0)
	var normal_length: float = max(p._surface_preview_world_radius * 0.65, 0.25)
	DebugDraw3d.line(p._dbg_surface_seam_from, p._dbg_surface_seam_to, seam_color)
	if p._dbg_surface_seam_normal.length() > 0.001:
		DebugDraw3d.arrow(
			p._dbg_surface_seam_to,
			p._dbg_surface_seam_to + p._dbg_surface_seam_normal.normalized() * normal_length,
			seam_color
		)


func _debug_draw_drift_guides(origin: Vector3, up: Vector3) -> void:
	var p = _owner
	if not p.drift_debug_guides_enabled:
		return
	if not p._drift_active:
		return
	var guide_length: float = max(p.drift_debug_guide_length, 0.1)
	var guide_up: Vector3 = up.normalized()
	if guide_up.length() < 0.001:
		guide_up = p._get_gravity_up()

	var lateral: Vector3 = p.velocity - guide_up * p.velocity.dot(guide_up)
	if lateral.length() < 0.001:
		lateral = p._model_forward - guide_up * p._model_forward.dot(guide_up)
	if lateral.length() < 0.001:
		return
	var forward_dir: Vector3 = lateral.normalized()
	var side_value: float = clamp(p._drift_direction_value, -1.0, 1.0)
	var committed_dir: Vector3 = forward_dir.rotated(guide_up, deg_to_rad(35.0) * side_value).normalized()
	var counter_side: int = -p._drift_direction
	var counter_dir: Vector3 = forward_dir
	if counter_side != 0:
		counter_dir = forward_dir.rotated(guide_up, deg_to_rad(35.0) * float(counter_side)).normalized()

	DebugDraw3d.arrow(origin, origin + forward_dir * guide_length, Color(0.0, 0.8, 1.0, 1.0))
	DebugDraw3d.arrow(origin + guide_up * 0.2, origin + guide_up * 0.2 + committed_dir * guide_length * 0.85, Color(0.2, 1.0, 0.25, 1.0))
	DebugDraw3d.arrow(origin + guide_up * 0.4, origin + guide_up * 0.4 + counter_dir * guide_length * 0.65, Color(1.0, 0.45, 0.1, 1.0))

	var preview_turn_deg: float = p._drift_turn_deg_per_sec_current
	if abs(preview_turn_deg) < 0.001:
		preview_turn_deg = p.drift_base_turn_deg_per_sec * side_value
	var total_rad: float = deg_to_rad(preview_turn_deg) * 0.75
	var segments: int = max(p.drift_debug_arc_segments, 1)
	var previous_point: Vector3 = origin + forward_dir * guide_length * 0.75
	for i in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		var arc_dir: Vector3 = forward_dir.rotated(guide_up, total_rad * t).normalized()
		var next_point: Vector3 = origin + arc_dir * guide_length * 0.75
		DebugDraw3d.line(previous_point, next_point, Color(1.0, 0.9, 0.1, 1.0))
		previous_point = next_point

	var right_dir: Vector3 = forward_dir.cross(guide_up)
	if right_dir.length() < 0.001:
		return
	right_dir = right_dir.normalized()
	var reward_t: float = clamp(p._drift_reward_progress, 0.0, 1.0)
	var reward_origin: Vector3 = origin - right_dir * guide_length * 0.5 + guide_up * 0.6
	var reward_end: Vector3 = reward_origin + right_dir * guide_length * reward_t
	DebugDraw3d.line(reward_origin, reward_origin + right_dir * guide_length, Color(0.25, 0.25, 0.25, 1.0))
	DebugDraw3d.line(reward_origin, reward_end, Color(1.0, 0.85, 0.05, 1.0))


func _debug_draw_movement_correction() -> void:
	var p = _owner
	if not p.movement_correction_debug_guides_enabled:
		return
	for ray_data: Dictionary in p._movement_correction_debug_rays:
		var from_position: Vector3 = ray_data.get("from", Vector3.ZERO)
		var to_position: Vector3 = ray_data.get("to", Vector3.ZERO)
		var hit: bool = bool(ray_data.get("hit", false))
		var kind: StringName = StringName(ray_data.get("kind", &"terrain"))
		var color: Color = Color(0.2, 0.75, 1.0, 1.0)
		if kind == &"surface":
			color = Color(0.85, 0.3, 1.0, 1.0)
		elif kind == &"ledge":
			color = Color(1.0, 0.75, 0.15, 1.0)
		if hit:
			color = color.lightened(0.25)
		DebugDraw3d.line(from_position, to_position, color)
	var push: Vector3 = p._movement_correction_debug_push
	if push.length() > 0.001:
		var push_origin: Vector3 = p._movement_correction_debug_origin
		DebugDraw3d.arrow(push_origin, push_origin + push * 3.0, Color(0.15, 1.0, 0.35, 1.0))


func _debug_draw_wall_input_projection(origin: Vector3, up: Vector3) -> void:
	var p = _owner
	if not p._wall_input_projection_active and not p._wall_input_push_active:
		return
	if p._wall_input_debug_normal.length() < 0.001:
		return

	var guide_up: Vector3 = up.normalized()
	if guide_up.length() < 0.001:
		guide_up = p._get_gravity_up()

	var guide_origin: Vector3 = origin + guide_up * 0.35
	var guide_length: float = 1.25
	var raw_dir: Vector3 = p._wall_input_debug_raw_dir
	var projected_dir: Vector3 = p._wall_input_debug_projected_dir
	var normal_dir: Vector3 = p._wall_input_debug_normal

	if raw_dir.length() > 0.001:
		raw_dir = raw_dir.normalized()
		DebugDraw3d.arrow(guide_origin, guide_origin + raw_dir * guide_length, Color(1.0, 0.35, 0.1, 1.0))
	if projected_dir.length() > 0.001:
		projected_dir = projected_dir.normalized()
		var projected_origin: Vector3 = guide_origin + guide_up * 0.18
		DebugDraw3d.arrow(projected_origin, projected_origin + projected_dir * guide_length, Color(0.1, 0.9, 1.0, 1.0))
	if normal_dir.length() > 0.001:
		normal_dir = normal_dir.normalized()
		var normal_origin: Vector3 = guide_origin + guide_up * 0.36
		DebugDraw3d.arrow(normal_origin, normal_origin + normal_dir * 0.75, Color(1.0, 0.1, 0.25, 1.0))


func _format_debug_columns(raw_text: String) -> String:
	var p = _owner
	var viewport_size: Vector2 = p.get_viewport().get_visible_rect().size
	var font_size: int = p._debug_label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = 14
	var line_height: int = max(font_size + 2, 10)
	var max_lines: int = max(int((viewport_size.y - 20.0) / float(line_height)), 8)
	var raw_lines: PackedStringArray = raw_text.split("\n")
	if raw_lines.size() <= max_lines:
		return raw_text

	var columns: Array[PackedStringArray] = []
	var index: int = 0
	while index < raw_lines.size():
		var column: PackedStringArray = PackedStringArray()
		for _i in range(max_lines):
			if index >= raw_lines.size():
				break
			column.append(raw_lines[index])
			index += 1
		columns.append(column)

	var widths: Array[int] = []
	for column in columns:
		var width: int = 0
		for line in column:
			width = max(width, line.length())
		widths.append(width)

	var formatted_lines: PackedStringArray = PackedStringArray()
	for row in range(max_lines):
		var line_parts: PackedStringArray = PackedStringArray()
		for col in range(columns.size()):
			var text: String = ""
			if row < columns[col].size():
				text = columns[col][row]
			if col < columns.size() - 1:
				text = text.rpad(widths[col] + 6)
			line_parts.append(text)
		formatted_lines.append("".join(line_parts).rstrip(" "))

	return "\n".join(formatted_lines)


func _debug_draw_control_anchor() -> void:
	var p = _owner
	if not p._debug_visible or p._debug_label == null:
		return
	if not p.control_anchor:
		return

	var origin: Vector3 = p.control_anchor.global_position

	# Forward (-Z)  → BLUE
	var f: Vector3 = -p.control_anchor.global_transform.basis.z * 1.5
	# Right (+X)    → RED
	var r: Vector3 = p.control_anchor.global_transform.basis.x * 1.5
	# Up (+Y)       → GREEN
	var u: Vector3 = p.control_anchor.global_transform.basis.y * 1.5

	DebugDraw3d.arrow(origin, origin + f, Color.CORAL)
	DebugDraw3d.arrow(origin, origin + r, Color.RED)
	DebugDraw3d.arrow(origin, origin + u, Color.GREEN)


func _debug_anim_tree_params() -> void:
	var p = _owner
	p._ensure_modules()
	if p._anim_module != null:
		p._anim_module._debug_anim_tree_params()


func _dump_animtree_params() -> void:
	var p = _owner
	p._ensure_modules()
	if p._anim_module != null:
		p._anim_module._dump_animtree_params()

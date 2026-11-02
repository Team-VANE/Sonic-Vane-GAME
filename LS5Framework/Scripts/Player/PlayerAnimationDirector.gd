extends RefCounted
class_name PlayerAnimationDirector

signal request_dispatched(request_id: int, semantic_id: StringName, command: StringName)
signal request_rejected(request_id: int, semantic_id: StringName, reason: StringName)
signal action_ended(token: int, action_id: StringName, reason: StringName)

class LocomotionEvents extends Node:
	## Player receiving locomotion markers outside upper-body overlay filters.
	var player: Node

	func request_walk_stop() -> void:
		player.request_walk_stop()

	func set_next_foot_right() -> void:
		player.set_next_foot_right()

	func set_next_foot_left() -> void:
		player.set_next_foot_left()

	func play_footstep(foot: StringName = &"", emit_dust: bool = false) -> void:
		player.play_footstep(foot, emit_dust)

class ActionRequest extends RefCounted:
	var token: int = 0
	var action_id: StringName = &""
	var phase_id: StringName = &""
	var priority: int = 0
	var revision: int = 0
	var source: WeakRef

class EventRequest extends RefCounted:
	var request_id: int = 0
	var event_id: StringName = &""
	var priority: int = 0
	var expires_at: float = 0.0
	var owner_token: int = 0

## Player state used by the presentation director and compatibility adapter.
var _owner: Node
var _legacy: PlayerAnimationLegacyAdapter
var _motion: PlayerAnimationMotionBackend
var _presentation: PlayerAnimationActionBackend
var _overlays: PlayerAnimationOverlayBackend
var _actions: Dictionary[int, ActionRequest] = {}
var _events: Array[EventRequest] = []
var _next_id: int = 1
var _elapsed: float = 0.0
var _applied_token: int = 0
var _applied_revision: int = -1
var _updating: bool = false
var _remote_playback: bool = false
var _flushing: bool = false
var _resetting: bool = false
var _last_rejection: Dictionary = {}
var _last_dispatch: Dictionary = {}
## Animation source with player method tracks bound to the current hierarchy.
## Separate callback target for locomotion events beneath carry overlays.
var _locomotion_events: LocomotionEvents
var _method_animation_player: AnimationPlayer
## Root used to resolve animation method tracks.
var _method_animation_root: Node
## Animation source and audio targets owned by the debug preview session.
var _debug_player: AnimationPlayer
var _debug_library: AnimationLibrary
var _debug_library_name: StringName = &""
var _debug_audio: Array[Node] = []
var _debug_saved_active: bool = true
var _debug_saved_callback: int = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var _debug_original_root: AnimationNodeBlendTree


func _init(owner: Node) -> void:
	_owner = owner
	_legacy = PlayerAnimationLegacyAdapter.new(owner)
	_motion = PlayerAnimationMotionBackend.new(owner)
	_presentation = PlayerAnimationActionBackend.new(owner)
	_overlays = PlayerAnimationOverlayBackend.new(owner)
	_presentation.presentation_finished.connect(_on_presentation_finished)


func dispose() -> void:
	end_debug_preview()
	_resetting = true
	_actions.clear()
	_events.clear()
	_legacy.dispose()
	_motion.dispose()
	_presentation.dispose()
	_overlays.dispose()
	_method_animation_player = null
	_method_animation_root = null
	_owner = null


func update(delta: float) -> void:
	if not is_instance_valid(_owner) or _updating:
		return
	if _debug_player:
		if not _owner._debug_mode:
			end_debug_preview()
		else:
			if _owner.anim_tree.active:
				_owner.anim_tree.advance(maxf(delta, 0.0))
			return
	_updating = true
	if _presentation.is_enabled():
		configure_tree()
		var remaining: float = maxf(delta, 0.0)
		if remaining <= 0.000001:
			_update_hierarchy(0.0)
		while remaining > 0.000001:
			var step: float = minf(remaining, 1.0 / 60.0)
			_update_hierarchy(step)
			remaining -= step
		_updating = false
		return
	_owner._anim_module._update_animation(delta)
	if not _remote_playback:
		_motion.update(delta)
	flush_requests(delta)
	_owner._update_carry_animation(delta)
	_owner._update_pending_carry_put_down_release()
	_owner._update_pending_carry_throw_release()
	_owner._update_carry_command_animation_exit()
	_updating = false


func uses_render_clock() -> bool:
	return is_instance_valid(_owner) and _owner.is_inside_tree() and _owner.is_processing() and not _remote_playback and _presentation.is_enabled() and (not _owner._network_is_active() or _owner.is_multiplayer_authority())


func update_render(delta: float) -> void:
	if uses_render_clock() and not _owner._level_load_suspended and _owner.can_process():
		update(delta)


func update_physics(delta: float) -> void:
	if not uses_render_clock():
		update(delta)


func begin_debug_preview() -> bool:
	if _debug_player:
		return true
	if not is_instance_valid(_owner) or not _owner._debug_mode or not _owner.anim_tree or not (_owner.anim_tree.tree_root is AnimationNodeBlendTree):
		return false
	var player: AnimationPlayer = _owner.anim_tree.get_node_or_null(_owner.anim_tree.anim_player) as AnimationPlayer
	if not player:
		return false
	if not _ensure_debug_layer():
		return false
	reset(&"debug_preview")
	_debug_player = player
	_debug_saved_active = _owner.anim_tree.active
	_debug_saved_callback = _owner.anim_tree.callback_mode_process
	_debug_player.stop()
	_debug_library = AnimationLibrary.new()
	_debug_library_name = &"DebugPreview"
	while player.has_animation_library(_debug_library_name):
		_debug_library_name = StringName(String(_debug_library_name) + "_")
	player.add_animation_library(_debug_library_name, _debug_library)
	_owner.anim_tree.add_animation_library(_debug_library_name, _debug_library)
	_owner.anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_owner.anim_tree.active = true
	_owner.anim_tree.set("parameters/DebugOverride/blend_amount", 1.0)
	return true


func _ensure_debug_layer() -> bool:
	var tree: AnimationTree = _owner.anim_tree
	var root: AnimationNodeBlendTree = tree.tree_root
	if root.has_node(&"DebugAnimation") and root.has_node(&"DebugSeek") and root.has_node(&"DebugOverride"):
		return true
	var connections: Array = root.get("node_connections")
	var source: StringName = &""
	for index: int in range(0, connections.size(), 3):
		if connections[index] == &"output":
			source = connections[index + 2]
			break
	if source == &"":
		return false
	_debug_original_root = root
	root = root.duplicate(true)
	var clip: AnimationNodeAnimation = AnimationNodeAnimation.new()
	clip.animation = &"RESET"
	root.add_node(&"DebugAnimation", clip, Vector2(1180.0, 580.0))
	root.add_node(&"DebugSeek", AnimationNodeTimeSeek.new(), Vector2(1400.0, 580.0))
	root.add_node(&"DebugOverride", AnimationNodeBlend2.new(), Vector2(1640.0, 60.0))
	root.disconnect_node(&"output", 0)
	root.connect_node(&"DebugSeek", 0, &"DebugAnimation")
	root.connect_node(&"DebugOverride", 0, source)
	root.connect_node(&"DebugOverride", 1, &"DebugSeek")
	root.connect_node(&"output", 0, &"DebugOverride")
	tree.tree_root = root
	_owner._anim_module._refresh_owner_playbacks(tree)
	return true


func play_debug_animation(animation_name: StringName, audio_enabled: bool = true) -> bool:
	if not is_instance_valid(_owner) or not _owner._debug_mode or not begin_debug_preview() or not _debug_player.has_animation(animation_name):
		return false
	_stop_debug_audio()
	var clip: Animation = _debug_player.get_animation(animation_name).duplicate(true)
	var animation_root: Node = _debug_player.get_node(_debug_player.root_node)
	for track: int in range(clip.get_track_count() - 1, -1, -1):
		var type: Animation.TrackType = clip.track_get_type(track)
		if type == Animation.TYPE_METHOD or (type == Animation.TYPE_AUDIO and not audio_enabled):
			clip.remove_track(track)
		elif type == Animation.TYPE_AUDIO:
			var target: Node = animation_root.get_node_or_null(NodePath(clip.track_get_path(track).get_concatenated_names()))
			if target and target.has_method("stop") and target not in _debug_audio:
				_debug_audio.append(target)
	if _debug_library.has_animation(&"Clip"):
		_debug_library.remove_animation(&"Clip")
	_debug_library.add_animation(&"Clip", clip)
	var root: AnimationNodeBlendTree = _owner.anim_tree.tree_root
	var node: AnimationNodeAnimation = root.get_node(&"DebugAnimation")
	node.animation = StringName(String(_debug_library_name) + "/Clip")
	_owner.anim_tree.set("parameters/DebugSeek/seek_request", 0.0)
	_owner.anim_tree.set("parameters/DebugOverride/blend_amount", 1.0)
	_owner.anim_tree.advance(0.0)
	return true


func end_debug_preview() -> void:
	if not _debug_player:
		return
	_stop_debug_audio()
	if is_instance_valid(_owner) and _owner.anim_tree:
		_owner.anim_tree.set("parameters/DebugOverride/blend_amount", 0.0)
		var root: AnimationNodeBlendTree = _owner.anim_tree.tree_root
		var node: AnimationNodeAnimation = root.get_node(&"DebugAnimation")
		node.animation = &"RESET"
	_debug_player.stop()
	_debug_player.remove_animation_library(_debug_library_name)
	if is_instance_valid(_owner) and _owner.anim_tree and _owner.anim_tree.has_animation_library(_debug_library_name):
		_owner.anim_tree.remove_animation_library(_debug_library_name)
	_debug_player = null
	_debug_library = null
	_debug_library_name = &""
	if is_instance_valid(_owner) and _owner.anim_tree and _owner._anim_module and _owner.is_inside_tree():
		if _debug_original_root:
			_owner.anim_tree.tree_root = _debug_original_root
			_owner._anim_module._refresh_owner_playbacks(_owner.anim_tree)
		_debug_original_root = null
		_owner.anim_tree.active = _debug_saved_active
		_owner.anim_tree.callback_mode_process = _debug_saved_callback
		configure_tree()
		reset(&"debug_exit")
		restart_movement()
		if _owner.anim_tree.active:
			update(0.0)
	_debug_original_root = null


func _stop_debug_audio() -> void:
	for target: Node in _debug_audio:
		if is_instance_valid(target):
			target.call("stop")
	_debug_audio.clear()


func begin_action(action_id: StringName, source: Object, priority: int = 0) -> int:
	if _resetting:
		return 0
	if _remote_playback:
		_reject(0, action_id, &"remote_playback")
		return 0
	var profile: PlayerAnimationProfile = _get_profile()
	if not is_instance_valid(source) or not profile or profile.get_action_command(action_id) == &"":
		_reject(0, action_id, &"unbound_action")
		return 0
	if _owner.anim_tree and not _legacy.has_command(profile.get_action_command(action_id)):
		_reject(0, action_id, &"missing_target")
		return 0
	for existing: ActionRequest in _actions.values():
		if existing.action_id == action_id and existing.source.get_ref() == source:
			end_action(existing.token, &"replaced")
	var action: ActionRequest = ActionRequest.new()
	action.token = _allocate_id()
	action.action_id = action_id
	action.priority = priority
	action.source = weakref(source)
	_actions[action.token] = action
	return action.token


func set_action_phase(token: int, phase_id: StringName) -> bool:
	var action: ActionRequest = _actions.get(token)
	var profile: PlayerAnimationProfile = _get_profile()
	if not action or not action.source.get_ref() or not profile:
		return false
	if profile.get_action_command(action.action_id, phase_id) == &"":
		_reject(token, action.action_id, &"unbound_phase")
		return false
	if _owner.anim_tree and not _legacy.has_command(profile.get_action_command(action.action_id, phase_id)):
		_reject(token, action.action_id, &"missing_target")
		return false
	if action.phase_id != phase_id:
		action.phase_id = phase_id
		action.revision += 1
	return true


func end_action(token: int, reason: StringName = &"completed") -> bool:
	var action: ActionRequest = _actions.get(token)
	if not action:
		return false
	_actions.erase(token)
	_presentation.cancel_owner(token)
	_cancel_owned_events(token, reason)
	action_ended.emit(token, action.action_id, reason)
	return true


func request_event(event_id: StringName, priority: int = 0, lifetime: float = -1.0, owner_token: int = 0) -> int:
	if _resetting:
		return 0
	if _remote_playback:
		_reject(0, event_id, &"remote_playback")
		return 0
	var profile: PlayerAnimationProfile = _get_profile()
	if not profile or profile.get_event_command(event_id) == &"":
		_reject(0, event_id, &"unbound_event")
		return 0
	if owner_token and not _actions.has(owner_token):
		_reject(0, event_id, &"stale_owner")
		return 0
	if _events.size() >= maxi(profile.event_queue_capacity, 1):
		_reject(0, event_id, &"queue_full")
		return 0
	var duration: float = profile.event_lifetime if lifetime < 0.0 else lifetime
	if duration <= 0.0 or not is_finite(duration):
		_reject(0, event_id, &"invalid_lifetime")
		return 0
	var event: EventRequest = EventRequest.new()
	event.request_id = _allocate_id()
	event.event_id = event_id
	event.priority = priority
	event.expires_at = _elapsed + duration
	event.owner_token = owner_token
	_events.append(event)
	return event.request_id


func flush_requests(delta: float = 0.0) -> void:
	if _flushing or _resetting:
		return
	_flushing = true
	_flush_requests(delta)
	_flushing = false


func _flush_requests(delta: float) -> void:
	if not is_instance_valid(_owner):
		return
	_elapsed += maxf(delta, 0.0)
	_prune_requests()
	if _owner._pending_anim_command != &"":
		_legacy.apply_pending()
		return
	if _remote_playback or not _owner.anim_tree or not _owner.anim_state or not _owner.anim_tree.active or _owner._rail_switch_active:
		return
	var profile: PlayerAnimationProfile = _get_profile()
	if not profile:
		return
	var action: ActionRequest = _select_action()
	var action_revision: int = action.revision if action else -1
	var event: EventRequest = _select_event()
	if event and (not action or event.priority >= action.priority):
		_events.erase(event)
		var dispatched: bool = _dispatch(event.request_id, event.event_id, profile.get_event_command(event.event_id), profile.default_crossfade)
		if dispatched and action and _actions.has(action.token):
			_applied_token = action.token
			_applied_revision = action_revision
		return
	if not action:
		_applied_token = 0
		_applied_revision = -1
		return
	if action.token == _applied_token and action.revision == _applied_revision:
		return
	if _dispatch(action.token, action.action_id, profile.get_action_command(action.action_id, action.phase_id), profile.default_crossfade) and _actions.has(action.token):
		_applied_token = action.token
		_applied_revision = action_revision


func reset(reason: StringName = &"reset") -> void:
	if _resetting:
		return
	_resetting = true
	_motion.clear_requests()
	_presentation.reset()
	_overlays.reset()
	var actions: Array = _actions.values()
	var events: Array[EventRequest] = _events.duplicate()
	_actions.clear()
	_events.clear()
	_applied_token = 0
	_applied_revision = -1
	if is_instance_valid(_owner):
		_owner._pending_anim_command = &""
		_owner._pending_anim_crossfade = -1.0
	for action: ActionRequest in actions:
		action_ended.emit(action.token, action.action_id, reason)
	for event: EventRequest in events:
		_reject(event.request_id, event.event_id, reason)
	_resetting = false


func queue_legacy_command(command: StringName, send_net: bool = true, crossfade: float = -1.0, force: bool = false) -> bool:
	return _legacy.queue_command(command, send_net, crossfade, force)


func get_motion_backend() -> PlayerAnimationMotionBackend:
	return _motion


func get_action_backend() -> PlayerAnimationActionBackend:
	return _presentation


func get_overlay_backend() -> PlayerAnimationOverlayBackend:
	return _overlays


func is_remote_playback() -> bool:
	return _remote_playback


func configure_tree() -> void:
	var tree: AnimationTree = _owner.anim_tree
	if tree and tree.tree_root and not tree.tree_root.resource_local_to_scene and not Engine.is_editor_hint():
		tree.tree_root = tree.tree_root.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as AnimationRootNode
		tree.tree_root.resource_local_to_scene = true
	_bind_player_method_tracks()
	if _presentation.is_enabled():
		_owner.anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_owner.anim_tree.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE


func _bind_player_method_tracks() -> void:
	var tree: AnimationTree = _owner.anim_tree
	if not tree or tree.anim_player.is_empty():
		return
	var player: AnimationPlayer = tree.get_node_or_null(tree.anim_player) as AnimationPlayer
	var root: Node = tree.get_node_or_null(tree.root_node)
	if not player or not root or (player == _method_animation_player and root == _method_animation_root):
		return
	_method_animation_player = player
	_method_animation_root = root
	var player_path: NodePath = root.get_path_to(_owner)
	if not is_instance_valid(_locomotion_events):
		_locomotion_events = LocomotionEvents.new()
		_locomotion_events.name = "AnimationLocomotionEvents"
		_locomotion_events.player = _owner
		_owner.add_child(_locomotion_events)
	var locomotion_path: NodePath = root.get_path_to(_locomotion_events)
	for library_name: StringName in player.get_animation_library_list():
		var source: AnimationLibrary = player.get_animation_library(library_name)
		var library: AnimationLibrary
		for animation_name: StringName in source.get_animation_list():
			var clip: Animation = source.get_animation(animation_name)
			var replacement: Animation
			for track: int in clip.get_track_count():
				var misplaced: bool = _is_misplaced_player_method_track(clip, track, root)
				var locomotion: bool = _is_locomotion_method_track(clip, track) and (misplaced or root.get_node_or_null(clip.track_get_path(track)) == _owner)
				if not misplaced and not locomotion:
					continue
				if not replacement:
					replacement = clip.duplicate(false) as Animation
				replacement.track_set_path(track, locomotion_path if locomotion else player_path)
			if replacement:
				if not library:
					library = source.duplicate(false) as AnimationLibrary
				library.remove_animation(animation_name)
				library.add_animation(animation_name, replacement)
		if library:
			player.remove_animation_library(library_name)
			player.add_animation_library(library_name, library)
			if tree.has_animation_library(library_name):
				tree.remove_animation_library(library_name)
			tree.add_animation_library(library_name, library)


func _is_locomotion_method_track(clip: Animation, track: int) -> bool:
	if clip.track_get_type(track) != Animation.TYPE_METHOD or not clip.track_get_key_count(track):
		return false
	for key: int in clip.track_get_key_count(track):
		if clip.method_track_get_name(track, key) not in [&"request_walk_stop", &"set_next_foot_right", &"set_next_foot_left", &"play_footstep"]:
			return false
	return true


func _is_misplaced_player_method_track(clip: Animation, track: int, root: Node) -> bool:
	if clip.track_get_type(track) != Animation.TYPE_METHOD or not clip.track_get_key_count(track):
		return false
	var path: NodePath = clip.track_get_path(track)
	if path.is_absolute() or path.get_subname_count():
		return false
	for part: String in String(path).split("/", false):
		if part not in [".", ".."]:
			return false
	var target: Node = root.get_node_or_null(path)
	if target == _owner:
		return false
	for key: int in clip.track_get_key_count(track):
		var method: StringName = clip.method_track_get_name(track, key)
		if not _owner.has_method(method) or (target and target.has_method(method)):
			return false
	return true


func get_current_state() -> StringName:
	return _presentation.current_state() if _presentation.is_enabled() else (_owner.anim_state.get_current_node() if _owner.anim_state else &"")


func get_group_playback(group: StringName) -> AnimationNodeStateMachinePlayback:
	if _presentation.is_enabled():
		return _presentation.group_playback(group)
	return _owner.anim_tree.get("%s/%s/playback" % [PlayerAnimation.SM_BASE, group]) if _owner.anim_tree else null


func get_active_playback() -> AnimationNodeStateMachinePlayback:
	if _motion.is_landing():
		return _owner.ground_state
	return _presentation.active_playback() if _presentation.is_enabled() else _owner.anim_state


func map_parameter(path: String) -> String:
	if not _presentation.is_enabled():
		return path
	var prefix: String = PlayerAnimation.SM_BASE
	for group: StringName in PlayerAnimationActionBackend.GROUPS:
		var old_path: String = prefix + "/" + String(group)
		if path.begins_with(old_path + "/"):
			return path.replace(old_path, PlayerAnimationActionBackend.BASE + "/" + String(PlayerAnimationActionBackend.GROUPS[group]))
	if path.begins_with(prefix + "/GAME_Land_Hard/"):
		if _motion.has_local_landings():
			return _motion.map_parameter(path)
		return path.replace(prefix + "/GAME_Land_Hard", PlayerAnimationActionBackend.BASE + "/Ground/LandHard")
	return path


func capture_marker(event_id: StringName, phase: StringName) -> void:
	_overlays.capture_marker(event_id, phase)


func advance_remote(delta: float) -> void:
	if not _presentation.is_enabled() or not _remote_playback:
		return
	configure_tree()
	_owner.anim_tree.advance(maxf(delta, 0.0))


func restart_movement() -> bool:
	if _presentation.is_enabled():
		_presentation.reset()
		_overlays.reset()
	return _motion.reset_playback()


func resume_movement() -> void:
	if _presentation.is_enabled() and not _presentation.allows_body_request():
		return
	if _motion.is_enabled():
		_motion.resume()
	else:
		_legacy.queue_command(_owner._get_respawn_animation_start_node(), false)
		_legacy.apply_pending()


func apply_legacy_command(force_direct: bool = false) -> void:
	_legacy.apply_pending(force_direct)


func play_action_if_exists(action_name: StringName, send_net: bool = true) -> bool:
	var profile: PlayerAnimationProfile = _get_profile()
	var command: StringName = profile.get_action_command(action_name) if profile else &""
	if command != &"" and _legacy.has_command(command):
		_legacy.queue_command(command, send_net)
		return true
	return _legacy.play_action_if_exists(action_name, send_net)


func resolve_legacy_target(command: StringName, machine: AnimationNodeStateMachine) -> Dictionary:
	return _legacy.resolve_target(command, machine)


func capture_network_snapshot() -> Dictionary:
	return _owner._anim_module.capture_network_snapshot()


func get_network_seeks() -> Dictionary[String, String]:
	var paths: Dictionary[String, String] = {}
	if not _presentation.is_enabled():
		return paths
	for family: StringName in [&"Ground", &"Air", &"Ball"]:
		paths[PlayerAnimationMotionBackend.BASE + "/" + String(family) + "Seek/seek_request"] = PlayerAnimationMotionBackend.BASE + "/" + String(family) + "/playback"
	for family: StringName in PlayerAnimationActionBackend.FAMILIES:
		if family != &"Tricks":
			paths[PlayerAnimationActionBackend.BASE + "/" + String(family) + "Seek/seek_request"] = PlayerAnimationActionBackend.BASE + "/" + String(family) + "/playback"
	for bank: String in ["A", "B"]:
		paths[PlayerAnimationActionBackend.BASE + "/Tricks/Active/Seek" + bank + "/seek_request"] = bank
	paths["parameters/StateMachine/REACTIONS/Seek/seek_request"] = "parameters/StateMachine/REACTIONS/State/playback"
	paths["parameters/CarrySeek/seek_request"] = "parameters/CarryAnimation/playback"
	paths["parameters/LandingSeek/seek_request"] = "parameters/LandingRollAnimation/playback"
	return paths


func capture_seek_position(source: String) -> float:
	if source in ["A", "B"]:
		var base: String = PlayerAnimationActionBackend.BASE + "/Tricks/Active/"
		var variant: String = String(_owner.anim_tree.get(base + "Select" + source + "/current_state"))
		return float(_owner.anim_tree.get(base + source + "_" + variant + "/current_position")) if variant != "" else 0.0
	var playback: AnimationNodeStateMachinePlayback = _owner.anim_tree.get(source)
	while playback:
		var nested_path: String = source.get_base_dir() + "/" + String(playback.get_current_node()) + "/playback"
		if not _owner._anim_param_exists(nested_path):
			return playback.get_current_play_position()
		source = nested_path
		playback = _owner.anim_tree.get(source)
	return 0.0


func prepare_remote_playback() -> void:
	if not _remote_playback:
		reset(&"remote_playback")
		_remote_playback = true


func apply_network_snapshot(states: Dictionary, values: Array) -> void:
	prepare_remote_playback()
	_owner._anim_module.apply_network_snapshot(states, values)
	if _presentation.is_enabled():
		_presentation.synchronize_remote_state()


func restore_authority_tree() -> void:
	if _remote_playback:
		reset(&"authority_changed")
	_remote_playback = false
	_owner._anim_module.restore_authority_tree()


func get_debug_snapshot() -> Dictionary:
	var action: ActionRequest = _select_action()
	return {
		"action_count": _actions.size(),
		"queued_events": _events.size(),
		"selected_token": action.token if action else 0,
		"selected_action": action.action_id if action else &"",
		"selected_phase": action.phase_id if action else &"",
		"applied_token": _applied_token,
		"remote_playback": _remote_playback,
		"last_rejection": _last_rejection.duplicate(),
		"last_dispatch": _last_dispatch.duplicate(),
		"motion_family": _motion.get_family(),
	}


func _dispatch(request_id: int, semantic_id: StringName, command: StringName, crossfade: float) -> bool:
	if command == &"" or not _legacy.has_command(command):
		_reject(request_id, semantic_id, &"missing_target")
		return false
	if _presentation.is_enabled() and _presentation.resolve(command) != &"":
		if not _presentation.apply_command(command, false, request_id if _actions.has(request_id) else 0):
			_reject(request_id, semantic_id, &"presentation_blocked")
			return false
		if _owner._network_is_active() and _owner.network_replication_enabled and _owner.is_multiplayer_authority():
			_owner.rpc("_net_anim_command", command)
	elif not _legacy.queue_command(command, true, crossfade):
		_reject(request_id, semantic_id, &"legacy_priority")
		return false
	else:
		_legacy.apply_pending()
	_last_dispatch = {"request_id": request_id, "semantic_id": semantic_id, "command": command}
	request_dispatched.emit(request_id, semantic_id, command)
	return true


func _update_hierarchy(delta: float) -> void:
	if not _owner.anim_tree.active:
		flush_requests(delta)
		return
	if _remote_playback:
		_owner.anim_tree.advance(delta)
		return
	_owner._anim_module._update_animation(delta)
	_motion.update(delta)
	_presentation.update(delta)
	flush_requests(delta)
	_overlays.update(delta)
	_owner.anim_tree.advance(delta)
	_overlays.after_advance()
	_presentation.after_advance()
	_motion.after_advance()


func _on_presentation_finished(token: int, reason: StringName) -> void:
	end_action(token, reason)


func _reject(request_id: int, semantic_id: StringName, reason: StringName) -> void:
	_last_rejection = {"request_id": request_id, "semantic_id": semantic_id, "reason": reason}
	request_rejected.emit(request_id, semantic_id, reason)


func _prune_requests() -> void:
	for action: ActionRequest in _actions.values():
		if not action.source.get_ref():
			end_action(action.token, &"owner_freed")
	for event: EventRequest in _events.duplicate():
		if event.expires_at <= _elapsed:
			_events.erase(event)
			request_rejected.emit(event.request_id, event.event_id, &"expired")


func _cancel_owned_events(token: int, reason: StringName) -> void:
	for event: EventRequest in _events.duplicate():
		if event.owner_token == token:
			_events.erase(event)
			request_rejected.emit(event.request_id, event.event_id, reason)


func _select_action() -> ActionRequest:
	var selected: ActionRequest = null
	for action: ActionRequest in _actions.values():
		if action.source.get_ref() and (not selected or action.priority > selected.priority or (action.priority == selected.priority and action.token > selected.token)):
			selected = action
	return selected


func _select_event() -> EventRequest:
	var selected: EventRequest = null
	for event: EventRequest in _events:
		if not selected or event.priority > selected.priority:
			selected = event
	return selected


func _get_profile() -> PlayerAnimationProfile:
	return _owner.animation_profile if is_instance_valid(_owner) else null


func _allocate_id() -> int:
	var result: int = _next_id
	_next_id += 1
	return result

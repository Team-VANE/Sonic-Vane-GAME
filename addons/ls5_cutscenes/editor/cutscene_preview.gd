@tool
extends SubViewportContainer

const Actor = preload("res://addons/ls5_cutscenes/editor/cutscene_preview_actor.gd")
const Resolver = preload("res://LS5Framework/Scripts/World/CutsceneActorHandler.gd")
const SAMPLE_LIBRARY: StringName = &"CutscenePreviewSamples"

var rows: Array[Dictionary] = []
var duration: float = 0.0

var _viewport: SubViewport
var _stage: Node
var _shot: Camera3D
var _marker: Node3D
var _player: Node3D
var _lip_sync: LipSyncDriver
var _master: Dictionary
var _settings: Resolver
var _samples: Dictionary[AnimationPlayer, Dictionary] = {}
var _motions: Dictionary[AnimationPlayer, Array] = {}
var _speech: Dictionary[StringName, Array] = {}
var _voices: Dictionary[StringName, AudioStreamPlayer] = {}
var _voice_keys: Dictionary[StringName, float] = {}
var _volume_db: float = 0.0
var _time: float = 0.0


func setup(level: Node, director: Node, character: Dictionary) -> String:
	var timeline: AnimationPlayer = director.get("timeline") as AnimationPlayer
	var camera: Camera3D = director.get("shot_camera") as Camera3D
	var marker: Node3D = director.get("player_pose") as Node3D
	var sequence: StringName = director.get("sequence")
	if not timeline or not camera or not timeline.has_animation(sequence):
		return "Assign a Shot Camera and an animation in the cutscene’s Timeline."
	for target: Node in [timeline, camera]:
		if target != level and not level.is_ancestor_of(target):
			return "Keep the timeline and camera inside the edited scene."

	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)

	_stage = level.duplicate(0)
	_prepare_nodes(_stage)
	_viewport.add_child(_stage)
	if not _stage is Light3D and _stage.find_children("*", "Light3D", true, false).is_empty():
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45.0, 25.0, 0.0)
		_viewport.add_child(light)
	_shot = _stage.get_node_or_null(level.get_path_to(camera)) as Camera3D
	var mixer: AnimationPlayer = _stage.get_node_or_null(level.get_path_to(timeline)) as AnimationPlayer
	if not _shot or not mixer:
		return "The preview could not resolve the camera or timeline."
	if marker and level.is_ancestor_of(marker):
		_marker = _stage.get_node_or_null(level.get_path_to(marker)) as Node3D
	_shot.make_current()
	_hide_other_casts(level)
	_add_player(character)
	_bind_roles(level, director)

	var source: Animation = timeline.get_animation(sequence)
	duration = source.length
	_master = _pose_sample(mixer, sequence)
	var handler: Node = director.get("actor_handler")
	var copied_handler: Node = _stage.get_node_or_null(level.get_path_to(handler)) if handler and level.is_ancestor_of(handler) else null
	_index_timeline(source, mixer, director, _stage.get_node_or_null(level.get_path_to(director)), copied_handler)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	seek(0.0, false)
	return ""


func seek(time: float, audible: bool) -> void:
	_time = clampf(time, 0.0, duration)
	if _viewport.get_camera_3d() != _shot:
		_shot.make_current()
	_sample(_master, _time, false)
	if _player and _marker:
		_player.global_transform = _marker.global_transform
	for mixer: AnimationPlayer in _motions:
		var cue: Dictionary = _at_time(_motions[mixer], _time)
		if cue.is_empty():
			cue = _motions[mixer].front()
		_sample(cue.sample, float(cue.get("hold", maxf(_time - float(cue.time), 0.0))))
	_sample_dialogue(audible)


func silence() -> void:
	for player: AudioStreamPlayer in _voices.values():
		player.stop()
	_voice_keys.clear()


func set_preview_volume(percent: float) -> void:
	_volume_db = -80.0 if percent <= 0.0 else linear_to_db(percent / 100.0)
	for player: AudioStreamPlayer in _voices.values():
		player.volume_db = _volume_db


func _prepare_nodes(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is AnimationMixer:
		node.active = false
	if node is AnimationPlayer or node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
		if node is AnimationPlayer:
			node.autoplay = ""
		else:
			node.autoplay = false
	if node is CanvasLayer or node is CanvasItem:
		node.hide()
	if node is GPUParticles3D or node is CPUParticles3D:
		node.emitting = false
	for child: Node in node.get_children():
		_prepare_nodes(child)


func _hide_other_casts(level: Node) -> void:
	for director: Node in level.get_tree().get_nodes_in_group(&"cutscene_director"):
		if director != level and not level.is_ancestor_of(director):
			continue
		var paths: Dictionary = director.get("actor_paths")
		for role: StringName in director.get("staged_roles"):
			var source: Node = director.get_node_or_null(paths.get(role, NodePath("")))
			if source and level.is_ancestor_of(source):
				var actor: Node3D = _stage.get_node_or_null(level.get_path_to(source)) as Node3D
				if actor:
					actor.hide()


func _add_player(character: Dictionary) -> void:
	if not _marker or character.is_empty():
		return
	var packed: PackedScene = load(character.scene) as PackedScene
	if not packed:
		return
	var source: Node = packed.instantiate()
	var model: Node3D = source.get("model_root") as Node3D
	if not model:
		source.free()
		return
	var profile: Resource = source.get("character_settings_profile") as Resource
	var tree: AnimationTree = source.get("anim_tree") as AnimationTree
	var mixer: AnimationPlayer = tree.get_node_or_null(tree.anim_player) as AnimationPlayer if tree else null
	var source_lip: Node = model.find_child("LipSyncDriver", true, false)
	var visual: Node3D = model.duplicate(0) as Node3D
	_prepare_nodes(visual)
	_player = Actor.new()
	_player.name = "PreviewPlayer"
	_player.character_id = StringName(character.id)
	if profile:
		_player.cue_profile = profile.get("cutscene_profile")
	_player.add_child(visual)
	if mixer and model.is_ancestor_of(mixer):
		_player.animation_player = visual.get_node_or_null(model.get_path_to(mixer))
	_viewport.add_child(_player)
	_player.global_transform = _marker.global_transform
	_bind_eye_projection(model, visual)
	if source_lip and source_lip.get_parent() is Skeleton3D:
		var lip_profile: LipSyncProfile = source_lip.get("profile") as LipSyncProfile
		var skeleton: Skeleton3D = visual.get_node_or_null(model.get_path_to(source_lip.get_parent())) as Skeleton3D
		if lip_profile and skeleton:
			_lip_sync = LipSyncDriver.new()
			_lip_sync.profile = lip_profile.duplicate()
			_lip_sync.set_editor_preview_enabled(true)
			skeleton.add_child(_lip_sync)
	source.free()


func _bind_eye_projection(model: Node3D, visual: Node3D) -> void:
	var original: CharacterEyeProjection = model.find_child("EyeProjection", true, false) as CharacterEyeProjection
	if not original or not original.eye_mesh or not model.is_ancestor_of(original.eye_mesh):
		return
	var projection: CharacterEyeProjection = CharacterEyeProjection.new()
	projection.eye_mesh = visual.get_node_or_null(model.get_path_to(original.eye_mesh)) as MeshInstance3D
	projection.projection_material = original.projection_material
	projection.surface_index = original.surface_index
	projection.match_physics_interpolation = false
	if original.left_projector and model.is_ancestor_of(original.left_projector):
		projection.left_projector = visual.get_node_or_null(model.get_path_to(original.left_projector)) as Node3D
	if original.right_projector and model.is_ancestor_of(original.right_projector):
		projection.right_projector = visual.get_node_or_null(model.get_path_to(original.right_projector)) as Node3D
	visual.add_child(projection)


func _bind_roles(level: Node, director: Node) -> void:
	var roles: Dictionary[StringName, Node3D] = {}
	var paths: Dictionary = director.get("actor_paths")
	for role: StringName in paths:
		var source: Node = director.get_node_or_null(paths[role])
		if source and (source == level or level.is_ancestor_of(source)):
			var actor: Node3D = _stage.get_node_or_null(level.get_path_to(source)) as Node3D
			if actor:
				roles[role] = actor
				if role in director.get("staged_roles"):
					actor.show()
		rows.append({"time": -1.0, "caption": "%s  ·  %s" % [role, roles[role].name if roles.has(role) else "Missing actor"]})
	if _player:
		roles[&"player"] = _player
	rows.append({"time": -1.0, "caption": "player  ·  %s" % [String(_player.character_id) if _player else "No preview character"]})
	rows.append({"time": -1.0, "caption": "camera  ·  %s" % _shot.name})
	if director.get("gameplay_movement"):
		rows.append({"time": -1.0, "caption": "Player movement  ·  Simulates in-game"})
	_settings = Resolver.new()
	add_child(_settings)
	var configured: Node = director.get("actor_handler")
	if configured:
		_settings.role_profiles = configured.get("role_profiles")
		_settings.character_profiles = configured.get("character_profiles")
		_settings.fallback_profile = configured.get("fallback_profile")
	var fallback: Dictionary[StringName, PackedStringArray] = {
		&"idle": PackedStringArray(director.get("idle_clips")),
		&"walk": PackedStringArray(director.get("walk_clips")),
	}
	_settings.begin(roles, fallback)


func _index_timeline(source: Animation, mixer: AnimationPlayer, source_director: Node, director: Node, handler: Node) -> void:
	var root: Node = mixer.get_node_or_null(mixer.root_node)
	_add_motion(_settings.resolve_animation(&"player", &"idle"), 0.0)
	for track: int in source.get_track_count():
		if not source.track_is_enabled(track):
			continue
		var kind: int = source.track_get_type(track)
		var path: NodePath = source.track_get_path(track)
		var target: Node = _track_node(root, path)
		if target and not _viewport.is_ancestor_of(target):
			target = null
		var player_motion: bool = kind == Animation.TYPE_VALUE and target == director and path.get_concatenated_subnames() == "player_motion"
		if not player_motion and kind not in [Animation.TYPE_METHOD, Animation.TYPE_ANIMATION, Animation.TYPE_AUDIO]:
			continue
		for key: int in source.track_get_key_count(track):
			var time: float = source.track_get_key_time(track, key)
			if kind == Animation.TYPE_METHOD:
				var method: StringName = source.method_track_get_name(track, key)
				if target == handler and handler:
					_index_actor_cue(method, source.method_track_get_params(track, key), time)
				elif director and target == director and method == &"play_player_dialogue":
					var required_id: StringName = source_director.get("dialogue_character_id")
					var stream: AudioStream = source_director.get("player_dialogue")
					if _player and stream and (required_id == &"" or required_id == _player.character_id):
						_add_dialogue(&"player", stream, time)
						_add_row(time, "player  ·  Dialogue")
					else:
						_add_row(time, "player  ·  Dialogue unavailable")
				else:
					_add_row(time, "%s  ·  Runtime event" % method)
			elif kind == Animation.TYPE_ANIMATION and target is AnimationPlayer:
				var clip: StringName = source.animation_track_get_key_animation(track, key)
				if clip == &"[stop]":
					var values: Array = _motions.get(target, [])
					if not values.is_empty():
						var prior: Dictionary = values.back()
						values.append({"time": time, "sample": prior.sample, "hold": time - float(prior.time)})
				elif target.has_animation(clip):
					_add_motion({"mixer": target, "clip": clip}, time)
					_add_row(time, "%s  ·  %s" % [target.get_parent().name, clip])
			elif kind == Animation.TYPE_AUDIO and target:
				_add_dialogue(StringName(path), source.audio_track_get_key_stream(track, key), time,
					source.audio_track_get_key_start_offset(track, key), source.audio_track_get_key_end_offset(track, key))
				_add_row(time, "%s  ·  Audio" % target.name)
			elif player_motion:
				var cue: StringName = &"walk" if int(source.track_get_key_value(track, key)) == 1 else &"idle"
				var available: bool = _add_motion(_settings.resolve_animation(&"player", cue), time)
				_add_row(time, "player  ·  %s%s" % [cue, "" if available else "  ·  Unavailable for this cast"])
	for cues: Array in _motions.values():
		cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for cues: Array in _speech.values():
		cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)


func _index_actor_cue(method: StringName, args: Array, time: float) -> void:
	if args.size() < 2 or not (args[0] is StringName or args[0] is String) or not (args[1] is StringName or args[1] is String):
		_add_row(time, "%s  ·  Runtime event" % method)
		return
	var role: StringName = StringName(args[0])
	var cue: StringName = StringName(args[1])
	var available: bool = false
	match method:
		&"play_dialogue":
			var stream: AudioStream = _settings.resolve_dialogue(role, cue)
			if stream:
				_add_dialogue(role, stream, time)
				available = true
		&"play_animation", &"perform_action":
			var binding: Dictionary = _settings.resolve_animation(role, cue) if method == &"play_animation" else _settings.resolve_action_animation(role, cue)
			available = _add_motion(binding, time)
		_:
			_add_row(time, "%s  ·  Runtime event" % method)
			return
	var status: String = "" if available else ("  ·  Runtime action or unavailable" if method == &"perform_action" else "  ·  Unavailable for this cast")
	_add_row(time, "%s  ·  %s%s" % [role, cue, status])


func _add_row(time: float, caption: String) -> void:
	rows.append({"time": time, "caption": "%.2f s   %s" % [time, caption]})


func _add_motion(binding: Dictionary, time: float) -> bool:
	if binding.is_empty():
		return false
	var mixer: AnimationPlayer = binding.mixer
	if not _viewport.is_ancestor_of(mixer):
		return false
	var entries: Array = _motions.get(mixer, [])
	entries.append({"time": time, "sample": _pose_sample(mixer, binding.clip)})
	_motions[mixer] = entries
	return true


func _add_dialogue(role: StringName, stream: AudioStream, time: float, start: float = 0.0, end: float = 0.0) -> void:
	if not stream:
		return
	var entries: Array = _speech.get(role, [])
	var lips: LipSyncClip = null
	if role == &"player" and _lip_sync:
		lips = _find_lip_clip(stream)
	entries.append({"time": time, "stream": stream, "offset": start, "length": maxf(0.0, stream.get_length() - start - end), "lips": lips})
	_speech[role] = entries


func _find_lip_clip(stream: AudioStream) -> LipSyncClip:
	var expected: String = stream.resource_path.get_file().get_basename() + ".lipsync.tres"
	for path: String in _lip_sync.profile.clip_paths:
		if path.get_file() == expected:
			var clip: LipSyncClip = load(path) as LipSyncClip
			if clip and clip.audio == stream:
				return clip
	return _lip_sync.profile.find_clip(stream)


func _sample_dialogue(audible: bool) -> void:
	for role: StringName in _speech:
		var cue: Dictionary = _at_time(_speech[role], _time)
		var elapsed: float = 0.0 if cue.is_empty() else _time - float(cue.time)
		var playing: bool = not cue.is_empty() and elapsed < float(cue.length)
		if role == &"player" and _lip_sync:
			if not cue.is_empty() and cue.lips and elapsed + float(cue.offset) <= cue.lips.get_influence_duration():
				_lip_sync.set_preview(cue.lips, elapsed + float(cue.offset), audible)
			else:
				_lip_sync.clear_preview()
		if not audible or not playing:
			if _voices.has(role):
				_voices[role].stop()
				_voice_keys.erase(role)
			continue
		if not _voices.has(role):
			var voice: AudioStreamPlayer = AudioStreamPlayer.new()
			voice.volume_db = _volume_db
			_viewport.add_child(voice)
			_voices[role] = voice
		if not _voice_keys.has(role) or _voice_keys[role] != cue.time:
			_voices[role].stream = cue.stream
			_voices[role].play(elapsed + float(cue.offset))
			_voice_keys[role] = cue.time


func _at_time(cues: Array, time: float) -> Dictionary:
	for index: int in range(cues.size() - 1, -1, -1):
		if float(cues[index].time) <= time:
			return cues[index]
	return {}


func _pose_sample(mixer: AnimationPlayer, name: StringName) -> Dictionary:
	var state: Dictionary = _samples.get(mixer, {})
	if state.is_empty():
		var library: AnimationLibrary = AnimationLibrary.new()
		var library_name: StringName = SAMPLE_LIBRARY
		while mixer.has_animation_library(library_name):
			library_name = StringName(String(library_name) + "_")
		mixer.add_animation_library(library_name, library)
		mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		mixer.active = true
		state = {"library": library, "library_name": library_name, "clips": {}}
		_samples[mixer] = state
	if not state.clips.has(name):
		var clip: Animation = mixer.get_animation(name).duplicate()
		var root: Node = mixer.get_node_or_null(mixer.root_node)
		for index: int in range(clip.get_track_count() - 1, -1, -1):
			if not _safe_pose_track(clip, index, root):
				clip.remove_track(index)
		var key: StringName = StringName("Pose%d" % state.clips.size())
		state.library.add_animation(key, clip)
		state.clips[name] = StringName("%s/%s" % [state.library_name, key])
	return {"mixer": mixer, "clip": state.clips[name]}


func _safe_pose_track(clip: Animation, index: int, root: Node) -> bool:
	var kind: int = clip.track_get_type(index)
	if kind in [Animation.TYPE_AUDIO, Animation.TYPE_METHOD, Animation.TYPE_ANIMATION]:
		return false
	var path: NodePath = clip.track_get_path(index)
	var target: Node = _track_node(root, path)
	if not target or target is AnimationMixer or not _viewport.is_ancestor_of(target):
		return false
	if kind in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER]:
		if path.get_subname_count() == 0:
			return false
		var property: StringName = path.get_subname(0)
		if property in [&"script", &"process_mode", &"autoplay", &"playing", &"emitting"] or not property in target:
			return false
		var prefix: PackedStringArray = []
		for component: int in range(path.get_subname_count() - 1):
			prefix.append(path.get_subname(component))
			if target.get_indexed(NodePath(":".join(prefix))) is Object:
				return false
	return true


func _track_node(root: Node, path: NodePath) -> Node:
	if not root:
		return null
	var names: String = path.get_concatenated_names()
	return root if names.is_empty() else root.get_node_or_null(NodePath(names))


func _sample(binding: Dictionary, time: float, wrap: bool = true) -> void:
	if binding.is_empty():
		return
	var mixer: AnimationPlayer = binding.mixer
	var clip: Animation = mixer.get_animation(binding.clip)
	if mixer.assigned_animation != binding.clip or not mixer.is_playing():
		mixer.play(binding.clip, 0.0)
	var position: float = minf(time, clip.length)
	if wrap and clip.length > 0.0:
		if clip.loop_mode == Animation.LOOP_LINEAR:
			position = fposmod(time, clip.length)
		elif clip.loop_mode == Animation.LOOP_PINGPONG:
			position = pingpong(time, clip.length)
	mixer.seek(position, true, true)

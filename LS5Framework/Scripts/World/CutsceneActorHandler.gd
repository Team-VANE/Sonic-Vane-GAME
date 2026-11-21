@tool
extends Node
class_name CutsceneActorHandler

const ActorProfile = preload("res://LS5Framework/Scripts/World/CutsceneActorProfile.gd")
const CUTSCENE_LIBRARY: StringName = &"CutscenePose"

## Scene-specific cue overrides for roles such as player or guide.
@export var role_profiles: Dictionary[StringName, ActorProfile] = {}
## Scene-specific cue overrides keyed by character settings ID.
@export var character_profiles: Dictionary[StringName, ActorProfile] = {}
## Cue mappings used when the actor has no usable mapping of its own.
@export var fallback_profile: ActorProfile

var _actors: Dictionary[StringName, Node3D] = {}
var _player_motion: Dictionary[StringName, PackedStringArray] = {}
var _mixers: Dictionary[AnimationPlayer, Dictionary] = {}
var _voices: Dictionary[Node, Dictionary] = {}
var _action_actors: Array[Node3D] = []
var _active: bool = false
var _gameplay_player: PlayerController
var _overlay_filter: Array[NodePath] = []


func begin(actors: Dictionary[StringName, Node3D], player_motion: Dictionary[StringName, PackedStringArray]) -> void:
	end()
	_actors = actors
	_player_motion = player_motion
	_active = true


func end() -> void:
	_active = false
	set_gameplay_player(null, [])
	for actor: Node3D in _action_actors:
		if is_instance_valid(actor) and actor.has_method("end_cutscene_actions"):
			actor.call("end_cutscene_actions")
	_action_actors.clear()
	for voice: Node in _voices:
		if not is_instance_valid(voice):
			continue
		var state: Dictionary = _voices[voice]
		if voice.stream == state.stream:
			voice.stop()
		voice.process_mode = state.process_mode
	_voices.clear()
	for mixer: AnimationPlayer in _mixers:
		if is_instance_valid(mixer):
			_release_mixer(mixer, _mixers[mixer])
	_mixers.clear()
	_actors = {}
	_player_motion = {}


func set_gameplay_player(player: PlayerController, filter: Array[NodePath]) -> void:
	if is_instance_valid(_gameplay_player) and _gameplay_player != player:
		_gameplay_player.get_animation_director().clear_cutscene_overlay()
	_gameplay_player = player
	_overlay_filter = filter
	if player:
		for mixer: AnimationPlayer in _mixers.keys():
			if is_instance_valid(mixer) and player.is_ancestor_of(mixer):
				_release_mixer(mixer, _mixers[mixer])
				_mixers.erase(mixer)


func get_actor(role: StringName) -> Node3D:
	var actor: Node3D = _actors.get(role)
	return actor if is_instance_valid(actor) and not actor.is_queued_for_deletion() else null


func get_actor_character_id(role: StringName) -> StringName:
	var actor: Node3D = get_actor(role)
	if not actor:
		return &""
	if actor.has_method("get_cutscene_character_id"):
		var id: Variant = actor.call("get_cutscene_character_id")
		if id is String or id is StringName:
			return StringName(id)
	if actor is PlayerController and actor.character_settings_profile:
		return actor.character_settings_profile.character_id
	return &""


func get_actor_value(role: StringName, key: StringName, fallback: Variant = null) -> Variant:
	for profile: ActorProfile in _profiles_for(role):
		if profile.values.has(key):
			return profile.values[key]
	return fallback


func supports_animation(role: StringName, cue: StringName) -> bool:
	return not resolve_animation(role, cue).is_empty()


func resolve_animation(role: StringName, cue: StringName) -> Dictionary:
	var mixer: AnimationPlayer = _animation_player(role)
	if not mixer:
		return {}
	var clip: StringName = _animation_name(role, cue, mixer)
	return {"mixer": mixer, "clip": clip} if clip != &"" else {}


func resolve_action_animation(role: StringName, cue: StringName) -> Dictionary:
	for action: StringName in _action_names(role, cue):
		var animation: Dictionary = resolve_animation(role, action)
		if not animation.is_empty():
			return animation
	return {}


func play_animation(role: StringName, cue: StringName, blend: float = 0.12) -> bool:
	if not _active:
		return false
	var binding: Dictionary = resolve_animation(role, cue)
	if binding.is_empty():
		return false
	var mixer: AnimationPlayer = binding.mixer
	var clip_name: StringName = binding.clip
	if _gameplay_player and get_actor(role) == _gameplay_player:
		return _gameplay_player.get_animation_director().play_cutscene_overlay(mixer, clip_name, _overlay_filter, blend)
	var state: Dictionary = _mixers.get(mixer, {})
	if state.is_empty():
		state = _borrow_mixer(get_actor(role), mixer)
	var library: AnimationLibrary = state.library
	var clips: Dictionary = state.clips
	if not clips.has(clip_name):
		var clip: Animation = mixer.get_animation(clip_name).duplicate()
		for index: int in range(clip.get_track_count() - 1, -1, -1):
			if clip.track_get_type(index) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION]:
				clip.remove_track(index)
		var local_name: StringName = StringName("clip_%d" % clips.size())
		library.add_animation(local_name, clip)
		clips[clip_name] = StringName("%s/%s" % [state.library_name, local_name])
	mixer.play(clips[clip_name], blend)
	return true


func supports_dialogue(role: StringName, cue: StringName) -> bool:
	return resolve_dialogue(role, cue) != null and _dialogue_player(role) != null


func play_dialogue(role: StringName, cue: StringName) -> bool:
	return play_dialogue_clip(role, resolve_dialogue(role, cue))


func play_dialogue_clip(role: StringName, clip: AudioStream) -> bool:
	if not _active or not clip:
		return false
	var actor: Node3D = get_actor(role)
	var voice: Node = _dialogue_player(role)
	if not actor or not voice:
		return false
	var original_mode: int = voice.process_mode
	if actor is PlayerController and voice == actor.get_dialogue_player():
		var clips: Array[AudioStream] = [clip]
		actor.play_voice_clips(clips, 1.0, PlayerAudio.VOICE_PRIORITY_DIALOGUE)
	else:
		if not voice.can_process():
			voice.process_mode = Node.PROCESS_MODE_PAUSABLE
		voice.stream = clip
		voice.play()
	if not voice.playing or voice.stream != clip:
		voice.process_mode = original_mode
		return false
	var state: Dictionary = _voices.get(voice, {"process_mode": original_mode})
	state["stream"] = clip
	_voices[voice] = state
	return true


func supports_action(role: StringName, cue: StringName) -> bool:
	var actor: Node3D = get_actor(role)
	if not actor:
		return false
	for action: StringName in _action_names(role, cue):
		if _supports_custom_action(actor, action) or supports_animation(role, action):
			return true
	return false


func perform_action(role: StringName, cue: StringName) -> bool:
	var actor: Node3D = get_actor(role)
	if not _active or not actor:
		return false
	for action: StringName in _action_names(role, cue):
		if _supports_custom_action(actor, action) and actor.call("perform_cutscene_action", action) == true:
			if actor not in _action_actors:
				_action_actors.append(actor)
			return true
		if play_animation(role, action):
			return true
	return false


func _profiles_for(role: StringName) -> Array[ActorProfile]:
	var profiles: Array[ActorProfile] = []
	var actor: Node3D = get_actor(role)
	if not actor:
		return profiles
	var actor_profile: ActorProfile
	if actor.has_method("get_cutscene_profile"):
		actor_profile = actor.call("get_cutscene_profile") as ActorProfile
	if not actor_profile and actor is PlayerController and actor.character_settings_profile:
		actor_profile = actor.character_settings_profile.cutscene_profile
	for profile: ActorProfile in [role_profiles.get(role), character_profiles.get(get_actor_character_id(role)), actor_profile, fallback_profile]:
		if profile and profile not in profiles:
			profiles.append(profile)
	return profiles


func resolve_dialogue(role: StringName, cue: StringName) -> AudioStream:
	for profile: ActorProfile in _profiles_for(role):
		var clip: AudioStream = profile.dialogue_cues.get(cue)
		if clip:
			return clip
	return null


func _dialogue_player(role: StringName) -> Node:
	var actor: Node3D = get_actor(role)
	if not actor:
		return null
	for profile: ActorProfile in _profiles_for(role):
		if not profile.dialogue_player_path.is_empty():
			var voice: Node = actor.get_node_or_null(profile.dialogue_player_path)
			if voice is AudioStreamPlayer3D or voice is AudioStreamPlayer:
				return voice
	if actor.has_method("get_dialogue_player"):
		var voice: Node = actor.call("get_dialogue_player") as Node
		if voice is AudioStreamPlayer3D or voice is AudioStreamPlayer:
			return voice
	var named_voice: Node = actor.find_child("Dialogue_Player", true, false)
	return named_voice if named_voice is AudioStreamPlayer3D or named_voice is AudioStreamPlayer else null


func _animation_player(role: StringName) -> AnimationPlayer:
	var actor: Node3D = get_actor(role)
	if not actor:
		return null
	for profile: ActorProfile in _profiles_for(role):
		if not profile.animation_player_path.is_empty():
			var mixer: AnimationPlayer = actor.get_node_or_null(profile.animation_player_path) as AnimationPlayer
			if mixer:
				return mixer
	if actor.has_method("get_cutscene_animation_player"):
		var mixer: AnimationPlayer = actor.call("get_cutscene_animation_player") as AnimationPlayer
		if mixer:
			return mixer
	var direct: AnimationPlayer = actor.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if direct:
		return direct
	var mixers: Array[Node] = actor.find_children("*", "AnimationPlayer", true, false)
	return mixers[0] as AnimationPlayer if mixers.size() == 1 else null


func _animation_name(role: StringName, cue: StringName, mixer: AnimationPlayer) -> StringName:
	var candidates: PackedStringArray = []
	for profile: ActorProfile in _profiles_for(role):
		candidates.append_array(profile.animation_cues.get(cue, PackedStringArray()))
	if role == &"player":
		candidates.append_array(_player_motion.get(cue, PackedStringArray()))
	candidates.append(String(cue))
	var available: PackedStringArray = mixer.get_animation_list()
	for candidate: String in candidates:
		if mixer.has_animation(StringName(candidate)):
			return StringName(candidate)
		var match_name: StringName
		for name: String in available:
			if name.get_file().nocasecmp_to(candidate) != 0:
				continue
			if match_name != &"":
				match_name = &""
				break
			match_name = StringName(name)
		if match_name != &"":
			return match_name
	return &""


func _action_names(role: StringName, cue: StringName) -> Array[StringName]:
	var names: Array[StringName] = []
	for profile: ActorProfile in _profiles_for(role):
		var action: StringName = profile.action_cues.get(cue, &"")
		if action != &"" and action not in names:
			names.append(action)
	if cue not in names:
		names.append(cue)
	return names


func _supports_custom_action(actor: Node3D, action: StringName) -> bool:
	return actor.has_method("supports_cutscene_action") and actor.has_method("perform_cutscene_action") and actor.call("supports_cutscene_action", action) == true


func _borrow_mixer(actor: Node3D, mixer: AnimationPlayer) -> Dictionary:
	var library_name: StringName = CUTSCENE_LIBRARY
	while mixer.has_animation_library(library_name):
		library_name = StringName(String(library_name) + "_")
	var library: AnimationLibrary = AnimationLibrary.new()
	var previous_animation: StringName = mixer.assigned_animation
	var trees: Array[AnimationTree] = []
	for node: Node in actor.find_children("*", "AnimationTree", true, false):
		var tree: AnimationTree = node as AnimationTree
		if tree.active and tree.get_node_or_null(tree.anim_player) == mixer:
			trees.append(tree)
			tree.active = false
	var state: Dictionary = {
		"library": library, "library_name": library_name, "clips": {}, "trees": trees,
		"active": mixer.active, "process_mode": mixer.process_mode, "playing": mixer.is_playing(),
		"animation": previous_animation,
		"position": mixer.current_animation_position if mixer.has_animation(previous_animation) else 0.0,
	}
	mixer.active = true
	if not mixer.can_process():
		mixer.process_mode = Node.PROCESS_MODE_PAUSABLE
	mixer.add_animation_library(library_name, library)
	_mixers[mixer] = state
	return state


func _release_mixer(mixer: AnimationPlayer, state: Dictionary) -> void:
	mixer.stop(true)
	mixer.remove_animation_library(state.library_name)
	if state.playing and mixer.is_inside_tree() and mixer.has_animation(state.animation):
		mixer.play(state.animation)
		mixer.seek(state.position, true, true)
	mixer.active = state.active
	mixer.process_mode = state.process_mode
	for tree: AnimationTree in state.trees:
		if is_instance_valid(tree):
			tree.active = true


func _exit_tree() -> void:
	end()

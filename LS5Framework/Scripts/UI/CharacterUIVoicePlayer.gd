extends AudioStreamPlayer
class_name CharacterUIVoicePlayer

const CLIP_SELECTOR: Script = preload("res://LS5Framework/Scripts/Audio/AudioClipSelector.gd")
var _clip_selector: RefCounted = CLIP_SELECTOR.new()

var _registered_profiles: Dictionary = {}

var _cooldown_deadlines_ms: Dictionary = {}
var _last_clips: Dictionary = {}


func play_voice_class(profile: CharacterUIVoiceProfile, character_id: String, voice_class: StringName) -> bool:
	if profile == null or playing:
		return false
	register_profile(profile)
	var clips: Array[AudioStream] = profile.get_clips(voice_class)
	if clips.is_empty():
		return false
	var cooldown_key: String = "%s:%s" % [character_id.to_lower(), String(voice_class)]
	var now_ms: int = Time.get_ticks_msec()
	var cooldown_deadline_ms: int = int(_cooldown_deadlines_ms.get(cooldown_key, 0))
	if now_ms < cooldown_deadline_ms:
		return false
	var selected_clip: AudioStream = _select_clip(clips, _last_clips.get(cooldown_key) as AudioStream)
	if selected_clip == null:
		return false
	stream = selected_clip
	play()
	_last_clips[cooldown_key] = selected_clip
	var cooldown_ms: int = ceili(maxf(profile.same_class_cooldown, 0.0) * 1000.0)
	_cooldown_deadlines_ms[cooldown_key] = now_ms + cooldown_ms
	return true


func _select_clip(clips: Array[AudioStream], previous_clip: AudioStream) -> AudioStream:
	var index: int = _clip_selector.pick_index(clips, true, previous_clip)
	return clips[index] if index >= 0 else null


func register_profile(profile: CharacterUIVoiceProfile, refresh: bool = false) -> void:
	if not profile or (_registered_profiles.has(profile.get_instance_id()) and not refresh):
		return
	_registered_profiles[profile.get_instance_id()] = profile
	for voice_class: StringName in [&"confirm", &"character", &"level", &"settings", &"online", &"loading", &"confirm_exit"]:
		_clip_selector.register_clips(profile.get_clips(voice_class), refresh)

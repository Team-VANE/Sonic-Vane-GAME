extends AudioStreamPlayer
class_name CharacterUIVoicePlayer

var _cooldown_deadlines_ms: Dictionary = {}
var _last_clips: Dictionary = {}


func play_voice_class(profile: CharacterUIVoiceProfile, character_id: String, voice_class: StringName) -> bool:
	if profile == null or playing:
		return false
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
	var available_clips: Array[AudioStream] = []
	for clip: AudioStream in clips:
		if clip != null:
			available_clips.append(clip)
	if available_clips.is_empty():
		return null
	if available_clips.size() == 1:
		return available_clips[0]
	var fresh_clips: Array[AudioStream] = []
	for clip: AudioStream in available_clips:
		if clip != previous_clip:
			fresh_clips.append(clip)
	if fresh_clips.is_empty():
		return available_clips.pick_random()
	return fresh_clips.pick_random()

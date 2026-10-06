extends RefCounted
class_name PlayerItemEffects

var _owner: Node = null
var _active_event_music: StringName = &""


func _init(owner: Node) -> void:
	_owner = owner


func apply_speed_shoes(duration_override: float = -1.0) -> bool:
	var p = _owner
	if p == null or not is_instance_valid(p) or not p._network_is_local_authority():
		return false
	var duration: float = p.speed_shoes_duration if duration_override <= 0.0 else duration_override
	duration = max(duration, 0.0)
	if duration <= 0.0:
		return false
	p._speed_shoes_timer = max(p._speed_shoes_timer, duration)
	p._speed_shoes_music_tail_timer = 0.0
	if _active_event_music == &"invincibility":
		_release_invincibility_music(0.0)
	_active_event_music = &"speed_shoes"
	_request_speed_shoes_music()
	p.speed_shoes_changed.emit(true, p._speed_shoes_timer)
	return true


func apply_invincibility(duration_override: float = -1.0) -> bool:
	var p = _owner
	if p == null or not is_instance_valid(p) or not p._network_is_local_authority():
		return false
	var duration: float = p.invincibility_duration if duration_override <= 0.0 else duration_override
	duration = max(duration, 0.0)
	if duration <= 0.0:
		return false
	p._invincibility_timer = max(p._invincibility_timer, duration)
	p._invincibility_music_timer = max(
		p._invincibility_music_timer,
		p._invincibility_timer + max(p.invincibility_music_end_delay, 0.0)
	)
	p._invincibility_attack_timer = 0.0
	if _active_event_music == &"speed_shoes":
		release_speed_shoes_music(0.0)
	_active_event_music = &"invincibility"
	_request_invincibility_music()
	if p.has_method("_refresh_invincibility_visual"):
		p.call("_refresh_invincibility_visual", true)
	p.invincibility_changed.emit(true, p._invincibility_timer)
	return true


func is_invincibility_active() -> bool:
	var p = _owner
	return p != null and is_instance_valid(p) and p._invincibility_timer > 0.0


func get_invincibility_remaining() -> float:
	var p = _owner
	return max(p._invincibility_timer, 0.0) if p != null and is_instance_valid(p) else 0.0


func is_speed_shoes_active() -> bool:
	var p = _owner
	return p != null and is_instance_valid(p) and p._speed_shoes_timer > 0.0


func get_speed_shoes_remaining() -> float:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return 0.0
	return max(p._speed_shoes_timer, 0.0)


func get_effect_remaining(item_id: StringName) -> float:
	match item_id:
		&"speed_shoes":
			return get_speed_shoes_remaining()
		&"invincibility":
			return get_invincibility_remaining()
	return -1.0


func get_active_top_speed_multiplier() -> float:
	var p = _owner
	if p == null or not is_instance_valid(p) or not is_speed_shoes_active():
		return 1.0
	return max(p.speed_shoes_top_speed_multiplier, 0.0)


func get_active_acceleration_curve(fallback_curve: Curve) -> Curve:
	var p = _owner
	if p == null or not is_instance_valid(p) or not is_speed_shoes_active():
		return fallback_curve
	var configured_curve: Curve = p.speed_shoes_acceleration_curve as Curve
	return configured_curve if configured_curve != null else fallback_curve


func tick(delta: float) -> void:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p._invincibility_music_timer > 0.0:
		p._invincibility_music_timer = max(p._invincibility_music_timer - delta, 0.0)
		if p._invincibility_music_timer <= 0.0:
			_release_invincibility_music()
	if p._invincibility_timer > 0.0:
		p._invincibility_timer = max(p._invincibility_timer - delta, 0.0)
		if p._invincibility_timer <= 0.0:
			p.invincibility_changed.emit(false, 0.0)
			if p.has_method("_refresh_invincibility_visual"):
				p.call("_refresh_invincibility_visual", false)
		else:
			_tick_invincibility_attack(delta)
	if p._speed_shoes_timer > 0.0:
		p._speed_shoes_timer = max(p._speed_shoes_timer - delta, 0.0)
		if p._speed_shoes_timer <= 0.0:
			p.speed_shoes_changed.emit(false, 0.0)
			_begin_speed_shoes_music_tail()
			return
		if _active_event_music == &"speed_shoes" and p.speed_shoes_music != null and (
				p._speed_shoes_music_controller == null
				or not is_instance_valid(p._speed_shoes_music_controller)
			):
			_request_speed_shoes_music()
		return
	if p._speed_shoes_music_tail_timer > 0.0:
		p._speed_shoes_music_tail_timer = max(p._speed_shoes_music_tail_timer - delta, 0.0)
		if p._speed_shoes_music_tail_timer <= 0.0:
			release_speed_shoes_music()


func release_speed_shoes_music(fade_duration: float = -1.0) -> void:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	var release_fade: float = p.speed_shoes_music_return_crossfade \
		if fade_duration < 0.0 else max(fade_duration, 0.0)
	if p._speed_shoes_music_controller != null and is_instance_valid(p._speed_shoes_music_controller):
		p._speed_shoes_music_controller.release_music_override(
			_get_speed_shoes_music_source_id(),
			release_fade,
			release_fade
		)
	p._speed_shoes_music_controller = null
	p._speed_shoes_music_tail_timer = 0.0
	if _active_event_music == &"speed_shoes":
		_active_event_music = &""


func clear_all_effects() -> void:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	var speed_shoes_was_active: bool = p._speed_shoes_timer > 0.0
	p._speed_shoes_timer = 0.0
	p._speed_shoes_music_tail_timer = 0.0
	if speed_shoes_was_active:
		p.speed_shoes_changed.emit(false, 0.0)
	release_speed_shoes_music(0.0)
	var invincibility_was_active: bool = p._invincibility_timer > 0.0
	p._invincibility_timer = 0.0
	p._invincibility_music_timer = 0.0
	p._invincibility_attack_timer = 0.0
	if invincibility_was_active:
		p.invincibility_changed.emit(false, 0.0)
		if p.has_method("_refresh_invincibility_visual"):
			p.call("_refresh_invincibility_visual", false)
	_release_invincibility_music(0.0)


func _tick_invincibility_attack(delta: float) -> void:
	var p = _owner
	p._invincibility_attack_timer = max(p._invincibility_attack_timer - delta, 0.0)
	if p._invincibility_attack_timer > 0.0 or p.is_attack_active():
		return
	p._invincibility_attack_timer = 0.7
	for enemy: Node in p.get_tree().get_nodes_in_group("NPCActor"):
		if enemy != null and is_instance_valid(enemy) and enemy.has_method("apply_damage"):
			if p.global_position.distance_squared_to(enemy.global_position) <= 4.0:
				enemy.call("apply_damage", 1, p)


func _request_invincibility_music() -> void:
	var p = _owner
	if _active_event_music != &"invincibility" or p.invincibility_music == null or p.get_tree() == null:
		return
	var controller: MusicController = MusicController.find_active_controller(p.get_tree())
	if controller == null:
		return
	p._invincibility_music_controller = controller
	if p._invincibility_music_source_id == &"":
		p._invincibility_music_source_id = StringName("invincibility_%d" % p.get_instance_id())
	p._invincibility_prepared_music_stream = p.invincibility_music.duplicate() as AudioStream
	if p._invincibility_prepared_music_stream == null:
		p._invincibility_prepared_music_stream = p.invincibility_music
	if p._object_has_property(p._invincibility_prepared_music_stream, "loop_mode"):
		p._invincibility_prepared_music_stream.set("loop_mode", 0)
	if p._object_has_property(p._invincibility_prepared_music_stream, "loop"):
		p._invincibility_prepared_music_stream.set("loop", false)
	controller.request_music_override(p._invincibility_music_source_id, p._invincibility_prepared_music_stream, p.invincibility_music_priority, 0.0, 0.0, true)


func _release_invincibility_music(fade_duration: float = -1.0) -> void:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	var fade: float = p.invincibility_music_return_crossfade if fade_duration < 0.0 else max(fade_duration, 0.0)
	if p._invincibility_music_controller != null and is_instance_valid(p._invincibility_music_controller):
		p._invincibility_music_controller.release_music_override(p._invincibility_music_source_id, fade, fade)
	p._invincibility_music_controller = null
	p._invincibility_music_timer = 0.0
	if _active_event_music == &"invincibility":
		_active_event_music = &""


func _request_speed_shoes_music() -> void:
	var p = _owner
	if p == null or not is_instance_valid(p) or _active_event_music != &"speed_shoes" \
			or p.speed_shoes_music == null or p.get_tree() == null:
		return
	var music_controller: MusicController = MusicController.find_active_controller(p.get_tree())
	if music_controller == null:
		return
	if p._speed_shoes_music_controller != null \
			and is_instance_valid(p._speed_shoes_music_controller) \
			and p._speed_shoes_music_controller != music_controller:
		p._speed_shoes_music_controller.release_music_override(
			_get_speed_shoes_music_source_id(),
			p.speed_shoes_music_return_crossfade,
			p.speed_shoes_music_return_crossfade
		)
	p._speed_shoes_music_controller = music_controller
	music_controller.request_music_override(
		_get_speed_shoes_music_source_id(),
		_get_speed_shoes_music_stream(),
		p.speed_shoes_music_priority,
		0.0,
		0.0,
		true
	)


func _begin_speed_shoes_music_tail() -> void:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p._speed_shoes_music_controller == null or not is_instance_valid(p._speed_shoes_music_controller):
		release_speed_shoes_music()
		return
	var source_id: StringName = _get_speed_shoes_music_source_id()
	if not p._speed_shoes_music_controller.has_music_override(source_id):
		release_speed_shoes_music()
		return
	var stream: AudioStream = _get_speed_shoes_music_stream()
	if stream == null:
		release_speed_shoes_music()
		return
	if p._speed_shoes_music_controller.get_active_music_source_id() == source_id \
			and not p._speed_shoes_music_controller.is_music_source_playing(source_id):
		release_speed_shoes_music()
		return
	var playback_position: float = p._speed_shoes_music_controller.get_music_source_playback_position(
		source_id
	)
	var remaining_track_time: float = max(stream.get_length() - playback_position, 0.0)
	p._speed_shoes_music_tail_timer = max(
		remaining_track_time - max(p.speed_shoes_music_end_lead_time, 0.0),
		0.0
	)
	if p._speed_shoes_music_tail_timer <= 0.0:
		release_speed_shoes_music()


func _get_speed_shoes_music_source_id() -> StringName:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return &""
	if p._speed_shoes_music_source_id == &"":
		p._speed_shoes_music_source_id = StringName("speed_shoes_%d" % p.get_instance_id())
	return p._speed_shoes_music_source_id


func _get_speed_shoes_music_stream() -> AudioStream:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return null
	if p._speed_shoes_prepared_music_stream != null:
		return p._speed_shoes_prepared_music_stream
	var prepared_stream: AudioStream = p.speed_shoes_music.duplicate() as AudioStream
	if prepared_stream == null:
		prepared_stream = p.speed_shoes_music
	elif p.speed_shoes_music.resource_path != "":
		prepared_stream.set_meta(&"source_resource_path", p.speed_shoes_music.resource_path)
	if p._object_has_property(prepared_stream, "loop_mode"):
		prepared_stream.set("loop_mode", 0)
	if p._object_has_property(prepared_stream, "loop"):
		prepared_stream.set("loop", false)
	p._speed_shoes_prepared_music_stream = prepared_stream
	return p._speed_shoes_prepared_music_stream

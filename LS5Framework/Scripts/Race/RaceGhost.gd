extends Node3D

signal playback_finished()

## Peak opacity used while the ghost is visible.
@export_range(0.05, 1.0, 0.05) var visual_opacity: float = 0.55
## Duration used to fade the ghost in and out.
@export_range(0.0, 2.0, 0.05, "or_greater", "suffix:s") var visual_fade_duration: float = 0.3

var _samples: Array = []
var _playback_time: float = 0.0
var _duration: float = 0.0
var _playing: bool = false
var _visual_root: Node3D = null
var _animation_player: AnimationPlayer = null
var _current_clip: StringName = &""
var _sample_cursor: int = 0
var _source_tick_rate: int = GhostDataManager.LEGACY_TICK_RATE
var _playback_tick_rate: int = GhostDataManager.DEFAULT_PLAYBACK_TICK_RATE
var _playback_update_accum: float = 0.0
var _animation_speed_scale: float = 1.0
var _geometry_instances: Array[GeometryInstance3D] = []
var _last_applied_opacity: float = -1.0


func _ready() -> void:
	visible = false
	set_process(false)


func _exit_tree() -> void:
	_playing = false
	set_process(false)
	_samples.clear()
	_geometry_instances.clear()
	_visual_root = null
	_animation_player = null


func configure_visual_from_player(player: Node) -> bool:
	_clear_visual()
	var source_visual: Node3D = _find_player_visual(player)
	if source_visual == null:
		return false
	var duplicated_visual: Node = source_visual.duplicate(Node.DUPLICATE_USE_INSTANTIATION)
	if not (duplicated_visual is Node3D):
		if duplicated_visual != null:
			duplicated_visual.free()
		return false
	_visual_root = duplicated_visual as Node3D
	_visual_root.name = "Visual"
	_sanitize_visual_branch(_visual_root)
	add_child(_visual_root)
	_initialize_visual_runtime()
	return true


func _find_player_visual(player: Node) -> Node3D:
	if player == null or not is_instance_valid(player):
		return null
	var model_root_value: Variant = player.get("model_root")
	var model_root: Node3D = model_root_value as Node3D
	if model_root == null or not is_instance_valid(model_root):
		return null
	var animation_tree_value: Variant = player.get("anim_tree")
	var player_animation_tree: AnimationTree = animation_tree_value as AnimationTree
	if player_animation_tree != null and is_instance_valid(player_animation_tree):
		var animated_visual: Node = player_animation_tree.get_parent()
		if animated_visual is Node3D and animated_visual != model_root:
			return animated_visual as Node3D
	for child: Node in model_root.get_children():
		if child is Node3D and child.find_child("AnimationPlayer", true, false) != null:
			return child as Node3D
	return null


func _sanitize_visual_branch(node: Node) -> void:
	for child: Node in node.get_children():
		if _is_non_visual_node(child):
			node.remove_child(child)
			child.free()
			continue
		_sanitize_visual_branch(child)
	if node.get_script() != null:
		node.set_script(null)


func _is_non_visual_node(node: Node) -> bool:
	return (
		node is AnimationTree
		or node is AudioStreamPlayer
		or node is AudioStreamPlayer2D
		or node is AudioStreamPlayer3D
		or node is Camera3D
		or node is CollisionObject3D
		or node is CPUParticles3D
		or node is GPUParticles3D
		or node is Light3D
		or node is RayCast3D
		or node is ShapeCast3D
	)


func _initialize_visual_runtime() -> void:
	_animation_player = _visual_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_set_animation_processing(false)
	_disable_secondary_motion()
	_cache_geometry_instances()
	_disable_additional_shader_passes()
	_set_shadow_casting(false)
	_last_applied_opacity = -1.0
	_apply_visual_opacity(0.0)


func _clear_visual() -> void:
	_animation_player = null
	_geometry_instances.clear()
	_last_applied_opacity = -1.0
	if _visual_root == null or not is_instance_valid(_visual_root):
		_visual_root = null
		return
	remove_child(_visual_root)
	_visual_root.free()
	_visual_root = null


func set_ghost_data(data: Dictionary) -> void:
	_samples.clear()
	var src = data.get("samples", [])
	if src is Array:
		var source_samples: Array = src
		var previous_source_time: float = -1.0
		var next_kept_time: float = 0.0
		var sample_interval: float = GhostDataManager.get_tick_interval(_playback_tick_rate)
		var final_sample: Dictionary = {}
		for sample_value in source_samples:
			if not (sample_value is Dictionary):
				continue
			var sample: Dictionary = sample_value
			var sample_time: float = float(sample.get("t", 0.0))
			if sample_time < previous_source_time:
				continue
			previous_source_time = sample_time
			final_sample = sample
			if _samples.is_empty() or sample_time + 0.0001 >= next_kept_time:
				_samples.append(sample)
				next_kept_time = sample_time + sample_interval
		if not final_sample.is_empty():
			var final_time: float = float(final_sample.get("t", 0.0))
			var kept_final_time: float = float((_samples[_samples.size() - 1] as Dictionary).get("t", 0.0)) if not _samples.is_empty() else -1.0
			if final_time > kept_final_time + 0.0001:
				_samples.append(final_sample)
	_duration = float(data.get("finish_time", 0.0))
	if not _samples.is_empty():
		_duration = max(_duration, float((_samples[_samples.size() - 1] as Dictionary).get("t", 0.0)))
	_source_tick_rate = GhostDataManager.get_payload_tick_rate(data)
	_playback_time = 0.0
	_playback_update_accum = 0.0
	_sample_cursor = 0
	_playing = false
	set_process(false)
	_current_clip = &""
	if _samples.is_empty():
		visible = false
		return
	visible = false
	_apply_sample(_samples[0])
	if _animation_player != null:
		_animation_player.speed_scale = 0.0
	_apply_visual_opacity(0.0)


func set_playback_tick_rate(tick_rate: int) -> void:
	_playback_tick_rate = GhostDataManager.normalize_recording_tick_rate(tick_rate)
	_playback_update_accum = 0.0


func set_visual_opacity(opacity: float) -> void:
	visual_opacity = clamp(opacity, 0.05, 1.0)
	if visible:
		_apply_visual_fade()


func get_source_tick_rate() -> int:
	return _source_tick_rate


func get_playback_progress() -> float:
	if _duration <= 0.0:
		return 0.0
	return clamp(_playback_time / _duration, 0.0, 1.0)


func seek_playback(time_seconds: float) -> void:
	if _samples.is_empty():
		return
	_playback_time = clamp(time_seconds, 0.0, _duration)
	_sample_cursor = _find_sample_index(_playback_time)
	_playback_update_accum = 0.0
	_apply_time(_playback_time)
	if not _playing and _animation_player != null:
		_animation_player.speed_scale = 0.0
	_apply_visual_fade()


func pause_playback() -> void:
	_playing = false
	set_process(false)
	if _animation_player != null:
		_animation_player.speed_scale = 0.0
	_set_animation_processing(false)


func resume_playback() -> void:
	if _samples.is_empty() or _playback_time >= _duration:
		return
	_playing = true
	visible = true
	set_process(true)
	_set_animation_processing(true)
	if _animation_player != null:
		_animation_player.speed_scale = _animation_speed_scale


func start_playback() -> void:
	if _samples.is_empty():
		return
	_playback_time = 0.0
	_playback_update_accum = 0.0
	_sample_cursor = 0
	_playing = true
	visible = true
	set_process(true)
	_set_animation_processing(true)
	_apply_sample(_samples[0])
	_apply_visual_fade()


func stop_playback() -> void:
	_playing = false
	set_process(false)
	if _animation_player != null:
		_animation_player.speed_scale = 0.0
	_set_animation_processing(false)


func clear_playback() -> void:
	_playing = false
	set_process(false)
	_samples.clear()
	_duration = 0.0
	_playback_time = 0.0
	_current_clip = &""
	_sample_cursor = 0
	_playback_update_accum = 0.0
	_apply_visual_opacity(0.0)
	visible = false
	if _animation_player != null:
		_animation_player.stop()
	_set_animation_processing(false)


func _process(delta: float) -> void:
	if not _playing or _samples.is_empty():
		return
	if get_tree().paused:
		return
	var frame_delta: float = max(delta, 0.0)
	_playback_time += frame_delta
	_playback_update_accum += frame_delta
	var reached_end: bool = _playback_time >= _duration
	if _playback_time >= _duration:
		_playback_time = _duration
		_playing = false
	var update_interval: float = GhostDataManager.get_tick_interval(_playback_tick_rate)
	if _playback_update_accum >= update_interval or reached_end:
		_playback_update_accum = fmod(_playback_update_accum, update_interval)
		_apply_time(_playback_time)
	_apply_visual_fade()
	if reached_end:
		set_process(false)
		if _animation_player != null:
			_animation_player.speed_scale = 0.0
		_set_animation_processing(false)
		visible = false
		playback_finished.emit()


func _apply_time(playback_time: float) -> void:
	if _samples.is_empty():
		return
	if _samples.size() == 1:
		_apply_sample(_samples[0])
		return
	var last_index: int = _samples.size() - 1
	while _sample_cursor < last_index - 1 and playback_time > float((_samples[_sample_cursor + 1] as Dictionary).get("t", 0.0)):
		_sample_cursor += 1
	while _sample_cursor > 0 and playback_time < float((_samples[_sample_cursor] as Dictionary).get("t", 0.0)):
		_sample_cursor -= 1
	if _sample_cursor >= last_index:
		_apply_sample(_samples[last_index])
		return
	var a: Dictionary = _samples[_sample_cursor]
	var b: Dictionary = _samples[_sample_cursor + 1]
	var ta: float = float(a.get("t", 0.0))
	var tb: float = float(b.get("t", ta))
	var alpha: float = 0.0
	var span: float = tb - ta
	if span > 0.0001:
		alpha = clamp((playback_time - ta) / span, 0.0, 1.0)
	_apply_interpolated_sample(a, b, alpha)


func _apply_interpolated_sample(a: Dictionary, b: Dictionary, alpha: float) -> void:
	var pos_a := _vec3_from_variant(a.get("position", []))
	var pos_b := _vec3_from_variant(b.get("position", []))
	var rot_a := _quat_from_variant(a.get("rotation", []))
	var rot_b := _quat_from_variant(b.get("rotation", []))
	var rot := rot_a.slerp(rot_b, alpha)
	var pos := pos_a.lerp(pos_b, alpha)
	global_transform = Transform3D(Basis(rot).orthonormalized(), pos)
	var speed : float = lerp(float(a.get("speed", 0.0)), float(b.get("speed", 0.0)), alpha)
	var state_sample: Dictionary = a if alpha < 0.5 else b
	var airborne: bool = bool(state_sample.get("airborne", false))
	var rolling: bool = bool(state_sample.get("rolling", false))
	var grinding: bool = bool(state_sample.get("grinding", false))
	_apply_animation(speed, airborne, rolling, grinding)


func _apply_sample(sample) -> void:
	if not (sample is Dictionary):
		return
	var data: Dictionary = sample
	var rot := _quat_from_variant(data.get("rotation", []))
	var pos := _vec3_from_variant(data.get("position", []))
	global_transform = Transform3D(Basis(rot).orthonormalized(), pos)
	_apply_animation(float(data.get("speed", 0.0)), bool(data.get("airborne", false)), bool(data.get("rolling", false)), bool(data.get("grinding", false)))


func _apply_animation(speed: float, airborne: bool, rolling: bool, grinding: bool) -> void:
	if _animation_player == null:
		return
	var clip: StringName = &"Idle"
	if grinding:
		clip = &"RailGrind"
	elif rolling:
		clip = &"RollFloor"
	elif airborne:
		clip = &"Fall"
	elif speed >= 90.0:
		clip = &"Move4_TopRun"
	elif speed >= 30.0:
		clip = &"Move3_Run"
	elif speed >= 4.0:
		clip = &"Move1_Walk"
	var speed_scale := 1.0
	if clip == &"Move1_Walk":
		speed_scale = clamp(speed / 18.0, 0.75, 1.75)
	elif clip == &"Move3_Run":
		speed_scale = clamp(speed / 42.0, 0.8, 2.0)
	elif clip == &"Move4_TopRun":
		speed_scale = clamp(speed / 90.0, 0.85, 2.5)
	elif clip == &"RollFloor":
		speed_scale = clamp(speed / 50.0, 0.75, 2.5)
	elif clip == &"RailGrind":
		speed_scale = clamp(speed / 65.0, 0.8, 2.0)
	else:
		speed_scale = 1.0
	if _current_clip != clip or not _animation_player.is_playing():
		if _animation_player.has_animation(clip):
			_animation_player.play(clip)
			_current_clip = clip
	if _animation_player.is_playing():
		_animation_speed_scale = speed_scale
		_animation_player.speed_scale = speed_scale


func _vec3_from_variant(value: Variant) -> Vector3:
	if value is Array:
		var arr: Array = value
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


func _quat_from_variant(value: Variant) -> Quaternion:
	if value is Array:
		var arr: Array = value
		if arr.size() >= 4:
			return Quaternion(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3])).normalized()
	return Quaternion.IDENTITY


func _find_sample_index(time_seconds: float) -> int:
	if _samples.size() <= 1:
		return 0
	var low: int = 0
	var high: int = _samples.size() - 1
	while low < high:
		var midpoint: int = int((low + high + 1) / 2)
		var midpoint_time: float = float((_samples[midpoint] as Dictionary).get("t", 0.0))
		if midpoint_time <= time_seconds:
			low = midpoint
		else:
			high = midpoint - 1
	return min(low, _samples.size() - 2)


func _cache_geometry_instances() -> void:
	_geometry_instances.clear()
	var visual: Node = _visual_root if _visual_root != null else self
	for node: Node in visual.find_children("*", "GeometryInstance3D", true, false):
		if node is GeometryInstance3D:
			_geometry_instances.append(node as GeometryInstance3D)


func _disable_secondary_motion() -> void:
	if _visual_root == null:
		return
	for node: Node in _visual_root.find_children("*", "SpringBoneSimulator3D", true, false):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.set_process(false)
		node.set_physics_process(false)


func _disable_additional_shader_passes() -> void:
	for geometry: GeometryInstance3D in _geometry_instances:
		if geometry == null or not is_instance_valid(geometry):
			continue
		geometry.material_overlay = null
		if geometry.material_override != null:
			geometry.material_override = _copy_material_without_additional_passes(
				geometry.material_override
			)
			continue
		if not (geometry is MeshInstance3D):
			continue
		var mesh_instance: MeshInstance3D = geometry as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var active_material: Material = mesh_instance.get_active_material(surface_index)
			if active_material == null or active_material.next_pass == null:
				continue
			mesh_instance.set_surface_override_material(
				surface_index,
				_copy_material_without_additional_passes(active_material)
			)


func _copy_material_without_additional_passes(source_material: Material) -> Material:
	if source_material == null or source_material.next_pass == null:
		return source_material
	var base_material: Material = source_material.duplicate(false) as Material
	if base_material == null:
		return source_material
	base_material.next_pass = null
	return base_material


func _set_animation_processing(enabled: bool) -> void:
	if _animation_player == null:
		return
	_animation_player.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func _apply_visual_fade() -> void:
	if visual_fade_duration <= 0.0 or _duration <= 0.0:
		_apply_visual_opacity(visual_opacity)
		return
	var fade_in: float = clamp(_playback_time / visual_fade_duration, 0.0, 1.0)
	var fade_out: float = clamp((_duration - _playback_time) / visual_fade_duration, 0.0, 1.0)
	_apply_visual_opacity(visual_opacity * min(fade_in, fade_out))


func _apply_visual_opacity(opacity: float) -> void:
	var clamped_opacity: float = clamp(opacity, 0.0, 1.0)
	if is_equal_approx(clamped_opacity, _last_applied_opacity):
		return
	_last_applied_opacity = clamped_opacity
	for geometry: GeometryInstance3D in _geometry_instances:
		if geometry != null and is_instance_valid(geometry):
			geometry.transparency = 1.0 - clamped_opacity


func _set_shadow_casting(enabled: bool) -> void:
	var visual := _visual_root if _visual_root != null else self
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if node is MeshInstance3D:
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

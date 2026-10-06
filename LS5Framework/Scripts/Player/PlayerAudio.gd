extends RefCounted
class_name PlayerAudio

# SUMMARY:
# - Centralized audio helpers for the player (footsteps, jumps, spindash, and action SFX).
# - Reads all audio nodes and settings from the owning player; does not own any nodes.
# - Keeps randomization and network SFX replication in one place.

enum FootstepSurface { DEFAULT, GRAVEL, SAND, TILE, DIRT, WOOD, GRASS, STONE, WATER, METAL }

const VOICE_PRIORITY_IDLE: int = 0
const VOICE_PRIORITY_ACTION: int = 1
const VOICE_PRIORITY_EMOTE: int = 2
const VOICE_PRIORITY_DIALOGUE: int = 5
const VOICE_PRIORITY_HURT: int = 10

var _owner: Node = null
var _last_footstep_index: int = -1
var _last_footstep_surface: int = FootstepSurface.DEFAULT
var _dbg_last_surface_name: String = ""
var _dbg_last_surface_type: String = "DEFAULT"
var _dbg_last_surface_candidates: String = ""
var _mesh_face_counts: Dictionary = {}
var _surface_result_cache: Dictionary = {}
var _object_material_property_cache: Dictionary = {}
var _last_jump_index: int = -1
var _last_jumpdash_index: int = -1
var _last_voice_index: int = -1
var _current_voice_priority: int = 0
var _voice_queue: Array[Dictionary] = []
var _emote_global_deadline_ms: int = 0
var _emote_deadlines_ms: Dictionary = {}
var _last_emote_clips: Dictionary = {}
var _dialogue_finished_connected: bool = false
var _spindash_loop_active: bool = false
var _barrier_blast_wind_mix: float = 0.0
var _barrier_blast_wind_hold_volume_db: float = -80.0
var _barrier_blast_wind_hold_pitch: float = 1.0
var _barrier_blast_wind_hold_intensity: float = 0.0
var _barrier_blast_wet_player: AudioStreamPlayer3D = null
var _drift_turn_volume_t_current: float = 0.0
var _engine_volume_speed_t_current: float = 0.0
var _engine_pitch_speed_t_current: float = 0.0
var _roll_active_last: bool = false
var _roll_loop_volume_speed_t_current: float = 0.0
var _roll_loop_pitch_speed_t_current: float = 0.0
var _skid_surface: int = FootstepSurface.DEFAULT
var _skid_stream: AudioStream = null


func _init(owner: Node) -> void:
	_owner = owner


func stop_remote_audio() -> void:
	_voice_queue.clear()
	_current_voice_priority = 0
	_spindash_loop_active = false
	if _owner == null or not is_instance_valid(_owner):
		return
	for node in _owner.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
	for node in _owner.find_children("*", "AudioStreamPlayer2D", true, false):
		(node as AudioStreamPlayer2D).stop()
	for node in _owner.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()


func play_item_collection_sound(item_id: StringName) -> bool:
	var p: Node = _owner
	if p == null or not is_instance_valid(p) or item_id == &"":
		return false
	if p._network_is_active() and not p.is_multiplayer_authority():
		return false
	var association: ItemAudioAssociation = _get_item_audio_association(item_id)
	if association == null or association.collection_sound == null:
		return false
	var audio_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	audio_player.add_to_group(&"LevelTransient")
	audio_player.name = "ItemCollectionAudio"
	audio_player.stream = association.collection_sound
	audio_player.volume_db = association.volume_db
	audio_player.pitch_scale = max(association.pitch_scale, 0.01)
	audio_player.bus = p.item_collection_sound_bus
	if item_id == &"rings":
		audio_player.bus = Ring.get_next_pickup_audio_bus(p.item_collection_sound_bus)
	audio_player.max_distance = max(p.item_collection_sound_max_distance, 0.0)
	var audio_parent: Node = p.get_tree().current_scene if p.get_tree() != null else null
	if audio_parent == null:
		audio_parent = p.get_parent()
	if audio_parent == null:
		audio_player.queue_free()
		return false
	audio_parent.add_child(audio_player)
	audio_player.top_level = true
	if p is Node3D:
		audio_player.global_transform = (p as Node3D).global_transform
	audio_player.finished.connect(Callable(audio_player, "queue_free"))
	audio_player.play()
	return true


func _get_item_audio_association(item_id: StringName) -> ItemAudioAssociation:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return null
	for association_resource: Resource in p.item_audio_associations:
		if not (association_resource is ItemAudioAssociation):
			continue
		var association: ItemAudioAssociation = association_resource as ItemAudioAssociation
		if association.item_id == item_id:
			return association
	return null


func _play_random_sfx_from_list(
		player: AudioStreamPlayer3D,
		sounds: Array[AudioStream],
		last_index: int,
		avoid_repeat: bool = true
	) -> int:
	# SUMMARY: Play a random sound from a list, optionally avoiding repeats.
	# STEPS:
	# - Step 1: Validate the player and list.
	# - Step 2: Choose an index (avoid repeats when requested).
	# - Step 3: Assign the stream and play.
	if player == null or sounds.is_empty():
		return last_index

	var idx: int
	if avoid_repeat and sounds.size() > 1 and last_index >= 0 and last_index < sounds.size():
		idx = randi_range(0, sounds.size() - 2)
		if idx >= last_index:
			idx += 1
	else:
		idx = randi_range(0, sounds.size() - 1)

	player.stream = sounds[idx]
	player.play()
	return idx


func _play_indexed_sfx_from_list(player: AudioStreamPlayer3D, sounds: Array[AudioStream], index: int) -> bool:
	if player == null or sounds.is_empty():
		return false
	if index < 0 or index >= sounds.size():
		return false
	player.stream = sounds[index]
	player.play()
	return true


func play_voice_clips(
		sounds: Array[AudioStream],
		chance: float = 1.0,
		priority: int = VOICE_PRIORITY_ACTION,
		queue_if_blocked: bool = false,
		_allow_non_authority: bool = false
	) -> void:
	var p: Node = _owner
	if not p or not is_instance_valid(p):
		return
	if p._network_is_active() and p.network_replication_enabled and not p.is_multiplayer_authority():
		return
	if sounds.is_empty():
		return
	var clamped_chance: float = clamp(chance, 0.0, 1.0)
	if clamped_chance <= 0.0:
		return
	if clamped_chance < 1.0 and randf() > clamped_chance:
		return
	var player: AudioStreamPlayer3D = p.get_dialogue_player()
	if not player:
		return
	_ensure_dialogue_finished_connection(player)
	var voice_priority: int = max(priority, 0)
	if player.playing:
		if voice_priority > _current_voice_priority and not queue_if_blocked:
			player.stop()
		else:
			if queue_if_blocked:
				_queue_voice_clips(sounds, voice_priority)
			return
	if voice_priority >= VOICE_PRIORITY_HURT:
		_voice_queue.clear()
	_current_voice_priority = voice_priority
	_last_voice_index = _play_random_sfx_from_list(player, sounds, _last_voice_index, true)
	_replicate_voice(player)


func play_emote_voice(emote_id: StringName) -> bool:
	var p: Node = _owner
	if not is_instance_valid(p) or p._is_dead or not p._network_is_local_authority():
		return false
	var character_profile: CharacterSettingsProfile = p.character_settings_profile
	if not character_profile or not character_profile.emote_voice_profile:
		return false
	var profile: EmoteVoiceProfile = character_profile.emote_voice_profile
	var entry: EmoteVoiceEntry = profile.get_entry(emote_id)
	if not entry:
		return false
	var now_ms: int = Time.get_ticks_msec()
	if profile.cooldowns_enabled and (now_ms < _emote_global_deadline_ms or now_ms < int(_emote_deadlines_ms.get(emote_id, 0))):
		return false
	var player: AudioStreamPlayer3D = p.get_dialogue_player()
	if not player or (player.playing and (not profile.allow_voice_interruption or _current_voice_priority > VOICE_PRIORITY_EMOTE)):
		return false
	var previous: AudioStream = _last_emote_clips.get(emote_id) as AudioStream
	var clips: Array[AudioStream] = []
	var fresh_clips: Array[AudioStream] = []
	for clip: AudioStream in entry.clips:
		if clip and not clips.has(clip):
			clips.append(clip)
			if clip != previous:
				fresh_clips.append(clip)
	if clips.is_empty():
		return false
	var selected: AudioStream = clips.pick_random() if fresh_clips.is_empty() else fresh_clips.pick_random()
	_ensure_dialogue_finished_connection(player)
	if player.playing:
		player.stop()
	_current_voice_priority = VOICE_PRIORITY_EMOTE
	player.stream = selected
	player.play()
	if not player.playing:
		_current_voice_priority = 0
		return false
	_last_emote_clips[emote_id] = selected
	if profile.cooldowns_enabled:
		_emote_global_deadline_ms = now_ms + ceili(maxf(profile.global_cooldown_seconds, 0.0) * 1000.0)
		var same_cooldown: float = entry.cooldown_override_seconds if entry.cooldown_override_seconds >= 0.0 else profile.same_emote_cooldown_seconds
		_emote_deadlines_ms[emote_id] = now_ms + ceili(maxf(same_cooldown, 0.0) * 1000.0)
	else:
		_emote_global_deadline_ms = 0
		_emote_deadlines_ms.clear()
	_replicate_voice(player)
	return true


func _queue_voice_clips(sounds: Array[AudioStream], priority: int) -> void:
	var queue_item: Dictionary = {
		"sounds": sounds,
		"priority": max(priority, 0),
	}
	_voice_queue.append(queue_item)
	_voice_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("priority", 0)) > int(b.get("priority", 0)))


func _ensure_dialogue_finished_connection(player: AudioStreamPlayer3D) -> void:
	if _dialogue_finished_connected:
		return
	var finished_callable: Callable = Callable(self, "_on_dialogue_player_finished")
	if not player.finished.is_connected(finished_callable):
		player.finished.connect(finished_callable)
	_dialogue_finished_connected = true


func _on_dialogue_player_finished() -> void:
	_current_voice_priority = 0
	_play_next_queued_voice()


func _play_next_queued_voice() -> void:
	var p: Node = _owner
	if not p or not is_instance_valid(p):
		_voice_queue.clear()
		return
	var player: AudioStreamPlayer3D = p.get_dialogue_player()
	if not player:
		_voice_queue.clear()
		return
	_ensure_dialogue_finished_connection(player)
	if player.playing or _voice_queue.is_empty():
		return
	var queue_item: Dictionary = _voice_queue.pop_front()
	var sounds: Array[AudioStream] = []
	var queued_sounds: Variant = queue_item.get("sounds", [])
	if queued_sounds is Array:
		sounds.assign(queued_sounds as Array)
	if sounds.is_empty():
		_play_next_queued_voice()
		return
	_current_voice_priority = int(queue_item.get("priority", 0))
	_last_voice_index = _play_random_sfx_from_list(player, sounds, _last_voice_index, true)
	_replicate_voice(player)


func _get_mesh_face_counts(mesh_res: ArrayMesh) -> Array[int]:
	var key: int = mesh_res.get_rid().get_id()
	if _mesh_face_counts.has(key):
		return _mesh_face_counts[key]
	var counts: Array[int] = []
	var surf_count: int = mesh_res.get_surface_count()
	for i in range(surf_count):
		var arrays = mesh_res.surface_get_arrays(i)
		var idx_arr = arrays[ArrayMesh.ARRAY_INDEX]
		var vert_arr = arrays[ArrayMesh.ARRAY_VERTEX]
		var tri_count: int = 0
		if idx_arr != null and idx_arr.size() > 0:
			tri_count = idx_arr.size() / 3
		elif vert_arr != null:
			tri_count = vert_arr.size() / 3
		counts.append(tri_count)
	_mesh_face_counts[key] = counts
	return counts


func _resolve_footstep_surface(ray: RayCast3D) -> int:
	_dbg_last_surface_name = ""
	_dbg_last_surface_type = FootstepSurface.keys()[FootstepSurface.DEFAULT]
	_dbg_last_surface_candidates = ""

	if ray == null or not ray.is_colliding():
		return FootstepSurface.DEFAULT

	var collider: Node = ray.get_collider()
	if collider == null or not is_instance_valid(collider):
		return FootstepSurface.DEFAULT

	var face_idx: int = ray.get_collision_face_index()
	var cache_key: String = "%d:%d" % [collider.get_instance_id(), face_idx]
	if _surface_result_cache.has(cache_key):
		var cached: Dictionary = _surface_result_cache[cache_key]
		_dbg_last_surface_name = String(cached.get("name", ""))
		_dbg_last_surface_type = String(cached.get("type", FootstepSurface.keys()[FootstepSurface.DEFAULT]))
		_dbg_last_surface_candidates = String(cached.get("checked", "cached"))
		return int(cached.get("surface", FootstepSurface.DEFAULT))

	var all_candidates: Array[String] = []
	var mesh_inst: MeshInstance3D = null

	var node: Node = collider
	for _depth in range(8):
		if node == null:
			break
		if mesh_inst == null and node is MeshInstance3D:
			mesh_inst = node as MeshInstance3D
		var object_names: Array[String] = []
		_add_object_material_keyword_names(object_names, node)
		_append_surface_candidates(all_candidates, object_names)
		var object_result: int = _match_surface_names(object_names)
		if object_result >= 0:
			_dbg_last_surface_candidates = _format_surface_candidates(all_candidates)
			_dbg_last_surface_type = FootstepSurface.keys()[object_result]
			_store_surface_cache(cache_key, object_result)
			return object_result
		node = node.get_parent()

	if mesh_inst == null:
		_dbg_last_surface_candidates = "collider=%s; checked=%s" % [collider.name, _format_surface_candidates(all_candidates)]
		_store_surface_cache(cache_key, FootstepSurface.DEFAULT)
		return FootstepSurface.DEFAULT

	var mesh_res: Mesh = mesh_inst.mesh
	if mesh_res == null:
		_dbg_last_surface_candidates = _format_surface_candidates(all_candidates)
		_store_surface_cache(cache_key, FootstepSurface.DEFAULT)
		return FootstepSurface.DEFAULT

	var general_names: Array[String] = []
	_add_material_keyword_names(general_names, mesh_inst.material_override)
	_add_object_material_keyword_names(general_names, mesh_res)
	_append_surface_candidates(all_candidates, general_names)
	var general_result: int = _match_surface_names(general_names)
	if general_result >= 0:
		_dbg_last_surface_candidates = _format_surface_candidates(all_candidates)
		_dbg_last_surface_type = FootstepSurface.keys()[general_result]
		_store_surface_cache(cache_key, general_result)
		return general_result

	if mesh_res is ArrayMesh:
		var target_surface_idx: int = -1
		var face_counts: Array[int] = _get_mesh_face_counts(mesh_res as ArrayMesh)
		var face_count_acc: int = 0
		for i in range(face_counts.size()):
			if face_idx < face_count_acc + face_counts[i]:
				target_surface_idx = i
				break
			face_count_acc += face_counts[i]

		if target_surface_idx >= 0:
			var names_to_check: Array[String] = _get_surface_keyword_names(mesh_inst, mesh_res, target_surface_idx)
			_append_surface_candidates(all_candidates, names_to_check)
			var result: int = _match_surface_names(names_to_check)
			if result >= 0:
				_dbg_last_surface_candidates = _format_surface_candidates(all_candidates)
				_dbg_last_surface_type = FootstepSurface.keys()[result]
				_store_surface_cache(cache_key, result)
				return result

	_dbg_last_surface_candidates = _format_surface_candidates(all_candidates)
	_store_surface_cache(cache_key, FootstepSurface.DEFAULT)
	return FootstepSurface.DEFAULT


func _store_surface_cache(cache_key: String, surface: int) -> void:
	if _surface_result_cache.size() > 512:
		_surface_result_cache.clear()
	_surface_result_cache[cache_key] = {
		"surface": surface,
		"name": _dbg_last_surface_name,
		"type": _dbg_last_surface_type,
		"checked": _dbg_last_surface_candidates
	}


func _match_surface_names(names_to_check: Array[String]) -> int:
	for name_str in names_to_check:
		var result: int = _match_surface_keyword(name_str)
		if result >= 0:
			_dbg_last_surface_name = name_str
			return result
	return -1


func _append_surface_candidates(all_candidates: Array[String], names_to_check: Array[String]) -> void:
	for name_str in names_to_check:
		if not all_candidates.has(name_str):
			all_candidates.append(name_str)


func _object_has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	var cache_key: String = "%s:%s" % [object.get_class(), property_name]
	if _object_material_property_cache.has(cache_key):
		return bool(_object_material_property_cache[cache_key])
	for entry in object.get_property_list():
		if typeof(entry) == TYPE_DICTIONARY and entry.has("name"):
			if String(entry["name"]) == property_name:
				_object_material_property_cache[cache_key] = true
				return true
	_object_material_property_cache[cache_key] = false
	return false


func _format_surface_candidates(names_to_check: Array[String]) -> String:
	var packed: PackedStringArray = PackedStringArray()
	var count: int = min(names_to_check.size(), 12)
	for i in range(count):
		packed.append(names_to_check[i])
	if names_to_check.size() > count:
		packed.append("+%d more" % (names_to_check.size() - count))
	return ", ".join(packed)


func debug_update_surface_probe(ray: RayCast3D) -> void:
	_resolve_footstep_surface(ray)


func _get_surface_keyword_names(mesh_inst: MeshInstance3D, mesh_res: Mesh, surface_idx: int) -> Array[String]:
	var names_to_check: Array[String] = []

	_add_material_keyword_names(names_to_check, mesh_inst.material_override)

	var mat: Material = mesh_inst.get_surface_override_material(surface_idx)
	if mat == null and mesh_res is ArrayMesh:
		mat = (mesh_res as ArrayMesh).surface_get_material(surface_idx)
	_add_material_keyword_names(names_to_check, mat)
	_add_object_material_keyword_names(names_to_check, mesh_res)

	if mesh_res is ArrayMesh:
		var array_mesh: ArrayMesh = mesh_res as ArrayMesh
		var surf_name: String = array_mesh.surface_get_name(surface_idx).to_lower()
		if not surf_name.is_empty() and not names_to_check.has(surf_name):
			names_to_check.append(surf_name)

	return names_to_check


func _add_object_material_keyword_names(names_to_check: Array[String], object: Object) -> void:
	if object == null:
		return
	if _object_has_property(object, "material_override"):
		var material_override_value = object.get("material_override")
		if material_override_value is Material:
			_add_material_keyword_names(names_to_check, material_override_value)
	if _object_has_property(object, "material"):
		var material_value = object.get("material")
		if material_value is Material:
			_add_material_keyword_names(names_to_check, material_value)


func _add_material_keyword_names(names_to_check: Array[String], mat: Material) -> void:
	if mat == null:
		return
	var resource_name: String = mat.resource_name.to_lower()
	if not resource_name.is_empty() and not names_to_check.has(resource_name):
		names_to_check.append(resource_name)
	var resource_path: String = mat.resource_path.get_file().get_basename().to_lower()
	if not resource_path.is_empty() and not names_to_check.has(resource_path):
		names_to_check.append(resource_path)


func _match_surface_keyword(name_str: String) -> int:
	if "gravel" in name_str or "grv" in name_str or "gvl" in name_str:
		return FootstepSurface.GRAVEL
	if "snd" in name_str or "sand" in name_str:
		return FootstepSurface.SAND
	if "til" in name_str or "tile" in name_str:
		return FootstepSurface.TILE
	if "drt" in name_str or "dirt" in name_str:
		return FootstepSurface.DIRT
	if "wod" in name_str or "wood" in name_str:
		return FootstepSurface.WOOD
	if "grs" in name_str or "grass" in name_str:
		return FootstepSurface.GRASS
	if "stn" in name_str or "stone" in name_str:
		return FootstepSurface.STONE
	if "wtr" in name_str or "water" in name_str:
		return FootstepSurface.WATER
	if "mtl" in name_str or "metal" in name_str:
		return FootstepSurface.METAL
	if "flr" in name_str or "floor" in name_str:
		return FootstepSurface.DEFAULT
	return -1


func _get_footstep_sounds_for_surface(surface: int) -> Array[AudioStream]:
	var p: Node = _owner
	match surface:
		FootstepSurface.GRAVEL:
			if not p.footstep_sounds_gravel.is_empty():
				return p.footstep_sounds_gravel
		FootstepSurface.SAND:
			if not p.footstep_sounds_sand.is_empty():
				return p.footstep_sounds_sand
		FootstepSurface.TILE:
			if not p.footstep_sounds_tile.is_empty():
				return p.footstep_sounds_tile
		FootstepSurface.DIRT:
			if not p.footstep_sounds_dirt.is_empty():
				return p.footstep_sounds_dirt
		FootstepSurface.WOOD:
			if not p.footstep_sounds_wood.is_empty():
				return p.footstep_sounds_wood
		FootstepSurface.GRASS:
			if not p.footstep_sounds_grass.is_empty():
				return p.footstep_sounds_grass
		FootstepSurface.STONE:
			if not p.footstep_sounds_stone.is_empty():
				return p.footstep_sounds_stone
		FootstepSurface.WATER:
			if not p.footstep_sounds_water.is_empty():
				return p.footstep_sounds_water
		FootstepSurface.METAL:
			if not p.footstep_sounds_metal.is_empty():
				return p.footstep_sounds_metal
	return p.footstep_sounds_default


func _get_skid_sound_for_surface(surface: int) -> AudioStream:
	var p: Node = _owner
	match surface:
		FootstepSurface.GRAVEL:
			if p.skid_sound_gravel != null:
				return p.skid_sound_gravel
		FootstepSurface.SAND:
			if p.skid_sound_sand != null:
				return p.skid_sound_sand
		FootstepSurface.TILE:
			if p.skid_sound_tile != null:
				return p.skid_sound_tile
		FootstepSurface.DIRT:
			if p.skid_sound_dirt != null:
				return p.skid_sound_dirt
		FootstepSurface.WOOD:
			if p.skid_sound_wood != null:
				return p.skid_sound_wood
		FootstepSurface.GRASS:
			if p.skid_sound_grass != null:
				return p.skid_sound_grass
		FootstepSurface.STONE:
			if p.skid_sound_stone != null:
				return p.skid_sound_stone
		FootstepSurface.WATER:
			if p.skid_sound_water != null:
				return p.skid_sound_water
		FootstepSurface.METAL:
			if p.skid_sound_metal != null:
				return p.skid_sound_metal
	return p.skid_sound_default


func _get_skid_pitch_reverse_for_surface(surface: int) -> bool:
	var p: Node = _owner
	match surface:
		FootstepSurface.GRAVEL:
			return p.skid_pitch_reverse_gravel
		FootstepSurface.SAND:
			return p.skid_pitch_reverse_sand
		FootstepSurface.TILE:
			return p.skid_pitch_reverse_tile
		FootstepSurface.DIRT:
			return p.skid_pitch_reverse_dirt
		FootstepSurface.WOOD:
			return p.skid_pitch_reverse_wood
		FootstepSurface.GRASS:
			return p.skid_pitch_reverse_grass
		FootstepSurface.STONE:
			return p.skid_pitch_reverse_stone
		FootstepSurface.WATER:
			return p.skid_pitch_reverse_water
		FootstepSurface.METAL:
			return p.skid_pitch_reverse_metal
	return p.skid_pitch_reverse_default


func _resolve_skid_surface(p: Node) -> int:
	if p._running_on_water_surface or p._fully_submerged or p._head_in_water_volume:
		_dbg_last_surface_name = "water"
		_dbg_last_surface_type = FootstepSurface.keys()[FootstepSurface.WATER]
		return FootstepSurface.WATER

	var ray: RayCast3D = p.ground_ray if (p.ground_ray != null and is_instance_valid(p.ground_ray)) else null
	var surface: int = _resolve_footstep_surface(ray)
	_dbg_last_surface_type = FootstepSurface.keys()[surface]
	return surface


func _set_stream_loop_enabled(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return
	var plist: Array = stream.get_property_list()
	for entry in plist:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("name") and String(entry["name"]) == "loop":
			stream.set("loop", true)
			return


func _get_footstep_volume_linear() -> float:
	# SUMMARY: Convert player speed into a linear footstep volume.
	# STEPS:
	# - Step 1: Use lateral speed as the driver.
	# - Step 2: Map to the configured min/max volume range.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return 0.0

	var speed : float = p._get_lateral_speed_for_anim()
	if p.footstep_full_volume_speed <= 0.0:
		return p.footstep_max_volume

	var t: float = clamp(speed / p.footstep_full_volume_speed, 0.0, 1.0)
	return lerp(p.footstep_min_volume, p.footstep_max_volume, t)


func _play_water_surface_footstep(p: Node, foot: StringName, emit_dust: bool) -> void:
	var water_sounds: Array[AudioStream] = p.footstep_sounds_water
	if water_sounds.is_empty():
		return

	var vol_linear: float = _get_footstep_volume_linear()
	var water_player: AudioStreamPlayer3D = null
	if p.footstep_player_water != null:
		water_player = p.get_node_or_null(p.footstep_player_water) as AudioStreamPlayer3D
	if water_player == null:
		water_player = p.footstep_player
	if water_player == null:
		return

	if _last_footstep_surface != FootstepSurface.WATER:
		_last_footstep_surface = FootstepSurface.WATER
		_last_footstep_index = -1
	_dbg_last_surface_name = "water_surface"
	_dbg_last_surface_type = FootstepSurface.keys()[FootstepSurface.WATER]

	water_player.volume_db = linear_to_db(vol_linear)
	_last_footstep_index = _play_random_sfx_from_list(
		water_player,
		water_sounds,
		_last_footstep_index,
		true
	)
	_send_footstep_rpc(FootstepSurface.WATER, _last_footstep_index, vol_linear, foot, emit_dust, -1, 0.0)

	if emit_dust and p.has_method("_emit_footstep_dust"):
		p.call("_emit_footstep_dust", foot)


func _send_footstep_rpc(surface: int, index: int, volume_linear: float, foot: StringName, emit_dust: bool, water_index: int, water_volume: float) -> void:
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p._network_is_active() or not p.network_replication_enabled or not p.is_multiplayer_authority():
		return
	p.rpc("_net_play_footstep_sfx", surface, index, volume_linear, String(foot), emit_dust, water_index, water_volume)


func play_footstep(foot: StringName = &"", emit_dust: bool = false) -> void:
	# SUMMARY: Play a footstep with volume scaled by player speed.
	# STEPS:
	# - Step 1: Validate audio node.
	# - Step 2: Compute volume from speed.
	# - Step 3: Play a non-repeating footstep.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p._network_is_active() and p.network_replication_enabled and not p.is_multiplayer_authority():
		return
	if p._running_on_water_surface and p.attached:
		_play_water_surface_footstep(p, foot, emit_dust)
		return
	if p.footstep_player == null:
		return

	var ray: RayCast3D = p.ground_ray if (p.ground_ray != null and is_instance_valid(p.ground_ray)) else null

	var surface: int = _resolve_footstep_surface(ray)
	if surface != _last_footstep_surface:
		_last_footstep_surface = surface
		_last_footstep_index = -1
		_dbg_last_surface_type = FootstepSurface.keys()[surface]

	var sounds: Array[AudioStream] = _get_footstep_sounds_for_surface(surface)

	var vol_linear: float = _get_footstep_volume_linear()
	p.footstep_player.volume_db = linear_to_db(vol_linear)

	_last_footstep_index = _play_random_sfx_from_list(
		p.footstep_player,
		sounds,
		_last_footstep_index,
		true
	)

	var water_index: int = -1
	var water_volume: float = 0.0

	if emit_dust and p.has_method("_emit_footstep_dust"):
		p.call("_emit_footstep_dust", foot)

	if p._water_footstep_timer > 0.0 and p.footstep_player_water != null:
		var water_player: AudioStreamPlayer3D = p.get_node_or_null(p.footstep_player_water) as AudioStreamPlayer3D
		if water_player != null:
			var water_sounds: Array[AudioStream] = p.footstep_sounds_water
			if water_sounds.size() > 0:
				water_volume = clamp(p._water_footstep_timer / p.water_footstep_max_time, 0.0, 1.0)
				water_player.volume_db = linear_to_db(vol_linear * water_volume)
				water_index = _play_random_sfx_from_list(
					water_player,
					water_sounds,
					-1,
					true
				)
	_send_footstep_rpc(surface, _last_footstep_index, vol_linear, foot, emit_dust, water_index, water_volume)


func play_remote_footstep(surface: int, index: int, volume_linear: float, foot: StringName = &"", emit_dust: bool = false, water_index: int = -1, water_volume: float = 0.0) -> void:
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.footstep_player == null:
		return
	var footstep_player: AudioStreamPlayer3D = p.footstep_player
	if surface == FootstepSurface.WATER and p.footstep_player_water != null:
		var water_surface_player: AudioStreamPlayer3D = p.get_node_or_null(p.footstep_player_water) as AudioStreamPlayer3D
		if water_surface_player != null:
			footstep_player = water_surface_player
	var sounds: Array[AudioStream] = _get_footstep_sounds_for_surface(surface)
	footstep_player.volume_db = linear_to_db(clamp(volume_linear, 0.0, 1.0))
	_play_indexed_sfx_from_list(footstep_player, sounds, index)
	_last_footstep_surface = surface
	_last_footstep_index = index
	_dbg_last_surface_type = FootstepSurface.keys()[surface] if surface >= 0 and surface < FootstepSurface.keys().size() else FootstepSurface.keys()[FootstepSurface.DEFAULT]
	if water_index >= 0 and p.footstep_player_water != null:
		var water_player: AudioStreamPlayer3D = p.get_node_or_null(p.footstep_player_water) as AudioStreamPlayer3D
		if water_player != null:
			var water_sounds: Array[AudioStream] = p.footstep_sounds_water
			water_player.volume_db = linear_to_db(clamp(volume_linear * water_volume, 0.0, 1.0))
			_play_indexed_sfx_from_list(water_player, water_sounds, water_index)
	if emit_dust and p.has_method("_emit_footstep_dust"):
		p.call("_emit_footstep_dust", foot)


func play_landing_sound() -> void:
	# SUMMARY: Play a surface-matched landing sound at full volume.
	# STEPS:
	# - Step 1: Validate audio node.
	# - Step 2: Resolve surface and select sound bank.
	# - Step 3: Play at footstep_max_volume regardless of speed.
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p._network_is_active() and p.network_replication_enabled and not p.is_multiplayer_authority():
		return
	if p.footstep_player == null:
		return

	var ray: RayCast3D = p.ground_ray if (p.ground_ray != null and is_instance_valid(p.ground_ray)) else null

	var surface: int = _resolve_footstep_surface(ray)
	if surface != _last_footstep_surface:
		_last_footstep_surface = surface
		_last_footstep_index = -1
		_dbg_last_surface_type = FootstepSurface.keys()[surface]

	var sounds: Array[AudioStream] = _get_footstep_sounds_for_surface(surface)

	p.footstep_player.volume_db = linear_to_db(p.footstep_max_volume)

	_last_footstep_index = _play_random_sfx_from_list(
		p.footstep_player,
		sounds,
		_last_footstep_index,
		true
	)


func play_jump_sfx() -> void:
	# SUMMARY: Play a jump SFX and replicate it to peers if needed.
	# STEPS:
	# - Step 1: Validate audio node.
	# - Step 2: Pick a random sound and play it.
	# - Step 3: Send the selection over the network.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.sfx_player == null:
		return

	p.sfx_player.volume_db = linear_to_db(p.jump_volume)
	_last_jump_index = _play_random_sfx_from_list(
		p.sfx_player,
		p.jump_sounds,
		_last_jump_index,
		true
	)

	if p._network_is_active() and p.is_multiplayer_authority():
		p.rpc("_net_play_action_sfx", "jump", _last_jump_index)


func play_jumpdash_sfx() -> void:
	# SUMMARY: Play a jump-dash SFX and replicate it to peers if needed.
	# STEPS:
	# - Step 1: Validate audio node.
	# - Step 2: Pick a random sound and play it.
	# - Step 3: Send the selection over the network.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.sfx_player == null:
		return

	p.sfx_player.volume_db = linear_to_db(p.jumpdash_volume)
	_last_jumpdash_index = _play_random_sfx_from_list(
		p.sfx_player,
		p.jumpdash_sounds,
		_last_jumpdash_index,
		true
	)

	if p._network_is_active() and p.is_multiplayer_authority():
		p.rpc("_net_play_action_sfx", "jumpdash", _last_jumpdash_index)


func _start_spindash_loop_sfx(send_net: bool = true) -> void:
	# SUMMARY: Start the spindash loop and optionally replicate.
	# STEPS:
	# - Step 1: Validate the loop player and any gating rules.
	# - Step 2: Start the loop and mark it active.
	# - Step 3: Replicate if requested.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.sfx_spindash_charge_loop == null:
		return
	if p.sfx_spindash_charge_loop.playing:
		_spindash_loop_active = true
		return
	p.sfx_spindash_charge_loop.play()
	_spindash_loop_active = true

	if send_net and p._network_is_active() and p.is_multiplayer_authority():
		p.rpc("_net_play_action_sfx", "spindash_loop", -1)


func _stop_spindash_loop_sfx(send_net: bool = true) -> void:
	# SUMMARY: Stop the spindash loop and optionally replicate.
	# STEPS:
	# - Step 1: Validate the loop player and current play state.
	# - Step 2: Stop playback and mark it inactive.
	# - Step 3: Replicate if requested.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.sfx_spindash_charge_loop == null:
		_spindash_loop_active = false
		return
	if not p.sfx_spindash_charge_loop.playing:
		_spindash_loop_active = false
		return
	p.sfx_spindash_charge_loop.stop()
	_spindash_loop_active = false

	if send_net and p._network_is_active() and p.is_multiplayer_authority():
		p.rpc("_net_play_action_sfx", "spindash_loop_stop", -1)


func _play_spindash_charge_full_sfx(send_net: bool = true) -> void:
	# SUMMARY: Play the spindash full-charge SFX and optionally replicate.
	# STEPS:
	# - Step 1: Validate the player node.
	# - Step 2: Restart the sound.
	# - Step 3: Replicate if requested.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.sfx_spindash_charge_full == null:
		return
	p.sfx_spindash_charge_full.stop()
	p.sfx_spindash_charge_full.play()

	if send_net and p._network_is_active() and p.is_multiplayer_authority():
		p.rpc("_net_play_action_sfx", "spindash_full", -1)


func _play_spindash_release_sfx(send_net: bool = true) -> void:
	# SUMMARY: Play the spindash release SFX and optionally replicate.
	# STEPS:
	# - Step 1: Stop any charge sounds that are still playing.
	# - Step 2: Play the release sound.
	# - Step 3: Replicate if requested.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.sfx_spindash_release == null:
		return
	_stop_spindash_loop_sfx(false)
	p.sfx_spindash_release.stop()
	p.sfx_spindash_release.play()

	if send_net and p._network_is_active() and p.is_multiplayer_authority():
		p.rpc("_net_play_action_sfx", "spindash_release", -1)


func update_barrier_blast_audio(
		speed: float,
		gauge_fraction: float,
		is_building: bool,
		reached_full: bool,
		delta: float
	) -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return

	var wind_player: AudioStreamPlayer3D = p.sfx_barrier_blast_wind
	if wind_player != null:
		var wet_player: AudioStreamPlayer3D = _ensure_barrier_blast_wet_player(
			wind_player,
			p.barrier_blast_wind_reverb_bus
		)
		var speed_t: float = 0.0
		if p.barrier_blast_fill_min_speed > 0.0:
			if p.barrier_blast_fill_max_speed > p.barrier_blast_fill_min_speed:
				speed_t = clamp(
					(speed - p.barrier_blast_fill_min_speed) / (p.barrier_blast_fill_max_speed - p.barrier_blast_fill_min_speed),
					0.0,
					1.0
				)
			elif speed >= p.barrier_blast_fill_min_speed:
				speed_t = 1.0

		var gauge_t: float = clamp(gauge_fraction, 0.0, 1.0)
		var speed_weight: float = clamp(p.barrier_blast_wind_speed_weight, 0.0, 1.0)
		var intensity: float = clamp(speed_t * speed_weight + gauge_t * (1.0 - speed_weight), 0.0, 1.0)
		var live_volume_db: float = lerp(
			p.barrier_blast_wind_volume_min_db,
			p.barrier_blast_wind_volume_max_db,
			intensity
		)
		var live_pitch: float = lerp(
			p.barrier_blast_wind_pitch_min,
			p.barrier_blast_wind_pitch_max,
			intensity
		)
		if is_building:
			_barrier_blast_wind_hold_volume_db = live_volume_db
			_barrier_blast_wind_hold_pitch = live_pitch
			_barrier_blast_wind_hold_intensity = intensity
		var fade_time: float = p.barrier_blast_wind_fade_in_time if is_building else p.barrier_blast_wind_fade_out_time
		var target_mix: float = 1.0 if is_building else 0.0
		_barrier_blast_wind_mix = move_toward(
			_barrier_blast_wind_mix,
			target_mix,
			max(delta, 0.0) / max(fade_time, 0.01)
		)

		if is_building and not wind_player.playing:
			wind_player.volume_db = p.barrier_blast_wind_silent_db
			wind_player.pitch_scale = p.barrier_blast_wind_pitch_min
			wind_player.play()
		if is_building and wet_player != null and not wet_player.playing:
			wet_player.volume_db = p.barrier_blast_wind_silent_db
			wet_player.pitch_scale = p.barrier_blast_wind_pitch_min
			wet_player.play(wind_player.get_playback_position())
		if wind_player.playing:
			var target_volume_db: float = _barrier_blast_wind_hold_volume_db
			var target_pitch: float = _barrier_blast_wind_hold_pitch
			var target_intensity: float = _barrier_blast_wind_hold_intensity
			var mixed_linear: float = db_to_linear(target_volume_db) * _barrier_blast_wind_mix
			var silent_linear: float = db_to_linear(p.barrier_blast_wind_silent_db)
			wind_player.volume_db = linear_to_db(max(mixed_linear, silent_linear))
			wind_player.pitch_scale = target_pitch
			if wet_player != null and wet_player.playing:
				var wet_curve: float = pow(target_intensity, max(p.barrier_blast_wind_wet_curve, 0.1))
				var wet_amount: float = lerp(
					p.barrier_blast_wind_wet_amount_low,
					p.barrier_blast_wind_wet_amount_high,
					wet_curve
				)
				var wet_linear: float = mixed_linear * clamp(wet_amount, 0.0, 1.0)
				wet_player.volume_db = linear_to_db(max(wet_linear, silent_linear))
				wet_player.pitch_scale = wind_player.pitch_scale
			if not is_building and _barrier_blast_wind_mix <= 0.0:
				wind_player.stop()
				if wet_player != null:
					wet_player.stop()

	if reached_full:
		var boom_player: AudioStreamPlayer3D = p.sfx_barrier_blast_boom
		if boom_player != null:
			boom_player.stop()
			boom_player.play()


func update_speed_wind(speed: float) -> void:
	# SUMMARY: Drive a movement-speed wind loop based on current speed.
	# STEPS:
	# - Step 1: Validate the wind player.
	# - Step 2: Start/stop based on minimum speed.
	# - Step 3: Scale volume/pitch by speed ratio.
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return

	var wind_player: AudioStreamPlayer3D = p.sfx_speed_wind
	if wind_player == null:
		return

	var min_speed: float = max(p.speed_wind_min_speed, 0.0)
	if speed < min_speed:
		if wind_player.playing:
			wind_player.stop()
		return

	if not wind_player.playing:
		wind_player.play()

	var full_speed: float = max(p.speed_wind_full_speed, min_speed)
	var t: float = 1.0
	if full_speed > min_speed:
		t = clamp((speed - min_speed) / (full_speed - min_speed), 0.0, 1.0)

	wind_player.volume_db = lerp(p.speed_wind_volume_min_db, p.speed_wind_volume_max_db, t)
	wind_player.pitch_scale = lerp(p.speed_wind_pitch_min, p.speed_wind_pitch_max, t)


func play_rail_land_sfx() -> void:
	# SUMMARY: Play the rail landing sound.
	# STEPS:
	# - Step 1: Validate the player node.
	# - Step 2: Restart the landing sound.
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var land_player: AudioStreamPlayer3D = p.sfx_rail_land
	if land_player == null:
		return
	land_player.stop()
	land_player.play()


func play_rail_detach_sfx() -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var detach_player: AudioStreamPlayer3D = p.sfx_rail_detach
	if detach_player == null:
		return

	var speed_abs: float = abs(p._rail_speed)
	var min_speed: float = max(p.rail_grind_min_speed, 0.0)
	var full_speed: float = max(p.rail_grind_full_speed, min_speed)
	var speed_ratio: float = 1.0
	if full_speed > min_speed:
		speed_ratio = clamp((speed_abs - min_speed) / (full_speed - min_speed), 0.0, 1.0)

	detach_player.volume_db = lerp(p.rail_grind_volume_min_db, p.rail_grind_volume_max_db, speed_ratio)
	detach_player.pitch_scale = lerp(p.rail_grind_pitch_min, p.rail_grind_pitch_max, speed_ratio)
	detach_player.stop()
	detach_player.play()


func update_rail_grind_audio(speed: float, delta: float) -> void:
	# SUMMARY: Drive rail grind loop volume/pitch by rail speed and fade on stop.
	# STEPS:
	# - Step 1: Validate the loop player and thresholds.
	# - Step 2: Compute target volume/pitch from speed.
	# - Step 3: Fade toward target and stop when fully quiet.
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return

	var grind_player: AudioStreamPlayer3D = p.sfx_rail_grind_loop
	if grind_player == null:
		return

	var speed_abs: float = max(speed, 0.0)
	var min_speed: float = max(p.rail_grind_min_speed, 0.0)
	var full_speed: float = max(p.rail_grind_full_speed, min_speed)
	var has_speed: bool = speed_abs >= min_speed

	var target_pitch: float = p.rail_grind_pitch_min
	var target_volume_db: float = p.rail_grind_stop_volume_db

	if has_speed:
		var t: float = 1.0
		if full_speed > min_speed:
			t = clamp((speed_abs - min_speed) / (full_speed - min_speed), 0.0, 1.0)
		target_volume_db = lerp(p.rail_grind_volume_min_db, p.rail_grind_volume_max_db, t)
		target_pitch = lerp(p.rail_grind_pitch_min, p.rail_grind_pitch_max, t)

	if not grind_player.playing:
		if not has_speed:
			return
		grind_player.volume_db = target_volume_db
		grind_player.pitch_scale = target_pitch
		grind_player.play()

	grind_player.pitch_scale = target_pitch

	var fade_speed_db: float = max(p.rail_grind_fade_speed_db, 0.0)
	if fade_speed_db > 0.0:
		grind_player.volume_db = move_toward(grind_player.volume_db, target_volume_db, fade_speed_db * delta)
	else:
		grind_player.volume_db = target_volume_db

	if not has_speed and grind_player.volume_db <= p.rail_grind_stop_volume_db + 0.1:
		grind_player.stop()


func update_drift_audio(
		drift_active: bool,
		lateral_speed: float,
		turn_speed_deg_per_sec: float,
		delta: float,
		drift_loop_sound: AudioStream = null
	) -> void:
	# SUMMARY: Drive drift loop volume and pitch from speed (pitch) and turn rate (volume).
	# STEPS:
	# - Step 1: Validate the drift loop player and drift state.
	# - Step 2: Map lateral speed to pitch (slower = higher, faster = lower).
	# - Step 3: Map turn speed to volume with smoothed lerp.
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var drift_player: AudioStreamPlayer3D = p.sfx_drift_loop
	if drift_player == null:
		return

	if not drift_active:
		if drift_player.playing:
			drift_player.stop()
		_drift_turn_volume_t_current = 0.0
		return

	if drift_loop_sound != null and drift_player.stream != drift_loop_sound:
		_set_stream_loop_enabled(drift_loop_sound)
		drift_player.stop()
		drift_player.stream = drift_loop_sound
	elif drift_player.stream != null:
		_set_stream_loop_enabled(drift_player.stream)

	var min_speed: float = max(p.drift_sound_min_speed, 0.0)
	var full_speed: float = max(p.drift_sound_full_speed, min_speed)
	var speed_t: float = 1.0
	if full_speed > min_speed:
		speed_t = clamp((lateral_speed - min_speed) / (full_speed - min_speed), 0.0, 1.0)

	var pitch_min: float = p.drift_sound_pitch_min
	var pitch_max: float = p.drift_sound_pitch_max
	var pitch_target: float = lerp(pitch_max, pitch_min, speed_t)

	var turn_speed_abs: float = abs(turn_speed_deg_per_sec)
	var turn_min: float = max(p.drift_sound_turn_min_deg_per_sec, 0.0)
	var turn_full: float = max(p.drift_sound_turn_full_deg_per_sec, turn_min)
	var turn_t: float = 1.0
	if turn_full > turn_min:
		turn_t = clamp((turn_speed_abs - turn_min) / (turn_full - turn_min), 0.0, 1.0)

	var lerp_speed: float = max(p.drift_sound_turn_lerp_speed, 0.0)
	if lerp_speed > 0.0:
		var t_raw: float = clamp(lerp_speed * delta, 0.0, 1.0)
		_drift_turn_volume_t_current = lerp(_drift_turn_volume_t_current, turn_t, t_raw)
	else:
		_drift_turn_volume_t_current = turn_t

	var volume_target_db: float = lerp(
		p.drift_sound_volume_min_db,
		p.drift_sound_volume_max_db,
		_drift_turn_volume_t_current
	)

	drift_player.volume_db = volume_target_db
	drift_player.pitch_scale = pitch_target

	if not drift_player.playing:
		drift_player.play()


func _play_roll_transition(roll_active: bool) -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var transition_player: AudioStreamPlayer3D = p.sfx_roll_transition
	if transition_player == null:
		return

	transition_player.stop()
	var transition_sound: AudioStream = p.roll_start_sound if roll_active else p.roll_end_sound
	if transition_sound == null:
		return
	transition_player.stream = transition_sound
	transition_player.volume_db = p.roll_start_volume_db if roll_active else p.roll_end_volume_db
	var transition_pitch: float = p.roll_start_pitch_scale if roll_active else p.roll_end_pitch_scale
	transition_player.pitch_scale = max(transition_pitch, 0.01)
	transition_player.play()


func update_roll_audio(
		roll_active: bool,
		loop_active: bool,
		tangential_speed: float,
		delta: float
	) -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return

	if roll_active != _roll_active_last:
		_play_roll_transition(roll_active)
	_roll_active_last = roll_active

	var loop_player: AudioStreamPlayer3D = p.sfx_roll_loop
	if loop_player == null:
		return

	var volume_min_speed: float = max(p.roll_loop_volume_min_speed, 0.0)
	var volume_full_speed: float = max(p.roll_loop_volume_full_speed, volume_min_speed)
	var pitch_min_speed: float = max(p.roll_loop_pitch_min_speed, 0.0)
	var pitch_full_speed: float = max(p.roll_loop_pitch_full_speed, pitch_min_speed)
	var speed: float = max(tangential_speed, 0.0)
	var has_speed: bool = loop_active and speed >= volume_min_speed and p.roll_loop_sound != null
	var volume_speed_t_target: float = 0.0
	var pitch_speed_t_target: float = 0.0
	if has_speed:
		volume_speed_t_target = 1.0
		if volume_full_speed > volume_min_speed:
			volume_speed_t_target = clamp(
				(speed - volume_min_speed) / (volume_full_speed - volume_min_speed),
				0.0,
				1.0
			)
		pitch_speed_t_target = 1.0
		if pitch_full_speed > pitch_min_speed:
			pitch_speed_t_target = clamp(
				(speed - pitch_min_speed) / (pitch_full_speed - pitch_min_speed),
				0.0,
				1.0
			)

	var lerp_speed: float = max(p.roll_loop_lerp_speed, 0.0)
	if lerp_speed > 0.0:
		var blend: float = clamp(lerp_speed * max(delta, 0.0), 0.0, 1.0)
		_roll_loop_volume_speed_t_current = lerp(
			_roll_loop_volume_speed_t_current,
			volume_speed_t_target,
			blend
		)
		_roll_loop_pitch_speed_t_current = lerp(
			_roll_loop_pitch_speed_t_current,
			pitch_speed_t_target,
			blend
		)
	else:
		_roll_loop_volume_speed_t_current = volume_speed_t_target
		_roll_loop_pitch_speed_t_current = pitch_speed_t_target

	var target_volume_db: float = p.roll_loop_stop_volume_db
	var target_pitch: float = p.roll_loop_pitch_min
	if has_speed:
		target_volume_db = lerp(
			p.roll_loop_volume_min_db,
			p.roll_loop_volume_max_db,
			_roll_loop_volume_speed_t_current
		)
		target_pitch = lerp(
			p.roll_loop_pitch_min,
			p.roll_loop_pitch_max,
			_roll_loop_pitch_speed_t_current
		)

	if has_speed:
		if loop_player.stream != p.roll_loop_sound:
			_set_stream_loop_enabled(p.roll_loop_sound)
			loop_player.stop()
			loop_player.stream = p.roll_loop_sound
		else:
			_set_stream_loop_enabled(loop_player.stream)
		if not loop_player.playing:
			loop_player.volume_db = p.roll_loop_stop_volume_db
			loop_player.pitch_scale = max(target_pitch, 0.01)
			loop_player.play()

	loop_player.pitch_scale = max(target_pitch, 0.01)
	var fade_speed_db: float = p.roll_loop_fade_in_speed_db if has_speed else p.roll_loop_fade_out_speed_db
	fade_speed_db = max(fade_speed_db, 0.0)
	if fade_speed_db > 0.0:
		loop_player.volume_db = move_toward(
			loop_player.volume_db,
			target_volume_db,
			fade_speed_db * max(delta, 0.0)
		)
	else:
		loop_player.volume_db = target_volume_db

	if not has_speed and loop_player.playing and loop_player.volume_db <= p.roll_loop_stop_volume_db + 0.1:
		loop_player.stop()
		_roll_loop_volume_speed_t_current = 0.0
		_roll_loop_pitch_speed_t_current = 0.0


func update_engine_audio(engine_active: bool, tangential_speed: float, delta: float) -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var engine_player: AudioStreamPlayer3D = p.sfx_engine_loop
	if engine_player == null:
		return

	var volume_min_speed: float = max(p.engine_sound_volume_min_speed, 0.0)
	var volume_full_speed: float = max(p.engine_sound_volume_full_speed, volume_min_speed)
	var pitch_min_speed: float = max(p.engine_sound_pitch_min_speed, 0.0)
	var pitch_full_speed: float = max(p.engine_sound_pitch_full_speed, pitch_min_speed)
	var has_speed: bool = engine_active and tangential_speed >= volume_min_speed
	var volume_speed_t_target: float = 0.0
	var pitch_speed_t_target: float = 0.0
	if has_speed:
		volume_speed_t_target = 1.0
		if volume_full_speed > volume_min_speed:
			volume_speed_t_target = clamp(
				(tangential_speed - volume_min_speed) / (volume_full_speed - volume_min_speed),
				0.0,
				1.0
			)
		pitch_speed_t_target = 1.0
		if pitch_full_speed > pitch_min_speed:
			pitch_speed_t_target = clamp(
				(tangential_speed - pitch_min_speed) / (pitch_full_speed - pitch_min_speed),
				0.0,
				1.0
			)

	var lerp_speed: float = max(p.engine_sound_lerp_speed, 0.0)
	if lerp_speed > 0.0:
		var blend: float = clamp(lerp_speed * max(delta, 0.0), 0.0, 1.0)
		_engine_volume_speed_t_current = lerp(
			_engine_volume_speed_t_current,
			volume_speed_t_target,
			blend
		)
		_engine_pitch_speed_t_current = lerp(
			_engine_pitch_speed_t_current,
			pitch_speed_t_target,
			blend
		)
	else:
		_engine_volume_speed_t_current = volume_speed_t_target
		_engine_pitch_speed_t_current = pitch_speed_t_target

	var target_volume_db: float = p.engine_sound_stop_volume_db
	var target_pitch: float = p.engine_sound_pitch_min
	if has_speed:
		target_volume_db = lerp(
			p.engine_sound_volume_min_db,
			p.engine_sound_volume_max_db,
			_engine_volume_speed_t_current
		)
		target_pitch = lerp(
			p.engine_sound_pitch_min,
			p.engine_sound_pitch_max,
			_engine_pitch_speed_t_current
		)

	if has_speed:
		if p.engine_loop_sound != null and engine_player.stream != p.engine_loop_sound:
			_set_stream_loop_enabled(p.engine_loop_sound)
			engine_player.stop()
			engine_player.stream = p.engine_loop_sound
		elif engine_player.stream != null:
			_set_stream_loop_enabled(engine_player.stream)
		if not engine_player.playing:
			engine_player.volume_db = p.engine_sound_stop_volume_db
			engine_player.pitch_scale = max(target_pitch, 0.01)
			engine_player.play()

	engine_player.pitch_scale = max(target_pitch, 0.01)
	var fade_speed_db: float = p.engine_sound_fade_in_speed_db if has_speed else p.engine_sound_fade_out_speed_db
	fade_speed_db = max(fade_speed_db, 0.0)
	if fade_speed_db > 0.0:
		engine_player.volume_db = move_toward(engine_player.volume_db, target_volume_db, fade_speed_db * max(delta, 0.0))
	else:
		engine_player.volume_db = target_volume_db

	if not has_speed and engine_player.playing and engine_player.volume_db <= p.engine_sound_stop_volume_db + 0.1:
		engine_player.stop()
		_engine_volume_speed_t_current = 0.0
		_engine_pitch_speed_t_current = 0.0


func update_skid_audio(skid_active: bool, lateral_speed: float, delta: float) -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var skid_player: AudioStreamPlayer3D = p.sfx_skid_loop
	if skid_player == null:
		return

	var speed_abs: float = max(lateral_speed, 0.0)
	var min_speed: float = max(p.skid_sound_min_speed, 0.0)
	var full_speed: float = max(p.skid_sound_full_speed, min_speed)
	var speed_t: float = 1.0
	if full_speed > min_speed:
		speed_t = clamp((speed_abs - min_speed) / (full_speed - min_speed), 0.0, 1.0)

	var target_volume_db: float = p.skid_sound_stop_volume_db
	var target_pitch: float = p.skid_sound_pitch_slow

	if skid_active:
		var surface: int = _resolve_skid_surface(p)
		var next_stream: AudioStream = _get_skid_sound_for_surface(surface)
		if next_stream == null:
			skid_active = false
		else:
			if surface != _skid_surface or next_stream != _skid_stream:
				_skid_surface = surface
				_skid_stream = next_stream
				_set_stream_loop_enabled(_skid_stream)
				skid_player.stream = _skid_stream
				skid_player.volume_db = p.skid_sound_stop_volume_db
				skid_player.play()
			elif not skid_player.playing:
				_set_stream_loop_enabled(next_stream)
				skid_player.stream = next_stream
				skid_player.volume_db = p.skid_sound_stop_volume_db
				skid_player.play()

			target_volume_db = lerp(p.skid_sound_volume_min_db, p.skid_sound_volume_max_db, speed_t)
			if _get_skid_pitch_reverse_for_surface(surface):
				target_pitch = lerp(p.skid_sound_pitch_fast, p.skid_sound_pitch_slow, speed_t)
			else:
				target_pitch = lerp(p.skid_sound_pitch_slow, p.skid_sound_pitch_fast, speed_t)

	skid_player.pitch_scale = max(target_pitch, 0.01)

	var fade_speed_db: float = p.skid_sound_fade_in_speed_db if skid_active else p.skid_sound_fade_out_speed_db
	fade_speed_db = max(fade_speed_db, 0.0)
	if fade_speed_db > 0.0:
		skid_player.volume_db = move_toward(skid_player.volume_db, target_volume_db, fade_speed_db * delta)
	else:
		skid_player.volume_db = target_volume_db

	if not skid_active and skid_player.playing and skid_player.volume_db <= p.skid_sound_stop_volume_db + 0.1:
		skid_player.stop()


func stop_rail_grind_audio() -> void:
	# SUMMARY: Immediately stop the rail grind loop.
	# STEPS:
	# - Step 1: Validate the loop player.
	# - Step 2: Stop if it is playing.
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var grind_player: AudioStreamPlayer3D = p.sfx_rail_grind_loop
	if grind_player == null:
		return
	if grind_player.playing:
		grind_player.stop()


func stop_drift_audio() -> void:
	# SUMMARY: Immediately stop the drift loop and reset its smoothing.
	# STEPS:
	# - Step 1: Validate the drift loop player.
	# - Step 2: Stop if it is playing.
	# - Step 3: Reset the smoothed turn volume factor.
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var drift_player: AudioStreamPlayer3D = p.sfx_drift_loop
	if drift_player == null:
		return
	if drift_player.playing:
		drift_player.stop()
	_drift_turn_volume_t_current = 0.0


func stop_engine_audio() -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var engine_player: AudioStreamPlayer3D = p.sfx_engine_loop
	if engine_player != null and engine_player.playing:
		engine_player.stop()
	if engine_player != null:
		engine_player.volume_db = p.engine_sound_stop_volume_db
	_engine_volume_speed_t_current = 0.0
	_engine_pitch_speed_t_current = 0.0


func stop_roll_audio() -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var transition_player: AudioStreamPlayer3D = p.sfx_roll_transition
	if transition_player != null and transition_player.playing:
		transition_player.stop()
	var loop_player: AudioStreamPlayer3D = p.sfx_roll_loop
	if loop_player != null and loop_player.playing:
		loop_player.stop()
	if loop_player != null:
		loop_player.volume_db = p.roll_loop_stop_volume_db
	_roll_active_last = false
	_roll_loop_volume_speed_t_current = 0.0
	_roll_loop_pitch_speed_t_current = 0.0


func stop_skid_audio() -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var skid_player: AudioStreamPlayer3D = p.sfx_skid_loop
	if skid_player == null:
		return
	if skid_player.playing:
		skid_player.stop()
	skid_player.volume_db = p.skid_sound_stop_volume_db


func stop_barrier_blast_wind() -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var wind_player: AudioStreamPlayer3D = p.sfx_barrier_blast_wind
	if wind_player == null:
		return
	if wind_player.playing:
		wind_player.stop()
	wind_player.volume_db = p.barrier_blast_wind_silent_db
	if _barrier_blast_wet_player != null and is_instance_valid(_barrier_blast_wet_player):
		if _barrier_blast_wet_player.playing:
			_barrier_blast_wet_player.stop()
		_barrier_blast_wet_player.volume_db = p.barrier_blast_wind_silent_db
	_barrier_blast_wind_mix = 0.0
	_barrier_blast_wind_hold_volume_db = p.barrier_blast_wind_silent_db
	_barrier_blast_wind_hold_pitch = p.barrier_blast_wind_pitch_min
	_barrier_blast_wind_hold_intensity = 0.0


func _ensure_barrier_blast_wet_player(
		dry_player: AudioStreamPlayer3D,
		wet_bus: StringName
	) -> AudioStreamPlayer3D:
	if AudioServer.get_bus_index(wet_bus) < 0:
		if _barrier_blast_wet_player != null and is_instance_valid(_barrier_blast_wet_player):
			_barrier_blast_wet_player.stop()
		return null
	if (
		_barrier_blast_wet_player != null
		and is_instance_valid(_barrier_blast_wet_player)
		and _barrier_blast_wet_player.get_parent() != dry_player
	):
		_barrier_blast_wet_player.queue_free()
		_barrier_blast_wet_player = null
	if _barrier_blast_wet_player == null or not is_instance_valid(_barrier_blast_wet_player):
		_barrier_blast_wet_player = AudioStreamPlayer3D.new()
		_barrier_blast_wet_player.name = "SFX_BarrierBlastWindWet"
		dry_player.add_child(_barrier_blast_wet_player)
	if _barrier_blast_wet_player.stream != dry_player.stream:
		_barrier_blast_wet_player.stream = dry_player.stream
	_barrier_blast_wet_player.bus = wet_bus
	_barrier_blast_wet_player.attenuation_model = dry_player.attenuation_model
	_barrier_blast_wet_player.unit_size = dry_player.unit_size
	_barrier_blast_wet_player.max_db = dry_player.max_db
	_barrier_blast_wet_player.max_distance = dry_player.max_distance
	_barrier_blast_wet_player.panning_strength = dry_player.panning_strength
	_barrier_blast_wet_player.attenuation_filter_cutoff_hz = dry_player.attenuation_filter_cutoff_hz
	_barrier_blast_wet_player.attenuation_filter_db = dry_player.attenuation_filter_db
	_barrier_blast_wet_player.emission_angle_enabled = dry_player.emission_angle_enabled
	_barrier_blast_wet_player.emission_angle_degrees = dry_player.emission_angle_degrees
	_barrier_blast_wet_player.emission_angle_filter_attenuation_db = dry_player.emission_angle_filter_attenuation_db
	_barrier_blast_wet_player.area_mask = dry_player.area_mask
	return _barrier_blast_wet_player


func _play_sfx(player: AudioStreamPlayer3D) -> void:
	# SUMMARY: Play a one-shot SFX and replicate the tag when needed.
	# STEPS:
	# - Step 1: Restart the audio player.
	# - Step 2: Determine the tag for replication.
	# - Step 3: Send the tag to peers.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if player == null:
		return
	player.stop()
	player.play()

	if p._network_is_active() and p.is_multiplayer_authority():
		var tag = ""
		if player == p.sfx_bounce_start:
			tag = "bounce_start"
		elif player == p.sfx_bounce_land:
			tag = "bounce_land"
		elif player == p.sfx_stomp_start:
			tag = "stomp_start"
		elif player == p.sfx_stomp_land:
			tag = "stomp_land"
		if tag != "":
			p.rpc("_net_play_action_sfx", tag, -1)


func _replicate_voice(player: AudioStreamPlayer3D) -> void:
	if _owner._network_is_active() and _owner.network_replication_enabled and _owner.is_multiplayer_authority() and player.stream:
		_owner.rpc("_net_play_voice_clip", player.stream.resource_path, _current_voice_priority)


func play_replicated_voice(stream: AudioStream, priority: int) -> void:
	var player: AudioStreamPlayer3D = _owner.get_dialogue_player()
	if not player:
		return
	_voice_queue.clear()
	_current_voice_priority = priority
	_ensure_dialogue_finished_connection(player)
	player.volume_db = minf(player.volume_db, player.max_db)
	player.unit_size = maxf(_owner.remote_voice_unit_size, 0.1)
	player.max_distance = maxf(_owner.remote_voice_max_distance, player.unit_size)
	player.stream = stream
	player.play()

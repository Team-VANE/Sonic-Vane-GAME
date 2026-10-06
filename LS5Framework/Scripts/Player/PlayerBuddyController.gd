extends RefCounted
class_name PlayerBuddyController

# Local buddy selection, spawning, synchronization, and lifecycle.
var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func _on_buddy_tree_exited(exited_buddy: Node = null) -> void:
	var p = _owner
	if exited_buddy != null and p._buddy_instance != exited_buddy:
		return
	# Keep the handle valid even if buddy is freed externally.
	p._buddy_instance = null
	_clear_buddy_runtime_state()


func _clear_buddy_runtime_state() -> void:
	var p = _owner
	p._buddy_jump_mimic_active = false
	p._buddy_last_sent_bb_gauge = -1.0
	p._buddy_last_sent_bb_active = false
	p._buddy_last_sent_mimic_jump_range = -1.0
	p._buddy_last_sent_mimic_roll_range = -1.0


func _get_valid_buddy_instance() -> Node:
	var p = _owner
	if p._buddy_instance == null or not is_instance_valid(p._buddy_instance):
		return null
	return p._buddy_instance


func _notify_buddy_leader_roll_changed(is_rolling: bool) -> void:
	var p = _owner
	var buddy = _get_valid_buddy_instance()
	if buddy == null:
		return
	if not buddy.has_method("on_leader_roll_changed"):
		return
	buddy.call("on_leader_roll_changed", is_rolling)


func _notify_buddy_barrier_blast_sync() -> void:
	var p = _owner
	var buddy = _get_valid_buddy_instance()
	if buddy == null:
		return
	if not buddy.has_method("sync_leader_barrier_blast"):
		return

	var g: float = clamp(p._barrier_blast_gauge, 0.0, 1.0)
	var a: bool = bool(p._barrier_blast_active)

	if p._buddy_last_sent_bb_gauge < 0.0 or abs(p._buddy_last_sent_bb_gauge - g) > 0.01 or p._buddy_last_sent_bb_active != a:
		p._buddy_last_sent_bb_gauge = g
		p._buddy_last_sent_bb_active = a
		buddy.call("sync_leader_barrier_blast", g, a)


func _notify_buddy_dynamic_mimic_ranges() -> void:
	var p = _owner
	var buddy = _get_valid_buddy_instance()
	if buddy == null:
		return

	var spd: float = p.velocity.length()
	var denom: float = max(p.buddy_mimic_scale_speed_for_max, 0.001)
	var t: float = clamp(spd / denom, 0.0, 1.0)
	var e: float = max(p.buddy_mimic_scale_exponent, 0.01)
	var k: float = pow(t, e)

	var jump_min: float = max(p.buddy_mimic_jump_range, 0.0)
	var roll_min: float = max(p.buddy_mimic_roll_range, 0.0)
	var jump_max: float = max(p.buddy_mimic_jump_range_max, jump_min)
	var roll_max: float = max(p.buddy_mimic_roll_range_max, roll_min)

	var jump_range: float = lerp(jump_min, jump_max, k)
	var roll_range: float = lerp(roll_min, roll_max, k)

	# Avoid spamming setters every frame.
	if p._object_has_property(buddy, "mimic_leader_jump_range"):
		if p._buddy_last_sent_mimic_jump_range < 0.0 or abs(p._buddy_last_sent_mimic_jump_range - jump_range) > 0.5:
			p._buddy_last_sent_mimic_jump_range = jump_range
			buddy.set("mimic_leader_jump_range", jump_range)

	if p._object_has_property(buddy, "mimic_leader_roll_range"):
		if p._buddy_last_sent_mimic_roll_range < 0.0 or abs(p._buddy_last_sent_mimic_roll_range - roll_range) > 0.5:
			p._buddy_last_sent_mimic_roll_range = roll_range
			buddy.set("mimic_leader_roll_range", roll_range)


func _notify_buddy_leader_jump_pressed() -> void:
	var p = _owner
	var buddy = _get_valid_buddy_instance()
	if buddy == null:
		return
	if not buddy.has_method("on_leader_jump_pressed"):
		return
	p._buddy_jump_mimic_active = true
	buddy.call("on_leader_jump_pressed")


func _notify_buddy_leader_jump_released() -> void:
	var p = _owner
	if not p._buddy_jump_mimic_active:
		return
	var buddy = _get_valid_buddy_instance()
	if buddy == null:
		p._buddy_jump_mimic_active = false
		return
	if not buddy.has_method("on_leader_jump_released"):
		p._buddy_jump_mimic_active = false
		return
	buddy.call("on_leader_jump_released")
	p._buddy_jump_mimic_active = false


func _toggle_buddy() -> void:
	var p = _owner
	if not p._network_is_local_authority():
		return
	if not p.buddy_enable:
		return
	if p._buddy_instance != null and is_instance_valid(p._buddy_instance):
		despawn_buddy()
		SettingsManager.set_buddy_active(false)
		SettingsManager.save_now()
		return
	spawn_selected_buddy()


func spawn_selected_buddy() -> bool:
	var p = _owner
	return set_buddy_character(SettingsManager.chosen_buddy_character_id)


func set_buddy_character(character_id: String) -> bool:
	var p = _owner
	if not p._network_is_local_authority():
		return false
	if not p.buddy_enable:
		return false
	# Keep buddy local-only for now (avoids networking + authority issues).
	if p.multiplayer != null and p.multiplayer.has_multiplayer_peer():
		return false
	var normalized_id: String = character_id.strip_edges()
	var resolved_entry: Dictionary = CharacterCatalog.get_entry_for_id(p.buddy_character_data_dir, normalized_id)
	if resolved_entry.is_empty():
		resolved_entry = _get_current_player_character_entry()
	if resolved_entry.is_empty():
		return false
	normalized_id = String(resolved_entry.get("id", "")).strip_edges()
	if p._buddy_instance != null and is_instance_valid(p._buddy_instance):
		var current_id: String = String(p._buddy_instance.get_meta("buddy_character_id", ""))
		var current_scene_path: String = String(p._buddy_instance.scene_file_path)
		var selected_scene_path: String = String(resolved_entry.get("scene", ""))
		if current_id.nocasecmp_to(normalized_id) == 0 and current_scene_path == selected_scene_path:
			SettingsManager.set_chosen_buddy_character_id(normalized_id)
			SettingsManager.set_buddy_active(true)
			SettingsManager.save_now()
			return true
		despawn_buddy()

	var inst = _instantiate_buddy_character(normalized_id)
	if inst == null:
		return false
	normalized_id = String(inst.get_meta("buddy_character_id", normalized_id))

	SettingsManager.set_chosen_buddy_character_id(normalized_id)
	SettingsManager.set_buddy_active(true)
	SettingsManager.save_now()
	_spawn_buddy_instance(inst, normalized_id)
	return true


func despawn_buddy() -> void:
	var p = _owner
	if p._buddy_instance == null or not is_instance_valid(p._buddy_instance):
		p._buddy_instance = null
		_clear_buddy_runtime_state()
		return
	# Defer to avoid "SceneTree is locked" in some input/physics contexts.
	p._buddy_instance.call_deferred("queue_free")
	p._buddy_instance = null
	_clear_buddy_runtime_state()


func _instantiate_buddy_character(character_id: String) -> Node:
	var p = _owner
	var entry: Dictionary = CharacterCatalog.get_entry_for_id(p.buddy_character_data_dir, character_id)
	var fallback_entry: Dictionary = _get_current_player_character_entry()
	var entries: Array[Dictionary] = []
	if not entry.is_empty():
		entries.append(entry)
	if not fallback_entry.is_empty() and String(fallback_entry.get("scene", "")) != String(entry.get("scene", "")):
		entries.append(fallback_entry)
	for candidate: Dictionary in entries:
		var scene_path: String = String(candidate.get("scene", "")).strip_edges()
		if scene_path == "":
			continue
		var packed: Resource = load(scene_path)
		if not (packed is PackedScene):
			continue
		var character_inst: Node = (packed as PackedScene).instantiate()
		if character_inst == null:
			continue
		var buddy_script: Resource = load("res://LS5Framework/Scripts/AI/BuddySonicPlayer.gd")
		if not (buddy_script is Script):
			character_inst.free()
			return null
		var character_properties: Dictionary = _collect_scene_root_properties(character_inst)
		character_inst.set_script(buddy_script)
		_restore_scene_root_properties(character_inst, character_properties)
		_copy_buddy_template_properties_to(character_inst)
		character_inst.set_meta("buddy_character_id", String(candidate.get("id", "")))
		return character_inst
	return null


func _get_current_player_character_entry() -> Dictionary:
	var p = _owner
	var scene_path: String = String(p.scene_file_path).strip_edges()
	if scene_path == "":
		return {}
	var entries: Array = CharacterCatalog.load_character_entries(p.buddy_character_data_dir)
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary:
			var entry: Dictionary = raw_entry
			if String(entry.get("scene", "")) == scene_path:
				return entry
	return {"id": scene_path.get_file().get_basename(), "scene": scene_path}


func _collect_scene_root_properties(source: Object) -> Dictionary:
	var p = _owner
	var values: Dictionary = {}
	if source == null:
		return values
	for property in source.get_property_list():
		var property_name: StringName = StringName(property.get("name", ""))
		if property_name == &"" or property_name == &"script":
			continue
		var usage: int = int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if _should_skip_ai_overlay_property(property_name):
			continue
		values[property_name] = source.get(property_name)
	return values


func _restore_scene_root_properties(target: Object, values: Dictionary) -> void:
	var p = _owner
	if target == null:
		return
	for key in values.keys():
		var property_name: StringName = StringName(key)
		if not p._object_has_property(target, property_name):
			continue
		target.set(property_name, values[key])


func _should_skip_ai_overlay_property(property_name: StringName) -> bool:
	var p = _owner
	var property_text: String = String(property_name)
	if property_text.begins_with("buddy_"):
		return true
	if property_text.begins_with("follow_"):
		return true
	if property_text.begins_with("mimic_"):
		return true
	if property_text.begins_with("obstacle_"):
		return true
	if property_text.begins_with("spawn_sync_"):
		return true
	if property_text.begins_with("catchup_"):
		return true
	if property_text.begins_with("crowd_slow_"):
		return true
	if property_text.begins_with("rival_"):
		return true
	return false


func _copy_buddy_template_properties_to(target: Node) -> void:
	var p = _owner
	if target == null:
		return
	var template_scene: Resource = load("res://LS5Framework/Scenes/Buddy/BuddySonicPlayer.tscn")
	if not (template_scene is PackedScene):
		return
	var template_inst: Node = (template_scene as PackedScene).instantiate()
	if not (template_inst is Node):
		return
	var template_node: Node = template_inst as Node
	for property in template_node.get_property_list():
		var property_name: StringName = StringName(property.get("name", ""))
		if property_name == &"" or property_name == &"script":
			continue
		if not _should_copy_buddy_template_property(property_name):
			continue
		if not p._object_has_property(target, property_name):
			continue
		target.set(property_name, template_node.get(property_name))
	template_node.queue_free()


func _should_copy_buddy_template_property(property_name: StringName) -> bool:
	var p = _owner
	var property_text: String = String(property_name)
	if property_text.begins_with("follow_"):
		return true
	if property_text.begins_with("buddy_"):
		return true
	if property_text.begins_with("mimic_"):
		return true
	if property_text.begins_with("obstacle_"):
		return true
	if property_text.begins_with("spawn_sync_"):
		return true
	if property_text.begins_with("catchup_"):
		return true
	if property_text.begins_with("crowd_slow_"):
		return true
	return false


func _spawn_buddy_instance(inst: Node, character_id: String) -> void:
	var p = _owner
	if inst == null:
		return
	p._buddy_instance = inst
	inst.set_meta("buddy_character_id", character_id)
	inst.name = "Buddy_%s" % character_id
	inst.tree_exited.connect(Callable(p, "_on_buddy_tree_exited").bind(inst))

	# Spawn near the player in world space.
	var spawn_offset: Vector3 = p.buddy_spawn_offset
	var up: Vector3 = p._get_gravity_up()
	if p.has_method("get_up_vector"):
		up = p.get_up_vector().normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()
	# Interpret X/Z of offset relative to player model forward/right.
	var forward: Vector3 = p._model_forward
	forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = -Vector3.FORWARD
	forward = forward.normalized()
	var right: Vector3 = forward.cross(up).normalized()

	var world_offset: Vector3 = right * spawn_offset.x + up * spawn_offset.y + forward * spawn_offset.z
	var spawn_pos: Vector3 = p.global_position + world_offset
	if inst is Node3D:
		(inst as Node3D).global_position = spawn_pos
	if inst.has_method("set_spawn_position_override"):
		inst.call("set_spawn_position_override", spawn_pos)

	# Assign follow target if supported.
	if inst.has_method("set"):
		if p._object_has_property(inst, "follow_target"):
			inst.set("follow_target", p)
		elif p._object_has_property(inst, "target"):
			inst.set("target", p)

		# Apply ranges/settings from the leader's exports for centralized tuning.
		if p._object_has_property(inst, "mimic_leader_jump_range"):
			inst.set("mimic_leader_jump_range", p.buddy_mimic_jump_range)
		if p._object_has_property(inst, "mimic_leader_roll_range"):
			inst.set("mimic_leader_roll_range", p.buddy_mimic_roll_range)
		if p._object_has_property(inst, "obstacle_jump_leader_range"):
			inst.set("obstacle_jump_leader_range", p.buddy_obstacle_jump_range)
		if p._object_has_property(inst, "buddy_teleport_distance"):
			inst.set("buddy_teleport_distance", p.buddy_spawn_teleport_distance)
		if p._object_has_property(inst, "buddy_teleport_height"):
			inst.set("buddy_teleport_height", p.buddy_spawn_teleport_height)
		if p._object_has_property(inst, "catchup_start_distance"):
			inst.set("catchup_start_distance", p.buddy_catchup_start_distance)
		if p._object_has_property(inst, "catchup_full_distance"):
			inst.set("catchup_full_distance", p.buddy_catchup_full_distance)
		if p._object_has_property(inst, "catchup_multiplier_max"):
			inst.set("catchup_multiplier_max", p.buddy_catchup_multiplier_max)
		if p._object_has_property(inst, "catchup_exponent"):
			inst.set("catchup_exponent", p.buddy_catchup_exponent)
		if p._object_has_property(inst, "crowd_slow_enabled"):
			inst.set("crowd_slow_enabled", p.buddy_crowd_slow_enabled)
		if p._object_has_property(inst, "crowd_slow_start_distance"):
			inst.set("crowd_slow_start_distance", p.buddy_crowd_slow_start_distance)
		if p._object_has_property(inst, "crowd_slow_full_distance"):
			inst.set("crowd_slow_full_distance", p.buddy_crowd_slow_full_distance)
		if p._object_has_property(inst, "crowd_slow_multiplier_min"):
			inst.set("crowd_slow_multiplier_min", p.buddy_crowd_slow_multiplier_min)
		if p._object_has_property(inst, "crowd_slow_leader_speed_threshold"):
			inst.set("crowd_slow_leader_speed_threshold", p.buddy_crowd_slow_leader_speed_threshold)
		if p._object_has_property(inst, "spawn_sync_enabled"):
			inst.set("spawn_sync_enabled", p.buddy_spawn_sync_enabled)
		if p._object_has_property(inst, "spawn_sync_copy_rotation"):
			inst.set("spawn_sync_copy_rotation", p.buddy_spawn_sync_copy_rotation)
		if p._object_has_property(inst, "spawn_sync_copy_velocity"):
			inst.set("spawn_sync_copy_velocity", p.buddy_spawn_sync_copy_velocity)

	# Match the leader's facing direction + speed so the buddy can keep up immediately.
	if inst.has_method("match_leader_spawn_state"):
		inst.call("match_leader_spawn_state", p)

	# Sync initial leader roll state if supported.
	_notify_buddy_leader_roll_changed(p.rolling)

	# Add to the current scene so it persists like other world objects.
	if p.get_tree() != null and p.get_tree().current_scene != null:
		# Defer add to avoid tree modification issues during input callbacks.
		p.get_tree().current_scene.call_deferred("add_child", inst)
	else:
		p.call_deferred("add_child", inst)


func _sync_buddy_after_leader_teleport() -> void:
	var p = _owner
	if p._buddy_instance == null or not is_instance_valid(p._buddy_instance):
		return
	if not (p._buddy_instance is Node3D):
		return

	var buddy: Node3D = p._buddy_instance as Node3D

	# Ensure follow target remains correct.
	if p._object_has_property(buddy, "follow_target"):
		buddy.set("follow_target", p)

	# Reposition near the player using the same offset logic as spawn.
	var spawn_offset: Vector3 = p.buddy_spawn_offset
	var up: Vector3 = p._get_gravity_up()
	if p.has_method("get_up_vector"):
		up = p.get_up_vector().normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var forward: Vector3 = p._model_forward
	forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = -Vector3.FORWARD
	forward = forward.normalized()
	var right: Vector3 = forward.cross(up).normalized()

	var world_off: Vector3 = right * spawn_offset.x + up * spawn_offset.y + forward * spawn_offset.z
	buddy.global_position = p.global_position + world_off

	# Sync facing + speed for immediate keep-up if supported.
	if buddy.has_method("match_leader_spawn_state"):
		buddy.call("match_leader_spawn_state", p)

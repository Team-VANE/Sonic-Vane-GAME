extends RefCounted
class_name PlayerCombatController

# Combat state, enemy bounce resolution, damage, and hurt presentation.
var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func _is_post_race_protected() -> bool:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return false
	if p.has_method("is_post_race_protected"):
		return bool(p.call("is_post_race_protected"))
	var race_finished_value: Variant = p.get("race_finished")
	return race_finished_value is bool and bool(race_finished_value)


func is_attack_active() -> bool:
	var p = _owner
	return p._attack_sources != 0


func is_hurt_active() -> bool:
	var p = _owner
	return p._hurt_active


func is_hurt_invulnerable() -> bool:
	var p = _owner
	return _is_post_race_protected() or p._damage_hit_invuln_timer > 0.0 or p._invincibility_timer > 0.0 or p._is_dead or p._player_state_locked


func is_death_sequence_active() -> bool:
	var p = _owner
	if p._active_death_type != &"":
		return true
	if p._hurt_action != null and is_instance_valid(p._hurt_action):
		if p._hurt_action.has_method("is_death_sequence_active"):
			return bool(p._hurt_action.call("is_death_sequence_active"))
	return p._is_dead


func begin_death_sequence(death_type: StringName = &"generic") -> void:
	if _is_post_race_protected():
		return
	var p = _owner
	if p._level_load_suspended:
		return
	p._active_death_type = death_type if death_type != &"" else &"generic"
	set_death_state(true)


func apply_death_respawn_consequences(_death_type: StringName = &"generic") -> void:
	if _is_post_race_protected():
		return
	var p = _owner
	if p.has_method("is_active_ring_race") and p.call("is_active_ring_race"):
		p.call("remove_rings", 20)
		return
	if p.has_method("reset_rings"):
		p.call("reset_rings")
		return
	p.rings = 0
	if p.has_method("_update_rings_hud"):
		p.call("_update_rings_hud")


func finish_death_sequence() -> void:
	set_death_state(false)


func is_airborne() -> bool:
	var p = _owner
	return not p.attached


func get_combat_class() -> int:
	var p = _owner
	return p.CombatClass.ATTACK if is_attack_active() else p.CombatClass.NEUTRAL


func cancel_attack_for_combat_response(_reason: StringName = &"combat_response") -> void:
	var p = _owner
	if p._homing_active or p._homing_target != null:
		p.cancel_homing_attack(false)
	p._stop_lightspeed_dash_if_active(false)
	p._cancel_spindash_charge()
	p._jump_dashing = false
	p._jump_dash_requested = false
	p._jump_dash_recent_timer = 0.0
	p._homing_post_attack_timer = 0.0
	p._bounce_state = p.BounceState.NONE
	p._bounce_rebound_attack_active = false
	p._enemy_attack_chain_active = false
	p._jumped_from_ground = false
	if p._roll_action != null and is_instance_valid(p._roll_action):
		p._roll_action.is_rolling = false
	p.rolling = false
	p._attack_sources = 0
	if p.has_method("_set_attack_pass_through_collision_enabled"):
		p.call("_set_attack_pass_through_collision_enabled", true)
	if p._active_action != null and is_instance_valid(p._active_action):
		var current_id: StringName = p.get_current_action_id()
		if current_id != &"insta_shield" and current_id != &"hurt" and current_id != &"drowned":
			p.clear_active_action()


func _set_hurt_flash_visible(value: bool) -> void:
	var p = _owner
	if p._hurt_flash_renderers.is_empty():
		_cache_hurt_flash_renderers()
	for renderer in p._hurt_flash_renderers:
		if renderer == null:
			continue
		if not is_instance_valid(renderer):
			continue
		renderer.visible = value


func _cache_hurt_flash_renderers() -> void:
	var p = _owner
	p._hurt_flash_renderers.clear()
	if p.model_root == null:
		return
	if not is_instance_valid(p.model_root):
		return
	_collect_hurt_flash_renderers(p.model_root)


func _collect_hurt_flash_renderers(node: Node) -> void:
	var p = _owner
	if node is GeometryInstance3D:
		p._hurt_flash_renderers.append(node as GeometryInstance3D)
	for child in node.get_children():
		if child is Node:
			_collect_hurt_flash_renderers(child as Node)


func _update_hurt_invuln_visual(delta: float) -> void:
	var p = _owner
	if p._hurt_action != null:
		p._sync_hurt_state_to_action()
		p._hurt_action.update_invuln_visual(delta)
		p._sync_hurt_state_from_action()
		return

	p._hurt_flash_accum = 0.0
	if not p._hurt_flash_visible:
		p._hurt_flash_visible = true
		_set_hurt_flash_visible(true)


func set_attack_active(active: bool) -> void:
	var p = _owner
	_set_attack_source(p.AttackSource.MANUAL, active)


func note_airborne_roll_uncurl_attack() -> void:
	var p = _owner
	if p.attached:
		return
	_set_attack_source(p.AttackSource.AIR_UNCURL, true)


func _set_attack_source(flag: int, active: bool) -> void:
	var p = _owner
	var was_attacking: bool = p._attack_sources != 0
	if active:
		p._attack_sources |= flag
	else:
		p._attack_sources &= ~flag
	var is_attacking: bool = p._attack_sources != 0
	if was_attacking != is_attacking and p.has_method("_set_attack_pass_through_collision_enabled"):
		p.call("_set_attack_pass_through_collision_enabled", not is_attacking)


func _update_attack_sources() -> void:
	var p = _owner
	if p.attached or p._hurt_active or p._is_dead:
		p._bounce_rebound_attack_active = false
	_set_attack_source(p.AttackSource.JUMP, p._jumped_from_ground)
	_set_attack_source(p.AttackSource.ROLL, p.rolling)
	_set_attack_source(p.AttackSource.SPINDASH, p._spindash_charging)
	_set_attack_source(p.AttackSource.JUMP_DASH, p._jump_dash_recent_timer > 0.0)
	_set_attack_source(p.AttackSource.BOUNCE, p._bounce_state != p.BounceState.NONE or p._bounce_rebound_attack_active)
	_set_attack_source(p.AttackSource.HOMING, p._homing_active or p._homing_post_attack_timer > 0.0)
	_set_attack_source(p.AttackSource.LIGHTSPEED, p._lightspeed_dash_active)
	_set_attack_source(p.AttackSource.ENEMY_CHAIN, p._enemy_attack_chain_active and not p.attached)
	_set_attack_source(p.AttackSource.AIR_UNCURL, (p._attack_sources & p.AttackSource.AIR_UNCURL) != 0 and not p.attached)


func apply_enemy_bounce(origin: Vector3, speed: float, source: Node = null) -> void:
	var p = _owner
	if p._enemy_bounce_cooldown_timer > 0.0:
		return

	var was_homing_contact: bool = _homing_contact_matches_source(source)
	var up: Vector3 = _get_homing_contact_up()
	var homing_contact_velocity: Vector3 = p.velocity
	var homing_contact_lateral: Vector3 = homing_contact_velocity - up * homing_contact_velocity.dot(up)
	var dir: Vector3 = p.global_position - origin
	if dir.length() < 0.001:
		dir = -p.global_transform.basis.z
	dir = dir.normalized()

	var bounce_speed: float = max(speed, 0.0)
	if p._homing_active or p._homing_post_attack_timer > 0.0:
		bounce_speed *= max(p.homing_bounce_speed_fraction, 0.0)
	bounce_speed = max(bounce_speed, max(p.enemy_bounce_min_speed, 0.0))
	if not was_homing_contact:
		bounce_speed += p._consume_attack_magnetism_bounce_compensation()
	p.velocity = dir * bounce_speed
	p.attached = false
	p.reset_trick_staleness()
	p._attachment_immunity = p.launch_immunity_time
	p._airborne_time = 0.0
	p._jumped_from_ground = false
	p._falling_without_jump = true
	p._enemy_bounce_cooldown_timer = p.ENEMY_BOUNCE_COOLDOWN_SEC
	p.refresh_airborne_abilities()
	if was_homing_contact:
		_complete_homing_from_enemy_contact(source, homing_contact_velocity, homing_contact_lateral, up, origin)
	_interrupt_skydive_for_enemy_bounce(&"enemy_bounce")
	p.reset_flight_eligibility()
	p.end_active_flight_for_external_impulse({"reason": &"enemy_bounce"})


func apply_enemy_attack_bounce(end_bounce_stomp: bool = false, source: Node = null) -> void:
	var p = _owner
	if p._bounce_state == p.BounceState.STOMP:
		p._on_trick_detected(TrickSystem.TrickType.STOMP_DAREHOG)

	var was_homing_contact: bool = _homing_contact_matches_source(source)
	var up: Vector3 = _get_homing_contact_up()

	var v: Vector3 = p.velocity
	var vertical: float = v.dot(up)
	var lateral: Vector3 = v - up * vertical
	var homing_contact_velocity: Vector3 = v
	var homing_contact_lateral: Vector3 = lateral

	if vertical >= 0.0:
		vertical = vertical + vertical * 0.5
	else:
		vertical = abs(vertical)

	if p._homing_active or p._homing_post_attack_timer > 0.0:
		vertical *= max(p.homing_bounce_speed_fraction, 0.0)
	vertical = max(vertical, max(p.enemy_bounce_min_speed, 0.0))
	if not was_homing_contact:
		vertical += p._consume_attack_magnetism_bounce_compensation()

	p.velocity = lateral + up * vertical
	p.attached = false
	p.reset_trick_staleness()
	p._attachment_immunity = p.launch_immunity_time
	p._airborne_time = 0.0
	p._jump_variable = false
	p._jump_hang_allowed = false
	p._jump_time = 0.0
	p._is_jumping = false
	p._enemy_attack_chain_active = true
	p.refresh_airborne_abilities()
	if end_bounce_stomp and p._bounce_state != p.BounceState.NONE:
		p._bounce_state = p.BounceState.NONE
	if was_homing_contact:
		_complete_homing_from_enemy_contact(source, homing_contact_velocity, homing_contact_lateral, up, p.global_position)
	_interrupt_skydive_for_enemy_bounce(&"enemy_attack_bounce")
	p.reset_flight_eligibility()
	p.end_active_flight_for_external_impulse({"reason": &"enemy_attack_bounce"})


func _homing_contact_matches_source(source: Node) -> bool:
	var p = _owner
	if not p._homing_active:
		return false
	if source == null or not is_instance_valid(source):
		return false
	if p._homing_target == null or not is_instance_valid(p._homing_target):
		return true
	if source == p._homing_target:
		return true
	if source.is_ancestor_of(p._homing_target):
		return true
	if p._homing_target is Node and (p._homing_target as Node).is_ancestor_of(source):
		return true
	return true


func _interrupt_skydive_for_enemy_bounce(reason: StringName) -> void:
	var p = _owner
	if p._current_action_id != &"skydive":
		return
	p._skydive_anim_phase = p.SKYDIVE_ANIM_NONE
	p._skydive_anim_exit_timer = 0.0
	p._force_neutral_air_action({"reason": reason, "source_action": &"skydive"})


func _get_homing_contact_up() -> Vector3:
	var p = _owner
	var up: Vector3 = p._physics_up_last.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()
	return up


func _get_homing_contact_direction(source: Node, fallback_velocity: Vector3, fallback_origin: Vector3) -> Vector3:
	var p = _owner
	var dir: Vector3 = Vector3.ZERO
	if p._homing_target != null and is_instance_valid(p._homing_target):
		dir = p.get_homing_attack_target_position() - p.global_position
	if dir.length() < 0.001 and source != null and is_instance_valid(source) and source is Node3D:
		dir = (source as Node3D).global_position - p.global_position
	if dir.length() < 0.001:
		dir = p.global_position - fallback_origin
	if dir.length() < 0.001:
		dir = fallback_velocity
	if dir.length() < 0.001:
		dir = -p.global_transform.basis.z
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	return dir.normalized()


func _get_homing_contact_target_position(source: Node, fallback_origin: Vector3) -> Vector3:
	var p = _owner
	if p._homing_target != null and is_instance_valid(p._homing_target):
		return p.get_homing_attack_target_position()
	if source != null and is_instance_valid(source) and source is Node3D:
		return (source as Node3D).global_position
	return fallback_origin


func _get_homing_contact_pass_through(source: Node) -> bool:
	var p = _owner
	if source != null and is_instance_valid(source) and p._object_has_property(source, "pass_through") and source.get("pass_through"):
		return true
	if p._homing_target != null and is_instance_valid(p._homing_target) and p._object_has_property(p._homing_target, "pass_through") and p._homing_target.get("pass_through"):
		return true
	return false


func _get_homing_contact_pop_speed(source: Node) -> float:
	var p = _owner
	var pop_speed: float = p.homing_pop_up_speed
	if source != null and is_instance_valid(source) and p._object_has_property(source, "pop_up_speed_override"):
		var source_override: Variant = source.get("pop_up_speed_override")
		if source_override is float and float(source_override) > 0.0:
			return float(source_override)
	if p._homing_target != null and is_instance_valid(p._homing_target) and p._object_has_property(p._homing_target, "pop_up_speed_override"):
		var target_override: Variant = p._homing_target.get("pop_up_speed_override")
		if target_override is float and float(target_override) > 0.0:
			pop_speed = float(target_override)
	return pop_speed


func _complete_homing_from_enemy_contact(source: Node, contact_velocity: Vector3, contact_lateral: Vector3, up: Vector3, fallback_origin: Vector3) -> void:
	var p = _owner
	var target_position: Vector3 = _get_homing_contact_target_position(source, fallback_origin)
	var jump_held: bool = p._is_jump_held()
	var is_pass_through: bool = _get_homing_contact_pass_through(source)
	var bounce_compensation: float = p._consume_attack_magnetism_bounce_compensation()
	if is_pass_through:
		var homing_dir: Vector3 = _get_homing_contact_direction(source, contact_velocity, fallback_origin)
		var homing_spd: float = max(p.homing_speed, p._homing_saved_speed_mag)
		p.velocity = homing_dir * homing_spd
	else:
		var pop_speed: float = _get_homing_contact_pop_speed(source) + bounce_compensation
		var retained: Vector3 = Vector3.ZERO
		if p.homing_retain_speed_if_jump_held and jump_held:
			if contact_velocity.dot(up) < 0.0:
				retained = contact_lateral
			elif contact_velocity.length() > 0.001:
				retained = contact_velocity
			elif contact_lateral.length() > 0.001:
				retained = contact_lateral
			else:
				retained = p._homing_saved_lateral
			p._homing_retain_timer = max(p.homing_retain_disable_air_decel_time, 0.0)
		else:
			p._homing_retain_timer = 0.0
		var bounce_velocity: Vector3 = retained + up * pop_speed
		p.velocity = p.limit_homing_bounce_from_below(bounce_velocity, target_position, up)

	p.attached = false
	p._homing_active = false
	p._homing_target = null
	p._homing_target_position = Vector3.ZERO
	p._homing_target_position_valid = false
	p._homing_saved_velocity = Vector3.ZERO
	p._homing_saved_lateral = Vector3.ZERO
	p._homing_saved_speed_mag = 0.0
	p._homing_elapsed = 0.0
	p._homing_post_attack_timer = max(p.homing_post_attack_time, 0.0)
	p.refresh_airborne_abilities()


func apply_damage(_amount: int = 1, _source: Node = null) -> void:
	if _is_post_race_protected():
		return
	var p = _owner
	if p._level_load_suspended:
		return
	if p._is_dead or p._player_state_locked:
		return
	if p._damage_hit_invuln_timer > 0.0:
		return
	p._begin_enemy_hurt_boundary_pass_through(_source)
	_on_player_hurt()
	if p._hurt_action != null:
		p._sync_hurt_state_to_action()
		p._hurt_action.apply_damage(_amount, _source)
		p._sync_hurt_state_from_action()
		p._capture_enemy_hurt_boundary_launch_velocity()
		return
	if not p._network_is_local_authority():
		return

	var up: Vector3 = p._physics_up_last.normalized()
	if up.length() < 0.001:
		up = p._get_gravity_up()

	var hit_dir: Vector3 = Vector3.ZERO
	if _source != null and is_instance_valid(_source) and _source is Node3D:
		hit_dir = p.global_position - (_source as Node3D).global_position
	else:
		hit_dir = -p.global_transform.basis.z
	hit_dir -= up * hit_dir.dot(up)
	if hit_dir.length() < 0.001:
		hit_dir = -p.global_transform.basis.z
		hit_dir -= up * hit_dir.dot(up)
	if hit_dir.length() < 0.001:
		hit_dir = Vector3.FORWARD
	hit_dir = hit_dir.normalized()

	var v: Vector3 = p.velocity
	var vertical: float = v.dot(up)
	var lateral: Vector3 = v - up * vertical
	var speed: float = lateral.length()
	var hurt_speed_threshold: float = max(p.damage_trip_speed_threshold, 0.0)
	var moving_hurt: bool = speed >= hurt_speed_threshold

	if speed >= p.damage_trip_speed_threshold:
		lateral *= clamp(p.damage_trip_speed_multiplier, 0.0, 1.0)
	else:
		lateral = hit_dir * max(p.damage_pushback_speed, 0.0)
		if not moving_hurt and _source != null and is_instance_valid(_source) and _source is Node3D:
			var face_dir: Vector3 = (_source as Node3D).global_position - p.global_position
			face_dir -= up * face_dir.dot(up)
			if face_dir.length() > 0.001:
				face_dir = face_dir.normalized()
				var look_basis: Basis = Basis().looking_at(face_dir, up)
				if p.model_root != null and is_instance_valid(p.model_root):
					var mt: Transform3D = p.model_root.global_transform
					mt.basis = look_basis.orthonormalized()
					p.model_root.global_transform = mt
				else:
					var gt: Transform3D = p.global_transform
					gt.basis = look_basis.orthonormalized()
					p.global_transform = gt

	vertical = max(vertical, max(p.damage_launch_upward_speed, 0.0))

	p.velocity = lateral + up * vertical
	p.attached = false
	p._attachment_immunity = p.launch_immunity_time
	p._airborne_time = 0.0
	p._jumped_from_ground = false
	p._falling_without_jump = true
	p._jump_variable = false
	p._jump_hang_allowed = false
	p._jump_time = 0.0
	p._is_jumping = false

	if p._homing_active or p._homing_target != null:
		p.cancel_homing_attack(false)
	p._stop_lightspeed_dash_if_active(false)
	p._cancel_spindash_charge()
	p._jump_dashing = false
	p._jump_dash_requested = false
	p._bounce_state = p.BounceState.NONE
	p.rolling = false

	if p.has_method("cancel_spline_spring"):
		p.call("cancel_spline_spring")
	if p.has_method("cancel_rail_grind"):
		p.call("cancel_rail_grind")

	p._hurt_active = true
	p._hurt_state_timer = 0.0
	p._hurt_flash_accum = 0.0
	p._hurt_flash_visible = true
	_set_hurt_flash_visible(true)
	p._damage_hit_invuln_timer = max(p.damage_hit_invuln_time, 0.0)
	p._capture_enemy_hurt_boundary_launch_velocity()
	if moving_hurt:
		p._trigger_anim_command(&"CMD_HURT_MOVING")
	else:
		p._trigger_anim_command(&"CMD_HURT")


func apply_death_plane_damage(_source: Node = null) -> void:
	if _is_post_race_protected():
		return
	var p = _owner
	if p._level_load_suspended:
		return
	if p._is_dead or p._player_state_locked:
		return
	_on_player_hurt()
	if p._hurt_action != null:
		p._sync_hurt_state_to_action()
		p._hurt_action.apply_death_plane_damage(_source)
		p._sync_hurt_state_from_action()
		return
	begin_death_sequence(&"pit")


func _on_player_hurt() -> void:
	var p = _owner
	p.clear_air_trick_bank()
	if p._trick_system != null:
		if not p._trick_system.current_air_tricks.is_empty():
			p._trick_system.cancel_combo(true)


func set_death_state(dead: bool) -> void:
	if dead and _is_post_race_protected():
		return
	var p = _owner
	if dead and p._level_load_suspended:
		return
	p._is_dead = dead
	if dead:
		if p._active_death_type == &"":
			p._active_death_type = &"generic"
		p.clear_gravity_state(&"death")
		_on_player_hurt()
	else:
		p._active_death_type = &""
		p.clear_air_trick_bank()
		# If we were dead and are now being resurrected (e.g. race restart),
		# make sure we clear the input block if it was set by the death sequence.
		if p._ui_input_blocked:
			p.set_ui_input_blocked(false)
		p._player_state_locked = false

		# Ensure combo system is in a clean state
		if p._trick_system != null:
			p._trick_system.cancel_combo()
			p._trick_system.reset_air_trick_staleness()

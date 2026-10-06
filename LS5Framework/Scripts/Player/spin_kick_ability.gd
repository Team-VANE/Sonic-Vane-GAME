class_name SpinKickAbility
extends CharacterAbility

@export_group("Spin Kick")
@export_subgroup("Movement")
@export var tornado_refresh_coyote: bool = false
@export var tornado_refresh_duration: float = 1.2
@export var air_forward_min_speed: float = 75.0
@export var ground_decel_per_sec: float = 24.0
@export var ground_duration: float = 0.8
@export var air_duration: float = 0.8
## Current action ids that can route into grounded Spin Kick. Empty allows any grounded state.
@export var spin_kick_allowed_source_actions: Array[StringName] = [&"", &"grounded"]
## Current action ids that can route into airborne Tornado Kick. Empty allows any airborne state.
@export var tornado_kick_allowed_source_actions: Array[StringName] = [&"fall", &"jump", &"propeller_flight", &"bounce", &"stomp", &"uppercut_kick"]

@export_subgroup("Kick Contacts")
## Shared right-foot contact controller.
@export var kick_contacts: KickContactController
## Time after activation when kick contacts become active.
@export var attack_start_time: float = 0.0
## Time before completion when kick contacts end.
@export var attack_recovery_time: float = 0.08

@export_subgroup("Audio")
## Sound played when Spin Kick starts on the ground.
@export var spin_kick_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Spin_Kick.ogg")
## Sound played when Tornado Kick starts in the air.
@export var tornado_kick_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Tornado_Kick.ogg")

@export_subgroup("Action Chain Routes")
@export_multiline var on_air_action_pressed_action_tooltip: String = "Route for Ability Slot 2 while Tornado Kick is active (e.g., bounce/stomp)."
@export var on_air_action_pressed_action: NodePath
@export_multiline var on_air_jump_pressed_action_tooltip: String = "Route for jump press in air to a Jump action when coyote jump is available."
@export var on_air_jump_pressed_action: NodePath
@export_multiline var on_air_jump_pressed_no_coyote_action_tooltip: String = "Route for jump press in air when coyote jump is NOT available (e.g., Jump Dash)."
@export var on_air_jump_pressed_no_coyote_action: NodePath

var _active: bool = false
var _air_started: bool = false
var _timer: float = 0.0
var _baseline_lateral_speed: float = 0.0
var _rival_cooldown: float = 0.0

func _on_action_initialized() -> void:
	action_id = &"spin_kick"
	allow_when_inactive = true
	continuous_update = true
	permits_attack_magnetism = true
	if input_action == &"":
		input_action = &"ability_slot_03"


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func on_action_pressed() -> void:
	execute({"reason": &"pressed"})

func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if not should_trigger_from_input(input_name, mode):
		return false
	return execute({"reason": &"pressed"})

func can_execute(context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if _is_rival_owner() and _rival_cooldown > 0.0:
		return false
	if not _source_action_allowed(context):
		return false
	if not owner_player.attached and owner_player.has_method("can_use_tornado_kick"):
		if not owner_player.can_use_tornado_kick():
			return false
	return true


func get_input_prompt(context: Dictionary = {}) -> Dictionary:
	if _active:
		return {}
	var prompt: Dictionary = super.get_input_prompt(context)
	if not prompt.is_empty() and not owner_player.attached and input_prompt_name.is_empty():
		prompt["label"] = "Tornado Kick"
	return prompt

func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if _active:
		return false
	if owner_player != null and owner_player.has_method("get_current_action_id"):
		if owner_player.get_current_action_id() == action_id:
			return false
	_active = true
	_air_started = false
	_timer = 0.0
	var v: Vector3 = owner_player.velocity
	var lateral: Vector3 = get_gravity_planar_component(v)
	_baseline_lateral_speed = lateral.length()
	if not activate(context):
		_active = false
		_timer = 0.0
		_baseline_lateral_speed = 0.0
		return false
	if owner_player.has_method("cancel_bounce_stomp_for_action"):
		owner_player.cancel_bounce_stomp_for_action()
	if kick_contacts:
		kick_contacts.begin_kick(&"spin" if owner_player.attached else &"tornado", get_owner_gravity_up())
	_update_attack_window()
	if owner_player.attached:
		_play_kick_sound(spin_kick_sound)
		if owner_player.has_method("_trigger_anim_command"):
			owner_player._trigger_anim_command(&"CMD_SPIN_KICK")
	else:
		_play_kick_sound(tornado_kick_sound)
		if owner_player.has_method("_trigger_anim_command"):
			owner_player._trigger_anim_command(&"CMD_TORNADO_KICK")
	return true

func on_action_exit(_next_action: CharacterAction) -> void:
	if kick_contacts:
		kick_contacts.end_kick()
	_active = false
	_air_started = false
	_timer = 0.0
	_baseline_lateral_speed = 0.0
	if owner_player != null and owner_player.has_method("set_attack_active"):
		owner_player.set_attack_active(false)
	if _is_rival_owner():
		_rival_cooldown = 0.5

func continuous_physics_update(delta: float) -> void:
	if _rival_cooldown > 0.0:
		_rival_cooldown = max(0.0, _rival_cooldown - delta)


func _is_rival_owner() -> bool:
	return owner_player != null and owner_player.has_meta("is_rival_actor")


func _source_action_allowed(context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	var source_action: StringName = _get_source_action_id(context)
	if owner_player.attached:
		return _action_id_in_allowed_sources(source_action, spin_kick_allowed_source_actions)
	return _action_id_in_allowed_sources(source_action, tornado_kick_allowed_source_actions)


func _get_source_action_id(context: Dictionary = {}) -> StringName:
	if context.has("source_action"):
		return StringName(context.get("source_action", &""))
	if owner_player != null and owner_player.has_method("get_current_action_id"):
		return owner_player.get_current_action_id()
	return &""


func _action_id_in_allowed_sources(action_id_value: StringName, allowed_sources: Array[StringName]) -> bool:
	if allowed_sources.is_empty():
		return true
	for allowed_action_id: StringName in allowed_sources:
		if allowed_action_id == action_id_value:
			return true
	return false


func _play_kick_sound(sound: AudioStream) -> void:
	if owner_player == null or sound == null:
		return
	var player: AudioStreamPlayer3D = owner_player.sfx_player
	if player == null:
		return
	player.stream = sound
	player.play()


func physics_update_action(delta: float) -> void:
	if owner_player == null:
		return
	if not _active:
		return
	_timer += delta
	_update_attack_window()
	var v: Vector3 = owner_player.velocity
	var vertical: float = get_gravity_vertical_component(v)
	var lateral: Vector3 = get_gravity_planar_component(v)
	var lateral_len: float = lateral.length()
	if owner_player.attached:
		if _air_started:
			if owner_player.has_method("clear_active_action"):
				owner_player.call("clear_active_action")
			return
		var decel_step: float = max(ground_decel_per_sec, 0.0) * owner_player.get_movement_delta(delta)
		if lateral_len > 0.0001:
			var new_len: float = max(lateral_len - decel_step, 0.0)
			lateral = lateral.normalized() * new_len
			v = compose_gravity_vector(lateral, vertical)
			owner_player.velocity = v
		if _timer >= max(ground_duration, 0.0):
			if owner_player.has_method("clear_active_action"):
				owner_player.call("clear_active_action")
			return
	else:
		if not owner_player.uses_character_ability_profile() and SettingsManager.is_gameplay_action_just_pressed("ability_slot_02"):
			if process_ability_routes(
				&"ability_slot_02",
				ActionTrigger.JUST_PRESSED,
				{"reason": &"air_action_pressed", "source_action": action_id}
			):
				return
		if not owner_player.uses_character_ability_profile() and SettingsManager.is_gameplay_action_just_pressed("ability_slot_02") and on_air_action_pressed_action != NodePath():
			if execute_routed_action(
				on_air_action_pressed_action,
				{"reason": &"air_action_pressed", "source_action": action_id}
			):
				return
		var jump_slot: StringName = owner_player.get_ability_input_slot(&"jump", &"ability_slot_01")
		if SettingsManager.is_gameplay_action_just_pressed(String(jump_slot)):
			var can_coyote: bool = false
			if owner_player.has_method("_can_consume_coyote_jump"):
				can_coyote = bool(owner_player.call("_can_consume_coyote_jump"))
			if can_coyote:
				if owner_player.has_method("queue_coyote_jump"):
					owner_player.queue_coyote_jump()
				if execute_manual_route(
					&"coyote_jump",
					{"reason": &"air_jump_pressed", "source_action": action_id}
				):
					return
				if on_air_jump_pressed_action != NodePath():
					if execute_routed_action(
						on_air_jump_pressed_action,
						{"reason": &"air_jump_pressed", "source_action": action_id}
					):
						return
				if owner_player.has_method("clear_active_action"):
					owner_player.call("clear_active_action")
				return
			else:
				if execute_manual_route(
					&"no_coyote_jump",
					{"reason": &"air_jump_pressed_no_coyote", "source_action": action_id}
				):
					return
				if on_air_jump_pressed_no_coyote_action != NodePath():
					if execute_routed_action(
						on_air_jump_pressed_no_coyote_action,
						{"reason": &"air_jump_pressed_no_coyote", "source_action": action_id}
					):
						return
		if not _air_started:
			var dir: Vector3 = lateral
			if dir.length() < 0.001:
				dir = get_gravity_planar_component(owner_player._model_forward)
			if dir.length() > 0.001:
				dir = dir.normalized()
			var min_spd: float = max(air_forward_min_speed, 0.0)
			if lateral_len < min_spd and dir.length() > 0.001:
				lateral = dir * min_spd
				lateral_len = min_spd
			if vertical < 0.0:
				vertical = 0.0
			elif vertical > 0.0:
				vertical *= 0.5
			v = compose_gravity_vector(lateral, vertical)
			owner_player.velocity = v
			if tornado_refresh_coyote:
				if owner_player.has_method("refresh_coyote_jump_window_custom"):
					owner_player.refresh_coyote_jump_window_custom(tornado_refresh_duration)
			else:
				if owner_player.has_method("remove_coyote_jump_eligibility"):
					owner_player.remove_coyote_jump_eligibility()
			if owner_player.has_method("mark_tornado_kick_used"):
				owner_player.mark_tornado_kick_used()
			_air_started = true
		if _timer >= max(air_duration, 0.0):
			if owner_player.has_method("activate_neutral_air_action"):
				owner_player.call("activate_neutral_air_action", {"reason": &"spin_kick_complete", "source_action": action_id})
			return


func _update_attack_window() -> void:
	var attack_duration: float = ground_duration if owner_player.attached else air_duration
	var attacking: bool = _timer >= max(attack_start_time, 0.0) and _timer < max(attack_duration - attack_recovery_time, 0.0)
	owner_player.set_attack_active(attacking)
	if kick_contacts:
		kick_contacts.set_contact_active(attacking)

class_name UppercutKickAbility
extends CharacterAbility

@export_group("Uppercut Kick")
## Ground launch speed relative to the character's normal jump.
@export var ground_jump_speed_multiplier: float = 1.25
## Air launch speed relative to the character's normal jump.
@export var air_jump_speed_multiplier: float = 0.65
## Tangential velocity retained when the kick launches.
@export_range(0.0, 1.0, 0.01) var horizontal_speed_retention: float = 0.85
## Maximum interval between the two chord presses.
@export var chord_press_window: float = 0.08
## Duration before returning to the neutral airborne action.
@export var duration: float = 0.55
## Time after activation when kick contacts become active.
@export var attack_start_time: float = 0.0
## Time after activation when kick contacts end.
@export var attack_end_time: float = 0.45
## Shared right-foot contact controller.
@export var kick_contacts: KickContactController
## Action identifiers permitted to start an Uppercut Kick.
@export var allowed_source_actions: Array[StringName] = [&"", &"grounded", &"rail_grind", &"spin_kick", &"jump", &"fall", &"bounce", &"bounce_rebound", &"stomp", &"propeller_flight"]
## Animation command for the Uppercut state.
@export var animation_command: StringName = &"CMD_UPPERCUT_KICK"
## Sound played when the kick launches.
@export var activation_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Spin_Kick.ogg")

@export_subgroup("Wall Fatigue")
## Reduces Uppercut launch strength after repeated parkour kicks from similarly oriented walls.
@export var wall_fatigue_enabled: bool = true
## Uppercut launch strength after kicking the same wall again without a replenishing interaction.
@export_range(0.0, 1.0, 0.01) var same_wall_minimum_strength: float = 0.25
## Wall-normal angle that restores full Uppercut strength relative to the previous kicked wall.
@export_range(1.0, 180.0, 1.0, "suffix:deg") var wall_fatigue_full_strength_angle: float = 90.0

var airborne_use_available: bool = true
var _last_kicked_wall_normal: Vector3 = Vector3.ZERO
var _wall_kick_strength: float = 1.0
var _active: bool = false
var _elapsed: float = 0.0
var _input_latched: bool = false
var _latched_slots: Array[StringName] = []
var _first_press_age: float = INF
var _first_press_grounded: bool = false
var _first_press_on_rail: bool = false
var _first_press_up: Vector3 = Vector3.UP
var _first_press_velocity: Vector3 = Vector3.ZERO
var _first_press_source: StringName = &""
var _first_press_jump_dash_used: bool = false


func _on_action_initialized() -> void:
	action_id = &"uppercut_kick"
	input_action = &"ability_slot_03"
	continuous_update = true
	shows_jump_ball = false
	permits_attack_magnetism = true


func get_input_prompt_stage() -> InputPromptStage:
	return InputPromptStage.PRIORITY


func can_execute(context: Dictionary = {}) -> bool:
	if not owner_player or not super.can_execute(context) or _active:
		return false
	if owner_player._is_dead or owner_player._hurt_active or owner_player.race_in_countdown:
		return false
	if owner_player._ui_input_blocked or owner_player._local_pause_enabled or owner_player._post_ui_unblock_action_suppress_timer > 0.0:
		return false
	if owner_player.get_tree().paused or owner_player._spline_active or owner_player._vault_bar_active:
		return false
	if owner_player._rail_active and (not owner_player._rail_allow_jump_exit or owner_player._spring_movement_lock_timer > 0.0):
		return false
	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._automation_lock_actions and owner_player._automation_locks_active():
		return false
	var source: StringName = StringName(context.get("source_action", &"rail_grind" if owner_player._rail_active else owner_player.get_current_action_id()))
	if not allowed_source_actions.is_empty() and not allowed_source_actions.has(source):
		return false
	var ground_launch: bool = bool(context.get("ground_launch", owner_player.attached))
	if ground_launch and not bool(context.get("rail_launch", owner_player._rail_active)) and owner_player.is_surface_jump_blocked():
		return false
	return ground_launch or airborne_use_available


func prepare_priority_input(delta: float) -> bool:
	if not owner_player or not owner_player._network_is_local_authority() or owner_player.has_meta("is_rival_actor") or owner_player.has_meta("is_buddy"):
		return false
	if _input_latched:
		if not _any_slot_pressed(_latched_slots):
			_input_latched = false
		return true
	_first_press_age += max(delta, 0.0)
	var slots: Array[StringName] = _get_chord_slots()
	if slots.is_empty():
		return false
	var just_pressed: bool = false
	var all_pressed: bool = true
	var all_just_pressed: bool = true
	for slot: StringName in slots:
		if EmoteWheel.is_action_blocked(slot):
			return false
		just_pressed = just_pressed or SettingsManager.is_gameplay_action_just_pressed(String(slot))
		all_pressed = all_pressed and SettingsManager.is_gameplay_action_pressed(String(slot))
		all_just_pressed = all_just_pressed and SettingsManager.is_gameplay_action_just_pressed(String(slot))
	if just_pressed and (not all_pressed or all_just_pressed):
		_first_press_age = 0.0
		_first_press_grounded = owner_player.attached
		_first_press_on_rail = owner_player._rail_active
		_first_press_up = _get_launch_up(_first_press_grounded)
		_first_press_velocity = _get_entry_velocity()
		_first_press_source = &"rail_grind" if _first_press_on_rail else owner_player.get_current_action_id()
		_first_press_jump_dash_used = owner_player._jump_dash_used_this_air
	if not just_pressed or not all_pressed or _first_press_age > max(chord_press_window, 0.0):
		return false
	var context: Dictionary = {
		"reason": &"uppercut_chord",
		"source_action": _first_press_source,
		"ground_launch": _first_press_grounded,
		"rail_launch": _first_press_on_rail,
		"launch_up": _first_press_up if _first_press_grounded else get_owner_gravity_up(),
		"entry_velocity": _first_press_velocity,
		"jump_dash_was_used": _first_press_jump_dash_used,
	}
	if owner_player._ability_input_router and owner_player._ability_input_router.has_binding(action_id):
		if not owner_player._ability_input_router.is_binding_simultaneously_just_pressed(action_id, input_action, chord_press_window):
			return false
	if not execute(context):
		return false
	_input_latched = true
	_latched_slots = slots.duplicate()
	if owner_player._ability_input_router:
		owner_player._ability_input_router.suppress_slots_until_release(slots)
	return true


func _get_chord_slots() -> Array[StringName]:
	if owner_player._ability_input_router and owner_player._ability_input_router.has_binding(action_id):
		return owner_player._ability_input_router.get_input_slots(action_id)
	var slots: Array[StringName] = [owner_player.get_ability_input_slot(&"spin_kick", &"ability_slot_03")]
	var jump_slot: StringName = owner_player.get_ability_input_slot(&"jump", &"ability_slot_01")
	if not slots.has(jump_slot):
		slots.append(jump_slot)
	return slots


func _any_slot_pressed(slots: Array[StringName]) -> bool:
	for slot: StringName in slots:
		if SettingsManager.is_gameplay_action_pressed(String(slot)):
			return true
	return false


func process_input_event(_input_name: StringName, _mode: ActionTrigger) -> bool:
	return false


func _get_launch_up(ground_launch: bool) -> Vector3:
	if owner_player._rail_active:
		return owner_player.get_rail_surface_up()
	return owner_player.surface_normal if ground_launch else get_owner_gravity_up()


func _get_entry_velocity() -> Vector3:
	if owner_player._rail_active:
		return owner_player._rail_last_motion_dir.normalized() * abs(owner_player._rail_speed)
	return owner_player.velocity


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	var ground_launch: bool = bool(context.get("ground_launch", owner_player.attached))
	var up: Vector3 = context.get("launch_up", _get_launch_up(ground_launch))
	if up.length_squared() < 0.0001:
		up = get_owner_gravity_up()
	up = up.normalized()
	if ground_launch and up.dot(get_owner_gravity_up()) > 0.7:
		refresh_airborne_abilities()
	var entry_velocity: Vector3 = context.get("entry_velocity", _get_entry_velocity())
	if not activate(context):
		return false
	if owner_player._rail_active:
		owner_player._end_rail(false, get_owner_gravity_up())
	if owner_player._rail_switch_active:
		owner_player._cancel_rail_switch()
	_active = true
	_elapsed = 0.0
	if not ground_launch:
		airborne_use_available = false
	owner_player.cancel_homing_attack(false)
	owner_player.cancel_bounce_stomp_for_action()
	owner_player._cancel_spindash_charge()
	owner_player._jump_requested = false
	owner_player._coyote_jump_requested = false
	owner_player._jump_dash_requested = false
	owner_player._jump_dash_recent_timer = 0.0
	owner_player._jump_dash_used_this_air = bool(context.get("jump_dash_was_used", owner_player._jump_dash_used_this_air))
	owner_player._jump_variable = false
	owner_player._jump_hang_allowed = false
	owner_player._jump_time = 0.0
	owner_player._is_jumping = false
	owner_player._jumped_from_ground = false
	owner_player.remove_coyote_jump_eligibility()
	if ground_launch:
		owner_player._record_detach_state(up, get_owner_gravity_up())
	owner_player.attached = false
	owner_player._attachment_immunity = owner_player.launch_immunity_time
	owner_player._airborne_time = 0.0
	owner_player._falling_without_jump = true
	var vertical: float = entry_velocity.dot(up)
	var lateral: Vector3 = entry_velocity - up * vertical
	var multiplier: float = ground_jump_speed_multiplier if ground_launch else air_jump_speed_multiplier
	var launch_speed: float = max(owner_player.jump_speed * multiplier, 0.0)
	if wall_fatigue_enabled:
		launch_speed *= _wall_kick_strength
	owner_player.velocity = lateral * clamp(horizontal_speed_retention, 0.0, 1.0) + up * max(vertical, launch_speed)
	if kick_contacts:
		kick_contacts.begin_kick(&"uppercut", up)
	_update_attack_window()
	owner_player._trigger_anim_command(animation_command)
	if activation_sound and owner_player.sfx_player:
		owner_player.sfx_player.stream = activation_sound
		owner_player.sfx_player.play()
	return true


func physics_update_action(delta: float) -> void:
	if not _active or not owner_player:
		return
	_elapsed += max(delta, 0.0)
	if owner_player.attached or _elapsed >= max(duration, 0.0):
		if owner_player.attached:
			owner_player.clear_active_action()
		else:
			owner_player.activate_neutral_air_action({"reason": &"uppercut_complete", "source_action": action_id})
		return
	_update_attack_window()


func _update_attack_window() -> void:
	var attacking: bool = _elapsed >= max(attack_start_time, 0.0) and _elapsed < min(attack_end_time, duration)
	owner_player.set_attack_active(attacking)
	if kick_contacts:
		kick_contacts.set_contact_active(attacking)


func on_action_exit(next_action: CharacterAction) -> void:
	_active = false
	if kick_contacts:
		kick_contacts.end_kick()
	if owner_player:
		owner_player.set_attack_active(false)
		if next_action and next_action.action_id == &"fall":
			owner_player._trigger_anim_command(&"FallBlend")


func notify_wall_kick(normal: Vector3) -> void:
	if not normal or not normal.is_finite():
		return
	normal = normal.normalized()
	_wall_kick_strength = 1.0
	if wall_fatigue_enabled and _last_kicked_wall_normal:
		var angle: float = rad_to_deg(acos(clampf(normal.dot(_last_kicked_wall_normal), -1.0, 1.0)))
		var recovery: float = clampf(angle / maxf(wall_fatigue_full_strength_angle, 1.0), 0.0, 1.0)
		_wall_kick_strength = lerpf(clampf(same_wall_minimum_strength, 0.0, 1.0), 1.0, recovery)
	_last_kicked_wall_normal = normal


func refresh_airborne_availability() -> void:
	airborne_use_available = true
	_first_press_age = INF


func refresh_airborne_abilities() -> void:
	refresh_airborne_availability()
	_reset_wall_fatigue()


func _reset_wall_fatigue() -> void:
	_last_kicked_wall_normal = Vector3.ZERO
	_wall_kick_strength = 1.0


func reset_traversal_history() -> void:
	refresh_airborne_abilities()


func continuous_physics_update(_delta: float) -> void:
	if not owner_player:
		return
	if owner_player._is_dead or (owner_player.attached and owner_player.surface_normal.normalized().dot(get_owner_gravity_up()) > 0.7):
		airborne_use_available = true
		_reset_wall_fatigue()


func resolve_landing_momentum(_landing_normal: Vector3, _incoming_velocity: Vector3) -> bool:
	refresh_airborne_availability()
	if _landing_normal.normalized().dot(get_owner_gravity_up()) > 0.7:
		refresh_airborne_abilities()
	return false


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false

class_name RollAction
extends CharacterAction

@export_group("Roll")

@export_subgroup("Activation")
@export var roll_enabled: bool = true

@export_subgroup("Movement")
@export var roll_decel: float = 3.0
## Speed-proportional resistance applied while rolling on a surface.
@export var roll_linear_drag: float = 0.0
## Squared-speed resistance applied while rolling on a surface.
@export var roll_quadratic_drag: float = 0.0005
@export var roll_air_decel: float = 2.5
@export var roll_turn_deg_per_sec: float = 140.0
## Applies airborne top-speed soft-cap rules while rolling in air.
@export var roll_air_top_speed_slowdown_enabled: bool = false
## Fraction of airborne top-speed slowdown applied while rolling.
@export var roll_top_speed_slowdown_scale: float = 0.2

@export_subgroup("Movement/Slope")
## Applies ordinary roll surface resistance while rolling on slopes and loop surfaces.
@export var roll_slope_surface_resistance_enabled: bool = false
@export var roll_downhill_accel_multiplier: float = 2.4
## Optional rolling downhill acceleration multiplier by lateral speed.
## X: lateral speed, Y: multiplier.
@export var roll_downhill_accel_multiplier_curve: Curve
@export var roll_uphill_decel_multiplier: float = 2.3
## Optional rolling uphill deceleration multiplier by lateral speed.
## X: lateral speed, Y: multiplier.
@export var roll_uphill_decel_multiplier_curve: Curve
## Final rolling slope response power by surface angle.
## X: surface angle in degrees, Y: power multiplier.
@export var roll_slope_gravity_angle_curve: Curve

@export_subgroup("Animation")
## Minimum roll animation playback scale.
@export var roll_anim_min_scale: float = 0.0
## Maximum roll animation playback scale.
@export var roll_anim_max_scale: float = 1.4
## Lateral speed that reaches the maximum roll animation scale.
@export var roll_anim_speed_for_max: float = 90.0

@export_subgroup("Audio/Transitions")
## Sound played when entering the curled roll state.
@export var roll_start_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Roll_Start.wav")
## Roll-start sound volume.
@export var roll_start_volume_db: float = -15.0
## Roll-start sound pitch.
@export var roll_start_pitch_scale: float = 1.0
## Sound played when leaving the curled roll state.
@export var roll_end_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Roll_End.wav")
## Roll-end sound volume.
@export var roll_end_volume_db: float = -15.0
## Roll-end sound pitch.
@export var roll_end_pitch_scale: float = 1.0

@export_subgroup("Audio/Loop")
## Speed-driven loop played while rolling.
@export var roll_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/Roll_Loop.ogg")
## Tangential speed where the roll loop starts fading in at minimum volume.
@export var roll_loop_volume_min_speed: float = 5.0
## Tangential speed where the roll loop reaches maximum volume.
@export var roll_loop_volume_full_speed: float = 90.0
## Roll-loop volume at the volume minimum speed.
@export var roll_loop_volume_min_db: float = -50.0
## Roll-loop volume at full speed.
@export var roll_loop_volume_max_db: float = -21.0
## Tangential speed where roll-loop pitch begins increasing.
@export var roll_loop_pitch_min_speed: float = 5.0
## Tangential speed where roll-loop pitch reaches its maximum value.
@export var roll_loop_pitch_full_speed: float = 90.0
## Roll-loop pitch at the pitch minimum speed.
@export var roll_loop_pitch_min: float = 0.45
## Roll-loop pitch at full speed.
@export var roll_loop_pitch_max: float = 1.0
## Blend speed for tangential-speed-driven volume and pitch changes.
@export var roll_loop_lerp_speed: float = 500.0
## Fade-in rate in decibels per second.
@export var roll_loop_fade_in_speed_db: float = 500.0
## Fade-out rate in decibels per second.
@export var roll_loop_fade_out_speed_db: float = 500.0
## Volume where the inactive roll loop stops playback.
@export var roll_loop_stop_volume_db: float = -80.0

@export_subgroup("Transitions")
## Roll-spindash lockout when rolling from skydive.
@export var skydive_roll_spindash_lockout: float = 0.6

var is_rolling: bool = false
var routed_toggle_active: bool = false
var _collision_uncurl_requested: bool = false


func _on_action_initialized() -> void:
	action_id = &"roll"
	input_action = &"ability_slot_04"
	trigger_mode = ActionTrigger.PRESSED
	continuous_update = false
	allow_when_inactive = true
	permits_attack_magnetism = true


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if not should_trigger_from_input(input_name, mode):
		return false
	if is_rolling:
		if routed_toggle_active:
			routed_toggle_active = false
			_set_rolling(false)
			_clear_active_roll()
		return true
	return execute({"reason": &"roll_pressed", "source_action": _get_current_source_action()})


func can_execute(context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if not enabled or not roll_enabled:
		return false
	if owner_player.has_method("is_surface_roll_blocked") and owner_player.is_surface_roll_blocked():
		return false
	if not owner_player.is_surface_roll_forced() and not _route_policy_allows(context):
		return false
	return _can_start_roll()


func get_input_prompt_stage() -> InputPromptStage:
	return InputPromptStage.BEFORE_ROUTES


func get_input_prompt(context: Dictionary = {}) -> Dictionary:
	if not input_prompt_enabled or not enabled:
		return {}
	if StringName(context.get("activation", &"")) == &"toggle_off":
		return {"label": "Uncurl"} if routed_toggle_active else {}
	var prompt: Dictionary = super.get_input_prompt(context)
	if not prompt.is_empty() and not context.has("route"):
		prompt["gesture"] = &"hold"
	return prompt


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if not activate(context):
		return false
	_set_rolling(true)
	_apply_skydive_roll_lockout(context)
	return true


func force_start_from_surface() -> bool:
	if is_rolling:
		return true
	return execute({"reason": &"surface_force_roll", "source_action": _get_current_source_action()})


func set_routed_toggle_active(toggle_active: bool, context: Dictionary = {}) -> bool:
	if toggle_active:
		if not can_execute(context):
			return false
		routed_toggle_active = true
		if not activate(context):
			routed_toggle_active = false
			return false
		_set_rolling(true)
		_apply_skydive_roll_lockout(context)
		return true
	if not routed_toggle_active:
		return false
	routed_toggle_active = false
	_end_roll_if_active()
	return true


func on_action_enter(_context: Dictionary = {}) -> void:
	_set_rolling(true)


func on_action_exit(next_action: CharacterAction) -> void:
	routed_toggle_active = false
	_set_rolling(false, next_action != null)


func physics_update_action(_delta: float) -> void:
	if owner_player == null:
		return
	var jump_slot: StringName = owner_player.get_ability_input_slot(&"jump", &"ability_slot_01")
	if SettingsManager.is_gameplay_action_just_pressed(String(jump_slot)):
		if process_ability_routes(
			jump_slot,
			ActionTrigger.JUST_PRESSED,
			{"reason": &"roll_jump", "source_action": action_id}
		):
			return
	continuous_physics_update(_delta)


func continuous_physics_update(_delta: float) -> void:
	if owner_player == null:
		return
	if not owner_player._network_is_local_authority():
		_end_roll_if_active()
		return
	if owner_player._hurt_active:
		_end_roll_if_active()
		return
	if owner_player._local_pause_enabled or owner_player._ui_input_blocked or owner_player._debug_mode:
		_end_roll_if_active()
		return
	if owner_player.has_method("is_surface_roll_blocked") and owner_player.is_surface_roll_blocked():
		_end_roll_if_active()
		return

	var spindash_action = _get_spindash_action()
	if spindash_action != null and spindash_action.is_charging:
		_set_rolling(true)
		return

	if not roll_enabled:
		_end_roll_if_active()
		return

	var was_rolling: bool = is_rolling
	var surface_forced: bool = (
		owner_player.has_method("is_surface_roll_forced")
		and owner_player.is_surface_roll_forced()
	)
	var want_roll: bool = (
		routed_toggle_active
		or surface_forced
		or (input_action != &"" and SettingsManager.is_gameplay_action_pressed(String(input_action)))
	)
	if want_roll:
		_collision_uncurl_requested = false

	if is_rolling:
		if not want_roll or not _can_continue_roll():
			_set_rolling(false)
	else:
		if want_roll and _can_start_roll():
			_set_rolling(true)

	if is_rolling and not was_rolling:
		var context: Dictionary = {"reason": &"roll_pressed", "source_action": _get_current_source_action()}
		activate(context)
		_apply_skydive_roll_lockout(context)
	elif was_rolling and not is_rolling:
		if not bool(owner_player.get("attached")) and owner_player.has_method("note_airborne_roll_uncurl_attack"):
			owner_player.call("note_airborne_roll_uncurl_attack")
		_clear_active_roll()


func _can_start_roll() -> bool:
	if owner_player._is_dead or owner_player._hurt_active or owner_player._local_pause_enabled or owner_player._ui_input_blocked or owner_player._debug_mode:
		return false
	if owner_player.has_method("is_surface_roll_blocked") and owner_player.is_surface_roll_blocked():
		return false
	if not owner_player.is_surface_roll_forced() and not _route_policy_allows({"source_action": _get_current_source_action()}):
		return false
	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._rail_active or owner_player._spline_active:
		return false
	if owner_player._homing_active:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	return true


func _can_continue_roll() -> bool:
	if owner_player.has_method("is_surface_roll_blocked") and owner_player.is_surface_roll_blocked():
		return false
	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._rail_active or owner_player._spline_active:
		return false
	if owner_player._homing_active:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	return true


func _set_rolling(rolling_now: bool, action_transition: bool = false) -> void:
	if rolling_now or action_transition:
		_collision_uncurl_requested = false
	if is_rolling == rolling_now:
		return
	if not rolling_now and not action_transition and owner_player != null:
		if owner_player.has_method("try_uncurl_with_wall_recovery") and not owner_player.try_uncurl_with_wall_recovery():
			_collision_uncurl_requested = true
			return
	_collision_uncurl_requested = false
	is_rolling = rolling_now
	_notify_roll_changed(is_rolling)


func resolve_collision_uncurl_after_movement() -> bool:
	if not _collision_uncurl_requested or not is_rolling or owner_player == null:
		return false
	_collision_uncurl_requested = false
	if owner_player._active_action != self or not owner_player.attached:
		return false
	if owner_player._hurt_active or owner_player._spindash_charging:
		return false
	_set_rolling(false)
	_clear_active_roll()
	return not is_rolling


func _end_roll_if_active() -> void:
	routed_toggle_active = false
	if not is_rolling:
		return
	_set_rolling(false)
	_clear_active_roll()


func _clear_active_roll() -> void:
	if owner_player == null:
		return
	if is_rolling:
		return
	if not owner_player.has_method("get_current_action_id"):
		return
	if owner_player.get_current_action_id() != action_id:
		return
	if owner_player.has_method("clear_active_action"):
		owner_player.clear_active_action()


func _route_policy_allows(context: Dictionary = {}) -> bool:
	var source_action: StringName = _get_policy_source_action(context)
	if owner_player != null and owner_player.has_method("has_character_profile_route_channel"):
		if bool(owner_player.call("has_character_profile_route_channel", action_id, CharacterProfileManager.ROUTE_EVENT_POLICY)):
			return bool(owner_player.call("is_character_profile_action_allowed", action_id, source_action))
	if uses_authoritative_profile_routes():
		return true
	if routes.is_empty():
		return true
	var has_policy: bool = false
	var allow_match: bool = false
	var has_allow_list: bool = false
	for route_resource: Resource in routes:
		if not (route_resource is AbilityRoute):
			continue
		var route: AbilityRoute = route_resource
		if route == null or not route.enabled:
			continue
		if route.target_action != NodePath():
			continue
		if route.trigger_input != &"":
			continue
		has_policy = true
		for blocked_source: StringName in route.blocked_source_actions:
			if blocked_source == source_action:
				return false
		if route.allowed_source_actions.is_empty():
			allow_match = true
			continue
		has_allow_list = true
		for allowed_source: StringName in route.allowed_source_actions:
			if allowed_source == source_action:
				allow_match = true
				break
	if not has_policy:
		return true
	if has_allow_list:
		return allow_match
	return true


func _get_policy_source_action(context: Dictionary = {}) -> StringName:
	if context.has("source_action"):
		return StringName(context.get("source_action", &""))
	return _get_current_source_action()


func _get_current_source_action() -> StringName:
	if owner_player == null:
		return &""
	if owner_player.has_method("get_current_action_id"):
		var current_action_id: StringName = owner_player.get_current_action_id()
		if current_action_id != &"":
			return current_action_id
	if bool(owner_player.get("attached")):
		return &"grounded"
	return &"fall"


func _apply_skydive_roll_lockout(context: Dictionary = {}) -> void:
	if owner_player == null:
		return
	if StringName(context.get("source_action", &"")) != &"skydive":
		return
	if owner_player.has_method("set_spindash_roll_route_lockout"):
		owner_player.set_spindash_roll_route_lockout(skydive_roll_spindash_lockout)


func _notify_roll_changed(rolling_now: bool) -> void:
	if rolling_now and owner_player.has_method("_trigger_anim_command"):
		var spindash_action = _get_spindash_action()
		if spindash_action == null or not spindash_action.is_charging:
			owner_player._trigger_anim_command(&"ROLL")
	if owner_player.has_method("_notify_buddy_leader_roll_changed"):
		owner_player._notify_buddy_leader_roll_changed(rolling_now)


func _get_spindash_action():
	for a in owner_player._actions:
		if a is SpindashAction:
			return a
	return null

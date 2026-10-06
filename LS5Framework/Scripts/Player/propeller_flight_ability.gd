class_name PropellerFlightAbility
extends CharacterAbility

@export_group("Propeller Flight")

@export_subgroup("HUD")
## Name displayed while this ability drives the shared ability meter.
@export var ability_meter_name: String = "Flight"

@export_subgroup("Timing")
## Maximum active flight time before tiring. Set <= 0 for unlimited flight.
@export var max_flight_time: float = 6.0
## Limits flight to one activation before landing.
@export var once_per_air: bool = false
## Delay after landing before flight becomes available again.
@export var landing_reset_delay: float = 0.0
## Timer drain multiplier while climbing. Set 1.0 for normal drain.
@export var ascend_flight_drain_multiplier: float = 1.85
## Timer drain multiplier while cratering. Set 1.0 for normal drain.
@export var dive_flight_drain_multiplier: float = 0.45

@export_subgroup("Movement/Vertical")
## Minimum upward speed applied when flight starts. Set <= 0 to preserve entry velocity.
@export var start_min_vertical_speed: float = 0.0
## Gravity scale while flight is active with no vertical input.
@export var float_gravity_scale: float = 0.48
## Maximum downward speed while floating or climbing. Set <= 0 to disable.
@export var float_max_fall_speed: float = 35.0
## Maximum downward speed while exhausted and floating. Set <= 0 to use float_max_fall_speed.
@export var exhausted_float_max_fall_speed: float = 96.0
## Smoothing speed used when returning from dive fall speed to float fall speed.
@export var float_max_fall_speed_lerp_speed: float = 3.0
## Upward acceleration while the climb input is held.
@export var ascend_accel: float = 180.0
## Maximum upward speed while climbing.
@export var ascend_max_speed: float = 39.0
## Smoothing speed used when returning from entry upward speed to climb speed limits.
@export var ascend_max_speed_lerp_speed: float = 3.0
## Upward speed limit lost per lateral speed while climbing. Set <= 0 to disable.
@export var ascend_lateral_speed_penalty: float = 0.3
## Gravity scale while the dive input is held.
@export var dive_gravity_scale: float = 2.6
## Downward acceleration added while the dive input is held.
@export var dive_accel: float = 0.0
## Maximum downward speed while diving.
@export var dive_max_fall_speed: float = 135.0

@export_subgroup("Movement/Horizontal")
## Lateral top speed while propeller flying. Set <= 0 to disable.
@export var flight_top_speed: float = 105.0
## Deceleration used when propeller flight exceeds its lateral top speed.
@export var flight_top_speed_slowdown: float = 14.0
## Lateral acceleration while propeller flying when no curve is assigned.
@export var flight_accel: float = 23.0
## Speed used to normalize the flight acceleration curve to 0..1. Set <= 0 to sample by current speed.
@export var flight_accel_curve_speed: float = 0.0
## Optional lateral acceleration curve while propeller flying. Y is acceleration.
@export var flight_accel_curve: Curve = preload("res://LS5Framework/Resources/Player/DefaultPropellerFlightAccelCurve.tres")
## Lateral speed that climb/dive damping eases toward.
@export var damping_target_speed: float = 70.0
## Horizontal deceleration applied at full climb/dive damping.
@export var damping_decel: float = 30.0
## Seconds for climb/dive damping to reach full strength.
@export var damping_enter_time: float = 1.2
## Seconds for climb/dive damping to release after input stops.
@export var damping_exit_time: float = 0.75

@export_subgroup("Input")
## Input held to climb during flight.
@export var ascend_input_action: StringName = &"ability_slot_01"
## Input held to dive during flight.
@export var dive_input_action: StringName = &"ability_slot_02"
## Input pressed to exit flight.
@export var exit_input_action: StringName = &"interact"
## Route used when flight exits. Empty uses the neutral fall action.
@export var exit_action: NodePath

@export_subgroup("Animation")
## Animation command used when propeller flight starts.
@export var flight_animation_command: StringName = &"CMD_PROPELLERFLIGHT"
## AnimationTree blend parameter driven by climb/dive input.
@export var flight_blend_parameter: String = "parameters/StateMachine/FLIGHT_BLEND/blend_position"
## Blend position used while climbing.
@export var flight_blend_ascend_value: float = 1.0
## Blend position used while neutral.
@export var flight_blend_neutral_value: float = 0.0
## Blend position used while diving.
@export var flight_blend_dive_value: float = -1.0
## Blend smoothing speed for propeller flight input changes.
@export var flight_blend_lerp_speed: float = 8.0
## AnimationTree time-scale parameter for the flight blend tree.
@export var flight_time_scale_parameter: String = ""
## Animation speed with no climb or dive input.
@export var flight_time_scale_neutral: float = 1.15
## Animation speed while climb input is held.
@export var flight_time_scale_ascend: float = 1.45
## Animation speed while dive input is held.
@export var flight_time_scale_dive: float = 1.45
## Smoothing speed for flight animation speed changes.
@export var flight_time_scale_lerp_speed: float = 2.75

@export_subgroup("Audio")
## Audio player used for propeller flight loop sounds.
@export var propeller_flight_audio_node: NodePath
## Loop played while propeller flight has flight time remaining.
@export var propeller_flight_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/PropellerFlight.wav")
## Loop played while propeller flight is exhausted.
@export var propeller_flight_exhausted_loop_sound: AudioStream = preload("res://LS5Framework/Sounds/Abilities/PropellerFlight_Exhausted.wav")
## Volume used while floating during propeller flight.
@export var propeller_flight_volume_min_db: float = -6.0
## Volume used while climbing or diving during propeller flight.
@export var propeller_flight_volume_max_db: float = 0.0
## Pitch scale used while floating during propeller flight.
@export var propeller_flight_pitch_min: float = 0.95
## Pitch scale used while climbing or diving during propeller flight.
@export var propeller_flight_pitch_max: float = 1.15
## Lerp speed for propeller flight loop volume and pitch changes.
@export var propeller_flight_audio_lerp_speed: float = 8.0

var _active: bool = false
var _flight_time_remaining: float = 0.0
var _flight_gauge_max: float = 0.0
var _used_this_air: bool = false
var _landing_reset_timer: float = 0.0
var _exhausted: bool = false
var _damping_weight: float = 0.0
var _damping_input_was_held: bool = false
var _current_max_fall_speed: float = 0.0
var _current_ascend_max_speed: float = 0.0
var _flight_blend_value: float = 0.0
var _flight_time_scale_value: float = 1.0
var _current_loop_stream: AudioStream = null
var _propeller_flight_audio_player: AudioStreamPlayer3D = null
var _propeller_flight_audio_activity: float = 0.0


func _on_action_initialized() -> void:
	action_id = &"propeller_flight"
	allow_when_inactive = true
	continuous_update = true
	_reset_flight_timer_to_max()
	if input_action == &"":
		input_action = ascend_input_action


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if mode != ActionTrigger.JUST_PRESSED:
		return false
	if not should_trigger_from_input(input_name, mode):
		return false
	if max_flight_time > 0.0 and _flight_time_remaining <= 0.0:
		_play_exhausted_flight_voice()
	return execute({"reason": &"pressed"})


func get_input_prompt(_context: Dictionary = {}) -> Dictionary:
	return {}


func can_execute(_context: Dictionary = {}) -> bool:
	if not enabled:
		return false
	if owner_player == null:
		return false
	if owner_player.attached:
		return false
	if once_per_air and _used_this_air:
		return false
	if owner_player.race_in_countdown:
		return false
	if owner_player._hurt_active:
		return false
	if owner_player._rail_active or owner_player._spline_active:
		return false
	if owner_player._spring_align_timer > 0.0:
		return false
	if owner_player._spring_action_lock_timer > 0.0:
		return false
	if owner_player._spring_movement_lock_timer > 0.0:
		return false
	if owner_player._homing_active:
		return false
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return false
	if max_flight_time > 0.0 and _flight_time_remaining <= 0.0:
		return false
	if owner_player.has_method("get_current_action_id"):
		var current_action_id: StringName = owner_player.get_current_action_id()
		if current_action_id != &"" and current_action_id != &"fall" and current_action_id != &"jump":
			return false
	return true


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	if not activate(context):
		return false
	_active = true
	if max_flight_time > 0.0 and _flight_time_remaining <= 0.0:
		_flight_time_remaining = max(max_flight_time, 0.0)
		_flight_gauge_max = max(_flight_gauge_max, _flight_time_remaining)
	_used_this_air = true
	_landing_reset_timer = 0.0
	_exhausted = false
	_damping_weight = 0.0
	_damping_input_was_held = false
	_clear_owner_jump_hang_state()
	_cancel_owner_airborne_torque()
	_apply_start_velocity()
	_sync_entry_speed_limits()
	if owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()
	_flight_blend_value = flight_blend_neutral_value
	_flight_time_scale_value = _get_flight_time_scale_target(0.0)
	_update_flight_animation_blend(0.0, flight_blend_neutral_value)
	_update_flight_animation_time_scale(0.0, 0.0)
	_play_flight_animation_command()
	_update_propeller_flight_loop()
	_update_propeller_flight_audio_mix(0.0, false)
	return true


func on_action_exit(_next_action: CharacterAction) -> void:
	_active = false
	_damping_weight = 0.0
	_damping_input_was_held = false
	_current_max_fall_speed = 0.0
	_current_ascend_max_speed = 0.0
	_propeller_flight_audio_activity = 0.0
	_stop_propeller_flight_loop()
	_set_flight_animation_time_scale(1.0)


func continuous_physics_update(delta: float) -> void:
	if owner_player == null:
		return
	if not owner_player.attached:
		return
	_reset_flight_timer_to_max()
	if _landing_reset_timer > 0.0:
		_landing_reset_timer = max(_landing_reset_timer - delta, 0.0)
		return
	_used_this_air = false


func physics_update_action(delta: float) -> void:
	if owner_player == null:
		return
	if not _active:
		return
	if exit_input_action != &"" and SettingsManager.is_gameplay_action_just_pressed(String(exit_input_action)):
		if process_ability_routes(
			exit_input_action,
			ActionTrigger.JUST_PRESSED,
			{"reason": &"propeller_flight_exit", "source_action": action_id}
		):
			return
		_exit_to_fall({"reason": &"propeller_flight_exit", "source_action": action_id})
		return
	if owner_player.attached:
		_reset_flight_timer_to_max()
		_stop_propeller_flight_loop()
		if owner_player.has_method("clear_active_action"):
			owner_player.clear_active_action()
		_landing_reset_timer = max(landing_reset_delay, 0.0)
		return
	_clear_owner_jump_hang_state()
	var flight_input_axis: float = _get_flight_input_axis()
	var climb_active: bool = flight_input_axis > 0.0
	var dive_active: bool = flight_input_axis < 0.0
	_update_flight_timer(delta, climb_active, dive_active)
	_update_propeller_flight_loop()
	_update_propeller_flight_audio_mix(delta, climb_active or dive_active)
	_apply_flight_physics(owner_player.get_movement_delta(delta), climb_active, dive_active)
	_update_flight_animation_blend(delta, _get_flight_blend_target(flight_input_axis))
	_update_flight_animation_time_scale(delta, flight_input_axis)


func is_flight_action() -> bool:
	return true


func overrides_air_acceleration() -> bool:
	return _active


func get_air_acceleration_override(lateral_speed: float) -> float:
	return _get_flight_accel(lateral_speed)


func is_exhausted() -> bool:
	return _active and _exhausted


func has_flight_gauge() -> bool:
	return enabled and max_flight_time > 0.0


func has_ability_meter() -> bool:
	return has_flight_gauge()


func get_ability_meter_name() -> String:
	return ability_meter_name


func get_ability_meter_current() -> float:
	return get_flight_gauge_current()


func get_ability_meter_max() -> float:
	return get_flight_gauge_max()


func get_flight_gauge_current() -> float:
	return max(_flight_time_remaining, 0.0)


func get_flight_gauge_max() -> float:
	if max_flight_time <= 0.0:
		return 0.0
	var base_max: float = max(max_flight_time, 0.0)
	var display_max: float = max(_flight_gauge_max, base_max)
	return max(display_max, _flight_time_remaining)


func get_flight_gauge_fraction() -> float:
	var gauge_max: float = get_flight_gauge_max()
	if gauge_max <= 0.0:
		return 0.0
	return clamp(get_flight_gauge_current() / gauge_max, 0.0, 1.0)


func reset_flight_eligibility() -> void:
	_used_this_air = false
	_landing_reset_timer = 0.0
	if max_flight_time <= 0.0:
		_flight_time_remaining = 0.0
		_flight_gauge_max = 0.0
		_exhausted = false
		return
	var max_time: float = max(max_flight_time, 0.0)
	if _flight_time_remaining < max_time:
		_flight_time_remaining = max_time
	_flight_gauge_max = max(max_time, _flight_time_remaining)
	_exhausted = _flight_time_remaining <= 0.0


func reset_flight_timer_to_max() -> void:
	_reset_flight_timer_to_max()


func add_flight_time(amount: float) -> void:
	if max_flight_time <= 0.0:
		_exhausted = false
		return
	if amount <= 0.0:
		return
	_flight_time_remaining = max(_flight_time_remaining, 0.0) + amount
	_flight_gauge_max = max(_flight_gauge_max, _flight_time_remaining)
	if _flight_time_remaining > 0.0:
		_exhausted = false
		_used_this_air = false
		if _active:
			_update_propeller_flight_loop()


func add_ability_meter(amount: float) -> bool:
	if max_flight_time <= 0.0 or amount <= 0.0:
		return false
	add_flight_time(amount)
	return true


func _reset_flight_timer_to_max() -> void:
	if max_flight_time <= 0.0:
		_flight_time_remaining = 0.0
		_flight_gauge_max = 0.0
	else:
		_flight_time_remaining = max(max_flight_time, 0.0)
		_flight_gauge_max = _flight_time_remaining
	_exhausted = false
	if _active:
		_update_propeller_flight_loop()


func _update_flight_timer(delta: float, climb_active: bool, dive_active: bool) -> void:
	if max_flight_time <= 0.0 or _exhausted:
		return
	var drain_multiplier: float = 1.0
	if dive_active:
		drain_multiplier = max(dive_flight_drain_multiplier, 0.0)
	elif climb_active:
		drain_multiplier = max(ascend_flight_drain_multiplier, 0.0)
	_flight_time_remaining = max(_flight_time_remaining - delta * drain_multiplier, 0.0)
	if _flight_time_remaining <= 0.0:
		_exhausted = true
		_play_exhausted_flight_voice()
		_update_propeller_flight_loop()


func _apply_start_velocity() -> void:
	if start_min_vertical_speed <= 0.0:
		return
	var velocity: Vector3 = owner_player.velocity
	var vertical: float = get_gravity_vertical_component(velocity)
	if vertical < start_min_vertical_speed:
		var lateral: Vector3 = get_gravity_planar_component(velocity)
		owner_player.velocity = compose_gravity_vector(lateral, max(start_min_vertical_speed, 0.0))


func _play_exhausted_flight_voice() -> void:
	if owner_player and owner_player.has_method("play_voice_event"):
		owner_player.call("play_voice_event", &"exhausted_flight")


func _update_propeller_flight_loop() -> void:
	var audio_player: AudioStreamPlayer3D = _get_propeller_flight_audio_player()
	if audio_player == null:
		_current_loop_stream = null
		return
	var next_stream: AudioStream = _get_propeller_flight_loop_stream()
	if next_stream == null:
		if audio_player.playing:
			audio_player.stop()
		_current_loop_stream = null
		return
	_set_stream_loop_enabled(next_stream)
	if _current_loop_stream != next_stream or audio_player.stream != next_stream:
		audio_player.stop()
		audio_player.stream = next_stream
		_current_loop_stream = next_stream
	if not audio_player.playing:
		audio_player.play()
	_apply_propeller_flight_audio_mix(audio_player)


func _stop_propeller_flight_loop() -> void:
	var audio_player: AudioStreamPlayer3D = _get_propeller_flight_audio_player()
	if audio_player != null and audio_player.playing:
		audio_player.stop()
	_current_loop_stream = null


func _update_propeller_flight_audio_mix(delta: float, input_active: bool) -> void:
	var target_activity: float = 0.0
	if input_active:
		target_activity = 1.0
	var lerp_speed: float = max(propeller_flight_audio_lerp_speed, 0.0)
	if delta <= 0.0 or lerp_speed <= 0.0:
		_propeller_flight_audio_activity = target_activity
	else:
		_propeller_flight_audio_activity = move_toward(
			_propeller_flight_audio_activity,
			target_activity,
			lerp_speed * delta
		)
	var audio_player: AudioStreamPlayer3D = _get_propeller_flight_audio_player()
	if audio_player != null:
		_apply_propeller_flight_audio_mix(audio_player)


func _apply_propeller_flight_audio_mix(audio_player: AudioStreamPlayer3D) -> void:
	if audio_player == null:
		return
	var activity: float = clamp(_propeller_flight_audio_activity, 0.0, 1.0)
	audio_player.volume_db = lerp(propeller_flight_volume_min_db, propeller_flight_volume_max_db, activity)
	audio_player.pitch_scale = lerp(
		max(propeller_flight_pitch_min, 0.01),
		max(propeller_flight_pitch_max, 0.01),
		activity
	)


func _get_propeller_flight_loop_stream() -> AudioStream:
	if _exhausted and propeller_flight_exhausted_loop_sound != null:
		return propeller_flight_exhausted_loop_sound
	return propeller_flight_loop_sound


func _get_propeller_flight_audio_player() -> AudioStreamPlayer3D:
	if _propeller_flight_audio_player != null and is_instance_valid(_propeller_flight_audio_player):
		return _propeller_flight_audio_player
	var node: Node = null
	if propeller_flight_audio_node != NodePath() and has_node(propeller_flight_audio_node):
		node = get_node(propeller_flight_audio_node)
	elif propeller_flight_audio_node != NodePath() and owner_player != null and owner_player.has_node(propeller_flight_audio_node):
		node = owner_player.get_node(propeller_flight_audio_node)
	if node is AudioStreamPlayer3D:
		_propeller_flight_audio_player = node
		return _propeller_flight_audio_player
	if owner_player != null:
		node = _find_child_by_name(owner_player, &"SFX_PropellerFlight")
		if node is AudioStreamPlayer3D:
			_propeller_flight_audio_player = node
			return _propeller_flight_audio_player
	return null


func _find_child_by_name(root: Node, target_name: StringName) -> Node:
	if root == null:
		return null
	for child in root.get_children():
		if child.name == target_name:
			return child
		var nested: Node = _find_child_by_name(child, target_name)
		if nested != null:
			return nested
	return null


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


func _clear_owner_jump_hang_state() -> void:
	if owner_player == null:
		return
	owner_player._is_jumping = false
	owner_player._jump_variable = false
	owner_player._jump_hang_allowed = false
	owner_player._jump_time = 0.0


func _cancel_owner_airborne_torque() -> void:
	if owner_player == null:
		return
	if not owner_player.has_method("cancel_airborne_torque_for_action"):
		return
	var up: Vector3 = _get_flight_up()
	owner_player.call("cancel_airborne_torque_for_action", up)


func _exit_to_fall(context: Dictionary = {}) -> bool:
	if exit_action != NodePath():
		var routed_action: CharacterAction = _get_exit_action()
		if routed_action != null and routed_action.action_id == &"fall":
			return routed_action.activate(context)
		if routed_action != null and routed_action.execute(context):
			return true
	if owner_player != null and owner_player.has_method("activate_neutral_air_action"):
		return bool(owner_player.activate_neutral_air_action(context))
	return false


func _get_exit_action() -> CharacterAction:
	if owner_player == null:
		return null
	if exit_action == NodePath():
		return null
	if not has_node(exit_action):
		return null
	var target_node: Node = get_node(exit_action)
	if not (target_node is CharacterAction):
		return null
	return target_node


func _get_flight_input_axis() -> float:
	var climb_held: bool = false
	var dive_held: bool = false
	if input_action == &"":
		climb_held = false
	else:
		climb_held = SettingsManager.is_gameplay_action_pressed(String(input_action))
	if dive_input_action == &"":
		dive_held = false
	else:
		dive_held = SettingsManager.is_gameplay_action_pressed(String(dive_input_action))
	if climb_held and dive_held:
		return 0.0
	if dive_held:
		return -1.0
	if climb_held and not _exhausted:
		return 1.0
	return 0.0


func _get_flight_blend_target(flight_input_axis: float) -> float:
	if flight_input_axis > 0.0:
		return flight_blend_ascend_value
	if flight_input_axis < 0.0:
		return flight_blend_dive_value
	return flight_blend_neutral_value


func _update_flight_animation_blend(delta: float, target_value: float) -> void:
	if owner_player == null:
		return
	if flight_blend_parameter.is_empty():
		return
	var lerp_speed: float = max(flight_blend_lerp_speed, 0.0)
	if delta <= 0.0 or lerp_speed <= 0.0:
		_flight_blend_value = target_value
	else:
		var blend_weight: float = clamp(lerp_speed * delta, 0.0, 1.0)
		_flight_blend_value = lerp(_flight_blend_value, target_value, blend_weight)
	if owner_player.has_method("_safe_set_anim_param"):
		owner_player.call("_safe_set_anim_param", flight_blend_parameter, _flight_blend_value)


func _update_flight_animation_time_scale(delta: float, flight_input_axis: float) -> void:
	_set_flight_animation_time_scale(_get_flight_time_scale_target(flight_input_axis), delta)


func _get_flight_time_scale_target(flight_input_axis: float) -> float:
	if flight_input_axis > 0.0:
		return max(flight_time_scale_ascend, 0.0)
	if flight_input_axis < 0.0:
		return max(flight_time_scale_dive, 0.0)
	return max(flight_time_scale_neutral, 0.0)


func _set_flight_animation_time_scale(target_value: float, delta: float = 0.0) -> void:
	if owner_player == null:
		return
	if flight_time_scale_parameter.is_empty():
		return
	var lerp_speed: float = max(flight_time_scale_lerp_speed, 0.0)
	if delta <= 0.0 or lerp_speed <= 0.0:
		_flight_time_scale_value = target_value
	else:
		var blend_weight: float = clamp(lerp_speed * delta, 0.0, 1.0)
		_flight_time_scale_value = lerp(_flight_time_scale_value, target_value, blend_weight)
	if owner_player.has_method("_safe_set_anim_param"):
		owner_player.call("_safe_set_anim_param", flight_time_scale_parameter, _flight_time_scale_value)


func _play_flight_animation_command() -> void:
	if owner_player == null:
		return
	if flight_animation_command != &"" and owner_player.has_method("_trigger_anim_command"):
		owner_player.call("_trigger_anim_command", flight_animation_command)
		return
	if owner_player.has_method("play_action_command_if_exists"):
		owner_player.play_action_command_if_exists(action_id)


func _apply_flight_physics(delta: float, climb_active: bool, dive_held: bool) -> void:
	var velocity: Vector3 = owner_player.velocity
	var vertical: float = get_gravity_vertical_component(velocity)
	var lateral: Vector3 = get_gravity_planar_component(velocity)
	var damping_input_held: bool = climb_active or dive_held
	var gravity_scale: float = float_gravity_scale
	var max_ascend_speed: float = 0.0

	if dive_held:
		gravity_scale = dive_gravity_scale
	elif climb_active:
		vertical += max(ascend_accel, 0.0) * delta
		max_ascend_speed = _get_current_ascend_max_speed(lateral.length(), delta)
		if max_ascend_speed > 0.0:
			vertical = min(vertical, max_ascend_speed)

	var gravity_strength: float = max(owner_player.get_effective_gravity_strength(), 0.0)
	vertical += gravity_strength * (1.0 - max(gravity_scale, 0.0)) * delta
	if climb_active and max_ascend_speed > 0.0:
		vertical = min(vertical, max_ascend_speed)

	if dive_held:
		vertical -= max(dive_accel, 0.0) * delta
	var max_fall_speed: float = _get_current_max_fall_speed(dive_held, delta)
	if max_fall_speed > 0.0:
		vertical = max(vertical, -max_fall_speed)

	if damping_input_held:
		lateral = _apply_lateral_damping(lateral, delta)
	else:
		lateral = _release_lateral_damping(lateral, delta)
	lateral = _apply_flight_top_speed(lateral, delta)
	_damping_input_was_held = damping_input_held

	owner_player.velocity = compose_gravity_vector(lateral, vertical)


func _get_flight_accel(lateral_speed: float) -> float:
	if flight_accel_curve != null:
		var sample_speed: float = lateral_speed
		if flight_accel_curve_speed > 0.0:
			sample_speed = clamp(lateral_speed / flight_accel_curve_speed, 0.0, 1.0)
		return max(PlayerMath.sample_curve_by_speed(flight_accel_curve, sample_speed, flight_accel), 0.0)
	return max(flight_accel, 0.0)


func _sync_entry_speed_limits() -> void:
	if owner_player == null:
		_current_max_fall_speed = max(float_max_fall_speed, 0.0)
		_current_ascend_max_speed = max(ascend_max_speed, 0.0)
		return
	var velocity: Vector3 = owner_player.velocity
	var vertical: float = get_gravity_vertical_component(velocity)
	var lateral: Vector3 = get_gravity_planar_component(velocity)
	var target_ascend_speed: float = _get_ascend_max_speed(lateral.length())
	var target_fall_speed: float = _get_target_float_fall_speed()
	_current_ascend_max_speed = max(target_ascend_speed, max(vertical, 0.0))
	_current_max_fall_speed = max(target_fall_speed, max(-vertical, 0.0))


func _get_current_ascend_max_speed(lateral_speed: float, delta: float) -> float:
	var target_speed: float = _get_ascend_max_speed(lateral_speed)
	if target_speed <= 0.0:
		_current_ascend_max_speed = 0.0
		return 0.0
	if _current_ascend_max_speed <= 0.0 or _current_ascend_max_speed < target_speed:
		_current_ascend_max_speed = target_speed
		return _current_ascend_max_speed
	var lerp_speed: float = max(ascend_max_speed_lerp_speed, 0.0)
	if delta <= 0.0 or lerp_speed <= 0.0:
		_current_ascend_max_speed = target_speed
	else:
		var blend_weight: float = clamp(lerp_speed * delta, 0.0, 1.0)
		_current_ascend_max_speed = lerp(_current_ascend_max_speed, target_speed, blend_weight)
	return _current_ascend_max_speed


func _get_current_max_fall_speed(dive_held: bool, delta: float) -> float:
	if dive_held:
		var dive_target_speed: float = max(dive_max_fall_speed, 0.0)
		if dive_target_speed <= 0.0:
			_current_max_fall_speed = 0.0
			return 0.0
		if _current_max_fall_speed < dive_target_speed:
			_current_max_fall_speed = dive_target_speed
		return _lerp_current_fall_speed_limit(dive_target_speed, delta)
	var target_speed: float = _get_target_float_fall_speed()
	if target_speed <= 0.0:
		_current_max_fall_speed = 0.0
		return 0.0
	if _current_max_fall_speed < target_speed:
		_current_max_fall_speed = target_speed
	return _lerp_current_fall_speed_limit(target_speed, delta)


func _get_target_float_fall_speed() -> float:
	var target_speed: float = max(float_max_fall_speed, 0.0)
	if _exhausted and exhausted_float_max_fall_speed > 0.0:
		target_speed = max(exhausted_float_max_fall_speed, 0.0)
	return target_speed


func _lerp_current_fall_speed_limit(target_speed: float, delta: float) -> float:
	var lerp_speed: float = max(float_max_fall_speed_lerp_speed, 0.0)
	if _current_max_fall_speed <= 0.0 or delta <= 0.0 or lerp_speed <= 0.0:
		_current_max_fall_speed = target_speed
	else:
		var blend_weight: float = clamp(lerp_speed * delta, 0.0, 1.0)
		_current_max_fall_speed = lerp(_current_max_fall_speed, target_speed, blend_weight)
	return _current_max_fall_speed


func _apply_flight_top_speed(lateral: Vector3, delta: float) -> Vector3:
	if flight_top_speed <= 0.0 or flight_top_speed_slowdown <= 0.0:
		return lateral
	var speed: float = lateral.length()
	var top_speed: float = max(flight_top_speed, 0.0)
	if speed <= top_speed or speed <= 0.001:
		return lateral
	var new_speed: float = move_toward(speed, top_speed, max(flight_top_speed_slowdown, 0.0) * delta)
	return lateral.normalized() * new_speed


func _get_ascend_max_speed(lateral_speed: float) -> float:
	var speed_limit: float = max(ascend_max_speed, 0.0)
	if ascend_lateral_speed_penalty <= 0.0:
		return speed_limit
	return max(speed_limit - max(lateral_speed, 0.0) * ascend_lateral_speed_penalty, 0.0)


func _apply_lateral_damping(lateral: Vector3, delta: float) -> Vector3:
	_move_damping_weight(1.0, damping_enter_time, delta)
	var speed: float = lateral.length()
	var target_speed: float = max(damping_target_speed, 0.0)
	if speed <= target_speed or speed <= 0.001:
		return lateral

	var decel: float = max(damping_decel, 0.0) * _damping_weight * delta
	var new_speed: float = max(speed - decel, target_speed)
	return lateral.normalized() * new_speed


func _release_lateral_damping(lateral: Vector3, delta: float) -> Vector3:
	_move_damping_weight(0.0, damping_exit_time, delta)
	return lateral


func _move_damping_weight(target_weight: float, time_seconds: float, delta: float) -> void:
	if time_seconds <= 0.0:
		_damping_weight = target_weight
		return
	_damping_weight = move_toward(_damping_weight, target_weight, delta / time_seconds)


func _get_flight_up() -> Vector3:
	return get_owner_gravity_up()

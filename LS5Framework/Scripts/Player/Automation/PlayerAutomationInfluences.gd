extends RefCounted
class_name PlayerAutomationInfluences

const CHANNELS: Array[int] = [1, 2, 4, 8, 16]
const HARD_RELEASES: Array[StringName] = [&"death", &"teleport", &"disabled", &"removed", &"invalid_path", &"target_removed", &"target_unavailable", &"reset", &"capture_distance", &"breakaway", &"obstruction"]
## Session controller supplying player ownership and samples.
var _controller_ref: WeakRef
var _context: Dictionary = {}
var _exit_context: Dictionary = {}
var _weights: Dictionary = {}
var _from_weights: Dictionary = {}
var _entry_time: float = 0.0
var _entry_distance: float = 0.0
var _exit_time: float = 0.0
var _exit_distance: float = 0.0
var _last_progress: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _policy_engaged: bool = false
var _suspended: bool = false
var _blocked_slots: Dictionary = {}
var _max_owned: bool = false
var _last_correction: Vector3 = Vector3.ZERO
var _last_obstruction: bool = false
var ribbon: AutomationRibbonState
## Camera binding owned by this player session.
var camera_binding: AutomationCameraBinding
var raw_intent: Vector3 = Vector3.ZERO
var raw_input: Vector2 = Vector2.ZERO


func _init(controller: PlayerAutomationController) -> void:
	_controller_ref = weakref(controller)


func _controller() -> PlayerAutomationController:
	return _controller_ref.get_ref() as PlayerAutomationController


func _body() -> Node3D:
	var controller: PlayerAutomationController = _controller()
	return controller.get_body() if controller else null


func selection_changed(previous: AutomationSession, current: AutomationSession) -> void:
	_release_ribbon()
	_from_weights = _weights.duplicate()
	_exit_context = _context if previous and not current and not previous.release_reason in HARD_RELEASES else {}
	_context = _make_context(current) if current else {}
	_entry_time = 0.0
	_entry_distance = 0.0
	_exit_time = 0.0
	_exit_distance = 0.0
	_last_progress = current.unwrapped_progress if current else 0.0
	var body: Node3D = _body()
	if body:
		_last_position = body.global_position
	_policy_engaged = false
	_restore_maximum()
	_update_weights()
	_update_policy()


func _make_context(session: AutomationSession) -> Dictionary:
	var source: AutomationSplineCore = session.get_source() as AutomationSplineCore if session else null
	if not is_instance_valid(source):
		return {}
	return {"session": session, "sample": session.sample, "source": weakref(source),
		"steering": source.steering_traits.duplicate(), "position": source.position_traits.duplicate(),
		"speed": source.speed_traits.duplicate(), "surface": source.surface_traits.duplicate(),
		"input": source.input_traits.duplicate(), "transition": source.transition_traits.duplicate(),
		"influence": source.influence_traits.duplicate()}


func _exclusive() -> bool:
	var body: Node3D = _body()
	if not is_instance_valid(body):
		return true
	if not body.has_method("get_automation_controller"):
		return false
	return not bool(body.call("is_automation_tracking_available")) or bool(body.get("_local_pause_enabled")) \
		or bool(body.get("race_in_countdown")) or bool(body.get("_ui_input_blocked")) \
		or bool(body.get("_hurt_active")) or bool(body.get("_rail_active")) or bool(body.get("_spline_active")) \
		or bool(body.get("_vault_bar_active")) or bool(body.get("_homing_active")) or bool(body.get("_lightspeed_dash_active")) \
		or float(body.get("_spring_align_timer")) > 0.0 \
		or (bool(body.get("_automation_active")) and float(body.get("_automation_timer")) > 0.0) \
		or bool(body.call("_current_action_blocks_shared_movement_integration"))


func prepare(delta: float) -> void:
	_last_correction = Vector3.ZERO
	_last_obstruction = false
	if _context.is_empty() and _exit_context.is_empty() and _blocked_slots.is_empty():
		_weights.clear()
		_policy_engaged = false
		_restore_maximum()
		return
	_suspended = _exclusive()
	_update_held_slots()
	if _suspended:
		var selected: AutomationSession = _controller().selected
		if selected:
			_context = _make_context(selected)
		_update_weights()
		_prepare_ribbon(delta)
		_policy_engaged = false
		_restore_maximum()
		return
	var controller: PlayerAutomationController = _controller()
	if controller and controller.selected:
		_context = _make_context(controller.selected)
		_entry_distance += absf(controller.selected.unwrapped_progress - _last_progress)
		_last_progress = controller.selected.unwrapped_progress
		_entry_time += maxf(delta, 0.0)
	elif not _exit_context.is_empty():
		_exit_time += maxf(delta, 0.0)
		var body: Node3D = _body()
		var sample: AutomationSample = _exit_context.sample
		_exit_distance += absf((body.global_position - _last_position).dot(sample.tangent))
	_update_weights()
	_prepare_ribbon(delta)
	_update_policy()
	_capture_blocked_slots()
	var player: Node3D = _body()
	if player and player.has_method("get_automation_controller"):
		if _blocks(&"jump"):
			player.set("_jump_requested", false)
			player.set("_coyote_jump_requested", false)
		if _blocks(&"jump_dash"):
			player.set("_jump_dash_requested", false)
			player.call("_clear_homing_target_request_buffer")
	if get_maximum_speed() < 0.0:
		_restore_maximum()
	var body: Node3D = _body()
	if body:
		_last_position = body.global_position


func _update_policy() -> void:
	var policy: AutomationInputTrait = _trait("input", AutomationInputTrait.Mode.PERMISSIONS) as AutomationInputTrait
	var weight: float = _weight(16)
	if policy and weight > 0.0:
		_policy_engaged = weight > policy.release_influence if _policy_engaged else weight >= policy.engage_influence
	else:
		_policy_engaged = false


func _transition(context: Dictionary, phase: int, channel: int) -> AutomationTransitionTrait:
	for entry: AutomationTransitionTrait in context.get("transition", []):
		if entry and entry.enabled and entry.phase == phase and entry.channels & channel:
			return entry
	return null


func _fraction(component: AutomationTransitionTrait, elapsed: float, distance: float) -> float:
	if not component or component.mode == AutomationTransitionTrait.Mode.INSTANT:
		return 1.0
	var value: float = elapsed / maxf(component.duration, 0.000001) if component.mode == AutomationTransitionTrait.Mode.TIME else distance / maxf(component.distance, 0.000001)
	value = clampf(value, 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value) if component.smooth else value


func _update_weights() -> void:
	_weights.clear()
	var context: Dictionary = _active_context()
	if context.is_empty():
		return
	for channel: int in CHANNELS:
		var weight: float = 1.0
		var array_name: String = {1: "steering", 2: "position", 4: "speed", 8: "surface", 16: "input"}[channel]
		var assigned: bool = false
		for component: AutomationTrait in context.get(array_name, []):
			if component and component.applies(_attached()):
				assigned = true
				break
		if not assigned:
			_weights[channel] = 0.0
			continue
		if not _context.is_empty():
			var source: AutomationSplineCore = context.source.get_ref() as AutomationSplineCore
			if not is_instance_valid(source):
				_weights[channel] = 0.0
				continue
			for influence: AutomationInfluenceTrait in context.influence:
				if influence and influence.enabled and influence.channels & channel:
					weight = influence.get_weight(context.session, source)
					break
			var transition: AutomationTransitionTrait = _transition(context, AutomationTransitionTrait.Phase.ENTRY, channel)
			weight *= _fraction(transition, _entry_time, _entry_distance)
		else:
			var transition: AutomationTransitionTrait = _transition(context, AutomationTransitionTrait.Phase.EXIT, channel)
			weight = float(_from_weights.get(channel, 0.0)) * (1.0 - _fraction(transition, _exit_time, _exit_distance))
			if channel in [8, 16]:
				weight = 0.0
		_weights[channel] = clampf(weight, 0.0, 1.0)
	if _context.is_empty() and float(_weights.get(1, 0.0)) + float(_weights.get(2, 0.0)) + float(_weights.get(4, 0.0)) <= 0.0:
		_exit_context.clear()


func _active_context() -> Dictionary:
	return _context if not _context.is_empty() else _exit_context


func _weight(channel: int) -> float:
	var value: float = float(_weights.get(channel, 0.0))
	if channel == 16 and ribbon:
		value *= ribbon.adherence if _ribbon_allowed() else 0.0
	return 0.0 if value <= 0.0 or _suspended or _exclusive() else value


func _attached() -> bool:
	var body: Node3D = _body()
	return is_instance_valid(body) and bool(body.get("attached"))


func _trait(array_name: String, mode: int) -> AutomationTrait:
	for component: AutomationTrait in _active_context().get(array_name, []):
		if component and component.applies(_attached()) and int(component.get("mode")) == mode:
			return component
	return null


func _sample() -> AutomationSample:
	return ribbon.sample if ribbon and ribbon.sample else _active_context().get("sample") as AutomationSample


func is_guiding() -> bool:
	return (_weight(1) > 0.0 and not _active_context().get("steering", []).is_empty()) or (_weight(2) > 0.0 and not _active_context().get("position", []).is_empty())


func has_input_effects() -> bool:
	return _sample() != null and (_weight(1) > 0.0 or _weight(16) > 0.0)


func _up(fallback: Vector3) -> Vector3:
	var body: Node3D = _body()
	if not _attached():
		return body.call("get_gravity_up") as Vector3 if body and body.has_method("get_gravity_up") else fallback
	var surface: AutomationSurfaceTrait = _trait("surface", AutomationSurfaceTrait.Mode.TERRAIN_FRAME) as AutomationSurfaceTrait
	if surface and _weight(8) > 0.0:
		var target: Vector3 = fallback.normalized()
		if surface.up_mode == AutomationSurfaceTrait.UpMode.GRAVITY and body.has_method("get_gravity_up"):
			target = body.call("get_gravity_up") as Vector3
		if surface.up_mode == AutomationSurfaceTrait.UpMode.PATH and _sample():
			target = _sample().up
		var base: Vector3 = fallback.normalized()
		var axis: Vector3 = base.cross(target).normalized()
		if not axis:
			axis = (Vector3.RIGHT if absf(base.x) < 0.9 else Vector3.FORWARD).slide(base).normalized()
		return base.rotated(axis, base.angle_to(target) * _weight(8)).normalized()
	return fallback.normalized()


func capture_input(input: Vector2, intent: Vector3) -> void:
	raw_input = input
	raw_intent = intent
	var controller: PlayerAutomationController = _controller()
	if not controller or _exclusive() or _blocks(&"movement"):
		return
	controller.routes.capture_input(input.x)
	intent = _mapped_intent()
	var sample: AutomationSample = _sample()
	if controller and controller.selected and sample:
		var source: AutomationSplineCore = controller.selected.get_source() as AutomationSplineCore
		if source and absf(controller.selected.signed_speed) <= source.direction_speed_deadband and absf(intent.dot(sample.tangent)) > source.direction_input_deadband:
			controller.selected.direction = 1 if intent.dot(sample.tangent) > 0.0 else -1
	var policy: AutomationInputTrait = _trait("input", AutomationInputTrait.Mode.PERMISSIONS) as AutomationInputTrait
	if policy and _policy_engaged and policy.lateral_breakaway and sample and intent.slide(sample.tangent).length() >= policy.breakaway_input:
		controller.release_source(controller.selected.get_source(), &"breakaway")


func adjust_input(direction: Vector3, up: Vector3) -> Vector3:
	var sample: AutomationSample = _sample()
	if not sample or _exclusive():
		return direction
	var tangent: Vector3 = sample.tangent if ribbon else sample.tangent.slide(_up(up)).normalized()
	if _blocks(&"movement"):
		return _braking_intent(tangent)
	if not tangent:
		return direction
	var context: Dictionary = _active_context()
	var travel: Vector3 = tangent * float(context.session.direction)
	var mapped: Vector3 = direction
	for mapping: AutomationInputTrait in context.get("input", []):
		if mapping and mapping.applies(_attached()) and mapping.mode != AutomationInputTrait.Mode.PERMISSIONS and _weight(16) > 0.0:
			var axis: float = raw_input.x if mapping.mode == AutomationInputTrait.Mode.PATH_HORIZONTAL else raw_input.y
			if mapping.reverse_axis:
				axis = -axis
			mapped = (direction * raw_input.length()).lerp(tangent * axis, _weight(16)) if absf(axis) > mapping.input_deadzone else direction * raw_input.length() * (1.0 - _weight(16))
			break
	var steering: AutomationSteeringTrait = _trait("steering", AutomationSteeringTrait.Mode.INPUT_HEADING) as AutomationSteeringTrait
	if steering and steering.canonical_direction:
		travel = tangent
	if steering and mapped and not (steering.allow_pullback and mapped.dot(travel) < -0.1):
		var strength: float = mapped.length()
		mapped = mapped.lerp(travel * strength, clampf(steering.strength * _weight(1), 0.0, 1.0)).normalized() * strength
	return mapped


func _mapped_intent() -> Vector3:
	var sample: AutomationSample = _sample()
	if sample and _blocks(&"movement"):
		return _braking_intent(sample.tangent)
	if sample and _weight(16) > 0.0:
		for component: AutomationInputTrait in _active_context().get("input", []):
			if component and component.applies(_attached()) and component.mode != AutomationInputTrait.Mode.PERMISSIONS:
				var axis: float = raw_input.x if component.mode == AutomationInputTrait.Mode.PATH_HORIZONTAL else raw_input.y
				if absf(axis) <= component.input_deadzone:
					axis = 0.0
				return raw_intent.lerp(sample.tangent * axis * (-1.0 if component.reverse_axis else 1.0), _weight(16))
	return raw_intent


func _braking_intent(tangent: Vector3) -> Vector3:
	if _blocks(&"brake"):
		return Vector3.ZERO
	var session: AutomationSession = _active_context().session
	var travel: Vector3 = tangent * float(session.direction)
	return -travel * maxf(-raw_intent.dot(travel), 0.0)


func has_automatic_drive() -> bool:
	var component: AutomationSpeedTrait = _drive_trait()
	if not component or component.mode != AutomationSpeedTrait.Mode.PROPULSION or component.acceleration <= 0.0 or _speed_target(component) <= 0.0 or _weight(4) <= 0.0:
		return false
	var body: Node3D = _body()
	if bool(body.get("rolling")) and not component.affect_rolling:
		return false
	var sample: AutomationSample = _sample()
	var context: Dictionary = _active_context()
	return not _drive_braking_allowed(component) or _mapped_intent().dot(sample.tangent * (1.0 if component.canonical_direction else float(context.session.direction))) >= -0.1


func apply_velocity(velocity: Vector3, up: Vector3, delta: float) -> Vector3:
	if ribbon and _ribbon_allowed():
		velocity = ribbon.constrain_velocity(velocity, delta)
	var sample: AutomationSample = _sample()
	if not sample or _exclusive():
		return velocity
	up = _up(up).normalized()
	var tangent: Vector3 = sample.tangent.slide(up).normalized()
	if not tangent:
		return velocity
	var body: Node3D = _body()
	var context: Dictionary = _active_context()
	var travel: Vector3 = tangent * float(context.session.direction)
	var lateral: Vector3 = velocity.slide(up)
	var steering: AutomationSteeringTrait = _trait("steering", AutomationSteeringTrait.Mode.VELOCITY_ALIGNMENT) as AutomationSteeringTrait
	if steering and steering.canonical_direction:
		travel = tangent
	if steering and _weight(1) > 0.0 and lateral and not (steering.allow_pullback and _mapped_intent().dot(travel) < -0.1):
		var direction: Vector3 = lateral.normalized()
		var angle: float = acos(clampf(direction.dot(travel), -1.0, 1.0))
		var axis: Vector3 = direction.cross(travel).normalized()
		if not axis:
			axis = up
		lateral = direction.rotated(axis, minf(angle, deg_to_rad(steering.turn_rate) * delta * _weight(1))) * lateral.length()
	var position: AutomationPositionTrait = _position_trait()
	if position and not position is AutomationRibbonTrait and _weight(2) > 0.0:
		var target_position: Vector3 = sample.position
		if position is AutomationLaneTrait:
			target_position += sample.normal * AutomationRouteRuntime.lane_offset(context.session, position as AutomationLaneTrait)
		var error: Vector3 = (target_position - body.global_position).slide(tangent).slide(up)
		if position.mode == AutomationPositionTrait.Mode.ATTRACTION:
			error = (sample.position - body.global_position).slide(up)
			var distance: float = error.length()
			var range_weight: float = clampf(1.0 - distance / position.attraction_radius, 0.0, 1.0) if position.attraction_radius > 0.0 else 1.0
			var along_speed: float = absf(velocity.dot(sample.tangent.normalized()))
			var attraction_speed: float = along_speed if position.attraction_use_along_speed else velocity.length()
			var multiplier_speed: float = along_speed if position.attraction_use_along_speed else lateral.length()
			var strength: float = maxf(position.attraction_acceleration + attraction_speed * position.attraction_per_speed, 0.0)
			strength *= 1.0 + multiplier_speed * position.attraction_speed_scale
			lateral += error.normalized() * minf(strength * range_weight, position.max_acceleration) * delta * _weight(2)
		elif error.length() > position.free_radius:
			var acceleration: Vector3 = error.normalized() * (error.length() - position.free_radius) * position.spring_strength - lateral.slide(tangent) * position.damping
			lateral += acceleration.limit_length(maxf(position.max_acceleration, 0.0)) * delta * _weight(2)
	var damping: AutomationSteeringTrait = _trait("steering", AutomationSteeringTrait.Mode.TANGENT_DAMPING) as AutomationSteeringTrait
	if damping:
		lateral -= lateral.slide(tangent) * clampf(damping.damping_strength * delta * _weight(1), 0.0, 1.0)
	var cap: AutomationSpeedTrait = _trait("speed", AutomationSpeedTrait.Mode.SOFT_CAP) as AutomationSpeedTrait
	for speed: AutomationSpeedTrait in [_drive_trait(), cap]:
		if not speed or _weight(4) <= 0.0 or (bool(body.get("rolling")) and not speed.affect_rolling):
			continue
		if speed.mode == AutomationSpeedTrait.Mode.SOFT_CAP and speed.player_top_speed:
			continue
		var target: float = _speed_target(speed)
		var along: float = lateral.dot(tangent)
		var step: float = maxf(speed.acceleration, 0.0) * delta * _weight(4)
		if speed.mode == AutomationSpeedTrait.Mode.SOFT_CAP:
			if absf(along) > target:
				lateral -= tangent * signf(along) * minf(absf(along) - maxf(target, 0.0), step)
		else:
			var intent: float = _mapped_intent().dot(tangent)
			var drive_sign: float = (1.0 if speed.canonical_direction else float(context.session.direction)) if speed.mode == AutomationSpeedTrait.Mode.PROPULSION else signf(intent)
			if speed.mode == AutomationSpeedTrait.Mode.ASSIST and absf(intent) <= 0.01:
				continue
			if speed.mode == AutomationSpeedTrait.Mode.ASSIST:
				step *= clampf(absf(intent), 0.0, 1.0)
			if speed.mode == AutomationSpeedTrait.Mode.PROPULSION and _drive_braking_allowed(speed) and intent * drive_sign < -0.1:
				continue
			var gain: float = minf(maxf(target - along * drive_sign, 0.0), step)
			lateral += tangent * drive_sign * gain
	return lateral + up * velocity.dot(up)


func _drive_trait() -> AutomationSpeedTrait:
	for component: AutomationSpeedTrait in _active_context().get("speed", []):
		if component and component.applies(_attached()) and component.mode in [AutomationSpeedTrait.Mode.ASSIST, AutomationSpeedTrait.Mode.PROPULSION]:
			return component
	return null


func _position_trait() -> AutomationPositionTrait:
	for component: AutomationPositionTrait in _active_context().get("position", []):
		if component and component.applies(_attached()):
			return component
	return null


func is_grounded() -> bool:
	return _attached()


func is_suspended() -> bool:
	return _exclusive()


func get_maximum_speed() -> float:
	if _context.is_empty() or _weight(4) <= 0.0:
		return -1.0
	var component: AutomationSpeedTrait = _trait("speed", AutomationSpeedTrait.Mode.MAX_SPEED_OVERRIDE) as AutomationSpeedTrait
	if not component:
		return -1.0
	_max_owned = true
	return lerpf(float(_body().get("max_speed")), maxf(_speed_target(component), 0.0), _weight(4))


func _restore_maximum() -> void:
	var body: Node3D = _body()
	if _max_owned and is_instance_valid(body) and not (bool(body.get("_automation_max_speed_override_enabled")) or float(body.get("_timed_max_speed_override_timer")) > 0.0):
		body.set("_functional_max_speed", body.get("max_speed"))
	_max_owned = false


func adhesion_active() -> bool:
	var body: Node3D = _body()
	return _attached() and _weight(8) > 0.0 and not bool(body.get("_jump_requested")) and _trait("surface", AutomationSurfaceTrait.Mode.ADHESION) != null


func _blocks(action: StringName) -> bool:
	var policy: AutomationInputTrait = _trait("input", AutomationInputTrait.Mode.PERMISSIONS) as AutomationInputTrait
	if not policy or not _policy_engaged or _weight(16) <= 0.0:
		return false
	if &"actions" in policy.blocked_actions or action in policy.blocked_actions:
		return true
	match action:
		&"movement": return policy.block_movement
		&"jump": return policy.block_jump
		&"roll", &"spindash": return policy.block_roll_spindash
		&"drift": return policy.block_drift
		&"brake": return (policy.block_movement or &"movement" in policy.blocked_actions) and not policy.allow_braking
		&"actions": return false
	return policy.block_abilities


func _slot(action: StringName) -> StringName:
	var body: Node3D = _body()
	if not body or not body.has_method("get_ability_input_slot"):
		return &""
	var fallback: StringName = {&"jump": &"ability_slot_01", &"spindash": &"ability_slot_02", &"roll": &"ability_slot_04", &"drift": &"ability_slot_05"}.get(action, &"")
	return StringName(body.call("get_ability_input_slot", action, fallback))


func _update_held_slots() -> void:
	for action: StringName in _blocked_slots.keys():
		var slot: StringName = _blocked_slots[action]
		if not SettingsManager.is_gameplay_action_pressed(String(slot)) and not SettingsManager.is_gameplay_action_just_released(String(slot)):
			_blocked_slots.erase(action)


func _capture_blocked_slots() -> void:
	for action: StringName in [&"jump", &"roll", &"spindash", &"drift"]:
		var slot: StringName = _slot(action)
		if slot and _blocks(action) and SettingsManager.is_gameplay_action_pressed(String(slot)):
			_blocked_slots[action] = slot
	var body: Node3D = _body()
	if body and body.has_method("get_automation_controller"):
		for action: Node in body.get("_actions"):
			if not is_instance_valid(action):
				continue
			var id: StringName = StringName(action.get("action_id"))
			var slot: StringName = _slot(id)
			if slot and _blocks(id) and SettingsManager.is_gameplay_action_pressed(String(slot)):
				_blocked_slots[id] = slot


func allows(action: StringName) -> bool:
	if _context.is_empty() and _exit_context.is_empty() and _blocked_slots.is_empty():
		return true
	if _exclusive():
		return true
	if _blocks(action):
		var slot: StringName = _slot(action)
		if slot and SettingsManager.is_gameplay_action_pressed(String(slot)):
			_blocked_slots[action] = slot
		return false
	return not _blocked_slots.has(action)


func jump_requested() -> void:
	var policy: AutomationInputTrait = _trait("input", AutomationInputTrait.Mode.PERMISSIONS) as AutomationInputTrait
	var controller: PlayerAutomationController = _controller()
	if policy and _policy_engaged and policy.release_on_jump and controller and controller.selected and allows(&"jump"):
		controller.release_source(controller.selected.get_source(), &"breakaway")


func constrain_position(delta: float, up: Vector3) -> void:
	if ribbon and _ribbon_allowed():
		var source: AutomationSplineCore = ribbon.source_ref.get_ref() as AutomationSplineCore
		var body: CharacterBody3D = _body() as CharacterBody3D
		if source and body and ribbon.config.post_slide_constraint_pass_enabled:
			var value: AutomationSample = source.sampler.closest(body.global_position, ribbon.sample.distance,
				maxf(source.tracking_window, body.global_position.distance_to(ribbon.sample.position) * source.travel_window_multiplier))
			ribbon.update(body, value, 0.0, float(_weights.get(2, 0.0)), false)
			var blocked: bool = ribbon.constrain_position(body, delta)
			_last_correction = ribbon.last_correction
			_last_obstruction = blocked
			if blocked and ribbon.config.obstruction == AutomationPositionTrait.Obstruction.RELEASE:
				_controller().release_source(source, &"obstruction")
				return
			body.velocity = ribbon.constrain_velocity(body.velocity, 0.0, true)
			_update_camera(0.0)
	var component: AutomationPositionTrait = _position_trait()
	var body: CharacterBody3D = _body() as CharacterBody3D
	var controller: PlayerAutomationController = _controller()
	if not component or component.mode != AutomationPositionTrait.Mode.CONFINEMENT or not body or _context.is_empty() or _weight(2) <= 0.0 or not controller.selected:
		return
	var source: AutomationSplineCore = controller.selected.get_source() as AutomationSplineCore
	var value: AutomationSample = source.sampler.closest(body.global_position, controller.selected.sample.distance,
		maxf(source.tracking_window, body.global_position.distance_to(controller.selected.sample.position) * 2.0))
	if not value.valid:
		return
	var tangent: Vector3 = value.tangent.slide(_up(up)).normalized()
	var error: Vector3 = (value.position - body.global_position).slide(tangent).slide(_up(up))
	if error.length() <= component.free_radius:
		return
	var correction: Vector3 = error.normalized() * (error.length() - component.free_radius)
	correction = correction.limit_length(maxf(component.correction_speed, 0.0) * maxf(delta, 0.0) * _weight(2))
	if not correction:
		return
	var collision: KinematicCollision3D = body.move_and_collide(correction, true)
	_last_correction = collision.get_travel() if collision else correction
	_last_obstruction = collision != null
	body.global_position += _last_correction
	if collision and component.obstruction == AutomationPositionTrait.Obstruction.RELEASE:
		controller.release_source(source, &"obstruction")


func _release_ribbon() -> void:
	ribbon = null
	if is_instance_valid(camera_binding):
		camera_binding.release()
		camera_binding.queue_free()
	camera_binding = null


func _ribbon_allowed() -> bool:
	var body: Node3D = _body()
	if not ribbon or not ribbon.config.applies(_attached()) or not body:
		return false
	if not body.has_method("get_automation_controller"):
		return true
	if not bool(body.call("is_automation_tracking_available")) or bool(body.get("_local_pause_enabled")) or bool(body.get("race_in_countdown")) or bool(body.get("_ui_input_blocked")) or bool(body.get("_hurt_active")) or bool(body.get("_rail_active")) or bool(body.get("_spline_active")) or bool(body.get("_vault_bar_active")) or (bool(body.get("_automation_active")) and float(body.get("_automation_timer")) > 0.0):
		return false
	var special: bool = bool(body.get("_homing_active")) or bool(body.get("_lightspeed_dash_active")) or float(body.get("_spring_align_timer")) > 0.0
	return ribbon.config.constrain_special_moves if special else not bool(body.call("_current_action_blocks_shared_movement_integration"))


func _prepare_ribbon(delta: float) -> void:
	var component: AutomationPositionTrait = _position_trait()
	var controller: PlayerAutomationController = _controller()
	if not component and ribbon and controller.selected and ribbon.config in controller.selected.get_source().position_traits:
		component = ribbon.config
	if not component is AutomationRibbonTrait or not controller.selected:
		_release_ribbon()
		return
	var source: AutomationSplineCore = controller.selected.get_source() as AutomationSplineCore
	if not ribbon or ribbon.config != component:
		_release_ribbon()
		ribbon = AutomationRibbonState.new(component, source)
	if not _ribbon_allowed():
		if is_instance_valid(camera_binding):
			camera_binding.release()
		return
	ribbon.update(_body(), controller.selected.sample, delta, float(_weights.get(2, 0.0)))
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var source: AutomationSplineCore = ribbon.source_ref.get_ref() as AutomationSplineCore if ribbon else null
	if not source or not ribbon.sample:
		return
	var component: AutomationCameraTrait = null
	for candidate: AutomationCameraTrait in source.camera_traits:
		if candidate and candidate.camera_enabled:
			component = candidate
			break
	if not component or ribbon.adherence <= 0.0:
		if is_instance_valid(camera_binding):
			camera_binding.release()
		return
	if not is_instance_valid(camera_binding):
		camera_binding = AutomationCameraBinding.new()
		source.add_child(camera_binding)
	camera_binding.config = component
	var authored: AutomationSample = source.sampler.smooth_sample(_controller().selected.sample, ribbon.config.tangent_lookahead)
	camera_binding.update(_body(), ribbon.sample, delta, authored.get_transform())


func disables_turning_slowdown() -> bool:
	return ribbon and _ribbon_allowed() and ribbon.config.disable_turning_slowdown and ribbon.adherence > 0.0


func get_diagnostics() -> Dictionary:
	var weights: Dictionary = {}
	for channel: int in CHANNELS:
		weights[channel] = _weight(channel)
	var blocked: PackedStringArray = []
	var actions: Array[StringName] = [&"movement", &"jump", &"roll", &"spindash", &"drift"]
	var policy: AutomationInputTrait = _trait("input", AutomationInputTrait.Mode.PERMISSIONS) as AutomationInputTrait
	if policy:
		for action: StringName in policy.blocked_actions:
			if not action in actions:
				actions.append(action)
	for action: StringName in actions:
		if not _exclusive() and (_blocks(action) or _blocked_slots.has(action)):
			blocked.append(String(action))
	return {"weights": weights, "blocked_actions": blocked, "correction": _last_correction.length(), "obstruction": _last_obstruction, "suspended": _exclusive()}


func _speed_target(component: AutomationSpeedTrait) -> float:
	if component.target_speed_curve:
		var context: Dictionary = _active_context()
		var source: AutomationSplineCore = context.source.get_ref() as AutomationSplineCore if context.has("source") else null
		var sample: AutomationSample = _sample()
		if source and sample:
			return maxf(component.target_speed_curve.sample_baked(clampf(sample.distance / maxf(source.sampler.length, 0.0001), 0.0, 1.0)), 0.0)
	return maxf(component.target_speed, 0.0)


func get_player_top_speed() -> float:
	var component: AutomationSpeedTrait = _trait("speed", AutomationSpeedTrait.Mode.SOFT_CAP) as AutomationSpeedTrait
	return _speed_target(component) if component and component.player_top_speed and _weight(4) > 0.0 else -1.0


func ignores_water_physics() -> bool:
	return _weight(8) > 0.0 and _trait("surface", AutomationSurfaceTrait.Mode.WATER_BYPASS) != null


func uses_native_integration() -> bool:
	var context: Dictionary = _active_context()
	var source: AutomationSplineCore = context.source.get_ref() as AutomationSplineCore if context.has("source") else null
	return source and source.integrate_before_speed_limits


func canonical_heading(up: Vector3) -> Vector3:
	var component: AutomationSteeringTrait = _trait("steering", AutomationSteeringTrait.Mode.INPUT_HEADING) as AutomationSteeringTrait
	var sample: AutomationSample = _sample()
	if uses_native_integration() and component and component.canonical_direction and component.strength >= 0.999 and sample and _weight(1) > 0.0:
		return sample.tangent.slide(_up(up)).normalized()
	return Vector3.ZERO


func _drive_braking_allowed(component: AutomationSpeedTrait) -> bool:
	return component.allow_braking and not _blocks(&"brake")

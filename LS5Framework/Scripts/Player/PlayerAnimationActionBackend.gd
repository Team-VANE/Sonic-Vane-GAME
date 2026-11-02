extends RefCounted
class_name PlayerAnimationActionBackend

signal presentation_finished(owner_token: int, reason: StringName)

const BASE: String = "parameters/StateMachine/Actions"
const GROUPS: Dictionary[StringName, StringName] = {&"RAIL": &"Rail", &"PARKOUR": &"Parkour", &"TRICKS": &"Tricks", &"SKYDIVE_MACHINE": &"Skydive", &"DRIFT_MACHINE": &"Drift"}
const FAMILIES: Array[StringName] = [&"Ground", &"Air", &"Rail", &"Parkour", &"Drift", &"Tricks", &"Skydive"]

## Player state used by action-family arbitration.
var _owner: Node
var _family: StringName = &"Ground"
var _target: StringName = &""
var _pending_target: StringName = &""
var _pending_owner: int = 0
var _owner_token: int = 0
var _fade_remaining: float = 0.0
## Additional playback multiplier while a victory intro or loop is waiting to exit.
var victory_playback_scale: float = 1.0
var _terminal: bool = false
var _skydive_phase: StringName = &""
var _bank: int = 0
var _bank_blend: float = 0.0
var _bank_remaining: float = 0.0
var _trick_variant: StringName = &""
var _pending_trick: StringName = &""
var _pending_trick_owner: int = 0
var _reaction: StringName = &""
var _awaiting_state: StringName = &""
var _returning_to_motion: bool = false


func _init(owner: Node) -> void:
	_owner = owner


func dispose() -> void:
	_owner = null


func is_enabled() -> bool:
	if not is_instance_valid(_owner) or not _owner.animation_profile or not _owner.animation_profile.hierarchical_actions or not _owner.anim_tree:
		return false
	var machine: AnimationNodeStateMachine = _owner._get_main_animation_state_machine()
	return machine and machine.has_node(&"Actions")


func reset() -> void:
	_target = &""
	_pending_target = &""
	_pending_owner = 0
	_owner_token = 0
	victory_playback_scale = 1.0
	_terminal = false
	_skydive_phase = &""
	_reaction = &""
	_pending_trick = &""
	_pending_trick_owner = 0
	_trick_variant = &""
	_bank_remaining = 0.0
	_bank_blend = 0.0
	_bank = 0
	_fade_remaining = 0.0
	_awaiting_state = &""
	_returning_to_motion = false
	_family = &"Ground"
	if is_enabled():
		_owner.anim_tree.set(BASE + "/Select/transition_request", _family)
		_owner.anim_tree.set(BASE + "/Tricks/Active/Banks/blend_amount", 0.0)


func resolve(command: StringName) -> StringName:
	if not is_enabled():
		return &""
	var target: StringName = _owner.animation_profile.presentation_commands.get(command, &"")
	if target == &"":
		return &""
	var parts: PackedStringArray = String(target).split("/", false, 1)
	if parts.size() != 2:
		return &""
	var family: StringName = StringName(parts[0])
	if family == &"Reaction":
		return target if _reaction_machine().has_node(StringName(parts[1])) else &""
	if family not in FAMILIES:
		return &""
	var machine: AnimationNodeStateMachine = _machine(family)
	if family == &"Tricks":
		var blend: AnimationNodeBlendTree = machine.get_node(&"Active")
		return target if blend.has_node(StringName("A_" + parts[1])) else &""
	return target if machine.has_node(StringName(parts[1])) else &""


func apply_command(command: StringName, restart: bool = false, owner_token: int = 0) -> bool:
	var target: StringName = resolve(command)
	if target == &"":
		return false
	if target == &"Air/Bounce" and _owner._bounce_state == _owner.BounceState.STOMP:
		target = &"Air/Stomp"
	if String(target).begins_with("Reaction/"):
		_set_reaction(StringName(String(target).get_slice("/", 1)), restart)
		return true
	if not allows_body_request():
		return false
	if (_owner.has_action_landing_animation_override() or _owner.get_animation_director().get_overlay_backend().landing_active()) and (String(target).begins_with("Tricks/") or String(target).begins_with("Skydive/")):
		return false
	_owner.get_animation_director().get_motion_backend().cancel_landing_request()
	_supersede_pending(owner_token)
	if String(target).begins_with("Tricks/"):
		var variant: StringName = StringName(String(target).get_slice("/", 1))
		if _returning_to_motion or _bank_remaining > 0.0 or (_family != &"Tricks" and _fade_remaining > 0.0 and _owner.anim_state.get_current_node() == &"Actions"):
			var previous: int = _pending_trick_owner
			_pending_trick = variant
			_pending_trick_owner = owner_token
			if previous != owner_token:
				_finish_owner(previous, &"superseded")
			return true
		_activate_trick(variant, owner_token)
		return true
	_request_target(target, restart, owner_token)
	return true


func allows_body_request() -> bool:
	return not _terminal and not _owner._is_dead and _owner.anim_state.get_current_node() != &"REACTIONS"


func start_rail_switch(side: float) -> void:
	if not is_enabled() or not allows_body_request():
		return
	resume_motion(&"rail_switch")
	_returning_to_motion = false
	_fade_remaining = 0.0
	var state: StringName = &"SWITCH_LEFT" if side < 0.0 else &"SWITCH_RIGHT"
	_request_target(StringName("Rail/" + String(state)), true, 0)
	_owner.anim_state.start(&"Actions", true)
	_owner.anim_tree.set(BASE + "/Select/transition_request", &"Rail")
	_owner.anim_tree.advance(0.0)
	_playback(&"Rail").start(state, true)
	_owner.anim_tree.advance(0.0)
	_owner._rail_switch_animation_started = true


func resume_motion(reason: StringName = &"completed") -> void:
	if not is_enabled() or _terminal:
		return
	var tokens: Array[int] = [_owner_token, _pending_owner, _pending_trick_owner]
	_owner_token = 0
	_pending_owner = 0
	_target = &""
	_pending_target = &""
	_pending_trick = &""
	_pending_trick_owner = 0
	_skydive_phase = &""
	_awaiting_state = &""
	_returning_to_motion = _returning_to_motion or _owner.anim_state.get_current_node() == &"Actions"
	if _owner.anim_state.get_current_node() != &"Motion":
		_owner.get_animation_director().get_motion_backend().prepare_resume()
	_owner.anim_state.travel(&"Motion")
	var finished: Dictionary[int, bool] = {}
	for token: int in tokens:
		if token and not finished.has(token):
			finished[token] = true
			_finish_owner(token, reason)


func cancel_owner(token: int) -> void:
	if not token:
		return
	if _pending_owner == token:
		_pending_target = &""
		_pending_owner = 0
	if _pending_trick_owner == token:
		_pending_trick = &""
		_pending_trick_owner = 0
	if _owner_token == token:
		resume_motion(&"cancelled")


func set_skydive_phase(phase: StringName) -> bool:
	if not is_enabled() or phase not in [&"Dive", &"Glide", &"Cancel", &"Exit"] or not allows_body_request():
		return false
	if _family != &"Skydive" or _owner.anim_state.get_current_node() != &"Actions":
		if phase not in [&"Dive", &"Glide"]:
			return false
		_supersede_pending(0)
		_request_target(&"Skydive/Skydive_Enter", false, 0)
	var previous_phase: StringName = _skydive_phase
	_skydive_phase = phase
	var playback: AnimationNodeStateMachinePlayback = group_playback(&"SKYDIVE_MACHINE")
	if phase == &"Dive" and (previous_phase in [&"Cancel", &"Exit"] or playback.get_current_node() in [&"Skydive_Cancel", &"Skydive_Exit"]):
		playback.travel(&"Skydive_Enter")
	_write_skydive_conditions()
	return true


func skydive_finished() -> bool:
	if _skydive_phase == &"":
		return true
	var playback: AnimationNodeStateMachinePlayback = group_playback(&"SKYDIVE_MACHINE")
	return playback and (playback.get_current_node() == &"End" or (playback.get_current_node() in [&"Skydive_Cancel", &"Skydive_Exit"] and _finished(playback)))


func get_skydive_phase() -> StringName:
	return _skydive_phase


func current_state() -> StringName:
	if not is_enabled():
		return &""
	var root_state: StringName = _owner.anim_state.get_current_node()
	if root_state == &"Motion":
		return _owner.get_animation_director().get_motion_backend().current_state()
	if root_state != &"Actions":
		return root_state
	var family: StringName = StringName(_owner.anim_tree.get(BASE + "/Select/current_state"))
	if family == &"":
		family = _family
	var playback: AnimationNodeStateMachinePlayback = _playback(family)
	var target: StringName = StringName("%s/%s" % [family, playback.get_current_node()])
	if family == &"Tricks":
		return &"TRICKS"
	return _owner.animation_profile.presentation_state_names.get(target, _group_alias(family))


func synchronize_remote_state() -> void:
	var family: StringName = StringName(_owner.anim_tree.get(BASE + "/Select/current_state"))
	if family in FAMILIES:
		_family = family
	if _family == &"Tricks":
		_bank_blend = float(_owner.anim_tree.get(BASE + "/Tricks/Active/Banks/blend_amount"))
		_bank = 1 if _bank_blend >= 0.5 else 0
		_trick_variant = StringName(_owner.anim_tree.get(BASE + "/Tricks/Active/Select" + ("B" if _bank else "A") + "/current_state"))


func group_playback(group: StringName) -> AnimationNodeStateMachinePlayback:
	if group == &"REACTIONS":
		return _owner.anim_tree.get("parameters/StateMachine/REACTIONS/State/playback")
	var family: StringName = GROUPS.get(group, group)
	return _playback(family) if family in FAMILIES else null


func group_node(group: StringName) -> StringName:
	if group == &"TRICKS":
		var clip: AnimationNodeAnimation = _trick_clip()
		return clip.animation if clip else &""
	var playback: AnimationNodeStateMachinePlayback = group_playback(group)
	return playback.get_current_node() if playback else &""


func active_playback() -> AnimationNodeStateMachinePlayback:
	if _owner.anim_state.get_current_node() == &"REACTIONS":
		return group_playback(&"REACTIONS")
	if _owner.anim_state.get_current_node() == &"Actions":
		return _playback(_family)
	return _owner.anim_state


func active_node() -> AnimationNode:
	if _owner.anim_state.get_current_node() == &"REACTIONS":
		return _reaction_machine().get_node(group_node(&"REACTIONS"))
	if _owner.anim_state.get_current_node() != &"Actions":
		return _owner.get_animation_director().get_motion_backend().get_active_node()
	if _family == &"Tricks":
		return _trick_clip()
	var playback: AnimationNodeStateMachinePlayback = _playback(_family)
	var state: StringName = playback.get_current_node()
	return _machine(_family).get_node(state) if state not in [&"", &"Start", &"End"] else null


func is_command_current(command: StringName) -> bool:
	return resolve(command) != &"" and resolve(command) == _target


func set_clocks(movement_scale: float) -> void:
	if not is_enabled():
		return
	var scale: float = maxf(_owner.animation_profile.action_playback_scale, 0.0)
	if _owner._active_action and is_instance_valid(_owner._active_action):
		scale *= maxf(_owner._active_action.get_animation_speed_multiplier(), 0.0)
	for family: StringName in FAMILIES:
		var rate: float = movement_scale if family in [&"Rail", &"Drift"] or (family == &"Ground" and current_state() == &"SPINDASH") else scale
		if family == &"Ground":
			var state: StringName = _playback(family).get_current_node()
			if state in [&"VictoryIntro", &"VictoryLoop"]:
				rate = victory_playback_scale
			elif state == &"VictoryExit":
				rate = 1.0
		_owner.anim_tree.set(BASE + "/" + String(family) + "Clock/scale", maxf(rate, 0.0))
	_owner.anim_tree.set("parameters/StateMachine/REACTIONS/Clock/scale", maxf(_owner.animation_profile.reaction_playback_scale, 0.0))


func update(delta: float) -> void:
	if not is_enabled():
		return
	_owner.anim_tree.set("parameters/StateMachine/REACTIONS/Clock/scale", maxf(_owner.animation_profile.reaction_playback_scale, 0.0))
	_fade_remaining = maxf(_fade_remaining - delta, 0.0)
	var trick_rate: float = float(_owner.anim_tree.get(BASE + "/TricksClock/scale"))
	if _bank_remaining > 0.0:
		var fade: float = maxf(_owner.trick_anim_crossfade, 0.001)
		_bank_blend = move_toward(_bank_blend, float(_bank), delta * trick_rate / fade)
		_bank_remaining = maxf(_bank_remaining - delta * trick_rate, 0.0)
		_owner.anim_tree.set(BASE + "/Tricks/Active/Banks/blend_amount", _bank_blend)
	if not _returning_to_motion and _bank_remaining <= 0.0 and _pending_trick != &"" and (_family == &"Tricks" or _fade_remaining <= 0.0 or _owner.anim_state.get_current_node() != &"Actions"):
		var variant: StringName = _pending_trick
		var token: int = _pending_trick_owner
		_pending_trick = &""
		_pending_trick_owner = 0
		_activate_trick(variant, token)
	if not _returning_to_motion and _fade_remaining <= 0.0 and _pending_target != &"":
		var target: StringName = _pending_target
		var token: int = _pending_owner
		_pending_target = &""
		_pending_owner = 0
		_request_target(target, false, token)
	_write_conditions()
	if _owner.anim_state.get_current_node() == &"Actions" and (_owner._rail_active or _owner._rail_switch_active) and _family != &"Rail" and allows_body_request():
		apply_command(&"CMD_SPINDASHRAIL" if _owner._spindash_charging else &"CMD_RAIL")
	if _owner._is_dead and _owner.anim_state.get_current_node() != &"REACTIONS":
		return
	if _owner.anim_state.get_current_node() == &"Motion" and allows_body_request():
		if _pending_target != &"" or _pending_trick != &"":
			return
		if &"Actions" in _owner.anim_state.get_travel_path():
			return
		var command: StringName = &""
		if _owner._rail_active or _owner._rail_switch_active:
			command = &"CMD_SPINDASHRAIL" if _owner._spindash_charging else &"CMD_RAIL"
		elif _owner._spindash_charging:
			command = _owner._spindash_action.get_charge_animation_command() if _owner._spindash_action else &"CMD_SPINDASH"
		elif _owner.has_state(_owner.STATE_DRIFT):
			command = &"DRIFT_MACHINE"
		elif _owner._bounce_state == _owner.BounceState.STOMP:
			command = &"STOMP"
		elif _owner._bounce_state == _owner.BounceState.BOUNCE:
			command = &"CMD_BOUNCE"
		elif _owner._jump_dash_recent_timer > 0.0 and not _owner.has_state(_owner.STATE_JUMP_FALL_BLEND):
			command = &"JUMPDASH"
		if command != &"":
			apply_command(command)


func after_advance() -> void:
	if not is_enabled():
		return
	if _returning_to_motion and _owner.anim_state.get_current_node() == &"Motion" and _owner.anim_state.get_fading_from_node() != &"Actions":
		_returning_to_motion = false
	if _owner.anim_state.get_current_node() == &"REACTIONS":
		if not _terminal and not _owner._hurt_active and not _owner._is_dead:
			_reaction = &""
			_owner.get_animation_director().get_motion_backend().prepare_resume()
			_owner.anim_state.travel(&"Motion")
		return
	if _owner.anim_state.get_current_node() != &"Actions" or _pending_target != &"":
		return
	var playback: AnimationNodeStateMachinePlayback = _playback(_family)
	var state: StringName = playback.get_current_node()
	if StringName(_owner.anim_tree.get(BASE + "/Select/current_state")) != _family:
		return
	if _awaiting_state != &"":
		if state == _awaiting_state:
			_awaiting_state = &""
		return
	if _family == &"Rail" and state in [&"SWITCH_LEFT", &"SWITCH_RIGHT"]:
		_owner._rail_switch_animation_started = true
	var done: bool = false
	match _family:
		&"Tricks":
			done = _owner.attached or _owner.rolling or _trick_finished()
		&"Skydive":
			done = _owner.attached or _owner.rolling or skydive_finished()
		&"Rail":
			done = not _owner._rail_active and not _owner._rail_switch_active
		&"Drift":
			done = not _owner.has_state(_owner.STATE_DRIFT) or not _owner.attached
		&"Ground":
			if state in [&"VictoryIntro", &"VictoryLoop"]:
				done = false
			elif state == &"Spindash":
				done = not _owner._spindash_charging and not _owner.has_state(_owner.STATE_SPINDASH)
			elif state in [&"Land", &"LandHard", &"LandMoving"]:
				done = not _owner.attached or _owner.rolling or (_finished(playback) and not _owner.has_action_landing_animation_override())
				if state != &"LandMoving" and not _owner.has_action_landing_animation_override():
					done = done or _owner._move_input.length_squared() > 0.000001 or _owner._get_lateral_speed_for_anim() >= 0.5
			else:
				done = _finished(playback)
		&"Air":
			match state:
				&"DropDash": done = _owner.attached or (not _owner._spindash_charging and not _owner.has_state(_owner.STATE_SPINDASH))
				&"Dash": done = _owner.attached or (_owner._jump_dash_recent_timer <= 0.0 and not _owner._homing_active and (_owner._vertical_speed < -_owner.fall_vertical_speed_threshold or _owner.has_state(_owner.STATE_FALLING)))
				&"Bounce":
					if _owner._bounce_state == _owner.BounceState.STOMP:
						apply_command(&"STOMP")
						return
					done = _owner.attached or (_owner._bounce_state != _owner.BounceState.BOUNCE and _owner._vertical_speed <= 0.0)
				&"Stomp": done = _owner.attached or _owner._bounce_state != _owner.BounceState.STOMP
				&"Spring": done = true
				&"LightSpeed": done = not _owner.has_state(_owner.STATE_LIGHTSPEED_DASH)
				&"Uppercut": done = _owner.attached or _owner._current_action_id != &"uppercut_kick"
				_: done = _owner.attached or _owner.rolling or _finished(playback)
		&"Parkour":
			if state == &"LEDGE_GRAB":
				done = _owner.attached and _owner._current_action_id not in [&"ledge_hang", &"ledge_mantle"]
			else:
				done = not _owner.is_parkour_active() and _owner._current_action_id != &"ledge_mantle" and _finished(playback)
	if done:
		resume_motion()


func _request_target(target: StringName, restart: bool, token: int) -> void:
	var parts: PackedStringArray = String(target).split("/", false, 1)
	var family: StringName = StringName(parts[0])
	var state: StringName = StringName(parts[1])
	if not restart and target == _target and &"Actions" in _owner.anim_state.get_travel_path():
		return
	_owner.get_animation_director().get_overlay_backend().interrupt(&"action")
	if _returning_to_motion or (family != _family and _fade_remaining > 0.0 and _owner.anim_state.get_current_node() == &"Actions"):
		var previous: int = _pending_owner
		_pending_target = target
		_pending_owner = token
		if previous != token:
			_finish_owner(previous, &"superseded")
		return
	if _owner_token and _owner_token != token:
		var previous: int = _owner_token
		_owner_token = 0
		_finish_owner(previous, &"interrupted")
	_owner_token = token
	_target = target
	_awaiting_state = state
	var playback: AnimationNodeStateMachinePlayback = _playback(family)
	var same_family: bool = family == _family and _owner.anim_state.get_current_node() == &"Actions"
	if family != _family:
		var select: AnimationNodeTransition = _actions().get_node(&"Select")
		_fade_remaining = select.xfade_time
		_family = family
		_owner.anim_tree.set(BASE + "/Select/transition_request", family)
	elif not same_family:
		_owner.anim_tree.set(BASE + "/Select/transition_request", family)
	if not same_family or playback.get_current_node() in [&"", &"Start", &"End"]:
		playback.start(state, true)
	elif playback.get_current_node() != state:
		playback.travel(state)
	elif restart:
		playback.start(state, true)
	if family == &"Skydive" and state == &"Skydive_Enter":
		_skydive_phase = &"Dive"
		_write_skydive_conditions()
	if _owner.anim_state.get_current_node() != &"Actions":
		_owner.anim_state.travel(&"Actions")


func _activate_trick(variant: StringName, token: int) -> void:
	var active: bool = _owner.anim_state.get_current_node() == &"Actions" and _family == &"Tricks"
	if active:
		_bank = 1 - _bank
		_bank_remaining = maxf(_owner.trick_anim_crossfade, 0.001)
	else:
		_bank = 0
		_bank_blend = 0.0
		_bank_remaining = 0.0
	_request_target(StringName("Tricks/Active"), false, token)
	_trick_variant = variant
	_target = StringName("Tricks/" + String(variant))
	var bank: String = "B" if _bank else "A"
	_owner.anim_tree.set(BASE + "/Tricks/Active/Select" + bank + "/transition_request", variant)
	_owner.anim_tree.set(BASE + "/Tricks/Active/Seek" + bank + "/seek_request", 0.0)
	_owner.anim_tree.set(BASE + "/Tricks/Active/Banks/blend_amount", _bank_blend)


func _set_reaction(state: StringName, restart: bool) -> void:
	var death: bool = String(state).begins_with("CMD_DEAD")
	if _terminal and not death:
		return
	_owner.get_animation_director().get_motion_backend().cancel_landing_request()
	_returning_to_motion = false
	var cancelled: Array[int] = [_pending_owner, _pending_trick_owner]
	_pending_target = &""
	_pending_owner = 0
	_pending_trick = &""
	_pending_trick_owner = 0
	var previous: int = _owner_token
	_owner_token = 0
	_finish_owner(previous, &"reaction")
	_terminal = _terminal or death
	_target = StringName("Reaction/" + String(state))
	_skydive_phase = &""
	var playback: AnimationNodeStateMachinePlayback = group_playback(&"REACTIONS")
	if _owner.anim_state.get_current_node() == &"REACTIONS" and _reaction != &"":
		if playback.get_current_node() != state:
			playback.travel(state)
		elif restart:
			playback.start(state, true)
	else:
		playback.start(state, true)
	_reaction = state
	_owner.anim_state.travel(&"REACTIONS")
	_owner.get_animation_director().get_overlay_backend().interrupt(&"reaction")
	for token: int in cancelled:
		_finish_owner(token, &"reaction")


func _write_conditions() -> void:
	var tree: AnimationTree = _owner.anim_tree
	for pair: Array in [["SwitchLeft", _owner._rail_switch_active and _owner._rail_switch_animation_side < 0.0], ["SwitchRight", _owner._rail_switch_active and _owner._rail_switch_animation_side >= 0.0], ["NotCharging", not _owner._spindash_charging]]:
		tree.set(BASE + "/Rail/conditions/" + String(pair[0]), pair[1])
	var direction: float = float(_owner._get_drift_anim_direction())
	for pair: Array in [["Left", direction < 0.0], ["Right", direction > 0.0], ["Neutral", not _owner._is_drift_anim_active()]]:
		tree.set(BASE + "/Drift/conditions/" + String(pair[0]), pair[1])
	_write_skydive_conditions()


func _write_skydive_conditions() -> void:
	for phase: StringName in [&"Dive", &"Glide", &"Cancel", &"Exit"]:
		_owner.anim_tree.set(BASE + "/Skydive/conditions/" + String(phase), phase == _skydive_phase)


func _actions() -> AnimationNodeBlendTree:
	return _owner._get_main_animation_state_machine().get_node(&"Actions")


func _machine(family: StringName) -> AnimationNodeStateMachine:
	return _actions().get_node(family)


func _reaction_machine() -> AnimationNodeStateMachine:
	var reaction: AnimationNodeBlendTree = _owner._get_main_animation_state_machine().get_node(&"REACTIONS")
	return reaction.get_node(&"State")


func _playback(family: StringName) -> AnimationNodeStateMachinePlayback:
	return _owner.anim_tree.get(BASE + "/" + String(family) + "/playback")


func _finished(playback: AnimationNodeStateMachinePlayback) -> bool:
	return playback and playback.get_current_length() > 0.001 and playback.get_current_play_position() >= playback.get_current_length() - 0.001


func _trick_clip() -> AnimationNodeAnimation:
	if _trick_variant == &"":
		return null
	var blend: AnimationNodeBlendTree = _machine(&"Tricks").get_node(&"Active")
	return blend.get_node(StringName(("B_" if _bank else "A_") + String(_trick_variant)))


func _trick_finished() -> bool:
	var clip: AnimationNodeAnimation = _trick_clip()
	if not clip or _pending_trick != &"":
		return false
	var player: AnimationPlayer = _owner.anim_tree.get_node(_owner.anim_tree.anim_player)
	var animation: Animation = player.get_animation(clip.animation)
	var length: float = clip.timeline_length if clip.use_custom_timeline else animation.length
	var path: String = BASE + "/Tricks/Active/" + ("B_" if _bank else "A_") + String(_trick_variant) + "/current_position"
	return float(_owner.anim_tree.get(path)) >= length - 0.001


func _group_alias(family: StringName) -> StringName:
	for alias: StringName in GROUPS:
		if GROUPS[alias] == family:
			return alias
	return family


func _finish_owner(token: int, reason: StringName) -> void:
	if token:
		presentation_finished.emit(token, reason)


func _supersede_pending(next_owner: int) -> void:
	var tokens: Array[int] = [_pending_owner, _pending_trick_owner]
	_pending_target = &""
	_pending_owner = 0
	_pending_trick = &""
	_pending_trick_owner = 0
	for token: int in tokens:
		if token != next_owner:
			_finish_owner(token, &"superseded")

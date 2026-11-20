extends RefCounted
class_name PlayerAnimationLegacyAdapter

## Player state and playback references used by the existing command graph.
var _owner: Node


func _init(owner: Node) -> void:
	_owner = owner


func dispose() -> void:
	_owner = null


func has_command(command: StringName) -> bool:
	var director = _owner.get_animation_director()
	if director.get_action_backend().is_enabled():
		return director.get_motion_backend().has_command(command) or director.get_action_backend().resolve(command) != &"" or command in [&"CMD_LANDING_ROLL", &"Carry_Hold", &"Carry_Pickup", &"Carry_PutDown", &"Carry_Throw"]
	return _owner.get_animation_director().get_motion_backend().has_command(command) or not resolve_target(command, _owner._get_main_animation_state_machine()).is_empty()


func queue_command(cmd: StringName, send_net: bool = true, crossfade: float = -1.0, force: bool = false) -> bool:
	var allow: bool = true
	var presentation = _owner.get_animation_director().get_action_backend()
	if presentation.is_enabled() and not String(presentation.resolve(cmd)).begins_with("Reaction/") and not presentation.allows_body_request():
		return false
	if not force and cmd != &"CMD_SPRING" and _owner._pending_anim_command == &"CMD_SPRING":
		allow = false
	if not force and _owner.has_action_landing_animation_override():
		var command_target: Dictionary = resolve_target(cmd, _owner._get_main_animation_state_machine())
		var target_machine: StringName = command_target.get("machine", &"") as StringName
		if cmd == &"CMD_SKYDIVE" or target_machine == &"TRICKS" or target_machine == &"SKYDIVE_MACHINE":
			allow = false
	if not allow:
		return false
	_owner._pending_anim_command = cmd
	_owner._pending_anim_crossfade = crossfade
	if send_net and _owner._network_is_active() and _owner.network_replication_enabled and _owner.is_multiplayer_authority():
		_owner.rpc("_net_anim_command", cmd)
	return true


func play_action_if_exists(action_name: StringName, send_net: bool = true) -> bool:
	if action_name == &"":
		return false
	var cmd: StringName = StringName("CMD_%s" % String(action_name).to_upper())
	if _owner.get_animation_director().get_motion_backend().has_command(cmd):
		return queue_command(cmd, send_net)
	if _owner.anim_tree == null:
		return false
	var sm: AnimationNodeStateMachine = null
	var root: AnimationNode = _owner.anim_tree.tree_root
	if root is AnimationNodeStateMachine:
		sm = root as AnimationNodeStateMachine
	elif root is AnimationNodeBlendTree:
		var bt: AnimationNodeBlendTree = root as AnimationNodeBlendTree
		var sm_node_name: String = PlayerAnimation.SM_BASE.replace("parameters/", "")
		if bt.has_node(sm_node_name):
			sm = bt.get_node(sm_node_name) as AnimationNodeStateMachine
	if sm != null and not resolve_target(cmd, sm).is_empty():
		queue_command(cmd, send_net)
		return true
	if action_name == &"homing" and sm != null and sm.has_node(&"JUMPDASH"):
		queue_command(&"JUMPDASH", send_net)
		return true
	if not _owner._missing_anim_command_logged.has(cmd):
		_owner._missing_anim_command_logged[cmd] = true
		push_warning("Missing AnimationTree state '%s'" % String(cmd))
	return false


func resolve_target(cmd: StringName, sm: AnimationNodeStateMachine) -> Dictionary:
	var presentation = _owner.get_animation_director().get_action_backend()
	if presentation.is_enabled():
		var target: StringName = presentation.resolve(cmd)
		if target != &"":
			return {"machine": &"Actions", "state": target}
		if cmd == &"CMD_LANDING_ROLL" or String(cmd).begins_with("Carry_"):
			return {"machine": &"Overlay", "state": cmd}
	if _owner.get_animation_director().get_motion_backend().has_command(cmd):
		return {"machine": &"Motion", "state": cmd}
	if sm == null:
		return {}
	if sm.has_node(cmd):
		return {"machine": &"", "state": cmd}
	var aliases: Dictionary = {
		&"CMD_ROLL": &"ROLL",
		&"CMD_BOUNCE": &"BOUNCE",
		&"CMD_RAIL": &"RAIL",
		&"CMD_SKYDIVE": &"SKYDIVE_MACHINE",
		&"CMD_SPINDASH": &"SPINDASH",
		&"CMD_DROP_DASH": &"DROPDASH",
		&"CMD_SPINDASHRAIL": &"SPINDASHRAIL",
		&"CMD_SPIN_KICK": &"SPINKICK",
		&"CMD_TORNADO_KICK": &"TORNADOKICK",
		&"CMD_LEDGE_GRAB": &"LEDGE_GRAB",
		&"CMD_TRICK_PITCH_FORWARD": &"Trick_Pitch_Forward",
		&"CMD_TRICK_PITCH_BACK": &"Trick_Pitch_Back",
		&"CMD_TRICK_YAW_LEFT": &"Trick_Yaw_Left",
		&"CMD_TRICK_YAW_RIGHT": &"Trick_Yaw_Right",
		&"CMD_TRICK_ROLL_LEFT": &"Trick_Roll_Left",
		&"CMD_TRICK_ROLL_RIGHT": &"Trick_Roll_Right",
	}
	var state: StringName = aliases.get(cmd, cmd) as StringName
	if sm.has_node(state):
		return {"machine": &"", "state": state}
	for machine_name: StringName in sm.get_node_list():
		var machine: AnimationNodeStateMachine = sm.get_node(machine_name) as AnimationNodeStateMachine
		if machine != null and machine.has_node(state):
			return {"machine": machine_name, "state": state}
	return {}


func release_grounded_parkour() -> void:
	if not _owner.attached or _owner.is_parkour_active() or _owner._is_dead or _owner._hurt_active or not _owner.anim_state:
		return
	var parkour = _owner._get_action_by_id(&"parkour")
	if not parkour:
		return
	if parkour.owns_wall_animation(_owner._pending_anim_command):
		_owner._pending_anim_command = &""
		_owner._pending_anim_crossfade = -1.0
	if _owner._pending_anim_command == &"" and parkour.owns_wall_animation(_owner.anim_state.get_current_node()):
		_owner.get_animation_director().resume_movement()


func apply_pending(force_direct: bool = false) -> void:
	var anim_tree: AnimationTree = _owner.anim_tree
	var anim_state: AnimationNodeStateMachinePlayback = _owner.anim_state
	if _owner._pending_anim_command == &"":
		return
	if anim_state == null:
		return

	var cmd: StringName = _owner._pending_anim_command
	var xfade: float = _owner._pending_anim_crossfade
	var director = _owner.get_animation_director()
	if director.get_action_backend().is_enabled():
		_owner._pending_anim_command = &""
		_owner._pending_anim_crossfade = -1.0
		if cmd == &"CMD_LANDING_ROLL":
			director.get_overlay_backend().request_landing_roll()
		elif String(cmd).begins_with("Carry_"):
			director.get_overlay_backend().request_carry(cmd)
		elif director.get_motion_backend().has_command(cmd):
			director.get_overlay_backend().interrupt(&"motion")
			director.get_motion_backend().apply_command(cmd)
		else:
			director.get_action_backend().apply_command(cmd, force_direct)
		return
	for action in _owner._actions:
		if action != null and is_instance_valid(action) and action.try_handle_animation_command(cmd):
			_owner._pending_anim_command = &""
			_owner._pending_anim_crossfade = -1.0
			return
	if _owner.get_animation_director().get_motion_backend().apply_command(cmd):
		_owner._pending_anim_command = &""
		_owner._pending_anim_crossfade = -1.0
		return
	var sm: AnimationNodeStateMachine = _owner._get_main_animation_state_machine()
	var command_target: Dictionary = resolve_target(cmd, sm)
	if not command_target.is_empty():
		var requested_command: StringName = cmd
		var machine_name: StringName = command_target["machine"]
		cmd = command_target["state"]
		if machine_name != &"":
			var force_restart: bool = _owner.has_action_landing_animation_override()
			if force_restart or anim_state.get_current_node() != machine_name:
				if _owner.get_animation_director().get_motion_backend().is_enabled() and not force_restart:
					anim_state.travel(machine_name)
				else:
					anim_state.start(machine_name, true)
			var playback_path: String = "%s/%s/playback" % [PlayerAnimation.SM_BASE, machine_name]
			var nested_playback: AnimationNodeStateMachinePlayback = anim_tree.get(playback_path) as AnimationNodeStateMachinePlayback
			if nested_playback != null:
				var current_nested: StringName = nested_playback.get_current_node()
				var can_crossfade_trick: bool = (
					machine_name == &"TRICKS"
					and anim_state.get_current_node() == &"TRICKS"
					and String(current_nested).begins_with("Trick_")
					and current_nested != cmd
				)
				if can_crossfade_trick:
					var trick_machine: AnimationNodeStateMachine = sm.get_node(machine_name) as AnimationNodeStateMachine
					var trick_fade: float = maxf(xfade if xfade >= 0.0 else _owner.trick_anim_crossfade, 0.0)
					var trick_transition: AnimationNodeStateMachineTransition = null
					for transition_index: int in trick_machine.get_transition_count():
						if trick_machine.get_transition_from(transition_index) == current_nested and trick_machine.get_transition_to(transition_index) == cmd:
							trick_transition = trick_machine.get_transition(transition_index)
							break
					if trick_transition == null:
						trick_transition = AnimationNodeStateMachineTransition.new()
						trick_transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
						trick_transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
						trick_machine.add_transition(current_nested, cmd, trick_transition)
					trick_transition.xfade_time = trick_fade
					nested_playback.travel(cmd)
				else:
					nested_playback.start(cmd, true)
			_owner._pending_anim_command = &""
			_owner._pending_anim_crossfade = -1.0
			return
		if _owner.get_animation_director().get_motion_backend().is_enabled():
			if force_direct or not sm.has_transition(anim_state.get_current_node(), cmd):
				anim_state.start(cmd, true)
			else:
				anim_state.travel(cmd)
			_owner._pending_anim_command = &""
			_owner._pending_anim_crossfade = -1.0
			return
		if cmd != requested_command:
			anim_state.start(cmd)
			_owner._pending_anim_command = &""
			_owner._pending_anim_crossfade = -1.0
			return
	if force_direct and sm != null and sm.has_node(cmd):
		anim_state.start(cmd, true)
		_owner._pending_anim_command = &""
		_owner._pending_anim_crossfade = -1.0
		return

	if (cmd == &"CMD_SPRING" or cmd == &"CMD_HOMING" or cmd == &"JUMPDASH" or cmd == &"ROLL") and anim_state.has_method("start"):
		anim_state.start(cmd)
	else:
		if xfade >= 0.0:
			if sm != null:
				var from: StringName = anim_state.get_current_node()
				var found_transition: bool = false

				for i: int in sm.get_transition_count():
					if sm.get_transition_to(i) == cmd:
						if from == &"" or sm.get_transition_from(i) == from:
							var trans: AnimationNodeStateMachineTransition = sm.get_transition(i)
							if trans:
								trans.xfade_time = xfade
								found_transition = true

				if not found_transition and from != &"" and from != cmd:
					var new_trans: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
					new_trans.xfade_time = xfade
					new_trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
					new_trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
					sm.add_transition(from, cmd, new_trans)

		anim_state.travel(cmd)

	_owner._pending_anim_command = &""
	_owner._pending_anim_crossfade = -1.0

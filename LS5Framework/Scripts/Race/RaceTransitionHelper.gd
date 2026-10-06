extends RefCounted
class_name RaceTransitionHelper


static func fade_teleport_player(
		context: Node,
		player: Node,
		target_transform: Transform3D,
		fade_out_duration: float,
		fade_hold_duration: float,
		fade_in_duration: float,
		fade_color: Color = Color.WHITE,
		can_continue: Callable = Callable()
	) -> void:
	if context == null or not is_instance_valid(context):
		return
	if player == null or not is_instance_valid(player):
		return
	var tree: SceneTree = context.get_tree()
	if tree == null:
		return

	var previous_ui_blocked: bool = false
	if player.has_method("get"):
		var blocked_value = player.get("_ui_input_blocked")
		if blocked_value is bool:
			previous_ui_blocked = bool(blocked_value)
	if player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", true)

	var fader: Node = _get_or_create_fader(context)
	var previous_fade_color: Color = Color.BLACK
	if fader != null and fader.has_method("get"):
		var color_value = fader.get("fade_color")
		if color_value is Color:
			previous_fade_color = color_value
	if fader != null and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", fade_color)

	var fade_out_time: float = max(fade_out_duration, 0.0)
	var hold_time: float = max(fade_hold_duration, 0.0)
	var fade_in_time: float = max(fade_in_duration, 0.0)
	_notify_camera_teleport(context, player, fade_out_time + hold_time + fade_in_time)
	if fader != null and fader.has_method("fade_out"):
		await fader.call("fade_out", fade_out_time)
	if not _transition_is_valid(context, player, can_continue):
		_cancel_transition(fader, player, previous_ui_blocked)
		return
	if hold_time > 0.0:
		await tree.create_timer(hold_time).timeout
	if not _transition_is_valid(context, player, can_continue):
		_cancel_transition(fader, player, previous_ui_blocked)
		return

	_apply_player_transform(player, target_transform)
	_notify_camera_teleport(context, player, fade_in_time + 0.25)
	if fader != null and is_instance_valid(fader) and fader.has_method("fade_in"):
		await fader.call("fade_in", fade_in_time)
	if not _transition_is_valid(context, player, can_continue):
		_cancel_transition(fader, player, previous_ui_blocked)
		return
	if fader != null and is_instance_valid(fader) and fader.has_method("set_fade_color"):
		fader.call("set_fade_color", previous_fade_color)
	if player != null and is_instance_valid(player) and player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", previous_ui_blocked)


static func _transition_is_valid(context: Node, player: Node, can_continue: Callable) -> bool:
	return is_instance_valid(context) and context.is_inside_tree() and is_instance_valid(player) and player.is_inside_tree() and (not can_continue.is_valid() or bool(can_continue.call()))


static func _cancel_transition(fader: Node, player: Node, previous_ui_blocked: bool) -> void:
	if is_instance_valid(fader) and fader.has_method("reset_now"):
		fader.call("reset_now")
	if is_instance_valid(player) and player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", previous_ui_blocked)


static func _apply_player_transform(player: Node, target_transform: Transform3D) -> void:
	if player.has_method("_apply_respawn_transform"):
		player.call("_apply_respawn_transform", target_transform, false)
	elif player is Node3D:
		(player as Node3D).global_transform = target_transform
	if player.has_method("set"):
		player.set("velocity", Vector3.ZERO)
		player.set("attached", true)
		player.set("_prev_attached", true)
	if player.has_method("stop_all_momentum_and_special_movement"):
		player.call("stop_all_momentum_and_special_movement")
	if player.has_method("_network_publish_teleport_state"):
		player.call("_network_publish_teleport_state")


static func _get_or_create_fader(context: Node) -> Node:
	var tree: SceneTree = context.get_tree()
	if tree == null:
		return null
	var existing: Array = tree.get_nodes_in_group("ScreenFader")
	if not existing.is_empty():
		return existing[0]
	var fader: ScreenFader = ScreenFader.new()
	fader.add_to_group("ScreenFader")
	var viewport: Viewport = context.get_viewport()
	if viewport != null:
		viewport.add_child(fader)
	elif tree.current_scene != null:
		tree.current_scene.add_child(fader)
	else:
		context.add_child(fader)
	return fader


static func _notify_camera_teleport(context: Node, player: Node, duration: float) -> void:
	var camera_rig: Node = null
	if player.has_method("get"):
		var rig_value = player.get("camera_rig")
		if rig_value is Node:
			camera_rig = rig_value
	if camera_rig == null and context.get_tree() != null:
		var rigs: Array = context.get_tree().get_nodes_in_group("CameraRig")
		if not rigs.is_empty() and rigs[0] is Node:
			camera_rig = rigs[0]
	if camera_rig != null and camera_rig.has_method("notify_teleport"):
		camera_rig.call("notify_teleport", max(duration, 0.0))

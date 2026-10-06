extends RefCounted
class_name PlayerNetworkReplication

const STATE_SYNCHRONIZER_SCRIPT: Script = preload("res://addons/netfox/state-synchronizer.gd")
const TICK_INTERPOLATOR_SCRIPT: Script = preload("res://addons/netfox/tick-interpolator.gd")
const STATE_SYNCHRONIZER_NAME: StringName = &"NetfoxStateSynchronizer"
const TICK_INTERPOLATOR_NAME: StringName = &"NetfoxTickInterpolator"

const PRESENTATION_PROPERTIES: Array[String] = [
	"rolling", "_spindash_charging", "_bounce_state", "_homing_active",
	"_jump_dash_recent_timer", "_is_jumping", "_is_falling", "_hurt_active", "_is_dead",
	"_player_state_locked", "_spring_align_timer", "_spline_active", "_vault_bar_active",
	"_rail_switch_active", "_rail_switch_animation_side", "race_finished",
]

const STATE_PROPERTIES: Array[String] = [
	":movement_time_scale",
	":movement_time_scale_multiplier",
	":movement_time_scale_debuff_multiplier",
	":_net_has_state",
	":_net_state_sequence",
	":_net_target_transform",
	":_net_target_velocity",
	":_net_target_attached",
	":_net_target_state_flags",
	":_net_target_main_state",
	":_net_target_visual_up",
	":_net_target_model_basis",
	":_net_target_move_direction",
	":_net_target_barrier_blast_gauge",
	":_net_target_action_id",
	":_net_animation_states",
	":_net_animation_values",
	":_net_presentation_state",
]

const INTERPOLATED_PROPERTIES: Array[String] = [
	":_net_target_transform",
	":_net_target_velocity",
	":_net_target_visual_up",
	":_net_target_model_basis",
	":_net_target_move_direction",
	":_net_target_barrier_blast_gauge",
]

var _owner: Node = null
var _state_synchronizer = null
var _tick_interpolator = null
var _visibility_filter: Callable = Callable()
var _last_remote_state_sequence: int = 0
var _remote_snap_updates_remaining: int = 0
var _remote_interpolation_started: bool = false
var _level_present: bool = true
var _teleport_state_floor: int = 0
var _teleport_state: Dictionary = {}


func _init(owner: Node) -> void:
	_owner = owner


func is_active() -> bool:
	var player = _owner
	return player and player.multiplayer and player.multiplayer.has_multiplayer_peer() and not (player.multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and player.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_local_authority() -> bool:
	var player = _owner
	if not is_active():
		return true
	return player.is_multiplayer_authority()


func configure_for_role() -> void:
	var player = _owner
	if player == null:
		return
	if not is_active() or not player.network_replication_enabled:
		player._anim_module.restore_authority_tree()
		_restore_collision(player)
		_remove_netfox_nodes()
		return

	var puppet: bool = not player.is_multiplayer_authority()
	if puppet:
		player.collision_layer = 0
		player.collision_mask = 0
		player.lock_cursor_to_game = false
		_stop_local_only_effects(player)
	else:
		player._anim_module.restore_authority_tree()
		_restore_collision(player)
	_ensure_netfox_nodes(puppet)


func set_visibility_filter(filter: Callable) -> void:
	if _visibility_filter == filter:
		return
	if _state_synchronizer != null and is_instance_valid(_state_synchronizer):
		var old_filter_node: PeerVisibilityFilter = _state_synchronizer.visibility_filter
		if old_filter_node != null and _visibility_filter.is_valid():
			old_filter_node.remove_visibility_filter(_visibility_filter)
	_visibility_filter = filter
	_apply_visibility_filter()


func refresh_visibility() -> void:
	if _state_synchronizer == null or not is_instance_valid(_state_synchronizer):
		return
	var filter_node: PeerVisibilityFilter = _state_synchronizer.visibility_filter
	if filter_node != null and filter_node.is_inside_tree():
		filter_node.update_visibility()


func set_level_presence(present: bool) -> void:
	if _level_present == present:
		return
	_level_present = present
	if not present and _owner != null:
		_owner._ensure_modules()
		_owner._audio_module.stop_remote_audio()


func is_level_present() -> bool:
	return _level_present


func puppet_tick(delta: float) -> void:
	var player = _owner
	if player and player._net_state_sequence < _teleport_state_floor:
		for property: String in _teleport_state:
			player.set(property, _teleport_state[property])
	_update_remote_interpolation_bootstrap()
	if player == null or not player.network_replication_enabled or not player._net_has_state:
		return

	player.global_transform = player._net_target_transform
	player.velocity = player._net_target_velocity
	player.attached = player._net_target_attached
	player.state_flags = player._net_target_state_flags
	player.main_state = player._net_target_main_state
	player.visual_up = player._net_target_visual_up
	player._physics_up_last = player._net_target_visual_up
	player._move_direction = player._net_target_move_direction
	player._current_action_id = player._net_target_action_id
	player.rolling = (player.state_flags & player.STATE_ROLL) != 0
	player._spindash_charging = (player.state_flags & player.STATE_SPINDASH) != 0
	player._horizontal_speed = player.velocity.slide(player.visual_up.normalized()).length()
	player._vertical_speed = player.velocity.dot(player.visual_up.normalized())
	for index: int in mini(player._net_presentation_state.size(), PRESENTATION_PROPERTIES.size()):
		var property: String = PRESENTATION_PROPERTIES[index]
		var current_value: Variant = player.get(property)
		var received_value: float = player._net_presentation_state[index]
		if current_value is bool:
			player.set(property, bool(received_value))
		elif current_value is int:
			player.set(property, int(received_value))
		else:
			player.set(property, received_value)

	var rail_flagged: bool = (player._net_target_state_flags & player.STATE_RAIL) != 0
	player._rail_active = rail_flagged
	if rail_flagged:
		var travel_sign: float = 1.0
		if (player._net_target_state_flags & player.STATE_RAIL_BACKWARD) != 0:
			travel_sign = -1.0
		elif (player._net_target_state_flags & player.STATE_RAIL_FORWARD) != 0:
			travel_sign = 1.0
		player._rail_travel_sign = travel_sign
		player._rail_speed = player._net_target_velocity.length() * travel_sign
	else:
		player._rail_travel_sign = 1.0
		player._rail_speed = 0.0

	if player.model_root != null:
		var model_transform: Transform3D = player.model_root.global_transform
		model_transform.basis = player._net_target_model_basis
		player.model_root.global_transform = model_transform
	if not _level_present:
		player._prev_attached = player.attached
		player._air_torque_prev_attached = player.attached and player._spring_align_timer <= 0.0 and not player._spline_active and not player._rail_active
		return

	if player._net_animation_states.is_empty():
		player._update_animation(delta)
	else:
		player._anim_module.apply_network_snapshot(player._net_animation_states, player._net_animation_values)
	player._update_jump_ball(delta)
	player._update_jump_dash_trail(delta)
	player._update_skid_sfx(delta, player._get_lateral_speed_for_anim())
	player._update_puppet_barrier_blast_fx(delta)
	player._prev_attached = player.attached
	if player._spring_align_timer > 0.0 or player._spline_active or player._rail_active:
		player._air_torque_prev_attached = false
	else:
		player._air_torque_prev_attached = player.attached


func capture_state(_delta: float) -> void:
	var player = _owner
	if player == null or not is_active() or not player.network_replication_enabled:
		return
	if not player.is_multiplayer_authority():
		return

	player._net_state_sequence += 1
	var model_basis: Basis = Basis.IDENTITY
	if player.model_root != null:
		model_basis = player.model_root.global_transform.basis
	player._net_target_transform = player.global_transform
	player._net_target_velocity = player.velocity
	player._net_target_attached = player.attached
	player._net_target_state_flags = player.state_flags
	player._net_target_main_state = player.main_state
	player._net_target_visual_up = player.visual_up
	player._net_target_model_basis = model_basis
	player._net_target_move_direction = player._move_direction
	player._net_target_barrier_blast_gauge = clamp(player._barrier_blast_gauge, 0.0, 1.0)
	player._net_target_action_id = player._current_action_id
	var animation_snapshot: Dictionary = player._anim_module.capture_network_snapshot()
	player._net_animation_states = animation_snapshot.get("states", {})
	player._net_animation_values = animation_snapshot.get("values", [])
	var presentation: PackedFloat32Array = PackedFloat32Array()
	for property: String in PRESENTATION_PROPERTIES:
		presentation.append(float(player.get(property)))
	player._net_presentation_state = presentation
	player._net_has_state = true


func initialize_spawn_state(spawn_transform: Transform3D) -> void:
	var player = _owner
	if player == null:
		return
	if is_active() and not player.is_multiplayer_authority():
		prepare_remote_scene_state(spawn_transform)
		return
	player.global_transform = spawn_transform
	player._initial_transform = spawn_transform
	player._net_target_transform = spawn_transform
	player._net_target_velocity = player.velocity
	player._net_target_attached = player.attached
	player._net_target_state_flags = player.state_flags
	player._net_target_main_state = player.main_state
	player._net_target_visual_up = player.visual_up
	player._net_target_move_direction = player._move_direction
	player._net_target_barrier_blast_gauge = clamp(player._barrier_blast_gauge, 0.0, 1.0)
	player._net_target_action_id = player._current_action_id
	if player.model_root != null:
		player._net_target_model_basis = player.model_root.global_transform.basis
	player._net_has_state = true


func prepare_remote_scene_state(spawn_transform: Transform3D) -> void:
	var player = _owner
	if player == null:
		return
	player.global_transform = spawn_transform
	player._initial_transform = spawn_transform
	player._net_target_transform = spawn_transform
	player._net_target_velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.attached = false
	player._net_has_state = false
	player._net_animation_states = {}
	player._net_animation_values = []
	player._net_presentation_state = PackedFloat32Array()
	_teleport_state_floor = 0
	_teleport_state.clear()
	_begin_remote_interpolation_bootstrap()


func get_state_sequence() -> int:
	var player = _owner
	if player == null:
		return 0
	return player._net_state_sequence


func request_authoritative_teleport() -> void:
	var player = _owner
	if player == null or not is_active() or player.is_multiplayer_authority():
		return
	var authority_id: int = player.get_multiplayer_authority()
	if authority_id <= 0:
		return
	player.rpc_id(authority_id, "_net_request_authoritative_teleport")


func publish_teleport_state(target_peer_id: int = 0) -> void:
	var player = _owner
	if player == null or not is_active() or not player.network_replication_enabled:
		return
	if not player.is_multiplayer_authority():
		return
	player._update_main_state_and_flags(0.0)
	player._update_animation(0.0)
	if player.anim_tree:
		player.anim_tree.advance(0.0)
	capture_state(0.0)
	var model_basis: Basis = Basis.IDENTITY
	if player.model_root != null:
		model_basis = player.model_root.global_transform.basis
	if target_peer_id > 0:
		player.rpc_id(
			target_peer_id,
			"_net_authoritative_teleport",
			player._net_target_transform,
			player._net_target_velocity,
			player._net_target_attached,
			player._net_target_state_flags,
			player._net_target_main_state,
			player._net_target_visual_up,
			model_basis,
			player._net_target_move_direction,
			player._net_target_barrier_blast_gauge,
			player._net_target_action_id,
			player._net_state_sequence,
			player._net_animation_states,
			player._net_animation_values,
			player._net_presentation_state
		)
	else:
		player.rpc(
			"_net_authoritative_teleport",
			player._net_target_transform,
			player._net_target_velocity,
			player._net_target_attached,
			player._net_target_state_flags,
			player._net_target_main_state,
			player._net_target_visual_up,
			model_basis,
			player._net_target_move_direction,
			player._net_target_barrier_blast_gauge,
			player._net_target_action_id,
			player._net_state_sequence,
			player._net_animation_states,
			player._net_animation_values,
			player._net_presentation_state
		)


func receive_authoritative_teleport_request() -> void:
	var player = _owner
	if player == null or not is_active() or not player.is_multiplayer_authority():
		return
	var sender: int = player.multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	publish_teleport_state(sender)


func receive_authoritative_teleport(
		transform_value: Transform3D,
		velocity_value: Vector3,
		attached_value: bool,
		flags_value: int,
		main_state_value: int,
		visual_up_value: Vector3,
		model_basis_value: Basis,
		move_direction_value: Vector3,
		barrier_blast_gauge_value: float,
		action_id_value: StringName,
		state_sequence: int,
		animation_states: Dictionary,
		animation_values: Array,
		presentation_state: PackedFloat32Array
	) -> void:
	var player = _owner
	if player == null or not is_active() or player.is_multiplayer_authority():
		return
	var sender: int = player.multiplayer.get_remote_sender_id()
	if sender != player.get_multiplayer_authority():
		return
	if state_sequence < _teleport_state_floor:
		return
	_teleport_state_floor = state_sequence
	player._net_target_transform = transform_value
	player._net_target_velocity = velocity_value
	player._net_target_attached = attached_value
	player._net_target_state_flags = flags_value
	player._net_target_main_state = main_state_value
	player._net_target_visual_up = visual_up_value
	player._net_target_model_basis = model_basis_value
	player._net_target_move_direction = move_direction_value
	player._net_target_barrier_blast_gauge = barrier_blast_gauge_value
	player._net_target_action_id = action_id_value
	player._net_state_sequence = state_sequence
	player._net_animation_states = animation_states
	player._net_animation_values = animation_values
	player._net_presentation_state = presentation_state
	player._net_has_state = true
	_teleport_state.clear()
	for property: String in STATE_PROPERTIES:
		if property.begins_with(":_net_"):
			var property_name: String = property.trim_prefix(":")
			_teleport_state[property_name] = player.get(property_name)
	player.global_transform = transform_value
	player.velocity = velocity_value
	player.attached = attached_value
	player.state_flags = flags_value
	player.main_state = main_state_value
	player.visual_up = visual_up_value
	player._physics_up_last = visual_up_value
	player._move_direction = move_direction_value
	player._current_action_id = action_id_value
	if player.model_root != null:
		var model_transform: Transform3D = player.model_root.global_transform
		model_transform.basis = model_basis_value
		player.model_root.global_transform = model_transform
	_begin_remote_interpolation_bootstrap()


func receive_animation_command(command: StringName) -> void:
	var player = _owner
	if player == null or not _level_present or not is_active() or not player.network_replication_enabled:
		return
	var sender: int = player.multiplayer.get_remote_sender_id()
	if sender != player.get_multiplayer_authority():
		return
	player._trigger_anim_command(command, false)


func apply_debug_puppet_state(
	transform_value: Transform3D,
	velocity_value: Vector3,
	attached_value: bool,
	flags_value: int,
	main_state_value: int,
	visual_up_value: Vector3,
	model_basis_value: Basis,
	move_direction_value: Vector3,
	barrier_blast_gauge_value: float,
	action_id_value: StringName
) -> void:
	var player = _owner
	if player == null:
		return
	player._net_state_sequence += 1
	player._net_target_transform = transform_value
	player._net_target_velocity = velocity_value
	player._net_target_attached = attached_value
	player._net_target_state_flags = flags_value
	player._net_target_main_state = main_state_value
	player._net_target_visual_up = visual_up_value
	player._net_target_model_basis = model_basis_value
	player._net_target_move_direction = move_direction_value
	player._net_target_barrier_blast_gauge = barrier_blast_gauge_value
	player._net_target_action_id = action_id_value
	player._net_has_state = true


func receive_action_sfx(tag: String, index: int) -> void:
	var player = _owner
	if player == null or not _level_present or not is_active() or not player.network_replication_enabled:
		return
	var sender: int = player.multiplayer.get_remote_sender_id()
	if sender != player.get_multiplayer_authority():
		return
	if tag == "jump":
		if player.sfx_player == null or index < 0 or index >= player.jump_sounds.size():
			return
		player.sfx_player.volume_db = linear_to_db(player.jump_volume)
		player.sfx_player.stream = player.jump_sounds[index]
		player.sfx_player.play()
		return
	if tag == "jumpdash":
		if player.sfx_player == null or index < 0 or index >= player.jumpdash_sounds.size():
			return
		player.sfx_player.volume_db = linear_to_db(player.jumpdash_volume)
		player.sfx_player.stream = player.jumpdash_sounds[index]
		player.sfx_player.play()
		return

	if tag == "bounce_start":
		player._play_sfx(player.sfx_bounce_start)
	elif tag == "bounce_land":
		player._play_sfx(player.sfx_bounce_land)
	elif tag == "stomp_start":
		player._play_sfx(player.sfx_stomp_start)
	elif tag == "stomp_land":
		player._play_sfx(player.sfx_stomp_land)
	elif tag == "spindash_loop":
		player._start_spindash_loop_sfx(false)
	elif tag == "spindash_loop_stop":
		player._stop_spindash_loop_sfx(false)
	elif tag == "spindash_full":
		player._play_spindash_charge_full_sfx(false)
	elif tag == "spindash_release":
		player._play_spindash_release_sfx(false)


func receive_footstep_sfx(
	surface: int,
	index: int,
	volume_linear: float,
	foot: StringName,
	emit_dust: bool,
	water_index: int,
	water_volume: float
) -> void:
	var player = _owner
	if player == null or not _level_present or not is_active() or not player.network_replication_enabled:
		return
	var sender: int = player.multiplayer.get_remote_sender_id()
	if sender != player.get_multiplayer_authority():
		return
	player._ensure_modules()
	if player._audio_module == null:
		return
	player._audio_module.play_remote_footstep(
		surface,
		index,
		volume_linear,
		foot,
		emit_dust,
		water_index,
		water_volume
	)


func _ensure_netfox_nodes(puppet: bool) -> void:
	var player = _owner
	if player == null or not player.is_inside_tree():
		return

	_state_synchronizer = player.get_node_or_null(NodePath(String(STATE_SYNCHRONIZER_NAME)))
	if _state_synchronizer == null:
		_state_synchronizer = STATE_SYNCHRONIZER_SCRIPT.new()
		_state_synchronizer.name = STATE_SYNCHRONIZER_NAME
		_state_synchronizer.root = player
		_state_synchronizer.properties = STATE_PROPERTIES.duplicate()
		_state_synchronizer.full_state_interval = player.network_full_state_interval_ticks
		_state_synchronizer.diff_ack_interval = player.network_diff_ack_interval_ticks
		_state_synchronizer.set_multiplayer_authority(player.get_multiplayer_authority())
		player.add_child(_state_synchronizer)
	else:
		_state_synchronizer.root = player
		_state_synchronizer.properties = STATE_PROPERTIES.duplicate()
		_state_synchronizer.full_state_interval = player.network_full_state_interval_ticks
		_state_synchronizer.diff_ack_interval = player.network_diff_ack_interval_ticks
		_state_synchronizer.set_multiplayer_authority(player.get_multiplayer_authority())
		_state_synchronizer.process_settings()

	if not puppet:
		_remote_interpolation_started = false
		_remote_snap_updates_remaining = 0
		_remove_tick_interpolator()
		_apply_visibility_filter()
		return

	_begin_remote_interpolation_bootstrap()
	_apply_visibility_filter()


func _begin_remote_interpolation_bootstrap() -> void:
	var player = _owner
	if player == null:
		return
	if _tick_interpolator == null:
		_tick_interpolator = player.get_node_or_null(NodePath(String(TICK_INTERPOLATOR_NAME)))
	_remove_tick_interpolator()
	_last_remote_state_sequence = player._net_state_sequence
	_remote_snap_updates_remaining = max(player.network_initial_snap_updates, 1)
	_remote_interpolation_started = false


func _update_remote_interpolation_bootstrap() -> void:
	var player = _owner
	if player == null or not is_active() or player.is_multiplayer_authority():
		return
	if not player.network_interpolate_remote_state:
		return
	if _remote_interpolation_started:
		return
	var current_sequence: int = player._net_state_sequence
	if current_sequence <= 0 or current_sequence == _last_remote_state_sequence:
		return
	_last_remote_state_sequence = current_sequence
	_remote_snap_updates_remaining = max(_remote_snap_updates_remaining - 1, 0)
	if _remote_snap_updates_remaining <= 0:
		_enable_remote_interpolation()


func _enable_remote_interpolation() -> void:
	var player = _owner
	if player == null or not player.is_inside_tree() or not player.network_interpolate_remote_state:
		return
	_tick_interpolator = player.get_node_or_null(NodePath(String(TICK_INTERPOLATOR_NAME)))
	if _tick_interpolator == null:
		_tick_interpolator = TICK_INTERPOLATOR_SCRIPT.new()
		_tick_interpolator.name = TICK_INTERPOLATOR_NAME
		_tick_interpolator.root = player
		_tick_interpolator.properties = INTERPOLATED_PROPERTIES.duplicate()
		_tick_interpolator.enabled = true
		_tick_interpolator.record_first_state = false
		_tick_interpolator.set_multiplayer_authority(player.get_multiplayer_authority())
		player.add_child(_tick_interpolator)
		_tick_interpolator.process_settings()
	else:
		_tick_interpolator.enabled = true
		_tick_interpolator.enable_recording = true
		_tick_interpolator.record_first_state = false
		_tick_interpolator.properties = INTERPOLATED_PROPERTIES.duplicate()
		_tick_interpolator.set_multiplayer_authority(player.get_multiplayer_authority())
		_tick_interpolator.process_settings()
	_tick_interpolator.teleport()
	_remote_interpolation_started = true


func _apply_visibility_filter() -> void:
	if _state_synchronizer == null or not is_instance_valid(_state_synchronizer):
		return
	var filter_node: PeerVisibilityFilter = _state_synchronizer.visibility_filter
	if filter_node == null:
		return
	filter_node.update_mode = PeerVisibilityFilter.UpdateMode.PER_TICK_LOOP
	if _visibility_filter.is_valid():
		filter_node.add_visibility_filter(_visibility_filter)
	if filter_node.is_inside_tree():
		filter_node.update_visibility()


func _remove_netfox_nodes() -> void:
	if _state_synchronizer != null and is_instance_valid(_state_synchronizer):
		_state_synchronizer.queue_free()
	_state_synchronizer = null
	_remove_tick_interpolator()


func _remove_tick_interpolator() -> void:
	if _tick_interpolator != null and is_instance_valid(_tick_interpolator):
		_tick_interpolator.enabled = false
		_tick_interpolator.enable_recording = false
		_tick_interpolator.properties.clear()
		_tick_interpolator.process_settings()
		var interpolator_parent: Node = _tick_interpolator.get_parent()
		if interpolator_parent != null:
			interpolator_parent.remove_child(_tick_interpolator)
		_tick_interpolator.queue_free()
	_tick_interpolator = null


func _restore_collision(player) -> void:
	if player._net_saved_collision:
		player.collision_layer = player._net_initial_collision_layer
		player.collision_mask = player._net_initial_collision_mask


func _stop_local_only_effects(player) -> void:
	if player.jump_dash_trail != null and player.jump_dash_trail.has_method("stop_and_clear"):
		player.jump_dash_trail.call("stop_and_clear")
	if player.jump_ball != null and player.jump_ball.has_method("set_jump_ball_active"):
		player.jump_ball.call(
			"set_jump_ball_active",
			0.0,
			false,
			player.global_position,
			Vector3.FORWARD,
			player.get_gravity_up()
		)
	if player.sfx_barrier_blast_wind != null:
		if player.has_method("_stop_barrier_blast_wind_sfx"):
			player.call("_stop_barrier_blast_wind_sfx")
		else:
			player.sfx_barrier_blast_wind.stop()
			player.sfx_barrier_blast_wind.volume_db = player.barrier_blast_wind_silent_db
			player.sfx_barrier_blast_wind.pitch_scale = player.barrier_blast_wind_pitch_min

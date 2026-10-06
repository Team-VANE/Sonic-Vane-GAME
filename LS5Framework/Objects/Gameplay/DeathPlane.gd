extends WorldObject

@export var death_delay: float = 3.0
@export var freeze_camera_at_death: bool = true
## Decreases death-camera FOV as the player travels away from the frozen camera.
@export var death_camera_distance_fov_enabled: bool = false
## Maximum FOV decrease from the player's configured camera FOV.
@export_range(0.0, 120.0, 0.1, "or_greater", "suffix:deg") var death_camera_fov_max_reduction: float = 20.0
## Additional camera-to-player distance before FOV reduction begins.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m") var death_camera_fov_reduction_start_distance: float = 0.0
## Additional camera-to-player distance where the maximum FOV reduction is reached.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m") var death_camera_fov_reduction_full_distance: float = 30.0
## FOV response speed while distance-based reduction is active. A value of 0 applies immediately.
@export_range(0.0, 60.0, 0.1, "or_greater") var death_camera_fov_smoothing: float = 8.0
@export var disable_player_input_during_death: bool = true
@export var fade_enabled: bool = true
@export var fade_out_duration: float = 0.35
@export var fade_hold_duration: float = 0.05
@export var fade_in_duration: float = 0.35
## Collision mask added at runtime for carryable objects.
@export_flags_3d_physics var carryable_collision_mask: int = 2
## Collision mask added at runtime for enemies affected by death planes.
@export_flags_3d_physics var enemy_collision_mask: int = 128

static var _death_sequence_in_progress: bool = false
static var _death_sequence_owner_id: int = 0
static var _death_cancel_token: int = 0

var _active_players: Dictionary = {}


func _ready() -> void:
	if carryable_collision_mask > 0:
		collision_mask = collision_mask | carryable_collision_mask
	if enemy_collision_mask > 0:
		collision_mask = collision_mask | enemy_collision_mask
	super._ready()


func _on_body_entered(body: Node3D) -> void:
	if not enabled:
		return
	if body.has_method("apply_environmental_hazard"):
		body.call("apply_environmental_hazard", &"death_plane", self)
		return
	if _try_respawn_carryable(body):
		return
	super._on_body_entered(body)


func _try_respawn_carryable(body: Node) -> bool:
	if not body.has_method("respawn_carryable"):
		return false
	return body.call("respawn_carryable", self) == true


func _apply_to_player(player: Node3D) -> void:
	if player == null:
		return

	# Only affect the local client in multiplayer.
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if player.has_method("is_multiplayer_authority") and not player.is_multiplayer_authority():
			return

	if player.has_method("is_player_state_locked") and player.call("is_player_state_locked"):
		return
	if player.has_method("apply_death_plane_damage"):
		player.call("apply_death_plane_damage", self)
		return

	var id: int = player.get_instance_id()
	if _death_sequence_in_progress:
		return
	if _active_players.has(id):
		if _death_sequence_owner_id == id:
			return
		_active_players.erase(id)
	_active_players[id] = true
	_death_sequence_in_progress = true
	_death_sequence_owner_id = id

	call_deferred("_run_death_sequence", player, id)


static func cancel_death_sequence() -> void:
	_death_cancel_token += 1
	_death_sequence_in_progress = false
	_death_sequence_owner_id = 0


static func is_death_sequence_in_progress() -> bool:
	return _death_sequence_in_progress


func _run_death_sequence(player: Node3D, player_id: int) -> void:
	var my_token: int = _death_cancel_token
	if player == null or not is_instance_valid(player):
		_active_players.erase(player_id)
		if _death_sequence_owner_id == player_id:
			_death_sequence_owner_id = 0
			_death_sequence_in_progress = false
		return

	# Trigger trick/combo death effect immediately
	if player.has_method("begin_death_sequence"):
		player.call("begin_death_sequence", &"pit")
	elif player.has_method("set_death_state"):
		player.call("set_death_state", true)
	elif player.has_method("_on_player_hurt"):
		player.call("_on_player_hurt")

	var rig = _resolve_camera_rig(player)
	if rig != null and is_instance_valid(rig):
		if rig.has_method("reset_camera_effects"):
			rig.call("reset_camera_effects", true)
		elif rig.has_method("clear_camera_constraints"):
			rig.call("clear_camera_constraints", null, true)

	var death_constraint = null
	if freeze_camera_at_death and rig != null and is_instance_valid(rig):
		death_constraint = _create_death_constraint_from_rig(rig, player)
		if death_constraint != null:
			_add_constraint_to_scene(death_constraint)
			if rig.has_method("register_camera_constraint"):
				rig.call("register_camera_constraint", death_constraint)

			# Lock distance + disable collision so the camera stays exactly where it was.
			if rig.has_method("begin_distance_lock"):
				var lock_distance: float = _get_rig_camera_distance(rig)
				rig.call("begin_distance_lock", lock_distance, true)

	if disable_player_input_during_death and player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", true)

	var fader = null
	if fade_enabled:
		fader = _get_or_create_fader(player)

	# Watch the fall first, then fade out for the respawn.
	var watch_delay: float = max(death_delay, 0.0)
	if get_tree() != null and watch_delay > 0.0:
		await get_tree().create_timer(watch_delay).timeout
		if my_token != _death_cancel_token:
			_cleanup_after_cancel(player, rig, death_constraint)
			return

	if fade_enabled and fader != null and is_instance_valid(fader) and fader.has_method("fade_out"):
		await fader.call("fade_out", fade_out_duration)
		if my_token != _death_cancel_token:
			_cleanup_after_cancel(player, rig, death_constraint)
			return
		if get_tree() != null and fade_hold_duration > 0.0:
			await get_tree().create_timer(fade_hold_duration).timeout
			if my_token != _death_cancel_token:
				_cleanup_after_cancel(player, rig, death_constraint)
				return

	if my_token != _death_cancel_token:
		_cleanup_after_cancel(player, rig, death_constraint)
		return

	if player != null and is_instance_valid(player):
		# Detach from any spline/rail constraints before respawning.
		if player.has_method("cancel_spline_spring"):
			player.call("cancel_spline_spring")
		if player.has_method("cancel_rail_grind"):
			player.call("cancel_rail_grind")

		# Respawn at checkpoint (future) or respawn_point/_initial_transform fallback.
		if player.has_method("respawn_checkpoint_now"):
			player.call("respawn_checkpoint_now")
		elif player.has_method("respawn_now"):
			player.call("respawn_now")
		elif player.has_method("_respawn"):
			player.call("_respawn")
		if player.has_method("apply_death_respawn_consequences"):
			player.call("apply_death_respawn_consequences", &"pit")
		elif player.has_method("reset_rings"):
			player.call("reset_rings")

		if disable_player_input_during_death and player.has_method("set_ui_input_blocked"):
			player.call("set_ui_input_blocked", false)

		# Make sure the camera snaps (no smoothing) to the respawned target.
		var prig = _resolve_camera_rig(player)
		if prig != null and is_instance_valid(prig) and prig.has_method("notify_teleport"):
			prig.call("notify_teleport")

	# Remove temporary camera lock/constraint.
	if rig != null and is_instance_valid(rig):
		if rig.has_method("end_distance_lock"):
			rig.call("end_distance_lock")
		if death_constraint != null and rig.has_method("unregister_camera_constraint"):
			rig.call("unregister_camera_constraint", death_constraint)

	if death_constraint != null and is_instance_valid(death_constraint):
		death_constraint.queue_free()

	# Fade back in after we've restored normal camera behavior.
	if fade_enabled and fader != null and is_instance_valid(fader) and fader.has_method("fade_in"):
		await fader.call("fade_in", fade_in_duration)
		if my_token != _death_cancel_token:
			_cleanup_after_cancel(player, rig, null)
			return

	if player != null and is_instance_valid(player):
		if player.has_method("finish_death_sequence"):
			player.call("finish_death_sequence")
		elif player.has_method("set_death_state"):
			player.call("set_death_state", false)

	_active_players.erase(player_id)
	if _death_sequence_owner_id == player_id:
		_death_sequence_owner_id = 0
		_death_sequence_in_progress = false


func _cleanup_after_cancel(player: Node3D, rig: Node, death_constraint: Node) -> void:
	if player != null and is_instance_valid(player):
		_active_players.erase(player.get_instance_id())
		if player.has_method("set_death_state"):
			player.call("set_death_state", false)
		if disable_player_input_during_death and player.has_method("set_ui_input_blocked"):
			player.call("set_ui_input_blocked", false)
	if rig != null and is_instance_valid(rig):
		if rig.has_method("end_distance_lock"):
			rig.call("end_distance_lock")
		if death_constraint != null and rig.has_method("unregister_camera_constraint"):
			rig.call("unregister_camera_constraint", death_constraint)
	if death_constraint != null and is_instance_valid(death_constraint):
		death_constraint.queue_free()


func _resolve_camera_rig(player: Node3D) -> Node:
	if player.has_method("get"):
		var r = player.get("camera_rig")
		if r != null:
			return r

	if get_tree() == null:
		return null
	var rigs = get_tree().get_nodes_in_group("CameraRig")
	if rigs != null and rigs.size() > 0:
		return rigs[0]
	return null


func _get_rig_camera_distance(rig: Node) -> float:
	if rig == null or not rig.has_method("get"):
		return 0.0
	var cam = rig.get("camera")
	if cam is Camera3D:
		var local_pos = (cam as Camera3D).position
		if abs(local_pos.z) > 0.001:
			return abs(local_pos.z)
	return 0.0


func _get_rig_default_fov(rig: Node) -> float:
	if rig != null and rig.has_method("get_default_fov"):
		var default_fov_value = rig.call("get_default_fov")
		if default_fov_value is float:
			return float(default_fov_value)
	if rig != null:
		var cam = rig.get("camera")
		if cam is Camera3D:
			return (cam as Camera3D).fov
	return 70.0


func _get_death_camera_player_distance(rig: Node, player: Node3D) -> float:
	if rig == null or player == null:
		return 0.0
	var reference_position: Vector3 = player.global_position
	var cam = rig.get("camera")
	if cam is Camera3D:
		reference_position = (cam as Camera3D).global_position
	elif rig is Node3D:
		reference_position = (rig as Node3D).global_position
	return reference_position.distance_to(player.global_position)


func _configure_death_camera_fov(constraint: DeathCameraConstraint, rig: Node, player: Node3D) -> void:
	if constraint == null or not death_camera_distance_fov_enabled:
		return
	var base_fov: float = _get_rig_default_fov(rig)
	var initial_distance: float = _get_death_camera_player_distance(rig, player)
	var start_distance: float = max(death_camera_fov_reduction_start_distance, 0.0)
	var full_distance: float = max(death_camera_fov_reduction_full_distance, start_distance + 0.001)
	constraint.lens_trait.mode = CameraLensTrait.Mode.DISTANCE_FOV
	constraint.lens_trait.near_fov = base_fov
	constraint.lens_trait.far_fov = max(base_fov - max(death_camera_fov_max_reduction, 0.0), 1.0)
	constraint.lens_trait.near_distance = initial_distance + start_distance
	constraint.lens_trait.far_distance = initial_distance + full_distance
	constraint.lens_trait.tracking_response = max(death_camera_fov_smoothing, 0.0)


func _create_death_constraint_from_rig(rig: Node, player: Node3D) -> DeathCameraConstraint:
	if rig == null or not rig.has_method("get"):
		return null

	var pos: Vector3 = (rig as Node3D).global_position if rig is Node3D else Vector3.ZERO
	var basis: Basis = Basis.IDENTITY

	# Use the pitch rig basis (yaw + pitch) so the camera's rotation is preserved.
	var pitch = rig.get("pitch_node")
	if pitch is Node3D:
		basis = (pitch as Node3D).global_transform.basis
	elif rig is Node3D:
		basis = (rig as Node3D).global_transform.basis

	var c: DeathCameraConstraint = DeathCameraConstraint.new()
	c.set_locked_transform(Transform3D(basis, pos))
	c.aim_trait.target_offset = Vector3(0.0, 1.5, 0.0)
	c.aim_trait.tracking_response = 18.0
	c.disable_camera_controls = true
	c.constraint_priority = 9999
	_configure_death_camera_fov(c, rig, player)
	return c


func _add_constraint_to_scene(constraint: Node) -> void:
	if constraint == null:
		return
	if get_tree() != null and get_tree().current_scene != null:
		get_tree().current_scene.add_child(constraint)
	else:
		add_child(constraint)


func _get_or_create_fader(player: Node) -> Node:
	if player == null or get_tree() == null:
		return null

	var existing = get_tree().get_nodes_in_group("ScreenFader")
	if existing != null and existing.size() > 0:
		return existing[0]

	var fader = ScreenFader.new()
	fader.add_to_group("ScreenFader")

	var vp = null
	if player.has_method("get_viewport"):
		vp = player.get_viewport()
	if vp != null:
		vp.add_child(fader)
	elif get_tree().current_scene != null:
		get_tree().current_scene.add_child(fader)
	else:
		add_child(fader)

	return fader

@tool
extends Area3D

const SIZE_BASE_POSITION_META: StringName = &"_uniform_size_base_position"
const SIZE_BASE_SCALE_META: StringName = &"_uniform_size_base_scale"

enum TrajectoryAimOrigin {
	SPRING_ROOT,
	PLAYER_POSITION,
}

enum TrajectoryArcUpMode {
	PLAYER_GRAVITY_UP,
	SPRING_LOCAL_UP,
	WORLD_UP,
}

# ===========================================================
# SPRING CONFIG
# ===========================================================
@export_group("Spring")
## Master enable for this spring.
@export var active: bool = true

## Uniform scale applied to the spring mesh and trigger collision.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = max(value, 0.01)
		if is_node_ready():
			_apply_size_preview()

## Additional collision mask for dynamic physics objects that can be launched by this spring.
@export_flags_3d_physics var dynamic_object_collision_mask: int = 2

## If true, Sonic is snapped to the spring center when triggered.
@export var snap_to_center: bool = true

## Time after triggering during which the SAME body cannot re-trigger
## this exact spring again.
@export var rehit_cooldown: float = 0.15

# -----------------------------------------------------------
# IMPULSE
# -----------------------------------------------------------
@export_group("Impulse")

## Base strength of the spring impulse.
@export var strength: float = 35.0

## If true, completely overrides Sonic's velocity with the spring impulse.
## If false, uses one of the additive modes below.
@export var stop_momentum: bool = true

## Additive behavior when stop_momentum == false:
## 0 = IgnorePriorVertical        → keep lateral, kill old vertical, add launch
## 1 = FullyAdditiveWithMinLaunch → v += dir*strength, enforce min launch along dir
@export_enum("IgnorePriorVertical", "FullyAdditiveWithMinLaunch")
var additive_mode: int = 0

## For FullyAdditiveWithMinLaunch: minimum additive result before mirrored-bounce blending.
@export var min_additive_launch_speed: float = 10.0

## Blends an inward additive launch toward a mirrored bounce.
## 0.0 preserves additive behavior, 1.0 mirrors exactly, and values above 1.0 amplify the bounce.
@export_range(0.0, 4.0, 0.01, "or_greater")
var additive_mirrored_bounce_ratio: float = 0.0

## Maximum resulting speed along the launch direction. A value of 0.0 disables the cap.
@export var max_additive_launch_speed: float = 0.0

# -----------------------------------------------------------
# DIRECTION
# -----------------------------------------------------------
@export_group("Direction")

## Which axis of the spring node counts as the launch direction.
## Adjust in the inspector to match how your spring mesh is oriented.
@export_enum("PositiveY", "NegativeY", "PositiveZ", "NegativeZ")
var launch_axis: int = 0

## Uses a movable target marker to determine the spring's launch direction.
@export var use_trajectory_solver: bool = false

## Target marker used to calculate the launch direction and editor preview.
@export_node_path("Node3D") var trajectory_solver_path: NodePath = NodePath("TrajectorySolver")

## Identity visual pivot rotated toward the trajectory target for the editor preview.
@export_node_path("Node3D") var trajectory_visual_root_path: NodePath = NodePath("Mesh")

## Uses the spring root for parallel launches or the unsnapped player's position to converge on the target marker.
@export_enum("Spring Root", "Player Position") var trajectory_aim_origin: int = TrajectoryAimOrigin.SPRING_ROOT

@export_group("Trajectory Arc")
## Follows a generated arc to the trajectory marker when the trajectory solver is enabled. Authored splines take priority.
@export var trajectory_arc_enabled: bool = false

## Maximum arc offset from the straight marker trajectory.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m") var trajectory_arc_height: float = 10.0

## Selects which up direction defines the generated arc.
@export_enum("Player Gravity Up", "Spring Local Up", "World Up") var trajectory_arc_up_mode: int = TrajectoryArcUpMode.PLAYER_GRAVITY_UP

## Constant travel speed along the generated arc. A value of 0 uses the spring strength.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m/s") var trajectory_arc_speed: float = 0.0

## Allows movement input to release the player from the generated arc before reaching its destination.
@export var trajectory_arc_allow_input_cancel: bool = false

# -----------------------------------------------------------
# LOCKING / ALIGNMENT
# -----------------------------------------------------------
@export_group("Locking")
## Replaces prior action, movement, and spring alignment locks when activated.
@export var override_previous_lock_timers: bool = true

## How long to lock player steering movement (they still travel on the trajectory).
@export var movement_lock_time: float = 0.0

## How long to lock actions. Pressing any action while this is > 0
## will *break movement lock* but still not perform the action.
@export var action_lock_time: float = 0.0

## How long to keep the player under the spring's directional influence.
## The player pawn is initially aligned to the spring, and while this
## timer is > 0, their velocity is constrained along the launch direction.
@export var align_time: float = 0.0

## If true, movement lock ends immediately when the player touches ground.
@export var clear_movement_lock_on_ground: bool = true

## If true, action lock ends immediately when the player touches ground.
@export var clear_action_lock_on_ground: bool = true

## If true, while align_time > 0, the player's local sideways motion is locked
## (velocity is projected onto the launch direction each frame).
@export var lock_horizontal_during_align: bool = true

## How much sideways component is allowed to "leak through" while aligned.
## 0.0 = no sideways velocity (pure along-spring),
## 1.0 = full sideways preserved.
@export_range(0.0, 1.0)
var sideways_gravity_influence: float = 0.0

@export var align_model_during_spring: bool = true

@export_group("Downward Trajectory Torque")

## Enables trajectory-facing airborne torque for launches angled away from gravity-up.
@export var downward_trajectory_torque_enabled: bool = true

## Minimum launch angle away from gravity-up required to enter trajectory torque.
@export_range(0.0, 180.0, 0.1, "suffix:deg")
var downward_trajectory_min_angle_deg: float = 0.0

## Visual rotation speed used to point the player's up axis along the trajectory.
## A value of 0.0 snaps to the trajectory immediately.
@export_range(0.0, 2160.0, 1.0, "or_greater", "suffix:deg/s")
var downward_trajectory_align_speed_deg: float = 720.0

## Ends trajectory torque while rising when gravity-horizontal movement falls below this speed.
## Set to 0.0 to keep trajectory torque active at low horizontal speeds.
@export_range(0.0, 100.0, 0.1, "or_greater", "suffix:m/s")
var downward_trajectory_torque_min_horizontal_speed: float = 12.0

## Makes predicted landing alignment continue forward pitch after trajectory torque ends.
@export var downward_trajectory_landing_forward_pitch_enabled: bool = true

## Turns trajectory-torque facing toward gravity-down as the launch tilts downward.
@export var downward_trajectory_gravity_yaw_enabled: bool = true

## Strength of the gravity-down yaw preference.
@export_range(0.0, 2.0, 0.01, "or_greater")
var downward_trajectory_gravity_yaw_strength: float = 1.0

## Angle away from gravity-up where gravity-down yaw preference begins and parallel projections remain stable.
@export_range(0.0, 45.0, 0.1, "suffix:deg")
var downward_trajectory_gravity_yaw_safe_angle_deg: float = 3.0

## Angle away from gravity-up where gravity-down yaw preference reaches full strength.
@export_range(0.1, 180.0, 0.1, "suffix:deg")
var downward_trajectory_gravity_yaw_full_angle_deg: float = 90.0

@export_group("Detaching")

## If true, the spring detaches the player from the ground (air-style spring).
## If false, the player stays attached; the impulse is applied but adhesion remains.
@export var detach_from_ground: bool = true

@export_group("Spline Follow")
## Enable spline-based travel instead of a single impulse.
@export var spline_enabled: bool = false

## Path3D defining the spline to follow. Defaults to child "SplinePath" if present.
@export var spline_path: Path3D

## Travel speed along the spline.
@export var spline_speed: float = 40.0

## Detach from ground while following the spline.
@export var spline_detach_from_ground: bool = true

## If true, player input can cancel the spline early.
@export var spline_allow_input_cancel: bool = false

@export_group("Flight Interaction")
## Keeps an active flight ability running instead of forcing fall.
@export var preserve_active_flight: bool = false

## Flight time added when active flight is preserved.
@export var preserved_flight_time_bonus: float = 1.0

# -----------------------------------------------------------
# AUDIO
# -----------------------------------------------------------
@export_group("Audio")

## Optional dedicated SFX player (can be a child of the spring).
@export var sfx_player: AudioStreamPlayer3D

## One or more spring sounds to pick from.
@export var spring_sounds: Array[AudioStream] = []

var _last_sound_index: int = -1

var _body_cooldowns: Dictionary = {}  # instance_id -> remaining_time

@export_group("Homing Attack")
@export var homing_target_enabled: bool = true

@export_group("Mesh Bounce")
## Enables the Mesh node squash and bounce when the spring is triggered.
@export var mesh_bounce_enabled: bool = false

## Axis used for the bounce scale.
@export_enum("X", "Y", "Z")
var mesh_bounce_axis: int = 1

## Peak scale multiplier applied on the selected axis during the bounce.
@export_range(1.0, 3.0, 0.01)
var mesh_bounce_peak_scale: float = 1.7

## Time in seconds for the bounce to complete.
@export var mesh_bounce_duration: float = 0.18

var _mesh_bounce_root: Node3D
var _mesh_bounce_base_scale: Vector3 = Vector3.ONE
var _mesh_bounce_tween: Tween
var _trajectory_solver: Node3D = null
var _trajectory_visual_root: Node3D = null
var _instance_resources_localized: bool = false
var _trajectory_settings_repaired: bool = false
var _level_prepared: bool = false
var _gameplay_activated: bool = false
var _managed_preparation: bool = false

# ===========================================================
# LIFECYCLE
# ===========================================================
func _enter_tree() -> void:
	if Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(true)


func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_size_preview()
		_update_trajectory_solver_preview()
		set_process(true)
		return
	if not _level_prepared:
		prepare_for_level({})
	if not _gameplay_activated and not _managed_preparation:
		activate_for_gameplay({})


func prepare_for_level(context: Dictionary) -> bool:
	_managed_preparation = _managed_preparation or bool(context.get("managed", false))
	if _level_prepared:
		return true
	_apply_size_preview()
	_update_trajectory_solver_preview()
	set_process(false)
	if dynamic_object_collision_mask > 0:
		collision_mask = collision_mask | dynamic_object_collision_mask
	if spline_path == null:
		var default_path: Node = get_node_or_null("SplinePath")
		if default_path is Path3D:
			spline_path = default_path
	_mesh_bounce_root = get_node_or_null("Mesh") as Node3D
	if _mesh_bounce_root != null:
		_mesh_bounce_base_scale = _mesh_bounce_root.scale
	_level_prepared = true
	return true


func activate_for_gameplay(_context: Dictionary) -> bool:
	if _gameplay_activated:
		return true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_set_homing_target_registered(homing_target_enabled)
	_gameplay_activated = true
	_managed_preparation = false
	return true


func _apply_size_preview() -> void:
	var uniform_size: float = max(size, 0.01)
	_apply_size_to_node(get_node_or_null("CollisionShape3D") as Node3D, uniform_size)
	_apply_size_to_node(get_node_or_null("Mesh") as Node3D, uniform_size)
	if not Engine.is_editor_hint() and _mesh_bounce_root:
		_mesh_bounce_base_scale = _mesh_bounce_root.scale


func _apply_size_to_node(node: Node3D, uniform_size: float) -> void:
	if not node:
		return
	if not node.has_meta(SIZE_BASE_POSITION_META):
		node.set_meta(SIZE_BASE_POSITION_META, node.position)
	if not node.has_meta(SIZE_BASE_SCALE_META):
		node.set_meta(SIZE_BASE_SCALE_META, node.scale)
	var base_position_value: Variant = node.get_meta(SIZE_BASE_POSITION_META, node.position)
	var base_scale_value: Variant = node.get_meta(SIZE_BASE_SCALE_META, node.scale)
	if base_position_value is Vector3:
		node.position = (base_position_value as Vector3) * uniform_size
	if base_scale_value is Vector3:
		node.scale = (base_scale_value as Vector3) * uniform_size


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_set_homing_target_registered(false)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if not use_trajectory_solver and is_instance_valid(_trajectory_solver) and not _trajectory_solver.visible:
			return
		_update_trajectory_solver_preview()


func _set_homing_target_registered(registered: bool) -> void:
	if registered:
		if not is_in_group("HomingTarget"):
			add_to_group("HomingTarget")
		var mgr = get_node_or_null("/root/HomingTargetManager")
		if mgr and mgr.has_method("register"):
			mgr.register(self)
		return
	if is_in_group("HomingTarget"):
		remove_from_group("HomingTarget")
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("unregister"):
		mgr.unregister(self)


func on_homing_hit(player: Node, _jump_held: bool) -> bool:
	# Treat a homing hit like a body enter.
	if player is Node3D:
		_on_body_entered(player)
	# Signal to the player that the spring handled the impact (no homing pop).
	return true

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if use_trajectory_solver:
		_update_trajectory_solver_preview()
	if _body_cooldowns.is_empty():
		return

	var to_erase: Array = []
	for id in _body_cooldowns.keys():
		_body_cooldowns[id] -= delta
		if _body_cooldowns[id] <= 0.0:
			to_erase.append(id)

	for id in to_erase:
		_body_cooldowns.erase(id)

# ===========================================================
# SIGNAL HANDLER
# ===========================================================
func _on_body_entered(body: Node3D) -> void:
	if not active:
		return
	if not (body is CharacterBody3D) and not body.has_method("apply_spring_impulse"):
		return
	if _is_carried_object(body):
		return
	if body.has_method("cancel_homing_attack"):
		body.call("cancel_homing_attack", stop_momentum)
	if body.has_method("cancel_spline_spring"):
		body.call("cancel_spline_spring")

	# ---- per-body rehit cooldown ----
	var id: int = body.get_instance_id()
	var remaining: float = _body_cooldowns.get(id, 0.0)
	if remaining > 0.0:
		return  # still on cooldown – ignore this enter

	var used_spring: bool = false
	var player: Node3D = body
	if _try_start_spline(player):
		used_spring = true
	elif _try_start_trajectory_arc(player):
		used_spring = true
	elif body.has_method("apply_spring_impulse"):
		var launch_dir: Vector3 = _get_launch_direction(player)
		var launch_basis: Basis = _get_launch_basis(player)
		if override_previous_lock_timers and player.has_method("clear_object_lock_timers"):
			player.call("clear_object_lock_timers")
		player.apply_spring_impulse(
			global_transform.origin,
			launch_dir,
			strength,
			snap_to_center,
			stop_momentum,
			additive_mode,
			min_additive_launch_speed,
			additive_mirrored_bounce_ratio,
			max_additive_launch_speed,
			movement_lock_time,
			action_lock_time,
			align_time,
			launch_basis,
			clear_movement_lock_on_ground,
			clear_action_lock_on_ground,
			lock_horizontal_during_align,
			sideways_gravity_influence,
			detach_from_ground,
			align_model_during_spring,
			preserve_active_flight,
			preserved_flight_time_bonus,
			downward_trajectory_torque_enabled,
			downward_trajectory_min_angle_deg,
			downward_trajectory_align_speed_deg,
			downward_trajectory_gravity_yaw_enabled,
			downward_trajectory_gravity_yaw_strength,
			downward_trajectory_gravity_yaw_safe_angle_deg,
			downward_trajectory_gravity_yaw_full_angle_deg,
			downward_trajectory_torque_min_horizontal_speed,
			downward_trajectory_landing_forward_pitch_enabled
		)
		used_spring = true

	if not used_spring:
		return
	if player.has_method("register_combo_feat"):
		player.call("register_combo_feat", &"spring_launch", "Spring Launch", 100.0, 0.75)

	_trigger_mesh_bounce()
	_body_cooldowns[id] = rehit_cooldown
	_play_spring_sfx()


func _is_carried_object(body: Node) -> bool:
	if not body.has_method("is_carried"):
		return false
	return body.call("is_carried") == true


# ===========================================================
# DIRECTION
# ===========================================================
func _get_launch_direction(player: Node3D = null) -> Vector3:
	if use_trajectory_solver:
		var trajectory_direction: Vector3 = _get_trajectory_direction_world(player)
		if trajectory_direction.length_squared() > 0.000001:
			return trajectory_direction

	var root_basis: Basis = global_transform.basis.orthonormalized()
	var direction: Vector3 = root_basis * _get_launch_axis_local()
	if direction.length_squared() <= 0.000001:
		return Vector3.UP
	return direction.normalized()


func _get_launch_basis(player: Node3D = null) -> Basis:
	var root_basis: Basis = global_transform.basis.orthonormalized()
	var launch_direction: Vector3 = _get_launch_direction(player)
	return _build_player_launch_basis(launch_direction, root_basis)


func _build_player_launch_basis(launch_direction: Vector3, root_basis: Basis) -> Basis:
	var launch_up: Vector3 = launch_direction.normalized()
	if launch_up.length_squared() <= 0.000001:
		launch_up = Vector3.UP

	var launch_forward: Vector3 = -root_basis.z
	launch_forward -= launch_up * launch_forward.dot(launch_up)
	if launch_forward.length_squared() <= 0.000001:
		var reference_right: Vector3 = root_basis.x
		reference_right -= launch_up * reference_right.dot(launch_up)
		if reference_right.length_squared() <= 0.000001:
			reference_right = Vector3.RIGHT if abs(launch_up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			reference_right -= launch_up * reference_right.dot(launch_up)
		reference_right = reference_right.normalized()
		launch_forward = launch_up.cross(reference_right)
	launch_forward = launch_forward.normalized()
	var launch_right: Vector3 = launch_forward.cross(launch_up).normalized()
	launch_forward = launch_up.cross(launch_right).normalized()
	return Basis(launch_right, launch_up, -launch_forward).orthonormalized()


func _get_trajectory_alignment_basis() -> Basis:
	var trajectory_direction: Vector3 = _calculate_trajectory_direction_world(null, _get_trajectory_arc_enabled())
	if trajectory_direction.length_squared() <= 0.000001:
		return Basis.IDENTITY
	var root_basis: Basis = global_transform.basis.orthonormalized()
	var target_local: Vector3 = root_basis.inverse() * trajectory_direction
	var launch_axis_local: Vector3 = _get_launch_axis_local()
	return Basis(Quaternion(launch_axis_local, target_local.normalized()))


func _get_trajectory_direction_world(player: Node3D = null, include_arc: bool = false) -> Vector3:
	_resolve_trajectory_nodes()
	return _calculate_trajectory_direction_world(player, include_arc)


func _calculate_trajectory_direction_world(player: Node3D, include_arc: bool) -> Vector3:
	if _trajectory_solver == null:
		return Vector3.ZERO
	var direction: Vector3 = _get_trajectory_displacement(player)
	if include_arc and direction.length_squared() > 0.000001:
		direction += _get_trajectory_arc_up(player) * _get_trajectory_arc_height() * 4.0
	if direction.length_squared() <= 0.000001:
		return Vector3.ZERO
	return direction.normalized()


func _get_trajectory_start_position(player: Node3D) -> Vector3:
	if not snap_to_center and player:
		return player.global_position
	return global_position


func _get_trajectory_displacement(player: Node3D) -> Vector3:
	if not _trajectory_solver:
		return Vector3.ZERO
	var aim_origin: Vector3 = global_position
	if _get_trajectory_aim_origin() == TrajectoryAimOrigin.PLAYER_POSITION and not snap_to_center and player:
		aim_origin = player.global_position
	return _trajectory_solver.global_position - aim_origin


func _get_trajectory_arc_up(player: Node) -> Vector3:
	var arc_up: Vector3 = Vector3.UP
	var arc_up_mode: int = _get_trajectory_arc_up_mode()
	if arc_up_mode == TrajectoryArcUpMode.SPRING_LOCAL_UP:
		arc_up = global_transform.basis.y
	elif arc_up_mode == TrajectoryArcUpMode.PLAYER_GRAVITY_UP:
		if player and player.has_method("get_gravity_up"):
			var gravity_up_value: Variant = player.call("get_gravity_up")
			if gravity_up_value is Vector3:
				arc_up = gravity_up_value as Vector3
	if arc_up.length_squared() <= 0.000001:
		arc_up = Vector3.UP
	return arc_up.normalized()


func _get_launch_axis_local() -> Vector3:
	match launch_axis:
		1:
			return Vector3.DOWN
		2:
			return Vector3.BACK
		3:
			return Vector3.FORWARD
	return Vector3.UP


func _resolve_trajectory_nodes() -> void:
	_repair_trajectory_settings()
	trajectory_solver_path = _get_local_node_path_or_fallback(
		trajectory_solver_path,
		NodePath("TrajectorySolver")
	)
	trajectory_visual_root_path = _get_local_node_path_or_fallback(
		trajectory_visual_root_path,
		NodePath("Mesh")
	)
	_trajectory_solver = _resolve_local_trajectory_node(trajectory_solver_path, NodePath("TrajectorySolver"))
	_trajectory_visual_root = _resolve_local_trajectory_node(trajectory_visual_root_path, NodePath("Mesh"))
	_localize_instance_resources()


func _repair_trajectory_settings() -> void:
	if _trajectory_settings_repaired:
		return
	_get_trajectory_aim_origin()
	_get_trajectory_arc_enabled()
	_get_trajectory_arc_height()
	_get_trajectory_arc_up_mode()
	_get_trajectory_arc_speed()
	_get_trajectory_arc_allow_input_cancel()
	_trajectory_settings_repaired = true


func _get_trajectory_aim_origin() -> int:
	var value: Variant = get("trajectory_aim_origin")
	if value is int:
		var aim_origin: int = int(value)
		if aim_origin >= TrajectoryAimOrigin.SPRING_ROOT and aim_origin <= TrajectoryAimOrigin.PLAYER_POSITION:
			return aim_origin
	trajectory_aim_origin = TrajectoryAimOrigin.SPRING_ROOT
	return TrajectoryAimOrigin.SPRING_ROOT


func _get_trajectory_arc_enabled() -> bool:
	var value: Variant = get("trajectory_arc_enabled")
	if value is bool:
		return bool(value)
	trajectory_arc_enabled = false
	return false


func _get_trajectory_arc_height() -> float:
	var value: Variant = get("trajectory_arc_height")
	if value is float or value is int:
		return max(float(value), 0.0)
	trajectory_arc_height = 10.0
	return trajectory_arc_height


func _get_trajectory_arc_up_mode() -> int:
	var value: Variant = get("trajectory_arc_up_mode")
	if value is int:
		var up_mode: int = int(value)
		if up_mode >= TrajectoryArcUpMode.PLAYER_GRAVITY_UP and up_mode <= TrajectoryArcUpMode.WORLD_UP:
			return up_mode
	trajectory_arc_up_mode = TrajectoryArcUpMode.PLAYER_GRAVITY_UP
	return TrajectoryArcUpMode.PLAYER_GRAVITY_UP


func _get_trajectory_arc_speed() -> float:
	var value: Variant = get("trajectory_arc_speed")
	if value is float or value is int:
		return max(float(value), 0.0)
	trajectory_arc_speed = 0.0
	return trajectory_arc_speed


func _get_trajectory_arc_allow_input_cancel() -> bool:
	var value: Variant = get("trajectory_arc_allow_input_cancel")
	if value is bool:
		return bool(value)
	trajectory_arc_allow_input_cancel = false
	return false


func _get_local_node_path_or_fallback(node_path: NodePath, fallback_path: NodePath) -> NodePath:
	var resolved_node: Node = get_node_or_null(node_path)
	if resolved_node and resolved_node != self and is_ancestor_of(resolved_node):
		return node_path
	return fallback_path


func _resolve_local_trajectory_node(node_path: NodePath, fallback_path: NodePath) -> Node3D:
	var resolved_node: Node3D = get_node_or_null(node_path) as Node3D
	if resolved_node and resolved_node != self and is_ancestor_of(resolved_node):
		return resolved_node
	return get_node_or_null(fallback_path) as Node3D


func _localize_instance_resources() -> void:
	if _instance_resources_localized:
		return
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape and collision_shape.shape and not collision_shape.shape.resource_local_to_scene:
		var local_shape: Shape3D = collision_shape.shape.duplicate() as Shape3D
		if local_shape:
			local_shape.resource_local_to_scene = true
			collision_shape.shape = local_shape
	var default_spline: Path3D = get_node_or_null("SplinePath") as Path3D
	if default_spline and default_spline.curve and not default_spline.curve.resource_local_to_scene:
		var local_curve: Curve3D = default_spline.curve.duplicate() as Curve3D
		if local_curve:
			local_curve.resource_local_to_scene = true
			default_spline.curve = local_curve
	_instance_resources_localized = true


func _update_trajectory_solver_preview() -> void:
	_resolve_trajectory_nodes()
	if _trajectory_solver != null:
		var show_solver: bool = Engine.is_editor_hint() and use_trajectory_solver
		if _trajectory_solver.visible != show_solver:
			_trajectory_solver.visible = show_solver
	if _trajectory_visual_root == null:
		return
	var visual_scale: Vector3 = _trajectory_visual_root.scale
	var preview_basis: Basis = _get_trajectory_alignment_basis() if use_trajectory_solver else Basis.IDENTITY
	var visual_basis: Basis = preview_basis.scaled(visual_scale)
	if _trajectory_visual_root.basis != visual_basis:
		_trajectory_visual_root.basis = visual_basis


func _try_start_trajectory_arc(player: Node3D) -> bool:
	if not _get_trajectory_arc_enabled() or not use_trajectory_solver:
		return false
	if not player or not player.has_method("start_spline_spring"):
		return false
	_resolve_trajectory_nodes()
	if not _trajectory_solver:
		return false
	var travel_speed: float = _get_trajectory_arc_speed()
	if travel_speed <= 0.0:
		travel_speed = strength
	travel_speed = max(travel_speed, 0.0)
	if travel_speed <= 0.001:
		return false
	var arc_path: Path3D = _create_trajectory_arc_path(player)
	if not arc_path:
		return false
	if override_previous_lock_timers and player.has_method("clear_object_lock_timers"):
		player.call("clear_object_lock_timers")
	player.start_spline_spring(
		arc_path,
		travel_speed,
		align_model_during_spring,
		detach_from_ground,
		_get_trajectory_arc_allow_input_cancel(),
		action_lock_time,
		Vector3.ZERO,
		&"CMD_SPRING",
		movement_lock_time,
		clear_movement_lock_on_ground,
		clear_action_lock_on_ground
	)
	return true


func _create_trajectory_arc_path(player: Node3D) -> Path3D:
	var start_position: Vector3 = _get_trajectory_start_position(player)
	var displacement: Vector3 = _get_trajectory_displacement(player)
	if displacement.length_squared() <= 0.000001:
		return null
	var arc_up: Vector3 = _get_trajectory_arc_up(player)
	var control_offset: Vector3 = displacement * 0.5
	control_offset += arc_up * _get_trajectory_arc_height() * 2.0

	var arc_path: Path3D = Path3D.new()
	arc_path.name = "SpringTrajectoryArc"
	arc_path.set_meta(&"runtime_trajectory_arc", true)
	var path_parent: Node = get_tree().current_scene
	if not path_parent:
		path_parent = self
	path_parent.add_child(arc_path)
	arc_path.global_transform = Transform3D(Basis.IDENTITY, start_position)

	var curve: Curve3D = Curve3D.new()
	var start_out_handle: Vector3 = control_offset * (2.0 / 3.0)
	var target_in_handle: Vector3 = (control_offset - displacement) * (2.0 / 3.0)
	curve.add_point(Vector3.ZERO, Vector3.ZERO, start_out_handle)
	curve.add_point(displacement, target_in_handle, Vector3.ZERO)
	arc_path.curve = curve
	return arc_path


func _try_start_spline(player: Node) -> bool:
	if not spline_enabled:
		return false
	if spline_path == null or spline_path.curve == null:
		return false
	if not player.has_method("start_spline_spring"):
		return false
	if spline_path.curve.get_baked_length() <= 0.001:
		return false
	if override_previous_lock_timers and player.has_method("clear_object_lock_timers"):
		player.call("clear_object_lock_timers")

	player.start_spline_spring(
		spline_path,
		spline_speed,
		align_model_during_spring,
		spline_detach_from_ground,
		spline_allow_input_cancel,
		action_lock_time,
		Vector3.ZERO,
		&"CMD_SPRING",
		movement_lock_time,
		clear_movement_lock_on_ground,
		clear_action_lock_on_ground
	)
	return true


func _trigger_mesh_bounce() -> void:
	if not mesh_bounce_enabled or _mesh_bounce_root == null:
		return
	if mesh_bounce_duration <= 0.0:
		_mesh_bounce_root.scale = _mesh_bounce_base_scale
		return
	if _mesh_bounce_tween != null:
		_mesh_bounce_tween.kill()
		_mesh_bounce_tween = null

	_set_mesh_bounce_progress(0.0)
	_mesh_bounce_tween = create_tween()
	_mesh_bounce_tween.tween_method(_set_mesh_bounce_progress, 0.0, 1.0, mesh_bounce_duration)
	_mesh_bounce_tween.finished.connect(_on_mesh_bounce_finished)


func _set_mesh_bounce_progress(progress: float) -> void:
	if _mesh_bounce_root == null:
		return

	var bounce_t: float = clamp(progress, 0.0, 1.0)
	var peak_scale: float = max(mesh_bounce_peak_scale, 1.0)
	var peak_offset: float = peak_scale - 1.0
	var axis_scale: float = 1.0
	var attack_ratio: float = 0.14

	if bounce_t <= attack_ratio:
		var attack_t: float = bounce_t / max(attack_ratio, 0.001)
		axis_scale = lerp(1.0, peak_scale, sin(attack_t * PI * 0.5))
	else:
		var settle_t: float = (bounce_t - attack_ratio) / max(1.0 - attack_ratio, 0.001)
		var decay: float = 4.5
		var frequency: float = 2.35
		axis_scale = 1.0 + peak_offset * exp(-decay * settle_t) * cos(frequency * PI * settle_t)

	var scale: Vector3 = _mesh_bounce_base_scale

	match mesh_bounce_axis:
		0:
			scale.x = _mesh_bounce_base_scale.x * axis_scale
		1:
			scale.y = _mesh_bounce_base_scale.y * axis_scale
		2:
			scale.z = _mesh_bounce_base_scale.z * axis_scale
		_:
			scale.y = _mesh_bounce_base_scale.y * axis_scale

	_mesh_bounce_root.scale = scale


func _on_mesh_bounce_finished() -> void:
	_mesh_bounce_tween = null
	if _mesh_bounce_root != null:
		_mesh_bounce_root.scale = _mesh_bounce_base_scale


# ===========================================================
# AUDIO
# ===========================================================
func _play_spring_sfx() -> void:
	if sfx_player == null or spring_sounds.is_empty():
		return

	_last_sound_index = _play_random_sfx_from_list(
		sfx_player,
		spring_sounds,
		_last_sound_index,
		true
	)

func _play_random_sfx_from_list(
	player: AudioStreamPlayer3D,
	sounds: Array[AudioStream],
	last_index: int,
	avoid_repeat: bool = true
) -> int:
	if player == null or sounds.is_empty():
		return last_index

	var idx: int = randi_range(0, sounds.size() - 1)

	if avoid_repeat and sounds.size() > 1 and idx == last_index:
		idx = (idx + 1) % sounds.size()

	player.stream = sounds[idx]
	player.play()
	return idx

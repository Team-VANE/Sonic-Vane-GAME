@tool
extends Area3D

enum SwingDirection {
	UNDER,
	OVER,
}

enum LaunchSpeedMode {
	MATCH_INCOMING_SPEED,
	FIXED_SPEED,
}

enum LaunchAimOrigin {
	PLAYER_GRIP,
	BAR_ROOT,
}

enum VerticalArcUpMode {
	PLAYER_GRAVITY_UP,
	BAR_LOCAL_UP,
	WORLD_UP,
}

@export_group("Vault Bar")
## Enables player attachment and homing targeting.
@export var active: bool = true
## Total usable length of the bar along its local X axis.
@export_range(0.5, 100.0, 0.1, "or_greater", "suffix:m") var bar_length: float = 8.0
## Radius used by the bar mesh and end caps.
@export_range(0.05, 5.0, 0.05, "or_greater", "suffix:m") var bar_radius: float = 0.15
## Radius used by the attachment collision around the bar.
@export_range(0.05, 5.0, 0.05, "or_greater", "suffix:m") var collision_radius: float = 0.45
## Full rotations completed after the first launch-angle pass.
@export_range(0, 20, 1, "or_greater") var spins_before_launch: int = 1
## Selects backflip-style under swings or front-flip-style over swings. Opposite entries reverse the world rotation.
@export_enum("Under", "Over") var swing_direction: int = SwingDirection.UNDER
## Uses Rotation Speed instead of deriving swing speed from the upcoming launch strength.
@export var manual_swing_speed_enabled: bool = false
## Constant scripted rotation speed used when Manual Swing Speed is enabled.
@export_range(1.0, 2160.0, 1.0, "or_greater", "suffix:deg/s") var rotation_speed_deg: float = 540.0
## Degrees per second generated for each unit of upcoming launch strength while Manual Swing Speed is disabled.
@export_range(0.01, 100.0, 0.01, "or_greater") var automatic_swing_speed_multiplier: float = 10.0
## Delay before the same player can attach to this bar again.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var rehit_cooldown: float = 0.25

@export_group("Launch")
## Chooses between clamped incoming speed and a fixed launch speed.
@export_enum("Match Incoming Speed", "Fixed Speed") var launch_speed_mode: int = LaunchSpeedMode.MATCH_INCOMING_SPEED
## Launch speed used by Fixed Speed mode.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m/s") var fixed_launch_speed: float = 55.0
## Multiplies incoming speed before applying the Match Incoming Speed limits without altering launch direction.
@export_range(0.0, 10.0, 0.01, "or_greater") var incoming_to_outgoing_speed_ratio: float = 1.0
## Minimum launch speed used by Match Incoming Speed mode.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m/s") var minimum_launch_impulse: float = 35.0
## Maximum launch speed used by Match Incoming Speed mode.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m/s") var maximum_launch_impulse: float = 120.0
## Marker targeted by the primary free-launch trajectory.
@export_node_path("Node3D") var launch_direction_marker_path: NodePath = NodePath("LaunchDirection")
## Local launch direction used when the direction marker is unavailable.
@export var fallback_launch_direction: Vector3 = Vector3(0.0, 1.0, -1.0)
## Uses the player's grip point to converge on the marker or the bar root to give every grip point a parallel trajectory.
@export_enum("Player Grip", "Bar Root") var launch_aim_origin: int = LaunchAimOrigin.PLAYER_GRIP
## Scales launch direction along the bar. 0 constrains launch to the swing plane, 1 aims exactly at the marker, and values above 1 exaggerate lateral travel.
@export_range(0.0, 2.0, 0.01, "or_greater") var lateral_trajectory_influence: float = 1.0
## Uses a separate free-launch direction when entry travel opposes the primary launch direction.
@export var opposite_entry_uses_separate_launch_direction: bool = false
## Marker that defines the free-launch direction for an opposite entry.
@export_node_path("Node3D") var opposite_launch_direction_marker_path: NodePath = NodePath("OppositeLaunchDirection")
## Local opposite-entry launch direction used when its marker is unavailable.
@export var fallback_opposite_launch_direction: Vector3 = Vector3(0.0, 1.0, 1.0)

@export_group("Vertical Arc")
## Follows a generated arc to the effective launch-marker destination. Authored launch splines take priority.
@export var vertical_arc_enabled: bool = false
## Maximum arc offset from the straight marker trajectory.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m") var vertical_arc_height: float = 10.0
## Selects which up direction defines the vertical arc.
@export_enum("Player Gravity Up", "Bar Local Up", "World Up") var vertical_arc_up_mode: int = VerticalArcUpMode.PLAYER_GRAVITY_UP

@export_group("Locking")
## Replaces prior action, movement, and spring alignment locks on capture and launch.
@export var override_previous_lock_timers: bool = true
## Duration that steering movement remains locked after launch.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var movement_lock_time: float = 0.35
## Duration that player actions remain locked after launch.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var action_lock_time: float = 0.35
## Duration that launch velocity remains constrained to the launch direction.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var align_time: float = 0.0

@export_group("Spline Follow")
## Uses the configured spline instead of a free launch impulse.
@export var spline_enabled: bool = false
## Path followed after launch. The child SplinePath is used when unset.
@export var spline_path: Path3D
## Travel speed used while following the launch spline.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m/s") var spline_speed: float = 55.0

@export_group("Homing Attack")
## Enables homing attack targeting along the full bar length.
@export var homing_target_enabled: bool = true
## Maximum distance from the player for homing targeting. Zero uses the player targeting range.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var homing_target_max_distance: float = 0.0

@export_group("Animations")
## Holding animation requested for an under swing.
@export var under_animation_name: StringName = &"VaultBar_Swing_Under"
## Holding animation requested for an over swing.
@export var over_animation_name: StringName = &"VaultBar_Swing_Over"

## Collision shape spanning the usable attachment length.
@onready var _collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
## Cylindrical visual representing the horizontal bar.
@onready var _bar_mesh: MeshInstance3D = get_node_or_null("Model/Bar") as MeshInstance3D
## Visual cap placed at the negative end of the bar.
@onready var _left_cap: MeshInstance3D = get_node_or_null("Model/LeftCap") as MeshInstance3D
## Visual cap placed at the positive end of the bar.
@onready var _right_cap: MeshInstance3D = get_node_or_null("Model/RightCap") as MeshInstance3D
## Marker used to derive the free-launch direction.
@onready var _launch_direction_marker: Node3D = get_node_or_null(launch_direction_marker_path) as Node3D
## Editor-only visual for the launch direction marker.
@onready var _launch_direction_visual: Node3D = get_node_or_null("LaunchDirection/Preview") as Node3D
## Marker used to derive the opposite-entry free-launch direction.
@onready var _opposite_launch_direction_marker: Node3D = get_node_or_null(opposite_launch_direction_marker_path) as Node3D
## Editor-only visual for the opposite-entry launch direction marker.
@onready var _opposite_launch_direction_visual: Node3D = get_node_or_null("OppositeLaunchDirection/Preview") as Node3D
## Sound player used when a player successfully attaches to the bar.
@onready var _touch_sfx: AudioStreamPlayer3D = get_node_or_null("TouchSFX") as AudioStreamPlayer3D
## Sound player used for non-final launch-angle passes.
@onready var _rotation_sfx: AudioStreamPlayer3D = get_node_or_null("RotationSFX") as AudioStreamPlayer3D
## Sound player used for the final launch.
@onready var _jump_sfx: AudioStreamPlayer3D = get_node_or_null("JumpSFX") as AudioStreamPlayer3D

var _sessions: Dictionary = {}
var _body_cooldowns: Dictionary = {}
var _instance_resources_localized: bool = false
var _level_prepared: bool = false
var _gameplay_activated: bool = false
var _managed_preparation: bool = false

static var _runtime_shape_cache: Dictionary = {}
static var _runtime_mesh_cache: Dictionary = {}


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(true)


func _ready() -> void:
	if Engine.is_editor_hint():
		_resolve_nodes()
		_update_geometry()
		return
	if not _level_prepared:
		prepare_for_level({})
	if not _gameplay_activated and not _managed_preparation:
		activate_for_gameplay({})


func prepare_for_level(context: Dictionary) -> bool:
	_managed_preparation = _managed_preparation or bool(context.get("managed", false))
	if _level_prepared:
		return true
	_resolve_nodes()
	_update_geometry()
	if not spline_path:
		spline_path = get_node_or_null("SplinePath") as Path3D
	_level_prepared = true
	return true


func activate_for_gameplay(_context: Dictionary) -> bool:
	if _gameplay_activated:
		return true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_set_homing_target_registered(active and homing_target_enabled)
	_gameplay_activated = true
	_managed_preparation = false
	return true


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_set_homing_target_registered(false)
	var session_ids: Array = _sessions.keys()
	for session_id in session_ids:
		var session: Dictionary = _sessions.get(session_id, {})
		var player: Node = session.get("player") as Node
		if player and is_instance_valid(player) and player.has_method("cancel_vault_bar"):
			player.call("cancel_vault_bar", self)
	_sessions.clear()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_resolve_nodes()
	_update_geometry()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _body_cooldowns.is_empty():
		return
	var expired_ids: Array = []
	for body_id in _body_cooldowns.keys():
		var remaining: float = float(_body_cooldowns.get(body_id, 0.0)) - delta
		if remaining <= 0.0:
			expired_ids.append(body_id)
		else:
			_body_cooldowns[body_id] = remaining
	for body_id in expired_ids:
		_body_cooldowns.erase(body_id)


func _resolve_nodes() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_bar_mesh = get_node_or_null("Model/Bar") as MeshInstance3D
	_left_cap = get_node_or_null("Model/LeftCap") as MeshInstance3D
	_right_cap = get_node_or_null("Model/RightCap") as MeshInstance3D
	launch_direction_marker_path = _get_local_node_path_or_fallback(
		launch_direction_marker_path,
		NodePath("LaunchDirection")
	)
	opposite_launch_direction_marker_path = _get_local_node_path_or_fallback(
		opposite_launch_direction_marker_path,
		NodePath("OppositeLaunchDirection")
	)
	_launch_direction_marker = _resolve_local_marker(launch_direction_marker_path, NodePath("LaunchDirection"))
	_launch_direction_visual = _get_marker_preview(_launch_direction_marker)
	_opposite_launch_direction_marker = _resolve_local_marker(
		opposite_launch_direction_marker_path,
		NodePath("OppositeLaunchDirection")
	)
	_opposite_launch_direction_visual = _get_marker_preview(_opposite_launch_direction_marker)
	_touch_sfx = get_node_or_null("TouchSFX") as AudioStreamPlayer3D
	_rotation_sfx = get_node_or_null("RotationSFX") as AudioStreamPlayer3D
	_jump_sfx = get_node_or_null("JumpSFX") as AudioStreamPlayer3D
	_localize_instance_resources()


func _get_local_node_path_or_fallback(node_path: NodePath, fallback_path: NodePath) -> NodePath:
	var resolved_node: Node = get_node_or_null(node_path)
	if resolved_node and resolved_node != self and is_ancestor_of(resolved_node):
		return node_path
	return fallback_path


func _resolve_local_marker(marker_path: NodePath, fallback_path: NodePath) -> Node3D:
	var marker: Node3D = get_node_or_null(marker_path) as Node3D
	if marker and marker != self and is_ancestor_of(marker):
		return marker
	return get_node_or_null(fallback_path) as Node3D


func _get_marker_preview(marker: Node3D) -> Node3D:
	if not marker:
		return null
	return marker.get_node_or_null("Preview") as Node3D


func _localize_instance_resources() -> void:
	if _instance_resources_localized:
		return
	if _collision_shape and _collision_shape.shape and not _collision_shape.shape.resource_local_to_scene:
		var local_shape: Shape3D = _get_prepared_collision_shape(_collision_shape.shape)
		if local_shape:
			_collision_shape.shape = local_shape
	if _bar_mesh and _bar_mesh.mesh and not _bar_mesh.mesh.resource_local_to_scene:
		var local_mesh: Mesh = _get_prepared_bar_mesh(_bar_mesh.mesh)
		if local_mesh:
			_bar_mesh.mesh = local_mesh
	var default_spline: Path3D = get_node_or_null("SplinePath") as Path3D
	if default_spline and default_spline.curve and not default_spline.curve.resource_local_to_scene:
		var local_curve: Curve3D = default_spline.curve.duplicate() as Curve3D
		if local_curve:
			local_curve.resource_local_to_scene = true
			default_spline.curve = local_curve
	_instance_resources_localized = true


func _get_prepared_collision_shape(source: Shape3D) -> Shape3D:
	if Engine.is_editor_hint():
		var editor_shape: Shape3D = source.duplicate() as Shape3D
		if editor_shape:
			editor_shape.resource_local_to_scene = true
		return editor_shape
	var length_used: float = max(bar_length, 0.5)
	var radius_used: float = max(collision_radius, 0.05)
	var cache_key: String = "%d|%.4f|%.4f" % [source.get_instance_id(), length_used, radius_used]
	if LevelPreparationManager.is_cache_enabled():
		var cached_value: Variant = _runtime_shape_cache.get(cache_key)
		if cached_value is Shape3D:
			return cached_value as Shape3D
	var prepared_shape: Shape3D = source.duplicate() as Shape3D
	if prepared_shape is BoxShape3D:
		(prepared_shape as BoxShape3D).size = Vector3(length_used, radius_used * 2.0, radius_used * 2.0)
	if LevelPreparationManager.is_cache_enabled():
		_runtime_shape_cache[cache_key] = prepared_shape
	return prepared_shape


func _get_prepared_bar_mesh(source: Mesh) -> Mesh:
	if Engine.is_editor_hint():
		var editor_mesh: Mesh = source.duplicate() as Mesh
		if editor_mesh:
			editor_mesh.resource_local_to_scene = true
		return editor_mesh
	var length_used: float = max(bar_length, 0.5)
	var radius_used: float = max(bar_radius, 0.05)
	var cache_key: String = "%d|%.4f|%.4f" % [source.get_instance_id(), length_used, radius_used]
	if LevelPreparationManager.is_cache_enabled():
		var cached_value: Variant = _runtime_mesh_cache.get(cache_key)
		if cached_value is Mesh:
			return cached_value as Mesh
	var prepared_mesh: Mesh = source.duplicate() as Mesh
	if prepared_mesh is CylinderMesh:
		var cylinder: CylinderMesh = prepared_mesh as CylinderMesh
		cylinder.height = length_used
		cylinder.top_radius = radius_used
		cylinder.bottom_radius = radius_used
	if LevelPreparationManager.is_cache_enabled():
		_runtime_mesh_cache[cache_key] = prepared_mesh
	return prepared_mesh


func _update_geometry() -> void:
	var length_used: float = max(bar_length, 0.5)
	var visual_radius_used: float = max(bar_radius, 0.05)
	var collision_radius_value: Variant = get("collision_radius")
	var collision_radius_used: float = 0.25
	if collision_radius_value is float or collision_radius_value is int:
		collision_radius_used = max(float(collision_radius_value), 0.05)
	if _collision_shape and _collision_shape.shape is BoxShape3D:
		var box_shape: BoxShape3D = _collision_shape.shape as BoxShape3D
		var collision_size: Vector3 = Vector3(length_used, collision_radius_used * 2.0, collision_radius_used * 2.0)
		if box_shape.size != collision_size:
			box_shape.size = collision_size
	if _bar_mesh and _bar_mesh.mesh is CylinderMesh:
		var cylinder_mesh: CylinderMesh = _bar_mesh.mesh as CylinderMesh
		if cylinder_mesh.height != length_used:
			cylinder_mesh.height = length_used
		if cylinder_mesh.top_radius != visual_radius_used:
			cylinder_mesh.top_radius = visual_radius_used
		if cylinder_mesh.bottom_radius != visual_radius_used:
			cylinder_mesh.bottom_radius = visual_radius_used
	var cap_scale: Vector3 = Vector3.ONE * visual_radius_used * 1.35
	if _left_cap:
		var left_position: Vector3 = Vector3(-length_used * 0.5, 0.0, 0.0)
		if _left_cap.position != left_position:
			_left_cap.position = left_position
		if _left_cap.scale != cap_scale:
			_left_cap.scale = cap_scale
	if _right_cap:
		var right_position: Vector3 = Vector3(length_used * 0.5, 0.0, 0.0)
		if _right_cap.position != right_position:
			_right_cap.position = right_position
		if _right_cap.scale != cap_scale:
			_right_cap.scale = cap_scale
	if _launch_direction_visual:
		var show_launch_preview: bool = Engine.is_editor_hint()
		if _launch_direction_visual.visible != show_launch_preview:
			_launch_direction_visual.visible = show_launch_preview
	if _opposite_launch_direction_visual:
		var show_opposite_preview: bool = Engine.is_editor_hint() and opposite_entry_uses_separate_launch_direction
		if _opposite_launch_direction_visual.visible != show_opposite_preview:
			_opposite_launch_direction_visual.visible = show_opposite_preview


func _set_homing_target_registered(registered: bool) -> void:
	var manager: Node = get_node_or_null("/root/HomingTargetManager")
	if registered:
		if not is_in_group("HomingTarget"):
			add_to_group("HomingTarget")
		if manager and manager.has_method("register"):
			manager.call("register", self)
		return
	if is_in_group("HomingTarget"):
		remove_from_group("HomingTarget")
	if manager and manager.has_method("unregister"):
		manager.call("unregister", self)


func _on_body_entered(body: Node3D) -> void:
	_try_attach_player(body)


func on_homing_hit(player: Node, _jump_held: bool) -> bool:
	if not active or not homing_target_enabled:
		return false
	if not (player is Node3D):
		return false
	return _try_attach_player(player as Node3D)


func _try_attach_player(player: Node3D) -> bool:
	if not active or not player or not is_instance_valid(player):
		return false
	if not player.has_method("begin_vault_bar"):
		return false
	var player_id: int = player.get_instance_id()
	if _sessions.has(player_id):
		return true
	if float(_body_cooldowns.get(player_id, 0.0)) > 0.0:
		return false

	var incoming_velocity: Vector3 = Vector3.ZERO
	var velocity_value: Variant = player.get("velocity")
	if velocity_value is Vector3:
		incoming_velocity = velocity_value as Vector3
	var grip_position: Vector3 = get_homing_target_position(player.global_position)
	if player.has_method("get_homing_attack_target_position"):
		var locked_position: Variant = player.call("get_homing_attack_target_position")
		if locked_position is Vector3:
			grip_position = get_homing_target_position(locked_position as Vector3)

	var incoming_speed: float = incoming_velocity.length()
	var launch_speed: float = _get_launch_speed(incoming_speed)
	var upcoming_launch_strength: float = _get_upcoming_launch_strength(launch_speed)
	var session_swing_speed_deg: float = _get_swing_speed_deg(upcoming_launch_strength)
	var start_angle: float = _get_entry_angle(player.global_position, grip_position, incoming_velocity)
	var primary_launch_direction: Vector3 = _get_launch_direction(grip_position, false, player)
	var opposite_entry: bool = _is_opposite_entry(
		incoming_velocity,
		primary_launch_direction,
		player
	)
	var use_opposite_launch_direction: bool = opposite_entry_uses_separate_launch_direction and opposite_entry
	var launch_direction: Vector3 = _get_launch_direction(grip_position, use_opposite_launch_direction, player)
	var rotation_sign: float = 1.0 if swing_direction == SwingDirection.UNDER else -1.0
	if opposite_entry:
		rotation_sign *= -1.0
	var facing_sign: float = -1.0 if opposite_entry else 1.0
	var launch_angle: float = _get_launch_rotation_angle(launch_direction, rotation_sign)
	var first_target_distance: float = fposmod((launch_angle - start_angle) * rotation_sign, TAU)
	var total_distance: float = first_target_distance + float(maxi(spins_before_launch, 0)) * TAU
	var next_target_distance: float = first_target_distance
	if next_target_distance <= 0.0001:
		next_target_distance = TAU
	var model_basis: Basis = _get_model_basis(start_angle, facing_sign)
	var animation_name: StringName = under_animation_name
	if swing_direction == SwingDirection.OVER:
		animation_name = over_animation_name

	var began: Variant = player.call("begin_vault_bar", self, grip_position, model_basis, animation_name)
	if began != true:
		return false
	if override_previous_lock_timers and player.has_method("clear_object_lock_timers"):
		player.call("clear_object_lock_timers")

	_sessions[player_id] = {
		"player": player,
		"grip_position": grip_position,
		"incoming_speed": incoming_speed,
		"launch_speed": launch_speed,
		"swing_speed_deg": session_swing_speed_deg,
		"use_opposite_launch_direction": use_opposite_launch_direction,
		"start_angle": start_angle,
		"rotation_sign": rotation_sign,
		"facing_sign": facing_sign,
		"travel_distance": 0.0,
		"total_distance": total_distance,
		"next_target_distance": next_target_distance,
	}
	_play_touch_sound()
	if total_distance <= 0.0001:
		_launch_player(player_id)
	return true


func update_vault_bar_player(player: Node, delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	var player_id: int = player.get_instance_id()
	if not _sessions.has(player_id):
		if player.has_method("cancel_vault_bar"):
			player.call("cancel_vault_bar", self)
		return
	if not active:
		_sessions.erase(player_id)
		if player.has_method("cancel_vault_bar"):
			player.call("cancel_vault_bar", self)
		return

	var session: Dictionary = _sessions[player_id]
	var previous_distance: float = float(session.get("travel_distance", 0.0))
	var total_distance: float = float(session.get("total_distance", 0.0))
	var session_swing_speed_deg: float = float(session.get("swing_speed_deg", max(rotation_speed_deg, 1.0)))
	var advance: float = deg_to_rad(max(session_swing_speed_deg, 1.0)) * max(delta, 0.0)
	var travel_distance: float = min(previous_distance + advance, total_distance)
	var next_target_distance: float = float(session.get("next_target_distance", TAU))
	while next_target_distance < total_distance - 0.0001 and next_target_distance <= travel_distance + 0.0001:
		if next_target_distance > previous_distance + 0.0001:
			_play_rotation_sound()
		next_target_distance += TAU

	var start_angle: float = float(session.get("start_angle", 0.0))
	var rotation_sign: float = float(session.get("rotation_sign", 1.0))
	var facing_sign: float = float(session.get("facing_sign", 1.0))
	var current_angle: float = start_angle + rotation_sign * travel_distance
	var grip_position: Vector3 = session.get("grip_position", global_position) as Vector3
	var posed: Variant = player.call(
		"set_vault_bar_pose",
		self,
		grip_position,
		_get_model_basis(current_angle, facing_sign)
	)
	if posed != true:
		_sessions.erase(player_id)
		return

	session["travel_distance"] = travel_distance
	session["next_target_distance"] = next_target_distance
	_sessions[player_id] = session
	if travel_distance >= total_distance - 0.0001:
		_launch_player(player_id)


func on_vault_bar_player_cancelled(player: Node) -> void:
	if not player:
		return
	_sessions.erase(player.get_instance_id())


func _launch_player(player_id: int) -> void:
	if not _sessions.has(player_id):
		return
	var session: Dictionary = _sessions[player_id]
	_sessions.erase(player_id)
	var player: Node = session.get("player") as Node
	if not player or not is_instance_valid(player):
		return

	var grip_position: Vector3 = session.get("grip_position", global_position) as Vector3
	var use_opposite_launch_direction: bool = bool(session.get("use_opposite_launch_direction", false))
	var launch_direction: Vector3 = _get_launch_direction(grip_position, use_opposite_launch_direction, player)
	var launch_speed: float = float(session.get(
		"launch_speed",
		_get_launch_speed(float(session.get("incoming_speed", 0.0)))
	))
	var launch_velocity: Vector3 = launch_direction * launch_speed
	var rotation_sign: float = float(session.get("rotation_sign", 1.0))
	var facing_sign: float = float(session.get("facing_sign", 1.0))
	var pitch_trick_command: StringName = &"Trick_Pitch_Back"
	if swing_direction == SwingDirection.OVER:
		pitch_trick_command = &"Trick_Pitch_Forward"
	var session_swing_speed_deg: float = float(session.get("swing_speed_deg", max(rotation_speed_deg, 1.0)))
	var angular_velocity: Vector3 = _get_bar_axis() * deg_to_rad(max(session_swing_speed_deg, 1.0)) * rotation_sign
	var launch_basis: Basis = _get_launch_basis(launch_direction, rotation_sign, facing_sign)
	var active_spline: Path3D = null
	var active_spline_speed: float = 0.0
	var spline_world_offset: Vector3 = Vector3.ZERO
	if _has_valid_launch_spline():
		active_spline = spline_path
		active_spline_speed = max(spline_speed, 0.0)
		var spline_start: Vector3 = spline_path.to_global(spline_path.curve.sample_baked(0.0))
		spline_world_offset = grip_position - spline_start
	elif vertical_arc_enabled and launch_speed > 0.001:
		active_spline = _create_vertical_arc_path(grip_position, use_opposite_launch_direction, player)
		if active_spline:
			active_spline_speed = launch_speed

	_body_cooldowns[player_id] = max(rehit_cooldown, 0.0)
	_play_jump_sound()
	if override_previous_lock_timers and player.has_method("clear_object_lock_timers"):
		player.call("clear_object_lock_timers")
	var launched: Variant = player.call(
		"launch_from_vault_bar",
		self,
		launch_velocity,
		angular_velocity,
		movement_lock_time,
		action_lock_time,
		align_time,
		launch_basis,
		active_spline,
		active_spline_speed,
		spline_world_offset,
		pitch_trick_command
	)
	if launched != true:
		if active_spline and active_spline.has_meta(&"runtime_trajectory_arc"):
			active_spline.queue_free()
		if player.has_method("cancel_vault_bar"):
			player.call("cancel_vault_bar", self)


func _get_launch_speed(incoming_speed: float) -> float:
	if launch_speed_mode == LaunchSpeedMode.FIXED_SPEED:
		return max(fixed_launch_speed, 0.0)
	var minimum_speed: float = max(minimum_launch_impulse, 0.0)
	var maximum_speed: float = max(maximum_launch_impulse, minimum_speed)
	var translated_speed: float = max(incoming_speed, 0.0) * max(incoming_to_outgoing_speed_ratio, 0.0)
	return clamp(translated_speed, minimum_speed, maximum_speed)


func _get_upcoming_launch_strength(launch_speed: float) -> float:
	if _has_valid_launch_spline():
		return max(spline_speed, 0.0)
	return max(launch_speed, 0.0)


func _get_swing_speed_deg(upcoming_launch_strength: float) -> float:
	if manual_swing_speed_enabled:
		return max(rotation_speed_deg, 1.0)
	return max(upcoming_launch_strength * max(automatic_swing_speed_multiplier, 0.01), 1.0)


func _has_valid_launch_spline() -> bool:
	if not spline_enabled or not spline_path or not spline_path.curve:
		return false
	return spline_speed > 0.0 and spline_path.curve.get_baked_length() > 0.001


func _get_entry_angle(entry_position: Vector3, grip_position: Vector3, incoming_velocity: Vector3) -> float:
	var radial_world: Vector3 = entry_position - grip_position
	var bar_axis: Vector3 = _get_bar_axis()
	radial_world -= bar_axis * radial_world.dot(bar_axis)
	if radial_world.length() < 0.001:
		radial_world = -incoming_velocity
		radial_world -= bar_axis * radial_world.dot(bar_axis)
	if radial_world.length() < 0.001:
		radial_world = -global_transform.basis.y
	return _get_swing_angle(radial_world)


func _get_swing_angle(world_direction: Vector3) -> float:
	var object_basis: Basis = global_transform.basis.orthonormalized()
	var local_direction: Vector3 = object_basis.inverse() * world_direction.normalized()
	local_direction.x = 0.0
	if local_direction.length() < 0.001:
		local_direction = Vector3.DOWN
	else:
		local_direction = local_direction.normalized()
	return atan2(-local_direction.z, -local_direction.y)


func _get_launch_rotation_angle(world_direction: Vector3, rotation_sign: float) -> float:
	var object_basis: Basis = global_transform.basis.orthonormalized()
	var local_direction: Vector3 = object_basis.inverse() * world_direction.normalized()
	local_direction.x = 0.0
	if local_direction.length() < 0.001:
		local_direction = Vector3.FORWARD
	else:
		local_direction = local_direction.normalized()
	var orbit_sign: float = signf(rotation_sign) if abs(rotation_sign) > 0.001 else 1.0
	local_direction *= orbit_sign
	return atan2(local_direction.y, -local_direction.z)


func _get_model_basis(angle: float, facing_sign: float) -> Basis:
	var object_basis: Basis = global_transform.basis.orthonormalized()
	var local_basis: Basis = Basis(Vector3.RIGHT, angle)
	if facing_sign < 0.0:
		local_basis *= Basis(Vector3.UP, PI)
	return (object_basis * local_basis).orthonormalized()


func _get_launch_direction(
	grip_position: Vector3,
	use_opposite_direction: bool = false,
	player: Node = null
) -> Vector3:
	if _has_valid_launch_spline():
		var curve: Curve3D = spline_path.curve
		var length: float = curve.get_baked_length()
		if length > 0.001:
			var first_point: Vector3 = spline_path.to_global(curve.sample_baked(0.0))
			var next_point: Vector3 = spline_path.to_global(curve.sample_baked(min(length, 0.25)))
			var tangent: Vector3 = next_point - first_point
			if tangent.length() > 0.001:
				return tangent.normalized()

	var selected_marker: Node3D = _get_launch_marker(use_opposite_direction)
	var direction: Vector3 = _get_free_launch_displacement(grip_position, use_opposite_direction)
	if vertical_arc_enabled and selected_marker and direction.length() > 0.001:
		direction += _get_vertical_arc_up(player) * max(vertical_arc_height, 0.0) * 4.0
	if direction.length() < 0.001:
		direction = global_transform.basis.y
	return direction.normalized()


func _get_launch_marker(use_opposite_direction: bool) -> Node3D:
	return _opposite_launch_direction_marker if use_opposite_direction else _launch_direction_marker


func _get_free_launch_displacement(grip_position: Vector3, use_opposite_direction: bool) -> Vector3:
	var selected_marker: Node3D = _get_launch_marker(use_opposite_direction)
	var selected_fallback: Vector3 = fallback_opposite_launch_direction if use_opposite_direction else fallback_launch_direction
	var displacement: Vector3 = Vector3.ZERO
	if selected_marker:
		var aim_origin: Vector3 = grip_position
		if launch_aim_origin == LaunchAimOrigin.BAR_ROOT:
			aim_origin = global_position
		displacement = selected_marker.global_position - aim_origin
	if displacement.length() < 0.001:
		displacement = global_transform.basis.orthonormalized() * selected_fallback
	var bar_axis: Vector3 = _get_bar_axis()
	var along_bar: Vector3 = bar_axis * displacement.dot(bar_axis)
	var swing_plane: Vector3 = displacement - along_bar
	return swing_plane + along_bar * max(lateral_trajectory_influence, 0.0)


func _get_vertical_arc_up(player: Node) -> Vector3:
	var arc_up: Vector3 = Vector3.UP
	if vertical_arc_up_mode == VerticalArcUpMode.BAR_LOCAL_UP:
		arc_up = global_transform.basis.y
	elif vertical_arc_up_mode == VerticalArcUpMode.PLAYER_GRAVITY_UP:
		arc_up = _get_player_gravity_up(player)
	if arc_up.length() < 0.001:
		arc_up = Vector3.UP
	return arc_up.normalized()


func _get_player_gravity_up(player: Node) -> Vector3:
	if player and player.has_method("get_gravity_up"):
		var gravity_up_value: Variant = player.call("get_gravity_up")
		if gravity_up_value is Vector3:
			var gravity_up: Vector3 = gravity_up_value as Vector3
			if gravity_up.length() >= 0.001:
				return gravity_up.normalized()
	return Vector3.UP


func _create_vertical_arc_path(
	grip_position: Vector3,
	use_opposite_direction: bool,
	player: Node
) -> Path3D:
	var selected_marker: Node3D = _get_launch_marker(use_opposite_direction)
	if not selected_marker:
		return null
	var displacement: Vector3 = _get_free_launch_displacement(grip_position, use_opposite_direction)
	if displacement.length() < 0.001:
		return null

	var arc_up: Vector3 = _get_vertical_arc_up(player)
	var control_offset: Vector3 = displacement * 0.5
	control_offset += arc_up * max(vertical_arc_height, 0.0) * 2.0

	var arc_path: Path3D = Path3D.new()
	arc_path.name = "VaultBarVerticalArc"
	arc_path.set_meta(&"runtime_trajectory_arc", true)
	var path_parent: Node = get_tree().current_scene
	if not path_parent:
		path_parent = self
	path_parent.add_child(arc_path)
	arc_path.global_transform = Transform3D(Basis.IDENTITY, grip_position)

	var curve: Curve3D = Curve3D.new()
	var start_out_handle: Vector3 = control_offset * (2.0 / 3.0)
	var target_in_handle: Vector3 = (control_offset - displacement) * (2.0 / 3.0)
	curve.add_point(Vector3.ZERO, Vector3.ZERO, start_out_handle)
	curve.add_point(displacement, target_in_handle, Vector3.ZERO)
	arc_path.curve = curve
	return arc_path


func _is_opposite_entry(
	incoming_velocity: Vector3,
	primary_launch_direction: Vector3,
	player: Node
) -> bool:
	var bar_axis: Vector3 = _get_bar_axis()
	var gravity_up: Vector3 = _get_player_gravity_up(player)
	var traversal_axis: Vector3 = bar_axis.cross(gravity_up)
	if traversal_axis.length() < 0.001:
		var incoming_swing_plane: Vector3 = incoming_velocity - bar_axis * incoming_velocity.dot(bar_axis)
		var primary_swing_plane: Vector3 = primary_launch_direction - bar_axis * primary_launch_direction.dot(bar_axis)
		if incoming_swing_plane.length() < 0.001 or primary_swing_plane.length() < 0.001:
			return false
		return incoming_swing_plane.normalized().dot(primary_swing_plane.normalized()) < 0.0
	traversal_axis = traversal_axis.normalized()
	var incoming_traversal_speed: float = incoming_velocity.dot(traversal_axis)
	var primary_traversal_direction: float = primary_launch_direction.dot(traversal_axis)
	if abs(incoming_traversal_speed) < 0.001 or abs(primary_traversal_direction) < 0.001:
		return false
	return incoming_traversal_speed * primary_traversal_direction < 0.0


func _get_launch_basis(launch_direction: Vector3, rotation_sign: float, facing_sign: float) -> Basis:
	var launch_angle: float = _get_launch_rotation_angle(launch_direction, rotation_sign)
	return _get_model_basis(launch_angle, facing_sign)


func _get_bar_axis() -> Vector3:
	var axis: Vector3 = global_transform.basis.x
	if axis.length() < 0.001:
		return Vector3.RIGHT
	return axis.normalized()


func _get_bar_endpoints() -> PackedVector3Array:
	var half_length: float = max(bar_length, 0.5) * 0.5
	return PackedVector3Array([
		to_global(Vector3(-half_length, 0.0, 0.0)),
		to_global(Vector3(half_length, 0.0, 0.0)),
	])


func get_homing_manager_positions(sample_spacing: float) -> Array[Vector3]:
	var endpoints: PackedVector3Array = _get_bar_endpoints()
	var start: Vector3 = endpoints[0]
	var end: Vector3 = endpoints[1]
	var length: float = start.distance_to(end)
	var spacing: float = max(sample_spacing, 1.0)
	var segments: int = maxi(ceili(length / spacing), 1)
	var positions: Array[Vector3] = []
	for index in range(segments + 1):
		positions.append(start.lerp(end, float(index) / float(segments)))
	return positions


func get_homing_target_position(origin: Vector3) -> Vector3:
	var endpoints: PackedVector3Array = _get_bar_endpoints()
	var start: Vector3 = endpoints[0]
	var segment: Vector3 = endpoints[1] - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0001:
		return start
	var progress: float = clamp((origin - start).dot(segment) / length_squared, 0.0, 1.0)
	return start + segment * progress


func get_homing_target_position_for_aim(aim_origin: Vector3, aim_direction: Vector3) -> Vector3:
	var direction: Vector3 = aim_direction.normalized()
	if direction.length() < 0.001:
		return get_homing_target_position(aim_origin)
	var endpoints: PackedVector3Array = _get_bar_endpoints()
	var segment_start: Vector3 = endpoints[0]
	var segment: Vector3 = endpoints[1] - segment_start
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= 0.0001:
		return segment_start
	var offset: Vector3 = segment_start - aim_origin
	var segment_direction_dot: float = segment.dot(direction)
	var segment_offset_dot: float = segment.dot(offset)
	var direction_offset_dot: float = direction.dot(offset)
	var denominator: float = segment_length_squared - segment_direction_dot * segment_direction_dot
	var segment_progress: float = 0.0
	if denominator > 0.0001:
		segment_progress = clamp(
			(segment_direction_dot * direction_offset_dot - segment_offset_dot) / denominator,
			0.0,
			1.0
		)
	var ray_progress: float = direction.dot(segment_start + segment * segment_progress - aim_origin)
	if ray_progress < 0.0:
		segment_progress = clamp(-segment_offset_dot / segment_length_squared, 0.0, 1.0)
	return segment_start + segment * segment_progress


func _play_rotation_sound() -> void:
	if _rotation_sfx:
		_rotation_sfx.play()


func _play_touch_sound() -> void:
	if _touch_sfx:
		_touch_sfx.play()


func _play_jump_sound() -> void:
	if _jump_sfx:
		_jump_sfx.play()

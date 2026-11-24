@tool
extends AnimatableBody3D

enum FlipperSide { LEFT, RIGHT }

const SWEEP_SAMPLE_SPACING: float = 0.45
const MAX_SWEEP_STEPS: int = 32
const MAX_GRACE_EXTENSION: float = 0.15

@export_group("Flipper")
## Selects the input, model, collision shape, and direction of the stroke.
@export var side: FlipperSide = FlipperSide.LEFT:
	set(value):
		side = value
		if is_node_ready():
			_apply_side()
## Travel from the resting pose around the flipper's local Y axis.
@export_range(1.0, 90.0, 0.5, "suffix:deg") var stroke_angle: float = 55.0
## Angular speed during the upward stroke.
@export_range(1.0, 1440.0, 1.0, "or_greater", "suffix:deg/s") var stroke_speed: float = 720.0
## Angular speed returning to the resting pose.
@export_range(1.0, 1440.0, 1.0, "or_greater", "suffix:deg/s") var return_speed: float = 480.0
## Maximum distance at which a player in pinball mode can operate the flipper. Zero removes the limit.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m") var input_range: float = 100.0
## Maximum outward speed transferred to a player during the upward stroke.
@export_range(0.0, 240.0, 1.0, "or_greater", "suffix:m/s") var maximum_strike_speed: float = 120.0

@export_subgroup("Launch Assist")
## Seconds from launch before airborne damping begins recovering. 0 starts the recovery ramp immediately.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var damping_grace_time: float = PlayerExternalMotionController.DEFAULT_LAUNCH_DAMPING_GRACE
## Extra reach of each swept-paddle overlap check.
@export_range(0.0, 1.0, 0.01, "or_greater", "suffix:m") var sweep_margin: float = 0.15
## Minimum speed from an assisted strike, including contacts near the hinge.
@export_range(0.0, 120.0, 0.5, "or_greater", "suffix:m/s") var minimum_assist_speed: float = 32.0
## Blend between the current stroke angle (0) and the hinge-to-tip contact position mapped onto the stroke arc (1).
@export_range(0.0, 1.0, 0.01) var contact_aim_weight: float = 0.7
## Fraction of sideways and opposing speed along the table redirected into the launch direction.
@export_range(0.0, 1.0, 0.01) var momentum_redirect_fraction: float = 0.85
## Time after reaching full height when a held flipper can catch an arriving player.
@export_range(0.0, 0.25, 0.01, "or_greater", "suffix:s") var strike_follow_through: float = 0.08
## Outgoing speed in the launch direction needed to lift the player and temporarily ignore this flipper.
@export_range(0.0, 120.0, 0.5, "or_greater", "suffix:m/s") var strong_launch_speed: float = 20.0
## Minimum speed away from the table on a strong launch.
@export_range(0.0, 40.0, 0.5, "or_greater", "suffix:m/s") var launch_lift_speed: float = 8.0
## Seconds a strongly launched player ignores this flipper's collider.
@export_range(0.0, 0.5, 0.01, "or_greater", "suffix:s") var collision_grace_time: float = 0.12

@onready var _left_model: Node3D = $LeftModel
@onready var _right_model: Node3D = $RightModel
@onready var _left_shape: CollisionShape3D = $LeftCollision
@onready var _right_shape: CollisionShape3D = $RightCollision
@onready var _stroke_audio: AudioStreamPlayer3D = $StrokeAudio

var _rest_basis: Basis = Basis.IDENTITY
var _angle: float = 0.0
var _stroke_in_progress: bool = false
var _stroke_angular_speed: float = 0.0
var _strike_follow_through_remaining: float = 0.0
var _paddle_shape: CollisionShape3D
var _paddle_tip: Vector3 = Vector3.ZERO
var _paddle_bottom: float = 0.0
var _sweep_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _strike_candidates: Array[PlayerController] = []
var _distance_culled: bool = false
var _struck_players: Dictionary[int, bool] = {}
var _collision_grace: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	_rest_basis = basis
	_apply_side()
	if Engine.is_editor_hint():
		return
	for model: Node3D in [_left_model, _right_model]:
		for collider: CollisionObject3D in model.find_children("*", "CollisionObject3D", true, false):
			collider.collision_layer = 0
			collider.collision_mask = 0


func _apply_side() -> void:
	var left: bool = side == FlipperSide.LEFT
	_left_model.visible = left
	_right_model.visible = not left
	_left_shape.set_deferred("disabled", not left)
	_right_shape.set_deferred("disabled", left)
	_paddle_shape = _left_shape if left else _right_shape
	_paddle_tip = Vector3.ZERO
	_paddle_bottom = INF
	var hull: ConvexPolygonShape3D = _paddle_shape.shape as ConvexPolygonShape3D
	if hull:
		for point: Vector3 in hull.points:
			var local: Vector3 = _paddle_shape.transform * point
			_paddle_bottom = minf(_paddle_bottom, local.y)
			var planar: Vector3 = local.slide(Vector3.UP)
			if planar.length_squared() > _paddle_tip.length_squared():
				_paddle_tip = planar


func set_distance_culled(value: bool) -> void:
	_distance_culled = value


func get_distance_cull_activity_range() -> float:
	return input_range + 60.0 if input_range > 0.0 else INF


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or delta <= 0.0:
		return
	_update_collision_grace(delta)
	if _distance_culled:
		_advance_stroke(delta, false, false)
		return
	var action: StringName = &"pinball_flipper_left" if side == FlipperSide.LEFT else &"pinball_flipper_right"
	var held: bool = false
	var pressed: bool = false
	_strike_candidates.clear()
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player: PlayerController = node as PlayerController
		if not _can_use_flipper(player) or not player.is_pinball_mode():
			continue
		_strike_candidates.append(player)
		if input_range > 0.0 and global_position.distance_squared_to(player.global_position) > input_range * input_range:
			continue
		held = held or player.is_pinball_flipper_pressed(action)
		pressed = pressed or player.is_pinball_flipper_just_pressed(action)
	var previous_pose: Transform3D = global_transform
	_advance_stroke(delta, held, pressed)
	if _can_strike_this_tick():
		_assist_swept_players(previous_pose, _stroke_angular_speed * delta * _stroke_sign())


func _advance_stroke(delta: float, held: bool, pressed: bool) -> void:
	_stroke_angular_speed = 0.0
	if not _stroke_in_progress and _angle < stroke_angle and (held or pressed):
		_stroke_in_progress = true
		_struck_players.clear()
		_stroke_audio.play()
	var previous: float = _angle
	if _stroke_in_progress:
		_angle = move_toward(_angle, stroke_angle, stroke_speed * delta)
		_stroke_angular_speed = deg_to_rad(_angle - previous) / delta
		_stroke_in_progress = _angle < stroke_angle
		if not _stroke_in_progress:
			_strike_follow_through_remaining = strike_follow_through
	elif not held:
		_strike_follow_through_remaining = 0.0
		_angle = move_toward(_angle, 0.0, return_speed * delta)
	else:
		_strike_follow_through_remaining = maxf(_strike_follow_through_remaining - delta, 0.0)
	if _angle != previous:
		basis = _rest_basis.rotated(_rest_basis.y.normalized(), deg_to_rad(_angle) * _stroke_sign())


func _stroke_sign() -> float:
	return 1.0 if side == FlipperSide.LEFT else -1.0


func resolve_player_collision_contact(body: Node3D, incoming_velocity: Vector3, contact_normal: Vector3) -> bool:
	var player: PlayerController = body as PlayerController
	if not _can_use_flipper(player):
		return false
	player.enter_pinball_mode()
	if not _can_strike_this_tick():
		return false
	return _try_strike(
		player, global_transform, _angle, player.get_main_collision_world_center(), incoming_velocity, contact_normal
	)


func _can_strike_this_tick() -> bool:
	return _stroke_angular_speed > 0.0 or _strike_follow_through_remaining > 0.0


func _can_use_flipper(player: PlayerController) -> bool:
	return (
		player and not player._is_buddy_actor() and not player._is_dead
		and player._network_is_local_authority()
		and bool(player.collision_mask & collision_layer)
	)


func _assist_swept_players(previous_pose: Transform3D, angle_delta: float) -> void:
	if _paddle_tip.is_zero_approx():
		return
	var tip_distance: float = (previous_pose.basis * _paddle_tip).length()
	var up: Vector3 = previous_pose.basis.y.normalized()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var paddle_travel: float = absf(angle_delta) * tip_distance
	var previous_angle: float = _angle - rad_to_deg(absf(angle_delta))
	for player: PlayerController in _strike_candidates:
		var player_id: int = player.get_instance_id()
		if _struck_players.has(player_id) or _collision_grace.has(player_id):
			continue
		var center: Vector3 = player.get_main_collision_world_center()
		var travel: Vector3 = player.velocity * player.get_movement_physics_delta()
		var reach: float = tip_distance * 1.25 + travel.length() + player.get_main_collision_world_radius() * 2.0 + sweep_margin
		if center.distance_squared_to(previous_pose.origin) > reach * reach:
			continue
		var steps: int = clampi(ceili((paddle_travel + travel.length()) / SWEEP_SAMPLE_SPACING), 1, MAX_SWEEP_STEPS)
		for step: int in range(steps + 1):
			var fraction: float = float(step) / float(steps)
			var pose: Transform3D = Transform3D(previous_pose.basis.rotated(up, angle_delta * fraction), previous_pose.origin)
			var offset: Vector3 = travel * fraction
			# Translate the query back by the player's travel so both motions are sampled at the same time.
			if _paddle_overlaps_player(space, pose.translated(-offset), player, sweep_margin):
				var sample_angle: float = lerpf(previous_angle, _angle, fraction)
				if _try_strike(player, pose, sample_angle, center + offset, player.velocity):
					break


func _paddle_overlaps_player(
	space: PhysicsDirectSpaceState3D, pose: Transform3D, player: PlayerController, margin: float
) -> bool:
	_sweep_query.shape = _paddle_shape.shape
	_sweep_query.collision_mask = player.collision_layer
	_sweep_query.margin = margin
	_sweep_query.transform = pose * _paddle_shape.transform
	for hit: Dictionary in space.intersect_shape(_sweep_query):
		if hit["collider"] == player:
			return true
	return false


func _try_strike(
	player: PlayerController, pose: Transform3D, pose_angle: float, center: Vector3, incoming_velocity: Vector3,
	contact_normal: Vector3 = Vector3.ZERO
) -> bool:
	var player_id: int = player.get_instance_id()
	if _struck_players.has(player_id) or _collision_grace.has(player_id) or player.get_collision_exceptions().has(self):
		return false
	if _paddle_tip.is_zero_approx() or (pose.affine_inverse() * center).y < _paddle_bottom - sweep_margin:
		return false
	var up: Vector3 = pose.basis.y.normalized()
	var arm: Vector3 = pose.basis * _paddle_tip
	var contact_fraction: float = clampf((center - pose.origin).dot(arm) / arm.length_squared(), 0.0, 1.0)
	var stroke_sign: float = _stroke_sign()
	var tangent: Vector3 = up.cross(arm) * stroke_sign
	var stroke_direction: Vector3 = tangent.normalized()
	if not contact_normal.is_zero_approx() and stroke_direction.dot(contact_normal) <= 0.1 and up.dot(contact_normal) <= 0.35:
		return false
	var angular_speed: float = _stroke_angular_speed if _stroke_angular_speed > 0.0 else deg_to_rad(stroke_speed)
	var paddle_speed: float = player.world_to_movement_velocity(tangent * (contact_fraction * angular_speed)).length()
	var strike_speed: float = minf(maxf(paddle_speed, minimum_assist_speed), maximum_strike_speed)
	if strike_speed <= 0.0:
		return false
	var contact_angle: float = contact_fraction * stroke_angle
	var aim_offset: float = deg_to_rad((contact_angle - pose_angle) * contact_aim_weight) * stroke_sign
	var direction: Vector3 = stroke_direction.rotated(up, aim_offset)
	var normal_speed: float = incoming_velocity.dot(up)
	var planar_velocity: Vector3 = incoming_velocity - up * normal_speed
	var forward_speed: float = planar_velocity.dot(direction)
	var carried_speed: float = maxf(forward_speed, 0.0)
	var sideways_velocity: Vector3 = planar_velocity - direction * forward_speed
	var redirect_fraction: float = clampf(momentum_redirect_fraction, 0.0, 1.0)
	var redirect_speed: float = (planar_velocity - direction * carried_speed).length() * redirect_fraction
	var exit_speed: float = maxf(strike_speed, Vector2(carried_speed, redirect_speed).length())
	var launch_velocity: Vector3 = direction * exit_speed + sideways_velocity * (1.0 - redirect_fraction) + up * normal_speed
	if launch_velocity.is_equal_approx(incoming_velocity):
		return false
	_struck_players[player_id] = true
	if player._rail_active or player._rail_switch_active:
		player.cancel_rail_grind()
		player.attached = false
		player._attachment_immunity = maxf(player._attachment_immunity, player.get_physics_process_delta_time() * 2.0)
	player.velocity = launch_velocity
	if exit_speed >= strong_launch_speed:
		_clear_player_from_paddle(player, up)
	if not player.attached:
		player.protect_airborne_launch_from_damping(damping_grace_time)
	return true


func _clear_player_from_paddle(player: PlayerController, up: Vector3) -> void:
	player.velocity += up * maxf(launch_lift_speed - player.velocity.dot(up), 0.0)
	if launch_lift_speed > 0.0 and player.attached:
		player._record_detach_state(player.surface_normal, player.get_gravity_up(), false, false)
		player.attached = false
		player._attachment_immunity = maxf(player._attachment_immunity, player.get_physics_process_delta_time() * 2.0)
	if collision_grace_time <= 0.0:
		return
	player.add_collision_exception_with(self)
	var ray: RayCast3D = player.ground_ray
	if ray:
		ray.add_exception(self)
	_collision_grace[player.get_instance_id()] = {
		"player": weakref(player),
		"ray": ray,
		"remaining": collision_grace_time,
	}


func _update_collision_grace(delta: float) -> void:
	for player_id: int in _collision_grace.keys():
		var entry: Dictionary = _collision_grace[player_id]
		var remaining: float = float(entry["remaining"]) - delta
		if remaining <= 0.0:
			var player: PlayerController = entry["player"].get_ref() as PlayerController
			if (
				remaining > -MAX_GRACE_EXTENSION and is_instance_valid(player)
				and _paddle_overlaps_player(get_world_3d().direct_space_state, global_transform, player, 0.0)
			):
				entry["remaining"] = remaining
				continue
			_restore_player_collision(entry)
			_collision_grace.erase(player_id)
		else:
			entry["remaining"] = remaining


func _restore_player_collision(entry: Dictionary) -> void:
	var player: PlayerController = entry["player"].get_ref() as PlayerController
	if is_instance_valid(player):
		player.remove_collision_exception_with(self)
	var ray: RayCast3D = entry["ray"] as RayCast3D
	if is_instance_valid(ray):
		ray.remove_exception(self)


func _exit_tree() -> void:
	for entry: Dictionary in _collision_grace.values():
		_restore_player_collision(entry)
	_collision_grace.clear()

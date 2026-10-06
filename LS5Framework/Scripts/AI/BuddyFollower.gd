extends CharacterBody3D
class_name BuddyFollower

@export var target: Node3D

@export_group("Follow")
@export var follow_distance: float = 3.0
@export var max_speed: float = 18.0
@export var accel: float = 45.0
@export var decel: float = 35.0
@export var catchup_multiplier: float = 1.8
@export var catchup_distance: float = 14.0
@export var teleport_if_far: bool = true
@export var teleport_distance: float = 70.0

@export_group("Jumping")
@export var jump_speed: float = 16.0
@export var obstacle_check_distance: float = 1.2
@export var obstacle_check_height: float = 0.9
@export var jump_cooldown: float = 0.25

@export_group("Gravity / Loops")
@export var gravity_strength: float = 38.0
@export var ground_ray_length: float = 3.0
@export var ground_attach_snap: float = 0.35

@export_group("Animation")
## Animation player used by the follower locomotion states.
@export var animation_player_path: NodePath = NodePath("ModelRoot/Sonic_NeoAdv_Root/AnimationPlayer")
@export var anim_idle: StringName = &"Idle"
@export var anim_run: StringName = &"Move3_Run"
@export var anim_fall: StringName = &"Fall"
@export var anim_jump: StringName = &"Jump"

var _jump_timer: float = 0.0
var _anim_player: AnimationPlayer

var _desired_up: Vector3 = Vector3.UP


func _ready() -> void:
	_desired_up = _get_target_gravity_up()
	if animation_player_path != NodePath(""):
		_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		velocity = Vector3.ZERO
		_play_anim_idle()
		return

	_jump_timer = max(_jump_timer - delta, 0.0)

	_update_desired_up()
	up_direction = _desired_up

	var to_target: Vector3 = target.global_position - global_position
	var planar_to_target: Vector3 = to_target - _desired_up * to_target.dot(_desired_up)
	var planar_dist: float = planar_to_target.length()

	if teleport_if_far and planar_dist > teleport_distance:
		var side: Vector3 = Vector3.RIGHT
		var spawn_pos: Vector3 = target.global_position + side * 1.5 + _desired_up * 0.25
		global_position = spawn_pos
		velocity = Vector3.ZERO
		return

	# Determine desired move direction (planar).
	var move_dir: Vector3 = Vector3.ZERO
	if planar_dist > max(follow_distance, 0.0) and planar_dist > 0.001:
		move_dir = planar_to_target / planar_dist

	# Apply gravity toward the current "down" (opposite desired up).
	var vertical_speed: float = velocity.dot(_desired_up)
	vertical_speed -= gravity_strength * delta

	var lateral: Vector3 = velocity - _desired_up * velocity.dot(_desired_up)

	# Accelerate toward target.
	var desired_speed: float = 0.0
	if move_dir.length() > 0.001:
		desired_speed = max_speed
		if planar_dist > catchup_distance:
			desired_speed *= max(catchup_multiplier, 1.0)

	var desired_lateral: Vector3 = move_dir * desired_speed
	var rate: float = accel if desired_speed > 0.0 else decel
	var t: float = clamp(rate * delta, 0.0, 1.0)
	lateral = lateral.lerp(desired_lateral, t)

	# Jump if obstacle ahead and we're roughly "grounded".
	if _should_jump(move_dir) and _jump_timer <= 0.0:
		vertical_speed = max(vertical_speed, jump_speed)
		_jump_timer = jump_cooldown

	# Recombine velocity and move.
	velocity = lateral + _desired_up * vertical_speed
	move_and_slide()

	_snap_to_ground(delta)
	_update_animation_state()


func _update_desired_up() -> void:
	_desired_up = _get_target_gravity_up()


func _get_target_gravity_up() -> Vector3:
	if target != null and is_instance_valid(target) and target.has_method("get_gravity_up"):
		var gravity_up_value = target.call("get_gravity_up")
		if gravity_up_value is Vector3:
			var gravity_up: Vector3 = (gravity_up_value as Vector3).normalized()
			if gravity_up.length() >= 0.001:
				return gravity_up
	return Vector3.UP


func _snap_to_ground(delta: float) -> void:
	# Try to stay attached to the nearest surface along the current down direction.
	if get_world_3d() == null:
		return
	var space_state = get_world_3d().direct_space_state
	var from: Vector3 = global_position + _desired_up * 0.2
	var to: Vector3 = from - _desired_up * max(ground_ray_length, 0.1)
	var params = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [self]
	var hit = space_state.intersect_ray(params)
	if hit:
		var n = hit.normal
		if n is Vector3 and (n as Vector3).length() > 0.001:
			var nn: Vector3 = (n as Vector3).normalized()
			_desired_up = nn
			up_direction = _desired_up
		# Optional small snap to keep us close to the surface.
		if ground_attach_snap > 0.0:
			var desired_pos: Vector3 = (hit.position as Vector3) + _desired_up * ground_attach_snap
			global_position = global_position.lerp(desired_pos, clamp(12.0 * delta, 0.0, 1.0))


func _should_jump(move_dir: Vector3) -> bool:
	if move_dir.length() < 0.001:
		return false
	if get_world_3d() == null:
		return false

	# Don't jump if moving upward strongly relative to up.
	var v_up: float = velocity.dot(_desired_up)
	if v_up > 2.0:
		return false

	var origin: Vector3 = global_position + _desired_up * obstacle_check_height
	var end: Vector3 = origin + move_dir * max(obstacle_check_distance, 0.0)
	var params = PhysicsRayQueryParameters3D.create(origin, end)
	params.exclude = [self]
	var hit = get_world_3d().direct_space_state.intersect_ray(params)
	return bool(hit)


func _update_animation_state() -> void:
	if _anim_player == null:
		return
	var up: Vector3 = _desired_up
	if up.length() < 0.001:
		up = _get_target_gravity_up()

	var lateral: Vector3 = velocity - up * velocity.dot(up)
	var speed: float = lateral.length()
	var v_up: float = velocity.dot(up)

	if v_up > 1.0:
		_play_anim(anim_jump)
	elif v_up < -1.0:
		_play_anim(anim_fall)
	elif speed > 0.5:
		_play_anim(anim_run)
	else:
		_play_anim_idle()


func _play_anim_idle() -> void:
	_play_anim(anim_idle)


func _play_anim(name: StringName) -> void:
	if _anim_player == null:
		return
	if _anim_player.is_playing() and _anim_player.current_animation == String(name):
		return
	if _anim_player.has_animation(name):
		_anim_player.play(name)
		return
	# Fallback: try without library prefix if needed.
	var s = String(name)
	var idx = s.find("/")
	if idx != -1:
		var short = s.substr(idx + 1)
		if _anim_player.has_animation(short):
			_anim_player.play(short)

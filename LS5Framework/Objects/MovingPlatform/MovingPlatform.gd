extends Node3D
class_name MovingPlatform

enum MotionMode {
	LOOP,
	PING_PONG,
	ONE_SHOT
}

@export_group("Moving Platform")
@export var enabled: bool = true
@export var motion_mode: MotionMode = MotionMode.LOOP
@export var speed: float = 5.0 # meters per second along the spline
@export var start_forward: bool = true
## Smoothly accelerates and decelerates at the beginning and end of each loop or ping-pong pass.
@export var slerp_in_out: bool = false

@export var start_on_player_collision: bool = false
@export var require_group: StringName = &"player"

@export_group("Nodes")
@export var path: Path3D
@export var follow: PathFollow3D
@export var start_trigger: Area3D
## Collision shape used for player-start activation.
@export var start_trigger_shape: CollisionShape3D

var _running: bool = false
var _started_once: bool = false
var _direction: float = 1.0
var _path_length: float = 0.0
var _motion_progress: float = 0.0


func _ready() -> void:
	process_priority = -100
	process_physics_priority = -100
	if path == null:
		path = get_node_or_null("Path3D") as Path3D
	if follow == null:
		follow = get_node_or_null("Path3D/PathFollow3D") as PathFollow3D
	if start_trigger == null:
		start_trigger = get_node_or_null("Path3D/PathFollow3D/PlatformBody/StartTrigger") as Area3D
	if start_trigger_shape == null:
		start_trigger_shape = get_node_or_null("Path3D/PathFollow3D/PlatformBody/StartTrigger/CollisionShape3D") as CollisionShape3D

	_direction = 1.0 if start_forward else -1.0
	_recalculate_length()
	if follow != null:
		_motion_progress = follow.progress

	_running = (not start_on_player_collision)
	_started_once = _running

	if start_trigger != null:
		start_trigger.monitoring = start_on_player_collision
		start_trigger.monitorable = start_on_player_collision
		if not start_trigger.body_entered.is_connected(_on_start_trigger_body_entered):
			start_trigger.body_entered.connect(_on_start_trigger_body_entered)
	if start_trigger_shape != null:
		start_trigger_shape.disabled = not start_on_player_collision


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if follow == null or path == null:
		return
	if not _running:
		return

	if _path_length <= 0.0:
		_recalculate_length()
		if _path_length <= 0.0:
			return

	var step: float = abs(speed) * delta * _direction
	_motion_progress += step
	if not slerp_in_out or motion_mode == MotionMode.ONE_SHOT:
		follow.progress = _motion_progress

	match motion_mode:
		MotionMode.LOOP:
			_apply_loop()
		MotionMode.PING_PONG:
			_apply_ping_pong()
		MotionMode.ONE_SHOT:
			_apply_one_shot()

	if slerp_in_out and motion_mode != MotionMode.ONE_SHOT:
		_apply_slerped_progress()


func _on_start_trigger_body_entered(body: Node) -> void:
	if not enabled:
		return
	if not start_on_player_collision:
		return
	if _started_once:
		return
	if body == null:
		return
	if require_group != &"" and not body.is_in_group(require_group):
		return

	_started_once = true
	_running = true
	if start_trigger != null:
		start_trigger.monitoring = false
		start_trigger.monitorable = false
	if start_trigger_shape != null:
		start_trigger_shape.disabled = true


func _recalculate_length() -> void:
	_path_length = 0.0
	if path == null:
		return
	if path.curve == null:
		return
	_path_length = float(path.curve.get_baked_length())


func _apply_loop() -> void:
	if _path_length <= 0.0:
		return

	var p: float = _motion_progress
	if p >= _path_length:
		_motion_progress = fmod(p, _path_length)
	elif p < 0.0:
		var wrapped: float = fmod(p, _path_length)
		_motion_progress = wrapped + _path_length
	if not slerp_in_out:
		follow.progress = _motion_progress


func _apply_ping_pong() -> void:
	if _path_length <= 0.0:
		return

	var p: float = _motion_progress
	if p >= _path_length:
		_motion_progress = _path_length
		_direction = -1.0
	elif p <= 0.0:
		_motion_progress = 0.0
		_direction = 1.0
	if not slerp_in_out:
		follow.progress = _motion_progress


func _apply_one_shot() -> void:
	if _path_length <= 0.0:
		return

	var p: float = _motion_progress
	if _direction >= 0.0:
		if p >= _path_length:
			_motion_progress = _path_length
			follow.progress = _path_length
			_running = false
	else:
		if p <= 0.0:
			_motion_progress = 0.0
			follow.progress = 0.0
			_running = false


func _apply_slerped_progress() -> void:
	var normalized_progress: float = clamp(_motion_progress / _path_length, 0.0, 1.0)
	var eased_progress: float = smoothstep(0.0, 1.0, normalized_progress)
	follow.progress = eased_progress * _path_length

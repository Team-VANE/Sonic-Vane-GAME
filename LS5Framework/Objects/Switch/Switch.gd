extends StaticBody3D

signal activated(player: Node3D)
signal deactivated(player: Node3D)

const ActivationLight = preload("res://LS5Framework/Objects/Switch/ActivationLight.gd")

const SPRING_STRENGTH: float = 96.0
const SPRING_DAMPING: float = 10.0
const HELD_BALL_REACH: float = 0.75
const MAX_SOCKET_TILT: float = PI / 12.0
const SETTLE_DISTANCE_SQUARED: float = 0.000004

## Starts with the ball seated and ready to be pushed. Otherwise the ball starts at Loose Ball Spawn.
@export var starts_connected: bool = true
## Maximum travel from the seated pose, capped by the socket's tilt clearance.
@export_range(0.0, 0.26, 0.01, "suffix:m") var maximum_push_distance: float = 0.25
## Rigid carryable ball used when the switch starts empty.
@export var loose_ball_scene: PackedScene
## Spawns a loose ball when the base starts empty. Disable to use a separately placed ball.
@export var spawn_loose_ball: bool = true
## Radius of the catch area for a rolling, dropped, or thrown ball.
@export_range(0.1, 4.0, 0.05, "or_greater", "suffix:m") var loose_ball_capture_radius: float = 1.35
@export_group("Activation")
## Latch permanently, expire after a countdown, or toggle on each press.
@export var activation_mode: ActivationSource.Mode = ActivationSource.Mode.LATCHED
## Objects controlled by this switch. Paths are relative to the switch root.
@export var activation_target_paths: Array[NodePath] = []
## Duration of a timed activation.
@export_range(0.1, 300.0, 0.1, "or_greater", "suffix:s") var timer_duration: float = 10.0
## Pauses the timer while the player is pressing the ball.
@export var hold_timer_while_pressed: bool = true
## Restarts the countdown on another press while the switch is active.
@export var restart_timer_on_press: bool = false
## Time before expiry during which the beep interval shortens.
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:s") var acceleration_window: float = 3.0

@export_group("Feedback")
## Sound played for activation and each countdown beep.
@export var activation_sound: AudioStream
## Sound played when the timer expires.
@export var expiration_sound: AudioStream
## Texture used for the ball's light while the switch is active.
@export var light_on_texture: Texture2D
## Emission multiplier for the active ball light.
@export_range(0.0, 16.0, 0.05, "or_greater") var light_emission: float = 1.5

## Rest position of the ball and aim point for targeted throws.
@onready var _socket: Marker3D = $Socket
## Starting pose of this switch's loose carryable ball.
@onready var _loose_spawn: Marker3D = $LooseBallSpawn
## Seated ball model displaced by contact with a player.
@onready var _seated_ball: Node3D = $SeatedBall
## Collects loose balls at the socket.
@onready var _socket_area: Area3D = $SocketArea
## Collision shape that sets the loose-ball catch radius.
@onready var _socket_shape: CollisionShape3D = $SocketArea/CollisionShape3D
## Detects player contact and carried balls around the base.
@onready var _push_area: Area3D = $PushArea
## Non-positional feedback for the activating player.
@onready var _feedback: AudioStreamPlayer = $ActivationFeedback

## Owns activation state and target claims.
@onready var _activation: ActivationSource = $ActivationSource
## Restores the ball light after a countdown flash.
@onready var _flash_timer: Timer = $LightFlash
## Mesh containing the ball's status light surface.
@onready var _ball_mesh: MeshInstance3D = $SeatedBall/Switch_Ball

var _connected: bool = false
var _watch_socket: bool = false
var _pressed: bool = false
var _just_docked: bool = false
var _light_surface: int = -1
var _light_off: StandardMaterial3D
var _light_on: StandardMaterial3D
var _offset: Vector2 = Vector2.ZERO
var _wobble_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	_connected = starts_connected
	_seated_ball.visible = _connected
	_seated_ball.transform = _socket.transform
	_socket_area.position = _socket.position
	(_socket_shape.shape as SphereShape3D).radius = maxf(loose_ball_capture_radius, 0.1)
	_socket_area.monitoring = not _connected
	_push_area.position = _socket.position
	_socket_area.body_entered.connect(_on_socket_entered)
	_push_area.body_entered.connect(_on_player_entered)
	_activation.mode = activation_mode
	_activation.duration = timer_duration
	_activation.hold_timer_while_pressed = hold_timer_while_pressed
	_activation.restart_timer_on_press = restart_timer_on_press
	_activation.acceleration_window = acceleration_window
	_activation.active_changed.connect(_on_active_changed)
	_activation.activation_started.connect(_on_activation_started)
	_activation.countdown_tick.connect(_on_countdown_tick)
	_activation.expired.connect(_on_expired)
	_flash_timer.timeout.connect(_set_light.bind(true))
	_setup_light()
	set_physics_process(false)
	if _connected:
		remove_from_group(&"CarryThrowTarget")
	elif spawn_loose_ball and loose_ball_scene:
		_spawn_loose_ball()


func _spawn_loose_ball() -> void:
	var ball: Node3D = loose_ball_scene.instantiate() as Node3D
	if ball:
		ball.top_level = true
		ball.transform = _loose_spawn.global_transform
		add_child(ball)


func can_receive_thrown_object(ball: Node3D) -> bool:
	return not _connected and is_instance_valid(ball) and not ball.is_queued_for_deletion() and ball is CarryableObject and ball.is_in_group(&"switch_ball")


func get_throw_target_position() -> Vector3:
	return _socket.global_position


func is_active() -> bool:
	return _activation.is_active


func activate(player: Node3D = null) -> void:
	if not _activation.is_active:
		_activation.set_targets(self, activation_target_paths)
	_activation.activate(player)


func deactivate() -> void:
	_activation.deactivate()


func _on_socket_entered(body: Node3D) -> void:
	if can_receive_thrown_object(body):
		_watch_socket = true
		set_physics_process(true)


func _on_player_entered(body: Node3D) -> void:
	if body is PlayerController:
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _watch_socket:
		_watch_socket = false
		for body: Node3D in _socket_area.get_overlapping_bodies():
			if not can_receive_thrown_object(body):
				continue
			var ball: CarryableObject = body as CarryableObject
			if not ball.is_carried():
				_dock_ball(ball)
				break
			_watch_socket = true

	var overlapping: Array[Node3D] = _push_area.get_overlapping_bodies()
	var push: Vector2 = Vector2.ZERO
	var strongest_pressure: float = 0.0
	var pusher: PlayerController
	var has_player: bool = false
	for body: Node3D in overlapping:
		var player: PlayerController = body as PlayerController
		if not player or player._is_buddy_actor() or not player._network_is_local_authority():
			continue
		has_player = true
		if not _connected:
			var carried: CarryableObject = player.get("_carried_object") as CarryableObject
			if can_receive_thrown_object(carried) and carried.global_position.distance_squared_to(_socket.global_position) <= HELD_BALL_REACH * HELD_BALL_REACH:
				_dock_ball(carried)
			continue
		var separation: Vector3 = to_local(player.get_main_collision_world_center()) - _socket.position
		var reach: float = 1.35 + player.get_main_collision_world_radius()
		var pressure: float = clampf((reach - separation.length()) / 0.32, 0.0, 1.0)
		var direction: Vector2 = Vector2(-separation.x, -separation.z)
		if direction.is_zero_approx():
			var incoming: Vector3 = global_basis.inverse() * player.velocity
			direction = Vector2(incoming.x, incoming.z)
		if pressure > strongest_pressure:
			strongest_pressure = pressure
			push = direction.normalized() * pressure
			pusher = player
	var pressed: bool = is_instance_valid(pusher)
	_activation.set_pressed(pressed)
	if pressed and not _pressed and not _just_docked:
		if not _activation.is_active:
			_activation.set_targets(self, activation_target_paths)
		_activation.press(pusher)
	_pressed = pressed
	_just_docked = false
	if _connected:
		var pivot_radius: float = _socket.position.length()
		var limit: float = clampf(maximum_push_distance, 0.0, 2.0 * pivot_radius * sin(MAX_SOCKET_TILT * 0.5))
		var target: Vector2 = push * limit
		_wobble_velocity += (target - _offset) * SPRING_STRENGTH * delta
		_wobble_velocity *= exp(-SPRING_DAMPING * delta)
		_offset = (_offset + _wobble_velocity * delta).limit_length(limit)
		if not has_player and _offset.length_squared() < SETTLE_DISTANCE_SQUARED and _wobble_velocity.length_squared() < SETTLE_DISTANCE_SQUARED:
			_offset = Vector2.ZERO
			_wobble_velocity = Vector2.ZERO
		_apply_ball_pivot(pivot_radius)
	if not _watch_socket and not has_player and _offset == Vector2.ZERO and _wobble_velocity == Vector2.ZERO:
		set_physics_process(false)


func _apply_ball_pivot(pivot_radius: float) -> void:
	if _offset.is_zero_approx() or is_zero_approx(pivot_radius):
		_seated_ball.transform = _socket.transform
		return
	var radial: Vector3 = _socket.position / pivot_radius
	var direction: Vector3 = Vector3(_offset.x, 0.0, _offset.y)
	var axis: Vector3 = radial.cross(direction).normalized()
	var angle: float = 2.0 * asin(clampf(_offset.length() / (2.0 * pivot_radius), 0.0, 1.0))
	var rotation: Basis = Basis(axis, angle)
	_seated_ball.transform = Transform3D(rotation * _socket.basis, rotation * _socket.position)


func _dock_ball(ball: CarryableObject) -> void:
	if not can_receive_thrown_object(ball):
		return
	var player: Node3D = ball.carry_holder if ball.is_carried() else ball.get_score_award_recipient()
	_connected = true
	_watch_socket = false
	_socket_area.monitoring = false
	remove_from_group(&"CarryThrowTarget")
	_seated_ball.transform = _socket.transform
	_seated_ball.visible = true
	ball.clear_carry_owner()
	ball.queue_free()
	_just_docked = true
	set_physics_process(true)
	activate(player)


func _setup_light() -> void:
	if not light_on_texture:
		return
	_light_surface = ActivationLight.find_surface(_ball_mesh)
	if _light_surface >= 0:
		_light_off = _ball_mesh.get_active_material(_light_surface) as StandardMaterial3D
		_light_on = ActivationLight.make_on_material(_light_off, light_on_texture, light_emission)


func _set_light(on: bool) -> void:
	if _light_surface >= 0:
		_ball_mesh.set_surface_override_material(_light_surface, _light_on if on else _light_off)


func _on_active_changed(active: bool, player: Node3D) -> void:
	_flash_timer.stop()
	_set_light(active)
	if active:
		activated.emit(player)
	else:
		deactivated.emit(player)


func _on_activation_started(player: Node3D) -> void:
	_flash_timer.stop()
	_set_light(true)
	_play_feedback(activation_sound, player)


func _on_countdown_tick() -> void:
	_set_light(false)
	_flash_timer.start()
	_play_feedback(activation_sound, _activation.get_actor())


func _on_expired() -> void:
	_play_feedback(expiration_sound, _activation.get_actor())


func _play_feedback(sound: AudioStream, player: Node3D) -> void:
	if sound and is_instance_valid(player) and player is PlayerController and player._network_is_local_authority():
		_feedback.stream = sound
		_feedback.play()

extends Node
class_name EnemyBrain

signal state_changed(state_name: StringName)

enum State {
	IDLE,
	ALERT,
	CHASE,
	ATTACK,
	RETURN_HOME,
}

@export_group("Behavior")
## Allows this brain to move toward acquired targets.
@export var follow_target: bool = true
## Returns the actor to its spawn position after losing a target.
@export var return_home_when_idle: bool = true
## Delay between acquiring a target and beginning pursuit.
@export var alert_duration_sec: float = 0.35
## Distance from home considered close enough to stop returning.
@export var home_arrival_distance: float = 5.0
## Maximum distance from spawn before the target is abandoned. Zero disables the leash.
@export var maximum_leash_distance: float = 35.0
## Movement speed ratio requested while pursuing a target.
@export_range(0.0, 1.0, 0.01) var chase_speed_ratio: float = 1.0
## Movement speed ratio requested while returning home.
@export_range(0.0, 1.0, 0.01) var return_speed_ratio: float = 0.75
## Requests attacks when an available attack is in range.
@export var attacks_enabled: bool = true

@export_group("Jump Requests")
## Requests a jump while chasing a target above the actor.
@export var jump_to_reach_target: bool = false
## Minimum target height along gravity-up that requests a jump.
@export var jump_target_height_threshold: float = 1.5
## Minimum delay between target-height jump requests.
@export var jump_request_cooldown_sec: float = 1.25
## Requests periodic jumps while chasing regardless of target height.
@export var periodic_chase_jump: bool = false
## Delay between periodic chase jump requests.
@export var periodic_chase_jump_interval_sec: float = 2.0

var state: State = State.IDLE
var _state_timer: float = 0.0
var _jump_request_timer: float = 0.0
var _last_target: Node3D = null


func physics_tick(
	delta: float,
	actor: CharacterBody3D,
	target: Node3D,
	home_position: Vector3,
	attack_controller: EnemyAttackController,
	intent: EnemyIntent
) -> void:
	intent.clear()
	_state_timer = max(_state_timer - delta, 0.0)
	_jump_request_timer = max(_jump_request_timer - delta, 0.0)
	if target and maximum_leash_distance > 0.0:
		if target.global_position.distance_to(home_position) > maximum_leash_distance:
			target = null
	if target != _last_target:
		_last_target = target
		if target:
			_set_state(State.ALERT)
			_state_timer = max(alert_duration_sec, 0.0)
		elif return_home_when_idle:
			_set_state(State.RETURN_HOME)

	if attack_controller and attack_controller.is_attacking():
		_set_state(State.ATTACK)
		intent.movement_locked = attack_controller.locks_movement()
		intent.facing_locked = attack_controller.locks_facing()
		if target:
			intent.face_direction = target.global_position - actor.global_position
		return

	if target:
		var to_target: Vector3 = target.global_position - actor.global_position
		intent.face_direction = to_target
		if state == State.ALERT and _state_timer > 0.0:
			return
		_set_state(State.CHASE)
		if follow_target and to_target.length() > 0.001:
			intent.move_direction = to_target.normalized()
			intent.speed_ratio = chase_speed_ratio
			_update_jump_request(actor, to_target, intent)
			if intent.jump_requested:
				return
		if attacks_enabled and attack_controller and attack_controller.has_attack_in_range(target):
			intent.attack_requested = true
			return
		return

	if return_home_when_idle:
		var to_home: Vector3 = home_position - actor.global_position
		if to_home.length() > max(home_arrival_distance, 0.0):
			_set_state(State.RETURN_HOME)
			intent.move_direction = to_home.normalized()
			intent.face_direction = to_home
			intent.speed_ratio = return_speed_ratio
			return
	_set_state(State.IDLE)


func reset_brain() -> void:
	_last_target = null
	_state_timer = 0.0
	_jump_request_timer = 0.0
	_set_state(State.IDLE)


func get_state_tag() -> StringName:
	match state:
		State.ALERT:
			return &"alert"
		State.CHASE:
			return &"chase"
		State.ATTACK:
			return &"attack"
		State.RETURN_HOME:
			return &"return_home"
		_:
			return &"idle"


func _set_state(next_state: State) -> void:
	if state == next_state:
		return
	state = next_state
	state_changed.emit(get_state_tag())


func _update_jump_request(actor: CharacterBody3D, to_target: Vector3, intent: EnemyIntent) -> void:
	if _jump_request_timer > 0.0:
		return
	var target_is_above: bool = false
	if jump_to_reach_target:
		target_is_above = to_target.dot(_get_actor_up(actor)) >= max(jump_target_height_threshold, 0.0)
	if target_is_above:
		intent.jump_requested = true
		_jump_request_timer = max(jump_request_cooldown_sec, 0.0)
	elif periodic_chase_jump:
		intent.jump_requested = true
		_jump_request_timer = max(periodic_chase_jump_interval_sec, 0.0)


func _get_actor_up(actor: CharacterBody3D) -> Vector3:
	if actor.has_method("get_gravity_up"):
		var up_value: Variant = actor.call("get_gravity_up")
		if up_value is Vector3:
			var up: Vector3 = (up_value as Vector3).normalized()
			if up.length() >= 0.001:
				return up
	return Vector3.UP

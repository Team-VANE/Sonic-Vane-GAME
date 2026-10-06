extends Node
class_name EnemyAttack

signal started()
signal active_window_opened()
signal active_window_closed()
signal finished()

enum Phase {
	READY,
	WINDUP,
	ACTIVE,
	RECOVERY,
	COOLDOWN,
}

@export_group("Attack")
## Enables this attack for selection by an attack controller.
@export var enabled: bool = true
## Higher-priority valid attacks are selected first.
@export var priority: int = 0
## Minimum target distance accepted by this attack.
@export var minimum_range: float = 0.0
## Maximum target distance accepted by this attack.
@export var maximum_range: float = 3.0
## Delay between starting and opening the active window.
@export var windup_duration_sec: float = 0.25
## Duration of the active damage or release window.
@export var active_duration_sec: float = 0.15
## Delay after the active window before movement resumes.
@export var recovery_duration_sec: float = 0.4
## Cooldown before this attack can be selected again.
@export var cooldown_duration_sec: float = 1.2
## Prevents locomotion while this attack is in progress.
@export var lock_movement: bool = true
## Prevents locomotion from changing facing while this attack is in progress.
@export var lock_facing: bool = false
## Semantic animation state requested while this attack is active.
@export var animation_tag: StringName = &"attack_primary"

var actor: CharacterBody3D = null
var target: Node3D = null
var phase: Phase = Phase.READY
var _phase_timer: float = 0.0


func setup(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor
	_reset_runtime()


func physics_tick(delta: float) -> void:
	if phase == Phase.READY:
		return
	_phase_timer = max(_phase_timer - delta, 0.0)
	if _phase_timer > 0.0:
		return
	match phase:
		Phase.WINDUP:
			_open_active_window()
		Phase.ACTIVE:
			_close_active_window()
		Phase.RECOVERY:
			finished.emit()
			phase = Phase.COOLDOWN
			_phase_timer = max(cooldown_duration_sec, 0.0)
			if _phase_timer <= 0.0:
				phase = Phase.READY
		Phase.COOLDOWN:
			phase = Phase.READY
			target = null


func can_start(candidate: Node3D) -> bool:
	if not enabled or phase != Phase.READY or actor == null or candidate == null:
		return false
	var distance: float = actor.global_position.distance_to(candidate.global_position)
	return distance >= max(minimum_range, 0.0) and distance <= max(maximum_range, minimum_range)


func start(candidate: Node3D) -> bool:
	if not can_start(candidate):
		return false
	target = candidate
	phase = Phase.WINDUP
	_phase_timer = max(windup_duration_sec, 0.0)
	started.emit()
	if _phase_timer <= 0.0:
		_open_active_window()
	return true


func cancel() -> void:
	if phase == Phase.ACTIVE:
		_on_active_window_closed()
	_reset_runtime()


func is_in_progress() -> bool:
	return phase == Phase.WINDUP or phase == Phase.ACTIVE or phase == Phase.RECOVERY


func animation_open_active_window() -> void:
	if phase == Phase.WINDUP:
		_open_active_window()


func animation_close_active_window() -> void:
	if phase == Phase.ACTIVE:
		_close_active_window()


func _open_active_window() -> void:
	phase = Phase.ACTIVE
	_phase_timer = max(active_duration_sec, 0.0)
	_on_active_window_opened()
	active_window_opened.emit()
	if _phase_timer <= 0.0:
		_close_active_window()


func _close_active_window() -> void:
	_on_active_window_closed()
	active_window_closed.emit()
	phase = Phase.RECOVERY
	_phase_timer = max(recovery_duration_sec, 0.0)
	if _phase_timer <= 0.0:
		finished.emit()
		phase = Phase.COOLDOWN
		_phase_timer = max(cooldown_duration_sec, 0.0)


func _on_active_window_opened() -> void:
	pass


func _on_active_window_closed() -> void:
	pass


func _reset_runtime() -> void:
	phase = Phase.READY
	_phase_timer = 0.0
	target = null


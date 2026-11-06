extends EnemyBrain
class_name EnemyChargeBrain

enum ChargePhase { PATROL, WINDUP, CHARGE, RECOVER, HURT }

## Distance travelled forward from home before patrolling back.
@export var patrol_distance: float = 12.0
## Patrol movement as a fraction of locomotion speed.
@export_range(0.0, 1.0, 0.01) var patrol_speed_ratio: float = 0.2
## Time spent aiming and telegraphing before committing to a heading.
@export var windup_time: float = 0.8833333
## Maximum time spent charging.
@export var charge_time: float = 1.5
## Maximum distance travelled during one charge.
@export var charge_distance: float = 55.0
## Delay before fresh target acquisition resumes.
@export var recovery_time: float = 1.0
## Time movement and detection are suspended after nonlethal damage.
@export var hurt_time: float = 0.45

var phase: ChargePhase = ChargePhase.PATROL
var _elapsed: float = 0.0
var _heading: Vector3 = Vector3.FORWARD
var _patrol_forward: Vector3 = Vector3.ZERO
var _charge_origin: Vector3 = Vector3.ZERO
var _returning: bool = false
var _actor: CharacterBody3D


func wants_perception() -> bool:
	return phase == ChargePhase.PATROL or phase == ChargePhase.WINDUP


func notify_hurt() -> void:
	_enter_phase(ChargePhase.HURT)
	if _actor and _actor._attacks:
		_actor._attacks.cancel_all()


func physics_tick(delta: float, actor: CharacterBody3D, target: Node3D, home: Vector3, attacks: EnemyAttackController, intent: EnemyIntent) -> void:
	_actor = actor
	intent.clear()
	_elapsed += delta
	var up: Vector3 = actor.up_direction.normalized()
	if _patrol_forward.is_zero_approx():
		_patrol_forward = -actor.global_basis.z
	match phase:
		ChargePhase.PATROL:
			if is_instance_valid(target):
				_enter_phase(ChargePhase.WINDUP)
			else:
				var destination: Vector3 = home if _returning else home + _patrol_forward * maxf(patrol_distance, 0.0)
				var offset: Vector3 = (destination - actor.global_position).slide(up)
				if offset.length() < 1.0:
					_returning = not _returning
				else:
					intent.move_direction = offset.normalized()
					var locomotion: GroundedEnemyLocomotion = actor._locomotion as GroundedEnemyLocomotion
					if locomotion and not locomotion.has_support_in_direction(intent.move_direction):
						_returning = true
						intent.move_direction = Vector3.ZERO
					intent.face_direction = intent.move_direction
					intent.speed_ratio = patrol_speed_ratio
				return
		ChargePhase.RECOVER, ChargePhase.HURT:
			if attacks:
				attacks.cancel_all()
			if _elapsed >= (hurt_time if phase == ChargePhase.HURT else recovery_time):
				_enter_phase(ChargePhase.PATROL)
			return

	if phase == ChargePhase.WINDUP:
		if not is_instance_valid(target):
			_enter_phase(ChargePhase.RECOVER)
			return
		var aim: Vector3 = (target.global_position - actor.global_position).slide(up)
		intent.face_direction = aim
		if _elapsed < maxf(windup_time, 0.0):
			return
		_heading = aim.normalized() if not aim.is_zero_approx() else -actor.global_basis.z
		_charge_origin = actor.global_position
		_enter_phase(ChargePhase.CHARGE)
		if attacks:
			attacks.try_start(target)

	if phase == ChargePhase.CHARGE:
		var blocked: bool = false
		var locomotion: GroundedEnemyLocomotion = actor._locomotion as GroundedEnemyLocomotion
		for index: int in actor.get_slide_collision_count():
			var contact: KinematicCollision3D = actor.get_slide_collision(index)
			if contact.get_normal().dot(_heading) < -0.5 and (
				not locomotion or not locomotion.is_surface_traversable(contact.get_collider(), contact.get_normal())
			):
				blocked = true
		var heading: Vector3 = _heading.slide(up).normalized()
		if locomotion:
			var speed: float = actor.velocity.slide(up).length()
			var stopping_distance: float = speed * speed / maxf(2.0 * locomotion.deceleration, 0.001)
			var lookahead: float = locomotion.ledge_probe_distance + stopping_distance + speed * delta
			if not locomotion.has_support_in_direction(heading, lookahead):
				blocked = true
		if blocked or _elapsed >= maxf(charge_time, 0.0) or actor.global_position.distance_to(_charge_origin) >= maxf(charge_distance, 0.0):
			_enter_phase(ChargePhase.RECOVER)
			if attacks:
				attacks.cancel_all()
			return
		intent.move_direction = heading
		intent.face_direction = heading
		intent.speed_ratio = 1.0


func get_state_tag() -> StringName:
	match phase:
		ChargePhase.WINDUP: return &"alert"
		ChargePhase.CHARGE: return &"charge"
		ChargePhase.RECOVER: return &"recover"
		ChargePhase.HURT: return &"hurt"
		_: return &"patrol"


func reset_brain() -> void:
	super.reset_brain()
	_patrol_forward = Vector3.ZERO
	_returning = false
	_enter_phase(ChargePhase.PATROL)


func _enter_phase(next: ChargePhase) -> void:
	phase = next
	_elapsed = 0.0
	if (phase == ChargePhase.RECOVER or phase == ChargePhase.HURT) and _actor and _actor._audio:
		_actor._audio.stop_one_shot()
	if not wants_perception() and _actor and _actor._perception:
		_actor._perception.clear()
	state_changed.emit(get_state_tag())

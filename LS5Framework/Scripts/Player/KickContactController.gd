class_name KickContactController
extends Node3D

@export_group("Kick Contacts")
## Character skeleton containing the kicking foot.
@export var skeleton: Skeleton3D
## Bone followed by the contact primitive.
@export var right_foot_bone: StringName = &"foot.r"
## Local sensor offset from the foot bone.
@export var foot_offset: Vector3 = Vector3.ZERO
## Contact radius during grounded Spin Kick.
@export var spin_radius: float = 1.25
## Contact radius during airborne Tornado Kick.
@export var tornado_radius: float = 1.35
## Contact radius during Uppercut Kick.
@export var uppercut_radius: float = 1.15
## Central impulse applied by Spin Kick and Tornado Kick.
@export var sweep_impulse_strength: float = 300.0
## Upward fraction of a sweeping kick impulse.
@export_range(0.0, 1.0, 0.01) var sweep_lift_fraction: float = 0.2
## Central impulse applied by Uppercut Kick.
@export var uppercut_impulse_strength: float = 300.0
## Upward fraction of the Uppercut impulse direction.
@export_range(0.0, 1.0, 0.01) var uppercut_lift_fraction: float = 0.85
## Layers queried for kick targets.
@export_flags_3d_physics var target_collision_mask: int = 0xFFFFFFFF
## Solid world layers that obstruct kick contacts.
@export_flags_3d_physics var obstruction_collision_mask: int = 17
## Maximum foot travel swept during one physics step.
@export var maximum_sweep_distance: float = 50.0
## Maximum contact query samples per physics step.
@export_range(1, 128, 1) var maximum_sweep_samples: int = 64

var _player: Node3D
var _attachment: BoneAttachment3D
var _sensor: Area3D
var _shape: SphereShape3D = SphereShape3D.new()
var _contact_active: bool = false
var _kick_kind: StringName = &""
var _kick_up: Vector3 = Vector3.UP
var _hit_targets: Dictionary = {}
var _previous_position: Vector3 = Vector3.ZERO
var _previous_player_position: Vector3 = Vector3.ZERO
var _has_previous_position: bool = false


func _ready() -> void:
	_player = get_parent() as Node3D
	process_physics_priority = 10
	if not skeleton or skeleton.find_bone(String(right_foot_bone)) < 0:
		push_warning("KickContacts: right-foot bone is unavailable.")
		return
	_attachment = BoneAttachment3D.new()
	_attachment.name = "KickFootAttachment"
	_attachment.bone_name = String(right_foot_bone)
	skeleton.add_child(_attachment)
	_sensor = Area3D.new()
	_sensor.name = "KickContactSensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = 0
	_sensor.monitoring = false
	_sensor.monitorable = false
	_sensor.position = foot_offset
	_attachment.add_child(_sensor)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = _shape
	_sensor.add_child(collision)


func begin_kick(kind: StringName, up: Vector3) -> void:
	_kick_kind = kind
	_kick_up = up.normalized()
	_hit_targets.clear()
	_has_previous_position = false
	_shape.radius = max(uppercut_radius if kind == &"uppercut" else (tornado_radius if kind == &"tornado" else spin_radius), 0.01)
	_contact_active = true


func set_contact_active(active: bool) -> void:
	if _contact_active != active:
		_has_previous_position = false
	_contact_active = active


func end_kick() -> void:
	_contact_active = false
	_has_previous_position = false
	_kick_kind = &""


func claim_target(target: Node) -> bool:
	if _kick_kind == &"":
		return true
	if not _contact_active or not target:
		return false
	var target_id: int = target.get_instance_id()
	if _hit_targets.has(target_id):
		return false
	_hit_targets[target_id] = true
	return true


func _physics_process(_delta: float) -> void:
	if not _contact_active or not _sensor or not _player or not _player._network_is_local_authority():
		_has_previous_position = false
		return
	if _player._is_dead or _player._hurt_active or not _player.is_attack_active():
		end_kick()
		return
	var position_now: Vector3 = _sensor.global_position
	var start: Vector3 = _previous_position if _has_previous_position else position_now
	var distance: float = start.distance_to(position_now)
	if distance > maximum_sweep_distance or (_has_previous_position and _previous_player_position.distance_to(_player.global_position) > maximum_sweep_distance):
		start = position_now
		distance = 0.0
	var samples: int = clampi(int(ceil(distance / max(_shape.radius * 0.5, 0.01))), 1, maximum_sweep_samples)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.collision_mask = target_collision_mask
	query.collide_with_areas = true
	query.exclude = [_player.get_rid(), _sensor.get_rid()]
	for sample: int in range(samples + 1):
		var sample_position: Vector3 = start.lerp(position_now, float(sample) / float(samples))
		query.transform = Transform3D(Basis.IDENTITY, sample_position)
		for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 64):
			_process_contact(hit.get("collider") as Node3D, sample_position)
			if not _contact_active:
				return
	_previous_position = position_now
	_previous_player_position = _player.global_position
	_has_previous_position = true


func _process_contact(collider: Node3D, origin: Vector3) -> void:
	if not collider or collider == _player or _player.is_ancestor_of(collider):
		return
	if collider is ActorHurtbox3D:
		if not _is_obstructed(origin, collider):
			(collider as ActorHurtbox3D).receive_player_attack(_player)
		return
	var target: Node3D = collider
	while target and not target.has_method("receive_kick_attack") and not (target is PhysicsBody3D):
		target = target.get_parent() as Node3D
	if not target or _is_obstructed(origin, target):
		return
	if target.has_method("receive_kick_attack"):
		target.call("receive_kick_attack", _player)
		return
	if not (target is RigidBody3D):
		return
	if target.has_method("is_carried") and bool(target.call("is_carried")):
		return
	var body: RigidBody3D = target as RigidBody3D
	if body.freeze and not body.has_method("apply_kick_impulse"):
		return
	if not claim_target(target):
		return
	var up: Vector3 = _kick_up if _kick_kind == &"uppercut" else _player.get_gravity_up()
	var outward: Vector3 = target.global_position - _player.global_position
	outward -= up * outward.dot(up)
	if outward.length_squared() < 0.0001:
		outward = _player._model_forward - up * _player._model_forward.dot(up)
	if outward.length_squared() < 0.0001:
		outward = up.cross(Vector3.RIGHT if abs(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD)
	var lift: float = uppercut_lift_fraction if _kick_kind == &"uppercut" else sweep_lift_fraction
	var direction: Vector3 = (outward.normalized() * (1.0 - lift) + up * lift).normalized()
	var strength: float = uppercut_impulse_strength if _kick_kind == &"uppercut" else sweep_impulse_strength
	var impulse: Vector3 = direction * max(strength, 0.0)
	if body.has_method("apply_kick_impulse"):
		body.call("apply_kick_impulse", impulse)
	else:
		body.sleeping = false
		body.apply_central_impulse(impulse)


func _is_obstructed(origin: Vector3, target: Node3D) -> bool:
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target.global_position, obstruction_collision_mask)
	var excluded: Array[RID] = [_player.get_rid(), _sensor.get_rid()]
	if target is CollisionObject3D:
		excluded.append((target as CollisionObject3D).get_rid())
	if target is ActorHurtbox3D and target.get_parent() is CollisionObject3D:
		excluded.append((target.get_parent() as CollisionObject3D).get_rid())
	ray.exclude = excluded
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _exit_tree() -> void:
	if is_instance_valid(_attachment) and not _attachment.is_queued_for_deletion():
		_attachment.queue_free()

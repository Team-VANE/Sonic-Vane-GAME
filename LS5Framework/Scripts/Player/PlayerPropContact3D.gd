extends Node
class_name PlayerPropContact3D

## Solid layers queried for prop body contacts.
@export_flags_3d_physics var target_mask: int = 131
## Maximum samples used by a body sweep.
@export_range(1, 256, 1) var maximum_samples: int = 128
## Displacement treated as a teleport instead of an attack sweep.
@export var teleport_distance: float = 200.0

var _player: Node3D
var _previous: Vector3 = Vector3.ZERO
var _last_id: StringName = &""
var _pending_id: StringName = &""
var _pending_airborne: bool = false
var _pending_attack_speed: float = 0.0
var _prepared_frame: int = -1
var _shape: SphereShape3D = SphereShape3D.new()
var _attack_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _obstruction_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _body_contact_frames: Dictionary[int, int] = {}

func _ready() -> void:
	_player = get_parent() as Node3D
	_previous = _player.global_position
	_attack_query.shape = _shape
	_attack_query.exclude = [_player.get_rid()]
	_obstruction_ray.collision_mask = 17
	process_physics_priority = 20

func claim_body_attack_contact(target: Node3D) -> bool:
	var frame: int = Engine.get_physics_frames()
	var target_id: int = target.get_instance_id()
	var previous_frame: int = _body_contact_frames.get(target_id, -2)
	_body_contact_frames[target_id] = frame
	return previous_frame < frame - 1


static func body_attack_id(player: Node3D) -> StringName:
	if player.get("_is_dead") or player.get("_hurt_active"):
		return &""
	if player.get("_homing_active"):
		return &"homing"
	var bounce: int = int(player.get("_bounce_state"))
	if bounce != 0:
		if bounce == int(player.BounceState.STOMP):
			return &"stomp"
		return &"bounce_rebound" if bounce == int(player.BounceState.REBOUND) else &"bounce"
	if player.get("_bounce_rebound_attack_active"):
		return &"bounce_rebound"
	var action: CharacterAction = player.get("_active_action") as CharacterAction
	if action and action.prop_body_attack_id != &"" and player.is_attack_active():
		return action.prop_body_attack_id
	var flags: int = int(player.get("_attack_sources"))
	var sources: Dictionary = {player.AttackSource.JUMP_DASH: &"jump_dash", player.AttackSource.LIGHTSPEED: &"lightspeed_dash", player.AttackSource.SPINDASH: &"spindash", player.AttackSource.ROLL: &"roll", player.AttackSource.JUMP: &"jump", player.AttackSource.AIR_UNCURL: &"air_uncurl", player.AttackSource.ENEMY_CHAIN: &"enemy_chain"}
	for flag: int in sources:
		if flags & flag:
			return sources[flag]
	return &""

func prepare() -> void:
	var id: StringName = body_attack_id(_player)
	if id != _last_id and id != &"":
		_player.set_meta(StringName("prop_activation_" + String(id)), Engine.get_physics_frames())
	_last_id = id
	var frame: int = Engine.get_physics_frames()
	if _prepared_frame != frame:
		_pending_id = id
		_pending_airborne = not bool(_player.get("attached"))
		_pending_attack_speed = _player.velocity.length() if id != &"" else 0.0
		_prepared_frame = frame
	elif id != &"":
		_pending_id = id
		_pending_airborne = _pending_airborne or not bool(_player.get("attached"))
		_pending_attack_speed = maxf(_pending_attack_speed, _player.velocity.length())

func _physics_process(_delta: float) -> void:
	var current: Vector3 = _player.global_position
	var frame: int = Engine.get_physics_frames()
	if frame % 60 == 0:
		for target_id: int in _body_contact_frames.keys():
			if _body_contact_frames[target_id] < frame - 1:
				_body_contact_frames.erase(target_id)
	var prepared: bool = _prepared_frame == frame
	var id: StringName = _pending_id if prepared else body_attack_id(_player)
	if id == &"" or not _player._network_is_local_authority() or _player._is_dead or _player._hurt_active or _player._debug_mode or _player._level_load_suspended:
		_previous = current
		return
	var radius: float = _player.get_main_collision_world_radius()
	var offset: Vector3 = _player.get_main_collision_world_center() - current
	if radius <= 0.0:
		var body_shape: CollisionShape3D = _player.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		if body_shape and not body_shape.disabled:
			if body_shape.shape is SphereShape3D or body_shape.shape is CapsuleShape3D:
				radius = body_shape.shape.radius * body_shape.global_basis.x.length()
				offset = body_shape.global_position - current
	for child: Node in _player.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape is SphereShape3D:
			radius = maxf(radius, child.shape.radius * child.global_basis.x.length())
	var speed: float = _player.velocity.length()
	if prepared:
		speed = maxf(speed, _pending_attack_speed)
	var radius_scale: float = _player.get_attack_hitbox_multiplier(speed)
	var expanded_attack: bool = radius_scale > 1.0 and _player.is_attack_active()
	_shape.radius = maxf(radius, 0.5) * radius_scale
	var start: Vector3 = _previous if _previous.distance_to(current) <= teleport_distance else current
	var count: int = clampi(ceili(start.distance_to(current) / maxf(_shape.radius * 0.5, 0.05)), 0, maximum_samples)
	_attack_query.collision_mask = target_mask | ActorHurtbox3D.BODY_ATTACK_TARGET_LAYER if expanded_attack else target_mask
	_attack_query.collide_with_areas = expanded_attack
	var seen: Dictionary = {}
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	for index: int in range(count + 1):
		var point: Vector3 = start.lerp(current, float(index) / float(count)) if count > 0 else current
		_attack_query.transform = Transform3D(Basis.IDENTITY, point + offset)
		for result: Dictionary in space.intersect_shape(_attack_query, 64):
			var target: CollisionObject3D = result.get("collider") as CollisionObject3D
			if not target or seen.has(target.get_instance_id()):
				continue
			if target is PropBody3D and target.is_destroyed:
				continue
			if not target is PropBody3D and not (expanded_attack and (target is ActorHurtbox3D or target is ItemMonitor)):
				continue
			if _is_attack_obstructed(space, point + offset, target):
				continue
			seen[target.get_instance_id()] = true
			if target is ActorHurtbox3D:
				target.receive_player_attack(_player, true)
			elif target is ItemMonitor:
				target.receive_player_attack(_player)
			else:
				var hit: PropHit = PropHit.from_player(_player, id)
				hit.was_airborne = _pending_airborne or hit.was_airborne
				hit.position = point
				hit.normal = (point - target.global_position).normalized()
				target.receive_prop_hit(hit)
	_previous = current


func _is_attack_obstructed(space: PhysicsDirectSpaceState3D, origin: Vector3, target: CollisionObject3D) -> bool:
	var destination: Vector3 = target.global_position
	if target is ItemMonitor:
		destination = target.get_homing_target_position(origin)
	_obstruction_ray.from = origin
	_obstruction_ray.to = destination
	var exclusions: Array[RID] = [_player.get_rid(), target.get_rid()]
	if target is ActorHurtbox3D and target.get_parent() is CollisionObject3D:
		exclusions.append(target.get_parent().get_rid())
	_obstruction_ray.exclude = exclusions
	return not space.intersect_ray(_obstruction_ray).is_empty()


func resolve_before_move(motion: Vector3) -> Array[PhysicsBody3D]:
	var ignored: Array[PhysicsBody3D] = []
	if not _player._network_is_local_authority():
		return ignored
	prepare()
	var id: StringName = body_attack_id(_player)
	if id == &"":
		return ignored
	var source_velocity: Vector3 = _player.velocity
	var parameters: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	parameters.from = _player.global_transform
	parameters.motion = motion
	parameters.margin = _player.safe_margin
	parameters.recovery_as_collision = true
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	for index: int in range(maximum_samples):
		if not PhysicsServer3D.body_test_motion(_player.get_rid(), parameters, result):
			break
		var prop: PropBody3D = result.get_collider() as PropBody3D
		if not prop:
			break
		if not prop.is_destroyed:
			var hit: PropHit = PropHit.from_player(_player, id)
			hit.position = result.get_collision_point()
			hit.normal = result.get_collision_normal()
			prop.receive_prop_hit(hit)
		if not prop.is_destroyed:
			break
		parameters.exclude_bodies.append(prop.get_rid())
		if prop not in _player.get_collision_exceptions():
			_player.add_collision_exception_with(prop)
			ignored.append(prop)
		if not source_velocity.is_equal_approx(_player.velocity):
			break
	return ignored

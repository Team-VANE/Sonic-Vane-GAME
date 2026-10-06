extends Node3D
class_name EnemyProjectile

signal impacted(collider: Node, position: Vector3, normal: Vector3)

@export_group("Motion")
## Initial travel speed used when no launch velocity is supplied.
@export var initial_speed: float = 22.0
## Acceleration applied along the current travel direction.
@export var forward_acceleration: float = 0.0
## Maximum speed reached through forward acceleration. Zero disables the cap.
@export var maximum_speed: float = 0.0
## Linear drag applied to projectile velocity.
@export var drag: float = 0.0
## Projectile lifetime before automatic removal. Zero disables the timer.
@export var lifetime_sec: float = 6.0
## Rotates the projectile visual to face its velocity.
@export var align_to_velocity: bool = true

@export_group("Homing")
## Enables steering toward an assigned target.
@export var homing_enabled: bool = false
## Maximum homing turn speed in degrees per second.
@export var homing_turn_speed_deg: float = 120.0
## Delay before homing steering begins.
@export var homing_delay_sec: float = 0.0
## Seconds of target velocity used to lead the aim point.
@export var target_lead_sec: float = 0.0
## Stops homing when the target becomes invalid.
@export var clear_invalid_target: bool = true

@export_group("Gravity")
## Applies a constant gravity acceleration to this projectile.
@export var gravity_enabled: bool = false
## Up direction opposite projectile gravity.
@export var gravity_up: Vector3 = Vector3.UP
## Projectile gravity acceleration.
@export var gravity_strength: float = 20.0

@export_group("Collision")
## Physics layers checked by swept collision and the projectile hitbox.
@export_flags_3d_physics var collision_mask: int = 5
## Prevents high-speed tunneling with a ray sweep each physics frame.
@export var swept_collision_enabled: bool = true
## Distance retained from a surface after a swept impact.
@export var collision_skin: float = 0.02
## Number of valid targets the projectile can pass through before removal.
@export_range(0, 32, 1) var pierce_count: int = 0
## Number of world surfaces the projectile can bounce from before removal.
@export_range(0, 32, 1) var bounce_count: int = 0
## Velocity retained after a world-surface bounce.
@export_range(0.0, 1.0, 0.01) var bounce_velocity_retention: float = 0.75
## Removes the projectile when it hits a non-damageable world surface.
@export var destroy_on_world_impact: bool = true
## Area used for overlap collision in addition to swept collision.
@export var hitbox_path: NodePath = NodePath("Hitbox")

@export_group("Damage")
## Damage applied to valid targets.
@export var damage_amount: int = 1
## Primary group accepted as a damage target.
@export var target_group_primary: StringName = &"player"
## Secondary group accepted as a damage target.
@export var target_group_secondary: StringName = &"Player"
## Prevents damage while the target's attack state is active.
@export var damage_only_if_target_not_attacking: bool = false
## Removes the projectile when a valid target is invulnerable.
@export var consume_on_invulnerable_target: bool = true

@export_group("Impact Presentation")
## Scene spawned at each accepted impact.
@export var impact_effect_scene: PackedScene
## Sound emitted at each accepted impact.
@export var impact_sound: AudioStream
## Audio bus used by temporary impact sounds.
@export var impact_sound_bus: StringName = &"SFX"
## Maximum audible distance for temporary impact sounds.
@export var impact_sound_max_distance: float = 48.0

var velocity: Vector3 = Vector3.ZERO
var target: Node3D = null
var instigator: CollisionObject3D = null
var _lifetime_timer: float = 0.0
var _homing_timer: float = 0.0
var _remaining_pierces: int = 0
var _remaining_bounces: int = 0
var _hitbox: Area3D = null
var _hit_instance_ids: Dictionary = {}
var _consumed: bool = false


func _ready() -> void:
	_lifetime_timer = max(lifetime_sec, 0.0)
	_homing_timer = max(homing_delay_sec, 0.0)
	_remaining_pierces = max(pierce_count, 0)
	_remaining_bounces = max(bounce_count, 0)
	if velocity.length() < 0.001:
		velocity = -global_basis.z * max(initial_speed, 0.0)
	if hitbox_path != NodePath(""):
		_hitbox = get_node_or_null(hitbox_path) as Area3D
	if _hitbox:
		_hitbox.collision_mask = collision_mask
		if not _hitbox.body_entered.is_connected(_on_hitbox_body_entered):
			_hitbox.body_entered.connect(_on_hitbox_body_entered)


func _physics_process(delta: float) -> void:
	if _consumed:
		return
	if lifetime_sec > 0.0:
		_lifetime_timer = max(_lifetime_timer - delta, 0.0)
		if _lifetime_timer <= 0.0:
			_consume()
			return
	_homing_timer = max(_homing_timer - delta, 0.0)
	_update_homing(delta)
	_update_motion(delta)
	var motion: Vector3 = velocity * delta
	if motion.length() <= 0.000001:
		return
	var start_position: Vector3 = global_position
	var end_position: Vector3 = start_position + motion
	if swept_collision_enabled:
		var hit: Dictionary = _cast_motion(start_position, end_position)
		if not hit.is_empty():
			_handle_swept_hit(hit)
			return
	global_position = end_position
	_align_visual_to_velocity()


func set_velocity(value: Vector3) -> void:
	velocity = value


func set_direction(direction: Vector3) -> void:
	if direction.length() < 0.001:
		return
	var speed: float = velocity.length()
	if speed < 0.001:
		speed = max(initial_speed, 0.0)
	velocity = direction.normalized() * speed


func set_target(value: Node3D) -> void:
	target = value


func set_owner_actor(value: CollisionObject3D) -> void:
	instigator = value


func set_lifetime(value: float) -> void:
	lifetime_sec = max(value, 0.0)
	_lifetime_timer = lifetime_sec


func set_homing_turn_speed(value: float) -> void:
	homing_enabled = value > 0.0
	homing_turn_speed_deg = max(value, 0.0)


func set_curve_strength(value: float) -> void:
	set_homing_turn_speed(value * 60.0)


func set_gravity(new_gravity_up: Vector3, new_strength: float) -> void:
	if new_gravity_up.length() >= 0.001:
		gravity_up = new_gravity_up.normalized()
	gravity_strength = max(new_strength, 0.0)


func _update_homing(delta: float) -> void:
	if not homing_enabled or _homing_timer > 0.0:
		return
	if target == null or not is_instance_valid(target):
		if clear_invalid_target:
			target = null
		return
	var aim_position: Vector3 = target.global_position
	if target_lead_sec > 0.0:
		var target_velocity: Vector3 = _get_node_velocity(target)
		aim_position += target_velocity * target_lead_sec
	var desired_direction: Vector3 = aim_position - global_position
	if desired_direction.length() < 0.001 or velocity.length() < 0.001:
		return
	var current_direction: Vector3 = velocity.normalized()
	var target_direction: Vector3 = desired_direction.normalized()
	var angle: float = acos(clamp(current_direction.dot(target_direction), -1.0, 1.0))
	if angle <= 0.000001:
		return
	var maximum_turn: float = deg_to_rad(max(homing_turn_speed_deg, 0.0)) * delta
	var weight: float = min(maximum_turn / angle, 1.0)
	var speed: float = velocity.length()
	velocity = current_direction.slerp(target_direction, weight).normalized() * speed


func _update_motion(delta: float) -> void:
	var speed: float = velocity.length()
	if speed > 0.001 and forward_acceleration != 0.0:
		speed += forward_acceleration * delta
		if maximum_speed > 0.0:
			speed = min(speed, maximum_speed)
		speed = max(speed, 0.0)
		velocity = velocity.normalized() * speed
	if drag > 0.0:
		velocity = velocity.move_toward(Vector3.ZERO, drag * delta)
	if gravity_enabled:
		var up: Vector3 = gravity_up.normalized()
		if up.length() < 0.001:
			up = Vector3.UP
		velocity -= up * max(gravity_strength, 0.0) * delta


func _cast_motion(from: Vector3, to: Vector3) -> Dictionary:
	var world: World3D = get_world_3d()
	if world == null:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var excluded: Array[RID] = []
	if instigator and is_instance_valid(instigator):
		excluded.append(instigator.get_rid())
	if _hitbox:
		excluded.append(_hitbox.get_rid())
	query.exclude = excluded
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)


func _handle_swept_hit(hit: Dictionary) -> void:
	var collider: Node = hit.get("collider") as Node
	var position: Vector3 = hit.get("position", global_position) as Vector3
	var normal: Vector3 = hit.get("normal", -velocity.normalized()) as Vector3
	global_position = position + normal.normalized() * max(collision_skin, 0.0)
	if _is_valid_target(collider):
		if not _try_damage_target(collider):
			global_position += velocity.normalized() * max(collision_skin * 2.0, 0.02)
			return
		_emit_impact(collider, position, normal)
		if _remaining_pierces > 0:
			_remaining_pierces -= 1
			global_position += velocity.normalized() * max(collision_skin * 2.0, 0.02)
			return
		_consume()
		return
	if _remaining_bounces > 0 and normal.length() >= 0.001:
		_remaining_bounces -= 1
		velocity = velocity.bounce(normal.normalized()) * clamp(bounce_velocity_retention, 0.0, 1.0)
		_emit_impact(collider, position, normal)
		_align_visual_to_velocity()
		return
	_emit_impact(collider, position, normal)
	if destroy_on_world_impact:
		_consume()


func _on_hitbox_body_entered(body: Node3D) -> void:
	if _consumed or body == instigator:
		return
	if _is_valid_target(body) and _try_damage_target(body):
		_emit_impact(body, global_position, -velocity.normalized())
		if _remaining_pierces > 0:
			_remaining_pierces -= 1
			return
		_consume()


func _try_damage_target(body: Node) -> bool:
	if body == null or not _is_valid_target(body):
		return false
	var body_id: int = body.get_instance_id()
	if _hit_instance_ids.has(body_id):
		return true
	_hit_instance_ids[body_id] = true
	if _is_target_invulnerable(body):
		return consume_on_invulnerable_target
	if damage_only_if_target_not_attacking and _is_target_attacking(body):
		return true
	if body.has_method("apply_damage"):
		body.call("apply_damage", max(damage_amount, 1), instigator if instigator else self)
	return true


func _is_valid_target(body: Node) -> bool:
	if body == null:
		return false
	return (
		(target_group_primary != &"" and body.is_in_group(target_group_primary))
		or (target_group_secondary != &"" and body.is_in_group(target_group_secondary))
	)


func _is_target_invulnerable(body: Node) -> bool:
	if not body.has_method("is_hurt_invulnerable"):
		return false
	var result: Variant = body.call("is_hurt_invulnerable")
	return result is bool and bool(result)


func _is_target_attacking(body: Node) -> bool:
	if not body.has_method("is_attack_active"):
		return false
	var result: Variant = body.call("is_attack_active")
	return result is bool and bool(result)


func _emit_impact(collider: Node, position: Vector3, normal: Vector3) -> void:
	impacted.emit(collider, position, normal)
	if impact_effect_scene:
		var effect: Node = impact_effect_scene.instantiate()
		var parent: Node = get_parent()
		if parent:
			parent.add_child(effect)
			if effect is Node3D:
				var effect_3d: Node3D = effect as Node3D
				var up: Vector3 = normal.normalized() if normal.length() >= 0.001 else Vector3.UP
				var forward: Vector3 = velocity.normalized()
				forward -= up * forward.dot(up)
				if forward.length() < 0.001:
					forward = up.cross(Vector3.RIGHT)
				effect_3d.global_transform = Transform3D(Basis().looking_at(forward.normalized(), up), position)
	if impact_sound:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.stream = impact_sound
		player.bus = String(impact_sound_bus)
		player.max_distance = max(impact_sound_max_distance, 0.0)
		var sound_parent: Node = get_parent()
		if sound_parent:
			sound_parent.add_child(player)
			player.global_position = position
			player.finished.connect(player.queue_free)
			player.play()


func _align_visual_to_velocity() -> void:
	if not align_to_velocity or velocity.length() < 0.001:
		return
	var up: Vector3 = gravity_up.normalized()
	if up.length() < 0.001 or abs(up.dot(velocity.normalized())) > 0.995:
		up = Vector3.UP
		if abs(up.dot(velocity.normalized())) > 0.995:
			up = Vector3.RIGHT
	global_basis = Basis().looking_at(velocity.normalized(), up).orthonormalized()


func _get_node_velocity(node: Node) -> Vector3:
	if node is CharacterBody3D:
		return (node as CharacterBody3D).velocity
	if node is RigidBody3D:
		return (node as RigidBody3D).linear_velocity
	for property: Dictionary in node.get_property_list():
		if StringName(property.get("name", &"")) == &"velocity":
			var value: Variant = node.get("velocity")
			if value is Vector3:
				return value as Vector3
	return Vector3.ZERO


func _consume() -> void:
	if _consumed:
		return
	_consumed = true
	set_physics_process(false)
	if _hitbox:
		_hitbox.set_deferred("monitoring", false)
	queue_free()

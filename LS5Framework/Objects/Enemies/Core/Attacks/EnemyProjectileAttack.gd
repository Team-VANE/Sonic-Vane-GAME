extends EnemyAttack
class_name EnemyProjectileAttack

@export_group("Projectile")
## Projectile scene instantiated when the active attack window opens.
@export var projectile_scene: PackedScene
## Marker on the owning actor used as the projectile spawn transform.
@export var spawn_path: NodePath = NodePath("Muzzle")
## Launch speed assigned to spawned projectiles.
@export var projectile_speed: float = 22.0
## Lifetime assigned to spawned projectiles. Zero keeps the scene default.
@export var projectile_lifetime_sec: float = 6.0
## Homing turn speed assigned to spawned projectiles. Zero disables homing.
@export var projectile_homing_turn_speed_deg: float = 0.0
## Number of projectiles released in one active window.
@export_range(1, 32, 1) var projectiles_per_shot: int = 1
## Total random spread cone in degrees.
@export_range(0.0, 180.0, 0.1) var spread_angle_deg: float = 0.0
## Copies the actor's current gravity frame to gravity-enabled projectiles.
@export var inherit_actor_gravity_frame: bool = true


func _on_active_window_opened() -> void:
	if projectile_scene == null or actor == null:
		return
	var spawn_transform: Transform3D = actor.global_transform
	if spawn_path != NodePath(""):
		var spawn: Node3D = actor.get_node_or_null(spawn_path) as Node3D
		if spawn:
			spawn_transform = spawn.global_transform
	var aim_direction: Vector3 = -spawn_transform.basis.z
	if target and is_instance_valid(target):
		var target_offset: Vector3 = target.global_position - spawn_transform.origin
		if target_offset.length() >= 0.001:
			aim_direction = target_offset.normalized()
	for projectile_index: int in range(max(projectiles_per_shot, 1)):
		_spawn_projectile(spawn_transform, _apply_spread(aim_direction, projectile_index))
	if actor.has_method("notify_projectile_fired"):
		actor.call("notify_projectile_fired")


func _spawn_projectile(spawn_transform: Transform3D, direction: Vector3) -> void:
	var projectile: Node = projectile_scene.instantiate()
	if projectile == null:
		return
	var parent: Node = actor.get_parent()
	if parent == null:
		parent = actor
	parent.add_child(projectile)
	if projectile is Node3D:
		(projectile as Node3D).global_transform = spawn_transform
	if projectile.has_method("set_velocity"):
		projectile.call("set_velocity", direction.normalized() * max(projectile_speed, 0.0))
	if projectile.has_method("set_target"):
		projectile.call("set_target", target)
	if projectile.has_method("set_owner_actor"):
		projectile.call("set_owner_actor", actor)
	if projectile_lifetime_sec > 0.0 and projectile.has_method("set_lifetime"):
		projectile.call("set_lifetime", projectile_lifetime_sec)
	if projectile.has_method("set_homing_turn_speed"):
		projectile.call("set_homing_turn_speed", projectile_homing_turn_speed_deg)
	if inherit_actor_gravity_frame and projectile.has_method("set_gravity") and actor.has_method("get_gravity_up"):
		var gravity_up_value: Variant = actor.call("get_gravity_up")
		var gravity_strength_value: float = 0.0
		if actor.has_method("get_effective_gravity_strength"):
			gravity_strength_value = float(actor.call("get_effective_gravity_strength"))
		if gravity_up_value is Vector3:
			projectile.call("set_gravity", gravity_up_value as Vector3, gravity_strength_value)


func _apply_spread(direction: Vector3, projectile_index: int) -> Vector3:
	if spread_angle_deg <= 0.0 or projectiles_per_shot <= 1:
		return direction.normalized()
	var up: Vector3 = Vector3.UP
	if actor.has_method("get_gravity_up"):
		var up_value: Variant = actor.call("get_gravity_up")
		if up_value is Vector3:
			up = up_value as Vector3
	if up.length() < 0.001:
		up = Vector3.UP
	up = up.normalized()
	var right: Vector3 = direction.cross(up)
	if right.length() < 0.001:
		right = direction.cross(Vector3.RIGHT)
	right = right.normalized()
	var spread_fraction: float = 0.0
	if projectiles_per_shot > 1:
		spread_fraction = float(projectile_index) / float(projectiles_per_shot - 1) - 0.5
	var yaw_angle: float = deg_to_rad(spread_angle_deg) * spread_fraction
	return direction.rotated(up, yaw_angle).rotated(right, randf_range(-abs(yaw_angle) * 0.2, abs(yaw_angle) * 0.2)).normalized()

extends Area3D
class_name ActorHurtbox3D

signal contact_damage_applied(target: Node, amount: int)

@export_group("Player Interaction")
## Primary group recognized as an enemy target.
@export var player_group_primary: StringName = &"player"
## Secondary group recognized as an enemy target.
@export var player_group_secondary: StringName = &"Player"
## Damages players that touch the hurtbox without attacking.
@export var contact_damage_enabled: bool = true
## Damage applied by ordinary contact.
@export var contact_damage_amount: int = 1
## Temporarily disables the owning enemy's boundary after applying contact damage.
@export var disable_owner_collision_after_contact_damage: bool = true
## Time the owning enemy's boundary remains disabled after contact damage.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:s") var contact_damage_collision_disable_sec: float = 0.2
## Bounces airborne players after ordinary contact.
@export var bounce_airborne_players: bool = true
## Upward bounce speed requested after ordinary airborne contact.
@export var bounce_player_speed: float = 12.0
## Damage applied to the owning actor by an attacking player.
@export var incoming_player_attack_damage: int = 1
## Temporarily disables physical collision after an incoming attack.
@export var disable_collision_when_attacked: bool = true
## Duration of physical collision suppression after an incoming attack.
@export var collision_disable_time_sec: float = 0.2

@export_group("Dynamic Impacts")
## Enables damage from fast dynamic physics objects.
@export var dynamic_body_damage_enabled: bool = true
## Group identifying non-rigid dynamic impact objects.
@export var dynamic_body_group: StringName = &"dynamic_physics_object"
## Minimum relative impact speed required to cause damage.
@export var dynamic_body_damage_min_speed: float = 20.0
## Relative impact speed that defeats the actor immediately. Zero disables it.
@export var dynamic_body_destroy_min_speed: float = 0.0
## Damage applied by dynamic impacts below the destroy threshold.
@export var dynamic_body_damage_amount: int = 1
## Cooldown between dynamic impact damage events.
@export var dynamic_body_damage_cooldown: float = 0.15

var _actor: Node3D = null
var _impact_cooldown: float = 0.0


func setup(actor: Node3D) -> void:
	_actor = actor
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func physics_tick(delta: float) -> void:
	_impact_cooldown = max(_impact_cooldown - delta, 0.0)


func reset_hurtbox() -> void:
	_impact_cooldown = 0.0


func _on_body_entered(body: Node) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if _actor.has_method("is_dead") and bool(_actor.call("is_dead")):
		return
	if _try_dynamic_impact(body):
		return
	if not _is_player(body) or (_is_player_invulnerable(body) and not _is_player_invincible(body)):
		return
	if _is_player_attacking(body):
		receive_player_attack(body)
		return
	if contact_damage_enabled and body.has_method("apply_damage"):
		var applied_amount: int = max(contact_damage_amount, 1)
		if disable_owner_collision_after_contact_damage and _actor.has_method("disable_collision_for"):
			_actor.call("disable_collision_for", max(contact_damage_collision_disable_sec, 0.0))
		body.call("apply_damage", applied_amount, _actor)
		contact_damage_applied.emit(body, applied_amount)
	if bounce_airborne_players and _is_player_airborne(body) and body.has_method("apply_enemy_bounce"):
		body.call("apply_enemy_bounce", _actor.global_position, bounce_player_speed, _actor)


func _try_dynamic_impact(body: Node) -> bool:
	if not dynamic_body_damage_enabled or _impact_cooldown > 0.0 or body == null or _is_player(body):
		return false
	if not (body is RigidBody3D) and (dynamic_body_group == &"" or not body.is_in_group(dynamic_body_group)):
		return false
	var impact_velocity: Vector3 = Vector3.ZERO
	if body.has_method("get_dynamic_impact_velocity"):
		var impact_value: Variant = body.call("get_dynamic_impact_velocity")
		if impact_value is Vector3:
			impact_velocity = impact_value as Vector3
	elif body is RigidBody3D:
		impact_velocity = (body as RigidBody3D).linear_velocity
	elif _object_has_property(body, &"velocity"):
		var velocity_value: Variant = body.get("velocity")
		if velocity_value is Vector3:
			impact_velocity = velocity_value as Vector3
	var actor_velocity: Vector3 = Vector3.ZERO
	if _object_has_property(_actor, &"velocity"):
		var actor_velocity_value: Variant = _actor.get("velocity")
		if actor_velocity_value is Vector3:
			actor_velocity = actor_velocity_value as Vector3
	var impact_speed: float = (impact_velocity - actor_velocity).length()
	if impact_speed < max(dynamic_body_damage_min_speed, 0.0):
		return false
	var damage: int = max(dynamic_body_damage_amount, 1)
	if dynamic_body_destroy_min_speed > 0.0 and impact_speed >= dynamic_body_destroy_min_speed:
		damage = 1000000
	_actor.call("apply_damage", damage, body)
	if disable_collision_when_attacked and not _is_actor_dead() and _actor.has_method("disable_collision_for"):
		_actor.call("disable_collision_for", collision_disable_time_sec)
	_impact_cooldown = max(dynamic_body_damage_cooldown, 0.0)
	return true


func _is_player(body: Node) -> bool:
	if body == null:
		return false
	if body.has_meta(&"is_buddy") and bool(body.get_meta(&"is_buddy")):
		return true
	if body.has_meta(&"is_rival_actor") and bool(body.get_meta(&"is_rival_actor")):
		return true
	return (
		(player_group_primary != &"" and body.is_in_group(player_group_primary))
		or (player_group_secondary != &"" and body.is_in_group(player_group_secondary))
	)


func _is_actor_dead() -> bool:
	if _actor == null or not _actor.has_method("is_dead"):
		return false
	return bool(_actor.call("is_dead"))


func _is_player_attacking(body: Node) -> bool:
	if not body.has_method("is_attack_active"):
		return false
	var result: Variant = body.call("is_attack_active")
	return (result is bool and bool(result)) or _is_player_invincible(body)


func _is_player_invincible(body: Node) -> bool:
	return body.has_method("is_invincibility_active") and bool(body.call("is_invincibility_active"))


func _is_player_invulnerable(body: Node) -> bool:
	if not body.has_method("is_hurt_invulnerable"):
		return false
	var result: Variant = body.call("is_hurt_invulnerable")
	return result is bool and bool(result)


func _is_player_airborne(body: Node) -> bool:
	if body.has_method("is_airborne"):
		var result: Variant = body.call("is_airborne")
		if result is bool:
			return bool(result)
	if _object_has_property(body, &"attached"):
		return not bool(body.get("attached"))
	if body is CharacterBody3D:
		return not (body as CharacterBody3D).is_on_floor()
	return true


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false


func receive_player_attack(body: Node) -> bool:
	if not _actor or not is_instance_valid(_actor) or _is_actor_dead() or not _is_player(body) or not _is_player_attacking(body):
		return false
	if _is_player_invulnerable(body) and not _is_player_invincible(body):
		return false
	if body.has_method("_network_is_local_authority") and not bool(body.call("_network_is_local_authority")):
		return false
	if body.has_method("claim_kick_contact") and not bool(body.call("claim_kick_contact", _actor)):
		return false
	var destroyed: bool = bool(_actor.call("apply_damage", max(incoming_player_attack_damage, 1), body))
	if _is_player_airborne(body):
		if body.has_method("apply_enemy_attack_bounce"):
			body.call("apply_enemy_attack_bounce", destroyed, _actor)
		elif body.has_method("apply_enemy_bounce"):
			body.call("apply_enemy_bounce", _actor.global_position, bounce_player_speed, _actor)
	if disable_collision_when_attacked and not _is_actor_dead() and _actor.has_method("disable_collision_for"):
		_actor.call("disable_collision_for", collision_disable_time_sec)
	return true

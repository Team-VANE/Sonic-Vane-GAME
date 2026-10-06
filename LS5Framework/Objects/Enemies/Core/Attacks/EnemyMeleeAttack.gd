extends EnemyAttack
class_name EnemyMeleeAttack

@export_group("Melee")
## Area on the owning actor enabled during the active attack window.
@export var hitbox_path: NodePath = NodePath("MeleeHitbox")
## Damage applied to each target once per swing.
@export var damage_amount: int = 1
## Primary group accepted by the melee hitbox.
@export var target_group_primary: StringName = &"player"
## Secondary group accepted by the melee hitbox.
@export var target_group_secondary: StringName = &"Player"

var _hitbox: Area3D = null
var _hit_ids: Dictionary = {}


func setup(owner_actor: CharacterBody3D) -> void:
	super.setup(owner_actor)
	_hitbox = actor.get_node_or_null(hitbox_path) as Area3D if hitbox_path != NodePath("") else null
	if _hitbox:
		_hitbox.monitoring = false
		if not _hitbox.body_entered.is_connected(_on_body_entered):
			_hitbox.body_entered.connect(_on_body_entered)


func _on_active_window_opened() -> void:
	_hit_ids.clear()
	if _hitbox:
		_hitbox.monitoring = true


func _on_active_window_closed() -> void:
	if _hitbox:
		_hitbox.monitoring = false


func _on_body_entered(body: Node3D) -> void:
	if phase != Phase.ACTIVE or body == null:
		return
	if not _is_valid_target(body):
		return
	var body_id: int = body.get_instance_id()
	if _hit_ids.has(body_id):
		return
	_hit_ids[body_id] = true
	if body.has_method("is_hurt_invulnerable"):
		var invulnerable_value: Variant = body.call("is_hurt_invulnerable")
		if invulnerable_value is bool and bool(invulnerable_value):
			return
	if body.has_method("apply_damage"):
		body.call("apply_damage", max(damage_amount, 1), actor)


func _is_valid_target(body: Node) -> bool:
	return (
		(target_group_primary != &"" and body.is_in_group(target_group_primary))
		or (target_group_secondary != &"" and body.is_in_group(target_group_secondary))
	)


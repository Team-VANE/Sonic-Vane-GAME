extends EnemyOptionalComponent
class_name EnemySelfDestructOnContactDamage

signal self_destruct_triggered(target: Node)

@export_group("Self-Destruct")
## Enables self-destruction after the enemy successfully applies contact damage.
@export var enabled: bool = true
## Delay between successful contact damage and self-destruction.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var delay_sec: float = 0.0
## Bypasses the enemy health component's invulnerability setting.
@export var bypass_enemy_invulnerability: bool = true
## Credits the contacted player as the source of the enemy's defeat.
@export var credit_contact_target: bool = false

@export_group("Nodes")
## Hurtbox that reports successful contact damage. The path is relative to the enemy.
@export var hurtbox_path: NodePath = NodePath("Hurtbox")

var _hurtbox: ActorHurtbox3D = null
var _pending: bool = false
var _timer: float = 0.0
var _target_reference: WeakRef = null


func setup(owner_actor: CharacterBody3D) -> void:
	super.setup(owner_actor)
	_hurtbox = actor.get_node_or_null(hurtbox_path) as ActorHurtbox3D if hurtbox_path != NodePath("") else null
	if _hurtbox != null and not _hurtbox.contact_damage_applied.is_connected(_on_contact_damage_applied):
		_hurtbox.contact_damage_applied.connect(_on_contact_damage_applied)
	reset_component(&"setup")


func physics_tick(delta: float) -> void:
	if not _pending:
		return
	_timer = max(_timer - delta, 0.0)
	if _timer > 0.0:
		return
	var target: Node = _target_reference.get_ref() as Node if _target_reference != null else null
	_detonate(target)


func reset_component(_reason: StringName) -> void:
	_pending = false
	_timer = 0.0
	_target_reference = null


func _on_contact_damage_applied(target: Node, _amount: int) -> void:
	if not enabled or _pending or actor == null or not is_instance_valid(actor):
		return
	_pending = true
	_timer = max(delay_sec, 0.0)
	_target_reference = weakref(target) if target != null else null
	self_destruct_triggered.emit(target)
	if _timer <= 0.0:
		_detonate(target)


func _detonate(target: Node) -> void:
	_pending = false
	_timer = 0.0
	_target_reference = null
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_method("defeat"):
		var defeat_source: Node = target if credit_contact_target else null
		actor.call("defeat", defeat_source, bypass_enemy_invulnerability)

extends Node
class_name ActorHealth

signal health_changed(current_health: int, maximum_health: int)
signal damaged(amount: int, source: Node)
signal died(source: Node)
signal restored()

@export_group("Health")
## Maximum health restored when the owning actor is initialized or reset.
@export_range(1, 1000000, 1, "or_greater") var max_health: int = 1
## Prevents incoming damage while enabled.
@export var invulnerable: bool = false
## Minimum delay before the same source can damage this actor again.
@export var repeated_source_cooldown_sec: float = 0.08

var current_health: int = 1
var is_dead: bool = false
var _source_cooldowns: Dictionary = {}


func initialize() -> void:
	reset_health()


func physics_tick(delta: float) -> void:
	for source_id: Variant in _source_cooldowns.keys():
		var remaining: float = max(float(_source_cooldowns.get(source_id, 0.0)) - delta, 0.0)
		if remaining <= 0.0:
			_source_cooldowns.erase(source_id)
		else:
			_source_cooldowns[source_id] = remaining


func apply_damage(amount: int = 1, source: Node = null) -> bool:
	if is_dead or invulnerable:
		return false
	if source:
		var source_id: int = source.get_instance_id()
		if float(_source_cooldowns.get(source_id, 0.0)) > 0.0:
			return false
		_source_cooldowns[source_id] = max(repeated_source_cooldown_sec, 0.0)
	var applied_amount: int = max(amount, 1)
	current_health = max(current_health - applied_amount, 0)
	damaged.emit(applied_amount, source)
	health_changed.emit(current_health, max(max_health, 1))
	if current_health > 0:
		return false
	is_dead = true
	died.emit(source)
	return true


func kill(source: Node = null, bypass_invulnerability: bool = false) -> bool:
	if is_dead or (invulnerable and not bypass_invulnerability):
		return false
	var applied_amount: int = max(current_health, 1)
	current_health = 0
	damaged.emit(applied_amount, source)
	health_changed.emit(current_health, max(max_health, 1))
	is_dead = true
	died.emit(source)
	return true


func heal(amount: int = 1) -> void:
	if is_dead or amount <= 0:
		return
	current_health = min(current_health + amount, max(max_health, 1))
	health_changed.emit(current_health, max(max_health, 1))


func reset_health() -> void:
	current_health = max(max_health, 1)
	is_dead = false
	_source_cooldowns.clear()
	health_changed.emit(current_health, max(max_health, 1))
	restored.emit()

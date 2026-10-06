extends Node
class_name EnemyAttackController

signal attack_started(attack: EnemyAttack)
signal attack_active(attack: EnemyAttack)
signal attack_finished(attack: EnemyAttack)

var _actor: CharacterBody3D = null
var _attacks: Array[EnemyAttack] = []
var _active_attack: EnemyAttack = null


func setup(actor: CharacterBody3D) -> void:
	_actor = actor
	_attacks.clear()
	for child: Node in get_children():
		if child is EnemyAttack:
			var attack: EnemyAttack = child as EnemyAttack
			attack.setup(actor)
			attack.started.connect(_on_attack_started.bind(attack))
			attack.active_window_opened.connect(_on_attack_active.bind(attack))
			attack.finished.connect(_on_attack_finished.bind(attack))
			_attacks.append(attack)
	_attacks.sort_custom(func(a: EnemyAttack, b: EnemyAttack) -> bool: return a.priority > b.priority)


func physics_tick(delta: float) -> void:
	for attack: EnemyAttack in _attacks:
		attack.physics_tick(delta)
	if _active_attack and not _active_attack.is_in_progress():
		_active_attack = null


func has_attack_in_range(target: Node3D) -> bool:
	if _active_attack:
		return true
	for attack: EnemyAttack in _attacks:
		if attack.can_start(target):
			return true
	return false


func try_start(target: Node3D) -> bool:
	if _active_attack:
		return false
	for attack: EnemyAttack in _attacks:
		if attack.start(target):
			_active_attack = attack
			return true
	return false


func is_attacking() -> bool:
	return _active_attack != null and _active_attack.is_in_progress()


func locks_movement() -> bool:
	return is_attacking() and _active_attack.lock_movement


func locks_facing() -> bool:
	return is_attacking() and _active_attack.lock_facing


func get_animation_tag() -> StringName:
	if is_attacking():
		return _active_attack.animation_tag
	return &""


func cancel_all() -> void:
	for attack: EnemyAttack in _attacks:
		attack.cancel()
	_active_attack = null


func reset_attacks() -> void:
	cancel_all()


func _on_attack_started(attack: EnemyAttack) -> void:
	attack_started.emit(attack)


func _on_attack_active(attack: EnemyAttack) -> void:
	attack_active.emit(attack)


func _on_attack_finished(attack: EnemyAttack) -> void:
	attack_finished.emit(attack)
	if _active_attack == attack:
		_active_attack = null


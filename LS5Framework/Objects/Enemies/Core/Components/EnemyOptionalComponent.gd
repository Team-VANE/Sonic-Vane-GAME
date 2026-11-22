extends Node
class_name EnemyOptionalComponent

var actor: CharacterBody3D = null


func setup(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor


func physics_tick(_delta: float) -> void:
	pass


func set_distance_culled(_value: bool) -> void:
	pass


func reset_component(_reason: StringName) -> void:
	pass


func on_enemy_damaged(_amount: int, _source: Node) -> void:
	pass


func on_enemy_defeated(_source: Node) -> void:
	pass

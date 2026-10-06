extends Node3D
class_name ActorDefeatEffects3D

@export_group("Defeat Effects")
## Scene spawned at the owning actor when it is defeated.
@export var defeat_effect_scene: PackedScene
## Node on the owning actor used as the effect origin.
@export var effect_origin_path: NodePath = NodePath("")
## Node on the owning actor that receives spawned effects. Empty uses the actor parent.
@export var effect_parent_path: NodePath = NodePath("")
## Fracture emitter triggered when the owning actor is defeated.
@export var fracture_emitter_path: NodePath = NodePath("")

var _actor: Node3D = null


func setup(actor: Node3D) -> void:
	_actor = actor


func play_defeat_effect(size: float = 1.0) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	var fracture_emitter: Node = _actor.get_node_or_null(fracture_emitter_path) if fracture_emitter_path != NodePath("") else null
	if fracture_emitter and fracture_emitter.has_method("emit_fractures"):
		fracture_emitter.call("emit_fractures", _get_origin_transform().origin)
	if defeat_effect_scene == null:
		return
	var effect: Node = defeat_effect_scene.instantiate()
	if effect == null:
		return
	var parent: Node = _resolve_parent()
	if parent == null:
		effect.queue_free()
		return
	parent.add_child(effect)
	if effect is Node3D:
		var effect_3d: Node3D = effect as Node3D
		var origin_transform: Transform3D = _get_origin_transform()
		effect_3d.global_transform = Transform3D(
			origin_transform.basis.scaled(Vector3.ONE * max(size, 0.01)),
			origin_transform.origin
		)


func _get_origin_transform() -> Transform3D:
	if effect_origin_path != NodePath(""):
		var origin: Node3D = _actor.get_node_or_null(effect_origin_path) as Node3D
		if origin:
			return origin.global_transform
	return _actor.global_transform


func _resolve_parent() -> Node:
	if effect_parent_path != NodePath(""):
		var configured_parent: Node = _actor.get_node_or_null(effect_parent_path)
		if configured_parent:
			return configured_parent
	var parent: Node = _actor.get_parent()
	if parent:
		return parent
	return _actor.get_tree().current_scene


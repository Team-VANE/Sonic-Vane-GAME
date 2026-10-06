extends Node
class_name ActorCollisionController3D

@export_group("Collision")
## Physics layers used by the actor while collision is enabled.
@export_flags_3d_physics var active_collision_layer: int = 128
## Physics layers detected by the actor while collision is enabled.
@export_flags_3d_physics var active_collision_mask: int = 1
## Collision objects disabled and restored with the actor body.
@export var managed_collision_paths: Array[NodePath] = []

var _actor: CollisionObject3D = null
var _managed_objects: Array[CollisionObject3D] = []
var _saved_layers: Dictionary = {}
var _saved_masks: Dictionary = {}
var _disable_timer: float = 0.0
var _enabled: bool = true


func setup(actor: CollisionObject3D) -> void:
	_actor = actor
	_managed_objects.clear()
	_saved_layers.clear()
	_saved_masks.clear()
	if actor:
		actor.collision_layer = active_collision_layer
		actor.collision_mask = active_collision_mask
		_register_object(actor)
	for path: NodePath in managed_collision_paths:
		var object: CollisionObject3D = actor.get_node_or_null(path) as CollisionObject3D if actor else null
		if object:
			_register_object(object)
	set_collision_enabled(true)


func physics_tick(delta: float) -> void:
	if _disable_timer <= 0.0:
		return
	_disable_timer = max(_disable_timer - delta, 0.0)
	if _disable_timer <= 0.0:
		set_collision_enabled(true)


func disable_for(duration: float) -> void:
	if duration <= 0.0:
		return
	_disable_timer = max(_disable_timer, duration)
	set_collision_enabled(false)


func disable_until_reset() -> void:
	_disable_timer = 0.0
	set_collision_enabled(false)


func set_collision_enabled(value: bool) -> void:
	_enabled = value
	for object: CollisionObject3D in _managed_objects:
		if object == null or not is_instance_valid(object):
			continue
		var object_id: int = object.get_instance_id()
		if value:
			object.collision_layer = int(_saved_layers.get(object_id, 0))
			object.collision_mask = int(_saved_masks.get(object_id, 0))
		else:
			object.collision_layer = 0
			object.collision_mask = 0
		if object is Area3D:
			var area: Area3D = object as Area3D
			area.set_deferred("monitoring", value)
			area.set_deferred("monitorable", value)


func reset_collision() -> void:
	_disable_timer = 0.0
	set_collision_enabled(true)


func is_collision_enabled() -> bool:
	return _enabled


func _register_object(object: CollisionObject3D) -> void:
	if _managed_objects.has(object):
		return
	_managed_objects.append(object)
	var object_id: int = object.get_instance_id()
	_saved_layers[object_id] = object.collision_layer
	_saved_masks[object_id] = object.collision_mask

@static_unload
extends RefCounted
class_name SurfaceBehaviorRegistry

const DETECTION_LAYER: int = 1 << 31
const DETECTION_GROUP: StringName = &"surface_behavior_triggers"
const INVISIBLE_KEY: StringName = &"surface_invisible"

static var _targets: Dictionary = {}
static var _sequence: int = 0


static func register(target: Node, provider: Node, metadata: Dictionary, priority: int) -> void:
	var target_id: int = target.get_instance_id()
	if not _targets.has(target_id):
		_targets[target_id] = {"target": weakref(target), "providers": {}}
		target.tree_exiting.connect(_on_target_exiting.bind(target_id))
	var entry: Dictionary = _targets[target_id]
	var provider_id: int = provider.get_instance_id()
	var providers: Dictionary = entry["providers"]
	if not providers.has(provider_id):
		_sequence += 1
		providers[provider_id] = {"provider": weakref(provider), "sequence": _sequence}
	var contribution: Dictionary = providers[provider_id]
	contribution["metadata"] = metadata.duplicate()
	contribution["priority"] = priority
	if target is MeshInstance3D and metadata.has(INVISIBLE_KEY):
		if not entry.has("visible"):
			entry["visible"] = (target as MeshInstance3D).visible
	if target is MeshInstance3D:
		_update_visibility(target as MeshInstance3D, entry)
	if target is Area3D and not target.has_method("is_imported_surface_behavior_area"):
		_link_area(target as Area3D, entry)


static func unregister(target: Node, provider: Node) -> void:
	var target_id: int = target.get_instance_id()
	if not _targets.has(target_id):
		return
	var entry: Dictionary = _targets[target_id]
	var providers: Dictionary = entry["providers"]
	providers.erase(provider.get_instance_id())
	if providers.is_empty():
		_remove_target(target_id)
	elif target is MeshInstance3D:
		_update_visibility(target as MeshInstance3D, entry)


static func get_override(target: Object, key: StringName) -> Dictionary:
	if not is_instance_valid(target) or not _targets.has(target.get_instance_id()):
		return {}
	var providers: Dictionary = _targets[target.get_instance_id()]["providers"]
	var selected: Dictionary = {}
	for contribution: Dictionary in providers.values():
		if not is_instance_valid((contribution["provider"] as WeakRef).get_ref()):
			continue
		if not (contribution["metadata"] as Dictionary).has(key):
			continue
		if selected.is_empty() or int(contribution["priority"]) > int(selected["priority"]) or (
			int(contribution["priority"]) == int(selected["priority"])
			and int(contribution["sequence"]) > int(selected["sequence"])
		):
			selected = contribution
	return {"value": selected["metadata"][key]} if not selected.is_empty() else {}


static func is_behavior_area(area: Area3D) -> bool:
	return is_instance_valid(area) and _targets.has(area.get_instance_id()) and _targets[area.get_instance_id()].has("bodies")


static func notify_entered(area: Area3D, body: Node3D) -> void:
	if not is_behavior_area(area) or not body.has_method("enter_surface_behavior_area"):
		return
	var entry: Dictionary = _targets[area.get_instance_id()]
	entry["bodies"][body.get_instance_id()] = weakref(body)
	body.call("enter_surface_behavior_area", area)


static func notify_exited(area: Area3D, body: Node3D) -> void:
	if is_behavior_area(area):
		_targets[area.get_instance_id()]["bodies"].erase(body.get_instance_id())
	if is_instance_valid(body) and body.has_method("exit_surface_behavior_area"):
		body.call("exit_surface_behavior_area", area)


static func _link_area(area: Area3D, entry: Dictionary) -> void:
	if entry.has("bodies"):
		return
	entry["bodies"] = {}
	entry["layer"] = area.collision_layer
	entry["monitoring"] = area.monitoring
	entry["group"] = area.is_in_group(DETECTION_GROUP)
	area.collision_layer |= DETECTION_LAYER
	area.add_to_group(DETECTION_GROUP)
	area.set_deferred("monitoring", true)
	area.body_entered.connect(_on_body_entered.bind(area))
	area.body_exited.connect(_on_body_exited.bind(area))
	_register_overlaps.call_deferred(weakref(area))


static func _register_overlaps(reference: WeakRef) -> void:
	var area: Area3D = reference.get_ref() as Area3D
	if not is_behavior_area(area) or not area.is_inside_tree():
		return
	for body: Node3D in area.get_overlapping_bodies():
		notify_entered(area, body)


static func _on_body_entered(body: Node3D, area: Area3D) -> void:
	notify_entered(area, body)


static func _on_body_exited(body: Node3D, area: Area3D) -> void:
	notify_exited(area, body)


static func _update_visibility(mesh: MeshInstance3D, entry: Dictionary) -> void:
	if not entry.has("visible"):
		return
	var override: Dictionary = get_override(mesh, INVISIBLE_KEY)
	mesh.visible = not bool(override["value"]) if not override.is_empty() else bool(entry["visible"])


static func _on_target_exiting(target_id: int) -> void:
	_remove_target(target_id)


static func _remove_target(target_id: int) -> void:
	if not _targets.has(target_id):
		return
	var entry: Dictionary = _targets[target_id]
	var target: Node = (entry["target"] as WeakRef).get_ref() as Node
	if is_instance_valid(target):
		if target is MeshInstance3D and entry.has("visible"):
			(target as MeshInstance3D).visible = bool(entry["visible"])
		if target is Area3D and entry.has("bodies"):
			var area: Area3D = target as Area3D
			area.body_entered.disconnect(_on_body_entered.bind(area))
			area.body_exited.disconnect(_on_body_exited.bind(area))
			for reference: WeakRef in entry["bodies"].values():
				var body: Node3D = reference.get_ref() as Node3D
				if is_instance_valid(body):
					notify_exited(area, body)
			area.collision_layer = int(entry["layer"])
			area.set_deferred("monitoring", bool(entry["monitoring"]))
			if not bool(entry["group"]):
				area.remove_from_group(DETECTION_GROUP)
		var callback: Callable = _on_target_exiting.bind(target_id)
		if target.tree_exiting.is_connected(callback):
			target.tree_exiting.disconnect(callback)
	_targets.erase(target_id)

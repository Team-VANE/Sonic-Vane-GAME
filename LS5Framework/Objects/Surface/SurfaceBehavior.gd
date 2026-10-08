@tool
extends Node3D
class_name SurfaceBehavior

@export_group("Surface")
## Registers the configured behavior at runtime. Disabling restores the underlying metadata and visibility.
@export var enabled: bool = true:
	set(value):
		enabled = value
		_queue_refresh()
## Target nodes relative to this component. Empty uses this node's collision subtree, or its parent when used as a child component.
@export var target_paths: Array[NodePath] = []:
	set(value):
		target_paths = value
		_queue_refresh()
## Higher values override other components on the same target. Equal priorities use the latest registration.
@export var behavior_priority: int = 0:
	set(value):
		behavior_priority = value
		_queue_refresh()

@export_group("Traits")
## Rolling, jumping, drifting, and slope gravity policies. Later entries override earlier entries for the same setting.
@export var movement_traits: Array[SurfaceMovementTrait] = []:
	set(value):
		movement_traits = value
		_queue_refresh()
## Wall cling, gravity-relative alignment, adhesion, and momentum policies.
@export var attachment_traits: Array[SurfaceAttachmentTrait] = []:
	set(value):
		attachment_traits = value
		_queue_refresh()
## Contact damage and pit-death policies.
@export var hazard_traits: Array[SurfaceHazardTrait] = []:
	set(value):
		hazard_traits = value
		_queue_refresh()
## Runtime mesh visibility within the selected target subtrees.
@export var visibility_traits: Array[SurfaceVisibilityTrait] = []:
	set(value):
		visibility_traits = value
		_queue_refresh()
## Additional behavior resources. Later entries override the built-in traits.
@export var custom_traits: Array[SurfaceBehaviorTrait] = []:
	set(value):
		custom_traits = value
		_queue_refresh()

var _registered_targets: Array[WeakRef] = []
var _connected_traits: Array[SurfaceBehaviorTrait] = []
var _refresh_pending: bool = false


func _ready() -> void:
	refresh()


func _exit_tree() -> void:
	_release_targets()
	_disconnect_traits()


func get_surface_metadata() -> Dictionary:
	var metadata: Dictionary = {}
	for component: SurfaceBehaviorTrait in _get_traits():
		if component:
			metadata.merge(component.get_surface_metadata(), true)
	if bool(metadata.get(SurfaceBehaviorMetadata.FORCE_ROLL, false)):
		metadata[SurfaceBehaviorMetadata.NO_ROLL] = false
	var angle: Variant = metadata.get(SurfaceBehaviorMetadata.ATTACH_LIMIT)
	if (angle is int or angle is float) and float(angle) <= 0.0:
		metadata[SurfaceBehaviorMetadata.NO_DETACH] = false
	return metadata


func refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree():
		return
	_connect_traits()
	update_configuration_warnings()
	if Engine.is_editor_hint():
		return
	var targets: Array[Node] = []
	if enabled:
		for root: Node in _get_target_roots():
			_collect_targets(root, targets)
	var metadata: Dictionary = get_surface_metadata()
	for reference: WeakRef in _registered_targets:
		var previous: Node = reference.get_ref() as Node
		if is_instance_valid(previous) and not targets.has(previous):
			SurfaceBehaviorRegistry.unregister(previous, self)
	_registered_targets.clear()
	for target: Node in targets:
		SurfaceBehaviorRegistry.register(target, self, metadata, behavior_priority)
		_registered_targets.append(weakref(target))


func _get_traits() -> Array[SurfaceBehaviorTrait]:
	var traits: Array[SurfaceBehaviorTrait] = []
	traits.append_array(movement_traits)
	traits.append_array(attachment_traits)
	traits.append_array(hazard_traits)
	traits.append_array(visibility_traits)
	traits.append_array(custom_traits)
	return traits


func _get_target_roots() -> Array[Node]:
	var roots: Array[Node] = []
	if not target_paths.is_empty():
		for path: NodePath in target_paths:
			var target: Node = get_node_or_null(path)
			if target and not roots.has(target):
				roots.append(target)
	else:
		var collisions: Array[Node] = []
		_collect_targets(self, collisions)
		var has_collision: bool = false
		for node: Node in collisions:
			if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
				has_collision = true
				break
		roots.append(self if has_collision or (self as Node) is MeshInstance3D or not get_parent() else get_parent())
	return roots


func _collect_targets(node: Node, targets: Array[Node], is_root: bool = true) -> void:
	if not is_root and node is SurfaceBehavior and node != self:
		return
	if node is CollisionShape3D or node is CollisionPolygon3D:
		var target: Node = node.get_parent() if node.get_parent() is Area3D else node
		if not targets.has(target):
			targets.append(target)
		return
	if node is CollisionObject3D or node is MeshInstance3D:
		if not targets.has(node):
			targets.append(node)
	for child: Node in node.get_children():
		if node is CollisionObject3D and (child is CollisionShape3D or child is CollisionPolygon3D):
			continue
		_collect_targets(child, targets, false)


func _queue_refresh() -> void:
	if not is_inside_tree() or _refresh_pending:
		return
	_refresh_pending = true
	refresh.call_deferred()


func _connect_traits() -> void:
	_disconnect_traits()
	for component: SurfaceBehaviorTrait in _get_traits():
		if component and not _connected_traits.has(component):
			component.changed.connect(_queue_refresh)
			_connected_traits.append(component)


func _disconnect_traits() -> void:
	for component: SurfaceBehaviorTrait in _connected_traits:
		if component.changed.is_connected(_queue_refresh):
			component.changed.disconnect(_queue_refresh)
	_connected_traits.clear()


func _release_targets() -> void:
	for reference: WeakRef in _registered_targets:
		var target: Node = reference.get_ref() as Node
		if is_instance_valid(target):
			SurfaceBehaviorRegistry.unregister(target, self)
	_registered_targets.clear()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	for path: NodePath in target_paths:
		if not get_node_or_null(path):
			warnings.append("Surface target not found: %s" % path)
	var targets: Array[Node] = []
	for root: Node in _get_target_roots():
		_collect_targets(root, targets)
	var has_collision: bool = false
	for target: Node in targets:
		if target is CollisionObject3D:
			has_collision = true
			if target is Area3D and (target as Area3D).collision_mask == 0:
				warnings.append("Area3D collision masks must include the player body layer.")
		elif target is CollisionShape3D or target is CollisionPolygon3D:
			if target.get_parent() is CollisionObject3D:
				has_collision = true
			else:
				warnings.append("Collision shapes require a CollisionObject3D parent.")
	if not has_collision:
		warnings.append("No collision target found. Mesh visibility traits can still be applied.")
	return warnings

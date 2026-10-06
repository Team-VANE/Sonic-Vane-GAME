extends Node
class_name LevelObjectProxySpawner

const DEFAULT_PROXY_GROUP: StringName = &"LevelObjectProxy"

static var _property_names_by_type: Dictionary = {}

## Group used to identify level object proxies.
@export var proxy_group: StringName = DEFAULT_PROXY_GROUP


static func collect_proxies(
		level_root: Node,
		proxy_group_name: StringName = DEFAULT_PROXY_GROUP
	) -> Array[Node]:
	var proxies: Array[Node] = []
	if level_root == null:
		return proxies
	var stack: Array[Node] = [level_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current != level_root and current.is_in_group(proxy_group_name):
			proxies.append(current)
			continue
		for child: Node in current.get_children():
			stack.append(child)
	return proxies


static func collect_required_resource_paths(proxies: Array[Node]) -> Array[String]:
	var resource_paths: Array[String] = []
	for proxy: Node in proxies:
		if proxy == null or not is_instance_valid(proxy):
			continue
		if not _read_proxy_bool(proxy, "spawn_enabled", true):
			continue
		_append_unique_path(
			resource_paths,
			_read_proxy_string(proxy, "target_scene_path", "")
		)
		var overrides: Array = _read_proxy_array(proxy, "property_overrides")
		for entry_value: Variant in overrides:
			if not (entry_value is Dictionary):
				continue
			var entry: Dictionary = entry_value
			if String(entry.get("value_type", "")).strip_edges() != "resource_path":
				continue
			_append_unique_path(resource_paths, String(entry.get("value", "")))
	return resource_paths


static func replace_proxies_in_level(
		level_root: Node,
		proxies: Array[Node] = [],
		proxy_group_name: StringName = DEFAULT_PROXY_GROUP
	) -> bool:
	if level_root == null:
		return false
	var resolved_proxies: Array[Node] = proxies
	if resolved_proxies.is_empty():
		resolved_proxies = collect_proxies(level_root, proxy_group_name)
	var succeeded: bool = true
	for proxy: Node in resolved_proxies:
		if not _replace_proxy(level_root, proxy):
			succeeded = false
	return succeeded


static func _replace_proxy(level_root: Node, proxy: Node) -> bool:
	if proxy == null or not is_instance_valid(proxy):
		return false
	if not _read_proxy_bool(proxy, "spawn_enabled", true):
		_free_proxy(proxy)
		return true
	var scene_path: String = _read_proxy_string(proxy, "target_scene_path", "").strip_edges()
	if scene_path == "":
		push_warning("LevelObjectProxySpawner: proxy missing target_scene_path: %s" % proxy.name)
		return false
	var packed: Resource = LevelPreparationManager.get_resource(
		scene_path,
		LevelPreparationManager.SCOPE_LEVEL
	)
	if packed == null and not LevelPreparationManager.is_cache_enabled():
		packed = ResourceLoader.load(scene_path)
	if not (packed is PackedScene):
		push_warning("LevelObjectProxySpawner: target scene could not be loaded: %s" % scene_path)
		return false
	var instance: Node = (packed as PackedScene).instantiate()
	if instance == null:
		push_warning("LevelObjectProxySpawner: failed to instantiate scene: %s" % scene_path)
		return false
	instance.name = proxy.name
	if instance is Node3D and proxy is Node3D:
		(instance as Node3D).transform = (proxy as Node3D).transform
	_apply_property_overrides(proxy, instance)
	_copy_curve_data(proxy, instance)
	_copy_transform_markers(proxy, instance)
	var parent_override: Node = _resolve_parent_override(level_root, proxy)
	var parent_node: Node = parent_override if parent_override != null else proxy.get_parent()
	if parent_node == null or parent_node == proxy or proxy.is_ancestor_of(parent_node):
		instance.free()
		push_warning("LevelObjectProxySpawner: proxy has an invalid spawn parent: %s" % proxy.name)
		return false
	var proxy_index: int = proxy.get_index()
	parent_node.add_child(instance)
	parent_node.move_child(instance, proxy_index)
	_free_proxy(proxy)
	return true


static func _resolve_parent_override(level_root: Node, proxy: Node) -> Node:
	var parent_path: NodePath = _read_proxy_node_path(proxy, "spawn_parent_path", NodePath(""))
	if parent_path == NodePath(""):
		return null
	return level_root.get_node_or_null(parent_path)


static func _apply_property_overrides(proxy: Node, target: Node) -> void:
	var overrides: Array = _read_proxy_array(proxy, "property_overrides")
	var override_map: Dictionary = {}
	for entry_value: Variant in overrides:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var property_name: String = String(entry.get("name", "")).strip_edges()
		if property_name == "":
			continue
		var value: Variant = _resolve_override_value(entry)
		override_map[property_name] = value
		if _object_has_property(target, property_name):
			target.set(property_name, value)
	if target.has_method("apply_spawn_overrides"):
		target.call("apply_spawn_overrides", override_map, proxy)


static func _copy_curve_data(proxy: Node, target: Node) -> void:
	if not _read_proxy_bool(proxy, "curve_copy_enabled", false):
		return
	var source_path: NodePath = _read_proxy_node_path(proxy, "curve_source_path", NodePath(""))
	var target_path: NodePath = _read_proxy_node_path(proxy, "curve_target_path", NodePath(""))
	if source_path == NodePath("") or target_path == NodePath(""):
		return
	var source_node: Node = proxy.get_node_or_null(source_path)
	var target_node: Node = target.get_node_or_null(target_path)
	if not (source_node is Path3D) or not (target_node is Path3D):
		return
	var source_curve: Curve3D = (source_node as Path3D).curve
	if source_curve == null:
		return
	var copied_curve: Curve3D = source_curve.duplicate() as Curve3D
	(target_node as Path3D).curve = copied_curve


static func _copy_transform_markers(proxy: Node, target: Node) -> void:
	var entries: Array = _read_proxy_array(proxy, "transform_copies")
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var from_path: NodePath = _read_dict_node_path(entry, "from")
		var to_path: NodePath = _read_dict_node_path(entry, "to")
		if from_path == NodePath("") or to_path == NodePath(""):
			continue
		var from_node: Node = proxy.get_node_or_null(from_path)
		var to_node: Node = target.get_node_or_null(to_path)
		if from_node is Node3D and to_node is Node3D:
			(to_node as Node3D).transform = (from_node as Node3D).transform


static func _resolve_override_value(entry: Dictionary) -> Variant:
	var value_type: String = String(entry.get("value_type", "")).strip_edges()
	var raw_value: Variant = entry.get("value")
	if value_type == "resource_path":
		var resource_path: String = String(raw_value).strip_edges()
		if resource_path == "":
			return null
		var resource: Resource = LevelPreparationManager.get_resource(resource_path)
		if resource == null and not LevelPreparationManager.is_cache_enabled():
			resource = ResourceLoader.load(resource_path)
		if resource == null:
			push_warning("LevelObjectProxySpawner: override resource could not be loaded: %s" % resource_path)
		return resource
	if value_type == "node_path":
		var node_path: String = String(raw_value)
		return NodePath(node_path) if node_path != "" else NodePath("")
	return raw_value


static func _read_proxy_string(proxy: Node, property_name: String, fallback: String) -> String:
	if not _object_has_property(proxy, property_name):
		return fallback
	var value: Variant = proxy.get(property_name)
	return String(value) if value is String else fallback


static func _read_proxy_bool(proxy: Node, property_name: String, fallback: bool) -> bool:
	if not _object_has_property(proxy, property_name):
		return fallback
	var value: Variant = proxy.get(property_name)
	return bool(value) if value is bool else fallback


static func _read_proxy_array(proxy: Node, property_name: String) -> Array:
	if not _object_has_property(proxy, property_name):
		return []
	var value: Variant = proxy.get(property_name)
	return value if value is Array else []


static func _read_proxy_node_path(proxy: Node, property_name: String, fallback: NodePath) -> NodePath:
	if not _object_has_property(proxy, property_name):
		return fallback
	var value: Variant = proxy.get(property_name)
	if value is NodePath:
		return value
	if value is String:
		return NodePath(String(value))
	return fallback


static func _read_dict_node_path(entry: Dictionary, key: String) -> NodePath:
	if not entry.has(key):
		return NodePath("")
	var value: Variant = entry.get(key)
	if value is NodePath:
		return value
	if value is String:
		return NodePath(String(value))
	return NodePath("")


static func _object_has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	var cache_key: String = _get_property_cache_key(object)
	var property_names: Dictionary = _property_names_by_type.get(cache_key, {})
	if property_names.is_empty():
		for property_entry: Dictionary in object.get_property_list():
			property_names[String(property_entry.get("name", ""))] = true
		_property_names_by_type[cache_key] = property_names
	return property_names.has(property_name)


static func _get_property_cache_key(object: Object) -> String:
	var script: Script = object.get_script() as Script
	if script != null:
		var script_path: String = script.resource_path
		if script_path != "":
			return script_path
		return "script:%d" % script.get_instance_id()
	return "class:%s" % object.get_class()


static func _append_unique_path(resource_paths: Array[String], resource_path: String) -> void:
	var normalized_path: String = resource_path.strip_edges()
	if normalized_path != "" and not resource_paths.has(normalized_path):
		resource_paths.append(normalized_path)


static func _free_proxy(proxy: Node) -> void:
	if proxy.is_inside_tree():
		proxy.queue_free()
	else:
		proxy.free()

extends RefCounted
class_name LevelCatalog

const DEBUG_LEVEL_DOCS: bool = true
const LEVEL_DOC_PREFIX: String = "LVL_"
const LEVEL_TEST_RESOURCE_NAME: String = "LVLTEST.tres"
const LEVEL_REGISTRY_PATH: String = "res://LS5Framework/Scenes/Levels/LevelRegistry.tres"
const PACK_MANIFEST_DIR_NAME: String = "PackManifests"


static func load_level_entries(levels_dir: String) -> Array:
	# SUMMARY: Load level entries from LevelDoc resources only.
	# STEPS:
	# - Step 1: Gather LevelDoc resources (LVL_*.tres / LVLTEST.tres).
	# - Step 2: Include pack manifests found under levels_dir/PackManifests.
	# - Step 3: Sort entries by order, then name.
	_log_debug("load_level_entries: levels_dir=%s" % levels_dir)
	var entries: Array = []
	var seen: Dictionary = {}

	var resource_paths: Array = []
	var registry_paths: Array = _load_level_docs_from_registry(levels_dir)
	if not registry_paths.is_empty():
		resource_paths.append_array(registry_paths)
	_log_debug("load_level_entries: registry_paths=%d" % registry_paths.size())

	var manifest_paths: Array = _load_level_docs_from_pack_manifests(levels_dir)
	if not manifest_paths.is_empty():
		resource_paths.append_array(manifest_paths)
	_log_debug("load_level_entries: manifest_paths=%d" % manifest_paths.size())

	var dir_paths: Array = _find_level_doc_resources(levels_dir)
	if not dir_paths.is_empty():
		resource_paths.append_array(dir_paths)
	_log_debug("load_level_entries: dir_paths=%d" % dir_paths.size())

	resource_paths = _dedupe_resource_paths(resource_paths)
	_log_debug("load_level_entries: resource_paths=%d" % resource_paths.size())
	var test_resource_path: String = _resolve_level_doc_path(levels_dir.path_join(LEVEL_TEST_RESOURCE_NAME))
	if test_resource_path != "":
		resource_paths.append(test_resource_path)
	_log_debug("load_level_entries: resource_paths_after_test=%d" % resource_paths.size())

	for res_path in resource_paths:
		var entry: Dictionary = _load_level_doc_resource(res_path)
		_append_entry(entries, seen, entry)

	_sort_entries(entries)
	_log_debug("load_level_entries: entries=%d" % entries.size())
	return entries


static func _find_level_doc_resources(levels_dir: String) -> Array:
	var result: Array = []
	if levels_dir.strip_edges() == "":
		_log_debug("_find_level_doc_resources: empty levels_dir")
		return result
	var base_dir: String = levels_dir
	var dir := DirAccess.open(levels_dir)
	if dir == null:
		var abs_dir: String = ProjectSettings.globalize_path(levels_dir)
		if DirAccess.dir_exists_absolute(abs_dir):
			dir = DirAccess.open(abs_dir)
			base_dir = abs_dir
		if dir == null:
			_log_debug("_find_level_doc_resources: cannot open dir %s" % levels_dir)
			return result

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var resource_name: String = _logical_resource_name(name)
			if resource_name.begins_with(LEVEL_DOC_PREFIX) and resource_name.get_extension().to_lower() == "tres":
				var resource_path: String = base_dir.path_join(resource_name)
				if not result.has(resource_path):
					result.append(resource_path)
		name = dir.get_next()
	dir.list_dir_end()
	_log_debug("_find_level_doc_resources: found=%d in %s" % [result.size(), base_dir])
	return result


static func _load_level_docs_from_registry(levels_dir: String) -> Array:
	return _load_level_docs_from_manifest(LEVEL_REGISTRY_PATH, levels_dir)


static func _load_level_docs_from_pack_manifests(levels_dir: String) -> Array:
	var result: Array = []
	if levels_dir.strip_edges() == "":
		_log_debug("_load_level_docs_from_pack_manifests: empty levels_dir")
		return result
	var manifests_dir: String = levels_dir.path_join(PACK_MANIFEST_DIR_NAME)
	var manifest_paths: Array = _find_pack_manifest_resources(manifests_dir)
	if manifest_paths.is_empty():
		return result
	for manifest_path in manifest_paths:
		var manifest_entries: Array = _load_level_docs_from_manifest(manifest_path, levels_dir)
		if not manifest_entries.is_empty():
			result.append_array(manifest_entries)
	return result


static func _find_pack_manifest_resources(manifests_dir: String) -> Array:
	var result: Array = []
	if manifests_dir.strip_edges() == "":
		_log_debug("_find_pack_manifest_resources: empty manifests_dir")
		return result
	var dir := DirAccess.open(manifests_dir)
	if dir == null:
		_log_debug("_find_pack_manifest_resources: cannot open dir %s" % manifests_dir)
		return result

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var resource_name: String = _logical_resource_name(name)
			var ext: String = resource_name.get_extension().to_lower()
			if ext == "tres" or ext == "res":
				var resource_path: String = manifests_dir.path_join(resource_name)
				if not result.has(resource_path):
					result.append(resource_path)
		name = dir.get_next()
	dir.list_dir_end()
	_log_debug("_find_pack_manifest_resources: found=%d in %s" % [result.size(), manifests_dir])
	return result


static func _logical_resource_name(entry_name: String) -> String:
	var resource_name: String = entry_name
	if resource_name.get_extension().to_lower() == "remap":
		resource_name = resource_name.get_basename()
	return resource_name


static func _load_level_docs_from_manifest(manifest_path: String, levels_dir: String) -> Array:
	var result: Array = []
	if manifest_path.strip_edges() == "":
		return result
	if not ResourceLoader.exists(manifest_path):
		return result
	var res = load(manifest_path)
	if res == null:
		_log_debug("_load_level_docs_from_manifest: load failed %s" % manifest_path)
		return result

	var raw_paths: Array = []
	if res is LevelPackManifest:
		var manifest: LevelPackManifest = res
		raw_paths = manifest.level_docs
	else:
		var fallback = res.get("level_docs")
		if fallback is Array:
			raw_paths = fallback
		elif fallback is PackedStringArray:
			raw_paths = fallback

	for doc_path in raw_paths:
		var doc_str: String = String(doc_path).strip_edges()
		if doc_str == "":
			continue
		var normalized: String = _normalize_level_doc_path(levels_dir, doc_str)
		if normalized != "":
			result.append(normalized)
	_log_debug("_load_level_docs_from_manifest: found=%d in %s" % [result.size(), manifest_path])
	return result


static func _normalize_level_doc_path(levels_dir: String, doc_path: String) -> String:
	if doc_path.begins_with("res://") or doc_path.begins_with("user://"):
		return doc_path
	if levels_dir.strip_edges() == "":
		return ""
	return levels_dir.path_join(doc_path)


static func _load_level_doc_resource(doc_path: String) -> Dictionary:
	var entry: Dictionary = {}
	if doc_path.strip_edges() == "":
		_log_debug("_load_level_doc_resource: empty doc_path")
		return entry
	var has_resource: bool = false
	if ResourceLoader.exists(doc_path):
		has_resource = true
	elif FileAccess.file_exists(doc_path):
		has_resource = true
	if not has_resource:
		_log_debug("_load_level_doc_resource: missing file %s" % doc_path)
		return entry

	var res = load(doc_path)
	if res == null:
		_log_debug("_load_level_doc_resource: load failed %s" % doc_path)
		return entry

	var level_name: String = ""
	var level_id: String = ""
	var scene_path: String = ""
	var level_scene_path: String = ""
	var order_value: int = 0
	var is_test: bool = false
	var selection_category: String = "Main"
	var attributes: Dictionary = {}

	if res is LevelDoc:
		var doc: LevelDoc = res
		level_name = doc.level_name.strip_edges()
		level_id = doc.level_id.strip_edges()
		scene_path = doc.scene.strip_edges()
		level_scene_path = doc.level_scene.strip_edges()
		order_value = int(doc.order)
		is_test = doc.is_test
		selection_category = doc.selection_category.strip_edges()
		attributes = doc.attributes
	else:
		# Fallback for exports that load LevelDoc resources without the script class.
		_log_debug("_load_level_doc_resource: using fallback for %s" % doc_path)
		var raw_name = res.get("level_name")
		if raw_name is String:
			level_name = raw_name.strip_edges()
		var raw_id = res.get("level_id")
		if raw_id is String:
			level_id = raw_id.strip_edges()
		var raw_scene = res.get("scene")
		if raw_scene is String:
			scene_path = raw_scene.strip_edges()
		var raw_level_scene = res.get("level_scene")
		if raw_level_scene is String:
			level_scene_path = raw_level_scene.strip_edges()
		var raw_order = res.get("order")
		if raw_order is int:
			order_value = raw_order
		elif raw_order is float:
			order_value = int(raw_order)
		var raw_is_test = res.get("is_test")
		if raw_is_test is bool:
			is_test = raw_is_test
		var raw_selection_category: Variant = res.get("selection_category")
		if raw_selection_category is String:
			selection_category = String(raw_selection_category).strip_edges()
		var raw_attributes = res.get("attributes")
		if raw_attributes is Dictionary:
			attributes = raw_attributes

	if level_name == "" or scene_path == "":
		_log_debug("_load_level_doc_resource: missing name/scene in %s" % doc_path)
		return {}

	entry["source"] = doc_path
	entry["name"] = level_name
	if level_id != "":
		entry["id"] = level_id
	entry["order"] = order_value
	entry["scene"] = scene_path
	entry["selection_category"] = selection_category
	if level_scene_path != "":
		entry["level_scene"] = level_scene_path
	if is_test:
		entry["is_test"] = true
	if not attributes.is_empty():
		entry["attributes"] = attributes

	return entry


static func _log_debug(message: String) -> void:
	if not DEBUG_LEVEL_DOCS:
		return
	print("LevelCatalog: %s" % message)


static func _resolve_level_doc_path(doc_path: String) -> String:
	if doc_path.strip_edges() == "":
		return ""
	if ResourceLoader.exists(doc_path):
		return doc_path
	if FileAccess.file_exists(doc_path):
		return doc_path
	var abs_path: String = ProjectSettings.globalize_path(doc_path)
	if FileAccess.file_exists(abs_path):
		return abs_path
	return ""


static func _dedupe_resource_paths(paths: Array) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for path in paths:
		var p: String = String(path)
		if p == "":
			continue
		if seen.has(p):
			continue
		seen[p] = true
		result.append(p)
	return result


static func _append_entry(entries: Array, seen: Dictionary, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	if not entry.has("name") or not entry.has("scene"):
		return

	var key: String = ""
	if entry.has("level_scene"):
		key = String(entry["level_scene"])
	if key == "":
		key = String(entry["scene"])
	if key != "":
		if seen.has(key):
			return
		seen[key] = true
	entries.append(entry)


static func _sort_entries(entries: Array) -> void:
	entries.sort_custom(Callable(LevelCatalog, "_compare_entries"))


static func _compare_entries(a: Variant, b: Variant) -> bool:
	var entry_a: Dictionary = {}
	var entry_b: Dictionary = {}
	if a is Dictionary:
		entry_a = a
	if b is Dictionary:
		entry_b = b

	var order_a: int = 0
	if entry_a.has("order"):
		order_a = int(entry_a["order"])
	var order_b: int = 0
	if entry_b.has("order"):
		order_b = int(entry_b["order"])

	if order_a != order_b:
		return order_a < order_b

	var name_a: String = ""
	if entry_a.has("name"):
		name_a = String(entry_a["name"])
	var name_b: String = ""
	if entry_b.has("name"):
		name_b = String(entry_b["name"])
	return name_a.nocasecmp_to(name_b) < 0

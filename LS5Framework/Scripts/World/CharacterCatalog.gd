extends RefCounted
class_name CharacterCatalog

const DEBUG_CHARACTER_DOCS: bool = true
const CHARACTER_DOC_PREFIX: String = "CHAR_"
const CHARACTER_REGISTRY_NAME: String = "CharacterRegistry.tres"
const DEFAULT_CHARACTER_ID: String = "sonic_neo_adventure"


static func load_character_entries(characters_dir: String) -> Array:
	_log_debug("load_character_entries: characters_dir=%s" % characters_dir)
	var entries: Array = []
	var seen: Dictionary = {}
	var resource_paths: Array = _load_character_docs_from_registry(characters_dir)
	_log_debug("load_character_entries: registry_paths=%d" % resource_paths.size())
	var dir_paths: Array = _find_character_doc_resources(characters_dir)
	if not dir_paths.is_empty():
		resource_paths.append_array(dir_paths)
	_log_debug("load_character_entries: dir_paths=%d" % dir_paths.size())
	resource_paths = _dedupe_resource_paths(resource_paths)
	for res_path in resource_paths:
		var entry: Dictionary = _load_character_doc_resource(res_path)
		_append_entry(entries, seen, entry)
	_sort_entries(entries)
	_log_debug("load_character_entries: entries=%d" % entries.size())
	return entries


static func get_entry_for_id(characters_dir: String, character_id: String) -> Dictionary:
	var normalized_id: String = character_id.strip_edges()
	if normalized_id == "":
		return {}
	var entries: Array = load_character_entries(characters_dir)
	for entry in entries:
		if not (entry is Dictionary):
			continue
		if String(entry.get("id", "")).nocasecmp_to(normalized_id) == 0:
			return entry
	return {}


static func get_default_entry(characters_dir: String) -> Dictionary:
	var entries: Array = load_character_entries(characters_dir)
	if entries.is_empty():
		return {}
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary:
			var entry: Dictionary = raw_entry
			if String(entry.get("id", "")).nocasecmp_to(DEFAULT_CHARACTER_ID) == 0:
				return entry
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary:
			var entry: Dictionary = raw_entry
			if String(entry.get("id", "")).nocasecmp_to("sonic") != 0:
				return entry
	return {}


static func get_selected_or_default_entry(characters_dir: String, character_id: String) -> Dictionary:
	var entry: Dictionary = get_entry_for_id(characters_dir, character_id)
	if not entry.is_empty():
		return entry
	return get_default_entry(characters_dir)


static func _find_character_doc_resources(characters_dir: String) -> Array:
	var result: Array = []
	if characters_dir.strip_edges() == "":
		return result
	_scan_character_dir(characters_dir, result, 0)
	_log_debug("_find_character_doc_resources: found=%d in %s" % [result.size(), characters_dir])
	return result


static func _load_character_docs_from_registry(characters_dir: String) -> Array:
	var result: Array = []
	if characters_dir.strip_edges() == "":
		return result
	var registry_path: String = characters_dir.path_join(CHARACTER_REGISTRY_NAME)
	if not ResourceLoader.exists(registry_path):
		_log_debug("_load_character_docs_from_registry: missing %s" % registry_path)
		return result
	var res = load(registry_path)
	if res == null:
		_log_debug("_load_character_docs_from_registry: load failed %s" % registry_path)
		return result
	var raw_paths = res.get("character_docs")
	if raw_paths is Array or raw_paths is PackedStringArray:
		for doc_path in raw_paths:
			var normalized: String = _normalize_character_doc_path(characters_dir, String(doc_path))
			if normalized != "":
				result.append(normalized)
	_log_debug("_load_character_docs_from_registry: found=%d in %s" % [result.size(), registry_path])
	return result


static func _normalize_character_doc_path(characters_dir: String, doc_path: String) -> String:
	var cleaned: String = doc_path.strip_edges()
	if cleaned == "":
		return ""
	if cleaned.begins_with("res://") or cleaned.begins_with("user://"):
		return cleaned
	if characters_dir.strip_edges() == "":
		return ""
	return characters_dir.path_join(cleaned)


static func _scan_character_dir(dir_path: String, result: Array, depth: int) -> void:
	if depth > 12:
		return
	var dir := DirAccess.open(dir_path)
	var base_dir: String = dir_path
	if dir == null:
		var abs_dir: String = ProjectSettings.globalize_path(dir_path)
		if DirAccess.dir_exists_absolute(abs_dir):
			dir = DirAccess.open(abs_dir)
			base_dir = abs_dir
	if dir == null:
		return

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child_path: String = base_dir.path_join(name)
		if dir.current_is_dir():
			_scan_character_dir(child_path, result, depth + 1)
		else:
			var resource_name: String = _logical_resource_name(name)
			var ext: String = resource_name.get_extension().to_lower()
			if resource_name.begins_with(CHARACTER_DOC_PREFIX) and (ext == "tres" or ext == "res"):
				var resource_path: String = base_dir.path_join(resource_name)
				if not result.has(resource_path):
					result.append(resource_path)
		name = dir.get_next()
	dir.list_dir_end()


static func _logical_resource_name(entry_name: String) -> String:
	var resource_name: String = entry_name
	if resource_name.get_extension().to_lower() == "remap":
		resource_name = resource_name.get_basename()
	return resource_name


static func _load_character_doc_resource(doc_path: String) -> Dictionary:
	var entry: Dictionary = {}
	if doc_path.strip_edges() == "":
		return entry
	var has_resource: bool = false
	if ResourceLoader.exists(doc_path):
		has_resource = true
	elif FileAccess.file_exists(doc_path):
		has_resource = true
	if not has_resource:
		return entry

	var res = load(doc_path)
	if res == null:
		return entry

	var character_name: String = ""
	var character_id: String = ""
	var scene_path: String = ""
	var order_value: int = 0
	var attributes: Dictionary = {}
	var settings_profile: CharacterSettingsProfile = null
	var ui_voice_profile: CharacterUIVoiceProfile = null

	if res is CharacterDoc:
		var doc: CharacterDoc = res
		character_name = doc.character_name.strip_edges()
		character_id = doc.character_id.strip_edges()
		scene_path = doc.scene.strip_edges()
		order_value = int(doc.order)
		attributes = doc.attributes
		settings_profile = doc.settings_profile
		ui_voice_profile = doc.ui_voice_profile
	else:
		var raw_name = res.get("character_name")
		if raw_name is String:
			character_name = raw_name.strip_edges()
		var raw_id = res.get("character_id")
		if raw_id is String:
			character_id = raw_id.strip_edges()
		var raw_scene = res.get("scene")
		if raw_scene is String:
			scene_path = raw_scene.strip_edges()
		var raw_order = res.get("order")
		if raw_order is int:
			order_value = raw_order
		elif raw_order is float:
			order_value = int(raw_order)
		var raw_attributes = res.get("attributes")
		if raw_attributes is Dictionary:
			attributes = raw_attributes
		var raw_settings_profile: Variant = res.get("settings_profile")
		if raw_settings_profile is CharacterSettingsProfile:
			settings_profile = raw_settings_profile
		var raw_ui_voice_profile: Variant = res.get("ui_voice_profile")
		if raw_ui_voice_profile is CharacterUIVoiceProfile:
			ui_voice_profile = raw_ui_voice_profile

	if character_name == "" or scene_path == "":
		return {}
	if character_id == "":
		character_id = character_name.to_snake_case()

	entry["source"] = doc_path
	entry["name"] = character_name
	entry["id"] = character_id
	entry["order"] = order_value
	entry["scene"] = scene_path
	if settings_profile != null:
		entry["settings_profile"] = settings_profile
		entry["hidden_from_character_select"] = settings_profile.hidden_from_character_select
		entry["selection_category"] = settings_profile.selection_category
	if ui_voice_profile != null:
		entry["ui_voice_profile"] = ui_voice_profile
	if not attributes.is_empty():
		entry["attributes"] = attributes
	return entry


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
	if not entry.has("id") or not entry.has("scene"):
		return
	var key: String = String(entry["id"]).to_lower()
	if key == "":
		return
	if seen.has(key):
		return
	seen[key] = true
	entries.append(entry)


static func _sort_entries(entries: Array) -> void:
	entries.sort_custom(Callable(CharacterCatalog, "_compare_entries"))


static func _compare_entries(a: Variant, b: Variant) -> bool:
	var entry_a: Dictionary = {}
	var entry_b: Dictionary = {}
	if a is Dictionary:
		entry_a = a
	if b is Dictionary:
		entry_b = b

	var order_a: int = int(entry_a.get("order", 0))
	var order_b: int = int(entry_b.get("order", 0))
	if order_a != order_b:
		return order_a < order_b

	var name_a: String = String(entry_a.get("name", ""))
	var name_b: String = String(entry_b.get("name", ""))
	return name_a.nocasecmp_to(name_b) < 0


static func _log_debug(message: String) -> void:
	if not DEBUG_CHARACTER_DOCS:
		return
	print("CharacterCatalog: %s" % message)

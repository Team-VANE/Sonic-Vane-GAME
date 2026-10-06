extends Node
class_name ContentPackManager

signal packs_loaded
signal pack_load_failed(pack_id: String, reason: String)

@export var auto_load_packs: bool = true
@export var data_folder_name: String = "Data"
@export var base_pack_names: PackedStringArray = [
	"shared.pck",
	"audio.pck",
	"characters.pck",
	"objects.pck"
]
@export var levels_subdir: String = "Levels"
@export var mods_subdir: String = "Mods"
@export var load_all_level_packs: bool = true
@export var load_mod_packs: bool = true
@export var base_pack_replace_files: bool = false
@export var level_pack_replace_files: bool = false
@export var mod_pack_replace_files: bool = true
@export var verbose_logging: bool = true

@export_group("Dependencies")
## Suffix used by dependency metadata stored beside each PCK.
@export var dependency_manifest_suffix: String = ".manifest.json"
## Prevents packs from mounting when required dependencies are missing or incompatible.
@export var reject_invalid_dependencies: bool = true

# Optional scene -> pack mapping (pack path is relative to Data/)
@export var scene_pack_map: Array[Dictionary] = []

var _loaded_packs: Dictionary = {}
var _loaded_pack_ids: Dictionary = {}
var _pack_catalog_by_id: Dictionary = {}
var _pack_catalog_by_path: Dictionary = {}
var _packs_loaded: bool = false


func _ready() -> void:
	add_to_group("ContentPackManager")
	if auto_load_packs:
		load_all_packs()


func load_all_packs() -> void:
	_packs_loaded = false
	var data_dir := _resolve_data_dir()
	if verbose_logging:
		print("ContentPackManager: data_dir=%s" % data_dir)
	if data_dir == "":
		_packs_loaded = true
		emit_signal("packs_loaded")
		return

	var catalog: Array = _build_pack_catalog(data_dir)
	var roots: Array = []
	for descriptor_value in catalog:
		if not (descriptor_value is Dictionary):
			continue
		var descriptor: Dictionary = descriptor_value
		var category: String = String(descriptor.get("category", ""))
		if category == "base":
			roots.append(descriptor)
		elif category == "level" and load_all_level_packs:
			roots.append(descriptor)
		elif category == "mod" and load_mod_packs:
			roots.append(descriptor)
	var selected: Array = _collect_dependency_closure(roots)
	_load_descriptors(_sort_descriptors_by_dependencies(selected))
	_packs_loaded = true
	if verbose_logging:
		print("ContentPackManager: packs_loaded")
		_log_level_docs_in_pack()
	emit_signal("packs_loaded")


func are_packs_loaded() -> bool:
	return _packs_loaded


func get_loaded_pack_paths() -> PackedStringArray:
	var result: PackedStringArray = []
	for key in _loaded_packs.keys():
		var path: String = String(key)
		if path == "":
			continue
		result.append(path)
	return result


func get_loaded_pack_ids() -> PackedStringArray:
	var result: PackedStringArray = []
	for key in _loaded_pack_ids.keys():
		result.append(String(key))
	result.sort()
	return result


func _log_level_docs_in_pack() -> void:
	var levels_dir: String = "res://LS5Framework/Scenes/Levels"
	var dir := DirAccess.open(levels_dir)
	if dir == null:
		var abs_dir: String = ProjectSettings.globalize_path(levels_dir)
		var abs_exists: bool = DirAccess.dir_exists_absolute(abs_dir)
		print("ContentPackManager: levels_dir open failed, abs=%s exists=%s" % [abs_dir, abs_exists])
		return

	var found: int = 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var resource_name: String = name
			if resource_name.get_extension().to_lower() == "remap":
				resource_name = resource_name.get_basename()
			if resource_name.begins_with("LVL_") and resource_name.get_extension().to_lower() == "tres":
				found += 1
		name = dir.get_next()
	dir.list_dir_end()
	print("ContentPackManager: level_docs_found=%d in %s" % [found, levels_dir])
	var sample_paths: PackedStringArray = [
		"res://LS5Framework/Scenes/Levels/LVL_EmeraldCoast.tres",
		"res://LS5Framework/Scenes/Levels/LVLTEST.tres"
	]
	for sample_path in sample_paths:
		var exists: bool = ResourceLoader.exists(sample_path)
		print("ContentPackManager: level_doc_exists=%s %s" % [str(exists), sample_path])


func ensure_pack_for_scene(scene_path: String) -> bool:
	if scene_path.strip_edges() == "":
		return false
	var data_dir := _resolve_data_dir()
	if data_dir == "":
		return false
	if _pack_catalog_by_path.is_empty():
		_build_pack_catalog(data_dir)
	for entry in scene_pack_map:
		var scene_val := String(entry.get("scene", ""))
		if scene_val != scene_path:
			continue
		var pack_rel := String(entry.get("pack", "")).strip_edges()
		if pack_rel == "":
			return false
		var pack_abs: String = data_dir.path_join(pack_rel).simplify_path()
		var descriptor_value = _pack_catalog_by_path.get(pack_abs, null)
		if descriptor_value is Dictionary:
			var selected: Array = _collect_dependency_closure([descriptor_value])
			_load_descriptors(_sort_descriptors_by_dependencies(selected))
			var descriptor: Dictionary = descriptor_value
			return _loaded_pack_ids.has(String(descriptor.get("id", "")))
		return _load_pack(pack_abs, level_pack_replace_files)
	return false


func _build_pack_catalog(data_dir: String) -> Array:
	_pack_catalog_by_id.clear()
	_pack_catalog_by_path.clear()
	var descriptors: Array = []
	var discovery_order: int = 0
	for pack_name in base_pack_names:
		var file_name: String = String(pack_name).strip_edges()
		if file_name == "":
			continue
		var base_path: String = data_dir.path_join(file_name).simplify_path()
		descriptors.append(_build_pack_descriptor(base_path, "base", base_pack_replace_files, 0, discovery_order, data_dir))
		discovery_order += 1

	var level_paths: PackedStringArray = _collect_pack_paths(data_dir.path_join(levels_subdir))
	for level_path in level_paths:
		descriptors.append(_build_pack_descriptor(level_path, "level", level_pack_replace_files, 1, discovery_order, data_dir))
		discovery_order += 1

	var mod_paths: PackedStringArray = _collect_pack_paths(data_dir.path_join(mods_subdir))
	for mod_path in mod_paths:
		descriptors.append(_build_pack_descriptor(mod_path, "mod", mod_pack_replace_files, 2, discovery_order, data_dir))
		discovery_order += 1

	for descriptor_value in descriptors:
		if not (descriptor_value is Dictionary):
			continue
		var descriptor: Dictionary = descriptor_value
		var pack_id: String = String(descriptor.get("id", ""))
		var pack_path: String = String(descriptor.get("path", ""))
		if _pack_catalog_by_id.has(pack_id):
			var existing: Dictionary = _pack_catalog_by_id[pack_id]
			descriptor["preflight_error"] = "Duplicate pack ID also used by %s" % String(existing.get("path", ""))
		else:
			_pack_catalog_by_id[pack_id] = descriptor
		_pack_catalog_by_path[pack_path] = descriptor
	return descriptors


func _build_pack_descriptor(
		pack_path: String,
		category: String,
		default_replace_files: bool,
		priority: int,
		discovery_order: int,
		data_dir: String
	) -> Dictionary:
	var metadata: Dictionary = _read_pack_manifest(pack_path)
	var pack_id: String = _normalize_pack_id(String(metadata.get("id", "")))
	if pack_id == "":
		pack_id = _default_pack_id(pack_path, data_dir)
	var replace_files: bool = default_replace_files
	var replace_value = metadata.get("replace_files", null)
	if replace_value is bool:
		replace_files = bool(replace_value)
	return {
		"id": pack_id,
		"version": String(metadata.get("version", "0.0.0")).strip_edges(),
		"path": pack_path.simplify_path(),
		"category": category,
		"replace_files": replace_files,
		"priority": priority,
		"discovery_order": discovery_order,
		"dependencies": _parse_dependency_specs(metadata.get("dependencies", [])),
		"optional_dependencies": _parse_dependency_specs(metadata.get("optional_dependencies", [])),
		"load_after": _parse_pack_id_list(metadata.get("load_after", [])),
		"manifest_path": String(metadata.get("_manifest_path", "")),
		"preflight_error": "",
	}


func _read_pack_manifest(pack_path: String) -> Dictionary:
	var candidates: PackedStringArray = [
		pack_path + dependency_manifest_suffix,
		pack_path.get_basename() + dependency_manifest_suffix,
	]
	for manifest_path in candidates:
		if not FileAccess.file_exists(manifest_path):
			continue
		var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			var metadata: Dictionary = parsed
			metadata["_manifest_path"] = manifest_path
			return metadata
		push_warning("ContentPackManager: invalid dependency manifest: %s" % manifest_path)
	return {}


func _parse_dependency_specs(value) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is String:
			var string_id: String = _normalize_pack_id(String(entry))
			if string_id != "":
				result.append({"id": string_id, "version": ""})
		elif entry is Dictionary:
			var dictionary_id: String = _normalize_pack_id(String(entry.get("id", "")))
			if dictionary_id != "":
				result.append({"id": dictionary_id, "version": String(entry.get("version", "")).strip_edges()})
	return result


func _parse_pack_id_list(value) -> PackedStringArray:
	var result: PackedStringArray = []
	if not (value is Array):
		return result
	for entry in value:
		var pack_id: String = _normalize_pack_id(String(entry))
		if pack_id != "" and not result.has(pack_id):
			result.append(pack_id)
	return result


func _collect_pack_paths(directory_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	_collect_pack_paths_recursive(directory_path, result)
	result.sort()
	return result


func _collect_pack_paths_recursive(directory_path: String, result: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(directory_path):
		return
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while entry_name != "":
		if not entry_name.begins_with("."):
			var full_path: String = directory_path.path_join(entry_name).simplify_path()
			if directory.current_is_dir():
				_collect_pack_paths_recursive(full_path, result)
			elif entry_name.get_extension().to_lower() == "pck":
				result.append(full_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _collect_dependency_closure(root_descriptors: Array) -> Array:
	var selected_by_id: Dictionary = {}
	var pending: Array = root_descriptors.duplicate()
	while not pending.is_empty():
		var descriptor_value = pending.pop_back()
		if not (descriptor_value is Dictionary):
			continue
		var descriptor: Dictionary = descriptor_value
		var pack_id: String = String(descriptor.get("id", ""))
		if pack_id == "" or selected_by_id.has(pack_id):
			continue
		selected_by_id[pack_id] = descriptor
		var dependency_groups: Array = [
			descriptor.get("dependencies", []),
			descriptor.get("optional_dependencies", []),
		]
		for dependency_group in dependency_groups:
			if not (dependency_group is Array):
				continue
			for dependency_value in dependency_group:
				if not (dependency_value is Dictionary):
					continue
				var dependency_id: String = String(dependency_value.get("id", ""))
				var dependency_descriptor = _pack_catalog_by_id.get(dependency_id, null)
				if dependency_descriptor is Dictionary:
					pending.append(dependency_descriptor)
	return selected_by_id.values()


func _sort_descriptors_by_dependencies(descriptors: Array) -> Array:
	var selected_by_id: Dictionary = {}
	for descriptor_value in descriptors:
		if descriptor_value is Dictionary:
			var descriptor: Dictionary = descriptor_value
			selected_by_id[String(descriptor.get("id", ""))] = descriptor

	var indegree: Dictionary = {}
	var dependents: Dictionary = {}
	for pack_id in selected_by_id.keys():
		indegree[pack_id] = 0
		dependents[pack_id] = []
	for pack_id in selected_by_id.keys():
		var descriptor: Dictionary = selected_by_id[pack_id]
		var ordering_ids: PackedStringArray = _get_hard_dependency_ids(descriptor, selected_by_id)
		for dependency_id in ordering_ids:
			_add_dependency_edge(String(pack_id), dependency_id, indegree, dependents)
	for pack_id in selected_by_id.keys():
		var descriptor: Dictionary = selected_by_id[pack_id]
		var load_after_value = descriptor.get("load_after", PackedStringArray())
		if not (load_after_value is PackedStringArray):
			continue
		for dependency_id in load_after_value:
			if not selected_by_id.has(dependency_id):
				continue
			if _dependency_graph_has_path(String(pack_id), dependency_id, dependents, {}):
				push_warning("ContentPackManager: ignored cyclic load_after rule: %s after %s" % [String(pack_id), dependency_id])
				continue
			_add_dependency_edge(String(pack_id), dependency_id, indegree, dependents)

	var ready: Array = []
	for pack_id in selected_by_id.keys():
		if int(indegree.get(pack_id, 0)) == 0:
			ready.append(selected_by_id[pack_id])
	_sort_descriptor_array(ready)
	var ordered: Array = []
	while not ready.is_empty():
		var descriptor: Dictionary = ready.pop_front()
		ordered.append(descriptor)
		var pack_id: String = String(descriptor.get("id", ""))
		for dependent_id in dependents.get(pack_id, []):
			indegree[dependent_id] = int(indegree.get(dependent_id, 0)) - 1
			if int(indegree.get(dependent_id, 0)) == 0:
				ready.append(selected_by_id[dependent_id])
				_sort_descriptor_array(ready)

	if ordered.size() != selected_by_id.size():
		for pack_id in selected_by_id.keys():
			var descriptor: Dictionary = selected_by_id[pack_id]
			if ordered.has(descriptor):
				continue
			descriptor["preflight_error"] = "Dependency ordering cycle detected"
			ordered.append(descriptor)
	return ordered


func _get_hard_dependency_ids(descriptor: Dictionary, selected_by_id: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	var dependency_groups: Array = [
		descriptor.get("dependencies", []),
		descriptor.get("optional_dependencies", []),
	]
	for dependency_group in dependency_groups:
		if not (dependency_group is Array):
			continue
		for dependency_value in dependency_group:
			if not (dependency_value is Dictionary):
				continue
			var dependency_id: String = String(dependency_value.get("id", ""))
			if selected_by_id.has(dependency_id) and not result.has(dependency_id):
				result.append(dependency_id)
	return result


func _add_dependency_edge(pack_id: String, dependency_id: String, indegree: Dictionary, dependents: Dictionary) -> void:
	var dependent_list: Array = dependents.get(dependency_id, [])
	if dependent_list.has(pack_id):
		return
	indegree[pack_id] = int(indegree.get(pack_id, 0)) + 1
	dependent_list.append(pack_id)
	dependents[dependency_id] = dependent_list


func _dependency_graph_has_path(from_id: String, target_id: String, dependents: Dictionary, visited: Dictionary) -> bool:
	if from_id == target_id:
		return true
	if visited.has(from_id):
		return false
	visited[from_id] = true
	for dependent_id in dependents.get(from_id, []):
		if _dependency_graph_has_path(String(dependent_id), target_id, dependents, visited):
			return true
	return false


func _sort_descriptor_array(descriptors: Array) -> void:
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority: int = int(a.get("priority", 0))
		var b_priority: int = int(b.get("priority", 0))
		if a_priority != b_priority:
			return a_priority < b_priority
		var a_order: int = int(a.get("discovery_order", 0))
		var b_order: int = int(b.get("discovery_order", 0))
		if a_order != b_order:
			return a_order < b_order
		return String(a.get("id", "")) < String(b.get("id", ""))
	)


func _load_descriptors(descriptors: Array) -> void:
	for descriptor_value in descriptors:
		if not (descriptor_value is Dictionary):
			continue
		var descriptor: Dictionary = descriptor_value
		var pack_id: String = String(descriptor.get("id", ""))
		var preflight_error: String = String(descriptor.get("preflight_error", ""))
		if preflight_error != "":
			_report_pack_failure(pack_id, preflight_error)
			if reject_invalid_dependencies:
				continue
		var dependency_error: String = _get_required_dependency_error(descriptor)
		if dependency_error != "":
			_report_pack_failure(pack_id, dependency_error)
			if reject_invalid_dependencies:
				continue
		var pack_path: String = String(descriptor.get("path", ""))
		var replace_files: bool = bool(descriptor.get("replace_files", false))
		if _load_pack(pack_path, replace_files):
			_loaded_pack_ids[pack_id] = descriptor


func _get_required_dependency_error(descriptor: Dictionary) -> String:
	var dependencies_value = descriptor.get("dependencies", [])
	if not (dependencies_value is Array):
		return ""
	for dependency_value in dependencies_value:
		if not (dependency_value is Dictionary):
			continue
		var dependency_id: String = String(dependency_value.get("id", ""))
		var dependency_descriptor_value = _pack_catalog_by_id.get(dependency_id, null)
		if not (dependency_descriptor_value is Dictionary):
			return "Missing required dependency: %s" % dependency_id
		if not _loaded_pack_ids.has(dependency_id):
			return "Required dependency failed to load: %s" % dependency_id
		var required_version: String = String(dependency_value.get("version", ""))
		var dependency_descriptor: Dictionary = dependency_descriptor_value
		var installed_version: String = String(dependency_descriptor.get("version", "0.0.0"))
		if not _version_satisfies(installed_version, required_version):
			return "Dependency %s version %s does not satisfy %s" % [dependency_id, installed_version, required_version]
	return ""


func _report_pack_failure(pack_id: String, reason: String) -> void:
	push_warning("ContentPackManager: %s: %s" % [pack_id, reason])
	pack_load_failed.emit(pack_id, reason)


func _version_satisfies(version: String, constraint: String) -> bool:
	var cleaned_constraint: String = constraint.strip_edges()
	if cleaned_constraint == "" or cleaned_constraint == "*":
		return true
	var tokens: PackedStringArray = cleaned_constraint.replace(",", " ").split(" ", false)
	for token in tokens:
		if not _version_satisfies_token(version, String(token)):
			return false
	return true


func _version_satisfies_token(version: String, token: String) -> bool:
	var operator: String = "="
	var expected: String = token.strip_edges()
	for candidate_operator in [">=", "<=", ">", "<", "==", "=", "^", "~"]:
		if expected.begins_with(candidate_operator):
			operator = candidate_operator
			expected = expected.trim_prefix(candidate_operator).strip_edges()
			break
	var comparison: int = _compare_versions(version, expected)
	if operator == ">=":
		return comparison >= 0
	if operator == "<=":
		return comparison <= 0
	if operator == ">":
		return comparison > 0
	if operator == "<":
		return comparison < 0
	if operator == "^":
		var caret_current_parts: PackedInt32Array = _version_parts(version)
		var caret_expected_parts: PackedInt32Array = _version_parts(expected)
		if comparison < 0 or caret_current_parts[0] != caret_expected_parts[0]:
			return false
		if caret_expected_parts[0] > 0:
			return true
		if caret_current_parts[1] != caret_expected_parts[1]:
			return false
		if caret_expected_parts[1] > 0:
			return true
		return caret_current_parts[2] == caret_expected_parts[2]
	if operator == "~":
		var tilde_current_parts: PackedInt32Array = _version_parts(version)
		var tilde_expected_parts: PackedInt32Array = _version_parts(expected)
		return comparison >= 0 and tilde_current_parts[0] == tilde_expected_parts[0] and tilde_current_parts[1] == tilde_expected_parts[1]
	return comparison == 0


func _compare_versions(a: String, b: String) -> int:
	var a_parts: PackedInt32Array = _version_parts(a)
	var b_parts: PackedInt32Array = _version_parts(b)
	for index in range(3):
		if a_parts[index] < b_parts[index]:
			return -1
		if a_parts[index] > b_parts[index]:
			return 1
	return 0


func _version_parts(version: String) -> PackedInt32Array:
	var normalized: String = version.strip_edges().trim_prefix("v")
	var release_parts: PackedStringArray = normalized.split("-", false)
	if not release_parts.is_empty():
		normalized = release_parts[0]
	var raw_parts: PackedStringArray = normalized.split(".", false)
	var result: PackedInt32Array = PackedInt32Array([0, 0, 0])
	for index in range(min(raw_parts.size(), 3)):
		if String(raw_parts[index]).is_valid_int():
			result[index] = int(raw_parts[index])
	return result


func _normalize_pack_id(value: String) -> String:
	return value.strip_edges().to_lower()


func _default_pack_id(pack_path: String, data_dir: String) -> String:
	var normalized_path: String = pack_path.replace("\\", "/")
	var normalized_data_dir: String = data_dir.replace("\\", "/").trim_suffix("/")
	var relative_path: String = normalized_path.trim_prefix(normalized_data_dir).trim_prefix("/")
	return _normalize_pack_id(relative_path.get_basename())


func get_data_directory() -> String:
	return _resolve_data_dir()


func _resolve_data_dir() -> String:
	var base_dir: String = OS.get_executable_path().get_base_dir()
	var data_dir: String = base_dir.path_join(data_folder_name)
	if DirAccess.dir_exists_absolute(data_dir):
		return data_dir

	if OS.has_feature("macos"):
		var app_bundle_dir: String = base_dir.get_base_dir().get_base_dir()
		var distribution_dir: String = app_bundle_dir.get_base_dir()
		var macos_data_dir: String = distribution_dir.path_join(data_folder_name)
		if DirAccess.dir_exists_absolute(macos_data_dir):
			return macos_data_dir

	var project_root: String = ProjectSettings.globalize_path("res://")
	var dev_dir: String = project_root.path_join(data_folder_name)
	if DirAccess.dir_exists_absolute(dev_dir):
		return dev_dir
	return ""


func _load_pack_list(base_dir: String, pack_names: PackedStringArray, replace_files: bool) -> void:
	for pack_name in pack_names:
		var name := String(pack_name).strip_edges()
		if name == "":
			continue
		_load_pack(base_dir.path_join(name), replace_files)


func _load_pack_dir(dir_path: String, replace_files: bool, recursive: bool) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path := dir_path.path_join(name)
		if dir.current_is_dir():
			if recursive:
				_load_pack_dir(full_path, replace_files, recursive)
		else:
			if name.get_extension().to_lower() == "pck":
				_load_pack(full_path, replace_files)
		name = dir.get_next()
	dir.list_dir_end()


func _load_pack(path: String, replace_files: bool) -> bool:
	if path == "":
		return false
	if _loaded_packs.has(path):
		return true
	if not FileAccess.file_exists(path):
		if verbose_logging:
			print("ContentPackManager: pack missing: %s" % path)
		return false
	var ok := ProjectSettings.load_resource_pack(path, replace_files)
	if verbose_logging:
		var status: String = "failed"
		if ok:
			status = "loaded"
		print("ContentPackManager: %s %s" % [status, path])
	if ok:
		_loaded_packs[path] = true
	return ok

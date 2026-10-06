extends Resource
class_name AudioPreparationManifest

const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3", "flac"]

## Character scenes whose audio dependencies must remain resident while their characters are in use.
@export var character_roots: Array[String] = []
## Level scenes whose audio dependencies must remain resident until the level is unloaded.
@export var level_roots: Array[String] = []
## Audio resources that are not reachable through a character or level scene dependency.
@export var additional_audio_paths: Array[String] = []


func get_character_audio_by_root() -> Dictionary:
	return _collect_audio_by_root(character_roots)


func get_level_audio_by_root() -> Dictionary:
	return _collect_audio_by_root(level_roots)


func get_additional_audio_paths() -> Array[String]:
	var audio_paths: Array[String] = []
	for path: String in additional_audio_paths:
		var normalized_path: String = path.strip_edges()
		if _is_audio_path(normalized_path) and not audio_paths.has(normalized_path):
			audio_paths.append(normalized_path)
	return audio_paths


func get_character_signature() -> String:
	var normalized_roots: Array[String] = []
	for root: String in character_roots:
		var normalized_root: String = root.strip_edges()
		if normalized_root != "" and not normalized_roots.has(normalized_root):
			normalized_roots.append(normalized_root)
	normalized_roots.sort()
	return "|".join(normalized_roots)


func _collect_audio_by_root(roots: Array[String]) -> Dictionary:
	var audio_by_root: Dictionary = {}
	for root: String in roots:
		var normalized_root: String = root.strip_edges()
		if normalized_root == "" or audio_by_root.has(normalized_root):
			continue
		var audio_paths: Array[String] = []
		var visited: Dictionary = {}
		_collect_audio_dependencies(normalized_root, visited, audio_paths)
		audio_by_root[normalized_root] = audio_paths
	return audio_by_root


func _collect_audio_dependencies(
		resource_path: String,
		visited: Dictionary,
		audio_paths: Array[String]
	) -> void:
	if resource_path == "" or visited.has(resource_path):
		return
	visited[resource_path] = true
	if _is_audio_path(resource_path) and not audio_paths.has(resource_path):
		audio_paths.append(resource_path)
	for dependency_entry: String in ResourceLoader.get_dependencies(resource_path):
		var dependency_path: String = _resolve_dependency_path(dependency_entry)
		_collect_audio_dependencies(dependency_path, visited, audio_paths)


func _is_audio_path(resource_path: String) -> bool:
	return AUDIO_EXTENSIONS.has(resource_path.get_extension().to_lower())


func _resolve_dependency_path(dependency_entry: String) -> String:
	if dependency_entry.contains("::"):
		var fallback_path: String = dependency_entry.get_slice("::", 2).strip_edges()
		if fallback_path != "":
			return fallback_path
		return dependency_entry.get_slice("::", 0).strip_edges()
	return dependency_entry.strip_edges()

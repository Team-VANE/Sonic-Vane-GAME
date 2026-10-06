@tool
class_name LMChoicesFileGlob extends LMChoicesProvider

@export_dir var search_path: String
@export var glob_pattern: String
@export var load_as_resource: bool = false

func get_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if search_path.is_empty():
		return result
	_scan_dir(search_path, result)
	return result

func _matches_glob(file: String) -> bool:
	if glob_pattern.is_empty():
		return true
	for pattern in glob_pattern.split(","):
		if file.match(pattern.strip_edges()):
			return true
	return false

func _scan_dir(dir: String, result: Array[Dictionary]) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "import":
			continue
		if _matches_glob(file):
			result.append({"label": file.get_basename(), "value": dir.path_join(file)})
	for subdir in DirAccess.get_directories_at(dir):
		_scan_dir(dir.path_join(subdir), result)


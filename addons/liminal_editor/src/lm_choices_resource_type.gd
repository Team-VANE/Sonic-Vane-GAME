@tool
class_name LMChoicesResourceType extends LMChoicesProvider

@export_dir var search_path: String
@export var resource_type: String

func get_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if search_path.is_empty() or resource_type.is_empty():
		return result
	_scan_dir(search_path, result)
	return result

func _is_type(res: Resource) -> bool:
	if res.is_class(resource_type):
		return true
	var script: Script = res.get_script()
	while script:
		if script.get_global_name() == resource_type:
			return true
		script = script.get_base_script()
	return false

func _scan_dir(dir: String, result: Array[Dictionary]) -> void:
	for file in DirAccess.get_files_at(dir):
		var ext := file.get_extension()
		if ext == "import" or ext not in ["tres", "res"]:
			continue
		var path := dir.path_join(file)
		var res := ResourceLoader.load(path)
		if res and _is_type(res):
			result.append({"label": file.get_basename(), "value": path})
	for subdir in DirAccess.get_directories_at(dir):
		_scan_dir(dir.path_join(subdir), result)


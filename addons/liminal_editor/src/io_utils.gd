class_name LMIOUtils extends RefCounted

static func find_files_recursively(in_directory: String) -> Array[String]:
	var ret: Array[String] = []
	var queue: Array[String] = [""]
	while !queue.is_empty():
		var p: String = queue.pop_front()
		var full_dir_path := in_directory.path_join(p)
		for file in DirAccess.get_files_at(full_dir_path):
			ret.append(p.path_join(file))
		for dir in DirAccess.get_directories_at(full_dir_path):
			queue.append(p.path_join(dir) if p != in_directory else dir)
	return ret

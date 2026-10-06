@tool
class_name LMMapExportPlugin extends EditorExportPlugin


func _get_name() -> String:
	return "liminal_editor.lm_cache"

func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	if path.get_extension() != "lm":
		return
	var cache_dir: String = LMMapImporter.cache_dir_for(path)
	var d := DirAccess.open(cache_dir)
	if d == null:
		push_error("[LM] Export: no geometry cache for '%s' (expected at '%s'). The exported map will fail to load — (re)import the .lm before exporting." % [path, cache_dir])
		return
	for f in d.get_files():
		if f == LMMapImporter.HASHES_FILE:
			continue
		var fpath: String = cache_dir.path_join(f)
		add_file(fpath, FileAccess.get_file_as_bytes(fpath), false)

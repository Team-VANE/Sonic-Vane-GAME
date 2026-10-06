@tool
class_name LMSyncCache extends RefCounted


const CACHE_PATH := "res://.godot/lm_sync_cache.json"
const CACHE_FORMAT := 1

var _entries: Dictionary = {}


static func open() -> LMSyncCache:
	var cache := LMSyncCache.new()
	if FileAccess.file_exists(CACHE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
		if parsed is Dictionary and int(parsed.get("format", -1)) == CACHE_FORMAT:
			var entries: Variant = parsed.get("entries", {})
			if entries is Dictionary:
				cache._entries = entries
	return cache


func save() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[LM] Could not write sync cache to '%s'" % CACHE_PATH)
		return
	f.store_string(JSON.stringify({"format": CACHE_FORMAT, "entries": _entries}))
	f.close()


func clear() -> void:
	_entries.clear()


func is_fresh(output_path: String, fingerprint: String) -> bool:
	if not FileAccess.file_exists(output_path):
		return false
	return _entries.get(output_path, "") == fingerprint


func record(output_path: String, fingerprint: String) -> void:
	_entries[output_path] = fingerprint


static func fingerprint(sources: Array, extra: Array = []) -> String:
	var acc: int = hash(CACHE_FORMAT)
	var seen: Dictionary = {}
	var queue: Array = sources.duplicate()
	while not queue.is_empty():
		var path: String = str(queue.pop_back())
		if path.contains("::"):
			path = path.substr(path.rfind("::") + 2)
		if path.begins_with("uid://"):
			var uid_int := ResourceUID.text_to_id(path)
			if uid_int == ResourceUID.INVALID_ID:
				continue
			path = ResourceUID.get_id_path(uid_int)
		if path.is_empty() or seen.has(path):
			continue
		seen[path] = true
		acc = _mix(acc, path.hash())
		acc = _mix(acc, hash(FileAccess.get_modified_time(path)))
		var import_path := path + ".import"
		if FileAccess.file_exists(import_path):
			acc = _mix(acc, hash(FileAccess.get_modified_time(import_path)))
		for dep in ResourceLoader.get_dependencies(path):
			queue.append(dep)
	for e in extra:
		acc = _mix(acc, hash(e))
	return String.num_uint64(acc)


static func _mix(a: int, b: int) -> int:
	return (a * 31 + b) & 0x7FFFFFFFFFFFFFFF

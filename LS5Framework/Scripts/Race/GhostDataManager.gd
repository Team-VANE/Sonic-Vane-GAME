extends RefCounted
class_name GhostDataManager

const ROOT_DIR: String = "user://Ghost"
const FILE_EXTENSION: String = "ghost"
const FORMAT_VERSION: int = 1
const SUPPORTED_TICK_RATES: Array[int] = [15, 30, 60]
const DEFAULT_TICK_RATE: int = 30
const DEFAULT_PLAYBACK_TICK_RATE: int = 60
const LEGACY_TICK_RATE: int = 15
const TICK_RATE: float = 30.0
const MAX_DURATION_SECONDS: float = 300.0
const RACE_ID_RULES_TEXT: String = "Race ID must be 1-8 characters with no spaces or special characters."
const RACE_TYPE_CLASSIC: String = "Classic Race"
const RACE_TYPE_COLLECTION: String = "Collection Race"
const RACE_TYPE_RING: String = "Ring Race"


static func get_tick_interval(tick_rate: int = DEFAULT_TICK_RATE) -> float:
	return 1.0 / float(normalize_recording_tick_rate(tick_rate))


static func normalize_recording_tick_rate(tick_rate: int) -> int:
	if SUPPORTED_TICK_RATES.has(tick_rate):
		return tick_rate
	var closest_rate: int = DEFAULT_TICK_RATE
	var closest_distance: int = abs(tick_rate - closest_rate)
	for rate: int in SUPPORTED_TICK_RATES:
		var distance: int = abs(tick_rate - rate)
		if distance < closest_distance:
			closest_rate = rate
			closest_distance = distance
	return closest_rate


static func get_payload_tick_rate(data: Dictionary) -> int:
	var tick_rate: int = int(data.get("tick_rate", LEGACY_TICK_RATE))
	if tick_rate <= 0 or tick_rate > 240:
		return LEGACY_TICK_RATE
	return tick_rate


static func get_race_id_rules_text() -> String:
	return RACE_ID_RULES_TEXT


static func normalize_race_type(race_type: String) -> String:
	var normalized: String = race_type.strip_edges().to_lower()
	if normalized == RACE_TYPE_COLLECTION.to_lower() or normalized == "collection" or normalized == "collection_race":
		return RACE_TYPE_COLLECTION
	if normalized == RACE_TYPE_RING.to_lower() or normalized == "ring" or normalized == "ring_race":
		return RACE_TYPE_RING
	return RACE_TYPE_CLASSIC


static func get_payload_race_type(data: Dictionary) -> String:
	return normalize_race_type(String(data.get("race_type", RACE_TYPE_CLASSIC)))


static func is_valid_race_id(race_id: String) -> bool:
	var trimmed := race_id.strip_edges()
	if trimmed == "":
		return false
	if trimmed.length() > 8:
		return false
	for i in range(trimmed.length()):
		var code := trimmed.unicode_at(i)
		if code <= 32:
			return false
		var ch := trimmed.substr(i, 1)
		if ch == "/" or ch == "\\" or ch == ":" or ch == "*" or ch == "?" or ch == '"' or ch == "<" or ch == ">" or ch == "|":
			return false
	return true


static func sanitize_path_component(value: String, allow_spaces: bool = true) -> String:
	var trimmed := value.strip_edges()
	if trimmed == "":
		return "Unknown"
	var out := ""
	for i in range(trimmed.length()):
		var code := trimmed.unicode_at(i)
		var ch := trimmed.substr(i, 1)
		var is_space := code <= 32
		var invalid := ch == "/" or ch == "\\" or ch == ":" or ch == "*" or ch == "?" or ch == '"' or ch == "<" or ch == ">" or ch == "|"
		if invalid:
			out += "_"
		elif is_space:
			out += " " if allow_spaces else "_"
		else:
			out += ch
	out = out.strip_edges()
	if out == "":
		return "Unknown"
	return out


static func get_level_folder_name(level_name: String, level_key: String) -> String:
	var basis := level_name.strip_edges()
	if basis == "":
		basis = level_key.strip_edges()
	return sanitize_path_component(basis, true)


static func get_ghost_dir(level_name: String, level_key: String, race_id: String) -> String:
	return "%s/%s/%s" % [
		ROOT_DIR,
		get_level_folder_name(level_name, level_key),
		sanitize_path_component(race_id.strip_edges(), false)
	]


static func ensure_ghost_dir(level_name: String, level_key: String, race_id: String) -> String:
	if not is_valid_race_id(race_id):
		return ""
	var dir_path := get_ghost_dir(level_name, level_key, race_id)
	var abs_path := ProjectSettings.globalize_path(dir_path)
	var err := DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return ""
	return dir_path


static func build_ghost_payload(
		level_name: String,
		level_key: String,
		race_id: String,
		finish_time: float,
		score: int,
		samples: Array,
		race_type: String = RACE_TYPE_CLASSIC,
		tick_rate: int = DEFAULT_TICK_RATE
	) -> Dictionary:
	var now_unix: float = Time.get_unix_time_from_system()
	var now_dict: Dictionary = Time.get_datetime_dict_from_system()
	var normalized_tick_rate: int = normalize_recording_tick_rate(tick_rate)
	return {
		"format_version": FORMAT_VERSION,
		"tick_rate": normalized_tick_rate,
		"max_duration_seconds": MAX_DURATION_SECONDS,
		"level_name": level_name,
		"level_key": level_key,
		"race_id": race_id.strip_edges(),
		"race_type": normalize_race_type(race_type),
		"finish_time": max(finish_time, 0.0),
		"score": score,
		"created_at_unix": now_unix,
		"created_at_text": "%04d-%02d-%02d %02d:%02d:%02d" % [
			int(now_dict.get("year", 0)),
			int(now_dict.get("month", 0)),
			int(now_dict.get("day", 0)),
			int(now_dict.get("hour", 0)),
			int(now_dict.get("minute", 0)),
			int(now_dict.get("second", 0))
		],
		"samples": samples.duplicate(true)
	}


static func save_ghost(payload: Dictionary) -> String:
	if payload.is_empty():
		return ""
	var finish_time := float(payload.get("finish_time", -1.0))
	if finish_time <= 0.0 or finish_time > MAX_DURATION_SECONDS:
		return ""
	var level_name := String(payload.get("level_name", ""))
	var level_key := String(payload.get("level_key", ""))
	var race_id := String(payload.get("race_id", ""))
	if not is_valid_race_id(race_id):
		return ""
	var samples = payload.get("samples", [])
	if not (samples is Array) or (samples as Array).is_empty():
		return ""
	var dir_path := ensure_ghost_dir(level_name, level_key, race_id)
	if dir_path == "":
		return ""
	var file_name := _build_auto_file_name(finish_time)
	var save_path := _make_unique_file_path(dir_path, file_name)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return ""
		
	file.store_string(JSON.stringify(payload))
	return save_path


static func load_ghost(file_path: String) -> Dictionary:
	if file_path.strip_edges() == "":
		return {}
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_as_text()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	if not _is_valid_payload(data):
		return {}
	return data


static func list_ghosts_for_race(level_name: String, level_key: String, race_id: String, race_type: String = RACE_TYPE_CLASSIC) -> Array:
	var out: Array = []
	if not is_valid_race_id(race_id):
		return out
	var dir_path := get_ghost_dir(level_name, level_key, race_id)
	var abs_path := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		var name_str := String(file_name)
		if not name_str.to_lower().ends_with("." + FILE_EXTENSION):
			continue
		var full_path := dir_path.path_join(name_str)
		var data := load_ghost(full_path)
		if data.is_empty():
			continue
		if not is_ghost_for_context(data, level_key, race_id, race_type):
			continue
		_insert_sorted_summary(out, _build_summary(data, full_path))
	return out


static func list_all_ghost_paths() -> Array[String]:
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ROOT_DIR)):
		return paths
	var pending: Array[String] = [ROOT_DIR]
	while not pending.is_empty():
		var directory_path: String = pending.pop_back()
		var directory: DirAccess = DirAccess.open(directory_path)
		if directory == null:
			continue
		for file_name: String in directory.get_files():
			var file_path: String = directory_path.path_join(file_name)
			if file_name.get_extension().to_lower() == FILE_EXTENSION and _is_ghost_path_in_root(file_path):
				paths.append(file_path)
		for child_name: String in directory.get_directories():
			if child_name == "." or child_name == ".." or directory.is_link(child_name):
				continue
			var child_path: String = directory_path.path_join(child_name)
			if _is_ghost_path_in_root(child_path):
				pending.append(child_path)
	return paths


static func list_ghost_paths_for_level(level_name: String, level_key: String) -> Array[String]:
	var paths: Array[String] = []
	if level_name.strip_edges() == "" and level_key.strip_edges() == "":
		return paths
	var level_dir: String = ROOT_DIR.path_join(get_level_folder_name(level_name, level_key))
	var level_prefix: String = level_dir.trim_suffix("/").to_lower() + "/"
	for file_path: String in list_all_ghost_paths():
		if file_path.to_lower().begins_with(level_prefix):
			paths.append(file_path)
	return paths


static func delete_ghost(file_path: String) -> Error:
	if not _is_ghost_path_in_root(file_path) or file_path.get_extension().to_lower() != FILE_EXTENSION:
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


static func delete_all_ghosts() -> Dictionary:
	var deleted: Array[String] = []
	var failed: Array[String] = []
	for file_path: String in list_all_ghost_paths():
		if delete_ghost(file_path) == OK:
			deleted.append(file_path)
		else:
			failed.append(file_path)
	return {"deleted": deleted, "failed": failed}


static func delete_ghosts_for_level(level_name: String, level_key: String) -> Dictionary:
	var deleted: Array[String] = []
	var failed: Array[String] = []
	for file_path: String in list_ghost_paths_for_level(level_name, level_key):
		if delete_ghost(file_path) == OK:
			deleted.append(file_path)
		else:
			failed.append(file_path)
	return {"deleted": deleted, "failed": failed}


static func _is_ghost_path_in_root(path: String) -> bool:
	var root_absolute: String = ProjectSettings.globalize_path(ROOT_DIR).simplify_path().replace("\\", "/").trim_suffix("/").to_lower()
	var path_absolute: String = ProjectSettings.globalize_path(path).simplify_path().replace("\\", "/").to_lower()
	return path_absolute.begins_with(root_absolute + "/")


static func get_best_ghost_path(level_name: String, level_key: String, race_id: String, race_type: String = RACE_TYPE_CLASSIC) -> String:
	var ghosts := list_ghosts_for_race(level_name, level_key, race_id, race_type)
	if ghosts.is_empty():
		return ""
	var best = ghosts[0]
	if best is Dictionary:
		return String(best.get("path", ""))
	return ""


static func is_ghost_for_context(data: Dictionary, level_key: String, race_id: String, race_type: String = RACE_TYPE_CLASSIC) -> bool:
	if data.is_empty():
		return false
	if String(data.get("level_key", "")).strip_edges() != level_key.strip_edges():
		return false
	if String(data.get("race_id", "")).strip_edges() != race_id.strip_edges():
		return false
	if get_payload_race_type(data) != normalize_race_type(race_type):
		return false
	return true


static func format_time(seconds_value: float) -> String:
	var elapsed: float = max(seconds_value, 0.0)
	var total_seconds: int = int(elapsed)
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	var hundredths: int = int((elapsed - total_seconds) * 100.0) % 100
	return "%02d:%02d:%02d" % [minutes, seconds, hundredths]


static func _build_auto_file_name(finish_time: float) -> String:
	var now_dict := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [
		int(now_dict.get("year", 0)),
		int(now_dict.get("month", 0)),
		int(now_dict.get("day", 0)),
		int(now_dict.get("hour", 0)),
		int(now_dict.get("minute", 0)),
		int(now_dict.get("second", 0))
	]
	var time_text := format_time(finish_time).replace(":", "-")
	return "ghost_%s_%s.%s" % [stamp, time_text, FILE_EXTENSION]


static func _make_unique_file_path(dir_path: String, file_name: String) -> String:
	var base_name := file_name.get_basename()
	var ext := file_name.get_extension()
	var candidate := dir_path.path_join(file_name)
	var suffix := 1
	while FileAccess.file_exists(candidate):
		candidate = dir_path.path_join("%s_%d.%s" % [base_name, suffix, ext])
		suffix += 1
	return candidate


static func _is_valid_payload(data: Dictionary) -> bool:
	if int(data.get("format_version", -1)) != FORMAT_VERSION:
		return false
	var finish_time := float(data.get("finish_time", -1.0))
	if finish_time <= 0.0 or finish_time > MAX_DURATION_SECONDS:
		return false
	var race_id := String(data.get("race_id", ""))
	if not is_valid_race_id(race_id):
		return false
	var race_type: String = get_payload_race_type(data)
	if race_type != RACE_TYPE_CLASSIC and race_type != RACE_TYPE_COLLECTION and race_type != RACE_TYPE_RING:
		return false
	var samples = data.get("samples", [])
	if not (samples is Array) or (samples as Array).is_empty():
		return false
	var tick_rate: int = get_payload_tick_rate(data)
	if tick_rate <= 0 or tick_rate > 240:
		return false
	return true


static func _insert_sorted_summary(out: Array, summary: Dictionary) -> void:
	var insert_at := out.size()
	for i in range(out.size()):
		var existing = out[i]
		if existing is Dictionary and _summary_beats(summary, existing):
			insert_at = i
			break
	out.insert(insert_at, summary)


static func _summary_beats(a: Dictionary, b: Dictionary) -> bool:
	var at := float(a.get("finish_time", 999999.0))
	var bt := float(b.get("finish_time", 999999.0))
	if is_equal_approx(at, bt):
		var ascore := int(a.get("score", 0))
		var bscore := int(b.get("score", 0))
		if ascore == bscore:
			return String(a.get("file_name", "")) < String(b.get("file_name", ""))
		return ascore > bscore
	return at < bt


static func _build_summary(data: Dictionary, full_path: String) -> Dictionary:
	var samples: Array = data.get("samples", []) as Array
	return {
		"path": full_path,
		"file_name": full_path.get_file(),
		"finish_time": float(data.get("finish_time", 0.0)),
		"formatted_time": format_time(float(data.get("finish_time", 0.0))),
		"score": int(data.get("score", 0)),
		"level_name": String(data.get("level_name", "")),
		"race_id": String(data.get("race_id", "")),
		"race_type": get_payload_race_type(data),
		"created_at_text": String(data.get("created_at_text", "")),
		"tick_rate": get_payload_tick_rate(data),
		"sample_count": samples.size(),
		"format_version": int(data.get("format_version", FORMAT_VERSION))
	}

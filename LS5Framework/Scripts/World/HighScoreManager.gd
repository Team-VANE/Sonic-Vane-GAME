extends RefCounted
class_name HighScoreManager

const SCORE_PATH := "user://high_scores.cfg"
const SECTION_LEVELS := "levels"


static func get_level_key(level_id: StringName, scene_path: String) -> String:
	var id_str := String(level_id)
	if id_str.strip_edges() != "":
		return id_str
	return scene_path.strip_edges()


static func get_best_time(level_key: String) -> float:
	if level_key.strip_edges() == "":
		return -1.0
	var cfg := ConfigFile.new()
	if cfg.load(SCORE_PATH) != OK:
		return -1.0
	var v = cfg.get_value(SECTION_LEVELS, level_key, -1.0)
	if v is float or v is int:
		return float(v)
	return -1.0


static func save_time_if_better(level_key: String, time_seconds: float) -> bool:
	if level_key.strip_edges() == "":
		return false
	var t : float = max(time_seconds, 0.0)
	var cfg := ConfigFile.new()
	var _err = cfg.load(SCORE_PATH)
	var current = cfg.get_value(SECTION_LEVELS, level_key, -1.0)
	var best: float = -1.0
	if current is float or current is int:
		best = float(current)
	if best > 0.0 and t >= best:
		return false
	cfg.set_value(SECTION_LEVELS, level_key, t)
	cfg.save(SCORE_PATH)
	return true

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


static func save_result_stats(level_key: String, rings: int, score: int, total: int) -> Array[String]:
	var records: Array[String] = []
	if level_key.strip_edges().is_empty():
		return records
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SCORE_PATH)
	var values: Dictionary = {"Rings": rings, "Score": score, "Total": total}
	for stat: String in values:
		var section: String = "results_" + stat.to_lower()
		var value: int = values[stat]
		if (cfg.has_section_key(section, level_key) and value <= int(cfg.get_value(section, level_key))) or value <= 0:
			continue
		cfg.set_value(section, level_key, value)
		records.append(stat)
	if not records.is_empty() and cfg.save(SCORE_PATH) != OK:
		records.clear()
	return records

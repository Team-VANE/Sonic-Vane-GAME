extends RefCounted
class_name AudioClipSelector

var _pools: Array[Dictionary] = []
var _metadata: Dictionary = {}


func register_clips(clips: Array, refresh: bool = false) -> Dictionary:
	for pool: Dictionary in _pools:
		if is_same(pool.source, clips):
			if not refresh and pool.count == clips.size():
				return pool
			_pools.erase(pool)
			break
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var total: float = 0.0
	for index: int in clips.size():
		var clip: AudioStream = clips[index] as AudioStream
		if not clip:
			continue
		var info: Dictionary = _register_clip(clip, refresh)
		if seen.has(info.key) or info.weight <= 0.0:
			continue
		seen[info.key] = true
		entries.append({"index": index, "key": info.key, "weight": info.weight})
		total += float(info.weight)
	var pool: Dictionary = {"source": clips, "count": clips.size(), "entries": entries, "total": total, "last": ""}
	if _pools.size() >= 128:
		_pools.pop_front()
	_pools.append(pool)
	return pool


func pick_index(clips: Array, avoid_repeat: bool = true, previous_clip: AudioStream = null) -> int:
	var pool: Dictionary = register_clips(clips)
	var previous: String = String(pool.last)
	if previous_clip:
		previous = String(_register_clip(previous_clip).key)
	var excluded_weight: float = 0.0
	if avoid_repeat and pool.entries.size() > 1:
		for entry: Dictionary in pool.entries:
			if entry.key == previous:
				excluded_weight = float(entry.weight)
	var total: float = float(pool.total) - excluded_weight
	if total <= 0.0:
		return -1
	var roll: float = randf() * total
	var selected: int = -1
	var selected_key: String = ""
	for entry: Dictionary in pool.entries:
		if excluded_weight > 0.0 and entry.key == previous:
			continue
		selected = int(entry.index)
		selected_key = String(entry.key)
		roll -= float(entry.weight)
		if roll < 0.0:
			break
	pool.last = selected_key
	return selected


func _register_clip(clip: AudioStream, refresh: bool = false) -> Dictionary:
	var id: int = clip.get_instance_id()
	if not refresh and _metadata.has(id):
		return _metadata[id]
	var weight: float = 1.0
	var filename: String = clip.resource_path.get_file().get_basename() if not clip.resource_path.contains("::") else ""
	for argument: String in filename.split(";", false):
		var assignment: PackedStringArray = argument.split("=", true, 1)
		if assignment.size() != 2 or assignment[0].strip_edges().to_lower() not in ["_weight", "_chance"]:
			continue
		var value: String = assignment[1].strip_edges()
		var fraction: PackedStringArray = value.split("-", true)
		var parsed: float = -1.0
		if value.is_valid_float():
			parsed = value.to_float()
		elif fraction.size() == 2 and fraction[0].strip_edges().is_valid_float() and fraction[1].strip_edges().is_valid_float():
			var denominator: float = fraction[1].to_float()
			if denominator > 0.0:
				parsed = fraction[0].to_float() / denominator
		if is_finite(parsed) and parsed >= 0.0:
			weight = parsed
		else:
			push_warning("Invalid audio selection weight on %s: %s" % [clip.resource_path, value])
	var key: String = clip.resource_path if clip.resource_path else "instance:%d" % id
	var info: Dictionary = {"key": key, "weight": weight}
	_metadata[id] = info
	return info

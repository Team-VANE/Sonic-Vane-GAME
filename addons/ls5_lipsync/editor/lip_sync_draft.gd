@tool
extends RefCounted

const SPELLINGS: Dictionary = {
	"VIS_AE": ["ae", "ai", "ay", "ei", "ey"],
	"VIS_Ah": ["ah", "a"],
	"VIS_B_M_P": ["b", "m", "p"],
	"VIS_Ch_J": ["tch", "dge", "ch", "sh", "j"],
	"VIS_EE": ["ee", "ea", "ie", "e", "y"],
	"VIS_F_V": ["f", "v", "ph"],
	"VIS_Ih": ["ih", "i"],
	"VIS_K_G_H_NG": ["ng", "ck", "k", "g", "h", "c", "q"],
	"VIS_Oh": ["oa", "oe", "ow", "oh", "aw", "au", "o"],
	"VIS_R": ["r"],
	"VIS_S_Z": ["ss", "s", "z"],
	"VIS_T_L_D_N": ["t", "l", "d", "n"],
	"VIS_Th": ["th"],
	"VIS_Uh": ["uh", "u"],
	"VIS_W_OO": ["oo", "ou", "ue", "ui", "w"],
}

const SHORT_EA_STEMS = ["head", "bread", "dead", "ready", "health", "wealth", "measure", "pleasant", "great", "break", "steak", "bear", "pear", "wear"]
const SHORT_OO_STEMS = ["book", "cook", "look", "good", "wood", "foot", "stood", "hood", "shook", "brook", "hook", "soot"]
const HARD_G_STARTS = ["get", "give", "gift", "girl", "gear", "geese", "gig"]


static func estimate_duration(transcript: String, words_per_minute: float = 165.0) -> float:
	var regex: RegEx = RegEx.new()
	regex.compile("[A-Za-z']+")
	var word_count: int = regex.search_all(transcript).size()
	return float(word_count) * 60.0 / maxf(words_per_minute, 1.0)


static func generate(clip: LipSyncClip) -> void:
	if not clip or not clip.profile or not clip.audio:
		return
	var words: Array[String] = []
	var regex: RegEx = RegEx.new()
	regex.compile("[A-Za-z']+")
	for result: RegExMatch in regex.search_all(clip.transcript):
		words.append(result.get_string())
	if words.is_empty():
		return
	var start_time: float = clampf(clip.audible_start, 0.0, clip.audio.get_length())
	var end_time: float = clip.audible_end if clip.audible_end > start_time else clip.audio.get_length()
	end_time = clampf(end_time, start_time, clip.audio.get_length())
	var word_units: Array[Array] = []
	var total_weight: float = 0.0
	var unit_count: int = 0
	for word: String in words:
		var units: Array[Dictionary] = _word_units(word.to_lower(), clip.profile)
		word_units.append(units)
		unit_count += units.size()
		for unit: Dictionary in units:
			total_weight += float(unit["weight"])
	if total_weight <= 0.0:
		return
	clip.viseme_cues.clear()
	clip.word_spans.clear()
	var available_time: float = end_time - start_time
	var gap_count: int = maxi(0, unit_count - 1)
	var minimum_cue_time: float = 0.02
	var maximum_padding: float = maxf(0.0, (available_time - float(unit_count) * minimum_cue_time) / float(gap_count)) if gap_count > 0 else 0.0
	var padding: float = minf(maxf(0.0, snappedf(clip.generation_padding, 0.01)), maximum_padding)
	var seconds_per_weight: float = maxf(0.0, available_time - padding * float(gap_count)) / total_weight
	var cursor: float = start_time
	var cue_index: int = 0
	for word_index: int in range(words.size()):
		var word_start: float = cursor
		var word_end: float = cursor
		for unit: Dictionary in word_units[word_index]:
			var cue: LipSyncCue = LipSyncCue.new()
			cue.pose_id = unit["id"]
			cue.start_time = cursor
			cursor += float(unit["weight"]) * seconds_per_weight
			cue.end_time = cursor
			cue.row = cue_index % LipSyncCue.ROW_COUNT
			var blend_limit: float = maxf(0.0, cue.end_time - cue.start_time) * 0.5
			cue.blend_in = minf(clip.new_blend_in, blend_limit)
			cue.blend_out = minf(clip.new_blend_out, blend_limit)
			clip.viseme_cues.append(cue)
			word_end = cursor
			cue_index += 1
			if cue_index < unit_count:
				cursor += padding
		clip.word_spans.append({"word": words[word_index], "start": word_start, "end": word_end})
	if is_zero_approx(padding):
		_crossfade_touching_cues(clip.viseme_cues)
	clip.emit_changed()


static func regenerate_from_words(clip: LipSyncClip) -> bool:
	if not clip or not clip.profile or clip.word_spans.is_empty():
		return false
	var units_by_word: Array[Array] = []
	for span: Dictionary in clip.word_spans:
		var word: String = String(span.get("word", ""))
		var start: float = float(span.get("start", 0.0))
		var end: float = float(span.get("end", 0.0))
		if word.strip_edges().is_empty() or end <= start:
			return false
		units_by_word.append(_word_units(word.to_lower(), clip.profile))
	clip.viseme_cues.clear()
	var padding: float = maxf(0.0, snappedf(clip.generation_padding, 0.01))
	var cue_index: int = 0
	for word_index: int in range(clip.word_spans.size()):
		var span: Dictionary = clip.word_spans[word_index]
		var start: float = float(span["start"])
		var end: float = float(span["end"])
		var left_trim: float = 0.0
		var right_trim: float = 0.0
		if word_index > 0:
			var previous_end: float = float(clip.word_spans[word_index - 1]["end"])
			left_trim = maxf(0.0, padding - maxf(0.0, start - previous_end)) * 0.5
		if word_index + 1 < clip.word_spans.size():
			var next_start: float = float(clip.word_spans[word_index + 1]["start"])
			right_trim = maxf(0.0, padding - maxf(0.0, next_start - end)) * 0.5
		var units: Array[Dictionary] = units_by_word[word_index]
		var minimum_cue_time: float = 0.02
		var trim_limit: float = maxf(0.0, end - start - float(units.size()) * minimum_cue_time)
		if left_trim + right_trim > trim_limit and left_trim + right_trim > 0.0:
			var trim_scale: float = trim_limit / (left_trim + right_trim)
			left_trim *= trim_scale
			right_trim *= trim_scale
		start += left_trim
		end -= right_trim
		var gap_count: int = maxi(0, units.size() - 1)
		var maximum_gap: float = maxf(0.0, (end - start - float(units.size()) * minimum_cue_time) / float(gap_count)) if gap_count > 0 else 0.0
		var local_padding: float = minf(padding, maximum_gap)
		var weight_total: float = 0.0
		for unit: Dictionary in units:
			weight_total += float(unit["weight"])
		var seconds_per_weight: float = maxf(0.0, end - start - local_padding * float(gap_count)) / maxf(weight_total, 0.001)
		var cursor: float = start
		for unit_index: int in range(units.size()):
			var unit: Dictionary = units[unit_index]
			var cue: LipSyncCue = LipSyncCue.new()
			cue.pose_id = unit["id"]
			cue.start_time = cursor
			cursor += float(unit["weight"]) * seconds_per_weight
			cue.end_time = cursor
			cue.row = cue_index % LipSyncCue.ROW_COUNT
			var blend_limit: float = maxf(0.0, cue.end_time - cue.start_time) * 0.5
			cue.blend_in = minf(clip.new_blend_in, blend_limit)
			cue.blend_out = minf(clip.new_blend_out, blend_limit)
			clip.viseme_cues.append(cue)
			cue_index += 1
			if unit_index + 1 < units.size():
				cursor += local_padding
	if is_zero_approx(padding):
		_crossfade_touching_cues(clip.viseme_cues)
	clip.emit_changed()
	return true


static func _crossfade_touching_cues(cues: Array[LipSyncCue]) -> void:
	cues.sort_custom(func(a: LipSyncCue, b: LipSyncCue) -> bool: return a.start_time < b.start_time)
	var base_durations: Array[float] = []
	for cue: LipSyncCue in cues:
		base_durations.append(maxf(0.0, cue.end_time - cue.start_time))
	for index: int in range(cues.size() - 1):
		var current: LipSyncCue = cues[index]
		var following: LipSyncCue = cues[index + 1]
		var gap: float = following.start_time - current.end_time
		if gap > 0.0:
			current.end_time += gap * 0.5
			following.start_time -= gap * 0.5
		var overlap: float = minf(current.blend_out, following.blend_in)
		overlap = minf(overlap, minf(base_durations[index], base_durations[index + 1]) * 0.5)
		current.end_time += overlap * 0.5
		following.start_time -= overlap * 0.5
		current.blend_out = overlap
		following.blend_in = overlap
	var covered_until: float = cues[0].end_time if not cues.is_empty() else 0.0
	for index: int in range(1, cues.size()):
		var cue: LipSyncCue = cues[index]
		if cue.start_time > covered_until:
			cue.start_time = covered_until
		covered_until = maxf(covered_until, cue.end_time)


static func _word_units(word: String, profile: LipSyncProfile) -> Array[Dictionary]:
	var custom_patterns: Array[Dictionary] = []
	var default_patterns: Array[Dictionary] = []
	for pose: LipSyncPose in profile.visemes:
		if not pose or pose.id == profile.silent_viseme_id:
			continue
		var spellings: PackedStringArray = pose.spelling_patterns
		var patterns: Array[Dictionary] = custom_patterns
		if spellings.is_empty():
			spellings = PackedStringArray(SPELLINGS.get(String(pose.id), []))
			patterns = default_patterns
		for spelling: String in spellings:
			if not spelling.is_empty():
				patterns.append({"text": spelling.to_lower(), "id": pose.id})
	custom_patterns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["text"]).length() > String(b["text"]).length())
	default_patterns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["text"]).length() > String(b["text"]).length())
	var units: Array[Dictionary] = []
	var index: int = 0
	while index < word.length():
		var letter: String = word.substr(index, 1)
		if letter == "'":
			index += 1
			continue
		var custom_match: Dictionary = _match_spelling(word, index, custom_patterns)
		if not custom_match.is_empty():
			_append_unit(units, custom_match["id"], String(custom_match["text"]))
			index += String(custom_match["text"]).length()
			continue
		if (index == 0 and word.substr(0, 2) in ["kn", "wr"]) or (letter == "b" and index > 0 and index == word.length() - 1 and word.substr(index - 1, 1) == "m"):
			index += 1
			continue
		if letter == "u" and (word.begins_with("guy") or word.begins_with("buy")):
			index += 1
			continue
		if index > 0 and letter == word.substr(index - 1, 1) and not _is_vowel(letter):
			index += 1
			continue
		if word.substr(index, 2) == "qu":
			_append_available_unit(units, profile, &"VIS_K_G_H_NG", "q")
			_append_available_unit(units, profile, &"VIS_W_OO", "w")
			index += 2
			continue
		if letter == "x":
			if index > 0:
				_append_available_unit(units, profile, &"VIS_K_G_H_NG", "k")
			_append_available_unit(units, profile, &"VIS_S_Z", "s")
			index += 1
			continue
		if word.substr(index, 2) == "gh":
			if index == 0:
				_append_available_unit(units, profile, &"VIS_K_G_H_NG", "g")
			elif _has_stem(word, ["laugh", "cough", "tough", "rough", "enough"]):
				_append_available_unit(units, profile, &"VIS_F_V", "f")
			index += 2
			continue
		var match_result: Dictionary = _match_spelling(word, index, default_patterns)
		if match_result.is_empty():
			index += 1
			continue
		var spelling: String = String(match_result["text"])
		var pose_id: StringName = _context_pose(word, index, spelling, match_result["id"], profile)
		if pose_id != &"":
			_append_unit(units, pose_id, spelling)
		index += spelling.length()
	if units.is_empty():
		units.append({"id": profile.silent_viseme_id, "weight": 1.0})
	return units


static func _match_spelling(word: String, index: int, patterns: Array[Dictionary]) -> Dictionary:
	for pattern: Dictionary in patterns:
		var spelling: String = String(pattern["text"])
		if word.substr(index, spelling.length()) == spelling:
			return pattern
	return {}


static func _append_available_unit(units: Array[Dictionary], profile: LipSyncProfile, pose_id: StringName, spelling: String) -> void:
	if profile.find_pose(pose_id):
		_append_unit(units, pose_id, spelling)


static func _append_unit(units: Array[Dictionary], pose_id: StringName, spelling: String) -> void:
	var vowel_pose: bool = pose_id in [&"VIS_AE", &"VIS_Ah", &"VIS_EE", &"VIS_Ih", &"VIS_Oh", &"VIS_Uh"]
	var vowel_spelling: bool = not spelling.is_empty() and _is_vowel(spelling.substr(0, 1))
	units.append({"id": pose_id, "weight": 1.3 if vowel_pose or vowel_spelling else 0.8})


static func _context_pose(word: String, index: int, spelling: String, fallback: StringName, profile: LipSyncProfile) -> StringName:
	var next_letter: String = word.substr(index + spelling.length(), 1)
	match spelling:
		"e":
			if index == word.length() - 1:
				if word == "the":
					return _available_pose(profile, &"VIS_Uh", fallback)
				return _available_pose(profile, &"VIS_EE", fallback) if word in ["be", "he", "me", "she", "we"] else &""
			if next_letter == "r":
				return _available_pose(profile, &"VIS_Uh", fallback)
			return _available_pose(profile, &"VIS_EE", fallback) if _has_magic_e(word, index) else _available_pose(profile, &"VIS_AE", fallback)
		"ea":
			return _available_pose(profile, &"VIS_AE", fallback) if _has_stem(word, SHORT_EA_STEMS) else fallback
		"ei":
			return _available_pose(profile, &"VIS_EE", fallback) if _has_stem(word, ["ceiv", "ceil", "seiz", "weird"]) else fallback
		"ey":
			return _available_pose(profile, &"VIS_EE", fallback) if _has_stem(word, ["key", "money", "honey", "monkey"]) else fallback
		"ie":
			return _available_pose(profile, &"VIS_AE", fallback) if word.ends_with("ie") and word.length() <= 4 else fallback
		"a":
			return _available_pose(profile, &"VIS_Ah", fallback) if next_letter == "r" else _available_pose(profile, &"VIS_AE", fallback)
		"i":
			if next_letter == "r":
				return _available_pose(profile, &"VIS_Uh", fallback)
			return _available_pose(profile, &"VIS_AE", fallback) if word == "i" or _has_magic_e(word, index) else fallback
		"o":
			if _has_magic_e(word, index) or index == word.length() - 1:
				return fallback
			return _available_pose(profile, &"VIS_Ah", fallback) if not next_letter.is_empty() and not _is_vowel(next_letter) and index + 2 >= word.length() else fallback
		"u":
			if _has_magic_e(word, index):
				return _available_pose(profile, &"VIS_W_OO", fallback)
			if next_letter == "r":
				return fallback
			return fallback if _has_stem(word, ["put", "push", "pull", "bush", "full"]) else _available_pose(profile, &"VIS_Ah", fallback)
		"y":
			return _available_pose(profile, &"VIS_AE", fallback) if word in ["my", "by", "why", "try", "fly", "sky", "cry", "dry", "shy", "reply"] or word.begins_with("guy") or word.begins_with("buy") else fallback
		"c":
			return _available_pose(profile, &"VIS_S_Z", fallback) if next_letter in ["e", "i", "y"] else fallback
		"g":
			return _available_pose(profile, &"VIS_Ch_J", fallback) if next_letter in ["e", "i", "y"] and not _has_stem(word, HARD_G_STARTS) else fallback
		"oo":
			return _available_pose(profile, &"VIS_Uh", fallback) if _has_stem(word, SHORT_OO_STEMS) else fallback
		"ou":
			if _has_stem(word, ["would", "could", "should", "touch", "young", "country"]):
				return _available_pose(profile, &"VIS_Uh", fallback)
			return _available_pose(profile, &"VIS_AE", fallback) if _has_stem(word, ["out", "ouse", "oud", "oun"]) else fallback
		"ow":
			return _available_pose(profile, &"VIS_AE", fallback) if _has_stem(word, ["cow", "how", "now", "wow", "down", "town", "brown", "flower", "power", "shower"]) else fallback
	return fallback


static func _available_pose(profile: LipSyncProfile, preferred: StringName, fallback: StringName) -> StringName:
	return preferred if profile.find_pose(preferred) else fallback


static func _has_magic_e(word: String, index: int) -> bool:
	if word in ["have", "give", "love", "some", "one", "done"]:
		return false
	return index == word.length() - 3 and word.ends_with("e") and not _is_vowel(word.substr(index + 1, 1))


static func _has_stem(word: String, stems: Array) -> bool:
	for stem: String in stems:
		if word.contains(stem):
			return true
	return false


static func _is_vowel(letter: String) -> bool:
	return letter in ["a", "e", "i", "o", "u"]


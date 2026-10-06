class_name LMCodeUtils extends RefCounted

static func _parse_comments_for_vars_in_script(script: Script) -> Dictionary[String, String]:
	var ret: Dictionary[String, String] = {}
	var comment_start: int = -1
	var line_counter: int = 0
	var src_lines: PackedStringArray = script.source_code.split("\n")
	for line in src_lines:
		if line.begins_with("\t"):
			pass
		elif line.strip_edges(true, true).is_empty():
			pass
		elif line.begins_with("##") && comment_start < 0:
			comment_start = line_counter
		elif line.contains("var "):
			var tokens: PackedStringArray = line.split(" ", false)
			var var_idx = tokens.find("var")
			if var_idx >= 0:
				var var_name: String = tokens[var_idx + 1]
				if var_name.ends_with(":"):
					var_name = var_name.left(-1)
				if comment_start >= 0:
					var comment_str: String = "\n".join(src_lines.slice(comment_start, line_counter)).right(-2).strip_edges(true, true)
					comment_start = -1
					ret.set(var_name, comment_str)
		elif comment_start >= 0:
			comment_start = -1
		line_counter += 1
	return ret

static func parse_comments_for_vars(obj: Object) -> Dictionary[String, String]:
	var ret: Dictionary[String, String] = {}
	var current: Script = obj.get_script()
	while current:
		if !current.source_code.is_empty():
			ret.merge(_parse_comments_for_vars_in_script(current))
		current = current.get_base_script()

	return ret

static func get_class_comment(obj: Object) -> String:
	var script = obj.get_script()
	if !script ||script.source_code.is_empty(): return ""

	var comment_start: int = -1
	var current_line: int = 0
	var src_lines: PackedStringArray = script.source_code.split("\n")
	for line in src_lines:
		if line.strip_edges(true, true).is_empty():
			pass
		elif line.begins_with("@tool") && comment_start < 0: pass
		elif line.contains(" extends ") && comment_start < 0: return ""
		elif comment_start < 0 && line.begins_with("##"):
			comment_start = current_line
		elif comment_start >= 0 && !line.begins_with("##"):
			break
		current_line += 1
	var ret: String = ""

	if comment_start >= 0:
		ret = "\n".join(src_lines.slice(comment_start, current_line)).replace("##", "")
	return ret

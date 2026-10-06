@tool
class_name LMTimings


const CFG_KEY_ENABLED := "liminal_editor/profiling/timings_enabled"
const REPORT_DIR := "res://.godot/liminal/timings"

static var force_enabled := false

static var _active := false
static var _session := ""
static var _t0 := 0
static var _phases: Dictionary = {}
static var _running: Dictionary = {}
static var _notes: Array[String] = []


static func is_enabled() -> bool:
	return force_enabled or bool(ProjectSettings.get_setting(CFG_KEY_ENABLED, false))


static func begin(session_name: String) -> void:
	_active = is_enabled()
	if not _active:
		return
	_session = session_name
	_phases.clear()
	_running.clear()
	_notes.clear()
	_t0 = Time.get_ticks_msec()


static func start(phase: String) -> void:
	if _active:
		_running[phase] = Time.get_ticks_msec()


static func stop(phase: String) -> void:
	if _active and _running.has(phase):
		add(phase, Time.get_ticks_msec() - _running[phase])
		_running.erase(phase)


static func add(phase: String, ms: float) -> void:
	if _active:
		_phases[phase] = _phases.get(phase, 0.0) + ms


static func note(text: String) -> void:
	if _active:
		_notes.append(text)


static func finish() -> String:
	if not _active:
		return ""
	_active = false
	var total := float(Time.get_ticks_msec() - _t0)
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/%s_%s.txt" % [REPORT_DIR, _session, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("LMTimings: cannot write report to '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	f.store_line("session: %s" % _session)
	f.store_line("total: %.0f ms" % total)
	f.store_line("")
	var phases := _phases.keys()
	phases.sort_custom(func(a, b) -> bool: return _phases[a] > _phases[b])
	for phase: String in phases:
		var ms: float = _phases[phase]
		var pct := " (%.1f%%)" % (100.0 * ms / total) if total > 0.0 else ""
		f.store_line("%-24s %10.1f ms%s" % [phase, ms, pct])
	if not _notes.is_empty():
		f.store_line("")
		for line in _notes:
			f.store_line(line)
	f.close()
	print("[LM] Timings report written to %s" % path)
	return path

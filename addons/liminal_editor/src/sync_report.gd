class_name LMSyncReport extends RefCounted

class EntityRow:
	var classname: String
	var source: String
	var prop_count: int
	var gizmo_count: int
	var has_preview: bool
	var is_volume: bool

class SkippedRow:
	var path: String
	var reason: String

class MaterialRow:
	var name: String
	var ok: bool
	var reason: String

var workspace_path: String = ""
var entities: Array[EntityRow] = []
var skipped: Array[SkippedRow] = []
var materials: Array[MaterialRow] = []
var config_errors: Array[String] = []


func add_entity(classname: String, source: String, prop_count: int, gizmo_count: int, has_preview: bool, is_volume: bool) -> void:
	var r := EntityRow.new()
	r.classname = classname
	r.source = source
	r.prop_count = prop_count
	r.gizmo_count = gizmo_count
	r.has_preview = has_preview
	r.is_volume = is_volume
	entities.append(r)


func add_skipped(path: String, reason: String) -> void:
	var r := SkippedRow.new()
	r.path = path
	r.reason = reason
	skipped.append(r)


func add_material(name: String, ok: bool, reason: String = "") -> void:
	var r := MaterialRow.new()
	r.name = name
	r.ok = ok
	r.reason = reason
	materials.append(r)


func add_config_error(msg: String) -> void:
	config_errors.append(msg)


func print_report() -> void:
	print("[LM] ======== SYNC REPORT ========")
	if not workspace_path.is_empty():
		print("[LM] Workspace: %s" % workspace_path)

	print("[LM] Entities exported: %d" % entities.size())
	for e: EntityRow in entities:
		print("[LM]   %-32s  props:%-3d  gizmos:%-2d  preview:%-3s  volume:%-3s  [%s]" % [
			e.classname, e.prop_count, e.gizmo_count,
			"yes" if e.has_preview else "no",
			"yes" if e.is_volume else "no",
			e.source,
		])

	var mat_ok: Array = materials.filter(func(m: MaterialRow) -> bool: return m.ok)
	var mat_fail: Array = materials.filter(func(m: MaterialRow) -> bool: return not m.ok)
	print("[LM] Materials exported: %d" % mat_ok.size())
	for m in mat_ok:
		print("[LM]   + %s" % m.name)

	var issue_count: int = config_errors.size() + skipped.size() + mat_fail.size()
	if issue_count > 0:
		print("[LM] Warnings & Failures (%d):" % issue_count)
		for msg: String in config_errors:
			print("[LM]   [CONFIG]  %s" % msg)
		for s in skipped:
			print("[LM]   [SKIPPED] %s - %s" % [s.path, s.reason])
		for m in mat_fail:
			print("[LM]   [MAT]     %s - %s" % [m.name, m.reason])
	else:
		print("[LM] No warnings or failures.")

	print("[LM] ================================")

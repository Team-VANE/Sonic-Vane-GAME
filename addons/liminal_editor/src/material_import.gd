@tool
class_name LMMaterialImport


const INCOMING_DIR_REL := "materials"
const INCOMING_PREFIX := "incoming_"
const INCOMING_SUFFIX := ".glb"

const IMPORTED_DIR := "res://materials/imported"
const TEX_SUBDIR := "textures"

const IMPORT_SCAN_ATTEMPTS := 3

enum TexRole { COLOR, NORMAL, LINEAR }

const _TEX_SLOTS := [
	{"prop": "albedo_texture", "suffix": "albedo", "role": TexRole.COLOR},
	{"prop": "normal_texture", "suffix": "normal", "role": TexRole.NORMAL},
	{"prop": "roughness_texture", "suffix": "rough", "role": TexRole.LINEAR},
	{"prop": "metallic_texture", "suffix": "metal", "role": TexRole.LINEAR},
	{"prop": "emission_texture", "suffix": "emission", "role": TexRole.COLOR},
	{"prop": "ao_texture", "suffix": "ao", "role": TexRole.LINEAR},
]

const _ORM_SUFFIXES := ["rough", "metal", "ao"]

static var _san_re: RegEx


static func ingest(dst_dir: String, report: LMSyncReport = null) -> PackedStringArray:
	var materials_dir: String = dst_dir.path_join(INCOMING_DIR_REL)
	var glb_paths := _find_incoming_glbs(materials_dir)
	if glb_paths.is_empty():
		return PackedStringArray()

	await _await_editor_idle()

	var names: PackedStringArray = []
	for glb_path in glb_paths:
		names.append_array(await _ingest_one(glb_path, _pack_name_from_path(glb_path), report))
	return names


static func _find_incoming_glbs(materials_dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var da := DirAccess.open(materials_dir)
	if da == null:
		return out
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir() and entry.begins_with(INCOMING_PREFIX) and entry.ends_with(INCOMING_SUFFIX):
			out.append(materials_dir.path_join(entry))
		entry = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


static func _pack_name_from_path(glb_path: String) -> String:
	var file_name := glb_path.get_file()
	var stem := file_name.substr(
		INCOMING_PREFIX.length(),
		file_name.length() - INCOMING_PREFIX.length() - INCOMING_SUFFIX.length())
	return _sanitize(stem)


static func _ingest_one(glb_path: String, pack_name: String, report: LMSyncReport) -> PackedStringArray:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	var err := doc.append_from_file(ProjectSettings.globalize_path(glb_path), state)
	if err != OK:
		push_error("[LM] Failed reading incoming materials GLB (error %d): %s" % [err, glb_path])
		if report: report.add_config_error("Failed reading incoming materials GLB (error %d)" % err)
		return PackedStringArray()

	var mats: Array = state.get_materials()
	if mats.is_empty():
		print("[LM] %s carried no materials; nothing to adopt." % glb_path.get_file())
		_delete_incoming(glb_path)
		return PackedStringArray()

	var pack_dir := IMPORTED_DIR.path_join(pack_name)
	_ensure_material_dir(pack_dir)
	var tex_dir := pack_dir.path_join(TEX_SUBDIR)
	DirAccess.make_dir_recursive_absolute(tex_dir)

	var used_names: Dictionary = {}
	var jobs: Array = []
	var groups: Array = []
	var group_index: Dictionary = {}
	for m in mats:
		if m is not BaseMaterial3D:
			continue
		var mat: BaseMaterial3D = m
		var name := _unique_name(_sanitize(mat.resource_name), used_names)
		for slot in _TEX_SLOTS:
			var tex: Variant = mat.get(slot["prop"])
			if tex == null or tex is not Texture2D:
				continue
			var key := "%d:%d" % [(tex as Texture2D).get_instance_id(), slot["role"]]
			var gi: int = group_index.get(key, -1)
			if gi == -1:
				var img: Image = (tex as Texture2D).get_image()
				if img == null:
					continue
				if img.is_compressed():
					img.decompress()
				gi = groups.size()
				groups.append({
					"img": img, "owner": name, "role": slot["role"],
					"suffixes": [], "targets": [],
				})
				group_index[key] = gi
			groups[gi]["suffixes"].append(slot["suffix"])
			groups[gi]["targets"].append({"mat": mat, "prop": slot["prop"]})
		mat.resource_name = name
		jobs.append({"mat": mat, "name": name, "tres_path": pack_dir.path_join(name + ".tres")})

	var pending: Array = []
	for g in groups:
		var png := tex_dir.path_join("%s_%s.png" % [g["owner"], _group_suffix(g["suffixes"])])
		if (g["img"] as Image).save_png(ProjectSettings.globalize_path(png)) != OK:
			push_error("[LM] Failed writing texture: %s" % png)
			continue
		pending.append({"path": png, "role": g["role"], "targets": g["targets"]})

	await _import_textures(pending)
	for e in pending:
		var t := _load_imported_texture(e["path"])
		if t == null:
			push_error("[LM] Could not load imported texture '%s' - the material(s) "
				% e["path"] + "using it cannot be adopted (see below).")
			continue
		for target in e["targets"]:
			(target["mat"] as BaseMaterial3D).set(target["prop"], t)

	var fs: EditorFileSystem = null
	if Engine.is_editor_hint():
		fs = EditorInterface.get_resource_filesystem()
	var names: PackedStringArray = []
	for job in jobs:
		var display_name := "%s/%s" % [pack_name, job["name"]]
		var embedded := _embedded_texture_slots(job["mat"])
		if not embedded.is_empty():
			var reason := "textures not rebound to disk: %s" % ", ".join(embedded)
			push_error("[LM] Not saving material '%s' - %s. The PNGs in %s/%s "
				% [display_name, reason, IMPORTED_DIR.path_join(pack_name), TEX_SUBDIR]
				+ "may have failed to write or import; see the errors above.")
			if report: report.add_material(display_name, false, reason)
			continue
		var save_err := ResourceSaver.save(job["mat"], job["tres_path"])
		if save_err != OK:
			push_error("[LM] Failed saving material '%s' (error %d)" % [display_name, save_err])
			if report: report.add_material(display_name, false, "ResourceSaver error %d" % save_err)
			continue
		if fs: fs.update_file(job["tres_path"])
		names.append(display_name)
		if report: report.add_material(display_name, true)

	if names.size() == jobs.size():
		_delete_incoming(glb_path)
	else:
		push_error("[LM] Keeping %s - %d of %d material(s) failed to adopt; the next sync will retry."
			% [glb_path.get_file(), jobs.size() - names.size(), jobs.size()])
	print("[LM] Adopted %d material(s) from %s into %s" % [names.size(), glb_path.get_file(), pack_dir])
	return names


static func _load_imported_texture(png_path: String) -> Texture2D:
	var tex := ResourceLoader.load(png_path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	if tex != null:
		return tex
	var cf := ConfigFile.new()
	if cf.load(png_path + ".import") != OK:
		return null
	var remap: String = cf.get_value("remap", "path", "")
	if remap.is_empty():
		return null
	tex = ResourceLoader.load(remap, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	if tex != null:
		tex.take_over_path(png_path)
	return tex


static func _embedded_texture_slots(mat: BaseMaterial3D) -> PackedStringArray:
	var out: PackedStringArray = []
	for slot in _TEX_SLOTS:
		var tex: Variant = mat.get(slot["prop"])
		if tex == null or tex is not Texture2D:
			continue
		var path: String = (tex as Texture2D).resource_path
		if path.is_empty() or path.contains("::"):
			out.append(slot["prop"])
	return out


static func _import_textures(pending: Array) -> void:
	if pending.is_empty() or not Engine.is_editor_hint():
		return
	for e in pending:
		_write_import_params(e["path"], e["role"])
	var fs := EditorInterface.get_resource_filesystem()
	for _attempt in IMPORT_SCAN_ATTEMPTS:
		await _await_editor_idle()
		if _all_imported(pending):
			return
		fs.scan_sources()
	await _await_editor_idle()
	if not _all_imported(pending):
		push_error("[LM] The editor did not import the adopted textures after %d scan(s); "
			% IMPORT_SCAN_ATTEMPTS + "the affected material(s) are reported below.")


static func _await_editor_idle() -> void:
	if not Engine.is_editor_hint():
		return
	var fs := EditorInterface.get_resource_filesystem()
	var tree := Engine.get_main_loop() as SceneTree
	while fs.is_scanning() or LMPlugin.editor_importing:
		await tree.process_frame


static func _all_imported(pending: Array) -> bool:
	for e in pending:
		if not FileAccess.file_exists(e["path"] + ".import"):
			return false
	return true


static func _write_import_params(png_path: String, role: int) -> void:
	if role != TexRole.NORMAL:
		return
	var import_path := png_path + ".import"
	var cf := ConfigFile.new()
	cf.load(import_path)
	cf.set_value("params", "compress/normal_map", 1)
	if cf.save(import_path) != OK:
		push_error("[LM] Could not write import settings: %s" % import_path)


static func _ensure_material_dir(pack_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(pack_dir):
		DirAccess.make_dir_recursive_absolute(pack_dir)
	var dirs: Array = ProjectSettings.get_setting(LMPlugin.CFG_KEY_MATERIAL_DIRS, [])
	if not dirs.has(IMPORTED_DIR):
		dirs.append(IMPORTED_DIR)
		ProjectSettings.set_setting(LMPlugin.CFG_KEY_MATERIAL_DIRS, dirs)
		ProjectSettings.save()
		print("[LM] Registered material directory: %s" % IMPORTED_DIR)


static func _delete_incoming(glb_path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(glb_path))


static func _sanitize(n: String) -> String:
	if _san_re == null:
		_san_re = RegEx.new()
		_san_re.compile("[^A-Za-z0-9_-]")
	return _san_re.sub(n, "_", true).strip_edges()


static func _group_suffix(suffixes: Array) -> String:
	if suffixes.size() == 1:
		return suffixes[0]
	for s in suffixes:
		if not _ORM_SUFFIXES.has(s):
			return "_".join(PackedStringArray(suffixes))
	return "orm"


static func _unique_name(base: String, used: Dictionary) -> String:
	var name := base if not base.is_empty() else "material"
	var candidate := name
	var i := 1
	while used.has(candidate):
		candidate = "%s_%d" % [name, i]
		i += 1
	used[candidate] = true
	return candidate

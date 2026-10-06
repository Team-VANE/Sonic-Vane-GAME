@tool
class_name LMMapImporter extends EditorImportPlugin

const CACHE_ROOT := "res://.godot/lm_cache"
const HASHES_FILE := "hashes.res"

func _get_importer_name():
	return "liminal_editor.lm.importer"

func _get_visible_name():
	return "Liminal Editor Map Asset"

func _get_recognized_extensions():
	return ["lm"]

func _get_save_extension():
	return "tres"

func _get_resource_type():
	return "LMMapAsset"

func _get_preset_count():
	return 1

func _get_preset_name(preset_index):
	return "Default"

func _get_import_options(path, preset_index):
	return [{
		"name": "lightmap/texel_size",
		"default_value": LMMap.DEFAULT_LIGHTMAP_TEXEL_SIZE,
		"property_hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.001,100,0.001",
	}]

func _import(source_file, save_path, options, platform_variants, gen_files):
	LMTimings.begin("lm_import_" + source_file.get_file().get_basename())
	var asset := LMMapAsset.new()

	var cache_dir: String = cache_dir_for(source_file)
	var derr: Error = DirAccess.make_dir_recursive_absolute(cache_dir)
	if derr != OK:
		push_error("[LM] Could not create cache dir '%s' (err %d)" % [cache_dir, derr])
		LMTimings.finish()
		return derr

	LMTimings.start("hashes_load")
	var hashes_path: String = cache_dir.path_join(HASHES_FILE)
	var old_hashes: Dictionary = {}
	if ResourceLoader.exists(hashes_path):
		var prev = ResourceLoader.load(hashes_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if prev is LMGeoHashes:
			old_hashes = prev.hashes
	LMTimings.stop("hashes_load")

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var ext := LMGltfExtension.new()
	doc.register_gltf_document_extension(ext)
	LMTimings.start("gltf_parse")
	var err: Error = doc.append_from_file(source_file, state)
	LMTimings.stop("gltf_parse")
	if err != OK:
		doc.unregister_gltf_document_extension(ext)
		push_error("[LM] GLTF parse failed for '%s' (err %d)" % [source_file, err])
		LMTimings.finish()
		return err
	LMTimings.start("generate_scene")
	var scene: Node = doc.generate_scene(state)
	LMTimings.stop("generate_scene")
	doc.unregister_gltf_document_extension(ext)
	if scene == null:
		push_error("[LM] generate_scene returned null for '%s'" % source_file)
		LMTimings.finish()
		return ERR_CANT_CREATE

	var new_hashes: Dictionary = {}
	var texel_size: float = options.get("lightmap/texel_size", LMMap.DEFAULT_LIGHTMAP_TEXEL_SIZE)
	LMTimings.start("material_dict_build")
	var material_dict: Dictionary = LMMap.build_material_dict()
	LMTimings.stop("material_dict_build")
	_extract(scene, asset, cache_dir, material_dict, old_hashes, new_hashes, texel_size)
	scene.queue_free()

	LMTimings.start("prune_orphans")
	_prune_orphans(cache_dir, asset)
	LMTimings.stop("prune_orphans")

	LMTimings.start("asset_save")
	var hres := LMGeoHashes.new()
	hres.hashes = new_hashes
	if ResourceSaver.save(hres, hashes_path, ResourceSaver.FLAG_COMPRESS) == OK:
		gen_files.append(hashes_path)

	var save_err: Error = ResourceSaver.save(asset, "%s.%s" % [save_path, _get_save_extension()])
	LMTimings.stop("asset_save")
	LMTimings.finish()
	return save_err

func _extract(scene: Node, asset: LMMapAsset, cache_dir: String, material_dict: Dictionary, old_hashes: Dictionary, new_hashes: Dictionary, texel_size: float) -> void:
	LMTimings.start("hash_meshes")
	var records: Array[Dictionary] = []
	var queue: Array[Node] = [scene]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		queue.append_array(n.get_children())
		if n is ImporterMeshInstance3D and n.has_meta(&"LM_geo"):
			var gx: Transform3D = _global_xform(n)
			var mesh: ArrayMesh = n.mesh.get_mesh()
			var key: String = String(n.name)
			var geo = n.get_meta(&"LM_geo")
			var ctype: String = geo.get("collision", "") if geo is Dictionary else ""
			var h: int = _content_hash(mesh, gx.basis, ctype, texel_size)
			new_hashes[key] = h
			records.append({key = key, mesh = mesh, gx = gx, ctype = ctype, hash = h})
	LMTimings.stop("hash_meshes")

	var cached_by_mesh: Dictionary = {}
	var shape_cache_hits := 0
	var shape_rebuilds := 0
	var mesh_dedup_hits := 0
	var mesh_cache_hits := 0
	var mesh_rebuilds := 0
	for r in records:
		var key: String = r.key
		var mesh: ArrayMesh = r.mesh
		var gx: Transform3D = r.gx
		var ctype: String = r.ctype
		var h: int = r.hash
		var mpath: String = cache_dir.path_join(_mesh_file(key))
		var spath: String = cache_dir.path_join(_shape_file(key))

		if ctype in ["CONCAVE", "CONVEX"]:
			if old_hashes.get(key) == h and FileAccess.file_exists(spath):
				LMTimings.start("shape_cache_load")
				asset.shapes[key] = ResourceLoader.load(spath)
				LMTimings.stop("shape_cache_load")
				shape_cache_hits += 1
			else:
				LMTimings.start("shape_build")
				var shape: Shape3D = LMMap.make_collision_shape(mesh, gx.basis.get_scale(), ctype)
				if shape and _save_cached(shape, spath, key):
					asset.shapes[key] = shape
				LMTimings.stop("shape_build")
				shape_rebuilds += 1

		var mid: int = mesh.get_instance_id()
		if cached_by_mesh.has(mid):
			asset.meshes[key] = cached_by_mesh[mid]
			mesh_dedup_hits += 1
		elif old_hashes.get(key) == h and FileAccess.file_exists(mpath):
			LMTimings.start("mesh_cache_load")
			var res: Resource = ResourceLoader.load(mpath)
			LMTimings.stop("mesh_cache_load")
			asset.meshes[key] = res
			cached_by_mesh[mid] = res
			mesh_cache_hits += 1
		else:
			LMTimings.start("mesh_lightmap_unwrap")
			LMMap._finalize_mesh(mesh, gx, material_dict, texel_size)
			LMTimings.stop("mesh_lightmap_unwrap")
			LMTimings.start("mesh_save")
			if _save_cached(mesh, mpath, key):
				asset.meshes[key] = mesh
				cached_by_mesh[mid] = mesh
			LMTimings.stop("mesh_save")
			mesh_rebuilds += 1

	LMTimings.note("nodes: %d  mesh: %d dedup / %d cache-hit / %d rebuilt  shape: %d cache-hit / %d rebuilt" % [
		records.size(), mesh_dedup_hits, mesh_cache_hits, mesh_rebuilds, shape_cache_hits, shape_rebuilds])

func _save_cached(res: Resource, path: String, key: String) -> bool:
	var err: Error = ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("[LM] Failed to cache '%s' -> %s (err %d)" % [key, path, err])
		return false
	res.take_over_path(path)
	return true

static func _global_xform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = node
	while cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

static func cache_dir_for(source_file: String) -> String:
	return "%s/%s_%d" % [CACHE_ROOT, source_file.get_file().get_basename(), abs(source_file.hash())]

static func _mesh_file(key: String) -> String:
	return key.validate_filename() + ".mesh.res"

static func _shape_file(key: String) -> String:
	return key.validate_filename() + ".shape.res"

static func _content_hash(mesh: ArrayMesh, basis: Basis, collision_type: String, texel_size: float) -> int:
	var acc: int = hash(basis)
	acc = _mix(acc, collision_type.hash())
	acc = _mix(acc, hash(texel_size))
	acc = _mix(acc, hash(LMMap.MAX_LIGHTMAP_TEXELS))
	for i in mesh.get_surface_count():
		acc = _mix(acc, hash(mesh.surface_get_arrays(i)))
		var sm: Material = mesh.surface_get_material(i)
		acc = _mix(acc, (sm.resource_name if sm else "").hash())
	return acc

static func _mix(a: int, b: int) -> int:
	return (a * 31 + b) & 0x7FFFFFFFFFFFFFFF

func _prune_orphans(cache_dir: String, asset: LMMapAsset) -> void:
	var valid: Dictionary = {HASHES_FILE: true}
	for res in asset.meshes.values():
		if res and not res.resource_path.is_empty():
			valid[res.resource_path.get_file()] = true
	for res in asset.shapes.values():
		if res and not res.resource_path.is_empty():
			valid[res.resource_path.get_file()] = true
	var d := DirAccess.open(cache_dir)
	if d == null:
		return
	for f in d.get_files():
		if not valid.has(f):
			DirAccess.remove_absolute(cache_dir.path_join(f))

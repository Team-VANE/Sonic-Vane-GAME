class_name LMMaterialUtils

const _ParallelPNG := preload("gltf_parallel_png.gd")

static func find_all_material_resources() -> Dictionary:
	var material_dirs: Array = ProjectSettings.get_setting(LMPlugin.CFG_KEY_MATERIAL_DIRS)
	var all_materials: Dictionary = {}
	for material_dir in material_dirs:
		all_materials.set(material_dir, LMIOUtils.find_files_recursively(material_dir))
	return all_materials

const PREVIEW_SIZE := 512
const PREVIEW_GRID := 4

class PreviewRig:
	var _vp: SubViewport
	var _quads: Array[MeshInstance3D] = []
	var _grid: int
	var _tile: int

	func setup(tile_size: int, grid: int) -> void:
		_grid = grid
		_tile = tile_size
		_vp = SubViewport.new()
		_vp.size = Vector2i(tile_size * grid, tile_size * grid)
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_vp.transparent_bg = true
		_vp.own_world_3d = true

		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = float(grid)
		cam.position = Vector3(0, 0, 1)

		var env := Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 1.0
		cam.environment = env
		_vp.add_child(cam)

		for i in grid * grid:
			var quad := MeshInstance3D.new()
			quad.mesh = QuadMesh.new()
			@warning_ignore("integer_division")
			var row := i / grid
			var col := i % grid
			quad.position = Vector3(col + 0.5 - grid * 0.5, grid * 0.5 - (row + 0.5), 0)
			quad.visible = false
			_vp.add_child(quad)
			_quads.append(quad)

		(Engine.get_main_loop().get_root() as Window).add_child(_vp)

	func render_batch(mats: Array) -> Array[ImageTexture]:
		for i in _quads.size():
			var active := i < mats.size()
			_quads[i].visible = active
			if active:
				_quads[i].set_surface_override_material(0, mats[i])
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var sheet := _vp.get_texture().get_image()
		var out: Array[ImageTexture] = []
		for i in mats.size():
			@warning_ignore("integer_division")
			var row := i / _grid
			var col := i % _grid
			var tile := sheet.get_region(Rect2i(col * _tile, row * _tile, _tile, _tile))
			out.append(ImageTexture.create_from_image(tile))
		return out

	func teardown() -> void:
		_vp.get_parent().remove_child(_vp)
		_vp.queue_free()

static func export_materials_glb(material_paths: Dictionary, output_path: String, report: LMSyncReport = null):
	var names: Array[String] = []
	var mats: Array[Material] = []
	for base_dir in material_paths:
		for res_partial_path in material_paths[base_dir]:
			var resource_path: String = base_dir.path_join(res_partial_path)
			if resource_path.get_extension() != "tres":
				continue

			LMTimings.start("material_load")
			var mat := ResourceLoader.load(resource_path) as Material
			LMTimings.stop("material_load")

			if mat == null:
				push_warning("LMMaterialUtils: could not load material at '%s', skipping" % resource_path)
				if report: report.add_material(resource_path, false, "could not load resource")
				continue

			if mat is BaseMaterial3D:
				mat = mat.duplicate()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

			names.append(res_partial_path.get_basename().replace("/", "_"))
			mats.append(mat)

	var baked: Array[ImageTexture] = []
	var rig := PreviewRig.new()
	rig.setup(PREVIEW_SIZE, PREVIEW_GRID)
	var batch_size := PREVIEW_GRID * PREVIEW_GRID
	for batch_start in range(0, mats.size(), batch_size):
		LMTimings.start("preview_render")
		baked.append_array(await rig.render_batch(mats.slice(batch_start, batch_start + batch_size)))
		LMTimings.stop("preview_render")
	rig.teardown()

	var scene_root := Node3D.new()
	scene_root.name = "MaterialLibrary"
	var box_mesh: BoxMesh = BoxMesh.new()
	var pos: Vector3
	for i in names.size():
		var mat_name := names[i]
		baked[i].resource_name = mat_name
		var proxy := StandardMaterial3D.new()
		proxy.albedo_texture = baked[i]
		proxy.resource_name = mat_name
		var mi := MeshInstance3D.new()
		mi.mesh = box_mesh
		mi.position = pos
		scene_root.add_child(mi)
		mi.set_surface_override_material(0, proxy)
		mi.owner = scene_root
		mi.name = "preview_" + mat_name
		if report: report.add_material(mat_name, true)
		pos.x += 1
		if pos.x >= 5:
			pos.y += 1
			pos.x = 0

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.copyright = "LiminalEditor"

	var png_encoder := _ParallelPNG.new()
	GLTFDocument.register_gltf_document_extension(png_encoder)
	doc.image_format = _ParallelPNG.IMAGE_FORMAT

	LMTimings.start("gltf_append")
	var err := doc.append_from_scene(scene_root, state)
	LMTimings.stop("gltf_append")
	if err != OK:
		push_error("LMMaterialUtils: failed to append scene - error %d" % err)
		if report: report.add_config_error("Failed to build materials GLB (error %d)" % err)
		GLTFDocument.unregister_gltf_document_extension(png_encoder)
		scene_root.free()
		return err

	LMTimings.start("gltf_write")
	err = doc.write_to_filesystem(state, output_path)
	LMTimings.stop("gltf_write")
	GLTFDocument.unregister_gltf_document_extension(png_encoder)
	LMTimings.add("png_encode_parallel", _ParallelPNG.last_encode_ms)
	if err != OK:
		push_error("LMMaterialUtils: failed to write GLB to '%s' - error %d" % [output_path, err])
		if report: report.add_config_error("Failed to write materials GLB to '%s' (error %d)" % [output_path, err])

	scene_root.free()
	return err

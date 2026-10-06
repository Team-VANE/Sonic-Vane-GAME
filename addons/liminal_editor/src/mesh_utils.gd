class_name LMMeshUtils extends RefCounted

static func bake_gltf_mesh_from_scene(root_node: Node, output_path: String) -> bool:

	var gltf_document: GLTFDocument = GLTFDocument.new()
	var gltf_state: GLTFState = GLTFState.new()
	var merged: MeshInstance3D = merge_mesh_instances(root_node)
	if merged:
		gltf_document.append_from_scene(merged, gltf_state)
		gltf_document.visibility_mode = GLTFDocument.VISIBILITY_MODE_EXCLUDE
		var out_dir: String = output_path.get_base_dir()

		DirAccess.make_dir_recursive_absolute(out_dir)
		var err: Error = gltf_document.write_to_filesystem(gltf_state, output_path)
		merged.free()
		if err:
			printerr("Export error: %s" % err)
		return err == Error.OK
	return false

static func merge_mesh_instances(root: Node) -> MeshInstance3D:
	var arrays: Array = []
	_collect_surfaces(root, Transform3D.IDENTITY, arrays)

	if arrays.is_empty():
		return null

	var merged_mesh := ArrayMesh.new()
	var i: int = 0
	for surface_data in arrays:
		merged_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_data["surface"])
		merged_mesh.surface_set_material(i, surface_data["material"])
		i += 1

	var result := MeshInstance3D.new()
	result.mesh = merged_mesh
	return result


static func _collect_surfaces(node: Node, root_inverse_transform: Transform3D, arrays: Array) -> void:
	var local_transform: Transform3D = root_inverse_transform
	if node is Node3D:
		local_transform  = local_transform * node.transform
	if node is MeshInstance3D && node.mesh:
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var surface := mesh_instance.mesh.surface_get_arrays(i)

			var verts: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
			for j in verts.size():
				verts[j] = local_transform * verts[j]
			surface[Mesh.ARRAY_VERTEX] = verts

			if surface[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = surface[Mesh.ARRAY_NORMAL]
				var normal_transform := local_transform.basis.inverse()
				for j in normals.size():
					normals[j] = (normal_transform * normals[j]).normalized()
				surface[Mesh.ARRAY_NORMAL] = normals

			arrays.append({"surface": surface, "material": mesh_instance.get_active_material(i) })

	for child in node.get_children():
		_collect_surfaces(child, local_transform, arrays)

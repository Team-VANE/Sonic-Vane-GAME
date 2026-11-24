extends RefCounted


static func build(curve: Curve3D, segment: Mesh, width_scale: float = 1.0, height_scale: float = 1.0) -> ArrayMesh:
	var length: float = curve.get_baked_length()
	var segment_length: float = segment.get_aabb().size.x
	if length <= 0.001 or segment_length <= 0.001:
		return null
	var count: int = maxi(1, roundi(length / segment_length))
	var spacing: float = length / count
	var cross_section: Vector3 = Vector3(1.0, maxf(height_scale, 0.05), maxf(width_scale, 0.05))
	var mesh: ArrayMesh = ArrayMesh.new()
	for surface: int in segment.get_surface_count():
		var source: Array = segment.surface_get_arrays(surface)
		var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL] if source[Mesh.ARRAY_NORMAL] else PackedVector3Array()
		var tangents: PackedFloat32Array = source[Mesh.ARRAY_TANGENT] if source[Mesh.ARRAY_TANGENT] else PackedFloat32Array()
		var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX] else PackedInt32Array()
		var result: Array = source.duplicate()
		for channel: int in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			if source[channel]:
				var tiled: Variant = source[channel].duplicate()
				for section: int in range(1, count):
					tiled.append_array(source[channel])
				result[channel] = tiled
		var positions: PackedVector3Array = PackedVector3Array()
		var rotated_normals: PackedVector3Array = PackedVector3Array()
		var rotated_tangents: PackedFloat32Array = PackedFloat32Array()
		var remapped_indices: PackedInt32Array = PackedInt32Array()
		positions.resize(vertices.size() * count)
		rotated_normals.resize(normals.size() * count)
		rotated_tangents.resize(tangents.size() * count)
		remapped_indices.resize(indices.size() * count)
		for section: int in count:
			var vertex_start: int = section * vertices.size()
			for index: int in vertices.size():
				var point: Vector3 = vertices[index]
				var distance: float = (section + point.x / segment_length) * spacing
				var frame: Transform3D = curve.sample_baked_with_rotation(distance, false, true)
				var forward: Vector3 = -frame.basis.z
				var up: Vector3 = frame.basis.y
				var orientation: Basis = Basis(forward, up, forward.cross(up))
				var target: int = vertex_start + index
				positions[target] = frame.origin + orientation * (Vector3(0, point.y, point.z) * cross_section)
				if normals:
					rotated_normals[target] = orientation * (normals[index] / cross_section).normalized()
				if tangents:
					var channel: int = index * 4
					var tangent: Vector3 = Vector3(tangents[channel], tangents[channel + 1], tangents[channel + 2])
					tangent = orientation * (tangent * cross_section).normalized()
					var start: int = target * 4
					rotated_tangents[start] = tangent.x
					rotated_tangents[start + 1] = tangent.y
					rotated_tangents[start + 2] = tangent.z
					rotated_tangents[start + 3] = tangents[channel + 3]
			for index: int in indices.size():
				remapped_indices[section * indices.size() + index] = vertex_start + indices[index]
		result[Mesh.ARRAY_VERTEX] = positions
		if normals:
			result[Mesh.ARRAY_NORMAL] = rotated_normals
		if tangents:
			result[Mesh.ARRAY_TANGENT] = rotated_tangents
		if indices:
			result[Mesh.ARRAY_INDEX] = remapped_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result)
		mesh.surface_set_material(surface, segment.surface_get_material(surface))
	return mesh

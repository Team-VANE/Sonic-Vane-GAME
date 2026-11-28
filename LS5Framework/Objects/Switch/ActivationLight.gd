extends RefCounted


static func find_surface(mesh: MeshInstance3D) -> int:
	if not mesh or not mesh.mesh:
		return -1
	for index: int in mesh.mesh.get_surface_count():
		var material: Material = mesh.get_active_material(index)
		if material is StandardMaterial3D and material.resource_name == "Light_OFF":
			return index
	return -1


static func make_on_material(off_material: StandardMaterial3D, texture: Texture2D, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = off_material.duplicate() as StandardMaterial3D
	material.albedo_texture = texture
	material.emission_enabled = true
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission = Color.WHITE
	material.emission_texture = texture
	material.emission_energy_multiplier = energy
	return material

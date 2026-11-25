@tool
extends EditorScenePostImport

const MATERIAL_PREFIX: String = "ANVIL_EXPORT_Material_"
const MATERIALS: Array[Material] = [
	preload("Materials/ANVIL_EXPORT_Material_1.tres"),
	preload("Materials/ANVIL_EXPORT_Material_2.tres"),
	preload("Materials/ANVIL_EXPORT_Material_3.tres"),
	preload("Materials/ANVIL_EXPORT_Material_4.tres"),
	preload("Materials/ANVIL_EXPORT_Material_5.tres"),
	preload("Materials/ANVIL_EXPORT_Material_6.tres"),
	preload("Materials/ANVIL_EXPORT_Material_7.tres"),
	preload("Materials/ANVIL_EXPORT_Material_8.tres"),
	preload("Materials/ANVIL_EXPORT_Material_9.tres"),
	preload("Materials/ANVIL_EXPORT_Material_10.tres"),
	preload("Materials/ANVIL_EXPORT_Material_11.tres"),
]


func _post_import(scene: Node) -> Object:
	for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if not node.mesh:
			continue
		for surface: int in range(node.mesh.get_surface_count()):
			var source: Material = node.mesh.surface_get_material(surface)
			if not source or not source.resource_name.begins_with(MATERIAL_PREFIX):
				continue
			var slot: String = source.resource_name.trim_prefix(MATERIAL_PREFIX).get_slice(".", 0)
			var index: int = slot.to_int() - 1
			if slot.is_valid_int() and index >= 0 and index < MATERIALS.size():
				node.mesh.surface_set_material(surface, MATERIALS[index])
	return scene

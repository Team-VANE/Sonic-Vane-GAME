@tool
class_name LMGltfExtension extends GLTFDocumentExtension

func _parse_node_extensions(state: GLTFState, gltf_node: GLTFNode, extensions: Dictionary) -> Error:
	if extensions.has("LM_entity"):
		gltf_node.set_additional_data("LM_entity", extensions["LM_entity"])
	elif extensions.has("LM_geo"):
		gltf_node.set_additional_data("LM_geo", extensions["LM_geo"])
	return OK

func _generate_scene_node(state: GLTFState, gltf_node: GLTFNode, scene_parent: Node) -> Node3D:
	var entity_data: Variant = gltf_node.get_additional_data(&"LM_entity")
	if entity_data != null && entity_data is not Dictionary:
		push_warning("Invalid type of additional data")
		return null

	var ret: Node3D = null

	if gltf_node.get_additional_data(&"LM_entity"):
		ret = LMProxyEntity.new()
		ret.position = gltf_node.position
		ret.quaternion = gltf_node.rotation
		ret.scale = gltf_node.scale
		ret.entity_data = entity_data
		if gltf_node.mesh >= 0:
			var meshes: Array[GLTFMesh] = state.get_meshes()
			ret.mesh_data = meshes[gltf_node.mesh].mesh.get_mesh()
	return ret

func _import_node(state: GLTFState, gltf_node: GLTFNode, json: Dictionary, node: Node) -> Error:
	if node is ImporterMeshInstance3D && gltf_node.get_additional_data(&"LM_geo"):
		node.set_meta(&"LM_geo", gltf_node.get_additional_data(&"LM_geo"))
	return OK

@tool
class_name LMMapHooks extends Resource


func on_setup_begin(map: LMMap) -> void:
	pass


func on_geo_mesh(map: LMMap, mesh_instance: MeshInstance3D, tags: PackedStringArray) -> MeshInstance3D:
	return mesh_instance


func on_geo_collision(map: LMMap, mesh_instance: MeshInstance3D, collision_shape: CollisionShape3D, tags: PackedStringArray) -> CollisionShape3D:
	return collision_shape


func on_geo_body(map: LMMap, mesh_instance: MeshInstance3D, collision_shape: CollisionShape3D, default_body: CollisionObject3D, tags: PackedStringArray) -> CollisionObject3D:
	return default_body


func on_entity_ready(map: LMMap, entity: Node, classname: String) -> void:
	pass


func on_setup_complete(map: LMMap) -> void:
	pass

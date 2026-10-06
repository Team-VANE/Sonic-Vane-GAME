class_name LMProxyEntity extends LMProxy

@export var entity_data: Dictionary

var uid: String:
	get: return entity_data["uid"]

@export var mesh_data: ArrayMesh

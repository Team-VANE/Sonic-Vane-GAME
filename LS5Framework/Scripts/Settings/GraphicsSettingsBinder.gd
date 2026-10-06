extends Node

@export var world_environment_path: NodePath
@export var directional_light_path: NodePath
@export var camera_path: NodePath


func _ready() -> void:
	var world_env: WorldEnvironment = _get_world_environment()
	var dir_light: DirectionalLight3D = _get_directional_light()
	var camera_node: Camera3D = _get_camera()

	if world_env or dir_light:
		SettingsManager.register_graphics_targets(world_env, dir_light)
	if camera_node != null:
		SettingsManager.register_camera_targets(camera_node)


func _get_world_environment() -> WorldEnvironment:
	if world_environment_path == NodePath(""):
		return null
	var node := get_node_or_null(world_environment_path)
	return node if node is WorldEnvironment else null


func _get_directional_light() -> DirectionalLight3D:
	if directional_light_path == NodePath(""):
		return null
	var node := get_node_or_null(directional_light_path)
	return node if node is DirectionalLight3D else null


func _get_camera() -> Camera3D:
	if camera_path == NodePath(""):
		return null
	var node := get_node_or_null(camera_path)
	return node if node is Camera3D else null

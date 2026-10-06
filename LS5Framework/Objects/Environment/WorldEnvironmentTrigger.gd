extends WorldObject

@export var target_world_environment_path: NodePath
@export var directional_light_path: NodePath

@export var apply_environment: bool = true
@export var apply_camera_attributes: bool = true
@export var apply_compositor: bool = true

@export var apply_graphics_settings: bool = true


func _apply_to_player(player: Node3D) -> void:
	if player == null:
		return

	# Only affect the local client in multiplayer.
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if player.has_method("is_multiplayer_authority") and not player.is_multiplayer_authority():
			return

	var world_env = _resolve_world_environment()
	if world_env == null:
		push_warning("WorldEnvironmentTrigger: target WorldEnvironment not found.")
		return

	var vp = player.get_viewport()
	if vp == null:
		vp = get_viewport()
	if vp == null:
		return

	var world = null
	if vp.has_method("get_world_3d"):
		world = vp.call("get_world_3d")

	if apply_environment:
		if world != null:
			_set_world_or_viewport_property(world, vp, "environment", world_env.environment)
	if apply_camera_attributes:
		if world != null:
			_set_world_or_viewport_property(world, vp, "camera_attributes", world_env.camera_attributes)
	if apply_compositor:
		if world != null:
			_set_world_or_viewport_property(world, vp, "compositor", world_env.compositor)

	if apply_graphics_settings:
		var settings = get_node_or_null("/root/SettingsManager")
		if settings != null and settings.has_method("register_graphics_targets"):
			var dir_light = _resolve_directional_light()
			settings.call("register_graphics_targets", world_env, dir_light)
		elif settings != null and settings.has_method("apply_graphics_to"):
			var dir_light2 = _resolve_directional_light()
			settings.call("apply_graphics_to", world_env, dir_light2)


func _resolve_world_environment() -> WorldEnvironment:
	if target_world_environment_path == NodePath(""):
		return null
	var n = get_node_or_null(target_world_environment_path)
	if n == null and get_tree() != null and get_tree().current_scene != null:
		n = get_tree().current_scene.get_node_or_null(target_world_environment_path)
	return n if n is WorldEnvironment else null


func _resolve_directional_light() -> DirectionalLight3D:
	if directional_light_path == NodePath(""):
		return null
	var n = get_node_or_null(directional_light_path)
	if n == null and get_tree() != null and get_tree().current_scene != null:
		n = get_tree().current_scene.get_node_or_null(directional_light_path)
	return n if n is DirectionalLight3D else null


func _set_world_or_viewport_property(world: Object, vp: Viewport, property_name: String, value) -> void:
	if world != null and _object_has_property(world, property_name):
		world.set(property_name, value)
		return
	if vp != null and _object_has_property(vp, property_name):
		vp.set(property_name, value)


func _object_has_property(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	var list = obj.get_property_list()
	for item in list:
		if item is Dictionary and item.has("name") and String(item["name"]) == property_name:
			return true
	return false

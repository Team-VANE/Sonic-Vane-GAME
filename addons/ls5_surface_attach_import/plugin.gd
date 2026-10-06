@tool
extends EditorPlugin

var _post_import_plugin: EditorScenePostImportPlugin = null


func _enter_tree() -> void:
	_post_import_plugin = preload("res://addons/ls5_surface_attach_import/surface_attach_post_import.gd").new()
	add_scene_post_import_plugin(_post_import_plugin)


func _exit_tree() -> void:
	if _post_import_plugin:
		remove_scene_post_import_plugin(_post_import_plugin)
	_post_import_plugin = null

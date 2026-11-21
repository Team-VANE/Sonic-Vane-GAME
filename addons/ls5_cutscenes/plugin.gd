@tool
extends EditorPlugin

const WORKSPACE_NAME: String = "Cutscenes"

var _screen: Control


func _enter_tree() -> void:
	main_screen_changed.connect(_on_main_screen_changed)
	scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	main_screen_changed.disconnect(_on_main_screen_changed)
	scene_changed.disconnect(_on_scene_changed)
	if _screen:
		_screen.free()
		_screen = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if visible and not _screen:
		var screen_script: Script = load("res://addons/ls5_cutscenes/editor/cutscene_screen.gd")
		_screen = screen_script.new()
		_screen.name = "CutsceneScreen"
		_screen.hide()
		_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
		EditorInterface.get_editor_main_screen().add_child(_screen)
		_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _screen:
		_screen.visible = visible


func _on_main_screen_changed(screen_name: String) -> void:
	_make_visible(screen_name == WORKSPACE_NAME)


func _on_scene_changed(_root: Node) -> void:
	if _screen and _screen.is_visible_in_tree():
		_screen.refresh_level()


func _get_plugin_name() -> String:
	return WORKSPACE_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("AnimationPlayer", "EditorIcons")

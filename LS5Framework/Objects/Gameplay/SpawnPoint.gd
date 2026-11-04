@tool
extends Node3D
class_name SpawnPoint

const EDITOR_PREVIEW_PATH: String = "res://LS5Framework/Objects/Reference/Sonic_NeoAdventure_REF.glb"
const GAMEPLAY_SCENE_PATH: String = "res://LS5Framework/Scenes/Main.tscn"
const DIRECT_START_GROUP: StringName = &"DirectLevelSpawn"

## Allows this marker to start gameplay when the level scene is run directly.
@export var direct_level_start_enabled: bool = true

@export_group("Editor Preview")
## Shows the reference character in the editor without loading it during gameplay.
@export var show_editor_preview: bool = true:
	set(value):
		show_editor_preview = value
		_update_editor_preview()
## Local preview offset from the player's collision-centred spawn origin.
@export var editor_preview_offset: Vector3 = Vector3(0.0, -1.0, 0.0):
	set(value):
		editor_preview_offset = value
		_update_editor_preview()

@export_group("Downwarp")
@export var downwarp_enabled: bool = true
@export var downwarp_distance: float = 150.0
@export var downwarp_offset: float = 0.05
@export var downwarp_collision_mask: int = 0xFFFFFFFF

## Unsaved reference model used to preview spawn placement and facing in the editor.
var _editor_preview: Node3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
	elif direct_level_start_enabled:
		add_to_group(DIRECT_START_GROUP)
		_start_direct_level.call_deferred()


func _start_direct_level() -> void:
	var tree: SceneTree = get_tree()
	if not tree or tree.has_meta("pending_level_scene"):
		return
	if tree.get_first_node_in_group("LevelManager") or tree.get_first_node_in_group("NetworkSession"):
		return
	var level: Node = tree.current_scene
	if not level or not level.is_ancestor_of(self) or level.scene_file_path.is_empty():
		return

	var spawn: Node = level.get_node_or_null("PlayerSpawn")
	if not spawn or not spawn.is_in_group(DIRECT_START_GROUP):
		for candidate: Node in tree.get_nodes_in_group(DIRECT_START_GROUP):
			if level.is_ancestor_of(candidate):
				spawn = candidate
				break
	if spawn != self:
		return

	tree.set_meta("pending_level_scene", level.scene_file_path)
	tree.set_meta("pending_level_spawn_path", level.get_path_to(self))
	NetworkManager.leave()
	var result: Error = tree.change_scene_to_file(GAMEPLAY_SCENE_PATH)
	if result != OK:
		tree.remove_meta("pending_level_scene")
		tree.remove_meta("pending_level_spawn_path")
		push_error("Could not start direct level gameplay: %s" % error_string(result))


func _update_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if not show_editor_preview:
		if is_instance_valid(_editor_preview):
			remove_child(_editor_preview)
			_editor_preview.queue_free()
			_editor_preview = null
		return
	if not is_instance_valid(_editor_preview):
		var scene: PackedScene = load(EDITOR_PREVIEW_PATH) as PackedScene
		if not scene:
			return
		_editor_preview = scene.instantiate() as Node3D
		if not _editor_preview:
			return
		_editor_preview.name = "SpawnCharacterPreview"
		_editor_preview.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(_editor_preview, false, Node.INTERNAL_MODE_BACK)
		for node: Node in _editor_preview.find_children("*", "GeometryInstance3D", true, false):
			var geometry: GeometryInstance3D = node as GeometryInstance3D
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_editor_preview.position = editor_preview_offset

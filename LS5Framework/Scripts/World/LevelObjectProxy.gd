extends Node3D
class_name LevelObjectProxy

const PROXY_GROUP: StringName = &"LevelObjectProxy"

## Enables replacement of this proxy during level preparation.
@export var spawn_enabled: bool = true
## Scene instantiated in place of this proxy.
@export_file("*.tscn") var target_scene_path: String = ""
## Optional parent within the loaded level for the instantiated scene.
@export_node_path("Node") var spawn_parent_path: NodePath = NodePath("")
## Property values applied to the instantiated scene.
@export var property_overrides: Array[Dictionary] = []
## Copies a Curve3D from the proxy hierarchy to the instantiated scene.
@export var curve_copy_enabled: bool = false
## Path3D within the proxy hierarchy that supplies the curve.
@export_node_path("Path3D") var curve_source_path: NodePath = NodePath("")
## Path3D within the instantiated scene that receives the curve.
@export_node_path("Path3D") var curve_target_path: NodePath = NodePath("")
## Transform marker mappings copied from the proxy to the instantiated scene.
@export var transform_copies: Array[Dictionary] = []


func _init() -> void:
	add_to_group(PROXY_GROUP)

extends Resource
class_name LevelPackManifest

# Level document list used by LevelRegistry.tres.

@export_group("Pack")
## Optional identifier for debugging or tooling.
@export var pack_id: String = ""

@export_group("Levels")
## LevelDoc resource paths (res://LS5Framework/Scenes/Levels/LVL_*.tres).
@export var level_docs: Array[String] = []

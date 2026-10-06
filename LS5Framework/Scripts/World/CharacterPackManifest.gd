extends Resource
class_name CharacterPackManifest

@export_group("Pack")
## Optional identifier for debugging or tooling.
@export var pack_id: String = ""

@export_group("Characters")
## CharacterDoc resource paths.
@export var character_docs: Array[String] = []

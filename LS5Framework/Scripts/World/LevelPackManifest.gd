extends Resource
class_name LevelPackManifest

# =========================================================
# LEVEL PACK MANIFEST
# =========================================================
# Lists LevelDoc resource paths that belong to a single PCK.
# LevelCatalog scans levels_dir/PackManifests for these manifests, so
# each pack can ship its own manifest without editing a master list.
# =========================================================

@export_group("Pack")
## Optional identifier for debugging or tooling.
@export var pack_id: String = ""

@export_group("Levels")
## LevelDoc resource paths (res://LS5Framework/Scenes/Levels/LVL_*.tres).
@export var level_docs: Array[String] = []

extends Resource
class_name LevelDoc

# =========================================================
# LEVEL DOC RESOURCE
# =========================================================
# Stores level metadata in a Resource so it exports with
# Selected Resources presets and can be loaded from packs.
# =========================================================

@export_group("Identity")
## Display name shown in Level Select.
@export var level_name: String = ""

## Optional stable ID for scripts or save data.
@export var level_id: String = ""

## Sort order for Level Select (lower appears first).
@export var order: int = 0

## Marks a dev/test entry for special handling.
@export var is_test: bool = false

## Section label used by level selection menus. Empty values use Main.
@export var selection_category: String = "Main"

@export_group("Scenes")
## Main game scene for the level (usually Main.tscn).
@export var scene: String = ""

## Level content scene (the actual playable level).
@export var level_scene: String = ""

@export_group("Attributes")
## Optional key/value metadata parsed by gameplay systems.
@export var attributes: Dictionary = {}

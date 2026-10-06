# Level Docs (Resource Format)

Level Select is populated by `LevelCatalog` from level doc files stored under:
`res://LS5Framework/Scenes/Levels/`

`LevelCatalog` reads `LVL_*.tres` files directly from this directory, including mounted PCKs. Exported `.tres.remap` entries are resolved to their original resource paths. `LevelRegistry.tres` supplies the built-in list, and `LVLTEST.tres` is included separately.

This project uses `LevelDoc` resources (`LVL_*.tres`) so level metadata is
exported with Selected Resources presets.

## Files

- Script: `Scripts/World/LevelDoc.gd`
- Example docs:
  - `Scenes/Levels/LVL_GreenHillOcean.tres`
  - `Scenes/Levels/LVL_EmeraldCoast.tres`

## LevelDoc Fields

Each `LVL_*.tres` sets these properties:

- `level_name`: Display name shown in Level Select.
- `level_id`: Optional ID for scripts or save data.
- `order`: Sort order (lower appears first).
- `is_test`: Marks a test entry.
- `scene`: Main scene (usually `res://LS5Framework/Scenes/Main.tscn`).
- `level_scene`: Playable level scene path.
- `attributes`: Optional key/value metadata.

## XML Files

`LevelCatalog` only loads `LVL_*.tres` resources. XML level docs are not used.

## Export Notes

When exporting level packs, ensure the matching `LVL_*.tres` is included in the
selected resources list so Level Select can find it at runtime.

No per-pack level manifest is required. New packs and mods can add `LVL_*.tres` files directly under the level document directory without editing a master list.

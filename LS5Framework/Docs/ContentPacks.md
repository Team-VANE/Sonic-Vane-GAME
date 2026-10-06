# Content Pack Layout

This project loads optional PCK files from a `Data/` folder next to the executable.
Without dependency metadata, packs are mounted deterministically in this order:

1. Base packs (`shared`, `audio`, `characters`, `objects`)
2. Level packs from `Data/Levels/`, sorted by path
3. Mod packs from `Data/Mods/`, sorted by path

Declared dependencies always mount before the pack that requires them. Mods otherwise remain last so their resource overrides continue to work.

The loader also looks for a `Data/` folder next to the project root while running in the editor.

## Suggested Pack Names
- Data/shared.pck        (materials, shaders, common textures)
- Data/audio.pck         (music + SFX)
- Data/characters.pck    (player and character scenes/assets)
- Data/objects.pck       (gameplay objects + assets)
- Data/Levels/*.pck      (one pack per level)
- Data/Mods/*.pck        (user mods, loaded last)

## Scene-to-Pack Mapping (Optional)

To load level packs on-demand instead of loading all of them at startup,
add entries to `scene_pack_map` in `ContentPackManager.gd`, for example:

```gdscript
  {"scene": "res://LS5Framework/Scenes/Levels/Green Hill Ocean/green_hill_ocean.tscn", "pack": "Levels/green_hill_ocean.pck"}
```

On-demand loading resolves and mounts the mapped pack's dependencies first.

## PCK Dependency Manifests

A dependency manifest is a JSON sidecar beside the PCK. It must remain outside the PCK so the loader can inspect dependencies before mounting resources.

Preferred naming:

```text
Data/Mods/example_assets.pck
Data/Mods/example_assets.pck.manifest.json
```

`example_assets.manifest.json` is also accepted. Pack IDs are case-insensitive and should use a stable reverse-domain identifier.

```json
{
  "id": "org.example.environment-assets",
  "version": "1.2.0",
  "dependencies": [
    { "id": "org.example.material-library", "version": ">=1.0.0 <2.0.0" }
  ],
  "optional_dependencies": [
    "org.example.hd-textures"
  ],
  "load_after": [
    "objects"
  ],
  "replace_files": true
}
```

- `dependencies` are required. A pack is rejected when one is missing, failed, or outside its version constraint.
- `optional_dependencies` affect mount order only when the referenced pack is installed.
- `load_after` is a soft ordering rule and does not install or select another pack.
- `replace_files` overrides the default for that individual pack.
- Supported version constraints are exact versions, `>`, `>=`, `<`, `<=`, `^`, `~`, and space- or comma-separated ranges.
- Packs without a sidecar keep the existing behavior. Their fallback ID is the lowercase path below `Data/` without `.pck`, such as `mods/example_assets`.

Dependency packs should expose assets at stable `res://` paths. A dependent level or object scene can reference those meshes, materials, sounds, and textures normally once the dependency has mounted. The dependency should own each shared resource path; dependents should not duplicate those files.

## Notes
- Shared assets used by many packs should live in `shared.pck` to avoid duplication.
- Level packs should include level-specific textures/meshes/audio that are not reused elsewhere.
- Level packs should include the matching `LVL_*.tres` doc so Level Select can list the level.
- Each level pack and mod pack should include a `LevelPackManifest` inside the pack:
  - Path: `res://LS5Framework/Scenes/Levels/PackManifests/<pack_id>.tres`
  - `<pack_id>` should be unique, but does not need to match the PCK filename
  - The manifest lists the `LVL_*.tres` docs inside the pack
  - `LevelCatalog` scans the PackManifests directory at runtime, so no master list is required
- The base game uses `res://LS5Framework/Scenes/Levels/LevelRegistry.tres` to list built-in LevelDoc entries.
- Mods can override any resource path by shipping a PCK with the same path, since they load last.
- `ContentPackManager` emits `packs_loaded` after mounting packs so menus can wait before building lists.
- `LevelPackManifest` registers level documents after mounting. It is separate from the external JSON dependency manifest, which controls mount order before loading.

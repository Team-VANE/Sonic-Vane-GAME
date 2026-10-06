# Race Types

`RaceStart` defaults to **Classic Race**. Existing race scenes require no changes.

## Collection Race

1. Set the `RaceStart` race type to **Collection Race**.
2. Set `collection_required_count` to the number of items needed to finish.
3. Keep the existing `RaceGoal` linked through its `race_start_path`.
4. Add any number of `RaceCollectionItem.tscn` instances to the level.
5. Set each item's `race_start_path` when the level contains multiple collection races. With no path, the nearest Collection Race is selected; `race_id` can narrow automatic selection.

The goal returns the player to the race start with a white fade while preserving the current level state, timer, checkpoints, and collected items. Reaching the configured item count runs the linked goal's normal finish sequence.

`RaceStart.collection_progress_changed(player, collected, required)` can drive custom HUD elements. `collection_race_completed(player)` is emitted immediately before the finish handler runs.

## Custom Collection Items

Collection items expose the collection radius, fixed home-in duration, player-local target offset, visual scene, mesh, material, touched particle scene, entry sound, completion sound, bus, and sound volumes. A level PCK can ship an inherited or replacement item scene with its own resources.

Shared meshes, sounds, or materials should live in a dependency PCK and use stable `res://` paths. Declare that pack in the level PCK's external dependency manifest as described in `ContentPacks.md`.

## Race-Specific Object Layouts

Use `RaceObjectLayout.tscn` as a dummy `Node3D` parent for objects that should only exist during one race:

1. Add a `RaceObjectLayout` to the level.
2. Set its exported `race_id` to the corresponding `RaceStart.race_id`.
3. Place every race-specific object beneath that layout node.

Keep the corresponding `RaceStart` outside its layout so the player can activate it while the layout is disabled.

Layout Race IDs are matched case-insensitively. Layouts are disabled when the level initializes. Starting a race restores the matching layout's authored state before race objects reset, while every nonmatching layout remains disabled. All layouts are disabled again when the race ends or is canceled.

Disabling a layout recursively blocks processing and player input, hides visuals, removes collision layers and masks, disables collision shapes, stops audio, disables particles, pauses physics bodies, and clears common `active`, `enabled`, monitoring, and navigation states. Those values are restored to their captured authored settings when the layout is enabled.

Custom objects with additional external behavior can implement:

```gdscript
func set_race_object_enabled(is_enabled: bool) -> void:
	# Custom manager registration and external state.
	pass
```

## Per-Object Race Blacklists

Add `RaceObjectBlacklist.tscn` as a child of an individual object and add one or more Race IDs to `blacklisted_race_ids`. Its default `target_path` of `..` controls the parent object. A different target can be assigned when the component is stored elsewhere.

When one of those Race IDs starts, the target and its entire subtree receive the same comprehensive disable treatment as a layout. The target's authored state is restored when that race ends or a nonblacklisted race initializes. Use one blacklist component per target object.

## Ghost Compatibility

New ghost files record `race_type`. Ghost selection requires the level key, race ID, and race type to match. Ghost files created before race types existed are treated as **Classic Race**.

## Online start sequence

Online races gather participants before starting the lineup. Each participant confirms that the destination level is ready and every joined player is present in that level. The server then starts lineup preparation, waits for all lineups to finish, and releases the countdown. Readiness messages include the setup generation so cancelled attempts cannot advance a later race. A player leaving during setup is removed from the readiness barriers.

During an active Ring Race, hurt and death each remove up to 20 rings. Hurt spews only the number actually removed. Other race types retain their existing ring-loss behavior.

# Music Triggers

This framework adds a lightweight way to control background music directly from your levels without writing any extra code.

## MusicController

1. Instance `Objects/Music/MusicController.tscn` anywhere in your level root (one per scene is enough).
2. Optionally set **autoplay_stream** and the fade-in time if you want the level to start with a default track. Use **autoplay_volume_offset_db** to raise or lower that level track without changing the Music bus.
3. The controller owns the AudioStreamPlayers (bus defaults to `Music`) and exposes two methods for scripts: `play_music(stream, fade_in, fade_out, restart_if_same, from_position, volume_offset_db)` and `stop_music(fade_out)`.

The node automatically registers itself in the `MusicControllers` group so triggers can find it without wiring a reference.

## MusicTrigger

1. Drop `Objects/Music/MusicTrigger.tscn` where you want the player to cross.
2. Assign the **controller** export to the MusicController node you added (or leave it empty and keep **auto_find_controller** on to use the first controller in the scene).
3. Pick an `AudioStream` for **music_stream** and adjust the fade times. Enable **stop_music_instead** if you only want the trigger to end the current track.
4. If you need a trigger volume to end music once the player leaves, enable **stop_on_exit** so it tracks the body that entered and stops once it exits.

`MusicTrigger` inherits from `WorldObject`, so you still get `one_shot`, `enabled`, and `require_group` behaviour for free.

See `Scenes/TestScene.tscn` for an example setup that starts `Levels/Minecraft/Minecraft.ogg` the first time the player leaves the spawn pad.

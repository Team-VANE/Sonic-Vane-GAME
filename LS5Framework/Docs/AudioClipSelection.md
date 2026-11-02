# Random audio selection

Add semicolon-separated selection arguments to the audio **filename**, before its extension. The imported WAV/OGG/MP3 resource retains that filename path. Resource > Name is not used.

- `Rare line;_weight=0.1.ogg` or `Rare line;_weight=1-10.ogg`: one tenth the selection weight of an ordinary clip.
- `Common line;_weight=2.wav`: twice the ordinary weight.
- `Unused line;_weight=0.mp3`: excluded from random selection.
- `_chance=1-10` is accepted as a compatibility alias for `_weight=1-10`.

Weights are relative to the other eligible clips, not exact event probabilities. A weight of 0.1 among two ordinary weight-1 clips has probability 0.1 / 2.1 before repeat avoidance. Event-level voice chance settings remain separate. No silent footstep is introduced when a rare clip loses selection.

The last distinct clip is excluded when another positive-weight clip exists. Duplicate entries referring to the same resource/path are collapsed during registration. With only two distinct clips, repeat avoidance necessarily alternates them regardless of their weights; use three or more variants for useful rarity with no consecutive repeats. Single eligible clips may repeat. Null clips are excluded.

Player random SFX, footsteps (including wet overlays), event voices, emote voices, and character menu voices use the selector. Indexed remote playback reproduces the selected clip without another random roll. Directly played, non-random sounds are unaffected.

Player/action arrays and emote profiles register at player initialization. Menu voice profiles register once when first used. Dynamically supplied lists register on first use. Filename parsing, validation, deduplication, and weight totals occur during registration; selection uses cached entries. Changes to list length automatically trigger registration. For in-place list replacements or renamed audio files, call `PlayerAudio.register_sound_lists()`, `CharacterUIVoicePlayer.register_profile(profile, true)`, or `AudioClipSelector.register_clips(clips, true)` after editing. Do not refresh every frame.

Use decimal weights where possible. Fractions use `numerator-denominator` because `/` is not permitted in Windows filenames. Rename referenced files through Godot's FileSystem dock so its dependency updates can run; include renamed files in any explicit export lists. In-memory/generated streams and embedded subresources without their own file default to weight 1. Arguments in directory names are ignored.

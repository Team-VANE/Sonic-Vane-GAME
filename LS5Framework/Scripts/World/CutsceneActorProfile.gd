extends Resource
class_name CutsceneActorProfile

## Animation names to try for each cue, in order. Library-qualified names are supported.
@export var animation_cues: Dictionary[StringName, PackedStringArray] = {}
## Voice streams keyed by dialogue cue.
@export var dialogue_cues: Dictionary[StringName, AudioStream] = {}
## Action cues mapped to an actor action or a fallback animation cue.
@export var action_cues: Dictionary[StringName, StringName] = {}
## Character-specific data queried by scene scripts, such as reach or eyeline offsets.
@export var values: Dictionary = {}
## Actor-relative AnimationPlayer path when automatic discovery is insufficient.
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
## Actor-relative voice player path when automatic discovery is insufficient.
@export_node_path("AudioStreamPlayer3D", "AudioStreamPlayer") var dialogue_player_path: NodePath

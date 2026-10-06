extends Resource
class_name RivalProfile

@export_group("Rival Actor")
## Name shown on the rival HUD. Uses the actor node name when empty.
@export var rival_display_name: String = ""
## Character ID used to choose the rival player scene. Empty keeps the placed scene.
@export var rival_character_id: String = ""
## Affiliation used for NPC relationship rules.
@export var rival_affiliation: StringName = &"rival"
## Group used for the rival's default target search.
@export var rival_target_group: StringName = &"Player"

@export_group("Rival colors")
## Applies character tint colors to the rival model.
@export var rival_apply_character_colors: bool = false
## Primary body color used by the rival.
@export var rival_primary_color: Color = Color(0.18, 0.52, 1.0, 1.0)
## Secondary accent color used by the rival.
@export var rival_secondary_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Trail and sonic boom color used by the rival.
@export var rival_trail_color: Color = Color(0.2, 0.8, 1.0, 1.0)

@export_group("Rival Combat")
## Resource used to determine whether the rival survives damage.
@export var rival_resource_mode: int = 0
## Maximum health used when the rival uses health as a resource.
@export var rival_max_health: int = 3
## Rings carried by the rival when activated.
@export var rival_starting_rings: int = 0
## 3D distance at which the rival enters chase toward the target.
@export var rival_chase_range: float = 100.0
## 3D distance at which the rival initiates an attack from chase.
@export var rival_attack_range: float = 18.0
## Seconds before a defeated rival respawns.
@export var rival_respawn_delay: float = 5.0

@export_group("Rival Rings")
## Ring search radius used for self-preservation.
@export var rival_ring_search_radius: float = 80.0
## If enabled, collected rings restore health.
@export var rival_rings_restore_health: bool = true
## Health restored per collected ring.
@export var rival_health_restored_per_ring: float = 0.25
## Health fraction at which the rival searches for healing rings.
@export_range(0.0, 1.0, 0.01) var rival_health_self_preservation_threshold: float = 0.35

@export_group("Rival Rage")
## Hits required to trigger enraged behavior.
@export var rival_rage_hits_required: int = 3
## Seconds the rival stays enraged.
@export var rival_rage_duration: float = 15.0

@export_group("Rival Voice")
## Voice clips played when self-preservation starts.
@export var rival_self_preserve_voice_clips: Array[AudioStream] = []
## Chance for self-preservation voice.
@export_range(0.0, 1.0, 0.01) var rival_self_preserve_voice_chance: float = 1.0
## Voice clips played when enraged behavior starts.
@export var rival_enraged_voice_clips: Array[AudioStream] = []
## Chance for enraged voice.
@export_range(0.0, 1.0, 0.01) var rival_enraged_voice_chance: float = 1.0

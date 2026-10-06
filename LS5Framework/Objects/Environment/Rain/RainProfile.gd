extends Resource
class_name RainProfile

@export_group("Precipitation")
## Overall emitted rain amount. Use RainSystem transitions to change this during gameplay.
@export_range(0.0, 1.0, 0.01) var intensity: float = 0.65
## HDR-compatible color and opacity applied to both detail layers.
@export var tint: Color = Color(0.72, 0.82, 0.92, 0.58)
## Strength of the view-dependent highlight along each low-poly drop's edges.
@export_range(0.0, 2.0, 0.01) var edge_highlight_strength: float = 0.65
## Unshaded emission added to rain so it remains legible against dark scenery.
@export_range(0.0, 2.0, 0.01) var emission_strength: float = 0.18
## Fraction of each drop length used to soften its pointed ends.
@export_range(0.01, 0.49, 0.01) var tip_softness: float = 0.16
## Downward rain speed in world units per second.
@export_range(1.0, 120.0, 0.1) var fall_speed: float = 32.0
## World-horizontal wind velocity, where X and Y map to world X and Z.
@export var wind_velocity: Vector2 = Vector2.ZERO
## Random variation around the configured rain speed.
@export_range(0.0, 0.8, 0.01) var velocity_randomness: float = 0.12
## Angular variation around the wind-adjusted fall direction.
@export_range(0.0, 15.0, 0.1) var direction_spread_degrees: float = 1.8

@export_group("Audio")
## Maximum rain-loop volume before RainSystem intensity and cover filtering.
@export_range(-40.0, 12.0, 0.1) var audio_volume_db: float = -3.0
## Playback pitch applied to both rain loops.
@export_range(0.5, 2.0, 0.01) var audio_pitch_scale: float = 1.0

@export_group("Thunder")
## Enables automatically scheduled thunder for this rain profile.
@export var thunder_enabled: bool = false
## Minimum delay between automatic thunder sounds.
@export_range(1.0, 300.0, 0.5) var thunder_interval_min_seconds: float = 12.0
## Maximum delay between automatic thunder sounds.
@export_range(1.0, 300.0, 0.5) var thunder_interval_max_seconds: float = 30.0
## Probability that an automatic thunder event uses the loud thunder collection.
@export_range(0.0, 1.0, 0.01) var thunder_loud_probability: float = 0.55
## Maximum thunder volume before RainSystem cover attenuation.
@export_range(-40.0, 12.0, 0.1) var thunder_volume_db: float = -1.0
## Minimum random thunder playback pitch.
@export_range(0.5, 2.0, 0.01) var thunder_pitch_min: float = 0.92
## Maximum random thunder playback pitch.
@export_range(0.5, 2.0, 0.01) var thunder_pitch_max: float = 1.06

@export_group("Rain Volume")
## Height of the moving emission plane above the active camera.
@export_range(4.0, 100.0, 0.5) var spawn_height: float = 30.0
## Horizontal radius covered by detailed individual drops.
@export_range(2.0, 60.0, 0.5) var near_radius: float = 15.0
## Horizontal radius covered by clustered distant rain.
@export_range(8.0, 160.0, 0.5) var far_radius: float = 48.0
## Extra particle lifetime after crossing camera height, as a fraction of fall time.
@export_range(0.0, 1.0, 0.01) var lifetime_margin: float = 0.28

@export_group("Near Detail")
## Diameter and length of each detailed low-poly drop before random scale.
@export var near_drop_size: Vector2 = Vector2(0.02, 1.25)
## Minimum random scale of individual drops.
@export_range(0.05, 4.0, 0.01) var near_scale_min: float = 0.65
## Maximum random scale of individual drops.
@export_range(0.05, 4.0, 0.01) var near_scale_max: float = 1.35
## Camera distance where detailed drops begin fading out.
@export_range(0.0, 100.0, 0.5) var near_fade_out_start: float = 12.0
## Camera distance where detailed drops are fully replaced by distant rain.
@export_range(0.5, 140.0, 0.5) var near_fade_out_end: float = 23.0

@export_group("Far Detail")
## Diameter and length of each simplified distant drop before random scale.
@export var far_drop_size: Vector2 = Vector2(0.027, 2.0)
## Minimum random scale of simplified distant drops.
@export_range(0.05, 4.0, 0.01) var far_scale_min: float = 0.75
## Maximum random scale of simplified distant drops.
@export_range(0.05, 4.0, 0.01) var far_scale_max: float = 1.3
## Camera distance where clustered distant rain begins fading in.
@export_range(0.0, 240.0, 0.5) var far_fade_in_start: float = 12.0
## Camera distance where clustered distant rain reaches full opacity.
@export_range(0.5, 240.0, 0.5) var far_fade_in_end: float = 20.0
## Camera distance where clustered rain begins fading into the weather haze.
@export_range(1.0, 240.0, 0.5) var far_fade_out_start: float = 200.0
## Camera distance where clustered rain becomes fully transparent.
@export_range(2.0, 320.0, 0.5) var far_fade_out_end: float = 240.0

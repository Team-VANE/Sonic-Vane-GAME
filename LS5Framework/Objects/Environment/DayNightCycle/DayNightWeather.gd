@tool
extends Resource
class_name DayNightWeather

@export_group("Cloud Shape")
## Fraction of the sky covered by clouds.
@export_range(0.0, 1.0, 0.01) var cloud_coverage: float = 0.35
## Opacity of fully formed clouds.
@export_range(0.0, 1.0, 0.01) var cloud_density: float = 0.82
## Width of the transition between clear sky and cloud.
@export_range(0.01, 0.5, 0.005) var cloud_softness: float = 0.12
## Scale of the primary procedural cloud formations.
@export_range(0.25, 20.0, 0.01) var cloud_scale: float = 3.2
## Strength of small cloud detail layered over the primary formations.
@export_range(0.0, 2.0, 0.01) var cloud_detail: float = 0.72
## Amount of direct celestial light absorbed by clouds.
@export_range(0.0, 1.0, 0.01) var cloud_light_absorption: float = 0.42

@export_group("Cloud Volume")
## Noise-space thickness sampled through each cloud formation. Zero retains the original flat sampling.
@export_range(0.0, 4.0, 0.01) var cloud_volume_depth: float = 0.0
## Number of depth samples per cloud layer. Higher values add fullness at increased GPU cost.
@export_range(1, 4, 1) var cloud_volume_steps: int = 1
## Optical density accumulated through the sampled cloud volume.
@export_range(0.1, 4.0, 0.01) var cloud_optical_density: float = 1.0
## Directional self-shadowing through dense cloud cores using the active sun or moon; multiple volume steps are required.
@export_range(0.0, 1.0, 0.01) var cloud_core_shadow_strength: float = 0.0
## Multiplier for sunlit or moonlit rim lighting along cloud edges.
@export_range(0.0, 2.0, 0.01) var cloud_edge_light_strength: float = 1.0

@export_group("Cloud Layers")
## Normalized height of the primary cloud shell above the observer's planet surface.
@export_range(0.001, 0.25, 0.001) var lower_layer_height: float = 0.022
## Opacity contribution of the higher secondary cloud shell.
@export_range(0.0, 1.0, 0.01) var upper_layer_amount: float = 0.12
## Normalized height of the secondary cloud shell above the observer's planet surface.
@export_range(0.002, 0.5, 0.001) var upper_layer_height: float = 0.07
## Scale multiplier for formations in the secondary cloud shell.
@export_range(0.1, 4.0, 0.01) var upper_layer_scale: float = 0.62
## Wind speed multiplier for the secondary cloud shell.
@export_range(0.0, 5.0, 0.01) var upper_layer_wind_multiplier: float = 1.45
## Normalized shell distance where above-horizon clouds begin fading into atmospheric haze.
@export_range(0.0, 0.99, 0.01) var distance_fade_start: float = 0.82
## Normalized shell distance where above-horizon clouds become fully transparent.
@export_range(0.01, 1.0, 0.01) var distance_fade_end: float = 0.995
## Strength of the distant above-horizon cloud color blend toward the horizon atmosphere.
@export_range(0.0, 1.0, 0.01) var distance_haze_strength: float = 0.78
## Renders procedural clouds in the upper hemisphere above the horizon.
@export var above_horizon_clouds_enabled: bool = true
## Renders procedural clouds in the lower hemisphere below the horizon.
@export var below_horizon_clouds_enabled: bool = true
## Opacity multiplier for clouds projected below the horizon in elevated sky-scapes.
@export_range(0.0, 1.0, 0.01) var below_horizon_visibility: float = 0.0
## Vertical lower-hemisphere depth over which clouds fade in away from the horizon.
@export_range(0.01, 1.0, 0.01) var below_horizon_fade_depth: float = 0.35
## Formation-scale multiplier for clouds below the horizon; one matches the above-horizon projection.
@export_range(0.25, 8.0, 0.01) var below_horizon_scale: float = 1.0
## Fine-detail multiplier for clouds below the horizon; one matches the primary above-horizon layer.
@export_range(0.0, 2.0, 0.01) var below_horizon_detail: float = 1.0
## Virtual shell-height multiplier for below-horizon curvature; one mirrors the above-horizon shell.
@export_range(0.1, 4.0, 0.01) var below_horizon_curvature: float = 1.0
## Atmospheric color blending applied to the below-horizon cloud deck near the horizon.
@export_range(0.0, 1.0, 0.01) var below_horizon_haze_strength: float = 0.72

@export_group("Cloud Motion")
## World-horizontal cloud travel direction, where X and Y map to world X and Z.
@export var wind_direction: Vector2 = Vector2(1.0, 0.25)
## Procedural cloud travel speed in sky-space units per second.
@export_range(0.0, 1.0, 0.0001) var wind_speed: float = 0.004

@export_group("Lighting and Atmosphere")
## Direct light multiplier at complete overcast.
@export_range(0.0, 1.0, 0.01) var overcast_light_multiplier: float = 0.48
## Ambient light multiplier at complete overcast.
@export_range(0.0, 2.0, 0.01) var overcast_ambient_multiplier: float = 0.82
## Distance fog density multiplier for this weather state.
@export_range(0.0, 20.0, 0.01) var fog_density_multiplier: float = 1.0
## Environment saturation multiplier for this weather state.
@export_range(0.0, 2.0, 0.01) var saturation_multiplier: float = 1.0

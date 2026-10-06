@tool
extends Resource
class_name DynamicWeatherPreset

@export_group("Identity")
## Stable identifier used by transitions, saves, and multiplayer synchronization.
@export var preset_id: StringName = &"weather"
## Editor-facing name for this combined weather state.
@export var display_name: String = "Weather"
## Tags exposed to optional weather extensions such as snow, wind debris, or lightning.
@export var feature_tags: Array[StringName] = []

@export_group("Systems")
## Cloud, fog, lighting, and atmosphere settings applied to the day-night cycle.
@export var sky_weather: DayNightWeather
## Rain appearance and audio settings applied when precipitation support is enabled.
@export var rain_profile: RainProfile
## Additional data available to optional weather-system extensions.
@export var extension_data: Dictionary = {}

@export_group("Automatic Selection")
## Allows this preset to be selected by the automatic weather scheduler.
@export var automatic_selection_enabled: bool = true
## Base weighted probability used when this preset is eligible.
@export_range(0.0, 100.0, 0.01) var selection_weight: float = 1.0
## Relative weather intensity used to avoid implausibly abrupt changes.
@export_range(0.0, 1.0, 0.01) var severity: float = 0.5
## Selection multiplier applied during dawn and daytime.
@export_range(0.0, 4.0, 0.01) var daytime_weight_multiplier: float = 1.0
## Selection multiplier applied during dusk and nighttime.
@export_range(0.0, 4.0, 0.01) var nighttime_weight_multiplier: float = 1.0
## Minimum and maximum seconds this weather remains after its transition completes.
@export var duration_range_seconds: Vector2 = Vector2(120.0, 300.0)
## Minimum and maximum seconds used to blend into this weather.
@export var transition_range_seconds: Vector2 = Vector2(12.0, 30.0)

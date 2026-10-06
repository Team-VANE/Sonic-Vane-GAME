@tool
extends Resource
class_name DayNightProfile

@export_group("Atmosphere")
## Color below the horizon used to keep reflections and low-angle views grounded.
@export var ground_color: Color = Color(0.035, 0.028, 0.025, 1.0)
## Visibility of the ground-colored lower hemisphere. Zero renders the sky continuously in every direction.
@export_range(0.0, 1.0, 0.01) var ground_visibility: float = 1.0
## Rayleigh scattering strength for the blue atmospheric component.
@export_range(0.0, 8.0, 0.01) var rayleigh_strength: float = 2.0
## Mie scattering strength for haze and the glow around the sun.
@export_range(0.0, 2.0, 0.001) var mie_strength: float = 0.08
## Forward-scattering bias of atmospheric haze.
@export_range(-0.99, 0.99, 0.01) var mie_eccentricity: float = 0.8
## Optical thickness near the horizon.
@export_range(0.1, 20.0, 0.1) var turbidity: float = 4.0
## Enables Godot's depth fog for this profile. Disabled profiles still blend fog density out during transitions.
@export var fog_enabled: bool = true

@export_group("Celestial Appearance")
## Apparent angular diameter of the sun in degrees.
@export_range(0.05, 5.0, 0.01) var sun_angular_diameter_degrees: float = 0.53
## HDR intensity of the visible sun disk.
@export_range(0.0, 100.0, 0.1) var sun_disk_intensity: float = 18.0
## Apparent angular diameter of the moon in degrees.
@export_range(0.05, 10.0, 0.01) var moon_angular_diameter_degrees: float = 0.52
## HDR intensity of the visible moon disk.
@export_range(0.0, 20.0, 0.01) var moon_disk_intensity: float = 1.2
## Brightness of the procedural star field before time-of-day fading.
@export_range(0.0, 10.0, 0.01) var star_intensity: float = 1.4
## Density and apparent size of the procedural star field.
@export_range(64.0, 2048.0, 1.0) var star_scale: float = 720.0
## Fraction of available procedural star cells populated with visible stars.
@export_range(0.0, 1.0, 0.01) var star_density: float = 0.28
## Visibility of stars below the horizon for space and planetary-orbit scenes.
@export_range(0.0, 1.0, 0.01) var star_lower_hemisphere_visibility: float = 0.0
## Cool endpoint used for procedural star temperature variation.
@export var star_cool_color: Color = Color(0.62, 0.72, 1.0, 1.0)
## Warm endpoint used for procedural star temperature variation.
@export var star_warm_color: Color = Color(1.0, 0.88, 0.68, 1.0)

@export_group("Lighting Scales")
## Peak energy multiplier for the sun DirectionalLight3D.
@export_range(0.0, 20.0, 0.01) var sun_energy_scale: float = 1.35
## Peak energy multiplier for the moon DirectionalLight3D.
@export_range(0.0, 5.0, 0.001) var moon_energy_scale: float = 0.08
## Multiplier applied to the environment's sky brightness.
@export_range(0.0, 10.0, 0.01) var sky_energy_scale: float = 1.0
## Multiplier applied to the environment's ambient light.
@export_range(0.0, 10.0, 0.01) var ambient_energy_scale: float = 1.0

@export_group("Color Over Day")
## Sky color at the zenith, sampled over normalized time from midnight to midnight.
@export var zenith_color: Gradient
## Sky color at the horizon, sampled over normalized time from midnight to midnight.
@export var horizon_color: Gradient
## Sun and direct sunlight color over normalized time.
@export var sun_color: Gradient
## Moon and direct moonlight color over normalized time.
@export var moon_color: Gradient
## Ambient light color over normalized time.
@export var ambient_color: Gradient
## Distance fog color over normalized time.
@export var fog_color: Gradient
## Illuminated cloud color over normalized time.
@export var cloud_light_color: Gradient
## Shadowed cloud color over normalized time.
@export var cloud_shadow_color: Gradient

@export_group("Intensity Over Day")
## Sun light energy over normalized time.
@export var sun_energy: Curve
## Moon light energy over normalized time.
@export var moon_energy: Curve
## Sky brightness over normalized time.
@export var sky_energy: Curve
## Ambient brightness over normalized time.
@export var ambient_energy: Curve
## Procedural star visibility over normalized time.
@export var star_visibility: Curve
## Distance fog density over normalized time.
@export var fog_density: Curve
## Sun scattering applied to distance fog over normalized time.
@export var fog_sun_scatter: Curve


func sample_color(gradient: Gradient, normalized_time: float, fallback: Color) -> Color:
	if gradient:
		return gradient.sample(wrapf(normalized_time, 0.0, 1.0))
	return fallback


func sample_value(curve: Curve, normalized_time: float, fallback: float) -> float:
	if curve:
		return curve.sample_baked(wrapf(normalized_time, 0.0, 1.0))
	return fallback

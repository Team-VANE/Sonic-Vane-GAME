# Day-Night Cycle

`DayNightCycle.tscn` is a self-contained environment, sun, moon, cloud, and time controller. It remains available as a standalone scene. `EnvironmentWeatherSystem.tscn` is the recommended combined scene when a level also needs dynamic weather, precipitation, or online synchronization.

The sky is rendered through Godot's `Sky` resource. It has no mesh, particle boundary, or world-space extent, so it cannot clip when the player crosses a large map. Atmosphere, sun disk, moon disk, phase shading, stars, and clouds are analytic shader effects and require no imported images.

## Quick setup

1. Drag `res://LS5Framework/Objects/Environment/DayNightCycle/DayNightCycle.tscn` into a level.
2. Remove or disable the level's previous `WorldEnvironment` and main directional lights. Only one `WorldEnvironment` should be active.
3. Set `Time > Time Of Day Hours` and `Time > Day Length Minutes` on the instance.
4. Duplicate `Profiles/EarthLikeDayNight.tres` for level-specific atmosphere and lighting.
5. Duplicate a resource in `Weather/` for level-specific cloud and weather tuning.

The scene is ready to use without external textures. Profile gradients and curves are editable in the Inspector and preview directly in the editor viewport.

For the combined workflow, instance `res://LS5Framework/Objects/Environment/WeatherSystem/EnvironmentWeatherSystem.tscn`. Dynamic weather and time progression can be disabled independently for static per-scene environments.

## Authoring model

`DayNightProfile` controls the stable character of a sky:

- Zenith, horizon, sun, moon, ambient, fog, and cloud colors are `Gradient` resources sampled from midnight at `0.0`, noon at `0.5`, and the next midnight at `1.0`.
- Sun, moon, sky, ambient, star, fog density, and fog scattering values are `Curve` resources sampled over the same range.
- Rayleigh, Mie, turbidity, celestial angular sizes, and peak energy values define the atmosphere and celestial appearance.
- `Ground Visibility` fades the ground-colored lower hemisphere. Set it to zero for a continuous sky in every viewing direction.
- Star density, scale, intensity, temperature colors, and lower-hemisphere visibility define an asset-free procedural star field.

`DayNightWeather` controls conditions that can transition independently:

- Cloud coverage, density, softness, scale, detail, and absorption.
- Independent lower and upper curved cloud-shell heights, upper-layer amount, scale, and wind response.
- Distance fade start, fade end, and atmospheric haze strength for a long, soft cloud horizon.
- Wind direction and speed.
- Overcast direct-light, ambient-light, fog, and saturation response.

Included atmospheric profiles are `EarthLikeDayNight` and `DesertHaze`. Space profiles are `DeepSpace`, `DenseStarfield`, and `CosmicViolet`; all three hide the ground, disable Godot depth fog, keep stars visible at every time and viewing angle, and disable atmospheric sun and moon lighting.

Included weather presets are `Clear`, `PartlyCloudy`, `Overcast`, `Storm`, `Cloudless`, `HighAltitudeWisps`, `FastScatteredClouds`, and `HeavyFog`. Pair a space profile with `Cloudless` to remove planetary clouds and fog. No weather texture is generated or uploaded during gameplay.

## Runtime API

```gdscript
var cycle: DayNightCycle = get_tree().get_first_node_in_group(&"day_night_cycle")
cycle.set_time(8.5)
cycle.transition_to_time(18.75, 4.0)
cycle.transition_to_weather(preload("res://path/to/weather.tres"), 12.0)
cycle.transition_to_profile(preload("res://path/to/profile.tres"), 8.0)
cycle.pause_cycle()
cycle.resume_cycle()
```

For a space transition, use the existing profile and weather transitions together:

```gdscript
cycle.transition_to_profile(preload("res://LS5Framework/Objects/Environment/DayNightCycle/Profiles/DeepSpace.tres"), 4.0)
cycle.transition_to_weather(preload("res://LS5Framework/Objects/Environment/DayNightCycle/Weather/Cloudless.tres"), 4.0)
```

`Ground Visibility` and lower-hemisphere star visibility are blended during profile transitions, so the horizon can dissolve smoothly instead of switching abruptly.

Profiles expose `Fog Enabled` independently from their fog-density curve. During a transition into a fog-disabled profile, density fades to zero before the environment fog is switched off. A weather preset with a zero fog multiplier, such as `Cloudless`, also disables environment fog once its density reaches zero.

Useful signals are `time_changed`, `phase_changed`, `time_transition_finished`, `weather_transition_finished`, and `profile_transition_finished`.

`DayNightTransitionTrigger.tscn` provides a volume-based authoring workflow. Set a target weather, time, profile, or any combination. If its cycle path is empty, it uses the first node in the `day_night_cycle` group. Multiplayer checks keep the transition local to the entering client.

While the player debug view is visible, minus rewinds the active day-night cycle by 15 minutes and plus advances it by 15 minutes. Holding either key uses keyboard repeat for faster scrubbing. Numpad subtract and add are also supported.

## Lighting and performance

The sun and moon are directional lights, so their positions are irrelevant and their illumination has no world-space range. Their orbit is world-up based because the sky belongs to the level, not to a gravity-aligned player. Player-up gravity changes do not rotate the astronomical frame.

Cloud noise renders in the sky shader's half-resolution subpass. View rays intersect shallow spherical cloud shells above a normalized planet surface, which keeps the cloud deck gently curved without inheriting the sky dome's severe horizon stretch. `Lower Layer Height` controls the primary shell; smaller values look flatter, while larger values produce more visible curvature. The optional upper shell can move at a different apparent speed and scale.

Cloud distance is measured along each view ray against the shell's geometric horizon. `Distance Fade Start` preserves cloud definition across most of the visible deck, `Distance Fade End` controls where it becomes transparent, and `Distance Haze Strength` blends distant cloud color into the atmospheric horizon. Keep the fade end above the fade start; the shader enforces a safe minimum gap while weather resources transition. Dense cloud interiors also receive stronger absorption, while sun-facing cloud edges receive a restrained silver lining.

The sky radiance cubemap uses Godot's realtime process mode at 256 pixels so the default cloud motion can update every rendered frame without stepping. `Cloud Motion Update Interval Seconds` controls only the cloud offset upload: zero is smooth per-frame motion, while a positive interval deliberately throttles it. Faster wind makes large intervals more noticeable.

Godot invalidates a sky's radiance cubemap whenever any shader uniform changes, even if that uniform only affects visible clouds. Smooth motion therefore trades some reflection and image-based-lighting cost for fluid animation. Projects targeting lower-end hardware can increase `Cloud Motion Update Interval Seconds` and switch the embedded `Sky` process mode to Incremental. `Environment Update Interval Seconds` remains independent and controls profile, weather, fog, color, and other sky-state sampling; directional lights still rotate every frame. The default `0.2` seconds is a practical balance for a 24-minute day.

The shader deliberately does not access `TIME` or camera `POSITION`. Cloud motion is accumulated by the controller, so pausing, weather transitions, and throttled motion do not jump when wind direction or speed changes.

Directional shadows remain camera-relative even though the light is infinite. Increase the Sun node's `Directional Shadow Max Distance` only when distant real-time shadows are important; larger values reduce nearby shadow detail and increase the number of relevant shadow casters. The default is 500 world units with four PSSM splits.

The project camera already uses auto exposure. The cycle does not add another camera attribute resource, so it will not compete with camera-level exposure or depth-of-field settings. `SettingsManager` remains authoritative for SSR, SSAO, SSIL, SDFGI, glow, and sun shadows.

## Custom assets

No image assets are required. If a future art direction calls for authored constellations, a detailed lunar albedo, or weather-map-driven clouds, add those as imported resources referenced by the sky material. Load them with the level or during a loading screen; do not create `ImageTexture`, `NoiseTexture`, or shader source resources during active gameplay.

## Technical references

- [Environment and post-processing](https://docs.godotengine.org/en/latest/tutorials/3d/environment_and_post_processing.html)
- [Sky shaders](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/sky_shader.html)
- [Sky process and radiance modes](https://docs.godotengine.org/en/stable/classes/class_sky.html)
- [Directional lights and shadows](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html)

## Online clock

`EnvironmentWeatherSystem` uses a server-owned clock in `NetworkSession`. The clock continues while the host changes levels or occupies a different level from clients. Persistent time references share a clock channel and retain their configured hour offsets; systems without persistent time use a level-specific channel. The first request initializes the channel's time and progression settings, which remain authoritative for the session. Time triggers and progression changes update the session clock. Weather preset replication remains level-specific.

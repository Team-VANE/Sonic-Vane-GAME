# Environment Weather System

`EnvironmentWeatherSystem.tscn` is the recommended drag-and-drop environment scene. It contains the existing `DayNightCycle` and `RainSystem` scenes as modular children, while keeping both scenes usable independently.

## Static setup

1. Instance `res://LS5Framework/Objects/Environment/WeatherSystem/EnvironmentWeatherSystem.tscn` under the level environment node.
2. Remove or disable the level's previous `WorldEnvironment` and primary sun light.
3. Disable `Weather > Dynamic Weather Enabled` to retain `Initial Weather Id` indefinitely.
4. Set `Environment > Initial Time Mode` to `Fixed` and disable `Time Progression Enabled` to retain `Initial Time Of Day Hours` indefinitely.
5. Disable `Weather > Precipitation Enabled` if the level never uses rain.

Static weather still applies the selected combined preset once during scene startup. The original standalone environment scenes remain appropriate when a level only needs one subsystem.

Disable `Weather > Use Weather Presets` to retain the `DayNightWeather` and rain profile assigned directly to the contained scenes. In this mode, initial selection, dynamic scheduling, weather persistence, and synchronized preset changes are skipped. Time progression and time synchronization remain available independently.

## Day and night duration balance

Enable `Uneven Day Night Durations Enabled` to divide the configured complete-cycle duration unevenly without changing the 24-hour game clock. `Daylight Start Hour` and `Daylight End Hour` define the clock range treated as daylight, including ranges that cross midnight. `Daylight Duration Ratio` assigns that range a fraction of the cycle's real duration.

The default cycle uses a `06:00`–`18:00` daylight range and a ratio of `0.70`. A 24-minute complete cycle therefore spends 16.8 real minutes in those daylight hours and 7.2 real minutes at night. Direct time changes, transitions, persistence offsets, profile curves, and celestial positions continue to use ordinary game-clock hours. The combined environment system synchronizes the duration-balance settings so clients predict the authoritative clock at the same variable rate.

Graphics options remain independent from weather. SSR, SSAO, SSIL, SDFGI, glow, and sun or moon shadows are reapplied through `SettingsManager`; weather transitions only control atmospheric properties such as fog, lighting color, and cloud state.

## Fixed scene attributes

The contained `DayNightCycle` exposes independent fixed, time-driven, and weather-driven attribute check boxes. Disabled controls restore or preserve values authored on the scene's `Environment`, sun, moon, or sky material.

- Enable `Fixed Scene Fog` for completely fixed scene fog. This override takes priority over both fog-control check boxes.
- Disabling both `Time Controls Fog` and `Weather Controls Fog` also retains fixed scene fog.
- Disable only `Time Controls Fog` to keep the scene fog color and base density while permitting weather density multipliers.
- Disable `Weather Controls Lighting` to prevent overcast states from reducing ambient, sun, or moon energy.
- Disable `Time Controls Environment Lighting` to retain the scene's sky and ambient lighting values.
- Disable `Weather Controls Clouds` to retain the cloud shader state authored in the scene, including fixed cloud motion.
- Sky appearance, celestial motion, celestial lighting, stars, cloud lighting, fog, saturation, and procedural cloud state can be controlled independently.

## Clouds below the horizon

Every `DayNightWeather` resource includes independent `Above Horizon Clouds Enabled` and `Below Horizon Clouds Enabled` switches. Below-horizon clouds mirror the same spherical-shell projection used above the horizon. Scale, detail frequency, wind motion, and curvature therefore remain at parity when their below-horizon multipliers are set to one. The higher cloud layer correctly occludes the lower layer when viewed from above.

`Below Horizon Visibility` controls deck opacity, while `Below Horizon Fade Depth` controls how far below the horizon it takes to reach full opacity. `Below Horizon Scale`, `Below Horizon Detail`, and `Below Horizon Curvature` default to `1.0` for projection parity and act only as deliberate multipliers. `Below Horizon Haze Strength` blends distant formations into the horizon atmosphere. Visibility zero retains the normal ground-level horizon cutoff. `HighAltitudeWisps.tres` includes a sky-scape configuration using this feature.

Primary and secondary cloud layers are composited before silhouette lighting is applied. This prevents either layer from drawing a separate illuminated outline through the other layer where their opacity fields overlap.

`Distance Fade Start`, `Distance Fade End`, and `Distance Haze Strength` apply only to the shell-projected clouds above the horizon. Lower-hemisphere clouds use their visibility and fade-depth controls independently.

## Volumetric cloud appearance

The `Cloud Volume` controls add procedural depth without requiring image assets or runtime texture generation:

- `Cloud Volume Depth` separates 3D noise samples through each formation. Zero retains the original single-surface appearance.
- `Cloud Volume Steps` controls quality and GPU cost from one to four half-resolution samples per layer.
- `Cloud Optical Density` increases accumulated water-vapour opacity.
- `Cloud Core Shadow Strength` controls capped directional self-shadowing through multiple volume steps from the active sun or moon.
- `Cloud Edge Light Strength` controls sunlit or moonlit rim and silver-lining highlights across the sky, with stronger forward scattering near the active light source.

Below-horizon clouds are treated as an upward-facing deck viewed from above. Top-surface brightness follows the active sun or moon elevation, while the full celestial direction, including azimuth, orders the volume samples so internal shadows extend away from the light source. Above-horizon clouds retain underside and forward-scattering lighting.

A useful dense-cumulus starting point is volume depth `1.0`, four steps, optical density `1.7`, core shadow strength `0.45`, and edge light strength `1.2`. Reduce steps before the other values when targeting lower-end GPUs.

Set `Initial Weather Id` to `random` to select the starting preset through the same weighted scheduler used for later changes. With `Weather Random Seed` set to zero, both the starting state and later sequence are randomized.

Set `Initial Time Mode` to `Random` for a uniformly random starting game-clock hour when no persistent time is available. `Time Random Seed` can make that starting hour repeatable; zero produces a new seed at startup.

## Dynamic weather

`DynamicWeatherPreset` combines a `DayNightWeather`, a `RainProfile`, selection settings, feature tags, and extension data. The included combined presets cover clear, partly cloudy, overcast, heavy fog, light rain, steady rain, heavy rain, wind-driven rain, and thunderstorms.

Automatic selection uses:

- Weighted probability per preset.
- A preferred maximum severity change between consecutive states.
- A severity-distance probability penalty.
- Reduced probability for recently used states.
- Independent daytime and nighttime weight multipliers.
- Per-preset duration and transition ranges.

The server performs every random selection. `Weather Random Seed` can make an offline or hosted sequence repeatable.

## Weather persistence

Dynamic weather persists across participating level changes by default. Its runtime state cache carries:

- Current preset ID and remaining duration.
- Procedural cloud offset.
- Random-number state, so the sequence continues instead of restarting.

Levels share weather when they use the same `Weather Persistence Namespace`. Use a different namespace for unrelated worlds or campaigns. Disable `Persistent Weather Enabled` when a dynamic level should always begin independently. Static environments neither restore nor replace cached dynamic weather.

Call `clear_persistent_weather_state()` on the combined system to clear its continuity channel. `EnvironmentWeatherState.clear_state(state_namespace)` and `clear_all_states()` are also available when a broader reset is needed. This cache lasts for the running application and does not write a save file.

## Time persistence

Time persistence uses a separate cache and remains available with either static or dynamic weather. `Time Persistence Reference` selects a shared time channel and may add or subtract an in-game clock offset:

- `default` shares the canonical `default` clock.
- `default+1h30m` displays that clock 1 hour and 30 minutes later.
- `default-45m` displays that clock 45 minutes earlier.
- Decimal hours such as `default+1.5h` are supported.

Offsets do not accumulate between levels. A level saves its local clock minus its configured offset, preserving the canonical shared time. No operating-system timestamp or real loading duration is used; persistence records only the current day-phase hour. Disable `Persistent Time Enabled` for an independent clock, or call `clear_persistent_time_state()` to clear the referenced time channel.

## Optional weather systems

Add future subsystem nodes to `Additional Weather System Paths`. Each node may implement:

```gdscript
func set_weather_system_active(active: bool) -> void:
    pass

func transition_to_weather_preset(preset: DynamicWeatherPreset, duration_seconds: float) -> void:
    pass
```

Extensions can read `preset.feature_tags` and `preset.extension_data`. The controller also emits `weather_extension_updated`, allowing systems to connect without appearing in the path list.

## Runtime API

```gdscript
var environment: EnvironmentWeatherSystem = get_tree().get_first_node_in_group(&"environment_weather_system")
environment.transition_to_weather_id(&"heavy_rain", 18.0)
environment.set_static_weather(&"clear", 24.0)
environment.set_dynamic_weather_active(true)
environment.set_time_progression_active(false)
environment.set_precipitation_active(true)
environment.force_next_weather()
environment.clear_persistent_weather_state()
environment.clear_persistent_time_state()
```

Only the server or an offline scene may change global weather through this API while network synchronization is enabled.

## Online synchronization

When an online session is active, the server owns time progression, dynamic selection, transition timing, and the current preset. Weather changes and initial state use reliable RPCs. Solar time uses ordered, unreliable snapshots at `Network Sync Interval Seconds`, one second by default.

Clients extrapolate time between snapshots and smoothly converge using `Network Time Interpolation Speed`. Errors beyond `Network Time Snap Threshold Hours` correct immediately. Presets synchronize by stable ID because Godot multiplayer replication does not support Resource properties.

Every peer must instance the controller at the same scene path and use matching preset IDs. This follows Godot's RPC node-path requirement.

## Loading and performance

All sky, rain, audio, shader, curve, gradient, and preset resources are referenced by the combined scene and load with it. Weather changes do not create textures, meshes, noise maps, audio effects, or shader resources during gameplay.

## Technical references

- [High-level multiplayer](https://docs.godotengine.org/en/latest/tutorials/networking/high_level_multiplayer.html)
- [MultiplayerSynchronizer](https://docs.godotengine.org/en/latest/classes/class_multiplayersynchronizer.html)

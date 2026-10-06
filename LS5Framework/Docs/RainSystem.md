# Rain System

`RainSystem.tscn` is a camera-following, world-up rain volume for large levels. It uses the provided `Rain_Single.png` for detailed nearby drops and `Rain_1.png` for lower-cost clustered rain at distance. Both textures are imported before gameplay with mipmaps enabled; the system creates no textures, meshes, shaders, or noise resources during active play.

All included rain profiles use a far drop size of `Vector2(0.027, 2.0)`, fade in from 12 to 20 world units, and fade out from 200 to 240 world units. Far scale minimum and maximum remain profile-specific for weather-dependent density and variation.

## Quick setup

1. Drag `res://LS5Framework/Objects/Environment/Rain/RainSystem.tscn` under the level root.
2. Select a resource from `Rain/Profiles/` in the `Rain > Profile` property.
3. Leave `Camera Path` empty to follow the viewport's active camera, or assign a specific `Camera3D` for split-screen or scripted views.
4. Set `Cover Collision Mask` to physics layers used by roofs, terrain, and other rain-blocking collision objects.
5. Set `Collision Visual Mask` to render layers used by terrain and roof `MeshInstance3D` nodes.

The included profiles are `Dry`, `LightRain`, `SteadyRain`, `HeavyRain`, and `WindDrivenRain`.

## Distance detail

The near layer renders individual drops from `Rain_Single`. The far layer renders groups of streaks from `Rain_1`, reducing the particle count required to fill the horizon. Shader distance bands crossfade the two layers:

- `Near Fade Out Start/End` removes individual drops as they become too small to justify their cost.
- `Far Fade In Start/End` brings in clustered streaks before the near layer disappears.
- `Far Fade Out Start/End` dissolves distant rain rather than clipping it at the local weather-volume boundary.

Both layers use world-space particles, so existing drops do not move with the camera when the emitter anchor recenters. The spawn plane is shifted upwind by the expected fall time, keeping the visible rain volume centered on the camera after wind drift.

## Cover and collision

Cover suppression and particle collision solve different problems:

- Wind-aligned physics probes originate around the camera and trace opposite the rain velocity toward the spawn plane. A blocked center probe stops new emission; surrounding probes reduce emission near partial cover. This prevents a camera under a roof or inside a tunnel from generating local rain.
- `GPUParticlesCollisionHeightField3D` tracks the active camera in configurable distance steps and captures nearby visual geometry. Both particle layers use `Collision Hide On Contact`, so drops disappear when they reach terrain or roofs.

The cover mask uses physics layers and therefore requires collision bodies. The heightfield mask uses visual layers and only captures matching `MeshInstance3D` geometry. These masks are intentionally separate because gameplay collision and rendered geometry often use different layer layouts.

Heightfields represent the highest surface at each horizontal point and cannot fully represent rooms stacked above rooms. The physics probes provide the indoor/overhang decision, while the heightfield provides efficient per-drop contact over a large outdoor area. For specialized interiors, place the roof on the cover physics mask even if it is excluded from particle heightfield capture.

`Collision Recenter Distance` prevents a static level's heightfield from rebuilding for every tiny camera movement. `Collision Update Always` should remain off for static levels. Enable it only when moving meshes must alter rain collision continuously; rebuilding a heightfield every frame is expensive.

## Runtime API

```gdscript
var rain: RainSystem = $RainSystem
rain.transition_to_profile(
	preload("res://LS5Framework/Objects/Environment/Rain/Profiles/HeavyRain.tres"),
	4.0
)
rain.transition_to_profile(
	preload("res://LS5Framework/Objects/Environment/Rain/Profiles/Dry.tres"),
	3.0
)
```

`Intensity Multiplier` provides a non-destructive gameplay override. Call `refresh_profile()` after directly changing values on the active resource at runtime.

## Performance tuning

- Lower `Near Particle Capacity` first when GPU particle cost is high.
- Lower `Far Particle Capacity` if distant clusters overlap excessively.
- `Amount Ratio` is used for smooth intensity and cover transitions without restarting the simulation, but Godot still allocates the configured maximum capacity.
- Lower `Collision Heightfield Resolution` before shrinking its coverage if roof collision is too expensive.
- Increase `Particle Fixed FPS` only if fast drops tunnel through thin captured geometry. Interpolation and fractional delta remain enabled for smooth motion.
- Reduce `Cover Grid Size` or increase `Cover Check Interval Seconds` if physics probing is measurable. The default 3 by 3 grid performs 90 rays per second.

## Technical references

- [Godot 3D particle collisions](https://docs.godotengine.org/en/latest/tutorials/3d/particles/collision.html)
- [Godot 3D particle system properties](https://docs.godotengine.org/en/stable/tutorials/3d/particles/properties.html)
- [GPUParticlesCollisionHeightField3D](https://docs.godotengine.org/en/latest/classes/class_gpuparticlescollisionheightfield3d.html)
- [ParticleProcessMaterial collision modes](https://docs.godotengine.org/en/latest/classes/class_particleprocessmaterial.html)

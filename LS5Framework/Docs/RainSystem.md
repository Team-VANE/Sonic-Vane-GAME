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

- The overhead ray starts at the camera and looks up to `Roof Probe Height` above it. Wind-aligned rays sample the route toward the rain spawn plane. Near rain fades with exposure, while far rain stays visible through nearby openings. A roof above the spawn plane can suppress both layers when the camera is at least `Deep Shelter Distance` from sampled open sky.
- `GPUParticlesCollisionHeightField3D` tracks the active camera in configurable distance steps and captures nearby visual geometry. Both particle layers use `Collision Hide On Contact`, so drops disappear when they reach terrain or roofs.

The cover mask uses physics layers and therefore requires collision bodies. The heightfield mask uses visual layers and only captures matching `MeshInstance3D` geometry. These masks are intentionally separate because gameplay collision and rendered geometry often use different layer layouts.

Heightfields represent the highest surface at each horizontal point and cannot fully represent rooms stacked above rooms. The physics probes provide the indoor/overhang decision, while the heightfield provides efficient per-drop contact over a large outdoor area. For specialized interiors, place the roof on the cover physics mask even if it is excluded from particle heightfield capture.

`RainOccluder.tscn` is a box-shaped roof collider on the Rain Cover physics layer. Instance it at a roof or canopy and edit the box size to fit. The default rain mask includes this layer and the default terrain layer. For a concave roof collider, enable its backface collision if the upward probe needs to hit the underside.

`RainShelterVolume.tscn` is a box-shaped area on the Rain Shelter layer. Place it in the deep interior of a cave or room where outside rain should no longer be visible. Resize its box and keep it away from cave mouths, windows, and skylights that should retain a view of the rain. The camera position inside the area suppresses both rain layers and bypasses the ray grid. The heightfield pauses once existing particles expire and resumes when the camera leaves shelter.

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
- Open areas use a rotating outer probe to check for partial cover. Mixed cover runs the full grid. Reduce `Cover Grid Size` or increase `Cover Check Interval Seconds` if physics probing is measurable.
- `Cover Edge Rays per Tick` spreads the open-sky search over multiple physics ticks. A smaller budget reduces per-tick cost and increases the time needed to confirm deep shelter.

## Technical references

- [Godot 3D particle collisions](https://docs.godotengine.org/en/latest/tutorials/3d/particles/collision.html)
- [Godot 3D particle system properties](https://docs.godotengine.org/en/stable/tutorials/3d/particles/properties.html)
- [GPUParticlesCollisionHeightField3D](https://docs.godotengine.org/en/latest/classes/class_gpuparticlescollisionheightfield3d.html)
- [ParticleProcessMaterial collision modes](https://docs.godotengine.org/en/latest/classes/class_particleprocessmaterial.html)

# Movement time scale

`PlayerController` exposes **Movement Time > Movement Time Scale** in character scenes.

| Property | Default | Purpose |
| --- | --- | --- |
| `movement_time_scale` | `1.0` | Pawn's configured movement rate. |
| `movement_time_scale_multiplier` | `1.0` | Runtime modifier owned by gameplay effects. |
| `movement_time_scale_debuff_multiplier` | `1.0` | Debuff modifier; values below `1.0` also override animation exclusions. |
| `effective_movement_time_scale` | Computed | Product of all three values, clamped to `0.01`–`10.0`. Non-finite products fall back to `1.0`. |

```gdscript
player.movement_time_scale_multiplier = 0.5

# Restore the configured pawn rate.
player.movement_time_scale_multiplier = 1.0
```

A pawn configured at `0.7` with a gameplay multiplier of `0.5` runs at `0.35`. The effective property is derived; gameplay writes the multiplier instead. Zero is limited to `0.01`; pausing remains a separate system. Overlapping effects must compose their multipliers in the effect owner before assigning the result.

## Clock and velocity units

### Animation exclusions

Add `_movement-time-scale=false` to an AnimationTree node resource's **Resource > Name**, for example `Idle _gaze-enabled=true; _movement-time-scale=false`. This is the AnimationTree resource name, matching the gaze convention, rather than the state name or animation-library key. Unmarked resources retain movement-clock scaling.

The marker bypasses only the movement-clock factor. Existing roll, rail, drift, and locomotion playback tuning remains intact. Nested state machines follow their current state; inactive states do not trigger exclusions. A marker on a parent applies to its branch. Blend trees and blend spaces share the main playback clock, so an exclusion within the current branch exempts that entire blend. Prefer placing the marker on the blend resource when all its clips should be exempt. During a state crossfade, the destination/current state's policy controls the shared clock. Independent carry overlays remain outside this policy.

Debuff owners use the separate multiplier:

```gdscript
player.movement_time_scale_debuff_multiplier = 0.5

# Clear the slowdown debuff.
player.movement_time_scale_debuff_multiplier = 1.0
```

While a finite debuff multiplier is below `1.0`, the marker is ignored and animation playback uses the full effective movement rate. At a default rate of `0.7`, an excluded idle uses a movement-clock factor of `1.0` normally and `0.35` with a `0.5` debuff. An ordinary gimmick multiplier does not override exclusions. Debuff owners compose overlapping debuffs and restore the multiplier when the effect ends; this does not introduce a rival attack or automatic effect duration. The debuff state is captured alongside the movement rate each physics tick and replicated by Netfox.

### Simulation

The controller captures the effective rate once per physics tick. Changes during a tick apply to simulation on the next tick. Internal `velocity`, launch strengths, speed thresholds, gravity, and tuning curves remain in movement-clock units. Changing the rate preserves internal momentum.

`_movement_physics_process(delta)` receives scaled elapsed time. Player subclasses override this hook and call `super._movement_physics_process(delta)`; they must not scale its delta again or bypass the `_physics_process` clock wrapper.

`move_and_slide()` receives world velocity temporarily, then its collision-adjusted result is converted back to movement units. Direct rail, vault, and spline travel already consumes the scaled delta. Movement animation uses the existing `MoveTimeScale` animation-tree parameter.

- `get_movement_time_scale()` returns the current tick's captured scale during simulation, or the effective rate outside it.
- `is_movement_time_scale_debuff_active()` reports whether exclusions are overridden for the current tick.
- `get_movement_physics_delta()` supplies scaled physics elapsed time to helpers without a delta argument.
- `get_world_movement_velocity()` supplies actual player speed in world units per second.
- `world_to_movement_velocity(world_velocity)` converts externally measured velocities into player units.

Launches authored for the player, including springs and ramps, continue using existing strengths. Moving-platform displacement uses real elapsed time; inherited platform velocity and collision-surface velocity are converted to movement units. UI, camera input, world objects, network delivery, and wall-clock cache timers retain their clocks. Netfox replicates all three scale inputs.

## Expected behavior and verification

At a constant rate `s`, world speed scales by `s`, acceleration and gravity by `s²`, and movement durations by `1/s`. Static-world trajectories and stopping distances should remain equivalent within integration and collision tolerances. At `0.7`, traversal takes approximately 43% longer. Inputs must occur at equivalent movement times to reproduce an actively controlled path; moving targets and platforms continue on world time.

Manual checks:

1. Compare ramp takeoff, jump apex/range, rolling stopping distance, and loop detachment at `1.0` and `0.7`.
2. Compare spring launches, rail exits/switches, homing, and vault release paths at both rates.
3. Change the gameplay multiplier during flight, then restore `1.0`; check continuity of position, direction, and internal momentum.
4. Ride and leave a moving platform at both rates; confirm normal carry speed and inherited world momentum.
5. Check buddy/rival movement and remote player animation with unequal rates.

Higher rates increase distance traveled per physics tick and can increase collision/integration error. Custom animation trees need the existing `MoveTimeScale` parameter to scale movement playback. Separate visual effects and carry overlays retain their own playback clocks.

# LS5 Surface Behavior Import

Place behavior tags before Godot's collision suffix. For example:

`LoopWall_attachlimit=80_nodetach-colonly`

`Spikes_hurt-colonly`

`Void_deathplane_intangible-colonly`

`Loop_noslopegravity_nodetach_forceroll_nojump-colonly`

Tags are case-insensitive and may be combined with underscores, hyphens, spaces, or brackets.

| Tag | Behavior |
| --- | --- |
| `attachlimit=60` | Allows alignment up to 60 degrees from gravity-up. |
| `noattach` | Keeps the collider solid but prevents surface alignment. |
| `hurt` | Applies one damage event on contact. |
| `hurt=3` or `damage=3` | Passes the specified amount to the player's damage handler. |
| `deathplane` or `death` | Applies forced pit-death behavior on contact. |
| `intangible` | Replaces physical response with an imported trigger area. |
| `noslopegravity` or `noslopegrav` | Disables tangential slope gravity on the surface. |
| `nodetach` | Ignores ordinary angle, outward-speed, and minimum-speed adhesion detach rules and preserves normal braking at every angle. |
| `sticky` | Prevents geometry-driven surface launches and preserves normal braking at every angle. |
| `forcecling` | Automatically enters wall cling on an eligible wall without holding Parkour. Jump displays a contextual Wall Kick glyph. Requires a Parkour ability. |
| `invisible` | Hides the tagged mesh and descendant meshes while preserving collisions and triggers. |
| `forceroll` | Keeps characters with a roll action in the roll state. |
| `nojump` | Blocks ground jumps and coyote jumps. |
| `nocoyotejump` or `nocoyote` | Blocks coyote jumps while preserving ground jumps. |
| `noroll` | Prevents rolling while the surface behavior is active. |
| `nodrift` | Prevents drifting while the surface behavior is active. |

`noattach` takes precedence over `nodetach`. `forceroll` takes precedence over `noroll` when both are present on the same object. Death behavior takes precedence over damage behavior at runtime.

Sticky surfaces keep following abrupt transitions, outer edges, and temporary follow-probe gaps instead of applying a surface launch. Intentional jumps, springs, knockback, and scripted detach actions are unchanged. Sticky surfaces also disable passive steep-slope sliding while the player is braking. Normal ground or roll deceleration applies, and the player settles into stationary hold after dropping below the configured idle-hold speed.

Combine `sticky_nodetach` when a surface should block both geometry-driven launches and ordinary adhesion detachment.

An imported mesh object whose name contains `_GENCOL` has its per-node `Generate Physics` import option enabled automatically. Other per-node physics settings retain their configured values.

The stock Sonic-style damage handler treats any positive damage amount as one damage event. Numeric amounts remain available to alternate damage handlers.

Combine `intangible` with movement tags such as `forceroll`, `noroll`, `nodrift`, `nojump`, `sticky`, or `forcecling` to apply them while overlapping the trigger. `forcecling` still requires a nearby solid wall; trigger volumes do not provide a wall normal. For example: `RollZone_invisible_intangible_forceroll_GENCOL`. Overlapping `forceroll` takes precedence over `noroll`.

Use a closed collider volume for reliable `intangible` triggers. Zero-thickness or concave trigger meshes can miss fast-moving bodies.

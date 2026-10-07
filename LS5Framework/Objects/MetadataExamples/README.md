# Metadata examples

Instance an individual example into a level, or use `MetadataExamples.tscn` to place the full collection. The collection contains damage and death volumes.

| Scene | Behavior |
| --- | --- |
| `ForceRollTrigger.tscn` | Forces rolling while inside the volume. Roll input is not required. |
| `MovementRestrictionsTrigger.tscn` | Blocks rolling, drifting, ground jumps, and coyote jumps while inside the volume. |
| `ForceClingTrigger.tscn` | Forces a wall cling when an eligible solid wall is nearby. Requires a Parkour ability. |
| `StickyTrigger.tscn` | Applies surface adhesion and disables slope gravity while inside the volume. Intentional jumps remain available. |
| `AttachLimitTrigger.tscn` | Limits surface alignment to 60 degrees from gravity-up while inside the volume. |
| `DamageTrigger.tscn` | Applies one damage event when entering the volume. |
| `DeathTrigger.tscn` | Applies pit-death behavior when entering the volume. |
| `ForceRollSurface.tscn` | Forces rolling while contacting the solid surface. |
| `StickySurface.tscn` | Preserves surface adhesion and disables slope gravity on the solid surface. |
| `AttachLimitSurface.tscn` | Allows surface alignment up to 60 degrees from gravity-up. Rotate the surface to test the limit. |
| `NoAttachSurface.tscn` | Remains solid while preventing player surface alignment. |
| `NoCoyoteJumpSurface.tscn` | Allows ground jumps while blocking coyote jumps after leaving the surface. |
| `InvisibleSurface.tscn` | Invisible solid surface. The mesh is hidden explicitly; the collision shape remains enabled. |
| `ForceClingWall.tscn` | Automatically enters wall cling without holding Parkour. Jump displays a contextual Wall Kick glyph. |

## Area3D volumes

`MetadataTrigger.tscn` is the reusable Area3D template. Add behavior keys through the root node's Metadata section in the Inspector. Its script registers the volume with the same player behavior resolver used by solid surfaces.

Edit `CollisionShape3D` to change the volume. The orange editor preview follows a box shape's dimensions and transform. The preview is hidden during gameplay; enable `show_in_game` on `VolumePreview` to display it. Resize each instance's local shape rather than scaling a physics node. Multiple primitive or convex shapes may share one Area3D for an irregular volume.

Layer 32 is reserved for surface behavior trigger queries. The area mask determines which body layers receive its behavior. A `forcecling` volume requires a nearby solid wall to provide a wall normal, and a character with a Parkour ability.

## Solid surfaces

`MetadataSurface.tscn` is the solid template. Add Metadata to the StaticBody3D for the entire object, or to individual CollisionShape3D nodes for separate regions. Explicit shape values take precedence over body and ancestor values.

`InvisibleSurface.tscn` hides its mesh explicitly. The `_invisible` name tag performs mesh hiding during imported-scene processing; scene-authored examples do not require import processing.

## Behavior lifetime

Movement flags remain active while touching a surface or overlapping a volume. `forceroll` takes precedence over `noroll` across overlapping sources. Damage and death triggers apply on entry, while roll and drift restrictions remain active throughout the overlap. Leaving, deleting a volume, or respawning clears its contribution.

The import tag reference is in `addons/ls5_surface_attach_import/README.md`. These scenes store explicit metadata and do not depend on their node names being parsed.

## Create a solid metadata object

1. Instance `MetadataSurface.tscn` into a level and make it unique or save an inherited scene.
2. Select the root StaticBody3D and add a key through the Inspector's Metadata section.
3. Set the value's type to Boolean for flags, Float for an angle, or Integer for a damage amount.
4. Resize or replace the collision shape and visible mesh together. A solid example has an enabled CollisionShape3D and a body on the level's normal collision layer.

For example, `surface_force_roll = true` on the body forces rolling on its surfaces. Place a key on a CollisionShape3D instead to affect only that shape. A shape value of `false` overrides an inherited flag for that shape.

## Create an Area3D metadata object

1. Instance `MetadataTrigger.tscn` into a level and save an inherited scene for the new behavior.
2. Keep `ImportedSurfaceBehaviorArea.gd` attached to the root Area3D. An Area3D with metadata alone does not register player behavior.
3. Add the behavior keys to the root Area3D's Metadata section. `surface_intangible = true` documents the volume's purpose; an Area3D already has no solid collision response.
4. Edit the local BoxShape3D on `CollisionShape3D`. Its bottom starts at the scene origin and its height is six units by default.
5. Keep monitoring enabled and include the player's collision layer in the area's collision mask. Runtime queries use the reserved layer 32.

For a rolling zone, set `surface_force_roll = true`. For an irregular zone, use several boxes or convex shapes under one Area3D. They share the root's metadata, and leaving one shape does not end the effect while another still overlaps the player. Separate Area3D nodes allow different behaviors in different regions.

Concave triangle meshes describe collision shells rather than filled trigger volumes. Use primitive or convex shapes for Area3D detection. Import processing converts an existing concave trigger shape into a convex hull; that hull fills recesses and openings, so use authored convex pieces when those spaces must remain empty.

## Metadata keys

| Inspector key | Type | Meaning |
| --- | --- | --- |
| `surface_attach_max_angle_deg` | Float, 0–180 | Maximum alignment angle from gravity-up; zero prevents alignment. |
| `surface_damage_amount` | Integer, positive | Contact damage; the standard player damage handler treats positive amounts as one event. |
| `surface_death` | Boolean | Pit-death contact behavior. |
| `surface_intangible` | Boolean | Converts imported collision geometry into trigger volumes. |
| `surface_no_slope_gravity` | Boolean | Disables tangential slope gravity. |
| `surface_no_detach` | Boolean | Blocks ordinary adhesion detachment. |
| `surface_sticky` | Boolean | Blocks geometry-driven surface launches. |
| `surface_force_roll` | Boolean | Forces rolling while the behavior is active. |
| `surface_force_cling` | Boolean | Automatically clings to an eligible nearby wall. |
| `surface_no_jump` | Boolean | Blocks ground and coyote jumps. |
| `surface_no_coyote_jump` | Boolean | Blocks coyote jumps while preserving ground jumps. |
| `surface_no_roll` | Boolean | Blocks rolling unless another active source forces it. |
| `surface_no_drift` | Boolean | Blocks drifting. |
| `surface_invisible` | Boolean | Hides meshes during import processing. Scene-authored objects set mesh visibility explicitly. |

`noattach` is represented by `surface_attach_max_angle_deg = 0.0`. Characters need the corresponding abilities for forced roll or cling behavior. Existing damage, spring, automation, and pause locks still apply.

## Verification

Test entering, remaining inside, leaving, and teleporting outside each volume. Test shape boundaries and overlapping volumes separately. Test `ForceClingTrigger.tscn` beside a wall and confirm the contextual Wall Kick jump glyph. Use `ForceClingWall.tscn` to test an automatically clinging solid wall without a trigger.

The examples are included in the Objects pack and the desktop platform export selections. A game binary rebuild is not required to edit or test these scenes in Godot.

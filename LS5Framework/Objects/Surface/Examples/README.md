# Script-driven surfaces

`SurfaceBehavior.gd` uses reusable trait resources, following the camera constraint system. The same component works on a StaticBody3D, an Area3D, a Node3D containing collision objects, or a separate child node targeting existing geometry. Imported names and manually authored metadata remain supported.

## Templates

- `../Surface.tscn`: solid platform with a collision shape, a mesh, and surface traits on the root.
- `../SurfaceTrigger.tscn`: filled Area3D volume with surface traits on the root. Its box preview is visible in the editor and hidden during gameplay.
- `../SurfaceBehavior.tscn`: standalone component for an existing asset or Area3D that already has a script.

Instance a template, expand a Traits array, and create the corresponding resource. Inspector tooltips describe each setting. `INHERIT` leaves existing behavior untouched; an explicit enabled, disabled, allow, or block policy overrides that setting on the selected target.

## Target selection

`target_paths` contains node paths relative to the component. Select a body for its collision shapes, an individual solid CollisionShape3D or CollisionPolygon3D for a single region, or a subtree for several objects. Mesh visibility applies to MeshInstance3D nodes within the selected subtrees. Selecting only a collision shape does not select its sibling mesh.

An empty target list uses the component's own collision subtree. When a component has no collision children, it uses its parent subtree. A component attached directly to a MeshInstance3D uses that mesh's subtree. Other SurfaceBehavior components define separate subtrees and are not traversed.

CollisionShape3D and CollisionPolygon3D nodes require a CollisionObject3D parent. This system configures existing geometry; it does not create physics bodies from an ordinary Node3D or turn solid bodies into triggers. Use an Area3D for intangible behavior.

All shapes of one Area3D share its volume behavior. Use separate areas for different trigger policies. Solid shapes can have separate policies on the same body.

## Imported assets, including FBX

1. Create a wrapper Node3D and instance the imported scene beneath it.
2. Add `SurfaceBehavior.tscn` beneath the wrapper.
3. Set a target path to the imported asset, for example `../ImportedAsset`.
4. Add an attachment trait and enable `force_cling`, or choose another trait.
5. Confirm the imported asset contains enabled collision shapes on physics bodies. Generate collision through the model's import settings if needed.

The wrapper stores the configuration outside the imported file and survives reimport. No `_forcecling` tag is required. `ImportedAssetWrapper.tscn` demonstrates this arrangement with the existing test cube; replace its imported child with an FBX or GLB while retaining the target name.

## Traits

| Resource | Settings |
| --- | --- |
| `SurfaceMovementTrait` | Force, block, or allow rolling; block ground/coyote jumps or coyote jumps alone; enable/disable drifting and slope gravity. |
| `SurfaceAttachmentTrait` | Force wall cling; limit or disable gravity-relative alignment; sticky adhesion; prevent detachment; preserve momentum. |
| `SurfaceHazardTrait` | Override contact damage, clear inherited damage with zero, or enable/disable pit-death behavior. |
| `SurfaceVisibilityTrait` | Hide or show meshes during gameplay while preserving collision. Disabling the component restores their previous visibility. |
| `SurfaceBehaviorTrait` | Base resource for custom traits. Override `get_surface_metadata()` to return supported metadata keys and values. Call `emit_changed()` when a custom setting changes. |

Traits can be shared across components. Use Make Unique when an instance needs different settings. The examples use local resources so editing one instance does not change another.

Later entries in an array override earlier entries. Custom traits run after built-in traits. Forced roll clears roll blocking within a component; disabled alignment clears prevent-detach within a component.

## Resolution and lifetime

Scripted shape settings take precedence over scripted body settings, followed by authored/imported shape metadata and body/ancestor metadata. On the same target, higher `behavior_priority` wins per setting; equal priorities use the latest registration. Unspecified settings continue to inherit.

Across active surfaces and overlapping volumes, flags combine using the existing player rules: forced rolling takes precedence over roll blocking, and alignment limits use the most restrictive active limit. Allowing an action on one target does not cancel a restriction from another active volume.

Area3D targets keep their existing scripts and signals. Runtime registration adds the reserved physics layer 32 and enables monitoring; the original values are restored when the last component releases the area. The area's collision mask must include the player's body layer. Primitive or convex shapes provide filled volumes; concave triangle meshes describe hollow shells and produce unreliable volume occupancy.

Volume flags are active during overlap. Damage and death apply on entry, and fast crossings use the existing player sweep. Exit, teleport, removal, and respawn clear occupancy. Trait changes update active settings without restarting occupancy or repeating entry damage. Newly enabling a volume around an existing player counts as entry. Changing traits, enabled state, or priority queues a deferred refresh; call `refresh()` after scripted array or target changes when immediate registration is needed. Adding collision nodes to an existing target subtree also requires `refresh()`.

Wall cling requires an eligible nearby solid wall and a character with a Parkour ability. The jump prompt becomes the contextual Wall Kick glyph during cling. Existing movement, damage, automation, and pause locks still apply.

## Examples

Instance an individual scene or `SurfaceExamples.tscn` for the collection. The collection includes damage and death volumes.

| Scene | Setup |
| --- | --- |
| `ForceClingWall.tscn` | Solid wall with automatic cling. |
| `ForceRollSurface.tscn` | Solid platform forcing roll on contact. |
| `StickySurface.tscn` | Adhesion traits on a solid platform. |
| `InvisibleSurface.tscn` | Mesh hidden at runtime, collision retained. |
| `ForceRollTrigger.tscn` | Rolling throughout an intangible volume. |
| `MovementRestrictionsTrigger.tscn` | Jump, drift, and roll restrictions. |
| `ForceClingTrigger.tscn` | Automatic cling near a solid wall; the collection supplies a nearby wall. |
| `AttachLimitTrigger.tscn` | Alignment limited to 60 degrees from gravity-up. |
| `DamageTrigger.tscn` | One damage event on entry. |
| `DeathTrigger.tscn` | Pit-death behavior on entry. |
| `ExistingAreaTrigger.tscn` | Existing Area3D script plus a child surface component. Its original entry counter remains active. |
| `ShapeOverrides.tscn` | Two shapes on one body: teal forces roll, red blocks roll. |
| `ImportedAssetWrapper.tscn` | Imported geometry configured through a separate wrapper component. |

The components, trait scripts, and examples are selected for the Objects pack and desktop exports. The shared runtime registry is also selected for the Shared pack. A game binary rebuild is not required for editor testing.

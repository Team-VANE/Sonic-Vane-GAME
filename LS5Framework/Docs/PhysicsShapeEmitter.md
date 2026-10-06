# Physics Shape Emitter

Spawns random physics shapes (sphere, box, cylinder, capsule) as `RigidBody3D`
instances. Each spawn can randomize physics attributes (mass, friction, bounce,
damping, gravity scale) and initial velocities. Designed to remain compatible
with the Jolt physics backend by using standard Godot physics nodes and shapes.

## Files

- Scene: `Objects/Gameplay/PhysicsShapeEmitter.tscn`
- Script: `Objects/Gameplay/PhysicsShapeEmitter.gd`

## Placement

- Place the scene in a level.
- The emitter is a `Node3D` and does not collide; the spawned bodies do.

## Key Inspector Groups

### Spawn
- `spawn_enabled`: Master switch for spawning.
- `spawn_on_ready`: Spawn a batch immediately on scene start.
- `spawn_interval_sec`: Time between batches. Set to `0.0` for every physics frame.
- `spawn_count`: How many shapes per batch.
- `max_alive`: Upper limit for live spawned bodies (0 = unlimited).
- `spawn_parent_path`: Optional parent to place spawned bodies under.
- `spawn_local_space`: If enabled, spawn offsets use the emitter's local basis.
- `spawn_box_extents`: Half-size of the spawn box in units.
- `randomize_rotation`: Randomize spawned body rotation.

### Lifetime
- `lifetime_sec`: Auto-free spawned bodies after this time (0 = no auto-free).
- `cleanup_on_exit`: Free spawned bodies when the emitter leaves the tree.
- `spawned_group`: Group name assigned to all spawned bodies.

### Collision
- `collision_layer` / `collision_mask`: Applied to each spawned `RigidBody3D`.
  Defaults collide with the level (layer 1) and the player (layer 4).

### Shapes
Enable or disable each shape, and set size ranges per shape type:
- Sphere: `sphere_radius_min` / `sphere_radius_max`
- Box: `box_size_min` / `box_size_max`
- Cylinder: `cylinder_radius_min` / `cylinder_radius_max`, `cylinder_height_min` / `cylinder_height_max`
- Capsule: `capsule_radius_min` / `capsule_radius_max`, `capsule_height_min` / `capsule_height_max`

### Visual
- `material_override`: Optional material applied to all meshes.
- `randomize_albedo`: If no override is set, randomize a `StandardMaterial3D` color.

### Physics Attributes
- Random ranges for mass, friction, bounce, linear/Angular damping, gravity scale.

### Velocity
- `linear_velocity_min` / `linear_velocity_max`: Initial linear velocity.
- `angular_velocity_min` / `angular_velocity_max`: Initial angular velocity.
- `velocity_local_space` / `angular_velocity_local_space`: If enabled, velocity
  ranges are treated as local-space values and converted into world space.

## Notes

- Spawned bodies are physics-driven, so they can collide with the player and
  respond to impulses.
- `max_alive` is checked every batch to avoid runaway spawning.

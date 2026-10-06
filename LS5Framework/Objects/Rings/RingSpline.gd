extends Node3D
class_name RingSpline

## Packed scene to instantiate for each ring along the spline.
@export var ring_scene: PackedScene = preload("res://LS5Framework/Objects/Rings/Ring.tscn")

## Distance between consecutive rings along the path (in world units).
@export var ring_spacing: float = 8.0

## If true, each ring position is snapped to the ground collision below the spline point.
@export var terrain_warp_enabled: bool = false

## Height above the detected ground surface when terrain warp is active.
@export var terrain_warp_height_offset: float = 1.5

## Collision mask used for the downward terrain raycast.
@export_flags_3d_physics var terrain_warp_collision_mask: int = 0xFFFFFFFF

## Respawn delay for each spawned ring (seconds). Zero disables respawn.
@export var ring_respawn_delay: float = 60.0

## Optional Path3D node. Defaults to a child named "Path3D" if left empty.
@export var path_node: Path3D

var _managed_preparation: bool = false


func _ready() -> void:
	if not _managed_preparation:
		call_deferred("_regenerate_after_physics")


func prepare_for_level(_context: Dictionary) -> bool:
	_managed_preparation = true
	return true


func activate_for_gameplay(_context: Dictionary) -> bool:
	_regenerate()
	return true


func _regenerate_after_physics() -> void:
	if get_tree() == null:
		return
	await get_tree().physics_frame
	if get_tree() == null:
		return
	await get_tree().process_frame
	if is_inside_tree() and not _managed_preparation:
		_regenerate()


func _regenerate() -> void:
	# Clear any previously generated rings owned by this spline.
	for child in get_children():
		if child is Ring:
			child.queue_free()

	if path_node == null:
		path_node = get_node_or_null("Path3D") as Path3D
	if path_node == null:
		return

	var curve: Curve3D = path_node.curve
	if curve == null:
		return

	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return

	var count: int = int(length / maxf(ring_spacing, 0.01))
	for i: int in range(count + 1):
		var dist: float = i * ring_spacing
		var t: float = clampf(dist / length, 0.0, 1.0)
		var pos: Vector3 = curve.sample_baked(t * length)
		var world_pos: Vector3 = path_node.to_global(pos)

		pos = to_local(world_pos)

		if ring_scene == null:
			continue
		var ring_node: Node = ring_scene.instantiate()
		if not (ring_node is Node3D):
			if ring_node != null:
				ring_node.free()
			continue
		var ring_3d: Node3D = ring_node as Node3D
		ring_3d.position = pos
		if ring_3d is Ring:
			var ring: Ring = ring_3d as Ring
			if ring_respawn_delay >= 0.0:
				ring.respawn_delay_sec = ring_respawn_delay
			ring.configure_terrain_warp(
				terrain_warp_enabled,
				terrain_warp_height_offset,
				terrain_warp_collision_mask
			)
		add_child(ring_3d)
		if ring_3d is Ring and terrain_warp_enabled:
			(ring_3d as Ring).apply_configured_terrain_warp()

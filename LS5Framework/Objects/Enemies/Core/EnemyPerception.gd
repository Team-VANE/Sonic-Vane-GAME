extends Node
class_name EnemyPerception

signal target_changed(target: Node3D)

@export_group("Detection")
## Enables automatic target acquisition.
@export var detection_enabled: bool = true
## Primary group searched for targets.
@export var target_group_primary: StringName = &"player"
## Secondary group searched for targets.
@export var target_group_secondary: StringName = &"Player"
## Maximum distance at which a new target can be acquired.
@export var detection_radius: float = 18.0
## Maximum distance at which the current target remains acquired.
@export var loss_radius: float = 24.0
## Horizontal field of view. Values at or above 360 disable the cone test.
@export_range(0.0, 360.0, 0.5) var field_of_view_deg: float = 220.0
## Maximum target distance along gravity-up. Zero disables this limit.
@export var vertical_tolerance: float = 12.0
## Time between acquisition scans.
@export var scan_interval_sec: float = 0.12
## Time a temporarily invalid current target remains remembered.
@export var target_memory_sec: float = 0.6

@export_group("Line of Sight")
## Requires an unobstructed ray before acquiring a target.
@export var line_of_sight_enabled: bool = true
## Physics layers that can block target visibility.
@export_flags_3d_physics var line_of_sight_mask: int = 1
## Node on the owning actor used as the sight origin.
@export var sight_origin_path: NodePath = NodePath("")

var _actor: CharacterBody3D = null
var _target: Node3D = null
var _scan_timer: float = 0.0
var _memory_timer: float = 0.0
var _visibility_timer: float = 0.0
var _target_visible: bool = true


func setup(actor: CharacterBody3D) -> void:
	_actor = actor
	var stagger_fraction: float = float(actor.get_instance_id() % 97) / 97.0
	_scan_timer = max(scan_interval_sec, 0.0) * stagger_fraction


func physics_tick(delta: float) -> void:
	if not detection_enabled or _actor == null:
		set_target(null)
		return
	_scan_timer = max(_scan_timer - delta, 0.0)
	_visibility_timer = max(_visibility_timer - delta, 0.0)
	if _target and is_instance_valid(_target):
		if _target_suppresses_enemy_targeting(_target):
			set_target(null)
		elif _current_target_is_valid():
			_memory_timer = max(target_memory_sec, 0.0)
			return
		else:
			_memory_timer = max(_memory_timer - delta, 0.0)
			if _memory_timer > 0.0:
				return
			set_target(null)
	if _scan_timer > 0.0:
		return
	_scan_timer = max(scan_interval_sec, 0.01)
	set_target(_find_best_target())


func get_target() -> Node3D:
	if _target and is_instance_valid(_target):
		return _target
	return null


func set_target(target: Node3D) -> void:
	if target == _target:
		return
	_target = target
	_target_visible = true
	_visibility_timer = max(scan_interval_sec, 0.01)
	_memory_timer = max(target_memory_sec, 0.0) if target else 0.0
	target_changed.emit(_target)


func clear() -> void:
	set_target(null)
	_scan_timer = 0.0
	_memory_timer = 0.0


func _find_best_target() -> Node3D:
	var best_target: Node3D = null
	var best_distance_squared: float = INF
	var visited: Dictionary = {}
	var groups: Array[StringName] = []
	if target_group_primary != &"":
		groups.append(target_group_primary)
	if target_group_secondary != &"" and target_group_secondary != target_group_primary:
		groups.append(target_group_secondary)
	for group_name: StringName in groups:
		for candidate_value: Variant in _actor.get_tree().get_nodes_in_group(group_name):
			if not (candidate_value is Node3D):
				continue
			var candidate: Node3D = candidate_value as Node3D
			var candidate_id: int = candidate.get_instance_id()
			if visited.has(candidate_id):
				continue
			visited[candidate_id] = true
			var distance_squared: float = _actor.global_position.distance_squared_to(candidate.global_position)
			if distance_squared >= best_distance_squared:
				continue
			if not _target_within_limits(candidate, max(detection_radius, 0.0), true):
				continue
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_target = candidate
	return best_target


func _current_target_is_valid() -> bool:
	if not _target_within_limits(_target, max(loss_radius, detection_radius), false, false):
		return false
	if _visibility_timer <= 0.0:
		_visibility_timer = max(scan_interval_sec, 0.01)
		_target_visible = not line_of_sight_enabled or _has_line_of_sight(_target)
	return _target_visible


func _target_within_limits(candidate: Node3D, radius: float, use_fov: bool, check_visibility: bool = true) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if _target_suppresses_enemy_targeting(candidate):
		return false
	var offset: Vector3 = candidate.global_position - _actor.global_position
	if radius > 0.0 and offset.length_squared() > radius * radius:
		return false
	var up: Vector3 = _get_actor_up()
	if vertical_tolerance > 0.0 and abs(offset.dot(up)) > vertical_tolerance:
		return false
	var planar_offset: Vector3 = offset - up * offset.dot(up)
	if use_fov and field_of_view_deg < 359.9 and planar_offset.length() > 0.001:
		var forward: Vector3 = -_actor.global_basis.z
		forward -= up * forward.dot(up)
		if forward.length() > 0.001:
			var angle_deg: float = rad_to_deg(acos(clamp(forward.normalized().dot(planar_offset.normalized()), -1.0, 1.0)))
			if angle_deg > field_of_view_deg * 0.5:
				return false
	if check_visibility and line_of_sight_enabled and not _has_line_of_sight(candidate):
		return false
	return true


func _target_suppresses_enemy_targeting(candidate: Node3D) -> bool:
	if candidate == null or not candidate.has_method("is_enemy_targeting_suppressed"):
		return false
	var suppressed_value: Variant = candidate.call("is_enemy_targeting_suppressed")
	return suppressed_value is bool and bool(suppressed_value)


func _has_line_of_sight(candidate: Node3D) -> bool:
	var world: World3D = _actor.get_world_3d()
	if world == null:
		return true
	var origin: Vector3 = _actor.global_position
	if sight_origin_path != NodePath(""):
		var origin_node: Node3D = _actor.get_node_or_null(sight_origin_path) as Node3D
		if origin_node:
			origin = origin_node.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin,
		candidate.global_position,
		line_of_sight_mask
	)
	query.exclude = [_actor.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Object = hit.get("collider") as Object
	return collider == candidate or (collider is Node and candidate.is_ancestor_of(collider as Node))


func _get_actor_up() -> Vector3:
	if _actor.has_method("get_gravity_up"):
		var up_value: Variant = _actor.call("get_gravity_up")
		if up_value is Vector3:
			var resolved_up: Vector3 = (up_value as Vector3).normalized()
			if resolved_up.length() >= 0.001:
				return resolved_up
	return Vector3.UP

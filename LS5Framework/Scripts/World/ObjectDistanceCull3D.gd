extends Node
class_name ObjectDistanceCull3D

const VISIBILITY_MARGIN: float = 20.0

## Enables distance culling for the parent object.
@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready():
			_update_visibility_ranges()
## Camera distance at which geometry is culled. Zero leaves the authored visibility ranges in use.
@export_range(0.0, 5000.0, 1.0, "or_greater", "suffix:m") var visual_distance: float = 450.0:
	set(value):
		visual_distance = value
		if is_node_ready():
			_update_visibility_ranges()
## Distance from a player or rival at which targeting and optional gameplay updates resume. Zero keeps them active.
@export_range(0.0, 5000.0, 1.0, "or_greater", "suffix:m") var activity_distance: float = 220.0
## Extra distance required to suspend activity after an object has resumed.
@export_range(0.0, 500.0, 1.0, "or_greater", "suffix:m") var activity_margin: float = 60.0
## Suspends the parent's homing, magnetism, ring and rail registrations while distant.
@export var suspend_targeting: bool = false
## Visual roots relative to the object. Empty applies the range to the object's geometry.
@export var visual_root_paths: Array[NodePath] = []
## Cosmetic animation mixers relative to the object. These pause beyond the visual range.
@export var cosmetic_animation_paths: Array[NodePath] = []

var _object: Node3D
var _target_manager: Node
var _distance_manager: Node
var _has_activity_hook: bool = false
var _has_activity_range: bool = false
var _uses_path_bounds: bool = false
var _activity_culled: bool = false
var _visual_culled: bool = false
var _animations: Array[AnimationMixer] = []
var _paused_animations: Array[AnimationMixer] = []
var _geometry_ranges: Dictionary[int, Vector2] = {}


func _ready() -> void:
	_object = get_parent() as Node3D
	if not _object:
		return
	_target_manager = get_node_or_null("/root/HomingTargetManager")
	_distance_manager = get_node_or_null("/root/ObjectDistanceManager")
	_has_activity_hook = _object.has_method(&"set_distance_culled")
	_has_activity_range = _object.has_method(&"get_distance_cull_activity_range")
	_uses_path_bounds = _object.has_method(&"get_path_world_aabb")
	for path: NodePath in cosmetic_animation_paths:
		var animation: AnimationMixer = _object.get_node_or_null(path) as AnimationMixer
		if animation:
			_animations.append(animation)
	_update_visibility_ranges()
	if _distance_manager:
		_distance_manager.register_component(self)


func _exit_tree() -> void:
	if is_instance_valid(_distance_manager):
		_distance_manager.unregister_component(self)
	if not is_instance_valid(_object) or _object.is_queued_for_deletion():
		return
	_set_activity_culled(false)
	_set_visual_culled(false)
	_restore_visibility_ranges()
	_animations.clear()
	request_ready()


func refresh(positions: PackedVector3Array, camera: Camera3D, minimum_target_distance: float) -> void:
	if not is_instance_valid(_object) or not _object.is_node_ready():
		return
	var cull_activity: bool = enabled and activity_distance > 0.0 and not positions.is_empty()
	if cull_activity and (_has_activity_hook or suspend_targeting):
		var distance: float = maxf(activity_distance, minimum_target_distance) if suspend_targeting else activity_distance
		if _has_activity_range:
			distance = maxf(distance, _object.call(&"get_distance_cull_activity_range"))
		if not _activity_culled:
			distance += activity_margin
		var origin: Vector3 = _object.global_position
		if _uses_path_bounds:
			var bounds: AABB = _object.call(&"get_path_world_aabb")
			for point: Vector3 in positions:
				if point.distance_squared_to(point.clamp(bounds.position, bounds.end)) <= distance * distance:
					cull_activity = false
					break
		else:
			for point: Vector3 in positions:
				if point.distance_squared_to(origin) <= distance * distance:
					cull_activity = false
					break
		_set_activity_culled(cull_activity)
	elif _activity_culled:
		_set_activity_culled(false)
	if not _animations.is_empty():
		var animation_distance: float = visual_distance + VISIBILITY_MARGIN * 2.0
		var cull_visual: bool = enabled and visual_distance > 0.0 and camera and camera.get_world_3d() == _object.get_world_3d() \
			and camera.global_position.distance_squared_to(_object.global_position) > animation_distance * animation_distance
		_set_visual_culled(cull_visual)


func get_world() -> World3D:
	return _object.get_world_3d()


func can_suspend_updates() -> bool:
	return _has_activity_hook or suspend_targeting or not _animations.is_empty()


func _update_visibility_ranges() -> void:
	_restore_visibility_ranges()
	if not _object or not enabled or visual_distance <= 0.0:
		return
	if visual_root_paths.is_empty():
		_apply_visibility_range(_object)
		return
	for path: NodePath in visual_root_paths:
		var visual: Node = _object.get_node_or_null(path)
		if visual:
			_apply_visibility_range(visual)


func _restore_visibility_ranges() -> void:
	for instance_id: int in _geometry_ranges:
		var geometry: GeometryInstance3D = instance_from_id(instance_id) as GeometryInstance3D
		if geometry:
			var previous: Vector2 = _geometry_ranges[instance_id]
			geometry.visibility_range_end = previous.x
			geometry.visibility_range_end_margin = previous.y
	_geometry_ranges.clear()


func _apply_visibility_range(root: Node) -> void:
	if root is GeometryInstance3D:
		_limit_geometry_range(root)
	for geometry: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		_limit_geometry_range(geometry)


func _limit_geometry_range(geometry: GeometryInstance3D) -> void:
	if geometry.visibility_range_begin >= visual_distance:
		return
	if geometry.visibility_range_end > 0.0:
		return
	_geometry_ranges[geometry.get_instance_id()] = Vector2(geometry.visibility_range_end, geometry.visibility_range_end_margin)
	geometry.visibility_range_end_margin = minf(VISIBILITY_MARGIN, visual_distance * 0.2)
	geometry.visibility_range_end = visual_distance


func _set_activity_culled(value: bool) -> void:
	if value == _activity_culled:
		return
	_activity_culled = value
	if suspend_targeting and is_instance_valid(_target_manager):
		_target_manager.set_distance_suspended(_object, value)
	if _has_activity_hook:
		_object.call(&"set_distance_culled", value)


func _set_visual_culled(value: bool) -> void:
	if value == _visual_culled:
		return
	_visual_culled = value
	if value:
		for animation: AnimationMixer in _animations:
			if is_instance_valid(animation) and animation.active:
				animation.active = false
				_paused_animations.append(animation)
		return
	for animation: AnimationMixer in _paused_animations:
		if is_instance_valid(animation):
			animation.active = true
	_paused_animations.clear()

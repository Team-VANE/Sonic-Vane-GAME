class_name SlidingGate
extends Node3D

## Starts at the fully open end of the animation.
@export var starts_open: bool = false
## Time to complete one opening or closing stroke.
@export_range(0.25, 15.0, 0.05, "or_greater", "suffix:s") var transition_time: float = 1.5
## Maximum speed at which closing panels clear players from the doorway.
@export_range(0.5, 30.0, 0.5, "or_greater", "suffix:m/s") var clearance_speed: float = 8.0

const TRACK_LEFT: NodePath = ^"LeftPanel"
const TRACK_RIGHT: NodePath = ^"RightPanel"
const PUSH_LEAD: float = 0.2
const CLEARANCE_MARGIN: float = 0.08

## Drives the panels, their colliders, and the two latch faces.
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
## Detects players overlapping the span and depth of the doorway.
@onready var _doorway: Area3D = $Doorway
## Sets the door plane clearance depth.
@onready var _doorway_shape: CollisionShape3D = $Doorway/CollisionShape3D
## Defines the width of the left panel's solid surface.
@onready var _left_shape: CollisionShape3D = $LeftPanel/CollisionShape3D
## Defines the width of the right panel's solid surface.
@onready var _right_shape: CollisionShape3D = $RightPanel/CollisionShape3D

var _travel: Animation
var _left_track: int = -1
var _right_track: int = -1
var _clip_time: float = 0.0
var _requested_open: bool = false
var _activation_sources: Dictionary = {}


func _ready() -> void:
	_requested_open = starts_open
	_travel = _animation_player.get_animation(&"travel")
	_left_track = _travel.find_track(TRACK_LEFT, Animation.TYPE_POSITION_3D)
	_right_track = _travel.find_track(TRACK_RIGHT, Animation.TYPE_POSITION_3D)
	_animation_player.play(&"travel")
	_clip_time = _travel.length if _wants_open() else 0.0
	_animation_player.seek(_clip_time, true)
	set_physics_process(false)


func open() -> void:
	_requested_open = true
	_wake_for_transition()


func close() -> void:
	_requested_open = false
	_wake_for_transition()


func toggle() -> void:
	if _requested_open:
		close()
	else:
		open()


func is_open() -> bool:
	return _travel and is_equal_approx(_clip_time, _travel.length)


func set_activation_source(source: Node, enabled: bool) -> void:
	if enabled:
		_activation_sources[source.get_instance_id()] = true
	else:
		_activation_sources.erase(source.get_instance_id())
	_wake_for_transition()


func _wants_open() -> bool:
	return _requested_open or not _activation_sources.is_empty()


func _wake_for_transition() -> void:
	if is_node_ready():
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	var endpoint: float = _travel.length if _wants_open() else 0.0
	if _clip_time == endpoint:
		set_physics_process(false)
		return
	var step: float = delta * _travel.length / maxf(transition_time, 0.01)
	var next_time: float = move_toward(_clip_time, endpoint, step)
	if next_time < _clip_time and not _clear_doorway(next_time, delta):
		return
	_clip_time = next_time
	_animation_player.seek(_clip_time, true)
	if _clip_time == endpoint:
		set_physics_process(false)


func _clear_doorway(next_time: float, delta: float) -> bool:
	if not _doorway.has_overlapping_bodies():
		return true
	var left_position: Vector3 = _travel.position_track_interpolate(_left_track, next_time)
	var right_position: Vector3 = _travel.position_track_interpolate(_right_track, next_time)
	var left_edge: float = left_position.x + (_left_shape.shape as BoxShape3D).size.x * 0.5
	var right_edge: float = right_position.x - (_right_shape.shape as BoxShape3D).size.x * 0.5
	var half_depth: float = (_doorway_shape.shape as BoxShape3D).size.z * 0.5
	var sideways_scale: float = global_basis.x.length()
	var depth_scale: float = global_basis.z.length()
	var forward: Vector3 = global_basis.z / depth_scale
	var clear: bool = true
	for body: Node3D in _doorway.get_overlapping_bodies():
		var player: PlayerController = body as PlayerController
		if not player or player._is_buddy_actor() or not player._network_is_local_authority():
			continue
		var center: Vector3 = to_local(player.get_main_collision_world_center())
		var radius: float = player.get_main_collision_world_radius()
		var width: float = radius / sideways_scale
		var side: float = -1.0 if center.z < 0.0 else 1.0
		var clearance: float = half_depth + (radius + CLEARANCE_MARGIN) / depth_scale
		if absf(center.z) >= clearance:
			continue
		if center.x - width > left_edge + PUSH_LEAD and center.x + width < right_edge - PUSH_LEAD:
			continue
		var distance: float = (clearance - absf(center.z)) * depth_scale
		player.move_and_collide(forward * side * minf(distance, clearance_speed * delta))
		var depth: float = to_local(player.get_main_collision_world_center()).z
		if (center.x - width <= left_edge or center.x + width >= right_edge) and absf(depth) < clearance - 0.001:
			clear = false
	return clear

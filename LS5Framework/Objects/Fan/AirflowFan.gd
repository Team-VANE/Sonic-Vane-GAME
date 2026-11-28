@tool
class_name AirflowFan
extends Area3D

signal active_changed(is_active: bool)

enum DirectionMode { FAN_UP, GRAVITY_UP }
const BLADE_SPEED_PER_FLOAT_SPEED: float = 30.0
const VISUAL_BASE_SCALE_META: StringName = &"_fan_visual_base_scale"

## Enables airflow, blade rotation, and the wind loop.
@export var active: bool = true:
	set(value):
		var was_active: bool = active
		_manual_active = value
		_update_effective_active(was_active)
	get:
		return _manual_active or not _activation_sources.is_empty()
## Higher priorities win when two fans overlap.
@export_range(-100, 100, 1) var airflow_priority: int = 0
## Local +Y follows the fan's rotation. Gravity Up follows each player's resolved gravity.
@export var direction_mode: DirectionMode = DirectionMode.FAN_UP
## Picks up grounded players when the current points away from their support surface.
@export var lift_from_ground: bool = true
## Applies airflow to loose switch balls inside the column.
@export var lift_switch_balls: bool = true
## Refreshes airborne abilities the first time the fan applies lift during each visit.
@export var refresh_on_entry: bool = false

@export_group("Volume")
## Radius of the airflow column around the fan's local Y axis.
@export_range(0.5, 100.0, 0.1, "or_greater", "suffix:m") var column_radius: float = 6.0:
	set(value):
		column_radius = value
		if is_node_ready():
			_sync_volume()
## Height of the airflow above the fan origin.
@export_range(1.0, 200.0, 0.5, "or_greater", "suffix:m") var column_height: float = 30.0:
	set(value):
		column_height = value
		if is_node_ready():
			_sync_volume()
## Fraction of the outer radius where lift tapers off. Zero gives uniform lift.
@export_range(0.0, 1.0, 0.01) var edge_falloff: float = 0.20

@export_group("Lift")
## Target speed along the current. Faster upward motion carries through.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m/s") var float_speed: float = 16.0:
	set(value):
		float_speed = value
		if is_node_ready() and not Engine.is_editor_hint() and not manual_blade_speed:
			_sync_blade_rotation()
## Acceleration toward Float Speed after arresting motion against the airflow.
@export_range(0.0, 500.0, 1.0, "or_greater", "suffix:m/s²") var lift_acceleration: float = 120.0
## Acceleration used to catch motion against the airflow. Higher values shorten the catch distance.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:m/s²") var fall_catch_strength: float = 230.0
## Speed added along the airflow when exiting through the top. Zero gives a coast exit.
@export_range(0.0, 100.0, 0.5, "or_greater", "suffix:m/s") var exit_kick_speed: float = 0.0

@export_group("Centering")
## Pull toward the centerline per metre of error. Zero preserves free sideways drift.
@export_range(0.0, 20.0, 0.1, "or_greater") var centering_strength: float = 0.0
## Fraction of the radius around the centerline with no centering.
@export_range(0.0, 1.0, 0.01) var centering_dead_zone: float = 0.12
## Maximum inward speed requested by the centering force.
@export_range(0.0, 50.0, 0.5, "or_greater", "suffix:m/s") var centering_max_speed: float = 12.0
## Limits how quickly centering can change the player's sideways velocity.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m/s²") var centering_acceleration: float = 45.0

@export_group("Visuals")
## Uniform scale of the fan model. The airflow uses Column Radius and Column Height.
@export_range(0.01, 100.0, 0.01, "or_greater") var visual_size: float = 1.0:
	set(value):
		visual_size = maxf(value, 0.01)
		if is_node_ready():
			_sync_visual_size()
## Plays the fan's looping blade rotation.
@export var blade_animation: AnimationPlayer
## Uses the authored Blade Speed. Otherwise blade speed follows Float Speed.
@export var manual_blade_speed: bool = false:
	set(value):
		manual_blade_speed = value
		if is_node_ready() and not Engine.is_editor_hint():
			_sync_blade_rotation()
## Blade rotation speed while the fan is active. Zero holds the blades still.
@export_range(0.0, 1440.0, 1.0, "or_greater", "suffix:deg/s") var blade_speed_deg: float = 480.0:
	set(value):
		blade_speed_deg = value
		if is_node_ready() and not Engine.is_editor_hint():
			_sync_blade_rotation()

@export_group("Audio")
## Positional wind loop played while airflow is enabled.
@export var wind_audio: AudioStreamPlayer3D

@onready var _volume: CollisionShape3D = $AirflowShape
## Model root for the fan body and blades.
@onready var _visual: Node3D = $Visual


var _manual_active: bool = true
var _activation_sources: Dictionary = {}
var _loose_balls: Array[CarryableObject] = []


func _ready() -> void:
	_sync_volume()
	_sync_visual_size()
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
	if lift_switch_balls:
		set_collision_mask_value(11, true)
	_sync_running_presentation()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func apply_spawn_overrides(overrides: Dictionary, _proxy: Node) -> void:
	if overrides.has("blade_speed_deg") and not overrides.has("manual_blade_speed"):
		manual_blade_speed = true


func activate() -> void:
	active = true


func deactivate() -> void:
	active = false


func toggle_active() -> void:
	active = not _manual_active


func set_activation_source(source: Node, enabled: bool) -> void:
	var was_active: bool = active
	var id: int = source.get_instance_id()
	if enabled:
		_activation_sources[id] = true
	else:
		_activation_sources.erase(id)
	_update_effective_active(was_active)


func _update_effective_active(was_active: bool) -> void:
	if was_active != active and is_node_ready() and not Engine.is_editor_hint():
		_sync_running_presentation()
		active_changed.emit(active)


func _sync_running_presentation() -> void:
	set_physics_process(active and not _loose_balls.is_empty())
	_sync_blade_rotation()
	if not is_instance_valid(wind_audio):
		return
	if active and wind_audio.stream:
		if not wind_audio.playing:
			wind_audio.play()
	else:
		wind_audio.stop()


func _sync_blade_rotation() -> void:
	if not is_instance_valid(blade_animation):
		return
	var speed: float = maxf(blade_speed_deg if manual_blade_speed else float_speed * BLADE_SPEED_PER_FLOAT_SPEED, 0.0)
	blade_animation.speed_scale = speed / 360.0
	if active and speed > 0.0:
		blade_animation.play(&"spin")
	else:
		blade_animation.pause()


func _sync_visual_size() -> void:
	if not _visual.has_meta(VISUAL_BASE_SCALE_META):
		_visual.set_meta(VISUAL_BASE_SCALE_META, _visual.scale)
	var base_scale: Vector3 = _visual.get_meta(VISUAL_BASE_SCALE_META)
	_visual.scale = base_scale * visual_size


func _sync_volume() -> void:
	var shape: CylinderShape3D = _volume.shape as CylinderShape3D
	shape.radius = maxf(column_radius, 0.05)
	shape.height = maxf(column_height, 0.05)
	_volume.position.y = shape.height * 0.5


func _on_body_entered(body: Node3D) -> void:
	if body.has_method(&"register_airflow_fan"):
		body.call(&"register_airflow_fan", self)
	elif lift_switch_balls and body is CarryableObject and body.is_in_group(&"switch_ball"):
		_loose_balls.append(body)
		set_physics_process(active)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method(&"unregister_airflow_fan"):
		body.call(&"unregister_airflow_fan", self)
	elif body is CarryableObject:
		_loose_balls.erase(body)
		set_physics_process(active and not _loose_balls.is_empty())


func _physics_process(delta: float) -> void:
	for index: int in range(_loose_balls.size() - 1, -1, -1):
		var ball: CarryableObject = _loose_balls[index]
		if not is_instance_valid(ball):
			_loose_balls.remove_at(index)
			continue
		if ball.is_carried() or ball.freeze:
			continue
		var weight: float = get_airflow_weight(ball.global_position)
		if weight > 0.0:
			var axis: Vector3 = get_airflow_axis(ball.get_gravity_up())
			var impulse: Vector3 = (apply_airflow(ball.linear_velocity, ball.global_position, axis, weight, delta) - ball.linear_velocity) * ball.mass
			if not impulse.is_zero_approx():
				ball.apply_central_impulse(impulse)
	if _loose_balls.is_empty():
		set_physics_process(false)


func get_airflow_axis(gravity_up: Vector3) -> Vector3:
	return gravity_up if direction_mode == DirectionMode.GRAVITY_UP else global_basis.y.normalized()


func get_airflow_weight(world_position: Vector3) -> float:
	var point: Vector3 = to_local(world_position)
	var radial_distance: float = Vector2(point.x, point.z).length()
	if point.y < 0.0 or point.y >= column_height or radial_distance >= column_radius:
		return 0.0
	var falloff: float = clampf(edge_falloff, 0.0, 1.0)
	if is_zero_approx(falloff):
		return 1.0
	return 1.0 - smoothstep(1.0 - falloff, 1.0, radial_distance / column_radius)


func apply_airflow(incoming: Vector3, world_position: Vector3, axis: Vector3, weight: float, delta: float) -> Vector3:
	var along_speed: float = incoming.dot(axis)
	var target_speed: float = maxf(float_speed, 0.0)
	var corrected_speed: float = along_speed
	var remaining_time: float = delta
	if corrected_speed < 0.0:
		var catch_rate: float = maxf(fall_catch_strength, 0.0) * weight
		if catch_rate > 0.0:
			remaining_time = maxf(0.0, delta + corrected_speed / catch_rate)
			corrected_speed = minf(corrected_speed + catch_rate * delta, 0.0)
		else:
			remaining_time = 0.0
	if corrected_speed < target_speed:
		corrected_speed = minf(corrected_speed + maxf(lift_acceleration, 0.0) * weight * remaining_time, target_speed)

	var result: Vector3 = incoming + axis * (corrected_speed - along_speed)
	if centering_strength <= 0.0 or centering_max_speed <= 0.0 or centering_acceleration <= 0.0:
		return result
	var point: Vector3 = to_local(world_position)
	var radial: Vector3 = Vector3(point.x, 0.0, point.z)
	var error: float = radial.length() - column_radius * clampf(centering_dead_zone, 0.0, 1.0)
	if error <= 0.0:
		return result
	var outward: Vector3 = (global_basis * radial).slide(axis).normalized()
	var radial_speed: float = result.dot(outward)
	var target_radial_speed: float = -minf(error * centering_strength, centering_max_speed)
	var radial_step: float = move_toward(radial_speed, target_radial_speed, centering_acceleration * delta) - radial_speed
	return result + outward * radial_step


func crossed_top(start: Vector3, finish: Vector3) -> bool:
	var from: Vector3 = to_local(start)
	var to: Vector3 = to_local(finish)
	if from.y >= column_height or to.y < column_height:
		return false
	var crossing: Vector3 = from.lerp(to, (column_height - from.y) / (to.y - from.y))
	return Vector2(crossing.x, crossing.z).length_squared() < column_radius * column_radius

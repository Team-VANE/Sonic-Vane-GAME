extends Node3D
class_name ExplosionEffect

@export_group("Playback")
## Starts the explosion when the scene enters the tree.
@export var auto_start: bool = true
## Removes this effect after the animation finishes.
@export var free_when_finished: bool = true
## Total explosion lifetime.
@export var duration: float = 1.15

@export_group("Light")
## Omni light used by the explosion flash.
@export var explosion_light_path: NodePath = NodePath("ExplosionLight")
## Light colour used by the explosion flash.
@export var explosion_light_color: Color = Color(1.0, 0.68, 0.18, 1.0)
## Maximum light energy reached when the effect starts.
@export var explosion_light_max_energy: float = 12.0
## Light range used by the explosion flash.
@export var explosion_light_range: float = 8.0
## Progress at which the light reaches zero energy.
@export var explosion_light_end_progress: float = 0.42
## Minimum visible energy threshold for the light.
@export var explosion_light_visible_threshold: float = 0.01

@export_group("Clouds")
## Mesh used for each gas cloud.
@export var cloud_mesh: Mesh
## Material used for each gas cloud.
@export var cloud_material: ShaderMaterial
## Number of gas cloud spheres.
@export var cloud_count: int = 6
## Starting cloud scale range.
@export var cloud_start_scale: Vector2 = Vector2(0.25, 0.45)
## Ending cloud scale range.
@export var cloud_end_scale: Vector2 = Vector2(1.7, 2.6)
## Maximum outward cloud travel.
@export var cloud_outward_distance: float = 1.6
## Random upward cloud travel.
@export var cloud_upward_distance: float = 0.65
## Cloud expansion ease.
@export var cloud_expand_curve: Curve

@export_group("Blast")
## Mesh used for each sharp blast plane.
@export var blast_mesh: Mesh
## Material used for each sharp blast plane.
@export var blast_material: ShaderMaterial
## Number of sharp blast planes.
@export var blast_count: int = 8
## Starting blast scale range.
@export var blast_start_scale: Vector2 = Vector2(0.25, 0.5)
## Ending blast length range.
@export var blast_end_length: Vector2 = Vector2(3.5, 5.5)
## Ending blast width range.
@export var blast_end_width: Vector2 = Vector2(0.35, 0.85)
## Maximum additional blast travel.
@export var blast_outward_distance: float = 2.2
## Blast expansion ease.
@export var blast_expand_curve: Curve

@export_group("Random")
## Random seed. Zero uses a randomized seed.
@export var random_seed: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _running: bool = false
var _elements: Array[Dictionary] = []
var _explosion_light: OmniLight3D = null


func _ready() -> void:
	add_to_group(&"LevelTransient")
	_explosion_light = get_node_or_null(explosion_light_path) as OmniLight3D
	_apply_explosion_light(1.0)
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	if auto_start:
		start()


func start() -> void:
	_clear_elements()
	_elapsed = 0.0
	_running = true
	_spawn_clouds()
	_spawn_blasts()
	_apply_explosion_light(0.0)
	set_process(true)


func _process(delta: float) -> void:
	if not _running:
		return

	_elapsed += delta
	var age: float = clamp(_elapsed / max(duration, 0.001), 0.0, 1.0)
	for element in _elements:
		_update_element(element, age)
	_apply_explosion_light(age)

	if age >= 1.0:
		_running = false
		set_process(false)
		_apply_explosion_light(1.0)
		if free_when_finished:
			queue_free()


func _spawn_clouds() -> void:
	if cloud_mesh == null or cloud_material == null:
		return
	for i in range(max(cloud_count, 0)):
		var direction: Vector3 = _random_direction()
		direction.y = abs(direction.y) * 0.35 + 0.15
		direction = direction.normalized()
		var start_scale_value: float = _rng.randf_range(cloud_start_scale.x, cloud_start_scale.y)
		var end_scale_value: float = _rng.randf_range(cloud_end_scale.x, cloud_end_scale.y)
		var mesh_instance: MeshInstance3D = _create_mesh_instance(cloud_mesh, cloud_material)
		mesh_instance.position = direction * _rng.randf_range(0.0, 0.15)
		mesh_instance.rotation = _random_rotation()
		mesh_instance.scale = Vector3.ONE * start_scale_value
		add_child(mesh_instance)

		_elements.append({
			"node": mesh_instance,
			"start_position": mesh_instance.position,
			"end_position": direction * _rng.randf_range(cloud_outward_distance * 0.35, cloud_outward_distance) + Vector3.UP * _rng.randf_range(0.0, cloud_upward_distance),
			"start_scale": Vector3.ONE * start_scale_value,
			"end_scale": Vector3.ONE * end_scale_value,
			"curve": cloud_expand_curve,
			"roll_speed": _rng.randf_range(-1.4, 1.4)
		})


func _spawn_blasts() -> void:
	if blast_mesh == null or blast_material == null:
		return
	for i in range(max(blast_count, 0)):
		var direction: Vector3 = _random_direction()
		direction.y *= 0.35
		if direction.length_squared() <= 0.0001:
			direction = Vector3.FORWARD
		direction = direction.normalized()
		var start_scale_value: float = _rng.randf_range(blast_start_scale.x, blast_start_scale.y)
		var end_length_value: float = _rng.randf_range(blast_end_length.x, blast_end_length.y)
		var mesh_instance: MeshInstance3D = _create_mesh_instance(blast_mesh, blast_material)
		mesh_instance.position = direction * start_scale_value * 0.5
		mesh_instance.transform = Transform3D(_basis_with_y_axis(direction, _rng.randf_range(-PI, PI)), mesh_instance.position)
		mesh_instance.scale = Vector3(start_scale_value, start_scale_value, start_scale_value)
		add_child(mesh_instance)

		_elements.append({
			"node": mesh_instance,
			"start_position": mesh_instance.position,
			"end_position": direction * (end_length_value * 0.5 + _rng.randf_range(0.0, blast_outward_distance)),
			"start_scale": Vector3(start_scale_value, start_scale_value, start_scale_value),
			"end_scale": Vector3(_rng.randf_range(blast_end_width.x, blast_end_width.y), end_length_value, 1.0),
			"curve": blast_expand_curve
		})


func _create_mesh_instance(mesh: Mesh, material: ShaderMaterial) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.set_surface_override_material(0, material)
	return mesh_instance


func _update_element(element: Dictionary, age: float) -> void:
	var node: MeshInstance3D = element["node"] as MeshInstance3D
	if node == null or not is_instance_valid(node):
		return

	var curve: Curve = element.get("curve", null) as Curve
	var t: float = age
	if curve != null:
		t = curve.sample_baked(age)

	var start_position: Vector3 = element["start_position"]
	var end_position: Vector3 = element["end_position"]
	var start_scale: Vector3 = element["start_scale"]
	var end_scale: Vector3 = element["end_scale"]
	node.position = start_position.lerp(end_position, t)
	node.scale = start_scale.lerp(end_scale, t)
	node.rotate_object_local(Vector3.FORWARD, float(element.get("roll_speed", 0.0)) * get_process_delta_time())

	node.set_instance_shader_parameter("age", age)


func _clear_elements() -> void:
	for element in _elements:
		var node: Node = element.get("node", null) as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	_elements.clear()


func _apply_explosion_light(age: float) -> void:
	if _explosion_light == null or not is_instance_valid(_explosion_light):
		return

	var end_progress: float = clamp(explosion_light_end_progress, 0.01, 1.0)
	var progress_factor: float = 1.0 - clamp(age / end_progress, 0.0, 1.0)
	var energy: float = max(explosion_light_max_energy, 0.0) * progress_factor

	_explosion_light.shadow_enabled = false
	_explosion_light.light_indirect_energy = 0.0
	_explosion_light.omni_range = max(explosion_light_range, 0.01)
	_explosion_light.light_color = Color(explosion_light_color.r, explosion_light_color.g, explosion_light_color.b, 1.0)
	_explosion_light.light_energy = energy
	_explosion_light.visible = energy > explosion_light_visible_threshold


func _random_direction() -> Vector3:
	var direction: Vector3 = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-0.25, 1.0),
		_rng.randf_range(-1.0, 1.0)
	)
	if direction.length_squared() <= 0.0001:
		return Vector3.UP
	return direction.normalized()


func _random_rotation() -> Vector3:
	return Vector3(
		_rng.randf_range(-PI, PI),
		_rng.randf_range(-PI, PI),
		_rng.randf_range(-PI, PI)
	)


func _basis_with_y_axis(direction: Vector3, roll: float) -> Basis:
	var y_axis: Vector3 = direction.normalized()
	var reference_axis: Vector3 = Vector3.UP
	if abs(y_axis.dot(reference_axis)) > 0.95:
		reference_axis = Vector3.RIGHT
	var x_axis: Vector3 = reference_axis.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).rotated(y_axis, roll)

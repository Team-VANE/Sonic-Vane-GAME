extends Node3D
class_name BarrierBlastFootTrailController

const FOOT_COUNT: int = 2
const LEFT_FOOT_INDEX: int = 0
const RIGHT_FOOT_INDEX: int = 1
const COLOR_SOURCE_PRIMARY: int = 0
const COLOR_SOURCE_SECONDARY: int = 1
const COLOR_SOURCE_TRAIL: int = 2
const BARRIER_FOOT_TRAIL_SHADER: Shader = preload(
	"res://LS5Framework/Scripts/Effects/barrier_foot_trail.gdshader"
)

var _player = null
var _skeleton: Skeleton3D = null
var _marker_nodes: Array[Node3D] = [null, null]
var _bone_indices: Array[int] = [-1, -1]
var _trail_meshes: Array[ImmediateMesh] = []
var _trail_instances: Array[MeshInstance3D] = []
var _trail_points: Array[Array] = [[], []]
var _sample_timers: Array[float] = [0.0, 0.0]
var _material: ShaderMaterial = null
var _activation_alpha: float = 0.0
var _sources_resolved: bool = false
var _resolution_warning_sent: bool = false


func setup(player: CharacterBody3D) -> void:
	_player = player
	name = "BarrierBlastFootTrails"
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 100
	_create_renderers()
	_resolve_sources()


func clear_trails() -> void:
	for foot_index: int in range(FOOT_COUNT):
		_trail_points[foot_index].clear()
		_sample_timers[foot_index] = 0.0
		if foot_index < _trail_meshes.size():
			_trail_meshes[foot_index].clear_surfaces()
	_activation_alpha = 0.0
	_update_material_parameters()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	if not _sources_resolved:
		_resolve_sources()

	var active: bool = bool(_player.barrier_foot_trails_enabled and _player._barrier_blast_active)
	_update_activation(delta, active)
	_update_material_parameters()
	_update_existing_points(delta)
	if active:
		_sample_feet(delta)
	else:
		for foot_index: int in range(FOOT_COUNT):
			_sample_timers[foot_index] = 0.0
	_rebuild_trails()


func _create_renderers() -> void:
	if not _trail_meshes.is_empty():
		return
	_material = ShaderMaterial.new()
	_material.shader = BARRIER_FOOT_TRAIL_SHADER
	for foot_index: int in range(FOOT_COUNT):
		var mesh: ImmediateMesh = ImmediateMesh.new()
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = "LeftFootTrail" if foot_index == LEFT_FOOT_INDEX else "RightFootTrail"
		instance.mesh = mesh
		instance.material_override = _material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.top_level = true
		add_child(instance)
		instance.global_transform = Transform3D.IDENTITY
		_trail_meshes.append(mesh)
		_trail_instances.append(instance)


func _resolve_sources() -> void:
	if _player == null:
		return
	_marker_nodes[LEFT_FOOT_INDEX] = _resolve_marker_node(_player.barrier_foot_trail_left_marker_path)
	_marker_nodes[RIGHT_FOOT_INDEX] = _resolve_marker_node(_player.barrier_foot_trail_right_marker_path)
	_skeleton = _resolve_skeleton()
	if _skeleton != null:
		_bone_indices[LEFT_FOOT_INDEX] = _find_bone_case_insensitive(
			_skeleton,
			_player.barrier_foot_trail_left_bone_name
		)
		_bone_indices[RIGHT_FOOT_INDEX] = _find_bone_case_insensitive(
			_skeleton,
			_player.barrier_foot_trail_right_bone_name
		)
	_sources_resolved = _has_source(LEFT_FOOT_INDEX) or _has_source(RIGHT_FOOT_INDEX)
	if not _sources_resolved and not _resolution_warning_sent:
		_resolution_warning_sent = true
		push_warning("BarrierBlastFootTrailController: foot trail sources could not be resolved.")


func _resolve_marker_node(path: NodePath) -> Node3D:
	if path != NodePath(""):
		var explicit_node: Node3D = _player.get_node_or_null(path) as Node3D
		if explicit_node != null:
			return explicit_node
	return null


func _resolve_skeleton() -> Skeleton3D:
	var skeleton_path: NodePath = _player.barrier_foot_trail_skeleton_path
	if skeleton_path != NodePath(""):
		var explicit_skeleton: Skeleton3D = _player.get_node_or_null(skeleton_path) as Skeleton3D
		if explicit_skeleton != null:
			return explicit_skeleton
	var search_root: Node = _player.model_root if _player.model_root != null else _player
	return _find_skeleton_recursive(search_root)


func _find_skeleton_recursive(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		var skeleton: Skeleton3D = root as Skeleton3D
		if (
			_find_bone_case_insensitive(skeleton, _player.barrier_foot_trail_left_bone_name) >= 0
			or _find_bone_case_insensitive(skeleton, _player.barrier_foot_trail_right_bone_name) >= 0
		):
			return skeleton
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton_recursive(child)
		if found != null:
			return found
	return null


func _find_bone_case_insensitive(skeleton: Skeleton3D, bone_name: StringName) -> int:
	if skeleton == null or bone_name == StringName():
		return -1
	var exact_index: int = skeleton.find_bone(String(bone_name))
	if exact_index >= 0:
		return exact_index
	var target_name: String = String(bone_name).to_lower()
	for bone_index: int in range(skeleton.get_bone_count()):
		if skeleton.get_bone_name(bone_index).to_lower() == target_name:
			return bone_index
	return -1


func _has_source(foot_index: int) -> bool:
	return _marker_nodes[foot_index] != null or (_skeleton != null and _bone_indices[foot_index] >= 0)


func _get_source_position(foot_index: int) -> Vector3:
	var marker: Node3D = _marker_nodes[foot_index]
	if marker != null and is_instance_valid(marker):
		return marker.global_position
	if _skeleton != null and _bone_indices[foot_index] >= 0:
		var bone_pose: Transform3D = _skeleton.get_bone_global_pose(_bone_indices[foot_index])
		return (_skeleton.global_transform * bone_pose).origin
	return Vector3.ZERO


func _update_activation(delta: float, active: bool) -> void:
	var target_alpha: float = 1.0 if active else 0.0
	var duration: float = (
		max(_player.barrier_foot_trail_fade_in_time, 0.0)
		if active
		else max(_player.barrier_foot_trail_fade_out_time, 0.0)
	)
	if duration <= 0.0:
		_activation_alpha = target_alpha
	else:
		_activation_alpha = move_toward(_activation_alpha, target_alpha, delta / duration)


func _update_material_parameters() -> void:
	if _material == null or _player == null:
		return
	_material.set_shader_parameter("trail_color", _get_trail_color())
	_material.set_shader_parameter("emission_energy", max(_player.barrier_foot_trail_emission_energy, 0.0))
	_material.set_shader_parameter("activation_alpha", clamp(_activation_alpha, 0.0, 1.0))
	_material.set_shader_parameter("tail_fade_power", max(_player.barrier_foot_trail_tail_fade_power, 0.1))
	_material.set_shader_parameter("head_fade_fraction", clamp(_player.barrier_foot_trail_head_fade_fraction, 0.0, 0.5))
	_material.set_shader_parameter("edge_softness", clamp(_player.barrier_foot_trail_edge_softness, 0.0, 0.5))


func _get_trail_color() -> Color:
	var effect_color: Color = _player.barrier_foot_trail_color
	var palette_color: Color = _player._character_trail_color
	match _player.barrier_foot_trail_color_source:
		COLOR_SOURCE_PRIMARY:
			palette_color = _player._character_primary_color
		COLOR_SOURCE_SECONDARY:
			palette_color = _player._character_secondary_color
		COLOR_SOURCE_TRAIL:
			palette_color = _player._character_trail_color
	palette_color.a *= effect_color.a
	return palette_color


func _sample_feet(delta: float) -> void:
	if not _sources_resolved:
		return
	var sample_interval: float = max(_player.barrier_foot_trail_sample_interval, 0.001)
	for foot_index: int in range(FOOT_COUNT):
		if not _has_source(foot_index):
			continue
		_sample_timers[foot_index] += delta
		if _sample_timers[foot_index] < sample_interval:
			continue
		_sample_timers[foot_index] = fmod(_sample_timers[foot_index], sample_interval)
		var position: Vector3 = _get_source_position(foot_index)
		var points: Array = _trail_points[foot_index]
		var min_distance: float = max(_player.barrier_foot_trail_min_sample_distance, 0.0)
		if not points.is_empty():
			var previous: Dictionary = points[points.size() - 1]
			var previous_position: Vector3 = previous.get("position", position)
			if position.distance_to(previous_position) < min_distance:
				continue
		_add_sample(foot_index, position)


func _add_sample(foot_index: int, position: Vector3) -> void:
	var outward: Vector3 = _get_foot_outward(foot_index)
	var player_speed: float = _player.velocity.length()
	var player_direction: Vector3 = Vector3.ZERO
	if player_speed > 0.001:
		player_direction = _player.velocity / player_speed
	var sample: Dictionary = {
		"position": position,
		"age": 0.0,
		"outward": outward,
		"direction": player_direction,
		"spawn_direction": player_direction,
		"motion_speed": player_speed,
		"spawn_speed": player_speed,
	}
	var points: Array = _trail_points[foot_index]
	points.append(sample)
	var max_points: int = max(_player.barrier_foot_trail_max_points, 2)
	while points.size() > max_points:
		points.pop_front()


func _update_existing_points(delta: float) -> void:
	var lifetime: float = max(_player.barrier_foot_trail_lifetime, 0.01)
	var player_speed: float = _player.velocity.length()
	var player_direction: Vector3 = Vector3.ZERO
	if player_speed > 0.001:
		player_direction = _player.velocity / player_speed
	var follow_scale: float = max(_player.barrier_foot_trail_follow_speed_scale, 0.0)
	var movement_time_scale: float = 1.0
	if _player.has_method("get_movement_time_scale"):
		movement_time_scale = max(float(_player.call("get_movement_time_scale")), 0.0)
	var trajectory_influence: float = clamp(_player.barrier_foot_trail_trajectory_follow_influence, 0.0, 1.0)
	var trajectory_smooth: float = max(_player.barrier_foot_trail_trajectory_follow_smooth, 0.0)
	var trajectory_blend: float = 1.0
	if trajectory_smooth > 0.0:
		trajectory_blend = 1.0 - exp(-trajectory_smooth * delta)
	for foot_index: int in range(FOOT_COUNT):
		var remaining: Array = []
		for point_variant in _trail_points[foot_index]:
			var point: Dictionary = point_variant
			var age: float = float(point.get("age", 0.0)) + delta
			if age >= lifetime:
				continue
			var direction: Vector3 = point.get("direction", Vector3.ZERO)
			var previous_direction: Vector3 = direction
			var spawn_direction: Vector3 = point.get("spawn_direction", direction)
			var motion_speed: float = float(point.get("motion_speed", 0.0))
			var spawn_speed: float = float(point.get("spawn_speed", motion_speed))
			if player_direction.length() > 0.001 and spawn_direction.length() > 0.001:
				var desired_direction: Vector3 = spawn_direction.normalized().slerp(
					player_direction,
					trajectory_influence
				).normalized()
				if direction.length() > 0.001:
					direction = direction.normalized().slerp(
						desired_direction,
						clamp(trajectory_blend, 0.0, 1.0)
					).normalized()
				else:
					direction = desired_direction
				var desired_speed: float = lerp(spawn_speed, player_speed, trajectory_influence)
				motion_speed = lerp(motion_speed, desired_speed, clamp(trajectory_blend, 0.0, 1.0))
			var outward: Vector3 = point.get("outward", _get_foot_outward(foot_index))
			if previous_direction.length() > 0.001 and direction.length() > 0.001:
				outward = _transport_vector_between_directions(outward, previous_direction, direction)
			var position: Vector3 = point.get("position", Vector3.ZERO)
			if direction.length() > 0.001 and motion_speed > 0.0 and follow_scale > 0.0:
				var follow_distance: float = motion_speed * follow_scale * movement_time_scale * delta
				position += direction * follow_distance
			point["age"] = age
			point["position"] = position
			point["direction"] = direction
			point["motion_speed"] = motion_speed
			point["outward"] = outward
			remaining.append(point)
		_trail_points[foot_index] = remaining


func _transport_vector_between_directions(vector: Vector3, from_direction: Vector3, to_direction: Vector3) -> Vector3:
	var from_normalized: Vector3 = from_direction.normalized()
	var to_normalized: Vector3 = to_direction.normalized()
	var axis: Vector3 = from_normalized.cross(to_normalized)
	var direction_dot: float = clamp(from_normalized.dot(to_normalized), -1.0, 1.0)
	if axis.length() > 0.0001:
		return vector.rotated(axis.normalized(), atan2(axis.length(), direction_dot)).normalized()
	if direction_dot < 0.0:
		var fallback_axis: Vector3 = from_normalized.cross(_get_player_up())
		if fallback_axis.length() < 0.001:
			fallback_axis = from_normalized.cross(Vector3.RIGHT)
		if fallback_axis.length() >= 0.001:
			return vector.rotated(fallback_axis.normalized(), PI).normalized()
	return vector.normalized()


func _rebuild_trails() -> void:
	for foot_index: int in range(FOOT_COUNT):
		_rebuild_trail(foot_index)


func _rebuild_trail(foot_index: int) -> void:
	if foot_index >= _trail_meshes.size():
		return
	var mesh: ImmediateMesh = _trail_meshes[foot_index]
	mesh.clear_surfaces()
	var points: Array = _trail_points[foot_index]
	if points.size() < 2 or _material == null:
		return
	var lifetime: float = max(_player.barrier_foot_trail_lifetime, 0.01)
	var half_width: float = max(_player.barrier_foot_trail_width, 0.001) * 0.5
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	var previous_width_axis: Vector3 = Vector3.ZERO
	for point_index: int in range(points.size()):
		var point: Dictionary = points[point_index]
		var position: Vector3 = point.get("position", Vector3.ZERO)
		var tangent: Vector3 = _get_point_tangent(points, point_index)
		var outward: Vector3 = point.get("outward", _get_foot_outward(foot_index))
		outward -= tangent * outward.dot(tangent)
		if outward.length() < 0.001:
			outward = _get_player_up()
			outward -= tangent * outward.dot(tangent)
		if outward.length() < 0.001:
			outward = tangent.cross(Vector3.RIGHT)
		outward = outward.normalized()
		var width_axis: Vector3 = tangent.cross(outward)
		if width_axis.length() < 0.001:
			width_axis = tangent.cross(_get_player_up())
		if width_axis.length() < 0.001:
			width_axis = Vector3.RIGHT
		width_axis = width_axis.normalized()
		if previous_width_axis.length() > 0.001 and width_axis.dot(previous_width_axis) < 0.0:
			width_axis = -width_axis
		previous_width_axis = width_axis
		var age_fraction: float = clamp(float(point.get("age", 0.0)) / lifetime, 0.0, 1.0)
		mesh.surface_set_normal(outward)
		mesh.surface_set_uv(Vector2(age_fraction, 0.0))
		mesh.surface_add_vertex(position - width_axis * half_width)
		mesh.surface_set_normal(outward)
		mesh.surface_set_uv(Vector2(age_fraction, 1.0))
		mesh.surface_add_vertex(position + width_axis * half_width)
	mesh.surface_end()


func _get_point_tangent(points: Array, point_index: int) -> Vector3:
	var previous_index: int = max(point_index - 1, 0)
	var next_index: int = min(point_index + 1, points.size() - 1)
	var previous_point: Dictionary = points[previous_index]
	var next_point: Dictionary = points[next_index]
	var previous_position: Vector3 = previous_point.get("position", Vector3.ZERO)
	var next_position: Vector3 = next_point.get("position", previous_position)
	var tangent: Vector3 = next_position - previous_position
	if tangent.length() < 0.001:
		var point: Dictionary = points[point_index]
		tangent = point.get("direction", Vector3.FORWARD)
	if tangent.length() < 0.001:
		tangent = Vector3.FORWARD
	return tangent.normalized()


func _get_player_up() -> Vector3:
	var player_up: Vector3 = _player.gravity_up.normalized()
	if player_up.length() < 0.001:
		player_up = Vector3.UP
	return player_up


func _get_foot_outward(foot_index: int) -> Vector3:
	var local_axis: Vector3 = _player.barrier_foot_trail_outward_axis
	if local_axis.length() < 0.001:
		local_axis = Vector3.RIGHT
	var outward: Vector3 = (_player.global_basis * local_axis.normalized()).normalized()
	if foot_index == LEFT_FOOT_INDEX:
		outward = -outward
	return outward

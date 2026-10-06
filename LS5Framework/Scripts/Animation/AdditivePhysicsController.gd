class_name AdditivePhysicsController
extends Node

@export_group("Node References")
## AnimationTree containing the configured additive blend nodes.
@export_node_path("AnimationTree") var animation_tree_path: NodePath = NodePath("../AnimationTree")
## AnimationPlayer supplying the configured animation names.
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = NodePath("../AnimationPlayer")
## Skeleton whose bone hierarchy expands each set's bone roots.
@export_node_path("Skeleton3D") var skeleton_path: NodePath = NodePath("../Armature/Skeleton3D")
## CharacterBody3D supplying velocity and grounded state. The nearest ancestor is used when empty.
@export_node_path("CharacterBody3D") var player_path: NodePath

@export_group("Additive Physics")
## Enables all configured additive physics sets.
@export var enabled: bool = true
## Per-bone animation and envelope configurations.
@export var physics_sets: Array[AdditivePhysicsSet] = []

@export_group("Animation Permission")
## Text in an AnimationTree resource Name that controls additive physics. Use `_additive-physics-enabled=false` or a set key such as `_additive-physics-ears=false`.
@export var animation_resource_marker: String = "_additive-physics"

var animation_tree: AnimationTree = null
var animation_player: AnimationPlayer = null
var skeleton: Skeleton3D = null
var player: CharacterBody3D = null
var _strengths: PackedFloat32Array = PackedFloat32Array()
var _hold_times: PackedFloat32Array = PackedFloat32Array()
var _animation_speeds: PackedFloat32Array = PackedFloat32Array()
var _animation_speed_hold_times: PackedFloat32Array = PackedFloat32Array()
var _permission_routes: Array[Dictionary] = []
var _valid_parameters: PackedByteArray = PackedByteArray()


func _ready() -> void:
	_resolve_references()
	_strengths.resize(physics_sets.size())
	_hold_times.resize(physics_sets.size())
	_animation_speeds.resize(physics_sets.size())
	_animation_speed_hold_times.resize(physics_sets.size())
	_valid_parameters.resize(physics_sets.size())
	_configure_sets()
	_cache_permission_routes()


func _physics_process(delta: float) -> void:
	if animation_tree == null or player == null:
		return
	var permissions: Dictionary = _get_current_permissions()
	var globally_allowed: bool = enabled and permissions.get("enabled", true) and not player.get("_is_dead")
	var velocity_value: Vector3 = player.velocity
	var grounded: bool = player.is_on_floor()
	var attached_state: Variant = player.get("attached")
	if attached_state is bool:
		grounded = attached_state
	var movement_speed: float = _get_movement_speed(velocity_value, grounded)
	for set_index: int in range(physics_sets.size()):
		var physics_set: AdditivePhysicsSet = physics_sets[set_index]
		if physics_set == null or _valid_parameters[set_index] == 0:
			continue
		var set_key: String = String(physics_set.set_id).strip_edges().to_lower().replace("-", "_")
		var set_allowed: bool = globally_allowed and physics_set.enabled and bool(permissions.get(set_key, true))
		if set_allowed:
			_update_envelope(set_index, physics_set, movement_speed, grounded, delta)
		else:
			_hold_times[set_index] = 0.0
			_strengths[set_index] = _move_over_time(
				_strengths[set_index],
				0.0,
				physics_set.suppression_fade_time,
				delta
			)
		_update_animation_speed(set_index, physics_set, movement_speed, grounded, set_allowed, delta)
		animation_tree.set(_get_amount_parameter(physics_set), _strengths[set_index])
		animation_tree.set(_get_time_scale_parameter(physics_set), _animation_speeds[set_index])


func refresh_animation_resource_routes() -> void:
	_cache_permission_routes()


func reset_envelopes() -> void:
	for set_index: int in range(_strengths.size()):
		_strengths[set_index] = 0.0
		_hold_times[set_index] = 0.0
		_animation_speed_hold_times[set_index] = 0.0
		if set_index < physics_sets.size() and physics_sets[set_index] != null and _valid_parameters[set_index] != 0:
			_animation_speeds[set_index] = max(physics_sets[set_index].inactive_animation_speed, 0.0)
			animation_tree.set(_get_amount_parameter(physics_sets[set_index]), 0.0)
			animation_tree.set(_get_time_scale_parameter(physics_sets[set_index]), _animation_speeds[set_index])
		else:
			_animation_speeds[set_index] = 0.0


func _resolve_references() -> void:
	animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not player_path.is_empty():
		player = get_node_or_null(player_path) as CharacterBody3D
	if player == null:
		var ancestor: Node = get_parent()
		while ancestor != null:
			if ancestor is CharacterBody3D:
				player = ancestor as CharacterBody3D
				break
			ancestor = ancestor.get_parent()


func _configure_sets() -> void:
	if animation_tree == null or not (animation_tree.tree_root is AnimationNodeBlendTree):
		push_warning("Additive physics requires an AnimationNodeBlendTree root.")
		return
	if animation_player == null or skeleton == null:
		push_warning("Additive physics references are incomplete.")
		return
	var blend_tree: AnimationNodeBlendTree = animation_tree.tree_root as AnimationNodeBlendTree
	var property_names: Dictionary = {}
	for property_data: Dictionary in animation_tree.get_property_list():
		property_names[String(property_data["name"])] = true
	for set_index: int in range(physics_sets.size()):
		var physics_set: AdditivePhysicsSet = physics_sets[set_index]
		if physics_set == null:
			continue
		var amount_parameter: String = _get_amount_parameter(physics_set)
		var time_scale_parameter: String = _get_time_scale_parameter(physics_set)
		if not property_names.has(amount_parameter) or not property_names.has(time_scale_parameter):
			push_warning("Additive physics set '%s' is missing its blend or playback-speed parameter." % physics_set.set_id)
			continue
		var additive_node: AnimationNodeAdd2 = blend_tree.get_node(physics_set.additive_node_name) as AnimationNodeAdd2
		var animation_node: AnimationNodeAnimation = blend_tree.get_node(physics_set.animation_node_name) as AnimationNodeAnimation
		var time_scale_node: AnimationNodeTimeScale = blend_tree.get_node(physics_set.animation_time_scale_node_name) as AnimationNodeTimeScale
		if additive_node == null or animation_node == null or time_scale_node == null:
			push_warning("Additive physics set '%s' has invalid AnimationTree node names." % physics_set.set_id)
			continue
		if not animation_player.has_animation(physics_set.animation_name):
			push_warning("Additive physics animation '%s' was not found." % physics_set.animation_name)
			continue
		animation_node.animation = physics_set.animation_name
		animation_node.loop_mode = Animation.LOOP_LINEAR
		_configure_bone_filter(additive_node, physics_set)
		_valid_parameters[set_index] = 1
		animation_tree.set(amount_parameter, 0.0)
		_animation_speeds[set_index] = max(physics_set.inactive_animation_speed, 0.0)
		animation_tree.set(time_scale_parameter, _animation_speeds[set_index])


func _configure_bone_filter(additive_node: AnimationNodeAdd2, physics_set: AdditivePhysicsSet) -> void:
	var selected_bones: Dictionary = {}
	for root_name: StringName in physics_set.bone_roots:
		var root_index: int = skeleton.find_bone(root_name)
		if root_index < 0:
			push_warning("Additive physics bone '%s' was not found for set '%s'." % [root_name, physics_set.set_id])
			continue
		selected_bones[root_name] = true
		if physics_set.include_child_bones:
			_collect_child_bones(root_index, selected_bones)
	var animation: Animation = animation_player.get_animation(physics_set.animation_name)
	if animation == null:
		return
	additive_node.filter_enabled = true
	for track_index: int in range(animation.get_track_count()):
		var track_path: NodePath = animation.track_get_path(track_index)
		if track_path.get_subname_count() <= 0:
			continue
		var bone_name: StringName = track_path.get_subname(0)
		if selected_bones.has(bone_name):
			additive_node.set_filter_path(track_path, true)


func _collect_child_bones(parent_index: int, selected_bones: Dictionary) -> void:
	for bone_index: int in range(skeleton.get_bone_count()):
		if skeleton.get_bone_parent(bone_index) != parent_index:
			continue
		selected_bones[skeleton.get_bone_name(bone_index)] = true
		_collect_child_bones(bone_index, selected_bones)


func _update_envelope(
	set_index: int,
	physics_set: AdditivePhysicsSet,
	movement_speed: float,
	grounded: bool,
	delta: float
) -> void:
	var activation_speed: float = physics_set.grounded_activation_speed if grounded else physics_set.airborne_activation_speed
	var full_speed: float = physics_set.grounded_full_speed if grounded else physics_set.airborne_full_speed
	var state_multiplier: float = physics_set.grounded_strength_multiplier if grounded else physics_set.airborne_strength_multiplier
	var target_strength: float = _get_speed_strength(movement_speed, activation_speed, full_speed)
	if physics_set.strength_curve != null:
		target_strength = physics_set.strength_curve.sample_baked(target_strength)
	target_strength = clamp(target_strength * max(state_multiplier, 0.0), 0.0, 1.0)
	target_strength *= max(physics_set.maximum_strength, 0.0)
	if target_strength > _strengths[set_index]:
		_hold_times[set_index] = max(physics_set.inactivity_hold_time, 0.0)
		_strengths[set_index] = _move_over_time(_strengths[set_index], target_strength, physics_set.rise_time, delta)
	elif target_strength > 0.0001:
		_hold_times[set_index] = max(physics_set.inactivity_hold_time, 0.0)
		_strengths[set_index] = _move_over_time(_strengths[set_index], target_strength, physics_set.decay_time, delta)
	elif _hold_times[set_index] > 0.0:
		_hold_times[set_index] = max(_hold_times[set_index] - max(delta, 0.0), 0.0)
	else:
		_strengths[set_index] = _move_over_time(_strengths[set_index], 0.0, physics_set.decay_time, delta)


func _get_movement_speed(velocity_value: Vector3, grounded: bool) -> float:
	if not grounded:
		return velocity_value.length()
	if player.has_method("_get_lateral_speed_for_anim"):
		return max(float(player.call("_get_lateral_speed_for_anim")), 0.0)
	return velocity_value.length()


func _update_animation_speed(
	set_index: int,
	physics_set: AdditivePhysicsSet,
	movement_speed: float,
	grounded: bool,
	set_allowed: bool,
	delta: float
) -> void:
	var activation_speed: float = physics_set.grounded_activation_speed if grounded else physics_set.airborne_activation_speed
	var full_speed: float = physics_set.grounded_full_speed if grounded else physics_set.airborne_full_speed
	var speed_amount: float = _get_speed_strength(movement_speed, activation_speed, full_speed) if set_allowed else 0.0
	var active: bool = speed_amount > 0.0001
	var target_speed: float = max(physics_set.inactive_animation_speed, 0.0)
	if active:
		var start_speed: float = physics_set.grounded_animation_speed_at_activation if grounded else physics_set.airborne_animation_speed_at_activation
		var full_animation_speed: float = physics_set.grounded_animation_speed_at_full if grounded else physics_set.airborne_animation_speed_at_full
		target_speed = lerp(max(start_speed, 0.0), max(full_animation_speed, 0.0), speed_amount)
		_animation_speed_hold_times[set_index] = max(physics_set.animation_speed_inactivity_hold_time, 0.0)
		var response_time: float = physics_set.animation_speed_rise_time if target_speed > _animation_speeds[set_index] else physics_set.animation_speed_falloff_time
		_animation_speeds[set_index] = _move_over_time(_animation_speeds[set_index], target_speed, response_time, delta)
	elif _animation_speed_hold_times[set_index] > 0.0:
		_animation_speed_hold_times[set_index] = max(_animation_speed_hold_times[set_index] - max(delta, 0.0), 0.0)
	else:
		_animation_speeds[set_index] = _move_over_time(
			_animation_speeds[set_index],
			target_speed,
			physics_set.animation_speed_falloff_time,
			delta
		)


func _get_speed_strength(speed: float, activation_speed: float, full_speed: float) -> float:
	var start: float = max(activation_speed, 0.0)
	var finish: float = max(full_speed, start + 0.001)
	return clamp(inverse_lerp(start, finish, max(speed, 0.0)), 0.0, 1.0)


func _move_over_time(current: float, target: float, duration: float, delta: float) -> float:
	if duration <= 0.0:
		return target
	return move_toward(current, target, max(delta, 0.0) / duration)


func _get_amount_parameter(physics_set: AdditivePhysicsSet) -> String:
	return "parameters/%s/add_amount" % physics_set.additive_node_name


func _get_time_scale_parameter(physics_set: AdditivePhysicsSet) -> String:
	return "parameters/%s/scale" % physics_set.animation_time_scale_node_name


func _cache_permission_routes() -> void:
	_permission_routes.clear()
	if animation_tree == null or animation_tree.tree_root == null or animation_resource_marker.is_empty():
		return
	_collect_permission_routes(animation_tree.tree_root, "parameters", [])


func _collect_permission_routes(node: AnimationNode, parameter_path: String, state_conditions: Array) -> void:
	if node == null:
		return
	var marker_index: int = node.resource_name.to_lower().find(animation_resource_marker.to_lower())
	if marker_index >= 0:
		_permission_routes.append({
			"conditions": state_conditions.duplicate(true),
			"settings": _parse_resource_arguments(node.resource_name, marker_index),
		})
	if node is AnimationNodeBlendTree:
		var blend_tree: AnimationNodeBlendTree = node as AnimationNodeBlendTree
		for child_name: StringName in blend_tree.get_node_list():
			_collect_permission_routes(blend_tree.get_node(child_name), parameter_path + "/" + String(child_name), state_conditions)
	elif node is AnimationNodeStateMachine:
		var state_machine: AnimationNodeStateMachine = node as AnimationNodeStateMachine
		for state_name: StringName in state_machine.get_node_list():
			var child_conditions: Array = state_conditions.duplicate(true)
			child_conditions.append({
				"playback_path": parameter_path + "/playback",
				"state_name": state_name,
			})
			_collect_permission_routes(state_machine.get_node(state_name), parameter_path + "/" + String(state_name), child_conditions)
	elif node is AnimationNodeBlendSpace1D:
		var blend_space_1d: AnimationNodeBlendSpace1D = node as AnimationNodeBlendSpace1D
		for point_index: int in range(blend_space_1d.get_blend_point_count()):
			_collect_permission_routes(blend_space_1d.get_blend_point_node(point_index), parameter_path, state_conditions)
	elif node is AnimationNodeBlendSpace2D:
		var blend_space_2d: AnimationNodeBlendSpace2D = node as AnimationNodeBlendSpace2D
		for point_index: int in range(blend_space_2d.get_blend_point_count()):
			_collect_permission_routes(blend_space_2d.get_blend_point_node(point_index), parameter_path, state_conditions)


func _parse_resource_arguments(resource_name: String, marker_index: int) -> Dictionary:
	var arguments: Dictionary = {}
	var argument_start: int = marker_index + animation_resource_marker.length()
	if argument_start >= resource_name.length():
		return arguments
	var suffix: String = resource_name.substr(argument_start).strip_edges()
	if not suffix.begins_with("-"):
		return arguments
	suffix = suffix.substr(1)
	for argument: String in suffix.split(";", false):
		var assignment: PackedStringArray = argument.split("=", true, 1)
		if assignment.size() != 2:
			continue
		var key: String = assignment[0].strip_edges().to_lower().replace("-", "_")
		var value: String = assignment[1].strip_edges().to_lower()
		arguments[key] = value in ["true", "1", "yes", "on"]
	return arguments


func _get_current_permissions() -> Dictionary:
	var permissions: Dictionary = {"enabled": true}
	for physics_set: AdditivePhysicsSet in physics_sets:
		if physics_set != null:
			permissions[String(physics_set.set_id).strip_edges().to_lower().replace("-", "_")] = true
	for route: Dictionary in _permission_routes:
		if not _is_route_active(route):
			continue
		var settings: Dictionary = route["settings"]
		for key_value: Variant in settings.keys():
			var key: String = String(key_value)
			if settings[key] == false:
				permissions[key] = false
	return permissions


func _is_route_active(route: Dictionary) -> bool:
	var conditions: Array = route["conditions"]
	for condition: Dictionary in conditions:
		var playback: AnimationNodeStateMachinePlayback = animation_tree.get(condition["playback_path"]) as AnimationNodeStateMachinePlayback
		if playback == null or playback.get_current_node() != condition["state_name"]:
			return false
	return true

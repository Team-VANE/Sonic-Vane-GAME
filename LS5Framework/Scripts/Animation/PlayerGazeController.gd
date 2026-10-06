extends Node
class_name PlayerGazeController

@export_group("Node References")
## AnimationTree whose active animation resources control gaze permission.
@export_node_path("AnimationTree") var animation_tree_path: NodePath = NodePath("../AnimationTree")
## AnimationPlayer used to resolve AnimationTree resource names and facial poses.
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = NodePath("../AnimationPlayer")
## Skeleton modifier that applies head and facial gaze transforms.
@export_node_path("SkeletonModifier3D") var gaze_modifier_path: NodePath = NodePath("../Armature/Skeleton3D/GazeTrackingModifier3D")
## Character node used for target distance checks. The nearest CharacterBody3D ancestor is used when empty.
@export_node_path("Node3D") var viewer_path: NodePath

@export_group("Animation Permission")
## Text in an AnimationTree resource Name that permits gaze tracking. Use `_gaze-enabled=true`.
@export var animation_resource_marker: String = "_gaze"

@export_group("Target Selection")
## Group containing automatic gaze targets.
@export var target_group: StringName = GazeTarget3D.GAZE_TARGET_GROUP
## Maximum viewer distance used before target-specific distance limits.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var maximum_target_distance: float = 80.0
## Delay between automatic target scans.
@export_range(0.01, 2.0, 0.01, "suffix:s") var target_scan_interval: float = 0.15
## Minimum time a same-priority target remains selected before a nearer target can replace it.
@export_range(0.0, 5.0, 0.01, "suffix:s") var same_priority_hold_time: float = 0.5

@export_group("Blending")
## Speed used to blend gaze tracking on when a permitted target is available.
@export_range(0.0, 100.0, 0.1) var acquire_speed: float = 8.0
## Speed used to blend gaze tracking off when permission or the target is lost.
@export_range(0.0, 100.0, 0.1) var release_speed: float = 6.0

@export_group("Debug View")
## Shows gaze candidates, the selected target, and gate status in the world.
@export var debug_view_enabled: bool = false
## Offset from the tracked head used for the debug status label.
@export var debug_label_offset: Vector3 = Vector3(0.0, 2.5, 0.0)
## Length of the cyan line showing the configured head-forward direction.
@export_range(0.1, 20.0, 0.1, "or_greater", "suffix:m") var debug_forward_line_length: float = 2.0

var _current_target: GazeTarget3D = null
var animation_tree: AnimationTree = null
var animation_player: AnimationPlayer = null
var gaze_modifier: GazeTrackingModifier3D = null
var viewer: Node3D = null
var _last_target_position: Vector3 = Vector3.ZERO
var _scan_time_remaining: float = 0.0
var _target_hold_remaining: float = 0.0
var _tracking_weight: float = 0.0
var _activation_routes: Array[Dictionary] = []
var _debug_group_member_count: int = 0
var _debug_valid_candidate_count: int = 0
var _debug_active_route_count: int = 0
var _debug_animation_allowed: bool = false
var _debug_candidates: Array[Dictionary] = []
var _debug_mesh_instance: MeshInstance3D = null
var _debug_mesh: ImmediateMesh = null
var _debug_line_material: StandardMaterial3D = null
var _debug_label: Label3D = null


func _ready() -> void:
	_resolve_references()
	_cache_activation_routes()
	if gaze_modifier != null:
		gaze_modifier.facial_animation_player = animation_player
	_update_debug_view()


func _process(delta: float) -> void:
	if gaze_modifier == null:
		return
	_scan_time_remaining -= max(delta, 0.0)
	_target_hold_remaining = max(_target_hold_remaining - max(delta, 0.0), 0.0)
	if _scan_time_remaining <= 0.0:
		_scan_time_remaining = max(target_scan_interval, 0.01)
		_select_target()

	var target_available: bool = _is_target_valid(_current_target)
	if target_available:
		_last_target_position = _current_target.get_gaze_position()
	var animation_allowed: bool = _is_current_animation_allowed()
	_debug_animation_allowed = animation_allowed
	var desired_weight: float = 1.0 if target_available and animation_allowed else 0.0
	var blend_speed: float = acquire_speed if desired_weight > _tracking_weight else release_speed
	if blend_speed <= 0.0:
		_tracking_weight = desired_weight
	else:
		var blend: float = 1.0 - exp(-blend_speed * max(delta, 0.0))
		_tracking_weight = lerp(_tracking_weight, desired_weight, blend)

	gaze_modifier.target_global_position = _last_target_position
	gaze_modifier.tracking_active = _tracking_weight > 0.0001
	gaze_modifier.influence = clamp(_tracking_weight, 0.0, 1.0)
	_update_debug_view()


func refresh_animation_resource_routes() -> void:
	_cache_activation_routes()


func get_current_gaze_target() -> GazeTarget3D:
	return _current_target


func set_gaze_target(target: GazeTarget3D) -> void:
	_current_target = target
	_target_hold_remaining = max(same_priority_hold_time, 0.0)
	if _is_target_valid(_current_target):
		_last_target_position = _current_target.get_gaze_position()


func clear_gaze_target() -> void:
	_current_target = null
	_target_hold_remaining = 0.0


func _resolve_references() -> void:
	animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	gaze_modifier = get_node_or_null(gaze_modifier_path) as GazeTrackingModifier3D
	if not viewer_path.is_empty():
		viewer = get_node_or_null(viewer_path) as Node3D
	if viewer == null:
		var ancestor: Node = get_parent()
		while ancestor != null:
			if ancestor is CharacterBody3D:
				viewer = ancestor as Node3D
				break
			ancestor = ancestor.get_parent()


func _cache_activation_routes() -> void:
	_activation_routes.clear()
	if animation_tree == null or animation_tree.tree_root == null or animation_resource_marker.is_empty():
		return
	_collect_activation_routes(animation_tree.tree_root, "parameters", [])


func _collect_activation_routes(node: AnimationNode, parameter_path: String, state_conditions: Array) -> void:
	if node == null:
		return
	var marker_index: int = node.resource_name.to_lower().find(animation_resource_marker.to_lower())
	if marker_index >= 0:
		_activation_routes.append({
			"conditions": state_conditions.duplicate(true),
			"settings": _parse_resource_arguments(node.resource_name, marker_index),
		})

	if node is AnimationNodeBlendTree:
		var blend_tree: AnimationNodeBlendTree = node as AnimationNodeBlendTree
		for child_name: StringName in blend_tree.get_node_list():
			_collect_activation_routes(blend_tree.get_node(child_name), parameter_path + "/" + String(child_name), state_conditions)
	elif node is AnimationNodeStateMachine:
		var state_machine: AnimationNodeStateMachine = node as AnimationNodeStateMachine
		for state_name: StringName in state_machine.get_node_list():
			var child_conditions: Array = state_conditions.duplicate(true)
			child_conditions.append({
				"playback_path": parameter_path + "/playback",
				"state_name": state_name,
			})
			_collect_activation_routes(state_machine.get_node(state_name), parameter_path + "/" + String(state_name), child_conditions)
	elif node is AnimationNodeBlendSpace1D:
		var blend_space_1d: AnimationNodeBlendSpace1D = node as AnimationNodeBlendSpace1D
		for point_index: int in range(blend_space_1d.get_blend_point_count()):
			_collect_activation_routes(blend_space_1d.get_blend_point_node(point_index), parameter_path, state_conditions)
	elif node is AnimationNodeBlendSpace2D:
		var blend_space_2d: AnimationNodeBlendSpace2D = node as AnimationNodeBlendSpace2D
		for point_index: int in range(blend_space_2d.get_blend_point_count()):
			_collect_activation_routes(blend_space_2d.get_blend_point_node(point_index), parameter_path, state_conditions)


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
		if key == "enabled":
			arguments[key] = value in ["true", "1", "yes", "on"]
	return arguments


func _select_target() -> void:
	_debug_candidates.clear()
	_debug_group_member_count = 0
	_debug_valid_candidate_count = 0
	if viewer == null or not is_instance_valid(viewer):
		_current_target = null
		return
	var best: GazeTarget3D = null
	var best_priority: int = -2147483648
	var best_distance_squared: float = INF
	var target_nodes: Array[Node] = get_tree().get_nodes_in_group(target_group)
	if target_nodes.is_empty():
		_repair_target_group(get_tree().root, target_nodes)
	for candidate_node: Node in target_nodes:
		_debug_group_member_count += 1
		var candidate: GazeTarget3D = candidate_node as GazeTarget3D
		if candidate == null:
			continue
		var rejection_reason: String = _get_target_rejection_reason(candidate)
		var candidate_valid: bool = rejection_reason.is_empty()
		_debug_candidates.append({
			"target": candidate,
			"valid": candidate_valid,
			"reason": rejection_reason,
		})
		if not candidate_valid:
			continue
		_debug_valid_candidate_count += 1
		var candidate_distance_squared: float = viewer.global_position.distance_squared_to(candidate.get_gaze_position())
		if candidate.gaze_priority > best_priority:
			best = candidate
			best_priority = candidate.gaze_priority
			best_distance_squared = candidate_distance_squared
		elif candidate.gaze_priority == best_priority and candidate_distance_squared < best_distance_squared:
			best = candidate
			best_distance_squared = candidate_distance_squared

	if best == null:
		_current_target = null
		return
	if _is_target_valid(_current_target) and _current_target.gaze_priority == best_priority and _target_hold_remaining > 0.0:
		return
	if best != _current_target:
		_current_target = best
		_target_hold_remaining = max(same_priority_hold_time, 0.0)


func _repair_target_group(node: Node, output: Array[Node]) -> void:
	if node is GazeTarget3D:
		var target: GazeTarget3D = node as GazeTarget3D
		if not target.is_in_group(target_group):
			target.add_to_group(target_group)
		output.append(target)
	for child: Node in node.get_children():
		_repair_target_group(child, output)


func _is_target_valid(target: Variant) -> bool:
	return _get_target_rejection_reason(target).is_empty()


func _get_target_rejection_reason(target: Variant) -> String:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return "not in tree"
	if not target is GazeTarget3D:
		return "invalid type"
	if target == viewer or viewer != null and viewer.is_ancestor_of(target):
		return "owned by viewer"
	if viewer == null or not is_instance_valid(viewer):
		return "viewer missing"
	if not target.gaze_enabled:
		return "disabled"
	var distance_squared: float = viewer.global_position.distance_squared_to(target.get_gaze_position())
	if target.gaze_max_distance > 0.0 and distance_squared > target.gaze_max_distance * target.gaze_max_distance:
		return "target range"
	if maximum_target_distance <= 0.0:
		return ""
	if distance_squared > maximum_target_distance * maximum_target_distance:
		return "viewer range"
	return ""


func _is_current_animation_allowed() -> bool:
	_debug_active_route_count = 0
	if animation_tree == null or not animation_tree.active:
		return false
	var allowed: bool = false
	for route: Dictionary in _activation_routes:
		var settings: Dictionary = route["settings"]
		if not _is_route_active(route):
			continue
		_debug_active_route_count += 1
		if bool(settings.get("enabled", true)):
			allowed = true
	return allowed


func _is_route_active(route: Dictionary) -> bool:
	var conditions: Array = route["conditions"]
	for condition: Dictionary in conditions:
		var playback: AnimationNodeStateMachinePlayback = animation_tree.get(condition["playback_path"]) as AnimationNodeStateMachinePlayback
		if playback == null or playback.get_current_node() != condition["state_name"]:
			return false
	return true


func _update_debug_view() -> void:
	if not debug_view_enabled:
		_set_debug_view_visible(false)
		return
	_ensure_debug_view()
	_set_debug_view_visible(true)
	if _debug_mesh == null or _debug_label == null:
		return
	var line_origin: Vector3 = viewer.global_position if viewer != null and is_instance_valid(viewer) else Vector3.ZERO
	if gaze_modifier != null and is_instance_valid(gaze_modifier):
		line_origin = gaze_modifier.get_debug_head_global_position()
	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_line_material)
	for candidate_data: Dictionary in _debug_candidates:
		var target: GazeTarget3D = candidate_data["target"] as GazeTarget3D
		if target == null or not is_instance_valid(target):
			continue
		var line_color: Color = Color(1.0, 0.2, 0.15, 1.0)
		if target == _current_target:
			line_color = Color(0.15, 1.0, 0.25, 1.0) if _debug_animation_allowed else Color(1.0, 0.25, 1.0, 1.0)
		elif bool(candidate_data["valid"]):
			line_color = Color(1.0, 0.75, 0.1, 1.0)
		_add_debug_line(line_origin, target.get_gaze_position(), line_color)
	if gaze_modifier != null and is_instance_valid(gaze_modifier):
		var head_forward: Vector3 = gaze_modifier.get_debug_head_forward_global()
		if head_forward.length_squared() > 0.0001:
			_add_debug_line(line_origin, line_origin + head_forward * debug_forward_line_length, Color(0.1, 0.9, 1.0, 1.0))
	_add_debug_line(line_origin, line_origin + Vector3.UP * 0.25, Color(0.7, 0.3, 1.0, 1.0))
	_debug_mesh.surface_end()
	_debug_label.global_position = line_origin + debug_label_offset
	_debug_label.text = _build_debug_status()


func _ensure_debug_view() -> void:
	if _debug_mesh_instance != null and is_instance_valid(_debug_mesh_instance):
		return
	_debug_line_material = StandardMaterial3D.new()
	_debug_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_line_material.vertex_color_use_as_albedo = true
	_debug_line_material.no_depth_test = true
	_debug_mesh = ImmediateMesh.new()
	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.name = "GazeDebugLines"
	_debug_mesh_instance.mesh = _debug_mesh
	_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_debug_mesh_instance)
	_debug_mesh_instance.top_level = true
	_debug_mesh_instance.global_transform = Transform3D.IDENTITY
	_debug_label = Label3D.new()
	_debug_label.name = "GazeDebugStatus"
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.fixed_size = true
	_debug_label.font_size = 16
	_debug_label.outline_size = 4
	_debug_label.pixel_size = 0.001
	_debug_label.modulate = Color(0.9, 1.0, 0.9, 1.0)
	add_child(_debug_label)
	_debug_label.top_level = true


func _set_debug_view_visible(visible_state: bool) -> void:
	if _debug_mesh_instance != null and is_instance_valid(_debug_mesh_instance):
		_debug_mesh_instance.visible = visible_state
	if _debug_label != null and is_instance_valid(_debug_label):
		_debug_label.visible = visible_state


func _add_debug_line(start_point: Vector3, end_point: Vector3, color: Color) -> void:
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(start_point)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(end_point)


func _build_debug_status() -> String:
	var target_name: String = "none"
	if _current_target != null and is_instance_valid(_current_target):
		target_name = _current_target.name
	var head_valid: bool = gaze_modifier != null and is_instance_valid(gaze_modifier) and gaze_modifier.has_valid_head_bone()
	var absolute_count: int = gaze_modifier.get_debug_absolute_eye_bone_count() if gaze_modifier != null and is_instance_valid(gaze_modifier) else 0
	var additive_count: int = gaze_modifier.get_debug_additive_face_bone_count() if gaze_modifier != null and is_instance_valid(gaze_modifier) else 0
	var pose_counts: PackedInt32Array = gaze_modifier.get_debug_directional_pose_counts() if gaze_modifier != null and is_instance_valid(gaze_modifier) else PackedInt32Array([0, 0, 0, 0, 0])
	var failure: String = _get_debug_failure_reason(head_valid)
	var tree_path: String = String(animation_tree.get_path()) if animation_tree != null else "missing"
	var tree_active: bool = animation_tree != null and animation_tree.active
	return "GAZE DEBUG\nTargets: %d group / %d valid / %s selected\n%s\nAnimation: %d routes / %d active / allowed=%s\nTree: %s active=%s\n%s\nModifier: head=%s eyes=%d additive=%d poses=%d/%d/%d/%d/%d influence=%.3f\n%s" % [
		_debug_group_member_count,
		_debug_valid_candidate_count,
		target_name,
		_build_debug_candidate_details(),
		_activation_routes.size(),
		_debug_active_route_count,
		str(_debug_animation_allowed),
		tree_path,
		str(tree_active),
		_build_debug_route_details(),
		str(head_valid),
		absolute_count,
		additive_count,
		pose_counts[0],
		pose_counts[1],
		pose_counts[2],
		pose_counts[3],
		pose_counts[4],
		_tracking_weight,
		failure,
	]


func _build_debug_candidate_details() -> String:
	if _debug_candidates.is_empty():
		return "Candidates: none"
	var details: PackedStringArray = PackedStringArray()
	var detail_count: int = mini(_debug_candidates.size(), 3)
	for candidate_index: int in range(detail_count):
		var candidate_data: Dictionary = _debug_candidates[candidate_index]
		var target: GazeTarget3D = candidate_data["target"] as GazeTarget3D
		if target == null or not is_instance_valid(target):
			continue
		var distance: float = viewer.global_position.distance_to(target.get_gaze_position()) if viewer != null else 0.0
		var state: String = "valid" if bool(candidate_data["valid"]) else String(candidate_data["reason"])
		details.append("%s %.1fm (%s)" % [target.name, distance, state])
	return "Candidates: " + ", ".join(details)


func _build_debug_route_details() -> String:
	if animation_tree == null or _activation_routes.is_empty():
		return "Route states: none"
	var details: PackedStringArray = PackedStringArray()
	var seen_paths: Dictionary = {}
	for route: Dictionary in _activation_routes:
		var conditions: Array = route["conditions"]
		for condition: Dictionary in conditions:
			var playback_path: String = String(condition["playback_path"])
			if seen_paths.has(playback_path):
				continue
			seen_paths[playback_path] = true
			var playback: AnimationNodeStateMachinePlayback = animation_tree.get(playback_path) as AnimationNodeStateMachinePlayback
			var current_state: String = String(playback.get_current_node()) if playback != null else "missing"
			details.append("%s=%s" % [playback_path.trim_prefix("parameters/"), current_state])
			if details.size() >= 4:
				return "Route states: " + ", ".join(details)
	if details.is_empty():
		return "Route states: no state conditions"
	return "Route states: " + ", ".join(details)


func _get_debug_failure_reason(head_valid: bool) -> String:
	if animation_tree == null:
		return "BLOCKED: AnimationTree reference missing"
	if gaze_modifier == null:
		return "BLOCKED: modifier reference missing"
	if viewer == null:
		return "BLOCKED: viewer reference missing"
	if _debug_group_member_count <= 0:
		return "BLOCKED: gaze_targets group is empty"
	if _debug_valid_candidate_count <= 0:
		return "BLOCKED: all candidates rejected; see reasons above"
	if _current_target == null:
		return "BLOCKED: no target selected"
	if _activation_routes.is_empty():
		return "BLOCKED: no _gaze resources cached"
	if not _debug_animation_allowed:
		return "BLOCKED: no marked route is active"
	if not head_valid:
		return "BLOCKED: head bone was not found"
	return "ACTIVE: green=selected yellow=valid red=rejected cyan=head forward"

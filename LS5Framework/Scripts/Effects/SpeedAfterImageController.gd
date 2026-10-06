extends Node
class_name SpeedAfterImageController

## AnimationTree inspected for animation resources whose names contain the activation marker.
@export_node_path("AnimationTree") var animation_tree_path: NodePath = NodePath("../AnimationTree")
## Player pawn that supplies tangential speed. Leave empty to use the nearest ancestor CharacterBody3D.
@export var player_pawn: CharacterBody3D
## Shader material resource name used to find the after-image surfaces under this node's parent.
@export var material_resource_name: StringName = &"FootAfterImage"
## Distinct text in an animation resource name that enables the effect. Arguments use _afterimage-speed=true;min_speed=80;max_speed=165;min_alpha=0;max_alpha=0.765.
@export var animation_resource_marker: String = "_afterimage"
## Default tangential speed where speed-gated alpha begins increasing.
@export_range(0.0, 1000.0, 0.1, "or_greater") var minimum_speed: float = 45.0
## Default tangential speed where speed-gated alpha reaches maximum_alpha.
@export_range(0.0, 1000.0, 0.1, "or_greater") var maximum_speed: float = 165.0
## Default alpha used at and below minimum_speed when speed gating is enabled.
@export_range(0.0, 1.0, 0.001) var minimum_alpha: float = 0.0
## Default maximum alpha, also used by marked resources without speed=true.
@export_range(0.0, 1.0, 0.001) var maximum_alpha: float = 0.765

const ALPHA_PARAMETER: StringName = &"afterimage_alpha"

var _animation_tree: AnimationTree
var _player: CharacterBody3D
var _surfaces: Array[Dictionary] = []
var _activation_routes: Array[Dictionary] = []


func _ready() -> void:
	_animation_tree = get_node_or_null(animation_tree_path) as AnimationTree
	_player = _resolve_player()
	_collect_afterimage_materials(get_parent())
	_cache_activation_routes()
	_set_alpha(0.0)


func _process(_delta: float) -> void:
	_set_alpha(_get_target_alpha())


func _resolve_player() -> CharacterBody3D:
	if player_pawn:
		return player_pawn
	var ancestor: Node = get_parent()
	while ancestor:
		if ancestor is CharacterBody3D:
			return ancestor as CharacterBody3D
		ancestor = ancestor.get_parent()
	return null


func _collect_afterimage_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh_instance: MeshInstance3D = root as MeshInstance3D
		for surface_index: int in range(mesh_instance.get_surface_override_material_count()):
			var material: Material = mesh_instance.get_active_material(surface_index)
			if material and StringName(material.resource_name) == material_resource_name:
				var instance_material: Material = material.duplicate() as Material
				instance_material.set_meta(&"character_color_source_material", material)
				mesh_instance.set_surface_override_material(surface_index, instance_material)
				_surfaces.append({
					"mesh_instance": mesh_instance,
					"surface_index": surface_index,
				})
	for child: Node in root.get_children():
		_collect_afterimage_materials(child)


func _cache_activation_routes() -> void:
	_activation_routes.clear()
	if _animation_tree == null or _animation_tree.tree_root == null or animation_resource_marker.is_empty():
		return
	_collect_activation_routes(_animation_tree.tree_root, "parameters", [])


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
			_collect_activation_routes(
				blend_tree.get_node(child_name),
				parameter_path + "/" + String(child_name),
				state_conditions
			)
	elif node is AnimationNodeStateMachine:
		var state_machine: AnimationNodeStateMachine = node as AnimationNodeStateMachine
		for state_name: StringName in state_machine.get_node_list():
			var child_conditions: Array = state_conditions.duplicate(true)
			child_conditions.append({
				"playback_path": parameter_path + "/playback",
				"state_name": state_name,
			})
			_collect_activation_routes(
				state_machine.get_node(state_name),
				parameter_path + "/" + String(state_name),
				child_conditions
			)
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
		if key == "speed":
			arguments[key] = value in ["true", "1", "yes", "on"]
		elif key in ["min_speed", "max_speed", "min_alpha", "max_alpha"] and value.is_valid_float():
			arguments[key] = value.to_float()
	return arguments


func _get_target_alpha() -> float:
	if _animation_tree == null or not _animation_tree.active:
		return 0.0
	var target_alpha: float = 0.0
	for route: Dictionary in _activation_routes:
		if not _is_route_active(route):
			continue
		var settings: Dictionary = route["settings"]
		var route_max_alpha: float = float(settings.get("max_alpha", maximum_alpha))
		var route_alpha: float = route_max_alpha
		if bool(settings.get("speed", false)):
			var route_min_speed: float = float(settings.get("min_speed", minimum_speed))
			var route_max_speed: float = float(settings.get("max_speed", maximum_speed))
			var route_min_alpha: float = float(settings.get("min_alpha", minimum_alpha))
			var speed_range: float = maxf(route_max_speed - route_min_speed, 0.001)
			var speed_ratio: float = clampf((_get_tangential_speed() - route_min_speed) / speed_range, 0.0, 1.0)
			route_alpha = lerpf(route_min_alpha, route_max_alpha, speed_ratio)
		target_alpha = maxf(target_alpha, route_alpha)
	return clampf(target_alpha, 0.0, 1.0)


func _is_route_active(route: Dictionary) -> bool:
	var conditions: Array = route["conditions"]
	for condition: Dictionary in conditions:
		var playback: AnimationNodeStateMachinePlayback = _animation_tree.get(condition["playback_path"]) as AnimationNodeStateMachinePlayback
		if playback == null or playback.get_current_node() != condition["state_name"]:
			return false
	return true


func _get_tangential_speed() -> float:
	if _player == null:
		return 0.0
	if _player.has_method("get_player_relative_horizontal_speed"):
		return absf(float(_player.call("get_player_relative_horizontal_speed")))
	return _player.velocity.slide(_player.up_direction).length()


func _set_alpha(alpha: float) -> void:
	var clamped_alpha: float = clampf(alpha, 0.0, 1.0)
	for surface: Dictionary in _surfaces:
		var mesh_instance: MeshInstance3D = surface.get("mesh_instance") as MeshInstance3D
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		var surface_index: int = int(surface.get("surface_index", -1))
		if surface_index < 0 or surface_index >= mesh_instance.get_surface_override_material_count():
			continue
		var material: Material = mesh_instance.get_active_material(surface_index)
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(ALPHA_PARAMETER, clamped_alpha)
		elif material is BaseMaterial3D:
			var base_material: BaseMaterial3D = material as BaseMaterial3D
			var albedo: Color = base_material.albedo_color
			albedo.a = clamped_alpha
			base_material.albedo_color = albedo

extends RefCounted

const PREFIX: StringName = &"ls5_camera_edit"
const TRAIT_SCRIPTS: Array[String] = [
	"res://LS5Framework/Scripts/Camera/Constraints/CameraActivationTrait.gd",
	"res://LS5Framework/Scripts/Camera/Constraints/CameraPositionTrait.gd",
	"res://LS5Framework/Scripts/Camera/Constraints/CameraOrientationTrait.gd",
	"res://LS5Framework/Scripts/Camera/Constraints/CameraLensTrait.gd",
	"res://LS5Framework/Scripts/Camera/Constraints/CameraTransitionTrait.gd",
	"res://LS5Framework/Scripts/Camera/Constraints/CameraInfluenceTrait.gd",
]


static func capture(message: String, data: Array) -> bool:
	if message != "configuration" or data.size() != 3:
		return false
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return true
	for constraint: Node in tree.get_nodes_in_group(&"LiveCameraConstraints"):
		var ancestor: Node = constraint
		while ancestor and ancestor != tree.root:
			if ancestor.scene_file_path == String(data[0]) and ancestor.get_path_to(constraint) == NodePath(data[1]):
				apply_snapshot(constraint, data[2])
				break
			ancestor = ancestor.get_parent()
	return true


static func encode(value: Variant) -> Variant:
	if value is Resource:
		var resource: Resource = value
		var script: Script = resource.get_script() as Script
		if not script or not TRAIT_SCRIPTS.has(script.resource_path):
			return null
		var properties: Dictionary = {}
		for property: Dictionary in script.get_script_property_list():
			if int(property.usage) & PROPERTY_USAGE_EDITOR and int(property.usage) & PROPERTY_USAGE_STORAGE:
				properties[property.name] = encode(resource.get(property.name))
		return {"trait_script": script.resource_path, "properties": properties}
	if value is Array:
		var values: Array = []
		for item: Variant in value:
			values.append(encode(item))
		return values
	return value if not value is Object else null


static func decode(value: Variant) -> Variant:
	if value is Dictionary and value.has("trait_script"):
		var path: String = String(value.trait_script)
		if not TRAIT_SCRIPTS.has(path):
			return null
		var script: Script = load(path) as Script
		var resource: Resource = script.new()
		apply_properties(resource, value.properties)
		return resource
	if value is Array:
		var values: Array = []
		for item: Variant in value:
			values.append(decode(item))
		return values
	return value


static func apply_properties(object: Object, properties: Dictionary) -> void:
	for property: Variant in properties:
		var value: Variant = decode(properties[property])
		var current: Variant = object.get(property)
		if current is Array and value is Array:
			var typed_values: Array = current.duplicate()
			typed_values.assign(value)
			object.set(property, typed_values)
		else:
			object.set(property, value)


static func snapshot(constraint: Node3D) -> Dictionary:
	var properties: Dictionary = {}
	var script: Script = constraint.get_script() as Script
	for property: Dictionary in script.get_script_property_list():
		if int(property.usage) & PROPERTY_USAGE_EDITOR and int(property.usage) & PROPERTY_USAGE_STORAGE:
			properties[property.name] = encode(constraint.get(property.name))
	var children: Dictionary = {}
	_collect_children(constraint, constraint, children)
	var state: Dictionary = {"properties": properties, "transform": constraint.transform, "children": children}
	var area: Area3D = (constraint as Node) as Area3D
	if area:
		state["area_properties"] = {"collision_layer": area.collision_layer, "collision_mask": area.collision_mask}
	return state


static func _collect_children(root: Node3D, node: Node, children: Dictionary) -> void:
	for child: Node in node.get_children():
		if child is Node3D:
			var state: Dictionary = {"transform": (child as Node3D).transform}
			if child is Area3D:
				state["area_properties"] = {"collision_layer": child.collision_layer, "collision_mask": child.collision_mask}
			if child is Path3D and (child as Path3D).curve:
				var curve: Curve3D = (child as Path3D).curve
				var points: Array[Dictionary] = []
				for index: int in range(curve.point_count):
					points.append({"position": curve.get_point_position(index), "in": curve.get_point_in(index), "out": curve.get_point_out(index), "tilt": curve.get_point_tilt(index)})
				state["curve"] = {"points": points, "bake_interval": curve.bake_interval, "closed": curve.closed}
			if child is CollisionShape3D:
				var shape: Shape3D = (child as CollisionShape3D).shape
				if shape:
					var shape_values: Dictionary = {}
					for property: Dictionary in shape.get_property_list():
						if int(property.usage) & PROPERTY_USAGE_EDITOR and int(property.usage) & PROPERTY_USAGE_STORAGE and not property.name in ["resource_name", "resource_local_to_scene", "script"]:
							shape_values[property.name] = shape.get(property.name)
					state["shape_class"] = shape.get_class()
					state["shape_properties"] = shape_values
				state["disabled"] = (child as CollisionShape3D).disabled
			children[root.get_path_to(child)] = state
		_collect_children(root, child, children)


static func apply_snapshot(constraint: Node3D, state: Dictionary) -> void:
	var activation_changed: bool = encode(constraint.get("activation_traits")) != state.properties.get("activation_traits", [])
	apply_properties(constraint, state.properties)
	constraint.transform = state.transform
	if state.has("area_properties"):
		apply_properties(constraint, state.area_properties)
	for path: Variant in state.children:
		var child: Node3D = constraint.get_node_or_null(NodePath(path)) as Node3D
		if not child:
			continue
		var child_state: Dictionary = state.children[path]
		child.transform = child_state.transform
		if child is Area3D and child_state.has("area_properties"):
			apply_properties(child, child_state.area_properties)
		if child is Path3D and child_state.has("curve"):
			var curve: Curve3D = Curve3D.new()
			curve.bake_interval = child_state.curve.bake_interval
			curve.closed = child_state.curve.closed
			for point: Dictionary in child_state.curve.points:
				curve.add_point(point.position, point["in"], point.out)
				curve.set_point_tilt(curve.point_count - 1, point.tilt)
			(child as Path3D).curve = curve
		if child is CollisionShape3D:
			if child_state.has("shape_class") and ClassDB.is_parent_class(child_state.shape_class, "Shape3D"):
				var shape: Shape3D = ClassDB.instantiate(child_state.shape_class) as Shape3D
				apply_properties(shape, child_state.shape_properties)
				(child as CollisionShape3D).shape = shape
			(child as CollisionShape3D).set_deferred("disabled", child_state.disabled)
	constraint.call("refresh_live_configuration", activation_changed)

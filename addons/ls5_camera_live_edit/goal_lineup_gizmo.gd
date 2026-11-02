@tool
extends EditorNode3DGizmoPlugin


func _init() -> void:
	create_material("forward", Color(0.2, 0.85, 1.0))
	create_material("camera", Color(1.0, 0.7, 0.2))


func _get_gizmo_name() -> String:
	return "Goal marker directions"


func _has_gizmo(node: Node3D) -> bool:
	return _marker_role(node) != &""


func _marker_role(node: Node3D) -> StringName:
	var ancestor: Node = node.get_parent()
	while ancestor:
		var script: Script = ancestor.get_script() as Script
		if script and script.resource_path == "res://LS5Framework/Objects/Race/RaceGoal.gd":
			if ancestor.get_node_or_null(ancestor.get("goal_camera_point_path")) == node:
				return &"camera"
			if ancestor.get_node_or_null(ancestor.get("goal_pose_path")) == node:
				return &"forward"
			return &""
		ancestor = ancestor.get_parent()
	return &""


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var points: PackedVector3Array = PackedVector3Array([
		Vector3.ZERO, Vector3(0.0, 0.0, -10.0),
		Vector3(0.0, 0.0, -10.0), Vector3(-2.5, 0.0, -7.0),
		Vector3(0.0, 0.0, -10.0), Vector3(2.5, 0.0, -7.0),
		Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0),
	])
	var role: StringName = _marker_role(gizmo.get_node_3d())
	if role == &"camera":
		var corners: PackedVector3Array = PackedVector3Array([
			Vector3(-3.0, -2.0, -4.0), Vector3(3.0, -2.0, -4.0),
			Vector3(3.0, 2.0, -4.0), Vector3(-3.0, 2.0, -4.0),
		])
		for index: int in corners.size():
			points.append_array(PackedVector3Array([
				Vector3.ZERO, corners[index], corners[index], corners[(index + 1) % corners.size()],
			]))
	gizmo.add_lines(points, get_material(String(role), gizmo))
	gizmo.add_collision_segments(points)

extends RefCounted
class_name RaceObjectStateController

const FALSE_WHILE_DISABLED: PackedStringArray = [
	"visible",
	"active",
	"enabled",
	"monitoring",
	"monitorable",
	"input_ray_pickable",
	"emitting",
	"avoidance_enabled",
	"current",
	"use_collision",
]
const TRUE_WHILE_DISABLED: PackedStringArray = [
	"disabled",
	"freeze",
]
const ZERO_WHILE_DISABLED: PackedStringArray = [
	"collision_layer",
	"collision_mask",
]
const NULL_WHILE_DISABLED: PackedStringArray = [
	"environment",
	"camera_attributes",
	"compositor",
]


static func set_tree_enabled(root: Node, is_enabled: bool, state: Dictionary) -> void:
	if root == null or not is_instance_valid(root):
		return
	_capture_missing_nodes(root, state)
	var records_value = state.get("records", [])
	if not (records_value is Array):
		return
	var records: Array = records_value
	if is_enabled:
		for record_value in records:
			if record_value is Dictionary:
				_restore_record(record_value)
	else:
		for record_value in records:
			if record_value is Dictionary:
				_disable_record(record_value)
	state["enabled"] = is_enabled


static func _capture_missing_nodes(root: Node, state: Dictionary) -> void:
	var records: Array = []
	var known_ids: Dictionary = {}
	var existing_records_value = state.get("records", [])
	if existing_records_value is Array:
		for record_value in existing_records_value:
			if not (record_value is Dictionary):
				continue
			var record: Dictionary = record_value
			var node_value = record.get("node", null)
			if node_value is Node and is_instance_valid(node_value):
				records.append(record)
				known_ids[(node_value as Node).get_instance_id()] = true
	_capture_node_recursive(root, records, known_ids)
	state["records"] = records


static func _capture_node_recursive(node: Node, records: Array, known_ids: Dictionary) -> void:
	var instance_id: int = node.get_instance_id()
	if not known_ids.has(instance_id):
		records.append(_capture_record(node))
		known_ids[instance_id] = true
	for child in node.get_children():
		if child is Node:
			_capture_node_recursive(child, records, known_ids)


static func _capture_record(node: Node) -> Dictionary:
	var property_state: Dictionary = {}
	for property_name in FALSE_WHILE_DISABLED:
		_capture_property(node, property_name, property_state)
	for property_name in TRUE_WHILE_DISABLED:
		_capture_property(node, property_name, property_state)
	for property_name in ZERO_WHILE_DISABLED:
		_capture_property(node, property_name, property_state)
	for property_name in NULL_WHILE_DISABLED:
		_capture_property(node, property_name, property_state)
	var audio_state: Dictionary = {}
	if _is_audio_player(node):
		audio_state = {
			"was_playing": bool(node.call("is_playing")),
			"position": float(node.call("get_playback_position")),
		}
	return {
		"node": node,
		"process_mode": int(node.process_mode),
		"properties": property_state,
		"audio": audio_state,
	}


static func _capture_property(
		node: Node,
		property_name: String,
		property_state: Dictionary
	) -> void:
	if _has_property(node, property_name):
		property_state[property_name] = node.get(property_name)


static func _disable_record(record: Dictionary) -> void:
	var node_value = record.get("node", null)
	if not (node_value is Node) or not is_instance_valid(node_value):
		return
	var node: Node = node_value
	if node.has_method("set_race_object_enabled"):
		node.call("set_race_object_enabled", false)
	if _is_audio_player(node):
		node.call("stop")
	for property_name in FALSE_WHILE_DISABLED:
		if _has_property(node, property_name):
			node.set(property_name, false)
	for property_name in TRUE_WHILE_DISABLED:
		if _has_property(node, property_name):
			node.set(property_name, true)
	for property_name in ZERO_WHILE_DISABLED:
		if _has_property(node, property_name):
			node.set(property_name, 0)
	for property_name in NULL_WHILE_DISABLED:
		if _has_property(node, property_name):
			node.set(property_name, null)
	node.process_mode = Node.PROCESS_MODE_DISABLED


static func _restore_record(record: Dictionary) -> void:
	var node_value = record.get("node", null)
	if not (node_value is Node) or not is_instance_valid(node_value):
		return
	var node: Node = node_value
	node.process_mode = int(record.get("process_mode", Node.PROCESS_MODE_INHERIT))
	var properties_value = record.get("properties", {})
	if properties_value is Dictionary:
		var properties: Dictionary = properties_value
		for property_name in properties.keys():
			if _has_property(node, String(property_name)):
				node.set(String(property_name), properties[property_name])
	if node.has_method("set_race_object_enabled"):
		node.call("set_race_object_enabled", true)
	var audio_value = record.get("audio", {})
	if audio_value is Dictionary and not (audio_value as Dictionary).is_empty():
		var audio_state: Dictionary = audio_value
		if bool(audio_state.get("was_playing", false)) and _is_audio_player(node):
			node.call("play", max(float(audio_state.get("position", 0.0)), 0.0))


static func _is_audio_player(node: Node) -> bool:
	return (
		node.has_method("is_playing")
		and node.has_method("get_playback_position")
		and node.has_method("play")
		and node.has_method("stop")
		and _has_property(node, "stream")
	)


static func _has_property(object: Object, property_name: String) -> bool:
	for property_data in object.get_property_list():
		if property_data is Dictionary and String(property_data.get("name", "")) == property_name:
			return true
	return false

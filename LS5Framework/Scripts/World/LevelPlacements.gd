extends RefCounted

const CATALOG_PATH: String = "res://_blender/sonic_vane_placements/catalog.json"
const SCHEMA_VERSION: int = 1
const ROOT_NAME: StringName = &"LevelPlacements"
const ID_META: StringName = &"placement_id"


static func read(path: String, level_id: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"error": "Placement file could not be opened: %s" % path}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"error": "%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	var document: Variant = json.data
	if not document is Dictionary or document.get("schema_version") != SCHEMA_VERSION:
		return {"error": "Unsupported placement schema in %s" % path}
	if level_id.is_empty() or document.get("level_id") != level_id:
		return {"error": "%s has level ID %s, expected %s." % [path, document.get("level_id"), level_id]}
	var records: Variant = document.get("placements")
	if not records is Array:
		return {"error": "Missing placements array in %s" % path}

	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not catalog is Dictionary or catalog.get("schema_version") != SCHEMA_VERSION or not catalog.get("types") is Dictionary:
		return {"error": "Could not read the placement object catalog: %s" % CATALOG_PATH}
	var object_types: Dictionary = catalog["types"]
	var uuid_pattern: RegEx = RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	var seen_ids: Dictionary = {}
	var placements: Array[Dictionary] = []
	for index: int in records.size():
		var record: Variant = records[index]
		var location: String = "%s placements[%d]" % [path, index]
		if not record is Dictionary:
			return {"error": "%s must be an object." % location}
		var raw_id: Variant = record.get("id")
		var id: String = raw_id.to_lower() if raw_id is String else ""
		if not uuid_pattern.search(id):
			return {"error": "%s has an invalid UUID." % location}
		if seen_ids.has(id):
			return {"error": "%s repeats placement UUID %s." % [location, id]}
		seen_ids[id] = true

		var type: Variant = record.get("type")
		if not type is String or not object_types.has(type):
			return {"error": "%s has an unknown object type: %s." % [location, type]}
		var definition: Dictionary = object_types[type]
		var scene_path: String = definition["scene"]
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			return {"error": "%s requires an unavailable scene: %s." % [location, scene_path]}
		var position_values: Variant = record.get("position")
		var rotation_values: Variant = record.get("rotation")
		if not _is_finite_array(position_values, 3) or not _is_finite_array(rotation_values, 4):
			return {"error": "%s has an invalid position or rotation." % location}
		var position: Vector3 = Vector3(position_values[0], position_values[1], position_values[2])
		var rotation: Quaternion = Quaternion(
			rotation_values[0], rotation_values[1], rotation_values[2], rotation_values[3]
		)
		if not position.is_finite() or not rotation.is_finite() or not is_finite(rotation.length_squared()) or is_zero_approx(rotation.length_squared()):
			return {"error": "%s has an invalid transform." % location}

		var properties: Variant = record.get("properties", {})
		if not properties is Dictionary:
			return {"error": "%s properties must be an object." % location}
		var fields: Dictionary = definition["properties"]
		var overrides: Array[Dictionary] = []
		var markers: Array[Dictionary] = []
		for key: String in properties:
			if not fields.has(key):
				return {"error": "%s has an unknown property: %s." % [location, key]}
			var field: Dictionary = fields[key]
			var value: Variant = _decode_property(properties[key], field)
			if value == null:
				return {"error": "%s has an invalid value for %s." % [location, key]}
			if field["type"] == "local_offset":
				markers.append({"target": field["marker"], "position": value})
			else:
				overrides.append({"name": key, "value": value})

		placements.append({
			"id": id,
			"transform": Transform3D(Basis(rotation.normalized()), position),
			"scene_path": scene_path,
			"overrides": overrides,
			"markers": markers,
		})
	return {"placements": placements}


static func add_proxies(level_root: Node, placements: Array[Dictionary]) -> void:
	if placements.is_empty():
		return
	var container: Node3D = Node3D.new()
	container.name = ROOT_NAME
	level_root.add_child(container, true)
	for placement: Dictionary in placements:
		var id: String = placement["id"]
		var holder: Node3D = Node3D.new()
		holder.name = "Placement_" + id
		holder.transform = placement["transform"]
		holder.set_meta(ID_META, id)
		container.add_child(holder)

		var proxy: LevelObjectProxy = LevelObjectProxy.new()
		proxy.name = "Object_" + id
		proxy.target_scene_path = placement["scene_path"]
		proxy.spawn_parent_path = level_root.get_path_to(holder)
		proxy.property_overrides = placement["overrides"]
		for entry: Dictionary in placement.get("markers", []):
			var marker: Marker3D = Marker3D.new()
			marker.name = "Marker_%d" % proxy.get_child_count()
			marker.position = entry["position"]
			proxy.add_child(marker)
			proxy.transform_copies.append({"from": NodePath(marker.name), "to": NodePath(entry["target"])})
		container.add_child(proxy)


static func _decode_property(raw: Variant, field: Dictionary) -> Variant:
	match field["type"]:
		"bool":
			return raw if raw is bool else null
		"enum":
			var options: Dictionary = field["options"]
			if raw is String and options.has(raw):
				return int(options[raw]["value"])
		"float":
			if _is_finite_number(raw):
				var value: float = float(raw)
				if value >= float(field["min"]) and value <= float(field.get("max", INF)):
					return value
		"local_offset":
			if _is_finite_array(raw, 3):
				var offset: Vector3 = Vector3(raw[0], raw[1], raw[2])
				if offset.is_finite():
					return offset
	return null


static func _is_finite_array(value: Variant, size: int) -> bool:
	if not value is Array or value.size() != size:
		return false
	for component: Variant in value:
		if not _is_finite_number(component):
			return false
	return true


static func _is_finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

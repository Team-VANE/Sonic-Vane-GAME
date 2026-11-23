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
	var environment: Dictionary = _decode_environment(document.get("environment", {}), catalog.get("environment", {}))
	if environment.has("error"):
		return {"error": "%s environment: %s" % [path, environment["error"]]}
	var object_types: Dictionary = catalog["types"]
	var variants: Dictionary = catalog.get("variants", {})
	var variant_defaults: Variant = document.get("variant_defaults", {})
	if not variant_defaults is Dictionary:
		return {"error": "Variant defaults must be an object in %s." % path}
	for family: String in variant_defaults:
		var default_id: Variant = variant_defaults[family]
		if not default_id is String or not variants.get(family, {}).has(default_id):
			return {"error": "%s has an unknown default variant for %s: %s." % [path, family, default_id]}
	var uuid_pattern: RegEx = RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	var types_by_id: Dictionary = {}
	var placements: Array[Dictionary] = []
	var has_player_spawn: bool = false
	var race_placements: Dictionary = {}
	for index: int in records.size():
		var record: Variant = records[index]
		var location: String = "%s placements[%d]" % [path, index]
		if not record is Dictionary:
			return {"error": "%s must be an object." % location}
		var raw_id: Variant = record.get("id")
		var id: String = raw_id.to_lower() if raw_id is String else ""
		if not uuid_pattern.search(id):
			return {"error": "%s has an invalid UUID." % location}
		if types_by_id.has(id):
			return {"error": "%s repeats placement UUID %s." % [location, id]}

		var type: Variant = record.get("type")
		if not type is String or not object_types.has(type):
			return {"error": "%s has an unknown object type: %s." % [location, type]}
		if type == "player_spawn":
			if has_player_spawn:
				return {"error": "%s contains more than one Player Spawn." % path}
			has_player_spawn = true
		types_by_id[id] = type
		var definition: Dictionary = object_types[type]
		var scene_path: String = definition["scene"]
		var variant_family: String = definition.get("variant_family", type)
		var variant_id: Variant = record.get(
			"variant", variant_defaults.get(variant_family, definition.get("default_variant", ""))
		)
		var variant_scene: String = ""
		if record.has("variant") or variant_id != "":
			var family_variants: Dictionary = variants.get(variant_family, {})
			if not variant_id is String or not family_variants.has(variant_id):
				return {"error": "%s has an unknown %s variant: %s." % [location, variant_family, variant_id]}
			variant_scene = family_variants[variant_id]["scene"]
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
		var automation_preset: String = str(properties.get("automation_preset", "soft_route"))
		var overrides: Array[Dictionary] = []
		var markers: Array[Dictionary] = []
		for key: String in properties:
			if not fields.has(key):
				return {"error": "%s has an unknown property: %s." % [location, key]}
			var field: Dictionary = fields[key]
			if type == "environment_transition" and field.get("authoring_only", false):
				return {"error": "%s has an editor-only property: %s." % [location, key]}
			if field.has("environment_preset"):
				var id_value: Variant = properties[key]
				var preset_field: Dictionary = catalog["environment"][field["environment_preset"]]
				var option: Dictionary = preset_field["options"].get(id_value, {}) if id_value is String else {}
				var preset_path: String = option.get("path", "")
				if preset_path.is_empty() or not ResourceLoader.exists(preset_path):
					return {"error": "%s has an invalid environment preset for %s." % [location, key]}
				if field["environment_preset"] == "starting_weather":
					if environment.has("allowed_weather") and not environment["allowed_weather"].has(preset_path):
						return {"error": "%s uses a weather preset outside the level's allowed list." % location}
					overrides.append({"name": field["target_property"], "value": StringName(id_value)})
				else:
					overrides.append({"name": field["target_property"], "value": preset_path, "value_type": "resource_path"})
				continue
			if field.has("for_variants") and not field["for_variants"].has(variant_id):
				return {"error": "%s property %s is unavailable for variant %s." % [location, key, variant_id]}
			var value: Variant = _decode_property(properties[key], field)
			if value == null:
				return {"error": "%s has an invalid value for %s." % [location, key]}
			if type == "camera_constraint" and field.get("camera_shot", false):
				continue
			if type == "surface_behavior" and field.has("surface_trait"):
				continue
			var option: Dictionary = field.get("options", {}).get(properties[key], {}) if field["type"] == "enum" else {}
			if option.has("scene"):
				scene_path = option["scene"]
			elif field["type"] == "local_offset":
				markers.append({"target": field["marker"], "position": value})
			elif field.get("placement_box", false):
				var box: BoxShape3D = BoxShape3D.new()
				box.size = value
				overrides.append({"name": "shape", "target_node": field.get("target_node", "CollisionShape3D"), "value": box})
			else:
				var property_override: Dictionary = {"name": field.get("target_property", key), "value": value}
				if field.has("target_node"):
					property_override["target_node"] = field["target_node"]
				if field.has("trait_targets"):
					var trait_targets: Dictionary = field["trait_targets"]
					if not trait_targets.has(automation_preset):
						return {"error": "%s property %s is unavailable for preset %s." % [location, key, automation_preset]}
					property_override["target_trait"] = trait_targets[automation_preset]
				overrides.append(property_override)

		if not variant_scene.is_empty():
			var variant_scene_property: String = definition.get("variant_scene_property", "")
			if variant_scene_property.is_empty():
				scene_path = variant_scene
			else:
				if not ResourceLoader.exists(variant_scene, "PackedScene"):
					return {"error": "%s requires an unavailable variant scene: %s." % [location, variant_scene]}
				overrides.append({
					"name": variant_scene_property,
					"value": variant_scene,
					"value_type": "resource_path",
				})
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			return {"error": "%s requires an unavailable scene: %s." % [location, scene_path]}
		var presentation: Variant = record.get("presentation", {})
		if not presentation is Dictionary or not presentation.get("hidden", false) is bool or not presentation.get("muted", false) is bool:
			return {"error": "%s has invalid presentation settings." % location}
		var placement: Dictionary = {
			"id": id,
			"transform": Transform3D(Basis(rotation.normalized()), position),
			"scene_path": scene_path,
			"overrides": overrides,
			"markers": markers,
			"presentation": presentation,
		}
		if record.has("volume_boxes"):
			var raw_boxes: Variant = record["volume_boxes"]
			if not type in ["rain_occluder", "rain_shelter", "carryable_respawn", "environment_transition"] or not raw_boxes is Array:
				return {"error": "%s has invalid compound volume boxes." % location}
			var extra_boxes: Array[Dictionary] = []
			for raw_box: Variant in raw_boxes:
				var extra_box: Dictionary = _decode_activation_box(raw_box)
				if extra_box.is_empty():
					return {"error": "%s has an invalid compound volume box." % location}
				extra_boxes.append(extra_box)
			placement["volume_boxes"] = extra_boxes
		if type in ["race_start", "goal_ring", "collection_item"]:
			var links: Variant = record.get("race_links", {})
			if not links is Dictionary:
				return {"error": "%s has invalid race links." % location}
			race_placements[id] = {"type": type, "links": links, "properties": properties, "overrides": overrides}
		if type == "surface_behavior":
			var targets: Variant = record.get("surface_targets", [])
			var volume: bool = properties.get("surface_behavior_mode", "targets") == "volume"
			if not targets is Array or targets.is_empty() != volume:
				return {"error": "%s needs %s." % [location, "no surface targets for a volume" if volume else "at least one surface target"]}
			var target_ids: Array[String] = []
			for raw_target: Variant in targets:
				if not raw_target is String or not uuid_pattern.search(raw_target) or target_ids.has(raw_target):
					return {"error": "%s has a duplicate or invalid surface target UUID." % location}
				target_ids.append(raw_target)
			if volume:
				overrides.append({"target_node": "CollisionShape3D", "name": "position", "value": Vector3.ZERO})
				overrides.append({"target_node": "VolumePreview", "name": "position", "value": Vector3.ZERO})
			else:
				placement["surface_targets"] = target_ids
			_configure_surface_traits(properties, fields, volume, overrides)
		if type == "gravity_modifier" and properties.has("gravity_modifier_gravity_up_direction"):
			var up: Vector3 = _decode_property(properties["gravity_modifier_gravity_up_direction"], fields["gravity_modifier_gravity_up_direction"])
			if up.length_squared() < 0.000001:
				return {"error": "%s needs a nonzero gravity up direction." % location}
		if type == "camera_constraint":
			var uses_entry_gate: bool = _camera_setting("camera_activation_mode", properties, fields) == 1
			var gates: Variant = _decode_camera_gates(record.get("camera_gates", {}), uses_entry_gate)
			if gates == null:
				return {"error": "%s has invalid camera gates. Entry Gate activation requires a valid entry box." % location}
			if _camera_setting("camera_override_position", properties, fields) and _camera_setting("camera_position_mode", properties, fields) == CameraPositionTrait.Mode.PATH_CAMERA:
				var camera_curve: Curve3D = _decode_curve(record.get("curve"))
				if not camera_curve:
					return {"error": "%s needs a valid Bézier camera path." % location}
				placement["curve"] = camera_curve
				placement["curve_target"] = "CameraPath"
				overrides.append({"name": "placement_camera_path", "value": true})
			if _camera_setting("camera_influence_enabled", properties, fields):
				if _camera_setting("camera_influence_full", properties, fields) >= _camera_setting("camera_influence_zero", properties, fields):
					return {"error": "%s needs a zero influence radius greater than its full influence radius." % location}
				if not (_camera_setting("camera_influence_position", properties, fields) or _camera_setting("camera_influence_orientation", properties, fields) or _camera_setting("camera_influence_lens", properties, fields)):
					return {"error": "%s needs at least one affected camera influence channel." % location}
			_configure_camera(properties, fields, gates, overrides, markers)
		if type == "teleporter_exit":
			overrides.append({"name": "teleporter_id", "value": StringName(id)})
		elif type == "teleporter_entrance":
			var link: Variant = record.get("teleporter_link")
			if not link is Dictionary:
				return {"error": "%s needs a teleporter link." % location}
			var raw_exit: Variant = link.get("exit", "")
			if not raw_exit is String or (link.has("exit") and not uuid_pattern.search(raw_exit.to_lower())):
				return {"error": "%s has an invalid teleporter exit UUID." % location}
			var exit_id: String = raw_exit.to_lower()
			if link.has("level_id"):
				var target_level: Variant = link["level_id"]
				var level_pattern: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
				if not target_level is String or not level_pattern.search(target_level) or target_level == level_id:
					return {"error": "%s has an invalid destination level ID." % location}
				overrides.append({"name": "target_level_id", "value": StringName(target_level)})
				if not exit_id.is_empty():
					var exit_path: NodePath = NodePath("%s/Placement_%s/Object_%s" % [ROOT_NAME, exit_id, exit_id])
					overrides.append({"name": "target_exit_path", "value": exit_path})
			elif exit_id.is_empty():
				return {"error": "%s needs a local teleporter exit UUID." % location}
			else:
				placement["teleporter_exit_id"] = exit_id
				overrides.append({"name": "exit_id", "value": StringName(exit_id)})
		if definition.has("curve_target"):
			var curve: Curve3D = _decode_curve(record.get("curve"))
			if not curve:
				return {"error": "%s has an invalid Bézier curve." % location}
			placement["curve"] = curve
			placement["curve_target"] = definition["curve_target"]
			if type == "automation_spline":
				var mode: String = str(properties.get("automation_activation", "endpoints"))
				if curve.closed and mode in ["endpoints", "area_crossings"]:
					return {"error": "%s needs Occupancy or Script Only activation for a closed route." % location}
				var boxes: Variant = _decode_automation_boxes(record.get("activation_boxes", {}), mode)
				if boxes == null:
					return {"error": "%s has invalid automation trigger boxes." % location}
				overrides.append({"name": "placement_triggers", "value": {"boxes": boxes}})
				var extensions: Variant = _decode_automation_extensions(
					record.get("automation_extensions", []), catalog.get("automation_extensions", {}), id, uuid_pattern
				)
				if extensions == null:
					return {"error": "%s has an invalid automation junction or progress event." % location}
				placement["automation_extensions"] = extensions
				overrides.append({"name": "placement_extensions", "value": extensions})
		if definition.has("attach_to"):
			var attachment: Variant = record.get("attachment")
			if not attachment is Dictionary or not attachment.get("rail_id") is String or not _is_finite_number(attachment.get("fraction")):
				return {"error": "%s needs a rail UUID and position." % location}
			var rail_id: String = attachment["rail_id"].to_lower()
			var fraction: float = float(attachment["fraction"])
			if not uuid_pattern.search(rail_id) or fraction < 0.0 or fraction > 1.0:
				return {"error": "%s has an invalid rail attachment." % location}
			placement["rail_id"] = rail_id
			placement["attach_to"] = definition["attach_to"]
			placement["curve_target"] = object_types[definition["attach_to"]]["curve_target"]
			overrides.append({"name": "placement_progress", "value": fraction})
		placements.append(placement)
	for placement: Dictionary in placements:
		if placement.has("teleporter_exit_id") and types_by_id.get(placement["teleporter_exit_id"]) != "teleporter_exit":
			return {"error": "%s teleporter %s references a missing exit: %s." % [path, placement["id"], placement["teleporter_exit_id"]]}
		if placement.has("rail_id") and types_by_id.get(placement["rail_id"]) != placement["attach_to"]:
			return {"error": "%s placement %s references a missing rail: %s." % [path, placement["id"], placement["rail_id"]]}
		for extension: Dictionary in placement.get("automation_extensions", []):
			if extension.has("destination") and types_by_id.get(extension["destination"]) != "automation_spline":
				return {"error": "%s route %s references a missing destination: %s." % [path, placement["id"], extension["destination"]]}
	var race_error: String = _configure_race_links(race_placements)
	if not race_error.is_empty():
		return {"error": "%s: %s" % [path, race_error]}
	return {"placements": placements, "environment": environment}


static func _decode_environment(raw: Variant, fields: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return {"error": "Expected an object."}
	var settings: Dictionary = {}
	var channel_pattern: RegEx = RegEx.create_from_string("^[A-Za-z0-9_]+$")
	for key: String in raw:
		if not fields.has(key):
			return {"error": "Unknown setting %s." % key}
		if key == "allowed_weather":
			continue
		var field: Dictionary = fields[key]
		var value: Variant = _decode_property(raw[key], field)
		if value == null:
			return {"error": "Invalid value for %s." % key}
		if field["type"] == "enum":
			var option: Dictionary = field["options"][raw[key]]
			var path: String = option.get("path", "")
			if not path.is_empty() and not ResourceLoader.exists(path):
				return {"error": "Missing preset resource %s." % path}
			if key == "sky_profile":
				value = path
			elif key == "starting_weather":
				value = StringName(raw[key])
				settings["starting_weather_path"] = path
		if key in ["time_channel", "weather_channel"] and not channel_pattern.search(str(value)):
			return {"error": "%s must use letters, digits, or underscores." % key}
		settings[key] = value
	if raw.has("allowed_weather"):
		var allowed: Variant = raw["allowed_weather"]
		if not allowed is Array or allowed.is_empty():
			return {"error": "Select at least one allowed weather preset."}
		if settings.get("dynamic_weather", false) and allowed.size() < 2:
			return {"error": "Dynamic weather needs at least two allowed presets."}
		var options: Dictionary = fields["starting_weather"]["options"]
		var preset_paths: Array[String] = []
		for id: Variant in allowed:
			if not id is String or not options.has(id) or not options[id].has("path"):
				return {"error": "Unknown allowed weather preset %s." % id}
			var path: String = options[id]["path"]
			if preset_paths.has(path) or not ResourceLoader.exists(path):
				return {"error": "Duplicate or unavailable allowed weather preset %s." % id}
			preset_paths.append(path)
		var initial_id: String = str(settings.get("starting_weather", &"random"))
		if initial_id != "random" and not allowed.has(initial_id):
			return {"error": "Starting Weather must be one of the allowed presets."}
		settings["allowed_weather"] = preset_paths
	return settings


static func apply_environment(level_root: Node, settings: Dictionary) -> String:
	if settings.is_empty():
		return ""
	var system: EnvironmentWeatherSystem = level_root as EnvironmentWeatherSystem
	for node: Node in level_root.find_children("*", "Node3D", true, false):
		if node is EnvironmentWeatherSystem:
			if system:
				return "Placement environment settings require a single EnvironmentWeatherSystem in %s." % level_root.name
			system = node
	if not system:
		return "Add an EnvironmentWeatherSystem to %s to use its placement environment settings." % level_root.name
	if settings.has("sky_profile"):
		var profile: DayNightProfile = load(settings["sky_profile"]) as DayNightProfile
		if not profile:
			return "Could not load placement sky profile %s." % settings["sky_profile"]
		system.environment_profile = profile
	if settings.has("start_time_mode") or settings.has("start_hour"):
		system.initial_time_mode = settings.get("start_time_mode", EnvironmentWeatherSystem.InitialTimeMode.FIXED)
		system.persistent_time_enabled = false
	if settings.has("start_hour"):
		system.initial_time_of_day_hours = fposmod(settings["start_hour"], 24.0)
	if settings.has("time_progression"):
		system.time_progression_enabled = settings["time_progression"]
	if settings.has("day_length_minutes"):
		system.day_length_minutes = settings["day_length_minutes"]
	if settings.has("allowed_weather"):
		system.weather_preset_paths = settings["allowed_weather"].duplicate()
		system.use_weather_presets = true
	elif settings.has("starting_weather"):
		var preset_path: String = settings["starting_weather_path"]
		if not preset_path.is_empty() and not system.weather_preset_paths.has(preset_path):
			var preset_paths: Array[String] = system.weather_preset_paths.duplicate()
			preset_paths.append(preset_path)
			system.weather_preset_paths = preset_paths
	if settings.has("starting_weather"):
		system.use_weather_presets = true
		system.initial_weather_id = settings["starting_weather"]
		system.persistent_weather_enabled = false
	if settings.has("dynamic_weather"):
		system.dynamic_weather_enabled = settings["dynamic_weather"]
		if system.dynamic_weather_enabled:
			system.use_weather_presets = true
	if settings.has("precipitation"):
		system.precipitation_enabled = settings["precipitation"]
	if settings.has("time_channel"):
		system.time_persistence_reference = settings["time_channel"]
	if settings.has("weather_channel"):
		system.weather_persistence_namespace = settings["weather_channel"]
	if settings.has("persistent_time"):
		system.persistent_time_enabled = settings["persistent_time"]
	if settings.has("persistent_weather"):
		system.persistent_weather_enabled = settings["persistent_weather"]
	return ""


static func _configure_surface_traits(properties: Dictionary, fields: Dictionary, volume: bool, overrides: Array[Dictionary]) -> void:
	var movement: SurfaceMovementTrait = SurfaceMovementTrait.new()
	movement.rolling = SurfaceMovementTrait.RollMode.FORCE
	var attachment: SurfaceAttachmentTrait = SurfaceAttachmentTrait.new()
	var hazard: SurfaceHazardTrait = SurfaceHazardTrait.new()
	var visibility: SurfaceVisibilityTrait = SurfaceVisibilityTrait.new()
	var resources: Dictionary = {
		"movement": movement, "attachment": attachment, "hazard": hazard, "visibility": visibility,
	}
	for key: String in properties:
		var field: Dictionary = fields[key]
		if field.has("surface_trait") and not (volume and field.get("surface_targets_only", false)):
			var component: SurfaceBehaviorTrait = resources[field["surface_trait"]]
			component.set(field["target_property"], _decode_property(properties[key], field))
	var movement_traits: Array[SurfaceMovementTrait] = [movement]
	var attachment_traits: Array[SurfaceAttachmentTrait] = [attachment]
	var hazard_traits: Array[SurfaceHazardTrait] = [hazard]
	var visibility_traits: Array[SurfaceVisibilityTrait] = [visibility]
	overrides.append_array([
		{"name": "movement_traits", "value": movement_traits},
		{"name": "attachment_traits", "value": attachment_traits},
		{"name": "hazard_traits", "value": hazard_traits},
		{"name": "visibility_traits", "value": visibility_traits},
	])


static func _configure_race_links(records: Dictionary) -> String:
	if records.is_empty():
		return ""
	var goal_owners: Dictionary = {}
	var race_ids: Dictionary = {}
	var race_id_pattern: RegEx = RegEx.create_from_string("^[A-Za-z0-9]{1,8}$")
	for id: String in records:
		var record: Dictionary = records[id]
		var links: Dictionary = record["links"]
		var kind: String = record["type"]
		var key: String = "goal" if kind == "race_start" else "start"
		if links.size() > int(links.has(key)) or (links.has(key) and not links[key] is String):
			return "Placement %s has invalid race links." % id
		var target: String = str(links.get(key, "")).to_lower()
		if links.has(key) and target.is_empty():
			return "Placement %s has an empty race link." % id
		var destination: Dictionary = records.get(target, {})
		if kind == "race_start":
			var race_id: String = str(record["properties"].get("race_start_race_id", "")).strip_edges()
			if race_id.is_empty():
				race_id = id.left(8).to_upper()
			if not race_id_pattern.search(race_id) or race_ids.has(race_id.to_lower()):
				return "Race Start %s needs a valid, distinct race ID." % id
			race_ids[race_id.to_lower()] = true
			record["overrides"].append({"name": "race_id", "value": race_id})
			if target.is_empty():
				continue
			if destination.get("type") != "goal_ring":
				return "Race Start %s needs a valid Goal Ring link." % id
			record["overrides"].append({"name": "collection_finish_goal_path", "value": _race_placement_path(target)})
			record["overrides"].append({"name": "ring_finish_goal_path", "value": _race_placement_path(target)})
		elif not target.is_empty():
			if destination.get("type") != "race_start":
				return "Placement %s needs a valid Race Start link." % id
			if kind == "collection_item":
				if destination["properties"].get("race_start_race_type") != "collection":
					return "Emerald Shard %s needs a Collection Race start." % id
				record["overrides"].append({"name": "race_start_path", "value": _race_placement_path(target)})
		if not target.is_empty() and kind != "collection_item":
			var goal_id: String = target if kind == "race_start" else id
			var start_id: String = id if kind == "race_start" else target
			if goal_owners.has(goal_id) and goal_owners[goal_id] != start_id:
				return "Goal Ring %s is linked to two different Race Starts." % goal_id
			goal_owners[goal_id] = start_id
	for goal_id: String in goal_owners:
		records[goal_id]["overrides"].append({"name": "race_start_path", "value": _race_placement_path(goal_owners[goal_id])})
	return ""


static func _race_placement_path(id: String) -> NodePath:
	return NodePath("../../Placement_%s/Object_%s" % [id, id])


static func _configure_camera(properties: Dictionary, fields: Dictionary, gates: Dictionary, overrides: Array[Dictionary], markers: Array[Dictionary]) -> void:
	if not properties.has("camera_point_offset"):
		markers.append({"target": "ConstraintPoint", "position": _camera_setting("camera_point_offset", properties, fields)})

	var helpers: Array[String] = []
	var activation_traits: Array[CameraActivationTrait] = []
	if gates.is_empty():
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = _camera_setting("camera_volume_size", properties, fields)
		overrides.append({"name": "shape", "target_node": "CollisionShape3D", "value": shape})
		var occupancy: CameraActivationTrait = CameraActivationTrait.new()
		occupancy.resource_name = "Occupancy Volume"
		activation_traits.append(occupancy)
	else:
		overrides.append({"name": "disabled", "target_node": "CollisionShape3D", "value": true})
		overrides.append({"name": "monitoring", "value": false})
		overrides.append({"name": "placement_camera_gates", "value": gates})
		var gate_events: Dictionary = {
			"EntryGate": CameraActivationTrait.Event.ENTER,
			"ExitGate": CameraActivationTrait.Event.EXIT,
			"RearmBoundary": CameraActivationTrait.Event.REARM,
		}
		for gate_name: String in gate_events:
			if gates.has(gate_name):
				var gate: CameraActivationTrait = CameraActivationTrait.new()
				gate.resource_name = gate_name
				gate.event = gate_events[gate_name]
				gate.area_path = NodePath(gate_name)
				activation_traits.append(gate)
		if _camera_setting("camera_duration_enabled", properties, fields):
			var timed: CameraActivationTrait = CameraActivationTrait.new()
			timed.resource_name = "Timed Release"
			timed.event = CameraActivationTrait.Event.DURATION
			timed.duration = _camera_setting("camera_duration", properties, fields)
			activation_traits.append(timed)
		if _camera_setting("camera_distance_enabled", properties, fields):
			var distance: CameraActivationTrait = CameraActivationTrait.new()
			distance.resource_name = "Distance Release"
			distance.event = CameraActivationTrait.Event.DISTANCE_EXIT
			distance.exit_distance = _camera_setting("camera_exit_distance", properties, fields)
			if _camera_setting("camera_distance_reference", properties, fields) == 1:
				distance.reference_path = _camera_helper("camera_release_offset", properties, fields, helpers, markers)
			activation_traits.append(distance)
	var position: CameraPositionTrait = CameraPositionTrait.new()
	position.mode = _camera_setting("camera_position_mode", properties, fields)
	if position.mode == CameraPositionTrait.Mode.PATH_CAMERA:
		position.resource_name = "Path Camera"
		position.source_path = NodePath("CameraPath")
	else:
		position.resource_name = ["Fixed Camera", "Fixed Pivot", "Player-relative Camera", "Player-relative Pivot"][position.mode]
	position.offset = _camera_setting("camera_position_offset", properties, fields)
	position.offset_space = _camera_setting("camera_offset_space", properties, fields)
	position.tracking_response = _camera_setting("camera_position_response", properties, fields)
	position.limit_axes = _camera_setting("camera_position_limit", properties, fields)
	if position.limit_axes:
		position.axis_mask = _camera_setting("camera_position_axes", properties, fields)
		if _camera_setting("camera_position_frame", properties, fields) == 1:
			position.axis_reference_path = NodePath(".")

	var orientation: CameraOrientationTrait = CameraOrientationTrait.new()
	orientation.mode = _camera_setting("camera_aim_mode", properties, fields)
	orientation.resource_name = "Face Aim Target" if orientation.mode == CameraOrientationTrait.Mode.FACE_TARGET else "Face Player"
	if orientation.mode == CameraOrientationTrait.Mode.FACE_TARGET:
		orientation.target_path = _camera_helper("camera_aim_target_offset", properties, fields, helpers, markers)
	orientation.target_offset = _camera_setting("camera_aim_offset", properties, fields)
	orientation.offset_uses_player_up = _camera_setting("camera_aim_player_offset", properties, fields)
	orientation.up_source = _camera_setting("camera_aim_up", properties, fields)
	orientation.tracking_response = _camera_setting("camera_aim_response", properties, fields)
	orientation.strength = _camera_setting("camera_aim_strength", properties, fields)
	orientation.limit_axes = _camera_setting("camera_aim_limit", properties, fields)
	if orientation.limit_axes:
		orientation.axis_mask = _camera_setting("camera_aim_axes", properties, fields)
		if _camera_setting("camera_aim_frame", properties, fields) == 1:
			orientation.axis_reference_path = NodePath(".")

	var lens_traits: Array[CameraLensTrait] = []
	if _camera_setting("camera_override_fov", properties, fields):
		var lens: CameraLensTrait = CameraLensTrait.new()
		lens.resource_name = "Fixed FOV"
		lens.fov = _camera_setting("camera_shot_fov", properties, fields)
		lens_traits.append(lens)
	if _camera_setting("camera_override_position", properties, fields) and position.mode in [CameraPositionTrait.Mode.FIXED_PIVOT, CameraPositionTrait.Mode.PLAYER_PIVOT]:
		orientation.orbit_rig = _camera_setting("camera_orbit_aim", properties, fields)
		if _camera_setting("camera_override_orbit_distance", properties, fields):
			var orbit: CameraLensTrait = CameraLensTrait.new()
			orbit.resource_name = "Orbit Distance"
			orbit.mode = CameraLensTrait.Mode.ORBIT_DISTANCE
			orbit.distance = _camera_setting("camera_orbit_distance", properties, fields)
			lens_traits.append(orbit)

	var influence_traits: Array[CameraInfluenceTrait] = []
	if _camera_setting("camera_influence_enabled", properties, fields):
		var influence: CameraInfluenceTrait = CameraInfluenceTrait.new()
		influence.resource_name = "Distance Influence"
		if _camera_setting("camera_influence_center", properties, fields) == 1:
			influence.reference_path = _camera_helper("camera_influence_offset", properties, fields, helpers, markers)
		influence.effective_axes = _camera_setting("camera_influence_axes", properties, fields)
		influence.axis_space = _camera_setting("camera_influence_frame", properties, fields)
		influence.full_influence_distance = _camera_setting("camera_influence_full", properties, fields)
		influence.zero_influence_distance = _camera_setting("camera_influence_zero", properties, fields)
		influence.falloff = _camera_setting("camera_influence_falloff", properties, fields)
		influence.power = _camera_setting("camera_influence_power", properties, fields)
		influence.position = _camera_setting("camera_influence_position", properties, fields)
		influence.orientation = _camera_setting("camera_influence_orientation", properties, fields)
		influence.lens = _camera_setting("camera_influence_lens", properties, fields)
		influence_traits.append(influence)

	var manual_mode: int = _camera_setting("camera_manual_mode", properties, fields)
	overrides.append({"name": "suppress_on_manual_look", "value": manual_mode in [0, 1]})
	overrides.append({"name": "cancel_on_manual_look", "value": manual_mode == 2})
	if manual_mode != 0:
		overrides.append({"name": "mouse_offset_enabled", "value": false})
		overrides.append({"name": "controller_offset_enabled", "value": false})

	var entry: CameraTransitionTrait = CameraTransitionTrait.new()
	entry.resource_name = "Entry Blend"
	entry.duration = _camera_setting("camera_blend_in", properties, fields)
	entry.mode = CameraTransitionTrait.Mode.TIMED if entry.duration > 0.0 else CameraTransitionTrait.Mode.INSTANT
	var exit: CameraTransitionTrait = CameraTransitionTrait.new()
	exit.resource_name = "Exit Blend"
	exit.phase = CameraTransitionTrait.Phase.EXIT
	exit.duration = _camera_setting("camera_blend_out", properties, fields)
	exit.mode = CameraTransitionTrait.Mode.TIMED if exit.duration > 0.0 else CameraTransitionTrait.Mode.INSTANT

	var position_traits: Array[CameraPositionTrait] = []
	var orientation_traits: Array[CameraOrientationTrait] = []
	if _camera_setting("camera_override_position", properties, fields):
		position_traits.append(position)
	if _camera_setting("camera_override_aim", properties, fields):
		orientation_traits.append(orientation)
	var transition_traits: Array[CameraTransitionTrait] = [entry, exit]
	overrides.append_array([
		{"name": "activation_traits", "value": activation_traits},
		{"name": "position_traits", "value": position_traits},
		{"name": "orientation_traits", "value": orientation_traits},
		{"name": "lens_traits", "value": lens_traits},
		{"name": "transition_traits", "value": transition_traits},
		{"name": "influence_traits", "value": influence_traits},
		{"name": "placement_camera_helpers", "value": helpers},
	])


static func _camera_helper(key: String, properties: Dictionary, fields: Dictionary, helpers: Array[String], markers: Array[Dictionary]) -> NodePath:
	var name: String = fields[key]["marker"]
	helpers.append(name)
	if not properties.has(key):
		markers.append({"target": name, "position": _camera_setting(key, properties, fields)})
	return NodePath(name)


static func _camera_setting(key: String, properties: Dictionary, fields: Dictionary) -> Variant:
	var field: Dictionary = fields[key]
	return _decode_property(properties.get(key, field["default"]), field)


static func _decode_camera_gates(raw: Variant, uses_entry_gate: bool) -> Variant:
	if not raw is Dictionary:
		return null
	if not uses_entry_gate:
		return {} if raw.is_empty() else null
	if not raw.has("entry"):
		return null
	var nodes: Dictionary = {"entry": "EntryGate", "exit": "ExitGate", "rearm": "RearmBoundary"}
	var gates: Dictionary = {}
	for role: String in raw:
		if not nodes.has(role):
			return null
		var box: Dictionary = _decode_activation_box(raw[role])
		if box.is_empty():
			return null
		gates[nodes[role]] = box
	return gates


static func _decode_automation_boxes(raw: Variant, mode: String) -> Variant:
	if not raw is Dictionary:
		return null
	if raw.is_empty():
		return {}
	var required: Array[String] = []
	match mode:
		"occupancy":
			required.assign(["Volume"])
		"endpoints", "area_crossings":
			required.assign(["Start", "End"])
	if required.is_empty() or raw.size() != required.size():
		return null
	var boxes: Dictionary = {}
	for label: String in required:
		var box: Dictionary = _decode_activation_box(raw.get(label))
		if box.is_empty():
			return null
		boxes[label] = box
	return boxes


static func _decode_activation_box(box: Variant) -> Dictionary:
	if not box is Dictionary or not _is_finite_array(box.get("position"), 3) or not _is_finite_array(box.get("size"), 3) or not _is_finite_array(box.get("rotation"), 4):
		return {}
	var position: Vector3 = Vector3(box.position[0], box.position[1], box.position[2])
	var size: Vector3 = Vector3(box.size[0], box.size[1], box.size[2])
	var rotation: Quaternion = Quaternion(box.rotation[0], box.rotation[1], box.rotation[2], box.rotation[3])
	if not position.is_finite() or not size.is_finite() or size.x < 0.1 or size.y < 0.1 or size.z < 0.1 or not is_finite(rotation.length_squared()) or is_zero_approx(rotation.length_squared()):
		return {}
	return {"transform": Transform3D(Basis(rotation.normalized()), position), "size": size}


static func _decode_automation_extensions(raw: Variant, definitions: Dictionary, source_id: String, uuid_pattern: RegEx) -> Variant:
	if not raw is Array:
		return null
	var extensions: Array[Dictionary] = []
	for item: Variant in raw:
		if not item is Dictionary or not definitions.has(item.get("kind")) or not item.get("properties") is Dictionary:
			return null
		var kind: String = item["kind"]
		var fields: Dictionary = definitions[kind]
		var properties: Dictionary = {}
		for key: String in item["properties"]:
			if not fields.has(key):
				return null
			var value: Variant = _decode_property(item["properties"][key], fields[key])
			if value == null:
				return null
			properties[key] = value
		var entry: Dictionary = {"kind": kind, "properties": properties}
		if kind == "junction":
			var destination: Variant = item.get("destination")
			if not destination is String or not uuid_pattern.search(destination) or destination == source_id:
				return null
			entry["destination"] = destination
		extensions.append(entry)
	return extensions


static func add_proxies(level_root: Node, placements: Array[Dictionary]) -> void:
	if placements.is_empty():
		return
	var container: Node3D = Node3D.new()
	var surface_nodes: Dictionary = {}
	for placement: Dictionary in placements:
		if placement.has("surface_targets"):
			surface_nodes = _index_surface_targets(level_root)
			break
	container.name = ROOT_NAME
	level_root.add_child(container, true)
	for placement: Dictionary in placements:
		var id: String = placement["id"]
		var surface_targets: Array[Node] = []
		if placement.has("surface_targets"):
			for target_id: String in placement["surface_targets"]:
				var target: Node = surface_nodes.get(target_id)
				if not target:
					push_warning("Surface placement %s cannot resolve a unique collider for %s. Export the track GLB with Custom Properties and reimport it." % [id, target_id])
					break
				surface_targets.append(target)
			if surface_targets.size() != placement["surface_targets"].size():
				continue
		var proxy: LevelObjectProxy = LevelObjectProxy.new()
		proxy.name = "Object_" + id
		proxy.target_scene_path = placement["scene_path"]
		proxy.set_meta(ID_META, id)
		if placement.has("rail_id"):
			var rail_id: String = placement["rail_id"]
			var parent_path: String = "%s/Placement_%s/Object_%s/%s" % [
				level_root.get_path_to(container), rail_id, rail_id, placement["curve_target"]
			]
			proxy.spawn_parent_path = NodePath(parent_path)
			proxy.spawn_parent_required = true
		else:
			var holder: Node3D = Node3D.new()
			holder.name = "Placement_" + id
			holder.transform = placement["transform"]
			holder.set_meta(ID_META, id)
			container.add_child(holder)
			proxy.spawn_parent_path = level_root.get_path_to(holder)
		proxy.property_overrides = placement["overrides"]
		var presentation: Dictionary = placement.get("presentation", {})
		proxy.presentation_hidden = presentation.get("hidden", false)
		proxy.presentation_muted = presentation.get("muted", false)
		if placement.has("volume_boxes"):
			proxy.extra_volume_boxes.assign(placement["volume_boxes"])
		if not surface_targets.is_empty():
			var target_paths: Array[NodePath] = []
			var holder: Node = level_root.get_node(proxy.spawn_parent_path)
			for target: Node in surface_targets:
				target_paths.append(NodePath("../" + str(holder.get_path_to(target))))
			proxy.property_overrides.append({"name": "target_paths", "value": target_paths})
		if placement.has("curve"):
			var curve_source: Path3D = Path3D.new()
			curve_source.name = &"SourceCurve"
			curve_source.curve = placement["curve"]
			proxy.add_child(curve_source)
			proxy.curve_copy_enabled = true
			proxy.curve_source_path = NodePath(curve_source.name)
			proxy.curve_target_path = NodePath(placement["curve_target"])
		for entry: Dictionary in placement.get("markers", []):
			var marker: Marker3D = Marker3D.new()
			marker.name = "Marker_%d" % proxy.get_child_count()
			marker.position = entry["position"]
			proxy.add_child(marker)
			proxy.transform_copies.append({"from": NodePath(marker.name), "to": NodePath(entry["target"])})
		container.add_child(proxy)


static func _index_surface_targets(level_root: Node) -> Dictionary:
	var result: Dictionary = {}
	for node: Node in level_root.find_children("*", "Node3D", true, false):
		var extras: Variant = node.get_meta(&"extras", {})
		if not extras is Dictionary or not extras.get("vane_surface_target_id") is String:
			continue
		var id: String = extras["vane_surface_target_id"]
		if result.has(id):
			result[id] = null
		else:
			result[id] = _surface_collider_for(node)
	return result


static func _surface_collider_for(node: Node) -> Node:
	if node is CollisionObject3D:
		return node if not node.get_shape_owners().is_empty() else null
	if not node.find_children("*", "CollisionShape3D", true, false).is_empty():
		return node
	var ancestor: Node = node.get_parent()
	while ancestor and not ancestor is CollisionObject3D:
		ancestor = ancestor.get_parent()
	if ancestor:
		var owners: PackedInt32Array = ancestor.get_shape_owners()
		if owners.size() == 1:
			return ancestor.shape_owner_get_owner(owners[0]) as Node
	return null


static func _decode_curve(raw: Variant) -> Curve3D:
	if not raw is Dictionary or not raw.get("closed") is bool or not raw.get("points") is Array:
		return null
	var points: Array = raw["points"]
	var closed: bool = raw["closed"]
	if points.size() < (3 if closed else 2):
		return null
	var curve: Curve3D = Curve3D.new()
	for point: Variant in points:
		if not point is Dictionary or not _is_finite_number(point.get("tilt")):
			return null
		var coordinates: Array[Vector3] = []
		for key: String in ["position", "in", "out"]:
			var values: Variant = point.get(key)
			if not _is_finite_array(values, 3):
				return null
			var vector: Vector3 = Vector3(values[0], values[1], values[2])
			if not vector.is_finite():
				return null
			coordinates.append(vector)
		curve.add_point(coordinates[0], coordinates[1], coordinates[2])
		curve.set_point_tilt(curve.point_count - 1, float(point["tilt"]))
	curve.closed = closed
	return curve if curve.get_baked_length() > 0.001 else null


static func _decode_property(raw: Variant, field: Dictionary) -> Variant:
	match field["type"]:
		"bool":
			return raw if raw is bool else null
		"string":
			if raw is String:
				var value: String = raw.strip_edges()
				if not value.is_empty() or field.get("allow_empty", false):
					return value if field.get("plain_string", false) else StringName(value)
		"physics_mask":
			if _is_finite_number(raw):
				var mask: float = float(raw)
				if mask >= 0.0 and mask <= 4294967295.0 and mask == floorf(mask):
					return int(mask)
		"axis_mask":
			if _is_finite_number(raw):
				var mask: float = float(raw)
				if mask >= 1.0 and mask <= 7.0 and mask == floorf(mask):
					return int(mask)
		"enum":
			var options: Dictionary = field["options"]
			if raw is String and options.has(raw):
				return int(options[raw]["value"])
		"float", "int":
			if _is_finite_number(raw):
				var value: float = float(raw)
				if value >= float(field["min"]) and value <= float(field.get("max", INF)):
					if field["type"] == "float":
						return value
					if value == floorf(value):
						return int(value)
		"local_offset", "local_vector":
			if _is_finite_array(raw, 3):
				var offset: Vector3 = Vector3(raw[0], raw[1], raw[2])
				if offset.is_finite():
					return offset
		"local_dimensions":
			if _is_finite_array(raw, 3):
				var minimum: float = float(field["min"])
				if minf(raw[0], minf(raw[1], raw[2])) >= minimum:
					var dimensions: Vector3 = Vector3(raw[0], raw[1], raw[2])
					if dimensions.is_finite():
						return dimensions
		"color":
			if _is_finite_array(raw, 4):
				for channel: float in raw:
					if channel < 0.0 or channel > 1.0:
						return null
				return Color(raw[0], raw[1], raw[2], raw[3])
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

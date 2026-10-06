@tool
extends EditorScenePostImportPlugin

const SURFACE_METADATA = preload("res://LS5Framework/Scripts/World/SurfaceBehaviorMetadata.gd")
const SURFACE_BEHAVIOR_AREA_SCRIPT = preload("res://LS5Framework/Scripts/World/ImportedSurfaceBehaviorArea.gd")
const MIN_ATTACH_ANGLE_DEG: float = 0.0
const MAX_ATTACH_ANGLE_DEG: float = 180.0
const MAX_DAMAGE_AMOUNT: int = 1000
const GENERATE_COLLISION_KEYWORD: String = "_GENCOL"

var _attach_limit_pattern: RegEx = null
var _no_attach_pattern: RegEx = null
var _hurt_pattern: RegEx = null
var _damage_pattern: RegEx = null
var _boolean_tag_metadata: Dictionary = {}
var _boolean_tag_patterns: Dictionary = {}
var _intangible_requests: Dictionary = {}


func _init() -> void:
	_attach_limit_pattern = RegEx.new()
	_attach_limit_pattern.compile(
		"(?i)(?:^|[^a-z0-9])attachlimit\\s*=\\s*([-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+))(?=$|[^a-z0-9.])"
	)
	_no_attach_pattern = _compile_boolean_tag_pattern("noattach")
	_hurt_pattern = _compile_boolean_tag_pattern("hurt")
	_damage_pattern = RegEx.new()
	_damage_pattern.compile(
		"(?i)(?:^|[^a-z0-9])(?:hurt|damage)\\s*=\\s*([-+]?[0-9]+)(?=$|[^a-z0-9.])"
	)

	_boolean_tag_metadata = {
		"deathplane": SURFACE_METADATA.DEATH,
		"death": SURFACE_METADATA.DEATH,
		"intangible": SURFACE_METADATA.INTANGIBLE,
		"noslopegravity": SURFACE_METADATA.NO_SLOPE_GRAVITY,
		"noslopegrav": SURFACE_METADATA.NO_SLOPE_GRAVITY,
		"nodetach": SURFACE_METADATA.NO_DETACH,
		"sticky": SURFACE_METADATA.STICKY,
		"forceroll": SURFACE_METADATA.FORCE_ROLL,
		"nojump": SURFACE_METADATA.NO_JUMP,
		"nocoyotejump": SURFACE_METADATA.NO_COYOTE_JUMP,
		"nocoyote": SURFACE_METADATA.NO_COYOTE_JUMP,
		"noroll": SURFACE_METADATA.NO_ROLL,
		"nodrift": SURFACE_METADATA.NO_DRIFT,
	}
	for tag: String in _boolean_tag_metadata:
		_boolean_tag_patterns[tag] = _compile_boolean_tag_pattern(tag)


func _pre_process(scene: Node) -> void:
	if scene == null:
		return
	var subresources_value: Variant = get_option_value(&"_subresources")
	if not (subresources_value is Dictionary):
		return
	var subresources: Dictionary = subresources_value
	var node_options: Dictionary = subresources.get("nodes", {})
	_enable_named_collision_generation(scene, scene, node_options)
	subresources["nodes"] = node_options


func _enable_named_collision_generation(
	scene: Node,
	node: Node,
	node_options: Dictionary
) -> void:
	var is_mesh_object: bool = node is ImporterMeshInstance3D or node is MeshInstance3D
	if is_mesh_object and String(node.name).to_upper().contains(GENERATE_COLLISION_KEYWORD):
		var path_key: String = "PATH:%s" % String(scene.get_path_to(node))
		var options: Dictionary = node_options.get(path_key, {})
		options["generate/physics"] = true
		node_options[path_key] = options
	for child: Node in node.get_children():
		_enable_named_collision_generation(scene, child, node_options)


func _post_process(scene: Node) -> void:
	if scene == null:
		return
	_intangible_requests.clear()
	_clear_imported_metadata(scene)
	_apply_name_rules(scene)
	_create_intangible_triggers(scene)


func _compile_boolean_tag_pattern(tag: String) -> RegEx:
	var pattern: RegEx = RegEx.new()
	pattern.compile("(?i)(?:^|[^a-z0-9])%s(?=$|[^a-z0-9])" % tag)
	return pattern


func _clear_imported_metadata(node: Node) -> void:
	_clear_metadata(node)
	if node is CollisionShape3D:
		var collision_shape: CollisionShape3D = node as CollisionShape3D
		if collision_shape.shape:
			_clear_metadata(collision_shape.shape)
	elif node is CollisionObject3D:
		_clear_collision_object_metadata(node as CollisionObject3D)

	for child: Node in node.get_children():
		_clear_imported_metadata(child)


func _clear_metadata(source: Object) -> void:
	if source == null:
		return
	for metadata_key: StringName in SURFACE_METADATA.get_all_keys():
		source.remove_meta(metadata_key)


func _apply_name_rules(node: Node) -> void:
	var metadata: Dictionary = _get_name_metadata(node)
	if not metadata.is_empty():
		_apply_surface_metadata(node, metadata)
		if bool(metadata.get(SURFACE_METADATA.INTANGIBLE, false)):
			_queue_intangible_targets(node, metadata)

	for child: Node in node.get_children():
		_apply_name_rules(child)


func _get_name_metadata(node: Node) -> Dictionary:
	var metadata: Dictionary = {}
	var attach_limit: float = _get_name_attach_limit(node)
	if attach_limit >= MIN_ATTACH_ANGLE_DEG:
		metadata[SURFACE_METADATA.ATTACH_LIMIT] = attach_limit

	var node_name: String = String(node.name)
	if _hurt_pattern.search(node_name) != null:
		metadata[SURFACE_METADATA.DAMAGE_AMOUNT] = 1
	_apply_damage_tag(node, node_name, metadata)

	for tag: String in _boolean_tag_patterns:
		var pattern: RegEx = _boolean_tag_patterns[tag]
		if pattern.search(node_name) != null:
			metadata[_boolean_tag_metadata[tag]] = true

	if (
		bool(metadata.get(SURFACE_METADATA.FORCE_ROLL, false))
		and bool(metadata.get(SURFACE_METADATA.NO_ROLL, false))
	):
		push_warning(
			"Surface behavior import: '%s' contains both forceroll and noroll; forceroll takes precedence."
			% node.get_path()
		)
		metadata.erase(SURFACE_METADATA.NO_ROLL)
	if (
		metadata.has(SURFACE_METADATA.ATTACH_LIMIT)
		and float(metadata.get(SURFACE_METADATA.ATTACH_LIMIT, -1.0)) <= 0.0
		and bool(metadata.get(SURFACE_METADATA.NO_DETACH, false))
	):
		push_warning(
			"Surface behavior import: '%s' contains both noattach and nodetach; noattach takes precedence."
			% node.get_path()
		)
		metadata.erase(SURFACE_METADATA.NO_DETACH)
	return metadata


func _apply_damage_tag(node: Node, node_name: String, metadata: Dictionary) -> void:
	var damage_matches: Array[RegExMatch] = _damage_pattern.search_all(node_name)
	if damage_matches.is_empty():
		var lower_name: String = node_name.to_lower()
		if lower_name.contains("hurt=") or lower_name.contains("damage="):
			push_warning(
				"Surface behavior import: '%s' contains an invalid hurt or damage tag."
				% node.get_path()
			)
			metadata.erase(SURFACE_METADATA.DAMAGE_AMOUNT)
		return
	if damage_matches.size() > 1:
		push_warning(
			"Surface behavior import: '%s' contains multiple damage values; the last value is used."
			% node.get_path()
		)
	var damage_match: RegExMatch = damage_matches[damage_matches.size() - 1]
	var amount: int = int(damage_match.get_string(1))
	if amount < 1 or amount > MAX_DAMAGE_AMOUNT:
		push_warning(
			"Surface behavior import: '%s' has damage=%s outside the valid 1 to %d range."
			% [node.get_path(), damage_match.get_string(1), MAX_DAMAGE_AMOUNT]
		)
		metadata.erase(SURFACE_METADATA.DAMAGE_AMOUNT)
		return
	metadata[SURFACE_METADATA.DAMAGE_AMOUNT] = amount


func _get_name_attach_limit(node: Node) -> float:
	var node_name: String = String(node.name)
	var has_no_attach: bool = _no_attach_pattern.search(node_name) != null
	var attach_matches: Array[RegExMatch] = _attach_limit_pattern.search_all(node_name)
	if has_no_attach:
		if not attach_matches.is_empty():
			push_warning(
				"Surface behavior import: '%s' contains both noattach and attachlimit; noattach takes precedence."
				% node.get_path()
			)
		return MIN_ATTACH_ANGLE_DEG

	if attach_matches.is_empty():
		if node_name.to_lower().contains("attachlimit"):
			push_warning(
				"Surface behavior import: '%s' contains an invalid attachlimit tag."
				% node.get_path()
			)
		return -1.0

	if attach_matches.size() > 1:
		push_warning(
			"Surface behavior import: '%s' contains multiple attachlimit tags; the last value is used."
			% node.get_path()
		)

	var attach_match: RegExMatch = attach_matches[attach_matches.size() - 1]
	var limit: float = float(attach_match.get_string(1))
	if limit < MIN_ATTACH_ANGLE_DEG or limit > MAX_ATTACH_ANGLE_DEG:
		push_warning(
			"Surface behavior import: '%s' has attachlimit=%s outside the valid 0 to 180 degree range."
			% [node.get_path(), attach_match.get_string(1)]
		)
		return -1.0
	return limit


func _apply_surface_metadata(node: Node, metadata: Dictionary) -> void:
	_set_metadata(node, metadata)

	if node is CollisionShape3D:
		_set_collision_shape_metadata(node as CollisionShape3D, metadata)
		return
	elif node is CollisionPolygon3D:
		var collision_object: CollisionObject3D = _find_collision_ancestor(node)
		if collision_object:
			var owner_id: int = _find_shape_owner_id(collision_object, node)
			if owner_id >= 0:
				_set_shape_owner_metadata(collision_object, owner_id, metadata)
		return
	elif node is CollisionObject3D:
		_set_collision_object_metadata(node as CollisionObject3D, metadata)
		return

	var collision_ancestor: CollisionObject3D = _find_collision_ancestor(node)
	if collision_ancestor:
		_set_collision_object_metadata(collision_ancestor, metadata)

	_apply_metadata_to_collision_descendants(node, metadata)


func _set_metadata(source: Object, metadata: Dictionary) -> void:
	if source == null:
		return
	for metadata_key: Variant in metadata:
		source.set_meta(StringName(String(metadata_key)), metadata[metadata_key])


func _find_collision_ancestor(node: Node) -> CollisionObject3D:
	var ancestor: Node = node.get_parent()
	while ancestor:
		if ancestor is CollisionObject3D:
			return ancestor as CollisionObject3D
		ancestor = ancestor.get_parent()
	return null


func _apply_metadata_to_collision_descendants(node: Node, metadata: Dictionary) -> void:
	for child: Node in node.get_children():
		if child is CollisionObject3D:
			_set_collision_object_metadata(child as CollisionObject3D, metadata)
		elif child is CollisionShape3D:
			_set_collision_shape_metadata(child as CollisionShape3D, metadata)
		_apply_metadata_to_collision_descendants(child, metadata)


func _set_collision_object_metadata(collision_object: CollisionObject3D, metadata: Dictionary) -> void:
	_set_metadata(collision_object, metadata)
	for owner_id: int in collision_object.get_shape_owners():
		_set_shape_owner_metadata(collision_object, owner_id, metadata)


func _set_shape_owner_metadata(
	collision_object: CollisionObject3D,
	owner_id: int,
	metadata: Dictionary
) -> void:
	var shape_owner: Object = collision_object.shape_owner_get_owner(owner_id)
	_set_metadata(shape_owner, metadata)


func _set_collision_shape_metadata(collision_shape: CollisionShape3D, metadata: Dictionary) -> void:
	_set_metadata(collision_shape, metadata)


func _clear_collision_object_metadata(collision_object: CollisionObject3D) -> void:
	_clear_metadata(collision_object)
	for owner_id: int in collision_object.get_shape_owners():
		var shape_owner: Object = collision_object.shape_owner_get_owner(owner_id)
		_clear_metadata(shape_owner)
		for shape_id: int in range(collision_object.shape_owner_get_shape_count(owner_id)):
			var shape: Shape3D = collision_object.shape_owner_get_shape(owner_id, shape_id)
			_clear_metadata(shape)


func _queue_intangible_targets(node: Node, metadata: Dictionary) -> void:
	if node is CollisionShape3D or node is CollisionPolygon3D:
		var collision_object: CollisionObject3D = _find_collision_ancestor(node)
		if collision_object:
			var owner_id: int = _find_shape_owner_id(collision_object, node)
			_queue_intangible_request(collision_object, owner_id, metadata)
		return
	if node is CollisionObject3D:
		_queue_intangible_request(node as CollisionObject3D, -1, metadata)
		return

	var collision_ancestor: CollisionObject3D = _find_collision_ancestor(node)
	if collision_ancestor:
		_queue_intangible_request(collision_ancestor, -1, metadata)
	_queue_intangible_descendants(node, metadata)


func _queue_intangible_descendants(node: Node, metadata: Dictionary) -> void:
	for child: Node in node.get_children():
		if child is CollisionObject3D:
			_queue_intangible_request(child as CollisionObject3D, -1, metadata)
		else:
			_queue_intangible_descendants(child, metadata)


func _find_shape_owner_id(collision_object: CollisionObject3D, owner_node: Node) -> int:
	for owner_id: int in collision_object.get_shape_owners():
		if collision_object.shape_owner_get_owner(owner_id) == owner_node:
			return owner_id
	return -1


func _queue_intangible_request(
	collision_object: CollisionObject3D,
	owner_id: int,
	metadata: Dictionary
) -> void:
	if collision_object == null:
		return
	var object_prefix: String = "%d:" % collision_object.get_instance_id()
	var whole_object_key: String = object_prefix + "all"
	if owner_id >= 0 and _intangible_requests.has(whole_object_key):
		return
	if owner_id < 0:
		for request_key: Variant in _intangible_requests.keys():
			if String(request_key).begins_with(object_prefix):
				_intangible_requests.erase(request_key)
	var key: String = whole_object_key if owner_id < 0 else object_prefix + str(owner_id)
	var merged_metadata: Dictionary = metadata.duplicate()
	if _intangible_requests.has(key):
		var existing_request: Dictionary = _intangible_requests[key]
		merged_metadata = existing_request.get("metadata", {}).duplicate()
		merged_metadata.merge(metadata, true)
	_intangible_requests[key] = {
		"collision_object": collision_object,
		"owner_id": owner_id,
		"metadata": merged_metadata,
	}


func _create_intangible_triggers(scene: Node) -> void:
	for request_value: Variant in _intangible_requests.values():
		var request: Dictionary = request_value
		var collision_object: CollisionObject3D = request.get("collision_object")
		if collision_object == null or not is_instance_valid(collision_object):
			continue
		var owner_id: int = int(request.get("owner_id", -1))
		var metadata: Dictionary = request.get("metadata", {})
		_create_intangible_trigger(scene, collision_object, owner_id, metadata)


func _create_intangible_trigger(
	scene: Node,
	collision_object: CollisionObject3D,
	owner_id: int,
	metadata: Dictionary
) -> void:
	var trigger: Area3D = Area3D.new()
	trigger.name = "%s_SurfaceBehaviorTrigger" % collision_object.name
	trigger.collision_layer = 0
	trigger.collision_mask = 0xFFFFFFFF
	trigger.monitoring = true
	trigger.monitorable = false
	trigger.set_script(SURFACE_BEHAVIOR_AREA_SCRIPT)
	collision_object.add_child(trigger, true)
	trigger.owner = scene
	_set_metadata(trigger, metadata)

	var shape_count: int = 0
	if owner_id >= 0:
		shape_count = _add_trigger_owner_shapes(scene, trigger, collision_object, owner_id)
	else:
		for current_owner_id: int in collision_object.get_shape_owners():
			shape_count += _add_trigger_owner_shapes(
				scene,
				trigger,
				collision_object,
				current_owner_id
			)

	if shape_count <= 0:
		collision_object.remove_child(trigger)
		trigger.free()
		push_warning(
			"Surface behavior import: '%s' could not create an intangible trigger because no collision shapes were found."
			% collision_object.get_path()
		)
		return

	if owner_id >= 0:
		collision_object.shape_owner_set_disabled(owner_id, true)
	else:
		collision_object.collision_layer = 0
		if collision_object is Area3D:
			(collision_object as Area3D).monitoring = false


func _add_trigger_owner_shapes(
	scene: Node,
	trigger: Area3D,
	collision_object: CollisionObject3D,
	owner_id: int
) -> int:
	var added_count: int = 0
	var owner_transform: Transform3D = collision_object.shape_owner_get_transform(owner_id)
	for shape_id: int in range(collision_object.shape_owner_get_shape_count(owner_id)):
		var shape: Shape3D = collision_object.shape_owner_get_shape(owner_id, shape_id)
		if shape == null:
			continue
		var trigger_shape: CollisionShape3D = CollisionShape3D.new()
		trigger_shape.name = "SurfaceBehaviorShape%d" % shape_id
		trigger_shape.transform = owner_transform
		trigger_shape.shape = shape
		trigger.add_child(trigger_shape, true)
		trigger_shape.owner = scene
		added_count += 1
	return added_count

class_name LiminalEditor extends RefCounted

class SchemaContext:
	var entity_definitions: Array[Dictionary]
	var choice_definitions: Dictionary
	var report: LMSyncReport
	var sync_cache: LMSyncCache

class PropContext:
	var godot_props: Array[Dictionary]
	var var_comments: Dictionary
	var lm_prop: Dictionary
	var clazz: Object
	var entity_classname: String

static func create_empty_manifest() -> Dictionary:
	return {

	}

static func create_schema_context() -> SchemaContext:
	var ctx := SchemaContext.new()
	ctx.report = LMSyncReport.new()
	return ctx

static func create_lm_entities_from_dir(dir: String, ctx: SchemaContext) -> void:
	var files: Array[String] = []
	var dirs: Array[String] = [dir]

	while !dirs.is_empty():
		var d: String = dirs.pop_front()
		for file in DirAccess.get_files_at(d):
			files.append(d.path_join(file))

		for subdir in DirAccess.get_directories_at(d):
			dirs.append(d.path_join(subdir))
	_create_lm_entities_from_paths(files, ctx)


static func _create_lm_entities_from_paths(paths: Array[String], ctx: SchemaContext) -> void:
	for path in paths:
		_create_lm_entity_from_path(path, ctx)

static func _register_choices_provider(provider: LMChoicesProvider, ctx: SchemaContext) -> void:
	if provider.type_key.is_empty():
		push_error("LMChoicesProvider has no type_key set - skipping.")
		return
	if ctx.choice_definitions.has(provider.type_key):
		return
	var choices_dict: Dictionary = {}
	for item in provider.get_choices():
		choices_dict[item["label"]] = item["value"]
	ctx.choice_definitions[provider.type_key] = choices_dict

static func _create_choice_definition(godot_prop: Dictionary, ctx: SchemaContext) -> void:
	var name: String = godot_prop["class_name"]
	if !ctx.choice_definitions.has(name):
		var items : Dictionary = {}
		for row in godot_prop["hint_string"].split(","):
			var t: PackedStringArray = row.split(":")
			items.set(t[0], int(t[1]))
		ctx.choice_definitions.set(name, items)


static func _parse_flags_hint(hint_string: String) -> Dictionary:
	var items: Dictionary = {}
	var parts: PackedStringArray = hint_string.split(",")
	for i in parts.size():
		var row: PackedStringArray = parts[i].split(":")
		var label: String = row[0].strip_edges()
		if label.is_empty():
			continue
		items[label] = int(row[1]) if row.size() > 1 else (1 << i)
	return items


const _LAYER_HINTS: Dictionary = {
	PROPERTY_HINT_LAYERS_2D_RENDER: ["Layers2DRender", "layer_names/2d_render", 20],
	PROPERTY_HINT_LAYERS_2D_PHYSICS: ["Layers2DPhysics", "layer_names/2d_physics", 32],
	PROPERTY_HINT_LAYERS_2D_NAVIGATION: ["Layers2DNavigation", "layer_names/2d_navigation", 32],
	PROPERTY_HINT_LAYERS_3D_RENDER: ["Layers3DRender", "layer_names/3d_render", 20],
	PROPERTY_HINT_LAYERS_3D_PHYSICS: ["Layers3DPhysics", "layer_names/3d_physics", 32],
	PROPERTY_HINT_LAYERS_3D_NAVIGATION: ["Layers3DNavigation", "layer_names/3d_navigation", 32],
	PROPERTY_HINT_LAYERS_AVOIDANCE: ["LayersAvoidance", "layer_names/avoidance", 32],
}


static func _layer_hint_items(hint: int) -> Dictionary:
	var spec: Array = _LAYER_HINTS[hint]
	var items: Dictionary = {}
	for i in range(int(spec[2])):
		var label: String = str(ProjectSettings.get_setting("%s/layer_%d" % [spec[1], i + 1], ""))
		if label.is_empty():
			label = "Layer %d" % (i + 1)
		if items.has(label):
			label = "%s (%d)" % [label, i + 1]
		items[label] = 1 << i
	return items


static func _choices_from_backing(node: Node, prop_name: String, owner_name: String) -> Dictionary:
	if node == null:
		return {}
	for gp in node.get_property_list():
		if gp.name == prop_name:
			return _choices_from_hint(gp, owner_name)
	return {}


static func _choices_from_hint(gp: Dictionary, owner_name: String) -> Dictionary:
	if gp.hint == PROPERTY_HINT_ENUM and not str(gp.hint_string).is_empty():
		var is_string: bool = gp.type in [TYPE_STRING, TYPE_STRING_NAME]
		var items: Dictionary = {}
		var parts: PackedStringArray = str(gp.hint_string).split(",")
		for i in parts.size():
			var row: PackedStringArray = parts[i].split(":")
			var label: String = row[0].strip_edges()
			if label.is_empty():
				continue
			if is_string:
				items[label] = label
			else:
				items[label] = int(row[1]) if row.size() > 1 else i
		var key: String = str(gp["class_name"])
		if key.is_empty():
			key = "%s.%s" % [owner_name, gp.name]
		return {"key": key, "items": items}
	if gp.hint == PROPERTY_HINT_FLAGS and not str(gp.hint_string).is_empty():
		return {"key": "%s.%s" % [owner_name, gp.name], "items": _parse_flags_hint(gp.hint_string)}
	if _LAYER_HINTS.has(gp.hint):
		return {"key": _LAYER_HINTS[gp.hint][0], "items": _layer_hint_items(gp.hint)}
	return {}


static func _mask_to_labels(mask: int, items: Dictionary) -> String:
	var labels: PackedStringArray = []
	for label in items:
		if mask & int(items[label]):
			labels.append(label)
	return ",".join(labels)

static func _process_lm_property(prop_def: Dictionary, context: PropContext, ctx: SchemaContext) -> bool:
	if not "name" in context.lm_prop:
		push_error("Liminal Editor: entity %s invalid setup in _export_entity_props. Missing \"name\" field.")
		return false

	var godot_prop_idx: int = context.godot_props.find_custom(func (p): return p.name == context.lm_prop.name)
	if godot_prop_idx < 0:
		push_error("_export_entity_props exports property that doesn't exist (%s)" % context.lm_prop.name)
		return false
	var godot_prop: Dictionary = context.godot_props[godot_prop_idx]

	var prop_comment: String = ""
	if "comment" in context.lm_prop: prop_comment = context.lm_prop.comment
	elif context.var_comments.has(context.lm_prop.name): prop_comment = context.var_comments[context.lm_prop.name]

	prop_def.set("name", context.lm_prop.name)
	prop_def.set("description", prop_comment)

	if context.lm_prop.has("choices") and context.lm_prop["choices"]:
		var provider: Resource = context.lm_prop["choices"]
		_register_choices_provider(provider, ctx)
		var suffix: String = "[]" if context.lm_prop.get("multi", false) else ""
		prop_def.set("type", "$%s%s" % [provider.get("type_key"), suffix])
		return true

	var prop_value: Variant = context.clazz.get(context.lm_prop.name)
	var prop_type: Variant = typeof(prop_value)
	if prop_type in	[TYPE_AABB,
		TYPE_ARRAY,
		TYPE_BASIS,
		TYPE_CALLABLE,
		TYPE_DICTIONARY,
		TYPE_NODE_PATH,
		TYPE_OBJECT]:
			push_error("Property type %s is not supported by Liminal Editor and will not be exported to blender" % [type_string(prop_type)])
			return false
	if "type" in context.lm_prop:
		prop_type = context.lm_prop.type
	else:
		prop_type = godot_prop.type

	if godot_prop.hint == PROPERTY_HINT_ENUM:
		prop_def.set("type", "$%s" % godot_prop.class_name)
		_create_choice_definition(godot_prop, ctx)
	elif godot_prop.hint == PROPERTY_HINT_FLAGS and not godot_prop.hint_string.is_empty():
		var key: String = "%s.%s" % [context.entity_classname, context.lm_prop.name]
		var items: Dictionary = _parse_flags_hint(godot_prop.hint_string)
		if not ctx.choice_definitions.has(key):
			ctx.choice_definitions[key] = items
		prop_def.set("type", "$%s[]" % key)
		prop_def.set("default_value", _mask_to_labels(int(prop_value), items))
	elif _LAYER_HINTS.has(godot_prop.hint):
		var key: String = _LAYER_HINTS[godot_prop.hint][0]
		var items: Dictionary = _layer_hint_items(godot_prop.hint)
		if not ctx.choice_definitions.has(key):
			ctx.choice_definitions[key] = items
		prop_def.set("type", "$%s[]" % key)
		prop_def.set("default_value", _mask_to_labels(int(prop_value), items))
	elif prop_type is String:
		var t: String = (prop_type as String).to_lower()
		if t in ["source", "destination"]:
			prop_def.set("type", t)
		else:
			push_warning("Unsupported prop type: %s" % prop_type)
	elif prop_type is int:
		prop_def.set("type", type_string(prop_type))
		match prop_type:
			TYPE_COLOR, TYPE_VECTOR4, TYPE_VECTOR4I:
				prop_def.set("default_value", [prop_value[0], prop_value[1], prop_value[2], prop_value[3]])
			TYPE_VECTOR3, TYPE_VECTOR3I:
				prop_def.set("default_value", [prop_value[0], prop_value[1], prop_value[2]])
			_:
				prop_def.set("default_value", prop_value)
	return true

static func _lm_prop_to_dict(item: Variant) -> Dictionary:
	if item is Dictionary:
		return item
	if item is LMEntityDefinitionProp:
		var d: Dictionary = {"name": item.name}
		if not item.description.is_empty():
			d["comment"] = item.description
		if item.choices != null:
			d["choices"] = item.choices
			if item.type == "multi_choices":
				d["multi"] = true
		elif not item.type.is_empty():
			d["type"] = item.type
		return d
	return {}


static func _export_class_properties(clazz: Object, entity: Dictionary, ctx: SchemaContext) -> bool:
	if clazz.has_method("_export_entity_props"):
		var exported_props: Array = clazz.call("_export_entity_props")

		entity["description"] = LMCodeUtils.get_class_comment(clazz)
		var context := PropContext.new()

		var entity_prop_definition_array: Array[Dictionary] = []
		context.clazz = clazz
		context.entity_classname = entity.get("classname", "")
		context.godot_props = clazz.get_property_list()
		context.var_comments = LMCodeUtils.parse_comments_for_vars(clazz)

		for prop in exported_props:
			context.lm_prop = _lm_prop_to_dict(prop)
			if context.lm_prop.is_empty():
				continue
			var prop_def: Dictionary = {}
			if _process_lm_property(prop_def, context, ctx):
				entity_prop_definition_array.append(prop_def)

		entity.set("props", entity_prop_definition_array)
		return true
	else:
		return false

static func _vec3_str_godot_to_blender(s: String) -> String:
	var parts := s.split(",")
	if parts.size() != 3:
		return s
	var x := float(parts[0].strip_edges())
	var y := float(parts[1].strip_edges())
	var z := float(parts[2].strip_edges())
	return "%.6f,%.6f,%.6f" % [x, -z, y]

const _DIRECTIONAL_GIZMO_TYPES := ["arrow", "cone", "frustum"]

static func _compute_gizmo_euler_blender(g: LMEntityGizmoDef) -> String:
	var is_directional := g.type in _DIRECTIONAL_GIZMO_TYPES
	var user_basis := Basis.IDENTITY
	if not g.euler.is_empty():
		var parts := g.euler.split(",")
		if parts.size() == 3:
			var rx := deg_to_rad(float(parts[0].strip_edges()))
			var ry := deg_to_rad(float(parts[1].strip_edges()))
			var rz := deg_to_rad(float(parts[2].strip_edges()))
			user_basis = Basis.from_euler(Vector3(rx, ry, rz), EULER_ORDER_XYZ)

	if not is_directional and g.euler.is_empty():
		return ""

	var combined: Basis
	if is_directional:
		var base := Basis.from_euler(Vector3(PI / 2.0, 0.0, 0.0), EULER_ORDER_XYZ)
		combined = base * user_basis
	else:
		combined = user_basis

	var e := combined.get_euler(EULER_ORDER_XYZ)
	var bx := rad_to_deg(e.x)
	var by := rad_to_deg(e.y)
	var bz := rad_to_deg(e.z)
	return "%.6f,%.6f,%.6f" % [bx, bz, -by]

static func _serialize_gizmo(g: LMEntityGizmoDef) -> Dictionary:
	var d: Dictionary = {"type": g.type}
	if not g.radius.is_empty(): d["radius"] = g.radius
	if not g.length.is_empty(): d["length"] = g.length
	if not g.angle.is_empty():  d["angle"]  = g.angle
	if not g.fov.is_empty():    d["fov"]    = g.fov
	if not g.near.is_empty():   d["near"]   = g.near
	if not g.far.is_empty():    d["far"]    = g.far
	if not g.size.is_empty():   d["size"]   = g.size
	if not g.size_x.is_empty(): d["size_x"] = g.size_x
	if not g.size_y.is_empty(): d["size_y"] = g.size_y
	if not g.size_z.is_empty(): d["size_z"] = g.size_z
	if not g.icon.is_empty():   d["icon"]   = g.icon
	if not g.text.is_empty():   d["text"]   = g.text
	if not g.color.is_empty():  d["color"]  = g.color
	if not g.style.is_empty():  d["style"]  = g.style
	if not g.alpha.is_empty():  d["alpha"]  = g.alpha
	if not g.offset.is_empty(): d["offset"] = _vec3_str_godot_to_blender(g.offset)
	var euler_out := _compute_gizmo_euler_blender(g)
	if not euler_out.is_empty(): d["euler"] = euler_out
	if not g.mode.is_empty():   d["mode"]   = g.mode
	if not g.closed.is_empty(): d["closed"] = g.closed
	if not g.bindings.is_empty(): d["bindings"] = g.bindings
	return d

static func _bake_preview_model(node: Node, classname: String, out_entity: Dictionary, ctx: SchemaContext) -> void:
	var out_dir: String = ProjectSettings.get_setting(LMPlugin.CFG_KEY_WORKSPACE_FOLDER)
	var gltf_path := "%s/models/%s.glb" % [out_dir, classname]

	var fp: String = ""
	if ctx and ctx.sync_cache:
		var sources: Array = []
		var uid: String = out_entity.get("uid", "")
		if uid.begins_with("uid://"):
			sources.append(uid)
		fp = LMSyncCache.fingerprint(sources)
		if ctx.sync_cache.is_fresh(gltf_path, fp):
			out_entity["metadata"].set("model", classname)
			return

	if LMMeshUtils.bake_gltf_mesh_from_scene(node, gltf_path):
		out_entity["metadata"].set("model", classname)
		if ctx and ctx.sync_cache:
			ctx.sync_cache.record(gltf_path, fp)

static func _enrich_metadata_from_node(node: Node, out_entity: Dictionary, ctx: SchemaContext) -> void:
	if out_entity["metadata"].get("volume", false):
		return
	if out_entity.has("classname"):
		_bake_preview_model(node, out_entity["classname"], out_entity, ctx)

static func _read_entity_volume_flag(node: Node) -> bool:
	if node.has_method("_export_entity_volume"):
		return bool(node.call("_export_entity_volume"))
	return false

static func _create_lm_entity_definition_from_node_tree(root_node: Node, entity_desc: Dictionary, ctx: SchemaContext) -> void:
	_export_class_properties(root_node, entity_desc, ctx)
	if root_node.has_method("_export_entity_gizmos"):
		var raw: Array = root_node.call("_export_entity_gizmos")
		var gizmos_list: Array[Dictionary] = []
		for g in raw:
			if g is LMEntityGizmoDef and not g.type.is_empty():
				gizmos_list.append(_serialize_gizmo(g))
			elif g is Dictionary and g.has("type"):
				gizmos_list.append(g)
		if not gizmos_list.is_empty():
			entity_desc["metadata"]["gizmos"] = gizmos_list
	entity_desc["metadata"]["volume"] = _read_entity_volume_flag(root_node)
	_enrich_metadata_from_node(root_node, entity_desc, ctx)


static func scan_entity_infos(dirs: Array) -> Array[LMEntityScanResult]:
	var results: Array[LMEntityScanResult] = []
	for dir in dirs:
		if not dir or (dir as String).is_empty(): continue
		if not DirAccess.dir_exists_absolute(dir): continue
		_scan_infos_from_dir(dir, results)
	return results


static func _scan_infos_from_dir(dir: String, results: Array[LMEntityScanResult]) -> void:
	for file in DirAccess.get_files_at(dir):
		var r := _scan_info_from_path(dir.path_join(file))
		if r:
			results.append(r)
	for subdir in DirAccess.get_directories_at(dir):
		_scan_infos_from_dir(dir.path_join(subdir), results)


static func _scan_info_from_path(path: String) -> LMEntityScanResult:
	var ext := path.get_extension()
	var result := LMEntityScanResult.new()
	result.source_path = path

	if ext in ["tres", "res"]:
		var res := ResourceLoader.load(path)
		if not res is LMEntityDefinition:
			return null
		var def := res as LMEntityDefinition
		result.source_type = "definition"
		result.classname = def.entity_name if not def.entity_name.is_empty() \
			else path.get_file().get_basename()
		result.description = def.description
		result.entity_def = def
		for prop in def.properties:
			if not prop: continue
			var pd := {"name": prop.name, "type": prop.type, "description": prop.description}
			if prop.default_value != null:
				pd["default_value"] = prop.default_value
			result.props.append(pd)
		for g in def.gizmos:
			if g and not g.type.is_empty():
				result.gizmos.append(g)
		return result

	if not ext in ["gd", "tscn", "scn"]:
		return null

	var res: Resource = ResourceLoader.load(path)
	var obj: Object = null
	if res is PackedScene:
		obj = (res as PackedScene).instantiate()
		result.source_type = "scene"
	elif res is Script:
		obj = (res as Script).new()
		result.source_type = "script"

	if not obj or not obj.has_method("_export_entity_props"):
		if obj is Node: obj.free()
		return null

	var attached_script: Script = obj.get_script()
	if attached_script and not attached_script.resource_path.is_empty():
		result.script_path = attached_script.resource_path
	else:
		result.script_path = path

	result.classname = path.get_file().split(".")[0]
	result.description = LMCodeUtils.get_class_comment(obj)
	_fill_scan_props(obj, result)
	if obj.has_method("_export_entity_gizmos"):
		result.gizmos = obj.call("_export_entity_gizmos")
	if obj is Node: obj.free()
	return result


static func _fill_scan_props(obj: Object, result: LMEntityScanResult) -> void:
	var exported: Array = obj.call("_export_entity_props")
	var godot_props := obj.get_property_list()
	var var_comments := LMCodeUtils.parse_comments_for_vars(obj)

	for _raw_prop in exported:
		var lm_prop: Dictionary = _lm_prop_to_dict(_raw_prop)
		if not lm_prop.has("name"):
			continue
		var prop_name: String = lm_prop.name
		var gp_idx := godot_props.find_custom(func(p: Dictionary) -> bool: return p.name == prop_name)
		if gp_idx < 0:
			continue
		var gp: Dictionary = godot_props[gp_idx]

		var pd: Dictionary = {"name": prop_name}
		pd["description"] = lm_prop.get("comment", var_comments.get(prop_name, ""))

		if lm_prop.has("choices") and lm_prop["choices"]:
			var provider: LMChoicesProvider = lm_prop["choices"]
			var _type_key: Variant = provider.get("type_key")
			pd["type"] = "$%s%s" % [
				str(_type_key) if _type_key != null else "choices",
				"[]" if lm_prop.get("multi", false) else "",
			]
			var labels: Array[String] = []
			for c in provider.get_choices():
				var lbl: String = c.get("label", "")
				if not lbl.is_empty():
					labels.append(lbl)
			if not labels.is_empty():
				pd["choices_labels"] = labels
		elif lm_prop.has("type"):
			var t: Variant = lm_prop.type
			pd["type"] = type_string(t) if t is int else str(t)
			var val: Variant = obj.get(prop_name)
			if val != null:
				pd["default_value"] = val
		elif gp.hint == PROPERTY_HINT_ENUM:
			pd["type"] = "$%s" % gp.class_name
			pd["enum_hint_string"] = gp.hint_string
			var enum_labels: Array[String] = []
			for pair: String in gp.hint_string.split(","):
				var parts := pair.split(":")
				enum_labels.append(parts[0].strip_edges())
			if not enum_labels.is_empty():
				pd["choices_labels"] = enum_labels
			var val: Variant = obj.get(prop_name)
			if val != null:
				pd["default_value"] = val
		elif gp.hint == PROPERTY_HINT_FLAGS and not gp.hint_string.is_empty():
			var items: Dictionary = _parse_flags_hint(gp.hint_string)
			pd["type"] = "$%s.%s[]" % [result.classname, prop_name]
			var flag_labels: Array[String] = []
			for label in items:
				flag_labels.append(label)
			if not flag_labels.is_empty():
				pd["choices_labels"] = flag_labels
			var val: Variant = obj.get(prop_name)
			if val != null:
				pd["default_value"] = _mask_to_labels(int(val), items)
		elif _LAYER_HINTS.has(gp.hint):
			var items: Dictionary = _layer_hint_items(gp.hint)
			pd["type"] = "$%s[]" % _LAYER_HINTS[gp.hint][0]
			var layer_labels: Array[String] = []
			for label in items:
				layer_labels.append(label)
			pd["choices_labels"] = layer_labels
			var val: Variant = obj.get(prop_name)
			if val != null:
				pd["default_value"] = _mask_to_labels(int(val), items)
		else:
			pd["type"] = type_string(gp.type)
			var val: Variant = obj.get(prop_name)
			if val != null:
				pd["default_value"] = val
		result.props.append(pd)



static func _create_lm_entity_from_path(path: String, ctx: SchemaContext) -> void:
	var ext := path.get_extension()
	if ext in ["tres", "res"]:
		_create_entity_from_definition(path, ctx)
	elif ext in ["gd", "tscn", "scn"]:
		_create_entity_from_api_node(path, ctx)


static func _create_entity_from_definition(path: String, ctx: SchemaContext) -> void:
	var res := ResourceLoader.load(path)
	if not res is LMEntityDefinition:
		return
	var entity_def := res as LMEntityDefinition
	if entity_def.entity_name.is_empty():
		push_warning("Liminal Editor: LMEntityDefinition at %s has no entity_name. Skipping." % path)
		ctx.report.add_skipped(path, "LMEntityDefinition has no entity_name")
		return

	var out_entity: Dictionary = {}
	out_entity["classname"] = entity_def.entity_name
	out_entity["uid"] = entity_def.identifier
	out_entity["description"] = entity_def.description
	out_entity["metadata"] = {}
	out_entity["metadata"].set("volume", entity_def.has_volume)

	if not entity_def.gizmos.is_empty():
		var gizmos_list: Array[Dictionary] = []
		for g in entity_def.gizmos:
			if g and not g.type.is_empty():
				gizmos_list.append(_serialize_gizmo(g))
		if not gizmos_list.is_empty():
			out_entity["metadata"]["gizmos"] = gizmos_list

	var preview_node := _instantiate_from_identifier(entity_def.identifier)

	var props: Array[Dictionary] = []
	for prop in entity_def.properties:
		if not prop: continue
		var prop_dict: Dictionary = {}
		prop_dict["name"] = prop.name
		prop_dict["description"] = prop.description
		var default_value: Variant = prop.default_value
		if prop.type in ["choices", "multi_choices"]:
			var suffix: String = "[]" if prop.type == "multi_choices" else ""
			if prop.choices:
				_register_choices_provider(prop.choices, ctx)
				prop_dict["type"] = "$%s%s" % [prop.choices.type_key, suffix]
			else:
				var derived: Dictionary = _choices_from_backing(preview_node, prop.name, entity_def.entity_name)
				if derived.is_empty():
					push_warning("Liminal Editor: entity '%s' prop '%s' is %s but has neither a choices provider nor a hint-backed property to derive one from. Skipping prop." % [entity_def.entity_name, prop.name, prop.type])
					ctx.report.add_config_error("Entity '%s': prop '%s' is %s but has no choices provider and no matching enum/flags property on '%s' - prop not exported" % [entity_def.entity_name, prop.name, prop.type, entity_def.identifier])
					continue
				var key: String = derived["key"]
				if not ctx.choice_definitions.has(key):
					ctx.choice_definitions[key] = derived["items"]
				prop_dict["type"] = "$%s%s" % [key, suffix]
				if prop.type == "multi_choices" and (default_value is int or default_value is float):
					default_value = _mask_to_labels(int(default_value), derived["items"])
		else:
			prop_dict["type"] = prop.type
		if default_value != null:
			prop_dict["default_value"] = default_value
		props.append(prop_dict)
	out_entity["props"] = props

	if preview_node:
		_enrich_metadata_from_node(preview_node, out_entity, ctx)
		preview_node.free()

	ctx.entity_definitions.append(out_entity)
	ctx.report.add_entity(
		out_entity["classname"], "definition",
		out_entity.get("props", []).size(),
		out_entity["metadata"].get("gizmos", []).size(),
		out_entity["metadata"].has("model"),
		out_entity["metadata"].get("volume", false),
	)


static func _create_entity_from_api_node(path: String, ctx: SchemaContext) -> void:
	var uid_int := ResourceLoader.get_resource_uid(path)
	if uid_int == ResourceUID.INVALID_ID:
		push_warning("Liminal Editor: '%s' has no resource UID. Skipping." % path)
		ctx.report.add_skipped(path, "missing resource UID")
		return
	var uid := ResourceUID.id_to_text(uid_int)
	var node_template := _instantiate_from_identifier(uid)
	if not node_template:
		push_warning("Liminal Editor: failed to instantiate '%s'. Skipping." % path)
		ctx.report.add_skipped(path, "failed to instantiate scene/script")
		return
	if not node_template.has_method("_export_entity_props"):
		node_template.free()
		return

	var out_entity: Dictionary = {}
	out_entity["classname"] = path.get_file().split(".")[0]
	out_entity["uid"] = uid
	out_entity["metadata"] = {}
	_create_lm_entity_definition_from_node_tree(node_template, out_entity, ctx)
	node_template.free()
	ctx.entity_definitions.append(out_entity)
	ctx.report.add_entity(
		out_entity["classname"], "api",
		out_entity.get("props", []).size(),
		out_entity["metadata"].get("gizmos", []).size(),
		out_entity["metadata"].has("model"),
		out_entity["metadata"].get("volume", false),
	)


static func _instantiate_from_identifier(id: String) -> Node:
	if id.is_empty():
		return null
	if id.begins_with("uid://"):
		var uid_int := ResourceUID.text_to_id(id)
		if uid_int == ResourceUID.INVALID_ID:
			return null
		var res := ResourceLoader.load(ResourceUID.get_id_path(uid_int))
		if res is PackedScene:
			return (res as PackedScene).instantiate()
		if res is Script:
			var obj: Object = (res as Script).new()
			if obj is Node:
				return obj as Node
			if obj:
				obj.free()
		return null
	if ClassDB.class_exists(id):
		var obj: Object = ClassDB.instantiate(id)
		if obj is Node:
			return obj as Node
		if obj:
			obj.free()
	return null

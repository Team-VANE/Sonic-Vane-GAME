@tool
class_name LMMap extends Node3D
const AUTO_RELOAD_DELAY: float = 0.1
const DEFAULT_LIGHTMAP_TEXEL_SIZE: float = 0.2
const MAX_LIGHTMAP_TEXELS: float = 2048.0
const _COLLISION_COLORS := {
	&"SPHERE":   Color(0.0, 1.0, 0.0, 0.4),
	&"BOX":      Color(0.4, 1.0, 0.0, 0.4),
	&"CAPSULE":  Color(1.0, 1.0, 0.0, 0.4),
	&"CYLINDER": Color(1.0, 0.6, 0.0, 0.4),
	&"CONVEX":   Color(1.0, 0.3, 0.0, 0.4),
	&"CONCAVE":  Color(1.0, 0.0, 0.0, 0.4),
}

@export_file("*.lm") var map_path: String
@export var auto_reload: bool = true
@export_tool_button("Import") var setup_button = run_import

@export_group("World Geometry Defaults")
@export_flags_3d_physics var geo_collision_layer: int = 1
@export_flags_3d_physics var geo_collision_mask: int = 0
@export_flags_3d_render var geo_visibility_layer: int = 1
@export_enum("Disabled:0", "Static:1", "Dynamic:2") var geo_gi_mode: int = 1
@export var geo_default_material: Material
@export var geo_default_physics_material: PhysicsMaterial
@export_group("")
@export var hooks: LMMapHooks


var _auto_reload_time_left: float = 0
var _last_modification_timestamp: int = 0

var _top_child_fold_states: Dictionary[NodePath, bool]
var _json_entity_props: Dictionary = {}
var _json_types: Dictionary = {}

func _store_fold_state(n: Node) -> void:
	_top_child_fold_states[n.get_path()] = n.is_displayed_folded()
func _recall_fold_state(n: Node) -> void:
	if _top_child_fold_states.has(n.get_path()):
		n.set_display_folded(_top_child_fold_states[n.get_path()])

func _load_entities_json() -> bool:
	_json_entity_props.clear()
	_json_types.clear()
	var workspace: String = ProjectSettings.get_setting(LMPlugin.CFG_KEY_WORKSPACE_FOLDER, "")
	if workspace.is_empty():
		push_error("[LM] CFG_KEY_WORKSPACE_FOLDER is not set - cannot load entities.json")
		return false
	var json_path := workspace.path_join("entities.json")
	var file := FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_error("[LM] entities.json not found at '%s'. Regenerate from Liminal Editor → Export Definitions." % json_path)
		return false
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[LM] Failed to parse entities.json: %s" % json.get_error_message())
		return false
	var data: Dictionary = json.get_data()
	_json_types = data.get("types", {})
	for entity in data.get("entities", []):
		var classname: String = entity.get("classname", "")
		if classname.is_empty():
			continue
		var props: Dictionary = {}
		for prop in entity.get("props", []):
			props[prop["name"]] = prop
		_json_entity_props[classname] = props
	return true

func run_import() -> void:
	LMTimings.begin("lm_map_setup_" + name)
	LMTimings.start("load_entities_json")
	var loaded := _load_entities_json()
	LMTimings.stop("load_entities_json")
	if not loaded:
		LMTimings.finish()
		return
	for child in get_children(true):
		_store_fold_state(child)
		child.free()

	var doc: GLTFDocument = GLTFDocument.new()
	doc.get_supported_gltf_extensions()
	var state: GLTFState = GLTFState.new()

	var ext := LMGltfExtension.new()
	doc.register_gltf_document_extension(ext)
	doc.get_supported_gltf_extensions()

	LMTimings.start("gltf_parse")
	doc.append_from_file(map_path, state)
	LMTimings.stop("gltf_parse")
	LMTimings.start("generate_scene")
	var node: Node = doc.generate_scene(state)
	LMTimings.stop("generate_scene")
	doc.unregister_gltf_document_extension(ext)
	ext = null

	add_child(node)
	var interesting_nodes: Array[Node] = node.get_child(0).get_children()
	for n in interesting_nodes:
		n.reparent(self)
	setup(interesting_nodes)
	node.queue_free()
	LMTimings.finish()
	
func _is_vector_type(property: Dictionary) -> bool:
	return typeof(property["value"]) == TYPE_ARRAY && property["type"].to_lower() in ["color", "vector2", "vector2i", "vector3", "vector3i", "vector4", "vector4i"]
	
func _convert_vector_type(property: Dictionary) -> Variant:
	var ret: Variant
	match property["type"].to_lower():
		"vector2":
			ret = Vector2()
		"vector2i":
			ret = Vector2i()
		"vector3":
			ret = Vector3()
		"vector3i":
			ret = Vector3i()
		"vector4":
			ret = Vector4()
		"vector4i":
			ret = Vector4i()
		"color":
			ret = Color()
		_:
			return null
	
	for idx in property["value"].size():
		ret[idx] = property["value"][idx]
	return ret
	
func _resolve_choices_value(entity_instance: Node, prop_name: String, type_key: String, stored: Variant) -> Variant:
	if stored is int or stored is float:
		return int(stored)
	var type_map: Dictionary = _json_types.get(type_key, {})
	if type_map.is_empty():
		push_warning("[LM] Unknown choices type '%s' for prop '%s'" % [type_key, prop_name])
		return stored
	if not type_map.has(stored):
		push_warning("[LM] No entry '%s' in choices type '%s'" % [stored, type_key])
		return stored
	var resolved: Variant = type_map[stored]
	if resolved is String and (resolved.begins_with("res://") or resolved.begins_with("uid://")):
		for godot_prop in entity_instance.get_property_list():
			if godot_prop["name"] != prop_name:
				continue
			if godot_prop["type"] == TYPE_OBJECT:
				var res := ResourceLoader.load(resolved)
				if res:
					return res
				push_warning("[LM] Failed to load resource '%s' for prop '%s'" % [resolved, prop_name])
			elif godot_prop["type"] == TYPE_STRING:
				return resolved
			else:
				push_warning("[LM] Cannot assign resource path to prop '%s' (Godot type %d)" % [prop_name, godot_prop["type"]])
			return stored
		push_warning("[LM] Prop '%s' not found on entity" % prop_name)
		return stored
	return resolved

func _resolve_multi_choices_value(entity_instance: Node, prop_name: String, type_key: String, stored: Variant) -> Variant:
	if stored is not String:
		push_warning("[LM] Multi-choices prop '%s' expects a comma-separated string, got %s" % [prop_name, type_string(typeof(stored))])
		return stored
	var type_map: Dictionary = _json_types.get(type_key, {})
	if type_map.is_empty():
		push_warning("[LM] Unknown choices type '%s' for prop '%s'" % [type_key, prop_name])
		return stored
	var resolved: Array = []
	for label in (stored as String).split(",", false):
		label = label.strip_edges()
		if label.is_empty():
			continue
		if not type_map.has(label):
			push_warning("[LM] No entry '%s' in choices type '%s'" % [label, type_key])
			continue
		resolved.append(type_map[label])
	for godot_prop in entity_instance.get_property_list():
		if godot_prop["name"] != prop_name:
			continue
		match godot_prop["type"]:
			TYPE_INT:
				var mask: int = 0
				for v in resolved:
					if v is int or v is float:
						mask |= int(v)
					else:
						push_warning("[LM] Multi-choices prop '%s': non-numeric value '%s' cannot join an int bitmask" % [prop_name, str(v)])
				return mask
			TYPE_STRING, TYPE_STRING_NAME:
				var parts: PackedStringArray = []
				for v in resolved:
					parts.append(str(v))
				return ",".join(parts)
			TYPE_PACKED_STRING_ARRAY:
				var psa: PackedStringArray = []
				for v in resolved:
					psa.append(str(v))
				return psa
			TYPE_ARRAY:
				return resolved
			_:
				push_warning("[LM] Multi-choices prop '%s' targets unsupported Godot type %d" % [prop_name, godot_prop["type"]])
				return stored
	push_warning("[LM] Prop '%s' not found on entity" % prop_name)
	return stored

func apply_entity_properties(entity_instance: Node, entity_proxy: LMProxyEntity) -> void:
	if not entity_proxy.entity_data:
		return
	var data: Dictionary = entity_proxy.entity_data
	if not data.has("props"):
		return
	var classname: String = data.get("classname", "")
	var json_props: Dictionary = _json_entity_props.get(classname, {})
	for key in data["props"]:
		if key not in entity_instance:
			push_warning("[LM] Missing property %s::%s" % [classname, key])
			return
		var val: Variant
		if _is_vector_type(data["props"][key]):
			val = _convert_vector_type(data["props"][key])
			if typeof(val) == TYPE_NIL:
				push_warning("[LM] Imported property %s::%s has vector type %s but the value could not be converted to that type" % [classname, key, data["props"][key]["type"]])
				return
		else:
			val = data["props"][key]["value"]
			var prop_type: String = json_props.get(key, {}).get("type", "")
			if prop_type.begins_with("$"):
				if prop_type.ends_with("[]"):
					val = _resolve_multi_choices_value(entity_instance, key, prop_type.substr(1, prop_type.length() - 3), val)
				else:
					val = _resolve_choices_value(entity_instance, key, prop_type.substr(1), val)
		entity_instance.set(key, val)
				
func _find_parent_entity(node: Node) -> Node:
	var n: Node = node
	while n != self && n != get_tree().root:
		if n.has_meta("LM_ent"): return n
		n = n.get_parent()
	return null

func _map_lightmap_texel_size() -> float:
	var path: String = map_path
	if path.begins_with("uid://"):
		path = ResourceUID.uid_to_path(path)
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return DEFAULT_LIGHTMAP_TEXEL_SIZE
	return cfg.get_value("params", "lightmap/texel_size", DEFAULT_LIGHTMAP_TEXEL_SIZE)

func _load_asset_fresh() -> LMMapAsset:
	var asset: LMMapAsset = ResourceLoader.load(map_path, "", ResourceLoader.CACHE_MODE_REPLACE) as LMMapAsset
	if asset == null:
		return null
	var refreshed: Dictionary = {}
	for dict in [asset.meshes, asset.shapes]:
		for res in dict.values():
			if res == null:
				continue
			var path: String = res.resource_path
			if path.is_empty() or refreshed.has(path):
				continue
			refreshed[path] = true
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	LMTimings.note("cache files refreshed: %d" % refreshed.size())
	return asset


func setup(nodes: Array[Node]) -> void:
	var effective_owner: Node = owner if owner != null else self
	var processed_meshes: Array[StringName]
	LMTimings.start("asset_load")
	var asset: LMMapAsset = _load_asset_fresh()
	LMTimings.stop("asset_load")
	LMTimings.start("material_dict_build")
	var material_dict: Dictionary = build_material_dict()
	LMTimings.stop("material_dict_build")
	var lightmap_texel_size: float = _map_lightmap_texel_size()
	var physics_world := StaticBody3D.new()
	physics_world.name = "PhysicsWorld"
	physics_world.collision_layer = geo_collision_layer
	physics_world.collision_mask = geo_collision_mask
	if geo_default_physics_material != null:
		physics_world.physics_material_override = geo_default_physics_material
	add_child(physics_world)
	physics_world.owner = effective_owner
	_recall_fold_state(physics_world)
	var hk: LMMapHooks = hooks.duplicate() if hooks != null else null
	if hk:
		LMTimings.start("hooks")
		hk.on_setup_begin(self)
		LMTimings.stop("hooks")
	var node_queue = nodes
	var mesh_cache_hits := 0
	var mesh_finalize_fallbacks := 0
	var shape_cache_hits := 0
	var shape_build_fallbacks := 0
	var entities_instanced := 0
	LMTimings.start("node_walk_total")
	while !node_queue.is_empty():
		var n: Node = node_queue.pop_front()
		var process_children := false
		var next: Array[Node] = n.get_children()
		if n is ImporterMeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.transform = n.transform
			var imported_mesh: ArrayMesh = n.mesh.get_mesh()
			var cache_key: String = String(n.name)
			if asset and asset.meshes.has(cache_key):
				mi.mesh = asset.meshes[cache_key]
				mesh_cache_hits += 1
			else:
				mi.mesh = imported_mesh
				if imported_mesh.resource_name not in processed_meshes:
					processed_meshes.append(imported_mesh.resource_name)
					LMTimings.start("mesh_finalize_fallback")
					_finalize_mesh(imported_mesh, n.global_transform, material_dict, lightmap_texel_size)
					LMTimings.stop("mesh_finalize_fallback")
					mesh_finalize_fallbacks += 1
			mi.name = n.name
			var lm_geo_data = n.get_meta(&"LM_geo")
			var geo_tags: PackedStringArray = _geo_tags(lm_geo_data)
			var geo_xform: Transform3D = n.global_transform
			n.replace_by(mi)
			n = mi
			_apply_geo_mesh_defaults(mi)

			var shape: Shape3D
			var collision_type: String
			if lm_geo_data is Dictionary:
				if lm_geo_data.has("collision"):
					collision_type = lm_geo_data["collision"]
					if asset and asset.shapes.has(mi.name):
						shape = asset.shapes[mi.name]
						shape_cache_hits += 1
					else:
						LMTimings.start("shape_build_fallback")
						shape = _make_collision_shape(mi, collision_type)
						LMTimings.stop("shape_build_fallback")
						shape_build_fallbacks += 1

			if shape:
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.debug_color = _COLLISION_COLORS.get(collision_type, Color(1.0, 1.0, 1.0, 0.4))

				var default_body: CollisionObject3D = physics_world
				var created_entity_body: StaticBody3D = null
				var parent_entity: Node = _find_parent_entity(mi)
				if parent_entity:
					var collision_objects: Array = parent_entity.find_children("*", "CollisionObject3D")
					if !collision_objects.is_empty():
						default_body = collision_objects[0]
					else:
						created_entity_body = StaticBody3D.new()
						parent_entity.add_child(created_entity_body, true)
						created_entity_body.owner = effective_owner
						default_body = created_entity_body

				var target_body: CollisionObject3D = default_body
				if hk:
					LMTimings.start("hooks")
					target_body = hk.on_geo_body(self, mi, cs, default_body, geo_tags)
					LMTimings.stop("hooks")
				if created_entity_body and target_body != created_entity_body:
					created_entity_body.get_parent().remove_child(created_entity_body)
					created_entity_body.free()

				if target_body == null:
					cs.free()
				else:
					if target_body.get_parent() == null:
						add_child(target_body)
						target_body.owner = effective_owner
					target_body.add_child(cs)
					cs.owner = effective_owner
					cs.name = mi.name + "Collider"
					cs.global_transform = geo_xform
					cs.scale = Vector3(1,1,1)
					match collision_type:
						"SPHERE", "BOX", "CYLINDER", "CAPSULE":
							var aabb := mi.mesh.get_aabb()
							cs.position += geo_xform.basis * aabb.get_center()

					if hk:
						LMTimings.start("hooks")
						var kept_cs: CollisionShape3D = hk.on_geo_collision(self, mi, cs, geo_tags)
						LMTimings.stop("hooks")
						if kept_cs == null:
							cs.get_parent().remove_child(cs)
							cs.free()
						elif kept_cs != cs:
							cs.replace_by(kept_cs)
							kept_cs.owner = effective_owner
							cs.free()

			if hk:
				LMTimings.start("hooks")
				var kept: MeshInstance3D = hk.on_geo_mesh(self, mi, geo_tags)
				LMTimings.stop("hooks")
				if kept == null:
					_replace_geo_visual(mi, null)
					node_queue.append_array(next)
					continue
				elif kept != mi:
					_replace_geo_visual(mi, kept)
					n = kept

		elif n is LMProxyEntity:
			LMTimings.start("entity_instantiate")
			var en: Node3D = null
			var _ent_cn: String = n.entity_data.get("classname", "?") if n.entity_data is Dictionary else "?"
			if ClassDB.class_exists(n.uid):
				var inst: Variant = ClassDB.instantiate(n.uid)
				if inst is Node3D:
					en = inst
				else:
					push_warning("Instantiating non Node3D from LMProxy is unsupported")
					inst.free()
			else:
				if not ResourceLoader.exists(n.uid):
					push_error("LMMap: entity '%s' (classname=%s) — cannot resolve uid '%s'. The scene or script may have been deleted or renamed; re-export from Blender after fixing the reference." % [n.name, _ent_cn, n.uid])
				else:
					var res: Resource = ResourceLoader.load(n.uid)
					if res is PackedScene:
						en = res.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
					elif res is GDScript:
						en = res.new()
					else:
						push_error("LMMap: entity '%s' (classname=%s, uid=%s) loaded as '%s' — only PackedScene and Script are supported." % [n.name, _ent_cn, n.uid, res.get_class() if res else "null"])
			LMTimings.stop("entity_instantiate")
			entities_instanced += 1

			if en:
				var entity_scale: Vector3 = n.transform.basis.get_scale()
				var bake_scale: bool = en is CollisionObject3D and not entity_scale.is_equal_approx(Vector3.ONE)
				if n.mesh_data:
					var shape_node := CollisionShape3D.new()
					var trimesh: ConcavePolygonShape3D = n.mesh_data.create_trimesh_shape()
					if bake_scale:
						var faces: PackedVector3Array = trimesh.data
						for i in faces.size():
							faces[i] *= entity_scale
						trimesh.data = faces
					shape_node.shape = trimesh
					en.add_child(shape_node)
					shape_node.name = "ColliderShape3D_Trimesh"
					next.append(shape_node)
				var scene_path = en.scene_file_path
				en.transform = n.transform
				if bake_scale:
					en.scale = Vector3.ONE
					var scale_xform := Transform3D(Basis.from_scale(entity_scale), Vector3.ZERO)
					for child in n.get_children():
						if child is Node3D:
							child.transform = scale_xform * child.transform
				en.name = n.name
				n.replace_by(en)
				en.scene_file_path = scene_path
				LMTimings.start("apply_entity_properties")
				apply_entity_properties(en, n)
				LMTimings.stop("apply_entity_properties")
				var _desc: String = n.entity_data.get("description", "") if n.entity_data is Dictionary else ""
				if _desc:
					en.editor_description = _desc
				en.set_meta("LM_ent", {"uid": n.uid})
				if hk:
					LMTimings.start("hooks")
					var cn: String = n.entity_data.get("classname", "") if n.entity_data is Dictionary else ""
					hk.on_entity_ready(self, en, cn)
					LMTimings.stop("hooks")
				n = en
			else:
				push_error("LMMap: failed to produce a Node3D for entity '%s' (classname=%s, uid=%s) — see errors above." % [n.name, _ent_cn, n.uid])

		n.owner = effective_owner
		node_queue.append_array(next)
	LMTimings.stop("node_walk_total")
	LMTimings.note("mesh: %d cache-hit / %d finalize-fallback  shape: %d cache-hit / %d build-fallback  entities: %d" % [
		mesh_cache_hits, mesh_finalize_fallbacks, shape_cache_hits, shape_build_fallbacks, entities_instanced])
	if hk:
		LMTimings.start("hooks")
		hk.on_setup_complete(self)
		LMTimings.stop("hooks")
	EditorInterface.mark_scene_as_unsaved()


func _geo_tags(lm_geo_data) -> PackedStringArray:
	var out := PackedStringArray()
	if lm_geo_data is Dictionary and lm_geo_data.has("tags"):
		for t in lm_geo_data["tags"]:
			out.append(String(t))
	return out

func _apply_geo_mesh_defaults(mi: MeshInstance3D) -> void:
	mi.layers = geo_visibility_layer
	mi.gi_mode = geo_gi_mode
	if geo_default_material != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			if mi.get_active_material(i) == null:
				mi.set_surface_override_material(i, geo_default_material)

func _replace_geo_visual(old: MeshInstance3D, new_node: MeshInstance3D) -> void:
	if new_node != null:
		old.replace_by(new_node)
		return
	var parent: Node = old.get_parent()
	for c in old.get_children():
		c.reparent(parent, true)
	parent.remove_child(old)
	old.queue_free()

func _make_collision_shape(node: MeshInstance3D, type: String) -> Shape3D:
	return make_collision_shape(node.mesh, node.global_transform.basis.get_scale(), type)

static func make_collision_shape(mesh: ArrayMesh, scale: Vector3, type: String) -> Shape3D:
	match type:
		"CONCAVE":
			var s: ConcavePolygonShape3D = mesh.create_trimesh_shape()
			var faces: PackedVector3Array = s.data
			for i in faces.size():
				faces[i] *= scale
			s.data = faces
			return s
		"CONVEX":
			var s: ConvexPolygonShape3D = mesh.create_convex_shape()
			var points: PackedVector3Array = s.points
			for i in points.size():
				points[i] *= scale
			s.points = points
			return s
		"SPHERE":
			var aabb := mesh.get_aabb()
			var scaled_size := aabb.size * scale.abs()
			var s := SphereShape3D.new()
			s.radius = max(scaled_size.x, scaled_size.y, scaled_size.z) * 0.5
			return s
		"BOX":
			var aabb := mesh.get_aabb()
			var s := BoxShape3D.new()
			s.size = aabb.size * scale.abs()
			return s
		"CYLINDER":
			var aabb := mesh.get_aabb()
			var scaled_size := aabb.size * scale.abs()
			var s := CylinderShape3D.new()
			s.height = scaled_size.y
			s.radius = max(scaled_size.x, scaled_size.z) * 0.5
			return s
		"CAPSULE":
			var aabb := mesh.get_aabb()
			var scaled_size := aabb.size * scale.abs()
			var s := CapsuleShape3D.new()
			s.radius = max(scaled_size.x, scaled_size.z) * 0.5
			s.height = scaled_size.y
			return s
		_: return null

static func build_material_dict() -> Dictionary:
	var material_dict: Dictionary = {}
	var mat_dict: Dictionary = LMMaterialUtils.find_all_material_resources()
	for mat_key in mat_dict:
		for mat in mat_dict[mat_key]:
			material_dict[mat.get_basename().replace("/", "_")] = mat_key.path_join(mat)
	return material_dict

static func _mesh_surface_area(mesh: ArrayMesh, global_xform: Transform3D) -> float:
	var area: float = 0.0
	for surf_idx in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surf_idx) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(surf_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tri_count: int = indices.size() / 3 if indices.size() > 0 else verts.size() / 3
		for t in tri_count:
			var i0: int
			var i1: int
			var i2: int
			if indices.size() > 0:
				i0 = indices[t * 3]
				i1 = indices[t * 3 + 1]
				i2 = indices[t * 3 + 2]
			else:
				i0 = t * 3
				i1 = t * 3 + 1
				i2 = t * 3 + 2
			var a: Vector3 = global_xform * verts[i0]
			var b: Vector3 = global_xform * verts[i1]
			var c: Vector3 = global_xform * verts[i2]
			area += (b - a).cross(c - a).length() * 0.5
	return area

static func _lightmap_texel_size_for(mesh: ArrayMesh, global_xform: Transform3D, base_texel_size: float) -> float:
	var area: float = _mesh_surface_area(mesh, global_xform)
	if area <= 0.0:
		return base_texel_size
	var min_texel_size: float = sqrt(area) / MAX_LIGHTMAP_TEXELS
	return max(base_texel_size, min_texel_size)

static func _finalize_mesh(mesh: ArrayMesh, global_xform: Transform3D, material_dict: Dictionary, texel_size: float = DEFAULT_LIGHTMAP_TEXEL_SIZE) -> void:
	mesh.lightmap_unwrap(global_xform, _lightmap_texel_size_for(mesh, global_xform, texel_size))
	for surf_idx in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(surf_idx)
		var mat_name: String = mat.resource_name if mat else ""
		if mat_name.is_empty(): continue
		if material_dict.has(mat_name):
			var material_res: Resource = ResourceLoader.load(material_dict[mat_name])
			if !material_res:
				push_warning("[LM] Failed loading requested material: %s" % mat_name)
			elif material_res is not Material:
				push_warning("[LM] Resource is not material: %s" % mat_name)
			mesh.surface_set_material(surf_idx, material_res)
		else:
			push_warning("[LM] Couldn't find material: %s" % mat_name)

func _resources_reimported(resource_paths: PackedStringArray) -> void:
	if auto_reload:
		var asset_path: String = ResourceUID.uid_to_path(map_path)
		if asset_path in resource_paths:
			print("[LM] Auto reload: %s" % asset_path)
			run_import()

func _ready() -> void:
	if Engine.is_editor_hint():
		if !EditorInterface.get_resource_filesystem().resources_reimported.is_connected(_resources_reimported):
			EditorInterface.get_resource_filesystem().resources_reimported.connect(_resources_reimported)

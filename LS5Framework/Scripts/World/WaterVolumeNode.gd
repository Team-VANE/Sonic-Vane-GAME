@tool
extends Node3D

## Full extents of the water volume (width X, height Y, depth Z).
@export var size: Vector3 = Vector3(25000.0, 200.0, 20000.0):
	set(v):
		size = v
		_sync()

## Y position of the water surface plane relative to this node.
## Collision top face and visual mesh both sit at this Y.
@export var surface_y_offset: float = 0.0:
	set(v):
		surface_y_offset = v
		_sync()
## Fine-tune offset applied only to the collision top face.
## Use this to compensate for average wave displacement bias
## without moving the visual surface.
@export var collision_y_adjust: float = 0.0:
	set(v):
		collision_y_adjust = v
		_sync()

@export_group("Environmental Hazards")
## Physics layers containing enemies that can be defeated by water.
@export_flags_3d_physics var enemy_collision_mask: int = 128

@export_group("Underwater Tint")
## Override the default underwater camera tint when the camera is inside this volume.
@export var override_tint: bool = false
## Tint color used when override_tint is enabled.
@export var tint_color_override: Color = Color(0.05, 0.2, 0.5, 0.35)

@export_group("Water color")
## Surface color used at low fresnel angles.
@export var water_surface_color: Color = Color(0.0, 0.7316994, 0.88269347, 1.0):
	set(v):
		water_surface_color = v
		_push_shader_params()
## Surface color used at high fresnel angles.
@export var water_fresnel_color: Color = Color(0.8127987, 0.86050355, 0.97439605, 1.0):
	set(v):
		water_fresnel_color = v
		_push_shader_params()
## Water surface metallic value.
@export_range(0.0, 1.0, 0.01) var water_metallic: float = 0.0:
	set(v):
		water_metallic = v
		_push_shader_params()
## Water surface roughness value.
@export_range(0.0, 1.0, 0.01) var water_roughness: float = 0.02:
	set(v):
		water_roughness = v
		_push_shader_params()
## color used where water is shallow.
@export var water_shallow_color: Color = Color(0.41579995, 0.6932566, 0.77, 1.0):
	set(v):
		water_shallow_color = v
		_push_shader_params()
## color used where water is deep.
@export var water_deep_color: Color = Color(0.16016582, 0.2380532, 0.36666462, 1.0):
	set(v):
		water_deep_color = v
		_push_shader_params()
## color used for edge foam.
@export var water_edge_color: Color = Color(0.91, 1.0, 0.9925, 1.0):
	set(v):
		water_edge_color = v
		_push_shader_params()
## Distance from an edge where foam starts.
@export_range(0.0, 5.0, 0.01) var water_edge_start: float = 0.34:
	set(v):
		water_edge_start = v
		_push_shader_params()
## Thickness of the edge foam band.
@export_range(0.0, 5.0, 0.01) var water_edge_thickness: float = 3.65:
	set(v):
		water_edge_thickness = v
		_push_shader_params()
## Water surface transparency.
@export_range(0.0, 1.0, 0.01) var water_alpha: float = 0.85:
	set(v):
		water_alpha = v
		_push_shader_params()

@export_group("Water Depth Effects")
## Depth where shallow water color begins blending.
@export_range(0.0, 20.0, 0.05) var water_shallow_depth: float = 0.5:
	set(v):
		water_shallow_depth = v
		_push_shader_params()
## Depth where deep water color finishes blending.
@export_range(0.0, 200.0, 0.1) var water_deep_depth: float = 50.0:
	set(v):
		water_deep_depth = v
		_push_shader_params()
## Offset applied to sampled scene depth.
@export_range(-10.0, 10.0, 0.01) var water_depth_offset: float = 0.0:
	set(v):
		water_depth_offset = v
		_push_shader_params()
## Absorption strength for refracted scene color.
@export_range(0.0, 10.0, 0.05) var water_beers_law: float = 2.0:
	set(v):
		water_beers_law = v
		_push_shader_params()
## Strength of the edge foam blend.
@export_range(0.0, 2.0, 0.01) var water_edge_strength: float = 1.0:
	set(v):
		water_edge_strength = v
		_push_shader_params()
## Strength of screen-space refraction.
@export_range(0.0, 0.2, 0.001) var water_refraction_strength: float = 0.058:
	set(v):
		water_refraction_strength = v
		_push_shader_params()
## Mip level scale used for refracted scene color.
@export_range(0.0, 8.0, 0.05) var water_refraction_mip_scale: float = 2.5:
	set(v):
		water_refraction_mip_scale = v
		_push_shader_params()

@export_group("LOD")
## Enable LOD for large water bodies.
@export var large_water_body: bool = false:
	set(v):
		large_water_body = v
		_build_lod()
## Subdivisions across each LOD level. Values are rounded up to a multiple of four.
@export var inner_subdivisions: int = 256:
	set(v):
		inner_subdivisions = v
		_build_lod()
## Half-extent (X and Z) of the inner high-detail mesh in world units.
@export var inner_mesh_radius: float = 500.0:
	set(v):
		inner_mesh_radius = v
		_build_lod()
## Number of square LOD rings surrounding the inner high-detail mesh.
@export_range(1, 10, 1) var lod_ring_count: int = 6:
	set(v):
		lod_ring_count = v
		_build_lod()
## Inner-radius multiplier where geometric wave displacement begins fading.
@export_range(1.0, 16.0, 0.25) var lod_displacement_fade_start: float = 2.0:
	set(v):
		lod_displacement_fade_start = v
		_build_lod()
## Vertical AABB headroom for frustum culling.
@export var wave_aabb_half: float = 10.0:
	set(v):
		wave_aabb_half = v
		_build_lod()

@export_group("Wave")
## Height of wave displacement in world units.
@export var wave_height: float = 5.0:
	set(v):
		wave_height = v
		_push_shader_params()
## Vertical offset applied to the entire water surface.
@export var wave_height_offset: float = 0.0:
	set(v):
		wave_height_offset = v
		_push_shader_params()
## Speed of wave animation (time multiplier).
@export_range(0.0, 0.2, 0.005) var wave_speed: float = 0.025:
	set(v):
		wave_speed = v
		_push_shader_params()
## Noise tiling scale; larger values = coarser, choppier waves.
@export var wave_noise_scale: float = 10.0:
	set(v):
		wave_noise_scale = v
		_push_shader_params()
## Primary wave direction (XY maps to world XZ).
@export var wave_direction: Vector2 = Vector2(2.0, 0.0):
	set(v):
		wave_direction = v
		_push_shader_params()
## Secondary wave direction for cross-wave blending.
@export var wave_direction2: Vector2 = Vector2(0.0, 1.0):
	set(v):
		wave_direction2 = v
		_push_shader_params()

@export_group("Water Anti-Aliasing")
## Camera distance where fine normal detail begins fading.
@export_range(0.0, 10000.0, 10.0) var normal_detail_fade_start: float = 500.0:
	set(v):
		normal_detail_fade_start = v
		_push_shader_params()
## Camera distance where distant normal strength reaches its minimum.
@export_range(1.0, 20000.0, 10.0) var normal_detail_fade_end: float = 4000.0:
	set(v):
		normal_detail_fade_end = v
		_push_shader_params()
## Normal-map strength retained beyond the detail fade distance.
@export_range(0.0, 1.0, 0.01) var distant_normal_strength: float = 0.2:
	set(v):
		distant_normal_strength = v
		_push_shader_params()
## Roughness added where normal-map variance would cause specular aliasing.
@export_range(0.0, 2.0, 0.01) var specular_aa_strength: float = 0.35:
	set(v):
		specular_aa_strength = v
		_push_shader_params()
## Minimum water roughness at the normal detail fade distance.
@export_range(0.0, 1.0, 0.01) var distant_roughness: float = 0.3:
	set(v):
		distant_roughness = v
		_push_shader_params()
## Camera distance where custom screen-space reflections begin fading.
@export_range(0.0, 10000.0, 10.0) var ssr_camera_fade_start: float = 750.0:
	set(v):
		ssr_camera_fade_start = v
		_push_shader_params()
## Camera distance where custom screen-space reflections are fully faded.
@export_range(1.0, 20000.0, 10.0) var ssr_camera_fade_end: float = 3000.0:
	set(v):
		ssr_camera_fade_end = v
		_push_shader_params()
## Stable subsurface-scattering approximation used to support the water tint.
@export_range(0.0, 0.5, 0.005) var water_scatter_strength: float = 0.06:
	set(v):
		water_scatter_strength = v
		_push_shader_params()
## Camera distance where SDFGI irradiance begins blending into the stable fallback.
@export_range(0.0, 20000.0, 10.0) var gi_fallback_fade_start: float = 650.0:
	set(v):
		gi_fallback_fade_start = v
		_push_shader_params()
## Camera distance where stable fallback irradiance fully replaces SDFGI irradiance.
@export_range(1.0, 30000.0, 10.0) var gi_fallback_fade_end: float = 1300.0:
	set(v):
		gi_fallback_fade_end = v
		_push_shader_params()
## Diffuse irradiance used beyond SDFGI coverage while radiance reflections remain active.
@export_range(0.0, 2.0, 0.01) var gi_fallback_irradiance: float = 0.45:
	set(v):
		gi_fallback_irradiance = v
		_push_shader_params()
## Stable irradiance share used near the camera to soften internal SDFGI cascade transitions.
@export_range(0.0, 1.0, 0.01) var gi_fallback_near_blend: float = 0.35:
	set(v):
		gi_fallback_near_blend = v
		_push_shader_params()

## Explicit reference to the mesh node containing the water material.
## If null, the script will look for a child named "Water_Visual".
@export var water_mesh_node: MeshInstance3D:
	set(v):
		water_mesh_node = v
		_material = null
		_push_shader_params()

## Fallback water material used when the authored visual or preview has no material.
@export var water_material: ShaderMaterial:
	set(v):
		water_material = v
		_material = null
		_material_source = null
		_push_shader_params()

@export_group("Rendering")
## Disable water mesh participation in SDFGI and other global illumination.
@export var exclude_from_sdfgi: bool = false:
	set(v):
		exclude_from_sdfgi = v
		_refresh_water_mesh_settings()

@export_group("Editor Preview")
## Show a water surface preview in the editor.
@export var show_editor_preview: bool = true:
	set(v):
		show_editor_preview = v
		_sync()
## Subdivisions used by the editor preview mesh.
@export var editor_preview_subdivisions: int = 32:
	set(v):
		editor_preview_subdivisions = v
		_sync()

var _material: Material = null
var _material_source: Material = null
var _lod_root: Node3D = null
var _lod_mesh: MeshInstance3D = null
var _editor_preview: MeshInstance3D = null
var _last_cam_pos: Vector3 = Vector3(1e9, 1e9, 1e9)

const WATER_SURFACE_THICKNESS: float = 0.1
const WATER_SURFACE_RAY_LAYER: int = 32


func _node_is_under_lod_root(node: Node) -> bool:
	if _lod_root == null or node == null:
		return false
	var p: Node = node.get_parent()
	while p != null:
		if p == _lod_root:
			return true
		p = p.get_parent()
	return false


func _free_node_now(node: Node) -> void:
	if node == null:
		return
	if not is_instance_valid(node):
		return
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


func _cache_material_from_mesh(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null:
		return
	if water_material != null:
		return
	var src_mat: Material = mesh_node.get_surface_override_material(0)
	if src_mat == null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
		src_mat = mesh_node.mesh.surface_get_material(0)
	if src_mat is ShaderMaterial:
		water_material = src_mat
		_material = src_mat


func _configure_water_mesh(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null:
		return
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if exclude_from_sdfgi:
		mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	elif mesh_node == _lod_mesh or mesh_node.name == "_WaterClipmap":
		mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	else:
		mesh_node.gi_mode = GeometryInstance3D.GI_MODE_STATIC


func _refresh_water_mesh_settings() -> void:
	if _lod_mesh != null and is_instance_valid(_lod_mesh):
		_configure_water_mesh(_lod_mesh)
	if _editor_preview != null and is_instance_valid(_editor_preview):
		_configure_water_mesh(_editor_preview)
	var visual_node: MeshInstance3D = get_node_or_null("Water_Visual")
	if visual_node != null:
		_configure_water_mesh(visual_node)


func _get_collision_top_y(collision: CollisionShape3D = null) -> float:
	var collision_node: CollisionShape3D = collision
	if collision_node == null:
		collision_node = get_node_or_null("Area3D/CollisionShape3D")
	if collision_node == null:
		return surface_y_offset + collision_y_adjust
	var box_shape: BoxShape3D = collision_node.shape as BoxShape3D
	if box_shape == null:
		return collision_node.position.y
	return collision_node.position.y + box_shape.size.y * 0.5


func _remove_editor_preview() -> void:
	if _editor_preview != null and is_instance_valid(_editor_preview):
		_free_node_now(_editor_preview)
	_editor_preview = null
	var found_preview: Node = get_node_or_null("Water_EditorPreview")
	if found_preview != null:
		_free_node_now(found_preview)


func _sync_editor_preview(collision: CollisionShape3D = null) -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		_remove_editor_preview()
		return
	if not show_editor_preview:
		_remove_editor_preview()
		return
	if _editor_preview == null or not is_instance_valid(_editor_preview):
		_editor_preview = get_node_or_null("Water_EditorPreview") as MeshInstance3D
	if _editor_preview == null:
		_editor_preview = MeshInstance3D.new()
		_editor_preview.name = "Water_EditorPreview"
		_editor_preview.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(_editor_preview)
		_editor_preview.owner = owner
	_configure_water_mesh(_editor_preview)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size.x, size.z)
	mesh.subdivide_width = max(editor_preview_subdivisions, 1)
	mesh.subdivide_depth = max(editor_preview_subdivisions, 1)
	_editor_preview.mesh = mesh
	_editor_preview.position = Vector3(0.0, _get_collision_top_y(collision), 0.0)
	_editor_preview.visible = true
	if not (_material is ShaderMaterial):
		_cache_material()
	if _material != null and _editor_preview.is_inside_tree():
		_editor_preview.set_surface_override_material(0, _material)
	_push_instance_shader_params(_editor_preview)


func _push_instance_shader_params(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null:
		return
	if not mesh_node.is_inside_tree():
		return
	mesh_node.set_instance_shader_parameter("height_scale", wave_height)
	mesh_node.set_instance_shader_parameter("clipmap_lod_scale", float(maxi(lod_ring_count, 1)) if mesh_node == _lod_mesh else 0.0)
	mesh_node.set_instance_shader_parameter("clipmap_inner_radius", maxf(inner_mesh_radius, 1.0) if mesh_node == _lod_mesh else 0.0)
	mesh_node.set_instance_shader_parameter(
		"clipmap_outer_radius",
		maxf(inner_mesh_radius, 1.0) * pow(2.0, float(maxi(lod_ring_count, 1))) if mesh_node == _lod_mesh else 0.0
	)
	mesh_node.set_instance_shader_parameter(
		"clipmap_displacement_fade_start",
		maxf(inner_mesh_radius, 1.0) * maxf(lod_displacement_fade_start, 1.0) if mesh_node == _lod_mesh else 0.0
	)


func _remove_large_water_preview_meshes() -> void:
	if not large_water_body:
		return
	var remove_nodes: Array[Node] = []
	if is_instance_valid(water_mesh_node):
		remove_nodes.append(water_mesh_node)
	var direct_visual: Node = get_node_or_null("Water_Visual")
	if direct_visual != null:
		remove_nodes.append(direct_visual)
	for child in get_children():
		if child is MeshInstance3D:
			remove_nodes.append(child)
	for found in find_children("Water_Visual", "MeshInstance3D", true, false):
		remove_nodes.append(found)
	for node in remove_nodes:
		if not is_instance_valid(node):
			continue
		if node.is_queued_for_deletion():
			continue
		if not (node is MeshInstance3D):
			continue
		if node == _lod_mesh:
			continue
		if node == _editor_preview or node.name == "Water_EditorPreview":
			continue
		if _node_is_under_lod_root(node):
			continue
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		_cache_material_from_mesh(mesh_node)
		if mesh_node == water_mesh_node:
			water_mesh_node = null
		mesh_node.visible = false
		mesh_node.material_override = null
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			mesh_node.set_surface_override_material(0, null)
		mesh_node.mesh = null
		_free_node_now(mesh_node)


func _ready() -> void:
	# Capture the authored material before runtime LOD mode removes Water_Visual.
	_cache_material()
	_sync()
	if Engine.is_editor_hint():
		return
	var water_area: Area3D = get_node_or_null("Area3D") as Area3D
	if water_area != null:
		water_area.collision_mask = water_area.collision_mask | enemy_collision_mask
		if not water_area.body_entered.is_connected(_on_water_body_entered):
			water_area.body_entered.connect(_on_water_body_entered)
		call_deferred("_register_existing_enemy_water_overlaps", water_area)
	_remove_editor_preview()
	_build_lod()
	_push_shader_params()


func _register_existing_enemy_water_overlaps(water_area: Area3D) -> void:
	if water_area == null or not is_instance_valid(water_area):
		return
	for body: Node3D in water_area.get_overlapping_bodies():
		_on_water_body_entered(body)


func _on_water_body_entered(body: Node3D) -> void:
	if body == null or not body.has_method("apply_environmental_hazard"):
		return
	body.call("apply_environmental_hazard", &"water", self)


func _process(_delta: float) -> void:
	if not large_water_body:
		return

	var cam: Camera3D = null
	if Engine.is_editor_hint():
		# In Godot 4 editor, the active camera can be found through the viewport.
		var viewport = get_viewport()
		if viewport:
			cam = viewport.get_camera_3d()
	else:
		var vp := get_viewport()
		if vp != null:
			cam = vp.get_camera_3d()
	
	if cam == null:
		return
		
	var cam_pos: Vector3 = cam.global_position
	# If we are in the editor, we don't want to update _last_cam_pos in a way that
	# prevents the first-frame sync.
	if cam_pos.distance_squared_to(_last_cam_pos) > 0.01:
		_last_cam_pos = cam_pos
		_follow_camera(cam_pos)


func _follow_camera(cam_pos: Vector3) -> void:
	var cam_local: Vector3 = to_local(cam_pos)
	var vertex_spacing: float = (maxf(inner_mesh_radius, 1.0) * 2.0) / float(_get_clipmap_subdivisions())
	var snapped_x: float = round(cam_local.x / vertex_spacing) * vertex_spacing
	var snapped_z: float = round(cam_local.z / vertex_spacing) * vertex_spacing

	var visual_node: MeshInstance3D = get_node_or_null("Water_Visual")

	if not large_water_body:
		if visual_node != null:
			_configure_water_mesh(visual_node)
			visual_node.position = Vector3(0.0, surface_y_offset, 0.0)
			visual_node.visible = not (Engine.is_editor_hint() and show_editor_preview)
		return

	_remove_large_water_preview_meshes()

	# Moving by a full inner-grid cell preserves the high-detail sample lattice.
	if _lod_root != null:
		_lod_root.position = Vector3(snapped_x, 0.0, snapped_z)


func _cache_material() -> void:
	var src_mat: Material = null
	if large_water_body:
		var preview_node: MeshInstance3D = get_node_or_null("Water_EditorPreview") as MeshInstance3D
		if preview_node != null:
			src_mat = preview_node.get_surface_override_material(0)
			if src_mat == null and preview_node.mesh != null and preview_node.mesh.get_surface_count() > 0:
				src_mat = preview_node.mesh.surface_get_material(0)
			if src_mat == _material and _material_source != null:
				src_mat = _material_source
	if src_mat == null:
		var visual_node: MeshInstance3D = water_mesh_node if is_instance_valid(water_mesh_node) else null
		if visual_node == null:
			visual_node = get_node_or_null("Water_Visual") as MeshInstance3D
		if visual_node != null:
			src_mat = visual_node.get_surface_override_material(0)
			if src_mat == null and visual_node.mesh != null and visual_node.mesh.get_surface_count() > 0:
				src_mat = visual_node.mesh.surface_get_material(0)
			if src_mat == _material and _material_source != null:
				src_mat = _material_source
	if src_mat == null:
		src_mat = water_material
	
	if src_mat == null:
		return

	if water_material == null:
		water_material = src_mat

	if src_mat is ShaderMaterial:
		if _material_source != src_mat or not (_material is ShaderMaterial):
			_material_source = src_mat
			_material = (src_mat as ShaderMaterial).duplicate(true) as ShaderMaterial
	else:
		_material_source = src_mat
		_material = src_mat

	_apply_materials_to_meshes()


func _apply_materials_to_meshes() -> void:
	if _lod_mesh != null and _lod_mesh.is_inside_tree() and _lod_mesh.mesh != null:
		_lod_mesh.set_surface_override_material(0, _material)
	
	# If not in LOD mode, apply to the preview mesh.
	if not large_water_body:
		var visual_node: MeshInstance3D = get_node_or_null("Water_Visual")
		if visual_node != null and visual_node.is_inside_tree() and visual_node.mesh != null:
			visual_node.set_surface_override_material(0, _material)
	
	if _editor_preview != null and _editor_preview.is_inside_tree() and _editor_preview.mesh != null:
		_editor_preview.set_surface_override_material(0, _material)


var _pushing: bool = false
func _push_shader_params() -> void:
	if not is_inside_tree(): return
	if _pushing: return
	_pushing = true
	
	_cache_material()
	
	if not (_material is ShaderMaterial):
		_pushing = false
		return
		
	var sm: ShaderMaterial = _material as ShaderMaterial
	
	sm.set_shader_parameter("height_offset", wave_height_offset)
	sm.set_shader_parameter("time_scale", wave_speed)
	sm.set_shader_parameter("noise_scale", wave_noise_scale)
	sm.set_shader_parameter("wave_direction", wave_direction)
	sm.set_shader_parameter("wave_direction2", wave_direction2)
	sm.set_shader_parameter("albedo", water_surface_color)
	sm.set_shader_parameter("albedo2", water_fresnel_color)
	sm.set_shader_parameter("metallic", water_metallic)
	sm.set_shader_parameter("roughness", water_roughness)
	sm.set_shader_parameter("color_shallow", water_shallow_color)
	sm.set_shader_parameter("color_deep", water_deep_color)
	sm.set_shader_parameter("shallow_depth", water_shallow_depth)
	sm.set_shader_parameter("deep_depth", water_deep_depth)
	sm.set_shader_parameter("depth_offset", water_depth_offset)
	sm.set_shader_parameter("beers_law", water_beers_law)
	sm.set_shader_parameter("edge_color", water_edge_color)
	sm.set_shader_parameter("edge_start", water_edge_start)
	sm.set_shader_parameter("edge_width", water_edge_thickness)
	sm.set_shader_parameter("edge_strength", water_edge_strength)
	sm.set_shader_parameter("refraction_strength", water_refraction_strength)
	sm.set_shader_parameter("refraction_mip_scale", water_refraction_mip_scale)
	sm.set_shader_parameter("alpha", water_alpha)
	sm.set_shader_parameter("normal_detail_fade_start", normal_detail_fade_start)
	sm.set_shader_parameter("normal_detail_fade_end", normal_detail_fade_end)
	sm.set_shader_parameter("distant_normal_strength", distant_normal_strength)
	sm.set_shader_parameter("specular_aa_strength", specular_aa_strength)
	sm.set_shader_parameter("distant_roughness", distant_roughness)
	sm.set_shader_parameter("ssr_camera_fade_start", ssr_camera_fade_start)
	sm.set_shader_parameter("ssr_camera_fade_end", ssr_camera_fade_end)
	sm.set_shader_parameter("water_scatter_strength", water_scatter_strength)
	sm.set_shader_parameter("gi_fallback_fade_start", gi_fallback_fade_start)
	sm.set_shader_parameter("gi_fallback_fade_end", gi_fallback_fade_end)
	sm.set_shader_parameter("gi_fallback_irradiance", gi_fallback_irradiance)
	sm.set_shader_parameter("gi_fallback_near_blend", gi_fallback_near_blend)
	
	if _lod_mesh != null and _lod_mesh.is_inside_tree():
		_push_instance_shader_params(_lod_mesh)

	if not large_water_body:
		var vn: MeshInstance3D = get_node_or_null("Water_Visual")
		if vn != null and vn.is_inside_tree():
			_push_instance_shader_params(vn)
	
	if _editor_preview != null and _editor_preview.is_inside_tree():
		_push_instance_shader_params(_editor_preview)

	_pushing = false


func _build_lod() -> void:
	if not (_material is ShaderMaterial):
		_cache_material()
	
	var aabb_h: float = maxf(wave_aabb_half, 1.0)

	if _lod_root != null:
		_free_node_now(_lod_root)
		_lod_root = null
		_lod_mesh = null

	_remove_large_water_preview_meshes()

	# In non-LOD mode, Water_Visual stays as a full-volume mesh on the node root.
	var visual_node: MeshInstance3D = get_node_or_null("Water_Visual")

	if not large_water_body:
		if visual_node != null:
			var mesh: PlaneMesh = PlaneMesh.new()
			mesh.size = Vector2(size.x, size.z)
			mesh.subdivide_width = inner_subdivisions
			mesh.subdivide_depth = inner_subdivisions
			_configure_water_mesh(visual_node)
			if _material != null and visual_node.is_inside_tree():
				visual_node.set_surface_override_material(0, _material)
			visual_node.mesh = mesh
			visual_node.custom_aabb = AABB(
				Vector3(-size.x * 0.5, -aabb_h, -size.z * 0.5),
				Vector3(size.x, aabb_h * 2.0, size.z)
			)
			visual_node.position = Vector3(0.0, surface_y_offset, 0.0)
			visual_node.visible = not (Engine.is_editor_hint() and show_editor_preview)
			_sync_editor_preview()
		return

	# LOD mode uses a stitched clipmap that follows the camera on the inner grid.
	_lod_root = Node3D.new()
	_lod_root.name = "_LodRoot"
	add_child(_lod_root)

	_remove_large_water_preview_meshes()

	var clipmap_radius: float = maxf(inner_mesh_radius, 1.0) * pow(2.0, float(maxi(lod_ring_count, 1)))
	var clipmap_mi: MeshInstance3D = MeshInstance3D.new()
	clipmap_mi.name = "_WaterClipmap"
	clipmap_mi.mesh = _create_clipmap_mesh()
	_configure_water_mesh(clipmap_mi)
	clipmap_mi.custom_aabb = AABB(
		Vector3(-clipmap_radius, -aabb_h, -clipmap_radius),
		Vector3(clipmap_radius * 2.0, aabb_h * 2.0, clipmap_radius * 2.0)
	)
	clipmap_mi.position = Vector3(0.0, surface_y_offset, 0.0)
	_lod_root.add_child(clipmap_mi)
	_lod_mesh = clipmap_mi
	_last_cam_pos = Vector3(1e9, 1e9, 1e9)
	
	_cache_material()
	_push_shader_params()
	_sync_editor_preview()


func _create_clipmap_mesh() -> Mesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var subdivisions: int = _get_clipmap_subdivisions()
	var center_radius: float = maxf(inner_mesh_radius, 1.0)
	var center_cell_size: float = center_radius * 2.0 / float(subdivisions)
	var ring_count: int = maxi(lod_ring_count, 1)
	var outer_radius: float = center_radius * pow(2.0, float(ring_count))
	var fade_start_radius: float = minf(center_radius * maxf(lod_displacement_fade_start, 1.0), outer_radius)

	_append_clipmap_grid(st, center_radius, center_cell_size, subdivisions, outer_radius, fade_start_radius)
	for level in range(1, ring_count + 1):
		var level_scale: float = pow(2.0, float(level))
		var ring_inner_radius: float = center_radius * level_scale * 0.5
		var ring_outer_radius: float = center_radius * level_scale
		var ring_cell_size: float = center_cell_size * level_scale
		_append_clipmap_ring(
			st,
			ring_inner_radius,
			ring_outer_radius,
			ring_cell_size,
			subdivisions,
			outer_radius,
			fade_start_radius
		)

	st.index()
	return st.commit()


func _get_clipmap_subdivisions() -> int:
	var subdivisions: int = maxi(inner_subdivisions, 4)
	if subdivisions % 4 != 0:
		subdivisions += 4 - subdivisions % 4
	return subdivisions


func _append_clipmap_grid(
	st: SurfaceTool,
	radius: float,
	cell_size: float,
	subdivisions: int,
	outer_radius: float,
	fade_start_radius: float
) -> void:
	for z_index in range(subdivisions):
		var z0: float = -radius + float(z_index) * cell_size
		var z1: float = z0 + cell_size
		for x_index in range(subdivisions):
			var x0: float = -radius + float(x_index) * cell_size
			var x1: float = x0 + cell_size
			_append_clipmap_quad(
				st,
				Vector2(x0, z0),
				Vector2(x1, z0),
				Vector2(x1, z1),
				Vector2(x0, z1),
				outer_radius,
				fade_start_radius
			)


func _append_clipmap_ring(
	st: SurfaceTool,
	inner_radius: float,
	outer_radius: float,
	cell_size: float,
	subdivisions: int,
	clipmap_radius: float,
	fade_start_radius: float
) -> void:
	var hole_min: int = floori(float(subdivisions) / 4.0)
	var hole_max: int = subdivisions - hole_min
	for z_index in range(subdivisions):
		for x_index in range(subdivisions):
			var inside_hole_x: bool = x_index >= hole_min and x_index < hole_max
			var inside_hole_z: bool = z_index >= hole_min and z_index < hole_max
			if inside_hole_x and inside_hole_z:
				continue

			var x0: float = -outer_radius + float(x_index) * cell_size
			var x1: float = x0 + cell_size
			var z0: float = -outer_radius + float(z_index) * cell_size
			var z1: float = z0 + cell_size
			var corners: Array[Vector2] = [
				Vector2(x0, z0),
				Vector2(x1, z0),
				Vector2(x1, z1),
				Vector2(x0, z1),
			]

			if z_index == hole_max and inside_hole_x:
				corners.insert(1, Vector2((x0 + x1) * 0.5, inner_radius))
			elif x_index == hole_min - 1 and inside_hole_z:
				corners.insert(2, Vector2(-inner_radius, (z0 + z1) * 0.5))
			elif z_index == hole_min - 1 and inside_hole_x:
				corners.insert(3, Vector2((x0 + x1) * 0.5, -inner_radius))
			elif x_index == hole_max and inside_hole_z:
				corners.append(Vector2(inner_radius, (z0 + z1) * 0.5))

			if corners.size() == 4:
				_append_clipmap_quad(
					st,
					corners[0],
					corners[1],
					corners[2],
					corners[3],
					clipmap_radius,
					fade_start_radius
				)
			else:
				_append_clipmap_polygon(st, corners, clipmap_radius, fade_start_radius)


func _append_clipmap_quad(
	st: SurfaceTool,
	p00: Vector2,
	p10: Vector2,
	p11: Vector2,
	p01: Vector2,
	outer_radius: float,
	fade_start_radius: float
) -> void:
	_append_clipmap_vertex(st, p00, outer_radius, fade_start_radius)
	_append_clipmap_vertex(st, p10, outer_radius, fade_start_radius)
	_append_clipmap_vertex(st, p11, outer_radius, fade_start_radius)
	_append_clipmap_vertex(st, p00, outer_radius, fade_start_radius)
	_append_clipmap_vertex(st, p11, outer_radius, fade_start_radius)
	_append_clipmap_vertex(st, p01, outer_radius, fade_start_radius)


func _append_clipmap_polygon(
	st: SurfaceTool,
	points: Array[Vector2],
	outer_radius: float,
	fade_start_radius: float
) -> void:
	var center: Vector2 = Vector2.ZERO
	for point in points:
		center += point
	center /= float(points.size())
	for point_index in range(points.size()):
		var next_index: int = (point_index + 1) % points.size()
		_append_clipmap_vertex(st, center, outer_radius, fade_start_radius)
		_append_clipmap_vertex(st, points[point_index], outer_radius, fade_start_radius)
		_append_clipmap_vertex(st, points[next_index], outer_radius, fade_start_radius)


func _append_clipmap_vertex(
	st: SurfaceTool,
	point: Vector2,
	_outer_radius: float,
	_fade_start_radius: float
) -> void:
	st.set_normal(Vector3.UP)
	st.set_tangent(Plane(1.0, 0.0, 0.0, -1.0))
	st.set_uv(point)
	st.add_vertex(Vector3(point.x, 0.0, point.y))


func _get_or_create_water_surface_body(create_if_missing: bool = true) -> StaticBody3D:
	var surface_body: StaticBody3D = get_node_or_null("WaterSurface") as StaticBody3D
	if surface_body == null:
		if not create_if_missing:
			return null
		surface_body = StaticBody3D.new()
		surface_body.name = "WaterSurface"
		add_child(surface_body)
		if owner != null:
			surface_body.owner = owner
	if surface_body.is_in_group("water"):
		surface_body.remove_from_group("water")
	if not surface_body.is_in_group("water_surface"):
		surface_body.add_to_group("water_surface")
	return surface_body


func _get_or_create_water_surface_collision(surface_body: StaticBody3D, create_if_missing: bool = true) -> CollisionShape3D:
	if surface_body == null:
		return null
	var surface_col: CollisionShape3D = surface_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if surface_col == null:
		if not create_if_missing:
			return null
		surface_col = CollisionShape3D.new()
		surface_col.name = "CollisionShape3D"
		surface_body.add_child(surface_col)
		if owner != null:
			surface_col.owner = owner
	return surface_col


func _sync_water_surface() -> void:
	var create_if_missing: bool = not Engine.is_editor_hint()
	var surface_body: StaticBody3D = _get_or_create_water_surface_body(create_if_missing)
	var surface_col: CollisionShape3D = _get_or_create_water_surface_collision(surface_body, create_if_missing)
	if surface_body == null or surface_col == null:
		return
	surface_body.collision_layer = WATER_SURFACE_RAY_LAYER
	surface_body.collision_mask = 0
	var shape: BoxShape3D = surface_col.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		surface_col.shape = shape
	shape.size = Vector3(size.x, WATER_SURFACE_THICKNESS, size.z)
	surface_col.position = Vector3(0.0, surface_y_offset + collision_y_adjust - WATER_SURFACE_THICKNESS * 0.5, 0.0)
	surface_col.disabled = false


func _sync() -> void:
	var collision: CollisionShape3D = get_node_or_null("Area3D/CollisionShape3D")

	if large_water_body:
		_remove_large_water_preview_meshes()

	var visual_node: MeshInstance3D = get_node_or_null("Water_Visual")
	if visual_node != null:
		if large_water_body:
			_remove_large_water_preview_meshes()
		else:
			var mesh := PlaneMesh.new()
			mesh.subdivide_width = inner_subdivisions
			mesh.subdivide_depth = inner_subdivisions
			mesh.size = Vector2(size.x, size.z)
			_configure_water_mesh(visual_node)
			visual_node.mesh = mesh
			visual_node.position = Vector3(0.0, surface_y_offset, 0.0)
			visual_node.visible = not (Engine.is_editor_hint() and show_editor_preview)
			if not (_material is ShaderMaterial):
				_cache_material()
			if _material != null and visual_node.is_inside_tree():
				visual_node.set_surface_override_material(0, _material)

	if collision != null:
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = Vector3(0.0, surface_y_offset - size.y * 0.5 + collision_y_adjust, 0.0)

	_sync_water_surface()
	_sync_editor_preview(collision)
	_push_shader_params()

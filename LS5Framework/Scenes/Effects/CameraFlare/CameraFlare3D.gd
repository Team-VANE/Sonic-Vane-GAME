extends Node3D
class_name CameraFlare3D

@export_group("Source")
## Enables visibility testing and camera flare rendering.
@export var enabled: bool = true
## Node producing the flare. Empty uses this node; the reusable scene defaults to its parent.
@export_node_path("Node3D") var source_path: NodePath = NodePath("..")
## Uses the source's world positive Z axis as an infinitely distant source direction.
@export var directional: bool = false
## Local offset from a finite source's origin.
@export var source_offset: Vector3 = Vector3.ZERO
## Camera receiving the effect. Empty follows the active camera in this viewport.
@export_node_path("Camera3D") var camera_path: NodePath
## Overall effect strength, including sun, lens elements, and bleach.
@export_range(0.0, 2.0, 0.01) var intensity: float = 1.0
## Light energy required for full intensity when the source is a Light3D.
@export_range(0.001, 16.0, 0.01) var full_intensity_light_energy: float = 1.0
## Optional day-night cycle supplying overcast attenuation during weather transitions.
@export_node_path("Node") var weather_cycle_path: NodePath

@export_group("Visibility")
## Seconds required to fade and grow from hidden to fully visible.
@export_range(0.001, 2.0, 0.001, "suffix:s") var fade_in_seconds: float = 0.25
## Seconds required to fade and shrink from fully visible to hidden.
@export_range(0.001, 2.0, 0.001, "suffix:s") var fade_out_seconds: float = 0.18
## Screen-edge fade width as a fraction of the shorter viewport dimension.
@export_range(0.001, 0.5, 0.001) var edge_fade_width: float = 0.12
## Sprite scale at the hidden end of the visibility fade.
@export_range(0.0, 1.0, 0.01) var hidden_scale: float = 0.1

@export_group("Obstruction")
## Fades all flare components behind physics surfaces and rendered meshes.
@export var obstruction_enabled: bool = true
## Includes rendered geometry and animated player models without requiring collision shapes.
@export var mesh_obstruction_enabled: bool = true
## Render layers included in the mesh visibility probe, intersected with the active camera's cull mask.
@export_flags_3d_render var mesh_obstruction_mask: int = 1048575
## Physics layers that block the source. Areas are ignored.
@export_flags_3d_physics var obstruction_mask: int = 1
## Maximum obstruction distance for directional sources.
@export_range(1.0, 20000.0, 1.0, "suffix:m") var obstruction_distance: float = 6000.0
## Seconds between obstruction checks. Zero checks every physics frame.
@export_range(0.0, 1.0, 0.001, "suffix:s") var obstruction_interval: float = 0.05
## Angular radius of the four outer visibility probes around the center probe.
@export_range(0.0, 2.0, 0.01, "suffix:°") var obstruction_radius_degrees: float = 0.2
## Collision objects ignored by obstruction checks, in addition to source and camera ancestors.
@export var obstruction_exclusion_paths: Array[NodePath] = []

@export_group("Sun Image")
## Image drawn at the projected source position.
@export var sun_texture: Texture2D
## Full-size sun diameter as a fraction of viewport height.
@export_range(0.001, 2.0, 0.001) var sun_diameter: float = 0.18
## Sun image color and maximum opacity.
@export var sun_tint: Color = Color(1.0, 1.0, 1.0, 0.9)

@export_group("Lens Flares")
## Independently configurable lens images along the source-to-center axis.
@export var lens_elements: Array[CameraFlareElement] = []

@export_group("Screen Bleach")
## Enables the broad wash when looking nearly directly toward the source.
@export var bleach_enabled: bool = true
## Texture used for the broad screen wash.
@export var bleach_texture: Texture2D
## View angle from the source at which bleaching begins.
@export_range(0.1, 45.0, 0.1, "suffix:°") var bleach_start_angle_degrees: float = 12.0
## View angle from the source at which bleaching reaches full strength.
@export_range(0.0, 15.0, 0.1, "suffix:°") var bleach_full_angle_degrees: float = 1.5
## Bleach diameter relative to the viewport diagonal, covering ultrawide screens without stretching.
@export_range(1.0, 5.0, 0.01) var bleach_diameter: float = 2.2
## Screen wash color and maximum opacity at full alignment.
@export var bleach_tint: Color = Color(0.88, 0.96, 1.0, 0.88)
## Adds a distinct circular bleach image centered on the source in addition to the broad wash.
@export var bleach_disc_enabled: bool = true
## Full-size circular bleach diameter as a fraction of viewport height.
@export_range(0.001, 2.0, 0.001) var bleach_disc_diameter: float = 0.72
## Circular bleach color and maximum opacity at full alignment.
@export var bleach_disc_tint: Color = Color(1.0, 1.0, 0.98, 0.9)

## Canvas layer placing the effect beneath the gameplay HUD.
@onready var _overlay: CanvasLayer = $Overlay
## Draws the additive sun and lens images without intercepting input.
@onready var _glow: Control = $Overlay/Glow
## Draws lens rings without applying the sun image's radial softening.
@onready var _lens: Control = $Overlay/Glow/Lens
## Draws the broad screen wash beneath the additive images.
@onready var _bleach: Control = $Overlay/Bleach
## Draws the distinct circular bleach image over the broad wash.
@onready var _bleach_disc: Control = $Overlay/BleachDisc

var _camera: Camera3D
var _source: Node3D
var _screen_position: Vector2 = Vector2.ZERO
var _viewport_size: Vector2 = Vector2.ZERO
var _source_direction: Vector3 = Vector3.FORWARD
var _source_distance: float = 0.0
var _view_weight: float = 0.0
var _visibility: float = 0.0
var _obstruction_visibility: float = 0.0
var _obstruction_elapsed: float = 0.0
var _obstruction_valid: bool = false
var _bleach_weight: float = 0.0
var _bleach_visibility: float = 0.0
var _physics_visibility: float = 0.0
var _mesh_visibility: float = 0.0
var _mesh_probe_pending: bool = false
var _mesh_probe_generation: int = 0
## Small transparent viewport sampling actual rendered geometry toward the source.
var _mesh_probe: SubViewport
## Camera testing only candidate geometry in the private probe world.
var _mesh_probe_camera: Camera3D
var _mesh_instances: Dictionary[int, RID] = {}
## Overrides camera selection while posing a photo.
var _photo_camera: Camera3D
var _previous_process_mode: ProcessMode
var _previous_overlay_visible: bool
var _previous_canvas_layers: Array[int] = []


func _ready() -> void:
	_glow.draw.connect(_draw_glow)
	_lens.draw.connect(_draw_lens)
	_bleach.draw.connect(_draw_bleach)
	_bleach_disc.draw.connect(_draw_bleach_disc)
	_overlay.layer = 0
	if directional:
		add_to_group(&"SunLensFlare")


func begin_photo_view(camera: Camera3D, mask: int) -> void:
	_photo_camera = camera
	_previous_process_mode = process_mode
	_previous_overlay_visible = _overlay.visible
	_previous_canvas_layers.clear()
	for item: Control in [_glow, _lens, _bleach, _bleach_disc]:
		_previous_canvas_layers.append(item.visibility_layer)
		item.visibility_layer = mask
	_overlay.layer = -2


func set_photo_flare_enabled(value: bool) -> void:
	_overlay.visible = value
	process_mode = Node.PROCESS_MODE_ALWAYS if value else Node.PROCESS_MODE_DISABLED


func end_photo_view() -> void:
	_photo_camera = null
	process_mode = _previous_process_mode
	_overlay.layer = 0
	_overlay.visible = _previous_overlay_visible
	var items: Array[Control] = [_glow, _lens, _bleach, _bleach_disc]
	for index: int in range(items.size()):
		items[index].visibility_layer = _previous_canvas_layers[index]
	_previous_canvas_layers.clear()


func _process(delta: float) -> void:
	_update_view()
	var clear_weight: float = _obstruction_visibility if obstruction_enabled else 1.0
	var target: float = _view_weight * clear_weight * _get_source_intensity()
	var duration: float = fade_in_seconds if target > _visibility else fade_out_seconds
	_visibility = move_toward(_visibility, target, maxf(delta, 0.0) / maxf(duration, 0.001))
	var bleach_target: float = _visibility * _bleach_weight if bleach_enabled else 0.0
	var bleach_duration: float = fade_in_seconds if bleach_target > _bleach_visibility else fade_out_seconds
	_bleach_visibility = move_toward(_bleach_visibility, bleach_target, maxf(delta, 0.0) / maxf(bleach_duration, 0.001))
	_glow.visible = _visibility > 0.0001
	_bleach.visible = _bleach_visibility > 0.0001
	_bleach_disc.visible = _bleach.visible and bleach_disc_enabled
	_glow.queue_redraw()
	_lens.queue_redraw()
	_bleach.queue_redraw()
	_bleach_disc.queue_redraw()


func _physics_process(delta: float) -> void:
	if not obstruction_enabled or _view_weight <= 0.0 or not is_instance_valid(_camera) or _get_source_intensity() <= 0.0:
		_obstruction_valid = false
		_obstruction_visibility = 0.0
		_mesh_probe_generation += 1
		_mesh_visibility = 0.0
		return
	_obstruction_elapsed += delta
	if _obstruction_valid and _obstruction_elapsed < obstruction_interval:
		return
	_obstruction_elapsed = 0.0
	_physics_visibility = _sample_obstruction()
	if _uses_mesh_obstruction():
		if _physics_visibility > 0.0:
			_queue_mesh_probe()
		else:
			_mesh_probe_generation += 1
			_mesh_visibility = 0.0
	_obstruction_visibility = minf(_physics_visibility, _mesh_visibility) if _uses_mesh_obstruction() else _physics_visibility
	_obstruction_valid = true


func _update_view() -> void:
	_view_weight = 0.0
	_bleach_weight = 0.0
	var next_camera: Camera3D = get_node_or_null(camera_path) as Camera3D if not camera_path.is_empty() else get_viewport().get_camera_3d()
	if is_instance_valid(_photo_camera):
		next_camera = _photo_camera
	var next_source: Node3D = get_node_or_null(source_path) as Node3D if not source_path.is_empty() else self
	if next_camera != _camera or next_source != _source:
		_camera = next_camera
		_source = next_source
		_visibility = 0.0
		_bleach_visibility = 0.0
		_obstruction_visibility = 0.0
		_obstruction_valid = false
		_mesh_probe_generation += 1
		_mesh_visibility = 0.0
	if not enabled or not is_visible_in_tree() or not is_instance_valid(_camera) or not is_instance_valid(_source) or not _source.is_visible_in_tree():
		return
	_viewport_size = _camera.get_viewport().get_visible_rect().size
	if _viewport_size.x <= 0.0 or _viewport_size.y <= 0.0:
		return
	var camera_position: Vector3 = _camera.get_camera_transform().origin
	var source_position: Vector3 = _source.to_global(source_offset)
	if directional:
		_source_direction = _source.global_basis.z.normalized()
		_source_distance = maxf(obstruction_distance, 1.0)
		source_position = camera_position + _source_direction * _source_distance
	else:
		_source_direction = source_position - camera_position
		_source_distance = _source_direction.length()
		if _source_distance <= 0.001:
			return
		_source_direction /= _source_distance
	var alignment: float = (-_camera.get_camera_transform().basis.z).dot(_source_direction)
	if alignment <= 0.0 or _camera.is_position_behind(source_position):
		return
	_screen_position = _camera.unproject_position(source_position)
	var nearest_edge: float = minf(minf(_screen_position.x, _viewport_size.x - _screen_position.x), minf(_screen_position.y, _viewport_size.y - _screen_position.y))
	_view_weight = clampf(nearest_edge / maxf(minf(_viewport_size.x, _viewport_size.y) * edge_fade_width, 0.001), 0.0, 1.0)
	var angle: float = rad_to_deg(acos(clampf(alignment, -1.0, 1.0)))
	var start_angle: float = maxf(bleach_start_angle_degrees, bleach_full_angle_degrees + 0.001)
	_bleach_weight = 1.0 - smoothstep(bleach_full_angle_degrees, start_angle, angle)


func _get_source_intensity() -> float:
	if not is_instance_valid(_source):
		return 0.0
	var strength: float = maxf(intensity, 0.0)
	if _source is Light3D:
		strength *= clampf((_source as Light3D).light_energy / maxf(full_intensity_light_energy, 0.001), 0.0, 1.0)
	var cycle: Node = get_node_or_null(weather_cycle_path) if not weather_cycle_path.is_empty() else null
	if cycle and cycle.has_method("get_current_weather_state"):
		var weather: Dictionary = cycle.call("get_current_weather_state")
		var overcast: float = clampf(float(weather.get("cloud_coverage", 0.0)) * float(weather.get("cloud_density", 0.0)), 0.0, 1.0)
		strength *= (1.0 - overcast) * (1.0 - overcast)
	return strength


func _sample_obstruction() -> float:
	var exclusions: Array[RID] = []
	for node: Node in [_source, _camera]:
		var ancestor: Node = node
		while ancestor:
			if ancestor is CollisionObject3D:
				exclusions.append((ancestor as CollisionObject3D).get_rid())
			ancestor = ancestor.get_parent()
	for path: NodePath in obstruction_exclusion_paths:
		var body: CollisionObject3D = get_node_or_null(path) as CollisionObject3D
		if body:
			exclusions.append(body.get_rid())
	var camera_transform: Transform3D = _camera.get_camera_transform()
	var spread: float = tan(deg_to_rad(obstruction_radius_degrees))
	var clear_samples: int = 0
	for offset: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var ray_direction: Vector3 = (_source_direction + (camera_transform.basis.x * offset.x + camera_transform.basis.y * offset.y) * spread).normalized()
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera_transform.origin, camera_transform.origin + ray_direction * _source_distance, obstruction_mask, exclusions)
		query.hit_back_faces = true
		query.hit_from_inside = true
		if _camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			clear_samples += 1
	return float(clear_samples) / 5.0


func _draw_glow() -> void:
	var sprite_scale: float = lerpf(hidden_scale, 1.0, clampf(_visibility, 0.0, 1.0))
	_draw_image(_glow, sun_texture, _screen_position, _viewport_size.y * sun_diameter * sprite_scale, sun_tint, _visibility)


func _draw_lens() -> void:
	var sprite_scale: float = lerpf(hidden_scale, 1.0, clampf(_visibility, 0.0, 1.0))
	var center: Vector2 = _viewport_size * 0.5
	for element: CameraFlareElement in lens_elements:
		if element:
			_draw_image(_lens, element.texture, _screen_position.lerp(center, element.axis_position), _viewport_size.y * element.diameter * sprite_scale, element.tint, _visibility)


func _draw_bleach() -> void:
	_draw_image(_bleach, bleach_texture, _screen_position, _viewport_size.length() * bleach_diameter, bleach_tint, _bleach_visibility)


func _draw_bleach_disc() -> void:
	var sprite_scale: float = lerpf(hidden_scale, 1.0, clampf(_bleach_visibility, 0.0, 1.0))
	_draw_image(_bleach_disc, bleach_texture, _screen_position, _viewport_size.y * bleach_disc_diameter * sprite_scale, bleach_disc_tint, _bleach_visibility)


func _uses_mesh_obstruction() -> bool:
	return mesh_obstruction_enabled and DisplayServer.get_name() != "headless"


func _queue_mesh_probe() -> void:
	if _mesh_probe_pending:
		return
	if not is_instance_valid(_mesh_probe):
		_mesh_probe = SubViewport.new()
		_mesh_probe.name = "MeshVisibilityProbe"
		_mesh_probe.size = Vector2i(16, 16)
		_mesh_probe.transparent_bg = true
		_mesh_probe.world_3d = World3D.new()
		_mesh_probe.gui_disable_input = true
		_mesh_probe.audio_listener_enable_3d = false
		_mesh_probe.audio_listener_enable_2d = false
		_mesh_probe.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_mesh_probe.canvas_cull_mask = 0
		_mesh_probe.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
		_mesh_probe.positional_shadow_atlas_size = 0
		_mesh_probe_camera = Camera3D.new()
		_mesh_probe_camera.environment = Environment.new()
		_mesh_probe_camera.environment.background_mode = Environment.BG_COLOR
		_mesh_probe_camera.environment.background_color = Color.TRANSPARENT
		_mesh_probe_camera.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_mesh_probe_camera.environment.ambient_light_energy = 0.0
		_mesh_probe_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_mesh_probe)
		_mesh_probe.add_child(_mesh_probe_camera)
		_mesh_probe_camera.make_current()
	var camera_transform: Transform3D = _camera.get_camera_transform()
	var basis_up: Vector3 = camera_transform.basis.y
	if absf(basis_up.dot(_source_direction)) > 0.98:
		basis_up = camera_transform.basis.x
	_mesh_probe_camera.global_transform = Transform3D(Basis.looking_at(_source_direction, basis_up), camera_transform.origin)
	_mesh_probe_camera.cull_mask = 1
	_mesh_probe_camera.near = maxf(_camera.near, 0.001)
	_mesh_probe_camera.far = maxf(minf(_source_distance - 0.01, _camera.far), _mesh_probe_camera.near + 0.01)
	_mesh_probe_camera.fov = maxf(obstruction_radius_degrees * 2.0, 1.0)
	if not _update_mesh_candidates():
		_mesh_visibility = 1.0
		return
	_mesh_probe_pending = true
	var generation: int = _mesh_probe_generation
	var sample_fraction: float = clampf(tan(deg_to_rad(maxf(obstruction_radius_degrees, 0.025))) / tan(deg_to_rad(_mesh_probe_camera.fov * 0.5)), 0.125, 1.0)
	_mesh_probe.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_mesh_probe):
		_mesh_probe_pending = false
		return
	if generation != _mesh_probe_generation:
		_mesh_probe_pending = false
		return
	if RenderingServer.get_rendering_device():
		RenderingServer.call_on_render_thread(_read_probe_async.bind(_mesh_probe.get_texture().get_rid(), generation, sample_fraction))
	else:
		var image: Image = _mesh_probe.get_texture().get_image()
		_accept_probe_image(image, generation, sample_fraction)


func _update_mesh_candidates() -> bool:
	var active: Dictionary[int, bool] = {}
	var mask: int = _camera.cull_mask & mesh_obstruction_mask
	var candidates: PackedInt64Array = RenderingServer.instances_cull_convex(_mesh_probe_camera.get_frustum(), _camera.get_world_3d().scenario)
	for id: int in candidates:
		var source: GeometryInstance3D = instance_from_id(id) as GeometryInstance3D
		if not source or not source.is_visible_in_tree() or not (source.layers & mask) or not source.get_base().is_valid() or source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		active[id] = true
		if not _mesh_instances.has(id):
			_mesh_instances[id] = RenderingServer.instance_create2(source.get_base(), _mesh_probe.world_3d.scenario)
		var proxy: RID = _mesh_instances[id]
		RenderingServer.instance_set_base(proxy, source.get_base())
		RenderingServer.instance_set_transform(proxy, source.global_transform)
		RenderingServer.instance_set_layer_mask(proxy, 1)
		RenderingServer.instance_geometry_set_cast_shadows_setting(proxy, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		RenderingServer.instance_geometry_set_material_override(proxy, source.material_override.get_rid() if source.material_override else RID())
		RenderingServer.instance_set_custom_aabb(proxy, source.custom_aabb)
		if source is MeshInstance3D:
			var mesh: MeshInstance3D = source as MeshInstance3D
			var skin: SkinReference = mesh.get_skin_reference()
			RenderingServer.instance_attach_skeleton(proxy, skin.get_skeleton() if skin else RID())
			for surface: int in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_surface_override_material(surface)
				RenderingServer.instance_set_surface_override_material(proxy, surface, material.get_rid() if material else RID())
			for shape: int in (mesh.mesh.get_blend_shape_count() if mesh.mesh is ArrayMesh else 0):
				RenderingServer.instance_set_blend_shape_weight(proxy, shape, mesh.get_blend_shape_value(shape))
	for id: int in _mesh_instances.keys():
		if not active.has(id):
			RenderingServer.free_rid(_mesh_instances[id])
			_mesh_instances.erase(id)
	return not active.is_empty()


func _read_probe_async(texture: RID, generation: int, sample_fraction: float) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	var gpu_texture: RID = RenderingServer.texture_get_rd_texture(texture)
	if not gpu_texture.is_valid() or device.texture_get_data_async(gpu_texture, 0, _receive_probe_data.bind(generation, sample_fraction)) != OK:
		_probe_read_failed.call_deferred()


func _probe_read_failed() -> void:
	_mesh_probe_pending = false


func _receive_probe_data(data: PackedByteArray, generation: int, sample_fraction: float) -> void:
	var image: Image = Image.create_from_data(16, 16, false, Image.FORMAT_RGBA8, data)
	_accept_probe_image.call_deferred(image, generation, sample_fraction)


func _accept_probe_image(image: Image, generation: int, sample_fraction: float) -> void:
	_mesh_probe_pending = false
	if generation != _mesh_probe_generation or image.is_empty():
		return
	var coverage: float = 0.0
	var samples: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var offset: Vector2 = Vector2((float(x) + 0.5) / float(image.get_width()), (float(y) + 0.5) / float(image.get_height())) - Vector2(0.5, 0.5)
			if maxf(absf(offset.x), absf(offset.y)) * 2.0 > sample_fraction:
				continue
			coverage += image.get_pixel(x, y).a
			samples += 1
	_mesh_visibility = clampf(1.0 - coverage / float(maxi(samples, 1)), 0.0, 1.0)
	_obstruction_visibility = minf(_physics_visibility, _mesh_visibility)


func _exit_tree() -> void:
	_mesh_probe_generation += 1
	for proxy: RID in _mesh_instances.values():
		RenderingServer.free_rid(proxy)
	_mesh_instances.clear()


func _draw_image(canvas: Control, texture: Texture2D, center: Vector2, diameter: float, tint: Color, opacity: float) -> void:
	if not texture or diameter <= 0.0:
		return
	var color: Color = tint
	color.a *= clampf(opacity, 0.0, 1.0)
	canvas.draw_texture_rect(texture, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), false, color)

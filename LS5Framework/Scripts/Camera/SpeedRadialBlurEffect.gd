extends CanvasLayer
class_name SpeedRadialBlurEffect

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _target_intensity: float = 0.0
var _current_intensity: float = 0.0
var _blend_speed: float = 6.0
var _time: float = 0.0
var _viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = -2
	_rect = get_node_or_null("RadialBlurRect") as ColorRect
	if _rect == null:
		return
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = _rect.material as ShaderMaterial
	_update_viewport_aspect()
	_apply_intensity()


func _process(delta: float) -> void:
	if _rect == null or _material == null:
		return
	_time += max(delta, 0.0)
	if _blend_speed <= 0.0 or delta <= 0.0:
		_current_intensity = _target_intensity
	else:
		var blend: float = 1.0 - exp(-_blend_speed * delta)
		_current_intensity = lerp(_current_intensity, _target_intensity, blend)
	_update_viewport_aspect()
	_apply_intensity()


func configure(
	max_blur_radius: float,
	vignette_inner_radius: float,
	vignette_outer_radius: float,
	max_opacity: float,
	pulse_amount: float,
	pulse_frequency: float,
	chromatic_separation: float,
	line_lanes_per_side: int,
	line_opacity: float,
	line_spawn_rate: float,
	line_lifetime_fraction: float,
	line_width: float,
	line_length: float,
	blend_speed: float
) -> void:
	_blend_speed = max(blend_speed, 0.0)
	if _material == null:
		return
	_material.set_shader_parameter("max_blur_radius", max(max_blur_radius, 0.0))
	_material.set_shader_parameter("vignette_inner_radius", max(vignette_inner_radius, 0.0))
	_material.set_shader_parameter(
		"vignette_outer_radius",
		max(vignette_outer_radius, vignette_inner_radius + 0.001)
	)
	_material.set_shader_parameter("max_opacity", clamp(max_opacity, 0.0, 1.0))
	_material.set_shader_parameter("pulse_amount", clamp(pulse_amount, 0.0, 1.0))
	_material.set_shader_parameter("pulse_frequency", max(pulse_frequency, 0.0))
	_material.set_shader_parameter("chromatic_separation", max(chromatic_separation, 0.0))
	_material.set_shader_parameter("speed_line_lanes_per_side", max(line_lanes_per_side, 1))
	_material.set_shader_parameter("speed_line_opacity", clamp(line_opacity, 0.0, 1.0))
	_material.set_shader_parameter("speed_line_spawn_rate", max(line_spawn_rate, 0.1))
	_material.set_shader_parameter("speed_line_lifetime_fraction", clamp(line_lifetime_fraction, 0.05, 0.95))
	_material.set_shader_parameter("speed_line_width", max(line_width, 0.001))
	_material.set_shader_parameter("speed_line_length", clamp(line_length, 0.01, 0.95))


func set_intensity(value: float) -> void:
	_target_intensity = clamp(value, 0.0, 2.0)
	if _rect != null and _target_intensity > 0.001:
		_rect.visible = true


func _update_viewport_aspect() -> void:
	if _material == null:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var size: Vector2 = viewport.get_visible_rect().size
	if size == _viewport_size or size.y <= 0.0:
		return
	_viewport_size = size
	_material.set_shader_parameter("viewport_aspect", max(size.x / size.y, 0.001))


func _apply_intensity() -> void:
	if _rect == null or _material == null:
		return
	_material.set_shader_parameter("intensity", _current_intensity)
	_material.set_shader_parameter("time_offset", _time)
	_rect.visible = _current_intensity > 0.001 or _target_intensity > 0.001

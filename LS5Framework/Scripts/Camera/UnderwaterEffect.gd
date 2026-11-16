extends CanvasLayer
class_name UnderwaterEffect

## Fullscreen underwater overlay: color tint + UV-ripple distortion.
## Managed by SonicCameraRig. Call set_underwater() to activate or deactivate.

## Tint color applied over the screen when submerged.
@export var tint_color: Color = Color(0.05, 0.2, 0.5, 0.35)
## Blend speed for fading the effect in and out (per second).
@export var blend_speed: float = 3.0
## Speed of the ripple wave animation.
@export var ripple_speed: float = 1.2
## Maximum UV distortion strength at full blend.
@export var ripple_strength: float = 0.008
## Spatial frequency of the ripple waves.
@export var ripple_scale: float = 8.0

var _blend: float = 0.0
var _target: float = 0.0
var _time: float = 0.0
var _rect: ColorRect = null
var _depth_absorption_active: bool = false
## Refreshes the screen texture between photo effects.
var _photo_copy: BackBufferCopy
## Graphics options controlling underwater tint and distortion.
var _graphics_settings: Node


func _ready() -> void:
	layer = -1
	_graphics_settings = get_node_or_null("/root/SettingsManager")
	if _graphics_settings:
		_graphics_settings.water_graphics_changed.connect(_on_water_graphics_changed)
	_rect = get_node_or_null("UnderwaterRect")
	if _rect == null:
		return
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo_copy = BackBufferCopy.new()
	_photo_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_photo_copy.show_behind_parent = true
	_photo_copy.hide()
	_rect.add_child(_photo_copy)
	_apply_shader_params()


func _process(delta: float) -> void:
	if _rect == null:
		return
	_time += delta
	var t: float = clamp(blend_speed * delta, 0.0, 1.0)
	_blend = lerp(_blend, _target, t)
	if not _target and _blend < 0.001:
		_depth_absorption_active = false
	var mat: ShaderMaterial = _rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("blend", _blend)
	mat.set_shader_parameter("time_offset", _time)
	mat.set_shader_parameter("tint_color", tint_color)
	mat.set_shader_parameter("ripple_speed", ripple_speed)
	mat.set_shader_parameter("ripple_strength", ripple_strength)
	mat.set_shader_parameter("ripple_scale", ripple_scale)
	mat.set_shader_parameter("depth_absorption_active", _depth_absorption_active)
	var tint_active: bool = not _depth_absorption_active and tint_color.a > 0.0 and (not _graphics_settings or _graphics_settings.water_depth_effects_enabled)
	var ripple_active: bool = ripple_strength > 0.0 and (not _graphics_settings or (_graphics_settings.water_refraction_enabled and _graphics_settings.water_normal_maps_enabled))
	_rect.visible = _blend > 0.001 and (tint_active or ripple_active)


func set_underwater(state: bool) -> void:
	_target = 1.0 if state else 0.0


func set_photo_presentation(mask: int, enabled: bool) -> void:
	if _rect:
		_rect.visibility_layer = mask
	if _photo_copy:
		_photo_copy.visibility_layer = mask
		_photo_copy.visible = mask != 1 and enabled
	visible = enabled
	layer = -3 if mask != 1 else -1


func set_depth_absorption_active(active: bool) -> void:
	if active or _target > 0.0 or _blend < 0.001:
		_depth_absorption_active = active
		_process(0.0)


func _on_water_graphics_changed() -> void:
	_process(0.0)


func set_tint_override(color: Color) -> void:
	tint_color = color


func clear_tint_override() -> void:
	tint_color = (get_script() as Script).get_property_default_value("tint_color")


func _apply_shader_params() -> void:
	var mat: ShaderMaterial = _rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("blend", 0.0)
	mat.set_shader_parameter("time_offset", 0.0)
	mat.set_shader_parameter("tint_color", tint_color)
	mat.set_shader_parameter("ripple_speed", ripple_speed)
	mat.set_shader_parameter("ripple_strength", ripple_strength)
	mat.set_shader_parameter("ripple_scale", ripple_scale)

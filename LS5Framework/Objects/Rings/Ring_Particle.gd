extends Sprite3D
class_name RingPickupTwinkle

@export var twinkle_texture: Texture2D = preload("res://LS5Framework/Images/Ring_Particle.png")
@export var twinkle_lifetime: float = 0.35
@export var twinkle_start_scale: float = 0.01
@export var twinkle_end_scale: float = 0.00
@export var twinkle_start_alpha: float = 1.0
@export var twinkle_end_alpha: float = 0.0
@export var twinkle_fade_out_time: float = 0.2
@export var twinkle_pixel_size: float = 0.005
## World-space position used as the twinkle start point.
@export var twinkle_spawn_position: Vector3 = Vector3.ZERO
## Keeps the twinkle position relative to its parent after spawning.
@export var twinkle_follow_parent: bool = false
## Local offset applied before the twinkle starts.
@export var twinkle_initial_offset: Vector3 = Vector3.ZERO
## Direction used for the subtle outward drift.
@export var twinkle_drift_direction: Vector3 = Vector3.ZERO
## Total drift distance applied over the twinkle lifetime.
@export var twinkle_drift_distance: float = 0.16
## Enables the softer glow layer behind the twinkle.
@export var twinkle_glow_enabled: bool = true
## Scale multiplier for the glow layer relative to the core sprite.
@export var twinkle_glow_scale_multiplier: float = 1.75
## Alpha multiplier applied to the glow layer.
@export var twinkle_glow_alpha_multiplier: float = 0.22
## Tint applied to the glow layer.
@export var twinkle_glow_color: Color = Color(1.0, 0.92, 0.55, 1.0)

var _twinkle_elapsed: float = 0.0
var _twinkle_start_position: Vector3 = Vector3.ZERO
var _twinkle_drift_step: Vector3 = Vector3.ZERO
var _twinkle_start_scale_value: float = 0.0
var _twinkle_end_scale_value: float = 0.0
var _twinkle_start_alpha_value: float = 1.0
var _twinkle_end_alpha_value: float = 0.0
var _twinkle_glow_sprite: Sprite3D = null


func _ready() -> void:
	add_to_group(&"LevelTransient")
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	shaded = false
	double_sided = true
	pixel_size = max(twinkle_pixel_size, 0.0001)
	if twinkle_follow_parent:
		var spatial_parent: Node3D = get_parent() as Node3D
		if spatial_parent != null:
			_twinkle_start_position = spatial_parent.to_local(twinkle_spawn_position) + twinkle_initial_offset
		else:
			_twinkle_start_position = position + twinkle_initial_offset
		position = _twinkle_start_position
	else:
		_twinkle_start_position = twinkle_spawn_position + twinkle_initial_offset
		global_position = _twinkle_start_position
	_twinkle_start_scale_value = max(twinkle_start_scale, 0.001)
	_twinkle_end_scale_value = max(twinkle_end_scale, 0.001)
	_twinkle_start_alpha_value = clamp(twinkle_start_alpha, 0.0, 1.0)
	_twinkle_end_alpha_value = clamp(twinkle_end_alpha, 0.0, 1.0)
	modulate = Color(1.0, 1.0, 1.0, _twinkle_start_alpha_value)
	texture = twinkle_texture
	scale = Vector3.ONE * _twinkle_start_scale_value
	if twinkle_drift_direction.length() > 0.001 and twinkle_drift_distance > 0.0:
		_twinkle_drift_step = twinkle_drift_direction.normalized() * max(twinkle_drift_distance, 0.0)
	else:
		_twinkle_drift_step = Vector3.ZERO
	if twinkle_glow_enabled:
		_twinkle_glow_sprite = Sprite3D.new()
		_twinkle_glow_sprite.name = "TwinkleGlow"
		_twinkle_glow_sprite.texture = twinkle_texture
		_twinkle_glow_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_twinkle_glow_sprite.no_depth_test = true
		_twinkle_glow_sprite.shaded = false
		_twinkle_glow_sprite.double_sided = true
		_twinkle_glow_sprite.pixel_size = max(twinkle_pixel_size, 0.0001)
		_twinkle_glow_sprite.position = Vector3.ZERO
		_twinkle_glow_sprite.scale = Vector3.ONE * max(twinkle_glow_scale_multiplier, 1.0)
		_twinkle_glow_sprite.modulate = Color(
			twinkle_glow_color.r,
			twinkle_glow_color.g,
			twinkle_glow_color.b,
			_twinkle_start_alpha_value * clamp(twinkle_glow_alpha_multiplier, 0.0, 1.0)
		)
		add_child(_twinkle_glow_sprite)
	set_process(true)


func _process(delta: float) -> void:
	_twinkle_elapsed += delta
	var life_time: float = max(twinkle_lifetime, 0.01)
	var life_t: float = clamp(_twinkle_elapsed / life_time, 0.0, 1.0)

	if twinkle_follow_parent:
		position = _twinkle_start_position + _twinkle_drift_step * life_t
	else:
		global_position = _twinkle_start_position + _twinkle_drift_step * life_t
	scale = Vector3.ONE * lerp(_twinkle_start_scale_value, _twinkle_end_scale_value, life_t)

	var fade_time: float = clamp(twinkle_fade_out_time, 0.01, life_time)
	var fade_start: float = max(life_time - fade_time, 0.0)
	var alpha_t: float = 0.0
	if _twinkle_elapsed > fade_start:
		alpha_t = clamp((_twinkle_elapsed - fade_start) / fade_time, 0.0, 1.0)
	var current_alpha: float = lerp(_twinkle_start_alpha_value, _twinkle_end_alpha_value, alpha_t)
	modulate.a = current_alpha
	if is_instance_valid(_twinkle_glow_sprite):
		_twinkle_glow_sprite.modulate = Color(
			twinkle_glow_color.r,
			twinkle_glow_color.g,
			twinkle_glow_color.b,
			current_alpha * clamp(twinkle_glow_alpha_multiplier, 0.0, 1.0)
		)

	if _twinkle_elapsed >= life_time:
		queue_free()

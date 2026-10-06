extends OmniLight3D
class_name RingPickupLight

## World-space position used as the light spawn point.
@export var light_spawn_position: Vector3 = Vector3.ZERO
## Starting brightness before fade-out.
@export var light_start_energy: float = 1.0
## Final brightness before despawn.
@export var light_end_energy: float = 0.0
## Total lifetime of the light pulse.
@export var light_lifetime: float = 0.2
## Time spent fading to zero brightness.
@export var light_fade_out_time: float = 0.2
## Effective radius of the light pulse.
@export var light_range: float = 2.5
## Tint applied to the light pulse.
@export var pulse_color: Color = Color(1.0, 0.92, 0.55, 1.0)

var _light_elapsed: float = 0.0
var _light_start_energy_value: float = 0.0
var _light_end_energy_value: float = 0.0


func _ready() -> void:
	add_to_group(&"LevelTransient")
	global_position = light_spawn_position
	shadow_enabled = false
	light_indirect_energy = 0.0
	omni_range = max(light_range, 0.01)
	light_color = Color(pulse_color.r, pulse_color.g, pulse_color.b, 1.0)
	_light_start_energy_value = max(light_start_energy, 0.0)
	_light_end_energy_value = max(light_end_energy, 0.0)
	light_energy = _light_start_energy_value
	set_process(true)


func _process(delta: float) -> void:
	_light_elapsed += delta
	var life_time: float = max(light_lifetime, 0.01)

	var fade_time: float = clamp(light_fade_out_time, 0.01, life_time)
	var fade_start: float = max(life_time - fade_time, 0.0)
	var energy_t: float = 0.0
	if _light_elapsed > fade_start:
		energy_t = clamp((_light_elapsed - fade_start) / fade_time, 0.0, 1.0)
	light_energy = lerp(_light_start_energy_value, _light_end_energy_value, energy_t)

	if _light_elapsed >= life_time:
		queue_free()

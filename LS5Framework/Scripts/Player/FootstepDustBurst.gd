extends Node3D
class_name FootstepDustBurst

## Starts the burst when the node enters the tree.
@export var auto_start: bool = true
## Extra time before the finished burst is freed.
@export var cleanup_delay: float = 0.1
## Lifetime fraction where the overall opacity fade begins.
@export_range(0.0, 1.0) var fade_out_start_fraction: float = 0.45

@onready var _particles: GPUParticles3D = $DustParticles

var _fade_tween: Tween = null


func _ready() -> void:
	top_level = true
	if _particles == null:
		queue_free()
		return
	if auto_start:
		call_deferred("emit_burst")


func emit_burst() -> void:
	if _particles == null:
		return
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = null
	_particles.transparency = 0.0
	_particles.emitting = false
	_particles.restart()
	_particles.emitting = true
	_start_opacity_fade()
	var timer: SceneTreeTimer = get_tree().create_timer(max(_particles.lifetime + cleanup_delay, 0.05))
	timer.timeout.connect(func(): queue_free())


func _start_opacity_fade() -> void:
	var lifetime: float = max(_particles.lifetime, 0.05)
	var fade_start: float = clamp(fade_out_start_fraction, 0.0, 1.0) * lifetime
	var fade_duration: float = max(lifetime - fade_start, 0.01)
	_fade_tween = create_tween()
	if fade_start > 0.0:
		_fade_tween.tween_interval(fade_start)
	_fade_tween.tween_property(_particles, "transparency", 1.0, fade_duration)

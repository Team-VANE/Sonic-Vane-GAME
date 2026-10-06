extends Node3D
class_name RaceCollectionParticle

## Texture used by the central flash and outward sparkles.
@export var particle_texture: Texture2D = preload("res://LS5Framework/Images/Ring_Particle.png")
## Total duration of the collection effect.
@export_range(0.05, 5.0, 0.01) var lifetime: float = 0.45
## World-space width of the central flash at its largest point.
@export_range(0.1, 20.0, 0.1) var central_flash_size: float = 3.0
## World-space width of each outward sparkle at its largest point.
@export_range(0.1, 20.0, 0.1) var sparkle_size: float = 1.4
## Number of sparkles emitted around the player.
@export_range(1, 16, 1) var sparkle_count: int = 6
## Starting distance of each sparkle from the effect center.
@export_range(0.0, 10.0, 0.05) var sparkle_start_radius: float = 0.35
## Outward distance traveled by each sparkle.
@export_range(0.0, 20.0, 0.05) var sparkle_travel_distance: float = 1.5
## Tint applied to the central flash.
@export var central_flash_color: Color = Color(0.65, 0.95, 1.0, 1.0)
## Tint applied to the outward sparkles.
@export var sparkle_color: Color = Color(0.14, 0.78, 1.0, 1.0)
## Scale multiplier used by the soft glow behind the central flash.
@export_range(1.0, 5.0, 0.05) var glow_size_multiplier: float = 1.8
## Opacity used by the soft glow behind the central flash.
@export_range(0.0, 1.0, 0.01) var glow_alpha: float = 0.3

var _elapsed: float = 0.0
var _central_flash: Sprite3D = null
var _central_glow: Sprite3D = null
var _sparkles: Array[Sprite3D] = []
var _sparkle_directions: Array[Vector3] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if particle_texture == null:
		queue_free()
		return
	_central_glow = _create_sprite(central_flash_size * glow_size_multiplier, central_flash_color)
	_central_glow.modulate.a = glow_alpha
	_central_glow.name = "CentralGlow"
	add_child(_central_glow)
	_central_flash = _create_sprite(central_flash_size, central_flash_color)
	_central_flash.name = "CentralFlash"
	add_child(_central_flash)
	_create_sparkles()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed = min(_elapsed + max(delta, 0.0), max(lifetime, 0.05))
	var progress: float = clamp(_elapsed / max(lifetime, 0.05), 0.0, 1.0)
	var expansion: float = 1.0 - pow(1.0 - progress, 3.0)
	var fade: float = 1.0 - smoothstep(0.2, 1.0, progress)
	var flash_scale: float = lerp(0.35, 1.0, min(progress * 5.0, 1.0))
	flash_scale *= lerp(1.0, 0.2, progress)
	if _central_flash != null and is_instance_valid(_central_flash):
		_central_flash.scale = Vector3.ONE * flash_scale
		_central_flash.modulate.a = fade
	if _central_glow != null and is_instance_valid(_central_glow):
		_central_glow.scale = Vector3.ONE * lerp(0.45, 1.15, expansion)
		_central_glow.modulate.a = fade * glow_alpha
	for index in range(_sparkles.size()):
		var sparkle: Sprite3D = _sparkles[index]
		if sparkle == null or not is_instance_valid(sparkle):
			continue
		var direction: Vector3 = _sparkle_directions[index]
		var distance: float = sparkle_start_radius + sparkle_travel_distance * expansion
		sparkle.position = direction * distance
		sparkle.scale = Vector3.ONE * lerp(0.7, 0.15, progress)
		sparkle.modulate.a = fade
	if progress >= 1.0:
		queue_free()


func _create_sparkles() -> void:
	var count: int = max(sparkle_count, 1)
	for index in range(count):
		var angle: float = TAU * float(index) / float(count)
		var vertical: float = 0.35 if index % 2 == 0 else -0.2
		var direction: Vector3 = Vector3(cos(angle), vertical, sin(angle)).normalized()
		var sparkle: Sprite3D = _create_sprite(sparkle_size, sparkle_color)
		sparkle.name = "Sparkle%d" % (index + 1)
		sparkle.position = direction * sparkle_start_radius
		add_child(sparkle)
		_sparkles.append(sparkle)
		_sparkle_directions.append(direction)


func _create_sprite(world_size: float, tint: Color) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.texture = particle_texture
	sprite.pixel_size = max(world_size, 0.1) / float(max(particle_texture.get_width(), 1))
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.double_sided = true
	sprite.modulate = tint
	return sprite

extends Control

signal entrance_music_requested
signal entrance_finished
signal departure_finished

## Skyline texture covering the viewport with motion overscan.
@export var skyline: Texture2D = preload("res://LS5Framework/Images/VANE/Title_Skyline.png")
## Centered title artwork.
@export var logo: Texture2D = preload("res://LS5Framework/Images/VANE/SONICVANE_LOGO_1440.png")
## Translucent rising particle artwork.
@export var floater: Texture2D = preload("res://LS5Framework/Images/Particles/Floater.png")
## Duration of the optional black startup fade.
@export var fade_duration: float = 0.65
## Duration of the title slide and settling motion.
@export_range(0.1, 0.8) var entrance_duration: float = 0.7
## Duration of the logo shrink and fade before the menu enters.
@export_range(0.1, 0.5) var departure_duration: float = 0.22
## Number of rising background particles.
@export var floater_count: int = 32
## Maximum logo scale increase on each musical beat.
@export var beat_scale: float = 0.018

var prompt_visible: bool = false
var ready_for_input: bool = false
var playback_position: Callable
var music_bpm: float = 0.0
var _time: float = 0.0
var _prompt_time: float = 0.0
var _slide: float = 0.0
var _black: float = 1.0
var _logo_visible: bool = false
var _logo_music_requested: bool = false
var _logo_scale: float = 1.0
var _logo_opacity: float = 1.0
var _particles: Array[Dictionary] = []
var _noise: FastNoiseLite = FastNoiseLite.new()
var _entrance: Tween
var _floater_texture: ImageTexture
const PROMPT_FONT: Font = preload("res://LS5Framework/Resources/Fonts/Orbitron900.tres")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noise.seed = randi()
	_noise.frequency = 0.7
	var particle_image: Image = floater.get_image()
	if particle_image.is_compressed():
		particle_image.decompress()
	particle_image.adjust_bcs(1.8, 1.0, 0.0)
	_floater_texture = ImageTexture.create_from_image(particle_image)
	for index in range(floater_count):
		_particles.append(_new_floater(randf()))

func _new_floater(height: float) -> Dictionary:
	return {"x": randf(), "y": height, "size": randf_range(0.018, 0.048),
		"speed": randf_range(0.025, 0.055), "phase": randf_range(0.0, TAU),
		"color": Color.from_hsv(randf(), randf_range(0.25, 0.65), 1.0, randf_range(0.18, 0.48))}

func show_title(fade_from_black: bool = false) -> void:
	if _entrance:
		_entrance.kill()
	set_process(true)
	ready_for_input = false
	prompt_visible = false
	_logo_visible = false
	_logo_music_requested = false
	_logo_scale = 1.0
	_logo_opacity = 1.0
	_slide = 1.0
	_black = 1.0 if fade_from_black else 0.0
	_entrance = create_tween()
	if fade_from_black:
		_entrance.tween_property(self, "_black", 0.0, fade_duration)
	_entrance.tween_callback(_begin_logo)
	_entrance.tween_property(self, "_slide", 0.0, entrance_duration).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_entrance.tween_callback(_finish_entrance)


func cancel_title() -> void:
	if _entrance:
		_entrance.kill()
		_entrance = null
	ready_for_input = false
	prompt_visible = false
	_logo_visible = false
	set_process(false)
	hide()


func skip_entrance() -> void:
	if ready_for_input:
		return
	if _entrance:
		_entrance.kill()
		_entrance = null
	_black = 0.0
	_slide = 0.0
	_logo_visible = true
	if not _logo_music_requested:
		_logo_music_requested = true
		entrance_music_requested.emit()
	_finish_entrance()

func _begin_logo() -> void:
	if not _logo_music_requested:
		_logo_music_requested = true
		entrance_music_requested.emit()
	_logo_visible = true

func _finish_entrance() -> void:
	ready_for_input = true
	prompt_visible = true
	_prompt_time = 0.0
	entrance_finished.emit()

func dismiss_title() -> void:
	ready_for_input = false
	prompt_visible = false
	if _entrance:
		_entrance.kill()
	_entrance = create_tween().set_parallel(true)
	_entrance.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_entrance.tween_property(self, "_logo_scale", 0.0, departure_duration)
	_entrance.tween_property(self, "_logo_opacity", 0.0, departure_duration)
	_entrance.chain().tween_callback(_finish_departure)

func _finish_departure() -> void:
	_logo_visible = false
	departure_finished.emit()

func _process(delta: float) -> void:
	_time += delta
	_prompt_time += delta
	for index in range(_particles.size()):
		_particles[index]["y"] -= float(_particles[index]["speed"]) * delta
		if float(_particles[index]["y"]) < -0.1:
			_particles[index] = _new_floater(1.1)
	queue_redraw()

func _draw() -> void:
	if not size.x or not size.y:
		return
	var cover: float = maxf(size.x / skyline.get_width(), size.y / skyline.get_height()) * 1.035
	var background_size: Vector2 = skyline.get_size() * cover
	var sway: Vector2 = Vector2(_noise.get_noise_1d(_time * 0.3), _noise.get_noise_1d(_time * 0.3 + 100.0)) * size.y * 0.009
	sway += Vector2(_noise.get_noise_1d(_time * 2.0 + 200.0), _noise.get_noise_1d(_time * 2.0 + 300.0)) * size.y * 0.0008
	draw_texture_rect(skyline, Rect2((size - background_size) * 0.5 + sway, background_size), false)
	for particle in _particles:
		var diameter: float = float(particle["size"]) * size.y
		var center: Vector2 = Vector2((float(particle["x"]) + sin(_time * 0.65 + float(particle["phase"])) * 0.012) * size.x, float(particle["y"]) * size.y)
		draw_texture_rect(_floater_texture, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), false, particle["color"])
	if _logo_visible:
		var pulse: float = 1.0
		if ready_for_input and playback_position.is_valid() and music_bpm > 0.0:
			var phase: float = fposmod(float(playback_position.call()) * music_bpm / 60.0, 1.0)
			pulse += beat_scale * pow(1.0 - phase, 3.0)
		var logo_scale: float = minf(size.x * 0.72 / logo.get_width(), size.y * 0.62 / logo.get_height()) * pulse
		var logo_size: Vector2 = logo.get_size() * logo_scale * _logo_scale
		var logo_position: Vector2 = (size - logo_size) * 0.5 - Vector2(size.x * 1.2 * _slide, 0.0)
		draw_texture_rect(logo, Rect2(logo_position, logo_size), false, Color(1.0, 1.0, 1.0, _logo_opacity))
	if prompt_visible:
		var font_size: int = maxi(18, int(size.y * 0.038))
		var text_size: Vector2 = PROMPT_FONT.get_string_size("Press Any Key", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var text_position: Vector2 = Vector2((size.x - text_size.x) * 0.5, size.y * 0.85)
		var alpha: float = 0.65 + 0.35 * cos(_prompt_time * TAU / 1.5)
		draw_string_outline(PROMPT_FONT, text_position, "Press Any Key", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.02, 0.04, 0.12, alpha))
		draw_string(PROMPT_FONT, text_position, "Press Any Key", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, alpha))
	if _black > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, _black))

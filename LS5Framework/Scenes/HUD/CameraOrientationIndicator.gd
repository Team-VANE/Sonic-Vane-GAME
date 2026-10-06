extends Control

const NORMAL_SCALE: Vector2 = Vector2.ONE
const TOGGLE_SCALE: Vector2 = Vector2(1.25, 1.25)
const TOGGLE_RETURN_DURATION: float = 0.22

## Displays the artwork for the selected camera orientation mode.
@onready var mode_texture: TextureRect = $ModeTexture
## Plays the confirmation sound for gravity-up mode.
@onready var gravity_up_audio: AudioStreamPlayer = $GravityUpAudio
## Plays the confirmation sound for player-up mode.
@onready var player_up_audio: AudioStreamPlayer = $PlayerUpAudio

## Artwork displayed while the camera is aligned to gravity-up.
@export var gravity_up_texture: Texture2D
## Artwork displayed while the camera is aligned to player-up.
@export var player_up_texture: Texture2D

var _return_tween: Tween = null


func _ready() -> void:
	if mode_texture.material != null:
		mode_texture.material = mode_texture.material.duplicate()
	resized.connect(_update_pivot)
	_update_pivot()
	set_player_up_enabled(false, false)


func set_icon_color(color: Color) -> void:
	if mode_texture == null:
		if not is_node_ready():
			call_deferred("set_icon_color", color)
		return
	var color_material: ShaderMaterial = mode_texture.material as ShaderMaterial
	if color_material != null:
		color_material.set_shader_parameter("tint_color", color)


func set_player_up_enabled(enabled: bool, animate: bool = true) -> void:
	mode_texture.texture = player_up_texture if enabled else gravity_up_texture
	if not animate:
		scale = NORMAL_SCALE
		return

	if enabled:
		player_up_audio.play()
	else:
		gravity_up_audio.play()
	_play_toggle_animation()


func _play_toggle_animation() -> void:
	if _return_tween != null and _return_tween.is_valid():
		_return_tween.kill()
	scale = TOGGLE_SCALE
	_return_tween = create_tween()
	_return_tween.set_trans(Tween.TRANS_QUAD)
	_return_tween.set_ease(Tween.EASE_OUT)
	_return_tween.tween_property(self, "scale", NORMAL_SCALE, TOGGLE_RETURN_DURATION)


func _update_pivot() -> void:
	pivot_offset = size * 0.5

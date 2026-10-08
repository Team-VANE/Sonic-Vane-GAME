extends Control

## Strength of the dark primary-colour surface beneath the three masks.
@export_range(0.0, 1.0, 0.01) var background_darkening: float = 0.78
## Time taken to blend the gauges to their new values.
@export_range(0.0, 2.0, 0.01, "suffix:s") var gauge_response: float = 0.12
## Fade duration after the landing feedback hold.
@export_range(0.05, 2.0, 0.01, "suffix:s") var landing_effect_duration: float = 0.35
## Time the landing-roll and rough-landing bar flashes remain at full strength before fading.
@export_range(0.0, 1.0, 0.01, "suffix:s") var landing_effect_hold_duration: float = 0.12
## Additive glow intensity for landing-roll and rough-landing bar feedback.
@export_range(0.0, 3.0, 0.05) var landing_effect_glow: float = 1.1
## Duration of each half of the full-charge text flash.
@export_range(0.05, 2.0, 0.01, "suffix:s") var barrier_flash_duration: float = 0.4

var _speed_fraction: float = 0.0
var _barrier_fraction: float = 0.0
var _target_speed_fraction: float = 0.0
var _target_barrier_fraction: float = 0.0
var _primary_color: Color = Color(0.1, 0.45, 1.0)
var _secondary_color: Color = Color(0.05, 0.45, 1.0)
var _landing_tween: Tween
var _barrier_flash_tween: Tween
var _barrier_active: bool = false

## Displays the masked speed fill and its dark background.
@onready var speed_mask: TextureRect = $Art/SpeedMask
## Displays the masked Barrier Blast fill and its dark background.
@onready var barrier_mask: TextureRect = $Art/BarrierMask
## Displays the dark digital readout surface.
@onready var readout_mask: TextureRect = $Art/ReadoutMask
## Tints the speedometer artwork with the character's primary colour.
@onready var frame: TextureRect = $Art/Frame
## Keeps both readout values and their inactive segments aligned.
@onready var readout: Control = $Art/Readout
## Holds the current speed in fixed digit positions, with the ones digit on the right.
@onready var current_digit_labels: Array[Label] = [
	$Art/Readout/CurrentThousands,
	$Art/Readout/CurrentHundreds,
	$Art/Readout/CurrentTens,
	$Art/Readout/CurrentOnes,
]
## Shows the gauge maximum over its inactive segments.
@onready var maximum_label: Label = $Art/Readout/Maximum
## Separates the current speed from the maximum speed.
@onready var readout_divider: ColorRect = $Art/Readout/Divider
## Fits the Barrier Blast indicator within the header frame.
@onready var barrier_label: Label = $Art/BarrierBlastLabel


func _ready() -> void:
	_apply_colors()
	_update_gauges()
	_set_barrier_indicator()


func _process(delta: float) -> void:
	var weight: float = 1.0 if gauge_response <= 0.0 else 1.0 - exp(-delta / gauge_response)
	_speed_fraction = lerpf(_speed_fraction, _target_speed_fraction, weight)
	_barrier_fraction = lerpf(_barrier_fraction, _target_barrier_fraction, weight)
	_update_gauges()


func set_speed(speed: float, max_speed_value: float, _top_speed_value: float, _delta: float = 0.0) -> void:
	var maximum: float = maxf(max_speed_value, 0.001)
	_target_speed_fraction = clampf(maxf(speed, 0.0) / maximum, 0.0, 1.0)
	_set_current_digits(str(int(maxf(speed, 0.0))))
	maximum_label.text = str(int(maxf(max_speed_value, 0.0)))


func _set_current_digits(value: String) -> void:
	for slot: int in range(current_digit_labels.size()):
		var digit_index: int = value.length() - current_digit_labels.size() + slot
		current_digit_labels[slot].text = value.substr(digit_index, 1) if digit_index >= 0 else ""


func set_barrier_blast_fraction(fraction: float) -> void:
	_target_barrier_fraction = clampf(fraction, 0.0, 1.0)
	_set_barrier_indicator()


func set_hud_colors(primary_color: Color, secondary_color: Color) -> void:
	_primary_color = primary_color
	_secondary_color = secondary_color
	if is_node_ready():
		_apply_colors()


func play_landing_roll_effect(result: StringName, strength: float) -> void:
	if _landing_tween and _landing_tween.is_valid():
		_landing_tween.kill()
	var material: ShaderMaterial = speed_mask.material as ShaderMaterial
	var flash: Color = Color(1.0, 1.0, 1.0) if result == &"accepted" else Color(1.0, 0.04, 0.02)
	if result == &"rejected":
		flash = Color(0.16, 0.16, 0.18)
	material.set_shader_parameter("feedback_color", flash)
	var glow: float = 0.0 if result == &"rejected" else landing_effect_glow
	if result == &"hard_landing":
		glow *= lerpf(0.55, 1.0, clampf(strength, 0.0, 1.0))
	material.set_shader_parameter("feedback_glow", glow)
	material.set_shader_parameter("feedback_strength", 1.0)
	_landing_tween = create_tween()
	if result == &"accepted" or result == &"hard_landing":
		_landing_tween.tween_interval(landing_effect_hold_duration)
	_landing_tween.tween_property(material, "shader_parameter/feedback_strength", 0.0, landing_effect_duration)


func _apply_colors() -> void:
	var background: Color = _primary_color.darkened(background_darkening)
	background.a = 1.0
	var frame_color: Color = _primary_color
	frame_color.a = 1.0
	(frame.material as ShaderMaterial).set_shader_parameter("tint_color", frame_color)
	for mask_node: TextureRect in [speed_mask, barrier_mask, readout_mask]:
		(mask_node.material as ShaderMaterial).set_shader_parameter("background_color", background)
	(barrier_mask.material as ShaderMaterial).set_shader_parameter("fill_color", _secondary_color)
	var digit_color: Color = _primary_color.lightened(0.6)
	for digit_label: Label in current_digit_labels:
		digit_label.add_theme_color_override("font_color", digit_color)
	maximum_label.add_theme_color_override("font_color", digit_color)
	readout_divider.color = digit_color.darkened(0.15)
	for ghost: Label in [
		$Art/Readout/CurrentGhostHundreds,
		$Art/Readout/CurrentGhostTens,
		$Art/Readout/CurrentGhostOnes,
		$Art/Readout/MaximumGhost,
	]:
		ghost.add_theme_color_override("font_color", background.lightened(0.12))
	_set_barrier_indicator(true)


func _update_gauges() -> void:
	(speed_mask.material as ShaderMaterial).set_shader_parameter("progress", _speed_fraction)
	(barrier_mask.material as ShaderMaterial).set_shader_parameter("progress", _barrier_fraction)


func _set_barrier_indicator(force: bool = false) -> void:
	if not is_node_ready():
		return
	var active: bool = _target_barrier_fraction >= 1.0
	if active == _barrier_active and not force:
		return
	_barrier_active = active
	if _barrier_flash_tween and _barrier_flash_tween.is_valid():
		_barrier_flash_tween.kill()
	var inactive_color: Color = Color(0.12, 0.12, 0.15, 0.14)
	if not active:
		barrier_label.modulate = inactive_color
		return
	barrier_label.modulate = _secondary_color
	_barrier_flash_tween = create_tween().set_loops()
	_barrier_flash_tween.tween_property(barrier_label, "modulate", inactive_color, barrier_flash_duration)
	_barrier_flash_tween.tween_property(barrier_label, "modulate", _secondary_color, barrier_flash_duration)

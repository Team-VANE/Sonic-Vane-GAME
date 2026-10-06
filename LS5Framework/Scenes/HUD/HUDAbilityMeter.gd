extends Control
class_name HUDAbilityMeter

## Displays the current ability name over the meter.
@onready var ability_name_label: Label = $ContentMargin/MeterProgress/AbilityName
## Displays the normalized ability value inside the frame.
@onready var meter_progress: ProgressBar = $ContentMargin/MeterProgress
## Displays scanlines behind the ability progress fill.
@onready var meter_background: ColorRect = $Background
## Displays the colorized ability meter frame.
@onready var meter_frame: TextureRect = $Frame

## Delay after the last value change before the meter starts fading.
@export var unchanged_hold_duration: float = 1.5
## Duration of the fade-out after the unchanged-value delay.
@export var fade_duration: float = 0.3
## Minimum normalized value difference treated as a meter change.
@export var value_change_epsilon: float = 0.0005

var _last_ability_name: String = ""
var _last_fraction: float = -1.0
var _unchanged_timer: float = 0.0
var _available: bool = false
var _fade_tween: Tween = null


func _ready() -> void:
	if meter_background.material != null:
		meter_background.material = meter_background.material.duplicate()
	meter_background.resized.connect(_update_background_size)
	_update_background_size()
	if meter_frame.material != null:
		meter_frame.material = meter_frame.material.duplicate()
	_apply_meter_color(Color(0.05, 0.45, 1.0, 1.0))
	visible = false
	modulate.a = 0.0


func set_meter_color(color: Color) -> void:
	if meter_progress == null:
		if not is_node_ready():
			call_deferred("set_meter_color", color)
		return
	_apply_meter_color(color)


func set_frame_color(color: Color) -> void:
	if meter_frame == null:
		if not is_node_ready():
			call_deferred("set_frame_color", color)
		return
	var color_material: ShaderMaterial = meter_frame.material as ShaderMaterial
	if color_material != null:
		color_material.set_shader_parameter("tint_color", color)
	var background_material: ShaderMaterial = meter_background.material as ShaderMaterial
	if background_material != null:
		var panel_color: Color = color.darkened(0.92)
		panel_color.a = 0.88
		background_material.set_shader_parameter("panel_color", panel_color)
		background_material.set_shader_parameter("scanline_color", color.lightened(0.2))


func _update_background_size() -> void:
	if meter_background == null:
		return
	var background_material: ShaderMaterial = meter_background.material as ShaderMaterial
	if background_material != null:
		background_material.set_shader_parameter("panel_size", meter_background.size)


func _apply_meter_color(color: Color) -> void:
	var fill_style: StyleBoxFlat = meter_progress.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style == null:
		return
	var colored_fill: StyleBoxFlat = fill_style.duplicate() as StyleBoxFlat
	colored_fill.bg_color = color
	meter_progress.add_theme_stylebox_override("fill", colored_fill)


func _process(delta: float) -> void:
	if not _available or not visible:
		return
	if _unchanged_timer <= 0.0:
		return
	_unchanged_timer = max(_unchanged_timer - delta, 0.0)
	if _unchanged_timer <= 0.0:
		_fade_out()


func set_meter(ability_name: String, current: float, max_value: float, available: bool = true) -> void:
	if not available:
		_hide_immediately()
		return

	var denominator: float = max(max_value, 0.001)
	var fraction: float = clamp(max(current, 0.0) / denominator, 0.0, 1.0)
	var ability_changed: bool = ability_name != _last_ability_name
	var value_changed: bool = _last_fraction < 0.0 or abs(fraction - _last_fraction) > value_change_epsilon

	_available = true
	ability_name_label.text = ability_name
	meter_progress.value = fraction * 100.0

	if ability_changed or value_changed:
		_last_ability_name = ability_name
		_last_fraction = fraction
		_unchanged_timer = max(unchanged_hold_duration, 0.0)
		_show_immediately()


func _show_immediately() -> void:
	_kill_fade_tween()
	visible = true
	modulate.a = 1.0


func _fade_out() -> void:
	_kill_fade_tween()
	var duration: float = max(fade_duration, 0.0)
	if duration <= 0.0:
		visible = false
		modulate.a = 0.0
		return
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_QUAD)
	_fade_tween.set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 0.0, duration)
	_fade_tween.tween_callback(_finish_fade_out)


func _finish_fade_out() -> void:
	visible = false


func _hide_immediately() -> void:
	_kill_fade_tween()
	_available = false
	_last_ability_name = ""
	_last_fraction = -1.0
	_unchanged_timer = 0.0
	visible = false
	modulate.a = 0.0


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

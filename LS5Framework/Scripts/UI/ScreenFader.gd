extends CanvasLayer
class_name ScreenFader

@export var fade_color: Color = Color.BLACK
@export var default_fade_out_duration: float = 0.35
@export var default_fade_in_duration: float = 0.35
@export var auto_reset_color_after_fade_in: bool = true

signal fade_interrupted()

var _rect: ColorRect
var _fade_tween: Tween = null
var _scene_changed_connected: bool = false


func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = fade_color
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	_rect.anchor_left = 0.0
	_rect.anchor_top = 0.0
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	_rect.offset_left = 0.0
	_rect.offset_top = 0.0
	_rect.offset_right = 0.0
	_rect.offset_bottom = 0.0

	_set_alpha(0.0)
	_connect_scene_changed()


func _exit_tree() -> void:
	_kill_fade_tween()
	if get_tree() != null and _scene_changed_connected:
		if get_tree().scene_changed.is_connected(_on_scene_changed):
			get_tree().scene_changed.disconnect(_on_scene_changed)
	_scene_changed_connected = false


func set_fade_color(c: Color) -> void:
	fade_color = c
	if _rect != null:
		_rect.color = fade_color


func is_fully_black() -> bool:
	return _rect != null and _rect.modulate.a >= 0.999


func fade_out(duration: float = -1.0) -> void:
	var d: float = duration
	if d < 0.0:
		d = default_fade_out_duration
	await fade_to(1.0, d)


func fade_in(duration: float = -1.0) -> void:
	var d: float = duration
	if d < 0.0:
		d = default_fade_in_duration
	var completed: bool = await fade_to(0.0, d)
	if completed and auto_reset_color_after_fade_in:
		set_fade_color(Color.BLACK)


func fade_to(alpha: float, duration: float) -> bool:
	if _rect == null:
		return false

	var a: float = clamp(alpha, 0.0, 1.0)
	var d: float = max(duration, 0.0)

	_kill_fade_tween()
	if d <= 0.0:
		_set_alpha(a)
		return true
	var tween: Tween = create_tween()
	_fade_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_alpha, _rect.modulate.a, a, d)
	tween.finished.connect(fade_interrupted.emit, CONNECT_ONE_SHOT)
	await fade_interrupted
	if _fade_tween == tween:
		_fade_tween = null
		return true
	return false


func reset_now() -> void:
	_kill_fade_tween()
	set_fade_color(Color.BLACK)
	_set_alpha(0.0)


func _set_alpha(a: float) -> void:
	if _rect == null:
		return
	var m: Color = _rect.modulate
	m.a = clamp(a, 0.0, 1.0)
	_rect.modulate = m


func _kill_fade_tween() -> void:
	var tween: Tween = _fade_tween
	_fade_tween = null
	if tween and tween.is_valid():
		tween.kill()
		fade_interrupted.emit()


func _connect_scene_changed() -> void:
	if get_tree() == null:
		return
	if get_tree().scene_changed.is_connected(_on_scene_changed):
		_scene_changed_connected = true
		return
	get_tree().scene_changed.connect(_on_scene_changed)
	_scene_changed_connected = true


func _on_scene_changed() -> void:
	reset_now()

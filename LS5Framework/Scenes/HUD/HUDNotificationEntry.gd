extends Control
class_name HUDNotificationEntry

signal dismissed(entry: HUDNotificationEntry)

## Minimum width used by the notification frame.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px") var minimum_panel_width: float = 340.0
## Maximum width used by the notification frame before text is truncated.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:px") var maximum_panel_width: float = 720.0
## Amount the text and icon are lightened from the frame color.
@export_range(0.0, 1.0, 0.01) var foreground_lighten_amount: float = 0.35
## Time taken to sweep the notification onto the screen.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var enter_duration: float = 0.42
## Time taken to sweep the notification off the screen.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var exit_duration: float = 0.34
## Time taken to close the notification's stack space.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var collapse_duration: float = 0.22

## Displays the notification frame.
@onready var _panel: PanelContainer = $Panel
## Provides the frame's outer padding.
@onready var _content_margin: MarginContainer = $Panel/ContentMargin
## Arranges notification text and icon horizontally.
@onready var _content: HBoxContainer = $Panel/ContentMargin/Content
## Displays the notification title.
@onready var _title_label: Label = $Panel/ContentMargin/Content/Text/Title
## Displays optional notification detail text.
@onready var _detail_label: Label = $Panel/ContentMargin/Content/Text/Detail
## Displays an optional notification icon.
@onready var _icon: TextureRect = $Panel/ContentMargin/Content/Icon

var notification_key: StringName = &""
var _hold_remaining: float = 0.0
var _bpm: float = 0.0
var _animation_elapsed: float = 0.0
var _playback_position_provider: Callable = Callable()
var _wobble_icon: bool = false
var _active: bool = false
var _dismissing: bool = false
var _transition_tween: Tween = null
var _panel_style: StyleBoxFlat = null
var _primary_color: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self)
	var configured_style: StyleBox = _panel.get_theme_stylebox("panel")
	if configured_style is StyleBoxFlat:
		_panel_style = configured_style.duplicate() as StyleBoxFlat
		_panel.add_theme_stylebox_override("panel", _panel_style)
	if not resized.is_connected(_update_panel_layout):
		resized.connect(_update_panel_layout)
	if not _icon.resized.is_connected(_update_icon_pivot):
		_icon.resized.connect(_update_icon_pivot)
	_update_icon_pivot()
	_update_colors()
	set_process(true)


func _process(delta: float) -> void:
	if _active and not _dismissing:
		_hold_remaining = max(_hold_remaining - max(delta, 0.0), 0.0)
		if _hold_remaining <= 0.0:
			dismiss()
	_animation_elapsed += max(delta, 0.0)
	_update_icon_animation()


func configure(
		title: String,
		detail: String,
		icon_texture: Texture2D,
		duration: float,
		key: StringName,
		primary_color: Color,
		bpm: float = 0.0,
		playback_position_provider: Callable = Callable(),
		wobble_icon: bool = false
	) -> void:
	if is_queued_for_deletion() or not is_node_ready() or not _content_nodes_available():
		return
	notification_key = key
	_primary_color = primary_color
	_bpm = max(bpm, 0.0)
	_playback_position_provider = playback_position_provider
	_wobble_icon = wobble_icon
	_hold_remaining = max(duration, 0.0)
	_title_label.text = title
	_detail_label.text = detail
	_detail_label.visible = detail != ""
	_icon.texture = icon_texture
	_icon.visible = icon_texture != null
	_update_colors()
	_update_panel_width()
	call_deferred("_play_enter")


func refresh(
		title: String,
		detail: String,
		icon_texture: Texture2D,
		duration: float,
		primary_color: Color,
		bpm: float = 0.0,
		playback_position_provider: Callable = Callable(),
		wobble_icon: bool = false
	) -> void:
	if _dismissing or is_queued_for_deletion():
		return
	if not is_node_ready() or not _content_nodes_available():
		return
	var title_changed: bool = _title_label.text != title
	_primary_color = primary_color
	_bpm = max(bpm, 0.0)
	_playback_position_provider = playback_position_provider
	_wobble_icon = wobble_icon
	_hold_remaining = max(duration, 0.0)
	_title_label.text = title
	_detail_label.text = detail
	_detail_label.visible = detail != ""
	_icon.texture = icon_texture
	_icon.visible = icon_texture != null
	_update_colors()
	_update_panel_width()
	if title_changed:
		var pulse_tween: Tween = UIExcitementEffects.pulse_in(_panel, 0.24, 0.96, 1.025)
		if pulse_tween != null:
			_transition_tween = pulse_tween


func set_primary_color(primary_color: Color) -> void:
	_primary_color = primary_color
	if is_node_ready():
		_update_colors()


func dismiss(immediate: bool = false) -> void:
	if _dismissing:
		return
	_dismissing = true
	_active = false
	_kill_transition_tween()
	if not _content_nodes_available():
		visible = false
		_finish_dismissal()
		return
	if immediate or exit_duration <= 0.0:
		visible = false
		_finish_dismissal()
		return
	_transition_tween = UIExcitementEffects.sweep_out(
		_panel,
		Vector2(max(size.x, maximum_panel_width) + 40.0, 0.0),
		exit_duration,
		0.94
	)
	if _transition_tween == null:
		_finish_dismissal()
		return
	_transition_tween.tween_callback(_collapse)


func speed_up(speed_scale: float = 4.0) -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.set_speed_scale(max(speed_scale, 1.0))


func is_dismissing() -> bool:
	return _dismissing


func _play_enter() -> void:
	if _dismissing or not is_inside_tree() or not _content_nodes_available():
		return
	_update_panel_layout()
	_kill_transition_tween()
	_transition_tween = UIExcitementEffects.sweep_in(
		_panel,
		Vector2(max(size.x, maximum_panel_width) + 40.0, 0.0),
		enter_duration,
		0.94
	)
	_animation_elapsed = 0.0
	if _transition_tween == null:
		_active = true
		return
	_transition_tween.tween_callback(_activate)


func _activate() -> void:
	if not _dismissing:
		_active = true


func _collapse() -> void:
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(
		self,
		"custom_minimum_size",
		Vector2(custom_minimum_size.x, 0.0),
		max(collapse_duration, 0.01)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(self, "modulate:a", 0.0, max(collapse_duration, 0.01))
	_transition_tween.chain().tween_callback(_finish_dismissal)


func _finish_dismissal() -> void:
	dismissed.emit(self)
	queue_free()


func _update_colors() -> void:
	if not _content_nodes_available():
		return
	var foreground_color: Color = _primary_color.lightened(
		clamp(foreground_lighten_amount, 0.0, 1.0)
	)
	_title_label.add_theme_color_override("font_color", foreground_color)
	_detail_label.add_theme_color_override("font_color", foreground_color)
	_icon.self_modulate = foreground_color
	if _panel_style != null:
		_panel_style.border_color = _primary_color


func _update_panel_layout() -> void:
	if not is_node_ready() or not _content_nodes_available():
		return
	_update_panel_width()
	_panel.position.x = max(size.x - _panel.size.x, 0.0)


func _update_panel_width() -> void:
	if not _content_nodes_available():
		return
	var text_width: float = max(
		_get_label_rendered_width(_title_label),
		_get_label_rendered_width(_detail_label)
	)
	var fixed_width: float = float(_content_margin.get_theme_constant("margin_left"))
	fixed_width += float(_content_margin.get_theme_constant("margin_right"))
	if _icon.visible:
		fixed_width += _icon.custom_minimum_size.x
		fixed_width += float(_content.get_theme_constant("separation"))
	var panel_style: StyleBox = _panel.get_theme_stylebox("panel")
	if panel_style != null:
		fixed_width += panel_style.get_minimum_size().x
	var upper_limit: float = max(maximum_panel_width, minimum_panel_width)
	if size.x > 0.0:
		upper_limit = min(upper_limit, size.x)
	var lower_limit: float = min(max(minimum_panel_width, 0.0), upper_limit)
	var panel_width: float = clamp(ceil(text_width + fixed_width), lower_limit, upper_limit)
	_panel.custom_minimum_size = Vector2(panel_width, _panel.custom_minimum_size.y)
	_panel.size = Vector2(panel_width, _panel.size.y)


func _get_label_rendered_width(label: Label) -> float:
	if label == null or not label.visible or label.text == "":
		return 0.0
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
	var outline_size: int = label.get_theme_constant("outline_size")
	return text_width + float(outline_size * 2)


func _update_icon_animation() -> void:
	if not is_instance_valid(_icon) or not _icon.visible:
		return
	if _bpm > 0.0:
		var playback_position: float = _animation_elapsed
		if _playback_position_provider.is_valid():
			var playback_value: Variant = _playback_position_provider.call()
			if playback_value is float or playback_value is int:
				playback_position = float(playback_value)
		var beat_phase: float = fposmod(playback_position * _bpm / 60.0, 1.0)
		var pulse: float = pow(1.0 - beat_phase, 7.0)
		_icon.rotation = 0.0
		_icon.scale = Vector2.ONE * (1.0 + 0.14 * pulse)
		return
	if _wobble_icon:
		var wobble_phase: float = _animation_elapsed * TAU / 2.4
		_icon.rotation = deg_to_rad(5.0) * sin(wobble_phase)
		_icon.scale = Vector2.ONE * (1.0 + sin(wobble_phase * 2.0) * 0.025)
		return
	_icon.rotation = 0.0
	_icon.scale = Vector2.ONE


func _update_icon_pivot() -> void:
	if is_instance_valid(_icon):
		_icon.pivot_offset = _icon.size * 0.5


func _content_nodes_available() -> bool:
	return (
		is_instance_valid(_panel)
		and is_instance_valid(_content_margin)
		and is_instance_valid(_content)
		and is_instance_valid(_title_label)
		and is_instance_valid(_detail_label)
		and is_instance_valid(_icon)
	)


func _kill_transition_tween() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null


func _set_mouse_filter_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_mouse_filter_recursive(child)

extends PanelContainer
class_name HeldButtonPrompt

## Tint used by the contextual shortcut frame.
@export var frame_color: Color = Color(0.1, 0.6, 1.0)
## Height of the green hold-progress strip along the frame's bottom edge.
@export var progress_height: float = 6.0

## Displays the active controller button artwork.
var _icon: TextureRect
## Displays the shortcut key when no button artwork is available.
var _key: Label
## Displays the action and optional hold duration.
var _caption: Label
## Displays normalized hold completion along the frame's bottom edge.
var _progress: ProgressBar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.025, 0.045, 0.94)
	style.border_color = frame_color.lightened(0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", style)
	var content: HBoxContainer = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(38.0, 38.0)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(_icon)
	_key = Label.new()
	_key.add_theme_font_size_override("font_size", 18)
	content.add_child(_key)
	_caption = Label.new()
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 16)
	content.add_child(_caption)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.step = 0.0
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_progress.offset_left = 6.0
	_progress.offset_right = -6.0
	_progress.offset_top = -progress_height - 3.0
	_progress.offset_bottom = -3.0
	_progress.top_level = false
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.1, 0.95, 0.25, 1.0)
	fill.set_corner_radius_all(2)
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.02, 0.08, 0.03, 0.8)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.add_theme_stylebox_override("background", background)
	var bar_layer: Control = Control.new()
	bar_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bar_layer)
	bar_layer.add_child(_progress)
	set_hold_progress(0.0)
	for child: Control in [_icon, _key, _caption]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(glyph: Dictionary, caption: String, held: bool = false) -> void:
	_icon.texture = glyph.get("texture") as Texture2D
	_icon.visible = _icon.texture != null
	_key.text = String(glyph.get("label", "")) if _icon.texture == null else ""
	_key.visible = not _icon.visible
	_caption.text = caption
	_progress.visible = held

func set_hold_progress(ratio: float) -> void:
	if _progress != null:
		_progress.value = clampf(ratio, 0.0, 1.0)

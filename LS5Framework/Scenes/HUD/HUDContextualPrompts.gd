extends HUDActionPrompts
class_name HUDContextualPrompts

## Minimum dimensions of each contextual ability card.
@export var card_size: Vector2 = Vector2(164.0, 190.0)
## Display bounds for contextual button glyphs.
@export var card_glyph_size: Vector2 = Vector2(98.0, 104.0)
## Number of outer-frame flashes per second.
@export_range(0.2, 10.0, 0.1) var flash_frequency: float = 5.0

var _flash_time: float = 0.0


func _process(delta: float) -> void:
	super._process(delta)
	if not visible:
		_flash_time = 0.0
		return
	_flash_time += delta
	var pulse: float = 0.5 + 0.5 * cos(_flash_time * TAU * flash_frequency)
	for row: PanelContainer in _row_nodes.values():
		var frame: StyleBoxFlat = row.get_theme_stylebox("panel") as StyleBoxFlat
		if not frame:
			continue
		var color: Color = _primary_color.lightened(0.25).lerp(Color.WHITE, pulse)
		color.a = lerpf(0.4, 1.0, pulse)
		frame.border_color = color
		frame.set_border_width_all(int(round(lerpf(3.0, 8.0, pulse))))
		frame.shadow_size = int(round(lerpf(8.0, 14.0, pulse)))
		frame.shadow_color = Color(color, lerpf(0.08, 0.55, pulse))


func _update_row(row: PanelContainer, entry: Dictionary) -> void:
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	row.custom_minimum_size = card_size
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.bg_color = Color(0.012, 0.025, 0.045, 0.92)
	frame.border_color = _primary_color.lightened(0.25)
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(12)
	frame.shadow_size = 8
	frame.content_margin_left = 10.0
	frame.content_margin_right = 10.0
	frame.content_margin_top = 12.0
	frame.content_margin_bottom = 10.0
	row.add_theme_stylebox_override("panel", frame)
	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(content)
	var glyph_row: HBoxContainer = HBoxContainer.new()
	glyph_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_row.alignment = BoxContainer.ALIGNMENT_CENTER
	glyph_row.custom_minimum_size.y = card_glyph_size.y
	content.add_child(glyph_row)
	var glyphs: Array = entry["glyphs"]
	for index: int in glyphs.size():
		if index:
			_add_label(glyph_row, "+", 22)
		var glyph: Dictionary = glyphs[index]
		var texture: Texture2D = glyph.get("texture") as Texture2D
		if texture:
			var icon: TextureRect = TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = card_glyph_size
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph_row.add_child(icon)
		else:
			var key: Label = _add_label(glyph_row, String(glyph["label"]), 26)
			key.add_theme_color_override("font_color", _primary_color.lightened(0.4))
			key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			key.custom_minimum_size = card_glyph_size
			key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var direction: String = String(glyph.get("direction", ""))
		if direction:
			_add_label(glyph_row, direction, 22)
	var label: Label = _add_label(content, String(entry["label"]), 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = 52.0

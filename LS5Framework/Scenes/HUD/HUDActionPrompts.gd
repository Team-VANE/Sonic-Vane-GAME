extends Control
class_name HUDActionPrompts

## Controller artwork used by action prompts. Auto follows the active controller identity.
@export_enum("Auto", "PlayStation", "Generic") var glyph_style: int = InputBindingGlyphs.Style.AUTO
## Maximum number of simultaneously displayed action prompts.
@export_range(1, 16, 1) var maximum_rows: int = 8
## Minimum vertical space reserved by each prompt row.
@export var row_height: float = 40.0
## Display bounds for each button or axis glyph.
@export var glyph_size: Vector2 = Vector2(56.0, 34.0)
## Width reserved for input glyphs and key names in the normal prompt rows.
@export var binding_area_width: float = 210.0
## Delay before passive mouse motion replaces controller glyphs.
@export var mouse_switch_delay: float = 0.4
## Displays contextual entries instead of the normal ability list.
@export var contextual: bool = false
## Container for the available action rows.
@onready var rows: BoxContainer = $Rows

var _source: Node = null
var _prompts: Array[Dictionary] = []
var _signature: String = ""
var _controller: bool = false
var _device: int = -1
var _mouse_pending: bool = false
var _mouse_elapsed: float = 0.0
var _primary_color: Color = Color(0.1, 0.6, 1.0)
var _row_nodes: Dictionary = {}


func _ready() -> void:
	_controller = SettingsManager.is_controller_input_active()
	_device = SettingsManager.get_preferred_joypad_device()
	SettingsManager.input_bindings_changed.connect(_invalidate)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_set_input_source(true, event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.3:
		_set_input_source(true, event.device)
	elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		_set_input_source(false)
	elif event is InputEventMouseMotion and event.relative.length_squared() >= 4.0 and _controller:
		if not _mouse_pending:
			_mouse_elapsed = 0.0
		_mouse_pending = true


func _process(delta: float) -> void:
	if _mouse_pending:
		_mouse_elapsed += delta
		if _mouse_elapsed >= mouse_switch_delay:
			_set_input_source(false)
	if not is_instance_valid(_source) or not SettingsManager.hud_visible or not SettingsManager.action_prompts_visible or not _source.can_offer_action_prompts():
		visible = false
		return
	_render_prompts()


func set_prompts(prompts: Array[Dictionary], source: Node) -> void:
	_source = source
	_prompts = prompts


func set_frame_color(color: Color) -> void:
	if color == _primary_color:
		return
	_primary_color = color
	_invalidate()


func _set_input_source(controller: bool, device: int = -1) -> void:
	_mouse_pending = false
	_mouse_elapsed = 0.0
	if _controller == controller and (not controller or device == _device):
		return
	_controller = controller
	if controller:
		_device = device
	_invalidate()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == _device:
		_set_input_source(false)
	_invalidate()


func _invalidate(_action: StringName = &"") -> void:
	_signature = ""


func _render_prompts() -> void:
	var resolved_style: int = InputBindingGlyphs.resolve_style(glyph_style, _device)
	var displayed: Array[Dictionary] = []
	var signature_parts: PackedStringArray = [str(resolved_style), str(maximum_rows), str(glyph_size), str(row_height), str(binding_area_width), str(_primary_color)]
	for prompt: Dictionary in _prompts:
		if bool(prompt.get("contextual", false)) != contextual:
			continue
		var glyphs: Array[Dictionary] = []
		var bound: bool = true
		for value: Variant in prompt.get("slots", []):
			var glyph: Dictionary = InputBindingGlyphs.get_slot_glyph(StringName(value), _controller, resolved_style, _device)
			if glyph.is_empty():
				bound = false
				break
			glyphs.append(glyph)
		if not bound:
			continue
		var entry: Dictionary = prompt.duplicate()
		entry["glyphs"] = glyphs
		displayed.append(entry)
		signature_parts.append(String(prompt["id"]) + String(prompt["label"]) + String(prompt["gesture"]))
		for glyph: Dictionary in glyphs:
			signature_parts.append(String(glyph["label"]) + String(glyph.get("asset", "")))
		if displayed.size() >= maximum_rows:
			break
	visible = not displayed.is_empty()
	var signature: String = "|".join(signature_parts)
	if signature == _signature:
		return
	_signature = signature
	var retained: Array[String] = []
	for entry: Dictionary in displayed:
		var id: String = String(entry["id"])
		retained.append(id)
		var row: PanelContainer = _row_nodes.get(id) as PanelContainer
		if not row:
			row = PanelContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(row)
			_row_nodes[id] = row
		_update_row(row, entry)
		rows.move_child(row, retained.size() - 1)
	for id: String in _row_nodes.keys():
		if not retained.has(id):
			var row: PanelContainer = _row_nodes[id]
			rows.remove_child(row)
			row.queue_free()
			_row_nodes.erase(id)


func _update_row(row: PanelContainer, entry: Dictionary) -> void:
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	row.custom_minimum_size.y = row_height
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.025, 0.045, 0.86)
	style.border_color = _primary_color
	style.border_width_left = 3
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10.0
	style.content_margin_right = 12.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	row.add_theme_stylebox_override("panel", style)
	var content: HBoxContainer = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	row.add_child(content)
	var binding_area: MarginContainer = MarginContainer.new()
	binding_area.name = "BindingArea"
	binding_area.custom_minimum_size.x = binding_area_width
	binding_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(binding_area)
	var bindings: HBoxContainer = HBoxContainer.new()
	bindings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bindings.alignment = BoxContainer.ALIGNMENT_CENTER
	bindings.add_theme_constant_override("separation", 8)
	binding_area.add_child(bindings)
	var divider: ColorRect = ColorRect.new()
	divider.color = Color(_primary_color, 0.35)
	divider.custom_minimum_size.x = 1.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)
	var label_area: HBoxContainer = HBoxContainer.new()
	label_area.name = "LabelArea"
	label_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_area.add_theme_constant_override("separation", 8)
	content.add_child(label_area)
	var glyphs: Array = entry["glyphs"]
	for index: int in glyphs.size():
		if index:
			_add_label(bindings, "+", 18)
		var glyph: Dictionary = glyphs[index]
		var texture: Texture2D = glyph.get("texture") as Texture2D
		if texture:
			var image: TextureRect = TextureRect.new()
			image.texture = texture
			image.custom_minimum_size = glyph_size
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bindings.add_child(image)
			var direction: String = String(glyph.get("direction", ""))
			if direction:
				_add_label(bindings, direction, 22)
			var caption: String = String(glyph.get("caption", ""))
			if caption:
				_add_label(bindings, caption, 18)
		else:
			var key: Label = _add_label(bindings, String(glyph["label"]), 18)
			key.add_theme_color_override("font_color", _primary_color.lightened(0.35))
	var gesture: StringName = StringName(entry["gesture"])
	var gesture_text: String = {&"tap": "Tap", &"hold": "Hold", &"release": "Release"}.get(gesture, "")
	var badge: Label = _add_label(label_area, gesture_text, 16)
	badge.custom_minimum_size.x = 56.0
	badge.modulate = Color(0.7, 0.8, 0.9)
	var action_label: Label = _add_label(label_area, String(entry["label"]), 22)
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _add_label(parent: Node, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

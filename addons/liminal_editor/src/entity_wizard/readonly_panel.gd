@tool
class_name LMEntityReadonlyPanel extends VBoxContainer

var _editor_interface: EditorInterface = null

var _classname_lbl: Label
var _source_path_lbl: Label
var _description_lbl: Label
var _props_container: VBoxContainer
var _props_grid: GridContainer
var _props_empty_lbl: Label
var _gizmos_container: VBoxContainer
var _current_info: LMEntityScanResult = null


func _ready() -> void:
	name = "ReadonlyPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_build_ui()


func _build_ui() -> void:
	var header_box := HBoxContainer.new()
	header_box.add_theme_constant_override("separation", 8)
	add_child(header_box)

	var lock_icon := TextureRect.new()
	lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	lock_icon.custom_minimum_size = Vector2(16, 16)
	header_box.add_child(lock_icon)
	lock_icon.ready.connect(func() -> void:
		lock_icon.texture = get_theme_icon("Lock", "EditorIcons")
	)

	var header_vbox := VBoxContainer.new()
	header_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vbox.add_theme_constant_override("separation", 2)
	header_box.add_child(header_vbox)

	_classname_lbl = Label.new()
	_classname_lbl.name = "ClassnameLbl"
	_classname_lbl.add_theme_font_size_override("font_size", 14)
	header_vbox.add_child(_classname_lbl)

	_source_path_lbl = Label.new()
	_source_path_lbl.name = "SourcePathLbl"
	_source_path_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_source_path_lbl.add_theme_font_size_override("font_size", 10)
	_source_path_lbl.clip_text = true
	header_vbox.add_child(_source_path_lbl)

	var notice_box := VBoxContainer.new()
	notice_box.name = "NoticeBox"
	notice_box.add_theme_constant_override("separation", 6)
	add_child(notice_box)

	var readonly_notice := Label.new()
	readonly_notice.text = "Read-only  -  edit the source script to change properties"
	readonly_notice.add_theme_color_override("font_color", Color("#f59e0b"))
	readonly_notice.add_theme_font_size_override("font_size", 13)
	notice_box.add_child(readonly_notice)

	var open_script_btn := Button.new()
	open_script_btn.name = "OpenScriptBtn"
	open_script_btn.text = "Open Script"
	open_script_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_script_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open_script_btn.pressed.connect(_on_open_script_pressed)
	open_script_btn.ready.connect(func() -> void:
		open_script_btn.icon = get_theme_icon("Script", "EditorIcons")
	)
	notice_box.add_child(open_script_btn)

	_description_lbl = Label.new()
	_description_lbl.name = "DescriptionLbl"
	_description_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	add_child(_description_lbl)

	var props_header := Label.new()
	props_header.text = "Properties"
	props_header.add_theme_font_size_override("font_size", 12)
	add_child(props_header)

	var props_sep := HSeparator.new()
	add_child(props_sep)

	_props_container = VBoxContainer.new()
	_props_container.name = "PropsContainer"
	_props_container.add_theme_constant_override("separation", 2)
	add_child(_props_container)

	_props_empty_lbl = Label.new()
	_props_empty_lbl.name = "PropsEmpty"
	_props_empty_lbl.text = "No exported properties"
	_props_empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_props_empty_lbl.add_theme_font_size_override("font_size", 11)
	_props_container.add_child(_props_empty_lbl)

	_props_grid = GridContainer.new()
	_props_grid.name = "PropsGrid"
	_props_grid.columns = 4
	_props_grid.add_theme_constant_override("h_separation", 16)
	_props_grid.add_theme_constant_override("v_separation", 5)
	_props_grid.visible = false
	_props_container.add_child(_props_grid)

	var gizmos_header := Label.new()
	gizmos_header.text = "Gizmos"
	gizmos_header.add_theme_font_size_override("font_size", 12)
	add_child(gizmos_header)

	var gizmos_sep := HSeparator.new()
	add_child(gizmos_sep)

	_gizmos_container = VBoxContainer.new()
	_gizmos_container.name = "GizmosContainer"
	_gizmos_container.add_theme_constant_override("separation", 2)
	add_child(_gizmos_container)

	var gizmos_empty := Label.new()
	gizmos_empty.name = "GizmosEmpty"
	gizmos_empty.text = "No gizmos"
	gizmos_empty.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	gizmos_empty.add_theme_font_size_override("font_size", 11)
	_gizmos_container.add_child(gizmos_empty)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	add_child(spacer)


func load_info(info: LMEntityScanResult) -> void:
	_current_info = info
	_classname_lbl.text = info.classname
	_source_path_lbl.text = info.source_path
	_description_lbl.text = info.description
	_description_lbl.visible = not info.description.is_empty()

	for c in _props_grid.get_children():
		c.queue_free()

	if info.props.is_empty():
		_props_empty_lbl.visible = true
		_props_grid.visible = false
	else:
		_props_empty_lbl.visible = false
		_props_grid.visible = true
		for prop in info.props:
			_add_prop_to_grid(prop)

	for c in _gizmos_container.get_children():
		c.queue_free()
	if info.gizmos.is_empty():
		var lbl := Label.new()
		lbl.text = "No gizmos"
		lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		lbl.add_theme_font_size_override("font_size", 11)
		_gizmos_container.add_child(lbl)
	else:
		for g in info.gizmos:
			_gizmos_container.add_child(_build_gizmo_row(g))


func _add_prop_to_grid(prop: Dictionary) -> void:
	var name_lbl := Label.new()
	name_lbl.text = prop.get("name", "")
	name_lbl.custom_minimum_size.x = 120
	name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_props_grid.add_child(name_lbl)

	var type_lbl := Label.new()
	type_lbl.text = prop.get("type", "")
	type_lbl.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
	type_lbl.add_theme_font_size_override("font_size", 11)
	type_lbl.custom_minimum_size.x = 80
	type_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_props_grid.add_child(type_lbl)

	if prop.has("choices_labels"):
		var labels: Array = prop["choices_labels"]
		type_lbl.tooltip_text = "\n".join(labels)
		type_lbl.mouse_filter = Control.MOUSE_FILTER_PASS

	var default_lbl := Label.new()
	if prop.has("default_value"):
		var fmt := _format_default(prop)
		default_lbl.text = fmt["display"]
	default_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	default_lbl.add_theme_font_size_override("font_size", 11)
	default_lbl.custom_minimum_size.x = 80
	default_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_props_grid.add_child(default_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = prop.get("description", "")
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.clip_text = true
	desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_props_grid.add_child(desc_lbl)


func _format_default(prop: Dictionary) -> Dictionary:
	var val: Variant = prop["default_value"]
	if prop.has("enum_hint_string") and val is int:
		for pair in (prop["enum_hint_string"] as String).split(","):
			var parts := pair.split(":")
			if parts.size() >= 2 and int(parts[1].strip_edges()) == val:
				return {"display": parts[0].strip_edges(), "tooltip": ""}

	if val is Array:
		var items := _collect_readable((val as Array))
		if not items.is_empty():
			return _format_list(items)

	if val is Dictionary:
		var items := _collect_readable((val as Dictionary).values())
		if items.is_empty():
			items = _collect_readable((val as Dictionary).keys())
		if not items.is_empty():
			return _format_list(items)

	var s := _readable(val)
	if not s.is_empty():
		return {"display": s, "tooltip": ""}

	return {"display": str(val), "tooltip": ""}


func _collect_readable(arr: Array) -> Array[String]:
	var out: Array[String] = []
	for v in arr:
		var s := _readable(v)
		if not s.is_empty():
			out.append(s)
	return out


func _readable(v: Variant) -> String:
	if v == null:
		return ""
	if v is Resource:
		var path := (v as Resource).resource_path
		if not path.is_empty():
			return path.split("::")[0].get_file().get_basename()
		return "(%s)" % (v as Resource).get_class()
	if v is String:
		var s := v as String
		if s.begins_with("res://"):
			return s.split("::")[0].get_file().get_basename()
		return s
	return str(v)


func _format_list(items: Array[String]) -> Dictionary:
	const MAX_ITEMS := 5
	var tooltip := "\n".join(items)
	if items.size() <= MAX_ITEMS:
		return {"display": ", ".join(items), "tooltip": tooltip}
	var shown: Array[String] = items.slice(0, MAX_ITEMS)
	var display := ", ".join(shown) + ", %d more" % (items.size() - MAX_ITEMS)
	return {"display": display, "tooltip": tooltip}


func _build_gizmo_row(g: Variant) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	if g is Dictionary:
		lbl.text = "%s  (%s)" % [g.get("type", ""), g.get("prop", "")]
	else:
		lbl.text = str(g)
	panel.add_child(lbl)
	return panel


func _on_open_script_pressed() -> void:
	if not _current_info or not _editor_interface: return
	var path: String = _current_info.script_path if not _current_info.script_path.is_empty() \
		else _current_info.source_path
	var res := ResourceLoader.load(path)
	if res:
		_editor_interface.edit_resource(res)

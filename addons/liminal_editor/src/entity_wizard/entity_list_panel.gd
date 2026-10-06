@tool
class_name LMEntityListPanel extends VBoxContainer

const _ICON_DEF_PATH  = "res://addons/liminal_editor/icons/icon_entity_def.svg"
const _ICON_CODE_PATH = "res://addons/liminal_editor/icons/icon_entity_code.svg"

signal entity_activated(info: LMEntityScanResult)

var _entity_list_container: VBoxContainer
var _entity_filter_edit: LineEdit
var _all_entity_items: Array[Dictionary] = []
var _selected_entity_row: Control = null
var _dpi_scale: float = 1.0


func _s(val: float) -> int:
	return int(val * _dpi_scale)


func _ready() -> void:
	_dpi_scale = EditorInterface.get_editor_scale()
	if _dpi_scale <= 0.0:
		_dpi_scale = 1.0

	name = "Sidebar"
	custom_minimum_size.x = _s(220)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", _s(4))

	var header_row := HBoxContainer.new()
	header_row.name = "SidebarHeaderRow"
	header_row.add_theme_constant_override("separation", _s(4))
	add_child(header_row)

	var header := Label.new()
	header.name = "SidebarHeader"
	header.text = "Entity Definitions"
	header.add_theme_font_size_override("font_size", _s(13))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)

	var refresh_btn := Button.new()
	refresh_btn.name = "BtnRefresh"
	refresh_btn.flat = true
	refresh_btn.tooltip_text = "Refresh entity list"
	refresh_btn.icon = get_theme_icon("Reload", "EditorIcons")
	refresh_btn.pressed.connect(refresh)
	header_row.add_child(refresh_btn)

	_entity_filter_edit = LineEdit.new()
	_entity_filter_edit.name = "EntityFilter"
	_entity_filter_edit.placeholder_text = "Filter..."
	_entity_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entity_filter_edit.text_changed.connect(_on_filter_changed)
	add_child(_entity_filter_edit)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "EntityListScroll"
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(list_scroll)

	_entity_list_container = VBoxContainer.new()
	_entity_list_container.name = "EntityList"
	_entity_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entity_list_container.add_theme_constant_override("separation", _s(1))
	list_scroll.add_child(_entity_list_container)


func refresh() -> void:
	_all_entity_items.clear()
	_selected_entity_row = null
	if not _entity_list_container: return
	for c in _entity_list_container.get_children():
		c.queue_free()

	var entity_dirs: Array = ProjectSettings.get_setting(LMPlugin.CFG_KEY_ENTITY_DIRS, [])
	var infos := LiminalEditor.scan_entity_infos(entity_dirs)
	infos.sort_custom(func(a: LMEntityScanResult, b: LMEntityScanResult) -> bool:
		var a_def := a.source_type == "definition"
		var b_def := b.source_type == "definition"
		if a_def != b_def: return a_def
		return a.classname.naturalnocasecmp_to(b.classname) < 0
	)
	for info in infos:
		_all_entity_items.append({"name": info.classname, "path": info.source_path, "info": info})

	_apply_filter(_entity_filter_edit.text if _entity_filter_edit else "")


func _on_filter_changed(filter: String) -> void:
	_apply_filter(filter)


func _apply_filter(filter: String) -> void:
	if not _entity_list_container: return
	for c in _entity_list_container.get_children():
		c.queue_free()
	_selected_entity_row = null
	var fl := filter.to_lower()

	var groups: Dictionary = {}
	for item in _all_entity_items:
		if fl.is_empty() or (item.name as String).to_lower().contains(fl) \
				or (item.path as String).to_lower().contains(fl):
			var key := _get_group_label(item.path as String)
			if not groups.has(key):
				groups[key] = []
			groups[key].append(item)

	var keys := groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		if a == "res://": return true
		if b == "res://": return false
		return a.naturalnocasecmp_to(b) < 0
	)
	var show_headers := keys.size() > 1
	for key in keys:
		if show_headers:
			_entity_list_container.add_child(_build_group_header(key))
		for item in groups[key]:
			var row := _build_row(item)
			item["row_panel"] = row
			_entity_list_container.add_child(row)


func _get_group_label(path: String) -> String:
	return path.get_base_dir()


func _build_group_header(text: String) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _s(8))
	margin.add_theme_constant_override("margin_top", _s(6))
	margin.add_theme_constant_override("margin_bottom", _s(2))
	margin.add_theme_constant_override("margin_right", 0)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", _s(11))
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	lbl.clip_text = true
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(lbl)
	return margin


func _build_row(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = item.path

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _s(6))
	margin.add_theme_constant_override("margin_right", _s(6))
	margin.add_theme_constant_override("margin_top", _s(1))
	margin.add_theme_constant_override("margin_bottom", _s(1))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", _s(6))
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	var icon_rect := TextureRect.new()
	var info: LMEntityScanResult = item.info
	var icon_texture: Texture2D
	match info.source_type:
		"scene", "script": icon_texture = load(_ICON_CODE_PATH)
		_:                 icon_texture = load(_ICON_DEF_PATH)
	icon_rect.texture = icon_texture if icon_texture else get_theme_icon("Resource", "EditorIcons")
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_FILL
	icon_rect.custom_minimum_size = Vector2(_s(18), 0)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_rect)

	var name_lbl := Label.new()
	name_lbl.text = item.name
	name_lbl.add_theme_font_size_override("font_size", _s(13))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.tooltip_text = item.path
	name_lbl.clip_text = true
	hbox.add_child(name_lbl)

	var info_ref: LMEntityScanResult = item.info

	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_row(panel)
			entity_activated.emit(info_ref)
	)
	panel.mouse_entered.connect(func() -> void:
		if _selected_entity_row != panel:
			var s := StyleBoxFlat.new()
			s.bg_color = Color(1, 1, 1, 0.05)
			panel.add_theme_stylebox_override("panel", s)
	)
	panel.mouse_exited.connect(func() -> void:
		if _selected_entity_row != panel:
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	)
	return panel


func select_by_source_path(path: String) -> void:
	for item in _all_entity_items:
		var row: Control = item.get("row_panel")
		if item.path == path and row and is_instance_valid(row):
			_select_row(row)
			return


func _select_row(row: Control) -> void:
	if _selected_entity_row and is_instance_valid(_selected_entity_row):
		_selected_entity_row.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_selected_entity_row = row
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.25, 0.45, 0.85, 0.35)
	row.add_theme_stylebox_override("panel", s)

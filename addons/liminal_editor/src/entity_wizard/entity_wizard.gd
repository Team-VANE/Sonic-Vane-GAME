@tool
class_name LMEntityWizard extends Control

class _BaseResFilter extends EditorInspectorPlugin:
	const _HIDDEN: Array[String] = [
		"resource_local_to_scene", "resource_path", "resource_name", "script",
	]
	func _can_handle(obj: Object) -> bool:
		return obj is LMChoicesProvider
	func _parse_property(_obj: Object, _type: Variant.Type, name: String,
			_hint: PropertyHint, _hint_str: String, _usage: int, _wide: bool) -> bool:
		return name in _HIDDEN

var entity_def: LMEntityDefinition = null
var editor_interface: EditorInterface = null
var export_callable: Callable = Callable()
var show_callable: Callable = Callable()
var hide_callable: Callable = Callable()
var toggle_float_callable: Callable = Callable()
var lm_plugin: EditorPlugin
var _base_control: Control
var _filter_plugin: _BaseResFilter
var _filter_registered: bool = false
var _ui_built := false

var _dirty: bool = false
var _loading: bool = false
var _confirm_discard: ConfirmationDialog
var _pending_def: LMEntityDefinition = null
var _pending_readonly_info: LMEntityScanResult = null

var _def_name_lbl: Label
var _def_path_lbl: Button
var _checkmark_lbl: Label
var _apply_btn: Button
var _editor_area: VBoxContainer
var _empty_state: Control
var _readonly_scroll: ScrollContainer
var _readonly_panel: LMEntityReadonlyPanel
var _sidebar: LMEntityListPanel
var _sidebar_divider: VSeparator
var _sidebar_visible: bool = true
var _breadcrumb_wrap: MarginContainer
var _breadcrumb: HBoxContainer
var _breadcrumb_sep: HSeparator

var _props_panel: LMPropsPanel
var _gizmos_panel: LMGizmosPanel
var _drag: LMBindingDrag


func _ready() -> void:
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	if _ui_built: return
	_ui_built = true
	_filter_plugin = _BaseResFilter.new()
	_drag = LMBindingDrag.new()
	_build_ui()


func setup() -> void:
	_confirm_discard = ConfirmationDialog.new()
	_confirm_discard.title = "Discard Changes?"
	_confirm_discard.confirmed.connect(_on_confirm_discard)
	_base_control.add_child(_confirm_discard)
	var sidebar_pref: bool = EditorInterface.get_editor_settings().get_setting(
		LMPlugin.EDITOR_CFG_KEY_SIDEBAR_VISIBLE)
	_apply_sidebar_visibility(sidebar_pref)
	editor_interface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


func _toggle_sidebar() -> void:
	_apply_sidebar_visibility(not _sidebar_visible)
	EditorInterface.get_editor_settings().set_setting(
		LMPlugin.EDITOR_CFG_KEY_SIDEBAR_VISIBLE, _sidebar_visible)


func _apply_sidebar_visibility(p_visible: bool) -> void:
	_sidebar_visible = p_visible
	_sidebar.visible = p_visible
	_sidebar_divider.visible = p_visible


func _on_visibility_changed() -> void:
	if visible:
		_register_filter()
		if _empty_state and _empty_state.visible:
			_sidebar.refresh()
	else:
		_unregister_filter()


func _register_filter() -> void:
	if lm_plugin and _filter_plugin and not _filter_registered:
		lm_plugin.add_inspector_plugin(_filter_plugin)
		_filter_registered = true


func _unregister_filter() -> void:
	if lm_plugin and _filter_plugin and _filter_registered:
		lm_plugin.remove_inspector_plugin(_filter_plugin)
		_filter_registered = false


func cleanup() -> void:
	_unregister_filter()
	if editor_interface and editor_interface.get_resource_filesystem().filesystem_changed.is_connected(_on_filesystem_changed):
		editor_interface.get_resource_filesystem().filesystem_changed.disconnect(_on_filesystem_changed)


func _on_filesystem_changed() -> void:
	if entity_def != null and not entity_def.resource_path.is_empty() \
			and not FileAccess.file_exists(entity_def.resource_path):
		open_no_def()
	elif visible:
		_sidebar.refresh()


func _process(_delta: float) -> void:
	if not visible or not _props_panel: return
	_props_panel.tick_drag()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).ctrl_pressed and (event as InputEventKey).keycode == KEY_S:
		if entity_def != null and _dirty:
			_on_apply()
			accept_event()



func _on_confirm_discard() -> void:
	_dirty = false
	if _pending_def != null:
		var def := _pending_def
		_pending_def = null
		_pending_readonly_info = null
		_do_open(def)
	elif _pending_readonly_info != null:
		var info := _pending_readonly_info
		_pending_readonly_info = null
		_do_open_readonly(info)
	else:
		open_no_def()


func _on_entity_activated(info: LMEntityScanResult) -> void:
	if info.entity_def != null:
		open(info.entity_def)
	else:
		_open_readonly(info)


func open(def: LMEntityDefinition) -> void:
	if _dirty and entity_def != null and def != entity_def:
		_pending_def = def
		_pending_readonly_info = null
		var name := def.resource_path.get_file().get_basename()
		_confirm_discard.dialog_text = \
			"You have unsaved changes to '%s'.\nOpening '%s' will discard them." \
			% [entity_def.resource_path.get_file().get_basename(), name]
		_confirm_discard.popup_centered()
		return
	_pending_def = null
	_pending_readonly_info = null
	_do_open(def)


func _open_readonly(info: LMEntityScanResult) -> void:
	if _dirty and entity_def != null:
		_pending_def = null
		_pending_readonly_info = info
		_confirm_discard.dialog_text = \
			"You have unsaved changes to '%s'.\nDiscarding them?" \
			% entity_def.resource_path.get_file().get_basename()
		_confirm_discard.popup_centered()
		return
	_pending_def = null
	_pending_readonly_info = null
	_do_open_readonly(info)


func _do_open(def: LMEntityDefinition) -> void:
	entity_def = def
	_dirty = false
	_loading = true
	_register_filter()
	_empty_state.visible = false
	_readonly_scroll.visible = false
	_breadcrumb_wrap.visible = true
	_breadcrumb_sep.visible = true
	_editor_area.visible = true
	_props_panel.reset()
	_props_panel.set_description(def.description)
	_gizmos_panel.reset()
	_props_panel.restore_from_def(def)
	_gizmos_panel.restore_from_def(def)
	_loading = false
	_update_def_header()
	_update_saved_indicator()
	_sidebar.select_by_source_path(def.resource_path)
	if show_callable.is_valid(): show_callable.call()
	else: show()


func _do_open_readonly(info: LMEntityScanResult) -> void:
	entity_def = null
	_dirty = false
	_empty_state.visible = false
	_editor_area.visible = false
	_breadcrumb_wrap.visible = true
	_breadcrumb_sep.visible = true
	_readonly_scroll.visible = true
	if _def_name_lbl: _def_name_lbl.text = info.classname
	if _def_path_lbl: _def_path_lbl.text = "🔗 " + info.source_path
	_checkmark_lbl.visible = false
	_readonly_panel.load_info(info)
	_sidebar.select_by_source_path(info.source_path)
	if show_callable.is_valid(): show_callable.call()
	else: show()


func open_no_def() -> void:
	entity_def = null
	_dirty = false
	_register_filter()
	_empty_state.visible = true
	_readonly_scroll.visible = false
	_breadcrumb_wrap.visible = false
	_breadcrumb_sep.visible = false
	_editor_area.visible = false
	_apply_btn.disabled = true
	_def_name_lbl.text = ""
	_def_path_lbl.text = ""
	_checkmark_lbl.visible = false
	_sidebar.refresh()
	if show_callable.is_valid(): show_callable.call()
	else: show()


func _mark_dirty() -> void:
	if _loading: return
	_dirty = true
	_update_saved_indicator()


func _update_saved_indicator() -> void:
	if _checkmark_lbl:
		_checkmark_lbl.visible = not _dirty
	if _apply_btn and entity_def != null:
		_apply_btn.disabled = not _dirty


func _update_def_header() -> void:
	if not entity_def: return
	if _def_name_lbl:
		var rp := entity_def.resource_path
		_def_name_lbl.text = rp.get_file().get_basename() if not rp.is_empty() else "(unsaved)"
	if _def_path_lbl:
		_def_path_lbl.text = "🔗 " + entity_def.resource_path



func _on_cancel_pressed() -> void:
	if _dirty:
		_pending_def = null
		_confirm_discard.dialog_text = "You have unsaved changes. Close anyway?"
		_confirm_discard.popup_centered()
	else:
		open_no_def()


func _on_apply() -> void:
	if not entity_def: return
	_do_apply()
	_dirty = false
	_update_saved_indicator()


func _do_apply() -> void:
	if entity_def.entity_name.is_empty():
		entity_def.entity_name = entity_def.resource_path.get_file().get_basename()
	entity_def.identifier = _props_panel.get_source_identifier()
	entity_def.description = _props_panel.get_description()
	entity_def.has_volume = _props_panel.get_has_volume()
	entity_def.properties = _props_panel.get_props()
	entity_def.gizmos = _gizmos_panel.get_gizmos()
	ResourceSaver.save(entity_def)
	if editor_interface:
		editor_interface.inspect_object(entity_def)



func _on_new_entity_def() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.title = "Create New Entity"
	dialog.filters = ["*.tres ; LMEntityDefinition Resource"]
	var entity_dirs: Array = ProjectSettings.get_setting(LMPlugin.CFG_KEY_ENTITY_DIRS, [])
	for dir in entity_dirs:
		if not dir or dir.is_empty(): continue
		if dir.begins_with("res://addons/liminal_editor"): continue
		dialog.current_dir = dir
		break
	dialog.file_selected.connect(func(path: String) -> void:
		var def := LMEntityDefinition.new()
		def.entity_name = path.get_file().get_basename()
		ResourceSaver.save(def, path)
		var loaded := ResourceLoader.load(path) as LMEntityDefinition
		if loaded:
			open(loaded)
		dialog.queue_free()
	)
	_base_control.add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))


func _on_open_resource() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Open Entity"
	dialog.filters = ["*.tres ; LMEntityDefinition Resource"]
	var entity_dirs: Array = ProjectSettings.get_setting(LMPlugin.CFG_KEY_ENTITY_DIRS, [])
	for dir in entity_dirs:
		if not dir or dir.is_empty(): continue
		if dir.begins_with("res://addons/liminal_editor"): continue
		dialog.current_dir = dir
		break
	dialog.file_selected.connect(func(path: String) -> void:
		var res := ResourceLoader.load(path) as LMEntityDefinition
		if res:
			open(res)
		else:
			push_warning("LM: '%s' is not an LMEntityDefinition" % path)
		dialog.queue_free()
	)
	_base_control.add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))


func _on_export_defs() -> void:
	_on_apply()
	if export_callable.is_valid():
		export_callable.call()



func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	margin.add_child(root_vbox)

	var toolbar := HBoxContainer.new()
	toolbar.name = "Toolbar"
	toolbar.add_theme_constant_override("separation", 4)

	var sidebar_toggle_btn := Button.new()
	sidebar_toggle_btn.name = "BtnSidebarToggle"
	sidebar_toggle_btn.flat = true
	sidebar_toggle_btn.tooltip_text = "Toggle entity list sidebar"
	sidebar_toggle_btn.icon = get_theme_icon("FileList", "EditorIcons")
	sidebar_toggle_btn.pressed.connect(_toggle_sidebar)
	toolbar.add_child(sidebar_toggle_btn)

	var new_def_btn := Button.new()
	new_def_btn.name = "BtnNewDef"
	new_def_btn.text = "New Entity"
	new_def_btn.icon = get_theme_icon("New", "EditorIcons")
	new_def_btn.pressed.connect(_on_new_entity_def)
	toolbar.add_child(new_def_btn)

	var open_res_btn := Button.new()
	open_res_btn.name = "BtnOpenDef"
	open_res_btn.text = "Open..."
	open_res_btn.icon = get_theme_icon("Load", "EditorIcons")
	open_res_btn.pressed.connect(_on_open_resource)
	toolbar.add_child(open_res_btn)

	var export_btn := Button.new()
	export_btn.name = "BtnExport"
	export_btn.text = "Sync Workspace"
	var _export_icon := load("res://addons/liminal_editor/icons/icon_export_defs.svg")
	export_btn.icon = _export_icon if _export_icon else get_theme_icon("Export", "EditorIcons")
	export_btn.pressed.connect(_on_export_defs)
	toolbar.add_child(export_btn)

	var toolbar_spacer := Control.new()
	toolbar_spacer.name = "ToolbarSpacer"
	toolbar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(toolbar_spacer)

	var float_btn := Button.new()
	float_btn.name = "BtnFloat"
	float_btn.text = "⧉"
	float_btn.flat = true
	float_btn.tooltip_text = "Toggle floating / docked"
	float_btn.pressed.connect(func() -> void:
		if toggle_float_callable.is_valid(): toggle_float_callable.call()
	)
	toolbar.add_child(float_btn)

	var help_btn := Button.new()
	help_btn.name = "BtnHelp"
	help_btn.text = "Help"
	help_btn.icon = get_theme_icon("Help", "EditorIcons")
	help_btn.pressed.connect(func() -> void:
		OS.shell_open("https://liminal.lv/docs/user/creating_entities.html")
	)
	toolbar.add_child(help_btn)
	root_vbox.add_child(toolbar)

	var toolbar_sep := HSeparator.new()
	toolbar_sep.name = "ToolbarSep"
	root_vbox.add_child(toolbar_sep)

	var body_hbox := HBoxContainer.new()
	body_hbox.name = "BodyHBox"
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 0)
	root_vbox.add_child(body_hbox)

	_sidebar = LMEntityListPanel.new()
	_sidebar.entity_activated.connect(_on_entity_activated)
	body_hbox.add_child(_sidebar)

	_sidebar_divider = VSeparator.new()
	_sidebar_divider.name = "SidebarDivider"
	body_hbox.add_child(_sidebar_divider)

	var content_vbox := VBoxContainer.new()
	content_vbox.name = "ContentVBox"
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 0)
	body_hbox.add_child(content_vbox)

	_breadcrumb_wrap = MarginContainer.new()
	_breadcrumb_wrap.name = "BreadcrumbMargin"
	_breadcrumb_wrap.add_theme_constant_override("margin_top", 4)
	_breadcrumb_wrap.add_theme_constant_override("margin_bottom", 4)
	_breadcrumb_wrap.add_theme_constant_override("margin_left", 4)
	_breadcrumb_wrap.add_theme_constant_override("margin_right", 4)
	_breadcrumb_wrap.visible = false
	content_vbox.add_child(_breadcrumb_wrap)

	_breadcrumb = HBoxContainer.new()
	_breadcrumb.name = "Breadcrumb"
	_breadcrumb.add_theme_constant_override("separation", 4)
	_breadcrumb_wrap.add_child(_breadcrumb)

	var bc_back_btn := Button.new()
	bc_back_btn.name = "BreadcrumbBackBtn"
	bc_back_btn.text = "Entity"
	bc_back_btn.flat = true
	bc_back_btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	bc_back_btn.add_theme_color_override("font_hover_color", Color(0.7, 0.85, 1.0))
	bc_back_btn.pressed.connect(_on_cancel_pressed)
	_breadcrumb.add_child(bc_back_btn)

	var bc_slash := Label.new()
	bc_slash.name = "BreadcrumbSlash"
	bc_slash.text = "/"
	bc_slash.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_breadcrumb.add_child(bc_slash)

	_def_name_lbl = Label.new()
	_def_name_lbl.name = "BreadcrumbEntityName"
	_breadcrumb.add_child(_def_name_lbl)

	_def_path_lbl = Button.new()
	_def_path_lbl.name = "BreadcrumbEntityPath"
	_def_path_lbl.flat = true
	_def_path_lbl.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_def_path_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_def_path_lbl.add_theme_color_override("font_hover_color", Color(0.7, 0.85, 1.0))
	_def_path_lbl.add_theme_font_size_override("font_size", 12)
	_def_path_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_def_path_lbl.clip_text = true
	_def_path_lbl.tooltip_text = "Show in FileSystem"
	_def_path_lbl.pressed.connect(func() -> void:
		var info := _readonly_panel._current_info
		var path: String = entity_def.resource_path if entity_def else (info.source_path if info else "")
		if not path.is_empty() and editor_interface:
			editor_interface.get_file_system_dock().navigate_to_path(path)
	)
	_breadcrumb.add_child(_def_path_lbl)

	var back_btn := Button.new()
	back_btn.name = "BtnBack"
	back_btn.text = "Back"
	back_btn.pressed.connect(_on_cancel_pressed)
	_breadcrumb.add_child(back_btn)

	_breadcrumb_sep = HSeparator.new()
	_breadcrumb_sep.name = "BreadcrumbSep"
	_breadcrumb_sep.visible = false
	content_vbox.add_child(_breadcrumb_sep)

	_empty_state = CenterContainer.new()
	_empty_state.name = "EmptyState"
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_state.visible = true
	content_vbox.add_child(_empty_state)

	var empty_lbl := Label.new()
	empty_lbl.name = "EmptyStateLabel"
	empty_lbl.text = "Select an entity from the list\nor use New Definition to create one."
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_empty_state.add_child(empty_lbl)

	_readonly_scroll = ScrollContainer.new()
	_readonly_scroll.name = "ReadonlyScroll"
	_readonly_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_readonly_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_readonly_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_readonly_scroll.visible = false
	content_vbox.add_child(_readonly_scroll)

	_readonly_panel = LMEntityReadonlyPanel.new()
	_readonly_panel._editor_interface = editor_interface
	_readonly_scroll.add_child(_readonly_panel)

	_editor_area = VBoxContainer.new()
	_editor_area.name = "EditorArea"
	_editor_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_area.add_theme_constant_override("separation", 4)
	_editor_area.visible = false
	content_vbox.add_child(_editor_area)

	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 0)
	_editor_area.add_child(columns)

	var left_scroll := ScrollContainer.new()
	left_scroll.name = "PropsScroll"
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(left_scroll)

	_props_panel = LMPropsPanel.new()
	_props_panel.base_control = _base_control
	_props_panel.drag = _drag
	_props_panel.dirty_changed.connect(_mark_dirty)
	left_scroll.add_child(_props_panel)

	var vsep := VSeparator.new()
	vsep.name = "ColumnDivider"
	columns.add_child(vsep)

	var right_scroll := ScrollContainer.new()
	right_scroll.name = "GizmosScroll"
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(right_scroll)

	_gizmos_panel = LMGizmosPanel.new()
	_gizmos_panel.drag = _drag
	_gizmos_panel.dirty_changed.connect(_mark_dirty)
	right_scroll.add_child(_gizmos_panel)

	var bottom_sep := HSeparator.new()
	bottom_sep.name = "BottomBarSep"
	_editor_area.add_child(bottom_sep)

	var bottom_margin := MarginContainer.new()
	bottom_margin.name = "BottomBarMargin"
	for side in ["left", "right", "top", "bottom"]:
		bottom_margin.add_theme_constant_override("margin_" + side, 8)
	_editor_area.add_child(bottom_margin)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.add_theme_constant_override("separation", 4)
	bottom_margin.add_child(bottom_bar)

	_apply_btn = Button.new()
	_apply_btn.name = "BtnApply"
	_apply_btn.text = "Save"
	_apply_btn.disabled = true
	_apply_btn.pressed.connect(_on_apply)
	_apply_btn.ready.connect(func() -> void:
		_apply_btn.icon = get_theme_icon("Save", "EditorIcons")
		_apply_btn.custom_minimum_size.y = _apply_btn.get_minimum_size().y * 1.5
	)
	bottom_bar.add_child(_apply_btn)

	_checkmark_lbl = Label.new()
	_checkmark_lbl.name = "SavedCheckmark"
	_checkmark_lbl.text = "✓"
	_checkmark_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 0.3))
	_checkmark_lbl.add_theme_font_size_override("font_size", 16)
	_checkmark_lbl.visible = false
	bottom_bar.add_child(_checkmark_lbl)


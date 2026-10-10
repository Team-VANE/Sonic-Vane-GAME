extends CanvasLayer

## Maximum width of the scene diagnostic readout before viewport margins are applied.
@export_range(320.0, 1200.0, 10.0, "suffix:px") var maximum_panel_width: float = 660.0
## Space retained between the readout and the viewport edges.
@export_range(8.0, 80.0, 1.0, "suffix:px") var viewport_margin: float = 22.0

var _root: Control = null
var _panel: PanelContainer = null
var _content: VBoxContainer = null
var _title: Label = null
var _subtitle: Label = null
var _body: Label = null
var _footer: Label = null
var _preview: bool = false
var _dependency_heading: Label = null
var _dependencies: ItemList = null
var _dependency_detail: Label = null
var _inspect_button: Button = null
var _inspection_active: bool = false
var _previous_pause: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _previous_focus: WeakRef = null
var _dependency_entries: Array = []
var _return_dialog: WeakRef = null

func _ready() -> void:
	layer = 220
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.014, 0.023, 0.97)
	style.border_color = Color(1.0, 0.12, 0.16)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	style.shadow_size = 10
	style.set_content_margin_all(18.0)
	_panel.add_theme_stylebox_override("panel", style)
	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 10)
	_panel.add_child(_content)
	_content.minimum_size_changed.connect(_fit_height)
	_title = _label(Color(1.0, 0.43, 0.43))
	_subtitle = _label(Color(1.0, 0.8, 0.72))
	_body = _label(Color(0.94, 0.94, 0.97))
	_dependency_heading = _label(Color(1.0, 0.8, 0.72))
	_dependencies = ItemList.new()
	_dependencies.max_columns = 1
	_dependencies.max_text_lines = 3
	_dependencies.focus_mode = Control.FOCUS_NONE
	_dependencies.mouse_filter = Control.MOUSE_FILTER_STOP
	_dependencies.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_dependencies.add_theme_color_override("font_selected_color", Color.WHITE)
	_dependencies.add_theme_color_override("font_unselected_color", Color(0.95, 0.95, 1.0))
	var list_style: StyleBoxFlat = StyleBoxFlat.new()
	list_style.bg_color = Color(0.045, 0.015, 0.025, 0.96)
	list_style.border_color = Color(0.65, 0.15, 0.2)
	list_style.set_border_width_all(1)
	list_style.set_content_margin_all(8.0)
	_dependencies.add_theme_stylebox_override("panel", list_style)
	var selected_style: StyleBoxFlat = list_style.duplicate() as StyleBoxFlat
	selected_style.bg_color = Color(0.4, 0.04, 0.065)
	selected_style.border_color = Color(1.0, 0.5, 0.5)
	_dependencies.add_theme_stylebox_override("selected", selected_style)
	_dependencies.add_theme_stylebox_override("selected_focus", selected_style)
	_dependencies.item_selected.connect(_select_dependency)
	_content.add_child(_dependencies)
	_dependency_detail = _label(Color(0.85, 0.88, 0.95))
	_dependency_detail.max_lines_visible = 5
	_dependency_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_footer = _label(Color(0.7, 0.76, 0.85))
	_inspect_button = Button.new()
	_inspect_button.text = "Inspect dependencies (F7 / Right-stick click)"
	_inspect_button.focus_mode = Control.FOCUS_NONE
	_inspect_button.add_theme_stylebox_override("normal", list_style)
	_inspect_button.add_theme_stylebox_override("hover", selected_style)
	_inspect_button.add_theme_stylebox_override("pressed", selected_style)
	_inspect_button.add_theme_stylebox_override("focus", selected_style)
	_inspect_button.pressed.connect(_toggle_inspection)
	_content.add_child(_inspect_button)
	_dependencies.focus_neighbor_right = _inspect_button.get_path()
	_dependencies.focus_neighbor_bottom = _inspect_button.get_path()
	_dependencies.focus_next = _inspect_button.get_path()
	_dependencies.focus_previous = _inspect_button.get_path()
	_inspect_button.focus_neighbor_left = _dependencies.get_path()
	_inspect_button.focus_neighbor_top = _dependencies.get_path()
	_inspect_button.focus_next = _dependencies.get_path()
	_inspect_button.focus_previous = _dependencies.get_path()
	_title.max_lines_visible = 2
	_subtitle.max_lines_visible = 3
	_body.max_lines_visible = 4
	_footer.max_lines_visible = 4
	_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var font_path: String = "res://LS5Framework/Resources/Fonts/Orbitron900.tres"
	if ResourceLoader.exists(font_path):
		var heading_font: Font = load(font_path) as Font
		if heading_font:
			_title.add_theme_font_override("font", heading_font)
	_root.resized.connect(_layout)
	_root.visible = false
	_layout()

func _label(color: Color) -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)
	return label

func show_report(report: Dictionary, log_saved: bool, preview: bool = false) -> void:
	_preview = preview
	_title.text = "SCENE DIAGNOSTICS" if not preview else "SCENE DIAGNOSTICS / PREVIEW"
	var issues: Array = report.get("issues", [])
	_subtitle.text = String(issues[0].get("title", "Scene setup problem")) if not issues.is_empty() else "Scene setup problem"
	var lines: PackedStringArray = []
	if not issues.is_empty():
		var issue: Dictionary = issues[0]
		lines.append("%s: %s" % [issue.get("confidence", "Observed"), issue.get("detail", "")])
		var suggestion: String = String(issue.get("suggestion", ""))
		if not suggestion.is_empty():
			lines.append(suggestion if suggestion.begins_with("Check ") else "Check: " + suggestion)
	if issues.size() > 1:
		lines.append("")
		lines.append("Also detected:")
		for index: int in range(1, mini(issues.size(), 4)):
			lines.append("• " + String(issues[index].get("title", "")))
	if issues.size() > 4:
		lines.append("+ %d more findings in the saved report." % (issues.size() - 4))
	_body.text = "\n".join(lines)
	update_dependencies(report, log_saved)
	_root.visible = true
	_layout()

func clear_report() -> void:
	_leave_inspection()
	if _root:
		_root.visible = false

func is_report_visible() -> bool:
	return _root != null and _root.visible

func _layout() -> void:
	if not _root or not _panel:
		return
	var viewport_size: Vector2 = _root.size
	var scale_factor: float = clampf(minf(viewport_size.x / 1280.0, viewport_size.y / 720.0), 0.62, 1.4)
	var margin: float = viewport_margin * scale_factor
	var width: float = minf(maximum_panel_width * scale_factor, maxf(viewport_size.x - margin * 2.0, 1.0))
	_panel.custom_minimum_size.x = width
	_panel.size.x = width
	_title.add_theme_font_size_override("font_size", maxi(roundi(22.0 * scale_factor), 14))
	_subtitle.add_theme_font_size_override("font_size", maxi(roundi(20.0 * scale_factor), 13))
	_body.add_theme_font_size_override("font_size", maxi(roundi(17.0 * scale_factor), 12))
	_footer.add_theme_font_size_override("font_size", maxi(roundi(14.0 * scale_factor), 10))
	_dependency_heading.add_theme_font_size_override("font_size", maxi(roundi(17.0 * scale_factor), 12))
	_dependencies.add_theme_font_size_override("font_size", maxi(roundi(15.0 * scale_factor), 12))
	_dependency_detail.add_theme_font_size_override("font_size", maxi(roundi(14.0 * scale_factor), 11))
	_inspect_button.add_theme_font_size_override("font_size", maxi(roundi(14.0 * scale_factor), 11))
	_body.max_lines_visible = 3 if viewport_size.y < 650.0 else 4
	_dependencies.fixed_column_width = maxi(roundi(width - 64.0), 100)
	_panel.position = Vector2(viewport_size.x - width - margin, margin)
	_panel.size.y = 0.0
	_fit_height.call_deferred()

func _fit_height() -> void:
	if not _panel or not _content:
		return
	var available_height: float = _root.size.y - _panel.position.y * 2.0
	var other_height: float = _content.get_combined_minimum_size().y - _dependencies.get_combined_minimum_size().y + 36.0
	var list_height: float = clampf(available_height - other_height, 60.0, 200.0)
	if not is_equal_approx(_dependencies.custom_minimum_size.y, list_height):
		_dependencies.custom_minimum_size.y = list_height
	_panel.size.y = _content.get_combined_minimum_size().y + 36.0

func update_dependencies(report: Dictionary, log_saved: bool) -> void:
	var context: Dictionary = report.get("context", {})
	var level: String = String(context.get("level_scene", context.get("scene", "unknown"))).get_file()
	var issues: Array = report.get("issues", [])
	var primary_code: String = String(issues[0].get("code", "UNKNOWN")) if not issues.is_empty() else "UNKNOWN"
	var log_text: String = "Preview only — no gameplay state changed."
	if not _preview:
		log_text = "Logs: Local Files / scene_dependency_errors.log + scene_diagnostics.log" if log_saved else "Scene report could not be saved; take a screenshot."
		if not report.get("dependency_error_log_saved", false):
			log_text += "\nDependency error log could not be saved."
	_footer.text = "Level: %s | %s\n%s" % [level, primary_code, log_text]
	var scan: Dictionary = report.get("dependency_scan", {})
	_dependency_entries = scan.get("entries", [])
	_dependencies.clear()
	_dependency_heading.text = "Missing / failed dependencies: %d — %s" % [_dependency_entries.size(), scan.get("state", "Not scanned")]
	for entry: Dictionary in _dependency_entries:
		var owners: String = ", ".join(entry.get("owners", []))
		var index: int = _dependencies.add_item("[%s] %s" % [entry.get("status", "Missing"), String(entry.get("path", "")).get_file()])
		_dependencies.set_item_tooltip(index, "%s\nReferenced by: %s\n%s" % [entry.get("path", ""), owners, entry.get("reason", "")])
	if _dependency_entries.is_empty():
		_dependency_detail.text = "Inspecting resource references…" if scan.get("state", "") == "Scanning" else "No missing files identified. Dependency metadata may not reveal every loading failure."
	else:
		_dependencies.select(0)
		_select_dependency(0)
	_layout()

func _select_dependency(index: int) -> void:
	if index < 0 or index >= _dependency_entries.size():
		return
	var entry: Dictionary = _dependency_entries[index]
	_dependency_detail.text = "%s\nReferenced by: %s\n%s" % [entry.get("path", ""), ", ".join(entry.get("owners", [])), entry.get("reason", "")]
	_dependency_detail.tooltip_text = _dependencies.get_item_tooltip(index)
	_dependencies.ensure_current_is_visible()
	_fit_height.call_deferred()

func _input(event: InputEvent) -> void:
	if not is_report_visible():
		return
	var toggle: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_STICK)
	if toggle:
		get_viewport().set_input_as_handled()
		_toggle_inspection()
	elif _inspection_active and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave_inspection()

func _toggle_inspection() -> void:
	if _inspection_active:
		_leave_inspection()
		return
	get_tree().root.move_child(self, get_tree().root.get_child_count() - 1)
	_previous_pause = get_tree().paused
	_previous_mouse_mode = Input.mouse_mode
	var focus: Control = get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus else null
	_inspection_active = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_dependencies.focus_mode = Control.FOCUS_ALL
	_inspect_button.focus_mode = Control.FOCUS_ALL
	_inspect_button.text = "Return (Back / Escape) — D-pad scrolls dependencies"
	_dependencies.grab_focus()

func open_inspection(return_dialog: Window = null) -> void:
	if _inspection_active:
		return
	_return_dialog = weakref(return_dialog) if is_instance_valid(return_dialog) else null
	_toggle_inspection()

func _leave_inspection() -> void:
	if not _inspection_active:
		return
	_inspection_active = false
	_dependencies.release_focus()
	_inspect_button.release_focus()
	_dependencies.focus_mode = Control.FOCUS_NONE
	_inspect_button.focus_mode = Control.FOCUS_NONE
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = _previous_pause
	Input.mouse_mode = _previous_mouse_mode as Input.MouseMode
	_inspect_button.text = "Inspect dependencies (F7 / Right-stick click)"
	var focus: Variant = _previous_focus.get_ref() if _previous_focus else null
	if is_instance_valid(focus) and focus is Control and focus.is_visible_in_tree():
		focus.grab_focus()
	_previous_focus = null
	var dialog: Variant = _return_dialog.get_ref() if _return_dialog else null
	_return_dialog = null
	if is_instance_valid(dialog) and dialog is AcceptDialog and dialog.is_inside_tree():
		dialog.popup_centered()
		dialog.get_ok_button().grab_focus()

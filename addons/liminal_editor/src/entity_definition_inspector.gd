@tool
class_name LMEntityDefinitionInspector extends EditorInspectorPlugin

var open_entity_callable: Callable = Callable()


func _can_handle(object: Object) -> bool:
	return object is LMEntityDefinition or object is LMEntityDefinitionProp


func _parse_begin(object: Object) -> void:
	var entity_def := object as LMEntityDefinition
	if not entity_def:
		return

	var vbox := VBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = entity_def.entity_name if not entity_def.entity_name.is_empty() else "(unnamed)"
	name_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(name_lbl)

	var open_btn := Button.new()
	open_btn.text = "Edit in Entity Wizard"
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_btn.custom_minimum_size = Vector2(0, 48)
	open_btn.add_theme_color_override("font_color", Color.WHITE)
	open_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	open_btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		match state_name:
			"hover":
				s.bg_color = Color("#3ba4ff").lightened(0.12)
			"pressed":
				s.bg_color = Color("#3ba4ff").darkened(0.18)
			_:
				s.bg_color = Color("#3ba4ff")
		s.set_corner_radius_all(4)
		s.content_margin_top = 4.0
		s.content_margin_bottom = 4.0
		open_btn.add_theme_stylebox_override(state_name, s)

	open_btn.pressed.connect(func() -> void:
		if open_entity_callable.is_valid():
			open_entity_callable.call(entity_def)
	)
	vbox.add_child(open_btn)

	add_custom_control(vbox)


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if object is LMEntityDefinitionProp and name == "choices":
		add_property_editor(name, LMChoicesEditorProperty.new())
		return true
	return false


class LMChoicesEditorProperty extends EditorProperty:
	const _TYPES: Array[String] = ["LMChoicesStatic", "LMChoicesResourceType", "LMChoicesFileGlob"]
	const _SCRIPTS := {
		"LMChoicesStatic": "res://addons/liminal_editor/src/lm_choices_static.gd",
		"LMChoicesResourceType": "res://addons/liminal_editor/src/lm_choices_resource_type.gd",
		"LMChoicesFileGlob": "res://addons/liminal_editor/src/lm_choices_file_glob.gd",
	}

	var _empty_row: HBoxContainer
	var _filled_row: HBoxContainer
	var _type_picker: OptionButton
	var _filled_lbl: Label
	var _file_dialog: EditorFileDialog

	func _init() -> void:
		var vbox := VBoxContainer.new()
		add_child(vbox)

		_empty_row = HBoxContainer.new()
		_type_picker = OptionButton.new()
		_type_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for t in _TYPES:
			_type_picker.add_item(t)
		_empty_row.add_child(_type_picker)

		var new_btn := Button.new()
		new_btn.text = "New"
		new_btn.pressed.connect(_on_new)
		_empty_row.add_child(new_btn)

		var load_btn := Button.new()
		load_btn.text = "Load..."
		load_btn.pressed.connect(_on_load)
		_empty_row.add_child(load_btn)

		vbox.add_child(_empty_row)

		_filled_row = HBoxContainer.new()
		_filled_lbl = Label.new()
		_filled_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_filled_row.add_child(_filled_lbl)

		var clear_btn := Button.new()
		clear_btn.text = "Clear"
		clear_btn.pressed.connect(_on_clear)
		_filled_row.add_child(clear_btn)

		vbox.add_child(_filled_row)

	func _update_property() -> void:
		var val: Variant = get_edited_object().get(get_edited_property())
		var has_val := val != null
		_empty_row.visible = not has_val
		_filled_row.visible = has_val
		if has_val:
			var cls: String = val.get_script().get_global_name() if val.get_script() else val.get_class()
			var key: String = val.get("type_key") if val.get("type_key") else ""
			_filled_lbl.text = "%s (%s)" % [cls, key] if not key.is_empty() else cls

	func _on_new() -> void:
		var cls_name: String = _type_picker.get_item_text(_type_picker.selected)
		var script: GDScript = load(_SCRIPTS[cls_name])
		var inst := Resource.new()
		inst.set_script(script)
		emit_changed(get_edited_property(), inst)

	func _on_load() -> void:
		if not _file_dialog:
			_file_dialog = EditorFileDialog.new()
			_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
			_file_dialog.add_filter("*.tres,*.res", "Resources")
			_file_dialog.file_selected.connect(_on_file_selected)
			add_child(_file_dialog)
		_file_dialog.popup_centered_ratio(0.5)

	func _on_file_selected(path: String) -> void:
		var res := ResourceLoader.load(path)
		if not res is LMChoicesProvider:
			push_warning("LM: '%s' is not a LMChoicesProvider" % path)
			return
		emit_changed(get_edited_property(), res)

	func _on_clear() -> void:
		emit_changed(get_edited_property(), null)

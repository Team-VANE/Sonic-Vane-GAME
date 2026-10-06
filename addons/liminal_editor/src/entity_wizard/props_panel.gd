@tool
class_name LMPropsPanel extends VBoxContainer

signal dirty_changed

enum SourceMode { BUILTIN, SCRIPT, SCENE }

var _source_mode: SourceMode = SourceMode.BUILTIN
var _scanned_props: Array[Dictionary] = []
var _prop_checkboxes: Array[CheckBox] = []
var _prop_type_opts: Array[OptionButton] = []
var _source_identifier: String = ""
var _pick_type_btn: Button

var _picker_container: VBoxContainer
var _props_container: VBoxContainer
var _status_label: Label
var _btn_builtin: Button
var _btn_script: Button
var _btn_scene: Button
var _resource_picker: EditorResourcePicker
var _desc_edit: TextEdit
var _volume_check: CheckBox

var base_control: Control
var drag: LMBindingDrag

var _class_chain: Array[String] = []
var _prop_class_map: Dictionary = {}

const _SKIP_CLASS_GROUPS := ["Object", "RefCounted"]


func _ready() -> void:
	name = "PropsVBox"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.name = "PropsHeader"
	header.text = "Properties"
	header.add_theme_font_size_override("font_size", 13)
	add_child(header)

	var sep := HSeparator.new()
	sep.name = "PropsSep"
	add_child(sep)

	var desc_row := HBoxContainer.new()
	desc_row.name = "DescRow"
	desc_row.add_theme_constant_override("separation", 4)
	var desc_lbl := Label.new()
	desc_lbl.name = "DescLabel"
	desc_lbl.text = "Description:"
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_row.add_child(desc_lbl)
	var wand_btn := Button.new()
	wand_btn.name = "BtnPullDesc"
	wand_btn.flat = true
	wand_btn.icon = load("res://addons/liminal_editor/icons/icon_pull_desc.svg")
	wand_btn.tooltip_text = "Pull description from source"
	wand_btn.pressed.connect(_pull_description_from_source)
	desc_row.add_child(wand_btn)
	add_child(desc_row)

	_desc_edit = TextEdit.new()
	_desc_edit.name = "DescEdit"
	_desc_edit.custom_minimum_size.y = 88
	_desc_edit.placeholder_text = "Entity description (optional)"
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_edit.text_changed.connect(func() -> void: dirty_changed.emit())
	add_child(_desc_edit)

	_volume_check = CheckBox.new()
	_volume_check.name = "VolumeCheck"
	_volume_check.text = "Is Volume"
	_volume_check.tooltip_text = "When enabled, the entity is placed in Blender as an editable mesh." \
		+ "Entities marked as volume, won't have preview meshes."
	_volume_check.toggled.connect(func(_pressed: bool) -> void: dirty_changed.emit())
	add_child(_volume_check)

	var mode_label := Label.new()
	mode_label.name = "SourceTypeLabel"
	mode_label.text = "Source Type:"
	add_child(mode_label)

	var mode_hbox := HBoxContainer.new()
	mode_hbox.name = "SourceModeRow"
	mode_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_group := ButtonGroup.new()

	_btn_builtin = Button.new()
	_btn_builtin.name = "BtnModeBuiltin"
	_btn_builtin.text = "BuiltIn"
	_btn_builtin.toggle_mode = true
	_btn_builtin.button_pressed = true
	_btn_builtin.button_group = btn_group
	_btn_builtin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_builtin.pressed.connect(_on_mode_builtin)
	_apply_mode_btn_style(_btn_builtin)
	mode_hbox.add_child(_btn_builtin)

	_btn_script = Button.new()
	_btn_script.name = "BtnModeScript"
	_btn_script.text = "Script"
	_btn_script.toggle_mode = true
	_btn_script.button_group = btn_group
	_btn_script.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_script.pressed.connect(_on_mode_script)
	_apply_mode_btn_style(_btn_script)
	mode_hbox.add_child(_btn_script)

	_btn_scene = Button.new()
	_btn_scene.name = "BtnModeScene"
	_btn_scene.text = "Scene"
	_btn_scene.toggle_mode = true
	_btn_scene.button_group = btn_group
	_btn_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_scene.pressed.connect(_on_mode_scene)
	_apply_mode_btn_style(_btn_scene)
	mode_hbox.add_child(_btn_scene)
	add_child(mode_hbox)

	_picker_container = VBoxContainer.new()
	_picker_container.name = "PickerContainer"
	add_child(_picker_container)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_props_container = VBoxContainer.new()
	_props_container.name = "PropsContainer"
	add_child(_props_container)



func reset() -> void:
	_clear_picker()
	_clear_props()
	_source_mode = SourceMode.BUILTIN
	_source_identifier = ""
	if _volume_check:
		_volume_check.set_pressed_no_signal(false)
	_set_mode_btn(_btn_builtin)
	_show_builtin_picker()
	if drag:
		drag.set_props(_scanned_props)


func get_has_volume() -> bool:
	return _volume_check.button_pressed if _volume_check else false


func get_description() -> String:
	return _desc_edit.text.strip_edges() if _desc_edit else ""


func set_description(text: String) -> void:
	if _desc_edit:
		_desc_edit.text = text


func get_source_identifier() -> String:
	return _source_identifier


func get_props() -> Array[LMEntityDefinitionProp]:
	var result: Array[LMEntityDefinitionProp] = []
	for prop in _scanned_props:
		if not prop.checked: continue
		var def_prop := LMEntityDefinitionProp.new()
		def_prop.name = prop.name
		def_prop.type = prop.type_string
		def_prop.description = prop.get("description", "")
		def_prop.default_value = prop.default_value
		if prop.type_string in ["choices", "multi_choices"]:
			def_prop.choices = prop.get("choices_provider")
		result.append(def_prop)
	return result


func restore_from_def(def: LMEntityDefinition) -> void:
	if not def: return
	if _volume_check:
		_volume_check.set_pressed_no_signal(def.has_volume)
	var id: String = def.identifier
	if id.is_empty(): return

	var mode := _detect_mode(id)
	_source_identifier = id

	match mode:
		SourceMode.BUILTIN:
			_set_mode_btn(_btn_builtin)
			_scan_builtin_class(id)
			_update_pick_type_btn_text()
		SourceMode.SCRIPT:
			_source_mode = SourceMode.SCRIPT
			_set_mode_btn(_btn_script)
			_clear_picker()
			_show_resource_picker("Script")
			var uid_int := ResourceUID.text_to_id(id)
			if uid_int != ResourceUID.INVALID_ID:
				var res := ResourceLoader.load(ResourceUID.get_id_path(uid_int)) as Script
				if res:
					_resource_picker.edited_resource = res
					_scan_script(res)
		SourceMode.SCENE:
			_source_mode = SourceMode.SCENE
			_set_mode_btn(_btn_scene)
			_clear_picker()
			_show_resource_picker("PackedScene")
			var uid_int := ResourceUID.text_to_id(id)
			if uid_int != ResourceUID.INVALID_ID:
				var res := ResourceLoader.load(ResourceUID.get_id_path(uid_int)) as PackedScene
				if res:
					_resource_picker.edited_resource = res
					_scan_scene(res)

	_preselect_existing_props(def)
	if drag:
		drag.set_props(_scanned_props)


func tick_drag() -> void:
	if not _props_container: return
	var is_dragging := _props_container.get_viewport().gui_is_dragging()
	if drag:
		drag.tick(is_dragging)



func _apply_mode_btn_style(btn: Button) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#3ba4ff")
	s.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("pressed", s)
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color("#3ba4ff").lightened(0.1)
	sh.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover_pressed", sh)


func _set_mode_btn(btn: Button) -> void:
	_btn_builtin.set_pressed_no_signal(_btn_builtin == btn)
	_btn_script.set_pressed_no_signal(_btn_script == btn)
	_btn_scene.set_pressed_no_signal(_btn_scene == btn)


func _on_mode_builtin() -> void:
	_source_mode = SourceMode.BUILTIN
	_clear_picker()
	_clear_props()
	_show_builtin_picker()
	dirty_changed.emit()


func _on_mode_script() -> void:
	_source_mode = SourceMode.SCRIPT
	_clear_picker()
	_clear_props()
	_show_resource_picker("Script")
	dirty_changed.emit()


func _on_mode_scene() -> void:
	_source_mode = SourceMode.SCENE
	_clear_picker()
	_clear_props()
	_show_resource_picker("PackedScene")
	dirty_changed.emit()


func _clear_picker() -> void:
	for c in _picker_container.get_children():
		c.queue_free()
	_pick_type_btn = null
	_resource_picker = null


func _clear_props() -> void:
	for c in _props_container.get_children():
		c.queue_free()
	_scanned_props.clear()
	_prop_checkboxes.clear()
	_prop_type_opts.clear()
	_class_chain.clear()
	_prop_class_map.clear()
	_status_label.text = ""


func _show_builtin_picker() -> void:
	_pick_type_btn = Button.new()
	_pick_type_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_pick_type_btn_text()
	_pick_type_btn.pressed.connect(_open_builtin_picker_dialog)
	_picker_container.add_child(_pick_type_btn)


func _update_pick_type_btn_text() -> void:
	if not _pick_type_btn: return
	if _source_mode == SourceMode.BUILTIN and not _source_identifier.is_empty():
		_pick_type_btn.text = "Change Type: %s" % _source_identifier
	else:
		_pick_type_btn.text = "Pick Type"


func _open_builtin_picker_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Select Built-in Type"
	dialog.min_size = Vector2i(400, 500)

	var vbox := VBoxContainer.new()
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter classes..."
	vbox.add_child(filter)

	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 400
	vbox.add_child(list)
	dialog.add_child(vbox)
	base_control.add_child(dialog)

	var populate := func(f: String) -> void:
		list.clear()
		var classes := ClassDB.get_class_list()
		classes.sort()
		var fl := f.to_lower()
		for cls in classes:
			if not ClassDB.is_parent_class(cls, "Node3D") and not ClassDB.is_parent_class(cls, "Resource"):
				continue
			if not ClassDB.can_instantiate(cls): continue
			if fl.is_empty() or cls.to_lower().contains(fl):
				list.add_item(cls)
		if not _source_identifier.is_empty():
			for i in list.item_count:
				if list.get_item_text(i) == _source_identifier:
					list.select(i)
					list.ensure_current_is_visible()
					break
	populate.call(filter.text)
	filter.text_changed.connect(populate)

	dialog.confirmed.connect(func() -> void:
		var sel := list.get_selected_items()
		if sel.is_empty(): return
		var cls: String = list.get_item_text(sel[0])
		_source_identifier = cls
		_update_pick_type_btn_text()
		_clear_props()
		_scan_builtin_class(cls)
		dirty_changed.emit()
	)
	dialog.popup_centered()


func _show_resource_picker(type_filter: String) -> void:
	_resource_picker = EditorResourcePicker.new()
	_resource_picker.base_type = type_filter
	_resource_picker.resource_changed.connect(_on_resource_picked)
	_picker_container.add_child(_resource_picker)


func _on_resource_picked(resource: Resource) -> void:
	if not resource: return
	_clear_props()
	if resource is Script:
		_source_identifier = _get_resource_uid_text(resource)
		_scan_script(resource)
	elif resource is PackedScene:
		_source_identifier = _get_resource_uid_text(resource)
		_scan_scene(resource)
	dirty_changed.emit()


func _get_resource_uid_text(res: Resource) -> String:
	var uid := ResourceLoader.get_resource_uid(res.resource_path)
	if uid != ResourceUID.INVALID_ID:
		return ResourceUID.id_to_text(uid)
	return res.resource_path



func _scan_builtin_class(cls: String) -> void:
	_clear_props()
	var obj: Object = ClassDB.instantiate(cls)
	if not obj:
		_status_label.text = "Failed to instantiate %s" % cls
		return
	_scan_object_properties(obj, true)
	if drag: drag.set_props(_scanned_props)
	if obj is Node:
		obj.free()


func _scan_script(script: Script) -> void:
	var obj: Object = script.new()
	if not obj:
		_status_label.text = "Failed to instantiate script"
		return
	_scan_object_properties(obj, false)
	_try_autofill_description(obj)
	if drag: drag.set_props(_scanned_props)
	if obj is Node:
		obj.free()


func _scan_scene(scene: PackedScene) -> void:
	var state := scene.get_state()
	if state != null and state.get_node_count() > 0:
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == "script":
				var val: Variant = state.get_node_property_value(0, i)
				if val is Script:
					_scan_script(val)
					return
	var node: Node = scene.instantiate()
	if not node:
		_status_label.text = "Failed to instantiate scene"
		return
	_scan_object_properties(node, false)
	_try_autofill_description(node)
	if drag: drag.set_props(_scanned_props)
	node.free()


func _try_autofill_description(obj: Object) -> void:
	if not _desc_edit or not _desc_edit.text.is_empty(): return
	var comment := LMCodeUtils.get_class_comment(obj)
	if not comment.is_empty():
		_desc_edit.text = comment.strip_edges()
		dirty_changed.emit()


func _build_class_attribution(obj: Object, is_builtin: bool) -> void:
	_class_chain.clear()
	_prop_class_map.clear()
	if is_builtin:
		_build_classdb_chain(obj.get_class())
	else:
		_build_script_chain(obj)
	for prop in _scanned_props:
		prop["class_group"] = _prop_class_map.get(prop.name, "")


func _build_classdb_chain(cls: String) -> void:
	var chain: Array[String] = []
	var c := cls
	while not c.is_empty():
		chain.push_back(c)
		c = ClassDB.get_parent_class(c)
	chain.reverse()
	_class_chain = chain
	for group_class in _class_chain:
		for p in ClassDB.class_get_property_list(group_class, true):
			_prop_class_map[p.name] = group_class


func _build_script_chain(obj: Object) -> void:
	var script_chain: Array[Script] = []
	var s := obj.get_script() as Script
	while s:
		script_chain.append(s)
		s = s.get_base_script()

	var native_base: String
	if not script_chain.is_empty():
		native_base = script_chain.back().get_instance_base_type()
	else:
		native_base = obj.get_class()

	var classdb_part: Array[String] = []
	var c := native_base
	while not c.is_empty():
		classdb_part.push_back(c)
		c = ClassDB.get_parent_class(c)
	classdb_part.reverse()

	var script_names: Array[String] = []
	for i in range(script_chain.size() - 1, -1, -1):
		var sc: Script = script_chain[i]
		var sname := sc.get_global_name()
		if sname.is_empty():
			sname = sc.resource_path.get_file().get_basename()
		if sname.is_empty():
			sname = "Script"
		script_names.append(sname)

	_class_chain.append_array(classdb_part)
	_class_chain.append_array(script_names)

	for group_class in classdb_part:
		for p in ClassDB.class_get_property_list(group_class, true):
			_prop_class_map[p.name] = group_class

	for i in range(script_chain.size() - 1, -1, -1):
		var sc: Script = script_chain[i]
		var sname := sc.get_global_name()
		if sname.is_empty():
			sname = sc.resource_path.get_file().get_basename()
		if sname.is_empty():
			sname = "Script"
		for p in sc.get_script_property_list():
			_prop_class_map[p.name] = sname


func _pull_description_from_source() -> void:
	var obj: Object = null
	match _source_mode:
		SourceMode.BUILTIN:
			if not _source_identifier.is_empty():
				obj = ClassDB.instantiate(_source_identifier)
		SourceMode.SCRIPT:
			var uid_int := ResourceUID.text_to_id(_source_identifier)
			if uid_int != ResourceUID.INVALID_ID:
				var res := ResourceLoader.load(ResourceUID.get_id_path(uid_int)) as Script
				if res: obj = res.new()
		SourceMode.SCENE:
			var uid_int := ResourceUID.text_to_id(_source_identifier)
			if uid_int != ResourceUID.INVALID_ID:
				var res := ResourceLoader.load(ResourceUID.get_id_path(uid_int)) as PackedScene
				if res: obj = res.instantiate()
	if not obj: return
	var comment := LMCodeUtils.get_class_comment(obj)
	if obj is Node: obj.free()
	if comment.is_empty(): return
	_desc_edit.text = comment.strip_edges()
	dirty_changed.emit()


func _scan_object_properties(obj: Object, is_builtin: bool) -> void:
	_scanned_props.clear()
	_prop_checkboxes.clear()
	_prop_type_opts.clear()

	var var_comments: Dictionary = {}
	if not is_builtin:
		var_comments = LMCodeUtils.parse_comments_for_vars(obj)

	for p in obj.get_property_list():
		if not (p.usage & PROPERTY_USAGE_EDITOR): continue
		if p.usage & PROPERTY_USAGE_GROUP or p.usage & PROPERTY_USAGE_CATEGORY or p.usage & PROPERTY_USAGE_SUBGROUP: continue
		var type_id: int = p.type
		if type_id in [TYPE_AABB, TYPE_ARRAY, TYPE_BASIS, TYPE_CALLABLE, TYPE_DICTIONARY, TYPE_NODE_PATH]: continue

		var type_str: String
		var default_val: Variant
		var auto_provider: LMChoicesProvider = null

		if type_id == TYPE_OBJECT:
			if p.hint != PROPERTY_HINT_RESOURCE_TYPE or p.hint_string.is_empty() or p.hint_string == "Resource":
				continue
			type_str = "choices"
			default_val = null
			var provider := LMChoicesResourceType.new()
			provider.resource_type = p.hint_string
			auto_provider = provider
		else:
			var derived: Dictionary = LiminalEditor._choices_from_hint(p, _scanned_owner_name(obj))
			var is_mask: bool = p.hint == PROPERTY_HINT_FLAGS or LiminalEditor._LAYER_HINTS.has(p.hint)
			if not derived.is_empty():
				type_str = "multi_choices" if is_mask else "choices"
			else:
				type_str = type_string(type_id)
			default_val = obj.get(p.name)
			match type_id:
				TYPE_COLOR, TYPE_VECTOR4, TYPE_VECTOR4I:
					default_val = [default_val[0], default_val[1], default_val[2], default_val[3]]
				TYPE_VECTOR3, TYPE_VECTOR3I:
					default_val = [default_val[0], default_val[1], default_val[2]]
			if is_mask and not derived.is_empty():
				default_val = LiminalEditor._mask_to_labels(int(default_val), derived["items"])

		_scanned_props.append({
			"name":             p.name,
			"type_string":      type_str,
			"orig_type_string": type_str,
			"type_id":          type_id,
			"default_value":    default_val,
			"description":      var_comments.get(p.name, ""),
			"checked":          false,
			"choices_provider": auto_provider,
			"hint":             p.hint,
			"hint_string":      p.hint_string,
			"class_name":       p.class_name,
		})

	if _scanned_props.is_empty():
		_status_label.text = "No exported properties found."
		return
	_build_class_attribution(obj, is_builtin)
	_status_label.text = "%d exported properties found:" % _scanned_props.size()
	_display_property_checkboxes()


func _scanned_owner_name(obj: Object) -> String:
	var scr: Script = obj.get_script()
	if scr:
		if not scr.get_global_name().is_empty():
			return scr.get_global_name()
		if not scr.resource_path.is_empty():
			return scr.resource_path.get_file().get_basename()
	return obj.get_class()



func _display_property_checkboxes() -> void:
	for c in _props_container.get_children():
		c.queue_free()
	_prop_checkboxes.clear()
	_prop_checkboxes.resize(_scanned_props.size())
	_prop_type_opts.clear()
	_prop_type_opts.resize(_scanned_props.size())

	var group_indices: Dictionary = {}
	for i in _scanned_props.size():
		var g: String = _scanned_props[i].get("class_group", "")
		if not group_indices.has(g):
			group_indices[g] = []
		group_indices[g].append(i)

	var ordered: Array = []
	for k in range(_class_chain.size() - 1, -1, -1):
		var gname: String = _class_chain[k]
		if gname in _SKIP_CLASS_GROUPS:
			continue
		if not group_indices.has(gname):
			continue
		ordered.append({ "name": gname, "indices": group_indices[gname] })
		group_indices.erase(gname)

	for gname in group_indices:
		ordered.append({ "name": gname, "indices": group_indices[gname] })

	for entry in ordered:
		(entry.indices as Array).sort_custom(func(a: int, b: int) -> bool:
			var ca: bool = _scanned_props[a].get("checked", false)
			var cb_: bool = _scanned_props[b].get("checked", false)
			if ca != cb_: return ca
			return a < b
		)

	for entry in ordered:
		var gname: String = entry.name
		var idxs: Array = entry.indices

		if not gname.is_empty():
			var header := Label.new()
			header.text = gname
			header.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
			header.add_theme_font_size_override("font_size", 10)
			_props_container.add_child(header)

		for i in idxs:
			var prop: Dictionary = _scanned_props[i]
			var row_vbox := VBoxContainer.new()
			var row_panel := PanelContainer.new()
			row_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			_scanned_props[i]["_ui_row_panel"] = row_panel
			var hbox := HBoxContainer.new()
			row_panel.add_child(hbox)

			var cb := CheckBox.new()
			cb.text = prop.name
			cb.button_pressed = prop.get("checked", false)
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb.tooltip_text = "Default: %s" % str(prop.default_value)
			var idx: int = i
			cb.toggled.connect(func(pressed: bool) -> void:
				_scanned_props[idx].checked = pressed
				var cp: VBoxContainer = _scanned_props[idx].get("_ui_choices_panel")
				if cp:
					cp.visible = pressed and _scanned_props[idx].type_string in ["choices", "multi_choices"]
				dirty_changed.emit()
				_display_property_checkboxes.call_deferred()
			)
			hbox.add_child(cb)
			_prop_checkboxes[i] = cb

			var choices_panel := _build_choices_sub_panel(idx)
			_scanned_props[i]["_ui_choices_panel"] = choices_panel
			var current_type: String = prop.get("type_string", "")
			choices_panel.visible = current_type in ["choices", "multi_choices"] and prop.get("checked", false)

			var type_opt := OptionButton.new()
			type_opt.custom_minimum_size.x = 120
			if prop.get("type_id") == TYPE_OBJECT:
				type_opt.add_item("choices")
				type_opt.disabled = true
			else:
				var scanned_type: String = prop.get("orig_type_string", prop.type_string)
				type_opt.add_item(scanned_type)
				if scanned_type in ["String", "StringName"]:
					for special in ["source", "destination"]:
						type_opt.add_item(special)
				for choice_type in ["choices", "multi_choices"]:
					if choice_type != scanned_type:
						type_opt.add_item(choice_type)
				if current_type != scanned_type:
					for j in type_opt.item_count:
						if type_opt.get_item_text(j) == current_type:
							type_opt.select(j)
							break
			type_opt.item_selected.connect(func(sel_idx: int) -> void:
				var selected := type_opt.get_item_text(sel_idx)
				_scanned_props[idx].type_string = selected
				choices_panel.visible = selected in ["choices", "multi_choices"] and _scanned_props[idx].get("checked", false)
				dirty_changed.emit()
			)
			hbox.add_child(type_opt)
			_prop_type_opts[i] = type_opt

			var prop_type_id: int = prop.get("type_id", TYPE_NIL)
			var no_drag := func(_p: Vector2) -> Variant: return null
			var can_drop: Callable
			var do_drop: Callable
			if drag:
				can_drop = drag.make_can_drop(idx, prop_type_id)
				do_drop = drag.make_do_drop(idx)
			else:
				can_drop = func(_pos: Vector2, _data: Variant) -> bool: return false
				do_drop = func(_pos: Vector2, _data: Variant) -> void: pass
			cb.set_drag_forwarding(no_drag, can_drop, do_drop)
			type_opt.set_drag_forwarding(no_drag, can_drop, do_drop)

			row_vbox.add_child(row_panel)
			row_vbox.add_child(choices_panel)
			_props_container.add_child(row_vbox)


func _provider_label(provider: LMChoicesProvider) -> String:
	if not provider: return "Provider (empty: derived from the script's hint at sync)"
	if not provider.resource_path.is_empty():
		return provider.resource_path.get_file().get_basename()
	var scr := provider.get_script()
	if scr and not (scr as Script).get_global_name().is_empty():
		return (scr as Script).get_global_name()
	return provider.get_class()


func _build_choices_sub_panel(idx: int) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2)

	var saved_provider: LMChoicesProvider = _scanned_props[idx].get("choices_provider")

	var fold_hbox := HBoxContainer.new()
	var fold_btn := Button.new()
	fold_btn.flat = true
	fold_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold_btn.icon = get_theme_icon("GuiTreeArrowRight", "EditorIcons")
	fold_btn.text = _provider_label(saved_provider)
	fold_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fold_hbox.add_child(fold_btn)
	panel.add_child(fold_hbox)

	var border_panel := PanelContainer.new()
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	border_style.set_border_width_all(1)
	border_style.set_corner_radius_all(3)
	border_style.set_content_margin_all(6)
	border_panel.add_theme_stylebox_override("panel", border_style)
	border_panel.visible = false
	panel.add_child(border_panel)

	fold_btn.pressed.connect(func() -> void:
		border_panel.visible = not border_panel.visible
		fold_btn.icon = get_theme_icon(
			"GuiTreeArrowDown" if border_panel.visible else "GuiTreeArrowRight", "EditorIcons")
	)

	var inner := VBoxContainer.new()
	border_panel.add_child(inner)

	var picker_hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Provider:"
	picker_hbox.add_child(lbl)

	var picker := EditorResourcePicker.new()
	picker.base_type = "LMChoicesProvider"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if saved_provider:
		picker.edited_resource = saved_provider
	picker_hbox.add_child(picker)
	inner.add_child(picker_hbox)
	panel.set_meta("picker_ref", picker)

	var sub_inspector := EditorInspector.new()
	sub_inspector.custom_minimum_size.y = 80
	inner.add_child(sub_inspector)
	if saved_provider:
		sub_inspector.edit(saved_provider)

	picker.resource_changed.connect(func(res: Resource) -> void:
		_scanned_props[idx]["choices_provider"] = res
		sub_inspector.edit(res)
		fold_btn.text = _provider_label(res)
		dirty_changed.emit()
		if res and not border_panel.visible:
			border_panel.visible = true
			fold_btn.icon = get_theme_icon("GuiTreeArrowDown", "EditorIcons")
	)

	var preview_hbox := HBoxContainer.new()
	var preview_btn := Button.new()
	preview_btn.text = "Preview"
	var preview_lbl := Label.new()
	preview_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_btn.pressed.connect(func() -> void:
		var provider: LMChoicesProvider = _scanned_props[idx].get("choices_provider")
		if not provider:
			preview_lbl.text = "No provider set."
			return
		var choices := provider.get_choices()
		if choices.is_empty():
			preview_lbl.text = "(no choices returned)"
			return
		var lines: PackedStringArray = []
		for c in choices:
			lines.append("%s → %s" % [c["label"], str(c["value"])])
		preview_lbl.text = "\n".join(lines)
	)
	preview_hbox.add_child(preview_btn)
	preview_hbox.add_child(preview_lbl)
	inner.add_child(preview_hbox)

	return panel



func _detect_mode(id: String) -> SourceMode:
	if id.begins_with("uid://"):
		var uid_int := ResourceUID.text_to_id(id)
		if uid_int != ResourceUID.INVALID_ID:
			if ResourceUID.get_id_path(uid_int).get_extension() in ["tscn", "scn"]:
				return SourceMode.SCENE
		return SourceMode.SCRIPT
	if ClassDB.class_exists(id):
		return SourceMode.BUILTIN
	return SourceMode.BUILTIN


func _preselect_existing_props(def: LMEntityDefinition) -> void:
	if def.properties.is_empty(): return
	var existing: Dictionary = {}
	for p in def.properties:
		existing[p.name] = p

	for i in _scanned_props.size():
		var saved: LMEntityDefinitionProp = existing.get(_scanned_props[i].name)
		if not saved: continue
		_scanned_props[i].checked = true
		if i < _prop_checkboxes.size():
			_prop_checkboxes[i].set_pressed_no_signal(true)

		if saved.type in ["choices", "multi_choices"]:
			_scanned_props[i].type_string = saved.type
			_scanned_props[i]["choices_provider"] = saved.choices
			if i < _prop_type_opts.size():
				for j in _prop_type_opts[i].item_count:
					if _prop_type_opts[i].get_item_text(j) == saved.type:
						_prop_type_opts[i].select(j)
						break
			var cp: VBoxContainer = _scanned_props[i].get("_ui_choices_panel")
			if cp:
				cp.visible = true
				var p_picker = cp.get_meta("picker_ref", null)
				if p_picker and saved.choices:
					p_picker.edited_resource = saved.choices
		elif saved.type in ["source", "destination"]:
			_scanned_props[i].type_string = saved.type
			if i < _prop_type_opts.size():
				for j in _prop_type_opts[i].item_count:
					if _prop_type_opts[i].get_item_text(j) == saved.type:
						_prop_type_opts[i].select(j)
						break

	_display_property_checkboxes()

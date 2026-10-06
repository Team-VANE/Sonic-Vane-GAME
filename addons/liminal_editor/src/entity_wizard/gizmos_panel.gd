@tool
class_name LMGizmosPanel extends VBoxContainer

signal dirty_changed

const GIZMO_PROP_GODOT_TYPE: Dictionary = {
	"radius": TYPE_FLOAT,
	"length": TYPE_FLOAT,
	"angle":  TYPE_FLOAT,
	"fov":    TYPE_FLOAT,
	"near":   TYPE_FLOAT,
	"far":    TYPE_FLOAT,
	"size":   TYPE_FLOAT,
	"size_x": TYPE_FLOAT,
	"size_y": TYPE_FLOAT,
	"size_z": TYPE_FLOAT,
	"alpha":  TYPE_FLOAT,
	"offset": TYPE_VECTOR3,
	"euler":  TYPE_VECTOR3,
	"color":  TYPE_COLOR,
	"icon":   TYPE_STRING,
	"text":   TYPE_STRING,
	"closed": TYPE_BOOL,
}

const _GIZMO_TYPES   := ["sphere", "arrow", "cone", "box", "frustum", "billboard", "volume", "text", "path"]
const _GIZMO_STYLES  := ["wire", "solid"]
const _GIZMO_PARAM_FIELDS := {
	"sphere":    [["radius", "Radius"]],
	"arrow":     [["length", "Length"]],
	"cone":      [["length", "Length"], ["angle", "Angle°"]],
	"box":       [["size", "Half-size"], ["size_x", "Half-size X"], ["size_y", "Half-size Y"], ["size_z", "Half-size Z"]],
	"frustum":   [["fov", "FOV°"], ["near", "Near"], ["far", "Far"]],
	"billboard": [["size", "Size"], ["icon", "Icon"]],
	"volume":    [],
	"text":      [["text", "Text"], ["size", "Font Size"]],
	"path":      [],
}

var _gizmo_rows: Array[Dictionary] = []
var _gizmos_container: VBoxContainer
var drag: LMBindingDrag


func _ready() -> void:
	name = "GizmosVBox"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.name = "GizmosHeader"
	header.text = "Gizmos"
	header.add_theme_font_size_override("font_size", 13)
	add_child(header)

	var sep := HSeparator.new()
	sep.name = "GizmosSep"
	add_child(sep)

	_gizmos_container = VBoxContainer.new()
	_gizmos_container.name = "GizmosContainer"
	add_child(_gizmos_container)

	var add_btn := Button.new()
	add_btn.name = "BtnAddGizmo"
	add_btn.text = "+ Add Gizmo"
	add_btn.pressed.connect(func() -> void:
		_add_row()
		dirty_changed.emit()
	)
	add_child(add_btn)


func reset() -> void:
	for c in _gizmos_container.get_children():
		c.queue_free()
	_gizmo_rows.clear()


func restore_from_def(def: LMEntityDefinition) -> void:
	if not def: return
	for g in def.gizmos:
		if not g or g.type.is_empty(): continue
		var fields: Dictionary = {}
		for fn in ["radius", "length", "angle", "fov", "near", "far", "size", "size_x", "size_y", "size_z", "alpha", "icon", "text", "offset", "euler", "mode", "closed"]:
			var val = g.get(fn)
			if val is String and not val.is_empty():
				fields[fn] = val
		if not g.color.is_empty(): fields["color"] = g.color
		if not g.style.is_empty(): fields["style"] = g.style
		var bindings: Dictionary = g.bindings.duplicate() if g.bindings else {}
		for fn in fields.keys():
			if fields[fn] is String and (fields[fn] as String).begins_with("$"):
				bindings[fn] = (fields[fn] as String).substr(1)
				fields.erase(fn)
		_add_row(g.type, fields, bindings)


func get_gizmos() -> Array[LMEntityGizmoDef]:
	var result: Array[LMEntityGizmoDef] = []
	for gd in _gizmo_rows:
		var g := LMEntityGizmoDef.new()
		g.type = gd["type"]
		for fn in gd["fields"]:
			if g.get(fn) != null:
				g.set(fn, gd["fields"][fn])
		g.bindings = gd["bindings"].duplicate()
		result.append(g)
	return result


func _add_row(type: String = "sphere", fields: Dictionary = {}, bindings: Dictionary = {}) -> void:
	var row_data := {
		"type":             type,
		"fields":           fields.duplicate(),
		"bindings":         bindings.duplicate(),
		"row_node":         null,
		"params_container": null,
	}
	_gizmo_rows.append(row_data)

	var row_vbox := VBoxContainer.new()
	row_data["row_node"] = row_vbox

	var top_hbox := HBoxContainer.new()

	var type_opt := OptionButton.new()
	type_opt.custom_minimum_size.x = 100
	for t in _GIZMO_TYPES:
		type_opt.add_item(t)
	for i in type_opt.item_count:
		if type_opt.get_item_text(i) == type:
			type_opt.select(i)
			break

	var style_opt := OptionButton.new()
	style_opt.custom_minimum_size.x = 72
	for s in _GIZMO_STYLES:
		style_opt.add_item(s)
	var current_style: String = fields.get("style", "wire")
	for i in style_opt.item_count:
		if style_opt.get_item_text(i) == current_style:
			style_opt.select(i)
			break
	style_opt.item_selected.connect(func(sel_idx: int) -> void:
		row_data["fields"]["style"] = style_opt.get_item_text(sel_idx)
		dirty_changed.emit()
	)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.pressed.connect(func() -> void:
		_gizmo_rows.erase(row_data)
		row_vbox.queue_free()
		dirty_changed.emit()
	)

	top_hbox.add_child(type_opt)
	top_hbox.add_child(style_opt)
	top_hbox.add_child(spacer)
	top_hbox.add_child(remove_btn)

	var params_vbox := VBoxContainer.new()
	params_vbox.add_theme_constant_override("separation", 2)
	row_data["params_container"] = params_vbox

	type_opt.item_selected.connect(func(sel_idx: int) -> void:
		row_data["type"] = type_opt.get_item_text(sel_idx)
		row_data["fields"].clear()
		row_data["bindings"].clear()
		_rebuild_params(row_data)
		dirty_changed.emit()
	)

	row_vbox.add_child(top_hbox)
	row_vbox.add_child(params_vbox)
	row_vbox.add_child(HSeparator.new())

	_rebuild_params(row_data)
	_gizmos_container.add_child(row_vbox)


func _rebuild_params(row_data: Dictionary) -> void:
	var container: VBoxContainer = row_data["params_container"]
	for c in container.get_children():
		c.queue_free()
	container.add_child(_build_field_row(row_data, "color", "Color"))
	if row_data["type"] != "text":
		container.add_child(_build_field_row(row_data, "alpha", "Fill α"))
	var type_fields: Array = _GIZMO_PARAM_FIELDS.get(row_data["type"], [])
	var transform_fields: Array = [] if row_data["type"] in ["volume", "path"] else [["offset", "Offset"], ["euler", "Euler°"]]
	for pair in type_fields + transform_fields:
		container.add_child(_build_field_row(row_data, pair[0], pair[1]))
	if row_data["type"] == "path":
		container.add_child(_build_path_mode_row(row_data))
		container.add_child(_build_field_row(row_data, "closed", "Closed"))


func _build_path_mode_row(row_data: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Mode:"
	lbl.custom_minimum_size.x = 58
	hbox.add_child(lbl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in ["hierarchy", "nearest"]:
		opt.add_item(m)
	var current: String = row_data["fields"].get("mode", "hierarchy")
	for i in opt.item_count:
		if opt.get_item_text(i) == current:
			opt.select(i)
			break
	opt.item_selected.connect(func(idx: int) -> void:
		row_data["fields"]["mode"] = opt.get_item_text(idx)
		dirty_changed.emit()
	)
	hbox.add_child(opt)
	return hbox


func _build_field_row(row_data: Dictionary, field_name: String, field_label: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()

	var lbl := Label.new()
	lbl.text = field_label + ":"
	lbl.custom_minimum_size.x = 58
	hbox.add_child(lbl)

	var expected_type: int = GIZMO_PROP_GODOT_TYPE.get(field_name, TYPE_STRING)
	var is_bound: bool = row_data["bindings"].has(field_name)
	var stored_val: String = row_data["fields"].get(field_name, "")

	var input_ctrl: Control
	match expected_type:
		TYPE_FLOAT:
			var spin := SpinBox.new()
			spin.custom_minimum_size.x = 70
			spin.min_value = -99999.0
			spin.max_value = 99999.0
			spin.step = 0.01
			spin.allow_greater = true
			spin.allow_lesser = true
			if not stored_val.is_empty():
				spin.set_value_no_signal(float(stored_val))
			spin.value_changed.connect(func(v: float) -> void:
				row_data["fields"][field_name] = str(v)
				dirty_changed.emit()
			)
			input_ctrl = spin
		TYPE_BOOL:
			var chk := CheckBox.new()
			chk.button_pressed = stored_val == "true"
			chk.toggled.connect(func(on: bool) -> void:
				row_data["fields"][field_name] = "true" if on else ""
				dirty_changed.emit()
			)
			input_ctrl = chk
		TYPE_COLOR:
			var cpb := ColorPickerButton.new()
			cpb.custom_minimum_size.x = 60
			cpb.edit_alpha = false
			if not stored_val.is_empty():
				cpb.color = Color(stored_val)
			cpb.color_changed.connect(func(c: Color) -> void:
				row_data["fields"][field_name] = "#%s" % c.to_html(false)
				dirty_changed.emit()
			)
			input_ctrl = cpb
		TYPE_VECTOR3:
			var xyz_box := HBoxContainer.new()
			xyz_box.add_theme_constant_override("separation", 2)
			var parts := stored_val.split(",")
			for axis_idx in 3:
				var axis_lbl := Label.new()
				axis_lbl.text = (["X", "Y", "Z"])[axis_idx]
				axis_lbl.custom_minimum_size.x = 10
				xyz_box.add_child(axis_lbl)
				var spin := SpinBox.new()
				spin.custom_minimum_size.x = 52
				spin.min_value = -99999.0
				spin.max_value = 99999.0
				spin.step = 0.001
				spin.allow_greater = true
				spin.allow_lesser = true
				if axis_idx < parts.size() and not parts[axis_idx].strip_edges().is_empty():
					spin.set_value_no_signal(float(parts[axis_idx].strip_edges()))
				var captured_axis := axis_idx
				var captured_spin := spin
				captured_spin.value_changed.connect(func(_v: float) -> void:
					var cur: PackedStringArray = row_data["fields"].get(field_name, "0,0,0").split(",")
					while cur.size() < 3:
						cur.append("0")
					cur[captured_axis] = str(captured_spin.value)
					row_data["fields"][field_name] = ",".join(cur)
					dirty_changed.emit()
				)
				xyz_box.add_child(spin)
			input_ctrl = xyz_box
		_:
			if field_name == "text":
				var te := TextEdit.new()
				te.custom_minimum_size = Vector2(90, 56)
				te.placeholder_text = "{{prop}} or literal\nSupports multiple lines"
				te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				te.text = stored_val
				te.text_changed.connect(func() -> void:
					row_data["fields"][field_name] = te.text
					dirty_changed.emit()
				)
				input_ctrl = te
			else:
				var le := LineEdit.new()
				le.custom_minimum_size.x = 90
				le.placeholder_text = "val"
				le.text = stored_val
				le.text_changed.connect(func(v: String) -> void:
					row_data["fields"][field_name] = v
					dirty_changed.emit()
				)
				input_ctrl = le

	input_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_ctrl.visible = not is_bound
	hbox.add_child(input_ctrl)

	if field_name == "text":
		return hbox

	var bound_lbl := Label.new()
	bound_lbl.text = "→ %s" % row_data["bindings"].get(field_name, "")
	bound_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	bound_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bound_lbl.clip_text = true
	bound_lbl.visible = is_bound
	hbox.add_child(bound_lbl)

	var clear_btn := Button.new()
	clear_btn.text = "×"
	clear_btn.custom_minimum_size = Vector2(22, 0)
	clear_btn.visible = is_bound
	hbox.add_child(clear_btn)

	var dot := Button.new()
	dot.text = "●"
	dot.custom_minimum_size = Vector2(24, 24)
	dot.flat = true
	if is_bound:
		dot.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	hbox.add_child(dot)

	clear_btn.pressed.connect(func() -> void:
		row_data["bindings"].erase(field_name)
		bound_lbl.visible = false
		clear_btn.visible = false
		input_ctrl.visible = true
		dot.remove_theme_color_override("font_color")
		dirty_changed.emit()
	)

	var _dot_drag_data := func(_pos: Vector2) -> Variant:
		if drag:
			drag.begin_drag(expected_type)
		return drag.make_drag_data(field_name, expected_type,
			func(entity_prop: String) -> void:
				row_data["bindings"][field_name] = entity_prop
				bound_lbl.text = "→ %s" % entity_prop
				bound_lbl.visible = true
				clear_btn.visible = true
				input_ctrl.visible = false
				dot.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
				dirty_changed.emit()
		)
	dot.set_drag_forwarding(
		_dot_drag_data,
		func(_pos: Vector2, _data: Variant) -> bool: return false,
		func(_pos: Vector2, _data: Variant) -> void: pass
	)

	return hbox

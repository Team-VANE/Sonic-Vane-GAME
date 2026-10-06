@tool
class_name LMBindingDrag extends RefCounted

var _was_dragging: bool = false
var _drag_expected_type: int = TYPE_NIL
var _scanned_props: Array[Dictionary] = []


func set_props(arr: Array[Dictionary]) -> void:
	_scanned_props = arr


func begin_drag(expected_type: int) -> void:
	_drag_expected_type = expected_type
	_was_dragging = true
	_update_highlights()


func tick(is_dragging: bool) -> void:
	if _was_dragging and not is_dragging:
		_was_dragging = false
		_drag_expected_type = TYPE_NIL
		_update_highlights()


func make_drag_data(field_name: String, expected_type: int, apply_fn: Callable) -> Dictionary:
	return {
		"type": "lm_gizmo_prop",
		"prop_name": field_name,
		"expected_type": expected_type,
		"apply_binding": apply_fn,
	}


func make_can_drop(prop_idx: int, prop_type_id: int) -> Callable:
	return func(_pos: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or data.get("type") != "lm_gizmo_prop":
			return false
		if prop_idx >= _scanned_props.size():
			return false
		if not _scanned_props[prop_idx].get("checked", false):
			return false
		var expected: int = data.get("expected_type", TYPE_NIL)
		return expected == prop_type_id or (expected == TYPE_FLOAT and prop_type_id == TYPE_INT)


func make_do_drop(prop_idx: int) -> Callable:
	return func(_pos: Vector2, data: Variant) -> void:
		if not (data is Dictionary): return
		var fn: Callable = data.get("apply_binding", Callable())
		if fn.is_valid() and prop_idx < _scanned_props.size():
			fn.call(_scanned_props[prop_idx].name)


func _update_highlights() -> void:
	for i in _scanned_props.size():
		var panel: PanelContainer = _scanned_props[i].get("_ui_row_panel")
		if not panel:
			continue
		var show := false
		if _drag_expected_type != TYPE_NIL:
			var prop := _scanned_props[i]
			var checked: bool = prop.get("checked", false)
			var prop_type: int = prop.get("type_id", TYPE_NIL)
			var compatible: bool = prop_type == _drag_expected_type \
				or (_drag_expected_type == TYPE_FLOAT and prop_type == TYPE_INT)
			show = checked and compatible
		if show:
			var s := StyleBoxFlat.new()
			s.bg_color = Color(0, 0, 0, 0)
			s.border_color = Color("#3ba4ff")
			s.set_border_width_all(2)
			s.set_corner_radius_all(3)
			panel.add_theme_stylebox_override("panel", s)
		else:
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

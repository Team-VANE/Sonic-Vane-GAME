extends Control

## Camera rig providing the constraint offset state.
var rig: Node3D
var _state: Dictionary = {}
var _scale: float = 1.0
var _style: StyleBoxFlat = StyleBoxFlat.new()
## Player diagnostics HUD supplying the sidecar anchor and shared scale.
var _diagnostics_hud: Control = null
const PANEL_SIZE: Vector2 = Vector2(330.0, 205.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_style.bg_color = Color(0.015, 0.025, 0.045, 0.92)
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(8)


func _process(_delta: float) -> void:
	if not is_instance_valid(rig):
		hide()
		_release_dock()
		return
	var driver: CameraConstraintController = rig.get("_constraint_driver") as CameraConstraintController
	_state = driver.get_mouse_debug_state()
	var target: Node3D = rig.get("target") as Node3D
	var debug_view: Variant = target.get("_debug_visible") if is_instance_valid(target) else false
	var enabled: bool = bool(rig.get("constraint_mouse_debug_enabled")) or (debug_view is bool and debug_view)
	visible = enabled and bool(_state.get("visible", false)) and not bool(rig.call("_is_camera_input_blocked_by_ui")) and not get_tree().paused
	if not visible:
		_release_dock()
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_scale = clampf(minf(viewport_size.x / 640.0, viewport_size.y / 480.0), 0.55, 1.0)
	var hud: Control = target.get("_debug_hud") as Control if is_instance_valid(target) else null
	if hud != _diagnostics_hud:
		_release_dock()
		_diagnostics_hud = hud
	if is_instance_valid(hud) and hud.is_visible_in_tree() and hud.has_method("get_diagnostics_frame_rect"):
		hud.call("set_sidecar_width", PANEL_SIZE.x + 12.0)
		var frame: Rect2 = hud.call("get_diagnostics_frame_rect") as Rect2
		_scale = hud.get_global_transform_with_canvas().get_scale().x
		position = Vector2(frame.end.x + 12.0 * _scale, frame.position.y)
	else:
		_release_dock()
		position = Vector2(viewport_size.x - PANEL_SIZE.x * _scale - 16.0 * _scale, 16.0 * _scale)
	size = PANEL_SIZE * _scale
	queue_redraw()


func _release_dock() -> void:
	if is_instance_valid(_diagnostics_hud) and _diagnostics_hud.has_method("set_sidecar_width"):
		_diagnostics_hud.call("set_sidecar_width", 0.0)
	_diagnostics_hud = null


func _exit_tree() -> void:
	_release_dock()


func _text(point: Vector2, value: String, color: Color = Color.WHITE, font_size: int = 14) -> void:
	draw_string(ThemeDB.fallback_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw() -> void:
	if _state.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _scale)
	var influence: float = float(_state.get("influence", 1.0))
	var suppressed: bool = bool(_state.get("suppressed", false))
	var accent: Color = Color(0.35, 0.95, 0.65).lerp(Color(1.0, 0.3, 0.25), 1.0 - influence)
	_style.border_color = accent.darkened(0.35)
	draw_style_box(_style, Rect2(Vector2.ZERO, PANEL_SIZE))
	_text(Vector2(14.0, 24.0), "CONSTRAINT LOOK OFFSET", accent, 16)
	_text(Vector2(14.0, 44.0), String(_state.get("name", "")), Color(0.7, 0.8, 0.9), 13)
	var centre: Vector2 = Vector2(72.0, 111.0)
	var radius: float = 48.0
	var threshold: float = maxf(float(_state.get("threshold", 1.0)), 0.001)
	var inner: float = clampf(float(_state.get("falloff_start", 0.0)) / threshold, 0.0, 1.0)
	draw_circle(centre, radius, Color(0.06, 0.1, 0.14))
	draw_arc(centre, radius, 0.0, TAU, 64, Color(1.0, 0.35, 0.3), 1.5, true)
	draw_arc(centre, radius * inner, 0.0, TAU, 48, Color(0.35, 0.95, 0.65), 1.0, true)
	draw_line(centre - Vector2(radius, 0.0), centre + Vector2(radius, 0.0), Color(0.25, 0.3, 0.4))
	draw_line(centre - Vector2(0.0, radius), centre + Vector2(0.0, radius), Color(0.25, 0.3, 0.4))
	var offset: Vector2 = _state.get("offset", Vector2.ZERO)
	var dot: Vector2 = centre + Vector2(-offset.x, offset.y).limit_length(threshold) / threshold * radius
	draw_line(centre, dot, accent, 2.0, true)
	draw_circle(dot, 4.0, accent)
	var status: String = "RELEASED" if suppressed else ("REJOINING" if bool(_state.get("returning", false)) else ("CENTERING" if offset.length_squared() > 0.000001 and float(_state.get("grace", 0.0)) <= 0.0 else "OFFSET"))
	_text(Vector2(139.0, 77.0), status, accent)
	_text(Vector2(139.0, 100.0), "Offset: %.1f / %.1f deg" % [rad_to_deg(offset.length()), rad_to_deg(threshold)])
	_text(Vector2(139.0, 123.0), "Influence: %.0f%%" % (influence * 100.0))
	var timer: float = float(_state.get("suppression_remaining", 0.0)) if suppressed else float(_state.get("grace", 0.0))
	_text(Vector2(139.0, 146.0), ("Return gate: %.2fs" if suppressed else "Grace: %.2fs") % timer)
	draw_rect(Rect2(14.0, 173.0, 302.0, 8.0), Color(0.12, 0.18, 0.23))
	draw_rect(Rect2(14.0, 173.0, 302.0 * influence, 8.0), accent)
	_text(Vector2(14.0, 197.0), "Green: bias   Red: release threshold", Color(0.7, 0.8, 0.9), 12)

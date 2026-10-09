extends "res://LS5Framework/Scripts/UI/HUDResolutionScale.gd"
class_name PlayerDebugHUD

## Diagnostics frame used to dock adjacent debug overlays.
@onready var main_frame: Control = $SafeArea/MainFrame
var _sidecar_width: float = 0.0
@onready var status_label: Label = $SafeArea/MainFrame/Content/Header/Status
@onready var overview_label: Label = $SafeArea/MainFrame/Content/Categories/Overview/CardContent/Values
@onready var movement_label: Label = $SafeArea/MainFrame/Content/Categories/Movement/CardContent/Values
@onready var surface_label: Label = $SafeArea/MainFrame/Content/Categories/Surface/CardContent/Values
@onready var ledge_label: Label = $SafeArea/MainFrame/Content/Categories/LedgeGrab/CardContent/Values
@onready var extended_panel: PanelContainer = $SafeArea/MainFrame/Content/Extended
@onready var legacy_label: Label = $SafeArea/MainFrame/Content/Extended/ExtendedContent/LegacyScroll/LegacyText


func _ready() -> void:
	super._ready()
	main_frame.resized.connect(_queue_scale_update)


func update_sections(data: Dictionary) -> void:
	visible = bool(data.get("visible", false))
	if not visible:
		return
	overview_label.text = String(data.get("overview", ""))
	movement_label.text = String(data.get("movement", ""))
	surface_label.text = String(data.get("surface", ""))
	ledge_label.text = String(data.get("ledge", ""))
	var status: StringName = StringName(data.get("status", &"IDLE"))
	status_label.text = String(status)
	_apply_status_color(status)
	var show_extended: bool = bool(data.get("show_extended", false))
	extended_panel.visible = show_extended
	legacy_label.visible = show_extended


func get_legacy_label() -> Label:
	return legacy_label


func get_diagnostics_frame_rect() -> Rect2:
	return main_frame.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, main_frame.size)


func set_sidecar_width(width: float) -> void:
	if is_equal_approx(_sidecar_width, width):
		return
	_sidecar_width = maxf(width, 0.0)
	_update_scale()


func _update_scale() -> void:
	super._update_scale()
	if _sidecar_width <= 0.0 or not is_instance_valid(main_frame):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var logical_right: float = get_diagnostics_frame_rect().end.x / maxf(scale.x, 0.001)
	var fitted_scale: float = minf(scale.x, viewport_size.x / maxf(logical_right + _sidecar_width + 18.0, 1.0))
	size = viewport_size / fitted_scale
	scale = Vector2.ONE * fitted_scale


func _apply_status_color(status: StringName) -> void:
	var color: Color = Color(0.55, 0.68, 0.82, 1.0)
	if status == &"ACTIVE":
		color = Color(0.35, 1.0, 0.58, 1.0)
	elif status == &"PROBING":
		color = Color(1.0, 0.82, 0.25, 1.0)
	elif status == &"BLOCKED":
		color = Color(1.0, 0.4, 0.32, 1.0)
	status_label.add_theme_color_override(&"font_color", color)

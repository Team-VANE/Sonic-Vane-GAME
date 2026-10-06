extends Control

## Logical resolution used to calculate the HUD scale.
@export var design_resolution: Vector2 = Vector2(1920, 1080)
## Smallest permitted HUD scale.
@export var min_scale: float = 0.6
## Largest permitted HUD scale.
@export var max_scale: float = 2.0

func _ready() -> void:
	_update_scale()
	var viewport: Viewport = get_viewport()
	if viewport and not viewport.size_changed.is_connected(_queue_scale_update):
		viewport.size_changed.connect(_queue_scale_update)


func _queue_scale_update() -> void:
	call_deferred("_update_scale")

func _update_scale() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var safe_design_resolution: Vector2 = Vector2(max(design_resolution.x, 1.0), max(design_resolution.y, 1.0))
	var scale_x: float = viewport_size.x / safe_design_resolution.x
	var scale_y: float = viewport_size.y / safe_design_resolution.y
	var uniform_scale: float = min(scale_x, scale_y)
	uniform_scale = clamp(uniform_scale, min_scale, max_scale)

	# Clear anchors so we can control size directly.
	# Without this, a full-rect control scaled from top-left grows beyond the viewport,
	# pushing corner-anchored children (speedometer, gauge) off-screen.
	anchors_preset = Control.PRESET_TOP_LEFT
	anchor_right = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	position = Vector2.ZERO

	# Logical size = viewport / scale, so visual size = viewport.
	# This keeps all corner-anchored elements within screen bounds
	# while still scaling their apparent size and margins.
	size = viewport_size / uniform_scale
	scale = Vector2(uniform_scale, uniform_scale)

extends Control
class_name HUDItemNotificationEntry

signal power_up_expired(entry: HUDItemNotificationEntry)

const BUFF_COLOR_FULL: Color = Color(0.2, 0.95, 0.18, 1.0)
const BUFF_COLOR_HALF: Color = Color(1.0, 0.84, 0.08, 1.0)
const BUFF_COLOR_EMPTY: Color = Color(1.0, 0.12, 0.08, 1.0)

## Displays the shared item icon background.
@onready var background: TextureRect = $Background
## Displays the foreground texture associated with the collected item.
@onready var item_icon: TextureRect = $ItemIcon
## Displays the collected quantity when it is greater than one.
@onready var quantity_label: Label = $QuantityLabel
## Displays remaining duration for active timed buffs.
@onready var buff_progress_frame: Panel = $BuffProgressFrame
## Colored segment showing the remaining buff duration.
@onready var buff_progress_fill: ColorRect = $BuffProgressFrame/BuffProgressFill

var item_id: StringName = &""
var is_power_up: bool = false
var _effect_duration: float = 0.0
var _effect_remaining: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_update_pivot)
	_update_pivot()
	buff_progress_frame.resized.connect(_update_power_up_progress)
	buff_progress_frame.visible = false
	set_process(false)


func _process(delta: float) -> void:
	if not is_power_up:
		return
	_effect_remaining = max(_effect_remaining - delta, 0.0)
	_update_power_up_progress()
	if _effect_remaining <= 0.0:
		set_process(false)
		power_up_expired.emit(self)


func configure(
		background_texture: Texture2D,
		item_texture: Texture2D,
		amount: float,
		display_size: Vector2,
		show_quantity: bool,
		configured_item_id: StringName = &"",
		power_up: bool = false,
		effect_duration: float = -1.0
	) -> void:
	item_id = configured_item_id
	is_power_up = power_up and effect_duration > 0.0
	custom_minimum_size = display_size
	size = display_size
	background.texture = background_texture
	item_icon.texture = item_texture
	quantity_label.text = _format_amount(amount)
	quantity_label.visible = show_quantity and not is_equal_approx(amount, 1.0)
	buff_progress_frame.visible = is_power_up
	if is_power_up:
		refresh_power_up(effect_duration)
	else:
		set_process(false)
	_update_pivot()


func refresh_power_up(effect_duration: float) -> void:
	is_power_up = effect_duration > 0.0
	_effect_duration = max(effect_duration, 0.001)
	_effect_remaining = _effect_duration
	_update_power_up_progress()
	set_process(is_power_up)


func get_effect_remaining() -> float:
	return max(_effect_remaining, 0.0)


func _format_amount(amount: float) -> String:
	var rounded_amount: float = round(amount)
	if is_equal_approx(amount, rounded_amount):
		return str(int(rounded_amount))
	return "%.1f" % amount


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _update_power_up_progress() -> void:
	var remaining_ratio: float = clamp(_effect_remaining / max(_effect_duration, 0.001), 0.0, 1.0)
	_set_power_up_progress(remaining_ratio)


func _set_power_up_progress(remaining_ratio: float) -> void:
	var progress: float = clampf(remaining_ratio, 0.0, 1.0)
	var fill_color: Color
	if progress >= 0.5:
		fill_color = BUFF_COLOR_HALF.lerp(BUFF_COLOR_FULL, (progress - 0.5) * 2.0)
	else:
		fill_color = BUFF_COLOR_EMPTY.lerp(BUFF_COLOR_HALF, progress * 2.0)
	buff_progress_fill.color = fill_color
	var inner_width: float = maxf(buff_progress_frame.size.x - 4.0, 0.0)
	var inner_height: float = maxf(buff_progress_frame.size.y - 4.0, 0.0)
	buff_progress_fill.position = Vector2(2.0, 2.0)
	buff_progress_fill.size = Vector2(inner_width * progress, inner_height)

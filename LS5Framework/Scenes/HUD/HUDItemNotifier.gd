extends Control
class_name HUDItemNotifier

## Item-to-icon mappings available to the notifier.
@export var item_icon_associations: Array[ItemIconAssociation] = [
	preload("res://LS5Framework/Resources/Items/RingItemIconAssociation.tres"),
	preload("res://LS5Framework/Resources/Items/SpeedShoesItemIconAssociation.tres"),
	preload("res://LS5Framework/Resources/Items/InvincibilityItemIconAssociation.tres"),
]
## Background frame displayed behind every item icon.
@export var icon_background_texture: Texture2D = preload("res://LS5Framework/Images/Icons/ItemMonitor_Icon_Background.png")
## Scene used for each queued item notification.
@export var notification_entry_scene: PackedScene = preload("res://LS5Framework/Scenes/HUD/HUDItemNotificationEntry.tscn")
## Logical size of each notification icon.
@export var entry_size: Vector2 = Vector2(144.0, 144.0)
## Horizontal gap between notification icons.
@export var entry_spacing: float = 22.0
## Minimum horizontal distance between the icon group and the screen edges.
@export var horizontal_margin: float = 40.0
## Vertical screen ratio used as the center of the icon group.
@export_range(0.0, 1.0, 0.01) var vertical_position_ratio: float = 0.76
## Extra distance beyond the left screen edge used by incoming icons.
@export var sweep_start_margin: float = 40.0
## Duration of the left-to-center sweep animation.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var sweep_duration: float = 0.45
## Duration used when existing icons reorganize around the center.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var reflow_duration: float = 0.25
## Delay after the latest item before cleanup or power-up settling begins.
@export_range(0.0, 30.0, 0.01, "or_greater", "suffix:s") var hold_duration: float = 1.5
## Duration of the collective shrink animation before cleanup.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var shrink_duration: float = 1.0
## Duration used to restore shrinking icons when another item arrives.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var restore_duration: float = 0.2
## Displays reward quantities greater than one over their icons.
@export var show_quantities: bool = true

@export_group("Power-Up Queue")
## Scale used by power-up icons after they settle beside the speedometer.
@export_range(0.1, 2.0, 0.01) var power_up_scale: float = 0.7
## Distance between the right screen edge and the nearest queued power-up icon.
@export var power_up_right_margin: float = 230.0
## Gap between settled power-up icons and the speedometer's left edge.
@export var power_up_speedometer_gap: float = 10.0
## Distance between the bottom screen edge and queued power-up icons.
@export var power_up_bottom_margin: float = 20.0
## Horizontal gap between queued power-up icons.
@export var power_up_spacing: float = 12.0
## Duration of the center-to-queue settling animation.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var power_up_settle_duration: float = 0.45
@export_group("Power-Up Bar")
## Padding surrounding the queued power-up icons.
@export var power_up_bar_padding: Vector2 = Vector2(16.0, 12.0)
## Distance the power-up bar extends toward the speedometer beyond the nearest icon.
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:px") var power_up_bar_connector_overlap: float = 20.0
## Time taken by the power-up bar to expand from the speedometer.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var power_up_bar_expand_duration: float = 0.34
## Time taken by the power-up bar to resize around its queue.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var power_up_bar_resize_duration: float = 0.24
## Time taken by the power-up bar to collapse into the speedometer.
@export_range(0.0, 5.0, 0.01, "or_greater", "suffix:s") var power_up_bar_collapse_duration: float = 0.24

## Frames the settled timed power-up queue beside the speedometer.
@onready var _power_up_bar: PanelContainer = $PowerUpBar
## Aligns the settled power-up queue with the speedometer.
@onready var _speedometer: Control = get_node_or_null("../Speedometer") as Control
## Contains the dynamically created notification entries.
@onready var _entry_layer: Control = $EntryLayer

var _entries: Array[HUDItemNotificationEntry] = []
var _power_up_entries: Array[HUDItemNotificationEntry] = []
var _discarding_entries: Array[HUDItemNotificationEntry] = []
var _hold_remaining: float = 0.0
var _shrinking: bool = false
var _layout_tween: Tween
var _cleanup_tween: Tween
var _restore_tween: Tween
var _power_up_layout_tween: Tween
var _power_up_bar_tween: Tween
var _power_up_bar_style: StyleBoxFlat = null
var _power_up_bar_expanded: bool = false
var _primary_color: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prepare_power_up_bar_style()
	_update_power_up_bar(false)
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	set_process(false)


func _process(delta: float) -> void:
	if _entries.is_empty() or _shrinking:
		return
	_hold_remaining = max(_hold_remaining - delta, 0.0)
	if _hold_remaining <= 0.0:
		_begin_cleanup()


func enqueue_item(item_id: StringName, amount: float = 1.0, effect_duration: float = -1.0) -> bool:
	if item_id == &"" or notification_entry_scene == null or icon_background_texture == null:
		return false
	var association: ItemIconAssociation = _find_item_association(item_id)
	if association == null or association.icon_texture == null:
		return false
	var power_up: bool = association.is_power_up and effect_duration > 0.0
	if power_up:
		var existing_entry: HUDItemNotificationEntry = _find_power_up_entry(item_id)
		if existing_entry != null:
			return _refresh_power_up_entry(existing_entry, effect_duration)
	var entry_instance: Node = notification_entry_scene.instantiate()
	if not (entry_instance is HUDItemNotificationEntry):
		if entry_instance != null:
			entry_instance.queue_free()
		return false
	_cancel_cleanup()
	var entry: HUDItemNotificationEntry = entry_instance as HUDItemNotificationEntry
	_entry_layer.add_child(entry)
	entry.configure(
		icon_background_texture,
		association.icon_texture,
		amount,
		entry_size,
		show_quantities,
		item_id,
		power_up,
		effect_duration
	)
	if power_up and not entry.power_up_expired.is_connected(_on_power_up_expired):
		entry.power_up_expired.connect(_on_power_up_expired)
	entry.scale = Vector2.ONE
	_entries.push_front(entry)
	_hold_remaining = max(hold_duration, 0.0)
	set_process(true)
	_layout_entries(true, entry)
	return true


func _find_item_association(item_id: StringName) -> ItemIconAssociation:
	for association: ItemIconAssociation in item_icon_associations:
		if association != null and association.item_id == item_id:
			return association
	return null


func _find_power_up_entry(item_id: StringName) -> HUDItemNotificationEntry:
	for entry: HUDItemNotificationEntry in _entries:
		if entry != null and is_instance_valid(entry) and entry.is_power_up and entry.item_id == item_id:
			return entry
	for entry: HUDItemNotificationEntry in _power_up_entries:
		if entry != null and is_instance_valid(entry) and entry.item_id == item_id:
			return entry
	return null


func _refresh_power_up_entry(entry: HUDItemNotificationEntry, effect_duration: float) -> bool:
	entry.refresh_power_up(effect_duration)
	_cancel_cleanup()
	if _power_up_entries.has(entry):
		_power_up_entries.erase(entry)
		_layout_power_up_entries(true)
		_entries.push_front(entry)
		entry.scale = Vector2.ONE
		_hold_remaining = max(hold_duration, 0.0)
		set_process(true)
		_layout_entries(true, entry)
		return true
	_hold_remaining = max(hold_duration, 0.0)
	set_process(true)
	return true


func _layout_entries(animate: bool, incoming_entry: HUDItemNotificationEntry = null) -> void:
	_kill_tween(_layout_tween)
	_layout_tween = null
	var targets: Array[Vector2] = _calculate_entry_targets()
	if targets.size() != _entries.size():
		return
	if incoming_entry != null:
		var incoming_index: int = _entries.find(incoming_entry)
		if incoming_index >= 0:
			incoming_entry.position = Vector2(-entry_size.x - sweep_start_margin, targets[incoming_index].y)
	if not animate:
		for index: int in range(_entries.size()):
			_entries[index].position = targets[index]
		return
	_layout_tween = create_tween()
	_layout_tween.set_parallel(true)
	_layout_tween.set_trans(Tween.TRANS_QUAD)
	_layout_tween.set_ease(Tween.EASE_OUT)
	for index: int in range(_entries.size()):
		var entry: HUDItemNotificationEntry = _entries[index]
		var duration: float = sweep_duration if entry == incoming_entry else reflow_duration
		if duration <= 0.0:
			entry.position = targets[index]
			continue
		_layout_tween.tween_property(entry, "position", targets[index], duration)


func _calculate_entry_targets() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	var entry_count: int = _entries.size()
	if entry_count <= 0:
		return targets
	var available_width: float = max(size.x - horizontal_margin * 2.0, entry_size.x)
	var center_step: float = entry_size.x + entry_spacing
	if entry_count > 1:
		var fitting_step: float = max((available_width - entry_size.x) / float(entry_count - 1), 0.0)
		center_step = min(center_step, fitting_step)
	var group_width: float = entry_size.x + center_step * float(entry_count - 1)
	var start_x: float = (size.x - group_width) * 0.5
	var target_y: float = size.y * vertical_position_ratio - entry_size.y * 0.5
	target_y = clamp(target_y, 0.0, max(size.y - entry_size.y, 0.0))
	for index: int in range(entry_count):
		targets.append(Vector2(start_x + center_step * float(index), target_y))
	return targets


func _begin_cleanup() -> void:
	set_process(false)
	_settle_power_up_entries()
	if _entries.is_empty():
		_finish_transient_cycle()
		return
	_shrinking = true
	_kill_tween(_restore_tween)
	_restore_tween = null
	var duration: float = max(shrink_duration, 0.0)
	if duration <= 0.0:
		_clear_entries()
		return
	_cleanup_tween = create_tween()
	_cleanup_tween.set_parallel(true)
	_cleanup_tween.set_trans(Tween.TRANS_QUAD)
	_cleanup_tween.set_ease(Tween.EASE_IN)
	for entry: HUDItemNotificationEntry in _entries:
		if entry != null and is_instance_valid(entry):
			_cleanup_tween.tween_property(entry, "scale", Vector2.ZERO, duration)
	_cleanup_tween.chain().tween_callback(_clear_entries)


func _settle_power_up_entries() -> void:
	var moved_entries: Array[HUDItemNotificationEntry] = []
	var transient_entries: Array[HUDItemNotificationEntry] = []
	for entry: HUDItemNotificationEntry in _entries:
		if entry != null and is_instance_valid(entry) and entry.is_power_up:
			moved_entries.append(entry)
		else:
			transient_entries.append(entry)
	_entries = transient_entries
	for index: int in range(moved_entries.size() - 1, -1, -1):
		_power_up_entries.push_front(moved_entries[index])
	if not moved_entries.is_empty():
		_layout_entries(true)
		_layout_power_up_entries(true, moved_entries)


func _layout_power_up_entries(
	animate: bool,
	settling_entries: Array[HUDItemNotificationEntry] = []
	) -> void:
	_kill_tween(_power_up_layout_tween)
	_power_up_layout_tween = null
	_update_power_up_bar(animate)
	if _power_up_entries.is_empty():
		return
	var targets: Array[Vector2] = _calculate_power_up_targets()
	var target_scale: Vector2 = Vector2.ONE * max(power_up_scale, 0.1)
	if not animate:
		for index: int in range(_power_up_entries.size()):
			_power_up_entries[index].position = targets[index]
			_power_up_entries[index].scale = target_scale
		return
	_power_up_layout_tween = create_tween()
	_power_up_layout_tween.set_parallel(true)
	_power_up_layout_tween.set_trans(Tween.TRANS_QUAD)
	_power_up_layout_tween.set_ease(Tween.EASE_OUT)
	for index: int in range(_power_up_entries.size()):
		var entry: HUDItemNotificationEntry = _power_up_entries[index]
		var duration: float = power_up_settle_duration if settling_entries.has(entry) else reflow_duration
		if duration <= 0.0:
			entry.position = targets[index]
			entry.scale = target_scale
			continue
		_power_up_layout_tween.tween_property(entry, "position", targets[index], duration)
		_power_up_layout_tween.tween_property(entry, "scale", target_scale, duration)


func _calculate_power_up_targets() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	var queue_scale: float = max(power_up_scale, 0.1)
	var visual_size: Vector2 = entry_size * queue_scale
	var scale_offset: Vector2 = (entry_size - visual_size) * 0.5
	var vertical_padding: float = max(power_up_bar_padding.y, 0.0)
	for index: int in range(_power_up_entries.size()):
		var visual_right: float = size.x - _get_power_up_right_margin() \
			- float(index) * (visual_size.x + power_up_spacing)
		var visual_top: float = size.y - power_up_bottom_margin
		visual_top -= vertical_padding + visual_size.y
		var visual_position: Vector2 = Vector2(visual_right - visual_size.x, visual_top)
		targets.append(visual_position - scale_offset)
	return targets


func _cancel_cleanup() -> void:
	var restore_required: bool = _shrinking
	_kill_tween(_cleanup_tween)
	_cleanup_tween = null
	_shrinking = false
	if not restore_required:
		return
	_kill_tween(_restore_tween)
	_restore_tween = null
	var duration: float = max(restore_duration, 0.0)
	if duration <= 0.0:
		for entry: HUDItemNotificationEntry in _entries:
			if entry != null and is_instance_valid(entry):
				entry.scale = Vector2.ONE
		return
	_restore_tween = create_tween()
	_restore_tween.set_parallel(true)
	_restore_tween.set_trans(Tween.TRANS_QUAD)
	_restore_tween.set_ease(Tween.EASE_OUT)
	for entry: HUDItemNotificationEntry in _entries:
		if entry != null and is_instance_valid(entry):
			_restore_tween.tween_property(entry, "scale", Vector2.ONE, duration)


func _clear_entries() -> void:
	_kill_tween(_layout_tween)
	_layout_tween = null
	_kill_tween(_restore_tween)
	_restore_tween = null
	for entry: HUDItemNotificationEntry in _entries:
		if entry != null and is_instance_valid(entry):
			entry.queue_free()
	_entries.clear()
	_finish_transient_cycle()


func _finish_transient_cycle() -> void:
	_hold_remaining = 0.0
	_shrinking = false
	_cleanup_tween = null
	set_process(false)


func _on_power_up_expired(entry: HUDItemNotificationEntry) -> void:
	if entry == null or not is_instance_valid(entry):
		return
	var was_transient: bool = _entries.has(entry)
	_entries.erase(entry)
	_power_up_entries.erase(entry)
	_begin_power_up_discard(entry)
	if was_transient:
		if _entries.is_empty():
			_finish_transient_cycle()
		else:
			_layout_entries(true)
	_layout_power_up_entries(true)


func _begin_power_up_discard(entry: HUDItemNotificationEntry) -> void:
	_discarding_entries.append(entry)
	var duration: float = max(shrink_duration, 0.0)
	if duration <= 0.0:
		_finish_power_up_discard(entry)
		return
	var discard_tween: Tween = create_tween()
	discard_tween.set_trans(Tween.TRANS_QUAD)
	discard_tween.set_ease(Tween.EASE_IN)
	discard_tween.tween_property(entry, "scale", Vector2.ZERO, duration)
	discard_tween.tween_callback(_finish_power_up_discard.bind(entry))


func _finish_power_up_discard(entry: HUDItemNotificationEntry) -> void:
	_discarding_entries.erase(entry)
	if entry != null and is_instance_valid(entry):
		entry.queue_free()


func clear_all_notifications() -> void:
	_kill_tween(_layout_tween)
	_kill_tween(_cleanup_tween)
	_kill_tween(_restore_tween)
	_kill_tween(_power_up_layout_tween)
	_kill_tween(_power_up_bar_tween)
	_layout_tween = null
	_cleanup_tween = null
	_restore_tween = null
	_power_up_layout_tween = null
	_power_up_bar_tween = null
	var entries_to_clear: Array[HUDItemNotificationEntry] = []
	entries_to_clear.append_array(_entries)
	entries_to_clear.append_array(_power_up_entries)
	entries_to_clear.append_array(_discarding_entries)
	for entry: HUDItemNotificationEntry in entries_to_clear:
		if entry != null and is_instance_valid(entry):
			entry.queue_free()
	_entries.clear()
	_power_up_entries.clear()
	_discarding_entries.clear()
	_update_power_up_bar(false)
	_finish_transient_cycle()


func set_hud_colors(primary_color: Color, _secondary_color: Color) -> void:
	_primary_color = primary_color
	if _power_up_bar_style != null:
		_power_up_bar_style.border_color = _primary_color


func _on_resized() -> void:
	if not _entries.is_empty():
		_layout_entries(false)
	if not _power_up_entries.is_empty():
		_layout_power_up_entries(false)
	else:
		_update_power_up_bar(false)


func _prepare_power_up_bar_style() -> void:
	if _power_up_bar == null:
		return
	var configured_style: StyleBox = _power_up_bar.get_theme_stylebox("panel")
	if configured_style is StyleBoxFlat:
		_power_up_bar_style = configured_style.duplicate() as StyleBoxFlat
		_power_up_bar.add_theme_stylebox_override("panel", _power_up_bar_style)
		_power_up_bar_style.border_color = _primary_color


func _update_power_up_bar(animate: bool) -> void:
	if _power_up_bar == null:
		return
	_kill_tween(_power_up_bar_tween)
	_power_up_bar_tween = null
	if _power_up_entries.is_empty():
		_collapse_power_up_bar(animate)
		return
	var target_rect: Rect2 = _calculate_power_up_bar_rect()
	if not _power_up_bar_expanded:
		_expand_power_up_bar(target_rect, animate)
		return
	_power_up_bar.visible = true
	if not animate or power_up_bar_resize_duration <= 0.0:
		_apply_power_up_bar_rect(target_rect)
		_power_up_bar.scale = Vector2.ONE
		_power_up_bar.modulate.a = 1.0
		return
	_power_up_bar_tween = create_tween()
	_power_up_bar_tween.set_parallel(true)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"position",
		target_rect.position,
		power_up_bar_resize_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"size",
		target_rect.size,
		power_up_bar_resize_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"scale",
		Vector2.ONE,
		power_up_bar_resize_duration
	)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"modulate:a",
		1.0,
		power_up_bar_resize_duration
	)
	_power_up_bar_tween.set_parallel(false)
	_power_up_bar_tween.tween_callback(_update_power_up_bar_pivot)


func _calculate_power_up_bar_rect() -> Rect2:
	var queue_scale: float = max(power_up_scale, 0.1)
	var visual_size: Vector2 = entry_size * queue_scale
	var entry_count: int = _power_up_entries.size()
	var group_width: float = visual_size.x * float(entry_count)
	group_width += max(power_up_spacing, 0.0) * float(max(entry_count - 1, 0))
	var safe_padding: Vector2 = Vector2(
		max(power_up_bar_padding.x, 0.0),
		max(power_up_bar_padding.y, 0.0)
	)
	var bar_size: Vector2 = Vector2(
		group_width + safe_padding.x * 2.0,
		visual_size.y + safe_padding.y * 2.0
	)
	var bar_right: float = size.x - _get_power_up_right_margin()
	bar_right += max(power_up_bar_connector_overlap, 0.0)
	var bar_bottom: float = size.y - power_up_bottom_margin
	return Rect2(
		Vector2(bar_right - bar_size.x, bar_bottom - bar_size.y),
		bar_size
	)


func _get_power_up_right_margin() -> float:
	if _speedometer:
		return size.x - _speedometer.position.x + power_up_speedometer_gap
	return power_up_right_margin


func _expand_power_up_bar(target_rect: Rect2, animate: bool) -> void:
	_power_up_bar_expanded = true
	_power_up_bar.visible = true
	_apply_power_up_bar_rect(target_rect)
	if not animate or power_up_bar_expand_duration <= 0.0:
		_power_up_bar.scale = Vector2.ONE
		_power_up_bar.modulate.a = 1.0
		return
	_power_up_bar.scale = Vector2(0.0, 0.84)
	_power_up_bar.modulate.a = 0.0
	_power_up_bar_tween = create_tween()
	_power_up_bar_tween.set_parallel(true)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"scale",
		Vector2.ONE,
		power_up_bar_expand_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"modulate:a",
		1.0,
		power_up_bar_expand_duration * 0.75
	)


func _collapse_power_up_bar(animate: bool) -> void:
	if not _power_up_bar_expanded:
		_power_up_bar.visible = false
		_power_up_bar.scale = Vector2.ZERO
		_power_up_bar.modulate.a = 0.0
		return
	_power_up_bar_expanded = false
	_update_power_up_bar_pivot()
	if not animate or power_up_bar_collapse_duration <= 0.0:
		_finish_power_up_bar_collapse()
		return
	_power_up_bar_tween = create_tween()
	_power_up_bar_tween.set_parallel(true)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"scale",
		Vector2(0.0, 0.84),
		power_up_bar_collapse_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_power_up_bar_tween.tween_property(
		_power_up_bar,
		"modulate:a",
		0.0,
		power_up_bar_collapse_duration * 0.8
	)
	_power_up_bar_tween.set_parallel(false)
	_power_up_bar_tween.tween_callback(_finish_power_up_bar_collapse)


func _finish_power_up_bar_collapse() -> void:
	_power_up_bar.visible = false
	_power_up_bar.scale = Vector2.ZERO
	_power_up_bar.modulate.a = 0.0


func _apply_power_up_bar_rect(target_rect: Rect2) -> void:
	_power_up_bar.position = target_rect.position
	_power_up_bar.size = target_rect.size
	_update_power_up_bar_pivot()


func _update_power_up_bar_pivot() -> void:
	if _power_up_bar != null:
		_power_up_bar.pivot_offset = Vector2(
			_power_up_bar.size.x,
			_power_up_bar.size.y * 0.5
		)


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()

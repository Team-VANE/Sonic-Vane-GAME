extends RefCounted
class_name MenuSelectList

const MAIN_CATEGORY: String = "Main"


static func populate(
		list: VBoxContainer,
		entries: Array,
		selected_id: String,
		pressed_callback: Callable,
		button_group: StringName = &"MenuButtons",
		right_pressed_callback: Callable = Callable(),
		secondary_selected_id: String = "",
		secondary_label: String = "Buddy",
		settings_callback: Callable = Callable(),
		settings_icon: Texture2D = null
	) -> int:
	if list == null:
		return 0
	clear(list)
	var added: int = 0
	var normalized_selected: String = selected_id.strip_edges()
	var normalized_secondary: String = secondary_selected_id.strip_edges()
	var category_groups: Array[Dictionary] = _group_entries_by_category(entries)
	for category_group: Dictionary in category_groups:
		_add_category_header(list, String(category_group.get("label", MAIN_CATEGORY)))
		var category_entries: Array = category_group.get("entries", [])
		for entry_value: Variant in category_entries:
			var entry_dict: Dictionary = entry_value
			var label: String = String(entry_dict["name"])
			var entry_id: String = String(entry_dict.get("id", "")).strip_edges()
			if entry_id != "" and normalized_selected != "" and entry_id.nocasecmp_to(normalized_selected) == 0:
				label += " (Selected)"
			if entry_id != "" and normalized_secondary != "" and entry_id.nocasecmp_to(normalized_secondary) == 0:
				label += " (%s)" % secondary_label
			var row: HBoxContainer = HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var btn: Button = Button.new()
			btn.text = label
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if button_group != &"":
				btn.add_to_group(String(button_group))
			btn.pressed.connect(func():
				pressed_callback.call(entry_dict)
			)
			if right_pressed_callback.is_valid():
				btn.gui_input.connect(func(event: InputEvent):
					if event is InputEventMouseButton:
						var mouse_event: InputEventMouseButton = event as InputEventMouseButton
						if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
							right_pressed_callback.call(entry_dict)
							btn.accept_event()
				)
			row.add_child(btn)
			if settings_callback.is_valid():
				var settings_button: Button = Button.new()
				settings_button.custom_minimum_size = Vector2(52.0, 52.0)
				settings_button.icon = settings_icon
				settings_button.expand_icon = true
				settings_button.tooltip_text = "Open settings for %s." % String(entry_dict.get("name", "this character"))
				if button_group != &"":
					settings_button.add_to_group(String(button_group))
				settings_button.pressed.connect(func():
					settings_callback.call(entry_dict)
				)
				row.add_child(settings_button)
			list.add_child(row)
			added += 1
	return added


static func _group_entries_by_category(entries: Array) -> Array[Dictionary]:
	var entries_by_category: Dictionary = {}
	var category_labels: Dictionary = {}
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if not entry.has("name") or bool(entry.get("hidden_from_character_select", false)):
			continue
		var category_label: String = _normalize_category_label(entry.get("selection_category", MAIN_CATEGORY))
		var category_key: String = category_label.to_lower()
		if not entries_by_category.has(category_key):
			entries_by_category[category_key] = []
			category_labels[category_key] = category_label
		var category_entries: Array = entries_by_category[category_key]
		category_entries.append(entry)
		entries_by_category[category_key] = category_entries

	var category_keys: Array[String] = []
	for key_value: Variant in entries_by_category.keys():
		category_keys.append(String(key_value))
	category_keys.sort_custom(Callable(MenuSelectList, "_compare_category_keys"))

	var result: Array[Dictionary] = []
	for category_key: String in category_keys:
		result.append({
			"label": String(category_labels.get(category_key, MAIN_CATEGORY)),
			"entries": entries_by_category.get(category_key, []),
		})
	return result


static func _normalize_category_label(value: Variant) -> String:
	var label: String = String(value).strip_edges()
	if label.is_empty() or label.nocasecmp_to(MAIN_CATEGORY) == 0:
		return MAIN_CATEGORY
	return label


static func _compare_category_keys(first: String, second: String) -> bool:
	var main_key: String = MAIN_CATEGORY.to_lower()
	if first == main_key:
		return second != main_key
	if second == main_key:
		return false
	return first.nocasecmp_to(second) < 0


static func _add_category_header(list: VBoxContainer, category_label: String) -> void:
	var header: Label = Label.new()
	header.text = category_label
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 22)
	list.add_child(header)


static func clear(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()

@tool
class_name LMWelcomeWindow extends Window

signal dont_show_changed(disabled: bool)

var _checkbox: CheckBox

func _init() -> void:
	title = "Welcome to Liminal Editor"
	transient = true
	unresizable = false
	min_size = Vector2i(600, 500)

func _ready() -> void:
	close_requested.connect(_on_close)
	_build_ui()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var rich_text := RichTextLabel.new()
	rich_text.bbcode_enabled = true
	rich_text.fit_content = false
	rich_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rich_text.scroll_active = true
	rich_text.text = _welcome_text()
	rich_text.meta_clicked.connect(_on_link_clicked)
	vbox.add_child(rich_text)

	vbox.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	vbox.add_child(footer)

	_checkbox = CheckBox.new()
	_checkbox.text = "Don't show again"
	_checkbox.toggled.connect(_on_checkbox_toggled)
	footer.add_child(_checkbox)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(80, 0)
	close_btn.pressed.connect(_on_close)
	footer.add_child(close_btn)

func set_welcome_disabled(value: bool) -> void:
	if _checkbox:
		_checkbox.set_pressed_no_signal(value)

func _welcome_text() -> String:
	return """[b]Thank you for downloading Liminal Editor![/b]

We're glad you're here. Liminal Editor bridges [b]Blender[/b] and [b]Godot[/b] - designers author levels in Blender, and this addon imports them into Godot automatically.

[b]This is a Godot integration addon.[/b] To author levels you also need the companion [b]Blender addon[/b], which handles entity placement, level export, and more.

[b]Get the Blender Addon[/b]

The Liminal Editor Blender addon is available for purchase at:
[url=https://liminal.lv][color=#4a9eff]https://liminal.lv[/color][/url]

[b]Already have the Blender addon?[/b]

The quickstart guide and full documentation are at:
[url=https://liminal.lv/docs/user/quickstart.html][color=#4a9eff]https://liminal.lv/docs/user/quickstart.html[/color][/url]"""

func _on_checkbox_toggled(toggled_on: bool) -> void:
	dont_show_changed.emit(toggled_on)

func _on_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

func _on_close() -> void:
	hide()
	queue_free()

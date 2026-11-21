@tool
extends Control

const Preview = preload("res://addons/ls5_cutscenes/editor/cutscene_preview.gd")
const Catalog = preload("res://LS5Framework/Scripts/World/CharacterCatalog.gd")
const FRAME_TIME: float = 1.0 / 30.0

var _level_id: int = 0
var _director_path: NodePath
var _directors: Array[Node] = []
var _characters: Array[Dictionary] = []
var _preview: Preview
var _time: float = 0.0
var _playing: bool = false
var _scene_name: Label
var _cutscene_menu: OptionButton
var _character_menu: OptionButton
var _edit: Button
var _frame: PanelContainer
var _message: Label
var _cue_panel: VBoxContainer
var _cues: ItemList
var _play: Button
var _audio: CheckButton
var _volume_slider: HSlider
var _volume_value: Label
var _expand: CheckButton
var _timecode: Label
var _playhead: HSlider
var _transport: Array[BaseButton] = []


func _ready() -> void:
	_build_layout()
	set_process(false)
	set_process_input(false)
	visibility_changed.connect(refresh_level)


func refresh_level() -> void:
	if not is_inside_tree():
		return
	_release_preview()
	_directors.clear()
	_cues.clear()
	_cutscene_menu.clear()
	_edit.disabled = true
	set_process_input(is_visible_in_tree())
	if not is_visible_in_tree():
		return
	var level: Node = EditorInterface.get_edited_scene_root()
	if not level:
		_scene_name.text = ""
		_message.text = "Open a level or cutscene scene."
		_set_transport_enabled(false)
		return
	if level.get_instance_id() != _level_id:
		_level_id = level.get_instance_id()
		_director_path = NodePath("")
		_time = 0.0
	_scene_name.text = String(level.name)
	var selected: int = 0
	for director: Node in level.get_tree().get_nodes_in_group(&"cutscene_director"):
		if director != level and not level.is_ancestor_of(director):
			continue
		var path: NodePath = level.get_path_to(director)
		if path == _director_path:
			selected = _directors.size()
		_directors.append(director)
		_cutscene_menu.add_item(String(director.name))
		_cutscene_menu.set_item_tooltip(_directors.size() - 1, String(path))
	_cutscene_menu.disabled = _directors.size() <= 1
	if _directors.is_empty():
		_set_transport_enabled(false)
		_message.text = "No cutscenes in this scene."
		return
	_load_characters()
	_cutscene_menu.select(selected)
	_rebuild_preview()


func _load_characters() -> void:
	if not _characters.is_empty():
		return
	_characters.append({})
	_character_menu.add_item("No player")
	var selected: int = 0
	for entry: Dictionary in Catalog.load_character_entries("res://LS5Framework/Characters"):
		if entry.get("hidden_from_character_select", false):
			continue
		if not ResourceLoader.exists(entry.scene):
			continue
		_characters.append({"id": entry.id, "name": entry.name, "scene": entry.scene})
		_character_menu.add_item(entry.name)
		if entry.id == Catalog.DEFAULT_CHARACTER_ID or selected == 0:
			selected = _characters.size() - 1
	_character_menu.select(selected)
	_character_menu.disabled = _characters.size() <= 1


func _rebuild_preview() -> void:
	_release_preview()
	_cues.clear()
	_set_transport_enabled(false)
	var level: Node = EditorInterface.get_edited_scene_root()
	var director: Node = _selected_director()
	if not level or not director:
		return
	var path: NodePath = level.get_path_to(director)
	if _director_path != path:
		_director_path = path
		_time = 0.0
	_edit.disabled = not is_instance_valid(director.get("timeline"))
	_preview = Preview.new()
	_frame.add_child(_preview)
	var problem: String = _preview.setup(level, director, _characters[_character_menu.selected])
	if not problem.is_empty():
		_release_preview()
		_message.text = problem
		return
	_message.hide()
	_preview.set_preview_volume(_volume_slider.value)
	for row: Dictionary in _preview.rows:
		_cues.add_item(row.caption)
		var index: int = _cues.item_count - 1
		_cues.set_item_metadata(index, row.time)
		_cues.set_item_selectable(index, row.time >= 0.0)
	_playhead.max_value = _preview.duration
	_set_transport_enabled(true)
	_seek(_time)


func _selected_director() -> Node:
	var index: int = _cutscene_menu.selected
	if index < 0 or index >= _directors.size() or not is_instance_valid(_directors[index]):
		return null
	return _directors[index]


func _release_preview() -> void:
	_set_playing(false)
	if _preview:
		_preview.silence()
		_preview.free()
		_preview = null
	_message.show()


func _set_transport_enabled(enabled: bool) -> void:
	for button: BaseButton in _transport:
		button.disabled = not enabled
	_playhead.editable = enabled
	_volume_slider.editable = enabled
	if not enabled:
		_timecode.text = "0.00 / 0.00 s"
		_playhead.set_value_no_signal(0.0)


func _edit_timeline() -> void:
	var director: Node = _selected_director()
	if director:
		var timeline: AnimationPlayer = director.get("timeline") as AnimationPlayer
		if timeline:
			EditorInterface.set_main_screen_editor("3D")
			EditorInterface.edit_node(timeline)


func _process(delta: float) -> void:
	if _time + delta >= _preview.duration:
		_seek(_preview.duration)
	else:
		_sample(_time + delta)


func _seek(time: float) -> void:
	_set_playing(false)
	_sample(time)


func _sample(time: float) -> void:
	if not _preview:
		return
	_time = clampf(time, 0.0, _preview.duration)
	_playhead.set_value_no_signal(_time)
	_timecode.text = "%.2f / %.2f s" % [_time, _preview.duration]
	_preview.seek(_time, _playing and _audio.button_pressed)


func _toggle_playback() -> void:
	if not _preview:
		return
	if _playing:
		_set_playing(false)
		return
	_set_playing(true)
	_sample(0.0 if _time >= _preview.duration else _time)


func _set_playing(playing: bool) -> void:
	_playing = playing
	_play.text = "Pause" if playing else "Play"
	set_process(playing)
	if not playing and _preview:
		_preview.silence()


func _on_preview_volume_changed(value: float) -> void:
	_volume_value.text = "%d%%" % int(value)
	if _preview:
		_preview.set_preview_volume(value)


func _input(event: InputEvent) -> void:
	if not _preview or not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus and not is_ancestor_of(focus):
		return
	match event.keycode:
		KEY_SPACE:
			if not event.echo:
				_toggle_playback()
		KEY_LEFT, KEY_RIGHT:
			if focus != _playhead:
				return
			_seek(_time + FRAME_TIME * (-1.0 if event.keycode == KEY_LEFT else 1.0))
		KEY_ESCAPE:
			if not _expand.button_pressed:
				return
			_expand.button_pressed = false
		_:
			return
	get_viewport().set_input_as_handled()


func _build_layout() -> void:
	var margins: MarginContainer = MarginContainer.new()
	add_child(margins)
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["top", "right", "bottom", "left"]:
		margins.add_theme_constant_override("margin_" + side, 8)
	var layout: VBoxContainer = VBoxContainer.new()
	margins.add_child(layout)
	var toolbar: HFlowContainer = HFlowContainer.new()
	layout.add_child(toolbar)
	_scene_name = Label.new()
	toolbar.add_child(_scene_name)
	_cutscene_menu = _make_picker(toolbar, "Cutscene in the edited scene.")
	_cutscene_menu.item_selected.connect(func(_index: int) -> void: _rebuild_preview())
	_character_menu = _make_picker(toolbar, "Character to bind to the player role.")
	_character_menu.item_selected.connect(func(_index: int) -> void: _rebuild_preview())
	_button(toolbar, "Refresh", refresh_level, "Rebuild from the current editor scene, including unsaved changes.")
	_edit = _button(toolbar, "Edit Animation", _edit_timeline, "Open the native Animation panel.")
	_expand = CheckButton.new()
	_expand.text = "Expand Preview"
	toolbar.add_child(_expand)
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(split)
	_frame = PanelContainer.new()
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_stretch_ratio = 3.0
	_frame.custom_minimum_size = Vector2(160.0, 100.0)
	split.add_child(_frame)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_frame.add_child(_message)
	_cue_panel = VBoxContainer.new()
	_cue_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cue_panel.custom_minimum_size.x = 200.0
	split.add_child(_cue_panel)
	_expand.toggled.connect(func(expanded: bool) -> void: _cue_panel.visible = not expanded and split.size.x >= 510.0)
	split.resized.connect(func() -> void: _cue_panel.visible = not _expand.button_pressed and split.size.x >= 510.0)
	var label: Label = Label.new()
	label.text = "Cast and cues"
	_cue_panel.add_child(label)
	_cues = ItemList.new()
	_cues.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cues.item_selected.connect(func(index: int) -> void: _seek(float(_cues.get_item_metadata(index))))
	_cue_panel.add_child(_cues)
	_build_transport(layout)


func _build_transport(layout: VBoxContainer) -> void:
	_playhead = HSlider.new()
	_playhead.step = 0.0
	_playhead.value_changed.connect(_seek)
	layout.add_child(_playhead)
	var controls: HFlowContainer = HFlowContainer.new()
	layout.add_child(controls)
	_play = _button(controls, "Play", _toggle_playback, "Space toggles playback.")
	_transport.append(_play)
	_transport.append(_button(controls, "Stop", _seek.bind(0.0), "Pause and return to the start."))
	_transport.append(_button(controls, "−1 Frame", func() -> void: _seek(_time - FRAME_TIME), "Step back at 30 fps."))
	_transport.append(_button(controls, "+1 Frame", func() -> void: _seek(_time + FRAME_TIME), "Step forward at 30 fps."))
	_audio = CheckButton.new()
	_audio.text = "Audio"
	_audio.button_pressed = true
	_audio.toggled.connect(func(_enabled: bool) -> void: _sample(_time))
	controls.add_child(_audio)
	_transport.append(_audio)
	var volume: HBoxContainer = HBoxContainer.new()
	controls.add_child(volume)
	var volume_label: Label = Label.new()
	volume_label.text = "Volume"
	volume.add_child(volume_label)
	_volume_slider = HSlider.new()
	_volume_slider.custom_minimum_size.x = 120.0
	_volume_slider.max_value = 100.0
	_volume_slider.step = 1.0
	_volume_slider.value = 100.0
	_volume_slider.tooltip_text = "Cutscene preview audio volume."
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume.add_child(_volume_slider)
	_volume_value = Label.new()
	_volume_value.text = "100%"
	_volume_value.custom_minimum_size.x = _volume_value.get_minimum_size().x
	volume.add_child(_volume_value)
	_volume_slider.value_changed.connect(_on_preview_volume_changed)
	_timecode = Label.new()
	_timecode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timecode.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.add_child(_timecode)


func _make_picker(parent: Container, tooltip: String) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.custom_minimum_size.x = 150.0
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = tooltip
	parent.add_child(picker)
	return picker


func _button(parent: Container, caption: String, callback: Callable, tooltip: String) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

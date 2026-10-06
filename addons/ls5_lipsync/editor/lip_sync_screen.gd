@tool
extends Control

const DRAFT_SCRIPT: Script = preload("res://addons/ls5_lipsync/editor/lip_sync_draft.gd")
const WAVEFORM_SCRIPT: Script = preload("res://addons/ls5_lipsync/editor/lip_sync_waveform.gd")
const TIMELINE_SCRIPT: Script = preload("res://addons/ls5_lipsync/editor/lip_sync_timeline.gd")
const DRIVER_SCRIPT: Script = preload("res://addons/ls5_lipsync/runtime/lip_sync_driver.gd")
const NEW_CLIP_SMOOTHING_TIME: float = 0.01

var _profile: LipSyncProfile
var _clip: LipSyncClip
var _profile_picker: EditorResourcePicker
var _transfer_picker: EditorResourcePicker
var _cue_source_picker: EditorResourcePicker
var _cue_source_menu: OptionButton
var _transfer_context: Label
var _copy_visemes: CheckBox
var _copy_expressions: CheckBox
var _copy_defaults: CheckBox
var _fit_transfer_timing: CheckBox
var _clip_picker: EditorResourcePicker
var _clip_menu: OptionButton
var _audio_picker: EditorResourcePicker
var _viseme_list: ItemList
var _expression_list: ItemList
var _creation_fields: Dictionary = {}
var _curve_fields: Dictionary = {}
var _cue_curve_menu: OptionButton
var _cue_blend_lock: CheckBox
var _expression_mix_menu: OptionButton
var _application_mode_menu: OptionButton
var _influence_duration_field: SpinBox
var _timeline: LipSyncTimeline
## Independent scrolling area for the timeline and editing categories.
var _center_scroll: ScrollContainer
var _transcript: TextEdit
var _status: Label
var _clip_context: Label
var _clip_edit_buttons: Array[Button] = []
var _saved_state: Dictionary = {}
var _pending_new_after_save: bool = false
var _fields: Dictionary = {}
var _cue_row_menu: OptionButton
var _editing_fields: bool = false
var _selected_cue: LipSyncCue
var _selected_expression: bool = false
var _selection_summary: Label
var _drag_redo_backup: Array[Dictionary] = []
var _drag_undo_backup: Array[Dictionary] = []
var _player: AudioStreamPlayer
var _audition_scrub: CheckButton
var _loop_playback: CheckButton
var _from_cursor: CheckButton
var _preview_volume_slider: HSlider
var _preview_volume_value: Label
var _transport_playing: bool = false
var _transport_time: float = 0.0
var _scrub_end_tick: int = -1
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _pre_draft_state: Dictionary = {}
var _restoring_history: bool = false
var _viewport: SubViewport
## Isolated model preview and camera input surface.
var _preview_container: SubViewportContainer
var _foldout_headers: Dictionary = {}
var _foldout_bodies: Dictionary = {}
var _preview_root: Node3D
var _preview_needs_rebuild: bool = false
var _preview_driver: LipSyncDriver
var _camera: Camera3D
var _camera_target: Vector3 = Vector3(0.0, 1.4, 0.0)
var _camera_distance: float = 2.2
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0
var _preview_dragging: bool = false
var _save_dialog: EditorFileDialog
var _save_action: String = ""
var _draft_dialog: ConfirmationDialog
var _new_clip_dialog: ConfirmationDialog
var _open_clip_dialog: ConfirmationDialog
var _pending_open_clip: LipSyncClip


func _ready() -> void:
	set_process(true)
	_build_ui()
	visibility_changed.connect(_update_preview_rendering)
	_update_preview_rendering()
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_audio_finished)
	_on_preview_volume_changed(_preview_volume_slider.value)
	var default_profile: LipSyncProfile = load("res://LS5Framework/Characters/Sonic Neo Adventure/SonicNeoLipSyncProfile.tres") as LipSyncProfile
	if default_profile:
		_profile_picker.edited_resource = default_profile
		_set_profile(default_profile)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _clip or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if key.keycode not in [KEY_SPACE, KEY_B] or key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is TextEdit or focus is LineEdit or (focus and focus.get_window() != get_window()):
		return
	if (_save_dialog and _save_dialog.visible) or (_draft_dialog and _draft_dialog.visible) or (_new_clip_dialog and _new_clip_dialog.visible) or (_open_clip_dialog and _open_clip_dialog.visible):
		return
	if key.keycode == KEY_B:
		if _timeline.selected_cues.is_empty() or not _timeline._drag_mode.is_empty():
			return
		get_viewport().set_input_as_handled()
		if key.pressed and not key.echo:
			_timeline.toggle_selected_blend_lock()
		return
	get_viewport().set_input_as_handled()
	if key.pressed and not key.echo:
		if _transport_playing:
			_stop_audio()
		else:
			_play_timeline()


func _update_preview_rendering() -> void:
	var showing: bool = is_visible_in_tree()
	set_process(showing)
	if _timeline:
		_timeline.set_process(showing)
		if not showing:
			_timeline._cancel_drag()
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED
		_viewport.process_mode = Node.PROCESS_MODE_INHERIT if showing else Node.PROCESS_MODE_DISABLED
	if not showing:
		_stop_audio()
		_preview_dragging = false
	elif _preview_needs_rebuild:
		_build_preview()


func _process(delta: float) -> void:
	if _scrub_end_tick >= 0 and Time.get_ticks_msec() >= _scrub_end_tick:
		_player.stop()
		_scrub_end_tick = -1
	if not _transport_playing or not _clip or not _timeline or _timeline.is_scrubbing():
		return
	_transport_time = _player.get_playback_position() if _player.playing else _transport_time + maxf(delta, 0.0)
	if _loop_playback.button_pressed:
		var loop_start: float = _selected_cue.start_time if _selected_cue else _clip.audible_start
		var loop_end: float = _selected_cue.end_time if _selected_cue else _clip.audible_end
		if loop_end > loop_start + 0.02 and _transport_time >= loop_end:
			_seek_transport(loop_start)
			return
	var timeline_end: float = _clip.get_timeline_length() + _clip.smoothing_time * 12.0
	if _transport_time >= timeline_end:
		_transport_time = timeline_end
		_transport_playing = false
	_timeline.set_playhead(_transport_time, false)
	_update_preview(_timeline.playhead, true)


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var toolbar: HFlowContainer = HFlowContainer.new()
	root.add_child(toolbar)
	_toolbar_button(toolbar, "New Clip", _new_clip)
	_clip_edit_buttons.append(_toolbar_button(toolbar, "Save Clip", _save_resources))
	_clip_edit_buttons.append(_toolbar_button(toolbar, "Undo", _undo))
	_clip_edit_buttons.append(_toolbar_button(toolbar, "Redo", _redo))
	_toolbar_button(toolbar, "Validate", _validate)
	_clip_edit_buttons.append(_toolbar_button(toolbar, "Generate Draft", _request_draft))
	_clip_edit_buttons.append(_toolbar_button(toolbar, "Regenerate from Words", _regenerate_from_words))
	_clip_edit_buttons.append(_toolbar_button(toolbar, "Revert Draft", _revert_draft))
	_clip_context = Label.new()
	_clip_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_clip_context)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_status.text = "Create or open a clip to begin editing."

	var profile_bar: HBoxContainer = HBoxContainer.new()
	root.add_child(profile_bar)
	_add_label(profile_bar, "Character profile")
	_profile_picker = _resource_picker(profile_bar, "LipSyncProfile", _on_profile_resource_changed)
	_profile_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit_profile_button: Button = _toolbar_button(profile_bar, "Edit Profile", _edit_profile)
	edit_profile_button.tooltip_text = "Edit this character's pose mappings and bone lists in the Inspector."
	var refresh_profile_button: Button = _toolbar_button(profile_bar, "Refresh Lists", _refresh_profile_lists)
	refresh_profile_button.tooltip_text = "Reload the viseme and expression lists from the selected profile's current pose mappings."
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size.x = 240.0
	split.add_child(left)
	var resource_controls: VBoxContainer = VBoxContainer.new()
	resource_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(resource_controls)
	_add_label(resource_controls, "Clip to edit")
	_clip_menu = OptionButton.new()
	_clip_menu.fit_to_longest_item = false
	_clip_menu.item_selected.connect(_on_clip_menu_selected)
	resource_controls.add_child(_clip_menu)
	var refresh_clip_names: Button = _toolbar_button(resource_controls, "Refresh Clip Names", _refresh_clip_names)
	refresh_clip_names.tooltip_text = "Resolve saved clip references to filenames and refresh this character's clip list."
	_clip_picker = _resource_picker(resource_controls, "LipSyncClip", _on_clip_resource_changed)
	_add_label(resource_controls, "Voice audio for this clip")
	_audio_picker = _resource_picker(resource_controls, "AudioStream", _on_audio_resource_changed)
	var palettes: VSplitContainer = VSplitContainer.new()
	palettes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(palettes)
	var viseme_pane: VBoxContainer = VBoxContainer.new()
	viseme_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palettes.add_child(viseme_pane)
	_add_label(viseme_pane, "Viseme palette")
	_viseme_list = ItemList.new()
	_viseme_list.custom_minimum_size.y = 100.0
	_viseme_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viseme_list.mouse_force_pass_scroll_events = false
	viseme_pane.add_child(_viseme_list)
	_add_palette_buttons(viseme_pane, false)
	var expression_pane: VBoxContainer = VBoxContainer.new()
	expression_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palettes.add_child(expression_pane)
	_add_label(expression_pane, "Expression palette")
	_expression_list = ItemList.new()
	_expression_list.custom_minimum_size.y = 100.0
	_expression_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_expression_list.mouse_force_pass_scroll_events = false
	expression_pane.add_child(_expression_list)
	_add_palette_buttons(expression_pane, true)

	var editor_split: HSplitContainer = HSplitContainer.new()
	editor_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(editor_split)
	var center_panel: VBoxContainer = VBoxContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_stretch_ratio = 2.0
	editor_split.add_child(center_panel)
	var transport: HFlowContainer = HFlowContainer.new()
	center_panel.add_child(transport)
	var play_button: Button = _toolbar_button(transport, "Play", _play_timeline)
	play_button.tooltip_text = "Play the timeline. Space toggles playback outside text fields."
	_from_cursor = CheckButton.new()
	_from_cursor.text = "From Cursor"
	_from_cursor.tooltip_text = "Start playback at the timeline cursor. Uncheck to start at the beginning."
	_from_cursor.button_pressed = false
	transport.add_child(_from_cursor)
	_toolbar_button(transport, "Stop", _stop_audio)
	_add_label(transport, "Volume")
	_preview_volume_slider = HSlider.new()
	_preview_volume_slider.custom_minimum_size.x = 120.0
	_preview_volume_slider.min_value = 0.0
	_preview_volume_slider.max_value = 100.0
	_preview_volume_slider.step = 1.0
	_preview_volume_slider.value = 100.0
	_preview_volume_slider.tooltip_text = "Lip Sync timeline playback and audition volume only."
	_preview_volume_slider.value_changed.connect(_on_preview_volume_changed)
	transport.add_child(_preview_volume_slider)
	_preview_volume_value = _add_label(transport, "100%")
	_toolbar_button(transport, "Fit Timeline", _fit_timeline)
	_toolbar_button(transport, "Refresh Waveform", _refresh_waveform)
	var detect_trim_button: Button = _toolbar_button(transport, "Detect Audible Range", _set_audible_range)
	detect_trim_button.tooltip_text = "Set the yellow trim handles to the detected audible portion of the audio file."
	_clip_edit_buttons.append(detect_trim_button)
	var reset_trim_button: Button = _toolbar_button(transport, "Reset Trim", _reset_audible_trim)
	reset_trim_button.tooltip_text = "Reset the yellow trim handles to the start and end of the audio file."
	_clip_edit_buttons.append(reset_trim_button)
	_toolbar_button(transport, "Zoom +", func() -> void: _zoom_timeline(1.25))
	_toolbar_button(transport, "Zoom −", func() -> void: _zoom_timeline(0.8))
	_loop_playback = CheckButton.new()
	_loop_playback.text = "Loop Cue / Audible Range"
	transport.add_child(_loop_playback)
	_audition_scrub = CheckButton.new()
	_audition_scrub.text = "Audition Scrub"
	_audition_scrub.button_pressed = true
	transport.add_child(_audition_scrub)
	var snap_menu: OptionButton = OptionButton.new()
	snap_menu.tooltip_text = "Timeline timing grid."
	for label: String in ["Snap Off", "Snap 0.01 s", "Snap 0.05 s", "Snap 0.10 s"]:
		snap_menu.add_item(label)
	snap_menu.select(1)
	snap_menu.item_selected.connect(func(index: int) -> void: _timeline.snap_step = [0.0, 0.01, 0.05, 0.1][index])
	transport.add_child(snap_menu)
	_center_scroll = ScrollContainer.new()
	_center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_center_scroll.follow_focus = true
	_center_scroll.mouse_force_pass_scroll_events = false
	center_panel.add_child(_center_scroll)
	var center: VBoxContainer = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_scroll.add_child(center)
	_timeline = TIMELINE_SCRIPT.new() as LipSyncTimeline
	_timeline.mouse_force_pass_scroll_events = false
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(_timeline)
	_timeline.playhead_changed.connect(_on_playhead_changed)
	_timeline.cue_selected.connect(_on_cue_selected)
	_timeline.cue_modified.connect(_on_cue_modified)
	_timeline.add_requested.connect(_add_cue)
	_timeline.delete_requested.connect(_delete_cue)
	_timeline.edit_started.connect(_on_timeline_edit_started)
	_timeline.edit_cancelled.connect(_on_timeline_edit_cancelled)
	_timeline.selection_status.connect(func(message: String) -> void: _status.text = message)
	var transcript_options: VBoxContainer = _add_foldout(center, "Transcript and Word Guidance")
	_transcript = TextEdit.new()
	_transcript.custom_minimum_size.y = 75.0
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transcript.tooltip_text = "Word spans guide editing. Only cue tracks animate the face."
	_transcript.mouse_force_pass_scroll_events = false
	transcript_options.add_child(_transcript)
	_transcript.text_changed.connect(_on_transcript_changed)
	_transcript.focus_entered.connect(_push_undo)
	_build_inspector(center)
	_build_transfer_organiser(center)

	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 280.0
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_split.add_child(right)
	var preview_title: Label = _add_label(right, "Character preview · drag to orbit · wheel to zoom")
	preview_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_container = SubViewportContainer.new()
	_preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_container.stretch = true
	_preview_container.custom_minimum_size.y = 180.0
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.mouse_force_pass_scroll_events = false
	right.add_child(_preview_container)
	_preview_container.gui_input.connect(_on_preview_input)
	_preview_container.mouse_exited.connect(func() -> void: _preview_dragging = false)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(480, 560)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_container.add_child(_viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("29333b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.75
	environment.environment = env
	_viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25.0, -30.0, 0.0)
	light.light_energy = 1.5
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.current = true
	_viewport.add_child(_camera)
	_update_camera()
	var preview_note: Label = _add_label(right, "Preview follows the timeline cursor and uses the runtime pose driver.")
	preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_save_dialog = EditorFileDialog.new()
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.add_filter("*.tres", "Godot resource")
	add_child(_save_dialog)
	_save_dialog.file_selected.connect(_on_save_path_selected)
	_save_dialog.canceled.connect(_on_save_dialog_canceled)
	_draft_dialog = ConfirmationDialog.new()
	_draft_dialog.title = "Generate transcript draft"
	_draft_dialog.dialog_text = "Replace the current viseme cues and word guidance with a transcript-based draft? Expressions remain unchanged."
	add_child(_draft_dialog)
	_draft_dialog.confirmed.connect(_generate_draft)
	_new_clip_dialog = ConfirmationDialog.new()
	_new_clip_dialog.title = "Unsaved clip changes"
	_new_clip_dialog.dialog_text = "Save changes to the current clip before creating another?"
	_new_clip_dialog.ok_button_text = "Save and New"
	_new_clip_dialog.add_button("Discard and New", true, "discard")
	add_child(_new_clip_dialog)
	_new_clip_dialog.confirmed.connect(_save_then_new)
	_new_clip_dialog.custom_action.connect(_on_new_clip_action)
	_open_clip_dialog = ConfirmationDialog.new()
	_open_clip_dialog.title = "Open another lip sync clip"
	_open_clip_dialog.ok_button_text = "Save and Open"
	_open_clip_dialog.add_button("Discard and Open", true, "discard")
	add_child(_open_clip_dialog)
	_open_clip_dialog.confirmed.connect(_save_then_open_clip)
	_open_clip_dialog.custom_action.connect(_on_open_clip_action)
	_open_clip_dialog.canceled.connect(func() -> void: _pending_open_clip = null)
	_update_clip_context()


func _add_palette_buttons(parent: Control, expression: bool) -> void:
	var actions: HFlowContainer = HFlowContainer.new()
	parent.add_child(actions)
	for row: int in range(LipSyncCue.ROW_COUNT):
		var button: Button = _toolbar_button(actions, "Row %d" % (row + 1), _insert_palette_cue.bind(expression, row))
		button.tooltip_text = "Insert the selected pose at the playhead in row %d." % (row + 1)
		_clip_edit_buttons.append(button)
	var replace_button: Button = _toolbar_button(actions, "Replace", func() -> void: _replace_selected_cue(expression))
	replace_button.tooltip_text = "Replace the selected cue with the palette pose when both have the same type."
	_clip_edit_buttons.append(replace_button)


func _insert_palette_cue(expression: bool, row: int) -> void:
	_add_cue(expression, _timeline.playhead, row)


func _build_inspector(parent: VBoxContainer) -> void:
	var cue_options_parent: VBoxContainer = _add_foldout(parent, "Selected Cue")
	var playback_parent: VBoxContainer = _add_foldout(parent, "Clip Playback")
	var playback_options: HFlowContainer = HFlowContainer.new()
	playback_parent.add_child(playback_options)
	_application_mode_menu = OptionButton.new()
	_application_mode_menu.add_item("Additive Overlay")
	_application_mode_menu.add_item("Absolute Override")
	_application_mode_menu.tooltip_text = "Overlay adds facial pose changes to gameplay animation. Absolute Override replaces the character's facial bone poses."
	_application_mode_menu.item_selected.connect(_on_application_mode_selected)
	playback_options.add_child(_application_mode_menu)
	_add_label(playback_options, "Influence Duration")
	_influence_duration_field = SpinBox.new()
	_influence_duration_field.min_value = 0.0
	_influence_duration_field.max_value = 120.0
	_influence_duration_field.step = 0.01
	_influence_duration_field.suffix = "s"
	_influence_duration_field.tooltip_text = "Runtime duration of this clip's facial influence. Zero uses the authored timeline length; other values scale cue timing to this duration."
	_influence_duration_field.value_changed.connect(_on_influence_duration_changed)
	playback_options.add_child(_influence_duration_field)
	var defaults_parent: VBoxContainer = _add_foldout(parent, "Generation and Blending")
	var defaults: HFlowContainer = HFlowContainer.new()
	defaults_parent.add_child(defaults)
	for setting: String in ["generation_padding", "new_blend_in", "new_blend_out", "new_expression_blend_in", "new_expression_blend_out", "smoothing_time"]:
		var column: VBoxContainer = VBoxContainer.new()
		column.custom_minimum_size.x = 100.0
		defaults.add_child(column)
		var captions: Dictionary = {"generation_padding": "Padding", "new_blend_in": "Viseme In", "new_blend_out": "Viseme Out", "new_expression_blend_in": "Expression In", "new_expression_blend_out": "Expression Out", "smoothing_time": "Smoothing (s)"}
		var caption: String = captions[setting]
		_add_label(column, caption)
		var field: SpinBox = SpinBox.new()
		field.min_value = 0.0
		field.max_value = 1.0 if setting == "generation_padding" else 2.0
		field.step = 0.01
		if setting == "smoothing_time":
			field.max_value = 0.25
			field.step = 0.005
		field.editable = false
		field.tooltip_text = "Gap between generated visemes across all four rows. Zero keeps their combined coverage continuous. Use Regenerate from Words to update existing cues." if setting == "generation_padding" else "Default %s duration for new visemes and expressions." % caption.to_lower()
		if setting == "smoothing_time":
			field.tooltip_text = "Overall facial response time in seconds. Zero disables smoothing. Playback uses smoothing; scrubbing resets it."
		column.add_child(field)
		field.value_changed.connect(_on_creation_field_changed.bind(setting))
		_creation_fields[setting] = field
	for setting: String in ["viseme_blend_curve", "expression_blend_curve"]:
		var column: VBoxContainer = VBoxContainer.new()
		defaults.add_child(column)
		_add_label(column, "Viseme Curve" if setting == "viseme_blend_curve" else "Expression Curve")
		var menu: OptionButton = OptionButton.new()
		for caption: String in ["Linear", "Smoothstep", "Sine"]:
			menu.add_item(caption)
		menu.tooltip_text = "Fade curve for cues using Default. Applies to existing and newly created cues."
		menu.item_selected.connect(_on_curve_selected.bind(setting))
		column.add_child(menu)
		_curve_fields[setting] = menu
	var title: Label = _add_label(cue_options_parent, "Timing and strength")
	_cue_blend_lock = _transfer_check(cue_options_parent, "Lock blends to maximum (B)", false, "Keep both blends at half this cue's duration. B toggles all selected cues. Editing either blend disables the lock on that cue.")
	_cue_blend_lock.toggled.connect(func(enabled: bool) -> void:
		if not _editing_fields:
			_timeline.set_selected_blend_lock(enabled, true)
	)
	title.tooltip_text = "Drag blocks and fade edges in the timeline, or edit exact values here."
	_selection_summary = _add_label(cue_options_parent, "No timeline clips selected")
	_selection_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cue_options: HFlowContainer = HFlowContainer.new()
	cue_options_parent.add_child(cue_options)
	_add_label(cue_options, "Cue row")
	_cue_row_menu = OptionButton.new()
	_cue_row_menu.add_item("Row 1")
	_cue_row_menu.add_item("Row 2")
	_cue_row_menu.add_item("Row 3")
	_cue_row_menu.add_item("Row 4")
	_cue_row_menu.item_selected.connect(_on_cue_row_selected)
	cue_options.add_child(_cue_row_menu)
	_add_label(cue_options, "Curve")
	_cue_curve_menu = OptionButton.new()
	for caption: String in ["Default", "Linear", "Smoothstep", "Sine"]:
		_cue_curve_menu.add_item(caption)
	_cue_curve_menu.item_selected.connect(_on_cue_option_selected.bind("blend_curve"))
	cue_options.add_child(_cue_curve_menu)
	_add_label(cue_options, "Expression Overlap")
	_expression_mix_menu = OptionButton.new()
	_expression_mix_menu.add_item("Compound")
	_expression_mix_menu.add_item("Crossfade")
	_expression_mix_menu.tooltip_text = "Compound combines neutral-relative pose offsets across rows. Crossfade shares influence between other Crossfade cues."
	_expression_mix_menu.item_selected.connect(_on_cue_option_selected.bind("expression_mix"))
	cue_options.add_child(_expression_mix_menu)
	var row: HFlowContainer = HFlowContainer.new()
	cue_options_parent.add_child(row)
	for key: String in ["start_time", "end_time", "blend_in", "blend_out", "strength"]:
		var column: VBoxContainer = VBoxContainer.new()
		column.custom_minimum_size.x = 80.0
		row.add_child(column)
		_add_label(column, key.replace("_", " ").capitalize())
		var field: SpinBox = SpinBox.new()
		field.min_value = 0.0
		field.max_value = 120.0 if key != "strength" else 1.0
		field.step = 0.01
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if key == "strength":
			field.tooltip_text = "Cue influence from 0 to 1. Expression offsets compound across rows, or share influence when set to Crossfade."
		column.add_child(field)
		field.value_changed.connect(_on_field_changed.bind(key))
		_fields[key] = field
	var tools: HFlowContainer = HFlowContainer.new()
	cue_options_parent.add_child(tools)
	_clip_edit_buttons.append(_toolbar_button(tools, "Delete Selection", _delete_cue))
	_clip_edit_buttons.append(_toolbar_button(tools, "Hold +0.25 s", func() -> void: _extend_expression(0.25)))
	_clip_edit_buttons.append(_toolbar_button(tools, "Hold +1 s", func() -> void: _extend_expression(1.0)))
	_clip_edit_buttons.append(_toolbar_button(tools, "Hold to Audio End", _hold_to_audio_end))


func _build_transfer_organiser(parent: VBoxContainer) -> void:
	var organiser: VBoxContainer = _add_foldout(parent, "Transfer Organiser")
	_transfer_context = _add_label(organiser, "")
	_transfer_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_label(organiser, "Copy cues into the open clip")
	_add_label(organiser, "Source clip from current character")
	_cue_source_menu = OptionButton.new()
	organiser.add_child(_cue_source_menu)
	_cue_source_menu.item_selected.connect(_on_cue_source_selected)
	_cue_source_picker = _resource_picker(organiser, "LipSyncClip", func(_resource: Resource) -> void: _refresh_cue_source_menu())
	_cue_source_picker.tooltip_text = "Source clip to copy. Choose a registered clip above or load a clip from another character."
	_copy_visemes = _transfer_check(organiser, "Copy visemes", true, "Replace all four viseme rows in the open clip with copies of the source cues.")
	_copy_expressions = _transfer_check(organiser, "Copy expressions", true, "Replace all four expression rows in the open clip with copies of the source cues.")
	_copy_defaults = _transfer_check(organiser, "Copy blending defaults and smoothing", true, "Copy defaults for selected cue types and overall smoothing. Playback mode and duration override stay with the destination.")
	_fit_transfer_timing = _transfer_check(organiser, "Fit timing to destination audible range", false, "Scale cue times and blend durations from the source audible range to the destination audible range. Expressions may still linger past audio.")
	var actions: HFlowContainer = HFlowContainer.new()
	organiser.add_child(actions)
	_clip_edit_buttons.append(_toolbar_button(actions, "Copy into Open Clip", _copy_cues_into_open_clip))
	_toolbar_button(actions, "Refresh Sources", _refresh_cue_source_menu)
	var guidance: Label = _add_label(organiser, "Selected cue types are replaced. Audio, transcript and word guidance stay with the destination. Undo restores the previous setup; Save Clip writes the result.")
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	organiser.add_child(HSeparator.new())
	_add_label(organiser, "Duplicate open clip to another character")
	_transfer_picker = _resource_picker(organiser, "LipSyncProfile", _on_transfer_resource_changed)
	_transfer_picker.tooltip_text = "Character profile assigned to the duplicated clip."
	_clip_edit_buttons.append(_toolbar_button(organiser, "Transfer to Character…", _transfer_clip))


func _transfer_check(parent: Control, title: String, checked: bool, tooltip: String) -> CheckBox:
	var check: CheckBox = CheckBox.new()
	check.text = title
	check.button_pressed = checked
	check.tooltip_text = tooltip
	parent.add_child(check)
	return check


func _refresh_cue_source_menu() -> void:
	if not _cue_source_menu:
		return
	var source: LipSyncClip = _cue_source_picker.edited_resource as LipSyncClip
	_cue_source_menu.clear()
	_cue_source_menu.add_item("Choose source clip…")
	_cue_source_menu.set_item_metadata(0, "")
	_cue_source_menu.select(0)
	if not _profile:
		return
	for reference: String in _profile.clip_paths:
		var path: String = _resolve_clip_path(reference)
		if path.is_empty():
			continue
		_cue_source_menu.add_item(path.get_file().trim_suffix(".tres"))
		var index: int = _cue_source_menu.item_count - 1
		_cue_source_menu.set_item_metadata(index, path)
		_cue_source_menu.set_item_tooltip(index, path)
		if source and source.resource_path == path:
			_cue_source_menu.select(index)


func _on_cue_source_selected(index: int) -> void:
	var path: String = String(_cue_source_menu.get_item_metadata(index))
	_cue_source_picker.edited_resource = load(path) as LipSyncClip if not path.is_empty() else null


func _prepare_cue_transfer(source: LipSyncClip, destination: LipSyncClip, visemes: bool, expressions: bool, fit: bool) -> Dictionary:
	if not source or not destination:
		return {"error": "Choose a source clip and open a destination clip first."}
	if source == destination:
		return {"error": "Source and destination must be different clips."}
	if not visemes and not expressions:
		return {"error": "Select visemes, expressions, or both to copy."}
	if not destination.profile:
		return {"error": "Assign a destination character profile first."}
	var scale_factor: float = 1.0
	var offset: float = 0.0
	if fit:
		var source_length: float = source.audible_end - source.audible_start
		var target_length: float = destination.audible_end - destination.audible_start
		if source_length <= 0.0 or target_length <= 0.0:
			return {"error": "Both clips need a valid audible range to fit timing."}
		scale_factor = target_length / source_length
		offset = destination.audible_start - source.audible_start * scale_factor
	var result: Dictionary = {"visemes": [], "expressions": []}
	var missing: PackedStringArray = PackedStringArray()
	for expression: bool in [false, true]:
		if not (expressions if expression else visemes):
			continue
		var cues: Array[LipSyncCue] = source.expression_cues if expression else source.viseme_cues
		for cue: LipSyncCue in cues:
			if not cue or cue.end_time <= cue.start_time or cue.row < 0 or cue.row >= LipSyncCue.ROW_COUNT:
				return {"error": "Source contains invalid cues. Validate the source clip first."}
			if not destination.profile.find_pose(cue.pose_id, expression):
				if not missing.has(String(cue.pose_id)):
					missing.append(String(cue.pose_id))
			var copied: LipSyncCue = cue.duplicate(true) as LipSyncCue
			copied.start_time = maxf(0.0, cue.start_time * scale_factor + offset)
			copied.end_time = maxf(0.0, cue.end_time * scale_factor + offset)
			if copied.end_time <= copied.start_time:
				return {"error": "Fitted timing places a cue before time zero. Adjust audible ranges or disable timing fit."}
			copied.blend_in = minf(cue.blend_in * scale_factor, (copied.end_time - copied.start_time) * 0.5)
			copied.blend_out = minf(cue.blend_out * scale_factor, (copied.end_time - copied.start_time) * 0.5)
			copied.refresh_blends()
			result["expressions" if expression else "visemes"].append(copied)
	if not missing.is_empty():
		return {"error": "Destination profile is missing poses: %s. Add mappings before copying." % ", ".join(missing)}
	return result


func _copy_cues_into_open_clip() -> void:
	var source: LipSyncClip = _cue_source_picker.edited_resource as LipSyncClip
	var result: Dictionary = _prepare_cue_transfer(source, _clip, _copy_visemes.button_pressed, _copy_expressions.button_pressed, _fit_transfer_timing.button_pressed)
	if result.has("error"):
		_status.text = result["error"]
		return
	_stop_audio()
	_push_undo()
	if _copy_visemes.button_pressed:
		_clip.viseme_cues.assign(result["visemes"])
		if _copy_defaults.button_pressed:
			_clip.new_blend_in = source.new_blend_in
			_clip.new_blend_out = source.new_blend_out
			_clip.viseme_blend_curve = source.viseme_blend_curve
	if _copy_expressions.button_pressed:
		_clip.expression_cues.assign(result["expressions"])
		if _copy_defaults.button_pressed:
			_clip.new_expression_blend_in = source.new_expression_blend_in
			_clip.new_expression_blend_out = source.new_expression_blend_out
			_clip.expression_blend_curve = source.expression_blend_curve
	if _copy_defaults.button_pressed:
		_clip.smoothing_time = source.smoothing_time
	_timeline.clear_selection()
	_clip.emit_changed()
	_refresh_fields()
	_refresh_creation_fields()
	_refresh_playback_fields()
	_update_preview(_timeline.playhead)
	_timeline.queue_redraw()
	_status.text = "Copied cues into the open clip. Undo restores the previous setup. Save Clip to keep these changes."


func _add_foldout(parent: VBoxContainer, title: String, expanded: bool = false) -> VBoxContainer:
	var section: VBoxContainer = VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)
	var header: Button = Button.new()
	header.toggle_mode = true
	header.button_pressed = expanded
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = ("▼ " if expanded else "▶ ") + title
	header.tooltip_text = "Expand or collapse %s. Settings remain unchanged when collapsed." % title.to_lower()
	section.add_child(header)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.visible = expanded
	section.add_child(body)
	header.toggled.connect(func(open: bool) -> void:
		var focused: Control = get_viewport().gui_get_focus_owner()
		var restore_focus: bool = not open and focused and body.is_ancestor_of(focused)
		body.visible = open
		header.text = ("▼ " if open else "▶ ") + title
		if title == "Selected Cue":
			_refresh_fields()
		if restore_focus:
			header.grab_focus()
	)
	_foldout_headers[title] = header
	_foldout_bodies[title] = body
	return body


func _resource_picker(parent: Control, base_type: String, callback: Callable) -> EditorResourcePicker:
	var picker: EditorResourcePicker = EditorResourcePicker.new()
	picker.base_type = base_type
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(picker)
	picker.resource_changed.connect(callback)
	return picker


func _add_label(parent: Control, value: String) -> Label:
	var label: Label = Label.new()
	label.text = value
	parent.add_child(label)
	return label


func _toolbar_button(parent: Control, value: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = value
	parent.add_child(button)
	button.pressed.connect(callback)
	return button


func _on_profile_resource_changed(resource: Resource) -> void:
	if _clip_is_dirty() and resource != _profile:
		_profile_picker.edited_resource = _profile
		_status.text = "Save the current clip before changing its character profile."
		return
	_set_profile(resource as LipSyncProfile)


func _on_transfer_resource_changed(_resource: Resource) -> void:
	_update_clip_context()


func _edit_profile() -> void:
	if _profile:
		EditorInterface.edit_resource(_profile)


func _on_clip_resource_changed(resource: Resource) -> void:
	var clip: LipSyncClip = resource as LipSyncClip
	if not clip:
		_clip_picker.edited_resource = _clip
		return
	_request_open_clip(clip)


func _request_open_clip(clip: LipSyncClip) -> void:
	if clip == _clip:
		_sync_clip_menu_selection()
		return
	if _clip_is_dirty():
		_pending_open_clip = clip
		_clip_picker.edited_resource = _clip
		_sync_clip_menu_selection()
		_open_clip_dialog.dialog_text = "Save changes to the current clip before opening %s?" % clip.resource_path.get_file()
		_open_clip_dialog.popup_centered()
		return
	_open_clip(clip)


func _open_clip(clip: LipSyncClip) -> void:
	if clip and not clip.profile and _profile:
		clip.profile = _profile
	if clip and clip.profile and clip.profile != _profile:
		_profile_picker.edited_resource = clip.profile
		_set_profile(clip.profile)
	_clip_picker.edited_resource = clip
	_set_clip(clip)


func _save_then_open_clip() -> void:
	_save_resources()
	if not _clip_is_dirty():
		_complete_pending_open()


func _complete_pending_open() -> void:
	if not _pending_open_clip:
		return
	var clip: LipSyncClip = _pending_open_clip
	_pending_open_clip = null
	_open_clip(clip)


func _on_open_clip_action(action: StringName) -> void:
	if action != &"discard":
		return
	_open_clip_dialog.hide()
	if not _saved_state.is_empty():
		_restore_state(_saved_state)
	_complete_pending_open()


func _on_audio_resource_changed(resource: Resource) -> void:
	if _clip:
		_push_undo()
		_clip.audio = resource as AudioStream
		var analysis: Dictionary = WAVEFORM_SCRIPT.analyze(_clip.audio) if _clip.audio else {"peaks": PackedFloat32Array(), "start": 0.0, "end": 0.0}
		_clip.audible_start = analysis["start"]
		_clip.audible_end = analysis["end"]
		_timeline.normalize_audible_range()
		_timeline.waveform = analysis["peaks"]
		_timeline.queue_redraw()
		_clip.emit_changed()
		_status.text = "Assigned voice audio to %s." % (_clip.resource_path.get_file() if not _clip.resource_path.is_empty() else "unsaved clip")
		call_deferred("_fit_timeline")


func _set_profile(profile: LipSyncProfile) -> void:
	_profile = profile
	_refresh_profile_lists()
	_build_preview()
	if _clip and _clip.profile != profile:
		_clip_picker.edited_resource = null
		_set_clip(null)
	_update_clip_context()


func _refresh_profile_lists() -> void:
	var selected_viseme: String = _selected_palette_id(_viseme_list)
	var selected_expression: String = _selected_palette_id(_expression_list)
	_viseme_list.clear()
	_expression_list.clear()
	if _profile:
		var viseme_names: Array[String] = []
		var expression_names: Array[String] = []
		for pose: LipSyncPose in _profile.visemes:
			if pose:
				viseme_names.append(String(pose.id))
		for pose: LipSyncPose in _profile.expressions:
			if pose:
				expression_names.append(String(pose.id))
		viseme_names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		expression_names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		for name: String in viseme_names:
			_viseme_list.add_item(name)
		for name: String in expression_names:
			_expression_list.add_item(name)
		_restore_palette_selection(_viseme_list, selected_viseme)
		_restore_palette_selection(_expression_list, selected_expression)
		_profile.invalidate_clip_cache()
		_status.text = "Loaded %d visemes and %d expressions." % [_viseme_list.item_count, _expression_list.item_count]
	else:
		_status.text = "Select a character profile to load pose lists."
	_refresh_clip_menu()
	if _clip:
		_update_preview(_timeline.playhead)


func _selected_palette_id(list: ItemList) -> String:
	var selected: PackedInt32Array = list.get_selected_items()
	return list.get_item_text(selected[0]) if not selected.is_empty() else ""


func _restore_palette_selection(list: ItemList, pose_id: String) -> void:
	if list.item_count == 0:
		return
	var selected_index: int = 0
	for index: int in range(list.item_count):
		if list.get_item_text(index) == pose_id:
			selected_index = index
			break
	list.select(selected_index)


func _set_clip(clip: LipSyncClip) -> void:
	_stop_audio()
	if _clip and _clip.changed.is_connected(_on_clip_changed):
		_clip.changed.disconnect(_on_clip_changed)
	_clip = clip
	_selected_cue = null
	_undo_stack.clear()
	_redo_stack.clear()
	_pre_draft_state.clear()
	_transcript.text = clip.transcript if clip else ""
	_audio_picker.edited_resource = clip.audio if clip else null
	var peaks: PackedFloat32Array = PackedFloat32Array()
	if clip and clip.audio:
		var analysis: Dictionary = WAVEFORM_SCRIPT.analyze(clip.audio)
		peaks = analysis["peaks"]
		if clip.audible_end <= clip.audible_start:
			clip.audible_start = analysis["start"]
			clip.audible_end = analysis["end"]
		_status.text = "Audio %.2f s · audible %.2f–%.2f s" % [clip.audio.get_length(), clip.audible_start, clip.audible_end]
		if peaks.is_empty():
			_status.text += " · waveform unavailable for this format"
	elif clip:
		_status.text = "Estimated speech length %.2f s at 165 words/minute. Assign audio for timing." % DRAFT_SCRIPT.estimate_duration(clip.transcript)
	_timeline.set_clip(clip, peaks)
	if clip:
		call_deferred("_fit_timeline")
	if _preview_driver:
		_preview_driver.set_preview(clip, 0.0) if clip else _preview_driver.clear_preview()
	_refresh_fields()
	_refresh_creation_fields()
	_refresh_playback_fields()
	_saved_state = _capture_state() if clip and not clip.resource_path.is_empty() else {}
	if clip:
		clip.changed.connect(_on_clip_changed)
	_update_clip_context()
	_sync_clip_menu_selection()


func _on_clip_changed() -> void:
	_update_clip_context()


func _clip_is_dirty() -> bool:
	return _clip != null and (_clip.resource_path.is_empty() or _capture_state() != _saved_state)


func _update_clip_context() -> void:
	if not _clip_context:
		return
	var editing: bool = _clip != null
	if _transfer_context:
		_transfer_context.text = "Destination: %s" % (_clip.resource_path.get_file() if editing and not _clip.resource_path.is_empty() else "open unsaved clip" if editing else "no clip open")
	for button: Button in _clip_edit_buttons:
		button.disabled = not editing
	if _audio_picker:
		_audio_picker.editable = editing
	if _transcript:
		_transcript.editable = editing
	if _application_mode_menu:
		_application_mode_menu.disabled = not editing
	if _influence_duration_field:
		_influence_duration_field.editable = editing
	if not editing:
		_clip_context.text = "No clip open · choose New Clip or load a clip resource to edit."
		return
	var clip_name: String = _clip.resource_path.get_file() if not _clip.resource_path.is_empty() else "Unsaved clip"
	var profile_name: String = _clip.profile.resource_path.get_file() if _clip.profile else "No character profile"
	_clip_context.text = "Editing %s · %s%s" % [clip_name, profile_name, " · Unsaved changes" if _clip_is_dirty() else " · Saved"]


func _refresh_clip_menu() -> void:
	_refresh_cue_source_menu()
	_clip_menu.clear()
	_clip_menu.add_item("Select a saved clip...")
	_clip_menu.set_item_metadata(0, "")
	_clip_menu.select(0)
	if not _profile:
		return
	for path: String in _profile.clip_paths:
		var resolved_path: String = _resolve_clip_path(path)
		var label: String = resolved_path.get_file().trim_suffix(".tres") if not resolved_path.is_empty() else "Missing clip %d" % _clip_menu.item_count
		_clip_menu.add_item(label)
		var index: int = _clip_menu.item_count - 1
		_clip_menu.set_item_metadata(index, resolved_path)
		_clip_menu.set_item_tooltip(index, resolved_path if not resolved_path.is_empty() else "Unresolved clip reference: %s" % path)
		_clip_menu.set_item_disabled(index, resolved_path.is_empty())
	_sync_clip_menu_selection()


func _resolve_clip_path(path: String) -> String:
	if not path.begins_with("uid://"):
		return path
	var resource_id: int = ResourceUID.text_to_id(path)
	return ResourceUID.get_id_path(resource_id) if ResourceUID.has_id(resource_id) else ""


func _refresh_clip_names() -> void:
	_refresh_clip_menu()
	_status.text = "Refreshed clip names from saved resource filenames." if _profile else "Select a character profile to refresh clip names."


func _on_clip_menu_selected(index: int) -> void:
	var path: String = String(_clip_menu.get_item_metadata(index))
	if path.is_empty():
		_sync_clip_menu_selection()
		return
	var selected_clip: LipSyncClip = load(path) as LipSyncClip
	if not selected_clip:
		_status.text = "Could not open lip sync clip: %s" % path
		_sync_clip_menu_selection()
		return
	_request_open_clip(selected_clip)


func _sync_clip_menu_selection() -> void:
	_clip_menu.select(0)
	if not _clip:
		return
	for index: int in range(_clip_menu.item_count):
		if String(_clip_menu.get_item_metadata(index)) == _clip.resource_path:
			_clip_menu.select(index)
			return


func _build_preview() -> void:
	_preview_needs_rebuild = true
	if not is_visible_in_tree():
		return
	_preview_needs_rebuild = false
	if _preview_root:
		_preview_root.queue_free()
		_preview_root = null
		_preview_driver = null
	if not _profile or not _profile.preview_scene:
		return
	_preview_root = _profile.preview_scene.instantiate() as Node3D
	if not _preview_root:
		return
	_viewport.add_child(_preview_root)
	var skeletons: Array[Node] = _preview_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		_status.text = "Preview scene has no Skeleton3D."
		return
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	_preview_driver = DRIVER_SCRIPT.new() as LipSyncDriver
	_preview_driver.name = "LipSyncPreview"
	_preview_driver.profile = _profile
	skeleton.add_child(_preview_driver)
	var head_index: int = skeleton.find_bone(_profile.preview_focus_bone)
	if head_index >= 0:
		_camera_target = skeleton.to_global(skeleton.get_bone_global_pose(head_index).origin + _profile.preview_focus_offset)
	else:
		_camera_target = skeleton.global_position + Vector3(0.0, 1.4, 0.0)
	_camera_distance = maxf(0.5, _profile.preview_distance)
	_update_camera()
	if _clip:
		_preview_driver.set_preview(_clip, _timeline.playhead)


func _update_camera() -> void:
	if not _camera:
		return
	var direction: Vector3 = Vector3(sin(_camera_yaw) * cos(_camera_pitch), sin(_camera_pitch), cos(_camera_yaw) * cos(_camera_pitch))
	_camera.position = _camera_target + direction * _camera_distance
	_camera.look_at(_camera_target, Vector3.UP)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_preview_dragging = button.pressed
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera_distance = clampf(_camera_distance * (0.88 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12), 0.5, 12.0)
			_update_camera()
			_preview_container.accept_event()
		if button.button_index == MOUSE_BUTTON_LEFT:
			_preview_container.accept_event()
	elif event is InputEventMouseMotion and _preview_dragging:
		var motion: InputEventMouseMotion = event
		_camera_yaw -= motion.relative.x * 0.008
		_camera_pitch = clampf(_camera_pitch + motion.relative.y * 0.008, -1.2, 1.2)
		_update_camera()
		_preview_container.accept_event()


func _on_playhead_changed(time_sec: float) -> void:
	_update_preview(time_sec)
	if _timeline.is_scrubbing() and _transport_playing:
		_stop_audio()
	if _timeline.is_scrubbing() and _audition_scrub.button_pressed and _clip and _clip.audio:
		if time_sec >= _clip.audio.get_length():
			_player.stop()
			_scrub_end_tick = -1
			return
		_player.stop()
		_player.stream = _clip.audio
		_player.play(time_sec)
		_scrub_end_tick = Time.get_ticks_msec() + 110


func _update_preview(time_sec: float, continuous: bool = false) -> void:
	if _preview_driver and _clip:
		_preview_driver.set_preview(_clip, time_sec, continuous and _transport_playing and not _timeline.is_scrubbing())


func _on_cue_selected(cue: LipSyncCue, expression: bool) -> void:
	_selected_cue = cue
	_selected_expression = expression
	_refresh_fields()


func _on_cue_modified() -> void:
	_refresh_fields()
	_on_playhead_changed(_timeline.playhead)


func _refresh_fields() -> void:
	_editing_fields = true
	if _foldout_headers.has("Selected Cue"):
		var header: Button = _foldout_headers["Selected Cue"]
		header.text = ("▼ " if header.button_pressed else "▶ ") + "Selected Cue (%d selected)" % _timeline.get_selection_count()
	if _selection_summary:
		var count: int = _timeline.get_selection_count()
		if _selected_cue:
			_selection_summary.text = "%d selected · editing %s. Fields, resize, blending, and Replace affect this active cue." % [count, _selected_cue.pose_id]
		elif not _timeline.active_word.is_empty():
			_selection_summary.text = "%d selected · active word: %s. Drag its body to move the selection; edges resize this word." % [count, _timeline.active_word.get("word", "")]
		else:
			_selection_summary.text = "No timeline clips selected. Shift adds; Ctrl subtracts; drag empty track space to box-select."
	_cue_curve_menu.disabled = _selected_cue == null
	_cue_blend_lock.disabled = _selected_cue == null
	_cue_blend_lock.set_pressed_no_signal(_selected_cue.lock_max_blend if _selected_cue else false)
	_cue_curve_menu.select(_selected_cue.blend_curve + 1 if _selected_cue else 0)
	_expression_mix_menu.disabled = _selected_cue == null or not _selected_expression
	_expression_mix_menu.select(_selected_cue.expression_mix if _selected_cue else 0)
	_cue_row_menu.disabled = _selected_cue == null
	_cue_row_menu.set_item_disabled(2, false)
	_cue_row_menu.set_item_disabled(3, false)
	_cue_row_menu.select(clampi(_selected_cue.row, 0, LipSyncCue.ROW_COUNT - 1) if _selected_cue else 0)
	for key: String in _fields:
		var field: SpinBox = _fields[key]
		field.editable = _selected_cue != null
		if not _selected_cue:
			field.value = 0.0
		elif key == "blend_in":
			field.value = _selected_cue.get_blend_in()
		elif key == "blend_out":
			field.value = _selected_cue.get_blend_out()
		else:
			field.value = float(_selected_cue.get(key))
	_editing_fields = false


func _refresh_playback_fields() -> void:
	_editing_fields = true
	_application_mode_menu.disabled = _clip == null
	_influence_duration_field.editable = _clip != null
	_application_mode_menu.select(clampi(_clip.application_mode, 0, 1) if _clip else 0)
	_influence_duration_field.value = _clip.influence_duration_override if _clip else 0.0
	_editing_fields = false


func _on_application_mode_selected(mode: int) -> void:
	if _editing_fields or not _clip or _clip.application_mode == mode:
		return
	_push_undo()
	_clip.application_mode = mode
	_clip.emit_changed()
	_update_preview(_timeline.playhead)


func _on_influence_duration_changed(value: float) -> void:
	if _editing_fields or not _clip or is_equal_approx(_clip.influence_duration_override, value):
		return
	_push_undo()
	_clip.influence_duration_override = value
	_clip.emit_changed()
	_update_preview(_timeline.playhead)


func _refresh_creation_fields() -> void:
	_editing_fields = true
	for key: String in _curve_fields:
		var menu: OptionButton = _curve_fields[key]
		menu.disabled = _clip == null
		menu.select(int(_clip.get(key)) if _clip else 1)
	for key: String in _creation_fields:
		var field: SpinBox = _creation_fields[key]
		field.editable = _clip != null
		field.value = float(_clip.get(key)) if _clip else 0.0
	_editing_fields = false


func _on_curve_selected(value: int, key: String) -> void:
	if _editing_fields or not _clip or int(_clip.get(key)) == value:
		return
	_push_undo()
	_clip.set(key, value)
	_clip.emit_changed()
	_timeline.queue_redraw()
	_update_preview(_timeline.playhead)


func _on_cue_option_selected(value: int, key: String) -> void:
	if key == "blend_curve":
		value -= 1
	if _editing_fields or not _selected_cue or int(_selected_cue.get(key)) == value:
		return
	_push_undo()
	_selected_cue.set(key, value)
	_clip.emit_changed()
	_timeline.queue_redraw()
	_update_preview(_timeline.playhead)


func _on_creation_field_changed(value: float, key: String) -> void:
	if _editing_fields or not _clip or is_equal_approx(float(_clip.get(key)), value):
		return
	_push_undo()
	_clip.set(key, value)
	_clip.emit_changed()
	_update_preview(_timeline.playhead)
	if key == "generation_padding":
		_status.text = "Padding set to %.2f s. Generate Draft or Regenerate from Words to update visemes." % value


func _on_field_changed(value: float, key: String) -> void:
	if _editing_fields or not _selected_cue:
		return
	_push_undo()
	var original_start: float = _selected_cue.start_time
	var original_end: float = _selected_cue.end_time
	if key in ["blend_in", "blend_out"]:
		_selected_cue.refresh_blends()
		_selected_cue.lock_max_blend = false
	_selected_cue.set(key, value)
	var cues: Array[LipSyncCue] = _clip.expression_cues if _selected_expression else _clip.viseme_cues
	var previous_end: float = 0.0
	var next_start: float = 120.0
	for other: LipSyncCue in cues:
		if other == _selected_cue or other.row != _selected_cue.row:
			continue
		if other.end_time <= original_start:
			previous_end = maxf(previous_end, other.end_time)
		elif other.start_time >= original_end:
			next_start = minf(next_start, other.start_time)
	if key == "start_time":
		_selected_cue.start_time = clampf(_selected_cue.start_time, previous_end, _selected_cue.end_time - 0.02)
	elif key == "end_time":
		_selected_cue.end_time = clampf(_selected_cue.end_time, _selected_cue.start_time + 0.02, next_start)
	_selected_cue.refresh_blends()
	cues.sort_custom(func(a: LipSyncCue, b: LipSyncCue) -> bool: return a.start_time < b.start_time)
	_selected_cue.emit_changed()
	_clip.emit_changed()
	_timeline.queue_redraw()
	_on_playhead_changed(_timeline.playhead)
	_refresh_fields()


func _on_cue_row_selected(row: int) -> void:
	if _editing_fields or not _selected_cue or row == _selected_cue.row:
		return
	if row < 0 or row >= LipSyncCue.ROW_COUNT:
		_refresh_fields()
		return
	var cues: Array[LipSyncCue] = _clip.expression_cues if _selected_expression else _clip.viseme_cues
	if not _row_available(cues, _selected_cue, row, _selected_cue.start_time, _selected_cue.end_time):
		_status.text = "Another cue occupies that row at this time."
		_refresh_fields()
		return
	_push_undo()
	_selected_cue.row = row
	_selected_cue.emit_changed()
	_clip.emit_changed()
	_timeline.queue_redraw()


func _row_available(cues: Array[LipSyncCue], selected: LipSyncCue, row: int, start: float, end: float) -> bool:
	for cue: LipSyncCue in cues:
		if cue and cue != selected and cue.row == row and start < cue.end_time - 0.001 and end > cue.start_time + 0.001:
			return false
	return true


func _replace_selected_cue(expression: bool) -> void:
	if not _clip or not _selected_cue or _selected_expression != expression:
		return
	var list: ItemList = _expression_list if expression else _viseme_list
	var selected: PackedInt32Array = list.get_selected_items()
	if selected.is_empty():
		return
	var pose_id: StringName = StringName(list.get_item_text(selected[0]))
	if _selected_cue.pose_id == pose_id:
		return
	_push_undo()
	_selected_cue.pose_id = pose_id
	_selected_cue.emit_changed()
	_clip.emit_changed()
	_timeline.queue_redraw()
	_update_preview(_timeline.playhead)


func _add_cue(expression: bool, time_sec: float, row: int = 0) -> void:
	if not _clip or not _profile:
		return
	row = clampi(row, 0, LipSyncCue.ROW_COUNT - 1)
	var list: ItemList = _expression_list if expression else _viseme_list
	var selected: PackedInt32Array = list.get_selected_items()
	if selected.is_empty():
		_status.text = "Select a pose from the palette first."
		return
	var pose_id: StringName = StringName(list.get_item_text(selected[0]))
	_push_undo()
	var cues: Array[LipSyncCue] = _clip.expression_cues if expression else _clip.viseme_cues
	var start: float = snappedf(time_sec, 0.01)
	var next_start: float = _clip.get_timeline_length() + 2.0
	for existing: LipSyncCue in cues:
		if existing.row != row:
			continue
		if absf(existing.start_time - start) < 0.01:
			existing.pose_id = pose_id
			_clip.emit_changed()
			_timeline.select_cue(existing, expression)
			_timeline.queue_redraw()
			return
		if existing.start_time < start and existing.end_time > start:
			existing.end_time = start
			existing.refresh_blends()
		elif existing.start_time > start:
			next_start = minf(next_start, existing.start_time)
	var cue: LipSyncCue = LipSyncCue.new()
	cue.pose_id = pose_id
	cue.row = row
	cue.start_time = start
	cue.end_time = minf(start + (0.7 if expression else 0.16), next_start)
	if cue.end_time <= cue.start_time + 0.01:
		_status.text = "No room for a cue at this time."
		return
	var blend_limit: float = (cue.end_time - cue.start_time) * 0.5
	cue.blend_in = minf(_clip.new_expression_blend_in if expression else _clip.new_blend_in, blend_limit)
	cue.blend_out = minf(_clip.new_expression_blend_out if expression else _clip.new_blend_out, blend_limit)
	cues.append(cue)
	cues.sort_custom(func(a: LipSyncCue, b: LipSyncCue) -> bool: return a.start_time < b.start_time)
	_clip.emit_changed()
	_timeline.select_cue(cue, expression)
	_timeline.queue_redraw()
	_on_playhead_changed(_timeline.playhead)


func _delete_cue() -> void:
	if not _clip or _timeline.get_selection_count() == 0:
		return
	_push_undo()
	for cue: LipSyncCue in _timeline.selected_cues:
		_clip.viseme_cues.erase(cue)
		_clip.expression_cues.erase(cue)
	for index: int in range(_clip.word_spans.size() - 1, -1, -1):
		if _timeline._has_word(_timeline.selected_words, _clip.word_spans[index]):
			_clip.word_spans.remove_at(index)
	_timeline.clear_selection()
	_clip.emit_changed()
	_refresh_fields()
	_timeline.queue_redraw()
	_on_playhead_changed(_timeline.playhead)


func _extend_expression(seconds: float) -> void:
	if not _clip or not _selected_cue or not _selected_expression:
		return
	_push_undo()
	var maximum: float = _next_start_in_row(_clip.expression_cues, _selected_cue, _clip.get_timeline_length() + seconds)
	_selected_cue.end_time = minf(_selected_cue.end_time + seconds, maximum)
	_refresh_selected_blends()
	_on_cue_modified()
	_clip.emit_changed()
	_timeline.queue_redraw()


func _hold_to_audio_end() -> void:
	if not _clip or not _clip.audio or not _selected_cue or not _selected_expression:
		return
	_push_undo()
	var maximum: float = _next_start_in_row(_clip.expression_cues, _selected_cue, _clip.audio.get_length())
	_selected_cue.end_time = maxf(_selected_cue.end_time, minf(_clip.audio.get_length(), maximum))
	_refresh_selected_blends()
	_on_cue_modified()
	_clip.emit_changed()
	_timeline.queue_redraw()


func _next_start_in_row(cues: Array[LipSyncCue], selected: LipSyncCue, fallback: float) -> float:
	var next_start: float = fallback
	for cue: LipSyncCue in cues:
		if cue and cue != selected and cue.row == selected.row and cue.start_time >= selected.end_time:
			next_start = minf(next_start, cue.start_time)
	return next_start


func _refresh_selected_blends() -> void:
	_selected_cue.refresh_blends()


func _set_audible_range() -> void:
	if not _clip or not _clip.audio:
		return
	_push_undo()
	var analysis: Dictionary = WAVEFORM_SCRIPT.analyze(_clip.audio)
	_clip.audible_start = analysis["start"]
	_clip.audible_end = analysis["end"]
	_timeline.normalize_audible_range()
	_timeline.waveform = analysis["peaks"]
	_timeline.queue_redraw()
	_clip.emit_changed()
	_status.text = "Detected audible range %.2f–%.2f s." % [_clip.audible_start, _clip.audible_end]


func _reset_audible_trim() -> void:
	if not _clip or not _clip.audio:
		return
	_push_undo()
	_timeline.cancel_audible_drag()
	_clip.audible_start = 0.0
	_clip.audible_end = _clip.audio.get_length()
	_clip.emit_changed()
	_timeline.queue_redraw()
	_status.text = "Reset audible trim to the full %.2f s audio clip." % _clip.audible_end


func _on_transcript_changed() -> void:
	if _clip and not _restoring_history:
		_clip.transcript = _transcript.text
		_clip.emit_changed()
		if not _clip.audio:
			_status.text = "Estimated speech length %.2f s at 165 words/minute." % DRAFT_SCRIPT.estimate_duration(_clip.transcript)


func _request_draft() -> void:
	if not _clip or not _clip.audio or _clip.transcript.strip_edges().is_empty():
		_status.text = "Add audio and transcript text before generating a draft."
		return
	if _clip.viseme_cues.is_empty():
		_generate_draft()
	else:
		_draft_dialog.popup_centered()


func _generate_draft() -> void:
	_push_undo()
	_pre_draft_state = _capture_state()
	DRAFT_SCRIPT.generate(_clip)
	_timeline.clear_selection()
	_timeline.queue_redraw()
	_on_playhead_changed(_timeline.playhead)
	_status.text = "Generated %d draft visemes. Review timing against the audio." % _clip.viseme_cues.size()


func _regenerate_from_words() -> void:
	if not _clip or _clip.word_spans.is_empty():
		_status.text = "Generate a draft with word guidance before regenerating visemes."
		return
	var previous_state: Dictionary = _capture_state()
	_push_undo()
	if not DRAFT_SCRIPT.regenerate_from_words(_clip):
		_undo_stack.pop_back()
		_status.text = "Word guidance has invalid timing or no usable words."
		return
	_pre_draft_state = previous_state
	_timeline.clear_selection()
	_refresh_fields()
	_timeline.queue_redraw()
	_on_playhead_changed(_timeline.playhead)
	_status.text = "Regenerated %d visemes from the adjusted word spans." % _clip.viseme_cues.size()


func _revert_draft() -> void:
	if not _clip or _pre_draft_state.is_empty():
		_status.text = "No generated draft to revert."
		return
	_push_undo()
	var state: Dictionary = _capture_state()
	state["visemes"] = _pre_draft_state["visemes"]
	state["words"] = _pre_draft_state["words"]
	_restore_state(state)
	_pre_draft_state.clear()
	_status.text = "Viseme draft and word guidance reverted."


func _play_timeline() -> void:
	if not _clip:
		return
	var start_time: float = _timeline.playhead if _from_cursor.button_pressed else 0.0
	if start_time >= _clip.get_timeline_length():
		return
	_seek_transport(start_time)


func _seek_transport(time_sec: float) -> void:
	_player.stop()
	_scrub_end_tick = -1
	_player.stream = _clip.audio
	_transport_time = time_sec
	_transport_playing = true
	if _clip.audio and time_sec < _clip.audio.get_length():
		_player.play(time_sec)
	_timeline.set_playhead(time_sec, false)
	_update_preview(time_sec)


func _stop_audio() -> void:
	if _player:
		_player.stop()
	_transport_playing = false
	_scrub_end_tick = -1


func _on_audio_finished() -> void:
	if _transport_playing and _clip and _clip.audio:
		_transport_time = maxf(_transport_time, _clip.audio.get_length())


func _on_preview_volume_changed(value: float) -> void:
	if _preview_volume_value:
		_preview_volume_value.text = "%d%%" % int(value)
	if _player:
		_player.volume_db = -80.0 if value <= 0.0 else linear_to_db(value / 100.0)


func _fit_timeline() -> void:
	if _clip:
		if _timeline.waveform.is_empty() and _clip.audio:
			_timeline.refresh_waveform()
		_timeline.pixels_per_second = clampf((_timeline.size.x - 24.0) / maxf(_clip.get_timeline_length(), 0.5), 45.0, 1000.0)
		_timeline.scroll_seconds = 0.0
		_timeline.queue_redraw()


func _refresh_waveform() -> void:
	if not _clip or not _clip.audio:
		_status.text = "Assign voice audio to refresh its waveform."
		return
	_timeline.refresh_waveform()
	_fit_timeline()
	_status.text = "Refreshed voice waveform." if not _timeline.waveform.is_empty() else _timeline._waveform_message


func _zoom_timeline(factor: float) -> void:
	_timeline.pixels_per_second = clampf(_timeline.pixels_per_second * factor, 45.0, 1000.0)
	_timeline.queue_redraw()


func _capture_state() -> Dictionary:
	if not _clip:
		return {}
	return {
		"audio": _clip.audio,
		"transcript": _clip.transcript,
		"audible_start": _clip.audible_start,
		"audible_end": _clip.audible_end,
		"generation_padding": _clip.generation_padding,
		"new_blend_in": _clip.new_blend_in,
		"new_blend_out": _clip.new_blend_out,
		"new_expression_blend_in": _clip.new_expression_blend_in,
		"new_expression_blend_out": _clip.new_expression_blend_out,
		"viseme_blend_curve": _clip.viseme_blend_curve,
		"expression_blend_curve": _clip.expression_blend_curve,
		"smoothing_time": _clip.smoothing_time,
		"application_mode": _clip.application_mode,
		"influence_duration_override": _clip.influence_duration_override,
		"visemes": _cue_data(_clip.viseme_cues),
		"expressions": _cue_data(_clip.expression_cues),
		"words": _clip.word_spans.duplicate(true),
	}


func _cue_data(cues: Array[LipSyncCue]) -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for cue: LipSyncCue in cues:
		data.append({
			"id": cue.pose_id,
			"start": cue.start_time,
			"end": cue.end_time,
			"row": cue.row,
			"blend_in": cue.blend_in,
			"blend_out": cue.blend_out,
			"strength": cue.strength,
			"lock_max_blend": cue.lock_max_blend,
			"blend_curve": cue.blend_curve,
			"expression_mix": cue.expression_mix,
		})
	return data


func _restore_state(state: Dictionary) -> void:
	if not _clip or state.is_empty():
		return
	_restoring_history = true
	_clip.audio = state["audio"]
	_clip.transcript = state["transcript"]
	_clip.audible_start = state["audible_start"]
	_clip.audible_end = state["audible_end"]
	_clip.generation_padding = float(state.get("generation_padding", 0.0))
	_clip.new_blend_in = float(state.get("new_blend_in", 0.04))
	_clip.new_blend_out = float(state.get("new_blend_out", 0.04))
	_clip.new_expression_blend_in = float(state.get("new_expression_blend_in", 0.15))
	_clip.new_expression_blend_out = float(state.get("new_expression_blend_out", 0.15))
	_clip.viseme_blend_curve = int(state.get("viseme_blend_curve", 1))
	_clip.expression_blend_curve = int(state.get("expression_blend_curve", 1))
	_clip.smoothing_time = float(state.get("smoothing_time", 0.0))
	_clip.application_mode = int(state.get("application_mode", 0))
	_clip.influence_duration_override = float(state.get("influence_duration_override", 0.0))
	_clip.viseme_cues.clear()
	for data: Dictionary in state["visemes"]:
		_clip.viseme_cues.append(_cue_from_data(data))
	_clip.expression_cues.clear()
	for data: Dictionary in state["expressions"]:
		_clip.expression_cues.append(_cue_from_data(data))
	_clip.word_spans.clear()
	for span: Dictionary in state["words"]:
		_clip.word_spans.append(span.duplicate(true))
	_transcript.text = _clip.transcript
	_audio_picker.edited_resource = _clip.audio
	_timeline.clear_selection()
	var analysis: Dictionary = WAVEFORM_SCRIPT.analyze(_clip.audio) if _clip.audio else {"peaks": PackedFloat32Array()}
	_timeline.waveform = analysis["peaks"]
	_timeline.queue_redraw()
	_clip.emit_changed()
	_refresh_fields()
	_refresh_creation_fields()
	_refresh_playback_fields()
	_update_preview(_timeline.playhead)
	_restoring_history = false


func _cue_from_data(data: Dictionary) -> LipSyncCue:
	var cue: LipSyncCue = LipSyncCue.new()
	cue.pose_id = data["id"]
	cue.start_time = data["start"]
	cue.end_time = data["end"]
	cue.row = int(data.get("row", 0))
	cue.blend_in = data["blend_in"]
	cue.blend_out = data["blend_out"]
	cue.strength = data["strength"]
	cue.lock_max_blend = bool(data.get("lock_max_blend", false))
	cue.blend_curve = int(data.get("blend_curve", -1))
	cue.expression_mix = int(data.get("expression_mix", 0))
	return cue


func _on_timeline_edit_started() -> void:
	_drag_undo_backup = _undo_stack.duplicate()
	_drag_redo_backup = _redo_stack.duplicate()
	_push_undo()


func _on_timeline_edit_cancelled() -> void:
	_undo_stack = _drag_undo_backup.duplicate()
	_redo_stack = _drag_redo_backup.duplicate()
	_update_clip_context()


func _push_undo() -> void:
	if not _clip or _restoring_history:
		return
	_undo_stack.append(_capture_state())
	if _undo_stack.size() > 64:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _undo() -> void:
	if _undo_stack.is_empty():
		_status.text = "Nothing to undo."
		return
	_redo_stack.append(_capture_state())
	_restore_state(_undo_stack.pop_back())
	_status.text = "Undid lip sync edit."


func _redo() -> void:
	if _redo_stack.is_empty():
		_status.text = "Nothing to redo."
		return
	_undo_stack.append(_capture_state())
	_restore_state(_redo_stack.pop_back())
	_status.text = "Redid lip sync edit."


func _new_clip() -> void:
	if not _profile:
		_status.text = "Select a character profile first."
		return
	if _clip_is_dirty():
		_new_clip_dialog.popup_centered()
		return
	_create_new_clip()


func _save_then_new() -> void:
	_pending_new_after_save = true
	_save_resources()
	if _pending_new_after_save and not _clip_is_dirty():
		_pending_new_after_save = false
		_create_new_clip()


func _on_new_clip_action(action: StringName) -> void:
	if action == &"discard":
		_new_clip_dialog.hide()
		_create_new_clip()


func _create_new_clip() -> void:
	var new_clip: LipSyncClip = LipSyncClip.new()
	new_clip.profile = _profile
	new_clip.smoothing_time = NEW_CLIP_SMOOTHING_TIME
	_clip_picker.edited_resource = new_clip
	_set_clip(new_clip)
	_status.text = "New unsaved clip. Assign voice audio, then edit cues and transcript. Save Clip chooses its file path."


func _transfer_clip() -> void:
	if not _clip or not (_transfer_picker.edited_resource is LipSyncProfile):
		_status.text = "Select a clip and a transfer target profile."
		return
	_save_action = "transfer"
	var target: LipSyncProfile = _transfer_picker.edited_resource as LipSyncProfile
	_save_dialog.current_dir = _clip_directory(target)
	_save_dialog.current_file = "%s.lipsync.tres" % _clip.audio.resource_path.get_file().get_basename() if _clip.audio else "TransferredLipSync.tres"
	_save_dialog.popup_centered_ratio(0.6)


func _on_save_path_selected(path: String) -> void:
	var owner_profile: LipSyncProfile = _transfer_picker.edited_resource as LipSyncProfile if _save_action == "transfer" else _profile
	if not owner_profile or owner_profile.resource_path.is_empty() or not path.begins_with(owner_profile.resource_path.get_base_dir() + "/"):
		_status.text = "Save lip sync clips inside the target character's folder."
		_save_action = ""
		_pending_new_after_save = false
		return
	if _save_action == "save":
		if not _clip or ResourceSaver.save(_clip, path) != OK:
			_status.text = "Could not save the clip."
			_save_action = ""
			_pending_new_after_save = false
			return
		_clip.take_over_path(path)
		_register_clip(_clip, _profile, path)
		_refresh_clip_menu()
		_clip_picker.edited_resource = _clip
		_saved_state = _capture_state()
		_update_clip_context()
		_status.text = "Saved %s." % path.get_file()
	elif _save_action == "transfer":
		var target: LipSyncProfile = _transfer_picker.edited_resource as LipSyncProfile
		var transferred: LipSyncClip = _clip.duplicate(true) as LipSyncClip
		transferred.profile = target
		var missing: Array[String] = []
		for cue: LipSyncCue in transferred.viseme_cues:
			if not target.find_pose(cue.pose_id):
				missing.append(String(cue.pose_id))
		for cue: LipSyncCue in transferred.expression_cues:
			if not target.find_pose(cue.pose_id, true):
				missing.append(String(cue.pose_id))
		if ResourceSaver.save(transferred, path) != OK:
			_status.text = "Could not save the transferred clip."
			_save_action = ""
			return
		_register_clip(transferred, target, path)
		_status.text = "Transferred clip. Missing target poses: %s" % (", ".join(missing) if not missing.is_empty() else "none")
	_save_action = ""
	_complete_pending_open()
	if _pending_new_after_save:
		_pending_new_after_save = false
		_create_new_clip()


func _on_save_dialog_canceled() -> void:
	_save_action = ""
	_pending_new_after_save = false
	_pending_open_clip = null


func _register_clip(clip: LipSyncClip, owner_profile: LipSyncProfile, path: String) -> void:
	var registered: bool = false
	for reference: String in owner_profile.clip_paths:
		if _resolve_clip_path(reference) == path:
			registered = true
			break
	if not registered:
		owner_profile.clip_paths.append(path)
	owner_profile.invalidate_clip_cache()
	ResourceSaver.save(owner_profile)
	_ensure_export_path("Characters pack", path)
	_ensure_export_path("Characters pack", owner_profile.resource_path)
	if clip.audio:
		_ensure_export_path("Audio pack", clip.audio.resource_path)


func _save_resources() -> void:
	if not _clip:
		_status.text = "Create or open a clip before saving."
		_pending_new_after_save = false
		return
	if not _profile:
		_status.text = "Select a character profile before saving the clip."
		_pending_new_after_save = false
		return
	if _clip.resource_path.is_empty():
		_save_action = "save"
		_save_dialog.current_dir = _clip_directory(_profile)
		_save_dialog.current_file = "%s.lipsync.tres" % _clip.audio.resource_path.get_file().get_basename() if _clip.audio else "NewLipSync.tres"
		_save_dialog.popup_centered_ratio(0.6)
		return
	if ResourceSaver.save(_clip) != OK:
		_status.text = "Could not save %s." % _clip.resource_path.get_file()
		_pending_new_after_save = false
		return
	_register_clip(_clip, _profile, _clip.resource_path)
	_saved_state = _capture_state()
	_update_clip_context()
	_status.text = "Saved %s." % _clip.resource_path.get_file()


func _clip_directory(profile: LipSyncProfile) -> String:
	var directory: String = profile.resource_path.get_base_dir().path_join("LipSync")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	return directory


func _ensure_export_path(preset_name: String, resource_path: String) -> void:
	if resource_path.is_empty() or not resource_path.begins_with("res://"):
		return
	var config_path: String = "res://export_presets.cfg"
	var content: String = FileAccess.get_file_as_string(config_path)
	var lines: PackedStringArray = content.split("\n")
	var in_preset: bool = false
	for index: int in range(lines.size()):
		var line: String = lines[index]
		if line.begins_with("name=\""):
			in_preset = line.strip_edges() == "name=\"%s\"" % preset_name
		elif in_preset and line.begins_with("export_files=PackedStringArray("):
			if not line.contains("\"%s\"" % resource_path):
				lines[index] = line.trim_suffix("\r").trim_suffix(")") + ", \"%s\")" % resource_path
				var file: FileAccess = FileAccess.open(config_path, FileAccess.WRITE)
				if file:
					file.store_string("\n".join(lines))
			return


func _validate() -> void:
	if not _profile:
		_status.text = "Select a character profile to validate."
		return
	var issues: Array[String] = []
	if not _profile.preview_scene:
		issues.append("preview scene missing")
	if _profile.viseme_bones.is_empty():
		issues.append("viseme bone list empty")
	if _profile.expression_bones.is_empty():
		issues.append("expression bone list empty")
	for pose: LipSyncPose in _profile.visemes + _profile.expressions:
		if not pose or not pose.animation:
			issues.append("animation mapping missing")
	if _clip:
		if _clip.profile != _profile:
			issues.append("clip profile differs from selected profile")
		if not _clip.audio:
			issues.append("clip audio missing")
		for expression: LipSyncCue in _clip.expression_cues:
			if not _profile.find_pose(expression.pose_id, true):
				issues.append("missing expression %s" % expression.pose_id)
		_validate_cue_rows(_clip.expression_cues, "expression", LipSyncCue.ROW_COUNT - 1, issues)
		for viseme: LipSyncCue in _clip.viseme_cues:
			if not _profile.find_pose(viseme.pose_id):
				issues.append("missing viseme %s" % viseme.pose_id)
		_validate_cue_rows(_clip.viseme_cues, "viseme", LipSyncCue.ROW_COUNT - 1, issues)
	_status.text = "Validation passed." if issues.is_empty() else "Validation: %s" % "; ".join(issues)


func _validate_cue_rows(cues: Array[LipSyncCue], kind: String, max_row: int, issues: Array[String]) -> void:
	for index: int in range(cues.size()):
		var cue: LipSyncCue = cues[index]
		if not cue or cue.row < 0 or cue.row > max_row or cue.end_time <= cue.start_time:
			issues.append("invalid %s cue" % kind)
			continue
		for other_index: int in range(index + 1, cues.size()):
			var other: LipSyncCue = cues[other_index]
			if other and cue.row == other.row and cue.start_time < other.end_time and cue.end_time > other.start_time:
				issues.append("%s row %d overlaps" % [kind, cue.row + 1])
				return

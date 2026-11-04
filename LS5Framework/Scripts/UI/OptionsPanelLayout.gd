@tool
extends Panel
class_name OptionsPanelLayout

const MAXIMUM_PANEL_WIDTH: float = 1180.0
const SETTINGS_CONTROLS: Dictionary = {
	&"item_selected": [
		"OptionResolution",
		"OptionLOD",
		"OptionHomingTargetMode",
		"OptionMouseHomingTargetMode",
		"OptionLightspeedDashTargetMode",
		"OptionGhostRecordingRate",
		"OptionGhostPlaybackRate",
	],
	&"pressed": [
		"ButtonApplyResolution",
		"ButtonResetDefaults",
		"ButtonOptionsBack",
	],
	&"toggled": [
		"CheckFullscreen",
		"CheckVsync",
		"CheckSSR",
		"CheckSSAO",
		"CheckSSIL",
		"CheckSDFGI",
		"CheckShadows",
		"CheckGlow",
		"CheckDepthOfField",
		"CheckWaterDisplacement",
		"CheckWaterRefraction",
		"CheckWaterNormals",
		"CheckWaterDepthFx",
		"CheckSeparateHomingTargeting",
		"CheckCameraDolly",
		"CheckCameraTargetLookahead",
		"CheckAutoFollowCamera",
		"CheckAutoFollowControllerOnly",
		"CheckCenterReticle",
		"CheckRememberEmotePage",
		"CheckComboSystem",
		"CheckRecordRaceGhosts",
		"CheckUseCharacterColorsOffline",
	],
	&"value_changed": [
		"SliderCameraFar",
		"SliderCameraFov",
		"SliderMaster",
		"SliderMusic",
		"SliderSfx",
		"SliderUi",
		"SliderVoice",
		"SliderHomingRadius",
		"SliderCameraFollowSmoothing",
		"SliderCameraTargetLookaheadAmount",
		"SliderAutoFollowSensitivity",
		"SliderAutoFollowInterruptDelay",
		"SliderCenterReticleScale",
		"SliderCenterReticleOpacity",
		"SliderReticleVerticalOffset",
	],
	&"color_changed": [
		"ColorCenterReticle",
		"ColorOfflinePrimary",
		"ColorOfflineSecondary",
		"ColorOfflineTrail",
	],
}

## Container spanning the options viewport.
var _frame: Control
## Displays navigation bindings for the active input device.
var _navigation_hint: Label
var _hint_signature: String = ""


func _ready() -> void:
	_frame = get_parent() as Control
	if not _frame:
		return
	_frame.resized.connect(_queue_layout)
	visibility_changed.connect(_queue_layout)
	if not Engine.is_editor_hint():
		_create_navigation_footer()
	_queue_layout()


func connect_settings_controls(menu: Control) -> void:
	for signal_name: StringName in SETTINGS_CONTROLS:
		for control_name: String in SETTINGS_CONTROLS[signal_name]:
			var control: Node = find_child(control_name, true, false)
			var handler: Callable = Callable(menu, "_on_%s_%s" % [control_name, signal_name])
			if not control or not handler.is_valid():
				push_error("Missing options control or handler: " + control_name)
				continue
			if not control.is_connected(signal_name, handler):
				control.connect(signal_name, handler)


func _queue_layout() -> void:
	_apply_layout.call_deferred()


func _apply_layout() -> void:
	if not is_instance_valid(_frame) or not is_inside_tree():
		return
	var available: Vector2 = (_frame.size - Vector2.ONE * 48.0).max(Vector2.ONE)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2.ONE
	custom_minimum_size = Vector2.ZERO
	size = Vector2(minf(MAXIMUM_PANEL_WIDTH, available.x), available.y)
	position = (_frame.size - size) * 0.5
	_fit_rows(self)


func _create_navigation_footer() -> void:
	var content: VBoxContainer = get_node_or_null("VBoxOptions") as VBoxContainer
	if not content or content.has_node("MenuDescription"):
		return
	var description: Label = Label.new()
	description.name = "MenuDescription"
	description.text = "Choose an option. Use left and right to adjust values."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 48.0
	description.add_theme_font_size_override("font_size", 18)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(description)
	content.move_child(description, maxi(0, content.get_child_count() - 3))
	var hint: Label = Label.new()
	_navigation_hint = hint
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(hint)
	var old_hint: Control = content.get_node_or_null("LabelTabHint") as Control
	if old_hint:
		old_hint.hide()
	_update_navigation_hint()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() and is_visible_in_tree():
		_update_navigation_hint()


func _update_navigation_hint() -> void:
	if not _navigation_hint:
		return
	var controller: bool = SettingsManager.is_controller_input_active()
	var signature: String = str(controller) + ":" + str(InputBindingGlyphs.resolve_style())
	if signature == _hint_signature:
		return
	_hint_signature = signature
	if controller:
		var presentation = preload("res://LS5Framework/Scripts/UI/MenuPresentation.gd")
		_navigation_hint.text = "↑ ↓  Navigate    ← →  Adjust    %s / %s  Category    %s  Back" % [presentation.button_label(JOY_BUTTON_LEFT_SHOULDER), presentation.button_label(JOY_BUTTON_RIGHT_SHOULDER), presentation.button_label(JOY_BUTTON_B)]
	else:
		_navigation_hint.text = "↑ ↓  Navigate    ← →  Adjust    PgUp / PgDn  Category    Esc  Back"


func _fit_rows(node: Node) -> void:
	for child: Node in node.get_children():
		if child is HBoxContainer:
			var row: HBoxContainer = child as HBoxContainer
			row.custom_minimum_size.y = 52.0
			for item: Node in row.get_children():
				if item is Label:
					var label: Label = item as Label
					if label.name == &"MenuValue":
						continue
					label.custom_minimum_size.x = 0.0
					label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				elif item is Slider or item is OptionButton:
					(item as Control).custom_minimum_size.x = clampf(size.x * 0.34, 120.0, 360.0)
					if item is Slider and not row.has_node("MenuValue"):
						var value_label: Label = Label.new()
						value_label.name = "MenuValue"
						value_label.custom_minimum_size.x = 72.0
						value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
						value_label.add_theme_font_size_override("font_size", 20)
						row.add_child(value_label)
						_update_value(item as Range, value_label)
						(item as Range).value_changed.connect(func(_value: float) -> void: _update_value(item as Range, value_label))
		if child is ScrollContainer:
			(child as ScrollContainer).horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_fit_rows(child)


func _update_value(control: Range, label: Label) -> void:
	label.text = String.num(control.value, 2).trim_suffix(".00")

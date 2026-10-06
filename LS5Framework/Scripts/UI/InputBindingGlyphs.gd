extends RefCounted
class_name InputBindingGlyphs

enum Style { AUTO, PLAYSTATION, GENERIC }

const PS_ROOT: String = "res://LS5Framework/Images/Buttons/ps/"
const PS_BUTTONS: Dictionary = {
	JOY_BUTTON_A: "PS_FACE_CROSS.png", JOY_BUTTON_B: "PS_FACE_CIRCLE.png",
	JOY_BUTTON_X: "PS_FACE_SQUARE.png", JOY_BUTTON_Y: "PS_FACE_TRIANGLE.png",
	JOY_BUTTON_BACK: "PS_Select.png", JOY_BUTTON_START: "PS_Start.png",
	JOY_BUTTON_LEFT_STICK: "PS_L3.png", JOY_BUTTON_RIGHT_STICK: "PS_R3.png",
	JOY_BUTTON_LEFT_SHOULDER: "PS_L1.png", JOY_BUTTON_RIGHT_SHOULDER: "PS_R1.png",
	JOY_BUTTON_DPAD_UP: "PS_Dpad_Up.png", JOY_BUTTON_DPAD_DOWN: "PS_Dpad_Down.png",
	JOY_BUTTON_DPAD_LEFT: "PS_Dpad_Left.png", JOY_BUTTON_DPAD_RIGHT: "PS_Dpad_Right.png",
}
const PS_AXES: Dictionary = {
	JOY_AXIS_LEFT_X: "PS_L_Stick.png", JOY_AXIS_LEFT_Y: "PS_L_Stick.png",
	JOY_AXIS_RIGHT_X: "PS_R_Stick.png", JOY_AXIS_RIGHT_Y: "PS_R_Stick.png",
	JOY_AXIS_TRIGGER_LEFT: "PS_L2.png", JOY_AXIS_TRIGGER_RIGHT: "PS_R2.png",
}
const PS_LABELS: Dictionary = {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_BACK: "Select", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "PS",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
}
const GENERIC_LABELS: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
}
const DPAD_LABELS: Dictionary = {
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}


static func resolve_style(style: int = Style.AUTO, device: int = -1) -> int:
	if style != Style.AUTO:
		return style
	if device < 0:
		device = SettingsManager.get_preferred_joypad_device()
	if device < 0:
		return Style.GENERIC
	var info: Dictionary = Input.get_joy_info(device)
	var name: String = (Input.get_joy_name(device) + " " + String(info.get("raw_name", ""))).to_lower()
	if int(info.get("vendor_id", 0)) == 0x054c:
		return Style.PLAYSTATION
	for identifier: String in ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5"]:
		if name.contains(identifier):
			return Style.PLAYSTATION
	return Style.GENERIC


static func get_slot_bindings(slot: StringName) -> Array:
	if SettingsManager.input_bindings.has(slot):
		return SettingsManager.get_action_bindings(slot)
	var bindings: Array = []
	if not InputMap.has_action(slot):
		return bindings
	for event: InputEvent in InputMap.action_get_events(slot):
		if event is InputEventKey:
			bindings.append({"type": "key", "keycode": event.keycode, "physical_keycode": event.physical_keycode})
		elif event is InputEventMouseButton:
			bindings.append({"type": "mouse", "button": event.button_index})
		elif event is InputEventJoypadButton:
			bindings.append({"type": "joy_button", "button": event.button_index})
		elif event is InputEventJoypadMotion:
			bindings.append({"type": "joy_motion", "axis": event.axis, "axis_value": event.axis_value})
	return bindings


static func get_slot_glyph(slot: StringName, controller: bool, style: int = Style.AUTO, device: int = -1) -> Dictionary:
	for value: Variant in get_slot_bindings(slot):
		if not value is Dictionary:
			continue
		var binding: Dictionary = value
		var type: String = String(binding.get("type", ""))
		var is_controller: bool = type == "joy_button" or type == "joy_motion"
		if is_controller == controller:
			var glyph: Dictionary = describe_binding(binding, style, device)
			if not String(glyph.get("label", "")).is_empty():
				return glyph
	return {}


static func describe_binding(binding: Dictionary, style: int = Style.AUTO, device: int = -1, include_texture: bool = true) -> Dictionary:
	var resolved_style: int = resolve_style(style, device)
	var label: String = ""
	var asset: String = ""
	var direction: String = ""
	match String(binding.get("type", "")):
		"key":
			var keycode: int = int(binding.get("keycode", 0))
			if not keycode:
				keycode = int(binding.get("physical_keycode", 0))
			if keycode:
				label = OS.get_keycode_string(keycode)
		"mouse":
			var button: int = int(binding.get("button", 0))
			var labels: Dictionary = {MOUSE_BUTTON_LEFT: "Mouse Left", MOUSE_BUTTON_RIGHT: "Mouse Right", MOUSE_BUTTON_MIDDLE: "Mouse Middle", MOUSE_BUTTON_WHEEL_UP: "Wheel Up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down", MOUSE_BUTTON_WHEEL_LEFT: "Wheel Left", MOUSE_BUTTON_WHEEL_RIGHT: "Wheel Right"}
			label = String(labels.get(button, "Mouse %d" % button)) if button > 0 else ""
		"joy_button":
			var button: int = int(binding.get("button", -1))
			if button >= 0:
				var labels: Dictionary = PS_LABELS if resolved_style == Style.PLAYSTATION else GENERIC_LABELS
				label = String(DPAD_LABELS.get(button, labels.get(button, "Button %d" % button)))
				if resolved_style == Style.PLAYSTATION:
					asset = String(PS_BUTTONS.get(button, ""))
		"joy_motion":
			var axis: int = int(binding.get("axis", -1))
			var value: float = float(binding.get("axis_value", 0.0))
			if axis < 0 or not value:
				return {}
			if axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT:
				label = ("L2" if axis == JOY_AXIS_TRIGGER_LEFT else "R2") if resolved_style == Style.PLAYSTATION else ("LT" if axis == JOY_AXIS_TRIGGER_LEFT else "RT")
				if value < 0.0:
					direction = "−"
					label += " −"
			else:
				var horizontal: bool = axis == JOY_AXIS_LEFT_X or axis == JOY_AXIS_RIGHT_X
				direction = ("←" if value < 0.0 else "→") if horizontal else ("↑" if value < 0.0 else "↓")
				if axis <= JOY_AXIS_RIGHT_Y:
					label = ("Left Stick " if axis <= JOY_AXIS_LEFT_Y else "Right Stick ") + direction
				else:
					label = "Axis %d %s" % [axis, "−" if value < 0.0 else "+"]
			if resolved_style == Style.PLAYSTATION:
				asset = String(PS_AXES.get(axis, ""))
	var texture: Texture2D = null
	if asset and include_texture:
		texture = load(PS_ROOT + asset) as Texture2D
	var caption: String = label if asset == "PS_Start.png" or asset == "PS_Select.png" else ""
	return {"label": label, "texture": texture, "direction": direction, "asset": asset, "caption": caption}

extends CanvasLayer

const CLOSED_PLACEHOLDER_TEXT: String = "Press Enter to chat..."
const OPEN_PLACEHOLDER_TEXT: String = "Type a message..."
const CLOSED_INPUT_HINT: String = "Enter  Open chat"
const OPEN_INPUT_HINT: String = "Enter  Send    Esc  Cancel"
const CHAT_INPUT_ACTIVE_META: StringName = &"chat_input_active"

## Locates the active network session used to send chat messages.
@export var network_session_path: NodePath = NodePath("../NetworkSession")
## Limits the number of messages retained in the visible chat history.
@export var max_history_messages: int = 10

## Contains the chat history and input controls.
@onready var panel: Control = $Panel
## Displays received player and system messages.
@onready var history: RichTextLabel = $Panel/Margin/VBox/History
## Accepts the local player's outgoing message.
@onready var input: LineEdit = $Panel/Margin/VBox/Input
## Displays the available chat controls.
@onready var input_hint: Label = $Panel/Margin/VBox/InputHint

var _open: bool = false
var _history_entries: Array[Dictionary] = []
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	visible = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.focus_mode = Control.FOCUS_NONE
	input.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input.focus_mode = Control.FOCUS_NONE
	input.visible = true
	input.editable = false
	input.placeholder_text = CLOSED_PLACEHOLDER_TEXT
	input_hint.text = CLOSED_INPUT_HINT
	set_process(true)
	set_process_input(true)
	set_process_shortcut_input(true)
	set_process_unhandled_input(true)
	_ensure_chat_input_binds()


func _exit_tree() -> void:
	_set_chat_input_active(false)
	if _open:
		_set_player_ui_blocked(false)


func _process(_delta: float) -> void:
	if not _is_online():
		if _open:
			_close_chat()
		visible = false
		input.visible = false
		return
	if not visible:
		visible = true
	if not input.visible:
		input.visible = true
	if _open:
		_set_chat_input_active(true)
		_maintain_player_input_block()
		if not input.has_focus():
			input.grab_focus()
			input.caret_column = input.text.length()


func _input(event: InputEvent) -> void:
	if not _is_online():
		return
	var enter_pressed: bool = event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)

	if _open:
		if enter_pressed:
			_submit_or_close()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			_close_chat()
			Input.action_release("ui_cancel")
			Input.action_release("pause")
			get_viewport().set_input_as_handled()
		return

	if enter_pressed and _can_open_chat():
		_open_chat()
		get_viewport().set_input_as_handled()


func _shortcut_input(_event: InputEvent) -> void:
	if _open:
		get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	if _open:
		get_viewport().set_input_as_handled()


func _ensure_chat_input_binds() -> void:
	if InputMap.has_action("enter_chat"):
		return

	InputMap.add_action("enter_chat")

	var enter_event: InputEventKey = InputEventKey.new()
	enter_event.keycode = Key.KEY_ENTER
	InputMap.action_add_event("enter_chat", enter_event)

	var keypad_enter_event: InputEventKey = InputEventKey.new()
	keypad_enter_event.keycode = Key.KEY_KP_ENTER
	InputMap.action_add_event("enter_chat", keypad_enter_event)


func _is_online() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer()


func _open_chat() -> void:
	if _open:
		return
	_open = true
	_set_chat_input_active(true)
	_mouse_mode_before_open = Input.get_mouse_mode()
	visible = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	history.mouse_filter = Control.MOUSE_FILTER_STOP
	input.visible = true
	input.editable = true
	input.mouse_filter = Control.MOUSE_FILTER_STOP
	input.focus_mode = Control.FOCUS_CLICK
	input.placeholder_text = OPEN_PLACEHOLDER_TEXT
	input_hint.text = OPEN_INPUT_HINT
	input.grab_focus()
	input.caret_column = input.text.length()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_set_player_ui_blocked(true)


func _close_chat() -> void:
	_open = false
	_set_chat_input_active(false)
	visible = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if input.has_focus():
		input.release_focus()
	input.text = ""
	input.visible = true
	input.editable = false
	input.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input.focus_mode = Control.FOCUS_NONE
	input.placeholder_text = CLOSED_PLACEHOLDER_TEXT
	input_hint.text = CLOSED_INPUT_HINT
	_set_player_ui_blocked(false)

	Input.set_mouse_mode(_mouse_mode_before_open)


func _submit_or_close() -> void:
	var message: String = input.text.strip_edges()
	if message == "":
		_close_chat()
		return
	_send_message(message)
	_close_chat()


func _get_local_player() -> Node:
	var players: Array[Node] = get_tree().get_nodes_in_group("Player")
	for player: Node in players:
		if player != null and (not _is_online() or player.is_multiplayer_authority()):
			return player
	return null


func _can_open_chat() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var focus_owner: Control = viewport.gui_get_focus_owner()
		if (focus_owner is LineEdit or focus_owner is TextEdit) and focus_owner != input:
			return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	for group_name: StringName in [&"ModalMenu", &"PauseMenu"]:
		for menu: Node in tree.get_nodes_in_group(group_name):
			if menu is CanvasItem and is_instance_valid(menu) and (menu as CanvasItem).is_visible_in_tree():
				return false
	return true


func _set_player_ui_blocked(value: bool) -> void:
	var player: Node = _get_local_player()
	if player != null and player.has_method("set_chat_input_blocked"):
		player.call("set_chat_input_blocked", value)
	elif player != null and player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", value)


func _maintain_player_input_block() -> void:
	var player: Node = _get_local_player()
	if player == null:
		return
	if player.has_method("set_chat_input_blocked"):
		player.call("set_chat_input_blocked", true)
	elif player.has_method("set_ui_input_blocked"):
		player.call("set_ui_input_blocked", true)


func _set_chat_input_active(value: bool) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if value:
		tree.set_meta(CHAT_INPUT_ACTIVE_META, true)
	elif tree.has_meta(CHAT_INPUT_ACTIVE_META):
		tree.remove_meta(CHAT_INPUT_ACTIVE_META)


func _get_session() -> Node:
	if network_session_path == NodePath(""):
		return null
	return get_node_or_null(network_session_path)


func _send_message(message: String) -> void:
	var session: Node = _get_session()
	if session == null:
		return
	if session.has_method("send_chat_message"):
		session.call("send_chat_message", message)


func add_message(author: String, message: String) -> void:
	var author_text: String = author.strip_edges()
	if author_text == "":
		author_text = "Player"
	_history_entries.append({
		"system": false,
		"author": author_text,
		"message": message,
	})
	_refresh_history()


func add_system_message(message: String) -> void:
	var text: String = message.strip_edges()
	if text == "":
		return
	_history_entries.append({
		"system": true,
		"message": text,
	})
	_refresh_history()


func _refresh_history() -> void:
	var history_limit: int = max_history_messages
	if history_limit > 0:
		while _history_entries.size() > history_limit:
			_history_entries.pop_front()

	history.clear()
	for entry: Dictionary in _history_entries:
		if bool(entry.get("system", false)):
			history.push_color(Color(0.72, 0.85, 1.0, 1.0))
			history.add_text(String(entry.get("message", "")))
			history.pop()
		else:
			history.push_bold()
			history.push_color(Color(0.56, 0.79, 1.0, 1.0))
			history.add_text("%s:" % String(entry.get("author", "Player")))
			history.pop()
			history.pop()
			history.add_text(" %s" % String(entry.get("message", "")))
		history.add_text("\n")
	history.scroll_to_line(maxi(history.get_line_count() - 1, 0))

@tool
extends EditorPlugin

const LiveEdit = preload("res://LS5Framework/Scripts/Camera/Constraints/CameraConstraintLiveEdit.gd")

var _debugger: EditorDebuggerPlugin = null
var _remaining: float = 0.0
var _sent: Dictionary = {}
var _ready_sessions: Dictionary = {}


func _enter_tree() -> void:
	_debugger = preload("res://addons/ls5_camera_live_edit/debugger.gd").new()
	_debugger.connect("configuration_requested", _on_configuration_requested)
	_debugger.connect("configuration_suspended", _on_configuration_suspended)
	add_debugger_plugin(_debugger)


func _exit_tree() -> void:
	if _debugger:
		remove_debugger_plugin(_debugger)
	_debugger = null


func _on_configuration_requested(session_id: int) -> void:
	_ready_sessions[_debugger.get_session(session_id).get_instance_id()] = true
	_sent.clear()


func _on_configuration_suspended(session_id: int) -> void:
	_ready_sessions.erase(_debugger.get_session(session_id).get_instance_id())


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	_remaining = 0.5
	var active_sessions: Array[EditorDebuggerSession] = []
	for session: EditorDebuggerSession in _debugger.get_sessions():
		if session.is_active() and _ready_sessions.has(session.get_instance_id()):
			active_sessions.append(session)
		elif not session.is_active():
			_ready_sessions.erase(session.get_instance_id())
	if active_sessions.is_empty():
		_sent.clear()
		return
	var root: Node = EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path.is_empty():
		return
	_scan(root, root, active_sessions)


func _scan(root: Node, node: Node, sessions: Array[EditorDebuggerSession]) -> void:
	if node is CameraConstraint:
		var state: Dictionary = LiveEdit.snapshot(node)
		var path: NodePath = root.get_path_to(node)
		var key: String = root.scene_file_path + ":" + String(path)
		var fingerprint: int = hash(state)
		for session: EditorDebuggerSession in sessions:
			var session_key: String = str(session.get_instance_id()) + ":" + key
			if _sent.get(session_key) != fingerprint:
				_sent[session_key] = fingerprint
				session.send_message("ls5_camera_edit:configuration", [root.scene_file_path, path, state])
		return
	for child: Node in node.get_children():
		_scan(root, child, sessions)

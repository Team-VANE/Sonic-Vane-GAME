@tool
extends EditorDebuggerPlugin

signal configuration_requested(session_id: int)
signal configuration_suspended(session_id: int)

func _has_capture(capture: String) -> bool:
	return capture == "ls5_camera_edit"

func _capture(message: String, _data: Array, session_id: int) -> bool:
	if message == "ls5_camera_edit:suspend":
		configuration_suspended.emit(session_id)
		return true
	if message != "ls5_camera_edit:request":
		return false
	configuration_requested.emit(session_id)
	return true

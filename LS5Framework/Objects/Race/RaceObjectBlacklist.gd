extends Node
class_name RaceObjectBlacklist

## Object disabled when the active race matches a blacklisted Race ID.
@export_node_path("Node") var target_path: NodePath = NodePath("..")
## Race IDs that disable the target object while their race is active.
@export var blacklisted_race_ids: PackedStringArray = []

var _object_state: Dictionary = {}
var _blacklist_applied: bool = false


func _ready() -> void:
	add_to_group("RaceObjectBlacklist")
	if Engine.is_editor_hint():
		update_configuration_warnings()


func set_active_race_id(started_race_id: String) -> void:
	var target: Node = _resolve_target()
	if target == null:
		return
	var is_blacklisted: bool = _contains_race_id(started_race_id)
	if is_blacklisted:
		RaceObjectStateController.set_tree_enabled(target, false, _object_state)
		_blacklist_applied = true
	elif _blacklist_applied:
		RaceObjectStateController.set_tree_enabled(target, true, _object_state)
		_blacklist_applied = false


func clear_active_race() -> void:
	if not _blacklist_applied:
		return
	var target: Node = _resolve_target()
	if target != null:
		RaceObjectStateController.set_tree_enabled(target, true, _object_state)
	_blacklist_applied = false


func _contains_race_id(started_race_id: String) -> bool:
	var normalized_started_id: String = started_race_id.strip_edges().to_lower()
	for blacklisted_id in blacklisted_race_ids:
		if String(blacklisted_id).strip_edges().to_lower() == normalized_started_id:
			return true
	return false


func _resolve_target() -> Node:
	if target_path == NodePath(""):
		return get_parent()
	return get_node_or_null(target_path)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if target_path != NodePath("") and get_node_or_null(target_path) == null:
		warnings.append("Target Path must resolve to the object controlled by this blacklist.")
	if blacklisted_race_ids.is_empty():
		warnings.append("Add at least one blacklisted Race ID.")
	for blacklisted_id in blacklisted_race_ids:
		if not GhostDataManager.is_valid_race_id(String(blacklisted_id).strip_edges()):
			warnings.append("Invalid blacklisted Race ID: %s" % String(blacklisted_id))
	return warnings

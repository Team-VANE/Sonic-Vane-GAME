extends Node3D
class_name RaceObjectLayout

## Race ID that enables this layout during race initialization.
@export_placeholder("1-8 letters or digits") var race_id: String = "RACE01"

var _object_state: Dictionary = {}


func _ready() -> void:
	add_to_group("RaceObjectLayout")
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	set_layout_enabled(false)


func matches_race_id(started_race_id: String) -> bool:
	return race_id.strip_edges().to_lower() == started_race_id.strip_edges().to_lower()


func set_active_for_race_id(started_race_id: String) -> void:
	set_layout_enabled(matches_race_id(started_race_id))


func set_layout_enabled(is_enabled: bool) -> void:
	RaceObjectStateController.set_tree_enabled(self, is_enabled, _object_state)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not GhostDataManager.is_valid_race_id(race_id.strip_edges()):
		warnings.append(GhostDataManager.get_race_id_rules_text())
	return warnings

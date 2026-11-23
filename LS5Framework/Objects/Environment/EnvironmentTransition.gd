@tool
extends WorldObject
class_name EnvironmentTransition

## Weather controller affected by this volume. Defaults to the active level's controller.
@export_node_path("Node3D") var environment_system_path: NodePath

@export_group("Time")
## Changes the solar hour when a player enters.
@export var transition_time: bool = true
## Target local solar hour.
@export_range(0.0, 24.0, 0.01) var target_time_hours: float = 18.5
## Solar time blend duration in seconds.
@export_range(0.0, 600.0, 0.1) var time_transition_seconds: float = 2.0
## Takes the shorter route around the solar clock.
@export var shortest_time_path: bool = true

@export_group("Weather")
## Combined weather preset ID from the level's allowed weather list. Empty leaves weather unchanged.
@export var target_weather_id: StringName
## Weather and precipitation blend duration in seconds.
@export_range(0.0, 600.0, 0.1) var weather_transition_seconds: float = 5.0

@export_group("Sky")
## Atmosphere and lighting profile applied on entry.
@export var target_profile: DayNightProfile
## Atmosphere and lighting blend duration in seconds.
@export_range(0.0, 600.0, 0.1) var profile_transition_seconds: float = 5.0


func _on_body_entered(body: Node3D) -> void:
	if not enabled or (require_group and not body.is_in_group(require_group)):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if not transition_time and not target_weather_id and not target_profile:
		return
	var system: EnvironmentWeatherSystem = _resolve_system()
	var cycle: DayNightCycle = system.get_photo_cycle() if system else null
	if not cycle:
		push_warning("%s requires the active level's EnvironmentWeatherSystem." % name)
		return
	if target_weather_id and not system.transition_to_weather_id(target_weather_id, weather_transition_seconds):
		push_warning("%s references a weather preset outside the level's allowed list: %s." % [name, target_weather_id])
		return
	if transition_time:
		cycle.transition_to_time(target_time_hours, time_transition_seconds, shortest_time_path)
	if target_profile:
		cycle.transition_to_profile(target_profile, profile_transition_seconds)
	if one_shot:
		enabled = false
		set_deferred(&"monitoring", false)
	triggered.emit(body)


func _resolve_system() -> EnvironmentWeatherSystem:
	if environment_system_path:
		return get_node_or_null(environment_system_path) as EnvironmentWeatherSystem
	var manager: Node = get_tree().get_first_node_in_group(&"LevelManager")
	var level: Node = manager.call("get_current_level") if manager else get_tree().current_scene
	if not level or not level.is_ancestor_of(self):
		return null
	for node: Node in get_tree().get_nodes_in_group(&"environment_weather_system"):
		if node is EnvironmentWeatherSystem and (node == level or level.is_ancestor_of(node)):
			return node
	return null

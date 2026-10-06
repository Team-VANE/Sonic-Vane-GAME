extends WorldObject
class_name DayNightTransitionTrigger

@export_group("Cycle Reference")
## DayNightCycle affected by this trigger; the day_night_cycle group is used when empty.
@export var target_cycle_path: NodePath

@export_group("Weather Transition")
## Weather preset applied when a local player enters the trigger.
@export var target_weather: DayNightWeather
## Duration of the weather blend in seconds.
@export_range(0.0, 600.0, 0.1) var weather_transition_seconds: float = 5.0

@export_group("Time Transition")
## Changes the cycle time when a local player enters the trigger.
@export var transition_time: bool = false
## Target local solar time in hours.
@export_range(0.0, 24.0, 0.01) var target_time_hours: float = 12.0
## Duration of the time blend in seconds.
@export_range(0.0, 600.0, 0.1) var time_transition_seconds: float = 2.0
## Uses the shorter direction around the 24-hour clock.
@export var shortest_time_path: bool = true

@export_group("Profile Transition")
## Optional atmosphere and lighting profile applied by this trigger.
@export var target_profile: DayNightProfile
## Duration of the profile blend in seconds.
@export_range(0.0, 600.0, 0.1) var profile_transition_seconds: float = 5.0


func _apply_to_player(player: Node3D) -> void:
	if not _is_local_player(player):
		return
	var cycle: DayNightCycle = _resolve_cycle()
	if not cycle:
		push_warning("DayNightTransitionTrigger: target DayNightCycle not found.")
		return
	if target_weather:
		cycle.transition_to_weather(target_weather, weather_transition_seconds)
	if transition_time:
		cycle.transition_to_time(target_time_hours, time_transition_seconds, shortest_time_path)
	if target_profile:
		cycle.transition_to_profile(target_profile, profile_transition_seconds)


func _resolve_cycle() -> DayNightCycle:
	if target_cycle_path != NodePath(""):
		var target: Node = get_node_or_null(target_cycle_path)
		if not target and get_tree() and get_tree().current_scene:
			target = get_tree().current_scene.get_node_or_null(target_cycle_path)
		if target is DayNightCycle:
			return target
	if get_tree():
		return get_tree().get_first_node_in_group(&"day_night_cycle") as DayNightCycle
	return null


func _is_local_player(player: Node3D) -> bool:
	if not player:
		return false
	if multiplayer and multiplayer.has_multiplayer_peer() and player.has_method("is_multiplayer_authority"):
		return player.is_multiplayer_authority()
	return true

class_name TrickSystem
extends Node

enum TrickType {
	NONE,
	BACKFLIP,
	FRONTFLIP,
	LEFT_SPIN,
	RIGHT_SPIN,
	FRONTFLIP_LEFT_SPIN,
	BACKFLIP_LEFT_SPIN,
	BACKFLIP_RIGHT_SPIN,
	FRONTFLIP_RIGHT_SPIN,
	RAIL_FORWARD,
	RAIL_BACKWARD,
	RAIL_FORWARD_CROUCH,
	RAIL_BACKWARD_CROUCH,
	BOUNCE_POGO,
	STOMP_DAREHOG,
	RAIL_FORWARD_CROUCH_FAST,
	RAIL_BACKWARD_CROUCH_FAST
}

enum TrickAxis {
	PITCH,
	YAW,
	DIAGONAL
}

@export_group("Tricks")
@export_subgroup("Names/Air")
@export var trick_name_backflip: String = "Backflip"
@export var trick_name_frontflip: String = "Frontflip"
@export var trick_name_left_spin: String = "Method"
@export var trick_name_right_spin: String = "Indy"
@export var trick_name_frontflip_left_spin: String = "Corkscrew"
@export var trick_name_backflip_left_spin: String = "Misty Flip"
@export var trick_name_backflip_right_spin: String = "Barani"
@export var trick_name_frontflip_right_spin: String = "McTwist"

@export_subgroup("Names/Rail")
@export var trick_name_rail_forward: String = "FS 50/50"
@export var trick_name_rail_backward: String = "BS 50/50"
@export var trick_name_rail_forward_crouch: String = "FS Low Raven"
@export var trick_name_rail_backward_crouch: String = "BS Low Raven"
## Name for a forward rail crouch at or above the fast-crouch speed threshold.
@export var trick_name_rail_forward_crouch_fast: String = "FS Fast Grind"
## Name for a backward rail crouch at or above the fast-crouch speed threshold.
@export var trick_name_rail_backward_crouch_fast: String = "BS Fast Grind"

@export_subgroup("Scores/Air")
@export var score_backflip: float = 100.0
@export var score_frontflip: float = 100.0
@export var score_left_spin: float = 100.0
@export var score_right_spin: float = 100.0
@export var score_frontflip_left_spin: float = 100.0
@export var score_backflip_left_spin: float = 100.0
@export var score_backflip_right_spin: float = 100.0
@export var score_frontflip_right_spin: float = 100.0

@export_subgroup("Scores/Rail")
@export var score_rail_forward: float = 10.0
@export var score_rail_backward: float = 10.0
@export var score_rail_forward_crouch: float = 15.0
@export var score_rail_backward_crouch: float = 15.0

@export_subgroup("Scores/Special")
@export var score_bounce_pogo: float = 0.0
@export var score_stomp_darehog: float = 500.0

@export_subgroup("Audio")

@export var trick_sound: AudioStream = null
@export var perfect_landing_sound: AudioStream = null

@export_range(-80, 24) var trick_sound_volume_db: float = 0.0
@export_range(-80, 24) var perfect_landing_sound_volume_db: float = 0.0

@export_group("Combo Timer")
## Maximum time retained by an active combo.
@export_range(0.1, 5.0, 0.05) var combo_timer_max_seconds: float = 5.0
## Time added by tricks and feats that do not specify an override.
@export_range(0.0, 5.0, 0.05) var combo_timer_default_add_seconds: float = 1.25
## Movement speed required to reach the minimum combo timer drain rate.
@export_range(1.0, 500.0, 1.0, "or_greater") var combo_timer_slowdown_speed: float = 150.0
## Combo timer drain multiplier applied at or above the slowdown speed.
@export_range(0.05, 1.0, 0.05) var combo_timer_minimum_drain_multiplier: float = 0.5
## Rolling speed required to reach the minimum rolling drain multiplier.
@export_range(1.0, 500.0, 1.0, "or_greater") var combo_timer_rolling_slowdown_speed: float = 150.0
## Additional combo timer drain multiplier while rolling at or above the rolling slowdown speed.
@export_range(0.05, 1.0, 0.05) var combo_timer_rolling_minimum_drain_multiplier: float = 0.6

@export_group("Combo Scoring")
## Multiplier added for each distinct trick or feat in the active combo.
@export_range(0.0, 1.0, 0.01) var unique_action_multiplier_step: float = 0.05
## Maximum score multiplier available from action variety.
@export_range(1.0, 10.0, 0.1) var combo_multiplier_max: float = 3.0

@export_group("Staleness")
## Score reduction applied for each repeat of the same authored trick.
@export_range(0.0, 1.0, 0.01) var trick_repeat_score_decay: float = 0.19
## Minimum score multiplier for repeatedly performing the same authored trick.
@export_range(0.0, 1.0, 0.05) var trick_min_score_multiplier: float = 0.05
## Score reduction applied for each repeat of the same feat.
@export_range(0.0, 1.0, 0.05) var feat_repeat_score_decay: float = 0.1
## Minimum score multiplier for repeatedly performing the same feat.
@export_range(0.0, 1.0, 0.05) var feat_min_score_multiplier: float = 0.35

var _trick_audio_player: AudioStreamPlayer = null
var _perfect_landing_audio_player: AudioStreamPlayer = null

class TrickEntry:
	var trick_type: TrickType
	var axis: TrickAxis
	var action_id: StringName
	var display_name: String
	var start_time: float
	var end_time: float
	var duration: float
	var score: float = 0.0

	func _init(p_type: TrickType, p_axis: TrickAxis, p_time: float, p_score: float = 0.0, p_action_id: StringName = &"", p_display_name: String = "") -> void:
		trick_type = p_type
		axis = p_axis
		action_id = p_action_id
		display_name = p_display_name
		start_time = p_time
		end_time = p_time
		duration = 0.0
		score = p_score

class TrickStats:
	var trick_type: TrickType
	var base_value: float = 100.0

	func _init(p_type: TrickType, p_value: float = 100.0) -> void:
		trick_type = p_type
		base_value = p_value

var trick_definitions: Dictionary = {}

func _ready() -> void:
	_initialize_trick_definitions()
	_initialize_audio_players()
	_initialize_trick_stats()

func _initialize_trick_definitions() -> void:
	trick_definitions = {
		TrickType.BACKFLIP: { "axis": TrickAxis.PITCH, "name": trick_name_backflip, "base_value": score_backflip },
		TrickType.FRONTFLIP: { "axis": TrickAxis.PITCH, "name": trick_name_frontflip, "base_value": score_frontflip },
		TrickType.LEFT_SPIN: { "axis": TrickAxis.YAW, "name": trick_name_left_spin, "base_value": score_left_spin },
		TrickType.RIGHT_SPIN: { "axis": TrickAxis.YAW, "name": trick_name_right_spin, "base_value": score_right_spin },
		TrickType.FRONTFLIP_LEFT_SPIN: { "axis": TrickAxis.DIAGONAL, "name": trick_name_frontflip_left_spin, "base_value": score_frontflip_left_spin },
		TrickType.BACKFLIP_LEFT_SPIN: { "axis": TrickAxis.DIAGONAL, "name": trick_name_backflip_left_spin, "base_value": score_backflip_left_spin },
		TrickType.BACKFLIP_RIGHT_SPIN: { "axis": TrickAxis.DIAGONAL, "name": trick_name_backflip_right_spin, "base_value": score_backflip_right_spin },
		TrickType.FRONTFLIP_RIGHT_SPIN: { "axis": TrickAxis.DIAGONAL, "name": trick_name_frontflip_right_spin, "base_value": score_frontflip_right_spin },
		TrickType.RAIL_FORWARD: { "axis": TrickAxis.YAW, "name": trick_name_rail_forward, "base_value": score_rail_forward },
		TrickType.RAIL_BACKWARD: { "axis": TrickAxis.YAW, "name": trick_name_rail_backward, "base_value": score_rail_backward },
		TrickType.RAIL_FORWARD_CROUCH: { "axis": TrickAxis.YAW, "name": trick_name_rail_forward_crouch, "base_value": score_rail_forward_crouch },
		TrickType.RAIL_BACKWARD_CROUCH: { "axis": TrickAxis.YAW, "name": trick_name_rail_backward_crouch, "base_value": score_rail_backward_crouch },
		TrickType.RAIL_FORWARD_CROUCH_FAST: { "axis": TrickAxis.YAW, "name": trick_name_rail_forward_crouch_fast, "base_value": score_rail_forward_crouch },
		TrickType.RAIL_BACKWARD_CROUCH_FAST: { "axis": TrickAxis.YAW, "name": trick_name_rail_backward_crouch_fast, "base_value": score_rail_backward_crouch },
		TrickType.BOUNCE_POGO: { "axis": TrickAxis.PITCH, "name": "POGO!", "base_value": score_bounce_pogo },
		TrickType.STOMP_DAREHOG: { "axis": TrickAxis.PITCH, "name": "DAREHOG!", "base_value": score_stomp_darehog }
	}

func update_trick_definitions() -> void:
	_initialize_trick_definitions()

func update_audio_streams() -> void:
	_initialize_audio_players()

func _initialize_audio_players() -> void:
	if trick_sound != null:
		_trick_audio_player = AudioStreamPlayer.new()
		_trick_audio_player.stream = trick_sound
		_trick_audio_player.bus = "UI"
		_trick_audio_player.volume_db = trick_sound_volume_db
		add_child(_trick_audio_player)

	if perfect_landing_sound != null:
		_perfect_landing_audio_player = AudioStreamPlayer.new()
		_perfect_landing_audio_player.stream = perfect_landing_sound
		_perfect_landing_audio_player.bus = "UI"
		_perfect_landing_audio_player.volume_db = perfect_landing_sound_volume_db
		add_child(_perfect_landing_audio_player)

func _initialize_trick_stats() -> void:
	for trick_type in trick_definitions.keys():
		trick_stats[trick_type] = TrickStats.new(trick_type, trick_definitions[trick_type]["base_value"])

var current_air_tricks: Array = []
var trick_stats: Dictionary = {}
var action_staleness_counts: Dictionary = {}
var character_presentation_profile: PlayerCharacterVisualProfile = null
var combo_multiplier: float = 1.0
var total_score: float = 0.0
var combo_time_remaining: float = 0.0

var combo_system_enabled: bool = true

signal trick_performed(trick_type: TrickType, count: int)
signal combo_updated(multiplier: float, score: float)
signal trick_sequence_updated(trick_list: Array)
signal combo_timer_updated(time_remaining: float, maximum_time: float)
signal combo_failed(final_score: float)

func update_combo_timer(delta: float, movement_speed: float = 0.0, is_rolling: bool = false) -> Dictionary:
	if not combo_system_enabled or combo_time_remaining <= 0.0:
		return {}
	var speed_ratio: float = clampf(
		maxf(movement_speed, 0.0) / maxf(combo_timer_slowdown_speed, 0.001),
		0.0,
		1.0
	)
	var minimum_drain_multiplier: float = clampf(combo_timer_minimum_drain_multiplier, 0.05, 1.0)
	var drain_multiplier: float = lerpf(1.0, minimum_drain_multiplier, speed_ratio)
	if is_rolling:
		var rolling_speed_ratio: float = clampf(
			maxf(movement_speed, 0.0) / maxf(combo_timer_rolling_slowdown_speed, 0.001),
			0.0,
			1.0
		)
		var rolling_minimum_drain_multiplier: float = clampf(
			combo_timer_rolling_minimum_drain_multiplier,
			0.05,
			1.0
		)
		drain_multiplier *= lerpf(1.0, rolling_minimum_drain_multiplier, rolling_speed_ratio)
	combo_time_remaining = maxf(combo_time_remaining - maxf(delta, 0.0) * drain_multiplier, 0.0)
	combo_timer_updated.emit(combo_time_remaining, combo_timer_max_seconds)
	if combo_time_remaining <= 0.0:
		return finish_combo()
	return {}

func finish_combo() -> Dictionary:
	if not combo_system_enabled or current_air_tricks.is_empty():
		return {}
	return _finish_combo()

func start_airborne_segment() -> void:
	pass

func end_airborne_segment() -> void:
	pass

func cancel_combo(failed: bool = false) -> void:
	if failed and not current_air_tricks.is_empty():
		_update_combo()
		combo_failed.emit(total_score)
	current_air_tricks.clear()
	combo_multiplier = 1.0
	total_score = 0.0
	combo_time_remaining = 0.0
	reset_staleness()
	if not failed:
		trick_sequence_updated.emit(current_air_tricks)
		combo_updated.emit(combo_multiplier, total_score)
	combo_timer_updated.emit(combo_time_remaining, combo_timer_max_seconds)

func register_trick(trick_type: TrickType, current_time: float, timer_add_seconds: float = -1.0) -> void:
	if not combo_system_enabled:
		return
	if trick_type == TrickType.NONE:
		return

	if trick_type == TrickType.BOUNCE_POGO:
		reset_air_trick_staleness()
		if current_air_tricks.is_empty():
			return
	var starting_combo: bool = current_air_tricks.is_empty()
	var action_id: StringName = _get_trick_action_id(trick_type)
	_refresh_other_action_staleness(action_id)

	var stats: TrickStats = trick_stats[trick_type]
	var repeat_count: int = int(action_staleness_counts.get(action_id, 0))
	var mult: float = _get_staleness_multiplier(
		repeat_count,
		trick_repeat_score_decay,
		trick_min_score_multiplier
	)
	var entry_score: float = stats.base_value * mult

	var trick_name: String = get_trick_name(trick_type)
	var entry: TrickEntry = TrickEntry.new(trick_type, trick_definitions[trick_type]["axis"], current_time, entry_score, action_id, trick_name)
	current_air_tricks.append(entry)

	action_staleness_counts[action_id] = repeat_count + 1

	if trick_type != TrickType.BOUNCE_POGO:
		_play_trick_sound(mult)
	var time_to_add: float = combo_timer_default_add_seconds if timer_add_seconds < 0.0 else timer_add_seconds
	_add_combo_time(time_to_add, starting_combo)
	_update_combo()
	_emit_trick_signals(trick_type, repeat_count + 1)
	push_warning("register_trick: %s count=%d score=%.2f" % [get_trick_name(trick_type), repeat_count + 1, entry_score])

func register_feat(feat_id: StringName, display_name: String, base_score: float, timer_add_seconds: float = -1.0) -> void:
	if not combo_system_enabled or feat_id == &"" or display_name.is_empty():
		return
	var starting_combo: bool = current_air_tricks.is_empty()
	_refresh_other_action_staleness(feat_id)
	var repeat_count: int = int(action_staleness_counts.get(feat_id, 0))
	var score_multiplier: float = _get_staleness_multiplier(
		repeat_count,
		feat_repeat_score_decay,
		feat_min_score_multiplier
	)
	var entry_score: float = maxf(base_score, 0.0) * score_multiplier
	var entry: TrickEntry = TrickEntry.new(TrickType.NONE, TrickAxis.PITCH, Time.get_ticks_msec() / 1000.0, entry_score, feat_id, display_name)
	current_air_tricks.append(entry)
	action_staleness_counts[feat_id] = repeat_count + 1
	var time_to_add: float = combo_timer_default_add_seconds if timer_add_seconds < 0.0 else timer_add_seconds
	_add_combo_time(time_to_add, starting_combo)
	_update_combo()
	combo_updated.emit(combo_multiplier, total_score)
	trick_sequence_updated.emit(current_air_tricks)

func _add_combo_time(seconds: float, starting_combo: bool = false) -> void:
	if starting_combo:
		combo_time_remaining = combo_timer_max_seconds
	else:
		combo_time_remaining = minf(combo_time_remaining + maxf(seconds, 0.0), combo_timer_max_seconds)
	combo_timer_updated.emit(combo_time_remaining, combo_timer_max_seconds)

func _finish_combo() -> Dictionary:
	if current_air_tricks.is_empty():
		return {}
	_update_combo()
	var final_score: float = total_score
	var final_entries: Array[String] = get_combo_list_entries()
	combo_updated.emit(combo_multiplier, total_score)
	play_combo_complete_sound()
	current_air_tricks.clear()
	combo_multiplier = 1.0
	total_score = 0.0
	combo_time_remaining = 0.0
	reset_staleness()
	combo_timer_updated.emit(combo_time_remaining, combo_timer_max_seconds)
	return {"score": final_score, "entries": final_entries}

func _play_trick_sound(volume_multiplier: float = 1.0) -> void:
	# Check if player is grinding to avoid sound spam
	var p = get_parent()
	if p != null and p.has_method("get"):
		var rail_active = p.get("_rail_active")
		if rail_active is bool and bool(rail_active):
			return

	if _trick_audio_player != null:
		# More subtle staleness scaling for audio:
		# Remap the multiplier so it only drops to ~50% linear volume (approx -6dB)
		var subtle_mult: float = lerp(0.5, 1.0, volume_multiplier)
		var mult_db: float = linear_to_db(subtle_mult)
			
		_trick_audio_player.volume_db = trick_sound_volume_db + mult_db
		
		# Very slight pitch down as it grows stale
		# Range: 1.0 (fresh) down to 0.9 (stale)
		_trick_audio_player.pitch_scale = lerp(0.9, 1.0, volume_multiplier)
		
		_trick_audio_player.play()

func play_combo_complete_sound() -> void:
	if _perfect_landing_audio_player != null:
		_perfect_landing_audio_player.volume_db = perfect_landing_sound_volume_db
		_perfect_landing_audio_player.play()

func _update_combo() -> void:
	var unique_types: Dictionary = {}
	var base_score: float = 0.0
	
	for trick: TrickEntry in current_air_tricks:
		if trick.score > 0.0:
			unique_types[trick.action_id] = true
		base_score += trick.score

	combo_multiplier = 1.0 + (float(unique_types.size()) * maxf(unique_action_multiplier_step, 0.0))
	combo_multiplier = minf(combo_multiplier, maxf(combo_multiplier_max, 1.0))
	
	total_score = base_score * combo_multiplier

func calculate_final_score() -> float:
	if not combo_system_enabled:
		return 0.0
	_update_combo()
	return total_score

func has_scoring_tricks() -> bool:
	for trick in current_air_tricks:
		if trick.score > 0.0:
			return true
	return false

func get_trick_name(trick_type: TrickType) -> String:
	if not trick_definitions.has(trick_type):
		return ""
	var fallback_name: String = str(trick_definitions[trick_type]["name"])
	if character_presentation_profile == null:
		return fallback_name
	return character_presentation_profile.get_trick_display_name(
		_get_trick_profile_id(trick_type),
		fallback_name
	)

func set_character_presentation_profile(profile: PlayerCharacterVisualProfile) -> void:
	character_presentation_profile = profile

func get_trick_list_string() -> String:
	return " + ".join(get_combo_list_entries())

func get_combo_list_entries() -> Array[String]:
	var grouped_entries: Array[String] = []
	var last_id: StringName = &""
	var last_name: String = ""
	var last_count: int = 0
	for entry: TrickEntry in current_air_tricks:
		if entry.action_id == last_id and entry.display_name == last_name:
			last_count += 1
			continue
		if last_id != &"":
			grouped_entries.append(_format_combo_line(last_name, last_count))
		last_id = entry.action_id
		last_name = entry.display_name
		last_count = 1
	if last_id != &"":
		grouped_entries.append(_format_combo_line(last_name, last_count))
	return grouped_entries

func _format_combo_line(display_name: String, count: int) -> String:
	if count > 1:
		return "%s x%d" % [display_name, count]
	return display_name

func _sort_tricks_by_count(a: TrickType, b: TrickType) -> bool:
	var a_count: int = 0
	var b_count: int = 0

	for trick in current_air_tricks:
		if trick.trick_type == a:
			a_count += 1
		if trick.trick_type == b:
			b_count += 1

	return a_count > b_count

func _emit_trick_signals(trick_type: TrickType, count: int) -> void:
	trick_performed.emit(trick_type, count)
	combo_updated.emit(combo_multiplier, total_score)
	trick_sequence_updated.emit(current_air_tricks)
	push_warning("combo emitted multiplier=%f total_score=%f" % [combo_multiplier, total_score])

func reset_staleness() -> void:
	action_staleness_counts.clear()

func _refresh_other_action_staleness(performed_action_id: StringName) -> void:
	for tracked_action_id: StringName in action_staleness_counts:
		if tracked_action_id == performed_action_id:
			continue
		var stale_count: int = int(action_staleness_counts[tracked_action_id])
		action_staleness_counts[tracked_action_id] = maxi(stale_count - 1, 0)

func _get_staleness_multiplier(repeat_count: int, score_decay: float, minimum_multiplier: float) -> float:
	return maxf(
		1.0 - float(maxi(repeat_count, 0)) * clampf(score_decay, 0.0, 1.0),
		clampf(minimum_multiplier, 0.0, 1.0)
	)

func _get_trick_action_id(trick_type: TrickType) -> StringName:
	if trick_type == TrickType.RAIL_FORWARD_CROUCH_FAST:
		return StringName("trick_%d" % int(TrickType.RAIL_FORWARD_CROUCH))
	if trick_type == TrickType.RAIL_BACKWARD_CROUCH_FAST:
		return StringName("trick_%d" % int(TrickType.RAIL_BACKWARD_CROUCH))
	return StringName("trick_%d" % int(trick_type))

func _get_trick_profile_id(trick_type: TrickType) -> StringName:
	match trick_type:
		TrickType.BACKFLIP: return &"backflip"
		TrickType.FRONTFLIP: return &"frontflip"
		TrickType.LEFT_SPIN: return &"left_spin"
		TrickType.RIGHT_SPIN: return &"right_spin"
		TrickType.FRONTFLIP_LEFT_SPIN: return &"frontflip_left_spin"
		TrickType.BACKFLIP_LEFT_SPIN: return &"backflip_left_spin"
		TrickType.BACKFLIP_RIGHT_SPIN: return &"backflip_right_spin"
		TrickType.FRONTFLIP_RIGHT_SPIN: return &"frontflip_right_spin"
		TrickType.RAIL_FORWARD: return &"rail_forward"
		TrickType.RAIL_BACKWARD: return &"rail_backward"
		TrickType.RAIL_FORWARD_CROUCH: return &"rail_forward_crouch"
		TrickType.RAIL_BACKWARD_CROUCH: return &"rail_backward_crouch"
		TrickType.RAIL_FORWARD_CROUCH_FAST: return &"rail_forward_crouch_fast"
		TrickType.RAIL_BACKWARD_CROUCH_FAST: return &"rail_backward_crouch_fast"
		TrickType.BOUNCE_POGO: return &"bounce_pogo"
		TrickType.STOMP_DAREHOG: return &"stomp_darehog"
	return &""

func reset_air_trick_staleness() -> void:
	# SUMMARY: Reset staleness for air-based tricks (flips/spins).
	# This allows players to refresh their air trick scores by touching a rail.
	var air_tricks = [
		TrickType.BACKFLIP, TrickType.FRONTFLIP, TrickType.LEFT_SPIN, TrickType.RIGHT_SPIN,
		TrickType.FRONTFLIP_LEFT_SPIN, TrickType.BACKFLIP_LEFT_SPIN, TrickType.BACKFLIP_RIGHT_SPIN, TrickType.FRONTFLIP_RIGHT_SPIN
	]
	for trick_type in air_tricks:
		var action_id: StringName = _get_trick_action_id(trick_type)
		if action_staleness_counts.has(action_id):
			action_staleness_counts[action_id] = 0

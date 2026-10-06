extends Resource
class_name ItemMonitorReward

enum RewardType {
	NOTHING,
	RINGS,
	SPECIAL_ITEM,
	FLIGHT_GAUGE,
	ABILITY_GAUGE,
	CUSTOM_RESOURCE,
	SPEED_SHOES,
	RANDOM_RINGS,
	INVINCIBILITY,
}

## Resource behavior used when the monitor is collected.
@export_enum("Nothing", "Rings", "Special Item", "Flight Gauge", "Ability Gauge", "Custom Resource", "Speed Shoes", "Random Rings", "Invincibility")
var reward_type: int = RewardType.NOTHING
## Quantity granted by this reward. Fixed Ring rewards are rounded to an integer. Random Rings and Speed Shoes do not use this value.
@export var amount: float = 0.0
## Item, ability, or custom resource identifier used by the selected reward type.
@export var resource_id: StringName = &""
## Optional player method used by Special Item or Custom Resource rewards. It receives resource_id and amount.
@export var grant_method: StringName = &""

@export_group("Random Rings")
## Possible ring amounts granted by a Random Rings reward.
@export var random_ring_pool: PackedInt32Array = PackedInt32Array([5, 10, 20, 40])
## Uses a fixed ring amount instead of RNG while the collecting player is in a Ring Race.
@export var fixed_amount_in_ring_race: bool = true
## Ring amount granted in a Ring Race when fixed_amount_in_ring_race is enabled.
@export_range(1, 9999, 1) var ring_race_fixed_amount: int = 10

@export_group("Speed Shoes")
## Duration override for Speed Shoes. Values at or below zero use the player's configured duration.
@export var speed_shoes_duration_override: float = -1.0
## Duration override for Invincibility. Values at or below zero use the player's configured duration.
@export var invincibility_duration_override: float = -1.0

@export_group("Display")
## Optional scene displayed inside the monitor for this reward.
@export var display_scene: PackedScene
## Local position of the display scene inside the monitor.
@export var display_position: Vector3 = Vector3.ZERO
## Local Euler rotation of the display scene inside the monitor.
@export var display_rotation_degrees: Vector3 = Vector3.ZERO
## Local scale of the display scene inside the monitor.
@export var display_scale: Vector3 = Vector3.ONE

var _last_notification_amount: float = 0.0


func is_configured() -> bool:
	if reward_type == RewardType.SPEED_SHOES or reward_type == RewardType.INVINCIBILITY:
		return true
	if reward_type == RewardType.RANDOM_RINGS:
		return not _get_positive_random_ring_pool().is_empty()
	return reward_type != RewardType.NOTHING and amount > 0.0


func get_item_id() -> StringName:
	match reward_type:
		RewardType.RINGS, RewardType.RANDOM_RINGS:
			return &"rings"
		RewardType.FLIGHT_GAUGE:
			return &"flight_gauge"
		RewardType.ABILITY_GAUGE:
			return resource_id if resource_id != &"" else &"ability_gauge"
		RewardType.SPECIAL_ITEM, RewardType.CUSTOM_RESOURCE:
			return resource_id
		RewardType.SPEED_SHOES:
			return &"speed_shoes"
		RewardType.INVINCIBILITY:
			return &"invincibility"
	return &""


func get_audio_item_id() -> StringName:
	return get_item_id()


func get_notification_amount() -> float:
	if reward_type == RewardType.RANDOM_RINGS:
		return _last_notification_amount
	return 1.0 if reward_type == RewardType.SPEED_SHOES or reward_type == RewardType.INVINCIBILITY else amount


func get_monitor_quantity_text(player: Node = null) -> String:
	match reward_type:
		RewardType.RINGS:
			var ring_amount: int = int(round(amount))
			return "" if ring_amount == 1 else str(ring_amount)
		RewardType.RANDOM_RINGS:
			if fixed_amount_in_ring_race and _is_player_in_ring_race(player):
				return str(max(ring_race_fixed_amount, 1))
			return "?"
	return ""


func grant_to(player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not is_configured():
		return false

	match reward_type:
		RewardType.RINGS:
			var ring_amount: int = int(round(amount))
			if ring_amount <= 0 or not player.has_method("add_rings"):
				return false
			player.call("add_rings", ring_amount)
			return true
		RewardType.RANDOM_RINGS:
			var random_ring_amount: int = _get_random_ring_amount(player)
			if random_ring_amount <= 0 or not player.has_method("add_rings"):
				return false
			_last_notification_amount = float(random_ring_amount)
			player.call("add_rings", random_ring_amount)
			return true
		RewardType.FLIGHT_GAUGE:
			if not player.has_method("add_flight_time"):
				return false
			player.call("add_flight_time", amount)
			return true
		RewardType.ABILITY_GAUGE:
			if not player.has_method("add_ability_gauge"):
				return false
			var ability_result: Variant = player.call("add_ability_gauge", resource_id, amount)
			return not (ability_result is bool) or bool(ability_result)
		RewardType.SPECIAL_ITEM, RewardType.CUSTOM_RESOURCE:
			return _grant_named_resource(player)
		RewardType.SPEED_SHOES:
			if not player.has_method("apply_speed_shoes"):
				return false
			var speed_shoes_result: Variant = player.call("apply_speed_shoes", speed_shoes_duration_override)
			return not (speed_shoes_result is bool) or bool(speed_shoes_result)
		RewardType.INVINCIBILITY:
			if not player.has_method("apply_invincibility"):
				return false
			var invincibility_result: Variant = player.call("apply_invincibility", invincibility_duration_override)
			return not (invincibility_result is bool) or bool(invincibility_result)

	return false


func _get_random_ring_amount(player: Node) -> int:
	if fixed_amount_in_ring_race and _is_player_in_ring_race(player):
		return max(ring_race_fixed_amount, 1)
	var positive_pool: PackedInt32Array = _get_positive_random_ring_pool()
	if positive_pool.is_empty():
		return 0
	var pool_index: int = randi_range(0, positive_pool.size() - 1)
	return positive_pool[pool_index]


func _get_positive_random_ring_pool() -> PackedInt32Array:
	var positive_pool: PackedInt32Array = PackedInt32Array()
	for ring_amount: int in random_ring_pool:
		if ring_amount > 0:
			positive_pool.append(ring_amount)
	return positive_pool


func _is_player_in_ring_race(player: Node) -> bool:
	if player == null or not is_instance_valid(player) or player.get_tree() == null:
		return false
	for race_start: Node in player.get_tree().get_nodes_in_group("RaceStart"):
		if race_start == null or not is_instance_valid(race_start):
			continue
		if not race_start.has_method("is_active_for_player") or not race_start.has_method("is_ring_race"):
			continue
		var is_active_value = race_start.call("is_active_for_player", player)
		var is_ring_race_value = race_start.call("is_ring_race")
		if is_active_value is bool and bool(is_active_value) and is_ring_race_value is bool and bool(is_ring_race_value):
			return true
	return false


func _grant_named_resource(player: Node) -> bool:
	if resource_id == &"":
		return false
	if grant_method != &"":
		if not player.has_method(grant_method):
			return false
		var method_result: Variant = player.call(grant_method, resource_id, amount)
		return not (method_result is bool) or bool(method_result)
	if not player.has_method("add_item_resource"):
		return false
	player.call("add_item_resource", resource_id, amount)
	return true

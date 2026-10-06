extends Area3D
class_name GravityModifier

@export_group("Activation")
## Enables gravity modifier activation.
@export var active: bool = true
## Primary group accepted as a player trigger.
@export var require_group_primary: StringName = &"Player"
## Secondary group accepted as a player trigger.
@export var require_group_secondary: StringName = &"player"
## Physics layers containing optional non-player gravity followers.
@export_flags_3d_physics var gravity_follower_collision_mask: int = 130
## Applies the modifier to every available player when one player enters.
@export var affects_all_players: bool = false
## Delay before the same body can activate this modifier again.
@export var rehit_cooldown: float = 0.25

@export_group("Gravity")
## Up direction opposite the gravity pull.
@export var gravity_up_direction: Vector3 = Vector3.UP
## Transforms the configured up direction by this object's global basis.
@export var direction_is_local: bool = true
## Multiplier applied to each affected body's base gravity strength.
@export var gravity_multiplier: float = 1.0
## Duration in seconds. Values at or below zero remain active indefinitely.
@export var duration: float = -1.0
## Higher priority modifiers replace lower priority modifiers.
@export var gravity_priority: int = 0
## Adds overlapping planetary pulls to this directional modifier.
@export var blend_with_planetary_gravity: bool = false

@export_group("Clearing")
## Clears this modifier when the affected body dies.
@export var clear_on_death: bool = true
## Clears this modifier when the affected body respawns.
@export var clear_on_respawn: bool = true
## Clears this modifier during level restart or level cleanup.
@export var clear_on_level_restart: bool = true
## Clears this modifier during race restart or race cleanup.
@export var clear_on_race_cleanup: bool = true

var _body_cooldowns: Dictionary = {}


func _ready() -> void:
	collision_mask |= gravity_follower_collision_mask
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _body_cooldowns.is_empty():
		return
	var expired_ids: Array = []
	for body_id in _body_cooldowns.keys():
		var remaining: float = max(float(_body_cooldowns.get(body_id, 0.0)) - delta, 0.0)
		if remaining <= 0.0:
			expired_ids.append(body_id)
		else:
			_body_cooldowns[body_id] = remaining
	for body_id in expired_ids:
		_body_cooldowns.erase(body_id)


func _on_body_entered(body: Node3D) -> void:
	if not active or not _is_gravity_body(body):
		return
	var body_id: int = body.get_instance_id()
	if float(_body_cooldowns.get(body_id, 0.0)) > 0.0:
		return
	if affects_all_players and _is_player(body):
		for player in _get_all_players():
			_apply_to_body(player)
	else:
		_apply_to_body(body)
	_body_cooldowns[body_id] = max(rehit_cooldown, 0.0)


func _apply_to_body(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.has_method("apply_gravity_modifier"):
		return
	var up: Vector3 = gravity_up_direction
	if direction_is_local:
		up = global_transform.basis * up
	if up.length() < 0.001:
		return
	body.call(
		"apply_gravity_modifier",
		self,
		up.normalized(),
		max(gravity_multiplier, 0.0),
		duration,
		gravity_priority,
		blend_with_planetary_gravity,
		clear_on_death,
		clear_on_respawn,
		clear_on_level_restart,
		clear_on_race_cleanup
	)


func _get_all_players() -> Array[Node]:
	var players: Array[Node] = []
	if get_tree() == null:
		return players
	for group_name: StringName in [require_group_primary, require_group_secondary]:
		if group_name == &"":
			continue
		for candidate in get_tree().get_nodes_in_group(group_name):
			if candidate is Node and not players.has(candidate):
				players.append(candidate)
	return players


func _is_player(body: Node) -> bool:
	if body == null or not body.has_method("apply_gravity_modifier"):
		return false
	if require_group_primary != &"" and body.is_in_group(require_group_primary):
		return true
	if require_group_secondary != &"" and body.is_in_group(require_group_secondary):
		return true
	return require_group_primary == &"" and require_group_secondary == &""


func _is_gravity_body(body: Node) -> bool:
	if _is_player(body):
		return true
	if body == null or not body.has_method("is_gravity_pull_enabled"):
		return false
	var enabled_value: Variant = body.call("is_gravity_pull_enabled")
	return enabled_value is bool and bool(enabled_value) and body.has_method("apply_gravity_modifier")


func reset_for_race_restart() -> void:
	_body_cooldowns.clear()

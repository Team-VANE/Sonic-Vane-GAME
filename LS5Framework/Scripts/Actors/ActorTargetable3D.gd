extends Marker3D
class_name ActorTargetable3D

@export_group("Homing")
## Registers this point as a homing target while the actor is alive.
@export var homing_target_enabled: bool = true
## Overrides the player's post-hit pop-up speed when zero or greater.
@export var pop_up_speed_override: float = -1.0

@export_group("Attack Magnetism")
## Registers this point as an attack-magnetism target while the actor is alive.
@export var attack_magnetism_enabled: bool = true
## Uses these target settings instead of player attack-magnetism settings.
@export var attack_magnetism_override_player_settings: bool = false
## Maximum attack-magnetism range when target settings override the player.
@export var attack_magnetism_range: float = 24.0
## Detection cone angle when target settings override the player.
@export var attack_magnetism_detection_angle_deg: float = 40.0
## Multiplier applied to the resolved magnetism strength.
@export var attack_magnetism_strength_multiplier: float = 1.0
## Pull strength when target settings override the player.
@export var attack_magnetism_strength: float = 46.0
## Minimum speed preserved during attack magnetism.
@export var attack_magnetism_min_speed: float = 0.0
## Maximum spatial-cell refresh frequency while moving.
@export var spatial_update_rate_hz: float = 20.0

var _registered: bool = false
var _cell_timer: float = 0.0


func setup(_actor: Node3D) -> void:
	set_meta(&"npc_affiliation", &"enemy")
	set_enabled(true)


func _exit_tree() -> void:
	_set_registered(false)


func set_enabled(value: bool) -> void:
	visible = value
	_set_registered(value)


func physics_tick(delta: float, moved: bool) -> void:
	if not _registered or not moved:
		return
	if spatial_update_rate_hz > 0.0:
		_cell_timer = max(_cell_timer - delta, 0.0)
		if _cell_timer > 0.0:
			return
		_cell_timer = 1.0 / spatial_update_rate_hz
	var manager: Node = get_node_or_null("/root/HomingTargetManager")
	if manager == null:
		return
	if homing_target_enabled and manager.has_method("update_target"):
		manager.call("update_target", self)
	if attack_magnetism_enabled and manager.has_method("update_attack_magnetism_target"):
		manager.call("update_attack_magnetism_target", self)


func get_homing_target_position(_origin: Vector3 = Vector3.ZERO) -> Vector3:
	return global_position


func get_attack_magnetism_position(_context: Variant = null) -> Vector3:
	return global_position


func on_homing_hit(_player: Node, _jump_held: bool) -> bool:
	return false


func _set_registered(value: bool) -> void:
	if value == _registered:
		return
	_registered = value
	var manager: Node = get_node_or_null("/root/HomingTargetManager")
	if value:
		if homing_target_enabled:
			add_to_group(&"HomingTarget")
			if manager and manager.has_method("register"):
				manager.call("register", self)
		if attack_magnetism_enabled:
			add_to_group(&"AttackMagnetismTarget")
			if manager and manager.has_method("register_attack_magnetism_target"):
				manager.call("register_attack_magnetism_target", self)
		return
	if is_in_group(&"HomingTarget"):
		remove_from_group(&"HomingTarget")
	if is_in_group(&"AttackMagnetismTarget"):
		remove_from_group(&"AttackMagnetismTarget")
	if manager and manager.has_method("unregister"):
		manager.call("unregister", self)
	if manager and manager.has_method("unregister_attack_magnetism_target"):
		manager.call("unregister_attack_magnetism_target", self)

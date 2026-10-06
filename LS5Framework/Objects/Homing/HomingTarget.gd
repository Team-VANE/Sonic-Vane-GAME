extends Area3D

@export var enabled: bool = true
@export var pop_up_speed_override: float = -1.0
@export var pass_through: bool = false

@export_group("Attack Magnetism")
## Allows attack magnetism to use this target.
@export var attack_magnetism_enabled: bool = true
## Uses the target settings below instead of the player's attack magnetism settings.
@export var attack_magnetism_override_player_settings: bool = false
## Targeting range used when player settings are overridden.
@export var attack_magnetism_range: float = 22.0
## Detection angle used when player settings are overridden.
@export var attack_magnetism_detection_angle_deg: float = 38.0
## Pull strength multiplier applied after player or override strength is resolved.
@export var attack_magnetism_strength_multiplier: float = 1.0
## Pull strength used when player settings are overridden.
@export var attack_magnetism_strength: float = 42.0
## Minimum speed preserved while attack magnetism adjusts direction.
@export var attack_magnetism_min_speed: float = 0.0
## Updates the attack magnetism spatial cell during physics frames.
@export var attack_magnetism_update_cell_each_physics_frame: bool = true
## Maximum spatial-cell refresh rate for moving attack magnetism targets.
@export var attack_magnetism_cell_update_rate_hz: float = 20.0

var _attack_magnetism_cell_update_timer: float = 0.0


func _ready() -> void:
	if not is_in_group("HomingTarget"):
		add_to_group("HomingTarget")
	if attack_magnetism_enabled and not is_in_group("AttackMagnetismTarget"):
		add_to_group("AttackMagnetismTarget")
	# Register with HomingTargetManager if available to avoid group scans
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("register"):
		mgr.register(self)
	if attack_magnetism_enabled and mgr and mgr.has_method("register_attack_magnetism_target"):
		mgr.register_attack_magnetism_target(self)


func _exit_tree() -> void:
	# Unregister from manager if present
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("unregister"):
		mgr.unregister(self)
	if mgr and mgr.has_method("unregister_attack_magnetism_target"):
		mgr.unregister_attack_magnetism_target(self)


func _physics_process(delta: float) -> void:
	if not attack_magnetism_enabled:
		return
	if not attack_magnetism_update_cell_each_physics_frame:
		return
	if attack_magnetism_cell_update_rate_hz > 0.0:
		_attack_magnetism_cell_update_timer -= delta
		if _attack_magnetism_cell_update_timer > 0.0:
			return
		_attack_magnetism_cell_update_timer = 1.0 / attack_magnetism_cell_update_rate_hz
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("update_attack_magnetism_target"):
		mgr.update_attack_magnetism_target(self)


func get_attack_magnetism_position(_context) -> Vector3:
	return global_position

func on_homing_hit(_player: Node, _jump_held: bool) -> bool:
	# Signal to the player that we handle the impact.
	# If pass_through is enabled, the player keeps their homing velocity and passes through.
	return pass_through

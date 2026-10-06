extends "res://LS5Framework/Scripts/Player/SonicPlayer.gd"
class_name RivalActorPlayer

const SonicPlayerRef = preload("res://LS5Framework/Scripts/Player/SonicPlayer.gd")

# RivalActorPlayer is an AI-controlled opponent that shares the SonicPlayer physics
# and ability system but is fully isolated from the local player's ring pickups,
# trick combos, homing targets, HUD, camera, and input.
#
# Physical attacks clash evenly. Timed Insta-Shields parry incoming attacks,
# while their held block phase absorbs one hit before breaking.

enum AIState {
	INACTIVE   = 0,
	IDLE       = 1,
	DEFENSIVE  = 2,
	CHASE      = 3,
	ATTACK     = 4,
}

enum RivalAttackType {
	JUMP_DASH   = 0,
	ROLL_CHARGE = 1,
	SPIN_KICK   = 2,
}

enum RivalResourceMode {
	HEALTH = 0,
	RINGS = 1,
}

enum RivalColorSource {
	MANUAL = 0,
	TARGET = 1,
}

@export_group("Rival Actor")
## Rival profile resource to load before initialization.
@export_file("*.tres") var rival_profile_path: String = ""
## Name shown on the rival HUD. Uses the node name when empty.
@export var rival_display_name: String = ""
## Character ID used to choose the rival player scene. Empty keeps the placed scene.
@export var rival_character_id: String = ""
## Directory where CHAR_*.tres character docs live for rival character selection.
@export var rival_character_data_dir: String = "res://LS5Framework/Characters"
## Affiliation used for future NPC relationship rules.
@export var rival_affiliation: StringName = &"rival"
@export var rival_target_group: StringName = &"Player"
@export var rival_is_homing_target: bool = true
## Maximum distance from the player for homing targeting. Zero uses the player targeting range.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var homing_target_max_distance: float = 0.0
## Maximum spatial-cell refresh frequency while the rival is moving.
@export_range(1.0, 60.0, 1.0, "suffix:Hz") var rival_target_spatial_update_rate_hz: float = 20.0

@export_group("Rival colors")
## Applies character tint colors to the rival model.
@export var rival_apply_character_colors: bool = false
## Source used for rival character tint colors.
@export var rival_color_source: RivalColorSource = RivalColorSource.MANUAL
## Primary body color used when manual rival colors are enabled.
@export var rival_primary_color: Color = Color(0.18, 0.52, 1.0, 1.0)
## Secondary accent color used when manual rival colors are enabled.
@export var rival_secondary_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Trail and sonic boom color used when manual rival colors are enabled.
@export var rival_trail_color: Color = Color(0.2, 0.8, 1.0, 1.0)

@export_group("Rival Activation")
## Rival begins AI routines when the target enters this radius.
@export var activation_distance: float = 100.0
## Rival suspends AI routines when the target exceeds this radius.
@export var deactivation_distance: float = 250.0

@export_group("Rival AI - Neutral")
@export var idle_duration_min: float = 0.8
@export var idle_duration_max: float = 2.5
## Minimum idle time during active battles.
@export var battle_idle_duration_min: float = 0.05
## Maximum idle time during active battles.
@export var battle_idle_duration_max: float = 0.35

@export_group("Rival AI - Defensive")
## Ideal distance the rival tries to maintain while circling the player.
@export var rival_defensive_ideal_distance: float = 30.0
## Speed multiplier while strafing defensively (0–1 scale of normal move).
@export var rival_defensive_strafe_speed: float = 0.9
## Per-second chance to break from defensive into chase/attack.
@export var rival_defensive_to_offensive_chance: float = 0.4
## Per-second chance to break from an attack back into defensive.
@export var rival_offensive_to_defensive_chance: float = 0.15
## How often the rival attempts a reaction when the player is attacking.
@export var rival_defensive_reaction_chance: float = 0.6
## Chance that a defensive reaction uses the Insta-Shield instead of evading.
@export_range(0.0, 1.0, 0.01) var rival_defensive_parry_chance: float = 0.75
## Chance to jump when performing an evasive dodge.
@export var rival_defensive_dodge_jump_chance: float = 0.5
## Chance to roll when performing an evasive dodge on the ground.
@export var rival_defensive_evade_roll_chance: float = 0.3
## Seconds the player's attack must persist before using linger reaction values.
@export var rival_defensive_linger_threshold: float = 0.3
## Increased reaction chance when the player's attack has lingered past the threshold.
@export var rival_defensive_linger_reaction_chance: float = 0.9
## Increased Insta-Shield chance when the player's attack has lingered.
@export_range(0.0, 1.0, 0.01) var rival_defensive_linger_parry_chance: float = 0.95
## Increased dodge jump chance when the player's attack has lingered.
@export var rival_defensive_linger_dodge_jump_chance: float = 0.7
## Increased evade roll chance when the player's attack has lingered.
@export var rival_defensive_linger_evade_roll_chance: float = 0.6
## Minimum age of a player action before the rival can react to it.
@export var rival_reaction_min_action_age: float = 0.2
## Minimum time the rival holds a successful defensive shield attempt.
@export_range(0.15, 1.15, 0.01, "suffix:s") var rival_defensive_shield_hold_min: float = 0.35
## Maximum time the rival holds a successful defensive shield attempt.
@export_range(0.15, 1.15, 0.01, "suffix:s") var rival_defensive_shield_hold_max: float = 0.8

@export_group("Rival AI - Combat")
## 3D distance at which the rival initiates an attack from chase.
@export var rival_attack_range: float = 18.0
## 3D distance at which the rival enters chase toward the player.
@export var rival_chase_range: float = 100.0
## 3D distance for defensive and post-attack transitions; controls engagement and disengagement from combat routines.
@export var rival_combat_range: float = 30.0
@export var rival_attack_cooldown: float = 2.0
@export var rival_jump_cooldown: float = 0.35
## Maximum seconds a rival can stay in a roll attack.
@export var rival_roll_attack_max_duration: float = 2.0
## Roll attack ends early below this speed after startup.
@export var rival_roll_min_active_speed: float = 2.0
## Seconds before low-speed roll recovery can end the roll attack.
@export var rival_roll_min_speed_grace: float = 0.35
@export var rival_obstacle_check_distance: float = 1.2
@export var rival_obstacle_check_height: float = 0.8
## Distance within which a touching attack collision is resolved.
@export var rival_combat_hit_radius: float = 2.0
## Speed of radial bounce-off applied to both parties on a draw.
@export var rival_combat_bounce_speed: float = 18.0
## Draw bounces multiply the base bounce speed by this factor for a more violent impulse.
@export var rival_combat_draw_bounce_multiplier: float = 1.5
## Seconds after any combat resolution before another can fire.
@export var rival_combat_recoil_cooldown: float = 0.5
## Shorter homing attack timeout to prevent overshooting the target.
@export var rival_homing_fail_timeout: float = 0.6

@export_group("Rival Threat")
## Enables threat-based target switching.
@export var rival_threat_enabled: bool = true
## Enables runtime discovery of nearby NPC actors.
@export var rival_dynamic_target_discovery_enabled: bool = true
## Radius used when discovering nearby NPC actors.
@export var rival_dynamic_target_search_radius: float = 100.0
## Additional groups considered during threat re-evaluation.
@export var rival_threat_extra_target_groups: Array[StringName] = []
## Threat gained per point of received damage.
@export var rival_threat_damage_weight: float = 12.0
## Threat lost per second.
@export var rival_threat_decay_per_sec: float = 1.0
## Threat bonus for the default rival target group.
@export var rival_threat_primary_target_bonus: float = 4.0
## Threat bonus while revenge strikes are owed to a source.
@export var rival_threat_revenge_bonus: float = 18.0
## Distance score weight used when selecting a focus target.
@export var rival_threat_distance_weight: float = 0.08
## Seconds between normal threat re-evaluations.
@export var rival_threat_reevaluate_interval: float = 0.75
## Revenge strikes added when the rival receives damage from a source.
@export var rival_revenge_strikes_per_hit: int = 1
## Minimum threat retained on a target that has pending revenge strikes.
@export var rival_revenge_min_threat: float = 10.0
## Maximum distance for revenge pursuit before normal target selection resumes.
@export var rival_revenge_pursuit_max_distance: float = 70.0
## Maximum seconds a revenge target can be pursued without landing a strike.
@export var rival_revenge_pursuit_timeout: float = 6.0

@export_group("Rival Health")
## Resource used to determine whether the rival survives damage.
@export var rival_resource_mode: RivalResourceMode = RivalResourceMode.HEALTH
## Maximum health used when the rival uses health as a resource.
@export var rival_max_health: int = 3
## Rings carried by the rival when activated.
@export var rival_starting_rings: int = 0
## If enabled, collected rings restore health.
@export var rival_rings_restore_health: bool = true
## Health restored per collected ring.
@export var rival_health_restored_per_ring: float = 0.25
## Health fraction at which the rival searches for healing rings.
@export_range(0.0, 1.0, 0.01) var rival_health_self_preservation_threshold: float = 0.35
## Enables rival respawn after defeat.
@export var rival_respawn_enabled: bool = true
## Seconds before a defeated rival respawns.
@export var rival_respawn_delay: float = 5.0
## Seconds the rival remains visible after defeat before hiding.
@export var rival_defeated_idle_duration: float = 3.0

@export_group("Rival Rings")
## Ring search radius used for self-preservation.
@export var rival_ring_search_radius: float = 80.0
## Ring search radius used while enraged.
@export var rival_rage_ring_search_radius: float = 8.0

@export_group("Rival Rage")
## Hits required to trigger enraged behavior.
@export var rival_rage_hits_required: int = 3
## Seconds the rival stays enraged.
@export var rival_rage_duration: float = 15.0
## Seconds after being hit before the rival can search for rings.
@export var rival_dazed_duration: float = 1.0

@export_group("Rival Invulnerability")
## Invulnerability duration at battle start.
@export var rival_battle_start_invuln_time: float = 2.5
## Invulnerability duration after the battle has fully scaled.
@export var rival_battle_end_invuln_time: float = 1.0
## Seconds over which rival invulnerability scales.
@export var rival_invuln_scale_duration: float = 60.0

@export_group("Rival HUD")
## Enables the rival status HUD.
@export var rival_hud_enabled: bool = true
## Distance from the target at which the rival status HUD is visible.
@export var rival_hud_visible_distance: float = 100.0

@export_group("Rival Actor Options")
@export var rival_can_take_damage: bool = true

@export_group("Rival Navigation")
## NavigationRegion3D to use for pathfinding in chase and obstructed combat.
@export var navigation_region: NavigationRegion3D
## Whether the rival should use navmesh pathfinding when appropriate.
@export var rival_use_navmesh: bool = true
## Seconds between navmesh path recalculations.
@export var rival_navmesh_path_recalc_interval: float = 0.3
## Distance threshold to advance to the next navmesh path point.
@export var rival_navmesh_path_point_threshold: float = 1.5
## How strongly to steer back onto the navmesh when off it.
@export var rival_navmesh_off_mesh_steer: float = 0.5
## Y coordinate below which the rival is considered to have fallen into a void and dies.
@export var rival_death_plane_y: float = -500.0

var _rival_move_dir: Vector3 = Vector3.ZERO
var _rival_move_input: Vector2 = Vector2.ZERO

var _ai_state: AIState = AIState.INACTIVE
var _idle_timer: float = 0.0
var _defensive_orbit_clockwise: bool = true
var _attack_cooldown_timer: float = 0.0
var _rival_jump_timer: float = 0.0
var _rival_attack_was_airborne: bool = false
var _combat_recoil_timer: float = 0.0

var _navmesh_map_rid: RID = RID()
var _navmesh_path_points: PackedVector3Array = PackedVector3Array()
var _navmesh_path_index: int = 0
var _navmesh_path_timer: float = 0.0
var _navmesh_has_path: bool = false

var _rival_attack_type: RivalAttackType = RivalAttackType.JUMP_DASH
var _rival_roll_attack_timer: float = 0.0
var _rival_roll_attack_elapsed: float = 0.0
var _rival_evade_roll_timer: float = 0.0
var _target_attack_linger_timer: float = 0.0
var _rival_debug_status: String = "Inactive"
var _rival_last_reaction: String = "None"
var _rival_threat_table: Dictionary = {}
var _rival_focus_target: Node3D = null
var _rival_threat_reevaluate_timer: float = 0.0

var _rival_health: float = 0.0
var _rival_defeated_idle_timer: float = 0.0
var _rival_is_defeated: bool = false
var _rival_awaiting_defeat_idle: bool = false
var _rival_respawn_timer: float = 0.0
var _rival_deactivated: bool = false
var _rival_battle_active: bool = false
var _rival_battle_time: float = 0.0
var _rival_rage: int = 0
var _rival_rage_timer: float = 0.0
var _rival_dazed_timer: float = 0.0
var _rival_self_preserve_voice_active: bool = false
var _rival_enraged_voice_pending: bool = false
var _rival_ring_target: Node3D = null
var _rival_hud_layer: CanvasLayer = null
var _rival_hud_panel: Control = null
var _rival_hud_title_label: Label = null
var _rival_hud_health_bar: ProgressBar = null
var _rival_hud_ring_label: Label = null
var _rival_hud_rage_label: Label = null
var _rival_hud_debug_label: Label = null
var _rival_spawn_transform: Transform3D = Transform3D.IDENTITY
var _rival_initial_collision_layer: int = 0
var _rival_initial_collision_mask: int = 0
var _rival_colors_applied: bool = false
var _rival_applied_primary_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var _rival_applied_secondary_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var _rival_applied_trail_color: Color = Color(0.0, 0.0, 0.0, 0.0)
var _rival_profile: RivalProfile = null
var _rival_target_spatial_update_timer: float = 0.0


func _ready() -> void:
	_apply_rival_profile()
	if _replace_with_rival_character_scene():
		return

	set_meta("is_rival_actor", true)
	set_meta("npc_affiliation", rival_affiliation)

	if is_in_group("Player"):
		remove_from_group("Player")
	if is_in_group("player"):
		remove_from_group("player")

	add_to_group("RivalActor")
	add_to_group("NPCActor")

	buddy_enable = false
	attack_magnetism_enabled = false
	homing_targeting_enabled = false
	lock_cursor_to_game = false
	name_tag_enabled = false
	chat_bubble_enabled = false
	speed_lines_enabled = false
	coyote_jump_enabled = false

	_rival_health = float(rival_max_health)
	rings = max(rival_starting_rings, 0)

	super._ready()
	_rival_spawn_transform = global_transform
	_rival_initial_collision_layer = collision_layer
	_rival_initial_collision_mask = collision_mask
	_configure_rival_death_action()

	if _ui_module != null:
		_ui_module._clear_speed_lines()

	_disable_rival_wind_sfx()

	_apply_rival_character_colors(null)
	_set_rival_homing_target_registered(rival_is_homing_target)

# ---------------------------------------------------------------------------
# Core lifecycle
# ---------------------------------------------------------------------------
func _movement_physics_process(delta: float) -> void:
	if _rival_deactivated:
		_rival_debug_status = "Respawn %.1f" % _rival_respawn_timer
		_update_rival_respawn(_movement_real_delta)
		return

	if _rival_is_defeated:
		_rival_defeated_idle_timer = max(_rival_defeated_idle_timer - delta, 0.0)
		_rival_debug_status = "Defeated %.1f" % _rival_defeated_idle_timer
		_set_rival_move(Vector3.ZERO)
		_hide_rival_hud()
		super._movement_physics_process(delta)
		if _rival_defeated_idle_timer <= 0.0:
			_deactivate_rival_until_respawn()
		return

	if global_position.y < rival_death_plane_y:
		apply_death_plane_damage(self)

	_rival_jump_timer = max(_rival_jump_timer - delta, 0.0)
	_attack_cooldown_timer = max(_attack_cooldown_timer - delta, 0.0)
	_combat_recoil_timer = max(_combat_recoil_timer - delta, 0.0)
	_rival_evade_roll_timer = max(_rival_evade_roll_timer - delta, 0.0)
	if _rival_battle_active:
		_rival_battle_time += delta
	_update_rival_threats(delta)
	_update_rival_status_timers(delta)
	_update_rival_invuln_duration()
	_update_rival_voice_cues()
	if _rival_evade_roll_timer > 0.0:
		rolling = true
	_update_rival_ai(delta)
	super._movement_physics_process(delta)
	_update_rival_homing_target_cell(delta)


# ---------------------------------------------------------------------------
# Input injection – AI-set vectors replace player input each frame
# ---------------------------------------------------------------------------
func _read_input() -> void:
	_move_input = _rival_move_input


func _compute_move_direction() -> void:
	_move_direction = _rival_move_dir


# ---------------------------------------------------------------------------
# Player-system isolation
# ---------------------------------------------------------------------------
func _ensure_debug_input_actions() -> void:
	pass


func _create_debug_hud() -> void:
	pass


func _update_mouse_lock() -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _set_manual_camera_lock(_active: bool) -> void:
	return


func _should_start_manual_airborne_torque() -> bool:
	return false


func _update_manual_airborne_torque(_delta: float) -> void:
	_manual_airborne_torque_active = false
	_manual_airborne_torque_suppress_decay = false
	_manual_airborne_torque_fast_decay = false
	_manual_airborne_mouse_delta = Vector2.ZERO


func _connect_trick_signals() -> void:
	return


func _on_trick_detected(_trick_type: int, _timer_add_seconds: float = -1.0) -> void:
	return


func _update_trick_detection(_delta: float) -> void:
	return


func _update_air_trick_animation() -> void:
	return


func _finalize_trick_landing() -> void:
	return


func _process_action_inputs() -> void:
	pass


func _update_roll_state() -> void:
	pass


func _update_spindash_state(_delta: float) -> void:
	pass


func _update_action_runtime(delta: float) -> void:
	for action in _actions:
		if action == null or not is_instance_valid(action) or not action.continuous_update:
			continue
		if action is SpindashAction or action is RollAction:
			continue
		action.continuous_physics_update(delta)


func _update_homing(delta: float, up_for_physics: Vector3, is_attached: bool) -> void:
	if not _homing_active:
		return
	_homing_elapsed += delta
	var timeout: float = rival_homing_fail_timeout
	if timeout > 0.0 and _homing_elapsed >= timeout:
		cancel_homing_attack(false)
		return
	super._update_homing(delta, up_for_physics, is_attached)


func _update_speed_wind_sfx() -> void:
	return


func _is_jump_held() -> bool:
	return false


func _get_hud_node() -> Node:
	return null


func _set_special_gauge_ui(_fraction: float) -> void:
	return


func add_rings(_amount: int) -> void:
	var amount: int = max(int(_amount), 0)
	super.add_rings(amount)
	if rival_rings_restore_health and amount > 0:
		_rival_health = min(_rival_health + float(amount) * max(rival_health_restored_per_ring, 0.0), float(max(rival_max_health, 0)))


func apply_damage(_amount: int = 1, _source: Node = null) -> void:
	if _is_dead or _player_state_locked:
		return
	if _damage_hit_invuln_timer > 0.0:
		return
	if not rival_can_take_damage:
		return

	_register_rival_hit()
	_register_rival_damage_threat(_source, max(int(_amount), 1))

	if rival_resource_mode == RivalResourceMode.RINGS:
		if rings <= 0:
			_begin_rival_death(_source)
			return
	else:
		_rival_health = max(_rival_health - float(max(int(_amount), 1)), 0.0)
		if _rival_health <= 0.0:
			_begin_rival_death(_source)
			return

	_on_player_hurt()
	if _hurt_action != null:
		_sync_hurt_state_to_action()
		_hurt_action.damage_hit_invuln_time = _get_current_rival_invuln_time()
		_hurt_action.apply_damage_without_ring_death(_amount, _source, true)
		_sync_hurt_state_from_action()
		_queue_rival_damage_voice_cues()
		return
	super.apply_damage(_amount, _source)
	_queue_rival_damage_voice_cues()


func apply_death_plane_damage(_source: Node = null) -> void:
	if _is_dead or _player_state_locked or _rival_deactivated:
		return
	_rival_health = 0.0
	_begin_rival_death(_source, true)


func _begin_rival_death(source: Node = null, pit_variant: bool = false) -> void:
	if _rival_deactivated:
		return
	_rival_awaiting_defeat_idle = false
	_rival_is_defeated = true
	_rival_defeated_idle_timer = max(rival_defeated_idle_duration, 0.0)
	_set_rival_move(Vector3.ZERO)
	_clear_rival_attack_state()
	_attack_cooldown_timer = 0.0
	_on_player_hurt()
	if _hurt_action != null:
		_sync_hurt_state_to_action()
		_hurt_action.apply_forced_death_damage(source, pit_variant)
		_sync_hurt_state_from_action()
	else:
		_play_rival_death_sound()
		set_death_state(true)
	if _rival_defeated_idle_timer <= 0.0:
		_deactivate_rival_until_respawn()


func _configure_rival_death_action() -> void:
	if _hurt_action == null:
		return
	_hurt_action.death_camera_constraint_enabled = false
	_hurt_action.death_fade_enabled = false
	_hurt_action.death_respawn_enabled = false


func _deactivate_rival_until_respawn() -> void:
	_clear_rival_attack_state()
	_attack_cooldown_timer = 0.0
	_reset_rival_hurt_action_state()
	_rival_threat_table.clear()
	_set_rival_focus_target(null)
	_rival_threat_reevaluate_timer = 0.0
	_rival_is_defeated = false
	_rival_awaiting_defeat_idle = false
	_rival_deactivated = true
	_rival_respawn_timer = max(rival_respawn_delay, 0.0)
	_ai_state = AIState.INACTIVE
	_rival_battle_active = false
	_set_rival_move(Vector3.ZERO)
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	_hurt_active = false
	_player_state_locked = false
	_is_dead = false
	_hide_rival_hud()
	_set_rival_homing_target_registered(false)
	if not rival_respawn_enabled:
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	if _rival_respawn_timer <= 0.0:
		activate_rival()


func _update_rival_respawn(delta: float) -> void:
	if not rival_respawn_enabled:
		return
	_rival_respawn_timer = max(_rival_respawn_timer - delta, 0.0)
	if _rival_respawn_timer <= 0.0:
		activate_rival()


func _play_rival_death_sound() -> void:
	if _hurt_action == null:
		return
	var death_stream: Variant = _hurt_action.get("death_sound")
	if death_stream == null or not (death_stream is AudioStream):
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = death_stream as AudioStream
	p.bus = "SFX"
	p.autoplay = true
	var parent: Node = get_parent()
	if parent == null:
		parent = self
	parent.add_child(p)
	p.top_level = true
	p.global_position = global_position
	p.finished.connect(func():
		p.queue_free()
	)


func _clear_rival_attack_state() -> void:
	rolling = false
	_rival_roll_attack_timer = 0.0
	_rival_roll_attack_elapsed = 0.0
	_rival_evade_roll_timer = 0.0
	_combat_recoil_timer = 0.0
	_rival_attack_was_airborne = false
	if _homing_active or _homing_target != null:
		cancel_homing_attack(false)
	if has_method("clear_active_action"):
		call("clear_active_action")


func _reset_rival_hurt_action_state() -> void:
	if _hurt_action == null:
		return
	_hurt_action.is_active = false
	_hurt_action.invuln_timer = 0.0
	_hurt_action.hurt_type = HurtAction.HurtType.NONE
	_hurt_action.state_timer = 0.0
	_hurt_action.pushback_dir = Vector3.ZERO
	_hurt_action.pushback_speed_locked = 0.0
	_hurt_action.set("_death_active", false)
	_hurt_action.set("_death_grounded", false)
	_hurt_action.set("_death_respawn_transition_active", false)
	_hurt_action.set("_death_pit_variant", false)
	_hurt_action.set("_flash_invulnerability_visual", false)


func _update_barrier_blast(_delta: float, _world_up: Vector3, _is_attached_for_movement: bool) -> void:
	return


func _disable_rival_wind_sfx() -> void:
	if sfx_speed_wind != null and sfx_speed_wind.playing:
		sfx_speed_wind.stop()
	sfx_speed_wind = null
	if sfx_barrier_blast_wind != null and sfx_barrier_blast_wind.playing:
		sfx_barrier_blast_wind.stop()
	sfx_barrier_blast_wind = null
	if sfx_barrier_blast_boom != null and sfx_barrier_blast_boom.playing:
		sfx_barrier_blast_boom.stop()
	sfx_barrier_blast_boom = null


# ---------------------------------------------------------------------------
# Homing target re-route: returns live target for gradual tracking
# ---------------------------------------------------------------------------
func _select_homing_target(origin: Vector3, max_range: float) -> Node3D:
	if max_range <= 0.0:
		return null
	var target := _find_rival_target()
	if target == null:
		return null
	var dist: float = (target.global_position - origin).length()
	if dist < 0.001 or dist > max_range:
		return null
	return target


# ---------------------------------------------------------------------------
# HomingTarget interface – called when the player locks on and hits this actor
# ---------------------------------------------------------------------------
func on_homing_hit(attacker: Node, _jump_held: bool) -> bool:
	if attacker is Node3D:
		var outcome: CombatOutcome = _apply_rival_combat(attacker as Node3D, true)
		return outcome == CombatOutcome.DRAW
	return true


# ---------------------------------------------------------------------------
# AI – core update
# ---------------------------------------------------------------------------
func _update_rival_ai(delta: float) -> void:
	var target := _find_rival_target()

	if target == null:
		_set_rival_move(Vector3.ZERO)
		_ai_state = AIState.INACTIVE
		return

	var dist: float = (target.global_position - global_position).length()
	var up: Vector3 = _get_gravity_up()
	_apply_rival_character_colors(target)
	if is_insta_shield_combat_control_locked():
		_set_rival_move(Vector3.ZERO)
		_rival_debug_status = "Combat recovery"
		_apply_rival_combat(target)
		_update_rival_hud(target, dist)
		return

	if _ai_state == AIState.INACTIVE:
		if dist <= activation_distance or _has_pending_revenge_target(target):
			_rival_battle_active = true
			_enter_idle()
		else:
			_set_rival_move(Vector3.ZERO)
			_update_rival_hud(target, dist)
			return
	elif dist > deactivation_distance and not _has_pending_revenge_target(target):
		_ai_state = AIState.INACTIVE
		_set_rival_move(Vector3.ZERO)
		_update_rival_hud(target, dist)
		return

	if _is_rival_enraged() and _ai_state != AIState.CHASE and _ai_state != AIState.ATTACK:
		_enter_chase()
	elif _should_search_for_ring() and _update_ring_search(up):
		_ai_state = AIState.DEFENSIVE
		_rival_debug_status = "Self-preservation"
		_apply_rival_combat(target)
		_update_rival_hud(target, dist)
		return

	match _ai_state:
		AIState.IDLE:
			_update_idle(delta, dist)
		AIState.DEFENSIVE:
			_update_defensive(delta, target, dist, up)
		AIState.CHASE:
			_update_chase(delta, target, dist, up)
		AIState.ATTACK:
			_update_attack(dist, target, up)

	_apply_rival_combat(target)
	_update_rival_hud(target, dist)


# ---------------------------------------------------------------------------
# AI – per-state updates
# ---------------------------------------------------------------------------
func _update_idle(delta: float, dist: float) -> void:
	_set_rival_move(Vector3.ZERO)
	_rival_debug_status = "Idle"
	if _rival_battle_active:
		if dist <= rival_combat_range:
			_enter_defensive()
			return
		if dist <= rival_chase_range and _can_act_offensively():
			_enter_chase()
			return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		if dist <= rival_combat_range:
			_enter_defensive()
		elif dist <= rival_chase_range and _can_act_offensively():
			_enter_chase()
		else:
			_enter_idle()


func _update_defensive(delta: float, target: Node3D, dist: float, up: Vector3) -> void:
	_rival_debug_status = "Defensive"
	if _is_rival_enraged():
		_enter_chase()
		return

	if dist > rival_combat_range:
		if dist <= rival_chase_range and _can_act_offensively():
			_enter_chase()
		else:
			_enter_idle()
		return

	# React to player attacks when in range.
	if target.has_method("is_attack_active"):
		var target_attacking: bool = bool(target.call("is_attack_active"))
		if target_attacking:
			_target_attack_linger_timer += delta
			_rival_last_reaction = "Reading action %.2f" % _target_attack_linger_timer
			if _should_react_to_attack():
				_attempt_defensive_reaction(target, up)
				return
		else:
			_target_attack_linger_timer = 0.0
			_rival_last_reaction = "Watching"

	# If obstructed and navmesh is enabled, path toward the player instead of orbiting
	if rival_use_navmesh and _has_obstruction_to(target, up) and _ensure_navmesh_map():
		_navmesh_path_timer += delta
		if _navmesh_path_timer >= rival_navmesh_path_recalc_interval or not _navmesh_has_path:
			_update_navmesh_path(target.global_position)
			_navmesh_path_timer = 0.0
		var move_dir: Vector3 = _get_navmesh_move_direction()
		if move_dir.length() < 0.001:
			move_dir = _get_direct_move_to_target(target, up)
		_set_rival_move(_adjust_move_for_navmesh(move_dir))
		_try_rival_obstacle_jump(up)
		return

	# Orbital strafe at ideal distance
	var to_player: Vector3 = target.global_position - global_position
	var planar_to: Vector3 = to_player - up * to_player.dot(up)
	var to_dir: Vector3 = Vector3.ZERO
	if planar_to.length() > 0.001:
		to_dir = planar_to.normalized()

	var orbit: Vector3 = to_dir.cross(up).normalized()
	if not _defensive_orbit_clockwise:
		orbit = -orbit

	var move: Vector3 = orbit
	if dist < rival_defensive_ideal_distance - 3.0:
		move = (orbit * 0.5 - to_dir * 0.5).normalized()
	elif dist > rival_defensive_ideal_distance + 3.0:
		move = (orbit * 0.5 + to_dir * 0.3).normalized()

	_set_rival_move(move * rival_defensive_strafe_speed)

	if randf() < 0.015:
		_defensive_orbit_clockwise = not _defensive_orbit_clockwise

	_try_rival_obstacle_jump(up)

	# After some time, go on the offensive
	if _can_act_offensively() and randf() < delta * rival_defensive_to_offensive_chance:
		_enter_chase()


func _update_chase(delta: float, target: Node3D, dist: float, up: Vector3) -> void:
	_rival_debug_status = "Offensive chase"
	if not _can_act_offensively():
		_enter_defensive()
		return

	if _attack_cooldown_timer <= 0.0 and dist <= rival_attack_range:
		_enter_attack()
		return

	if dist > rival_chase_range:
		_enter_idle()
		return

	if dist > rival_defensive_ideal_distance + 2.0 and randf() < delta * 0.5:
		_enter_defensive()
		return

	var move_dir: Vector3 = Vector3.ZERO
	if rival_use_navmesh and _ensure_navmesh_map():
		_navmesh_path_timer += delta
		if _navmesh_path_timer >= rival_navmesh_path_recalc_interval or not _navmesh_has_path:
			_update_navmesh_path(target.global_position)
			_navmesh_path_timer = 0.0
		move_dir = _get_navmesh_move_direction()
		if move_dir.length() < 0.001:
			move_dir = _get_direct_move_to_target(target, up)
	else:
		move_dir = _get_direct_move_to_target(target, up)

	_set_rival_move(_adjust_move_for_navmesh(move_dir))
	_try_rival_obstacle_jump(up)


func _update_attack(dist: float, target: Node3D, up: Vector3) -> void:
	_rival_debug_status = "Attack %s" % _get_attack_type_name()
	if not _can_act_offensively():
		_clear_rival_attack_state()
		_enter_defensive()
		return

	if not attached:
		_rival_attack_was_airborne = true

	if _homing_active:
		_set_rival_move(Vector3.ZERO)
		return

	# Occasionally break the attack cycle with a defensive detour
	if not _is_rival_enraged() and randf() < get_movement_physics_delta() * rival_offensive_to_defensive_chance:
		_clear_rival_attack_state()
		_enter_defensive()
		return

	match _rival_attack_type:
		RivalAttackType.JUMP_DASH:
			_update_attack_jump_dash(dist)
		RivalAttackType.ROLL_CHARGE:
			_update_attack_roll_charge(dist)
		RivalAttackType.SPIN_KICK:
			_update_attack_spin_kick(dist)


func _update_attack_jump_dash(dist: float) -> void:
	if not attached and _rival_jump_timer <= 0.0 and _attack_cooldown_timer <= 0.0 and not _jump_dash_used_this_air:
		if homing_attack_enabled and has_homing_target_in_range():
			queue_jump_dash()
			_set_rival_move(Vector3.ZERO)
			return

	if attached and _rival_attack_was_airborne:
		_clear_rival_attack_state()
		if dist <= rival_combat_range:
			_enter_defensive()
		else:
			_enter_idle()


func _update_attack_roll_charge(dist: float) -> void:
	var delta: float = get_movement_physics_delta()
	_rival_roll_attack_timer -= delta
	_rival_roll_attack_elapsed += delta
	var lateral_speed: float = _get_rival_lateral_speed()
	var max_duration: float = max(rival_roll_attack_max_duration, 0.05)
	var low_speed_stalled: bool = _rival_roll_attack_elapsed >= max(rival_roll_min_speed_grace, 0.0) and lateral_speed < max(rival_roll_min_active_speed, 0.0)
	if _rival_roll_attack_timer <= 0.0 or _rival_roll_attack_elapsed >= max_duration or low_speed_stalled or _hurt_active:
		_clear_rival_attack_state()
		if dist <= rival_combat_range:
			_enter_defensive()
		else:
			_enter_idle()
		return

	var target := _find_rival_target()
	if target != null:
		var to: Vector3 = target.global_position - global_position
		var up: Vector3 = _get_gravity_up()
		var planar: Vector3 = to - up * to.dot(up)
		if planar.length() > 0.001:
			_set_rival_move(planar.normalized())
		else:
			_set_rival_move(Vector3.ZERO)
	else:
		_set_rival_move(Vector3.ZERO)


func _update_attack_spin_kick(dist: float) -> void:
	_rival_roll_attack_timer -= get_movement_physics_delta()
	if _rival_roll_attack_timer <= 0.0 or _hurt_active:
		if dist <= rival_combat_range:
			_enter_defensive()
		else:
			_enter_idle()
		return

	if attached:
		for action in _actions:
			if action != null and is_instance_valid(action) and action is SpinKickAbility:
				if action.has_method("execute"):
					action.call("execute", {"reason": &"ai_attack"})
				return
	else:
		for action in _actions:
			if action != null and is_instance_valid(action) and action is SpinKickAbility:
				if action.has_method("execute"):
					action.call("execute", {"reason": &"ai_attack"})
				return

	if attached and _rival_attack_was_airborne:
		if dist <= rival_combat_range:
			_enter_defensive()
		else:
			_enter_idle()


# ---------------------------------------------------------------------------
# AI – state transitions
# ---------------------------------------------------------------------------
func _enter_idle() -> void:
	_ai_state = AIState.IDLE
	_rival_debug_status = "Idle"
	if _rival_battle_active:
		_idle_timer = randf_range(battle_idle_duration_min, max(battle_idle_duration_min, battle_idle_duration_max))
	else:
		_idle_timer = randf_range(idle_duration_min, max(idle_duration_min, idle_duration_max))
	_set_rival_move(Vector3.ZERO)


func _enter_defensive() -> void:
	_ai_state = AIState.DEFENSIVE
	_rival_debug_status = "Defensive"
	_defensive_orbit_clockwise = randf() < 0.5


func _enter_chase() -> void:
	if not _can_act_offensively():
		_enter_defensive()
		return
	_ai_state = AIState.CHASE
	_rival_debug_status = "Offensive chase"
	_clear_rival_navmesh_path()


func _enter_attack(p_forced_type: int = -1, allow_defensive_counter: bool = false) -> void:
	if not allow_defensive_counter and not _can_act_offensively():
		_enter_defensive()
		return
	_ai_state = AIState.ATTACK
	_rival_attack_was_airborne = false
	_attack_cooldown_timer = rival_attack_cooldown

	if p_forced_type >= 0:
		_rival_attack_type = p_forced_type as RivalAttackType
	else:
		var roll_weight: float = 0.35
		var kick_weight: float = 0.35
		var r: float = randf()
		if r < roll_weight:
			_rival_attack_type = RivalAttackType.ROLL_CHARGE
		elif r < roll_weight + kick_weight:
			_rival_attack_type = RivalAttackType.SPIN_KICK
		else:
			_rival_attack_type = RivalAttackType.JUMP_DASH

	if _rival_attack_type == RivalAttackType.JUMP_DASH:
		_rival_debug_status = "Attack Jump Dash"
		if attached and _rival_jump_timer <= 0.0:
			queue_jump()
			_rival_jump_timer = rival_jump_cooldown
	elif _rival_attack_type == RivalAttackType.ROLL_CHARGE:
		_rival_debug_status = "Attack Roll"
		rolling = true
		_rival_roll_attack_timer = min(1.5, max(rival_roll_attack_max_duration, 0.05))
		_rival_roll_attack_elapsed = 0.0
	elif _rival_attack_type == RivalAttackType.SPIN_KICK:
		_rival_debug_status = "Attack Spin Kick"
		_rival_roll_attack_timer = 0.8
		_rival_roll_attack_elapsed = 0.0


# ---------------------------------------------------------------------------
# AI – helpers
# ---------------------------------------------------------------------------
func _find_rival_target() -> Node3D:
	if not rival_threat_enabled:
		return _find_default_rival_target()
	if _should_reselect_rival_focus():
		_set_rival_focus_target(_select_highest_threat_target())
		_rival_threat_reevaluate_timer = max(rival_threat_reevaluate_interval, 0.05)
	if _is_valid_rival_target(_rival_focus_target):
		return _rival_focus_target
	_set_rival_focus_target(_select_highest_threat_target())
	return _rival_focus_target


func _find_default_rival_target() -> Node3D:
	if rival_target_group == &"" or get_tree() == null:
		return null
	var best: Node3D = null
	var best_dist_sq: float = 1e20
	for node in get_tree().get_nodes_in_group(rival_target_group):
		if not _is_valid_rival_target_node(node):
			continue
		var dist_sq: float = ((node as Node3D).global_position - global_position).length_squared()
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = node as Node3D
	return best


func _should_reselect_rival_focus() -> bool:
	if not _is_valid_rival_target(_rival_focus_target):
		return true
	if _has_pending_revenge_target(_rival_focus_target):
		return false
	return _rival_threat_reevaluate_timer <= 0.0


func _select_highest_threat_target() -> Node3D:
	var best: Node3D = null
	var best_score: float = -1e20
	var candidates: Array[Node3D] = _get_rival_target_candidates()
	for candidate in candidates:
		var score: float = _get_target_threat_score(candidate)
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _get_rival_target_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	var default_target: Node3D = _find_default_rival_target()
	if default_target != null:
		candidates.append(default_target)
	for entry in _rival_threat_table.values():
		if not (entry is Dictionary):
			continue
		var target: Variant = (entry as Dictionary).get("target", null)
		if not _is_valid_rival_target(target):
			continue
		var target_node: Node3D = target as Node3D
		if not (target_node in candidates):
			candidates.append(target_node)
	if get_tree() != null:
		for group_name in rival_threat_extra_target_groups:
			if group_name == &"":
				continue
			for node in get_tree().get_nodes_in_group(group_name):
				if _is_valid_rival_target_node(node) and not ((node as Node3D) in candidates):
					candidates.append(node as Node3D)
		if rival_dynamic_target_discovery_enabled:
			_append_dynamic_rival_targets(candidates)
	return candidates


func _append_dynamic_rival_targets(candidates: Array[Node3D]) -> void:
	if get_tree() == null:
		return
	var radius: float = max(rival_dynamic_target_search_radius, 0.0)
	var radius_sq: float = radius * radius
	for node in get_tree().get_nodes_in_group("NPCActor"):
		if not _is_valid_rival_target_node(node):
			continue
		var target: Node3D = node as Node3D
		if target in candidates:
			continue
		if radius > 0.0 and (target.global_position - global_position).length_squared() > radius_sq:
			continue
		candidates.append(target)


func _get_target_threat_score(target: Variant) -> float:
	if not _is_valid_rival_target(target):
		return -1e20
	var target_node: Node3D = target as Node3D
	var score: float = 0.0
	var entry: Dictionary = _get_threat_entry_for_target(target_node)
	if not entry.is_empty():
		score += float(entry.get("threat", 0.0))
		if int(entry.get("revenge", 0)) > 0:
			score += max(rival_threat_revenge_bonus, 0.0)
	if rival_target_group != &"" and target_node.is_in_group(rival_target_group):
		score += rival_threat_primary_target_bonus
	var distance: float = (target_node.global_position - global_position).length()
	score -= distance * max(rival_threat_distance_weight, 0.0)
	return score


func _is_valid_rival_target_node(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Node3D) or node == self:
		return false
	return _is_valid_rival_target(node as Node3D)


func _is_valid_rival_target(target: Variant) -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node3D) or target == self:
		return false
	var target_node: Node3D = target as Node3D
	if not target_node.visible:
		return false
	var dead_value: Variant = target_node.get("_dead")
	if dead_value is bool and bool(dead_value):
		return false
	var is_dead_value: Variant = target_node.get("_is_dead")
	if is_dead_value is bool and bool(is_dead_value):
		return false
	var enabled_value: Variant = target_node.get("enabled")
	if enabled_value is bool and not bool(enabled_value):
		return false
	return true


func _set_rival_move(dir: Vector3) -> void:
	_rival_move_dir = dir
	_rival_move_input = Vector2(0.0, 1.0) if dir.length() > 0.001 else Vector2.ZERO


func _set_rival_focus_target(target: Node3D) -> void:
	if _rival_focus_target == target:
		return
	_rival_focus_target = target
	_clear_rival_navmesh_path()
	_set_rival_move(Vector3.ZERO)


func clear_rival_target_reference(target: Node) -> void:
	if target == null:
		return
	if _rival_focus_target == target:
		_set_rival_focus_target(null)
	var remove_ids: Array[int] = []
	for id in _rival_threat_table.keys():
		var entry_value: Variant = _rival_threat_table[id]
		if not (entry_value is Dictionary):
			continue
		var entry_target: Variant = (entry_value as Dictionary).get("target", null)
		if entry_target == target:
			remove_ids.append(int(id))
	for id in remove_ids:
		_rival_threat_table.erase(id)


func _clear_rival_navmesh_path() -> void:
	_navmesh_path_points.clear()
	_navmesh_path_index = 0
	_navmesh_path_timer = 0.0
	_navmesh_has_path = false


func _ensure_navmesh_map() -> bool:
	if _navmesh_map_rid.is_valid():
		return true
	if navigation_region == null:
		return false
	var region_rid: RID = navigation_region.get_rid()
	if not region_rid.is_valid():
		return false
	_navmesh_map_rid = NavigationServer3D.region_get_map(region_rid)
	return _navmesh_map_rid.is_valid()


func _has_obstruction_to(target: Node3D, up: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + up * rival_obstacle_check_height
	var to: Vector3 = target.global_position + up * 0.5
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result:
		var collider: Node = result.get("collider", null)
		if collider != null and collider != target:
			return true
	return false


func _update_navmesh_path(to: Vector3) -> void:
	if not _navmesh_map_rid.is_valid():
		_navmesh_has_path = false
		return
	var origin: Vector3 = global_position
	var path: PackedVector3Array = NavigationServer3D.map_get_path(_navmesh_map_rid, origin, to, true)
	if path.size() < 2:
		_navmesh_has_path = false
		return
	_navmesh_path_points = path
	_navmesh_path_index = 1
	_navmesh_has_path = true


func _get_navmesh_move_direction() -> Vector3:
	if not _navmesh_has_path or _navmesh_path_points.size() < 2:
		return Vector3.ZERO
	while _navmesh_path_index < _navmesh_path_points.size() - 1:
		var to_next: Vector3 = _navmesh_path_points[_navmesh_path_index] - global_position
		if to_next.length() > rival_navmesh_path_point_threshold:
			break
		_navmesh_path_index += 1
	if _navmesh_path_index >= _navmesh_path_points.size():
		return Vector3.ZERO
	var to_next: Vector3 = _navmesh_path_points[_navmesh_path_index] - global_position
	return to_next.normalized() if to_next.length() > 0.001 else Vector3.ZERO


func _get_direct_move_to_target(target: Node3D, up: Vector3) -> Vector3:
	var to: Vector3 = target.global_position - global_position
	var planar: Vector3 = to - up * to.dot(up)
	return planar.normalized() if planar.length() > 0.001 else Vector3.ZERO


func _get_rival_lateral_speed() -> float:
	var up: Vector3 = _get_gravity_up()
	var lateral: Vector3 = velocity - up * velocity.dot(up)
	return lateral.length()


func _adjust_move_for_navmesh(move_dir: Vector3) -> Vector3:
	if not rival_use_navmesh or not _navmesh_map_rid.is_valid():
		return move_dir
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(_navmesh_map_rid, global_position)
	var to_mesh: Vector3 = closest - global_position
	var dist_to_mesh: float = to_mesh.length()
	if dist_to_mesh > 3.0:
		return to_mesh.normalized()
	if dist_to_mesh > 0.5:
		return (move_dir.normalized() + to_mesh.normalized() * rival_navmesh_off_mesh_steer).normalized()
	return move_dir


func _try_rival_obstacle_jump(up: Vector3) -> void:
	if not attached or _rival_jump_timer > 0.0 or _rival_move_dir.length() < 0.001:
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + up * rival_obstacle_check_height
	var to: Vector3 = from + _rival_move_dir * rival_obstacle_check_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	if result:
		queue_jump()
		_rival_jump_timer = rival_jump_cooldown


func _update_rival_threats(delta: float) -> void:
	if not rival_threat_enabled:
		return
	_rival_threat_reevaluate_timer = max(_rival_threat_reevaluate_timer - delta, 0.0)
	var remove_ids: Array[int] = []
	for id in _rival_threat_table.keys():
		var entry_value: Variant = _rival_threat_table[id]
		if not (entry_value is Dictionary):
			remove_ids.append(int(id))
			continue
		var entry: Dictionary = entry_value
		var target: Variant = entry.get("target", null)
		if not _is_valid_rival_target(target):
			remove_ids.append(int(id))
			continue
		var revenge: int = int(entry.get("revenge", 0))
		var threat: float = float(entry.get("threat", 0.0))
		var target_node: Node3D = target as Node3D
		if revenge > 0:
			var now: float = Time.get_ticks_msec() * 0.001
			var last_damage_time: float = float(entry.get("last_damage_time", now))
			var revenge_age: float = max(now - last_damage_time, 0.0)
			var revenge_distance: float = (target_node.global_position - global_position).length()
			var timeout_expired: bool = rival_revenge_pursuit_timeout > 0.0 and revenge_age >= rival_revenge_pursuit_timeout
			var distance_expired: bool = rival_revenge_pursuit_max_distance > 0.0 and revenge_distance > rival_revenge_pursuit_max_distance
			if timeout_expired or distance_expired:
				revenge = 0
				threat = max(threat * 0.35, 0.0)
				entry["revenge"] = revenge
				_rival_threat_reevaluate_timer = 0.0
				if _rival_focus_target == target_node:
					_set_rival_focus_target(null)
		threat = max(threat - max(rival_threat_decay_per_sec, 0.0) * delta, 0.0)
		if revenge > 0:
			threat = max(threat, max(rival_revenge_min_threat, 0.0))
		entry["threat"] = threat
		_rival_threat_table[id] = entry
		if threat <= 0.0 and revenge <= 0:
			remove_ids.append(int(id))
	for id in remove_ids:
		_rival_threat_table.erase(id)


func _register_rival_damage_threat(source: Node, amount: int) -> void:
	if not rival_threat_enabled:
		return
	if source == null or not is_instance_valid(source) or not (source is Node3D) or source == self:
		return
	var source_target: Node3D = source as Node3D
	if not _is_valid_rival_target(source_target):
		return
	var id: int = source_target.get_instance_id()
	var entry: Dictionary = {}
	var entry_value: Variant = _rival_threat_table.get(id, {})
	if entry_value is Dictionary:
		entry = entry_value
	entry["target"] = source_target
	entry["threat"] = float(entry.get("threat", 0.0)) + float(max(amount, 1)) * max(rival_threat_damage_weight, 0.0)
	entry["revenge"] = int(entry.get("revenge", 0)) + max(rival_revenge_strikes_per_hit, 0)
	entry["last_damage_time"] = Time.get_ticks_msec() * 0.001
	_rival_threat_table[id] = entry
	_set_rival_focus_target(source_target)
	_rival_threat_reevaluate_timer = max(rival_threat_reevaluate_interval, 0.05)
	_rival_last_reaction = "Aggro: %s" % source_target.name


func _mark_revenge_strike_satisfied(target: Variant) -> void:
	var entry: Dictionary = _get_threat_entry_for_target(target)
	if entry.is_empty():
		return
	var target_node: Node3D = target as Node3D
	var revenge: int = max(int(entry.get("revenge", 0)) - 1, 0)
	entry["revenge"] = revenge
	entry["threat"] = max(float(entry.get("threat", 0.0)) * 0.65, 0.0)
	_rival_threat_table[target_node.get_instance_id()] = entry
	if revenge <= 0:
		_rival_threat_reevaluate_timer = 0.0


func _has_pending_revenge_target(target: Variant) -> bool:
	var entry: Dictionary = _get_threat_entry_for_target(target)
	if entry.is_empty():
		return false
	return int(entry.get("revenge", 0)) > 0


func _get_threat_entry_for_target(target: Variant) -> Dictionary:
	if not _is_valid_rival_target(target):
		return {}
	var target_node: Node3D = target as Node3D
	var id: int = target_node.get_instance_id()
	if not _rival_threat_table.has(id):
		return {}
	var entry: Variant = _rival_threat_table[id]
	if entry is Dictionary:
		return entry
	return {}


func _update_rival_status_timers(delta: float) -> void:
	_rival_dazed_timer = max(_rival_dazed_timer - delta, 0.0)
	if _rival_rage_timer <= 0.0:
		return
	_rival_rage_timer = max(_rival_rage_timer - delta, 0.0)
	if _rival_rage_timer <= 0.0:
		_rival_rage = 0
		_queue_self_preserve_voice_if_active()


func _register_rival_hit() -> void:
	_rival_dazed_timer = max(rival_dazed_duration, 0.0)
	_rival_last_reaction = "Hit: dazed"
	var hits_required: int = max(rival_rage_hits_required, 0)
	if _is_rival_enraged():
		_rival_enraged_voice_pending = true
		return
	if hits_required <= 0:
		return
	_rival_rage = min(_rival_rage + 1, hits_required)
	if _rival_rage >= hits_required:
		_rival_rage_timer = max(rival_rage_duration, 0.0)
		if _rival_rage_timer <= 0.0:
			_rival_rage = 0
		else:
			_rival_enraged_voice_pending = true


func _is_rival_enraged() -> bool:
	return _rival_rage_timer > 0.0


func _update_rival_voice_cues() -> void:
	_rival_self_preserve_voice_active = _is_self_preserve_mode_active()


func _queue_rival_damage_voice_cues() -> void:
	if _rival_enraged_voice_pending:
		_rival_enraged_voice_pending = false
		if _rival_profile != null:
			_play_rival_dialogue_voice(
				_rival_profile.rival_enraged_voice_clips,
				_rival_profile.rival_enraged_voice_chance
			)
		_rival_self_preserve_voice_active = false
		return
	_queue_self_preserve_voice_if_active()


func _queue_self_preserve_voice_if_active() -> void:
	var self_preserve_active: bool = _is_self_preserve_mode_active()
	if self_preserve_active and _rival_profile != null:
		_play_rival_dialogue_voice(
			_rival_profile.rival_self_preserve_voice_clips,
			_rival_profile.rival_self_preserve_voice_chance
		)
	_rival_self_preserve_voice_active = self_preserve_active


func _is_self_preserve_mode_active() -> bool:
	return _needs_ring_self_preservation() and not _is_rival_enraged()


func _play_rival_dialogue_voice(clips: Array[AudioStream], chance: float = 1.0) -> void:
	if clips.is_empty():
		return
	play_voice_clips(clips, chance, PlayerAudio.VOICE_PRIORITY_DIALOGUE, true)


func _get_current_rival_invuln_time() -> float:
	var scale_duration: float = max(rival_invuln_scale_duration, 0.001)
	var t: float = clamp(_rival_battle_time / scale_duration, 0.0, 1.0)
	return lerp(max(rival_battle_start_invuln_time, 0.0), max(rival_battle_end_invuln_time, 0.0), t)


func _update_rival_invuln_duration() -> void:
	damage_hit_invuln_time = _get_current_rival_invuln_time()
	if _hurt_action != null:
		_hurt_action.damage_hit_invuln_time = damage_hit_invuln_time


func _get_health_fraction() -> float:
	if rival_max_health <= 0:
		return 0.0
	return clamp(_rival_health / float(rival_max_health), 0.0, 1.0)


func _get_rival_display_name() -> String:
	if rival_display_name.strip_edges() != "":
		return rival_display_name
	return name


func _apply_rival_profile() -> void:
	if rival_profile_path.strip_edges() == "":
		return

	_rival_profile = load(rival_profile_path) as RivalProfile
	if _rival_profile == null:
		push_warning("%s: Rival profile could not be loaded: %s" % [name, rival_profile_path])
		return

	for property in _rival_profile.get_property_list():
		var property_name: StringName = StringName(property.get("name", ""))
		if property_name == &"" or property_name == &"script" or not String(property_name).begins_with("rival_"):
			continue
		if not _has_object_property(self, property_name):
			continue
		set(property_name, _rival_profile.get(property_name))


func _replace_with_rival_character_scene() -> bool:
	var character_id: String = rival_character_id.strip_edges()
	if character_id == "":
		return false
	var entry: Dictionary = CharacterCatalog.get_entry_for_id(rival_character_data_dir, character_id)
	if entry.is_empty():
		return false
	var scene_path: String = String(entry.get("scene", "")).strip_edges()
	if scene_path == "":
		return false
	if String(scene_file_path) == scene_path:
		return false
	var packed = load(scene_path)
	if not (packed is PackedScene):
		return false
	var replacement = (packed as PackedScene).instantiate()
	if not (replacement is Node):
		return false
	var rival_script = load("res://LS5Framework/Scripts/AI/RivalActorPlayer.gd")
	if not (rival_script is Script):
		replacement.queue_free()
		return false
	var replacement_node: Node = replacement as Node
	var character_properties: Dictionary = _collect_scene_root_properties(replacement_node)
	replacement_node.set_script(rival_script)
	_restore_scene_root_properties(replacement_node, character_properties)
	_copy_rival_runtime_properties_to(replacement_node)
	replacement_node.name = name
	if replacement_node is Node3D:
		(replacement_node as Node3D).global_transform = global_transform
	var parent_node: Node = get_parent()
	if parent_node == null:
		replacement.queue_free()
		return false
	var sibling_index: int = get_index()
	call_deferred("_finish_rival_character_replacement", parent_node, replacement_node, sibling_index)
	return true


func _finish_rival_character_replacement(parent_node: Node, replacement_node: Node, sibling_index: int) -> void:
	if parent_node == null or not is_instance_valid(parent_node):
		if replacement_node != null and is_instance_valid(replacement_node):
			replacement_node.queue_free()
		return
	if replacement_node == null or not is_instance_valid(replacement_node):
		return
	parent_node.add_child(replacement_node)
	if replacement_node.get_parent() == parent_node:
		parent_node.move_child(replacement_node, min(sibling_index, parent_node.get_child_count() - 1))
	queue_free()


func _copy_rival_runtime_properties_to(target: Object) -> void:
	if target == null:
		return
	for property in get_property_list():
		var property_name: StringName = StringName(property.get("name", ""))
		if property_name == &"" or property_name == &"script":
			continue
		if not _should_copy_rival_runtime_property(property_name):
			continue
		if not _has_object_property(target, property_name):
			continue
		target.set(property_name, get(property_name))
	target.set("rival_character_id", rival_character_id)
	target.set("rival_character_data_dir", rival_character_data_dir)


func _collect_scene_root_properties(source: Object) -> Dictionary:
	var values: Dictionary = {}
	if source == null:
		return values
	for property in source.get_property_list():
		var property_name: StringName = StringName(property.get("name", ""))
		if property_name == &"" or property_name == &"script":
			continue
		var usage: int = int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if _should_skip_rival_overlay_property(property_name):
			continue
		values[property_name] = source.get(property_name)
	return values


func _restore_scene_root_properties(target: Object, values: Dictionary) -> void:
	if target == null:
		return
	for key in values.keys():
		var property_name: StringName = StringName(key)
		if not _has_object_property(target, property_name):
			continue
		target.set(property_name, values[key])


func _should_skip_rival_overlay_property(property_name: StringName) -> bool:
	var property_text: String = String(property_name)
	if property_text.begins_with("rival_"):
		return true
	if property_text.begins_with("buddy_"):
		return true
	if property_text.begins_with("follow_"):
		return true
	if property_text.begins_with("mimic_"):
		return true
	if property_text.begins_with("obstacle_"):
		return true
	if property_text.begins_with("spawn_sync_"):
		return true
	if property_text.begins_with("catchup_"):
		return true
	if property_text.begins_with("crowd_slow_"):
		return true
	return false


func _should_copy_rival_runtime_property(property_name: StringName) -> bool:
	var property_text: String = String(property_name)
	if property_text.begins_with("rival_"):
		return true
	if property_text.begins_with("idle_"):
		return true
	if property_text.begins_with("battle_idle_"):
		return true
	if property_name == &"activation_distance" or property_name == &"deactivation_distance":
		return true
	if property_name == &"navigation_region":
		return true
	return false


func _has_object_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _apply_rival_character_colors(target: Node3D) -> void:
	if not rival_apply_character_colors:
		return
	var primary: Color = rival_primary_color
	var secondary: Color = rival_secondary_color
	var trail: Color = rival_trail_color
	if rival_color_source == RivalColorSource.TARGET:
		if target == null:
			return
		var target_primary: Variant = target.get("_character_primary_color")
		var target_secondary: Variant = target.get("_character_secondary_color")
		if target_primary is Color:
			primary = target_primary
		else:
			return
		if target_secondary is Color:
			secondary = target_secondary
		var target_trail_node: Variant = target.get("jump_dash_trail")
		if target_trail_node is Node:
			var target_trail_color: Variant = (target_trail_node as Node).get("tint")
			if target_trail_color is Color:
				trail = target_trail_color
	if _rival_colors_applied:
		if _rival_applied_primary_color == primary and _rival_applied_secondary_color == secondary and _rival_applied_trail_color == trail:
			return
	set_character_colors(primary, secondary, trail)
	_rival_colors_applied = true
	_rival_applied_primary_color = primary
	_rival_applied_secondary_color = secondary
	_rival_applied_trail_color = trail


func _get_ai_state_name() -> String:
	match _ai_state:
		AIState.INACTIVE:
			return "Inactive"
		AIState.IDLE:
			return "Idle"
		AIState.DEFENSIVE:
			return "Defensive"
		AIState.CHASE:
			return "Chase"
		AIState.ATTACK:
			return "Attack"
	return "Unknown"


func _get_attack_type_name() -> String:
	match _rival_attack_type:
		RivalAttackType.JUMP_DASH:
			return "Jump Dash"
		RivalAttackType.ROLL_CHARGE:
			return "Roll"
		RivalAttackType.SPIN_KICK:
			return "Spin Kick"
	return "Unknown"


func _needs_ring_self_preservation() -> bool:
	if rival_resource_mode == RivalResourceMode.RINGS:
		return rings <= 0
	return rival_rings_restore_health and _get_health_fraction() <= rival_health_self_preservation_threshold


func _can_act_offensively() -> bool:
	if _is_rival_enraged():
		return true
	return not _needs_ring_self_preservation()


func _should_search_for_ring() -> bool:
	if _rival_dazed_timer > 0.0:
		return false
	if not _needs_ring_self_preservation():
		return false
	return _get_active_ring_search_radius() > 0.0


func _get_active_ring_search_radius() -> float:
	if _is_rival_enraged():
		return max(rival_rage_ring_search_radius, 0.0)
	return max(rival_ring_search_radius, 0.0)


func _update_ring_search(up: Vector3) -> bool:
	var radius: float = _get_active_ring_search_radius()
	_rival_ring_target = _find_nearest_available_ring(radius)
	if _rival_ring_target == null:
		_rival_last_reaction = "Searching: no ring"
		_set_rival_move(Vector3.ZERO)
		return false
	_rival_last_reaction = "Seeking ring"
	var move_dir: Vector3 = _get_direct_move_to_target(_rival_ring_target, up)
	if rival_use_navmesh and _ensure_navmesh_map():
		_navmesh_path_timer += get_movement_physics_delta()
		if _navmesh_path_timer >= rival_navmesh_path_recalc_interval or not _navmesh_has_path:
			_update_navmesh_path(_rival_ring_target.global_position)
			_navmesh_path_timer = 0.0
		var nav_dir: Vector3 = _get_navmesh_move_direction()
		if nav_dir.length() > 0.001:
			move_dir = nav_dir
	_set_rival_move(_adjust_move_for_navmesh(move_dir))
	_try_rival_obstacle_jump(up)
	return true


func _find_nearest_available_ring(radius: float) -> Node3D:
	if radius <= 0.0:
		return null
	var best: Node3D = null
	var best_dist_sq: float = radius * radius
	var nodes: Array = []
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("get_rings_in_range"):
		nodes = mgr.get_rings_in_range(global_position, radius)
	if get_tree() != null:
		for ring_node in get_tree().get_nodes_in_group("RivalRingSearch"):
			if not (ring_node in nodes):
				nodes.append(ring_node)
	for node in nodes:
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var ring: Node3D = node as Node3D
		if not _is_ring_available(ring):
			continue
		var dist_sq: float = (ring.global_position - global_position).length_squared()
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best = ring
	return best


func _is_ring_available(ring: Node3D) -> bool:
	if ring == null:
		return false
	if not ring.visible:
		return false
	if ring.has_meta("ignore_rival_ring_search") and bool(ring.get_meta("ignore_rival_ring_search")):
		return false
	var collected: Variant = ring.get("_collected")
	if collected is bool and bool(collected):
		return false
	return true


# ---------------------------------------------------------------------------
# Defensive reaction helpers
# ---------------------------------------------------------------------------
func _is_attack_lingering() -> bool:
	return _target_attack_linger_timer > rival_defensive_linger_threshold


func _get_reaction_chance() -> float:
	return rival_defensive_linger_reaction_chance if _is_attack_lingering() else rival_defensive_reaction_chance


func _get_parry_chance() -> float:
	return rival_defensive_linger_parry_chance if _is_attack_lingering() else rival_defensive_parry_chance


func _get_evade_roll_chance() -> float:
	return rival_defensive_linger_evade_roll_chance if _is_attack_lingering() else rival_defensive_evade_roll_chance


func _get_dodge_jump_chance() -> float:
	return rival_defensive_linger_dodge_jump_chance if _is_attack_lingering() else rival_defensive_dodge_jump_chance


func _should_react_to_attack() -> bool:
	if _target_attack_linger_timer < max(rival_reaction_min_action_age, 0.0):
		return false
	return randf() < _get_reaction_chance()


func _perform_defensive_evade(target: Node3D, up: Vector3) -> void:
	var evade_roll: float = randf()
	var roll_chance: float = _get_evade_roll_chance()
	var jump_chance: float = _get_dodge_jump_chance()
	if attached and evade_roll < roll_chance:
		if _spindash_action != null and spindash_enabled:
			_start_spindash_charge()
			_spindash_charge_time = spindash_charge_time_max * 0.5
			_trigger_spindash_release(false)
			_rival_evade_roll_timer = 0.6
		else:
			rolling = true
			_rival_evade_roll_timer = 0.6
	elif attached and evade_roll < roll_chance + jump_chance:
		if _rival_jump_timer <= 0.0:
			queue_jump()
			_rival_jump_timer = rival_jump_cooldown

	var to_player: Vector3 = target.global_position - global_position
	var planar_to: Vector3 = to_player - up * to_player.dot(up)
	if planar_to.length() > 0.001:
		var away: Vector3 = -planar_to.normalized()
		var perp: Vector3 = away.cross(up).normalized()
		if randf() < 0.5:
			perp = -perp
		_set_rival_move((away * 0.6 + perp * 0.4).normalized())
	else:
		_set_rival_move(Vector3.ZERO)


func _attempt_defensive_reaction(target: Node3D, up: Vector3) -> void:
	if randf() <= clamp(_get_parry_chance(), 0.0, 1.0):
		var hold_duration: float = randf_range(
			min(rival_defensive_shield_hold_min, rival_defensive_shield_hold_max),
			max(rival_defensive_shield_hold_min, rival_defensive_shield_hold_max)
		)
		if try_activate_insta_shield_for_ai(hold_duration):
			_rival_last_reaction = "Insta-Shield"
			_set_rival_move(Vector3.ZERO)
			return
	_rival_last_reaction = "Evade"
	_perform_defensive_evade(target, up)


# ---------------------------------------------------------------------------
# Combat resolution
# ---------------------------------------------------------------------------
func _apply_rival_combat(target: Node3D, bypass_recoil: bool = false) -> CombatOutcome:
	if _combat_recoil_timer > 0.0:
		return CombatOutcome.DRAW if bypass_recoil else CombatOutcome.LOSE

	var target_player := target as SonicPlayerRef
	if target_player == null:
		return _apply_rival_generic_combat(target, bypass_recoil)

	if (target.global_position - global_position).length() > rival_combat_hit_radius and not bypass_recoil:
		return CombatOutcome.LOSE

	var player_attacking: bool = target_player.is_attack_active()
	var rival_attacking: bool = is_attack_active()
	if not player_attacking and not rival_attacking:
		return CombatOutcome.LOSE

	_combat_recoil_timer = rival_combat_recoil_cooldown
	if player_attacking and is_insta_shield_defense_active():
		var rival_defense: int = resolve_incoming_combat_attack(target_player, target_player.velocity)
		if rival_defense != InstaShieldAction.DefenseResult.NONE:
			_rival_last_reaction = "Parried attack" if rival_defense == InstaShieldAction.DefenseResult.PARRIED else "Block broken"
			return CombatOutcome.DRAW
	if rival_attacking and target_player.is_insta_shield_defense_active():
		var player_defense: int = target_player.resolve_incoming_combat_attack(self, velocity)
		if player_defense != InstaShieldAction.DefenseResult.NONE:
			_rival_last_reaction = "Attack parried" if player_defense == InstaShieldAction.DefenseResult.PARRIED else "Broke block"
			return CombatOutcome.DRAW

	var mid: Vector3 = (global_position + target.global_position) * 0.5
	if player_attacking and rival_attacking:
		_rival_last_reaction = "Attack clash"
		var clash_speed: float = rival_combat_bounce_speed * rival_combat_draw_bounce_multiplier
		var was_attached: bool = attached
		var target_was_attached: bool = target_player.attached
		cancel_attack_for_combat_response(&"combat_clash")
		target_player.cancel_attack_for_combat_response(&"combat_clash")
		apply_enemy_bounce(mid, clash_speed, target_player)
		target_player.apply_enemy_bounce(mid, clash_speed, self)
		if was_attached:
			attached = true
		if target_was_attached:
			target_player.attached = true
		return CombatOutcome.DRAW
	if player_attacking:
		_rival_last_reaction = "Hit by attack"
		if rival_can_take_damage:
			apply_damage(1, target)
		_on_hit_by_player(target, false)
		return CombatOutcome.WIN

	_rival_last_reaction = "Landed attack"
	target_player.apply_damage(1, self)
	_mark_revenge_strike_satisfied(target)
	_on_rival_attacked_player(target)
	return CombatOutcome.LOSE


func _apply_rival_generic_combat(target: Node3D, bypass_recoil: bool = false) -> CombatOutcome:
	if target == null or not _is_valid_rival_target(target):
		return CombatOutcome.LOSE
	if (target.global_position - global_position).length() > rival_combat_hit_radius and not bypass_recoil:
		return CombatOutcome.LOSE
	if not is_attack_active() and not bypass_recoil:
		return CombatOutcome.LOSE
	if not target.has_method("apply_damage"):
		return CombatOutcome.LOSE
	_combat_recoil_timer = rival_combat_recoil_cooldown
	var arg_count: int = _get_method_argument_count(target, &"apply_damage")
	if arg_count >= 2:
		target.call("apply_damage", 1, self)
	else:
		target.call("apply_damage", 1)
	_mark_revenge_strike_satisfied(target)
	_rival_last_reaction = "Revenge strike: %s" % target.name
	return CombatOutcome.LOSE


func _get_method_argument_count(target: Object, method_name: StringName) -> int:
	for method_info in target.get_method_list():
		if not (method_info is Dictionary):
			continue
		if StringName((method_info as Dictionary).get("name", &"")) != method_name:
			continue
		var args: Variant = (method_info as Dictionary).get("args", [])
		if args is Array:
			return (args as Array).size()
	return 1


# ---------------------------------------------------------------------------
# Combat event hooks – override in subclasses or connect signals externally
# ---------------------------------------------------------------------------
func _on_hit_by_player(_attacker: Node, _jump_held: bool) -> void:
	pass


func _on_rival_attacked_player(_target: Node) -> void:
	pass


# ---------------------------------------------------------------------------
# Rival HUD
# ---------------------------------------------------------------------------
func _update_rival_hud(target: Node3D, dist: float) -> void:
	if not rival_hud_enabled or target == null or dist > rival_hud_visible_distance or _rival_is_defeated or _is_dead:
		_hide_rival_hud()
		return
	_ensure_rival_hud()
	if _rival_hud_panel == null:
		return
	_rival_hud_panel.visible = true
	if _rival_hud_title_label != null:
		_rival_hud_title_label.text = _get_rival_display_name()
	if rival_resource_mode == RivalResourceMode.RINGS:
		if _rival_hud_health_bar != null:
			_rival_hud_health_bar.visible = false
		if _rival_hud_ring_label != null:
			_rival_hud_ring_label.visible = true
			_rival_hud_ring_label.text = "Rings: %d" % rings
	else:
		if _rival_hud_ring_label != null:
			_rival_hud_ring_label.visible = false
		if _rival_hud_health_bar != null:
			_rival_hud_health_bar.visible = true
			_rival_hud_health_bar.value = _get_health_fraction() * 100.0
	if _rival_hud_rage_label != null:
		if _is_rival_enraged():
			_rival_hud_rage_label.text = "Enraged %.1f" % _rival_rage_timer
		else:
			_rival_hud_rage_label.text = "Rage %d/%d" % [_rival_rage, max(rival_rage_hits_required, 0)]
	if _rival_hud_debug_label != null:
		var debug_enabled: bool = _is_rival_debug_hud_enabled(target)
		_rival_hud_debug_label.visible = debug_enabled
		if debug_enabled:
			_rival_hud_debug_label.text = _get_rival_debug_hud_text(dist)


func _ensure_rival_hud() -> void:
	if _rival_hud_panel != null and is_instance_valid(_rival_hud_panel):
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	_rival_hud_layer = CanvasLayer.new()
	_rival_hud_layer.name = "RivalStatusHUD"
	viewport.add_child(_rival_hud_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "RivalStatusPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -230.0
	panel.offset_top = 18.0
	panel.offset_right = -18.0
	panel.offset_bottom = 170.0
	_rival_hud_layer.add_child(panel)
	_rival_hud_panel = panel

	var box: VBoxContainer = VBoxContainer.new()
	box.name = "StatusVBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = _get_rival_display_name()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(title)
	_rival_hud_title_label = title

	var health_bar: ProgressBar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.min_value = 0.0
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(180.0, 14.0)
	box.add_child(health_bar)
	_rival_hud_health_bar = health_bar

	var ring_label: Label = Label.new()
	ring_label.name = "RingLabel"
	ring_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(ring_label)
	_rival_hud_ring_label = ring_label

	var rage_label: Label = Label.new()
	rage_label.name = "RageLabel"
	rage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(rage_label)
	_rival_hud_rage_label = rage_label

	var debug_label: Label = Label.new()
	debug_label.name = "DebugLabel"
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	debug_label.visible = false
	box.add_child(debug_label)
	_rival_hud_debug_label = debug_label


func _hide_rival_hud() -> void:
	if _rival_hud_panel != null and is_instance_valid(_rival_hud_panel):
		_rival_hud_panel.visible = false


func _is_rival_debug_hud_enabled(target: Node3D) -> bool:
	if _debug_visible:
		return true
	if target != null:
		var target_debug_visible: Variant = target.get("_debug_visible")
		if target_debug_visible is bool and bool(target_debug_visible):
			return true
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.debug_draw != Viewport.DEBUG_DRAW_DISABLED:
		return true
	return false


func _get_rival_debug_hud_text(dist: float) -> String:
	var resource_text: String = "Health %.1f/%.1f" % [_rival_health, float(max(rival_max_health, 0))]
	if rival_resource_mode == RivalResourceMode.RINGS:
		resource_text = "Rings %d" % rings
	var ring_target_text: String = "None"
	if _rival_ring_target != null and is_instance_valid(_rival_ring_target):
		ring_target_text = _rival_ring_target.name
	var focus_text: String = "None"
	var focus_score: float = 0.0
	var focus_revenge: int = 0
	if _rival_focus_target != null and is_instance_valid(_rival_focus_target):
		focus_text = _rival_focus_target.name
		focus_score = _get_target_threat_score(_rival_focus_target)
		var focus_entry: Dictionary = _get_threat_entry_for_target(_rival_focus_target)
		if not focus_entry.is_empty():
			focus_revenge = int(focus_entry.get("revenge", 0))
	return "AI: %s / %s\nMode: %s\nFocus: %s %.1f R%d\nSelf-preserve: %s\nReaction: %s\nDist: %.1f  Invuln: %.1f\nDazed: %.1f  Rage: %d %.1f\nRoll: %.1f / %.1f\nRing target: %s" % [
		_get_ai_state_name(),
		_rival_debug_status,
		resource_text,
		focus_text,
		focus_score,
		focus_revenge,
		_needs_ring_self_preservation(),
		_rival_last_reaction,
		dist,
		_damage_hit_invuln_timer,
		_rival_dazed_timer,
		_rival_rage,
		_rival_rage_timer,
		_rival_roll_attack_elapsed,
		_rival_roll_attack_timer,
		ring_target_text,
	]


# ---------------------------------------------------------------------------
# Activation / deactivation
# ---------------------------------------------------------------------------
func activate_rival() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	global_transform = _rival_spawn_transform
	collision_layer = _rival_initial_collision_layer
	collision_mask = _rival_initial_collision_mask
	_rival_health = float(rival_max_health)
	rings = max(rival_starting_rings, 0)
	_rival_deactivated = false
	_rival_is_defeated = false
	_rival_awaiting_defeat_idle = false
	_rival_defeated_idle_timer = 0.0
	_rival_respawn_timer = 0.0
	_rival_battle_active = false
	_rival_battle_time = 0.0
	_rival_rage = 0
	_rival_rage_timer = 0.0
	_rival_dazed_timer = 0.0
	_rival_self_preserve_voice_active = false
	_rival_enraged_voice_pending = false
	_rival_ring_target = null
	_rival_threat_table.clear()
	_set_rival_focus_target(null)
	_rival_threat_reevaluate_timer = 0.0
	_ai_state = AIState.INACTIVE
	velocity = Vector3.ZERO
	_rival_move_dir = Vector3.ZERO
	_rival_move_input = Vector2.ZERO
	_clear_rival_attack_state()
	_attack_cooldown_timer = 0.0
	_hurt_active = false
	_hurt_state_timer = 0.0
	_damage_hit_invuln_timer = 0.0
	_player_state_locked = false
	_is_dead = false
	_target_attack_linger_timer = 0.0
	_clear_rival_navmesh_path()
	_reset_rival_hurt_action_state()
	_rival_colors_applied = false
	_apply_rival_character_colors(null)
	_restart_animation_state_machine_for_respawn()
	_set_rival_homing_target_registered(rival_is_homing_target)


func _exit_tree() -> void:
	_set_rival_homing_target_registered(false)
	if _rival_hud_layer != null and is_instance_valid(_rival_hud_layer):
		_rival_hud_layer.queue_free()


func _set_rival_homing_target_registered(registered: bool) -> void:
	if registered:
		if not is_in_group("HomingTarget"):
			add_to_group("HomingTarget")
		var mgr = get_node_or_null("/root/HomingTargetManager")
		if mgr and mgr.has_method("register"):
			mgr.register(self)
		return
	if is_in_group("HomingTarget"):
		remove_from_group("HomingTarget")
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("unregister"):
		mgr.unregister(self)


func _update_rival_homing_target_cell(delta: float) -> void:
	if not rival_is_homing_target:
		return
	if not is_in_group("HomingTarget"):
		return
	_rival_target_spatial_update_timer = max(_rival_target_spatial_update_timer - delta, 0.0)
	if _rival_target_spatial_update_timer > 0.0:
		return
	_rival_target_spatial_update_timer = 1.0 / max(rival_target_spatial_update_rate_hz, 1.0)
	var mgr = get_node_or_null("/root/HomingTargetManager")
	if mgr and mgr.has_method("update_target"):
		mgr.update_target(self)

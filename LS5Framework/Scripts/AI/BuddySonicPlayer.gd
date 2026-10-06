extends "res://LS5Framework/Scripts/Player/SonicPlayer.gd"
class_name BuddySonicPlayer

class BuddyFollowContext:
	var up: Vector3 = Vector3.UP
	var planar: Vector3 = Vector3.ZERO
	var planar_dist: float = 0.0
	var leader_speed: float = 0.0
	var leader_forward_planar: Vector3 = Vector3.ZERO
	var slot_pos: Vector3 = Vector3.ZERO
	var slot_planar: Vector3 = Vector3.ZERO
	var slot_dist: float = 0.0
	var follow_dir: Vector3 = Vector3.ZERO
	var follow_along: float = 0.0
	var follow_lateral: Vector3 = Vector3.ZERO
	var in_sweet_spot: bool = false

@export var follow_target: Node3D

@export_group("Buddy Follow Sweet Spot")
## Desired spacing between the buddy's follow slot and the leader (world units).
@export_range(0.0, 30.0, 0.25, "or_greater") var follow_sweet_spot_distance: float = 6.0
## Allowed forward/back deadzone around the sweet spot (world units).
@export var follow_sweet_spot_deadzone: float = 0.5
## Max turn rate when steering toward the slot (deg/sec, 0 disables this limit).
@export var follow_turn_max_deg_per_sec: float = 360.0
## Time to smooth follow direction changes (seconds, 0 disables).
@export var follow_dir_smoothing_time: float = 0.12
## Speed gain per unit of distance behind the slot (units/sec per unit).
@export var follow_speed_gain: float = 6.0
## Minimum target top speed for the buddy.
@export var follow_speed_min: float = 0.0
## Maximum speed bonus over the leader (caps catch-up speed).
@export var follow_speed_max_bonus: float = 60.0
## Max speed multiplier while ahead of the sweet spot (<= 1 slows down).
@export var follow_ahead_speed_multiplier: float = 0.9
## How quickly the target speed rises to match the sweet spot (units/sec^2).
@export var follow_speed_ramp_up: float = 180.0
## How quickly the target speed falls when ahead of the sweet spot (units/sec^2).
@export var follow_speed_ramp_down: float = 260.0
## Prefer leader velocity direction over facing above this speed.
@export var follow_velocity_dir_threshold: float = 3.0

@export_group("Buddy Rail Follow")
## Enable rail following behavior based on the leader's current rail.
@export var buddy_rail_follow_enabled: bool = true
## Desired distance behind the leader along the rail (world units).
@export var buddy_rail_sweet_spot_distance: float = 2.5
## How quickly to correct rail distance toward the sweet spot (units/sec).
@export var buddy_rail_offset_correction_speed: float = 8.0

@export_group("Buddy Rail Homing")
## Allow buddy to home in to the leader's rail instead of teleporting.
@export var buddy_rail_homing_enabled = true
## Travel speed while homing to a rail entry point.
@export var buddy_rail_homing_speed = 90.0
## Snap to rail when within this distance (world units).
@export var buddy_rail_homing_snap_distance = 2.0
## Disable collisions while homing to a rail entry point.
@export var buddy_rail_homing_disable_collision = true

@export_group("Buddy Teleport")
@export var buddy_teleport_enabled: bool = true
@export var buddy_teleport_distance: float = 75.0
@export var buddy_teleport_height: float = 2.2
@export var buddy_teleport_scale_from: float = 0.2
@export var buddy_teleport_scale_time: float = 0.18
@export var buddy_post_teleport_keepup_time: float = 0.6

@export_group("Buddy Jumping")
@export var buddy_jump_enabled: bool = true
@export var obstacle_check_distance: float = 1.35
@export var obstacle_check_height: float = 0.85
@export var buddy_jump_cooldown: float = 0.25
@export var obstacle_jump_leader_range: float = 0.0

@export_group("Buddy Options")
## Keeps the buddy's gravity-up aligned with the leader's gravity-up.
@export var buddy_use_target_up_vector: bool = true
@export var buddy_disable_abilities: bool = true
@export var buddy_disable_name_tag: bool = true
@export var buddy_copy_leader_movement_settings: bool = true

var _buddy_jump_timer: float = 0.0
var _buddy_move_input: Vector2 = Vector2.ZERO
var _buddy_move_dir: Vector3 = Vector3.ZERO
var _post_teleport_keepup_timer: float = 0.0
var _follow_accel_floor: float = 0.0
var _follow_dir_smoothed: Vector3 = Vector3.ZERO
var _spawn_position_override: Vector3 = Vector3.ZERO
var _spawn_position_override_set: bool = false
var _follow_last_valid: bool = false
var _follow_last_speed_cap: float = 0.0
var _follow_last_in_sweet_spot: bool = false
var _follow_last_ahead: bool = false
var _rail_follow_active = false
var _rail_follow_target_distance = 0.0
var _rail_follow_leader_speed = 0.0
var _rail_follow_travel_sign = 1.0
var _rail_transfer_pending = false
var _rail_transfer_timer = 0.0
var _rail_transfer_path: Path3D = null
var _rail_homing_active = false
var _rail_homing_target_distance = 0.0
var _rail_homing_leader_speed = 0.0
var _rail_homing_travel_sign = 1.0
var _rail_homing_path: Path3D = null
var _rail_homing_saved_collision = false
var _rail_homing_saved_layer = 0
var _rail_homing_saved_mask = 0

@export_group("Buddy Mimic Jump")
@export var mimic_leader_jump_enabled: bool = true
@export var mimic_leader_jump_range: float = 12.0
@export var mimic_leader_jump_delay: float = 0.1

var _mimic_jump_session_active: bool = false
var _mimic_jump_press_pending: bool = false
var _mimic_jump_release_pending: bool = false
var _mimic_jump_press_timer: float = 0.0
var _mimic_jump_release_timer: float = 0.0
var _mimic_jump_held: bool = false

@export_group("Buddy Mimic Roll")
@export var mimic_leader_roll_enabled: bool = true
@export var mimic_leader_roll_range: float = 12.0

var _mimic_leader_roll_active: bool = false
var _mimic_roll_desired: bool = false

@export_group("Buddy Spawn Sync")
@export var spawn_sync_enabled: bool = true
@export var spawn_sync_copy_rotation: bool = true
@export var spawn_sync_copy_velocity: bool = true

var _teleport_tween: Tween = null
var _base_max_speed: float = 0.0
var _base_run_top_speed: float = 0.0


# ---------------------------------------------------------------------------
# Core lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	set_meta("is_buddy", true)
	set_meta("npc_affiliation", &"player_party")
	# Don't steal camera auto-target or trigger "player" volumes.
	if is_in_group("Player"):
		remove_from_group("Player")
	if is_in_group("player"):
		remove_from_group("player")
	add_to_group("NPCActor")

	# Buddy shouldn't be able to spawn another buddy.
	buddy_enable = false
	attack_magnetism_enabled = false
	homing_targeting_enabled = false

	lock_cursor_to_game = false
	name_tag_enabled = false if buddy_disable_name_tag else name_tag_enabled
	chat_bubble_enabled = false
	speed_lines_enabled = false

	# Use the base initialization (model refs, animation tree, etc.).
	super._ready()
	if _ui_module != null:
		_ui_module._clear_speed_lines()
	_configure_buddy_death_action()
	_disable_buddy_wind_sfx()
	_base_max_speed = max_speed
	_base_run_top_speed = run_top_speed
	if _spawn_position_override_set:
		global_position = _spawn_position_override


func _movement_physics_process(delta: float) -> void:
	_buddy_jump_timer = max(_buddy_jump_timer - delta, 0.0)
	_update_buddy_ai(delta)
	_update_mimic_jump(delta)
	if _rail_homing_active:
		_update_buddy_rail_homing(delta)
		if _rail_homing_active:
			var world_up: Vector3 = _get_gravity_up()

			up_direction = world_up
			attached = false
			_is_falling = false

			_update_control_anchor(world_up)
			_update_visual_up(delta)
			_update_model_orientation(delta)
			_debug_draw()
			_update_main_state_and_flags(delta)
			_update_animation(delta)
			_update_jump_dash_trail(delta)
			_network_send_state(delta)
			_sync_online_debug_puppet(delta)

			_jump_requested = false
			_prev_attached = attached
			_apply_follow_speed_cap()
			return
	super._movement_physics_process(delta)
	_apply_follow_speed_cap()


# ---------------------------------------------------------------------------
# Input/ability overrides
# ---------------------------------------------------------------------------
func _ensure_debug_input_actions() -> void:
	# Buddy shouldn't add debug/player inputs.
	pass


func _create_debug_hud() -> void:
	# Buddy doesn't need debug HUD canvas.
	pass


func _update_mouse_lock() -> void:
	# Buddy must not affect global mouse mode.
	pass


func _unhandled_input(_event: InputEvent) -> void:
	# Buddy should not react to player inputs.
	pass


func _set_manual_camera_lock(_active: bool) -> void:
	# Buddy must not lock/unlock the shared player camera rig.
	return


func _should_start_manual_airborne_torque() -> bool:
	# Buddy should never consume local trick-torque input.
	return false


func _update_manual_airborne_torque(_delta: float) -> void:
	# Ensure buddy cannot keep any trick camera lock active.
	_manual_airborne_torque_active = false
	_manual_airborne_torque_suppress_decay = false
	_manual_airborne_torque_fast_decay = false
	_manual_airborne_mouse_delta = Vector2.ZERO


func _connect_trick_signals() -> void:
	# Buddy should not register trick callbacks.
	return


func _on_trick_detected(_trick_type: int, _timer_add_seconds: float = -1.0) -> void:
	# Buddy should not register trick events.
	return


func _update_trick_detection(_delta: float) -> void:
	# Buddy should not run trick detection.
	return


func _update_air_trick_animation() -> void:
	# Buddy should not trigger trick animations.
	return


func _finalize_trick_landing() -> void:
	# Buddy should not finalize trick rewards.
	return


func _init_abilities() -> void:
	if buddy_disable_abilities:
		super._init_abilities()
		for action in _actions:
			if action != _hurt_action:
				action.enabled = false
		return
	super._init_abilities()


func _process_action_inputs() -> void:
	# Buddy abilities are either disabled or AI-driven.
	return


func _update_speed_wind_sfx() -> void:
	# Buddy should not drive movement wind audio.
	return


func _disable_buddy_wind_sfx() -> void:
	if sfx_speed_wind != null and sfx_speed_wind.playing:
		sfx_speed_wind.stop()
	sfx_speed_wind = null
	if sfx_barrier_blast_wind != null and sfx_barrier_blast_wind.playing:
		sfx_barrier_blast_wind.stop()
	sfx_barrier_blast_wind = null
	if sfx_barrier_blast_boom != null and sfx_barrier_blast_boom.playing:
		sfx_barrier_blast_boom.stop()
	sfx_barrier_blast_boom = null


func _update_roll_state() -> void:
	# Buddy shouldn't respond to player roll input.
	_update_mimic_roll()
	var want_roll: bool = _mimic_roll_desired

	if rolling:
		if not want_roll or not _can_continue_roll():
			rolling = false
	else:
		if want_roll and _can_start_roll():
			rolling = true


func on_leader_roll_changed(is_rolling: bool) -> void:
	_mimic_leader_roll_active = bool(is_rolling)


func _update_mimic_roll() -> void:
	_mimic_roll_desired = false
	if not mimic_leader_roll_enabled:
		return
	if follow_target == null or not is_instance_valid(follow_target):
		return
	if not _mimic_leader_roll_active:
		return
	if mimic_leader_roll_range > 0.0:
		var d: float = (follow_target.global_position - global_position).length()
		if d > mimic_leader_roll_range:
			return
	_mimic_roll_desired = true


func _is_jump_held() -> bool:
	return _mimic_jump_held


func _get_hud_node() -> Node:
	# Buddy should never drive the main HUD (rings, special gauge, timer, etc.).
	return null


func _set_special_gauge_ui(_fraction: float) -> void:
	# Buddy should not update HUD.
	return


func add_rings(_amount: int) -> void:
	if follow_target != null and is_instance_valid(follow_target) and follow_target.has_method("add_rings"):
		follow_target.call("add_rings", _amount)
	return


func remove_rings(_amount: int) -> int:
	return 0


func reset_rings() -> void:
	rings = 0


func apply_damage(_amount: int = 1, _source: Node = null) -> void:
	if _is_dead or _player_state_locked:
		return
	if _damage_hit_invuln_timer > 0.0:
		return
	_on_player_hurt()
	if _hurt_action != null:
		_sync_hurt_state_to_action()
		_hurt_action.apply_damage_without_ring_death(_amount, _source, false)
		_sync_hurt_state_from_action()
		return
	super.apply_damage(_amount, _source)


func apply_death_plane_damage(_source: Node = null) -> void:
	if _is_dead or _player_state_locked:
		return
	if _hurt_action != null:
		_sync_hurt_state_to_action()
		_hurt_action.apply_forced_death_damage(_source, true)
		_sync_hurt_state_from_action()
		return
	set_death_state(true)


func _configure_buddy_death_action() -> void:
	rings = 0
	if _hurt_action == null:
		return
	_hurt_action.death_camera_constraint_enabled = false
	_hurt_action.death_fade_enabled = false
	_hurt_action.death_respawn_enabled = false
	_hurt_action.hurt_invuln_flash_enabled = true


func _update_barrier_blast(_delta: float, _world_up: Vector3, _is_attached_for_movement: bool) -> void:
	# Buddy barrier blast state is synced from the leader; don't run local thresholds.
	return


func on_leader_jump_pressed() -> void:
	if _rail_transfer_pending:
		return
	if not mimic_leader_jump_enabled:
		return
	if follow_target == null or not is_instance_valid(follow_target):
		return
	if mimic_leader_jump_range > 0.0:
		var d: float = (follow_target.global_position - global_position).length()
		if d > mimic_leader_jump_range:
			return

	_mimic_jump_session_active = true
	_mimic_jump_press_pending = true
	_mimic_jump_release_pending = false
	_mimic_jump_press_timer = max(mimic_leader_jump_delay, 0.0)
	_mimic_jump_release_timer = 0.0


func on_leader_jump_released() -> void:
	if _rail_transfer_pending:
		return
	if not _mimic_jump_session_active:
		return
	_mimic_jump_release_pending = true
	_mimic_jump_release_timer = max(mimic_leader_jump_delay, 0.0)


func _update_mimic_jump(delta: float) -> void:
	if not _mimic_jump_session_active:
		_mimic_jump_held = false
		_mimic_jump_press_pending = false
		_mimic_jump_release_pending = false
		return

	if _mimic_jump_press_pending:
		_mimic_jump_press_timer = max(_mimic_jump_press_timer - delta, 0.0)
		if _mimic_jump_press_timer <= 0.0:
			_mimic_jump_press_pending = false
			if attached:
				_mimic_jump_held = true
				queue_jump()
			else:
				_mimic_jump_session_active = false
				_mimic_jump_held = false
				_mimic_jump_release_pending = false
				return

	if _mimic_jump_release_pending:
		_mimic_jump_release_timer = max(_mimic_jump_release_timer - delta, 0.0)
		if _mimic_jump_release_timer <= 0.0:
			_mimic_jump_release_pending = false
			_mimic_jump_session_active = false
			_mimic_jump_held = false


func _read_input() -> void:
	# Override player input with AI values.
	_move_input = _buddy_move_input


func _compute_move_direction() -> void:
	# Use AI-computed world direction directly.
	_move_direction = _buddy_move_dir


func _adjust_final_movement_velocity(movement_velocity: Vector3, physics_up: Vector3) -> Vector3:
	if not _follow_last_valid or _follow_last_ahead:
		return movement_velocity

	var safe_up: Vector3 = physics_up.normalized()
	if safe_up.length() < 0.001:
		safe_up = _get_gravity_up()
	var vertical_speed: float = movement_velocity.dot(safe_up)
	var planar_velocity: Vector3 = movement_velocity - safe_up * vertical_speed
	var planar_speed: float = planar_velocity.length()
	var protected_speed: float = max(min(run_top_speed, _follow_last_speed_cap), 0.0)
	var final_planar_speed: float = max(planar_speed, protected_speed)
	var protected_direction: Vector3 = _buddy_move_dir - safe_up * _buddy_move_dir.dot(safe_up)
	if protected_direction.length() < 0.001:
		protected_direction = planar_velocity
	if protected_direction.length() < 0.001:
		return movement_velocity
	protected_direction = protected_direction.normalized()
	return protected_direction * final_planar_speed + safe_up * vertical_speed


# ---------------------------------------------------------------------------
# Follow AI
# ---------------------------------------------------------------------------
func _update_buddy_ai(delta: float) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		_follow_accel_floor = 0.0
		_follow_dir_smoothed = Vector3.ZERO
		_follow_last_valid = false
		_rail_follow_active = false
		_clear_rail_transfer()
		_stop_rail_homing()
		_buddy_move_input = Vector2.ZERO
		_buddy_move_dir = Vector3.ZERO
		return

	_sync_leader_movement_limits()

	# Keep the gravity frame aligned with the leader.
	if buddy_use_target_up_vector and follow_target.has_method("get_gravity_up"):
		var uv = follow_target.call("get_gravity_up")
		if uv is Vector3 and (uv as Vector3).length() > 0.001:
			set_gravity_up(uv as Vector3)

	var up: Vector3 = _get_gravity_up().normalized()
	if up.length() < 0.001:
		up = Vector3.UP

	if _rail_homing_active:
		_follow_accel_floor = 0.0
		_follow_last_valid = false
		_buddy_move_input = Vector2.ZERO
		_buddy_move_dir = Vector3.ZERO
		return

	var to_target: Vector3 = follow_target.global_position - global_position
	var total_dist: float = to_target.length()

	if buddy_teleport_enabled and buddy_teleport_distance > 0.0 and total_dist > buddy_teleport_distance:
		var leader_state = _get_leader_rail_state()
		if not leader_state.is_empty() and _rail_active and _rail_path == leader_state.get("path"):
			# Already on the leader's rail; let rail follow handle the distance.
			pass
		elif _try_start_rail_homing():
			_follow_dir_smoothed = Vector3.ZERO
			_follow_last_valid = false
			_buddy_move_input = Vector2.ZERO
			_buddy_move_dir = Vector3.ZERO
			return
		else:
			_teleport_to_target(up)
			_follow_dir_smoothed = Vector3.ZERO
			_follow_last_valid = false
			_buddy_move_input = Vector2.ZERO
			_buddy_move_dir = Vector3.ZERO
			return

	var rail_follow_active = _update_buddy_rail_follow(delta)
	if rail_follow_active:
		_follow_accel_floor = 0.0
		_follow_last_valid = false
		_buddy_move_input = Vector2.ZERO
		_buddy_move_dir = Vector3.ZERO
		return

	var ctx: BuddyFollowContext = _build_follow_context(up, to_target)
	_follow_last_valid = true
	_follow_last_in_sweet_spot = ctx.in_sweet_spot
	_follow_last_ahead = ctx.follow_along < -max(follow_sweet_spot_deadzone, 0.2)

	_post_teleport_keepup_timer = max(_post_teleport_keepup_timer - delta, 0.0)
	_apply_follow_speed(ctx, delta)

	# Briefly "keep up" after teleport/spawn so we don't immediately brake while near the leader.
	if _post_teleport_keepup_timer > 0.0 and ctx.planar_dist > 0.001:
		var keep_dir: Vector3 = Vector3.ZERO
		# Match facing to the leader while keep-up is active.
		if follow_target is Node3D:
			var lb: Basis = (follow_target as Node3D).global_transform.basis.orthonormalized()
			global_transform = Transform3D(lb, global_transform.origin)
		if follow_target is CharacterBody3D:
			var lv: Vector3 = (follow_target as CharacterBody3D).velocity
			var lp: Vector3 = lv - up * lv.dot(up)
			if lp.length() > 0.001:
				keep_dir = lp.normalized()
				# Also match planar velocity immediately so we don't rely on acceleration.
				var bv: Vector3 = velocity
				var bv_vert: float = bv.dot(up)
				velocity = lp + up * bv_vert
		if keep_dir == Vector3.ZERO:
			keep_dir = ctx.planar / ctx.planar_dist
		_buddy_move_dir = keep_dir
		_buddy_move_input = Vector2(0.0, 1.0)
		return

	var arrive_radius: float = max(0.2, follow_sweet_spot_deadzone)
	if ctx.in_sweet_spot:
		var lock_dir: Vector3 = Vector3.ZERO
		if ctx.planar_dist > 0.001:
			lock_dir = ctx.planar / ctx.planar_dist
		if lock_dir.length() < 0.001:
			lock_dir = ctx.leader_forward_planar
		if lock_dir.length() < 0.001:
			_follow_dir_smoothed = Vector3.ZERO
			_buddy_move_input = Vector2.ZERO
			_buddy_move_dir = Vector3.ZERO
			return
		_buddy_move_dir = lock_dir
		_buddy_move_input = Vector2(0.0, 1.0)
		return

	if ctx.slot_dist <= arrive_radius or ctx.follow_dir.length() < 0.001:
		_follow_dir_smoothed = Vector3.ZERO
		_buddy_move_input = Vector2.ZERO
		_buddy_move_dir = Vector3.ZERO
		return

	var dir: Vector3 = _get_follow_steering_direction(ctx)
	if ctx.follow_along < -arrive_radius and ctx.leader_forward_planar.length() > 0.001:
		dir = ctx.leader_forward_planar
	if dir.length() < 0.001:
		_follow_dir_smoothed = Vector3.ZERO
		_buddy_move_input = Vector2.ZERO
		_buddy_move_dir = Vector3.ZERO
		return
	dir = dir.normalized()
	var smooth_time: float = max(follow_dir_smoothing_time, 0.0)
	if smooth_time > 0.0:
		if _follow_dir_smoothed.length() < 0.001:
			_follow_dir_smoothed = dir
		else:
			var t: float = 1.0 - exp(-delta / max(smooth_time, 0.001))
			var smoothed_from: Vector3 = _follow_dir_smoothed.normalized()
			_follow_dir_smoothed = smoothed_from.slerp(dir, t).normalized()
		dir = _follow_dir_smoothed
	if _buddy_move_dir.length() > 0.001:
		var current_dir: Vector3 = _buddy_move_dir.normalized()
		dir = dir.normalized()
		var dot_dir: float = clamp(current_dir.dot(dir), -1.0, 1.0)
		var angle: float = acos(dot_dir)
		var max_turn: float = deg_to_rad(max(follow_turn_max_deg_per_sec, 0.0)) * delta
		if angle > 0.001 and max_turn > 0.0:
			var t: float = min(1.0, max_turn / angle)
			dir = current_dir.slerp(dir, t).normalized()
	_buddy_move_dir = dir
	_buddy_move_input = Vector2(0.0, 1.0)

	if buddy_jump_enabled:
		_try_buddy_jump(dir, up, delta)


# ---------------------------------------------------------------------------
# Follow helpers
# ---------------------------------------------------------------------------
func set_spawn_position_override(pos: Vector3) -> void:
	_spawn_position_override = pos
	_spawn_position_override_set = true

func _build_follow_context(up: Vector3, to_target: Vector3) -> BuddyFollowContext:
	var ctx: BuddyFollowContext = BuddyFollowContext.new()
	ctx.up = up
	ctx.planar = to_target - up * to_target.dot(up)
	ctx.planar_dist = ctx.planar.length()
	ctx.leader_speed = _get_leader_speed(up)
	ctx.leader_forward_planar = _get_leader_heading_planar(up, ctx.planar, ctx.leader_speed)

	var sweet_spot: float = max(follow_sweet_spot_distance, 0.0)
	var slot_offset: Vector3 = Vector3.ZERO
	if ctx.leader_forward_planar.length() > 0.001:
		slot_offset = ctx.leader_forward_planar * sweet_spot

	ctx.slot_pos = follow_target.global_position - slot_offset

	var to_slot: Vector3 = ctx.slot_pos - global_position
	ctx.slot_planar = to_slot - up * to_slot.dot(up)
	ctx.slot_dist = ctx.slot_planar.length()

	if ctx.leader_forward_planar.length() > 0.001:
		ctx.follow_along = ctx.slot_planar.dot(ctx.leader_forward_planar)
		ctx.follow_lateral = ctx.slot_planar - ctx.leader_forward_planar * ctx.follow_along
		var sweet_radius: float = max(follow_sweet_spot_deadzone, 0.0)
		ctx.in_sweet_spot = ctx.slot_dist <= max(sweet_radius, 0.2)
	else:
		ctx.follow_along = ctx.slot_dist
		ctx.follow_lateral = Vector3.ZERO
	if ctx.slot_dist > 0.001:
		ctx.follow_dir = ctx.slot_planar / ctx.slot_dist
	else:
		ctx.follow_dir = Vector3.ZERO
	return ctx

func _get_follow_steering_direction(ctx: BuddyFollowContext) -> Vector3:
	if ctx.leader_forward_planar.length() < 0.001:
		return ctx.follow_dir

	var lookahead_distance: float = max(follow_sweet_spot_distance, 1.0)
	var steering_vector: Vector3 = ctx.leader_forward_planar * lookahead_distance + ctx.follow_lateral
	if steering_vector.length() < 0.001:
		return ctx.leader_forward_planar
	return steering_vector.normalized()


func _get_leader_speed(up: Vector3) -> float:
	if follow_target == null or not is_instance_valid(follow_target):
		return 0.0

	var leader_velocity: Vector3 = Vector3.ZERO
	if follow_target is CharacterBody3D:
		leader_velocity = (follow_target as CharacterBody3D).velocity
	elif follow_target.has_method("get_velocity"):
		var velocity_value: Variant = follow_target.call("get_velocity")
		if velocity_value is Vector3:
			leader_velocity = velocity_value as Vector3
	elif follow_target.has_method("get_linear_velocity"):
		var linear_velocity_value: Variant = follow_target.call("get_linear_velocity")
		if linear_velocity_value is Vector3:
			leader_velocity = linear_velocity_value as Vector3

	var leader_planar_velocity: Vector3 = leader_velocity - up * leader_velocity.dot(up)
	return leader_planar_velocity.length()

func _get_leader_heading_planar(up: Vector3, fallback_dir: Vector3, leader_speed: float) -> Vector3:
	var heading: Vector3 = Vector3.ZERO
	var vel_dir_threshold: float = max(follow_velocity_dir_threshold, 0.0)
	if leader_speed > vel_dir_threshold and follow_target is CharacterBody3D:
		var leader_v: Vector3 = (follow_target as CharacterBody3D).velocity
		var leader_v_planar: Vector3 = leader_v - up * leader_v.dot(up)
		if leader_v_planar.length() > 0.001:
			heading = leader_v_planar.normalized()
	if heading.length() < 0.001:
		heading = _get_leader_facing_planar(up, fallback_dir)
	return heading

func _get_leader_facing_planar(up: Vector3, fallback_dir: Vector3) -> Vector3:
	if follow_target == null or not is_instance_valid(follow_target):
		return Vector3.ZERO

	var forward: Vector3 = Vector3.ZERO
	if follow_target is Node3D:
		var leader_node: Node3D = follow_target as Node3D
		var basis: Basis = leader_node.global_transform.basis
		if _object_has_property(leader_node, "model_root"):
			var root_path = leader_node.get("model_root")
			if root_path is NodePath and root_path != NodePath() and leader_node.has_node(root_path):
				var root_node = leader_node.get_node(root_path)
				if root_node is Node3D:
					basis = (root_node as Node3D).global_transform.basis
		forward = -basis.z

	if forward.length() < 0.001 and fallback_dir.length() > 0.001:
		forward = fallback_dir.normalized()

	var u: Vector3 = up.normalized()
	if u.length() < 0.001:
		u = _get_gravity_up()

	forward -= u * forward.dot(u)
	if forward.length() < 0.001:
		return Vector3.ZERO

	return forward.normalized()

func _get_leader_rail_state() -> Dictionary:
	if follow_target == null or not is_instance_valid(follow_target):
		return {}
	if not follow_target.has_method("get_rail_session_snapshot"):
		return {}
	var state = follow_target.call("get_rail_session_snapshot")
	if state is Dictionary:
		return state
	return {}

func _get_leader_rail_switch_state() -> Dictionary:
	if follow_target == null or not is_instance_valid(follow_target):
		return {}
	if not follow_target.has_method("get_rail_switch_snapshot"):
		return {}
	var state = follow_target.call("get_rail_switch_snapshot")
	if state is Dictionary:
		return state
	return {}

func _set_rail_homing_collision_disabled(disabled: bool) -> void:
	if disabled:
		if not _rail_homing_saved_collision:
			_rail_homing_saved_collision = true
			_rail_homing_saved_layer = collision_layer
			_rail_homing_saved_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
	else:
		if _rail_homing_saved_collision:
			collision_layer = _rail_homing_saved_layer
			collision_mask = _rail_homing_saved_mask
			_rail_homing_saved_collision = false

func _stop_rail_homing() -> void:
	if not _rail_homing_active:
		return
	_rail_homing_active = false
	_rail_homing_path = null
	if buddy_rail_homing_disable_collision:
		_set_rail_homing_collision_disabled(false)

func _clear_rail_transfer() -> void:
	_rail_transfer_pending = false
	_rail_transfer_timer = 0.0
	_rail_transfer_path = null

func _cancel_mimic_jump_session() -> void:
	_mimic_jump_session_active = false
	_mimic_jump_press_pending = false
	_mimic_jump_release_pending = false
	_mimic_jump_press_timer = 0.0
	_mimic_jump_release_timer = 0.0
	_mimic_jump_held = false

func _start_rail_follow_from_leader(
	state,
	target_distance,
	travel_sign,
	leader_speed
) -> bool:
	var params = _build_rail_params_from_leader(state, target_distance, travel_sign, leader_speed)
	if params.is_empty():
		return false

	_cancel_mimic_jump_session()
	start_rail_grind(params)
	if _rail_active:
		_rail_speed = leader_speed * travel_sign
		_rail_travel_sign = travel_sign
		_rail_follow_active = true
		_rail_follow_target_distance = target_distance
		_rail_follow_leader_speed = leader_speed
		_rail_follow_travel_sign = travel_sign
		return true
	return false

func _build_rail_params_from_leader(
	state,
	target_distance,
	travel_sign,
	leader_speed
) -> Dictionary:
	var params: Dictionary = {}
	params["path"] = state.get("path")
	params["start_offset"] = target_distance
	params["start_travel_sign"] = travel_sign
	params["initial_speed"] = leader_speed

	for key in [
		"align_model",
		"align_to_path_tilt",
		"allow_jump_exit",
		"allow_reverse",
		"allow_input_reverse",
		"end_detach_distance",
		"min_speed",
		"lock_speed_enabled",
		"lock_speed_value",
		"gravity_scale",
		"player_height_offset",
		"reverse_speed_threshold",
		"reverse_boost_speed"
	]:
		if state.has(key):
			params[key] = state[key]

	return params

func _try_start_rail_homing() -> bool:
	if not buddy_rail_homing_enabled:
		return false
	var state = _get_leader_rail_state()
	if state.is_empty():
		state = _get_leader_rail_switch_state()
	if state.is_empty():
		return false

	_start_rail_homing(state)
	return _rail_homing_active

func _start_rail_homing(state) -> void:
	var leader_path: Path3D = state.get("path")
	if leader_path == null or leader_path.curve == null:
		return

	var total_length = leader_path.curve.get_baked_length()
	if total_length <= 0.01:
		return

	var leader_speed_signed = float(state.get("speed", 0.0))
	var leader_speed = abs(leader_speed_signed)
	var leader_sign = float(state.get("travel_sign", 0.0))
	if abs(leader_sign) < 0.001:
		leader_sign = -1.0 if leader_speed_signed < 0.0 else 1.0
		if abs(leader_sign) < 0.001:
			leader_sign = 1.0

	var sweet = max(buddy_rail_sweet_spot_distance, 0.0)
	var leader_dist = float(state.get("distance", 0.0))
	var target_distance = clamp(leader_dist - leader_sign * sweet, 0.0, total_length)

	_rail_homing_active = true
	_rail_homing_path = leader_path
	_rail_homing_target_distance = target_distance
	_rail_homing_leader_speed = leader_speed
	_rail_homing_travel_sign = leader_sign
	_clear_rail_transfer()
	_cancel_mimic_jump_session()
	if _rail_active:
		cancel_rail_grind()

	if buddy_rail_homing_disable_collision:
		_set_rail_homing_collision_disabled(true)

	queue_jump()

func _update_buddy_rail_homing(delta: float) -> bool:
	if not _rail_homing_active:
		return false

	var state = _get_leader_rail_state()
	if state.is_empty():
		state = _get_leader_rail_switch_state()
	if state.is_empty():
		_stop_rail_homing()
		return false

	var leader_path: Path3D = state.get("path")
	if leader_path == null or leader_path.curve == null:
		_stop_rail_homing()
		return false

	var total_length = leader_path.curve.get_baked_length()
	if total_length <= 0.01:
		_stop_rail_homing()
		return false

	var leader_speed_signed = float(state.get("speed", 0.0))
	var leader_speed = abs(leader_speed_signed)
	var leader_sign = float(state.get("travel_sign", 0.0))
	if abs(leader_sign) < 0.001:
		leader_sign = -1.0 if leader_speed_signed < 0.0 else 1.0
		if abs(leader_sign) < 0.001:
			leader_sign = 1.0

	var sweet = max(buddy_rail_sweet_spot_distance, 0.0)
	var leader_dist = float(state.get("distance", 0.0))
	var target_distance = clamp(leader_dist - leader_sign * sweet, 0.0, total_length)
	_rail_homing_target_distance = target_distance
	_rail_homing_leader_speed = leader_speed
	_rail_homing_travel_sign = leader_sign
	_rail_homing_path = leader_path

	var attach_height = float(state.get("player_height_offset", rail_default_attach_height))
	if attach_height <= 0.0:
		attach_height = rail_default_attach_height

	var base_point = leader_path.to_global(leader_path.curve.sample_baked(target_distance))
	var up_vec = leader_path.global_transform.basis * Vector3.UP
	if up_vec.length() < 0.001:
		up_vec = _get_gravity_up()
	var target_point = base_point + up_vec.normalized() * attach_height

	var to_target = target_point - global_position
	var dist = to_target.length()
	var snap = max(buddy_rail_homing_snap_distance, 0.1)
	if dist <= snap:
		var started = _start_rail_follow_from_leader(state, target_distance, leader_sign, leader_speed)
		_stop_rail_homing()
		return started

	var speed = max(buddy_rail_homing_speed, 0.0)
	if speed <= 0.0:
		speed = max(leader_speed, 0.0)
	var step = min(dist, speed * delta)
	var dir = to_target / dist
	global_position += dir * step
	velocity = dir * (step / max(delta, 0.001))
	_last_air_velocity = velocity
	attached = false
	_prev_attached = false
	return true

func _attempt_rail_transfer() -> void:
	var state = _get_leader_rail_state()
	if state.is_empty():
		state = _get_leader_rail_switch_state()
	if state.is_empty():
		_clear_rail_transfer()
		return

	var leader_path: Path3D = state.get("path")
	if leader_path == null or leader_path.curve == null:
		_clear_rail_transfer()
		return

	var total_length = leader_path.curve.get_baked_length()
	if total_length <= 0.01:
		_clear_rail_transfer()
		return

	var leader_speed_signed = float(state.get("speed", 0.0))
	var leader_speed = abs(leader_speed_signed)
	var leader_sign = float(state.get("travel_sign", 0.0))
	if abs(leader_sign) < 0.001:
		leader_sign = -1.0 if leader_speed_signed < 0.0 else 1.0
		if abs(leader_sign) < 0.001:
			leader_sign = 1.0

	var sweet = max(buddy_rail_sweet_spot_distance, 0.0)
	var leader_dist = float(state.get("distance", 0.0))
	var target_distance = clamp(leader_dist - leader_sign * sweet, 0.0, total_length)

	if buddy_rail_homing_enabled and (_rail_path != leader_path or not _rail_active):
		_start_rail_homing(state)
		if _rail_homing_active:
			return

	if _start_rail_follow_from_leader(state, target_distance, leader_sign, leader_speed):
		_clear_rail_transfer()
	else:
		_rail_transfer_timer = max(mimic_leader_jump_delay, 0.0)

func _update_buddy_rail_follow(delta: float) -> bool:
	_rail_follow_active = false
	if not buddy_rail_follow_enabled:
		_clear_rail_transfer()
		return _rail_active or _rail_homing_active

	var state = _get_leader_rail_state()
	var using_switch = false
	if state.is_empty():
		state = _get_leader_rail_switch_state()
		using_switch = not state.is_empty()

	if state.is_empty():
		_clear_rail_transfer()
		if _rail_active:
			var up: Vector3 = _get_gravity_up()
			_end_rail(true, up)
		return _rail_active or _rail_homing_active

	var leader_path: Path3D = state.get("path")
	if leader_path == null or leader_path.curve == null:
		_clear_rail_transfer()
		return _rail_active or _rail_homing_active

	var total_length = leader_path.curve.get_baked_length()
	if total_length <= 0.01:
		_clear_rail_transfer()
		return _rail_active or _rail_homing_active

	var leader_speed_signed = float(state.get("speed", 0.0))
	var leader_speed = abs(leader_speed_signed)
	var leader_sign = float(state.get("travel_sign", 0.0))
	if abs(leader_sign) < 0.001:
		leader_sign = -1.0 if leader_speed_signed < 0.0 else 1.0
		if abs(leader_sign) < 0.001:
			leader_sign = 1.0

	var sweet = max(buddy_rail_sweet_spot_distance, 0.0)
	var leader_dist = float(state.get("distance", 0.0))
	var target_distance = clamp(leader_dist - leader_sign * sweet, 0.0, total_length)

	if _rail_active and _rail_path == leader_path:
		_rail_follow_active = true
		_rail_follow_target_distance = target_distance
		_rail_follow_leader_speed = leader_speed
		_rail_follow_travel_sign = leader_sign
		_clear_rail_transfer()
		return true

	_rail_follow_target_distance = target_distance
	_rail_follow_leader_speed = leader_speed
	_rail_follow_travel_sign = leader_sign

	if using_switch:
		_rail_transfer_pending = true
		_rail_transfer_path = leader_path
		if _rail_transfer_timer <= 0.0:
			_rail_transfer_timer = max(mimic_leader_jump_delay, 0.0)
		_cancel_mimic_jump_session()

	if _rail_transfer_path != leader_path:
		_rail_transfer_path = leader_path
		_rail_transfer_pending = true
		_rail_transfer_timer = max(mimic_leader_jump_delay, 0.0)
		_cancel_mimic_jump_session()
	elif _rail_transfer_pending:
		_rail_transfer_timer = max(_rail_transfer_timer - delta, 0.0)

	if _rail_transfer_pending and _rail_transfer_timer <= 0.0:
		_attempt_rail_transfer()
		if _rail_homing_active:
			return true
		if _rail_active and _rail_path == leader_path:
			_rail_follow_active = true
			_rail_follow_target_distance = target_distance
			_rail_follow_leader_speed = leader_speed
			_rail_follow_travel_sign = leader_sign
			return true

	if _rail_active:
		_rail_follow_active = true
		_rail_follow_target_distance = _rail_distance
		_rail_follow_leader_speed = abs(_rail_speed)
		_rail_follow_travel_sign = _rail_travel_sign
		return true

	return _rail_homing_active


# ---------------------------------------------------------------------------
# Rail follow motion
# ---------------------------------------------------------------------------
func _update_rail_motion(delta: float, world_up: Vector3) -> void:
	if not _rail_follow_active:
		super._update_rail_motion(delta, world_up)
		return

	if not _rail_active or _rail_path == null or _rail_path.curve == null:
		_stop_rail_grind_sfx()
		if _rail_active:
			_play_rail_detach_sfx()
		_rail_active = false
		_rail_crouching = false
		return

	_move_input = Vector2.ZERO
	_rail_crouching = false
	_rail_switch_active = false

	var curve = _rail_path.curve
	var total_length = _rail_total_length
	if total_length <= 0.01:
		total_length = curve.get_baked_length()
		_rail_total_length = total_length
	if total_length <= 0.01:
		_stop_rail_grind_sfx()
		_play_rail_detach_sfx()
		_rail_active = false
		_rail_crouching = false
		return

	var travel_sign = _rail_follow_travel_sign
	if abs(travel_sign) < 0.001:
		travel_sign = 1.0
	_rail_travel_sign = travel_sign

	var target_distance = clamp(_rail_follow_target_distance, 0.0, total_length)
	var leader_speed = max(_rail_follow_leader_speed, 0.0)
	var along_delta = (target_distance - _rail_distance) * travel_sign

	var correction_speed = max(buddy_rail_offset_correction_speed, 0.0)
	var adjust_speed = 0.0
	if correction_speed > 0.0:
		var needed = abs(along_delta) / max(delta, 0.001)
		adjust_speed = min(correction_speed, needed)
		if along_delta < 0.0:
			adjust_speed = -adjust_speed

	var desired_speed = max(leader_speed + adjust_speed, 0.0)
	var prev_distance = _rail_distance
	_rail_speed = desired_speed * travel_sign
	var next_distance = prev_distance + _rail_speed * delta

	if along_delta > 0.0:
		if travel_sign > 0.0:
			next_distance = min(next_distance, target_distance)
		else:
			next_distance = max(next_distance, target_distance)

	var end_buffer = clamp(_rail_end_detach_distance, 0.0, total_length * 0.5)
	if end_buffer > 0.0:
		if travel_sign > 0.0 and next_distance >= total_length - end_buffer:
			_rail_distance = total_length if travel_sign > 0.0 else 0.0
			_ensure_modules()
			_rail_module._finish_rail_endpoint(world_up)
			return
		if travel_sign < 0.0 and next_distance <= end_buffer:
			_rail_distance = total_length if travel_sign > 0.0 else 0.0
			_ensure_modules()
			_rail_module._finish_rail_endpoint(world_up)
			return

	if next_distance < 0.0 or next_distance > total_length:
		_rail_distance = clamp(next_distance, 0.0, total_length)
		_ensure_modules()
		_rail_module._finish_rail_endpoint(world_up)
		return

	_rail_distance = next_distance
	var actual_step = abs(_rail_distance - prev_distance)
	var actual_speed = actual_step / max(delta, 0.001)
	_rail_speed = actual_speed * travel_sign

	_ensure_modules()
	var rail_point: Vector3 = _rail_path.to_global(curve.sample_baked(_rail_distance))
	var path_dir: Vector3 = _get_rail_tangent_world(curve, _rail_distance, _rail_total_length).normalized()
	if path_dir.length_squared() < 0.001:
		path_dir = _rail_last_tangent.normalized()
	var up_vec: Vector3 = _rail_module._sample_rail_up(_rail_distance, path_dir, world_up)
	var motion_dir: Vector3 = path_dir * travel_sign
	_rail_last_tangent = path_dir
	_rail_last_motion_dir = motion_dir
	var next_position: Vector3 = rail_point + up_vec * _rail_attach_height
	if _rail_module._try_rail_collision_handoff(next_position, up_vec, world_up):
		return
	visual_up = up_vec
	up_direction = visual_up

	var attach_offset: Vector3 = visual_up * _rail_attach_height
	global_position = rail_point + attach_offset
	velocity = motion_dir * abs(_rail_speed)
	attached = true

	if _rail_align_model:
		var face_dir = path_dir
		var spindash_on_rail = _spindash_charging and spindash_enabled
		if spindash_on_rail:
			var desired_sign = _get_rail_spindash_release_sign(path_dir, world_up)
			face_dir = path_dir * desired_sign
		var f = face_dir - visual_up * face_dir.dot(visual_up)
		if f.length() > 0.001:
			_model_forward = f.normalized()
		var right = _model_forward.cross(visual_up)
		if right.length() < 0.001:
			right = Vector3.RIGHT - visual_up * Vector3.RIGHT.dot(visual_up)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		var forward = visual_up.cross(right).normalized()
		_rail_model_basis = Basis(right, visual_up, -forward).orthonormalized()
		_rail_model_basis_valid = true
	else:
		_rail_model_basis_valid = false


# ---------------------------------------------------------------------------
# Follow speed
# ---------------------------------------------------------------------------
func _apply_follow_speed(ctx: BuddyFollowContext, delta: float) -> void:
	var min_speed: float = max(follow_speed_min, 0.0)
	var max_bonus: float = max(follow_speed_max_bonus, 0.0)
	var gain: float = max(follow_speed_gain, 0.0)
	var deadzone: float = max(follow_sweet_spot_deadzone, 0.2)
	var ramp_up: float = max(follow_speed_ramp_up, 0.0)
	var ramp_down: float = max(follow_speed_ramp_down, 0.0)
	var base_max: float = _base_max_speed if _base_max_speed > 0.0 else max_speed

	var position_error: float = max(ctx.slot_dist - deadzone, 0.0)
	var distance_correction: float = position_error * gain
	var braking_correction: float = sqrt(2.0 * max(ramp_down, 0.001) * position_error)
	var correction_speed: float = min(distance_correction, braking_correction, max_bonus)
	var behind: bool = ctx.follow_along > deadzone
	var ahead: bool = ctx.follow_along < -deadzone
	var target_speed: float = ctx.leader_speed
	var max_speed_target: float = max(base_max, ctx.leader_speed)

	if ctx.in_sweet_spot:
		target_speed = ctx.leader_speed
	elif behind:
		target_speed = ctx.leader_speed + correction_speed
		max_speed_target += max_bonus
	elif ahead:
		var ahead_mult: float = clamp(follow_ahead_speed_multiplier, 0.0, 1.0)
		target_speed = max(ctx.leader_speed - abs(ctx.follow_along) * gain, ctx.leader_speed * ahead_mult)
	else:
		var lateral_bonus: float = min(correction_speed, max_bonus * 0.5)
		target_speed = ctx.leader_speed + lateral_bonus
		max_speed_target += max_bonus * 0.5

	target_speed = clamp(target_speed, min_speed, max_speed_target)
	_follow_last_speed_cap = target_speed
	var current_speed_cap: float = run_top_speed
	var ramp_rate: float = ramp_up if target_speed > current_speed_cap else ramp_down
	if ramp_rate > 0.0:
		current_speed_cap = move_toward(current_speed_cap, target_speed, ramp_rate * delta)
	else:
		current_speed_cap = target_speed
	current_speed_cap = min(current_speed_cap, max_speed_target)

	run_top_speed = current_speed_cap
	air_top_speed = current_speed_cap

	if behind and not ctx.in_sweet_spot:
		_follow_accel_floor = position_error * gain
		var current_planar_velocity: Vector3 = velocity - ctx.up * velocity.dot(ctx.up)
		var speed_diff: float = max(current_speed_cap - current_planar_velocity.length(), 0.0)
		_follow_accel_floor = max(_follow_accel_floor, speed_diff * 2.0)
	else:
		_follow_accel_floor = 0.0

	max_speed = max(base_max, current_speed_cap)


func _sync_leader_movement_limits() -> void:
	if not buddy_copy_leader_movement_settings:
		return
	if follow_target == null or not is_instance_valid(follow_target):
		return

	if _object_has_property(follow_target, "run_top_speed"):
		_base_run_top_speed = max(float(follow_target.get("run_top_speed")), 0.0)
	if _object_has_property(follow_target, "max_speed"):
		_base_max_speed = max(float(follow_target.get("max_speed")), 0.0)

func _sample_curve_by_speed(curve: Curve, speed: float, fallback_value: float) -> float:
	var base_value: float = PlayerMath.sample_curve_by_speed(curve, speed, fallback_value)
	if _follow_accel_floor <= 0.0:
		return base_value

	if curve == ground_accel_curve or curve == barrier_blast_ground_accel_curve:
		return max(base_value, _follow_accel_floor)
	if curve == air_accel_curve:
		return max(base_value, _follow_accel_floor * 0.7)
	return base_value


func _get_ground_anim_speed_for_max() -> float:
	if _base_run_top_speed > 0.0:
		return _base_run_top_speed
	return run_top_speed


# ---------------------------------------------------------------------------
# Teleport + spawn sync
# ---------------------------------------------------------------------------
func _apply_follow_speed_cap() -> void:
	if not _follow_last_valid:
		return
	if not (_follow_last_in_sweet_spot or _follow_last_ahead):
		return
	var cap: float = max(_follow_last_speed_cap, 0.0)
	var up: Vector3 = _get_gravity_up()
	var v: Vector3 = velocity
	var vertical: float = v.dot(up)
	var planar: Vector3 = v - up * vertical
	var speed: float = planar.length()
	if speed > cap and speed > 0.001:
		planar = planar.normalized() * cap
		velocity = planar + up * vertical

func _teleport_to_target(up: Vector3) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		return

	var safe_up: Vector3 = up.normalized()
	if safe_up.length() < 0.001:
		safe_up = _get_gravity_up()

	var target_pos: Vector3 = follow_target.global_position + safe_up * buddy_teleport_height
	global_position = target_pos
	attached = false
	_attachment_immunity = 0.0
	match_leader_spawn_state(follow_target)
	# Always copy leader velocity on teleport so the buddy can immediately keep up.
	if follow_target is CharacterBody3D:
		velocity = (follow_target as CharacterBody3D).velocity
	elif not spawn_sync_copy_velocity:
		velocity = Vector3.ZERO

	_post_teleport_keepup_timer = max(buddy_post_teleport_keepup_time, 0.0)

	var visual: Node3D = model_root if model_root != null else self

	var from_scale: float = clamp(buddy_teleport_scale_from, 0.01, 1.0)
	visual.scale = Vector3(from_scale, from_scale, from_scale)

	if _teleport_tween != null:
		_teleport_tween.kill()
	_teleport_tween = null

	if get_tree() == null:
		return

	var t: Tween = get_tree().create_tween()
	_teleport_tween = t
	t.tween_property(visual, "scale", Vector3.ONE, max(buddy_teleport_scale_time, 0.01))\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)


func match_leader_spawn_state(leader: Node3D) -> void:
	if not spawn_sync_enabled:
		return
	if leader == null or not is_instance_valid(leader):
		return

	if spawn_sync_copy_rotation:
		var b: Basis = leader.global_transform.basis.orthonormalized()
		global_transform = Transform3D(b, global_transform.origin)

	if spawn_sync_copy_velocity and leader is CharacterBody3D:
		velocity = (leader as CharacterBody3D).velocity

	# Copy movement baselines from the leader so the buddy accelerates similarly.
	if buddy_copy_leader_movement_settings and leader.has_method("get"):
		if _object_has_property(leader, "run_top_speed"):
			run_top_speed = float(leader.get("run_top_speed"))
			_base_run_top_speed = run_top_speed
		if _object_has_property(leader, "air_top_speed"):
			air_top_speed = float(leader.get("air_top_speed"))
		if _object_has_property(leader, "max_speed"):
			max_speed = float(leader.get("max_speed"))

		if _object_has_property(leader, "ground_accel_curve"):
			ground_accel_curve = leader.get("ground_accel_curve")
		if _object_has_property(leader, "air_accel_curve"):
			air_accel_curve = leader.get("air_accel_curve")

		_base_max_speed = max_speed

	# After spawn/teleport sync, keep moving briefly so we don't immediately brake
	# just because we spawned near the sweet spot.
	_post_teleport_keepup_timer = max(buddy_post_teleport_keepup_time, 0.0)

	if leader.has_method("get_gravity_up"):
		var uv = leader.call("get_gravity_up")
		if uv is Vector3 and (uv as Vector3).length() > 0.001:
			set_gravity_up(uv as Vector3)


func sync_leader_barrier_blast(gauge_fraction: float, is_active: bool) -> void:
	_barrier_blast_gauge = clamp(gauge_fraction, 0.0, 1.0)
	_barrier_blast_active = bool(is_active)
	_set_special_gauge_ui(_barrier_blast_gauge)


func _try_buddy_jump(dir: Vector3, up: Vector3, delta: float) -> void:
	if _buddy_jump_timer > 0.0:
		return
	if not attached:
		return
	if obstacle_jump_leader_range > 0.0 and follow_target != null and is_instance_valid(follow_target):
		var d: float = (follow_target.global_position - global_position).length()
		if d > obstacle_jump_leader_range:
			return

	if get_world_3d() == null:
		return

	var origin: Vector3 = global_position + up * obstacle_check_height
	var end: Vector3 = origin + dir * obstacle_check_distance
	var params = PhysicsRayQueryParameters3D.create(origin, end)
	# Exclude self and the follow target so the buddy doesn't jump because it "hit" the player.
	var ex: Array = [self]
	if follow_target != null and is_instance_valid(follow_target):
		ex.append(follow_target)
	params.exclude = ex
	var hit = get_world_3d().direct_space_state.intersect_ray(params)
	if not hit:
		return

	# If we still hit the leader (or another player pawn), ignore it.
	if hit is Dictionary and hit.has("collider"):
		var c = hit["collider"]
		if c != null and is_instance_valid(c):
			if follow_target != null and c == follow_target:
				return
			if c is Node and ((c as Node).is_in_group("Player") or (c as Node).is_in_group("player")):
				return

	# Jump using the same mechanics as the player (shared physics).
	queue_jump()
	_buddy_jump_timer = max(buddy_jump_cooldown, 0.0)

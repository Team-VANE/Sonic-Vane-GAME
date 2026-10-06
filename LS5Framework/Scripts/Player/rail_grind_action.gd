class_name RailGrindAction
extends CharacterAction

@export_group("Rail Grind")

@export_subgroup("Movement")
@export var rail_jump_vertical_speed: float = 35.0
@export var rail_default_attach_height: float = 0.9
@export var rail_align_to_path_tilt: bool = true
@export_range(0.0, 2.0) var rail_end_detach_distance: float = 0.05
## Cooldown before the same rail can be attached again.
@export_range(0.0, 5.0, 0.01) var rail_rehit_cooldown: float = 0.3

@export_subgroup("Movement/Reverse")
@export var rail_allow_input_reverse: bool = false
@export var rail_reverse_speed_threshold: float = 10.0
@export var rail_reverse_boost_speed: float = 10.0
@export_range(0.0, 1.0) var rail_reverse_input_dot_threshold: float = 0.35

@export_subgroup("Movement/Crouch")
@export var rail_crouch_enabled: bool = true
@export var rail_crouch_uphill_decel: float = 18.0
@export var rail_crouch_downhill_accel: float = 24.0

@export_subgroup("Proximity Snap")
## Enables rail attachment from proximity to the rail path.
@export var rail_path_snap_enabled: bool = true
## Proximity snap radius at zero speed.
@export_range(0.0, 20.0, 0.1) var rail_path_snap_radius_min: float = 1.5
## Proximity snap radius at or above the configured maximum-radius speed.
@export_range(0.0, 20.0, 0.1) var rail_path_snap_radius_max: float = 4.0
## Speed where proximity snap reaches its maximum radius.
@export_range(0.0, 300.0, 0.1) var rail_path_snap_speed_for_max_radius: float = 90.0
## Blocks proximity snapping when geometry separates the character and rail.
@export var rail_path_snap_obstruction_check: bool = true
## Clearance allowed before an obstruction blocks proximity snapping.
@export_range(0.0, 2.0, 0.01) var rail_path_snap_obstruction_margin: float = 0.15

@export_subgroup("Animation")
@export var rail_anim_min_scale: float = 0.8
@export var rail_anim_max_scale: float = 3.0
@export var rail_anim_speed_for_max: float = 120.0
@export var rail_anim_blend_smooth_speed: float = 75.0
@export var rail_anim_dir_smooth_speed: float = 6.0
@export var rail_anim_dir_speed_for_full: float = 8.0

@export_subgroup("Switch")
@export var rail_switch_enabled: bool = true
@export_range(10.0, 50.0) var rail_switch_query_radius: float = 30.0
@export_range(0.0, 1.0) var rail_switch_side_input_min: float = 0.35
@export_range(0.0, 1.0) var rail_switch_side_dot_min: float = 0.25
@export_range(0.0, 1.0) var rail_switch_forward_dot_min: float = 0.2
@export_range(0.0, 1.0) var rail_switch_tangent_lookahead: float = 0.05
@export_range(0.0, 150.0) var rail_switch_lateral_speed: float = 90.0
@export_range(0.0, 60.0) var rail_switch_vertical_speed: float = 50.0
@export_range(0.0, 2.0) var rail_switch_forward_speed_scale: float = 1.0
@export_range(0.0, 60.0) var rail_switch_forward_speed_min: float = 0.0
@export_range(0.0, 8.0) var rail_switch_snap_distance: float = 0.5
## Fixed duration of every rail-to-rail transfer.
@export_range(0.0, 1.5) var rail_switch_max_duration: float = 0.5
@export_range(0.0, 2.0) var rail_switch_min_end_distance: float = 0.2

@export_subgroup("Audio")
@export var rail_grind_min_speed: float = 3.0
@export var rail_grind_full_speed: float = 65.0
@export var rail_grind_volume_min_db: float = -10.0
@export var rail_grind_volume_max_db: float = 5.0
@export var rail_grind_stop_volume_db: float = -60.0
@export var rail_grind_fade_speed_db: float = 60.0
@export var rail_grind_pitch_min: float = 0.8
@export var rail_grind_pitch_max: float = 1.1

var is_active: bool = false
var rail_path: Path3D = null
var rail_distance: float = 0.0
var rail_total_length: float = 0.0
var rail_speed: float = 0.0
var align_model: bool = true
var allow_jump_exit: bool = true
var allow_reverse: bool = true
var min_speed: float = 0.0
var locked_speed: bool = false
var lock_speed_value: float = 0.0
var gravity_scale: float = 1.0
var attach_height: float = 0.9
var last_tangent: Vector3 = Vector3.FORWARD
var last_motion_dir: Vector3 = Vector3.FORWARD
var align_to_path_tilt: bool = true
var input_reverse_enabled: bool = false
var model_basis: Basis = Basis.IDENTITY
var model_basis_valid: bool = false
var reverse_speed_threshold: float = 0.0
var reverse_boost_speed: float = 0.0
var travel_sign: float = 1.0
var end_detach_distance: float = 0.0
var anim_dir_smoothed: float = 0.0
var anim_speed_smoothed: float = 0.0
var crouching: bool = false
var switch_active: bool = false
var switch_timer: float = 0.0


func _on_action_initialized() -> void:
	
	action_id = &"rail_grind"
	input_action = &""
	continuous_update = false
	allow_when_inactive = true


func can_grind() -> bool:
	if owner_player == null:
		return false
	if owner_player.get("_is_dead"):
		return false
	return enabled


func start_grind(params: Dictionary) -> bool:
	if owner_player == null:
		return false
	if not enabled:
		return false
	if owner_player.get("_is_dead"):
		return false
	if owner_player.has_method("refresh_coyote_jump_window_custom"):
		owner_player.refresh_coyote_jump_window_custom(owner_player.coyote_jump_duration)

	if is_active:
		end_grind(false, get_owner_gravity_up())

	if owner_player._homing_active:
		owner_player.cancel_homing_attack(false)

	var path: Path3D = params.get("path")
	if path == null or path.curve == null:
		return false

	var curve := path.curve
	var length := curve.get_baked_length()
	if length <= 0.01:
		return false

	rail_path = path
	rail_total_length = length
	rail_distance = clamp(params.get("start_offset", 0.0), 0.0, rail_total_length)
	rail_speed = params.get("initial_speed", 0.0)
	if abs(rail_speed) < 0.01:
		rail_speed = params.get("min_speed", 0.0)

	if abs(rail_speed) < 0.01:
		var fallback: float = max(params.get("lock_speed_value", 0.0), params.get("min_speed", 0.0))
		if fallback <= 0.0:
			fallback = 5.0
		rail_speed = fallback

	align_model = params.get("align_model", true)
	align_to_path_tilt = params.get("align_to_path_tilt", rail_align_to_path_tilt)
	allow_jump_exit = params.get("allow_jump_exit", true)
	allow_reverse = params.get("allow_reverse", true)
	input_reverse_enabled = params.get("allow_input_reverse", rail_allow_input_reverse)
	end_detach_distance = max(float(params.get("end_detach_distance", rail_end_detach_distance)), 0.0)
	min_speed = params.get("min_speed", 0.0)
	locked_speed = params.get("lock_speed_enabled", false)
	lock_speed_value = params.get("lock_speed_value", 0.0)
	if locked_speed and lock_speed_value <= 0.0:
		locked_speed = false
	gravity_scale = params.get("gravity_scale", 1.0)
	reverse_speed_threshold = max(float(params.get("reverse_speed_threshold", rail_reverse_speed_threshold)), 0.0)
	reverse_boost_speed = max(float(params.get("reverse_boost_speed", rail_reverse_boost_speed)), 0.0)
	attach_height = params.get("player_height_offset", rail_default_attach_height)
	if attach_height <= 0.0:
		attach_height = rail_default_attach_height
	last_tangent = Vector3.FORWARD

	if not allow_reverse and rail_speed < 0.0:
		rail_speed = abs(rail_speed)

	var start_travel_sign := float(params.get("start_travel_sign", 0.0))
	if abs(start_travel_sign) > 0.001:
		travel_sign = -1.0 if start_travel_sign < 0.0 else 1.0
	else:
		travel_sign = -1.0 if rail_speed < 0.0 else 1.0
	if not allow_reverse and travel_sign < 0.0:
		travel_sign = 1.0

	var start_tangent := _get_tangent_world(curve, rail_distance, rail_total_length)
	if start_tangent.length() > 0.001:
		last_tangent = start_tangent.normalized()
	last_motion_dir = last_tangent * travel_sign
	var dir_den: float = max(rail_anim_dir_speed_for_full, 0.001)
	anim_dir_smoothed = clamp(rail_speed / dir_den, -1.0, 1.0)
	anim_speed_smoothed = 0.0

	is_active = true
	owner_player.attached = true
	
	_check_and_apply_rail_boosters_on_start()
	if owner_player.has_method("reset_trick_staleness"):
		owner_player.reset_trick_staleness()
	owner_player._prev_attached = true
	owner_player._jump_dash_requested = false
	owner_player._spline_active = false
	owner_player._bounce_state = owner_player.BounceState.NONE
	owner_player._is_jumping = false
	owner_player._is_falling = false


	owner_player._play_rail_land_sfx()
	return true


func end_grind(jump_exit: bool, world_up: Vector3) -> void:
	is_active = false
	rail_path = null
	rail_distance = 0.0
	rail_total_length = 0.0
	rail_speed = 0.0
	travel_sign = 1.0
	last_tangent = Vector3.FORWARD
	last_motion_dir = Vector3.FORWARD
	model_basis_valid = false
	crouching = false
	owner_player._stop_rail_grind_sfx()


func cancel_grind(reset_velocity: bool = false) -> void:
	var gravity_up: Vector3 = get_owner_gravity_up()
	end_grind(false, gravity_up)
	if reset_velocity:
		owner_player.velocity = Vector3.ZERO


func _get_tangent_world(curve: Curve3D, distance: float, total_length: float) -> Vector3:
	if curve == null or total_length <= 0.0:
		return Vector3.FORWARD
	var d: float = clamp(distance, 0.0, total_length)
	var sample_ahead: float = min(d + 0.1, total_length)
	var sample_behind: float = max(d - 0.1, 0.0)
	var p1: Vector3 = curve.sample_baked(sample_behind)
	var p2: Vector3 = curve.sample_baked(sample_ahead)
	var tangent: Vector3 = p2 - p1
	if rail_path != null:
		tangent = rail_path.global_transform.basis * tangent
	if tangent.length() < 0.001:
		return Vector3.FORWARD
	return tangent.normalized()


func _get_spring_action():
	if owner_player == null:
		return null
	for a in owner_player._actions:
		if a is SpringAction:
			return a
	return null


func _check_and_apply_rail_boosters_on_start() -> void:
	if rail_path == null:
		return
	if owner_player == null:
		return
	
	for child in rail_path.get_children():
		if child is PathFollow3D and child.get_script() != null:
			var script_path = child.get_script().get_path()
			if script_path.contains("RailBooster"):
				if child.has_method("active") and not child.active:
					continue
				if child.has_method("require_group"):
					if child.require_group != "" and not owner_player.is_in_group(child.require_group):
						continue
				
				if child.has_method("_get_rail_path") and child.has_method("_get_rail_tangent"):
					var booster_path = child._get_rail_path()
					if booster_path != rail_path:
						continue
				
				var booster_progress: float = child.progress
				var distance_threshold: float = 6.0
				
				if abs(rail_distance - booster_progress) > distance_threshold:
					continue
				
				if owner_player.has_method("apply_rail_boost"):
					var rail_dir: Vector3 = child._get_rail_tangent()
					if rail_dir.length() < 0.001:
						continue
					var forward: Vector3 = -child.global_transform.basis.z
					if forward.length() < 0.001:
						forward = rail_dir
					var sign: float = 1.0 if rail_dir.dot(forward) >= 0.0 else -1.0
					
					var boost_spd: float = 80.0
					if child.has_property("boost_speed"):
						boost_spd = child.boost_speed
					
					var boost_mode: int = 0
					if child.has_property("boost_mode"):
						boost_mode = child.boost_mode
					
					var additive_min: float = 0.0
					if child.has_property("additive_min_speed"):
						additive_min = child.additive_min_speed
					
					owner_player.apply_rail_boost(boost_spd, boost_mode, sign, rail_path, additive_min)
					
					if child.has_method("_play_boost_sfx"):
						child._play_boost_sfx()
					
					if child.has_property("_body_cooldowns"):
						var id: int = owner_player.get_instance_id()
						var rehit: float = 0.2
						if child.has_property("rehit_cooldown"):
							rehit = child.rehit_cooldown
						child._body_cooldowns[id] = max(rehit, 0.0)

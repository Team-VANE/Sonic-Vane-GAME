class_name WallBonkAction
extends CharacterAction

@export_group("Wall Bonk")
## Minimum surface-tangential speed required before impact.
@export var minimum_speed: float = 80.0
## Maximum impact direction angle from directly into the wall.
@export_range(0.0, 89.0, 0.5) var maximum_approach_angle: float = 35.0
## Maximum wall tilt away from perpendicular to the supporting floor.
@export_range(0.0, 45.0, 0.5) var maximum_wall_tilt: float = 15.0
## Delay between impact and the backward impulse, in seconds.
@export_range(0.0, 2.0, 0.01) var knockback_delay: float = 0.1
## Initial speed away from the wall, along the supporting floor.
@export var knockback_speed: float = 25.0
## Speed removed from the knockback each second.
@export var knockback_deceleration: float = 20.0
## Animation command used for the bonk presentation.
@export var animation_command: StringName = &"CMD_WALL_BONK"
## Duration used only when animation playback timing is unavailable.
@export var fallback_duration: float = 1.42

@export_subgroup("Obstacle Trip")
## Maximum obstacle height above the supporting surface. Zero disables trips and vaults.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m") var trip_max_height: float = 2.5
## Clearance between the bottom of the player collider and the obstacle top at launch, for trips and vaults.
@export_range(0.05, 2.0, 0.05, "or_greater", "suffix:m") var trip_clearance: float = 0.25
## Fraction of incoming forward speed removed on a trip.
@export_range(0.0, 1.0, 0.01) var trip_speed_loss: float = 0.4
## Launch speed away from the supporting surface.
@export_range(0.0, 50.0, 0.5, "or_greater", "suffix:m/s") var trip_lift_speed: float = 14.0

var _active: bool = false
var _elapsed: float = 0.0
var _away: Vector3 = Vector3.ZERO
var _up: Vector3 = Vector3.UP
var _speed: float = 0.0
var _playback_state: StringName = &""

func _on_action_initialized() -> void:
	action_id = &"wall_bonk"
	input_action = &""
	input_prompt_enabled = false
	shows_jump_ball = false

func can_execute(_context: Dictionary = {}) -> bool:
	return (
		_can_check_contact() and not owner_player.rolling
		and owner_player.get_current_action_id() in [&"", &"grounded"]
	)

func _can_check_contact() -> bool:
	return (
		enabled and owner_player and owner_player.attached and not _active
		and not owner_player._hurt_active and not owner_player._is_dead and not owner_player.race_in_countdown
		and owner_player.get_current_action_id() in [&"", &"grounded", &"roll"]
		and not owner_player.is_parkour_active() and not owner_player._rail_active
		and not owner_player._automation_locks_active()
	)

func resolve_movement_contact(entry_velocity: Vector3) -> void:
	if not _can_check_contact():
		return
	var up: Vector3 = owner_player.surface_normal.normalized()
	if up.is_zero_approx():
		return
	var lateral: Vector3 = entry_velocity.slide(up)
	var vault: VaultAction = owner_player._get_action_by_id(&"vault") as VaultAction
	if vault and vault.can_start_from_contact(lateral.length()):
		if _resolve_contacts(up, lateral, vault):
			return
	if lateral.length() >= minimum_speed and can_execute():
		_resolve_contacts(up, lateral)

func _resolve_contacts(up: Vector3, lateral: Vector3, vault: VaultAction = null) -> bool:
	var sphere: Dictionary = owner_player._movement_sphere_contact
	if not sphere.is_empty() and _resolve_contact(sphere.normal, sphere.point, sphere.rid, up, lateral, vault):
		return true
	for collision: KinematicCollision3D in owner_player._get_movement_slide_collisions():
		for index: int in range(collision.get_collision_count()):
			if _resolve_contact(
				collision.get_normal(index), collision.get_position(index), collision.get_collider_rid(index),
				up, lateral, vault
			):
				return true
	return false

func _resolve_contact(
	normal: Vector3, point: Vector3, collider: RID, up: Vector3, lateral: Vector3, vault: VaultAction
) -> bool:
	if not vault:
		return try_bonk(normal, lateral, point, collider)
	var wall: Vector3 = normal.normalized()
	if absf(wall.dot(up)) >= cos(owner_player.floor_max_angle):
		return false
	var forward: Vector3 = lateral.normalized()
	var inward: Vector3 = -wall.slide(up).normalized()
	var approach: float = forward.dot(inward)
	if approach <= 0.001:
		return false
	# Use the wall-normal route when an oblique approach crosses the lip too far sideways.
	var offset: Vector3 = _get_clearance_offset(point, collider, wall, up, forward) if approach >= 0.5 else Vector3.ZERO
	if offset.is_zero_approx() and not forward.is_equal_approx(inward):
		offset = _get_clearance_offset(point, collider, wall, up, inward)
	if offset.is_zero_approx():
		return false
	if not vault.activate({"vault_position": owner_player.global_position + offset, "lateral": lateral, "up": up}):
		return false
	owner_player._movement_object_contact_handled = true
	return true

func try_bonk(
	normal: Vector3, entry_velocity: Vector3, contact_point: Vector3 = Vector3.ZERO, collider: RID = RID()
) -> bool:
	if not _can_check_contact() or normal.is_zero_approx():
		return false
	var up: Vector3 = owner_player.surface_normal.normalized()
	if up.is_zero_approx():
		return false
	var lateral: Vector3 = entry_velocity.slide(up)
	if lateral.length() < maxf(minimum_speed, 0.001):
		return false
	var wall: Vector3 = normal.normalized()
	if absf(wall.dot(up)) > sin(deg_to_rad(maximum_wall_tilt)):
		return false
	var away: Vector3 = wall.slide(up).normalized()
	if -lateral.normalized().dot(away) < cos(deg_to_rad(maximum_approach_angle)):
		return false
	if not _try_obstacle_trip(contact_point, collider, wall, up, lateral):
		if not activate({"normal": away, "up": up}):
			return false
	owner_player._movement_object_contact_handled = true
	return true

func _try_obstacle_trip(contact_point: Vector3, collider: RID, wall: Vector3, up: Vector3, lateral: Vector3) -> bool:
	var hurt: HurtAction = owner_player._hurt_action
	if not hurt or not hurt.enabled or not can_execute():
		return false
	var forward: Vector3 = lateral.normalized()
	var offset: Vector3 = _get_clearance_offset(contact_point, collider, wall, up, forward)
	var inward: Vector3 = -wall.slide(up).normalized()
	if offset.is_zero_approx() and not forward.is_equal_approx(inward):
		offset = _get_clearance_offset(contact_point, collider, wall, up, inward)
	if offset.is_zero_approx():
		return false
	var launch: Vector3 = lateral * (1.0 - clampf(trip_speed_loss, 0.0, 1.0)) + up * maxf(trip_lift_speed, 0.0)
	return hurt.start_obstacle_trip(owner_player.global_position + offset, launch, up, forward)

func _get_clearance_offset(contact_point: Vector3, collider: RID, wall: Vector3, up: Vector3, forward: Vector3) -> Vector3:
	if not collider.is_valid() or trip_max_height <= 0.0:
		return Vector3.ZERO
	var radius: float = owner_player.get_main_collision_world_radius()
	if radius <= 0.0:
		return Vector3.ZERO
	var center: Vector3 = owner_player.get_main_collision_world_center()
	var foot: Vector3 = center - up * radius
	var inset: float = 0.05
	var approach: float = forward.dot(wall)
	# Keep the top probe just inside the impact plane along the approach line.
	var probe_base: Vector3 = foot + forward * (((contact_point - foot).dot(wall) - inset) / approach)
	var probe_up: Vector3 = up - forward * (up.dot(wall) / approach)
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		probe_base + probe_up * (trip_max_height + inset), probe_base + probe_up * inset,
		owner_player.collision_mask, owner_player._get_collision_query_exclusions()
	)
	ray.hit_back_faces = false
	ray.hit_from_inside = true
	var top: Dictionary = owner_player.get_world_3d().direct_space_state.intersect_ray(ray)
	if top.is_empty() or top.rid != collider:
		return Vector3.ZERO
	var top_normal: Vector3 = top.normal
	var top_point: Vector3 = top.position
	var rise: float = (top_point - foot).dot(up)
	if top_normal.dot(up) < cos(owner_player.floor_max_angle) or rise > trip_max_height:
		return Vector3.ZERO

	var lift: Vector3 = up * (rise + maxf(trip_clearance, inset))
	var advance: Vector3 = forward * (top_point - foot).dot(forward)
	var margin: float = owner_player.safe_margin
	var raised: Transform3D = owner_player.global_transform
	if owner_player.test_move(raised, lift, null, margin):
		return Vector3.ZERO
	raised.origin += lift
	if owner_player.test_move(raised, advance, null, margin):
		return Vector3.ZERO
	raised.origin += advance
	if owner_player.test_move(raised, Vector3.ZERO, null, margin, true):
		return Vector3.ZERO
	return lift + advance

func on_action_enter(context: Dictionary = {}) -> void:
	_active = true
	_elapsed = 0.0
	_speed = maxf(knockback_speed, 0.0)
	_away = context.get("normal", Vector3.BACK)
	_up = context.get("up", get_owner_gravity_up())
	_playback_state = animation_command
	if owner_player.animation_profile:
		var target: String = String(owner_player.animation_profile.presentation_commands.get(animation_command, ""))
		if not target.is_empty():
			_playback_state = StringName(target.get_slice("/", 1))
	owner_player.velocity = Vector3.ZERO
	owner_player._is_skidding = false
	owner_player.snap_model_to_normal(_up, -_away)
	owner_player._trigger_anim_command_immediate(animation_command)

func physics_update_action(delta: float) -> void:
	if not owner_player.attached:
		owner_player.activate_neutral_air_action({"reason": &"bonk_left_floor"})
		return
	_elapsed += maxf(delta, 0.0)
	var playback: AnimationNodeStateMachinePlayback = owner_player.get_animation_director().get_active_playback()
	var finished: bool = _elapsed >= maxf(fallback_duration, knockback_delay)
	if playback and playback.get_current_node() == _playback_state and playback.get_current_length() > 0.001:
		finished = playback.get_current_play_position() >= playback.get_current_length() - 0.001
	if finished:
		owner_player.velocity = Vector3.ZERO
		owner_player.clear_active_action()
		owner_player.get_animation_director().get_action_backend().resume_motion()
		return
	var up: Vector3 = owner_player.surface_normal.normalized()
	var direction: Vector3 = _away.slide(up).normalized()
	owner_player.velocity = direction * _speed if _elapsed >= knockback_delay else Vector3.ZERO
	if _elapsed >= knockback_delay:
		_speed = move_toward(_speed, 0.0, maxf(knockback_deceleration, 0.0) * delta)

func prepare_priority_input(_delta: float) -> bool:
	if not _active:
		return false
	var slot: StringName = owner_player.get_ability_input_slot(&"jump", &"ability_slot_01")
	if SettingsManager.is_gameplay_action_just_pressed(String(slot)) and owner_player._jump_action:
		owner_player._jump_action.execute({"reason": &"bonk_cancel"})
	return true

func on_action_exit(_next_action: CharacterAction) -> void:
	_active = false
	owner_player.get_animation_director().get_action_backend().resume_motion(&"bonk_exit")

func blocks_shared_movement_integration() -> bool:
	return _active

func apply_visual_orientation() -> bool:
	return _active

func influence_movement_input(direction: Vector3, _gravity_up: Vector3) -> Vector3:
	return Vector3.ZERO if _active else direction

func get_movement_input_strength_multiplier() -> float:
	return 0.0 if _active else 1.0

func allows_profile_route(_route: Dictionary, _context: Dictionary = {}) -> bool:
	return not _active

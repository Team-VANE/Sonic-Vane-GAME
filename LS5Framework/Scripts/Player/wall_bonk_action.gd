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
		enabled and owner_player and owner_player.attached and not _active
		and not owner_player.rolling and not owner_player._hurt_active
		and not owner_player._is_dead and not owner_player.race_in_countdown
		and owner_player.get_current_action_id() in [&"", &"grounded"]
		and not owner_player.is_parkour_active() and not owner_player._rail_active
		and not owner_player._automation_locks_active()
	)

func resolve_movement_contact(entry_velocity: Vector3) -> void:
	if not can_execute() or entry_velocity.length_squared() < minimum_speed * minimum_speed:
		return
	var sphere: Dictionary = owner_player._movement_sphere_contact
	if not sphere.is_empty() and try_bonk(sphere.normal, entry_velocity):
		return
	for collision: KinematicCollision3D in owner_player._get_movement_slide_collisions():
		if try_bonk(collision.get_normal(), entry_velocity):
			return

func try_bonk(normal: Vector3, entry_velocity: Vector3) -> bool:
	if not can_execute() or normal.is_zero_approx():
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
	if not activate({"normal": away, "up": up}):
		return false
	owner_player._movement_object_contact_handled = true
	return true

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

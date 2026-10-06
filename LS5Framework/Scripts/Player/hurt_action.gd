class_name HurtAction
extends CharacterAction

const DROPPED_RING_SCENE: PackedScene = preload("res://LS5Framework/Objects/Rings/DroppedRing.tscn")
const MAX_RECOVERABLE_DROPPED_RINGS: int = 20

enum HurtType {
	NONE,
	MOVING,
	PUSHBACK,
	DEAD,
}

@export_group("Hurt and Damage")

@export_subgroup("Damage/Movement")
@export var damage_hit_invuln_time: float = 2.0
@export var damage_trip_speed_threshold: float = 40.0
@export var damage_trip_speed_multiplier: float = 0.55
@export var damage_pushback_speed: float = 30.0
@export var damage_launch_upward_speed: float = 32.0
@export var hurt_input_influence: float = 0.2
@export var hurt_air_decel_multiplier: float = 0.6
@export var hurt_ground_decel_multiplier: float = 0.1
@export var hurt_air_jump_unlock_time: float = 0.7
## Seconds between visibility toggles during hurt invulnerability.
@export var hurt_invuln_flash_interval: float = 0.04

@export_subgroup("Death/Movement")
## Sound played when damage is taken with zero rings.
@export var death_sound: AudioStream = preload("res://LS5Framework/Sounds/General/Hurt.wav")
## Pushback speed applied when dying.
@export var death_pushback_speed: float = 34.0
## Upward launch speed applied when dying.
@export var death_launch_upward_speed: float = 30.0
## Seconds airborne before the death respawn transition starts.
@export var death_airborne_respawn_delay: float = 2.0
## Seconds after dead-ground landing before the death respawn transition starts.
@export var death_grounded_respawn_delay: float = 1.5

@export_subgroup("Death/Respawn")
## Fade-out duration for death respawn.
@export var death_fade_out_duration: float = 0.35
## Hold duration at full fade during death respawn.
@export var death_fade_hold_duration: float = 0.05
## Fade-in duration after death respawn.
@export var death_fade_in_duration: float = 0.35
## Enables fade, respawn, and cleanup after the death timer completes.
@export var death_respawn_enabled: bool = true
## Enables screen fade during death respawn.
@export var death_fade_enabled: bool = true
## Creates a temporary camera constraint during death.
@export var death_camera_constraint_enabled: bool = true
## Camera aim offset while death camera is active.
@export var death_camera_aim_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
## Camera aim smoothing while death camera is active.
@export var death_camera_aim_smooth: float = 18.0
## Decreases death-camera FOV as the player travels away from the frozen camera.
@export var death_camera_distance_fov_enabled: bool = false
## Maximum FOV decrease from the player's configured camera FOV.
@export_range(0.0, 120.0, 0.1, "or_greater", "suffix:deg") var death_camera_fov_max_reduction: float = 20.0
## Additional camera-to-player distance before FOV reduction begins.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m") var death_camera_fov_reduction_start_distance: float = 0.0
## Additional camera-to-player distance where the maximum FOV reduction is reached.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:m") var death_camera_fov_reduction_full_distance: float = 30.0
## FOV response speed while distance-based reduction is active. A value of 0 applies immediately.
@export_range(0.0, 60.0, 0.1, "or_greater") var death_camera_fov_smoothing: float = 8.0
## Invulnerability time held through death respawn and after it completes.
@export var death_respawn_invuln_time: float = 0.5

@export_subgroup("Ring Spew/Resources")
## Scene spawned for each dropped ring.
@export var ring_spew_scene: PackedScene = DROPPED_RING_SCENE
## Sound played when rings are dropped.
@export var ring_spew_sound: AudioStream = preload("res://LS5Framework/Sounds/General/RingSpread.wav")
## Volume for the ring drop sound.
@export var ring_spew_sound_volume_db: float = 0.0
## Base pitch for the ring drop sound.
@export var ring_spew_sound_pitch_scale: float = 1.0

@export_subgroup("Ring Spew/Physics")
## Minimum outward speed applied to dropped rings.
@export var ring_spew_outward_speed_min: float = 18.0
## Maximum outward speed applied to dropped rings.
@export var ring_spew_outward_speed_max: float = 30.0
## Minimum upward speed applied to dropped rings.
@export var ring_spew_upward_speed_min: float = 20.0
## Maximum upward speed applied to dropped rings.
@export var ring_spew_upward_speed_max: float = 42.0
## Fraction of player velocity inherited by dropped rings.
@export var ring_spew_player_velocity_fraction: float = 0.25
## Upward spawn offset from the player origin.
@export var ring_spew_spawn_up_offset: float = 1.2
## Radial spawn offset from the player origin.
@export var ring_spew_spawn_radial_offset: float = 0.55
## Fraction of rings lost when holding more than twenty.
@export_range(0.0, 1.0, 0.01) var ring_spew_high_ring_loss_fraction: float = 0.8
## Ring count threshold before fractional loss is used.
@export var ring_spew_high_ring_threshold: int = 20

@export_subgroup("Visuals")
## Flashes the actor while hurt invulnerability is active.
@export var hurt_invuln_flash_enabled: bool = true

var is_active: bool = false
var state_timer: float = 0.0
var flash_accum: float = 0.0
var flash_visible: bool = true
var invuln_timer: float = 0.0
var flash_renderers: Array[GeometryInstance3D] = []
var hurt_type: HurtType = HurtType.NONE
var pushback_dir: Vector3 = Vector3.ZERO
var pushback_speed_locked: float = 0.0
var _anim_retriggered: bool = false
var _death_active: bool = false
var _death_grounded: bool = false
var _death_respawn_transition_active: bool = false
var _death_respawn_timer: float = 0.0
var _death_sequence_token: int = 0
var _death_camera_constraint: Node = null
var _death_camera_rig: Node = null
var _death_ground_anim_timer: float = 0.0
var _death_ground_anim_available: bool = true
var _death_pit_variant: bool = false
var _death_air_anim_timer: float = 0.0
var _death_air_anim_available: bool = true
var _flash_invulnerability_visual: bool = false


func _on_action_initialized() -> void:
	action_id = &"hurt"
	input_action = &""
	continuous_update = false
	allow_when_inactive = true


func is_death_sequence_active() -> bool:
	return _death_active or _death_respawn_transition_active


func continuous_physics_update(delta: float) -> void:
	if owner_player == null:
		return
	if _death_active:
		_update_death_state(delta)
		return
	invuln_timer = max(invuln_timer - delta, 0.0)
	if is_active:
		state_timer += delta
		if owner_player.attached:
			is_active = false
			state_timer = 0.0
			hurt_type = HurtType.NONE
			_anim_retriggered = false
		else:
			_enforce_pushback_velocity(delta)
	else:
		state_timer = 0.0
		hurt_type = HurtType.NONE
		_anim_retriggered = false


func _enforce_pushback_velocity(delta: float) -> void:
	if hurt_type != HurtType.PUSHBACK:
		return
	if state_timer >= max(hurt_air_jump_unlock_time, 0.0):
		return
	if owner_player == null:
		return
	
	var v: Vector3 = owner_player.velocity
	var vertical: float = get_gravity_vertical_component(v)
	var planar_pushback: Vector3 = get_gravity_planar_component(pushback_dir)
	if planar_pushback.length() >= 0.001:
		pushback_dir = planar_pushback.normalized()
	owner_player.velocity = compose_gravity_vector(pushback_dir * pushback_speed_locked, vertical)
	
	if not _anim_retriggered:
		owner_player._trigger_anim_command(&"CMD_HURT")
		_anim_retriggered = true


func apply_damage(amount: int = 1, source: Node = null) -> void:
	if owner_player == null:
		return
	if not owner_player._network_is_local_authority():
		return
	if _death_active or owner_player._is_dead:
		return
	if invuln_timer > 0.0:
		return

	var up: Vector3 = get_owner_gravity_up()

	if int(owner_player.get("rings")) <= 0:
		_begin_death_damage(source, up)
		return

	_begin_regular_damage(source, up, true)


func apply_damage_without_ring_death(_amount: int = 1, source: Node = null, spew_rings: bool = true) -> void:
	if owner_player == null:
		return
	if not owner_player._network_is_local_authority():
		return
	if _death_active or owner_player._is_dead:
		return
	if invuln_timer > 0.0:
		return

	var up: Vector3 = get_owner_gravity_up()
	_begin_regular_damage(source, up, spew_rings)


func apply_forced_death_damage(source: Node = null, pit_variant: bool = false) -> void:
	if owner_player == null:
		return
	if not owner_player._network_is_local_authority():
		return
	if _death_active or owner_player._is_dead:
		return

	var up: Vector3 = get_owner_gravity_up()
	_begin_death_damage(source, up, pit_variant)


func _begin_regular_damage(source: Node, up: Vector3, spew_rings: bool) -> void:
	if spew_rings:
		_spew_damage_rings(up)

	var hit_dir: Vector3 = Vector3.ZERO
	if source != null and is_instance_valid(source) and source is Node3D:
		hit_dir = owner_player.global_position - (source as Node3D).global_position
	else:
		hit_dir = -owner_player.global_transform.basis.z
	hit_dir -= up * hit_dir.dot(up)
	if hit_dir.length() < 0.001:
		hit_dir = -owner_player.global_transform.basis.z
		hit_dir -= up * hit_dir.dot(up)
	if hit_dir.length() < 0.001:
		hit_dir = Vector3.FORWARD
	hit_dir = hit_dir.normalized()

	var v: Vector3 = owner_player.velocity
	var vertical: float = get_gravity_vertical_component(v)
	var lateral: Vector3 = get_gravity_planar_component(v)
	var speed: float = lateral.length()
	var hurt_speed_threshold: float = max(damage_trip_speed_threshold, 0.0)
	var moving_hurt: bool = speed >= hurt_speed_threshold

	if speed >= damage_trip_speed_threshold:
		lateral *= clamp(damage_trip_speed_multiplier, 0.0, 1.0)
	else:
		lateral = hit_dir * max(damage_pushback_speed, 0.0)
		if not moving_hurt and source != null and is_instance_valid(source) and source is Node3D:
			var face_dir: Vector3 = (source as Node3D).global_position - owner_player.global_position
			face_dir -= up * face_dir.dot(up)
			if face_dir.length() > 0.001:
				face_dir = face_dir.normalized()
				var look_basis: Basis = Basis().looking_at(face_dir, up)
				if owner_player.model_root != null and is_instance_valid(owner_player.model_root):
					var mt: Transform3D = owner_player.model_root.global_transform
					mt.basis = look_basis.orthonormalized()
					owner_player.model_root.global_transform = mt
				else:
					var gt: Transform3D = owner_player.global_transform
					gt.basis = look_basis.orthonormalized()
					owner_player.global_transform = gt

	vertical = max(vertical, max(damage_launch_upward_speed, 0.0))

	owner_player.velocity = compose_gravity_vector(lateral, vertical)
	owner_player.attached = false
	owner_player._attachment_immunity = owner_player.launch_immunity_time
	owner_player._airborne_time = 0.0
	owner_player._jumped_from_ground = false
	owner_player._falling_without_jump = true
	owner_player._jump_variable = false
	owner_player._jump_hang_allowed = false
	owner_player._jump_time = 0.0
	owner_player._is_jumping = false

	if owner_player._homing_active or owner_player._homing_target != null:
		owner_player.cancel_homing_attack(false)

	var spindash = _get_spindash_action()
	if spindash != null:
		spindash._cancel_charge()
	owner_player._jump_dashing = false
	owner_player._jump_dash_requested = false
	owner_player._bounce_state = owner_player.BounceState.NONE

	var roll = _get_roll_action()
	if roll != null:
		roll.is_rolling = false

	if owner_player.has_method("cancel_spline_spring"):
		owner_player.call("cancel_spline_spring")
	if owner_player.has_method("cancel_rail_grind"):
		owner_player.call("cancel_rail_grind")

	is_active = true
	state_timer = 0.0
	flash_accum = 0.0
	flash_visible = true
	_set_flash_visible(true)
	invuln_timer = max(damage_hit_invuln_time, 0.0)
	_flash_invulnerability_visual = hurt_invuln_flash_enabled
	_anim_retriggered = false

	if moving_hurt:
		hurt_type = HurtType.MOVING
		pushback_dir = Vector3.ZERO
		pushback_speed_locked = 0.0
		owner_player._trigger_anim_command(&"CMD_HURT_MOVING")
	else:
		hurt_type = HurtType.PUSHBACK
		pushback_dir = hit_dir
		pushback_speed_locked = max(damage_pushback_speed, 0.0)
		owner_player._trigger_anim_command(&"CMD_HURT")
	if owner_player.has_method("play_voice_event"):
		owner_player.call("play_voice_event", &"hurt")


func apply_death_plane_damage(source: Node = null) -> void:
	if owner_player == null:
		return
	if not owner_player._network_is_local_authority():
		return
	if _death_active or owner_player._is_dead:
		return

	var up: Vector3 = get_owner_gravity_up()
	_begin_death_damage(source, up, true)


func _begin_death_damage(source: Node, up: Vector3, pit_variant: bool = false) -> void:
	if owner_player == null:
		return

	_death_sequence_token += 1
	_death_active = true
	_death_grounded = false
	_death_respawn_transition_active = false
	_death_respawn_timer = max(death_airborne_respawn_delay, 0.0)
	_death_ground_anim_timer = 0.0
	_death_ground_anim_available = true
	_death_pit_variant = pit_variant
	_death_air_anim_timer = 0.0
	_death_air_anim_available = true

	is_active = not pit_variant
	state_timer = 0.0
	hurt_type = HurtType.DEAD
	invuln_timer = max(death_respawn_invuln_time, 0.0)
	flash_accum = 0.0
	flash_visible = true
	_set_flash_visible(true)
	_flash_invulnerability_visual = false

	var death_type: StringName = &"pit" if pit_variant else &"damage"
	if owner_player.has_method("begin_death_sequence"):
		owner_player.call("begin_death_sequence", death_type)
	elif owner_player.has_method("set_death_state"):
		owner_player.call("set_death_state", true)
	else:
		owner_player._player_state_locked = true
	if owner_player.has_method("set_ui_input_blocked"):
		owner_player.call("set_ui_input_blocked", true)
	owner_player._player_state_locked = true

	if pit_variant:
		pushback_dir = Vector3.ZERO
		pushback_speed_locked = 0.0
	else:
		var hit_dir: Vector3 = _get_death_pushback_direction(source, up)
		pushback_dir = hit_dir
		pushback_speed_locked = max(death_pushback_speed, 0.0)
		owner_player.velocity = hit_dir * pushback_speed_locked + up * max(death_launch_upward_speed, 0.0)
		owner_player.attached = false
		owner_player._attachment_immunity = owner_player.launch_immunity_time
	owner_player._airborne_time = 0.0
	owner_player._jumped_from_ground = false
	owner_player._falling_without_jump = true
	owner_player._jump_variable = false
	owner_player._jump_hang_allowed = false
	owner_player._jump_time = 0.0
	owner_player._is_jumping = false
	owner_player._move_input = Vector2.ZERO
	owner_player._move_direction = Vector3.ZERO

	if owner_player._homing_active or owner_player._homing_target != null:
		owner_player.cancel_homing_attack(false)
	var spindash = _get_spindash_action()
	if spindash != null:
		spindash._cancel_charge()
	var roll = _get_roll_action()
	if roll != null:
		roll.is_rolling = false
	owner_player._jump_dashing = false
	owner_player._jump_dash_requested = false
	owner_player._bounce_state = owner_player.BounceState.NONE
	if owner_player.has_method("cancel_spline_spring"):
		owner_player.call("cancel_spline_spring")
	if owner_player.has_method("cancel_rail_grind"):
		owner_player.call("cancel_rail_grind")
	if owner_player.has_method("clear_active_action"):
		owner_player.call("clear_active_action")

	if owner_player.has_method("play_voice_event"):
		owner_player.call("play_voice_event", &"pit" if pit_variant else &"death")
	_play_death_sound()
	_start_death_camera_constraint()
	if pit_variant:
		_force_death_air_animation(0.0)
	else:
		owner_player._trigger_anim_command(&"CMD_DEADFALL")


func _update_death_state(delta: float) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		_cleanup_death_camera_constraint()
		_death_active = false
		return

	state_timer += delta
	invuln_timer = max(invuln_timer - delta, 0.0)
	_refresh_death_respawn_invulnerability()
	owner_player._move_input = Vector2.ZERO
	owner_player._move_direction = Vector3.ZERO
	if owner_player.has_method("set_ui_input_blocked"):
		owner_player.call("set_ui_input_blocked", true)
	owner_player._player_state_locked = true

	if not _death_respawn_transition_active:
		if owner_player.attached:
			owner_player.velocity = Vector3.ZERO
			if not _death_grounded:
				_enter_death_grounded()
			else:
				_force_death_ground_animation(delta)
		elif _death_pit_variant:
			_force_death_air_animation(delta)

	if not _death_respawn_transition_active:
		_death_respawn_timer = max(_death_respawn_timer - delta, 0.0)
		if _death_respawn_timer <= 0.0:
			_start_death_respawn_transition()


func _enter_death_grounded() -> void:
	_death_grounded = true
	_death_respawn_timer = max(death_grounded_respawn_delay, 0.0)
	owner_player.velocity = Vector3.ZERO
	if owner_player.has_method("play_action_command_if_exists"):
		_death_ground_anim_available = bool(owner_player.call("play_action_command_if_exists", &"deadground"))
	else:
		owner_player._trigger_anim_command(&"CMD_DEADGROUND")
	_death_ground_anim_timer = 0.25


func _force_death_ground_animation(delta: float) -> void:
	if not _death_ground_anim_available:
		return
	if _is_death_reaction_current_or_pending(&"CMD_DEADGROUND"):
		return
	_death_ground_anim_timer = max(_death_ground_anim_timer - delta, 0.0)
	if _death_ground_anim_timer > 0.0:
		return
	if owner_player.has_method("play_action_command_if_exists"):
		_death_ground_anim_available = bool(owner_player.call("play_action_command_if_exists", &"deadground"))
	else:
		owner_player._trigger_anim_command(&"CMD_DEADGROUND")
	_death_ground_anim_timer = 0.25


func _force_death_air_animation(delta: float) -> void:
	if not _death_air_anim_available:
		return
	if _is_death_reaction_current_or_pending(&"CMD_DEADPIT"):
		return
	_death_air_anim_timer = max(_death_air_anim_timer - delta, 0.0)
	if _death_air_anim_timer > 0.0:
		return
	if owner_player.has_method("play_action_command_if_exists"):
		_death_air_anim_available = bool(owner_player.call("play_action_command_if_exists", &"deadpit"))
	else:
		_death_air_anim_available = false
	_death_air_anim_timer = 0.25


func _is_death_reaction_current_or_pending(command: StringName) -> bool:
	if not owner_player:
		return false
	if owner_player._pending_anim_command == command:
		return true
	if not owner_player.anim_state or owner_player.anim_state.get_current_node() != &"REACTIONS":
		return false
	return owner_player._get_animation_group_current_node("REACTIONS") == command


func _start_death_respawn_transition() -> void:
	if _death_respawn_transition_active:
		return
	_death_respawn_transition_active = true
	if not death_respawn_enabled:
		return
	var token: int = _death_sequence_token
	_run_death_respawn_transition_async(token)


func _run_death_respawn_transition_async(token: int) -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		_finish_death_state(token)
		return

	_refresh_death_respawn_invulnerability()
	var fader: Node = _get_or_create_fader() if death_fade_enabled else null
	if death_fade_enabled and fader != null and fader.has_method("fade_out"):
		await fader.call("fade_out", death_fade_out_duration)
		if token != _death_sequence_token:
			return
	if death_fade_enabled and fader != null and get_tree() != null and death_fade_hold_duration > 0.0:
		await get_tree().create_timer(death_fade_hold_duration).timeout
		if token != _death_sequence_token:
			return

	if owner_player != null and is_instance_valid(owner_player):
		_refresh_death_respawn_invulnerability()
		if owner_player.has_method("cancel_spline_spring"):
			owner_player.call("cancel_spline_spring")
		if owner_player.has_method("cancel_rail_grind"):
			owner_player.call("cancel_rail_grind")
		if owner_player.has_method("respawn_checkpoint_now"):
			owner_player.call("respawn_checkpoint_now")
		elif owner_player.has_method("respawn_now"):
			owner_player.call("respawn_now")
		elif owner_player.has_method("_respawn"):
			owner_player.call("_respawn")
		var death_type: StringName = &"pit" if _death_pit_variant else &"damage"
		if owner_player.has_method("apply_death_respawn_consequences"):
			owner_player.call("apply_death_respawn_consequences", death_type)
		elif owner_player.has_method("reset_rings"):
			owner_player.call("reset_rings")
		_refresh_death_respawn_invulnerability()
		if owner_player.camera_rig != null and owner_player.camera_rig.has_method("notify_teleport"):
			owner_player.camera_rig.call("notify_teleport")

	_cleanup_death_camera_constraint()

	if death_fade_enabled and fader != null and is_instance_valid(fader) and fader.has_method("fade_in"):
		await fader.call("fade_in", death_fade_in_duration)
		if token != _death_sequence_token:
			return

	_finish_death_state(token)


func _finish_death_state(token: int) -> void:
	if token != _death_sequence_token:
		return
	_death_active = false
	_death_grounded = false
	_death_respawn_transition_active = false
	_death_pit_variant = false
	is_active = false
	hurt_type = HurtType.NONE
	state_timer = 0.0
	pushback_dir = Vector3.ZERO
	pushback_speed_locked = 0.0
	_flash_invulnerability_visual = false
	_cleanup_death_camera_constraint()
	if owner_player == null or not is_instance_valid(owner_player):
		return
	if owner_player.has_method("finish_death_sequence"):
		owner_player.call("finish_death_sequence")
	elif owner_player.has_method("set_death_state"):
		owner_player.call("set_death_state", false)
	else:
		owner_player._player_state_locked = false
	_refresh_death_respawn_invulnerability()
	if owner_player.has_method("set_ui_input_blocked"):
		owner_player.call("set_ui_input_blocked", false)
	if owner_player.has_method("clear_active_action"):
		owner_player.call("clear_active_action")


func clear_death_grounded_respawn_hold() -> void:
	_death_grounded = false
	_death_ground_anim_timer = 0.0
	_death_ground_anim_available = true


func _refresh_death_respawn_invulnerability() -> void:
	if owner_player == null or not is_instance_valid(owner_player):
		return
	var respawn_invuln_time: float = max(death_respawn_invuln_time, 0.0)
	invuln_timer = max(invuln_timer, respawn_invuln_time)
	owner_player._damage_hit_invuln_timer = max(owner_player._damage_hit_invuln_timer, respawn_invuln_time)


func _get_death_pushback_direction(source: Node, up: Vector3) -> Vector3:
	var hit_dir: Vector3 = Vector3.ZERO
	if source != null and is_instance_valid(source) and source is Node3D:
		hit_dir = owner_player.global_position - (source as Node3D).global_position
	else:
		hit_dir = -owner_player.global_transform.basis.z
	hit_dir -= up * hit_dir.dot(up)
	if hit_dir.length() < 0.001:
		hit_dir = -owner_player.global_transform.basis.z
		hit_dir -= up * hit_dir.dot(up)
	if hit_dir.length() < 0.001:
		hit_dir = Vector3.FORWARD
	return hit_dir.normalized()


func _play_death_sound() -> void:
	if death_sound == null or owner_player == null:
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = death_sound
	p.bus = "SFX"
	p.autoplay = true
	var parent: Node = owner_player.get_parent()
	if parent == null:
		parent = owner_player
	parent.add_child(p)
	p.top_level = true
	p.global_position = owner_player.global_position
	p.finished.connect(func():
		p.queue_free()
	)


func _start_death_camera_constraint() -> void:
	if not death_camera_constraint_enabled:
		return
	_cleanup_death_camera_constraint()
	_death_camera_rig = _resolve_camera_rig()
	if _death_camera_rig == null or not is_instance_valid(_death_camera_rig):
		return
	if _death_camera_rig.has_method("reset_camera_effects"):
		_death_camera_rig.call("reset_camera_effects", true)
	elif _death_camera_rig.has_method("clear_camera_constraints"):
		_death_camera_rig.call("clear_camera_constraints", null, true)

	var constraint: DeathCameraConstraint = _create_death_camera_constraint(_death_camera_rig)
	if constraint == null:
		return
	_death_camera_constraint = constraint
	_add_constraint_to_scene(constraint)
	if _death_camera_rig.has_method("register_camera_constraint"):
		_death_camera_rig.call("register_camera_constraint", constraint)
	if _death_camera_rig.has_method("begin_distance_lock"):
		var lock_distance: float = _get_rig_camera_distance(_death_camera_rig)
		_death_camera_rig.call("begin_distance_lock", lock_distance, true)


func _cleanup_death_camera_constraint() -> void:
	if _death_camera_rig != null and is_instance_valid(_death_camera_rig):
		if _death_camera_rig.has_method("end_distance_lock"):
			_death_camera_rig.call("end_distance_lock")
		if _death_camera_constraint != null and _death_camera_rig.has_method("unregister_camera_constraint"):
			_death_camera_rig.call("unregister_camera_constraint", _death_camera_constraint)
	if _death_camera_constraint != null and is_instance_valid(_death_camera_constraint):
		_death_camera_constraint.queue_free()
	_death_camera_constraint = null
	_death_camera_rig = null


func _resolve_camera_rig() -> Node:
	if owner_player == null:
		return null
	var r = owner_player.get("camera_rig")
	if r != null:
		return r
	if owner_player.get_tree() == null:
		return null
	var rigs: Array = owner_player.get_tree().get_nodes_in_group("CameraRig")
	if rigs != null and rigs.size() > 0:
		return rigs[0]
	return null


func _get_rig_camera_distance(rig: Node) -> float:
	if rig == null:
		return 0.0
	var cam = rig.get("camera")
	if cam is Camera3D:
		var local_pos: Vector3 = (cam as Camera3D).position
		if abs(local_pos.z) > 0.001:
			return abs(local_pos.z)
	return 0.0


func _get_rig_default_fov(rig: Node) -> float:
	if rig != null and rig.has_method("get_default_fov"):
		var default_fov_value = rig.call("get_default_fov")
		if default_fov_value is float:
			return float(default_fov_value)
	if rig != null:
		var cam = rig.get("camera")
		if cam is Camera3D:
			return (cam as Camera3D).fov
	return 70.0


func _get_death_camera_player_distance(rig: Node) -> float:
	if rig == null or owner_player == null:
		return 0.0
	var reference_position: Vector3 = owner_player.global_position
	var cam = rig.get("camera")
	if cam is Camera3D:
		reference_position = (cam as Camera3D).global_position
	elif rig is Node3D:
		reference_position = (rig as Node3D).global_position
	return reference_position.distance_to(owner_player.global_position)


func _configure_death_camera_fov(constraint: DeathCameraConstraint, rig: Node) -> void:
	if constraint == null or not death_camera_distance_fov_enabled:
		return
	var base_fov: float = _get_rig_default_fov(rig)
	var initial_distance: float = _get_death_camera_player_distance(rig)
	var start_distance: float = max(death_camera_fov_reduction_start_distance, 0.0)
	var full_distance: float = max(death_camera_fov_reduction_full_distance, start_distance + 0.001)
	constraint.lens_trait.mode = CameraLensTrait.Mode.DISTANCE_FOV
	constraint.lens_trait.near_fov = base_fov
	constraint.lens_trait.far_fov = max(base_fov - max(death_camera_fov_max_reduction, 0.0), 1.0)
	constraint.lens_trait.near_distance = initial_distance + start_distance
	constraint.lens_trait.far_distance = initial_distance + full_distance
	constraint.lens_trait.tracking_response = max(death_camera_fov_smoothing, 0.0)


func _create_death_camera_constraint(rig: Node) -> DeathCameraConstraint:
	if rig == null:
		return null
	var pos: Vector3 = (rig as Node3D).global_position if rig is Node3D else owner_player.global_position
	var basis: Basis = Basis.IDENTITY
	var pitch = rig.get("pitch_node")
	if pitch is Node3D:
		basis = (pitch as Node3D).global_transform.basis
	elif rig is Node3D:
		basis = (rig as Node3D).global_transform.basis

	var c: DeathCameraConstraint = DeathCameraConstraint.new()
	c.set_locked_transform(Transform3D(basis, pos))
	c.aim_trait.target_offset = death_camera_aim_offset
	c.aim_trait.tracking_response = max(death_camera_aim_smooth, 0.0)
	c.disable_camera_controls = true
	c.constraint_priority = 9999
	_configure_death_camera_fov(c, rig)
	return c


func _add_constraint_to_scene(constraint: Node) -> void:
	if constraint == null:
		return
	if owner_player != null and owner_player.get_tree() != null and owner_player.get_tree().current_scene != null:
		owner_player.get_tree().current_scene.add_child(constraint)
	else:
		owner_player.add_child(constraint)


func _get_or_create_fader() -> Node:
	if owner_player == null or owner_player.get_tree() == null:
		return null
	var existing: Array = owner_player.get_tree().get_nodes_in_group("ScreenFader")
	if existing != null and existing.size() > 0:
		return existing[0]
	var fader: ScreenFader = ScreenFader.new()
	fader.add_to_group("ScreenFader")
	var vp: Viewport = owner_player.get_viewport()
	if vp != null:
		vp.add_child(fader)
	elif owner_player.get_tree().current_scene != null:
		owner_player.get_tree().current_scene.add_child(fader)
	else:
		owner_player.add_child(fader)
	return fader


func _spew_damage_rings(up: Vector3) -> void:
	if owner_player == null:
		return
	var held_rings: int = int(owner_player.get("rings"))
	if held_rings <= 0:
		return

	var threshold: int = max(ring_spew_high_ring_threshold, 0)
	var lost_rings: int = held_rings
	if held_rings > threshold:
		lost_rings = int(ceil(float(held_rings) * clamp(ring_spew_high_ring_loss_fraction, 0.0, 1.0)))
	if owner_player.has_method("is_active_ring_race") and owner_player.call("is_active_ring_race"):
		lost_rings = 20
	lost_rings = clamp(lost_rings, 0, held_rings)
	if lost_rings <= 0:
		return

	var removed_rings: int = _remove_player_rings(lost_rings)
	if removed_rings <= 0:
		return

	_play_ring_spew_sound()
	var inherited_velocity: Vector3 = owner_player.velocity * max(ring_spew_player_velocity_fraction, 0.0)
	_spawn_dropped_rings(removed_rings, up.normalized(), inherited_velocity)


func _remove_player_rings(amount: int) -> int:
	if owner_player == null:
		return 0
	if owner_player.has_method("remove_rings"):
		return int(owner_player.call("remove_rings", amount))
	var current_rings: int = int(owner_player.get("rings"))
	var removed: int = min(max(amount, 0), current_rings)
	owner_player.set("rings", current_rings - removed)
	return removed


func _spawn_dropped_rings(count: int, up: Vector3, inherited_velocity: Vector3) -> void:
	if ring_spew_scene == null:
		return
	count = min(max(count, 0), MAX_RECOVERABLE_DROPPED_RINGS)
	if up.length() < 0.001:
		up = get_owner_gravity_up()
	var forward: Vector3 = -owner_player.global_transform.basis.z
	forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = owner_player.global_transform.basis.x
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
		forward -= up * forward.dot(up)
	if forward.length() < 0.001:
		forward = Vector3.RIGHT
	forward = forward.normalized()

	var right: Vector3 = up.cross(forward)
	if right.length() < 0.001:
		right = Vector3.RIGHT
		right -= up * right.dot(up)
	if right.length() < 0.001:
		right = Vector3.FORWARD
	right = right.normalized()

	var parent: Node = owner_player.get_parent()
	if parent == null:
		parent = owner_player.get_tree().current_scene
	if parent == null:
		parent = owner_player

	var spawn_center: Vector3 = owner_player.global_position + up * max(ring_spew_spawn_up_offset, 0.0)
	for i in range(count):
		var angle: float = TAU * float(i) / float(max(count, 1))
		var radial_dir: Vector3 = (forward * cos(angle) + right * sin(angle)).normalized()
		var ring: Node = ring_spew_scene.instantiate()
		if ring == null:
			continue
		parent.add_child(ring)
		if ring is Node3D:
			var ring_3d: Node3D = ring as Node3D
			ring_3d.global_position = spawn_center + radial_dir * max(ring_spew_spawn_radial_offset, 0.0)
			var outward_speed: float = randf_range(
				min(ring_spew_outward_speed_min, ring_spew_outward_speed_max),
				max(ring_spew_outward_speed_min, ring_spew_outward_speed_max)
			)
			var upward_speed: float = randf_range(
				min(ring_spew_upward_speed_min, ring_spew_upward_speed_max),
				max(ring_spew_upward_speed_min, ring_spew_upward_speed_max)
			)
			var launch_velocity: Vector3 = radial_dir * outward_speed + up * upward_speed + inherited_velocity
			if ring.has_method("setup_dropped_ring"):
				ring.call("setup_dropped_ring", launch_velocity, up)
			else:
				ring.set("dropped_initial_velocity", launch_velocity)
				ring.set("dropped_up", up)


func _play_ring_spew_sound() -> void:
	if ring_spew_sound == null or owner_player == null:
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.add_to_group(&"LevelTransient")
	p.stream = ring_spew_sound
	p.volume_db = ring_spew_sound_volume_db
	p.pitch_scale = max(ring_spew_sound_pitch_scale + randf_range(-0.04, 0.04), 0.01)
	p.bus = "SFX"
	p.autoplay = true
	var parent: Node = owner_player.get_parent()
	if parent == null:
		parent = owner_player
	parent.add_child(p)
	p.top_level = true
	p.global_position = owner_player.global_position
	p.finished.connect(func():
		p.queue_free()
	)


func update_invuln_visual(delta: float) -> void:
	if invuln_timer <= 0.0 or not _flash_invulnerability_visual or _death_active:
		flash_accum = 0.0
		if not flash_visible:
			flash_visible = true
			_set_flash_visible(true)
		return

	var interval: float = max(hurt_invuln_flash_interval, 0.001)
	flash_accum += delta
	if flash_accum < interval:
		return
	flash_accum = fmod(flash_accum, interval)
	flash_visible = not flash_visible
	_set_flash_visible(flash_visible)


func _set_flash_visible(visible_state: bool) -> void:
	if owner_player != null and owner_player.has_method("_set_hurt_flash_visible"):
		owner_player._set_hurt_flash_visible(visible_state)


func _get_spindash_action():
	if owner_player == null:
		return null
	for a in owner_player._actions:
		if a is SpindashAction:
			return a
	return null


func _get_roll_action():
	if owner_player == null:
		return null
	for a in owner_player._actions:
		if a is RollAction:
			return a
	return null

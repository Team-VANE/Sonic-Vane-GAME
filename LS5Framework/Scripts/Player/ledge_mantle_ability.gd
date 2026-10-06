class_name LedgeMantleAbility
extends CharacterAbility

const MANTLE_EXCLUDED_GROUP: StringName = &"mantle_excluded"

@export_group("Ledge Mantle")

@export_subgroup("Activation")
## Enables automatic ledge catches while the character is airborne.
@export var ledge_mantle_enabled: bool = true
## Air actions from which a ledge catch may begin.
@export var allowed_source_actions: Array[StringName] = [&"fall", &"jump", &"parkour"]
## Minimum movement-input strength required to catch a ledge.
@export_range(0.0, 1.0, 0.01) var minimum_input_strength: float = 0.35
## Minimum alignment between movement input and the direction into the wall.
@export_range(0.0, 1.0, 0.01) var input_toward_wall_dot: float = 0.55
## Upward speed at or above which ledge catches are disabled. Zero removes the limit.
@export var maximum_upward_catch_speed: float = 9.0
## Downward speed at or above which ledge catches are disabled. Zero removes the limit.
@export var maximum_fall_speed: float = 120.0

@export_subgroup("Detection/Wall")
## Gravity-up offset applied to the wall probe origin.
@export var wall_probe_height: float = 0.0
## Maximum radius from the character origin in which a ledge wall can be detected.
@export var ledge_grab_radius: float = 4.0
## Vertical range covered by the wall-probe samples.
@export var wall_probe_vertical_span: float = 1.2
## Number of wall rays distributed across the vertical probe range.
@export_range(1, 7, 1) var wall_probe_samples: int = 3
## Sideways range covered by wall probes to reduce misses at mesh seams.
@export var wall_probe_lateral_spread: float = 0.3
## Number of wall rays distributed across the sideways probe range.
@export_range(1, 5, 1) var wall_probe_lateral_samples: int = 3
## Number of directions sampled across the movement-toward-wall acceptance angle.
@export_range(1, 9, 1) var wall_probe_angle_samples: int = 5
## Maximum deviation from vertical for a wall to qualify.
@export_range(0.0, 45.0, 0.1) var wall_max_tilt_from_vertical_deg: float = 15.0

@export_subgroup("Detection/Ledge")
## Minimum ledge height above the character origin.
@export var minimum_ledge_height: float = 0.1
## Maximum ledge height above the character origin.
@export var maximum_ledge_height: float = 4.0
## Distance behind the wall used for the first upper-surface probe.
@export var top_probe_edge_inset: float = 0.08
## Distance behind the wall used to search for the upper surface.
@export var top_probe_inset: float = 0.7
## Maximum distance behind the wall searched for an upper surface.
@export var top_probe_depth: float = 2.0
## Number of upper-surface rays distributed across the probe depth.
@export_range(1, 9, 1) var top_probe_samples: int = 5
## Sideways distance searched on either side of the wall contact.
@export var top_probe_lateral_spread: float = 0.45
## Maximum upper-surface angle from gravity-up.
@export_range(0.0, 89.0, 0.1) var top_max_surface_angle_deg: float = 35.0
## Collision layers used by mantle probes. Zero uses the character collision mask.
@export_flags_3d_physics var collision_mask_override: int = 0

@export_subgroup("Detection/Clearance")
## Distance outside the wall used for the caught position.
@export var hang_outward_distance: float = 1.05
## Distance below the ledge used for the caught position.
@export var hang_vertical_drop: float = 0.85
## Gravity-up clearance checked above the ledge surface.
@export var landing_clearance_height: float = 1.1
## Distance behind the wall used for the upper clearance check.
@export var landing_clearance_inset: float = 0.75
## Extra separation used by collision-shape clearance checks.
@export var clearance_margin: float = 0.04
## Height above the detected top used to verify that the ledge edge is open.
@export var ledge_opening_probe_height: float = 0.12

@export_subgroup("Movement")
## Time spent holding the ledge before the mantle jump.
@export var catch_hold_duration: float = 0.2
## Horizontal speed applied toward the upper surface during the mantle jump.
@export var mantle_forward_speed: float = 10.0
## Delay before another ledge can be caught after a mantle jump.
@export var regrab_cooldown: float = 0.3
## Time after a ledge jump before wall parkour may catch another surface.
@export var parkour_lock_after_jump: float = 0.75

@export_subgroup("Animation")
## Animation command requested when the character catches a ledge. Empty disables it.
@export var ledge_grab_animation_command: StringName = &""
## Crossfade duration used when entering the ledge-grab animation.
@export_range(0.0, 1.0, 0.01) var ledge_grab_animation_crossfade: float = 0.04
## Keeps the character model facing into the detected wall throughout the ledge hold.
@export var align_visual_to_ledge: bool = true

@export_subgroup("Audio")
## Sound played when the character catches a ledge.
@export var ledge_catch_sound: AudioStream = preload("res://LS5Framework/Sounds/General/Ledge_Catch.wav")
## Sound played when the character jumps from a caught ledge.
@export var ledge_jump_sound: AudioStream = preload("res://LS5Framework/Sounds/General/Ledge_Jump.wav")
## Volume applied to ledge catch and jump sounds.
@export_range(-80.0, 24.0, 0.5) var ledge_sound_volume_db: float = 0.0

@export_subgroup("Debug")
## Prints the current mantle detection rejection while movement is held in the air.
@export var debug_detection: bool = false
## Minimum delay between repeated mantle detection messages.
@export var debug_print_interval: float = 0.25

var _hold_elapsed: float = 0.0
var _regrab_cooldown_timer: float = 0.0
var _parkour_lock_timer: float = 0.0
var _hang_position: Vector3 = Vector3.ZERO
var _mantle_direction: Vector3 = Vector3.ZERO
var _anchor_collider: Node3D = null
var _anchor_local_position: Vector3 = Vector3.ZERO
var _anchor_local_mantle_direction: Vector3 = Vector3.ZERO
var _is_holding_ledge: bool = false
var _debug_print_timer: float = 0.0
var _debug_last_rejection: StringName = &""
var _debug_attempting: bool = false
var _debug_wall_detected: bool = false
var _debug_upper_surface_detected: bool = false
var _debug_catch_position_clear: bool = false
var _debug_mantle_space_clear: bool = false
var _debug_wall_angle_deg: float = 0.0
var _debug_upper_surface_angle_deg: float = 0.0
var _debug_upper_surface_height: float = 0.0
var _debug_input_toward_wall: float = 0.0
var _debug_top_probe_ray_count: int = 0
var _debug_top_probe_hit_count: int = 0
var _debug_top_probe_result: StringName = &""
var _debug_top_probe_starts: Array[Vector3] = []
var _debug_top_probe_ends: Array[Vector3] = []
var _debug_top_probe_hit_positions: Array[Vector3] = []
var _debug_top_probe_hit_flags: Array[bool] = []


func _on_action_initialized() -> void:
	action_id = &"ledge_mantle"
	input_action = &""
	allow_when_inactive = true
	continuous_update = true
	can_pick_up_carryables_while_active = false
	can_execute_while_carrying = false


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func blocks_shared_movement_integration() -> bool:
	return true


func get_input_prompt(_context: Dictionary = {}) -> Dictionary:
	return {}


func can_execute(context: Dictionary = {}) -> bool:
	if not super.can_execute(context):
		return false
	if not _can_attempt_catch():
		return false
	var candidate_value: Variant = context.get("candidate", {})
	if not (candidate_value is Dictionary):
		return false
	var candidate: Dictionary = candidate_value
	if candidate.is_empty() or not bool(candidate.get("valid", false)):
		return false
	return int(candidate.get("physics_frame", -1)) == Engine.get_physics_frames()


func execute(context: Dictionary = {}) -> bool:
	if not can_execute(context):
		return false
	return activate(context)


func continuous_physics_update(delta: float) -> void:
	_regrab_cooldown_timer = max(_regrab_cooldown_timer - max(delta, 0.0), 0.0)
	_parkour_lock_timer = max(_parkour_lock_timer - max(delta, 0.0), 0.0)
	_debug_print_timer = max(_debug_print_timer - max(delta, 0.0), 0.0)
	_debug_attempting = false
	if _is_holding_ledge:
		return
	if not _can_attempt_catch():
		return
	_debug_attempting = true
	var candidate: Dictionary = _find_ledge_candidate()
	if candidate.is_empty():
		return
	execute({"reason": &"ledge_catch", "candidate": candidate})


func on_action_enter(context: Dictionary = {}) -> void:
	var candidate_value: Variant = context.get("candidate", {})
	if not (candidate_value is Dictionary):
		return
	var candidate: Dictionary = candidate_value
	_hold_elapsed = 0.0
	_hang_position = candidate.get("hang_position", Vector3.ZERO)
	_mantle_direction = candidate.get("mantle_direction", Vector3.ZERO)
	_anchor_collider = candidate.get("anchor_collider", null) as Node3D
	_anchor_local_position = candidate.get("anchor_local_position", Vector3.ZERO)
	_anchor_local_mantle_direction = candidate.get("anchor_local_mantle_direction", Vector3.ZERO)
	_is_holding_ledge = true
	owner_player.attached = false
	owner_player.velocity = Vector3.ZERO
	owner_player._jumped_from_ground = false
	owner_player._falling_without_jump = true
	owner_player.global_position = _resolve_hang_position()
	if owner_player.has_method("_gracefully_end_airborne_torque"):
		owner_player.call("_gracefully_end_airborne_torque")
	_align_visual_to_ledge()
	_play_ledge_sound(ledge_catch_sound)
	owner_player._attachment_immunity = max(
		owner_player._attachment_immunity,
		max(catch_hold_duration, 0.0) + 0.05
	)
	if owner_player.has_method("remove_coyote_jump_eligibility"):
		owner_player.remove_coyote_jump_eligibility()
	if ledge_grab_animation_command != &"":
		owner_player._trigger_anim_command(
			ledge_grab_animation_command,
			true,
			max(ledge_grab_animation_crossfade, 0.0)
		)


func blocks_parkour_interaction() -> bool:
	return _is_holding_ledge or _parkour_lock_timer > 0.0


func on_action_exit(_next_action: CharacterAction) -> void:
	_hold_elapsed = 0.0
	_hang_position = Vector3.ZERO
	_mantle_direction = Vector3.ZERO
	_anchor_collider = null
	_anchor_local_position = Vector3.ZERO
	_anchor_local_mantle_direction = Vector3.ZERO
	_is_holding_ledge = false


func physics_update_action(delta: float) -> void:
	if owner_player == null or not _is_holding_ledge:
		return
	owner_player.attached = false
	owner_player.velocity = Vector3.ZERO
	owner_player.global_position = _resolve_hang_position()
	_align_visual_to_ledge()
	_hold_elapsed += max(delta, 0.0)
	if _hold_elapsed < max(catch_hold_duration, 0.0):
		return
	_launch_mantle_jump()


func _can_attempt_catch() -> bool:
	if owner_player == null:
		return false
	if not ledge_mantle_enabled or not enabled:
		return _reject_attempt(&"ability_disabled")
	if _regrab_cooldown_timer > 0.0:
		return _reject_attempt(&"regrab_cooldown")
	if not owner_player.is_inside_tree() or not owner_player._network_is_local_authority():
		return _reject_attempt(&"not_local_authority")
	if owner_player.attached or owner_player._is_dead or owner_player._hurt_active:
		return _reject_attempt(&"grounded_dead_or_hurt")
	if owner_player.race_in_countdown or owner_player._ui_input_blocked:
		return _reject_attempt(&"input_blocked")
	if owner_player.rolling or owner_player._spindash_charging:
		return _reject_attempt(&"rolling_or_spindash")
	if owner_player._rail_active or owner_player._spline_active or owner_player._homing_active:
		return _reject_attempt(&"rail_spline_or_homing")
	if owner_player._lightspeed_dash_active or owner_player._automation_active:
		return _reject_attempt(&"dash_or_automation")
	if owner_player._spring_align_timer > 0.0:
		return _reject_attempt(&"spring_alignment")
	if owner_player._spring_action_lock_timer > 0.0 or owner_player._spring_movement_lock_timer > 0.0:
		return _reject_attempt(&"spring_lock")
	if owner_player._bounce_state != owner_player.BounceState.NONE:
		return _reject_attempt(&"bounce_or_stomp")
	if owner_player._fully_submerged:
		return _reject_attempt(&"fully_submerged")
	if owner_player.is_carrying_object():
		return _reject_attempt(&"carrying_object")
	var source_action: StringName = owner_player.get_current_action_id()
	if source_action == &"parkour" and not owner_player._active_action.allows_ledge_handoff():
		return false
	if source_action == &"":
		source_action = &"fall"
	if not allowed_source_actions.is_empty() and not allowed_source_actions.has(source_action):
		return _reject_attempt(StringName("source_action_%s" % String(source_action)))
	if owner_player._move_input.length() < max(minimum_input_strength, 0.0):
		return false
	var gravity_up: Vector3 = get_owner_gravity_up()
	var vertical_speed: float = owner_player.velocity.dot(gravity_up)
	if maximum_upward_catch_speed > 0.0 and vertical_speed >= maximum_upward_catch_speed:
		return _reject_attempt(&"moving_up_too_fast")
	var downward_speed: float = max(-vertical_speed, 0.0)
	if maximum_fall_speed > 0.0 and downward_speed >= maximum_fall_speed:
		return _reject_attempt(&"falling_too_fast")
	return true


func _find_ledge_candidate() -> Dictionary:
	_debug_wall_detected = false
	_debug_upper_surface_detected = false
	_debug_catch_position_clear = false
	_debug_mantle_space_clear = false
	_debug_wall_angle_deg = 0.0
	_debug_upper_surface_angle_deg = 0.0
	_debug_upper_surface_height = 0.0
	_debug_input_toward_wall = 0.0
	_debug_top_probe_ray_count = 0
	_debug_top_probe_hit_count = 0
	_debug_top_probe_result = &"not_tested"
	_debug_top_probe_starts.clear()
	_debug_top_probe_ends.clear()
	_debug_top_probe_hit_positions.clear()
	_debug_top_probe_hit_flags.clear()
	var world: World3D = owner_player.get_world_3d()
	if world == null:
		return _reject_candidate(&"world_unavailable")
	var gravity_up: Vector3 = get_owner_gravity_up()
	var input_direction: Vector3 = _get_input_direction(gravity_up)
	if input_direction.length() < 0.001:
		return _reject_candidate(&"input_direction_invalid")
	var query_mask: int = _get_query_collision_mask()
	if query_mask == 0:
		return _reject_candidate(&"collision_mask_empty")

	var wall_hit: Dictionary = _find_wall_hit(
		world,
		gravity_up,
		input_direction,
		query_mask
	)
	if wall_hit.is_empty():
		return _reject_candidate(&"wall_not_found")
	_debug_wall_detected = true
	var wall_end: Vector3 = owner_player.global_position + input_direction * max(ledge_grab_radius, 0.0)
	var wall_normal: Vector3 = wall_hit.get("normal", Vector3.ZERO)
	if wall_normal.length() < 0.001:
		return _reject_candidate(&"wall_normal_invalid")
	wall_normal = wall_normal.normalized()
	if wall_normal.dot(input_direction) > 0.0:
		wall_normal = -wall_normal
	var wall_angle_deg: float = rad_to_deg(acos(clamp(wall_normal.dot(gravity_up), -1.0, 1.0)))
	_debug_wall_angle_deg = wall_angle_deg
	if abs(wall_angle_deg - 90.0) > max(wall_max_tilt_from_vertical_deg, 0.0):
		return _reject_candidate(&"wall_angle_rejected")

	var wall_outward: Vector3 = wall_normal - gravity_up * wall_normal.dot(gravity_up)
	if wall_outward.length() < 0.001:
		return _reject_candidate(&"wall_direction_invalid")
	wall_outward = wall_outward.normalized()
	var mantle_direction: Vector3 = -wall_outward
	_debug_input_toward_wall = input_direction.dot(mantle_direction)
	if _debug_input_toward_wall < clamp(input_toward_wall_dot, 0.0, 1.0):
		return _reject_candidate(&"input_not_toward_wall")

	var wall_collider: Object = wall_hit.get("collider", null)
	if _collider_blocks_mantle(wall_collider):
		return _reject_candidate(&"wall_collider_excluded")
	var wall_position: Vector3 = wall_hit.get("position", wall_end)
	var ledge_min_height: float = max(minimum_ledge_height, 0.0)
	var ledge_max_height: float = max(maximum_ledge_height, ledge_min_height)
	var top_hit: Dictionary = _find_upper_surface_hit(
		world,
		wall_position,
		mantle_direction,
		gravity_up,
		ledge_min_height,
		ledge_max_height,
		query_mask
	)
	if top_hit.is_empty():
		return _reject_candidate(&"upper_surface_not_found")
	var top_collider: Object = top_hit.get("collider", null)
	if _collider_blocks_mantle(top_collider):
		return _reject_candidate(&"upper_surface_collider_excluded")
	_debug_upper_surface_detected = true
	var top_to: Vector3 = owner_player.global_position + gravity_up * ledge_min_height
	var top_position: Vector3 = top_hit.get("position", top_to)
	var top_normal: Vector3 = top_hit.get("normal", Vector3.ZERO)
	if top_normal.length() < 0.001:
		return _reject_candidate(&"upper_surface_normal_invalid")
	top_normal = top_normal.normalized()
	var top_angle_deg: float = rad_to_deg(acos(clamp(top_normal.dot(gravity_up), -1.0, 1.0)))
	_debug_upper_surface_angle_deg = top_angle_deg
	if top_angle_deg > clamp(top_max_surface_angle_deg, 0.0, 89.0):
		return _reject_candidate(&"upper_surface_too_steep")
	var top_height: float = (top_position - owner_player.global_position).dot(gravity_up)
	_debug_upper_surface_height = top_height
	if top_height < ledge_min_height or top_height > ledge_max_height + 0.1:
		return _reject_candidate(&"upper_surface_height_rejected")
	var top_inset_from_wall: float = (top_position - wall_position).dot(mantle_direction)
	if top_inset_from_wall < -0.05:
		return _reject_candidate(&"upper_surface_behind_wall")
	var ledge_edge_position: Vector3 = (
		top_position
		- mantle_direction * max(top_inset_from_wall, 0.0)
	)

	var resolved_hang_outward_distance: float = _get_hang_outward_distance(wall_outward)
	var hang_position: Vector3 = (
		ledge_edge_position
		+ wall_outward * resolved_hang_outward_distance
		- gravity_up * max(hang_vertical_drop, 0.0)
	)
	var landing_position: Vector3 = (
		ledge_edge_position
		+ mantle_direction * max(landing_clearance_inset, 0.0)
		+ gravity_up * max(landing_clearance_height, 0.0)
	)
	if not _ledge_opening_is_clear(
		world,
		ledge_edge_position,
		top_position,
		wall_outward,
		gravity_up,
		resolved_hang_outward_distance,
		query_mask
	):
		return _reject_candidate(&"ledge_opening_obscured")
	_debug_catch_position_clear = _character_shape_is_clear(world, hang_position, query_mask)
	if not _debug_catch_position_clear:
		return _reject_candidate(&"catch_position_blocked")
	if not _character_shape_path_is_clear(
		world,
		owner_player.global_position,
		hang_position,
		query_mask
	):
		return _reject_candidate(&"catch_path_blocked")
	_debug_mantle_space_clear = _character_shape_is_clear(world, landing_position, query_mask)
	if not _debug_mantle_space_clear:
		return _reject_candidate(&"mantle_space_blocked")
	var raised_hang_position: Vector3 = (
		ledge_edge_position
		+ wall_outward * resolved_hang_outward_distance
		+ gravity_up * max(landing_clearance_height, 0.0)
	)
	if not _character_shape_is_clear(world, raised_hang_position, query_mask):
		return _reject_candidate(&"mantle_rise_space_blocked")
	if (
		not _character_shape_path_is_clear(world, hang_position, raised_hang_position, query_mask)
		or not _character_shape_path_is_clear(world, raised_hang_position, landing_position, query_mask)
	):
		return _reject_candidate(&"mantle_path_blocked")

	var anchor_collider: Node3D = wall_collider as Node3D
	var anchor_local_position: Vector3 = hang_position
	var anchor_local_mantle_direction: Vector3 = mantle_direction
	if anchor_collider != null:
		anchor_local_position = anchor_collider.global_transform.affine_inverse() * hang_position
		anchor_local_mantle_direction = anchor_collider.global_transform.basis.inverse() * mantle_direction
	_debug_last_rejection = &""
	_debug_print_timer = 0.0
	return {
		"valid": true,
		"physics_frame": Engine.get_physics_frames(),
		"hang_position": hang_position,
		"mantle_direction": mantle_direction,
		"anchor_collider": anchor_collider,
		"anchor_local_position": anchor_local_position,
		"anchor_local_mantle_direction": anchor_local_mantle_direction,
	}


func _get_input_direction(gravity_up: Vector3) -> Vector3:
	var direction: Vector3 = (
		owner_player._control_forward * owner_player._move_input.y
		+ owner_player._control_right * owner_player._move_input.x
	)
	direction -= gravity_up * direction.dot(gravity_up)
	if direction.length() < 0.001:
		return Vector3.ZERO
	return direction.normalized()


func _get_query_collision_mask() -> int:
	if collision_mask_override != 0:
		return collision_mask_override
	return owner_player.collision_mask


func _collider_blocks_mantle(collider: Object) -> bool:
	var collision_object: CollisionObject3D = collider as CollisionObject3D
	if collision_object != null and owner_player != null:
		var excluded_layers: int = (
			owner_player.non_alignable_surface_mask
			| owner_player.attack_pass_through_surface_mask
		)
		if (collision_object.collision_layer & excluded_layers) != 0:
			return true
	var collider_node: Node = collider as Node
	while collider_node != null:
		if collider_node.is_in_group(MANTLE_EXCLUDED_GROUP):
			return true
		collider_node = collider_node.get_parent()
	return false


func _find_wall_hit(
	world: World3D,
	gravity_up: Vector3,
	input_direction: Vector3,
	query_mask: int
) -> Dictionary:
	var vertical_sample_count: int = max(wall_probe_samples, 1)
	var lateral_sample_count: int = max(wall_probe_lateral_samples, 1)
	var angle_sample_count: int = max(wall_probe_angle_samples, 1)
	var vertical_span: float = max(wall_probe_vertical_span, 0.0)
	var lateral_span: float = max(wall_probe_lateral_spread, 0.0) * 2.0
	var radial_reach: float = max(ledge_grab_radius, 0.0)
	var required_alignment: float = clamp(input_toward_wall_dot, 0.0, 1.0)
	var maximum_probe_angle: float = acos(required_alignment)
	var best_hit: Dictionary = {}
	var best_score: float = -INF
	for angle_index: int in range(angle_sample_count):
		var angle_ratio: float = 0.5
		if angle_sample_count > 1:
			angle_ratio = float(angle_index) / float(angle_sample_count - 1)
		var probe_angle: float = lerp(-maximum_probe_angle, maximum_probe_angle, angle_ratio)
		var probe_direction: Vector3 = input_direction.rotated(gravity_up, probe_angle).normalized()
		var wall_tangent: Vector3 = gravity_up.cross(probe_direction)
		if wall_tangent.length() >= 0.001:
			wall_tangent = wall_tangent.normalized()
		else:
			wall_tangent = Vector3.ZERO
		for vertical_index: int in range(vertical_sample_count):
			var sample_ratio: float = 0.5
			if vertical_sample_count > 1:
				sample_ratio = float(vertical_index) / float(vertical_sample_count - 1)
			var height_offset: float = wall_probe_height + lerp(
				-vertical_span * 0.5,
				vertical_span * 0.5,
				sample_ratio
			)
			for lateral_index: int in range(lateral_sample_count):
				var lateral_ratio: float = 0.5
				if lateral_sample_count > 1:
					lateral_ratio = float(lateral_index) / float(lateral_sample_count - 1)
				var lateral_offset: float = lerp(-lateral_span * 0.5, lateral_span * 0.5, lateral_ratio)
				var ray_origin: Vector3 = (
					owner_player.global_position
					+ gravity_up * height_offset
					+ wall_tangent * lateral_offset
				)
				var ray_end: Vector3 = ray_origin + probe_direction * radial_reach
				var hit: Dictionary = _raycast(world, ray_origin, ray_end, query_mask)
				if hit.is_empty():
					continue
				var normal: Vector3 = hit.get("normal", Vector3.ZERO)
				if normal.length() < 0.001:
					continue
				normal = normal.normalized()
				if normal.dot(probe_direction) > 0.0:
					normal = -normal
				var angle_deg: float = rad_to_deg(acos(clamp(normal.dot(gravity_up), -1.0, 1.0)))
				if abs(angle_deg - 90.0) > max(wall_max_tilt_from_vertical_deg, 0.0):
					continue
				var wall_outward: Vector3 = normal - gravity_up * normal.dot(gravity_up)
				if wall_outward.length() < 0.001:
					continue
				var direction_into_wall: Vector3 = -wall_outward.normalized()
				var input_alignment: float = input_direction.dot(direction_into_wall)
				if input_alignment < required_alignment:
					continue
				var hit_position: Vector3 = hit.get("position", ray_end)
				var radial_distance: float = owner_player.global_position.distance_to(hit_position)
				if radial_distance > radial_reach + 0.01:
					continue
				hit["normal"] = normal
				var score: float = (
					-radial_distance
					+ input_alignment * 0.25
					- abs(probe_angle) * 0.02
					- abs(height_offset - wall_probe_height) * 0.02
					- abs(lateral_offset) * 0.02
				)
				if score > best_score:
					best_score = score
					best_hit = hit
	return best_hit


func _find_upper_surface_hit(
	world: World3D,
	wall_position: Vector3,
	mantle_direction: Vector3,
	gravity_up: Vector3,
	ledge_min_height: float,
	ledge_max_height: float,
	query_mask: int
) -> Dictionary:
	var depth_sample_count: int = max(top_probe_samples, 1)
	var edge_inset: float = max(top_probe_edge_inset, 0.01)
	var start_inset: float = max(top_probe_inset, 0.05)
	var end_inset: float = max(top_probe_depth, start_inset)
	var wall_height_offset: float = (wall_position - owner_player.global_position).dot(gravity_up)
	var wall_height_base: Vector3 = wall_position - gravity_up * wall_height_offset
	var wall_tangent: Vector3 = gravity_up.cross(mantle_direction)
	if wall_tangent.length() >= 0.001:
		wall_tangent = wall_tangent.normalized()
	else:
		wall_tangent = Vector3.ZERO
	var lateral_spread: float = max(top_probe_lateral_spread, 0.0)
	var lateral_offsets: Array[float] = [0.0]
	if lateral_spread > 0.001 and wall_tangent.length() >= 0.001:
		lateral_offsets.append(-lateral_spread)
		lateral_offsets.append(lateral_spread)
	var probe_insets: Array[float] = [edge_inset]
	_debug_top_probe_result = &"no_collision"
	for sample_index: int in range(depth_sample_count):
		var sample_ratio: float = 0.0
		if depth_sample_count > 1:
			sample_ratio = float(sample_index) / float(depth_sample_count - 1)
		var inset: float = lerp(start_inset, end_inset, sample_ratio)
		if abs(inset - edge_inset) > 0.001 and not probe_insets.has(inset):
			probe_insets.append(inset)
	for inset: float in probe_insets:
		for lateral_offset: float in lateral_offsets:
			var probe_base: Vector3 = (
				wall_height_base
				+ mantle_direction * inset
				+ wall_tangent * lateral_offset
			)
			var ray_from: Vector3 = probe_base + gravity_up * (ledge_max_height + 0.15)
			var ray_to: Vector3 = probe_base + gravity_up * ledge_min_height
			_debug_top_probe_ray_count += 1
			_debug_top_probe_starts.append(ray_from)
			_debug_top_probe_ends.append(ray_to)
			var hit: Dictionary = _raycast(world, ray_from, ray_to, query_mask)
			if hit.is_empty():
				_debug_top_probe_hit_positions.append(ray_to)
				_debug_top_probe_hit_flags.append(false)
				continue
			_debug_top_probe_hit_count += 1
			var top_position: Vector3 = hit.get("position", ray_to)
			_debug_top_probe_hit_positions.append(top_position)
			_debug_top_probe_hit_flags.append(true)
			var top_normal: Vector3 = hit.get("normal", Vector3.ZERO)
			if top_normal.length() < 0.001:
				_debug_top_probe_result = &"normal_invalid"
				continue
			top_normal = top_normal.normalized()
			if top_normal.dot(gravity_up) < 0.0:
				top_normal = -top_normal
			var top_angle_deg: float = rad_to_deg(acos(clamp(top_normal.dot(gravity_up), -1.0, 1.0)))
			if top_angle_deg > clamp(top_max_surface_angle_deg, 0.0, 89.0):
				_debug_top_probe_result = &"surface_too_steep"
				continue
			var top_height: float = (top_position - owner_player.global_position).dot(gravity_up)
			if top_height < ledge_min_height:
				_debug_top_probe_result = &"surface_too_low"
				continue
			if top_height > ledge_max_height + 0.1:
				_debug_top_probe_result = &"surface_too_high"
				continue
			if (top_position - wall_position).dot(mantle_direction) < -0.05:
				_debug_top_probe_result = &"surface_outside_wall"
				continue
			_debug_top_probe_result = &"accepted"
			hit["normal"] = top_normal
			return hit
	return {}


func _raycast(
	world: World3D,
	from_position: Vector3,
	to_position: Vector3,
	query_mask: int
) -> Dictionary:
	if from_position.distance_squared_to(to_position) < 0.000001:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_position,
		to_position,
		query_mask,
		_get_query_excludes()
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_back_faces = true
	return world.direct_space_state.intersect_ray(query)


func _ledge_opening_is_clear(
	world: World3D,
	ledge_edge_position: Vector3,
	top_position: Vector3,
	wall_outward: Vector3,
	gravity_up: Vector3,
	hang_distance: float,
	query_mask: int
) -> bool:
	var probe_height: float = max(
		ledge_opening_probe_height,
		max(clearance_margin, 0.0) + 0.02
	)
	var ray_from: Vector3 = (
		ledge_edge_position
		+ wall_outward * max(hang_distance, 0.0)
		+ gravity_up * probe_height
	)
	var ray_to: Vector3 = top_position + gravity_up * probe_height
	return _raycast(world, ray_from, ray_to, query_mask).is_empty()


func _get_query_excludes() -> Array[RID]:
	var excludes: Array[RID] = []
	if owner_player != null and is_instance_valid(owner_player):
		excludes.append(owner_player.get_rid())
	return excludes


func _get_hang_outward_distance(wall_outward: Vector3) -> float:
	var configured_distance: float = max(hang_outward_distance, 0.0)
	if owner_player == null or wall_outward.length() < 0.001:
		return configured_distance
	var collision_shape: CollisionShape3D = owner_player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.disabled or collision_shape.shape == null:
		return configured_distance
	var outward: Vector3 = wall_outward.normalized()
	var shape_basis: Basis = collision_shape.global_transform.basis
	var local_direction: Vector3 = shape_basis.transposed() * outward
	var shape: Shape3D = collision_shape.shape
	var support_distance: float = 0.0
	if shape is SphereShape3D:
		var sphere: SphereShape3D = shape as SphereShape3D
		support_distance = sphere.radius * local_direction.length()
	elif shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		var capsule_segment_half_length: float = max(capsule.height * 0.5 - capsule.radius, 0.0)
		support_distance = (
			capsule.radius * local_direction.length()
			+ capsule_segment_half_length * abs(local_direction.y)
		)
	elif shape is CylinderShape3D:
		var cylinder: CylinderShape3D = shape as CylinderShape3D
		var cylinder_radial_direction: Vector2 = Vector2(local_direction.x, local_direction.z)
		support_distance = (
			cylinder.radius * cylinder_radial_direction.length()
			+ cylinder.height * 0.5 * abs(local_direction.y)
		)
	elif shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		var half_size: Vector3 = box.size * 0.5
		support_distance = (
			abs(local_direction.x) * half_size.x
			+ abs(local_direction.y) * half_size.y
			+ abs(local_direction.z) * half_size.z
		)
	elif shape is ConvexPolygonShape3D:
		var convex: ConvexPolygonShape3D = shape as ConvexPolygonShape3D
		for point: Vector3 in convex.points:
			support_distance = max(support_distance, (shape_basis * point).dot(outward))
	if support_distance <= 0.0:
		return configured_distance
	var shape_center_offset: Vector3 = collision_shape.global_position - owner_player.global_position
	var required_distance: float = (
		support_distance
		- shape_center_offset.dot(outward)
		+ max(clearance_margin, 0.0)
		+ 0.02
	)
	return max(configured_distance, required_distance)


func _character_shape_is_clear(
	world: World3D,
	candidate_position: Vector3,
	query_mask: int
) -> bool:
	var collision_shape: CollisionShape3D = owner_player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.disabled or collision_shape.shape == null:
		return false
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	var shape_transform: Transform3D = collision_shape.global_transform
	shape_transform.origin += candidate_position - owner_player.global_position
	query.transform = shape_transform
	query.margin = max(clearance_margin, 0.0)
	query.collision_mask = query_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_query_excludes()
	var overlaps: Array[Dictionary] = world.direct_space_state.intersect_shape(query, 1)
	return overlaps.is_empty()


func _character_shape_path_is_clear(
	world: World3D,
	from_position: Vector3,
	to_position: Vector3,
	query_mask: int
) -> bool:
	var motion: Vector3 = to_position - from_position
	if motion.length_squared() < 0.000001:
		return true
	var collision_shape: CollisionShape3D = owner_player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.disabled or collision_shape.shape == null:
		return false
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	var shape_transform: Transform3D = collision_shape.global_transform
	shape_transform.origin += from_position - owner_player.global_position
	query.transform = shape_transform
	query.motion = motion
	query.margin = max(clearance_margin, 0.0)
	query.collision_mask = query_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_query_excludes()
	var cast_result: PackedFloat32Array = world.direct_space_state.cast_motion(query)
	return cast_result.is_empty() or cast_result[0] >= 0.999


func _resolve_hang_position() -> Vector3:
	if _anchor_collider != null and is_instance_valid(_anchor_collider):
		return _anchor_collider.global_transform * _anchor_local_position
	return _hang_position


func _resolve_mantle_direction() -> Vector3:
	if (
		_anchor_collider != null
		and is_instance_valid(_anchor_collider)
		and _anchor_local_mantle_direction.length() >= 0.001
	):
		return _anchor_collider.global_transform.basis * _anchor_local_mantle_direction
	return _mantle_direction


func _align_visual_to_ledge() -> void:
	if not align_visual_to_ledge or owner_player == null:
		return
	if not owner_player.has_method("snap_model_to_normal"):
		return
	var gravity_up: Vector3 = get_owner_gravity_up()
	var forward: Vector3 = _resolve_mantle_direction()
	forward -= gravity_up * forward.dot(gravity_up)
	if forward.length() < 0.001:
		return
	owner_player.call("snap_model_to_normal", gravity_up, forward.normalized())


func _launch_mantle_jump() -> void:
	var gravity_up: Vector3 = get_owner_gravity_up()
	var mantle_direction: Vector3 = _resolve_mantle_direction()
	var forward: Vector3 = mantle_direction - gravity_up * mantle_direction.dot(gravity_up)
	if forward.length() < 0.001:
		forward = -owner_player.global_transform.basis.z
		forward -= gravity_up * forward.dot(gravity_up)
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	owner_player.velocity = (
		gravity_up * max(float(owner_player.jump_speed), 0.0)
		+ forward * max(mantle_forward_speed, 0.0)
	)
	owner_player.attached = false
	owner_player._attachment_immunity = max(
		owner_player._attachment_immunity,
		owner_player.launch_immunity_time
	)
	owner_player._airborne_time = 0.0
	owner_player._clear_coyote_jump_window()
	owner_player._is_skidding = false
	owner_player._jumped_from_ground = true
	owner_player._falling_without_jump = false
	owner_player._jump_dash_used_this_air = false
	owner_player._tornado_kick_used_this_air = false
	owner_player._just_jumped = true
	owner_player._begin_jump_hold_state(false)
	_regrab_cooldown_timer = max(regrab_cooldown, 0.0)
	_parkour_lock_timer = max(parkour_lock_after_jump, 0.0)
	var jump_action_activated: bool = owner_player._activate_jump_action_for_launch(&"ledge_mantle")
	if not jump_action_activated:
		owner_player.activate_neutral_air_action({"reason": &"ledge_mantle"})
	if owner_player.has_method("register_combo_feat"):
		owner_player.register_combo_feat(&"ledge_mantle", "Ledge Mantle", 225.0, 1.0)
	_play_ledge_sound(ledge_jump_sound)
	owner_player._trigger_anim_command(&"CMD_JUMP")


func _reject_candidate(reason: StringName) -> Dictionary:
	_report_detection_rejection(reason)
	return {}


func debug_draw_ledge_mantle_probes(gravity_up: Vector3) -> void:
	if not _debug_attempting:
		return
	var ray_count: int = min(_debug_top_probe_starts.size(), _debug_top_probe_ends.size())
	ray_count = min(
		ray_count,
		min(_debug_top_probe_hit_positions.size(), _debug_top_probe_hit_flags.size())
	)
	for index: int in range(ray_count):
		var ray_from: Vector3 = _debug_top_probe_starts[index]
		var ray_to: Vector3 = _debug_top_probe_ends[index]
		var did_hit: bool = _debug_top_probe_hit_flags[index]
		var ray_color: Color = Color(0.95, 0.2, 0.12, 1.0)
		if did_hit:
			ray_color = Color(0.15, 0.8, 1.0, 1.0)
		DebugDraw3d.line(ray_from, ray_to, ray_color)
		if did_hit:
			var hit_position: Vector3 = _debug_top_probe_hit_positions[index]
			DebugDraw3d.arrow(
				hit_position,
				hit_position + gravity_up * 0.35,
				Color(0.3, 1.0, 0.45, 1.0)
			)


func get_ledge_mantle_debug_snapshot() -> Dictionary:
	var vertical_speed: float = 0.0
	var input_strength: float = 0.0
	if owner_player != null:
		vertical_speed = owner_player.velocity.dot(get_owner_gravity_up())
		input_strength = owner_player._move_input.length()
	return {
		"available": owner_player != null,
		"enabled": enabled and ledge_mantle_enabled,
		"attempting": _debug_attempting,
		"active": _is_holding_ledge,
		"rejection": _debug_last_rejection,
		"wall_detected": _debug_wall_detected,
		"wall_angle_deg": _debug_wall_angle_deg,
		"input_strength": input_strength,
		"minimum_input_strength": minimum_input_strength,
		"input_toward_wall": _debug_input_toward_wall,
		"upper_surface_detected": _debug_upper_surface_detected,
		"upper_surface_angle_deg": _debug_upper_surface_angle_deg,
		"upper_surface_height": _debug_upper_surface_height,
		"top_probe_rays": _debug_top_probe_ray_count,
		"top_probe_hits": _debug_top_probe_hit_count,
		"top_probe_result": _debug_top_probe_result,
		"catch_position_clear": _debug_catch_position_clear,
		"mantle_space_clear": _debug_mantle_space_clear,
		"vertical_speed": vertical_speed,
		"fall_speed_limit": maximum_fall_speed,
		"hold_elapsed": _hold_elapsed,
		"hold_duration": catch_hold_duration,
		"regrab_cooldown": _regrab_cooldown_timer,
	}


func _reject_attempt(reason: StringName) -> bool:
	if (
		owner_player != null
		and not owner_player.attached
		and owner_player._move_input.length() >= max(minimum_input_strength, 0.0)
	):
		_report_detection_rejection(reason)
	return false


func _report_detection_rejection(reason: StringName) -> void:
	if owner_player == null:
		return
	var repeated_reason: bool = reason == _debug_last_rejection
	_debug_last_rejection = reason
	if not debug_detection:
		return
	if repeated_reason and _debug_print_timer > 0.0:
		return
	_debug_print_timer = max(debug_print_interval, 0.0)
	print("[LedgeMantle:%s] %s" % [owner_player.name, String(reason)])


func _play_ledge_sound(sound: AudioStream) -> void:
	if sound == null or owner_player == null:
		return
	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.add_to_group(&"LevelTransient")
	player.stream = sound
	player.volume_db = ledge_sound_volume_db
	player.bus = &"SFX"
	player.autoplay = true
	var parent: Node = owner_player.get_parent()
	if parent == null:
		parent = owner_player
	parent.add_child(player)
	player.top_level = true
	player.global_position = owner_player.global_position
	player.finished.connect(func() -> void:
		player.queue_free()
	)

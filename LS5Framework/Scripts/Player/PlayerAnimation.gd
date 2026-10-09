extends RefCounted
class_name PlayerAnimation

# SUMMARY:
# - Animation helpers for PlayerController, isolated from gameplay logic.
# - Reads player state (velocity, flags, model orientation) and writes AnimationTree params.
# - BRIDGE: PlayerModel updates visual_up and model_root orientation; this module reads them
#   for blend calculations and model-relative momentum.

const SM_BASE: String = "parameters/StateMachine"
const SM_GROUND: String = SM_BASE + "/GROUND_MACHINE"
const JUMP_FALL_BLEND_CONDITION: String = "conditions/UseFallBlendForJump"
const NOT_JUMP_FALL_BLEND_CONDITION: String = "conditions/NotUseFallBlendForJump"
const RAIL_SWITCH_ANIM_DURATION: float = 0.5

var _owner: Node = null
var _anim_param_cache: Dictionary = {}
var _anim_param_types: Dictionary = {}
var _anim_value_cache: Dictionary = {}
var _anim_playback_cache: Dictionary = {}
var _cached_tree: AnimationTree = null
var _cached_root: AnimationRootNode = null
var _anim_properties_cached: bool = false
var _movement_time_name_cache: Dictionary = {}
var _anim_turn_raw: float = 0.0
var _anim_turn_smooth: float = 0.0
var _anim_turn_prev_lateral_dir: Vector3 = Vector3.ZERO  # Used to measure signed turn rate.
var _fall_blend_smoothed: Vector2 = Vector2.ZERO
var _fall_blend_initialized: bool = false
var _movement_time_exclusion_pattern: RegEx = RegEx.new()
var _network_tree_id: int = 0
var _network_playback_paths: Array[String] = []
var _network_value_paths: Array[String] = []
var _network_puppet_tree_id: int = 0
var _network_oneshot_states: Dictionary = {}
var _network_authority_tree_root: AnimationRootNode = null


func _init(owner: Node) -> void:
	_owner = owner
	_movement_time_exclusion_pattern.compile("(?i)_movement-time-scale\\s*=\\s*(false|0|no|off)(?=$|[\\s;_])")


func dispose() -> void:
	if is_instance_valid(_cached_tree) and _cached_tree.property_list_changed.is_connected(_invalidate_animation_cache):
		_cached_tree.property_list_changed.disconnect(_invalidate_animation_cache)
	if _cached_root and _cached_root.changed.is_connected(_invalidate_animation_cache):
		_cached_root.changed.disconnect(_invalidate_animation_cache)
	_cached_tree = null
	_cached_root = null
	_owner = null
	_invalidate_animation_cache()
	_movement_time_name_cache.clear()


func _invalidate_animation_cache() -> void:
	_anim_param_cache.clear()
	_anim_param_types.clear()
	_anim_value_cache.clear()
	_anim_playback_cache.clear()
	_anim_properties_cached = false
	_network_tree_id = 0


func _sync_animation_cache(tree: AnimationTree) -> void:
	if tree == _cached_tree and tree.tree_root == _cached_root:
		return
	if is_instance_valid(_cached_tree) and _cached_tree.property_list_changed.is_connected(_invalidate_animation_cache):
		_cached_tree.property_list_changed.disconnect(_invalidate_animation_cache)
	if _cached_root and _cached_root.changed.is_connected(_invalidate_animation_cache):
		_cached_root.changed.disconnect(_invalidate_animation_cache)
	_cached_tree = tree
	_cached_root = tree.tree_root
	tree.property_list_changed.connect(_invalidate_animation_cache)
	if _cached_root:
		_cached_root.changed.connect(_invalidate_animation_cache)
	_invalidate_animation_cache()
	_refresh_owner_playbacks(tree)


func _node_excludes_movement_time(node: AnimationNode) -> bool:
	var label: String = node.resource_name
	if not _movement_time_name_cache.has(label):
		_movement_time_name_cache[label] = _movement_time_exclusion_pattern.search(label) != null
	return _movement_time_name_cache[label]


func capture_network_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	var tree: AnimationTree = _owner.anim_tree
	if tree == null:
		return snapshot
	_refresh_network_paths(tree)
	var states: Dictionary = {}
	var values: Array = []
	for path: String in _network_playback_paths:
		var playback: AnimationNodeStateMachinePlayback = tree.get(path) as AnimationNodeStateMachinePlayback
		if playback != null:
			states[path] = playback.get_current_node()
	for path: String in _network_value_paths:
		values.append(tree.get(path))
	snapshot["states"] = states
	snapshot["values"] = values
	return snapshot


func apply_network_snapshot(states: Dictionary, values: Array) -> void:
	var tree: AnimationTree = _owner.anim_tree
	if tree == null:
		return
	_prepare_network_puppet_tree(tree)
	_sync_animation_cache(tree)
	_anim_value_cache.clear()
	_refresh_network_paths(tree)
	for index: int in mini(values.size(), _network_value_paths.size()):
		var path: String = _network_value_paths[index]
		if path.ends_with("/active"):
			var active: bool = bool(values[index])
			if bool(_network_oneshot_states.get(path, false)) != active:
				var request_path: String = path.get_base_dir() + "/request"
				tree.set(request_path, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE if active else AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			_network_oneshot_states[path] = active
		elif tree.get(path) != values[index]:
			tree.set(path, values[index])
	var paths: Array[String] = []
	for path: String in states:
		paths.append(path)
	paths.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length())
	for path: String in paths:
		if not _anim_param_exists(path):
			continue
		var state_path: String = path.get_base_dir()
		var parent_path: String = state_path.get_base_dir() + "/playback"
		if states.has(parent_path) and StringName(states[parent_path]) != StringName(state_path.get_file()):
			continue
		var state: StringName = StringName(states[path])
		if state == &"":
			continue
		var playback: AnimationNodeStateMachinePlayback = tree.get(path) as AnimationNodeStateMachinePlayback
		if playback != null and playback.get_current_node() != state:
			playback.start(state)


func _prepare_network_puppet_tree(tree: AnimationTree) -> void:
	if _network_puppet_tree_id == tree.get_instance_id():
		return
	_network_puppet_tree_id = tree.get_instance_id()
	if tree.tree_root:
		_network_authority_tree_root = tree.tree_root
		tree.tree_root = tree.tree_root.duplicate(true) as AnimationRootNode
		_disable_network_auto_transitions(tree.tree_root)
	_invalidate_animation_cache()
	_network_tree_id = 0
	_refresh_owner_playbacks(tree)


func restore_authority_tree() -> void:
	var tree: AnimationTree = _owner.anim_tree
	if tree and _network_authority_tree_root:
		tree.tree_root = _network_authority_tree_root
	_network_authority_tree_root = null
	_network_puppet_tree_id = 0
	_network_tree_id = 0
	_network_oneshot_states.clear()
	_invalidate_animation_cache()
	if tree:
		_refresh_owner_playbacks(tree)


func _refresh_owner_playbacks(tree: AnimationTree) -> void:
	_owner.anim_state = tree.get(SM_BASE + "/playback") as AnimationNodeStateMachinePlayback
	_owner.ground_state = tree.get(SM_GROUND + "/playback") as AnimationNodeStateMachinePlayback


func _disable_network_auto_transitions(node: AnimationNode) -> void:
	if node is AnimationNodeStateMachine:
		var machine: AnimationNodeStateMachine = node as AnimationNodeStateMachine
		for index: int in machine.get_transition_count():
			machine.get_transition(index).advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		for name: StringName in machine.get_node_list():
			_disable_network_auto_transitions(machine.get_node(name))
	elif node is AnimationNodeBlendTree:
		var blend_tree: AnimationNodeBlendTree = node as AnimationNodeBlendTree
		for name: StringName in blend_tree.get_node_list():
			_disable_network_auto_transitions(blend_tree.get_node(name))
	elif node is AnimationNodeBlendSpace1D or node is AnimationNodeBlendSpace2D:
		for index: int in node.get_blend_point_count():
			_disable_network_auto_transitions(node.get_blend_point_node(index))


func _refresh_network_paths(tree: AnimationTree) -> void:
	_sync_animation_cache(tree)
	var tree_id: int = tree.get_instance_id()
	if _network_tree_id == tree_id:
		return
	_network_tree_id = tree_id
	_network_playback_paths.clear()
	_network_value_paths.clear()
	for property: Dictionary in tree.get_property_list():
		var path: String = String(property.get("name", ""))
		if not path.begins_with("parameters/"):
			continue
		if path.ends_with("/playback"):
			_network_playback_paths.append(path)
		elif path.contains("/conditions/") or path.ends_with("/blend_position") or path.ends_with("/blend_amount") or path.ends_with("/scale") or path.ends_with("/active"):
			_network_value_paths.append(path)
	_network_value_paths.sort()


func _get_owner_gravity_up() -> Vector3:
	if _owner != null and is_instance_valid(_owner) and _owner.has_method("get_gravity_up"):
		var gravity_up_value = _owner.call("get_gravity_up")
		if gravity_up_value is Vector3:
			var gravity_up: Vector3 = (gravity_up_value as Vector3).normalized()
			if gravity_up.length() >= 0.001:
				return gravity_up
	return Vector3.UP


func _update_animation(delta: float) -> void:
	var p = _owner
	if p == null or not is_instance_valid(p):
		_fall_blend_smoothed = Vector2.ZERO
		_fall_blend_initialized = false
		return
	
	var anim_tree: AnimationTree = p.anim_tree
	if anim_tree:
		_sync_animation_cache(anim_tree)
	var anim_state: AnimationNodeStateMachinePlayback = p.anim_state
	if anim_tree == null or anim_state == null:
		return
	if p._is_dead:
		_set_anim_bool_param("conditions/Grounded", p.attached)
		_set_anim_bool_param("conditions/Airborne", not p.attached)
		_set_anim_bool_param("conditions/Moving", false)
		_set_anim_bool_param("conditions/Falling", false)
		_set_anim_bool_param("conditions/Landing", false)
		_set_anim_bool_param("conditions/LandMoving", false)
		_safe_set_anim_param("MoveTimeScale/scale", _get_animation_movement_time_scale())
		return

	var rail_playback: AnimationNodeStateMachinePlayback = _get_rail_state_playback(anim_tree)
	if p._rail_switch_active:
		p._pending_anim_command = &""
		p._pending_anim_crossfade = -1.0
		if not p._rail_switch_animation_started:
			var rail_switch_state: StringName = &"SWITCH_LEFT" if p._rail_switch_animation_side < 0.0 else &"SWITCH_RIGHT"
			anim_state.start(&"RAIL")
			if rail_playback != null:
				rail_playback.start(rail_switch_state)
			p._rail_switch_animation_started = true

	# Optimize: Capture state flags once for all checks this frame.
	var flags: int = p.state_flags

	# Force-enter the rail animation state when transitions miss.
	var spindash_rail_active: bool = (flags & p.STATE_SPINDASHRAIL) != 0 or (p._rail_active and p._spindash_charging)
	if (p._rail_active or p._rail_switch_active) and not spindash_rail_active and anim_state.get_current_node() != "RAIL":
		anim_state.travel("RAIL")
	
	# Force-enter GROUND_MACHINE if grounded and not in any other override state.
	var grounded: bool = p.attached
	var landing_entry_pending: bool = grounded and p._landing_animation_pending
	var st_spring: bool = (flags & (p.STATE_SPRING | p.STATE_SPLINE)) != 0
	var st_hard_land: bool = p.is_ground_hit_hard()
	var st_jump: bool = (flags & p.STATE_JUMPING) != 0
	var st_fall: bool = (flags & p.STATE_FALLING) != 0 or p._current_action_id == &"fall"
	var st_roll: bool = (flags & p.STATE_ROLL) != 0
	var st_spindash: bool = (flags & p.STATE_SPINDASH) != 0
	var st_drift: bool = (flags & p.STATE_DRIFT) != 0
	var st_skydive: bool = (flags & p.STATE_SKYDIVE) != 0
	var st_landing_animation_override: bool = p.has_action_landing_animation_override()
	var st_carry_anim: bool = p.has_method("is_carry_animation_locked") and bool(p.call("is_carry_animation_locked"))
	var fall_blend_jump_active: bool = (
		not grounded
		and st_jump
		and (flags & p.STATE_JUMP_FALL_BLEND) != 0
	)
	
	var in_override_state: bool = p._rail_active or p._rail_switch_active or st_spring or st_hard_land or st_jump or st_fall or st_roll or st_spindash or st_drift or st_skydive or st_landing_animation_override or st_carry_anim
	var landing_node: StringName = anim_state.get_current_node()
	var landing_animation_active: bool = (
		landing_node == &"To_Any_Grounded_State"
		or landing_node == &"LAND"
		or landing_node == &"LAND_MOVING"
		or landing_node == &"GAME_Land_Hard"
	)
	if not grounded or st_landing_animation_override or (
		landing_node == &"LAND" or landing_node == &"LAND_MOVING" or landing_node == &"GAME_Land_Hard" or landing_node == &"GROUND_MACHINE"
	):
		p._landing_animation_pending = false
		
	if grounded and not in_override_state and not landing_entry_pending and not landing_animation_active:
		if anim_state.get_current_node() != "GROUND_MACHINE":
			anim_state.travel("GROUND_MACHINE")

	# Step 1: Basic kinematics used by animations.
	var up: Vector3 = p._physics_up_last.normalized()
	if up.length() < 0.001:
		up = _get_owner_gravity_up()

	var animation_speed_scale: float = _get_speed_based_animation_scale()
	var animation_velocity: Vector3 = p.velocity * animation_speed_scale
	p._horizontal_speed = p._get_lateral_speed_for_anim()
	p._vertical_speed = p.velocity.dot(up)
	var speed: float = p._horizontal_speed * animation_speed_scale
	var vertical_speed: float = animation_velocity.dot(up)

	# Model-root-relative momentum for fall/landing blends.
	var mb: Basis = p.global_transform.basis
	if p.model_root != null:
		mb = p.model_root.global_transform.basis
	mb = mb.orthonormalized()
	var v_model: Vector3 = mb.transposed() * p.velocity
	p._model_vertical_momentum = v_model.y
	p._model_horizontal_momentum = Vector2(v_model.x, v_model.z).length()
	var configured_min: Vector2 = p.anim_fall_blend_min_position
	var configured_max: Vector2 = p.anim_fall_blend_max_position
	var fall_blend_min: Vector2 = Vector2(
		min(configured_min.x, configured_max.x),
		min(configured_min.y, configured_max.y)
	)
	var fall_blend_max: Vector2 = Vector2(
		max(configured_min.x, configured_max.x),
		max(configured_min.y, configured_max.y)
	)
	var fall_blend_target: Vector2 = Vector2(
		clamp(p._model_horizontal_momentum * animation_speed_scale, fall_blend_min.x, fall_blend_max.x),
		clamp(p._model_vertical_momentum * animation_speed_scale, fall_blend_min.y, fall_blend_max.y)
	)
	if not _fall_blend_initialized:
		_fall_blend_smoothed = fall_blend_target
		_fall_blend_initialized = true
	else:
		var fall_blend_speed: float = max(p.anim_fall_blend_smooth_speed, 0.0)
		if fall_blend_speed <= 0.0 or delta <= 0.0:
			_fall_blend_smoothed = fall_blend_target
		else:
			var s: float = 1.0 - exp(-fall_blend_speed * delta)
			_fall_blend_smoothed = _fall_blend_smoothed.lerp(fall_blend_target, s)

	var land_moving: bool = landing_entry_pending and p.should_play_moving_landing_animation()

	# Step 2: Animation conditions.
	var current_action_id: StringName = p._current_action_id
	
	_set_anim_bool_param("conditions/Grounded", grounded)
	_set_anim_bool_param("conditions/Airborne", not grounded)
	_set_anim_bool_param("conditions/Moving", (flags & p.STATE_MOVING) != 0)
	_set_anim_bool_param("conditions/Skidding", (flags & p.STATE_SKIDDING) != 0)
	
	# Action-based conditions
	_set_anim_bool_param("conditions/Drifting", st_drift)
	_set_anim_bool_param("conditions/NotDrifting", not st_drift)
	_set_anim_bool_param("conditions/DriftLeft", st_drift and p._get_drift_anim_direction() < 0)
	_set_anim_bool_param("conditions/DriftRight", st_drift and p._get_drift_anim_direction() > 0)
	_update_skydive_animation_latch(delta)
	_set_anim_bool_param("conditions/Skydiving", st_skydive)
	_set_anim_bool_param("conditions/SkydiveDiving", p._is_skydive_anim_diving())
	_set_anim_bool_param("conditions/SkydiveGliding", p._is_skydive_anim_gliding())
	_set_anim_bool_param("conditions/Rolling", (flags & p.STATE_ROLL) != 0)
	_set_anim_bool_param("conditions/Spindashing", (flags & p.STATE_SPINDASH) != 0)
	_set_anim_bool_param("conditions/NotSpindashing", not (flags & p.STATE_SPINDASH) != 0)
	_set_anim_bool_param("conditions/Jumping", (flags & p.STATE_JUMPING) != 0)
	var use_fall_blend_for_jump: bool = (
		fall_blend_jump_active
		or (not grounded and st_jump and vertical_speed < -max(p.fall_vertical_speed_threshold, 0.0))
	)
	_set_anim_bool_param(JUMP_FALL_BLEND_CONDITION, use_fall_blend_for_jump)
	_set_anim_bool_param(NOT_JUMP_FALL_BLEND_CONDITION, not use_fall_blend_for_jump)
	_set_anim_bool_param("conditions/Spring", (flags & (p.STATE_SPRING | p.STATE_SPLINE)) != 0)
	_set_anim_bool_param("conditions/HardLanding", st_hard_land)
	_safe_set_anim_param(SM_BASE + "/GAME_Land_Hard/blend_position", p.get_ground_hit_strength())
	
	var fall_threshold: float = max(p.fall_vertical_speed_threshold, 0.0)
	st_fall = (flags & p.STATE_FALLING) != 0 or current_action_id == &"fall"
	if not st_fall and not grounded and vertical_speed < -fall_threshold:
		var bounce_blocked: bool = (p._bounce_state == p.BounceState.BOUNCE)
		if not bounce_blocked:
			st_fall = true
	
	_set_anim_bool_param("conditions/Falling", st_fall)
	_set_anim_bool_param("conditions/Looping", (flags & p.STATE_LOOPING) != 0)
	_set_anim_bool_param("conditions/Landing", landing_entry_pending)
	_set_anim_bool_param("conditions/LandMoving", land_moving)
	_set_anim_bool_param("conditions/JumpDashing", (flags & p.STATE_JUMP_DASH) != 0)
	
	var st_spindash_airborne: bool = not grounded and (p._spindash_charging or p._spindash_pending_release)
	_set_anim_bool_param("conditions/SpindashAirborne", st_spindash_airborne)

	# Step 3: Blend positions and time scaling.
	_update_turn_amount(delta)
	var turn_amount: float = _anim_turn_smooth

	_safe_set_anim_param(SM_GROUND + "/GroundMove/blend_position", Vector2(speed, turn_amount))
	_safe_set_anim_param(SM_BASE + "/FallBlend/blend_position", _fall_blend_smoothed)

	var rail_speed_max: float = max(p.anim_speed_blend_max, 0.01)
	var rail_animation_speed: float = p._rail_speed * animation_speed_scale
	var rail_speed_target: float = clamp(abs(rail_animation_speed), 0.0, rail_speed_max)
	if p._rail_active and not p._rail_crouching:
		rail_speed_target = 0.0
	
	var rail_blend_speed: float = max(p.rail_anim_blend_smooth_speed, 0.0)
	if not p._rail_active:
		p._rail_anim_speed_smoothed = 0.0
	elif rail_blend_speed <= 0.0:
		p._rail_anim_speed_smoothed = rail_speed_target
	else:
		p._rail_anim_speed_smoothed = move_toward(p._rail_anim_speed_smoothed, rail_speed_target, rail_blend_speed * delta)
	
	var rail_dir_target: float = 0.0
	if p._rail_active:
		var dir_den : float = max(p.rail_anim_dir_speed_for_full, 0.001)
		rail_dir_target = clamp(rail_animation_speed / dir_den, -1.0, 1.0)
	
	var rail_dir_smooth_speed: float = max(p.rail_anim_dir_smooth_speed, 0.0)
	if rail_dir_smooth_speed <= 0.0:
		p._rail_anim_dir_smoothed = rail_dir_target
	else:
		var t_dir : float = clamp(rail_dir_smooth_speed * delta, 0.0, 1.0)
		p._rail_anim_dir_smoothed = lerp(p._rail_anim_dir_smoothed, rail_dir_target, t_dir)
	
	var rail_blend_position: Vector2 = Vector2(p._rail_anim_speed_smoothed, p._rail_anim_dir_smoothed)
	_safe_set_anim_param(SM_BASE + "/RAIL/GRIND/blend_position", rail_blend_position)
	_safe_set_anim_param(SM_BASE + "/RAIL/blend_position", rail_blend_position)

	var current_state: StringName = anim_state.get_current_node()
	var move_time_scale: float = 1.0
	var rail_sub_state: StringName = &""
	if rail_playback != null:
		rail_sub_state = rail_playback.get_current_node()
	var rail_switch_anim_playing: bool = (
		p._rail_switch_active
		or (
			current_state == &"RAIL"
			and (rail_sub_state == &"SWITCH_LEFT" or rail_sub_state == &"SWITCH_RIGHT")
		)
	)

	var in_ground_move: bool = false
	if current_state == "GROUND_MACHINE" and p.ground_state != null:
		var sub_state = p.ground_state.get_current_node()
		if sub_state == "GroundMove" or String(sub_state).begins_with("GAME_Move"):
			in_ground_move = true

	if rail_switch_anim_playing:
		var switch_duration: float = max(p.rail_switch_max_duration, 0.001)
		move_time_scale = RAIL_SWITCH_ANIM_DURATION / switch_duration
	elif st_roll and not p._spindash_charging:
		var spd_roll: float = animation_velocity.length()
		var denom_roll: float = max(p.roll_anim_speed_for_max, 0.001)
		var t_roll: float = clamp(spd_roll / denom_roll, 0.0, 1.0)
		move_time_scale = lerp(p.roll_anim_min_scale, p.roll_anim_max_scale, t_roll)
	elif current_state == "RAIL" or current_state == "SPINDASHRAIL":
		if rail_sub_state == &"" or rail_sub_state == &"GRIND":
			var spd_rail: float = abs(rail_animation_speed)
			var denom_rail: float = max(p.rail_anim_speed_for_max, 0.001)
			var t_rail: float = clamp(spd_rail / denom_rail, 0.0, 1.0)
			move_time_scale = lerp(p.rail_anim_min_scale, p.rail_anim_max_scale, t_rail)
	elif st_drift:
		var steer_amount: float = p._get_drift_anim_steer_amount()
		var steer_scale: float = max(p.drift_anim_neutral_speed_scale, 0.0)
		if steer_amount < 0.0:
			steer_scale = lerp(
				max(p.drift_anim_neutral_speed_scale, 0.0),
				max(p.drift_anim_outward_speed_scale, 0.0),
				abs(steer_amount)
			)
		elif steer_amount > 0.0:
			steer_scale = lerp(
				max(p.drift_anim_neutral_speed_scale, 0.0),
				max(p.drift_anim_inward_speed_scale, 0.0),
				steer_amount
			)
		var drift_speed_denom: float = max(p.drift_anim_movement_speed_for_max, 0.001)
		var drift_speed_t: float = clamp(speed / drift_speed_denom, 0.0, 1.0)
		var movement_scale: float = lerp(
			max(p.drift_anim_movement_min_scale, 0.0),
			max(p.drift_anim_movement_max_scale, 0.0),
			drift_speed_t
		)
		move_time_scale = steer_scale * movement_scale
	elif in_ground_move:
		var speed_norm: float = 0.0
		var ground_anim_speed_for_max: float = p.run_top_speed
		if p.has_method("_get_ground_anim_speed_for_max"):
			ground_anim_speed_for_max = float(p.call("_get_ground_anim_speed_for_max"))
		if ground_anim_speed_for_max > 0.0:
			speed_norm = clamp(speed / ground_anim_speed_for_max, 0.0, 1.0)
		if p.anim_movespeed_scale_curve:
			move_time_scale = p.anim_movespeed_scale_curve.sample(speed)
		else:
			move_time_scale = lerp(p.anim_movespeed_min_scale, p.anim_movespeed_max_scale, speed_norm)

	var action_animation_scale: float = 1.0
	if p._active_action != null and is_instance_valid(p._active_action):
		action_animation_scale = max(p._active_action.get_animation_speed_multiplier(), 0.0)
	_safe_set_anim_param(
		"MoveTimeScale/scale",
		move_time_scale * action_animation_scale * _get_animation_movement_time_scale()
	)


func _get_speed_based_animation_scale() -> float:
	# Stored velocity uses movement-clock units.
	return 1.0 if _owner.anim_speed_logic_compensation_enabled else _owner.get_movement_time_scale()


func _get_animation_movement_time_scale() -> float:
	var p = _owner
	var movement_scale: float = p.get_movement_time_scale()
	if movement_scale == 1.0 or p.is_movement_time_scale_debuff_active():
		return movement_scale
	var tree: AnimationTree = p.anim_tree
	if tree and tree.tree_root:
		var root: AnimationNode = tree.tree_root
		if _node_excludes_movement_time(root):
			return 1.0
		# MoveTimeScale controls the main state machine, excluding independent overlays.
		if root is AnimationNodeBlendTree:
			var blend_tree: AnimationNodeBlendTree = root as AnimationNodeBlendTree
			if blend_tree.has_node(&"StateMachine"):
				root = blend_tree.get_node(&"StateMachine")
				if _is_movement_time_excluded(root, SM_BASE, tree):
					return 1.0
		elif _is_movement_time_excluded(root, "parameters", tree):
			return 1.0
	return movement_scale


func _is_movement_time_excluded(node: AnimationNode, parameter_path: String, tree: AnimationTree) -> bool:
	if not node:
		return false
	if _node_excludes_movement_time(node):
		return true
	if node is AnimationNodeStateMachine:
		var machine: AnimationNodeStateMachine = node as AnimationNodeStateMachine
		var playback: AnimationNodeStateMachinePlayback = tree.get(parameter_path + "/playback") as AnimationNodeStateMachinePlayback
		if not playback:
			return false
		var state: StringName = playback.get_current_node()
		if state != &"" and machine.has_node(state):
			return _is_movement_time_excluded(machine.get_node(state), parameter_path + "/" + String(state), tree)
	elif node is AnimationNodeBlendTree:
		var blend_tree: AnimationNodeBlendTree = node as AnimationNodeBlendTree
		for child_name: StringName in blend_tree.get_node_list():
			if _is_movement_time_excluded(blend_tree.get_node(child_name), parameter_path + "/" + String(child_name), tree):
				return true
	elif node is AnimationNodeBlendSpace1D:
		var blend_space: AnimationNodeBlendSpace1D = node as AnimationNodeBlendSpace1D
		for point_index: int in range(blend_space.get_blend_point_count()):
			if _is_movement_time_excluded(blend_space.get_blend_point_node(point_index), parameter_path, tree):
				return true
	elif node is AnimationNodeBlendSpace2D:
		var blend_space: AnimationNodeBlendSpace2D = node as AnimationNodeBlendSpace2D
		for point_index: int in range(blend_space.get_blend_point_count()):
			if _is_movement_time_excluded(blend_space.get_blend_point_node(point_index), parameter_path, tree):
				return true
	return false


func _get_rail_state_playback(anim_tree: AnimationTree) -> AnimationNodeStateMachinePlayback:
	var rail_playback_path: String = SM_BASE + "/RAIL/playback"
	if not _anim_param_exists(rail_playback_path):
		return null
	if not _anim_playback_cache.has(rail_playback_path):
		_anim_playback_cache[rail_playback_path] = anim_tree.get(rail_playback_path)
	return _anim_playback_cache[rail_playback_path] as AnimationNodeStateMachinePlayback


func _update_skydive_animation_latch(delta: float) -> void:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p._skydive_anim_exit_timer > 0.0:
		p._skydive_anim_exit_timer = max(p._skydive_anim_exit_timer - max(delta, 0.0), 0.0)
		var in_skydive_machine: bool = p.anim_state != null and p.anim_state.get_current_node() == &"SKYDIVE_MACHINE"
		if p._current_action_id != &"skydive" and not in_skydive_machine:
			p._skydive_anim_phase = p.SKYDIVE_ANIM_NONE
			p._skydive_anim_exit_timer = 0.0
		elif p._skydive_anim_exit_timer <= 0.0 and p._current_action_id != &"skydive":
			p._skydive_anim_phase = p.SKYDIVE_ANIM_NONE


func _safe_set_anim_param(path: String, value) -> void:
	# Commands remain write-through; persistent parameters use change detection.
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	var anim_tree: AnimationTree = p.anim_tree
	if anim_tree == null:
		return

	var full_path: String = path
	if not full_path.begins_with("parameters/"):
		full_path = "parameters/" + full_path

	if not _anim_param_exists(full_path):
		return

	var is_command: bool = full_path.ends_with("/request")
	if not is_command and _anim_value_cache.has(full_path) and typeof(_anim_value_cache[full_path]) == typeof(value) and _anim_value_cache[full_path] == value:
		if full_path != String(p.carry_hold_blend_parameter):
			return

	var current_type: int = int(_anim_param_types.get(full_path, TYPE_NIL))
	var new_type: int = typeof(value)
	var numeric_types: bool = (current_type == TYPE_INT or current_type == TYPE_FLOAT) and (new_type == TYPE_INT or new_type == TYPE_FLOAT)
	if current_type != TYPE_NIL and current_type != new_type and not numeric_types:
		return

	anim_tree.set(full_path, value)
	if not is_command:
		_anim_value_cache[full_path] = value


func _anim_values_compatible(current_value: Variant, new_value: Variant) -> bool:
	var current_type: int = typeof(current_value)
	var new_type: int = typeof(new_value)
	if current_type == TYPE_NIL:
		return true
	if current_type == new_type:
		return true
	var current_is_number: bool = current_type == TYPE_INT or current_type == TYPE_FLOAT
	var new_is_number: bool = new_type == TYPE_INT or new_type == TYPE_FLOAT
	return current_is_number and new_is_number


func _update_locomotion_anim(delta: float) -> void:
	# SUMMARY: Optional locomotion blend based on turn and speed.
	# STEPS:
	# - Step 1: Compute raw and smoothed turn values.
	# - Step 2: Derive lateral speed and normalized speed param.
	# - Step 3: Write blend positions and basic conditions.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	var anim_tree: AnimationTree = p.anim_tree
	var anim_state: AnimationNodeStateMachinePlayback = p.anim_state
	if anim_tree == null or anim_state == null:
		return

	_update_turn_amount(delta)

	var up: Vector3 = p._physics_up_last.normalized()
	if up.length() < 0.001:
		up = _get_owner_gravity_up()

	var v: Vector3 = p.velocity * _get_speed_based_animation_scale()
	var vertical: float = v.dot(up)
	var lateral: Vector3 = v - up * vertical
	var lateral_speed: float = lateral.length()

	anim_tree.set(SM_GROUND + "/GroundMove/blend_position", Vector2(lateral_speed, _anim_turn_smooth))

	var grounded: bool = p.attached
	_set_anim_bool_param("conditions/Grounded", grounded)
	_set_anim_bool_param("conditions/Moving", lateral_speed > 0.5)

func _update_turn_amount(delta: float) -> void:
	# SUMMARY: Compute a signed turn lean target from turn rate, then smooth toward it.
	# NOTES:
	# - Uses physics up (loop-safe) to define the lateral plane and sign direction.
	# - Turn rate is measured from the change in lateral direction (deg/sec).
	# - Max lean is driven by turn rate, not smoothing strength.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		_anim_turn_raw = 0.0
		_anim_turn_smooth = 0.0
		_anim_turn_prev_lateral_dir = Vector3.ZERO
		return

	var up: Vector3 = p._physics_up_last.normalized()
	if up.length() < 0.001:
		up = _get_owner_gravity_up()

	var v: Vector3 = p.velocity * _get_speed_based_animation_scale()
	var vertical: float = v.dot(up)
	var lateral: Vector3 = v - up * vertical
	var lateral_speed: float = lateral.length()

	var target: float = 0.0
	var turn_rate_deg_per_sec: float = 0.0
	var min_speed: float = max(p.anim_turn_min_speed, 0.001)
	if lateral_speed >= min_speed and delta > 0.0:
		var lateral_dir: Vector3 = lateral / lateral_speed

		if _anim_turn_prev_lateral_dir.length() > 0.001:
			var dot_dir: float = clamp(_anim_turn_prev_lateral_dir.dot(lateral_dir), -1.0, 1.0)
			var angle_rad: float = acos(dot_dir)
			if angle_rad > 0.00001:
				var axis: Vector3 = _anim_turn_prev_lateral_dir.cross(lateral_dir)
				var axis_len: float = axis.length()
				if axis_len > 0.0001:
					axis /= axis_len
					var sign_dir: float = 1.0
					if axis.dot(up) < 0.0:
						sign_dir = -1.0
					turn_rate_deg_per_sec = (rad_to_deg(angle_rad) / delta) * sign_dir

		_anim_turn_prev_lateral_dir = lateral_dir
	else:
		_anim_turn_prev_lateral_dir = Vector3.ZERO

	# Turn rate maps directly to max lean; speed is handled by the X axis blend.
	var rate_full: float = max(p.anim_turn_max_angle_deg, 0.001)
	var rate_ratio: float = clamp(abs(turn_rate_deg_per_sec) / rate_full, 0.0, 1.0)
	target = rate_ratio
	if turn_rate_deg_per_sec < 0.0:
		target = -target

	_anim_turn_raw = target

	var smooth_speed: float = max(p.anim_turn_smooth_factor, 0.0)
	if smooth_speed <= 0.0 or delta <= 0.0:
		_anim_turn_smooth = _anim_turn_raw
	else:
		# Frame-rate independent smoothing (exponential response).
		var s: float = 1.0 - exp(-smooth_speed * delta)
		_anim_turn_smooth = lerp(_anim_turn_smooth, _anim_turn_raw, s)


func _get_turn_amount_for_anim() -> float:
	# SUMMARY: Return the latest smoothed turn amount for animation blending.
	# NOTE: _update_turn_amount() should be called each frame before use.
	return _anim_turn_smooth


func _set_anim_bool_param(rel_path: String, value: bool) -> void:
	# SUMMARY: Set a boolean parameter in the AnimationTree with change detection.
	var p = _owner
	if p == null or not is_instance_valid(p):
		return
	
	var full_path: String = rel_path
	if not full_path.begins_with("parameters/"):
		full_path = SM_BASE + "/" + rel_path

	_safe_set_anim_param(full_path, value)


func set_next_foot_right() -> void:
	# SUMMARY: Mark the next walk stop as right-footed.
	# STEPS:
	# - Step 1: Set the internal flag.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	p._last_walk_foot_left = true


func set_next_foot_left() -> void:
	# SUMMARY: Mark the next walk stop as left-footed.
	# STEPS:
	# - Step 1: Set the internal flag.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	p._last_walk_foot_left = false


func request_walk_stop() -> void:
	# SUMMARY: Briefly arm a walk stop window for the animation graph.
	# STEPS:
	# - Step 1: Set the pending flag.
	# - Step 2: Clear it after a short delay.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	p._pending_walk_stop = true
	await p.get_tree().create_timer(0.05).timeout
	p._pending_walk_stop = false


func _debug_anim_tree_params() -> void:
	# SUMMARY: Print common animation parameter paths for quick verification.
	# STEPS:
	# - Step 1: Validate animation references.
	# - Step 2: Print a short list of expected parameters.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	var anim_tree: AnimationTree = p.anim_tree
	var anim_state: AnimationNodeStateMachinePlayback = p.anim_state

	print("\n=== ANIM TREE DEBUG ===")

	if anim_tree == null:
		print("anim_tree is NULL")
		return
	else:
		print("anim_tree OK, active =", anim_tree.active)

	if anim_state == null:
		print("anim_state (%s/playback) is NULL" % SM_BASE)
	else:
		print("anim_state OK, current state =", anim_state.get_current_node())

	var paths: Array[String] = [
		"%s/conditions/Grounded" % SM_BASE,
		"%s/conditions/Moving" % SM_BASE,
		"%s/conditions/Landing" % SM_BASE,
		"%s/conditions/HardLanding" % SM_BASE,
		"%s/conditions/JumpDashing" % SM_BASE,
	]

	for pth in paths:
		var exists: bool = _anim_param_exists(pth)
		print("param '%s' exists? %s" % [pth, exists])

	print("=== END ANIM TREE DEBUG ===\n")


func _anim_param_exists(prop_path: String) -> bool:
	# Index all parameters once per tree structure.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return false
	var anim_tree: AnimationTree = p.anim_tree
	if anim_tree == null:
		return false

	_sync_animation_cache(anim_tree)
	if not _anim_properties_cached:
		for entry: Dictionary in anim_tree.get_property_list():
			var name: String = String(entry.get("name", ""))
			_anim_param_cache[name] = true
			_anim_param_types[name] = int(entry.get("type", TYPE_NIL))
		_anim_properties_cached = true
	return _anim_param_cache.has(prop_path)


func _dump_animtree_params() -> void:
	# SUMMARY: Print all AnimationTree parameters for debugging.
	# STEPS:
	# - Step 1: Iterate through parameters.
	# - Step 2: Print each value.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	var anim_tree: AnimationTree = p.anim_tree
	if anim_tree == null:
		return
	print("\n=== ANIMTREE PARAMS ===")
	for entry in anim_tree.get_property_list():
		var n: String = String(entry.name)
		if n.begins_with("parameters"):
			print(n, " = ", anim_tree.get(n))
	print("=== END PARAMS ===\n")

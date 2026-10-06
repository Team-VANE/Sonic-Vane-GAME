extends RefCounted
class_name PlayerEffectsController

const BARRIER_FOOT_TRAIL_CONTROLLER_SCRIPT: Script = preload(
	"res://LS5Framework/Scripts/Effects/BarrierBlastFootTrailController.gd"
)
const JUMP_BALL_RESOURCE_ARGUMENT: String = "_jump-ball-enabled"

# Barrier Blast state and player-specific runtime visual effects.
var _owner: Node = null
var _barrier_foot_trail_controller: BarrierBlastFootTrailController = null


func _init(owner: Node) -> void:
	_owner = owner


func _ensure_barrier_foot_trail_controller() -> void:
	var p = _owner
	if p == null or not is_instance_valid(p) or not p.barrier_foot_trails_enabled:
		return
	if _barrier_foot_trail_controller != null and is_instance_valid(_barrier_foot_trail_controller):
		return
	_barrier_foot_trail_controller = (
		BARRIER_FOOT_TRAIL_CONTROLLER_SCRIPT.new() as BarrierBlastFootTrailController
	)
	if _barrier_foot_trail_controller == null:
		return
	p.add_child(_barrier_foot_trail_controller)
	_barrier_foot_trail_controller.setup(p)


func is_barrier_blast_active() -> bool:
	var p = _owner
	return p._barrier_blast_active


func _cancel_barrier_blast() -> void:
	var p = _owner
	p._barrier_blast_active = false
	p._barrier_blast_gauge = 0.0
	p._barrier_blast_was_full = false
	p._barrier_blast_deplete_grace_timer = 0.0
	p._barrier_blast_full_land_exit_grace_timer = 0.0
	_stop_barrier_blast_wind_sfx()
	if _barrier_foot_trail_controller != null and is_instance_valid(_barrier_foot_trail_controller):
		_barrier_foot_trail_controller.clear_trails()
	p._set_special_gauge_ui(0.0)


func reset_for_level_change() -> void:
	var p = _owner
	_cancel_barrier_blast()
	p._sonic_boom_active = false
	p._sonic_boom_was_full = false
	p._sonic_boom_timer = 0.0
	p._sonic_boom_visible = 0.0
	p._sonic_boom_dir = Vector3.FORWARD
	p._net_target_barrier_blast_gauge = 0.0
	_set_sonic_boom_visibility(0.0, 1.0)
	if p.jump_dash_trail != null and p.jump_dash_trail.has_method("stop_and_clear"):
		p.jump_dash_trail.call("stop_and_clear")


func _update_barrier_blast(delta: float, world_up: Vector3, is_attached_for_movement: bool) -> void:
	var p = _owner
	_ensure_barrier_foot_trail_controller()
	if not p.barrier_blast_enabled:
		if p._barrier_blast_active or p._barrier_blast_gauge > 0.0:
			_cancel_barrier_blast()
		else:
			p._barrier_blast_was_full = false
			p._barrier_blast_deplete_grace_timer = 0.0
			p._barrier_blast_full_land_exit_grace_timer = 0.0
			_stop_barrier_blast_wind_sfx()
		return

	# Count down the "full gauge landing" exit grace timer every frame to avoid
	# cross-state bleed (for example, landing on a ramp then immediately leaving it).
	if p._barrier_blast_full_land_exit_grace_timer > 0.0:
		p._barrier_blast_full_land_exit_grace_timer = max(p._barrier_blast_full_land_exit_grace_timer - delta, 0.0)

	var speed: float = p.velocity.length()
	var pause_deplete: bool = p.barrier_blast_pause_deplete_while_spindash and p._spindash_charging
	var action_allows_building: bool = false
	if p._active_action != null and p._active_action.pauses_barrier_blast_depletion():
		pause_deplete = true
		p._barrier_blast_deplete_grace_timer = max(p.barrier_blast_deplete_grace_time, 0.0)
	if p._active_action != null:
		action_allows_building = p._active_action.allows_barrier_blast_building()
	var full_land_exit_grace_active: bool = false
	if is_attached_for_movement and p._barrier_blast_gauge >= 1.0:
		full_land_exit_grace_active = p._barrier_blast_full_land_exit_grace_timer > 0.0

	if p._barrier_blast_active:
		# Only allow exit-speed logic while attached for movement.
		# In air, speed can briefly dip near the apex of a jump, which can
		# cause a full -> not-full -> full flicker on the next landing.
		var allow_exit_speed_check: bool = is_attached_for_movement
		# Do not force the gauge below full immediately after a full-gauge landing.
		# This prevents a full -> not-full -> full flicker on ramp landings where
		# vertical impact speed is high but tangential speed is briefly low.
		if allow_exit_speed_check and not pause_deplete and not full_land_exit_grace_active and p.barrier_blast_exit_speed > 0.0 and speed <= p.barrier_blast_exit_speed:
			p._barrier_blast_active = false
			# Avoid immediately re-triggering if the gauge is still full this frame.
			if p._barrier_blast_gauge >= 1.0:
				p._barrier_blast_gauge = 0.999
		# While active, keep updating the UI from the actual gauge value so depletion is visible.
		p._set_special_gauge_ui(p._barrier_blast_gauge)
		# Continue into drain logic below so speed-based depletion can happen.

	# Rapidly drain the gauge while below the minimum speed threshold (with grace time).
	var can_build: bool = is_attached_for_movement or action_allows_building
	if is_attached_for_movement and p.barrier_blast_fill_min_speed > 0.0:
		if pause_deplete:
			p._barrier_blast_deplete_grace_timer = max(p.barrier_blast_deplete_grace_time, 0.0)
		elif speed >= p.barrier_blast_fill_min_speed or p._barrier_blast_gauge <= 0.0:
			p._barrier_blast_deplete_grace_timer = max(p.barrier_blast_deplete_grace_time, 0.0)
		elif p._barrier_blast_gauge > 0.0:
			p._barrier_blast_deplete_grace_timer = max(p._barrier_blast_deplete_grace_timer - delta, 0.0)
			if p._barrier_blast_deplete_grace_timer <= 0.0:
				p._barrier_blast_gauge -= max(p.barrier_blast_drain_rate_under_min_speed, 0.0) * delta

	# Fill while grounded or while an active action provides a valid movement surface.
	var external_gain_blocked: bool = p.is_spindash_overcharge_blocking_external_barrier_blast_gain()
	if can_build and not external_gain_blocked and p.barrier_blast_fill_min_speed > 0.0:
		if speed >= p.barrier_blast_fill_min_speed:
			var t: float = 1.0
			if p.barrier_blast_fill_max_speed > p.barrier_blast_fill_min_speed:
				t = clamp(
					(speed - p.barrier_blast_fill_min_speed) / (p.barrier_blast_fill_max_speed - p.barrier_blast_fill_min_speed),
					0.0,
					1.0
				)

			var fill_rate: float = lerp(p.barrier_blast_fill_rate_min, p.barrier_blast_fill_rate_max, t)
			fill_rate = max(fill_rate, 0.0)
			fill_rate *= p.get_combo_barrier_blast_gain_multiplier()
			p._barrier_blast_gauge += fill_rate * delta

	p._barrier_blast_gauge = clamp(p._barrier_blast_gauge, 0.0, 1.0)

	var gauge_full: bool = p._barrier_blast_gauge >= 1.0
	if gauge_full:
		p._barrier_blast_active = true
		p._barrier_blast_gauge = 1.0
		p._set_special_gauge_ui(1.0)
	else:
		p._set_special_gauge_ui(p._barrier_blast_gauge)

	var reached_full: bool = gauge_full and not p._barrier_blast_was_full
	var is_building: bool = can_build and p.barrier_blast_fill_min_speed > 0.0
	is_building = is_building and speed >= p.barrier_blast_fill_min_speed and not gauge_full
	_update_barrier_blast_sfx(speed, is_building, reached_full, delta)
	p._barrier_blast_was_full = gauge_full


func _update_barrier_blast_sfx(speed: float, is_building: bool, reached_full: bool, delta: float) -> void:
	var p = _owner
	p._ensure_modules()
	if p._audio_module != null:
		p._audio_module.update_barrier_blast_audio(speed, p._barrier_blast_gauge, is_building, reached_full, delta)


func _stop_barrier_blast_wind_sfx() -> void:
	var p = _owner
	p._ensure_modules()
	if p._audio_module != null:
		p._audio_module.stop_barrier_blast_wind()


func _update_puppet_barrier_blast_fx(delta: float) -> void:
	var p = _owner
	_ensure_barrier_foot_trail_controller()
	if not p.barrier_blast_enabled:
		if p._barrier_blast_gauge > 0.0 or p._barrier_blast_active:
			p._barrier_blast_gauge = 0.0
			p._barrier_blast_active = false
			p._barrier_blast_was_full = false
			p._barrier_blast_deplete_grace_timer = 0.0
			p._barrier_blast_full_land_exit_grace_timer = 0.0
		p._sonic_boom_active = false
		p._sonic_boom_was_full = false
		p._sonic_boom_timer = 0.0
		p._sonic_boom_visible = 0.0
		_stop_barrier_blast_wind_sfx()
		_set_sonic_boom_visibility(0.0, 1.0)
		return

	p._barrier_blast_gauge = clamp(p._net_target_barrier_blast_gauge, 0.0, 1.0)
	p._barrier_blast_active = bool(p.state_flags & p.STATE_BARRIER_BLAST)

	var speed: float = p.velocity.length()
	var gauge_full: bool = p._barrier_blast_gauge >= 1.0
	var reached_full: bool = gauge_full and not p._barrier_blast_was_full

	var is_building: bool = p.attached and p.barrier_blast_fill_min_speed > 0.0
	if is_building:
		is_building = speed >= p.barrier_blast_fill_min_speed and not gauge_full

	_update_barrier_blast_sfx(speed, is_building, reached_full, delta)
	p._barrier_blast_was_full = gauge_full
	_update_sonic_boom_fx(delta)


func _update_speed_wind_sfx() -> void:
	var p = _owner
	p._ensure_modules()
	if p._audio_module != null:
		var speed: float = p.velocity.length()
		p._audio_module.update_speed_wind(speed)


func _ensure_sonic_boom_fx() -> void:
	var p = _owner
	if p._sonic_boom_fx_node != null and is_instance_valid(p._sonic_boom_fx_node):
		return
	var found: Node = p.get_node_or_null("SonicBoomFX")
	if found is Node3D:
		p._sonic_boom_fx_node = found
		_apply_sonic_boom_materials()
		if p._sonic_boom_fx_node.has_method("set_boom_state"):
			p._sonic_boom_fx_node.call("set_boom_state", 0.0, 0.0, p.sonic_boom_color)


func _apply_sonic_boom_materials() -> void:
	var p = _owner
	p._sonic_boom_materials.clear()
	if p._sonic_boom_fx_node == null or not is_instance_valid(p._sonic_boom_fx_node):
		return

	p._ensure_modules()
	var meshes: Array = []
	p._collect_mesh_instances(p._sonic_boom_fx_node, meshes)

	var shader: Shader = p.sonic_boom_shader
	if shader == null:
		var loaded: Resource = load("res://LS5Framework/Shaders/SonicBoomFX.gdshader")
		if loaded is Shader:
			shader = loaded
	if shader == null:
		return

	for m in meshes:
		if not (m is MeshInstance3D):
			continue
		var mi: MeshInstance3D = m
		var added_any: bool = false
		var override_mat: Material = mi.material_override
		if override_mat != null:
			if override_mat is ShaderMaterial:
				var shader_override: ShaderMaterial = override_mat
				if shader_override.shader == shader:
					var unique_override: ShaderMaterial = _duplicate_sonic_boom_material(shader_override, shader)
					mi.material_override = unique_override
					p._sonic_boom_materials.append(unique_override)
					added_any = true
				else:
					continue
			else:
				continue

		if not added_any:
			var mesh: Mesh = mi.mesh
			if mesh != null:
				var surface_count: int = mesh.get_surface_count()
				for i in range(surface_count):
					var surface_mat: Material = mi.get_surface_override_material(i)
					if surface_mat == null:
						surface_mat = mesh.surface_get_material(i)
					if surface_mat is ShaderMaterial:
						var shader_mat: ShaderMaterial = surface_mat
						if shader_mat.shader == shader:
							var unique_surface: ShaderMaterial = _duplicate_sonic_boom_material(shader_mat, shader)
							mi.set_surface_override_material(i, unique_surface)
							p._sonic_boom_materials.append(unique_surface)
							added_any = true

		if not added_any:
			var mat: ShaderMaterial = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("boom_alpha", 0.0)
			mat.set_shader_parameter("boom_progress", 1.0)
			mat.set_shader_parameter("boom_color", p.sonic_boom_color)
			if p.sonic_boom_override_material_params:
				mat.set_shader_parameter("boom_max_alpha", p.sonic_boom_max_alpha)
			mi.material_override = mat
			p._sonic_boom_materials.append(mat)

	p._sonic_boom_fx_node.visible = false


func _update_sonic_boom_fx(delta: float) -> void:
	var p = _owner
	if not p.sonic_boom_enabled:
		_set_sonic_boom_visibility(0.0, 1.0)
		return

	_ensure_sonic_boom_fx()
	if p._sonic_boom_fx_node == null or not is_instance_valid(p._sonic_boom_fx_node):
		return

	var gauge_full: bool = p._barrier_blast_gauge >= 1.0
	if gauge_full and not p._sonic_boom_was_full:
		p._sonic_boom_active = true
		p._sonic_boom_timer = 0.0
	if not gauge_full and p._sonic_boom_active:
		p._sonic_boom_active = false

	if p._sonic_boom_active:
		p._sonic_boom_timer += delta
		if p._sonic_boom_timer >= p.sonic_boom_duration:
			p._sonic_boom_active = false
			p._sonic_boom_timer = p.sonic_boom_duration

	p._sonic_boom_was_full = gauge_full

	var target_visible: float = 0.0
	if p._sonic_boom_active and gauge_full:
		target_visible = 1.0

	var fade_speed: float = p.sonic_boom_fade_out_speed
	if target_visible > p._sonic_boom_visible:
		fade_speed = p.sonic_boom_fade_in_speed
	p._sonic_boom_visible = move_toward(p._sonic_boom_visible, target_visible, fade_speed * delta)

	var progress: float = 1.0
	if p.sonic_boom_duration > 0.0:
		var delay: float = max(p.sonic_boom_progress_delay, 0.0)
		if p._sonic_boom_timer <= delay:
			progress = 0.0
		else:
			var denom: float = max(p.sonic_boom_duration - delay, 0.001)
			progress = clamp((p._sonic_boom_timer - delay) / denom, 0.0, 1.0)

	_set_sonic_boom_visibility(p._sonic_boom_visible, progress)
	if p._sonic_boom_visible > 0.01:
		_update_sonic_boom_orientation(delta)


func _update_jump_dash_trail(delta: float) -> void:
	var p = _owner
	if p.jump_dash_trail == null:
		return
	if not p.jump_dash_trail.has_method("update_trail"):
		return
	if not p._network_is_local_authority() and not p._network_module.is_level_present():
		if p.jump_dash_trail.has_method("stop_and_clear"):
			p.jump_dash_trail.call("stop_and_clear")
		return

	var active: bool = p.rolling
	active = active or p._jump_dash_recent_timer > 0.0
	active = active or p._homing_active or p._homing_post_attack_timer > 0.0
	active = active or p._bounce_state != p.BounceState.NONE

	var head_pos: Vector3 = p.global_transform.origin
	if p.model_root != null:
		head_pos = p.model_root.global_transform.origin
	p.jump_dash_trail.call("update_trail", delta, head_pos, active, p.velocity.length())


func _update_jump_ball(delta: float) -> void:
	var p = _owner
	if p.jump_ball == null:
		return
	if not p.jump_ball.has_method("set_jump_ball_active"):
		return
	var ball_pos: Vector3 = p.global_position
	if p.model_root != null:
		ball_pos = p.model_root.global_position
	if not p._network_is_local_authority() and not p._network_module.is_level_present():
		p.jump_ball.call("set_jump_ball_active", delta, false, ball_pos, Vector3.FORWARD, p._get_gravity_up())
		return

	var external_motion_active: bool = (
		p._rail_active
		or p._rail_switch_active
		or p._spline_active
		or p._vault_bar_active
	)
	var active: bool = (
		not external_motion_active
		and not p.attached
		and p.is_attack_active()
		and _current_action_allows_jump_ball()
	)
	if (
		p._current_action_id == &"jump"
		and p.has_method("uses_fall_blend_for_jump_animation")
		and bool(p.call("uses_fall_blend_for_jump_animation"))
	):
		active = false
	if p._hurt_active or p._is_dead or p._player_state_locked:
		active = false

	var heading: Vector3 = p.velocity
	if heading.length() <= 0.001:
		heading = p._model_forward
	if heading.length() <= 0.001:
		heading = -p.global_transform.basis.z

	var up: Vector3 = p._get_gravity_up()

	if p.jump_ball.has_method("set_speed_for_full_extrusion"):
		p.jump_ball.call("set_speed_for_full_extrusion", p.jump_ball_speed_for_full_extrusion)
	p.jump_ball.call("set_jump_ball_active", delta, active, ball_pos, heading, up)


func _current_action_allows_jump_ball() -> bool:
	var p = _owner
	if not _current_animation_allows_jump_ball():
		return false
	if p._active_action == null or not is_instance_valid(p._active_action):
		return true
	var allows: Variant = p._active_action.get("shows_jump_ball")
	if allows is bool:
		return bool(allows)
	return true


func _current_animation_allows_jump_ball() -> bool:
	var p = _owner
	if p.anim_tree == null or p.anim_tree.tree_root == null or p.anim_state == null:
		return true
	var root: AnimationNode = p.anim_tree.tree_root as AnimationNode
	var machine: AnimationNodeStateMachine = null
	if root is AnimationNodeStateMachine:
		machine = root as AnimationNodeStateMachine
	elif root is AnimationNodeBlendTree:
		var blend_tree: AnimationNodeBlendTree = root as AnimationNodeBlendTree
		if blend_tree.has_node(&"StateMachine"):
			machine = blend_tree.get_node(&"StateMachine") as AnimationNodeStateMachine
	if machine == null:
		return true
	var state: StringName = p.anim_state.get_current_node()
	if state == &"" or not machine.has_node(state):
		return true
	var animation_node: AnimationNode = machine.get_node(state)
	if animation_node == null:
		return true
	for argument: String in animation_node.resource_name.to_lower().split(";", false):
		var assignment: PackedStringArray = argument.split("=", true, 1)
		if assignment.size() != 2:
			continue
		var key: String = assignment[0].strip_edges()
		if key != JUMP_BALL_RESOURCE_ARGUMENT:
			continue
		var value: String = assignment[1].strip_edges()
		return value != "false" and value != "0" and value != "off" and value != "no"
	return true


func _set_sonic_boom_visibility(alpha: float, progress: float) -> void:
	var p = _owner
	if p._sonic_boom_fx_node != null and is_instance_valid(p._sonic_boom_fx_node):
		p._sonic_boom_fx_node.visible = alpha > 0.01
		if p._sonic_boom_fx_node.has_method("set_boom_state"):
			p._sonic_boom_fx_node.call("set_boom_state", alpha, progress, p.sonic_boom_color)

	var clamped_alpha: float = clamp(alpha, 0.0, 1.0)
	var clamped_progress: float = clamp(progress, 0.0, 1.0)
	for mat in p._sonic_boom_materials:
		if mat is ShaderMaterial:
			var sm: ShaderMaterial = mat
			sm.set_shader_parameter("boom_alpha", clamped_alpha)
			sm.set_shader_parameter("boom_progress", clamped_progress)
			sm.set_shader_parameter("boom_color", p.sonic_boom_color)
			if p.sonic_boom_override_material_params:
				sm.set_shader_parameter("boom_max_alpha", p.sonic_boom_max_alpha)


func _duplicate_sonic_boom_material(source: ShaderMaterial, shader: Shader) -> ShaderMaterial:
	var p = _owner
	var mat: ShaderMaterial = source.duplicate(true)
	mat.shader = shader
	mat.set_shader_parameter("boom_alpha", 0.0)
	mat.set_shader_parameter("boom_progress", 1.0)
	mat.set_shader_parameter("boom_color", p.sonic_boom_color)
	if p.sonic_boom_override_material_params:
		mat.set_shader_parameter("boom_max_alpha", p.sonic_boom_max_alpha)
	return mat


func _update_sonic_boom_orientation(delta: float) -> void:
	var p = _owner
	if p._sonic_boom_fx_node == null or not is_instance_valid(p._sonic_boom_fx_node):
		return

	var speed: float = p.velocity.length()
	if speed > 0.01:
		p._sonic_boom_dir = p.velocity / speed
	if p._sonic_boom_dir.length() < 0.001:
		return

	var up: Vector3 = p._get_gravity_up()

	var forward_dir: Vector3 = -p._sonic_boom_dir.normalized()
	var target_basis: Basis = Basis().looking_at(forward_dir, up)
	var scale: Vector3 = p._sonic_boom_fx_node.scale
	var new_basis: Basis = target_basis.scaled(scale)
	p._sonic_boom_fx_node.global_transform = Transform3D(new_basis, p._sonic_boom_fx_node.global_position)

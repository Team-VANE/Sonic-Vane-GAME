extends RefCounted
class_name PlayerWaterController

var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func setup_detection() -> void:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return
	for child: Node in p.get_children():
		if child is Area3D and child.name == "WaterDetector":
			child.body_entered.connect(p._on_water_body_entered)
			child.body_exited.connect(p._on_water_body_exited)
			child.area_entered.connect(p._on_water_area_entered)
			child.area_exited.connect(p._on_water_area_exited)
		if child is Area3D and child.name == "HeadWaterDetector":
			p._head_water_detector_node = child
			child.body_entered.connect(p._on_head_water_body_entered)
			child.body_exited.connect(p._on_head_water_body_exited)
			child.area_entered.connect(p._on_head_water_area_entered)
			child.area_exited.connect(p._on_head_water_area_exited)


func reset_for_level_change() -> void:
	reset_for_teleport()


func reset_for_teleport() -> void:
	var p = _owner
	if p == null:
		return
	p._water_volume_count = 0
	p._in_water_volume = false
	p._head_water_volume_count = 0
	p._head_in_water_volume = false
	p._fully_submerged = false
	p._was_in_water_volume = false
	p._was_airborne_before_water_entry = false
	p._running_on_water_surface = false
	p._water_reattach_cooldown_timer = 0.0
	p._water_last_collider = null
	p._water_last_entry_area = null
	p._water_surface_normal = p.get_gravity_up()
	p._water_footstep_timer = 0.0
	reset_logic_speed()
	if p._drowned_action != null and is_instance_valid(p._drowned_action):
		if not p._drowned_action.is_drowned():
			p._drowned_action.stop_countdown()


func register_volume_entry(collider: Node3D) -> void:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return
	if collider == null or not collider.is_in_group("water"):
		return
	p._water_volume_count += 1
	p._in_water_volume = p._water_volume_count > 0
	p._water_last_collider = collider
	var entry_area: Area3D = collider as Area3D
	if entry_area != null:
		p._water_last_entry_area = entry_area


func register_volume_exit(collider: Node3D) -> void:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return
	if collider == null or not collider.is_in_group("water"):
		return
	p._water_volume_count = max(p._water_volume_count - 1, 0)
	if p._water_volume_count <= 0:
		p._in_water_volume = false
		p._water_reattach_cooldown_timer = p.water_reattach_cooldown


func register_head_entry(collider: Node3D) -> void:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return
	if collider != null and collider.is_in_group("water"):
		p._head_water_volume_count += 1
		if p._head_water_volume_count > 0:
			p._head_in_water_volume = true
			notify_head_entered_water()


func register_head_exit(collider: Node3D) -> void:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return
	if collider != null and collider.is_in_group("water"):
		p._head_water_volume_count = max(p._head_water_volume_count - 1, 0)
		if p._head_water_volume_count <= 0:
			p._head_in_water_volume = false
			notify_head_exited_water()


func notify_head_entered_water() -> void:
	var p = _owner
	if p._drowned_action != null and is_instance_valid(p._drowned_action):
		if not p._drowned_action.is_drowned():
			p._drowned_action.start_countdown()


func notify_head_exited_water() -> void:
	var p = _owner
	if p._drowned_action != null and is_instance_valid(p._drowned_action):
		if not p._drowned_action.is_drowned():
			p._drowned_action.stop_countdown()


func is_water_collider(collider: Node) -> bool:
	if collider == null:
		return false
	return collider.is_in_group("water") or collider.is_in_group("water_surface")


func can_land_on_surface(velocity_before: Vector3, normal: Vector3) -> bool:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return false
	if p._water_reattach_cooldown_timer > 0.0:
		return false
	if velocity_before.length() < p.water_surface_landing_min_tangential_speed:
		return false
	var metrics: Dictionary = PlayerMath.compute_radial_landing_metrics(velocity_before, normal)
	var radial_angle: float = metrics.angle
	var tangential_speed: float = metrics.tangent_speed
	return (
		tangential_speed >= p.water_surface_landing_min_tangential_speed
		and radial_angle <= p.water_surface_landing_max_angle_deg
	)


func apply_surface_landing_speed_penalty(
	velocity_before: Vector3,
	normal: Vector3
) -> Vector3:
	var p = _owner
	if p == null:
		return velocity_before
	var surface_normal: Vector3 = normal.normalized()
	if surface_normal.length() < 0.001:
		surface_normal = p.get_gravity_up()
	var normal_velocity: Vector3 = surface_normal * velocity_before.dot(surface_normal)
	var tangential_velocity: Vector3 = velocity_before - normal_velocity
	var tangential_speed: float = tangential_velocity.length()
	var penalized_speed: float = max(
		tangential_speed - max(p.water_surface_landing_speed_penalty, 0.0),
		0.0
	)
	if tangential_speed > 0.001:
		tangential_velocity *= penalized_speed / tangential_speed
	else:
		tangential_velocity = Vector3.ZERO
	return normal_velocity + tangential_velocity


func apply_vertical_speed_slowdown(vertical: float, delta: float) -> float:
	var p = _owner
	if p.water_logic_speed_enabled:
		return vertical
	var max_up: float = p.jump_speed * p.water_max_up_speed_mult
	var max_down: float = p.max_fall_speed * p.water_max_down_speed_mult
	var rate: float = max(p.water_vertical_speed_slowdown_rate, 0.0)
	if vertical > max_up:
		if rate <= 0.0:
			return vertical
		return max(vertical - rate * delta, max_up)
	if vertical < -max_down:
		if rate <= 0.0:
			return vertical
		return min(vertical + rate * delta, -max_down)
	return vertical


func update_physics_state(delta: float) -> void:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return
	p._water_reattach_cooldown_timer = max(p._water_reattach_cooldown_timer - delta, 0.0)
	refresh_submersion_state()
	if p._in_water_volume:
		if p._water_footstep_timer < p.water_footstep_min_time:
			p._water_footstep_timer = p.water_footstep_min_time
		p._water_footstep_timer = min(p._water_footstep_timer + delta, p.water_footstep_max_time)
	else:
		p._water_footstep_timer = max(p._water_footstep_timer - delta, 0.0)
	if p._running_on_water_surface and p.attached:
		check_surface_min_speed()


func refresh_submersion_state() -> void:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return
	if p._running_on_water_surface and not p.attached:
		p._running_on_water_surface = false

	var was_fully_submerged: bool = p._fully_submerged
	if p.attached:
		p._fully_submerged = p._in_water_volume and p._head_in_water_volume
	else:
		p._fully_submerged = p._in_water_volume

	if p._in_water_volume and not was_fully_submerged and p._fully_submerged:
		p._was_airborne_before_water_entry = not p.attached
		play_entry_splash()
	elif not p._in_water_volume and p._was_in_water_volume:
		play_exit_splash()
		p._was_airborne_before_water_entry = false
	p._was_in_water_volume = p._in_water_volume


func update_logic_speed(delta: float) -> void:
	var p = _owner
	if not p.water_physics_enabled or not p.water_logic_speed_enabled:
		reset_logic_speed()
		return
	var submerged: bool = p._fully_submerged and not p._running_on_water_surface
	if p._automation_active and p._automation_ignore_water_physics:
		submerged = false
	if not submerged:
		var preserve_exit_speed: bool = (
			(p.water_logic_speed_preserve_grounded_exit_speed if p.attached else p.water_logic_speed_preserve_airborne_exit_speed)
			and not p._fully_submerged
			and not p._running_on_water_surface
			and not (p._automation_active and p._automation_ignore_water_physics)
			and p._water_logic_speed_current < 1.0
		)
		var submerged_clock: float = p.effective_movement_time_scale
		reset_logic_speed()
		if preserve_exit_speed:
			var exit_velocity_scale: float = submerged_clock / p.effective_movement_time_scale
			p.velocity *= exit_velocity_scale
			if p._rail_active:
				p._rail_speed *= exit_velocity_scale
		return
	var target: float = clampf(p.water_logic_speed_multiplier, 0.01, 1.0)
	if not is_equal_approx(target, p._water_logic_speed_target):
		p._water_logic_speed_start = p._water_logic_speed_current
		p._water_logic_speed_target = target
		p._water_logic_speed_elapsed = 0.0
	var duration: float = maxf(p.water_logic_speed_lerp_time, 0.0)
	p._water_logic_speed_elapsed = minf(p._water_logic_speed_elapsed + maxf(delta, 0.0), duration)
	var progress: float = clampf(p._water_logic_speed_elapsed / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	p._water_logic_speed_current = lerpf(p._water_logic_speed_start, target, smoothstep(0.0, 1.0, progress))


func reset_logic_speed() -> void:
	_owner._water_logic_speed_current = 1.0
	_owner._water_logic_speed_start = 1.0
	_owner._water_logic_speed_target = 1.0
	_owner._water_logic_speed_elapsed = 0.0


func get_surface_run_normal() -> Vector3:
	var p = _owner
	var normal: Vector3 = p._water_surface_normal.normalized()
	if normal.length() < 0.001:
		normal = p.surface_normal.normalized()
	if normal.length() < 0.001:
		normal = p.get_gravity_up()
	return normal


func check_surface_min_speed() -> void:
	var p = _owner
	if not p._running_on_water_surface or not p.attached:
		return
	var normal: Vector3 = get_surface_run_normal()
	var lateral_speed: float = p.velocity.slide(normal).length()
	if lateral_speed < p.water_surface_min_speed:
		drop_from_surface(normal)


func can_start_surface_running(normal: Vector3) -> bool:
	var p = _owner
	if p == null or not p.water_physics_enabled:
		return false
	if p._water_reattach_cooldown_timer > 0.0:
		return false
	var water_normal: Vector3 = normal.normalized()
	if water_normal.length() < 0.001:
		water_normal = p.get_gravity_up()
	return p.velocity.slide(water_normal).length() >= p.water_surface_min_speed


func start_surface_running(normal: Vector3) -> void:
	var p = _owner
	var water_normal: Vector3 = normal.normalized()
	if water_normal.length() < 0.001:
		water_normal = p.get_gravity_up()
	p._running_on_water_surface = true
	p._in_water_volume = false
	p._fully_submerged = false
	p._water_surface_normal = water_normal


func drop_from_surface(normal: Vector3) -> void:
	var p = _owner
	var drop_normal: Vector3 = normal.normalized()
	if drop_normal.length() < 0.001:
		drop_normal = p.get_gravity_up()
	p.attached = false
	p._running_on_water_surface = false
	p._in_water_volume = true
	p._fully_submerged = true
	p._water_reattach_cooldown_timer = p.water_reattach_cooldown
	p._attachment_immunity = max(p._attachment_immunity, p.water_reattach_cooldown)
	p._clear_coyote_jump_window()
	var sink_depth: float = max(p.water_surface_sink_depth, 0.0)
	if sink_depth > 0.0:
		p.global_position -= drop_normal * sink_depth
	var down_speed: float = max(p.water_surface_sink_down_speed, 0.0)
	if down_speed > 0.0:
		var normal_speed: float = p.velocity.dot(drop_normal)
		if normal_speed > -down_speed:
			p.velocity -= drop_normal * (normal_speed + down_speed)


func get_surface_normal(area: Variant) -> Vector3:
	var p = _owner
	if is_instance_valid(area) and area is Area3D:
		return (area as Area3D).global_transform.basis.y.normalized()
	return p.get_gravity_up()


func get_splash_tier(velocity_value: Vector3, surface_normal: Vector3) -> int:
	var p = _owner
	if velocity_value.length() < 0.001:
		return 0
	var incidence_angle_deg: float = rad_to_deg(acos(clamp(
		abs(velocity_value.normalized().dot(surface_normal)),
		0.0,
		1.0
	)))
	var entry_angle_deg: float = 90.0 - incidence_angle_deg
	if entry_angle_deg < p.water_splash_min_angle_deg:
		return 0
	if entry_angle_deg < p.water_splash_soft_angle_deg:
		return 1
	if entry_angle_deg < p.water_splash_hard_angle_deg:
		return 2
	return 3


func play_entry_splash() -> void:
	var p = _owner
	var normal: Vector3 = get_surface_normal(p._water_last_entry_area)
	var tier: int = get_splash_tier(p.velocity, normal)
	var sounds: Array[AudioStream] = []
	match tier:
		1: sounds = p.sfx_water_enter_soft
		2: sounds = p.sfx_water_enter_medium
		3: sounds = p.sfx_water_enter_hard
	p._last_splash_index = play_sfx_from_array(sounds, p._last_splash_index)


func play_exit_splash() -> void:
	var p = _owner
	var normal: Vector3 = get_surface_normal(p._water_last_entry_area)
	var tier: int = get_splash_tier(p.velocity, normal)
	var sounds: Array[AudioStream] = []
	match tier:
		1: sounds = p.sfx_water_exit_soft
		2: sounds = p.sfx_water_exit_medium
		3: sounds = p.sfx_water_exit_hard
	p._last_splash_index = play_sfx_from_array(sounds, p._last_splash_index)


func play_sfx_from_array(sounds: Array[AudioStream], last_index: int) -> int:
	var p = _owner
	if sounds.is_empty():
		return last_index
	var player: AudioStreamPlayer3D = p.get_node_or_null(p.water_sounds_player)
	if player == null or not is_instance_valid(player):
		return last_index
	var index: int = 0
	if sounds.size() > 1 and last_index >= 0:
		index = randi_range(0, sounds.size() - 2)
		if index >= last_index:
			index += 1
	else:
		index = randi_range(0, sounds.size() - 1)
	player.stream = sounds[index]
	player.play()
	return index

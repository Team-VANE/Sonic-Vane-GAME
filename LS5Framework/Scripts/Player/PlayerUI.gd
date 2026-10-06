extends RefCounted
class_name PlayerUI

const DEBUG_SHOW_FPS: bool = true
const WORLD_TEXT_MODEL_SCRIPT: Script = preload("res://LS5Framework/Scripts/UI/YawBillboardTextModel.gd")
const DEFAULT_HOMING_RETICLE_SOUND: AudioStream = preload("res://LS5Framework/Sounds/General/reticle.wav")

# SUMMARY:
# - UI/HUD helpers for player-facing elements (HUD, chat bubble, reticles, and effects).
# - Holds UI state so SonicPlayer stays focused on movement and gameplay rules.
# - BRIDGE: Reads player config/state and writes UI nodes without touching physics.

var _owner: Node = null
var _hud_cached: Node = null
var _action_prompt_resolver: PlayerActionPromptResolver = null

var _display_name: String = ""
var _display_color: Color = Color(1, 1, 1, 1)
var _hud_primary_color: Color = Color(1, 1, 1, 1)
var _hud_secondary_color: Color = Color(1, 1, 1, 1)
var _hud_colors_initialized: bool = false

var _name_tag_label: Label3D = null
var _chat_bubble_label = null
var _chat_bubble_timer: float = 0.0

var _homing_reticle: Sprite3D = null
var _homing_reticle_audio: AudioStreamPlayer = null
var _homing_reticle_target_id: int = 0
var _center_reticle: CenterReticleDot = null

var _speed_lines_root: Node3D = null
var _speed_lines: Array = []
var _speed_lines_spawn_accum: float = 0.0
var _speed_line_mesh: BoxMesh = null
var _speed_line_material: ShaderMaterial = null
var _speed_line_rng: RandomNumberGenerator = RandomNumberGenerator.new()

const CENTER_RETICLE_BASE_RADIUS: float = 3.0
const POST_PROCESS_EXEMPT_3D_LAYER: int = 1 << 19
const SPEED_LINE_SHADER: Shader = preload("res://LS5Framework/Scripts/Player/player_speed_line.gdshader")


func _init(owner: Node) -> void:
	_owner = owner
	_speed_line_rng.randomize()


func _get_hud_node() -> Node:
	# SUMMARY: Resolve the HUD node for local-only UI updates.
	# STEPS:
	# - Step 1: Require local authority and validate owner.
	# - Step 2: Ensure owner is a real player (not AI/buddy).
	# - Step 3: Use explicit HUD reference or cached lookup.
	# - Step 4: Search typical HUD locations and group fallback.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return null
	if not p._network_is_local_authority():
		return null
	if not p.is_in_group("Player"):
		return null
	if p.hud != null:
		return p.hud
	if _hud_cached != null:
		return _hud_cached

	var found = null
	found = p.get_node_or_null("../HUD")
	if found == null and p.get_parent() != null:
		found = p.get_parent().get_node_or_null("HUD")
	if found == null and p.get_tree() != null:
		var cs = p.get_tree().current_scene
		if cs != null:
			found = cs.get_node_or_null("HUD")
	if found == null and p.get_tree() != null:
		var list = p.get_tree().get_nodes_in_group("HUD")
		if list != null and list.size() > 0:
			found = list[0]

	_hud_cached = found
	return found


func _set_special_gauge_ui(fraction: float) -> void:
	# SUMMARY: Update the special gauge on the HUD if available.
	# STEPS:
	# - Step 1: Resolve the HUD node.
	# - Step 2: Call set_special_gauge if present.
	var h = _get_hud_node()
	if h != null and h.has_method("set_special_gauge"):
		h.call("set_special_gauge", fraction)


func _set_ability_meter_ui(ability_name: String, current: float, max_value: float, available: bool) -> void:
	var h: Node = _get_hud_node()
	if h != null and h.has_method("set_ability_meter"):
		h.call("set_ability_meter", ability_name, current, max_value, available)


func _set_coyote_available_ui(available: bool) -> void:
	# SUMMARY: Update the coyote jump indicator on the HUD if available.
	# STEPS:
	# - Step 1: Resolve the HUD node.
	# - Step 2: Call set_coyote_available if present.
	var h = _get_hud_node()
	if h != null and h.has_method("set_coyote_available"):
		h.call("set_coyote_available", available)


func _tick_ui(delta: float) -> void:
	# SUMMARY: Per-frame UI upkeep for chat bubbles, reticles, and effects.
	# STEPS:
	# - Step 1: Position name tag and chat bubble.
	# - Step 2: Countdown chat bubble timer.
	# - Step 3: Update homing reticle preview.
	# - Step 4: Update speed line VFX.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	_update_hud_character_colors()

	if _name_tag_label != null:
		_name_tag_label.position = Vector3(0.0, p.name_tag_height, 0.0)

	if _chat_bubble_label != null:
		_chat_bubble_label.position = Vector3(0.0, p.name_tag_height + p.chat_bubble_height_offset, 0.0)
		if _chat_bubble_timer > 0.0:
			_chat_bubble_timer = max(_chat_bubble_timer - delta, 0.0)
			if _chat_bubble_timer <= 0.0:
				_chat_bubble_label.visible = false

	_update_homing_reticle()
	_update_center_reticle()
	_update_speed_lines(delta)
	_update_speedometer(delta)
	_update_action_prompts()

	# Debug FPS overlay — update existing FPSLabel only (avoid creating new nodes dynamically)
	if DEBUG_SHOW_FPS:
		var h = _get_hud_node()
		if h != null and h is Control:
			var fps_label = h.get_node_or_null("FPSLabel")
			if fps_label != null:
				if fps_label.has_method("set_text") or fps_label.has_property("text"):
					fps_label.text = str(Engine.get_frames_per_second()) + " FPS"
				else:
					# If it's not a standard Label, set its custom property if available
					if fps_label.has_method("set_value"):
						fps_label.call("set_value", Engine.get_frames_per_second())
					else:
						# Fallback: print to console
						print("FPS: ", Engine.get_frames_per_second())
			else:
				# No FPSLabel in HUD; print to console as fallback
				print("FPS: ", Engine.get_frames_per_second())


func _update_action_prompts() -> void:
	var h: Node = _get_hud_node()
	if not h or not h.has_method("set_action_prompts"):
		return
	if not _action_prompt_resolver:
		_action_prompt_resolver = PlayerActionPromptResolver.new(_owner)
	h.call("set_action_prompts", _action_prompt_resolver.get_prompts(), _owner)


func _update_hud_character_colors() -> void:
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	var primary_value: Variant = p.get("_character_primary_color")
	var secondary_value: Variant = p.get("_character_secondary_color")
	if not (primary_value is Color) or not (secondary_value is Color):
		return
	var primary_color: Color = Color(primary_value)
	var secondary_color: Color = Color(secondary_value)
	if _hud_colors_initialized and primary_color == _hud_primary_color and secondary_color == _hud_secondary_color:
		return
	var h: Node = _get_hud_node()
	if h == null or not h.has_method("set_hud_character_colors"):
		return
	h.call("set_hud_character_colors", primary_color, secondary_color)
	_hud_primary_color = primary_color
	_hud_secondary_color = secondary_color
	_hud_colors_initialized = true


func set_display_name(value: String) -> void:
	# SUMMARY: Set display name and update the name tag text.
	# STEPS:
	# - Step 1: Store the new name.
	# - Step 2: Refresh the cached name tag text.
	_display_name = value
	_update_name_tag_text()


func set_display_color(value: Color) -> void:
	# SUMMARY: Set display color and update the name tag visual.
	# STEPS:
	# - Step 1: Store the new color.
	# - Step 2: Refresh name tag color.
	_display_color = value
	_update_name_tag_color()


func show_chat_bubble(message: String) -> void:
	# SUMMARY: Show a multiplayer chat bubble over the player.
	# STEPS:
	# - Step 1: Validate network and feature toggle.
	# - Step 2: Ensure bubble node exists.
	# - Step 3: Set text and start timer.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p._network_is_active():
		return
	if not p.chat_bubble_enabled:
		return
	_ensure_chat_bubble()
	if _chat_bubble_label == null:
		return

	_chat_bubble_label.set_message(message, false)
	_chat_bubble_timer = max(p.chat_bubble_duration, 0.0)
	_chat_bubble_label.visible = true


func show_prompt(message: String, duration: float) -> void:
	# SUMMARY: Show a local prompt using the chat bubble UI.
	# STEPS:
	# - Step 1: Validate feature toggle.
	# - Step 2: Ensure bubble node exists.
	# - Step 3: Set text and timer, then show/hide as needed.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p.chat_bubble_enabled:
		return
	_ensure_chat_bubble()
	if _chat_bubble_label == null:
		return
	_chat_bubble_label.set_message(message, true)
	_chat_bubble_timer = max(duration, 0.0)
	_chat_bubble_label.visible = message != ""


func clear_prompt() -> void:
	_chat_bubble_timer = 0.0
	if _chat_bubble_label == null:
		return
	_chat_bubble_label.set_message("", false)
	_chat_bubble_label.visible = false


func _ensure_name_tag() -> void:
	# World-space name tags are replaced by the local HUD player locator.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	var existing: Node = p.get_node_or_null("NameTag")
	if existing != null:
		existing.queue_free()
	_name_tag_label = null


func _ensure_chat_bubble() -> void:
	# SUMMARY: Create the chat bubble label if missing.
	# STEPS:
	# - Step 1: Check for existing label.
	# - Step 2: Create Label3D and apply visual settings.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if _chat_bubble_label != null:
		return
	var label = p.get_node_or_null("ChatBubble")
	if label == null or not label.has_method("set_message"):
		var existing_label: Node = label as Node
		if existing_label != null:
			p.remove_child(existing_label)
			existing_label.queue_free()
		label = WORLD_TEXT_MODEL_SCRIPT.new()
		label.name = "ChatBubble"
		p.add_child(label)
	_chat_bubble_label = label
	_chat_bubble_label.configure(0.01, Color.WHITE, true, POST_PROCESS_EXEMPT_3D_LAYER)
	_chat_bubble_label.visible = false


func _update_name_tag_text() -> void:
	# SUMMARY: Write display name to the name tag label.
	# STEPS:
	# - Step 1: Validate label.
	# - Step 2: Apply fallback name.
	if _name_tag_label == null:
		return
	if _display_name == "":
		_display_name = "Player"
	_name_tag_label.text = _display_name


func _update_name_tag_color() -> void:
	# SUMMARY: Update the name tag color.
	# STEPS:
	# - Step 1: Validate label.
	# - Step 2: Apply color.
	if _name_tag_label == null:
		return
	_name_tag_label.modulate = _display_color


func _update_homing_reticle() -> void:
	# SUMMARY: Update homing reticle target, visibility, and scaling.
	# STEPS:
	# - Step 1: Validate local authority and state.
	# - Step 2: Resolve the current target.
	# - Step 3: Update sprite transform, scale, and optional sound.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p._network_is_local_authority():
		_hide_homing_reticle()
		return
	if not SettingsManager.hud_visible:
		_hide_homing_reticle()
		return
	if not p.homing_reticle_enabled:
		_hide_homing_reticle()
		return
	if p._homing_active:
		_hide_homing_reticle()
		return
	if p._spring_action_lock_timer > 0.0:
		_hide_homing_reticle()
		return

	var target: Node3D = p._get_homing_reticle_target()
	if target == null or not is_instance_valid(target):
		_hide_homing_reticle()
		return

	_ensure_homing_reticle()
	if _homing_reticle == null:
		return

	var target_id: int = int(target.get_instance_id())
	if target_id != _homing_reticle_target_id:
		_homing_reticle_target_id = target_id
		_play_homing_reticle_sound()

	var tpos: Vector3 = target.global_position
	if p.has_method("get_homing_reticle_target_position"):
		var sampled_position: Variant = p.call("get_homing_reticle_target_position", target)
		if sampled_position is Vector3:
			tpos = sampled_position
	tpos.y += p.homing_reticle_height_offset
	_homing_reticle.global_position = tpos
	_homing_reticle.visible = true

	var dist: float = (p.global_position - tpos).length()
	var scale_add: float = max(dist, 0.0) * max(p.homing_reticle_scale_per_unit, 0.0)
	var scale_val: float = max(p.homing_reticle_scale_base, 0.0) + scale_add
	var max_scale: float = max(p.homing_reticle_scale_max, 0.0)
	if max_scale > 0.0:
		scale_val = min(scale_val, max_scale)
	_homing_reticle.scale = Vector3.ONE * scale_val


func _update_center_reticle() -> void:
	# SUMMARY: Update the center-screen reticle UI.
	# STEPS:
	# - Step 1: Validate local authority and settings.
	# - Step 2: Ensure reticle node exists.
	# - Step 3: Apply dot size, color, offset, and visibility.
	var p: Node = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p._network_is_local_authority():
		_hide_center_reticle()
		return
	if not SettingsManager.hud_visible or not SettingsManager.center_reticle_enabled:
		_hide_center_reticle()
		return

	_ensure_center_reticle()
	if _center_reticle == null:
		return

	var scale_val: float = max(SettingsManager.center_reticle_scale, 0.01)
	_center_reticle.scale = Vector2.ONE * scale_val
	var offset_t: float = clamp(SettingsManager.reticle_vertical_offset, 0.0, 100.0) / 100.0
	var vp_size: Vector2 = Vector2.ZERO
	if p.get_viewport() != null:
		vp_size = p.get_viewport().get_visible_rect().size
	if vp_size.y > 0.0:
		var offset_pixels: float = -0.5 * vp_size.y * offset_t
		_center_reticle.set_offset_y(offset_pixels)
	else:
		_center_reticle.set_offset_y(0.0)

	var opacity_val: float = clamp(SettingsManager.center_reticle_opacity, 0.0, 1.0)
	var dot_color: Color = SettingsManager.center_reticle_color
	dot_color.a = clamp(dot_color.a * opacity_val, 0.0, 1.0)
	_center_reticle.set_dot_color(dot_color)
	_center_reticle.visible = true


func _hide_homing_reticle() -> void:
	# SUMMARY: Hide the reticle and reset target tracking.
	# STEPS:
	# - Step 1: Hide sprite if present.
	# - Step 2: Reset target id.
	if _homing_reticle != null:
		_homing_reticle.visible = false
	_homing_reticle_target_id = 0


func _hide_center_reticle() -> void:
	if _center_reticle != null:
		_center_reticle.visible = false


func _ensure_homing_reticle() -> void:
	# SUMMARY: Create the homing reticle sprite if missing.
	# STEPS:
	# - Step 1: Validate owner.
	# - Step 2: Create and configure sprite.
	# - Step 3: Apply texture and defaults.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if _homing_reticle != null:
		return

	var sprite: Sprite3D = Sprite3D.new()
	sprite.name = "HomingReticle"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.pixel_size = max(p.homing_reticle_pixel_size, 0.001)
	sprite.render_priority = 1
	sprite.visible = false
	p.add_child(sprite)
	_homing_reticle = sprite

	_apply_homing_reticle_texture()


func _ensure_center_reticle() -> void:
	var h: Node = _get_hud_node()
	if h == null or not is_instance_valid(h):
		return
	if _center_reticle != null:
		return

	var root: Control = null
	if h is Control:
		root = h
	if root == null:
		root = h.get_node_or_null("HUDRoot") as Control
	if root == null:
		root = h.get_node_or_null("Control") as Control
	if root == null:
		return

	var dot: CenterReticleDot = CenterReticleDot.new()
	dot.name = "CenterReticle"
	dot.set_dot_radius(CENTER_RETICLE_BASE_RADIUS)
	root.add_child(dot)
	_center_reticle = dot


func _apply_homing_reticle_texture() -> void:
	# SUMMARY: Apply the reticle texture, using a fallback if needed.
	# STEPS:
	# - Step 1: Prefer exported texture if provided.
	# - Step 2: Load the default reticle texture path.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if _homing_reticle == null:
		return

	var tex: Texture2D = p.homing_reticle_texture
	if tex == null:
		var loaded: Resource = load("res://LS5Framework/Images/Homing_Reticle.png")
		if loaded is Texture2D:
			tex = loaded

	_homing_reticle.texture = tex


func _update_speedometer(delta: float) -> void:
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p._network_is_local_authority():
		return
	var h = _get_hud_node()
	if h == null or not h.has_method("set_speedometer_value"):
		return
	var logic_speed_scale: float = p.get_movement_time_scale()
	var speed: float = p._get_lateral_speed_for_anim() * logic_speed_scale
	var max_speed_val: float = p.max_speed * logic_speed_scale
	var top_speed_val: float = p.run_top_speed * logic_speed_scale
	if p.has_method("get_active_top_speed_multiplier"):
		top_speed_val *= max(float(p.call("get_active_top_speed_multiplier")), 0.0)
	h.call("set_speedometer_value", speed, max_speed_val, top_speed_val, delta)


func _update_speed_lines(delta: float) -> void:
	# SUMMARY: Spawn and update speed line VFX based on barrier blast buildup.
	# STEPS:
	# - Step 1: Validate local authority and settings.
	# - Step 2: Spawn new lines as gauge builds.
	# - Step 3: Update existing lines (motion, scale, fade, cleanup).
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p._network_is_local_authority():
		_clear_speed_lines()
		return
	if not p.speed_lines_enabled or not p.barrier_blast_enabled:
		_clear_speed_lines()
		return

	var speed: float = p.velocity.length()
	var min_speed: float = max(p.barrier_blast_fill_min_speed, 0.0)
	var can_build: bool = min_speed > 0.0 and speed >= min_speed
	var gauge_t: float = clamp(p._barrier_blast_gauge, 0.0, 1.0)

	if can_build:
		var spawn_rate: float = lerp(p.speed_lines_spawn_rate_min, p.speed_lines_spawn_rate_max, gauge_t)
		spawn_rate = max(spawn_rate, 0.0)
		_speed_lines_spawn_accum += delta * spawn_rate
		while _speed_lines_spawn_accum >= 1.0:
			_speed_lines_spawn_accum -= 1.0
			_spawn_speed_line(speed, gauge_t)
	else:
		_speed_lines_spawn_accum = 0.0

	_update_speed_line_instances(delta)


func _update_speed_line_instances(delta: float) -> void:
	if _speed_lines.is_empty():
		return

	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		_clear_speed_lines()
		return

	var remaining: Array = []
	for entry in _speed_lines:
		if entry == null or not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		var line: MeshInstance3D = data.get("node")
		if line == null or not is_instance_valid(line):
			continue

		var age: float = float(data.get("age", 0.0)) + delta
		var life: float = float(data.get("life", 0.0))
		if life <= 0.0 or age >= life:
			line.queue_free()
			continue


		var base_alpha: float = float(data.get("alpha", 1.0))
		var fade_out: float = clamp(1.0 - (age / life), 0.0, 1.0)
		var fade_in: float = 1.0
		var fade_in_time: float = float(data.get("fade_in_time", 0.0))
		if fade_in_time > 0.0:
			fade_in = smoothstep(0.0, fade_in_time, age)
		line.set_instance_shader_parameter(
			"lifecycle_alpha",
			clamp(base_alpha * min(fade_in, fade_out), 0.0, 1.0)
		)

		var grow_time: float = float(data.get("grow_time", 0.0))
		var grow_start: float = float(data.get("grow_start", 0.0))
		var grow_t: float = 1.0
		if grow_time > 0.0:
			grow_t = clamp(age / grow_time, 0.0, 1.0)
		var length: float = float(data.get("length", 1.0))
		var width: float = float(data.get("width", 0.01))
		var len_scale: float = lerp(grow_start, 1.0, grow_t)
		var line_direction: Vector3 = data.get("dir", Vector3.ZERO)
		var spawn_direction: Vector3 = data.get("spawn_dir", line_direction)
		var line_up: Vector3 = data.get("up", Vector3.UP)
		var motion_speed: float = float(data.get("motion_speed", 0.0))
		var spawn_speed: float = float(data.get("spawn_speed", motion_speed))
		var speed_scale: float = float(data.get("speed_scale", 0.0))
		var movement_time_scale: float = 1.0
		if p.has_method("get_movement_time_scale"):
			movement_time_scale = max(float(p.call("get_movement_time_scale")), 0.0)
		var trajectory_influence: float = clamp(p.speed_lines_trajectory_follow_influence, 0.0, 1.0)
		var player_speed: float = p.velocity.length()
		if trajectory_influence > 0.0 and player_speed > 0.001 and spawn_direction.length() > 0.001:
			var player_direction: Vector3 = p.velocity / player_speed
			var desired_direction: Vector3 = spawn_direction.normalized().slerp(
				player_direction,
				trajectory_influence
			).normalized()
			var trajectory_smooth: float = max(p.speed_lines_trajectory_follow_smooth, 0.0)
			var trajectory_blend: float = 1.0
			if trajectory_smooth > 0.0:
				trajectory_blend = 1.0 - exp(-trajectory_smooth * delta)
			if line_direction.length() > 0.001:
				line_direction = line_direction.normalized().slerp(
					desired_direction,
					clamp(trajectory_blend, 0.0, 1.0)
				).normalized()
			else:
				line_direction = desired_direction
			var desired_motion_speed: float = lerp(spawn_speed, player_speed, trajectory_influence)
			motion_speed = lerp(motion_speed, desired_motion_speed, clamp(trajectory_blend, 0.0, 1.0))
			data["dir"] = line_direction
			data["motion_speed"] = motion_speed
		var next_position: Vector3 = line.global_position
		if line_direction.length() > 0.001 and motion_speed > 0.0 and speed_scale > 0.0:
			var follow_distance: float = motion_speed * speed_scale * movement_time_scale * delta
			next_position += line_direction * follow_distance
			line.global_transform = Transform3D(
				_build_speed_line_basis(line_direction, line_up),
				next_position
			)
		line.scale = Vector3(width, width, length * len_scale)

		data["age"] = age
		remaining.append(data)

	_speed_lines = remaining


func _spawn_speed_line(speed: float, gauge_t: float) -> void:
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return

	var dir: Vector3 = p.velocity.normalized()
	if dir.length() < 0.001:
		return

	_ensure_speed_lines_root()
	if _speed_lines_root == null:
		return

	var up: Vector3 = p.gravity_up.normalized()
	if up.length() < 0.001:
		up = Vector3.UP
	if p.attached and p.surface_normal.length() > 0.001:
		var surface_up: Vector3 = p.surface_normal.normalized()
		if abs(dir.dot(surface_up)) < 0.98:
			up = surface_up
	if abs(dir.dot(up)) > 0.98:
		up = Vector3.UP
		if abs(dir.dot(up)) > 0.98:
			up = Vector3.FORWARD
			if abs(dir.dot(up)) > 0.98:
				up = Vector3.RIGHT
	var right: Vector3 = up.cross(dir)
	if right.length() < 0.001:
		right = Vector3.UP.cross(dir)
	if right.length() < 0.001:
		right = Vector3.FORWARD.cross(dir)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()

	var radius_variance: float = max(p.speed_lines_spawn_radius_variance, 0.0)
	var radius_scale: float = 1.0 + _speed_line_rng.randf_range(-radius_variance, radius_variance)
	var radius: float = max(p.speed_lines_spawn_radius * radius_scale, 0.0)
	var radius_vert: float = max(p.speed_lines_spawn_radius_vertical * radius_scale, 0.0)
	if radius_vert <= 0.0:
		radius_vert = radius

	var angle: float = _speed_line_rng.randf_range(0.0, TAU)
	var offset: Vector3 = right * cos(angle) * radius + up * sin(angle) * radius_vert

	var length_scale: float = lerp(1.0, max(p.speed_lines_length_scale_max, 1.0), gauge_t)
	var length_variance: float = max(p.speed_lines_length_variance, 0.0)
	var length_random_scale: float = 1.0 + _speed_line_rng.randf_range(-length_variance, length_variance)
	var length: float = max(p.speed_lines_length * length_random_scale, 0.01) * length_scale
	var width_variance: float = max(p.speed_lines_width_variance, 0.0)
	var width_random_scale: float = 1.0 + _speed_line_rng.randf_range(-width_variance, width_variance)
	var width: float = max(p.speed_lines_width * width_random_scale, 0.001)
	var back_offset: float = p.speed_lines_spawn_back_offset
	if back_offset <= 0.0:
		back_offset = length * 0.5
	var back_offset_variance: float = max(p.speed_lines_spawn_back_offset_variance, 0.0)
	back_offset *= 1.0 + _speed_line_rng.randf_range(-back_offset_variance, back_offset_variance)

	var base_alpha: float = lerp(p.speed_lines_alpha_min, p.speed_lines_alpha_max, gauge_t)
	var alpha_variance: float = max(p.speed_lines_alpha_variance, 0.0)
	base_alpha *= 1.0 + _speed_line_rng.randf_range(-alpha_variance, alpha_variance)
	base_alpha = clamp(base_alpha, 0.0, 1.0)
	var line_color: Color = p.speed_lines_color

	var line: MeshInstance3D = MeshInstance3D.new()
	line.name = "SpeedLine"
	line.mesh = _get_speed_line_mesh()
	line.material_override = _get_speed_line_material()
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.top_level = true
	_speed_lines_root.add_child(line)

	var pos: Vector3 = p.global_position + offset - dir * back_offset
	var basis: Basis = _build_speed_line_basis(dir, up)
	line.global_transform = Transform3D(basis, pos)
	line.scale = Vector3(width, width, length * max(p.speed_lines_grow_start_scale, 0.01))
	line.set_instance_shader_parameter("line_color", line_color)
	line.set_instance_shader_parameter("lifecycle_alpha", 0.0)
	line.set_instance_shader_parameter(
		"surface_end_fade",
		clamp(p.speed_lines_surface_end_fade, 0.01, 0.49)
	)
	line.set_instance_shader_parameter(
		"surface_fade_power",
		max(p.speed_lines_surface_fade_power, 0.1)
	)

	var life: float = max(p.speed_lines_lifetime, 0.05)
	var life_var: float = max(p.speed_lines_lifetime_variance, 0.0)
	if life_var > 0.0:
		life += _speed_line_rng.randf_range(-life_var, life_var)
		life = max(life, 0.05)

	var vel_scale: float = max(p.speed_lines_follow_speed_scale, 0.0)

	var entry: Dictionary = {
		"node": line,
		"speed_scale": vel_scale,
		"motion_speed": max(speed, 0.0),
		"spawn_speed": max(speed, 0.0),
		"life": life,
		"age": 0.0,
		"length": length,
		"width": width,
		"alpha": base_alpha,
		"fade_in_time": max(p.speed_lines_fade_in_time, 0.0),
		"grow_time": max(p.speed_lines_grow_time, 0.0),
		"grow_start": clamp(p.speed_lines_grow_start_scale, 0.0, 1.0),
		"dir": dir,
		"spawn_dir": dir,
		"up": up
	}
	_speed_lines.append(entry)


func _build_speed_line_basis(dir: Vector3, up_hint: Vector3) -> Basis:
	var forward: Vector3 = dir.normalized()
	if forward.length() < 0.001:
		return Basis()

	var up: Vector3 = up_hint.normalized()
	if up.length() < 0.001:
		up = Vector3.UP
	if abs(forward.dot(up)) > 0.98:
		up = Vector3.UP
		if abs(forward.dot(up)) > 0.98:
			up = Vector3.FORWARD
			if abs(forward.dot(up)) > 0.98:
				up = Vector3.RIGHT

	var right: Vector3 = up.cross(forward)
	if right.length() < 0.001:
		right = Vector3.UP.cross(forward)
	if right.length() < 0.001:
		right = Vector3.FORWARD.cross(forward)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()

	var final_up: Vector3 = forward.cross(right)
	if final_up.length() < 0.001:
		final_up = up
	else:
		final_up = final_up.normalized()

	var basis: Basis = Basis()
	basis.x = right
	basis.y = final_up
	basis.z = -forward
	return basis


func _ensure_speed_lines_root() -> void:
	if _speed_lines_root != null:
		return
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	var root: Node3D = Node3D.new()
	root.name = "SpeedLines"
	root.top_level = true
	p.add_child(root)
	_speed_lines_root = root


func _get_speed_line_mesh() -> BoxMesh:
	if _speed_line_mesh != null:
		return _speed_line_mesh
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE
	_speed_line_mesh = mesh
	return mesh


func _get_speed_line_material() -> ShaderMaterial:
	if _speed_line_material != null:
		return _speed_line_material
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SPEED_LINE_SHADER
	_speed_line_material = mat
	return mat


func _clear_speed_lines() -> void:
	if _speed_lines_root != null and is_instance_valid(_speed_lines_root):
		_speed_lines_root.queue_free()
	_speed_lines_root = null
	_speed_lines.clear()
	_speed_lines_spawn_accum = 0.0


func _ensure_homing_reticle_audio() -> void:
	# SUMMARY: Create a non-spatial audio player for reticle sounds.
	# STEPS:
	# - Step 1: Validate owner.
	# - Step 2: Create AudioStreamPlayer if missing.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if _homing_reticle_audio != null:
		return

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = "HomingReticleSfx"
	p.add_child(player)
	_homing_reticle_audio = player


func _play_homing_reticle_sound() -> void:
	# SUMMARY: Play the reticle sound when target changes.
	# STEPS:
	# - Step 1: Validate toggle and owner.
	# - Step 2: Resolve stream (exported or default).
	# - Step 3: Play through local audio player.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if not p.homing_reticle_sound_enabled:
		return

	_ensure_homing_reticle_audio()
	if _homing_reticle_audio == null:
		return

	var stream: AudioStream = p.homing_reticle_sound
	if stream == null:
		stream = DEFAULT_HOMING_RETICLE_SOUND
	if stream == null:
		return

	var bus_name: StringName = p.homing_reticle_sound_bus
	if bus_name != StringName(""):
		_homing_reticle_audio.bus = bus_name
	_homing_reticle_audio.volume_db = p.homing_reticle_sound_volume_db
	_homing_reticle_audio.stream = stream
	_homing_reticle_audio.play()

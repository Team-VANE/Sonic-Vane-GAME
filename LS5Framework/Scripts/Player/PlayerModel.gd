extends RefCounted
class_name PlayerModel

# SUMMARY:
# - Handles visual orientation and model appearance for the player.
# - Applies character tinting and keeps model alignment stable on surfaces.
# - BRIDGE: Writes visual_up and _model_forward, which PlayerAnimation reads for blending.

var _owner: Node = null


func _init(owner: Node) -> void:
	_owner = owner


func _get_owner_gravity_up() -> Vector3:
	if _owner != null and is_instance_valid(_owner) and _owner.has_method("get_gravity_up"):
		var gravity_up_value = _owner.call("get_gravity_up")
		if gravity_up_value is Vector3:
			var gravity_up: Vector3 = (gravity_up_value as Vector3).normalized()
			if gravity_up.length() >= 0.001:
				return gravity_up
	return Vector3.UP


func _apply_character_tint() -> void:
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.model_root == null:
		return
	if not p.character_tint_enabled:
		_clear_character_tint_overrides()
		return
	if p._character_tint_shader == null:
		var sh: Resource = load("res://LS5Framework/Shaders/CharacterTint.gdshader")
		if sh is Shader:
			p._character_tint_shader = sh
		else:
			return
	if p._character_tint_transparent_shader == null:
		var transparent_shader: Resource = load("res://LS5Framework/Shaders/CharacterTintTransparent.gdshader")
		if transparent_shader is Shader:
			p._character_tint_transparent_shader = transparent_shader

	var meshes: Array = []
	_collect_mesh_instances(p.model_root, meshes)
	for mesh_value: Variant in meshes:
		if not mesh_value is MeshInstance3D:
			continue
		var mesh_instance: MeshInstance3D = mesh_value as MeshInstance3D
		var mesh_obj: Mesh = mesh_instance.mesh
		if mesh_obj == null:
			continue
		var surface_count: int = mesh_obj.get_surface_count()
		for surface_index: int in range(surface_count):
			var existing_override: Material = mesh_instance.get_surface_override_material(surface_index)
			var source_was_override: bool = existing_override != null
			var src_mat: Material = mesh_instance.get_active_material(surface_index)
			if _is_character_tint_material(src_mat):
				var tint_material: ShaderMaterial = src_mat as ShaderMaterial
				var stored_source: Variant = tint_material.get_meta(&"character_tint_source_material", null)
				src_mat = stored_source as Material if stored_source is Material else null
				source_was_override = bool(tint_material.get_meta(&"character_tint_source_was_override", false))
			var base_mat: Material = mesh_obj.surface_get_material(surface_index)
			if src_mat == null:
				src_mat = base_mat
			if src_mat == null:
				continue
			var base_tex: Texture2D = null
			var base_material: BaseMaterial3D = null
			if src_mat is BaseMaterial3D:
				base_material = src_mat as BaseMaterial3D
				base_tex = base_material.albedo_texture
			elif base_mat is BaseMaterial3D:
				base_material = base_mat as BaseMaterial3D
				base_tex = base_material.albedo_texture
			var matching_material: Material = src_mat
			if src_mat.has_meta(&"character_color_source_material"):
				var matching_source: Variant = src_mat.get_meta(&"character_color_source_material")
				if matching_source is Material:
					matching_material = matching_source as Material
			var entry: CharacterColorMaterialEntry = _get_character_color_entry(matching_material, base_tex)
			if entry == null:
				if _is_character_tint_material(existing_override):
					_restore_character_tint_override(mesh_instance, surface_index, existing_override as ShaderMaterial)
				continue

			var uses_transparency: bool = false
			if base_material != null:
				uses_transparency = (
					base_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
					or base_material.albedo_color.a < 0.999
				)
			var desired_shader: Shader = p._character_tint_transparent_shader if uses_transparency else p._character_tint_shader
			if desired_shader == null:
				continue
			var shader_material: ShaderMaterial = null
			if existing_override is ShaderMaterial and (existing_override as ShaderMaterial).shader == desired_shader:
				shader_material = existing_override as ShaderMaterial
			else:
				shader_material = ShaderMaterial.new()
				shader_material.shader = desired_shader
			shader_material.set_meta(&"character_tint_source_material", src_mat)
			shader_material.set_meta(&"character_tint_source_was_override", source_was_override)

			var metallic_scalar: float = 0.0
			var roughness_scalar: float = 0.5
			var specular_scalar: float = 0.5
			var metallic_tex: Texture2D = null
			var roughness_tex: Texture2D = null
			var normal_tex: Texture2D = null
			var metallic_channel: int = 0
			var roughness_channel: int = 0
			var normal_scale: float = 1.0
			var has_metallic_tex: bool = false
			var has_roughness_tex: bool = false
			var has_normal_tex: bool = false
			var base_color: Color = Color.WHITE
			var emission_enabled: bool = false
			var emission_tex: Texture2D = null
			var emission_color: Color = Color.BLACK
			var emission_energy: float = 1.0
			var alpha_scissor_enabled: bool = false
			var alpha_scissor_threshold: float = 0.5
			var afterimage_alpha: float = 1.0

			if base_material != null:
				base_color = base_material.albedo_color
				if StringName(src_mat.resource_name) == &"FootAfterImage":
					afterimage_alpha = base_color.a
					base_color.a = 1.0
				var metallic_prop = base_material.get("metallic")
				if metallic_prop is float or metallic_prop is int:
					metallic_scalar = float(metallic_prop)
				var roughness_prop = base_material.get("roughness")
				if roughness_prop is float or roughness_prop is int:
					roughness_scalar = float(roughness_prop)
				var specular_prop = base_material.get("metallic_specular")
				if not (specular_prop is float or specular_prop is int):
					specular_prop = base_material.get("specular")
				if specular_prop is float or specular_prop is int:
					specular_scalar = float(specular_prop)

				var metallic_tex_prop = base_material.get("metallic_texture")
				if metallic_tex_prop is Texture2D:
					metallic_tex = metallic_tex_prop
					has_metallic_tex = true
					var metallic_channel_prop = base_material.get("metallic_texture_channel")
					if metallic_channel_prop is int:
						metallic_channel = int(metallic_channel_prop)
				else:
					metallic_tex = null
					has_metallic_tex = false
					metallic_channel = 0

				var roughness_tex_prop = base_material.get("roughness_texture")
				if roughness_tex_prop is Texture2D:
					roughness_tex = roughness_tex_prop
					has_roughness_tex = true
					var roughness_channel_prop = base_material.get("roughness_texture_channel")
					if roughness_channel_prop is int:
						roughness_channel = int(roughness_channel_prop)
				else:
					roughness_tex = null
					has_roughness_tex = false
					roughness_channel = 0

				if bool(base_material.get("normal_enabled")):
					var normal_tex_prop = base_material.get("normal_texture")
					if normal_tex_prop is Texture2D:
						normal_tex = normal_tex_prop
						has_normal_tex = true
						var normal_scale_prop = base_material.get("normal_scale")
						if normal_scale_prop is float or normal_scale_prop is int:
							normal_scale = float(normal_scale_prop)
					else:
						normal_tex = null
						has_normal_tex = false
						normal_scale = 1.0
				else:
					normal_tex = null
					has_normal_tex = false
					normal_scale = 1.0
				emission_enabled = base_material.emission_enabled
				emission_tex = base_material.emission_texture
				emission_color = base_material.emission
				emission_energy = base_material.emission_energy_multiplier
				alpha_scissor_enabled = base_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				alpha_scissor_threshold = base_material.alpha_scissor_threshold

			var selected_color: Color = entry.get_color(
				p._character_primary_color,
				p._character_secondary_color,
				p._character_trail_color
			)
			var applied_texture: Texture2D = entry.texture if entry.texture != null else base_tex
			shader_material.set_shader_parameter("base_tex", applied_texture)
			shader_material.set_shader_parameter("base_color", base_color)
			shader_material.set_shader_parameter("mask_primary", entry.mask)
			shader_material.set_shader_parameter("mask_secondary", null)
			shader_material.set_shader_parameter("primary_strength", 1.0)
			shader_material.set_shader_parameter("secondary_strength", 0.0)
			shader_material.set_shader_parameter("primary_color", selected_color)
			shader_material.set_shader_parameter("secondary_color", selected_color)
			shader_material.set_shader_parameter("metallic_scalar", metallic_scalar)
			shader_material.set_shader_parameter("roughness_scalar", roughness_scalar)
			shader_material.set_shader_parameter("specular_scalar", specular_scalar)
			shader_material.set_shader_parameter("metallic_tex", metallic_tex)
			shader_material.set_shader_parameter("roughness_tex", roughness_tex)
			shader_material.set_shader_parameter("normal_tex", normal_tex)
			shader_material.set_shader_parameter("has_metallic_tex", has_metallic_tex)
			shader_material.set_shader_parameter("has_roughness_tex", has_roughness_tex)
			shader_material.set_shader_parameter("has_normal_tex", has_normal_tex)
			shader_material.set_shader_parameter("metallic_tex_channel", metallic_channel)
			shader_material.set_shader_parameter("roughness_tex_channel", roughness_channel)
			shader_material.set_shader_parameter("normal_scale", normal_scale)
			shader_material.set_shader_parameter("emission_enabled", emission_enabled)
			shader_material.set_shader_parameter("emission_tex", emission_tex)
			shader_material.set_shader_parameter("emission_color", emission_color)
			shader_material.set_shader_parameter("emission_energy", emission_energy)
			shader_material.set_shader_parameter("saturation_threshold", clamp(p.character_hue_saturation_threshold, 0.0, 1.0))
			shader_material.set_shader_parameter("saturation_softness", clamp(p.character_hue_saturation_softness, 0.0, 1.0))
			shader_material.set_shader_parameter("saturation_exponent", max(p.character_hue_saturation_exponent, 0.01))
			shader_material.set_shader_parameter("overlay_strength", clamp(p.character_hue_overlay_strength, 0.0, 1.0))
			_configure_character_surface_passes(
				shader_material,
				src_mat.next_pass,
				applied_texture,
				base_color,
				entry.mask,
				selected_color
			)
			if uses_transparency:
				shader_material.set_shader_parameter("alpha_scissor_enabled", alpha_scissor_enabled)
				shader_material.set_shader_parameter("alpha_scissor_threshold", alpha_scissor_threshold)
				shader_material.set_shader_parameter("afterimage_alpha", afterimage_alpha)
			mesh_instance.set_surface_override_material(surface_index, shader_material)


func _configure_character_surface_passes(
	tint_material: ShaderMaterial,
	source_pass: Material,
	base_texture: Texture2D,
	base_color: Color,
	mask: Texture2D,
	selected_color: Color
) -> void:
	tint_material.next_pass = _duplicate_character_surface_pass(
		source_pass,
		base_texture,
		base_color,
		mask,
		selected_color
	)


func _duplicate_character_surface_pass(
	source_pass: Material,
	base_texture: Texture2D,
	base_color: Color,
	mask: Texture2D,
	selected_color: Color
) -> Material:
	if source_pass == null:
		return null
	var copied_pass: Material = source_pass.duplicate() as Material
	if copied_pass == null:
		return source_pass
	copied_pass.next_pass = _duplicate_character_surface_pass(
		source_pass.next_pass,
		base_texture,
		base_color,
		mask,
		selected_color
	)
	if not copied_pass is ShaderMaterial:
		return copied_pass
	var shader_material: ShaderMaterial = copied_pass as ShaderMaterial
	if shader_material.shader == null:
		return copied_pass
	var shader_path: String = shader_material.shader.resource_path
	if shader_path != "res://LS5Framework/Shaders/CharacterSurfaceOutline.gdshader" and shader_path != "res://LS5Framework/Shaders/CharacterUekawaRim.gdshader":
		return copied_pass
	_configure_character_color_pass(
		shader_material,
		base_texture,
		base_color,
		mask,
		selected_color
	)
	return copied_pass


func _configure_character_color_pass(
	shader_material: ShaderMaterial,
	base_texture: Texture2D,
	base_color: Color,
	mask: Texture2D,
	selected_color: Color
) -> void:
	if shader_material == null:
		return
	shader_material.set_shader_parameter(&"tint_enabled", true)
	shader_material.set_shader_parameter(&"base_tex", base_texture)
	shader_material.set_shader_parameter(&"base_color", base_color)
	shader_material.set_shader_parameter(&"mask_primary", mask)
	shader_material.set_shader_parameter(&"mask_secondary", null)
	shader_material.set_shader_parameter(&"primary_strength", 1.0)
	shader_material.set_shader_parameter(&"secondary_strength", 0.0)
	shader_material.set_shader_parameter(&"primary_color", selected_color)
	shader_material.set_shader_parameter(&"secondary_color", selected_color)
	shader_material.set_shader_parameter(
		&"saturation_threshold",
		clamp(_owner.character_hue_saturation_threshold, 0.0, 1.0)
	)
	shader_material.set_shader_parameter(
		&"saturation_softness",
		clamp(_owner.character_hue_saturation_softness, 0.0, 1.0)
	)
	shader_material.set_shader_parameter(
		&"saturation_exponent",
		max(_owner.character_hue_saturation_exponent, 0.01)
	)
	shader_material.set_shader_parameter(
		&"overlay_strength",
		clamp(_owner.character_hue_overlay_strength, 0.0, 1.0)
	)


func _clear_character_tint_overrides() -> void:
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.model_root == null:
		return
	var meshes: Array = []
	_collect_mesh_instances(p.model_root, meshes)
	for mesh_value: Variant in meshes:
		if not mesh_value is MeshInstance3D:
			continue
		var mesh_instance: MeshInstance3D = mesh_value as MeshInstance3D
		var mesh_obj: Mesh = mesh_instance.mesh
		if mesh_obj == null:
			continue
		var surface_count: int = mesh_obj.get_surface_count()
		for surface_index: int in range(surface_count):
			var existing_override: Material = mesh_instance.get_surface_override_material(surface_index)
			if _is_character_tint_material(existing_override):
				_restore_character_tint_override(mesh_instance, surface_index, existing_override as ShaderMaterial)


func _get_character_color_entry(
	source_material: Material,
	base_texture: Texture2D
) -> CharacterColorMaterialEntry:
	var p = _owner
	if p == null or not is_instance_valid(p) or p.character_visual_profile == null:
		return null
	for entry: CharacterColorMaterialEntry in p.character_visual_profile.color_materials:
		if entry != null and entry.matches(source_material, base_texture):
			return entry
	return null


func _is_character_tint_material(material: Material) -> bool:
	var p = _owner
	if not material is ShaderMaterial or p == null or not is_instance_valid(p):
		return false
	var shader: Shader = (material as ShaderMaterial).shader
	return shader != null and (
		shader == p._character_tint_shader
		or shader == p._character_tint_transparent_shader
	)


func _restore_character_tint_override(
	mesh_instance: MeshInstance3D,
	surface_index: int,
	shader_material: ShaderMaterial
) -> void:
	var source_was_override: bool = bool(
		shader_material.get_meta(&"character_tint_source_was_override", false)
	)
	var source_value: Variant = shader_material.get_meta(&"character_tint_source_material", null)
	var source_material: Material = source_value as Material if source_value is Material else null
	mesh_instance.set_surface_override_material(
		surface_index,
		source_material if source_was_override else null
	)


func _collect_mesh_instances(node: Node, out: Array) -> void:
	# SUMMARY: Collect all MeshInstance3D nodes in the subtree.
	# STEPS:
	# - Step 1: Append meshes at this node.
	# - Step 2: Recurse into children.
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_mesh_instances(c, out)


func _step_visual_up_toward(target: Vector3, speed_deg: float, delta: float) -> void:
	# SUMMARY: Smooth visual_up toward a target by a max angular step.
	# STEPS:
	# - Step 1: Normalize inputs and early-out when aligned.
	# - Step 2: Rotate toward target by the clamped step.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return

	var t: Vector3 = target
	if t.length() < 0.001:
		t = _get_owner_gravity_up()
	t = t.normalized()

	if p.visual_up.length() < 0.001:
		p.visual_up = t
		return

	p.visual_up = p.visual_up.normalized()

	var dot_ut: float = clamp(p.visual_up.dot(t), -1.0, 1.0)
	var angle: float = acos(dot_ut)
	if angle < 0.0001:
		p.visual_up = t
		return

	var speed_used: float = max(speed_deg, 0.0)
	var max_step: float = deg_to_rad(speed_used) * delta
	if max_step <= 0.0:
		return

	var t_step: float = min(1.0, max_step / angle)
	var axis: Vector3 = p.visual_up.cross(t)
	var axis_len: float = axis.length()
	if axis_len < 0.0001:
		p.visual_up = t
		return

	axis /= axis_len
	var rot: Basis = Basis(axis, angle * t_step)
	p.visual_up = (rot * p.visual_up).normalized()


func _step_air_torque_frame_toward(target_up: Vector3, speed_deg: float, delta: float) -> void:
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return

	var target: Vector3 = target_up.normalized()
	if target.length() < 0.001:
		return

	var current_up: Vector3 = p.visual_up.normalized()
	if current_up.length() < 0.001:
		current_up = target

	var visual_forward: Vector3 = p._air_torque_visual_forward
	visual_forward -= current_up * visual_forward.dot(current_up)
	if visual_forward.length() < 0.001 and p.model_root != null:
		visual_forward = -p.model_root.global_transform.basis.z
		visual_forward -= current_up * visual_forward.dot(current_up)
	if visual_forward.length() < 0.001:
		var forward_fallback: Vector3 = Vector3.FORWARD
		if abs(forward_fallback.dot(current_up)) > 0.99:
			forward_fallback = Vector3.RIGHT
		visual_forward = forward_fallback - current_up * forward_fallback.dot(current_up)
	visual_forward = visual_forward.normalized()

	var alignment_dot: float = clamp(current_up.dot(target), -1.0, 1.0)
	var angle: float = acos(alignment_dot)
	if angle < 0.0001:
		p.visual_up = target
		visual_forward -= target * visual_forward.dot(target)
		if visual_forward.length() > 0.001:
			visual_forward = visual_forward.normalized()
			visual_forward = _step_trajectory_gravity_yaw(visual_forward, target, speed_deg, delta)
			p._air_torque_visual_forward = visual_forward
		return

	var axis: Vector3 = current_up.cross(target)
	if axis.length() < 0.0001:
		axis = visual_forward.cross(current_up)
	if axis.length() < 0.0001:
		axis = Vector3.RIGHT - current_up * Vector3.RIGHT.dot(current_up)
	if axis.length() < 0.0001:
		axis = Vector3.FORWARD - current_up * Vector3.FORWARD.dot(current_up)
	axis = axis.normalized()

	var step: float = angle
	var speed_used: float = max(speed_deg, 0.0)
	if speed_used > 0.0:
		step = min(angle, deg_to_rad(speed_used) * max(delta, 0.0))
	if step <= 0.0:
		return

	var rotation: Basis = Basis(axis, step)
	p.visual_up = (rotation * current_up).normalized()
	if step >= angle - 0.0001:
		p.visual_up = target
	visual_forward = rotation * visual_forward
	visual_forward -= p.visual_up * visual_forward.dot(p.visual_up)
	if visual_forward.length() > 0.001:
		visual_forward = visual_forward.normalized()
		visual_forward = _step_trajectory_gravity_yaw(visual_forward, target, speed_deg, delta)
		p._air_torque_visual_forward = visual_forward


func _step_trajectory_gravity_yaw(
	visual_forward: Vector3,
	trajectory_up: Vector3,
	speed_deg: float,
	delta: float
) -> Vector3:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return visual_forward
	if not p._spring_trajectory_gravity_yaw_enabled:
		return visual_forward

	var strength: float = max(p._spring_trajectory_gravity_yaw_strength, 0.0)
	if strength <= 0.0:
		return visual_forward
	var gravity_up: Vector3 = _get_owner_gravity_up()
	var trajectory: Vector3 = trajectory_up.normalized()
	if trajectory.length() < 0.001:
		return visual_forward

	var tilt_angle_deg: float = rad_to_deg(acos(clamp(trajectory.dot(gravity_up), -1.0, 1.0)))
	var safe_angle_deg: float = clamp(p._spring_trajectory_gravity_yaw_safe_angle_deg, 0.0, 179.9)
	if tilt_angle_deg <= safe_angle_deg:
		return visual_forward
	var full_angle_deg: float = clamp(
		max(p._spring_trajectory_gravity_yaw_full_angle_deg, safe_angle_deg + 0.001),
		safe_angle_deg + 0.001,
		180.0
	)
	var yaw_influence: float = smoothstep(safe_angle_deg, full_angle_deg, tilt_angle_deg)
	yaw_influence = clamp(yaw_influence * strength, 0.0, 1.0)
	if yaw_influence <= 0.0:
		return visual_forward

	var frame_up: Vector3 = p.visual_up.normalized()
	if frame_up.length() < 0.001:
		frame_up = trajectory
	var gravity_forward: Vector3 = -gravity_up
	gravity_forward -= frame_up * gravity_forward.dot(frame_up)
	var minimum_projection: float = max(sin(deg_to_rad(safe_angle_deg)), 0.001)
	if gravity_forward.length() <= minimum_projection:
		return visual_forward
	gravity_forward = gravity_forward.normalized()

	var forward: Vector3 = visual_forward - frame_up * visual_forward.dot(frame_up)
	if forward.length() < 0.001:
		return gravity_forward
	forward = forward.normalized()
	var signed_yaw: float = atan2(
		frame_up.dot(forward.cross(gravity_forward)),
		clamp(forward.dot(gravity_forward), -1.0, 1.0)
	)
	if abs(signed_yaw) < 0.0001:
		return gravity_forward

	var yaw_step: float = signed_yaw * yaw_influence
	var speed_used: float = max(speed_deg, 0.0)
	if speed_used > 0.0:
		var max_yaw_step: float = deg_to_rad(speed_used) * max(delta, 0.0) * yaw_influence
		yaw_step = clamp(signed_yaw, -max_yaw_step, max_yaw_step)
	return forward.rotated(frame_up, yaw_step).normalized()


func _should_end_trajectory_torque_for_low_horizontal_speed() -> bool:
	var p = _owner
	if p == null or not is_instance_valid(p):
		return false
	var minimum_horizontal_speed: float = max(p._spring_trajectory_torque_min_horizontal_speed, 0.0)
	if minimum_horizontal_speed <= 0.0:
		return false

	var gravity_up: Vector3 = _get_owner_gravity_up()
	var vertical_speed: float = p.velocity.dot(gravity_up)
	if vertical_speed <= 0.0:
		return false
	var horizontal_velocity: Vector3 = p.velocity - gravity_up * vertical_speed
	return horizontal_velocity.length() < minimum_horizontal_speed


func _get_air_landing_frame_forward(current_up: Vector3) -> Vector3:
	var p = _owner
	var visual_forward: Vector3 = p._air_torque_visual_forward
	visual_forward -= current_up * visual_forward.dot(current_up)
	if visual_forward.length() < 0.001 and p.model_root != null:
		visual_forward = -p.model_root.global_transform.basis.z
		visual_forward -= current_up * visual_forward.dot(current_up)
	if visual_forward.length() < 0.001:
		visual_forward = p._model_forward - current_up * p._model_forward.dot(current_up)
	if visual_forward.length() < 0.001:
		var fallback_forward: Vector3 = Vector3.FORWARD
		if abs(fallback_forward.dot(current_up)) > 0.99:
			fallback_forward = Vector3.RIGHT
		visual_forward = fallback_forward - current_up * fallback_forward.dot(current_up)
	return visual_forward.normalized()


func _resolve_air_landing_pitch_direction(current_up: Vector3, visual_forward: Vector3) -> float:
	var p = _owner
	if p._air_landing_align_directional_pitch_complete:
		return 0.0
	if p._air_landing_align_pitch_preference_resolved:
		return p._air_landing_align_pitch_direction

	p._air_landing_align_pitch_preference_resolved = true
	p._air_landing_align_pitch_direction = 0.0
	if not p.airborne_landing_align_directional_pitch_enabled:
		return 0.0
	if p._spring_trajectory_landing_forward_pitch_active:
		p._air_landing_align_pitch_direction = -1.0
		return -1.0

	var right: Vector3 = visual_forward.cross(current_up)
	if right.length() < 0.001:
		return 0.0
	right = right.normalized()
	var pitch_speed: float = p._air_torque_angular_velocity.dot(right)
	var minimum_pitch_speed: float = deg_to_rad(
		max(p.airborne_landing_align_pitch_preference_min_speed_deg, 0.0)
	)
	if abs(pitch_speed) <= minimum_pitch_speed:
		return 0.0

	p._air_landing_align_pitch_direction = -1.0 if pitch_speed < 0.0 else 1.0
	return p._air_landing_align_pitch_direction


func _is_flat_jump_full_directional_facing_active() -> bool:
	var p = _owner
	if not p._jumped_from_ground:
		return false
	var flat_detach_limit: float = max(p.airborne_torque_flat_detach_max_angle_deg, 0.0)
	if flat_detach_limit <= 0.0:
		return false
	return p._last_detach_angle_deg <= flat_detach_limit


func _step_air_landing_movement_yaw(
	current_up: Vector3,
	visual_forward: Vector3,
	delta: float
) -> Vector3:
	var p = _owner
	if not p.airborne_landing_align_movement_yaw_enabled:
		return visual_forward

	var terrain_up: Vector3 = p._air_landing_align_normal.normalized()
	if terrain_up.length() < 0.001:
		terrain_up = current_up
	var terrain_movement: Vector3 = p.velocity - terrain_up * p.velocity.dot(terrain_up)
	var movement_speed: float = terrain_movement.length()
	var full_directional_facing: bool = _is_flat_jump_full_directional_facing_active()
	var minimum_speed: float = max(p.airborne_landing_align_movement_yaw_min_speed, 0.0)
	if full_directional_facing:
		minimum_speed = max(p.model_turn_min_speed, 0.0)
	if movement_speed <= minimum_speed:
		return visual_forward

	var current_forward: Vector3 = visual_forward - current_up * visual_forward.dot(current_up)
	var target_forward: Vector3 = terrain_movement - current_up * terrain_movement.dot(current_up)
	if target_forward.length() < 0.001:
		return visual_forward
	target_forward = target_forward.normalized()
	if current_forward.length() < 0.001:
		return target_forward
	current_forward = current_forward.normalized()
	var yaw_angle: float = atan2(
		current_up.dot(current_forward.cross(target_forward)),
		clamp(current_forward.dot(target_forward), -1.0, 1.0)
	)
	if abs(yaw_angle) < 0.0001:
		return target_forward

	var full_speed: float = max(
		p.airborne_landing_align_movement_yaw_full_speed,
		minimum_speed + 0.001
	)
	var movement_influence: float = smoothstep(minimum_speed, full_speed, movement_speed)
	var align_influence: float = lerp(
		0.25,
		1.0,
		clamp(p._air_landing_align_ramp, 0.0, 1.0)
	)
	var level_t: float = clamp((current_up.dot(terrain_up) + 1.0) * 0.5, 0.0, 1.0)
	var level_influence: float = smoothstep(0.0, 1.0, level_t)
	if full_directional_facing:
		movement_influence = 1.0
		align_influence = 1.0
		level_influence = 1.0
	var yaw_speed: float = max(p.airborne_landing_align_movement_yaw_speed_deg, 0.0)
	yaw_speed *= movement_influence * align_influence * level_influence
	var max_yaw_step: float = deg_to_rad(yaw_speed) * max(delta, 0.0)
	if max_yaw_step <= 0.0:
		return current_forward
	var yaw_step: float = clamp(yaw_angle, -max_yaw_step, max_yaw_step)
	return current_forward.rotated(current_up, yaw_step).normalized()


func _step_air_landing_alignment(delta: float) -> void:
	var p = _owner
	if not p._air_landing_align_active:
		return

	var align_normal: Vector3 = p._air_landing_align_normal.normalized()
	if align_normal.length() < 0.001:
		return
	var current_up: Vector3 = p.visual_up.normalized()
	if current_up.length() < 0.001:
		p.visual_up = align_normal
		return

	var alignment_dot: float = clamp(current_up.dot(align_normal), -1.0, 1.0)
	var shortest_angle: float = acos(alignment_dot)
	var completion_angle: float = deg_to_rad(
		max(p.airborne_landing_align_completion_angle_deg, 0.0)
	)
	if shortest_angle <= max(completion_angle, 0.0001):
		p.visual_up = align_normal
		p._air_landing_align_directional_pitch_complete = true
		var aligned_forward: Vector3 = _get_air_landing_frame_forward(align_normal)
		p._air_torque_visual_forward = _step_air_landing_movement_yaw(
			align_normal,
			aligned_forward,
			delta
		)
		return

	var align_speed_deg: float = max(p.airborne_landing_align_speed_deg, 0.0)
	var align_ramp: float = clamp(p._air_landing_align_ramp, 0.0, 1.0)
	var align_speed_scale: float = max(p._air_landing_align_speed_scale, 0.0)
	align_speed_deg *= align_ramp * align_speed_scale
	var max_step: float = deg_to_rad(align_speed_deg) * max(delta, 0.0)
	if max_step <= 0.0:
		return

	var visual_forward: Vector3 = _get_air_landing_frame_forward(current_up)
	var right: Vector3 = visual_forward.cross(current_up).normalized()
	var preferred_pitch_direction: float = _resolve_air_landing_pitch_direction(
		current_up,
		visual_forward
	)
	var remaining_step: float = max_step
	var next_up: Vector3 = current_up
	var next_forward: Vector3 = visual_forward

	if preferred_pitch_direction != 0.0 and right.length() > 0.001:
		var target_up_component: float = align_normal.dot(next_up)
		var target_forward_component: float = align_normal.dot(next_forward)
		var pitch_angle: float = atan2(-target_forward_component, target_up_component)
		if abs(pitch_angle) > 0.0001:
			if pitch_angle * preferred_pitch_direction < 0.0:
				pitch_angle += TAU * preferred_pitch_direction
			var pitch_distance: float = abs(pitch_angle)
			var pitch_step: float = min(pitch_distance, remaining_step)
			pitch_step *= -1.0 if pitch_angle < 0.0 else 1.0
			var pitch_rotation: Basis = Basis(right, pitch_step)
			next_up = (pitch_rotation * next_up).normalized()
			next_forward = (pitch_rotation * next_forward).normalized()
			remaining_step = max(remaining_step - abs(pitch_step), 0.0)
			if abs(pitch_step) >= pitch_distance - 0.0001:
				p._air_landing_align_directional_pitch_complete = true
		else:
			p._air_landing_align_directional_pitch_complete = true

	var residual_axis: Vector3 = next_up.cross(align_normal)
	var residual_angle: float = acos(clamp(next_up.dot(align_normal), -1.0, 1.0))
	if residual_angle > 0.0001 and remaining_step > 0.0:
		if residual_axis.length() < 0.0001:
			residual_axis = next_forward.cross(next_up)
		if residual_axis.length() > 0.0001:
			residual_axis = residual_axis.normalized()
			var residual_step: float = min(residual_angle, remaining_step)
			var residual_rotation: Basis = Basis(residual_axis, residual_step)
			next_up = (residual_rotation * next_up).normalized()
			next_forward = (residual_rotation * next_forward).normalized()

	if next_up.dot(align_normal) > 0.999999:
		next_up = align_normal
	p.visual_up = next_up
	visual_forward = next_forward - p.visual_up * next_forward.dot(p.visual_up)
	if visual_forward.length() > 0.001:
		visual_forward = _step_air_landing_movement_yaw(
			p.visual_up,
			visual_forward.normalized(),
			delta
		)
		p._air_torque_visual_forward = visual_forward


func _update_visual_up(delta: float) -> void:
	# SUMMARY: Update visual_up with optional airborne torque carryover.
	# STEPS:
	# - Step 1: Use standard smoothing while grounded or forced-aligned.
	# - Step 2: While airborne, apply torque + delayed re-alignment nudge.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return

	if p._rail_switch_active and p._rail_model_basis_valid:
		p.visual_up = p._rail_model_basis.y
		return

	var world_up: Vector3 = _get_owner_gravity_up()

	var target: Vector3 = p.up_direction
	if target.length() < 0.001:
		target = world_up
	target = target.normalized()

	var trajectory_torque_active: bool = p.is_airborne_trajectory_torque_active()
	if trajectory_torque_active and _should_end_trajectory_torque_for_low_horizontal_speed():
		p._cancel_spring_trajectory_torque(false)
		trajectory_torque_active = false
	var forced_align: bool = (
		(p._spring_align_timer > 0.0 and not trajectory_torque_active and not p._external_airborne_torque_active)
		or (p._spline_active and not p._external_airborne_torque_active)
		or p._rail_active
		or p._bounce_state != p.BounceState.NONE
		or p.is_action_id_active(&"skydive")
	)

	if forced_align:
		if p._spring_trajectory_torque_active:
			p._cancel_spring_trajectory_torque(false)
		p._reset_air_torque_airborne_state(false)
		p._air_torque_segment_allowed = false
		_step_visual_up_toward(target, p.visual_up_lerp_speed_deg, delta)
		return

	if p.attached:
		p._reset_air_torque_airborne_state(true)
		_step_visual_up_toward(target, p.visual_up_lerp_speed_deg, delta)
		return
	if trajectory_torque_active:
		if p._manual_airborne_torque_active or p._air_landing_align_active:
			p._cancel_spring_trajectory_torque(false)
		else:
			var trajectory_up: Vector3 = p.get_airborne_trajectory_up()
			if trajectory_up.length() > 0.001:
				p._air_torque_airborne_time += delta
				_step_air_torque_frame_toward(
					trajectory_up,
					p._spring_trajectory_torque_align_speed_deg,
					delta
				)
			return


	var torque_active: bool = p.airborne_torque_enabled and p._air_torque_segment_allowed

	if p.visual_up.length() < 0.001:
		p.visual_up = target
		return

	p.visual_up = p.visual_up.normalized()
	p._air_torque_airborne_time += delta

	var omega_raw: Vector3 = p._air_torque_angular_velocity
	if torque_active and not p._air_landing_align_active:
		var torque_gain: float = max(p.airborne_torque_gain, 0.0)
		var omega: Vector3 = omega_raw * torque_gain
		var omega_len: float = omega.length()
		if omega_len > 0.0001:
			var axis_torque: Vector3 = omega / omega_len
			var angle_step: float = omega_len * delta
			if angle_step > 0.0:
				var rot_torque: Basis = Basis(axis_torque, angle_step)
				p.visual_up = (rot_torque * p.visual_up).normalized()
				# Keep the cached visual forward rotating with torque for stable yaw suppression.
				var vis_fwd: Vector3 = p._air_torque_visual_forward
				if vis_fwd.length() > 0.0001:
					vis_fwd = (rot_torque * vis_fwd).normalized()
					vis_fwd = vis_fwd - p.visual_up * vis_fwd.dot(p.visual_up)
					if vis_fwd.length() > 0.0001:
						p._air_torque_visual_forward = vis_fwd.normalized()
				
				# Track cumulative rotation for trick rewards.
				if p.get("trick_rotation_gauge_bonus") > 0.0:
					# Track rotation around current local axes.
					var local_omega: Vector3 = p.model_root.global_transform.basis.inverse() * omega
					var step_v: Vector3 = local_omega.abs() * delta
					var old_accum: Vector3 = p._air_torque_rotation_accum
					p._air_torque_rotation_accum += step_v
					
					var bonus: float = p.trick_rotation_gauge_bonus
					var thresh: float = TAU # 360 degrees
					
					var rewards: int = 0
					if floor(p._air_torque_rotation_accum.x / thresh) > floor(old_accum.x / thresh): rewards += 1
					if floor(p._air_torque_rotation_accum.y / thresh) > floor(old_accum.y / thresh): rewards += 1
					if floor(p._air_torque_rotation_accum.z / thresh) > floor(old_accum.z / thresh): rewards += 1
					
					if rewards > 0 and not p.is_spindash_overcharge_blocking_external_barrier_blast_gain():
						var combo_gain_multiplier: float = p.get_combo_barrier_blast_gain_multiplier()
						p._barrier_blast_gauge = clamp(
							p._barrier_blast_gauge + bonus * float(rewards) * combo_gain_multiplier,
							0.0,
							1.0
						)

	_step_air_landing_alignment(delta)

	if p._air_landing_align_active:
		p._air_torque_angular_velocity = Vector3.ZERO
		p._external_airborne_torque_active = false
	elif torque_active:
		var decay_speed: float = max(p.airborne_torque_decay_speed, 0.0)
		if p.get("_manual_airborne_torque_fast_decay"):
			decay_speed = max(p.manual_airborne_torque_fast_decay_speed, decay_speed)
		if decay_speed > 0.0 and not p.get("_manual_airborne_torque_suppress_decay"):
			var t_decay: float = clamp(decay_speed * delta, 0.0, 1.0)
			p._air_torque_angular_velocity = omega_raw.lerp(Vector3.ZERO, t_decay)
			if p._air_torque_angular_velocity.length() < 0.01:
				p._manual_airborne_torque_fast_decay = false
				p._external_airborne_torque_active = false
	if p._air_landing_align_active:
		return

	var delay: float = max(p.airborne_up_blend_delay, 0.0)
	if p._air_torque_airborne_time <= delay:
		return

	var ramp_speed: float = max(p.airborne_up_blend_ramp_speed, 0.0)
	var ramp_t: float = 1.0
	if ramp_speed > 0.0:
		ramp_t = clamp((p._air_torque_airborne_time - delay) * ramp_speed, 0.0, 1.0)

	var align_speed: float = max(p.airborne_up_blend_speed, 0.0)
	if align_speed <= 0.0 or p.get("_manual_airborne_torque_active") or p.get("_external_airborne_torque_active"):
		return

	var axis_to_up: Vector3 = p.visual_up.cross(world_up)
	var axis_len: float = axis_to_up.length()
	if axis_len < 0.0001:
		return

	var dot_up: float = clamp(p.visual_up.dot(world_up), -1.0, 1.0)
	var angle_to_up: float = acos(dot_up)
	if angle_to_up < 0.0001:
		return

	var max_step: float = deg_to_rad(align_speed) * delta * ramp_t
	if max_step <= 0.0:
		return

	var step: float = min(max_step, angle_to_up)
	axis_to_up /= axis_len
	var rot_to_up: Basis = Basis(axis_to_up, step)
	p.visual_up = (rot_to_up * p.visual_up).normalized()


func _get_air_turn_axis_step(angle_rad: float, speed: float, delta: float, ramp_t: float) -> float:
	# SUMMARY: Return the incremental rotation for a single air-turn axis.
	# STEPS:
	# - Step 1: Apply the ramp factor (0 = hold, 1 = full).
	# - Step 2: Snap on this axis when speed <= 0.
	# - Step 3: Scale the angle by the lerp factor.
	var ramp_used: float = clamp(ramp_t, 0.0, 1.0)
	if ramp_used <= 0.0:
		return 0.0
	var speed_used: float = max(speed, 0.0)
	if speed_used <= 0.0:
		return angle_rad * ramp_used
	if delta <= 0.0:
		return 0.0
	var t: float = clamp(speed_used * delta, 0.0, 1.0)
	return angle_rad * t * ramp_used


func _get_air_turn_ramp_t(air_time: float, delay: float, ramp_speed: float) -> float:
	# SUMMARY: Return a 0..1 ramp factor for airborne turn speeds.
	var delay_used: float = max(delay, 0.0)
	if air_time <= delay_used:
		return 0.0
	var ramp_speed_used: float = max(ramp_speed, 0.0)
	if ramp_speed_used <= 0.0:
		return 1.0
	return clamp((air_time - delay_used) * ramp_speed_used, 0.0, 1.0)


func _apply_air_turn_axis_smoothing(
	current_basis: Basis,
	target_basis: Basis,
	delta: float,
	yaw_speed: float,
	pitch_speed: float,
	roll_speed: float,
	yaw_ramp: float,
	pitch_ramp: float,
	roll_ramp: float
) -> Basis:
	# SUMMARY: Apply swing (up alignment) + twist (yaw) smoothing without Euler gimbal issues.
	# STEPS:
	# - Step 1: Swing current up toward target up.
	# - Step 2: Twist around the new up axis to align forward.
	# NOTES:
	# - Pitch/Roll speeds are combined for the swing step.
	# - Yaw speed applies to the twist around the up axis.
	var current_up: Vector3 = current_basis.y.normalized()
	if current_up.length() < 0.001:
		current_up = _get_owner_gravity_up()

	var target_up: Vector3 = target_basis.y.normalized()
	if target_up.length() < 0.001:
		target_up = _get_owner_gravity_up()

	var axis: Vector3 = current_up.cross(target_up)
	var axis_len: float = axis.length()
	var basis_step: Basis = current_basis
	if axis_len > 0.0001:
		axis /= axis_len
		var dot_up: float = clamp(current_up.dot(target_up), -1.0, 1.0)
		var angle_up: float = acos(dot_up)
		var pitch_ramp_used: float = clamp(pitch_ramp, 0.0, 1.0)
		var roll_ramp_used: float = clamp(roll_ramp, 0.0, 1.0)
		var swing_ramp: float = min(pitch_ramp_used, roll_ramp_used)
		var swing_speed: float = max(max(pitch_speed, roll_speed), 0.0)
		var swing_step: float = _get_air_turn_axis_step(angle_up, swing_speed, delta, swing_ramp)
		if abs(swing_step) > 0.000001:
			var swing_basis: Basis = Basis(axis, swing_step)
			basis_step = swing_basis * current_basis

	var new_up: Vector3 = basis_step.y.normalized()
	if new_up.length() < 0.001:
		new_up = target_up

	var cur_f: Vector3 = -basis_step.z
	var tgt_f: Vector3 = -target_basis.z
	cur_f = cur_f - new_up * cur_f.dot(new_up)
	tgt_f = tgt_f - new_up * tgt_f.dot(new_up)
	if cur_f.length() < 0.0001 or tgt_f.length() < 0.0001:
		return basis_step

	cur_f = cur_f.normalized()
	tgt_f = tgt_f.normalized()
	var dot_f: float = clamp(cur_f.dot(tgt_f), -1.0, 1.0)
	var angle_f: float = acos(dot_f)
	var cross_f: Vector3 = cur_f.cross(tgt_f)
	if cross_f.dot(new_up) < 0.0:
		angle_f = -angle_f

	var yaw_step: float = _get_air_turn_axis_step(angle_f, yaw_speed, delta, yaw_ramp)
	if abs(yaw_step) <= 0.000001:
		return basis_step

	var yaw_basis: Basis = Basis(new_up, yaw_step)
	return yaw_basis * basis_step


func _update_model_orientation(delta: float) -> void:
	# SUMMARY: Orient the model root to match movement and surface direction.
	# STEPS:
	# - Step 1: Choose up and forward sources based on state.
	# - Step 2: Build the target basis.
	# - Step 3: Snap on landings or smooth-turn toward the target.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.model_root == null:
		return

	if p._active_action != null and p._active_action.apply_visual_orientation():
		return
	if (p._rail_active or p._rail_switch_active) and p._rail_align_model and p._rail_model_basis_valid:
		p._clear_drift_visual_influence()
		var t: Transform3D = p.model_root.global_transform
		var target_basis: Basis = p._rail_model_basis
		if p._rail_switch_active:
			t.basis = target_basis
		elif not p.attached:
			var air_time: float = max(p._airborne_time, 0.0)
			var yaw_ramp: float = _get_air_turn_ramp_t(
				air_time,
				p.model_turn_speed_air_yaw_delay,
				p.model_turn_speed_air_yaw_ramp_speed
			)
			var pitch_ramp: float = _get_air_turn_ramp_t(
				air_time,
				p.model_turn_speed_air_pitch_delay,
				p.model_turn_speed_air_pitch_ramp_speed
			)
			var roll_ramp: float = _get_air_turn_ramp_t(
				air_time,
				p.model_turn_speed_air_roll_delay,
				p.model_turn_speed_air_roll_ramp_speed
			)
			t.basis = _apply_air_turn_axis_smoothing(
				t.basis,
				target_basis,
				delta,
				p.model_turn_speed_air_yaw,
				p.model_turn_speed_air_pitch,
				p.model_turn_speed_air_roll,
				yaw_ramp,
				pitch_ramp,
				roll_ramp
			)
		else:
			if p.model_turn_speed <= 0.0:
				t.basis = target_basis
			else:
				var current_q: Quaternion = t.basis.get_rotation_quaternion()
				var target_q: Quaternion = target_basis.get_rotation_quaternion()
				var new_q: Quaternion = current_q.slerp(target_q, p.model_turn_speed * delta)
				t.basis = Basis(new_q)
		p.model_root.global_transform = t
		p._model_forward = -t.basis.z
		return

	var trajectory_torque_active: bool = p.is_airborne_trajectory_torque_active()
	var in_spring_align: bool = (
		p._spring_align_timer > 0.0
		and p._spring_align_dir.length() > 0.001
		and p._spring_align_model
		and not trajectory_torque_active
	)

	var up: Vector3
	var forward_src: Vector3
	var spindash_input_facing: bool = p._spindash_charging

	if in_spring_align:
		up = p._spring_align_dir.normalized()
		var v: Vector3 = p.velocity
		var v_tangent: Vector3 = v - up * v.dot(up)
		if v_tangent.length() > 0.05:
			forward_src = v_tangent.normalized()
		else:
			var cf: Vector3 = p._control_forward - up * p._control_forward.dot(up)
			if cf.length() > 0.001:
				forward_src = cf.normalized()
			else:
				forward_src = -Vector3.FORWARD
	else:
		up = p.visual_up.normalized()
		if up.length() < 0.001:
			up = _get_owner_gravity_up()

		if spindash_input_facing:
			up = p._physics_up_last.normalized()
			if p.attached and p.surface_normal.length() > 0.001:
				up = p.surface_normal.normalized()
			if up.length() < 0.001:
				up = _get_owner_gravity_up()
		var use_input_facing: bool = spindash_input_facing or (p.race_in_countdown and not p.race_active)
		var has_input_facing_direction: bool = p._move_direction.length() > 0.001
		if spindash_input_facing and p._spindash_latched_direction.length() > 0.001:
			has_input_facing_direction = true
		if p._is_dead:
			p._model_forward = p._model_forward - up * p._model_forward.dot(up)
			if p._model_forward.length() > 0.001:
				p._model_forward = p._model_forward.normalized()
			else:
				p._model_forward = (-Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up)).normalized()
			forward_src = p._model_forward
		elif use_input_facing and has_input_facing_direction:
			var input_up: Vector3 = up
			if spindash_input_facing:
				input_up = p._physics_up_last.normalized()
				if p.attached and p.surface_normal.length() > 0.001:
					input_up = p.surface_normal.normalized()
				if input_up.length() < 0.001:
					input_up = _get_owner_gravity_up()
			var input_dir: Vector3 = p._move_direction
			if spindash_input_facing and p._spindash_latched_direction.length() > 0.001:
				input_dir = p._spindash_latched_direction
			input_dir -= input_up * input_dir.dot(input_up)
			if input_dir.length() > 0.001:
				forward_src = input_dir.normalized()
				p._model_forward = forward_src
			else:
				forward_src = p._model_forward
		else:
			var move_dir: Vector3 = p.velocity - up * p.velocity.dot(up)
			var min_turn_speed: float = max(p.model_turn_min_speed, 0.0)
			if move_dir.length() > min_turn_speed:
				forward_src = move_dir.normalized()
				p._model_forward = forward_src
			else:
				p._model_forward = p._model_forward - up * p._model_forward.dot(up)
				if p._model_forward.length() > 0.001:
					p._model_forward = p._model_forward.normalized()
				else:
					p._model_forward = (-Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up)).normalized()
				forward_src = p._model_forward

	# Gameplay-facing forward stays driven by movement/input.
	var gameplay_forward: Vector3 = forward_src - up * forward_src.dot(up)
	if gameplay_forward.length() < 0.001:
		gameplay_forward = -Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up)
	if gameplay_forward.length() < 0.001:
		gameplay_forward = -Vector3.FORWARD
	gameplay_forward = gameplay_forward.normalized()
	p._model_forward = gameplay_forward

	# Visual-facing forward can pause yaw correction while airborne torque is active.
	var visual_forward: Vector3 = gameplay_forward
	var torque_active: bool = p.airborne_torque_enabled and p._air_torque_segment_allowed
	var external_torque_active: bool = bool(p.get("_external_airborne_torque_active"))
	var manual_active: bool = bool(p.get("_manual_airborne_torque_active")) or external_torque_active
	var torque_visual_speed: float = (
		p._air_torque_angular_velocity.length()
		* max(p.airborne_torque_gain, 0.0)
	)
	var free_torque_rotating: bool = torque_active and torque_visual_speed > 0.01
	
	if not p.attached and (torque_active or p._air_landing_align_active):
		var delay: float = max(p.airborne_facing_resume_delay, 0.0)
		var yaw_blend: float = 1.0
		
		if manual_active or trajectory_torque_active or free_torque_rotating or p._air_landing_align_active:
			# Torque-controlled frames preserve their visual facing.
			yaw_blend = 0.0
		elif p._air_torque_airborne_time <= delay:
			yaw_blend = 0.0
		else:
			var ramp_speed: float = max(p.airborne_facing_resume_ramp_speed, 0.0)
			if ramp_speed <= 0.0:
				yaw_blend = 1.0
			else:
				yaw_blend = clamp(
					(p._air_torque_airborne_time - delay) * ramp_speed,
					0.0,
					1.0
				)

		if yaw_blend < 1.0:
			var yaw_ref: Vector3 = p._air_torque_visual_forward
			if yaw_ref.length() < 0.001:
				yaw_ref = p._air_torque_yaw_forward
			if yaw_ref.length() < 0.001:
				yaw_ref = -p.model_root.global_transform.basis.z
			var yaw_plane: Vector3 = yaw_ref - up * yaw_ref.dot(up)
			if yaw_plane.length() < 0.001:
				var current_forward: Vector3 = -p.model_root.global_transform.basis.z
				yaw_plane = current_forward - up * current_forward.dot(up)
			if yaw_plane.length() > 0.001:
				yaw_plane = yaw_plane.normalized()
				visual_forward = yaw_plane.slerp(gameplay_forward, yaw_blend)
	if not p.attached and not manual_active and not trajectory_torque_active and not p._air_landing_align_active:
		var cached_forward: Vector3 = visual_forward - up * visual_forward.dot(up)
		if cached_forward.length() > 0.001:
			p._air_torque_visual_forward = cached_forward.normalized()

	var right: Vector3 = visual_forward.cross(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()

	var forward: Vector3 = up.cross(right).normalized()
	var target_basis: Basis = Basis(right, up, -forward)
	p._update_drift_visual_influence(delta)
	var drift_visual_angles: Vector3 = p._get_drift_visual_angles_deg()
	if not trajectory_torque_active and not external_torque_active and not p._air_landing_align_active and drift_visual_angles.length_squared() > 0.000001:
		var pitch_rad: float = deg_to_rad(drift_visual_angles.x)
		var yaw_rad: float = deg_to_rad(drift_visual_angles.y)
		var roll_rad: float = deg_to_rad(drift_visual_angles.z)
		if abs(pitch_rad) > 0.000001:
			target_basis = Basis(target_basis.x.normalized(), pitch_rad) * target_basis
		if abs(yaw_rad) > 0.000001:
			target_basis = Basis(target_basis.y.normalized(), yaw_rad) * target_basis
		if abs(roll_rad) > 0.000001:
			target_basis = Basis((-target_basis.z).normalized(), roll_rad) * target_basis

	var t: Transform3D = p.model_root.global_transform
	if trajectory_torque_active:
		t.basis = target_basis
		p.model_root.global_transform = t
		p._model_forward = -t.basis.z
		return
	if external_torque_active and not p._air_landing_align_active:
		t.basis = target_basis
		p.model_root.global_transform = t
		p._model_forward = gameplay_forward
		return
	# Snap immediately to spring direction for a short window.
	if in_spring_align and p._spring_model_snap_timer > 0.0:
		t.basis = target_basis
		p.model_root.global_transform = t
		p._model_forward = -t.basis.z
		return
	if spindash_input_facing:
		t.basis = target_basis
		p.model_root.global_transform = t
		p._model_forward = -t.basis.z
		return
	if p.attached and not p._prev_attached:
		t.basis = target_basis
		p.model_root.global_transform = t
		return

	if not p.attached:
		var air_time: float = max(p._airborne_time, 0.0)
		var yaw_ramp: float = _get_air_turn_ramp_t(
			air_time,
			p.model_turn_speed_air_yaw_delay,
			p.model_turn_speed_air_yaw_ramp_speed
		)
		var pitch_ramp: float = _get_air_turn_ramp_t(
			air_time,
			p.model_turn_speed_air_pitch_delay,
			p.model_turn_speed_air_pitch_ramp_speed
		)
		var roll_ramp: float = _get_air_turn_ramp_t(
			air_time,
			p.model_turn_speed_air_roll_delay,
			p.model_turn_speed_air_roll_ramp_speed
		)
		t.basis = _apply_air_turn_axis_smoothing(
			t.basis,
			target_basis,
			delta,
			p.model_turn_speed_air_yaw,
			p.model_turn_speed_air_pitch,
			p.model_turn_speed_air_roll,
			yaw_ramp,
			pitch_ramp,
			roll_ramp
		)
	else:
		if p.model_turn_speed <= 0.0:
			t.basis = target_basis
		else:
			var current_q: Quaternion = t.basis.get_rotation_quaternion()
			var target_q: Quaternion = target_basis.get_rotation_quaternion()
			var new_q: Quaternion = current_q.slerp(target_q, p.model_turn_speed * delta)
			t.basis = Basis(new_q)
	p.model_root.global_transform = t


func snap_model_to_normal(normal: Vector3, forward_hint: Vector3 = Vector3.FORWARD) -> void:
	# SUMMARY: Snap the model basis to a given normal and forward hint.
	# STEPS:
	# - Step 1: Normalize inputs and build a stable right vector.
	# - Step 2: Apply the basis to the model root.
	# - Step 3: Keep visual_up and _model_forward consistent.
	var p
	p = _owner
	if p == null or not is_instance_valid(p):
		return
	if p.model_root == null:
		return

	var up: Vector3 = normal.normalized()
	if up.length() < 0.001:
		up = _get_owner_gravity_up()

	var f: Vector3 = forward_hint - up * forward_hint.dot(up)
	if f.length() < 0.001:
		if p._model_forward.length() > 0.001:
			f = p._model_forward - up * p._model_forward.dot(up)
		else:
			f = -Vector3.FORWARD - up * (-Vector3.FORWARD).dot(up)
	if f.length() < 0.001:
		f = Vector3.FORWARD
	else:
		f = f.normalized()

	var right: Vector3 = f.cross(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()

	var forward: Vector3 = up.cross(right).normalized()

	var basis: Basis = Basis(right, up, -forward)
	var t: Transform3D = p.model_root.global_transform
	t.basis = basis
	p.model_root.global_transform = t

	p.visual_up = up
	p._model_forward = forward

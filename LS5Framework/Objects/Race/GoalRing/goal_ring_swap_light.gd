@tool

extends Node3D

# Syncs an optional Light3D with the goal ring shader's flat/glow swap timing.
# This keeps the light energy in-phase with the shader's texture swap.

@export_group("Label")
## Normal GOAL label texture used by Classic Race.
@export var goal_label_texture: Texture2D = preload("res://LS5Framework/Objects/Race/GoalRing/GOAL_LABEL.png")
## Glowing GOAL label texture used by Classic Race.
@export var goal_label_glow_texture: Texture2D = preload("res://LS5Framework/Objects/Race/GoalRing/GOAL_LABEL_GLOW.png")
## Normal BACK label texture used by objective race types.
@export var back_label_texture: Texture2D = preload("res://LS5Framework/Objects/Race/GoalRing/BACK_LABEL.png")
## Glowing BACK label texture used by objective race types.
@export var back_label_glow_texture: Texture2D = preload("res://LS5Framework/Objects/Race/GoalRing/BACK_LABEL_GLOW.png")

@export_group("Swap Light")
@export var swap_light_enabled: bool = false
@export var swap_light_path: NodePath = NodePath("SwapLight")
@export var flat_light_energy: float = 0.0
@export var glow_light_energy: float = 6.0

@export_group("Swap Timing")
# Fallback interval if no shader parameter is found.
@export var swap_interval: float = 1.0
# Mesh path used to read the swap_interval parameter.
@export var swap_material_path: NodePath = NodePath("Armature/Skeleton3D/Circle")
# When enabled, drives the shader's swap_time so the editor preview stays in sync.
@export var drive_shader_time: bool = true

var _swap_light: Light3D = null
var _swap_material: ShaderMaterial = null
var _swap_interval: float = 1.0
var _last_glow_state: bool = false
# Tracks first sync after the light is enabled or reloaded.
var _light_initialized: bool = false
var _back_label_enabled: bool = false
var _effects_active: bool = true


func _enter_tree() -> void:
	# Ensure editor previews process even when the main game loop is not running.
	if Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(true)


func _ready() -> void:
	_swap_light = _resolve_swap_light()
	_swap_material = _resolve_swap_material()
	_localize_swap_material()
	_swap_interval = _resolve_swap_interval(_swap_material)
	_apply_label_textures()
	_light_initialized = false

	# Force processing on so swap timing updates are reliable.
	set_process(true)
	_sync_light_state(true)


func _exit_tree() -> void:
	_cleanup_light_state()


func set_goal_effects_active(active: bool) -> void:
	_effects_active = active
	if not active:
		_cleanup_light_state()
		set_process(false)
		return
	set_process(true)
	_sync_light_state(true)


func set_back_label_enabled(enabled: bool) -> void:
	_back_label_enabled = enabled
	_apply_label_textures()


func _apply_label_textures() -> void:
	if _swap_material == null or not is_instance_valid(_swap_material):
		_swap_material = _resolve_swap_material()
	if _swap_material == null:
		return
	var normal_texture: Texture2D = back_label_texture if _back_label_enabled else goal_label_texture
	var glow_texture: Texture2D = back_label_glow_texture if _back_label_enabled else goal_label_glow_texture
	if normal_texture != null:
		_swap_material.set_shader_parameter("tex_flat", normal_texture)
	if glow_texture != null:
		_swap_material.set_shader_parameter("tex_glow", glow_texture)


func _localize_swap_material() -> void:
	if _swap_material == null:
		return
	var local_material: ShaderMaterial = _swap_material.duplicate() as ShaderMaterial
	if local_material == null:
		return
	var mesh: MeshInstance3D = get_node_or_null(swap_material_path) as MeshInstance3D
	if mesh == null:
		return
	mesh.material_override = local_material
	_swap_material = local_material


func _process(_delta: float) -> void:
	_sync_light_state(false)


func _get_time_seconds() -> float:
	# Uses engine time so the light swap matches the shader TIME uniform.
	var ms: int = Time.get_ticks_msec()
	return float(ms) * 0.001


func _is_glow_phase(time_seconds: float) -> bool:
	var safe_interval: float = _swap_interval
	if safe_interval < 0.01:
		safe_interval = 0.01

	var phase: float = floor(time_seconds / safe_interval)
	var phase_index: int = int(phase) % 2
	if phase_index == 1:
		return true
	return false


func _apply_light_energy(glow_state: bool) -> void:
	if _swap_light == null:
		return

	if glow_state:
		_swap_light.light_energy = glow_light_energy
	else:
		_swap_light.light_energy = flat_light_energy


func _sync_light_state(force_update: bool) -> void:
	# Handles enable/disable logic and applies energy only when needed.
	if not _effects_active or not swap_light_enabled:
		_cleanup_light_state()
		return
	if _swap_light == null or not is_instance_valid(_swap_light):
		_light_initialized = false
		return
	_swap_light.visible = true

	var time_seconds: float = _get_time_seconds()
	_apply_shader_time(time_seconds)
	var glow_state: bool = _is_glow_phase(time_seconds)
	if not _light_initialized or force_update:
		_last_glow_state = glow_state
		_apply_light_energy(glow_state)
		_light_initialized = true
		return

	if glow_state == _last_glow_state:
		return

	_last_glow_state = glow_state
	_apply_light_energy(glow_state)


func _cleanup_light_state() -> void:
	_light_initialized = false
	if _swap_light != null and is_instance_valid(_swap_light):
		_swap_light.light_energy = 0.0
		_swap_light.visible = false


func _resolve_swap_light() -> Light3D:
	if swap_light_path == NodePath(""):
		return null

	var node := get_node_or_null(swap_light_path)
	if node is Light3D:
		return node as Light3D
	return null


func _resolve_swap_interval(material: ShaderMaterial = null) -> float:
	var interval: float = swap_interval
	if material != null:
		var param = material.get_shader_parameter("swap_interval")
		if param is float:
			interval = float(param)
		elif param is int:
			interval = float(param)

	if interval < 0.01:
		interval = 0.01
	return interval


func _resolve_swap_material() -> ShaderMaterial:
	if swap_material_path != NodePath(""):
		var node := get_node_or_null(swap_material_path)
		if node is MeshInstance3D:
			var mesh := node as MeshInstance3D
			var override_material := mesh.material_override
			if override_material is ShaderMaterial:
				return override_material as ShaderMaterial
			var active_material = mesh.get_active_material(0)
			if active_material is ShaderMaterial:
				return active_material as ShaderMaterial

	# Fallback for renamed mesh paths or alternate imports.
	var meshes: Array = find_children("*", "MeshInstance3D", true, false)
	for mesh_node in meshes:
		var mesh := mesh_node as MeshInstance3D
		if mesh == null:
			continue
		var override_material := mesh.material_override
		if override_material is ShaderMaterial:
			var mat := override_material as ShaderMaterial
			if _has_swap_interval(mat):
				return mat
		var active_material = mesh.get_active_material(0)
		if active_material is ShaderMaterial:
			var mat2 := active_material as ShaderMaterial
			if _has_swap_interval(mat2):
				return mat2

	return null


func _has_swap_interval(material: ShaderMaterial) -> bool:
	var param = material.get_shader_parameter("swap_interval")
	if param is float:
		return true
	if param is int:
		return true
	return false


func _has_swap_time(material: ShaderMaterial) -> bool:
	var param = material.get_shader_parameter("swap_time")
	if param is float:
		return true
	if param is int:
		return true
	return false


func _apply_shader_time(time_seconds: float) -> void:
	if not drive_shader_time:
		return

	if _swap_material == null:
		_swap_material = _resolve_swap_material()
		if _swap_material != null:
			_swap_interval = _resolve_swap_interval(_swap_material)

	if _swap_material == null:
		return
	if not _has_swap_time(_swap_material):
		return

	_swap_material.set_shader_parameter("swap_time", time_seconds)

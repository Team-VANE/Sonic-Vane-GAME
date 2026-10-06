extends Node
class_name EmissionBlink

@export_group("Targets")
## Primary MeshInstance3D whose material receives the emission pulse.
@export_node_path("MeshInstance3D") var target_node_path: NodePath
## Additional MeshInstance3D nodes that share the same emission pulse.
@export var target_paths: Array[NodePath] = []
## Surface on the primary target to animate. A value of -1 animates every compatible surface.
@export_range(-1, 255, 1) var surface_index: int = -1
## Per-target surface indices for Additional Targets. Missing entries use -1.
@export var surface_indices: Array[int] = []

@export_group("Blink")
## Enables the emission pulse.
@export var active: bool = true
## Color used by the animated emission.
@export var emission_color: Color = Color(1.0, 0.0, 0.0, 1.0)
## Emission energy at the darkest point of the pulse.
@export_range(0.0, 64.0, 0.05, "or_greater") var minimum_emission_energy: float = 0.0
## Emission energy at the brightest point of the pulse.
@export_range(0.0, 64.0, 0.05, "or_greater") var maximum_emission_energy: float = 8.0
## Duration of one complete dark-to-bright-to-dark pulse.
@export_range(0.01, 60.0, 0.01, "or_greater", "suffix:s") var cycle_duration: float = 1.5
## Starting position within the pulse cycle.
@export_range(0.0, 1.0, 0.01) var start_phase: float = 0.0

var _materials: Array[BaseMaterial3D] = []
var _elapsed: float = 0.0
var _was_active: bool = false


func _ready() -> void:
	_refresh_targets()
	var duration: float = max(cycle_duration, 0.01)
	_elapsed = fposmod(start_phase, 1.0) * duration
	_was_active = active
	if active:
		_apply_current_pulse()
	else:
		_apply_emission_energy(max(minimum_emission_energy, 0.0))
	set_process(not _materials.is_empty())


func _process(delta: float) -> void:
	if not active:
		if _was_active:
			_apply_emission_energy(max(minimum_emission_energy, 0.0))
		_was_active = false
		return
	_was_active = true
	var duration: float = max(cycle_duration, 0.01)
	_elapsed = fposmod(_elapsed + delta, duration)
	_apply_current_pulse()


func set_blink_enabled(enabled: bool) -> void:
	active = enabled
	if active:
		set_process(not _materials.is_empty())
		return
	_apply_emission_energy(max(minimum_emission_energy, 0.0))


func refresh_targets() -> void:
	_refresh_targets()
	if active:
		_apply_current_pulse()
	else:
		_apply_emission_energy(max(minimum_emission_energy, 0.0))
	set_process(not _materials.is_empty())


func _refresh_targets() -> void:
	_materials.clear()
	var paths: Array[NodePath] = _collect_target_paths()
	for index in range(paths.size()):
		var mesh_instance: MeshInstance3D = get_node_or_null(paths[index]) as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh:
			continue
		_add_target_materials(mesh_instance, _get_surface_index(index))


func _collect_target_paths() -> Array[NodePath]:
	var paths: Array[NodePath] = []
	if target_node_path != NodePath(""):
		paths.append(target_node_path)
	for path in target_paths:
		if path != NodePath(""):
			paths.append(path)
	return paths


func _add_target_materials(mesh_instance: MeshInstance3D, target_surface: int) -> void:
	if mesh_instance.material_override is BaseMaterial3D:
		var override_material: BaseMaterial3D = _duplicate_material(
			mesh_instance.material_override as BaseMaterial3D
		)
		if override_material:
			mesh_instance.material_override = override_material
			_materials.append(override_material)
		return

	var surface_count: int = mesh_instance.mesh.get_surface_count()
	if target_surface >= 0:
		_add_surface_material(mesh_instance, target_surface, surface_count)
		return
	for current_surface in range(surface_count):
		_add_surface_material(mesh_instance, current_surface, surface_count)


func _add_surface_material(
	mesh_instance: MeshInstance3D,
	current_surface: int,
	surface_count: int
) -> void:
	if current_surface < 0 or current_surface >= surface_count:
		return
	var source_material: Material = mesh_instance.get_surface_override_material(current_surface)
	if not source_material:
		source_material = mesh_instance.mesh.surface_get_material(current_surface)
	if not (source_material is BaseMaterial3D):
		return
	var local_material: BaseMaterial3D = _duplicate_material(source_material as BaseMaterial3D)
	if not local_material:
		return
	mesh_instance.set_surface_override_material(current_surface, local_material)
	_materials.append(local_material)


func _duplicate_material(source_material: BaseMaterial3D) -> BaseMaterial3D:
	var local_material: BaseMaterial3D = source_material.duplicate() as BaseMaterial3D
	if not local_material:
		return null
	local_material.resource_local_to_scene = true
	local_material.emission_enabled = true
	local_material.emission = emission_color
	return local_material


func _apply_current_pulse() -> void:
	var duration: float = max(cycle_duration, 0.01)
	var cycle_progress: float = fposmod(_elapsed / duration, 1.0)
	var pulse: float = (1.0 - cos(cycle_progress * TAU)) * 0.5
	var low_energy: float = max(minimum_emission_energy, 0.0)
	var high_energy: float = max(maximum_emission_energy, low_energy)
	_apply_emission_energy(lerpf(low_energy, high_energy, pulse))


func _apply_emission_energy(energy: float) -> void:
	for material in _materials:
		if not material or not is_instance_valid(material):
			continue
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = energy


func _get_surface_index(index: int) -> int:
	if index == 0 and target_node_path != NodePath(""):
		return surface_index
	var additional_index: int = index
	if target_node_path != NodePath(""):
		additional_index -= 1
	if additional_index >= 0 and additional_index < surface_indices.size():
		return surface_indices[additional_index]
	return -1

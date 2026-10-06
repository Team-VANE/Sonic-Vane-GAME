extends Resource
class_name ObjectRespawnFeedback

## Yellow-white tint applied to compatible materials during the respawn flash.
@export var emission_color: Color = Color(1.0, 0.94, 0.62, 1.0)
## Initial emission energy of the respawn flash.
@export_range(0.0, 64.0, 0.05, "or_greater") var emission_energy: float = 8.0
## Duration of the respawn flash fade.
@export_range(0.01, 10.0, 0.01, "or_greater", "suffix:s") var fade_duration: float = 0.65

@export_group("Audio")
## Sound played when the object respawns.
@export var respawn_sound: AudioStream = preload("res://LS5Framework/Sounds/Objects/Object_Respawn.wav")
## Audio bus used by the respawn sound.
@export var sound_bus: StringName = &"SFX"
## Volume applied to the respawn sound.
@export var sound_volume_db: float = 0.0
## Pitch scale applied to the respawn sound.
@export_range(0.01, 4.0, 0.01, "or_greater") var sound_pitch_scale: float = 1.0
## Maximum audible distance of the respawn sound.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var sound_max_distance: float = 65.0


func play(target_root: Node3D) -> bool:
	if target_root == null or not is_instance_valid(target_root) or not target_root.is_inside_tree():
		return false
	var restoration_entries: Array[Dictionary] = []
	var flash_materials: Array[BaseMaterial3D] = []
	_collect_flash_materials(target_root, restoration_entries, flash_materials)
	_play_sound(target_root)
	if flash_materials.is_empty():
		return respawn_sound != null
	_apply_flash_strength(1.0, flash_materials)
	var tween: Tween = target_root.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_method(
		_apply_flash_strength.bind(flash_materials),
		1.0,
		0.0,
		max(fade_duration, 0.01)
	)
	tween.tween_callback(_restore_materials.bind(restoration_entries))
	return true


func _collect_flash_materials(
		node: Node,
		restoration_entries: Array[Dictionary],
		flash_materials: Array[BaseMaterial3D]
	) -> void:
	if node is MeshInstance3D:
		_add_mesh_flash_materials(
			node as MeshInstance3D,
			restoration_entries,
			flash_materials
		)
	for child: Node in node.get_children():
		_collect_flash_materials(child, restoration_entries, flash_materials)


func _add_mesh_flash_materials(
		mesh_instance: MeshInstance3D,
		restoration_entries: Array[Dictionary],
		flash_materials: Array[BaseMaterial3D]
	) -> void:
	if mesh_instance.mesh == null:
		return
	if mesh_instance.material_override is BaseMaterial3D:
		var original_material_override: BaseMaterial3D = mesh_instance.material_override as BaseMaterial3D
		var flash_override: BaseMaterial3D = _create_flash_material(original_material_override)
		if flash_override == null:
			return
		restoration_entries.append({
			"mesh_instance": mesh_instance,
			"surface_index": -1,
			"original_material": original_material_override,
			"flash_material": flash_override,
		})
		mesh_instance.material_override = flash_override
		flash_materials.append(flash_override)
		return
	if mesh_instance.material_override != null:
		return
	var surface_count: int = mesh_instance.mesh.get_surface_count()
	for surface_index: int in range(surface_count):
		var surface_override: Material = mesh_instance.get_surface_override_material(surface_index)
		var source_material: Material = surface_override
		if source_material == null:
			source_material = mesh_instance.mesh.surface_get_material(surface_index)
		if not (source_material is BaseMaterial3D):
			continue
		var flash_material: BaseMaterial3D = _create_flash_material(
			source_material as BaseMaterial3D
		)
		if flash_material == null:
			continue
		restoration_entries.append({
			"mesh_instance": mesh_instance,
			"surface_index": surface_index,
			"original_material": surface_override,
			"flash_material": flash_material,
		})
		mesh_instance.set_surface_override_material(surface_index, flash_material)
		flash_materials.append(flash_material)


func _create_flash_material(source_material: BaseMaterial3D) -> BaseMaterial3D:
	var flash_material: BaseMaterial3D = source_material.duplicate() as BaseMaterial3D
	if flash_material == null:
		return null
	flash_material.resource_local_to_scene = true
	flash_material.emission_enabled = true
	flash_material.emission = emission_color
	flash_material.emission_texture = null
	flash_material.emission_energy_multiplier = max(emission_energy, 0.0)
	return flash_material


func _apply_flash_strength(
		strength: float,
		flash_materials: Array[BaseMaterial3D]
	) -> void:
	var energy: float = max(emission_energy, 0.0) * clamp(strength, 0.0, 1.0)
	for material: BaseMaterial3D in flash_materials:
		if material == null or not is_instance_valid(material):
			continue
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = energy


func _restore_materials(restoration_entries: Array[Dictionary]) -> void:
	for entry: Dictionary in restoration_entries:
		var mesh_instance: MeshInstance3D = entry.get("mesh_instance") as MeshInstance3D
		var flash_material: Material = entry.get("flash_material") as Material
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		var surface_index: int = int(entry.get("surface_index", -1))
		var original_material: Material = entry.get("original_material") as Material
		if surface_index < 0:
			if mesh_instance.material_override == flash_material:
				mesh_instance.material_override = original_material
			continue
		if mesh_instance.get_surface_override_material(surface_index) == flash_material:
			mesh_instance.set_surface_override_material(surface_index, original_material)


func _play_sound(target_root: Node3D) -> void:
	if respawn_sound == null:
		return
	var audio_player := AudioStreamPlayer3D.new()
	audio_player.stream = respawn_sound
	audio_player.bus = sound_bus
	audio_player.volume_db = sound_volume_db
	audio_player.pitch_scale = max(sound_pitch_scale, 0.01)
	audio_player.max_distance = max(sound_max_distance, 0.0)
	target_root.add_child(audio_player)
	audio_player.finished.connect(Callable(audio_player, "queue_free"))
	audio_player.play()

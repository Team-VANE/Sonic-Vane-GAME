extends Node3D

@export var flat_texture: Texture2D = preload("res://LS5Framework/Objects/Race/GoalRing/textures/GOAL_Flat.png")
@export var glowing_texture: Texture2D = preload("res://LS5Framework/Objects/Race/GoalRing/textures/GOAL_Glowing.png")
@export var swap_interval: float = 1.0
@export var use_emission: bool = true
@export var apply_recursive: bool = true

var _material: ShaderMaterial


func _ready() -> void:
	_apply_swap_material()


func _apply_swap_material() -> void:
	var shader = load("res://LS5Framework/Objects/Race/GoalRing/goal_ring_swap.gshader")
	if shader == null:
		return

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("tex_flat", flat_texture)
	_material.set_shader_parameter("tex_glow", glowing_texture)
	_material.set_shader_parameter("swap_interval", max(swap_interval, 0.01))
	_material.set_shader_parameter("use_emission", use_emission)

	var meshes: Array = []
	if apply_recursive:
		meshes = find_children("*", "MeshInstance3D", true, false)
	else:
		var root: Node = self
		if root is MeshInstance3D:
			meshes = [root]

	for m in meshes:
		var mesh := m as MeshInstance3D
		if mesh != null:
			mesh.material_override = _material

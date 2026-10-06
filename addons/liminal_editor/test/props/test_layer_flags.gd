@tool
extends Node

@export_flags_3d_render var render_layers: int = 5
@export_flags_3d_physics var collide_layers: int = 2


func _export_entity_props() -> Array:
	return [{"name": "render_layers"}, {"name": "collide_layers"}]

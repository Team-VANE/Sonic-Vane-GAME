extends EnemyAnimationDriver

## UV travel per unit of signed movement along the tank's forward axis.
@export var tread_scroll_per_unit: Vector2 = Vector2(0.0, 0.18)

var _treads: Array[StandardMaterial3D] = []
var _uv_offset: Vector2 = Vector2.ZERO
var _previous_position: Vector3


func setup(actor: CharacterBody3D) -> void:
	super.setup(actor)
	_previous_position = actor.global_position
	if not _visual_root:
		return
	for node: Node in _visual_root.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if original and original.albedo_texture and original.albedo_texture.resource_path.ends_with("RhinoTank_catarp.png"):
				var material: StandardMaterial3D = original.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, material)
				_treads.append(material)


func physics_tick(delta: float, brain_state: StringName, locomotion_state: StringName, attack_state: StringName, dead: bool, speed: float) -> void:
	var distance: float = (_actor.global_position - _previous_position).dot(-_actor.global_basis.z)
	_previous_position = _actor.global_position
	if not dead:
		_uv_offset += tread_scroll_per_unit * distance
		_uv_offset = Vector2(fposmod(_uv_offset.x, 1.0), fposmod(_uv_offset.y, 1.0))
	for material: StandardMaterial3D in _treads:
		material.uv1_offset = Vector3(_uv_offset.x, _uv_offset.y, 0.0)
	super.physics_tick(delta, brain_state, locomotion_state, attack_state, dead, speed)


func _resolve_state(brain_state: StringName, locomotion_state: StringName, _attack_state: StringName, dead: bool) -> StringName:
	if dead: return &"dead"
	if _hurt_timer > 0.0 or brain_state == &"hurt": return &"hurt"
	if brain_state == &"alert": return &"alert"
	if brain_state == &"charge": return &"attack_primary"
	return &"move" if locomotion_state == &"move" else &"idle"


func reset_driver() -> void:
	super.reset_driver()
	_previous_position = _actor.global_position
	_uv_offset = Vector2.ZERO


func notify_hurt() -> void:
	super.notify_hurt()
	_current_state = &""

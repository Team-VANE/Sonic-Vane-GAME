extends EnemyOptionalComponent

## Skeleton containing the animated burner bones, relative to the owning enemy.
@export_node_path("Skeleton3D") var skeleton_path: NodePath = NodePath("Visual/Model/Armature/Skeleton3D")
## Bone names whose local positive Y axes define burner emission direction.
@export var burner_bones: PackedStringArray = PackedStringArray(["FireParticle.L", "FireParticle.R", "FireParticle_Top"])
## Particle effect attached to each configured burner bone.
@export var particle_scene: PackedScene = preload("res://LS5Framework/Objects/Enemies/RhinoTank/BurnerParticles.tscn")
## Maximum camera distance for burner particles. Zero keeps them active at any distance.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:m") var burner_visibility_distance: float = 140.0

## Particle emitters attached to the animated skeleton.
var _emitters: Array[GPUParticles3D] = []
var _emitting: bool = false
var _distance_culled: bool = false
## Animated skeleton supplying burner poses.
var _skeleton: Skeleton3D
var _bone_indices: PackedInt32Array = []


func setup(owner_actor: CharacterBody3D) -> void:
	super.setup(owner_actor)
	set_process(false)
	var skeleton: Skeleton3D = actor.get_node_or_null(skeleton_path) as Skeleton3D
	if not skeleton or not particle_scene:
		return
	_skeleton = skeleton
	if actor._brain:
		actor._brain.state_changed.connect(_on_state_changed)
	for bone: String in burner_bones:
		var bone_index: int = skeleton.find_bone(bone)
		if bone_index < 0:
			push_warning("Missing burner bone: " + bone)
			continue
		var attachment: BoneAttachment3D = BoneAttachment3D.new()
		attachment.name = "Burner_" + bone.replace(".", "_")
		attachment.bone_name = bone
		skeleton.add_child(attachment)
		var particles: GPUParticles3D = particle_scene.instantiate() as GPUParticles3D
		if particles:
			attachment.add_child(particles)
			particles.top_level = true
			_emitters.append(particles)
			_bone_indices.append(bone_index)


func _process(_delta: float) -> void:
	if is_instance_valid(actor) and (not actor.enabled or not actor.active or actor.is_dead()):
		_set_emitting(false)
	if not _emitting or not is_instance_valid(_skeleton):
		return
	var skeleton_transform: Transform3D = _skeleton.global_transform
	var skeleton_basis: Basis = skeleton_transform.basis.orthonormalized()
	var skeleton_scale: Vector3 = skeleton_transform.basis.get_scale().abs()
	for index: int in _emitters.size():
		var bone: int = _bone_indices[index]
		var position: Vector3 = _skeleton.get_bone_global_pose(bone).origin
		var rotation: Quaternion = Quaternion.IDENTITY
		while bone >= 0:
			rotation = _skeleton.get_bone_pose_rotation(bone) * rotation
			bone = _skeleton.get_bone_parent(bone)
		var basis: Basis = (skeleton_basis * Basis(rotation)).scaled(skeleton_scale)
		_emitters[index].global_transform = Transform3D(basis, skeleton_transform * position)


func physics_tick(_delta: float) -> void:
	var permitted: bool = not _distance_culled and not _emitters.is_empty() and actor.enabled and actor.active and not actor.is_dead()
	if permitted and actor._brain:
		var state: StringName = actor._brain.get_state_tag()
		permitted = state != &"charge" and state != &"chase" and state != &"hurt"
	if permitted and burner_visibility_distance > 0.0:
		var camera: Camera3D = actor.get_viewport().get_camera_3d()
		permitted = not camera or camera.global_position.distance_squared_to(actor.global_position) <= burner_visibility_distance * burner_visibility_distance
	_set_emitting(permitted)


func set_distance_culled(value: bool) -> void:
	_distance_culled = value
	physics_tick(0.0)


func on_enemy_damaged(_amount: int, _source: Node) -> void:
	_set_emitting(false)


func on_enemy_defeated(_source: Node) -> void:
	_set_emitting(false)


func reset_component(_reason: StringName) -> void:
	_set_emitting(false)
	for particles: GPUParticles3D in _emitters:
		particles.restart()
		particles.emitting = false


func _on_state_changed(_state: StringName) -> void:
	physics_tick(0.0)


func _set_emitting(value: bool) -> void:
	if value == _emitting:
		return
	_emitting = value
	set_process(value)
	if value and _skeleton and _skeleton.is_inside_tree():
		_process(0.0)
	for particles: GPUParticles3D in _emitters:
		if not value:
			particles.restart()
		particles.emitting = value

@tool
extends Area3D

const SIZE_BASE_POSITION_META: StringName = &"_uniform_size_base_position"
const SIZE_BASE_SCALE_META: StringName = &"_uniform_size_base_scale"

@export_group("Ramp")
@export var active: bool = true
## Uniform scale applied to the ramp mesh and trigger collision.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = max(value, 0.01)
		if is_node_ready():
			_apply_size_preview()
## Additional collision mask for dynamic physics objects that can be launched by this ramp.
@export_flags_3d_physics var dynamic_object_collision_mask: int = 2
@export var rehit_cooldown: float = 0.15

var _body_cooldowns: Dictionary = {}

@export_group("Impulse")
@export var forward_speed: float = 60.0
@export var up_speed: float = 18.0

@export_group("Additive Launch")
## If enabled, keeps only the current speed along the ramp direction and adds forward_speed.
@export var additive_launch: bool = false
## Optional minimum forward speed when using additive launch (0 = disable).
@export var additive_min_forward_speed: float = 0.0

@export_group("Continuous Hold (0 = disable)")
@export var hold_forward_time: float = 0.0
@export var hold_up_time: float = 0.0

@export_group("Direction")
@export_enum("PositiveX", "NegativeX", "PositiveZ", "NegativeZ")
var launch_axis: int = 2

@export_group("Locking")
## Replaces prior action, movement, and spring alignment locks when activated.
@export var override_previous_lock_timers: bool = true
@export var movement_lock_time: float = 0.0
@export var action_lock_time: float = 0.0

@export_group("Camera")
@export var align_camera_yaw_roll: bool = true

@export_group("Audio")
@export var sfx_player: AudioStreamPlayer3D
@export var launch_sounds: Array[AudioStream] = []
var _last_sound_index: int = -1
var _level_prepared: bool = false
var _gameplay_activated: bool = false
var _managed_preparation: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_size_preview()
		set_physics_process(false)
		return
	if not _level_prepared:
		prepare_for_level({})
	if not _gameplay_activated and not _managed_preparation:
		activate_for_gameplay({})


func prepare_for_level(context: Dictionary) -> bool:
	_managed_preparation = _managed_preparation or bool(context.get("managed", false))
	if _level_prepared:
		return true
	_apply_size_preview()
	if dynamic_object_collision_mask > 0:
		collision_mask = collision_mask | dynamic_object_collision_mask
	_level_prepared = true
	return true


func activate_for_gameplay(_context: Dictionary) -> bool:
	if _gameplay_activated:
		return true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_gameplay_activated = true
	_managed_preparation = false
	return true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _body_cooldowns.is_empty():
		return
	var to_erase: Array = []
	for id in _body_cooldowns.keys():
		_body_cooldowns[id] -= delta
		if _body_cooldowns[id] <= 0.0:
			to_erase.append(id)
	for id in to_erase:
		_body_cooldowns.erase(id)


func _apply_size_preview() -> void:
	var uniform_size: float = max(size, 0.01)
	var size_node_paths: Array[NodePath] = [
		NodePath("CollisionShape3D"),
		NodePath("TempMesh"),
		NodePath("RampMesh"),
	]
	for node_path: NodePath in size_node_paths:
		_apply_size_to_node(get_node_or_null(node_path) as Node3D, uniform_size)


func _apply_size_to_node(node: Node3D, uniform_size: float) -> void:
	if not node:
		return
	if not node.has_meta(SIZE_BASE_POSITION_META):
		node.set_meta(SIZE_BASE_POSITION_META, node.position)
	if not node.has_meta(SIZE_BASE_SCALE_META):
		node.set_meta(SIZE_BASE_SCALE_META, node.scale)
	var base_position_value: Variant = node.get_meta(SIZE_BASE_POSITION_META, node.position)
	var base_scale_value: Variant = node.get_meta(SIZE_BASE_SCALE_META, node.scale)
	if base_position_value is Vector3:
		node.position = (base_position_value as Vector3) * uniform_size
	if base_scale_value is Vector3:
		node.scale = (base_scale_value as Vector3) * uniform_size


func _on_body_entered(body: Node3D) -> void:
	if not active:
		return
	if not body.has_method("apply_ramp_impulse"):
		return
	if _is_carried_object(body):
		return

	var id: int = body.get_instance_id()
	var remaining: float = _body_cooldowns.get(id, 0.0)
	if remaining > 0.0:
		return

	var basis: Basis = global_transform.basis
	var ramp_forward: Vector3 = _get_launch_direction(basis)
	var ramp_up: Vector3 = basis.y
	if override_previous_lock_timers and body.has_method("clear_object_lock_timers"):
		body.call("clear_object_lock_timers")

	body.call(
		"apply_ramp_impulse",
		global_transform.origin,
		ramp_forward,
		ramp_up,
		forward_speed,
		up_speed,
		additive_launch,
		additive_min_forward_speed,
		movement_lock_time,
		action_lock_time,
		align_camera_yaw_roll,
		hold_forward_time,
		hold_up_time
	)

	_body_cooldowns[id] = rehit_cooldown
	_play_launch_sfx()


func _is_carried_object(body: Node) -> bool:
	if not body.has_method("is_carried"):
		return false
	return body.call("is_carried") == true


func _get_launch_direction(basis: Basis) -> Vector3:
	var dir: Vector3 = basis.z
	match launch_axis:
		0:
			dir = basis.x
		1:
			dir = -basis.x
		2:
			dir = basis.z
		3:
			dir = -basis.z
	if dir.length() < 0.001:
		dir = basis.z
	return dir.normalized()


func _play_launch_sfx() -> void:
	if sfx_player == null or launch_sounds.is_empty():
		return
	var idx := randi_range(0, launch_sounds.size() - 1)
	if launch_sounds.size() > 1 and idx == _last_sound_index:
		idx = (idx + 1) % launch_sounds.size()
	_last_sound_index = idx
	sfx_player.stream = launch_sounds[idx]
	sfx_player.play()

@tool
extends Area3D

const SIZE_BASE_POSITION_META: StringName = &"_uniform_size_base_position"
const SIZE_BASE_SCALE_META: StringName = &"_uniform_size_base_scale"

# ===========================================================
# DASH PANEL CONFIG
# ===========================================================
@export_group("DashPanel")
@export var active: bool = true
## Uniform scale applied to the panel mesh and trigger collision.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = max(value, 0.01)
		if is_node_ready():
			_apply_size_preview()
## Additional collision mask for dynamic physics objects that can be launched by this dash panel.
@export_flags_3d_physics var dynamic_object_collision_mask: int = 2
@export var rehit_cooldown: float = 0.15
## Also snaps the player to the panel's grounded Y position. Disabled follows the player's current surface height.
@export var match_y_position: bool = false

var _body_cooldowns: Dictionary = {}

# -----------------------------------------------------------
# IMPULSE
# -----------------------------------------------------------
@export_group("Impulse")

## Base strength of the dash impulse (units / sec).
@export var strength: float = 40.0

## Replaces prior movement with panel speed. Wall runs use the panel's wall-projected direction.
@export var stop_momentum: bool = true

## When stop_momentum is disabled, mode 0 replaces prior vertical speed; mode 1 adds to all prior speed.
@export_enum("IgnorePriorVertical", "FullyAdditiveWithMinLaunch")
var additive_mode: int = 0

## For FullyAdditiveWithMinLaunch: minimum speed along dash direction
## after the impulse is applied.
@export var min_additive_launch_speed: float = 15.0

# -----------------------------------------------------------
# DIRECTION
# -----------------------------------------------------------
@export_group("Direction")

## Which axis of the panel node counts as the dash direction.
## Typically PositiveZ if your arrow points +Z.
@export_enum("PositiveX", "NegativeX", "PositiveZ", "NegativeZ")
var launch_axis: int = 2

# -----------------------------------------------------------
# LOCKING / CAMERA
# -----------------------------------------------------------
@export_group("Locking & Camera")
## Replaces prior action, movement, and spring alignment locks when activated.
@export var override_previous_lock_timers: bool = true

## How long to lock player steering movement (they still move along the dash).
@export var movement_lock_time: float = 0.0

## How long to lock actions. Pressing any action while this is > 0
## will break movement lock but still not perform the action.
@export var action_lock_time: float = 0.0

## If true, aligns the camera yaw (and potential roll later)
## to the dash direction when activated.
@export var align_camera_yaw_roll: bool = true

## If true, forces Sonic to stay at a fixed speed along the dash direction
## for a short duration.
@export var lock_speed_enabled: bool = false

## Speed to lock at (units/sec).
@export var lock_speed_value: float = 60.0

## How long to keep this speed lock active.
@export var lock_speed_duration: float = 0.5

## If true, temporarily overrides the player's maximum speed when this panel is activated.
@export var override_player_max_speed: bool = false
## Maximum player speed used while the override is active.
@export_range(0.0, 1000.0) var player_max_speed_override: float = 60.0
## Duration of the player maximum speed override.
@export_range(0.0, 60.0) var max_speed_override_duration: float = 0.5

# -----------------------------------------------------------
# AUDIO (optional, same pattern as springs)
# -----------------------------------------------------------
@export_group("Audio")

@export var sfx_player: AudioStreamPlayer3D
@export var dash_sounds: Array[AudioStream] = []
var _last_sound_index: int = -1
var _level_prepared: bool = false
var _gameplay_activated: bool = false
var _managed_preparation: bool = false


# ===========================================================
# LIFECYCLE
# ===========================================================
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
		NodePath("TempMesh2"),
		NodePath("Mesh"),
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

# ===========================================================
# SIGNAL HANDLER
# ===========================================================
func _on_body_entered(body: Node3D) -> void:
	if not active:
		return
	if not body.has_method("apply_dash_panel_impulse"):
		return
	if _is_carried_object(body):
		return

	# ---- per-body rehit cooldown ----
	var id: int = body.get_instance_id()
	var remaining: float = _body_cooldowns.get(id, 0.0)
	if remaining > 0.0:
		return  # still on cooldown – ignore this enter

	var player: Node3D = body
	var dash_dir: Vector3 = _get_dash_direction()

	player.apply_dash_panel_impulse(
		global_transform.origin,
		dash_dir,
		strength,
		stop_momentum,
		additive_mode,
		min_additive_launch_speed,
		movement_lock_time,
		action_lock_time,
		align_camera_yaw_roll,
		global_transform.basis,
		lock_speed_enabled,
		lock_speed_value,
		lock_speed_duration,
		override_player_max_speed,
		player_max_speed_override,
		max_speed_override_duration,
		match_y_position,
		override_previous_lock_timers
	)
	if player.has_method("register_combo_feat"):
		player.call("register_combo_feat", &"dash_panel", "Dash Panel", 75.0, 0.6)

	# Start cooldown for this body on this dash panel
	_body_cooldowns[id] = rehit_cooldown

	_play_dash_sfx()


func _is_carried_object(body: Node) -> bool:
	if not body.has_method("is_carried"):
		return false
	return body.call("is_carried") == true


# ===========================================================
# DIRECTION
# ===========================================================
func _get_dash_direction() -> Vector3:
	var basis := global_transform.basis
	var dir := basis.z  # default +Z

	match launch_axis:
		0: # PositiveX
			dir = basis.x
		1: # NegativeX
			dir = -basis.x
		2: # PositiveZ
			dir = basis.z
		3: # NegativeZ
			dir = -basis.z

	if dir.length() < 0.001:
		dir = basis.z

	return dir.normalized()


# ===========================================================
# AUDIO
# ===========================================================
func _play_dash_sfx() -> void:
	if sfx_player == null or dash_sounds.is_empty():
		return

	_last_sound_index = _play_random_sfx_from_list(
		sfx_player,
		dash_sounds,
		_last_sound_index,
		true
	)

func _play_random_sfx_from_list(
	player: AudioStreamPlayer3D,
	sounds: Array[AudioStream],
	last_index: int,
	avoid_repeat: bool = true
) -> int:
	if player == null or sounds.is_empty():
		return last_index

	var idx := randi_range(0, sounds.size() - 1)

	if avoid_repeat and sounds.size() > 1 and idx == last_index:
		idx = (idx + 1) % sounds.size()

	player.stream = sounds[idx]
	player.play()
	return idx

extends PathFollow3D

const BOOST_FIXED: int = 0
const BOOST_ADDITIVE: int = 1

@export_group("Rail Booster")
@export var active: bool = true
@export var require_group: StringName = "player"
@export_enum("Fixed", "Additive") var boost_mode: int = BOOST_FIXED
@export_range(-400.0, 400.0) var boost_speed: float = 80.0
## Reverses the boost relative to the rail direction or the authored facing of a native booster.
@export var reverse_direction: bool = false
@export var require_same_rail: bool = true
@export_range(0.0, 1.0) var tangent_lookahead: float = 0.05
@export var rehit_cooldown: float = 0.2
@export_range(-400.0, 400.0) var additive_min_speed: float = 0.0
## Fraction along the parent rail for placement sidecars. Negative values use the authored PathFollow progress.
@export_range(-1.0, 1.0) var placement_progress: float = -1.0
@export_group("Audio")
@export var sfx_player: AudioStreamPlayer3D
@export var boost_sounds: Array[AudioStream] = []
var _last_sound_index: int = -1

var _body_cooldowns: Dictionary = {}
var _area: Area3D


func _ready() -> void:
	if placement_progress >= 0.0:
		var path: Path3D = _get_rail_path()
		if path:
			path.curve_changed.connect(_sync_placement_progress)
			_sync_placement_progress()
	_area = get_node_or_null("Area3D")
	if _area != null:
		_area.body_entered.connect(try_boost)
	set_physics_process(true)


func _sync_placement_progress() -> void:
	var path: Path3D = _get_rail_path()
	if not path or not path.curve:
		return
	loop = path.curve.closed
	rotation_mode = PathFollow3D.ROTATION_ORIENTED
	cubic_interp = false
	progress = path.curve.get_baked_length() * placement_progress


func _physics_process(delta: float) -> void:
	if _body_cooldowns.is_empty():
		return

	var to_remove: Array = []
	for id in _body_cooldowns.keys():
		_body_cooldowns[id] -= delta
		if _body_cooldowns[id] <= 0.0:
			to_remove.append(id)

	for id in to_remove:
		_body_cooldowns.erase(id)


func try_boost(body: Node) -> void:
	if not active:
		return
	if require_group != "" and not body.is_in_group(require_group):
		return
	if not body.has_method("apply_rail_boost"):
		return
	if require_same_rail and not _is_body_on_same_rail(body):
		return

	var id: int = body.get_instance_id()
	var remaining := float(_body_cooldowns.get(id, 0.0))
	if remaining > 0.0:
		return

	var rail_dir: Vector3 = _get_rail_tangent()
	if rail_dir.length() < 0.001:
		return
	var direction: float = -1.0 if placement_progress < 0.0 and rail_dir.dot(-global_basis.z) < 0.0 else 1.0
	if reverse_direction:
		direction = -direction
	if not body.call("apply_rail_boost", boost_speed, boost_mode, direction, _get_rail_path(), additive_min_speed):
		return
	_body_cooldowns[id] = max(rehit_cooldown, 0.0)
	_play_boost_sfx()


func _get_rail_path() -> Path3D:
	var parent := get_parent()
	return parent if parent is Path3D else null


func _is_body_on_same_rail(body: Node) -> bool:
	var path := _get_rail_path()
	if path == null:
		return false
	if body.has_method("is_on_rail_path"):
		return bool(body.call("is_on_rail_path", path))
	return false


func _get_rail_tangent() -> Vector3:
	var path := _get_rail_path()
	if path == null or path.curve == null:
		return Vector3.ZERO
	var curve := path.curve
	var total_len := curve.get_baked_length()
	if total_len <= 0.01:
		return Vector3.ZERO

	var offset : float = clamp(progress, 0.0, total_len)
	var lookahead : float = max(tangent_lookahead, 0.0)
	var ahead : float = clamp(offset + lookahead, 0.0, total_len)
	if abs(ahead - offset) < 0.0001:
		ahead = min(offset + 0.05, total_len)
	if is_equal_approx(ahead, offset):
		offset = maxf(ahead - 0.05, 0.0)

	var here_local := curve.sample_baked(offset)
	var there_local := curve.sample_baked(ahead)
	var here := path.to_global(here_local)
	var there := path.to_global(there_local)
	var dir := there - here
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized()

func _play_boost_sfx() -> void:
	if sfx_player == null or boost_sounds.is_empty():
		return
	_last_sound_index = _play_random_sfx_from_list(
		sfx_player,
		boost_sounds,
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

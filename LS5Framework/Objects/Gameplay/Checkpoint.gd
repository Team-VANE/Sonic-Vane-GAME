extends Area3D

@export var active: bool = true

@export_group("Activation")
@export var require_group_primary: StringName = &"Player"
@export var require_group_secondary: StringName = &"player"
@export var rehit_cooldown: float = 0.25

var _body_cooldowns: Dictionary = {}

@export_group("Respawn")
@export var respawn_point_path: NodePath = NodePath("RespawnPoint")
@export var respawn_speed: float = 0.0
@export_enum("PositiveX", "NegativeX", "PositiveZ", "NegativeZ")
var respawn_axis: int = 2

@export_group("Audio")
@export var sfx_player: AudioStreamPlayer3D
@export var activate_sounds: Array[AudioStream] = []
var _last_sound_index: int = -1


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _body_cooldowns.is_empty():
		return
	var to_erase: Array = []
	for id in _body_cooldowns.keys():
		_body_cooldowns[id] -= delta
		if _body_cooldowns[id] <= 0.0:
			to_erase.append(id)
	for id in to_erase:
		_body_cooldowns.erase(id)


func _on_body_entered(body: Node) -> void:
	if not active:
		return
	if body == null:
		return
	if not (body is CharacterBody3D):
		return
	# Buddy pawns should never activate checkpoints.
	if body.has_method("has_meta") and body.call("has_meta", "is_buddy"):
		var v = body.call("get_meta", "is_buddy")
		if v is bool and bool(v):
			return

	var ok_group: bool = false
	if require_group_primary != &"" and body.is_in_group(require_group_primary):
		ok_group = true
	if not ok_group and require_group_secondary != &"" and body.is_in_group(require_group_secondary):
		ok_group = true
	if not ok_group:
		return

	var can_activate = body.has_method("activate_checkpoint_from") or body.has_method("activate_checkpoint")
	if not can_activate:
		return

	# Don’t play SFX or re-activate if this is the same checkpoint as last time.
	if body.has_method("can_activate_checkpoint_source"):
		var ok = body.call("can_activate_checkpoint_source", self)
		if ok is bool and not bool(ok):
			return

	var id: int = int(body.get_instance_id())
	var remaining: float = float(_body_cooldowns.get(id, 0.0))
	if remaining > 0.0:
		return

	var t: Transform3D = _get_respawn_transform()
	var dir: Vector3 = _get_respawn_direction(t.basis)

	if body.has_method("activate_checkpoint_from"):
		body.call("activate_checkpoint_from", self, t, respawn_speed, dir)
	else:
		body.call("activate_checkpoint", t, respawn_speed, dir)
	_body_cooldowns[id] = max(rehit_cooldown, 0.0)
	_play_activate_sfx()


func _get_respawn_transform() -> Transform3D:
	var n = get_node_or_null(respawn_point_path)
	if n is Node3D:
		return (n as Node3D).global_transform
	return global_transform


func _get_respawn_direction(basis: Basis) -> Vector3:
	var dir: Vector3 = basis.z
	match respawn_axis:
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


func _play_activate_sfx() -> void:
	if sfx_player == null or activate_sounds.is_empty():
		return
	var idx: int = int(randi_range(0, activate_sounds.size() - 1))
	if activate_sounds.size() > 1 and idx == _last_sound_index:
		idx = (idx + 1) % activate_sounds.size()
	_last_sound_index = idx
	sfx_player.stream = activate_sounds[idx]
	sfx_player.play()

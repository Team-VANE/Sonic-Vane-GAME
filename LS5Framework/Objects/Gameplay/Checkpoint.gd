@tool
extends Area3D

const CheckpointVisual = preload("res://LS5Framework/Objects/Gameplay/CheckpointVisual.gd")

@export var active: bool = true

@export_group("Activation")
@export var require_group_primary: StringName = &"Player"
@export var require_group_secondary: StringName = &"player"
@export var rehit_cooldown: float = 0.25

var _body_cooldowns: Dictionary = {}

@export_group("Gate")
## Distance between post centers in meters. The minimum fits the inward-folded poles.
@export_range(6.0, 100.0, 0.01, "or_greater", "suffix:m") var width: float = 6.006:
	set(value):
		width = maxf(6.0, value)
		if is_node_ready():
			_sync_width()
## Matches the trigger's local X span to the post spacing.
@export var fit_trigger_to_width: bool = false:
	set(value):
		fit_trigger_to_width = value
		if is_node_ready():
			_sync_width()
## Local X size when Match Post Spacing is off. Zero uses the authored collider.
@export_range(0.0, 100.0, 0.05, "or_greater", "suffix:m") var trigger_width: float = 0.0:
	set(value):
		trigger_width = value
		if is_node_ready():
			_sync_width()
## Local Y size of the trigger. Zero uses the authored collider.
@export_range(0.0, 100.0, 0.05, "or_greater", "suffix:m") var trigger_height: float = 0.0:
	set(value):
		trigger_height = value
		if is_node_ready():
			_sync_width()
## Local Z size of the trigger. Zero uses the authored collider.
@export_range(0.0, 100.0, 0.05, "or_greater", "suffix:m") var trigger_depth: float = 0.0:
	set(value):
		trigger_depth = value
		if is_node_ready():
			_sync_width()

@export_group("Respawn")
@export var respawn_speed: float = 0.0
@export_enum("PositiveX", "NegativeX", "PositiveZ", "NegativeZ")
var respawn_axis: int = 2

@export_group("Audio")
@export var sfx_player: AudioStreamPlayer3D
@export var activate_sounds: Array[AudioStream] = []
var _last_sound_index: int = -1
var _selected_players: Dictionary = {}
var _authored_trigger_size: Vector3

## Skinned model driven by checkpoint selection and approach motion.
@onready var _visual: CheckpointVisual = get_node_or_null("CheckpointVisual") as CheckpointVisual

## Trigger used for the optional width-matched gate.
@onready var _trigger: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D


func _ready() -> void:
	if _trigger and _trigger.shape is BoxShape3D:
		_authored_trigger_size = (_trigger.shape as BoxShape3D).size
	_sync_width()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _sync_width() -> void:
	if _visual:
		_visual.set_width(width)
	if _trigger and _trigger.shape is BoxShape3D:
		var box: BoxShape3D = _trigger.shape
		var size: Vector3 = _authored_trigger_size
		size.x = width if fit_trigger_to_width else (trigger_width if trigger_width > 0.0 else size.x)
		if trigger_height > 0.0:
			size.y = trigger_height
		if trigger_depth > 0.0:
			size.z = trigger_depth
		if not size.is_equal_approx(box.size):
			var resized: BoxShape3D = box.duplicate() as BoxShape3D
			resized.size = size
			_trigger.shape = resized


func set_checkpoint_selected(body: CharacterBody3D, selected: bool) -> void:
	var id: int = body.get_instance_id()
	if selected:
		if not _selected_players.has(id):
			_selected_players[id] = true
			body.tree_exiting.connect(_remove_selected_player.bind(id), CONNECT_ONE_SHOT)
		if _visual:
			_visual.set_selected(true, body.velocity, body.global_position)
		return
	var on_exit: Callable = _remove_selected_player.bind(id)
	if body.tree_exiting.is_connected(on_exit):
		body.tree_exiting.disconnect(on_exit)
	_remove_selected_player(id)


func _remove_selected_player(id: int) -> void:
	_selected_players.erase(id)
	if _visual and _selected_players.is_empty():
		_visual.set_selected(false, Vector3.ZERO, Vector3.ZERO)


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


## Uses only this checkpoint instance's direct RespawnPoint child.
func _get_respawn_transform() -> Transform3D:
	var respawn_point: Node3D = get_node_or_null("RespawnPoint") as Node3D
	if respawn_point:
		return respawn_point.global_transform
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

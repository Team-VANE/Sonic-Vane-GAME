extends Area3D
class_name TeleporterEntrance

@export_group("Teleporter Entrance")
@export var enabled: bool = true
@export var one_shot: bool = false
@export var require_group: StringName = &"player"

@export var keep_velocity: bool = true
@export var match_exit_rotation: bool = false
@export var rehit_cooldown: float = 0.20
@export var exit_local_offset: Vector3 = Vector3.ZERO

@export_group("Level")
## LVL_*.tres doc name used by the level catalog (example: LVL_GreenHillOcean.tres).
@export var target_level_doc_name: String = ""
@export var target_level_id: StringName = &""
@export_file("*.tscn") var target_level_scene_path: String = ""
@export var target_exit_path: NodePath = NodePath("")

@export_group("Link")
@export var exit_node: Node3D
@export var exit_id: StringName = &""
@export var exit_group: StringName = &"TeleporterExit"

var _body_cooldowns: Dictionary = {}


func _ready() -> void:
	monitoring = true
	monitorable = true
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
	if not enabled:
		return
	if body == null or not (body is Node3D):
		return

	# Buddy pawns should not trigger teleporters.
	if body.has_method("has_meta") and body.call("has_meta", "is_buddy"):
		var v = body.call("get_meta", "is_buddy")
		if v is bool and bool(v):
			return

	# Group gating.
	if require_group != &"" and not body.is_in_group(require_group):
		return

	# Only affect the local authority in multiplayer.
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if body.has_method("is_multiplayer_authority") and not body.is_multiplayer_authority():
			return

	var exit_target: Node3D = _resolve_exit()
	if exit_target == null or not is_instance_valid(exit_target):
		push_warning("%s: TeleporterExit not found (assign exit_node or set exit_id)." % name)
		return

	var id = body.get_instance_id()
	var remaining: float = float(_body_cooldowns.get(id, 0.0))
	if remaining > 0.0:
		return

	if _has_level_target():
		var level_manager = _get_level_manager()
		if level_manager != null:
			if target_level_doc_name.strip_edges() != "" and level_manager.has_method("request_level_change_from_doc"):
				level_manager.call(
					"request_level_change_from_doc",
					target_level_doc_name,
					target_exit_path,
					body,
					keep_velocity,
					match_exit_rotation,
					exit_local_offset
				)
			elif level_manager.has_method("request_level_change"):
				level_manager.call(
					"request_level_change",
					target_level_id,
					target_level_scene_path,
					target_exit_path,
					body,
					keep_velocity,
					match_exit_rotation,
					exit_local_offset
				)
		_body_cooldowns[id] = rehit_cooldown
		if one_shot:
			enabled = false
			monitoring = false
		return

	_apply_teleport_to_body(body as Node3D, exit_target)
	_body_cooldowns[id] = rehit_cooldown

	if one_shot:
		enabled = false
		monitoring = false


func _resolve_exit() -> Node3D:
	if _has_level_target():
		return null
	if exit_node != null and is_instance_valid(exit_node):
		return exit_node
	if exit_id == &"" or exit_group == &"":
		return null
	if get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group(exit_group):
		if n == null or not is_instance_valid(n):
			continue
		if not (n is Node3D):
			continue
		if n.has_method("get"):
			var tid = n.get("teleporter_id")
			if tid is StringName and tid == exit_id:
				return n as Node3D
			if tid is String and StringName(String(tid)) == exit_id:
				return n as Node3D
	return null


func _apply_teleport_to_body(body: Node3D, exit_target: Node3D) -> void:
	# Preferred integration hook: if your player has a dedicated teleport method, use it.
	if body.has_method("apply_teleport_from_exit"):
		body.call("apply_teleport_from_exit", exit_target, keep_velocity, match_exit_rotation, exit_local_offset)
	elif body.has_method("apply_teleport"):
		body.call("apply_teleport", exit_target.global_transform, keep_velocity, match_exit_rotation, exit_local_offset)
		return

	# Fallback: move the body directly.
	var old_basis: Basis = body.global_transform.basis
	var old_velocity: Vector3 = Vector3.ZERO
	var has_velocity: bool = false
	if body is CharacterBody3D:
		old_velocity = (body as CharacterBody3D).velocity
		has_velocity = true

	var exit_xform: Transform3D = exit_target.global_transform
	var world_offset: Vector3 = exit_xform.basis * exit_local_offset
	var base_xform := Transform3D(exit_xform.basis, exit_xform.origin + world_offset)
	base_xform = DownwarpUtil.apply_downwarp_from_node(exit_target, base_xform, [body])
	var new_origin: Vector3 = base_xform.origin
	var new_basis: Basis = base_xform.basis if match_exit_rotation else old_basis
	body.global_transform = Transform3D(new_basis, new_origin)

	if has_velocity:
		var cb = body as CharacterBody3D
		cb.velocity = old_velocity if keep_velocity else Vector3.ZERO


func _has_level_target() -> bool:
	if target_level_doc_name.strip_edges() != "":
		return true
	if target_level_id != &"":
		return true
	if target_level_scene_path != "":
		return true
	return false


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)

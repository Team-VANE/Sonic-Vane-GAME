extends Node3D
class_name Teleporter

# ===========================================================
# TELEPORTER CONFIG
# ===========================================================
@export_group("Teleporter")
@export var enabled: bool = true
@export var one_shot: bool = false
@export var require_group: StringName = "player" # matches your WorldObject default :contentReference[oaicite:2]{index=2}

## If true, keep the player's velocity as-is after teleport.
## If false, the player's velocity will be zeroed.
@export var keep_velocity: bool = true

## If true, overwrite the player's rotation to match the Exit node.
## If false, only move position.
@export var match_exit_rotation: bool = false

## Time after triggering during which the same body cannot re-trigger this teleporter.
@export var rehit_cooldown: float = 0.20

## Local-space offset from the Exit node (useful to avoid spawning inside geometry).
@export var exit_local_offset: Vector3 = Vector3(0, 0, 0)

@export_group("Level")
## LVL_*.tres doc name used by the level catalog (example: LVL_GreenHillOcean.tres).
@export var target_level_doc_name: String = ""
@export var target_level_id: StringName = &""
@export_file("*.tscn") var target_level_scene_path: String = ""
@export var target_exit_path: NodePath = NodePath("")

@export_group("Nodes")
@export var entrance_area: Area3D
@export var exit_node: Node3D

# instance_id -> remaining_time :contentReference[oaicite:3]{index=3}
var _body_cooldowns: Dictionary = {}

func _ready() -> void:
	if entrance_area == null:
		push_warning("%s: entrance_area is not assigned." % name)
		return
	if exit_node == null and not _has_level_target():
		push_warning("%s: exit_node is not assigned." % name)
		return

	if not entrance_area.body_entered.is_connected(_on_entrance_body_entered):
		entrance_area.body_entered.connect(_on_entrance_body_entered)

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

func _on_entrance_body_entered(body: Node3D) -> void:
	if not enabled:
		return

	# Group gating like WorldObject :contentReference[oaicite:4]{index=4}
	if require_group != "" and not body.is_in_group(require_group):
		return

	# Only affect the local authority in multiplayer.
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if body.has_method("is_multiplayer_authority") and not body.is_multiplayer_authority():
			return

	# ---- per-body rehit cooldown (Spring-style) :contentReference[oaicite:5]{index=5}
	var id := body.get_instance_id()
	var remaining: float = _body_cooldowns.get(id, 0.0)
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
			entrance_area.monitoring = false
		return

	if exit_node == null:
		return

	# Preferred integration hook: if your player has a dedicated teleport method, use it.
	# (This is the best place to reset "attached" / adhesion state cleanly.)
	if body.has_method("apply_teleport_from_exit"):
		body.apply_teleport_from_exit(exit_node, keep_velocity, match_exit_rotation, exit_local_offset)
	elif body.has_method("apply_teleport"):
		body.apply_teleport(exit_node.global_transform, keep_velocity, match_exit_rotation, exit_local_offset)
	else:
		_fallback_teleport(body)

	_body_cooldowns[id] = rehit_cooldown
	print("Teleporting...")
	
	if one_shot:
		enabled = false
		entrance_area.monitoring = false

func _fallback_teleport(body: Node3D) -> void:
	var old_basis := body.global_transform.basis
	var old_velocity := Vector3.ZERO
	var has_velocity := false

	if body is CharacterBody3D:
		old_velocity = body.velocity
		has_velocity = true

	var exit_xform := exit_node.global_transform
	var world_offset := exit_xform.basis * exit_local_offset
	var base_xform := Transform3D(exit_xform.basis, exit_xform.origin + world_offset)
	base_xform = DownwarpUtil.apply_downwarp_from_node(exit_node, base_xform, [body])
	var new_origin := base_xform.origin

	var new_basis := base_xform.basis if match_exit_rotation else old_basis
	body.global_transform = Transform3D(new_basis, new_origin)

	if has_velocity:
		if keep_velocity:
			body.velocity = old_velocity
		else:
			body.velocity = Vector3.ZERO


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

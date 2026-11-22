extends Node

const COMPONENT = preload("res://LS5Framework/Scripts/World/ObjectDistanceCull3D.gd")
const UPDATE_BUCKETS: int = 8
const TELEPORT_DISTANCE_SQUARED: float = 4096.0
const TARGET_WAKE_MARGIN: float = 60.0
const ANCHOR_GROUPS: Array[StringName] = [&"player", &"Player", &"RivalActor"]

enum Policy { NONE, VISUAL, TARGET, RING, PATH, TARGET_POINT, ENEMY }

const POLICIES: Dictionary[String, int] = {
	"Objects/Enemies/Core/Enemy.gd": Policy.ENEMY,
	"Scripts/Actors/ActorTargetable3D.gd": Policy.TARGET_POINT,
	"Objects/Bumper/Bumper.gd": Policy.VISUAL,
	"Objects/Carry/CarryableObject.gd": Policy.VISUAL,
	"Objects/DashPanels/DashPanel.gd": Policy.VISUAL,
	"Objects/Enemies/SpikeBall/SpikeBall.gd": Policy.VISUAL,
	"Objects/Gameplay/Checkpoint.gd": Policy.VISUAL,
	"Objects/Homing/HomingTarget.gd": Policy.TARGET_POINT,
	"Objects/Homing/AttackMagnetismTarget.gd": Policy.TARGET_POINT,
	"Objects/ItemMonitor/ItemMonitor.gd": Policy.TARGET,
	"Objects/MovingPlatform/MovingPlatform.gd": Policy.VISUAL,
	"Objects/Pinball/Flipper/Flipper.gd": Policy.VISUAL,
	"Objects/Props/ObjectPhysicsBody3D.gd": Policy.VISUAL,
	"Objects/Props/PropBody3D.gd": Policy.VISUAL,
	"Objects/Race/GoalRing/goal_ring_visual.gd": Policy.VISUAL,
	"Objects/Rail/Rail.gd": Policy.PATH,
	"Objects/Rail/RailBooster.gd": Policy.VISUAL,
	"Objects/Ramps/JumpPanelRamp.gd": Policy.VISUAL,
	"Objects/Rings/DroppedRing.gd": Policy.VISUAL,
	"Objects/Rings/Ring.gd": Policy.RING,
	"Objects/SpikeStrip/SpikeStrip.gd": Policy.VISUAL,
	"Objects/Spring/Spring.gd": Policy.TARGET,
	"Objects/Terminal/Terminal.gd": Policy.VISUAL,
	"Objects/Teleporter/TeleporterExit.gd": Policy.VISUAL,
	"Objects/VaultBar/VaultBar.gd": Policy.TARGET,
}

var _policies_by_script: Dictionary[int, int] = {}
var _buckets: Array[Dictionary] = []
var _anchor_positions: Dictionary[World3D, PackedVector3Array] = {}
var _anchor_target_distances: Dictionary[World3D, float] = {}
var _previous_anchors: Dictionary[int, Vector3] = {}
var _previous_camera: Camera3D
var _previous_camera_position: Vector3 = Vector3.ZERO
var _bucket_index: int = 0
var _next_registration: int = 0


func _ready() -> void:
	process_physics_priority = -90
	for index: int in range(UPDATE_BUCKETS):
		_buckets.append({})
	get_tree().node_added.connect(_on_node_added)
	set_physics_process(false)


func register_component(component: ObjectDistanceCull3D) -> void:
	if not component.can_suspend_updates():
		return
	var bucket: int = _next_registration % UPDATE_BUCKETS
	_next_registration += 1
	_buckets[bucket][component.get_instance_id()] = component
	set_physics_process(true)


func unregister_component(component: ObjectDistanceCull3D) -> void:
	for bucket: Dictionary in _buckets:
		if bucket.erase(component.get_instance_id()):
			break
	for bucket: Dictionary in _buckets:
		if not bucket.is_empty():
			return
	set_physics_process(false)
	_previous_anchors.clear()
	_anchor_positions.clear()
	_anchor_target_distances.clear()


func _physics_process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var refresh_all: bool = _refresh_anchors() or camera != _previous_camera
	if camera:
		var position: Vector3 = camera.global_position
		refresh_all = refresh_all or position.distance_squared_to(_previous_camera_position) > TELEPORT_DISTANCE_SQUARED
		_previous_camera_position = position
	_previous_camera = camera
	if refresh_all:
		for bucket: Dictionary in _buckets:
			_refresh_bucket(bucket, camera)
	else:
		_refresh_bucket(_buckets[_bucket_index], camera)
	_bucket_index = (_bucket_index + 1) % UPDATE_BUCKETS


func _refresh_bucket(bucket: Dictionary, camera: Camera3D) -> void:
	for entry: Variant in bucket.values():
		if is_instance_valid(entry) and entry.can_process():
			var component: ObjectDistanceCull3D = entry
			var world: World3D = component.get_world()
			component.refresh(_anchor_positions.get(world, PackedVector3Array()), camera, _anchor_target_distances.get(world, 0.0))


func _refresh_anchors() -> bool:
	_anchor_positions.clear()
	_anchor_target_distances.clear()
	var current_anchors: Dictionary[int, Vector3] = {}
	var changed: bool = false
	for group: StringName in ANCHOR_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not node is Node3D or node.is_queued_for_deletion():
				continue
			var id: int = node.get_instance_id()
			if current_anchors.has(id):
				continue
			var position: Vector3 = node.global_position
			current_anchors[id] = position
			if not _previous_anchors.has(id) or position.distance_squared_to(_previous_anchors[id]) > TELEPORT_DISTANCE_SQUARED:
				changed = true
			var world: World3D = node.get_world_3d()
			if world:
				var positions: PackedVector3Array = _anchor_positions.get(world, PackedVector3Array())
				positions.append(position)
				_anchor_positions[world] = positions
				if node is PlayerControllerState:
					var player: PlayerControllerState = node
					var range_limit: float = maxf(player.homing_max_range, player.attack_magnetism_max_range)
					range_limit = maxf(range_limit, player.carry_throw_target_max_range)
					range_limit = maxf(range_limit, maxf(player.lightspeed_dash_start_radius, player.lightspeed_dash_chain_radius) + player.lightspeed_dash_camera_radius_bonus)
					if node is RivalActorPlayer:
						range_limit = maxf(range_limit, maxf(node.rival_ring_search_radius, node.rival_rage_ring_search_radius))
					_anchor_target_distances[world] = maxf(_anchor_target_distances.get(world, 0.0), range_limit + TARGET_WAKE_MARGIN)
	changed = changed or current_anchors.size() != _previous_anchors.size()
	_previous_anchors = current_anchors
	return changed


func _on_node_added(node: Node) -> void:
	if not node is Node3D:
		return
	var script: Script = node.get_script() as Script
	if not script:
		return
	var script_id: int = script.get_instance_id()
	if not _policies_by_script.has(script_id):
		_policies_by_script[script_id] = _get_policy(script)
	var policy: int = _policies_by_script[script_id]
	if policy != Policy.NONE:
		_install_component.call_deferred(node.get_instance_id(), policy)


func _get_policy(script: Script) -> int:
	while script:
		var policy: int = POLICIES.get(script.resource_path.trim_prefix("res://LS5Framework/"), Policy.NONE)
		if policy != Policy.NONE:
			return policy
		script = script.get_base_script()
	return Policy.NONE


func _install_component(instance_id: int, policy: int) -> void:
	var node: Node3D = instance_from_id(instance_id) as Node3D
	if not node or not node.is_inside_tree() or node.is_queued_for_deletion():
		return
	for child: Node in node.get_children():
		if child is ObjectDistanceCull3D:
			return
	var component: ObjectDistanceCull3D = COMPONENT.new()
	component.name = &"DistanceCull"
	match policy:
		Policy.TARGET:
			component.suspend_targeting = true
		Policy.TARGET_POINT, Policy.PATH:
			component.visual_distance = 0.0
			component.suspend_targeting = true
		Policy.RING:
			component.visual_distance = 250.0
			component.suspend_targeting = true
		Policy.ENEMY:
			component.visual_root_paths = [^"Visual"]
	node.add_child(component)

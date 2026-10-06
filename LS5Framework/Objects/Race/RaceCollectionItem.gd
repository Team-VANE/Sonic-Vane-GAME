extends Area3D
class_name RaceCollectionItem

enum CollectionCountTiming {
	HOME_IN_COMPLETED,
	RADIUS_ENTERED,
}

## Enables this collection item when its linked race is active.
@export var enabled: bool = true
## Radius that triggers collection around the item.
@export_range(0.1, 100.0, 0.1) var collection_radius: float = 3.0
## Determines whether race progress updates after home-in or immediately on radius entry.
@export_enum("Home-In Completed", "Radius Entered") var collection_count_timing: int = CollectionCountTiming.HOME_IN_COMPLETED

@export_group("Race Link")
## RaceStart that owns this item. An empty path selects the nearest Collection Race.
@export_node_path("Area3D") var race_start_path: NodePath = NodePath("")
## Optional Race ID used when automatically resolving a RaceStart.
@export var race_id: String = ""

@export_group("Visuals")
## Optional scene instantiated as the collection item's visual root.
@export var visual_scene: PackedScene
## Existing visual root used when no visual scene is provided.
@export_node_path("Node3D") var visual_root_path: NodePath = NodePath("VisualRoot")
## Mesh instance that receives custom mesh and material overrides.
@export_node_path("MeshInstance3D") var mesh_instance_path: NodePath = NodePath("VisualRoot/Mesh")
## Optional mesh override, including resources provided by mounted content packs.
@export var custom_mesh: Mesh
## Optional material override applied to the configured mesh instance.
@export var custom_material: Material
## Local rotation speed applied to the visual while available.
@export var rotation_speed_degrees: Vector3 = Vector3(0.0, 120.0, 0.0)

@export_group("Home In")
## Fixed duration of the visual home-in effect.
@export_range(0.0, 2.0, 0.01) var home_duration: float = 0.25
## Player-local offset used as the visual home-in target.
@export var home_target_offset: Vector3 = Vector3(0.0, 1.0, 0.0)
## Flat trail scene drawn along the item's home-in path.
@export var home_trail_scene: PackedScene = preload("res://LS5Framework/Objects/Homing/FlatHomingTrail.tscn")

@export_group("Effects")
## Particle scene spawned at the player when the home-in effect completes.
@export var touched_particle_scene: PackedScene = preload("res://LS5Framework/Objects/Race/RaceCollectionParticle.tscn")
## Lifetime used to clean up particle scenes that do not free themselves.
@export_range(0.05, 10.0, 0.05) var touched_particle_lifetime: float = 0.5
## Sound played when the player enters the collection radius.
@export var radius_entered_sound: AudioStream = preload("res://LS5Framework/Sounds/Objects/CollectionItem_Radius.wav")
## Sound played when the visual completes its home-in effect.
@export var home_completed_sound: AudioStream = preload("res://LS5Framework/Sounds/Objects/CollectionItem_Grab.wav")
## Audio bus used by both collection sounds.
@export var sound_bus: StringName = &"SFX"
## Volume applied to the radius-entered sound.
@export var radius_entered_volume_db: float = 0.0
## Volume applied to the home-completed sound.
@export var home_completed_volume_db: float = 0.0

var _configured_enabled: bool = true
var _race_enabled: bool = false
var _collected_locally: bool = false
var _homing: bool = false
var _home_elapsed: float = 0.0
var _home_start_position: Vector3 = Vector3.ZERO
var _home_last_target: Vector3 = Vector3.ZERO
var _home_player: Node3D = null
var _home_race_start: Node = null
var _home_trail: Node = null
var _visual_root: Node3D = null
var _visual_initial_transform: Transform3D = Transform3D.IDENTITY
var _collision_shape: CollisionShape3D = null


func _ready() -> void:
	_configured_enabled = enabled
	add_to_group("RaceCollectionItem")
	monitoring = true
	monitorable = true
	collision_mask = 0xFFFFFFFF
	_resolve_visuals()
	_resolve_home_trail()
	_configure_collection_shape()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	set_process(true)
	call_deferred("_sync_initial_active_state")


func _process(delta: float) -> void:
	if _visual_root != null and is_instance_valid(_visual_root) and not _homing and not _collected_locally:
		_visual_root.rotate_x(deg_to_rad(rotation_speed_degrees.x) * delta)
		_visual_root.rotate_y(deg_to_rad(rotation_speed_degrees.y) * delta)
		_visual_root.rotate_z(deg_to_rad(rotation_speed_degrees.z) * delta)
	if _homing:
		_tick_home_in(delta)


func _sync_initial_active_state() -> void:
	var race_start: Node = _resolve_race_start()
	if race_start == null:
		_race_enabled = false
	_sync_active_state()


func set_active_for_race(is_enabled: bool) -> void:
	_race_enabled = is_enabled
	_sync_active_state()


func is_for_race_start(race_start: Node) -> bool:
	if race_start == null or not is_instance_valid(race_start):
		return false
	return _resolve_race_start() == race_start


func reset_for_race_restart() -> void:
	_collected_locally = false
	_homing = false
	_home_elapsed = 0.0
	_home_player = null
	_home_race_start = null
	if _home_trail != null and is_instance_valid(_home_trail) and _home_trail.has_method("clear_trail"):
		_home_trail.call("clear_trail")
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.transform = _visual_initial_transform
	_sync_active_state()


func _on_body_entered(body: Node) -> void:
	if not _can_collect(body):
		return
	var race_start: Node = _resolve_race_start()
	if race_start == null or not race_start.has_method("collect_collection_item"):
		return
	if not _race_start_can_accept_collection(race_start, body):
		return
	if collection_count_timing == CollectionCountTiming.RADIUS_ENTERED:
		var accepted_value = race_start.call("collect_collection_item", body, self)
		if not (accepted_value is bool) or not bool(accepted_value):
			return
	_begin_collection(body as Node3D, race_start)


func _can_collect(body: Node) -> bool:
	if not _configured_enabled or not _race_enabled or _collected_locally or _homing:
		return false
	if body == null or not (body is CharacterBody3D):
		return false
	if body.has_meta("is_buddy") and bool(body.get_meta("is_buddy")):
		return false
	if not body.is_in_group("Player") and not body.is_in_group("player"):
		return false
	if not _is_local_player_authority(body):
		return false
	return true


func _begin_collection(player: Node3D, race_start: Node) -> void:
	_collected_locally = true
	_homing = true
	_home_elapsed = 0.0
	_home_player = player
	_home_race_start = race_start
	_home_start_position = global_position
	if _visual_root != null and is_instance_valid(_visual_root):
		_home_start_position = _visual_root.global_position
	_home_last_target = _get_home_target_position()
	_set_collision_enabled(false)
	_set_visual_visible(true)
	if _home_trail != null and is_instance_valid(_home_trail) and _home_trail.has_method("begin_trail"):
		_home_trail.call("begin_trail", _home_start_position, _get_home_trail_up())
	_play_local_sound(player, radius_entered_sound, radius_entered_volume_db)
	if home_duration <= 0.0:
		_complete_home_in()


func _tick_home_in(delta: float) -> void:
	var duration: float = max(home_duration, 0.001)
	_home_elapsed = min(_home_elapsed + max(delta, 0.0), duration)
	var progress: float = clamp(_home_elapsed / duration, 0.0, 1.0)
	var eased_progress: float = 1.0 - pow(1.0 - progress, 3.0)
	_home_last_target = _get_home_target_position()
	var visual_position: Vector3 = _home_start_position.lerp(_home_last_target, eased_progress)
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.global_position = visual_position
	if _home_trail != null and is_instance_valid(_home_trail) and _home_trail.has_method("add_trail_point"):
		_home_trail.call("add_trail_point", visual_position, _get_home_trail_up())
	if progress >= 1.0:
		_complete_home_in()


func _complete_home_in() -> void:
	if not _homing:
		return
	_homing = false
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.global_position = _home_last_target
	if _home_trail != null and is_instance_valid(_home_trail):
		if _home_trail.has_method("add_trail_point"):
			_home_trail.call("add_trail_point", _home_last_target, _get_home_trail_up())
		if _home_trail.has_method("finish_trail"):
			_home_trail.call("finish_trail")
	if collection_count_timing == CollectionCountTiming.HOME_IN_COMPLETED:
		_count_collection_item()
	_set_visual_visible(false)
	_spawn_touched_particles(_home_player, _home_last_target)
	_play_local_sound(_home_player, home_completed_sound, home_completed_volume_db)
	_home_player = null
	_home_race_start = null


func _race_start_can_accept_collection(race_start: Node, player: Node) -> bool:
	if race_start == null or not is_instance_valid(race_start):
		return false
	if race_start.has_method("can_accept_collection_item"):
		var can_accept_value = race_start.call("can_accept_collection_item", player, self)
		return can_accept_value is bool and bool(can_accept_value)
	return true


func _count_collection_item() -> bool:
	if _home_race_start == null or not is_instance_valid(_home_race_start):
		return false
	if _home_player == null or not is_instance_valid(_home_player):
		return false
	if not _home_race_start.has_method("collect_collection_item"):
		return false
	var accepted_value = _home_race_start.call("collect_collection_item", _home_player, self)
	return accepted_value is bool and bool(accepted_value)


func _get_home_target_position() -> Vector3:
	if _home_player == null or not is_instance_valid(_home_player):
		return _home_last_target
	var target_transform: Transform3D = _home_player.global_transform
	if _home_player.has_method("get"):
		var model_root_value = _home_player.get("model_root")
		if model_root_value is Node3D:
			target_transform.origin = (model_root_value as Node3D).global_position
	return target_transform.origin + target_transform.basis * home_target_offset


func _get_home_trail_up() -> Vector3:
	if _home_player == null or not is_instance_valid(_home_player):
		return Vector3.UP
	var player_up: Vector3 = _home_player.global_transform.basis.y
	return player_up.normalized() if player_up.length() >= 0.001 else Vector3.UP


func _resolve_visuals() -> void:
	var configured_visual_root: Node3D = null
	if visual_root_path != NodePath(""):
		configured_visual_root = get_node_or_null(visual_root_path) as Node3D
	if visual_scene != null:
		var visual_instance: Node = visual_scene.instantiate()
		if visual_instance != null:
			add_child(visual_instance)
			if visual_instance is Node3D:
				_visual_root = visual_instance as Node3D
				if configured_visual_root != null:
					configured_visual_root.visible = false
	if _visual_root == null:
		_visual_root = configured_visual_root
	if _visual_root != null:
		_visual_initial_transform = _visual_root.transform
	var mesh_instance: MeshInstance3D = null
	if _visual_root is MeshInstance3D:
		mesh_instance = _visual_root as MeshInstance3D
	elif _visual_root != null:
		mesh_instance = _visual_root.find_child("Mesh", true, false) as MeshInstance3D
	if mesh_instance == null and mesh_instance_path != NodePath(""):
		mesh_instance = get_node_or_null(mesh_instance_path) as MeshInstance3D
	if mesh_instance != null:
		if custom_mesh != null:
			mesh_instance.mesh = custom_mesh
		if custom_material != null:
			mesh_instance.material_override = custom_material


func _resolve_home_trail() -> void:
	if home_trail_scene == null:
		return
	var trail_instance: Node = home_trail_scene.instantiate()
	if trail_instance == null:
		return
	add_child(trail_instance)
	_home_trail = trail_instance


func _configure_collection_shape() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		add_child(_collision_shape)
	var sphere: SphereShape3D = _collision_shape.shape as SphereShape3D
	if sphere == null:
		sphere = SphereShape3D.new()
		_collision_shape.shape = sphere
	sphere.radius = max(collection_radius, 0.1)


func _resolve_race_start() -> Node:
	if race_start_path != NodePath(""):
		var explicit_start: Node = get_node_or_null(race_start_path)
		if explicit_start == null and get_tree() != null and get_tree().current_scene != null:
			explicit_start = get_tree().current_scene.get_node_or_null(race_start_path)
		if explicit_start != null:
			return explicit_start
	if get_tree() == null:
		return null
	var nearest_start: Node3D = null
	var nearest_distance_squared: float = INF
	for candidate in get_tree().get_nodes_in_group("RaceStart"):
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not candidate.has_method("is_collection_race") or not bool(candidate.call("is_collection_race")):
			continue
		if race_id.strip_edges() != "":
			if not candidate.has_method("_get_race_id_value"):
				continue
			if String(candidate.call("_get_race_id_value")) != race_id.strip_edges():
				continue
		if not (candidate is Node3D):
			continue
		var candidate_3d: Node3D = candidate as Node3D
		var distance_squared: float = global_position.distance_squared_to(candidate_3d.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_start = candidate_3d
			nearest_distance_squared = distance_squared
	return nearest_start


func _sync_active_state() -> void:
	var is_active: bool = _configured_enabled and _race_enabled and not _collected_locally
	_set_collision_enabled(is_active)
	if not _homing:
		_set_visual_visible(is_active)


func _set_collision_enabled(is_enabled: bool) -> void:
	set_deferred("monitoring", is_enabled)
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", not is_enabled)


func _set_visual_visible(is_visible: bool) -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.visible = is_visible


func _spawn_touched_particles(player: Node3D, spawn_position: Vector3) -> void:
	if touched_particle_scene == null:
		return
	if player == null or not is_instance_valid(player):
		return
	var particle_instance: Node = touched_particle_scene.instantiate()
	if particle_instance == null:
		return
	particle_instance.add_to_group(&"LevelTransient")
	if _object_has_property(particle_instance, "twinkle_spawn_position"):
		particle_instance.set("twinkle_spawn_position", spawn_position)
	if _object_has_property(particle_instance, "twinkle_follow_parent"):
		particle_instance.set("twinkle_follow_parent", true)
	if particle_instance is Node3D:
		var particle_3d: Node3D = particle_instance as Node3D
		particle_3d.top_level = false
		particle_3d.position = player.to_local(spawn_position)
	player.add_child(particle_instance)
	_start_particles_recursive(particle_instance)
	var lifetime: float = max(touched_particle_lifetime, 0.05)
	if get_tree() != null:
		get_tree().create_timer(lifetime).timeout.connect(func() -> void:
			if particle_instance != null and is_instance_valid(particle_instance):
				particle_instance.queue_free()
		)


func _start_particles_recursive(node: Node) -> void:
	if node is GPUParticles3D:
		var gpu_particles: GPUParticles3D = node as GPUParticles3D
		gpu_particles.emitting = true
		gpu_particles.restart()
	elif node is CPUParticles3D:
		var cpu_particles: CPUParticles3D = node as CPUParticles3D
		cpu_particles.emitting = true
		cpu_particles.restart()
	for child in node.get_children():
		_start_particles_recursive(child)


func _play_local_sound(player: Node, stream: AudioStream, volume_db: float) -> void:
	if stream == null or not _is_local_player_authority(player):
		return
	var parent: Node = null
	if player != null and is_instance_valid(player):
		parent = player.get_viewport()
	if parent == null:
		parent = get_viewport()
	if parent == null and get_tree() != null:
		parent = get_tree().current_scene
	if parent == null:
		return
	var sound_player: AudioStreamPlayer = AudioStreamPlayer.new()
	sound_player.add_to_group(&"LevelTransient")
	sound_player.stream = stream
	sound_player.bus = sound_bus
	sound_player.volume_db = volume_db
	sound_player.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(sound_player)
	sound_player.finished.connect(Callable(sound_player, "queue_free"))
	sound_player.play()


func _is_local_player_authority(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()


func _object_has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property_data in object.get_property_list():
		if property_data is Dictionary and String(property_data.get("name", "")) == property_name:
			return true
	return false

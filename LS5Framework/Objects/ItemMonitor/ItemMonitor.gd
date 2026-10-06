@tool
extends Area3D
class_name ItemMonitor

const ATTACK_PASS_THROUGH_COLLISION_LAYER: int = 1 << 7
const SIZE_BASE_POSITION_META: StringName = &"_uniform_size_base_position"
const SIZE_BASE_SCALE_META: StringName = &"_uniform_size_base_scale"
const QUANTITY_RACE_REFRESH_INTERVAL: float = 0.25

signal monitor_broken(player: Node)
signal rewards_collected(player: Node)
signal reward_unhandled(player: Node, reward: ItemMonitorReward)

@export_group("Monitor")
## Uniform scale applied to the monitor visuals, collisions, and break effect.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = max(value, 0.01)
		if is_node_ready():
			_apply_size_preview()

## Rewards granted after this monitor breaks.
@export var rewards: Array[ItemMonitorReward] = []

@export_group("Item Display")
## Item-to-icon mappings used by the monitor display.
@export var item_icon_associations: Array[ItemIconAssociation] = [
	preload("res://LS5Framework/Resources/Items/RingItemIconAssociation.tres"),
	preload("res://LS5Framework/Resources/Items/SpeedShoesItemIconAssociation.tres"),
	preload("res://LS5Framework/Resources/Items/InvincibilityItemIconAssociation.tres"),
]
## Background frame composited behind the selected item icon.
@export var icon_background_texture: Texture2D = preload("res://LS5Framework/Images/Icons/ItemMonitor_Icon_Background.png")
## Counter-clockwise rotation speed of the intact item icon plane.
@export_range(0.0, 720.0, 0.1, "or_greater", "suffix:deg/s") var icon_rotation_speed_degrees: float = 90.0

@export_group("Interaction")
## Allows homing attacks to target this monitor while it is intact.
@export var homing_target_enabled: bool = true
## Maximum distance from the player for homing targeting. Zero uses the player targeting range.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var homing_target_max_distance: float = 0.0
## Breaks on player contact and disables the solid collider when enabled.
@export var allow_player_pass_through: bool = false
## Applies the standard upward attack bounce when an airborne player breaks the monitor.
@export var bounce_airborne_player: bool = true
## Delay between breakage and reward collection.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var collection_delay: float = 0.7
## Keeps the authored base mesh after the monitor breaks.
@export var leave_base_after_break: bool = false

@export_group("Regeneration")
## Restores the monitor after its rewards have been collected.
@export var respawn_enabled: bool = true
## Delay between reward collection and monitor regeneration.
@export_range(0.0, 600.0, 0.1, "or_greater", "suffix:s") var respawn_delay_sec: float = 60.0
## Reusable visual and audio feedback played when the monitor respawns.
@export var respawn_feedback: ObjectRespawnFeedback = preload("res://LS5Framework/Resources/Effects/ObjectRespawnFeedback.tres")

@export_group("Break Effect")
## Particle scene spawned when the monitor breaks.
@export var break_particle_scene: PackedScene = preload("res://LS5Framework/Objects/ItemMonitor/ItemMonitorBreakDust.tscn")
## Local offset used as the break particle spawn point.
@export var break_particle_offset: Vector3 = Vector3(0.0, 1.6, 0.0)
## Cleanup time for particle scenes that do not free themselves.
@export_range(0.05, 30.0, 0.05, "or_greater", "suffix:s") var break_particle_lifetime: float = 2.0

@export_group("Audio")
## Looping sound played while the monitor is intact. Empty disables the sound.
@export var intact_idle_sound: AudioStream
## Looping sound played after the monitor breaks. Empty disables the sound.
@export var broken_idle_sound: AudioStream
## One-shot sound played when the monitor breaks.
@export var break_sound: AudioStream = preload("res://LS5Framework/Sounds/Objects/Item_Monitor_Break.wav")
## Audio bus used by the monitor sounds.
@export var sound_bus: StringName = &"SFX"
## Volume applied to the monitor sounds.
@export var sound_volume_db: float = 0.0
## Pitch scale applied to the monitor sounds.
@export_range(0.01, 4.0, 0.01, "or_greater") var sound_pitch_scale: float = 1.0
## Maximum audible distance for the monitor sounds.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var sound_max_distance: float = 65.0

## Detects player contact around the monitor body.
@onready var _touch_shape: CollisionShape3D = $TouchShape
## Provides solid, non-alignable collision while the monitor is intact.
@onready var _solid_body: StaticBody3D = $SolidBody
## Defines the monitor's simple solid collision volume.
@onready var _solid_shape: CollisionShape3D = $SolidBody/SolidShape
## Contains the complete authored monitor model.
@onready var _visual_root: Node3D = $VisualRoot
## Contains the imported model parts used by the break state.
@onready var _monitor_model: Node3D = $VisualRoot/MonitorModel
## Contains reward displays inside the glass.
@onready var _item_display_root: Node3D = $VisualRoot/ItemDisplays
## Displays the first configured reward with a matching item icon association.
@onready var _icon_display: MeshInstance3D = $VisualRoot/ItemDisplays/IconDisplay
## Displays the ring quantity on the front of the rotating item icon.
@onready var _quantity_label_front: Label3D = $VisualRoot/ItemDisplays/IconDisplay/QuantityLabelFront
## Displays the ring quantity on the back of the rotating item icon.
@onready var _quantity_label_back: Label3D = $VisualRoot/ItemDisplays/IconDisplay/QuantityLabelBack
## Plays the looping sound for the current monitor state.
@onready var _idle_audio: AudioStreamPlayer3D = $IdleAudio
## Plays the one-shot monitor break sound.
@onready var _break_audio: AudioStreamPlayer3D = $BreakAudio
## Awards score to the player that breaks this monitor.
@onready var _score_award: ScoreAward = get_node_or_null("ScoreAward") as ScoreAward
## Enables icon updates while the monitor display is on screen.
@onready var _display_visibility: VisibleOnScreenNotifier3D = get_node_or_null("VisualRoot/DisplayVisibility") as VisibleOnScreenNotifier3D

var _broken: bool = false
var _collection_completed: bool = false
var _state_generation: int = 0
var _solid_collision_layer: int = 0
var _solid_collision_mask: int = 0
var _monitor_part_visibility: Dictionary = {}
var _display_reward: ItemMonitorReward = null
var _quantity_race_refresh_remaining: float = 0.0
var _level_prepared: bool = false
var _gameplay_activated: bool = false
var _managed_preparation: bool = false
var _cosmetics_activated: bool = false
var _touching_players: Array[Node3D] = []

static var _display_material_cache: Dictionary = {}
static var _looping_audio_cache: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_size_preview()
		set_process(false)
		set_physics_process(false)
		return
	if not _level_prepared:
		prepare_for_level({})
	if not _gameplay_activated and not _managed_preparation:
		activate_for_gameplay({})
		activate_level_cosmetics({})


func prepare_for_level(context: Dictionary) -> bool:
	_managed_preparation = _managed_preparation or bool(context.get("managed", false))
	if _level_prepared:
		return true
	_resolve_preparation_nodes()
	_apply_size_preview()
	_cache_intact_state()
	_display_reward = _find_display_reward()
	_setup_audio()
	_level_prepared = true
	return true


func activate_for_gameplay(_context: Dictionary) -> bool:
	if _gameplay_activated:
		return true
	monitoring = true
	monitorable = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_set_intact_collision_state()
	_configure_monitor_quantity(_display_reward)
	_set_homing_target_registered(homing_target_enabled)
	set_process(false)
	set_physics_process(false)
	_gameplay_activated = true
	_managed_preparation = false
	return true


func activate_level_cosmetics(_context: Dictionary) -> bool:
	if _cosmetics_activated:
		return true
	_configure_icon_display()
	_create_reward_displays()
	_set_idle_audio_stream(intact_idle_sound)
	_cosmetics_activated = true
	if _display_visibility:
		if not _display_visibility.screen_entered.is_connected(_update_cosmetic_processing):
			_display_visibility.screen_entered.connect(_update_cosmetic_processing)
		if not _display_visibility.screen_exited.is_connected(_update_cosmetic_processing):
			_display_visibility.screen_exited.connect(_update_cosmetic_processing)
	_update_cosmetic_processing()
	return true


func _resolve_preparation_nodes() -> void:
	_touch_shape = get_node_or_null("TouchShape") as CollisionShape3D
	_solid_body = get_node_or_null("SolidBody") as StaticBody3D
	_solid_shape = get_node_or_null("SolidBody/SolidShape") as CollisionShape3D
	_visual_root = get_node_or_null("VisualRoot") as Node3D
	_monitor_model = get_node_or_null("VisualRoot/MonitorModel") as Node3D
	_item_display_root = get_node_or_null("VisualRoot/ItemDisplays") as Node3D
	_icon_display = get_node_or_null("VisualRoot/ItemDisplays/IconDisplay") as MeshInstance3D
	_quantity_label_front = get_node_or_null(
		"VisualRoot/ItemDisplays/IconDisplay/QuantityLabelFront"
	) as Label3D
	_quantity_label_back = get_node_or_null(
		"VisualRoot/ItemDisplays/IconDisplay/QuantityLabelBack"
	) as Label3D
	_idle_audio = get_node_or_null("IdleAudio") as AudioStreamPlayer3D
	_break_audio = get_node_or_null("BreakAudio") as AudioStreamPlayer3D
	_score_award = get_node_or_null("ScoreAward") as ScoreAward
	_display_visibility = get_node_or_null("VisualRoot/DisplayVisibility") as VisibleOnScreenNotifier3D


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_set_homing_target_registered(false)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _broken or _icon_display == null or not _icon_display.visible:
		return
	if (
		_display_reward != null
		and _display_reward.reward_type == ItemMonitorReward.RewardType.RANDOM_RINGS
		and _display_reward.fixed_amount_in_ring_race
	):
		_quantity_race_refresh_remaining = max(_quantity_race_refresh_remaining - delta, 0.0)
		if _quantity_race_refresh_remaining <= 0.0:
			_quantity_race_refresh_remaining = QUANTITY_RACE_REFRESH_INTERVAL
			_configure_monitor_quantity(_display_reward)
	var rotation_step: float = deg_to_rad(icon_rotation_speed_degrees) * delta
	_icon_display.rotate_y(rotation_step)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _broken or allow_player_pass_through:
		return
	for index: int in range(_touching_players.size() - 1, -1, -1):
		if not is_instance_valid(_touching_players[index]):
			_touching_players.remove_at(index)
			continue
		var body: Node3D = _touching_players[index]
		if _is_supported_player(body) and _is_player_attacking(body):
			_break_monitor(body)
			return
	if _touching_players.is_empty():
		set_physics_process(false)


func _update_cosmetic_processing() -> void:
	var display_active: bool = _cosmetics_activated and not _broken and _icon_display and _icon_display.visible
	if _display_visibility:
		display_active = display_active and _display_visibility.is_on_screen()
	var dynamic_quantity: bool = (
		_display_reward
		and _display_reward.reward_type == ItemMonitorReward.RewardType.RANDOM_RINGS
		and _display_reward.fixed_amount_in_ring_race
	)
	set_process(display_active and (icon_rotation_speed_degrees > 0.0 or dynamic_quantity))
	if display_active:
		_configure_monitor_quantity(_display_reward)


func _apply_size_preview() -> void:
	var uniform_size: float = max(size, 0.01)
	_apply_size_to_node(get_node_or_null("TouchShape") as Node3D, uniform_size)
	_apply_size_to_node(get_node_or_null("SolidBody/SolidShape") as Node3D, uniform_size)
	_apply_size_to_node(get_node_or_null("VisualRoot") as Node3D, uniform_size)


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
	if _broken or not _is_supported_player(body):
		return
	if allow_player_pass_through or _is_player_attacking(body):
		_break_monitor(body)
		return
	if not _touching_players.has(body):
		_touching_players.append(body)
	set_physics_process(true)


func _on_body_exited(body: Node3D) -> void:
	_touching_players.erase(body)
	if _touching_players.is_empty():
		set_physics_process(false)


func _break_monitor(player: Node3D) -> void:
	if player.has_method("claim_kick_contact") and not bool(player.call("claim_kick_contact", self)):
		return
	if _broken:
		return
	_state_generation += 1
	_broken = true
	_set_homing_target_registered(false)
	_disable_collision()
	_set_broken_visual_state()
	_spawn_break_particles()
	_set_idle_audio_stream(broken_idle_sound)
	_play_break_sound()
	if _score_award:
		_score_award.award(player)
	if bounce_airborne_player and _is_player_airborne(player):
		_bounce_player(player)
	monitor_broken.emit(player)
	if collection_delay <= 0.0 or get_tree() == null:
		_collect_rewards(player, _state_generation)
		return
	var collection_generation: int = _state_generation
	var collection_timer: SceneTreeTimer = get_tree().create_timer(collection_delay)
	collection_timer.timeout.connect(_collect_rewards.bind(player, collection_generation))


func _collect_rewards(player: Node, expected_generation: int = -1) -> void:
	if expected_generation >= 0 and expected_generation != _state_generation:
		return
	if _collection_completed or not _broken:
		return
	_collection_completed = true
	if player != null and is_instance_valid(player):
		var notified_item_ids: Dictionary = {}
		for reward: ItemMonitorReward in rewards:
			if reward == null or not reward.is_configured():
				continue
			if not reward.grant_to(player):
				reward_unhandled.emit(player, reward)
				continue
			var item_id: StringName = reward.get_item_id()
			if item_id != &"" and not notified_item_ids.has(item_id):
				notified_item_ids[item_id] = true
				if player.has_method("notify_item_collected"):
					player.call("notify_item_collected", item_id, reward.get_notification_amount())
				elif player.has_method("play_item_collection_sound"):
					player.call("play_item_collection_sound", item_id)
		rewards_collected.emit(player)
	if respawn_enabled:
		_start_respawn_timer()
	elif not leave_base_after_break:
		_queue_free_after_break_sound()


func _is_supported_player(body: Node) -> bool:
	if body == null or not (body is CharacterBody3D):
		return false
	if body.has_meta("is_buddy") and body.get_meta("is_buddy"):
		return false
	if not body.is_in_group("Player") and not body.is_in_group("player"):
		return false
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		return body.is_multiplayer_authority()
	return true


func _is_player_attacking(player: Node) -> bool:
	if not player.has_method("is_attack_active"):
		return false
	var attack_result: Variant = player.call("is_attack_active")
	return attack_result is bool and bool(attack_result)


func _is_player_airborne(player: Node) -> bool:
	if _object_has_property(player, "attached"):
		return not player.get("attached")
	if player is CharacterBody3D:
		return not (player as CharacterBody3D).is_on_floor()
	return false


func _bounce_player(player: Node) -> void:
	if player.has_method("apply_enemy_attack_bounce"):
		player.call("apply_enemy_attack_bounce", false, self)


func on_homing_hit(player: Node, _jump_held: bool) -> bool:
	if _broken or not homing_target_enabled:
		return false
	if player is Node3D:
		_break_monitor(player as Node3D)
		if not bounce_airborne_player:
			_finish_homing_without_bounce(player)
	return true


func get_homing_target_position(_origin: Vector3) -> Vector3:
	if _touch_shape != null:
		return _touch_shape.global_position
	return global_position


func _finish_homing_without_bounce(player: Node) -> void:
	if not _object_has_property(player, &"velocity"):
		return
	var up: Vector3 = Vector3.UP
	if player.has_method("_get_gravity_up"):
		var gravity_up: Variant = player.call("_get_gravity_up")
		if gravity_up is Vector3:
			up = (gravity_up as Vector3).normalized()
	var current_velocity: Vector3 = player.get("velocity")
	var upward_speed: float = current_velocity.dot(up)
	if upward_speed > 0.0:
		player.set("velocity", current_velocity - up * upward_speed)
	if player.has_method("cancel_homing_attack"):
		player.call("cancel_homing_attack", false)


func _set_homing_target_registered(registered: bool) -> void:
	var should_register: bool = registered and not _broken
	if should_register:
		if not is_in_group("HomingTarget"):
			add_to_group("HomingTarget")
		var manager: Node = get_node_or_null("/root/HomingTargetManager")
		if manager != null and manager.has_method("register"):
			manager.call("register", self)
		return
	if is_in_group("HomingTarget"):
		remove_from_group("HomingTarget")
	var manager: Node = get_node_or_null("/root/HomingTargetManager")
	if manager != null and manager.has_method("unregister"):
		manager.call("unregister", self)


func _set_intact_collision_state() -> void:
	if _touch_shape != null:
		_touch_shape.set_deferred("disabled", false)
	if _solid_body != null:
		_solid_body.collision_layer = 0 if allow_player_pass_through else _solid_collision_layer
		_solid_body.collision_mask = _solid_collision_mask
	if _solid_shape != null:
		_solid_shape.set_deferred("disabled", allow_player_pass_through)


func _disable_collision() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_touching_players.clear()
	set_process(false)
	set_physics_process(false)
	if _touch_shape != null:
		_touch_shape.set_deferred("disabled", true)
	if _solid_body != null:
		_solid_body.collision_layer = 0
		_solid_body.collision_mask = 0
	if _solid_shape != null:
		_solid_shape.set_deferred("disabled", true)


func _set_broken_visual_state() -> void:
	if _item_display_root != null:
		_item_display_root.visible = false
	if not leave_base_after_break:
		if _visual_root != null:
			_visual_root.visible = false
		return
	if _monitor_model == null:
		return
	for child: Node in _monitor_model.get_children():
		if child is Node3D:
			(child as Node3D).visible = child.name == &"Base"


func _cache_intact_state() -> void:
	if _solid_body != null:
		_solid_collision_layer = _solid_body.collision_layer
		if _solid_collision_layer == 0:
			_solid_collision_layer = ATTACK_PASS_THROUGH_COLLISION_LAYER
		_solid_collision_mask = _solid_body.collision_mask
	if _monitor_model == null:
		return
	_monitor_part_visibility.clear()
	for child: Node in _monitor_model.get_children():
		if child is Node3D:
			_monitor_part_visibility[child] = (child as Node3D).visible


func _restore_intact_visual_state() -> void:
	if _visual_root != null:
		_visual_root.visible = true
	if _item_display_root != null:
		_item_display_root.visible = true
	for part: Variant in _monitor_part_visibility:
		if part is Node3D and is_instance_valid(part):
			(part as Node3D).visible = bool(_monitor_part_visibility[part])


func _start_respawn_timer() -> void:
	var respawn_generation: int = _state_generation
	if respawn_delay_sec <= 0.0 or get_tree() == null:
		call_deferred("_finish_respawn_wait", respawn_generation)
		return
	var respawn_timer: SceneTreeTimer = get_tree().create_timer(respawn_delay_sec)
	respawn_timer.timeout.connect(_finish_respawn_wait.bind(respawn_generation))


func _finish_respawn_wait(expected_generation: int) -> void:
	if expected_generation != _state_generation or not _broken or not respawn_enabled:
		return
	_respawn_monitor(true)


func _respawn_monitor(play_feedback: bool) -> void:
	if not _broken and not _collection_completed:
		return
	_state_generation += 1
	_broken = false
	if _score_award:
		_score_award.reset_award()
	_collection_completed = false
	_set_homing_target_registered(homing_target_enabled)
	monitorable = true
	set_deferred("monitoring", true)
	_set_intact_collision_state()
	_restore_intact_visual_state()
	if _break_audio != null:
		_break_audio.stop()
	_set_idle_audio_stream(intact_idle_sound)
	_touching_players.clear()
	_update_cosmetic_processing()
	set_physics_process(false)
	if play_feedback and respawn_feedback != null:
		var feedback_root: Node3D = _visual_root if _visual_root != null else _monitor_model
		respawn_feedback.play(feedback_root)


func reset_for_race_restart() -> void:
	_respawn_monitor(true)


func _create_reward_displays() -> void:
	if _item_display_root == null:
		return
	for reward: ItemMonitorReward in rewards:
		if reward == null or not reward.is_configured() or reward.display_scene == null:
			continue
		var display_instance: Node = reward.display_scene.instantiate()
		if not (display_instance is Node3D):
			if display_instance != null:
				display_instance.queue_free()
			continue
		var display_3d: Node3D = display_instance as Node3D
		_item_display_root.add_child(display_3d)
		display_3d.position = reward.display_position
		display_3d.rotation_degrees = reward.display_rotation_degrees
		display_3d.scale = reward.display_scale


func _configure_icon_display() -> void:
	if _icon_display == null:
		return
	_icon_display.visible = false
	_set_monitor_quantity_text("")
	_display_reward = _find_display_reward()
	if _display_reward == null:
		return
	var icon_texture: Texture2D = _find_item_icon(_display_reward.get_item_id())
	if icon_texture == null or icon_background_texture == null:
		return
	var display_material: ShaderMaterial = _icon_display.get_active_material(0) as ShaderMaterial
	if display_material == null:
		return
	var prepared_material: ShaderMaterial = _get_prepared_display_material(
		display_material,
		icon_background_texture,
		icon_texture
	)
	if prepared_material == null:
		return
	_icon_display.material_override = prepared_material
	_configure_monitor_quantity(_display_reward)
	_icon_display.visible = true


func _get_prepared_display_material(
		source: ShaderMaterial,
		background_texture: Texture2D,
		item_texture: Texture2D
	) -> ShaderMaterial:
	if Engine.is_editor_hint():
		var editor_material: ShaderMaterial = source.duplicate() as ShaderMaterial
		if editor_material != null:
			editor_material.set_shader_parameter(&"background_texture", background_texture)
			editor_material.set_shader_parameter(&"item_texture", item_texture)
		return editor_material
	var cache_key: String = "%d|%d|%d" % [
		source.get_instance_id(),
		background_texture.get_instance_id(),
		item_texture.get_instance_id(),
	]
	if LevelPreparationManager.is_cache_enabled():
		var cached_value: Variant = _display_material_cache.get(cache_key)
		if cached_value is ShaderMaterial:
			return cached_value as ShaderMaterial
	var prepared_material: ShaderMaterial = source.duplicate() as ShaderMaterial
	if prepared_material == null:
		return null
	prepared_material.set_shader_parameter(&"background_texture", background_texture)
	prepared_material.set_shader_parameter(&"item_texture", item_texture)
	if LevelPreparationManager.is_cache_enabled():
		_display_material_cache[cache_key] = prepared_material
	return prepared_material


func _find_display_reward() -> ItemMonitorReward:
	for reward: ItemMonitorReward in rewards:
		if reward == null or not reward.is_configured():
			continue
		var reward_item_id: StringName = reward.get_item_id()
		if reward_item_id != &"" and _find_item_icon(reward_item_id) != null:
			return reward
	return null


func _find_item_icon(item_id: StringName) -> Texture2D:
	for association: ItemIconAssociation in item_icon_associations:
		if association != null and association.item_id == item_id and association.icon_texture != null:
			return association.icon_texture
	return null


func _configure_monitor_quantity(reward: ItemMonitorReward) -> void:
	if reward == null:
		_set_monitor_quantity_text("")
		return
	_set_monitor_quantity_text(reward.get_monitor_quantity_text(_get_local_player()))


func _set_monitor_quantity_text(quantity_text: String) -> void:
	for quantity_label: Label3D in [_quantity_label_front, _quantity_label_back]:
		if quantity_label == null:
			continue
		if quantity_label.text != quantity_text:
			quantity_label.text = quantity_text
		var quantity_visible: bool = not quantity_text.is_empty()
		if quantity_label.visible != quantity_visible:
			quantity_label.visible = quantity_visible


func _get_local_player() -> Node:
	if get_tree() == null:
		return null
	var players: Array[Node] = get_tree().get_nodes_in_group("Player")
	var online: bool = multiplayer != null and multiplayer.has_multiplayer_peer()
	for player: Node in players:
		if player != null and is_instance_valid(player) and (not online or player.is_multiplayer_authority()):
			return player
	return null


func _setup_audio() -> void:
	_configure_audio_player(_idle_audio)
	_configure_audio_player(_break_audio)
	if _idle_audio != null and not _idle_audio.finished.is_connected(_on_idle_audio_finished):
		_idle_audio.finished.connect(_on_idle_audio_finished)
	if _idle_audio != null:
		_idle_audio.stream = _prepare_looping_audio_stream(intact_idle_sound)


func _configure_audio_player(player: AudioStreamPlayer3D) -> void:
	if player == null:
		return
	player.bus = sound_bus
	player.volume_db = sound_volume_db
	player.pitch_scale = max(sound_pitch_scale, 0.01)
	player.max_distance = max(sound_max_distance, 0.0)


func _set_idle_audio_stream(stream: AudioStream) -> void:
	if _idle_audio == null:
		return
	_idle_audio.stop()
	_idle_audio.stream = _prepare_looping_audio_stream(stream)
	if _idle_audio.stream != null:
		_idle_audio.play()


func _prepare_looping_audio_stream(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	if not Engine.is_editor_hint() and LevelPreparationManager.is_cache_enabled():
		var cached_value: Variant = _looping_audio_cache.get(stream.get_instance_id())
		if cached_value is AudioStream:
			return cached_value as AudioStream
	var prepared_stream: AudioStream = stream.duplicate() as AudioStream
	if prepared_stream == null:
		return stream
	if _object_has_property(prepared_stream, &"loop_mode"):
		prepared_stream.set("loop_mode", 1)
	elif _object_has_property(prepared_stream, &"loop"):
		prepared_stream.set("loop", true)
	if not Engine.is_editor_hint() and LevelPreparationManager.is_cache_enabled():
		_looping_audio_cache[stream.get_instance_id()] = prepared_stream
	return prepared_stream


func _play_break_sound() -> void:
	if _break_audio == null or break_sound == null:
		return
	_break_audio.stop()
	_break_audio.stream = break_sound
	_break_audio.play()


func _on_idle_audio_finished() -> void:
	if _idle_audio != null and _idle_audio.stream != null:
		_idle_audio.play()


func _queue_free_after_break_sound() -> void:
	if _break_audio == null or not _break_audio.playing:
		queue_free()
		return
	var free_callable: Callable = Callable(self, "queue_free")
	if not _break_audio.finished.is_connected(free_callable):
		_break_audio.finished.connect(free_callable, CONNECT_ONE_SHOT)


func _spawn_break_particles() -> void:
	if break_particle_scene == null or get_tree() == null:
		return
	var particle_instance: Node = break_particle_scene.instantiate()
	if particle_instance == null:
		return
	particle_instance.add_to_group(&"LevelTransient")
	var particle_parent: Node = get_tree().current_scene
	if particle_parent == null:
		particle_parent = get_parent()
	if particle_parent == null:
		particle_instance.queue_free()
		return
	particle_parent.add_child(particle_instance)
	if particle_instance is Node3D:
		var particle_3d: Node3D = particle_instance as Node3D
		var uniform_size: float = max(size, 0.01)
		particle_3d.global_transform = Transform3D(
			global_basis.scaled(Vector3.ONE * uniform_size),
			global_transform * (break_particle_offset * uniform_size)
		)
	_start_particles_recursive(particle_instance)
	var cleanup_timer: SceneTreeTimer = get_tree().create_timer(max(break_particle_lifetime, 0.05))
	cleanup_timer.timeout.connect(func() -> void:
		if particle_instance != null and is_instance_valid(particle_instance):
			particle_instance.queue_free()
	)


func _start_particles_recursive(node: Node) -> void:
	if node is GPUParticles3D:
		var gpu_particles: GPUParticles3D = node as GPUParticles3D
		gpu_particles.restart()
		gpu_particles.emitting = true
	elif node is CPUParticles3D:
		var cpu_particles: CPUParticles3D = node as CPUParticles3D
		cpu_particles.restart()
		cpu_particles.emitting = true
	for child: Node in node.get_children():
		_start_particles_recursive(child)


func _object_has_property(object: Object, property_name: StringName) -> bool:
	if object == null:
		return false
	for property_data: Dictionary in object.get_property_list():
		if StringName(property_data.get("name", &"")) == property_name:
			return true
	return false


func receive_kick_attack(player: Node3D) -> bool:
	if _broken or not _is_supported_player(player) or not _is_player_attacking(player):
		return false
	_break_monitor(player)
	return _broken

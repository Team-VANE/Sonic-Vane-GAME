@tool
extends CharacterBody3D
class_name Enemy

const SIZE_BASE_POSITION_META: StringName = &"_enemy_size_base_position"
const SIZE_BASE_SCALE_META: StringName = &"_enemy_size_base_scale"
const SURFACE_METADATA = preload("res://LS5Framework/Scripts/World/SurfaceBehaviorMetadata.gd")

@export_group("General")
## Enables this enemy and all of its configured functionality.
@export var enabled: bool = true
## Enables perception, decisions, attacks, and active movement while preserving gravity and damage.
@export var active: bool = true
## Uniform scale applied to configured visual, collision, hurtbox, and socket nodes.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = max(value, 0.01)
		if is_node_ready():
			_apply_size()
## Nodes whose local position and scale follow the uniform enemy size.
@export var size_target_paths: Array[NodePath] = []

@export_group("Player Boundary")
## Preserves player speed while sliding along this enemy's solid boundary.
@export var preserve_player_boundary_momentum: bool = true

@export_group("Environmental Hazards")
## Defeats this enemy immediately when it enters a death plane.
@export var die_in_death_planes: bool = true
## Defeats this enemy immediately when it enters a water volume.
@export var die_in_water: bool = true
## Time after respawning before overlapping environmental hazards are re-evaluated.
@export var environmental_hazard_respawn_grace_sec: float = 0.25

@export_group("Fall Impact Damage")
## Enables damage from sufficiently fast collisions with configured surfaces.
@export var fall_damage_enabled: bool = false
## Surface layers that can cause fall-impact damage. Zero accepts every reported surface.
@export_flags_3d_physics var fall_damage_surface_mask: int = 1
## Effective impact speed required to apply fall damage.
@export var fall_damage_minimum_speed: float = 32.0
## Effective impact speed that defeats the enemy immediately. Zero disables it.
@export var fall_damage_death_speed: float = 55.0
## Damage applied by impacts below the instant-death threshold.
@export var fall_damage_amount: int = 1
## Minimum impact strength retained as the collision becomes more glancing.
@export_range(0.0, 1.0, 0.01) var fall_damage_slope_bias: float = 0.15
## Minimum fraction of total velocity directed into the collision surface.
@export_range(0.0, 1.0, 0.01) var fall_damage_minimum_opposition: float = 0.2
## Delay before another surface impact can damage this enemy.
@export var fall_damage_cooldown_sec: float = 0.2
## Prints captured impact values and filtering decisions for this enemy.
@export var fall_damage_debug_enabled: bool = false

@export_group("Respawn Presentation")
## Reusable visual and audio feedback played when this enemy respawns.
@export var respawn_feedback: ObjectRespawnFeedback = preload("res://LS5Framework/Resources/Effects/ObjectRespawnFeedback.tres")

@export_group("Components")
## Health component used for damage and defeat state.
@export var health_component_path: NodePath = NodePath("Components/Health")
## Gravity receiver used by locomotion and external gravity systems.
@export var gravity_component_path: NodePath = NodePath("Components/Gravity")
## Perception component that acquires targets.
@export var perception_component_path: NodePath = NodePath("Components/Perception")
## Brain component that converts targets into movement and attack intent.
@export var brain_component_path: NodePath = NodePath("Components/Brain")
## Active locomotion component used to move this CharacterBody3D.
@export var locomotion_component_path: NodePath = NodePath("Locomotion")
## Attack controller containing modular enemy attacks.
@export var attack_controller_path: NodePath = NodePath("Attacks")
## Homing and attack-magnetism target point.
@export var targetable_component_path: NodePath = NodePath("Targetable")
## Collision component responsible for disabling and restoring collision objects.
@export var collision_component_path: NodePath = NodePath("Components/Collision")
## Hurtbox component responsible for contact and incoming impact interactions.
@export var hurtbox_component_path: NodePath = NodePath("Hurtbox")
## Animation and custom visual adapter component.
@export var animation_component_path: NodePath = NodePath("Components/Animation")
## Audio cue component used by actor and attack events.
@export var audio_component_path: NodePath = NodePath("Components/Audio")
## Defeat effect and fracture component.
@export var defeat_effects_component_path: NodePath = NodePath("Components/DefeatEffects")
## Respawn timer and spawn-transform component.
@export var respawn_component_path: NodePath = NodePath("Components/Respawn")
## Score component awarded when this enemy is defeated.
@export var score_award_path: NodePath = NodePath("ScoreAward")
## Root containing optional reusable enemy components.
@export var optional_components_root_path: NodePath = NodePath("Components/Optional")

var _health: ActorHealth = null
var _gravity: ActorGravityReceiver3D = null
var _perception: EnemyPerception = null
var _brain: EnemyBrain = null
var _locomotion: EnemyLocomotion = null
var _attacks: EnemyAttackController = null
var _targetable: ActorTargetable3D = null
var _collision: ActorCollisionController3D = null
var _hurtbox: ActorHurtbox3D = null
var _animation: EnemyAnimationDriver = null
var _audio: ActorAudioCues3D = null
var _defeat_effects: ActorDefeatEffects3D = null
var _respawn: ActorRespawnComponent3D = null
var _score_award: ScoreAward = null
var _optional_components: Array[EnemyOptionalComponent] = []
var _intent: EnemyIntent = EnemyIntent.new()
var _spawn_transform: Transform3D = Transform3D.IDENTITY
var _spawn_active: bool = true
var _dead: bool = false
var _environmental_hazard_immunity_timer: float = 0.0
var _pending_environmental_hazards: Dictionary = {}
var _fall_damage_cooldown_timer: float = 0.0
var _level_prepared: bool = false
var _gameplay_activated: bool = false
var _managed_preparation: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_size()
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
	_apply_size()
	set_meta(&"npc_affiliation", &"enemy")
	set_meta(SURFACE_METADATA.PRESERVE_PLAYER_MOMENTUM, preserve_player_boundary_momentum)
	add_to_group(&"NPCActor")
	_resolve_components()
	_level_prepared = true
	return true


func activate_for_gameplay(_context: Dictionary) -> bool:
	if _gameplay_activated:
		return true
	_spawn_transform = global_transform
	_spawn_active = active
	if _respawn:
		_respawn.capture_spawn(_spawn_transform)
	_initialize_components()
	_gameplay_activated = true
	_managed_preparation = false
	return true


func _physics_process(delta: float) -> void:
	if not enabled:
		velocity = Vector3.ZERO
		if _audio:
			_audio.set_idle_active(false)
		return
	if _health:
		_health.physics_tick(delta)
	_update_environmental_hazard_immunity(delta)
	_fall_damage_cooldown_timer = max(_fall_damage_cooldown_timer - delta, 0.0)
	if _gravity:
		_gravity.physics_tick(delta)
	if _collision:
		_collision.physics_tick(delta)
	if _hurtbox:
		_hurtbox.physics_tick(delta)
	for component: EnemyOptionalComponent in _optional_components:
		if component != null and is_instance_valid(component):
			component.physics_tick(delta)
	if _dead:
		if _respawn and _respawn.physics_tick(delta):
			_respawn_enemy()
		_update_presentation(delta)
		return
	if _attacks:
		_attacks.physics_tick(delta)
	if active and _perception:
		_perception.physics_tick(delta)
	elif _perception:
		_perception.clear()
	var target: Node3D = _perception.get_target() if _perception else null
	if active and _brain:
		_brain.physics_tick(delta, self, target, _spawn_transform.origin, _attacks, _intent)
	else:
		_intent.clear()
	if _attacks and _intent.attack_requested:
		_attacks.try_start(target)
	if _attacks and _attacks.is_attacking():
		_intent.movement_locked = _attacks.locks_movement()
		_intent.facing_locked = _attacks.locks_facing()
		if _intent.movement_locked:
			_intent.move_direction = Vector3.ZERO
			_intent.speed_ratio = 0.0
	if _locomotion:
		_locomotion.capture_impact_contacts = fall_damage_enabled
		_locomotion.physics_tick(delta, _intent)
		_process_fall_impact_damage()
	if _targetable:
		_targetable.physics_tick(delta, velocity.length_squared() > 0.000001)
	if _audio:
		_audio.set_idle_active(active)
	_update_presentation(delta)


func apply_damage(amount: int = 1, source: Node = null) -> bool:
	if not enabled or _dead or _health == null:
		return false
	return _health.apply_damage(amount, source)


func defeat(source: Node = null, bypass_invulnerability: bool = true) -> bool:
	if not enabled or _dead or _health == null:
		return false
	return _health.kill(source, bypass_invulnerability)


func apply_environmental_hazard(hazard_type: StringName, source: Node = null) -> bool:
	if not enabled or _dead or _health == null:
		return false
	match hazard_type:
		&"death_plane":
			if not die_in_death_planes:
				return false
		&"water":
			if not die_in_water:
				return false
		_:
			return false
	if _environmental_hazard_immunity_timer > 0.0:
		if source != null and is_instance_valid(source):
			_pending_environmental_hazards[source.get_instance_id()] = {
				"hazard_type": hazard_type,
				"source": weakref(source),
			}
		return false
	return _health.kill(source, true)


func on_homing_hit(player: Node, _jump_held: bool) -> bool:
	apply_damage(1, player)
	return false


func is_dead() -> bool:
	return _dead


func disable_collision_for(duration: float) -> void:
	if _collision:
		_collision.disable_for(duration)


func notify_projectile_fired() -> void:
	if _audio:
		_audio.play_cue(&"projectile")


func get_dynamic_impact_velocity() -> Vector3:
	return Vector3.ZERO if _dead else velocity


func is_gravity_pull_enabled() -> bool:
	return _gravity != null and _gravity.is_gravity_pull_enabled()


func get_gravity_up() -> Vector3:
	return _gravity.get_gravity_up() if _gravity else Vector3.UP


func get_gravity_down() -> Vector3:
	return -get_gravity_up()


func get_effective_gravity_strength() -> float:
	return _gravity.get_effective_gravity_strength() if _gravity else 0.0


func get_gravity_acceleration_vector() -> Vector3:
	return _gravity.get_gravity_acceleration_vector() if _gravity else Vector3.ZERO


func apply_gravity_modifier(
	source: Object,
	new_gravity_up: Vector3,
	gravity_multiplier: float,
	duration: float,
	priority: int,
	blend_with_planetary: bool,
	clear_on_death: bool,
	clear_on_respawn: bool,
	clear_on_level_restart: bool,
	clear_on_race_cleanup: bool
) -> void:
	if _gravity:
		_gravity.apply_gravity_modifier(
			source,
			new_gravity_up,
			gravity_multiplier,
			duration,
			priority,
			blend_with_planetary,
			clear_on_death,
			clear_on_respawn,
			clear_on_level_restart,
			clear_on_race_cleanup
		)


func remove_gravity_modifier(source: Object) -> void:
	if _gravity:
		_gravity.remove_gravity_modifier(source)


func register_planetary_gravity_source(source: Node) -> void:
	if _gravity:
		_gravity.register_planetary_gravity_source(source)


func unregister_planetary_gravity_source(source: Node) -> void:
	if _gravity:
		_gravity.unregister_planetary_gravity_source(source)


func clear_gravity_state(reason: StringName = &"all", clear_planetary: bool = true) -> void:
	if _gravity:
		_gravity.clear_gravity_state(reason, clear_planetary)


func reset_for_race_restart() -> void:
	if _respawn:
		_respawn.cancel()
	global_transform = _spawn_transform
	_reset_components(&"race_cleanup")


func _resolve_components() -> void:
	_health = get_node_or_null(health_component_path) as ActorHealth
	_gravity = get_node_or_null(gravity_component_path) as ActorGravityReceiver3D
	_perception = get_node_or_null(perception_component_path) as EnemyPerception
	_brain = get_node_or_null(brain_component_path) as EnemyBrain
	_locomotion = get_node_or_null(locomotion_component_path) as EnemyLocomotion
	_attacks = get_node_or_null(attack_controller_path) as EnemyAttackController
	_targetable = get_node_or_null(targetable_component_path) as ActorTargetable3D
	_collision = get_node_or_null(collision_component_path) as ActorCollisionController3D
	_hurtbox = get_node_or_null(hurtbox_component_path) as ActorHurtbox3D
	_animation = get_node_or_null(animation_component_path) as EnemyAnimationDriver
	_audio = get_node_or_null(audio_component_path) as ActorAudioCues3D
	_defeat_effects = get_node_or_null(defeat_effects_component_path) as ActorDefeatEffects3D
	_respawn = get_node_or_null(respawn_component_path) as ActorRespawnComponent3D
	_score_award = get_node_or_null(score_award_path) as ScoreAward
	_optional_components.clear()
	var optional_root: Node = get_node_or_null(optional_components_root_path)
	if optional_root != null:
		_collect_optional_components(optional_root)


func _initialize_components() -> void:
	if _health:
		_health.initialize()
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
	if _gravity:
		_gravity.setup(self)
	if _perception:
		_perception.setup(self)
	if _brain:
		_brain.state_changed.connect(_on_brain_state_changed)
	if _locomotion:
		_locomotion.setup(self)
	if _attacks:
		_attacks.setup(self)
		_attacks.attack_started.connect(_on_attack_started)
	if _targetable:
		_targetable.setup(self)
	if _collision:
		_collision.setup(self)
	if _hurtbox:
		_hurtbox.setup(self)
	if _animation:
		_animation.setup(self)
	if _audio:
		_audio.setup()
		_audio.set_idle_active(active)
	if _defeat_effects:
		_defeat_effects.setup(self)
	for component: EnemyOptionalComponent in _optional_components:
		component.setup(self)
	_dead = false


func _on_damaged(_amount: int, _source: Node) -> void:
	for component: EnemyOptionalComponent in _optional_components:
		if component != null and is_instance_valid(component):
			component.on_enemy_damaged(_amount, _source)
	if _audio:
		_audio.play_cue(&"damage")
	if _animation:
		_animation.notify_hurt()


func _on_died(source: Node) -> void:
	_dead = true
	_refresh_source_traversal_actions(source)
	_register_source_combo_feat(source)
	for component: EnemyOptionalComponent in _optional_components:
		if component != null and is_instance_valid(component):
			component.on_enemy_defeated(source)
	active = false
	velocity = Vector3.ZERO
	if _attacks:
		_attacks.cancel_all()
	if _perception:
		_perception.clear()
	if _targetable:
		_targetable.set_enabled(false)
	if _collision:
		_collision.disable_until_reset()
	if _animation:
		_animation.set_dead(true)
	if _audio:
		_audio.set_idle_active(false)
		_audio.play_cue(&"defeat")
	if _defeat_effects:
		_defeat_effects.play_defeat_effect(size)
	if _score_award:
		_score_award.award(source)
	clear_gravity_state(&"death", true)
	if _respawn:
		_respawn.request_respawn()


func _refresh_source_traversal_actions(source: Node) -> void:
	var current: Node = source
	var visited: Dictionary = {}
	while current != null and is_instance_valid(current):
		var instance_id: int = current.get_instance_id()
		if visited.has(instance_id):
			return
		visited[instance_id] = true
		if current.has_method("refresh_airborne_abilities"):
			current.call("refresh_airborne_abilities")
			return
		if current.has_method("refresh_traversal_actions"):
			current.call("refresh_traversal_actions")
			return
		if current.has_method("get_score_award_recipient"):
			var recipient_value: Variant = current.call("get_score_award_recipient")
			if recipient_value is Node and recipient_value != current:
				current = recipient_value as Node
				continue
		current = current.get_parent()


func _register_source_combo_feat(source: Node) -> void:
	var current: Node = source
	var visited: Dictionary = {}
	while current != null and is_instance_valid(current):
		var instance_id: int = current.get_instance_id()
		if visited.has(instance_id):
			return
		visited[instance_id] = true
		if current.has_method("register_combo_feat"):
			current.call("register_combo_feat", &"badnik_defeat", "Badnik Defeated", 250.0, 1.25)
			return
		if current.has_method("get_score_award_recipient"):
			var recipient_value: Variant = current.call("get_score_award_recipient")
			if recipient_value is Node and recipient_value != current:
				current = recipient_value as Node
				continue
		current = current.get_parent()


func _respawn_enemy() -> void:
	global_transform = _respawn.get_spawn_transform() if _respawn else _spawn_transform
	_reset_components(&"respawn")
	if respawn_feedback != null:
		respawn_feedback.play(self)


func _reset_components(gravity_reason: StringName) -> void:
	_dead = false
	active = _spawn_active
	velocity = Vector3.ZERO
	_environmental_hazard_immunity_timer = (
		max(environmental_hazard_respawn_grace_sec, 0.0)
		if gravity_reason == &"respawn"
		else 0.0
	)
	_pending_environmental_hazards.clear()
	_fall_damage_cooldown_timer = 0.0
	clear_gravity_state(gravity_reason, true)
	if _health:
		_health.reset_health()
	if _perception:
		_perception.clear()
	if _brain:
		_brain.reset_brain()
	if _attacks:
		_attacks.reset_attacks()
	if _locomotion:
		_locomotion.reset_locomotion()
	if _hurtbox:
		_hurtbox.reset_hurtbox()
	if _collision:
		_collision.reset_collision()
	if _targetable:
		_targetable.set_enabled(true)
	if _animation:
		_animation.reset_driver()
	if _score_award:
		_score_award.reset_award()
	if _audio:
		_audio.set_idle_active(active)
	for component: EnemyOptionalComponent in _optional_components:
		if component != null and is_instance_valid(component):
			component.reset_component(gravity_reason)


func _collect_optional_components(node: Node) -> void:
	if node is EnemyOptionalComponent:
		_optional_components.append(node as EnemyOptionalComponent)
	for child: Node in node.get_children():
		_collect_optional_components(child)


func _update_environmental_hazard_immunity(delta: float) -> void:
	if _environmental_hazard_immunity_timer <= 0.0:
		return
	_environmental_hazard_immunity_timer = max(_environmental_hazard_immunity_timer - delta, 0.0)
	if _environmental_hazard_immunity_timer > 0.0:
		return
	var pending_hazards: Array = _pending_environmental_hazards.values()
	_pending_environmental_hazards.clear()
	for pending_value: Variant in pending_hazards:
		if not (pending_value is Dictionary):
			continue
		var pending: Dictionary = pending_value as Dictionary
		var source_reference: WeakRef = pending.get("source") as WeakRef
		var source: Node = source_reference.get_ref() as Node if source_reference != null else null
		if source == null or not is_instance_valid(source) or not _environmental_hazard_overlaps_self(source):
			continue
		var hazard_type: StringName = StringName(pending.get("hazard_type", &""))
		if apply_environmental_hazard(hazard_type, source):
			return


func _environmental_hazard_overlaps_self(source: Node) -> bool:
	var hazard_area: Area3D = source as Area3D
	if hazard_area == null:
		hazard_area = source.get_node_or_null("Area3D") as Area3D
	return hazard_area != null and hazard_area.overlaps_body(self)


func _process_fall_impact_damage() -> void:
	if not fall_damage_enabled or _dead or _health == null or _locomotion == null:
		return
	if _fall_damage_cooldown_timer > 0.0:
		return
	var incoming_velocity: Vector3 = _locomotion.get_pre_move_velocity()
	var incoming_speed: float = incoming_velocity.length()
	var impact_contacts: Array[Dictionary] = _locomotion.get_impact_contacts()
	if impact_contacts.is_empty():
		return
	if fall_damage_debug_enabled:
		print(name, " fall impact contacts=", impact_contacts.size(), " incoming_speed=", incoming_speed)
	if incoming_speed < max(fall_damage_minimum_speed, 0.0):
		if fall_damage_debug_enabled:
			print(name, " fall impact rejected: below minimum speed ", fall_damage_minimum_speed)
		return
	var strongest_effective_speed: float = 0.0
	var strongest_source: Node = null
	for contact: Dictionary in impact_contacts:
		var collider: Object = contact.get("collider") as Object
		if not _fall_damage_surface_is_allowed(collider):
			if fall_damage_debug_enabled:
				print(name, " fall impact rejected: surface mask collider=", collider)
			continue
		var normal: Vector3 = contact.get("normal", Vector3.ZERO) as Vector3
		if normal.length() < 0.001:
			continue
		var normal_impact_speed: float = max(-incoming_velocity.dot(normal), 0.0)
		var opposition: float = normal_impact_speed / max(incoming_speed, 0.001)
		if opposition < clamp(fall_damage_minimum_opposition, 0.0, 1.0):
			if fall_damage_debug_enabled:
				print(name, " fall impact rejected: opposition=", opposition)
			continue
		var alignment_weight: float = lerp(
			clamp(fall_damage_slope_bias, 0.0, 1.0),
			1.0,
			clamp(opposition, 0.0, 1.0)
		)
		var effective_speed: float = incoming_speed * alignment_weight
		if fall_damage_debug_enabled:
			print(name, " fall impact candidate effective_speed=", effective_speed, " opposition=", opposition, " normal=", normal)
		if effective_speed <= strongest_effective_speed:
			continue
		strongest_effective_speed = effective_speed
		strongest_source = collider as Node
	if strongest_effective_speed < max(fall_damage_minimum_speed, 0.0):
		if fall_damage_debug_enabled:
			print(name, " fall impact rejected: effective speed=", strongest_effective_speed)
		return
	_fall_damage_cooldown_timer = max(fall_damage_cooldown_sec, 0.0)
	if fall_damage_death_speed > 0.0 and strongest_effective_speed >= fall_damage_death_speed:
		if fall_damage_debug_enabled:
			print(name, " fall impact death: effective_speed=", strongest_effective_speed)
		_health.kill(strongest_source)
	else:
		if fall_damage_debug_enabled:
			print(name, " fall impact damage: effective_speed=", strongest_effective_speed, " amount=", fall_damage_amount)
		_health.apply_damage(max(fall_damage_amount, 1), strongest_source)


func _fall_damage_surface_is_allowed(collider: Object) -> bool:
	if fall_damage_surface_mask == 0:
		return true
	if collider is CollisionObject3D:
		return ((collider as CollisionObject3D).collision_layer & fall_damage_surface_mask) != 0
	if collider != null:
		for property: Dictionary in collider.get_property_list():
			if StringName(property.get("name", &"")) != &"collision_layer":
				continue
			return (int(collider.get("collision_layer")) & fall_damage_surface_mask) != 0
	return true


func _on_brain_state_changed(state_name: StringName) -> void:
	if state_name == &"alert" and _audio:
		_audio.play_cue(&"alert")


func _on_attack_started(_attack: EnemyAttack) -> void:
	if _audio:
		_audio.play_cue(&"attack")


func _update_presentation(delta: float) -> void:
	if _animation == null:
		return
	var brain_state: StringName = _brain.get_state_tag() if _brain else &"idle"
	var locomotion_state: StringName = _locomotion.get_state_tag() if _locomotion else &"idle"
	var attack_state: StringName = _attacks.get_animation_tag() if _attacks else &""
	_animation.physics_tick(delta, brain_state, locomotion_state, attack_state, _dead, velocity.length())


func _apply_size() -> void:
	var uniform_size: float = max(size, 0.01)
	for path: NodePath in size_target_paths:
		var target_node: Node3D = get_node_or_null(path) as Node3D
		if target_node == null:
			continue
		if not target_node.has_meta(SIZE_BASE_POSITION_META):
			target_node.set_meta(SIZE_BASE_POSITION_META, target_node.position)
		if not target_node.has_meta(SIZE_BASE_SCALE_META):
			target_node.set_meta(SIZE_BASE_SCALE_META, target_node.scale)
		var base_position_value: Variant = target_node.get_meta(SIZE_BASE_POSITION_META)
		var base_scale_value: Variant = target_node.get_meta(SIZE_BASE_SCALE_META)
		if base_position_value is Vector3:
			target_node.position = (base_position_value as Vector3) * uniform_size
		if base_scale_value is Vector3:
			target_node.scale = (base_scale_value as Vector3) * uniform_size


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if get_node_or_null(locomotion_component_path) == null:
		warnings.append("Enemy requires one locomotion component.")
	if get_node_or_null(health_component_path) == null:
		warnings.append("Enemy has no health component and cannot receive damage.")
	if get_node_or_null(gravity_component_path) == null:
		warnings.append("Enemy has no gravity receiver; gravity-relative systems will use world up.")
	return warnings

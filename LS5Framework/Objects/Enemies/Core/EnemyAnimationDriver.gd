extends Node
class_name EnemyAnimationDriver

@export_group("Nodes")
## Visual hierarchy hidden and restored by the enemy lifecycle.
@export var visual_root_path: NodePath = NodePath("Visual")
## AnimationPlayer used by the default semantic animation mapping.
@export var animation_player_path: NodePath = NodePath("")
## Optional adapter receiving apply_enemy_visual_state calls instead of the default mapping.
@export var visual_adapter_path: NodePath = NodePath("")

@export_group("Animations")
## Animation used by the idle semantic state.
@export var animation_idle: StringName = &""
## Animation used by the alert semantic state.
@export var animation_alert: StringName = &""
## Animation used by grounded or flying movement.
@export var animation_move: StringName = &""
## Animation used while airborne under grounded locomotion.
@export var animation_airborne: StringName = &""
## Animation used by the primary attack semantic state.
@export var animation_attack_primary: StringName = &""
## Animation used by the secondary attack semantic state.
@export var animation_attack_secondary: StringName = &""
## Animation used after non-lethal damage.
@export var animation_hurt: StringName = &""
## Animation used after defeat when the visual remains visible.
@export var animation_dead: StringName = &""
## Duration the hurt semantic state overrides ordinary movement animation.
@export var hurt_linger_sec: float = 0.2
## Hides the configured visual root when the actor is defeated.
@export var hide_visual_on_death: bool = true

var _actor: CharacterBody3D = null
var _visual_root: Node3D = null
var _animation_player: AnimationPlayer = null
var _visual_adapter: Node = null
var _hurt_timer: float = 0.0
var _current_state: StringName = &""


func setup(actor: CharacterBody3D) -> void:
	_actor = actor
	_visual_root = actor.get_node_or_null(visual_root_path) as Node3D if visual_root_path != NodePath("") else null
	_animation_player = actor.get_node_or_null(animation_player_path) as AnimationPlayer if animation_player_path != NodePath("") else null
	_visual_adapter = actor.get_node_or_null(visual_adapter_path) if visual_adapter_path != NodePath("") else null
	set_visual_visible(true)


func physics_tick(
	delta: float,
	brain_state: StringName,
	locomotion_state: StringName,
	attack_state: StringName,
	dead: bool,
	speed: float
) -> void:
	_hurt_timer = max(_hurt_timer - delta, 0.0)
	var state: StringName = _resolve_state(brain_state, locomotion_state, attack_state, dead)
	if _visual_adapter and _visual_adapter.has_method("apply_enemy_visual_state"):
		_visual_adapter.call("apply_enemy_visual_state", state, speed, delta)
		_current_state = state
		return
	if state == _current_state:
		return
	_current_state = state
	_play_animation(_get_animation_for_state(state))


func notify_hurt() -> void:
	_hurt_timer = max(hurt_linger_sec, 0.0)


func set_dead(value: bool) -> void:
	if value and hide_visual_on_death:
		set_visual_visible(false)
	elif not value:
		set_visual_visible(true)
	_current_state = &""


func set_visual_visible(value: bool) -> void:
	if _visual_root:
		_visual_root.visible = value


func reset_driver() -> void:
	_hurt_timer = 0.0
	_current_state = &""
	set_visual_visible(true)


func _resolve_state(
	brain_state: StringName,
	locomotion_state: StringName,
	attack_state: StringName,
	dead: bool
) -> StringName:
	if dead:
		return &"dead"
	if _hurt_timer > 0.0:
		return &"hurt"
	if attack_state != &"":
		return attack_state
	if locomotion_state == &"airborne":
		return &"airborne"
	if brain_state == &"alert":
		return &"alert"
	if locomotion_state == &"move":
		return &"move"
	return &"idle"


func _get_animation_for_state(state: StringName) -> StringName:
	match state:
		&"alert":
			return animation_alert if animation_alert != &"" else animation_idle
		&"move":
			return animation_move if animation_move != &"" else animation_idle
		&"airborne":
			return animation_airborne if animation_airborne != &"" else animation_move
		&"attack_primary":
			return animation_attack_primary if animation_attack_primary != &"" else animation_idle
		&"attack_secondary":
			return animation_attack_secondary if animation_attack_secondary != &"" else animation_attack_primary
		&"hurt":
			return animation_hurt if animation_hurt != &"" else animation_idle
		&"dead":
			return animation_dead
		_:
			return animation_idle


func _play_animation(animation_name: StringName) -> void:
	if _animation_player == null or animation_name == &"":
		return
	if _animation_player.is_playing() and _animation_player.current_animation == String(animation_name):
		return
	if _animation_player.has_animation(animation_name):
		_animation_player.play(animation_name)
		return
	var full_name: String = String(animation_name)
	var separator_index: int = full_name.find("/")
	if separator_index >= 0:
		var short_name: String = full_name.substr(separator_index + 1)
		if _animation_player.has_animation(short_name):
			_animation_player.play(short_name)


class_name FloorButton
extends Node3D

signal activated(actor: Node3D)
signal deactivated(actor: Node3D)

const ActivationLight = preload("res://LS5Framework/Objects/Switch/ActivationLight.gd")

@export_group("Pressure")
## Accepts pressure from locally controlled players.
@export var accept_players: bool = true
## Accepts pressure from rigid bodies, including loose carryables.
@export var accept_physics_objects: bool = true
## Requires the combined weight of eligible bodies to reach Minimum Weight.
@export var use_weight_threshold: bool = false
## Combined weight required to depress the button when the threshold is enabled.
@export_range(0.1, 500.0, 0.1, "or_greater", "suffix:kg") var minimum_weight: float = 10.0
## Effective weight contributed by a player when the threshold is enabled.
@export_range(0.0, 500.0, 0.1, "or_greater", "suffix:kg") var player_weight: float = 40.0
## Limits pressure to the specific nodes in Allowed Bodies.
@export var require_specific_objects: bool = false
## Players or rigid bodies that may depress this button in specific-object mode.
@export var allowed_bodies: Array[Node3D] = []
## Physics layers scanned for pressure. Non-player characters and static bodies are ignored.
@export_flags_3d_physics var pressure_collision_mask: int = 1031
## Time pressure can drop before the button releases.
@export_range(0.0, 1.0, 0.01, "suffix:s") var release_grace: float = 0.12

@export_group("Activation")
## Stays depressed after pressure is removed, until reset_button() is called.
@export var stay_pressed: bool = false
## Objects controlled by this button. Paths are relative to the button root.
@export var activation_target_paths: Array[NodePath] = []

@export_group("Feedback")
## Texture used both as the active light color and its emission.
@export var light_on_texture: Texture2D
## Emission multiplier for the active light.
@export_range(0.0, 16.0, 0.05, "or_greater") var light_emission: float = 1.5
## Positional sound played when the button depresses.
@export var activation_sound: AudioStream
## Positional sound played when the button releases.
@export var deactivation_sound: AudioStream

## Detects pressure across the travel of the button cap.
@onready var _pressure: Area3D = $Pressure
## Drives the cap mesh and its solid collision.
@onready var _animation: AnimationPlayer = $AnimationPlayer
## Sends activation state to linked objects.
@onready var _activation: ActivationSource = $ActivationSource
## Imported cap mesh containing the light surface.
@onready var _cap_mesh: MeshInstance3D = $Cap/Model/Button_Push
## Plays the press and release sounds at the button.
@onready var _feedback: AudioStreamPlayer3D = $Feedback

var _clip_length: float = 0.0
var _clip_time: float = 0.0
var _release_remaining: float = 0.0
var _wait_for_unload: bool = false
var _light_surface: int = -1
var _light_off: StandardMaterial3D
var _light_on: StandardMaterial3D


func _ready() -> void:
	_pressure.collision_mask = pressure_collision_mask
	_pressure.body_entered.connect(_on_body_entered)
	_activation.active_changed.connect(_on_active_changed)
	_clip_length = _animation.get_animation(&"press").length
	_animation.play(&"press")
	_animation.seek(0.0, true)
	if light_on_texture:
		_light_surface = ActivationLight.find_surface(_cap_mesh)
		if _light_surface >= 0:
			_light_off = _cap_mesh.get_active_material(_light_surface) as StandardMaterial3D
			_light_on = ActivationLight.make_on_material(_light_off, light_on_texture, light_emission)
	set_physics_process(false)


func is_active() -> bool:
	return _activation.is_active


func reset_button() -> void:
	if not _activation.is_active:
		return
	_wait_for_unload = true
	_release_remaining = 0.0
	_activation.deactivate()


func _on_body_entered(body: Node3D) -> void:
	if _accepts_body(body) and not (stay_pressed and _activation.is_active):
		set_physics_process(true)


func _accepts_body(body: Node3D) -> bool:
	if require_specific_objects and not allowed_bodies.has(body):
		return false
	if body is PlayerController:
		return accept_players and not body._is_buddy_actor() and body._network_is_local_authority()
	return accept_physics_objects and body is RigidBody3D


func _physics_process(delta: float) -> void:
	var keep_tracking: bool = false
	if not (stay_pressed and _activation.is_active):
		keep_tracking = _update_pressure(delta)
	var endpoint: float = _clip_length if _activation.is_active else 0.0
	if _clip_time != endpoint:
		_clip_time = move_toward(_clip_time, endpoint, delta)
		_animation.seek(_clip_time, true)
	set_physics_process(keep_tracking or _clip_time != endpoint)


func _update_pressure(delta: float) -> bool:
	var actor: Node3D
	var prop: ObjectPhysicsBody3D
	var has_candidate: bool = false
	var has_pressure: bool = false
	var weight: float = 0.0
	for body: Node3D in _pressure.get_overlapping_bodies():
		if not _accepts_body(body):
			continue
		has_candidate = true
		if body is ObjectPhysicsBody3D and body.is_carried():
			continue
		has_pressure = true
		if body is PlayerController:
			weight += player_weight
			actor = body
		else:
			weight += (body as RigidBody3D).mass
			if not prop and body is ObjectPhysicsBody3D:
				prop = body
	if has_pressure and (not use_weight_threshold or weight >= minimum_weight):
		_release_remaining = release_grace
		if not _wait_for_unload and not _activation.is_active:
			if not actor and prop:
				actor = prop.get_score_award_recipient()
			_activation.set_targets(self, activation_target_paths)
			_activation.activate(actor)
	else:
		_wait_for_unload = false
		if _activation.is_active:
			_release_remaining = maxf(_release_remaining - delta, 0.0)
			if is_zero_approx(_release_remaining):
				_activation.deactivate()
	return has_candidate or _activation.is_active


func _on_active_changed(active: bool, actor: Node3D) -> void:
	if _light_surface >= 0:
		_cap_mesh.set_surface_override_material(_light_surface, _light_on if active else _light_off)
	var sound: AudioStream = activation_sound if active else deactivation_sound
	if sound:
		_feedback.stream = sound
		_feedback.play()
	set_physics_process(true)
	if active:
		activated.emit(actor)
	else:
		deactivated.emit(actor)

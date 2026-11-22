@tool
extends Node3D
class_name SpikeStrip

enum Phase { DOWN_LOOP, RISING, UP_LOOP, FALLING }

@export_group("Size")
## Uniform size multiplier for the model, solid base, and damage area.
@export_range(0.01, 100.0, 0.01, "or_greater") var size: float = 1.0:
	set(value):
		size = maxf(value, 0.01)
		if is_node_ready():
			_apply_size()

@export_group("Base Plate")
## Hides the plate and lowers the spikes beneath the object root when retracted.
@export var hide_base_plate: bool = false:
	set(value):
		hide_base_plate = value
		if is_node_ready():
			_apply_size()
## Disables solid plate collision independently of plate visibility.
@export var disable_base_collision: bool = false:
	set(value):
		disable_base_collision = value
		if is_node_ready():
			_apply_size()
## Downward offset when the plate is hidden, multiplied by Size. Keeps the retracted spikes below ground.
@export_range(0.0, 10.0, 0.01, "or_greater") var hidden_base_offset: float = 0.55:
	set(value):
		hidden_base_offset = maxf(value, 0.0)
		if is_node_ready():
			_apply_size()

@export_group("Cycle")
## Time spent retracted between rises, in seconds.
@export_range(0.01, 60.0, 0.01, "or_greater", "suffix:s") var down_loop_duration: float = 2.0
## Time spent in the damaging raised loop, in seconds.
@export_range(0.01, 60.0, 0.01, "or_greater", "suffix:s") var up_loop_duration: float = 2.0
## Playback duration of the upward transition, in seconds.
@export_range(0.01, 10.0, 0.01, "or_greater", "suffix:s") var up_transition_duration: float = 1.0
## Remains in the damaging raised loop indefinitely after rising. Overrides Up Loop Duration.
@export var stay_up: bool = false
## Begins in the raised loop instead of the retracted loop.
@export var start_raised: bool = false

@export_group("Damage")
## Contact damage while Spike_Up_Loop is playing. Zero disables damage.
@export_range(0, 1000, 1) var damage_amount: int = 1

@export_group("References")
## Root containing the animated Spike Strip model.
@export_node_path("Node3D") var visual_root_path: NodePath = NodePath("Armature")
## Plate mesh hidden by the Hide Base Plate option.
@export_node_path("GeometryInstance3D") var base_plate_path: NodePath = NodePath("Armature/Skeleton3D/Cube")
## Animation player containing the four Spike Strip animations.
@export_node_path("AnimationPlayer") var animation_player_path: NodePath = NodePath("AnimationPlayer")
## Area covering the raised spikes and detecting player contact.
@export_node_path("Area3D") var damage_area_path: NodePath = NodePath("DamageArea")
## Spatial sound triggered by frame 27 of the upward transition.
@export_node_path("AudioStreamPlayer3D") var up_audio_path: NodePath = NodePath("SpikeUpAudio")

## Animated model root resized without changing the object's placement.
@onready var _visual_root: Node3D = _get_owned_reference(visual_root_path, NodePath("Armature")) as Node3D
## Plate mesh controlled independently of solid collision.
@onready var _base_plate: GeometryInstance3D = _get_owned_reference(base_plate_path, NodePath("Armature/Skeleton3D/Cube")) as GeometryInstance3D
## Solid base shape resized alongside the model.
@onready var _base_collision: CollisionShape3D = get_node_or_null("BaseCollision/CollisionShape3D") as CollisionShape3D
## Authored animation playback controlled by the physics cycle.
@onready var _animation_player: AnimationPlayer = _get_owned_reference(animation_player_path, NodePath("AnimationPlayer")) as AnimationPlayer
## Player contact area kept active throughout the cycle.
@onready var _damage_area: Area3D = _get_owned_reference(damage_area_path, NodePath("DamageArea")) as Area3D
## Damage shape belonging to the resolved local damage area.
@onready var _damage_collision: CollisionShape3D = _damage_area.get_node_or_null("CollisionShape3D") as CollisionShape3D if _damage_area else null
## Upward transition sound source.
@onready var _up_audio: AudioStreamPlayer3D = _get_owned_reference(up_audio_path, NodePath("SpikeUpAudio")) as AudioStreamPlayer3D

var _phase: Phase = Phase.DOWN_LOOP
var _phase_remaining: float = 0.0
var _distance_culled: bool = false

func _get_owned_reference(path: NodePath, fallback: NodePath) -> Node:
	var candidate: Node = get_node_or_null(path)
	if candidate and is_ancestor_of(candidate):
		return candidate
	return get_node_or_null(fallback)

func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	if not _animation_player or not _damage_area:
		push_warning("Spike Strip requires animation player and damage area references.")
		set_physics_process(false)
		return
	for animation: StringName in [&"Spike_Down_Loop", &"Spike_Up", &"Spike_Up_Loop", &"Spike_Down"]:
		if not _animation_player.has_animation(animation):
			push_warning("Spike Strip is missing animation: %s" % animation)
			set_physics_process(false)
			return
	_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation_player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	_enter_phase(Phase.UP_LOOP if start_raised else Phase.DOWN_LOOP)

func set_distance_culled(value: bool) -> void:
	_distance_culled = value


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_advance_cycle(delta)
	if not _distance_culled and is_damage_active():
		for body: Node3D in _damage_area.get_overlapping_bodies():
			_try_damage_body(body)

func _apply_size() -> void:
	var offset: Vector3 = Vector3.DOWN * hidden_base_offset * size if hide_base_plate else Vector3.ZERO
	if _base_plate:
		_base_plate.visible = not hide_base_plate
	if _base_collision:
		_base_collision.set_deferred("disabled", disable_base_collision)
	if _visual_root:
		if not _visual_root.has_meta(&"_uniform_size_base_scale"):
			_visual_root.set_meta(&"_uniform_size_base_scale", _visual_root.scale)
		if not _visual_root.has_meta(&"_uniform_size_base_position"):
			_visual_root.set_meta(&"_uniform_size_base_position", _visual_root.position)
		_visual_root.scale = (_visual_root.get_meta(&"_uniform_size_base_scale") as Vector3) * size
		_visual_root.position = (_visual_root.get_meta(&"_uniform_size_base_position") as Vector3) * size + offset
	for collision: CollisionShape3D in [_base_collision, _damage_collision]:
		if not collision or not collision.shape is BoxShape3D:
			continue
		if not collision.has_meta(&"_uniform_size_base_dimensions"):
			collision.set_meta(&"_uniform_size_base_dimensions", collision.shape.size)
		if not collision.has_meta(&"_uniform_size_base_position"):
			collision.set_meta(&"_uniform_size_base_position", collision.position)
		collision.shape.size = (collision.get_meta(&"_uniform_size_base_dimensions") as Vector3) * size
		collision.position = (collision.get_meta(&"_uniform_size_base_position") as Vector3) * size
		if collision == _damage_collision:
			collision.position += offset

func is_damage_active() -> bool:
	return damage_amount > 0 and _animation_player and _animation_player.is_playing() and _animation_player.current_animation == &"Spike_Up_Loop"

func _advance_cycle(delta: float) -> void:
	var remaining: float = maxf(delta, 0.0)
	while remaining > 0.0:
		if stay_up and _phase == Phase.UP_LOOP:
			if not _distance_culled:
				_animation_player.advance(remaining)
			return
		var step: float = minf(remaining, _phase_remaining)
		_animation_player.advance(step)
		_phase_remaining -= step
		remaining = maxf(remaining - step, 0.0)
		if _phase_remaining <= 0.0:
			_enter_phase(((_phase + 1) % 4) as Phase)

func _enter_phase(phase: Phase) -> void:
	_phase = phase
	var animation: StringName
	var duration: float
	match phase:
		Phase.DOWN_LOOP:
			animation = &"Spike_Down_Loop"
			duration = down_loop_duration
		Phase.RISING:
			animation = &"Spike_Up"
			duration = up_transition_duration
		Phase.UP_LOOP:
			animation = &"Spike_Up_Loop"
			duration = up_loop_duration
		Phase.FALLING:
			animation = &"Spike_Down"
			duration = _animation_player.get_animation(animation).length
	_phase_remaining = maxf(duration, 0.01)
	var rate: float = 1.0
	if phase in [Phase.RISING, Phase.FALLING]:
		rate = _animation_player.get_animation(animation).length / _phase_remaining
	_animation_player.play(animation, 0.0, rate)
	_animation_player.advance(0.0)

func _play_up_sound() -> void:
	if not Engine.is_editor_hint() and not _distance_culled and _up_audio:
		_up_audio.play()

func _try_damage_body(body: Node3D) -> bool:
	if not is_damage_active() or not body or not (body.is_in_group(&"player") or body.is_in_group(&"Player")) or not body.has_method("apply_damage"):
		return false
	if body.has_method("is_hurt_invulnerable") and body.call("is_hurt_invulnerable"):
		return false
	body.call("apply_damage", damage_amount, self)
	return true

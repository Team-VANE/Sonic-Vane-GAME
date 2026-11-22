@tool
extends Node3D

const FOLDED: float = -PI / 2.0
const BLINK_HZ: float = 3.0
const LAMP_YELLOW: Color = Color(1.0, 0.8, 0.04)

@onready var _skeleton: Skeleton3D = $Model/Armature/Skeleton3D
@onready var _beam: MeshInstance3D = $Model/Armature/Skeleton3D/BEAM
@onready var _posts: MeshInstance3D = $Model/Armature/Skeleton3D/Checkpoint

var _post_bones: PackedInt32Array
var _pole_bones: PackedInt32Array
var _lamp_bones: PackedInt32Array
var _rest_lamp: Material
var _lit_lamp: StandardMaterial3D
var _beam_material: BaseMaterial3D
var _beam_flicker: Tween
var _beam_full_emission: float = 1.0
var _raised: bool = false
var _elapsed: float = 0.0
var _duration: float = 0.0
var _horizontal_duration: float = 0.0
var _entry_forward: float = 1.0
var _entry_side: float = 0.0
var _entry_speed: float = 0.0
var _closing_poles: Array[Quaternion] = []
var _closing_lamps: Array[Quaternion] = []


func _ready() -> void:
	_post_bones = _find_pair("Post")
	_pole_bones = _find_pair("Pole")
	_lamp_bones = _find_pair("PoleTop")
	_rest_lamp = _posts.get_active_material(1)
	_apply_poles(0.0)
	set_process(false)
	if not Engine.is_editor_hint():
		var beam_material: BaseMaterial3D = _beam.get_active_material(0) as BaseMaterial3D
		if beam_material:
			_beam_material = beam_material.duplicate() as BaseMaterial3D
			_beam_full_emission = beam_material.emission_energy_multiplier
			_beam.set_surface_override_material(0, _beam_material)
			_start_beam_flicker()


func _start_beam_flicker() -> void:
	if not _beam_material:
		return
	_beam_material.emission_energy_multiplier = _beam_full_emission
	_beam_flicker = create_tween().set_loops()
	_beam_flicker.tween_interval(0.07)
	_beam_flicker.tween_property(_beam_material, "emission_energy_multiplier", _beam_full_emission * 0.75, 0.0)
	_beam_flicker.tween_interval(0.05)
	_beam_flicker.tween_property(_beam_material, "emission_energy_multiplier", _beam_full_emission, 0.0)


func set_width(width: float) -> void:
	if not is_node_ready():
		return
	for index: int in _post_bones.size():
		var bone: int = _post_bones[index]
		var position: Vector3 = _skeleton.get_bone_rest(bone).origin
		position.x = signf(position.x) * width * 0.5
		_skeleton.set_bone_pose_position(bone, position)
	var extent: float = width * 0.5 + 3.5
	var bounds: AABB = AABB(Vector3(-extent, -1.0, -3.5), Vector3(extent * 2.0, 6.5, 7.0))
	_posts.custom_aabb = bounds
	_beam.custom_aabb = bounds


func set_selected(selected: bool, velocity: Vector3, approach_position: Vector3) -> void:
	if _raised == selected:
		return
	_raised = selected
	_elapsed = 0.0
	_beam.visible = not selected
	if not selected:
		_start_beam_flicker()
		_posts.set_surface_override_material(1, _rest_lamp)
		_closing_poles.clear()
		_closing_lamps.clear()
		for index: int in _pole_bones.size():
			_closing_poles.append(_skeleton.get_bone_pose_rotation(_pole_bones[index]))
			_closing_lamps.append(_skeleton.get_bone_pose_rotation(_lamp_bones[index]))
		_duration = 0.24
		set_process(true)
		return
	if _beam_flicker:
		_beam_flicker.kill()
		_beam_flicker = null
	var local_velocity: Vector3 = global_basis.orthonormalized().inverse() * velocity
	var crossing: Vector2 = Vector2(local_velocity.x, local_velocity.z)
	_entry_speed = crossing.length()
	_entry_side = clampf(crossing.x / maxf(_entry_speed, 1.0), -1.0, 1.0)
	var approach: float = to_local(approach_position).z
	_entry_forward = signf(crossing.y) if absf(crossing.y) > 0.25 else (-1.0 if approach > 0.0 else 1.0)
	var speed_weight: float = clampf(_entry_speed / 65.0, 0.0, 1.0)
	_horizontal_duration = lerpf(0.08, 0.65, speed_weight)
	_duration = _horizontal_duration + lerpf(0.68, 0.50, speed_weight)
	if not _lit_lamp:
		_lit_lamp = (_rest_lamp as BaseMaterial3D).duplicate() as StandardMaterial3D
		_lit_lamp.albedo_texture = null
		_lit_lamp.albedo_color = LAMP_YELLOW
		_lit_lamp.emission_enabled = true
		_lit_lamp.emission = LAMP_YELLOW
		_lit_lamp.emission_energy_multiplier = 1.0
	_posts.set_surface_override_material(1, _lit_lamp)
	set_process(true)


func _process(delta: float) -> void:
	var previous_elapsed: float = _elapsed
	_elapsed += delta
	if not _raised:
		var folded: Quaternion = Quaternion(Vector3.RIGHT, FOLDED)
		var close_weight: float = smoothstep(0.0, _duration, _elapsed)
		for index: int in _pole_bones.size():
			_skeleton.set_bone_pose_rotation(_pole_bones[index], _closing_poles[index].slerp(folded, close_weight))
			_skeleton.set_bone_pose_rotation(_lamp_bones[index], _closing_lamps[index].slerp(Quaternion.IDENTITY, close_weight))
		if _elapsed >= _duration:
			set_process(false)
		return
	if previous_elapsed < _duration:
		_apply_poles(minf(_elapsed, _duration))
	var pulse: float = 0.5 + 0.5 * cos(_elapsed * BLINK_HZ * TAU)
	_lit_lamp.emission_energy_multiplier = lerpf(0.35, 2.5, pulse)


func _apply_poles(elapsed: float) -> void:
	var rise_duration: float = maxf(_duration - _horizontal_duration, 0.001)
	var rise: float = clampf((elapsed - _horizontal_duration) / rise_duration, 0.0, 1.0)
	var lift: float = smoothstep(0.0, 1.0, rise)
	for index: int in _pole_bones.size():
		var side: float = -1.0 if index == 0 else 1.0
		var speed: float = _entry_speed * (1.0 + side * _entry_side * 0.3)
		var rate: float = lerpf(1.7, 5.8, clampf(speed / 65.0, 0.0, 1.0))
		var turns: float = rate * minf(elapsed, _horizontal_duration)
		if rise > 0.0:
			var rise_slope: float = rate * rise_duration
			var final_turn: float = ceilf(turns + rise_slope * 0.4)
			turns = lerpf(turns, final_turn, lift) + rise_slope * rise * (1.0 - rise) ** 2
		var direction: float = side * _entry_forward
		var hinge: Quaternion = Quaternion(Vector3.RIGHT, lerpf(FOLDED, 0.0, lift))
		var swivel: Quaternion = Quaternion(Vector3.UP, direction * TAU * turns)
		var roll: float = direction * sin(rise * TAU) * (1.0 - rise) * (0.3 + minf(speed / 80.0, 0.7))
		var sway: Quaternion = Quaternion(Vector3.BACK, roll)
		_skeleton.set_bone_pose_rotation(_pole_bones[index], swivel * hinge * sway)
		_skeleton.set_bone_pose_rotation(_lamp_bones[index], Quaternion(Vector3.UP, -direction * TAU * turns))


func _find_pair(part: String) -> PackedInt32Array:
	return PackedInt32Array([_skeleton.find_bone(part + ".L"), _skeleton.find_bone(part + ".R")])

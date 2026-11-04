extends Node
class_name SpinBallVisuals

class MarkerReader extends SpeedAfterImageController:
	func _parse_resource_arguments(text: String, index: int) -> Dictionary:
		var result: Dictionary = {"enabled": true}
		var suffix: String = text.substr(index + animation_resource_marker.length()).trim_prefix("-")
		for item: String in suffix.split(";", false):
			var pair: PackedStringArray = item.split("=", true, 1)
			if pair.size() != 2:
				continue
			if pair[0].strip_edges().to_lower() == "enabled":
				result.enabled = pair[1].strip_edges().to_lower() in ["true", "1", "on"]
			elif pair[0] == "shear" and pair[1].is_valid_float():
				result.shear = pair[1].to_float()
		return result

## Character supplying animation state and visual orientation.
@export var player_path: NodePath = NodePath("..")
## Animation tree containing _spinball-enabled=true markers in node resource names.
@export var animation_tree_path: NodePath
## Dedicated transform containing character visuals and the Spin Ball.
@export var deformation_root_path: NodePath
## Model root containing the meshes alternated with the Spin Ball.
@export var character_root_path: NodePath
## Bone-controlled Spin Ball mesh inside the character model.
@export var spin_ball_path: NodePath
## Flicker ticks per second. Each cycle hides the Spin Ball for two ticks, then shows it for one.
@export_range(1.0, 120.0, 1.0) var flicker_steps_per_second: float = 60.0
## Chance per visible or hidden interval of holding that state for one extra tick.
@export_range(0.0, 1.0, 0.01) var flicker_stutter_chance: float = 0.08
## Forward shear while spindashing or drop-dashing.
@export_range(-1.0, 1.0, 0.01) var shear_strength: float = 0.3
## Forward stretch at the start of a grounded spindash launch.
@export_range(0.0, 1.0, 0.01) var spindash_forward_stretch: float = 0.65
## Vertical stretch during bounce descent, aligned with player gravity-up.
@export_range(0.0, 0.5, 0.01) var bounce_fall_stretch_strength: float = 0.18
## Bottom height anchored while shearing and stretching.
@export var bottom_height: float = -1.05
## Response rate for entering and leaving shear.
@export_range(0.1, 60.0, 0.1) var shear_response: float = 18.0
## Duration of the squash and stretch following rebound.
@export_range(0.05, 2.0, 0.01) var rebound_duration: float = 0.7
## Number of diminishing squash and stretch cycles following rebound.
@export_range(1, 6, 1) var rebound_cycles: int = 3
## Maximum rebound deformation. Zero disables squash and stretch.
@export_range(0.0, 0.5, 0.01) var rebound_strength: float = 0.24

## Character state used by visual deformation.
var _player: Node
## Animated visuals alternated with the Spin Ball.
var _character: Node3D
## Visual transform isolated from movement orientation.
var _deformation: Node3D
## Per-character animation marker evaluator.
var _reader: MarkerReader
## Authored Spin Ball visual instance.
var _ball: Node3D
var _base_transform: Transform3D
var _ball_visibility: bool = false
var _clock: float = 0.0
var _flicker_steps_remaining: int = 2
var _ball_frame: bool = false
var _flicker_random: RandomNumberGenerator = RandomNumberGenerator.new()
var _shear: float = 0.0
var _bounce_stretch: float = 0.0
var _forward_stretch: float = 0.0
var _rebound_elapsed: float = 1000.0
var _active: bool = false
## Model geometry alternated without hiding the skeleton or its ancestors.
var _character_meshes: Array[GeometryInstance3D] = []
var _mesh_visibility: Dictionary = {}

func _ready() -> void:
	process_priority = 100
	_flicker_random.randomize()
	_player = get_node_or_null(player_path)
	_character = get_node_or_null(character_root_path) as Node3D
	_deformation = get_node_or_null(deformation_root_path) as Node3D
	_ball = get_node_or_null(spin_ball_path) as Node3D
	var tree: AnimationTree = get_node_or_null(animation_tree_path) as AnimationTree
	if not _player or not _character or not _deformation or not tree or not _ball:
		push_warning("Spin Ball requires character, animation tree, deformation root, visual root, and authored Spin Ball references.")
		_deformation = null
		set_process(false)
		return
	_base_transform = _deformation.transform
	_reader = MarkerReader.new()
	_reader.animation_resource_marker = "_spinball"
	_reader._animation_tree = tree
	_reader._cache_activation_routes()
	for visual: Node in _character.find_children("*", "GeometryInstance3D", true, false):
		if visual != _ball and not _ball.is_ancestor_of(visual):
			_character_meshes.append(visual)
	_ball_visibility = _ball.visible
	_ball.visible = false
	if _player.has_signal("visual_bounce_rebounded"):
		_player.connect("visual_bounce_rebounded", notify_rebound)

func notify_rebound() -> void:
	_rebound_elapsed = 0.0
	_shear = 0.0
	_bounce_stretch = 0.0
	_forward_stretch = 0.0

func _process(delta: float) -> void:
	var settings: Dictionary = {}
	var disabled: bool = false
	for route: Dictionary in _reader._activation_routes:
		if _reader._is_route_active(route):
			disabled = disabled or not bool(route.settings.get("enabled", true))
			settings.merge(route.settings, true)
	var active: bool = not disabled and not settings.is_empty() and bool(settings.get("enabled", true)) and not _player._is_dead and not _player._hurt_active
	if active and not _active:
		_reset_flicker()
		for visual: GeometryInstance3D in _character_meshes:
			if is_instance_valid(visual):
				_mesh_visibility[visual] = visual.visible
	if active:
		_advance_flicker(delta)
		_ball.visible = _ball_frame
		for visual: GeometryInstance3D in _character_meshes:
			if is_instance_valid(visual):
				visual.visible = not _ball_frame and bool(_mesh_visibility.get(visual, false))
	else:
		_ball.visible = false
		if _active:
			_restore_mesh_visibility()
	_active = active
	var animation_state: StringName = _player.get_animation_director().get_current_state()
	var bouncing: bool = active and (_player._bounce_state == _player.BounceState.BOUNCE or animation_state == &"BOUNCE")
	var drop_dash_released: bool = _player._spindash_action and _player._spindash_action.drop_dash_released
	var deforming: bool = active and not drop_dash_released and (_player._spindash_charging or animation_state in [&"SPINDASH", &"DROPDASH"])
	if _rebound_elapsed < rebound_duration:
		deforming = false
		bouncing = false
	if bouncing or drop_dash_released:
		_shear = 0.0
	var target_shear: float = float(settings.get("shear", shear_strength)) if deforming else 0.0
	var launch_fraction: float = 0.0
	if active and _player.attached and _player._roll_action:
		launch_fraction = _player._roll_action.spindash_roll_remaining / RollAction.SPINDASH_ROLL_DURATION
	var launch_weight: float = pow(launch_fraction, 3.0)
	_forward_stretch = lerpf(_forward_stretch, spindash_forward_stretch * launch_weight, 1.0 - exp(-36.0 * maxf(delta, 0.0)))
	_shear = lerpf(_shear, target_shear, 1.0 - exp(-shear_response * maxf(delta, 0.0)))
	_bounce_stretch = lerpf(_bounce_stretch, bounce_fall_stretch_strength if bouncing else 0.0, 1.0 - exp(-shear_response * maxf(delta, 0.0)))
	_rebound_elapsed += maxf(delta, 0.0)
	var stretch: float = 1.0 + _bounce_stretch
	if _rebound_elapsed < rebound_duration and not _player._is_dead and not _player._hurt_active:
		var phase: float = _rebound_elapsed / rebound_duration
		stretch += -rebound_strength * cos(phase * TAU * rebound_cycles) * pow(1.0 - phase, 2.0)
	var width: float = 1.0 / sqrt(maxf(stretch, 0.1))
	var local_up: Vector3 = (_deformation.get_parent().global_basis.inverse() * _player.get_gravity_up()).normalized()
	var difference: float = stretch - width
	var vertical_basis: Basis = Basis(Vector3.RIGHT * width + local_up * difference * local_up.x, Vector3.UP * width + local_up * difference * local_up.y, Vector3.BACK * width + local_up * difference * local_up.z)
	var launch_width: float = 1.0 / sqrt(1.0 + _forward_stretch)
	var shear_basis: Basis = Basis(
		Vector3.RIGHT * launch_width,
		Vector3(0.0, launch_width, -_shear),
		Vector3.BACK * (1.0 + _forward_stretch)
	)
	var vertical_pivot: Vector3 = local_up * bottom_height
	var shear_pivot: Vector3 = Vector3(0.0, bottom_height, absf(bottom_height))
	var vertical_transform: Transform3D = Transform3D(vertical_basis, vertical_pivot - vertical_basis * vertical_pivot)
	var shear_transform: Transform3D = Transform3D(shear_basis, shear_pivot - shear_basis * shear_pivot)
	_deformation.transform = _base_transform * vertical_transform * shear_transform

func _reset_flicker() -> void:
	_clock = 0.0
	_ball_frame = false
	_flicker_steps_remaining = 2 + int(_flicker_random.randf() < flicker_stutter_chance)

func _advance_flicker(delta: float) -> void:
	_clock += maxf(delta, 0.0) * flicker_steps_per_second
	while _clock >= 1.0 - 0.000001:
		_clock = maxf(_clock - 1.0, 0.0)
		_flicker_steps_remaining -= 1
		if not _flicker_steps_remaining:
			_ball_frame = not _ball_frame
			_flicker_steps_remaining = (1 if _ball_frame else 2) + int(_flicker_random.randf() < flicker_stutter_chance)

func _restore_mesh_visibility() -> void:
	for visual: GeometryInstance3D in _character_meshes:
		if is_instance_valid(visual) and _mesh_visibility.has(visual):
			visual.visible = bool(_mesh_visibility[visual])
	_mesh_visibility.clear()

func _exit_tree() -> void:
	_restore_mesh_visibility()
	if is_instance_valid(_deformation):
		_deformation.transform = _base_transform
	if is_instance_valid(_ball):
		_ball.visible = _ball_visibility
	if is_instance_valid(_reader):
		_reader.free()

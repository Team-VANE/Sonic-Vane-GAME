extends Node3D
class_name SonicBoomFXController

## Node path to the omni light used by the boom effect.
@export var boom_light_path: NodePath = NodePath("BoomLight")
## Maximum light energy reached when the effect is fully progressed.
@export var boom_light_max_energy: float = 8.5
## Light range used by the boom pulse.
@export var boom_light_range: float = 4.5
## Progress at which the light reaches zero energy.
@export var boom_light_end_progress: float = 0.6
## Minimum visible energy threshold for the light.
@export var boom_light_visible_threshold: float = 0.01

var _boom_light: OmniLight3D = null
var _boom_alpha: float = 0.0
var _boom_progress: float = 0.0
var _boom_color: Color = Color(0.35, 0.8, 1.0, 1.0)


func _ready() -> void:
	_boom_light = get_node_or_null(boom_light_path) as OmniLight3D
	_apply_boom_light()


func set_boom_state(alpha: float, progress: float, color: Color = Color(0.35, 0.8, 1.0, 1.0)) -> void:
	_boom_alpha = clamp(alpha, 0.0, 1.0)
	_boom_progress = clamp(progress, 0.0, 1.0)
	_boom_color = color
	_apply_boom_light()


func _apply_boom_light() -> void:
	if _boom_light == null or not is_instance_valid(_boom_light):
		return

	var clamped_alpha: float = clamp(_boom_alpha, 0.0, 1.0)
	var clamped_progress: float = clamp(_boom_progress, 0.0, 1.0)
	var end_progress: float = clamp(boom_light_end_progress, 0.01, 1.0)
	var progress_factor: float = 1.0 - clamp(clamped_progress / end_progress, 0.0, 1.0)
	var energy: float = max(boom_light_max_energy, 0.0) * clamped_alpha * progress_factor

	_boom_light.shadow_enabled = false
	_boom_light.light_indirect_energy = 0.0
	_boom_light.omni_range = max(boom_light_range, 0.01)
	_boom_light.light_color = Color(_boom_color.r, _boom_color.g, _boom_color.b, 1.0)
	_boom_light.light_energy = energy
	_boom_light.visible = energy > boom_light_visible_threshold

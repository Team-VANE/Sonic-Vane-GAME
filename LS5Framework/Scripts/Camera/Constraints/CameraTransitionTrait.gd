@tool
extends Resource
class_name CameraTransitionTrait

enum Phase { ENTRY, EXIT }
enum Mode { INSTANT, TIMED }
enum Easing { LINEAR, SMOOTHSTEP, SINE }

## Entry or exit phase affected by this transition.
@export var phase: Phase = Phase.ENTRY
## Immediate cut or timed transition from the displayed camera pose.
@export var mode: Mode = Mode.INSTANT:
	set(value):
		mode = value
		notify_property_list_changed()
## Duration of the timed transition.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var duration: float = 0.35
## Curve applied to normalized transition time.
@export var easing: Easing = Easing.SMOOTHSTEP
## Applies the transition to camera position.
@export var position: bool = true
## Applies the transition to orientation and roll.
@export var orientation: bool = true
## Applies the transition to field of view.
@export var lens: bool = true

func _validate_property(property: Dictionary) -> void:
	if mode == Mode.INSTANT and property["name"] in ["duration", "easing"]:
		property["usage"] = PROPERTY_USAGE_NO_EDITOR

func get_weight(elapsed: float) -> float:
	if mode == Mode.INSTANT or duration <= 0.0:
		return 1.0
	var weight: float = clampf(elapsed / duration, 0.0, 1.0)
	match easing:
		Easing.SMOOTHSTEP:
			return weight * weight * (3.0 - 2.0 * weight)
		Easing.SINE:
			return 0.5 - 0.5 * cos(PI * weight)
	return weight

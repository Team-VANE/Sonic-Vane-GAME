@tool
extends Resource
class_name CameraTransitionTrait

enum Phase { ENTRY, EXIT }
enum Mode {
	## Cuts the selected channels immediately to the new pose.
	INSTANT,
	## Blends the selected channels from the displayed pose over Duration, using Easing.
	TIMED,
}
enum Easing { LINEAR, SMOOTHSTEP, SINE }

## Entry or exit phase affected by this transition.
@export var phase: Phase = Phase.ENTRY
## Transition from the displayed camera pose for the selected phase and channels.
## [br][b]Instant:[/b] Cuts the selected channels immediately to the new pose.
## [br][b]Timed:[/b] Blends the selected channels over Duration, using Easing.
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

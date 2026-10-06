class_name AbilityRoute
extends Resource

enum TriggerMode {
	NONE,
	JUST_PRESSED,
	PRESSED,
	JUST_RELEASED,
	MANUAL,
}

enum ActivationMode {
	EXECUTE,
	ACTIVATE,
	NEUTRAL_AIR,
	CLEAR_ACTIVE,
}

enum RequiredState {
	ANY,
	GROUNDED,
	AIRBORNE,
}

## Enables this route.
@export var enabled: bool = true
## Identifier added to route context when this route runs.
@export var route_id: StringName = &""
## Input that triggers this route.
@export var trigger_input: StringName = &""
## Input trigger mode used by this route.
@export var trigger_mode: TriggerMode = TriggerMode.JUST_PRESSED
## Target action node for execute or activate routes.
@export var target_action: NodePath
## How the route transitions when selected.
@export var activation_mode: ActivationMode = ActivationMode.EXECUTE
## Player state required for this route.
@export var required_state: RequiredState = RequiredState.ANY
## Higher priority routes are attempted first.
@export var priority: int = 0
## Reason added to route context when this route runs.
@export var reason: StringName = &"route"
## Source action ids allowed to use this route. Empty allows any source.
@export var allowed_source_actions: Array[StringName] = []
## Source action ids blocked from using this route.
@export var blocked_source_actions: Array[StringName] = []
## Blocks the route while the race countdown is active.
@export var block_during_race_countdown: bool = true

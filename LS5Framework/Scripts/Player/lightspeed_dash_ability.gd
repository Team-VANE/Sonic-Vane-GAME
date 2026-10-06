class_name LightspeedDashAbility
extends CharacterAbility

var _input_prompt_available: bool = false

@export_group("Lightspeed Dash")
@export_multiline var tooltip: String = "Lightspeed Dash triggers when the lightspeeddash input is pressed near rings."

@export_subgroup("Activation")
## Enables lightspeed dash execution.
@export var lightspeed_dash_enabled: bool = true
## Radius used to find the first ring.
@export var lightspeed_dash_start_radius: float = 18.0
## Radius used to find each following ring.
@export var lightspeed_dash_chain_radius: float = 15.0
## Distance at which a target ring is collected.
@export var lightspeed_dash_collect_distance: float = 1.15
## Minimum forward alignment required for a starting ring.
@export var lightspeed_dash_min_forward_dot: float = 0.0
## Maximum vertical difference allowed for a starting ring.
@export var lightspeed_dash_max_height_delta: float = 50.0

@export_subgroup("Movement")
## Minimum travel speed during lightspeed dash.
@export var lightspeed_dash_min_speed: float = 85.0
## Speed bonus derived from the character's incoming speed.
@export var lightspeed_dash_speed_bonus_per_speed: float = 0.1
## Extra camera search radius used for hybrid targeting.
@export var lightspeed_dash_camera_radius_bonus: float = 5.0
## Angle separating camera-priority and movement-priority targeting.
@export var lightspeed_dash_hybrid_angle_deg: float = 45.0
## Steering response while travelling between rings.
@export var lightspeed_dash_turn_rate: float = 20.0
## Adds a flat speed bonus when lightspeed dash begins.
@export var lightspeed_dash_start_additive_speed_enabled: bool = true
## Flat speed bonus added at lightspeed dash start.
@export var lightspeed_dash_start_additive_speed: float = 14.0
## Cooldown before the flat entry speed bonus can be granted again.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var lightspeed_dash_start_bonus_cooldown: float = 1.0
## Maximum speed allowed after the start bonus.
@export var lightspeed_dash_start_speed_cap: float = 220.0
## Faces the current ring target while dashing.
@export var lightspeed_dash_face_target: bool = true

@export_subgroup("Traversal")
## Maximum ring-chain steps processed per physics frame.
@export var lightspeed_dash_max_iterations_per_frame: int = 3
## Maximum duration of a lightspeed dash chain.
@export var lightspeed_dash_max_duration: float = 99.0

@export_subgroup("Exit")
## Attempts to attach to a nearby surface when the ring chain ends.
@export var lightspeed_dash_auto_attach_on_end: bool = true
## Maximum surface distance used by automatic end attachment.
@export var lightspeed_dash_auto_attach_max_distance: float = 8.5
## Allows automatic end attachment to use a wall when no floor-like surface is found.
@export var lightspeed_dash_auto_attach_allow_wall_fallback: bool = true

func _on_action_initialized() -> void:
	action_id = &"lightspeed_dash"
	allow_when_inactive = true
	trigger_mode = ActionTrigger.JUST_PRESSED
	if input_action == &"":
		input_action = StringName("lightspeeddash")


func receives_fast_fall_horizontal_drag_by_default() -> bool:
	return false


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if mode != ActionTrigger.JUST_PRESSED:
		return false
	if not should_trigger_from_input(input_name, mode):
		return false
	return execute({"reason": &"pressed", "input": input_name})


func get_input_prompt(_context: Dictionary = {}) -> Dictionary:
	if not input_prompt_enabled or not enabled or not lightspeed_dash_enabled or not owner_player:
		return {}
	if not _input_prompt_available or owner_player._lightspeed_dash_active or not owner_player.can_offer_action_prompts():
		return {}
	return {"label": input_prompt_name if input_prompt_name else "Light Speed Dash", "contextual": true, "display_priority": 90}


func update_input_prompt_availability() -> void:
	_input_prompt_available = false
	if not input_prompt_enabled or not enabled or not lightspeed_dash_enabled or not owner_player:
		return
	if not SettingsManager.action_prompts_visible or not SettingsManager.hud_visible or not owner_player.can_offer_action_prompts():
		return
	_input_prompt_available = owner_player.can_start_lightspeed_dash()


func can_execute(_context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if not enabled or not lightspeed_dash_enabled:
		return false
	if not owner_player.has_method("can_start_lightspeed_dash"):
		return false
	if owner_player._lightspeed_dash_active:
		return true
	return bool(owner_player.call("can_start_lightspeed_dash"))


func execute(context: Dictionary = {}) -> bool:
	if owner_player == null:
		return false
	if not owner_player.has_method("queue_lightspeed_dash"):
		return false
	var started: bool = bool(owner_player.call("queue_lightspeed_dash", context))
	if not started:
		return false
	activate(context)
	return true

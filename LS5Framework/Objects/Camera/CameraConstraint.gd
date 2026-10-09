@tool
extends Node3D
class_name CameraConstraint

signal activated(body: Node3D)
signal deactivated(reason: StringName)

enum CollisionMode { INHERIT, ENABLED, DISABLED }
enum UpMode { INHERIT, GRAVITY, PLAYER }

const LiveEdit = preload("res://LS5Framework/Scripts/Camera/Constraints/CameraConstraintLiveEdit.gd")

@export_group("Constraint")
## Enables activation and camera evaluation.
@export var enabled: bool = true
## Applies only while the last detected input is from a controller. Keyboard or mouse input suspends the constraint until controller input resumes.
@export var controller_only: bool = false
## Body group accepted by activation volumes. Empty accepts any camera target.
@export var require_group: StringName = &"player"
## Higher values take precedence. Equal priorities use the most recent activation.
@export var constraint_priority: int = 0
## Releases equal or lower priority constraints when this constraint activates.
@export var override_previous_constraints: bool = false
## Skips activation while another constraint is selected.
@export var ignore_when_constraint_active: bool = false
## Releases this constraint when a newer constraint with equal or greater priority activates.
@export var release_when_replaced: bool = false

@export_group("Traits")
## Volume, lifetime, and distance rules. Empty permits scripted activation only.
@export var activation_traits: Array[CameraActivationTrait] = []
## Camera placement or orbit-pivot traits. Earlier entries override later entries on their selected axes. Empty preserves normal player tracking.
@export var position_traits: Array[CameraPositionTrait] = []
## Aim and roll traits. Earlier entries override later entries on their selected axes. Unrestricted aim preserves additive roll. Empty preserves normal camera orientation.
@export var orientation_traits: Array[CameraOrientationTrait] = []
## Field of view and orbit-distance traits. Empty preserves the normal lens.
@export var lens_traits: Array[CameraLensTrait] = []
## Entry and exit transitions. Unassigned channels cut immediately.
@export var transition_traits: Array[CameraTransitionTrait] = []
## Proximity weights for position, orientation, and FOV. Unassigned channels retain full influence.
@export var influence_traits: Array[CameraInfluenceTrait] = []

@export_group("Modifiers")
## Blocks manual orbit and zoom while selected. Manual suppression can temporarily release this lock.
@export var disable_camera_controls: bool = true
## Collision policy applied to the final camera position.
@export var collision_mode: CollisionMode = CollisionMode.INHERIT
## Temporary camera up preference. Manual alignment changes take precedence until reactivation.
@export var up_mode: UpMode = UpMode.INHERIT
## Suppresses speed distance, height, FOV, and radial blur while selected.
@export var suppress_speed_effects: bool = false
## Temporarily releases camera control on manual look while keeping activation and lifetime rules active.
@export var suppress_on_manual_look: bool = true
## Delay after the last manual camera movement before movement or action input can restore this constraint.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var manual_suppression_duration: float = 1.5
## Smooth release and return duration for manual suppression, independently of normal entry and exit transitions.
@export_range(0.01, 10.0, 0.05, "or_greater", "suffix:s") var manual_suppression_blend_duration: float = 0.35
## Accumulates mouse look as an offset from constraint aim instead of suppressing on slight movement. Requires Suppress on Manual Look.
@export var mouse_offset_enabled: bool = true
## Accumulates controller look using the offset falloff and break thresholds. Disabled uses immediate manual suppression.
@export var controller_offset_enabled: bool = true
## Angular offset where mouse or controller look starts reducing constraint influence.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var mouse_offset_falloff_start_deg: float = 20.0
## Angular offset that fully releases the constraint until the normal suppression return conditions are met.
@export_range(1.0, 120.0, 0.5, "suffix:deg") var mouse_offset_break_deg: float = 80.0
## Idle period after mouse or controller movement before the offset starts returning toward the intended aim.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:s") var mouse_offset_grace_duration: float = 0.6
## Critically damped centering time. Larger values return more slowly without oscillation.
@export_range(0.05, 5.0, 0.05, "or_greater", "suffix:s") var mouse_offset_return_time: float = 0.45
## Permanently releases this constraint when manual look exceeds the rig's cancel thresholds. Takes precedence over temporary suppression.
@export var cancel_on_manual_look: bool = false
## Retains the displayed heading when a temporary orientation effect ends.
@export var retain_heading_on_release: bool = true

## Rig receiving this constraint's runtime registration.
var _camera_rig: Node3D = null
## Player associated with the current registration.
var _active_body: Node3D = null
var _registered: bool = false
var _blocked: bool = false
var _elapsed: float = 0.0
var _lifetime_ticks: int = 0
## Manual alignment takes precedence for the current activation.
var alignment_override_dismissed: bool = false
var _entry_areas: Array[Area3D] = []
## Entry volumes requiring an observed crossing after spawn or teleport.
var _crossing_areas: Array[Area3D] = []
var _entry_states: Dictionary = {}
var _activation_connections: Array[Dictionary] = []
var _occupancy_areas: Array[Area3D] = []
var _rearm_areas: Array[Area3D] = []
var _locked_transform: Transform3D = Transform3D.IDENTITY
var _has_locked_transform: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if OS.has_feature("editor") and EngineDebugger.is_active():
		add_to_group(&"LiveCameraConstraints")
		if not EngineDebugger.has_capture(LiveEdit.PREFIX):
			EngineDebugger.register_message_capture(LiveEdit.PREFIX, LiveEdit.capture)
		EngineDebugger.send_message("ls5_camera_edit:request", [])
	_refresh_activation_connections()


func _connect_activation_signal(source: Signal, callback: Callable) -> void:
	if not source.is_connected(callback):
		source.connect(callback)
	_activation_connections.append({"signal": source, "callback": callback})


func _refresh_activation_connections() -> void:
	for connection: Dictionary in _activation_connections:
		var source: Signal = connection.signal
		if not source.is_null() and source.is_connected(connection.callback):
			source.disconnect(connection.callback)
	_activation_connections.clear()
	_entry_areas.clear()
	_crossing_areas.clear()
	_occupancy_areas.clear()
	_rearm_areas.clear()
	_entry_states.clear()
	var host_area: Area3D = (self as Node) as Area3D
	for component: CameraActivationTrait in activation_traits:
		if not component or component.event in [CameraActivationTrait.Event.DURATION, CameraActivationTrait.Event.DISTANCE_EXIT]:
			continue
		var area: Area3D = resolve_trait_node(component.area_path) as Area3D
		if not area:
			push_warning("%s: activation area not found: %s" % [name, component.area_path])
			continue
		if host_area and area != host_area and area.collision_mask in [0, 1]:
			area.collision_mask = host_area.collision_mask
		area.monitoring = true
		match component.event:
			CameraActivationTrait.Event.OCCUPANCY:
				_occupancy_areas.append(area)
				_entry_areas.append(area)
				_connect_activation_signal(area.body_entered, _on_entry)
				_connect_activation_signal(area.body_exited, _on_occupancy_exit)
			CameraActivationTrait.Event.ENTER:
				_entry_areas.append(area)
				_crossing_areas.append(area)
				_connect_activation_signal(area.body_entered, _on_crossing_entry.bind(area))
			CameraActivationTrait.Event.EXIT:
				_connect_activation_signal(area.body_entered, _on_exit)
			CameraActivationTrait.Event.REARM:
				_rearm_areas.append(area)
				_connect_activation_signal(area.body_exited, _on_rearm)


func refresh_live_configuration(activation_changed: bool = true) -> void:
	if activation_changed:
		_refresh_activation_connections()
	if is_instance_valid(_camera_rig):
		var driver: CameraConstraintController = _camera_rig.get("_constraint_driver") as CameraConstraintController
		if driver:
			driver.refresh_configuration(self)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_entry_states()
	if not enabled:
		deactivate(&"disabled")
		return
	if _registered and not is_instance_valid(_active_body):
		deactivate(&"target_lost")
	if _blocked and not _registered:
		var boundaries: Array[Area3D] = _rearm_areas if not _rearm_areas.is_empty() else _entry_areas
		var inside: bool = false
		for area: Variant in boundaries:
			if is_instance_valid(area) and is_instance_valid(_active_body) and area.overlaps_body(_active_body):
				inside = true
		if not inside:
			_blocked = false
	if not _registered and not _blocked:
		for area: Variant in _occupancy_areas:
			if is_instance_valid(area):
				for body: Node3D in area.get_overlapping_bodies():
					if activate(body):
						return


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		if is_in_group(&"LiveCameraConstraints") and EngineDebugger.is_active() and EngineDebugger.has_capture(LiveEdit.PREFIX) and get_tree().get_nodes_in_group(&"LiveCameraConstraints").size() <= 1:
			EngineDebugger.send_message("ls5_camera_edit:suspend", [])
			EngineDebugger.unregister_message_capture(LiveEdit.PREFIX)
		deactivate(&"removed")


func activate(body: Node3D, rig: Node3D = null) -> bool:
	if not enabled or not is_input_allowed() or _registered or _blocked or not is_instance_valid(body):
		return false
	if require_group and not body.is_in_group(require_group):
		return false
	if not rig:
		for candidate: Node in get_tree().get_nodes_in_group("CameraRig"):
			if candidate.get("target") == body:
				rig = candidate as Node3D
				break
	if not rig or rig.get("target") != body:
		return false
	if ignore_when_constraint_active and rig.call("is_constraint_active"):
		return false
	rig.call("register_camera_constraint", self)
	return _registered


func is_input_allowed() -> bool:
	return not controller_only or SettingsManager.is_controller_input_active()


func deactivate(reason: StringName = &"released") -> void:
	if not _registered:
		return
	if is_instance_valid(_camera_rig):
		_camera_rig.call("unregister_camera_constraint", self, reason)
	else:
		on_unregistered(reason)


func on_registered(rig: Node3D) -> void:
	_camera_rig = rig
	_active_body = rig.get("target") as Node3D
	_registered = true
	_blocked = true
	_elapsed = 0.0
	_lifetime_ticks = 0
	alignment_override_dismissed = false
	activated.emit(_active_body)


func on_unregistered(reason: StringName = &"released") -> void:
	_registered = false
	_camera_rig = null
	deactivated.emit(reason)


func advance_lifetime(delta: float) -> bool:
	_elapsed += maxf(delta, 0.0)
	_lifetime_ticks += 1
	for component: CameraActivationTrait in activation_traits:
		if not component:
			continue
		if component.event == CameraActivationTrait.Event.DURATION:
			if _lifetime_ticks > 1 and _elapsed > maxf(component.duration, get_entry_duration()) + 0.000001:
				return false
		elif component.event == CameraActivationTrait.Event.DISTANCE_EXIT and is_instance_valid(_active_body):
			var reference: Node3D = resolve_trait_node(component.reference_path) as Node3D
			var origin: Vector3 = reference.global_position if reference else global_position
			if origin.distance_to(_active_body.global_position) > component.exit_distance:
				return false
	return enabled


func get_entry_duration() -> float:
	var duration: float = 0.0
	for component: CameraTransitionTrait in transition_traits:
		if component and component.phase == CameraTransitionTrait.Phase.ENTRY and component.mode == CameraTransitionTrait.Mode.TIMED:
			duration = maxf(duration, component.duration)
	return duration


func _on_entry(body: Node3D) -> void:
	activate(body)


func _update_entry_states() -> void:
	if _crossing_areas.is_empty():
		return
	for candidate: Node in get_tree().get_nodes_in_group("CameraRig"):
		var body: Node3D = candidate.get("target") as Node3D
		if not is_instance_valid(body):
			continue
		var revision: int = int(candidate.call("get_teleport_revision"))
		for area: Variant in _crossing_areas:
			if not is_instance_valid(area):
				continue
			var bodies: Dictionary = _entry_states.get_or_add(area.get_instance_id(), {})
			var state: Dictionary = bodies.get(body.get_instance_id(), {})
			if state.get("revision", -1) != revision:
				# Initial overlaps settle across two physics updates.
				state = {"revision": revision, "armed": false, "settle_frame": Engine.get_physics_frames() + 2}
			elif Engine.get_physics_frames() >= int(state["settle_frame"]) and not area.overlaps_body(body):
				state["armed"] = true
			bodies[body.get_instance_id()] = state


func _on_crossing_entry(body: Node3D, area: Area3D) -> void:
	var bodies: Dictionary = _entry_states.get(area.get_instance_id(), {})
	var state: Dictionary = bodies.get(body.get_instance_id(), {})
	if not state.get("armed", false):
		return
	state["armed"] = false
	for candidate: Node in get_tree().get_nodes_in_group("CameraRig"):
		if candidate.get("target") == body:
			if state.get("revision", -1) == int(candidate.call("get_teleport_revision")):
				activate(body, candidate as Node3D)
			return


func _on_occupancy_exit(body: Node3D) -> void:
	if body != _active_body:
		return
	for area: Variant in _occupancy_areas:
		if is_instance_valid(area) and area.overlaps_body(body):
			return
	deactivate(&"volume_exit")


func _on_exit(body: Node3D) -> void:
	if body == _active_body:
		deactivate(&"exit_volume")


func _on_rearm(body: Node3D) -> void:
	if body == _active_body:
		_blocked = false


func resolve_trait_node(path: NodePath) -> Node:
	if path.is_empty():
		return self
	return get_node_or_null(path)


func set_locked_transform(value: Transform3D) -> void:
	_locked_transform = value
	_has_locked_transform = true


func get_locked_transform() -> Transform3D:
	return _locked_transform if _has_locked_transform else global_transform


func has_influence_trait(channel: int = -1) -> bool:
	for component: CameraInfluenceTrait in influence_traits:
		if component and ((channel < 0 and (component.position or component.orientation or component.lens)) or component.affects_channel(channel)):
			return true
	return false


func get_influence_weights(player_position: Vector3) -> Vector3:
	var weights: Vector3 = Vector3.ONE
	var assigned: int = 0
	for component: CameraInfluenceTrait in influence_traits:
		if not component:
			continue
		var weight: float = component.get_weight(self, player_position)
		for channel: int in 3:
			var mask: int = 1 << channel
			if not assigned & mask and component.affects_channel(channel):
				weights[channel] = weight
				assigned |= mask
	return weights


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	for components: Array in [position_traits, orientation_traits]:
		for component: Resource in components:
			if not component or not component.limit_axes:
				continue
			if not component.axis_mask:
				warnings.append("Axis-limited traits require at least one selected axis.")
			if not component.axis_reference_path.is_empty() and not (resolve_trait_node(component.axis_reference_path) is Node3D):
				warnings.append("Axis reference requires a Node3D: %s" % component.axis_reference_path)
	var lens_count: int = 0
	var distance_count: int = 0
	for component: CameraLensTrait in lens_traits:
		if component:
			if component.mode == CameraLensTrait.Mode.ORBIT_DISTANCE:
				distance_count += 1
			else:
				lens_count += 1
	if lens_count > 1 or distance_count > 1:
		warnings.append("Only one FOV component and one distance component may be assigned.")
	for phase: int in 2:
		var channels: int = 0
		for component: CameraTransitionTrait in transition_traits:
			if component and component.phase == phase:
				var mask: int = int(component.position) | (int(component.orientation) << 1) | (int(component.lens) << 2)
				if channels & mask:
					warnings.append("Transition channels overlap within the same phase.")
				channels |= mask
	for component: CameraActivationTrait in activation_traits:
		if component and component.event < CameraActivationTrait.Event.DURATION and not (resolve_trait_node(component.area_path) is Area3D):
			warnings.append("Activation component requires an Area3D: %s" % component.area_path)
	var influence_channels: int = 0
	for component: CameraInfluenceTrait in influence_traits:
		if not component:
			continue
		var mask: int = int(component.position) | (int(component.orientation) << 1) | (int(component.lens) << 2)
		if influence_channels & mask:
			warnings.append("Influence channels overlap; the first component for each channel takes precedence.")
		influence_channels |= mask
		if not mask:
			warnings.append("Influence component requires at least one affected channel.")
		if not component.effective_axes & 7:
			warnings.append("Influence component requires at least one effective axis.")
		if component.full_influence_distance < 0.0 or component.zero_influence_distance <= component.full_influence_distance:
			warnings.append("Zero Influence Distance must exceed the nonnegative Full Influence Distance.")
		if component.power <= 0.0:
			warnings.append("Influence power must be positive.")
		if not (resolve_trait_node(component.reference_path) is Node3D):
			warnings.append("Influence component requires a Node3D reference: %s" % component.reference_path)
	return warnings

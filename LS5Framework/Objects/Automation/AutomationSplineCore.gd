@tool
extends Node3D
class_name AutomationSplineCore

const LiveEdit = preload("res://LS5Framework/Scripts/Player/Automation/AutomationLiveEdit.gd")

enum ActivationMode { OCCUPANCY, ENDPOINTS, SCRIPT_ONLY, AREA_CROSSINGS }
enum DirectionPolicy { BIDIRECTIONAL, FORWARD_ONLY, REVERSE_ONLY }

@export_group("Route")
## Enables registration and route tracking. Disabling releases every session immediately.
@export var enabled: bool = true:
	set(value):
		if enabled != value:
			activation_revision += 1
		enabled = value
		if not value:
			_release_sessions(&"disabled")
## Body group accepted by this route. Empty accepts compatible bodies from any group.
@export var require_group: StringName = &"player"
## Higher priorities win; equal priorities retain the most recent registration.
@export var priority: int = 0
## Path supplying canonical geometry, frame, and world-space arc distance.
@export_node_path("Path3D") var path_path: NodePath = NodePath("Path3D")
## Permitted entry directions. Canonical curve orientation remains unchanged during reversal.
@export var direction_policy: DirectionPolicy = DirectionPolicy.BIDIRECTIONAL

@export_group("Activation")
## Occupancy includes initial overlap. Endpoints require an observed signed crossing. Script Only requires registration through the player controller.
@export var activation_mode: ActivationMode = ActivationMode.ENDPOINTS
## Volume used for occupancy activation and release.
@export_node_path("Area3D") var volume_path: NodePath = NodePath("Volume")
## Start boundary volume. Its origin defines the boundary plane using the canonical start tangent.
@export_node_path("Area3D") var start_gate_path: NodePath = NodePath("Start")
## End boundary volume. Its origin defines the boundary plane using the canonical end tangent.
@export_node_path("Area3D") var end_gate_path: NodePath = NodePath("End")
## Maximum three-dimensional capture/tracking error. Zero disables distance release.
@export_range(0.0, 10000.0, 0.1, "or_greater", "suffix:m") var capture_distance: float = 12.0
## Permits entry through either area in Area Crossings mode. Disabled retains dedicated start-enter/end-release roles.
@export var area_crossings_bidirectional: bool = true
## Evaluates guided forces before the player's normal speed limits and slope response.
@export var integrate_before_speed_limits: bool = false
## Forward sample distance used for guided tangent evaluation. Zero uses transported sample frames.
@export_range(0.0, 100.0, 0.01) var sample_lookahead: float = 0.0
## Maximum adaptive tracking span. Zero leaves the displacement-based span unrestricted.
@export_range(0.0, 1000.0, 0.1) var maximum_tracking_window: float = 0.0
## Boundary side deadband. A nonzero side is retained while the body remains inside this band.
@export_range(0.001, 2.0, 0.001, "suffix:m") var crossing_deadband: float = 0.02
## Releases open-path sessions after crossing beyond either canonical end.
@export var release_at_path_ends: bool = true

@export_group("Tracking")
## Minimum connected arc neighborhood searched around predicted progress, in world meters.
@export_range(0.01, 1000.0, 0.1, "or_greater", "suffix:m") var tracking_window: float = 6.0
## Expands the arc search using measured body displacement between updates.
@export_range(1.0, 10.0, 0.1) var travel_window_multiplier: float = 2.0
## Local tracking error that permits a global recovery search. Zero keeps the current branch until capture distance releases it.
@export_range(0.0, 1000.0, 0.1, "or_greater", "suffix:m") var recovery_distance: float = 8.0
## Signed speed required to change travel direction. Slower motion retains the last direction.
@export_range(0.01, 20.0, 0.01, "suffix:m/s") var direction_speed_deadband: float = 0.5
## Path-aligned input intent required to choose direction near rest.
@export_range(0.01, 1.0, 0.01) var direction_input_deadband: float = 0.2

@export_group("Traits")
## Movement-intent and momentum heading resources. First applicable resource per steering mode wins.
@export var steering_traits: Array[AutomationSteeringTrait] = []
## Corridor or collision-tested confinement resources. First applicable position resource wins.
@export var position_traits: Array[AutomationPositionTrait] = []
## Drive, soft cap, and maximum-speed resources. Unassigned speed channels preserve normal physics.
@export var speed_traits: Array[AutomationSpeedTrait] = []
## Contact-frame and adhesion resources.
@export var surface_traits: Array[AutomationSurfaceTrait] = []
## Permissions and path-axis input resources.
@export var input_traits: Array[AutomationInputTrait] = []
## Independent entry and exit transitions. Unassigned channels change immediately.
@export var transition_traits: Array[AutomationTransitionTrait] = []
## Per-channel weights. Factors inside a resource multiply; the first resource per channel wins.
@export var influence_traits: Array[AutomationInfluenceTrait] = []

## Companion camera configurations. The first enabled binding uses the existing camera evaluator.
@export var camera_traits: Array[AutomationCameraTrait] = []

@export_group("Authoring")
## Draws route, confinement, capture, direction, and preview guides in the editor.
@export var show_authoring_guides: bool = true
## Canonical route fraction displayed by the static editor preview.
@export_range(0.0, 1.0, 0.001) var preview_progress: float = 0.5
## Travel direction displayed by the preview without reversing authored frames.
@export_enum("Forward:1", "Reverse:-1") var preview_direction: int = 1
## Signed preview speed magnitude used for speed-gated influence weights.
@export_range(0.0, 2000.0, 0.1) var preview_speed: float = 30.0
## Full world-space width of generated activation volumes.
@export_range(0.1, 1000.0, 0.1) var trigger_width: float = 8.0
## Full world-space height of generated activation volumes.
@export_range(0.1, 1000.0, 0.1) var trigger_height: float = 8.0
## World-space depth and segment overlap of generated endpoint gates.
@export_range(0.1, 100.0, 0.1) var trigger_gate_depth: float = 2.0
## Maximum world-space spacing of generated occupancy segments.
@export_range(0.1, 100.0, 0.1) var trigger_spacing: float = 8.0
## Shows a read-only runtime overlay for players selecting this route.
@export var debug_overlay_enabled: bool = false

var sampler: AutomationPathSampler = AutomationPathSampler.new()
var placement_triggers: Dictionary = {}
var placement_extensions: Array[Dictionary] = []
var activation_revision: int = 0
## Path currently watched for curve edits.
var _path: Path3D
## Occupancy area currently connected to immediate release notifications.
var _volume: Area3D
## Per-player controllers receiving source release notifications.
var _controllers: Array[WeakRef] = []


func _ready() -> void:
	if not placement_triggers.is_empty():
		_install_placement_triggers()
	if not placement_extensions.is_empty():
		_install_placement_extensions()
	if Engine.is_editor_hint():
		return
	add_to_group(&"AutomationSplineSources")
	_setup_live_edit()
	_bind_path()
	_bind_volume()
	process_physics_priority = -100


func _install_placement_extensions() -> void:
	for configuration: Dictionary in placement_extensions:
		var extension: Node3D
		if configuration["kind"] == "junction":
			var junction: AutomationRouteConnection = AutomationRouteConnection.new()
			var destination: String = configuration["destination"]
			junction.destination_path = NodePath("../../../Placement_%s/Object_%s" % [destination, destination])
			junction.name = "Junction"
			extension = junction
		else:
			extension = AutomationProgressMarker.new()
			extension.name = "ProgressEvent"
		for key: String in configuration["properties"]:
			extension.set(key, configuration["properties"][key])
		add_child(extension, true)


func _install_placement_triggers() -> void:
	var container: Node3D = build_trigger_geometry(true, placement_triggers.get("boxes", {}))
	if not container:
		return
	for path: NodePath in [volume_path, start_gate_path, end_gate_path]:
		var area: Area3D = get_node_or_null(path) as Area3D
		if area and area.get_parent() == self:
			remove_child(area)
			area.queue_free()
	add_child(container)
	volume_path = NodePath("_AutomationVolumes/Volume")
	start_gate_path = NodePath("_AutomationVolumes/Start")
	end_gate_path = NodePath("_AutomationVolumes/End")


func build_trigger_geometry(active_only: bool = false, boxes: Dictionary = {}) -> Node3D:
	sampler.configure(get_node_or_null(path_path) as Path3D)
	if not sampler.refresh():
		return null
	var existing: Node = get_node_or_null("_AutomationVolumes")
	if existing and not existing.get_meta(&"automation_generated", false):
		return null
	var container: Node3D = Node3D.new()
	container.name = "_AutomationVolumes"
	container.set_meta(&"automation_generated", true)
	container.set_meta(&"automation_basis", global_basis)
	var frame: Transform3D = Transform3D(Basis.IDENTITY, global_position)
	container.transform = global_transform.affine_inverse() * frame
	var inverse: Transform3D = frame.affine_inverse()
	var width: float = maxf(trigger_width, 0.1)
	var height: float = maxf(trigger_height, 0.1)
	var depth: float = maxf(trigger_gate_depth, 0.1)
	if not active_only or activation_mode in [ActivationMode.ENDPOINTS, ActivationMode.AREA_CROSSINGS]:
		for index: int in 2:
			var label: String = "Start" if index == 0 else "End"
			var gate: Area3D = _add_trigger_area(container, label, not active_only)
			if boxes.has(label):
				_add_custom_trigger_box(gate, boxes[label], inverse)
				continue
			var value: AutomationSample = sampler.sample(0.0 if index == 0 else sampler.length)
			gate.transform = inverse * value.get_transform()
			_add_trigger_box(gate, Vector3(width, height, depth), Transform3D.IDENTITY)
	if active_only and activation_mode != ActivationMode.OCCUPANCY:
		return container
	var volume: Area3D = _add_trigger_area(container, "Volume", true)
	if boxes.has("Volume"):
		_add_custom_trigger_box(volume, boxes["Volume"], inverse)
		return container
	var step: float = maxf(minf(trigger_spacing, width * 0.5), 0.1)
	var count: int = clampi(ceili(sampler.length / step), 1, 2048)
	for index: int in count:
		var start: AutomationSample = sampler.sample(sampler.length * float(index) / float(count))
		var finish: AutomationSample = sampler.sample(sampler.length * float(index + 1) / float(count))
		var middle: AutomationSample = sampler.sample(sampler.length * (float(index) + 0.5) / float(count))
		var tangent: Vector3 = (finish.position - start.position).normalized()
		if not tangent:
			tangent = middle.tangent
		var up: Vector3 = middle.up.slide(tangent).normalized()
		var side: Vector3 = tangent.cross(up).normalized()
		var pose: Transform3D = Transform3D(Basis(side, side.cross(tangent), -tangent), (start.position + finish.position) * 0.5)
		_add_trigger_box(volume, Vector3(width, height, start.position.distance_to(finish.position) + depth), inverse * pose)
	return container


func _add_custom_trigger_box(area: Area3D, box: Dictionary, inverse: Transform3D) -> void:
	area.transform = inverse * global_transform * (box["transform"] as Transform3D)
	_add_trigger_box(area, box["size"], Transform3D.IDENTITY)


func _add_trigger_area(container: Node3D, label: String, monitors_bodies: bool) -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = label
	area.collision_layer = 0
	area.collision_mask = 4
	area.monitoring = monitors_bodies
	area.monitorable = monitors_bodies
	container.add_child(area)
	return area


func _add_trigger_box(area: Area3D, size: Vector3, pose: Transform3D) -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Shape%d" % area.get_child_count()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.resource_local_to_scene = true
	shape.size = size
	collision.shape = shape
	collision.transform = pose
	area.add_child(collision)


func _bind_volume() -> void:
	var volume: Area3D = get_node_or_null(volume_path) as Area3D
	if _volume == volume:
		return
	if is_instance_valid(_volume) and _volume.body_exited.is_connected(_on_volume_exit):
		_volume.body_exited.disconnect(_on_volume_exit)
	_volume = volume
	if _volume:
		_volume.body_exited.connect(_on_volume_exit)


func _bind_path() -> void:
	var path: Path3D = get_node_or_null(path_path) as Path3D
	if _path == path:
		return
	if is_instance_valid(_path) and _path.curve_changed.is_connected(_on_curve_changed):
		_path.curve_changed.disconnect(_on_curve_changed)
	_path = path
	sampler.configure(_path)
	if _path:
		_path.curve_changed.connect(_on_curve_changed)


func _on_curve_changed() -> void:
	sampler.invalidate()
	if not sampler.refresh():
		_release_sessions(&"invalid_path")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_bind_path()
	_bind_volume()
	LiveEdit.poll(self)
	if not sampler.refresh():
		_release_sessions(&"invalid_path")


func _exit_tree() -> void:
	_release_sessions(&"removed")
	if is_instance_valid(_path) and _path.curve_changed.is_connected(_on_curve_changed):
		_path.curve_changed.disconnect(_on_curve_changed)
	if is_instance_valid(_volume) and _volume.body_exited.is_connected(_on_volume_exit):
		_volume.body_exited.disconnect(_on_volume_exit)
	_volume = null
	sampler.dispose()
	_path = null


func accepts(body: Node3D) -> bool:
	return enabled and is_inside_tree() and is_instance_valid(body) and (not require_group or body.is_in_group(require_group)) and sampler.refresh()


func attach_controller(controller: PlayerAutomationController) -> void:
	for reference: WeakRef in _controllers.duplicate():
		if not reference.get_ref():
			_controllers.erase(reference)
		if reference.get_ref() == controller:
			return
	_controllers.append(weakref(controller))


func _release_sessions(reason: StringName) -> void:
	for reference: WeakRef in _controllers.duplicate():
		var controller: PlayerAutomationController = reference.get_ref() as PlayerAutomationController
		if controller:
			controller.unregister_source(get_instance_id(), reason)
	_controllers.clear()


func _on_volume_exit(body: Node3D) -> void:
	if activation_mode != ActivationMode.OCCUPANCY:
		return
	for reference: WeakRef in _controllers.duplicate():
		var controller: PlayerAutomationController = reference.get_ref() as PlayerAutomationController
		if controller and controller.get_body() == body:
			controller.unregister_source(get_instance_id(), &"volume_exit")


func is_occupied(body: Node3D) -> bool:
	var volume: Area3D = get_node_or_null(volume_path) as Area3D
	return volume and volume.overlaps_body(body)


func permits_direction(direction: int) -> bool:
	return direction_policy == DirectionPolicy.BIDIRECTIONAL or (direction > 0 and direction_policy == DirectionPolicy.FORWARD_ONLY) or (direction < 0 and direction_policy == DirectionPolicy.REVERSE_ONLY)


func boundary_events(body: Node3D, previous: Vector3, current: Vector3, state: Dictionary, initialized: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if activation_mode == ActivationMode.AREA_CROSSINGS:
		return _area_crossings(body, previous, current, state, initialized)
	if activation_mode != ActivationMode.ENDPOINTS or sampler.closed or not sampler.refresh():
		return events
	var sides: Array = state.get("sides", [0, 0])
	var armed: Array = state.get("armed", [false, false])
	var pending: Dictionary = state.get("plane_crossings", {})
	for index: int in 2:
		var gate: Area3D = get_node_or_null(start_gate_path if index == 0 else end_gate_path) as Area3D
		if not gate or (body is CollisionObject3D and not (body as CollisionObject3D).collision_layer & gate.collision_mask):
			continue
		var endpoint: AutomationSample = sampler.sample(0.0 if index == 0 else sampler.length)
		var axis: Vector3 = endpoint.tangent
		var before: float = (previous - gate.global_position).dot(axis)
		var after: float = (current - gate.global_position).dot(axis)
		var side: int = 1 if after > crossing_deadband else (-1 if after < -crossing_deadband else 0)
		var old_side: int = int(sides[index])
		var fraction: float = 0.0
		if initialized and old_side:
			if after * float(old_side) >= 0.0:
				pending.erase(index)
			elif before * float(old_side) >= 0.0:
				fraction = clampf(-before / (after - before), 0.0, 1.0)
				pending[index] = previous.lerp(current, fraction)
		if side and old_side and side != old_side:
			if pending.has(index):
				var crossing: Vector3 = pending[index]
				var inward: bool = side > 0 if index == 0 else side < 0
				if contains_gate_point(gate, crossing) and (not inward or armed[index]):
					events.append({"fraction": fraction, "inward": inward, "direction": 1 if index == 0 else -1, "position": crossing})
					armed[index] = false
			pending.erase(index)
		if side:
			sides[index] = side
		if not contains_gate_point(gate, current):
			armed[index] = true
	state["sides"] = sides
	state["armed"] = armed
	state["plane_crossings"] = pending
	events.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.fraction) < float(second.fraction))
	return events


func contains_gate_point(gate: Area3D, point: Vector3) -> bool:
	for child: Node in gate.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if not collision or collision.disabled or not collision.shape or absf(collision.global_basis.determinant()) < 0.000001:
			continue
		var local: Vector3 = collision.to_local(point)
		var shape: Shape3D = collision.shape
		if shape is BoxShape3D:
			var half: Vector3 = (shape as BoxShape3D).size * 0.5
			if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
				return true
		elif shape is SphereShape3D and local.length_squared() <= pow((shape as SphereShape3D).radius, 2.0):
			return true
		elif shape is CapsuleShape3D:
			var capsule: CapsuleShape3D = shape as CapsuleShape3D
			var half_segment: float = maxf(capsule.height * 0.5 - capsule.radius, 0.0)
			var nearest: Vector3 = Vector3(0.0, clampf(local.y, -half_segment, half_segment), 0.0)
			if local.distance_squared_to(nearest) <= capsule.radius * capsule.radius:
				return true
		elif shape is CylinderShape3D:
			var cylinder: CylinderShape3D = shape as CylinderShape3D
			if absf(local.y) <= cylinder.height * 0.5 and Vector2(local.x, local.z).length_squared() <= cylinder.radius * cylinder.radius:
				return true
	return false


func beyond_open_end(position: Vector3, tracking: AutomationSample) -> bool:
	if not release_at_path_ends or sampler.closed:
		return false
	var start: AutomationSample = sampler.sample(0.0)
	var finish: AutomationSample = sampler.sample(sampler.length)
	return start.valid and finish.valid and ((tracking.distance < 0.001 and (position - start.position).dot(start.tangent) < -crossing_deadband) or (tracking.distance > sampler.length - 0.001 and (position - finish.position).dot(finish.tangent) > crossing_deadband))


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	for traits: Array in [steering_traits, position_traits, speed_traits, surface_traits, input_traits]:
		var assigned: Dictionary = {}
		for component: AutomationTrait in traits:
			if not component or not component.enabled:
				continue
			var key: int = int(component.get("mode"))
			if component is AutomationPositionTrait:
				key = 0
			elif component is AutomationSpeedTrait and key in [0, 1]:
				key = 0
			elif component is AutomationInputTrait and key in [1, 2]:
				key = 1
			var eligibility: int = int(component.grounded) | (int(component.airborne) << 1)
			if not eligibility:
				warnings.append("Enabled traits require ground or airborne eligibility.")
			if int(assigned.get(key, 0)) & eligibility:
				warnings.append("Trait channels overlap; earlier applicable resources take precedence.")
			assigned[key] = int(assigned.get(key, 0)) | eligibility
	for phase: int in 2:
		var channels: int = 0
		for component: AutomationTransitionTrait in transition_traits:
			if component and component.enabled and component.phase == phase:
				if channels & component.channels:
					warnings.append("Transition channels overlap within the same phase.")
				channels |= component.channels
	var channels: int = 0
	for component: AutomationInfluenceTrait in influence_traits:
		if component and component.enabled:
			if channels & component.channels:
				warnings.append("Influence channels overlap; the first resource for each channel wins.")
			channels |= component.channels
			if component.distance_falloff and component.zero_distance <= component.full_distance:
				warnings.append("Zero Distance must exceed Full Distance.")
			if component.progress_end < component.progress_start:
				warnings.append("Progress End must not precede Progress Start.")
	for component: AutomationInputTrait in input_traits:
		if component and component.release_influence >= component.engage_influence:
			warnings.append("Release Influence must be lower than Engage Influence.")
	var path: Path3D = get_node_or_null(path_path) as Path3D
	if not path or not path.curve or path.curve.point_count < 2:
		warnings.append("A Path3D with at least two curve points is required.")
	elif is_inside_tree() and path.global_basis.determinant() <= 0.000001:
		warnings.append("Route transforms must be nonsingular and nonmirrored.")
	if activation_mode == ActivationMode.OCCUPANCY and not get_node_or_null(volume_path) is Area3D:
		warnings.append("Occupancy requires an Area3D volume.")
	if activation_mode in [ActivationMode.ENDPOINTS, ActivationMode.AREA_CROSSINGS]:
		if path and path.curve and path.curve.closed:
			warnings.append("Closed routes require Occupancy or Script Only activation.")
		if start_gate_path == end_gate_path:
			warnings.append("Start and end gates must be distinct.")
		for gate_path: NodePath in [start_gate_path, end_gate_path]:
			var gate: Area3D = get_node_or_null(gate_path) as Area3D
			if not gate:
				warnings.append("Endpoints require distinct start and end Area3D nodes.")
				continue
			for child: Node in gate.get_children():
				if child is CollisionShape3D:
					var shape: Shape3D = (child as CollisionShape3D).shape
					if not (shape is BoxShape3D or shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D):
						warnings.append("Endpoint gates support box, sphere, capsule, and cylinder shapes.")
	if path and path.curve and is_inside_tree():
		sampler.configure(path)
		if not sampler.refresh():
			warnings.append(sampler.validation_message)
	for component: AutomationPositionTrait in position_traits:
		if component and component.mode == AutomationPositionTrait.Mode.RIBBON and not component is AutomationRibbonTrait:
			warnings.append("Ribbon mode requires an AutomationRibbonTrait resource.")
	var generated: Node3D = get_node_or_null("_AutomationVolumes") as Node3D
	if generated and generated.get_meta(&"automation_generated", false) and generated.has_meta(&"automation_basis"):
		if generated.get_meta(&"automation_basis") != global_basis:
			warnings.append("Route basis changed; regenerate generated triggers to retain world-space shape sizes.")
	for area_path: NodePath in [volume_path] if activation_mode == ActivationMode.OCCUPANCY else ([start_gate_path, end_gate_path] if activation_mode == ActivationMode.ENDPOINTS else []):
		var area: Area3D = get_node_or_null(area_path) as Area3D
		if not area:
			continue
		var usable: bool = false
		for child: Node in area.get_children():
			if child is CollisionShape3D and child.shape and not child.disabled:
				usable = true
		if not usable:
			warnings.append("Activation areas require an enabled collision shape.")
		if not area.collision_mask:
			warnings.append("Activation area collision mask accepts no bodies.")
	var junctions: Dictionary = {}
	for child: Node in get_children():
		if child is AutomationRouteConnection and child.enabled:
			warnings.append_array(child._get_configuration_warnings())
			var key: String = "%f:%d:%d" % [child.source_progress, child.source_direction, child.choice]
			if junctions.has(key):
				warnings.append("Duplicate junction choices use child order as precedence.")
			junctions[key] = true
	return warnings


func _setup_live_edit() -> void:
	if OS.has_feature("editor") and EngineDebugger.is_active():
		add_to_group(&"LiveAutomationSources")
		if not EngineDebugger.has_capture(LiveEdit.PREFIX):
			EngineDebugger.register_message_capture(LiveEdit.PREFIX, LiveEdit.capture)
		EngineDebugger.send_message("ls5_automation_edit:request", [])


func refresh_live_configuration(activation_changed: bool) -> void:
	if activation_changed:
		activation_revision += 1
		_release_sessions(&"reset")
	_bind_path()
	_bind_volume()
	sampler.invalidate()
	if not sampler.refresh():
		_release_sessions(&"invalid_path")
	for reference: WeakRef in _controllers:
		var controller: PlayerAutomationController = reference.get_ref() as PlayerAutomationController
		if controller and controller.motion.camera_binding:
			controller.motion.camera_binding.config.emit_changed()


func tracking_span(traveled: float) -> float:
	var span: float = maxf(tracking_window, traveled * travel_window_multiplier)
	return minf(span, maximum_tracking_window) if maximum_tracking_window > 0.0 else span


func tracking_sample(position: Vector3, preferred: float = -1.0, window: float = -1.0, predicted: float = -1.0, heading: Vector3 = Vector3.ZERO) -> AutomationSample:
	var value: AutomationSample = sampler.closest(position, preferred, tracking_window if window < 0.0 else window, predicted, recovery_distance, heading)
	if value.valid and sample_lookahead > 0.0:
		var ahead: AutomationSample = sampler.sample(value.distance + sample_lookahead)
		var tangent: Vector3 = (ahead.position - value.position).normalized()
		if tangent:
			value.tangent = tangent
			value.normal = value.normal.slide(tangent).normalized()
			if not value.normal:
				value.normal = tangent.cross(Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT).normalized()
			value.up = value.normal.cross(tangent).normalized()
	return value


func _area_crossings(body: Node3D, previous: Vector3, current: Vector3, state: Dictionary, initialized: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index: int in 2:
		var gate: Area3D = get_node_or_null(start_gate_path if index == 0 else end_gate_path) as Area3D
		if not gate or (body is CollisionObject3D and not body.collision_layer & gate.collision_mask):
			continue
		var key: String = "inside_%d" % index
		var inside: bool = contains_gate_point(gate, current)
		var was_inside: bool = bool(state[key]) if state.has(key) else contains_gate_point(gate, previous)
		state[key] = inside
		if not initialized or was_inside:
			continue
		var fraction: float = preload("res://LS5Framework/Scripts/Player/Automation/AutomationGateSweep.gd")._gate_entry(gate, previous, current)
		if fraction >= 0.0:
			var point: Vector3 = previous.lerp(current, fraction)
			var inward: bool = index == 0
			if area_crossings_bidirectional:
				var value: AutomationSample = sampler.closest(point)
				var speed: float = (current - previous).dot(value.tangent)
				if absf(speed) < 0.000001:
					continue
				inward = speed > 0.0 if index == 0 else speed < 0.0
			events.append({"fraction": fraction, "inward": inward, "direction": 1 if index == 0 else -1, "position": point})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction))
	return events

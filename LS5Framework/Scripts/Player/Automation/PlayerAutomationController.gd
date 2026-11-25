extends RefCounted
class_name PlayerAutomationController

const DebugOverlay = preload("res://LS5Framework/Scripts/Player/Automation/AutomationDebugOverlay.gd")

signal selected_changed(previous: AutomationSession, current: AutomationSession)
signal session_released(source_id: int, reason: StringName)

var selected: AutomationSession
var motion: PlayerAutomationInfluences
var routes: AutomationRouteRuntime
var last_release_reason: StringName = &""
## Player owning the registration, direction, and tracking state.
var _body_ref: WeakRef
## Optional runtime overlay owned by this player.
var _debug_overlay: CanvasLayer
var _sessions: Dictionary = {}
var _boundary_states: Dictionary = {}
var _blocked_sources: Dictionary = {}
var _sequence: int = 0
var _previous_position: Vector3 = Vector3.ZERO
var _has_previous: bool = false
var _clearing: bool = false
var _disposed: bool = false
var _intent: Vector3 = Vector3.ZERO


func _init(body: Node3D) -> void:
	_body_ref = weakref(body)
	body.add_to_group(&"AutomationDebugPlayers")
	motion = PlayerAutomationInfluences.new(self)
	routes = AutomationRouteRuntime.new(self)
	body.tree_exiting.connect(dispose, CONNECT_ONE_SHOT)


func get_body() -> Node3D:
	return _body_ref.get_ref() as Node3D if _body_ref else null


func get_session(source: Node3D) -> AutomationSession:
	return _sessions.get(source.get_instance_id()) as AutomationSession if is_instance_valid(source) else null


func _available() -> bool:
	var body: Node3D = get_body()
	return not _disposed and is_instance_valid(body) and body.is_inside_tree() and (not body.has_method("is_automation_tracking_available") or bool(body.call("is_automation_tracking_available")))


func register_source(source: AutomationSplineCore, initial_direction: int = 0,
		capture_position: Vector3 = Vector3(INF, INF, INF)) -> AutomationSession:
	return _register_source(source, initial_direction, capture_position, false)


func _register_source(source: AutomationSplineCore, initial_direction: int,
		capture_position: Vector3, rearm_at_boundary: bool) -> AutomationSession:
	var body: Node3D = get_body()
	if not _available() or not is_instance_valid(source):
		return null
	var source_id: int = source.get_instance_id()
	if (_blocked_sources.has(source_id) and not rearm_at_boundary) or not source.accepts(body):
		return null
	var existing: AutomationSession = get_session(source)
	if existing:
		return existing
	var position: Vector3 = capture_position if capture_position.is_finite() else body.global_position
	var velocity: Vector3 = _velocity(body)
	var sample: AutomationSample = source.tracking_sample(position, -1.0, source.tracking_window, -1.0, velocity.normalized())
	if not sample.valid or (source.capture_distance > 0.0 and sample.spatial_error > source.capture_distance):
		return null
	var direction: int = initial_direction if initial_direction else (-1 if source.direction_policy == AutomationSplineCore.DirectionPolicy.REVERSE_ONLY else 1)
	var signed_speed: float = velocity.dot(sample.tangent)
	if absf(signed_speed) > source.direction_speed_deadband:
		direction = 1 if signed_speed > 0.0 else -1
	elif absf(_intent.dot(sample.tangent)) > source.direction_input_deadband:
		direction = 1 if _intent.dot(sample.tangent) > 0.0 else -1
	if not source.permits_direction(initial_direction if initial_direction else direction):
		return null
	if rearm_at_boundary:
		_blocked_sources.erase(source_id)
	_sequence += 1
	var session: AutomationSession = AutomationSession.new()
	session.source_ref = weakref(source)
	session.source_id = source_id
	session.activation_frame = Engine.get_physics_frames()
	session.activation_sequence = _sequence
	session.direction = direction
	session.update_tracking(sample, source.sampler, velocity, _intent, 0.0,
		source.direction_speed_deadband, source.direction_input_deadband)
	session.previous_position = body.global_position
	_sessions[session.source_id] = session
	source.attach_controller(self)
	_select()
	return session


func unregister_source(source_id: int, reason: StringName = &"released") -> void:
	var session: AutomationSession = _sessions.get(source_id) as AutomationSession
	if not session:
		return
	_sessions.erase(source_id)
	session.release_reason = reason
	last_release_reason = reason
	if not _clearing:
		_select(true)
	session_released.emit(source_id, reason)


func clear(reason: StringName = &"reset") -> void:
	_clearing = true
	for source_id: int in _sessions.keys():
		unregister_source(source_id, reason)
	_clearing = false
	_boundary_states.clear()
	_blocked_sources.clear()
	_has_previous = false
	last_release_reason = reason
	_select()
	if motion:
		motion.selection_changed(null, null)


func release_source(source: Node3D, reason: StringName = &"breakaway") -> void:
	if not is_instance_valid(source):
		return
	_blocked_sources[source.get_instance_id()] = true
	unregister_source(source.get_instance_id(), reason)


func rearm_source(source: Node3D) -> void:
	if is_instance_valid(source):
		_blocked_sources.erase(source.get_instance_id())


func dispose() -> void:
	if _disposed:
		return
	clear(&"target_removed")
	_disposed = true
	if is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
	_debug_overlay = null
	_body_ref = null


func advance(delta: float, input_intent: Vector3 = Vector3.ZERO) -> void:
	if not _available():
		clear(&"target_unavailable")
		return
	var body: Node3D = get_body()
	var position: Vector3 = body.global_position
	var previous_selected: AutomationSession = selected
	var previous_progress: float = selected.unwrapped_progress if selected else 0.0
	var previous_revision: int = selected.sample.revision if selected and selected.sample else -1
	var displacement: float = position.distance_to(selected.previous_position) if selected else 0.0
	_intent = input_intent if input_intent.is_finite() else Vector3.ZERO
	if not position.is_finite():
		clear(&"invalid_position")
		return
	var sources: Array[Node] = body.get_tree().get_nodes_in_group(&"AutomationSplineSources")
	var live_ids: Dictionary = {}
	var occupancy_checks: Array[Dictionary] = []
	var pending_boundaries: Array[Dictionary] = []
	for candidate: Node in sources:
		var source: AutomationSplineCore = candidate as AutomationSplineCore
		if not source:
			continue
		var id: int = source.get_instance_id()
		live_ids[id] = true
		if source.activation_mode == AutomationSplineCore.ActivationMode.OCCUPANCY:
			var occupied: bool = source.is_occupied(body)
			if occupied or _sessions.has(id) or _blocked_sources.has(id):
				occupancy_checks.append({"source": source, "path": String(source.get_path()), "occupied": occupied})
			continue
		if source.activation_mode == AutomationSplineCore.ActivationMode.SCRIPT_ONLY and not _sessions.has(id) and not _blocked_sources.has(id):
			continue
		if not source.accepts(body):
			unregister_source(id, &"source_unavailable")
			_boundary_states.erase(id)
			_blocked_sources.erase(id)
			continue
		if source.activation_mode in [AutomationSplineCore.ActivationMode.ENDPOINTS, AutomationSplineCore.ActivationMode.AREA_CROSSINGS]:
			var state: Dictionary = _boundary_states.get_or_add(id, {})
			if int(state.get("revision", -1)) != source.activation_revision:
				state.clear()
				state["revision"] = source.activation_revision
			var events: Array[Dictionary] = source.boundary_events(body, _previous_position, position, state, _has_previous)
			if not events.is_empty():
				pending_boundaries.append({"source": source, "path": String(source.get_path()), "events": events,
					"rearm": _blocked_sources.has(id)})
	if occupancy_checks.size() > 1:
		occupancy_checks.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.path < second.path)
	for check: Dictionary in occupancy_checks:
		var source: AutomationSplineCore = check.source
		if not is_instance_valid(source):
			continue
		var id: int = source.get_instance_id()
		if not source.accepts(body):
			unregister_source(id, &"source_unavailable")
			_boundary_states.erase(id)
			_blocked_sources.erase(id)
		elif check.occupied:
			if not _sessions.has(id):
				register_source(source)
		else:
			unregister_source(id, &"volume_exit")
			_blocked_sources.erase(id)
	for id: int in _boundary_states.keys():
		if not live_ids.has(id):
			_boundary_states.erase(id)
	for id: int in _sessions.keys():
		var session: AutomationSession = _sessions.get(id) as AutomationSession
		if not session:
			continue
		var source: AutomationSplineCore = session.get_source() as AutomationSplineCore
		if not is_instance_valid(source) or not source.accepts(body):
			unregister_source(id, &"source_unavailable")
			continue
		var velocity: Vector3 = _velocity(body)
		var traveled: float = position.distance_to(session.previous_position)
		var window: float = source.tracking_span(traveled)
		var predicted: float = source.sampler.wrap_distance(session.unwrapped_progress + session.signed_speed * maxf(delta, 0.0))
		var value: AutomationSample = source.tracking_sample(position, session.sample.distance, window, predicted, velocity.normalized())
		if not value.valid or (source.capture_distance > 0.0 and value.spatial_error > source.capture_distance):
			unregister_source(id, &"capture_distance")
			continue
		session.update_tracking(value, source.sampler, velocity, _intent, delta,
			source.direction_speed_deadband, source.direction_input_deadband)
		session.previous_position = position
	_previous_position = position
	_has_previous = true
	_select()
	if selected and selected == previous_selected and selected.sample.revision == previous_revision:
		routes.advance(selected, previous_progress, delta, displacement)
	var transferred: bool = previous_selected and previous_selected.release_reason == &"route_transfer"
	if pending_boundaries.size() > 1:
		pending_boundaries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.path < second.path)
	for boundary: Dictionary in pending_boundaries:
		var source: AutomationSplineCore = boundary.source
		if not is_instance_valid(source):
			continue
		for event: Dictionary in boundary.events:
			if not is_instance_valid(source):
				break
			if event.inward:
				var owner: AutomationSplineCore = selected.get_source() as AutomationSplineCore if selected else null
				if not transferred or not owner or source == owner or source.priority > owner.priority:
					_register_source(source, int(event.direction), event.position, boundary.rearm)
			else:
				var id: int = source.get_instance_id()
				unregister_source(id, &"endpoint_exit")
				if boundary.rearm:
					_blocked_sources.erase(id)
	for id: int in _sessions.keys():
		var session: AutomationSession = _sessions.get(id) as AutomationSession
		if not session:
			continue
		var source: AutomationSplineCore = session.get_source() as AutomationSplineCore
		if source and source.beyond_open_end(position, session.sample):
			unregister_source(id, &"path_end")
	if motion:
		motion.prepare(delta)
	_update_debug_overlay()


func _velocity(body: Node3D) -> Vector3:
	var value: Variant = body.get("velocity")
	return value as Vector3 if value is Vector3 and (value as Vector3).is_finite() else Vector3.ZERO


func get_body_velocity() -> Vector3:
	return _velocity(get_body())


func is_source_blocked(source: AutomationSplineCore) -> bool:
	return _blocked_sources.has(source.get_instance_id())


func can_select_transfer(previous: AutomationSession, destination: AutomationSplineCore) -> bool:
	if not _available() or selected != previous:
		return false
	for session: AutomationSession in _sessions.values():
		var source: AutomationSplineCore = session.get_source() as AutomationSplineCore
		if session != previous and source and source != destination and source.priority > destination.priority:
			return false
	return true


func commit_transfer(previous: AutomationSession, destination: AutomationSplineCore,
		value: AutomationSample, direction: int, velocity: Vector3) -> AutomationSession:
	if not can_select_transfer(previous, destination):
		return null
	var body: Node3D = get_body()
	var current: AutomationSession = AutomationSession.new()
	_sequence += 1
	current.source_ref = weakref(destination)
	current.source_id = destination.get_instance_id()
	current.activation_frame = Engine.get_physics_frames()
	current.activation_sequence = _sequence
	current.direction = direction
	current.update_tracking(value, destination.sampler, velocity, Vector3.ZERO, 0.0,
		destination.direction_speed_deadband, destination.direction_input_deadband)
	current.previous_position = body.global_position
	_sessions.erase(previous.source_id)
	_blocked_sources[previous.source_id] = true
	previous.release_reason = &"route_transfer"
	last_release_reason = &"route_transfer"
	_sessions[current.source_id] = current
	destination.attach_controller(self)
	body.set("velocity", velocity)
	_select()
	session_released.emit(previous.source_id, &"route_transfer")
	return current if selected == current else null


func _select(revalidate: bool = false) -> void:
	var winner: AutomationSession = null
	var winner_priority: int = -2147483648
	var dropped: Array[AutomationSession] = []
	for session: AutomationSession in _sessions.values():
		var source: AutomationSplineCore = session.get_source() as AutomationSplineCore
		if not is_instance_valid(source):
			continue
		if revalidate:
			var body: Node3D = get_body()
			if not is_instance_valid(body) or not source.accepts(body):
				dropped.append(session)
				continue
			var traveled: float = body.global_position.distance_to(session.previous_position)
			var value: AutomationSample = source.tracking_sample(body.global_position, session.sample.distance,
				source.tracking_span(traveled))
			if not value.valid or (source.capture_distance > 0.0 and value.spatial_error > source.capture_distance) or source.beyond_open_end(body.global_position, value):
				dropped.append(session)
				continue
		if not winner or source.priority > winner_priority or (source.priority == winner_priority and session.activation_sequence > winner.activation_sequence):
			winner = session
			winner_priority = source.priority
	for session: AutomationSession in dropped:
		_sessions.erase(session.source_id)
		session.release_reason = &"resume_invalid"
	if selected != winner:
		var previous: AutomationSession = selected
		selected = winner
		if motion:
			motion.selection_changed(previous, selected)
		selected_changed.emit(previous, selected)
	for session: AutomationSession in dropped:
		session_released.emit(session.source_id, session.release_reason)


func _update_debug_overlay() -> void:
	var source: AutomationSplineCore = selected.get_source() as AutomationSplineCore if selected else null
	var body: Node3D = get_body()
	if source and source.debug_overlay_enabled and body and body.is_multiplayer_authority():
		if not is_instance_valid(_debug_overlay):
			_debug_overlay = DebugOverlay.new()
			_debug_overlay.set("controller_ref", weakref(self))
			body.add_child(_debug_overlay)
		_debug_overlay.set("source_ref", weakref(source))


func get_diagnostics() -> Dictionary:
	var body: Node3D = get_body()
	var source: Node3D = selected.get_source() if selected else null
	var value: AutomationSample = selected.sample if selected else null
	var details: Dictionary = motion.get_diagnostics() if motion else {}
	return {"player": String(body.name) if body else "removed", "source": String(source.get_path()) if is_instance_valid(source) else "No active route",
		"progress": selected.unwrapped_progress if selected else 0.0, "branch": value.segment if value else -1,
		"direction": selected.direction if selected else 0, "speed": selected.signed_speed if selected else 0.0,
		"tracking_error": value.spatial_error if value else 0.0, "weights": details.get("weights", {}),
		"blocked_actions": details.get("blocked_actions", PackedStringArray()), "correction": details.get("correction", 0.0),
		"obstruction": details.get("obstruction", false), "suspended": details.get("suspended", false),
		"last_release": String(last_release_reason) if last_release_reason else "none",
		"lane": int(selected.route_state.get("lane", -1)) if selected else -1,
		"buffered_choice": int(selected.route_state.get("choice", 0)) if selected else 0}

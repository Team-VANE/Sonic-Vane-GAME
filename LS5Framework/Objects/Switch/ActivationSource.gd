class_name ActivationSource
extends Node

signal active_changed(active: bool, actor: Node3D)
signal activation_started(actor: Node3D)
signal countdown_tick
signal expired

enum Mode { LATCHED, TIMED, TOGGLE }

const LONGEST_INTERVAL: float = 1.5
const SHORTEST_INTERVAL: float = 0.08

## Determines whether activation latches, expires on a timer, or toggles on each press.
@export var mode: Mode = Mode.LATCHED
## Countdown time available after activation.
@export_range(0.1, 300.0, 0.1, "or_greater", "suffix:s") var duration: float = 10.0
## Pauses the countdown while the trigger reports a held press.
@export var hold_timer_while_pressed: bool = true
## A fresh press while active restarts the countdown.
@export var restart_timer_on_press: bool = false
## Time before expiry during which the beep interval shortens.
@export_range(0.1, 30.0, 0.1, "or_greater", "suffix:s") var acceleration_window: float = 3.0

var is_active: bool = false
var remaining: float = 0.0
var _pressed: bool = false
var _next_tick: float = 0.0
var _actor: WeakRef
var _receivers: Array[WeakRef] = []


func _ready() -> void:
	_sync_processing()


func _exit_tree() -> void:
	_update_receivers(false)


func set_targets(origin: Node, paths: Array[NodePath]) -> void:
	_update_receivers(false)
	_receivers.clear()
	var seen: Dictionary = {}
	for path: NodePath in paths:
		var target: Node = origin.get_node_or_null(path)
		if not target or not target.has_method(&"set_activation_source"):
			push_warning("%s has an invalid activation target: %s" % [origin.name, path])
		elif not seen.has(target):
			seen[target] = true
			_receivers.append(weakref(target))
	_update_receivers(is_active)


func press(actor: Node3D = null) -> void:
	if is_active and mode == Mode.TOGGLE:
		deactivate()
	else:
		activate(actor)


func set_pressed(pressed: bool) -> void:
	if _pressed != pressed:
		_pressed = pressed
		_sync_processing()


func activate(actor: Node3D = null) -> void:
	if is_active and (mode != Mode.TIMED or not restart_timer_on_press):
		return
	_actor = weakref(actor) if is_instance_valid(actor) else null
	if mode == Mode.TIMED:
		remaining = maxf(duration, 0.1)
		_next_tick = _beep_interval()
	var changed: bool = not is_active
	is_active = true
	_sync_processing()
	if changed:
		_update_receivers(true)
		active_changed.emit(true, actor)
	activation_started.emit(actor)


func deactivate() -> void:
	if not is_active:
		return
	var actor: Node3D = get_actor()
	is_active = false
	remaining = 0.0
	_actor = null
	_sync_processing()
	_update_receivers(false)
	active_changed.emit(false, actor)


func get_actor() -> Node3D:
	return _actor.get_ref() as Node3D if _actor else null


func _sync_processing() -> void:
	set_physics_process(is_active and mode == Mode.TIMED and not (_pressed and hold_timer_while_pressed))


func _physics_process(delta: float) -> void:
	remaining = maxf(remaining - delta, 0.0)
	if remaining <= 0.0:
		expired.emit()
		deactivate()
		return
	_next_tick -= delta
	if _next_tick <= 0.000001:
		countdown_tick.emit()
		_next_tick = _beep_interval()


func _beep_interval() -> float:
	var window: float = minf(maxf(acceleration_window, 0.1), maxf(duration, 0.1))
	var interval: float = lerpf(SHORTEST_INTERVAL, LONGEST_INTERVAL, pow(clampf(remaining / window, 0.0, 1.0), 2.0))
	return clampf(minf(interval, remaining * 0.5), SHORTEST_INTERVAL, LONGEST_INTERVAL)


func _update_receivers(enabled: bool) -> void:
	for receiver: WeakRef in _receivers:
		var target: Node = receiver.get_ref() as Node
		if target and target.is_inside_tree():
			target.call(&"set_activation_source", self, enabled)

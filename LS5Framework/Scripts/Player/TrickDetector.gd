class_name TrickDetector
extends Node

const TRICK_ROTATION_THRESHOLD: float = PI / 2.0

var _last_model_basis: Basis = Basis()
var _current_trick_type: int = TrickSystem.TrickType.NONE
var _trick_start_time: float = 0.0
var _trick_in_progress: bool = false
var _accumulated_rotation: Vector3 = Vector3.ZERO
var _basis_initialized: bool = false
var _current_trick_axis: int = TrickSystem.TrickAxis.PITCH

signal trick_detected(trick_type: int)

func _ready() -> void:
	pass

func reset() -> void:
	_last_model_basis = Basis()
	_current_trick_type = TrickSystem.TrickType.NONE
	_trick_in_progress = false
	_current_trick_axis = TrickSystem.TrickAxis.PITCH
	_reset_accumulated_rotation()

func update_trick_detection(model_basis: Basis, current_time: float, torque_yaw_delta: float = 0.0) -> void:
	if not _basis_initialized:
		_last_model_basis = model_basis
		_basis_initialized = true
		return

	var delta_basis: Basis = _last_model_basis.inverse() * model_basis
	var q_delta: Quaternion = delta_basis.get_rotation_quaternion()
	
	var angle: float = q_delta.get_angle()
	var axis: Vector3 = q_delta.get_axis()
	
	if is_nan(axis.x) or is_nan(axis.y) or is_nan(axis.z):
		_last_model_basis = model_basis
		return
	if angle < 0.001 and absf(torque_yaw_delta) < 0.001:
		_last_model_basis = model_basis
		return
	
	# Accumulate signed local rotation per axis
	var q_euler: Vector3 = q_delta.get_euler()
	q_euler.y = torque_yaw_delta
	_accumulated_rotation += q_euler
	
	_last_model_basis = model_basis

	# Check for trick completion based on total absolute accumulation
	var total_accumulation: float = abs(_accumulated_rotation.x) + abs(_accumulated_rotation.y) + abs(_accumulated_rotation.z)
	
	if not _trick_in_progress:
		if total_accumulation >= TRICK_ROTATION_THRESHOLD:
			_start_trick(current_time)
	else:
		if total_accumulation >= (1.5 * PI): # 270 degrees for completion
			_complete_trick(current_time)

func _start_trick(current_time: float) -> void:
	_trick_in_progress = true
	_trick_start_time = current_time
	push_warning("trick attempt started")

func _complete_trick(current_time: float) -> void:
	# Determine dominant axis and direction at the moment of completion
	var x: float = _accumulated_rotation.x
	var y: float = _accumulated_rotation.y
	var z: float = _accumulated_rotation.z
	
	var abs_x: float = abs(x)
	var abs_y: float = abs(y)
	var abs_z: float = abs(z)
	
	var trick_type: int = TrickSystem.TrickType.NONE
	
	# Determine if this is a diagonal trick (Pitch + Yaw)
	# Triggered when Pitch and Yaw are both significant and similar in magnitude
	var is_diagonal: bool = false
	if abs_x > 0.5 and abs_y > 0.5:
		var diff: float = abs(abs_x - abs_y)
		var avg: float = (abs_x + abs_y) * 0.5
		if diff < avg: # More same than different
			is_diagonal = true
	
	if is_diagonal:
		if x > 0:
			# Backflip-based diagonal tricks
			trick_type = TrickSystem.TrickType.BACKFLIP_RIGHT_SPIN if y > 0 else TrickSystem.TrickType.BACKFLIP_LEFT_SPIN
		else:
			# Frontflip-based diagonal tricks
			trick_type = TrickSystem.TrickType.FRONTFLIP_RIGHT_SPIN if y > 0 else TrickSystem.TrickType.FRONTFLIP_LEFT_SPIN
	elif abs_x >= abs_y and abs_x >= abs_z:
		# Pitch axis (Flips)
		# In Godot's right-handed system, negative X is usually Frontflip, positive is Backflip
		trick_type = TrickSystem.TrickType.BACKFLIP if x > 0 else TrickSystem.TrickType.FRONTFLIP
	elif abs_y >= abs_x and abs_y >= abs_z:
		# Yaw axis (Spins/Grabs)
		trick_type = TrickSystem.TrickType.RIGHT_SPIN if y > 0 else TrickSystem.TrickType.LEFT_SPIN
	else:
		# Pure Roll axis (or fallback)
		trick_type = TrickSystem.TrickType.FRONTFLIP_LEFT_SPIN if z > 0 else TrickSystem.TrickType.BACKFLIP_LEFT_SPIN

	if trick_type != TrickSystem.TrickType.NONE:
		push_warning("!!! TRICK DETECTOR SUCCESS: %d (x=%.2f, y=%.2f, z=%.2f) !!!" % [trick_type, x, y, z])
		trick_detected.emit(trick_type)
		
		# Bulletproof fallback: search up the tree for the player
		var p = owner
		if p == null or not p.has_method("_on_trick_detected"):
			p = get_parent()
			while p != null and not p.has_method("_on_trick_detected"):
				p = p.get_parent()
		
		if p != null:
			push_warning("Calling player directly: %s" % p.name)
			p._on_trick_detected(trick_type)
		else:
			push_warning("Could not find player node to notify!")

	_trick_in_progress = false
	_accumulated_rotation = Vector3.ZERO

func _reset_accumulated_rotation() -> void:
	_accumulated_rotation = Vector3.ZERO
	_basis_initialized = false

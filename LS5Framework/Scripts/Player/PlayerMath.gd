extends Object
class_name PlayerMath

# SUMMARY:
# - Shared, pure math helpers used by PlayerController and related modules.
# - No node state or side effects; callers supply all inputs.
# - Centralizes common calculations so gameplay logic stays focused.


static func sample_curve_by_speed(curve: Curve, speed: float, fallback_value: float) -> float:
	# SUMMARY: Sample a Curve by clamped speed, or return a fallback if missing.
	# STEPS:
	# - Step 1: Validate the curve and clamp speed to its max X.
	# - Step 2: Sample the curve at the clamped X value.
	# - Step 3: Fallback when the curve is missing or empty.
	if curve != null and curve.get_point_count() > 0:
		# Step 1: Clamp speed to the curve's last key.
		var point_count: int = curve.get_point_count()
		var max_x: float = curve.get_point_position(point_count - 1).x
		var x: float = clamp(speed, 0.0, max_x)
		# Step 2: Sample the curve.
		return curve.sample(x)
	# Step 3: Fallback value when the curve is not usable.
	return fallback_value


static func basis_from_to(from: Vector3, to: Vector3) -> Basis:
	# SUMMARY: Build a rotation basis that aligns one direction vector to another.
	# STEPS:
	# - Step 1: Normalize inputs and early-out for degenerate vectors.
	# - Step 2: Handle nearly-identical and opposite directions.
	# - Step 3: Compute a rotation basis around the cross-product axis.
	var f: Vector3 = from.normalized()
	var t: Vector3 = to.normalized()

	# Step 1: Validate inputs.
	if f.length() < 0.001 or t.length() < 0.001:
		return Basis.IDENTITY

	var cos_theta: float = clamp(f.dot(t), -1.0, 1.0)

	# Step 2: Nearly the same direction.
	if cos_theta > 0.9999:
		return Basis.IDENTITY

	# Step 2: Opposite direction (180 degrees).
	if cos_theta < -0.9999:
		var axis: Vector3 = f.cross(Vector3.RIGHT)
		if axis.length() < 0.001:
			axis = f.cross(Vector3.FORWARD)
		axis = axis.normalized()
		return Basis(axis, PI)

	# Step 3: General case rotation around cross(from, to).
	var axis: Vector3 = f.cross(t)
	var axis_len: float = axis.length()
	if axis_len < 0.0001:
		return Basis.IDENTITY
	axis /= axis_len

	var angle: float = acos(cos_theta)
	return Basis(axis, angle)


static func compute_radial_landing_metrics(v: Vector3, n: Vector3) -> Dictionary:
	# SUMMARY: Decompose velocity into tangential vs into-surface components for landing logic.
	# STEPS:
	# - Step 1: Normalize the surface normal and early-out for tiny velocities.
	# - Step 2: Compute into-surface speed and tangential speed.
	# - Step 3: Derive an impact angle for debugging/threshold logic.
	var n_norm: Vector3 = n.normalized()
	var v_len: float = v.length()
	if v_len < 0.0001:
		# Step 1: Tiny velocity has no meaningful impact data.
		return {
			"angle": 0.0,
			"into_speed": 0.0,
			"tangent_speed": 0.0
		}

	# Step 2: Split velocity into normal and tangential components.
	var into_speed: float = -v.dot(n_norm) # positive when moving into the surface
	var tangent_vec: Vector3 = v + n_norm * into_speed
	var tangent_speed: float = tangent_vec.length()

	# Step 3: Impact angle (0 = sliding, 90 = straight in).
	var angle: float = 0.0
	if into_speed > 0.0 or tangent_speed > 0.0001:
		angle = rad_to_deg(atan2(max(into_speed, 0.0), max(tangent_speed, 0.0001)))

	return {
		"angle": angle,
		"into_speed": into_speed,
		"tangent_speed": tangent_speed
	}


static func vel_to_local(v: Vector3, forward: Vector3, right: Vector3, up: Vector3) -> Vector3:
	# SUMMARY: Convert a world-space velocity into a local forward/up/right frame.
	# STEPS:
	# - Step 1: Project velocity onto each local axis.
	return Vector3(
		# Step 1: Dot each axis for local components.
		v.dot(forward),  # local forward
		v.dot(up),       # local up
		v.dot(right)     # local right
	)


static func vel_from_local(s: Vector3, forward: Vector3, right: Vector3, up: Vector3) -> Vector3:
	# SUMMARY: Convert a local forward/up/right velocity into world space.
	# STEPS:
	# - Step 1: Combine the local components along each axis.
	return forward * s.x + up * s.y + right * s.z


static func get_curve_tangent(curve: Curve3D, distance: float, total_length: float) -> Vector3:
	# SUMMARY: Approximate a curve tangent using a small distance delta.
	# STEPS:
	# - Step 1: Clamp sample positions around the distance.
	# - Step 2: Sample positions and compute the direction vector.
	if curve == null:
		return Vector3.FORWARD
	var step: float = 0.05
	# Step 1: Build a symmetric sample window.
	var before: float = clamp(distance - step, 0.0, total_length)
	var after: float = clamp(distance + step, 0.0, total_length)
	if abs(after - before) < 0.0001:
		after = min(before + step, total_length)
		before = max(before - step, 0.0)
	# Step 2: Compute tangent from sampled positions.
	var p0: Vector3 = curve.sample_baked(before)
	var p1: Vector3 = curve.sample_baked(after)
	var dir: Vector3 = p1 - p0
	return dir

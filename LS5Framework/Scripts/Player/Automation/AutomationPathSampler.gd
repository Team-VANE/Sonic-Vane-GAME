@tool
extends RefCounted
class_name AutomationPathSampler

var length: float = 0.0
var closed: bool = false
var revision: int = 0
var last_segment_tests: int = 0
var validation_message: String = ""
## Path supplying geometry and its world transform.
var _path_ref: WeakRef
var _curve: Curve3D
var _transform: Transform3D = Transform3D.IDENTITY
var _dirty: bool = true
var _rebuilding: bool = false
var _points: PackedVector3Array = []
var _distances: PackedFloat64Array = []
var _local_distances: PackedFloat64Array = []
var _frames: Array[Quaternion] = []
var _search_blocks: Array[AABB] = []
const SEARCH_BLOCK_SIZE: int = 32


func configure(path: Path3D) -> void:
	var previous: Path3D = _path_ref.get_ref() as Path3D if _path_ref else null
	if previous == path:
		return
	dispose()
	_path_ref = weakref(path) if path else null
	_dirty = true


func dispose() -> void:
	if _curve and _curve.changed.is_connected(invalidate):
		_curve.changed.disconnect(invalidate)
	_curve = null
	_path_ref = null
	_points.clear()
	_distances.clear()
	_frames.clear()
	_search_blocks.clear()
	_local_distances.clear()
	length = 0.0
	_dirty = true


func invalidate() -> void:
	_dirty = true


func refresh() -> bool:
	if _rebuilding:
		return false
	var path: Path3D = _path_ref.get_ref() as Path3D if _path_ref else null
	if not is_instance_valid(path) or not path.is_inside_tree():
		validation_message = "A live Path3D is required."
		return false
	if _curve != path.curve:
		if _curve and _curve.changed.is_connected(invalidate):
			_curve.changed.disconnect(invalidate)
		_curve = path.curve
		if _curve:
			_curve.changed.connect(invalidate)
		_dirty = true
	if _transform != path.global_transform:
		_transform = path.global_transform
		_dirty = true
	if _dirty:
		_rebuilding = true
		_rebuild()
		_rebuilding = false
	return not _points.is_empty()


func _rebuild() -> void:
	_dirty = false
	revision += 1
	_points.clear()
	_distances.clear()
	_frames.clear()
	_search_blocks.clear()
	_local_distances.clear()
	length = 0.0
	validation_message = ""
	closed = _curve.closed if _curve else false
	if not _curve or _curve.point_count < 2:
		validation_message = "The route requires at least two curve points."
		return
	if not _transform.origin.is_finite() or not _transform.basis.is_finite() or _transform.basis.determinant() <= 0.000001:
		validation_message = "Route transforms must be finite, nonsingular, and nonmirrored."
		return
	var baked: PackedVector3Array = _curve.get_baked_points()
	var local_distance: float = 0.0
	for index: int in baked.size():
		if index:
			local_distance += baked[index - 1].distance_to(baked[index])
		var point: Vector3 = _transform * baked[index]
		if not point.is_finite():
			validation_message = "The curve contains nonfinite points."
			_points.clear()
			return
		if not _points.is_empty() and point.distance_squared_to(_points[-1]) < 0.00000001:
			continue
		if not _points.is_empty():
			length += _points[-1].distance_to(point)
		_points.append(point)
		_distances.append(length)
		_local_distances.append(local_distance)
	if _points.size() < 2 or length < 0.0001:
		_points.clear()
		validation_message = "The curve requires nonzero length."
		return
	var tangents: PackedVector3Array = []
	var ups: PackedVector3Array = []
	var previous_tangent: Vector3 = (_points[1] - _points[0]).normalized()
	var previous_up: Vector3 = _safe_up(previous_tangent, _transform.basis.y)
	var tilts: PackedFloat32Array = _curve.get_baked_tilts()
	var baked_length: float = _curve.get_baked_length()
	for index: int in _points.size():
		var before: int = maxi(index - 1, 0)
		var after: int = mini(index + 1, _points.size() - 1)
		if closed and (index == 0 or index == _points.size() - 1):
			before = _points.size() - 2
			after = 1
		var tangent: Vector3 = (_points[after] - _points[before]).normalized()
		if tangent.length_squared() < 0.0001:
			tangent = previous_tangent
		var transported: Vector3 = previous_up
		var dot_value: float = clampf(previous_tangent.dot(tangent), -1.0, 1.0)
		if dot_value < -0.9999:
			transported = transported.rotated(_safe_up(previous_tangent, previous_up), PI)
		elif dot_value < 0.999999:
			transported = Quaternion(previous_tangent, tangent) * previous_up
		var up_value: Vector3 = _safe_up(tangent, transported)
		if _curve.up_vector_enabled:
			var local_up: Vector3 = _curve.sample_baked_up_vector(minf(_local_distances[index], baked_length), true)
			up_value = _safe_up(tangent, _transform.basis * local_up)
		elif not tilts.is_empty():
			var tilt_index: int = mini(int(_local_distances[index] / maxf(_curve.bake_interval, 0.001)), tilts.size() - 1)
			up_value = up_value.rotated(tangent, tilts[tilt_index])
		tangents.append(tangent)
		ups.append(up_value)
		previous_tangent = tangent
		previous_up = _safe_up(tangent, transported)
	if closed:
		var seam_angle: float = ups[-1].signed_angle_to(ups[0], tangents[0])
		for index: int in ups.size():
			ups[index] = ups[index].rotated(tangents[index], seam_angle * _distances[index] / length)
	for index: int in _points.size():
		var side: Vector3 = tangents[index].cross(ups[index]).normalized()
		var corrected_up: Vector3 = side.cross(tangents[index]).normalized()
		_frames.append(Basis(side, corrected_up, -tangents[index]).get_rotation_quaternion())

	for first: int in range(0, _points.size() - 1, SEARCH_BLOCK_SIZE):
		var bounds: AABB = AABB(_points[first], Vector3.ZERO)
		for index: int in range(first + 1, mini(first + SEARCH_BLOCK_SIZE + 1, _points.size())):
			bounds = bounds.expand(_points[index])
		_search_blocks.append(bounds)


func _safe_up(tangent: Vector3, preferred: Vector3) -> Vector3:
	var up_value: Vector3 = preferred.slide(tangent)
	if up_value.length_squared() < 0.000001:
		up_value = (Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT).slide(tangent)
	return up_value.normalized()


func wrap_distance(value: float) -> float:
	return fposmod(value, length) if closed and length > 0.0 else clampf(value, 0.0, length)


func distance_delta(from: float, to: float) -> float:
	var difference: float = to - from
	return wrapf(difference, -length * 0.5, length * 0.5) if closed and length > 0.0 else difference


func _segment_at(distance_value: float) -> int:
	var low: int = 0
	var high: int = _distances.size() - 1
	while low + 1 < high:
		var middle: int = (low + high) >> 1
		if _distances[middle] <= distance_value:
			low = middle
		else:
			high = middle
	return mini(low, _points.size() - 2)


func sample(distance_value: float) -> AutomationSample:
	var result: AutomationSample = AutomationSample.new()
	if not refresh():
		return result
	var offset: float = wrap_distance(distance_value)
	var index: int = _segment_at(offset)
	var fraction: float = clampf((offset - _distances[index]) / (_distances[index + 1] - _distances[index]), 0.0, 1.0)
	var frame: Basis = Basis(_frames[index].slerp(_frames[index + 1], fraction))
	result.valid = true
	result.revision = revision
	result.segment = index
	result.distance = offset
	result.position = _points[index].lerp(_points[index + 1], fraction)
	result.tangent = -frame.z
	result.normal = frame.x
	result.up = frame.y
	return result


func closest(position: Vector3, preferred: float = -1.0, window: float = 6.0, predicted: float = -1.0,
		recovery_distance: float = 20.0, heading: Vector3 = Vector3.ZERO,
		projection_normal: Vector3 = Vector3.ZERO, projection_depth: float = 4.0) -> AutomationSample:
	last_segment_tests = 0
	if not refresh() or not position.is_finite():
		return AutomationSample.new()
	var anchor: float = predicted if predicted >= 0.0 else preferred
	if preferred >= 0.0 and window > 0.0 and absf(distance_delta(wrap_distance(preferred), wrap_distance(anchor))) > window:
		anchor = preferred
	var local: AutomationSample = AutomationSample.new()
	if preferred >= 0.0 and window > 0.0:
		var center: float = wrap_distance(preferred)
		local = _search(position, maxf(center - window, 0.0), minf(center + window, length), anchor, heading, projection_normal, projection_depth)
		if closed and center - window < 0.0:
			local = _better(local, _search(position, maxf(length + center - window, 0.0), length, anchor, heading, projection_normal, projection_depth), anchor, heading)
		if closed and center + window > length:
			local = _better(local, _search(position, 0.0, minf(center + window - length, length), anchor, heading, projection_normal, projection_depth), anchor, heading)
		if local.valid and (recovery_distance <= 0.0 or local.spatial_error <= recovery_distance):
			return local
	var global: AutomationSample = _search(position, 0.0, length, anchor, heading, projection_normal, projection_depth)
	global.recovered = preferred >= 0.0
	return global


func _better(first: AutomationSample, second: AutomationSample, anchor: float, heading: Vector3) -> AutomationSample:
	if not first.valid:
		return second
	if not second.valid:
		return first
	var difference: float = second.spatial_error - first.spatial_error
	if absf(difference) > 0.0001:
		return second if difference < 0.0 else first
	if anchor >= 0.0:
		return second if absf(distance_delta(wrap_distance(anchor), second.distance)) < absf(distance_delta(wrap_distance(anchor), first.distance)) else first
	return second if absf(second.tangent.dot(heading)) > absf(first.tangent.dot(heading)) else first


func _search(position: Vector3, start: float, finish: float, anchor: float, heading: Vector3,
		projection_normal: Vector3, projection_depth: float) -> AutomationSample:
	var best: AutomationSample = AutomationSample.new()
	var normal: Vector3 = projection_normal.normalized()
	var begin_index: int = _segment_at(start)
	var end_index: int = _segment_at(finish)
	var best_offset: float = -1.0
	var best_error: float = INF
	var best_preference: float = INF
	var best_score: float = INF
	var first_block: int = begin_index / SEARCH_BLOCK_SIZE
	var last_block: int = end_index / SEARCH_BLOCK_SIZE
	var seed: int = first_block
	var nearest_bound: float = INF
	for block: int in range(first_block, last_block + 1):
		var bound_distance: float = _bound_distance_squared(_search_blocks[block], position, normal)
		if bound_distance < nearest_bound:
			nearest_bound = bound_distance
			seed = block
	for iteration: int in range(last_block - first_block + 2):
		var block: int = seed if not iteration else first_block + iteration - 1
		if iteration and block == seed:
			continue
		if _bound_distance_squared(_search_blocks[block], position, normal) > best_score + 0.000001:
			continue
		for index: int in range(maxi(begin_index, block * SEARCH_BLOCK_SIZE), mini(end_index + 1, (block + 1) * SEARCH_BLOCK_SIZE)):
			last_segment_tests += 1
			var segment_length: float = _distances[index + 1] - _distances[index]
			var segment: Vector3 = _points[index + 1] - _points[index]
			var relative: Vector3 = position - _points[index]
			var measured_segment: Vector3 = segment.slide(normal) if normal else segment
			var measured_relative: Vector3 = relative.slide(normal) if normal else relative
			var fraction: float = measured_relative.dot(measured_segment) / maxf(measured_segment.length_squared(), 0.0000001)
			fraction = clampf(fraction, maxf((start - _distances[index]) / segment_length, 0.0), minf((finish - _distances[index]) / segment_length, 1.0))
			var point: Vector3 = _points[index] + segment * fraction
			var error_vector: Vector3 = position - point
			if normal and absf(error_vector.dot(normal)) > projection_depth:
				continue
			var error: float = (error_vector.slide(normal) if normal else error_vector).length()
			var offset: float = _distances[index] + segment_length * fraction
			var preference: float = absf(distance_delta(wrap_distance(anchor), offset)) if anchor >= 0.0 else -absf(segment.normalized().dot(heading))
			var continuity_cost: float = pow(preference * 0.05, 2.0) if anchor >= 0.0 else 0.0
			var heading_cost: float = (1.0 - absf(segment.normalized().dot(heading))) * 0.01 if heading else 0.0
			var score: float = error * error + continuity_cost + heading_cost
			if score < best_score - 0.000001 or (absf(score - best_score) <= 0.000001 and preference < best_preference):
				best_error = error
				best_score = score
				best_offset = offset
				best_preference = preference
	if best_offset >= 0.0:
		best = sample(best_offset)
		best.spatial_error = best_error
	return best


func smooth_sample(value: AutomationSample, lookahead: float = 0.5) -> AutomationSample:
	if not value or not value.valid or not refresh():
		return value
	var index: int = _segment_at(wrap_distance(value.distance))
	var fraction: float = clampf((value.distance - _distances[index]) / (_distances[index + 1] - _distances[index]), 0.0, 1.0)
	var local_offset: float = lerpf(_local_distances[index], _local_distances[index + 1], fraction)
	var result: AutomationSample = sample(value.distance)
	result.position = _transform * _curve.sample_baked(local_offset, true)
	var step: float = maxf(lookahead, _curve.bake_interval)
	var before: float = local_offset - step
	var after: float = local_offset + step
	var local_length: float = _curve.get_baked_length()
	before = fposmod(before, local_length) if closed else maxf(before, 0.0)
	after = fposmod(after, local_length) if closed else minf(after, local_length)
	var tangent: Vector3 = _transform.basis * (_curve.sample_baked(after, true) - _curve.sample_baked(before, true))
	if tangent:
		result.tangent = tangent.normalized()
		result.normal = result.normal.slide(result.tangent).normalized()
		result.up = result.normal.cross(result.tangent).normalized()
	result.spatial_error = value.spatial_error
	return result


func _bound_distance_squared(bounds: AABB, point: Vector3, normal: Vector3) -> float:
	if normal:
		var separation: float = (point - bounds.get_center()).slide(normal).length()
		var lower_bound: float = maxf(separation - bounds.size.length() * 0.5, 0.0)
		return lower_bound * lower_bound
	var nearest: Vector3 = point.clamp(bounds.position, bounds.end)
	return point.distance_squared_to(nearest)

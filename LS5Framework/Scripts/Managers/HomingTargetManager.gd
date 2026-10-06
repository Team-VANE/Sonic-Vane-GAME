extends Node

@export var cell_size: float = 64.0
## Cell size used for the lightspeed dash ring spatial grid. Rings are static so a smaller cell is fine.
@export var ring_cell_size: float = 32.0
## Cell size used for nearby rail snap queries.
@export var rail_cell_size: float = 32.0

var _targets: Array[Node3D] = []
var _target_cells: Dictionary = {}
var _cells: Dictionary = {}

var _attack_magnetism_targets: Array[Node3D] = []
var _attack_magnetism_target_cells: Dictionary = {}
var _attack_magnetism_cells: Dictionary = {}

# ---------------------------------------------------------------------------
# Lightspeed dash ring registry
# ---------------------------------------------------------------------------
var _rings: Array[Node3D] = []
var _ring_cells: Dictionary = {}
var _ring_grid: Dictionary = {}

var _rails: Array[Node3D] = []
var _rail_cells: Dictionary = {}
var _rail_grid: Dictionary = {}
var _rail_bounds: Dictionary = {}

func register(target: Node) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		return
	if not (target is Node3D):
		return
	if target in _targets:
		return
	var node: Node3D = target as Node3D
	_targets.append(node)
	var cells: Array[Vector3i] = _get_target_cells(node)
	_target_cells[node.get_instance_id()] = cells
	for cell in cells:
		_add_to_cell(node, cell)

func unregister(target: Node) -> void:
	if target == null:
		return
	if target in _targets:
		_targets.erase(target)
	var id: int = target.get_instance_id()
	if _target_cells.has(id):
		var cells: Array = _target_cells[id]
		for cell in cells:
			if cell is Vector3i:
				_remove_from_cell(target, cell)
		_target_cells.erase(id)

func get_targets() -> Array:
	var out: Array = []
	for t in _targets:
		if t != null and is_instance_valid(t):
			out.append(t)
	return out

func get_targets_in_range(origin: Vector3, max_range: float) -> Array:
	var out: Array = []
	if max_range <= 0.0:
		return out
	var maxr2: float = max_range * max_range
	var radius_cells: int = int(ceil(max_range / max(cell_size, 1.0)))
	var origin_cell: Vector3i = _get_cell_key(origin)
	var seen: Dictionary = {}
	for x in range(origin_cell.x - radius_cells, origin_cell.x + radius_cells + 1):
		for y in range(origin_cell.y - radius_cells, origin_cell.y + radius_cells + 1):
			for z in range(origin_cell.z - radius_cells, origin_cell.z + radius_cells + 1):
				var cell := Vector3i(x, y, z)
				if not _cells.has(cell):
					continue
				for t in _cells[cell]:
					if t == null or not is_instance_valid(t):
						continue
					var id: int = t.get_instance_id()
					if seen.has(id):
						continue
					seen[id] = true
					var target_position: Vector3 = _get_target_query_position(t, origin)
					var to: Vector3 = target_position - origin
					if to.length_squared() <= maxr2:
						out.append(t)
	return out

func update_target(target: Node) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		return
	if not (target is Node3D):
		return
	var node: Node3D = target as Node3D
	var id: int = node.get_instance_id()
	if not _target_cells.has(id):
		register(node)
		return
	var old_cells: Array = _target_cells[id]
	var new_cells: Array[Vector3i] = _get_target_cells(node)
	if _cells_match(old_cells, new_cells):
		return
	for cell in old_cells:
		if cell is Vector3i:
			_remove_from_cell(node, cell)
	_target_cells[id] = new_cells
	for cell in new_cells:
		_add_to_cell(node, cell)

func _get_cell_key(position: Vector3) -> Vector3i:
	var size: float = max(cell_size, 1.0)
	return Vector3i(floori(position.x / size), floori(position.y / size), floori(position.z / size))


func _get_target_cells(target: Node3D) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var positions: Array = []
	if target.has_method("get_homing_manager_positions"):
		positions = target.call("get_homing_manager_positions", max(cell_size, 1.0))
	if positions.is_empty():
		positions.append(target.global_position)
	for position in positions:
		if not (position is Vector3):
			continue
		var cell: Vector3i = _get_cell_key(position)
		if not (cell in cells):
			cells.append(cell)
	if cells.is_empty():
		cells.append(_get_cell_key(target.global_position))
	return cells


func _get_target_query_position(target: Node3D, origin: Vector3) -> Vector3:
	if target.has_method("get_homing_target_position"):
		var position: Variant = target.call("get_homing_target_position", origin)
		if position is Vector3:
			return position
	return target.global_position


func _cells_match(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for cell in a:
		if not (cell in b):
			return false
	return true

func _add_to_cell(target: Node3D, cell: Vector3i) -> void:
	if not _cells.has(cell):
		_cells[cell] = []
	var bucket: Array = _cells[cell]
	if not (target in bucket):
		bucket.append(target)

func _remove_from_cell(target: Node, cell: Vector3i) -> void:
	if not _cells.has(cell):
		return
	var bucket: Array = _cells[cell]
	if target in bucket:
		bucket.erase(target)
	if bucket.is_empty():
		_cells.erase(cell)


func register_attack_magnetism_target(target: Node) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		return
	if not (target is Node3D):
		return
	if target in _attack_magnetism_targets:
		return
	var node: Node3D = target as Node3D
	_attack_magnetism_targets.append(node)
	var cells: Array[Vector3i] = _get_target_cells(node)
	_attack_magnetism_target_cells[node.get_instance_id()] = cells
	for cell in cells:
		_attack_magnetism_add_to_cell(node, cell)


func unregister_attack_magnetism_target(target: Node) -> void:
	if target == null:
		return
	if target in _attack_magnetism_targets:
		_attack_magnetism_targets.erase(target)
	var id: int = target.get_instance_id()
	if _attack_magnetism_target_cells.has(id):
		var cells: Array = _attack_magnetism_target_cells[id]
		for cell in cells:
			if cell is Vector3i:
				_attack_magnetism_remove_from_cell(target, cell)
		_attack_magnetism_target_cells.erase(id)


func update_attack_magnetism_target(target: Node) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		return
	if not (target is Node3D):
		return
	var node: Node3D = target as Node3D
	var id: int = node.get_instance_id()
	if not _attack_magnetism_target_cells.has(id):
		register_attack_magnetism_target(node)
		return
	var old_cells: Array = _attack_magnetism_target_cells[id]
	var new_cells: Array[Vector3i] = _get_target_cells(node)
	if _cells_match(old_cells, new_cells):
		return
	for cell in old_cells:
		if cell is Vector3i:
			_attack_magnetism_remove_from_cell(node, cell)
	_attack_magnetism_target_cells[id] = new_cells
	for cell in new_cells:
		_attack_magnetism_add_to_cell(node, cell)


func get_attack_magnetism_targets_in_range(origin: Vector3, max_range: float) -> Array:
	var out: Array = []
	if max_range <= 0.0:
		return out
	var maxr2: float = max_range * max_range
	var radius_cells: int = int(ceil(max_range / max(cell_size, 1.0)))
	var origin_cell: Vector3i = _get_cell_key(origin)
	var seen: Dictionary = {}
	for x in range(origin_cell.x - radius_cells, origin_cell.x + radius_cells + 1):
		for y in range(origin_cell.y - radius_cells, origin_cell.y + radius_cells + 1):
			for z in range(origin_cell.z - radius_cells, origin_cell.z + radius_cells + 1):
				var cell := Vector3i(x, y, z)
				if not _attack_magnetism_cells.has(cell):
					continue
				for t in _attack_magnetism_cells[cell]:
					if t == null or not is_instance_valid(t):
						continue
					var id: int = t.get_instance_id()
					if seen.has(id):
						continue
					seen[id] = true
					var target_position: Vector3 = _get_attack_magnetism_query_position(t, origin)
					var to: Vector3 = target_position - origin
					if to.length_squared() <= maxr2:
						out.append(t)
	return out


func _get_attack_magnetism_query_position(target: Node3D, origin: Vector3) -> Vector3:
	if target.has_method("get_attack_magnetism_position"):
		var position: Variant = target.call("get_attack_magnetism_position", origin)
		if position is Vector3:
			return position
	return _get_target_query_position(target, origin)


func _attack_magnetism_add_to_cell(target: Node3D, cell: Vector3i) -> void:
	if not _attack_magnetism_cells.has(cell):
		_attack_magnetism_cells[cell] = []
	var bucket: Array = _attack_magnetism_cells[cell]
	if not (target in bucket):
		bucket.append(target)


func _attack_magnetism_remove_from_cell(target: Node, cell: Vector3i) -> void:
	if not _attack_magnetism_cells.has(cell):
		return
	var bucket: Array = _attack_magnetism_cells[cell]
	if target in bucket:
		bucket.erase(target)
	if bucket.is_empty():
		_attack_magnetism_cells.erase(cell)


# ---------------------------------------------------------------------------
# Ring registration (lightspeed dash)
# ---------------------------------------------------------------------------
func register_ring(ring: Node) -> void:
	if ring == null:
		return
	if not is_instance_valid(ring):
		return
	if not (ring is Node3D):
		return
	if ring in _rings:
		return
	var node: Node3D = ring as Node3D
	_rings.append(node)
	var cell: Vector3i = _get_ring_cell_key(node.global_position)
	_ring_cells[node.get_instance_id()] = cell
	_ring_add_to_cell(node, cell)


func unregister_ring(ring: Node) -> void:
	if ring == null:
		return
	if ring in _rings:
		_rings.erase(ring)
	var id: int = ring.get_instance_id()
	if _ring_cells.has(id):
		var cell: Vector3i = _ring_cells[id]
		_ring_remove_from_cell(ring, cell)
		_ring_cells.erase(id)


func get_rings_in_range(origin: Vector3, max_range: float) -> Array:
	var out: Array = []
	if max_range <= 0.0:
		return out
	var maxr2: float = max_range * max_range
	var radius_cells: int = int(ceil(max_range / max(ring_cell_size, 1.0)))
	var origin_cell: Vector3i = _get_ring_cell_key(origin)
	for x in range(origin_cell.x - radius_cells, origin_cell.x + radius_cells + 1):
		for y in range(origin_cell.y - radius_cells, origin_cell.y + radius_cells + 1):
			for z in range(origin_cell.z - radius_cells, origin_cell.z + radius_cells + 1):
				var cell := Vector3i(x, y, z)
				if not _ring_grid.has(cell):
					continue
				for r in _ring_grid[cell]:
					if r == null or not is_instance_valid(r):
						continue
					var to: Vector3 = r.global_position - origin
					if to.length_squared() <= maxr2:
						out.append(r)
	return out


func _get_ring_cell_key(position: Vector3) -> Vector3i:
	var size: float = max(ring_cell_size, 1.0)
	return Vector3i(floori(position.x / size), floori(position.y / size), floori(position.z / size))


func _ring_add_to_cell(ring: Node3D, cell: Vector3i) -> void:
	if not _ring_grid.has(cell):
		_ring_grid[cell] = []
	var bucket: Array = _ring_grid[cell]
	if not (ring in bucket):
		bucket.append(ring)


func _ring_remove_from_cell(ring: Node, cell: Vector3i) -> void:
	if not _ring_grid.has(cell):
		return
	var bucket: Array = _ring_grid[cell]
	if ring in bucket:
		bucket.erase(ring)
	if bucket.is_empty():
		_ring_grid.erase(cell)


# ---------------------------------------------------------------------------
# Rail registration
# ---------------------------------------------------------------------------
func register_rail(rail: Node) -> void:
	if rail == null or not is_instance_valid(rail) or not (rail is Node3D):
		return
	if rail in _rails:
		update_rail(rail)
		return
	var node: Node3D = rail as Node3D
	_rails.append(node)
	_store_rail_spatial_data(node)


func unregister_rail(rail: Node) -> void:
	if rail == null:
		return
	if rail in _rails:
		_rails.erase(rail)
	var rail_id: int = rail.get_instance_id()
	_remove_rail_from_cells(rail, rail_id)
	_rail_bounds.erase(rail_id)


func update_rail(rail: Node) -> void:
	if rail == null or not is_instance_valid(rail) or not (rail is Node3D):
		return
	var node: Node3D = rail as Node3D
	if not (node in _rails):
		_rails.append(node)
	var rail_id: int = node.get_instance_id()
	_remove_rail_from_cells(node, rail_id)
	_store_rail_spatial_data(node)


func get_rails_in_range(origin: Vector3, max_range: float) -> Array:
	var rails: Array = []
	if max_range <= 0.0:
		return rails
	var size: float = max(rail_cell_size, 1.0)
	var radius_cells: int = int(ceil(max_range / size))
	var origin_cell: Vector3i = _get_rail_cell_key(origin)
	var max_range_squared: float = max_range * max_range
	var seen: Dictionary = {}
	for x: int in range(origin_cell.x - radius_cells, origin_cell.x + radius_cells + 1):
		for y: int in range(origin_cell.y - radius_cells, origin_cell.y + radius_cells + 1):
			for z: int in range(origin_cell.z - radius_cells, origin_cell.z + radius_cells + 1):
				var cell: Vector3i = Vector3i(x, y, z)
				if not _rail_grid.has(cell):
					continue
				for rail_value: Variant in _rail_grid[cell]:
					if not (rail_value is Node3D):
						continue
					var rail: Node3D = rail_value as Node3D
					if not is_instance_valid(rail):
						continue
					var rail_id: int = rail.get_instance_id()
					if seen.has(rail_id):
						continue
					seen[rail_id] = true
					var bounds_value: Variant = _rail_bounds.get(rail_id)
					if bounds_value is AABB:
						var closest: Vector3 = _get_closest_point_on_aabb(bounds_value as AABB, origin)
						if closest.distance_squared_to(origin) > max_range_squared:
							continue
					rails.append(rail)
	return rails


func _store_rail_spatial_data(rail: Node3D) -> void:
	var bounds: AABB = AABB(rail.global_position, Vector3.ZERO)
	if rail.has_method("get_path_world_aabb"):
		var bounds_value: Variant = rail.call("get_path_world_aabb")
		if bounds_value is AABB:
			bounds = bounds_value as AABB
	var rail_id: int = rail.get_instance_id()
	_rail_bounds[rail_id] = bounds
	var cells: Array[Vector3i] = _get_rail_cells_for_node(rail, bounds)
	_rail_cells[rail_id] = cells
	for cell: Vector3i in cells:
		if not _rail_grid.has(cell):
			_rail_grid[cell] = []
		var bucket: Array = _rail_grid[cell]
		if not (rail in bucket):
			bucket.append(rail)


func _remove_rail_from_cells(rail: Node, rail_id: int) -> void:
	if not _rail_cells.has(rail_id):
		return
	var cells: Array = _rail_cells[rail_id]
	for cell_value: Variant in cells:
		if not (cell_value is Vector3i) or not _rail_grid.has(cell_value):
			continue
		var bucket: Array = _rail_grid[cell_value]
		bucket.erase(rail)
		if bucket.is_empty():
			_rail_grid.erase(cell_value)
	_rail_cells.erase(rail_id)


func _get_rail_cells_for_node(rail: Node3D, bounds: AABB) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var positions: Array = []
	if rail.has_method("get_homing_manager_positions"):
		positions = rail.call("get_homing_manager_positions", max(rail_cell_size * 0.5, 1.0))
	for position_value: Variant in positions:
		if not (position_value is Vector3):
			continue
		var cell: Vector3i = _get_rail_cell_key(position_value as Vector3)
		if not (cell in cells):
			cells.append(cell)
	if cells.is_empty():
		cells.append(_get_rail_cell_key(bounds.get_center()))
	return cells


func _get_rail_cell_key(position: Vector3) -> Vector3i:
	var size: float = max(rail_cell_size, 1.0)
	return Vector3i(floori(position.x / size), floori(position.y / size), floori(position.z / size))


func _get_closest_point_on_aabb(bounds: AABB, point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, bounds.position.x, bounds.end.x),
		clampf(point.y, bounds.position.y, bounds.end.y),
		clampf(point.z, bounds.position.z, bounds.end.z)
	)

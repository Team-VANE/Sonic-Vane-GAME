extends Control
class_name PlayerLocator

const TRACKING_ACTION: StringName = &"player_tracking"
const FULL_TRACKING_RELEASE_DURATION: float = 2.0
const MARKER_SIZE: Vector2 = Vector2(210.0, 58.0)
const DIRECTION_EPSILON: float = 0.001
const TRACKING_MODE_FULL: int = 0
const TRACKING_MODE_MINIMAL: int = 1
const TRACKING_MODE_OFF: int = 2
const LEADING_GHOST_GROUP: StringName = &"LeadingRaceGhost"

## Screen clearance used by off-screen player markers.
@export var edge_margin: Vector2 = Vector2(72.0, 64.0)
## Height above a remote player's origin used for screen projection.
@export var player_anchor_height: float = 2.4
## Relative height required before an up or down hint is displayed.
@export var vertical_hint_threshold: float = 8.0
## Distance where normal tracking begins fading toward its minimum opacity.
@export var fade_start_distance: float = 45.0
## Distance where normal tracking reaches its minimum opacity.
@export var fade_end_distance: float = 220.0
## Lowest opacity used by normal tracking.
@export_range(0.0, 1.0, 0.01) var minimum_opacity: float = 0.48
## Extra inset used to decide whether a projected player is safely on-screen.
@export var on_screen_inset: Vector2 = Vector2(36.0, 36.0)

var _markers: Dictionary = {}
var _network_session: Node = null
var _full_tracking_remaining: float = 0.0
var _tracking_was_pressed: bool = false
var _ghost_marker: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_update_tracking_override(delta)
	_update_markers()
	_update_ghost_marker()


func _update_ghost_marker() -> void:
	if not is_visible_in_tree() or not SettingsManager.hud_visible:
		_hide_ghost_marker()
		return
	var ghost: Node3D = get_tree().get_first_node_in_group(LEADING_GHOST_GROUP) as Node3D
	if ghost == null or ghost.is_queued_for_deletion() or not ghost.is_visible_in_tree():
		_hide_ghost_marker()
		return
	if not ghost.has_method("is_locator_visible") or not ghost.call("is_locator_visible"):
		_hide_ghost_marker()
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var local_player: Node3D = _get_ghost_reference_player()
	if camera == null or local_player == null:
		_hide_ghost_marker()
		return
	if _ghost_marker.is_empty():
		_ghost_marker = _create_marker("Ghost")
	_update_marker(_ghost_marker, {"name": "Ghost", "color": Color.WHITE}, local_player, ghost, camera, TRACKING_MODE_FULL)


func _get_ghost_reference_player() -> Node3D:
	var session: Node = _get_network_session()
	if session != null and session.has_method("get_local_player"):
		var local_player: Node3D = session.call("get_local_player") as Node3D
		if is_instance_valid(local_player) and local_player.is_inside_tree():
			return local_player
	for player: Node in get_tree().get_nodes_in_group("Player"):
		if not (player is Node3D) or player.is_queued_for_deletion() or player.get_meta(&"is_buddy", false):
			continue
		if player.has_method("_network_is_local_authority") and not player.call("_network_is_local_authority"):
			continue
		return player as Node3D
	return null


func _hide_ghost_marker() -> void:
	var root: Control = _ghost_marker.get("root") as Control
	if root != null:
		root.visible = false


func _update_tracking_override(delta: float) -> void:
	var tree: SceneTree = get_tree()
	if tree != null and tree.has_meta(&"chat_input_active") and bool(tree.get_meta(&"chat_input_active")):
		_tracking_was_pressed = false
		_full_tracking_remaining = max(_full_tracking_remaining - max(delta, 0.0), 0.0)
		return
	var tracking_pressed: bool = InputMap.has_action(TRACKING_ACTION) and Input.is_action_pressed(TRACKING_ACTION)
	if tracking_pressed:
		_full_tracking_remaining = FULL_TRACKING_RELEASE_DURATION
	elif _tracking_was_pressed:
		_full_tracking_remaining = FULL_TRACKING_RELEASE_DURATION
	else:
		_full_tracking_remaining = max(_full_tracking_remaining - max(delta, 0.0), 0.0)
	_tracking_was_pressed = tracking_pressed


func _update_markers() -> void:
	var session: Node = _get_network_session()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if session == null or camera == null or not _has_remote_player_context(session):
		_hide_all_markers()
		return
	var tracking_mode: int = TRACKING_MODE_MINIMAL
	if session.has_method("get_player_tracking_mode"):
		tracking_mode = clampi(int(session.call("get_player_tracking_mode")), TRACKING_MODE_FULL, TRACKING_MODE_OFF)
	if tracking_mode == TRACKING_MODE_OFF and not _is_full_tracking_active():
		_hide_all_markers()
		return

	var local_id: int = multiplayer.get_unique_id() if _is_online() else 1
	if session.has_method("get_local_peer_id"):
		local_id = int(session.call("get_local_peer_id"))
	var local_player: Node3D = session.call("get_local_player") as Node3D
	if local_player == null or not is_instance_valid(local_player):
		_hide_all_markers()
		return

	var active_ids: Dictionary = {}
	var peer_info_list: Array = session.call("get_peer_info_list")
	for info_value: Variant in peer_info_list:
		if not (info_value is Dictionary):
			continue
		var info: Dictionary = info_value
		var peer_id: int = int(info.get("peer_id", 0))
		if peer_id <= 0 or peer_id == local_id:
			continue
		var remote_player: Node3D = session.call("get_player_node", peer_id) as Node3D
		if remote_player == null or not is_instance_valid(remote_player) or not remote_player.is_visible_in_tree():
			continue
		active_ids[peer_id] = true
		var marker: Dictionary = _get_or_create_marker(peer_id)
		_update_marker(marker, info, local_player, remote_player, camera, tracking_mode)

	for peer_id_value: Variant in _markers.keys():
		var peer_id: int = int(peer_id_value)
		if active_ids.has(peer_id):
			continue
		var marker: Dictionary = _markers[peer_id]
		var root: Control = marker.get("root", null) as Control
		if root != null:
			root.visible = false


func _get_or_create_marker(peer_id: int) -> Dictionary:
	if _markers.has(peer_id):
		return _markers[peer_id]
	var marker: Dictionary = _create_marker("Player_%d" % peer_id)
	_markers[peer_id] = marker
	return marker


func _create_marker(marker_name: String) -> Dictionary:

	var root: Control = Control.new()
	root.name = marker_name
	root.custom_minimum_size = MARKER_SIZE
	root.size = MARKER_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var arrow: Node2D = Node2D.new()
	arrow.name = "Direction"
	arrow.position = Vector2(MARKER_SIZE.x * 0.5, 14.0)
	var pointer_points: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -17.0),
		Vector2(-10.0, 8.0),
		Vector2(-4.0, 6.0),
		Vector2(-4.0, 17.0),
		Vector2(4.0, 17.0),
		Vector2(4.0, 6.0),
		Vector2(10.0, 8.0),
	])
	var pointer_outline: Polygon2D = Polygon2D.new()
	pointer_outline.name = "Outline"
	pointer_outline.polygon = pointer_points
	pointer_outline.color = Color(0.0, 0.0, 0.0, 0.92)
	pointer_outline.scale = Vector2(1.28, 1.2)
	arrow.add_child(pointer_outline)
	var pointer_fill: Polygon2D = Polygon2D.new()
	pointer_fill.name = "Fill"
	pointer_fill.polygon = pointer_points
	pointer_fill.color = Color.WHITE
	pointer_fill.scale = Vector2(0.82, 0.82)
	arrow.add_child(pointer_fill)
	root.add_child(arrow)

	var label: Label = Label.new()
	label.name = "PlayerLabel"
	label.position = Vector2.ZERO
	label.size = Vector2(MARKER_SIZE.x, 26.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("outline_size", 7)
	root.add_child(label)

	var marker: Dictionary = {
		"root": root,
		"arrow": arrow,
		"label": label,
	}
	return marker


func _update_marker(
	marker: Dictionary,
	info: Dictionary,
	local_player: Node3D,
	remote_player: Node3D,
	camera: Camera3D,
	tracking_mode: int
	) -> void:
	var root: Control = marker.get("root", null) as Control
	var arrow: Node2D = marker.get("arrow", null) as Node2D
	var label: Label = marker.get("label", null) as Label
	if root == null or arrow == null or label == null:
		return

	var local_up: Vector3 = _get_player_up(local_player)
	var relative: Vector3 = remote_player.global_position - local_player.global_position
	var distance: float = relative.length()
	var anchor_position: Vector3 = remote_player.global_position + _get_player_up(remote_player) * player_anchor_height
	var screen_position: Vector2 = camera.unproject_position(anchor_position)
	var local_position: Vector2 = _screen_to_local(screen_position)
	var viewport_size: Vector2 = size
	var behind_camera: bool = camera.is_position_behind(anchor_position)
	var on_screen_rect: Rect2 = Rect2(on_screen_inset, viewport_size - on_screen_inset * 2.0)
	var on_screen: bool = not behind_camera and on_screen_rect.has_point(local_position)
	var direction: Vector2 = _get_screen_direction(camera, anchor_position, local_position, viewport_size, behind_camera)

	if on_screen:
		root.position = _clamp_marker_position(local_position + Vector2(0.0, -36.0), viewport_size)
		arrow.rotation = PI
		arrow.position.y = 38.0
		label.position.y = 0.0
	else:
		var edge_position: Vector2 = _get_edge_position(direction, viewport_size)
		root.position = edge_position - MARKER_SIZE * 0.5
		arrow.rotation = direction.angle() + PI * 0.5
		arrow.position.y = 14.0
		label.position.y = 28.0

	var vertical_distance: float = relative.dot(local_up)
	var vertical_hint: String = ""
	if vertical_distance >= vertical_hint_threshold:
		vertical_hint = "  △"
	elif vertical_distance <= -vertical_hint_threshold:
		vertical_hint = "  ▽"

	var display_name: String = String(info.get("name", "Player"))
	if display_name.is_empty():
		display_name = "Player"
	label.text = "%s  %dm%s" % [display_name, int(round(distance)), vertical_hint]

	var display_color: Color = Color(info.get("color", Color.WHITE))
	var full_tracking: bool = _is_full_tracking_active() or tracking_mode == TRACKING_MODE_FULL
	var opacity: float = 1.0 if full_tracking else _get_normal_opacity(distance, on_screen)
	var marker_color: Color = Color(display_color.r, display_color.g, display_color.b, opacity)
	arrow.modulate = marker_color
	label.modulate = marker_color
	root.visible = true


func _get_screen_direction(
	camera: Camera3D,
	world_position: Vector3,
	projected_position: Vector2,
	viewport_size: Vector2,
	behind_camera: bool
	) -> Vector2:
	var center: Vector2 = viewport_size * 0.5
	var direction: Vector2 = projected_position - center
	if behind_camera:
		var camera_position: Vector3 = camera.global_transform.affine_inverse() * world_position
		direction = Vector2(camera_position.x, -camera_position.y)
	if direction.length_squared() <= DIRECTION_EPSILON:
		direction = Vector2.UP
	return direction.normalized()


func _get_edge_position(direction: Vector2, viewport_size: Vector2) -> Vector2:
	var center: Vector2 = viewport_size * 0.5
	var half_extents: Vector2 = Vector2(
		max(center.x - edge_margin.x - MARKER_SIZE.x * 0.5, 1.0),
		max(center.y - edge_margin.y - MARKER_SIZE.y * 0.5, 1.0)
	)
	var scale_x: float = INF if abs(direction.x) <= DIRECTION_EPSILON else half_extents.x / abs(direction.x)
	var scale_y: float = INF if abs(direction.y) <= DIRECTION_EPSILON else half_extents.y / abs(direction.y)
	return center + direction * min(scale_x, scale_y)


func _clamp_marker_position(target_center: Vector2, viewport_size: Vector2) -> Vector2:
	var half_size: Vector2 = MARKER_SIZE * 0.5
	var center: Vector2 = Vector2(
		clamp(target_center.x, half_size.x, viewport_size.x - half_size.x),
		clamp(target_center.y, half_size.y, viewport_size.y - half_size.y)
	)
	return center - half_size


func _screen_to_local(screen_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_position


func _get_player_up(player: Node3D) -> Vector3:
	if player != null and player.has_method("get_up_vector"):
		var up_value: Variant = player.call("get_up_vector")
		if up_value is Vector3 and not (up_value as Vector3).is_zero_approx():
			return (up_value as Vector3).normalized()
	return Vector3.UP


func _get_normal_opacity(distance: float, on_screen: bool) -> float:
	var fade_range: float = max(fade_end_distance - fade_start_distance, 0.001)
	var distance_weight: float = clamp((distance - fade_start_distance) / fade_range, 0.0, 1.0)
	var opacity: float = lerp(0.88, minimum_opacity, distance_weight)
	if not on_screen:
		opacity = max(opacity, 0.68)
	return opacity


func _is_full_tracking_active() -> bool:
	return _tracking_was_pressed or _full_tracking_remaining > 0.0


func _get_network_session() -> Node:
	if _network_session != null and is_instance_valid(_network_session):
		return _network_session
	if get_tree() == null:
		return null
	var sessions: Array[Node] = get_tree().get_nodes_in_group("NetworkSession")
	if not sessions.is_empty():
		_network_session = sessions[0]
	return _network_session


func _is_online() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer()


func _has_remote_player_context(session: Node) -> bool:
	if _is_online():
		return true
	return session.has_method("has_debug_dummy_player") and bool(session.call("has_debug_dummy_player"))


func _hide_all_markers() -> void:
	for marker_value: Variant in _markers.values():
		if not (marker_value is Dictionary):
			continue
		var root: Control = (marker_value as Dictionary).get("root", null) as Control
		if root != null:
			root.visible = false

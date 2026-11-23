from math import cos, radians, sin, tan, tau
from itertools import combinations

import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Vector

from .automation_preview import curve_samples
from .checkpoint_preview import CORNER_SIGNS, EDGES
from .spring_preview import MARKER_FIELD_KEY, placement_marker


CAMERA_POINT = "camera_point_offset"
RELEASE_POINT = "camera_release_offset"
AIM_POINT = "camera_aim_target_offset"
INFLUENCE_POINT = "camera_influence_offset"
MARKER_FIELDS = (CAMERA_POINT, RELEASE_POINT, AIM_POINT, INFLUENCE_POINT)
GATE_ROLE = "sonic_vane_camera_gate"
PATH_ROLE = "sonic_vane_camera_path"
GATES = {
    "entry": ("Camera Entry Gate", (0.25, 0.78, 1.0, 1.0)),
    "exit": ("Camera Exit Gate", (1.0, 0.44, 0.26, 1.0)),
    "rearm": ("Camera Rearm Boundary", (0.69, 0.50, 1.0, 0.75)),
}
WORLD_UP = Vector((0, 0, 1))
PREVIEW_ASPECTS = {"16_9": 16 / 9, "21_9": 21 / 9, "32_9": 32 / 9}


def influence_error(placement):
    if not placement.camera_influence_enabled:
        return None
    if placement.camera_influence_zero <= placement.camera_influence_full:
        return "Zero Influence Radius must exceed Full Influence Radius."
    if not (placement.camera_influence_position or placement.camera_influence_orientation or placement.camera_influence_lens):
        return "Enable at least one camera influence channel."
    return None


def active_gates(placement):
    if placement.kind != "camera_constraint" or placement.camera_activation_mode != "entry_gate":
        return ()
    return (
        "entry",
        *(("exit",) if placement.camera_exit_gate_enabled else ()),
        *(("rearm",) if placement.camera_rearm_gate_enabled else ()),
    )


def gate_for(obj, role):
    return next((child for child in obj.children if child.get(GATE_ROLE) == role), None)


def path_for(obj):
    return next((child for child in obj.children if child.get(PATH_ROLE)), None)


def sync_path(placement):
    obj = placement.id_data
    if not obj.is_editable:
        return
    active = placement.kind == "camera_constraint" and placement.camera_override_position and placement.camera_position_mode == "path_camera"
    path = path_for(obj)
    if path:
        path.hide_viewport = not active
        return
    if not active or not obj.users_collection:
        return
    curve = bpy.data.curves.new("Camera Path", "CURVE")
    curve.dimensions = "3D"
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(2)
    for point, co in zip(spline.bezier_points, ((-12, -4, 0), (0, 0, 0), (12, -4, 0))):
        point.co = co
        point.handle_left_type = point.handle_right_type = "AUTO"
    path = bpy.data.objects.new("Camera Path", curve)
    path[PATH_ROLE] = True
    path.parent = obj
    camera = placement_marker(obj, CAMERA_POINT)
    path.location = camera.location if camera else placement.camera_point_offset
    path.show_in_front = True
    for collection in obj.users_collection:
        if collection.is_editable:
            collection.objects.link(path)


def sync_gates(placement):
    obj = placement.id_data
    if not obj.is_editable:
        return
    roles = active_gates(placement)
    for role, (label, color) in GATES.items():
        child = gate_for(obj, role)
        if child:
            child.hide_viewport = role not in roles
        elif role in roles and obj.users_collection:
            width, depth, height = placement.camera_volume_size
            child = bpy.data.objects.new(label, None)
            child[GATE_ROLE] = role
            child.parent = obj
            child.empty_display_type = "CUBE"
            child.empty_display_size = 0.5
            child.show_in_front = True
            child.color = color
            if role == "rearm":
                child.scale = (width + 4, depth + 10, height + 4)
            else:
                child.location = (0, depth * (-0.5 if role == "entry" else 0.5), 0)
                child.scale = (width, 4, height)
            for collection in obj.users_collection:
                if collection.is_editable:
                    collection.objects.link(child)


def copy_helpers(obj, source):
    if source:
        lookup = [(placement_marker, key) for key in MARKER_FIELDS]
        lookup.extend((gate_for, role) for role in GATES)
        for find, key in lookup:
            original = find(source, key)
            if not original or find(obj, key):
                continue
            duplicate = original.copy()
            duplicate.parent = obj
            for collection in obj.users_collection:
                if collection.is_editable:
                    collection.objects.link(duplicate)
        path = path_for(source)
        if path and not path_for(obj):
            duplicate = path.copy()
            duplicate.data = path.data.copy()
            duplicate.parent = obj
            for collection in obj.users_collection:
                if collection.is_editable:
                    collection.objects.link(duplicate)
    sync_gates(obj.sonic_vane_placement)
    sync_path(obj.sonic_vane_placement)


def box_corners(center, rotation, half_size):
    return [
        center + rotation @ Vector((half_size.x * x, half_size.y * y, half_size.z * z))
        for x, y, z in CORNER_SIGNS
    ]


def shot_guides(obj, world):
    placement = obj.sonic_vane_placement
    center = world.translation
    rotation = world.to_quaternion()
    half_size = placement.camera_volume_size * 0.5
    box = box_corners(center, rotation, half_size) if placement.camera_activation_mode == "occupancy" else []
    if not placement.camera_override_position or not placement.camera_override_aim:
        return box, []
    entry = gate_for(obj, "entry") if not box else None
    sample = center + rotation @ entry.matrix_local.translation if entry else center
    aim_point = marker_world(obj, AIM_POINT, world) if placement.camera_aim_mode == "marker" else sample
    target = aim_point + placement.camera_aim_offset
    anchor = sample if placement.camera_position_mode.startswith("player_") else marker_world(obj, CAMERA_POINT, world)
    if placement.camera_position_mode == "path_camera":
        path = path_for(obj)
        if path:
            anchor = path_preview_point(path, world, sample)
    offset = placement.camera_position_offset
    if placement.camera_offset_space == "constraint":
        offset = rotation @ offset
    anchor = anchor + offset
    camera = anchor
    if placement.camera_position_mode.endswith("_pivot"):
        away = anchor - target
        if away.length_squared < 1e-8:
            away = rotation @ Vector((0, -1, 0))
        distance = placement.camera_orbit_distance if placement.camera_override_orbit_distance else 16.0
        camera = anchor + away.normalized() * distance
    direction = target - camera
    distance = direction.length
    if distance < 0.001:
        return box, []
    direction.normalize()
    side = direction.cross(WORLD_UP)
    if side.length_squared < 1e-8:
        side = direction.cross(Vector((0, 1, 0)))
    side.normalize()
    up = side.cross(direction)
    fov = placement.camera_shot_fov if placement.camera_override_fov else 70.0
    slope = tan(radians(fov * 0.5))
    depth = min(distance * 0.35, 4.0 / max(1.0, slope))
    height = slope * depth
    plane = camera + direction * depth
    corners = [
        plane + side * (height * PREVIEW_ASPECTS[placement.camera_preview_aspect] * x) + up * (height * y)
        for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))
    ]
    lines = [camera, target]
    for index, corner in enumerate(corners):
        lines.extend((camera, corner, corner, corners[(index + 1) % 4]))
    return box, lines


def path_preview_point(path, world, sample):
    points, _, _ = curve_samples(path)
    if len(points) < 2:
        return world.translation
    rigid_world = world.to_quaternion().to_matrix().to_4x4()
    rigid_world.translation = world.translation
    transform = rigid_world @ path.matrix_local
    locations = [transform @ point for point in points]
    closest = locations[0]
    closest_distance = (closest - sample).length_squared
    for start, end in zip(locations, locations[1:]):
        segment = end - start
        if segment.length_squared < 1e-10:
            continue
        progress = min(max((sample - start).dot(segment) / segment.length_squared, 0.0), 1.0)
        candidate = start + segment * progress
        distance = (candidate - sample).length_squared
        if distance < closest_distance:
            closest = candidate
            closest_distance = distance
    return closest


def marker_world(obj, key, world):
    marker = placement_marker(obj, key)
    offset = marker.location if marker else getattr(obj.sonic_vane_placement, key)
    return world.translation + world.to_quaternion() @ offset


def ring_lines(center, radius, axes):
    lines = []
    for first, second in combinations(axes, 2):
        ring = []
        for index in range(48):
            angle = index * tau / 48
            ring.append(center + (first * cos(angle) + second * sin(angle)) * radius)
        for index, point in enumerate(ring):
            lines.extend((point, ring[(index + 1) % 48]))
    return lines


def release_guides(obj, world):
    placement = obj.sonic_vane_placement
    if placement.camera_activation_mode != "entry_gate" or not placement.camera_distance_enabled:
        return []
    center = world.translation
    if placement.camera_distance_reference == "marker":
        center = marker_world(obj, RELEASE_POINT, world)
    return ring_lines(center, placement.camera_exit_distance, (Vector((1, 0, 0)), Vector((0, 1, 0)), WORLD_UP))


def influence_guides(obj, world):
    placement = obj.sonic_vane_placement
    if not placement.camera_influence_enabled or influence_error(placement):
        return (), ()
    center = marker_world(obj, INFLUENCE_POINT, world) if placement.camera_influence_center == "marker" else world.translation
    axes = [
        axis for axis, enabled in zip((Vector((1, 0, 0)), Vector((0, 1, 0)), WORLD_UP), placement.camera_influence_axes)
        if enabled
    ]
    if placement.camera_influence_frame == "constraint":
        rotation = world.to_quaternion()
        axes = [rotation @ axis for axis in axes]
    return tuple(influence_contour(center, radius, axes) for radius in (placement.camera_influence_full, placement.camera_influence_zero))


def influence_contour(center, radius, axes):
    if radius <= 0 or not axes:
        return ()
    if len(axes) > 1:
        return ring_lines(center, radius, axes)
    axis = axes[0]
    side = axis.cross(WORLD_UP)
    if side.length_squared < 1e-8:
        side = axis.cross(Vector((1, 0, 0)))
    side = side.normalized() * min(radius * 0.2, 3.0)
    return tuple(center + axis * (sign * radius) + side * end for sign in (-1, 1) for end in (-1, 1))


def draw():
    context = bpy.context
    obj = context.object
    if obj and (obj.get(MARKER_FIELD_KEY) in MARKER_FIELDS or obj.get(GATE_ROLE) in GATES or obj.get(PATH_ROLE)):
        obj = obj.parent
    if not obj or obj.sonic_vane_placement.kind != "camera_constraint" or not obj.visible_get():
        return
    if not obj.sonic_vane_placement.camera_constraint_guides or not context.space_data.overlay.show_overlays:
        return
    world = obj.evaluated_get(context.evaluated_depsgraph_get()).matrix_world
    box, lines = shot_guides(obj, world)
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    if box:
        shader.uniform_float("color", (0.36, 0.63, 1.0, 0.85))
        batch_for_shader(shader, "LINES", {"pos": box}, indices=EDGES).draw(shader)
    rotation = world.to_quaternion()
    for role in active_gates(obj.sonic_vane_placement):
        gate = gate_for(obj, role)
        if not gate:
            continue
        offset, gate_rotation, size = gate.matrix_local.decompose()
        corners = box_corners(world.translation + rotation @ offset, rotation @ gate_rotation, size * 0.5)
        shader.uniform_float("color", GATES[role][1])
        batch_for_shader(shader, "LINES", {"pos": corners}, indices=EDGES).draw(shader)
    radius = release_guides(obj, world)
    if radius:
        shader.uniform_float("color", (0.46, 0.77, 0.67, 0.35))
        batch_for_shader(shader, "LINES", {"pos": radius}).draw(shader)
    for guide, color in zip(influence_guides(obj, world), ((0.32, 0.85, 0.58, 1.0), (0.22, 0.53, 0.42, 1.0))):
        if guide:
            shader.uniform_float("color", color)
            batch_for_shader(shader, "LINES", {"pos": guide}).draw(shader)
    if lines:
        shader.uniform_float("color", (1.0, 0.73, 0.25, 1.0))
        batch_for_shader(shader, "LINES", {"pos": lines}).draw(shader)

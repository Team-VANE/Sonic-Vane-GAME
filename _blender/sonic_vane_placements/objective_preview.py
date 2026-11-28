from math import cos, sin, tau

import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Vector

from .camera_preview import box_corners, marker_world, ring_lines
from .checkpoint_preview import EDGES
from .spring_preview import MARKER_FIELD_KEY


VOLUME_COLORS = {
    "rain_occluder": (0.40, 0.67, 1.0, 1.0),
    "rain_shelter": (0.40, 0.88, 0.66, 1.0),
    "carryable_respawn": (0.85, 0.62, 1.0, 1.0),
    "environment_transition": (1.0, 0.64, 0.29, 1.0),
}
VOLUME_BOX_KEY = "sonic_vane_volume_box"
SIZING_REFERENCE_KEY = "sonic_vane_sizing_reference"
TRAVERSAL_BOXES = {
    "ramp": ((0, 0.04, 0.879), (4.3, 5.2, 2.3579102)),
    "dash_panel": ((0, 0, 0.2), (5, 5, 1)),
    "rail_booster": ((0.1, 0, 0.9293544), (7, 6, 3)),
}
TRAVERSAL_GUIDES = TRAVERSAL_BOXES.keys() | {"spring", "vault_bar", "bumper", "fan"}
KINDS = {"goal_ring", "collection_item", "race_start", "homing_target", "gravity_modifier", "surface_behavior"} | VOLUME_COLORS.keys()
AXES = tuple(Vector(axis) for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1)))


def gravity_guides(placement, world):
    rotation = world.to_quaternion()
    origin = world.translation
    box = box_corners(origin, rotation, placement.gravity_modifier_size * 0.5)
    up = placement.gravity_modifier_gravity_up_direction.normalized()
    if placement.gravity_modifier_direction_is_local:
        up = rotation @ up
    if up.length_squared < 1e-6:
        return box, [], [], []
    side = up.cross(AXES[2] if abs(up.z) < 0.9 else AXES[0]).normalized()
    forward = up.cross(side)
    size = max(min(placement.gravity_modifier_size) * 0.18, 0.3)
    ground = origin - up * size
    plane = [ground - side * size, ground + side * size, ground - forward * size, ground + forward * size]
    strength = placement.gravity_modifier_gravity_multiplier
    arrow = []
    if strength > 0:
        length = size * max(0.6, min(strength + 0.5, 3.5))
        tip = origin - up * length
        arrow = [origin + up * size, tip]
        for axis in (side, -side, forward, -forward):
            arrow.extend((tip, tip + up * size * 0.5 + axis * size * 0.3))
    timer = []
    if placement.gravity_modifier_timed:
        center = origin + side * size * 1.8
        radius = size * 0.45
        timer = ring_lines(center, radius, (side, up))
        angle = min(placement.gravity_modifier_duration, 12) / 12 * tau
        timer.extend((center, center + up * radius * 0.72, center,
                      center + (side * sin(angle) + up * cos(angle)) * radius * 0.85))
    return box, arrow, plane, timer


def draw_lines(shader, points, color, indices=None):
    if points:
        shader.uniform_float("color", color)
        batch_for_shader(shader, "LINES", {"pos": points}, indices=indices).draw(shader)


def volume_boxes(obj):
    return [child for child in obj.children if child.get(VOLUME_BOX_KEY)]


def traversal_bounds(placement, origin, rotation):
    kind = placement.kind
    if kind == "bumper":
        return ring_lines(origin, 2.5, AXES), None
    if kind == "fan":
        x, y, up = (rotation @ axis for axis in AXES)
        radius = placement.column_radius
        top = origin + up * placement.column_height
        lines = ring_lines(origin, radius, (x, y)) + ring_lines(top, radius, (x, y))
        for axis in (x, y, -x, -y):
            lines.extend((origin + axis * radius, top + axis * radius))
        return lines, None
    if kind == "spring":
        dash_ring = placement.spring_style == "dash_ring"
        size = placement.size
        radius = (6.0 if dash_ring else 2.0) * size
        half_height = (1.0 if dash_ring else 1.00024415) * size
        x, y, up = (rotation @ axis for axis in AXES)
        center = origin + up * (0.2 * size)
        bottom, top = center - up * half_height, center + up * half_height
        lines = ring_lines(bottom, radius, (x, y)) + ring_lines(top, radius, (x, y))
        for axis in (x, y, -x, -y):
            lines.extend((bottom + axis * radius, top + axis * radius))
        return lines, None
    if kind == "vault_bar":
        radius = placement.vault_collision_radius
        return box_corners(origin, rotation, Vector((placement.bar_length * 0.5, radius, radius))), EDGES
    offset, dimensions = TRAVERSAL_BOXES[kind]
    size = placement.size if kind in {"ramp", "dash_panel"} else 1.0
    return box_corners(origin + rotation @ (Vector(offset) * size), rotation, Vector(dimensions) * (0.5 * size)), EDGES


def draw():
    context = bpy.context
    obj = context.object
    if obj and (obj.get(MARKER_FIELD_KEY) in {"goal_ring_pose", "goal_ring_camera_point"} or obj.get(VOLUME_BOX_KEY)):
        obj = obj.parent
    if not obj or not obj.visible_get() or not context.space_data.overlay.show_overlays:
        return
    placement = obj.sonic_vane_placement
    kind = placement.kind
    if kind in TRAVERSAL_GUIDES and not obj.sonic_vane_show_size_guide:
        return
    if obj.get(SIZING_REFERENCE_KEY):
        world = obj.evaluated_get(context.evaluated_depsgraph_get()).matrix_world
        points = ring_lines(Vector((0, 0, 1)), obj.sonic_vane_reference_radius, AXES)
        shader = gpu.shader.from_builtin("UNIFORM_COLOR")
        shader.bind()
        draw_lines(shader, [world @ point for point in points], (0.25, 0.94, 0.9, 1.0))
        return
    if kind not in KINDS and kind not in TRAVERSAL_GUIDES:
        return
    world = obj.evaluated_get(context.evaluated_depsgraph_get()).matrix_world
    origin = world.translation
    rotation = world.to_quaternion()
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    cyan = (0.22, 0.75, 0.95, 1.0)
    amber = (1.0, 0.62, 0.20, 1.0)
    if kind in TRAVERSAL_GUIDES:
        points, edges = traversal_bounds(placement, origin, rotation)
        draw_lines(shader, points, amber, edges)
    elif kind in VOLUME_COLORS:
        size = getattr(placement, f"{kind}_size")
        color = VOLUME_COLORS[kind]
        if kind == "environment_transition" and not placement.environment_transition_enabled:
            color = (0.42, 0.42, 0.42, 1.0)
        draw_lines(shader, box_corners(origin, rotation, size * 0.5), color, EDGES)
        for box in volume_boxes(obj):
            offset, orientation, dimensions = box.matrix_local.decompose()
            corners = box_corners(origin + rotation @ offset, rotation @ orientation, dimensions * 0.5)
            draw_lines(shader, corners, color, EDGES)
    elif kind == "gravity_modifier":
        box, arrow, plane, timer = gravity_guides(placement, world)
        active = cyan if placement.gravity_modifier_active else (0.42, 0.42, 0.42, 1.0)
        draw_lines(shader, box, active, EDGES)
        draw_lines(shader, arrow, amber if placement.gravity_modifier_timed and placement.gravity_modifier_active else active)
        draw_lines(shader, plane, (0.55, 0.9, 0.55, 1.0))
        draw_lines(shader, timer, amber)
    elif kind == "goal_ring":
        center = origin + rotation @ Vector((0, 0, 10))
        draw_lines(shader, box_corners(center, rotation, placement.goal_ring_size * 0.5), amber, EDGES)
        draw_lines(shader, [marker_world(obj, "goal_ring_camera_point", world), marker_world(obj, "goal_ring_pose", world)], cyan)
    elif kind == "collection_item":
        draw_lines(shader, ring_lines(origin, placement.collection_item_collection_radius, AXES), (0.3, 0.8, 0.45, 1.0))
    elif kind == "race_start":
        x, y, up = (rotation @ axis for axis in AXES)
        bottom = origin - up * 1.5
        top = origin + up * 6.5
        points = ring_lines(bottom, 8.0, (x, y)) + ring_lines(top, 8.0, (x, y))
        for axis in (x, y, -x, -y):
            points.extend((bottom + axis * 8.0, top + axis * 8.0))
        start = origin + rotation @ placement.race_start_starting_line_offset
        points.extend((start - x * 3, start + x * 3, start, start + y * 5))
        draw_lines(shader, points, cyan)
    elif kind == "surface_behavior":
        color = {
            "force": cyan,
            "block": amber,
        }.get(placement.surface_behavior_rolling, (0.56, 0.80, 0.65, 1.0))
        if not placement.surface_behavior_enabled:
            color = (0.45, 0.45, 0.45, 1.0)
        if placement.surface_behavior_mode == "volume":
            draw_lines(shader, box_corners(origin, rotation, placement.surface_behavior_size * 0.5), color, EDGES)
        else:
            lines = []
            for entry in placement.surface_targets:
                target = entry.target
                if not target or not target.visible_get():
                    continue
                transform = target.matrix_world
                corners = [transform @ Vector(corner) for corner in target.bound_box]
                center = sum(corners, Vector()) / len(corners)
                lines.extend((origin, center))
                for index in range(4):
                    following = (index + 1) % 4
                    lines.extend((corners[index], corners[following], corners[index + 4], corners[following + 4],
                                  corners[index], corners[index + 4]))
            draw_lines(shader, lines, color)
    elif placement.homing_target_homing_target_max_distance > 0:
        draw_lines(shader, ring_lines(origin, placement.homing_target_homing_target_max_distance, AXES), (0.93, 0.44, 0.67, 1.0))

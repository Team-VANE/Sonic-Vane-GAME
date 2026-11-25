from math import pi

import bpy
import gpu
from bpy.app.handlers import persistent
from gpu_extras.batch import batch_for_shader
from mathutils import Quaternion, Vector

from .model_preview import set_rotation


MARKER_FIELD_KEY = "sonic_vane_marker_field"
TARGET_FIELD = "trajectory_target_offset"
MODIFIER = "Sonic Vane Spring Aim"
UP = Vector((0, 0, 1))
DASH_RING_CENTER = Vector((0, 0, -1.4942181))
DASH_RING_FLIP = Quaternion((1, 0, 0), pi)
AXES = {
    "positive_y": (0, 0, 1),
    "negative_y": (0, 0, -1),
    "positive_z": (0, -1, 0),
    "negative_z": (0, 1, 0),
}


def placement_marker(obj, key):
    return next((child for child in obj.children if child.get(MARKER_FIELD_KEY) == key), None)


def trajectory(obj):
    placement = obj.sonic_vane_placement
    if placement.kind != "spring" or not placement.use_trajectory_solver:
        return None
    marker = placement_marker(obj, TARGET_FIELD)
    offset = marker.location if marker else placement.trajectory_target_offset
    if offset.length_squared <= 1e-6:
        return None
    rotation = obj.matrix_world.to_quaternion()
    world_up = rotation @ UP if placement.trajectory_arc_up_mode == "spring_local_up" else UP
    height = placement.trajectory_arc_height if placement.trajectory_arc_enabled else 0.0
    return obj.matrix_world.translation, rotation @ offset, world_up * (4 * height)


def trajectory_points(obj, steps=40):
    path = trajectory(obj)
    if path is None:
        return ()
    start, displacement, lift = path
    return tuple(start + displacement * t + lift * (t * (1 - t))
                 for t in (index / steps for index in range(steps + 1)))


def sync_model(placement, _context=None):
    obj = placement.id_data
    if not obj.is_editable or obj.type != "MESH":
        return
    if placement.kind != "spring":
        set_rotation(obj, MODIFIER, None)
        return
    scale = placement.size
    path = trajectory(obj)
    axis = Vector(AXES[placement.launch_axis])
    aim = None
    if path is not None:
        _, displacement, lift = path
        direction = obj.matrix_world.to_quaternion().inverted() @ (displacement + lift)
        if direction.length_squared > 1e-6:
            aim = axis.rotation_difference(direction.normalized())
    if placement.spring_style == "dash_ring":
        set_dash_ring_pose(obj, axis, aim if aim is not None else Quaternion(), scale)
    else:
        rotation = aim.to_euler() if aim is not None else ((0, 0, 0) if scale != 1.0 else None)
        set_rotation(obj, MODIFIER, rotation, scale=scale)


def set_dash_ring_pose(obj, axis, aim, scale=1.0):
    facing = UP.rotation_difference(axis) @ DASH_RING_FLIP
    offset = aim @ (DASH_RING_CENTER - facing @ DASH_RING_CENTER)
    set_rotation(obj, MODIFIER, (aim @ facing).to_euler(), offset * scale, scale=scale)


@persistent
def sync_moved_targets(_scene, depsgraph):
    springs = set()
    for update in depsgraph.updates:
        if not isinstance(update.id, bpy.types.Object) or not update.is_updated_transform:
            continue
        obj = update.id.original
        if obj.get(MARKER_FIELD_KEY) == TARGET_FIELD and obj.parent:
            obj = obj.parent
        if obj.sonic_vane_placement.kind == "spring" and obj.sonic_vane_placement.use_trajectory_solver:
            springs.add(obj)
    for spring in springs:
        sync_model(spring.sonic_vane_placement)


def draw():
    obj = bpy.context.object
    if not obj or obj.sonic_vane_placement.kind != "spring" or not obj.sonic_vane_show_trajectory or not obj.visible_get():
        return
    if not bpy.context.space_data.overlay.show_overlays:
        return
    points = trajectory_points(obj)
    if not points:
        return
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    shader.uniform_float("color", (0.28, 0.82, 1.0, 1.0))
    batch_for_shader(shader, "LINE_STRIP", {"pos": points}).draw(shader)

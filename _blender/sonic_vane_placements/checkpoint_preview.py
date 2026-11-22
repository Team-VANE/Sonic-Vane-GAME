from itertools import product

import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Vector

from .spring_preview import MARKER_FIELD_KEY, placement_marker


TRIGGER_CENTER = "checkpoint_trigger_offset"
CORNER_SIGNS = tuple(product((-1, 1), repeat=3))
EDGES = tuple(
    (corner, corner | axis) for corner in range(8) for axis in (1, 2, 4)
    if not corner & axis
)


def trigger_bounds(obj):
    placement = obj.sonic_vane_placement
    marker = placement_marker(obj, TRIGGER_CENTER)
    center = marker.location if marker else placement.checkpoint_trigger_offset
    width = placement.checkpoint_width if placement.fit_trigger_to_width else placement.trigger_width
    return center, Vector((width, placement.trigger_depth, placement.trigger_height))


def draw():
    context = bpy.context
    obj = context.object
    if obj and obj.get(MARKER_FIELD_KEY) == TRIGGER_CENTER:
        obj = obj.parent
    if not obj or obj.sonic_vane_placement.kind != "checkpoint" or not obj.visible_get():
        return
    if not obj.sonic_vane_show_trigger or not context.space_data.overlay.show_overlays:
        return

    center, size = trigger_bounds(obj)
    world = obj.evaluated_get(context.evaluated_depsgraph_get()).matrix_world
    rotation = world.to_quaternion()
    origin = world.translation + rotation @ center
    half_size = size * 0.5
    corners = [
        origin + rotation @ Vector((half_size.x * x, half_size.y * y, half_size.z * z))
        for x, y, z in CORNER_SIGNS
    ]
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    shader.uniform_float("color", (1.0, 0.68, 0.22, 1.0))
    batch_for_shader(shader, "LINES", {"pos": corners}, indices=EDGES).draw(shader)

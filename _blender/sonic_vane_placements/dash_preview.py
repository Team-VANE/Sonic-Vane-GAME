from math import atan2

import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Vector
from .model_preview import set_rotation


AXES = {
    "positive_x": (1, 0, 0),
    "negative_x": (-1, 0, 0),
    "positive_z": (0, -1, 0),
    "negative_z": (0, 1, 0),
}
PANEL_MESH_KEY = "sonic_vane_dash_panel_preview"
MODIFIER = "Sonic Vane Dash Facing"


def panel_direction(obj):
    placement = obj.sonic_vane_placement
    axis = Vector(AXES[placement.ramp_launch_axis if placement.kind == "ramp" else placement.dash_launch_axis])
    return (obj.matrix_world.to_3x3() @ axis).normalized()


def sync_model(placement, _context=None):
    obj = placement.id_data
    if not obj.is_editable or obj.type != "MESH":
        return
    if placement.kind != "dash_panel":
        set_rotation(obj, MODIFIER, None)
        return
    if not obj.data.get(PANEL_MESH_KEY) and not obj.data.name.startswith("Sonic Vane Dash Panel"):
        return
    set_panel_axis(obj, placement.dash_launch_axis)


def set_panel_axis(obj, axis):
    x, y, _ = AXES[axis]
    set_rotation(obj, MODIFIER, (0, 0, atan2(-x, y)))


def draw():
    obj = bpy.context.object
    if not obj or obj.sonic_vane_placement.kind not in {"dash_panel", "ramp"}:
        return
    if not obj.sonic_vane_dash_direction or not obj.visible_get():
        return
    if not bpy.context.space_data.overlay.show_overlays:
        return
    direction = panel_direction(obj)
    size = obj.sonic_vane_placement.size
    world = obj.matrix_world
    side = (world.to_quaternion() @ Vector((0, 0, 1))).cross(direction)
    start = world @ Vector((0, 0, 0.75))
    tip = start + direction * (5 * size)
    shoulder = tip - direction * (1.15 * size)
    side *= 0.62 * size
    points = (start, tip, tip, shoulder + side, tip, shoulder - side)
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    shader.uniform_float("color", (0.25, 1.0, 0.63, 1.0))
    batch_for_shader(shader, "LINES", {"pos": points}).draw(shader)

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


def booster_direction(obj):
    placement = obj.sonic_vane_placement
    reverse = placement.reverse_direction and placement.booster_rail.sonic_vane_placement.allow_reverse
    forward = obj.matrix_world.col[1].to_3d().normalized()
    return -forward if reverse != (placement.boost_speed < 0.0) else forward


def draw():
    obj = bpy.context.object
    if not obj or not obj.visible_get() or not bpy.context.space_data.overlay.show_overlays:
        return
    placement = obj.sonic_vane_placement
    world = obj.matrix_world
    if placement.kind == "rail_booster" and placement.booster_show_direction and placement.booster_rail:
        direction = booster_direction(obj)
        size = 1.0
        start = world @ Vector((0, 0, 1.55))
    elif placement.kind in {"dash_panel", "ramp"} and obj.sonic_vane_dash_direction:
        direction = panel_direction(obj)
        size = placement.size
        start = world @ Vector((0, 0, 0.75))
    else:
        return
    side = (world.to_quaternion() @ Vector((0, 0, 1))).cross(direction)
    tip = start + direction * (5 * size)
    shoulder = tip - direction * (1.15 * size)
    side *= 0.62 * size
    points = (start, tip, tip, shoulder + side, tip, shoulder - side)
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    shader.uniform_float("color", (0.25, 1.0, 0.63, 1.0))
    batch_for_shader(shader, "LINES", {"pos": points}).draw(shader)

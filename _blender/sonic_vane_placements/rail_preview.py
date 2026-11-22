import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Quaternion, Vector


def draw():
    obj = bpy.context.object
    if not obj or obj.type != "CURVE" or obj.sonic_vane_placement.kind != "rail":
        return
    if not obj.sonic_vane_rail_guides or not obj.visible_get() or len(obj.data.splines) != 1:
        return
    spline = obj.data.splines[0]
    if spline.type != "BEZIER" or len(spline.bezier_points) < 2:
        return
    points = tuple(spline.bezier_points)
    pairs = zip(points, points[1:] + (points[:1] if spline.use_cyclic_u else ()))
    centerline, rider, arrows = [], [], []
    up = Vector((0, 0, 1))
    last_tangent = None
    world = obj.matrix_world
    world_up = world.to_quaternion().inverted() @ Vector((0, 0, 1))
    placement = obj.sonic_vane_placement
    for a, b in pairs:
        for index in range(17):
            t = index / 16
            s = 1 - t
            center = a.co * s**3 + a.handle_right * (3 * s*s*t) + b.handle_left * (3 * s*t*t) + b.co * t**3
            tangent = ((a.handle_right - a.co) * s*s
                       + (b.handle_left - a.handle_right) * (2*s*t)
                       + (b.co - b.handle_left) * t*t)
            if tangent.length_squared < 1e-10:
                tangent = b.co - a.co
            if tangent.length_squared < 1e-10:
                continue
            tangent.normalize()
            if last_tangent is not None:
                up = last_tangent.rotation_difference(tangent) @ up
            else:
                up -= tangent * up.dot(tangent)
                if up.length_squared < 1e-10:
                    up = tangent.cross(Vector((0, 1, 0)))
                up.normalize()
            last_tangent = tangent
            if placement.align_to_path_tilt:
                rider_up = Quaternion(tangent, (1 - t) * a.tilt + t * b.tilt) @ up
            else:
                projected_up = world_up - tangent * world_up.dot(tangent)
                rider_up = projected_up.normalized() if projected_up.length_squared > 1e-10 else up
            centerline.append(world @ center)
            rider.append(world @ (center + rider_up * placement.player_height_offset))
            if index == 8:
                side = tangent.cross(rider_up) * 0.35
                tip = center + tangent
                arrows.extend(world @ value for value in (center, tip, tip, center + side, tip, center - side))
    if len(centerline) < 2:
        return
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    for primitive, vertices, color in [
        ("LINE_STRIP", centerline, (0.1, 0.75, 1, 1)),
        ("LINE_STRIP", rider, (1, 0.7, 0.2, 1)),
        ("LINES", arrows, (1, 1, 1, 1)),
    ]:
        if vertices:
            shader.uniform_float("color", color)
            batch_for_shader(shader, primitive, {"pos": vertices}).draw(shader)
    if not spline.use_cyclic_u:
        gpu.state.point_size_set(7)
        try:
            for position, color in ((centerline[0], (0.2, 1, 0.3, 1)), (centerline[-1], (1, 0.3, 0.2, 1))):
                shader.uniform_float("color", color)
                batch_for_shader(shader, "POINTS", {"pos": [position]}).draw(shader)
        finally:
            gpu.state.point_size_set(1)

from bisect import bisect_left
from math import atan2

import bpy
from bpy.app.handlers import persistent
from mathutils import Matrix, Quaternion, Vector
from mathutils.geometry import interpolate_bezier


def rail_poll(_placement, obj):
    return obj.type == "CURVE" and obj.sonic_vane_placement.kind == "rail"


def sample_rail(rail):
    if len(rail.data.splines) != 1:
        return None
    spline = rail.data.splines[0]
    if spline.type != "BEZIER" or len(spline.bezier_points) < 2:
        return None
    points = tuple(spline.bezier_points)
    following = points[1:] + (points[:1] if spline.use_cyclic_u else ())
    samples = []
    for a, b in zip(points, following):
        positions = interpolate_bezier(a.co, a.handle_right, b.handle_left, b.co, 129)
        for index, position in enumerate(positions):
            if samples and (position - samples[-1][1]).length_squared < 1e-12:
                continue
            t = index / 128
            s = 1 - t
            tangent = ((a.handle_right - a.co) * s*s
                       + (b.handle_left - a.handle_right) * (2*s*t)
                       + (b.co - b.handle_left) * t*t)
            if tangent.length_squared < 1e-12:
                tangent = positions[min(index + 1, 128)] - positions[max(index - 1, 0)]
            if tangent.length_squared < 1e-12:
                continue
            tangent.normalize()
            if samples:
                last_distance, last_position, last_tangent, last_up, _ = samples[-1]
                distance = last_distance + (position - last_position).length
                up = last_tangent.rotation_difference(tangent) @ last_up
            else:
                distance = 0.0
                up = Vector((0, 0, 1)) if abs(tangent.z) < 0.9999 else Vector((1, 0, 0))
                up = (up - tangent * tangent.dot(up)).normalized()
            samples.append((distance, position, tangent, up, (1 - t) * a.tilt + t * b.tilt))
    if len(samples) < 2:
        return None
    length, end, tangent, up, _ = samples[-1]
    _, start, first_tangent, first_up, _ = samples[0]
    if (end - start).length_squared < 1e-8 and first_tangent.dot(tangent) > 0.9999:
        correction = atan2(up.cross(first_up).dot(first_tangent), up.dot(first_up))
        samples = [
            (distance, position, forward, Quaternion(forward, correction * distance / length) @ normal, tilt)
            for distance, position, forward, normal, tilt in samples
        ]
    return samples


def sync_preview(placement, depsgraph=None, sampled=None):
    rail = placement.booster_rail
    obj = placement.id_data
    if placement.kind != "rail_booster" or not rail or not rail_poll(placement, rail) or not obj.is_editable:
        return
    samples = sampled if sampled is not None else sample_rail(rail)
    if not samples:
        return
    distance = samples[-1][0] * placement.booster_position / 100
    index = max(1, min(len(samples) - 1, bisect_left(samples, distance, key=lambda sample: sample[0])))
    first, second = samples[index - 1:index + 1]
    alpha = (distance - first[0]) / (second[0] - first[0])
    position = first[1].lerp(second[1], alpha)
    forward = first[2].lerp(second[2], alpha).normalized()
    if not forward.length_squared:
        forward = first[2]
    up = first[3].lerp(second[3], alpha)
    up = (up - forward * up.dot(forward)).normalized()
    tilt = first[4] + (second[4] - first[4]) * alpha
    up = Quaternion(forward, tilt) @ up
    basis = Matrix((forward.cross(up), forward, up)).transposed().to_4x4()
    basis.translation = position
    world = rail.evaluated_get(depsgraph).matrix_world if depsgraph else rail.matrix_world
    matrix = world @ basis
    if any(abs(a - b) > 1e-5 for old, new in zip(obj.matrix_world, matrix) for a, b in zip(old, new)):
        obj.matrix_world = matrix


def update_preview(placement, _context):
    sync_preview(placement)


@persistent
def sync_moved_rails(scene, depsgraph):
    changed = {update.id.original for update in depsgraph.updates if isinstance(update.id, (bpy.types.Object, bpy.types.Curve))}
    if not changed:
        return
    samples = {}
    for obj in scene.objects:
        placement = obj.sonic_vane_placement
        if placement.kind != "rail_booster":
            continue
        rail = placement.booster_rail
        if not rail or (obj not in changed and rail not in changed and rail.data not in changed):
            continue
        if rail not in samples:
            samples[rail] = sample_rail(rail) if rail_poll(placement, rail) else None
        if samples[rail]:
            sync_preview(placement, depsgraph, samples[rail])

from bisect import bisect_left
from functools import lru_cache
from itertools import product
from math import ceil, cos, sin, tau

import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Matrix, Quaternion, Vector
from mathutils.geometry import interpolate_bezier


BOX_ROLE = "sonic_vane_automation_box"
ROLES = {"occupancy": ("Volume",), "endpoints": ("Start", "End"), "area_crossings": ("Start", "End")}
SIGNS = tuple(product((-1, 1), repeat=3))
EDGES = tuple((i, i | bit) for i in range(8) for bit in (1, 2, 4) if not (i & bit))
UP = Vector((0, 0, 1))


def box_for(obj, role):
    return next((child for child in obj.children if child.get(BOX_ROLE) == role), None)


def curve_samples(obj):
    if obj.type != "CURVE" or len(obj.data.splines) != 1:
        return (), (), ()
    spline = obj.data.splines[0]
    if spline.type != "BEZIER" or len(spline.bezier_points) < 2:
        return (), (), ()
    controls = tuple((tuple(p.co), tuple(p.handle_left), tuple(p.handle_right), p.tilt) for p in spline.bezier_points)
    return _samples(controls, spline.use_cyclic_u)


@lru_cache(maxsize=16)
def _samples(controls, closed):
    points, tilts = [], []
    count = len(controls)
    for i in range(count if closed else count - 1):
        start, _, out_handle, start_tilt = controls[i]
        end, in_handle, _, end_tilt = controls[(i + 1) % count]
        segment = interpolate_bezier(Vector(start), Vector(out_handle), Vector(in_handle), Vector(end), 25)
        for j, point in enumerate(segment):
            if not points or (point - points[-1]).length_squared > 1e-10:
                points.append(point)
                tilts.append(start_tilt + (end_tilt - start_tilt) * j / 24)
    if len(points) < 2:
        return (), (), ()
    distances = [0.0]
    tangents = []
    previous_up = UP
    ups = []
    for i, point in enumerate(points):
        if i:
            distances.append(distances[-1] + (point - points[i - 1]).length)
        tangent = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        if not tangent.length_squared:
            tangent = tangents[-1]
        if i:
            previous_up = tangents[-1].rotation_difference(tangent) @ previous_up
        previous_up = frame_up(tangent, previous_up)
        tangents.append(tangent)
        ups.append(Quaternion(tangent, tilts[i]) @ previous_up)
    frames = tuple(zip(tangents, ups))
    return tuple(points), tuple(distances), frames


def frame_up(tangent, up):
    projected = up - tangent * tangent.dot(up)
    if projected.length_squared < 1e-8:
        fallback = Vector((1, 0, 0)) if abs(tangent.x) < 0.9 else Vector((0, 1, 0))
        projected = fallback - tangent * tangent.dot(fallback)
    return projected.normalized()


def sample(samples, distance):
    points, distances, frames = samples
    end = min(len(points) - 1, max(1, bisect_left(distances, distance)))
    start = end - 1
    factor = (distance - distances[start]) / (distances[end] - distances[start])
    tangent = frames[start][0].lerp(frames[end][0], factor).normalized()
    if not tangent.length_squared:
        tangent = frames[end][0]
    up = frame_up(tangent, frames[start][1].lerp(frames[end][1], factor))
    return points[start].lerp(points[end], factor), tangent, up


def box_rotation(tangent, up):
    side = tangent.cross(up).normalized()
    return Matrix((side, tangent, side.cross(tangent))).transposed().to_quaternion()


def sync_custom_boxes(placement, _context=None):
    obj = placement.id_data
    if not obj.is_editable:
        return
    roles = ()
    if placement.kind == "automation_spline" and placement.automation_trigger_layout == "custom":
        roles = ROLES.get(placement.automation_activation, ())
    samples = curve_samples(obj) if roles else ((), (), ())
    points, distances, frames = samples
    for role in ("Start", "End", "Volume"):
        child = box_for(obj, role)
        if child and child.hide_viewport != (role not in roles):
            child.hide_viewport = role not in roles
        if child or role not in roles or not points or not obj.users_collection:
            continue
        child = bpy.data.objects.new(f"Automation {role}", None)
        child[BOX_ROLE] = role
        child.parent = obj
        child.empty_display_type = "CUBE"
        child.empty_display_size = 0.5
        child.show_in_front = True
        if role == "Volume":
            lower = Vector(tuple(min(p[i] for p in points) for i in range(3)))
            upper = Vector(tuple(max(p[i] for p in points) for i in range(3)))
            child.location = (lower + upper) * 0.5
            child.scale = upper - lower + Vector((8, 2, 8))
        else:
            index = 0 if role == "Start" else -1
            child.location = points[index]
            child.rotation_mode = "QUATERNION"
            child.rotation_quaternion = box_rotation(*frames[index])
            child.scale = (8, 2, 8)
        for collection in obj.users_collection:
            if collection.is_editable:
                collection.objects.link(child)


def copy_custom_boxes(obj, source):
    placement = obj.sonic_vane_placement
    if placement.automation_trigger_layout != "custom":
        return
    if source:
        for role in ROLES.get(placement.automation_activation, ()):
            original = box_for(source, role)
            if not original or box_for(obj, role):
                continue
            duplicate = original.copy()
            duplicate.parent = obj
            for collection in obj.users_collection:
                if collection.is_editable:
                    collection.objects.link(duplicate)
    sync_custom_boxes(placement)


def generated_boxes(obj):
    placement = obj.sonic_vane_placement
    points, distances, frames = samples = curve_samples(obj)
    if not points or placement.automation_trigger_layout != "generated":
        return ()
    width, height = placement.automation_trigger_width, placement.automation_trigger_height
    depth = placement.automation_trigger_gate_depth
    if placement.automation_activation in {"endpoints", "area_crossings"}:
        return tuple((points[i], box_rotation(*frames[i]), Vector((width, depth, height))) for i in (0, -1))
    if placement.automation_activation != "occupancy":
        return ()
    length = distances[-1]
    step = max(min(placement.automation_trigger_spacing, width * 0.5), 0.1)
    count = min(2048, max(1, ceil(length / step)))
    boxes = []
    stride = max(1, ceil(count / 192))
    for i in range(0, count, stride):
        a = sample(samples, length * i / count)[0]
        b = sample(samples, length * (i + 1) / count)[0]
        _, mid_tangent, up = sample(samples, length * (i + 0.5) / count)
        tangent = (b - a).normalized()
        if not tangent.length_squared:
            tangent = mid_tangent
        boxes.append(((a + b) * 0.5, box_rotation(tangent, frame_up(tangent, up)),
                      Vector((width, (b - a).length + depth, height))))
    return boxes


def capture_distance_lines(samples, radius):
    if radius <= 0 or not samples[0]:
        return ()
    center, tangent, up = sample(samples, samples[1][-1] * 0.5)
    side = tangent.cross(up).normalized()

    def point(angle):
        return center + (side * cos(angle) + up * sin(angle)) * radius

    lines = []
    step = tau / 20
    for index in range(20):
        angle = step * index
        start, middle, end = (point(angle + step * offset) for offset in (0, 0.28, 0.56))
        lines.extend((start, middle, middle, end))
    return lines


def draw():
    context = bpy.context
    obj = context.object
    if obj and obj.get(BOX_ROLE):
        obj = obj.parent
    if (not obj or obj.sonic_vane_placement.kind != "automation_spline" or not obj.visible_get()
            or not obj.sonic_vane_automation_guides or not context.space_data.overlay.show_overlays):
        return
    points, distances, frames = samples = curve_samples(obj)
    if not points:
        return
    matrix = obj.matrix_world.normalized()
    shader = gpu.shader.from_builtin("UNIFORM_COLOR")

    def draw_lines(vertices, color, mode):
        if vertices:
            shader.bind()
            shader.uniform_float("color", color)
            batch_for_shader(shader, mode, {"pos": [matrix @ v for v in vertices]}).draw(shader)

    capture = capture_distance_lines(samples, obj.sonic_vane_placement.automation_capture_distance)
    if capture:
        blend = gpu.state.blend_get()
        try:
            gpu.state.blend_set("ALPHA")
            draw_lines(capture, (0.47, 0.63, 0.69, 0.42), "LINES")
        finally:
            gpu.state.blend_set(blend)
    draw_lines(points, (0.2, 0.8, 1.0, 1), "LINE_STRIP")
    outlines = []
    for center, rotation, size in generated_boxes(obj):
        half = size * 0.5
        corners = [center + rotation @ Vector((x * half.x, y * half.y, z * half.z)) for x, y, z in SIGNS]
        outlines.extend(corners[index] for edge in EDGES for index in edge)
    draw_lines(outlines, (1.0, 0.65, 0.18, 1), "LINES")
    arrows = []
    direction = obj.sonic_vane_placement.automation_direction
    for fraction in (0.12, 0.5, 0.88):
        point, tangent, up = sample(samples, distances[-1] * fraction)
        side = tangent.cross(up)
        for sign in ((1, -1) if direction == "both" else (1,) if direction == "forward" else (-1,)):
            tip = point + tangent * sign * min(1.5, distances[-1] * 0.06)
            arrows.extend((point, tip, point + side * 0.4, tip, point - side * 0.4, tip))
    draw_lines(arrows, (0.2, 0.8, 1.0, 1), "LINES")
    annotations = []
    for extension in obj.sonic_vane_placement.automation_extensions:
        if not extension.enabled:
            continue
        if extension.kind == "event":
            position, tangent, up = sample(samples, distances[-1] * extension.progress)
            side = tangent.cross(up)
            annotations.extend((position - side, position + side, position, position + up))
        elif extension.destination and extension.destination != obj:
            destination = extension.destination
            target_samples = curve_samples(destination)
            if not target_samples[0]:
                continue
            first = sample(samples, distances[-1] * extension.source_progress)[0]
            last, tangent, up = sample(target_samples, target_samples[1][-1] * extension.destination_progress)
            transform = matrix.inverted() @ destination.matrix_world.normalized()
            sign = 1 if extension.destination_direction == "forward" else -1
            tip = last + tangent * sign * 1.5
            side = tangent.cross(up) * 0.45
            annotations.extend((first, transform @ last, transform @ (last + side), transform @ tip,
                                transform @ (last - side), transform @ tip))
    draw_lines(annotations, (1, 0.35, 0.75, 1), "LINES")

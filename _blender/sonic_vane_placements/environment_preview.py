import json
from math import asin, cos, degrees, floor, sin, tau
from pathlib import Path

import blf
import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Vector


PREVIEW_DATA = json.loads(Path(__file__).with_name("environment_preview_data.json").read_text(encoding="utf-8"))
WHITE = (0.91, 0.94, 0.98, 1.0)
MUTED = (0.67, 0.73, 0.80, 1.0)
HORIZON_RING = tuple(Vector((cos(i * tau / 32), sin(i * tau / 32), 0.0)) for i in range(32))


def redraw_viewports(_settings, context):
    if context.window_manager:
        for window in context.window_manager.windows:
            for area in window.screen.areas:
                if area.type == "VIEW_3D":
                    area.tag_redraw()


def selection(settings, preview):
    profile = settings.sky_profile if settings.override_sky_profile else "earth_like"
    weather = preview.weather
    if weather == "authored":
        weather = settings.starting_weather if settings.override_starting_weather else "clear"
    if weather == "random":
        weather = "clear"
    return profile, weather


def sun_direction(hour):
    angle = (hour % 24.0 - 6.0) * tau / 24.0
    return Vector((cos(angle), 0.0, sin(angle)))


def display_color(color):
    return tuple(
        min(1.0, 12.92 * value if value <= 0.0031308 else 1.055 * value ** (1.0 / 2.4) - 0.055)
        for value in color
    ) + (1.0,)


def sample(profile_id, weather_id, hour):
    profile = PREVIEW_DATA["profiles"][profile_id]
    samples = profile["samples"]
    position = hour % 24.0 / 24.0 * len(samples)
    index = floor(position)
    weight = position - index
    first = samples[index]
    second = samples[(index + 1) % len(samples)]
    coverage, light, fog_multiplier, saturation = PREVIEW_DATA["weather"][weather_id]

    def sky_color(channel):
        color = Vector(first[channel]).lerp(Vector(second[channel]), weight)
        luminance = color.dot(Vector((0.2126, 0.7152, 0.0722)))
        greying = 1.0 - saturation * (1.0 - coverage * 0.28)
        color = color.lerp(Vector((luminance,) * 3), greying)
        return color * (1.0 - coverage * (1.0 - light) * 0.45)

    fog = Vector(first[2]).lerp(Vector(second[2]), weight)
    density = (first[3] * (1 - weight) + second[3] * weight) * fog_multiplier
    zenith = sky_color(0)
    horizon = sky_color(1).lerp(fog, min(0.80, density * 500.0))
    return display_color(zenith), display_color(horizon), display_color(fog), density > 0.0, profile["sun_visible"]


def quad(shader, x, y, width, height, bottom, top):
    points = ((x, y), (x + width, y), (x, y + height), (x + width, y + height))
    batch_for_shader(shader, "TRI_STRIP", {"pos": points, "color": (bottom, bottom, top, top)}).draw(shader)


def line(shader, mode, points, color):
    shader.uniform_float("color", color)
    batch_for_shader(shader, mode, {"pos": points}).draw(shader)


def label(x, y, size, value, color):
    blf.size(0, max(1, round(size)))
    blf.color(0, *color)
    blf.position(0, x, y, 0)
    blf.draw(0, value)


def draw(profile_labels, weather_labels):
    context = bpy.context
    preview = context.scene.sonic_vane_environment_preview
    if not preview.enabled or not context.space_data.overlay.show_overlays or not context.region_data:
        return
    scale = min(context.preferences.system.ui_scale, context.region.width / 310, context.region.height / 180)
    if scale < 0.55:
        return
    profile, weather = selection(context.scene.sonic_vane_environment, preview)
    zenith, horizon, fog, fog_enabled, sun_visible = sample(profile, weather, preview.hour)
    direction = sun_direction(preview.hour)
    elevation = degrees(asin(max(-1.0, min(1.0, direction.z))))
    minutes = round(preview.hour * 60) % 1440
    time = f"{minutes // 60:02}:{minutes % 60:02}"
    blend = gpu.state.blend_get()
    gpu.state.blend_set("ALPHA")
    try:
        smooth = gpu.shader.from_builtin("SMOOTH_COLOR")
        smooth.bind()
        background = (0.025, 0.037, 0.054, 0.92)
        quad(smooth, 16 * scale, 24 * scale, 278 * scale, 132 * scale, background, background)
        quad(smooth, 27 * scale, 53 * scale, 168 * scale, 56 * scale, horizon, zenith)
        if fog_enabled:
            quad(smooth, 27 * scale, 35 * scale, 15 * scale, 10 * scale, fog, fog)
        label(27 * scale, 136 * scale, 13 * scale, f"{time}  {profile_labels[profile]}", WHITE)
        label(27 * scale, 118 * scale, 11 * scale, weather_labels[weather], MUTED)
        label((48 if fog_enabled else 27) * scale, 35 * scale, 11 * scale, "Fog" if fog_enabled else "Fog off", MUTED)
        draw_sun(context.region_data.view_rotation, direction, sun_visible, elevation, scale)
    finally:
        gpu.state.blend_set(blend)


def draw_sun(view_rotation, direction, visible, elevation, scale):
    rotation = view_rotation.inverted()
    center = Vector((244 * scale, 82 * scale))

    def project(vector):
        return center + (rotation @ vector).xy * (35 * scale)

    shader = gpu.shader.from_builtin("UNIFORM_COLOR")
    shader.bind()
    line(shader, "LINE_LOOP", [project(point) for point in HORIZON_RING], (0.29, 0.36, 0.46, 1.0))
    line(shader, "LINES", (center, project(Vector((0.0, 0.0, 1.0)))), (0.39, 0.49, 0.60, 1.0))
    tip = project(direction)
    color = (1.0, 0.73, 0.30, 1.0) if visible and elevation >= 0.0 else (0.57, 0.66, 0.80, 1.0)
    line(shader, "LINES", (center, tip), color)
    dot = [(tip.x + point.x * 4 * scale, tip.y + point.y * 4 * scale) for point in HORIZON_RING]
    line(shader, "TRI_FAN", dot, color)
    caption = f"Sun {elevation:+.0f}°" if visible else "Sun off"
    label(214 * scale, 35 * scale, 11 * scale, caption, MUTED)

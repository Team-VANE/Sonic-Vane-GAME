# SPDX-License-Identifier: GPL-3.0-or-later

import json
import math
import os
import re
import tempfile
import uuid
from pathlib import Path

import bpy
from bpy.app.handlers import persistent
from bpy.props import BoolProperty, BoolVectorProperty, CollectionProperty, EnumProperty, FloatProperty, FloatVectorProperty, IntProperty, PointerProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ExportHelper
from mathutils import Matrix, Vector
from . import automation_preview, booster_preview, camera_preview, checkpoint_preview, dash_preview, environment_preview, model_preview, objective_preview, rail_preview, ring_preview, spring_preview
from .spring_preview import MARKER_FIELD_KEY, placement_marker


CATALOG = json.loads(Path(__file__).with_name("catalog.json").read_text(encoding="utf-8"))
ENVIRONMENT_FIELDS = CATALOG["environment"]
WEATHER_PRESETS = {
    key: value for key, value in ENVIRONMENT_FIELDS["starting_weather"]["options"].items() if "path" in value
}
SKY_LABELS = {key: value["label"] for key, value in ENVIRONMENT_FIELDS["sky_profile"]["options"].items()}
WEATHER_LABELS = {key: value["label"] for key, value in WEATHER_PRESETS.items()}
PREVIEW_WEATHER_ITEMS = [("authored", "Starting Weather", "Use the authored preset or preview clear skies", 0)] + [
    (key, value["label"], "", value["value"] + 1) for key, value in WEATHER_PRESETS.items()
]
ENVIRONMENT_CHANNEL_PATTERN = re.compile(r"[A-Za-z0-9_]+")
AUTOMATION_EXTENSIONS = CATALOG["automation_extensions"]
for definition in CATALOG["types"].values():
    for field in definition["properties"].values():
        if "environment_preset" in field:
            field["options"] = {
                preset_id: option
                for preset_id, option in ENVIRONMENT_FIELDS[field["environment_preset"]]["options"].items()
                if "path" in option
            }
PLACEMENT_PROPERTIES = {
    key: field for definition in CATALOG["types"].values() for key, field in definition["properties"].items()
}
LEVEL_ID_PATTERN = re.compile(r"[a-z][a-z0-9_]*")
PLACEMENT_SUFFIX = ".placements.json"
PLACEMENT_SUFFIX_PATTERN = re.compile(r"(?:\.placements)+(?:\.json)?$|\.json$", re.IGNORECASE)
ASSET_LIBRARY_NAME = "Sonic Vane"
ASSET_DIRECTORY = Path(__file__).with_name("assets").resolve()
ASSET_TYPE_KEY = "sonic_vane_asset_type"
SPRING_STYLE_KEY = "sonic_vane_spring_style"
SPRING_STYLES = CATALOG["types"]["spring"]["properties"]["spring_style"]["options"]
SPRING_VARIANT_BOOLS = {key for style in SPRING_STYLES.values() for key in style.get("bool_defaults", {})}
RAIL_VARIANT_KEY = "sonic_vane_rail_variant"
RAIL_SEGMENT_KEY = "sonic_vane_rail_preview_segment"
PREVIEW_SOURCE_KEY = ring_preview.PREVIEW_SOURCE_KEY
MONITOR_STYLE_KEY = "sonic_vane_monitor_style"
MONITOR_MATERIAL_KEY = "sonic_vane_monitor_material"
MONITOR_TEXTURE_KEY = "sonic_vane_monitor_texture"
MONITOR_STYLES = CATALOG["types"]["item_monitor"]["properties"]["monitor_style"]["options"]
RING_TRAIL_GROUP = "Sonic Vane Ring Trail"
VARIANTS = CATALOG["variants"]
RING_VARIANTS = VARIANTS["ring"]
STANDARD_RING = "core:ring"
STANDARD_ENEMY = CATALOG["types"]["enemy"]["default_variant"]
DEFAULT_VARIANTS = {"ring": STANDARD_RING, "enemy": STANDARD_ENEMY}
RING_KINDS = {"ring", "ring_spline"}
SIZED_HAZARD_KINDS = {"enemy", "spike_strip", "spike_ball"}
ENEMY_HAZARD_LIBRARY = "Enemies and Hazards.blend"
VOLUME_LIBRARY = "Water Flippers and Portals.blend"
VOLUME_PREVIEWS = {"adventure_water", "flipper", "death_plane", "teleporter_entrance", "teleporter_exit"}
CONDITIONAL_EXPORT_KINDS = VOLUME_PREVIEWS | objective_preview.KINDS | {"automation_spline", "dash_panel", "enemy", "ring_spline", "planetary_gravity", "camera_constraint", "surface_behavior"}
SURFACE_TARGET_KEY = "vane_surface_target_id"
RACE_ID_PATTERN = re.compile(r"[A-Za-z0-9]{1,8}")
PLANETARY_LIBRARY = "Planetary Gravity.blend"
PLANETARY_GROUP = "Sonic Vane Planetary Gravity"
PLANETARY_PREVIEW_INPUTS = {
    "planetary_radius": "Influence Radius",
    "planetary_surface_radius": "Surface Radius",
    "planetary_field_only": "Field Only",
    "planetary_show_influence": "Show Influence",
}
USE_LEVEL_DEFAULT = "LEVEL_DEFAULT"
RAIL_VARIANTS = CATALOG["types"]["rail"]["properties"]["rail_variant"]["options"]
GAMEPLAY_COLLECTION_NAME = "Sonic Vane Gameplay"
MARKER_FIELDS = {
    key: field for definition in CATALOG["types"].values()
    for key, field in definition["properties"].items() if field["type"] == "local_offset"
}
MARKER_CONTROLS = {key for field in MARKER_FIELDS.values() for key in field.get("requires", {})}
Y_UP = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
rail_guides_handler = None
dash_direction_handler = None
spring_trajectory_handler = None
checkpoint_trigger_handler = None
automation_guides_handler = None
camera_guides_handler = None
objective_guides_handler = None
environment_preview_handler = None
known_object_ids = set()
tracking_new_objects = False


def variant_items(family):
    return (
        (USE_LEVEL_DEFAULT, "Use Level Default", f"Use the level's {family} variant", 0),
        *((key, entry["label"], key, entry["blender_index"]) for key, entry in VARIANTS[family].items()),
    )


VARIANT_ITEMS = {family: variant_items(family) for family in DEFAULT_VARIANTS}


def variant_family(kind):
    return CATALOG["types"][kind].get("variant_family", kind)


def effective_variant(placement, family, scene):
    variant = getattr(placement, f"{family}_variant")
    if variant != USE_LEVEL_DEFAULT:
        return variant
    return getattr(scene, f"sonic_vane_{family}_default") if scene else DEFAULT_VARIANTS[family]


def export_bezier(obj, world, local_transform=None):
    if (obj.type != "CURVE" or obj.data.dimensions != "3D"
            or len(obj.data.splines) != 1 or obj.data.splines[0].type != "BEZIER"):
        raise ValueError(f"{obj.name} needs one Bézier spline on a 3D curve.")
    if local_transform is None:
        rotation = world.to_quaternion().to_matrix()
        if any(abs(value - rotation[row][col]) > 0.0001
               for row, values in enumerate(world.to_3x3()) for col, value in enumerate(values)):
            raise ValueError(f"Apply the scale of {obj.name} before exporting the spline.")
        local_transform = Matrix.Identity(4)
    spline = obj.data.splines[0]
    if len(spline.bezier_points) < (3 if spline.use_cyclic_u else 2):
        raise ValueError(f"{obj.name} has too few Bézier points.")
    points = []
    basis = local_transform.to_3x3()
    for point in spline.bezier_points:
        data = {
            "position": list(Y_UP @ (local_transform @ point.co)),
            "in": list(Y_UP @ (basis @ (point.handle_left - point.co))),
            "out": list(Y_UP @ (basis @ (point.handle_right - point.co))),
            "tilt": point.tilt,
        }
        if not all(math.isfinite(value) for key in ("position", "in", "out") for value in data[key]) or not math.isfinite(point.tilt):
            raise ValueError(f"{obj.name} has a non-finite Bézier point.")
        points.append(data)
    return {"closed": spline.use_cyclic_u, "points": points}


def field_enabled(placement, field, scene=None):
    if field.get("local_destination_only") and placement.teleporter_link_mode != "local":
        return False
    if placement.kind == "automation_spline":
        if "trait_targets" in field and placement.automation_preset not in field["trait_targets"]:
            return False
        if "activation_modes" in field and placement.automation_activation not in field["activation_modes"]:
            return False
    if placement.kind == "enemy":
        scene = scene if scene is not None else bpy.context.scene
        variant = effective_variant(placement, "enemy", scene)
        if "for_variants" in field and variant not in field["for_variants"]:
            return False
        properties = CATALOG["types"]["enemy"]["properties"]
        for key, required in field.get("requires", {}).items():
            control = properties[key]
            if placement.is_property_set(key):
                value = getattr(placement, key)
            else:
                value = control.get("variant_defaults", {}).get(variant, control["default"])
            if value != required:
                return False
        return True
    return all(
        getattr(placement, key) in value if isinstance(value, list) else getattr(placement, key) == value
        for key, value in field.get("requires", {}).items()
    )


def sync_placement_markers(placement, _context):
    obj = placement.id_data
    if not obj.is_editable:
        return
    fields = CATALOG["types"].get(placement.kind, {}).get("properties", {})
    for key, field in MARKER_FIELDS.items():
        marker = placement_marker(obj, key)
        enabled = key in fields and field_enabled(placement, field)
        if enabled and marker is None and obj.users_collection:
            marker = bpy.data.objects.new(field.get("marker_label", field["label"]), None)
            marker[MARKER_FIELD_KEY] = key
            marker.parent = obj
            marker.location = getattr(placement, key)
            marker.empty_display_type = "SPHERE"
            marker.empty_display_size = 0.65
            marker.show_in_front = True
            for collection in obj.users_collection:
                if collection.is_editable:
                    collection.objects.link(marker)
        if marker and marker.hide_viewport == enabled:
            marker.hide_viewport = not enabled
    spring_preview.sync_model(placement)


@persistent
def sync_loaded_markers(*_):
    for scene in bpy.data.scenes:
        for obj in tuple(scene.objects):
            placement = obj.sonic_vane_placement
            if placement.kind != "NONE":
                sync_placement_markers(placement, None)
            if placement.kind == "rail_booster":
                booster_preview.sync_preview(placement)
            if placement.kind == "dash_panel":
                dash_preview.sync_model(placement)
            if placement.kind == "vault_bar":
                sync_vault_preview(placement, None)
            if placement.kind == "automation_spline":
                automation_preview.sync_custom_boxes(placement)
            if placement.kind in RING_KINDS:
                sync_ring_preview(placement, None, scene)
            if placement.kind in SIZED_HAZARD_KINDS:
                sync_enemy_hazard_preview(placement, scene)
            if placement.kind in VOLUME_PREVIEWS:
                sync_volume_preview(placement, None)
            if placement.kind == "planetary_gravity":
                sync_planetary_preview(placement, None)
            if placement.kind == "camera_constraint":
                camera_preview.sync_gates(placement)
                camera_preview.sync_path(placement)


def update_marker_offset(key):
    def update(placement, _context):
        marker = placement_marker(placement.id_data, key)
        if marker and marker.is_editable:
            marker.location = getattr(placement, key)
        spring_preview.sync_model(placement)
    return update


def build_placement_document(scene, depsgraph):
    level_id = scene.sonic_vane_level_id
    if not LEVEL_ID_PATTERN.fullmatch(level_id):
        raise ValueError("Set a level ID using lowercase letters, numbers, and underscores.")
    if not math.isclose(scene.unit_settings.scale_length, 1.0):
        raise ValueError("Set Unit Scale to 1.0 to match the GLB export.")

    environment = export_environment(scene.sonic_vane_environment)
    records = []
    names_by_id = {}
    race_ids = set()
    race_finish_ids = set()
    surface_ids = {}
    for obj in scene.objects:
        target_id = obj.get(SURFACE_TARGET_KEY)
        if isinstance(target_id, str):
            surface_ids[target_id] = obj if target_id not in surface_ids else None
    spawn_name = None
    for obj in scene.objects:
        placement = obj.sonic_vane_placement
        if placement.kind == "NONE":
            continue
        try:
            placement_id = str(uuid.UUID(placement.placement_id))
        except ValueError as exc:
            raise ValueError(f"{obj.name} needs a placement UUID.") from exc
        if placement_id in names_by_id:
            raise ValueError(f"{obj.name} and {names_by_id[placement_id]} share a placement UUID.")
        names_by_id[placement_id] = obj.name
        if placement.kind == "player_spawn":
            if spawn_name is not None:
                raise ValueError(f"{spawn_name} and {obj.name} are both marked as Player Spawn. Keep one per level.")
            spawn_name = obj.name

        world = obj.evaluated_get(depsgraph).matrix_world
        position = Y_UP @ world.translation
        rotation = (Y_UP @ world.to_quaternion().to_matrix() @ Y_UP.transposed()).to_quaternion()
        rotation.normalize()
        if rotation.w < 0.0:
            rotation.negate()
        xyzw = (rotation.x, rotation.y, rotation.z, rotation.w)
        if not all(math.isfinite(component) for component in (*position, *xyzw)):
            raise ValueError(f"{obj.name} has a non-finite transform.")

        values = {}
        for key, field in CATALOG["types"][placement.kind]["properties"].items():
            if field.get("authoring_only"):
                continue
            if placement.kind in CONDITIONAL_EXPORT_KINDS and not field_enabled(placement, field, scene):
                continue
            marker = None
            if field["type"] == "local_offset":
                if not field_enabled(placement, field):
                    continue
                marker = placement_marker(obj, key)
            if marker is None and not field.get("always_export") and not placement.is_property_set(key):
                continue
            value = getattr(placement, key)
            if field["type"] == "local_offset":
                if marker is not None:
                    value = marker.location
            if field["type"] in {"local_offset", "local_vector"}:
                value = list(Y_UP @ value)
                valid = all(math.isfinite(component) for component in value)
            elif field["type"] == "local_dimensions":
                value = [value.x, value.z, value.y]
                valid = all(math.isfinite(component) and component >= field["min"] for component in value)
            elif field["type"] == "color":
                value = list(value)
                valid = all(0 <= component <= 1 for component in value)
            elif field["type"] == "string":
                value = value.strip()
                valid = bool(value) or field.get("allow_empty", False)
            elif field["type"] == "physics_mask":
                value = sum(1 << index for index, enabled in enumerate(value) if enabled)
                valid = True
            elif field["type"] == "axis_mask":
                indices = (0, 1, 2) if "axis_labels" in field else (0, 2, 1)
                value = sum(1 << index for index, enabled in zip(indices, value) if enabled)
                valid = value != 0
            elif field["type"] in {"float", "int"}:
                valid = math.isfinite(value) and field["min"] <= value <= field.get("max", math.inf)
            elif field["type"] == "enum":
                valid = value in field["options"]
            else:
                valid = isinstance(value, bool)
            if not valid:
                raise ValueError(f"{obj.name} has an invalid {field['label']}.")
            values[key] = value
        record = {
            "id": placement_id,
            "type": placement.kind,
            "label": obj.name,
            "position": list(position),
            "rotation": list(xyzw),
            "properties": values,
        }
        presentation = {
            key: True for key in ("hidden", "muted")
            if getattr(placement, f"presentation_{key}")
        }
        if presentation:
            record["presentation"] = presentation
        if placement.kind == "environment_transition":
            preset = values.get("environment_transition_weather_id")
            if preset and "allowed_weather" in environment and preset not in environment["allowed_weather"]:
                raise ValueError(f"{obj.name} uses a weather preset outside the level's allowed list.")
            if placement.environment_transition_enabled and not (
                placement.environment_transition_time or preset or values.get("environment_transition_sky_id")
            ):
                raise ValueError(f"{obj.name} needs at least one environment override.")
        if placement.kind in objective_preview.VOLUME_COLORS:
            boxes = [
                export_local_box(box, world.inverted() @ box.evaluated_get(depsgraph).matrix_world)
                for box in objective_preview.volume_boxes(obj) if scene.objects.get(box.name) == box
            ]
            if boxes:
                record["volume_boxes"] = boxes
        family = variant_family(placement.kind)
        if family in VARIANTS:
            variant = getattr(placement, f"{family}_variant")
            if variant != USE_LEVEL_DEFAULT:
                record["variant"] = variant
        if "curve_target" in CATALOG["types"][placement.kind]:
            record["curve"] = export_bezier(obj, world)
        if placement.kind == "camera_constraint" and placement.camera_override_position and placement.camera_position_mode == "path_camera":
            path = camera_preview.path_for(obj)
            if not path or scene.objects.get(path.name) != path:
                raise ValueError(f"{obj.name} needs a camera path. Re-select Path Camera to restore it.")
            path_world = path.evaluated_get(depsgraph).matrix_world
            curve = export_bezier(path, path_world, world.inverted_safe() @ path_world)
            origin = Vector(curve["points"][0]["position"])
            if not any(
                (Vector(point["position"]) + Vector(handle) - origin).length_squared > 1e-6
                for point in curve["points"]
                for handle in ((0, 0, 0), point["in"], point["out"])
            ):
                raise ValueError(f"{path.name} needs a path with usable length.")
            record["curve"] = curve
        if placement.kind == "automation_spline":
            export_automation_triggers(obj, placement, record)
            if placement.automation_extensions:
                record["automation_extensions"] = export_automation_extensions(obj, scene)
        if placement.kind == "teleporter_entrance":
            record["teleporter_link"] = export_teleporter_link(obj, placement, scene)
        if placement.kind == "surface_behavior" and placement.surface_behavior_mode == "targets":
            targets = []
            for entry in placement.surface_targets:
                target = entry.target
                target_id = target.get(SURFACE_TARGET_KEY) if target else None
                if not target_id or surface_ids.get(target_id) != target or target_id in targets or target.sonic_vane_placement.kind != "NONE":
                    raise ValueError(f"{obj.name} has a missing or duplicate track target. Remove it and add the track mesh again.")
                targets.append(target_id)
            if not targets:
                raise ValueError(f"{obj.name} needs at least one track target.")
            record["surface_targets"] = targets
        if placement.kind == "gravity_modifier" and placement.gravity_modifier_gravity_up_direction.length_squared < 1e-6:
            raise ValueError(f"{obj.name} needs a nonzero gravity up direction.")
        if placement.kind == "race_start":
            race_id = (placement.race_start_race_id.strip() or placement_id[:8].upper()).lower()
            if not RACE_ID_PATTERN.fullmatch(race_id) or race_id in race_ids:
                raise ValueError(f"{obj.name} needs a distinct Race ID of one to eight letters or digits.")
            race_ids.add(race_id)
            if placement.race_finish is not None:
                goal_id = race_link_id(obj, placement.race_finish, "goal_ring", scene)
                if goal_id in race_finish_ids:
                    raise ValueError(f"{placement.race_finish.name} is assigned to two Race Starts.")
                race_finish_ids.add(goal_id)
                record["race_links"] = {"goal": goal_id}
                goal_start = placement.race_finish.sonic_vane_placement.race_start_link
                if goal_start is not None and goal_start != obj:
                    raise ValueError(f"{placement.race_finish.name} is linked to a different Race Start.")
        if placement.kind in {"goal_ring", "collection_item"} and placement.race_start_link is not None:
            target = placement.race_start_link
            record["race_links"] = {"start": race_link_id(obj, target, "race_start", scene)}
            if placement.kind == "collection_item" and target.sonic_vane_placement.race_start_race_type != "collection":
                raise ValueError(f"{obj.name} needs a Collection Race start.")
        if placement.kind == "camera_constraint" and (error := camera_preview.influence_error(placement)):
            raise ValueError(f"{obj.name}: {error}")
        if placement.kind == "camera_constraint" and placement.camera_activation_mode == "entry_gate":
            gates = {}
            for role in camera_preview.active_gates(placement):
                gate = camera_preview.gate_for(obj, role)
                if not gate or scene.objects.get(gate.name) != gate:
                    raise ValueError(f"{obj.name} needs a {role} box. Re-select Entry Gate to restore missing boxes.")
                local = world.inverted() @ gate.evaluated_get(depsgraph).matrix_world
                gates[role] = export_local_box(gate, local)
            record["camera_gates"] = gates
        if placement.kind == "rail_booster":
            rail = placement.booster_rail
            if not rail or scene.objects.get(rail.name) != rail or not booster_preview.rail_poll(placement, rail):
                raise ValueError(f"{obj.name} needs a rail from the current scene.")
            try:
                rail_id = str(uuid.UUID(rail.sonic_vane_placement.placement_id))
            except ValueError as exc:
                raise ValueError(f"{obj.name} targets a rail that needs a placement UUID.") from exc
            record["attachment"] = {"rail_id": rail_id, "fraction": placement.booster_position / 100}
        records.append(record)

    records.sort(key=lambda record: record["id"])
    document = {"schema_version": CATALOG["schema_version"], "level_id": level_id, "placements": records}
    defaults = {}
    for family, standard in DEFAULT_VARIANTS.items():
        variant = getattr(scene, f"sonic_vane_{family}_default")
        if variant != standard:
            defaults[family] = variant
    if defaults:
        document["variant_defaults"] = defaults
    if environment:
        document["environment"] = environment
    return document


def export_environment(settings):
    environment = {
        key: getattr(settings, key) for key in ENVIRONMENT_FIELDS
        if key != "allowed_weather" and getattr(settings, f"override_{key}")
    }
    if environment.get("start_time_mode") == "random":
        environment.pop("start_hour", None)
    for key in ("time_channel", "weather_channel"):
        if key in environment:
            channel = environment[key].strip()
            if not ENVIRONMENT_CHANNEL_PATTERN.fullmatch(channel):
                raise ValueError(f"{ENVIRONMENT_FIELDS[key]['label']} must use letters, digits, or underscores.")
            environment[key] = channel
    if settings.override_allowed_weather:
        allowed = [key for key, enabled in zip(WEATHER_PRESETS, settings.allowed_weather) if enabled]
        if not allowed:
            raise ValueError("Select at least one allowed weather preset.")
        if environment.get("dynamic_weather") and len(allowed) < 2:
            raise ValueError("Dynamic weather needs at least two allowed presets.")
        if environment.get("starting_weather", "random") not in ["random", *allowed]:
            raise ValueError("Starting Weather must be one of the allowed presets.")
        environment["allowed_weather"] = allowed
    return environment


def export_teleporter_link(obj, placement, scene):
    if placement.teleporter_link_mode == "level":
        level_id = placement.teleporter_level_id.strip()
        if not LEVEL_ID_PATTERN.fullmatch(level_id) or level_id == scene.sonic_vane_level_id:
            raise ValueError(f"{obj.name} needs a different destination level ID.")
        link = {"level_id": level_id}
        exit_id = placement.teleporter_level_exit_id.strip()
        if exit_id:
            try:
                link["exit"] = str(uuid.UUID(exit_id))
            except ValueError as exc:
                raise ValueError(f"{obj.name} has an invalid destination UUID.") from exc
        return link
    target = placement.teleporter_destination
    if not target or scene.objects.get(target.name) != target or target.sonic_vane_placement.kind != "teleporter_exit":
        raise ValueError(f"{obj.name} needs a Teleporter Exit in the current scene.")
    exit_id = canonical_placement_id(target.sonic_vane_placement)
    if not exit_id:
        raise ValueError(f"{target.name} needs a placement UUID.")
    return {"exit": exit_id}


def race_link_id(obj, target, kind, scene):
    if scene.objects.get(target.name) != target or target.sonic_vane_placement.kind != kind:
        raise ValueError(f"{obj.name} needs a {CATALOG['types'][kind]['label']} from the current scene.")
    placement_id = canonical_placement_id(target.sonic_vane_placement)
    if not placement_id:
        raise ValueError(f"{target.name} needs a placement UUID.")
    return placement_id


def export_automation_triggers(obj, placement, record):
    mode = placement.automation_activation
    if record["curve"]["closed"] and mode in {"endpoints", "area_crossings"}:
        raise ValueError(f"{obj.name} needs Occupancy or Script Only activation for a closed route.")
    roles = automation_preview.ROLES.get(mode, ())
    if placement.automation_trigger_layout != "custom" or not roles:
        return
    boxes = {}
    for role in roles:
        child = automation_preview.box_for(obj, role)
        if child is None:
            raise ValueError(f"{obj.name} needs a custom {role} box. Switch to Follow Spline and back to recreate it.")
        boxes[role] = export_local_box(child, obj.matrix_world.inverted() @ child.matrix_world)
    record["activation_boxes"] = boxes


def export_local_box(child, local):
    size = local.to_scale()
    rotation = local.to_quaternion().normalized()
    basis = local.to_3x3()
    expected = rotation.to_matrix()
    coordinates = (*local.translation, *size, *rotation)
    if (not all(math.isfinite(n) for n in coordinates) or min(size) < 0.1 or any(n <= 0 for n in child.scale)
            or any(abs(basis[i][j] - expected[i][j] * size[j]) > 0.001 for i in range(3) for j in range(3))):
        raise ValueError(f"{child.name} needs positive dimensions of at least 0.1 m and no shear.")
    engine_rotation = (Y_UP @ expected @ Y_UP.transposed()).to_quaternion().normalized()
    return {
        "position": list(Y_UP @ local.translation),
        "rotation": (engine_rotation.x, engine_rotation.y, engine_rotation.z, engine_rotation.w),
        "size": (size.x, size.z, size.y),
    }


def export_automation_extensions(obj, scene):
    records = []
    for extension in obj.sonic_vane_placement.automation_extensions:
        values = {key: getattr(extension, key) for key in AUTOMATION_EXTENSIONS[extension.kind]}
        record = {"kind": extension.kind, "properties": values}
        if extension.kind == "junction":
            target = extension.destination
            if not target or target == obj or scene.objects.get(target.name) != target:
                raise ValueError(f"{obj.name} needs a distinct junction destination in the current scene.")
            target_id = canonical_placement_id(target.sonic_vane_placement)
            if target.sonic_vane_placement.kind != "automation_spline" or not target_id:
                raise ValueError(f"{obj.name} has a junction destination without an automation UUID.")
            record["destination"] = target_id
        elif not values["event_id"].strip():
            raise ValueError(f"{obj.name} has a progress event without an ID.")
        records.append(record)
    return records


def write_placements(path, scene, depsgraph):
    document = build_placement_document(scene, depsgraph)
    content = json.dumps(document, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    destination = Path(path)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", dir=destination.parent, delete=False
        ) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        temporary.replace(destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return len(document["placements"])


def placement_filepath(filepath):
    filename = os.path.basename(filepath)
    if not filename or filename in {".", ".."}:
        return filepath
    stem = PLACEMENT_SUFFIX_PATTERN.sub("", filename)
    return filepath[:-len(filename)] + stem + PLACEMENT_SUFFIX


def sync_rail_preview(placement, _context):
    obj = placement.id_data
    if placement.kind != "rail" or obj.type != "CURVE" or not obj.is_editable:
        return
    variant = RAIL_VARIANTS[placement.rail_variant]
    group_name = variant["preview_group"]
    modifier = obj.modifiers.get("Rail Preview")
    if modifier is not None and modifier.type != "NODES":
        return
    if modifier is not None and modifier.node_group:
        group = modifier.node_group
        if group.get(RAIL_VARIANT_KEY, group.name) == group_name:
            return
    group = next((group for group in bpy.data.node_groups
                  if group.get(RAIL_VARIANT_KEY, group.name) == group_name), None)
    if group is None:
        with bpy.data.libraries.load(str(ASSET_DIRECTORY / variant["asset"])) as (_, imported):
            imported.node_groups = [group_name]
        group = imported.node_groups[0]
        group[RAIL_VARIANT_KEY] = group_name
    if modifier is None:
        modifier = obj.modifiers.new("Rail Preview", "NODES")
    modifier.node_group = group


def sync_ring_preview(placement, context, scene=None):
    obj = placement.id_data
    if not obj.is_editable or placement.kind not in RING_KINDS:
        return
    variant = effective_variant(placement, "ring", scene if scene else (context or bpy.context).scene)
    if placement.kind == "ring" and obj.type == "MESH":
        mesh = model_preview.load_mesh(ASSET_DIRECTORY, variant, RING_VARIANTS[variant])
        if mesh is None:
            mesh = model_preview.load_mesh(ASSET_DIRECTORY, STANDARD_RING, RING_VARIANTS[STANDARD_RING])
        if mesh is not None and obj.data != mesh:
            obj.data = mesh
    elif placement.kind == "ring_spline" and obj.type == "CURVE":
        sync_ring_trail_preview(placement, variant)


def sync_level_ring_default(scene, _context):
    for obj in scene.objects:
        if obj.sonic_vane_placement.kind in RING_KINDS:
            sync_ring_preview(obj.sonic_vane_placement, None, scene)


def update_ring_preview(placement, context):
    sync_ring_preview(placement, context)


def sync_ring_trail_preview(placement, variant):
    obj = placement.id_data
    modifier = obj.modifiers.get("Ring Trail Preview")
    if modifier is None:
        modifier = obj.modifiers.new("Ring Trail Preview", "NODES")
    if modifier.type != "NODES":
        return
    group = modifier.node_group
    if not group or group.get(ring_preview.VARIANT_KEY):
        group = bpy.data.node_groups.get(RING_TRAIL_GROUP)
        if group is None:
            with bpy.data.libraries.load(str(ASSET_DIRECTORY / "Traversal Objects.blend")) as (_, imported):
                imported.node_groups = [RING_TRAIL_GROUP]
            group = imported.node_groups[0]
    if variant != STANDARD_RING:
        mesh = model_preview.load_mesh(ASSET_DIRECTORY, variant, RING_VARIANTS[variant])
        if mesh is not None:
            group = ring_preview.trail_group(group, variant, mesh)
    if modifier.node_group != group:
        modifier.node_group = group
    set_preview_input(obj, modifier, "Ring Spacing", placement.ring_spacing)


def set_preview_input(obj, modifier, name, value):
    for socket in modifier.node_group.interface.items_tree:
        if socket.item_type == "SOCKET" and socket.in_out == "INPUT" and socket.name == name:
            if hasattr(modifier, "properties"):
                getattr(modifier.properties.inputs, socket.identifier).value = value
            else:
                modifier[socket.identifier] = value
            obj.update_tag()
            break


def sync_checkpoint_width(placement, _context):
    obj = placement.id_data
    if placement.kind != "checkpoint" or obj.type != "MESH" or not obj.is_editable:
        return
    modifier = obj.modifiers.get("Checkpoint Width")
    if modifier and modifier.type == "NODES" and modifier.node_group:
        set_preview_input(obj, modifier, "Width", placement.checkpoint_width)


def sync_monitor_preview(placement, _context):
    obj = placement.id_data
    if placement.kind != "item_monitor" or obj.type != "MESH" or not obj.is_editable:
        return
    style = placement.monitor_style
    mesh = next((mesh for mesh in bpy.data.meshes if mesh.get(MONITOR_STYLE_KEY) == style), None)
    if mesh is None:
        option = MONITOR_STYLES[style]
        with bpy.data.libraries.load(str(ASSET_DIRECTORY / option.get("preview_file", "Item Monitors.blend"))) as (_, imported):
            imported.meshes = [option["preview_mesh"]]
        mesh = imported.meshes[0]
    obj.data = mesh
    for index, material in enumerate(mesh.materials):
        role = material.get(MONITOR_MATERIAL_KEY) if material else None
        if role:
            mesh.materials[index] = next(
                entry for entry in bpy.data.materials if entry.get(MONITOR_MATERIAL_KEY) == role
            )
    obj.delta_scale = (placement.size,) * 3


def sync_spring_preview(placement, _context):
    obj = placement.id_data
    if placement.kind != "spring" or obj.type != "MESH" or not obj.is_editable:
        return
    style = placement.spring_style
    current_style = obj.data.get(SPRING_STYLE_KEY, "standard")
    if current_style == style:
        return
    if style == "standard" and placement.spring_original_mesh:
        obj.data = placement.spring_original_mesh
        placement.spring_original_mesh = None
        return
    if current_style == "standard":
        placement.spring_original_mesh = obj.data
    definition = SPRING_STYLES[style]
    mesh = next((item for item in bpy.data.meshes if item.get(SPRING_STYLE_KEY) == style), None)
    if mesh is None:
        with bpy.data.libraries.load(str(ASSET_DIRECTORY / definition["asset"])) as (_, imported):
            imported.meshes = [definition["preview_mesh"]]
        mesh = imported.meshes[0]
        mesh[SPRING_STYLE_KEY] = style
    obj.data = mesh


def sync_spring_style(placement, context):
    sync_spring_preview(placement, context)
    spring_preview.sync_model(placement, context)


def sync_dash_panel_size(placement, _context):
    obj = placement.id_data
    if placement.kind == "dash_panel" and obj.type == "MESH" and obj.is_editable:
        obj.delta_scale = (placement.size,) * 3


def sync_size_preview(placement, context):
    sync_monitor_preview(placement, context)
    sync_dash_panel_size(placement, context)
    update_enemy_hazard_preview(placement, context)
    obj = placement.id_data
    if placement.kind == "ramp" and obj.type == "MESH" and obj.is_editable:
        obj.delta_scale = (placement.size,) * 3


def sync_vault_preview(placement, _context):
    obj = placement.id_data
    if placement.kind != "vault_bar" or not obj.is_editable:
        return
    modifier = obj.modifiers.get("Vault Bar Dimensions")
    if modifier and modifier.type == "NODES" and modifier.node_group:
        set_preview_input(obj, modifier, "Length", placement.bar_length)
        set_preview_input(obj, modifier, "Radius", placement.bar_radius)


def update_enemy_hazard_preview(placement, context):
    sync_enemy_hazard_preview(placement, (context or bpy.context).scene)


def sync_enemy_hazard_preview(placement, scene):
    obj = placement.id_data
    kind = placement.kind
    if kind not in SIZED_HAZARD_KINDS or obj.type != "MESH" or not obj.is_editable:
        return
    obj.delta_scale = (placement.size,) * 3
    if kind == "enemy":
        variant = effective_variant(placement, "enemy", scene)
        variants = VARIANTS["enemy"]
        mesh = model_preview.load_mesh(ASSET_DIRECTORY, variant, variants[variant])
        if mesh is None:
            mesh = model_preview.load_mesh(ASSET_DIRECTORY, STANDARD_ENEMY, variants[STANDARD_ENEMY])
    else:
        name = "Spike Ball"
        if kind == "spike_strip":
            pose = "Raised" if placement.start_raised else "Retracted"
            name = f"Spike Strip {pose}" + (" No Plate" if placement.hide_base_plate else "")
        mesh = model_preview.load_mesh(
            ASSET_DIRECTORY, name, {"preview_file": ENEMY_HAZARD_LIBRARY, "preview_mesh": name}
        )
    if mesh is not None and obj.data != mesh:
        obj.data = mesh

    if kind == "spike_strip" and placement.hide_base_plate:
        model_preview.set_rotation(obj, "Spike Strip Offset", (0, 0, 0), (0, 0, -placement.hidden_base_offset))
    else:
        model_preview.set_rotation(obj, "Spike Strip Offset", None)


def sync_level_enemy_default(scene, _context):
    for obj in scene.objects:
        if obj.sonic_vane_placement.kind == "enemy":
            sync_enemy_hazard_preview(obj.sonic_vane_placement, scene)


def item_variant_default(key):
    def get(placement, value, is_set):
        if is_set:
            return value
        if placement.kind == "spring":
            return SPRING_STYLES[placement.spring_style].get("bool_defaults", {}).get(key, value)
        if placement.kind == "item_monitor" and placement.monitor_style == "balloon":
            return key == "allow_player_pass_through"
        return value

    return get


@persistent
def cleanup_monitor_previews(*_):
    for collection, key in (
        (bpy.data.meshes, MONITOR_STYLE_KEY),
        (bpy.data.materials, MONITOR_MATERIAL_KEY),
        (bpy.data.images, MONITOR_TEXTURE_KEY),
    ):
        unused = [item for item in collection if item.get(key) and not item.users]
        if unused:
            bpy.data.batch_remove(ids=unused)


def sync_volume_preview(placement, _context):
    obj = placement.id_data
    kind = placement.kind
    if kind not in VOLUME_PREVIEWS or not obj.is_editable or obj.type != "MESH":
        return
    if kind == "adventure_water":
        name = "Water " + placement.water_geometry.title()
        scale = placement.water_dimensions
        offset = placement.surface_y_offset / scale.z
        model_preview.set_rotation(obj, "Water Surface Offset", (0, 0, 0) if offset else None, (0, 0, offset))
    elif kind == "flipper":
        name = placement.flipper_side.title() + " Flipper"
        scale = (1, 1, 1)
    elif kind == "death_plane":
        name = "Death Plane"
        scale = placement.death_plane_dimensions
    elif kind == "teleporter_entrance":
        name = "Teleporter Entrance"
        scale = (2 * placement.teleporter_radius,) * 3
    else:
        name = "Teleporter Exit"
        scale = (1, 1, 1)
    mesh = model_preview.load_mesh(
        ASSET_DIRECTORY, name, {"preview_file": VOLUME_LIBRARY, "preview_mesh": name}
    )
    if mesh and obj.data != mesh:
        obj.data = mesh
    if tuple(obj.delta_scale) != tuple(scale):
        obj.delta_scale = scale
    obj.display_type = "TEXTURED" if kind == "flipper" else "WIRE"


def sync_planetary_preview(placement, _context):
    obj = placement.id_data
    if placement.kind != "planetary_gravity" or not obj.is_editable or obj.type != "MESH":
        return
    modifier = obj.modifiers.get(PLANETARY_GROUP)
    if not modifier:
        group = bpy.data.node_groups.get(PLANETARY_GROUP)
        path = ASSET_DIRECTORY / PLANETARY_LIBRARY
        if group is None and path.is_file():
            with bpy.data.libraries.load(str(path)) as (available, imported):
                if PLANETARY_GROUP in available.node_groups:
                    imported.node_groups = [PLANETARY_GROUP]
            if imported.node_groups:
                group = imported.node_groups[0]
        if group is None:
            return
        modifier = obj.modifiers.new(PLANETARY_GROUP, "NODES")
        modifier.node_group = group
    if modifier.type != "NODES" or not modifier.node_group:
        return
    obj.display_type = "WIRE"
    for key, name in PLANETARY_PREVIEW_INPUTS.items():
        set_preview_input(obj, modifier, name, getattr(placement, key))


def update_placement_kind(placement, context):
    if placement.kind != "spike_strip" and placement.id_data.is_editable:
        model_preview.set_rotation(placement.id_data, "Spike Strip Offset", None)
    sync_placement_markers(placement, context)
    if placement.kind == "camera_constraint" or any(child.get(camera_preview.GATE_ROLE) for child in placement.id_data.children):
        camera_preview.sync_gates(placement)
    if placement.kind == "camera_constraint" or camera_preview.path_for(placement.id_data):
        camera_preview.sync_path(placement)
    automation_preview.sync_custom_boxes(placement, context)
    sync_ring_preview(placement, context)
    sync_checkpoint_width(placement, context)
    sync_size_preview(placement, context)
    sync_vault_preview(placement, context)
    sync_spring_preview(placement, context)
    dash_preview.sync_model(placement)
    booster_preview.sync_preview(placement)
    if placement.kind != "adventure_water" and placement.id_data.is_editable:
        model_preview.set_rotation(placement.id_data, "Water Surface Offset", None)
    sync_volume_preview(placement, context)
    if placement.kind == "planetary_gravity":
        sync_planetary_preview(placement, context)
    elif placement.id_data.is_editable:
        modifier = placement.id_data.modifiers.get(PLANETARY_GROUP)
        if modifier and modifier.type == "NODES" and modifier.node_group and modifier.node_group.get("sonic_vane_planetary_preview"):
            placement.id_data.modifiers.remove(modifier)


def placement_property(key, field):
    settings = {"name": field["label"], "description": field["description"], "default": field["default"]}
    if key in {"sky_profile", "starting_weather"}:
        settings["update"] = environment_preview.redraw_viewports
    if field["type"] == "string":
        return StringProperty(**settings)
    if field["type"] == "physics_mask":
        settings["default"] = tuple(bool(field["default"] & (1 << index)) for index in range(32))
        return BoolVectorProperty(size=32, **settings)
    if field["type"] == "axis_mask":
        indices = (0, 1, 2) if "axis_labels" in field else (0, 2, 1)
        settings["default"] = tuple(bool(field["default"] & (1 << index)) for index in indices)
        return BoolVectorProperty(size=3, **settings)
    if key in PLANETARY_PREVIEW_INPUTS or key == "planetary_preset":
        settings["update"] = sync_planetary_preview
    if "planet_defaults" in field:
        if bpy.app.version >= (5, 1, 0):
            settings["get_transform"] = planetary_property_default(field)
        else:
            settings["get"], settings["set"] = legacy_planetary_property(key, field)
    if "variant_defaults" in field and bpy.app.version >= (5, 1, 0):
        settings["get_transform"] = enemy_property_default(field)
    if "preset_defaults" in field and bpy.app.version >= (5, 1, 0):
        settings["get_transform"] = automation_property_default(field)
    if field["type"] == "bool":
        if key == "dash_additive_launch":
            return BoolProperty(
                name=field["label"], description=field["description"],
                get=lambda placement: not placement.stop_momentum,
                set=lambda placement, value: setattr(placement, "stop_momentum", not value),
            )
        if key in MARKER_CONTROLS:
            settings["update"] = sync_placement_markers
        if key == "camera_override_position":
            settings["update"] = update_camera_position
        if key in {"camera_exit_gate_enabled", "camera_rearm_gate_enabled"}:
            settings["update"] = update_camera_activation
        if key in SPRING_VARIANT_BOOLS | {"homing_target_enabled", "allow_player_pass_through"} and bpy.app.version >= (5, 1, 0):
            settings["get_transform"] = item_variant_default(key)
        if key == "trajectory_arc_enabled":
            settings["update"] = spring_preview.sync_model
        if key in {"start_raised", "hide_base_plate"}:
            settings["update"] = update_enemy_hazard_preview
        return BoolProperty(**settings)
    if field["type"] == "enum":
        items = [(key, option["label"], "", option["value"]) for key, option in field["options"].items()]
        if key in {"automation_trigger_layout", "automation_activation"}:
            settings["update"] = automation_preview.sync_custom_boxes
        if key == "camera_activation_mode":
            settings["update"] = update_camera_activation
        if key == "camera_position_mode":
            settings["update"] = update_camera_position
        if key in {"camera_distance_reference", "camera_aim_mode", "camera_influence_center"}:
            settings["update"] = sync_placement_markers
        if key == "rail_variant":
            settings["update"] = sync_rail_preview
        if key == "monitor_style":
            settings["update"] = sync_monitor_preview
        if key == "spring_style":
            settings["update"] = sync_spring_style
        if key == "dash_launch_axis":
            settings["update"] = dash_preview.sync_model
        if key in {"water_geometry", "flipper_side"}:
            settings["update"] = sync_volume_preview
        if key in {"launch_axis", "trajectory_arc_up_mode"}:
            settings["update"] = spring_preview.sync_model
        return EnumProperty(items=items, **settings)
    if field["type"] == "local_offset":
        settings["default"] = Y_UP.transposed() @ Vector(field["default"])
        settings["update"] = update_marker_offset(key)
        return FloatVectorProperty(size=3, subtype="TRANSLATION", unit="LENGTH", **settings)
    if field["type"] == "local_vector":
        settings["default"] = Y_UP.transposed() @ Vector(field["default"])
        return FloatVectorProperty(size=3, subtype="XYZ", **settings)
    if field["type"] == "local_dimensions":
        x, y, z = field["default"]
        settings["default"] = (x, z, y)
        return FloatVectorProperty(size=3, subtype="XYZ", unit="LENGTH", min=field["min"],
                                   update=sync_volume_preview, **settings)
    if field["type"] == "color":
        return FloatVectorProperty(size=4, subtype="COLOR", min=0, max=1, **settings)
    settings["min"] = field["min"]
    if "max" in field:
        settings["max"] = field["max"]
    if field["type"] == "int":
        if key == "ring_value" and bpy.app.version >= (5, 1, 0):
            settings["get_transform"] = ring_value_default
        return IntProperty(**settings)
    if key == "ring_spacing":
        settings["update"] = update_ring_preview
        settings["unit"] = "LENGTH"
    if key == "size":
        settings["update"] = sync_size_preview
    if key == "trajectory_arc_height":
        settings["update"] = spring_preview.sync_model
    if key == "checkpoint_width":
        settings["update"] = sync_checkpoint_width
    if key == "hidden_base_offset":
        settings["update"] = update_enemy_hazard_preview
    if key in {"bar_length", "bar_radius"}:
        settings["update"] = sync_vault_preview
        settings["unit"] = "LENGTH"
    if key in {"surface_y_offset", "teleporter_radius"}:
        settings["update"] = sync_volume_preview
        settings["unit"] = "LENGTH"
    if key in {"planetary_radius", "planetary_surface_radius", "planetary_reference_distance", "planetary_surface_extra"}:
        settings["unit"] = "LENGTH"
    if key in {"camera_exit_distance", "camera_orbit_distance", "camera_influence_full", "camera_influence_zero"}:
        settings["unit"] = "LENGTH"
    if key in {"checkpoint_width", "trigger_width", "trigger_height", "trigger_depth",
               "hidden_base_offset", "collision_radius", "damage_contact_margin"}:
        settings["unit"] = "LENGTH"
    return FloatProperty(**settings)


def update_camera_activation(placement, context):
    camera_preview.sync_gates(placement)
    sync_placement_markers(placement, context)


def update_camera_position(placement, context):
    camera_preview.sync_path(placement)
    sync_placement_markers(placement, context)


def ring_value_default(placement, value, is_set):
    if is_set or placement.kind != "ring":
        return value
    variant = effective_variant(placement, "ring", bpy.context.scene)
    return RING_VARIANTS[variant].get("ring_value", value)


def enemy_property_default(field):
    def get(placement, value, is_set):
        if is_set or placement.kind != "enemy":
            return value
        variant = effective_variant(placement, "enemy", bpy.context.scene)
        return field["variant_defaults"].get(variant, value)

    return get


def automation_property_default(field):
    def get(placement, value, is_set):
        return value if is_set else field["preset_defaults"].get(placement.automation_preset, value)

    return get


def planetary_property_default(field):
    def get(placement, value, is_set):
        return value if is_set else field["planet_defaults"].get(placement.planetary_preset, value)

    return get


def legacy_planetary_property(key, field):
    def get(placement):
        return placement.get(key, field["planet_defaults"].get(placement.planetary_preset, field["default"]))

    def set_value(placement, value):
        placement[key] = value

    return get, set_value


def canonical_placement_id(placement):
    if placement.kind != "NONE":
        try:
            return str(uuid.UUID(placement.placement_id.strip()))
        except ValueError:
            pass
    return None


def scene_placement_ids(scene):
    return {key for obj in scene.objects if (key := canonical_placement_id(obj.sonic_vane_placement))}


def reserve_placement_id(used):
    placement_id = str(uuid.uuid4())
    while placement_id in used:
        placement_id = str(uuid.uuid4())
    used.add(placement_id)
    return placement_id


@persistent
def pause_object_tracking(*_):
    global tracking_new_objects
    tracking_new_objects = False


@persistent
def reset_object_tracking(*_):
    global tracking_new_objects
    known_object_ids.clear()
    known_object_ids.update(obj.session_uid for obj in bpy.data.objects)
    tracking_new_objects = True


@persistent
def assign_duplicate_placement_ids(_scene, depsgraph):
    if not tracking_new_objects or not depsgraph.id_type_updated("OBJECT"):
        return
    if len(known_object_ids) == len(bpy.data.objects) and not any(
        isinstance(update.id, bpy.types.Object) and update.id.original.session_uid not in known_object_ids
        for update in depsgraph.updates
    ):
        return
    current_ids = set()
    existing = set()
    marker_sources = {}
    new_placements = []
    for obj in bpy.data.objects:
        current_ids.add(obj.session_uid)
        if obj.session_uid not in known_object_ids and obj.is_editable and obj.get(SURFACE_TARGET_KEY):
            obj[SURFACE_TARGET_KEY] = str(uuid.uuid4())
        placement = obj.sonic_vane_placement
        if placement.kind == "NONE":
            continue
        key = canonical_placement_id(placement)
        if obj.session_uid in known_object_ids or not obj.is_editable:
            if key:
                existing.add(key)
                if placement.kind in {"automation_spline", "camera_constraint", "goal_ring"} or placement.kind in objective_preview.VOLUME_COLORS:
                    marker_sources.setdefault((key, placement.kind), obj)
        else:
            new_placements.append((placement, key))
    known_object_ids.clear()
    known_object_ids.update(current_ids)
    used = existing | {key for _, key in new_placements if key}
    for placement, key in new_placements:
        if not key or key in existing:
            placement.placement_id = reserve_placement_id(used)
        else:
            existing.add(key)
        if placement.kind == "automation_spline":
            automation_preview.copy_custom_boxes(placement.id_data, marker_sources.get((key, placement.kind)))
        elif placement.kind == "camera_constraint":
            obj = placement.id_data
            source = marker_sources.get((key, placement.kind))
            camera_preview.copy_helpers(obj, source)
            sync_placement_markers(placement, None)
        elif placement.kind == "goal_ring":
            obj = placement.id_data
            source = marker_sources.get((key, placement.kind))
            if source:
                for field in ("goal_ring_pose", "goal_ring_camera_point"):
                    original = placement_marker(source, field)
                    if original is not None and not placement_marker(obj, field):
                        duplicate = original.copy()
                        duplicate.parent = obj
                        for collection in obj.users_collection:
                            if collection.is_editable:
                                collection.objects.link(duplicate)
            sync_placement_markers(placement, None)
        elif placement.kind in objective_preview.VOLUME_COLORS:
            obj = placement.id_data
            source = marker_sources.get((key, placement.kind))
            if source and not objective_preview.volume_boxes(obj):
                for box in objective_preview.volume_boxes(source):
                    duplicate = box.copy()
                    duplicate.parent = obj
                    for collection in obj.users_collection:
                        if collection.is_editable:
                            collection.objects.link(duplicate)


OBJECT_TRACKING_HANDLERS = (
    (bpy.app.handlers.load_pre, pause_object_tracking),
    (bpy.app.handlers.load_post, reset_object_tracking),
    (bpy.app.handlers.undo_pre, pause_object_tracking),
    (bpy.app.handlers.undo_post, reset_object_tracking),
    (bpy.app.handlers.redo_pre, pause_object_tracking),
    (bpy.app.handlers.redo_post, reset_object_tracking),
    (bpy.app.handlers.depsgraph_update_post, assign_duplicate_placement_ids),
)


@persistent
def initialize_appended_gameplay_assets(import_context):
    scene = bpy.context.scene
    if scene is None:
        return
    used = None
    for item in import_context.import_items:
        if item.id_type != "OBJECT" or item.append_action not in {"MAKE_LOCAL", "COPY_LOCAL"}:
            continue
        obj = item.id
        if obj is None or not obj.is_editable or scene.objects.get(obj.name) != obj:
            continue
        if obj.get(RAIL_SEGMENT_KEY) or obj.get(PREVIEW_SOURCE_KEY):
            for collection in tuple(obj.users_collection):
                if collection.is_editable:
                    collection.objects.unlink(obj)
            continue
        kind = obj.get(ASSET_TYPE_KEY)
        if not isinstance(kind, str) or kind not in CATALOG["types"]:
            continue

        placement = obj.sonic_vane_placement
        if kind == "flipper" and obj.get("sonic_vane_flipper_side") == "right":
            placement.flipper_side = "right"
            del obj["sonic_vane_flipper_side"]
        if kind == "planetary_gravity" and obj.get("sonic_vane_planetary_preset") == "strong":
            placement.planetary_preset = "strong"
            del obj["sonic_vane_planetary_preset"]
        family = variant_family(kind)
        if family in VARIANTS:
            variant = obj.get(model_preview.VARIANT_KEY)
            if variant in VARIANTS[family]:
                setattr(placement, f"{family}_variant", variant)
                del obj[model_preview.VARIANT_KEY]
            if obj.type == "MESH":
                obj.data[model_preview.VARIANT_KEY] = variant or DEFAULT_VARIANTS[family]
        if kind == "item_monitor":
            style = obj.get(MONITOR_STYLE_KEY)
            if isinstance(style, str) and style in MONITOR_STYLES:
                placement.monitor_style = style
                del obj[MONITOR_STYLE_KEY]
        if kind == "spring":
            style = obj.get(SPRING_STYLE_KEY)
            if isinstance(style, str) and style in SPRING_STYLES:
                placement.spring_style = style
                del obj[SPRING_STYLE_KEY]
        placement.kind = kind
        if kind == "rail":
            variant = obj.get(RAIL_VARIANT_KEY)
            if isinstance(variant, str) and variant in RAIL_VARIANTS:
                placement.rail_variant = variant
                del obj[RAIL_VARIANT_KEY]
        if not placement.placement_id.strip():
            if used is None:
                used = scene_placement_ids(scene)
            placement.placement_id = reserve_placement_id(used)
        del obj[ASSET_TYPE_KEY]

        gameplay = scene.collection.children.get(GAMEPLAY_COLLECTION_NAME)
        if gameplay is None:
            gameplay = bpy.data.collections.new(GAMEPLAY_COLLECTION_NAME)
            scene.collection.children.link(gameplay)
        previous_collections = tuple(obj.users_collection)
        if gameplay.objects.get(obj.name) is None:
            gameplay.objects.link(obj)
        for collection in previous_collections:
            if collection != gameplay and collection.is_editable:
                collection.objects.unlink(obj)
        if kind in {"camera_constraint", "goal_ring"}:
            for point in obj.children:
                if not point.get(MARKER_FIELD_KEY):
                    continue
                previous_collections = tuple(point.users_collection)
                if gameplay.objects.get(point.name) is None:
                    gameplay.objects.link(point)
                for collection in previous_collections:
                    if collection != gameplay and collection.is_editable:
                        collection.objects.unlink(point)


class SonicVaneAutomationExtension(PropertyGroup):
    kind: EnumProperty(items=(("junction", "Junction", ""), ("event", "Progress Event", "")))
    destination: PointerProperty(
        name="Destination", description="Route to transfer to at this junction", type=bpy.types.Object,
        poll=lambda self, obj: obj != self.id_data and obj.sonic_vane_placement.kind == "automation_spline",
    )


SonicVaneAutomationExtension.__annotations__.update({
    key: placement_property(key, field)
    for fields in AUTOMATION_EXTENSIONS.values() for key, field in fields.items()
})


class SonicVaneSurfaceTarget(PropertyGroup):
    target: PointerProperty(type=bpy.types.Object)


class SonicVanePlacement(PropertyGroup):
    kind: EnumProperty(
        name="Type",
        description="Gameplay object exported for this Blender object",
        items=(
            ("NONE", "None", "Omit this object from the placement JSON", 0),
            ("spring", CATALOG["types"]["spring"]["label"], "Place a Sonic Vane spring", 1),
            ("rail", CATALOG["types"]["rail"]["label"], "Place a Sonic Vane grind rail", 2),
            ("ring", CATALOG["types"]["ring"]["label"], "Place an individual ring", 3),
            ("ring_spline", CATALOG["types"]["ring_spline"]["label"], "Place rings along a Bézier curve", 4),
            ("rail_booster", CATALOG["types"]["rail_booster"]["label"], "Place a boost along a grind rail", 5),
            ("item_monitor", CATALOG["types"]["item_monitor"]["label"], "Place a reward monitor", 6),
            ("dash_panel", CATALOG["types"]["dash_panel"]["label"], "Place a directional dash panel", 7),
            ("checkpoint", CATALOG["types"]["checkpoint"]["label"], "Place a checkpoint gate", 8),
            ("enemy", CATALOG["types"]["enemy"]["label"], "Place an enemy", 9),
            ("spike_strip", CATALOG["types"]["spike_strip"]["label"], "Place a timed spike strip", 10),
            ("spike_ball", CATALOG["types"]["spike_ball"]["label"], "Place a spike ball hazard", 11),
            ("player_spawn", CATALOG["types"]["player_spawn"]["label"], "Set the level's starting position and facing", 12),
            ("ramp", CATALOG["types"]["ramp"]["label"], "Place a jump-panel ramp", 13),
            ("bumper", CATALOG["types"]["bumper"]["label"], "Place a pinball bumper", 14),
            ("vault_bar", CATALOG["types"]["vault_bar"]["label"], "Place a swing and launch bar", 15),
            ("automation_spline", CATALOG["types"]["automation_spline"]["label"], "Place a guided movement route", 16),
            ("adventure_water", CATALOG["types"]["adventure_water"]["label"], "Place a runnable Adventure water volume", 17),
            ("flipper", CATALOG["types"]["flipper"]["label"], "Place a pinball flipper", 18),
            ("death_plane", CATALOG["types"]["death_plane"]["label"], "Place a death trigger", 19),
            ("teleporter_entrance", CATALOG["types"]["teleporter_entrance"]["label"], "Place a teleporter trigger", 20),
            ("teleporter_exit", CATALOG["types"]["teleporter_exit"]["label"], "Place a teleporter destination", 21),
            ("planetary_gravity", CATALOG["types"]["planetary_gravity"]["label"], "Place a radial gravity field or planet", 22),
            ("camera_constraint", CATALOG["types"]["camera_constraint"]["label"], "Place a camera shot with a volume or gate", 23),
            ("goal_ring", "Goal Ring", "Place a race finish ring", 24),
            ("collection_item", "Emerald Shard", "Place a collection race pickup", 25),
            ("race_start", "Race Start", "Place a race start and countdown", 26),
            ("homing_target", "Homing Target", "Place a target for homing attacks", 27),
            ("gravity_modifier", "Gravity Modifier", "Place a directional gravity trigger", 28),
            ("surface_behavior", "Surface Behavior", "Apply traits to track colliders or inside a volume", 29),
            ("rain_occluder", "Rain Occluder", "Place a box that blocks rain cover rays", 30),
            ("rain_shelter", "Rain Shelter", "Mark an interior sheltered from rain", 31),
            ("carryable_respawn", "Carryable Respawn Volume", "Return eligible carryables to their spawn", 32),
            ("environment_transition", "Environment Transition", "Blend time, weather, or sky on entry in offline play", 33),
        ),
        default="NONE",
        update=update_placement_kind,
    )
    placement_id: StringProperty(
        name="Placement UUID",
        description="Stable identity shared by all exports of this placement",
    )
    automation_extensions: CollectionProperty(type=SonicVaneAutomationExtension)
    surface_targets: CollectionProperty(type=SonicVaneSurfaceTarget)
    presentation_hidden: BoolProperty(
        name="Invisible", description="Hide the object's world visuals in game while keeping its gameplay active",
    )
    presentation_muted: BoolProperty(
        name="Inaudible", description="Mute the object's own sounds in game while keeping its gameplay active",
    )
    race_start_link: PointerProperty(
        name="Race Start", description="Race which owns this object. Empty uses Vane's native lookup",
        type=bpy.types.Object, poll=lambda _self, obj: obj.sonic_vane_placement.kind == "race_start",
    )
    race_finish: PointerProperty(
        name="Finish Goal", description="Goal Ring used to finish this race",
        type=bpy.types.Object, poll=lambda _self, obj: obj.sonic_vane_placement.kind == "goal_ring",
    )
    teleporter_link_mode: EnumProperty(
        name="Destination",
        items=(("local", "This Level", "Link to an exit in this scene"),
               ("level", "Other Level", "Load another registered level")),
    )
    teleporter_destination: PointerProperty(
        name="Exit", description="Teleporter Exit object in this scene", type=bpy.types.Object,
        poll=lambda _self, obj: obj.sonic_vane_placement.kind == "teleporter_exit",
    )
    teleporter_level_id: StringProperty(name="Level ID", description="Registered ID of the destination level")
    teleporter_level_exit_id: StringProperty(
        name="Exit UUID", description="Destination placement UUID. Leave blank to use the level spawn",
    )
    ring_variant: EnumProperty(
        name="Variant", description="Pickup appearance and behavior",
        items=VARIANT_ITEMS["ring"], default=USE_LEVEL_DEFAULT, update=update_ring_preview,
    )
    enemy_variant: EnumProperty(
        name="Variant", description="Enemy type and behavior",
        items=VARIANT_ITEMS["enemy"], default=USE_LEVEL_DEFAULT, update=update_enemy_hazard_preview,
    )
    spring_original_mesh: PointerProperty(type=bpy.types.Mesh, options={"HIDDEN"})
    booster_rail: PointerProperty(
        name="Rail", description="Grind rail this booster follows", type=bpy.types.Object,
        poll=booster_preview.rail_poll, update=booster_preview.update_preview,
    )
    booster_position: FloatProperty(
        name="Rail Position", description="Percentage of the rail length from its start to its end",
        subtype="PERCENTAGE", default=50, min=0, max=100, update=booster_preview.update_preview,
    )


SonicVanePlacement.__annotations__.update(
    {key: placement_property(key, field) for key, field in PLACEMENT_PROPERTIES.items()}
)


class SONICVANE_OT_register_asset_library(Operator):
    bl_idname = "sonic_vane.register_asset_library"
    bl_label = "Register Asset Library"
    bl_description = "Add the Sonic Vane palette to the Asset Browser"

    def execute(self, context):
        if not ASSET_DIRECTORY.is_dir():
            self.report({"ERROR"}, "The Sonic Vane asset folder is missing.")
            return {"CANCELLED"}
        libraries = context.preferences.filepaths.asset_libraries
        library = next(
            (entry for entry in libraries if Path(entry.path).resolve() == ASSET_DIRECTORY), None
        )
        if library is None:
            library = libraries.new(name=ASSET_LIBRARY_NAME, directory=str(ASSET_DIRECTORY))
        library.import_method = "APPEND"
        library.use_relative_path = False
        self.report({"INFO"}, f'Select "{library.name}" in the Asset Browser.')
        return {"FINISHED"}


class SONICVANE_OT_new_placement_id(Operator):
    bl_idname = "sonic_vane.new_placement_id"
    bl_label = "Assign New UUID"
    bl_description = "Assign a fresh identity to an intentionally new or duplicated placement"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        obj = context.object
        return bool(obj and obj.is_editable and obj.sonic_vane_placement.kind != "NONE")

    def execute(self, context):
        used = scene_placement_ids(context.scene)
        context.object.sonic_vane_placement.placement_id = reserve_placement_id(used)
        return {"FINISHED"}


class SONICVANE_OT_assign_missing_placement_ids(Operator):
    bl_idname = "sonic_vane.assign_missing_placement_ids"
    bl_label = "Assign Missing UUIDs"
    bl_description = "Assign UUIDs to marked objects without one in the current scene"
    bl_options = {"UNDO"}

    def execute(self, context):
        used = scene_placement_ids(context.scene)
        assigned = 0
        read_only = 0
        for obj in context.scene.objects:
            placement = obj.sonic_vane_placement
            if placement.kind == "NONE" or placement.placement_id.strip():
                continue
            if not obj.is_editable:
                read_only += 1
                continue
            placement.placement_id = reserve_placement_id(used)
            assigned += 1
        if read_only:
            self.report({"WARNING"}, f"Assigned {assigned} UUIDs. Skipped {read_only} read-only placements.")
        else:
            self.report({"INFO"}, f"Assigned {assigned} UUIDs.")
        return {"FINISHED"} if assigned else {"CANCELLED"}


class SONICVANE_OT_repair_duplicate_placement_ids(Operator):
    bl_idname = "sonic_vane.repair_duplicate_placement_ids"
    bl_label = "Find and Replace Duplicate UUIDs"
    bl_description = "Keep one placement per UUID and replace duplicate IDs in this scene"
    bl_options = {"UNDO"}

    def execute(self, context):
        seen = set()
        used = scene_placement_ids(context.scene)
        repaired = 0
        read_only = 0
        for obj in sorted(context.scene.objects, key=lambda item: (item.is_editable, item.name)):
            placement = obj.sonic_vane_placement
            key = canonical_placement_id(placement)
            if not key:
                continue
            if key not in seen:
                seen.add(key)
            elif obj.is_editable:
                placement.placement_id = reserve_placement_id(used)
                repaired += 1
            else:
                read_only += 1
        if read_only:
            self.report({"WARNING"}, f"Replaced {repaired} duplicate UUIDs. {read_only} read-only duplicates remain.")
        elif repaired:
            self.report({"INFO"}, f"Replaced {repaired} duplicate UUIDs.")
        else:
            self.report({"INFO"}, "No duplicate UUIDs found.")
        return {"FINISHED"} if repaired else {"CANCELLED"}


class SONICVANE_OT_export_placements(Operator, ExportHelper):
    bl_idname = "sonic_vane.export_placements"
    bl_label = "Export Placements"
    bl_description = "Write the current scene's marked gameplay objects to JSON"
    filename_ext = PLACEMENT_SUFFIX
    filter_glob: StringProperty(default="*.json", options={"HIDDEN"})

    def draw(self, context):
        box = self.layout.box()
        box.label(text="Companion GLB", icon="INFO")
        box.label(text="In the GLB export, enable")
        box.label(text="Custom Properties.")
        box.label(text="This preserves track target links.")

    def check(self, context):
        filepath = placement_filepath(self.filepath)
        if filepath == self.filepath:
            return False
        self.filepath = filepath
        return True

    def execute(self, context):
        self.filepath = placement_filepath(self.filepath)
        try:
            count = write_placements(self.filepath, context.scene, context.evaluated_depsgraph_get())
        except (OSError, ValueError) as error:
            self.report({"ERROR"}, str(error))
            return {"CANCELLED"}
        self.report({"INFO"}, f"Exported {count} Sonic Vane placements.")
        return {"FINISHED"}


def editable_automation_route(context):
    obj = context.object
    return bool(obj and obj.is_editable and obj.sonic_vane_placement.kind == "automation_spline")


class SONICVANE_OT_add_automation_extension(Operator):
    bl_idname = "sonic_vane.add_automation_extension"
    bl_label = "Add Automation Extension"
    bl_description = "Add a junction or progress event to the active route"
    bl_options = {"UNDO"}

    kind: EnumProperty(
        items=(("junction", "Junction", ""), ("event", "Progress Event", "")),
        options={"SKIP_SAVE"},
    )

    @classmethod
    def poll(cls, context):
        return editable_automation_route(context)

    def execute(self, context):
        context.object.sonic_vane_placement.automation_extensions.add().kind = self.kind
        return {"FINISHED"}


class SONICVANE_OT_remove_automation_extension(Operator):
    bl_idname = "sonic_vane.remove_automation_extension"
    bl_label = "Remove Automation Extension"
    bl_description = "Remove this junction or progress event from the active route"
    bl_options = {"UNDO"}

    index: IntProperty(default=-1, options={"SKIP_SAVE"})

    @classmethod
    def poll(cls, context):
        return editable_automation_route(context)

    def execute(self, context):
        items = context.object.sonic_vane_placement.automation_extensions
        if not 0 <= self.index < len(items):
            return {"CANCELLED"}
        items.remove(self.index)
        return {"FINISHED"}


class SONICVANE_OT_add_surface_targets(Operator):
    bl_idname = "sonic_vane.add_surface_targets"
    bl_label = "Add Selected Track Meshes"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return context.object and context.object.sonic_vane_placement.kind == "surface_behavior"

    def execute(self, context):
        placement = context.object.sonic_vane_placement
        existing = {item.target for item in placement.surface_targets}
        meshes = [
            obj for obj in context.selected_objects
            if obj.type == "MESH" and obj.is_editable and obj not in existing and obj.sonic_vane_placement.kind == "NONE"
        ]
        if not meshes:
            self.report({"WARNING"}, "Select track meshes with the Surface Behavior as the active object.")
            return {"CANCELLED"}
        for obj in meshes:
            if not obj.get(SURFACE_TARGET_KEY):
                obj[SURFACE_TARGET_KEY] = str(uuid.uuid4())
            placement.surface_targets.add().target = obj
        return {"FINISHED"}


class SONICVANE_OT_remove_surface_target(Operator):
    bl_idname = "sonic_vane.remove_surface_target"
    bl_label = "Remove Track Target"
    bl_options = {"REGISTER", "UNDO"}
    index: IntProperty(min=0)

    @classmethod
    def poll(cls, context):
        return context.object and context.object.sonic_vane_placement.kind == "surface_behavior"

    def execute(self, context):
        targets = context.object.sonic_vane_placement.surface_targets
        if self.index >= len(targets):
            return {"CANCELLED"}
        targets.remove(self.index)
        return {"FINISHED"}


class SONICVANE_OT_add_volume_box(Operator):
    bl_idname = "sonic_vane.add_volume_box"
    bl_label = "Add Box"
    bl_description = "Add another collision box to this volume"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return context.object and context.object.is_editable and context.object.sonic_vane_placement.kind in objective_preview.VOLUME_COLORS

    def execute(self, context):
        obj = context.object
        placement = obj.sonic_vane_placement
        size = getattr(placement, f"{placement.kind}_size")
        box = bpy.data.objects.new("Volume Box", None)
        box[objective_preview.VOLUME_BOX_KEY] = True
        box.parent = obj
        box.empty_display_type = "CUBE"
        box.empty_display_size = 0.5
        box.scale = tuple(max(dimension, 0.1) for dimension in size)
        box.location.x = size.x * (1 + len(objective_preview.volume_boxes(obj)))
        for collection in obj.users_collection:
            if collection.is_editable:
                collection.objects.link(box)
        return {"FINISHED"}


class SONICVANE_PT_object_placement(Panel):
    bl_label = "Sonic Vane Placement"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "object"

    def draw(self, context):
        placement = context.object.sonic_vane_placement
        layout = self.layout
        details = layout.column()
        details.use_property_split = True
        details.prop(placement, "kind")
        if placement.kind == "NONE":
            return
        identity = details.row()
        identity.enabled = False
        identity.prop(placement, "placement_id")
        details.operator(SONICVANE_OT_new_placement_id.bl_idname)
        header, body = layout.panel("Presentation", default_closed=True)
        header.label(text="Presentation")
        if body:
            body.prop(placement, "presentation_hidden")
            body.prop(placement, "presentation_muted")
        family = variant_family(placement.kind)
        if family in VARIANTS:
            details.prop(placement, f"{family}_variant")
        if placement.kind == "rail":
            details.prop(context.object, "sonic_vane_rail_guides")
        elif placement.kind in {"dash_panel", "ramp"}:
            details.prop(context.object, "sonic_vane_dash_direction")
        elif placement.kind == "automation_spline":
            details.prop(context.object, "sonic_vane_automation_guides")
        elif placement.kind == "spring" and placement.use_trajectory_solver:
            details.prop(context.object, "sonic_vane_show_trajectory")
        elif placement.kind == "checkpoint":
            details.prop(context.object, "sonic_vane_show_trigger")
        elif placement.kind == "rail_booster":
            details.prop(placement, "booster_rail")
            position_row = details.row()
            position_row.enabled = bool(placement.booster_rail)
            position_row.prop(placement, "booster_position")
        elif placement.kind == "teleporter_entrance":
            details.prop(placement, "teleporter_link_mode")
            if placement.teleporter_link_mode == "local":
                details.prop(placement, "teleporter_destination")
            else:
                details.prop(placement, "teleporter_level_id")
                details.prop(placement, "teleporter_level_exit_id")
        elif placement.kind in {"goal_ring", "collection_item"}:
            details.prop(placement, "race_start_link")
        elif placement.kind == "race_start":
            details.prop(placement, "race_finish")
        elif placement.kind == "environment_transition":
            details.label(text="Runs in offline play.", icon="INFO")

        groups = {}
        for key, field in CATALOG["types"][placement.kind]["properties"].items():
            if not field.get("authoring_hidden") and field_enabled(placement, field):
                groups.setdefault(field["group"], []).append((key, field))
        for group, fields in groups.items():
            header, body = layout.panel(group, default_closed=group not in {
                "Spring", "Rail", "Ring", "Ring Trail", "Rail Booster", "Item Monitor", "Dash Panel",
                "Checkpoint", "Trigger", "Enemy", "Spike Strip", "Base Plate", "Cycle",
                "Spike Ball", "Crash Down", "Physical", "Player Spawn", "Ramp", "Bumper", "Vault Bar",
                "Route", "Activation", "Water Geometry", "Flipper", "Death Plane", "Teleporter Entrance",
                "Teleporter Exit", "Gravity Field", "Planet Surface", "Camera Activation", "Camera Release",
                "Camera Framing", "Camera Aim", "Camera Blends", "Goal Ring", "Goal Camera",
                "Collection Item", "Race Start", "Homing Target", "Gravity Modifier", "Surface Behavior",
                "Surface Movement", "Volume", "Time Transition", "Weather Transition", "Sky Transition",
                "Impulse", "Locks and Camera"
            })
            header.label(text=group)
            if body is None:
                continue
            body.use_property_split = True
            for key, field in fields:
                if field["type"] == "axis_mask":
                    row = body.row(align=True)
                    row.use_property_split = False
                    row.label(text=field["label"])
                    for index, label in enumerate(field.get("axis_labels", ("X", "Y", "Z"))):
                        row.prop(placement, key, index=index, text=label, toggle=True)
                    continue
                if field["type"] == "physics_mask":
                    grid = body.column(align=True)
                    grid.use_property_split = False
                    grid.label(text=field["label"])
                    for start in range(0, 32, 8):
                        row = grid.row(align=True)
                        for index in range(start, start + 8):
                            row.prop(placement, key, index=index, text=str(index + 1), toggle=True)
                    continue
                row = body.row()
                marker = placement_marker(context.object, key) if field["type"] == "local_offset" else None
                if marker:
                    row.prop(marker, "location", text=field["label"])
                else:
                    row.prop(placement, key, text=field["label"])
        if placement.kind == "automation_spline":
            self.draw_automation_extensions(layout, placement)
        if placement.kind in objective_preview.VOLUME_COLORS:
            layout.operator(SONICVANE_OT_add_volume_box.bl_idname)
            for box in objective_preview.volume_boxes(context.object):
                options = layout.box()
                options.label(text=box.name, icon="CUBE")
                options.prop(box, "location", text="Center")
                options.prop(box, "rotation_euler", text="Rotation")
                options.prop(box, "scale", text="Dimensions")
        if placement.kind == "surface_behavior" and placement.surface_behavior_mode == "targets":
            box = layout.box()
            box.operator(SONICVANE_OT_add_surface_targets.bl_idname)
            target_ids = set()
            for index, entry in enumerate(placement.surface_targets):
                row = box.row()
                target = entry.target
                target_id = target.get(SURFACE_TARGET_KEY) if target else None
                valid = (
                    target_id
                    and target_id not in target_ids
                    and target.type == "MESH"
                    and target.sonic_vane_placement.kind == "NONE"
                    and context.scene.objects.get(target.name) == target
                )
                row.alert = not valid
                row.label(text=target.name if target else "Missing track mesh", icon="MESH_DATA" if valid else "ERROR")
                row.operator(SONICVANE_OT_remove_surface_target.bl_idname, text="", icon="X").index = index
                target_ids.add(target_id)
            box.label(text="Enable Custom Properties when exporting the track GLB.")
        if placement.kind == "camera_constraint" and (error := camera_preview.influence_error(placement)):
            layout.label(text=error, icon="ERROR")
        if placement.kind == "camera_constraint" and placement.camera_override_position and placement.camera_position_mode == "path_camera":
            path = camera_preview.path_for(context.object)
            if path:
                layout.label(text=f"Edit the {path.name} child to shape the camera path.", icon="CURVE_BEZCURVE")
            else:
                layout.label(text="Re-select Path Camera to restore the path.", icon="ERROR")
        if placement.kind == "camera_constraint" and placement.camera_activation_mode == "entry_gate":
            if not (placement.camera_exit_gate_enabled or placement.camera_duration_enabled or placement.camera_distance_enabled):
                layout.label(text="This shot has no automatic release.", icon="INFO")
            for role in camera_preview.active_gates(placement):
                box = layout.box()
                box.label(text=camera_preview.GATES[role][0])
                gate = camera_preview.gate_for(context.object, role)
                if not gate:
                    box.label(text="Re-select Entry Gate to restore this box.", icon="ERROR")
                    continue
                box.use_property_split = True
                box.prop(gate, "location", text="Center")
                box.prop(gate, "rotation_euler", text="Rotation")
                box.prop(gate, "scale", text="Dimensions")

    def draw_automation_extensions(self, layout, placement):
        header, body = layout.panel("Automation Junctions and Events", default_closed=True)
        header.label(text="Junctions and Events")
        if body is None:
            return
        buttons = body.row()
        buttons.operator(SONICVANE_OT_add_automation_extension.bl_idname, text="Add Junction").kind = "junction"
        buttons.operator(SONICVANE_OT_add_automation_extension.bl_idname, text="Add Progress Event").kind = "event"
        for index, item in enumerate(placement.automation_extensions):
            box = body.box()
            title = box.row()
            title.label(text="Junction" if item.kind == "junction" else "Progress Event")
            title.operator(SONICVANE_OT_remove_automation_extension.bl_idname, text="", icon="X").index = index
            box.use_property_split = True
            if item.kind == "junction":
                box.prop(item, "destination")
            for key in AUTOMATION_EXTENSIONS[item.kind]:
                if key in {"buffer_seconds", "input_threshold"} and item.choice == "default":
                    continue
                if key == "rearm_distance" and item.retrigger == "once":
                    continue
                box.prop(item, key)


class SonicVaneEnvironment(PropertyGroup):
    __annotations__ = {
        **{
            key: placement_property(key, field) for key, field in ENVIRONMENT_FIELDS.items()
            if key != "allowed_weather"
        },
        "allowed_weather": BoolVectorProperty(
            name="Allowed Weather", size=len(WEATHER_PRESETS), default=(True,) * len(WEATHER_PRESETS)
        ),
        **{
            f"override_{key}": BoolProperty(
                name=f"Override {field['label']}",
                description=f"Export {field['label']} as an override of the Godot scene setting",
                update=environment_preview.redraw_viewports if key in {"sky_profile", "starting_weather"} else None,
            )
            for key, field in ENVIRONMENT_FIELDS.items()
        },
    }


class SonicVaneEnvironmentPreview(PropertyGroup):
    enabled: BoolProperty(
        name="Show Environment Preview",
        description="Show approximate sky and fog colors and the sun direction in the 3D View",
        update=environment_preview.redraw_viewports,
    )
    hour: FloatProperty(
        name="Preview Hour", description="Preview time in decimal hours. 6.5 is 06:30",
        min=0.0, max=24.0, default=6.5, precision=2,
        update=environment_preview.redraw_viewports,
    )
    weather: EnumProperty(
        name="Preview Weather", description="Weather used only in the viewport preview",
        items=PREVIEW_WEATHER_ITEMS, default="authored", update=environment_preview.redraw_viewports,
    )


class SONICVANE_OT_preview_start_hour(Operator):
    bl_idname = "sonic_vane.preview_start_hour"
    bl_label = "Use Starting Hour"
    bl_description = "Copy the authored starting hour into the environment preview"

    @classmethod
    def poll(cls, context):
        settings = context.scene.sonic_vane_environment
        return settings.override_start_hour and not (settings.override_start_time_mode and settings.start_time_mode == "random")

    def execute(self, context):
        context.scene.sonic_vane_environment_preview.hour = context.scene.sonic_vane_environment.start_hour
        return {"FINISHED"}


class SONICVANE_PT_environment_preview(Panel):
    bl_label = "Environment Preview"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Sonic Vane"

    def draw(self, context):
        preview = context.scene.sonic_vane_environment_preview
        self.layout.prop(preview, "enabled")
        controls = self.layout.column()
        controls.enabled = preview.enabled
        controls.prop(preview, "hour", slider=True)
        controls.prop(preview, "weather", text="Weather")
        controls.operator(SONICVANE_OT_preview_start_hour.bl_idname)


class SONICVANE_PT_scene_placements(Panel):
    bl_label = "Sonic Vane Placements"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "scene"

    def draw(self, context):
        self.layout.prop(context.scene, "sonic_vane_level_id")
        self.layout.prop(context.scene, "sonic_vane_ring_default")
        self.layout.prop(context.scene, "sonic_vane_enemy_default")
        self.layout.operator(SONICVANE_OT_register_asset_library.bl_idname)
        self.layout.operator(SONICVANE_OT_assign_missing_placement_ids.bl_idname)
        self.layout.operator(SONICVANE_OT_repair_duplicate_placement_ids.bl_idname)
        self.layout.operator(SONICVANE_OT_export_placements.bl_idname)


class SONICVANE_PT_scene_environment(Panel):
    bl_label = "Environment"
    bl_parent_id = "SONICVANE_PT_scene_placements"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "scene"
    bl_options = {"DEFAULT_CLOSED"}

    def draw(self, context):
        settings = context.scene.sonic_vane_environment
        self.layout.label(text="Unchecked settings use the Godot scene values.")
        for key in ENVIRONMENT_FIELDS:
            if key == "start_hour" and settings.override_start_time_mode and settings.start_time_mode == "random":
                continue
            row = self.layout.row(align=True)
            override = f"override_{key}"
            if key == "allowed_weather":
                row.prop(settings, override, text="Override Allowed Weather")
                if settings.override_allowed_weather:
                    presets = self.layout.box()
                    for index, preset in enumerate(WEATHER_PRESETS.values()):
                        presets.prop(settings, key, index=index, text=preset["label"])
                continue
            row.prop(settings, override, text="")
            value = row.row()
            value.enabled = getattr(settings, override)
            value.prop(settings, key)


CLASSES = (
    SonicVaneAutomationExtension,
    SonicVaneSurfaceTarget,
    SonicVanePlacement,
    SonicVaneEnvironment,
    SonicVaneEnvironmentPreview,
    SONICVANE_OT_preview_start_hour,
    SONICVANE_OT_add_surface_targets,
    SONICVANE_OT_remove_surface_target,
    SONICVANE_OT_add_volume_box,
    SONICVANE_OT_register_asset_library,
    SONICVANE_OT_new_placement_id,
    SONICVANE_OT_assign_missing_placement_ids,
    SONICVANE_OT_repair_duplicate_placement_ids,
    SONICVANE_OT_export_placements,
    SONICVANE_OT_add_automation_extension,
    SONICVANE_OT_remove_automation_extension,
    SONICVANE_PT_object_placement,
    SONICVANE_PT_scene_placements,
    SONICVANE_PT_scene_environment,
    SONICVANE_PT_environment_preview,
)


def export_menu(self, context):
    self.layout.operator(SONICVANE_OT_export_placements.bl_idname, text="Sonic Vane Placements (.json)")


def register():
    global rail_guides_handler, dash_direction_handler, spring_trajectory_handler, checkpoint_trigger_handler
    global automation_guides_handler, camera_guides_handler, objective_guides_handler
    global environment_preview_handler
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Object.sonic_vane_placement = PointerProperty(type=SonicVanePlacement)
    bpy.types.Object.sonic_vane_rail_guides = BoolProperty(
        name="Show Rail Guides", description="Show centerline, direction, endpoints and rider height", default=True
    )
    bpy.types.Object.sonic_vane_dash_direction = BoolProperty(
        name="Show Direction", description="Show the dash launch direction on the active panel", default=True
    )
    bpy.types.Object.sonic_vane_show_trajectory = BoolProperty(
        name="Show Trajectory", description="Show the aim line or arc of the selected spring or dash ring", default=True
    )
    bpy.types.Object.sonic_vane_show_trigger = BoolProperty(
        name="Show Trigger", description="Show the checkpoint's trigger bounds in the viewport", default=True
    )
    bpy.types.Object.sonic_vane_automation_guides = BoolProperty(
        name="Show Route Guides", description="Display the route direction and generated trigger bounds", default=True
    )
    if not bpy.app.background:
        rail_guides_handler = bpy.types.SpaceView3D.draw_handler_add(rail_preview.draw, (), "WINDOW", "POST_VIEW")
        dash_direction_handler = bpy.types.SpaceView3D.draw_handler_add(dash_preview.draw, (), "WINDOW", "POST_VIEW")
        spring_trajectory_handler = bpy.types.SpaceView3D.draw_handler_add(spring_preview.draw, (), "WINDOW", "POST_VIEW")
        checkpoint_trigger_handler = bpy.types.SpaceView3D.draw_handler_add(
            checkpoint_preview.draw, (), "WINDOW", "POST_VIEW"
        )
        automation_guides_handler = bpy.types.SpaceView3D.draw_handler_add(
            automation_preview.draw, (), "WINDOW", "POST_VIEW"
        )
        camera_guides_handler = bpy.types.SpaceView3D.draw_handler_add(
            camera_preview.draw, (), "WINDOW", "POST_VIEW"
        )
        objective_guides_handler = bpy.types.SpaceView3D.draw_handler_add(
            objective_preview.draw, (), "WINDOW", "POST_VIEW"
        )
        environment_preview_handler = bpy.types.SpaceView3D.draw_handler_add(
            environment_preview.draw, (SKY_LABELS, WEATHER_LABELS), "WINDOW", "POST_PIXEL"
        )
    bpy.types.Scene.sonic_vane_level_id = StringProperty(
        name="Level ID", description="Stable lowercase identifier for this level"
    )
    bpy.types.Scene.sonic_vane_environment = PointerProperty(type=SonicVaneEnvironment)
    bpy.types.Scene.sonic_vane_environment_preview = PointerProperty(type=SonicVaneEnvironmentPreview)
    bpy.types.Scene.sonic_vane_ring_default = EnumProperty(
        name="Default Ring Variant", description="Pickup variant used by this level's rings and ring trails",
        items=VARIANT_ITEMS["ring"][1:], default=STANDARD_RING, update=sync_level_ring_default,
    )
    bpy.types.Scene.sonic_vane_enemy_default = EnumProperty(
        name="Default Enemy Variant", description="Enemy used by placements set to Use Level Default",
        items=VARIANT_ITEMS["enemy"][1:], default=STANDARD_ENEMY, update=sync_level_enemy_default,
    )
    bpy.app.handlers.blend_import_post.append(initialize_appended_gameplay_assets)
    bpy.app.handlers.load_post.append(sync_loaded_markers)
    bpy.app.handlers.save_pre.append(cleanup_monitor_previews)
    bpy.app.handlers.depsgraph_update_post.append(booster_preview.sync_moved_rails)
    bpy.app.handlers.depsgraph_update_post.append(spring_preview.sync_moved_targets)
    reset_object_tracking()
    for handlers, callback in OBJECT_TRACKING_HANDLERS:
        handlers.append(callback)
    bpy.app.timers.register(sync_loaded_markers)
    bpy.types.TOPBAR_MT_file_export.append(export_menu)


def unregister():
    global rail_guides_handler, dash_direction_handler, spring_trajectory_handler, checkpoint_trigger_handler
    global automation_guides_handler, camera_guides_handler, objective_guides_handler
    global environment_preview_handler
    if environment_preview_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(environment_preview_handler, "WINDOW")
        environment_preview_handler = None
    if objective_guides_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(objective_guides_handler, "WINDOW")
        objective_guides_handler = None
    if camera_guides_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(camera_guides_handler, "WINDOW")
        camera_guides_handler = None
    if automation_guides_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(automation_guides_handler, "WINDOW")
        automation_guides_handler = None
    if rail_guides_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(rail_guides_handler, "WINDOW")
        rail_guides_handler = None
    if dash_direction_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(dash_direction_handler, "WINDOW")
        dash_direction_handler = None
    if spring_trajectory_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(spring_trajectory_handler, "WINDOW")
        spring_trajectory_handler = None
    if checkpoint_trigger_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(checkpoint_trigger_handler, "WINDOW")
        checkpoint_trigger_handler = None
    bpy.types.TOPBAR_MT_file_export.remove(export_menu)
    bpy.app.handlers.blend_import_post.remove(initialize_appended_gameplay_assets)
    bpy.app.handlers.load_post.remove(sync_loaded_markers)
    bpy.app.handlers.save_pre.remove(cleanup_monitor_previews)
    bpy.app.handlers.depsgraph_update_post.remove(booster_preview.sync_moved_rails)
    bpy.app.handlers.depsgraph_update_post.remove(spring_preview.sync_moved_targets)
    for handlers, callback in OBJECT_TRACKING_HANDLERS:
        handlers.remove(callback)
    pause_object_tracking()
    known_object_ids.clear()
    if bpy.app.timers.is_registered(sync_loaded_markers):
        bpy.app.timers.unregister(sync_loaded_markers)
    del bpy.types.Scene.sonic_vane_level_id
    del bpy.types.Scene.sonic_vane_environment
    del bpy.types.Scene.sonic_vane_environment_preview
    del bpy.types.Scene.sonic_vane_ring_default
    del bpy.types.Scene.sonic_vane_enemy_default
    del bpy.types.Object.sonic_vane_placement
    del bpy.types.Object.sonic_vane_rail_guides
    del bpy.types.Object.sonic_vane_dash_direction
    del bpy.types.Object.sonic_vane_show_trajectory
    del bpy.types.Object.sonic_vane_show_trigger
    del bpy.types.Object.sonic_vane_automation_guides
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)

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
from bpy.props import BoolProperty, EnumProperty, FloatProperty, FloatVectorProperty, IntProperty, PointerProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ExportHelper
from mathutils import Matrix, Vector
from . import booster_preview, dash_preview, rail_preview, spring_preview
from .spring_preview import MARKER_FIELD_KEY, placement_marker


CATALOG = json.loads(Path(__file__).with_name("catalog.json").read_text(encoding="utf-8"))
PLACEMENT_PROPERTIES = {
    key: field for definition in CATALOG["types"].values()
    for key, field in definition["properties"].items()
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
PREVIEW_SOURCE_KEY = "sonic_vane_placement_preview_source"
MONITOR_STYLE_KEY = "sonic_vane_monitor_style"
MONITOR_MATERIAL_KEY = "sonic_vane_monitor_material"
MONITOR_TEXTURE_KEY = "sonic_vane_monitor_texture"
MONITOR_STYLES = CATALOG["types"]["item_monitor"]["properties"]["monitor_style"]["options"]
RING_TRAIL_GROUP = "Sonic Vane Ring Trail"
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


def export_bezier(obj, world):
    if (obj.type != "CURVE" or obj.data.dimensions != "3D"
            or len(obj.data.splines) != 1 or obj.data.splines[0].type != "BEZIER"):
        raise ValueError(f"{obj.name} needs one Bézier spline on a 3D curve.")
    rotation = world.to_quaternion().to_matrix()
    if any(abs(value - rotation[row][col]) > 0.0001
           for row, values in enumerate(world.to_3x3()) for col, value in enumerate(values)):
        raise ValueError(f"Apply the scale of {obj.name} before exporting the spline.")
    spline = obj.data.splines[0]
    if len(spline.bezier_points) < (3 if spline.use_cyclic_u else 2):
        raise ValueError(f"{obj.name} has too few Bézier points.")
    points = []
    for point in spline.bezier_points:
        data = {
            "position": list(Y_UP @ point.co),
            "in": list(Y_UP @ (point.handle_left - point.co)),
            "out": list(Y_UP @ (point.handle_right - point.co)),
            "tilt": point.tilt,
        }
        if not all(math.isfinite(value) for key in ("position", "in", "out") for value in data[key]) or not math.isfinite(point.tilt):
            raise ValueError(f"{obj.name} has a non-finite Bézier point.")
        points.append(data)
    return {"closed": spline.use_cyclic_u, "points": points}


def field_enabled(placement, field):
    return all(
        getattr(placement, key) == value for key, value in field.get("requires", {}).items()
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

    records = []
    names_by_id = {}
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
                value = list(Y_UP @ value)
                valid = all(math.isfinite(component) for component in value)
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
        if "curve_target" in CATALOG["types"][placement.kind]:
            record["curve"] = export_bezier(obj, world)
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
    return {"schema_version": CATALOG["schema_version"], "level_id": level_id, "placements": records}


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


def sync_ring_trail_preview(placement, _context):
    obj = placement.id_data
    if placement.kind != "ring_spline" or obj.type != "CURVE" or not obj.is_editable:
        return
    modifier = obj.modifiers.get("Ring Trail Preview")
    if modifier is None:
        modifier = obj.modifiers.new("Ring Trail Preview", "NODES")
    if modifier.type != "NODES":
        return
    if not modifier.node_group:
        group = bpy.data.node_groups.get(RING_TRAIL_GROUP)
        if group is None:
            with bpy.data.libraries.load(str(ASSET_DIRECTORY / "Traversal Objects.blend")) as (_, imported):
                imported.node_groups = [RING_TRAIL_GROUP]
            group = imported.node_groups[0]
        modifier.node_group = group
    for socket in modifier.node_group.interface.items_tree:
        if socket.item_type == "SOCKET" and socket.in_out == "INPUT" and socket.name == "Ring Spacing":
            if hasattr(modifier, "properties"):
                getattr(modifier.properties.inputs, socket.identifier).value = placement.ring_spacing
            else:
                modifier[socket.identifier] = placement.ring_spacing
            obj.update_tag()
            break


def sync_monitor_preview(placement, _context):
    obj = placement.id_data
    if placement.kind != "item_monitor" or obj.type != "MESH" or not obj.is_editable:
        return
    style = placement.monitor_style
    mesh = next((mesh for mesh in bpy.data.meshes if mesh.get(MONITOR_STYLE_KEY) == style), None)
    if mesh is None:
        with bpy.data.libraries.load(str(ASSET_DIRECTORY / "Item Monitors.blend")) as (_, imported):
            imported.meshes = [MONITOR_STYLES[style]["preview_mesh"]]
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


def spring_variant_default(key):
    def get(placement, value, is_set):
        if is_set or placement.kind != "spring":
            return value
        return SPRING_STYLES[placement.spring_style].get("bool_defaults", {}).get(key, value)

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


def update_placement_kind(placement, context):
    sync_placement_markers(placement, context)
    sync_ring_trail_preview(placement, context)
    sync_size_preview(placement, context)
    sync_spring_preview(placement, context)
    dash_preview.sync_model(placement)
    booster_preview.sync_preview(placement)


def placement_property(key, field):
    settings = {"name": field["label"], "description": field["description"], "default": field["default"]}
    if field["type"] == "bool":
        if key in MARKER_CONTROLS:
            settings["update"] = sync_placement_markers
        if key in SPRING_VARIANT_BOOLS and bpy.app.version >= (5, 1, 0):
            settings["get_transform"] = spring_variant_default(key)
        if key == "trajectory_arc_enabled":
            settings["update"] = spring_preview.sync_model
        return BoolProperty(**settings)
    if field["type"] == "enum":
        items = [(key, option["label"], "", option["value"]) for key, option in field["options"].items()]
        if key == "rail_variant":
            settings["update"] = sync_rail_preview
        if key == "monitor_style":
            settings["update"] = sync_monitor_preview
        if key == "spring_style":
            settings["update"] = sync_spring_style
        if key == "dash_launch_axis":
            settings["update"] = dash_preview.sync_model
        if key in {"launch_axis", "trajectory_arc_up_mode"}:
            settings["update"] = spring_preview.sync_model
        return EnumProperty(items=items, **settings)
    if field["type"] == "local_offset":
        settings["default"] = Y_UP.transposed() @ Vector(field["default"])
        settings["update"] = update_marker_offset(key)
        return FloatVectorProperty(size=3, subtype="TRANSLATION", unit="LENGTH", **settings)
    settings["min"] = field["min"]
    if "max" in field:
        settings["max"] = field["max"]
    if field["type"] == "int":
        return IntProperty(**settings)
    if key == "ring_spacing":
        settings["update"] = sync_ring_trail_preview
        settings["unit"] = "LENGTH"
    if key == "size":
        settings["update"] = sync_size_preview
    if key == "trajectory_arc_height":
        settings["update"] = spring_preview.sync_model
    return FloatProperty(**settings)


def scene_placement_ids(scene):
    used = set()
    for obj in scene.objects:
        placement = obj.sonic_vane_placement
        if placement.kind == "NONE" or not placement.placement_id.strip():
            continue
        try:
            used.add(str(uuid.UUID(placement.placement_id.strip())))
        except ValueError:
            continue
    return used


def reserve_placement_id(used):
    placement_id = str(uuid.uuid4())
    while placement_id in used:
        placement_id = str(uuid.uuid4())
    used.add(placement_id)
    return placement_id


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
        ),
        default="NONE",
        update=update_placement_kind,
    )
    placement_id: StringProperty(
        name="Placement UUID",
        description="Stable identity shared by all exports of this placement",
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


class SONICVANE_OT_export_placements(Operator, ExportHelper):
    bl_idname = "sonic_vane.export_placements"
    bl_label = "Export Placements"
    bl_description = "Write the current scene's marked gameplay objects to JSON"
    filename_ext = PLACEMENT_SUFFIX
    filter_glob: StringProperty(default="*.json", options={"HIDDEN"})

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
        if placement.kind == "rail":
            details.prop(context.object, "sonic_vane_rail_guides")
        elif placement.kind == "dash_panel":
            details.prop(context.object, "sonic_vane_dash_direction")
        elif placement.kind == "spring" and placement.use_trajectory_solver:
            details.prop(context.object, "sonic_vane_show_trajectory")
        elif placement.kind == "rail_booster":
            details.prop(placement, "booster_rail")
            position_row = details.row()
            position_row.enabled = bool(placement.booster_rail)
            position_row.prop(placement, "booster_position")

        groups = {}
        for key, field in CATALOG["types"][placement.kind]["properties"].items():
            if field_enabled(placement, field):
                groups.setdefault(field["group"], []).append((key, field))
        for group, fields in groups.items():
            header, body = layout.panel(group, default_closed=group not in {
                "Spring", "Rail", "Ring", "Ring Trail", "Rail Booster", "Item Monitor", "Dash Panel"
            })
            header.label(text=group)
            if body is None:
                continue
            body.use_property_split = True
            for key, field in fields:
                row = body.row()
                marker = placement_marker(context.object, key) if field["type"] == "local_offset" else None
                if marker:
                    row.prop(marker, "location", text=field["label"])
                else:
                    row.prop(placement, key, text=field["label"])


class SONICVANE_PT_scene_placements(Panel):
    bl_label = "Sonic Vane Placements"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "scene"

    def draw(self, context):
        self.layout.prop(context.scene, "sonic_vane_level_id")
        self.layout.operator(SONICVANE_OT_register_asset_library.bl_idname)
        self.layout.operator(SONICVANE_OT_assign_missing_placement_ids.bl_idname)
        self.layout.operator(SONICVANE_OT_export_placements.bl_idname)


CLASSES = (
    SonicVanePlacement,
    SONICVANE_OT_register_asset_library,
    SONICVANE_OT_new_placement_id,
    SONICVANE_OT_assign_missing_placement_ids,
    SONICVANE_OT_export_placements,
    SONICVANE_PT_object_placement,
    SONICVANE_PT_scene_placements,
)


def export_menu(self, context):
    self.layout.operator(SONICVANE_OT_export_placements.bl_idname, text="Sonic Vane Placements (.json)")


def register():
    global rail_guides_handler, dash_direction_handler, spring_trajectory_handler
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
    if not bpy.app.background:
        rail_guides_handler = bpy.types.SpaceView3D.draw_handler_add(rail_preview.draw, (), "WINDOW", "POST_VIEW")
        dash_direction_handler = bpy.types.SpaceView3D.draw_handler_add(dash_preview.draw, (), "WINDOW", "POST_VIEW")
        spring_trajectory_handler = bpy.types.SpaceView3D.draw_handler_add(spring_preview.draw, (), "WINDOW", "POST_VIEW")
    bpy.types.Scene.sonic_vane_level_id = StringProperty(
        name="Level ID", description="Stable lowercase identifier for this level"
    )
    bpy.app.handlers.blend_import_post.append(initialize_appended_gameplay_assets)
    bpy.app.handlers.load_post.append(sync_loaded_markers)
    bpy.app.handlers.save_pre.append(cleanup_monitor_previews)
    bpy.app.handlers.depsgraph_update_post.append(booster_preview.sync_moved_rails)
    bpy.app.handlers.depsgraph_update_post.append(spring_preview.sync_moved_targets)
    bpy.app.timers.register(sync_loaded_markers)
    bpy.types.TOPBAR_MT_file_export.append(export_menu)


def unregister():
    global rail_guides_handler, dash_direction_handler, spring_trajectory_handler
    if rail_guides_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(rail_guides_handler, "WINDOW")
        rail_guides_handler = None
    if dash_direction_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(dash_direction_handler, "WINDOW")
        dash_direction_handler = None
    if spring_trajectory_handler is not None:
        bpy.types.SpaceView3D.draw_handler_remove(spring_trajectory_handler, "WINDOW")
        spring_trajectory_handler = None
    bpy.types.TOPBAR_MT_file_export.remove(export_menu)
    bpy.app.handlers.blend_import_post.remove(initialize_appended_gameplay_assets)
    bpy.app.handlers.load_post.remove(sync_loaded_markers)
    bpy.app.handlers.save_pre.remove(cleanup_monitor_previews)
    bpy.app.handlers.depsgraph_update_post.remove(booster_preview.sync_moved_rails)
    bpy.app.handlers.depsgraph_update_post.remove(spring_preview.sync_moved_targets)
    if bpy.app.timers.is_registered(sync_loaded_markers):
        bpy.app.timers.unregister(sync_loaded_markers)
    del bpy.types.Scene.sonic_vane_level_id
    del bpy.types.Object.sonic_vane_placement
    del bpy.types.Object.sonic_vane_rail_guides
    del bpy.types.Object.sonic_vane_dash_direction
    del bpy.types.Object.sonic_vane_show_trajectory
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)

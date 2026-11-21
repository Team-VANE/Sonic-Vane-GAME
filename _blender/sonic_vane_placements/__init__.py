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
from bpy.props import BoolProperty, EnumProperty, FloatProperty, FloatVectorProperty, PointerProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup
from bpy_extras.io_utils import ExportHelper
from mathutils import Matrix, Vector


CATALOG = json.loads(Path(__file__).with_name("catalog.json").read_text(encoding="utf-8"))
SPRING_PROPERTIES = CATALOG["types"]["spring"]["properties"]
LEVEL_ID_PATTERN = re.compile(r"[a-z][a-z0-9_]*")
PLACEMENT_SUFFIX = ".placements.json"
PLACEMENT_SUFFIX_PATTERN = re.compile(r"(?:\.placements)+(?:\.json)?$|\.json$", re.IGNORECASE)
ASSET_LIBRARY_NAME = "Sonic Vane"
ASSET_DIRECTORY = Path(__file__).with_name("assets").resolve()
ASSET_TYPE_KEY = "sonic_vane_asset_type"
GAMEPLAY_COLLECTION_NAME = "Sonic Vane Gameplay"
MARKER_FIELD_KEY = "sonic_vane_marker_field"
MARKER_FIELDS = {
    key: field for definition in CATALOG["types"].values()
    for key, field in definition["properties"].items() if field["type"] == "local_offset"
}
MARKER_CONTROLS = {key for field in MARKER_FIELDS.values() for key in field.get("requires", {})}
Y_UP = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))


def field_enabled(placement, field):
    return all(
        getattr(placement, key) == value for key, value in field.get("requires", {}).items()
    )


def placement_marker(obj, key):
    return next((child for child in obj.children if child.get(MARKER_FIELD_KEY) == key), None)


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


@persistent
def sync_loaded_markers(*_):
    for scene in bpy.data.scenes:
        for obj in tuple(scene.objects):
            placement = obj.sonic_vane_placement
            if placement.kind != "NONE":
                sync_placement_markers(placement, None)


def update_marker_offset(key):
    def update(placement, _context):
        marker = placement_marker(placement.id_data, key)
        if marker and marker.is_editable:
            marker.location = getattr(placement, key)
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
            elif field["type"] == "float":
                valid = math.isfinite(value) and field["min"] <= value <= field.get("max", math.inf)
            elif field["type"] == "enum":
                valid = value in field["options"]
            else:
                valid = isinstance(value, bool)
            if not valid:
                raise ValueError(f"{obj.name} has an invalid {field['label']}.")
            values[key] = value
        records.append({
            "id": placement_id,
            "type": placement.kind,
            "label": obj.name,
            "position": list(position),
            "rotation": list(xyzw),
            "properties": values,
        })

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


def spring_property(key, field):
    settings = {"name": field["label"], "description": field["description"], "default": field["default"]}
    if field["type"] == "bool":
        if key in MARKER_CONTROLS:
            settings["update"] = sync_placement_markers
        return BoolProperty(**settings)
    if field["type"] == "enum":
        items = [(key, option["label"], "", option["value"]) for key, option in field["options"].items()]
        return EnumProperty(items=items, **settings)
    if field["type"] == "local_offset":
        settings["default"] = Y_UP.transposed() @ Vector(field["default"])
        settings["update"] = update_marker_offset(key)
        return FloatVectorProperty(size=3, subtype="TRANSLATION", unit="LENGTH", **settings)
    settings["min"] = field["min"]
    if "max" in field:
        settings["max"] = field["max"]
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
        kind = obj.get(ASSET_TYPE_KEY)
        if not isinstance(kind, str) or kind not in CATALOG["types"]:
            continue

        placement = obj.sonic_vane_placement
        placement.kind = kind
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
        ),
        default="NONE",
        update=sync_placement_markers,
    )
    placement_id: StringProperty(
        name="Placement UUID",
        description="Stable identity shared by all exports of this placement",
    )


SonicVanePlacement.__annotations__.update(
    {key: spring_property(key, field) for key, field in SPRING_PROPERTIES.items()}
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
    filter_glob: StringProperty(default=f"*{PLACEMENT_SUFFIX}", options={"HIDDEN"})

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

        groups = {}
        for key, field in CATALOG["types"][placement.kind]["properties"].items():
            if field_enabled(placement, field):
                groups.setdefault(field["group"], []).append((key, field))
        for group, fields in groups.items():
            header, body = layout.panel(group, default_closed=group != "Spring")
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
                    row.prop(placement, key)


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
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Object.sonic_vane_placement = PointerProperty(type=SonicVanePlacement)
    bpy.types.Scene.sonic_vane_level_id = StringProperty(
        name="Level ID", description="Stable lowercase identifier for this level"
    )
    bpy.app.handlers.blend_import_post.append(initialize_appended_gameplay_assets)
    bpy.app.handlers.load_post.append(sync_loaded_markers)
    bpy.app.timers.register(sync_loaded_markers)
    bpy.types.TOPBAR_MT_file_export.append(export_menu)


def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(export_menu)
    bpy.app.handlers.blend_import_post.remove(initialize_appended_gameplay_assets)
    bpy.app.handlers.load_post.remove(sync_loaded_markers)
    if bpy.app.timers.is_registered(sync_loaded_markers):
        bpy.app.timers.unregister(sync_loaded_markers)
    del bpy.types.Scene.sonic_vane_level_id
    del bpy.types.Object.sonic_vane_placement
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)

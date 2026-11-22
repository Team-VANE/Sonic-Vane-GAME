import bpy
from mathutils import Vector


ROTATION_GROUP = "Sonic Vane Preview Rotation"
ROTATION_KEY = "sonic_vane_preview_rotation"
VARIANT_KEY = "sonic_vane_object_variant"
PREVIEW_REVISION = "sonic_vane_preview_revision"


def load_mesh(directory, preview_id, definition):
    filename = definition.get("preview_file")
    mesh_name = definition.get("preview_mesh")
    if not filename or not mesh_name:
        return None
    revision = definition.get("preview_revision", 0)
    mesh = next(
        (mesh for mesh in bpy.data.meshes if mesh.get(VARIANT_KEY) == preview_id and
         mesh.get(PREVIEW_REVISION, 0) == revision),
        None,
    )
    if mesh is not None:
        return mesh
    path = directory / filename
    if not path.is_file():
        return None
    with bpy.data.libraries.load(str(path)) as (available, imported):
        if mesh_name in available.meshes:
            imported.meshes = [mesh_name]
    if not imported.meshes or imported.meshes[0] is None:
        return None
    mesh = imported.meshes[0]
    mesh[VARIANT_KEY] = preview_id
    if revision:
        mesh[PREVIEW_REVISION] = revision
    return mesh


def rotation_group():
    group = next((item for item in bpy.data.node_groups if item.get(ROTATION_KEY)), None)
    if group:
        return group
    group = bpy.data.node_groups.new(ROTATION_GROUP, "GeometryNodeTree")
    group[ROTATION_KEY] = True
    group.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    angles = group.interface.new_socket(name="Euler Angles", in_out="INPUT", socket_type="NodeSocketVector")
    angles.force_non_field = True
    group.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    start = group.nodes.new("NodeGroupInput")
    euler = group.nodes.new("FunctionNodeEulerToRotation")
    transform = group.nodes.new("GeometryNodeTransform")
    result = group.nodes.new("NodeGroupOutput")
    start.location = (-440, 0)
    euler.location = (-230, -130)
    transform.location = (-20, 0)
    result.location = (190, 0)
    group.links.new(start.outputs["Geometry"], transform.inputs["Geometry"])
    group.links.new(start.outputs["Euler Angles"], euler.inputs[0])
    group.links.new(euler.outputs[0], transform.inputs["Rotation"])
    group.links.new(transform.outputs["Geometry"], result.inputs["Geometry"])
    return group


def set_rotation(obj, name, rotation, translation=(0, 0, 0)):
    modifier = obj.modifiers.get(name)
    if modifier and (modifier.type != "NODES" or not modifier.node_group or not modifier.node_group.get(ROTATION_KEY)):
        return
    if rotation is None:
        if modifier:
            obj.modifiers.remove(modifier)
        return
    if obj.type != "MESH":
        return
    if not modifier:
        modifier = obj.modifiers.new(name, "NODES")
        modifier.node_group = rotation_group()
        modifier.show_on_cage = False
    group = modifier.node_group
    if not any(item.name == "Translation" for item in group.interface.items_tree):
        socket = group.interface.new_socket(name="Translation", in_out="INPUT", socket_type="NodeSocketVector")
        socket.force_non_field = True
        start = next(node for node in group.nodes if node.type == "GROUP_INPUT")
        transform = next(node for node in group.nodes if node.bl_idname == "GeometryNodeTransform")
        group.links.new(start.outputs["Translation"], transform.inputs["Translation"])
    for key, value in (("Euler Angles", rotation), ("Translation", translation)):
        socket = next(item for item in group.interface.items_tree if item.name == key)
        if hasattr(modifier, "properties"):
            field = getattr(modifier.properties.inputs, socket.identifier)
            if (Vector(field.value) - Vector(value)).length_squared > 1e-12:
                field.value = tuple(value)
                obj.update_tag()
        elif (Vector(modifier[socket.identifier]) - Vector(value)).length_squared > 1e-12:
            modifier[socket.identifier] = tuple(value)
            obj.update_tag()

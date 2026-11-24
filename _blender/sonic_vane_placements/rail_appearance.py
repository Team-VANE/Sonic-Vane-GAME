import math

import bpy


APPEARANCE = "sonic_vane_rail_appearance"
SETTING_KEYS = {
    "rail_profile", "rail_width_scale", "rail_height_scale", "rail_override_finish",
    "rail_tint", "rail_roughness", "rail_metallic",
}


def configure_preview(group, standard):
    if group.get(APPEARANCE):
        return True
    nodes = group.nodes
    links = group.links
    start = next((node for node in nodes if node.type == "GROUP_INPUT"), None)
    end = next((node for node in nodes if node.type == "GROUP_OUTPUT"), None)
    if not start or not end or not end.inputs.get("Geometry") or not end.inputs["Geometry"].is_linked:
        return False
    if standard:
        circle = next((node for node in nodes if node.bl_idname == "GeometryNodeCurvePrimitiveCircle"), None)
        rotation = next((node for node in nodes if node.bl_idname == "GeometryNodeTransform"), None)
        if not circle or not rotation or not rotation.outputs["Geometry"].is_linked:
            return False
    else:
        info = next((node for node in nodes if node.bl_idname == "GeometryNodeObjectInfo"), None)
        axes = next((node for node in nodes if node.bl_idname == "ShaderNodeSeparateXYZ"), None)
        if not info or not axes:
            return False
        segment = info.inputs["Object"].default_value
        if not segment or segment.type != "MESH":
            return False

    def input_socket(name, socket_type, default=None):
        socket = group.interface.new_socket(name=name, in_out="INPUT", socket_type=socket_type)
        if default is not None:
            socket.default_value = default
        return start.outputs[name]

    width = input_socket("Width Scale", "NodeSocketFloat", 1.0)
    height = input_socket("Height Scale", "NodeSocketFloat", 1.0)
    materials = []
    if standard:
        sides = input_socket("Profile Sides", "NodeSocketInt", 4)
        links.new(sides, circle.inputs["Resolution"])
        square = nodes.new("ShaderNodeMath")
        square.operation = "COMPARE"
        square.inputs[1].default_value = 4.0
        square.inputs[2].default_value = 0.01
        links.new(sides, square.inputs[0])
        radius = nodes.new("GeometryNodeSwitch")
        radius.input_type = "FLOAT"
        radius.inputs["False"].default_value = 0.5
        radius.inputs["True"].default_value = math.sqrt(0.5)
        links.new(square.outputs[0], radius.inputs["Switch"])
        links.new(radius.outputs[0], circle.inputs["Radius"])
        dimensions = nodes.new("ShaderNodeCombineXYZ")
        dimensions.inputs["Z"].default_value = 1.0
        links.new(width, dimensions.inputs["X"])
        links.new(height, dimensions.inputs["Y"])
        transform = nodes.new("GeometryNodeTransform")
        profile = tuple(rotation.outputs["Geometry"].links)[0].to_socket
        links.new(rotation.outputs["Geometry"], transform.inputs["Geometry"])
        links.new(dimensions.outputs[0], transform.inputs["Scale"])
        links.new(transform.outputs["Geometry"], profile)
        for node, position in (
            (square, (-930, -280)), (radius, (-735, -280)), (dimensions, (-515, -480)),
            (transform, (-60, -210)),
        ):
            node.location = position
        materials = [None]
    else:
        materials = list(segment.data.materials)
        for channel, factor in (("Y", width), ("Z", height)):
            targets = [link.to_socket for link in axes.outputs[channel].links]
            scale = nodes.new("ShaderNodeMath")
            scale.operation = "MULTIPLY"
            scale.location = (-230, -575 if channel == "Y" else -750)
            links.new(axes.outputs[channel], scale.inputs[0])
            links.new(factor, scale.inputs[1])
            for target in targets:
                links.new(scale.outputs[0], target)

    geometry = end.inputs["Geometry"].links[0].from_socket
    end.location.x = max(end.location.x, geometry.node.location.x + 230 * (len(materials) + 1))
    for index, material in enumerate(materials):
        apply = nodes.new("GeometryNodeSetMaterial")
        apply.location = (end.location.x - 230 * (len(materials) - index), end.location.y)
        links.new(geometry, apply.inputs["Geometry"])
        links.new(input_socket(f"Finish {index + 1}", "NodeSocketMaterial", material), apply.inputs["Material"])
        if material:
            mask = nodes.new("GeometryNodeMaterialSelection")
            mask.inputs["Material"].default_value = material
            mask.location = (apply.location.x, apply.location.y - 200)
            links.new(mask.outputs[0], apply.inputs["Selection"])
        geometry = apply.outputs[0]
    links.new(geometry, end.inputs["Geometry"])
    group[APPEARANCE] = True
    return True


def themed_material(base, placement):
    color = (*placement.rail_tint[:3], 1.0)
    finish = [*color, placement.rail_roughness, placement.rail_metallic]
    for material in bpy.data.materials:
        if material.get(APPEARANCE + "_source") == (base.name if base else "") and list(material.get(APPEARANCE, [])) == finish:
            return material
    material = base.copy() if base else bpy.data.materials.new("Rail Material")
    material[APPEARANCE + "_source"] = base.name if base else ""
    material[APPEARANCE] = finish
    if not material.node_tree:
        material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    surface = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    base_color = surface.inputs["Base Color"]
    if base_color.is_linked:
        source = base_color.links[0].from_socket
        tint = nodes.new("ShaderNodeMixRGB")
        tint.blend_type = "MULTIPLY"
        tint.inputs[0].default_value = 1.0
        tint.inputs[2].default_value = color
        tint.location = (surface.location.x - 190, surface.location.y - 80)
        links.new(source, tint.inputs[1])
        links.new(tint.outputs[0], base_color)
        material.diffuse_color = color
    else:
        original = base_color.default_value[:] if base else (1.0, 1.0, 1.0, 1.0)
        material.diffuse_color = base_color.default_value = tuple(a * b for a, b in zip(original, color))
    for name, value in (("Roughness", placement.rail_roughness), ("Metallic", placement.rail_metallic)):
        socket = surface.inputs[name]
        if socket.is_linked:
            links.remove(socket.links[0])
        socket.default_value = value
    return material

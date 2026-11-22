import bpy

from .model_preview import VARIANT_KEY

PREVIEW_SOURCE_KEY = "sonic_vane_placement_preview_source"


def trail_group(base, variant_id, mesh):
    group = next((group for group in bpy.data.node_groups if group.get(VARIANT_KEY) == variant_id), None)
    if group is not None:
        return group
    source = bpy.data.objects.new(f"{mesh.name} Trail Preview", mesh)
    source[PREVIEW_SOURCE_KEY] = True
    group = base.copy()
    group.name = f"Sonic Vane Ring Trail ({variant_id})"
    group[VARIANT_KEY] = variant_id
    group.nodes["Object Info"].inputs["Object"].default_value = source
    return group

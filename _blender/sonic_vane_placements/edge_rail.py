import math

import bmesh


def selected_edge_chain(obj):
    mesh = bmesh.from_edit_mesh(obj.data)
    mesh.verts.index_update()
    links = {}
    for edge in mesh.edges:
        if edge.select and not edge.hide:
            first, second = edge.verts
            links.setdefault(first, []).append(second)
            links.setdefault(second, []).append(first)
    if not links:
        raise ValueError("Select the edges for the rail.")
    if any(len(neighbors) > 2 for neighbors in links.values()):
        raise ValueError("Select a single edge chain without branches.")

    endpoints = [vertex for vertex, neighbors in links.items() if len(neighbors) == 1]
    if len(endpoints) not in (0, 2):
        raise ValueError("Select one connected chain or closed loop.")
    closed = not endpoints
    first = min(endpoints or links, key=lambda vertex: vertex.index)
    ordered = [first]
    previous = None
    current = first
    visited = {first}
    while True:
        following = min(
            (vertex for vertex in links[current] if vertex != previous),
            default=None,
            key=lambda vertex: vertex.index,
        )
        if following is None or following == first:
            break
        if following in visited:
            raise ValueError("Select one connected chain or closed loop.")
        ordered.append(following)
        visited.add(following)
        previous, current = current, following
    if len(ordered) != len(links):
        raise ValueError("Select one connected chain or closed loop.")

    points = [obj.matrix_world @ vertex.co for vertex in ordered]
    if not all(math.isfinite(component) for point in points for component in point):
        raise ValueError("The selected edges contain invalid positions.")
    pairs = zip(points, points[1:] + (points[:1] if closed else []))
    if any((end - start).length_squared < 1e-12 for start, end in pairs):
        raise ValueError("Remove zero-length edges before converting.")
    return points, closed

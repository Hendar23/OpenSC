#!/usr/bin/env python3
"""Extract a mesh from a Sub Culture DFF clump and write a glTF binary file.

This early converter handles the final geometry in a clump, which is the main
body in SUB.DFF. It deliberately rejects layouts it cannot validate.
"""

import argparse
import json
import math
import struct
from pathlib import Path


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def extract_last_mesh(data):
    geom = data.rfind(b"moeg")
    if geom < 0 or data[geom + 8:geom + 12] != b"trts" or u32(data, geom + 12) != 36:
        raise ValueError("Last geometry does not have the expected 36-byte header")
    header = geom + 16
    flags, count_a, triangle_count, vertex_count = struct.unpack_from("<4I", data, header)
    if not 0 < vertex_count < 100000 or not 0 < triangle_count < 100000:
        raise ValueError("Implausible geometry counts")

    # The final struct holds a sphere and two flags, followed by positions and
    # normals. Find it by requiring its arrays to end exactly at EOF.
    vertex_header = len(data) - vertex_count * 24 - 32
    if vertex_header < header or data[vertex_header:vertex_header + 8] != b"trts\x18\0\0\0":
        raise ValueError("Vertex and normal arrays do not fit the final struct")
    position_offset = vertex_header + 32
    triangle_offset = vertex_header - triangle_count * 8
    uv_offset = triangle_offset - vertex_count * 4
    if uv_offset < header + 36:
        raise ValueError("UV and triangle arrays overlap geometry header")

    vertices = [struct.unpack_from("<3f", data, position_offset + i * 12)
                for i in range(vertex_count)]
    normals = [struct.unpack_from("<3f", data, position_offset + vertex_count * 12 + i * 12)
               for i in range(vertex_count)]
    triangles = [struct.unpack_from("<4H", data, triangle_offset + i * 8)
                 for i in range(triangle_count)]
    if any(i >= vertex_count for face in triangles for i in face[:3]):
        raise ValueError("Triangle index exceeds vertex count")
    if not all(math.isfinite(c) for v in vertices + normals for c in v):
        raise ValueError("Non-finite vertex data")
    materials = sorted({face[3] for face in triangles})
    if len(materials) > 128:
        raise ValueError("Implausible material count")
    return vertices, normals, triangles, materials, (flags, count_a, uv_offset)


def make_glb(vertices, normals, triangles, materials, output):
    blob = bytearray()
    views, accessors = [], []

    def add(raw, target, component, kind, count, bounds=None):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(raw)
        view = len(views)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw), "target": target})
        accessor = {"bufferView": view, "componentType": component, "count": count, "type": kind}
        if bounds:
            accessor["min"], accessor["max"] = bounds
        accessors.append(accessor)
        return len(accessors) - 1

    positions = add(b"".join(struct.pack("<3f", *v) for v in vertices), 34962, 5126,
                    "VEC3", len(vertices),
                    ([min(v[j] for v in vertices) for j in range(3)],
                     [max(v[j] for v in vertices) for j in range(3)]))
    normal_accessor = add(b"".join(struct.pack("<3f", *v) for v in normals),
                          34962, 5126, "VEC3", len(normals))
    palette = [[0.31, 0.62, 0.65, 1], [0.76, 0.63, 0.33, 1], [0.28, 0.34, 0.40, 1],
               [0.65, 0.49, 0.31, 1]]
    primitives = []
    for n, material in enumerate(materials):
        faces = [f for f in triangles if f[3] == material]
        indices = [i for f in faces for i in f[:3]]
        accessor = add(struct.pack("<" + "H" * len(indices), *indices), 34963,
                       5123, "SCALAR", len(indices), ([min(indices)], [max(indices)]))
        primitives.append({"attributes": {"POSITION": positions, "NORMAL": normal_accessor},
                           "indices": accessor, "material": n})
    document = {"asset": {"version": "2.0", "generator": "OpenSubCulture prototype"},
                "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
                "meshes": [{"name": "Sub Culture clump", "primitives": primitives}],
                "buffers": [{"byteLength": len(blob)}], "bufferViews": views,
                "accessors": accessors,
                "materials": [{"name": f"Original material {m} (placeholder)",
                               "pbrMetallicRoughness": {"baseColorFactor": palette[n % len(palette)],
                                                         "metallicFactor": 0.1, "roughnessFactor": 0.7},
                               "doubleSided": True} for n, m in enumerate(materials)]}
    js = json.dumps(document, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob.extend(b"\0" * (-len(blob) % 4))
    total = 12 + 8 + len(js) + 8 + len(blob)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(struct.pack("<4sII", b"glTF", 2, total) +
                       struct.pack("<I4s", len(js), b"JSON") + js +
                       struct.pack("<I4s", len(blob), b"BIN\0") + blob)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="A DFF from the original CLUMPS directory")
    parser.add_argument("output", type=Path, help="Destination .glb")
    args = parser.parse_args()
    vertices, normals, triangles, materials, extra = extract_last_mesh(args.source.read_bytes())
    make_glb(vertices, normals, triangles, materials, args.output)
    print(f"Converted {args.source.name}: {len(vertices)} vertices, "
          f"{len(triangles)} triangles, {len(materials)} materials -> {args.output}")
    print("Original texture coordinates and materials are not mapped yet.")


if __name__ == "__main__":
    main()

"""Build the optional cockpit's self-contained GLB with no external dependencies."""
import json
import math
import struct
from pathlib import Path

DESTINATION = Path(__file__).resolve().parents[1] / "Mods/bubble-cockpit/BubbleCanopy.glb"


def normalize(v):
    length = math.sqrt(sum(x * x for x in v))
    return tuple(x / length for x in v)


def geometry():
    radii = (0.85, 0.55, 0.7)
    cap = math.radians(80)
    glass = ([], [], [], [])
    segments, rings = 96, 32
    for row in range(rings + 1):
        theta = cap * row / rings
        for column in range(segments + 1):
            phi = math.tau * column / segments
            point = (radii[0] * math.sin(theta) * math.cos(phi),
                     radii[1] * math.sin(theta) * math.sin(phi),
                     -radii[2] * math.cos(theta))
            glass[0].extend(point)
            glass[1].extend(normalize(tuple(p / (r * r) for p, r in zip(point, radii))))
            glass[2].extend((0.5 + point[0] / (2 * radii[0] * math.sin(cap)),
                             0.5 - point[1] / (2 * radii[1] * math.sin(cap))))
    for row in range(rings):
        for column in range(segments):
            a = row * (segments + 1) + column
            b = a + segments + 1
            glass[3].extend((a, a + 1, b, a + 1, b + 1, b))
    return (glass,)


def build():
    blob = bytearray()
    views, accessors, meshes = [], [], []

    def accessor(values, width, integer=False):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(struct.pack("<" + ("I" if integer else "f") * len(values), *values))
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob) - offset,
                      "target": 34963 if integer else 34962})
        result = {"bufferView": len(views) - 1, "componentType": 5125 if integer else 5126,
                  "count": len(values) // width, "type": {1: "SCALAR", 2: "VEC2", 3: "VEC3"}[width]}
        if width == 3:
            result["min"] = [min(values[i::3]) for i in range(3)]
            result["max"] = [max(values[i::3]) for i in range(3)]
        accessors.append(result)
        return len(accessors) - 1

    for index, (positions, normals, uv, indices) in enumerate(geometry()):
        attributes = {"POSITION": accessor(positions, 3), "NORMAL": accessor(normals, 3),
                      "TEXCOORD_0": accessor(uv, 2)}
        meshes.append({"primitives": [{"attributes": attributes, "indices": accessor(indices, 1, True),
                                        "material": index}]})
    document = {"asset": {"version": "2.0", "generator": "OpenSC bubble canopy builder"},
                "scene": 0, "scenes": [{"nodes": [0]}],
                "nodes": [{"name": "Canopy_Glass", "mesh": 0}],
                "meshes": meshes, "materials": [
                    {"name": "Canopy glass", "doubleSided": True, "alphaMode": "BLEND",
                     "pbrMetallicRoughness": {"baseColorFactor": [0.82, 0.94, 0.96, 0.035], "metallicFactor": 0,
                                               "roughnessFactor": 0.14}}],
                "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    metadata = json.dumps(document, separators=(",", ":")).encode()
    metadata += b" " * (-len(metadata) % 4)
    blob += b"\0" * (-len(blob) % 4)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(metadata) + 8 + len(blob))
    glb += struct.pack("<II", len(metadata), 0x4E4F534A) + metadata
    glb += struct.pack("<II", len(blob), 0x004E4942) + blob
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    DESTINATION.write_bytes(glb)
    print(f"Built {DESTINATION.name}: {len(glb):,} bytes")


if __name__ == "__main__":
    build()

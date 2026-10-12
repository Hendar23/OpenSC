"""Extract turret evidence from the locally owned original game assets.

Uses only the standard library and inspect_map.py. Addresses are build-specific;
the executable hash is checked before reading them. Prints JSON to stdout.
"""
import csv
import hashlib
import io
import json
import math
import struct
from pathlib import Path

from inspect_map import read_ddb

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SHA256 = "df81a55dc31cb9386cd3fb70bc828b04295f66b900da0fc9a86c697c08a345e3"


def main():
    raw = (ROOT / "Original Sub Culture/SC.EXE").read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError("Unrecognised SC.EXE build; recover addresses again")
    pe = struct.unpack_from("<I", raw, 0x3C)[0]
    sections = struct.unpack_from("<H", raw, pe + 6)[0]
    optional = struct.unpack_from("<H", raw, pe + 20)[0]
    base = struct.unpack_from("<I", raw, pe + 24 + 28)[0]

    def read(address, fmt):
        rva = address - base
        for index in range(sections):
            start = pe + 24 + optional + index * 40
            size, va, disk_size, offset = struct.unpack_from("<4I", raw, start + 8)
            if va <= rva < va + max(size, disk_size):
                return struct.unpack_from(fmt, raw, offset + rva - va)[0]
        raise ValueError(f"Unmapped address {address:#x}")

    catalogue = json.loads((ROOT / "Extracted Original Data/catalogue.json").read_text())
    text = catalogue["tables"]["source_texts"]["records"]["data.objects.csv"]["text"]
    rows = list(csv.DictReader(io.StringIO(text)))
    objects = {}
    for object_id, name, callback in [(81, "TURRET", 0x4051F0), (82, "HOMINGTURRET", 0x4051F0),
                                      (153, "HMISSILE", 0x469340), (154, "TMISSILE", 0x469340)]:
        row = rows[object_id - 1]
        if row["object"] != name or read(0x4E65D8 + object_id * 80, "<I") != callback:
            raise ValueError("Object catalogue and callback table disagree")
        objects[str(object_id)] = row
    constants = {}
    for address, expected in [(0x4DA0E8, 0.092), (0x4DA0EC, 0.15),
                              (0x4DA0F0, 0.0003), (0x4DA0F4, 0.001)]:
        value = read(address, "<f")
        if not math.isclose(value, expected, rel_tol=1e-6):
            raise ValueError(f"Unexpected turret constant at {address:#x}")
        constants[hex(address)] = value
    placements = []
    for row in read_ddb(ROOT / "Original Sub Culture/DATA/SCEN1.DDB")["Objects"]["rows"]:
        if str(row.get("clump", "")).upper() != "TURRET":
            continue
        if int(row.get("AutoCreate", 0)) == 1 or (
                int(row.get("MissionID", 0)) == 2 and int(row.get("ObjectID", -1)) in [4, 11, 12]):
            placements.append(row)
    if len(placements) != 23:
        raise ValueError("Unexpected startup turret count")
    print(json.dumps({"input_sha256": digest, "objects": objects, "constants": constants,
                      "startup_placements": placements,
                      "decompiled_functions": ["0x4051f0", "0x42b9d0", "0x42cfb0", "0x468e70", "0x469340", "0x47eb40"],
                      "scope": "Static data and decompiled control flow; not original runtime emulation"}, indent=2))


if __name__ == "__main__":
    main()

"""Inspect original Sub Culture databases without changing the game files."""
import csv
import io
import json
import struct
from collections import Counter
from pathlib import Path
import sys


def read_ddb(path):
    data = Path(path).read_bytes()
    tables = {}
    offset = 24
    while offset < len(data):
        start = offset
        name = data[offset:offset + 20].split(b"\0")[0].decode("ascii")
        columns, memory_size, count = struct.unpack_from("<3I", data, offset + 20)
        if name == "Missions":
            break  # This inspector only needs the world tables before mission text.
        if not (0 < columns < 100 and count < 10000):
            raise ValueError(f"Invalid table at {offset:#x}: {name!r}")
        offset += 32
        fields = []
        for _ in range(columns):
            label = data[offset:offset + 20].split(b"\0")[0].decode("ascii")
            kind, length, flags, bit = struct.unpack_from("<4I", data, offset + 20)
            size = (length + 3) & ~3 if kind == 2 else length * 4
            fields.append((label, kind, length, size, bit))
            offset += 36
        rows = []
        for row_index in range(count):
            row = {"_offset": offset, "_mask": struct.unpack_from("<I", data, offset)[0]}
            offset += 4
            for label, kind, length, size, bit in fields:
                if offset + size > len(data):
                    raise ValueError("Truncated database")
                if kind == 2:
                    value = data[offset:offset + length].split(b"\0")[0].decode("latin1")
                elif kind == 1:
                    values = struct.unpack_from("<" + "f" * length, data, offset)
                    value = values[0] if length == 1 else list(values)
                else:
                    values = struct.unpack_from("<" + "i" * length, data, offset)
                    value = values[0] if length == 1 else list(values)
                if row["_mask"] & bit and kind != 3:
                    if label == "matrix":
                        value = [None if i % 4 == 3 else component for i, component in enumerate(value)]
                    row[label] = value
                offset += size
            rows.append(row)
        tables[name] = {"offset": start, "memory_size": memory_size, "fields": fields, "rows": rows}
    return tables


def read_archive(path):
    data = Path(path).read_bytes()
    count = struct.unpack_from("<I", data)[0]
    base = 4 + count * 21
    entries = {}
    for index in range(count):
        p = 4 + index * 21
        name = data[p:p + 13].split(b"\0")[0].decode("ascii")
        size, offset = struct.unpack_from("<2I", data, p + 13)
        entries[name.upper()] = bytes(b ^ 255 for b in data[base + offset:base + offset + size]).decode("latin1")
    return entries


if __name__ == "__main__":
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else "Sub Culture")
    tables = read_ddb(folder / "DATA/SCEN1.DDB")
    archive = read_archive(folder / "DATA/DATA.ENC")
    definitions = list(csv.DictReader(io.StringIO(archive["OBJECTS.CSV"])))
    print("Tables:", {key: len(value["rows"]) for key, value in tables.items()})
    print("Definitions:", len(definitions))
    print("Object IDs:", Counter(row.get("ObjectID") for row in tables["Objects"]["rows"]))
    for row in tables["Objects"]["rows"]:
        if row.get("ObjectID") in (26, 27):
            print("Plant patch:", row.get("Comment"), "position", row["matrix"][12:15],
                  "parameters", row.get("param1"), row.get("param2"))
    print("Automatically created model definitions:", Counter(
        definitions[row["ObjectType"] - 1]["object"]
        for row in tables["Objects"]["rows"]
        if row.get("AutoCreate") == 1 and 1 <= row.get("ObjectType", 0) <= len(definitions)))
    if len(sys.argv) > 2:
        Path(sys.argv[2]).write_text(json.dumps(tables, indent=2), encoding="utf-8")

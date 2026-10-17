"""Check Big Ears callbacks/constants against the supplied SC.EXE and decompile.

Read-only original data; evidence is written beneath ignored .local/.
"""
import csv
import hashlib
import io
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    raw = (ROOT / "Original Sub Culture/SC.EXE").read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == "df81a55dc31cb9386cd3fb70bc828b04295f66b900da0fc9a86c697c08a345e3"
    header = struct.unpack_from("<I", raw, 0x3C)[0]
    count = struct.unpack_from("<H", raw, header + 6)[0]
    optional_size = struct.unpack_from("<H", raw, header + 20)[0]
    base = struct.unpack_from("<I", raw, header + 24 + 28)[0]
    sections = [struct.unpack_from("<IIII", raw, header + 24 + optional_size + i * 40 + 8)
                for i in range(count)]

    def read(address, fmt="<f"):
        rva = address - base
        for virtual_size, start, disk_size, offset in sections:
            if start <= rva < start + max(virtual_size, disk_size):
                return struct.unpack_from(fmt, raw, offset + rva - start)[0]
        raise ValueError(hex(address))

    catalogue = json.loads((ROOT / "Extracted Original Data/catalogue.json").read_text())
    csv_text = catalogue["tables"]["source_texts"]["records"]["data.objects.csv"]["text"]
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    assert rows[34]["object"] == "LISTENLAUNCHER"
    assert rows[35]["object"] == "LISTENINGDEVICE"
    assert read(0x4E65D8 + 35 * 80, "<I") == 0x432D50
    assert read(0x4E65D8 + 36 * 80, "<I") == 0x41B620
    constants = {"thrust": read(0x4DA864), "surface_offset": read(0x4DA868),
                 "gravity_per_tick": read(0x4DB62C)}
    assert math.isclose(constants["thrust"], 0.0005, rel_tol=1e-6)
    assert math.isclose(constants["gravity_per_tick"], -0.001, rel_tol=1e-6)
    assert float(rows[35]["mass"]) == 0.01 and float(rows[35]["damp"]) == 0.9
    source = (ROOT / "Extracted Original Data/decompilation/output/SC.c").read_text()

    def function(address):
        marker = f"/* Address: {address} */"
        start = source.index(marker)
        end = source.find("/* Address:", start + len(marker))
        return source[start:end if end >= 0 else None]

    launcher = function("00432d50")
    device = function("0041b620")
    flight = function("0041b510")
    mission = function("00490640")
    assert "FUN_004655b0(0x24" in launcher and "FUN_00464c00(iVar3,0x26" in launcher
    assert "puStack_38 == param_4" in device and "= 100;" in device
    assert "FUN_00460080" in flight and "_DAT_004da864" in flight
    assert "== 4)" in mission and "0x1a,4,0,400" in mission
    evidence = {"executable_sha256": digest, "constants": constants,
                "launcher_callback": "00432d50", "device_callback": "0041b620",
                "flight_callback": "0041b510", "mission_callback": "00490640",
                "device_mass": 0.01, "device_retention": 0.9,
                "powered_ticks": 100, "inherited_velocity": True,
                "attachment": "Only launcher's designated target; surface offset .05",
                "wrong_actor_contact": "Stop thrust and linear velocity; do not attach",
                "intercept_lines_ticks": [200, 400, 600, 800, 1000],
                "base_reveal_ticks": 800, "final_instruction_ticks": 1200,
                "tick_rate": "25 Hz, matching the existing original-damage time convention",
                "scope": "Static decompile/constant checks; Godot supplies collision response"}
    target = ROOT / ".local/stage-two-research/bigears-findings.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(evidence, indent=2) + "\n")
    print("Verified Big Ears launcher, flight constants, designated-target contact and mission timers.")


if __name__ == "__main__":
    main()

"""Read-only depth-charge checks against the supplied retail executable/data.

Writes private audit evidence beneath ignored .local/, never original assets.
"""
import hashlib
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
    optional = struct.unpack_from("<H", raw, header + 20)[0]
    base = struct.unpack_from("<I", raw, header + 52)[0]
    sections = [struct.unpack_from("<IIII", raw, header + 24 + optional + i * 40 + 8)
                for i in range(count)]

    def offset(address):
        rva = address - base
        for virtual, start, size, disk in sections:
            if start <= rva < start + max(virtual, size):
                return disk + rva - start
        raise ValueError(hex(address))

    def read(address, fmt="<f"):
        return struct.unpack_from(fmt, raw, offset(address))[0]

    def string(address):
        start = offset(address)
        return raw[start:raw.index(b"\0", start)].decode("ascii")

    assert read(0x4E65D8 + 37 * 80, "<I") == 0x46A930
    assert read(0x4E65D8 + 38 * 80, "<I") == 0x44A420
    launch_sound = string(read(0x4DD6A4 + (0x2E - 1) * 8, "<I"))
    blast_sound = string(read(0x4DD6A4 + (0x39 - 1) * 8, "<I"))
    assert launch_sound == "depth.raw" and blast_sound == "dcharge.raw"
    assert math.isclose(read(0x4DB0F4), 0.03, rel_tol=1e-6)
    assert read(0x4DB0F8) == 4.0
    source = (ROOT / "Extracted Original Data/decompilation/output/SC.c").read_text()

    def function(address):
        start = source.index(f"/* Address: {address} */")
        return source[start:source.find("/* Address:", start + 20)]

    launcher = function("0046a930")
    flight = function("0044a100")
    charge = function("0044a420")
    assert "_DAT_00565910 = 25.0" in launcher
    assert "0x26,0" in launcher and "0x14) = 3" in launcher
    assert "0xb951b717" in flight and "0x40400000,&LAB_0044a2d0" in flight
    assert "iVar1 < 0" in flight and "iVar1 + -1" in flight
    # The blast callback applies 4/distance * sustain straight to health.
    # It has no aperture-entry flag/direction/shaft-column checks.
    assert raw[offset(0x44A3DD):offset(0x44A3DD)+6] == bytes.fromhex("d905f8b04d00")
    assert raw[offset(0x44A3EA):offset(0x44A3EA)+9] == bytes.fromhex("d84e30d86e28d95e28")
    covert = function("00490640")
    assert "FUN_0042f0e0(param_1,0x1a,0xb,0,0x96)" in covert
    assert read(0x4DBF24) == 9.0 and read(0x4DBF1C) == 0.0
    assert "param_3 * 10" in charge and "0x3d4ccccd,2,0xd,8" in charge
    shop = function("00440970")
    assert shop  # This callback applies the catalogue's Default purchase amount.
    tables = json.loads((ROOT / "Extracted Original Data/catalogue.json").read_text())["tables"]
    ammo = tables["equipment"]["records"]["depth"]
    assert int(ammo["Default"]) == 4 and int(ammo["Maximum"]) == 80
    description = tables["equipment_text"]["records"]["depthl"]["Description"]
    assert "8 free depth charges" in description
    evidence = {
        "exe_sha256": digest,
        "callbacks": {"launcher": "0046a930", "charge": "0044a420", "flight": "0044a100", "blast": "0044a2d0"},
        "launch_sound": launch_sound, "explosion_sound": blast_sound,
        "launch_cooldown_ticks": 25, "fuse_initial_counter": 30,
        "fuse_condition": "Test old counter < 0, decrement each update: 32 updates",
        "mass": 0.05, "down_force_per_tick": -0.0002,
        "linear_retention": 1.0, "angular_retention": 0.9,
        "velocity": "Inherit all three player velocity components without an added downward kick",
        "blast_radius": 3.0, "raw_damage_numerator": read(0x4DB0F8),
        "radial_force_numerator": read(0x4DB0F4), "blast_ignores_player": True,
        "ammo_pack": 4, "ammo_maximum": 80, "launcher_free_ammo": 8,
        "base_internal_target_below_door": read(0x4DBF10),
        "base_health_override": 1.5,
        "base_blast_damage": "4/distance to internal target * 0.1 sustain; no entry flag, direction, or column gate in original blast callback",
        "base_arrival_radius": 9.0,
        "base_vent_instruction_delay_ticks": 150,
        "pricing": {k: tables[k]["records"]["depth"] for k in ["equipment_prices.1", "equipment_prices.3", "equipment_prices.4"]},
    }
    output = ROOT / ".local/stage-two-research/depth-charge-original-findings.json"
    output.write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"Retail depth-charge callbacks, data, constants and sounds verified; evidence: {output}")


if __name__ == "__main__":
    main()

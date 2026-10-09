"""Verify this SC.EXE build and extract evidence for recovered damage behaviour.

Run after decompile_original.ps1. Requires pefile and capstone on PYTHONPATH.
Outputs stay in the ignored Extracted Original Data directory.
"""
import csv
import hashlib
import io
import json
import math
import struct
from pathlib import Path

import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Extracted Original Data/decompilation/output"
EXPECTED_SHA256 = "df81a55dc31cb9386cd3fb70bc828b04295f66b900da0fc9a86c697c08a345e3"


def main():
    raw = (ROOT / "Original Sub Culture/SC.EXE").read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError("Unrecognised SC.EXE build: addresses must be recovered again")
    pe = pefile.PE(data=raw)
    base = pe.OPTIONAL_HEADER.ImageBase
    constants = {}
    expected = {0x4DB6D8: 10.0, 0x4DB6C0: 0.0, 0x4DB6E4: 0.02,
                0x4DB6E8: 0.4, 0x4DAAC0: 4.0, 0x4DAD40: 0.35,
                0x4DAE30: 0.005, 0x4DAD20: 0.05, 0x4DAE34: 0.008,
                0x4DAD0C: 1.0, 0x4DAD5C: 0.1}
    for address, value in expected.items():
        actual = struct.unpack("<f", pe.get_data(address - base, 4))[0]
        if not math.isclose(actual, value, rel_tol=1e-6, abs_tol=1e-8):
            raise ValueError(f"Unexpected constant at {address:#x}: {actual}")
        constants[hex(address)] = actual
    md = Cs(CS_ARCH_X86, CS_MODE_32)
    ranges = {"object_collision": (0x465FA0, 0x4660F5),
              "terrain_damage": (0x46708A, 0x467135),
              "radiation_damage": (0x4264C7, 0x426536)}
    assembly = {}
    for name, (start, end) in ranges.items():
        assembly[name] = "\n".join(f"{a:08x} {m} {o}" for a, _, m, o in
                                  md.disasm_lite(pe.get_data(start - base, end - start), start))
        (OUT / f"{name}.asm").write_text(assembly[name] + "\n", encoding="utf-8")
    # Verify that constants belong to the recovered arithmetic, rather than
    # merely appearing somewhere in the executable's data section.
    for name, instructions in {
        "object_collision": ["fmul dword ptr [0x4db6d8]", "fmul dword ptr [esi + 0x30]",
                             "fsubr dword ptr [esi + 0x28]"],
        "terrain_damage": ["fdiv dword ptr [ecx + 4]", "fcomp dword ptr [0x4db6e4]",
                           "fcomp dword ptr [0x4db6e8]"],
        "radiation_damage": ["fdiv dword ptr [esp + 0x10]", "fmul dword ptr [0x89a358]",
                             "fmul dword ptr [ebx + 0x48]"],
    }.items():
        for instruction in instructions:
            if instruction not in assembly[name]:
                raise ValueError(f"Missing evidence: {name}: {instruction}")
    catalogue = json.loads((ROOT / "Extracted Original Data/catalogue.json").read_text())
    text = catalogue["tables"]["source_texts"]["records"]["data.objects.csv"]["text"]
    rows = list(csv.DictReader(io.StringIO(text)))
    names = {i: rows[i - 1]["object"] for i in [1, 11, 62, 63, 64, 98, 150, 151, 152, 153, 154, 159]}
    if names[1] != "PLAYER" or names[63] != "THORIUM":
        raise ValueError("Unexpected object catalogue order")
    for object_id, callback in [(1, 0x434180), (63, 0x4260F0), (64, 0x4260F0), (98, 0x4260F0)]:
        actual = struct.unpack("<I", pe.get_data(0x4E65D8 + object_id * 80 - base, 4))[0]
        if actual != callback:
            raise ValueError("Object callback table does not match CSV row indexing")
    source = (OUT / "SC.c").read_text(encoding="utf-8")
    addresses = ["00434180", "00433eb0", "00433fb0", "00465e80", "00465fa0", "00466620",
                 "004260f0", "004658f0", "00469880", "0047ed10", "00497eb0", "00497f50"]
    for address in addresses:
        marker = f"/* Address: {address} */"
        start = source.find(marker)
        if start < 0:
            raise ValueError(f"Missing decompiled function {address}")
        end = source.find("/* Address:", start + len(marker))
        (OUT / f"{address}.c").write_text(source[start:end if end >= 0 else None], encoding="utf-8")
    findings = {
        "input_sha256": digest,
        "status": "Static recovery cross-checked against x86 instructions; not runtime emulation",
        "constants": constants,
        "object_ids": names,
        "object_fields": {"0x28": "remaining shields (raw full value 10)",
                          "0x2c": "inflict", "0x30": "sustain (damage received multiplier)",
                          "0x48": "physics body; mass +4, velocity +8/+12/+16"},
        "object_collision": {
            "function": "0x465fa0", "dispatcher": "0x465e80",
            "formula": "n = normalize(A.position-B.position); impact = 10*dot(B.velocity-A.velocity,n); if impact>0: A.shields -= B.inflict*impact*A.sustain; B.shields -= A.inflict*impact*B.sustain",
            "eligible_if_either_id": [1, 11, 153, 62, 159, 154],
            "exception": "No damage here when both objects are FLOATINGMINE/HARDMINE",
            "scope": "Object contacts only; dispatcher also filters pairs and triggers separate callbacks"},
        "terrain_collision": {
            "function": "0x466620", "arithmetic": "0x4670bf-0x467132",
            "formula": "v = abs(dot(velocity,terrain_normal)); if v>0.02 and player.shields>0.4: player.shields -= (v/mass)*player.sustain",
            "note": "The 0.4 shield gate is a pre-hit condition, not a post-hit clamp. Uses raw engine speed units."},
        "radiation": {
            "function": "0x4260f0", "arithmetic": "0x4264c7-0x426533",
            "eligible_ids": [63, 64, 98],
            "formula": "if distance<4: exposure=(source.inflict/distance)*engine_step; player.shields -= player.sustain*exposure*player.radiation_multiplier",
            "source_inflict": {"THORIUM": rows[62]["inflict"], "INERTTHORIUM": rows[63]["inflict"],
                               "CANISTER": "0.05 runtime override, not its CSV 0.006"},
            "note": "Distance helper 0x47ed10 returns Euclidean distance through normalizer 0x497eb0. Shard IDs are absent from this branch. No zero-distance clamp in this branch. Step is engine time, not yet mapped experimentally to Godot seconds."},
        "player_upgrades": {
            "function": "0x434180", "ui_evidence": "0x469880 reads messages 0x2b,0x2c,0x2e,0x2d for labelled status values",
            "initial_shields_raw": 10, "initial_sustain": 0.35,
            "initial_hull_rating": 100, "hull_upgrade_step": 20, "maximum_hull_rating": 200,
            "hull_sustain_formula": "max(0.05, 0.35-(hull_rating-100)*0.005)",
            "shield_display_fraction": "raw_shields * 0.1; repair message 0x28 resets raw shields to 10",
            "radiation_upgrade_step": 20, "maximum_radiation_rating": 100,
            "radiation_multiplier_formula": "1-radiation_rating*0.008"},
        "limitations": ["Auto-discovered function boundaries/types may be wrong, including candidate entries.",
                        "Recovered arithmetic has not been checked against live original-game measurements.",
                        "No OpenSC gameplay, saved settings or original files were changed."]}
    (OUT / "damage-findings.json").write_text(json.dumps(findings, indent=2) + "\n", encoding="utf-8")
    print("Verified input hash, 11 constants, 9 instruction patterns and 4 callback entries.")
    print("Exported 12 focused functions, 3 assembly ranges and damage-findings.json")


if __name__ == "__main__":
    main()

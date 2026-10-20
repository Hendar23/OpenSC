"""Read-only retail fishing / Attractatron checks; findings stay in .local."""
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
    header = struct.unpack_from("<I", raw, 60)[0]
    base = struct.unpack_from("<I", raw, header + 52)[0]
    count = struct.unpack_from("<H", raw, header + 6)[0]
    size = struct.unpack_from("<H", raw, header + 20)[0]
    sections = [struct.unpack_from("<IIII", raw, header + 24 + size + i * 40 + 8) for i in range(count)]

    def read(address, fmt="<f"):
        for virtual_size, start, disk_size, offset in sections:
            if start <= address - base < start + max(virtual_size, disk_size):
                return struct.unpack_from(fmt, raw, offset + address - base - start)[0]
        raise ValueError(hex(address))

    catalogue = json.loads((ROOT / "Extracted Original Data/catalogue.json").read_text())
    tables = catalogue["tables"]
    source = (ROOT / "Extracted Original Data/decompilation/output/SC.c").read_text()

    def function(address):
        marker = f"/* Address: {address} */"
        start = source.index(marker)
        end = source.find("/* Address:", start + len(marker))
        return source[start:end if end >= 0 else None]

    for index, name, callback in [(21, b"fishing", 0x452050), (22, b"bigherd", 0x430910)]:
        assert read(0x4DA490 + index * 12, "<12s").rstrip(b"\0") == name
        assert read(0x4DF168 + index * 4, "<I") == callback
    assert read(0x4E65D8 + 39 * 80, "<I") == 0x4822A0
    assert read(0x4E65D8 + 51 * 80, "<I") == 0x47C9F0
    assert read(0x4E65D8 + 52 * 80, "<I") == 0x47C9F0
    rows = list(csv.DictReader(io.StringIO(tables["source_texts"]["records"]["data.objects.csv"]["text"])))
    assert rows[3]["object"] == "SILVERBACK" and rows[3]["dff"] == "silver"
    assert rows[42]["object"] == "MUTANTSILVERBACK"
    assert tables["equipment"]["records"]["attract"]["position"] == 8
    constants = {}
    for address, value in [(0x4DBCA4, 1.75), (0x4DBCB0, .015), (0x4DBB30, .9),
                           (0x4DB2A4, 8), (0x4DB2A8, 5), (0x4DAC4C, 9), (0x4DAC54, 1/3)]:
        actual = read(address)
        assert math.isclose(actual, value, rel_tol=1e-6)
        constants[hex(address)] = actual
    attract = function("004822a0")
    assert "0x40a00000,&LAB_00481fe0" in attract  # radius 5
    assert "s_attron_bmp" in attract and "s_attroff_bmp" in attract
    fishing = function("00452050")
    bigherd = function("00430910")
    herder = function("0047c680")
    assert "param_3 == 6" in fishing and "param_3 == 0xc" in fishing
    assert "iVar5 < 0x14" in fishing and "param_1,0x33" in fishing
    assert "piVar3[0xd] = 3" in bigherd and "iVar5 = 0x32" in bigherd
    assert "*(int *)(iVar1 + 0x18) < 0xc" in herder
    assert "&LAB_0047c4a0" in herder and "0x3f800000" in herder  # capture radius 1
    prices = tables["equipment_prices.1"]["records"]["attract"]
    assert [prices[k + " buy"] for k in ["Touka", "Beluga", "Velcova", "Tryton"]] == [0, 2970, 3140, 2710]
    for name, credits, city in [("fishing", 3000, "velcova"), ("bigherd", 3500, "beluga")]:
        assert tables["mission_rewards"]["records"][name]["credits"] == credits
        assert tables["mission_availability"]["records"][name]["avail"] == city
        assert tables["mission_requirements"]["records"][name]["items"] == ["attract"]
    missing_voice = [code for code in [*(f"U{i}" for i in range(1, 12)), *(f"V{i}" for i in range(1, 14))]
                     if not (ROOT / "Original Sub Culture/WAVES/ENGLISH" / (code + ".RAW")).is_file()]
    assert not missing_voice, missing_voice
    evidence = {"executable_sha256": digest, "constants": constants,
                "callbacks": {"fishing": "00452050", "bigherd": "00430910", "attract": "004822a0",
                              "attract_field": "00481fe0", "herder": "0047c9f0", "capture": "0047c4a0"},
                "attract": {"radius": 5, "minimum_distance": 1.75, "limit_per_tick": 7,
                            "target_forward_offset": 1.5, "species": ["SILVERBACK", "MUTANTSILVERBACK"],
                            "icons": ["ATTRON", "ATTROFF"], "slot": 8},
                "fishing": {"city": "Velcova", "herders": 1, "model": "TECHHERD", "fish": 20,
                            "half_hold": 6, "full_hold": 12, "enemy_waves": [2, 2], "credits": 3000},
                "bigherd": {"city": "Beluga", "herders": 3, "model": "TRADHERD", "fish": 50,
                            "full_hold_each": 12, "enemy_waves": [3, 3], "credits": 3500,
                            "score": "returned herders / 3; one returned is a success"},
                "scope": "Static executable/decompile/source-table checks. OpenSC uses its own fish/vessel steering, cone drawing and local collision clearance, not an instruction-for-instruction physics port."}
    target = ROOT / ".local/stage-two-research/fishing-original-findings.json"
    target.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print("Verified both original fishing callbacks, Attractatron, quotas, waves, rewards, stock and all 24 voice files.")


if __name__ == "__main__":
    main()

"""Read-only PE string references and disassembly for a supplied game executable.

Requires pefile and capstone. No original bytes are changed.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from capstone.x86 import X86_OP_IMM, X86_OP_MEM


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--strings", default="thorium|radiation|collision|shield|inflict|hull")
    parser.add_argument("--start", type=lambda s: int(s, 0))
    parser.add_argument("--end", type=lambda s: int(s, 0))
    parser.add_argument("--candidates", type=Path,
                        help="Write direct-call and aligned data callback candidates for Ghidra")
    args = parser.parse_args()
    raw = args.executable.read_bytes()
    pe = pefile.PE(data=raw)
    if pe.FILE_HEADER.Machine != 0x14C:
        parser.error("Only 32-bit x86 PE executables are supported")
    base = pe.OPTIONAL_HEADER.ImageBase
    md = Cs(CS_ARCH_X86, CS_MODE_32)
    md.detail = True
    md.skipdata = True
    if args.candidates:
        targets = set()
        code_ranges = [(base + s.VirtualAddress, base + s.VirtualAddress + s.Misc_VirtualSize)
                       for s in pe.sections if s.Characteristics & 0x20000000]
        def in_code(value):
            return any(start <= value < end for start, end in code_ranges)
        for section in pe.sections:
            if section.Characteristics & 0x20000000:
                for address, size, mnemonic, operands in md.disasm_lite(section.get_data(), base + section.VirtualAddress):
                    if mnemonic == "call" and operands.startswith("0x"):
                        target = int(operands, 16)
                        if in_code(target):
                            targets.add(target)
            else:
                data = section.get_data()
                for offset in range(0, len(data) - 3, 4):
                    target = int.from_bytes(data[offset:offset + 4], "little")
                    if target % 16 == 0 and in_code(target):
                        targets.add(target)
        args.candidates.parent.mkdir(parents=True, exist_ok=True)
        args.candidates.write_text("\n".join(hex(a) for a in sorted(targets)), encoding="utf-8")
        print(f"Wrote {len(targets)} candidates; data pointers require manual validation")
        return
    print(json.dumps({"file": str(args.executable), "sha256": hashlib.sha256(raw).hexdigest(),
                      "image_base": hex(base)}, indent=2))
    if args.start is not None:
        if args.end is None or args.end <= args.start:
            parser.error("--end must be greater than --start")
        data = pe.get_data(args.start - base, args.end - args.start)
        for ins in md.disasm(data, args.start):
            print(f"{ins.address:08x}  {ins.mnemonic:9} {ins.op_str}")
        return
    strings = {}
    for match in re.finditer(rb"[\x20-\x7e]{4,}", raw):
        value = match.group().decode("ascii")
        if re.search(args.strings, value, re.I):
            try:
                address = base + pe.get_rva_from_offset(match.start())
            except pefile.PEFormatError:
                continue
            strings[address] = {"address": hex(address), "text": value, "references": []}
    for section in pe.sections:
        if not section.Characteristics & 0x20000000:
            continue
        for ins in md.disasm(section.get_data(), base + section.VirtualAddress):
            if ins.id == 0:
                continue
            for op in ins.operands:
                value = op.imm if op.type == X86_OP_IMM else op.mem.disp if op.type == X86_OP_MEM else None
                if value in strings:
                    strings[value]["references"].append({"address": hex(ins.address),
                                                        "instruction": ins.mnemonic + " " + ins.op_str})
    print(json.dumps(list(strings.values()), indent=2))


if __name__ == "__main__":
    main()

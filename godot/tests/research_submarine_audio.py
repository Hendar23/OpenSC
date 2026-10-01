"""Read-only inspection of original sound metadata (temporary research tools)."""
import os, sys, struct, re
from pathlib import Path
sys.path.insert(0, str(Path(os.environ['TEMP']) / 'opensubculture-audio-research'))
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path = Path('Original Sub Culture/SC.EXE')
data = path.read_bytes()
pe = pefile.PE(str(path))
base = pe.OPTIONAL_HEADER.ImageBase
def va(offset): return base + pe.get_rva_from_offset(offset)
def offset(address): return pe.get_offset_from_rva(address - base)
def string(address):
    p = offset(address)
    return data[p:data.index(b'\0', p)].decode('ascii', errors='replace')
start = 0xdc098
for index in range(72):
    flag, pointer = struct.unpack_from('<II', data, start + index * 8)
    if flag not in (0, 1): break
    print(index, flag, string(pointer))

md = Cs(CS_ARCH_X86, CS_MODE_32)
md.skipdata = True
section = pe.sections[0]
code = list(md.disasm_lite(section.get_data(), base + section.VirtualAddress))
for a, _, m, o in code:
    if 0x435c46 <= a < 0x435eb3 or 0x409840 <= a < 0x409880: print(hex(a), m, o)
for address in [0x4dae1c,0x4dae24,0x4dae28,0x4dad08]:
    print('FLOAT',hex(address),struct.unpack_from('<f',data,offset(address))[0])

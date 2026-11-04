"""Bake conservative Godot LOD indices into a separate local Marine Biome GLB.

Keeps original vertex attributes, images, materials and nodes. Only triangle
indices change; source bounds are recorded for stable placement/culling. The
default allowlist contains reductions reviewed in native close-up comparisons.
The input is never edited. Requires NumPy and the local Godot executable.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

import numpy as np


def read_glb(path):
    data = path.read_bytes()
    if struct.unpack_from('<II', data) != (0x46546C67, 2):
        raise ValueError('Expected GLB version 2')
    length = struct.unpack_from('<I', data, 12)[0]
    return json.loads(data[20:20+length]), bytearray(data[28+length:])


def accessor(doc, binary, index):
    item = doc['accessors'][index]; view = doc['bufferViews'][item['bufferView']]
    components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[item['type']]
    dtype = {5123: '<u2', 5125: '<u4', 5126: '<f4'}[item['componentType']]
    if view.get('byteStride') or item.get('sparse'):
        raise ValueError('Interleaved/sparse geometry needs a separate converter')
    return np.frombuffer(binary, dtype=dtype, count=item['count']*components,
                         offset=view.get('byteOffset', 0)+item.get('byteOffset', 0)).reshape(-1, components).copy()


def compact(doc, binary):
    """Repack referenced views losslessly, discarding superseded index buffers."""
    if doc.get('animations') or doc.get('skins'):
        raise ValueError('This converter expects static scenery')
    used = set()
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            used.update(primitive['attributes'].values())
            if 'indices' in primitive: used.add(primitive['indices'])
            for target in primitive.get('targets',[]): used.update(target.values())
    accessors = sorted(used); mapping = {old:new for new,old in enumerate(accessors)}
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            primitive['attributes'] = {key:mapping[value] for key,value in primitive['attributes'].items()}
            if 'indices' in primitive: primitive['indices'] = mapping[primitive['indices']]
            for target in primitive.get('targets',[]):
                for key,value in target.items(): target[key] = mapping[value]
    doc['accessors'] = [doc['accessors'][index] for index in accessors]
    if any('sparse' in item for item in doc['accessors']): raise ValueError('Sparse accessor unsupported')
    views = sorted({a['bufferView'] for a in doc['accessors']} | {im['bufferView'] for im in doc['images']})
    mapping = {old:new for new,old in enumerate(views)}; result = bytearray(); packed = []
    for index in views:
        view = dict(doc['bufferViews'][index]); offset = view.get('byteOffset',0)
        while len(result)%4: result.append(0)
        view['byteOffset'] = len(result); packed.append(view)
        result.extend(binary[offset:offset+view['byteLength']])
    for item in doc['accessors']+doc['images']: item['bufferView'] = mapping[item['bufferView']]
    doc['bufferViews'] = packed
    return result


def bake(source, destination, work, allowed=None):
    doc, binary = read_glb(source)
    # Strip only the old GLB padding, never vertex/image data.
    binary = binary[:doc['buffers'][0]['byteLength']]
    plan = json.loads((work/'plan.json').read_text())
    plan = [entry for entry in plan if 'osc_original_aabb' not in doc['meshes'][entry['mesh']].get('extras',{})
            and (allowed is None or doc['meshes'][entry['mesh']]['name'] in allowed)]
    for entry in plan:
        primitive = doc['meshes'][entry['mesh']]['primitives'][0]
        original = accessor(doc, binary, primitive['indices']).flatten()
        positions = accessor(doc, binary, primitive['attributes']['POSITION'])
        uvs = accessor(doc, binary, primitive['attributes']['TEXCOORD_0'])
        prefix = work/str(entry['mesh'])
        imported = np.fromfile(str(prefix)+'.base.bin', dtype='<u4')
        reduced = np.fromfile(str(prefix)+'.indices.bin', dtype='<u4')
        imported_positions = np.fromfile(str(prefix)+'.positions.bin', dtype='<f4').reshape(-1,3)
        imported_uvs = np.fromfile(str(prefix)+'.uvs.bin', dtype='<f4').reshape(-1,2)
        if not np.array_equal(positions, imported_positions) or not np.array_equal(uvs, imported_uvs):
            raise ValueError('Importer changed vertex order/attributes: '+entry['name'])
        if np.array_equal(imported, original): pass
        elif np.array_equal(imported.reshape(-1,3)[:,[0,2,1]].flatten(), original):
            reduced = reduced.reshape(-1,3)[:,[0,2,1]].flatten()
        else: raise ValueError('Unexpected source winding/order: '+entry['name'])
        if len(reduced)%3 or reduced.max() >= len(positions): raise ValueError('Invalid reduced indices')
        while len(binary)%4: binary.append(0)
        dtype = '<u2' if len(positions) <= 65535 else '<u4'
        encoded = reduced.astype(dtype).tobytes()
        view = len(doc['bufferViews'])
        doc['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':len(encoded),'target':34963})
        binary.extend(encoded)
        index = len(doc['accessors'])
        doc['accessors'].append({'bufferView':view,'componentType':5123 if dtype=='<u2' else 5125,
                                 'count':len(reduced),'type':'SCALAR'})
        primitive['indices'] = index
        doc['meshes'][entry['mesh']].setdefault('extras',{})['osc_original_aabb'] = entry['source_aabb']
    binary = compact(doc,binary)
    doc['buffers'] = [{'byteLength':len(binary)}]
    encoded = json.dumps(doc,separators=(',',':')).encode(); encoded += b' '*(-len(encoded)%4)
    binary += b'\0'*(-len(binary)%4)
    result = struct.pack('<III',0x46546C67,2,28+len(encoded)+len(binary))
    result += struct.pack('<II',len(encoded),0x4E4F534A)+encoded
    result += struct.pack('<II',len(binary),0x004E4942)+binary
    destination.write_bytes(result)
    report = {'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
              'output_sha256':hashlib.sha256(result).hexdigest(),'models':plan,
              'triangles_removed':sum(e['before']-e['after'] for e in plan)}
    (work/'report.json').write_text(json.dumps(report,indent=2))
    print(f"Reduced {len(plan)} heavy meshes; removed {report['triangles_removed']:,} source triangles.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--all-candidates',action='store_true',help='Create an unreviewed comparison candidate instead of the approved reductions')
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve(): parser.error('Output must differ from source')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    work = args.output.parent/'mesh-reduction'
    work.mkdir(exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    command = [str(args.engine.resolve()),'--headless','--audio-driver','Dummy','--path',str(root/'godot'),
               '--script','res://../tools/optimize_marine_meshes.gd','--log-file',str(work/'worker.log'),
               '--','--source='+str(args.source.resolve()),'--output='+str(work.resolve())]
    completed = subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120,
                               creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if completed.returncode or re.search(r'(?m)^(?:SCRIPT )?ERROR:',completed.stdout+completed.stderr):
        raise RuntimeError(completed.stdout+completed.stderr)
    approved = None if args.all_candidates else set(json.loads(Path(__file__).with_name('marine_mesh_reductions.json').read_text()))
    bake(args.source,args.output,work,approved)


if __name__ == '__main__': main()

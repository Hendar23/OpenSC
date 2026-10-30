"""Read the owner's Corals OBJ archive without importing its example scenes."""
import io
from pathlib import Path
import zipfile

from PIL import Image


# Tall blue finger corals and yellow tube sponges, including grouped exports.
# Explicit names: nearby Coral1/3/4 labels also include unrelated short corals.
HALF_SIZE_MODELS = {
    ('Corals', 'Coral1_1_1'),
    ('Corals', 'Coral3_1'), ('Corals', 'Coral3_2'),
    ('CoralGroups', 'Coral1_G3'), ('CoralGroups', 'Coral1_G1'),
    ('CoralGroups', 'Coral1_G2_1'),
    ('CoralGroups', 'Coral4_G3'), ('CoralGroups', 'Coral4_G2'),
    ('CoralGroups', 'Coral3_G1_1')}


def obj_parts(data):
    """Split global-index OBJ objects, preserving authored corner normals/UVs."""
    positions, normals, uvs = [], [], []
    parts = []
    current = None
    material = None
    for line in data.decode('utf-8-sig').splitlines():
        values = line.split()
        if not values:
            continue
        kind = values[0]
        if kind == 'v': positions.append(tuple(map(float, values[1:4])))
        elif kind == 'vn': normals.append(tuple(map(float, values[1:4])))
        elif kind == 'vt': uvs.append(tuple(map(float, values[1:3])))
        elif kind == 'o':
            current = {'name': values[1], 'vertices': [], 'normals': [], 'uvs': [], 'material': None}
            parts.append(current)
        elif kind == 'usemtl': material = values[1]
        elif kind == 'f':
            if current is None: raise ValueError('Coral faces have no object name')
            if current['material'] not in (None, material):
                raise ValueError('Expected one material per coral object')
            current['material'] = material
            corners = [tuple(int(index) for index in value.split('/')) for value in values[1:]]
            for index in range(1, len(corners) - 1):
                for vi, ti, ni in (corners[0], corners[index], corners[index + 1]):
                    current['vertices'].append(positions[vi - 1 if vi > 0 else vi])
                    current['normals'].append(normals[ni - 1 if ni > 0 else ni])
                    u, v = uvs[ti - 1 if ti > 0 else ti]
                    current['uvs'].append((u, 1 - v))
    return parts


def append_corals(builder, source):
    entries = []
    with zipfile.ZipFile(source) as outer:
        with zipfile.ZipFile(io.BytesIO(outer.read('Corals_OBJ.zip'))) as archive:
            textures = {}
            for document in ('Corals', 'CoralGroups', 'Seaweeds'):
                materials = {}
                current = None
                for line in archive.read(document + '.mtl').decode('utf-8-sig').splitlines():
                    if line.startswith('newmtl '): current = line.split(maxsplit=1)[1]
                    elif line.startswith('map_Kd '):
                        # Source MTLs contain the author's absolute Windows paths.
                        filename = line.replace('\\', '/').rsplit('/', 1)[-1]
                        if filename not in textures:
                            image = Image.open(io.BytesIO(archive.read('Textures/' + filename))).convert('RGBA')
                            image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
                            png = io.BytesIO(); image.save(png, format='PNG', optimize=True)
                            texture_id = 'CoralsPack_' + Path(filename).stem
                            builder.material(texture_id, png.getvalue())
                            textures[filename] = texture_id
                        materials[current] = textures[filename]
                for part in obj_parts(archive.read(document + '.obj')):
                    vertices = part['vertices']
                    if not vertices: continue
                    low = [min(v[i] for v in vertices) for i in range(3)]
                    high = [max(v[i] for v in vertices) for i in range(3)]
                    width = max(high[0] - low[0], high[2] - low[2])
                    if width <= 0: raise ValueError('Coral has no horizontal extent')
                    center = ((high[0] + low[0]) / 2, low[1], (high[2] + low[2]) / 2)
                    fitted = [tuple((v[i] - center[i]) / width for i in range(3)) for v in vertices]
                    name = 'CoralsPack_' + document + '_' + part['name']
                    builder.model(name, (fitted, part['normals'], part['uvs'], materials[part['material']]))
                    entry = {'node': name, 'size': 2.0 if document in ('CoralGroups', 'CoralRocks') else 1.5,
                             'weight': 1.0, 'upright': document != 'CoralRocks'}
                    if document != 'CoralRocks': entry['ground_clearance'] = 0.005
                    if document == 'Seaweeds':
                        entry.update(size=2.5 * width / (high[1] - low[1]), sway=True)
                    if (document, part['name']) in HALF_SIZE_MODELS: entry['size'] *= 0.5
                    if (high[1] - low[1]) / width < 0.18: entry['ground_clearance'] = 0.08
                    entries.append(entry)
    return entries

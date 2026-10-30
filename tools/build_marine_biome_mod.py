"""Convert the owner's local marine archives into a self-contained scenery mod.

Requires Pillow. Source archives remain untouched; no downloads are performed.
"""
from pathlib import Path
import argparse
import io
import json
import struct
import zipfile
from PIL import Image


BIOME_MATERIALS = {
    "MAT_Sea_Shells": "seaShells", "MAT_Coral_Table": "Coral_Table",
    "MAT_Coral_Whip": "Coral_Whip", "MAT_Urchin": "Urchin_DefaultColor",
    "MAT_Sea_Barnacle": "Barnacles", "MAT_Coral_Plate": "Plate_Coral",
    "MAT_Feather_Star": "Feather_Star"}
PLANT_MATERIALS = {
    "MAT_Christmas_treeWorm": "Christmas_TreeWorm", "MAT_Coral_Finger": "Coral_Finger",
    "MAT_Coral_Sea_Fan": "Coral_Sea_Fan", "MAT_Coral_Staghorn": "Coral_Staghorn",
    "MAT_Coral_Sticks": "Coral_Sticks", "MAT_eelGrass": "eelGrass", "MAT_Kelp": "Kelp",
    "MAT_Scatter_Plant": "Scatter_Plant", "MAT_Scatter_Plant_Green": "Scatter_Plant_Alt_Green"}
# Closest silhouettes, fitted to measured released-game plant heights and bases.
# The single reed also keeps its narrow original footprint.
REPLACEMENTS = {
    "reed": ("SM_ocean_Kelp_leaf_05", 3.0, 0.0, 0.2),
    "bush1": ("SM_ocean_Kelp_02", 3.0, 0.0, None),
    "bush2": ("SM_ocean_coralSticks_02", 4.0, 0.0005, None),
    "bush3": ("SM_ocean_eelGrass_02", 3.0, 0.0004, None),
    "bush4": ("SM_ocean_coralFan_04", 4.5, 0.0006, None)}

# Visible stem feet measured against the embedded alpha-cutout texture, in
# normalized mesh coordinates. Bounding-box bottoms include transparent cards.
FAN_ANCHORS = {
    "SM_ocean_coralFan_01": [-0.01117925, 0.00726041, 0.00704644],
    "SM_ocean_coralFan_02": [0.04864965, 0.00310046, 0.00465726],
    "SM_ocean_coralFan_03": [0.11516809, 0.00537871, 0.00590710],
    "SM_ocean_coralFan_04": [0.07388929, 0.02242095, 0.00607412],
    "SM_ocean_coralFan_05": [-0.04682736, 0.02243672, -0.07338847],
    "SM_ocean_coralFan_06": [0.06459410, 0.04130854, 0.06174954],
    "SM_ocean_coralFan_07": [-0.05735211, 0.03174572, 0.11019383]}


def read_obj(data):
    positions, normals, uvs, vertices, texcoords, vertex_normals = [], [], [], [], [], []
    material = None
    for line in data.decode().splitlines():
        values = line.split()
        if not values:
            continue
        if values[0] == "v": positions.append(tuple(map(float, values[1:4])))
        elif values[0] == "vn": normals.append(tuple(map(float, values[1:4])))
        elif values[0] == "vt": uvs.append(tuple(map(float, values[1:3])))
        elif values[0] == "usemtl":
            if material is not None and material != values[1]:
                raise ValueError("Expected a single material per scenery model")
            material = values[1]
        elif values[0] == "f":
            corners = [tuple(int(i) for i in v.split('/')) for v in values[1:]]
            for i in range(1, len(corners) - 1):
                for vi, ti, ni in (corners[0], corners[i], corners[i + 1]):
                    vertices.append(positions[vi - 1]); vertex_normals.append(normals[ni - 1])
                    u, v = uvs[ti - 1]; texcoords.append((u, 1 - v))
    # Both supplied OBJ exports are Y-up. Normalize their base and horizontal width.
    low = [min(v[i] for v in vertices) for i in range(3)]
    high = [max(v[i] for v in vertices) for i in range(3)]
    width = max(high[0] - low[0], high[2] - low[2])
    center = ((high[0] + low[0]) / 2, low[1], (high[2] + low[2]) / 2)
    vertices = [tuple((v[i] - center[i]) / width for i in range(3)) for v in vertices]
    return vertices, vertex_normals, texcoords, material


class GlbBuilder:
    def __init__(self):
        self.binary = bytearray()
        self.material_ids = {}
        self.doc = {"asset": {"version": "2.0", "generator": "OpenSC local marine converter"},
            "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [],
            "materials": [], "textures": [], "images": [], "samplers": [{"magFilter": 9729, "minFilter": 9987}],
            "bufferViews": [], "accessors": [], "buffers": []}

    def view(self, data, target=None):
        while len(self.binary) % 4: self.binary.append(0)
        result = {"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(data)}
        if target: result["target"] = target
        self.binary.extend(data)
        self.doc["bufferViews"].append(result)
        return len(self.doc["bufferViews"]) - 1

    def accessor(self, rows, kind):
        flat = [c for row in rows for c in row]
        item = {"bufferView": self.view(struct.pack('<' + 'f' * len(flat), *flat), 34962),
                "componentType": 5126, "count": len(rows), "type": kind}
        if kind == "VEC3":
            item["min"] = [min(r[i] for r in rows) for i in range(3)]
            item["max"] = [max(r[i] for r in rows) for i in range(3)]
        self.doc["accessors"].append(item)
        return len(self.doc["accessors"]) - 1

    def material(self, name, png):
        index = len(self.doc["images"])
        self.doc["images"].append({"bufferView": self.view(png), "mimeType": "image/png"})
        self.doc["textures"].append({"source": index, "sampler": 0})
        self.material_ids[name] = len(self.doc["materials"])
        self.doc["materials"].append({"name": name, "doubleSided": True, "alphaMode": "MASK", "alphaCutoff": 0.45,
            "pbrMetallicRoughness": {"baseColorTexture": {"index": index}, "metallicFactor": 0, "roughnessFactor": 0.9}})

    def model(self, name, geometry):
        vertices, normals, uvs, material = geometry
        # Match the exact exported float32 tuple, including seams/hard normals.
        # Preserve triangle/corner order; this changes storage, not geometry.
        unique, indices, positions, directions, texcoords = {}, [], [], [], []
        for position, normal, uv in zip(vertices, normals, uvs):
            key = struct.pack('<8f', *position, *normal, *uv)
            if key not in unique:
                unique[key] = len(positions)
                positions.append(position); directions.append(normal); texcoords.append(uv)
            indices.append(unique[key])
        attrs = {"POSITION": self.accessor(positions, "VEC3"), "NORMAL": self.accessor(directions, "VEC3"), "TEXCOORD_0": self.accessor(texcoords, "VEC2")}
        short = len(positions) <= 65535  # glTF reserves the maximum index value.
        index_accessor = len(self.doc["accessors"])
        self.doc["accessors"].append({"bufferView": self.view(struct.pack('<' + ('H' if short else 'I') * len(indices), *indices), 34963),
            "componentType": 5123 if short else 5125, "count": len(indices), "type": "SCALAR"})
        index = len(self.doc["meshes"])
        self.doc["meshes"].append({"name": name, "primitives": [{"attributes": attrs, "indices": index_accessor, "material": self.material_ids[material]}]})
        self.doc["nodes"].append({"name": name, "mesh": index})
        self.doc["scenes"][0]["nodes"].append(index)

    def save(self, path):
        self.doc["buffers"] = [{"byteLength": len(self.binary)}]
        encoded = json.dumps(self.doc, separators=(',', ':')).encode()
        encoded += b' ' * (-len(encoded) % 4)
        binary = self.binary + b'\0' * (-len(self.binary) % 4)
        glb = struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary))
        glb += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
        glb += struct.pack('<II', len(binary), 0x004E4942) + binary
        path.write_bytes(glb)
        return len(glb)


def read_textures(outer, archive, folder, families):
    result = {}
    with zipfile.ZipFile(io.BytesIO(outer.read(archive))) as textures:
        for material, prefix in families.items():
            image = Image.open(io.BytesIO(textures.read(f"{folder}/TEX_{prefix}_BaseColor.tga"))).convert("RGBA")
            image.thumbnail((2048, 2048) if material == "MAT_Sea_Shells" else (1024, 1024), Image.Resampling.LANCZOS)
            png = io.BytesIO(); image.save(png, format="PNG", optimize=True)
            result[material] = png.getvalue()
    return result


def build(source: Path, destination: Path, plants: Path | None = None, corals: Path | None = None, density: float = 1.0):
    destination.mkdir(parents=True, exist_ok=True)
    builder = GlbBuilder()
    entries, assets = [], {}
    with zipfile.ZipFile(source) as outer:
        for material, png in read_textures(outer, "marineBiome_blender.zip", "marineBiome_blender/Textures", BIOME_MATERIALS).items():
            if material == "MAT_Sea_Barnacle": continue  # Used only by the removed barnacle rocks.
            builder.material(material, png)
        with zipfile.ZipFile(io.BytesIO(outer.read("obj.zip"))) as models:
            for name in sorted(models.namelist()):
                if not name.endswith(".obj"): continue
                stem = Path(name).stem
                if "Rock" in stem: continue
                if "Group" in stem or ("Montipora" in stem and not stem.endswith("01")) or ("Feather" in stem and not stem.endswith("01")): continue
                geometry = read_obj(models.read(name)); builder.model(stem, geometry)
                large = "Coral" in stem or "Feather" in stem or "Rock" in stem
                size = 2.4 if large else (0.65 if any(s in stem for s in ("Starfish", "Urchin", "Clam", "Seaslug")) else 0.3)
                entry = {"node": stem, "size": size, "weight": 1.0}
                if "Coral_Table_Acropora" in stem or "Coral_Plate_Montipora" in stem:
                    entry["ground_clearance"] = 0.08
                if "Coral_Whip" in stem: entry["upright"] = True
                entries.append(entry)
    if plants:
        with zipfile.ZipFile(plants) as outer:
            textures = read_textures(outer, "blender_OceanPlants.zip", "blenderMarinePlants/textures", PLANT_MATERIALS)
            for material, png in textures.items(): builder.material(material, png)
            with zipfile.ZipFile(io.BytesIO(outer.read("OBJ.zip"))) as models:
                selected = {}
                for name in sorted(models.namelist()):
                    if not name.endswith(".obj"): continue
                    stem = Path(name).stem
                    geometry = read_obj(models.read(name)); builder.model(stem, geometry)
                    sway = any(part in stem for part in ("Kelp", "eelGrass", "seaPlant", "scatterPlant"))
                    size = 1.2 if "Kelp" in stem else 1.5 if "Grass" in stem or "seaPlant" in stem else 0.7 if "scatterPlant" in stem or "treeWorm" in stem else 2.0
                    upright = sway or any(part in stem for part in ("coralFan", "coralFinger", "coralSticks", "staghornCoral", "treeWorm"))
                    entry = {"node": stem, "size": size, "weight": 1.0, "sway": sway, "upright": upright}
                    if stem in FAN_ANCHORS: entry['ground_anchor'] = FAN_ANCHORS[stem]
                    entries.append(entry)
                    if stem in {item[0] for item in REPLACEMENTS.values()}: selected[stem] = geometry
                for original, (name, height, base, width_limit) in REPLACEMENTS.items():
                    vertices, normals, uvs, material = selected[name]
                    y_scale = height / max(v[1] for v in vertices)
                    xz_scale = min(y_scale, width_limit) if width_limit else y_scale
                    anchor = FAN_ANCHORS.get(name, [0.0, 0.0, 0.0])
                    fitted = [((v[0] - anchor[0]) * xz_scale, (v[1] - anchor[1]) * y_scale + base,
                               (v[2] - anchor[2]) * xz_scale) for v in vertices]
                    fitted_normals = []
                    for normal in normals:
                        n = (normal[0] / xz_scale, normal[1] / y_scale, normal[2] / xz_scale)
                        length = sum(c*c for c in n) ** 0.5
                        fitted_normals.append(tuple(c / max(length, 1e-12) for c in n))
                    replacement = GlbBuilder(); replacement.material(material, textures[material])
                    replacement.model(name, (fitted, fitted_normals, uvs, material))
                    relative = f"plants/{original}.glb"
                    (destination / 'plants').mkdir(exist_ok=True)
                    replacement.save(destination / relative)
                    assets[f"model.{original}"] = {"file": relative, "forward_axis": "+Z"}
    if corals:
        from coral_pack import append_corals
        entries.extend(append_corals(builder, corals))
    size = builder.save(destination / 'marine-biome.glb')
    manifest = {"schema_version": 1, "id": "marine-biome", "name": "Marine Biome", "version": "0.3.1" if plants else "0.1.3",
        "description": "Scattered marine scenery and ocean plants by lugiagames. Replaces the five original plant models with matching ocean plants." if plants else "Scattered coral, shells, barnacles, starfish and urchins. Decorative scenery only.",
        "assets": assets, "scenery": {"file": "marine-biome.glb", "seed": 481516, "count": 10800 if plants else 3600, "patch_radius": 9.0, "models": entries}}
    manifest['scenery']['density'] = density
    if corals:
        manifest['version'] = '0.4.2'
        manifest['description'] += ' Includes additional corals, coral groups and seaweeds from the supplied Corals pack.'
    (destination / 'mod.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    provenance = ["Local conversion of Nature Assets - Marine Biome" + (" and Nature Assets - Ocean Plants." if plants else "."),
        "Original archives in Other resources are preserved.", "Converted from supplied Y-up OBJ geometry and Blender base-colour textures.",
        "No licence/author attribution found in inspected entries; redistribution permission unverified. Keep local."]
    if plants:
        provenance += [f"{original.upper()} -> {item[0]} (original height {item[1]}, base {item[2]})." for original, item in REPLACEMENTS.items()]
        provenance += ['Sea fan scatter anchors and BUSH4 replacement aligned to visible stem feet rather than transparent mesh bounds.',
                       'Decorative rocks omitted at owner request.']
    if corals:
        provenance += ['Additional local source: ' + corals.name + ' / Corals_OBJ.zip.',
            'Includes individually separated Corals, CoralGroups and Seaweeds; rocks and Ex demonstration scenes omitted.',
            'Source names retained with CoralsPack prefixes; shared base-colour atlases resized to 1024 pixels.',
            'Tall blue finger corals and yellow tube sponges (nine standalone/group variants) reduced to half size at owner request.',
            'No author or redistribution licence supplied in the inspected OBJ archive; keep local.']
    (destination / 'SOURCE.txt').write_text('\n'.join(provenance) + '\n', encoding='utf-8')
    print(f"Built {len(entries)} scenery variants, {len(assets)} original plant replacements, {size:,} GLB bytes in {destination}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--plants', type=Path, help='Optional Nature Assets - Ocean Plants archive')
    parser.add_argument('--corals', type=Path, help='Optional Corals archive')
    parser.add_argument('--density', type=float, default=1.0, help='Scenery density multiplier, 0 to 1')
    args = parser.parse_args()
    if not 0 <= args.density <= 1: parser.error('Density must be between 0 and 1')
    build(args.archive, args.destination, args.plants, args.corals, args.density)

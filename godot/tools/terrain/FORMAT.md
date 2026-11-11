# SCEN1 terrain assets

Set `assets["terrain.scen1"]` in `mod.json` to a `.oscterrain` file in the mod folder. The file supplies the complete static terrain. `map.scen1` still supplies the placements and other editable map data. Use the original world coordinate system and database offset if you want the original placements to line up.

The file starts with the four ASCII bytes `OCST`, then a little-endian `uint32` version. Version 1 has a header followed by one record per render chunk. Each record starts with the raw byte count and compressed byte count as two little-endian `uint32` values. The payload is `var_to_bytes(dictionary)` compressed with Godot's Zstandard mode. The reader accepts data types only.

The header has `bounds` (`AABB`), `surface_height` (number), `database_offset` (`Vector3`) and `chunks` (record count). Each chunk has a `slot` integer and a `cell` (`Vector2i`). Together these identify the chunk. The cell can group surfaces that should share a collision body. The `material` dictionary has `texture` and `mask` strings and a fallback `color`. Texture names resolve through the existing world texture loader and can be overridden by `texture.*` mods. Use empty strings when no texture or mask applies.

Terrain variants covering the same explored space can share an optional `exploration_signature` in the header. For a visual replacement of the original map, use `terrain-v1:` followed by the original BSP's SHA256, with the same map bounds and coordinate system. This preserves map reveal, discovered cities and landmark visits across variants. Omitting this field gives the asset its own exploration identity. An optional `exploration_aliases` array can list previous `terrain-asset-v1:<sha256>` save identities for migration. Installed terrain headers supply those aliases even when the mod is disabled. The high-poly baker writes the original map's shared identity.

The geometry fields are `vertices` and `normals` (`PackedVector3Array`), `uvs` (`PackedVector2Array`) and `indices` (`PackedInt32Array`). Use Godot's clockwise triangle order. An empty index array gives a triangle list. Set `coarse_count` to zero to use the same geometry for collision, navigation and rendering. For a detailed indexed mesh, an optional positive `coarse_count` takes the first N vertices as a nonindexed triangle list for collision, navigation and the distant render mesh. Set `lod_error` to a positive screen-space error when supplying that list.

`bake_high_poly.gd` uses the original BSP, the placement map and a local profile to generate the High-Poly Terrain asset. The optional profile and placement paths default to `high_poly_profile.json` and `Maps/scen1.json`.

```text
godot --headless --path godot --script res://tools/terrain/bake_high_poly.gd -- "<original game folder>" "<output.oscterrain>"
```

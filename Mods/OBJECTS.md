# Map objects and floating mines

The map editor has **Object types** and **Object groups**. Object types hold
shared size, health, explosion damage, blast impulse, explosion radius and trigger distance.
Group count and scatter radius belong exclusively to each placed group.

Select Floating Mine under Object types, or use **New object type** to make a
variant. Choose **Add object group**, set its position, count and radius, then
Apply properties and Save map. A count of one places the mine at the exact
centre. Larger counts scatter uniformly within a sphere. The map seed and
stable group ID reproduce the same placements in the editor and game.
Groups are stationary in the editor and never detonate there. Frame selection,
Shift-drag horizontally, Ctrl + Shift-drag vertically, duplication, deletion,
undo/redo and JSON export work for object groups.
No original mission mines are imported automatically.

The initial appearance is the original `MINE.BMP` with `MINEM.BMP` transparency.
The original `MINE.DFF` is also available by choosing 3D model. Size is the
maximum image/model diameter in world units; model replacements are centred
and fitted to that diameter. Image replacements preserve their aspect ratio.

Floating Mine starts with 0.5 health from the original FLOATINGMINE definition.
Damage defaults to **30**, based on a user test showing roughly 30% damage to
starting 100 shield strength. Explosion radius (2 units) and trigger distance
(0.75 units) are provisional OpenSC defaults, not recovered original rules.
Trigger distance measures submarine centre to mine centre; zero disables
proximity activation. Mines bob slightly, can be shot by the zapper, and
explode once using the original masked `EX1.BMP`–`EX12.BMP` animation and
positional explosion sound. The animation plays at 24 frames per second.
**Blast impulse** defaults to 300 N·s and pushes the submarine away from the
explosion, falling linearly to zero at the explosion radius. The resulting
speed depends on submarine mass; zero disables the push. Damage triggers a
short controller pulse, scaled by the existing rumble strength setting.
They expose the configured explosion damage/radius through a signal and call
`take_damage(amount, source_position)` on damage-capable bodies in range.
Submarine shields/damage are not implemented yet. Mines are recreated on
world reload; persistent destroyed-object state is future work. Adding or moving
objects does not invalidate saves. Loading requires the saved dock and inventory
items to exist, and places the submarine at the dock's current location. Replacing
terrain is also allowed; terrain signatures only decide whether to restore or
reset explored-map coverage.

## Replace the image or use a 3D model

Place a mod folder under Mods with one of these manifests. No original bitmap
or model needs to be copied into the mod.

Image replacement (PNG alpha supplies transparency; the original mask is ignored):

```json
{
  "schema_version": 1,
  "id": "my-mines",
  "name": "My mines",
  "assets": { "texture.mine": "mine.png" }
}
```

Model replacement (automatically replaces the billboard, even on existing maps):

```json
{
  "schema_version": 1,
  "id": "my-mines",
  "name": "My 3D mines",
  "assets": { "model.mine": "mine.glb" }
}
```

GLBs must be self-contained. DFF replacements also work. A model replacement
wins over an image replacement when both are enabled. Disable the model mod to
use the billboard again. Explosion audio can be replaced with the asset ID
`audio.object.mine.explosion` (WAV/OGG/MP3/RAW); the original fallback is
`WAVES/EXPLODE1.RAW`.

For a trigger radius that follows the displayed model's size, use a descriptor:

```json
"model.mine": { "file": "mine.glb", "trigger_distance": "model_radius" }
```

This sets proximity detonation to half the type's maximum diameter, including
model spikes. It follows editor size changes without replacing the map;
disabling the mod restores the map's trigger distance.

Types and placements live in the map JSON under `object_types` and
`object_groups`. Package that JSON using `map.scen1` to distribute stats and
placements with the same mod. Existing maps without these arrays gain the
Floating Mine type and an empty object group list when opened in the editor.

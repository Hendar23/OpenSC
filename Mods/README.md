# Modding OpenSubCulture

Use **Main menu → Mods** in the game or the top-row **Mods** button in the editor. Put each mod into
its own folder here, select it in the menu, and choose **Apply and reload**.
The game resets the world when applying mods. The viewer refreshes its previews.
Original files remain the fallback; disabling all mods restores the base assets.
After editing an enabled mod's file, choose **Mods → Apply and reload** again
to load the updated file, or restart the game.

Three examples are included, disabled by default:

- **Example: heavier movement** changes only mass and rotational drag.
- **Example: PNG submarine texture** uses the original pixels in PNG format.
  Replace its PNG to try your own artwork.
- **Example: GLB submarine** converts all six original parts and their materials
  into a self-contained GLB, preserving their appearance and propeller animation.

The last two are format examples, not new artwork. Their assets were derived
from your original files for this local project.

## A mod folder

```text
Mods/
  my-submarine/
    mod.json
    models/submarine.glb
    textures/submarine.png
```

Example manifest:

```json
{
  "schema_version": 1,
  "id": "my-submarine",
  "name": "My submarine",
  "version": "1.0",
  "description": "A new submarine and a little more mass.",
  "movement": { "mass": 125.0 },
  "assets": {
    "submarine.player": {
      "file": "models/submarine.glb",
      "scale": 1.0,
      "forward_axis": "-Z",
      "parts": {
        "left_pod": "MyHull/LeftPod",
        "right_pod": "MyHull/RightPod",
        "main_propeller": "MyHull/MainPropeller",
        "left_propeller": "MyHull/LeftPod/Propeller",
        "right_propeller": "MyHull/RightPod/Propeller"
      }
    },
    "texture.sub1": "textures/submarine.png"
  }
}
```

Use a unique lowercase ID containing letters, digits, dots, underscores or
hyphens. Keep it stable when changing the display name or version. Paths must
stay inside the mod folder. Unknown schema versions, duplicate IDs, missing
files and malformed entries are reported in the menu.

## Priority and fallback

Later enabled mods take priority when they change the same asset or movement
setting. **Earlier/Later** buttons change the order; the menu explains conflicts
before applying changes. Unrelated changes combine. Selection and priority are
saved across launches and shared by both apps; apply or restart the other app
to refresh it.

Invalid replacements fall back through lower-priority replacements to the
original asset. Load warnings appear when reopening the Mods menu. Mods in this
first version contain assets/configuration, without executable scripts.

## Stable IDs and modern assets

| ID | Meaning |
| --- | --- |
| `submarine.player` | Player submarine (`model.sub` is an alias) |
| `model.angel` | Angel fish |
| `model.bush1` | Bush asset |
| `model.docking` | Original docking port |
| `texture.sub1` | Original submarine skin |
| `audio.submarine.main_propeller` | Main propulsion loop (PROP3.RAW) |
| `audio.submarine.side_pods` | Side propulsion loop (PROP4.RAW) |
| `audio.submarine.pod_rotation` | Pod rotation motor (PROP1.RAW) |
| `audio.submarine.impact_hit1` | First random hull impact (HIT1.RAW, one-shot) |
| `audio.submarine.impact_hit3` | Second random hull impact (HIT3.RAW, one-shot) |
| `audio.submarine.impact_creaking` | Occasional delayed hull creak (CREAKING.RAW, one-shot) |
| `audio.docking.sequence` | Full docking/undocking background (DOCKING.RAW, loop) |
| `audio.docking.doors` | Start of hatch movement (DOCK.RAW, one-shot) |
| `audio.docking.door_stop` | Finished opening/closing (DOCKSHUT.RAW, one-shot) |

Other existing assets use `model.<clump name>` and `texture.<texture name>`,
without extensions. IDs are case-insensitive and remain the lookup contract
when replacement files have different names or formats. A brand-new ID does
not yet place an object in the world.

Models support self-contained **GLB 2.0** files; embed textures and buffers when
exporting. DFF replacements also work. Textures support PNG, JPEG, WebP, BMP
and RAS. Modern replacements supply their own alpha and can use a different
resolution from old masked textures. GLBs can contain their own PBR materials;
`texture.*` overrides apply to original-model and terrain materials. GLB mods
can also opt into texture overrides by adding `material_textures` to their
model entry, mapping zero-based GLB material indices to stable texture IDs:

```json
"material_textures": { "2": "texture.sub1", "4": "texture.sub1", "5": "texture.sub1" }
```

The GLB submarine example includes these bindings, so the PNG example works
with both the original submarine and the GLB replacement. Unbound materials
keep their embedded textures. If no usable texture override is enabled, bound
materials also keep their embedded textures. Material indices belong to the
particular GLB export; update the bindings if its material order changes.

The viewer opens GLBs directly and lists registered mod assets alongside the
base library. Original-model previews use enabled replacements and show their
source; assets belonging to disabled mods can be inspected directly.

Submarine and docking audio replacements support WAV, Ogg Vorbis, MP3 and RAW.
WAV/Ogg are recommended for clean loops. Looping roles repeat the complete
sample; supply audio with matching endpoints. Impact, creaking, moving-door and door-finish
roles play once. RAW uses the original 11025 Hz, 8-bit unsigned
mono format; modern formats carry their own sample rate and channels. For example:

```json
"assets": { "audio.submarine.main_propeller": "sounds/my-engine.wav" }
```

Apply reloads sound files as well as visuals. Disabling the mod restores the
original sound, and an unreadable replacement falls back to the next valid sample.
The earlier `audio.submarine.thrust` ID remains an alias for pod rotation.
Use **F6** to tune each layer's gain/pitch and loop smoothing, solo it, or preview
it while stationary. Saved/exported sound mixes are separate from movement.

## Submarine conventions

Export a GLB with its nose facing **-Z** by default. Set `forward_axis` to `+Z`
for a source facing the other way. `scale` changes visual size; the collision
sphere remains radius 0.54, independent of replacement model size. Piloting
applies a further 0.8 scale to the loaded model, matching the original ship.

`parts` maps animation roles to node paths in the imported scene. Copy the
included GLB example for a complete working hierarchy and mapping. Left/right
mean the physical sides while piloting. Place pivots correctly and align local
axes with the source hull: pods rotate around X and propellers around Z.
Nest each propeller under its pod so it tilts with the pod.

Unmapped parts remain static, while piloting still works. Automatic submarine
collision generation, skeleton animation mapping and alternate propulsion
arrangements are future extensions.

Static scenery replacements share original placement and collision loaders.
Fish/docking morph targets can use the existing stored-pose convention, but
arbitrary GLB skeleton animations and docking clips are not yet connected to
gameplay. A replacement docking port needs compatible morph poses to retain
the current docking sequence.

## Partial movement presets

Specify only values you want to change; untouched values inherit the player's
base tuning. All 22 tuning keys are supported:

```text
main_forward, main_reverse, side_thrust,
forward_speed, reverse_speed, vertical_speed,
forward_drag, lateral_drag, vertical_drag,
turn_acceleration, turn_speed, turn_drag, tilt_speed,
camera_distance, mass, water_resistance,
pitch_acceleration, pitch_speed, upright_strength, upright_damping,
propeller_spin_down, bubble_rate
```

Thrust uses newtons, mass uses kilograms, angular speeds/accelerations use
degrees per second/per second squared, and camera distance uses world units.
Values must be finite and nonnegative; mass is clamped to at least 1 kg and
camera distance to its supported range. Experiment in the tuning panel, then
copy relevant values from its export into the manifest.
`propeller_spin_down` is the time in seconds to coast from full spin to rest;
`bubble_rate` is bubbles per second per propeller at full spin. These affect
visuals rather than thrust forces. Replace the bubble sprite using `texture.bubble`;
it supplies its own alpha, while the original sprite uses `BUBBLEM.BMP`.

**Save settings** keeps a separate profile for each enabled-mod combination,
preserving base tuning. Changing a preset or source defaults refreshes that
combination's defaults. **Export settings** exports the complete effective
settings to a CFG file.

## Later extensions

This supports gradual replacement with modern assets. Original BSP/DDB files
still supply terrain, placements and cities. Modern map packs, new creature
definitions/spawns, missions, downloadable packages and an editor interface for
creating mod folders can build on this layer later.

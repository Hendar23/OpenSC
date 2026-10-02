# Map and wildlife editor

Launch the existing editor and choose **Map** at the top. It loads the original
terrain, scenery, plants and lights, plus an editable player spawn and seeded
wildlife groups. Original game files are never written.

Hold right mouse and use WASD to fly, Q/E to descend/ascend, and Shift to move
faster. Mouse wheel adjusts flight speed. Select from the entity list or click
near an entity's origin in the viewport. Double-click its list entry, or press
F, to frame it. Shift-drag moves horizontally; position fields handle vertical
movement. **Snap to seabed** uses terrain rather than the selected model.

Edit properties and press **Apply properties**. Add, duplicate and delete
entities using the sidebar. Undo/Redo also restore deleted original entities.
Ctrl+Z / Ctrl+Y and Ctrl+S work when the viewport has focus. Visibility filters
affect only the editor view. The terrain itself is read-only in this version.

**Creature types** define the model, mobility, group behaviour, submarine
response, speed, detection distance and scale range. Scale is a percentage of
the supplied model: 40–60 means 0.4–0.6 times its original size. **Wildlife groups**
place a type in the world, with population range, roaming radius, spawn chance
and optional size/behaviour overrides. 1–1 produces one creature.

Spawn chance is rolled once for the entire group at world load and again when
the submarine finishes docking. 0% never spawns; 100% always attempts to spawn.
Members must fit in clear water or above the seabed, so unsafe placements can
produce fewer creatures. All group markers remain selectable even when their
spawn roll fails. The map seed gives repeatable placement previews.

Wildlife starts stationary in the editor. **Simulate wildlife** enables movement.
Swimming, seabed crawling, loose shoals,
coordinated schools and fleeing/chasing the submarine are implemented. Defense
reacts to close hull contact. Attacking currently means pursuit; hull damage
and combat are future work.

Wildlife turns smoothly with bounded yaw and pitch. Creature properties expose
maximum turn speed and swim pitch; older definitions use 60°/s and 25°.

Swimming creatures set to **flee** make a short startle turn and speed burst
when the submarine approaches, then settle into normal fleeing. Creature type
properties control startle duration (0 disables), burst speed multiplier, and
startle turn speed. Defaults are 0.3 seconds, 2.8× swim speed, and 720°/s.
The burst accelerates the swimming animation too. Detection hysteresis and a
short cooldown prevent repeated flinching at the range boundary. Crawlers keep
their existing grounded fleeing movement.
The original turtle has rigid head/flipper parts rather than morph poses, so
it uses a gentle procedural swim cycle in both the asset preview and world.

**Save map** writes `Maps/scen1.json` beside this document. Restart the game or
apply/reload its mods to load it. The game retains the original world as its
foundation, applies entity overrides, and uses the authored wildlife groups.
Docking now shows a simple opaque docked screen before population changes;
press Y or controller A to undock. This screen can later become the dock UI.

Maps can also be packaged as mods. Export JSON into a mod folder and add this
entry to its `mod.json`:

```json
{
  "schema_version": 1,
  "id": "my-map",
  "name": "My map",
  "assets": { "map.scen1": "maps/scen1.json" }
}
```

Enabled map mods take priority over `Maps/scen1.json`, following the existing
mod order. The editor saves back to the active map file when editing such a
mod. **Reload map** refreshes changed files/mods and asks before discarding
unsaved changes. Disabling a map mod restores the project map; removing or
renaming `Maps/scen1.json` restores the original scenery and provisional fish.

Lights use the original star flare in both the game and map editor. Choose
**Steady**, **Pulsing**, or **Flashing** under **Light style**. Flashing has
separate on/off durations in seconds (defaults: 0.5 on, 1.0 off); pulsing has
a period and minimum brightness percentage. Peak energy, range, and flare
size apply to every style. Apply properties and save the map to retain changes.
Original lights and older maps without saved style settings default to flashing.
Previously saved pulse/steady choices are preserved.

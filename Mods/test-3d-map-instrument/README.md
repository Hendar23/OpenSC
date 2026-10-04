# Test 3D map instrument

Enable this pack in F1 → Mods to replace the minimap's original frame with the supplied 3D instrument. The map stays live. Key 3 hides either version.

Cockpit models use `hud.tilt`, `hud.equipment`, `hud.map`, `hud.weapon` or `hud.shield` as replacement IDs. Use a self-contained GLB, with local +Z facing the viewer, +Y pointing up, and a mesh named `Screen_Display` whose UVs cover the live display. Set `forward_axis` to `+Z` in the manifest. The engine fits the instrument to its HUD slot and binds the live display to that mesh.

The original HUD frames can also be replaced through the usual `texture.*` IDs (for example `texture.maprov`). Replacement images supply their own transparency. Deep-Sea Lights use `model.light` for their housing and `texture.deepwp1` / `texture.deepwp2` for their active / inactive icons.

A replacement submarine may supply a node named `EquipmentMount_DeepSeaLights` to position the light housing and beam. Its local -Z points forward. Submarines without this socket use the original ship's mount position.

The original side-view attitude sprite can be replaced with a transparent image using `texture.hud_tilt`. Its nose points left when level. Minimap zoom and HUD size are adjustable in F1 → Graphics; both sprite and 3D panels slide when toggled.

# First-person cockpit models

An optional mod can replace `cockpit.first_person` with a self-contained GLB.
The model sits at the first-person camera origin: X is right, Y is up, and
negative Z is ahead. Use `forward_axis: "+Z"` to retain these camera-local
coordinates with the existing model loader. `scale` and ordinary mod priority
and fallback rules apply. Models have no collision and appear only in the main
first-person view, never in the menu, third person, or auxiliary camera feeds.

Name a mesh `Canopy_Glass` (or a name starting with it) for the built-in glass
shader. Alternatively map a `glass` role through the model's `parts` dictionary.
Its UVs carry the imperfections; the example maps the dome into a circle centred
at UV 0.5. The glass material's tint and roughness are retained. Other materials
receive the normal world lighting, allowing metal canopy frames.

The asset entry accepts an optional `glass` object with numeric values in 0..2:
`scratch_strength`, `reflection_strength`, `edge_tint`, `grime_strength`, and
`refraction_strength` (defaults to zero for other cockpit models).
Scratches are stationary on the glass, antialiased procedurally, and respond to
scene lights. The rimless example also refracts the scene toward the curved
edges. This uses one screen-copy pass after the 3D world (including transparent
bubbles) and before the HUD, leaving instruments and text sharp. The centre
stays clear. It adds no shadow casting or gameplay changes. Arbitrary
shaders/scripts are not loaded from the mod.

Reflections use six scene views, all refreshed every rendered frame. The default
resolution is 256 square and the default range is 40 world units. Captures share
the existing world; they do not run a second simulation. Their range is also
capped by the main camera's far distance,
and they exclude the player hull, glass and HUD. Capturing stops outside
first-person piloting. The glass blends the surrounding image with an
approximation of the inner surface's reflection, giving nearby coloured objects
a distorted ghost on the opposite side. This is a local environment reflection,
not a ray-traced model of thick glass.

Fine scratches scatter grazing scene light. Mottled dirt and curved wipe marks
soften the reflection and catch weaker side lighting; smooth glass no longer
uses the old broad direct-light highlight.

The default is four individual scratches. With the canopy enabled, open the
developer menu's **Mods** tab to tune scratch count, strength, length and width;
reflection strength, inner-surface blend, roughness, resolution and distance;
dirt, refraction, edge tint and glass RGB colour. Sliders apply immediately and
save when released. Resolution ranges from 64 to 512 square, and distance from
5 to 100 units. These controls let you tune reflection detail and rendering cost.
Values are stored per mod in the player's private `settings/canopy.cfg`, leaving
the authored mod manifest unchanged. Exporting all settings includes canopy
values under namespaced `canopy/<mod-id>/...` view keys. The tab is hidden when
no first-person cockpit mod is enabled.

The experimental **Bubble cockpit canopy** mod is not bundled in this beta.
`tools/build_bubble_canopy.py` deterministically builds its GLB using
only Python's standard library. Its geometry and materials are newly authored;
it contains no original-game assets.

# Bubbles: 3D Model

Enable **Bubbles: 3D Model** in **Main menu → Mods**, then Apply.

Replaces the bubble sprites in propeller wakes (including the main menu) and
wildlife/submarine death effects. Disable the mod to restore sprite bubbles.
Movement, size, emission rate and lifetime are unchanged.

"Free Bubble Kit" (https://skfb.ly/oIUoJ) by SpeedyGonzalesJR is licensed under
Creative Commons Attribution (http://creativecommons.org/licenses/by/4.0/).

Changes: isolated the transparent textured bubble, removed the other variants
and display plane, centred it with a unit diameter, reduced its geometry to
726 triangles, and added translucent water-bubble shading with particle fading.
The original kit's embedded
metadata also identifies Waffle Duck (https://sketchfab.com/DuckyGraphic).

`model.bubble` replacements must contain one mesh centred at the origin with
a diameter of one unit. Source colour textures provide subtle iridescence;
the water-bubble shader supplies transparent centres, bright rims and fading.

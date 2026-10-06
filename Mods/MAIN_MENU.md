# Main menu

The live main menu uses the loaded world, a separate camera and decorative
actors. Opening it pauses gameplay; closing it restores the gameplay camera,
visibility and lighting without reloading the map.

To frame the background visually, open the map editor, fly to the desired
position and aim the camera, then click **Use current view for menu** and
**Save map**. **View menu camera** returns to that saved framing for adjustments.
Capture supports undo/redo. The position, angle and field of view are stored in
the map JSON's optional `menu_camera` object and travel with a `map.scen1` mod.
This map camera takes precedence over the UI file's scenic coordinates.

Replace `texture.menu_title` with a PNG (transparency supported). Replace
`ui.main` with a JSON file based on
`godot/game_assets/ui/main_menu.json` to change the button labels, order,
positions, spacing, title rectangle or scenic camera position.

Rectangles use a 640 × 480 logical canvas scaled to the window. Camera and
look offsets are world-space offsets from `camera_anchor`, a fixed scenic
position independent of the map's player spawn. Moving the New Game start
therefore leaves the menu framing unchanged. Existing
button IDs keep their named actions; unimplemented settings remain inactive.
Controls use the rebindable `menu_up`, `menu_down` and `menu_accept` actions.

Example manifest assets:

```json
{
  "texture.menu_title": "images/title.png",
  "ui.main": "main_menu.json"
}
```

Each return to the menu rolls two or three new groups from all loaded wildlife
types, including crawlers, respecting their counts, scales and roaming settings.
Menu creatures reuse imported wildlife templates, and the passing sub reuses the
player model. Fish use the normal swimming, animation, shoaling and terrain
avoidance AI, with their species settings. They remain separate from gameplay
wildlife and cannot be hit by the player. Menu creatures pause when the menu closes.
The menu stays at midday; gameplay physics and the game clock remain paused.
The passing sub has positional propeller sound, sharing the loaded (including
modded) main propeller loop and the master/propeller sound settings. Its audio
stops when the pass ends or the menu closes.

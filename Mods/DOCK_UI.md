# Dock interface replacements

Dock screens use original BMPs from the player's installed game. No original artwork is bundled with OpenSC.

A mod can replace backgrounds through `texture.ui_dock_home`, `texture.ui_dock_equipment`, `texture.ui_dock_goods`, `texture.ui_dock_missions`, `texture.ui_dock_save` and `texture.ui_dock_load`. These accept the usual texture replacement formats.

Add a JSON replacement for `ui.dock` or `ui.saves` to change page layouts. Coordinates use a 640 × 480 canvas, scaled to fit the window. Unspecified properties keep their defaults.

```json
{
  "schema_version": 1,
  "text_colour": [0.2, 0.95, 1.0],
  "pages": {
    "home": {
      "background": "texture.ui_dock_home",
      "title": [218, 10, 202, 40],
      "welcome": [95, 94, 450, 130],
      "status": [222, 304, 198, 155],
      "buttons": [
        {"action": "missions", "rect": [18, 298, 155, 42]},
        {"action": "equipment", "rect": [48, 421, 140, 45]},
        {"action": "save", "rect": [474, 298, 151, 42]},
        {"action": "launch", "rect": [466, 421, 142, 45]}
      ]
    },
    "save": {"slots": [204, 56, 268, 44]},
    "load": {"slots": [204, 56, 268, 44]}
  }
}
```

Buttons can include a `text` label. Named actions open pages (`home`, `equipment`, `goods`, `missions`, `save`, `load`), launch the sub (`launch`), or return to the main menu (`close`). The slots rectangle sets the first slot position, width and vertical spacing. Save/load actions remain in the game backend, separate from presentation.

This first pass provides working named saves and loading, plus equipment, trade and mission previews. Trading, purchases and missions do not change game state yet. More detailed control layouts and custom interface scripts can be added as those systems develop.

Saves are versioned JSON in Godot's user data `saves` directory, with seven slots. They contain the dock, submarine pose, time of day, mounted equipment/weapon IDs, enabled equipment and explored map. Developer preferences remain separate. A changed map or missing required equipment is reported before loading.

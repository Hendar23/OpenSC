# Controls menu

Each named action has two independent binding slots. Either slot can hold a key (with Ctrl/Alt/Shift), a mouse button, a controller button, one direction of a stick/trigger, or a controller combination. Combinations require both buttons on the same controller: hold the first button, then press the second. A combination takes priority over actions using its second button alone.

The Controls menu saves changes to `user://controls.cfg` automatically, under `[bindings]`. This is a player preference file, separate from game saves and the original game folder setting. Missing/invalid entries retain their defaults. The Restore defaults button restores every action, including menu navigation.

To change the menu's title, action labels or grouping, add `"ui.controls": "controls.json"` to the mod manifest's `assets` object. Use `godot/game_assets/ui/controls.json` as a starting point. Its `schema_version` must be `1`; `title` is a string, `labels` maps action ids to displayed labels, and `groups` maps section names to arrays of action ids. Unlisted actions are still displayed, so a presentation mod cannot remove access to a control. This JSON customizes content; arbitrary layout changes require changing the menu script.

Camera zoom and editor mouse gestures remain developer/editor tools, outside the gameplay bindings menu. Editor commands are installed only by the separate editor. F1 is reserved for the developer menu and cannot be rebound. Up/down moves between action rows in the same column; left/right selects binding slots and their clear buttons.

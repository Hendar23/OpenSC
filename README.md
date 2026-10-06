# OpenSC
OpenSC is an open-source game engine that supports playing Criterion Games [Sub Culture](https://en.wikipedia.org/wiki/Sub_Culture)

You will need a copy of the original Sub Culture files.

Startup shows the loading screen and checks only the saved original game folder. If that location is missing or invalid, it asks you to choose the folder containing `CLUMPS/SUB.DFF` and `DATA/SCEN1.BSP` using the Windows folder picker. The selection is saved in `user://opensubculture.cfg`, under `[game]` as `folder`. On Windows, this is currently `%APPDATA%\Godot\app_userdata\OpenSubCulture- asset viewer\opensubculture.cfg`.

Built with [Godot](https://godotengine.org/)

<img width="1920" height="1080" alt="OpenSC 2026-10-04 16-48-09" src="https://github.com/user-attachments/assets/8025017f-1d10-4db0-b224-4bb7c3b5346d" />

## Current Progress
+ Sub loaded in and moving, with propellers and pods attached and animated
+ Random wildlife populations, animated and moving around as you explore
+ Docking/undocking
+ Original city names and relay-beacon approach greetings, imported from the player's game files and moddable through gameplay data.
+ Basic modding support
+ Propellers producing bubbles when moving
+ Asset viewer for models, images and sounds
+ Map editor for placing and editing scenery, lights and wildlife
+ Editable wildlife populations, shoals, schooling and startled fleeing fish
+ Animated building lights
+ Floating particles in the water
+ Gamepad controls and impact rumble
+ Day/night cycle with moving sunlight and natural shadows
+ Five individually toggleable HUD panels
+ Detailed minimap with fog of war revealed while exploring
+ First and third person camera views
+ Modular submarine equipment, starting with working headlights
+ Tabbed developer menu for adjusting and exporting settings
+ Classic loading screen and a live daytime main menu, with controller navigation, fresh wildlife groups and a passing submarine with positional propeller sound
+ Plants bend in travelling current waves and twist in propeller wash, with developer sliders for wave length, ripple strength and twisting.
+ Toggleable FPS counter and screenshot capture
+ Animated sunlight caustics and small water surface waves
+ Darker caves and deep water, with adjustable lighting and fog
+ Working zapper weapon with creature damage, animated impact effects and adjustable auto aim
+ Organic explosions with adjustable gore and persistent chunks that settle on the seabed
+ Equipment and weapon mounting editor
+ Full-screen map sharing the minimap's exploration progress
+ Docked interface with working save/load slots and placeholder equipment, trading and mission screens
+ Moddable dock menus and layouts
+ Floating mines and editor Object Types / Object Groups, with per-group count and scatter radius and moddable image or 3D appearances. Submarine shield damage is still to come.
+ Controls menu with two saved bindings per action, including keyboard, mouse, controller buttons, sticks, triggers and held-button combinations.

Open **Controls** from the main menu to change either binding slot. Changes save automatically; **X** clears a slot and **Restore defaults** resets all bindings. The full map defaults to **M** or **hold left shoulder and press Y** on a controller. Y alone still switches camera. Escape opens the main menu during play (or closes the current map/menu), and Page Up / Page Down cycle weapons. Camera zoom remains a developer control.

Bindings are stored separately from saves in `user://controls.cfg` (`%APPDATA%\Godot\app_userdata\OpenSubCulture- asset viewer\controls.cfg` on Windows). Controls labels and grouping can be changed by mods through `ui.controls`; see [Controls modding](Mods/CONTROLS.md).

The developer menu's Weapons tab includes **Auto aim cone (degrees, full width; 0 = off)**. The zapper targets visible creatures within that cone and its configured range. Its beam matches the range and stops at the first collision.

In **F1 → Graphics**, **Fade start distance** sets where distance fog begins,
and **Absolute view distance** sets where it fully obscures the world and
clipping begins. The view limit ranges from 1 to 2,000 units; fade start ranges
from zero to 0.5 units below it. A wider gap produces a longer transition.
Both save and export using the existing `fog_start` and `fog_visibility` keys.

Wildlife beyond the view limit pauses simulation. Offscreen wildlife skips
animation updates and uses a lower AI update rate, while nearby creatures
retain full-rate reactions. Distant random groups despawn and generate fresh
members when you approach again; authored groups remain dormant for your return.

Place floating mines through the editor's **Add object group** button. Shared stats are under **Object types**; population and scatter radius are per group. No original mission minefields are imported. See [Objects and mine modding](Mods/OBJECTS.md).

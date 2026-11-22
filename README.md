<img width="1920" height="1080" alt="OpenSC 2026-10-04 16-48-09" src="https://github.com/user-attachments/assets/8025017f-1d10-4db0-b224-4bb7c3b5346d" />

# OpenSC
OpenSC is an open-source game remake for playing Criterion Games' [Sub Culture](https://en.wikipedia.org/wiki/Sub_Culture).

[Watch the trailer here.](https://www.youtube.com/watch?v=_cgAMurOpoc)

[Join the Discord](https://discord.gg/56ESd7m8w)

OpenSC brings this true forgotten gem to modern systems and expands on it with improved gameplay, new features and modding support. 

## Installation
Latest release is available [here](https://github.com/Hendar23/OpenSC/releases).
- OpenSC does not include the original Sub Culture game assets. You'll need your own copy of the original game files.
- When you first run the game, it will ask you to point it to the original Sub Culture folder.
- A controller is recommended for controlling the sub.

<img width="1920" height="1080" alt="OpenSC 2026-10-27 21-57-30" src="https://github.com/user-attachments/assets/fb41cc38-aa36-4b3c-9b8c-f06a5a1fdee2" />

## Enhancements
OpenSC offers a few enhancements over the original:

### Mod Support
- **Built in mod manager**
  - Download all the official mods directly from the game.

### Missions & NPCs
- **Mission Improvements**
  - Lots and lots of little enhancements. Things like mission related subs and items not just vanishing into thin air. More dramatic explosions for buildings and big subs.
- **NPCs**
  - NPCs use docks.
  - Random Pirates (and bounties for killing them).
  - Reworked NPC movement.

### Interface & Quality of Life
- **New main menu**
  - Replaced static main menu with a live in game view.
- **Photo and Action Replay Modes**
  - Pauses the game and gives full camera control for taking screenshots.
  - Replay the last 30 seconds of action from any angle.
- **UI**
  - Compact multi-message radio stack
  - Credits and hold inventory displayed next to full screen map

## Why are the cutscenes not playing?

There is a bad copy of Sub Culture going about that has the FMV files replaced with single frame placeholders. This was probably done at some point in the past to make the install size smaller. The game checks for this and gives a warning if it detects this bad copy. (The game will play fine, you just don't get video cutscenes.)

If you are not sure, check the file sizes in the FMV folder of the original game install. If they look like [this](https://private-user-images.githubusercontent.com/270592230/715133378-1c050a7f-060e-4759-94a3-0dd9dfe23e80.png?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3OTUzNzUxMDksIm5iZiI6MTc5NTM3NDgwOSwicGF0aCI6Ii8yNzA1OTIyMzAvNzE1MTMzMzc4LTFjMDUwYTdmLTA2MGUtNDc1OS05NGEzLTBkZDlkZmUyM2U4MC5wbmc_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjYxMTIyJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI2MTEyMlQxOTEzMjlaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT1hMTk3N2NjZWQxZTQ2M2MyYjE5YzBkMTBjNDY3MDc3YThkOTA5N2MzZGNjMmY5MjQzYjIxODk5OGFjZDQ1YTAwJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCZyZXNwb25zZS1jb250ZW50LXR5cGU9aW1hZ2UlMkZwbmcifQ.GPRRSbo7BhfGJdwsxqXKZp2IDb1lgwq9s03gGLQ9ewo) you have a bad copy. A good copy looks like [this](https://private-user-images.githubusercontent.com/270592230/715133478-428295f8-4e2b-48ee-840a-4b504b2ea052.png?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3OTUzNzUxMDksIm5iZiI6MTc5NTM3NDgwOSwicGF0aCI6Ii8yNzA1OTIyMzAvNzE1MTMzNDc4LTQyODI5NWY4LTRlMmItNDhlZS04NDBhLTRiNTA0YjJlYTA1Mi5wbmc_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjYxMTIyJTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI2MTEyMlQxOTEzMjlaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT0wYzMzOTQ0YjdlOTQ3M2E1NTZlMmQyYzQ5YTEyYTVmYzhjMDMxYmMwYjI2ODMwOTQwN2E1MWJhNzhiYjY1M2VhJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCZyZXNwb25zZS1jb250ZW50LXR5cGU9aW1hZ2UlMkZwbmcifQ.OhpoTXmFF7NTCjubKm6ZXrmbzf1f_QLvTpH7M_5juTA).

Of course I'm sure none of you will have this problem, because you are all using a legit copy of your original CD-ROM.

## Controls

Default bindings use Xbox button names. Controls can be changed in the **Controls** menu.

| Control | Action |
|---|---|
| Right trigger (RT) | Forward thrust |
| Left trigger (LT) | Reverse thrust |
| Left stick left / right | Turn left / right |
| Left stick back / forward | Pitch nose up / down |
| Right stick up / down | Thrust vertically up / down |
| X | Fire selected weapon |
| D-pad up / down | Select previous / next weapon |
| D-pad left / right | Select previous / next equipment |
| B | Activate or deactivate selected equipment |
| A | Accept docking or delivery prompt |
| B | Decline docking or delivery prompt |
| Y | Switch between cockpit and external view |
| Hold LB, then press Y | Open or close the map |
| Hold RB, then press Y | Toggle bottom camera |
| Hold RB, then press B | Toggle rear camera |
| View / Back | Enter photo and replay mode |
| Menu / Start | Open the pause menu |

When a docking or delivery prompt is active, **B** declines the prompt instead of toggling equipment.

### Menus

| Control | Action |
|---|---|
| D-pad | Navigate |
| A | Select or confirm |
| B | Back or cancel |

### Photo and replay mode

| Control | Action |
|---|---|
| Left stick | Move camera forward, backward and sideways |
| Right stick | Look around |
| RT / LT | Raise / lower camera |
| Hold RB | Move faster |
| Hold LB | Move slower |
| D-pad up | Play or pause replay |
| D-pad down | Switch between normal and quarter speed |
| D-pad left / right | Scrub backward / forward |
| View / Back, Menu / Start, or B | Exit photo and replay mode |
 
## Credits
- Screenshot shutter sound: [“camera” by irinairinafomicheva](https://pixabay.com/sound-effects/technology-camera-13695/), from Pixabay. Used under the Pixabay Content License.

<img width="1920" height="1080" alt="OpenSC 2026-10-21 20-35-50" src="https://github.com/user-attachments/assets/9b6adf8d-ec6a-4b38-835e-adfb537182a9" />

<img width="1920" height="1080" alt="OpenSC 2026-10-17 15-22-02" src="https://github.com/user-attachments/assets/ac7ab934-019f-42a1-b13f-df1f6d110879" />

<img width="1920" height="1080" alt="OpenSC 2026-10-17 09-03-08" src="https://github.com/user-attachments/assets/ab1e2640-c8ac-4138-8217-b3e82e3d8f3a" />

# Ground traffic

The original startup routine (`0x42b9d0`) creates eight Mission 2 / Object 31
placements from SCEN1.DDB: TRADCAR rows 27, 44, 45 and TECHTRUK rows
40, 41, 43, 46, 47. The shared handler is `0x453ef0`. The original object
table gives both vehicles 4 raw shields and a 0.1 damage multiplier.

The original movement uses forward steps, ground probes and turns when blocked;
no road waypoint network was recovered. Its fixed 0.01 movement step has not
been tied conclusively to wall-clock time. Original city-return logic restores
missing vehicles; there is no recovered timed respawn interval.

OpenSC keeps those eight starting placements, models and damage values. Its
movement is deliberately improved: each vehicle builds a small local AStar3D
graph from walkable ground, chooses destinations, pauses between journeys,
steers along the surface, yields to collisions and reverses/replans if stuck.
Navigation builds incrementally; distant vehicles update less often. Default
speed (0.4 cars / 0.3 trucks), operating radius (8 units), stops (2–6 seconds)
and timed respawn (120 seconds, away from the player and outside the camera)
are OpenSC choices, editable per placement. There are no inter-city routes.

`ground_vehicle.gd` handles individual movement and damage; `ground_traffic.gd`
owns shared effects and save state. `npc_health.gd` is reusable raw shield storage
for future NPC controllers. NPCs remain model entities in map documents, with
optional `npc_*` properties, so older maps still load. Runtime pose, health,
destination, waiting, respawn countdown and RNG state are saved separately;
older saves simply start traffic at its map placements.

In the map editor, NPCs has Add car / Add truck and per-vehicle controls.
The outline shows operating radius. Place vehicles near the seabed (use Snap
to seabed), then enable Simulate wildlife / NPCs to preview them. Turrets and
their Add button live under Object types. Other add controls follow their
corresponding category rather than accumulating in the common action grid.

Run `res://tests/verify_ground_traffic.gd` with the original assets available to
check sustained movement at all eight placements, save/load, damage/respawning
and editor categorisation, duplication and map round trips. Tests redirect
player storage into an ignored workspace fixture directory.

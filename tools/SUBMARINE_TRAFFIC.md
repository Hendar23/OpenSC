# Civilian submarine traffic

The default map places six civilian shuttles: three Bohine TRADSHUT and three Procha TECHSHUT. Their shared templates live under NPC types; placements live under NPCs. The template controls speed, raw shield health, damage sustain, berth dwell time and respawning. Faction belongs to the placement.

Bohine traders visit cities 1 and 3; Procha traders visit 2 and 4. Both use Factory (6). Aquatraz (5) is excluded. Visits currently leave commodity markets untouched. Traders are unarmed, flee damage, alert their faction's defences, and use the same low-shield smoke, metal fragments and destruction bubbles as the player.

A single AStar water graph combines terrain height samples with static scenery and swept collision checks. Construction is budgeted across loading frames; the editor reuses its terrain samples. Hull motion still collides with terrain, wildlife and other submarines. Temporary obstructions cause a sidestep and retry.

Dock entrance reservations use weak owners, shared with player docking. Approach, entry and exit hold the entrance. After entry and hatch closure, the shuttle disappears into an internal berth and releases it. Berth dwell holds no reservation. Waiting player launches resume when the entrance becomes available. Save snapshots include hull pose/health, destination, berth/transit stage, timing, escape state and RNG; transit reservations and hatch state are reconstructed on load.

Wildlife selects the nearest active submarine in its own physics world and applies the existing flee/attack response and ranges. Minimap actor dots remain distinct from the static city markers and disappear while inside a berth or destroyed.

## Original evidence and deliberate changes

OBJECTS.CSV entries TECHSHUTTLE (61, TECHSHUT) and TRADSHUTTLE (69, TRADSHUT) both specify raw shields 10 and sustain 0.3. Both use SC.EXE callback 0x471890; its update at 0x4715d0 performs steering, propulsion bubbles, low-health smoke and destruction handling. Raw shield units correspond to ten displayed shield points; wildlife bite damage is converted accordingly.

The six-ship population, faction/factory journeys, internal berth scheduling and shared navigation graph are OpenSC behaviour, not a claim to have recovered the original traffic schedule. Map marker colours currently distinguish Bohine (yellow) and Procha (blue); they are not asserted to reproduce recovered palette entries.

Run godot/tests/verify_submarine_traffic.gd to check permitted routes, repeated journeys, busy entrance arbitration, queued launches, save restoration, wildlife bites/fleeing and destruction. verify_entity_types.gd covers shared trader template editing.

Trader motion runs every physics tick, with steering decisions at 8 Hz. Predicted closest approach over three seconds prompts right-side passing and braking before contact. Visibility shortcuts smooth navigation paths, allowing diagonal climbs and descents outside the vertical docking hatch transit.

Bohine propellers spin with propulsion power and emit a stern wake; Procha shuttles use twin aft outlets, matching their single-piece original model. The shared wake renderer tracks fractional emission independently for each vessel/outlet.

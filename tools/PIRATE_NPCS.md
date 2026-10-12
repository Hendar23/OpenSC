# Placeable pirate submarines

Create a shared template in NPC types > New NPC type, selecting Pirate submarine, Pirate submarine 2 or Pirate submarine 3. Add placements from NPCs > Add NPC. No automatic placements or replenishment are introduced.

Templates share health, received-damage multiplier, speed, detection range, missile range, firing interval and optional respawning. Instances own their pose. Pirates use faction 3 and red minimap dots. They target the player and civilian vessels, use shared water navigation and collision avoidance, aim before firing, respect scenery occlusion and stop at a fighting distance. Damage, smoke, wakes and destruction reuse the vessel systems. They never reserve docks.

Original evidence: SC.EXE callback 0x4393b0 and update 0x438c50 supply raw shield health 30, sustain 0.3, firing range 15, forward aim threshold 0.85, a five-to-six-unit fighting distance and ordinary MISSILE object 11 (inflict 8). Speed 2.5, detection 25 and a randomised 1.5-second shot interval are editable OpenSC choices; the old manoeuvre and timer solver is not reproduced exactly. Respawning defaults off.

Recovered English messages include ag1 (refinery cargo taunt), ag2 (escape taunt), ag3 (death cry) and ar7 ("You are doomed"). These belong to missions. Generic placed pirates do not inject those mission lines. A general spoken attack taunt has not been confirmed.

Checks: verify_pirates.gd covers targeting, aim, cooldown, blocked shots, damage, destruction, save state and reset; verify_entity_types.gd covers shared pirate definitions and their editor fields.

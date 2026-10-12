# Original turret behaviour

OpenSC suppresses the generic turret at SCEN1.DDB row 71 in favour of the
dedicated Tryton defence at row 30, only 0.372 units away. This leaves 22 live
startup turrets. Suppression happens after native beacon naming to preserve
existing map light IDs. Both turrets and ground vehicles now use the submarine's
textured metal fragments and bubble burst alongside the explosion animation.

`research_original_turrets.py` checks the original executable hash, object table,
callback pointers, aiming constants and startup database placements. It requires
locally owned original assets and the extracted catalogue; neither is distributed
with this research note. Decompiled functions are in the local `SC.c` output.

## Recovered behaviour

- Handler `0x4051f0`: TURRET (81) and HOMINGTURRET (82) have 8 raw shield
  units, 0.3 received-damage multiplier and an articulated gun frame. Gun forward
  is local +Z; the muzzle is 0.7 units ahead of the gun frame.
- Gun turn: 0.5 degrees per normalized update, or 12.5 degrees/second at 25 Hz.
  Interception assumes projectile speed 0.15 units/update and a 96-update horizon.
  Alignment uses squared cross-product thresholds 0.0003 normally and 0.001
  during temporary activation. Obstructed launch lines do not fire.
- Firing counters reset to 40 normally or 30 during temporary activation, then
  decrement. A zero counter fires on the following update: 41/31 update periods.
- Events 0x19/0x1f enable/disable persistent activation. Event 0x23 temporarily
  activates and resets the firing counter when previously inactive.
- Straight turrets launch TMISSILE (154, inflict 2.5); homing turrets launch
  HMISSILE (153, inflict 2). Missile callbacks `0x469340`/`0x468e70` use
  mass 0.1, thrust 0.0025, damping 0.857142857 and lifetime 133.333 updates.
  Terminal straight speed is approximately 3.75 world units/second. Swept
  terrain collisions and generic object collision damage terminate the missile.
- Startup `0x42b9d0`: six AutoCreate turrets, three straight MissionID 2 / ObjectID
  4 guards, twelve homing ObjectID 11 city guards, and two homing ObjectID 12
  turrets. Only the last two receive persistent activation at startup. Other
  mission turrets remain dormant. There are 23 startup turrets in total.
- City routine `0x42cfb0` sends temporary activation to guards for hostility:
  60 seconds for city guards, 120 seconds for the special straight guard group.

## OpenSC implementation boundary

`gun_turret.gd` owns aiming, activation, raw health and articulated mesh hitboxes;
`turret_missile.gd` owns projectile flight and swept hits; `turret_system.gd`
owns shared missile assets and save/reset state. Map records remain ordinary
TURRET model entities with optional combat properties, so older maps still load.
Saved health, destruction, retaliation and firing counters are optional extensions
to existing saves. Transient missiles and gun orientation are not saved.

Original coordinates and authored map transforms are retained. The original's
terrain-normal grounding adjustment is not reproduced. A configurable 20-unit
activation range bounds processing; this is a provisional OpenSC setting, not a
recovered distance gate in the turret callback. Homing uses a bounded 0.1-radian
turn per normalized update rather than the old angular-momentum solver. Missile
impacts currently reuse the existing explosion effect/audio. Bubble wakes use a
shared bounded world-space batch, including the optional 3D bubble replacement.
Hits impart up to 50 impulse units along flight, with off-centre rotation and one
controller impact pulse; this feedback tuning is an OpenSC addition. Original
missile sound-event mapping remains to be recovered.

Current activation covers explicit hostility, bad faction standing and 60-second
retaliation when a turret is hit. It does not yet reproduce city-wide retaliation
or the mission event dispatcher. Future missions should call `activate(seconds)`
and update persistent activation for their associated guards. Homing currently
targets the player; original target-acquisition rules need extending when NPC
submarines are added.

`verify_turrets.gd` covers native articulation/collision, neutral and armed
behaviour, turning and interception, blocked firing, projectile hits and homing,
health/destruction/reset/save state, startup placements, and editor property,
duplication, undo and map persistence.

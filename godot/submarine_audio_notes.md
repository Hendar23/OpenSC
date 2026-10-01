# Original submarine sound references

Read-only disassembly of the supplied SC.EXE found the sound table at file
offset 0xDC098 (virtual address 0x4DD698). Each entry holds a flag and a filename
pointer. The game loads the samples at 11025 Hz (0x2B11), at 0x409863.

The submarine update routine calls the loop/update helper at 0x40A170 and stop
helper at 0x40A380:

| Sound ID | File | Submarine use |
| --- | --- | --- |
| 3 | PROP3.RAW | Forward/reverse propulsion layer; updates at 0x435CC1 and 0x435D02 |
| 4 | PROP4.RAW | Side propulsion layer; updates at 0x435DF2 |
| 5 | PROP1.RAW | Additional active-thrust layer; updates at 0x435E7C |

ID 3 playback frequency depends on the forward propulsion state at object
offset 0x30. ID 4 uses the absolute side propulsion state at offset 0x28 and
calculates a frequency capped at 11000 Hz. ID 5 plays under active propulsion
input, at 11025 Hz. This identifies propulsion layers; it does not establish
a separate pod-rotation servo sound. SUBCYCLE.RAW (ID 26) appears in the input
handling routine, so it is not used as a continuous propeller sound here.

The prototype assigns PROP3/PROP4 to main and side-pod propulsion. PROP1 is
assigned to the pod-angle motor following the user's listening feedback on
the video around 46:53; this specific role is provisional rather than proven
by the unnamed executable fields above. It plays on angle changes, including
the return to neutral, rather than holding a steady angle or applying main thrust.
Pitch and volume interpolate, and propulsion release follows propeller spin-down.
This is an approximation of the original mix, not an exact emulation of its
sound engine. No ambient or bubble audio is added yet.

F6 exposes independent pitch/gain controls, solo buttons, a stationary preview,
response times and PCM overlap smoothing. Tail/head blending produces a continuous
wraparound, avoiding abrupt loop steps. This addresses loop-boundary clicks;
it does not establish that every tick heard was caused by a loop seam, as the
original samples also contain mechanical pulses. All three layers are processed
without modifying the original RAW files. Exported defaults are stored separately
in submarine_audio.cfg, with one user mix per enabled-mod combination.

The remaining side-prop tick was reproduced in actual AudioEffectRecord output
at constant 0.96 pitch, with the exported 19 ms blend. It occurred every loop:
the recording peaked at 4920 (16-bit PCM), versus the source's expected peak
around 1800 at -10 dB. Godot's WAV mixer can read the exclusive loop_end frame
before wrapping, matching https://github.com/godotengine/godot/issues/119778.
guarded_loop supplies the first loop frame at that position in a runtime copy;
the loop bounds and exported settings remain unchanged. With the guard, the
recorded peak is 1793 and the maximum adjacent step falls from 1305 to 120.
verify_submarine_audio.gd now exercises the actual mixer over repeated wraps
for 8/16-bit mono/stereo PCM and the side-prop pitch range 0.49–1.19.
capture_side_loop.gd records isolated loops with smoothing off and at 19 ms.

Loop preparation now lives in audio_loop.gd, shared by submarine playback and
the asset viewer's native looping transport. The buffer guard already applied
to all three submarine layers. The main-prop follow-up therefore also addresses
the blend: at 19 ms the original tail/head correlation was only 0.118, so a
linear overlap could make a repeating level dip. Tonal loops now select a
better phase match within 50–100% of the requested blend duration, use a cosine
transition, and compensate for correlation-dependent energy loss. Noise-like
loops retain the requested duration. The exported slider values remain intact.
Regression coverage includes each layer's exported pitch range and a tonal
fixture whose RMS stays above 92% of its normal level throughout the join.
Original assets are unchanged; modern PCM replacements receive the same handling.

Hull collision audio follows the user's identification of HIT1 / HIT3, selected
with equal probability. CREAKING has an independent 20% chance, scheduled after
the selected hit's duration (accounting for pitch), plus 0.15–0.5 seconds. All
three are non-looping unsigned 8-bit mono PCM at 11025 Hz, with mod replacements
supported. Each hit/creak receives an independent pitch multiplier in 0.95–1.05.
Closing speed/normal impulse determines impact strength and scales gain. Fresh
physics contacts and the surface clamp trigger sounds; persistent contact does
not. Default minimum speed is 0.5 m/s and cooldown is 0.35 seconds. F6 includes
six live/exportable collision controls and an audition button. Reset or hiding
the hull cancels queued creaks. verify_collision_audio.gd includes real physics
wall impacts, persistent-contact silence and seeded random distribution checks.

Docking audio follows the user's sound identification. DOCKING loops continuously
from accepted docking (including settling, stationary turning and forward approach) until DOCKED, and from
accepted launch until the exit hatch finishes closing. DOCK plays once on entering
OPEN/CLOSE/EXIT_OPEN/EXIT_CLOSE, stopping if that movement finishes first. DOCKSHUT is a one-shot on leaving each door stage
through normal completion, including opening. Cancellation stops everything and
does not play a completion sound. Players belong to the docking controller so
hiding the submarine does not truncate the final DOCKSHUT. All original PCM is
11025 Hz unsigned 8-bit mono; loop roles share audio_loop.gd smoothing/guards.
Master gain, propeller solo and three F6 docking gains apply live. Exported
settings and audio.docking.* mod IDs support replacement formats. State tests
exercise all six original ports, and mixer tests check repeated docking loops.

Accepted physical impacts emit impact_accepted independently of sound availability
or mute. impact_rumble.gd drives the first connected controller's two motors,
matching pilot_input.gd controller selection. Strength and duration scale with
closing speed relative to forward top speed, with finite 0.08–0.22 s pulses.
Impact threshold/cooldown suppress tiny and repeated contact pulses. Rumble
strength defaults to 0.65 and is live/save/exportable in F6 (zero disables it).
Reset, disabling piloting, hiding the hull, focus loss and node exit stop rumble.
verify_impact_rumble.gd uses an injected joypad backend to verify API calls,
severity, cancellation, no-controller behavior, and independence from audio gain.
Physical motor response still requires controller playtesting.

research_submarine_audio.py reproduces the relevant table/disassembly using
pefile and capstone from the temporary opensubculture-audio-research directory.
These packages are research aids and are not runtime game dependencies.

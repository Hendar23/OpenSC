#ifndef OSC_REPLAY_CLOCK
#define OSC_REPLAY_CLOCK
global uniform bool osc_replay_active;
global uniform float osc_replay_time;
float visual_time() { return osc_replay_active ? osc_replay_time : TIME; }
#endif

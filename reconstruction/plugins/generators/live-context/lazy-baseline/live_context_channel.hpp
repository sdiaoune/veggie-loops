#pragma once
#include "three_osc_multimode_channel.h"
// Private observed active-context extension. Calls are serial, valid prepared
// contexts only, no reentrant callbacks, and caller-owned notes remain live.
// The actual corpus covers specific transitions in LIVE_CONTEXT.md; these
// functions do not provide application clock production or scheduler behavior.
extern "C" int vl_private_live_rate(vl_osc_multimode_channel*,int32_t);
extern "C" int vl_private_live_PPQ(vl_osc_multimode_channel*,uint32_t);
extern "C" int vl_private_live_tempo(vl_osc_multimode_channel*,double);

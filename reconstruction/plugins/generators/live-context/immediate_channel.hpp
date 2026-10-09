#pragma once
#include "three_osc_multimode_channel.h"
// Private observed active-context extension. Calls are serial, valid prepared
// contexts only, no reentrant callbacks, and caller-owned notes remain live.
// Calls across all raw-engine/factory instances are serialized. The measured
// FP environment is nontrapping nearest-even with gradual underflow. Cached
// coefficients are prepared immediately for the listed active tempo/control/
// restore calls; general fenv and prevoice timing remain outside this contract.
// The actual corpus covers specific transitions in LIVE_CONTEXT.md; these
// functions do not provide application clock production or scheduler behavior.
extern "C" int vl_private_live_rate(vl_osc_multimode_channel*,int32_t);
extern "C" int vl_private_live_PPQ(vl_osc_multimode_channel*,uint32_t);
extern "C" int vl_private_live_tempo(vl_osc_multimode_channel*,double);

// Private inspection only: destination is caller-owned storage for five
// 160-byte prepared configurations. Output is nonaliasing800 writable bytes;
// comparisons omit target-specific table pointers and synchronized phase.
extern "C" int vl_private_immediate_coefficients(vl_osc_multimode_channel*,void*);

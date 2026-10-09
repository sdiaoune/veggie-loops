#pragma once
#include "three_osc_multimode_channel.h"
#include "three_osc_native_factory.h"
#include "prevoice_cache.hpp"
// Private copied active-context implementation plus separately measured no-voice cache. Calls are serial, valid prepared
// contexts only, no reentrant callbacks, and caller-owned notes remain live.
// Calls across all raw-engine/factory instances are serialized. The measured
// FP environment is nontrapping nearest-even with gradual underflow. Cached
// coefficients are prepared immediately for the listed active tempo/control/
// restore calls. The new no-voice cache covers the listed measured callbacks;
// general fenv and other prevoice timing remain outside this contract.
// The actual corpus covers specific transitions in LIVE_CONTEXT.md; these
// functions do not provide application clock production or scheduler behavior.
extern "C" int vl_private_live_rate(vl_osc_multimode_channel*,int32_t);
extern "C" int vl_private_live_PPQ(vl_osc_multimode_channel*,uint32_t);
extern "C" int vl_private_live_tempo(vl_osc_multimode_channel*,double);

// Private inspection only: destination is caller-owned storage for five
// 160-byte prepared configurations. Output is nonaliasing800 writable bytes;
// comparisons omit target-specific table pointers and synchronized phase.
extern "C" int vl_private_immediate_coefficients(vl_osc_multimode_channel*,void*);

// Inspection outputs have the exact Snapshot size and caller-owned, valid,
// nonaliasing storage. No arbitrary-pointer validation/foreign class ABI claim.
extern "C" int vl_private_prevoice_cache_snapshot(vl_private_osc::Plugin*,void*,size_t);
extern "C" int vl_private_prevoice_channel_cache(vl_osc_multimode_channel*,veggie_loops::three_osc::prevoice::Cache*);
extern "C" vl_osc_multimode_channel* vl_private_prevoice_import(vl_osc_compute_lr,vl_osc_multimode_channel_notify_kill,void*,const float*const[6],const uint8_t*,const veggie_loops::three_osc::prevoice::Cache*);
extern "C" int vl_private_prevoice_ticks(int32_t,double,int32_t*);
// Typed observation of an already computed owned source-core field. The
// immutable core implementation is compiled exactly once in the factory TU.
extern "C" float vl_private_prevoice_core_scaler(const vl_osc_core*);

// Test-only actual immutable source-core phase consumer; delivered-rate domain.
extern "C" int vl_private_prevoice_phase(vl_private_osc::Plugin*,float,uint32_t*);

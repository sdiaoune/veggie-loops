#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Independently written numerical C API; this is not the native FL, VST or AU
// interface. Each instance requires serialized calls or the host's mix lock.
typedef struct VLPhaseInverterPlugin VLPhaseInverterPlugin;
VLPhaseInverterPlugin* vl_phase_inverter_create(void);
void vl_phase_inverter_destroy(VLPhaseInverterPlugin* plugin);
// One raw parameter, 0..1024, initially 1024. Values 0..341 bypass inversion,
// 342..682 invert left, 683..1024 invert right. Flags 1=set, 2=get, 32=normalize a
// MIDI integer 0..2^30 with nearest-even rounding in the default FP environment.
// Returns 1 on accepted input; rejected input leaves state and result untouched.
int vl_phase_inverter_parameter(VLPhaseInverterPlugin* plugin,int32_t index,
                               int32_t value,uint32_t flags,int32_t* result);
// Interleaved stereo 32-bit float storage, 0..1024 frames, valid disjoint or exactly
// identical buffers. Every sample bit pattern is supported. Inversion toggles
// the selected channel's sign bit, preserving all payload bits and signed zero.
// Partial overlap is rejected atomically. Calls on the instance are serialized.
int vl_phase_inverter_render(VLPhaseInverterPlugin* plugin,const float* input,
                            float* output,int32_t frames);
// Exactly 8 little-endian bytes: version 1 and one raw value. Restore accepts
// versions 0/1 and valid raw values atomically. Malformed-input rejection is an
// independent validation extension with no original-plugin equivalence claim.
int vl_phase_inverter_save_state(const VLPhaseInverterPlugin* plugin,void* bytes,size_t size);
int vl_phase_inverter_restore_state(VLPhaseInverterPlugin* plugin,const void* bytes,size_t size);
#ifdef __cplusplus
}
#endif

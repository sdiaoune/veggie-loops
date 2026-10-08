#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Original C ABI for the verified Balance numerical implementation. This is
// not the FL native, VST, or AU ABI and does not export a commercial plugin ID.
// Each instance requires serialized calls or the host's mix lock; mutable
// parameter, render, save and restore operations are not internally synchronized.
typedef struct VLBalancePlugin VLBalancePlugin;

VLBalancePlugin* vl_balance_create(void);
void vl_balance_destroy(VLBalancePlugin* plugin);
// Native parameter units: pan -128..128, volume 0..320 (default 256).
// Supported numerical flags: 1=set, 2=get, 32=normalized MIDI 0..2^30.
// Returns 1 on accepted input and writes the native numerical result.
int vl_balance_parameter(VLBalancePlugin* plugin,int32_t index,int32_t value,
                         uint32_t flags,int32_t* result);
int vl_balance_set_sample_rate(VLBalancePlugin* plugin,int32_t sample_rate);
void vl_balance_resume(VLBalancePlugin* plugin);
// Stereo interleaved floats; finite samples, 0..1024 frames, separate or exactly
// identical buffers. Partial overlap is rejected. Returns 1 on accepted input.
int vl_balance_render(VLBalancePlugin* plugin,const float* source,float* destination,
                      int32_t frames);
int vl_balance_get_meters(const VLBalancePlugin* plugin,float* left,float* right);
// Exactly 8 bytes of little-endian parameter state, excluding host/preset wrappers.
int vl_balance_save_state(const VLBalancePlugin* plugin,void* bytes,size_t size);
int vl_balance_restore_state(VLBalancePlugin* plugin,const void* bytes,size_t size);

#ifdef __cplusplus
}
#endif

#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Independent numerical API for the inspected Mute 2 behavior. This interface
// is not the FL native, VST, or AU ABI and has no commercial plugin identifier.
// Each instance requires serialized calls or the host's mix lock; mutable
// parameter, render, save and restore operations are not internally synchronized.
typedef struct VLMute2Plugin VLMute2Plugin;
VLMute2Plugin* vl_mute2_create(void);
void vl_mute2_destroy(VLMute2Plugin* plugin);
// Two raw parameters, both 0..1024 and initially 512. Parameter 0 enables audio
// when its value is >=512. Parameter 1 selects left/both/right for muted audio.
// Numerical flags: 1=set, 2=get, 32=normalize an integer MIDI value 0..2^30.
// Normalization follows nearest-even rounding under the default FP environment.
// Returns 1 on accepted input, 0 on invalid input without changing state.
int vl_mute2_parameter(VLMute2Plugin* plugin,int32_t index,int32_t value,
                       uint32_t flags,int32_t* result);
// Finite interleaved stereo floats, 0..1024 frames, disjoint or exactly identical
// buffers. Partial overlap is rejected. Signed zero from single-channel mute
// multiplication is preserved; muting both channels writes positive zero.
int vl_mute2_render(VLMute2Plugin* plugin,const float* input,float* output,int32_t frames);
// Version 1 plus two raw parameters, exactly 12 little-endian bytes. Restoration
// accepts versions 0/1 and validates ranges atomically. Malformed state handling
// is an independent validation extension, outside original equivalence claims.
int vl_mute2_save_state(const VLMute2Plugin* plugin,void* bytes,size_t size);
int vl_mute2_restore_state(VLMute2Plugin* plugin,const void* bytes,size_t size);
#ifdef __cplusplus
}
#endif

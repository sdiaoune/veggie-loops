#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Independently written numerical C ABI, separate from native FL/VST/AU hosts.
// All access to an instance, including getters, save and destruction, requires
// serialization or a host mix lock. The default FP environment (nearest-even
// rounding) is required.
typedef struct VLStereoShaperPlugin VLStereoShaperPlugin;
VLStereoShaperPlugin* vl_stereo_shaper_create(void);
void vl_stereo_shaper_destroy(VLStereoShaperPlugin* plugin);
// Six raw values: matrix controls 0..3 in -25600..25600, delay and phase 4/5 in
// -4096..4096. Defaults: [0,12800,12800,0,0,0]. Flags 1=set, 2=get, 32=normalize
// MIDI integers 0..2^30. UI/hint flags are handled by separate native wrappers.
// Returns 1 on success. Rejected input leaves state and result unchanged.
int vl_stereo_shaper_parameter(VLStereoShaperPlugin* plugin,int32_t index,
                              int32_t value,uint32_t flags,int32_t* result);
// Measured sample rates: 22050,44100,48000,96000,192000. Rate changes reset the
// delay ring and recalculate active filter coefficients; resume clears filter
// history and copies existing matrix targets into the current slew state.
int vl_stereo_shaper_sample_rate(VLStereoShaperPlugin* plugin,int32_t rate);
int vl_stereo_shaper_resume(VLStereoShaperPlugin* plugin);
// Synthetic factory fixture provides four outputs. Index 0 disables the side
// send, 1..3 select a side output; pre_post 0 runs delay/phase before the matrix,
// 1 runs them afterwards. Actual host output-count/routing adaptation is separate.
int vl_stereo_shaper_routing(VLStereoShaperPlugin* plugin,int32_t send_index,
                            int32_t pre_post);
int vl_stereo_shaper_get_routing(const VLStereoShaperPlugin* plugin,
                                int32_t* send_index,int32_t* pre_post);
// Interleaved stereo float, 0..1024 frames, finite samples with |input|<=4.
// Main buffers must be disjoint or exactly identical. The optional side output
// must be disjoint from both main buffers, with 2*frames finite samples. When
// enabled and provided, it receives existing + (dry - processed). A null side
// output models a host that provides no output buffer. Partial overlap is
// rejected before processing. NaN/Inf and alternate FP environments are outside
// the comparison domain. Bit-exact evidence is limited to macOS arm64, measured
// binaries, system libm and the documented compiler flags.
int vl_stereo_shaper_render(VLStereoShaperPlugin* plugin,const float* input,
                           float* output,int32_t frames,float* side_output);
// Exactly 36 LE bytes: version 0, six raw values, send index, pre/post mode.
// Restore accepts version0 and the documented domains atomically. Malformed
// input rejection is an independent extension; source-factory proof uses valid
// original framing only. Delay/filter runtime history is not serialized.
int vl_stereo_shaper_save_state(const VLStereoShaperPlugin* plugin,void* bytes,size_t size);
int vl_stereo_shaper_restore_state(VLStereoShaperPlugin* plugin,const void* bytes,size_t size);
#ifdef __cplusplus
}
#endif

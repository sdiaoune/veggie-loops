#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VLCenterPlugin VLCenterPlugin;
// Independent bounded numerical API. Every access to an instance, including
// getters/save/destruction, is serialized or protected by the host mix lock.
// Default nearest-even FP environment; tested macOS arm64/Apple clang21 with
// -std=c++20 -O2 -ffp-contract=off -fno-fast-math. NaN/Inf parity is
// unverified. Valid readable/writable caller buffers are external to the live
// instance. Any buffer range overlapping it rejects before access; a zero-frame
// sample pointer inside the live instance also rejects. Rejection preserves
// instance and caller result/output bytes. These checks extend the independent
// C ABI; no equivalence for original malformed inputs is claimed.
VLCenterPlugin *vl_center_create(void);
void vl_center_destroy(VLCenterPlugin *plugin);
// index0; raw0/1 or normalized0..2^30; flags0/1/2/3/32/33/34/35.
// Requires a valid result pointer. Set has priority over get.
int vl_center_parameter(VLCenterPlugin *plugin, int32_t index, int32_t value,
                        uint32_t flags, int32_t *result);
// Positive integer rates8000..384000; coefficient changes preserve filter
// state.
int vl_center_sample_rate(VLCenterPlugin *plugin, int32_t sample_rate);
// Original resume clears filter runtime; enable/coefficients remain unchanged.
int vl_center_resume(VLCenterPlugin *plugin);
// Interleaved float stereo, finite abs(input)<=16; frames0..1024. Valid exact
// alias or disjoint buffers, partial overlap rejected. Null buffers only when
// frames0. Enabled processing flushes small internal doubles at every block
// end, including zero frames. Disabled processing copies bitwise and preserves
// state.
int vl_center_render(VLCenterPlugin *plugin, const float *input, float *output,
                     int32_t frames);
// Exactly8 LE bytes: version1 and enable0/1. Restore accepts version0/1 and
// preserves coefficients/filter history; invalid versions/values reject
// atomically.
int vl_center_save_state(const VLCenterPlugin *plugin, uint8_t *bytes,
                         size_t length);
int vl_center_restore_state(VLCenterPlugin *plugin, const uint8_t *bytes,
                            size_t length);
// Own numerical inspection: L/R position followed by L/R velocity (four
// doubles).
int vl_center_get_filter_state(const VLCenterPlugin *plugin, double *values);
#ifdef __cplusplus
}
#endif

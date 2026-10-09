#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VLFastDistPlugin VLFastDistPlugin;
// Independent bounded numerical API. ALL instance access, including getters,
// save and destruction, is serialized or protected by the host mix lock.
// Default nearest-even FP; tested Apple arm64/clang21 with contraction off,
// no-fast-math, and no-builtin-exp/log. Valid caller buffers must be external
// to live instance storage. Overlapping instance ranges reject before access,
// including zero-frame pointers starting inside. Own invalid-input rejection
// extends this API; no malformed-original equivalence is claimed.
// Quality0/1 selects the verified integer/interpolated host DSP branch.
// Original application configuration/lifecycle choosing quality is not
// reconstructed.
VLFastDistPlugin *vl_fast_dist_create(int32_t quality);
void vl_fast_dist_destroy(VLFastDistPlugin *plugin);
int vl_fast_dist_quality(VLFastDistPlugin *plugin, int32_t quality);
// indices0..4:raw ranges64..192,1..10,0..1,0..128,0..128. Normalized0..2^30.
// flags0/1/2/3/32/33/34/35;set has priority over get. Raw getter ignores input
// value;normalized getter input remains bounded. Result is a valid external
// int32. UI, hint and remaining host flag contracts excluded.
int vl_fast_dist_parameter(VLFastDistPlugin *plugin, int32_t index,
                           int32_t value, uint32_t flags, int32_t *result);
// Finite stereo float abs(input)<=16,frames0..1024,exact alias or disjoint.
// Partial overlap rejected;null sample buffers only when frames0. No render
// allocations. Independently generated immutable tables initialize on create.
int vl_fast_dist_render(VLFastDistPlugin *plugin, const float *input,
                        float *output, int32_t frames);
// Exactly20 little-endian bytes:five raw int32 values,no version. Restore
// validates the entire packet atomically and preserves host-quality choice.
int vl_fast_dist_save_state(const VLFastDistPlugin *plugin, uint8_t *bytes,
                            size_t length);
int vl_fast_dist_restore_state(VLFastDistPlugin *plugin, const uint8_t *bytes,
                               size_t length);
// Own inspection:dry,wet,multiplier as3floats;valid external output.
int vl_fast_dist_get_coefficients(const VLFastDistPlugin *plugin,
                                  float *values);
#ifdef __cplusplus
}
#endif

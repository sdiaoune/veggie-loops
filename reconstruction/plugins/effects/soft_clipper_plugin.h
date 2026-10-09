#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Independent numerical C API. All instance access, including getters, state,
// render, metering and destruction, requires serialized calls or host mix lock.
// Every caller result/sample/state/meter buffer requires valid
// readable/writable storage as appropriate, outside the live instance. Ranges
// overlapping instance storage reject before caller-buffer access, including
// zero-frame buffer starts inside it. This overlap rejection is an independent
// ABI validation extension. Native FL/editor/VST/AU/application integration is
// a separate obligation.
typedef struct VLSoftClipperPlugin VLSoftClipperPlugin;
VLSoftClipperPlugin *vl_soft_clipper_create(void);
void vl_soft_clipper_destroy(VLSoftClipperPlugin *);
// Threshold raw1..127 default100; postgain raw0..160 default128. Flags1=set,
// 2=get,32=normalize MIDI0..2^30 with nearest-even rounding in the default FP
// environment. Rejected input preserves state and result. Flags outside35
// reject.
int vl_soft_clipper_parameter(VLSoftClipperPlugin *, int32_t index,
                              int32_t value, uint32_t flags, int32_t *result);
// Interleaved finite float stereo, abs(input)<=16, frames0..1024. Valid
// identical or disjoint buffers; partial overlap rejects before changing
// output/state. The knee maps negative zero to positive zero. Postgain follows
// knee/metering. NaN/Inf, other FP environments and compiler flags are outside
// the proof domain.
int vl_soft_clipper_render(VLSoftClipperPlugin *, const float *, float *,
                           int32_t frames);
// Cumulative pre-postgain stereo peaks, enabled by default. The measured NEON
// meter tail uses signed samples after each full group of eight stereo frames.
// Enable/clear are independent numerical controls: their render effects are
// compared to explicit synthetic source-object meter state, not a source GUI.
int vl_soft_clipper_metering(VLSoftClipperPlugin *, int enabled);
int vl_soft_clipper_clear_meters(VLSoftClipperPlugin *);
int vl_soft_clipper_get_meters(const VLSoftClipperPlugin *, float *two_peaks);
// Exactly8 little-endian bytes: threshold and postgain raw words, no version.
// Valid states preserve meters. Malformed restore rejection is an independent
// atomic validation extension; only valid framing is compared with the source.
int vl_soft_clipper_save_state(const VLSoftClipperPlugin *, void *, size_t);
int vl_soft_clipper_restore_state(VLSoftClipperPlugin *, const void *, size_t);
#ifdef __cplusplus
}
#endif

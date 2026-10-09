#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// New prepared-state ABI, not a native class/factory or complete Purity plugin.
typedef struct {
    uint64_t reserved0;
    float sample_rate;
    uint32_t reserved1[5];
    float threshold, ratio, release;
    float target_threshold, target_ratio, target_release;
    uint8_t dirty;
    uint8_t reserved2[3];
    float gain;
} VLPurityPeakCompressor;
// Caller supplies non-overlapping state/audio storage; left/right may be
// disjoint or exactly identical. Count0..8192; null audio allowed at count0.
// Finite sample rate8000..192000; coefficient/gain fields0..1; input samples
// finite[-4,4]. Invalid arguments return0 without changing state or audio.
int vl_purity_peak_compress(VLPurityPeakCompressor*, float* left, float* right, int32_t count);
#ifdef __cplusplus
}
#endif

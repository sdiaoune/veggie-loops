#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// New caller-owned mathematical ABI, not a complete native plugin ABI.
typedef struct {
    int32_t stage;
    uint32_t reserved0;
    double position;
    float level;
    float increment;
    float release_scale;
    uint32_t reserved1;
} VLPurityEnvelopeFollower;
// Curve holds259 generated floats. Steps holds attack, decay, release motion
// per block. Verified domain: stage0..5, position0..255, attack/sustain0..1,
// steps0..510, finite level/prior increment, release scale-2..2, count1..8192,
// finite curve values0..1. Cubic interpolation can overshoot the unit interval.
// Only state changes; invalid inputs return0 with state untouched.
int vl_purity_envelope_follow(float attack, float sustain,
    VLPurityEnvelopeFollower* state, const double* steps,
    const float* curve, int32_t count);
#ifdef __cplusplus
}
#endif

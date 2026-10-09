// Independently written parameter conversion/range subset. MIT.
#ifndef VL_TYRELL_PARAMETER_SCALE_H
#define VL_TYRELL_PARAMETER_SCALE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VLTyrellParameterRange {
    int32_t public_index;
    int32_t identifier;
    float minimum;
    float maximum;
} VLTyrellParameterRange;
// Returns a stable read-only range for public index 0..91, or 10000+identifier
// for these same 92 descriptors. Other internal IDs are outside this subset.
const VLTyrellParameterRange* vl_tyrell_parameter_range(int32_t index);
// Finite ordered endpoints abs<=512. Separate single-precision operations,
// nearest-even rounding and compiler flags -ffp-contract=off -fno-fast-math.
// Subnormal handling is gradual: FTZ/DAZ/FZ disabled. Other FP settings are
// outside the verified domain.
// Denormalization supports finite normalized values in [-2,2] without clipping.
// Normalization supports finite raw abs<=4096; a zero-width range returns its
// minimum. Non-finite computed results are rejected. Returns 1 on success, 0
// on invalid arguments without changing output. Output must be valid writable
// float storage; arbitrary pointer validity is the caller's responsibility.
int vl_tyrell_parameter_denormalize(float minimum, float maximum,
                                   float normalized, float* output);
int vl_tyrell_parameter_normalize(float minimum, float maximum,
                                 float raw, float* output);
#ifdef __cplusplus
}
#endif
#endif

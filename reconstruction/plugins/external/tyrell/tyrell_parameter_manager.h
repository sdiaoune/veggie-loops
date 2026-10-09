// Independently written bounded parameter-controller subset. MIT.
#ifndef VL_TYRELL_PARAMETER_MANAGER_H
#define VL_TYRELL_PARAMETER_MANAGER_H
#include "tyrell_parameter_scale.h"
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct VLTyrellParameterDescriptor {
    VLTyrellParameterRange range;
    uint32_t type;
} VLTyrellParameterDescriptor;

// A caller-owned prepared backend, not a native Tyrell class or factory preset.
// Access to one instance, including reads/preparation, must be serialized.
typedef struct VLTyrellParameterManager {
    float raw[92];
    float clock;
    int32_t last_identifier;
} VLTyrellParameterManager;

// Records the manager decision and downstream ABI arguments. The independent
// backend commits changed values synchronously; real audio-target scheduling,
// callbacks, thread/RT behavior and native object layout are outside this API.
// input/type/clock are diagnostic fields. Getter and notifier argument fields
// describe actual calls only when their corresponding call count is nonzero.
typedef struct VLTyrellParameterWrite {
    int32_t identifier;
    uint32_t descriptor_type;
    uint32_t ignored;
    uint32_t getter_calls;
    uint32_t notifier_calls;
    float input;
    float getter_fallback;
    float previous;
    float value;
    float clock;
    int32_t getter_flag;
    int32_t notifier_flag;
} VLTyrellParameterWrite;

// Flag must be exactly 1 (public 0..91) or 0 (one of those 92 internal IDs).
// These descriptors carry actual published type 0/1 and range facts. The
// minimum/maximum do not clamp manager writes.
int vl_tyrell_parameter_descriptor(int32_t index, int32_t public_flag,
                                  VLTyrellParameterDescriptor* output);

// Prepared scalar decision. Finite |input|,|previous|<=4096; finite clock;
// identifier 0..212; type byte 0..255. Types 0/5 floor a separately rounded
// single-precision (input+0.5f); type 3 ignores the write before getter/last-ID
// changes (the native warning logger is excluded); other types pass through.
// Only types 0/1 occur in the 92 actual descriptors. Additional type behavior
// is compared with a synthetic descriptor table, not actual type-3/5 controls.
int vl_tyrell_parameter_decide(int32_t identifier, uint32_t type, float input,
                              float previous, float clock,
                              VLTyrellParameterWrite* output);

// Preparation takes exactly 92 finite raw values with abs<=4096, finite clock,
// and last_identifier=-1 or a supported internal ID. All state calls validate
// the complete prepared record before changing it. Floating-point contract:
// nearest-even, gradual subnormals, -ffp-contract=off -fno-fast-math.
int vl_tyrell_parameter_manager_prepare(const float* raw, uint32_t count,
                                       float clock, int32_t last_identifier,
                                       VLTyrellParameterManager* output);
int vl_tyrell_parameter_manager_clock(VLTyrellParameterManager* manager, float clock);
int vl_tyrell_parameter_manager_get(const VLTyrellParameterManager* manager,
                                   int32_t index, int32_t public_flag, float* output);
int vl_tyrell_parameter_manager_write(VLTyrellParameterManager* manager,
                                     int32_t index, int32_t public_flag, float input,
                                     VLTyrellParameterWrite* output);

// Success=1, rejection=0 with every supplied state/output byte unchanged.
// State/output storage and preparation input/output must be disjoint (including
// partial overlap). Storage must be valid and correctly aligned for its type;
// arbitrary pointer validity cannot be tested by this API. Invalid arguments
// are never forwarded to the original binary by the differential fixture.
#ifdef __cplusplus
}
#endif
#endif

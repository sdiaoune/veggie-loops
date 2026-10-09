#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Original bounded C API for independently written live C++ compressor objects.
// All handle/object/stream/audio access and destruction must be serialized.
// Kinds5/6 normalize to Peak6, kind7 selects RMS7. Other kinds are rejected.
typedef struct VLPurityLiveCompressor VLPurityLiveCompressor;
typedef struct {
    uint32_t version;
    int32_t kind;
    uint32_t object_bytes, initialized;
    float sample_rate;
    uint32_t reserved0;
    double bpm, ppq;
    float current[3], targets[3];
    uint8_t dirty, wet_only;
    uint16_t reserved1;
    float gain, detector;
    uint32_t reserved2;
} VLPurityLiveSnapshot;
VLPurityLiveCompressor* vl_purity_live_create(int32_t kind, int32_t enabled);
void vl_purity_live_destroy(VLPurityLiveCompressor*);
// Allocate first, then replace; allocation/argument failure preserves old object
// and history. This atomic failure policy extends the original delete-first factory.
int vl_purity_live_replace(VLPurityLiveCompressor*, int32_t kind, int32_t enabled);
int vl_purity_live_sample_rate(VLPurityLiveCompressor*, float rate); // finite8000..192000
int vl_purity_live_bpm(VLPurityLiveCompressor*, double bpm); // finite
int vl_purity_live_ppq(VLPurityLiveCompressor*, double ppq); // finite
int vl_purity_live_parameters(VLPurityLiveCompressor*, const float* three_values); // finite0..1
int vl_purity_live_wet_only(VLPurityLiveCompressor*, int32_t value); //0/1
// Operations0=commonInit,1=init,2=commonPrepare,3=prepare,4=commonCalc,5=calc.
// Init resets gain/detector only if dirty==0. For a disabled object, init after
// commonInit/prepare is rejected because the native history would still be
// undefined. A count0 process clears dirty; init can then establish valid history.
int vl_purity_live_lifecycle(VLPurityLiveCompressor*, int32_t operation);
// Count0..8192, left/right disjoint or identical; state/handle/object/audio storage
// must not overlap. Positive counts require successful init, rate and targets.
// Fresh finite input[-4,4] for each block; makeup output may exceed that range.
// Zero count accepts null audio and clears dirty even before configuration/init.
// Invalid calls preserve all numerical state and audio. Default FP environment.
int vl_purity_live_process(VLPurityLiveCompressor*, float* left, float* right, int32_t count);
int vl_purity_live_snapshot(const VLPurityLiveCompressor*, VLPurityLiveSnapshot*);
// Bounded, atomic formatting. Index0..2, normalized value0..1. Display uses the
// stored target, including native constructor sentinel-1. Caller supplies valid
// non-overlapping output storage. Rejection leaves output unchanged.
int vl_purity_live_format(VLPurityLiveCompressor*, int32_t index, float value, char* output, size_t capacity);
int vl_purity_live_display(VLPurityLiveCompressor*, int32_t index, char* output, size_t capacity);
// Read-only borrowed address of the real64/72-byte C++ object, invalidated by
// replacement/destruction. Its own sixteen-slot ABI is available for differential
// fixtures; callers must obey live_compressor.hpp preconditions. No native VST/AU
// class/factory identity or application integration is claimed.
const void* vl_purity_live_object(const VLPurityLiveCompressor*);
#ifdef __cplusplus
}
#endif

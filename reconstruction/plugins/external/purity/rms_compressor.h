#pragma once
#include "peak_compressor.h"
#ifdef __cplusplus
extern "C" {
#endif
// New prepared-state ABI. The inspected RMS-named variant smooths the stereo
// mean absolute level; it does not square samples or take a square root.
typedef struct {
    VLPurityPeakCompressor base;
    float detector;
    uint32_t reserved3;
} VLPurityRMSCompressor;
// Same domain/storage rules as the prepared peak routine, with additional
// finite detector[0,131072]. Audio input is freshly bounded for each block;
// makeup output may exceed the allowed input range. Invalid calls are atomic.
int vl_purity_rms_compress(VLPurityRMSCompressor*, float* left, float* right, int32_t count);
#ifdef __cplusplus
}
#endif

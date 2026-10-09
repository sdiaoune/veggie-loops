#pragma once
// Prepared cosine/linear declick tables and precomputed release application.
// No native allocation, dynamic 64-sample cache, mode1/2 state or host routing.
#include "three_osc_envelope.hpp"
#include <cstdint>

namespace veggie_loops::three_osc::declick {
using Curve=envelope::Curve;
// Positive zero or prepared finite curve, |amount| in[2^-23,64] when nonzero.
// shape3=raised cosine, shape4=linear; direction0=initial,1=release.
// totalFrames in[1,65536], offset>=0, count>=1, offset+count<=totalFrames.
// output has count writable floats. Uses Apple's Accelerate vector arithmetic
// to match the observed macOS DSP wrapper's system calls and float rounding.
// Native generation comparison covers count64. Other counts are an independent
// generalization, without native table-generation equivalence evidence here.
// Allocation failure is outside this prepared-arithmetic contract; temporary
// storage allocation can throw and the thin C adapter is not a total C API.
void generate(const Curve&,int shape,int direction,std::int32_t offset,
              std::int32_t totalFrames,float* output,std::int32_t count);

struct ReleaseState {std::int32_t position=-1,waitFrames=0;};
// Prepared table has tableFrames readable floats, tableFrames in[1,65536].
// stereo is interleaved with2*frames writable finite floats; frames in[0,2^20].
// position is-1(not released) or[0,2^30], waitFrames in[0,2^30]. Successful
// calls do not overflow position. No table/output overlap is allowed.
void applyRelease(const float* table,std::int32_t tableFrames,ReleaseState&,
                  float* stereo,std::int32_t frames);
}

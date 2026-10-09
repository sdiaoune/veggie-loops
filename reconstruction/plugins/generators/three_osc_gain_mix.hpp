#pragma once
// Independent stereo accumulation primitives. Native Fruity factory, filter,
// voice scheduling and complete generator output are not implemented here.
#include <cstdint>

namespace veggie_loops::three_osc::gain_mix {
// Preconditions: source/destination are non-overlapping interleaved stereo
// buffers with 2*frames readable/writable floats; frames in[0,2^20]; finite
// |samples|,|initial gains|<=4 and |steps|<=1. Separate float multiply/add
// rounding is required (-fno-fast-math -ffp-contract=off).
inline void fixed(float left,float right,const float* source,float* destination,
                  std::uint32_t frames) {
  for(std::uint32_t i=0;i<frames;++i) {
    const float l=left*source[2*i];
    const float r=right*source[2*i+1];
    destination[2*i]=l+destination[2*i];
    destination[2*i+1]=r+destination[2*i+1];
  }
}

inline void ramp(float left,float right,float leftStep,float rightStep,
                 const float* source,float* destination,std::uint32_t frames) {
  // The observed SIMD routine holds even/odd-frame gains separately, each
  // advancing by a separately rounded twice-step. Its scalar remainder uses
  // the opposite channel's increment; that observable tail is preserved.
  float evenLeft=left+0.0f,evenRight=right+0.0f;
  float oddLeft=left+leftStep,oddRight=right+rightStep;
  if(frames>=8) {
    const float twiceLeft=leftStep+leftStep,twiceRight=rightStep+rightStep;
    while(frames>=8) {
      for(int pair=0;pair<4;++pair) {
        const float l0=evenLeft*source[0],r0=evenRight*source[1];
        const float l1=oddLeft*source[2],r1=oddRight*source[3];
        destination[0]=l0+destination[0];destination[1]=r0+destination[1];
        destination[2]=l1+destination[2];destination[3]=r1+destination[3];
        evenLeft=twiceLeft+evenLeft;evenRight=twiceRight+evenRight;
        oddLeft=twiceLeft+oddLeft;oddRight=twiceRight+oddRight;
        source+=4;destination+=4;
      }
      frames-=8;
    }
  }
  while(frames>0) {
    const float l=evenLeft*source[0],r=evenRight*source[1];
    destination[0]=destination[0]+l;destination[1]=destination[1]+r;
    evenLeft=rightStep+evenLeft;evenRight=leftStep+evenRight;
    source+=2;destination+=2;--frames;
  }
}
}

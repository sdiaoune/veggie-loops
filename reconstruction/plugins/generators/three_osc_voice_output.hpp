#pragma once
// Independently reconstructed pan and block gain-slew primitives. These do
// not implement the per-voice filter, output mixer or wrapper lifecycle.
#include <bit>
#include <cmath>
#include <cstdint>

namespace veggie_loops::three_osc::voice_output {
// Finite pan; |volume|<=4, law0/1, finite compensation in(0,1].
inline void gains(float pan,float volume,int law,float compensation,float& left,float& right) {
  pan=pan<-1.0f ? -1.0f : pan>1.0f ? 1.0f : pan;
  if(law==1) {
    const float gain=volume*compensation;
    if(std::signbit(pan)) {left=gain;right=gain*(pan+1.0f);}
    else {left=gain*(1.0f-pan);right=gain;}
  } else {
    const float shifted=pan+1.0f;
    const float angle=static_cast<float>(static_cast<double>(shifted)*0.7853981633974483);
    float sine,cosine;
#if defined(__APPLE__)
    // The reviewed routine uses Darwin's joint sin/cos range reduction.
    ::__sincosf(angle,&sine,&cosine);
#else
    sine=std::sin(angle);cosine=std::cos(angle);
#endif
    left=cosine*volume;right=sine*volume;
  }
}
// Finite previous/target with magnitude<=4; maxStep in(0,4], frames in1..2^20,
// threshold in[0,1] encoded as float bits. No gain/output buffer
// processing is implied; target and step are the native block boundary values.
inline void slew(float previous,float maxStep,std::uint32_t silenceThresholdBits,
                  std::int32_t frames,float& step,float& target) {
  step=target-previous;
  if(std::bit_cast<std::uint32_t>(step)!=0) {
    step=step/static_cast<float>(frames);
    if(std::fabs(step)>maxStep) {
      step=std::bit_cast<float>(std::bit_cast<std::uint32_t>(maxStep)|
                               (std::bit_cast<std::uint32_t>(step)&0x80000000u));
      target=previous+(step*static_cast<float>(frames));
      if((std::bit_cast<std::uint32_t>(target)&0x7fffffffu)<silenceThresholdBits) {
        target=0;step=-previous/static_cast<float>(frames);
      }
    }
  }
}
}

#include "three_osc_gain_mix.hpp"
extern "C" void vl_osc_mix_fixed(float left,float right,const float* source,
                                 float* destination,std::uint32_t frames) {
  veggie_loops::three_osc::gain_mix::fixed(left,right,source,destination,frames);
}
extern "C" void vl_osc_mix_ramp(float left,float right,float leftStep,float rightStep,
                                const float* source,float* destination,std::uint32_t frames) {
  veggie_loops::three_osc::gain_mix::ramp(left,right,leftStep,rightStep,source,destination,frames);
}

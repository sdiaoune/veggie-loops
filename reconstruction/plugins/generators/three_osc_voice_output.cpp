#include "three_osc_voice_output.hpp"
extern "C" void vl_osc_voice_gains(float pan,float volume,int law,float compensation,float* left,float* right) {
  veggie_loops::three_osc::voice_output::gains(pan,volume,law,compensation,*left,*right);
}
extern "C" void vl_osc_voice_slew(float previous,float maximum,std::uint32_t threshold,int frames,float* step,float* target) {
  veggie_loops::three_osc::voice_output::slew(previous,maximum,threshold,frames,*step,*target);
}

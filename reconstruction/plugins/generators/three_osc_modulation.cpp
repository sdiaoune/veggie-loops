#include "three_osc_modulation.hpp"
using namespace veggie_loops::three_osc::modulation;
extern "C" void vl_osc_modulation_step(const Configurations* cfg,State* state) {step(*cfg,*state);}
extern "C" void vl_osc_modulation_release(const Configurations* cfg,State* state) {release(*cfg,*state);}
extern "C" void vl_osc_modulation_tick_pitch(const Configurations* cfg,State* state,int newTick,int counter,float* finalPitch) {
  tickPitch(*cfg,*state,newTick!=0,counter,*finalPitch);
}

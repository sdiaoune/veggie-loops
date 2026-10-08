#include "../generators/three_osc_wrapper_core.h"
#include <array>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
void compute(void*,float* l,float* r,float,float v){*l=v;*r=v;}
void require(bool condition,const char* message){if(!condition)throw std::runtime_error(message);}
std::array<uint32_t,6> phases(vl_osc_voice* voice){
 std::array<uint32_t,6> result{};uint8_t stereo=0;vl_osc_core_voice_phases(voice,result.data(),&stereo);return result;
}
int main(){try{
 auto* core=vl_osc_core_create(compute,nullptr);
 require(core,"create");
 vl_osc_core_parameter(core,1,5,1); // Noise in the first oscillator makes early RNG mutation observable.
 vl_osc_core_parameter(core,20,64,1);
 vl_osc_random_state random{};random.index=0;random.seed=random.previous_seed=123;
 for(uint32_t i=0;i<624;++i)random.words[i]=i*1812433253u+17;
 require(vl_osc_core_random_state(core,&random),"set RNG");
 auto* voice=vl_osc_core_trigger(core,4);
 require(voice,"trigger");
 const auto before=phases(voice);
 std::array<float,4> buffer{.25f,-.5f,42,43};
 for(float cents:{1e9f,std::numeric_limits<float>::max(),std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()}){
  const auto old=buffer;
  require(!vl_osc_core_render(core,voice,cents,buffer.data(),1),"invalid pitch accepted");
  require(buffer==old && phases(voice)==before,"invalid pitch mutated output/phase");
 }
 auto* after=vl_osc_core_trigger(core,5);require(after,"second trigger");const auto afterPhases=phases(after);
 vl_osc_core_kill(core,voice);vl_osc_core_kill(core,after);
 require(vl_osc_core_random_state(core,&random),"reset RNG");
 auto* referenceFirst=vl_osc_core_trigger(core,4);auto* referenceSecond=vl_osc_core_trigger(core,5);
 require(referenceFirst && referenceSecond && phases(referenceSecond)==afterPhases,"invalid render consumed RNG");
 require(vl_osc_core_render(core,referenceFirst,6000,buffer.data(),1),"normal render rejected");
 require(buffer[2]==42 && buffer[3]==43,"normal render overwrote buffer guard");
 std::array<uint8_t,89> preset{},afterPreset{};require(vl_osc_core_save_prefix(core,preset.data(),preset.size()),"save prefix");
 vl_osc_core_parameter(core,2,std::numeric_limits<int32_t>::max(),1);
 vl_osc_core_parameter(core,6,-1,33);
 require(vl_osc_core_save_prefix(core,afterPreset.data(),afterPreset.size()) && preset==afterPreset,"invalid parameter mutated preset");
 vl_osc_core_destroy(core);
 std::cout<<"{\"status\":\"passed\",\"invalid_pitch_atomic\":true,\"rng_unchanged_on_rejection\":true,\"normal_buffer_guard\":true,\"invalid_parameter_atomic\":true}\n";
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}

#include "three_osc_prepared_voice.h"
#include "three_osc_modulation.hpp"
#include "three_osc_envelope_coefficients.hpp"
#include "three_osc_filter_routing.hpp"
#include "three_osc_declick.hpp"
#include "three_osc_gain_mix.hpp"
#include <memory>
#include <new>
#include <vector>
using namespace veggie_loops::three_osc;
struct vl_osc_prepared_voice {
  vl_osc_core* core=nullptr;vl_osc_voice* raw=nullptr;
  std::array<const float*,3> tables{};
  modulation::Configurations configs;
  modulation::State modulation;
  filter_routing::State filter;
  filter::Context context;
  std::vector<float> releaseTable;
  double tempo=120;uint32_t clock=240;
  float left=-1,right=-1;
};
namespace {
template<class T>T payloadValue(const std::array<uint8_t,456>& bytes,size_t offset) {T value;std::memcpy(&value,bytes.data()+offset,sizeof(value));return value;}
bool configuration(vl_osc_prepared_voice& voice,modulation::Configurations& out,int& rawCutoff,int& rawResonance) {
  std::array<uint8_t,456> bytes{};if(!vl_osc_core_save_payload(voice.core,bytes.data(),bytes.size()))return false;
  rawCutoff=payloadValue<int>(bytes,440);rawResonance=payloadValue<int>(bytes,444);
  if(rawCutoff<0 || rawCutoff>256 || rawResonance<0 || rawResonance>256 || payloadValue<int>(bytes,452)!=0)return false;
  for(size_t i=0;i<5;++i) {
    auto& cfg=out[i];std::memcpy(cfg.raw.data(),bytes.data()+92+i*68,68);
    if(cfg.raw[0]<0 || cfg.raw[0]>31 || cfg.raw[1]<0 || cfg.raw[1]>1 || cfg.raw[6]<0 || cfg.raw[6]>128 ||
       cfg.raw[8]<-128 || cfg.raw[8]>128 || cfg.raw[11]<-128 || cfg.raw[11]>128 || cfg.raw[13]<0 || cfg.raw[13]>2)return false;
    for(int index:{2,3,4,5,7,9,10,12})if(cfg.raw[size_t(index)]<0 || cfg.raw[size_t(index)]>65536)return false;
    for(int index:{14,15,16})if(cfg.raw[size_t(index)]<-128 || cfg.raw[size_t(index)]>128)return false;
    // Keep combined filter controls in the reviewed normalized routing domain.
    if((i==2 || i==3) && (std::abs(cfg.raw[8])>32 || std::abs(cfg.raw[11])>32))return false;
    envelope::prepareConfiguration(cfg,voice.tempo,voice.clock,voice.tables);
  }
  return true;
}
}
extern "C" vl_osc_prepared_voice* vl_osc_prepared_voice_create(vl_osc_core* core,vl_osc_voice* raw,int32_t initialRate,
 int32_t currentRate,double tempo,uint32_t clock,const float* const tables[3]) {
  if(!core || !raw || !tables || initialRate<8000 || initialRate>384000 || currentRate<8000 || currentRate>384000 ||
     !std::isfinite(tempo) || tempo<=0 || tempo>1000 || clock<4 || clock>(1u<<20))return nullptr;
  for(int i=0;i<3;++i)if(!tables[i])return nullptr;
  try {
    auto result=std::make_unique<vl_osc_prepared_voice>();result->core=core;result->raw=raw;result->tempo=tempo;result->clock=clock;
    std::copy_n(tables,3,result->tables.begin());result->context=filter::context(currentRate);
    int cutoff,resonance;if(!configuration(*result,result->configs,cutoff,resonance))return nullptr;
    modulation::initialize(result->configs,result->modulation);
    result->filter.initializerCounter=(result->modulation.groups[1].stage>1 ? 1:0)+1;
    const int count=int(std::nearbyint(10.0*0.001*double(initialRate)));
    result->releaseTable.resize(size_t(count));declick::generate({},3,1,0,count,result->releaseTable.data(),count);
    return result.release();
  }catch(const std::bad_alloc&) {return nullptr;}
}
extern "C" void vl_osc_prepared_voice_destroy(vl_osc_prepared_voice* voice) {delete voice;}
extern "C" void vl_osc_prepared_voice_release(vl_osc_prepared_voice* voice) {
  if(voice) {
    modulation::Configurations cfg;int cutoff,resonance;if(!configuration(*voice,cfg,cutoff,resonance))return;
    voice->configs=cfg;modulation::release(cfg,voice->modulation);vl_osc_core_release(voice->core,voice->raw);
  }
}
extern "C" int vl_osc_prepared_voice_render(vl_osc_prepared_voice* voice,vl_osc_prepared_parameters* parameters,int newTick,float* destination,uint32_t frames) {
  if(!voice || !parameters || !destination || newTick<0 || newTick>1 || frames<1 || frames>4096 ||
     !std::isfinite(parameters->pan) || std::fabs(parameters->pan)>1 || !std::isfinite(parameters->volume) || parameters->volume<0 || parameters->volume>1 ||
     !std::isfinite(parameters->pitch) || std::fabs(parameters->pitch)>2400 || !std::isfinite(parameters->mod_x) || std::fabs(parameters->mod_x)>0.25f ||
     !std::isfinite(parameters->mod_y) || std::fabs(parameters->mod_y)>0.25f || voice->modulation.declickPosition>INT32_MAX-4096)return 0;
  try {
    modulation::Configurations cfg;int rawCutoff,rawResonance;
    if(!configuration(*voice,cfg,rawCutoff,rawResonance))return 0;
    std::vector<float> raw(size_t(frames)*2),filtered(size_t(frames)*2);
    auto modulationState=voice->modulation;auto filterState=voice->filter;
    float finalPitch=parameters->pitch;
    modulation::tickPitch(cfg,modulationState,newTick!=0,filterState.initializerCounter,finalPitch);
    if(!vl_osc_core_render(voice->core,voice->raw,finalPitch,raw.data(),frames))return 0;
    float left,right;voice_output::gains(parameters->pan+modulationState.groups[0].combined,
                                       parameters->volume*modulationState.groups[1].combined,0,0.70710677f,left,right);
    float previousLeft=voice->left==-1 ? 0:voice->left,previousRight=voice->right==-1 ? 0:voice->right;
    if(filterState.initializerCounter>1) {previousLeft=left;previousRight=right;}
    const filter_routing::Inputs inputs{parameters->mod_x,parameters->mod_y,modulationState.groups[2].combined,
      modulationState.groups[3].combined,rawCutoff,rawResonance};
    float* audio=raw.data();
    if(filter_routing::process(filterState,inputs,voice->context,raw.data(),filtered.data(),int(frames),left,right))audio=filtered.data();
    declick::ReleaseState release{modulationState.declickPosition,modulationState.waitFrames};
    declick::applyRelease(voice->releaseTable.data(),int(voice->releaseTable.size()),release,audio,int(frames));
    modulationState.declickPosition=release.position;modulationState.waitFrames=release.waitFrames;
    const float maximum=float(double(voice->context.rateRatio)*0.001);float leftStep,rightStep;
    voice_output::slew(previousLeft,maximum,0x33800000u,int(frames),leftStep,left);
    voice_output::slew(previousRight,maximum,0x33800000u,int(frames),rightStep,right);
    if(std::bit_cast<uint32_t>(leftStep)==0 && std::bit_cast<uint32_t>(rightStep)==0)gain_mix::fixed(left,right,audio,destination,frames);
    else gain_mix::ramp(previousLeft,previousRight,leftStep,rightStep,audio,destination,frames);
    filterState.initializerCounter=0;voice->filter=filterState;voice->modulation=modulationState;
    voice->configs=cfg;voice->left=left;voice->right=right;parameters->pitch=finalPitch;return 1;
  }catch(const std::bad_alloc&) {return 0;}
}
extern "C" void vl_osc_prepared_voice_snapshot(const vl_osc_prepared_voice* voice,uint32_t* modulationWords,uint8_t* filterBytes,float* gains,int32_t* releaseValues) {
  if(voice) {
    if(modulationWords)std::memcpy(modulationWords,voice->modulation.groups.data(),180);
    if(filterBytes)std::memcpy(filterBytes,&voice->filter,112);
    if(gains) {gains[0]=voice->left;gains[1]=voice->right;}
    if(releaseValues) {releaseValues[0]=voice->modulation.declickPosition;releaseValues[1]=voice->modulation.waitFrames;releaseValues[2]=voice->modulation.released;}
  }
}

#include "three_osc_channel.h"
#include "three_osc_modulation.hpp"
#include "three_osc_envelope_coefficients.hpp"
#include "three_osc_filter_routing.hpp"
#include "three_osc_declick.hpp"
#include "three_osc_gain_mix.hpp"
#include "three_osc_voice_lifecycle.h"
#include <memory>
#include <new>
#include <vector>
using namespace veggie_loops::three_osc;
struct vl_osc_channel_voice {
  vl_osc_core* core=nullptr;vl_osc_voice* raw=nullptr;
  vl_osc_channel_parameters* parameters=nullptr;intptr_t tag=0;
  modulation::State modulation;filter_routing::State filter;
  float left=-1,right=-1;
  ~vl_osc_channel_voice() {if(raw)vl_osc_core_kill(core,raw);}
};
struct vl_osc_channel {
  vl_osc_core* core=nullptr;
  std::vector<std::unique_ptr<vl_osc_channel_voice>> voices;
  std::array<const float*,3> lfoTables{};
  std::vector<float> releaseTable;filter::Context filterContext;
  double tempo=120;uint32_t ppq=240;int32_t maxPoly=0;
  bool newTick=false;vl_osc_channel_notify_kill notify=nullptr;void* callbackContext=nullptr;
  ~vl_osc_channel() {voices.clear();if(core)vl_osc_core_destroy(core);}
};
namespace {
template<class T>T payloadValue(const std::array<uint8_t,456>& bytes,size_t offset) {T value;std::memcpy(&value,bytes.data()+offset,sizeof(value));return value;}
bool configuration(vl_osc_channel& channel,modulation::Configurations& out,int& rawCutoff,int& rawResonance) {
  std::array<uint8_t,456> bytes{};if(!vl_osc_core_save_payload(channel.core,bytes.data(),bytes.size()))return false;
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
    envelope::prepareConfiguration(cfg,channel.tempo,channel.ppq,channel.lfoTables);
  }
  return true;
}
}

namespace {
bool owned(const vl_osc_channel& channel,const vl_osc_channel_voice* voice) {
  return std::any_of(channel.voices.begin(),channel.voices.end(),[&](const auto& item){return item.get()==voice;});
}
void quick(vl_osc_channel_voice& voice) {
  vl_osc_lifecycle_state state{voice.modulation.declickPosition,voice.modulation.waitFrames,voice.modulation.released};
  vl_osc_lifecycle_quick_release(&state);
  voice.modulation.declickPosition=state.position;voice.modulation.waitFrames=state.wait_frames;voice.modulation.released=state.released;
  vl_osc_core_release(voice.core,voice.raw);
}
bool valid(const vl_osc_channel_levels& p) {
  return std::isfinite(p.pan) && std::fabs(p.pan)<=1 && std::isfinite(p.volume) && p.volume>=0 && p.volume<=1 &&
    std::isfinite(p.pitch) && std::fabs(p.pitch)<=2400 && std::isfinite(p.mod_x) && std::fabs(p.mod_x)<=.25f &&
    std::isfinite(p.mod_y) && std::fabs(p.mod_y)<=.25f;
}
bool renderVoice(vl_osc_channel& channel,vl_osc_channel_voice* voice,const modulation::Configurations& cfg,
 int rawCutoff,int rawResonance,float* rawBuffer,float* filteredBuffer,float* accumulator,uint32_t frames) {
    auto modulationState=voice->modulation;auto filterState=voice->filter;
    float finalPitch=voice->parameters->final.pitch;
    modulation::tickPitch(cfg,modulationState,channel.newTick,filterState.initializerCounter,finalPitch);
    if(!vl_osc_core_render(channel.core,voice->raw,finalPitch,rawBuffer,frames))return false;
    float left,right;voice_output::gains(voice->parameters->final.pan+modulationState.groups[0].combined,
                                       voice->parameters->final.volume*modulationState.groups[1].combined,0,0.70710677f,left,right);
    float previousLeft=voice->left==-1 ? 0:voice->left,previousRight=voice->right==-1 ? 0:voice->right;
    if(filterState.initializerCounter>1) {previousLeft=left;previousRight=right;}
    const filter_routing::Inputs inputs{voice->parameters->final.mod_x,voice->parameters->final.mod_y,modulationState.groups[2].combined,
      modulationState.groups[3].combined,rawCutoff,rawResonance};
    float* audio=rawBuffer;
    if(filter_routing::process(filterState,inputs,channel.filterContext,rawBuffer,filteredBuffer,int(frames),left,right))audio=filteredBuffer;
    declick::ReleaseState release{modulationState.declickPosition,modulationState.waitFrames};
    declick::applyRelease(channel.releaseTable.data(),int(channel.releaseTable.size()),release,audio,int(frames));
    modulationState.declickPosition=release.position;modulationState.waitFrames=release.waitFrames;
    const float maximum=float(double(channel.filterContext.rateRatio)*0.001);float leftStep,rightStep;
    voice_output::slew(previousLeft,maximum,0x33800000u,int(frames),leftStep,left);
    voice_output::slew(previousRight,maximum,0x33800000u,int(frames),rightStep,right);
    if(std::bit_cast<uint32_t>(leftStep)==0 && std::bit_cast<uint32_t>(rightStep)==0)gain_mix::fixed(left,right,audio,accumulator,frames);
    else gain_mix::ramp(previousLeft,previousRight,leftStep,rightStep,audio,accumulator,frames);
    filterState.initializerCounter=0;voice->filter=filterState;voice->modulation=modulationState;
    voice->left=left;voice->right=right;voice->parameters->final.pitch=finalPitch;return true;
}
}
extern "C" vl_osc_channel* vl_osc_channel_create(vl_osc_compute_lr compute,vl_osc_channel_notify_kill notify,
 void* context,int32_t rate,double tempo,uint32_t ppq,const float* const tables[6]) {
  if(!compute || !tables || rate<8000 || rate>384000 || !std::isfinite(tempo) || tempo<=0 || tempo>1000 || ppq<4 || ppq>(1u<<20))return nullptr;
  for(int i=0;i<6;++i)if(!tables[i])return nullptr;
  try {
    auto result=std::make_unique<vl_osc_channel>();result->tempo=tempo;result->ppq=ppq;result->notify=notify;result->callbackContext=context;
    result->core=vl_osc_core_create(compute,context);if(!result->core)return nullptr;
    if(!vl_osc_core_host_tables(result->core,tables) || !vl_osc_core_set_sample_rate(result->core,rate))return nullptr;
    std::copy_n(tables,3,result->lfoTables.begin());result->filterContext=filter::context(rate);
    result->releaseTable.resize(441);declick::generate({},3,1,0,441,result->releaseTable.data(),441);
    return result.release();
  }catch(const std::bad_alloc&) {return nullptr;}
}
extern "C" void vl_osc_channel_destroy(vl_osc_channel* channel) {delete channel;}
extern "C" int32_t vl_osc_channel_parameter(vl_osc_channel* channel,int32_t index,int32_t value,uint32_t flags) {
  return channel ? vl_osc_core_parameter(channel->core,index,value,flags):0;
}
extern "C" int vl_osc_channel_restore(vl_osc_channel* channel,const uint8_t* payload,size_t length) {
  return channel && vl_osc_core_restore_payload(channel->core,payload,length);
}
extern "C" void vl_osc_channel_max_poly(vl_osc_channel* channel,int32_t limit) {if(channel)channel->maxPoly=limit;}
extern "C" vl_osc_channel_voice* vl_osc_channel_trigger(vl_osc_channel* channel,vl_osc_channel_parameters* parameters,intptr_t tag) {
  if(!channel || !parameters || !valid(parameters->initial) || !valid(parameters->final) || channel->voices.size()>=(1u<<20))return nullptr;
  try {
    modulation::Configurations cfg;int cutoff,resonance;if(!configuration(*channel,cfg,cutoff,resonance))return nullptr;
    auto result=std::make_unique<vl_osc_channel_voice>();result->core=channel->core;result->parameters=parameters;result->tag=tag;
    modulation::initialize(cfg,result->modulation);result->filter.initializerCounter=(result->modulation.groups[1].stage>1 ? 1:0)+1;
    std::vector<uint8_t> flags;flags.reserve(channel->voices.size());for(const auto& voice:channel->voices)flags.push_back(voice->modulation.released);
    const int32_t selected=vl_osc_lifecycle_select(flags.data(),int32_t(flags.size()),channel->maxPoly);
    channel->voices.reserve(channel->voices.size()+1);
    result->raw=vl_osc_core_trigger(channel->core,tag);if(!result->raw)return nullptr;
    if(selected>=0)quick(*channel->voices[size_t(selected)]);
    auto* handle=result.get();channel->voices.push_back(std::move(result));return handle;
  }catch(const std::bad_alloc&) {return nullptr;}
}
extern "C" int vl_osc_channel_release(vl_osc_channel* channel,vl_osc_channel_voice* voice) {
  if(!channel || !owned(*channel,voice))return 0;
  modulation::Configurations cfg;int cutoff,resonance;if(!configuration(*channel,cfg,cutoff,resonance))return 0;
  modulation::release(cfg,voice->modulation);vl_osc_core_release(channel->core,voice->raw);return 1;
}
extern "C" int vl_osc_channel_quick_release(vl_osc_channel* channel,vl_osc_channel_voice* voice) {
  if(!channel || !owned(*channel,voice))return 0;quick(*voice);return 1;
}
extern "C" int vl_osc_channel_kill(vl_osc_channel* channel,vl_osc_channel_voice* voice) {
  if(!channel)return 0;
  const auto it=std::find_if(channel->voices.begin(),channel->voices.end(),[&](const auto& item){return item.get()==voice;});
  if(it==channel->voices.end())return 0;channel->voices.erase(it);return 1;
}
extern "C" void vl_osc_channel_new_tick(vl_osc_channel* channel) {if(channel)channel->newTick=true;}
extern "C" int vl_osc_channel_render(vl_osc_channel* channel,float* destination,uint32_t frames) {
  if(!channel || !destination || frames<1 || frames>4096)return 0;
  for(const auto& voice:channel->voices)if(!valid(voice->parameters->final) || voice->modulation.declickPosition>INT32_MAX-4096)return 0;
  if(channel->voices.empty())return 1;
  try {
    modulation::Configurations cfg;int cutoff,resonance;if(!configuration(*channel,cfg,cutoff,resonance))return 0;
    std::vector<float> raw(size_t(frames)*2),filtered(size_t(frames)*2),accumulator(size_t(frames)*2,0.0f);
    for(const auto& voice:channel->voices) {
      if(!renderVoice(*channel,voice.get(),cfg,cutoff,resonance,raw.data(),filtered.data(),accumulator.data(),frames))return 0;
      const vl_osc_lifecycle_state state{voice->modulation.declickPosition,voice->modulation.waitFrames,voice->modulation.released};
      if(vl_osc_lifecycle_finished(&state,int32_t(channel->releaseTable.size())) && channel->notify)channel->notify(channel->callbackContext,voice->tag,-1);
    }
    std::memcpy(destination,accumulator.data(),size_t(frames)*2*sizeof(float));
    channel->newTick=false;return 1;
  }catch(const std::bad_alloc&) {return 0;}
}
extern "C" size_t vl_osc_channel_voice_count(const vl_osc_channel* channel) {return channel ? channel->voices.size():0;}
extern "C" int vl_osc_channel_snapshot(const vl_osc_channel* channel,const vl_osc_channel_voice* voice,
 uint32_t* modulationWords,uint8_t* filterBytes,float* gains,int32_t* releaseValues,uint32_t* phases,uint8_t* stereo) {
  if(!channel || !owned(*channel,voice))return 0;
  if(modulationWords)std::memcpy(modulationWords,voice->modulation.groups.data(),180);
  if(filterBytes)std::memcpy(filterBytes,&voice->filter,112);
  if(gains) {gains[0]=voice->left;gains[1]=voice->right;}
  if(releaseValues) {releaseValues[0]=voice->modulation.declickPosition;releaseValues[1]=voice->modulation.waitFrames;releaseValues[2]=voice->modulation.released;}
  uint32_t fallbackPhases[6];uint8_t fallbackStereo;
  vl_osc_core_voice_phases(voice->raw,phases ? phases:fallbackPhases,stereo ? stereo:&fallbackStereo);return 1;
}

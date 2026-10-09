#pragma once
// Original bounded no-voice cache. Calls across every raw-engine/factory instance
// are serial; callbacks do not reenter. This adds no source factory/UI/RT claim.
#include "../../../../reconstruction/plugins/generators/live-context/immediate_coefficients.hpp"
#include "three_osc_sync_lfo.h"
#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <cstring>
#include <limits>
#include <type_traits>
namespace veggie_loops::three_osc::prevoice {
using Configurations=std::array<envelope::Configuration,5>;
inline bool tempoValid(double value) {
 const uint64_t bits=std::bit_cast<uint64_t>(value);
 return bits>0 && bits<=std::bit_cast<uint64_t>(1000.0);
}
inline bool contextValid(int32_t rate,double tempo,uint32_t ppq) {
 return rate>=8000&&rate<=384000&&tempoValid(tempo)&&ppq>=4&&ppq<=(1u<<20);
}
inline bool rawValid(const std::array<int32_t,17>& r,size_t group) {
 if(group>=5||r[0]<0||r[0]>63||r[1]<0||r[1]>1||r[6]<0||r[6]>128||r[8]<-128||r[8]>128||r[11]<-128||r[11]>128||r[13]<0||r[13]>2)return false;
 for(int i:{2,3,4,5,7,9,10,12})if(r[size_t(i)]<0||r[size_t(i)]>65536)return false;
 for(int i:{14,15,16})if(r[size_t(i)]<-128||r[size_t(i)]>128)return false;
 if((group==2||group==3)&&(r[8]<-32||r[8]>32||r[11]<-32||r[11]>32))return false;
 return true;
}
template<class T>T field(const uint8_t* bytes,size_t offset) {T result;std::memcpy(&result,bytes+offset,sizeof result);return result;}
inline bool payloadValid(const uint8_t* bytes,size_t length) {
 if(!bytes||length!=456)return false;
 constexpr std::array<int32_t,21> minima{-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0};
 constexpr std::array<int32_t,21> maxima{64,6,24,100,64,50,128,64,6,24,100,64,50,128,64,6,24,100,64,50,64};
 for(size_t i=0;i<21;++i){const int32_t v=field<int32_t>(bytes,i*4);if(v<minima[i]||v>maxima[i])return false;}
 if(bytes[87]>2)return false;
 for(size_t group=0;group<5;++group){std::array<int32_t,17> raw{};std::memcpy(raw.data(),bytes+92+group*68,68);if(!rawValid(raw,group))return false;}
 const int32_t cutoff=field<int32_t>(bytes,440),resonance=field<int32_t>(bytes,444),mode=field<int32_t>(bytes,452);
 return cutoff>=0&&cutoff<=256&&resonance>=0&&resonance<=256&&mode>=0&&mode<=7;
}
// These loaded defaults are actual native scalar facts, not results of calling
// SetSampleRate: fresh declickStep is literal .01f, and plugin phase scaler starts +0.
struct Rate {
 int32_t rate=44100;float ratio=1,maximumGainStep=.001f,declickStep=.01f,declickFixed=32.768f,pluginPhaseScaler=0;
 void delivered(int32_t value,float phaseScaler) {
  rate=value;ratio=static_cast<float>(44100.0/static_cast<double>(value));
  maximumGainStep=static_cast<float>(static_cast<double>(ratio)*.001);
  declickStep=maximumGainStep*10.f;declickFixed=maximumGainStep*32768.f;pluginPhaseScaler=phaseScaler;
 }
};
struct Cache {
 Configurations groups{};
 std::array<bool,5> valid{};
 std::array<double,5> preparedTempo{140,140,140,140,140};
 std::array<uint32_t,5> preparedPPQ{96,96,96,96,96};
 double tempo=140;uint32_t ppq=96;
 Rate rate{};vl_osc_sync_lfo_state synchronized{};
 void prepare(size_t group) {
  valid[group]=rawValid(groups[group].raw,group);
  if(valid[group])immediate::prepareConfiguration(groups[group],preparedTempo[group],preparedPPQ[group],{nullptr,nullptr,nullptr});
 }
 void initialize() {
  // Native object clearing is established by actual NewInstance120b0→memset.
  // All raw/curve zero fields are real defined zeros, not allocator residue.
  *this=Cache{};
  defaultGroups();synchronized.dirty=1;
 }
 void defaultGroups() {
  // Actual valid restore first runs the native raw-default preparation pass.
  // Zero curves preserve history; the forced volume release-101 overwrites it.
  for(size_t g=0;g<5;++g){preparedTempo[g]=tempo;preparedPPQ[g]=ppq;groups[g].raw={0,0,100,20000,20000,30000,50,20000,0,100,20000,0,32950,0,0,0,0};prepare(g);}
  groups[1].raw[0]=4;groups[1].raw[16]=-101;prepare(1);
 }
 bool groupPayload(const uint8_t* bytes,size_t group) {
  if(!bytes||group>=5)return false;std::array<int32_t,17> raw{};std::memcpy(raw.data(),bytes+92+group*68,68);
  if(!rawValid(raw,group))return false;
  groups[group].raw=raw;preparedTempo[group]=tempo;preparedPPQ[group]=ppq;prepare(group);
  vl_osc_sync_lfo_editor_changed(&synchronized);return true;
 }
 bool restore(const uint8_t* bytes,size_t length) {
  if(!payloadValid(bytes,length))return false;
  defaultGroups();
  for(size_t group=0;group<5;++group){std::memcpy(groups[group].raw.data(),bytes+92+group*68,68);preparedTempo[group]=tempo;preparedPPQ[group]=ppq;prepare(group);}
  vl_osc_sync_lfo_editor_changed(&synchronized);return true;
 }
 bool deliveredTempo(double value) {
  if(!tempoValid(value))return false;tempo=value;
  for(size_t g=0;g<5;++g){preparedTempo[g]=tempo;preparedPPQ[g]=ppq;prepare(g);}return true;
 }
 bool deliveredPPQ(uint32_t value) {if(value<4||value>(1u<<20))return false;ppq=value;return true;}
 bool deliveredRate(int32_t value,float phaseScaler) {if(value<8000||value>384000)return false;rate.delivered(value,phaseScaler);return true;}
 bool ready()const{return std::all_of(valid.begin(),valid.end(),[](bool value){return value;});}
};
struct Snapshot {
 Configurations groups;
 std::array<uint32_t,5> valid;
 std::array<double,5> preparedTempo;
 std::array<uint32_t,5> preparedPPQ;
 double tempo;uint32_t ppq;Rate rate;vl_osc_sync_lfo_state synchronized;
 uint32_t channelAvailable,voiceCount;
};
static_assert(std::is_trivially_copyable_v<Cache>&&std::is_trivially_copyable_v<Snapshot>);
inline bool overlap(const void*a,size_t an,const void*b,size_t bn) {
 const uintptr_t x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);
 if(an>UINTPTR_MAX-x||bn>UINTPTR_MAX-y)return true;
 return x<y+bn&&y<x+an;
}
}

#include "three_osc_native_factory.h"
#include "prevoice_channel.hpp"
#include "three_osc_legacy_tables.hpp"
#include <array>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <memory>
#include <vector>
#include <type_traits>
// The exact immutable implementation is compiled once here; it is omitted
// from the separate link inputs. This permits a typed read of its owned field,
// with no copied layout, aliasing UB, redefined inline function or extra divide.
#include "three_osc_wrapper_core.cpp"
extern "C" float vl_private_prevoice_core_scaler(const vl_osc_core*core){return core?core->phase_scaler:0.f;}
using namespace vl_private_osc;
namespace {
// Runtime construction avoids unaligned pointer relocation entries in the
// packed host record. After the one-time guarded initialization it is const.
__attribute__((noinline,optnone)) Info makeInfo(const char*longName,const char*shortName) {
 return {1,longName,shortName,(1<<21)|1|16|32,114,0,0,0,{}};
}
const Info& metadata(){static const Info value=makeInfo("VL 3 Osc private factory","VL 3 Osc");return value;}
struct Instance {
 Plugin header{};void*host=nullptr;vl_osc_core*storage=nullptr;vl_osc_multimode_channel*channel=nullptr;
 veggie_loops::three_osc::prevoice::Cache cache{};int32_t max_poly=0;
 std::vector<float>tables;std::array<const float*,6>tablePointers{};
 ~Instance(){if(channel)vl_osc_multimode_channel_destroy(channel);if(storage)vl_osc_core_destroy(storage);}
};
static_assert(std::is_standard_layout_v<Instance> && offsetof(Instance,header)==0);
Instance& instance(Plugin*p){return *reinterpret_cast<Instance*>(p);}
template<class T>T hostMethod(Instance&o,size_t index){if(!o.host)return nullptr;void**vtable=nullptr;std::memcpy(&vtable,o.host,8);return vtable?reinterpret_cast<T>(vtable[index]):nullptr;}
// Storage-only core never creates raw voices. It makes no host callbacks during
// CreatePlugInstance; its state controls are forwarded to the actual channel.
void storageLR(void*,float*l,float*r,float pan,float volume){*l=volume*std::sqrt((1-pan)*0.5f);*r=volume*std::sqrt((1+pan)*0.5f);}
void hostLR(void*context,float*l,float*r,float pan,float volume){auto&o=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,float*,float*,float,float)>(o,31))f(o.host,l,r,pan,volume);}
void notify(void*context,intptr_t tag,int32_t flag){auto&o=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,intptr_t,int32_t)>(o,5))f(o.host,tag,flag);}
namespace pv=veggie_loops::three_osc::prevoice;
void mirror(Instance&o){if(o.channel)vl_private_prevoice_channel_cache(o.channel,&o.cache);}
void discardEmpty(Instance&o){if(o.channel){mirror(o);vl_osc_multimode_channel_destroy(o.channel);o.channel=nullptr;}}
bool ensure(Instance&o){if(o.channel)return true;try{if(o.tables.empty()){o.tables.resize(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(o.tables.data(),o.tables.size()));for(int i=0;i<6;++i)o.tablePointers[i]=o.tables.data()+i*16384;}
 std::array<uint8_t,456>payload{};if(!vl_osc_core_save_payload(o.storage,payload.data(),payload.size()))return false;
 auto*next=vl_private_prevoice_import(hostLR,notify,&o,o.tablePointers.data(),payload.data(),&o.cache);if(!next)return false;
 vl_osc_multimode_channel_max_poly(next,o.max_poly);o.channel=next;mirror(o);return true;
 }catch(const std::bad_alloc&){return false;}}
bool activeRate(Instance&o,int32_t rate){if(rate<8000||rate>384000)return false;
 if(o.channel&&vl_osc_multimode_channel_voice_count(o.channel)){if(!vl_private_live_rate(o.channel,rate))return false;mirror(o);return true;}
 discardEmpty(o);if(!vl_osc_core_set_sample_rate(o.storage,rate))return false;return o.cache.deliveredRate(rate,vl_private_prevoice_core_scaler(o.storage));}
bool activePPQ(Instance&o,uint32_t ppq){if(ppq<4||ppq>(1u<<20))return false;
 if(o.channel&&vl_osc_multimode_channel_voice_count(o.channel)){if(!vl_private_live_PPQ(o.channel,ppq))return false;mirror(o);return true;}
 discardEmpty(o);return o.cache.deliveredPPQ(ppq);}
bool activeTempo(Instance&o,double tempo){if(!pv::tempoValid(tempo))return false;
 if(o.channel&&vl_osc_multimode_channel_voice_count(o.channel)){if(!vl_private_live_tempo(o.channel,tempo))return false;mirror(o);return true;}
 discardEmpty(o);return o.cache.deliveredTempo(tempo);}
int32_t normalized(int32_t value,int32_t minimum,int32_t maximum){
 const uint64_t numerator=uint64_t(uint32_t(value))*uint64_t(uint32_t(maximum-minimum));const uint64_t q=numerator>>30,r=numerator&((1ull<<30)-1);return int32_t(q+((r>(1ull<<29))||(r==(1ull<<29)&&(q&1))))+minimum;
}
bool validSetter(Instance&o,int32_t index,int32_t value,uint32_t flags){
 if(index<0||index>=114)return false;if((flags&32)&&(value<0||value>1073741824))return false;
 if(!(flags&1))return true;
 if(index>=23&&index<108){
  const size_t group=size_t(index-23)/17,column=size_t(index-23)%17;
  if((flags&32)&&column!=0){constexpr std::array<int32_t,17> low{0,0,100,100,100,100,0,100,-128,100,100,-128,200,0,-128,-128,-128},high{255,1,65536,65536,65536,65536,128,65536,128,65536,65536,128,65536,2,128,128,128};int32_t lo=low[column],hi=high[column];if(column==8||column==11){hi=std::array<int32_t,5>{64,128,128,128,2400}[group];lo=-hi;}value=normalized(value,lo,hi);}
  std::array<uint8_t,456>payload{};if(!vl_osc_core_save_payload(o.storage,payload.data(),payload.size()))return false;std::array<int32_t,17>raw{};std::memcpy(raw.data(),payload.data()+92+group*68,68);raw[column]=value;return pv::rawValid(raw,group);
 }
 if(index==110||index==111||index==113){const int32_t high=index==113?7:256;if(flags&32)value=normalized(value,0,high);return value>=0&&value<=high;}
 return true;
}
bool finiteMagnitude(float value,float bound){const uint32_t bits=std::bit_cast<uint32_t>(value)&0x7fffffffu;return bits<=std::bit_cast<uint32_t>(bound);}
bool noteValid(const vl_osc_multimode_channel_parameters*p){if(!p)return false;
 for(const auto&x:{p->initial,p->final})if(!finiteMagnitude(x.pan,1)||!finiteMagnitude(x.volume,1)||((std::bit_cast<uint32_t>(x.volume)>>31)&&(std::bit_cast<uint32_t>(x.volume)&0x7fffffffu))||!finiteMagnitude(x.pitch,2400)||!finiteMagnitude(x.mod_x,.25f)||!finiteMagnitude(x.mod_y,.25f))return false;return true;
}
// Complete destruction ends every owned resource/member lifetime but retains
// the original allocation. After success the caller may only raw-deallocate;
// a second plugin callback/destructor is invalid. Host/notes are borrowed.
bool finishLifetime(Plugin*p){if(!p)return false;instance(p).~Instance();return true;}
void completeDestructor(Plugin*p){(void)finishLifetime(p);}
void destroy(Plugin*p){if(finishLifetime(p))::operator delete(static_cast<void*>(p));}
void deletingDestructor(Plugin*p){destroy(p);}
intptr_t dispatch(Plugin*p,intptr_t id,intptr_t,intptr_t value){auto&o=instance(p);if(id==4&&value>=8000&&value<=384000)activeRate(o,int32_t(value));if(id==14&&value){uint32_t ppq;std::memcpy(&ppq,reinterpret_cast<const char*>(value)+8,4);activePPQ(o,ppq);}if(id==13&&o.channel){std::array<double,2>time{};if(auto f=hostMethod<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t,intptr_t)>(o,0)){f(o.host,o.header.tag,36,4,reinterpret_cast<intptr_t>(time.data()));vl_osc_multimode_channel_song_position(o.channel,time[0]);}}return 0;}
void idle(Plugin*){}
void state(Plugin*p,void*stream,int32_t save){auto&o=instance(p);if(!stream)return;void**functions=nullptr;std::memcpy(&functions,stream,8);if(!functions)return;std::array<uint8_t,456>payload{};uint32_t version=14,count=0;
 if(save){auto f=reinterpret_cast<int32_t(*)(void*,const void*,uint32_t,uint32_t*)>(functions[4]);if(!f||!vl_osc_core_save_payload(o.storage,payload.data(),payload.size()))return;if(f(stream,&version,4,&count)!=0||count!=4)return;count=0;f(stream,payload.data(),456,&count);}
 else{auto f=reinterpret_cast<int32_t(*)(void*,void*,uint32_t,uint32_t*)>(functions[3]);if(!f||f(stream,&version,4,&count)!=0||count!=4||version!=14)return;count=0;if(f(stream,payload.data(),456,&count)!=0||count!=456)return;if(!pv::payloadValid(payload.data(),456))return;if(o.channel){if(!vl_osc_multimode_channel_restore(o.channel,payload.data(),456))return;mirror(o);}else if(!o.cache.restore(payload.data(),456))return;vl_osc_core_restore_payload(o.storage,payload.data(),456);}}
void name(Plugin*,int32_t,int32_t index,int32_t,char*out){if(out)std::snprintf(out,256,"VL control %d",index);}
int32_t event(Plugin*p,int32_t id,int32_t value,int32_t){auto&o=instance(p);if(id==0){const uint32_t bits=std::bit_cast<uint32_t>(value);if(bits>0&&bits<=std::bit_cast<uint32_t>(1000.f))activeTempo(o,std::bit_cast<float>(bits));}if(id==1){o.max_poly=value;if(o.channel)vl_osc_multimode_channel_max_poly(o.channel,value);}return 0;}
int32_t parameter(Plugin*p,int32_t index,int32_t value,int32_t flags){auto&o=instance(p);if(!validSetter(o,index,value,uint32_t(flags)))return 0;const auto result=vl_osc_core_parameter(o.storage,index,value,uint32_t(flags));
 if(o.channel){vl_osc_multimode_channel_parameter(o.channel,index,value,uint32_t(flags));mirror(o);}else if(index>=23&&index<108&&(flags&1)){std::array<uint8_t,456>payload{};vl_osc_core_save_payload(o.storage,payload.data(),payload.size());o.cache.groupPayload(payload.data(),size_t(index-23)/17);}return result;}
void effect(Plugin*,const float*,float*,int32_t){}
void generator(Plugin*p,float*buffer,int32_t&length){auto&o=instance(p);if(o.channel&&length>0&&length<=4096)vl_osc_multimode_channel_render(o.channel,buffer,uint32_t(length));}
intptr_t trigger(Plugin*p,void*params,intptr_t tag){auto&o=instance(p);if(!noteValid(static_cast<vl_osc_multimode_channel_parameters*>(params))||pv::overlap(params,sizeof(vl_osc_multimode_channel_parameters),&o,sizeof o)||!ensure(o))return -1;auto*voice=vl_osc_multimode_channel_trigger(o.channel,static_cast<vl_osc_multimode_channel_parameters*>(params),tag);return voice?reinterpret_cast<intptr_t>(voice):-1;}
void release(Plugin*p,intptr_t handle){auto&o=instance(p);if(o.channel)vl_osc_multimode_channel_release(o.channel,reinterpret_cast<vl_osc_multimode_channel_voice*>(handle));}
void kill(Plugin*p,intptr_t handle){auto&o=instance(p);if(o.channel)vl_osc_multimode_channel_kill(o.channel,reinterpret_cast<vl_osc_multimode_channel_voice*>(handle));}
int32_t voiceEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}
int32_t rawRender(Plugin*,intptr_t,float*,int32_t&){return 0;}
void tick(Plugin*p){auto&o=instance(p);if(o.channel)vl_osc_multimode_channel_new_tick(o.channel);}
void midiTick(Plugin*){}void midi(Plugin*,int32_t&){}void message(Plugin*,intptr_t){}
int32_t outputEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}void outputKill(Plugin*,intptr_t){}
const Functions functions{destroy,dispatch,idle,state,name,event,parameter,effect,generator,trigger,release,kill,voiceEvent,rawRender,tick,midiTick,midi,message,outputEvent,outputKill,completeDestructor,deletingDestructor};
}
extern "C" Plugin* CreatePlugInstance(void*host,intptr_t tag){if(!host)return nullptr;try{auto result=std::make_unique<Instance>();result->header={&functions,tag,&metadata(),0,0,{}};result->host=host;result->storage=vl_osc_core_create(storageLR,nullptr);if(!result->storage)return nullptr;result->cache.initialize();return &result.release()->header;}catch(const std::bad_alloc&){return nullptr;}}
extern "C" int vl_private_osc_prepare(Plugin*p,int32_t rate,double tempo,uint32_t ppq){if(!p||!pv::contextValid(rate,tempo,ppq))return 0;auto&o=instance(p);if(o.channel&&vl_osc_multimode_channel_voice_count(o.channel))return 0;return activeRate(o,rate)&&activePPQ(o,ppq)&&activeTempo(o,tempo)&&ensure(o);}
extern "C" vl_osc_multimode_channel* vl_private_osc_channel(Plugin*p){return p?instance(p).channel:nullptr;}

extern "C" int vl_private_prevoice_cache_snapshot(Plugin*p,void*out,size_t length){
 if(!p||!out||length!=sizeof(pv::Snapshot))return 0;auto&o=instance(p);if(pv::overlap(out,length,&o,sizeof o))return 0;
 mirror(o);pv::Snapshot value;std::memset(&value,0,sizeof value);value.groups=o.cache.groups;for(size_t i=0;i<5;++i)value.valid[i]=o.cache.valid[i];value.preparedTempo=o.cache.preparedTempo;value.preparedPPQ=o.cache.preparedPPQ;value.tempo=o.cache.tempo;value.ppq=o.cache.ppq;value.rate=o.cache.rate;value.synchronized=o.cache.synchronized;value.channelAvailable=o.channel!=nullptr;value.voiceCount=uint32_t(vl_osc_multimode_channel_voice_count(o.channel));std::memcpy(out,&value,sizeof value);return 1;
}

extern "C" int vl_private_prevoice_phase(Plugin*p,float pitch,uint32_t*out){
 if(!p||!out||!finiteMagnitude(pitch,2400))return 0;auto&o=instance(p);if(pv::overlap(out,4,&o,sizeof o))return 0;
 *out=phaseIncrement(*o.storage,pitch);return 1;
}

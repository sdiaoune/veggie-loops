#include "three_osc_native_factory.h"
#include "three_osc_legacy_tables.hpp"
#include <array>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <memory>
#include <vector>
#include <type_traits>
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
 int32_t rate=44100,max_poly=0;double tempo=120;uint32_t ppq=240;
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
bool ensure(Instance&o){if(o.channel)return true;try{if(o.tables.empty()){o.tables.resize(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(o.tables.data(),o.tables.size()));for(int i=0;i<6;++i)o.tablePointers[i]=o.tables.data()+i*16384;}
 auto*next=vl_osc_multimode_channel_create(hostLR,notify,&o,o.rate,o.tempo,o.ppq,o.tablePointers.data());if(!next)return false;
 std::array<uint8_t,456>payload{};if(!vl_osc_core_save_payload(o.storage,payload.data(),payload.size())||!vl_osc_multimode_channel_restore(next,payload.data(),payload.size())){vl_osc_multimode_channel_destroy(next);return false;}vl_osc_multimode_channel_max_poly(next,o.max_poly);o.channel=next;return true;
 }catch(const std::bad_alloc&){return false;}}
bool context(Instance&o,int32_t rate,double tempo,uint32_t ppq){if(rate<8000||rate>384000||!std::isfinite(tempo)||tempo<=0||tempo>1000||ppq<4||ppq>(1u<<20)||(o.channel&&vl_osc_multimode_channel_voice_count(o.channel)))return false;if(o.channel){vl_osc_multimode_channel_destroy(o.channel);o.channel=nullptr;}o.rate=rate;o.tempo=tempo;o.ppq=ppq;return true;}
void destroy(Plugin*p){if(p)delete &instance(p);}
intptr_t dispatch(Plugin*p,intptr_t id,intptr_t,intptr_t value){auto&o=instance(p);if(id==4&&value>=8000&&value<=384000)context(o,int32_t(value),o.tempo,o.ppq);if(id==14&&value){uint32_t ppq;std::memcpy(&ppq,reinterpret_cast<const char*>(value)+8,4);context(o,o.rate,o.tempo,ppq);}if(id==13&&o.channel){std::array<double,2>time{};if(auto f=hostMethod<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t,intptr_t)>(o,0)){f(o.host,o.header.tag,36,4,reinterpret_cast<intptr_t>(time.data()));vl_osc_multimode_channel_song_position(o.channel,time[0]);}}return 0;}
void idle(Plugin*){}
void state(Plugin*p,void*stream,int32_t save){auto&o=instance(p);if(!stream)return;void**functions=nullptr;std::memcpy(&functions,stream,8);if(!functions)return;std::array<uint8_t,456>payload{};uint32_t version=14,count=0;
 if(save){auto f=reinterpret_cast<int32_t(*)(void*,const void*,uint32_t,uint32_t*)>(functions[4]);if(!f||!vl_osc_core_save_payload(o.storage,payload.data(),payload.size()))return;if(f(stream,&version,4,&count)!=0||count!=4)return;count=0;f(stream,payload.data(),456,&count);}
 else{auto f=reinterpret_cast<int32_t(*)(void*,void*,uint32_t,uint32_t*)>(functions[3]);if(!f||f(stream,&version,4,&count)!=0||count!=4||version!=14)return;count=0;if(f(stream,payload.data(),456,&count)!=0||count!=456)return;if(o.channel&&!vl_osc_multimode_channel_restore(o.channel,payload.data(),456))return;vl_osc_core_restore_payload(o.storage,payload.data(),456);}}
void name(Plugin*,int32_t,int32_t index,int32_t,char*out){if(out)std::snprintf(out,256,"VL control %d",index);}
int32_t event(Plugin*p,int32_t id,int32_t value,int32_t){auto&o=instance(p);if(id==0){float tempo;std::memcpy(&tempo,&value,4);context(o,o.rate,tempo,o.ppq);}if(id==1){o.max_poly=value;if(o.channel)vl_osc_multimode_channel_max_poly(o.channel,value);}return 0;}
int32_t parameter(Plugin*p,int32_t index,int32_t value,int32_t flags){auto&o=instance(p);const auto result=vl_osc_core_parameter(o.storage,index,value,uint32_t(flags));if(o.channel)vl_osc_multimode_channel_parameter(o.channel,index,value,uint32_t(flags));return result;}
void effect(Plugin*,const float*,float*,int32_t){}
void generator(Plugin*p,float*buffer,int32_t&length){auto&o=instance(p);if(o.channel&&length>0&&length<=4096)vl_osc_multimode_channel_render(o.channel,buffer,uint32_t(length));}
intptr_t trigger(Plugin*p,void*params,intptr_t tag){auto&o=instance(p);if(!ensure(o))return -1;auto*voice=vl_osc_multimode_channel_trigger(o.channel,static_cast<vl_osc_multimode_channel_parameters*>(params),tag);return voice?reinterpret_cast<intptr_t>(voice):-1;}
void release(Plugin*p,intptr_t handle){auto&o=instance(p);if(o.channel)vl_osc_multimode_channel_release(o.channel,reinterpret_cast<vl_osc_multimode_channel_voice*>(handle));}
void kill(Plugin*p,intptr_t handle){auto&o=instance(p);if(o.channel)vl_osc_multimode_channel_kill(o.channel,reinterpret_cast<vl_osc_multimode_channel_voice*>(handle));}
int32_t voiceEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}
int32_t rawRender(Plugin*,intptr_t,float*,int32_t&){return 0;}
void tick(Plugin*p){auto&o=instance(p);if(o.channel)vl_osc_multimode_channel_new_tick(o.channel);}
void midiTick(Plugin*){}void midi(Plugin*,int32_t&){}void message(Plugin*,intptr_t){}
int32_t outputEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}void outputKill(Plugin*,intptr_t){}
const Functions functions{destroy,dispatch,idle,state,name,event,parameter,effect,generator,trigger,release,kill,voiceEvent,rawRender,tick,midiTick,midi,message,outputEvent,outputKill,destroy,destroy};
}
extern "C" Plugin* CreatePlugInstance(void*host,intptr_t tag){if(!host)return nullptr;try{auto result=std::make_unique<Instance>();result->header={&functions,tag,&metadata(),0,0,{}};result->host=host;result->storage=vl_osc_core_create(storageLR,nullptr);if(!result->storage)return nullptr;return &result.release()->header;}catch(const std::bad_alloc&){return nullptr;}}
extern "C" int vl_private_osc_prepare(Plugin*p,int32_t rate,double tempo,uint32_t ppq){return p&&context(instance(p),rate,tempo,ppq)&&ensure(instance(p));}
extern "C" vl_osc_multimode_channel* vl_private_osc_channel(Plugin*p){return p?instance(p).channel:nullptr;}

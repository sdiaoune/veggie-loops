#include "mute2_native_abi.h"
#include "mute2_plugin.h"
#include <array>
#include <cstring>
#include <mutex>
#include <new>

namespace {
using namespace veggie_loops::mute2::native;
struct Instance{Plugin header{};VLMute2Plugin* numerical=vl_mute2_create();};
static_assert(offsetof(Instance,header)==0);
Instance& object(Plugin* plugin){return *reinterpret_cast<Instance*>(plugin);}
const Info& commonInfo(){
  static Info info{};static std::once_flag initialize;
  std::call_once(initialize,[]{info.version=1;info.longName="VL Mute 2";info.shortName="VL Mute 2";info.flags=1<<21;info.parameterCount=2;});return info;
}
void destroy(Plugin* plugin){if(plugin){vl_mute2_destroy(object(plugin).numerical);delete &object(plugin);}}
intptr_t dispatch(Plugin*,intptr_t,intptr_t,intptr_t){return 0;}
void idle(Plugin*){}
void state(Plugin* plugin,Stream* stream,int32_t save){
  if(!stream || !stream->functions)return;
  std::array<uint8_t,12> bytes{};uint64_t count=0;
  using Transfer=intptr_t(*)(Stream*,void*,uint64_t,uint64_t*);
  if(save){
    if(!vl_mute2_save_state(object(plugin).numerical,bytes.data(),bytes.size()))return;
    const auto write=reinterpret_cast<Transfer>(stream->functions[4]);if(!write)return;
    if(write(stream,bytes.data(),4,&count)>=0 && count==4)write(stream,bytes.data()+4,8,&count);
  }else{
    const auto read=reinterpret_cast<Transfer>(stream->functions[3]);if(!read)return;
    if(read(stream,bytes.data(),4,&count)<0 || count!=4)return;
    if(read(stream,bytes.data()+4,8,&count)>=0 && count==8)vl_mute2_restore_state(object(plugin).numerical,bytes.data(),bytes.size());
  }
}
void name(Plugin*,int32_t section,int32_t index,int32_t,char* output){
  if(output)std::strcpy(output,section==0 && index==0?"Audio":section==0 && index==1?"Channels":"");
}
int32_t event(Plugin*,int32_t,int32_t,int32_t){return 0;}
int32_t parameter(Plugin* plugin,int32_t index,int32_t value,int32_t flags){
  int32_t result=0;vl_mute2_parameter(object(plugin).numerical,index,value,static_cast<uint32_t>(flags)&35u,&result);return result;
}
void effect(Plugin* plugin,const float* input,float* output,int32_t frames){vl_mute2_render(object(plugin).numerical,input,output,frames);}
void generator(Plugin*,float*,int32_t& length){length=0;}
intptr_t voice(Plugin*,void*,intptr_t){return -1;}
void voiceEnd(Plugin*,intptr_t){}
int32_t voiceEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}
int32_t voiceRender(Plugin*,intptr_t,float*,int32_t& length){length=0;return 0;}
void midi(Plugin*,int32_t&){}
void message(Plugin*,intptr_t){}
const Functions functions{destroy,dispatch,idle,state,name,event,parameter,effect,generator,voice,voiceEnd,voiceEnd,voiceEvent,voiceRender,idle,idle,midi,message,voiceEvent,voiceEnd,destroy,destroy};
}
extern "C" veggie_loops::balance::native::Plugin* CreatePlugInstance(void*,intptr_t hostTag){
  auto* instance=new(std::nothrow) Instance;if(!instance)return nullptr;
  if(!instance->numerical){delete instance;return nullptr;}
  instance->header.functions=&functions;instance->header.hostTag=hostTag;instance->header.info=&commonInfo();return &instance->header;
}

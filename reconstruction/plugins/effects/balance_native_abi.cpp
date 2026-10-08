#include "balance_native_abi.h"
#include "balance_plugin.h"
#include <algorithm>
#include <array>
#include <cstring>
#include <new>

namespace veggie_loops::balance::native {
namespace {
struct Instance {
  Plugin header{};
  Info information{};
  VLBalancePlugin* numerical=vl_balance_create();
};
static_assert(offsetof(Instance,header)==0);
Instance& instance(Plugin* p){return *reinterpret_cast<Instance*>(p);}
void destroy(Plugin* p){if(p){vl_balance_destroy(instance(p).numerical);delete &instance(p);}}
std::intptr_t dispatch(Plugin* p,std::intptr_t id,std::intptr_t,std::intptr_t value){
  if(id==2)vl_balance_resume(instance(p).numerical);
  if(id==4 && value>=8000 && value<=192000)
    vl_balance_set_sample_rate(instance(p).numerical,static_cast<std::int32_t>(value));
  return 0;
}
void idle(Plugin*){}
void state(Plugin* p,Stream* stream,std::int32_t save){
  if(!stream || !stream->functions)return;
  std::array<std::uint8_t,8> bytes{};std::uint64_t count=0;
  using Transfer=std::intptr_t(*)(Stream*,void*,std::uint64_t,std::uint64_t*);
  if(save){
    if(vl_balance_save_state(instance(p).numerical,bytes.data(),bytes.size()))
      reinterpret_cast<Transfer>(stream->functions[4])(stream,bytes.data(),8,&count);
  }else{
    const auto status=reinterpret_cast<Transfer>(stream->functions[3])(stream,bytes.data(),8,&count);
    if(status>=0 && count==8)vl_balance_restore_state(instance(p).numerical,bytes.data(),bytes.size());
  }
}
void name(Plugin*,std::int32_t section,std::int32_t index,std::int32_t,char* output){
  if(!output)return;
  const char* text=section==0 && index==0?"Pan":section==0 && index==1?"Volume":"";
  std::strcpy(output,text);
}
std::int32_t event(Plugin*,std::int32_t,std::int32_t,std::int32_t){return 0;}
std::int32_t parameter(Plugin* p,std::int32_t index,std::int32_t value,std::int32_t flags){
  std::int32_t result=0;
  // Numerical set/get/normalized bits. Native hint/editor flags have no UI yet.
  vl_balance_parameter(instance(p).numerical,index,value,static_cast<std::uint32_t>(flags)&35u,&result);
  return result;
}
void effect(Plugin* p,const float* input,float* output,std::int32_t frames){
  vl_balance_render(instance(p).numerical,input,output,frames);
}
void generator(Plugin*,float*,std::int32_t& length){length=0;}
std::intptr_t voice(Plugin*,void*,std::intptr_t){return -1;}
void voiceEnd(Plugin*,std::intptr_t){}
std::int32_t voiceEvent(Plugin*,std::intptr_t,std::intptr_t,std::intptr_t,std::intptr_t){return 0;}
std::int32_t voiceRender(Plugin*,std::intptr_t,float*,std::int32_t& length){length=0;return 0;}
void midi(Plugin*,std::int32_t&){}
void message(Plugin*,std::intptr_t){}
const Functions functions={destroy,dispatch,idle,state,name,event,parameter,effect,generator,
  voice,voiceEnd,voiceEnd,voiceEvent,voiceRender,idle,idle,midi,message,voiceEvent,voiceEnd,
  destroy,destroy};
}
}
extern "C" veggie_loops::balance::native::Plugin*
CreatePlugInstance(void*,std::intptr_t hostTag){
  using namespace veggie_loops::balance::native;
  auto* object=new(std::nothrow) Instance;
  if(!object)return nullptr;
  if(!object->numerical){delete object;return nullptr;}
  // Runtime stores avoid an unaligned chained-fixup relocation in packed Info.
  object->information.version=1;
  object->information.longName="VL Balance";object->information.shortName="VL Balance";
  object->information.flags=1<<21;object->information.parameterCount=2;
  object->header.functions=&functions;object->header.hostTag=hostTag;
  object->header.info=&object->information;
  return &object->header;
}

#include "balance_native_abi.h"
#include "balance_plugin.h"
#if defined(VL_BALANCE_APPKIT_EDITOR)
#include "balance_editor.h"
#endif
#include <algorithm>
#include <array>
#include <cstring>
#include <new>
#include <mutex>

namespace veggie_loops::balance::native {
namespace {
struct Instance {
  Plugin header{};
  VLBalancePlugin* numerical=vl_balance_create();
#if defined(VL_BALANCE_APPKIT_EDITOR)
  void* host=nullptr;
  void* editor=nullptr;
  bool resizePending=false;
#endif
};
static_assert(offsetof(Instance,header)==0);
Instance& instance(Plugin* p){return *reinterpret_cast<Instance*>(p);}
const Info& commonInfo(){
  static Info information{};static std::once_flag initialize;
  std::call_once(initialize,[]{
    // Runtime stores avoid packed-pointer chained-fixup relocations. Shared
    // metadata remains valid for every instance until the dylib is unloaded.
    information.version=1;information.longName="VL Balance";information.shortName="VL Balance";
    information.flags=1<<21;information.parameterCount=2;
#if defined(VL_BALANCE_APPKIT_EDITOR)
    information.flags|=1<<27;
#endif
  });return information;
}
#if defined(VL_BALANCE_APPKIT_EDITOR)
template<class T>T hostMethod(Instance& object,std::size_t slot){
  if(!object.host)return nullptr;
  auto** table=*static_cast<void***>(object.host);return table?reinterpret_cast<T>(table[slot]):nullptr;
}
void hostLock(void* context){auto& o=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,std::intptr_t)>(o,32))f(o.host,o.header.hostTag);}
void hostUnlock(void* context){auto& o=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,std::intptr_t)>(o,33))f(o.host,o.header.hostTag);}
void hostChanged(void* context,std::int32_t index,std::int32_t value){auto& o=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,std::intptr_t,std::int32_t,std::int32_t)>(o,1))f(o.host,o.header.hostTag,index,value);}
void hostHint(void* context,const char* text){auto& o=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,std::intptr_t,const char*)>(o,2))f(o.host,o.header.hostTag,text);}
#endif
void destroy(Plugin* p){if(p){
#if defined(VL_BALANCE_APPKIT_EDITOR)
  if(!vl_balance_editor_main_thread())return;
  if(!vl_balance_editor_destroy(instance(p).editor))return;
#endif
  vl_balance_destroy(instance(p).numerical);delete &instance(p);
}}
std::intptr_t dispatch(Plugin* p,std::intptr_t id,std::intptr_t,std::intptr_t value){
#if defined(VL_BALANCE_APPKIT_EDITOR)
  if(id==0){if(!vl_balance_editor_main_thread())return 0;auto& object=instance(p);
    if(value && !object.editor){const VLBalanceEditorHost callbacks{&object,hostLock,hostUnlock,hostChanged,hostHint};
      object.editor=vl_balance_editor_create(object.numerical,&callbacks);}
    vl_balance_editor_attach(object.editor,reinterpret_cast<void*>(value));
    object.header.editor=value?reinterpret_cast<std::intptr_t>(object.editor):0;
    object.resizePending=value && object.editor;
  }
#endif
  if(id==2)vl_balance_resume(instance(p).numerical);
  if(id==4 && value>=8000 && value<=192000)
    vl_balance_set_sample_rate(instance(p).numerical,static_cast<std::int32_t>(value));
  return 0;
}
void idle(Plugin* p){
#if defined(VL_BALANCE_APPKIT_EDITOR)
  if(!vl_balance_editor_main_thread())return;
  auto& object=instance(p);vl_balance_editor_refresh(object.editor);
  if(object.resizePending){object.resizePending=false;
    if(auto f=hostMethod<std::intptr_t(*)(void*,std::intptr_t,std::intptr_t,std::intptr_t,std::intptr_t)>(object,0))
      f(object.host,object.header.hostTag,2,0,0);
  }
#else
  (void)p;
#endif
}
void tick(Plugin*){} // effect tick/MIDI tick callbacks never access GUI state
void state(Plugin* p,Stream* stream,std::int32_t save){
  if(!stream || !stream->functions)return;
  std::array<std::uint8_t,8> bytes{};std::uint64_t count=0;
  // The actual engine IStream provider returns HRESULT in W0 and stores a
  // 32-bit completed count. Wide zeroed storage also accepts fixture providers
  // that write 64-bit counts without overwriting adjacent state bytes.
  using Transfer=std::int32_t(*)(Stream*,void*,std::uint32_t,void*);
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
  vl_balance_parameter(instance(p).numerical,index,value,static_cast<std::uint32_t>(flags)&35u,&result);
#if defined(VL_BALANCE_APPKIT_EDITOR)
  if((flags&4) && vl_balance_editor_main_thread())vl_balance_editor_hint(instance(p).editor,index,result);
#endif
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
  voice,voiceEnd,voiceEnd,voiceEvent,voiceRender,tick,tick,midi,message,voiceEvent,voiceEnd,
  destroy,destroy};
}
}
extern "C" veggie_loops::balance::native::Plugin*
CreatePlugInstance(void* host,std::intptr_t hostTag){
  using namespace veggie_loops::balance::native;
  auto* object=new(std::nothrow) Instance;
  if(!object)return nullptr;
  if(!object->numerical){delete object;return nullptr;}
#if defined(VL_BALANCE_APPKIT_EDITOR)
  object->host=host;
#else
  (void)host;
#endif
  object->header.functions=&functions;object->header.hostTag=hostTag;
  object->header.info=&commonInfo();
  return &object->header;
}

#include "phase_inverter_native_abi.h"
#include "phase_inverter_plugin.h"
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
#include "phase_inverter_editor.h"
#endif
#include <array>
#include <cstring>
#include <mutex>
#include <new>

namespace {
using namespace veggie_loops::phase_inverter::native;
struct Instance{Plugin header{};VLPhaseInverterPlugin* numerical=vl_phase_inverter_create();
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
  void* host=nullptr;void* editor=nullptr;bool resizePending=false;
#endif
};
static_assert(offsetof(Instance,header)==0);
Instance& object(Plugin* plugin){return *reinterpret_cast<Instance*>(plugin);}
const Info& commonInfo(){
  static Info info{};static std::once_flag initialize;
  std::call_once(initialize,[]{info.version=1;info.longName="VL Phase Inverter";info.shortName="VL Phase";info.flags=1<<21;info.parameterCount=1;
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
    info.flags|=1<<27;
#endif
  });return info;
}
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
template<class T>T hostMethod(Instance& instance,size_t slot){
  if(!instance.host)return nullptr;auto** table=*static_cast<void***>(instance.host);return table?reinterpret_cast<T>(table[slot]):nullptr;
}
void hostLock(void* context){auto& instance=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,intptr_t)>(instance,32))f(instance.host,instance.header.hostTag);}
void hostUnlock(void* context){auto& instance=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,intptr_t)>(instance,33))f(instance.host,instance.header.hostTag);}
void hostChanged(void* context,int32_t index,int32_t value){auto& instance=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,intptr_t,int32_t,int32_t)>(instance,1))f(instance.host,instance.header.hostTag,index,value);}
void hostHint(void* context,const char* text){auto& instance=*static_cast<Instance*>(context);if(auto f=hostMethod<void(*)(void*,intptr_t,const char*)>(instance,2))f(instance.host,instance.header.hostTag,text);}
#endif
bool finishLifetime(Plugin* plugin){
  if(!plugin)return false;
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
  if(!vl_phase_inverter_editor_main_thread())return false;
  if(!vl_phase_inverter_editor_destroy(object(plugin).editor))return false;
#endif
  auto* instance=&object(plugin);
  vl_phase_inverter_destroy(instance->numerical);
  instance->numerical=nullptr;
  instance->~Instance();
  return true;
}
void completeDestructor(Plugin* plugin){(void)finishLifetime(plugin);}
void destroy(Plugin* plugin){if(finishLifetime(plugin))::operator delete(static_cast<void*>(plugin));}
void deletingDestructor(Plugin* plugin){destroy(plugin);}
intptr_t dispatch(Plugin* plugin,intptr_t id,intptr_t,intptr_t value){
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
  if(id==0){if(!vl_phase_inverter_editor_main_thread())return 0;auto& instance=object(plugin);
    if(value && !instance.editor){const VLPhaseInverterEditorHost callbacks{&instance,hostLock,hostUnlock,hostChanged,hostHint};instance.editor=vl_phase_inverter_editor_create(instance.numerical,&callbacks);}
    vl_phase_inverter_editor_attach(instance.editor,reinterpret_cast<void*>(value));
    instance.header.editor=value && instance.editor?reinterpret_cast<intptr_t>(instance.editor):0;
    instance.resizePending=value && instance.editor;
  }
#else
  (void)plugin;(void)id;(void)value;
#endif
  return 0;
}
void idle(Plugin* plugin){
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
  if(!vl_phase_inverter_editor_main_thread())return;
  auto& instance=object(plugin);vl_phase_inverter_editor_refresh(instance.editor);
  if(instance.resizePending){instance.resizePending=false;
    if(auto f=hostMethod<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t,intptr_t)>(instance,0))f(instance.host,instance.header.hostTag,2,0,0);
  }
#else
  (void)plugin;
#endif
}
void tick(Plugin*){}
void state(Plugin* plugin,Stream* stream,int32_t save){
  if(!stream || !stream->functions)return;
  std::array<uint8_t,8> bytes{};uint64_t count=0;
  // Actual engine IStream uses HRESULT32 and length32. Wide zeroed completed-
  // count storage safely accepts its 32-bit store and synthetic 64-bit fixtures.
  using Transfer=int32_t(*)(Stream*,void*,uint32_t,void*);
  if(save){
    if(!vl_phase_inverter_save_state(object(plugin).numerical,bytes.data(),bytes.size()))return;
    const auto write=reinterpret_cast<Transfer>(stream->functions[4]);if(!write)return;
    if(write(stream,bytes.data(),4,&count)>=0 && count==4){count=0;write(stream,bytes.data()+4,4,&count);}
  }else{
    const auto read=reinterpret_cast<Transfer>(stream->functions[3]);if(!read)return;
    if(read(stream,bytes.data(),4,&count)<0 || count!=4)return;
    count=0;
    if(read(stream,bytes.data()+4,4,&count)>=0 && count==4)vl_phase_inverter_restore_state(object(plugin).numerical,bytes.data(),bytes.size());
  }
}
void name(Plugin*,int32_t section,int32_t index,int32_t,char* output){
  if(output)std::strcpy(output,section==0 && index==0?"Inversion":"");
}
int32_t event(Plugin*,int32_t,int32_t,int32_t){return 0;}
int32_t parameter(Plugin* plugin,int32_t index,int32_t value,int32_t flags){
  int32_t result=0;vl_phase_inverter_parameter(object(plugin).numerical,index,value,static_cast<uint32_t>(flags)&35u,&result);
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
  if((flags&4) && vl_phase_inverter_editor_main_thread())vl_phase_inverter_editor_hint(object(plugin).editor,index,result);
#endif
  return result;
}
void effect(Plugin* plugin,const float* input,float* output,int32_t frames){vl_phase_inverter_render(object(plugin).numerical,input,output,frames);}
void generator(Plugin*,float*,int32_t& length){length=0;}
intptr_t voice(Plugin*,void*,intptr_t){return -1;}
void voiceEnd(Plugin*,intptr_t){}
int32_t voiceEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}
int32_t voiceRender(Plugin*,intptr_t,float*,int32_t& length){length=0;return 0;}
void midi(Plugin*,int32_t&){}
void message(Plugin*,intptr_t){}
const Functions functions{destroy,dispatch,idle,state,name,event,parameter,effect,generator,voice,voiceEnd,voiceEnd,voiceEvent,voiceRender,tick,tick,midi,message,voiceEvent,voiceEnd,completeDestructor,deletingDestructor};
}
extern "C" veggie_loops::balance::native::Plugin* CreatePlugInstance(void* host,intptr_t hostTag){
  auto* instance=new(std::nothrow) Instance;if(!instance)return nullptr;
  if(!instance->numerical){delete instance;return nullptr;}
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
  instance->host=host;
#else
  (void)host;
#endif
  instance->header.functions=&functions;instance->header.hostTag=hostTag;instance->header.info=&commonInfo();return &instance->header;
}

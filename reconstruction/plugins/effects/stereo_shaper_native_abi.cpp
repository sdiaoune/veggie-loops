#include "stereo_shaper_native_abi.h"
#include "stereo_shaper_plugin.h"
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
#include "stereo_shaper_editor.h"
#endif
#include <array>
#include <cstring>
#include <mutex>
#include <new>

namespace {
using namespace veggie_loops::stereo_shaper::native;
struct Instance{Plugin header{};VLStereoShaperPlugin* numerical=vl_stereo_shaper_create();void*host=nullptr;int32_t registeredSend=0;
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
void*editor=nullptr;bool resizePending=false;
#endif
};
static_assert(offsetof(Instance,header)==0);
Instance& object(Plugin*p){return *reinterpret_cast<Instance*>(p);}
const Info& commonInfo(){static Info info{};static std::once_flag once;std::call_once(once,[]{info.version=1;info.longName="VL Stereo Shaper";info.shortName="VL Stereo";info.flags=1<<21;info.parameterCount=6;
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
info.flags|=1<<27;
#endif
});return info;}
template<class T>T hostMethod(Instance&instance,size_t slot){if(!instance.host)return nullptr;auto**vmt=*static_cast<void***>(instance.host);return vmt?reinterpret_cast<T>(vmt[slot]):nullptr;}
void notifyRouting(Instance&instance,int32_t send){
  if(send==instance.registeredSend)return;
  if(auto f=hostMethod<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t,intptr_t)>(instance,0)){
    if(instance.registeredSend>0)f(instance.host,instance.header.hostTag,73,instance.registeredSend,0);
    if(send>0)f(instance.host,instance.header.hostTag,73,send,1);
  }
  instance.registeredSend=send;
}
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
void hostLock(void*c){auto&i=*static_cast<Instance*>(c);if(auto f=hostMethod<void(*)(void*,intptr_t)>(i,32))f(i.host,i.header.hostTag);}
void hostUnlock(void*c){auto&i=*static_cast<Instance*>(c);if(auto f=hostMethod<void(*)(void*,intptr_t)>(i,33))f(i.host,i.header.hostTag);}
void hostChanged(void*c,int32_t index,int32_t value){auto&i=*static_cast<Instance*>(c);if(auto f=hostMethod<void(*)(void*,intptr_t,int32_t,int32_t)>(i,1))f(i.host,i.header.hostTag,index,value);}
void hostHint(void*c,const char*text){auto&i=*static_cast<Instance*>(c);if(auto f=hostMethod<void(*)(void*,intptr_t,const char*)>(i,2))f(i.host,i.header.hostTag,text);}
void hostRouting(void*c,int32_t send,int32_t){notifyRouting(*static_cast<Instance*>(c),send);}
#endif
bool finishLifetime(Plugin* p){
  if(!p)return false;
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
  if(!vl_stereo_shaper_editor_main_thread())return false;
  if(!vl_stereo_shaper_editor_destroy(object(p).editor))return false;
#endif
  auto* instance=&object(p);
  vl_stereo_shaper_destroy(instance->numerical);
  instance->numerical=nullptr;
  instance->~Instance();
  return true;
}
void completeDestructor(Plugin* p){(void)finishLifetime(p);}
void destroy(Plugin* p){if(finishLifetime(p))::operator delete(static_cast<void*>(p));}
void deletingDestructor(Plugin* p){destroy(p);}
intptr_t dispatch(Plugin*p,intptr_t id,intptr_t index,intptr_t value){
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
if(id==0){if(!vl_stereo_shaper_editor_main_thread())return 0;auto&i=object(p);if(value&&!i.editor){const VLStereoShaperEditorHost callbacks{&i,hostLock,hostUnlock,hostChanged,hostHint,hostRouting};i.editor=vl_stereo_shaper_editor_create(i.numerical,&callbacks);}vl_stereo_shaper_editor_attach(i.editor,reinterpret_cast<void*>(value));i.header.editor=value&&i.editor?reinterpret_cast<intptr_t>(i.editor):0;i.resizePending=value&&i.editor;}
#endif
if(id==2)vl_stereo_shaper_resume(object(p).numerical);else if(id==4)vl_stereo_shaper_sample_rate(object(p).numerical,int32_t(value));else if(id==52&&index>=0&&index<6)return index<4?1:index==4?4:3;return 0;}
void idle(Plugin*p){
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
if(!vl_stereo_shaper_editor_main_thread())return;auto&i=object(p);vl_stereo_shaper_editor_refresh(i.editor);if(i.resizePending){i.resizePending=false;if(auto f=hostMethod<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t,intptr_t)>(i,0))f(i.host,i.header.hostTag,2,0,0);}
#else
(void)p;
#endif
}
void tick(Plugin*){}
void state(Plugin*p,Stream*stream,int32_t save){
  if(!stream||!stream->functions)return;std::array<uint8_t,36>bytes{};uint64_t count=0;
  using Transfer=int32_t(*)(Stream*,void*,uint32_t,void*);
  if(save){if(!vl_stereo_shaper_save_state(object(p).numerical,bytes.data(),bytes.size()))return;const auto write=reinterpret_cast<Transfer>(stream->functions[4]);if(!write)return;if(write(stream,bytes.data(),4,&count)>=0&&count==4){count=0;write(stream,bytes.data()+4,32,&count);}}
  else {const auto read=reinterpret_cast<Transfer>(stream->functions[3]);if(!read||read(stream,bytes.data(),4,&count)<0||count!=4)return;count=0;if(read(stream,bytes.data()+4,32,&count)>=0&&count==32&&vl_stereo_shaper_restore_state(object(p).numerical,bytes.data(),bytes.size())){int32_t send=0,mode=0;vl_stereo_shaper_get_routing(object(p).numerical,&send,&mode);notifyRouting(object(p),send);}}
}
void name(Plugin*,int32_t section,int32_t index,int32_t,char*out){static constexpr std::array<const char*,6>labels{"Right to Left","Left Level","Right Level","Left to Right","Delay","Phase"};if(out)std::strcpy(out,section==0&&index>=0&&index<6?labels[size_t(index)]:"");}
int32_t event(Plugin*,int32_t,int32_t,int32_t){return 0;}
int32_t parameter(Plugin*p,int32_t index,int32_t value,int32_t flags){int32_t result=0;vl_stereo_shaper_parameter(object(p).numerical,index,value,uint32_t(flags)&35u,&result);
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
if((flags&4)&&vl_stereo_shaper_editor_main_thread())vl_stereo_shaper_editor_hint(object(p).editor,index,result);
#endif
return result;}
void effect(Plugin*p,const float*input,float*output,int32_t frames){
  auto&instance=object(p);int32_t send=0,mode=0;if(!vl_stereo_shaper_get_routing(instance.numerical,&send,&mode)||frames<0||frames>1024||!input||!output)return;
  std::array<float,2048>dry;if(send>0)std::memcpy(dry.data(),input,size_t(frames)*8);
  if(!vl_stereo_shaper_render(instance.numerical,input,output,frames,nullptr))return;
  if(send>0)if(auto getOut=hostMethod<void(*)(void*,intptr_t,intptr_t,IOBuffer*)>(instance,37)){
    IOBuffer descriptor{nullptr,0};getOut(instance.host,p->hostTag,send,&descriptor);
    if(descriptor.buffer)for(size_t i=0;i<size_t(frames)*2;++i){const float residual=dry[i]-output[i];descriptor.buffer[i]=residual+descriptor.buffer[i];}
    descriptor.flags=1;getOut(instance.host,p->hostTag,send,&descriptor);
  }
}
void generator(Plugin*,float*,int32_t&count){count=0;}
intptr_t voice(Plugin*,void*,intptr_t){return -1;}
void voiceEnd(Plugin*,intptr_t){}
int32_t voiceEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}
int32_t voiceRender(Plugin*,intptr_t,float*,int32_t&count){count=0;return 0;}
void midi(Plugin*,int32_t&){}
void message(Plugin*,intptr_t){}
const Functions functions{destroy,dispatch,idle,state,name,event,parameter,effect,generator,voice,voiceEnd,voiceEnd,voiceEvent,voiceRender,tick,tick,midi,message,voiceEvent,voiceEnd,completeDestructor,deletingDestructor};
}
extern "C" veggie_loops::balance::native::Plugin* CreatePlugInstance(void*host,intptr_t tag){auto*instance=new(std::nothrow)Instance;if(!instance)return nullptr;if(!instance->numerical){delete instance;return nullptr;}instance->host=host;instance->header.functions=&functions;instance->header.hostTag=tag;instance->header.info=&commonInfo();return &instance->header;}

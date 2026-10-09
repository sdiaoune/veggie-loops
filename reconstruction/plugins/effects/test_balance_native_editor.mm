#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound native editor test requires macOS arm64.
#endif
#include "balance_native_abi.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <thread>
#include <atomic>

namespace {
using namespace veggie_loops::balance::native;
void require(bool v,const char* m){if(!v)throw std::runtime_error(m);}
std::string sourceHash(const char* path){
  std::ifstream in(path,std::ios::binary);require(in.good(),"Cannot read engine");
  std::vector<unsigned char>b{std::istreambuf_iterator<char>(in),std::istreambuf_iterator<char>()};
  std::array<unsigned char,32>h{};CC_SHA256(b.data(),static_cast<CC_LONG>(b.size()),h.data());
  std::ostringstream s;for(auto v:h)s<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(v);return s.str();
}
template<class T>T get(void* o,std::size_t p){T v;std::memcpy(&v,static_cast<char*>(o)+p,sizeof(v));return v;}
template<class T>T method(void* o,std::size_t p){return get<T>(get<void*>(o,0),p);}
struct Host {
  void** functions;
  bool locked=false;int locks=0,unlocks=0,changes=0,hints=0,resizes=0;
  std::int32_t index=-1,value=-1;std::string hint;
  void* pluginWrapper=nullptr;
};
void hostLock(Host* h,std::intptr_t tag){require(tag==0x564c && !h->locked,"Host lock protocol failed");h->locked=true;++h->locks;}
void hostUnlock(Host* h,std::intptr_t tag){require(tag==0x564c && h->locked,"Host unlock protocol failed");h->locked=false;++h->unlocks;}
void hostChanged(Host* h,std::intptr_t tag,std::int32_t index,std::int32_t value){require(tag==0x564c && !h->locked,"Change callback occurred inside lock");h->index=index;h->value=value;++h->changes;}
void hostHint(Host* h,std::intptr_t tag,const char* text){require(tag==0x564c && !h->locked && text,"Hint callback protocol failed");h->hint=text;++h->hints;}
std::intptr_t hostDispatch(Host* h,std::intptr_t tag,std::intptr_t id,std::intptr_t,std::intptr_t){
  require(tag==0x564c && !h->locked,"Dispatch callback protocol failed");
  if(id==2){require(h->pluginWrapper && get<std::intptr_t>(h->pluginWrapper,24)!=0,"Resize preceded editor-handle bridge");++h->resizes;}return 0;
}
}
int main(int argc,char** argv){@autoreleasepool{try{
 require(argc==3,"Usage: test_balance_native_editor inspected-engine compiled-editor-plugin");
 require(sourceHash(argv[1])=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine identity changed");
 [NSApplication sharedApplication];void* engine=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(engine,"Engine load failed");
 Dl_info image{};require(dladdr(dlsym(engine,"CreateFruityInstance"),&image),"Engine image unavailable");auto* base=static_cast<char*>(image.dli_fbase);
 std::array<void*,96> hostMethods{};hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0xd0/8]=reinterpret_cast<void*>(&hostChanged);hostMethods[0xd8/8]=reinterpret_cast<void*>(&hostHint);
 hostMethods[0x1c8/8]=reinterpret_cast<void*>(&hostLock);hostMethods[0x1d0/8]=reinterpret_cast<void*>(&hostUnlock);Host host{};host.functions=hostMethods.data();
 using Constructor=void*(*)(void*,std::intptr_t,void*);
 auto hostConstructor=reinterpret_cast<Constructor>(base+0xb4cd20);void* hostWrapper=hostConstructor(base+0x1497870,1,&host);require(hostWrapper,"Actual engine host class allocation failed");
 void* library=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(library,"Editor plugin load failed");
 auto factory=reinterpret_cast<Plugin*(*)(void*,std::intptr_t)>(dlsym(library,"CreatePlugInstance"));require(factory,"Missing native factory");
 Plugin* plugin=factory(static_cast<char*>(hostWrapper)+16,0x564c);require(plugin && plugin->info->flags==((1<<21)|(1<<27)),"Editor plugin metadata failed");
 auto pluginConstructor=reinterpret_cast<Constructor>(base+0xb4c7c0);void* wrapper=pluginConstructor(base+0x1497618,1,plugin);require(wrapper,"Actual engine plugin class allocation failed");host.pluginWrapper=wrapper;
 auto dispatch=method<std::intptr_t(*)(void*,std::intptr_t,std::intptr_t,std::intptr_t)>(wrapper,0xd0);auto idle=method<void(*)(void*)>(wrapper,0xd8);
 auto parameter=method<std::int32_t(*)(void*,std::int32_t,std::int32_t,std::int32_t)>(wrapper,0xf8);
 // Optional-editor native destruction is main-thread even before first attachment.
 std::thread unattachedDestroyWorker([&]{method<void(*)(void*)>(wrapper,0xc8)(wrapper);});unattachedDestroyWorker.join();
 require(parameter(wrapper,0,0,2)==0,"Worker unattached destruction freed native state");
 auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,500,300)];
 // Worker hint/get calls overlap the editor's first creation. They must keep
 // numerical access working while skipping GUI-owned editor pointer access.
 std::atomic<bool> stopHints=false,hintNumericalFailed=false;std::atomic<size_t> workerHintCalls=0;
 std::thread attachmentWorker([&]{while(!stopHints.load(std::memory_order_acquire)){if(parameter(wrapper,0,0,6)!=0)hintNumericalFailed.store(true);workerHintCalls.fetch_add(1,std::memory_order_release);}});
 while(workerHintCalls.load(std::memory_order_acquire)==0)std::this_thread::yield();
 dispatch(wrapper,0,0,reinterpret_cast<std::intptr_t>((__bridge void*)parent));
 stopHints.store(true,std::memory_order_release);attachmentWorker.join();
 require(!hintNumericalFailed.load() && workerHintCalls.load()>0 && host.hints==0,"Worker first-attachment hint accessed GUI/host or skipped numerical work");
 require(parent.subviews.count==1 && get<std::intptr_t>(wrapper,24)!=0,"Native editor attachment failed");
 const auto locksBeforeWorker=host.locks;
 std::thread worker([&]{method<void(*)(void*)>(wrapper,0x138)(wrapper);method<void(*)(void*)>(wrapper,0x140)(wrapper);idle(wrapper);dispatch(wrapper,0,0,0);});worker.join();
 require(host.resizes==0 && host.locks==locksBeforeWorker && parent.subviews.count==1 && get<std::intptr_t>(wrapper,24)!=0,"Worker tick/Idle accessed GUI/host state");
 idle(wrapper);require(host.resizes==1,"Deferred native editor resize notification failed");
 NSView* editor=parent.subviews[0];NSSlider* pan=nil;NSSlider* volume=nil;NSMutableArray<NSLevelIndicator*>* meters=[NSMutableArray array];
 for(NSView* view in editor.subviews){if([view isKindOfClass:NSSlider.class]){NSSlider* s=(NSSlider*)view;if(s.tag==0)pan=s;else volume=s;}if([view isKindOfClass:NSLevelIndicator.class])[meters addObject:(NSLevelIndicator*)view];}
 require(pan && volume && meters.count==2,"Native editor widgets absent");
 pan.integerValue=-128;[pan sendAction:pan.action to:pan.target];require(host.index==0 && host.value==-128 && parameter(wrapper,0,0,2)==-128,"Pan UI/native parameter mismatch");
 volume.integerValue=320;[volume sendAction:volume.action to:volume.target];require(host.index==1 && host.value==320 && parameter(wrapper,1,0,2)==320,"Volume UI/native parameter mismatch");
 require(host.changes==2 && host.hints==2 && host.hint.find("Volume:")==0,"Native host UI notification failed");
 parameter(wrapper,0,0,17);parameter(wrapper,1,256,17);idle(wrapper);require(pan.integerValue==0 && volume.integerValue==256,"Host automation/editor refresh failed");
 parameter(wrapper,0,0,6);require(host.hints==3 && host.hint=="Pan: Center","Native hint flag failed");
 dispatch(wrapper,2,0,0);std::array<float,18> input{},output{};input[0]=1;input[1]=.5f;input[16]=-1;input[17]=-2;
 host.locked=true;method<void(*)(void*,const float*,float*,std::int32_t)>(wrapper,0x100)(wrapper,input.data(),output.data(),9);host.locked=false;
 idle(wrapper);require(meters[0].doubleValue==1 && meters[1].doubleValue==.5,"Native audio/editor meter refresh failed");
 dispatch(wrapper,0,0,0);require(parent.subviews.count==0 && get<std::intptr_t>(wrapper,24)==0,"Native editor detach failed");
 dispatch(wrapper,0,0,reinterpret_cast<std::intptr_t>((__bridge void*)parent));idle(wrapper);require(host.resizes==2,"Native editor reattach failed");
 method<void(*)(void*)>(wrapper,0xc8)(wrapper);require(parent.subviews.count==0,"Native editor destruction left an attached view");
 method<void(*)(void*,std::intptr_t)>(wrapper,0x60)(wrapper,1);method<void(*)(void*,std::intptr_t)>(hostWrapper,0x60)(hostWrapper,1);
 require(host.locks==host.unlocks && !host.locked,"Unbalanced host editor locks");dlclose(library);dlclose(engine);
 std::cout<<"{\"status\":\"passed\",\"independently_written_appkit_editor\":true,\"actual_engine_plugin_and_host_adapters\":true,\"concurrent_first_attachment_worker_hints_checked\":true,\"worker_tick_idle_skipped_gui\":true,\"control_changes\":"<<host.changes<<",\"hints\":"<<host.hints<<",\"resize_notifications\":"<<host.resizes<<",\"source_gui_resources_copied\":false,\"actual_fl_application_created\":false,\"full_plugin_equivalence\":false}\n";
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}}

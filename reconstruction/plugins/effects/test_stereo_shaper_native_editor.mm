#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This identity-bound native editor test requires macOS arm64.
#endif
#include "stereo_shaper_native_abi.h"
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
using namespace veggie_loops::stereo_shaper::native;
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
  bool locked=false;int locks=0,unlocks=0,changes=0,hints=0,resizes=0;std::vector<std::pair<int32_t,int32_t>>registrations;
  std::int32_t index=-1,value=-1;std::string hint;
  void* pluginWrapper=nullptr;
};
void hostLock(Host* h,std::intptr_t tag){require(tag==0x564c && !h->locked,"Host lock protocol failed");h->locked=true;++h->locks;}
void hostUnlock(Host* h,std::intptr_t tag){require(tag==0x564c && h->locked,"Host unlock protocol failed");h->locked=false;++h->unlocks;}
void hostChanged(Host* h,std::intptr_t tag,std::int32_t index,std::int32_t value){require(tag==0x564c && !h->locked,"Change callback occurred inside lock");h->index=index;h->value=value;++h->changes;}
void hostHint(Host* h,std::intptr_t tag,const char* text){require(tag==0x564c && !h->locked && text,"Hint callback protocol failed");h->hint=text;++h->hints;}
std::intptr_t hostDispatch(Host* h,std::intptr_t tag,std::intptr_t id,std::intptr_t index,std::intptr_t value){
  require(tag==0x564c && !h->locked,"Dispatch callback protocol failed");
  if(id==73){h->registrations.emplace_back(int32_t(index),int32_t(value));return 0;}
  if(id==2){require(h->pluginWrapper && get<std::intptr_t>(h->pluginWrapper,24)!=0,"Resize preceded editor-handle bridge");++h->resizes;}return 0;
}
}
int main(int argc,char** argv){@autoreleasepool{try{
 require(argc==3,"Usage: test_stereo_shaper_native_editor inspected-engine compiled-editor-plugin");
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
 NSView*editor=parent.subviews[0];std::array<NSSlider*,6>sliders{};NSPopUpButton*send=nil;NSSegmentedControl*position=nil;
 for(NSView*child in editor.subviews){if([child isKindOfClass:NSSlider.class])sliders[size_t(((NSSlider*)child).tag)]=(NSSlider*)child;if([child isKindOfClass:NSPopUpButton.class])send=(NSPopUpButton*)child;if([child isKindOfClass:NSSegmentedControl.class])position=(NSSegmentedControl*)child;}
 require(send&&position,"Native routing controls absent");for(int i=0;i<6;++i){require(sliders[size_t(i)],"Native parameter slider absent");const int32_t raw=i<4?-25600:-4096;sliders[size_t(i)].integerValue=raw;[sliders[size_t(i)]sendAction:sliders[size_t(i)].action to:sliders[size_t(i)].target];require(host.index==i&&host.value==raw&&parameter(wrapper,i,0,2)==raw,"Native slider/parameter mismatch");}
 require(host.changes==6&&host.hints==6,"Native control callback counts differ");
 [send selectItemAtIndex:3];[send sendAction:send.action to:send.target];position.selectedSegment=1;[position sendAction:position.action to:position.target];[send selectItemAtIndex:1];[send sendAction:send.action to:send.target];
 const std::vector<std::pair<int32_t,int32_t>>expected{{3,1},{3,0},{1,1}};require(host.registrations==expected,"Native routing registration differs");
 for(int i=0;i<6;++i)parameter(wrapper,i,0,17);idle(wrapper);for(int i=0;i<6;++i)require(sliders[size_t(i)].integerValue==0,"Native host automation did not refresh slider");
 parameter(wrapper,0,0,6);require(host.hints==7,"Native GUI hint flag did not notify");
 const auto beforeWorkerHints=host.hints;std::thread hintWorker([&]{parameter(wrapper,0,0,6);method<void(*)(void*)>(wrapper,0xc8)(wrapper);});hintWorker.join();require(host.hints==beforeWorkerHints&&parent.subviews.count==1&&parameter(wrapper,0,0,2)==0,"Worker hint/destruction changed editor lifetime");
 dispatch(wrapper,0,0,0);require(parent.subviews.count==0 && get<std::intptr_t>(wrapper,24)==0,"Native editor detach failed");
 dispatch(wrapper,0,0,reinterpret_cast<std::intptr_t>((__bridge void*)parent));idle(wrapper);require(host.resizes==2,"Native editor reattach failed");
 const auto beforeDestroyRegistrations=host.registrations;method<void(*)(void*)>(wrapper,0xc8)(wrapper);require(host.registrations==beforeDestroyRegistrations,"Native destroy emitted an unobserved registration callback");require(parent.subviews.count==0,"Native editor destruction left an attached view");
 method<void(*)(void*,std::intptr_t)>(wrapper,0x60)(wrapper,1);method<void(*)(void*,std::intptr_t)>(hostWrapper,0x60)(hostWrapper,1);
 require(host.locks==host.unlocks && !host.locked,"Unstereo_shaperd host editor locks");dlclose(library);dlclose(engine);
 std::cout<<"{\"status\":\"passed\",\"independently_written_appkit_editor\":true,\"actual_engine_plugin_and_host_adapters\":true,\"concurrent_first_attachment_worker_hints_checked\":true,\"worker_tick_idle_skipped_gui\":true,\"control_changes\":"<<host.changes<<",\"hints\":"<<host.hints<<",\"resize_notifications\":"<<host.resizes<<",\"source_gui_resources_copied\":false,\"actual_fl_application_created\":false,\"full_plugin_equivalence\":false}\n";
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}}

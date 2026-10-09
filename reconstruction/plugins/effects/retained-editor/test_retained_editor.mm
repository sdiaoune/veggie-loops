#import <Cocoa/Cocoa.h>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <stdexcept>
#include <thread>
namespace {
std::array<void*,2> watchedPlugins{},watchedNumerical{};
std::array<unsigned,2> pluginDeletes{},numericalDeletes{};
}
void* operator new(std::size_t n){if(void* p=std::malloc(n?n:1))return p;throw std::bad_alloc();}
void* operator new(std::size_t n,const std::nothrow_t&)noexcept{try{return ::operator new(n);}catch(...){return nullptr;}}
void operator delete(void* p)noexcept{
 if(p)for(std::size_t i=0;i<2;++i){if(p==watchedPlugins[i])++pluginDeletes[i];if(p==watchedNumerical[i])++numericalDeletes[i];}
 std::free(p);
}
void operator delete(void* p,const std::nothrow_t&)noexcept{::operator delete(p);}
void operator delete(void* p,std::size_t)noexcept{::operator delete(p);}
#include "../balance_editor.mm"
#include "../balance_native_abi.cpp"
namespace {
using namespace veggie_loops::balance::native;
void require(bool ok,const char* message){if(!ok)throw std::runtime_error(message);}
struct Host {
 void** vtable=nullptr;
 std::array<void*,43> slots{};
 unsigned lockDepth=0,locks=0,unlocks=0,hints=0,changes=0,resizes=0;
 bool ended=false;
 std::intptr_t tag=0;
 Host(std::intptr_t t):tag(t){vtable=slots.data();}
};
Host& checkHost(void* raw,std::intptr_t tag){
 auto& h=*static_cast<Host*>(raw);require(!h.ended,"Callback reached ended host owner");
 require(h.tag==tag,"Cross-instance host tag");return h;
}
void onLock(void* p,std::intptr_t tag){auto& h=checkHost(p,tag);require(!h.lockDepth,"Nested lock");++h.lockDepth;++h.locks;}
void onUnlock(void* p,std::intptr_t tag){auto& h=checkHost(p,tag);require(h.lockDepth==1,"Unbalanced unlock");--h.lockDepth;++h.unlocks;}
void onHint(void* p,std::intptr_t tag,const char* text){auto& h=checkHost(p,tag);require(!h.lockDepth && text && text[0],"Invalid hint ordering or text");++h.hints;}
void onChanged(void* p,std::intptr_t tag,std::int32_t index,std::int32_t value){auto& h=checkHost(p,tag);require(!h.lockDepth && index>=0 && index<2 && value>=-128 && value<=320,"Invalid changed callback");++h.changes;}
std::intptr_t onDispatch(void* p,std::intptr_t tag,std::intptr_t id,std::intptr_t,std::intptr_t){auto& h=checkHost(p,tag);require(id==2,"Unexpected editor dispatch");++h.resizes;return 0;}
void initializeHost(Host& h){
 h.slots[0]=reinterpret_cast<void*>(onDispatch);h.slots[1]=reinterpret_cast<void*>(onChanged);h.slots[2]=reinterpret_cast<void*>(onHint);
 h.slots[32]=reinterpret_cast<void*>(onLock);h.slots[33]=reinterpret_cast<void*>(onUnlock);
}
void clearWatch(){watchedPlugins={};watchedNumerical={};pluginDeletes={};numericalDeletes={};}
void end(Plugin* p,int route,std::size_t tracked){
 // Save the function before ending the C++ object lifetime. No post-lifetime object access.
 const auto f=route==0?p->functions->destroy:route==1?p->functions->completeDestructor:p->functions->deletingDestructor;
 f(p);
 require(numericalDeletes[tracked]==1,"Numerical ownership was not cleaned exactly once");
 if(route==1){require(pluginDeletes[tracked]==0,"Complete destructor deallocated caller storage");::operator delete(static_cast<void*>(p));}
 require(pluginDeletes[tracked]==1,"Plugin storage was not deallocated exactly once");
}
void requireCleared(VLBalanceEditorView* view){
 require(view.numerical==nullptr && view.superview==nil,"Retained view still owns numerical storage or parent");
 const auto c=view.callbacks;
 // Check before invoking a retained action: negative fixtures never dereference ended Instance storage.
 require(!c.context && !c.lock && !c.unlock && !c.changed && !c.hint,"Retained editor preserves host callback or context");
 for(NSControl* control in view.sliders)require(control.target==nil,"Retained control preserves action target");
}
}
int main(){@autoreleasepool{try{
 require(NSThread.isMainThread,"Main thread required");[NSApplication sharedApplication];
 unsigned refusals=0,retainedActions=0,peerActions=0;
 for(int rep=0;rep<24;++rep)for(int route=0;route<3;++route){@autoreleasepool{
  clearWatch();Host host(1000+rep*3+route),peerHost(2000+rep*3+route);initializeHost(host);initializeHost(peerHost);
  Plugin* subject=CreatePlugInstance(&host,host.tag);Plugin* peer=CreatePlugInstance(&peerHost,peerHost.tag);
  require(subject && peer,"Factory failed");watchedPlugins={subject,peer};watchedNumerical={instance(subject).numerical,instance(peer).numerical};
  auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,500,400)];auto* peerParent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,500,400)];
  subject->functions->dispatch(subject,0,0,reinterpret_cast<std::intptr_t>((__bridge void*)parent));
  peer->functions->dispatch(peer,0,0,reinterpret_cast<std::intptr_t>((__bridge void*)peerParent));
  VLBalanceEditorView* retained=(__bridge VLBalanceEditorView*)instance(subject).editor;
  VLBalanceEditorView* retainedPeer=(__bridge VLBalanceEditorView*)instance(peer).editor;
  require(retained && retainedPeer && retained.superview==parent && retainedPeer.superview==peerParent,"Editor attachment failed");
  subject->functions->idle(subject);peer->functions->idle(peer);
  require(host.resizes==1 && peerHost.resizes==1,"Initial resize was not delivered");
  std::array<unsigned char,sizeof(Instance)> before{};std::memcpy(before.data(),&instance(subject),before.size());const auto beforeCallbacks=retained.callbacks;
  const auto hints=host.hints,changes=host.changes,locks=host.locks,unlocks=host.unlocks;
  auto refused=route==0?subject->functions->destroy:route==1?subject->functions->completeDestructor:subject->functions->deletingDestructor;
  std::thread worker([&]{refused(subject);});worker.join();
  require(std::memcmp(&instance(subject),before.data(),before.size())==0,"Off-main refusal modified plugin storage");
  const auto afterCallbacks=retained.callbacks;
  require(afterCallbacks.context==beforeCallbacks.context && afterCallbacks.lock==beforeCallbacks.lock && afterCallbacks.unlock==beforeCallbacks.unlock && afterCallbacks.changed==beforeCallbacks.changed && afterCallbacks.hint==beforeCallbacks.hint,"Off-main refusal modified editor callbacks");
  require(retained.numerical==watchedNumerical[0] && retained.superview==parent,"Off-main refusal detached editor");
  for(NSControl* control in retained.sliders)require(control.target==retained,"Off-main refusal cleared a live target");
  require(pluginDeletes[0]==0 && numericalDeletes[0]==0 && host.hints==hints && host.changes==changes && host.locks==locks && host.unlocks==unlocks,"Off-main refusal performed cleanup or a host callback");++refusals;
  end(subject,route,0);host.ended=true;requireCleared(retained);
  for(std::int32_t index=0;index<2;++index){
   vl_balance_editor_hint((__bridge void*)retained,index,index==0?-64:192);++retainedActions;
   [retained changed:retained.sliders[index]];++retainedActions;
  }
  vl_balance_editor_refresh((__bridge void*)retained);++retainedActions;
  require(host.hints==hints && host.changes==changes && host.locks==locks && host.unlocks==unlocks,"Retained editor delivered a callback after teardown");
  require(!pluginDeletes[1] && !numericalDeletes[1],"Other instance was destroyed");
  const auto peerHints=peerHost.hints,peerChanges=peerHost.changes;
  retainedPeer.sliders[0].integerValue=rep-12;[retainedPeer changed:retainedPeer.sliders[0]];++peerActions;
  vl_balance_editor_hint((__bridge void*)retainedPeer,1,256);++peerActions;
  vl_balance_editor_refresh((__bridge void*)retainedPeer);++peerActions;
  require(peerHost.hints==peerHints+2 && peerHost.changes==peerChanges+1 && peerHost.locks==peerHost.unlocks && !peerHost.lockDepth,"Live peer lost callbacks or lock balance");
  end(peer,(route+1)%3,1);peerHost.ended=true;requireCleared(retainedPeer);
  vl_balance_editor_hint((__bridge void*)retainedPeer,0,0);++retainedActions;
  require(peerHost.hints==peerHints+2,"Retained peer delivered a callback after teardown");
  clearWatch();
 }}
 std::cout<<"{\"status\":\"matched_own_retained_editor_teardown_contract\",\"instances\":144,\"subject_routes\":72,\"off_main_attached_refusals\":"<<refusals<<",\"retained_actions\":"<<retainedActions<<",\"live_peer_actions\":"<<peerActions<<",\"original_editor_compared\":false,\"full_plugin_equivalence\":false}\n";
 return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}}

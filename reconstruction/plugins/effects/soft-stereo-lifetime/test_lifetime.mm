#if !defined(__APPLE__) || !defined(__aarch64__)
#error This source lifecycle fixture requires macOS arm64.
#endif
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
#include <vector>
namespace {
std::array<void*,6> watched{};
std::array<unsigned,6> frees{};
int allocationBudget=-1;
void* failureAllocation=nullptr;
unsigned failureAllocations=0,failureFrees=0;
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR) || defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
unsigned editorCleanupEntries=0;
#endif
}
void* operator new(std::size_t n){
 if(allocationBudget==0)throw std::bad_alloc();
 const bool injection=allocationBudget>0;if(injection)--allocationBudget;
 if(void* p=std::malloc(n?n:1)){if(injection){failureAllocation=p;++failureAllocations;}return p;}throw std::bad_alloc();
}
void* operator new(std::size_t n,const std::nothrow_t&)noexcept{try{return ::operator new(n);}catch(...){return nullptr;}}
void operator delete(void* p)noexcept{
 if(p){for(size_t i=0;i<watched.size();++i)if(watched[i]==p)++frees[i];if(p==failureAllocation)++failureFrees;}std::free(p);
}
void operator delete(void* p,const std::nothrow_t&)noexcept{::operator delete(p);}
void operator delete(void* p,std::size_t)noexcept{::operator delete(p);}
#if defined(VL_TEST_STEREO)
#include "stereo_shaper_native_abi.cpp"
// Unchanged numerical source is included in this fixture only to watch the
// live delay allocation/history. Production modules do not expose a getter.
#include "stereo_shaper_plugin.cpp"
#if defined(VL_STEREO_SHAPER_APPKIT_EDITOR)
#define VL_LIFETIME_HAS_EDITOR 1
#define vl_stereo_shaper_editor_destroy vl_test_stereo_editor_destroy_real
#include "stereo_shaper_editor.mm"
#undef vl_stereo_shaper_editor_destroy
extern "C" int vl_stereo_shaper_editor_destroy(void* e){++editorCleanupEntries;return vl_test_stereo_editor_destroy_real(e);}
#endif
#else
#include "soft_clipper_native_abi.cpp"
#include "soft_clipper_plugin.cpp"
#if defined(VL_SOFT_CLIPPER_APPKIT_EDITOR)
#define VL_LIFETIME_HAS_EDITOR 1
#define vl_soft_clipper_editor_destroy vl_test_soft_editor_destroy_real
#include "soft_clipper_editor.mm"
#undef vl_soft_clipper_editor_destroy
extern "C" int vl_soft_clipper_editor_destroy(void* e){++editorCleanupEntries;return vl_test_soft_editor_destroy_real(e);}
#endif
#endif
namespace {
void require(bool condition,const char* message){if(!condition)throw std::runtime_error(message);}
#if defined(VL_TEST_STEREO)
using Numerical=VLStereoShaperPlugin;
constexpr auto numericalCreate=&vl_stereo_shaper_create;
constexpr auto numericalDestroy=&vl_stereo_shaper_destroy;
constexpr auto numericalParameter=&vl_stereo_shaper_parameter;
constexpr auto numericalSave=&vl_stereo_shaper_save_state;
constexpr size_t stateSize=36;constexpr int controls=6;
constexpr const char* family="Stereo Shaper";
#else
using Numerical=VLSoftClipperPlugin;
constexpr auto numericalCreate=&vl_soft_clipper_create;
constexpr auto numericalDestroy=&vl_soft_clipper_destroy;
constexpr auto numericalParameter=&vl_soft_clipper_parameter;
constexpr auto numericalSave=&vl_soft_clipper_save_state;
constexpr size_t stateSize=8;constexpr int controls=2;
constexpr const char* family="Soft Clipper";
#endif
using State=std::array<uint8_t,stateSize>;
State snapshot(Plugin* p){State bytes{};require(numericalSave(object(p).numerical,bytes.data(),bytes.size()),"Live raw state save failed");return bytes;}
void* ring(Plugin* p){
#if defined(VL_TEST_STEREO)
 return object(p).numerical->processor.delay.data();
#else
 (void)p;return nullptr;
#endif
}
std::vector<std::byte> numericalSnapshot(Plugin* p){
 auto* numerical=object(p).numerical;size_t size=sizeof *numerical;
#if defined(VL_TEST_STEREO)
 const auto count=numerical->processor.delay.size()*sizeof(float);size+=count;
#endif
 std::vector<std::byte> bytes(size);std::memcpy(bytes.data(),numerical,sizeof *numerical);
#if defined(VL_TEST_STEREO)
 if(count)std::memcpy(bytes.data()+sizeof *numerical,numerical->processor.delay.data(),count);
#endif
 return bytes;
}
struct Host {
 void** functions=nullptr;std::array<void*,43> table{};intptr_t tag=0;
 unsigned locks=0,unlocks=0,depth=0,hints=0,changes=0,resizes=0,routing=0,outputCalls=0;
 int activeSend=0;bool ended=false;std::array<float,68> side{};
 explicit Host(intptr_t t):tag(t){functions=table.data();}
};
Host& checkedHost(void* pointer,intptr_t tag){auto& host=*static_cast<Host*>(pointer);require(!host.ended&&host.tag==tag,"Borrowed host ended or crossed instance tags");return host;}
intptr_t onDispatch(void* p,intptr_t tag,intptr_t id,intptr_t index,intptr_t value){
 auto& h=checkedHost(p,tag);require(!h.depth,"Host notification delivered under lock");
 if(id==2){++h.resizes;return 0;}require(id==73&&index>=1&&index<=3&&(value==0||value==1),"Unexpected own host routing event");++h.routing;if(value)h.activeSend=int(index);else if(h.activeSend==index)h.activeSend=0;return 0;
}
void onLock(void* p,intptr_t tag){auto& h=checkedHost(p,tag);require(!h.depth,"Nested own host lock");++h.depth;++h.locks;}
void onUnlock(void* p,intptr_t tag){auto& h=checkedHost(p,tag);require(h.depth==1,"Unbalanced own host unlock");--h.depth;++h.unlocks;}
void onHint(void* p,intptr_t tag,const char* text){auto& h=checkedHost(p,tag);require(!h.depth&&text&&text[0],"Invalid own hint delivery");++h.hints;}
void onChanged(void* p,intptr_t tag,int32_t index,int32_t){auto& h=checkedHost(p,tag);require(!h.depth&&index>=0&&index<controls,"Invalid own change delivery");++h.changes;}
#if defined(VL_TEST_STEREO)
void onOutput(void* p,intptr_t tag,intptr_t index,IOBuffer* buffer){auto& h=checkedHost(p,tag);require(index==h.activeSend&&index>0&&buffer&&buffer->flags<=1,"Invalid own output descriptor");++h.outputCalls;if(buffer->flags==0)buffer->buffer=h.side.data()+2;}
#endif
void initialize(Host& h){h.table[0]=reinterpret_cast<void*>(&onDispatch);h.table[1]=reinterpret_cast<void*>(&onChanged);h.table[2]=reinterpret_cast<void*>(&onHint);h.table[32]=reinterpret_cast<void*>(&onLock);h.table[33]=reinterpret_cast<void*>(&onUnlock);
#if defined(VL_TEST_STEREO)
 h.table[37]=reinterpret_cast<void*>(&onOutput);
#endif
}
std::array<unsigned,7> counters(const Host& h){return {h.locks,h.unlocks,h.depth,h.hints,h.changes,h.routing,h.outputCalls};}
int rawValue(int iteration,int index){
#if defined(VL_TEST_STEREO)
 const std::array<int,6> values{-6400+iteration*1000,14000+iteration*1000,10000+iteration*1000,3200-iteration*700,512+iteration*341,1024+iteration*256};return values[size_t(index)];
#else
 return index==0?100+iteration*3:128-iteration*9;
#endif
}
std::array<float,64> input(){std::array<float,64> data{};for(size_t i=0;i<32;++i){data[2*i]=.125f+float(i)*.0009765625f;data[2*i+1]=-.25f+float(i)*.001953125f;}data[0]=+0.f;data[1]=-0.f;return data;}
void setup(Plugin* p,Numerical* reference,int iteration,Host& h){
 for(int index=0;index<controls;++index){const auto value=rawValue(iteration,index);require(p->functions->parameter(p,index,value,1)==value,"Own control setup failed");if(reference){int32_t result=0;require(numericalParameter(reference,index,value,1,&result)&&result==value,"Reference control setup failed");}}
#if defined(VL_TEST_STEREO)
 const int send=1+iteration%3,mode=iteration%2;require(vl_stereo_shaper_routing(object(p).numerical,send,mode),"Own routing setup failed");notifyRouting(object(p),send);if(reference)require(vl_stereo_shaper_routing(reference,send,mode),"Reference routing setup failed");require(h.activeSend==send,"Own send registration absent");
#else
 (void)h;
#endif
}
void renderPeer(Plugin* p,Numerical* reference,Host& host){const auto in=input();std::array<float,68> actual{},expected{};actual.fill(123.25f);expected.fill(123.25f);host.side.fill(123.25f);for(size_t i=2;i<66;++i)host.side[i]=.125f;
#if defined(VL_TEST_STEREO)
 auto expectedSide=host.side;
#endif
 p->functions->effect(p,in.data(),actual.data()+2,32);
#if defined(VL_TEST_STEREO)
 require(vl_stereo_shaper_render(reference,in.data(),expected.data()+2,32,expectedSide.data()+2),"Reference render failed");require(!std::memcmp(host.side.data(),expectedSide.data(),sizeof expectedSide),"Own side PCM or guards differ");
#else
 require(vl_soft_clipper_render(reference,in.data(),expected.data()+2,32),"Reference render failed");std::array<float,2> actualMeters{},expectedMeters{};require(vl_soft_clipper_get_meters(object(p).numerical,actualMeters.data())&&vl_soft_clipper_get_meters(reference,expectedMeters.data())&&!std::memcmp(actualMeters.data(),expectedMeters.data(),sizeof actualMeters),"Peer numerical meter state differs");
#endif
 require(!std::memcmp(actual.data(),expected.data(),sizeof actual),"Peer PCM or guards differ");
}
void primeSelected(Plugin* p,Host& h){const auto in=input();std::array<float,68> out{};out.fill(123.25f);h.side.fill(123.25f);for(size_t i=2;i<66;++i)h.side[i]=.125f;p->functions->effect(p,in.data(),out.data()+2,32);require(out[0]==123.25f&&out[1]==123.25f&&out[66]==123.25f&&out[67]==123.25f&&h.side[0]==123.25f&&h.side[1]==123.25f&&h.side[66]==123.25f&&h.side[67]==123.25f,"Selected priming touched guards");}
#if defined(VL_LIFETIME_HAS_EDITOR)
#if defined(VL_TEST_STEREO)
using View=VLStereoShaperEditorView;
void cleared(View* view){const auto h=view.callbacks;require(view.numerical==nullptr&&view.superview==nil&&!h.context&&!h.lock&&!h.unlock&&!h.changed&&!h.hint&&!h.routing,"Retained view preserves numerical or host callback/context");for(NSControl* control in view.sliders)require(control.target==nil,"Retained control target remains");require(view.send.target==nil&&view.position.target==nil,"Retained routing control target remains");}
void retainedActions(View* view){cleared(view);[view refresh];for(NSControl* control in view.sliders)[view changed:control];[view changed:view.send];[view changed:view.position];vl_stereo_shaper_editor_hint((__bridge void*)view,0,0);}
void livePeerAction(View* view,Numerical* reference){const int value=int(view.sliders[0].integerValue)+1;view.sliders[0].integerValue=value;[view changed:view.sliders[0]];int32_t result=0;require(numericalParameter(reference,0,value,1,&result),"Peer reference action rejected");vl_stereo_shaper_editor_hint((__bridge void*)view,0,value);[view refresh];}
#else
using View=VLSoftClipperEditorView;
void cleared(View* view){const auto h=view.callbacks;require(view.numerical==nullptr&&view.superview==nil&&!h.context&&!h.lock&&!h.unlock&&!h.changed&&!h.hint,"Retained view preserves numerical or host callback/context");for(NSControl* control in view.sliders)require(control.target==nil,"Retained control target remains");}
void retainedActions(View* view){cleared(view);[view refresh];for(NSSlider* control in view.sliders)[view changed:control];vl_soft_clipper_editor_hint((__bridge void*)view,0,100);}
void livePeerAction(View* view,Numerical* reference){const int value=int(view.sliders[0].integerValue)+1;view.sliders[0].integerValue=value;[view changed:view.sliders[0]];int32_t result=0;require(numericalParameter(reference,0,value,1,&result),"Peer reference action rejected");vl_soft_clipper_editor_hint((__bridge void*)view,0,value);[view refresh];require(vl_soft_clipper_clear_meters(reference),"Reference meter clear rejected");}
#endif
#endif
unsigned complete=0,deleting=0,ordinary=0,ringCleanups=0;
void finish(Plugin* p,int route,size_t base){const auto callback=route==0?p->functions->completeDestructor:route==1?p->functions->deletingDestructor:p->functions->destroy;const bool ownedRing=watched[base+2]!=nullptr;callback(p);
 require(frees[base+1]==1,"Numerical resource must be released exactly once");require(frees[base+2]==unsigned(ownedRing),"Owned delay allocation must be released exactly once");if(ownedRing)++ringCleanups;
 if(route==0){require(frees[base]==0,"Complete lifetime must retain caller raw storage");::operator delete(static_cast<void*>(p));++complete;}else if(route==1)++deleting;else ++ordinary;
 require(frees[base]==1,"Deleting lifetime must release selected raw storage once");for(size_t i=base;i<base+3;++i)watched[i]=nullptr;
}
}
int main(){@autoreleasepool{try{
 require(NSThread.isMainThread,"Main required");[NSApplication sharedApplication];auto* prime=CreatePlugInstance(nullptr,0);require(prime,"Metadata prime failed");prime->functions->destroy(prime);
 unsigned failures=0;for(int budget:{0,1}){failureAllocation=nullptr;failureAllocations=failureFrees=0;allocationBudget=budget;auto* p=CreatePlugInstance(nullptr,0);allocationBudget=-1;require(!p&&failureAllocations==unsigned(budget)&&failureFrees==unsigned(budget),"Factory failure leaked allocation");failureAllocation=nullptr;++failures;}
 functions.destroy(nullptr);functions.completeDestructor(nullptr);functions.deletingDestructor(nullptr);
 unsigned pairs=0,refusals=0,attached=0,retained=0,peerActions=0,mainEditorCleanups=0;
 for(int iteration=0;iteration<4;++iteration)for(int route=0;route<3;++route){@autoreleasepool{
 watched={};frees={};Host host(1000+iteration*3+route),peerHost(2000+iteration*3+route);initialize(host);initialize(peerHost);
 auto* p=CreatePlugInstance(&host,host.tag);auto* peer=CreatePlugInstance(&peerHost,peerHost.tag);auto* reference=numericalCreate();require(p&&peer&&reference&&p!=peer&&object(p).numerical!=object(peer).numerical,"Independent factories failed");
 setup(p,nullptr,iteration,host);setup(peer,reference,3-iteration,peerHost);watched={p,object(p).numerical,ring(p),peer,object(peer).numerical,ring(peer)};p->mono=-234567;peer->mono=0x7654321;
#if defined(VL_LIFETIME_HAS_EDITOR)
 auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,550,370)];auto* peerParent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,550,370)];
 const auto refuse=[&]{std::array<std::byte,sizeof(Instance)> before{};std::memcpy(before.data(),p,before.size());const auto numerical=numericalSnapshot(p);const auto callbacks=counters(host);const auto entries=editorCleanupEntries;const auto f=route==0?p->functions->completeDestructor:route==1?p->functions->deletingDestructor:p->functions->destroy;std::thread worker([&]{f(p);});worker.join();require(editorCleanupEntries==entries,"Worker lifetime entered editor cleanup");require(frees==std::array<unsigned,6>{0,0,0,0,0,0}&&!std::memcmp(before.data(),p,before.size())&&numericalSnapshot(p)==numerical&&counters(host)==callbacks,"Worker refusal changed instance/numerical/host ownership");++refusals;};
 refuse();p->functions->dispatch(p,0,0,reinterpret_cast<intptr_t>((__bridge void*)parent));require(object(p).editor&&parent.subviews.count==1,"Subject editor attachment failed");View* retainedView=(__bridge View*)object(p).editor;refuse();p->functions->dispatch(p,0,0,0);require(parent.subviews.count==0,"Subject detach failed");refuse();p->functions->dispatch(p,0,0,reinterpret_cast<intptr_t>((__bridge void*)parent));require(parent.subviews.count==1,"Subject reattach failed");
 peer->functions->dispatch(peer,0,0,reinterpret_cast<intptr_t>((__bridge void*)peerParent));require(object(peer).editor&&peerParent.subviews.count==1,"Peer editor attachment failed");View* retainedPeer=(__bridge View*)object(peer).editor;attached+=2;
#endif
 primeSelected(p,host);renderPeer(peer,reference,peerHost);const auto peerState=snapshot(peer);const auto peerNumerical=numericalSnapshot(peer);const auto info=*peer->info;std::array<std::byte,sizeof(Instance)> before{};std::memcpy(before.data(),peer,before.size());const auto hostBefore=counters(host),peerBefore=counters(peerHost);const int registered=host.activeSend,peerRegistered=peerHost.activeSend;
#if defined(VL_LIFETIME_HAS_EDITOR)
 const auto entries=editorCleanupEntries;
#endif
 finish(p,route,0);host.ended=true;require(counters(host)==hostBefore&&host.activeSend==registered,"Cleanup delivered a borrowed-host teardown/routing event");require(!frees[3]&&!frees[4]&&!frees[5]&&!std::memcmp(before.data(),peer,before.size())&&peerState==snapshot(peer)&&peerNumerical==numericalSnapshot(peer)&&!std::memcmp(&info,peer->info,sizeof info)&&peer->mono==0x7654321&&counters(peerHost)==peerBefore&&peerHost.activeSend==peerRegistered,"Selected cleanup changed live peer resources/state/host");renderPeer(peer,reference,peerHost);
#if defined(VL_LIFETIME_HAS_EDITOR)
 require(editorCleanupEntries==entries+1,"Main cleanup must enter editor exactly once");require(parent.subviews.count==0,"Main cleanup left attached subject view");retainedActions(retainedView);require(counters(host)==hostBefore,"Retained subject delivered host callback");++retained;++mainEditorCleanups;const auto hints=peerHost.hints,changes=peerHost.changes;livePeerAction(retainedPeer,reference);require(peerHost.hints==hints+2&&peerHost.changes==changes+1&&peerHost.locks==peerHost.unlocks&&!peerHost.depth,"Live peer callbacks lost or unbalanced");++peerActions;renderPeer(peer,reference,peerHost);const auto peerEntries=editorCleanupEntries;
#endif
 const auto beforePeerCleanup=counters(peerHost);finish(peer,(route+1)%3,3);peerHost.ended=true;require(counters(peerHost)==beforePeerCleanup&&peerHost.activeSend==peerRegistered,"Peer cleanup delivered borrowed-host routing event");
#if defined(VL_LIFETIME_HAS_EDITOR)
 require(editorCleanupEntries==peerEntries+1&&peerParent.subviews.count==0,"Peer main editor cleanup failed");retainedActions(retainedPeer);require(counters(peerHost)==beforePeerCleanup,"Retained peer delivered host callback");++retained;++mainEditorCleanups;
#endif
 watched={};numericalDestroy(reference);++pairs;
 }}
 std::cout<<"{\"status\":\"passed_own_Soft_Stereo_lifetime_contract\",\"family\":\""<<family<<"\",\"pairs\":"<<pairs<<",\"instances\":"<<pairs*2<<",\"complete_caller_free\":"<<complete<<",\"deleting\":"<<deleting<<",\"DestroyObject\":"<<ordinary<<",\"allocation_failures\":"<<failures<<",\"offmain_refusals\":"<<refusals<<",\"attached_editors\":"<<attached<<",\"retained_view_cases\":"<<retained<<",\"live_peer_actions\":"<<peerActions<<",\"main_editor_cleanup_calls\":"<<mainEditorCleanups<<",\"delay_ring_cleanups\":"<<ringCleanups<<",\"borrowed_host_teardown_events\":0,\"own_allocator_hooks\":true,\"original_images_loaded\":false,\"original_extra_destructor_equivalence\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception& e){allocationBudget=-1;std::cerr<<e.what()<<'\n';return 1;}}}

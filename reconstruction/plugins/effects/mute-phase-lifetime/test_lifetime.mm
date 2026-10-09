#if !defined(__APPLE__) || !defined(__aarch64__)
#error This own-source lifecycle fixture requires macOS arm64.
#endif
#import <Cocoa/Cocoa.h>
#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <stdexcept>
#include <thread>
namespace {
std::array<void*,4> watched{};
std::array<unsigned,4> frees{};
int allocationBudget=-1;
void* failureAllocation=nullptr;
unsigned failureAllocations=0,failureFrees=0;
#if defined(VL_MUTE2_APPKIT_EDITOR) || defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
unsigned editorCleanupEntries=0;
#endif
}
void* operator new(std::size_t n){
 if(allocationBudget==0)throw std::bad_alloc();
 const bool injection=allocationBudget>0;if(injection)--allocationBudget;
 if(void* p=std::malloc(n?n:1)){if(injection){failureAllocation=p;++failureAllocations;}return p;}
 throw std::bad_alloc();
}
void* operator new(std::size_t n,const std::nothrow_t&)noexcept{try{return ::operator new(n);}catch(...){return nullptr;}}
void operator delete(void* p)noexcept{
 if(p){for(size_t i=0;i<watched.size();++i)if(watched[i]==p)++frees[i];if(p==failureAllocation)++failureFrees;}
 std::free(p);
}
void operator delete(void* p,const std::nothrow_t&)noexcept{::operator delete(p);}
void operator delete(void* p,std::size_t)noexcept{::operator delete(p);}
#if defined(VL_TEST_PHASE)
#include "phase_inverter_native_abi.cpp"
#if defined(VL_PHASE_INVERTER_APPKIT_EDITOR)
#define VL_LIFETIME_HAS_EDITOR 1
#define vl_phase_inverter_editor_destroy vl_test_phase_editor_destroy_real
#include "phase_inverter_editor.mm"
#undef vl_phase_inverter_editor_destroy
extern "C" int vl_phase_inverter_editor_destroy(void* e){++editorCleanupEntries;return vl_test_phase_editor_destroy_real(e);}
#endif
#else
#include "mute2_native_abi.cpp"
#if defined(VL_MUTE2_APPKIT_EDITOR)
#define VL_LIFETIME_HAS_EDITOR 1
#define vl_mute2_editor_destroy vl_test_mute_editor_destroy_real
#include "mute2_editor.mm"
#undef vl_mute2_editor_destroy
extern "C" int vl_mute2_editor_destroy(void* e){++editorCleanupEntries;return vl_test_mute_editor_destroy_real(e);}
#endif
#endif
namespace {
#if defined(VL_TEST_PHASE)
using Numerical=VLPhaseInverterPlugin;
constexpr auto numericalCreate=&vl_phase_inverter_create;
constexpr auto numericalDestroy=&vl_phase_inverter_destroy;
constexpr auto numericalParameter=&vl_phase_inverter_parameter;
constexpr auto numericalSave=&vl_phase_inverter_save_state;
constexpr auto numericalRender=&vl_phase_inverter_render;
constexpr size_t stateSize=8;constexpr int controls=1;
constexpr const char* family="Phase Inverter";
#else
using Numerical=VLMute2Plugin;
constexpr auto numericalCreate=&vl_mute2_create;
constexpr auto numericalDestroy=&vl_mute2_destroy;
constexpr auto numericalParameter=&vl_mute2_parameter;
constexpr auto numericalSave=&vl_mute2_save_state;
constexpr auto numericalRender=&vl_mute2_render;
constexpr size_t stateSize=12;constexpr int controls=2;
constexpr const char* family="Mute 2";
#endif
void require(bool condition,const char* message){if(!condition)throw std::runtime_error(message);}
using State=std::array<uint8_t,stateSize>;
State snapshot(Plugin* p){State s{};require(numericalSave(object(p).numerical,s.data(),s.size()),"Live numerical state snapshot failed");return s;}
std::array<float,64> sampleInput(){
 std::array<float,64> data{};for(size_t i=0;i<32;++i){data[2*i]=.125f+float(i)*.0009765625f;data[2*i+1]=-.25f+float(i)*.001953125f;}
 data[0]=+0.f;data[1]=-0.f;
#if defined(VL_TEST_PHASE)
 data[2]=std::bit_cast<float>(0x7fc0beefu);data[3]=std::bit_cast<float>(0xffa01234u);
#endif
 return data;
}
void renderPeer(Plugin* p,Numerical* reference){
 const auto in=sampleInput();std::array<float,68> actual{},expected{};actual.fill(123.25f);expected.fill(123.25f);
 p->functions->effect(p,in.data(),actual.data()+2,32);
 require(numericalRender(reference,in.data(),expected.data()+2,32),"Reference numerical render rejected");
 require(!std::memcmp(actual.data(),expected.data(),sizeof actual),"Peer numerical output or nonzero guards changed");
}
#if defined(VL_LIFETIME_HAS_EDITOR)
#if defined(VL_TEST_PHASE)
void retainedViewActions(VLPhaseInverterEditorView* view){
 require(view&&view.numerical==nullptr&&view.callbacks.context==nullptr&&!view.callbacks.lock&&!view.callbacks.unlock&&!view.callbacks.changed&&!view.callbacks.hint&&view.inversion.target==nil,"Retained view still owns ended numerical/context/control access");
 [view refresh];[view changed:view.inversion];vl_phase_inverter_editor_hint((__bridge void*)view,0,512);
}
#else
void retainedViewActions(VLMute2EditorView* view){
 require(view&&view.numerical==nullptr&&view.callbacks.context==nullptr&&!view.callbacks.lock&&!view.callbacks.unlock&&!view.callbacks.changed&&!view.callbacks.hint&&view.enabled.target==nil&&view.channels.target==nil,"Retained view still owns ended numerical/context/control access");
 [view refresh];[view changed:view.enabled];[view changed:view.channels];vl_mute2_editor_hint((__bridge void*)view,0,512);vl_mute2_editor_hint((__bridge void*)view,1,512);
}
#endif
#endif
}
int main(){@autoreleasepool{try{
 [NSApplication sharedApplication];auto* prime=CreatePlugInstance(nullptr,0);require(prime,"Factory metadata prime failed");prime->functions->destroy(prime);
 unsigned allocationFailures=0;
 for(int budget:{0,1}){failureAllocation=nullptr;failureAllocations=failureFrees=0;allocationBudget=budget;auto* p=CreatePlugInstance(nullptr,0);allocationBudget=-1;require(!p&&failureAllocations==unsigned(budget)&&failureFrees==unsigned(budget),"Factory failure leaked own allocation");failureAllocation=nullptr;++allocationFailures;}
 functions.destroy(nullptr);functions.completeDestructor(nullptr);functions.deletingDestructor(nullptr);
 unsigned pairs=0,complete=0,deleting=0,ordinary=0,refusals=0,attached=0,retainedActions=0,editorCleanups=0;
 for(int iteration=0;iteration<4;++iteration)for(int route=0;route<3;++route){
  watched={};frees={};auto* p=CreatePlugInstance(nullptr,INT64_C(0x1234567812345678));auto* peer=CreatePlugInstance(nullptr,-INT64_C(0x11223344556677));
  require(p&&peer&&p!=peer&&object(p).numerical!=object(peer).numerical,"Two live factories must own distinct resources");
  auto* reference=numericalCreate();require(reference,"Reference numerical factory failed");watched={p,object(p).numerical,peer,object(peer).numerical};
  p->mono=-7654321;peer->mono=0x55667788;
  for(int index=0;index<controls;++index){const int value=(iteration*341+index*137)%1025;require(p->functions->parameter(p,index,1024-value,1)==1024-value,"Selected control setup failed");int32_t result=0;require(numericalParameter(reference,index,value,1,&result)&&peer->functions->parameter(peer,index,value,1)==result,"Peer/reference control setup differs");}
  renderPeer(peer,reference);const auto selectedState=snapshot(p),peerState=snapshot(peer);const auto information=*peer->info;
  std::array<std::byte,sizeof(Instance)> peerBefore{};std::memcpy(peerBefore.data(),peer,peerBefore.size());
  auto finish=route==0?p->functions->completeDestructor:route==1?p->functions->deletingDestructor:p->functions->destroy;
#if defined(VL_LIFETIME_HAS_EDITOR)
  const auto refuse=[&]{std::array<std::byte,sizeof(Instance)> before{};std::memcpy(before.data(),p,before.size());const auto cleanup=editorCleanupEntries;std::thread worker([&]{finish(p);});worker.join();require(editorCleanupEntries==cleanup,"Worker lifetime entered editor cleanup");require(frees==std::array<unsigned,4>{0,0,0,0}&&!std::memcmp(before.data(),p,before.size())&&selectedState==snapshot(p),"Worker refusal changed instance/resource ownership/state");++refusals;};
  refuse();auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,450,260)];p->functions->dispatch(p,0,0,reinterpret_cast<intptr_t>((__bridge void*)parent));
  require(object(p).editor&&parent.subviews.count==1,"Optional editor attachment failed");
#if defined(VL_TEST_PHASE)
  VLPhaseInverterEditorView* retained=(__bridge VLPhaseInverterEditorView*)object(p).editor;
#else
  VLMute2EditorView* retained=(__bridge VLMute2EditorView*)object(p).editor;
#endif
  ++attached;refuse();p->functions->dispatch(p,0,0,0);require(parent.subviews.count==0,"Optional temporary detach failed");refuse();p->functions->dispatch(p,0,0,reinterpret_cast<intptr_t>((__bridge void*)parent));require(parent.subviews.count==1,"Optional reattach failed");const auto mainEntries=editorCleanupEntries;
#else
  (void)selectedState;
#endif
  finish(p);
  require(frees[1]==1&&frees[2]==0&&frees[3]==0,"Selected numerical resource must be released exactly once");
  if(route==0){require(frees[0]==0,"Complete lifetime must retain caller raw storage");::operator delete(static_cast<void*>(p));++complete;}else if(route==1)++deleting;else ++ordinary;
  require(frees[0]==1,"Deleting lifetime must release selected raw storage once");watched[0]=watched[1]=nullptr;
  require(!std::memcmp(peerBefore.data(),peer,peerBefore.size())&&!std::memcmp(&information,peer->info,sizeof information)&&peerState==snapshot(peer)&&peer->mono==0x55667788,"Peer instance/metadata/raw state changed during selected cleanup");renderPeer(peer,reference);
#if defined(VL_LIFETIME_HAS_EDITOR)
  require(editorCleanupEntries==mainEntries+1,"Main lifetime must enter editor cleanup exactly once");require(parent.subviews.count==0,"Successful lifetime left attached editor");retainedViewActions(retained);++retainedActions;++editorCleanups;
#endif
  peer->functions->destroy(peer);require(frees[2]==1&&frees[3]==1,"Peer cleanup must release both resources once");watched={};numericalDestroy(reference);++pairs;
 }
 std::cout<<"{\"status\":\"passed_source_Mute_Phase_lifetime_contract\",\"family\":\""<<family<<"\",\"pairs\":"<<pairs<<",\"complete_caller_free\":"<<complete<<",\"deleting\":"<<deleting<<",\"DestroyObject\":"<<ordinary<<",\"allocation_failures\":"<<allocationFailures<<",\"offmain_refusals\":"<<refusals<<",\"attached_editors\":"<<attached<<",\"retained_view_actions\":"<<retainedActions<<",\"main_editor_cleanup_calls\":"<<editorCleanups<<",\"own_allocator_hooks\":true,\"original_images_loaded\":false,\"original_extra_destructor_equivalence\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception&e){allocationBudget=-1;std::cerr<<e.what()<<'\n';return 1;}}}

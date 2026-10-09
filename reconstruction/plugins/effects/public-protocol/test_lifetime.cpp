#include <cstdlib>
#include <cstddef>
#include <new>
#include <iostream>
#include <stdexcept>
#include <thread>
#if defined(VL_BALANCE_APPKIT_EDITOR)
#import <Cocoa/Cocoa.h>
#endif
namespace {
void* watchedPlugin=nullptr;void* watchedNumerical=nullptr;
unsigned pluginDeletes=0,numericalDeletes=0;
}
void* operator new(std::size_t n){if(void* p=std::malloc(n?n:1))return p;throw std::bad_alloc();}
void* operator new(std::size_t n,const std::nothrow_t&)noexcept{try{return ::operator new(n);}catch(...){return nullptr;}}
void operator delete(void* p)noexcept{if(p==watchedPlugin)++pluginDeletes;if(p==watchedNumerical)++numericalDeletes;std::free(p);}
void operator delete(void* p,const std::nothrow_t&)noexcept{::operator delete(p);}
void operator delete(void* p,std::size_t)noexcept{::operator delete(p);}
#include "../balance_native_abi.cpp"
namespace {
void require(bool value,const char* text){if(!value)throw std::runtime_error(text);}
}
int main(){try{
 using namespace veggie_loops::balance::native;
 unsigned offMainRefusals=0;
#if defined(VL_BALANCE_APPKIT_EDITOR)
 [NSApplication sharedApplication];
#endif
 for(int repetition=0;repetition<32;++repetition)for(int route=0;route<3;++route){
  watchedPlugin=nullptr;watchedNumerical=nullptr;pluginDeletes=0;numericalDeletes=0;
  Plugin* p=CreatePlugInstance(nullptr,42);require(p!=nullptr,"Factory failed");
  watchedPlugin=p;watchedNumerical=instance(p).numerical;require(watchedNumerical!=nullptr,"Numerical factory failed");
#if defined(VL_BALANCE_APPKIT_EDITOR)
  const Plugin beforeHeader=*p;const auto beforeMaxPoly=instance(p).maxPoly;
  const auto beforeEditor=instance(p).editor;const auto beforeHost=instance(p).host;
  const auto beforeResizePending=instance(p).resizePending;
  auto refused=route==0?p->functions->completeDestructor:route==1?p->functions->deletingDestructor:p->functions->destroy;
  std::thread worker([&]{refused(p);});worker.join();
  require(pluginDeletes==0 && numericalDeletes==0,"Off-main lifetime callback deallocated storage");
  require(std::memcmp(p,&beforeHeader,sizeof(Plugin))==0 && instance(p).numerical==watchedNumerical && instance(p).maxPoly==beforeMaxPoly && instance(p).editor==beforeEditor && instance(p).host==beforeHost && instance(p).resizePending==beforeResizePending,"Off-main refusal modified source state");
  ++offMainRefusals;
#endif
  if(route==0){p->functions->completeDestructor(p);require(pluginDeletes==0 && numericalDeletes==1,"Complete destructor must clean ownership without deallocation");::operator delete(static_cast<void*>(p));}
  else if(route==1)p->functions->deletingDestructor(p);
  else p->functions->destroy(p);
  require(pluginDeletes==1 && numericalDeletes==1,"Lifetime route must clean and deallocate exactly once");
 }
 watchedPlugin=nullptr;watchedNumerical=nullptr;
 std::cout<<"{\"status\":\"matched_own_source_lifetime_contract\",\"instances\":96,\"complete_caller_free_routes\":32,\"deleting_routes\":32,\"DestroyObject_routes\":32,\"tracked_plugin_deallocations\":96,\"tracked_numerical_deallocations\":96,\"optional_editor_off_main_refusals\":"<<offMainRefusals<<",\"original_extra_destructor_invoked\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}

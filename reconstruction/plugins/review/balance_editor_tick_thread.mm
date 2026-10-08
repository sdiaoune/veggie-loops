#import <Cocoa/Cocoa.h>
#include "../effects/balance_native_abi.h"
#include <dlfcn.h>
#include <array>
#include <atomic>
#include <iostream>
#include <thread>
using namespace veggie_loops::balance::native;
struct Host {void** functions;std::atomic<int> resizes{0};std::atomic<int> workerResizes{0};};
std::intptr_t resize(void* p,std::intptr_t,std::intptr_t id,std::intptr_t,std::intptr_t){
 auto& h=*static_cast<Host*>(p);if(id==2){++h.resizes;if(!NSThread.isMainThread)++h.workerResizes;}return 0;
}
void lock(void*,std::intptr_t){}
int main(int argc,char** argv){@autoreleasepool{
 if(argc!=2)return 2;[NSApplication sharedApplication];void* library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!library)return 3;
 auto create=reinterpret_cast<Plugin*(*)(void*,std::intptr_t)>(dlsym(library,"CreatePlugInstance"));if(!create)return 4;
 std::array<void*,34> methods{};methods[0]=reinterpret_cast<void*>(&resize);methods[32]=reinterpret_cast<void*>(&lock);methods[33]=reinterpret_cast<void*>(&lock);
 Host h{};h.functions=methods.data();Plugin* p=create(&h,22);if(!p)return 5;
 auto* parent=[[NSView alloc]initWithFrame:NSMakeRect(0,0,500,300)];p->functions->dispatch(p,0,0,reinterpret_cast<std::intptr_t>((__bridge void*)parent));
 std::thread worker([&]{p->functions->tick(p);p->functions->midiTick(p);p->functions->idle(p);p->functions->destroy(p);});worker.join();
 const int before=h.resizes;p->functions->idle(p);const int after=h.resizes;
 p->functions->destroy(p);dlclose(library);
 std::cout<<"{\"worker_resizes\":"<<h.workerResizes<<",\"resizes_before_main_idle\":"<<before<<",\"resizes_after_main_idle\":"<<after<<"}\n";
 return h.workerResizes==0 && before==0 && after==1?0:1;
}}

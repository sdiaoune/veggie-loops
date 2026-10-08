// Reviewer-only inclusion exposes the private shutdown fence for its test.
// Compile this with Engine.cpp and Wrapper.cpp, not another StudioBridge.cpp.
#include "../../../Sources/VLNativeDSP/StudioBridge.cpp"
#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <future>
#include <iostream>
#include <thread>
#include <vector>

namespace {
std::atomic<int> allocationFailure{-1};
vl_native_oscillator* exitVoice=nullptr;
std::atomic<bool> stopExitWorker{false};
std::atomic<int> exitRejections{0};
std::thread* exitWorker=nullptr;
void require(bool value,const char* message){if(!value)throw std::runtime_error(message);}
std::vector<float> render(int note,int rate){
 auto* voice=vl_native_oscillator_create(note,rate);require(voice,"create");
 std::vector<float> result(4099,77);
 for(uint32_t offset=0;offset<4097;){
  const uint32_t count=std::min(1024u,4097u-offset);
  require(vl_native_oscillator_render(voice,result.data()+offset,count),"render");offset+=count;
 }
 vl_native_oscillator_destroy(voice);
 require(result[4097]==77 && result[4098]==77,"output guards");return result;
}
// This callback is registered before first bridge creation, so the later
// bridge shutdown fence must run before it, and raw namespace cleanup later.
void observeFencedExit(){
 if(!engineLifetime().shuttingDown || vl_native_oscillator_create(69,48000))std::abort();
 std::array<float,2> output{41,42};
 if(vl_native_oscillator_render(exitVoice,output.data(),1) || output!=std::array<float,2>{41,42})std::abort();
 vl_native_oscillator_destroy(exitVoice);stopExitWorker=true;exitWorker->join();delete exitWorker;
 std::fprintf(stdout,"{\"exit_fence_order\":true,\"worker_refused_after_fence\":true}\n");
}
}
void* operator new(std::size_t bytes){
 const int count=allocationFailure.load();
 if(count==0){allocationFailure=-1;throw std::bad_alloc();}
 if(count>0)--allocationFailure;
 if(void* result=std::malloc(bytes?bytes:1))return result;throw std::bad_alloc();
}
void operator delete(void* pointer)noexcept{std::free(pointer);}
void operator delete(void* pointer,std::size_t)noexcept{std::free(pointer);}
int main(int argc,char**){try{
 require(std::atexit(observeFencedExit)==0,"register observer");
 for(auto [note,rate]:std::array<std::pair<int,int>,4>{{{-1,48000},{128,48000},{69,7999},{69,192001}}})
  require(!vl_native_oscillator_create(note,rate),"invalid note/rate accepted");
 std::array<int,4> notes{0,69,72,127},rates{8000,44100,48000,192000};
 std::array<std::vector<float>,4> reference;
 for(size_t i=0;i<4;++i)reference[i]=render(notes[i],rates[i]);
 std::array<std::future<void>,8> jobs;
 for(size_t worker=0;worker<jobs.size();++worker)jobs[worker]=std::async(std::launch::async,[&,worker]{
  for(int pass=0;pass<8;++pass){const size_t index=(worker+pass)%4;require(render(notes[index],rates[index])==reference[index],"concurrent deterministic output");}
 });
 for(auto& job:jobs)job.get();
 size_t refused=0;
 for(int allocation=0;allocation<12;++allocation){
  allocationFailure=allocation;auto* value=vl_native_oscillator_create(69,48000);allocationFailure=-1;
  if(!value)++refused;else vl_native_oscillator_destroy(value);
  require(render(69,44100)==reference[1],"failed create contaminated next note");
 }
 exitVoice=vl_native_oscillator_create(69,48000);require(exitVoice,"exit voice");
 std::array<float,3> guard{41,42,43};
 require(!vl_native_oscillator_render(exitVoice,nullptr,1) && !vl_native_oscillator_render(exitVoice,guard.data(),1025),"invalid render arguments");
 require(vl_native_oscillator_render(exitVoice,guard.data(),0) && guard==std::array<float,3>{41,42,43},"zero frame mutation");
 if(argc>1){
  // Direct mode deterministically queues the fence behind an in-flight lock.
  std::unique_lock<std::mutex> active(engineLifetime().mutex);
  std::promise<void> attempting;auto arrived=attempting.get_future();
  auto fence=std::async(std::launch::async,[&]{attempting.set_value();fenceEngineShutdown();});arrived.get();
  require(!engineLifetime().shuttingDown,"fence bypassed active mutex");active.unlock();fence.get();
  require(engineLifetime().shuttingDown && !vl_native_oscillator_render(exitVoice,guard.data(),1),"fence failed to refuse render");
 }
 exitWorker=new std::thread([]{
  std::array<float,1024> output{};
  while(!stopExitWorker){if(!vl_native_oscillator_render(exitVoice,output.data(),1024))++exitRejections;}
 });
 std::cout<<"{\"status\":\"passed\",\"concurrent_voice_renders\":64,\"allocation_failure_points\":"<<refused<<",\"ordinary_voice_cleanup\":true,\"direct_fence\":"<<(argc>1?"true":"false")<<"}\n";
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';std::abort();}}

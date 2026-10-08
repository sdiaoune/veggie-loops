// Exercises only independent host code. No installed plugin is loaded.
#define main reference_probe_entry
#include "../common/vst2_probe.mm"
#undef main
#include <thread>

namespace {
std::array<int32_t,3> closing{};
size_t closingCount=0;
intptr_t closeDispatch(Effect*,int32_t code,int32_t,intptr_t,void*,float){
 if(closingCount<closing.size())closing[closingCount++]=code;return 0;
}
intptr_t suppliedChunkSize=0;
intptr_t chunkDispatch(Effect*,int32_t code,int32_t,intptr_t,void*,float){return code==23?suppliedChunkSize:0;}
bool chunkRejected(Effect& effect,intptr_t size){
 suppliedChunkSize=size;try{(void)chunk(&effect);return false;}catch(const std::runtime_error&){return true;}
}
}
int main(){try{
 for(const char* capability:{"receiveVstEvents","receiveVstMidiEvent"})
  require(host(nullptr,37,0,0,const_cast<char*>(capability),0)==0,"Unsupported receive capability advertised");
 for(const char* capability:{"sendVstEvents","sendVstMidiEvent"})
  require(host(nullptr,37,0,0,const_cast<char*>(capability),0)==1,"Input event capability absent");
 {
  Effect effect{};effect.dispatcher=closeDispatch;Instance instance;
  instance.value=&effect;instance.opened=instance.powered=instance.started=true;
 }
 require(closingCount==3 && closing==std::array<int32_t,3>{72,12,1},"Stop/power-off/close lifetime ordering");
 Effect fake{};fake.dispatcher=chunkDispatch;
 require(chunkRejected(fake,-1) && chunkRejected(fake,67108865),"Oversized/negative chunks accepted");
 suppliedChunkSize=0;require(chunk(&fake).empty(),"Empty chunk handling");
 for(auto& count:callbackCounts)count.store(0);otherCallbacks.store(0);
 {
  std::lock_guard<std::mutex> guard(transportMutex);transport.sampleRate=48000;transport.tempo=120;
 }
 std::array<std::thread,4> workers;
 for(auto& thread:workers)thread=std::thread([]{
  for(int i=0;i<10000;++i){
   auto* time=reinterpret_cast<const Time*>(host(nullptr,7,0,0,nullptr,0));
   if(!time || time->sampleRate!=48000 || time->tempo!=120)std::terminate();
   host(nullptr,-3,0,0,nullptr,0);
  }
 });
 for(auto& thread:workers)thread.join();
 require(callbackCounts[7].load()==40000 && otherCallbacks.load()==40000,"Concurrent callback accounting");
 std::cout<<"{\"status\":\"passed\",\"protocol_layout\":true,\"supported_event_claims\":true,\"lifetime_order\":true,\"chunk_bounds\":true,\"threaded_callback_count\":40000,\"native_plugin_loaded\":false}\n";
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}

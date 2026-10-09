#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_filter_routing.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>
using namespace veggie_loops::three_osc;
namespace {
void require(bool value,const char* message) {if(!value)throw std::runtime_error(message);}
std::string hashFile(const char* path) {
  std::ifstream file(path,std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
  std::array<unsigned char,32> bytes;CC_SHA256(image.data(),static_cast<CC_LONG>(image.size()),bytes.data());
  std::ostringstream out;for(auto byte:bytes)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
template<class T>void store(void* target,size_t offset,T value) {std::memcpy(static_cast<char*>(target)+offset,&value,sizeof(value));}
float bounded(std::mt19937& random,float scale) {return float(int(random()%20001)-10000)*scale;}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_filter_routing <native wrapper> <rebuilt module>");
    require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No native base");auto base=static_cast<char*>(info.dli_fbase);
    auto nativeRate=reinterpret_cast<void(*)(int)>(base+0x6d990);
    auto original=reinterpret_cast<uint8_t(*)(void*,float*,float*)>(base+0x1bcd60);
    auto model=reinterpret_cast<uint8_t(*)(filter_routing::State*,const filter_routing::Inputs*,const filter::Context*,const float*,float*,int,float*,float*)>(dlsym(rebuilt,"vl_osc_filter_route"));require(model,"Missing rebuilt route export");
    std::mt19937 random(0x96dc9);size_t calls=0,values=0,active=0,inactive=0;double maximumHistory=0;
    const std::array<int,6> rates{8000,22050,44100,48000,96000,384000};
    const std::array<int,10> lengths{1,2,3,7,8,15,63,441,1024,4096};
    for(int fixture=0;fixture<1200;++fixture) {
      const int rate=rates[fixture%rates.size()];nativeRate(rate);const auto ctx=filter::context(rate);
      filter_routing::State state{};state.coefficients.type=fixture%8;state.doubleOrder=uint8_t((fixture/8)%2);state.active=state.coefficients.type>0;
      alignas(16) std::array<std::byte,416> voice{};std::memcpy(voice.data()+0x108,&state,sizeof(state));
      alignas(16) std::array<std::byte,840> config{};
      alignas(16) std::array<std::byte,64> context{};store<void*>(context.data(),0x10,config.data());store<void*>(voice.data(),0x48,context.data());
      alignas(16) std::array<std::byte,64> buffers{};store<void*>(context.data(),0x18,buffers.data());
      std::array<float,10> parameters{};store<void*>(voice.data(),0x180,parameters.data());
      for(int block=0;block<12;++block) {
        filter_routing::Inputs inputs;inputs.rawCutoff=int(random()%257);inputs.rawResonance=int(random()%257);
        inputs.finalCutoff=bounded(random,0.00005f);inputs.finalResonance=bounded(random,0.00005f);
        inputs.cutoffModulation=bounded(random,0.000025f);inputs.resonanceModulation=bounded(random,0.000025f);
        if(state.coefficients.type==0 && block%4==0)inputs={0,0,0,0,256,0};
        if(block==2)inputs={-2,-2,0,0,0,0};
        if(block==5)inputs={1,1,0,0,256,256};
        if(block==8)inputs={-1,-1,-1,-1,0,0};
        if(block==10)inputs={0.75f,0.75f,0.25f,0.25f,256,256};
        const int frames=lengths[(fixture+block)%lengths.size()];
        std::vector<float> source(size_t(frames)*2+16,1234.5f),a(source.size(),-4321.25f),b=a;
        for(int i=0;i<frames*2;++i)source[size_t(i)+8]=bounded(random,0.0001f);const auto unchanged=source;
        parameters[8]=inputs.finalCutoff;parameters[9]=inputs.finalResonance;
        store<float>(voice.data(),0xb8,inputs.cutoffModulation);store<float>(voice.data(),0xdc,inputs.resonanceModulation);
        store<int>(config.data(),0x328,inputs.rawCutoff);store<int>(config.data(),0x32c,inputs.rawResonance);
        state.initializerCounter=block==0 ? 1:0;store<int>(voice.data(),0x174,state.initializerCounter);
        store<const float*>(buffers.data(),0x18,source.data()+8);store<float*>(buffers.data(),0x28,a.data()+8);store<int>(buffers.data(),0x30,frames);
        std::array<float,2> ga{bounded(random,0.0001f),bounded(random,0.0001f)},gb=ga;
        const uint8_t aa=original(voice.data(),&ga[0],&ga[1]);const uint8_t bb=model(&state,&inputs,&ctx,source.data()+8,b.data()+8,frames,&gb[0],&gb[1]);
        if(aa!=bb || std::memcmp(voice.data()+0x108,&state,sizeof(state))!=0 || std::memcmp(a.data(),b.data(),a.size()*4)!=0 || std::memcmp(ga.data(),gb.data(),8)!=0) {
          std::cerr<<"route fixture="<<fixture<<" type="<<state.coefficients.type<<" double="<<int(state.doubleOrder)<<" block="<<block<<" frames="<<frames<<'\n';
          throw std::runtime_error("Filter routing output/state differs");
        }
        for(int j=0;j<8;++j)require(a[size_t(j)]==-4321.25f && a[size_t(frames)*2+8+size_t(j)]==-4321.25f,"Routing output guard overwritten");
        require(std::memcmp(source.data(),unchanged.data(),source.size()*4)==0,"Routing source modified");
        if(state.coefficients.type==0)for(auto value:state.coefficients.single)maximumHistory=std::max(maximumHistory,std::fabs(value));
        else {std::array<float,8> history;std::memcpy(history.data(),state.coefficients.single.data(),32);for(auto value:history)maximumHistory=std::max(maximumHistory,double(std::fabs(value)));}
        for(auto value:state.secondPass)maximumHistory=std::max(maximumHistory,double(std::fabs(value)));
        ++calls;values+=size_t(frames)*2+31;if(aa)++active;else++inactive;
      }
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"prepared_routing_fixtures\":1200,\"route_calls\":"<<calls<<",\"exact_float_state_gain_values\":"<<values
             <<",\"active_calls\":"<<active<<",\"inactive_calls\":"<<inactive<<",\"maximum_observed_history_magnitude\":"<<maximumHistory
             <<",\"combined_control_boundaries_tested\":true,\"filter_types\":8,\"one_and_two_passes\":true,\"native_factory_or_host_routing_rebuilt\":false,\"audio_voice_pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

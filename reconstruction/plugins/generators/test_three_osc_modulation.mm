#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_modulation.hpp"
#include "three_osc_envelope_coefficients.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <bit>
#include <cmath>
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
template<class T>T load(const void* target,size_t offset) {T value;std::memcpy(&value,static_cast<const char*>(target)+offset,sizeof(value));return value;}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_modulation <native wrapper> <rebuilt module>");
    require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No native base");auto base=static_cast<char*>(info.dli_fbase);
    auto originalStep=reinterpret_cast<void(*)(void*)>(base+0x1bd0f0);
    auto originalRelease=reinterpret_cast<void(*)(void*,const void*)>(base+0x1bd2a0);
    auto originalTick=reinterpret_cast<void(*)(void*,int)>(base+0x1bcb40);
    auto modelStep=reinterpret_cast<void(*)(const modulation::Configurations*,modulation::State*)>(dlsym(rebuilt,"vl_osc_modulation_step"));
    auto modelRelease=reinterpret_cast<void(*)(const modulation::Configurations*,modulation::State*)>(dlsym(rebuilt,"vl_osc_modulation_release"));
    auto modelTick=reinterpret_cast<void(*)(const modulation::Configurations*,modulation::State*,int,int,float*)>(dlsym(rebuilt,"vl_osc_modulation_tick_pitch"));
    require(modelStep && modelRelease && modelTick,"Missing rebuilt exports");
    std::array<float,16384> table;for(size_t i=0;i<table.size();++i)table[i]=std::sin(float(i)*0.0003834952f);
    const std::array<const float*,3> tablePointers{table.data(),table.data(),table.data()};
    std::mt19937 random(0x146535);size_t steps=0,releases=0,pitches=0,words=0;
    for(int fixture=0;fixture<1800;++fixture) {
      modulation::Configurations cfg;
      for(auto& group:cfg) {
        group.raw={int(random()%64),int(random()%2),100,100+int(random()%15000),100,100+int(random()%20000),int(random()%129),100+int(random()%18000),int(random()%257)-128,100,100+int(random()%15000),int(random()%257)-128,5000+int(random()%40000),int(random()%3),int(random()%257)-128,int(random()%257)-128,int(random()%257)-128};
        envelope::prepareConfiguration(group,120.0,240,tablePointers);
      }
      modulation::State state;modulation::initialize(cfg,state);state.waitFrames=int(random()%64);
      alignas(16) std::array<std::byte,808> nativeCfg{};std::memcpy(nativeCfg.data()+8,cfg.data(),800);
      alignas(16) std::array<std::byte,64> context{};store<void*>(context.data(),0x10,nativeCfg.data());
      alignas(16) std::array<std::byte,416> voice{};store<void*>(voice.data(),0x48,context.data());
      std::memcpy(voice.data()+0x50,state.groups.data(),180);store<int>(voice.data(),0xc,state.declickPosition);store<int>(voice.data(),0x10,state.waitFrames);
      alignas(16) std::array<float,10> finalParameters{};store<void*>(voice.data(),0x180,finalParameters.data());
      const auto compare=[&] {
        if(std::memcmp(voice.data()+0x50,state.groups.data(),180)!=0) {std::cerr<<"fixture="<<fixture<<'\n';throw std::runtime_error("Five-group modulation state differs");}
        require(load<int>(voice.data(),0xc)==state.declickPosition && load<int>(voice.data(),0x10)==state.waitFrames && load<uint8_t>(voice.data(),0x178)==state.released,"Modulation release state differs");words+=48;
      };
      for(int tick=0;tick<180;++tick) {
        if(tick==fixture%90 || tick==135) {originalRelease(voice.data(),cfg.data());modelRelease(&cfg,&state);compare();++releases;}
        if(tick%3==0) {originalStep(voice.data());modelStep(&cfg,&state);compare();++steps;}
        else {
          const int newTick=int(random()%2),counter=tick<5 ? int(random()%3):0;store<int>(voice.data(),0x174,counter);
          float pitch=float(int(random()%12001)-6000);finalParameters[7]=pitch;
          originalTick(voice.data(),newTick);modelTick(&cfg,&state,newTick,counter,&pitch);compare();
          require(std::bit_cast<uint32_t>(finalParameters[7])==std::bit_cast<uint32_t>(pitch),"Pitch update differs");++pitches;++words;
        }
      }
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"prepared_five_group_fixtures\":1800,\"direct_tick_steps\":"<<steps
             <<",\"release_calls\":"<<releases<<",\"conditional_pitch_ticks\":"<<pitches<<",\"exact_state_values\":"<<words
             <<",\"host_tick_production_rebuilt\":false,\"audio_pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_envelope.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>
#include <cstring>
#include <vector>
using namespace veggie_loops::three_osc::envelope;
namespace {
void require(bool value,const char* message) {if (!value) throw std::runtime_error(message);}
template<class T>T symbol(void* library,const char* name) {
  auto result=reinterpret_cast<T>(dlsym(library,name));require(result,"Missing rebuilt export");return result;
}
std::string hash(const void* value,size_t length) {
  std::array<unsigned char,32> bytes;CC_SHA256(value,static_cast<CC_LONG>(length),bytes.data());
  std::ostringstream output;for (auto byte:bytes) output<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return output.str();
}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_envelope <native wrapper> <rebuilt envelope dylib>");
    std::ifstream file(argv[1],std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
    require(hash(image.data(),image.size())=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Unreviewed source wrapper");
    [NSApplication sharedApplication];
    void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Cannot load reviewed native wrapper");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Cannot load rebuilt envelope primitive");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No wrapper image base");
    auto base=static_cast<char*>(info.dli_fbase);
    using Prepare=void(*)(Curve*,float);using Raw=void(*)(Curve*,int);
    using Initialize=void(*)(State*,const Configuration*);using Step=void(*)(const Configuration*,State*);
    const auto originalPrepare=reinterpret_cast<Prepare>(base+0x173b80),modelPrepare=symbol<Prepare>(rebuilt,"vl_osc_envelope_prepare_curve");
    const auto originalRaw=reinterpret_cast<Raw>(base+0x1c1a10),modelRaw=symbol<Raw>(rebuilt,"vl_osc_envelope_prepare_raw_curve");
    const auto originalInitialize=reinterpret_cast<Initialize>(base+0x1c1fd0),modelInitialize=symbol<Initialize>(rebuilt,"vl_osc_envelope_initialize");
    const auto originalRelease=reinterpret_cast<Initialize>(base+0x1c1ed0),modelRelease=symbol<Initialize>(rebuilt,"vl_osc_envelope_release");
    const auto originalStep=reinterpret_cast<Step>(base+0x1c1470),modelStep=symbol<Step>(rebuilt,"vl_osc_envelope_step");
    std::array<float,16384> table;for (size_t i=0;i<table.size();++i) table[i]=std::sin(float(i)*0.0003834952f);
    std::mt19937 random(0xa630u);size_t curves=0,initializations=0,releaseCases=0,stepCases=0;
    const auto equal=[&](const State& original,const State& model,int fixture,int tick) {
      if (std::memcmp(&original,&model,sizeof(State))) {
        std::array<uint32_t,9> a,b;std::memcpy(a.data(),&original,36);std::memcpy(b.data(),&model,36);
        for (int i=0;i<9;++i) if (a[i]!=b[i]) std::cerr<<"fixture="<<fixture<<" tick="<<tick<<" word="<<i<<" native="<<std::hex<<a[i]<<" rebuilt="<<b[i]<<std::dec<<'\n';
        throw std::runtime_error("Envelope/LFO state differs");
      }
    };
    for (int i=-512;i<=512;++i) {
      Curve original{1,0.125f,0.375f},model=original;
      originalRaw(&original,i);modelRaw(&model,i);require(std::memcmp(&original,&model,12)==0,"Raw curve preparation differs");++curves;
      const float amount=float(i)*0.125f;originalPrepare(&original,amount);modelPrepare(&model,amount);
      require(std::memcmp(&original,&model,12)==0,"Curve preparation differs");++curves;
    }
    for (int fixture=0;fixture<1200;++fixture) {
      Configuration cfg;cfg.raw[0]=int(random()%64);cfg.raw[1]=fixture%9!=0;
      cfg.raw[3]=fixture%7==0 ? 100 : 20000;
      cfg.attackStep=1.0f/float(1+random()%45);cfg.decayStep=-1.0f/float(1+random()%75);
      cfg.releaseStep=-1.0f/float(1+random()%60);cfg.sustain=float(random()%129)/128.0f;
      cfg.delayTicks=int(random()%4);cfg.holdTicks=int(random()%5);cfg.lfoDelayTicks=int(random()%7);
      cfg.lfoAttackStep=1.0f/float(1+random()%40);cfg.lfoPhaseIncrement=random();cfg.synchronizedLFOPhase=random();cfg.lfoTable=table.data();
      for (auto* curve:{&cfg.attack,&cfg.decay,&cfg.release}) prepareRawCurve(*curve,int(random()%257)-128);
      State original{},model{};originalInitialize(&original,&cfg);modelInitialize(&model,&cfg);equal(original,model,fixture,-1);++initializations;
      for (int tick=0;tick<260;++tick) {
        if (tick==fixture%150 || tick==201) {originalRelease(&original,&cfg);modelRelease(&model,&cfg);equal(original,model,fixture,tick);++releaseCases;}
        if (tick==170) {cfg.raw[1]^=1;cfg.raw[0]^=32;}
        originalStep(&cfg,&original);modelStep(&cfg,&model);equal(original,model,fixture,tick);++stepCases;
      }
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"curve_preparation_cases\":"<<curves
             <<",\"initialized_states\":"<<initializations<<",\"release_cases\":"<<releaseCases<<",\"envelope_lfo_tick_cases\":"<<stepCases
             <<",\"state_words_compared\":"<<(initializations+releaseCases+stepCases)*9
             <<",\"wrapper_pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

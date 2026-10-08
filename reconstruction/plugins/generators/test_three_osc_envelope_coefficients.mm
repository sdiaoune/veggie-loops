#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_envelope_coefficients.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>
using namespace veggie_loops::three_osc::envelope;
namespace {
void require(bool value,const char* message) {if (!value) throw std::runtime_error(message);}
std::string hash(const void* value,size_t length) {
  std::array<unsigned char,32> bytes;CC_SHA256(value,static_cast<CC_LONG>(length),bytes.data());
  std::ostringstream out;for(auto byte:bytes) out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_envelope_coefficients <native wrapper> <rebuilt coefficients dylib>");
    std::ifstream file(argv[1],std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
    require(hash(image.data(),image.size())=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Native identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No source image base");
    auto base=static_cast<char*>(info.dli_fbase);
    auto setTempo=reinterpret_cast<void(*)(double)>(base+0x1c13a0);
    auto setClock=reinterpret_cast<void(*)(uint32_t)>(base+0x1c13c0);
    auto originalPrepare=reinterpret_cast<void(*)(Configuration*)>(base+0x1c1ac0);
    auto modelPrepare=reinterpret_cast<void(*)(Configuration*,double,uint32_t,const float* const*)>(dlsym(rebuilt,"vl_osc_envelope_prepare_configuration"));
    require(modelPrepare,"Missing compiled counterpart");
    std::array<const float*,3> tables;std::memcpy(tables.data(),base+0x263020,24);
    std::mt19937 random(0xece125u);size_t cases=0;
    for(int i=0;i<3600;++i) {
      Configuration original{},model{};
      original.raw[0]=int(random()%256);original.raw[1]=i%2;
      for(int index:{2,3,4,5,7,9,10,12}) original.raw[index]=i%9==0 ? 100 : int(random()%65537);
      original.raw[6]=int(random()%129);original.raw[8]=int(random()%4801)-2400;
      original.raw[11]=int(random()%4801)-2400;original.raw[13]=int(random()%7)-2;
      for(int index:{14,15,16}) original.raw[index]=int(random()%257)-128;
      original.synchronizedLFOPhase=random();model=original;
      const double tempo=double(20+random()%981);
      const uint32_t setting=std::array<uint32_t,8>{4,48,96,240,1024,4096,65536,1048576}[i%8];
      setTempo(tempo);setClock(setting);originalPrepare(&original);modelPrepare(&model,tempo,setting,tables.data());
      if(std::memcmp(&original,&model,160)) {
        std::array<uint32_t,40> a,b;std::memcpy(a.data(),&original,160);std::memcpy(b.data(),&model,160);
        for(int word=0;word<40;++word) if(a[word]!=b[word]) std::cerr<<"case="<<i<<" word="<<word<<" native="<<std::hex<<a[word]<<" rebuilt="<<b[word]<<std::dec<<'\n';
        throw std::runtime_error("Native prepared envelope coefficients differ");
      }
      ++cases;
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"prepared_configuration_cases\":"<<cases
             <<",\"configuration_words_exact\":"<<cases*40<<",\"clock_settings\":8,\"host_tick_semantics_reconstructed\":false,\"wrapper_pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

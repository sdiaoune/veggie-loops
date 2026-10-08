#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_voice_output.hpp"
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
namespace {
void require(bool value,const char* message) {if(!value) throw std::runtime_error(message);}
std::string hash(const void* value,size_t length) {
  std::array<unsigned char,32> bytes;CC_SHA256(value,static_cast<CC_LONG>(length),bytes.data());
  std::ostringstream out;for(auto byte:bytes) out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
template<class T>T load(const void* pointer,size_t offset) {T value;std::memcpy(&value,static_cast<const char*>(pointer)+offset,sizeof(value));return value;}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_voice_output <native wrapper> <rebuilt output primitives>");
    std::ifstream file(argv[1],std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
    require(hash(image.data(),image.size())=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Source identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No native base");auto base=static_cast<char*>(info.dli_fbase);
    auto originalGains=reinterpret_cast<void(*)(float,float,float*,float*)>(base+0x6ef40);
    auto originalLinear=reinterpret_cast<void(*)(float,float,float*,float*)>(base+0x6eec0);
    auto originalSlew=reinterpret_cast<void(*)(float,float,float*,float*,int)>(base+0x6edf0);
    auto modelGains=reinterpret_cast<void(*)(float,float,int,float,float*,float*)>(dlsym(rebuilt,"vl_osc_voice_gains"));
    auto modelSlew=reinterpret_cast<void(*)(float,float,uint32_t,int,float*,float*)>(dlsym(rebuilt,"vl_osc_voice_slew"));
    require(modelGains && modelSlew,"Missing compiled primitives");
    const int law=load<int>(base,0x289ca8);const float compensation=load<float>(base,0x289cb0);const auto threshold=load<uint32_t>(base,0x289cb4);
    require(law==0,"Unreviewed active native pan mode");std::mt19937 random(0x77842);size_t panCases=0,slewCases=0;
    for(int i=0;i<60000;++i) {
      const float pan=i%13==0 ? std::array<float,4>{-1.0f,-0.0f,0.0f,1.0f}[i%4] : float(int(random()%60001)-30000)/10000.0f;
      const float volume=float(int(random()%40001)-20000)/10000.0f;
      std::array<float,2> a,b;originalGains(pan,volume,&a[0],&a[1]);modelGains(pan,volume,law,compensation,&b[0],&b[1]);
      require(std::memcmp(a.data(),b.data(),8)==0,"Circular pan differs");++panCases;
      const float clamped=std::max(-1.0f,std::min(pan,1.0f));originalLinear(clamped,volume*compensation,&a[0],&a[1]);modelGains(pan,volume,1,compensation,&b[0],&b[1]);
      require(std::memcmp(a.data(),b.data(),8)==0,"Linear pan primitive differs");++panCases;
      float previous=float(int(random()%40001)-20000)/10000.0f;
      float target=float(int(random()%40001)-20000)/10000.0f;
      float maximum=std::array<float,4>{0.00001f,0.001f,0.01f,0.1f}[i%4];int frames=1+int(random()%4096);
      if(i%17==0) {previous=6e-8f;target=-0.0001f;maximum=1e-8f;frames=1;}
      if(i%19==0) {previous=0.0f;target=-0.0f;}
      float nativeStep,modelStep,nativeTarget=target,modelTarget=target;
      originalSlew(previous,maximum,&nativeStep,&nativeTarget,frames);modelSlew(previous,maximum,threshold,frames,&modelStep,&modelTarget);
      require(std::bit_cast<uint32_t>(nativeStep)==std::bit_cast<uint32_t>(modelStep) &&
              std::bit_cast<uint32_t>(nativeTarget)==std::bit_cast<uint32_t>(modelTarget),"Gain slew differs");++slewCases;
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"pan_cases\":"<<panCases<<",\"slew_cases\":"<<slewCases
             <<",\"circular_whole_helper_verified\":true,\"linear_primitive_with_observed_compensation_verified\":true,\"pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

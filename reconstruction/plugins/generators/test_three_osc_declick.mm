#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_declick.hpp"
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
void require(bool value,const char* message) {if(!value) throw std::runtime_error(message);}
std::string hash(const void* value,size_t length) {
  std::array<unsigned char,32> bytes;CC_SHA256(value,static_cast<CC_LONG>(length),bytes.data());
  std::ostringstream out;for(auto byte:bytes) out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
template<class T>void store(void* target,size_t offset,T value) {std::memcpy(static_cast<char*>(target)+offset,&value,sizeof(value));}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_declick <native wrapper> <rebuilt module>");
    std::ifstream file(argv[1],std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
    require(hash(image.data(),image.size())=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Source identity mismatch");
    std::ifstream dependency("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib",std::ios::binary);
    std::vector<char> dependencyImage{std::istreambuf_iterator<char>(dependency),{}};
    require(hash(dependencyImage.data(),dependencyImage.size())=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Native vector dependency identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No native base");auto base=static_cast<char*>(info.dli_fbase);
    using NativeGenerate=void(*)(float,float,float,int,int,float*,int);
    using ModelGenerate=void(*)(const envelope::Curve*,int,int,int,int,float*,int);
    using NativeApply=void(*)(void*,void*,float*,int);
    using ModelApply=void(*)(const float*,int,declick::ReleaseState*,float*,int);
    auto cosine=reinterpret_cast<NativeGenerate>(base+0x1c2480),linear=reinterpret_cast<NativeGenerate>(base+0x1c2610);
    auto generate=reinterpret_cast<ModelGenerate>(dlsym(rebuilt,"vl_osc_declick_generate"));
    auto nativeApply=reinterpret_cast<NativeApply>(base+0x1c3100);
    auto apply=reinterpret_cast<ModelApply>(dlsym(rebuilt,"vl_osc_declick_release"));require(generate && apply,"Missing rebuilt entry points");
    std::mt19937 random(0x5712);size_t generated=0,releaseCases=0,words=0;
    for(int i=0;i<10000;++i) {
      const int total=64+int(random()%65473),offset=int(random()%uint32_t(total-63)),direction=i%2,shape=3+((i/2)%2);
      envelope::Curve curve{};envelope::prepareCurve(curve,i%9==0 ? 0.0f : float(int(random()%1025)-512)*0.125f);
      alignas(16) std::array<float,72> a,b;a.fill(-999);b=a;
      (shape==3 ? cosine:linear)(curve.amount,curve.inverse,curve.logarithm,direction,offset,a.data()+4,total);
      generate(&curve,shape,direction,offset,total,b.data()+4,64);
      if(std::memcmp(a.data(),b.data(),sizeof(a))!=0) {
        std::cerr<<"table fixture="<<i<<" shape="<<shape<<" direction="<<direction<<" curve="<<curve.amount<<'\n';
        for(int j=0;j<72;++j) if(std::bit_cast<uint32_t>(a[j])!=std::bit_cast<uint32_t>(b[j])) {std::cerr<<"lane="<<j<<" native="<<std::hex<<std::bit_cast<uint32_t>(a[j])<<" model="<<std::bit_cast<uint32_t>(b[j])<<std::dec<<'\n';break;}
        throw std::runtime_error("Prepared declick table differs");
      }
      ++generated;words+=64;
    }
    for(int i=0;i<6000;++i) {
      const int count=1+int(random()%2048),frames=int(random()%4097);
      std::vector<float> table(static_cast<size_t>(count)),a(size_t(frames)*2+16),b;
      envelope::Curve curve{};generate(&curve,3,1,0,count,table.data(),count);
      for(auto& value:a)value=float(int(random()%20001)-10000)/10000.0f;b=a;
      declick::ReleaseState state{i%11==0 ? -1:int(random()%uint32_t(count+2048)),i%7==0 ? int(random()%5000):0};
      alignas(16) std::array<std::byte,128> config{};
      store<uint8_t>(config.data(),8,0);store<uint8_t>(config.data(),0x38,3);
      store<int>(config.data(),0x3c,count);store<const float*>(config.data(),0x58,table.data());
      std::array<int32_t,13> nativeState{};nativeState[0]=INT32_MAX;nativeState[1]=state.position;nativeState[2]=state.waitFrames;
      nativeApply(config.data(),nativeState.data(),a.data()+8,frames);apply(table.data(),count,&state,b.data()+8,frames);
      require(std::memcmp(a.data(),b.data(),a.size()*4)==0,"Release audio differs");
      require(nativeState[1]==state.position && nativeState[2]==state.waitFrames,"Release position differs");
      ++releaseCases;words+=size_t(frames)*2+2;
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"prepared_64_frame_tables\":"<<generated
             <<",\"precomputed_release_cases\":"<<releaseCases<<",\"exact_float_and_state_words\":"<<words
             <<",\"uses_system_accelerate\":true,\"dynamic_cache_rebuilt\":false,\"pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

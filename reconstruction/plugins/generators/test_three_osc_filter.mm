#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_filter.hpp"
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
using namespace veggie_loops::three_osc::filter;
namespace {
void require(bool value,const char* message) {if(!value)throw std::runtime_error(message);}
std::string hashFile(const char* path) {
  std::ifstream file(path,std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
  std::array<unsigned char,32> bytes;CC_SHA256(image.data(),static_cast<CC_LONG>(image.size()),bytes.data());
  std::ostringstream out;for(auto byte:bytes)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
template<class T>T load(const void* pointer,size_t offset) {T value;std::memcpy(&value,static_cast<const char*>(pointer)+offset,sizeof(value));return value;}
template<class T>T symbol(void* library,const char* name) {auto result=reinterpret_cast<T>(dlsym(library,name));require(result,"Missing rebuilt export");return result;}
float bounded(std::mt19937& random) {return float(int(random()%20001)-10000)*0.0001f;}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_filter <native wrapper> <rebuilt module>");
    require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No native base");auto base=static_cast<char*>(info.dli_fbase);
    const Context defaults;
    require(load<uint32_t>(base,0x289ce8)==std::bit_cast<uint32_t>(defaults.singleExponent) &&
            load<uint32_t>(base,0x2f3370)==std::bit_cast<uint32_t>(defaults.biquadFrequencyExponent) &&
            load<uint32_t>(base,0x2f3374)==std::bit_cast<uint32_t>(defaults.biquadResonanceExponent) &&
            load<uint32_t>(base,0x258964)==std::bit_cast<uint32_t>(defaults.silenceThreshold),"Unreviewed initialized native coefficient context");
    using NativeCoefficients=void(*)(float,float,Coefficients*);
    using ModelCoefficients=void(*)(float,float,const Context*,Coefficients*);
    auto nativeRate=reinterpret_cast<void(*)(int)>(base+0x6d990);
    const std::array<NativeCoefficients,3> originals{reinterpret_cast<NativeCoefficients>(base+0x708d0),reinterpret_cast<NativeCoefficients>(base+0x706f0),reinterpret_cast<NativeCoefficients>(base+0x70a80)};
    const std::array<ModelCoefficients,3> models{symbol<ModelCoefficients>(rebuilt,"vl_osc_filter_single_coefficients"),symbol<ModelCoefficients>(rebuilt,"vl_osc_filter_biquad_coefficients"),symbol<ModelCoefficients>(rebuilt,"vl_osc_filter_special_coefficients")};
    auto nativeSingle=reinterpret_cast<void(*)(float,float,Coefficients*,const float*,float*,int)>(base+0x6dc00);
    auto nativeBiquad=reinterpret_cast<void(*)(const Coefficients*,std::array<float,8>*,const float*,float*,int)>(base+0x70bc0);
    auto nativeSpecial=reinterpret_cast<void(*)(const Coefficients*,std::array<float,8>*,const float*,float*,int)>(base+0x70d70);
    auto modelSingle=symbol<void(*)(float,float,Coefficients*,const Context*,const float*,float*,int)>(rebuilt,"vl_osc_filter_single_render");
    auto modelBiquad=symbol<decltype(nativeBiquad)>(rebuilt,"vl_osc_filter_biquad_render");
    auto modelSpecial=symbol<void(*)(const Coefficients*,std::array<float,8>*,const Context*,const float*,float*,int)>(rebuilt,"vl_osc_filter_special_render");
    std::mt19937 random(0x803592);size_t coefficientCases=0,renderCases=0,values=0;
    const std::array<int,7> rates{8000,22050,44100,48000,88200,96000,384000};
    const std::array<int,14> lengths{0,1,2,3,7,8,9,15,16,31,63,441,1024,4096};
    for(int fixture=0;fixture<18000;++fixture) {
      const int rate=rates[fixture%rates.size()];nativeRate(rate);const auto ctx=context(rate);
      require(std::bit_cast<uint32_t>(ctx.rateRatio)==load<uint32_t>(base,0x258930),"Native rate ratio differs");
      const float cutoff=fixture%17==0 ? std::array<float,5>{-1,-0.0f,0,1,2}[fixture%5]:2*bounded(random);
      const float resonance=fixture%19==0 ? std::array<float,5>{-1,-0.0f,0,1,2}[fixture%5]:2*bounded(random);
      const int frames=lengths[fixture%lengths.size()];
      std::vector<float> source(size_t(frames)*2+16,0),a(source.size(),1234.5f),b=a;
      for(auto& sample:source)sample=bounded(random);const auto savedSource=source;
      for(int family=0;family<3;++family) {
        Coefficients ca{},cb{};ca.type=family==1 ? 1+fixture%5:family==2 ? 6+fixture%2:0;ca.unused=0.123f;ca.padding=-0.456f;
        for(auto& value:ca.biquad)value=bounded(random);for(auto& value:ca.single)value=double(bounded(random));cb=ca;
        originals[family](cutoff,resonance,&ca);models[family](cutoff,resonance,&ctx,&cb);
        if(std::memcmp(&ca,&cb,sizeof(ca))!=0) {std::cerr<<"coefficient fixture="<<fixture<<" family="<<family<<" type="<<ca.type<<'\n';throw std::runtime_error("Filter coefficients differ");}
        ++coefficientCases;values+=18;
        // Render preparation uses a stable narrower normalized domain.
        originals[family](float(random()%10001)*0.0001f,float(random()%10001)*0.0001f,&ca);cb=ca;
        if(fixture%29==0)for(auto& value:ca.single)value=0x1p-26;cb.single=ca.single;
        std::array<float,8> sa,sb;for(auto& value:sa)value=bounded(random);if(fixture%31==0)sa.fill(-0x1p-26f);sb=sa;
        a.assign(source.size(),1234.5f);b=a;
        const bool inPlace=fixture%4==0;
        if(inPlace) {std::copy(source.begin()+8,source.begin()+8+frames*2,a.begin()+8);b=a;}
        const float* nativeInput=inPlace ? a.data()+8:source.data()+8;
        const float* modelInput=inPlace ? b.data()+8:source.data()+8;
        if(family==0) {
          const float start=ca.cutoff;
          const float target=float(random()%10001)*0.0001f;
          const float increment=frames ? (target-start)/float(frames):0;
          nativeSingle(start,increment,&ca,nativeInput,a.data()+8,frames);modelSingle(start,increment,&cb,&ctx,modelInput,b.data()+8,frames);
        } else if(family==1) {nativeBiquad(&ca,&sa,nativeInput,a.data()+8,frames);modelBiquad(&cb,&sb,modelInput,b.data()+8,frames);}
        else {nativeSpecial(&ca,&sa,nativeInput,a.data()+8,frames);modelSpecial(&cb,&sb,&ctx,modelInput,b.data()+8,frames);}
        if(std::memcmp(a.data(),b.data(),a.size()*4)!=0 || std::memcmp(&ca,&cb,sizeof(ca))!=0 || std::memcmp(sa.data(),sb.data(),32)!=0) {
          std::cerr<<"render fixture="<<fixture<<" family="<<family<<" type="<<ca.type<<" frames="<<frames<<'\n';throw std::runtime_error("Filter render/state differs");
        }
        for(int j=0;j<8;++j)require(a[size_t(j)]==1234.5f && a[size_t(frames)*2+8+size_t(j)]==1234.5f,"Filter output guard overwritten");
        require(std::memcmp(source.data(),savedSource.data(),source.size()*4)==0,"Filter source modified");
        ++renderCases;values+=size_t(frames)*2+26;
      }
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"coefficient_cases\":"<<coefficientCases<<",\"filter_render_cases\":"<<renderCases
             <<",\"exact_float_state_values\":"<<values<<",\"rate_contexts\":7,\"kernel_families\":3,\"in_place_and_disjoint\":true,\"audio_pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

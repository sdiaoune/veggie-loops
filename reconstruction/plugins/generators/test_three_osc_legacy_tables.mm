#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_legacy_tables.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <bit>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <vector>
namespace {
void require(bool value,const char* message) {if(!value) throw std::runtime_error(message);}
std::string hash(const void* value,size_t length) {
  std::array<unsigned char,32> bytes;CC_SHA256(value,static_cast<CC_LONG>(length),bytes.data());
  std::ostringstream out;for(auto byte:bytes) out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_legacy_tables <native wrapper> <rebuilt tables dylib>");
    std::ifstream file(argv[1],std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
    require(hash(image.data(),image.size())=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Native identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Cannot load reviewed wrapper");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Cannot load rebuilt table generator");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No native base");
    auto generate=reinterpret_cast<void(*)(float*)>(dlsym(rebuilt,"vl_osc_generate_legacy_tables"));require(generate,"Missing compiled generator");
    const auto* original=reinterpret_cast<const float*>(static_cast<const char*>(info.dli_fbase)+0x291eb0);
    std::vector<float> output(6*16384);generate(output.data());
    for(size_t i=0;i<output.size();++i) if(std::bit_cast<uint32_t>(output[i])!=std::bit_cast<uint32_t>(original[i])) {
      std::cerr<<"wave="<<i/16384<<" index="<<i%16384<<" native="<<std::setprecision(9)<<original[i]<<" compiled="<<output[i]<<'\n';
      throw std::runtime_error("Legacy waveform bank differs");
    }
    auto seedOriginal=reinterpret_cast<void(*)(void*,uint32_t)>(static_cast<char*>(info.dli_fbase)+0x1c3c80);
    auto nextOriginal=reinterpret_cast<uint32_t(*)(void*)>(static_cast<char*>(info.dli_fbase)+0x1c3e50);
    auto generateNoise=reinterpret_cast<void(*)(uint32_t,uint32_t,uint32_t*)>(dlsym(rebuilt,"vl_osc_generate_legacy_noise"));require(generateNoise,"No compiled noise helper");
    constexpr std::array<uint32_t,9> seeds{0,1,5489,19650218,0x80000000u,0xffffffffu,624,226,314159265};
    std::vector<uint32_t> numbers(9000);
    for(auto seed:seeds) {
      alignas(16) std::array<std::byte,0x9d0> object{};seedOriginal(object.data(),seed);generateNoise(seed,uint32_t(numbers.size()),numbers.data());
      for(size_t i=0;i<numbers.size();++i) require(nextOriginal(object.data())==numbers[i],"Legacy MT noise integer sequence differs");
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"waveform_count\":6,\"waveform_floats_exact\":98304,\"noise_seed_cases\":9,\"noise_integers_exact\":81000,\"independently_generated_from_math_and_prng\":true,\"native_assets_embedded\":false,\"wrapper_pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

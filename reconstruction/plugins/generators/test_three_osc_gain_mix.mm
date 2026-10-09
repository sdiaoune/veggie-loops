#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
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
namespace {
void require(bool value,const char* message) {if(!value) throw std::runtime_error(message);}
std::string hash(const void* value,size_t length) {
  std::array<unsigned char,32> bytes;CC_SHA256(value,static_cast<CC_LONG>(length),bytes.data());
  std::ostringstream out;for(auto byte:bytes) out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
float sample(std::mt19937& random) {
  // Signed zeros, subnormal/tiny and ordinary bounded finite values.
  uint32_t bits=random();bits=(bits&0x807fffffu)|((random()%129u)<<23);
  return std::bit_cast<float>(bits);
}
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==3,"Usage: test_three_osc_gain_mix <native wrapper> <rebuilt mixer>");
    std::ifstream file(argv[1],std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
    require(hash(image.data(),image.size())=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Source identity mismatch");
    [NSApplication sharedApplication];void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    Dl_info info{};require(dladdr(dlsym(native,"CreatePlugInstance"),&info),"No native base");auto base=static_cast<char*>(info.dli_fbase);
    using Fixed=void(*)(float,float,const float*,float*,uint32_t);
    using Ramp=void(*)(float,float,float,float,const float*,float*,uint32_t);
    auto nativeFixed=reinterpret_cast<Fixed>(base+0x3528);
    auto nativeRamp=reinterpret_cast<Ramp>(base+0x3808);
    auto modelFixed=reinterpret_cast<Fixed>(dlsym(rebuilt,"vl_osc_mix_fixed"));
    auto modelRamp=reinterpret_cast<Ramp>(dlsym(rebuilt,"vl_osc_mix_ramp"));
    require(modelFixed && modelRamp,"Missing compiled mixer primitives");
    std::mt19937 random(0x8675);size_t cases=0,values=0;bool unequalTailVerified=false;
    const std::array<uint32_t,20> lengths{0,1,2,3,4,5,6,7,8,9,10,15,16,17,31,32,33,63,1024,4096};
    for(int i=0;i<24000;++i) {
      const auto frames=i<4000 ? lengths[i%lengths.size()] : random()%1025u;
      const size_t sourceOffset=4+(i%4),destinationOffset=4+((i/4)%4);
      const size_t length=frames*2+16;
      std::vector<float> source(length),initial(length),a(length),b(length);
      for(auto& x:source)x=sample(random);for(auto& x:initial)x=sample(random);
      const auto unchanged=source;
      const float left=i%29==0 ? -0.0f : sample(random),right=i%31==0 ? 0.0f : sample(random);
      const float stepLeft=float(int(random()%2001)-1000)*0.00001f;
      const float stepRight=float(int(random()%2001)-1000)*0.00001f;
      for(int mode=0;mode<2;++mode) {
        a=initial;b=initial;
        if(mode==0) {nativeFixed(left,right,source.data()+sourceOffset,a.data()+destinationOffset,frames);
                     modelFixed(left,right,source.data()+sourceOffset,b.data()+destinationOffset,frames);}
        else {nativeRamp(left,right,stepLeft,stepRight,source.data()+sourceOffset,a.data()+destinationOffset,frames);
              modelRamp(left,right,stepLeft,stepRight,source.data()+sourceOffset,b.data()+destinationOffset,frames);}
        if(std::memcmp(a.data(),b.data(),length*4)!=0) {
          std::cerr<<"case="<<i<<" frames="<<frames<<" mode="<<mode<<'\n';
          for(size_t j=0;j<length;++j) if(std::bit_cast<uint32_t>(a[j])!=std::bit_cast<uint32_t>(b[j])) {std::cerr<<"lane="<<j<<" native="<<a[j]<<" model="<<b[j]<<'\n';break;}
          throw std::runtime_error("Mixer output differs");
        }
        require(std::memcmp(a.data(),initial.data(),destinationOffset*4)==0,"Leading output guard changed");
        const size_t end=destinationOffset+frames*2;
        require(std::memcmp(a.data()+end,initial.data()+end,(length-end)*4)==0,"Trailing output guard changed");
        ++cases;values+=frames*2;
      }
      require(std::memcmp(source.data(),unchanged.data(),length*4)==0,"Source mutated");
    }
    {std::array<float,6> src{1,1,1,1,1,1},a{},b{};
     nativeRamp(0.25f,0.5f,0.01f,0.03f,src.data(),a.data(),3);
     modelRamp(0.25f,0.5f,0.01f,0.03f,src.data(),b.data(),3);
     require(std::memcmp(a.data(),b.data(),24)==0 && a[2]==0.25f+0.03f && a[3]==0.5f+0.01f,"Unequal scalar-tail increments differ");unequalTailVerified=true;}
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"stereo_mix_cases\":"<<cases<<",\"rendered_float_values_exact\":"<<values
             <<",\"alignment_offsets_covered\":16,\"unequal_scalar_tail_verified\":"<<(unequalTailVerified ? "true":"false")
             <<",\"pipeline_integrated\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

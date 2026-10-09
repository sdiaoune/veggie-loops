#include "center_plugin.cpp"
#include <array>
#include <bit>
#include <cassert>
#include <iostream>
#include <limits>
int main() {
  auto *p=vl_center_create(); assert(p);
  std::array<float,16> input{},output{};
  for(size_t i=0;i<8;++i){input[2*i]=.5f;input[2*i+1]=-.25f;}
  assert(vl_center_render(p,input.data(),output.data(),8));
  assert(p->numerical.position[0]!=0&&p->numerical.velocity[1]!=0);
  output.fill(42);const auto expectedOutput=output;
  size_t rejected=0;
  const auto alias=[&](ptrdiff_t off){const auto n=reinterpret_cast<uintptr_t>(p);return off<0?n-size_t(-off):n+size_t(off);};
  const auto reject=[&](auto call){
    std::array<unsigned char,sizeof(*p)> before{},after{};
    std::memcpy(before.data(),p,before.size());
    assert(call()==0);std::memcpy(after.data(),p,after.size());
    assert(before==after&&output==expectedOutput);++rejected;
  };
  for(ptrdiff_t off=-3;off<ptrdiff_t(sizeof(*p));++off)
    reject([&]{return vl_center_parameter(p,0,0,2,reinterpret_cast<int32_t*>(alias(off)));});
  for(ptrdiff_t off=-7;off<ptrdiff_t(sizeof(*p));++off){
    reject([&]{return vl_center_save_state(p,reinterpret_cast<uint8_t*>(alias(off)),8);});
    reject([&]{return vl_center_restore_state(p,reinterpret_cast<uint8_t*>(alias(off)),8);});
    reject([&]{return vl_center_render(p,reinterpret_cast<float*>(alias(off)),output.data(),1);});
    reject([&]{return vl_center_render(p,input.data(),reinterpret_cast<float*>(alias(off)),1);});
  }
  for(ptrdiff_t off=-31;off<ptrdiff_t(sizeof(*p));++off)
    reject([&]{return vl_center_get_filter_state(p,reinterpret_cast<double*>(alias(off)));});
  for(ptrdiff_t off=0;off<ptrdiff_t(sizeof(*p));++off)
    reject([&]{return vl_center_render(p,reinterpret_cast<float*>(alias(off)),reinterpret_cast<float*>(alias(off)),0);});
  for(int enabled:{0,1})for(int style:{0,1,2}){
    p->numerical.enabled=enabled;
    p->numerical.position={0x1p-25,-0.0};p->numerical.velocity={-0x1p-25,0.0};
    const auto before=p->numerical;
    const float*in=style==0?nullptr:input.data();float*out=style==1?nullptr:output.data();
    assert(vl_center_render(p,in,out,0));assert(output==expectedOutput);
    if(enabled){for(auto value:p->numerical.position)assert(std::bit_cast<uint64_t>(value)==0);for(auto value:p->numerical.velocity)assert(std::bit_cast<uint64_t>(value)==0);}
    else {assert(std::memcmp(&before,&p->numerical,sizeof(before))==0);}
  }
  vl_center_destroy(p);
  std::cout<<"{\"status\":\"passed\",\"alias_rejection_interval_cases\":"<<rejected<<",\"zero_frame_nullable_cases\":6,\"sanitizers\":\"address,undefined\",\"source_binaries_loaded\":false}\n";
}

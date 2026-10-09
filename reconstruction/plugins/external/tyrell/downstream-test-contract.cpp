#include "downstream-getter.h"
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
static void check(bool x){if(!x)throw std::runtime_error("Raw getter contract");}
template<class T>static void put(void*p,size_t o,T v){std::memcpy(static_cast<unsigned char*>(p)+o,&v,sizeof v);}
int main(){try{
 check(std::fegetround()==FE_TONEAREST);
 std::array<unsigned char,4*116> descriptors{};std::array<uint32_t,4> raw{0x80000000u,0x7fc12345u,0x7f800000u,0x3f800001u};
 std::array<int32_t,4> ints{INT32_MAX,INT32_MIN,16777217,-16777217};
 std::array<const void*,4> pointers{&ints[0],nullptr,&raw[2],&raw[3]};
 std::array<int32_t,4> map{3,2,1,0},specialMap{0,1,0,1};std::array<unsigned char,32> special{};
 put(descriptors.data(),72,int32_t(0));put(descriptors.data(),116+72,int32_t(0));put(descriptors.data(),232+72,int32_t(3));put(descriptors.data(),348+72,int32_t(1));put(descriptors.data(),348+92,uint32_t(2));put(special.data(),28,uint32_t(0x7f812345u));
 VLTyrellRawView view{descriptors.data(),raw.data(),pointers.data(),specialMap.data(),special.data(),map.data(),4,2,4};
 uint64_t success=0,rejects=0;float out=0;
 for(int32_t id=0;id<4;++id)for(int mode=0;mode<2;++mode){const int32_t index=mode?3-id:id;
  check(vl_tyrell_raw_get(&view,index,mode,std::bit_cast<float>(0x7fc99aabu),&out));const uint32_t expected=id==0?std::bit_cast<uint32_t>(float(INT32_MAX)):id==1?raw[1]:id==2?raw[2]:0x7f812345u;
  check(std::bit_cast<uint32_t>(out)==expected);++success;
 }
 for(int32_t value:{INT32_MIN,INT32_MAX,0,-1,1,16777215,16777216,16777217,16777218,-16777215,-16777216,-16777217,-16777218}){
  ints[0]=value;check(vl_tyrell_raw_get(&view,0,0,1234,&out)&&std::bit_cast<uint32_t>(out)==std::bit_cast<uint32_t>(float(double(value))));++success;
 }
 uint32_t rng=0x717963;for(int n=0;n<4096;++n){rng=rng*1664525u+1013904223u;raw[1]=rng;check(vl_tyrell_raw_get(&view,1,0,0,&out)&&std::bit_cast<uint32_t>(out)==rng);++success;}
 const auto rejected=[&](auto call){const auto prior=std::bit_cast<uint32_t>(out);const auto descBefore=descriptors;const auto rawBefore=raw;const auto intsBefore=ints;const auto specialBefore=special;
  check(!call()&&std::bit_cast<uint32_t>(out)==prior&&descriptors==descBefore&&raw==rawBefore&&ints==intsBefore&&special==specialBefore);++rejects;};
 for(int id:{-1,4,INT32_MIN,INT32_MAX})rejected([&]{return vl_tyrell_raw_get(&view,id,0,0,&out);});
 for(int flag:{-1,2,255,256,INT32_MAX})rejected([&]{return vl_tyrell_raw_get(&view,0,flag,0,&out);});
 for(int id:{-1,4,213}){map[0]=id;rejected([&]{return vl_tyrell_raw_get(&view,0,1,0,&out);});}map[0]=3;
 for(int id:{-1,2,213}){specialMap[3]=id;rejected([&]{return vl_tyrell_raw_get(&view,3,0,0,&out);});}specialMap[3]=1;
 auto invalid=view;for(uint32_t count:{214u,UINT32_MAX}){invalid.internal_count=count;rejected([&]{return vl_tyrell_raw_get(&invalid,0,0,0,&out);});}invalid=view;
 invalid.special_count=214;rejected([&]{return vl_tyrell_raw_get(&invalid,0,0,0,&out);});invalid=view;
 invalid.public_count=93;rejected([&]{return vl_tyrell_raw_get(&invalid,0,0,0,&out);});
 for(auto field:{&VLTyrellRawView::raw_values,&VLTyrellRawView::special_map,&VLTyrellRawView::special_records,&VLTyrellRawView::public_map}){
  invalid=view;invalid.*field=nullptr;const int id=field==&VLTyrellRawView::raw_values?1:3;const int flag=field==&VLTyrellRawView::public_map?1:0;
  rejected([&]{return vl_tyrell_raw_get(&invalid,id,flag,0,&out);});
 }
 invalid=view;invalid.parameter_pointers=nullptr;rejected([&]{return vl_tyrell_raw_get(&invalid,0,0,0,&out);});rejected([&]{return vl_tyrell_raw_get(&invalid,2,0,0,&out);});
 pointers[2]=nullptr;rejected([&]{return vl_tyrell_raw_get(&view,2,0,0,&out);});pointers[2]=&raw[2];
 check(vl_tyrell_raw_get(nullptr,0,0,99,&out)&&std::bit_cast<uint32_t>(out)==0);++success;
 invalid=view;invalid.descriptors=nullptr;check(vl_tyrell_raw_get(&invalid,0,0,-123,&out)&&std::bit_cast<uint32_t>(out)==0);++success;
 // Every overlapping byte start rejects before alignment-sensitive reads.
 for(const auto span:{std::pair<const void*,size_t>{&view,sizeof view},{descriptors.data(),descriptors.size()},{raw.data(),sizeof raw},{pointers.data(),sizeof pointers},{specialMap.data(),sizeof specialMap},{special.data(),sizeof special},{map.data(),sizeof map},{ints.data(),4}}){
  const auto start=reinterpret_cast<uintptr_t>(span.first);for(int64_t off=-3;off<int64_t(span.second);++off){
   float*bad=reinterpret_cast<float*>(start+uintptr_t(off));const auto before=view;const auto descBefore=descriptors;const auto spBefore=special;const auto rawBefore=raw;const auto intsBefore=ints;
   check(!vl_tyrell_raw_get(&view,0,0,0,bad)&&!std::memcmp(&view,&before,sizeof view)&&descBefore==descriptors&&spBefore==special&&rawBefore==raw&&intsBefore==ints);++rejects;
  }
 }
 invalid=view;invalid.descriptors=nullptr;check(!vl_tyrell_raw_get(&invalid,0,0,0,reinterpret_cast<float*>(&ints[0])));++rejects;
 check(!vl_tyrell_raw_get(&view,0,0,0,nullptr));++rejects;
 std::cout<<"{\"status\":\"passed\",\"source_only_sanitizers\":true,\"success_cases\":"<<success<<",\"atomic_rejections\":"<<rejects<<"}\n";
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}

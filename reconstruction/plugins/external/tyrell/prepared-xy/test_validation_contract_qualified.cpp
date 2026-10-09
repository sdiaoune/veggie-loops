#include "xy-api.h"
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
static void require(bool v,const char* text){if(!v)throw std::runtime_error(text);}
struct Fixture {
 uint64_t leading[4];std::array<VLTyrellXYDescriptor,213> descriptors;
 uint64_t middle1[4];VLTyrellXYState state;uint64_t middle2[4];
 VLTyrellXYResult result;uint64_t trailing[4];
 Fixture(){std::memset(this,0xa5,sizeof *this);state.internal_count=2;state.xy_count=1;state.targets_per_control=1;state.cell_count=2;state.queue_count=-1;state.dirty=19;
  for(unsigned i=0;i<2;++i){descriptors[i]={i?2:0,-1024,1024};state.raw[i]=i?50.f:0.f;state.cell_slots[i]=int32_t(i);state.marks[i]=-1;state.cells[i]=std::bit_cast<float>(i?0x80000001u:0x00000001u);}
  state.records[0]={-1,std::bit_cast<float>(0x80000001u),std::bit_cast<float>(0x00000001u),std::bit_cast<float>(0x7f800001u)};
 }
};
static uint64_t accepted=0,rejected=0,restored=0;
static void check(Fixture f,bool expected,int seed){
 const Fixture old=f;std::fenv_t outer{},before{},after{},readback{};
 require(std::fegetenv(&outer)==0&&std::feclearexcept(FE_ALL_EXCEPT)==0&&std::feraiseexcept(seed)==0&&std::fegetenv(&before)==0,"Validation contract fenv setup");
 const int status=vl_tyrell_xy_step(f.descriptors.data(),2,&f.state,&f.result);
 require(std::fegetenv(&after)==0&&!std::memcmp(&before,&after,sizeof before),"Validation changed caller floating environment");
 require(bool(status)==expected,"Validation acceptance differs from ordinary finite reference");
 if(expected){Fixture wanted=old;wanted.state.queue_count=0;wanted.state.dirty=0;wanted.result.touched_count=0;require(!std::memcmp(&f,&wanted,sizeof f),"Validation success changed inactive/guard/state bytes");++accepted;}
 else{require(!std::memcmp(&f,&old,sizeof f),"Validation rejection changed state/result/guards");++rejected;}
 require(std::fesetenv(&outer)==0&&std::fegetenv(&readback)==0&&!std::memcmp(&outer,&readback,sizeof outer),"Validation contract outer restore/readback");++restored;
}
static bool endpointReference(float a,float b){return std::isfinite(a)&&std::isfinite(b)&&std::fabs(a)<=1024.f&&std::fabs(b)<=1024.f&&a<=b;}
static bool magnitudeReference(float v,float limit){return std::isfinite(v)&&std::fabs(v)<=limit;}
int main(){try{
 std::fenv_t entry{},exit{};require(std::fegetenv(&entry)==0&&std::fesetround(FE_TONEAREST)==0,"Initial contract fenv");
 const uint32_t words[]={0u,0x80000000u,1u,0x80000001u,2u,0x80000002u,0x007fffffu,0x807fffffu,0x00800000u,0x80800000u,0x3f800000u,0xbf800000u,0x42c80000u,0xc2c80000u,0x42c80001u,0xc2c80001u,0x44800000u,0xc4800000u,0x44800001u,0xc4800001u,0x7f800000u,0xff800000u,0x7fc00001u,0x7f800001u,0xff800001u};
 for(uint32_t a:words)for(uint32_t b:words){const float minimum=std::bit_cast<float>(a),maximum=std::bit_cast<float>(b);const bool expected=endpointReference(minimum,maximum);for(int seed:{0,FE_ALL_EXCEPT}){Fixture f;f.descriptors[0].minimum=minimum;f.descriptors[0].maximum=maximum;check(f,expected,seed);}}
 for(uint32_t bits:words){const float value=std::bit_cast<float>(bits);for(unsigned field=0;field<5;++field){if(field==1&&(bits&0x7fffffffu)!=0&&(bits&0x7f800000u)==0)continue; // Active coordinate comparison is actual XY FP work, covered by native pairs.
 const float limit=field==0||field==2?1024.f:100.f;const bool expected=magnitudeReference(value,limit);for(int seed:{0,FE_ALL_EXCEPT}){Fixture f;if(field==0)f.state.raw[0]=value;if(field==1)f.state.raw[1]=value;if(field==2)f.state.cells[0]=value;if(field==3)f.state.records[0].negative_depth=value;if(field==4)f.state.records[0].positive_depth=value;check(f,expected,seed);}}}
 require(restored==1488&&accepted&&rejected,"Validation contract coverage differs");require(std::fesetenv(&entry)==0&&std::fegetenv(&exit)==0&&!std::memcmp(&entry,&exit,sizeof entry),"Entire validation test caller restore");
 std::cout<<"{\"status\":\"passed_bit_validation_state_and_FP_preservation\",\"calls\":"<<restored<<",\"accepted\":"<<accepted<<",\"atomic_rejections\":"<<rejected<<",\"endpoint_pairs\":625,\"field_magnitude_values\":119,\"active_subnormal_coordinate_cases_separately_native_tested\":12,\"two_seeded_FP_environments_per_input\":true,\"full_fenv_readbacks\":"<<restored<<",\"original_executed\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}

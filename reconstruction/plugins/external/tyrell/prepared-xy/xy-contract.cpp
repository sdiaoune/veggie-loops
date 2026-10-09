#include "xy-api.h"
#include <array>
#include <bit>
#include <cfenv>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <cstdint>
namespace {
void require(bool v,const char* message){if(!v)throw std::runtime_error(message);}
template<class T>struct Guarded{uint64_t before[4];T value;uint64_t after[4];};
using Descriptors=std::array<VLTyrellXYDescriptor,213>;
struct Fixture {
 Guarded<Descriptors> d;Guarded<VLTyrellXYState> s;Guarded<VLTyrellXYResult> r;
 Fixture(){std::memset(this,0xa5,sizeof *this);s.value.internal_count=4;s.value.xy_count=1;s.value.targets_per_control=2;s.value.cell_count=4;s.value.queue_count=0;s.value.dirty=17;
  for(uint32_t i=0;i<4;++i){d.value[i]={i==1?2:0,-100,100};s.value.raw[i]=i==1?100.f:0.f;s.value.cell_slots[i]=int32_t(i);s.value.cells[i]=0;s.value.marks[i]=-1;}
  s.value.records[0]={0,-7,50,std::bit_cast<float>(0x7fc0beefu)};s.value.records[1]={0,9,25,std::bit_cast<float>(0x7fc0cafeu)};
 }
 int call(){return vl_tyrell_xy_step(d.value.data(),s.value.internal_count,&s.value,&r.value);}
 void guards(const Fixture&old){require(!std::memcmp(d.before,old.d.before,sizeof d.before)&&!std::memcmp(d.after,old.d.after,sizeof d.after)&&!std::memcmp(s.before,old.s.before,sizeof s.before)&&!std::memcmp(s.after,old.s.after,sizeof s.after)&&!std::memcmp(r.before,old.r.before,sizeof r.before)&&!std::memcmp(r.after,old.r.after,sizeof r.after),"Nonzero guards changed");}
};
uint64_t successes=0,rejections=0;
template<class F>void rejected(F change){Fixture f;change(f);const Fixture old=f;require(!f.call(),"Malformed input accepted");require(!std::memcmp(&f,&old,sizeof f),"Rejected call mutated storage");++rejections;}
}
int main(){try{
 require(std::fesetround(FE_TONEAREST)==0,"Nearest-even unavailable");
 {Fixture f;const Fixture old=f;require(f.call(),"Golden duplicate rejected");require(f.s.value.cells[0]==75&&f.s.value.records[0].last_contribution==50&&f.s.value.records[1].last_contribution==25&&f.r.value.touched_count==2&&f.s.value.touched[0]==0&&f.s.value.touched[1]==0&&f.s.value.marks[0]==-1&&f.s.value.dirty==0,"Duplicate accumulation differs");f.guards(old);require(!std::memcmp(f.d.value.data(),old.d.value.data(),sizeof f.d.value),"Descriptors changed");require(!std::memcmp(f.s.value.raw,old.s.value.raw,sizeof f.s.value.raw),"Raw changed");require(!std::memcmp(f.s.value.records+2,old.s.value.records+2,sizeof f.s.value.records-2*sizeof(VLTyrellXYRecord)),"Inactive records changed");require(!std::memcmp(f.s.value.touched+2,old.s.value.touched+2,sizeof f.s.value.touched-8),"Scratch suffix changed");++successes;}
 {Fixture f;f.s.value.queue_count=-1;f.s.value.records[0].target_id=f.s.value.records[1].target_id=-1;const Fixture old=f;require(f.call(),"Skipped records rejected");require(f.s.value.queue_count==0&&f.s.value.dirty==0&&f.r.value.touched_count==0,"Empty result differs");require(!std::memcmp(f.s.value.records,old.s.value.records,sizeof f.s.value.records)&&!std::memcmp(f.s.value.cells,old.s.value.cells,sizeof f.s.value.cells)&&!std::memcmp(f.s.value.marks,old.s.value.marks,sizeof f.s.value.marks)&&!std::memcmp(f.s.value.touched,old.s.value.touched,sizeof f.s.value.touched),"Inactive storage changed");f.guards(old);++successes;}
 {Fixture f;f.s.value.records[1].target_id=2;f.s.value.cell_slots[2]=0;f.d.value[0].minimum=-100;f.d.value[0].maximum=-20;f.d.value[2].minimum=10;f.d.value[2].maximum=100;const Fixture old=f;require(f.call()&&f.s.value.cells[0]==10&&f.r.value.touched_count==2,"Shared-cell clamp order differs");f.guards(old);++successes;}
 {Fixture f;f.s.value.records[1].target_id=2;f.s.value.cell_slots[2]=0;f.d.value[0].minimum=-100;f.d.value[0].maximum=-20;f.d.value[2].minimum=10;f.d.value[2].maximum=100;std::swap(f.s.value.records[0],f.s.value.records[1]);const Fixture old=f;require(f.call()&&f.s.value.cells[0]==-20,"Reversed shared-cell clamp order differs");f.guards(old);++successes;}
 {Fixture f;f.s.value.raw[1]=-0.f;f.s.value.records[1].target_id=-1;const Fixture old=f;require(f.call()&&std::bit_cast<uint32_t>(f.s.value.records[0].last_contribution)==0x80000000u,"Signed-zero contribution differs");f.guards(old);++successes;}
 for(uint32_t bad:{0u,1u,214u,UINT32_MAX})rejected([&](Fixture& f){f.s.value.internal_count=bad;});
 for(uint32_t bad:{0u,5u,UINT32_MAX})rejected([&](Fixture& f){f.s.value.xy_count=bad;});
 for(uint32_t bad:{0u,17u,UINT32_MAX})rejected([&](Fixture& f){f.s.value.targets_per_control=bad;});
 for(uint32_t bad:{0u,5u,UINT32_MAX})rejected([&](Fixture& f){f.s.value.cell_count=bad;});
 for(int32_t bad:{-2,1,INT32_MIN,INT32_MAX})rejected([&](Fixture& f){f.s.value.queue_count=bad;});
 rejected([](Fixture& f){f.d.value[0].full_type=2;});rejected([](Fixture& f){f.d.value[1].full_type=0x102;});rejected([](Fixture& f){f.d.value[2].full_type=2;});
 for(uint32_t id=0;id<4;++id){
  for(int32_t bad:{-1,4,INT32_MIN,INT32_MAX})rejected([&](Fixture& f){f.s.value.cell_slots[id]=bad;});
  for(int32_t bad:{-2,1,INT32_MIN,INT32_MAX})rejected([&](Fixture& f){f.s.value.marks[id]=bad;});
  for(float bad:{-1025.f,1025.f,std::numeric_limits<float>::infinity(),-std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()}){
   rejected([&](Fixture& f){f.s.value.raw[id]=bad;});rejected([&](Fixture& f){f.s.value.cells[id]=bad;});rejected([&](Fixture& f){f.d.value[id].minimum=bad;});rejected([&](Fixture& f){f.d.value[id].maximum=bad;});
  }
  rejected([&](Fixture& f){f.d.value[id].minimum=1;f.d.value[id].maximum=-1;});
 }
 for(float bad:{-101.f,101.f})rejected([&](Fixture& f){f.s.value.raw[1]=bad;});
 for(uint32_t slot=0;slot<2;++slot){for(int32_t bad:{-2,4,INT32_MIN,INT32_MAX})rejected([&](Fixture& f){f.s.value.records[slot].target_id=bad;});for(float bad:{-101.f,101.f,std::numeric_limits<float>::infinity(),-std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()}){rejected([&](Fixture& f){f.s.value.records[slot].negative_depth=bad;});rejected([&](Fixture& f){f.s.value.records[slot].positive_depth=bad;});}}
 {Fixture f;const Fixture old=f;for(uint32_t capacity:{0u,1u,3u,214u,UINT32_MAX}){require(!vl_tyrell_xy_step(f.d.value.data(),capacity,&f.s.value,&f.r.value),"Bad capacity accepted");require(!std::memcmp(&f,&old,sizeof f),"Capacity rejection wrote");++rejections;}}
 {Fixture f;const Fixture old=f;require(!vl_tyrell_xy_step(nullptr,4,&f.s.value,&f.r.value),"Null descriptors");require(!vl_tyrell_xy_step(f.d.value.data(),4,nullptr,&f.r.value),"Null state");require(!vl_tyrell_xy_step(f.d.value.data(),4,&f.s.value,nullptr),"Null result");require(!std::memcmp(&f,&old,sizeof f),"Null rejection wrote");rejections+=3;}
 {Fixture f;const Fixture old=f;require(!vl_tyrell_xy_step(reinterpret_cast<const VLTyrellXYDescriptor*>(&f.s.value),4,&f.s.value,&f.r.value),"Descriptor/state overlap");require(!vl_tyrell_xy_step(f.d.value.data(),4,&f.s.value,reinterpret_cast<VLTyrellXYResult*>(&f.s.value)),"State/result overlap");require(!vl_tyrell_xy_step(f.d.value.data(),4,&f.s.value,reinterpret_cast<VLTyrellXYResult*>(f.d.value.data())),"Descriptor/result overlap");require(!std::memcmp(&f,&old,sizeof f),"Overlap rejection wrote");rejections+=3;}
 {Fixture f;const Fixture old=f;auto* d=reinterpret_cast<const VLTyrellXYDescriptor*>(std::numeric_limits<uintptr_t>::max()-3);auto* r=reinterpret_cast<VLTyrellXYResult*>(std::numeric_limits<uintptr_t>::max()-1);require(!vl_tyrell_xy_step(d,4,&f.s.value,&f.r.value),"Descriptor range wrap");require(!vl_tyrell_xy_step(f.d.value.data(),4,&f.s.value,r),"Result range wrap");require(!std::memcmp(&f,&old,sizeof f),"Range rejection wrote");rejections+=2;}
 {Fixture f;const Fixture old=f;std::fenv_t env;require(std::fegetenv(&env)==0&&std::fesetround(FE_DOWNWARD)==0,"Rounding setup");require(!f.call(),"Unsupported rounding accepted");require(std::fesetenv(&env)==0&&!std::memcmp(&f,&old,sizeof f),"Rounding rejection mutated storage");++rejections;}
 std::cout<<"{\"status\":\"passed_prepared_XY_contract\",\"successes\":"<<successes<<",\"atomic_rejections\":"<<rejections<<",\"native_executed\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}

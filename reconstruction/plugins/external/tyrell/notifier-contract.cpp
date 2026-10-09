#include "notifier-storage.h"
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
namespace {
void require(bool v,const char*m){if(!v)throw std::runtime_error(m);}
using Descriptors=std::array<VLTyrellNotifyDescriptor,213>;
struct Case {
 Descriptors d{};VLTyrellNotifyState s{};
 Case(){s.internal_count=2;s.special_count=2;s.queue_count=0;
  d[0]={1,2,0,100,0,1};d[1]={0,0,-24,24,1,1};
  s.special[0].identifier=0;s.special[1].identifier=1;}
};
uint64_t successes=0,rejections=0;
VLTyrellNotifyResult apply(Case&c,float value,uint32_t force=0,int32_t id=0){
 VLTyrellNotifyResult r{};require(vl_tyrell_notifier_storage(c.d.data(),&c.s,id,force,value,&r),"Valid source case rejected");++successes;return r;
}
void reject(Case c,int32_t id,uint32_t force,float value){const auto before=c;
 VLTyrellNotifyResult r{};std::memset(&r,0x5a,sizeof r);const auto prior=r;
 require(!vl_tyrell_notifier_storage(c.d.data(),&c.s,id,force,value,&r),"Malformed accepted");
 require(!std::memcmp(&c,&before,sizeof c)&&!std::memcmp(&r,&prior,sizeof r),"Rejected call changed bytes");++rejections;
}
}
int main(){try{
 {
  Case c;auto r=apply(c,25);require(c.s.queue_count==1&&c.s.queue[0]==0&&
  c.s.special[0].remaining==50&&c.s.special[0].increment==.5f&&c.s.special[0].target==25&&c.s.raw[0]==0&&c.s.pointee_bits[0]==0&&!r.effective_immediate,"New 50-step motion");
  const auto held=c.s;apply(c,25);require(!std::memcmp(&held,&c.s,sizeof held),"Equal target changed motion");
  apply(c,75);require(c.s.queue_count==1&&c.s.special[0].remaining==50&&c.s.special[0].increment==1.5f&&c.s.raw[0]==0,"Retarget uses current cache");
  apply(c,75,1);require(c.s.raw[0]==75&&c.s.pointee_bits[0]==std::bit_cast<uint32_t>(75.0f)&&c.s.special[0].remaining==50&&c.s.special[0].increment==1.5f&&c.s.queue_count==1,"Equal immediate target retains queued motion");
  apply(c,50,1);require(c.s.raw[0]==50&&c.s.special[0].remaining==1&&c.s.special[0].increment==0&&c.s.queue_count==1,"Immediate retarget keeps queue entry");
 }
 {
  Case c;c.s.special[0].remaining=17;c.s.special[0].increment=.25f;c.s.special[0].target=75;
  auto r=apply(c,25);require(r.effective_immediate&&c.s.queue_count==0&&c.s.raw[0]==25&&c.s.special[0].target==25&&c.s.special[0].remaining==0&&c.s.special[0].increment==0&&c.s.dirty==1,"Unqueued stale motion reset");
 }
 {
  Case c;c.s.raw[0]=75;c.s.special[0].target=75;c.d[0].flags|=0x200;
  apply(c,24);require(c.s.special[0].increment==.02f*49&&c.s.special[0].remaining==50,"Short cyclic route");
  c=Case{};c.s.raw[0]=75;c.s.special[0].target=75;c.d[0].flags|=0x200;
  apply(c,25);require(c.s.special[0].increment==-1,"Cyclic tie must keep direct route");
 }
 {
  Case c;c.s.queue_count=-1;apply(c,-0.0f);
  require(std::bit_cast<uint32_t>(c.s.raw[0])==0x80000000&&c.s.pointee_bits[0]==0x80000000&&std::bit_cast<uint32_t>(c.s.special[0].target)==0x80000000,"Signed zero float storage");
  for(float value:{-24.0f,-23.5f,-.5f,-0.0f,0.0f,.49999997f,.5f,23.5f,24.0f}){
   auto r=apply(c,value,0,1);const float reference=std::floor(value+.5f);
   require(c.s.raw[1]==reference&&c.s.pointee_bits[1]==uint32_t(int32_t(reference))&&r.unit_activity_needed&&!r.unit_set_needed,"Integer raw/pointee writes");}
  c.d[1].pointer_present=0;auto r=apply(c,2,0,1);require(r.unit_set_needed&&!r.unit_activity_needed,"Null pointer callback routing");
 }
 for(int32_t type:{3,4,0x103,0x104,0x604,-252}){
  Case c;c.d[0].type=type;const auto before=c.s;const auto r=apply(c,25);
  require(r.ignored&&!std::memcmp(&before,&c.s,sizeof before),"Low-byte ignored type");
 }
 for(auto mode:std::array<std::array<int32_t,3>,4>{{{-1,0,0},{0,1,0},{0,0,1},{0,0,-1}}}){
  Case c;c.s.queue_count=mode[0];c.s.immediate=uint32_t(mode[1]);c.s.depth=mode[2];auto r=apply(c,50);
  const bool immediate=mode[0]==-1||mode[1]||mode[2]>0;
  require(bool(r.effective_immediate)==immediate&&c.s.raw[0]==(immediate?50:0),"Factory/immediate/depth precedence");
 }
 for(uint32_t force:{0u,1u,2u,255u}){
  Case c;auto r=apply(c,50,force);require(bool(r.effective_immediate)==bool(force),"Force byte truthiness");}
 for(int32_t id:{-1,2,INT32_MIN,INT32_MAX})reject(Case{},id,0,25);
 for(float value:{std::numeric_limits<float>::infinity(),-std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN(),8193.0f})reject(Case{},0,0,value);
 reject(Case{},0,256,25);
 const auto bad=[&](auto mutate){Case c;mutate(c);reject(c,0,0,25);};
 bad([](Case&c){c.s.internal_count=214;});bad([](Case&c){c.s.special_count=214;});
 bad([](Case&c){c.s.queue_count=-2;});bad([](Case&c){c.s.queue_count=3;});
 bad([](Case&c){c.s.dirty=2;});bad([](Case&c){c.s.immediate=256;});
 bad([](Case&c){c.s.raw[1]=4097;});bad([](Case&c){c.d[1].pointer_present=2;});
 bad([](Case&c){c.s.special[0].identifier=2;});bad([](Case&c){c.s.special[0].increment=8193;});
 bad([](Case&c){c.s.special[0].target=4097;});bad([](Case&c){c.s.special[0].remaining=51;});
 bad([](Case&c){c.s.special[0].remaining=-2;});bad([](Case&c){c.s.queue_count=1;c.s.queue[0]=2;});
 bad([](Case&c){c.d[0].minimum=101;});bad([](Case&c){c.d[0].maximum=4097;});
 bad([](Case&c){c.d[0].special_index=-1;});bad([](Case&c){c.d[0].special_index=2;});
 bad([](Case&c){c.d[0].type=5;});bad([](Case&c){c.d[0].type=0x100;});
 bad([](Case&c){c.s.queue_count=2;c.s.queue[0]=1;c.s.queue[1]=1;});
 {
  Case c;alignas(VLTyrellNotifyState) std::array<unsigned char,sizeof(VLTyrellNotifyState)+sizeof(VLTyrellNotifyResult)> bytes{};
  for(size_t i=0;i<sizeof(VLTyrellNotifyState);++i){std::memcpy(bytes.data(),&c.s,sizeof c.s);const auto before=bytes;
   require(!vl_tyrell_notifier_storage(c.d.data(),reinterpret_cast<VLTyrellNotifyState*>(bytes.data()),0,0,25,reinterpret_cast<VLTyrellNotifyResult*>(bytes.data()+i)),"State/result alias accepted");require(bytes==before,"Alias rejection mutated bytes");++rejections;}
  VLTyrellNotifyResult r{};const auto before=c;
  require(!vl_tyrell_notifier_storage(reinterpret_cast<const VLTyrellNotifyDescriptor*>(&c.s),&c.s,0,0,25,&r),"Descriptor/state alias accepted");require(!std::memcmp(&before,&c,sizeof c),"Descriptor alias changed bytes");++rejections;
 }
 std::cout<<"{\"status\":\"passed_prepared_notifier_contract\",\"success_cases\":"<<successes<<",\"atomic_rejections\":"<<rejections<<",\"full_plugin_equivalence\":false}\n";
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}

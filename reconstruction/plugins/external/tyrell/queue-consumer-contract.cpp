#include "queue-consumer-storage.h"
#include <array>
#include <bit>
#include <cassert>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <iostream>
#include <limits>
#include <new>
namespace {
uint64_t success=0,rejections=0;
struct Fixture{
 VLTyrellQueueState s{};VLTyrellQueueResult r{12345};std::array<VLTyrellQueueDescriptor,3>d{};
 Fixture(){s.internal_count=s.special_count=s.pointee_count=3;s.queue_count=3;s.dirty=1;
  for(int32_t i=0;i<3;++i){s.raw[i]=float(i);s.pointee_words[i]=std::bit_cast<uint32_t>(float(i));s.records[i]={i,.25f,50,float(i+1)};s.queue[i]=i;s.marks[i]=-1;s.changed[i]=-17;d[i]={-10,10,0,i};}
 }
 void reject(){const auto oldS=s;const auto oldD=d;const auto oldR=r;assert(!vl_tyrell_queue_step(d.data(),&s,&r));assert(!std::memcmp(&s,&oldS,sizeof s)&&!std::memcmp(&r,&oldR,sizeof r)&&!std::memcmp(d.data(),oldD.data(),sizeof d));++rejections;}
 void pass(){assert(vl_tyrell_queue_step(d.data(),&s,&r));++success;}
};
}
int main(){
 {Fixture f;f.s.queue_count=-1;f.pass();assert(f.s.queue_count==0&&f.r.visited_count==0&&f.s.dirty==0);}
 {Fixture f;f.s.queue_count=0;f.pass();assert(f.r.visited_count==0&&f.s.dirty==0);}
 {Fixture f;f.s.records[0].remaining=1;f.s.records[1].remaining=2;f.s.records[2].remaining=0;f.pass();assert(f.r.visited_count==3&&f.s.queue_count==1&&f.s.queue[0]==1&&f.s.records[0].remaining==-1&&f.s.records[2].remaining==-1&&f.s.records[1].remaining==1);assert(f.s.changed[0]==0&&f.s.changed[1]==2&&f.s.changed[2]==1);}
 {Fixture f;f.d[1].pointee_index=f.d[2].pointee_index=0;for(auto&x:f.s.records)x.remaining=1;f.pass();assert(f.s.changed[0]==0&&f.s.changed[1]==2&&f.s.changed[2]==1&&f.s.pointee_words[0]==std::bit_cast<uint32_t>(1.0f));}
 {Fixture f;f.s.queue_count=1;f.d[0].minimum=1;f.d[0].maximum=4;f.d[0].flags=0x200;f.s.raw[0]=3.75f;f.s.records[0].increment=.5f;f.pass();assert(f.s.raw[0]==1.25f);}
 {Fixture f;f.s.queue_count=1;f.d[0].minimum=1;f.d[0].maximum=4;f.d[0].flags=0x200;f.s.raw[0]=1.25f;f.s.records[0].increment=-.5f;f.pass();assert(f.s.raw[0]==3.75f);}
 for(uint32_t bits:{0u,0x80000000u}){Fixture f;f.s.queue_count=1;f.s.records[0].remaining=1;f.s.records[0].target=std::bit_cast<float>(bits);f.pass();assert(f.s.pointee_words[0]==bits&&std::bit_cast<uint32_t>(f.s.raw[0])==bits);}
 for(int field=0;field<10;++field){Fixture f;switch(field){case 0:f.s.internal_count=214;break;case 1:f.s.special_count=4;break;case 2:f.s.pointee_count=214;break;case 3:f.s.xy_count=1;break;case 4:f.s.xy_targets_per_control=1;break;case 5:f.s.queue_count=-2;break;case 6:f.s.queue_count=4;break;case 7:f.s.queue[0]=-1;break;case 8:f.s.queue[0]=3;break;case 9:f.d[0].pointee_index=-1;break;}f.reject();}
 for(int field=0;field<14;++field){Fixture f;switch(field){case 0:f.s.records[0].identifier=-1;break;case 1:f.s.records[0].identifier=3;break;case 2:f.s.records[0].remaining=-2;break;case 3:f.s.records[0].remaining=51;break;case 4:f.s.records[0].increment=8193;break;case 5:f.s.records[0].target=4097;break;case 6:f.s.raw[0]=32769;break;case 7:f.d[0].minimum=-4097;break;case 8:f.d[0].maximum=4097;break;case 9:f.d[0].minimum=11;break;case 10:f.d[0].pointee_index=-2;break;case 11:f.d[0].pointee_index=3;break;case 12:f.s.raw[0]=32768;f.s.records[0].increment=1;break;case 13:f.s.raw[0]=-32768;f.s.records[0].increment=-1;break;}f.reject();}
 for(uint32_t bits:{0x7f800000u,0xff800000u,0x7fc00001u,0x7f800001u})for(int field=0;field<5;++field){Fixture f;float v=std::bit_cast<float>(bits);if(field==0)f.s.raw[0]=v;else if(field==1)f.s.records[0].increment=v;else if(field==2)f.s.records[0].target=v;else if(field==3)f.d[0].minimum=v;else f.d[0].maximum=v;f.reject();}
 {Fixture f;const auto old=f.s;assert(!vl_tyrell_queue_step(nullptr,&f.s,&f.r));assert(!std::memcmp(&f.s,&old,sizeof old));assert(!vl_tyrell_queue_step(f.d.data(),nullptr,&f.r));assert(!vl_tyrell_queue_step(f.d.data(),&f.s,nullptr));rejections+=3;}
 for(size_t offset=0;offset<sizeof(VLTyrellQueueState);++offset){Fixture f;const auto old=f.s;assert(!vl_tyrell_queue_step(f.d.data(),&f.s,reinterpret_cast<VLTyrellQueueResult*>(reinterpret_cast<std::byte*>(&f.s)+offset)));assert(!std::memcmp(&f.s,&old,sizeof old));++rejections;}
 for(size_t offset=0;offset<sizeof(VLTyrellQueueState);++offset){Fixture f;const auto old=f.s;const auto oldR=f.r;assert(!vl_tyrell_queue_step(reinterpret_cast<VLTyrellQueueDescriptor*>(reinterpret_cast<std::byte*>(&f.s)+offset),&f.s,&f.r));assert(!std::memcmp(&f.s,&old,sizeof old)&&!std::memcmp(&f.r,&oldR,sizeof oldR));++rejections;}
 for(size_t offset=0;offset<sizeof(std::array<VLTyrellQueueDescriptor,3>);++offset){Fixture f;const auto old=f.s;const auto oldD=f.d;assert(!vl_tyrell_queue_step(f.d.data(),&f.s,reinterpret_cast<VLTyrellQueueResult*>(reinterpret_cast<std::byte*>(f.d.data())+offset)));assert(!std::memcmp(&f.s,&old,sizeof old)&&!std::memcmp(f.d.data(),oldD.data(),sizeof oldD));++rejections;}
 {alignas(VLTyrellQueueState)std::array<std::byte,sizeof(VLTyrellQueueState)+8>bytes{};auto*s=new(bytes.data()+4)VLTyrellQueueState{};Fixture f;std::memcpy(s,&f.s,sizeof(*s));const auto old=bytes;assert(!vl_tyrell_queue_step(f.d.data(),s,reinterpret_cast<VLTyrellQueueResult*>(bytes.data()+1)));assert(bytes==old);++rejections;}
 {struct Adjacent{VLTyrellQueueState state;VLTyrellQueueResult result;std::array<VLTyrellQueueDescriptor,3>descriptors;}a{};Fixture f;a.state=f.s;a.descriptors=f.d;assert(vl_tyrell_queue_step(a.descriptors.data(),&a.state,&a.result));++success;}
 {VLTyrellQueueState s{};VLTyrellQueueResult r{};s.queue_count=-1;assert(vl_tyrell_queue_step(nullptr,&s,&r)&&s.queue_count==0&&r.visited_count==0);++success;}
 {VLTyrellQueueState s{};VLTyrellQueueResult r{};std::array<VLTyrellQueueDescriptor,213>d{};s.internal_count=s.special_count=s.pointee_count=213;s.queue_count=213;
  for(int32_t i=0;i<213;++i){s.records[i]={i,0,1,float(i)+.5f};s.queue[i]=i;d[i]={0,213,0,i};}
  assert(vl_tyrell_queue_step(d.data(),&s,&r)&&r.visited_count==213&&s.queue_count==0&&s.changed[0]==0);
  for(int32_t i=0;i<213;++i){assert(s.records[i].remaining==-1&&s.pointee_words[i]==std::bit_cast<uint32_t>(float(i)+.5f));if(i)assert(s.changed[i]==213-i);}++success;
 }
 std::cout<<"{\"status\":\"passed_queue_consumer_contract\",\"success_cases\":"<<success<<",\"atomic_rejections\":"<<rejections<<",\"full_plugin_equivalence\":false}\n";
}

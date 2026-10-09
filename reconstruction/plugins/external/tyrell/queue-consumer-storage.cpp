#include "queue-consumer-storage.h"
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
namespace {
bool overlap(const void*a,size_t an,const void*b,size_t bn){
 const uintptr_t x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);
 if(an>std::numeric_limits<uintptr_t>::max()-x||bn>std::numeric_limits<uintptr_t>::max()-y)return true;
 return an&&bn&&x<y+bn&&y<x+an;
}
bool bounded(float value,float limit){return std::isfinite(value)&&std::fabs(value)<=limit;}
}
static_assert(sizeof(VLTyrellQueueRecord)==16);
extern "C" int vl_tyrell_queue_step(const VLTyrellQueueDescriptor*d,VLTyrellQueueState*s,VLTyrellQueueResult*r){
 if(!s||!r)return 0;
 const uint32_t n=s->internal_count,k=s->special_count,p=s->pointee_count;
 if(n>213||k>n||p>213||s->xy_count||s->xy_targets_per_control||s->queue_count< -1||s->queue_count>int32_t(k))return 0;
 if((n&&!d)||overlap(s,sizeof(*s),r,sizeof(*r))||overlap(d,size_t(n)*sizeof(*d),s,sizeof(*s))||overlap(d,size_t(n)*sizeof(*d),r,sizeof(*r)))return 0;
 for(uint32_t i=0;i<n;++i){
  if(!bounded(s->raw[i],32768)||!bounded(d[i].minimum,4096)||!bounded(d[i].maximum,4096)||d[i].minimum>d[i].maximum||d[i].pointee_index< -1||d[i].pointee_index>=int32_t(p))return 0;
 }
 for(uint32_t i=0;i<k;++i){
  const auto&x=s->records[i];if(x.identifier<0||x.identifier>=int32_t(n)||!bounded(x.increment,8192)||!bounded(x.target,4096)||x.remaining< -1||x.remaining>50)return 0;
 }
 for(int32_t i=0;i<s->queue_count;++i){
  const int32_t slot=s->queue[i];if(slot<0||slot>=int32_t(k)||d[s->records[slot].identifier].pointee_index<0)return 0;
 }
 VLTyrellQueueState next;std::memcpy(&next,s,sizeof next);uint32_t visited=0;
 if(next.queue_count== -1)next.queue_count=0;
 for(int32_t index=0;index<next.queue_count;){
  auto&record=next.records[next.queue[index]];const int32_t id=record.identifier,old=record.remaining;
  record.remaining=old-1;
  if(old<=1){
   record.remaining= -1;next.raw[id]=record.target;--next.queue_count;
   if(index<next.queue_count)next.queue[index]=next.queue[next.queue_count];
  }else{
   float value=record.increment+next.raw[id];
   if(d[id].flags&0x200u){const float range=d[id].maximum-d[id].minimum;if(value<d[id].minimum)value=value+range;if(d[id].maximum<value)value=value-range;}
   if(!bounded(value,32768))return 0;next.raw[id]=value;++index;
  }
  next.marks[id]=int32_t(visited);next.changed[visited++]=id;
 }
 for(uint32_t i=visited;i>0;--i){const int32_t id=next.changed[i-1];next.pointee_words[d[id].pointee_index]=std::bit_cast<uint32_t>(next.raw[id]);}
 next.dirty=0;const VLTyrellQueueResult result{visited};std::memcpy(s,&next,sizeof next);std::memcpy(r,&result,sizeof result);return 1;
}

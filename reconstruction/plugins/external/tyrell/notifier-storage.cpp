#include "notifier-storage.h"
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstring>
namespace {
bool overlap(const void*a,size_t an,const void*b,size_t bn){
 const auto x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);
 return x<=y?y-x<an:x-y<bn;
}
bool bounded(float x,float limit){return std::isfinite(x)&&std::fabs(x)<=limit;}
}
extern "C" int vl_tyrell_notifier_storage(const VLTyrellNotifyDescriptor*d,
 VLTyrellNotifyState*s,int32_t id,uint32_t force,float value,
 VLTyrellNotifyResult*out){
 if(!d||!s||!out||force>255||!bounded(value,8192)||
    overlap(s,sizeof(*s),out,sizeof(*out))||s->internal_count>213||
    s->special_count>213||id<0||uint32_t(id)>=s->internal_count||
    s->queue_count < -1||s->queue_count>int32_t(s->special_count)||
    s->dirty<0||s->dirty>1||s->immediate>255)return 0;
 const size_t descriptorBytes=size_t(s->internal_count)*sizeof(*d);
 if(overlap(d,descriptorBytes,s,sizeof(*s))||
    overlap(d,descriptorBytes,out,sizeof(*out)))return 0;
 for(uint32_t i=0;i<s->internal_count;++i)
  if(!bounded(s->raw[i],4096)||d[i].pointer_present>1)return 0;
 for(uint32_t i=0;i<s->special_count;++i){const auto&r=s->special[i];
  if(r.identifier<0||uint32_t(r.identifier)>=s->internal_count||
     !bounded(r.increment,8192)||!bounded(r.target,4096)||
     r.remaining< -1||r.remaining>50)return 0;
 }
 for(int32_t i=0;i<s->queue_count;++i)
  if(s->queue[i]<0||uint32_t(s->queue[i])>=s->special_count)return 0;
 const auto meta=d[id];
 if(!bounded(meta.minimum,4096)||!bounded(meta.maximum,4096)||
    meta.minimum>meta.maximum)return 0;
 const auto low=uint8_t(uint32_t(meta.type));
 VLTyrellNotifyResult result{};
 result.clipped=value;
 result.effective_immediate=s->immediate||s->queue_count==-1||
                            s->depth>0||force;
 if(low==3||low==4){result.ignored=1;std::memcpy(out,&result,sizeof result);return 1;}
 if(meta.type!=0&&meta.type!=1)return 0;
 auto next=*s;
 if(value>meta.maximum)value=meta.maximum;
 if(value<meta.minimum)value=meta.minimum;
 result.clipped=value;
 bool direct=true;
 if(meta.flags&2){
  const int32_t slot=meta.special_index;
  if(slot<0||uint32_t(slot)>=next.special_count||
     next.special[slot].identifier!=id)return 0;
  bool queued=false;
  for(int32_t i=0;i<next.queue_count;++i)queued|=next.queue[i]==slot;
  auto&r=next.special[slot];
  if(!queued&&r.remaining>0){
   r.remaining=0;r.increment=0;r.target=value;next.raw[id]=value;
  }
  const float scale=result.effective_immediate?1.0f:0.02f;
  const int32_t duration=result.effective_immediate?1:50;
  if(result.effective_immediate)next.raw[id]=value;
  const float previous=r.target;
  r.target=value;
  float difference=value-next.raw[id];
  if(!queued&&difference==0){next.dirty=1;result.effective_immediate=1;}
  if(meta.flags&0x200){
   const float wrap=difference<0?meta.maximum:-meta.maximum;
   const float alternate=difference+wrap;
   if(std::fabs(alternate)<std::fabs(difference))difference=alternate;
  }
  const int32_t oldRemaining=r.remaining;
  if(previous!=value){r.increment=scale*difference;r.remaining=duration;}
  direct=result.effective_immediate!=0;
  if(oldRemaining<=0){
   if(direct){
    r.remaining=0;r.increment=0;next.raw[id]=value;
    if(meta.pointer_present)next.pointee_bits[id]=std::bit_cast<uint32_t>(value);
   }else{
    if(next.queue_count<0)next.queue_count=0;
    if(uint32_t(next.queue_count)>=next.special_count)return 0;
    next.queue[next.queue_count++]=slot;
   }
  }
 }
 if(direct){
  next.raw[id]=meta.type==0?std::floor(value+0.5f):value;
  if(meta.pointer_present){
   if(meta.type==0){
    next.pointee_bits[id]=uint32_t(int32_t(std::floor(value+0.5f)));
    result.unit_activity_needed=1;
   }else next.pointee_bits[id]=std::bit_cast<uint32_t>(value);
  }
 }
 result.unit_set_needed=!meta.pointer_present||(meta.flags&0x80)!=0;
 result.property_needed=(meta.flags&0x20)!=0;
 std::memcpy(s,&next,sizeof next);std::memcpy(out,&result,sizeof result);
 return 1;
}

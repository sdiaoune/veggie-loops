#include "xy-api.h"
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#if defined(__x86_64__)
#include <xmmintrin.h>
#endif
#pragma STDC FENV_ACCESS ON

namespace {
bool overlap(const void* a,size_t an,const void* b,size_t bn) {
 const uintptr_t x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);
 if(an>std::numeric_limits<uintptr_t>::max()-x||bn>std::numeric_limits<uintptr_t>::max()-y)return true;
 return an&&bn&&x<y+bn&&y<x+an;
}
// Positive finite limits are compile-time domain constants. Magnitude and
// endpoint ordering use integer bits so unused subnormals/sNaNs are not
// evaluated as FP operands during validation. Actual XY math stays below.
bool bounded(float x,float limit) {
 return (std::bit_cast<uint32_t>(x)&0x7fffffffu)<=std::bit_cast<uint32_t>(limit);
}
bool finiteGreater(float left,float right) {
 const uint32_t a=std::bit_cast<uint32_t>(left),b=std::bit_cast<uint32_t>(right);
 if(((a|b)&0x7fffffffu)==0)return false; // Both signed zeros compare equal.
 const uint32_t ka=(a&0x80000000u)?~a:(a^0x80000000u);
 const uint32_t kb=(b&0x80000000u)?~b:(b^0x80000000u);
 return ka>kb;
}
float absoluteBits(float x) { return std::bit_cast<float>(std::bit_cast<uint32_t>(x)&0x7fffffffu); }
bool floatingDomain() {
 if(std::fegetround()!=FE_TONEAREST)return false;
#if defined(__x86_64__)
 const uint32_t csr=_mm_getcsr();return (csr&0xe040u)==0&&(csr&0x1f80u)==0x1f80u;
#elif defined(__aarch64__)
 uint64_t control;asm volatile("mrs %0, fpcr":"=r"(control));return (control&((1ull<<24)|(0x1full<<8)))==0;
#else
 return true; // Other targets must satisfy the declared gradual/masked domain.
#endif
}
}
static_assert(sizeof(VLTyrellXYDescriptor)==12&&sizeof(VLTyrellXYRecord)==16);
extern "C" int vl_tyrell_xy_step(const VLTyrellXYDescriptor* d,uint32_t capacity,VLTyrellXYState* s,VLTyrellXYResult* r) {
 if(!d||!s||!r||capacity<2||capacity>213)return 0;
 if(overlap(d,size_t(capacity)*sizeof(*d),s,sizeof(*s))||overlap(d,size_t(capacity)*sizeof(*d),r,sizeof(*r))||overlap(s,sizeof(*s),r,sizeof(*r)))return 0;
 const uint32_t n=s->internal_count,x=s->xy_count,t=s->targets_per_control,m=s->cell_count;
 if(n!=capacity||n<2||n>213||x<1||x>4||t<1||t>16||x*t>64||m<1||m>n||(s->queue_count!=0&&s->queue_count!=-1)||!floatingDomain())return 0;
 uint32_t controls[4]{},found=0;
 for(uint32_t id=0;id<n;++id) {
  if(!bounded(d[id].minimum,1024)||!bounded(d[id].maximum,1024)||finiteGreater(d[id].minimum,d[id].maximum)||!bounded(s->raw[id],1024)||s->cell_slots[id]<0||s->cell_slots[id]>=int32_t(m)||(s->marks[id]!=-1&&s->marks[id]!=-3&&s->marks[id]!=0))return 0;
  if(d[id].full_type==2) {
   if(id==0||found>=x||!bounded(s->raw[id],100))return 0;
   controls[found++]=id;
  }
 }
 if(found!=x)return 0;
 for(uint32_t i=0;i<m;++i)if(!bounded(s->cells[i],1024))return 0;
 for(uint32_t i=0;i<x*t;++i) {
  const auto& v=s->records[i];
  if(v.target_id< -1||v.target_id>=int32_t(n)||!bounded(v.negative_depth,100)||!bounded(v.positive_depth,100))return 0;
 }
 VLTyrellXYState next;std::memcpy(&next,s,sizeof next);uint32_t touchedCount=0;
 if(next.queue_count==-1)next.queue_count=0;
 for(uint32_t group=0;group<x;++group) {
  const float coordinate=next.raw[controls[group]];
  const bool positive=coordinate>0; // Original evaluates this before target skipping.
  for(uint32_t j=0;j<t;++j) {
   auto& record=next.records[group*t+j];const int32_t id=record.target_id;
   if(id<0)continue;
   next.touched[touchedCount++]=id;
   float contribution;
   if(positive) {const float product=record.positive_depth*coordinate;contribution=product*0.01f;}
   else {const float product=record.negative_depth*coordinate;contribution=product*-0.01f;}
   record.last_contribution=contribution;float& cell=next.cells[next.cell_slots[id]];
   if(next.marks[id]==-3)cell=contribution+cell;
   else {cell=contribution+next.raw[id];next.marks[id]=-3;}
  }
 }
 next.dirty=0;
 for(uint32_t i=0;i<touchedCount;++i) {
  const int32_t id=next.touched[i];
  if(next.marks[id]==-1)continue;
  next.marks[id]=-1;float& cell=next.cells[next.cell_slots[id]];
  const float lower=absoluteBits(cell-d[id].minimum);
  const float first=lower+d[id].maximum;
  const float second=first+d[id].minimum;
  const float upper=absoluteBits(cell-d[id].maximum);
  const float difference=second-upper;
  cell=difference*0.5f;
 }
 const VLTyrellXYResult result{touchedCount};std::memcpy(s,&next,sizeof next);std::memcpy(r,&result,sizeof result);return 1;
}

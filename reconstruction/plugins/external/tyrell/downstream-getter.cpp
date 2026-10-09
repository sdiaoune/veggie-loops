#include "downstream-getter.h"
#include <cstddef>
#include <array>
#include <cstdint>
#include <cstring>
namespace {
static_assert(sizeof(void*)==8);
static bool overlaps(const void*a,size_t an,const void*b,size_t bn){const auto x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);return x<=y?y-x<an:x-y<bn;}
template<class T>T read(const void*p,size_t offset){T value;std::memcpy(&value,static_cast<const unsigned char*>(p)+offset,sizeof value);return value;}
}
extern "C" int vl_tyrell_raw_get(const VLTyrellRawView*v,int32_t index,int32_t flag,
                                  float fallback,float*output){
 (void)fallback;
 if(!output||index<0||(flag!=0&&flag!=1)||index>=(flag?92:213))return 0;
 uint32_t result=0;
 if(!v){std::memcpy(output,&result,4);return 1;}
 if(overlaps(v,sizeof(*v),output,4)||v->internal_count>213||v->public_count>92||v->special_count>213)return 0;
 struct Span{const void*p;size_t n;};
 for(const auto pair:std::array<Span,6>{{{v->descriptors,size_t(v->internal_count)*116},
                      Span{v->raw_values,size_t(v->internal_count)*4},Span{v->parameter_pointers,size_t(v->internal_count)*8},
                      Span{v->special_map,size_t(v->internal_count)*4},Span{v->special_records,size_t(v->special_count)*16},
                      Span{v->public_map,size_t(v->public_count)*4}}})
  if(pair.p&&pair.n&&overlaps(pair.p,pair.n,output,4))return 0;
 int32_t id=index;
 if(flag){if(!v->public_map||uint32_t(index)>=v->public_count)return 0;id=read<int32_t>(v->public_map,size_t(index)*4);}
 if(id<0||uint32_t(id)>=v->internal_count)return 0;
 if(v->parameter_pointers)for(uint32_t i=0;i<v->internal_count;++i){const void*p=read<const void*>(v->parameter_pointers,size_t(i)*8);if(p&&overlaps(p,4,output,4))return 0;}
 if(!v->descriptors){std::memcpy(output,&result,4);return 1;}
 const size_t slot=size_t(id);
 const int32_t type=read<int32_t>(v->descriptors,slot*116+72);
 const uint32_t flags=read<uint32_t>(v->descriptors,slot*116+92);
 if(flags&2u){
  if(!v->special_map||!v->special_records)return 0;
  const int32_t special=read<int32_t>(v->special_map,slot*4);
  if(special<0||uint32_t(special)>=v->special_count)return 0;
  result=read<uint32_t>(v->special_records,size_t(special)*16+12);
 }else{
  if((type==0||type==3)&&!v->parameter_pointers)return 0;
  const void*p=v->parameter_pointers?read<const void*>(v->parameter_pointers,slot*8):nullptr;
  if(type==0&&p){const float value=float(read<int32_t>(p,0));std::memcpy(&result,&value,4);}
  else if(type==3){if(!p)return 0;result=read<uint32_t>(p,0);}
  else{if(!v->raw_values)return 0;result=read<uint32_t>(v->raw_values,slot*4);}
 }
 std::memcpy(output,&result,4);return 1;
}

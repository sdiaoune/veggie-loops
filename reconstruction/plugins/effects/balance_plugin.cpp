#include "balance_plugin.h"
#include "balance_dsp.hpp"
#include <bit>
#include <cmath>
#include <cstring>
#include <new>

struct VLBalancePlugin {
  veggie_loops::balance::Controls controls;
  veggie_loops::balance::State state;
  float maximumStep = static_cast<float>(0.001) * 10.0f;
  VLBalancePlugin() {
    veggie_loops::balance::parameter(controls,state,0,0,1,320);
    veggie_loops::balance::parameter(controls,state,1,256,1,320);
  }
};

namespace {
// Live caller buffers must not overlap any bytes of the plugin instance.
// Ordered unsigned differences avoid computing a possibly wrapped end address.
bool spans_overlap(const void* a, size_t a_size, const void* b, size_t b_size) {
  if(a_size==0 || b_size==0)return false;
  const auto x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);
  return x<=y ? y-x<a_size : x-y<b_size;
}
bool overlaps_instance(const VLBalancePlugin* plugin,const void* data,size_t size) {
  return spans_overlap(plugin,sizeof(*plugin),data,size);
}
}

extern "C" {
VLBalancePlugin* vl_balance_create(void){return new(std::nothrow) VLBalancePlugin;}
void vl_balance_destroy(VLBalancePlugin*plugin){delete plugin;}
int vl_balance_parameter(VLBalancePlugin*plugin,int32_t index,int32_t value,
                         uint32_t flags,int32_t*result){
  if(!plugin || !result || index<0 || index>1 || flags&~35u)return 0;
  if(overlaps_instance(plugin,result,sizeof(*result)))return 0;
  if(flags&32){if(value<0 || value>0x40000000)return 0;}
  else if(flags&1){if(value<(index==0?-128:0) || value>(index==0?128:320))return 0;}
  *result=veggie_loops::balance::parameter(plugin->controls,plugin->state,index,value,flags,320);
  return 1;
}
int vl_balance_set_sample_rate(VLBalancePlugin*plugin,int32_t sample_rate){
  if(!plugin || sample_rate<8000 || sample_rate>192000)return 0;
  plugin->maximumStep=static_cast<float>((44100.0/static_cast<double>(sample_rate))*0.001)*10.0f;
  return 1;
}
void vl_balance_resume(VLBalancePlugin*plugin){
  if(plugin)for(size_t i=0;i<4;++i)plugin->state.current[i]=static_cast<float>(plugin->state.target[i]);
}
int vl_balance_render(VLBalancePlugin*plugin,const float*source,float*destination,int32_t frames){
  if(!plugin || !source || !destination || frames<0 || frames>1024)return 0;
  const auto start=reinterpret_cast<uintptr_t>(source),end=reinterpret_cast<uintptr_t>(destination);
  const auto size=static_cast<uintptr_t>(frames)*2*sizeof(float);
  if(overlaps_instance(plugin,source,size) || overlaps_instance(plugin,destination,size))return 0;
  if(start!=end && (start<end?end-start:start-end)<size)return 0;
  for(int32_t i=0;i<2*frames;++i)if(!std::isfinite(source[i]))return 0;
  veggie_loops::balance::process(plugin->state,source,destination,frames,plugin->maximumStep,0x1p-24f);
  return 1;
}
int vl_balance_get_meters(const VLBalancePlugin*plugin,float*left,float*right){
  if(!plugin || !left || !right)return 0;
  if(overlaps_instance(plugin,left,sizeof(*left)) || overlaps_instance(plugin,right,sizeof(*right)) ||
     spans_overlap(left,sizeof(*left),right,sizeof(*right)))return 0;
  *left=plugin->state.meters[0];*right=plugin->state.meters[1];return 1;
}
int vl_balance_save_state(const VLBalancePlugin*plugin,void*bytes,size_t size){
  if(!plugin || !bytes || size!=8)return 0;
  if(overlaps_instance(plugin,bytes,size))return 0;
  auto*out=static_cast<uint8_t*>(bytes);
  for(size_t i=0;i<2;++i){const auto bits=std::bit_cast<uint32_t>(plugin->controls.raw[i]);
    for(size_t j=0;j<4;++j)out[4*i+j]=static_cast<uint8_t>(bits>>(8*j));}
  return 1;
}
int vl_balance_restore_state(VLBalancePlugin*plugin,const void*bytes,size_t size){
  if(!plugin || !bytes || size!=8)return 0;
  if(overlaps_instance(plugin,bytes,size))return 0;
  const auto*input=static_cast<const uint8_t*>(bytes);int32_t values[2]{};
  for(size_t i=0;i<2;++i){uint32_t bits=0;for(size_t j=0;j<4;++j)bits|=uint32_t(input[4*i+j])<<(8*j);values[i]=std::bit_cast<int32_t>(bits);}
  if(values[0]<-128 || values[0]>128 || values[1]<0 || values[1]>320)return 0;
  for(int32_t i=0;i<2;++i)veggie_loops::balance::parameter(plugin->controls,plugin->state,i,values[i],1,320);
  return 1;
}
}

#include "stereo_shaper_plugin.h"
#include "stereo_shaper_dsp.hpp"
#include <new>
#include <utility>

struct VLStereoShaperPlugin {vl::stereo_shaper::Processor processor;};
namespace {
bool legalValue(int32_t index,int32_t value){return index>=0 && index<6 && (index<4?value>=-25600&&value<=25600:value>=-4096&&value<=4096);}
bool legalRate(int32_t rate){return rate==22050||rate==44100||rate==48000||rate==96000||rate==192000;}
bool legalRouting(int32_t index,int32_t mode){return index>=0&&index<=3&&mode>=0&&mode<=1;}
void word(uint8_t* p,uint32_t value){for(size_t i=0;i<4;++i)p[i]=uint8_t(value>>(i*8));}
uint32_t word(const uint8_t*p){uint32_t value=0;for(size_t i=0;i<4;++i)value|=uint32_t(p[i])<<(i*8);return value;}
bool overlaps(const void*a,const void*b,size_t size){const auto x=reinterpret_cast<uintptr_t>(a),y=reinterpret_cast<uintptr_t>(b);return (x<y?y-x:x-y)<size;}
}
extern "C" {
VLStereoShaperPlugin* vl_stereo_shaper_create(void){return new(std::nothrow)VLStereoShaperPlugin;}
void vl_stereo_shaper_destroy(VLStereoShaperPlugin* plugin){delete plugin;}
int vl_stereo_shaper_parameter(VLStereoShaperPlugin* plugin,int32_t index,int32_t value,uint32_t flags,int32_t* result){
  if(!plugin||!result||index<0||index>=6||flags&~35u)return 0;
  if(flags&32){if(value<0||value>0x40000000)return 0;const int32_t low=index<4?-25600:-4096,range=index<4?51200:8192;value=int32_t(std::nearbyint((double(value)*0x1p-30)*double(range)))+low;}
  if((flags&1)&&!legalValue(index,value))return 0;
  try{if(flags&1){if(index==4){auto candidate=plugin->processor;candidate.parameter(index,value);plugin->processor=std::move(candidate);}else plugin->processor.parameter(index,value);}else if(flags&2)value=plugin->processor.raw[size_t(index)];}catch(const std::bad_alloc&){return 0;}
  *result=value;return 1;
}
int vl_stereo_shaper_sample_rate(VLStereoShaperPlugin* plugin,int32_t rate){if(!plugin||!legalRate(rate))return 0;try{auto candidate=plugin->processor;candidate.changeRate(rate);plugin->processor=std::move(candidate);}catch(const std::bad_alloc&){return 0;}return 1;}
int vl_stereo_shaper_resume(VLStereoShaperPlugin* plugin){if(!plugin)return 0;plugin->processor.resume();return 1;}
int vl_stereo_shaper_routing(VLStereoShaperPlugin* plugin,int32_t index,int32_t mode){if(!plugin||!legalRouting(index,mode))return 0;plugin->processor.send=index;plugin->processor.prePost=mode;return 1;}
int vl_stereo_shaper_get_routing(const VLStereoShaperPlugin* plugin,int32_t* index,int32_t* mode){if(!plugin||!index||!mode)return 0;*index=plugin->processor.send;*mode=plugin->processor.prePost;return 1;}
int vl_stereo_shaper_render(VLStereoShaperPlugin* plugin,const float* input,float* output,int32_t count,float* side){
  if(!plugin||!input||!output||count<0||count>1024)return 0;const size_t bytes=size_t(count)*8;
  if(input!=output&&overlaps(input,output,bytes))return 0;if(side&&(overlaps(side,input,bytes)||overlaps(side,output,bytes)))return 0;
  for(size_t i=0;i<size_t(count)*2;++i)if(!std::isfinite(input[i])||std::abs(input[i])>4.0f||(side&&!std::isfinite(side[i])))return 0;
  plugin->processor.render(input,output,count,side);return 1;
}
int vl_stereo_shaper_save_state(const VLStereoShaperPlugin* plugin,void* bytes,size_t size){
  if(!plugin||!bytes||size!=36)return 0;auto*out=static_cast<uint8_t*>(bytes);word(out,0);for(size_t i=0;i<6;++i)word(out+4+i*4,std::bit_cast<uint32_t>(plugin->processor.raw[i]));word(out+28,uint32_t(plugin->processor.send));word(out+32,uint32_t(plugin->processor.prePost));return 1;
}
int vl_stereo_shaper_restore_state(VLStereoShaperPlugin* plugin,const void* bytes,size_t size){
  if(!plugin||!bytes||size!=36)return 0;const auto*in=static_cast<const uint8_t*>(bytes);if(word(in)!=0)return 0;std::array<int32_t,6>raw{};for(size_t i=0;i<6;++i){raw[i]=std::bit_cast<int32_t>(word(in+4+i*4));if(!legalValue(int32_t(i),raw[i]))return 0;}const int32_t send=std::bit_cast<int32_t>(word(in+28)),mode=std::bit_cast<int32_t>(word(in+32));if(!legalRouting(send,mode))return 0;
  try{auto candidate=plugin->processor;for(int i=0;i<6;++i)candidate.parameter(i,raw[size_t(i)]);candidate.send=send;candidate.prePost=mode;plugin->processor=std::move(candidate);}catch(const std::bad_alloc&){return 0;}return 1;
}
}

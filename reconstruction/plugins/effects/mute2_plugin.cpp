#include "mute2_plugin.h"
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <new>

struct VLMute2Plugin {
  std::array<int32_t,2> raw{512,512};
  bool muted=false;
  int32_t channels=1;
  void update(int32_t index,int32_t value){
    raw[index]=value;
    const float unit=static_cast<float>(static_cast<double>(value)*(1.0/1024.0));
    if(index==0)muted=unit<0.5f;
    else channels=std::min(static_cast<int32_t>(unit/(1.0f/3.0f)),2);
  }
};
namespace {
void writeWord(uint8_t* p,uint32_t value){for(size_t i=0;i<4;++i)p[i]=static_cast<uint8_t>(value>>(8*i));}
uint32_t readWord(const uint8_t* p){uint32_t result=0;for(size_t i=0;i<4;++i)result|=uint32_t(p[i])<<(8*i);return result;}
}
extern "C" {
VLMute2Plugin* vl_mute2_create(void){return new(std::nothrow) VLMute2Plugin;}
void vl_mute2_destroy(VLMute2Plugin* plugin){delete plugin;}
int vl_mute2_parameter(VLMute2Plugin* plugin,int32_t index,int32_t value,uint32_t flags,int32_t* result){
  if(!plugin || !result || index<0 || index>1 || flags&~35u)return 0;
  if(flags&32){
    if(value<0 || value>0x40000000)return 0;
    value=static_cast<int32_t>(std::nearbyint(static_cast<double>(value)*0x1p-30*1024.0));
  }else if((flags&1) && (value<0 || value>1024))return 0;
  if(flags&1)plugin->update(index,value);
  else if(flags&2)value=plugin->raw[index];
  *result=value;return 1;
}
int vl_mute2_render(VLMute2Plugin* plugin,const float* input,float* output,int32_t frames){
  if(!plugin || !input || !output || frames<0 || frames>1024)return 0;
  const auto a=reinterpret_cast<uintptr_t>(input),b=reinterpret_cast<uintptr_t>(output);
  const auto size=static_cast<size_t>(frames)*2*sizeof(float);
  if(a!=b && (a<b?b-a:a-b)<size)return 0;
  for(int32_t i=0;i<2*frames;++i)if(!std::isfinite(input[i]))return 0;
  if(!plugin->muted){if(input!=output)std::memcpy(output,input,size);}
  else if(plugin->channels==1)std::memset(output,0,size);
  else {
    const float left=plugin->channels==0?0.0f:1.0f,right=plugin->channels==2?0.0f:1.0f;
    for(int32_t i=0;i<frames;++i){const float a=input[2*i],b=input[2*i+1];output[2*i]=a*left;output[2*i+1]=b*right;}
  }
  return 1;
}
int vl_mute2_save_state(const VLMute2Plugin* plugin,void* bytes,size_t size){
  if(!plugin || !bytes || size!=12)return 0;
  auto* output=static_cast<uint8_t*>(bytes);writeWord(output,1);
  for(size_t i=0;i<2;++i)writeWord(output+4+4*i,std::bit_cast<uint32_t>(plugin->raw[i]));
  return 1;
}
int vl_mute2_restore_state(VLMute2Plugin* plugin,const void* bytes,size_t size){
  if(!plugin || !bytes || size!=12)return 0;
  const auto* input=static_cast<const uint8_t*>(bytes);if(readWord(input)>1)return 0;
  const std::array<int32_t,2> values{std::bit_cast<int32_t>(readWord(input+4)),std::bit_cast<int32_t>(readWord(input+8))};
  if(values[0]<0 || values[0]>1024 || values[1]<0 || values[1]>1024)return 0;
  for(int32_t i=0;i<2;++i)plugin->update(i,values[i]);return 1;
}
}

#include "phase_inverter_plugin.h"
#include <bit>
#include <cmath>
#include <cstring>
#include <new>

struct VLPhaseInverterPlugin {
  int32_t raw=1024;
  int32_t channel=2;
  void update(int32_t value){
    raw=value;
    const float unit=static_cast<float>(static_cast<double>(value)*0x1p-10);
    const float selector=unit*3.0f-0.5f;
    channel=static_cast<int32_t>(std::nearbyint(static_cast<double>(selector)));
  }
};
namespace {
void word(uint8_t* bytes,uint32_t value){for(size_t i=0;i<4;++i)bytes[i]=static_cast<uint8_t>(value>>(8*i));}
uint32_t word(const uint8_t* bytes){uint32_t value=0;for(size_t i=0;i<4;++i)value|=uint32_t(bytes[i])<<(8*i);return value;}
}
extern "C" {
VLPhaseInverterPlugin* vl_phase_inverter_create(void){return new(std::nothrow) VLPhaseInverterPlugin;}
void vl_phase_inverter_destroy(VLPhaseInverterPlugin* plugin){delete plugin;}
int vl_phase_inverter_parameter(VLPhaseInverterPlugin* plugin,int32_t index,int32_t value,uint32_t flags,int32_t* result){
  if(!plugin || !result || index!=0 || flags&~35u)return 0;
  if(flags&32){
    if(value<0 || value>0x40000000)return 0;
    value=static_cast<int32_t>(std::nearbyint(static_cast<double>(value)*0x1p-30*1024.0));
  }else if((flags&1) && (value<0 || value>1024))return 0;
  if(flags&1)plugin->update(value);
  else if(flags&2)value=plugin->raw;
  *result=value;return 1;
}
int vl_phase_inverter_render(VLPhaseInverterPlugin* plugin,const float* input,float* output,int32_t frames){
  if(!plugin || !input || !output || frames<0 || frames>1024)return 0;
  const auto a=reinterpret_cast<uintptr_t>(input),b=reinterpret_cast<uintptr_t>(output);
  const auto bytes=static_cast<size_t>(frames)*2*sizeof(float);
  if(a!=b && (a<b?b-a:a-b)<bytes)return 0;
  if(input!=output)std::memcpy(output,input,bytes);
  if(plugin->channel>0){
    const int32_t selected=plugin->channel==2?1:0;
    for(int32_t i=0;i<frames;++i){
      uint32_t value;std::memcpy(&value,output+2*i+selected,sizeof(value));
      value^=0x80000000u;std::memcpy(output+2*i+selected,&value,sizeof(value));
    }
  }
  return 1;
}
int vl_phase_inverter_save_state(const VLPhaseInverterPlugin* plugin,void* bytes,size_t size){
  if(!plugin || !bytes || size!=8)return 0;
  auto* output=static_cast<uint8_t*>(bytes);word(output,1);word(output+4,std::bit_cast<uint32_t>(plugin->raw));return 1;
}
int vl_phase_inverter_restore_state(VLPhaseInverterPlugin* plugin,const void* bytes,size_t size){
  if(!plugin || !bytes || size!=8)return 0;
  const auto* input=static_cast<const uint8_t*>(bytes);if(word(input)>1)return 0;
  const auto value=std::bit_cast<int32_t>(word(input+4));if(value<0 || value>1024)return 0;
  plugin->update(value);return 1;
}
}

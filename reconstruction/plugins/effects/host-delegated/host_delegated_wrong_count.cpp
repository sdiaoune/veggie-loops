#include "host_delegated_native.h"
#include "fast_dist_dsp.hpp"
#include <bit>
#include <cstring>
#include <mutex>
#include <new>
#include <type_traits>
namespace {
using namespace veggie_loops::fast_dist::native;
using veggie_loops::fast_dist::host_delegated::DistWave;
struct Instance {Plugin header{};veggie_loops::fast_dist::Processor processor{};void*host=nullptr;};
static_assert(offsetof(Instance,header)==0);
static_assert(offsetof(Instance,processor)==sizeof(Plugin)&&sizeof(Instance)==208);
static_assert(std::is_standard_layout_v<Instance>);
Instance& object(Plugin*p){return *reinterpret_cast<Instance*>(p);}
constexpr std::array<int32_t,5> minimum{64,1,0,0,0},maximum{192,10,1,128,128};
bool validRaw(int32_t index,int32_t v){return v>=minimum[size_t(index)]&&v<=maximum[size_t(index)];}
bool overlaps(const Instance&i,const void*p,size_t n){const auto a=reinterpret_cast<uintptr_t>(&i),b=reinterpret_cast<uintptr_t>(p);return b>=a?b-a<sizeof(i):a-b<n;}
DistWave hostMethod(void*host){if(!host)return nullptr;void**table=nullptr;std::memcpy(&table,host,sizeof(table));return table?reinterpret_cast<DistWave>(table[veggie_loops::fast_dist::host_delegated::host_ordinal]):nullptr;}
const Info& commonInfo(){static Info info{};static std::once_flag once;std::call_once(once,[]{info.version=1;info.longName="VL Fast Dist host DSP";info.shortName="VL Host Dist";info.flags=1<<21;info.parameterCount=5;});return info;}
void destroy(Plugin*p){if(p)delete &object(p);}
intptr_t dispatch(Plugin*,intptr_t id,intptr_t index,intptr_t){if(id==52&&index>=0&&index<5)return index==2?9:5;return 0;}
void idle(Plugin*){}
void encode(const Instance&i,std::array<uint8_t,20>&bytes){for(size_t j=0;j<5;++j){const auto v=uint32_t(i.processor.raw[j]);for(size_t k=0;k<4;++k)bytes[j*4+k]=uint8_t(v>>(8*k));}}
bool restore(Instance&i,const std::array<uint8_t,20>&bytes){std::array<int32_t,5>raw{};for(size_t j=0;j<5;++j){uint32_t v=0;for(size_t k=0;k<4;++k)v|=uint32_t(bytes[j*4+k])<<(8*k);if(v<uint32_t(minimum[j])||v>uint32_t(maximum[j]))return false;raw[j]=int32_t(v);}auto next=i.processor;next.raw=raw;next.set(0,raw[0]);i.processor=next;return true;}
void state(Plugin*p,Stream*s,int32_t save){if(!s||!s->functions)return;auto&i=object(p);std::array<uint8_t,20>bytes{};using Transfer=int32_t(*)(Stream*,void*,uint32_t,void*);uint64_t count=0;if(save){encode(i,bytes);if(auto f=reinterpret_cast<Transfer>(s->functions[4]))f(s,bytes.data(),20,&count);}else if(auto f=reinterpret_cast<Transfer>(s->functions[3]);f&&f(s,bytes.data(),20,&count)>=0&&count==20)restore(i,bytes);}
void name(Plugin*,int32_t section,int32_t index,int32_t,char*out){constexpr std::array<const char*,5>names{"Pre Gain","Threshold","Type","Mix","Post Gain"};if(out)std::strcpy(out,section==0&&index>=0&&index<5?names[size_t(index)]:"");}
int32_t event(Plugin*,int32_t,int32_t,int32_t){return 0;}
int32_t parameter(Plugin*p,int32_t index,int32_t value,int32_t flags){if(index<0||index>=5)return 0;auto&i=object(p);const uint32_t f=uint32_t(flags)&35u;if(f&32u){if(value<0||value>(1<<30))return 0;value=int32_t(std::nearbyint(double(value)*0x1p-30*double(maximum[size_t(index)]-minimum[size_t(index)])))+minimum[size_t(index)];}if(((f&1u)||!(f&2u))&&!validRaw(index,value))return 0;if(f&1u)i.processor.set(index,value);else if(f&2u)value=i.processor.raw[size_t(index)];return value;}
int render(Plugin*p,const float*in,float*out,int32_t frames){if(!p||frames<0||frames>1024||(frames&&(!in||!out)))return 0;auto&i=object(p);const size_t n=size_t(frames)*8;if(overlaps(i,in,n)||overlaps(i,out,n))return 0;if(in!=out){const auto a=reinterpret_cast<uintptr_t>(in),b=reinterpret_cast<uintptr_t>(out);if((a>=b?a-b:b-a)<n)return 0;}for(int32_t j=0;j<2*frames;++j)if(!std::isfinite(in[j])||std::fabs(in[j])>16)return 0;auto host=hostMethod(i.host);if(!host)return 0;if(frames&&in!=out)std::memcpy(out,in,n);host(i.host,i.processor.raw[2],i.processor.raw[1],out,frames,i.processor.dry,i.processor.wet,i.processor.multiplier);return 1;}
void effect(Plugin*p,const float*in,float*out,int32_t frames){render(p,in,out,frames);}
void generator(Plugin*,float*,int32_t&n){n=0;}
intptr_t voice(Plugin*,void*,intptr_t){return -1;}
void voiceEnd(Plugin*,intptr_t){}
int32_t voiceEvent(Plugin*,intptr_t,intptr_t,intptr_t,intptr_t){return 0;}
int32_t voiceRender(Plugin*,intptr_t,float*,int32_t&n){n=0;return 0;}
void tick(Plugin*){}void midi(Plugin*,int32_t&){}void message(Plugin*,intptr_t){}
const Functions functions{destroy,dispatch,idle,state,name,event,parameter,effect,generator,voice,voiceEnd,voiceEnd,voiceEvent,voiceRender,tick,tick,midi,message,voiceEvent,voiceEnd,destroy,destroy};
}
extern "C" veggie_loops::balance::native::Plugin* CreatePlugInstance(void*host,intptr_t tag){if(!hostMethod(host))return nullptr;auto*i=new(std::nothrow)Instance;if(!i)return nullptr;i->host=host;i->header.functions=&functions;i->header.hostTag=tag;i->header.info=&commonInfo();return &i->header;}
extern "C" void* vl_private_fast_dist_host_pointer(Plugin*p){return p?object(p).host:nullptr;}
extern "C" int vl_private_fast_dist_host_coefficients(Plugin*p,float*out){if(!p||!out||overlaps(object(p),out,3*sizeof(float)))return 0;auto&i=object(p);out[0]=i.processor.dry;out[1]=i.processor.wet;out[2]=i.processor.multiplier;return 1;}
extern "C" int vl_private_fast_dist_host_render(Plugin*p,const float*in,float*out,int32_t frames){return render(p,in,out,frames);}

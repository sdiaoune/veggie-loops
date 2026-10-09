#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error Pinned native addresses require macOS arm64.
#endif
#include "three_osc_clock_context.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>
namespace {
void require(bool c,const char*s){if(!c)throw std::runtime_error(s);}
template<class T>T load(const void*p,size_t n){T x;std::memcpy(&x,static_cast<const char*>(p)+n,sizeof x);return x;}
template<class T>void store(void*p,size_t n,T x){std::memcpy(static_cast<char*>(p)+n,&x,sizeof x);}
template<class T>T method(void*p,size_t n){return load<T>(load<void*>(p,0),n);}
std::string sha(const char*p){std::ifstream s(p,std::ios::binary);require(bool(s),"Target absent");std::vector<char>b{std::istreambuf_iterator<char>(s),{}};std::array<unsigned char,32>d{};CC_SHA256(b.data(),CC_LONG(b.size()),d.data());std::ostringstream r;for(auto x:d)r<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(x);return r.str();}
struct SavedGlobals {
 char*base;std::array<size_t,12>offsets{0x19f9778,0x19f9744,0x19f9748,0x19f9750,0x19f9768,0x167dab8,0x19f9680,0x19f9790,0x167d358,0x167daec,0x167da78,0x19b4a2a};
 std::array<std::array<unsigned char,8>,12>bytes{};
 explicit SavedGlobals(char*p):base(p){for(size_t i=0;i<offsets.size();++i)std::memcpy(bytes[i].data(),base+offsets[i],8);}
 bool restore(){for(size_t i=0;i<offsets.size();++i)std::memcpy(base+offsets[i],bytes[i].data(),8);for(size_t i=0;i<offsets.size();++i)if(std::memcmp(base+offsets[i],bytes[i].data(),8)!=0)return false;return true;}
 ~SavedGlobals(){restore();}
};
struct NativePlugin { void**functions;intptr_t tag;void*info;intptr_t editor;int32_t mono,reserved[32]; };static_assert(sizeof(NativePlugin)==168);
struct Call {bool event=false;intptr_t id=0,index=0,value=0;uint32_t flags=0;std::array<int32_t,3>signature{};};
struct Capture {NativePlugin plugin{};std::array<Call,4>calls{};size_t count=0;};
Capture*capture=nullptr;
intptr_t pluginDispatch(NativePlugin*p,intptr_t id,intptr_t index,intptr_t value){require(p==&capture->plugin&&capture->count<4,"Unexpected delivery dispatch");auto&c=capture->calls[capture->count++];c={false,id,index,value,0,{}};if(id==14)std::memcpy(c.signature.data(),reinterpret_cast<const void*>(value),12);return 0;}
int32_t pluginEvent(NativePlugin*p,int32_t id,int32_t value,int32_t flags){require(p==&capture->plugin&&capture->count<4,"Unexpected delivery event");capture->calls[capture->count++]={true,id,0,value,uint32_t(flags),{}};return 0;}
struct Interface {void**vmt=nullptr;void*plugin=nullptr;int32_t refs=0;uint32_t retains=0,releases=0,getters=0;};
struct Holder {std::array<uint8_t,72>prefix{};Interface interface{};};static_assert(offsetof(Holder,interface)==0x48);
int32_t retain(Interface*p){++p->retains;return ++p->refs;}int32_t release(Interface*p){++p->releases;require(p->refs>0,"Unbalanced interface release");return --p->refs;}void*get(Interface*p){++p->getters;return p->plugin;}
struct SavedFEnv {
 fenv_t value{};SavedFEnv(){require(std::fegetenv(&value)==0,"Cannot snapshot fenv");}
 bool restore(){if(std::fesetenv(&value)!=0)return false;fenv_t current{};if(std::fegetenv(&current)!=0)return false;return std::memcmp(&current,&value,sizeof value)==0;}
 ~SavedFEnv(){std::fesetenv(&value);}
};
struct Packet{uint64_t lead;double time;uint64_t second;uint64_t tail;};static_assert(sizeof(Packet)==32);
}
int main(){@autoreleasepool{try {
 require(std::fegetround()==FE_TONEAREST,"Nearest-even required");uint64_t fpcr=0;asm volatile("mrs %0, fpcr":"=r"(fpcr));require((fpcr&(1ull<<24))==0,"Gradual underflow required");
 const char*path="/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib";require(sha(path)=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine identity changed");[NSApplication sharedApplication];void*image=dlopen(path,RTLD_NOW|RTLD_LOCAL);require(image,"Engine load failed");Dl_info info{};require(dladdr(dlsym(image,"CreateFruityInstance"),&info),"Engine base absent");auto*base=static_cast<char*>(info.dli_fbase);
 size_t cases=0,cachedCases=0,activeCases=0,futureCases=0,roundedCases=0,localCases=0,offsetCases=0,descriptors=0,notifications=0,retentions=0,rejected=0,fenvTicks=0,fenvDescriptors=0,fenvRestores=0,fenvDescriptorRetains=0;
 {
 SavedGlobals saved(base);
 // Synthetic host vtable routes CPP slot0 through the intact measured Pascal
 // implementation. Neither this host nor the sender is application-owned.
 std::array<void*,96>vmt{};vmt[0xc8/8]=base+0x3d00e0;std::array<uint8_t,512>host{},sender{};store<void*>(host.data(),0,vmt.data());
 using Ctor=void*(*)(void*,intptr_t,void*);void*adapter=reinterpret_cast<Ctor>(base+0xb4cd20)(base+0x1497870,1,host.data());require(adapter,"Adapter allocation failed");void*cpp=static_cast<char*>(adapter)+16;auto call=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t,intptr_t)>(cpp,0);
 std::mt19937_64 random(0x564c54494d45);for(size_t i=0;i<12064;++i){
  const bool active=i<12000&&i%3==1,future=i<12000&&i%3==2,rounded=i<12000?i%2!=0:i%12>=2,local=i%5==0;
  const double cached=i<12000?double(int64_t(random()%2000001)-1000000)/8.0:std::array<double,12>{0.0,-0.0,1.5,-1.5,2.5,-2.5,0x1p31+0.5,-0x1p31-0.5,0x1p32+0.5,-0x1p32-0.5,0x1p52,-0x1p52}[i%12];
  const int32_t tick=int32_t(random()%200001)-100000,position=int32_t(random()%200001)-100000,minimum=int32_t(random()%200001)-100000,latency=int32_t(random()%10001);
  const double fractional=double(int64_t(random()%20001)-10000)/8.0,samplesPerTick=std::array<double,6>{1.0,12.5,183.75,441.0,960.0,1920.125}[i%6];
  const int32_t mode=i<12000?(local?1:0):int32_t(i%3)-1,localStart=int32_t(random()%20001)-10000;
  const double input=i>=12000||i%4==0?0.0:double(int64_t(random()%200001)-100000)/16.0;
  store<double>(base,0x19f9778,cached);store<int32_t>(base,0x19f9744,tick);store<int32_t>(base,0x19f9748,position);store<double>(base,0x19f9750,fractional);store<int32_t>(base,0x19f9768,minimum);store<double>(base,0x167dab8,samplesPerTick);store<int32_t>(base,0x19f9680,mode);store<int32_t>(base,0x19f9790,localStart);
  store<uint8_t>(sender.data(),0x11c,uint8_t(active));store<int32_t>(sender.data(),0x130,latency);
  veggie_loops::three_osc::clock::TicksContext context{cached,fractional,samplesPerTick,tick,position,minimum,latency,mode,localStart,active,future,rounded};
  veggie_loops::three_osc::clock::TimePacket model{input,std::bit_cast<double>(0x7ff80000564c4142ULL)};
  require(veggie_loops::three_osc::clock::ticks(context,model),"Model context rejected");const double expected=model.t;
  require(std::bit_cast<uint64_t>(model.t2)==0x7ff80000564c4142ULL,"Model wrote t2");
  Packet packet{0xa5a55a5adeadcafeULL,input,0x7ff80000564c4142ULL,0x1234abcdef987654ULL};
  const intptr_t flags=4|(future?intptr_t(0x40000000):0)|(rounded?intptr_t(0x80000000):0);
  call(cpp,reinterpret_cast<intptr_t>(sender.data()),36,flags,reinterpret_cast<intptr_t>(&packet.time));
  if(std::bit_cast<uint64_t>(packet.time)!=std::bit_cast<uint64_t>(expected)){std::cerr<<"Case "<<i<<" expected="<<std::setprecision(17)<<expected<<" actual="<<packet.time<<'\n';throw std::runtime_error("GT_Ticks value differs");}
  require(packet.lead==0xa5a55a5adeadcafeULL&&packet.second==0x7ff80000564c4142ULL&&packet.tail==0x1234abcdef987654ULL,"Provider changed t2 or outer guard");
  ++cases;cachedCases+=!active&&!future;activeCases+=active;futureCases+=future;roundedCases+=rounded;localCases+=mode==1&&rounded;offsetCases+=input!=0;
 }
 // Focused cleared-mask cases distinguish FRINTX from nearbyint while
 // retaining the caller's complete fenv. General trap/FP-status parity is not
 // inferred from these nearest-even finite cached cases.
 {
  SavedFEnv environment;
  using namespace veggie_loops::three_osc::clock;
  struct RoundCase{double value;bool fractional;};
  const std::array<RoundCase,20>values{{{0,false},{-0.0,false},{1,false},{-1,false},{2,false},{-2,false},{1.5,true},{-1.5,true},{2.5,true},{-2.5,true},{3.5,true},{-3.5,true},{0x1p31,false},{-0x1p31,false},{0x1p31+0.5,true},{-0x1p31-0.5,true},{0x1p32+0.5,true},{-0x1p32-0.5,true},{0x1p52,false},{-0x1p52,false}}};
  for(const auto item:values)for(bool rounded:{false,true}){
   TicksContext c{};c.cachedTicks=item.value;c.roundLocal=rounded;
   store<double>(base,0x19f9778,c.cachedTicks);store<double>(base,0x167dab8,1);store<int32_t>(base,0x19f9680,0);store<int32_t>(base,0x19f9790,0);store<uint8_t>(sender.data(),0x11c,0);store<int32_t>(sender.data(),0x130,0);
   TimePacket model{0,std::bit_cast<double>(0x7ff0000000000001ULL)};Packet original{0xa5a55a5adeadcafeULL,0,0x7ff0000000000001ULL,0x1234abcdef987654ULL};
   require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Cannot clear model fenv");require(ticks(c,model),"Focused ticks rejected");const int modelMask=std::fetestexcept(FE_ALL_EXCEPT);
   require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Cannot clear original fenv");call(cpp,reinterpret_cast<intptr_t>(sender.data()),36,4|(rounded?intptr_t(0x80000000):0),reinterpret_cast<intptr_t>(&original.time));const int originalMask=std::fetestexcept(FE_ALL_EXCEPT);
   require(std::bit_cast<uint64_t>(model.t)==std::bit_cast<uint64_t>(original.time)&&modelMask==originalMask&&originalMask==(rounded&&item.fractional?FE_INEXACT:0),"Focused tick rounding bits/exception mask differs");
   require(std::bit_cast<uint64_t>(model.t2)==0x7ff0000000000001ULL&&original.second==0x7ff0000000000001ULL&&original.lead==0xa5a55a5adeadcafeULL&&original.tail==0x1234abcdef987654ULL,"Focused tick packet guards differ");++fenvTicks;
  }
  require(environment.restore(),"Focused tick fenv not restored");++fenvRestores;
 }
 // Original TExPlugin functions and their resolution helper execute intact.
 // Only the refcounted manager interface's getter/retention callbacks are
 // substituted; final dispatcher/event calls cross the original CPP adapter.
 std::array<void*,22>pluginFns{};pluginFns[1]=reinterpret_cast<void*>(&pluginDispatch);pluginFns[5]=reinterpret_cast<void*>(&pluginEvent);
 std::array<uint8_t,160>metadata{};Capture captured{};capture=&captured;captured.plugin.functions=pluginFns.data();captured.plugin.info=metadata.data();
 void*pluginAdapter=reinterpret_cast<Ctor>(base+0xb4c7c0)(base+0x1497618,1,&captured.plugin);require(pluginAdapter,"Plugin adapter allocation failed");
 std::array<void*,5>interfaceFns{};interfaceFns[1]=reinterpret_cast<void*>(&retain);interfaceFns[2]=reinterpret_cast<void*>(&release);interfaceFns[4]=reinterpret_cast<void*>(&get);Holder holder{};holder.interface.vmt=interfaceFns.data();holder.interface.plugin=pluginAdapter;
 auto ppqProducer=reinterpret_cast<void(*)(void*)>(base+0x32e000),tempoProducer=reinterpret_cast<void(*)(void*)>(base+0x32e1f0);
 for(size_t i=0;i<6000;++i){
  using namespace veggie_loops::three_osc::clock;
  DeliveryContext c{std::array<int32_t,6>{44100,48000,96000,22050,8000,384000}[i%6],int32_t(random()%64)+1,int32_t(random()%64)+1,int32_t(random()%((1<<20)-3))+4,std::array<float,6>{60,90,120,137,240,1000}[i%6],std::array<double,12>{1,1.5,2.5,12.5,183.75,441,960,1920.125,4294967295.0,4294967295.5,0x1p32,12000.25}[i%12]};
  Delivery model{};require(delivery(c,model),"Descriptor rejected");
  store<int32_t>(base,0x167d358,c.signatureFirst);store<int32_t>(base,0x167d35c,c.signatureSecond);store<int32_t>(base,0x167daec,c.ppq);store<float>(base,0x167da78,c.tempo);store<double>(base,0x167dab8,c.samplesPerTick);store<uint8_t>(base,0x19b4a2a,1);
  alignas(16)std::array<uint8_t,320>node{},expected{};store<void*>(node.data(),0,base+0x1076760);store<void*>(node.data(),0x18,&holder);store<int32_t>(node.data(),0x44,2);store<int32_t>(node.data(),0x130,0);for(size_t k=0;k<12;++k)node[0x120+k]=uint8_t(random());expected=node;std::memcpy(expected.data()+0x120,model.timeSignature.data(),12);
  captured.count=0;ppqProducer(node.data());tempoProducer(node.data());
  require(captured.count==4&&node==expected,"Delivery ordering or sender state differs");const auto&a=captured.calls;
  require(!a[0].event&&a[0].id==14&&a[0].index==0&&a[0].signature==model.timeSignature,"Time-signature packet differs");
  require(!a[1].event&&a[1].id==20&&a[1].index==0&&a[1].value==model.samplesPerTickDispatchValue,"First sample-clock packet differs");
  require(a[2].event&&a[2].id==0&&a[2].value==model.tempoEventValue&&a[2].flags==model.tempoEventFlags,"Tempo packet differs");
  require(!a[3].event&&a[3].id==20&&a[3].index==0&&a[3].value==model.samplesPerTickDispatchValue,"Second sample-clock packet differs");
  require(holder.interface.refs==0&&holder.interface.retains==holder.interface.releases&&holder.interface.getters==2*(i+1),"Interface lifetime differs");++descriptors;notifications+=4;
 }
 retentions=holder.interface.retains;
 {
  SavedFEnv environment;
  using namespace veggie_loops::three_osc::clock;
  const std::array<double,14>clocks{1,1.5,2,2.5,3,3.5,12.5,183.75,441,4294967295.0,4294967295.5,0x1p32,2.5000000000000004,16777217.0};
  for(double clock:clocks){
   DeliveryContext c{};c.samplesPerTick=clock;
   const bool inexact=double(static_cast<float>(clock))!=clock||std::trunc(clock)!=clock;
   store<int32_t>(base,0x167d358,c.signatureFirst);store<int32_t>(base,0x167d35c,c.signatureSecond);store<int32_t>(base,0x167daec,c.ppq);store<float>(base,0x167da78,c.tempo);store<double>(base,0x167dab8,c.samplesPerTick);store<uint8_t>(base,0x19b4a2a,1);
   alignas(16)std::array<uint8_t,320>node{},expected{};store<void*>(node.data(),0,base+0x1076760);store<void*>(node.data(),0x18,&holder);store<int32_t>(node.data(),0x44,2);expected=node;
   Delivery model{};require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Cannot clear descriptor model fenv");require(delivery(c,model),"Focused descriptor rejected");const int modelMask=std::fetestexcept(FE_ALL_EXCEPT);std::memcpy(expected.data()+0x120,model.timeSignature.data(),12);
   captured.count=0;require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Cannot clear descriptor original fenv");ppqProducer(node.data());tempoProducer(node.data());const int originalMask=std::fetestexcept(FE_ALL_EXCEPT);
   require(captured.count==4&&node==expected&&modelMask==originalMask&&originalMask==(inexact?FE_INEXACT:0),"Descriptor state/exception mask differs");const auto&a=captured.calls;
   require(!a[0].event&&a[0].id==14&&a[0].index==0&&a[0].signature==model.timeSignature&&!a[1].event&&a[1].id==20&&a[1].index==0&&a[1].value==model.samplesPerTickDispatchValue&&a[2].event&&a[2].id==0&&a[2].value==model.tempoEventValue&&a[2].flags==model.tempoEventFlags&&!a[3].event&&a[3].id==20&&a[3].index==0&&a[3].value==model.samplesPerTickDispatchValue,"Focused descriptor arguments differ");
   require(holder.interface.refs==0&&holder.interface.retains==holder.interface.releases,"Focused descriptor lifetime differs");++fenvDescriptors;
  }
  require(environment.restore(),"Focused descriptor fenv not restored");++fenvRestores;
 }
 fenvDescriptorRetains=holder.interface.retains-retentions;
 method<void(*)(void*,intptr_t)>(pluginAdapter,0x60)(pluginAdapter,1);
 using namespace veggie_loops::three_osc::clock;
 const std::array<double,6>bad{NAN,INFINITY,-INFINITY,-0x1p53,0x1p53,0.0};
 for(double value:bad){for(int field=0;field<4;++field){TicksContext c{};TimePacket packet{123.25,std::bit_cast<double>(0x7ff80000564c4142ULL)};if(field==0)c.cachedTicks=value;else if(field==1)c.samplePositionFraction=value;else if(field==2)c.samplesPerTick=value;else packet.t=value;const auto before=packet;const bool invalid=field==2?(!std::isfinite(value)||value<1||value>0x1p32):(!std::isfinite(value)||std::abs(value)>0x1p52);if(invalid){require(!ticks(c,packet)&&std::memcmp(&packet,&before,sizeof packet)==0,"Invalid ticks changed output");++rejected;}}}
 for(int field=0;field<12;++field){DeliveryContext c{};if(field==0)c.sampleRate=7999;else if(field==1)c.sampleRate=384001;else if(field==2)c.signatureFirst=0;else if(field==3)c.signatureSecond=1025;else if(field==4)c.ppq=3;else if(field==5)c.ppq=(1<<20)+1;else if(field==6)c.tempo=INFINITY;else if(field==7)c.samplesPerTick=0;else if(field==8)c.tempo=NAN;else if(field==9)c.tempo=0;else if(field==10)c.samplesPerTick=0x1p32+1;else c.samplesPerTick=INFINITY;Delivery out{};std::memset(&out,0x5a,sizeof out);const auto before=std::bit_cast<std::array<uint8_t,sizeof(Delivery)>>(out);require(!delivery(c,out)&&std::bit_cast<std::array<uint8_t,sizeof(Delivery)>>(out)==before,"Invalid descriptor changed output");++rejected;}
 {TicksContext c{};c.latencySamples=-1;TimePacket packet{1.25,std::bit_cast<double>(0x7ff80000564c4142ULL)};const auto before=packet;require(!ticks(c,packet)&&std::memcmp(&packet,&before,sizeof packet)==0,"Negative latency changed output");++rejected;}
 require(saved.restore(),"Loaded-process globals not restored exactly");
 method<void(*)(void*,intptr_t)>(adapter,0x60)(adapter,1);
 }
 dlclose(image);
 std::cout<<"{\"status\":\"passed\",\"intact_cpp_host_adapter_and_pascal_GT_Ticks_provider\":true,\"controlled_cases\":"<<cases<<",\"cached_cases\":"<<cachedCases<<",\"active_sender_cases\":"<<activeCases<<",\"future_flag_cases\":"<<futureCases<<",\"rounded_cases\":"<<roundedCases<<",\"local_subtraction_cases\":"<<localCases<<",\"sample_offset_cases\":"<<offsetCases<<",\"descriptor_fixtures\":"<<descriptors<<",\"ordered_descriptor_callbacks\":"<<notifications<<",\"balanced_interface_retains\":"<<retentions<<",\"source_rejection_preservation_cases\":"<<rejected<<",\"focused_rounding_exception_tick_cases\":"<<fenvTicks<<",\"focused_rounding_exception_descriptor_cases\":"<<fenvDescriptors<<",\"focused_descriptor_balanced_retains\":"<<fenvDescriptorRetains<<",\"full_fenv_snapshots_restored\":"<<fenvRestores<<",\"general_fenv_or_trap_equivalence\":false,\"exact_output_bytes_per_case\":8,\"second_time_word_preserved\":true,\"selected_native_global_snapshots_restored\":true,\"actual_application_clock_production\":false,\"actual_application_owned_host_or_sender\":false,\"full_plugin_equivalence\":false}\n";
 return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

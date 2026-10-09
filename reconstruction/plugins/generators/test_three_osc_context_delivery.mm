#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_native_factory.h"
#include "three_osc_legacy_tables.hpp"
#include "three_osc_declick.hpp"
#include "three_osc_clock_context.hpp"
#include "three_osc_envelope_coefficients.hpp"
#include <cfenv>
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <memory>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>
namespace {
void require(bool value,const char* message) {if(!value)throw std::runtime_error(message);}
std::string hashFile(const char* path) {
  std::ifstream file(path,std::ios::binary);std::vector<char> image{std::istreambuf_iterator<char>(file),{}};
  std::array<unsigned char,32> bytes;CC_SHA256(image.data(),static_cast<CC_LONG>(image.size()),bytes.data());
  std::ostringstream out;for(auto byte:bytes)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return out.str();
}
template<class T>T load(const void* pointer,size_t offset) {T value;std::memcpy(&value,static_cast<const char*>(pointer)+offset,sizeof(value));return value;}
template<class T>T method(void* pointer,size_t offset) {return reinterpret_cast<T>(load<void**>(pointer,0)[offset/8]);}
template<class T>T symbol(void* library,const char* name) {auto value=reinterpret_cast<T>(dlsym(library,name));require(value,"Missing rebuilt entry point");return value;}
std::array<void*,96> hostMethods;std::array<void*,32> pathMethods;
struct Object {void** methods;};Object pathObject{pathMethods.data()};const char* dataPath;double hostTicks=0;size_t hostTimeRequests=0;size_t modelTimeRequests=0;
extern "C" intptr_t noop() {return 0;}
extern "C" intptr_t hostDispatch(void*,intptr_t,intptr_t id,intptr_t index,intptr_t value) {
  if(id==36 && index==4) {const std::array<double,2> time{hostTicks,0};std::memcpy(reinterpret_cast<void*>(value),time.data(),16);++hostTimeRequests;return 1;}
  if(id==71)return reinterpret_cast<intptr_t>(&pathObject);
  if(id==29)return reinterpret_cast<intptr_t>(dataPath);return 0;
}
extern "C" void nativeLR(void*,float* left,float* right,float pan,float volume) {
  *left=volume*std::sqrt((1-pan)*0.5f);*right=volume*std::sqrt((1+pan)*0.5f);
}

struct Stream {void** methods;std::vector<uint8_t> bytes;size_t cursor=0;};
extern "C" int32_t readStream(Stream* stream,void* value,uint32_t length,void* completed) {
  require(stream->cursor+length<=stream->bytes.size(),"State read overflow");
  std::memcpy(value,stream->bytes.data()+stream->cursor,length);stream->cursor+=length;
  if(completed)std::memcpy(completed,&length,4);return 0;
}
extern "C" int32_t writeStream(Stream* stream,const void* value,uint32_t length,void* completed) {
  auto first=static_cast<const uint8_t*>(value);stream->bytes.insert(stream->bytes.end(),first,first+length);
  if(completed)std::memcpy(completed,&length,4);return 0;
}
std::vector<std::pair<intptr_t,int32_t>> nativeNotices;
extern "C" void nativeNotify(void*,intptr_t tag,int32_t flag) {nativeNotices.emplace_back(tag,flag);}
struct ModelHost {void**methods;std::vector<std::pair<intptr_t,int32_t>>*notices;};
intptr_t modelHostDispatch(void*,intptr_t,intptr_t id,intptr_t index,intptr_t value) {
 if(id==36&&index==4){const std::array<double,2>time{hostTicks,0};std::memcpy(reinterpret_cast<void*>(value),time.data(),16);++modelTimeRequests;return 1;}return 0;
}
void modelHostNotify(ModelHost*h,intptr_t tag,int32_t flag){h->notices->emplace_back(tag,flag);}

struct Levels {float pan=0,volume=0.8f,pitch=-300,cutoff=0,resonance=0;};
struct Parameters {Levels initial,final;};static_assert(sizeof(Parameters)==40);
}

namespace {
template<class T>void store(void* p,size_t offset,T value){std::memcpy(static_cast<char*>(p)+offset,&value,sizeof value);}
struct SavedSpans {
 char*base;std::vector<std::pair<size_t,size_t>>spans;std::vector<std::vector<uint8_t>>bytes;
 SavedSpans(char*b,std::initializer_list<std::pair<size_t,size_t>>s):base(b),spans(s){for(auto[o,n]:spans){bytes.emplace_back(n);std::memcpy(bytes.back().data(),base+o,n);}}
 bool restore(){for(size_t i=0;i<spans.size();++i)std::memcpy(base+spans[i].first,bytes[i].data(),bytes[i].size());for(size_t i=0;i<spans.size();++i)if(std::memcmp(base+spans[i].first,bytes[i].data(),bytes[i].size()))return false;return true;}
 ~SavedSpans(){restore();}
};
struct Interface{void**vmt=nullptr;void*plugin=nullptr;int32_t refs=0;size_t retains=0,releases=0,getters=0;};
struct Holder{std::array<uint8_t,72>prefix{};Interface interface;};static_assert(offsetof(Holder,interface)==0x48);
int32_t retain(Interface*p){++p->retains;return ++p->refs;}
int32_t releaseInterface(Interface*p){++p->releases;require(p->refs>0,"Unbalanced manager release");return --p->refs;}
void*getPlugin(Interface*p){++p->getters;return p->plugin;}
void appendBytes(std::vector<uint8_t>&out,const void*value,size_t n){auto*b=static_cast<const uint8_t*>(value);out.insert(out.end(),b,b+n);}
}
int main(int argc,char**argv){@autoreleasepool{try{
 require(argc==4,"Usage: context-delivery <original wrapper> <rebuilt factory> <private directory/>");
 require(std::fegetround()==FE_TONEAREST,"Nearest-even required");uint64_t fpcr;asm volatile("mrs %0, fpcr":"=r"(fpcr));require((fpcr&(1ull<<24))==0,"Gradual underflow required");
 require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity changed");
 require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Vector identity changed");
 require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib")=="d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Small engine identity changed");
 const char*enginePath="/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib";
 require(hashFile(enginePath)=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Host engine identity changed");
 [NSApplication sharedApplication];dataPath=argv[3];hostMethods.fill(reinterpret_cast<void*>(&noop));pathMethods.fill(reinterpret_cast<void*>(&noop));hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);hostMethods[0xf0/8]=reinterpret_cast<void*>(&nativeNotify);
 alignas(16)std::array<std::byte,512>host{};store<void*>(host.data(),0,hostMethods.data());std::vector<float>tables(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(tables.data(),tables.size()));std::array<const float*,6>tablePointers{};
 for(int i=0;i<6;++i){tablePointers[i]=tables.data()+i*16384;store<const float*>(host.data(),0x18+i*8,tablePointers[i]);}
 void*native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Original wrapper load failed");void*rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt factory load failed");void*engine=dlopen(enginePath,RTLD_NOW|RTLD_LOCAL);require(engine,"Host engine load failed");
 auto create=symbol<void*(*)(void*,intptr_t)>(native,"CreatePlugInstance");auto cppFactory=symbol<vl_private_osc::Plugin*(*)(void*,intptr_t)>(rebuilt,"CreatePlugInstance");auto factoryChannel=symbol<vl_osc_multimode_channel*(*)(vl_private_osc::Plugin*)>(rebuilt,"vl_private_osc_channel");
 auto snapshot=symbol<int(*)(const vl_osc_multimode_channel*,const vl_osc_multimode_channel_voice*,uint32_t*,uint8_t*,float*,int32_t*,uint32_t*,uint8_t*)>(rebuilt,"vl_osc_multimode_channel_snapshot");
 Dl_info nativeInfo{},engineInfo{};require(dladdr(reinterpret_cast<void*>(create),&nativeInfo)&&dladdr(dlsym(engine,"CreateFruityInstance"),&engineInfo),"Native image base unavailable");auto*wrapperBase=static_cast<char*>(nativeInfo.dli_fbase);auto*engineBase=static_cast<char*>(engineInfo.dli_fbase);
 using Ctor=void*(*)(void*,intptr_t,void*);auto hostCtor=reinterpret_cast<Ctor>(engineBase+0xb4cd20),pluginCtor=reinterpret_cast<Ctor>(engineBase+0xb4c7c0);auto ppqProducer=reinterpret_cast<void(*)(void*)>(engineBase+0x32e000),tempoProducer=reinterpret_cast<void(*)(void*)>(engineBase+0x32e1f0);
 size_t fixtures=0,descriptorRoutes=0,retains=0,coeffWords=0,stateBytes=0,voiceStateValues=0,audioFloats=0,renderCalls=0,pairs=0,contextValues=0;std::array<size_t,8>modes{};std::vector<uint8_t>previousFingerprint;
 {
 SavedSpans engineGlobals(engineBase,{{0x167d358,8},{0x167daec,8},{0x167da78,4},{0x167dab8,8},{0x19b4a2a,1}});
 SavedSpans wrapperGlobals(wrapperBase,{{0x25892c,24},{0x263008,16}});
 std::array<void*,5>interfaceFns{};interfaceFns[1]=reinterpret_cast<void*>(&retain);interfaceFns[2]=reinterpret_cast<void*>(&releaseInterface);interfaceFns[4]=reinterpret_cast<void*>(&getPlugin);
 std::array<void*,5>streamMethods{};streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);
 for(int fixture=0;fixture<72;++fixture){const int profile=fixture/2,variant=fixture%2;const int rate=std::array<int,6>{8000,22050,44100,48000,96000,384000}[profile%6];const float tempo=std::array<float,6>{60,90,120,137.125f,240,1000}[profile%6];const int ppq=std::array<int,6>{4,48,96,240,960,4096}[(profile/6)%6];
  const double clock=variant==0?double(rate)*60/(double(tempo)*ppq):std::array<double,6>{1.5,2.5,183.75,16777217.0,4294967295.5,0x1p32}[profile%6];
  using namespace veggie_loops::three_osc::clock;DeliveryContext delivered{rate,16,4,ppq,tempo,clock};Delivery expectedDelivery{};require(delivery(delivered,expectedDelivery),"Prepared descriptor context invalid");
  void*plugin=create(host.data(),42);require(plugin,"Original factory failed");std::vector<std::pair<intptr_t,int32_t>>modelNotices;std::array<void*,96>modelMethods{};modelMethods[0xc8/8]=reinterpret_cast<void*>(&modelHostDispatch);modelMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);modelMethods[0xf0/8]=reinterpret_cast<void*>(&modelHostNotify);ModelHost modelHost{modelMethods.data(),&modelNotices};void*hostAdapter=hostCtor(engineBase+0x1497870,1,&modelHost);require(hostAdapter,"Host adapter failed");auto*cppPlugin=cppFactory(static_cast<char*>(hostAdapter)+16,42);require(cppPlugin,"Source factory failed");void*model=pluginCtor(engineBase+0x1497618,1,cppPlugin);require(model,"Plugin adapter failed");require(!factoryChannel(cppPlugin),"Source channel eagerly prepared before descriptor delivery");
  auto state=method<void(*)(void*,void*,int32_t)>(plugin,0xe0),modelState=method<void(*)(void*,void*,int32_t)>(model,0xe0);Stream initial{streamMethods.data(),{},0};state(plugin,&initial,1);require(initial.bytes.size()==460,"Initial state framing changed");initial.bytes[92]=uint8_t(profile%2);state(plugin,&initial,0);initial.cursor=0;modelState(model,&initial,0);
  auto parameter=method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(plugin,0xf8),modelParameter=method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(model,0xf8);
  const auto set=[&](int i,int v){parameter(plugin,i,v,1);modelParameter(model,i,v,1);};
  const std::array<int,21>core{12,0,0,-3,7,-8,80,-13,1,7,5,-9,11,70,0,2,-12,0,0,0,0};for(int i=0;i<21;++i)set(i,core[i]);
  std::array<std::array<int32_t,17>,5>raw{};
  for(int group=0;group<5;++group){raw[group]={int32_t((profile+group)%32),1,100,2000+profile*31,100,5000+group*200,64,9000+profile*11,group==2||group==3?8:16,100,2000,group==2||group==3?-8:12,16000+profile*17,(profile+group)%3,16,-32,48};for(int field=0;field<17;++field)set(23+group*17+field,raw[group][field]);}
  set(110,128);set(111,32);set(113,profile%8);++modes[profile%8];
  // Rate delivery is the measured Pascal dispatch entry, called directly with
  // a prepared rate. Full native DLL-loader production is statically mapped,
  // not executed by this fixture. TExPlugin PPQ/tempo producers below are intact.
  method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(plugin,0xd0)(plugin,4,0,expectedDelivery.sampleRate);method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(model,0xd0)(model,4,0,expectedDelivery.sampleRate);
  store<int32_t>(engineBase,0x167d358,16);store<int32_t>(engineBase,0x167d35c,4);store<int32_t>(engineBase,0x167daec,ppq);store<float>(engineBase,0x167da78,tempo);store<double>(engineBase,0x167dab8,clock);store<uint8_t>(engineBase,0x19b4a2a,1);
  for(void*target:{plugin,model}){Holder holder{};holder.interface.vmt=interfaceFns.data();holder.interface.plugin=target;alignas(16)std::array<uint8_t,320>node{},expectedNode{};for(size_t i=0;i<node.size();++i)node[i]=uint8_t(0xa5+i*13);store<void*>(node.data(),0,engineBase+0x1076760);store<void*>(node.data(),0x18,&holder);store<int32_t>(node.data(),0x44,2);store<int32_t>(node.data(),0x130,0);expectedNode=node;std::memcpy(expectedNode.data()+0x120,expectedDelivery.timeSignature.data(),12);
   ppqProducer(node.data());tempoProducer(node.data());require(node==expectedNode,"Descriptor sender guard/state differs");require(holder.interface.getters==2&&holder.interface.retains==2&&holder.interface.releases==2&&holder.interface.refs==0,"Descriptor manager interface lifetime differs");retains+=holder.interface.retains;++descriptorRoutes;
  }
  require(!factoryChannel(cppPlugin),"Descriptor path unexpectedly created a channel/voice");
  require(load<int32_t>(wrapperBase,0x25892c)==rate&&std::bit_cast<uint32_t>(load<float>(wrapperBase,0x258930))==std::bit_cast<uint32_t>(float(44100.0/double(rate))),"Original delivered rate/ratio differs");contextValues+=2;
  require(load<double>(wrapperBase,0x263008)==double(tempo)&&load<uint32_t>(wrapperBase,0x263010)==uint32_t(ppq)&&load<uint32_t>(wrapperBase,0x263014)==uint32_t(ppq>>2),"Original delivered tempo/PPQ differs");contextValues+=3;
  std::vector<uint8_t>fingerprint;const void*cfg=load<void*>(plugin,0x240);
  for(int group=0;group<5;++group){veggie_loops::three_osc::envelope::Configuration prepared{};prepared.raw=raw[group];veggie_loops::three_osc::envelope::prepareConfiguration(prepared,double(tempo),uint32_t(ppq),{tablePointers[0],tablePointers[1],tablePointers[2]});
   for(size_t off=0;off<160;off+=4)if(off!=0x68&&off!=0x6c&&off!=0x78){const auto value=load<uint32_t>(cfg,8+group*160+off);require(value==load<uint32_t>(&prepared,off),"Delivered prevoice coefficient differs");appendBytes(fingerprint,&value,4);++coeffWords;}
   const float*pointer=load<const float*>(cfg,8+group*160+0x68);require(pointer==load<const float*>(wrapperBase,0x263020+size_t(raw[group][13])*8),"Native internal LFO table selection differs");require(!std::memcmp(pointer,tablePointers[size_t(raw[group][13])],16384*sizeof(float)),"Native internal LFO table content differs from generated source bank");
  }
  Stream nativeSave{streamMethods.data(),{},0},modelSave{streamMethods.data(),{},0};state(plugin,&nativeSave,1);modelState(model,&modelSave,1);require(nativeSave.bytes.size()==460&&modelSave.bytes.size()==460,"Delivered state framing differs");for(size_t byte=0;byte<460;++byte)if(byte<93||byte>=96){require(nativeSave.bytes[byte]==modelSave.bytes[byte],"Delivered semantic state differs");appendBytes(fingerprint,&nativeSave.bytes[byte],1);++stateBytes;}
  Parameters params{};params.initial.pitch=float((profile%7-3)*300);params.final=params.initial;vl_osc_multimode_channel_parameters sourceParams{};std::memcpy(&sourceParams,&params,40);
  auto voice=method<uintptr_t(*)(void*,void*,intptr_t)>(plugin,0x110)(plugin,&params,100+profile);auto sourceHandle=method<intptr_t(*)(void*,void*,intptr_t)>(model,0x110)(model,&sourceParams,100+profile);require(voice&&sourceHandle!=-1&&sourceHandle,"Delivered first voice failed");auto*channel=factoryChannel(cppPlugin);require(channel,"Source channel not created lazily at first voice");
  const auto compareVoice=[&](){const void*editor=load<void*>(reinterpret_cast<void*>(voice),48);std::array<uint32_t,45>mod{};std::array<uint8_t,112>filter{};std::array<float,2>gain{};std::array<int32_t,3>released{};std::array<uint32_t,6>phase{};uint8_t stereo=0;require(snapshot(channel,reinterpret_cast<vl_osc_multimode_channel_voice*>(sourceHandle),mod.data(),filter.data(),gain.data(),released.data(),phase.data(),&stereo),"Delivered voice snapshot failed");
   require(!std::memcmp(static_cast<const char*>(editor)+0x50,mod.data(),180)&&!std::memcmp(static_cast<const char*>(editor)+0x108,filter.data(),112)&&!std::memcmp(static_cast<const char*>(editor)+0x40,gain.data(),8)&&load<int>(editor,0xc)==released[0]&&load<int>(editor,0x10)==released[1]&&load<uint8_t>(editor,0x178)==released[2]&&!std::memcmp(reinterpret_cast<const char*>(voice)+16,phase.data(),24)&&load<uint8_t>(reinterpret_cast<void*>(voice),40)==stereo,"Delivered voice state differs");require(!std::memcmp(&params,&sourceParams,40),"Delivered borrowed parameters differ");voiceStateValues+=95;
   appendBytes(fingerprint,mod.data(),180);appendBytes(fingerprint,filter.data(),112);appendBytes(fingerprint,gain.data(),8);appendBytes(fingerprint,released.data(),12);appendBytes(fingerprint,phase.data(),24);appendBytes(fingerprint,&stereo,1);
  };compareVoice();
  for(int block=0;block<8;++block){const int count=std::array<int,8>{1,7,8,63,441,1024,16,3}[block];if(block%2==0){method<void(*)(void*)>(plugin,0x138)(plugin);method<void(*)(void*)>(model,0x138)(model);}
   params.final.pan=float((block%3-1)*.15f);params.final.volume=.8f-.03f*float(block);params.final.cutoff=.02f;params.final.resonance=-.015f;std::memcpy(&sourceParams,&params,40);std::vector<float>a(size_t(count)*2+16,1234.5f);for(int i=0;i<2*count;++i)a[size_t(i)+8]=.25f;auto b=a;int nativeLength=count;int32_t sourceLength=count;nativeNotices.clear();modelNotices.clear();method<void(*)(void*,float*,int*)>(plugin,0x108)(plugin,a.data()+8,&nativeLength);method<void(*)(void*,float*,int32_t&)>(model,0x108)(model,b.data()+8,sourceLength);require(nativeLength==count&&sourceLength==count,"Delivered render length differs");for(int i=0;i<8;++i)require(a[size_t(i)]==1234.5f&&b[size_t(i)]==1234.5f&&a[size_t(2*count+i+8)]==1234.5f&&b[size_t(2*count+i+8)]==1234.5f,"Delivered audio guard changed");require(!std::memcmp(a.data(),b.data(),a.size()*4),"Delivered audio differs");for(int i=0;i<2*count;++i)require(std::isfinite(a[size_t(i)+8]),"Delivered audio nonfinite");require(nativeNotices==modelNotices,"Delivered notification sequence differs");appendBytes(fingerprint,a.data()+8,size_t(count)*8);audioFloats+=size_t(count)*2;++renderCalls;compareVoice();
  }
  if(variant==0)previousFingerprint=fingerprint;else{require(fingerprint==previousFingerprint,"Ignored clock20/event flags changed coefficients/state/audio");++pairs;}
  method<void(*)(void*,uintptr_t)>(plugin,0x120)(plugin,voice);method<void(*)(void*,intptr_t)>(model,0x120)(model,sourceHandle);method<void(*)(void*)>(plugin,0xc8)(plugin);method<void(*)(void*)>(model,0xc8)(model);method<void(*)(void*,intptr_t)>(model,0x60)(model,1);method<void(*)(void*,intptr_t)>(hostAdapter,0x60)(hostAdapter,1);++fixtures;
 }
 require(engineGlobals.restore()&&wrapperGlobals.restore(),"Selected native global snapshots not restored");
 }
 dlclose(rebuilt);dlclose(native);dlclose(engine);std::cout<<"{\"status\":\"passed\",\"unchanged_published_cpp_factory\":true,\"prevoice_delivery_fixtures\":"<<fixtures<<",\"intact_TExPlugin_descriptor_routes\":"<<descriptorRoutes<<",\"balanced_manager_retains\":"<<retains<<",\"delivered_original_context_values\":"<<contextValues<<",\"exact_prevoice_coefficient_words\":"<<coeffWords<<",\"exact_semantic_state_bytes\":"<<stateBytes<<",\"exact_voice_state_values\":"<<voiceStateValues<<",\"GenRender_calls\":"<<renderCalls<<",\"exact_overwritten_audio_floats\":"<<audioFloats<<",\"ignored_clock_metadata_pairs\":"<<pairs<<",\"filter_mode_fixtures\":[";for(size_t i=0;i<8;++i)std::cout<<(i?",":"")<<modes[i];std::cout<<"],\"selected_native_globals_restored\":true,\"direct_prepared_rate_delivery\":true,\"native_DLL_loader_rate_production_executed\":false,\"active_voice_context_updates\":false,\"actual_application_clock_production\":false,\"full_plugin_equivalence\":false}\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

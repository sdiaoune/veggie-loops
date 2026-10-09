#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_sync_lfo.h"
#include "three_osc_legacy_tables.hpp"
#include "three_osc_envelope_coefficients.hpp"
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
struct Object {void** methods;};Object pathObject{pathMethods.data()};const char* dataPath;double hostTicks=0;size_t hostTimeRequests=0;
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
struct Levels {float pan=0,volume=0.8f,pitch=-300,cutoff=0,resonance=0;};
struct Parameters {Levels initial,final;};static_assert(sizeof(Parameters)==40);
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==4,"Usage: sync_lfo <native wrapper> <rebuilt helper> <private directory/>");
    require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Vector dependency identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib")=="d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Engine identity mismatch");
    [NSApplication sharedApplication];dataPath=argv[3];hostMethods.fill(reinterpret_cast<void*>(&noop));pathMethods.fill(reinterpret_cast<void*>(&noop));hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);
    alignas(16) std::array<std::byte,512> host{};auto** hostVMT=hostMethods.data();std::memcpy(host.data(),&hostVMT,8);
    std::vector<float> tables(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(tables.data(),tables.size()));std::array<const float*,6> tablePointers{};
    for(int i=0;i<6;++i) {tablePointers[i]=tables.data()+i*16384;std::memcpy(host.data()+0x18+i*8,&tablePointers[i],8);}
    auto* original=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(original,"Native load failed");auto* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    auto create=symbol<void*(*)(void*,intptr_t)>(original,"CreatePlugInstance");
    auto changed=symbol<void(*)(vl_osc_sync_lfo_state*)>(rebuilt,"vl_osc_sync_lfo_editor_changed");
    auto prepare=symbol<void(*)(vl_osc_sync_lfo_state*,const uint32_t*,int,int)>(rebuilt,"vl_osc_sync_lfo_prepare_frame");
    auto newTick=symbol<void(*)(vl_osc_sync_lfo_state*,const uint32_t*)>(rebuilt,"vl_osc_sync_lfo_new_tick");
    auto position=symbol<int(*)(vl_osc_sync_lfo_state*,const uint32_t*,double)>(rebuilt,"vl_osc_sync_lfo_song_position");
    auto finish=symbol<void(*)(vl_osc_sync_lfo_state*,int)>(rebuilt,"vl_osc_sync_lfo_finish_frame");
    std::array<void*,5> streamMethods{};streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);
    using veggie_loops::three_osc::envelope::Configuration;std::array<Configuration,5> cfg;
    std::mt19937 random(0x32ff);size_t prepares=0,ticks=0,seeks=0,emptyFrames=0,stateValues=0,rejects=0,preparedIncrements=0;
    constexpr int fixtureCount=360;
    for(int fixture=0;fixture<fixtureCount;++fixture) {
      void* plugin=create(host.data(),42);require(plugin,"Factory failed");auto state=method<void(*)(void*,void*,int)>(plugin,0xe0);Stream stream{streamMethods.data(),{},0};state(plugin,&stream,1);require(stream.bytes.size()==460,"State frame changed");stream.bytes[92]=1;state(plugin,&stream,0);
      auto param=method<int(*)(void*,int,int,uint32_t)>(plugin,0xf8);auto event=method<int(*)(void*,int,int,int)>(plugin,0xf0);auto dispatch=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(plugin,0xd0);
      auto tick=method<void(*)(void*)>(plugin,0x138);auto render=method<void(*)(void*,float*,int*)>(plugin,0x108);auto trigger=method<uintptr_t(*)(void*,void*,intptr_t)>(plugin,0x110);auto kill=method<void(*)(void*,uintptr_t)>(plugin,0x120);
      const double tempo=std::array<double,6>{60,90,120,137,240,1000}[fixture%6];const uint32_t ppq=std::array<uint32_t,6>{4,48,96,240,960,4096}[(fixture/6)%6];std::array<int,3> signature{16,4,int(ppq)};dispatch(plugin,14,0,reinterpret_cast<intptr_t>(signature.data()));event(plugin,0,int(std::bit_cast<uint32_t>(float(tempo))),0);
      std::array<uint32_t,5> flags{},increments{};vl_osc_sync_lfo_state model{};
      auto* context=load<char*>(plugin,0x238);auto* nativeCfg=load<char*>(plugin,0x240);
      for(size_t group=0;group<5;++group) {
        std::memcpy(cfg[group].raw.data(),nativeCfg+8+group*160,68);const int period=100+int(random()%65437);param(plugin,23+int(group)*17+12,period,1);changed(&model);cfg[group].raw[12]=period;
        veggie_loops::three_osc::envelope::prepareConfiguration(cfg[group],tempo,ppq,{tablePointers[0],tablePointers[1],tablePointers[2]});increments[group]=cfg[group].lfoPhaseIncrement;
        require(load<uint32_t>(nativeCfg,8+group*160+0x64)==increments[group],"Prepared increment differs");++preparedIncrements;flags[group]=uint32_t(cfg[group].raw[0]);
      }
      int currentRound=-1;
      const auto compare=[&]() {
        const void* list=load<void*>(context,0x28);const int count=load<int>(list,0x10);auto* items=load<void* const*>(list,8);uint32_t mask=0;if(count!=int(model.registered_count) || load<uint8_t>(list,0x18)!=0) {std::cerr<<"fixture="<<fixture<<" round="<<currentRound<<" native count="<<count<<" model count="<<model.registered_count<<" order policy="<<int(load<uint8_t>(list,0x18))<<" mask="<<model.registered_mask<<" native dirty="<<load<int>(nativeCfg,0x334)<<" model dirty="<<model.dirty<<"\n";}require(count==int(model.registered_count) && load<uint8_t>(list,0x18)==0,"Registry count/order policy differs");
        for(int i=0;i<count;++i) {const auto difference=static_cast<const char*>(items[i])-(nativeCfg+8);require(difference>=0 && difference%160==0 && difference/160<5,"Unknown registry pointer");const int group=int(difference/160);require(uint32_t(group)==model.registered_order[size_t(i)],"Registry order differs");mask|=1u<<group;}
        require(mask==model.registered_mask && load<uint32_t>(context,0x20)==model.pending_tick && load<uint32_t>(nativeCfg,0x334)==model.dirty && load<uint8_t>(context,0x24)==model.release_refresh,"Registry/pending/dirty/refresh differs");
        for(size_t group=0;group<5;++group)require(load<uint32_t>(nativeCfg,8+group*160+0x78)==model.phases[group],"Synchronized phase differs");stateValues+=10+size_t(count);
      };
      int volumeEnabled=0;uintptr_t voice=0;Parameters parameters;
      for(int round=0;round<256;++round) {currentRound=round;
        compare();
        const int group=int(random()%5);flags[size_t(group)]=random()%64;param(plugin,23+group*17,int(flags[size_t(group)]),1);changed(&model);cfg[size_t(group)].raw[0]=int(flags[size_t(group)]);
        veggie_loops::three_osc::envelope::prepareConfiguration(cfg[size_t(group)],tempo,ppq,{tablePointers[0],tablePointers[1],tablePointers[2]});increments[size_t(group)]=cfg[size_t(group)].lfoPhaseIncrement;
        require(load<uint32_t>(nativeCfg,8+size_t(group)*160+0x64)==increments[size_t(group)],"Updated increment differs");++preparedIncrements;compare();
        if(round%7==0) {volumeEnabled=1-volumeEnabled;param(plugin,41,volumeEnabled,1);changed(&model);}
        if(round%5==0) {tick(plugin);newTick(&model,increments.data());++ticks;compare();}
        if(round%3==0) {
          const std::array<double,12> times{0,1,-1,12345.625,-12345.625,2147483647.75,-2147483648.75,4294967296.625,-4294967297.625,0x1p63-1024,-0x1p63,0x1p52+0.5};hostTicks=times[size_t((fixture+round)%int(times.size()))];dispatch(plugin,13,0,0);require(position(&model,increments.data(),hostTicks),"Valid seek rejected");++seeks;compare();
        }
        if(round%8==0) {if(voice) {kill(plugin,voice);voice=0;}else {parameters.final=parameters.initial;voice=trigger(plugin,&parameters,100);require(voice,"Trigger failed");}}
        if(voice)parameters.final=parameters.initial;
        const int hasVoices=voice ? 1:0;alignas(64) std::array<float,32> output;output.fill(1234.5f);std::fill(output.begin()+8,output.begin()+24,0.0f);int frames=8;prepare(&model,flags.data(),volumeEnabled,hasVoices);render(plugin,output.data()+8,&frames);finish(&model,hasVoices);
        require(std::all_of(output.begin(),output.begin()+8,[](float value){return value==1234.5f;}) && std::all_of(output.begin()+24,output.end(),[](float value){return value==1234.5f;}),"Native metadata fixture output guard changed");
        ++prepares;if(!voice)++emptyFrames;compare();
        if(round%11==0) {const auto saved=model;for(double bad:{std::numeric_limits<double>::infinity(),-std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN(),0x1p63,std::nextafter(-0x1p63,-std::numeric_limits<double>::infinity())}) {require(!position(&model,increments.data(),bad),"Invalid mixing time accepted");require(std::memcmp(&saved,&model,sizeof(model))==0,"Rejected time mutated state");++rejects;}}
      }
      if(voice)kill(plugin,voice);method<void(*)(void*)>(plugin,0xc8)(plugin);
    }
    require(hostTimeRequests==seeks,"Unexpected host mixing-time request count");
    dlclose(rebuilt);dlclose(original);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"actual_native_factory_fixtures\":"<<fixtureCount<<",\"prepared_coefficient_increments\":"<<preparedIncrements
      <<",\"registry_frame_cases\":"<<prepares<<",\"empty_render_cases\":"<<emptyFrames<<",\"explicit_NewTick_calls\":"<<ticks<<",\"public_song_position_cases\":"<<seeks<<",\"controlled_host_time_requests\":"<<hostTimeRequests<<",\"exact_metadata_values\":"<<stateValues<<",\"rejected_time_preservation_cases\":"<<rejects
      <<",\"actual_host_clock_production_rebuilt\":false,\"synchronized_audio_pipeline_rebuilt\":false,\"native_factory_rebuilt\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

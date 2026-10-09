#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_prepared_voice.h"
#include "three_osc_legacy_tables.hpp"
#include "three_osc_declick.hpp"
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
struct Object {void** methods;};Object pathObject{pathMethods.data()};const char* dataPath;
extern "C" intptr_t noop() {return 0;}
extern "C" intptr_t hostDispatch(void*,intptr_t,intptr_t id,intptr_t,intptr_t) {
  if(id==71)return reinterpret_cast<intptr_t>(&pathObject);
  if(id==29)return reinterpret_cast<intptr_t>(dataPath);return 0;
}
extern "C" void nativeLR(void*,float* left,float* right,float pan,float volume) {
  *left=volume*std::sqrt((1-pan)*0.5f);*right=volume*std::sqrt((1+pan)*0.5f);
}
void modelLR(void*,float* left,float* right,float pan,float volume) {nativeLR(nullptr,left,right,pan,volume);}
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
    require(argc==4,"Usage: test_three_osc_prepared_voice <native wrapper> <rebuilt module> <private directory/>");
    require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Vector dependency identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib")=="d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Oscillator engine identity mismatch");
    [NSApplication sharedApplication];dataPath=argv[3];
    hostMethods.fill(reinterpret_cast<void*>(&noop));pathMethods.fill(reinterpret_cast<void*>(&noop));
    hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);
    alignas(16) std::array<std::byte,512> host{};auto** hostVMT=hostMethods.data();std::memcpy(host.data(),&hostVMT,8);
    std::vector<float> tables(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(tables.data(),tables.size()));
    std::array<const float*,6> tablePointers{};
    for(int i=0;i<6;++i) {tablePointers[i]=tables.data()+i*16384;std::memcpy(host.data()+0x18+i*8,&tablePointers[i],8);}
    void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    auto create=symbol<void*(*)(void*,intptr_t)>(native,"CreatePlugInstance");
    auto coreCreate=symbol<vl_osc_core*(*)(vl_osc_compute_lr,void*)>(rebuilt,"vl_osc_core_create");
    auto coreDestroy=symbol<void(*)(vl_osc_core*)>(rebuilt,"vl_osc_core_destroy");
    auto coreTables=symbol<int(*)(vl_osc_core*,const float* const*)>(rebuilt,"vl_osc_core_host_tables");
    auto coreRate=symbol<int(*)(vl_osc_core*,int)>(rebuilt,"vl_osc_core_set_sample_rate");
    auto coreParam=symbol<int32_t(*)(vl_osc_core*,int,int,uint32_t)>(rebuilt,"vl_osc_core_parameter");
    auto coreRestore=symbol<int(*)(vl_osc_core*,const uint8_t*,size_t)>(rebuilt,"vl_osc_core_restore_payload");
    auto coreTrigger=symbol<vl_osc_voice*(*)(vl_osc_core*,intptr_t)>(rebuilt,"vl_osc_core_trigger");
    auto corePhases=symbol<void(*)(const vl_osc_voice*,uint32_t*,uint8_t*)>(rebuilt,"vl_osc_core_voice_phases");
    auto outputCreate=symbol<vl_osc_prepared_voice*(*)(vl_osc_core*,vl_osc_voice*,int,int,double,uint32_t,const float* const*)>(rebuilt,"vl_osc_prepared_voice_create");
    auto outputDestroy=symbol<void(*)(vl_osc_prepared_voice*)>(rebuilt,"vl_osc_prepared_voice_destroy");
    auto outputRelease=symbol<void(*)(vl_osc_prepared_voice*)>(rebuilt,"vl_osc_prepared_voice_release");
    auto outputRender=symbol<int(*)(vl_osc_prepared_voice*,vl_osc_prepared_parameters*,int,float*,uint32_t)>(rebuilt,"vl_osc_prepared_voice_render");
    auto outputSnapshot=symbol<void(*)(const vl_osc_prepared_voice*,uint32_t*,uint8_t*,float*,int32_t*)>(rebuilt,"vl_osc_prepared_voice_snapshot");
    auto generate=symbol<void(*)(const veggie_loops::three_osc::declick::Curve*,int,int,int,int,float*,int)>(rebuilt,"vl_osc_declick_generate");
    std::array<void*,5> streamMethods{};streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);
    std::mt19937 random(0x74756);size_t blocks=0,floats=0,stateWords=0,releaseTables=0,rejectedCalls=0;
    double maxHistory=0,maxOutput=0,maxWorkingSample=0,maxGain=0;
    const std::array<int,12> lengths{1,2,3,7,8,9,15,16,63,441,1024,4096};
    constexpr int fixtureCount=360;
    for(int fixture=0;fixture<fixtureCount;++fixture) {
      void* plugin=create(host.data(),42);require(plugin,"Native factory failed");auto* core=coreCreate(modelLR,nullptr);require(core,"Rebuilt core failed");require(coreTables(core,tablePointers.data()),"Tables rejected");
      auto state=method<void(*)(void*,void*,int)>(plugin,0xe0);Stream stream{streamMethods.data(),{},0};state(plugin,&stream,1);
      require(stream.bytes.size()==460,"Wrong version14 framing");stream.bytes[92]=uint8_t(fixture%2);state(plugin,&stream,0);require(coreRestore(core,stream.bytes.data()+4,456),"Model state rejected");
      auto dispatch=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(plugin,0xd0);
      const int rate=std::array<int,6>{44100,48000,96000,22050,8000,384000}[fixture%6];dispatch(plugin,4,0,rate);require(coreRate(core,rate),"Rate rejected");
      auto parameter=method<int(*)(void*,int,int,uint32_t)>(plugin,0xf8);
      auto event=method<int(*)(void*,int,int,int)>(plugin,0xf0);const float tempo=std::array<float,6>{60,90,120,137,240,1000}[fixture%6];
      event(plugin,0,int(std::bit_cast<uint32_t>(tempo)),0);
      const int clock=std::array<int,6>{4,48,96,240,960,4096}[(fixture/6)%6];
      std::array<int,3> rawClock{0,0,clock};dispatch(plugin,14,0,reinterpret_cast<intptr_t>(rawClock.data()));
      const auto set=[&](int index,int value) {parameter(plugin,index,value,1);coreParam(core,index,value,1);};
      const std::array<int,21> mins{-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0};
      const std::array<int,21> maxs{64,4,24,100,64,50,128,64,4,24,100,64,50,128,64,4,24,100,64,50,0};
      for(int i=0;i<21;++i)set(i,mins[i]+int(random()%uint32_t(maxs[i]-mins[i]+1)));
      for(int group=0;group<5;++group) {
        const int choice=(fixture+group)%6;
        const std::array<int,6> times{100,512,2000,5000,9000,16000};
        std::array<int,17> controls{(fixture+group)%32,(fixture+group)%5!=0 ? 1:0,
          choice%3==0 ? 2000:100,times[size_t(choice)],choice%3==1 ? 512:100,
          times[size_t((choice+2)%6)],(fixture+group)%3*64,times[size_t((choice+4)%6)],
          group==4 ? int(random()%257)-128:group==2 || group==3 ? int(random()%65)-32:int(random()%257)-128,
          choice%3==2 ? 2000:100,choice%2 ? 3000:100,
          group==2 || group==3 ? int(random()%65)-32:int(random()%257)-128,
          times[size_t((choice+3)%6)],(fixture+group)%3,
          int(random()%257)-128,int(random()%257)-128,int(random()%257)-128};
        for(int field=0;field<17;++field)set(23+group*17+field,controls[size_t(field)]);
      }
      set(110,int(random()%257));set(111,int(random()%257));
      const void* extra=load<void*>(load<void*>(plugin,0x238),8);const int releaseCount=load<int>(extra,0x3c);require(releaseCount==441,"Changed constructor release table domain");
      std::vector<float> expectedRelease(size_t(releaseCount),0);veggie_loops::three_osc::declick::Curve curve{};
      generate(&curve,3,1,0,releaseCount,expectedRelease.data(),releaseCount);
      require(std::memcmp(load<void*>(extra,0x58),expectedRelease.data(),size_t(releaseCount)*4)==0,"Actual native factory441table differs");++releaseTables;
      auto trigger=method<uintptr_t(*)(void*,void*,intptr_t)>(plugin,0x110);auto tick=method<void(*)(void*)>(plugin,0x138);
      auto render=method<void(*)(void*,float*,int*)>(plugin,0x108);auto release=method<void(*)(void*,uintptr_t)>(plugin,0x118);auto kill=method<void(*)(void*,uintptr_t)>(plugin,0x120);
      std::array<Parameters,2> params;std::array<uintptr_t,2> voices{};std::array<vl_osc_voice*,2> raws{};std::array<vl_osc_prepared_voice*,2> outputs{};
      for(int v=0;v<2;++v) {params[v].initial.pitch=float(int(random()%4801)-2400);params[v].final=params[v].initial;voices[v]=trigger(plugin,&params[v],100+v);raws[v]=coreTrigger(core,100+v);outputs[v]=outputCreate(core,raws[v],44100,rate,double(tempo),uint32_t(clock),tablePointers.data());require(voices[v] && outputs[v],"Voice creation failed");}
      for(int block=0;block<24;++block) {
        if(block==6) {release(plugin,voices[0]);outputRelease(outputs[0]);}
        if(block==13) {release(plugin,voices[1]);outputRelease(outputs[1]);}
        const int count=lengths[(fixture+block)%lengths.size()];
        for(auto& p:params) {p.final=p.initial;p.final.pan=float(int(random()%2001)-1000)/1000.0f;p.final.volume=float(random()%1001)/1000.0f;p.final.pitch=float(int(random()%4801)-2400);p.final.cutoff=float(int(random()%501)-250)/1000.0f;p.final.resonance=float(int(random()%501)-250)/1000.0f;}
        const std::array<float,2> basePitches{params[0].final.pitch,params[1].final.pitch};
        const int newTick=(block+fixture)%4!=3;if(newTick)tick(plugin);std::vector<float> a(size_t(count)*2+16,1234.5f);
        std::fill(a.begin()+8,a.begin()+8+count*2,0.0f);auto b=a;
        const auto checkGuards=[&](const std::vector<float>& buffer) {
          for(int j=0;j<8;++j)require(buffer[size_t(j)]==1234.5f && buffer[size_t(count)*2+8+size_t(j)]==1234.5f,"Output guard overwritten");
        };
        int nativeCount=count;render(plugin,a.data()+8,&nativeCount);require(nativeCount==count,"Native frame count changed");checkGuards(a);
        for(int v=0;v<2;++v) {
          vl_osc_prepared_parameters modelParams{params[v].final.pan,params[v].final.volume,basePitches[v],params[v].final.cutoff,params[v].final.resonance};
          if(block==0) {
            std::array<uint32_t,45> beforeMod{},afterMod{};std::array<uint8_t,112> beforeFilter{},afterFilter{};
            std::array<float,2> beforeGain{},afterGain{};std::array<int32_t,3> beforeRelease{},afterRelease{};
            std::array<uint32_t,6> beforePhase{},afterPhase{};uint8_t beforeStereo=0,afterStereo=0;
            outputSnapshot(outputs[v],beforeMod.data(),beforeFilter.data(),beforeGain.data(),beforeRelease.data());
            corePhases(raws[v],beforePhase.data(),&beforeStereo);
            const auto preservedOutput=b;
            for(int bad=0;bad<9;++bad) {
              auto invalid=modelParams;const auto original=modelParams;int invalidTick=newTick;uint32_t invalidFrames=uint32_t(count);
              if(bad==0)invalidFrames=0;else if(bad==1)invalidFrames=4097;
              else if(bad==2)invalidTick=2;else if(bad==3)invalid.pan=2;
              else if(bad==4)invalid.volume=std::numeric_limits<float>::infinity();
              else if(bad==5)invalid.pitch=2401;else if(bad==6)invalid.mod_x=.251f;
              else if(bad==7)invalid.mod_y=std::numeric_limits<float>::quiet_NaN();
              else coreParam(core,113,1,1);
              const auto preservedParameters=invalid;
              require(!outputRender(outputs[v],&invalid,invalidTick,b.data()+8,invalidFrames),"Unsupported input was accepted");
              require(std::memcmp(&invalid,&preservedParameters,sizeof(invalid))==0 && std::memcmp(&modelParams,&original,sizeof(original))==0,"Rejected call changed parameters");
              require(std::memcmp(b.data(),preservedOutput.data(),b.size()*4)==0,"Rejected call changed output");
              outputSnapshot(outputs[v],afterMod.data(),afterFilter.data(),afterGain.data(),afterRelease.data());
              corePhases(raws[v],afterPhase.data(),&afterStereo);
              require(beforeMod==afterMod && beforeFilter==afterFilter && beforeGain==afterGain && beforeRelease==afterRelease && beforePhase==afterPhase && beforeStereo==afterStereo,"Rejected call changed voice state");
              if(bad==8)coreParam(core,113,0,1);++rejectedCalls;
            }
          }
          require(outputRender(outputs[v],&modelParams,newTick,b.data()+8,uint32_t(count)),"Model output rejected");checkGuards(b);
          const void* editor=load<void*>(reinterpret_cast<void*>(voices[v]),48);
          std::array<uint32_t,45> modulation{};std::array<uint8_t,112> filter{};std::array<float,2> gains{};std::array<int32_t,3> released{};
          outputSnapshot(outputs[v],modulation.data(),filter.data(),gains.data(),released.data());
          if(std::memcmp(static_cast<const char*>(editor)+0x50,modulation.data(),180)!=0 ||
             std::memcmp(static_cast<const char*>(editor)+0x108,filter.data(),112)!=0 ||
             std::memcmp(static_cast<const char*>(editor)+0x40,gains.data(),8)!=0 ||
             load<int>(editor,0xc)!=released[0] || load<int>(editor,0x10)!=released[1] || load<uint8_t>(editor,0x178)!=released[2] ||
             std::bit_cast<uint32_t>(params[v].final.pitch)!=std::bit_cast<uint32_t>(modelParams.pitch)) {
            std::cerr<<"state fixture="<<fixture<<" block="<<block<<" voice="<<v<<'\n';
            const auto* nativeWords=reinterpret_cast<const uint32_t*>(static_cast<const char*>(editor)+0x50);
            for(size_t j=0;j<45;++j)if(nativeWords[j]!=modulation[j])std::cerr<<"mod word="<<j<<" native="<<std::hex<<nativeWords[j]<<" model="<<modulation[j]<<std::dec<<'\n';
            const auto* nativeFilter=reinterpret_cast<const uint32_t*>(static_cast<const char*>(editor)+0x108);
            std::array<uint32_t,28> filterWords{};std::memcpy(filterWords.data(),filter.data(),112);
            for(size_t j=0;j<28;++j)if(nativeFilter[j]!=filterWords[j])std::cerr<<"filter word="<<j<<" native="<<std::hex<<nativeFilter[j]<<" model="<<filterWords[j]<<std::dec<<'\n';
            for(size_t j=0;j<2;++j)std::cerr<<"gain "<<j<<" native="<<std::hex<<load<uint32_t>(editor,0x40+j*4)<<" model="<<std::bit_cast<uint32_t>(gains[j])<<std::dec<<'\n';
            std::cerr<<"release "<<load<int>(editor,0xc)<<'/'<<released[0]<<' '<<load<int>(editor,0x10)<<'/'<<released[1]<<' '<<int(load<uint8_t>(editor,0x178))<<'/'<<released[2]<<'\n';
            std::cerr<<"pitch "<<std::hex<<std::bit_cast<uint32_t>(params[v].final.pitch)<<'/'<<std::bit_cast<uint32_t>(modelParams.pitch)<<std::dec<<'\n';
            throw std::runtime_error("Active pipeline state differs");
          }
          std::array<uint32_t,6> phases;uint8_t stereo;corePhases(raws[v],phases.data(),&stereo);
          require(std::memcmp(reinterpret_cast<const char*>(voices[v])+16,phases.data(),24)==0 && load<uint8_t>(reinterpret_cast<void*>(voices[v]),40)==stereo,"Raw phase/stereo state differs");stateWords+=86;
          for(size_t j=0;j<4;++j) {const auto history=load<double>(editor,0x108+0x28+j*8);require(std::isfinite(history),"Filter history became nonfinite");maxHistory=std::max(maxHistory,std::fabs(history));}
          for(float gain:gains) {require(std::isfinite(gain),"Gain became nonfinite");maxGain=std::max(maxGain,double(std::fabs(gain)));}
        }
        if(std::memcmp(a.data(),b.data(),a.size()*4)!=0) {
          std::cerr<<"fixture="<<fixture<<" block="<<block<<" frames="<<count<<'\n';
          for(size_t i=0;i<a.size();++i)if(std::bit_cast<uint32_t>(a[i])!=std::bit_cast<uint32_t>(b[i])) {std::cerr<<"lane="<<i<<" native="<<std::hex<<std::bit_cast<uint32_t>(a[i])<<" model="<<std::bit_cast<uint32_t>(b[i])<<std::dec<<'\n';break;}
          throw std::runtime_error("Actual GenRender audio differs");
        }
        for(int lane=0;lane<count*2;++lane) {require(std::isfinite(a[size_t(lane)+8]),"Output became nonfinite");maxOutput=std::max(maxOutput,double(std::fabs(a[size_t(lane)+8])));}
        const void* buffers=load<void*>(load<void*>(plugin,0x238),0x18);
        for(size_t offset:{0x18u,0x28u}) {const float* working=load<float*>(buffers,offset);for(int lane=0;lane<count*2;++lane) {require(std::isfinite(working[lane]),"Working sample became nonfinite");maxWorkingSample=std::max(maxWorkingSample,double(std::fabs(working[lane])));}}
        ++blocks;floats+=size_t(count)*2;
      }
      for(int v=0;v<2;++v) {outputDestroy(outputs[v]);kill(plugin,voices[v]);}
      coreDestroy(core);method<void(*)(void*)>(plugin,0xc8)(plugin);
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<std::setprecision(17)<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"real_native_factory_fixtures\":360,\"two_live_voices\":true,\"actual_GenRender_blocks\":"<<blocks
             <<",\"stereo_float_values_exact\":"<<floats<<",\"state_values_exact\":"<<stateWords<<",\"actual_native441sample_release_tables\":"<<releaseTables
             <<",\"rejection_preservation_cases\":"<<rejectedCalls<<",\"maximum_observed_filter_history\":"<<maxHistory<<",\"maximum_observed_output\":"<<maxOutput<<",\"maximum_observed_working_sample\":"<<maxWorkingSample<<",\"maximum_observed_gain\":"<<maxGain<<",\"prepared_active_editor_context\":true,\"host_pan_callback_controlled\":true,\"native_factory_rebuilt\":false,\"bounded_modulation_single_filter_pipeline_rebuilt\":true,\"native_editor_rebuilt\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_native_factory.h"
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
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==4,"Usage: channel <native wrapper> <rebuilt channel> <private directory/>");
    require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Vector dependency identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib")=="d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Engine identity mismatch");
    [NSApplication sharedApplication];dataPath=argv[3];hostMethods.fill(reinterpret_cast<void*>(&noop));pathMethods.fill(reinterpret_cast<void*>(&noop));
    hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);hostMethods[0xf0/8]=reinterpret_cast<void*>(&nativeNotify);
    alignas(16) std::array<std::byte,512> host{};auto** hostVMT=hostMethods.data();std::memcpy(host.data(),&hostVMT,8);
    std::vector<float> tables(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(tables.data(),tables.size()));std::array<const float*,6> tablePointers{};
    for(int i=0;i<6;++i) {tablePointers[i]=tables.data()+i*16384;std::memcpy(host.data()+0x18+i*8,&tablePointers[i],8);}
    void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt load failed");
    const char*enginePath="/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib";
    require(hashFile(enginePath)=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Host engine identity changed");
    void*hostEngine=dlopen(enginePath,RTLD_NOW|RTLD_LOCAL);require(hostEngine,"Host engine load failed");Dl_info hostEngineInfo{};require(dladdr(dlsym(hostEngine,"CreateFruityInstance"),&hostEngineInfo),"Host engine base missing");auto*engineBase=static_cast<char*>(hostEngineInfo.dli_fbase);using Ctor=void*(*)(void*,intptr_t,void*);auto hostCtor=reinterpret_cast<Ctor>(engineBase+0xb4cd20),pluginCtor=reinterpret_cast<Ctor>(engineBase+0xb4c7c0);
    auto cppFactory=symbol<vl_private_osc::Plugin*(*)(void*,intptr_t)>(rebuilt,"CreatePlugInstance");auto prepareFactory=symbol<int(*)(vl_private_osc::Plugin*,int32_t,double,uint32_t)>(rebuilt,"vl_private_osc_prepare");auto factoryChannel=symbol<vl_osc_multimode_channel*(*)(vl_private_osc::Plugin*)>(rebuilt,"vl_private_osc_channel");
    auto create=symbol<void*(*)(void*,intptr_t)>(native,"CreatePlugInstance");Dl_info info{};require(dladdr(reinterpret_cast<void*>(create),&info),"No native base");
    auto nativeCount=reinterpret_cast<int(*)(const void*)>(static_cast<char*>(info.dli_fbase)+0x44990);auto nativeQuick=reinterpret_cast<void(*)(void*)>(static_cast<char*>(info.dli_fbase)+0x1bd320);
    [[maybe_unused]] auto channelCreate=symbol<vl_osc_multimode_channel*(*)(vl_osc_compute_lr,vl_osc_multimode_channel_notify_kill,void*,int,double,uint32_t,const float* const*)>(rebuilt,"vl_osc_multimode_channel_create");
    [[maybe_unused]] auto channelDestroy=symbol<void(*)(vl_osc_multimode_channel*)>(rebuilt,"vl_osc_multimode_channel_destroy");auto channelParameter=symbol<int32_t(*)(vl_osc_multimode_channel*,int32_t,int32_t,uint32_t)>(rebuilt,"vl_osc_multimode_channel_parameter");
    [[maybe_unused]] auto channelRestore=symbol<int(*)(vl_osc_multimode_channel*,const uint8_t*,size_t)>(rebuilt,"vl_osc_multimode_channel_restore");[[maybe_unused]] auto channelMax=symbol<void(*)(vl_osc_multimode_channel*,int32_t)>(rebuilt,"vl_osc_multimode_channel_max_poly");
    auto channelTrigger=symbol<vl_osc_multimode_channel_voice*(*)(vl_osc_multimode_channel*,vl_osc_multimode_channel_parameters*,intptr_t)>(rebuilt,"vl_osc_multimode_channel_trigger");
    [[maybe_unused]] auto channelRelease=symbol<int(*)(vl_osc_multimode_channel*,vl_osc_multimode_channel_voice*)>(rebuilt,"vl_osc_multimode_channel_release");auto channelQuick=symbol<int(*)(vl_osc_multimode_channel*,vl_osc_multimode_channel_voice*)>(rebuilt,"vl_osc_multimode_channel_quick_release");
    [[maybe_unused]] auto channelKill=symbol<int(*)(vl_osc_multimode_channel*,vl_osc_multimode_channel_voice*)>(rebuilt,"vl_osc_multimode_channel_kill");[[maybe_unused]] auto channelTick=symbol<int(*)(vl_osc_multimode_channel*)>(rebuilt,"vl_osc_multimode_channel_new_tick");
    auto channelSeek=symbol<int(*)(vl_osc_multimode_channel*,double)>(rebuilt,"vl_osc_multimode_channel_song_position");
    auto contextSnapshot=symbol<int(*)(const vl_osc_multimode_channel*,vl_osc_sync_lfo_state*)>(rebuilt,"vl_osc_multimode_channel_context_snapshot");
    auto channelRender=symbol<int(*)(vl_osc_multimode_channel*,float*,uint32_t)>(rebuilt,"vl_osc_multimode_channel_render");auto channelCount=symbol<size_t(*)(const vl_osc_multimode_channel*)>(rebuilt,"vl_osc_multimode_channel_voice_count");
    auto channelSnapshot=symbol<int(*)(const vl_osc_multimode_channel*,const vl_osc_multimode_channel_voice*,uint32_t*,uint8_t*,float*,int32_t*,uint32_t*,uint8_t*)>(rebuilt,"vl_osc_multimode_channel_snapshot");
    struct Record {uintptr_t native;vl_osc_multimode_channel_voice* model;intptr_t tag;std::unique_ptr<Parameters> parameters;std::unique_ptr<vl_osc_multimode_channel_parameters> modelParameters;int filterMode;};
    static_assert(sizeof(Parameters)==sizeof(vl_osc_multimode_channel_parameters));
    std::array<void*,5> streamMethods{};streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);
    std::mt19937 random(0x19ca710);std::array<size_t,8> modeTriggers{};size_t capturedModeValues=0,mixedModeRenders=0;
    const std::array<int,8> nativeTypes{0,1,2,3,4,1,6,6};const std::array<uint8_t,8> nativeDouble{0,0,0,0,0,1,0,1};
    for(size_t mode=0;mode<8;++mode)require(load<uint8_t>(info.dli_fbase,0x262fb0+2*mode)==nativeTypes[mode] && load<uint8_t>(info.dli_fbase,0x262fb1+2*mode)==nativeDouble[mode],"Native public filter-mode table differs");
    size_t seeks=0,registryValues=0,releaseRefreshFrames=0,refreshCandidates=0,rejectedTimes=0,triggers=0,ordinaryReleases=0,explicitQuickReleases=0,polyphonyQuickReleases=0,renderCalls=0,notices=0,stateValues=0,floatValues=0,deletions=0,emptyRenders=0,destroyedLive=0,rejectedCalls=0;
    double maxHistory=0,maxGain=0,maxOutput=0,maxWorkingSample=0;
    constexpr int fixtureCount=180;const std::array<int,7> limits{-2,0,1,2,4,8,32};const std::array<int,12> lengths{1,2,3,7,8,9,15,16,63,441,1024,4096};
    for(int fixture=0;fixture<fixtureCount;++fixture) {
      void* plugin=create(host.data(),42);require(plugin,"Factory failed");const int rate=std::array<int,6>{44100,48000,96000,22050,8000,384000}[fixture%6];
      const float tempo=std::array<float,6>{60,90,120,137,240,1000}[fixture%6];const int ppq=std::array<int,6>{4,48,96,240,960,4096}[(fixture/6)%6];
      std::vector<std::pair<intptr_t,int32_t>> modelNotices;std::array<void*,96>modelHostMethods{};modelHostMethods[0xc8/8]=reinterpret_cast<void*>(&modelHostDispatch);modelHostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);modelHostMethods[0xf0/8]=reinterpret_cast<void*>(&modelHostNotify);ModelHost modelHost{modelHostMethods.data(),&modelNotices};void*hostAdapter=hostCtor(engineBase+0x1497870,1,&modelHost);require(hostAdapter,"Model host adapter failed");void*cppHost=static_cast<char*>(hostAdapter)+16;auto*cppPlugin=cppFactory(cppHost,42);require(cppPlugin&&cppPlugin->info->parameters==114,"Native CPP factory failed");void*modelAdapter=pluginCtor(engineBase+0x1497618,1,cppPlugin);require(modelAdapter&&load<intptr_t>(modelAdapter,8)==42&&load<const vl_private_osc::Info*>(modelAdapter,16)==cppPlugin->info,"Model engine plugin adapter failed");require(prepareFactory(cppPlugin,rate,double(tempo),uint32_t(ppq)),"Fixed prepared factory context failed");auto*channel=factoryChannel(cppPlugin);require(channel,"Factory channel missing");
      auto modelParameter=method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(modelAdapter,0xf8);auto modelEvent=method<int32_t(*)(void*,int32_t,int32_t,int32_t)>(modelAdapter,0xf0);auto modelDispatch=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(modelAdapter,0xd0);
      auto modelTrigger=method<intptr_t(*)(void*,void*,intptr_t)>(modelAdapter,0x110);auto modelRelease=method<void(*)(void*,intptr_t)>(modelAdapter,0x118);auto modelKill=method<void(*)(void*,intptr_t)>(modelAdapter,0x120);auto modelRender=method<void(*)(void*,float*,int32_t&)>(modelAdapter,0x108);auto modelTick=method<void(*)(void*)>(modelAdapter,0x138);auto modelState=method<void(*)(void*,void*,int32_t)>(modelAdapter,0xe0);
      const auto destroyModel=[&](){method<void(*)(void*)>(modelAdapter,0xc8)(modelAdapter);method<void(*)(void*,intptr_t)>(modelAdapter,0x60)(modelAdapter,1);method<void(*)(void*,intptr_t)>(hostAdapter,0x60)(hostAdapter,1);};
      auto state=method<void(*)(void*,void*,int)>(plugin,0xe0);Stream stream{streamMethods.data(),{},0};state(plugin,&stream,1);require(stream.bytes.size()==460,"State framing changed");stream.bytes[92]=uint8_t(fixture%2);state(plugin,&stream,0);stream.cursor=0;modelState(modelAdapter,&stream,0);
      auto dispatch=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(plugin,0xd0);dispatch(plugin,4,0,rate);std::array<int,3> signature{16,4,ppq};dispatch(plugin,14,0,reinterpret_cast<intptr_t>(signature.data()));
      auto event=method<int(*)(void*,int,int,int)>(plugin,0xf0);event(plugin,0,int(std::bit_cast<uint32_t>(tempo)),0);auto parameter=method<int(*)(void*,int,int,uint32_t)>(plugin,0xf8);
      const auto set=[&](int index,int value){parameter(plugin,index,value,1);modelParameter(modelAdapter,index,value,1);};
      const std::array<int,21> mins{-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0};const std::array<int,21> maxs{64,4,24,100,64,50,128,64,4,24,100,64,50,128,64,4,24,100,64,50,0};
      for(int i=0;i<21;++i)set(i,mins[i]+int(random()%uint32_t(maxs[i]-mins[i]+1)));
      for(int group=0;group<5;++group) {
        const int choice=(fixture+group)%6;const std::array<int,6> times{100,512,2000,5000,9000,16000};
        std::array<int,17> controls{(fixture+group)%64,group==1 ? 1:(fixture+group)%5!=0 ? 1:0,choice%3==0 ? 2000:100,times[size_t(choice)],choice%3==1 ? 512:100,
          times[size_t((choice+2)%6)],64,times[size_t((choice+4)%6)],group==4 ? int(random()%257)-128:group==2 || group==3 ? int(random()%65)-32:int(random()%257)-128,
          choice%3==2 ? 2000:100,choice%2 ? 3000:100,group==2 || group==3 ? int(random()%65)-32:int(random()%257)-128,times[size_t((choice+3)%6)],(fixture+group)%3,int(random()%257)-128,int(random()%257)-128,int(random()%257)-128};
        for(int field=0;field<17;++field)set(23+group*17+field,controls[size_t(field)]);
      }
      set(110,int(random()%257));set(111,int(random()%257));set(113,fixture%8);
      auto trigger=method<uintptr_t(*)(void*,void*,intptr_t)>(plugin,0x110);auto release=method<void(*)(void*,uintptr_t)>(plugin,0x118);auto kill=method<void(*)(void*,uintptr_t)>(plugin,0x120);
      auto tick=method<void(*)(void*)>(plugin,0x138);auto render=method<void(*)(void*,float*,int*)>(plugin,0x108);std::vector<Record> voices;int ordinal=0;
      const auto compare=[&]() {
        Stream originalSave{streamMethods.data(),{},0},modelSave{streamMethods.data(),{},0};state(plugin,&originalSave,1);modelState(modelAdapter,&modelSave,1);require(originalSave.bytes.size()==460&&modelSave.bytes.size()==460,"Factory state length differs");for(size_t byte=0;byte<460;++byte)if(byte<93||byte>=96)require(originalSave.bytes[byte]==modelSave.bytes[byte],"Factory semantic state byte differs");
        vl_osc_sync_lfo_state metadata{};require(contextSnapshot(channel,&metadata),"Context snapshot failed");
        const void* context=load<void*>(plugin,0x238);const void* nativeCfg=load<void*>(plugin,0x240);const void* list=load<void*>(context,0x28);
        const int registered=load<int>(list,0x10);auto* items=load<const void* const*>(list,8);uint32_t mask=0;
        require(registered==int(metadata.registered_count) && load<uint8_t>(list,0x18)==0,"Registration count/policy differs");
        for(int i=0;i<registered;++i) {const auto offset=static_cast<const char*>(items[i])-(static_cast<const char*>(nativeCfg)+8);require(offset>=0 && offset%160==0 && offset/160<5,"Unknown registry group");const uint32_t group=uint32_t(offset/160);require(group==metadata.registered_order[size_t(i)],"Registration order differs");mask|=1u<<group;}
        require(mask==metadata.registered_mask && load<uint32_t>(context,0x20)==metadata.pending_tick && load<uint32_t>(nativeCfg,0x334)==metadata.dirty && load<uint8_t>(context,0x24)==metadata.release_refresh,"Context metadata differs");
        for(size_t group=0;group<5;++group)require(load<uint32_t>(nativeCfg,8+160*group+0x78)==metadata.phases[group],"Context phase differs");registryValues+=10+size_t(registered);
        require(nativeCount(load<void*>(plugin,0x200))==int(voices.size()) && channelCount(channel)==voices.size(),"Voice counts differ");
        for(const auto& voice:voices) {
          const void* editor=load<void*>(reinterpret_cast<void*>(voice.native),48);
          require(load<int>(editor,0x108)==nativeTypes[size_t(voice.filterMode)] && load<uint8_t>(editor,0x170)==nativeDouble[size_t(voice.filterMode)],"Native per-voice captured mode changed");capturedModeValues+=2;
          std::array<uint32_t,45> mod{};std::array<uint8_t,112> filter{};std::array<float,2> gain{};std::array<int32_t,3> released{};std::array<uint32_t,6> phase{};uint8_t stereo=0;
          require(channelSnapshot(channel,voice.model,mod.data(),filter.data(),gain.data(),released.data(),phase.data(),&stereo),"Snapshot failed");
          if(std::memcmp(static_cast<const char*>(editor)+0x50,mod.data(),180)!=0 || std::memcmp(static_cast<const char*>(editor)+0x108,filter.data(),112)!=0 || std::memcmp(static_cast<const char*>(editor)+0x40,gain.data(),8)!=0 ||
             load<int>(editor,0xc)!=released[0] || load<int>(editor,0x10)!=released[1] || load<uint8_t>(editor,0x178)!=released[2] || std::memcmp(reinterpret_cast<const char*>(voice.native)+16,phase.data(),24)!=0 || load<uint8_t>(reinterpret_cast<void*>(voice.native),40)!=stereo) {
            std::cerr<<"fixture="<<fixture<<" tag="<<voice.tag<<'\n';throw std::runtime_error("Integrated channel state differs");
          }
          require(std::memcmp(voice.parameters.get(),voice.modelParameters.get(),40)==0,"Borrowed parameters differ");stateValues+=95;
          if(load<int>(editor,0x108)==0) {
            for(size_t i=0;i<4;++i) {const double value=load<double>(editor,0x108+0x28+i*8);require(std::isfinite(value),"Single filter history became nonfinite");maxHistory=std::max(maxHistory,std::fabs(value));}
          }else for(size_t i=0;i<16;++i) {const float value=load<float>(editor,0x108+0x28+i*4);require(std::isfinite(value),"Positive filter history became nonfinite");maxHistory=std::max(maxHistory,double(std::fabs(value)));}
          for(float value:gain) {require(std::isfinite(value),"Gain became nonfinite");maxGain=std::max(maxGain,double(std::fabs(value)));}
        }
      };
      if(fixture%4==0) {std::array<float,2> a{-.25f,.25f},b=a;tick(plugin);modelTick(modelAdapter);int count=1;render(plugin,a.data(),&count);int32_t modelCount=1;modelRender(modelAdapter,b.data(),modelCount);require(modelCount==1,"Empty length changed");require(a==b,"Empty render differs");++emptyRenders;}
      for(int round=0;round<24;++round) {
        const int limit=limits[size_t((fixture+round)%int(limits.size()))];event(plugin,1,limit,0);modelEvent(modelAdapter,1,limit,0);
        if(!voices.empty()) {
          auto& voice=voices[size_t(random()%voices.size())];release(plugin,voice.native);modelRelease(modelAdapter,reinterpret_cast<intptr_t>(voice.model));++ordinaryReleases;compare();
          if(round%4==0) {release(plugin,voice.native);modelRelease(modelAdapter,reinterpret_cast<intptr_t>(voice.model));++ordinaryReleases;compare();}
          if(round%5==0) {auto& quick=voices[size_t(random()%voices.size())];nativeQuick(load<void*>(reinterpret_cast<void*>(quick.native),48));require(channelQuick(channel,quick.model),"Quick release failed");++explicitQuickReleases;compare();}
        }
        set(113,(fixture+round)%8);
        set(23+17*((fixture+round)%5),(fixture*13+round*7)%64);
        if(round%3==1)set(41,(round/3)%2);
        compare();
        if(round%3==0) {
          const std::array<double,12> times{0,1,-1,12345.625,-12345.625,2147483647.75,-2147483648.75,4294967296.625,-4294967297.625,0x1p63-1024,-0x1p63,0x1p52+0.5};
          hostTicks=times[size_t((fixture+round)%int(times.size()))];dispatch(plugin,13,0,0);modelDispatch(modelAdapter,13,0,0);++seeks;compare();
        }
        for(int note=0;note<1+round%2;++note) {
          if(limit>0 && voices.size()>=size_t(limit))++polyphonyQuickReleases;
          auto p=std::make_unique<Parameters>();p->initial.pitch=float(int(random()%4801)-2400);p->final=p->initial;auto q=std::make_unique<vl_osc_multimode_channel_parameters>();std::memcpy(q.get(),p.get(),40);
          const intptr_t tag=fixture*1000+ordinal++;auto original=trigger(plugin,p.get(),tag);auto* model=reinterpret_cast<vl_osc_multimode_channel_voice*>(modelTrigger(modelAdapter,q.get(),tag));require(original && model && reinterpret_cast<intptr_t>(model)!=-1,"Trigger failed");voices.push_back({original,model,tag,std::move(p),std::move(q),(fixture+round)%8});++modeTriggers[size_t((fixture+round)%8)];++triggers;compare();
        }
        const int count=lengths[size_t((fixture+round)%int(lengths.size()))];std::vector<float> a(size_t(count)*2+16,1234.5f);
        for(int lane=0;lane<count*2;++lane)a[size_t(lane)+8]=float(int(random()%2001)-1000)/1000.0f;auto b=a;
        for(auto& voice:voices) {auto& p=*voice.parameters;p.final=p.initial;p.final.pan=float(int(random()%2001)-1000)/1000.0f;p.final.volume=float(random()%1001)/1000.0f;p.final.pitch=float(int(random()%4801)-2400);p.final.cutoff=float(int(random()%501)-250)/1000.0f;p.final.resonance=float(int(random()%501)-250)/1000.0f;std::memcpy(voice.modelParameters.get(),&p,40);}
        const bool newTick=(fixture+round)%4!=3;if(newTick) {tick(plugin);modelTick(modelAdapter);}nativeNotices.clear();modelNotices.clear();int frameCount=count;
        if(round==0) {
          const auto saved=b;const auto callbacks=modelNotices;
          require(!channelRender(channel,b.data()+8,0),"Zero-frame call accepted");++rejectedCalls;
          require(!channelRender(channel,b.data()+8,4097),"Oversized call accepted");++rejectedCalls;
          channelParameter(channel,113,8,1);require(!channelRender(channel,b.data()+8,uint32_t(count)),"Unsupported configuration accepted");channelParameter(channel,113,(fixture+round)%8,1);++rejectedCalls;
          const auto before=*voices[0].modelParameters;voices[0].modelParameters->final.pitch=2401;
          require(!channelRender(channel,b.data()+8,uint32_t(count)),"Out-of-range pitch accepted");*voices[0].modelParameters=before;++rejectedCalls;
          auto invalid=before;invalid.final.pitch=2401;require(!channelTrigger(channel,&invalid,-999),"Invalid trigger accepted");++rejectedCalls;
          vl_osc_sync_lfo_state beforeContext{};require(contextSnapshot(channel,&beforeContext),"Rejected-time context snapshot failed");
          for(double invalidTime:{std::numeric_limits<double>::infinity(),-std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN(),0x1p63,std::nextafter(-0x1p63,-std::numeric_limits<double>::infinity())}) {
            require(!channelSeek(channel,invalidTime),"Invalid seek accepted");vl_osc_sync_lfo_state afterContext{};require(contextSnapshot(channel,&afterContext),"After-rejection context snapshot failed");
            require(std::memcmp(&beforeContext,&afterContext,sizeof(beforeContext))==0,"Invalid seek changed context");++rejectedTimes;compare();
          }
          require(std::memcmp(saved.data(),b.data(),b.size()*4)==0 && callbacks==modelNotices,"Rejected call changed output/notifications");compare();
        }
        uint32_t presentModes=0;for(const auto& voice:voices)presentModes|=1u<<voice.filterMode;if(std::popcount(presentModes)>1)++mixedModeRenders;
        const void* beforeConfig=load<void*>(plugin,0x240);
        if(load<uint32_t>(beforeConfig,0x334)==1 && load<int>(beforeConfig,0xac)==0)
          for(const auto& voice:voices)if(load<int>(load<void*>(reinterpret_cast<void*>(voice.native),48),0x80)==6)++refreshCandidates;
        render(plugin,a.data()+8,&frameCount);if(load<uint8_t>(load<void*>(plugin,0x238),0x24))++releaseRefreshFrames;int32_t modelFrameCount=count;modelRender(modelAdapter,b.data()+8,modelFrameCount);require(modelFrameCount==count,"CPP frame count changed");require(frameCount==count,"Native frame count changed");++renderCalls;
        for(int j=0;j<8;++j)require(a[size_t(j)]==1234.5f && b[size_t(j)]==1234.5f && a[size_t(count)*2+8+size_t(j)]==1234.5f && b[size_t(count)*2+8+size_t(j)]==1234.5f,"Output guard overwritten");
        if(std::memcmp(a.data(),b.data(),a.size()*4)!=0) {std::cerr<<"audio fixture="<<fixture<<" round="<<round<<" voices="<<voices.size()<<'\n';compare();for(size_t i=8;i<size_t(count)*2+8;++i)if(std::bit_cast<uint32_t>(a[i])!=std::bit_cast<uint32_t>(b[i])) {std::cerr<<"lane="<<i-8<<" native="<<std::hex<<std::bit_cast<uint32_t>(a[i])<<" model="<<std::bit_cast<uint32_t>(b[i])<<std::dec<<'\n';break;}throw std::runtime_error("Overwritten channel audio differs");}
        for(int lane=0;lane<count*2;++lane) {require(std::isfinite(a[size_t(lane)+8]),"Output became nonfinite");maxOutput=std::max(maxOutput,double(std::fabs(a[size_t(lane)+8])));}
        const void* buffers=load<void*>(load<void*>(plugin,0x238),0x18);
        for(size_t offset:{0x18u,0x28u}) {const float* working=load<float*>(buffers,offset);for(int lane=0;lane<count*2;++lane) {require(std::isfinite(working[lane]),"Working sample became nonfinite");maxWorkingSample=std::max(maxWorkingSample,double(std::fabs(working[lane])));}}floatValues+=size_t(count)*2;require(nativeNotices==modelNotices,"Notification order/flags differ");notices+=nativeNotices.size();compare();
        if(round%4!=1)for(const auto& notice:nativeNotices) {auto it=std::find_if(voices.begin(),voices.end(),[&](const auto& voice){return voice.tag==notice.first;});require(it!=voices.end(),"Unknown notification");kill(plugin,it->native);modelKill(modelAdapter,reinterpret_cast<intptr_t>(it->model));voices.erase(it);++deletions;compare();}
        if(round%5==0 && !voices.empty()) {const size_t index=size_t(random()%voices.size());kill(plugin,voices[index].native);modelKill(modelAdapter,reinterpret_cast<intptr_t>(voices[index].model));voices.erase(voices.begin()+static_cast<ptrdiff_t>(index));++deletions;compare();}
      }
      if(fixture%3==0) {
        compare();destroyedLive+=voices.size();
        for(const auto& voice:voices)kill(plugin,voice.native);
        method<void(*)(void*)>(plugin,0xc8)(plugin);destroyModel();voices.clear();
      } else {
        for(const auto& voice:voices) {kill(plugin,voice.native);modelKill(modelAdapter,reinterpret_cast<intptr_t>(voice.model));++deletions;}voices.clear();compare();destroyModel();method<void(*)(void*)>(plugin,0xc8)(plugin);
      }
    }
    require(hostTimeRequests==seeks&&modelTimeRequests==seeks,"Host time request count differs");dlclose(rebuilt);dlclose(native);dlclose(hostEngine);
    std::cout<<std::setprecision(17)<<"{\"status\":\"passed\",\"private_native_CPP_factory_replayed\":true,\"actual_native_factory_fixtures\":"<<fixtureCount<<",\"voice_triggers\":"<<triggers
      <<",\"public_song_position_cases\":"<<seeks<<",\"controlled_host_time_requests\":"<<hostTimeRequests<<",\"exact_context_values\":"<<registryValues<<",\"release_refresh_frames\":"<<releaseRefreshFrames<<",\"pre_render_volume_stage6_refresh_candidates\":"<<refreshCandidates<<",\"rejected_time_preservation_cases\":"<<rejectedTimes
      <<",\"captured_filter_mode_values\":"<<capturedModeValues<<",\"heterogeneous_filter_render_cases\":"<<mixedModeRenders
      <<",\"ordinary_release_cases\":"<<ordinaryReleases<<",\"explicit_quick_release_cases\":"<<explicitQuickReleases<<",\"polyphony_quick_release_cases\":"<<polyphonyQuickReleases
      <<",\"actual_GenRender_calls\":"<<renderCalls<<",\"host_completion_notifications\":"<<notices<<",\"exact_state_values\":"<<stateValues<<",\"exact_overwritten_host_floats\":"<<floatValues
      <<",\"per_public_mode_triggers\":["<<modeTriggers[0]<<','<<modeTriggers[1]<<','<<modeTriggers[2]<<','<<modeTriggers[3]<<','<<modeTriggers[4]<<','<<modeTriggers[5]<<','<<modeTriggers[6]<<','<<modeTriggers[7]<<']'
      <<",\"paired_explicit_deletions\":"<<deletions<<",\"empty_render_cases\":"<<emptyRenders<<",\"model_voices_destroyed_with_live_channel\":"<<destroyedLive<<",\"new_api_rejection_preservation_cases\":"<<rejectedCalls<<",\"maximum_observed_filter_history\":"<<maxHistory<<",\"maximum_observed_gain\":"<<maxGain<<",\"maximum_observed_output\":"<<maxOutput<<",\"maximum_observed_working_sample\":"<<maxWorkingSample<<",\"private_native_CPP_factory_rebuilt\":true,\"actual_engine_plugin_and_host_adapters\":true,\"explicit_quick_release_uses_component_helper\":true,\"context_changes_only_before_voices\":true,\"native_factory_rebuilt\":false,\"actual_host_scheduling_rebuilt\":false,\"native_editor_rebuilt\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

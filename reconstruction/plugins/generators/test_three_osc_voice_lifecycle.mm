#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_voice_lifecycle.h"
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
struct Object {void** methods;};Object pathObject{pathMethods.data()};const char* dataPath;
extern "C" intptr_t noop() {return 0;}
extern "C" intptr_t hostDispatch(void*,intptr_t,intptr_t id,intptr_t,intptr_t) {
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
std::vector<std::pair<intptr_t,int32_t>> notifications;
extern "C" void notifyKill(void*,intptr_t tag,int32_t flag) {notifications.emplace_back(tag,flag);}
struct Levels {float pan=0,volume=0.8f,pitch=-300,cutoff=0,resonance=0;};
struct Parameters {Levels initial,final;};static_assert(sizeof(Parameters)==40);
}
int main(int argc,char** argv) {
 @autoreleasepool {
  try {
    require(argc==4,"Usage: lifecycle <native wrapper> <rebuilt helper> <private directory/>");
    require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Vector dependency identity mismatch");
    require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib")=="d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Engine identity mismatch");
    [NSApplication sharedApplication];dataPath=argv[3];hostMethods.fill(reinterpret_cast<void*>(&noop));pathMethods.fill(reinterpret_cast<void*>(&noop));
    hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);hostMethods[0xf0/8]=reinterpret_cast<void*>(&notifyKill);
    alignas(16) std::array<std::byte,512> host{};auto** hostVMT=hostMethods.data();std::memcpy(host.data(),&hostVMT,8);
    void* native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Native load failed");
    void* rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt helper load failed");
    auto create=symbol<void*(*)(void*,intptr_t)>(native,"CreatePlugInstance");Dl_info info{};require(dladdr(reinterpret_cast<void*>(create),&info),"No native image base");
    auto nativeCount=reinterpret_cast<int(*)(const void*)>(static_cast<char*>(info.dli_fbase)+0x44990);
    auto nativeQuick=reinterpret_cast<void(*)(void*)>(static_cast<char*>(info.dli_fbase)+0x1bd320);
    auto nativeApply=reinterpret_cast<void(*)(void*,void*,float*,int)>(static_cast<char*>(info.dli_fbase)+0x1c3100);
    auto nativeFinished=reinterpret_cast<uint8_t(*)(const void*)>(static_cast<char*>(info.dli_fbase)+0x1bd360);
    auto select=symbol<int32_t(*)(const uint8_t*,int32_t,int32_t)>(rebuilt,"vl_osc_lifecycle_select");
    auto quick=symbol<void(*)(vl_osc_lifecycle_state*)>(rebuilt,"vl_osc_lifecycle_quick_release");
    auto advance=symbol<void(*)(vl_osc_lifecycle_state*,int32_t)>(rebuilt,"vl_osc_lifecycle_advance");
    auto finished=symbol<int(*)(const vl_osc_lifecycle_state*,int32_t)>(rebuilt,"vl_osc_lifecycle_finished");
    struct Record {uintptr_t native;intptr_t tag;std::unique_ptr<Parameters> parameters;vl_osc_lifecycle_state state{-1,0,0};};
    std::array<void*,5> streamMethods{};streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);
    std::mt19937 random(0x1bcd90);size_t triggers=0,quickReleases=0,normalReleases=0,renderCalls=0,notices=0,stateValues=0,deletions=0,directCases=0;
    constexpr int fixtureCount=120;const std::array<int,7> limits{-2,0,1,2,4,8,32};const std::array<int,8> lengths{1,7,8,63,440,441,442,1024};
    for(int fixture=0;fixture<fixtureCount;++fixture) {
      void* plugin=create(host.data(),42);require(plugin,"Factory failed");
      auto state=method<void(*)(void*,void*,int)>(plugin,0xe0);Stream stream{streamMethods.data(),{},0};state(plugin,&stream,1);require(stream.bytes.size()==460,"Unexpected state frame");stream.bytes[92]=1;state(plugin,&stream,0);
      const int releaseLength=load<int>(load<void*>(load<void*>(plugin,0x238),8),0x3c);require(releaseLength==441,"Unexpected release context");
      auto trigger=method<uintptr_t(*)(void*,void*,intptr_t)>(plugin,0x110);auto release=method<void(*)(void*,uintptr_t)>(plugin,0x118);
      auto kill=method<void(*)(void*,uintptr_t)>(plugin,0x120);auto tick=method<void(*)(void*)>(plugin,0x138);
      auto render=method<void(*)(void*,float*,int*)>(plugin,0x108);auto event=method<int(*)(void*,int,int,int)>(plugin,0xf0);
      std::vector<Record> voices;int ordinal=0;
      const auto compare=[&]() {
        require(nativeCount(load<void*>(plugin,0x200))==int(voices.size()),"Voice list count differs");
        for(const auto& voice:voices) {
          const void* editor=load<void*>(reinterpret_cast<void*>(voice.native),48);
          require(load<intptr_t>(reinterpret_cast<void*>(voice.native),0)==voice.tag,"Voice tag differs");
          require(load<int>(editor,0xc)==voice.state.position && load<int>(editor,0x10)==voice.state.wait_frames && load<uint8_t>(editor,0x178)==voice.state.released,"Release metadata differs");
          require(int(nativeFinished(editor))==finished(&voice.state,releaseLength),"Completion helper differs");stateValues+=5;
        }
      };
      for(int round=0;round<30;++round) {
        const int limit=limits[size_t((fixture+round)%int(limits.size()))];event(plugin,1,limit,0);require(load<int>(plugin,0xdc)==limit,"Max-poly event differs");
        if(!voices.empty()) {
          auto& voice=voices[size_t(random()%voices.size())];release(plugin,voice.native);quick(&voice.state);++normalReleases;compare();
          if(round%4==0) {release(plugin,voice.native);quick(&voice.state);++normalReleases;compare();}
        }
        for(int note=0;note<1+round%3;++note) {
          std::vector<uint8_t> flags;for(const auto& voice:voices)flags.push_back(voice.state.released);
          const int selected=select(flags.data(),int32_t(flags.size()),limit);
          if(selected>=0) {require(size_t(selected)<voices.size(),"Selected voice outside list");quick(&voices[size_t(selected)].state);++quickReleases;}
          auto parameters=std::make_unique<Parameters>();parameters->initial.pitch=float(int(random()%2401)-1200);parameters->final=parameters->initial;
          const intptr_t tag=fixture*1000+ordinal++;uintptr_t original=trigger(plugin,parameters.get(),tag);require(original,"Native trigger failed");
          voices.push_back({original,tag,std::move(parameters),{-1,0,0}});++triggers;compare();
          if(round==0 && note==0) {
            auto* editor=load<char*>(reinterpret_cast<void*>(original),48);
            std::array<uint8_t,416> saved{};std::memcpy(saved.data(),editor,saved.size());
            for(int position:{-1,0,440,441,1024,INT32_MAX-4096})for(int wait:{0,1,63,8192})for(uint8_t flag:{uint8_t(0),uint8_t(1)}) {
              std::memcpy(editor,saved.data(),saved.size());std::memcpy(editor+0xc,&position,4);std::memcpy(editor+0x10,&wait,4);editor[0x178]=char(flag);
              auto expected=saved;std::memcpy(expected.data()+0xc,&position,4);std::memcpy(expected.data()+0x10,&wait,4);expected[0x178]=flag;
              vl_osc_lifecycle_state model{position,wait,flag};quick(&model);nativeQuick(editor);
              std::memcpy(expected.data()+0xc,&model.position,4);std::memcpy(expected.data()+0x10,&model.wait_frames,4);expected[0x178]=model.released;
              require(std::memcmp(editor,expected.data(),416)==0,"Quick release changed unrelated voice storage");
              require(int(nativeFinished(editor))==finished(&model,releaseLength),"Direct completion mismatch");
              const int count=lengths[size_t(directCases%lengths.size())];std::vector<float> output(size_t(count)*2+16,1234.5f);std::fill(output.begin()+8,output.begin()+8+count*2,.25f);
              nativeApply(load<void*>(load<void*>(plugin,0x238),8),editor+8,output.data()+8,count);advance(&model,count);
              require(load<int>(editor,0xc)==model.position && load<int>(editor,0x10)==model.wait_frames && load<uint8_t>(editor,0x178)==model.released,"Direct advance metadata mismatch");
              for(int i=0;i<8;++i)require(output[size_t(i)]==1234.5f && output[size_t(count)*2+8+size_t(i)]==1234.5f,"Direct release guard changed");
              stateValues+=7;++directCases;
            }
            std::memcpy(editor,saved.data(),saved.size());compare();
          }
        }
        if(round%3!=2) {
          const int count=lengths[size_t((fixture+round)%int(lengths.size()))];std::vector<float> output(size_t(count)*2+16,1234.5f);std::fill(output.begin()+8,output.begin()+8+count*2,0);
          for(auto& voice:voices)voice.parameters->final=voice.parameters->initial;
          notifications.clear();tick(plugin);int frameCount=count;render(plugin,output.data()+8,&frameCount);require(frameCount==count,"Render length changed");++renderCalls;
          for(int i=0;i<8;++i)require(output[size_t(i)]==1234.5f && output[size_t(count)*2+8+size_t(i)]==1234.5f,"Render guard changed");
          for(int i=0;i<count*2;++i)require(std::isfinite(output[size_t(i)+8]),"Native output nonfinite");
          std::vector<std::pair<intptr_t,int32_t>> expected;
          for(auto& voice:voices) {advance(&voice.state,count);if(finished(&voice.state,releaseLength))expected.emplace_back(voice.tag,-1);}
          require(notifications==expected,"Host completion notification order/flags differ");notices+=expected.size();compare();
          // Controlled host shim defers removal until the complete render returns.
          if(round%4!=1)for(const auto& notice:expected) {
            auto it=std::find_if(voices.begin(),voices.end(),[&](const auto& voice){return voice.tag==notice.first;});require(it!=voices.end(),"Unknown notification tag");kill(plugin,it->native);voices.erase(it);++deletions;compare();
          }
        }
        if(round%5==0 && !voices.empty()) {const size_t index=size_t(random()%voices.size());kill(plugin,voices[index].native);voices.erase(voices.begin()+static_cast<ptrdiff_t>(index));++deletions;compare();}
      }
      for(const auto& voice:voices) {kill(plugin,voice.native);++deletions;}
      require(nativeCount(load<void*>(plugin,0x200))==0,"Explicit final cleanup failed");method<void(*)(void*)>(plugin,0xc8)(plugin);
    }
    dlclose(rebuilt);dlclose(native);
    std::cout<<"{\"status\":\"passed\",\"compiled_dylib_replayed\":true,\"actual_native_factory_fixtures\":"<<fixtureCount<<",\"voice_triggers\":"<<triggers
      <<",\"polyphony_quick_release_cases\":"<<quickReleases<<",\"normal_or_repeated_release_cases\":"<<normalReleases<<",\"actual_GenRender_calls\":"<<renderCalls
      <<",\"host_completion_notifications\":"<<notices<<",\"metadata_values_exact\":"<<stateValues<<",\"explicit_native_deletions\":"<<deletions<<",\"direct_release_metadata_cases\":"<<directCases
      <<",\"rebuilt_native_factory\":false,\"envelope_state_rebuilt_by_this_module\":false,\"audio_rebuilt_by_this_module\":false,\"actual_host_scheduling_rebuilt\":false,\"full_plugin_recompiled\":false}\n";
    return 0;
  }catch(const std::exception& error) {std::cerr<<error.what()<<'\n';return 1;}
 }
}

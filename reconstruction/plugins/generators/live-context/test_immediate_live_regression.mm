#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error "Native offsets require the reviewed macOS arm64 slice"
#endif
#include "three_osc_native_factory.h"
#include "three_osc_legacy_tables.hpp"
#include "three_osc_declick.hpp"
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
template<class T>void store(void*p,size_t offset,T value){std::memcpy(static_cast<char*>(p)+offset,&value,sizeof value);}
struct SavedSpans {char*base;std::vector<std::pair<size_t,size_t>>spans;std::vector<std::vector<uint8_t>>bytes;SavedSpans(char*b,std::initializer_list<std::pair<size_t,size_t>>s):base(b),spans(s){for(auto[o,n]:spans){bytes.emplace_back(n);std::memcpy(bytes.back().data(),base+o,n);}}bool restore(){for(size_t i=0;i<spans.size();++i)std::memcpy(base+spans[i].first,bytes[i].data(),bytes[i].size());for(size_t i=0;i<spans.size();++i)if(std::memcmp(base+spans[i].first,bytes[i].data(),bytes[i].size()))return false;return true;}~SavedSpans(){restore();}};
struct VoiceSnapshot {std::array<uint32_t,45>mod{};std::array<uint8_t,112>filter{};std::array<float,2>gain{};std::array<int32_t,3>released{};std::array<uint32_t,6>phase{};uint8_t stereo=0;std::array<uint8_t,40>parameters{};};
bool equal(const VoiceSnapshot&a,const VoiceSnapshot&b){return a.mod==b.mod&&a.filter==b.filter&&std::memcmp(a.gain.data(),b.gain.data(),8)==0&&a.released==b.released&&a.phase==b.phase&&a.stereo==b.stereo&&a.parameters==b.parameters;}
size_t differenceWords(const VoiceSnapshot&a,const VoiceSnapshot&b){size_t n=0;for(size_t i=0;i<45;++i)n+=a.mod[i]!=b.mod[i];for(size_t i=0;i<28;++i)n+=load<uint32_t>(a.filter.data(),i*4)!=load<uint32_t>(b.filter.data(),i*4);for(size_t i=0;i<2;++i)n+=std::bit_cast<uint32_t>(a.gain[i])!=std::bit_cast<uint32_t>(b.gain[i]);for(size_t i=0;i<3;++i)n+=a.released[i]!=b.released[i];for(size_t i=0;i<6;++i)n+=a.phase[i]!=b.phase[i];n+=a.stereo!=b.stereo;for(size_t i=0;i<10;++i)n+=load<uint32_t>(a.parameters.data(),i*4)!=load<uint32_t>(b.parameters.data(),i*4);return n;}
std::vector<uint32_t>coefficients(const void*cfg){std::vector<uint32_t>out;for(int group=0;group<5;++group)for(size_t off=0;off<160;off+=4)if(off!=0x68&&off!=0x6c&&off!=0x78)out.push_back(load<uint32_t>(cfg,8+group*160+off));return out;}
}
int main(int argc,char**argv){@autoreleasepool{try{
 require(argc==4,"Usage: live-variant <original wrapper> <private variant library> <private data directory/>");require(std::fegetround()==FE_TONEAREST,"Nearest-even required");uint64_t fpcr;asm volatile("mrs %0, fpcr":"=r"(fpcr));require((fpcr&(1ull<<24))==0,"Gradual underflow required");
 require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity changed");require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Vector identity changed");require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib")=="d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Small engine identity changed");const char*enginePath="/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib";require(hashFile(enginePath)=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Host engine identity changed");
 [NSApplication sharedApplication];dataPath=argv[3];hostMethods.fill(reinterpret_cast<void*>(&noop));pathMethods.fill(reinterpret_cast<void*>(&noop));hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);hostMethods[0xf0/8]=reinterpret_cast<void*>(&nativeNotify);alignas(16)std::array<std::byte,512>host{};store<void*>(host.data(),0,hostMethods.data());std::vector<float>tables(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(tables.data(),tables.size()));for(int i=0;i<6;++i)store<const float*>(host.data(),0x18+i*8,tables.data()+i*16384);
 void*native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Original load failed");void*rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Reviewed source load failed");void*engine=dlopen(enginePath,RTLD_NOW|RTLD_LOCAL);require(engine,"Host engine load failed");auto create=symbol<void*(*)(void*,intptr_t)>(native,"CreatePlugInstance");auto factory=symbol<vl_private_osc::Plugin*(*)(void*,intptr_t)>(rebuilt,"CreatePlugInstance");auto getChannel=symbol<vl_osc_multimode_channel*(*)(vl_private_osc::Plugin*)>(rebuilt,"vl_private_osc_channel");auto snapshot=symbol<int(*)(const vl_osc_multimode_channel*,const vl_osc_multimode_channel_voice*,uint32_t*,uint8_t*,float*,int32_t*,uint32_t*,uint8_t*)>(rebuilt,"vl_osc_multimode_channel_snapshot");
 Dl_info ni{},ei{};require(dladdr(reinterpret_cast<void*>(create),&ni)&&dladdr(dlsym(engine,"CreateFruityInstance"),&ei),"Image base unavailable");auto*wrapperBase=static_cast<char*>(ni.dli_fbase);auto*engineBase=static_cast<char*>(ei.dli_fbase);using Ctor=void*(*)(void*,intptr_t,void*);auto hostCtor=reinterpret_cast<Ctor>(engineBase+0xb4cd20),pluginCtor=reinterpret_cast<Ctor>(engineBase+0xb4c7c0);
 size_t fixtures=0,renders=0,exactPrerenders=0,exactVoiceComparisons=0,exactAudioFloats=0,audioMismatches=0,stateMismatches=0,immediateNativeMutations=0,immediateSourceMutations=0,sourceChannelReplacements=0;std::array<size_t,6>changedAudio{},changedState{},changedCoefficients{};std::vector<std::string>observations;
 {
 SavedSpans globals(wrapperBase,{{0x25892c,24},{0x263008,16}});std::array<void*,5>streamMethods{};streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);
 for(int fixture=0;fixture<96;++fixture){const int action=fixture%6,mode=(fixture/6)%8;const bool musical=(fixture/48)!=0;void*plugin=create(host.data(),42);require(plugin,"Original factory failed");const void*rateHelper=load<void*>(plugin,0xc8);const auto rateMethodOffset=reinterpret_cast<uintptr_t>(load<void*>(load<void*>(rateHelper,0),0xc8))-reinterpret_cast<uintptr_t>(wrapperBase);std::vector<std::pair<intptr_t,int32_t>>modelNotices;std::array<void*,96>modelMethods{};modelMethods[0xc8/8]=reinterpret_cast<void*>(&modelHostDispatch);modelMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);modelMethods[0xf0/8]=reinterpret_cast<void*>(&modelHostNotify);ModelHost modelHost{modelMethods.data(),&modelNotices};void*hostAdapter=hostCtor(engineBase+0x1497870,1,&modelHost);require(hostAdapter,"Host adapter failed");auto*cpp=factory(static_cast<char*>(hostAdapter)+16,42);require(cpp,"Source factory failed");void*model=pluginCtor(engineBase+0x1497618,1,cpp);require(model,"Plugin adapter failed");
  auto nativeState=method<void(*)(void*,void*,int32_t)>(plugin,0xe0),sourceState=method<void(*)(void*,void*,int32_t)>(model,0xe0);Stream initial{streamMethods.data(),{},0};nativeState(plugin,&initial,1);require(initial.bytes.size()==460,"State framing changed");initial.bytes[92]=uint8_t(fixture/48);nativeState(plugin,&initial,0);initial.cursor=0;sourceState(model,&initial,0);
  const auto dispatch=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(plugin,0xd0),sourceDispatch=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(model,0xd0);const auto event=method<int32_t(*)(void*,int32_t,int32_t,int32_t)>(plugin,0xf0),sourceEvent=method<int32_t(*)(void*,int32_t,int32_t,int32_t)>(model,0xf0);
  for(void*target:{plugin,model}){const auto d=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(target,0xd0);const auto e=method<int32_t(*)(void*,int32_t,int32_t,int32_t)>(target,0xf0);d(target,4,0,44100);std::array<int32_t,3>sig{16,4,240};d(target,14,0,reinterpret_cast<intptr_t>(sig.data()));e(target,0,std::bit_cast<int32_t>(120.0f),0);}
  const auto set=[&](int32_t id,int32_t value){method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(plugin,0xf8)(plugin,id,value,1);method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(model,0xf8)(model,id,value,1);};std::array<int,21>core{};core[1]=0;core[8]=1;core[15]=2;core[6]=80;core[13]=70;for(int i=0;i<21;++i)set(i,core[i]);
  for(int group=0;group<5;++group){const std::array<int32_t,17>controls{musical?3:0,1,100,4000,100,9000,64,12000,group==4?0:group==1?128:8,100,100,group==4?0:4,16000,group%3,16,-32,48};for(int f=0;f<17;++f)set(23+17*group+f,controls[f]);}set(110,128);set(111,32);set(113,mode);
  Parameters params{};params.initial.pitch=0;params.final=params.initial;vl_osc_multimode_channel_parameters sourceParams{};std::memcpy(&sourceParams,&params,40);auto voice=method<uintptr_t(*)(void*,void*,intptr_t)>(plugin,0x110)(plugin,&params,fixture+100);auto handle=method<intptr_t(*)(void*,void*,intptr_t)>(model,0x110)(model,&sourceParams,fixture+100);require(voice&&handle&&handle!=-1,"Initial trigger failed");auto*channel=getChannel(cpp);require(channel,"Initial source channel missing");
  const auto nativeSnapshot=[&](){VoiceSnapshot s;const void*editor=load<void*>(reinterpret_cast<void*>(voice),48);std::memcpy(s.mod.data(),static_cast<const char*>(editor)+0x50,180);std::memcpy(s.filter.data(),static_cast<const char*>(editor)+0x108,112);std::memcpy(s.gain.data(),static_cast<const char*>(editor)+0x40,8);s.released={load<int32_t>(editor,0xc),load<int32_t>(editor,0x10),load<uint8_t>(editor,0x178)};std::memcpy(s.phase.data(),reinterpret_cast<const char*>(voice)+16,24);s.stereo=load<uint8_t>(reinterpret_cast<void*>(voice),40);std::memcpy(s.parameters.data(),&params,40);return s;};
  const auto modelSnapshot=[&](){VoiceSnapshot s;require(snapshot(channel,reinterpret_cast<vl_osc_multimode_channel_voice*>(handle),s.mod.data(),s.filter.data(),s.gain.data(),s.released.data(),s.phase.data(),&s.stereo),"Source snapshot failed");std::memcpy(s.parameters.data(),&sourceParams,40);return s;};require(equal(nativeSnapshot(),modelSnapshot()),"Initial state differs before live context test");++exactVoiceComparisons;
  const auto render=[&](int count){method<void(*)(void*)>(plugin,0x138)(plugin);method<void(*)(void*)>(model,0x138)(model);std::vector<float>a(size_t(count)*2+16,1234.5f);for(int j=0;j<count*2;++j)a[size_t(j)+8]=.25f;auto b=a;nativeNotices.clear();modelNotices.clear();int n=count;int32_t m=count;method<void(*)(void*,float*,int*)>(plugin,0x108)(plugin,a.data()+8,&n);method<void(*)(void*,float*,int32_t&)>(model,0x108)(model,b.data()+8,m);require(n==count&&m==count,"Render length changed");for(int j=0;j<8;++j)require(a[size_t(j)]==1234.5f&&b[size_t(j)]==1234.5f&&a[size_t(count)*2+8+size_t(j)]==1234.5f&&b[size_t(count)*2+8+size_t(j)]==1234.5f,"Render guard changed");size_t differences=0;for(int j=0;j<count*2;++j){require(std::isfinite(a[size_t(j)+8])&&std::isfinite(b[size_t(j)+8]),"Render nonfinite");differences+=std::bit_cast<uint32_t>(a[size_t(j)+8])!=std::bit_cast<uint32_t>(b[size_t(j)+8]);}const bool stateEqual=equal(nativeSnapshot(),modelSnapshot());if(differences||!stateEqual)std::cerr<<"Live fixture "<<fixture<<" action "<<action<<" differs\n";require(differences==0&&stateEqual,"Live context render/state differs");require(nativeNotices==modelNotices,"Live context notification sequence differs");++exactVoiceComparisons;exactAudioFloats+=size_t(count)*2;++renders;return differences;};
  render(63);++exactPrerenders;auto beforeNative=nativeSnapshot(),beforeSource=modelSnapshot();auto*cfg=load<void*>(plugin,0x240);const auto coeffBefore=coefficients(cfg);const float scaleBefore=load<float>(plugin,0xe0);std::array<int32_t,3>sig{16,4,960};
  if(action==0){dispatch(plugin,4,0,44100);sourceDispatch(model,4,0,44100);sig[2]=240;dispatch(plugin,14,0,reinterpret_cast<intptr_t>(sig.data()));sourceDispatch(model,14,0,reinterpret_cast<intptr_t>(sig.data()));event(plugin,0,std::bit_cast<int32_t>(120.0f),0);sourceEvent(model,0,std::bit_cast<int32_t>(120.0f),0);}
  if(action==1||action==5){const int rate=action==1?96000:22050;dispatch(plugin,4,0,rate);sourceDispatch(model,4,0,rate);}
  if(action==3||action==4||action==5){if(action==5)sig[2]=48;dispatch(plugin,14,0,reinterpret_cast<intptr_t>(sig.data()));sourceDispatch(model,14,0,reinterpret_cast<intptr_t>(sig.data()));}
  if(action==2||action==4||action==5){const float tempo=action==2?60.0f:action==4?120.0f:137.125f;event(plugin,0,std::bit_cast<int32_t>(tempo),12345);sourceEvent(model,0,std::bit_cast<int32_t>(tempo),12345);}
  auto afterNative=nativeSnapshot(),afterSource=modelSnapshot();const auto coeffAfter=coefficients(cfg);size_t coeffChanges=0;for(size_t i=0;i<coeffBefore.size();++i)coeffChanges+=coeffBefore[i]!=coeffAfter[i];changedCoefficients[action]+=coeffChanges;
  require(equal(beforeNative,afterNative),"Original live delivery mutated immediate voice state");immediateNativeMutations+=differenceWords(beforeNative,afterNative);immediateSourceMutations+=differenceWords(beforeSource,afterSource);sourceChannelReplacements+=getChannel(cpp)!=channel;require(equal(beforeSource,afterSource)&&getChannel(cpp)==channel,"Live context delivery changed immediate voice state/channel");
  // Record the measured context transitions independently while requiring
  // this new source runtime to match native post-transition state and audio.
  const auto beforeFirst=nativeSnapshot();const size_t firstAudio=render(7);const auto afterFirst=nativeSnapshot();const auto sourceFirst=modelSnapshot();size_t firstState=differenceWords(afterFirst,sourceFirst);size_t blocksDifferent=firstAudio!=0;size_t framesDifferent=firstAudio;
  for(int block=0;block<4;++block){const auto differences=render(std::array<int,4>{8,16,63,441}[block]);blocksDifferent+=differences!=0;framesDifferent+=differences;}
  if(framesDifferent){++audioMismatches;++changedAudio[action];}if(firstState){++stateMismatches;++changedState[action];}
  const uint32_t step=uint32_t(uint64_t(std::nearbyint(double(load<float>(plugin,0xe0)))));for(int oscillator=0;oscillator<3;++oscillator)require(afterFirst.phase[2*oscillator]==beforeFirst.phase[2*oscillator]+step*7,"Native raw phase increment did not follow current rate scaler");const uint32_t sourceStep=step;for(int oscillator=0;oscillator<3;++oscillator)require(sourceFirst.phase[2*oscillator]==beforeSource.phase[2*oscillator]+sourceStep*7,"Live variant rate scaler differs");
  for(int group=0;group<5;++group)require(afterFirst.mod[size_t(group)*9+1]==beforeFirst.mod[size_t(group)*9+1]+load<uint32_t>(cfg,8+group*160+0x64),"Native LFO increment did not follow current prepared config");
  require(framesDifferent==0&&firstState==0,"Live context variant rendering/state differs");
  std::ostringstream o;o<<"{\"fixture\":"<<fixture<<",\"action\":"<<action<<",\"filter_mode\":"<<mode<<",\"musical_time_flags\":"<<(musical?3:0)<<",\"HQ\":"<<(fixture/48)<<",\"changed_prepared_coefficient_words\":"<<coeffChanges<<",\"immediate_native_voice_word_changes\":"<<differenceWords(beforeNative,afterNative)<<",\"immediate_source_voice_word_changes\":"<<differenceWords(beforeSource,afterSource)<<",\"native_scaler_before_bits\":"<<std::bit_cast<uint32_t>(scaleBefore)<<",\"native_scaler_after_bits\":"<<std::bit_cast<uint32_t>(load<float>(plugin,0xe0))<<",\"delivered_original_rate\":"<<load<int32_t>(wrapperBase,0x25892c)<<",\"delivered_original_tempo\":"<<load<double>(wrapperBase,0x263008)<<",\"delivered_original_PPQ\":"<<load<uint32_t>(wrapperBase,0x263010)<<",\"native_rate_helper_method_offset\":"<<rateMethodOffset<<",\"native_rate_helper_rate\":"<<load<int32_t>(rateHelper,8)<<",\"native_raw_phase_step\":"<<step<<",\"source_current_raw_phase_step\":"<<sourceStep<<",\"first_render_differing_state_values\":"<<firstState<<",\"differing_audio_float_values\":"<<framesDifferent<<",\"differing_render_blocks\":"<<blocksDifferent<<"}";observations.push_back(o.str());
  method<void(*)(void*,uintptr_t)>(plugin,0x120)(plugin,voice);method<void(*)(void*,intptr_t)>(model,0x120)(model,handle);method<void(*)(void*)>(plugin,0xc8)(plugin);method<void(*)(void*)>(model,0xc8)(model);method<void(*)(void*,intptr_t)>(model,0x60)(model,1);method<void(*)(void*,intptr_t)>(hostAdapter,0x60)(hostAdapter,1);++fixtures;
 }
 require(globals.restore(),"Selected wrapper global snapshots not restored");
 }
 dlclose(rebuilt);dlclose(native);dlclose(engine);std::cout<<"{\"status\":\"passed_live_context_variant\",\"fixtures\":"<<fixtures<<",\"exact_initial_prerenders\":"<<exactPrerenders<<",\"exact_voice_state_comparisons\":"<<exactVoiceComparisons<<",\"exact_voice_state_values\":"<<exactVoiceComparisons*95<<",\"exact_overwritten_audio_floats\":"<<exactAudioFloats<<",\"render_calls\":"<<renders<<",\"fixtures_with_audio_difference\":"<<audioMismatches<<",\"fixtures_with_first_state_difference\":"<<stateMismatches<<",\"immediate_native_voice_word_mutations\":"<<immediateNativeMutations<<",\"immediate_source_voice_word_mutations\":"<<immediateSourceMutations<<",\"source_channel_replacements\":"<<sourceChannelReplacements<<",\"changed_audio_fixtures_by_action\":[";for(size_t i=0;i<6;++i)std::cout<<(i?",":"")<<changedAudio[i];std::cout<<"],\"changed_first_state_fixtures_by_action\":[";for(size_t i=0;i<6;++i)std::cout<<(i?",":"")<<changedState[i];std::cout<<"],\"changed_coefficient_words_by_action\":[";for(size_t i=0;i<6;++i)std::cout<<(i?",":"")<<changedCoefficients[i];std::cout<<"],\"observations\":[";for(size_t i=0;i<observations.size();++i)std::cout<<(i?",":"")<<observations[i];std::cout<<"],\"new_runtime_implementation\":true,\"selected_wrapper_globals_restored\":true,\"real_application_clock_production\":false,\"real_scheduler_or_RT\":false,\"full_plugin_equivalence\":false}\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#include "factory_helpers.mm"
#pragma clang diagnostic pop
#include "../../../../reconstruction/plugins/effects/balance_native_abi.h"
#include <limits>

namespace {
using NativePlugin=veggie_loops::balance::native::Plugin;
struct GuardedName {
 std::array<char,288> bytes{};
 GuardedName(){bytes.fill('Q');const char text[]="previous caller contents";std::memcpy(bytes.data()+16,text,sizeof(text));bytes[271]=0;}
 char* data(){return bytes.data()+16;}
 void check()const {for(size_t i=0;i<16;++i)require(bytes[i]=='Q'&&bytes[272+i]=='Q',"Name boundary sentinel changed");}
};
}
int main(int argc,char**argv){@autoreleasepool{try{
 require(argc==4,"Expected original plugin, private output directory, rebuilt source module");
 require(sourceHash(argv[1])=="525e96102a4eddc89de484ec3bc6a3c92788738c1dc50b5a5fa71bbd994e77ef","Original identity");
 privatePath=argv[2];[NSApplication sharedApplication];hostVmt.fill(reinterpret_cast<void*>(&noOperation));pathVmt.fill(reinterpret_cast<void*>(&noOperation));hostVmt[0xc8/8]=reinterpret_cast<void*>(&dispatch);
 alignas(16)std::array<std::byte,512> host{};void**table=hostVmt.data();std::memcpy(host.data(),&table,8);
 void*original=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(original,"Original load");void*source=dlopen(argv[3],RTLD_NOW|RTLD_LOCAL);require(source,"Source load");
 using OriginalCreate=void*(*)(void*,std::intptr_t);using SourceCreate=NativePlugin*(*)(void*,std::intptr_t);
 auto createOriginal=reinterpret_cast<OriginalCreate>(dlsym(original,"CreatePlugInstance"));auto createSource=reinterpret_cast<SourceCreate>(dlsym(source,"CreatePlugInstance"));require(createOriginal&&createSource,"Factories");
 const char* enginePath="/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib";
 require(sourceHash(enginePath)=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine identity");
 void* engine=dlopen(enginePath,RTLD_NOW|RTLD_LOCAL);require(engine,"Engine load");Dl_info engineImage{};
 require(dladdr(dlsym(engine,"CreateFruityInstance"),&engineImage)&&engineImage.dli_fbase,"Engine base");
 auto* engineBase=static_cast<char*>(engineImage.dli_fbase);
 using MaxPoly=std::int32_t(*)(NativePlugin*);auto maxPoly=reinterpret_cast<MaxPoly>(dlsym(source,"VLBalanceProtocolMaxPoly"));require(maxPoly,"Own probe getter");
 size_t maxPolyComparisons=0;
 size_t nameCalls=0,differentNameBuffers=0,nonzeroSectionNativeUnchanged=0,eventCalls=0,storedMaxPoly=0;std::array<size_t,10>sectionDifferences{};std::array<std::string,2>originalNames{},sourceNames{};
 for(int repetition=0;repetition<2;++repetition){
  void*object=createOriginal(host.data(),42);auto*rebuilt=createSource(nullptr,42);require(object&&rebuilt,"Instances");
  using Name=void(*)(void*,int32_t,int32_t,int32_t,char*);using Event=int32_t(*)(void*,int32_t,int32_t,int32_t);
  alignas(16)std::array<std::byte,184> bridge{};std::memcpy(bridge.data()+0xa8,&rebuilt,8);std::memcpy(bridge.data()+0xb0,&rebuilt,8);
  auto bridgeName=reinterpret_cast<Name>(engineBase+0xb4c9e0);auto bridgeEvent=reinterpret_cast<Event>(engineBase+0xb4cb60);
  require(load<int32_t>(object,0xdc)==0 && maxPoly(rebuilt)==0,"Fresh maximum-polyphony state");++maxPolyComparisons;
  auto getName=method<Name>(object,0xe8);auto event=method<Event>(object,0xf0);
  Dl_info image{};require(dladdr(reinterpret_cast<void*>(getName),&image)&&image.dli_fbase,"Name image");auto base=reinterpret_cast<uintptr_t>(image.dli_fbase);
  require(reinterpret_cast<uintptr_t>(getName)-base==0x5b330&&reinterpret_cast<uintptr_t>(event)-base==0x72370,"Pinned actual methods");
  for(int section=0;section<=9;++section)for(int index=0;index<2;++index)for(int value:{-1,0,1}){
   GuardedName a,b;const auto before=a.bytes;getName(object,section,index,value,a.data());if(repetition)bridgeName(bridge.data(),section,index,value,b.data());else rebuilt->functions->name(rebuilt,section,index,value,b.data());a.check();b.check();
   if(a.bytes!=b.bytes){++differentNameBuffers;++sectionDifferences[size_t(section)];}
   require(a.bytes==b.bytes,"Native/source name buffer differs");
   if(section!=0){require(a.bytes==before,"Original nonzero name section wrote output");++nonzeroSectionNativeUnchanged;}
   else if(value==0){originalNames[size_t(index)]=a.data();sourceNames[size_t(index)]=b.data();}
   ++nameCalls;
  }
  require(load<int32_t>(object,0xdc)==0 && maxPoly(rebuilt)==0,"Name calls changed maximum-polyphony state");++maxPolyComparisons;
  for(int id=0;id<3;++id)for(int value:{std::numeric_limits<int32_t>::min(),-1,0,1,17,std::numeric_limits<int32_t>::max()}){
   const auto before=load<int32_t>(object,0xdc);const auto a=event(object,id,value,0);const auto b=repetition?bridgeEvent(bridge.data(),id,value,0):rebuilt->functions->event(rebuilt,id,value,0);require(a==0&&b==0,"Event return");
   const auto after=load<int32_t>(object,0xdc);require(after==(id==1?value:before),"Native max-poly storage");require(maxPoly(rebuilt)==after,"Native/source maximum-polyphony state differs");++maxPolyComparisons;if(id==1)++storedMaxPoly;require(rebuilt->mono==0,"Source MonoRender unexpectedly changed");++eventCalls;
  }
  rebuilt->functions->destroy(rebuilt);method<void(*)(void*)>(object,0xc8)(object);
 }
 dlclose(engine);dlclose(source);dlclose(original);
 std::cout<<"{\"status\":\"matched_balance_public_name_and_event_protocol\",\"factory_pairs\":2,\"name_pairs\":"<<nameCalls<<",\"different_name_buffers\":"<<differentNameBuffers<<",\"nonzero_section_native_buffers_unchanged\":"<<nonzeroSectionNativeUnchanged<<",\"section_difference_counts\":[";
 for(size_t i=0;i<sectionDifferences.size();++i)std::cout<<(i?",":"")<<sectionDifferences[i];
 std::cout<<"],\"original_names\":[\""<<originalNames[0]<<"\",\""<<originalNames[1]<<"\"],\"source_names\":[\""<<sourceNames[0]<<"\",\""<<sourceNames[1]<<"\"],\"event_pairs\":"<<eventCalls<<",\"native_max_poly_writes\":"<<storedMaxPoly<<",\"maximum_polyphony_state_comparisons\":"<<maxPolyComparisons<<",\"intact_engine_bridge_name_calls\":60,\"intact_engine_bridge_event_calls\":18,\"name_guards_preserved\":true,\"original_callback_bytes_or_VFT_changed\":false,\"audio_compared\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

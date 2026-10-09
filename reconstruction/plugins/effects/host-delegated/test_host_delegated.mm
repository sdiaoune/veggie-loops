#define main frozen_provider_original_main
#include "../quality-provider/provider_original_probe.mm"
#undef main
#include "host_delegated_native.h"
#include "fast_dist_plugin.h"
namespace hd=veggie_loops::fast_dist::native;
struct ImmutablePath {
 std::vector<uint64_t> storage;
 explicit ImmutablePath(const char*path){NSString*s=[NSString stringWithUTF8String:path];require(s,"Bad path");size_t n=[s length];storage.resize((24+(n+1)*2+7)/8);storage[0]=0x204b0;storage[1]=~uint64_t{};storage[2]=n;[s getCharacters:reinterpret_cast<unichar*>(storage.data()+3) range:NSMakeRange(0,n)];}
 const char16_t*data()const{return reinterpret_cast<const char16_t*>(storage.data()+3);}
};
struct MemoryState {
 hd::Stream interface{};std::array<void*,5>functions{};std::array<uint8_t,20>bytes{};uint32_t calls=0;int32_t status=0;bool shortCount=false;
 MemoryState(){functions[3]=reinterpret_cast<void*>(&read);functions[4]=reinterpret_cast<void*>(&write);interface.functions=functions.data();}
 static int32_t read(hd::Stream*s,void*out,uint32_t n,uint32_t*done){auto&m=*reinterpret_cast<MemoryState*>(s);require(n==20,"State read length");std::memcpy(out,m.bytes.data(),20);if(done)*done=m.shortCount?19:20;++m.calls;return m.status;}
 static int32_t write(hd::Stream*s,void*in,uint32_t n,uint32_t*done){auto&m=*reinterpret_cast<MemoryState*>(s);require(n==20,"State write length");std::memcpy(m.bytes.data(),in,20);if(done)*done=20;++m.calls;return 0;}
};
static void*parentExpected=nullptr;static const float*inputExpected=nullptr;static int32_t countExpected=0;static std::array<int32_t,2>rawExpected{};static std::array<float,3>coefficientExpected{};static uint64_t hostCalls=0,hostViolations=0;
extern "C" void delegatedCapture(void*parent,int32_t type,int32_t threshold,float*buffer,int32_t count,float dry,float wet,float mul){
 if(parent!=parentExpected||type!=rawExpected[0]||threshold!=rawExpected[1]||count!=countExpected||std::bit_cast<uint32_t>(dry)!=std::bit_cast<uint32_t>(coefficientExpected[0])||std::bit_cast<uint32_t>(wet)!=std::bit_cast<uint32_t>(coefficientExpected[1])||std::bit_cast<uint32_t>(mul)!=std::bit_cast<uint32_t>(coefficientExpected[2]))++hostViolations;
 if(count>=0&&count<=countExpected)for(int32_t j=0;j<count;++j)if(std::bit_cast<uint32_t>(buffer[j])!=std::bit_cast<uint32_t>(inputExpected[j]))++hostViolations;
 ++hostCalls;distortion(parent,type,threshold,buffer,count,dry,wet,mul);
}
int main(int argc,char**argv){@autoreleasepool{try{
 require(argc==6,"Expected engine original physical-library logical-library private-directory");
 require(hash(argv[1])=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine identity");
 require(hash(argv[2])=="22b0fc6fa9f3cc065587f5e142ec047d8877432454ca7c25aba9e4eb195c5b82","Original identity");
 require(hash("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","IPP identity");
 [NSApplication sharedApplication];checkFloatingDomain();void*engine=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(engine,"Engine load");Dl_info ei{};require(dladdr(dlsym(engine,"CreateFruityInstance"),&ei)&&ei.dli_fbase,"Engine base");auto*b=static_cast<char*>(ei.dli_fbase);
 require(read<void*>(b,0x109e180+0x188)==b+0x3d5ff0,"Pascal DistWave identity");distortion=reinterpret_cast<Distortion>(b+0x3d5ff0);reinterpret_cast<void(*)()>(b+0x3e5980)();
 void*originalModule=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);void*sourceModule=dlopen(argv[3],RTLD_NOW|RTLD_LOCAL);require(originalModule&&sourceModule,"Plugin modules load");
 auto createOriginal=reinterpret_cast<void*(*)(void*,intptr_t)>(dlsym(originalModule,"CreatePlugInstance"));auto createSource=reinterpret_cast<hd::Plugin*(*)(void*,intptr_t)>(dlsym(sourceModule,"CreatePlugInstance"));auto getHost=reinterpret_cast<void*(*)(hd::Plugin*)>(dlsym(sourceModule,"vl_private_fast_dist_host_pointer"));auto getCoefficients=reinterpret_cast<int(*)(hd::Plugin*,float*)>(dlsym(sourceModule,"vl_private_fast_dist_host_coefficients"));auto renderPrivate=reinterpret_cast<int(*)(hd::Plugin*,const float*,float*,int32_t)>(dlsym(sourceModule,"vl_private_fast_dist_host_render"));require(createOriginal&&createSource&&getHost&&getCoefficients&&renderPrivate,"Factory/inspection symbols");
 auto*direct=vl_fast_dist_create(0);require(direct,"Own numerical source");uint64_t cppHostCalls=0,callbackSlots=0;uint64_t parameters=0,renders=0,frames=0,saves=0,restores=0,failedReads=0,rejections=0,differentQuality=0;void*loaderLibrary=nullptr;
 {
 Restore parentGlobal(b+0x18d9758,8),selectorGlobal(b+0x19b4a28,1);
 factoryHostVmt.fill(reinterpret_cast<void*>(&factoryNoop));factoryPathVmt.fill(reinterpret_cast<void*>(&factoryNoop));factoryHostVmt[0xc8/8]=reinterpret_cast<void*>(&factoryHostDispatch);factoryHostVmt[0x188/8]=reinterpret_cast<void*>(&delegatedCapture);factoryPath=argv[5];alignas(16)std::array<uint8_t,512>host{};write(host.data(),0,factoryHostVmt.data());auto hostBefore=host;parentExpected=host.data();
 auto hostCtor=reinterpret_cast<void*(*)(void*,intptr_t,void*)>(b+0xb4cd20),pluginCtor=reinterpret_cast<void*(*)(void*,intptr_t,void*)>(b+0xb4c7c0);
 void*hostFacade=hostCtor(b+0x1497870,1,host.data());require(hostFacade&&read<void*>(hostFacade,8)==host.data(),"Real manual host facade");void*cppHost=static_cast<char*>(hostFacade)+16;require(vmethod<void*>(cppHost,24*8)==b+0xb4e8c0,"Real host ordinal24");auto*cpp=createSource(cppHost,42);require(cpp&&getHost(cpp)==cppHost,"Borrowed host identity");void*source=pluginCtor(b+0x1497618,1,cpp);require(source,"Real plugin adapter");
 write(b,0x18d9758,host.data());ImmutablePath logical(argv[4]);void*loaded=reinterpret_cast<void*(*)(const char16_t*,void**,intptr_t)>(b+0x3e1450)(logical.data(),&loaderLibrary,43);require(loaded&&loaderLibrary,"Intact DLL loader");require(read<void*>(loaded,0)==b+0x1497618,"Loaded wrapper class");auto*loadedCpp=read<hd::Plugin*>(loaded,0xa8);require(loadedCpp,"Loaded CPP object");void*loadedHost=getHost(loadedCpp);void*loadedFacade=static_cast<char*>(loadedHost)-16;require(read<void*>(loadedFacade,0)==b+0x1497870&&read<void*>(loadedFacade,8)==host.data()&&vmethod<void*>(loadedHost,24*8)==b+0xb4e8c0,"Intact loader supplied measured host facade");
 void*original=createOriginal(host.data(),42);require(original,"Original factory");Dl_info oi{};require(dladdr(reinterpret_cast<void*>(createOriginal),&oi)&&read<void*>(original,0)==static_cast<char*>(oi.dli_fbase)+0x1bd490,"Original class identity");
 std::array<void*,3>targets{original,source,loaded};constexpr std::array<int32_t,5>minimum{64,1,0,0,0},maximum{192,10,1,128,128};constexpr std::array<int32_t,12>lengths{0,1,2,3,7,8,9,16,17,63,257,1024};std::mt19937 rng(0x6864656c);
 for(void*t:targets)for(int j=0;j<5;++j)require(vmethod<int32_t(*)(void*,int32_t,int32_t,int32_t)>(t,0xf8)(t,j,0,2)==std::array<int32_t,5>{128,10,0,128,128}[size_t(j)],"Defaults");
 std::array<float,3>defaultCoefficients{};require(getCoefficients(cpp,defaultCoefficients.data())&&defaultCoefficients==std::array<float,3>{0,1,1}&&!std::memcmp(static_cast<char*>(original)+0x13c,defaultCoefficients.data(),12),"Default coefficients differ");
 for(int caseIndex=0;caseIndex<1200;++caseIndex){
  for(int j=0;j<5;++j){const bool normalized=caseIndex%3==0;int32_t value=normalized?int32_t(rng()%0x40000001u):minimum[size_t(j)]+int32_t(rng()%uint32_t(maximum[size_t(j)]-minimum[size_t(j)]+1));int32_t result=0;const int32_t flags=normalized?49:17;require(vl_fast_dist_parameter(direct,j,value,uint32_t(flags)&35u,&result),"Own control rejected");for(void*t:targets)require(vmethod<int32_t(*)(void*,int32_t,int32_t,int32_t)>(t,0xf8)(t,j,value,flags)==result,"Control differs");parameters+=3;}
  std::array<float,3>coefficients{};require(vl_fast_dist_get_coefficients(direct,coefficients.data()),"Own coefficients");for(auto*p:{cpp,loadedCpp}){std::array<float,3>v{};require(getCoefficients(p,v.data())&&!std::memcmp(v.data(),coefficients.data(),12),"Source coefficients differ");}require(!std::memcmp(static_cast<char*>(original)+0x13c,coefficients.data(),12),"Original coefficients differ");
  MemoryState originalState;vmethod<void(*)(void*,hd::Stream*,int32_t)>(original,0xe0)(original,&originalState.interface,1);std::array<uint8_t,20>ownState{};require(vl_fast_dist_save_state(direct,ownState.data(),20)&&originalState.bytes==ownState&&originalState.calls==1,"Original state framing");
  for(void*t:{source,loaded}){MemoryState s;vmethod<void(*)(void*,hd::Stream*,int32_t)>(t,0xe0)(t,&s.interface,1);require(s.bytes==ownState&&s.calls==1,"Delegated source state save");++saves;}
  if(caseIndex%5==0){for(void*t:targets){vmethod<int32_t(*)(void*,int32_t,int32_t,int32_t)>(t,0xf8)(t,0,64,1);MemoryState s;s.bytes=ownState;vmethod<void(*)(void*,hd::Stream*,int32_t)>(t,0xe0)(t,&s.interface,0);require(s.calls==1,"State restore framing");++restores;}for(auto*p:{cpp,loadedCpp}){std::array<float,3>v{};require(getCoefficients(p,v.data())&&!std::memcmp(v.data(),coefficients.data(),12),"Restore coefficients differ");}}
  for(void*t:targets){auto dispatch=vmethod<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(t,0xd0);dispatch(t,1,0,std::array<int32_t,7>{0,1,3,17,19,INT32_MIN,INT32_MAX}[size_t(caseIndex)%7]);for(int j=0;j<5;++j)require(dispatch(t,52,j,0)==(j==2?9:5),"Classifications differ");}
  const int n=lengths[size_t(caseIndex)%lengths.size()];size_t start=size_t(caseIndex)%4;size_t size=size_t(n)*2+16;std::vector<float>input(size),expected(size,1234),opposite(size,1234);for(float&f:input)f=float(int32_t(rng()%1048577)-524288)*0x1p-15f;if(n){input[start]=-.0f;if(n>1)input[start+1]=.0f;}auto beforeInput=input;const bool alias=caseIndex%3==0;auto initial=alias?input:expected;
  for(uint8_t quality:{uint8_t(0),uint8_t(1)}){
   write(b,0x19b4a28,quality);vl_fast_dist_quality(direct,quality);expected=initial;require(vl_fast_dist_render(direct,alias?expected.data()+start:input.data()+start,expected.data()+start,n),"Own render");vl_fast_dist_quality(direct,quality^1);opposite=initial;require(vl_fast_dist_render(direct,alias?opposite.data()+start:input.data()+start,opposite.data()+start,n),"Opposite-quality render");
   for(size_t j=start;j<start+size_t(n)*2;++j)differentQuality+=std::bit_cast<uint32_t>(expected[j])!=std::bit_cast<uint32_t>(opposite[j]);
   coefficientExpected=coefficients;rawExpected={std::bit_cast<int32_t>(read<uint32_t>(ownState.data(),8)),std::bit_cast<int32_t>(read<uint32_t>(ownState.data(),4))};countExpected=n*2;inputExpected=input.data()+start;
   for(void*t:targets){auto actual=initial;const auto oldCalls=hostCalls;vmethod<void(*)(void*,const float*,float*,int32_t)>(t,0x100)(t,alias?actual.data()+start:input.data()+start,actual.data()+start,n);
    for(size_t j=start;j<start+size_t(n)*2;++j)require(std::bit_cast<uint32_t>(actual[j])==std::bit_cast<uint32_t>(expected[j]),"Delegated native sample differs");
    require(hostCalls==oldCalls+1&&hostViolations==0,"Host callback ordinal/receiver/arguments differ");for(size_t j=0;j<size;++j)if(j<start||j>=start+size_t(n)*2)require(std::bit_cast<uint32_t>(actual[j])==std::bit_cast<uint32_t>(initial[j]),"Output guard changed");require(!std::memcmp(input.data(),beforeInput.data(),size*4),"Input changed");++renders;if(t!=original)++cppHostCalls;frames+=uint64_t(n);
   }
   require(read<uint8_t>(b,0x19b4a28)==quality&&read<void*>(b,0x18d9758)==host.data()&&host==hostBefore,"Prepared host/global changed");checkFloatingDomain();
  }
 }

 // Exercise all20 reviewed native callback slots through both real adapters.
 for(void*t:{source,loaded}){
  vmethod<void(*)(void*)>(t,0xd8)(t);require(vmethod<int32_t(*)(void*,int32_t,int32_t,int32_t)>(t,0xf0)(t,0,0,0)==0,"Event callback");
  std::array<float,8>guard{1,2,3,4,5,6,7,8};const auto before=guard;int32_t n=4;
  vmethod<void(*)(void*,float*,int32_t&)>(t,0x108)(t,guard.data(),n);require(n==0&&guard==before,"Unused generator callback");
  require(vmethod<intptr_t(*)(void*,void*,intptr_t)>(t,0x110)(t,nullptr,0x1234)==-1,"Voice trigger callback");
  for(size_t off:{0x118u,0x120u,0x160u})vmethod<void(*)(void*,intptr_t)>(t,off)(t,0x1234);
  for(size_t off:{0x128u,0x158u})require(vmethod<int32_t(*)(void*,intptr_t,intptr_t,intptr_t,intptr_t)>(t,off)(t,0x1234,1,2,3)==0,"Unused voice/output event");
  n=4;require(vmethod<int32_t(*)(void*,intptr_t,float*,int32_t&)>(t,0x130)(t,0x1234,guard.data(),n)==0&&n==0&&guard==before,"Voice render callback");
  for(size_t off:{0x138u,0x140u})vmethod<void(*)(void*)>(t,off)(t);int32_t midi=0x1234;vmethod<void(*)(void*,int32_t&)>(t,0x148)(t,midi);require(midi==0x1234,"MIDI callback");vmethod<void(*)(void*,intptr_t)>(t,0x150)(t,0x1234);
  constexpr std::array<const char*,5>names{"Pre Gain","Threshold","Type","Mix","Post Gain"};for(int j=0;j<5;++j){std::array<char,12>text;text.fill(0x55);vmethod<void(*)(void*,int32_t,int32_t,int32_t,char*)>(t,0xe8)(t,0,j,0,text.data());require(std::strcmp(text.data(),names[size_t(j)])==0&&text[10]==0x55&&text[11]==0x55,"Name/canary callback");}
  callbackSlots+=20;
 }
 // Own rejection extensions: no malformed original call is made.
 std::array<float,16>audio{};std::array<float,16>before=audio;const auto callsBefore=hostCalls;std::array<float,3>coeffBefore{},coeffAfter{};require(getCoefficients(cpp,coeffBefore.data()),"Rejection coefficients");
 for(auto n:{-1,1025,INT32_MIN,INT32_MAX}){require(!renderPrivate(cpp,audio.data(),audio.data(),n),"Unsupported frames accepted");++rejections;}
 require(!renderPrivate(cpp,nullptr,audio.data(),1)&&!renderPrivate(cpp,audio.data(),nullptr,1),"Null active buffer accepted");rejections+=2;
 require(!renderPrivate(cpp,audio.data(),audio.data()+1,2)&&!renderPrivate(cpp,audio.data()+1,audio.data(),2),"Partial alias accepted");rejections+=2;
 for(float v:{17.f,-17.f,std::numeric_limits<float>::infinity(),-std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()}){audio[0]=v;auto saved=audio;require(!renderPrivate(cpp,audio.data(),audio.data(),8)&&!std::memcmp(audio.data(),saved.data(),sizeof(audio)),"Invalid audio not atomic");++rejections;}audio=before;
 require(!renderPrivate(cpp,reinterpret_cast<float*>(cpp),audio.data(),0)&&!renderPrivate(cpp,audio.data(),reinterpret_cast<float*>(cpp),0),"Zero-frame instance alias accepted");rejections+=2;
 std::array<uint8_t,208>instanceBefore{},instanceAfter{};std::memcpy(instanceBefore.data(),cpp,208);for(size_t off=0;off<208;++off){auto*inside=reinterpret_cast<float*>(reinterpret_cast<uintptr_t>(cpp)+off);require(!renderPrivate(cpp,inside,audio.data(),0)&&!renderPrivate(cpp,audio.data(),inside,0),"Live instance interior alias accepted");rejections+=2;}std::memcpy(instanceAfter.data(),cpp,208);require(instanceBefore==instanceAfter,"Interior rejection mutated instance bytes");
 require(getCoefficients(cpp,coeffAfter.data())&&!std::memcmp(coeffBefore.data(),coeffAfter.data(),12)&&hostCalls==callsBefore&&audio==before,"Rejected calls mutated/called host");
 for(void*t:{source,loaded}){MemoryState s;vmethod<void(*)(void*,hd::Stream*,int32_t)>(t,0xe0)(t,&s.interface,1);auto saved=s.bytes;for(bool shortCount:{false,true}){write(s.bytes.data(),0,uint32_t(read<uint32_t>(saved.data(),0)==64?192:64));s.shortCount=shortCount;s.status=shortCount?0:std::bit_cast<int32_t>(0x80004005u);vmethod<void(*)(void*,hd::Stream*,int32_t)>(t,0xe0)(t,&s.interface,0);MemoryState after;vmethod<void(*)(void*,hd::Stream*,int32_t)>(t,0xe0)(t,&after.interface,1);require(after.bytes==saved,"Failed HRESULT/count restore mutated state");++failedReads;}}
 require(differentQuality>0,"No quality discrimination");
 vmethod<void(*)(void*)>(original,0xc8)(original);for(void*t:{source,loaded}){vmethod<void(*)(void*)>(t,0xc8)(t);vmethod<void(*)(void*,intptr_t)>(t,0x60)(t,1);}for(void*t:{hostFacade,loadedFacade})vmethod<void(*)(void*,intptr_t)>(t,0x60)(t,1);
 parentGlobal.apply();selectorGlobal.apply();require(!std::memcmp(parentGlobal.p,parentGlobal.b.data(),8)&&!std::memcmp(selectorGlobal.p,selectorGlobal.b.data(),1),"Selected globals not restored/read back after destruction");
 }
 vl_fast_dist_destroy(direct);dlclose(loaderLibrary);dlclose(sourceModule);dlclose(originalModule);dlclose(engine);
 std::cout<<"{\"status\":\"passed_host_delegated_original_adapters_loader\",\"parameter_calls\":"<<parameters<<",\"render_callbacks\":"<<renders<<",\"stereo_frames\":"<<frames<<",\"host_ordinal24_calls\":"<<cppHostCalls<<",\"total_original_and_delegated_DistWave_calls\":"<<hostCalls<<",\"callback_slots_exercised_across_two_adapters\":"<<callbackSlots<<",\"source_state_saves\":"<<saves<<",\"all_target_state_restores\":"<<restores<<",\"atomic_failed_streams\":"<<failedReads<<",\"atomic_audio_rejections\":"<<rejections<<",\"opposite_quality_differences\":"<<differentQuality<<",\"actual_adapters_and_DLL_loader\":true,\"selected_globals_restored_after_instance_destruction\":true,\"provided_host_DSP_delegation\":true,\"independent_own_DSP_in_runtime\":false,\"application_host_or_selector_production\":false,\"full_plugin_equivalence\":false}\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

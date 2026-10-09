#define main accepted_prevoice_regression_main
#include "../../../../reconstruction/plugins/generators/live-context/test_immediate_prevoice_regression.mm"
#undef main
#include "prevoice_channel.hpp"

namespace {
std::vector<uint32_t> definedWords(const void* cfg) {
 std::vector<uint32_t> result;
 for(int group=0;group<5;++group)for(size_t offset=0;offset<160;offset+=4)
  if(offset!=0x68&&offset!=0x6c&&offset!=0x78)result.push_back(load<uint32_t>(cfg,8+group*160+offset));
 return result;
}
std::vector<uint32_t> sourceWords(const std::array<uint8_t,800>& cfg) {
 std::vector<uint32_t> result;
 for(int group=0;group<5;++group)for(size_t offset=0;offset<160;offset+=4)
  if(offset!=0x68&&offset!=0x6c&&offset!=0x78)result.push_back(load<uint32_t>(cfg.data(),group*160+offset));
 return result;
}
size_t changed(const std::vector<uint32_t>& a,const std::vector<uint32_t>& b) {
 require(a.size()==b.size(),"Word count differs");size_t n=0;for(size_t i=0;i<a.size();++i)n+=a[i]!=b[i];return n;
}
std::string wordDifferences(const std::vector<uint32_t>& a,const std::vector<uint32_t>& b) {
 std::ostringstream out;out<<'[';size_t index=0,found=0;
 for(int group=0;group<5;++group)for(size_t offset=0;offset<160;offset+=4)if(offset!=0x68&&offset!=0x6c&&offset!=0x78) {
  if(a[index]!=b[index])out<<(found++?",":"")<<"{\"group\":"<<group<<",\"offset\":"<<offset<<",\"native_bits\":"<<a[index]<<",\"source_bits\":"<<b[index]<<'}';++index;
 }
 out<<']';return out.str();
}
}
int main(int argc,char** argv){@autoreleasepool{try{
 require(argc==4,"Usage: observe_prevoice <native wrapper> <frozen source module> <own data directory/>");
 require(std::fegetround()==FE_TONEAREST,"Nearest-even required");uint64_t fpcr;asm volatile("mrs %0, fpcr":"=r"(fpcr));require((fpcr&((1ull<<24)|(0x1full<<8)))==0,"Gradual underflow and nontrapping exceptions required");
 require(hashFile(argv[1])=="c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c","Wrapper identity changed");
 require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib")=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","DSP identity changed");
 require(hashFile("/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib")=="d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f","Engine identity changed");
 const char*enginePath="/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib";require(hashFile(enginePath)=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Host identity changed");
 [NSApplication sharedApplication];dataPath=argv[3];hostMethods.fill(reinterpret_cast<void*>(&noop));pathMethods.fill(reinterpret_cast<void*>(&noop));hostMethods[0xc8/8]=reinterpret_cast<void*>(&hostDispatch);hostMethods[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);hostMethods[0xf0/8]=reinterpret_cast<void*>(&nativeNotify);
 alignas(16)std::array<std::byte,512> host{};store<void*>(host.data(),0,hostMethods.data());std::vector<float> tables(6*16384);veggie_loops::three_osc::legacy::generateTables(std::span<float,6*16384>(tables.data(),tables.size()));for(int i=0;i<6;++i)store<const float*>(host.data(),0x18+i*8,tables.data()+i*16384);
 void*native=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(native,"Original load failed");void*source=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(source,"Source load failed");void*engine=dlopen(enginePath,RTLD_NOW|RTLD_LOCAL);require(engine,"Host engine load failed");
 auto create=symbol<void*(*)(void*,intptr_t)>(native,"CreatePlugInstance");auto factory=symbol<vl_private_osc::Plugin*(*)(void*,intptr_t)>(source,"CreatePlugInstance");auto channel=symbol<vl_osc_multimode_channel*(*)(vl_private_osc::Plugin*)>(source,"vl_private_osc_channel");auto prepared=symbol<int(*)(vl_osc_multimode_channel*,void*)>(source,"vl_private_immediate_coefficients");auto cacheSnapshot=symbol<int(*)(vl_private_osc::Plugin*,void*,size_t)>(source,"vl_private_prevoice_cache_snapshot");auto ticks=symbol<int(*)(int32_t,double,int32_t*)>(source,"vl_private_prevoice_ticks");
 Dl_info ni{},ei{};require(dladdr(reinterpret_cast<void*>(create),&ni)&&dladdr(dlsym(engine,"CreateFruityInstance"),&ei),"Native bases unavailable");auto*w=static_cast<char*>(ni.dli_fbase);auto*e=static_cast<char*>(ei.dli_fbase);
 using Ctor=void*(*)(void*,intptr_t,void*);auto hc=reinterpret_cast<Ctor>(e+0xb4cd20),pc=reinterpret_cast<Ctor>(e+0xb4c7c0);auto ppqProducer=reinterpret_cast<void(*)(void*)>(e+0x32e000),tempoProducer=reinterpret_cast<void(*)(void*)>(e+0x32e1f0);
 size_t phaseCases=0;auto sourcePhase=symbol<int(*)(vl_private_osc::Plugin*,float,uint32_t*)>(source,"vl_private_prevoice_phase");auto nativePhase=reinterpret_cast<uint32_t(*)(void*,float)>(w+0x6a520);
 size_t calls=0,maskDifferences=0,restorations=0,semanticBytes=0,descriptorRoutes=0,firstTriggerDifferences=0;std::vector<std::string> observations,triggerObservations;
 {
 SavedSpans eg(e,{{0x167d358,8},{0x167daec,8},{0x167da78,4},{0x167dab8,8},{0x19b4a2a,1}}),wg(w,{{0x25892c,24},{0x263008,16}});
 std::array<void*,5> sm{};sm[3]=reinterpret_cast<void*>(&readStream);sm[4]=reinterpret_cast<void*>(&writeStream);std::array<void*,5> im{};im[1]=reinterpret_cast<void*>(&retain);im[2]=reinterpret_cast<void*>(&releaseInterface);im[4]=reinterpret_cast<void*>(&getPlugin);
 for(int fixture=0;fixture<16;++fixture){require(eg.restore()&&wg.restore(),"Initial controlled factory globals not restored");
  void*p=create(host.data(),42);require(p,"Original factory failed");std::vector<std::pair<intptr_t,int32_t>> notices;std::array<void*,96> mm{};mm[0xc8/8]=reinterpret_cast<void*>(&modelHostDispatch);mm[0x1c0/8]=reinterpret_cast<void*>(&nativeLR);mm[0xf0/8]=reinterpret_cast<void*>(&modelHostNotify);ModelHost mh{mm.data(),&notices};void*ha=hc(e+0x1497870,1,&mh);require(ha,"Host adapter failed");auto*cpp=factory(static_cast<char*>(ha)+16,42);require(cpp,"Source factory failed");void*m=pc(e+0x1497618,1,cpp);require(m,"Plugin adapter failed");
  const auto snap=[&](){veggie_loops::three_osc::prevoice::Snapshot out{};require(cacheSnapshot(cpp,&out,sizeof out),"Parent cache snapshot unavailable");return out;};
  const auto cacheWords=[&](){const auto x=snap();std::array<uint8_t,800> bytes;std::memcpy(bytes.data(),x.groups.data(),800);return sourceWords(bytes);};
  require(definedWords(load<void*>(p,0x240))==cacheWords(),"Fresh defined default cache differs");const auto freshSnap=snap();require(freshSnap.tempo==140&&freshSnap.ppq==96&&freshSnap.rate.rate==44100&&std::bit_cast<uint32_t>(freshSnap.rate.pluginPhaseScaler)==0&&!freshSnap.channelAvailable,"Fresh source context differs");
  auto ns=method<void(*)(void*,void*,int32_t)>(p,0xe0),ss=method<void(*)(void*,void*,int32_t)>(m,0xe0);auto np=method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(p,0xf8),sp=method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(m,0xf8);auto nd=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(p,0xd0),sd=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(m,0xd0);auto ne=method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(p,0xf0),se=method<int32_t(*)(void*,int32_t,int32_t,uint32_t)>(m,0xf0);
  nd(p,4,0,44100);sd(m,4,0,44100);std::array<int32_t,3> sig{16,4,240};nd(p,14,0,reinterpret_cast<intptr_t>(sig.data()));sd(m,14,0,reinterpret_cast<intptr_t>(sig.data()));ne(p,0,std::bit_cast<int32_t>(120.f),0);se(m,0,std::bit_cast<int32_t>(120.f),0);
  Stream initial{sm.data(),{},0};ns(p,&initial,1);require(initial.bytes.size()==460,"Initial framing changed");initial.bytes[92]=uint8_t(fixture%2);ns(p,&initial,0);initial.cursor=0;ss(m,&initial,0);
  for(int i=0;i<21;++i){const int v=i==0?12:0;np(p,i,v,1);sp(m,i,v,1);}
  for(int group=0;group<5;++group){const std::array<int32_t,17> raw{(fixture+group)%32,1,100,4000,100,9000,64,12000,group==2||group==3?8:16,100,100,4,16000,group%3,16,-32,48};for(int j=0;j<17;++j){np(p,23+group*17+j,raw[j],1);sp(m,23+group*17+j,raw[j],1);}}
  np(p,113,0,1);sp(m,113,0,1);require(!channel(cpp),"Source channel not lazy initially");
  const auto compareState=[&](){Stream a{sm.data(),{},0},b{sm.data(),{},0};ns(p,&a,1);ss(m,&b,1);require(a.bytes.size()==460&&b.bytes.size()==460,"State framing differs");for(size_t i=0;i<460;++i)if(i<93||i>=96){require(a.bytes[i]==b.bytes[i],"Semantic state differs");++semanticBytes;}};
  const auto action=[&](const char*name,auto nativeCall,auto sourceCall){const auto before=definedWords(load<void*>(p,0x240));std::fenv_t saved{},restored{};require(std::fegetenv(&saved)==0,"Fenv capture failed");require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Native clear failed");nativeCall();const int nmask=std::fetestexcept(FE_ALL_EXCEPT);require(std::feclearexcept(FE_ALL_EXCEPT)==0,"Source clear failed");sourceCall();const int smask=std::fetestexcept(FE_ALL_EXCEPT);require(std::fesetenv(&saved)==0&&std::fegetenv(&restored)==0&&!std::memcmp(&saved,&restored,sizeof saved),"Full caller fenv restore failed");++restorations;
   require(!channel(cpp),"No-voice action eagerly created source channel");std::array<uint8_t,800> guard;guard.fill(0xa5);const auto oldGuard=guard;require(prepared(nullptr,guard.data())==0&&guard==oldGuard,"Null source cache reader changed output");const auto after=definedWords(load<void*>(p,0x240));require(after==cacheWords(),"Immediate parent coefficients differ");require(nmask==smask,"Immediate no-voice FE masks differ");const auto x=snap();require(x.ppq==load<uint32_t>(w,0x263010)&&x.tempo==load<double>(w,0x263008)&&x.rate.rate==load<int32_t>(w,0x25892c),"Delivered parent context differs");const std::array<float,4>scalars{x.rate.ratio,x.rate.maximumGainStep,x.rate.declickStep,x.rate.declickFixed};for(size_t i=0;i<4;++i)require(std::bit_cast<uint32_t>(scalars[i])==load<uint32_t>(w,0x258930+i*4),"Delivered rate scalar differs");if(std::bit_cast<uint32_t>(x.rate.pluginPhaseScaler)!=load<uint32_t>(p,0xe0))std::cerr<<"Rate field action "<<name<<" fixture "<<fixture<<" sourcebits="<<std::bit_cast<uint32_t>(x.rate.pluginPhaseScaler)<<" nativebits="<<load<uint32_t>(p,0xe0)<<"\n";require(std::bit_cast<uint32_t>(x.rate.pluginPhaseScaler)==load<uint32_t>(p,0xe0),"Delivered plugin phase scaler differs");compareState();std::ostringstream o;o<<"{\"fixture\":"<<fixture<<",\"action\":\""<<name<<"\",\"native_mask\":"<<nmask<<",\"source_mask\":"<<smask<<",\"native_changed_defined_words\":"<<changed(before,after)<<",\"source_channel_available\":false,\"semantic_state_equal\":true}";observations.push_back(o.str());++calls;maskDifferences+=nmask!=smask;};
  action("same-tempo120",[&]{ne(p,0,std::bit_cast<int32_t>(120.f),0);},[&]{se(m,0,std::bit_cast<int32_t>(120.f),0);});
  action("changed-tempo60",[&]{ne(p,0,std::bit_cast<int32_t>(60.f),0);},[&]{se(m,0,std::bit_cast<int32_t>(60.f),0);});
  action("repeated-tempo60",[&]{ne(p,0,std::bit_cast<int32_t>(60.f),0);},[&]{se(m,0,std::bit_cast<int32_t>(60.f),0);});
  sig[2]=960;action("PPQ-only960",[&]{nd(p,14,0,reinterpret_cast<intptr_t>(sig.data()));},[&]{sd(m,14,0,reinterpret_cast<intptr_t>(sig.data()));});
  action("post-PPQ-tempo60",[&]{ne(p,0,std::bit_cast<int32_t>(60.f),0);},[&]{se(m,0,std::bit_cast<int32_t>(60.f),0);});
  action("rate96000",[&]{nd(p,4,0,96000);},[&]{sd(m,4,0,96000);});
  // This separate actual-entry replay checks the immutable core's real phase
  // consumer at delivered rates; it does not claim complete consumer FE parity.
  for(float pitch:{-2400.f,-123.5f,0.f,2400.f}){std::fenv_t saved{},restored{};require(std::fegetenv(&saved)==0,"Phase fenv capture failed");const uint32_t a=nativePhase(p,pitch);uint32_t b=0;require(sourcePhase(cpp,pitch,&b),"Source phase consumer rejected");require(std::fesetenv(&saved)==0&&std::fegetenv(&restored)==0&&!std::memcmp(&saved,&restored,sizeof saved),"Phase caller fenv restore failed");require(a==b,"Actual legacy phase consumer differs");++phaseCases;}
  const int group=fixture%5,control=23+group*17;
  action("raw-attack5000",[&]{np(p,control+3,5000,1);},[&]{sp(m,control+3,5000,1);});
  action("same-raw-attack5000",[&]{np(p,control+3,5000,1);},[&]{sp(m,control+3,5000,1);});
  const auto descriptor=[&](void* target){Holder h{};h.interface.vmt=im.data();h.interface.plugin=target;alignas(16)std::array<uint8_t,320>node{},expected{};for(size_t i=0;i<node.size();++i)node[i]=uint8_t(0xa5+i*13);store<void*>(node.data(),0,e+0x1076760);store<void*>(node.data(),0x18,&h);store<int32_t>(node.data(),0x44,2);store<int32_t>(node.data(),0x130,0);expected=node;std::array<int32_t,3>ds{16,4,240};std::memcpy(expected.data()+0x120,ds.data(),12);ppqProducer(node.data());tempoProducer(node.data());require(node==expected&&h.interface.getters==2&&h.interface.retains==2&&h.interface.releases==2&&h.interface.refs==0,"Descriptor guard/lifetime differs");++descriptorRoutes;};
  store<int32_t>(e,0x167d358,16);store<int32_t>(e,0x167d35c,4);store<int32_t>(e,0x167daec,240);store<float>(e,0x167da78,120.f);store<double>(e,0x167dab8,1.0);store<uint8_t>(e,0x19b4a2a,1);
  action("intact-descriptor-PPQ240-tempo120-clock1",[&]{descriptor(p);},[&]{descriptor(m);});
  Stream saved{sm.data(),{},0};ns(p,&saved,1);action("same-valid-restore",[&]{saved.cursor=0;ns(p,&saved,0);},[&]{saved.cursor=0;ss(m,&saved,0);});
  const int curve=control+14+(fixture%3);action("curve-to16",[&]{np(p,curve,16,1);},[&]{sp(m,curve,16,1);});
  action("curve16-to0",[&]{np(p,curve,0,1);},[&]{sp(m,curve,0,1);});
  const auto beforeTrigger=definedWords(load<void*>(p,0x240));Parameters params{};params.final=params.initial;vl_osc_multimode_channel_parameters sourceParams{};std::memcpy(&sourceParams,&params,40);auto voice=method<uintptr_t(*)(void*,void*,intptr_t)>(p,0x110)(p,&params,100+fixture);auto sourceVoice=method<intptr_t(*)(void*,void*,intptr_t)>(m,0x110)(m,&sourceParams,100+fixture);require(voice&&sourceVoice&&sourceVoice!=-1,"First trigger failed");require(channel(cpp),"Source channel not created by first trigger");require(!std::memcmp(&params,&sourceParams,40),"Borrowed note parameters differ");std::array<uint8_t,816> buffer;buffer.fill(0xa5);require(prepared(channel(cpp),buffer.data()+8)==1,"Source cache unavailable after trigger");for(size_t i=0;i<8;++i)require(buffer[i]==0xa5&&buffer[808+i]==0xa5,"Cache snapshot guard changed");std::array<uint8_t,800> sourceCfg;std::memcpy(sourceCfg.data(),buffer.data()+8,800);const auto nwords=definedWords(load<void*>(p,0x240)),swords=sourceWords(sourceCfg);compareState();const size_t differences=changed(nwords,swords);firstTriggerDifferences+=differences!=0;require(differences==0,"First-trigger cached history differs");require(cacheWords()==nwords,"Imported parent cache differs");
  std::ostringstream t;t<<"{\"fixture\":"<<fixture<<",\"curve_group\":"<<group<<",\"curve_field\":"<<14+fixture%3<<",\"native_words_changed_at_first_trigger\":"<<changed(beforeTrigger,nwords)<<",\"native_source_word_differences\":"<<differences<<",\"different_words\":"<<wordDifferences(nwords,swords)<<",\"borrowed_note_parameters_equal\":true}";triggerObservations.push_back(t.str());
  method<void(*)(void*,uintptr_t)>(p,0x120)(p,voice);method<void(*)(void*,intptr_t)>(m,0x120)(m,sourceVoice);method<void(*)(void*)>(p,0xc8)(p);method<void(*)(void*)>(m,0xc8)(m);method<void(*)(void*,intptr_t)>(m,0x60)(m,1);method<void(*)(void*,intptr_t)>(ha,0x60)(ha,1);
 }
 require(eg.restore()&&wg.restore(),"Selected native globals not restored/read back");
 }
 // A separately prepared native time helper boundary discriminates FRINTX/rint.
 alignas(16)std::array<double,8>frame{};frame[0]=46.710520033103712;auto nativeTicks=reinterpret_cast<int32_t(*)(void*,int32_t)>(w+0x1c1d90);std::fenv_t saved{},restored{};require(std::fegetenv(&saved)==0,"Tick fenv capture failed");std::feclearexcept(FE_ALL_EXCEPT);const int32_t nativeValue=nativeTicks(frame.data()+6,101);const int nativeMask=std::fetestexcept(FE_ALL_EXCEPT);std::feclearexcept(FE_ALL_EXCEPT);int32_t modelValue=-123;require(ticks(101,frame[0],&modelValue),"Prepared tick boundary rejected");const int modelMask=std::fetestexcept(FE_ALL_EXCEPT);require(std::fesetenv(&saved)==0&&std::fegetenv(&restored)==0&&!std::memcmp(&saved,&restored,sizeof saved),"Tick caller fenv restoration failed");require(nativeValue==modelValue&&nativeMask==modelMask,"Native FRINTX prepared boundary differs");
 dlclose(source);dlclose(native);dlclose(engine);std::cout<<"{\"status\":\"passed_bounded_no_voice_preparation_cache\",\"fixtures\":16,\"measured_callback_pairs\":"<<calls<<",\"mask_differences\":"<<maskDifferences<<",\"full_fenv_restorations\":"<<restorations<<",\"exact_semantic_state_bytes\":"<<semanticBytes<<",\"intact_descriptor_routes\":"<<descriptorRoutes<<",\"first_trigger_fixtures_with_cache_difference\":"<<firstTriggerDifferences<<",\"selected_globals_restored\":true,\"source_repair_performed\":true,\"direct_prepared_FRINTX_boundary_cases\":1,\"direct_actual_legacy_phase_consumer_cases\":"<<phaseCases<<",\"full_phase_consumer_fenv_equivalence\":false,\"audio_comparison_performed\":false,\"full_plugin_equivalence\":false,\"callback_observations\":[";for(size_t i=0;i<observations.size();++i)std::cout<<(i?",":"")<<observations[i];std::cout<<"],\"first_trigger_observations\":[";for(size_t i=0;i<triggerObservations.size();++i)std::cout<<(i?",":"")<<triggerObservations[i];std::cout<<"]}\n";return 0;
 }catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}}}

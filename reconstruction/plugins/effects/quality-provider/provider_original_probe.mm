#if !defined(__APPLE__) || !defined(__aarch64__)
#error This measured provider requires macOS arm64.
#endif
#import <Cocoa/Cocoa.h>
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <cstring>
#include <cstdint>
#include <dlfcn.h>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
static void require(bool b,const char*m){if(!b)throw std::runtime_error(m);}
template<class T>static T read(const void*p,size_t n){T v;std::memcpy(&v,static_cast<const char*>(p)+n,sizeof v);return v;}
template<class T>static void write(void*p,size_t n,T v){std::memcpy(static_cast<char*>(p)+n,&v,sizeof v);}
static std::string hash(const char*p){std::ifstream f(p,std::ios::binary);require(bool(f),"No binary");CC_SHA256_CTX c;CC_SHA256_Init(&c);std::array<char,65536>b;while(f.read(b.data(),b.size())||f.gcount())CC_SHA256_Update(&c,b.data(),CC_LONG(f.gcount()));require(f.eof(),"Binary read");std::array<unsigned char,32>o{};CC_SHA256_Final(o.data(),&c);std::string s;for(auto v:o){s+="0123456789abcdef"[v>>4];s+="0123456789abcdef"[v&15];}return s;}
struct Restore {void*p;std::vector<unsigned char>b;Restore(void*p,size_t n):p(p),b(n){std::memcpy(b.data(),p,n);}void apply(){std::memcpy(p,b.data(),b.size());}~Restore(){apply();}};
static std::vector<int> events;static int lockDepth=0,violations=0;static int64_t expectedMode=0;static void* expectedReceiver=nullptr;
extern "C" void enterLock(void*){events.push_back(1);if(lockDepth++)++violations;}
extern "C" void leaveLock(void*){events.push_back(6);if(--lockDepth)++violations;}
struct Interface {void**vmt;int32_t refs;int32_t padding;void*target;};
extern "C" uint32_t addRef(Interface*i){events.push_back(2);if(lockDepth!=1)++violations;return uint32_t(++i->refs);}
extern "C" uint32_t releaseRef(Interface*i){events.push_back(5);if(lockDepth!=1)++violations;return uint32_t(--i->refs);}
extern "C" void* getPlugin(Interface*i){events.push_back(3);if(lockDepth!=1||i->refs!=8)++violations;return i->target;}
extern "C" intptr_t captureDispatch(void*p,intptr_t id,intptr_t index,intptr_t value){events.push_back(4);if(p!=expectedReceiver||id!=1||index||value!=expectedMode||lockDepth!=1)++violations;return 0;}
int provider_only_main(int argc,char**argv){@autoreleasepool{try{
 require(argc==2,"Expected engine");require(hash(argv[1])=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine identity changed");
 void*h=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(h,"Engine load failed");Dl_info di{};require(dladdr(dlsym(h,"CreateFruityInstance"),&di)&&di.dli_fbase,"Engine base");auto*b=static_cast<char*>(di.dli_fbase);
 using Provider=void(*)(int32_t,int32_t,uint8_t);auto provider=reinterpret_cast<Provider>(b+0xa2ff0);
 std::array<void*,32> lockVmt{},interfaceVmt{},pluginVmt{};lockVmt[0xc8/8]=reinterpret_cast<void*>(&enterLock);lockVmt[0xd0/8]=reinterpret_cast<void*>(&leaveLock);void**lockPtr=lockVmt.data();
 interfaceVmt[1]=reinterpret_cast<void*>(&addRef);interfaceVmt[2]=reinterpret_cast<void*>(&releaseRef);interfaceVmt[4]=reinterpret_cast<void*>(&getPlugin);pluginVmt[0xd0/8]=reinterpret_cast<void*>(&captureDispatch);
 alignas(16)std::array<unsigned char,320> recipient{},holder{},plugin{},skipped{};recipient.fill(0x56);holder.fill(0x78);plugin.fill(0x9a);skipped.fill(0xbc);
 write(plugin.data(),0,pluginVmt.data());expectedReceiver=plugin.data();Interface iface{interfaceVmt.data(),7,0,plugin.data()};std::memcpy(holder.data()+0x48,&iface,sizeof iface);write(recipient.data(),0x18,holder.data());write(recipient.data(),0x44,int32_t(2));write(skipped.data(),0x44,int32_t(1));
 std::array<void*,2> items{recipient.data(),skipped.data()};alignas(8)std::array<unsigned char,24> list{};write(list.data(),8,items.data());write(list.data(),0x10,int32_t(2));
 auto recipientBefore=recipient,holderBefore=holder,pluginBefore=plugin,skippedBefore=skipped;auto listBefore=list;
 Restore lockGlobal(b+0x19b4848,8),listGlobal(b+0x18d8440,8),indexGlobal(b+0x163ca98,1),pointsGlobal(b+0x18d8510,4),lastGlobal(b+0x18d8514,1),selectorGlobal(b+0x19b4a28,1);
 write(b,0x19b4848,&lockPtr);write(b,0x18d8440,list.data());
 std::array<uint32_t,10> points{};for(size_t i=0;i<points.size();++i)points[i]=read<uint32_t>(b,0x163da60+i*4);
 uint64_t calls=0,deliveries=0,retains=0;
 for(int32_t index=1;index<=10;++index)for(int32_t mode:{0,1,3,0x11,0x13,INT32_MAX,INT32_MIN})for(uint8_t tail:{uint8_t(0),uint8_t(1),uint8_t(255)})for(uint8_t selector:{uint8_t(0),uint8_t(1)}){
 write(b,0x19b4a28,selector);expectedMode=int64_t(int32_t(uint32_t(mode)|(points[size_t(index-1)]<<8)));events.clear();provider(index,mode,tail);
 require(!violations&&lockDepth==0,"Callback ABI/order contract violation");require(events==std::vector<int>({1,2,3,4,5,6}),"Provider callback order differs");
 require(read<uint8_t>(b,0x163ca98)==index&&read<uint32_t>(b,0x18d8510)==points[size_t(index-1)]&&read<uint8_t>(b,0x18d8514)==tail,"Provider controlled globals differ");require(read<uint8_t>(b,0x19b4a28)==selector,"Provider changed DistWave selector");
 require(read<void*>(b,0x19b4848)==&lockPtr&&read<void*>(b,0x18d8440)==list.data(),"Provider replaced controlled list/lock globals");for(size_t i=0;i<points.size();++i)require(read<uint32_t>(b,0x163da60+i*4)==points[i],"Provider changed points table");
 require(recipient==recipientBefore&&holder==holderBefore&&plugin==pluginBefore&&skipped==skippedBefore&&list==listBefore,"Prepared receiver/interface/guards changed");++calls;++deliveries;++retains;
 }
 listGlobal.apply();lockGlobal.apply();indexGlobal.apply();pointsGlobal.apply();lastGlobal.apply();selectorGlobal.apply();
 for(Restore*r:{&listGlobal,&lockGlobal,&indexGlobal,&pointsGlobal,&lastGlobal,&selectorGlobal})require(!std::memcmp(r->p,r->b.data(),r->b.size()),"Global restoration failed");
 std::cout<<"{\"status\":\"passed_prepared_actual_mode_provider\",\"calls\":"<<calls<<",\"mode_deliveries\":"<<deliveries<<",\"balanced_interface_retains\":"<<retains<<",\"restored_globals\":6,\"captured_sender_bytes\":1304,\"substituted_lock_and_recipient_callbacks\":true,\"actual_distwave_selector_writer\":false,\"actual_application_quality_lifecycle\":false,\"full_plugin_equivalence\":false}\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

#include "../../../../reconstruction/plugins/effects/fast_dist_dsp.hpp"
#include <bit>
#include <memory>
#include <random>
#include <cfenv>
static void checkFloatingDomain(){uint64_t fpcr;asm volatile("mrs %0, fpcr":"=r"(fpcr));require(std::fegetround()==FE_TONEAREST&&(fpcr&((3ull<<22)|(1ull<<24)|(31ull<<8)))==0,"Nearest-even gradual FP without traps required");}
static std::array<void*,96> factoryHostVmt{};
static std::array<void*,32> factoryPathVmt{};
static void** factoryPathObject=factoryPathVmt.data();
static const char* factoryPath=nullptr;
using Distortion=void(*)(void*,int32_t,int32_t,float*,int32_t,float,float,float);
static Distortion distortion=nullptr;
extern "C" intptr_t factoryNoop(){return 0;}
extern "C" intptr_t factoryHostDispatch(void*,intptr_t,intptr_t id,intptr_t,intptr_t){
 if(id==71)return reinterpret_cast<intptr_t>(&factoryPathObject);
 if(id==29)return reinterpret_cast<intptr_t>(factoryPath);return 0;
}
extern "C" void forwardDistortion(void*h,int32_t type,int32_t threshold,float*buffer,int32_t count,float dry,float wet,float mul){distortion(h,type,threshold,buffer,count,dry,wet,mul);}
template<class T>static T vmethod(void*p,size_t n){return read<T>(read<void*>(p,0),n);}
int main(int argc,char**argv){@autoreleasepool{try{
 require(argc==4,"Expected engine original-plugin private-directory");
 require(hash(argv[1])=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine identity");
 require(hash(argv[2])=="22b0fc6fa9f3cc065587f5e142ec047d8877432454ca7c25aba9e4eb195c5b82","Plugin identity");
 [NSApplication sharedApplication];checkFloatingDomain();void*engine=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(engine,"Engine load");Dl_info image{};require(dladdr(dlsym(engine,"CreateFruityInstance"),&image)&&image.dli_fbase,"Engine base");auto*b=static_cast<char*>(image.dli_fbase);
 require(read<void*>(b,0x109e180+0x188)==b+0x3d5ff0,"Host distortion identity");distortion=reinterpret_cast<Distortion>(b+0x3d5ff0);reinterpret_cast<void(*)()>(b+0x3e5980)();
 auto tables=std::make_unique<veggie_loops::fast_dist::Tables>();uint64_t tableWords=0;
 for(int type=0;type<2;++type)for(int threshold=1;threshold<=10;++threshold){auto*row=reinterpret_cast<int16_t*>(b+0x18d9768+type*0x28028+(threshold-1)*0x4004);for(size_t i=0;i<8194;++i){require(row[i]==tables->values[size_t(type)][size_t(threshold-1)][i],"Generated table mismatch");++tableWords;}}
 factoryHostVmt.fill(reinterpret_cast<void*>(&factoryNoop));factoryPathVmt.fill(reinterpret_cast<void*>(&factoryNoop));factoryHostVmt[0xc8/8]=reinterpret_cast<void*>(&factoryHostDispatch);factoryHostVmt[0x188/8]=reinterpret_cast<void*>(&forwardDistortion);factoryPath=argv[3];alignas(16)std::array<unsigned char,512> host{};write(host.data(),0,factoryHostVmt.data());
 void*module=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(module,"Plugin load");auto create=reinterpret_cast<void*(*)(void*,intptr_t)>(dlsym(module,"CreatePlugInstance"));require(create,"Original factory");Dl_info pi{};require(dladdr(reinterpret_cast<void*>(create),&pi)&&pi.dli_fbase,"Plugin base");auto*pb=static_cast<char*>(pi.dli_fbase);Dl_info copy{};require(dladdr(read<void*>(pb,0x22fef8),&copy)&&copy.dli_fname&&hash(copy.dli_fname)=="f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1","Copy dependency identity");
 void*original=create(host.data(),42);require(original&&read<void*>(original,0)==pb+0x1bd490&&vmethod<void*>(original,0xd0)==pb+0x5c0b0,"Original class/dispatcher");
 checkFloatingDomain();auto hostBefore=host;
 auto parameter=vmethod<int32_t(*)(void*,int32_t,int32_t,int32_t)>(original,0xf8);auto render=vmethod<void(*)(void*,const float*,float*,int32_t)>(original,0x100);
 std::array<void*,32> lockVmt{},interfaceVmt{},dummyVmt{};lockVmt[0xc8/8]=reinterpret_cast<void*>(&enterLock);lockVmt[0xd0/8]=reinterpret_cast<void*>(&leaveLock);void**lockPtr=lockVmt.data();interfaceVmt[1]=reinterpret_cast<void*>(&addRef);interfaceVmt[2]=reinterpret_cast<void*>(&releaseRef);interfaceVmt[4]=reinterpret_cast<void*>(&getPlugin);dummyVmt[0xd0/8]=reinterpret_cast<void*>(&captureDispatch);
 alignas(16)std::array<unsigned char,320> originalRecipient{},originalHolder{},captureRecipient{},captureHolder{},dummy{};originalRecipient.fill(0x11);originalHolder.fill(0x22);captureRecipient.fill(0x33);captureHolder.fill(0x44);dummy.fill(0x55);write(dummy.data(),0,dummyVmt.data());expectedReceiver=dummy.data();Interface oi{interfaceVmt.data(),7,0,original},ci{interfaceVmt.data(),7,0,dummy.data()};std::memcpy(originalHolder.data()+0x48,&oi,sizeof oi);std::memcpy(captureHolder.data()+0x48,&ci,sizeof ci);write(originalRecipient.data(),0x18,originalHolder.data());write(captureRecipient.data(),0x18,captureHolder.data());write(originalRecipient.data(),0x44,int32_t(2));write(captureRecipient.data(),0x44,int32_t(2));
 std::array<void*,2> items{originalRecipient.data(),captureRecipient.data()};alignas(8)std::array<unsigned char,24> list{};write(list.data(),8,items.data());write(list.data(),0x10,int32_t(2));
 auto orBefore=originalRecipient,ohBefore=originalHolder,crBefore=captureRecipient,chBefore=captureHolder,dBefore=dummy;auto listBefore=list;
 Restore lockGlobal(b+0x19b4848,8),listGlobal(b+0x18d8440,8),indexGlobal(b+0x163ca98,1),pointsGlobal(b+0x18d8510,4),tailGlobal(b+0x18d8514,1),selectorGlobal(b+0x19b4a28,1);write(b,0x19b4848,&lockPtr);write(b,0x18d8440,list.data());
 using Provider=void(*)(int32_t,int32_t,uint8_t);auto provider=reinterpret_cast<Provider>(b+0xa2ff0);std::mt19937 rng(0x7175616c);veggie_loops::fast_dist::Processor model;uint64_t calls=0,frames=0,samples=0,differentQuality=0;std::array<uint32_t,10> pointsBefore{};for(size_t i=0;i<pointsBefore.size();++i)pointsBefore[i]=read<uint32_t>(b,0x163da60+i*4);constexpr std::array<int32_t,8> lengths{0,1,7,8,17,63,257,1024};
 for(int index=1;index<=10;++index)for(int32_t mode:{0,1,3,17,19,INT32_MAX,INT32_MIN})for(uint8_t tail:{uint8_t(0),uint8_t(1),uint8_t(255)})for(uint8_t selector:{uint8_t(0),uint8_t(1)}){
  const std::array<int32_t,5> values{64+int32_t(rng()%129),1+int32_t(rng()%10),int32_t(rng()%2),int32_t(rng()%129),int32_t(rng()%129)};for(int p=0;p<5;++p){require(parameter(original,p,values[size_t(p)],1)==values[size_t(p)],"Original control");model.set(p,values[size_t(p)]);}
  std::array<unsigned char,32> numericBefore{};std::memcpy(numericBefore.data(),static_cast<char*>(original)+0x128,32);
  write(b,0x19b4a28,selector);auto points=read<uint32_t>(b,0x163da60+size_t(index-1)*4);expectedMode=int64_t(int32_t(uint32_t(mode)|(points<<8)));events.clear();provider(index,mode,tail);checkFloatingDomain();
  require(!violations&&lockDepth==0&&events==std::vector<int>({1,2,3,5,2,3,4,5,6}),"Actual original provider callback chain");require(!std::memcmp(numericBefore.data(),static_cast<char*>(original)+0x128,32),"Mode packet changed captured numerical state");require(read<uint8_t>(b,0x19b4a28)==selector,"Mode packet changed DistWave selector");
  for(size_t i=0;i<pointsBefore.size();++i)require(read<uint32_t>(b,0x163da60+i*4)==pointsBefore[i],"Mode packet changed points table");require(host==hostBefore,"Original modified prepared host fields");
  require(originalRecipient==orBefore&&originalHolder==ohBefore&&captureRecipient==crBefore&&captureHolder==chBefore&&dummy==dBefore&&list==listBefore,"Prepared object guard bytes");require(read<void*>(b,0x19b4848)==&lockPtr&&read<void*>(b,0x18d8440)==list.data(),"Controlled globals pointer change");require(read<uint8_t>(b,0x163ca98)==index&&read<uint32_t>(b,0x18d8510)==points&&read<uint8_t>(b,0x18d8514)==tail,"Mode global state");
  int count=lengths[size_t(calls)%lengths.size()];size_t n=size_t(count)*2;std::vector<float> input(n+8),actual(n+8,1234),expected(n+8,1234),opposite(n+8,1234);for(auto&v:input)v=float(int32_t(rng()%1048577)-524288)*0x1p-15f;if(n>1){input[0]=-0.f;input[1]=0.f;}auto before=input;bool alias=calls%3==0;if(alias){actual=input;expected=input;}
  render(original,alias?actual.data():input.data(),actual.data(),count);model.render(*tables,alias?expected.data():input.data(),expected.data(),count,selector!=0);model.render(*tables,input.data(),opposite.data(),count,selector==0);
  for(size_t i=0;i<n;++i){require(std::bit_cast<uint32_t>(actual[i])==std::bit_cast<uint32_t>(expected[i]),"Original DSP after mode packet differs");if(std::bit_cast<uint32_t>(actual[i])!=std::bit_cast<uint32_t>(opposite[i]))++differentQuality;}
  for(size_t i=n;i<n+8;++i){float guard=alias?before[i]:1234.f;require(std::bit_cast<uint32_t>(actual[i])==std::bit_cast<uint32_t>(guard)&&std::bit_cast<uint32_t>(expected[i])==std::bit_cast<uint32_t>(guard),"Render guard change");}require(!std::memcmp(input.data(),before.data(),input.size()*4),"Input changed");++calls;frames+=uint64_t(count);samples+=n;
 }
 require(differentQuality>0,"Opposite quality negative discrimination absent");for(Restore*r:{&lockGlobal,&listGlobal,&indexGlobal,&pointsGlobal,&tailGlobal,&selectorGlobal}){r->apply();require(!std::memcmp(r->p,r->b.data(),r->b.size()),"Global restoration");}
 vmethod<void(*)(void*)>(original,0xc8)(original);dlclose(module);
 std::cout<<"{\"status\":\"passed_actual_mode_provider_original_fast_dist\",\"actual_provider_calls\":"<<calls<<",\"original_fast_dist_deliveries\":"<<calls<<",\"native_parameter_calls\":"<<calls*5<<",\"capture_recipient_deliveries\":"<<calls<<",\"balanced_interface_retains\":"<<calls*2<<",\"table_entries\":"<<tableWords<<",\"render_callbacks\":"<<calls<<",\"stereo_frames\":"<<frames<<",\"exact_sample_comparisons\":"<<samples<<",\"opposite_quality_different_samples\":"<<differentQuality<<",\"restored_globals\":6,\"selector_writer_executed\":false,\"actual_application_lifecycle\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

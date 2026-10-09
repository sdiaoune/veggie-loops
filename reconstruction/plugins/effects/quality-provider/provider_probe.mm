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
int main(int argc,char**argv){@autoreleasepool{try{
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

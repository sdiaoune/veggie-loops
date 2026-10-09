#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error The image-pinned loader requires macOS arm64.
#endif
#include "three_osc_native_factory.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <vector>
void require(bool v,const char*m){if(!v)throw std::runtime_error(m);}
template<class T>T load(void*p,size_t o){T v;std::memcpy(&v,static_cast<char*>(p)+o,sizeof v);return v;}
template<class T>T method(void*p,size_t o){return load<T>(load<void*>(p,0),o);}
std::string hash(const char*p){std::ifstream in(p,std::ios::binary);require(in.good(),"Missing engine");std::vector<char>b{std::istreambuf_iterator<char>(in),{}};std::array<unsigned char,32>d{};CC_SHA256(b.data(),CC_LONG(b.size()),d.data());std::ostringstream out;for(auto v:d)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(v);return out.str();}
struct ImmutablePath {std::vector<uint64_t>words;explicit ImmutablePath(const char*path){NSString*s=[NSString stringWithUTF8String:path];require(s!=nil,"Path invalid");auto n=[s length];words.resize((24+(n+1)*2+7)/8);words[0]=0x204b0;words[1]=~uint64_t{};words[2]=n;[s getCharacters:reinterpret_cast<unichar*>(words.data()+3) range:NSMakeRange(0,n)];}const char16_t*data()const{return reinterpret_cast<const char16_t*>(words.data()+3);}};
struct Stream {void**functions;std::vector<uint8_t>bytes;size_t cursor=0;};
int32_t writeStream(Stream*s,const void*p,uint32_t n,uint32_t*done){auto*b=static_cast<const uint8_t*>(p);s->bytes.insert(s->bytes.end(),b,b+n);if(done)*done=n;return 0;}
int32_t readStream(Stream*s,void*p,uint32_t n,uint32_t*done){require(s->cursor+n<=s->bytes.size(),"Read overflow");std::memcpy(p,s->bytes.data()+s->cursor,n);s->cursor+=n;if(done)*done=n;return 0;}
int main(int argc,char**argv){@autoreleasepool{try{
 require(argc==3,"Expected engine and logical rebuilt path");require(hash(argv[1])=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine hash mismatch");[NSApplication sharedApplication];void*engine=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(engine,"Engine load failed");Dl_info info{};require(dladdr(dlsym(engine,"CreateFruityInstance"),&info),"No engine base");auto*base=static_cast<char*>(info.dli_fbase);ImmutablePath path(argv[2]);void*library=nullptr;auto loader=reinterpret_cast<void*(*)(const char16_t*,void**,intptr_t)>(base+0x3e1450);void*wrapper=loader(path.data(),&library,0x564c);require(wrapper&&library,"Loader refused factory");require(load<void*>(wrapper,0)==base+0x1497618&&load<intptr_t>(wrapper,8)==0x564c,"Loader adapter/tag mismatch");const auto*metadata=load<const vl_private_osc::Info*>(wrapper,16);require(metadata&&metadata->version==1&&metadata->parameters==114&&metadata->flags==((1<<21)|1|16|32)&&std::strcmp(metadata->long_name,"VL 3 Osc private factory")==0,"Wrong metadata");require(!dlsym(library,"SetExternalAppHandle"),"Unexpected Pascal selector");
 // No source host callbacks/notes here: actual application host is absent.
 // The lazy factory can therefore be tested through the intact DLL loader.
 auto*cpp=load<vl_private_osc::Plugin*>(wrapper,0xa8);auto channel=reinterpret_cast<decltype(&vl_private_osc_channel)>(dlsym(library,"vl_private_osc_channel"));require(channel&&!channel(cpp),"Factory unexpectedly initialized host-dependent voice channel");auto parameter=method<int32_t(*)(void*,int32_t,int32_t,int32_t)>(wrapper,0xf8);size_t gets=0;
 for(int i=0;i<114;++i){const auto before=parameter(wrapper,i,0,2);require(parameter(wrapper,i,before,1)==before&&parameter(wrapper,i,0,2)==before,"Loader get/set defaults mismatch");gets+=2;}
 std::array<void*,5>streamVmt{};streamVmt[3]=reinterpret_cast<void*>(&readStream);streamVmt[4]=reinterpret_cast<void*>(&writeStream);Stream stream{streamVmt.data(),{},0};auto state=method<void(*)(void*,void*,int32_t)>(wrapper,0xe0);state(wrapper,&stream,1);require(stream.bytes.size()==460&&load<int32_t>(stream.bytes.data(),0)==14,"Loader state framing differs");const auto before=stream.bytes;state(wrapper,&stream,0);require(stream.cursor==460,"Loader state restore count differs");Stream after{streamVmt.data(),{},0};state(wrapper,&after,1);require(after.bytes==before,"Loader semantic state roundtrip differs");require(!channel(cpp),"Storage callbacks initialized actual host voice channel");method<void(*)(void*)>(wrapper,0xc8)(wrapper);method<void(*)(void*,intptr_t)>(wrapper,0x60)(wrapper,1);dlclose(library);dlclose(engine);
 std::cout<<"{\"status\":\"passed\",\"intact_engine_DLL_loader_accepted_CPP_generator\":true,\"loader_metadata_and_114_controls\":true,\"getters\":"<<gets<<",\"stored_state_bytes\":460,\"voice_channel_created\":false,\"actual_application_host\":false,\"original_Pascal_factory_rebuilt\":false,\"full_plugin_equivalence\":false}\n";return 0;
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

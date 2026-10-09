#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error Measured engine adapter offsets require macOS arm64.
#endif
#include "stereo_shaper_native_abi.h"
#include "stereo_shaper_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <bit>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>
namespace {
using namespace veggie_loops::stereo_shaper::native;
void require(bool value,const char*text){if(!value)throw std::runtime_error(text);}
template<class T>T load(void*p,size_t off){T value;std::memcpy(&value,static_cast<char*>(p)+off,sizeof(T));return value;}
template<class T>T method(void*p,size_t off){return load<T>(load<void*>(p,0),off);}
std::string hash(const char*path){std::ifstream file(path,std::ios::binary);require(file.good(),"Missing target");std::vector<uint8_t>bytes{std::istreambuf_iterator<char>(file),{}};std::array<uint8_t,32>digest{};CC_SHA256(bytes.data(),CC_LONG(bytes.size()),digest.data());std::ostringstream out;for(auto b:digest)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(b);return out.str();}
struct Host{void**vmt;float*buffer=nullptr;bool available=true;std::vector<uint32_t>flags;};
void getOut(Host*h,intptr_t tag,intptr_t index,IOBuffer*io){require(tag==0x564c&&index>=1&&index<=3,"Host side identity differs");h->flags.push_back(io->flags);if(io->flags==0)io->buffer=h->available?h->buffer:nullptr;}
struct Memory{Stream interface{};std::array<void*,5>vmt{};std::array<uint8_t,36>bytes{};size_t cursor=0;Memory(){interface.functions=vmt.data();vmt[3]=reinterpret_cast<void*>(&read);vmt[4]=reinterpret_cast<void*>(&write);}
  static int32_t read(Stream*p,void*out,uint32_t size,uint32_t*count){auto&s=*reinterpret_cast<Memory*>(p);if(s.cursor+size>36){if(count)*count=0;return -1;}std::memcpy(out,s.bytes.data()+s.cursor,size);s.cursor+=size;if(count)*count=size;return 0;}
  static int32_t write(Stream*p,void*in,uint32_t size,uint32_t*count){auto&s=*reinterpret_cast<Memory*>(p);if(s.cursor+size>36){if(count)*count=0;return -1;}std::memcpy(s.bytes.data()+s.cursor,in,size);s.cursor+=size;if(count)*count=size;return 0;}
};
void word(uint8_t*p,uint32_t value){for(size_t i=0;i<4;++i)p[i]=uint8_t(value>>(i*8));}
}
int main(int argc,char**argv){@autoreleasepool{try{
  require(argc==3,"Usage: test_stereo_shaper_host_routing <engine> <rebuilt native dylib>");require(hash(argv[1])=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine identity changed");
  [NSApplication sharedApplication];void*engine=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(engine,"Engine load failed");Dl_info image{};require(dladdr(dlsym(engine,"CreateFruityInstance"),&image),"Engine base unavailable");auto*base=static_cast<char*>(image.dli_fbase);
  std::array<void*,96>hostVmt{};hostVmt[0x1f0/8]=reinterpret_cast<void*>(&getOut);Host host{};host.vmt=hostVmt.data();using Constructor=void*(*)(void*,intptr_t,void*);
  auto hostCtor=reinterpret_cast<Constructor>(base+0xb4cd20);void*hostAdapter=hostCtor(base+0x1497870,1,&host);require(hostAdapter,"Actual host adapter allocation failed");void*cppHost=static_cast<char*>(hostAdapter)+16;
  require(load<void**>(cppHost,0)[37]==base+0xb4e990,"Unexpected actual GetOutBuffer interface thunk");
  void*rebuilt=dlopen(argv[2],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Rebuilt module failed");auto bind=[&](const char*name){void*p=dlsym(rebuilt,name);require(p,"Rebuilt symbol missing");return p;};
  auto factory=reinterpret_cast<Plugin*(*)(void*,intptr_t)>(bind("CreatePlugInstance"));Plugin*plugin=factory(cppHost,0x564c);require(plugin,"Native factory failed");auto pluginCtor=reinterpret_cast<Constructor>(base+0xb4c7c0);void*wrapper=pluginCtor(base+0x1497618,1,plugin);require(wrapper,"Actual plugin adapter allocation failed");
  auto create=reinterpret_cast<decltype(&vl_stereo_shaper_create)>(bind("vl_stereo_shaper_create"));auto destroy=reinterpret_cast<decltype(&vl_stereo_shaper_destroy)>(bind("vl_stereo_shaper_destroy"));auto restore=reinterpret_cast<decltype(&vl_stereo_shaper_restore_state)>(bind("vl_stereo_shaper_restore_state"));auto process=reinterpret_cast<decltype(&vl_stereo_shaper_render)>(bind("vl_stereo_shaper_render"));auto rate=reinterpret_cast<decltype(&vl_stereo_shaper_sample_rate)>(bind("vl_stereo_shaper_sample_rate"));auto resume=reinterpret_cast<decltype(&vl_stereo_shaper_resume)>(bind("vl_stereo_shaper_resume"));auto*direct=create();require(direct,"Reference create failed");
  const auto state=method<void(*)(void*,Stream*,int32_t)>(wrapper,0xe0);const auto render=method<void(*)(void*,const float*,float*,int32_t)>(wrapper,0x100);const auto dispatch=method<intptr_t(*)(void*,intptr_t,intptr_t,intptr_t)>(wrapper,0xd0);
  std::mt19937 random(0x564c534f);size_t frames=0,sequences=0;const std::array<int32_t,20>lengths{0,1,2,3,4,7,8,9,15,16,17,31,32,33,63,64,65,257,512,1024};
  for(size_t sequence=0;sequence<600;++sequence){Memory stream;for(int i=0;i<6;++i)word(stream.bytes.data()+4+i*4,uint32_t(int32_t(random()%(i<4?51201:8193))-(i<4?25600:4096)));word(stream.bytes.data()+28,uint32_t(sequence%4));word(stream.bytes.data()+32,uint32_t(sequence&1));state(wrapper,&stream.interface,0);require(stream.cursor==36&&restore(direct,stream.bytes.data(),36),"State routing restore failed");
    const std::array<int32_t,5>rates{22050,44100,48000,96000,192000};dispatch(wrapper,4,0,rates[sequence%5]);require(rate(direct,rates[sequence%5]),"Rate failed");if(sequence%11==0){dispatch(wrapper,2,0,0);require(resume(direct),"Resume failed");}
    const int32_t count=lengths[sequence%lengths.size()];const size_t start=sequence&1;std::vector<float>input(size_t(count)*2+16);for(auto&sample:input)sample=float(int32_t(random()%65536)-32768)/8192.0f;std::vector<float>a(input.size(),1234),b(a);const bool alias=(sequence%3)==0;const auto initial=alias?input:a;if(alias){a=input;b=input;}
    const auto initialInput=input;std::vector<float>side(size_t(count)*2+8,0.25f),expectedSide(side);host.buffer=side.data();host.available=(sequence%5)!=0;host.flags.clear();render(wrapper,alias?a.data()+start:input.data()+start,a.data()+start,count);require(process(direct,alias?b.data()+start:input.data()+start,b.data()+start,count,(sequence%4)&&host.available?expectedSide.data():nullptr),"Direct render failed");
    require(std::memcmp(input.data(),initialInput.data(),input.size()*4)==0,"Disjoint source changed");
    require(std::memcmp(a.data(),b.data(),a.size()*4)==0&&std::memcmp(side.data(),expectedSide.data(),side.size()*4)==0,"Actual adapters changed audio/side contribution");
    for(size_t i=0;i<a.size();++i)if(i<start||i>=start+size_t(count)*2)require(std::bit_cast<uint32_t>(a[i])==std::bit_cast<uint32_t>(initial[i])&&std::bit_cast<uint32_t>(b[i])==std::bit_cast<uint32_t>(initial[i]),"Main guard changed");for(size_t i=size_t(count)*2;i<side.size();++i)require(side[i]==0.25f&&expectedSide[i]==0.25f,"Side guard changed");
    if(sequence%4){require(host.flags==std::vector<uint32_t>{0,1},"Actual adapter lock/unlock failed");++sequences;}else require(host.flags.empty(),"Inactive send called host");frames+=count;
  }
  method<void(*)(void*)>(wrapper,0xc8)(wrapper);method<void(*)(void*,intptr_t)>(wrapper,0x60)(wrapper,1);method<void(*)(void*,intptr_t)>(hostAdapter,0x60)(hostAdapter,1);destroy(direct);dlclose(rebuilt);dlclose(engine);
  std::cout<<"{\"status\":\"passed\",\"actual_engine_plugin_and_host_adapters\":true,\"get_out_buffer_cpp_slot\":37,\"pascal_slot\":496,\"routing_state_restores\":600,\"side_output_sequences\":"<<sequences<<",\"stereo_frames\":"<<frames<<",\"actual_fl_application_created\":false,\"full_plugin_equivalence\":false}\n";
}catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}}

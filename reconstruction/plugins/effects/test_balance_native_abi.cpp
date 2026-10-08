#include "balance_native_abi.h"
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This engine adapter replay requires macOS arm64.
#endif
#include <CommonCrypto/CommonDigest.h>
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <dlfcn.h>
#include <array>
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
using namespace veggie_loops::balance::native;
void require(bool value,const char* message){if(!value)throw std::runtime_error(message);}
std::vector<std::uint8_t> read(const char* path){
  std::ifstream in(path,std::ios::binary);require(in.good(),"Cannot read engine");
  return {std::istreambuf_iterator<char>(in),std::istreambuf_iterator<char>()};
}
std::string hash(const void* bytes,std::size_t length){
  std::array<unsigned char,CC_SHA256_DIGEST_LENGTH> result{};
  CC_SHA256(bytes,static_cast<CC_LONG>(length),result.data());
  std::ostringstream out;for(auto v:result)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(v);
  return out.str();
}
struct Body{std::size_t address,length;const char* hash;};
constexpr Body bodies[]={
  {0xb4c910,40,"b5035cbf586ed8d8512cbac043b51593cccf049beb3bda82466bbe9885458466"},
  {0xb4c940,60,"8c9c5f01ea9c0178da68f538867a528b2d848331acf67be158e6a54b665478fe"},
  {0xb4c980,40,"cdb96bfe8dcb7f030ac09d9a4ef879f312f766df2dc6a57aa9ebfa2ce27cd462"},
  {0xb4c9b0,40,"2fd8d0aad6183925a891f2a5c9fdec3bc12a72b87e016610960d06ac0d9c0cb4"},
  {0xb4c9e0,40,"9585fa8bc02beed8cbe92ed5481c33cd9257a1c07dfd4554210b4c2bd0b26e48"},
  {0xb4ca10,40,"4a6e269444eefcafe39ea5a7ee9b220bc878492815ff94cca883cbb763de93d6"},
  {0xb4ca40,40,"8201bca9271fc8f0b9867d2e67cdd87ef57507a2208c7aaa63d6723d4d641638"},
  {0xb4ca70,40,"feb0f69574885349b495e9ed755407c517e32f2b90fdb1946be7e71ee84a39f2"},
  {0xb4caa0,40,"dff5bb2ab6f8a913ef5d97415b1ccaf0a21953bc250c036b0df140b6388bc779"},
  {0xb4cad0,40,"7268ad8648c1ac2d92f68008f89a06a956805131eff98916b52e34bd9ff825c4"},
  {0xb4cb00,40,"3ada23ee956a451516803361dbb0a37afcf1180bdf94154585bcd7f9cd745323"},
  {0xb4cb30,40,"fca9c5b130e91da782eccb51f3234d070403ee1d89256335403c4d0d3028cd2a"},
  {0xb4cb60,40,"8ccd03c770f2395a07d712c88eb83c298a788d2b0a7d3ac24e85d86a944328d0"},
  {0xb4cb90,40,"5e5522ea7f448a4e7d6dc7599aa4a865c3ab7626229a95ea8775ed7f7480a7ae"},
  {0xb4cbc0,40,"e9953d9954efe52f76bc403ef424260251f45b0fe81e2a44772ba51f33e3f129"},
  {0xb4cbf0,40,"cd2baf54249c171aed56d58d6828c1edb3f2102850736954282d937c0a3d084a"},
  {0xb4cc20,40,"50063a1b90fb05d9a3ed0449f2b492c43c3fce5d7fdd9c3748e80e456d56e881"},
  {0xb4cc50,40,"17f3d6f95caf10636109cdda081f7cd9aa5555e15ee39e822bad0e1f41bf8036"},
  {0xb4cc80,40,"0c83d75b544ad1d23f94960dd56478b42e791cb970263655e1eda3fc1b66429f"},
  {0xb4ccb0,40,"487d7f88b4ecc10096d2e456f25d7717fa9a388a7a812eff56cbb22ff5926e47"},
  {0xb4cce0,52,"11fa664e113dba48ce3dd850eb7862fa90cfd26422a87cba202f4c9f03d55f99"},
};
class EngineReplay{
 public:
  explicit EngineReplay(const std::vector<std::uint8_t>& bytes){
    const auto page=static_cast<std::size_t>(sysconf(_SC_PAGESIZE));
    start_=0xb4c910/page*page;size_=(0xb4cd14-start_+page-1)/page*page;
    code_=static_cast<std::uint8_t*>(mmap(nullptr,size_,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0));
    require(code_!=MAP_FAILED,"Cannot map engine methods");
    try{
      for(const auto& b:bodies){
        require(hash(bytes.data()+b.address,b.length)==b.hash,"Engine method hash mismatch");
        std::memcpy(code_+b.address-start_,bytes.data()+b.address,b.length);
      }
      require(mprotect(code_,size_,PROT_READ|PROT_EXEC)==0,"Cannot protect engine methods");
      sys_icache_invalidate(code_,size_);
    }catch(...){munmap(code_,size_);throw;}
  }
  ~EngineReplay(){munmap(code_,size_);}
  template<class T>T at(std::size_t address)const{return reinterpret_cast<T>(code_+address-start_);}
 private:std::uint8_t* code_;std::size_t start_,size_;
};
struct PascalObject{
  alignas(16) std::array<std::uint8_t,184> bytes{};
  explicit PascalObject(Plugin* plugin){put(0xa8,plugin);put(0xb0,plugin);}
  template<class T>void put(std::size_t off,const T& v){std::memcpy(bytes.data()+off,&v,sizeof(v));}
  template<class T>T get(std::size_t off)const{T v;std::memcpy(&v,bytes.data()+off,sizeof(v));return v;}
};
struct MemoryStream{
  Stream interface{};std::array<void*,14> functions{};std::array<std::uint8_t,8> bytes{};
  MemoryStream(){functions[3]=reinterpret_cast<void*>(&transferRead);functions[4]=reinterpret_cast<void*>(&transferWrite);interface.functions=functions.data();}
  static std::intptr_t transferRead(Stream* s,void* destination,std::uint64_t length,std::uint64_t* count){
    auto& m=*reinterpret_cast<MemoryStream*>(s);if(length!=8)return -1;
    std::memcpy(destination,m.bytes.data(),8);if(count)*count=8;return 0;
  }
  static std::intptr_t transferWrite(Stream* s,void* source,std::uint64_t length,std::uint64_t* count){
    auto& m=*reinterpret_cast<MemoryStream*>(s);if(length!=8)return -1;
    std::memcpy(m.bytes.data(),source,8);if(count)*count=8;return 0;
  }
};
}
int main(int argc,char** argv){
  try{
    require(argc==4,"Usage: test_balance_native_abi original-engine arm64-engine rebuilt-native-library");
    const auto source=read(argv[1]),slice=read(argv[2]);
    require(hash(source.data(),source.size())=="22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37","Engine source identity changed");
    require(hash(slice.data(),slice.size())=="04db862b730950c5e2b678e5477900bec29ab839bf35611dce92be1795636eb0","Engine slice identity changed");
    EngineReplay engine(slice);void* library=dlopen(argv[3],RTLD_NOW|RTLD_LOCAL);require(library,"Cannot load rebuilt native library");
    require(dlsym(library,"SetExternalAppHandle")==nullptr,"Unexpected Pascal selector export");
    auto factory=reinterpret_cast<Plugin*(*)(void*,std::intptr_t)>(dlsym(library,"CreatePlugInstance"));
    require(factory,"Missing native factory");
    auto* adapted=factory(nullptr,0x12345);auto* direct=factory(nullptr,0x12345);
    require(adapted && direct,"Native factory failed");
    PascalObject wrapper(adapted);void* self=wrapper.bytes.data();
    engine.at<void(*)(void*)>(0xb4cce0)(self);
    require(wrapper.get<std::intptr_t>(8)==0x12345 && wrapper.get<const Info*>(16)==adapted->info,"Engine field bridge failed");
    require(adapted->info->version==1 && adapted->info->parameterCount==2 && adapted->info->flags==(1<<21),"Native info incorrect");
    auto parameter=engine.at<std::int32_t(*)(void*,std::int32_t,std::int32_t,std::int32_t)>(0xb4cb90);
    auto render=engine.at<void(*)(void*,const float*,float*,std::int32_t)>(0xb4c980);
    auto dispatch=engine.at<std::intptr_t(*)(void*,std::intptr_t,std::intptr_t,std::intptr_t)>(0xb4c940);
    auto state=engine.at<void(*)(void*,Stream*,std::int32_t)>(0xb4cbc0);
    auto name=engine.at<void(*)(void*,std::int32_t,std::int32_t,std::int32_t,char*)>(0xb4c9e0);
    std::mt19937 random(0x564c);std::size_t frames=0,cases=0;
    const std::array<std::int32_t,12> lengths{0,1,2,3,7,8,9,16,17,63,257,1024};
    for(std::int32_t k=0;k<1200;++k){
      for(std::int32_t index=0;index<2;++index){
        const auto value=(k%3==0)?static_cast<std::int32_t>(random()%0x40000001u):
          index==0?static_cast<std::int32_t>(random()%257)-128:static_cast<std::int32_t>(random()%321);
        const auto flags=(k%3==0)?49:17;
        require(parameter(self,index,value,flags)==direct->functions->parameter(direct,index,value,flags),"Engine parameter bridge differs");
      }
      if(k%7==0){const std::intptr_t rate=8000+random()%184001;dispatch(self,4,0,rate);direct->functions->dispatch(direct,4,0,rate);}
      if(k%11==0){dispatch(self,2,0,0);direct->functions->dispatch(direct,2,0,0);}
      MemoryStream a,b;state(self,&a.interface,1);direct->functions->state(direct,&b.interface,1);
      require(a.bytes==b.bytes,"Engine state bridge differs");
      if(k%5==0){parameter(self,0,0,17);state(self,&b.interface,0);}
      const auto length=lengths[k%lengths.size()];std::vector<float> input(2*length+2),left(input.size()),right(input.size());
      for(auto& v:input)v=static_cast<float>(static_cast<std::int32_t>(random()%65537)-32768)/32768.0f;
      render(self,input.data(),left.data(),length);direct->functions->effect(direct,input.data(),right.data(),length);
      require(std::memcmp(left.data(),right.data(),2*length*sizeof(float))==0,"Engine audio bridge differs");
      for(std::int32_t i=0;i<2;++i){std::array<char,256>x{},y{};name(self,0,i,0,x.data());direct->functions->name(direct,0,i,0,y.data());require(x==y,"Engine name bridge differs");}
      frames+=length;++cases;
    }
    engine.at<void(*)(void*)>(0xb4ca10)(self);
    require(engine.at<std::int32_t(*)(void*,std::int32_t,std::int32_t,std::int32_t)>(0xb4cb60)(self,0,0,0)==0,"Engine event bridge differs");
    // All unused effect callbacks must still occupy the correct protocol slots.
    std::array<float,8> guard{1,2,3,4,5,6,7,8};std::int32_t length=4;
    engine.at<void(*)(void*,float*,std::int32_t&)>(0xb4c9b0)(self,guard.data(),length);
    require(length==0 && guard==std::array<float,8>{1,2,3,4,5,6,7,8},"Engine generator ABI differs");
    require(engine.at<std::intptr_t(*)(void*,void*,std::intptr_t)>(0xb4cbf0)(self,nullptr,0x1234)==-1,"Engine voice ABI differs");
    for(auto address:{0xb4cc20,0xb4cc80,0xb4cb00})engine.at<void(*)(void*,std::intptr_t)>(address)(self,0x1234);
    for(auto address:{0xb4cc50,0xb4cb30})
      require(engine.at<std::int32_t(*)(void*,std::intptr_t,std::intptr_t,std::intptr_t,std::intptr_t)>(address)(self,0x1234,1,2,3)==0,"Engine voice event ABI differs");
    length=4;require(engine.at<std::int32_t(*)(void*,std::intptr_t,float*,std::int32_t&)>(0xb4ccb0)(self,0x1234,guard.data(),length)==0 && length==0,"Engine voice render ABI differs");
    for(auto address:{0xb4ca70,0xb4cad0})engine.at<void(*)(void*)>(address)(self);
    std::int32_t midi=0x1234;engine.at<void(*)(void*,std::int32_t&)>(0xb4ca40)(self,midi);require(midi==0x1234,"Engine MIDI ABI differs");
    engine.at<void(*)(void*,std::intptr_t)>(0xb4caa0)(self,0x1234);
    engine.at<void(*)(void*)>(0xb4c910)(self);direct->functions->destroy(direct);dlclose(library);
    std::cout<<"{\"status\":\"passed\",\"engine_adapter_routines\":21,\"public_callback_slots_exercised\":20,\"rebuilt_native_factory_loaded\":true,\"cases\":"<<cases<<",\"stereo_frames\":"<<frames<<",\"full_fl_host_loading\":false,\"full_plugin_equivalence\":false}\n";
  }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}

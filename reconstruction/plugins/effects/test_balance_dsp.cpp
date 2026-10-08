#include "balance_dsp.hpp"

#if !defined(__APPLE__) || !defined(__aarch64__)
#error This differential replay requires macOS arm64.
#endif

#include <CommonCrypto/CommonDigest.h>
#include <libkern/OSCacheControl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <random>
#include <set>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace {
using veggie_loops::balance::State;
using veggie_loops::balance::Controls;
constexpr const char* kSourceHash = "525e96102a4eddc89de484ec3bc6a3c92788738c1dc50b5a5fa71bbd994e77ef";
constexpr const char* kSliceHash = "8a0320e4cf2ba57e076b22264f1c9c78d0b37c2bda9053c8d0e08c98d33b430b";
constexpr float kFloor = 0x1p-24f;
struct Body { std::size_t address, size; const char* hash; };
constexpr std::array<Body, 11> kBodies{{
  {0x288c,456,"a3320d5111d8cc8cd4ef0d62555832573e762d04181b7522a84c2c94b57714c3"},
  {0x2bf0,208,"44c8fb08eb125b7a043e5cf5e4e02b2cb26869201259a3dde9abfb6e1de1c8a7"},
  {0x5b400,248,"f37c166a3899ab59cf53475d4f2ace247b54bb3e6ad2216c110217119c6a0ea1"},
  {0x14a8a0,4,"af47aa69d039f5c9996a5232ce8039b7cc1c0617e41c1012dfd75272018ce735"},
  {0x14af20,216,"adcfd2cf6c4756558183c236932e5a39043a7c5c32d38e4f64ebaffc144e8b0c"},
  {0x5ade0,1360,"f4ae777ea8dce62e09a98a75248f91ef43fc47f558281e17fe908312d5184e2f"},
  {0x5ab0,20,"0fbac99a6c8d1199219a1ca1867316512b6dd74b88acd2926d273def46aa5adf"},
  {0x5af0,20,"ab7ed049a9f4a068d2a8d32d4dd08128d494131c9e9930f908f281e8dc2105e0"},
  {0x5b10,20,"6cca2461d58311dc339329865fa8335dc6bdbd913a0ee920eaad047cb87b0bcc"},
  {0x94c60,68,"22ae418cf25fa6f290dfb324ae3e4618156c452c7dbb414df8ff303af1fdfa77"},
  {0x1331c0,20,"dbd688b4ca6baca3f6eb4ee2075f67a6b37d58ef9c85dd93eb249de08b32edfa"},
}};
extern "C" void replayNoOp() {}
extern "C" int replaySetjmpSuccess() {return 0;}
void require(bool value,const std::string& message) {
  if (!value) throw std::runtime_error(message);
}
std::vector<std::uint8_t> read(const char* path) {
  std::ifstream input(path,std::ios::binary);
  require(input.good(),std::string("Cannot read ")+path);
  return {std::istreambuf_iterator<char>(input),std::istreambuf_iterator<char>()};
}
std::string digest(const std::uint8_t* bytes,std::size_t size) {
  require(size<=std::numeric_limits<CC_LONG>::max(),"Hash input exceeds CC_LONG");
  std::array<unsigned char,CC_SHA256_DIGEST_LENGTH> result{};
  CC_SHA256(bytes,static_cast<CC_LONG>(size),result.data());
  std::ostringstream out;
  for (auto byte:result) out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);
  return out.str();
}
class Replay {
 public:
  explicit Replay(const std::vector<std::uint8_t>& bytes) {
    const auto page=sysconf(_SC_PAGESIZE);
    require(page>0 && page%4096==0,"Invalid page alignment for original ADRP instructions");
    page_=static_cast<std::size_t>(page);
    size_=round(0x231000)+page_;
    base_=static_cast<std::uint8_t*>(mmap(nullptr,size_,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0));
    require(base_!=MAP_FAILED,"Cannot reserve replay image");
    try {
      std::set<std::size_t> code;
      for (auto body:kBodies) {
        require(body.address+body.size<=bytes.size(),"Body outside source slice");
        require(digest(bytes.data()+body.address,body.size)==body.hash,"Original body hash mismatch");
        for(auto p=round(body.address);p<=round(body.address+body.size-1);p+=page_)code.insert(p);
      }
      const std::array<std::size_t,8> hooks{0x12990,0x3ce0,0x12de0,0xc650,0x9fe0,0x187314,0x1875e4,0x1872c0};
      for(auto hook:hooks)code.insert(round(hook));
      for(auto p:code)protect(p,PROT_READ|PROT_WRITE);
      for(auto body:kBodies)std::memcpy(base_+body.address,bytes.data()+body.address,body.size);
      for(auto hook:{0x12990,0x12de0,0xc650,0x9fe0})trampoline(hook,reinterpret_cast<void*>(&replayNoOp));
      trampoline(0x3ce0,reinterpret_cast<void*>(&replaySetjmpSuccess));
      trampoline(0x187314,reinterpret_cast<void*>(static_cast<double(*)(double)>(&std::exp)));
      trampoline(0x1875e4,reinterpret_cast<void*>(static_cast<double(*)(double)>(&std::sin)));
      trampoline(0x1872c0,reinterpret_cast<void*>(static_cast<double(*)(double)>(&std::cos)));
      for(auto p:code) {protect(p,PROT_READ|PROT_EXEC);sys_icache_invalidate(base_+p,page_);}
      protect(round(0x1a3cd4),PROT_READ|PROT_WRITE);
      // Literal zero remains at its original relative address.
      require(std::memcmp(bytes.data()+0x1a3cd4,"\0\0\0\0",4)==0,"Zero literal changed");
      protect(round(0x230d7c),PROT_READ|PROT_WRITE);
      write(0x230d7c,kFloor);
      write(0x230e38,reinterpret_cast<void*>(base_+0x288c));
      for(auto [offset,length]:std::array<std::pair<std::size_t,std::size_t>,2>{{{0x18a080,72},{0x20bd00,64}}}) {
        protect(round(offset),PROT_READ|PROT_WRITE);
        std::memcpy(base_+offset,bytes.data()+offset,length);
      }
      for(auto body:kBodies)require(digest(base_+body.address,body.size)==body.hash,"Mapped body changed");
    }catch(...){munmap(base_,size_);base_=nullptr;throw;}
  }
  ~Replay(){if(base_)munmap(base_,size_);}
  Replay(const Replay&)=delete;
  void run(State& state,const float* input,float* output,std::int32_t frames,float limit) {
    alignas(16) std::array<std::byte,0x1b8> object{};
    alignas(16) std::array<std::byte,0x48> host{};
    put(host,0x40,limit);
    put(object,0xc8,host.data());
    put(object,0x128,state.current);
    put(object,0x138,state.target);
    put(object,0x178,state.blockStart);
    put(object,0x188,state.increment);
    put(object,0x1a8,state.meters);
    using Function=void(*)(void*,const float*,float*,std::int32_t);
    reinterpret_cast<Function>(base_+0x5b400)(object.data(),input,output,frames);
    get(object,0x128,state.current);
    get(object,0x138,state.target);
    get(object,0x178,state.blockStart);
    get(object,0x188,state.increment);
    get(object,0x1a8,state.meters);
  }
  std::int32_t parameter(Controls&controls,State&state,std::int32_t index,
                         std::int32_t value,std::uint32_t flags,std::int32_t maximum) {
    require(index>=0 && index<2 && !(flags&~3u),"Replay parameter subset exceeded");
    alignas(16) std::array<std::byte,0x1b8>object{};
    alignas(16) std::array<std::byte,0x960>form{};
    alignas(16) std::array<std::array<std::byte,0x420>,2>knobs{};
    put(object,0xc0,form.data());
    for(std::size_t i=0;i<2;++i) {
      put(form,0x950+8*i,knobs[i].data());
      put(knobs[i],0x40c,maximum);
    }
    put(object,0x138,state.target);
    put(object,0x158,controls.panUnit);
    put(object,0x160,controls.panSigned);
    put(object,0x168,controls.volumeUnit);
    put(object,0x170,controls.panScale);
    put(object,0x198,controls.normalization);
    put(object,0x1a0,controls.raw);
    using Function=std::int32_t(*)(void*,std::int32_t,std::int32_t,std::uint32_t);
    const auto result=reinterpret_cast<Function>(base_+0x5ade0)(object.data(),index,value,flags);
    get(object,0x138,state.target);
    get(object,0x158,controls.panUnit);
    get(object,0x160,controls.panSigned);
    get(object,0x168,controls.volumeUnit);
    get(object,0x170,controls.panScale);
    get(object,0x1a0,controls.raw);
    return result;
  }
 private:
  template<std::size_t N,class T>static void put(std::array<std::byte,N>&a,std::size_t p,const T&v){std::memcpy(a.data()+p,&v,sizeof(v));}
  template<std::size_t N,class T>static void get(const std::array<std::byte,N>&a,std::size_t p,T&v){std::memcpy(&v,a.data()+p,sizeof(v));}
  template<class T>void write(std::size_t p,const T&v){std::memcpy(base_+p,&v,sizeof(v));}
  void trampoline(std::size_t offset,void*function) {
    // LDR X16, literal +8; BR X16; absolute process-local function address.
    write(offset,std::uint32_t{0x58000050});write(offset+4,std::uint32_t{0xd61f0200});write(offset+8,function);
  }
  std::size_t round(std::size_t p)const{return p-p%page_;}
  void protect(std::size_t p,int mode){require(mprotect(base_+p,page_,mode)==0,"Cannot protect replay page");}
  std::uint8_t*base_=nullptr;
  std::size_t page_=0,size_=0;
};
template<class T>bool identical(const T&a,const T&b){return std::memcmp(&a,&b,sizeof(T))==0;}
void equal(const State&a,const State&b,std::size_t test) {
  for(auto name:{"current","target","start","increment","meters"}) {
    const bool pass=std::string(name)=="current"?identical(a.current,b.current):
      std::string(name)=="target"?identical(a.target,b.target):
      std::string(name)=="start"?identical(a.blockStart,b.blockStart):
      std::string(name)=="increment"?identical(a.increment,b.increment):identical(a.meters,b.meters);
    if(!pass && std::string(name)=="target")for(std::size_t i=0;i<4;++i)
      std::cerr<<"target "<<i<<" native="<<std::hexfloat<<a.target[i]<<" model="<<b.target[i]<<'\n';
    require(pass,"State mismatch in "+std::string(name)+" case "+std::to_string(test));
  }
}
}

int main(int argc,char**argv) {
 try {
  require(argc==3,"Usage: test_balance_dsp original-universal-dylib verified-arm64-slice");
  const auto original=read(argv[1]);const auto slice=read(argv[2]);
  require(digest(original.data(),original.size())==kSourceHash,"Installed universal target hash mismatch");
  require(digest(slice.data(),slice.size())==kSliceHash,"Arm64 slice hash mismatch");
  Replay replay(slice);
  std::mt19937 generator(0x0b41aace);std::uniform_real_distribution<float>random(-3,3);
  const std::array<std::int32_t,20> sizes{0,1,2,3,4,7,8,9,15,16,17,31,32,33,63,64,65,257,512,1024};
  const std::array<float,6>limits{0,0x1p-24f,0.0001f,0.01f,1,8};
  std::size_t cases=0,framesTested=0;
  for(std::size_t trial=0;trial<4800;++trial) {
    const auto frames=sizes[trial%sizes.size()];const auto limit=limits[trial%limits.size()];
    State initial{};
    for(std::size_t j=0;j<4;++j) {initial.current[j]=random(generator);initial.target[j]=random(generator);}
    if(trial%7==0)initial.target={initial.current[0],initial.current[1],initial.current[2],initial.current[3]};
    if(trial%7==1){initial.current[2]=initial.current[3]=0;initial.target[2]=initial.target[3]=0;}
    if(trial%7==2){initial.current.fill(0);initial.target.fill(0);}
    if(trial%7==3){initial.current={1,1,0,0};initial.target={0,0,0,0};}
    if(trial%7==4){initial.current={0,0,1,1};initial.target={1,1,0,0};}
    if(trial%7==5){initial.current.fill(0x1p-25f);initial.target.fill(0);}
    if(trial%7==6){initial.current={-0.0f,0,0,-0.0f};initial.target={-0.0,0,0,-0.0};}
    State actual=initial,expected=initial;
    for(std::size_t block=0;block<4;++block) {
      const std::size_t shift=trial%2; // Exercise both 16-byte aligned and 4-byte offset buffers.
      std::vector<float> input(2*static_cast<std::size_t>(frames)+8),a(input.size(),42),b(input.size(),42);
      for(auto&value:input)value=random(generator);
      if(trial%11==0)for(auto&value:input)value=-std::fabs(value);
      if(trial%13==0) {a=input;b=input;}
      replay.run(actual,trial%13==0?a.data()+shift:input.data()+shift,a.data()+shift,frames,limit);
      veggie_loops::balance::process(expected,trial%13==0?b.data()+shift:input.data()+shift,b.data()+shift,frames,limit,kFloor);
      equal(actual,expected,cases);
      require(std::memcmp(a.data(),b.data(),a.size()*sizeof(float))==0,"Output mismatch case "+std::to_string(cases));
      ++cases;framesTested+=static_cast<std::size_t>(frames);
      if(block==2)for(auto&value:actual.target)value=random(generator);
      if(block==2)expected.target=actual.target;
    }
  }
  std::size_t parameterCases=0;
  for(auto maximum:{256,320,640})for(int pan=-128;pan<=128;++pan)for(int volume=0;volume<=maximum;volume+=16) {
    Controls actual{},expected{};State nativeState{},modelState{};
    for(auto [index,value,flags]:std::array<std::array<std::int32_t,3>,4>{{{0,pan,1},{1,volume,1},{0,999,2},{1,-999,2}}}) {
      const auto nativeResult=replay.parameter(actual,nativeState,index,value,static_cast<std::uint32_t>(flags),maximum);
      const auto modelResult=veggie_loops::balance::parameter(expected,modelState,index,value,static_cast<std::uint32_t>(flags),maximum);
      require(nativeResult==modelResult,"Parameter result mismatch case "+std::to_string(parameterCases));
      require(actual.raw==expected.raw && identical(actual.panUnit,expected.panUnit) &&
        identical(actual.panSigned,expected.panSigned) && identical(actual.volumeUnit,expected.volumeUnit) &&
        identical(actual.panScale,expected.panScale),"Control state mismatch case "+std::to_string(parameterCases));
      equal(nativeState,modelState,parameterCases);
      ++parameterCases;
    }
  }
  std::cout<<"{\"status\":\"passed\",\"scope\":\"bounded native Balance DSP and numerical parameter callbacks\",\"cases\":"<<cases
    <<",\"parameter_cases\":"<<parameterCases<<",\"frames\":"<<framesTested<<",\"mapped_original_routines\":11,\"bit_exact\":true,\"full_plugin_recompiled\":false}\n";
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}
}

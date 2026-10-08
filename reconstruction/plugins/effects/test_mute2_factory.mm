#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This measured factory layout test requires macOS arm64.
#endif
#include "mute2_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <bit>
#include <cmath>
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
void require(bool value,const char* text){if(!value)throw std::runtime_error(text);}
template<class T>T load(const void* p,size_t offset){T value;std::memcpy(&value,static_cast<const char*>(p)+offset,sizeof(T));return value;}
template<class F>F method(void* p,size_t offset){return reinterpret_cast<F>(load<void**>(p,0)[offset/8]);}
std::string hash(const char* path){
  std::ifstream file(path,std::ios::binary);require(file.good(),"Missing inspected source");
  std::vector<uint8_t> bytes{std::istreambuf_iterator<char>(file),{}};require(bytes.size()<=UINT32_MAX,"Oversize input");
  std::array<uint8_t,32> digest{};CC_SHA256(bytes.data(),static_cast<CC_LONG>(bytes.size()),digest.data());
  std::ostringstream out;for(auto b:digest)out<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(b);return out.str();
}
std::array<void*,96> hostMethods{};std::array<void*,32> pathMethods{};
struct Object{void** methods;};Object pathObject{pathMethods.data()};const char* privatePath=nullptr;
extern "C" intptr_t noOperation(){return 0;}
extern "C" intptr_t dispatch(void*,intptr_t,intptr_t id,intptr_t,intptr_t){
  if(id==71)return reinterpret_cast<intptr_t>(&pathObject);
  if(id==29)return reinterpret_cast<intptr_t>(privatePath);return 0;
}
struct Stream{void** methods;std::array<uint8_t,12> bytes{};size_t cursor=0,calls=0;};
extern "C" intptr_t readStream(Stream* s,void* output,uint32_t size,void*){
  require(s->cursor+size<=s->bytes.size(),"Unexpected original read size");std::memcpy(output,s->bytes.data()+s->cursor,size);s->cursor+=size;++s->calls;return 0;
}
extern "C" intptr_t writeStream(Stream* s,const void* input,uint32_t size,void*){
  require(s->cursor+size<=s->bytes.size(),"Unexpected original write size");std::memcpy(s->bytes.data()+s->cursor,input,size);s->cursor+=size;++s->calls;return 0;
}
void word(uint8_t* p,uint32_t value){for(size_t i=0;i<4;++i)p[i]=static_cast<uint8_t>(value>>(8*i));}
}
int main(int argc,char** argv){
 @autoreleasepool {
  try{
    require(argc==4,"Usage: test_mute2_factory <installed Mute 2 dylib> <private path/> <rebuilt C ABI dylib>");
    require(hash(argv[1])=="79e0f73c536f4545186cea477e39fd2f4a807a57853e0af3018379a3d8b3ea9a","Installed source identity mismatch");
    [NSApplication sharedApplication];privatePath=argv[2];
    hostMethods.fill(reinterpret_cast<void*>(&noOperation));pathMethods.fill(reinterpret_cast<void*>(&noOperation));hostMethods[0xc8/8]=reinterpret_cast<void*>(&dispatch);
    alignas(16)std::array<std::byte,512> host{};auto* table=hostMethods.data();std::memcpy(host.data(),&table,8);
    void* source=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(source,"Cannot load original Mute 2");
    void* rebuilt=dlopen(argv[3],RTLD_NOW|RTLD_LOCAL);require(rebuilt,"Cannot load independent Mute 2");
    const auto bind=[&](const char* name){void* symbol=dlsym(rebuilt,name);require(symbol,"Missing reconstructed API");return symbol;};
    auto create=reinterpret_cast<decltype(&vl_mute2_create)>(bind("vl_mute2_create"));
    auto destroy=reinterpret_cast<decltype(&vl_mute2_destroy)>(bind("vl_mute2_destroy"));
    auto parameter=reinterpret_cast<decltype(&vl_mute2_parameter)>(bind("vl_mute2_parameter"));
    auto render=reinterpret_cast<decltype(&vl_mute2_render)>(bind("vl_mute2_render"));
    auto save=reinterpret_cast<decltype(&vl_mute2_save_state)>(bind("vl_mute2_save_state"));
    auto restore=reinterpret_cast<decltype(&vl_mute2_restore_state)>(bind("vl_mute2_restore_state"));
    auto factory=reinterpret_cast<void*(*)(void*,intptr_t)>(dlsym(source,"CreatePlugInstance"));require(factory,"Missing original factory");
    void* native=factory(host.data(),0x564c);require(native,"Original factory failed");auto* clone=create();require(clone,"Reconstructed factory failed");
    using Parameter=int32_t(*)(void*,int32_t,int32_t,uint32_t);using Render=void(*)(void*,const float*,float*,int32_t);using State=void(*)(void*,void*,int32_t);
    const auto nativeParameter=method<Parameter>(native,0xf8);const auto nativeRender=method<Render>(native,0x100);const auto nativeState=method<State>(native,0xe0);
    void* form=load<void*>(native,0xc0);
    for(int i=0;i<2;++i){void* knob=load<void*>(form,0x930+8*i);require(load<int32_t>(knob,0x408)==0 && load<int32_t>(knob,0x40c)==1024 && load<int32_t>(knob,0x410)==512,"Unexpected source range/default");
      require(load<double>(knob,0x430)==1.0/1024.0,"Unexpected original normalized scale");int32_t value=0;require(parameter(clone,i,0,2,&value) && value==nativeParameter(native,i,0,2) && value==512,"Default parameter mismatch");}
    std::array<void*,5> streamMethods{};streamMethods[3]=reinterpret_cast<void*>(&readStream);streamMethods[4]=reinterpret_cast<void*>(&writeStream);Stream stream{streamMethods.data()};
    size_t parameterCases=0,stateCases=0,renderCases=0,frames=0;
    const auto compareSave=[&]{stream.cursor=stream.calls=0;nativeState(native,&stream,1);std::array<uint8_t,12> bytes{};require(save(clone,bytes.data(),bytes.size()),"Rebuilt save rejected");require(stream.calls==2 && stream.cursor==12 && stream.bytes==bytes,"State serialization differs");};compareSave();
    const auto change=[&](int32_t index,int32_t value,uint32_t flags){const auto actual=nativeParameter(native,index,value,flags);int32_t model=0;require(parameter(clone,index,value,flags&35u,&model) && model==actual,"Numerical parameter mismatch");
      require(nativeParameter(native,index,0,2)==model,"Original parameter get mismatch");void* knob=load<void*>(form,0x930+8*index);if(flags&16)require(load<int32_t>(knob,0x410)==model,"Real original control differs");++parameterCases;};
    std::mt19937 random(0x564c4d32);const std::array<int32_t,20> lengths{0,1,2,3,4,7,8,9,15,16,17,31,32,33,63,64,65,257,512,1024};
    const auto compareRender=[&](int32_t length,bool alias,bool offset){
      std::vector<float> input(2*length+12),actual(input.size(),42.0f),model(input.size(),42.0f);
      for(size_t i=0;i<input.size();++i)input[i]=i%11==0?std::bit_cast<float>((i%2)?0x80000000u:0u):float(int32_t(random()%4097)-2048)/1024.0f;
      if(alias){actual=input;model=input;}
      const size_t start=offset?1:0;
      nativeRender(native,alias?actual.data()+start:input.data()+start,actual.data()+start,length);
      require(render(clone,alias?model.data()+start:input.data()+start,model.data()+start,length),"Reconstructed render rejected");
      require(std::memcmp(actual.data(),model.data(),actual.size()*sizeof(float))==0,"Audio or guard bytes differ");++renderCases;frames+=length;
    };
    // Exhaust both recovered native integer ranges, including every threshold.
    for(int index=0;index<2;++index)for(int value=0;value<=1024;++value){
      change(index,value,17);if(index==0)change(1,int32_t(random()%1025),17);else change(0,value%3==0?0:511,17);
      compareRender(lengths[value%lengths.size()],value%2!=0,value%3!=0);compareSave();
    }
    // Exercise nearest-even normalization at exact ties and either adjacent MIDI unit.
    for(int index=0;index<2;++index)for(int step=0;step<1024;++step){const int32_t half=step*1048576+524288;
      for(int delta=-1;delta<=1;++delta)change(index,half+delta,49);compareRender(lengths[step%lengths.size()],step%2!=0,step%3!=0);
    }
    for(int index=0;index<2;++index){change(index,0,49);change(index,0x40000000,49);}
    for(size_t i=0;i<512;++i){word(stream.bytes.data(),uint32_t(i%2));word(stream.bytes.data()+4,random()%1025);word(stream.bytes.data()+8,random()%1025);
      stream.cursor=stream.calls=0;nativeState(native,&stream,0);require(stream.cursor==12 && stream.calls==2,"Original restore framing differs");require(restore(clone,stream.bytes.data(),12),"Rebuilt valid restore rejected");
      for(int32_t p=0;p<2;++p){int32_t value=0;require(parameter(clone,p,0,2,&value) && value==nativeParameter(native,p,0,2),"Restored parameter differs");}compareRender(lengths[i%lengths.size()],i%2!=0,i%3!=0);compareSave();++stateCases;
    }
    // Validate own rejection contract without implying malformed original equivalence.
    std::array<uint8_t,12> before{},after{};require(save(clone,before.data(),12),"Own save failed");auto bad=before;word(bad.data()+4,1025);require(!restore(clone,bad.data(),12),"Invalid range accepted");
    bad=before;word(bad.data(),2);require(!restore(clone,bad.data(),12) && save(clone,after.data(),12) && before==after,"Invalid restore changed state");
    int32_t ignored=0;require(!parameter(clone,-1,0,1,&ignored) && !parameter(clone,0,-1,1,&ignored) && !parameter(clone,0,0x40000001,33,&ignored),"Invalid automation accepted");
    std::array<float,8> overlap{};require(!render(clone,overlap.data(),overlap.data()+1,2),"Partial overlap accepted");
    destroy(clone);method<void(*)(void*)>(native,0xc8)(native);dlclose(rebuilt);dlclose(source);
    std::cout<<"{\"status\":\"passed\",\"actual_original_factory_created_and_destroyed\":true,\"compiled_c_abi_dylib_compared\":true,\"parameter_and_control_cases\":"<<parameterCases
      <<",\"valid_state_restore_cases\":"<<stateCases<<",\"render_cases\":"<<renderCases<<",\"stereo_frames\":"<<frames<<",\"signed_zero_compared\":true,\"full_plugin_equivalence\":false}\n";
  }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
 }
}

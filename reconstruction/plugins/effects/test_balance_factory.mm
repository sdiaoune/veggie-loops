#import <Cocoa/Cocoa.h>
#if !defined(__APPLE__) || !defined(__aarch64__)
#error This measured factory layout test requires macOS arm64.
#endif
#include "balance_dsp.hpp"
#include "balance_plugin.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <array>
#include <cstdint>
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
using veggie_loops::balance::State;
using veggie_loops::balance::Controls;
void require(bool value,const std::string&message){if(!value)throw std::runtime_error(message);}
template<class T>T load(const void*object,std::size_t offset){T result;std::memcpy(&result,static_cast<const char*>(object)+offset,sizeof(T));return result;}
template<class F>F method(void*object,std::size_t offset){return reinterpret_cast<F>(load<void**>(object,0)[offset/8]);}
std::string sourceHash(const char*path){
  std::ifstream input(path,std::ios::binary);require(input.good(),"Missing inspected plugin");
  std::vector<unsigned char>bytes{std::istreambuf_iterator<char>(input),std::istreambuf_iterator<char>()};
  require(bytes.size()<=UINT32_MAX,"Hash input too large");
  std::array<unsigned char,32>hash{};CC_SHA256(bytes.data(),static_cast<CC_LONG>(bytes.size()),hash.data());
  std::ostringstream result;for(auto byte:hash)result<<std::hex<<std::setfill('0')<<std::setw(2)<<unsigned(byte);return result.str();
}
struct Object{void**vmt;};
std::array<void*,96>hostVmt{};std::array<void*,32>pathVmt{};
Object pathObject{pathVmt.data()};
const char*privatePath=nullptr;
std::vector<std::intptr_t>hostCalls;
extern "C" std::intptr_t noOperation(){return 0;}
extern "C" std::intptr_t dispatch(void*,std::intptr_t,std::intptr_t id,std::intptr_t,std::intptr_t){
  hostCalls.push_back(id);
  if(id==71)return reinterpret_cast<std::intptr_t>(&pathObject);
  if(id==29)return reinterpret_cast<std::intptr_t>(privatePath);
  return 0;
}
struct Stream{void**vmt;std::array<std::byte,8>data{};unsigned calls=0;};
extern "C" std::intptr_t streamRead(Stream*s,void*buffer,std::uint32_t size,void*){
  require(size==s->data.size(),"Unexpected native state length");std::memcpy(buffer,s->data.data(),size);++s->calls;return 0;
}
extern "C" std::intptr_t streamWrite(Stream*s,const void*buffer,std::uint32_t size,void*){
  require(size==s->data.size(),"Unexpected native state length");std::memcpy(s->data.data(),buffer,size);++s->calls;return 0;
}
State observedState(void*object){
  State state;state.current=load<decltype(state.current)>(object,0x128);
  state.target=load<decltype(state.target)>(object,0x138);
  state.blockStart=load<decltype(state.blockStart)>(object,0x178);
  state.increment=load<decltype(state.increment)>(object,0x188);
  state.meters=load<decltype(state.meters)>(object,0x1a8);return state;
}
void compareState(const State&a,const State&b){
  const auto equal=[](const auto&a,const auto&b){return std::memcmp(a.data(),b.data(),sizeof(a))==0;};
  const bool same=equal(a.current,b.current) && equal(a.target,b.target) &&
    equal(a.blockStart,b.blockStart) && equal(a.increment,b.increment) && equal(a.meters,b.meters);
  if(!same) {
    for(std::size_t i=0;i<4;++i)std::cerr<<"lane "<<i<<" current "<<std::hexfloat<<a.current[i]<<'/'<<b.current[i]
      <<" target "<<a.target[i]<<'/'<<b.target[i]<<" start "<<a.blockStart[i]<<'/'<<b.blockStart[i]
      <<" step "<<a.increment[i]<<'/'<<b.increment[i]<<'\n';
  }
  require(same,"Actual plugin state differs from model");
}
}

int main(int argc,char**argv){
 @autoreleasepool {
  try {
   require(argc==4,"Usage: test_balance_factory <inspected installed plugin> <private probe data directory/> <rebuilt C ABI dylib>");
   require(sourceHash(argv[1])=="525e96102a4eddc89de484ec3bc6a3c92788738c1dc50b5a5fa71bbd994e77ef","Inspected source hash mismatch");
   privatePath=argv[2];[NSApplication sharedApplication];
   hostVmt.fill(reinterpret_cast<void*>(&noOperation));pathVmt.fill(reinterpret_cast<void*>(&noOperation));
   hostVmt[0xc8/8]=reinterpret_cast<void*>(&dispatch);
   alignas(16)std::array<std::byte,512>host{};void**hostMethods=hostVmt.data();std::memcpy(host.data(),&hostMethods,8);
   void*library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);require(library!=nullptr,"Cannot load installed source plugin");
   void*rebuilt=dlopen(argv[3],RTLD_NOW|RTLD_LOCAL);require(rebuilt!=nullptr,"Cannot load rebuilt C ABI library");
   const auto bind=[&](const char*name){void*symbol=dlsym(rebuilt,name);require(symbol!=nullptr,std::string("Missing rebuilt symbol ")+name);return symbol;};
   const auto cloneCreate=reinterpret_cast<decltype(&vl_balance_create)>(bind("vl_balance_create"));
   const auto cloneDestroy=reinterpret_cast<decltype(&vl_balance_destroy)>(bind("vl_balance_destroy"));
   const auto cloneParameter=reinterpret_cast<decltype(&vl_balance_parameter)>(bind("vl_balance_parameter"));
   const auto cloneRate=reinterpret_cast<decltype(&vl_balance_set_sample_rate)>(bind("vl_balance_set_sample_rate"));
   const auto cloneResume=reinterpret_cast<decltype(&vl_balance_resume)>(bind("vl_balance_resume"));
   const auto cloneRender=reinterpret_cast<decltype(&vl_balance_render)>(bind("vl_balance_render"));
   const auto cloneMeters=reinterpret_cast<decltype(&vl_balance_get_meters)>(bind("vl_balance_get_meters"));
   const auto cloneSave=reinterpret_cast<decltype(&vl_balance_save_state)>(bind("vl_balance_save_state"));
   const auto cloneRestore=reinterpret_cast<decltype(&vl_balance_restore_state)>(bind("vl_balance_restore_state"));
   auto*clone=cloneCreate();require(clone!=nullptr,"Rebuilt factory failed");
   using Create=void*(*)(void*,std::intptr_t);auto create=reinterpret_cast<Create>(dlsym(library,"CreatePlugInstance"));require(create!=nullptr,"Missing original factory");
   void*object=create(host.data(),42);require(object!=nullptr,"Original factory failed");
   using Parameter=std::int32_t(*)(void*,std::int32_t,std::int32_t,std::uint32_t);
   using Dispatcher=std::intptr_t(*)(void*,std::intptr_t,std::intptr_t,std::intptr_t);
   using Render=void(*)(void*,const float*,float*,std::int32_t);
   using SaveRestore=void(*)(void*,void*,std::int32_t);
   const auto parameter=method<Parameter>(object,0xf8);
   const auto dispatcher=method<Dispatcher>(object,0xd0);
   const auto render=method<Render>(object,0x100);
   const auto saveRestore=method<SaveRestore>(object,0xe0);
   void*form=load<void*>(object,0xc0);
   for(int i=0;i<2;++i){void*knob=load<void*>(form,0x950+8*i);
     require(load<int>(knob,0x408)==(i==0?-128:0) && load<int>(knob,0x40c)==(i==0?128:320) &&
       parameter(object,i,0,2)==(i==0?0:256),"Factory range/default changed");}
   Controls controls;State expected;
   veggie_loops::balance::parameter(controls,expected,0,0,1,320);
   veggie_loops::balance::parameter(controls,expected,1,256,1,320);
   compareState(observedState(object),expected);
   std::array<void*,5>streamVmt{};streamVmt[3]=reinterpret_cast<void*>(&streamRead);streamVmt[4]=reinterpret_cast<void*>(&streamWrite);
   Stream stream{streamVmt.data()};saveRestore(object,&stream,1);
   require(stream.calls==1 && std::memcmp(stream.data.data(),controls.raw.data(),8)==0,"Original state save mismatch");
   std::array<std::byte,8>cloneBytes{};
   require(cloneSave(clone,cloneBytes.data(),8) && cloneBytes==stream.data,"Rebuilt initial state differs");
   std::mt19937 random(0x564c4241);std::size_t cases=0,frames=0,stateCases=0;
   const std::array<std::int32_t,12>lengths{0,1,2,3,7,8,9,16,17,63,128,257};
   for(std::size_t trial=0;trial<1024;++trial){
     const auto index=static_cast<int>(trial%2);
     const auto normalized=static_cast<std::int32_t>(random()&0x3fffffffu);
     const auto flags=trial%3==0?49u:17u; // Update value/control, optionally normalize MIDI.
     const auto value=flags&32?normalized:(index==0?int(random()%257)-128:int(random()%321));
     const auto a=parameter(object,index,value,flags);
     const auto b=veggie_loops::balance::parameter(controls,expected,index,value,flags,320);
     require(a==b,"Real parameter result differs");
     int32_t cloneResult=0;
     require(cloneParameter(clone,index,value,flags&35u,&cloneResult) && cloneResult==a,"Rebuilt parameter result differs");
     void*knob=load<void*>(form,0x950+8*index);require(load<int>(knob,0x410)==b,"Native control value differs");
     compareState(observedState(object),expected);
     ++cases;
     if(trial%5==0){
       saveRestore(object,&stream,1);require(std::memcmp(stream.data.data(),controls.raw.data(),8)==0,"State payload differs");
       const std::array<int,2>restored{int(random()%257)-128,int(random()%321)};
       std::memcpy(stream.data.data(),restored.data(),8);saveRestore(object,&stream,0);
       require(cloneRestore(clone,stream.data.data(),8),"Rebuilt state restore failed");
       for(int p=0;p<2;++p)veggie_loops::balance::parameter(controls,expected,p,restored[p],1,320);
       compareState(observedState(object),expected);++stateCases;
     }
     const auto length=lengths[trial%lengths.size()];std::vector<float>input(2*length+8),actual(input.size(),42),model(input.size(),42);
     for(auto&v:input)v=float(int(random()%2049)-1024)/1024;
     const auto audio=load<void*>(object,0xc8);const auto limit=load<float>(audio,0x40);
     render(object,input.data(),actual.data(),length);
     veggie_loops::balance::process(expected,input.data(),model.data(),length,limit,0x1p-24f);
     require(std::memcmp(actual.data(),model.data(),actual.size()*sizeof(float))==0,"Real callback output differs");
     auto cloneOutput=std::vector<float>(input.size(),42);
     require(cloneRender(clone,input.data(),cloneOutput.data(),length) &&
       std::memcmp(actual.data(),cloneOutput.data(),actual.size()*sizeof(float))==0,"Rebuilt shared library audio differs");
     float left=0,right=0;require(cloneMeters(clone,&left,&right),"Rebuilt meters failed");
     const auto nativeMeters=observedState(object).meters;
     require(std::memcmp(&left,&nativeMeters[0],4)==0 && std::memcmp(&right,&nativeMeters[1],4)==0,"Rebuilt meters differ");
     compareState(observedState(object),expected);frames+=length;
     if(trial%13==0){dispatcher(object,2,0,0);cloneResume(clone);for(std::size_t i=0;i<4;++i)expected.current[i]=static_cast<float>(expected.target[i]);compareState(observedState(object),expected);}
     if(trial%19==0){const std::array<int,6>rates{8000,22050,44100,48000,96000,192000};const auto rate=rates[(trial/19)%rates.size()];
       dispatcher(object,4,0,rate);require(cloneRate(clone,rate),"Rebuilt sample rate failed");}
   }
   cloneDestroy(clone);dlclose(rebuilt);
   method<void(*)(void*)>(object,0xc8)(object);dlclose(library);
   std::cout<<"{\"status\":\"passed\",\"actual_source_factory_created_and_destroyed\":true,\"parameter_and_control_cases\":"<<cases
     <<",\"preset_state_restore_cases\":"<<stateCases<<",\"render_frames\":"<<frames<<",\"real_vcl_controls\":true,\"native_host_dispatcher_calls\":"<<hostCalls.size()
     <<",\"rebuilt_c_abi_dylib_loaded_and_compared\":true,\"rebuilt_plugin_loaded_in_fl_studio\":false,\"full_plugin_equivalence\":false}\n";
  }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}
 }
}

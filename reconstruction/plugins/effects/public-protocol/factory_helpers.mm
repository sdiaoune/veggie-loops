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

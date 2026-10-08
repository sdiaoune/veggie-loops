#pragma once
#include <cstddef>
#include <cstdint>

// Independent declaration of the inspected arm64 FL C++ plugin boundary.
// Function order and field offsets are protocol facts, not copied SDK code.
// This experimental wrapper is separately tested through unchanged engine
// adapters. Loading it into the FL Studio application is a further gate.
// Numerical preconditions match balance_plugin.h: finite stereo buffers,
// 0..1024 frames, 8..192 kHz, pan -128..128 and volume 0..320. No editor or
// hint callback is implemented; flags 16/4 have no UI side effects here.
namespace veggie_loops::balance::native {
struct Plugin;
#pragma pack(push,4)
struct Info {
  std::int32_t version;
  const char* longName;
  const char* shortName;
  std::int32_t flags,parameterCount,polyphony,outputControls,outputVoices;
  std::int32_t reserved[30];
};
#pragma pack(pop)
static_assert(offsetof(Info,flags)==20 && offsetof(Info,parameterCount)==24);
struct Stream {
  void** functions;
};
struct Functions {
  void (*destroy)(Plugin*);
  std::intptr_t (*dispatch)(Plugin*,std::intptr_t,std::intptr_t,std::intptr_t);
  void (*idle)(Plugin*);
  void (*state)(Plugin*,Stream*,std::int32_t);
  void (*name)(Plugin*,std::int32_t,std::int32_t,std::int32_t,char*);
  std::int32_t (*event)(Plugin*,std::int32_t,std::int32_t,std::int32_t);
  std::int32_t (*parameter)(Plugin*,std::int32_t,std::int32_t,std::int32_t);
  void (*effect)(Plugin*,const float*,float*,std::int32_t);
  void (*generator)(Plugin*,float*,std::int32_t&);
  std::intptr_t (*voice)(Plugin*,void*,std::intptr_t);
  void (*release)(Plugin*,std::intptr_t);
  void (*kill)(Plugin*,std::intptr_t);
  std::int32_t (*voiceEvent)(Plugin*,std::intptr_t,std::intptr_t,std::intptr_t,std::intptr_t);
  std::int32_t (*voiceRender)(Plugin*,std::intptr_t,float*,std::int32_t&);
  void (*tick)(Plugin*);
  void (*midiTick)(Plugin*);
  void (*midi)(Plugin*,std::int32_t&);
  void (*message)(Plugin*,std::intptr_t);
  std::int32_t (*outputEvent)(Plugin*,std::intptr_t,std::intptr_t,std::intptr_t,std::intptr_t);
  void (*outputKill)(Plugin*,std::intptr_t);
  void (*completeDestructor)(Plugin*);
  void (*deletingDestructor)(Plugin*);
};
static_assert(offsetof(Functions,parameter)==0x30 && offsetof(Functions,effect)==0x38);
struct Plugin {
  const Functions* functions;
  std::intptr_t hostTag;
  const Info* info;
  std::intptr_t editor;
  std::int32_t mono;
  std::int32_t reserved[32];
};
static_assert(offsetof(Plugin,hostTag)==8 && offsetof(Plugin,info)==16);
static_assert(offsetof(Plugin,editor)==24 && sizeof(Plugin)==168);
}

extern "C" veggie_loops::balance::native::Plugin*
CreatePlugInstance(void* host,std::intptr_t hostTag);

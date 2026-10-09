#pragma once
// Independent prepared five-group modulation combination. Native object
// lifecycle, tick production, filtering and audio pipeline routing are absent.
#include "three_osc_envelope.hpp"
#include <array>
namespace veggie_loops::three_osc::modulation {
using Configurations=std::array<envelope::Configuration,5>;
struct State {
  std::array<envelope::State,5> groups{};
  std::int32_t declickPosition=-1,waitFrames=0;
  std::uint8_t released=0;
};
inline void initialize(const Configurations& cfg,State& state) {
  for(size_t i=0;i<5;++i)envelope::initialize(state.groups[i],cfg[i]);
}
// Prepared configuration and initialized-state contracts from the envelope
// module apply. Each table has16384 readable finite samples in[-1,1]; raw depth
// ranges[-128,128], matching the bounded sine-table native corpus.
// Calls are serial and advance one explicit host tick, without audio rendering.
// Declick position is-1 or nonnegative; waitFrames is nonnegative, released0/1.
inline void step(const Configurations& cfg,State& state) {
  for(size_t i=0;i<5;++i)envelope::step(cfg[i],state.groups[i]);
  auto& g=state.groups;
  g[0].combined=(g[0].lfoValue*cfg[0].lfoDepth)*2.0f;
  g[1].combined=g[1].value*(g[1].lfoValue*cfg[1].lfoDepth+1.0f);
  if(g[1].combined<0)g[1].combined=0;
  g[2].combined=g[2].value*cfg[2].envelopeDepth+g[2].lfoValue*cfg[2].lfoDepth;
  g[3].combined=g[3].value*cfg[3].envelopeDepth+g[3].lfoValue*cfg[3].lfoDepth;
  g[4].combined=g[4].value*float(cfg[4].raw[8])+g[4].lfoValue*float(cfg[4].raw[11]);
  if(g[1].stage==9 && state.declickPosition<0) {state.declickPosition=0;state.waitFrames=0;}
}
inline void release(const Configurations& cfg,State& state) {
  state.released=1;
  for(size_t i=1;i<5;++i)envelope::release(state.groups[i],cfg[i]);
  if(cfg[1].raw[1]==0 && state.declickPosition<0) {state.declickPosition=0;state.waitFrames=0;}
}
// Match the explicit native update condition: newTick or positive initializer
// counter. The caller supplies/restores its own base final pitch each block.
// finalPitch is finite with magnitude<=24000; this helper does not generate
// the clock, clear the initializer counter or render any sample buffer.
inline void tickPitch(const Configurations& cfg,State& state,bool newTick,
                      std::int32_t initializerCounter,float& finalPitch) {
  if(newTick || initializerCounter>0) {step(cfg,state);finalPitch+=state.groups[4].combined;}
}
}

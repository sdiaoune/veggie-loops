#pragma once
// Prepared wrapper-filter activation, slew and one/two-pass routing. Native
// object/context production, editor dispatch and audio voice integration are
// not provided. This adds routing around the separately verified kernels.
#include "three_osc_filter.hpp"
#include "three_osc_voice_output.hpp"
#include <cstring>
namespace veggie_loops::three_osc::filter_routing {
struct State {
  filter::Coefficients coefficients;
  std::array<float,8> secondPass{};
  std::uint8_t doubleOrder=0,active=0;
  std::uint16_t reserved=0;
  std::int32_t initializerCounter=0;
};
static_assert(sizeof(State)==112 && offsetof(State,secondPass)==0x48 && offsetof(State,initializerCounter)==0x6c);
struct Inputs {
  float finalCutoff=0,finalResonance=0,cutoffModulation=0,resonanceModulation=0;
  std::int32_t rawCutoff=256,rawResonance=0;
};
// type0..7; prepared default Context; initial histories are zero (then carry
// forward from successful calls). Raw controls in[0,256], final/mod terms and
// their rounded combined normalized values in[-2,2]. Flags are0/1. Frames in
// [1,4096], source has2*frames finite samples |x|<=1; output is a separate
// 2*frames writable buffer, not overlapping state/source. Gain magnitudes<=1.
// Returns active. An inactive return preserves output. Caller performs its
// own pointer swap/final voice mixing. Initialized positive types begin active.
// Native retained-state replay fixes type, doubleOrder and rate per fixture;
// changing those within a live routed state is outside the current proof.
inline bool process(State& state,const Inputs& inputs,const filter::Context& ctx,
                    const float* source,float* output,std::int32_t frames,float& left,float& right) {
  auto& cfg=state.coefficients;const float previousCutoff=cfg.cutoff;
  const float cutoff=inputs.finalCutoff+float(inputs.rawCutoff)*0x1p-8f;
  const float resonance=inputs.finalResonance+float(inputs.rawResonance)*0x1p-8f;
  const float finalCutoff=cutoff+inputs.cutoffModulation;
  const float finalResonance=resonance+inputs.resonanceModulation;
  if(cfg.type==0) {
    filter::singleCoefficients(finalCutoff,finalResonance,ctx,cfg);
    if(std::bit_cast<uint32_t>(cfg.cutoff)!=0x3f800000u || std::bit_cast<uint32_t>(cfg.resonance)!=0)state.active=1;
  } else if(cfg.type>=1 && cfg.type<=5)filter::biquadCoefficients(finalCutoff,finalResonance,ctx,cfg);
  else if(cfg.type>=6 && cfg.type<=7)filter::specialCoefficients(finalCutoff,finalResonance,ctx,cfg);
  if(state.active) {
    if(cfg.type==0) {
      const float start=state.initializerCounter>0 ? cfg.cutoff:previousCutoff;
      const float maximum=static_cast<float>(double(ctx.rateRatio)*0.001);float increment;
      voice_output::slew(start,maximum,std::bit_cast<uint32_t>(ctx.silenceThreshold),frames,increment,cfg.cutoff);
      filter::singleRender(start,increment,cfg,ctx,source,output,frames);
    } else if(cfg.type>=1 && cfg.type<=5) {
      std::array<float,8> firstPass;std::memcpy(firstPass.data(),cfg.single.data(),32);
      filter::biquadRender(cfg,firstPass,source,output,frames);std::memcpy(cfg.single.data(),firstPass.data(),32);
      if(state.doubleOrder) {
        filter::biquadRender(cfg,state.secondPass,output,output,frames);
        const float compensation=static_cast<float>(1.0-(double(cfg.resonance)*(3.2-double(cfg.cutoff)))*0.046875);
        left=left*compensation;right=right*compensation;
      }
    } else if(cfg.type>=6 && cfg.type<=7) {
      std::array<float,8> firstPass;std::memcpy(firstPass.data(),cfg.single.data(),32);
      filter::specialRender(cfg,firstPass,ctx,source,output,frames);std::memcpy(cfg.single.data(),firstPass.data(),32);
      if(state.doubleOrder) {
        const float original=cfg.resonance;
        cfg.resonance=original+(1.0f-original)*0.25f;
        filter::specialRender(cfg,state.secondPass,ctx,output,output,frames);cfg.resonance=original;
      }
    }
  }
  return state.active!=0;
}
}

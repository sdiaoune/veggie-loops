#pragma once
// Original source for the reviewed per-tick envelope/LFO state machine.
// This isolated primitive is not connected to the wrapper core or DAW. Host
// tick scheduling, coefficient preparation, per-voice modulation/filtering,
// output gain smoothing and integrated-editor GUI remain separate work.
#include <array>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace veggie_loops::three_osc::envelope {
struct Curve { float amount=0,inverse=0,logarithm=0; };
struct Configuration {
  std::array<std::int32_t,17> raw{};
  float attackStep=0,decayStep=0,sustain=0,releaseStep=0,lfoAttackStep=0;
  std::int32_t delayTicks=0,holdTicks=0,lfoDelayTicks=0;
  std::uint32_t lfoPhaseIncrement=0;
  const float* lfoTable=nullptr;
  float envelopeDepth=0,lfoDepth=0;
  std::uint32_t synchronizedLFOPhase=0;
  Curve attack,decay,release;
};
struct State {
  std::uint32_t ticks=0,lfoPhase=0;
  std::int32_t lfoDelay=0,stage=0;
  float position=0,value=0,lfoRamp=0,lfoValue=0,combined=0;
};
static_assert(sizeof(Curve)==12 && sizeof(Configuration)==160 && sizeof(State)==36);
static_assert(offsetof(Configuration,attackStep)==0x44 && offsetof(Configuration,lfoTable)==0x68);
static_assert(offsetof(Configuration,attack)==0x7c && offsetof(Configuration,release)==0x94);
static_assert(offsetof(State,stage)==0xc && offsetof(State,value)==0x14);

// Successful coefficient domain: positive zero, or finite amount with
// |amount|>=2^-23 and finite reciprocal/logarithm. Tiny nonzero floats can
// round |amount|+1 to 1 or overflow the reciprocal; they are outside this
// low-level helper's contract. Positive zero leaves the other fields unchanged.
inline void prepareCurve(Curve& curve,float amount) {
  curve.amount=amount;
  if (amount!=0) {
    curve.inverse=1.0f/std::fabs(amount);
    curve.logarithm=static_cast<float>(std::log(static_cast<double>(std::fabs(amount)+1.0f)));
  }
}
// Musical control range is [-128,128]. Arithmetic replay additionally covers
// [-512,512]; arbitrary Int32 inputs are not a successful-coefficient claim.
inline void prepareRawCurve(Curve& curve,std::int32_t amount) {
  const float normalized=static_cast<float>(amount)*0.0078125f;
  const float magnitude=static_cast<float>(std::exp(static_cast<double>(std::fabs(normalized))*8.75573753930647)-1.0);
  const float sign=amount>0 ? 1.0f : amount<0 ? -1.0f : 0.0f;
  prepareCurve(curve,(sign*magnitude)*0.1f);
}
inline float forward(const Curve& curve,float position) {
  if (std::bit_cast<std::uint32_t>(curve.amount)==0) return position;
  const double value=static_cast<double>(position);
  if (!std::signbit(curve.amount))
    return static_cast<float>(1.0-(std::exp((1.0-value)*static_cast<double>(curve.logarithm))-1.0)*static_cast<double>(curve.inverse));
  return static_cast<float>((std::exp(value*static_cast<double>(curve.logarithm))-1.0)*static_cast<double>(curve.inverse));
}
inline float inverse(const Curve& curve,float value) {
  if (curve.amount==0) return value;
  if (!std::signbit(curve.amount))
    return static_cast<float>(1.0-std::log((1.0-static_cast<double>(value))*static_cast<double>(std::fabs(curve.amount))+1.0)/static_cast<double>(curve.logarithm));
  return static_cast<float>(std::log(static_cast<double>(value)*static_cast<double>(std::fabs(curve.amount))+1.0)/static_cast<double>(curve.logarithm));
}
inline void initialize(State& state,const Configuration& cfg) {
  state.ticks=0;
  if (cfg.delayTicks<1 || cfg.raw[1]==0) {
    state.stage=1;
    if (((cfg.raw[0]&4)!=0 && cfg.raw[1]==0) || (cfg.raw[1]!=0 && cfg.raw[3]==100)) {
      state.position=1.0f;state.stage=cfg.holdTicks<1 ? 3 : 2;
    } else state.position=0;
  } else {state.stage=0;state.position=0;}
  state.value=state.position;state.lfoDelay=cfg.lfoDelayTicks;state.lfoPhase=0;
  state.lfoRamp=0;state.lfoValue=0;state.combined=0;
}
inline void release(State& state,const Configuration& cfg) {
  if (state.stage<7) {state.position=inverse(cfg.release,state.value);state.ticks=0;state.stage=6;}
}
// cfg/state are initialized and finite. Attack/LFO fade steps lie in (0,1],
// decay/release steps in [-1,0), sustain in [0,1], and curves use the musical
// raw range above. Timer values are nonnegative and <=INT_MAX; lfoTable has
// 16384 readable floats. Valid transitions keep inverse arguments positive
// and position in [-1,1]. The function advances one host tick.
inline void step(const Configuration& cfg,State& state) {
  if (cfg.raw[1]!=0) {
    switch (state.stage) {
      case 0:
        ++state.ticks;if (cfg.delayTicks<=std::bit_cast<std::int32_t>(state.ticks)) state.stage=1;break;
      case 1:
        state.position+=cfg.attackStep;
        if (state.position>=1.0f) {state.position=1.0f;if (cfg.holdTicks<1) state.stage=3;else {state.ticks=0;state.stage=2;}}
        state.value=forward(cfg.attack,state.position);break;
      case 2:
        ++state.ticks;if (cfg.holdTicks<=std::bit_cast<std::int32_t>(state.ticks)) state.stage=3;break;
      case 3:
        state.position+=cfg.decayStep;state.value=forward(cfg.decay,state.position);
        if (state.value<=cfg.sustain) {state.value=cfg.sustain;state.position=inverse(cfg.decay,state.value);state.ticks=0;state.stage=4;}
        break;
      case 6:
        state.position+=cfg.releaseStep;state.value=forward(cfg.release,state.position);break;
      default:break;
    }
    if (state.stage>2 && state.value<0x1p-24f) {state.value=0;state.stage=9;}
  }
  if (state.lfoDelay==0) {
    if ((cfg.raw[0]&32)==0) state.lfoPhase+=cfg.lfoPhaseIncrement;
    else state.lfoPhase=cfg.synchronizedLFOPhase;
    state.lfoValue=cfg.lfoTable[state.lfoPhase>>18];
    if (state.lfoRamp!=1.0f) {
      state.lfoRamp+=cfg.lfoAttackStep;if (state.lfoRamp>1.0f) state.lfoRamp=1.0f;
      state.lfoValue*=state.lfoRamp;
    }
  } else --state.lfoDelay;
}
}

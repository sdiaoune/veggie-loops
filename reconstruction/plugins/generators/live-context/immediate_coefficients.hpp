#pragma once
#include "three_osc_envelope.hpp"
// Private preparation timing repair; FRINTX is modeled by rint. The
// accepted shared coefficient helper is immutable. Original reconstruction
// of coefficient preparation with an explicit tick
// context. clockSetting is the measured PPQ argument; actual application
// production remains outside this prepared-domain private helper.
namespace veggie_loops::three_osc::immediate {
using envelope::Configuration;using envelope::prepareRawCurve;
inline std::int32_t timeTicks(std::int32_t raw,double scale) {
  if (raw<=100) return 0;
  const float normalized=static_cast<float>(static_cast<double>(raw)*0x1p-16);
  const float curve=static_cast<float>(std::exp(static_cast<double>(normalized)*6.90875477931522)-1.0);
  const auto ticks=static_cast<std::uint64_t>(std::rint(static_cast<double>(curve)*scale));
  return std::bit_cast<std::int32_t>(static_cast<std::uint32_t>(ticks));
}
// Valid context: finite tempo in (0,1000], clockSetting in [4,2^20], each time
// raw in [0,65536], sustain in [0,128], curve raws in [-128,128]. These bounds
// keep native signed conversion and +1 denominators defined. Table pointers
// are copied only; subsequent step() needs 16384 readable samples in the choice.
inline void prepareConfiguration(Configuration& cfg,double tempo,std::uint32_t clockSetting,
                                  const std::array<const float*,3>& tables) {
  const double base=((static_cast<double>(clockSetting>>2)/48.0)*24576.0)/1000.0;
  const double scale=(cfg.raw[0]&1)!=0 ? base : (base*tempo)/120.0;
  const double lfoScale=(cfg.raw[0]&2)!=0 ? base : (base*tempo)/120.0;
  cfg.delayTicks=timeTicks(cfg.raw[2],scale);
  cfg.attackStep=static_cast<float>(1.0/(static_cast<double>(timeTicks(cfg.raw[3],scale))+1.0));
  cfg.sustain=static_cast<float>(cfg.raw[6])*0.0078125f;
  cfg.holdTicks=timeTicks(cfg.raw[4],scale);
  cfg.decayStep=static_cast<float>(-1.0/(static_cast<double>(timeTicks(cfg.raw[5],scale))+1.0));
  cfg.releaseStep=static_cast<float>(-1.0/(static_cast<double>(timeTicks(cfg.raw[7],scale))+1.0));
  cfg.envelopeDepth=static_cast<float>(cfg.raw[8])*0.0078125f;
  prepareRawCurve(cfg.attack,cfg.raw[14]);prepareRawCurve(cfg.decay,cfg.raw[15]);prepareRawCurve(cfg.release,cfg.raw[16]);
  cfg.lfoDelayTicks=timeTicks(cfg.raw[9],lfoScale);
  cfg.lfoAttackStep=static_cast<float>(1.0/(static_cast<double>(timeTicks(cfg.raw[10],lfoScale))+1.0));
  const std::int32_t period=timeTicks(cfg.raw[12],lfoScale);
  cfg.lfoPhaseIncrement=static_cast<std::uint32_t>(0x100000000ull/static_cast<std::uint64_t>(period<4 ? 3 : period));
  cfg.lfoDepth=static_cast<float>(cfg.raw[11])*0.0078125f;
  const auto waveform=cfg.raw[13]<1 ? 0 : cfg.raw[13]>2 ? 2 : cfg.raw[13];
  cfg.lfoTable=tables[waveform];
}
}

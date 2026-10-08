#include "three_osc_wrapper_core.h"
#include "three_osc.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <memory>
#include <vector>

using veggie_loops::three_osc::OscState;
using veggie_loops::three_osc::RenderArguments;
extern "C" uintptr_t dispatch(OscState*, int32_t, intptr_t);

struct vl_osc_voice {
  intptr_t tag;
  std::array<uint32_t, 6> phases{};
  bool stereo = false, released = false;
};
struct vl_osc_core {
  vl_osc_compute_lr compute;
  void* context;
  std::array<int32_t, 21> parameters{};
  std::array<std::array<int32_t,17>,5> editor{};
  std::array<int32_t,3> globals{256,0,0};
  std::array<uint8_t, 4> switches{};
  std::array<vl_osc_derived, 3> derived{};
  uint32_t ring = UINT32_MAX, random_range = 0;
  bool stereo = false, custom = false, hq = true, average = false;
  std::array<const float*,6> host_tables{};
  std::array<float,16384> custom_samples{};
  float phase_scaler = 0;
  OscState* engine = nullptr;
  std::vector<std::unique_ptr<vl_osc_voice>> voices;
  ~vl_osc_core() { if (engine) dispatch(engine,1,0); }
};
namespace {
vl_osc_random_state randomGlobals = [] {
  vl_osc_random_state result{}; result.index=625; result.previous_seed=UINT32_MAX; return result;
}();
constexpr std::array<int,21> minimums{-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0,-64,0,-24,-100,-64,-50,0};
constexpr std::array<int,21> maximums{64,6,24,100,64,50,128,64,6,24,100,64,50,128,64,6,24,100,64,50,64};
constexpr std::array<int,17> editorMinimums{0,0,100,100,100,100,0,100,-128,100,100,-128,200,0,-128,-128,-128};
constexpr std::array<int,17> editorMaximums{255,1,65536,65536,65536,65536,128,65536,128,65536,65536,128,65536,2,128,128,128};
constexpr std::array<int,5> depthRanges{64,128,128,128,2400};
int* editorValue(vl_osc_core& core,int index) {
  if (index>=23 && index<108) return &core.editor[(index-23)/17][(index-23)%17];
  if (index==110) return &core.globals[0];
  if (index==111) return &core.globals[1];
  if (index==113) return &core.globals[2];
  return nullptr;
}
bool editorRange(int index,int& minimum,int& maximum) {
  if (index>=23 && index<108) {
    const int group=(index-23)/17,column=(index-23)%17;
    if (column==0) return false; // Flag word has no native normalization control.
    minimum=editorMinimums[column];maximum=editorMaximums[column];
    if (column==8 || column==11) {maximum=depthRanges[group];minimum=-maximum;}
    return true;
  }
  if (index==110 || index==111) {minimum=0;maximum=256;return true;}
  if (index==113) {minimum=0;maximum=7;return true;}
  return false;
}
uint32_t nextRandom(vl_osc_random_state& state) {
  const uint32_t current = state.index++;
  uint32_t index = current;
  if (state.seed != state.previous_seed || current > 624) {
    state.words[0] = state.seed;
    for (uint32_t i = 1; i < 624; ++i)
      state.words[i] = i + (state.words[i-1] ^ (state.words[i-1] >> 30)) * 1812433253u;
    state.seed = state.previous_seed = ~state.seed;
    index = 624;
  }
  if (index == 624) {
    for (uint32_t i = 0; i < 624; ++i) {
      const uint32_t joined = (state.words[i] & 0x80000000u) |
                              (state.words[(i + 1) % 624] & 0x7fffffffu);
      state.words[i] = state.words[(i + 397) % 624] ^ (joined >> 1) ^
                        ((joined & 1) ? 0x9908b0dfu : 0u);
    }
    state.index = 1; index = 0;
  }
  uint32_t result = state.words[index];
  result ^= result >> 11; result ^= (result << 7) & 0x9d2c5680u;
  result ^= (result << 15) & 0xefc60000u; return result ^ (result >> 18);
}
uint32_t randomBelow(uint32_t maximum) {
  return static_cast<uint32_t>((uint64_t(maximum) * nextRandom(randomGlobals)) >> 32);
}
void update(vl_osc_core& core) {
  const float third = static_cast<float>(core.parameters[13]) * 0.0078125f;
  const float remaining = core.switches[3] == 0 ? 1.0f - third : 1.0f;
  const float second = (remaining * static_cast<float>(core.parameters[6])) * 0.0078125f;
  const std::array<float,3> volumes{remaining - second, second, third};
  core.stereo = core.parameters[20] != 0;
  core.random_range = static_cast<uint32_t>(core.parameters[20]) << 18;
  constexpr std::array<uint32_t,3> ring{UINT32_MAX,2,0};
  core.ring = ring[core.switches[3]];
  for (int i = 0; i < 3; ++i) {
    auto& item = core.derived[i]; const int base = i * 7;
    item.pitch = core.parameters[base + 2] * 100 + core.parameters[base + 3];
    item.volume = core.switches[i] ? -volumes[i] : volumes[i];
    core.compute(core.context, &item.left_gain, &item.right_gain,
                 static_cast<float>(core.parameters[base]) * 0.015625f, item.volume);
    item.phase_offset = static_cast<uint32_t>(core.parameters[base + 4]) * 0x1ffffffu;
    item.stereo_fine = core.parameters[base + 5];
    const int waveform = core.parameters[base + 1];
    item.noise = waveform == 5;
    item.non_sine = waveform != 0 && waveform != 5;
    core.stereo |= item.noise || item.phase_offset != 0 || item.stereo_fine != 0 || core.parameters[base] != 0;
  }
}
bool owns(const vl_osc_core& core, const vl_osc_voice* voice) {
  return std::any_of(core.voices.begin(), core.voices.end(), [voice](const auto& entry){return entry.get() == voice;});
}
uint32_t phaseIncrement(const vl_osc_core& core, float pitch) {
  // Native float pitch sum, then system exp in double, then FRINTX.
  return static_cast<uint32_t>(static_cast<uint64_t>(std::nearbyint(
    static_cast<double>(core.phase_scaler) * std::exp(static_cast<double>(pitch) * 0.00057762265046662107))));
}
uint32_t legacyRender(const float* table,float* buffer,uint32_t frames,float gain,
                      uint32_t phase,uint32_t increment,int command) {
  for (uint32_t i=0;i<frames;++i) {
    const float sample=table[phase>>18]*gain;
    if (command==11) buffer[2*i]=sample;
    else if (command==12) buffer[2*i]=buffer[2*i]-(buffer[2*i]*sample);
    else buffer[2*i]=buffer[2*i]+sample;
    phase+=increment;
  }
  return phase;
}
}
extern "C" vl_osc_core* vl_osc_core_create(vl_osc_compute_lr compute, void* context) {
  if (!compute) return nullptr;
  try {
    auto result = std::make_unique<vl_osc_core>(); result->compute = compute; result->context = context;
    result->engine = reinterpret_cast<OscState*>(dispatch(nullptr,0,0));
    if (!result->engine) return nullptr;
    for (auto& group:result->editor) group={0,0,100,20000,20000,30000,50,20000,0,100,20000,0,32950,0,0,0,0};
    result->editor[1][0]=4;result->editor[1][16]=-101;
    update(*result); vl_osc_core_set_sample_rate(result.get(),44100); return result.release();
  } catch (...) { return nullptr; }
}
extern "C" void vl_osc_core_destroy(vl_osc_core* core) {
  delete core;
}
extern "C" int vl_osc_core_set_sample_rate(vl_osc_core* core, int32_t rate) {
  if (!core || rate < 1 || rate > 1000000) return 0;
  core->phase_scaler = static_cast<float>(2247346493527.166 / static_cast<double>(rate));
  dispatch(core->engine,2,rate); return 1;
}
extern "C" int32_t vl_osc_core_parameter(vl_osc_core* core, int32_t index, int32_t value, uint32_t flags) {
  if (!core || index < 0 || index >= 114) return 0;
  if ((flags & 32) && (value < 0 || value > 1073741824)) return 0;
  if (index>=21) {
    int* stored=editorValue(*core,index);int minimum,maximum;
    if ((flags & 32) && editorRange(index,minimum,maximum))
      value=static_cast<int32_t>(std::nearbyint(static_cast<double>(value)*0x1p-30*(maximum-minimum)))+minimum;
    if (stored) {if (flags & 1) *stored=value;else if (flags & 2) value=*stored;}
    return value;
  }
  if (flags & 32) value = static_cast<int32_t>(std::nearbyint(static_cast<double>(value) * 0x1p-30 *
                          (maximums[index] - minimums[index]))) + minimums[index];
  if (flags & 1) {
    if (value < minimums[index] || value > maximums[index]) return 0;
    core->parameters[index] = value; update(*core);
  }
  else if (flags & 2) value = core->parameters[index];
  return value;
}
extern "C" void vl_osc_core_derived(const vl_osc_core* core, vl_osc_derived result[3], uint32_t* ring, uint8_t* stereo) {
  if (!core) return;
  std::copy(core->derived.begin(), core->derived.end(), result); *ring = core->ring; *stereo = core->stereo;
}
extern "C" int vl_osc_core_restore_prefix(vl_osc_core* core, const uint8_t* prefix, size_t length) {
  if (!core || !prefix || length != 89 || prefix[87] > 2) return 0;
  std::array<int32_t,21> parameters; std::memcpy(parameters.data(),prefix,84);
  for (int i = 0; i < 21; ++i) if (parameters[i] < minimums[i] || parameters[i] > maximums[i]) return 0;
  core->parameters = parameters; std::copy_n(prefix+84,4,core->switches.begin()); core->hq = (prefix[88] & 1) != 0;
  update(*core); return 1;
}
extern "C" int vl_osc_core_save_prefix(const vl_osc_core* core, uint8_t* prefix, size_t length) {
  if (!core || !prefix || length != 89) return 0;
  std::memcpy(prefix,core->parameters.data(),84); std::copy(core->switches.begin(),core->switches.end(),prefix+84);
  prefix[88] = core->hq; return 1;
}
extern "C" int vl_osc_core_restore_payload(vl_osc_core* core,const uint8_t* payload,size_t length) {
  if (!core || !payload || length!=456 || !vl_osc_core_restore_prefix(core,payload,89)) return 0;
  for (int i=0;i<5;++i) std::memcpy(core->editor[i].data(),payload+92+i*68,68);
  std::memcpy(&core->globals[0],payload+440,4);std::memcpy(&core->globals[1],payload+444,4);std::memcpy(&core->globals[2],payload+452,4);
  return 1;
}
extern "C" int vl_osc_core_save_payload(const vl_osc_core* core,uint8_t* payload,size_t length) {
  if (!core || !payload || length!=456) return 0;
  std::memset(payload,0,456);vl_osc_core_save_prefix(core,payload,89);
  for (int i=0;i<5;++i) std::memcpy(payload+92+i*68,core->editor[i].data(),68);
  std::memcpy(payload+440,&core->globals[0],4);std::memcpy(payload+444,&core->globals[1],4);std::memcpy(payload+452,&core->globals[2],4);
  return 1;
}
extern "C" int vl_osc_core_host_tables(vl_osc_core* core,const float* const tables[6]) {
  if (!core || !tables) return 0;
  for (int i=0;i<6;++i) if (!tables[i]) return 0;
  std::copy_n(tables,6,core->host_tables.begin());return 1;
}
extern "C" void vl_osc_core_render_mode(vl_osc_core* core,uint32_t flags) {if (core) core->average=(flags&2)!=0;}
extern "C" void vl_osc_core_custom_wave(vl_osc_core* core, const float* waveform) {
  if (!core) return; core->custom = waveform != nullptr;
  if (waveform) {std::copy_n(waveform,16384,core->custom_samples.begin());dispatch(core->engine,3,reinterpret_cast<intptr_t>(waveform));}
}
extern "C" int vl_osc_core_random_state(vl_osc_core* core, const vl_osc_random_state* state) {
  if (!core || !state || state->index > 624 || state->seed != state->previous_seed) return 0;
  randomGlobals = *state; return 1;
}
extern "C" vl_osc_voice* vl_osc_core_trigger(vl_osc_core* core, intptr_t tag) {
  if (!core) return nullptr;
  try {
    auto voice = std::make_unique<vl_osc_voice>(); voice->tag = tag; voice->stereo = core->stereo;
    for (int i=0;i<3;++i) voice->phases[2*i+1]=core->derived[i].phase_offset;
    auto* result=voice.get(); core->voices.push_back(std::move(voice));
    // Allocate/insert before consuming RNG so allocation failures are atomic.
    for (int i=0;i<3;++i) if (core->random_range) for (int lane=0;lane<2;++lane)
      result->phases[2*i+lane]+=(randomBelow(core->random_range)-core->random_range/2)*256u;
    return result;
  } catch (...) { return nullptr; }
}
extern "C" void vl_osc_core_release(vl_osc_core* core, vl_osc_voice* voice) {
  if (core && owns(*core,voice)) voice->released = true;
}
extern "C" void vl_osc_core_kill(vl_osc_core* core, vl_osc_voice* voice) {
  if (!core) return;
  std::erase_if(core->voices,[voice](const auto& item){return item.get() == voice;});
}
extern "C" int vl_osc_core_render(vl_osc_core* core, vl_osc_voice* voice, float pitch, float* buffer, uint32_t frames) {
  if (!core || !owns(*core,voice) || !std::isfinite(pitch) || !buffer || frames > (1u<<20)) return 0;
  if (!core->hq && std::any_of(core->host_tables.begin(),core->host_tables.end(),[](const float* table){return table==nullptr;})) return 0;
  // The native FCVTZS saturates on invalid/overflowing inputs. The bounded
  // API rejects them before advancing any voice or random state instead.
  for (const auto& item : core->derived) if (!item.noise) for (int lane=0;lane<2;++lane) {
    const float cents=(pitch+static_cast<float>(item.pitch))+(lane ? static_cast<float>(item.stereo_fine) : 0.0f);
    const double step=std::nearbyint(static_cast<double>(core->phase_scaler)*
      std::exp(static_cast<double>(cents)*0.00057762265046662107));
    if (!(step >= 0 && step < 0x1p63)) return 0;
  }
  voice->stereo |= core->stereo;
  const int lanes = voice->stereo ? 2 : 1;
  for (int lane = 0; lane < lanes; ++lane) {
    bool first = true;
    for (int i = 0; i < 3; ++i) {
      const auto& item = core->derived[i];
      const float cents = lane == 0 ? pitch + static_cast<float>(item.pitch) :
                         (pitch + static_cast<float>(item.pitch)) + static_cast<float>(item.stereo_fine);
      const uint32_t increment = item.noise ? randomBelow(0x99326u) + 0x99326u : phaseIncrement(*core,cents);
      auto& phase = voice->phases[2*i+lane];
      if (item.volume == 0) { phase += increment * frames; continue; }
      int waveform = core->parameters[i*7+1]; if (waveform > 5 && !core->custom) waveform = 3;
      RenderArguments args{waveform,buffer+lane,frames,phase,increment,lane == 0 ? item.left_gain : item.right_gain};
      const int command = core->ring == static_cast<uint32_t>(i) ? 12 : first ? 11 : 10;
      if (core->hq) phase=static_cast<uint32_t>(dispatch(core->engine,command,reinterpret_cast<intptr_t>(&args)));
      else {
        const float* table=waveform==6 ? core->custom_samples.data() : core->host_tables[waveform];
        const uint32_t initialPhase=phase;
        const uint32_t copies=core->average && item.non_sine && command!=12 ? std::max(1u,increment>>22) : 1u;
        const float gain=args.gain/static_cast<float>(copies);
        phase=legacyRender(table,buffer+lane,frames,gain,phase,increment,command);
        const int32_t spread=std::bit_cast<int32_t>(increment)/static_cast<int32_t>(copies);
        for (uint32_t copy=1;copy<copies;++copy)
          legacyRender(table,buffer+lane,frames,gain,initialPhase+uint32_t(spread)*copy,increment,10);
      }
      if (command != 12) first = false;
    }
  }
  if (!voice->stereo) {
    for (int i = 0; i < 3; ++i) voice->phases[2*i+1] = voice->phases[2*i];
    for (uint32_t i = 0; i < frames; ++i) buffer[2*i+1] = buffer[2*i];
  }
  return 1;
}
extern "C" void vl_osc_core_voice_phases(const vl_osc_voice* voice, uint32_t phases[6], uint8_t* stereo) {
  if (voice) { std::copy(voice->phases.begin(),voice->phases.end(),phases); *stereo = voice->stereo; }
}
extern "C" size_t vl_osc_core_voice_count(const vl_osc_core* core) { return core ? core->voices.size() : 0; }
